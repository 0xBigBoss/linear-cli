const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const config = @import("config");
const cli = @import("cli");
const graphql = @import("graphql");
const gql_command = @import("commands/gql.zig");
const auth_command = @import("commands/auth.zig");
const config_command = @import("commands/config.zig");
const me_command = @import("commands/me.zig");
const teams_command = @import("commands/teams.zig");
const issues_command = @import("commands/issues.zig");
const issue_view_command = @import("commands/issue_view.zig");
const issue_create_command = @import("commands/issue_create.zig");
const issue_delete_command = @import("commands/issue_delete.zig");
const issue_update_command = @import("commands/issue_update.zig");
const issue_link_command = @import("commands/issue_link.zig");
const issue_comment_command = @import("commands/issue_comment.zig");
const download_command = @import("download");
const search_command = @import("commands/search.zig");
const projects_command = @import("commands/projects.zig");
const project_view_command = @import("commands/project_view.zig");
const project_create_command = @import("commands/project_create.zig");
const project_update_command = @import("commands/project_update.zig");
const project_delete_command = @import("commands/project_delete.zig");
const project_issues_command = @import("commands/project_issues.zig");

const version_string = build_options.version;
const GlobalOptions = cli.GlobalOptions;
const Parsed = cli.Parsed;
const parseGlobal = cli.parseGlobal;

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

    defer graphql.deinitSharedClient();

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
    var opts = parsed.opts;

    const cleaned_rest = cli.stripTrailingGlobals(allocator, parsed.rest, &opts) catch |err| {
        try stderr.print("error: {s}\n", .{@errorName(err)});
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stderr().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return 1;
    };
    defer allocator.free(cleaned_rest);

    // Check help/version flags before requiring a subcommand
    if (opts.version) {
        try printVersion();
        return 0;
    }

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stdout().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return 0;
    }

    if (cleaned_rest.len == 0) {
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stderr().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return 1;
    }

    const subcommand = cleaned_rest[0];
    const sub_args_raw = cleaned_rest[1..];
    const sub_args = cli.stripTrailingGlobals(allocator, sub_args_raw, &opts) catch |err| {
        try stderr.print("error: {s}\n", .{@errorName(err)});
        var out_buf: [0]u8 = undefined;
        var usage_writer = std.fs.File.stderr().writer(&out_buf);
        try printUsage(&usage_writer.interface);
        return 1;
    };
    defer allocator.free(sub_args);

    graphql.setDefaultKeepAlive(opts.keep_alive);

    if (std.mem.eql(u8, subcommand, "help")) {
        return routeHelp(sub_args, stderr);
    }

    var cfg = config.load(allocator, opts.config_path) catch |err| {
        try stderr.print("failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer cfg.deinit();
    if (cfg.permissions_warning) {
        const path = cfg.config_path orelse "(unknown)";
        try stderr.print("warning: config file {s} permissions should be 0600\n", .{path});
    }

    const json_output = opts.json or std.ascii.eqlIgnoreCase(cfg.default_output, "json");

    if (std.mem.eql(u8, subcommand, "gql")) {
        return gql_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "auth")) {
        return auth_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .config_path = opts.config_path,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "config")) {
        return config_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .config_path = opts.config_path,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "me")) {
        return me_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "search")) {
        return search_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "download")) {
        return download_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args,
            .json_output = json_output,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
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
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "projects")) {
        if (sub_args.len == 0 or !std.mem.eql(u8, sub_args[0], "list")) {
            try stderr.print("projects: expected 'list'\n", .{});
            try printUsage(stderr);
            return 1;
        }
        return projects_command.run(.{
            .allocator = allocator,
            .config = &cfg,
            .args = sub_args[1..],
            .json_output = json_output,
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
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
            .retries = opts.retries,
            .timeout_ms = opts.timeout_ms,
            .endpoint = opts.endpoint,
        });
    }

    if (std.mem.eql(u8, subcommand, "issue")) {
        if (sub_args.len == 0) {
            try stderr.print("issue: expected 'view', 'create', 'update', 'delete', 'link', or 'comment'\n", .{});
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
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, issue_sub, "create")) {
            return issue_create_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, issue_sub, "delete")) {
            return issue_delete_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, issue_sub, "update")) {
            return issue_update_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, issue_sub, "link")) {
            return issue_link_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, issue_sub, "comment")) {
            return issue_comment_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = issue_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }

        try stderr.print("issue: unknown command: {s}\n", .{issue_sub});
        try printUsage(stderr);
        return 1;
    }

    if (std.mem.eql(u8, subcommand, "project")) {
        if (sub_args.len == 0) {
            try stderr.print("project: expected 'view', 'create', 'update', 'delete', 'add-issue', or 'remove-issue'\n", .{});
            try printUsage(stderr);
            return 1;
        }
        const project_sub = sub_args[0];
        const project_args = sub_args[1..];
        if (std.mem.eql(u8, project_sub, "view")) {
            return project_view_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = project_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, project_sub, "create")) {
            return project_create_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = project_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, project_sub, "update")) {
            return project_update_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = project_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, project_sub, "delete")) {
            return project_delete_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = project_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }
        if (std.mem.eql(u8, project_sub, "add-issue") or std.mem.eql(u8, project_sub, "remove-issue")) {
            return project_issues_command.run(.{
                .allocator = allocator,
                .config = &cfg,
                .args = sub_args,
                .json_output = json_output,
                .retries = opts.retries,
                .timeout_ms = opts.timeout_ms,
                .endpoint = opts.endpoint,
            });
        }

        try stderr.print("project: unknown command: {s}\n", .{project_sub});
        try printUsage(stderr);
        return 1;
    }

    try stderr.print("unknown command: {s}\n", .{subcommand});
    try printUsage(stderr);
    return 1;
}

fn routeHelp(args: [][]const u8, stderr: anytype) !u8 {
    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const out = &out_writer.interface;

    if (args.len == 0) {
        try printUsage(out);
        return 0;
    }

    const target = args[0];
    const tail = args[1..];

    if (std.mem.eql(u8, target, "auth")) {
        if (tail.len > 0) {
            if (std.mem.eql(u8, tail[0], "set")) {
                try auth_command.setUsage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "test")) {
                try auth_command.testUsage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "show")) {
                try auth_command.showUsage(out);
                return 0;
            }
        }
        try auth_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "me")) {
        try me_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "config")) {
        if (tail.len > 0) {
            if (std.mem.eql(u8, tail[0], "set")) {
                try config_command.setUsage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "unset")) {
                try config_command.unsetUsage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "show")) {
                try config_command.showUsage(out);
                return 0;
            }
        }
        try config_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "teams")) {
        try teams_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "projects")) {
        try projects_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "project")) {
        if (tail.len > 0) {
            if (std.mem.eql(u8, tail[0], "view")) {
                try project_view_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "create")) {
                try project_create_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "update")) {
                try project_update_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "delete")) {
                try project_delete_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "add-issue")) {
                try project_issues_command.addUsage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "remove-issue")) {
                try project_issues_command.removeUsage(out);
                return 0;
            }
        }
        try project_view_command.usage(out);
        try out.writeByte('\n');
        try project_create_command.usage(out);
        try out.writeByte('\n');
        try project_update_command.usage(out);
        try out.writeByte('\n');
        try project_delete_command.usage(out);
        try out.writeByte('\n');
        try project_issues_command.addUsage(out);
        try out.writeByte('\n');
        try project_issues_command.removeUsage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "issues")) {
        try issues_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "download")) {
        try download_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "search")) {
        try search_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "issue")) {
        if (tail.len > 0) {
            if (std.mem.eql(u8, tail[0], "view")) {
                try issue_view_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "create")) {
                try issue_create_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "delete")) {
                try issue_delete_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "update")) {
                try issue_update_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "link")) {
                try issue_link_command.usage(out);
                return 0;
            }
            if (std.mem.eql(u8, tail[0], "comment")) {
                try issue_comment_command.usage(out);
                return 0;
            }
        }
        try issue_view_command.usage(out);
        try out.writeByte('\n');
        try issue_create_command.usage(out);
        try out.writeByte('\n');
        try issue_update_command.usage(out);
        try out.writeByte('\n');
        try issue_delete_command.usage(out);
        try out.writeByte('\n');
        try issue_link_command.usage(out);
        try out.writeByte('\n');
        try issue_comment_command.usage(out);
        return 0;
    }

    if (std.mem.eql(u8, target, "gql")) {
        try gql_command.usage(out);
        return 0;
    }

    try stderr.print("help: unknown command: {s}\n", .{target});
    try printUsage(stderr);
    return 1;
}

fn printUsage(writer: anytype) !void {
    try writer.print(
        \\linear [--json] [--config PATH] [--endpoint URL] [--no-keepalive] [--retries N] [--timeout-ms MS] [--help] [--version] <command> [args]
        \\Commands:
        \\  auth set|test|show   Manage or validate authentication
        \\  config show|set|unset Manage CLI defaults (team/output/state filter)
        \\  me                   Show current user
        \\  teams list           List teams
        \\  search               Search issues by keyword
        \\  download             Download uploads.linear.app attachments
        \\  projects list        List projects
        \\  issues list          List issues
        \\  issue view|create|update|delete|link|comment  Manage issues
        \\  project view|create|update|delete|add-issue|remove-issue  Manage projects
        \\  gql                  Run an arbitrary GraphQL query against Linear
        \\
        \\Use 'linear help <command>' for command-specific help and examples.
        \\Examples:
        \\  linear help issues
        \\  linear issues list --pages 2 --limit 50
        \\  linear issue view ENG-123 --json
        \\
    , .{});
}

fn printVersion() !void {
    var buf: [0]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const mode_label = @tagName(builtin.mode);
    const git_hash = build_options.git_hash;
    try stdout_writer.interface.print("linear {s} (git {s}, {s})\n", .{ version_string, git_hash, mode_label });
}
