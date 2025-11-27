const std = @import("std");
const config = @import("config");
const graphql = @import("graphql");
const printer = @import("printer");
const common = @import("common");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    allocator: Allocator,
    config: *config.Config,
    args: [][]const u8,
    json_output: bool,
};

const Options = struct {
    team: ?[]const u8 = null,
    state: ?[]const u8 = null,
    limit: usize = 25,
    cursor: ?[]const u8 = null,
    pages: ?usize = null,
    all: bool = false,
    help: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("issues list: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "issues") catch {
        return 1;
    };

    const team_value = opts.team orelse ctx.config.default_team_id;
    if (team_value.len == 0) {
        try stderr.print("issues list: missing team selection\n", .{});
        return 1;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    const query =
        \\query Issues($filter: IssueFilter, $first: Int!, $after: String) {
        \\  issues(filter: $filter, first: $first, after: $after) {
        \\    nodes {
        \\      id
        \\      identifier
        \\      title
        \\      state { name type }
        \\      assignee { name }
        \\      priorityLabel
        \\      updatedAt
        \\      url
        \\    }
        \\    pageInfo {
        \\      hasNextPage
        \\      endCursor
        \\    }
        \\  }
        \\}
    ;

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();

    const page_limit: ?usize = if (opts.all) null else opts.pages orelse 1;
    var remaining = opts.limit;
    var next_cursor = opts.cursor;

    var responses = std.ArrayList(graphql.GraphqlClient.Response).init(ctx.allocator);
    defer {
        for (responses.items) |*resp| resp.deinit();
        responses.deinit();
    }

    var rows = std.ArrayList(printer.IssueRow){};
    defer rows.deinit(ctx.allocator);

    var nodes_accumulator = std.ArrayList(std.json.Value).init(ctx.allocator);
    defer nodes_accumulator.deinit();

    var total_fetched: usize = 0;
    var page_count: usize = 0;
    var more_available = false;
    var last_end_cursor: ?[]const u8 = null;

    while (remaining > 0) {
        if (page_limit) |limit_pages| {
            if (page_count >= limit_pages) break;
        }

        const page_size = remaining;
        const variables = buildVariables(
            var_alloc,
            team_value,
            opts.state,
            ctx.config.default_state_filter,
            page_size,
            next_cursor,
        ) catch |err| {
            try stderr.print("issues list: {s}\n", .{@errorName(err)});
            return 1;
        };

        var response = common.send("issues", &client, ctx.allocator, .{
            .query = query,
            .variables = variables,
            .operation_name = "Issues",
        }, stderr) catch {
            return 1;
        };
        var response_owned = true;
        errdefer if (response_owned) response.deinit();

        common.checkResponse("issues", &response, stderr, api_key) catch {
            return 1;
        };

        try responses.append(response);
        response_owned = false;
        const resp = &responses.items[responses.items.len - 1];

        const data_value = resp.data() orelse {
            try stderr.print("issues list: response missing data\n", .{});
            return 1;
        };

        const issues_obj = common.getObjectField(data_value, "issues") orelse {
            try stderr.print("issues list: issues not found in response\n", .{});
            return 1;
        };
        const nodes_array = common.getArrayField(issues_obj, "nodes") orelse {
            try stderr.print("issues list: nodes missing in response\n", .{});
            return 1;
        };

        const take_count = @min(nodes_array.items.len, remaining);
        const page_nodes = nodes_array.items[0..take_count];

        total_fetched += take_count;
        page_count += 1;
        remaining -= take_count;

        if (ctx.json_output) {
            try nodes_accumulator.appendSlice(page_nodes);
        } else {
            for (page_nodes) |node| {
                if (node != .object) continue;

                const identifier = common.getStringField(node, "identifier") orelse continue;
                const title = common.getStringField(node, "title") orelse "";
                const state_obj = common.getObjectField(node, "state");
                const state_name = if (state_obj) |st| common.getStringField(st, "name") else null;
                const state_type = if (state_obj) |st| common.getStringField(st, "type") else null;
                const state_value = state_name orelse state_type orelse "";
                const assignee_obj = common.getObjectField(node, "assignee");
                const assignee_name = if (assignee_obj) |assignee| common.getStringField(assignee, "name") else null;
                const assignee_value = assignee_name orelse "(unassigned)";
                const priority = common.getStringField(node, "priorityLabel") orelse "";
                const updated = common.getStringField(node, "updatedAt") orelse "";

                try rows.append(ctx.allocator, .{
                    .identifier = identifier,
                    .title = title,
                    .state = state_value,
                    .assignee = assignee_value,
                    .priority = priority,
                    .updated = updated,
                });
            }
        }

        const page_info = common.getObjectField(issues_obj, "pageInfo");
        const has_next = if (page_info) |pi| common.getBoolField(pi, "hasNextPage") orelse false else false;
        last_end_cursor = if (page_info) |pi| common.getStringField(pi, "endCursor") else null;
        more_available = has_next;

        if (take_count == 0) {
            if (has_next) {
                try stderr.print("issues list: received empty page; stopping pagination\n", .{});
            }
            break;
        }

        if (!has_next) break;
        if (remaining == 0) break;
        if (page_limit) |limit_pages| {
            if (page_count >= limit_pages) break;
        }
        if (last_end_cursor == null) {
            try stderr.print("issues list: missing endCursor for additional page\n", .{});
            break;
        }
        next_cursor = last_end_cursor;
    }

    if (ctx.json_output) {
        var nodes_value = std.json.Value{ .array = std.json.Array.init(ctx.allocator) };
        try nodes_value.array.appendSlice(nodes_accumulator.items);

        var page_info_obj = std.json.Value{ .object = std.json.ObjectMap.init(ctx.allocator) };
        try page_info_obj.object.put("hasNextPage", .{ .bool = more_available });
        if (last_end_cursor) |cursor_value| {
            try page_info_obj.object.put("endCursor", .{ .string = cursor_value });
        }

        var issues_obj = std.json.Value{ .object = std.json.ObjectMap.init(ctx.allocator) };
        try issues_obj.object.put("nodes", nodes_value);
        try issues_obj.object.put("pageInfo", page_info_obj);

        var root_obj = std.json.Value{ .object = std.json.ObjectMap.init(ctx.allocator) };
        try root_obj.object.put("issues", issues_obj);

        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(root_obj, &out_writer.interface, true);
    } else {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printIssueTable(ctx.allocator, &out_writer.interface, rows.items);
    }

    const summary_suffix = if (more_available) " (more available)" else "";
    try stderr.print("issues list: fetched {d} issue(s) across {d} page(s){s}\n", .{ total_fetched, page_count, summary_suffix });

    return 0;
}

fn buildVariables(
    allocator: Allocator,
    team: []const u8,
    state_override: ?[]const u8,
    default_state_filter: []const []const u8,
    page_size: usize,
    cursor: ?[]const u8,
) !std.json.Value {
    const page_size_i64 = std.math.cast(i64, page_size) orelse return error.InvalidLimit;

    var vars = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try vars.object.put("first", .{ .integer = page_size_i64 });

    var filter = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    var team_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    var eq_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try eq_obj.object.put("eq", .{ .string = team });
    if (isUuid(team)) {
        try team_obj.object.put("id", eq_obj);
    } else {
        try team_obj.object.put("key", eq_obj);
    }
    try filter.object.put("team", team_obj);

    var state_values = std.json.Array.init(allocator);
    if (state_override) |override_value| {
        var iter = std.mem.tokenizeScalar(u8, override_value, ',');
        var added: usize = 0;
        while (iter.next()) |entry| {
            const trimmed = std.mem.trim(u8, entry, " \t");
            if (trimmed.len == 0) continue;
            try state_values.append(.{ .string = trimmed });
            added += 1;
        }
        if (added == 0) return error.InvalidStateFilter;
    } else {
        for (default_state_filter) |entry| {
            try state_values.append(.{ .string = entry });
        }
    }

    var state_type_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    const states_value = std.json.Value{ .array = state_values };
    if (state_override) |_| {
        try state_type_obj.object.put("in", states_value);
    } else {
        try state_type_obj.object.put("nin", states_value);
    }

    var state_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try state_obj.object.put("type", state_type_obj);
    try filter.object.put("state", state_obj);

    try vars.object.put("filter", filter);
    if (cursor) |cursor_value| try vars.object.put("after", .{ .string = cursor_value });
    return vars;
}

fn isUuid(value: []const u8) bool {
    if (value.len != 36) return false;
    const dash_positions = [_]usize{ 8, 13, 18, 23 };
    for (dash_positions) |idx| {
        if (value[idx] != '-') return false;
    }
    return true;
}

pub fn parseOptions(args: []const []const u8) !Options {
    var opts = Options{};
    var idx: usize = 0;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--team")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.team = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--team=")) {
            opts.team = arg["--team=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--state")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.state = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--state=")) {
            opts.state = arg["--state=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--limit")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.limit = try std.fmt.parseInt(usize, args[idx + 1], 10);
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--limit=")) {
            opts.limit = try std.fmt.parseInt(usize, arg["--limit=".len..], 10);
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--cursor")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.cursor = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--cursor=")) {
            opts.cursor = arg["--cursor=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--pages")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            const value = try std.fmt.parseInt(usize, args[idx + 1], 10);
            if (value == 0) return error.InvalidPageCount;
            opts.pages = value;
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--pages=")) {
            const value = try std.fmt.parseInt(usize, arg["--pages=".len..], 10);
            if (value == 0) return error.InvalidPageCount;
            opts.pages = value;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--all")) {
            opts.all = true;
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    if (opts.all and opts.pages != null) return error.ConflictingPageFlags;
    return opts;
}

fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issues list [--team ID|KEY] [--state STATE[,STATE...]] [--limit N] [--cursor CURSOR] [--pages N|--all] [--help]
        \\Flags:
        \\  --team ID|KEY       Team id or key (default: config.default_team_id)
        \\  --state VALUES      Comma-separated state types to include (default: exclude completed,canceled)
        \\  --limit N           Max issues to fetch (default: 25)
        \\  --cursor CURSOR     Start pagination after the provided cursor
        \\  --pages N           Fetch up to N pages (default: 1; stops early at limit)
        \\  --all               Fetch all pages until the end or the limit
        \\  --help              Show this help message
        \\
    , .{});
}
