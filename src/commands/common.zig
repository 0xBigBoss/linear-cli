const std = @import("std");
const config = @import("config");
const graphql = @import("graphql");
const Allocator = std.mem.Allocator;

pub const CommandError = error{CommandFailed};

pub fn requireApiKey(cfg: *config.Config, override_key: ?[]const u8, stderr: anytype, prefix: []const u8) ![]const u8 {
    const key = cfg.resolveApiKey(override_key) catch {
        try stderr.print("{s}: missing API key; set LINEAR_API_KEY or run 'linear auth set'\n", .{prefix});
        return CommandError.CommandFailed;
    };
    return key;
}

pub fn checkResponse(prefix: []const u8, resp: *const graphql.GraphqlClient.Response, stderr: anytype) !void {
    if (!resp.isSuccessStatus()) {
        try stderr.print("{s}: HTTP status {d}\n", .{ prefix, resp.status });
        if (resp.firstErrorMessage()) |msg| {
            try stderr.print("{s}: {s}\n", .{ prefix, msg });
        }
        if (resp.status == 401) {
            try stderr.print("{s}: unauthorized; verify LINEAR_API_KEY or run 'linear auth set'\n", .{prefix});
        }
        return CommandError.CommandFailed;
    }

    if (resp.hasGraphqlErrors()) {
        if (resp.firstErrorMessage()) |msg| {
            try stderr.print("{s}: {s}\n", .{ prefix, msg });
        } else {
            try stderr.print("{s}: GraphQL errors present\n", .{prefix});
        }
        return CommandError.CommandFailed;
    }
}

pub fn getStringField(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    if (value.object.get(key)) |found| {
        if (found == .string) return found.string;
    }
    return null;
}

pub fn getObjectField(value: std.json.Value, key: []const u8) ?std.json.Value {
    if (value != .object) return null;
    if (value.object.get(key)) |found| {
        if (found == .object) return found;
    }
    return null;
}

pub fn getArrayField(value: std.json.Value, key: []const u8) ?std.json.Array {
    if (value != .object) return null;
    if (value.object.get(key)) |found| {
        if (found == .array) return found.array;
    }
    return null;
}

pub fn getBoolField(value: std.json.Value, key: []const u8) ?bool {
    if (value != .object) return null;
    if (value.object.get(key)) |found| {
        if (found == .bool) return found.bool;
    }
    return null;
}

pub fn send(
    prefix: []const u8,
    client: *graphql.GraphqlClient,
    allocator: Allocator,
    req: graphql.GraphqlClient.Request,
    stderr: anytype,
) !graphql.GraphqlClient.Response {
    return client.send(allocator, req) catch |err| {
        try stderr.print("{s}: request failed: {s}\n", .{ prefix, @errorName(err) });
        return CommandError.CommandFailed;
    };
}
