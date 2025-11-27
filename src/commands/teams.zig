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
    help: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("teams: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "teams") catch {
        return 1;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("first", .{ .integer = 50 });

    const query =
        \\query Teams($first: Int!) {
        \\  teams(first: $first) {
        \\    nodes {
        \\      id
        \\      key
        \\      name
        \\    }
        \\  }
        \\}
    ;

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();

    var response = common.send("teams", &client, ctx.allocator, .{
        .query = query,
        .variables = variables,
        .operation_name = "Teams",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("teams", &response, stderr) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("teams: response missing data\n", .{});
        return 1;
    };

    if (ctx.json_output) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const teams_obj = common.getObjectField(data_value, "teams") orelse {
        try stderr.print("teams: teams not found in response\n", .{});
        return 1;
    };
    const nodes_array = common.getArrayField(teams_obj, "nodes") orelse {
        try stderr.print("teams: nodes missing in response\n", .{});
        return 1;
    };

    var rows = std.ArrayList(printer.TeamRow){};
    defer rows.deinit(ctx.allocator);

    for (nodes_array.items) |node| {
        if (node != .object) continue;
        const id = common.getStringField(node, "id") orelse continue;
        const key = common.getStringField(node, "key") orelse "";
        const name = common.getStringField(node, "name") orelse "";
        try rows.append(ctx.allocator, .{ .id = id, .key = key, .name = name });
    }

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    try printer.printTeamTable(ctx.allocator, &out_writer.interface, rows.items);
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
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    return opts;
}

fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear teams list [--help]
        \\Flags:
        \\  --help    Show this help message
        \\
    , .{});
}
