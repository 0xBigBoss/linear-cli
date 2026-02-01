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
    dry_run: bool = false,
    reason: ?[]const u8 = null,
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
    const reason = if (opts.reason) |raw_reason| blk: {
        const trimmed = std.mem.trim(u8, raw_reason, " \t");
        if (trimmed.len == 0) {
            try stderr.print("issue delete: invalid --reason value\n", .{});
            return 1;
        }
        break :blk trimmed;
    } else null;

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;
    if (ctx.endpoint) |ep| client.endpoint = ep;

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("id", .{ .string = target });

    if (opts.dry_run) {
        const lookup_query =
            \\query IssueDeleteLookup($id: String!) {
            \\  issue(id: $id) {
            \\    id
            \\    identifier
            \\    title
            \\  }
            \\}
        ;

        var lookup_response = common.send(ctx.allocator, "issue delete", &client, .{
            .query = lookup_query,
            .variables = variables,
            .operation_name = "IssueDeleteLookup",
        }, stderr) catch {
            return 1;
        };
        defer lookup_response.deinit();

        common.checkResponse("issue delete", &lookup_response, stderr, api_key) catch {
            return 1;
        };

        const data_value = lookup_response.data() orelse {
            try stderr.print("issue delete: response missing data\n", .{});
            return 1;
        };
        const issue_obj = common.getObjectField(data_value, "issue") orelse {
            try stderr.print("issue delete: issue not found\n", .{});
            return 1;
        };

        const resolved_identifier = common.getStringField(issue_obj, "identifier") orelse target;
        const resolved_id = common.getStringField(issue_obj, "id") orelse target;
        const resolved_title = common.getStringField(issue_obj, "title");

        const dry_data_pairs = [_]printer.KeyValue{
            .{ .key = "identifier", .value = resolved_identifier },
            .{ .key = "id", .value = resolved_id },
            .{ .key = "dry_run", .value = "true" },
        };

        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        var stdout_iface = &out_writer.interface;

        if (ctx.json_output) {
            var obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            try obj.object.put("identifier", .{ .string = resolved_identifier });
            try obj.object.put("id", .{ .string = resolved_id });
            if (resolved_title) |title_value| try obj.object.put("title", .{ .string = title_value });
            try obj.object.put("dry_run", .{ .bool = true });
            if (reason) |reason_value| try obj.object.put("reason", .{ .string = reason_value });
            try printer.printJson(obj, stdout_iface, true);
            return 0;
        }

        if (opts.data_only) {
            var data_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
            defer data_pairs.deinit(ctx.allocator);
            try data_pairs.appendSlice(ctx.allocator, dry_data_pairs[0..]);
            if (resolved_title) |title_value| try data_pairs.append(ctx.allocator, .{ .key = "title", .value = title_value });
            if (reason) |reason_value| try data_pairs.append(ctx.allocator, .{ .key = "reason", .value = reason_value });
            try printer.printKeyValuesPlain(stdout_iface, data_pairs.items);
            return 0;
        }

        if (opts.quiet) {
            try stdout_iface.print("issue delete: dry run; {s}\n", .{resolved_identifier});
            return 0;
        }

        try stdout_iface.print("issue delete: dry run; would delete {s} (id {s})", .{ resolved_identifier, resolved_id });
        if (resolved_title) |title_value| try stdout_iface.print(" title \"{s}\"", .{title_value});
        if (reason) |reason_value| try stdout_iface.print(" reason: {s}", .{reason_value});
        try stdout_iface.writeByte('\n');
        return 0;
    }

    if (!opts.yes) {
        try stderr.print("issue delete: confirmation required; re-run with --yes to proceed\n", .{});
        return 1;
    }

    const mutation =
        \\mutation IssueDelete($id: String!) {
        \\  issueDelete(id: $id) {
        \\    success
        \\    entity { id identifier }
        \\    lastSyncId
        \\  }
        \\}
    ;

    var response = common.send(ctx.allocator, "issue delete", &client, .{
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

    if (ctx.json_output and !opts.quiet and !opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        if (reason) |reason_value| {
            var root_obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            try root_obj.object.put("response", data_value);
            try root_obj.object.put("reason", .{ .string = reason_value });
            try printer.printJson(root_obj, &out_writer.interface, true);
        } else {
            try printer.printJson(data_value, &out_writer.interface, true);
        }
        return 0;
    }

    const identifier = if (issue_obj) |issue|
        common.getStringField(issue, "identifier") orelse target
    else
        target;
    const id_value = if (issue_obj) |issue|
        common.getStringField(issue, "id") orelse "(unknown)"
    else
        "(unknown)";

    var pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer pairs.deinit(ctx.allocator);
    var data_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer data_pairs.deinit(ctx.allocator);
    try pairs.appendSlice(ctx.allocator, &[_]printer.KeyValue{
        .{ .key = "Identifier", .value = identifier },
        .{ .key = "ID", .value = id_value },
    });
    try data_pairs.appendSlice(ctx.allocator, &[_]printer.KeyValue{
        .{ .key = "identifier", .value = identifier },
        .{ .key = "id", .value = id_value },
    });
    if (reason) |reason_value| {
        try pairs.append(ctx.allocator, .{ .key = "Reason", .value = reason_value });
        try data_pairs.append(ctx.allocator, .{ .key = "reason", .value = reason_value });
    }

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
            for (data_pairs.items) |pair| {
                try data_obj.object.put(pair.key, .{ .string = pair.value });
            }
            try printer.printJson(data_obj, stdout_iface, true);
            return 0;
        }

        try printer.printKeyValuesPlain(stdout_iface, data_pairs.items);
        return 0;
    }

    try printer.printKeyValues(stdout_iface, pairs.items);
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
        if (std.mem.eql(u8, arg, "--dry-run")) {
            opts.dry_run = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--reason")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.reason = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--reason=")) {
            opts.reason = arg["--reason=".len..];
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
        \\Usage: linear issue delete <ID|IDENTIFIER> [--quiet] [--data-only] [--yes] [--dry-run] [--reason TEXT] [--help]
        \\Flags:
        \\  --quiet        Print only the identifier
        \\  --data-only    Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --yes          Skip confirmation prompt (useful for scripts; alias: --force)
        \\  --dry-run      Resolve and validate the issue without deleting; prints the target and exits 0
        \\  --reason TEXT  Attach a reason (echoed in output; for audit logging)
        \\  --help         Show this help message
        \\Examples:
        \\  linear issue delete ENG-123
        \\  linear issue delete 12345 --quiet
        \\
    , .{});
}
