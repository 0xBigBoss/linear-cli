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
const cli = @import("cli");
const gql = @import("gql");
const issues_cmd = @import("issues_test");
const issue_create_cmd = @import("issue_create_test");
const issue_view_cmd = @import("issue_view_test");
const issue_delete_cmd = @import("issue_delete_test");
const me_cmd = @import("me_test");
const teams_cmd = @import("teams_test");
const printer = @import("printer");
const graphql = @import("graphql");
const mock_graphql = @import("graphql_mock");
const fixtures = struct {
    pub const issues_response = @embedFile("fixtures/issues.json");
    pub const issues_page2_response = @embedFile("fixtures/issues_page2.json");
    pub const issues_table = @embedFile("fixtures/issues_table.txt");
    pub const issues_json = @embedFile("fixtures/issues_json.txt");
    pub const issues_pagination_stderr = @embedFile("fixtures/issues_pagination_stderr.txt");
    pub const teams_response = @embedFile("fixtures/teams.json");
    pub const teams_table = @embedFile("fixtures/teams_table.txt");
    pub const viewer_response = @embedFile("fixtures/viewer.json");
    pub const viewer_table = @embedFile("fixtures/me_table.txt");
    pub const issue_create_team_lookup = @embedFile("fixtures/issue_create_team_lookup.json");
    pub const issue_create_response = @embedFile("fixtures/issue_create_response.json");
    pub const issue_delete_response = @embedFile("fixtures/issue_delete_response.json");
    pub const issue_view_response = @embedFile("fixtures/issue_view.json");
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

test "parse gql options" {
    const args = [_][]const u8{ "--query", "file.graphql", "--vars", "{\"a\":1}", "--data-only", "--fields", "data" };
    const opts = try gql.parseOptions(args[0..]);
    try std.testing.expect(opts.query_path != null);
    try std.testing.expect(opts.vars_json != null);
    try std.testing.expect(opts.data_only);
    try std.testing.expectEqualStrings("data", opts.fields.?);
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
        "--updated-since",
        "2024-01-01T00:00:00Z",
        "--sort",
        "updated:asc",
        "--limit",
        "5",
        "--cursor",
        "abc",
        "--pages",
        "2",
        "--fields",
        "identifier,title",
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
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", opts.updated_since.?);
    try std.testing.expect(opts.sort != null);
    try std.testing.expectEqualStrings("updated", @tagName(opts.sort.?.field));
    try std.testing.expectEqualStrings("asc", @tagName(opts.sort.?.direction));
    try std.testing.expectEqual(@as(usize, 5), opts.limit);
    try std.testing.expectEqualStrings("abc", opts.cursor.?);
    try std.testing.expectEqual(@as(usize, 2), opts.pages.?);
    try std.testing.expectEqualStrings("identifier,title", opts.fields.?);
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
    try cfg.setApiKey("test-key");
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

test "issues list renders table and warns about pagination with mock graphql" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.set("Issues", fixtures.issues_response);

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

test "issues list paginates across pages when multiple requests allowed" {
    const allocator = std.testing.allocator;

    var server = mock_graphql.MockServer.init(allocator);
    defer server.deinit();
    var scope = mock_graphql.useServer(&server);
    defer scope.restore();
    try server.setSequence("Issues", &.{ fixtures.issues_response, fixtures.issues_page2_response });

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
