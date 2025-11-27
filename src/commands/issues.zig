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

    const variables = buildVariables(var_alloc, team_value, opts.state, ctx.config.default_state_filter, opts.limit) catch |err| {
        try stderr.print("issues list: {s}\n", .{@errorName(err)});
        return 1;
    };

    const query =
        \\query Issues($filter: IssueFilter, $first: Int!) {
        \\  issues(filter: $filter, first: $first) {
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

    var response = common.send("issues", &client, ctx.allocator, .{
        .query = query,
        .variables = variables,
        .operation_name = "Issues",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("issues", &response, stderr) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("issues list: response missing data\n", .{});
        return 1;
    };

    if (ctx.json_output) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const issues_obj = common.getObjectField(data_value, "issues") orelse {
        try stderr.print("issues list: issues not found in response\n", .{});
        return 1;
    };
    const nodes_array = common.getArrayField(issues_obj, "nodes") orelse {
        try stderr.print("issues list: nodes missing in response\n", .{});
        return 1;
    };

    var rows = std.ArrayList(printer.IssueRow){};
    defer rows.deinit(ctx.allocator);

    for (nodes_array.items) |node| {
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

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    try printer.printIssueTable(ctx.allocator, &out_writer.interface, rows.items);

    if (common.getObjectField(issues_obj, "pageInfo")) |page_info| {
        if (page_info == .object) {
            const has_next = page_info.object.get("hasNextPage");
            if (has_next) |flag| {
                if (flag == .bool and flag.bool) {
                    try stderr.print("issues list: additional pages available (pagination not implemented)\n", .{});
                }
            }
        }
    }

    return 0;
}

fn buildVariables(
    allocator: Allocator,
    team: []const u8,
    state_override: ?[]const u8,
    default_state_filter: []const []const u8,
    limit: usize,
) !std.json.Value {
    const limit_i64 = std.math.cast(i64, limit) orelse return error.InvalidLimit;

    var vars = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try vars.object.put("first", .{ .integer = limit_i64 });

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
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    return opts;
}

fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issues list [--team ID|KEY] [--state STATE[,STATE...]] [--limit N] [--help]
        \\Flags:
        \\  --team ID|KEY       Team id or key (default: config.default_team_id)
        \\  --state VALUES      Comma-separated state types to include (default: exclude completed,canceled)
        \\  --limit N           Max issues to fetch (default: 25)
        \\  --help              Show this help message
        \\
    , .{});
}
