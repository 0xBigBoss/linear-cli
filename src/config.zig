const std = @import("std");

const Allocator = std.mem.Allocator;

pub const default_team_id_value = "";
pub const default_output_value = "table";
pub const default_state_filter_value = [_][]const u8{ "completed", "canceled" };
const linear_api_key_env = "LINEAR_API_KEY";

pub const Config = struct {
    allocator: Allocator,
    api_key: ?[]const u8 = null,
    default_team_id: []const u8 = default_team_id_value,
    default_output: []const u8 = default_output_value,
    default_state_filter: []const []const u8 = &default_state_filter_value,

    owned_api_key: bool = false,
    owned_default_team_id: bool = false,
    owned_default_output: bool = false,
    owned_state_filter: bool = false,

    pub fn deinit(self: *Config) void {
        if (self.owned_api_key) {
            if (self.api_key) |key| self.allocator.free(key);
        }
        if (self.owned_default_team_id) {
            self.allocator.free(self.default_team_id);
        }
        if (self.owned_default_output) {
            self.allocator.free(self.default_output);
        }
        if (self.owned_state_filter) {
            for (self.default_state_filter) |entry| {
                self.allocator.free(entry);
            }
            self.allocator.free(self.default_state_filter);
        }
    }

    pub fn resolveApiKey(self: *Config, override_key: ?[]const u8) ![]const u8 {
        if (override_key) |key| return key;
        if (self.api_key) |key| return key;
        return error.MissingApiKey;
    }

    pub fn applyEnvOverrides(self: *Config) !void {
        if (std.process.getEnvVarOwned(self.allocator, linear_api_key_env)) |value| {
            defer self.allocator.free(value);
            try self.setApiKey(value);
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }
    }

    pub fn save(self: *const Config, allocator: Allocator, override_path: ?[]const u8) !void {
        const path = try resolvePath(allocator, override_path);
        defer allocator.free(path);

        if (std.fs.path.dirname(path)) |dir_path| {
            try std.fs.cwd().makePath(dir_path);
        }

        var file = try std.fs.cwd().createFile(path, .{
            .truncate = true,
            .read = true,
        });
        defer file.close();

        try file.setPermissions(.{ .inner = .{ .mode = 0o600 } });

        var json_buffer = std.io.Writer.Allocating.init(allocator);
        defer json_buffer.deinit();
        var jw = std.json.Stringify{ .writer = &json_buffer.writer, .options = .{ .whitespace = .indent_2 } };
        try jw.beginObject();

        if (self.api_key) |key| {
            try jw.objectField("api_key");
            try jw.write(key);
        }

        if (self.default_team_id.len != 0) {
            try jw.objectField("default_team_id");
            try jw.write(self.default_team_id);
        }

        if (self.default_output.len != 0) {
            try jw.objectField("default_output");
            try jw.write(self.default_output);
        }

        try jw.objectField("default_state_filter");
        try jw.beginArray();
        for (self.default_state_filter) |state| {
            try jw.write(state);
        }
        try jw.endArray();

        try jw.endObject();
        try file.writeAll(json_buffer.writer.buffered());
    }

    pub fn setApiKey(self: *Config, value: []const u8) !void {
        if (self.owned_api_key) {
            if (self.api_key) |current| self.allocator.free(current);
        }
        self.api_key = try self.allocator.dupe(u8, value);
        self.owned_api_key = true;
    }

    pub fn setDefaultTeamId(self: *Config, value: []const u8) !void {
        try replaceRequiredString(self.allocator, &self.default_team_id, &self.owned_default_team_id, value);
    }

    pub fn setDefaultOutput(self: *Config, value: []const u8) !void {
        try replaceRequiredString(self.allocator, &self.default_output, &self.owned_default_output, value);
    }

    pub fn setStateFilter(self: *Config, value: std.json.Value) !void {
        const entries = switch (value) {
            .array => |arr| arr.items,
            else => return error.InvalidConfig,
        };

        if (self.owned_state_filter) {
            for (self.default_state_filter) |entry| self.allocator.free(entry);
            self.allocator.free(self.default_state_filter);
        }

        var list = std.ArrayList([]const u8){};
        errdefer {
            for (list.items) |entry| self.allocator.free(entry);
            list.deinit(self.allocator);
        }

        for (entries) |entry| {
            if (entry != .string) return error.InvalidConfig;
            const duped = try self.allocator.dupe(u8, entry.string);
            try list.append(self.allocator, duped);
        }

        self.default_state_filter = try list.toOwnedSlice(self.allocator);
        self.owned_state_filter = true;
    }
};

pub fn load(allocator: Allocator, override_path: ?[]const u8) !Config {
    var cfg = Config{ .allocator = allocator };

    const path = try resolvePath(allocator, override_path);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try cfg.applyEnvOverrides();
            return cfg;
        },
        else => return err,
    };
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidConfig;

    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        if (std.mem.eql(u8, key, "api_key")) {
            if (value != .string) return error.InvalidConfig;
            try cfg.setApiKey(value.string);
        } else if (std.mem.eql(u8, key, "default_team_id")) {
            if (value != .string) return error.InvalidConfig;
            try cfg.setDefaultTeamId(value.string);
        } else if (std.mem.eql(u8, key, "default_output")) {
            if (value != .string) return error.InvalidConfig;
            try cfg.setDefaultOutput(value.string);
        } else if (std.mem.eql(u8, key, "default_state_filter")) {
            try cfg.setStateFilter(value);
        }
    }

    try cfg.applyEnvOverrides();
    return cfg;
}

fn resolvePath(allocator: Allocator, override_path: ?[]const u8) ![]u8 {
    if (override_path) |path| return allocator.dupe(u8, path);

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return error.MissingHome;
    };
    defer allocator.free(home);

    return std.fs.path.join(allocator, &.{ home, ".config", "linear", "config.json" });
}

fn replaceRequiredString(allocator: Allocator, target: *[]const u8, owned: *bool, value: []const u8) !void {
    if (owned.*) allocator.free(target.*);
    target.* = try allocator.dupe(u8, value);
    owned.* = true;
}
