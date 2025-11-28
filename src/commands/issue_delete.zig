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
    target: ?[]const u8 = null,
    quiet: bool = false,
    data_only: bool = false,
    yes: bool = false,
    help: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("issue delete: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const target = opts.target orelse {
        try stderr.print("issue delete: missing identifier or id\n", .{});
        return 1;
    };

    const api_key = common.requireApiKey(ctx.config, null, stderr, "issue delete") catch {
        return 1;
    };

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;
    if (ctx.endpoint) |ep| client.endpoint = ep;

    if (!opts.yes) {
        try stderr.print("issue delete: confirmation required; re-run with --yes to proceed\n", .{});
        return 1;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("id", .{ .string = target });

    const mutation =
        \\mutation IssueDelete($id: String!) {
        \\  issueDelete(id: $id) {
        \\    success
        \\    entity { id identifier }
        \\    lastSyncId
        \\  }
        \\}
    ;

    var response = common.send("issue delete", &client, ctx.allocator, .{
        .query = mutation,
        .variables = variables,
        .operation_name = "IssueDelete",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("issue delete", &response, stderr, api_key) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("issue delete: response missing data\n", .{});
        return 1;
    };

    if (ctx.json_output and !opts.quiet and !opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const payload = common.getObjectField(data_value, "issueDelete") orelse {
        try stderr.print("issue delete: issueDelete missing in response\n", .{});
        return 1;
    };

    const success = common.getBoolField(payload, "success") orelse false;
    const issue_obj = common.getObjectField(payload, "entity");

    if (!success) {
        if (issue_obj) |issue| {
            if (common.getStringField(issue, "identifier")) |identifier| {
                try stderr.print("issue delete: delete failed for {s}\n", .{identifier});
                return 1;
            }
        }
        try stderr.print("issue delete: request failed\n", .{});
        return 1;
    }

    const identifier = if (issue_obj) |issue|
        common.getStringField(issue, "identifier") orelse target
    else
        target;
    const id_value = if (issue_obj) |issue|
        common.getStringField(issue, "id") orelse "(unknown)"
    else
        "(unknown)";

    const pairs = [_]printer.KeyValue{
        .{ .key = "Identifier", .value = identifier },
        .{ .key = "ID", .value = id_value },
    };
    const data_pairs = [_]printer.KeyValue{
        .{ .key = "identifier", .value = identifier },
        .{ .key = "id", .value = id_value },
    };

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    var stdout_iface = &out_writer.interface;

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
            try printer.printJson(data_obj, stdout_iface, true);
            return 0;
        }

        try printer.printKeyValuesPlain(stdout_iface, data_pairs[0..]);
        return 0;
    }

    try printer.printKeyValues(stdout_iface, pairs[0..]);
    return 0;
}

fn parseOptions(args: []const []const u8) !Options {
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
        if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--force")) {
            opts.yes = true;
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        if (opts.target == null) {
            opts.target = arg;
            idx += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return opts;
}

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issue delete <ID|IDENTIFIER> [--quiet] [--data-only] [--yes] [--help]
        \\Flags:
        \\  --quiet        Print only the identifier
        \\  --data-only    Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --yes          Skip confirmation prompt (useful for scripts; alias: --force)
        \\  --help         Show this help message
        \\Examples:
        \\  linear issue delete ENG-123
        \\  linear issue delete 12345 --quiet
        \\
    , .{});
}
