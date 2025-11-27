const std = @import("std");
const config = @import("config");
const graphql = @import("graphql");
const printer = @import("printer");
const common = @import("common");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    allocator: Allocator,
    config: *config.Config,
    args: [][]const u8,
    json_output: bool,
    config_path: ?[]const u8,
    retries: u8,
    timeout_ms: u32,
};

const SetOptions = struct {
    api_key: ?[]const u8 = null,
    help: bool = false,
};

const TestOptions = struct {
    help: bool = false,
};

const ShowOptions = struct {
    redacted: bool = false,
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
    if (std.mem.eql(u8, sub, "show")) {
        return runShow(ctx, rest);
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
    var prompt_value: ?[]u8 = null;
    defer {
        if (stdin_value) |buf| ctx.allocator.free(buf);
        if (prompt_value) |buf| ctx.allocator.free(buf);
    }

    var key: ?[]const u8 = opts.api_key;
    const stdin_file = std.fs.File.stdin();
    if (key == null and !stdin_file.isTty()) {
        var reader = stdin_file.reader();
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
        prompt_value = try promptForApiKey(ctx.allocator, stderr);
        if (prompt_value) |buf| {
            const trimmed = std.mem.trim(u8, buf, " \r\n\t");
            if (trimmed.len > 0) {
                key = trimmed;
            } else {
                ctx.allocator.free(buf);
                prompt_value = null;
            }
        }
    }

    if (key == null) {
        if (ctx.config.api_key) |existing| {
            key = existing;
        }
    }

    if (key == null) {
        try stderr.print("auth set: missing --api-key (stdin/prompt empty)\n", .{});
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
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;

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

    common.checkResponse("auth test", &response, stderr, api_key) catch {
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
    try printer.printUserTable(ctx.allocator, &out_writer.interface, &.{row}, .{});
    return 0;
}

fn runShow(ctx: Context, args: [][]const u8) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseShowOptions(args) catch |err| {
        try stderr.print("auth show: {s}\n", .{@errorName(err)});
        try showUsage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try showUsage(&out_writer.interface);
        return 0;
    }

    const key = ctx.config.api_key orelse {
        try stderr.print("auth show: no API key configured\n", .{});
        return 1;
    };

    var redacted_buf: [64]u8 = undefined;
    const display = if (opts.redacted) common.redactKey(key, &redacted_buf) else key;

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    if (ctx.json_output) {
        var json_buffer = std.io.Writer.Allocating.init(ctx.allocator);
        defer json_buffer.deinit();
        var jw = std.json.Stringify{ .writer = &json_buffer.writer, .options = .{ .whitespace = .indent_2 } };
        try jw.beginObject();
        try jw.objectField("api_key");
        try jw.write(display);
        try jw.endObject();
        try out_writer.interface.writeAll(json_buffer.writer.buffered());
        try out_writer.interface.writeByte('\n');
        return 0;
    }

    try out_writer.interface.print("api key: {s}\n", .{display});
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

fn parseShowOptions(args: [][]const u8) !ShowOptions {
    var opts = ShowOptions{};
    var idx: usize = 0;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--redacted")) {
            opts.redacted = true;
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }
    return opts;
}

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth <set|test|show> [args]
        \\Commands:
        \\  set     Store an API key in the config file
        \\  show    Display the configured API key
        \\  test    Validate the configured API key
        \\Examples:
        \\  linear auth set --api-key lin_api_key
        \\  linear auth test
        \\
    , .{});
}

pub fn setUsage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth set [--api-key KEY]
        \\Flags:
        \\  --api-key KEY    API key to save (fallback: piped stdin or interactive prompt)
        \\  --help           Show this help message
        \\Examples:
        \\  linear auth set --api-key lin_api_key
        \\  echo "$LINEAR_API_KEY" | linear auth set
        \\
    , .{});
}

pub fn testUsage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth test [--help]
        \\Flags:
        \\  --help           Show this help message
        \\Examples:
        \\  linear auth test
        \\
    , .{});
}

pub fn showUsage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear auth show [--redacted] [--help]
        \\Flags:
        \\  --redacted      Mask the API key in output
        \\  --help          Show this help message
        \\Examples:
        \\  linear auth show --redacted
        \\
    , .{});
}

const EchoState = struct {
    enabled: bool = false,
    previous: std.posix.termios = undefined,
};

fn promptForApiKey(allocator: Allocator, stderr: anytype) !?[]u8 {
    const stdin_file = std.fs.File.stdin();
    if (!stdin_file.isTty()) return null;

    var prompt_buf: [0]u8 = undefined;
    var prompt_writer = std.fs.File.stderr().writer(&prompt_buf);
    try prompt_writer.interface.writeAll("API key: ");

    var echo_state: EchoState = .{};
    echo_state = disableEcho(stdin_file) catch |err| blk: {
        try stderr.print("auth set: failed to disable echo: {s}\n", .{@errorName(err)});
        break :blk EchoState{};
    };
    defer restoreEcho(stdin_file, echo_state);

    var reader = stdin_file.reader();
    const input = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 64 * 1024) catch |err| {
        try stderr.print("auth set: failed to read key: {s}\n", .{@errorName(err)});
        return null;
    };

    try prompt_writer.interface.writeByte('\n');
    return input;
}

fn disableEcho(file: std.fs.File) !EchoState {
    if (!file.isTty()) return .{};
    if (builtin.os.tag == .windows) return .{};

    var term = try std.posix.tcgetattr(file.handle);
    var no_echo = term;
    no_echo.lflag &= ~@as(std.posix.tcflag_t, std.posix.ECHO);
    try std.posix.tcsetattr(file.handle, .FLUSH, no_echo);
    return .{ .enabled = true, .previous = term };
}

fn restoreEcho(file: std.fs.File, state: EchoState) void {
    if (!state.enabled) return;
    std.posix.tcsetattr(file.handle, .FLUSH, state.previous) catch {};
}
