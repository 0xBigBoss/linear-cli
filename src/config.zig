const std = @import("std");

const Allocator = std.mem.Allocator;

pub const default_team_id_value = "";
pub const default_output_value = "table";
pub const default_state_filter_value = [_][]const u8{ "completed", "canceled" };
const linear_api_key_env = "LINEAR_API_KEY";
const linear_config_env = "LINEAR_CONFIG";

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
    api_key_from_env: bool = false,
    permissions_warning: bool = false,
    config_path: ?[]const u8 = null,
    owned_config_path: bool = false,
    team_cache: std.StringHashMap([]const u8) = undefined,

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
        if (self.owned_config_path) {
            if (self.config_path) |path| self.allocator.free(path);
        }

        var it = self.team_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.team_cache.deinit();
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
            self.api_key_from_env = true;
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }
    }

    pub fn save(self: *const Config, allocator: Allocator, override_path: ?[]const u8) !void {
        const path = try resolveSavePath(self, allocator, override_path);
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

        if (self.api_key != null and !self.api_key_from_env) {
            try jw.objectField("api_key");
            try jw.write(self.api_key.?);
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

        if (self.team_cache.count() > 0) {
            try jw.objectField("team_cache");
            try jw.beginObject();
            var it = self.team_cache.iterator();
            while (it.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try jw.write(entry.value_ptr.*);
            }
            try jw.endObject();
        }

        try jw.endObject();
        try file.writeAll(json_buffer.writer.buffered());
    }

    pub fn setApiKey(self: *Config, value: []const u8) !void {
        if (self.owned_api_key) {
            if (self.api_key) |current| self.allocator.free(current);
        }
        self.api_key = try self.allocator.dupe(u8, value);
        self.owned_api_key = true;
        self.api_key_from_env = false;
    }

    pub fn setDefaultTeamId(self: *Config, value: []const u8) !void {
        try replaceRequiredString(self.allocator, &self.default_team_id, &self.owned_default_team_id, value);
    }

    pub fn resetDefaultTeamId(self: *Config) void {
        if (self.owned_default_team_id) {
            self.allocator.free(self.default_team_id);
            self.owned_default_team_id = false;
        }
        self.default_team_id = default_team_id_value;
    }

    pub fn setDefaultOutput(self: *Config, value: []const u8) !void {
        try replaceRequiredString(self.allocator, &self.default_output, &self.owned_default_output, value);
    }

    pub fn resetDefaultOutput(self: *Config) void {
        if (self.owned_default_output) {
            self.allocator.free(self.default_output);
            self.owned_default_output = false;
        }
        self.default_output = default_output_value;
    }

    pub fn resetStateFilter(self: *Config) void {
        if (self.owned_state_filter) {
            for (self.default_state_filter) |entry| self.allocator.free(entry);
            self.allocator.free(self.default_state_filter);
            self.owned_state_filter = false;
        }
        self.default_state_filter = &default_state_filter_value;
    }

    pub fn setStateFilterValues(self: *Config, values: []const []const u8) !void {
        var list = std.ArrayList([]const u8){};
        errdefer {
            for (list.items) |entry| self.allocator.free(entry);
            list.deinit(self.allocator);
        }

        for (values) |entry| {
            const duped = try self.allocator.dupe(u8, entry);
            try list.append(self.allocator, duped);
        }

        const new_filter = try list.toOwnedSlice(self.allocator);

        if (self.owned_state_filter) {
            for (self.default_state_filter) |entry| self.allocator.free(entry);
            self.allocator.free(self.default_state_filter);
        }

        self.default_state_filter = new_filter;
        self.owned_state_filter = true;
    }

    pub fn setStateFilter(self: *Config, value: std.json.Value) !void {
        const entries = switch (value) {
            .array => |arr| arr.items,
            else => return error.InvalidConfig,
        };

        var list = std.ArrayList([]const u8){};
        errdefer list.deinit(self.allocator);
        for (entries) |entry| {
            if (entry != .string) return error.InvalidConfig;
            try list.append(self.allocator, entry.string);
        }

        const items = list.items;
        const result = self.setStateFilterValues(items);
        list.deinit(self.allocator);
        return result;
    }

    pub fn cacheTeamId(self: *Config, key: []const u8, id: []const u8) !bool {
        if (self.team_cache.get(key)) |existing| {
            if (std.mem.eql(u8, existing, id)) return false;
        }

        const duped_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(duped_key);
        const duped_id = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(duped_id);

        if (try self.team_cache.fetchPut(duped_key, duped_id)) |replaced| {
            self.allocator.free(replaced.key);
            self.allocator.free(replaced.value);
        }
        return true;
    }

    pub fn lookupTeamId(self: *const Config, key: []const u8) ?[]const u8 {
        return self.team_cache.get(key);
    }
};

pub fn load(allocator: Allocator, override_path: ?[]const u8) !Config {
    var cfg = Config{ .allocator = allocator };
    cfg.team_cache = std.StringHashMap([]const u8).init(allocator);
    errdefer cfg.team_cache.deinit();

    const path = try resolvePath(allocator, override_path);
    cfg.config_path = path;
    cfg.owned_config_path = true;
    errdefer if (cfg.config_path) |p| allocator.free(p);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try cfg.applyEnvOverrides();
            return cfg;
        },
        else => return err,
    };
    defer file.close();

    const stat = file.stat() catch null;
    if (stat) |info| {
        const masked = info.mode & 0o777;
        if (masked != 0 and masked != 0o600) {
            cfg.permissions_warning = true;
        }
    }

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
        } else if (std.mem.eql(u8, key, "team_cache")) {
            if (value != .object) return error.InvalidConfig;
            var cache_it = value.object.iterator();
            while (cache_it.next()) |cache_entry| {
                if (cache_entry.value_ptr.* != .string) return error.InvalidConfig;
                _ = try cfg.cacheTeamId(cache_entry.key_ptr.*, cache_entry.value_ptr.*.string);
            }
        }
    }

    try cfg.applyEnvOverrides();
    return cfg;
}

fn resolvePath(allocator: Allocator, override_path: ?[]const u8) ![]u8 {
    if (override_path) |path| return allocator.dupe(u8, path);

    if (std.process.getEnvVarOwned(allocator, linear_config_env)) |value| {
        return value;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

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

fn resolveSavePath(self: *const Config, allocator: Allocator, override_path: ?[]const u8) ![]u8 {
    if (override_path) |path| return allocator.dupe(u8, path);
    if (self.config_path) |path| return allocator.dupe(u8, path);
    return resolvePath(allocator, null);
}
