const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});
const env_name = "LINEAR_API_KEY";
const env_name_z = "LINEAR_API_KEY\x00";
const config = @import("config");
const gql = @import("gql");
const issues = @import("issues");
const issue_create = @import("issue_create");
const printer = @import("printer");
const graphql = @import("graphql");

test "config save and load roundtrip" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, env_name) catch null;
    defer {
        if (previous) |value| {
            setEnvValue(value, allocator) catch {};
            allocator.free(value);
        } else {
            clearEnv();
        }
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
    defer {
        if (previous) |value| {
            setEnvValue(value, allocator) catch {};
            allocator.free(value);
        } else {
            clearEnv();
        }
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

test "parse gql options" {
    const args = [_][]const u8{ "--query", "file.graphql", "--vars", "{\"a\":1}", "--data-only" };
    const opts = try gql.parseOptions(args[0..]);
    try std.testing.expect(opts.query_path != null);
    try std.testing.expect(opts.vars_json != null);
    try std.testing.expect(opts.data_only);
}

test "parse issues options" {
    const args = [_][]const u8{ "--team", "TEAM", "--state", "todo,in_progress", "--limit", "5" };
    const opts = try issues.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("TEAM", opts.team.?);
    try std.testing.expectEqual(@as(usize, 5), opts.limit);
    try std.testing.expect(opts.state != null);
}

test "parse issue create options" {
    const args = [_][]const u8{ "--team", "team-1", "--title", "hello", "--priority", "2", "--labels", "a,b" };
    const opts = try issue_create.parseOptions(args[0..]);
    try std.testing.expectEqualStrings("team-1", opts.team.?);
    try std.testing.expectEqualStrings("hello", opts.title.?);
    try std.testing.expect(opts.priority.? == 2);
    try std.testing.expect(opts.labels != null);
}

test "printer issue table includes headers" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const rows = [_]printer.IssueRow{
        .{
            .identifier = "ISS-1",
            .title = "Example",
            .state = "todo",
            .assignee = "None",
            .priority = "High",
            .updated = "2024-05-10T12:00:00Z",
        },
    };

    try printer.printIssueTable(allocator, buffer.writer(allocator), &rows);
    const output = buffer.items;
    try std.testing.expect(std.mem.startsWith(u8, output, "Identifier"));
    try std.testing.expect(std.mem.indexOf(u8, output, "ISS-1") != null);
}

fn setEnvValue(value: []const u8, allocator: std.mem.Allocator) !void {
    var buf = try allocator.alloc(u8, value.len + 1);
    defer allocator.free(buf);
    std.mem.copyForwards(u8, buf[0..value.len], value);
    buf[value.len] = 0;
    _ = c.setenv(env_name_z.ptr, buf.ptr, 1);
}

fn clearEnv() void {
    _ = c.unsetenv(env_name_z.ptr);
}

test "online viewer smoke (env gated)" {
    const allocator = std.testing.allocator;
    const run_online = std.process.getEnvVarOwned(allocator, "LINEAR_ONLINE_TESTS") catch null;
    defer if (run_online) |val| allocator.free(val);
    if (run_online == null) return;

    const api_key = std.process.getEnvVarOwned(allocator, "LINEAR_API_KEY") catch null;
    defer if (api_key) |val| allocator.free(val);
    if (api_key == null) return;

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
