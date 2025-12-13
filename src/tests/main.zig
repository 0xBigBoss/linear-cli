const std = @import("std");
const posix = std.posix;
const c = @cImport({
    @cInclude("stdlib.h");
});
const env_name = "LINEAR_API_KEY";
const env_name_z = "LINEAR_API_KEY\x00";
const config_env_name = "LINEAR_CONFIG";
const config_env_name_z = "LINEAR_CONFIG\x00";
const config = @import("config");
const config_cmd = @import("config_cmd");
const cli = @import("cli");
const gql = @import("gql");
const issues_cmd = @import("issues_test");
const search_cmd = @import("search_test");
const issue_create_cmd = @import("issue_create_test");
const issue_view_cmd = @import("issue_view_test");
const issue_delete_cmd = @import("issue_delete_test");
const issue_update_cmd = @import("issue_update_test");
const issue_link_cmd = @import("issue_link_test");
const issue_comment_cmd = @import("issue_comment_test");
const me_cmd = @import("me_test");
const teams_cmd = @import("teams_test");
const projects_cmd = @import("projects_test");
const project_view_cmd = @import("project_view_test");
const project_create_cmd = @import("project_create_test");
const project_update_cmd = @import("project_update_test");
const project_delete_cmd = @import("project_delete_test");
const project_issues_cmd = @import("project_issues_test");
const printer = @import("printer");
const graphql = @import("graphql");
const mock_graphql = @import("graphql_mock");
const fixtures = struct {
    pub const issues_response = @embedFile("fixtures/issues.json");
    pub const issues_page2_response = @embedFile("fixtures/issues_page2.json");
    pub const issues_with_subs_response = @embedFile("fixtures/issues_with_subs.json");
    pub const issues_table = @embedFile("fixtures/issues_table.txt");
    pub const issues_json = @embedFile("fixtures/issues_json.txt");
    pub const issues_pagination_stderr = @embedFile("fixtures/issues_pagination_stderr.txt");
    pub const teams_response = @embedFile("fixtures/teams.json");
    pub const teams_table = @embedFile("fixtures/teams_table.txt");
    pub const viewer_response = @embedFile("fixtures/viewer.json");
    pub const viewer_table = @embedFile("fixtures/me_table.txt");
    pub const issue_create_team_lookup = @embedFile("fixtures/issue_create_team_lookup.json");
    pub const team_lookup_empty = @embedFile("fixtures/team_lookup_empty.json");
    pub const issue_create_response = @embedFile("fixtures/issue_create_response.json");
    pub const issue_delete_response = @embedFile("fixtures/issue_delete_response.json");
    pub const issue_delete_lookup = @embedFile("fixtures/issue_delete_lookup.json");
    pub const issue_view_response = @embedFile("fixtures/issue_view.json");
    pub const issue_view_project = @embedFile("fixtures/issue_view_project.json");
    pub const issue_view_relations = @embedFile("fixtures/issue_view_relations.json");
    pub const issue_view_comments = @embedFile("fixtures/issue_view_comments.json");
    pub const issue_update_response = @embedFile("fixtures/issue_update_response.json");
    pub const issue_state_lookup_response = @embedFile("fixtures/issue_state_lookup_response.json");
    pub const issue_lookup_response = @embedFile("fixtures/issue_lookup_response.json");
    pub const issue_link_response = @embedFile("fixtures/issue_link_response.json");
    pub const project_create_response = @embedFile("fixtures/project_create_response.json");
    pub const projects_response = @embedFile("fixtures/projects_response.json");
    pub const project_view_response = @embedFile("fixtures/project_view_response.json");
    pub const project_update_response = @embedFile("fixtures/project_update_response.json");
    pub const project_delete_response = @embedFile("fixtures/project_delete_response.json");
    pub const project_add_issue_response = @embedFile("fixtures/project_add_issue_response.json");
    pub const project_remove_issue_response = @embedFile("fixtures/project_remove_issue_response.json");
    pub const project_statuses_response = @embedFile("fixtures/project_statuses_response.json");
    pub const comment_create_response = @embedFile("fixtures/comment_create_response.json");
};

test "config save and load roundtrip" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("file-key");
    try cfg.setDefaultTeamId("team-123");
    try cfg.setDefaultOutput("json");
    try cfg.save(allocator, config_path);

    var loaded = try config.load(allocator, config_path);
    defer loaded.deinit();
    try std.testing.expect(loaded.api_key != null);
    try std.testing.expectEqualStrings("file-key", loaded.api_key.?);
    try std.testing.expectEqualStrings("team-123", loaded.default_team_id);
    try std.testing.expectEqualStrings("json", loaded.default_output);
    try std.testing.expect(loaded.default_state_filter.len == config.default_state_filter_value.len);
}

test "config env override precedence" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("file-key");
    try cfg.save(allocator, config_path);
    try setEnvValue("env-key", allocator);

    var loaded = try config.load(allocator, config_path);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("env-key", loaded.api_key.?);
}

test "config path honors LINEAR_CONFIG" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const default_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(default_path);
    const override_path = try std.fs.path.join(allocator, &.{ dir_path, "override.json" });
    defer allocator.free(override_path);

    var default_cfg = try config.load(allocator, default_path);
    defer default_cfg.deinit();
    try default_cfg.setApiKey("default-key");
    try default_cfg.save(allocator, default_path);

    var override_cfg = try config.load(allocator, override_path);
    defer override_cfg.deinit();
    try override_cfg.setApiKey("override-key");
    try override_cfg.save(allocator, override_path);

    try setConfigEnvValue(override_path, allocator);

    var loaded = try config.load(allocator, null);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("override-key", loaded.api_key.?);
    try std.testing.expect(loaded.config_path != null);
    try std.testing.expectEqualStrings(override_path, loaded.config_path.?);
}

test "config warns on loose permissions" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var file = try tmp.dir.createFile("config.json", .{ .read = true, .truncate = true });
    defer file.close();
    try file.writeAll("{\"api_key\":\"file-key\"}");
    try file.setPermissions(.{ .inner = .{ .mode = 0o644 } });

    var loaded = try config.load(allocator, config_path);
    defer loaded.deinit();
    try std.testing.expect(loaded.permissions_warning);
}

test "config caches team ids" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("file-key");
    try std.testing.expect(try cfg.cacheTeamId("ABC", "team-id-1"));
    try cfg.save(allocator, config_path);

    var loaded = try config.load(allocator, config_path);
    defer loaded.deinit();
    const cached = loaded.lookupTeamId("ABC") orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("team-id-1", cached);
}

test "config rejects invalid types" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var file = try tmp.dir.createFile("config.json", .{ .read = true, .truncate = true });
    defer file.close();
    try file.writeAll("{\"api_key\":123,\"default_state_filter\":\"todo\"}");

    try std.testing.expectError(error.InvalidConfig, config.load(allocator, config_path));
}

test "config env api key is not persisted" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    const previous_config = std.process.getEnvVarOwned(allocator, config_env_name) catch null;
    const previous_home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
    defer {
        restoreEnv(env_name_z, previous, allocator);
        restoreEnv(config_env_name_z, previous_config, allocator);
        restoreEnv("HOME\x00", previous_home, allocator);
    }
    clearEnv();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    try setEnvValue("env-only-key", allocator);
    try setEnvPair("HOME\x00", dir_path, allocator);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try std.testing.expectEqualStrings("env-only-key", cfg.api_key.?);
    try cfg.save(allocator, config_path);

    var saved_file = try tmp.dir.openFile("config.json", .{});
    defer saved_file.close();
    const contents = try saved_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "env-only-key") == null);
}

test "config command sets default output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{ "set", "default_output", "json" };
    const runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "default_output saved") != null);

    var reloaded = try config.load(allocator, config_path);
    defer reloaded.deinit();
    try std.testing.expectEqualStrings("json", reloaded.default_output);
}

test "config command rejects invalid default output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{ "set", "default_output", "csv" };
    const runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "default_output must be 'table' or 'json'") != null);
    try std.testing.expectEqualStrings(config.default_output_value, cfg.default_output);
}

test "config command validates team selection" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    const response =
        \\{
        \\  "data": {
        \\    "teams": {
        \\      "nodes": [
        \\        { "id": "team-id-1", "key": "ENG" }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    try server.set("TeamLookup", response);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{ "set", "default_team_id", "ENG" };
    var runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("ENG", cfg.default_team_id);
    const cached = cfg.lookupTeamId("ENG") orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("team-id-1", cached);

    var reloaded = try config.load(allocator, config_path);
    defer reloaded.deinit();
    const persisted = reloaded.lookupTeamId("ENG") orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("team-id-1", persisted);
}

test "config command rejects unknown team" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    const response = "{\"data\":{\"teams\":{\"nodes\":[]}}}";
    try server.set("TeamLookup", response);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{ "set", "default_team_id", "MISSING" };
    var runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "team 'MISSING' not found") != null);
    try std.testing.expectEqual(@as(usize, 0), cfg.default_team_id.len);
}

test "config command unsets state filter" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var set_args = [_][]const u8{ "set", "default_state_filter", "backlog" };
    var runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = set_args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const set_capture = try captureOutput(allocator, &runner, runConfig);
    defer set_capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), set_capture.exit_code);
    try std.testing.expectEqual(@as(usize, 1), cfg.default_state_filter.len);
    try std.testing.expectEqualStrings("backlog", cfg.default_state_filter[0]);

    var unset_args = [_][]const u8{ "unset", "default_state_filter" };
    runner.ctx.args = unset_args[0..];
    const unset_capture = try captureOutput(allocator, &runner, runConfig);
    defer unset_capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), unset_capture.exit_code);
    try std.testing.expectEqual(config.default_state_filter_value.len, cfg.default_state_filter.len);
    for (cfg.default_state_filter, 0..) |entry, idx| {
        try std.testing.expectEqualStrings(config.default_state_filter_value[idx], entry);
    }
}

test "config command unsets default output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var set_args = [_][]const u8{ "set", "default_output", "json" };
    var runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = set_args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const set_capture = try captureOutput(allocator, &runner, runConfig);
    defer set_capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), set_capture.exit_code);
    try std.testing.expectEqualStrings("json", cfg.default_output);

    var unset_args = [_][]const u8{ "unset", "default_output" };
    runner.ctx.args = unset_args[0..];
    const unset_capture = try captureOutput(allocator, &runner, runConfig);
    defer unset_capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), unset_capture.exit_code);
    try std.testing.expectEqualStrings(config.default_output_value, cfg.default_output);

    var reloaded = try config.load(allocator, config_path);
    defer reloaded.deinit();
    try std.testing.expectEqualStrings(config.default_output_value, reloaded.default_output);
}

test "config command unsets default team id" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setApiKey("test-key");
    try cfg.setDefaultTeamId("TEAM-123");

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{ "unset", "default_team_id" };
    const runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = false,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqual(@as(usize, 0), cfg.default_team_id.len);

    var reloaded = try config.load(allocator, config_path);
    defer reloaded.deinit();
    try std.testing.expectEqual(@as(usize, 0), reloaded.default_team_id.len);
}

test "config show returns json" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(config_path);

    var cfg = try config.load(allocator, config_path);
    defer cfg.deinit();
    try cfg.setDefaultTeamId("ENG");
    try cfg.setDefaultOutput("json");
    const states = [_][]const u8{ "backlog", "started" };
    try cfg.setStateFilterValues(states[0..]);

    const Runner = struct { ctx: config_cmd.Context };
    const runConfig = struct {
        pub fn call(r: *const Runner) !u8 {
            return config_cmd.run(r.ctx);
        }
    }.call;

    var args = [_][]const u8{"show"};
    const runner = Runner{ .ctx = .{
        .allocator = allocator,
        .config = &cfg,
        .args = args[0..],
        .json_output = true,
        .config_path = config_path,
        .retries = 0,
        .timeout_ms = 10_000,
    } };

    const capture = try captureOutput(allocator, &runner, runConfig);
    defer capture.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;

    const config_path_value = obj.get("config_path") orelse return error.TestExpectedResult;
    try std.testing.expect(config_path_value == .string);
    try std.testing.expectEqualStrings(config_path, config_path_value.string);

    const team_value = obj.get("default_team_id") orelse return error.TestExpectedResult;
    try std.testing.expect(team_value == .string);
    try std.testing.expectEqualStrings("ENG", team_value.string);

    const output_value = obj.get("default_output") orelse return error.TestExpectedResult;
    try std.testing.expect(output_value == .string);
    try std.testing.expectEqualStrings("json", output_value.string);

    const state_value = obj.get("default_state_filter") orelse return error.TestExpectedResult;
    try std.testing.expect(state_value == .array);
    try std.testing.expectEqual(@as(usize, 2), state_value.array.items.len);
    try std.testing.expect(state_value.array.items[0] == .string);
    try std.testing.expect(state_value.array.items[1] == .string);
    try std.testing.expectEqualStrings("backlog", state_value.array.items[0].string);
    try std.testing.expectEqualStrings("started", state_value.array.items[1].string);
}

test "parse gql options" {
    const args = [_][]const u8{ "--query", "file.graphql", "--vars", "{\"a\":1}", "--data-only", "--fields", "data" };
    const opts = try gql.parseOptions(args[0..]);
    try std.testing.expect(opts.query_path != null);
    try std.testing.expect(opts.vars_json != null);
    try std.testing.expect(opts.data_only);
    try std.testing.expectEqualStrings("data", opts.fields.?);
}

test "parse search options" {
    const args = [_][]const u8{
        "agent",
        "--team",
        "ENG",
        "--fields",
        "title,comments,identifier",
        "--state-type",
        "backlog,started",
        "--assignee",
        "user-1",
        "--limit",
        "10",
        "--case-sensitive",
    };
    const opts = try search_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("agent", opts.query.?);
    try std.testing.expectEqualStrings("ENG", opts.team.?);
    try std.testing.expectEqualStrings("title,comments,identifier", opts.fields.?);
    try std.testing.expectEqualStrings("backlog,started", opts.state_type.?);
    try std.testing.expectEqualStrings("user-1", opts.assignee.?);
    try std.testing.expectEqual(@as(usize, 10), opts.limit);
    try std.testing.expect(opts.case_sensitive);
}

test "parse search rejects zero limit" {
    const args = [_][]const u8{ "query", "--limit", "0" };
    try std.testing.expectError(error.InvalidLimit, search_cmd.parseOptions(args[0..]));
}

test "parse search unknown flag errors" {
    const args = [_][]const u8{ "query", "--unknown" };
    try std.testing.expectError(error.UnknownFlag, search_cmd.parseOptions(args[0..]));
}

test "parse issues options" {
    const args = [_][]const u8{
        "--team",
        "TEAM",
        "--state-type",
        "todo,in_progress",
        "--state-id",
        "state-1",
        "--assignee",
        "user-1",
        "--label",
        "label-1",
        "--project",
        "proj-1",
        "--milestone",
        "ms-1",
        "--updated-since",
        "2024-01-01T00:00:00Z",
        "--sort",
        "updated:asc",
        "--limit",
        "5",
        "--max-items",
        "50",
        "--sub-limit",
        "3",
        "--cursor",
        "abc",
        "--pages",
        "2",
        "--fields",
        "identifier,title",
        "--include-projects",
        "--plain",
        "--no-truncate",
        "--human-time",
        "--quiet",
        "--data-only",
    };
    const opts = try issues_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("TEAM", opts.team.?);
    try std.testing.expectEqualStrings("todo,in_progress", opts.state_type.?);
    try std.testing.expectEqualStrings("state-1", opts.state_id.?);
    try std.testing.expectEqualStrings("user-1", opts.assignee.?);
    try std.testing.expectEqualStrings("label-1", opts.label.?);
    try std.testing.expectEqualStrings("proj-1", opts.project.?);
    try std.testing.expectEqualStrings("ms-1", opts.milestone.?);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", opts.updated_since.?);
    try std.testing.expect(opts.sort != null);
    try std.testing.expectEqualStrings("updated", @tagName(opts.sort.?.field));
    try std.testing.expectEqualStrings("asc", @tagName(opts.sort.?.direction));
    try std.testing.expectEqual(@as(usize, 5), opts.limit);
    try std.testing.expectEqual(@as(usize, 50), opts.max_items.?);
    try std.testing.expectEqual(@as(usize, 3), opts.sub_limit);
    try std.testing.expectEqualStrings("abc", opts.cursor.?);
    try std.testing.expectEqual(@as(usize, 2), opts.pages.?);
    try std.testing.expectEqualStrings("identifier,title", opts.fields.?);
    try std.testing.expect(opts.include_projects);
    try std.testing.expect(opts.plain);
    try std.testing.expect(opts.no_truncate);
    try std.testing.expect(opts.human_time);
    try std.testing.expect(!opts.all);
    try std.testing.expect(opts.quiet);
    try std.testing.expect(opts.data_only);
}

test "parse issue create options" {
    const args = [_][]const u8{ "--team", "team-1", "--title", "hello", "--priority", "2", "--labels", "a,b", "--quiet", "--data-only" };
    const opts = try issue_create_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("team-1", opts.team.?);
    try std.testing.expectEqualStrings("hello", opts.title.?);
    try std.testing.expect(opts.priority.? == 2);
    try std.testing.expect(opts.labels != null);
    try std.testing.expect(opts.quiet);
    try std.testing.expect(opts.data_only);
}

test "parse issue update options" {
    const args = [_][]const u8{
        "ENG-123",
        "--assignee",
        "me",
        "--parent",
        "ENG-100",
        "--state",
        "state-1",
        "--priority",
        "2",
        "--title",
        "Updated",
        "--description",
        "Updated description",
        "--yes",
        "--quiet",
    };
    const opts = try issue_update_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("ENG-123", opts.identifier.?);
    try std.testing.expectEqualStrings("me", opts.assignee.?);
    try std.testing.expectEqualStrings("ENG-100", opts.parent.?);
    try std.testing.expectEqualStrings("state-1", opts.state.?);
    try std.testing.expectEqual(@as(i64, 2), opts.priority.?);
    try std.testing.expectEqualStrings("Updated", opts.title.?);
    try std.testing.expectEqualStrings("Updated description", opts.description.?);
    try std.testing.expect(opts.yes);
    try std.testing.expect(opts.quiet);
}

test "parse issue update rejects unknown flag" {
    const args = [_][]const u8{ "ENG-123", "--unknown" };
    try std.testing.expectError(error.UnknownFlag, issue_update_cmd.parseOptions(args[0..]));
}

test "parse issue link options blocks" {
    const args = [_][]const u8{ "ENG-123", "--blocks", "ENG-456", "--yes" };
    const opts = try issue_link_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("ENG-123", opts.identifier.?);
    try std.testing.expectEqualStrings("ENG-456", opts.blocks.?);
    try std.testing.expect(opts.related == null);
    try std.testing.expect(opts.duplicate == null);
    try std.testing.expect(opts.yes);
}

test "parse issue link options related" {
    const args = [_][]const u8{ "ENG-123", "--related", "ENG-789", "--yes" };
    const opts = try issue_link_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("ENG-789", opts.related.?);
    try std.testing.expect(opts.blocks == null);
}

test "parse issue link options duplicate" {
    const args = [_][]const u8{ "ENG-123", "--duplicate", "ENG-100", "--yes" };
    const opts = try issue_link_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("ENG-100", opts.duplicate.?);
}

test "parse issue link rejects unknown flag" {
    const args = [_][]const u8{ "ENG-123", "--unknown" };
    try std.testing.expectError(error.UnknownFlag, issue_link_cmd.parseOptions(args[0..]));
}

test "parse project create options" {
    var args = [_][]const u8{
        "--name",
        "Roadmap",
        "--team",
        "ENG",
        "--description",
        "Desc",
        "--start-date",
        "2024-01-01",
        "--target-date",
        "2024-06-30",
        "--state",
        "started",
        "--yes",
        "--quiet",
        "--data-only",
    };
    const opts = try project_create_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("Roadmap", opts.name.?);
    try std.testing.expectEqualStrings("ENG", opts.team.?);
    try std.testing.expectEqualStrings("Desc", opts.description.?);
    try std.testing.expectEqualStrings("2024-01-01", opts.start_date.?);
    try std.testing.expectEqualStrings("2024-06-30", opts.target_date.?);
    try std.testing.expectEqualStrings("started", opts.state.?);
    try std.testing.expect(opts.yes);
    try std.testing.expect(opts.quiet);
    try std.testing.expect(opts.data_only);
}

test "parse project update options" {
    var args = [_][]const u8{ "proj_123", "--name", "New Name", "--description", "Updated", "--state", "started", "--yes", "--quiet", "--data-only" };
    const opts = try project_update_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("proj_123", opts.identifier.?);
    try std.testing.expectEqualStrings("New Name", opts.name.?);
    try std.testing.expectEqualStrings("Updated", opts.description.?);
    try std.testing.expectEqualStrings("started", opts.state.?);
    try std.testing.expect(opts.yes);
    try std.testing.expect(opts.quiet);
    try std.testing.expect(opts.data_only);
}

test "parse project issue modification options" {
    var args = [_][]const u8{ "proj_123", "ENG-42", "--yes", "--quiet", "--data-only" };
    const opts = try project_issues_cmd.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("proj_123", opts.project_id.?);
    try std.testing.expectEqualStrings("ENG-42", opts.issue_id.?);
    try std.testing.expect(opts.yes);
    try std.testing.expect(opts.quiet);
    try std.testing.expect(opts.data_only);
}

test "global flags parsed after subcommand" {
    const allocator = std.testing.allocator;
    var opts = cli.GlobalOptions{};
    const args = [_][]const u8{ "issues", "list", "--json", "--timeout-ms", "2000" };
    const cleaned = try cli.stripTrailingGlobals(allocator, args[0..], &opts);
    defer allocator.free(cleaned);

    try std.testing.expect(opts.json);
    try std.testing.expectEqual(@as(u32, 2000), opts.timeout_ms);
    try std.testing.expectEqual(@as(usize, 2), cleaned.len);
    try std.testing.expectEqualStrings("issues", cleaned[0]);
    try std.testing.expectEqualStrings("list", cleaned[1]);
}

test "endpoint flag parsed from globals" {
    var args = [_][]const u8{ "linear", "--endpoint", "http://localhost:3000/mock", "issues" };
    const parsed = try cli.parseGlobal(args[0..]);
    try std.testing.expect(parsed.opts.endpoint != null);
    try std.testing.expectEqualStrings("http://localhost:3000/mock", parsed.opts.endpoint.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.rest.len);
    try std.testing.expectEqualStrings("issues", parsed.rest[0]);
}

test "parseGlobal handles keepalive and version flags" {
    var args = [_][]const u8{ "linear", "--no-keepalive", "--version", "issues" };
    const parsed = try cli.parseGlobal(args[0..]);
    try std.testing.expect(!parsed.opts.keep_alive);
    try std.testing.expect(parsed.opts.version);
    try std.testing.expectEqualStrings("issues", parsed.rest[0]);
}

test "parseGlobal errors on missing value" {
    var args = [_][]const u8{ "linear", "--timeout-ms" };
    try std.testing.expectError(error.MissingValue, cli.parseGlobal(args[0..]));
}

test "parseGlobal errors on unknown flag" {
    var args = [_][]const u8{ "linear", "--bogus" };
    try std.testing.expectError(error.UnknownFlag, cli.parseGlobal(args[0..]));
}

test "stripTrailingGlobals stops at separator" {
    const allocator = std.testing.allocator;
    var opts = cli.GlobalOptions{};
    const args = [_][]const u8{ "issues", "--", "--json", "list" };
    const cleaned = try cli.stripTrailingGlobals(allocator, args[0..], &opts);
    defer allocator.free(cleaned);
    try std.testing.expectEqual(@as(usize, 3), cleaned.len);
    try std.testing.expectEqualStrings("issues", cleaned[0]);
    try std.testing.expectEqualStrings("--", cleaned[1]);
    try std.testing.expectEqualStrings("list", cleaned[2]);
    try std.testing.expect(opts.json);
}

test "printer issue table includes headers" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    const rows = [_]printer.IssueRow{
        .{
            .identifier = "ISS-1",
            .title = "Example",
            .state = "todo",
            .assignee = "None",
            .priority = "High",
            .parent = "",
            .sub_issues = "",
            .project = "",
            .milestone = "",
            .updated = "2024-05-10T12:00:00Z",
        },
    };

    try printer.printIssueTable(allocator, buffer.writer(allocator), &rows, printer.issue_default_fields[0..], .{});
    const output = buffer.items;
    try std.testing.expect(std.mem.startsWith(u8, output, "Identifier"));
    try std.testing.expect(std.mem.indexOf(u8, output, "ISS-1") != null);
}

test "printer key values plain includes trailing newline" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    const pairs = [_]printer.KeyValue{
        .{ .key = "id", .value = "ISS-1" },
        .{ .key = "title", .value = "Example" },
    };

    try printer.printKeyValuesPlain(buffer.writer(allocator), pairs[0..]);
    try std.testing.expectEqualStrings("id\tISS-1\ntitle\tExample\n", buffer.items);
}

test "printer issue table plain preserves long values" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    const long_title = "This is a very long issue title that should remain visible";
    const rows = [_]printer.IssueRow{
        .{
            .identifier = "ISS-99",
            .title = long_title,
            .state = "todo",
            .assignee = "None",
            .priority = "High",
            .parent = "",
            .sub_issues = "",
            .project = "",
            .milestone = "",
            .updated = "2024-05-10T12:00:00Z",
        },
    };

    const opts = printer.TableOptions{ .pad = false, .truncate = false };
    try printer.printIssueTable(allocator, buffer.writer(allocator), &rows, printer.issue_default_fields[0..], opts);
    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "...") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, long_title) != null);
}

test "human time renders relative days" {
    const allocator = std.testing.allocator;
    const formatted = try printer.humanTime(allocator, "1970-01-02T00:00:00Z", 86400 * 3);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("2d ago", formatted);
}

test "printJsonFields filters root object" {
    const allocator = std.testing.allocator;
    var obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer obj.object.deinit();
    try obj.object.put("a", .{ .string = "1" });
    try obj.object.put("b", .{ .string = "2" });

    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try printer.printJsonFields(obj, &out.writer, true, &.{"b"});
    try std.testing.expectEqualStrings("{\n  \"b\": \"2\"\n}\n", out.written());
}

test "gql fields filter data without data-only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var query_file = try tmp.dir.createFile("viewer.graphql", .{ .read = true, .truncate = true });
    defer query_file.close();
    try query_file.writeAll("query Viewer { viewer { id name email } }");
    const query_path = try tmp.dir.realpathAlloc(allocator, "viewer.graphql");
    defer allocator.free(query_path);

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Viewer", fixtures.viewer_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
        query: []const u8,
    };
    const runGql = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "--query",
                r.query,
                "--operation-name",
                "Viewer",
                "--fields",
                "viewer",
            };
            return gql.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .json_output = false,
                .retries = 0,
                .timeout_ms = 10_000,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg, .query = query_path };

    const capture = try captureOutput(allocator, &runner, runGql);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    const expected =
        \\{
        \\  "viewer": {
        \\    "id": "user-1",
        \\    "name": "Offline User",
        \\    "email": "offline@example.com"
        \\  }
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(expected, capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "gql enforces mutually exclusive vars options" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var query_file = try tmp.dir.createFile("query.graphql", .{ .read = true, .truncate = true });
    defer query_file.close();
    try query_file.writeAll("query Viewer { viewer { id } }");
    const query_path = try tmp.dir.realpathAlloc(allocator, "query.graphql");
    defer allocator.free(query_path);
    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
        query: []const u8,
    };
    const runGql = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "--query",
                r.query,
                "--vars",
                "{}",
                "--vars-file",
                "vars.json",
            };
            return gql.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .json_output = false,
                .retries = 0,
                .timeout_ms = 10_000,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg, .query = query_path };

    const capture = try captureOutput(allocator, &runner, runGql);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "only one of --vars") != null);
}

test "gql data-only requires data field" {
    const allocator = std.testing.allocator;
    const missing_data = "{}";
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var query_file = try tmp.dir.createFile("query.graphql", .{ .read = true, .truncate = true });
    defer query_file.close();
    try query_file.writeAll("query Viewer { viewer { id } }");
    const query_path = try tmp.dir.realpathAlloc(allocator, "query.graphql");
    defer allocator.free(query_path);

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Viewer", missing_data);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
        query: []const u8,
    };
    const runGql = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--query", r.query, "--data-only", "--operation-name", "Viewer" };
            return gql.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .json_output = false,
                .retries = 0,
                .timeout_ms = 10_000,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg, .query = query_path };

    const capture = try captureOutput(allocator, &runner, runGql);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "response did not include a data field") != null);
}

test "parse issues all without pages" {
    const args = [_][]const u8{"--all"};
    const opts = try issues_cmd.parseOptions(args[0..]);
    try std.testing.expect(opts.all);
    try std.testing.expect(opts.pages == null);
}

test "parse issues pages/all conflict" {
    const args = [_][]const u8{ "--pages", "1", "--all" };
    try std.testing.expectError(error.ConflictingPageFlags, issues_cmd.parseOptions(args[0..]));
}

test "parse issues rejects zero limit" {
    const args = [_][]const u8{ "--limit", "0" };
    try std.testing.expectError(error.InvalidLimit, issues_cmd.parseOptions(args[0..]));
}

test "parse issues unknown flag errors" {
    const args = [_][]const u8{"--unknown"};
    try std.testing.expectError(error.UnknownFlag, issues_cmd.parseOptions(args[0..]));
}

fn setEnvValue(value: []const u8, allocator: std.mem.Allocator) !void {
    try setEnvPair(env_name_z, value, allocator);
}

fn clearEnv() void {
    clearEnvVar(env_name_z);
    clearEnvVar(config_env_name_z);
}

fn setConfigEnvValue(value: []const u8, allocator: std.mem.Allocator) !void {
    try setEnvPair(config_env_name_z, value, allocator);
}

fn setEnvPair(name_z: [*:0]const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    var buf = try allocator.alloc(u8, value.len + 1);
    defer allocator.free(buf);
    std.mem.copyForwards(u8, buf[0..value.len], value);
    buf[value.len] = 0;
    _ = c.setenv(name_z, buf.ptr, 1);
}

fn clearEnvVar(name_z: [*:0]const u8) void {
    _ = c.unsetenv(name_z);
}

fn restoreEnv(name_z: [*:0]const u8, previous: ?[]u8, allocator: std.mem.Allocator) void {
    if (previous) |value| {
        setEnvPair(name_z, value, allocator) catch {};
        allocator.free(value);
    } else {
        clearEnvVar(name_z);
    }
}

fn makeTestConfig(allocator: std.mem.Allocator) !config.Config {
    var cfg = config.Config{ .allocator = allocator };
    cfg.team_cache = std.StringHashMap([]const u8).init(allocator);
    try cfg.setApiKey("test-key");
    try cfg.setDefaultTeamId("test-team-id");
    return cfg;
}

const Capture = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,

    pub fn deinit(self: Capture, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn captureOutput(allocator: std.mem.Allocator, context: anytype, run_fn: anytype) !Capture {
    var stdout_pipe = try posix.pipe();
    defer if (stdout_pipe[0] != -1) posix.close(stdout_pipe[0]);
    defer if (stdout_pipe[1] != -1) posix.close(stdout_pipe[1]);

    var stderr_pipe = try posix.pipe();
    defer if (stderr_pipe[0] != -1) posix.close(stderr_pipe[0]);
    defer if (stderr_pipe[1] != -1) posix.close(stderr_pipe[1]);

    const saved_stdout = try posix.dup(posix.STDOUT_FILENO);
    const saved_stderr = try posix.dup(posix.STDERR_FILENO);
    defer posix.close(saved_stdout);
    defer posix.close(saved_stderr);

    try posix.dup2(stdout_pipe[1], posix.STDOUT_FILENO);
    try posix.dup2(stderr_pipe[1], posix.STDERR_FILENO);

    const exit_code = try run_fn(context);

    posix.dup2(saved_stdout, posix.STDOUT_FILENO) catch {};
    posix.dup2(saved_stderr, posix.STDERR_FILENO) catch {};

    posix.close(stdout_pipe[1]);
    stdout_pipe[1] = -1;
    posix.close(stderr_pipe[1]);
    stderr_pipe[1] = -1;

    const stdout_data = try readAll(allocator, stdout_pipe[0]);
    errdefer allocator.free(stdout_data);
    const stderr_data = try readAll(allocator, stderr_pipe[0]);
    errdefer allocator.free(stderr_data);

    return .{ .stdout = stdout_data, .stderr = stderr_data, .exit_code = exit_code };
}

fn readAll(allocator: std.mem.Allocator, fd: posix.fd_t) ![]u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    errdefer buffer.deinit(allocator);

    var tmp: [256]u8 = undefined;
    while (true) {
        const count = posix.read(fd, &tmp) catch |err| return err;
        if (count == 0) break;
        try buffer.appendSlice(allocator, tmp[0..count]);
    }

    return buffer.toOwnedSlice(allocator);
}

test "search renders table and warns about pagination with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("SearchIssues", fixtures.issues_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runSearch = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{"offline"};
            return search_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .json_output = false,
                .retries = 0,
                .timeout_ms = 10_000,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runSearch);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings(fixtures.issues_table, capture.stdout);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "pagination not implemented") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "cursor-2") != null);
}

test "search builds filters for selected fields" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Viewer", fixtures.viewer_response);
    try server.set("SearchIssues", fixtures.issues_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runSearch = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "Agent",
                "--team",
                "TEAM",
                "--fields",
                "title,comments",
                "--state-type",
                "backlog,started",
                "--assignee",
                "me",
                "--limit",
                "3",
                "--case-sensitive",
            };
            return search_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .json_output = true,
                .retries = 0,
                .timeout_ms = 10_000,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runSearch);
    defer capture.deinit(allocator);
    if (capture.exit_code != 0) {
        std.debug.print("search stdout: {s}\nstderr: {s}\n", .{ capture.stdout, capture.stderr });
    }
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("SearchIssues", recorded.operation);

    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;

    const first_value = root.object.get("first") orelse return error.TestExpectedResult;
    if (first_value != .integer) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i64, 3), first_value.integer);

    const filter = root.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;

    const or_value = filter.object.get("or") orelse return error.TestExpectedResult;
    if (or_value != .array) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 2), or_value.array.items.len);

    const title_entry = or_value.array.items[0];
    if (title_entry != .object) return error.TestExpectedResult;
    const title_filter = title_entry.object.get("title") orelse return error.TestExpectedResult;
    if (title_filter != .object) return error.TestExpectedResult;
    const contains_title = title_filter.object.get("contains") orelse return error.TestExpectedResult;
    if (contains_title != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Agent", contains_title.string);
    try std.testing.expect(title_filter.object.get("containsIgnoreCase") == null);

    const comments_entry = or_value.array.items[1];
    if (comments_entry != .object) return error.TestExpectedResult;
    const comments_filter = comments_entry.object.get("comments") orelse return error.TestExpectedResult;
    if (comments_filter != .object) return error.TestExpectedResult;
    const some_filter = comments_filter.object.get("some") orelse return error.TestExpectedResult;
    if (some_filter != .object) return error.TestExpectedResult;
    const body_filter = some_filter.object.get("body") orelse return error.TestExpectedResult;
    if (body_filter != .object) return error.TestExpectedResult;
    const body_contains = body_filter.object.get("contains") orelse return error.TestExpectedResult;
    if (body_contains != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Agent", body_contains.string);

    const state_filter = filter.object.get("state") orelse return error.TestExpectedResult;
    if (state_filter != .object) return error.TestExpectedResult;
    const type_filter = state_filter.object.get("type") orelse return error.TestExpectedResult;
    if (type_filter != .object) return error.TestExpectedResult;
    const in_filter = type_filter.object.get("in") orelse return error.TestExpectedResult;
    if (in_filter != .array) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 2), in_filter.array.items.len);
    if (in_filter.array.items[0] != .string) return error.TestExpectedResult;
    if (in_filter.array.items[1] != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("backlog", in_filter.array.items[0].string);
    try std.testing.expectEqualStrings("started", in_filter.array.items[1].string);

    const assignee_filter = filter.object.get("assignee") orelse return error.TestExpectedResult;
    if (assignee_filter != .object) return error.TestExpectedResult;
    const assignee_id = assignee_filter.object.get("id") orelse return error.TestExpectedResult;
    if (assignee_id != .object) return error.TestExpectedResult;
    const eq_assignee = assignee_id.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_assignee != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("user-1", eq_assignee.string);

    const team_filter = filter.object.get("team") orelse return error.TestExpectedResult;
    if (team_filter != .object) return error.TestExpectedResult;
    const team_key = team_filter.object.get("key") orelse return error.TestExpectedResult;
    if (team_key != .object) return error.TestExpectedResult;
    const team_eq = team_key.object.get("eq") orelse return error.TestExpectedResult;
    if (team_eq != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("TEAM", team_eq.string);
}

test "issues list renders table and warns about pagination with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "2" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings(fixtures.issues_table, capture.stdout);
    try std.testing.expectEqualStrings(fixtures.issues_pagination_stderr, capture.stderr);
}

test "issues list prints json output with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssuesJson = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssuesJson);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings(fixtures.issues_json, capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issues list data-only json includes sub-issues and project fields when enabled" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_with_subs_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "1", "--data-only", "--include-projects" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    if (capture.exit_code != 0) {
        std.debug.print("issues list stdout: {s}\nstderr: {s}\n", .{ capture.stdout, capture.stderr });
    }
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;
    const nodes_value = root.object.get("nodes") orelse return error.TestExpectedResult;
    if (nodes_value != .array) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), nodes_value.array.items.len);
    const first = nodes_value.array.items[0];
    if (first != .object) return error.TestExpectedResult;
    try std.testing.expect(first.object.get("sub_issue_identifiers") != null);
    try std.testing.expect(first.object.get("parent_identifier") != null);
    try std.testing.expect(first.object.get("project") != null);
    try std.testing.expect(first.object.get("milestone") != null);
    const page_info = root.object.get("pageInfo") orelse return error.TestExpectedResult;
    if (page_info != .object) return error.TestExpectedResult;
    const limit_value = root.object.get("limit") orelse return error.TestExpectedResult;
    if (limit_value != .integer) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i64, 1), limit_value.integer);
}

test "issues list data-only json hides sub-issues when disabled" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_with_subs_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "1", "--data-only", "--sub-limit", "0" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    if (capture.exit_code != 0) {
        std.debug.print("issues list stdout: {s}\nstderr: {s}\n", .{ capture.stdout, capture.stderr });
    }
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;
    const nodes_value = root.object.get("nodes") orelse return error.TestExpectedResult;
    if (nodes_value != .array) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), nodes_value.array.items.len);
    const first = nodes_value.array.items[0];
    if (first != .object) return error.TestExpectedResult;
    try std.testing.expect(first.object.get("sub_issue_identifiers") == null);
    try std.testing.expect(first.object.get("parent_identifier") == null);
    try std.testing.expect(first.object.get("project") == null);
    try std.testing.expect(first.object.get("milestone") == null);
    const page_info = root.object.get("pageInfo") orelse return error.TestExpectedResult;
    if (page_info != .object) return error.TestExpectedResult;
    const limit_value = root.object.get("limit") orelse return error.TestExpectedResult;
    if (limit_value != .integer) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i64, 1), limit_value.integer);
}

test "issues list warns when sub-issues truncated" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_with_subs_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "1", "--sub-limit", "1", "--quiet" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "sub-issues limited") != null);
}

test "issues list paginates across pages when multiple requests allowed" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.setSequence("Issues", &.{ fixtures.issues_response, fixtures.issues_page2_response });
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "3", "--pages", "2" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "LIN-101") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "LIN-102") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "LIN-103") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "across 2 page") != null);
}

test "issues list quiet prints identifiers only to stdout" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "2", "--quiet" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqualStrings("LIN-101\nLIN-102\n", capture.stdout);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "fetched 2 items") != null);
}

test "issues list honors max-items" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "2", "--max-items", "1", "--quiet" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqualStrings("LIN-101\n", capture.stdout);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "stopped after 1 items") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "more available") != null);
}

test "issues list applies created-since and project filters" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "--limit",
                "1",
                "--created-since",
                "2024-01-01T00:00:00Z",
                "--project",
                "proj-123",
            };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);
    if (capture.exit_code != 0) {
        std.debug.print("issues created-since stdout: {s}\nstderr: {s}\n", .{ capture.stdout, capture.stderr });
    }
    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expect(recorded.variables_json != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, recorded.variables_json.?, .{});
    defer parsed.deinit();
    const vars_root = parsed.value;
    if (vars_root != .object) return error.TestExpectedResult;
    const filter = vars_root.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;
    const created_at = filter.object.get("createdAt") orelse return error.TestExpectedResult;
    if (created_at != .object) return error.TestExpectedResult;
    const gt_value = created_at.object.get("gt") orelse return error.TestExpectedResult;
    if (gt_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", gt_value.string);

    const project = filter.object.get("project") orelse return error.TestExpectedResult;
    if (project != .object) return error.TestExpectedResult;
    const id_obj = project.object.get("id") orelse return error.TestExpectedResult;
    if (id_obj != .object) return error.TestExpectedResult;
    const eq_value = id_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("proj-123", eq_value.string);
}

test "issues list resolves assignee me before applying filter" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.setSequence("Viewer", &.{ fixtures.viewer_response, fixtures.viewer_response });
    try server.set("Issues", fixtures.issues_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--assignee", " me ", "--limit", "1" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const viewer_series = server.fixtures.getPtr("Viewer") orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), viewer_series.*.next);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Issues", recorded.operation);

    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars_root = parsed.value;
    if (vars_root != .object) return error.TestExpectedResult;

    const filter = vars_root.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;

    const assignee = filter.object.get("assignee") orelse return error.TestExpectedResult;
    if (assignee != .object) return error.TestExpectedResult;
    const id_obj = assignee.object.get("id") orelse return error.TestExpectedResult;
    if (id_obj != .object) return error.TestExpectedResult;
    const eq_value = id_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("user-1", eq_value.string);
}

test "issues list warns when sub-issues are truncated" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_with_subs_response);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "1", "--sub-limit", "1" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "sub-issues limited to 1") != null);
}

test "issues list warns on empty page" {
    const allocator = std.testing.allocator;
    const empty_payload =
        \\{
        \\  "data": {
        \\    "issues": {
        \\      "nodes": [],
        \\      "pageInfo": { "hasNextPage": true, "endCursor": "cursor-empty" }
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", empty_payload);
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--limit", "2" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "received empty page") != null);
}

test "issues list fails when team not found" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.team_lookup_empty);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runIssues = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--team", "missing-team" };
            return issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runIssues);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expectEqualStrings("", capture.stdout);
    try std.testing.expectEqualStrings("issues list: team 'missing-team' not found\n", capture.stderr);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("TeamLookup", recorded.operation);
}

test "teams list renders table with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Teams", fixtures.teams_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runTeams = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return teams_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runTeams);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings(fixtures.teams_table, capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "me prints viewer table with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Viewer", fixtures.viewer_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runViewer = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return me_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runViewer);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings(fixtures.viewer_table, capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue create succeeds with quiet output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueCreate", fixtures.issue_create_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "--team",
                "123e4567-e89b-12d3-a456-426614174000",
                "--title",
                "Example created issue",
                "--yes",
                "--quiet",
            };
            return issue_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("LIN-200\n", capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue create requires confirmation" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--team", "ENG", "--title", "Needs confirmation" };
            return issue_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "issue create reports user error" {
    const allocator = std.testing.allocator;
    const user_error =
        \\{
        \\  "data": {
        \\    "issueCreate": {
        \\      "success": false,
        \\      "issue": null,
        \\      "userError": "permission denied",
        \\      "lastSyncId": 0
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);
    try server.set("IssueCreate", user_error);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--team", "ENG", "--title", "Example created issue", "--yes" };
            return issue_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "permission denied") != null);
}

test "issue create data-only json output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);
    try server.set("IssueCreate", fixtures.issue_create_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--team", "ENG", "--title", "Example created issue", "--yes", "--data-only" };
            return issue_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    const expected =
        \\{
        \\  "identifier": "LIN-200",
        \\  "title": "Example created issue",
        \\  "url": "https://linear.app/example/issue/200"
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(expected, capture.stdout);
}

test "issue delete prints identifier and id" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDelete", fixtures.issue_delete_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-300", "--yes" };
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("Identifier: LIN-300\nID        : issue-del-1\n", capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue delete requires target" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDelete", fixtures.issue_delete_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "missing identifier") != null);
}

test "issue delete dry run validates without mutation" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDeleteLookup", fixtures.issue_delete_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-300", "--dry-run" };
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "dry run") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "LIN-300") != null);
}

test "issue delete dry run emits json" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDeleteLookup", fixtures.issue_delete_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-300", "--dry-run" };
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"dry_run\": true") != null);
}

test "issue delete data-only plain output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDelete", fixtures.issue_delete_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-300", "--yes", "--data-only" };
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.startsWith(u8, capture.stdout, "identifier\tLIN-300"));
}

test "issue delete reports failure" {
    const allocator = std.testing.allocator;
    const failure_payload =
        \\{
        \\  "data": {
        \\    "issueDelete": {
        \\      "success": false,
        \\      "entity": { "identifier": "LIN-300", "id": "issue-del-1" },
        \\      "lastSyncId": 0
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueDelete", failure_payload);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-300", "--yes" };
            return issue_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "delete failed") != null);
}

test "issue update succeeds with quiet output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--priority", "1", "--yes", "--quiet" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("LIN-123\n", capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue update requires confirmation" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--priority", "1" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "issue update requires at least one field" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--yes" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "at least one field") != null);
}

test "issue update with assignee me resolves viewer" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    // The viewer query runs first to resolve "me", then the update mutation
    try server.set("Viewer", fixtures.viewer_response);
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--assignee", "me", "--yes", "--quiet" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("LIN-123\n", capture.stdout);
}

test "issue update reports user error" {
    const allocator = std.testing.allocator;
    const user_error =
        \\{
        \\  "data": {
        \\    "issueUpdate": {
        \\      "success": false,
        \\      "issue": null,
        \\      "userError": "permission denied"
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", user_error);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--priority", "1", "--yes" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "permission denied") != null);
}

test "issue update resolves workflow state name" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueStateLookup", fixtures.issue_state_lookup_response);
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--state", "done", "--yes", "--quiet" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const state_value = input.object.get("stateId") orelse return error.TestExpectedResult;
    if (state_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("69525da9-b8a9-4f58-a7b9-4187aaf9e02a", state_value.string);
}

test "issue update reports missing workflow state name" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueStateLookup", fixtures.issue_state_lookup_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--state", "waiting", "--yes" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "state 'waiting' not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "In Progress") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "Backlog") != null);
    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("IssueStateLookup", recorded.operation);
}

test "issue update data-only json output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--priority", "1", "--yes", "--data-only" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"identifier\": \"LIN-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"state\": \"In Progress\"") != null);
}

test "issue link succeeds with quiet output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("IssueRelationCreate", fixtures.issue_link_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--blocks", "LIN-456", "--yes", "--quiet" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("relation-1\n", capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue link requires confirmation" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--blocks", "LIN-456" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "issue link requires exactly one relation type" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--yes" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "exactly one of --blocks") != null);
}

test "issue link rejects multiple relation types" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--blocks", "LIN-456", "--related", "LIN-789", "--yes" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "only one of --blocks") != null);
}

test "issue link data-only json output" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("IssueRelationCreate", fixtures.issue_link_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--blocks", "LIN-456", "--yes", "--data-only" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"id\": \"relation-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"type\": \"blocks\"") != null);
}

test "issue link reports user error" {
    const allocator = std.testing.allocator;
    const user_error =
        \\{
        \\  "data": {
        \\    "issueRelationCreate": {
        \\      "success": false,
        \\      "issueRelation": null,
        \\      "userError": "relation already exists"
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("IssueRelationCreate", user_error);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--blocks", "LIN-456", "--yes" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "relation already exists") != null);
}

test "issue link lookup trims identifiers and accepts direct target ids" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.setSequence("IssueLookup", &.{ fixtures.issue_lookup_response, fixtures.issue_lookup_response, fixtures.issue_lookup_response });

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ " ENG-123 ", "--related", "iss_target_123", "--yes" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "invalid issue identifier") == null);

    const lookup_series = server.fixtures.getPtr("IssueLookup") orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), lookup_series.*.next);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("IssueLookup", recorded.operation);

    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;

    const filter = root.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;

    const team_obj = filter.object.get("team") orelse return error.TestExpectedResult;
    if (team_obj != .object) return error.TestExpectedResult;
    const key_obj = team_obj.object.get("key") orelse return error.TestExpectedResult;
    if (key_obj != .object) return error.TestExpectedResult;
    const eq_key = key_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_key != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("ENG", eq_key.string);

    const number_obj = filter.object.get("number") orelse return error.TestExpectedResult;
    if (number_obj != .object) return error.TestExpectedResult;
    const eq_number = number_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_number != .integer) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i64, 123), eq_number.integer);
}

test "issue link lookup validates target payload and accepts cuid ids" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.setSequence("IssueLookup", &.{ fixtures.issue_lookup_response, fixtures.issue_lookup_response, fixtures.issue_lookup_response });

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runLink = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ckopq3f5u00012qqqs64aqkef", "--blocks", " LIN-456 ", "--yes" };
            return issue_link_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runLink);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "invalid issue identifier") == null);

    const lookup_series = server.fixtures.getPtr("IssueLookup") orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), lookup_series.*.next);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("IssueLookup", recorded.operation);

    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;

    const filter = root.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;

    const team_obj = filter.object.get("team") orelse return error.TestExpectedResult;
    if (team_obj != .object) return error.TestExpectedResult;
    const key_obj = team_obj.object.get("key") orelse return error.TestExpectedResult;
    if (key_obj != .object) return error.TestExpectedResult;
    const eq_key = key_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_key != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("LIN", eq_key.string);

    const number_obj = filter.object.get("number") orelse return error.TestExpectedResult;
    if (number_obj != .object) return error.TestExpectedResult;
    const eq_number = number_obj.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_number != .integer) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i64, 456), eq_number.integer);
}

test "issue view filters fields" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-500", "--fields", "identifier,title", "--data-only" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("{\n  \"identifier\": \"LIN-500\",\n  \"title\": \"Example issue\"\n}\n", capture.stdout);
    try std.testing.expectEqualStrings("", capture.stderr);
}

test "issue view includes project and milestone fields" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_project);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-500", "--fields", "project,milestone", "--data-only" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;
    const project_field = root.object.get("project") orelse return error.TestExpectedResult;
    const milestone_field = root.object.get("milestone") orelse return error.TestExpectedResult;
    if (project_field != .string or milestone_field != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Offline Project", project_field.string);
    try std.testing.expectEqualStrings("Offline Milestone", milestone_field.string);
}

test "issue view requires identifier" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "missing identifier") != null);
}

test "issue view rejects invalid fields" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-500", "--fields", "unknown" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "invalid --fields") != null);
}

test "issue view quiet prints identifier" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-500", "--quiet" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("LIN-500\n", capture.stdout);
}

test "issue view reports missing issue" {
    const allocator = std.testing.allocator;
    const missing_payload =
        \\{
        \\  "data": {
        \\    "issue": null
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", missing_payload);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{"LIN-500"};
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "issue not found") != null);
}

test "issue view includes parent and sub-issues with limit" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_relations);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-600", "--fields", "identifier,parent,sub_issues", "--data-only", "--sub-limit", "1" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;
    const parent_field = root.object.get("parent") orelse return error.TestExpectedResult;
    if (parent_field != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("LIN-500", parent_field.string);
    const subs_field = root.object.get("sub_issue_identifiers") orelse return error.TestExpectedResult;
    if (subs_field != .string) return error.TestExpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, subs_field.string, "LIN-601") != null);
    try std.testing.expect(subs_field.string.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "sub-issues limited") != null);
}

test "issue view includes comments with limit" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueView", fixtures.issue_view_comments);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-700", "--fields", "identifier,comments", "--data-only", "--comment-limit", "1" };
            return issue_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, capture.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.TestExpectedResult;
    const comments_field = root.object.get("comments") orelse return error.TestExpectedResult;
    if (comments_field != .array) return error.TestExpectedResult;
    try std.testing.expect(comments_field.array.items.len > 0);
    const first_comment = comments_field.array.items[0];
    if (first_comment != .object) return error.TestExpectedResult;
    const body_field = first_comment.object.get("body") orelse return error.TestExpectedResult;
    if (body_field != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("First comment body", body_field.string);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "comments limited") != null);
}

test "project create uses teamIds array" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);
    try server.set("ProjectCreate", fixtures.project_create_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--name", "New Project", "--team", "ENG", "--yes" };
            return project_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("ProjectCreate", recorded.operation);
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const team_ids = input.object.get("teamIds") orelse return error.TestExpectedResult;
    if (team_ids != .array) return error.TestExpectedResult;
    try std.testing.expectEqual(@as(usize, 1), team_ids.array.items.len);
    const first = team_ids.array.items[0];
    if (first != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("team-id-123", first.string);
    try std.testing.expect(input.object.get("teamId") == null);
}

test "project create requires confirmation" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("TeamLookup", fixtures.issue_create_team_lookup);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--name", "New Project", "--team", "ENG" };
            return project_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "projects list renders rows and warns about pagination" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Projects", fixtures.projects_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runProjects = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{};
            return projects_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runProjects);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "Roadmap") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "API revamp") != null);
    try std.testing.expectEqualStrings("projects list: more projects available; pagination not implemented (endCursor cursor-123)\n", capture.stderr);
}

test "projects list maps state filter to status id" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("ProjectStatuses", fixtures.project_statuses_response);
    try server.set("Projects", fixtures.projects_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runProjects = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--state", "started" };
            return projects_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runProjects);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Projects", recorded.operation);
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const filter = vars.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;
    const status_filter = filter.object.get("status") orelse return error.TestExpectedResult;
    if (status_filter != .object) return error.TestExpectedResult;
    const id_filter = status_filter.object.get("id") orelse return error.TestExpectedResult;
    if (id_filter != .object) return error.TestExpectedResult;
    const eq_value = id_filter.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("status_started", eq_value.string);
    try std.testing.expect(filter.object.get("statusId") == null);
    try std.testing.expect(filter.object.get("state") == null);
}

test "projects list maps team filter to accessibleTeams some filter" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Projects", fixtures.projects_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runProjects = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "--team", "ENG" };
            return projects_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runProjects);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Projects", recorded.operation);
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const filter = vars.object.get("filter") orelse return error.TestExpectedResult;
    if (filter != .object) return error.TestExpectedResult;
    const teams_filter = filter.object.get("accessibleTeams") orelse return error.TestExpectedResult;
    if (teams_filter != .object) return error.TestExpectedResult;
    const some_filter = teams_filter.object.get("some") orelse return error.TestExpectedResult;
    if (some_filter != .object) return error.TestExpectedResult;
    const key_filter = some_filter.object.get("key") orelse return error.TestExpectedResult;
    if (key_filter != .object) return error.TestExpectedResult;
    const eq_value = key_filter.object.get("eq") orelse return error.TestExpectedResult;
    if (eq_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("ENG", eq_value.string);
    try std.testing.expect(filter.object.get("team") == null);
}

test "project view prints teams and truncated issues warning" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("ProjectView", fixtures.project_view_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runView = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "proj_123", "--fields", "name,teams,issues", "--issue-limit", "1" };
            return project_view_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runView);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "Roadmap") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "ENG (Engineering), DS (Data Science)") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "ENG-10 Kickoff, ENG-20 Ship v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "issues limited to 1") != null);
}

test "project update requires at least one field" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{"proj_123"};
            return project_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "at least one field") != null);
}

test "project update quiet output and payload" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("ProjectStatuses", fixtures.project_statuses_response);
    try server.set("ProjectUpdate", fixtures.project_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "proj_123", "--name", "Renamed Roadmap", "--state", "started", "--yes", "--quiet" };
            return project_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("roadmap\n", capture.stdout);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const name_value = input.object.get("name") orelse return error.TestExpectedResult;
    if (name_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("Renamed Roadmap", name_value.string);
    const status_id_value = input.object.get("statusId") orelse return error.TestExpectedResult;
    if (status_id_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("status_started", status_id_value.string);
    try std.testing.expect(input.object.get("description") == null);
}

test "project delete requires confirmation" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{"proj_123"};
            return project_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "project delete prints archive message" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("ProjectDelete", fixtures.project_delete_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runDelete = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "proj_123", "--yes" };
            return project_delete_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runDelete);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expectEqualStrings("project delete: archived proj_123\n", capture.stdout);
}

test "project add-issue sets project id" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.project_add_issue_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runAdd = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "add-issue", "proj_123", "ENG-42", "--yes" };
            return project_issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runAdd);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "Roadmap") != null);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const project_value = input.object.get("projectId") orelse return error.TestExpectedResult;
    if (project_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("proj_123", project_value.string);
}

test "project remove-issue clears project id" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.project_remove_issue_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runRemove = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "remove-issue", "proj_123", "ENG-42", "--yes", "--data-only" };
            return project_issues_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runRemove);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "\"project\": \"proj_123\"") != null);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const project_value = input.object.get("projectId") orelse return error.TestExpectedResult;
    try std.testing.expect(project_value == .null);
}

test "issue create sets projectId when provided" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueCreate", fixtures.issue_create_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runCreate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{
                "--team",
                "123e4567-e89b-12d3-a456-426614174000",
                "--title",
                "Example created issue",
                "--project",
                "proj_123",
                "--yes",
            };
            return issue_create_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runCreate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const project_value = input.object.get("projectId") orelse return error.TestExpectedResult;
    if (project_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("proj_123", project_value.string);
}

test "issue update sets projectId when provided" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--project", "proj_123", "--yes", "--quiet" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const project_value = input.object.get("projectId") orelse return error.TestExpectedResult;
    if (project_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("proj_123", project_value.string);
}

test "issue update sets description when provided" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueUpdate", fixtures.issue_update_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runUpdate = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "LIN-123", "--description", "New description", "--yes", "--quiet" };
            return issue_update_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runUpdate);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);

    const recorded = server.lastRequest() orelse return error.TestExpectedResult;
    const vars_json = recorded.variables_json orelse return error.TestExpectedResult;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, vars_json, .{});
    defer parsed.deinit();
    const vars = parsed.value;
    if (vars != .object) return error.TestExpectedResult;
    const input = vars.object.get("input") orelse return error.TestExpectedResult;
    if (input != .object) return error.TestExpectedResult;
    const description_value = input.object.get("description") orelse return error.TestExpectedResult;
    if (description_value != .string) return error.TestExpectedResult;
    try std.testing.expectEqualStrings("New description", description_value.string);
}

test "graphql client reuses shared http client across instances" {
    const allocator = std.testing.allocator;

    var first = graphql.GraphqlClient.init(allocator, "test-key");
    const first_http = first.http_client;
    first.deinit();

    defer graphql.deinitSharedClient();
    var second = graphql.GraphqlClient.init(allocator, "test-key");
    defer second.deinit();

    try std.testing.expect(first_http == second.http_client);
}

test "graphql client refreshes tls certs when reused" {
    const allocator = std.testing.allocator;

    var first = graphql.GraphqlClient.init(allocator, "test-key");
    const shared = first.http_client;
    @atomicStore(bool, &shared.next_https_rescan_certs, false, .release);
    first.deinit();

    defer graphql.deinitSharedClient();
    var second = graphql.GraphqlClient.init(allocator, "test-key");
    defer second.deinit();

    try std.testing.expect(@atomicLoad(bool, &second.http_client.next_https_rescan_certs, .acquire));
}

test "graphql client uses configured keep alive setting" {
    const allocator = std.testing.allocator;
    const previous = graphql.getDefaultKeepAlive();
    graphql.setDefaultKeepAlive(false);
    defer graphql.setDefaultKeepAlive(previous);
    defer graphql.deinitSharedClient();

    var client = graphql.GraphqlClient.init(allocator, "test-key");
    defer client.deinit();

    try std.testing.expect(!client.keep_alive);
}

test "issue comment succeeds with body" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("CommentCreate", fixtures.comment_create_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--body", "Test comment", "--yes" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "ENG-123") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture.stdout, "comment-1") != null);
}

test "issue comment reports user error" {
    const allocator = std.testing.allocator;
    const user_error =
        \\{
        \\  "data": {
        \\    "commentCreate": {
        \\      "success": false,
        \\      "comment": null,
        \\      "userError": "permission denied"
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("CommentCreate", user_error);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--body", "Test comment", "--yes" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "permission denied") != null);
}

test "issue comment fails with json output when success is false" {
    const allocator = std.testing.allocator;
    const user_error =
        \\{
        \\  "data": {
        \\    "commentCreate": {
        \\      "success": false,
        \\      "comment": null,
        \\      "userError": "rate limited"
        \\    }
        \\  }
        \\}
    ;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);
    try server.set("CommentCreate", user_error);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--body", "Test comment", "--yes" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = true,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    // Key assertion: even with json_output=true, exit code is 1 when success is false
    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "rate limited") != null);
}

test "issue comment requires confirmation" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("IssueLookup", fixtures.issue_lookup_response);

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--body", "Test comment" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "confirmation required") != null);
}

test "issue comment requires body or body-file" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--yes" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "--body or --body-file is required") != null);
}

test "issue comment rejects both body and body-file" {
    const allocator = std.testing.allocator;

    var cfg = try makeTestConfig(allocator);
    defer cfg.deinit();

    const Runner = struct {
        allocator: std.mem.Allocator,
        cfg: *config.Config,
    };
    const runComment = struct {
        pub fn call(r: *const Runner) !u8 {
            var args = [_][]const u8{ "ENG-123", "--body", "text", "--body-file", "file.md", "--yes" };
            return issue_comment_cmd.run(.{
                .allocator = r.allocator,
                .config = r.cfg,
                .args = args[0..],
                .retries = 0,
                .timeout_ms = 10_000,
                .json_output = false,
            });
        }
    }.call;
    const runner = Runner{ .allocator = allocator, .cfg = &cfg };

    const capture = try captureOutput(allocator, &runner, runComment);
    defer capture.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), capture.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capture.stderr, "cannot use both --body and --body-file") != null);
}

test "online viewer smoke (env gated)" {
    const allocator = std.testing.allocator;
    const run_online = std.process.getEnvVarOwned(allocator, "LINEAR_ONLINE_TESTS") catch null;
    defer if (run_online) |val| allocator.free(val);
    if (run_online == null) return;

    const api_key = std.process.getEnvVarOwned(allocator, "LINEAR_API_KEY") catch null;
    defer if (api_key) |val| allocator.free(val);
    if (api_key == null) return;

    defer graphql.deinitSharedClient();
    var client = graphql.GraphqlClient.init(allocator, api_key.?);
    defer client.deinit();

    const query = "query { viewer { id } }";
    var response = try client.send(allocator, .{
        .query = query,
        .variables = null,
        .operation_name = "Viewer",
    });
    defer response.deinit();

    try std.testing.expect(response.isSuccessStatus());
    try std.testing.expect(!response.hasGraphqlErrors());
}
