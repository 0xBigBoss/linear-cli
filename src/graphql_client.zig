const std = @import("std");

const Allocator = std.mem.Allocator;

pub const GraphqlClient = struct {
    allocator: Allocator,
    api_key: []const u8,
    endpoint: []const u8 = "https://api.linear.app/graphql",
    http_client: *std.http.Client,
    keep_alive: bool,
    // TODO: make timeouts configurable when retry policy is added.
    timeout_ms: u32 = 10_000,
    max_retries: u8 = 0,

    pub const Options = struct {
        keep_alive: ?bool = null,
    };

    pub fn init(allocator: Allocator, api_key: []const u8) GraphqlClient {
        return initWithOptions(allocator, api_key, .{});
    }

    pub fn initWithOptions(allocator: Allocator, api_key: []const u8, options: Options) GraphqlClient {
        const http_client = shared_client.acquire(allocator);
        markTlsRefresh(http_client);
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .http_client = http_client,
            .keep_alive = options.keep_alive orelse keep_alive_preference.load(.acquire),
        };
    }

    pub fn deinit(self: *GraphqlClient) void {
        _ = self;
        shared_client.release();
    }

    pub const Request = struct {
        query: []const u8,
        variables: ?std.json.Value = null,
        operation_name: ?[]const u8 = null,
    };

    pub const Response = struct {
        status: u16,
        parsed: std.json.Parsed(std.json.Value),

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

    pub fn send(self: *GraphqlClient, allocator: Allocator, req: Request) !Response {
        const payload_bytes = try buildPayload(allocator, req);
        defer allocator.free(payload_bytes);

        var response_writer = std.io.Writer.Allocating.init(allocator);
        defer response_writer.deinit();

        var attempt: u8 = 0;
        const max_attempts: u8 = self.max_retries + 1;
        var fetch_result: std.http.Client.FetchResult = undefined;
        while (true) : (attempt += 1) {
            response_writer.clearRetainingCapacity();
            fetch_result = try self.http_client.fetch(.{
                .location = .{ .url = self.endpoint },
                .method = .POST,
                .payload = payload_bytes,
                .response_writer = &response_writer.writer,
                .keep_alive = self.keep_alive,
                .headers = .{
                    .authorization = .{ .override = self.api_key },
                    .content_type = .{ .override = "application/json" },
                },
                .extra_headers = &.{.{
                    .name = "Accept",
                    .value = "application/json",
                }},
            });

            const status_code: u16 = @intFromEnum(fetch_result.status);
            if (status_code >= 500 and attempt < max_attempts) {
                const delay_ns: u64 = 50_000_000 * (@as(u64, attempt));
                std.Thread.sleep(delay_ns);
                continue;
            }
            break;
        }

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_writer.writer.buffered(), .{});
        return .{
            .status = @intFromEnum(fetch_result.status),
            .parsed = parsed,
        };
    }
};

pub fn setDefaultKeepAlive(enabled: bool) void {
    keep_alive_preference.store(enabled, .release);
}

pub fn getDefaultKeepAlive() bool {
    return keep_alive_preference.load(.acquire);
}

pub fn deinitSharedClient() void {
    shared_client.shutdown();
}

const SharedHttpClient = struct {
    mutex: std.Thread.Mutex = .{},
    ref_count: usize = 0,
    client: ?std.http.Client = null,

    fn acquire(self: *SharedHttpClient, allocator: Allocator) *std.http.Client {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.client == null) {
            self.client = std.http.Client{ .allocator = allocator };
        }
        self.ref_count += 1;
        return &self.client.?;
    }

    fn release(self: *SharedHttpClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.client == null) return;
        std.debug.assert(self.ref_count > 0);
        self.ref_count -= 1;
    }

    fn shutdown(self: *SharedHttpClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.client == null) return;
        std.debug.assert(self.ref_count == 0);
        self.client.?.deinit();
        self.client = null;
    }
};

var shared_client: SharedHttpClient = .{};
var keep_alive_preference = std.atomic.Value(bool).init(true);

fn markTlsRefresh(client: *std.http.Client) void {
    @atomicStore(bool, &client.next_https_rescan_certs, true, .release);
}

fn buildPayload(allocator: Allocator, req: GraphqlClient.Request) ![]u8 {
    const Payload = struct {
        query: []const u8,
        variables: ?std.json.Value = null,
        operationName: ?[]const u8 = null,
    };

    const payload = Payload{
        .query = req.query,
        .variables = req.variables,
        .operationName = req.operation_name,
    };

    return std.json.Stringify.valueAlloc(allocator, payload, .{ .whitespace = .minified });
}
