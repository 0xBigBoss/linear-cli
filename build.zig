const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    const git_hash = detectGitHash(b.allocator);
    build_options.addOption([]const u8, "git_hash", git_hash);

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "linear",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", build_options);
    exe.root_module.addImport("cli", cli_mod);
    b.installArtifact(exe);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addOptions("build_options", build_options);

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const graphql_mod = b.createModule(.{
        .root_source_file = b.path("src/graphql_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    const graphql_mock_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/mock_graphql.zig"),
        .target = target,
        .optimize = optimize,
    });
    const printer_mod = b.createModule(.{
        .root_source_file = b.path("src/print.zig"),
        .target = target,
        .optimize = optimize,
    });
    const common_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    common_mod.addImport("config", config_mod);
    common_mod.addImport("graphql", graphql_mod);
    const common_test_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    common_test_mod.addImport("config", config_mod);
    common_test_mod.addImport("graphql", graphql_mock_mod);
    const app_main_stub = b.createModule(.{
        .root_source_file = b.path("src/tests/app_main_stub.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("config", config_mod);
    exe.root_module.addImport("graphql", graphql_mod);
    exe.root_module.addImport("printer", printer_mod);
    exe.root_module.addImport("common", common_mod);

    const tests_mod = tests.root_module;
    tests_mod.addImport("config", config_mod);
    tests_mod.addImport("graphql", graphql_mod);
    tests_mod.addImport("graphql_mock", graphql_mock_mod);
    tests_mod.addImport("printer", printer_mod);
    tests_mod.addImport("common", common_test_mod);
    tests_mod.addImport("cli", cli_mod);
    tests_mod.addImport("app_main", app_main_stub);

    const gql_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/gql.zig"),
        .target = target,
        .optimize = optimize,
    });
    gql_mod.addImport("config", config_mod);
    gql_mod.addImport("graphql", graphql_mod);
    gql_mod.addImport("printer", printer_mod);
    gql_mod.addImport("common", common_mod);
    const gql_test_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/gql.zig"),
        .target = target,
        .optimize = optimize,
    });
    gql_test_mod.addImport("config", config_mod);
    gql_test_mod.addImport("graphql", graphql_mock_mod);
    gql_test_mod.addImport("printer", printer_mod);
    gql_test_mod.addImport("common", common_test_mod);
    tests_mod.addImport("gql", gql_test_mod);

    const issues_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issues.zig"),
        .target = target,
        .optimize = optimize,
    });
    issues_mod.addImport("config", config_mod);
    issues_mod.addImport("graphql", graphql_mod);
    issues_mod.addImport("printer", printer_mod);
    issues_mod.addImport("common", common_mod);
    const issues_test_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issues.zig"),
        .target = target,
        .optimize = optimize,
    });
    issues_test_mod.addImport("config", config_mod);
    issues_test_mod.addImport("graphql", graphql_mock_mod);
    issues_test_mod.addImport("printer", printer_mod);
    issues_test_mod.addImport("common", common_test_mod);
    tests_mod.addImport("issues_test", issues_test_mod);

    const issue_create_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issue_create.zig"),
        .target = target,
        .optimize = optimize,
    });
    issue_create_mod.addImport("config", config_mod);
    issue_create_mod.addImport("graphql", graphql_mod);
    issue_create_mod.addImport("printer", printer_mod);
    issue_create_mod.addImport("common", common_mod);
    const issue_create_test_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issue_create.zig"),
        .target = target,
        .optimize = optimize,
    });
    issue_create_test_mod.addImport("config", config_mod);
    issue_create_test_mod.addImport("graphql", graphql_mock_mod);
    issue_create_test_mod.addImport("printer", printer_mod);
    issue_create_test_mod.addImport("common", common_test_mod);
    tests_mod.addImport("issue_create_test", issue_create_test_mod);

    const issue_view_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issue_view.zig"),
        .target = target,
        .optimize = optimize,
    });
    issue_view_mod.addImport("config", config_mod);
    issue_view_mod.addImport("graphql", graphql_mock_mod);
    issue_view_mod.addImport("printer", printer_mod);
    issue_view_mod.addImport("common", common_test_mod);
    tests_mod.addImport("issue_view_test", issue_view_mod);

    const me_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/me.zig"),
        .target = target,
        .optimize = optimize,
    });
    me_mod.addImport("config", config_mod);
    me_mod.addImport("graphql", graphql_mock_mod);
    me_mod.addImport("printer", printer_mod);
    me_mod.addImport("common", common_test_mod);
    tests_mod.addImport("me_test", me_mod);

    const teams_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/teams.zig"),
        .target = target,
        .optimize = optimize,
    });
    teams_mod.addImport("config", config_mod);
    teams_mod.addImport("graphql", graphql_mock_mod);
    teams_mod.addImport("printer", printer_mod);
    teams_mod.addImport("common", common_test_mod);
    tests_mod.addImport("teams_test", teams_mod);

    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}

fn detectGitHash(allocator: std.mem.Allocator) []const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
    }) catch return "unknown";
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    const success = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (!success) return "unknown";

    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0) return "unknown";

    return allocator.dupe(u8, trimmed) catch "unknown";
}
