const std = @import("std");
const sha1 = @import("sha1.zig");
pub fn main() !void {
    var args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);
    const stdOutFile = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdOutFile);
    const stdOut = bw.writer();
    try stdOut.print("Benchmark runner\n", .{});
    try bw.flush();
    if (args.len < 2) return;
    for (args[1..]) |name| {
        try stdOut.print("\tRunning {s}\n", .{name});
        try bw.flush();
        const result = if(std.mem.eql(u8, name, "sha1:big"))hashBenchmarkBig() else hashBenchmarkSmall();
        try stdOut.print("\tRan in {d}ms\n", .{@divFloor(result, 1000000)});
        try bw.flush();
    }
}

fn hashBenchmarkBig() i128 {
    const content = @embedFile("test-vectors/shabytetestvectors/SHA1LongMsg.rsp");
    var hasher = sha1.SHA1{};
    hasher.updateSlice(content);
    const h = hasher.end();
    const start = std.time.nanoTimestamp();
    for (0..10_000) |_| {
        hasher = sha1.SHA1{};
        hasher.updateSlice(content);
        const hbis = hasher.end();
        if (h != hbis) @panic("Invalid benchmark");
    }
    const end = std.time.nanoTimestamp();
    std.debug.print("Hash {x}\n", .{h});
    return end - start;
}

fn hashBenchmarkSmall() i128 {
    const content = "test-vectors/shabytetestvectors/SHA1LongMsg.rsp";
    var hasher = sha1.SHA1{};
    hasher.updateSlice(content);
    const h = hasher.end();
    const start = std.time.nanoTimestamp();
    for (0..10_000) |_| {
        hasher = sha1.SHA1{};
        hasher.updateSlice(content);
        const hbis = hasher.end();
        if (h != hbis) @panic("Invalid benchmark");
    }
    const end = std.time.nanoTimestamp();
    std.debug.print("Hash {x}\n", .{h});
    return end - start;
}
