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
    identifier: ?[]const u8 = null,
    help: bool = false,
    quiet: bool = false,
    data_only: bool = false,
};

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

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("id", .{ .string = target });

    const query =
        \\query IssueView($id: String!) {
        \\  issue(id: $id) {
        \\    id
        \\    identifier
        \\    title
        \\    description
        \\    state { name type }
        \\    assignee { name }
        \\    priorityLabel
        \\    url
        \\    createdAt
        \\    updatedAt
        \\  }
        \\}
    ;

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();

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

    if (ctx.json_output and !opts.quiet and !opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

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
    const created = common.getStringField(node, "createdAt") orelse "";
    const updated = common.getStringField(node, "updatedAt") orelse "";
    const description = common.getStringField(node, "description");

    const pairs = [_]printer.KeyValue{
        .{ .key = "Identifier", .value = identifier },
        .{ .key = "Title", .value = title },
        .{ .key = "State", .value = state_value },
        .{ .key = "Assignee", .value = assignee_value },
        .{ .key = "Priority", .value = priority },
        .{ .key = "URL", .value = url },
        .{ .key = "Created", .value = created },
        .{ .key = "Updated", .value = updated },
    };
    const data_pairs = [_]printer.KeyValue{
        .{ .key = "identifier", .value = identifier },
        .{ .key = "title", .value = title },
        .{ .key = "state", .value = state_value },
        .{ .key = "assignee", .value = assignee_value },
        .{ .key = "priority", .value = priority },
        .{ .key = "url", .value = url },
        .{ .key = "created_at", .value = created },
        .{ .key = "updated_at", .value = updated },
    };

    var stdout_buf: [0]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stdout_iface = &stdout_writer.interface;

    if (opts.quiet) {
        try stdout_iface.writeAll(identifier);
        try stdout_iface.writeByte('\n');
        return 0;
    }

    if (opts.data_only) {
        if (ctx.json_output) {
            var data_obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            for (data_pairs) |pair| {
                try data_obj.object.put(pair.key, .{ .string = pair.value });
            }
            if (description) |desc| {
                if (desc.len > 0) {
                    try data_obj.object.put("description", .{ .string = desc });
                }
            }
            try printer.printJson(data_obj, stdout_iface, true);
            return 0;
        }

        try printer.printKeyValuesPlain(stdout_iface, data_pairs[0..]);
        if (description) |desc| {
            if (desc.len > 0) {
                const desc_pair = [_]printer.KeyValue{
                    .{ .key = "description", .value = desc },
                };
                try printer.printKeyValuesPlain(stdout_iface, desc_pair[0..]);
            }
        }
        return 0;
    }

    try printer.printKeyValues(stdout_iface, pairs[0..]);
    if (description) |desc| {
        if (desc.len > 0) {
            try stdout_iface.writeByte('\n');
            try stdout_iface.writeAll("Description:\n");
            try stdout_iface.writeAll(desc);
            try stdout_iface.writeByte('\n');
        }
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

fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issue view <ID|IDENTIFIER> [--quiet] [--data-only] [--help]
        \\Flags:
        \\  --quiet        Print only the identifier
        \\  --data-only    Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --help         Show this help message
        \\
    , .{});
}
