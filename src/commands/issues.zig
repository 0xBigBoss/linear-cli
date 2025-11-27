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
    retries: u8,
    timeout_ms: u32,
};

const SortField = enum {
    created,
    updated,
};

const SortDirection = enum {
    asc,
    desc,
};

const Sort = struct {
    field: SortField,
    direction: SortDirection,
};

const Options = struct {
    team: ?[]const u8 = null,
    state_type: ?[]const u8 = null,
    state_id: ?[]const u8 = null,
    assignee: ?[]const u8 = null,
    label: ?[]const u8 = null,
    updated_since: ?[]const u8 = null,
    sort: ?Sort = null,
    limit: usize = 25,
    cursor: ?[]const u8 = null,
    pages: ?usize = null,
    all: bool = false,
    fields: ?[]const u8 = null,
    plain: bool = false,
    no_truncate: bool = false,
    human_time: bool = false,
    quiet: bool = false,
    data_only: bool = false,
    help: bool = false,
};

const DataRow = struct {
    identifier: []const u8,
    title: []const u8,
    state: []const u8,
    assignee: []const u8,
    priority: []const u8,
    updated_raw: []const u8,
    url: []const u8,
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

    var field_buf = std.BoundedArray(printer.IssueField, printer.issue_field_count){};
    const selected_fields = parseIssueFields(opts.fields, &field_buf) catch |err| {
        try stderr.print("issues list: {s}\n", .{@errorName(err)});
        return 1;
    };
    const disable_trunc = opts.plain or opts.no_truncate;
    const table_opts = printer.TableOptions{
        .pad = !disable_trunc,
        .truncate = !disable_trunc,
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
        \\query Issues($filter: IssueFilter, $first: Int!, $after: String, $orderBy: PaginationOrderBy, $sort: [IssueSortInput!]) {
        \\  issues(filter: $filter, first: $first, after: $after, orderBy: $orderBy, sort: $sort) {
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
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;

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

    var data_rows = std.ArrayList(DataRow){};
    defer data_rows.deinit(ctx.allocator);

    var nodes_accumulator = std.ArrayList(std.json.Value).init(ctx.allocator);
    defer nodes_accumulator.deinit();

    var total_fetched: usize = 0;
    var page_count: usize = 0;
    var more_available = false;
    var last_end_cursor: ?[]const u8 = null;
    const want_table = !ctx.json_output and !opts.data_only and !opts.quiet;
    const want_data_rows = opts.data_only or opts.quiet;
    const want_raw_nodes = ctx.json_output and !opts.data_only and !opts.quiet;

    while (remaining > 0) {
        if (page_limit) |limit_pages| {
            if (page_count >= limit_pages) break;
        }

        const page_size = remaining;
        const variables = buildVariables(
            var_alloc,
            team_value,
            opts,
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

        if (want_raw_nodes) {
            try nodes_accumulator.appendSlice(page_nodes);
        }

        if (want_table or want_data_rows) {
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
                const updated_raw = common.getStringField(node, "updatedAt") orelse "";
                const url = common.getStringField(node, "url") orelse "";

                const updated_display = if (opts.human_time and want_table)
                    printer.humanTime(ctx.allocator, updated_raw, null) catch updated_raw
                else
                    updated_raw;

                if (want_table) {
                    try rows.append(ctx.allocator, .{
                        .identifier = identifier,
                        .title = title,
                        .state = state_value,
                        .assignee = assignee_value,
                        .priority = priority,
                        .updated = updated_display,
                    });
                }

                if (want_data_rows) {
                    try data_rows.append(ctx.allocator, .{
                        .identifier = identifier,
                        .title = title,
                        .state = state_value,
                        .assignee = assignee_value,
                        .priority = priority,
                        .updated_raw = updated_raw,
                        .url = url,
                    });
                }
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

    if (opts.quiet) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        for (data_rows.items) |row| {
            try out_writer.interface.writeAll(row.identifier);
            try out_writer.interface.writeByte('\n');
        }
    } else if (opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        if (ctx.json_output) {
            var out_array = std.json.Array.init(ctx.allocator);
            for (data_rows.items) |row| {
                var obj = std.json.Value{ .object = std.json.ObjectMap.init(ctx.allocator) };
                try obj.object.put("identifier", .{ .string = row.identifier });
                try obj.object.put("title", .{ .string = row.title });
                try obj.object.put("state", .{ .string = row.state });
                try obj.object.put("assignee", .{ .string = row.assignee });
                try obj.object.put("priority", .{ .string = row.priority });
                try obj.object.put("updated_at", .{ .string = row.updated_raw });
                try obj.object.put("url", .{ .string = row.url });
                try out_array.append(obj);
            }
            const out_value = std.json.Value{ .array = out_array };
            try printer.printJson(out_value, &out_writer.interface, true);
        } else {
            for (data_rows.items) |row| {
                try out_writer.interface.print(
                    "{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\n",
                    .{ row.identifier, row.title, row.state, row.assignee, row.priority, row.updated_raw, row.url },
                );
            }
        }
    } else if (ctx.json_output) {
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
        try printer.printIssueTable(ctx.allocator, &out_writer.interface, rows.items, selected_fields, table_opts);
    }

    const summary_suffix = if (more_available) " (more available)" else "";
    try stderr.print("issues list: fetched {d} issue(s) across {d} page(s){s}\n", .{ total_fetched, page_count, summary_suffix });

    return 0;
}

fn buildVariables(
    allocator: Allocator,
    team: []const u8,
    opts: Options,
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

    var state_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    const has_state_type = opts.state_type != null;
    const has_state_id = opts.state_id != null;
    if (has_state_type) {
        const state_values = try parseCsvValues(allocator, opts.state_type.?) catch |err| switch (err) {
            error.EmptyList => error.InvalidStateFilter,
            else => err,
        };
        var state_type_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try state_type_obj.object.put("in", .{ .array = state_values });
        try state_obj.object.put("type", state_type_obj);
    } else if (!has_state_id) {
        var state_values = std.json.Array.init(allocator);
        for (default_state_filter) |entry| {
            try state_values.append(.{ .string = entry });
        }
        var state_type_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try state_type_obj.object.put("nin", .{ .array = state_values });
        try state_obj.object.put("type", state_type_obj);
    }

    if (has_state_id) {
        const state_ids = try parseCsvValues(allocator, opts.state_id.?) catch |err| switch (err) {
            error.EmptyList => error.InvalidStateIdFilter,
            else => err,
        };
        var state_id_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try state_id_obj.object.put("in", .{ .array = state_ids });
        try state_obj.object.put("id", state_id_obj);
    }

    try filter.object.put("state", state_obj);

    if (opts.assignee) |assignee_value| {
        const trimmed = std.mem.trim(u8, assignee_value, " \t");
        if (trimmed.len == 0) return error.InvalidAssigneeFilter;

        var id_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try id_obj.object.put("eq", .{ .string = trimmed });

        var assignee_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try assignee_obj.object.put("id", id_obj);
        try filter.object.put("assignee", assignee_obj);
    }

    if (opts.label) |label_value| {
        const label_ids = try parseCsvValues(allocator, label_value) catch |err| switch (err) {
            error.EmptyList => error.InvalidLabelFilter,
            else => err,
        };
        var id_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try id_obj.object.put("in", .{ .array = label_ids });

        var label_filter = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try label_filter.object.put("id", id_obj);

        var labels_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try labels_obj.object.put("some", label_filter);
        try filter.object.put("labels", labels_obj);
    }

    if (opts.updated_since) |updated_value| {
        const trimmed = std.mem.trim(u8, updated_value, " \t");
        if (trimmed.len == 0) return error.InvalidUpdatedSinceFilter;

        var updated_cmp = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try updated_cmp.object.put("gt", .{ .string = trimmed });
        try filter.object.put("updatedAt", updated_cmp);
    }

    try vars.object.put("filter", filter);
    if (cursor) |cursor_value| try vars.object.put("after", .{ .string = cursor_value });
    if (opts.sort) |sort| {
        const field_name = switch (sort.field) {
            .created => "createdAt",
            .updated => "updatedAt",
        };
        const order_value = switch (sort.direction) {
            .asc => "Ascending",
            .desc => "Descending",
        };

        var sort_details = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try sort_details.object.put("order", .{ .string = order_value });

        var sort_entry = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        try sort_entry.object.put(field_name, sort_details);

        var sort_array = std.json.Array.init(allocator);
        try sort_array.append(sort_entry);

        try vars.object.put("orderBy", .{ .string = field_name });
        try vars.object.put("sort", .{ .array = sort_array });
    }
    return vars;
}

fn parseCsvValues(allocator: Allocator, raw: []const u8) !std.json.Array {
    var values = std.json.Array.init(allocator);
    var iter = std.mem.tokenizeScalar(u8, raw, ',');
    var added: usize = 0;
    while (iter.next()) |entry| {
        const trimmed = std.mem.trim(u8, entry, " \t");
        if (trimmed.len == 0) continue;
        try values.append(.{ .string = trimmed });
        added += 1;
    }
    if (added == 0) return error.EmptyList;
    return values;
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
        if (std.mem.eql(u8, arg, "--state") or std.mem.eql(u8, arg, "--state-type")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.state_type = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--state=")) {
            opts.state_type = arg["--state=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--state-type=")) {
            opts.state_type = arg["--state-type=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--state-id")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.state_id = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--state-id=")) {
            opts.state_id = arg["--state-id=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--assignee")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.assignee = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--assignee=")) {
            opts.assignee = arg["--assignee=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--label")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.label = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--label=")) {
            opts.label = arg["--label=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--updated-since")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.updated_since = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--updated-since=")) {
            opts.updated_since = arg["--updated-since=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--sort")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.sort = try parseSort(args[idx + 1]);
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sort=")) {
            opts.sort = try parseSort(arg["--sort=".len..]);
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
        if (std.mem.eql(u8, arg, "--fields")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.fields = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--fields=")) {
            opts.fields = arg["--fields=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--plain")) {
            opts.plain = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-truncate")) {
            opts.no_truncate = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--human-time")) {
            opts.human_time = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--quiet")) {
            opts.quiet = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--data-only")) {
            opts.data_only = true;
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    if (opts.all and opts.pages != null) return error.ConflictingPageFlags;
    return opts;
}

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issues list [--team ID|KEY] [--state-type TYPES] [--state-id IDS] [--assignee USER_ID] [--label IDS] [--updated-since TS] [--sort FIELD[:asc|desc]] [--limit N] [--cursor CURSOR] [--pages N|--all] [--fields LIST] [--plain] [--no-truncate] [--human-time] [--quiet] [--data-only] [--help]
        \\Flags:
        \\  --team ID|KEY         Team id or key (default: config.default_team_id)
        \\  --state-type VALUES   Comma-separated state types to include (alias: --state; default: exclude completed,canceled)
        \\  --state-id IDS        Comma-separated workflow state ids to include (overrides default exclusion)
        \\  --assignee USER_ID    Filter by assignee id
        \\  --label IDS           Comma-separated label ids to include
        \\  --updated-since TS    Only include issues updated after the timestamp
        \\  --sort FIELD[:DIR]    Sort by created|updated (dir asc|desc, default: desc)
        \\  --limit N             Max issues to fetch (default: 25)
        \\  --cursor CURSOR       Start pagination after the provided cursor
        \\  --pages N             Fetch up to N pages (default: 1; stops early at limit)
        \\  --all                 Fetch all pages until the end or the limit
        \\  --fields LIST         Comma-separated columns (identifier,title,state,assignee,priority,updated)
        \\  --plain               Do not pad or truncate table cells
        \\  --no-truncate         Disable ellipsis and padding in table cells
        \\  --human-time          Render timestamps as relative values
        \\  --quiet               Print only identifiers (one per line)
        \\  --data-only           Emit tab-separated rows (or JSON array with --json)
        \\  --help                Show this help message
        \\Examples:
        \\  linear issues list --team ENG --pages 2 --limit 50 --sort updated:desc
        \\  linear issues list --state-type todo,in_progress --label lbl-1,lbl-2 --assignee user-123
        \\
    , .{});
}

fn parseSort(raw: []const u8) !Sort {
    var parts = std.mem.splitScalar(u8, raw, ':');
    const field_raw = parts.next() orelse return error.InvalidSort;
    const field_name = std.mem.trim(u8, field_raw, " \t");
    if (field_name.len == 0) return error.InvalidSort;

    const field = if (std.ascii.eqlIgnoreCase(field_name, "created") or std.ascii.eqlIgnoreCase(field_name, "createdAt"))
        SortField.created
    else if (std.ascii.eqlIgnoreCase(field_name, "updated") or std.ascii.eqlIgnoreCase(field_name, "updatedAt"))
        SortField.updated
    else
        return error.InvalidSort;

    var direction: SortDirection = .desc;
    if (parts.next()) |dir_raw| {
        const dir_value = std.mem.trim(u8, dir_raw, " \t");
        if (dir_value.len == 0) return error.InvalidSort;
        if (std.ascii.eqlIgnoreCase(dir_value, "asc")) {
            direction = .asc;
        } else if (std.ascii.eqlIgnoreCase(dir_value, "desc")) {
            direction = .desc;
        } else {
            return error.InvalidSort;
        }
        if (parts.next()) |_| return error.InvalidSort;
    }

    return Sort{
        .field = field,
        .direction = direction,
    };
}

fn parseIssueFields(raw: ?[]const u8, buffer: *std.BoundedArray(printer.IssueField, printer.issue_field_count)) ![]const printer.IssueField {
    if (raw) |value| {
        var iter = std.mem.tokenizeScalar(u8, value, ',');
        while (iter.next()) |field_raw| {
            const trimmed = std.mem.trim(u8, field_raw, " \t");
            if (trimmed.len == 0) continue;
            const field = parseIssueFieldName(trimmed) orelse return error.InvalidField;
            if (!containsIssueField(buffer.slice(), field)) {
                try buffer.append(field);
            }
        }
        if (buffer.len == 0) return error.InvalidField;
        return buffer.slice();
    }
    return printer.issue_default_fields[0..];
}

fn parseIssueFieldName(name: []const u8) ?printer.IssueField {
    if (std.ascii.eqlIgnoreCase(name, "identifier") or std.ascii.eqlIgnoreCase(name, "id")) return .identifier;
    if (std.ascii.eqlIgnoreCase(name, "title")) return .title;
    if (std.ascii.eqlIgnoreCase(name, "state")) return .state;
    if (std.ascii.eqlIgnoreCase(name, "assignee")) return .assignee;
    if (std.ascii.eqlIgnoreCase(name, "priority")) return .priority;
    if (std.ascii.eqlIgnoreCase(name, "updated") or std.ascii.eqlIgnoreCase(name, "updatedAt")) return .updated;
    return null;
}

fn containsIssueField(haystack: []const printer.IssueField, needle: printer.IssueField) bool {
    for (haystack) |entry| {
        if (entry == needle) return true;
    }
    return false;
}
