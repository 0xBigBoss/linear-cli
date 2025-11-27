const std = @import("std");

const Allocator = std.mem.Allocator;

pub const GraphqlClient = struct {
    allocator: Allocator,
    api_key: []const u8,
    endpoint: []const u8 = "https://api.linear.app/graphql",
    http_client: std.http.Client,
    // TODO: make timeouts configurable when retry policy is added.
    timeout_ms: u32 = 10_000,
    max_retries: u8 = 0,

    pub fn init(allocator: Allocator, api_key: []const u8) GraphqlClient {
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *GraphqlClient) void {
        self.http_client.deinit();
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
