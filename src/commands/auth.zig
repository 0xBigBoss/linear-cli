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
    config_path: ?[]const u8,
};

const SetOptions = struct {
    api_key: ?[]const u8 = null,
    help: bool = false,
};

const TestOptions = struct {
    help: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    if (ctx.args.len == 0) {
        try usage(stderr);
        return 1;
    }

    const sub = ctx.args[0];
    const rest = ctx.args[1..];

    if (std.mem.eql(u8, sub, "set")) {
        return runSet(ctx, rest);
    }
    if (std.mem.eql(u8, sub, "test")) {
        return runTest(ctx, rest);
    }

    try stderr.print("auth: unknown command: {s}\n", .{sub});
    try usage(stderr);
    return 1;
}

fn runSet(ctx: Context, args: [][]const u8) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseSetOptions(args) catch |err| {
        try stderr.print("auth set: {s}\n", .{@errorName(err)});
        try setUsage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try setUsage(&out_writer.interface);
        return 0;
    }

    var stdin_value: ?[]u8 = null;
    defer {
        if (stdin_value) |buf| ctx.allocator.free(buf);
    }

    var key: ?[]const u8 = opts.api_key;
    if (key == null) {
        var reader = std.fs.File.stdin().deprecatedReader();
        const input = reader.readAllAlloc(ctx.allocator, 64 * 1024) catch |err| {
            try stderr.print("auth set: failed to read stdin: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (input.len > 0) {
            const trimmed = std.mem.trim(u8, input, " \r\n\t");
            if (trimmed.len > 0) {
                stdin_value = input;
                key = trimmed;
            } else {
                ctx.allocator.free(input);
            }
        } else {
            ctx.allocator.free(input);
        }
    }

    if (key == null) {
        if (ctx.config.api_key) |existing| {
            key = existing;
        }
    }

    if (key == null) {
        try stderr.print("auth set: missing --api-key (or stdin value)\n", .{});
        return 1;
    }

    try ctx.config.setApiKey(key.?);
    try ctx.config.save(ctx.allocator, ctx.config_path);

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    try out_writer.interface.print("api key saved\n", .{});
    return 0;
}

fn runTest(ctx: Context, args: [][]const u8) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseTestOptions(args) catch |err| {
        try stderr.print("auth test: {s}\n", .{@errorName(err)});
        try testUsage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try testUsage(&out_writer.interface);
        return 0;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "auth test") catch {
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

    var response = common.send("auth test", &client, ctx.allocator, .{
        .query = query,
        .variables = null,
        .operation_name = "Viewer",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("auth test", &response, stderr) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("auth test: response missing data\n", .{});
        return 1;
    };

    if (ctx.json_output) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const viewer = common.getObjectField(data_value, "viewer") orelse {
        try stderr.print("auth test: viewer not found in response\n", .{});
        return 1;
    };

    const id = common.getStringField(viewer, "id") orelse "(unknown)";
    const name = common.getStringField(viewer, "name") orelse "(unknown)";
    const email = common.getStringField(viewer, "email") orelse "(unknown)";

    const row = printer.UserRow{
        .id = id,
        .name = name,
        .email = email,
    };

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    try printer.printUserTable(ctx.allocator, &out_writer.interface, &.{row});
    return 0;
}

fn parseSetOptions(args: [][]const u8) !SetOptions {
    var opts = SetOptions{};
    var idx: usize = 0;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--api-key")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.api_key = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--api-key=")) {
            opts.api_key = arg["--api-key=".len..];
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    return opts;
}

fn parseTestOptions(args: [][]const u8) !TestOptions {
    var opts = TestOptions{};
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
        \\Usage: linear auth <set|test> [args]
        \\Commands:
        \\  set     Store an API key in the config file
        \\  test    Validate the configured API key
        \\
    , .{});
}

fn setUsage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth set --api-key KEY
        \\Flags:
        \\  --api-key KEY    API key to save (fallback: stdin or existing env/config)
        \\  --help           Show this help message
        \\
    , .{});
}

fn testUsage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth test [--help]
        \\Flags:
        \\  --help           Show this help message
        \\
    , .{});
}
