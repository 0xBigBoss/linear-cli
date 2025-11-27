const std = @import("std");

pub fn printJson(value: std.json.Value, writer: anytype, pretty: bool) !void {
    var jw = std.json.Stringify{
        .writer = writer,
        .options = .{ .whitespace = if (pretty) .indent_2 else .minified },
    };
    try jw.write(value);
    try writer.writeByte('\n');
}

pub const IssueRow = struct {
    identifier: []const u8,
    title: []const u8,
    state: []const u8,
    assignee: []const u8,
    priority: []const u8,
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

pub fn printIssueTable(allocator: std.mem.Allocator, writer: anytype, rows: []const IssueRow) !void {
    const headers = [_][]const u8{ "Identifier", "Title", "State", "Assignee", "Priority", "Updated" };
    const max_widths = [_]usize{ 0, 48, 18, 20, 10, 25 };

    var table_rows = try allocator.alloc([headers.len][]const u8, rows.len);
    defer allocator.free(table_rows);

    for (rows, 0..) |row, idx| {
        table_rows[idx] = .{
            row.identifier,
            row.title,
            row.state,
            row.assignee,
            row.priority,
            row.updated,
        };
    }

    try printTable(headers, table_rows, max_widths, writer);
}

pub fn printTeamTable(allocator: std.mem.Allocator, writer: anytype, rows: []const TeamRow) !void {
    const headers = [_][]const u8{ "ID", "Key", "Name" };
    const max_widths = [_]usize{ 0, 0, 0 };

    var table_rows = try allocator.alloc([headers.len][]const u8, rows.len);
    defer allocator.free(table_rows);

    for (rows, 0..) |row, idx| {
        table_rows[idx] = .{ row.id, row.key, row.name };
    }

    try printTable(headers, table_rows, max_widths, writer);
}

pub fn printUserTable(allocator: std.mem.Allocator, writer: anytype, rows: []const UserRow) !void {
    const headers = [_][]const u8{ "ID", "Name", "Email" };
    const max_widths = [_]usize{ 0, 0, 0 };

    var table_rows = try allocator.alloc([headers.len][]const u8, rows.len);
    defer allocator.free(table_rows);

    for (rows, 0..) |row, idx| {
        table_rows[idx] = .{ row.id, row.name, row.email };
    }

    try printTable(headers, table_rows, max_widths, writer);
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

fn printTable(
    comptime headers: anytype,
    rows: []const [headers.len][]const u8,
    max_widths: [headers.len]usize,
    writer: anytype,
) !void {
    var widths: [headers.len]usize = undefined;
    for (headers, 0..) |header, idx| {
        widths[idx] = displayWidth(header, max_widths[idx]);
    }

    for (rows) |row| {
        for (row, 0..) |cell, idx| {
            const width = displayWidth(cell, max_widths[idx]);
            widths[idx] = @max(widths[idx], width);
        }
    }

    try writeRow(headers.len, headers, widths, max_widths, writer);
    for (rows) |row| {
        try writeRow(headers.len, row, widths, max_widths, writer);
    }
}

fn writeRow(
    comptime count: usize,
    row: [count][]const u8,
    widths: [count]usize,
    max_widths: [count]usize,
    writer: anytype,
) !void {
    for (row, 0..) |cell, idx| {
        try writeCell(cell, widths[idx], max_widths[idx], writer);
        if (idx + 1 < count) try writer.writeAll("  ");
    }
    try writer.writeByte('\n');
}

fn writeCell(value: []const u8, padded_width: usize, cap: usize, writer: anytype) !void {
    const needs_trunc = cap != 0 and value.len > cap;
    if (needs_trunc and cap > 3) {
        const keep = cap - 3;
        try writer.writeAll(value[0..keep]);
        try writer.writeAll("...");
        const padding = padded_width - cap;
        try writeSpaces(writer, padding);
    } else if (needs_trunc) {
        const keep = cap;
        try writer.writeAll(value[0..keep]);
        if (padded_width > keep) try writeSpaces(writer, padded_width - keep);
    } else {
        try writer.writeAll(value);
        if (padded_width > value.len) try writeSpaces(writer, padded_width - value.len);
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
