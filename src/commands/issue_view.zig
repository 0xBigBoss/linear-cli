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
    endpoint: ?[]const u8 = null,
};

const Options = struct {
    identifier: ?[]const u8 = null,
    help: bool = false,
    quiet: bool = false,
    data_only: bool = false,
    human_time: bool = false,
    fields: ?[]const u8 = null,
    sub_limit: usize = 10,
};

const Field = enum { identifier, title, state, assignee, priority, url, created_at, updated_at, description, project, milestone, parent, sub_issues };
const default_fields = [_]Field{ .identifier, .title, .state, .assignee, .priority, .url, .created_at, .updated_at, .description };

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("issue view: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const target = opts.identifier orelse {
        try stderr.print("issue view: missing identifier or id\n", .{});
        return 1;
    };

    const api_key = common.requireApiKey(ctx.config, null, stderr, "issue view") catch {
        return 1;
    };

    var owned_times = std.ArrayListUnmanaged([]u8){};
    defer {
        for (owned_times.items) |value| ctx.allocator.free(value);
        owned_times.deinit(ctx.allocator);
    }

    var fields_buf = std.ArrayListUnmanaged(Field){};
    defer fields_buf.deinit(ctx.allocator);
    const selected_fields = parseFields(opts.fields, &fields_buf, ctx.allocator) catch |err| {
        const message = switch (err) {
            error.InvalidFieldList => "invalid --fields value",
            else => @errorName(err),
        };
        try stderr.print("issue view: {s}\n", .{message});
        return 1;
    };
    const include_project = containsField(selected_fields, .project);
    const include_milestone = containsField(selected_fields, .milestone);
    const include_parent = containsField(selected_fields, .parent);
    const include_subs = containsField(selected_fields, .sub_issues) and opts.sub_limit > 0;

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("id", .{ .string = target });
    if (include_subs) {
        const sub_limit_i64 = std.math.cast(i64, opts.sub_limit) orelse return error.InvalidLimit;
        try variables.object.put("subLimit", .{ .integer = sub_limit_i64 });
    }

    var query_builder = std.ArrayListUnmanaged(u8){};
    defer query_builder.deinit(ctx.allocator);
    try query_builder.appendSlice(ctx.allocator, "query IssueView($id: String!");
    if (include_subs) try query_builder.appendSlice(ctx.allocator, ", $subLimit: Int!");
    try query_builder.appendSlice(
        ctx.allocator,
        ") {\n  issue(id: $id) {\n    id\n    identifier\n    title\n    description\n    state { name type }\n    assignee { name }\n    priorityLabel\n    url\n    createdAt\n    updatedAt\n",
    );
    if (include_parent) try query_builder.appendSlice(ctx.allocator, "    parent { identifier url }\n");
    if (include_project) try query_builder.appendSlice(ctx.allocator, "    project { name }\n");
    if (include_milestone) try query_builder.appendSlice(ctx.allocator, "    milestone: projectMilestone { title: name }\n");
    if (include_subs) try query_builder.appendSlice(ctx.allocator, "    children(first: $subLimit) { nodes { identifier url } pageInfo { hasNextPage } }\n");
    try query_builder.appendSlice(ctx.allocator, "  }\n}\n");
    const query = query_builder.items;

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;
    if (ctx.endpoint) |ep| client.endpoint = ep;

    var response = common.send("issue view", &client, ctx.allocator, .{
        .query = query,
        .variables = variables,
        .operation_name = "IssueView",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("issue view", &response, stderr, api_key) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("issue view: response missing data\n", .{});
        return 1;
    };

    const node = common.getObjectField(data_value, "issue") orelse {
        try stderr.print("issue view: issue not found\n", .{});
        return 1;
    };

    const identifier = common.getStringField(node, "identifier") orelse "(unknown)";
    const title = common.getStringField(node, "title") orelse "";
    const state_obj = common.getObjectField(node, "state");
    const state_name = if (state_obj) |st| common.getStringField(st, "name") else null;
    const state_type = if (state_obj) |st| common.getStringField(st, "type") else null;
    const state_value = state_name orelse state_type orelse "";
    const assignee_obj = common.getObjectField(node, "assignee");
    const assignee_name = if (assignee_obj) |assignee| common.getStringField(assignee, "name") else null;
    const assignee_value = assignee_name orelse "(unassigned)";
    const priority = common.getStringField(node, "priorityLabel") orelse "";
    const url = common.getStringField(node, "url") orelse "";
    const created_raw = common.getStringField(node, "createdAt") orelse "";
    const updated_raw = common.getStringField(node, "updatedAt") orelse "";
    const parent_obj = if (include_parent) common.getObjectField(node, "parent") else null;
    const parent_identifier = if (parent_obj) |p| common.getStringField(p, "identifier") else null;
    const parent_url = if (parent_obj) |p| common.getStringField(p, "url") else null;
    var sub_display: []const u8 = "";
    var sub_truncated = false;
    if (include_subs) {
        const subs_obj = common.getObjectField(node, "children") orelse common.getObjectField(node, "subIssues");
        if (subs_obj) |subs| {
            if (common.getArrayField(subs, "nodes")) |sub_nodes| {
                var joined = std.ArrayListUnmanaged(u8){};
                defer joined.deinit(ctx.allocator);
                for (sub_nodes.items, 0..) |sub, idx| {
                    if (sub != .object) continue;
                    const sub_ident = common.getStringField(sub, "identifier") orelse continue;
                    if (idx > 0) try joined.appendSlice(ctx.allocator, ", ");
                    try joined.appendSlice(ctx.allocator, sub_ident);
                }
                if (joined.items.len > 0) {
                    const owned = try joined.toOwnedSlice(ctx.allocator);
                    try owned_times.append(ctx.allocator, owned);
                    sub_display = owned;
                }
            }
            if (common.getObjectField(subs, "pageInfo")) |si_page| {
                if (common.getBoolField(si_page, "hasNextPage") orelse false) sub_truncated = true;
            }
        }
    }
    const project_obj = if (include_project) common.getObjectField(node, "project") else null;
    const project_name = if (project_obj) |proj| common.getStringField(proj, "name") else null;
    const milestone_obj = if (include_milestone)
        common.getObjectField(node, "milestone") orelse common.getObjectField(node, "projectMilestone")
    else
        null;
    const milestone_title = if (milestone_obj) |m|
        common.getStringField(m, "title") orelse common.getStringField(m, "name")
    else
        null;
    const created = if (opts.human_time) blk: {
        const formatted = printer.humanTime(ctx.allocator, created_raw, null) catch null;
        if (formatted) |value| {
            try owned_times.append(ctx.allocator, value);
            break :blk value;
        }
        break :blk created_raw;
    } else created_raw;
    const updated = if (opts.human_time) blk: {
        const formatted = printer.humanTime(ctx.allocator, updated_raw, null) catch null;
        if (formatted) |value| {
            try owned_times.append(ctx.allocator, value);
            break :blk value;
        }
        break :blk updated_raw;
    } else updated_raw;
    const description = common.getStringField(node, "description");

    const values = struct {
        identifier: []const u8,
        title: []const u8,
        state: []const u8,
        assignee: []const u8,
        priority: []const u8,
        url: []const u8,
        created: []const u8,
        updated: []const u8,
        description: ?[]const u8,
        project: ?[]const u8,
        milestone: ?[]const u8,
        parent: ?[]const u8,
        parent_url: ?[]const u8,
        sub_issue_identifiers: []const u8,
    }{
        .identifier = identifier,
        .title = title,
        .state = state_value,
        .assignee = assignee_value,
        .priority = priority,
        .url = url,
        .created = created,
        .updated = updated,
        .description = if (description) |desc| if (desc.len > 0) desc else null else null,
        .project = if (include_project) project_name else null,
        .milestone = if (include_milestone) milestone_title else null,
        .parent = if (include_parent) parent_identifier else null,
        .parent_url = if (include_parent) parent_url else null,
        .sub_issue_identifiers = sub_display,
    };

    var display_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer display_pairs.deinit(ctx.allocator);
    var data_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer data_pairs.deinit(ctx.allocator);

    for (selected_fields) |field| {
        switch (field) {
            .identifier => {
                try appendPair(&display_pairs, ctx.allocator, "Identifier", values.identifier);
                try appendPair(&data_pairs, ctx.allocator, "identifier", values.identifier);
            },
            .title => {
                try appendPair(&display_pairs, ctx.allocator, "Title", values.title);
                try appendPair(&data_pairs, ctx.allocator, "title", values.title);
            },
            .state => {
                try appendPair(&display_pairs, ctx.allocator, "State", values.state);
                try appendPair(&data_pairs, ctx.allocator, "state", values.state);
            },
            .assignee => {
                try appendPair(&display_pairs, ctx.allocator, "Assignee", values.assignee);
                try appendPair(&data_pairs, ctx.allocator, "assignee", values.assignee);
            },
            .priority => {
                try appendPair(&display_pairs, ctx.allocator, "Priority", values.priority);
                try appendPair(&data_pairs, ctx.allocator, "priority", values.priority);
            },
            .url => {
                try appendPair(&display_pairs, ctx.allocator, "URL", values.url);
                try appendPair(&data_pairs, ctx.allocator, "url", values.url);
            },
            .created_at => {
                try appendPair(&display_pairs, ctx.allocator, "Created", values.created);
                try appendPair(&data_pairs, ctx.allocator, "created_at", values.created);
            },
            .updated_at => {
                try appendPair(&display_pairs, ctx.allocator, "Updated", values.updated);
                try appendPair(&data_pairs, ctx.allocator, "updated_at", values.updated);
            },
            .description => {
                if (values.description) |desc_value| {
                    try appendPair(&display_pairs, ctx.allocator, "Description", desc_value);
                    try appendPair(&data_pairs, ctx.allocator, "description", desc_value);
                }
            },
            .project => {
                if (values.project) |proj| {
                    try appendPair(&display_pairs, ctx.allocator, "Project", proj);
                    try appendPair(&data_pairs, ctx.allocator, "project", proj);
                }
            },
            .milestone => {
                if (values.milestone) |ms| {
                    try appendPair(&display_pairs, ctx.allocator, "Milestone", ms);
                    try appendPair(&data_pairs, ctx.allocator, "milestone", ms);
                }
            },
            .parent => {
                if (values.parent) |pval| {
                    try appendPair(&display_pairs, ctx.allocator, "Parent", pval);
                    try appendPair(&data_pairs, ctx.allocator, "parent", pval);
                    if (values.parent_url) |purl| try appendPair(&data_pairs, ctx.allocator, "parent_url", purl);
                }
            },
            .sub_issues => {
                if (values.sub_issue_identifiers.len > 0) {
                    try appendPair(&display_pairs, ctx.allocator, "Sub-issues", values.sub_issue_identifiers);
                    try appendPair(&data_pairs, ctx.allocator, "sub_issue_identifiers", values.sub_issue_identifiers);
                }
            },
        }
    }

    var stdout_buf: [0]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stdout_iface = &stdout_writer.interface;

    if (opts.quiet) {
        try stdout_iface.writeAll(identifier);
        try stdout_iface.writeByte('\n');
        if (sub_truncated) {
            try stderr.print("issue view: sub-issues limited to {d}; additional sub-issues omitted\n", .{opts.sub_limit});
        }
        return 0;
    }

    if (opts.data_only) {
        if (ctx.json_output) {
            var data_obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            for (data_pairs.items) |pair| {
                try data_obj.object.put(pair.key, .{ .string = pair.value });
            }
            try printer.printJson(data_obj, stdout_iface, true);
            if (sub_truncated) {
                try stderr.print("issue view: sub-issues limited to {d}; additional sub-issues omitted\n", .{opts.sub_limit});
            }
            return 0;
        }

        try printer.printKeyValuesPlain(stdout_iface, data_pairs.items);
        if (sub_truncated) {
            try stderr.print("issue view: sub-issues limited to {d}; additional sub-issues omitted\n", .{opts.sub_limit});
        }
        return 0;
    }

    if (ctx.json_output) {
        if (opts.fields == null) {
            var out_buf2: [0]u8 = undefined;
            var out_writer = std.fs.File.stdout().writer(&out_buf2);
            try printer.printJson(data_value, &out_writer.interface, true);
        } else {
            var data_obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            for (data_pairs.items) |pair| {
                try data_obj.object.put(pair.key, .{ .string = pair.value });
            }
            try printer.printJson(data_obj, stdout_iface, true);
        }
        if (sub_truncated) {
            try stderr.print("issue view: sub-issues limited to {d}; additional sub-issues omitted\n", .{opts.sub_limit});
        }
        return 0;
    }

    try printer.printKeyValues(stdout_iface, display_pairs.items);

    if (sub_truncated) {
        try stderr.print("issue view: sub-issues limited to {d}; additional sub-issues omitted\n", .{opts.sub_limit});
    }

    return 0;
}

fn parseOptions(args: [][]const u8) !Options {
    var opts = Options{};
    var idx: usize = 0;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
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
        if (std.mem.eql(u8, arg, "--human-time")) {
            opts.human_time = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--sub-limit")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.sub_limit = try std.fmt.parseInt(usize, args[idx + 1], 10);
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sub-limit=")) {
            opts.sub_limit = try std.fmt.parseInt(usize, arg["--sub-limit=".len..], 10);
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        if (opts.identifier == null) {
            opts.identifier = arg;
            idx += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return opts;
}

fn parseFields(raw: ?[]const u8, buffer: *std.ArrayListUnmanaged(Field), allocator: Allocator) ![]const Field {
    if (raw) |value| {
        var iter = std.mem.tokenizeScalar(u8, value, ',');
        while (iter.next()) |field_raw| {
            const trimmed = std.mem.trim(u8, field_raw, " \t");
            if (trimmed.len == 0) continue;
            const field = parseFieldName(trimmed) orelse return error.InvalidFieldList;
            if (!containsField(buffer.items, field)) {
                try buffer.append(allocator, field);
            }
        }
        if (buffer.items.len == 0) return error.InvalidFieldList;
        return buffer.items;
    }
    return default_fields[0..];
}

fn parseFieldName(name: []const u8) ?Field {
    if (std.ascii.eqlIgnoreCase(name, "identifier") or std.ascii.eqlIgnoreCase(name, "id")) return .identifier;
    if (std.ascii.eqlIgnoreCase(name, "title")) return .title;
    if (std.ascii.eqlIgnoreCase(name, "state")) return .state;
    if (std.ascii.eqlIgnoreCase(name, "assignee")) return .assignee;
    if (std.ascii.eqlIgnoreCase(name, "priority")) return .priority;
    if (std.ascii.eqlIgnoreCase(name, "url")) return .url;
    if (std.ascii.eqlIgnoreCase(name, "created") or std.ascii.eqlIgnoreCase(name, "created_at")) return .created_at;
    if (std.ascii.eqlIgnoreCase(name, "updated") or std.ascii.eqlIgnoreCase(name, "updated_at")) return .updated_at;
    if (std.ascii.eqlIgnoreCase(name, "description")) return .description;
    if (std.ascii.eqlIgnoreCase(name, "project")) return .project;
    if (std.ascii.eqlIgnoreCase(name, "milestone")) return .milestone;
    if (std.ascii.eqlIgnoreCase(name, "parent")) return .parent;
    if (std.ascii.eqlIgnoreCase(name, "sub_issues") or std.ascii.eqlIgnoreCase(name, "subIssues")) return .sub_issues;
    return null;
}

fn containsField(haystack: []const Field, needle: Field) bool {
    for (haystack) |entry| {
        if (entry == needle) return true;
    }
    return false;
}

fn appendPair(list: *std.ArrayListUnmanaged(printer.KeyValue), allocator: Allocator, key: []const u8, value: []const u8) !void {
    try list.append(allocator, .{ .key = key, .value = value });
}

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issue view <ID|IDENTIFIER> [--quiet] [--data-only] [--fields LIST] [--human-time] [--sub-limit N] [--help]
        \\Flags:
        \\  --quiet        Print only the identifier
        \\  --data-only    Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --fields LIST  Comma-separated fields (identifier,title,state,assignee,priority,url,created_at,updated_at,description,project,milestone,parent,sub_issues)
        \\  --human-time   Render timestamps as relative values
        \\  --sub-limit N  Sub-issues to fetch when sub_issues field is requested (0 disables; default: 10)
        \\  --help         Show this help message
        \\Examples:
        \\  linear issue view ENG-123
        \\  linear issue view 12345 --data-only --json
        \\
    , .{});
}
