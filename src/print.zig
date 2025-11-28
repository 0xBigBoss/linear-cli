const std = @import("std");
const io = std.io;

pub const TableOptions = struct {
    pad: bool = true,
    truncate: bool = true,
};

pub const IssueField = enum { identifier, title, state, assignee, priority, updated, parent, sub_issues, project, milestone };
pub const issue_default_fields = [_]IssueField{ .identifier, .title, .state, .assignee, .priority, .updated };
pub const issue_field_count = std.meta.fields(IssueField).len;

pub const TeamField = enum { id, key, name };
pub const team_default_fields = [_]TeamField{ .id, .key, .name };
pub const team_field_count = team_default_fields.len;

pub fn printJson(value: std.json.Value, writer: *io.Writer, pretty: bool) !void {
    var jw = std.json.Stringify{
        .writer = writer,
        .options = .{ .whitespace = if (pretty) .indent_2 else .minified },
    };
    try jw.write(value);
    try writer.writeByte('\n');
}

pub fn printJsonFields(value: std.json.Value, writer: *io.Writer, pretty: bool, fields: []const []const u8) !void {
    if (value != .object) return error.InvalidRoot;

    var jw = std.json.Stringify{
        .writer = writer,
        .options = .{ .whitespace = if (pretty) .indent_2 else .minified },
    };
    try jw.beginObject();
    for (fields) |field_name| {
        const field = value.object.get(field_name) orelse return error.UnknownField;
        try jw.objectField(field_name);
        try jw.write(field);
    }
    try jw.endObject();
    try writer.writeByte('\n');
}

pub const IssueRow = struct {
    identifier: []const u8,
    title: []const u8,
    state: []const u8,
    assignee: []const u8,
    priority: []const u8,
    parent: []const u8,
    sub_issues: []const u8,
    project: []const u8,
    milestone: []const u8,
    updated: []const u8,
};

pub const TeamRow = struct {
    id: []const u8,
    key: []const u8,
    name: []const u8,
};

pub const UserRow = struct {
    id: []const u8,
    name: []const u8,
    email: []const u8,
};

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

pub fn printKeyValuesPlain(writer: anytype, pairs: []const KeyValue) !void {
    for (pairs) |pair| {
        try writer.writeAll(pair.key);
        try writer.writeByte('\t');
        try writer.writeAll(pair.value);
        try writer.writeByte('\n');
    }
}

pub fn printIssueTable(allocator: std.mem.Allocator, writer: anytype, rows: []const IssueRow, fields: []const IssueField, opts: TableOptions) !void {
    _ = allocator;
    const selected = if (fields.len == 0) issue_default_fields[0..] else fields;

    var caps_buf: [issue_field_count]usize = undefined;
    var widths: [issue_field_count]usize = undefined;
    var header_row: [issue_field_count][]const u8 = undefined;
    var cell_row: [issue_field_count][]const u8 = undefined;

    for (selected, 0..) |field, idx| {
        const cap = if (opts.truncate) issueFieldCap(field) else 0;
        caps_buf[idx] = cap;
        const header = issueFieldLabel(field);
        header_row[idx] = header;
        widths[idx] = displayWidth(header, cap);
    }

    for (rows) |row| {
        fillIssueCells(row, selected, &cell_row);
        for (selected, 0..) |_, idx| {
            widths[idx] = @max(widths[idx], displayWidth(cell_row[idx], caps_buf[idx]));
        }
    }

    const active_caps = caps_buf[0..selected.len];
    const active_widths = widths[0..selected.len];
    try writeRow(header_row[0..selected.len], active_widths, active_caps, opts, writer);
    for (rows) |row| {
        fillIssueCells(row, selected, &cell_row);
        try writeRow(cell_row[0..selected.len], active_widths, active_caps, opts, writer);
    }
}

pub fn printTeamTable(allocator: std.mem.Allocator, writer: anytype, rows: []const TeamRow, fields: []const TeamField, opts: TableOptions) !void {
    _ = allocator;
    const selected = if (fields.len == 0) team_default_fields[0..] else fields;

    var caps_buf: [team_field_count]usize = undefined;
    var widths: [team_field_count]usize = undefined;
    var header_row: [team_field_count][]const u8 = undefined;
    var cell_row: [team_field_count][]const u8 = undefined;

    for (selected, 0..) |field, idx| {
        const cap = if (opts.truncate) teamFieldCap(field) else 0;
        caps_buf[idx] = cap;
        const header = teamFieldLabel(field);
        header_row[idx] = header;
        widths[idx] = displayWidth(header, cap);
    }

    for (rows) |row| {
        fillTeamCells(row, selected, &cell_row);
        for (selected, 0..) |_, idx| {
            widths[idx] = @max(widths[idx], displayWidth(cell_row[idx], caps_buf[idx]));
        }
    }

    const active_caps = caps_buf[0..selected.len];
    const active_widths = widths[0..selected.len];
    try writeRow(header_row[0..selected.len], active_widths, active_caps, opts, writer);
    for (rows) |row| {
        fillTeamCells(row, selected, &cell_row);
        try writeRow(cell_row[0..selected.len], active_widths, active_caps, opts, writer);
    }
}

pub fn printUserTable(allocator: std.mem.Allocator, writer: anytype, rows: []const UserRow, opts: TableOptions) !void {
    _ = allocator;
    const headers = [_][]const u8{ "ID", "Name", "Email" };
    const caps = [_]usize{ 0, 0, 0 };

    var widths = [_]usize{
        displayWidth(headers[0], caps[0]),
        displayWidth(headers[1], caps[1]),
        displayWidth(headers[2], caps[2]),
    };

    for (rows) |row| {
        widths[0] = @max(widths[0], displayWidth(row.id, caps[0]));
        widths[1] = @max(widths[1], displayWidth(row.name, caps[1]));
        widths[2] = @max(widths[2], displayWidth(row.email, caps[2]));
    }

    try writeRow(headers[0..], widths[0..], caps[0..], opts, writer);
    for (rows) |row| {
        const cells = [_][]const u8{ row.id, row.name, row.email };
        try writeRow(cells[0..], widths[0..], caps[0..], opts, writer);
    }
}

pub fn printKeyValues(writer: anytype, pairs: []const KeyValue) !void {
    var max_key: usize = 0;
    for (pairs) |pair| {
        max_key = @max(max_key, pair.key.len);
    }

    for (pairs) |pair| {
        try writer.writeAll(pair.key);
        if (pair.key.len < max_key) try writeSpaces(writer, max_key - pair.key.len);
        try writer.writeAll(": ");
        try writer.writeAll(pair.value);
        try writer.writeByte('\n');
    }
}

pub fn humanTime(allocator: std.mem.Allocator, iso: []const u8, now_override: ?i64) ![]u8 {
    const ts = try parseIso8601Seconds(iso);
    const now = now_override orelse std.time.timestamp();
    const diff = now - ts;
    const in_future = diff < 0;
    if (diff == std.math.minInt(i64)) return error.InvalidTimestamp;
    const distance = if (diff < 0) -diff else diff;

    const unit_info = chooseUnit(distance);
    const suffix = if (in_future) "from now" else "ago";
    return try std.fmt.allocPrint(allocator, "{d}{s} {s}", .{ unit_info.value, unit_info.unit, suffix });
}

const Unit = struct {
    value: i64,
    unit: []const u8,
};

fn chooseUnit(seconds: i64) Unit {
    if (seconds < 60) return .{ .value = seconds, .unit = "s" };
    if (seconds < 3600) return .{ .value = @divTrunc(seconds, 60), .unit = "m" };
    if (seconds < 86400) return .{ .value = @divTrunc(seconds, 3600), .unit = "h" };
    return .{ .value = @divTrunc(seconds, 86400), .unit = "d" };
}

fn parseIso8601Seconds(value: []const u8) !i64 {
    if (value.len < 20) return error.InvalidTimestamp;
    if (value[4] != '-' or value[7] != '-' or value[10] != 'T') return error.InvalidTimestamp;

    const year = try std.fmt.parseInt(i32, value[0..4], 10);
    const month = try std.fmt.parseInt(u8, value[5..7], 10);
    const day = try std.fmt.parseInt(u8, value[8..10], 10);
    const hour = try std.fmt.parseInt(u8, value[11..13], 10);
    const minute = try std.fmt.parseInt(u8, value[14..16], 10);
    const second = try std.fmt.parseInt(u8, value[17..19], 10);

    if (hour >= 24 or minute >= 60 or second >= 60) return error.InvalidTimestamp;

    const tz_start = findTimezoneStart(value) orelse return error.InvalidTimestamp;
    const tz_slice = value[tz_start..];
    const tz_offset = try parseTimezoneOffset(tz_slice);

    const days = try daysSinceEpoch(year, month, day);
    const base_seconds: i64 = (days * 86400) + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    return base_seconds - tz_offset;
}

fn findTimezoneStart(value: []const u8) ?usize {
    var idx: usize = 19;
    if (idx >= value.len) return null;
    while (idx < value.len and value[idx] != 'Z' and value[idx] != '+' and value[idx] != '-') {
        idx += 1;
    }
    if (idx >= value.len) return null;
    return idx;
}

fn parseTimezoneOffset(tz: []const u8) !i64 {
    if (tz.len == 0) return error.InvalidTimestamp;
    if (tz[0] == 'Z') return 0;
    if (tz.len < 6 or tz[3] != ':') return error.InvalidTimestamp;
    const sign: i64 = if (tz[0] == '+') 1 else if (tz[0] == '-') -1 else return error.InvalidTimestamp;
    const hours = try std.fmt.parseInt(i64, tz[1..3], 10);
    const minutes = try std.fmt.parseInt(i64, tz[4..6], 10);
    if (hours >= 24 or minutes >= 60) return error.InvalidTimestamp;
    return sign * ((hours * 3600) + (minutes * 60));
}

fn daysSinceEpoch(year: i32, month: u8, day: u8) !i64 {
    if (month == 0 or month > 12) return error.InvalidTimestamp;
    if (year < std.time.epoch.epoch_year or year > std.math.maxInt(std.time.epoch.Year)) return error.InvalidTimestamp;

    const year_value: std.time.epoch.Year = @intCast(year);
    const days_in_month = std.time.epoch.getDaysInMonth(year_value, @enumFromInt(month));
    if (day == 0 or day > days_in_month) return error.InvalidTimestamp;

    var days: i64 = 0;
    var y: std.time.epoch.Year = std.time.epoch.epoch_year;
    while (y < year_value) : (y += 1) {
        days += @as(i64, @intCast(std.time.epoch.getDaysInYear(y)));
    }

    var m: u8 = 1;
    while (m < month) : (m += 1) {
        days += @as(i64, @intCast(std.time.epoch.getDaysInMonth(year_value, @enumFromInt(m))));
    }

    days += @as(i64, @intCast(day)) - 1;
    return days;
}

fn issueFieldLabel(field: IssueField) []const u8 {
    return switch (field) {
        .identifier => "Identifier",
        .title => "Title",
        .state => "State",
        .assignee => "Assignee",
        .priority => "Priority",
        .parent => "Parent",
        .sub_issues => "Sub-issues",
        .project => "Project",
        .milestone => "Milestone",
        .updated => "Updated",
    };
}

fn issueFieldCap(field: IssueField) usize {
    return switch (field) {
        .identifier => 0,
        .title => 48,
        .state => 18,
        .assignee => 20,
        .priority => 10,
        .parent => 20,
        .sub_issues => 32,
        .project => 28,
        .milestone => 28,
        .updated => 25,
    };
}

fn fillIssueCells(row: IssueRow, fields: []const IssueField, buffer: *[issue_field_count][]const u8) void {
    for (fields, 0..) |field, idx| {
        buffer[idx] = switch (field) {
            .identifier => row.identifier,
            .title => row.title,
            .state => row.state,
            .assignee => row.assignee,
            .priority => row.priority,
            .parent => row.parent,
            .sub_issues => row.sub_issues,
            .project => row.project,
            .milestone => row.milestone,
            .updated => row.updated,
        };
    }
}

fn teamFieldLabel(field: TeamField) []const u8 {
    return switch (field) {
        .id => "ID",
        .key => "Key",
        .name => "Name",
    };
}

fn teamFieldCap(field: TeamField) usize {
    return switch (field) {
        .id => 0,
        .key => 0,
        .name => 0,
    };
}

fn fillTeamCells(row: TeamRow, fields: []const TeamField, buffer: *[team_field_count][]const u8) void {
    for (fields, 0..) |field, idx| {
        buffer[idx] = switch (field) {
            .id => row.id,
            .key => row.key,
            .name => row.name,
        };
    }
}

fn writeRow(row: []const []const u8, widths: []const usize, caps: []const usize, opts: TableOptions, writer: anytype) !void {
    for (row, 0..) |cell, idx| {
        try writeCell(cell, widths[idx], caps[idx], opts, writer);
        if (idx + 1 < row.len) try writer.writeAll("  ");
    }
    try writer.writeByte('\n');
}

fn writeCell(value: []const u8, padded_width: usize, cap: usize, opts: TableOptions, writer: anytype) !void {
    const limit = cap;
    const needs_trunc = opts.truncate and limit != 0 and value.len > limit;
    if (needs_trunc and limit > 3) {
        const keep = limit - 3;
        try writer.writeAll(value[0..keep]);
        try writer.writeAll("...");
        if (opts.pad and padded_width > limit) try writeSpaces(writer, padded_width - limit);
    } else if (needs_trunc) {
        const keep = limit;
        try writer.writeAll(value[0..keep]);
        if (opts.pad and padded_width > keep) try writeSpaces(writer, padded_width - keep);
    } else {
        try writer.writeAll(value);
        if (opts.pad and padded_width > value.len) try writeSpaces(writer, padded_width - value.len);
    }
}

fn displayWidth(value: []const u8, cap: usize) usize {
    if (cap != 0 and value.len > cap) return cap;
    return value.len;
}

fn writeSpaces(writer: anytype, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeByte(' ');
    }
}
