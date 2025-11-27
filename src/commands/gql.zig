const std = @import("std");
const config = @import("config");
const graphql = @import("graphql");
const printer = @import("printer");
const common = @import("common");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    allocator: Allocator,
    config: *config.Config,
    args: [][]const u8,
    json_output: bool,
    retries: u8,
    timeout_ms: u32,
};

const Options = struct {
    query_path: ?[]const u8 = null,
    vars_json: ?[]const u8 = null,
    vars_file: ?[]const u8 = null,
    data_only: bool = false,
    operation_name: ?[]const u8 = null,
    fields: ?[]const u8 = null,
    help: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("gql: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    if (opts.vars_json != null and opts.vars_file != null) {
        try stderr.print("gql: only one of --vars or --vars-file may be provided\n", .{});
        return 1;
    }

    const api_key = ctx.config.resolveApiKey(null) catch |err| {
        try stderr.print("gql: {s}\n", .{@errorName(err)});
        try stderr.print("set LINEAR_API_KEY or configure api_key in the config file\n", .{});
        return 1;
    };

    const query = try loadQuery(ctx.allocator, opts.query_path);
    defer ctx.allocator.free(query);

    var vars_parsed: ?std.json.Parsed(std.json.Value) = null;
    defer {
        if (vars_parsed) |*parsed| parsed.deinit();
    }

    var variables_value: ?std.json.Value = null;
    if (opts.vars_json) |inline_vars| {
        const parsed = try std.json.parseFromSlice(std.json.Value, ctx.allocator, inline_vars, .{});
        vars_parsed = parsed;
        variables_value = vars_parsed.?.value;
    } else if (opts.vars_file) |vars_path| {
        const vars_text = try readFile(ctx.allocator, vars_path);
        defer ctx.allocator.free(vars_text);

        const parsed = try std.json.parseFromSlice(std.json.Value, ctx.allocator, vars_text, .{});
        vars_parsed = parsed;
        variables_value = vars_parsed.?.value;
    }

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;

    var response = common.send("gql", &client, ctx.allocator, .{
        .query = query,
        .variables = variables_value,
        .operation_name = opts.operation_name,
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    var stdout_buf: [0]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const pretty = !ctx.json_output;
    var fields_buf = std.ArrayListUnmanaged([]const u8){};
    defer fields_buf.deinit(ctx.allocator);
    const selected_fields = parseFields(opts.fields, &fields_buf, ctx.allocator) catch |err| {
        const message = switch (err) {
            error.InvalidFieldList => "invalid --fields value",
            else => @errorName(err),
        };
        try stderr.print("gql: {s}\n", .{message});
        return 1;
    };

    if (opts.data_only) {
        if (response.data()) |data_value| {
            if (selected_fields) |fields| {
                printer.printJsonFields(data_value, &stdout_writer.interface, pretty, fields) catch |err| {
                    const message = switch (err) {
                        error.UnknownField => "requested field not found in response",
                        error.InvalidRoot => "fields can only target objects",
                        else => @errorName(err),
                    };
                    try stderr.print("gql: {s}\n", .{message});
                    return 1;
                };
            } else {
                try printer.printJson(data_value, &stdout_writer.interface, pretty);
            }
        } else {
            try stderr.print("gql: response did not include a data field\n", .{});
            return 1;
        }
    } else {
        if (selected_fields) |fields| {
            printer.printJsonFields(response.parsed.value, &stdout_writer.interface, pretty, fields) catch |err| {
                const message = switch (err) {
                    error.UnknownField => "requested field not found in response",
                    error.InvalidRoot => "fields can only target objects",
                    else => @errorName(err),
                };
                try stderr.print("gql: {s}\n", .{message});
                return 1;
            };
        } else {
            try printer.printJson(response.parsed.value, &stdout_writer.interface, pretty);
        }
    }

    if (!response.isSuccessStatus()) {
        try stderr.print("gql: HTTP status {d}\n", .{response.status});
        if (response.firstErrorMessage()) |msg| {
            try stderr.print("gql: {s}\n", .{msg});
        }
        return 1;
    }

    if (response.hasGraphqlErrors()) {
        if (response.firstErrorMessage()) |msg| {
            try stderr.print("gql: {s}\n", .{msg});
        }
        return 1;
    }

    return 0;
}

pub fn parseOptions(args: []const []const u8) !Options {
    var opts = Options{};
    var idx: usize = 0;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--query")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.query_path = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--query=")) {
            opts.query_path = arg["--query=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--vars")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.vars_json = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--vars=")) {
            opts.vars_json = arg["--vars=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--vars-file")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.vars_file = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--vars-file=")) {
            opts.vars_file = arg["--vars-file=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--data-only")) {
            opts.data_only = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--fields")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.fields = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--fields=")) {
            opts.fields = arg["--fields=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--operation-name")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.operation_name = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--operation-name=")) {
            opts.operation_name = arg["--operation-name=".len..];
            idx += 1;
            continue;
        }

        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        return error.UnexpectedArgument;
    }

    return opts;
}

fn parseFields(raw: ?[]const u8, buffer: *std.ArrayListUnmanaged([]const u8), allocator: Allocator) !?[]const []const u8 {
    if (raw) |value| {
        var iter = std.mem.tokenizeScalar(u8, value, ',');
        while (iter.next()) |entry| {
            const trimmed = std.mem.trim(u8, entry, " \t");
            if (trimmed.len == 0) continue;
            try buffer.append(allocator, trimmed);
        }
        if (buffer.items.len == 0) return error.InvalidFieldList;
        return buffer.items;
    }
    return null;
}

fn loadQuery(allocator: Allocator, path: ?[]const u8) ![]u8 {
    if (path) |query_path| {
        return readFile(allocator, query_path);
    }

    var reader = std.fs.File.stdin().deprecatedReader();
    return reader.readAllAlloc(allocator, 1024 * 1024);
}

fn readFile(allocator: Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024);
}

pub fn usage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: linear gql [--query FILE] [--vars JSON|--vars-file FILE] [--data-only] [--operation-name NAME] [--fields LIST] [--help]
        \\Flags:
        \\  --query FILE          Read GraphQL query from a file (default: stdin)
        \\  --vars JSON           Inline JSON variables
        \\  --vars-file FILE      Load JSON variables from a file
        \\  --data-only           Print only the data payload
        \\  --operation-name NAME Set GraphQL operationName
        \\  --fields LIST         Comma-separated top-level fields to include in the output
        \\  --help                Show this help message
        \\
        \\Environment:
        \\  LINEAR_API_KEY        Overrides api_key from config when present
        \\Examples:
        \\  linear gql --query query.graphql --vars '{\"id\":\"abc\"}'
        \\  echo \"query { viewer { id } }\" | linear gql --data-only --json
        \\
    );
}
