const std = @import("std");
const config = @import("config");
const gql_command = @import("commands/gql.zig");
const auth_command = @import("commands/auth.zig");
const me_command = @import("commands/me.zig");
const teams_command = @import("commands/teams.zig");
const issues_command = @import("commands/issues.zig");
const issue_view_command = @import("commands/issue_view.zig");
const issue_create_command = @import("commands/issue_create.zig");

const version_string = "0.0.1-dev";

const GlobalOptions = struct {
    json: bool = false,
    config_path: ?[]const u8 = null,
    help: bool = false,
    version: bool = false,
};

const Parsed = struct {
    opts: GlobalOptions,
    rest: [][]const u8,
};

pub fn main() !void {
    const exit_code = run() catch |err| {
        var stderr_buf: [0]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        var stderr = &stderr_writer.interface;
        stderr.print("linear: {s}\n", .{@errorName(err)}) catch {};
        std.process.exit(1);
    };
    std.process.exit(exit_code);
}

fn run() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args_raw = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_raw);

    const args = try allocator.alloc([]const u8, args_raw.len);
    defer allocator.free(args);
    for (args_raw, 0..) |arg, idx| {
        args[idx] = arg[0..arg.len];
    }

    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;

    const parsed = parseGlobal(args) catch |err| {
        try stderr.print("error: {s}\n", .{@errorName(err)});
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stderr().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return 1;
    };
    const opts = parsed.opts;

    if (opts.version) {
        try printVersion();
        return 0;
    }

    if (opts.help or parsed.rest.len == 0) {
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stdout().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return if (opts.help) 0 else 1;
    }

    var cfg = config.load(allocator, opts.config_path) catch |err| {
        try stderr.print("failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer cfg.deinit();

    const json_output = opts.json or std.ascii.eqlIgnoreCase(cfg.default_output, "json");

    const subcommand = parsed.rest[0];
    const sub_args = parsed.rest[1..];

    if (std.mem.eql(u8, subcommand, "gql")) {
        return gql_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
        });
    }

    if (std.mem.eql(u8, subcommand, "auth")) {
        return auth_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .config_path = opts.config_path,
        });
    }

    if (std.mem.eql(u8, subcommand, "me")) {
        return me_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
        });
    }

    if (std.mem.eql(u8, subcommand, "teams")) {
        if (sub_args.len == 0 or !std.mem.eql(u8, sub_args[0], "list")) {
            try stderr.print("teams: expected 'list'\n", .{});
            try printUsage(stderr);
            return 1;
        }
        return teams_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args[1..],
            .json_output = json_output,
        });
    }

    if (std.mem.eql(u8, subcommand, "issues")) {
        if (sub_args.len == 0 or !std.mem.eql(u8, sub_args[0], "list")) {
            try stderr.print("issues: expected 'list'\n", .{});
            try printUsage(stderr);
            return 1;
        }
        return issues_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args[1..],
            .json_output = json_output,
        });
    }

    if (std.mem.eql(u8, subcommand, "issue")) {
        if (sub_args.len == 0) {
            try stderr.print("issue: expected 'view' or 'create'\n", .{});
            try printUsage(stderr);
            return 1;
        }
        const issue_sub = sub_args[0];
        const issue_args = sub_args[1..];
        if (std.mem.eql(u8, issue_sub, "view")) {
            return issue_view_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
            });
        }
        if (std.mem.eql(u8, issue_sub, "create")) {
            return issue_create_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
            });
        }

        try stderr.print("issue: unknown command: {s}\n", .{issue_sub});
        try printUsage(stderr);
        return 1;
    }

    try stderr.print("unknown command: {s}\n", .{subcommand});
    try printUsage(stderr);
    return 1;
}

pub fn parseGlobal(args: [][]const u8) !Parsed {
    var opts = GlobalOptions{};
    if (args.len == 0) return .{ .opts = opts, .rest = args };

    var idx: usize = 1;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--json")) {
            opts.json = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--version")) {
            opts.version = true;
            idx += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--config=")) {
            opts.config_path = arg["--config=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--config")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.config_path = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            idx += 1;
            break;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        break;
    }

    return .{ .opts = opts, .rest = args[idx..] };
}

fn printUsage(writer: anytype) !void {
    try writer.print(
        \\linear [--json] [--config PATH] [--help] [--version] <command> [args]
        \\Commands:
        \\  auth set|test        Manage or validate authentication
        \\  me                   Show current user
        \\  teams list           List teams
        \\  issues list          List issues
        \\  issue view|create    View or create an issue
        \\  gql                  Run an arbitrary GraphQL query against Linear
        \\
        \\Use 'linear <command> --help' for command-specific help.
        \\
    , .{});
}

fn printVersion() !void {
    var buf: [0]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    try stdout_writer.interface.print("linear {s}\n", .{version_string});
}
