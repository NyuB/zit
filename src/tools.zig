const std = @import("std");
const diff = @import("diff.zig");
const sha1 = @import("sha1.zig");

const String = []const u8;

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const stdOutFile = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdOutFile);
    const stdOut = bw.writer();

    const tool = args[1];
    if (std.mem.eql(u8, "diff", tool)) {
        try tool_diff(allocator, args[2], args[3], stdOut, &bw);
    } else if (std.mem.eql(u8, "hash", tool)) {
        try tool_sha1(allocator, args[2], stdOut, &bw);
    } else {
        try stdOut.print("{s}\n", .{usage});
    }
    try bw.flush();
}

fn tool_diff(allocator: std.mem.Allocator, fileA_path: String, fileB_path: String, stdOut: anytype, bw: anytype) !void {
    var fileA = try Lines.readFile(fileA_path, allocator);
    defer fileA.deinit();

    var fileB = try Lines.readFile(fileB_path, allocator);
    defer fileB.deinit();

    const d = try diff.Myers(String, strEq).diff(allocator, fileA.lines, fileB.lines);
    defer allocator.free(d);

    for (d) |di| {
        switch (di) {
            .Add => |add| {
                for (add.symbols) |l| {
                    try stdOut.print("{d} + {s}\n", .{ add.position, l });
                }
            },
            .Del => |del| {
                try stdOut.print("{d} - {s}\n", .{ del.position, fileA.lines[del.position - 1] });
            },
        }
        try bw.flush();
    }
}

fn tool_sha1(allocator: std.mem.Allocator, file_path: String, stdOut: anytype, bw: anytype) !void {
    var h = sha1.SHA1{};
    var file = try Lines.readFile(file_path, allocator);
    h.updateSlice(file.bytes);
    try stdOut.print("{x}", .{h.end()});
    try bw.flush();
}

const usage =
    \\Usage: tools {diff, hash, help,} [args ...]
    \\
    \\    diff <file_a> <file_b>: output the edit script to update from file_a from file_b
    \\
    \\    hash <file>           : output the hexadecimal representation of the sha1 checksum of file 
    \\
    \\    help                  : print this help message
;

const Lines = struct {
    bytes: []const u8,
    lines: []const String,
    allocator: std.mem.Allocator,

    fn readFile(path: []const u8, allocator: std.mem.Allocator) !Lines {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        var bytes = try f.readToEndAlloc(allocator, 100_000_000);
        errdefer allocator.free(bytes);

        var lines = std.ArrayList(String).init(allocator);
        errdefer lines.deinit();

        var index: usize = 0;
        var start: usize = 0;
        while (index < bytes.len) {
            if (bytes[index] == '\n') {
                try lines.append(bytes[start..index]);
                start = index + 1;
                index = start;
            } else if (bytes[index] == '\r' and index + 1 < bytes.len and bytes[index + 1] == '\n') {
                try lines.append(bytes[start..index]);
                start = index + 2;
                index = start;
            } else {
                index += 1;
            }
        }
        if (index > start) {
            try lines.append(bytes[start..index]);
        }
        return Lines{ .bytes = bytes, .lines = try lines.toOwnedSlice(), .allocator = allocator };
    }

    fn deinit(self: *Lines) void {
        self.allocator.free(self.lines);
        self.allocator.free(self.bytes);
    }
};

inline fn strEq(a: String, b: String) bool {
    return std.mem.eql(u8, a, b);
}
