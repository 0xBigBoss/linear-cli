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
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    state: ?[]const u8 = null,
    yes: bool = false,
    help: bool = false,
    quiet: bool = false,
    data_only: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("project update: {s}\n", .{@errorName(err)});
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
        try stderr.print("project update: missing id\n", .{});
        return 1;
    };

    if (opts.name == null and opts.description == null and opts.state == null) {
        try stderr.print("project update: at least one field to update is required\n", .{});
        return 1;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "project update") catch {
        return 1;
    };

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;
    if (ctx.endpoint) |ep| client.endpoint = ep;

    var status_id: ?[]const u8 = null;
    defer if (status_id) |sid| ctx.allocator.free(sid);

    const resolved = common.resolveProjectId(ctx.allocator, &client, target, stderr, "project update") catch {
        return 1;
    };
    defer if (resolved.owned) ctx.allocator.free(resolved.value);

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var input = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    if (opts.name) |name_value| try input.object.put("name", .{ .string = name_value });
    if (opts.description) |desc| try input.object.put("description", .{ .string = desc });
    if (opts.state) |state_value| {
        status_id = common.resolveProjectStatusId(ctx.allocator, &client, state_value, stderr, "project update") catch {
            return 1;
        };
    }
    if (status_id) |sid| try input.object.put("statusId", .{ .string = sid });

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("id", .{ .string = resolved.value });
    try variables.object.put("input", input);

    if (!opts.yes) {
        try stderr.print("project update: confirmation required; re-run with --yes to proceed\n", .{});
        return 1;
    }

    const mutation =
        \\mutation ProjectUpdate($id: String!, $input: ProjectUpdateInput!) {
        \\  projectUpdate(id: $id, input: $input) {
        \\    success
        \\    project { id name slugId state url }
        \\  }
        \\}
    ;

    var response = common.send(ctx.allocator, "project update", &client, .{
        .query = mutation,
        .variables = variables,
        .operation_name = "ProjectUpdate",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("project update", &response, stderr, api_key) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("project update: response missing data\n", .{});
        return 1;
    };

    const payload = common.getObjectField(data_value, "projectUpdate") orelse {
        try stderr.print("project update: projectUpdate missing in response\n", .{});
        return 1;
    };
    const success = common.getBoolField(payload, "success") orelse false;
    const project_obj = common.getObjectField(payload, "project");
    if (!success) {
        if (payload.object.get("userError")) |user_error| {
            if (user_error == .string) {
                try stderr.print("project update: {s}\n", .{user_error.string});
                return 1;
            }
            if (user_error == .object) {
                if (user_error.object.get("message")) |msg| {
                    if (msg == .string) {
                        try stderr.print("project update: {s}\n", .{msg.string});
                        return 1;
                    }
                }
            }
        }
        try stderr.print("project update: request failed\n", .{});
        return 1;
    }

    const project = project_obj orelse {
        try stderr.print("project update: project missing in response\n", .{});
        return 1;
    };

    if (ctx.json_output and !opts.quiet and !opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const id = common.getStringField(project, "id") orelse "(unknown)";
    const name = common.getStringField(project, "name") orelse "";
    const slug = common.getStringField(project, "slugId") orelse "";
    const state = common.getStringField(project, "state") orelse "";
    const url = common.getStringField(project, "url") orelse "";

    const quiet_value = if (slug.len > 0) slug else id;

    var display_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer display_pairs.deinit(ctx.allocator);
    var data_pairs = std.ArrayListUnmanaged(printer.KeyValue){};
    defer data_pairs.deinit(ctx.allocator);

    try display_pairs.append(ctx.allocator, .{ .key = "ID", .value = id });
    try display_pairs.append(ctx.allocator, .{ .key = "Name", .value = name });
    try display_pairs.append(ctx.allocator, .{ .key = "Slug", .value = slug });
    try display_pairs.append(ctx.allocator, .{ .key = "State", .value = state });
    try display_pairs.append(ctx.allocator, .{ .key = "URL", .value = url });

    try data_pairs.append(ctx.allocator, .{ .key = "id", .value = id });
    try data_pairs.append(ctx.allocator, .{ .key = "name", .value = name });
    try data_pairs.append(ctx.allocator, .{ .key = "slug", .value = slug });
    try data_pairs.append(ctx.allocator, .{ .key = "state", .value = state });
    try data_pairs.append(ctx.allocator, .{ .key = "url", .value = url });

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    var stdout_iface = &out_writer.interface;

    if (opts.quiet) {
        try stdout_iface.writeAll(quiet_value);
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

    try printer.printKeyValues(stdout_iface, display_pairs.items);
    return 0;
}

pub fn parseOptions(args: [][]const u8) !Options {
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
        if (std.mem.eql(u8, arg, "--name")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.name = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--name=")) {
            opts.name = arg["--name=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--description")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.description = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--description=")) {
            opts.description = arg["--description=".len..];
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
        if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--force")) {
            opts.yes = true;
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

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear project update <ID> [--name NAME] [--description TEXT] [--state STATE] [--yes] [--quiet] [--data-only] [--help]
        \\Flags:
        \\  --name NAME         Update project name
        \\  --description TEXT  Update description
        \\  --state STATE       Update state (backlog, planned, started, paused, completed, canceled)
        \\  --yes               Skip confirmation prompt (alias: --force)
        \\  --quiet             Print only the identifier
        \\  --data-only         Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --help              Show this help message
        \\Examples:
        \\  linear project update a6e7e3aa-53d0-42ab-9049-ac7aaa51f732 --name "New Name" --yes
        \\  linear project update 0949c8955675 --state started --yes --json
        \\
    , .{});
}
