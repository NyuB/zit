const std = @import("std");
const argparse = @import("argparse.zig");
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
    if (args.len < 2) {
        try stdOut.print("{s}\n", .{usage});
        try bw.flush();
    }
    const tool = args[1];
    const toolArgs = args[2..];
    if (std.mem.eql(u8, "diff", tool)) {
        const options = try argparse.argParse(toolArgs, DiffOptions);
        try tool_diff(allocator, options, toolArgs[toolArgs.len - 2], toolArgs[toolArgs.len - 1], stdOut, &bw);
    } else if (std.mem.eql(u8, "hash", tool)) {
        try tool_sha1(allocator, args[2], stdOut, &bw);
    } else {
        try stdOut.print("{s}\n", .{usage});
    }
    try bw.flush();
}

fn tool_diff(allocator: std.mem.Allocator, options: DiffOptions, fileA_path: String, fileB_path: String, stdOut: anytype, bw: anytype) !void {
    var fileA = try Lines.readFile(fileA_path, allocator);
    defer fileA.deinit();

    var fileB = try Lines.readFile(fileB_path, allocator);
    defer fileB.deinit();

    const d = try diff.Myers(String, strEq).diff(allocator, fileA.lines, fileB.lines);
    defer allocator.free(d);
    const ansiDefaultColor = if (options.color.value) "\u{001b}[39m" else "";
    const ansiGreen = if (options.color.value) "\u{001b}[31m" else "";
    const ansiRed = if (options.color.value) "\u{001b}[32m" else "";
    for (d) |di| {
        switch (di) {
            .Add => |add| {
                for (add.symbols) |l| {
                    try stdOut.print("{s}{d} + {s}{s}\n", .{ ansiGreen, add.position, l, ansiDefaultColor });
                }
            },
            .Del => |del| {
                try stdOut.print("{s}{d} - {s}{s}\n", .{ ansiRed, del.position, fileA.lines[del.position - 1], ansiDefaultColor });
            },
        }
        try bw.flush();
    }
}

const DiffOptions = struct { color: argparse.BoolFlag };

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
    \\    diff <file_a> <file_b>: output the edit script to update from <file_a> from <file_b>
    \\        --color: output deletions in red and insertions in green
    \\
    \\    hash <file>           : output the hexadecimal representation of the sha1 checksum of <file> 
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
