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
        try stderr.print("me: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "me") catch {
        return 1;
    };

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();

    const query =
        \\query Viewer {
        \\  viewer {
        \\    id
        \\    name
        \\    email
        \\  }
        \\}
    ;

    var response = common.send("me", &client, ctx.allocator, .{
        .query = query,
        .variables = null,
        .operation_name = "Viewer",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("me", &response, stderr) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("me: response missing data\n", .{});
        return 1;
    };

    if (ctx.json_output) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const viewer = common.getObjectField(data_value, "viewer") orelse {
        try stderr.print("me: viewer not found in response\n", .{});
        return 1;
    };

    const row = printer.UserRow{
        .id = common.getStringField(viewer, "id") orelse "(unknown)",
        .name = common.getStringField(viewer, "name") orelse "(unknown)",
        .email = common.getStringField(viewer, "email") orelse "(unknown)",
    };

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    try printer.printUserTable(ctx.allocator, &out_writer.interface, &.{row});
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
        \\Usage: linear me [--help]
        \\Flags:
        \\  --help    Show this help message
        \\
    , .{});
}
