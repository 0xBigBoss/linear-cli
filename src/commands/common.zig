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

pub fn checkResponse(prefix: []const u8, resp: *const graphql.GraphqlClient.Response, stderr: anytype, api_key: ?[]const u8) !void {
    if (!resp.isSuccessStatus()) {
        try stderr.print("{s}: HTTP status {d}\n", .{ prefix, resp.status });
        if (resp.firstErrorMessage()) |msg| {
            try stderr.print("{s}: {s}\n", .{ prefix, msg });
        }
        if (resp.status == 401) {
            if (api_key) |key| {
                var buf: [64]u8 = undefined;
                const redacted = redactKey(key, &buf);
                try stderr.print("{s}: unauthorized (key {s}); verify LINEAR_API_KEY or run 'linear auth set'\n", .{ prefix, redacted });
            } else {
                try stderr.print("{s}: unauthorized; verify LINEAR_API_KEY or run 'linear auth set'\n", .{prefix});
            }
        }
        try printRateLimit(prefix, resp.rate_limit, stderr);
        return CommandError.CommandFailed;
    }

    if (resp.hasGraphqlErrors()) {
        if (resp.firstErrorMessage()) |msg| {
            try stderr.print("{s}: {s}\n", .{ prefix, msg });
        } else {
            try stderr.print("{s}: GraphQL errors present\n", .{prefix});
        }
        try printRateLimit(prefix, resp.rate_limit, stderr);
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
        if (err == graphql.GraphqlClient.Error.RequestTimedOut) {
            try stderr.print("{s}: request timed out after {d}ms\n", .{ prefix, client.timeout_ms });
            return CommandError.CommandFailed;
        }
        try stderr.print("{s}: request failed: {s}\n", .{ prefix, @errorName(err) });
        return CommandError.CommandFailed;
    };
}

fn printRateLimit(prefix: []const u8, info: graphql.GraphqlClient.RateLimitInfo, stderr: anytype) !void {
    if (!info.hasData()) return;
    try stderr.print("{s}: rate limit:", .{prefix});

    var emitted = false;
    if (info.remaining) |remaining| {
        try stderr.print(" remaining {d}", .{remaining});
        if (info.limit) |limit| {
            try stderr.print("/{d}", .{limit});
        }
        emitted = true;
    } else if (info.limit) |limit| {
        try stderr.print(" limit {d}", .{limit});
        emitted = true;
    }

    if (info.retry_after_ms) |retry_ms| {
        try stderr.print("{s} retry after ~{d}ms", .{ if (emitted) ";" else "", retry_ms });
        emitted = true;
    }

    if (info.reset_epoch_ms) |reset_ms| {
        const now_ms_i64: i64 = std.time.milliTimestamp();
        const now_ms: u64 = if (now_ms_i64 > 0) @intCast(now_ms_i64) else 0;
        if (reset_ms > now_ms) {
            try stderr.print("{s} reset in ~{d}ms", .{ if (emitted) ";" else "", reset_ms - now_ms });
        } else {
            try stderr.print("{s} reset at {d}", .{ if (emitted) ";" else "", reset_ms });
        }
        emitted = true;
    }

    if (!emitted) return;
    try stderr.print("\n", .{});
}

pub fn redactKey(key: []const u8, buffer: []u8) []const u8 {
    if (buffer.len == 0 or key.len == 0) return "<redacted>";
    const head_len: usize = @min(key.len, 4);
    const tail_len: usize = if (key.len > head_len) @min(key.len - head_len, 4) else 0;

    return std.fmt.bufPrint(buffer, "{s}...{s}", .{
        key[0..head_len],
        if (tail_len > 0) key[key.len - tail_len ..] else "",
    }) catch "<redacted>";
}
