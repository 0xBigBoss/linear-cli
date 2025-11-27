const std = @import("std");
const Allocator = std.mem.Allocator;

const RateLimitInfoInternal = struct {
    remaining: ?u32 = null,
    limit: ?u32 = null,
    retry_after_ms: ?u32 = null,
    reset_epoch_ms: ?u64 = null,

    pub fn hasData(self: RateLimitInfoInternal) bool {
        return self.remaining != null or self.limit != null or self.retry_after_ms != null or self.reset_epoch_ms != null;
    }
};

pub const MockResponse = struct {
    body: []const u8,
    status: u16 = 200,
    rate_limit: RateLimitInfoInternal = .{},
};

pub const MockServer = struct {
    allocator: Allocator,
    fixtures: std.StringHashMap(MockResponse),

    pub fn init(allocator: Allocator) MockServer {
        return .{
            .allocator = allocator,
            .fixtures = std.StringHashMap(MockResponse).init(allocator),
        };
    }

    pub fn deinit(self: *MockServer) void {
        var it = self.fixtures.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.body);
        }
        self.fixtures.deinit();
    }

    pub fn set(self: *MockServer, operation: []const u8, payload: []const u8) !void {
        try self.setWithStatus(operation, payload, 200);
    }

    pub fn setWithStatus(self: *MockServer, operation: []const u8, payload: []const u8, status: u16) !void {
        const duped = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(duped);

        if (try self.fixtures.fetchPut(operation, .{ .body = duped, .status = status })) |entry| {
            self.allocator.free(entry.value.body);
        }
    }

    fn lookup(self: *const MockServer, operation: []const u8) ?MockResponse {
        return self.fixtures.get(operation);
    }
};

threadlocal var active_server: ?*MockServer = null;

pub const ServerScope = struct {
    previous: ?*MockServer,

    pub fn restore(self: *ServerScope) void {
        active_server = self.previous;
    }
};

pub fn useServer(server: *MockServer) ServerScope {
    const previous = active_server;
    active_server = server;
    return .{ .previous = previous };
}

pub const GraphqlClient = struct {
    allocator: Allocator,
    api_key: []const u8,
    endpoint: []const u8 = "https://api.linear.app/graphql",
    keep_alive: bool = true,
    timeout_ms: u32 = 10_000,
    max_retries: u8 = 0,
    server: ?*MockServer,

    pub const Error = error{ RequestTimedOut, MockServerNotInstalled, MissingOperationName, MissingFixture };

    pub const RateLimitInfo = RateLimitInfoInternal;

    pub const Request = struct {
        query: []const u8,
        variables: ?std.json.Value = null,
        operation_name: ?[]const u8 = null,
    };

    pub const Response = struct {
        status: u16,
        parsed: std.json.Parsed(std.json.Value),
        rate_limit: RateLimitInfoInternal = .{},

        pub fn data(self: *const Response) ?std.json.Value {
            if (self.parsed.value != .object) return null;
            return self.parsed.value.object.get("data");
        }

        pub fn errors(self: *const Response) ?std.json.Value {
            if (self.parsed.value != .object) return null;
            return self.parsed.value.object.get("errors");
        }

        pub fn hasGraphqlErrors(self: *const Response) bool {
            if (self.errors()) |errs| {
                switch (errs) {
                    .array => |arr| return arr.items.len > 0,
                    .null => return false,
                    else => return true,
                }
            }
            return false;
        }

        pub fn firstErrorMessage(self: *const Response) ?[]const u8 {
            const errs = self.errors() orelse return null;
            switch (errs) {
                .array => |arr| {
                    for (arr.items) |item| {
                        if (item != .object) continue;
                        if (item.object.get("message")) |msg| {
                            if (msg == .string) return msg.string;
                        }
                    }
                },
                else => {},
            }
            return null;
        }

        pub fn isSuccessStatus(self: *const Response) bool {
            return self.status >= 200 and self.status < 300;
        }

        pub fn deinit(self: *Response) void {
            self.parsed.deinit();
        }
    };

    pub fn init(allocator: Allocator, api_key: []const u8) GraphqlClient {
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .server = active_server,
        };
    }

    pub fn deinit(self: *GraphqlClient) void {
        _ = self;
    }

    pub fn send(self: *GraphqlClient, allocator: Allocator, req: Request) !Response {
        const server = self.server orelse return Error.MockServerNotInstalled;
        const op_name = req.operation_name orelse return Error.MissingOperationName;
        const fixture = server.lookup(op_name) orelse return Error.MissingFixture;

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, fixture.body, .{});
        return .{
            .status = fixture.status,
            .parsed = parsed,
            .rate_limit = fixture.rate_limit,
        };
    }
};

pub fn loadFixture(allocator: Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 64 * 1024);
}
