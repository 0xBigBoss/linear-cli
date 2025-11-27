const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "linear",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

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

    exe.root_module.addImport("config", config_mod);
    exe.root_module.addImport("graphql", graphql_mod);
    exe.root_module.addImport("printer", printer_mod);
    exe.root_module.addImport("common", common_mod);

    const tests_mod = tests.root_module;
    tests_mod.addImport("config", config_mod);
    tests_mod.addImport("graphql", graphql_mod);
    tests_mod.addImport("printer", printer_mod);
    tests_mod.addImport("common", common_mod);

    const gql_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/gql.zig"),
        .target = target,
        .optimize = optimize,
    });
    gql_mod.addImport("config", config_mod);
    gql_mod.addImport("graphql", graphql_mod);
    gql_mod.addImport("printer", printer_mod);
    gql_mod.addImport("common", common_mod);
    tests_mod.addImport("gql", gql_mod);

    const issues_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issues.zig"),
        .target = target,
        .optimize = optimize,
    });
    issues_mod.addImport("config", config_mod);
    issues_mod.addImport("graphql", graphql_mod);
    issues_mod.addImport("printer", printer_mod);
    issues_mod.addImport("common", common_mod);
    tests_mod.addImport("issues", issues_mod);

    const issue_create_mod = b.createModule(.{
        .root_source_file = b.path("src/commands/issue_create.zig"),
        .target = target,
        .optimize = optimize,
    });
    issue_create_mod.addImport("config", config_mod);
    issue_create_mod.addImport("graphql", graphql_mod);
    issue_create_mod.addImport("printer", printer_mod);
    issue_create_mod.addImport("common", common_mod);
    tests_mod.addImport("issue_create", issue_create_mod);

    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
