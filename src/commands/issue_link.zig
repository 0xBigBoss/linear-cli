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
    endpoint: ?[]const u8 = null,
};

const RelationType = enum {
    blocks,
    related,
    duplicate,
};

const Options = struct {
    identifier: ?[]const u8 = null,
    blocks: ?[]const u8 = null,
    related: ?[]const u8 = null,
    duplicate: ?[]const u8 = null,
    yes: bool = false,
    help: bool = false,
    quiet: bool = false,
    data_only: bool = false,
};

pub fn run(ctx: Context) !u8 {
    var stderr_buf: [0]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    const opts = parseOptions(ctx.args) catch |err| {
        try stderr.print("issue link: {s}\n", .{@errorName(err)});
        try usage(stderr);
        return 1;
    };

    if (opts.help) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try usage(&out_writer.interface);
        return 0;
    }

    const source_id = opts.identifier orelse {
        try stderr.print("issue link: missing source identifier\n", .{});
        return 1;
    };

    // Determine relation type and target
    var relation_count: u8 = 0;
    var relation_type: RelationType = .related;
    var target_id: []const u8 = "";

    if (opts.blocks) |id| {
        relation_count += 1;
        relation_type = .blocks;
        target_id = id;
    }
    if (opts.related) |id| {
        relation_count += 1;
        relation_type = .related;
        target_id = id;
    }
    if (opts.duplicate) |id| {
        relation_count += 1;
        relation_type = .duplicate;
        target_id = id;
    }

    if (relation_count == 0) {
        try stderr.print("issue link: exactly one of --blocks, --related, or --duplicate is required\n", .{});
        return 1;
    }
    if (relation_count > 1) {
        try stderr.print("issue link: only one of --blocks, --related, or --duplicate can be specified\n", .{});
        return 1;
    }

    const api_key = common.requireApiKey(ctx.config, null, stderr, "issue link") catch {
        return 1;
    };

    var client = graphql.GraphqlClient.init(ctx.allocator, api_key);
    defer client.deinit();
    client.max_retries = ctx.retries;
    client.timeout_ms = ctx.timeout_ms;
    if (ctx.endpoint) |ep| client.endpoint = ep;

    if (!opts.yes) {
        try stderr.print("issue link: confirmation required; re-run with --yes to proceed\n", .{});
        return 1;
    }

    const source_resolved = common.resolveIssueId(ctx.allocator, &client, source_id, stderr, "issue link") catch {
        return 1;
    };
    defer if (source_resolved.owned) ctx.allocator.free(source_resolved.value);

    const target_resolved = common.resolveIssueId(ctx.allocator, &client, target_id, stderr, "issue link") catch {
        return 1;
    };
    defer if (target_resolved.owned) ctx.allocator.free(target_resolved.value);

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const var_alloc = arena.allocator();

    const relation_type_str = switch (relation_type) {
        .blocks => "blocks",
        .related => "related",
        .duplicate => "duplicate",
    };

    var input = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try input.object.put("issueId", .{ .string = source_resolved.value });
    try input.object.put("relatedIssueId", .{ .string = target_resolved.value });
    try input.object.put("type", .{ .string = relation_type_str });

    var variables = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
    try variables.object.put("input", input);

    const mutation =
        \\mutation IssueRelationCreate($input: IssueRelationCreateInput!) {
        \\  issueRelationCreate(input: $input) {
        \\    success
        \\    issueRelation {
        \\      id
        \\      type
        \\      issue { identifier }
        \\      relatedIssue { identifier }
        \\    }
        \\  }
        \\}
    ;

    var response = common.send("issue link", &client, ctx.allocator, .{
        .query = mutation,
        .variables = variables,
        .operation_name = "IssueRelationCreate",
    }, stderr) catch {
        return 1;
    };
    defer response.deinit();

    common.checkResponse("issue link", &response, stderr, api_key) catch {
        return 1;
    };

    const data_value = response.data() orelse {
        try stderr.print("issue link: response missing data\n", .{});
        return 1;
    };

    const payload = common.getObjectField(data_value, "issueRelationCreate") orelse {
        try stderr.print("issue link: issueRelationCreate missing in response\n", .{});
        return 1;
    };

    const success = common.getBoolField(payload, "success") orelse false;
    if (!success) {
        if (payload.object.get("userError")) |user_error| {
            if (user_error == .string) {
                try stderr.print("issue link: {s}\n", .{user_error.string});
                return 1;
            }
            if (user_error == .object) {
                if (user_error.object.get("message")) |msg| {
                    if (msg == .string) {
                        try stderr.print("issue link: {s}\n", .{msg.string});
                        return 1;
                    }
                }
            }
        }
        try stderr.print("issue link: request failed\n", .{});
        return 1;
    }

    const relation_obj = common.getObjectField(payload, "issueRelation") orelse {
        try stderr.print("issue link: issueRelation missing in response\n", .{});
        return 1;
    };

    if (ctx.json_output and !opts.quiet and !opts.data_only) {
        var out_buf: [0]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        try printer.printJson(data_value, &out_writer.interface, true);
        return 0;
    }

    const relation_id = common.getStringField(relation_obj, "id") orelse "(unknown)";
    const type_value = common.getStringField(relation_obj, "type") orelse relation_type_str;
    const issue_obj = common.getObjectField(relation_obj, "issue");
    const source_identifier = if (issue_obj) |i| common.getStringField(i, "identifier") else null;
    const related_obj = common.getObjectField(relation_obj, "relatedIssue");
    const target_identifier = if (related_obj) |r| common.getStringField(r, "identifier") else null;

    var out_buf: [0]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    var stdout_iface = &out_writer.interface;

    if (opts.quiet) {
        try stdout_iface.writeAll(relation_id);
        try stdout_iface.writeByte('\n');
        return 0;
    }

    const src_display = source_identifier orelse source_id;
    const tgt_display = target_identifier orelse target_id;

    const pairs = [_]printer.KeyValue{
        .{ .key = "Relation ID", .value = relation_id },
        .{ .key = "Type", .value = type_value },
        .{ .key = "Source", .value = src_display },
        .{ .key = "Target", .value = tgt_display },
    };
    const data_pairs = [_]printer.KeyValue{
        .{ .key = "id", .value = relation_id },
        .{ .key = "type", .value = type_value },
        .{ .key = "source", .value = src_display },
        .{ .key = "target", .value = tgt_display },
    };

    if (opts.data_only) {
        if (ctx.json_output) {
            var data_obj = std.json.Value{ .object = std.json.ObjectMap.init(var_alloc) };
            for (data_pairs) |pair| {
                try data_obj.object.put(pair.key, .{ .string = pair.value });
            }
            try printer.printJson(data_obj, stdout_iface, true);
            return 0;
        }

        try printer.printKeyValuesPlain(stdout_iface, data_pairs[0..]);
        return 0;
    }

    try printer.printKeyValues(stdout_iface, pairs[0..]);
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
        if (std.mem.eql(u8, arg, "--quiet")) {
            opts.quiet = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--data-only")) {
            opts.data_only = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--blocks")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.blocks = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--blocks=")) {
            opts.blocks = arg["--blocks=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--related")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.related = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--related=")) {
            opts.related = arg["--related=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--duplicate")) {
            if (idx + 1 >= args.len) return error.MissingValue;
            opts.duplicate = args[idx + 1];
            idx += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--duplicate=")) {
            opts.duplicate = arg["--duplicate=".len..];
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--force")) {
            opts.yes = true;
            idx += 1;
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;
        if (opts.identifier == null) {
            opts.identifier = arg;
            idx += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return opts;
}

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage: linear issue link <ID|IDENTIFIER> --blocks|--related|--duplicate <OTHER_ID> [--yes] [--quiet] [--data-only] [--help]
        \\Flags:
        \\  --blocks OTHER_ID      This issue blocks the other issue
        \\  --related OTHER_ID     General relation between issues
        \\  --duplicate OTHER_ID   Mark this issue as duplicate of other
        \\  --yes                  Skip confirmation prompt (alias: --force)
        \\  --quiet                Print only the relation ID
        \\  --data-only            Emit tab-separated fields without formatting (or JSON object with --json)
        \\  --help                 Show this help message
        \\Examples:
        \\  linear issue link ENG-123 --blocks ENG-456 --yes
        \\  linear issue link ENG-123 --related ENG-456 --yes
        \\  linear issue link ENG-123 --duplicate ENG-100 --yes
        \\
    , .{});
}
