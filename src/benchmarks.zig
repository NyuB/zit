const std = @import("std");
const sha1 = @import("sha1.zig");
const zlib = @import("zlib.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const stdOutFile = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdOutFile);
    const stdOut = bw.writer();
    try stdOut.print("Benchmark runner\n", .{});
    try bw.flush();
    if (args.len < 2) return;

    var actualArgs = std.ArrayList([]const u8).init(allocator);
    defer actualArgs.deinit();
    var iter: usize = 10;
    for (args[1..]) |a| {
        if (std.mem.startsWith(u8, a, "-iter=")) {
            iter = try std.fmt.parseInt(usize, a[6..], 10);
        } else {
            try actualArgs.append(a);
        }
    }

    for (actualArgs.items) |name| {
        try stdOut.print("\tRunning {s} for {d} iterations\n", .{ name, iter });
        try bw.flush();
        const result = if (std.mem.eql(u8, name, "sha1:big")) r: {
            break :r hashBenchmarkBig(iter);
        } else if (std.mem.eql(u8, name, "sha1:small")) r: {
            break :r hashBenchmarkSmall(iter);
        } else if (std.mem.eql(u8, name, "zlib:decompress")) r: {
            break :r try decompressBenchmark("test-zlib/geo.z", iter);
        } else if (std.mem.eql(u8, name, "zlib-ref:decompress")) r: {
            break :r try decompressRef("test-zlib/geo.z", iter);
        } else continue;
        try stdOut.print("\tRan in {d}ms\n", .{@divFloor(result, 1000000)});
        try bw.flush();
    }
}

fn hashBenchmarkBig(iter: usize) i128 {
    const content = @embedFile("test-sha1/shabytetestvectors/SHA1LongMsg.rsp");
    var hasher = sha1.SHA1{};
    hasher.updateSlice(content);
    const h = hasher.end();
    const start = std.time.nanoTimestamp();
    for (0..iter) |_| {
        hasher = sha1.SHA1{};
        hasher.updateSlice(content);
        const hbis = hasher.end();
        if (h != hbis) @panic("Invalid benchmark");
    }
    const end = std.time.nanoTimestamp();
    std.debug.print("Hash {x}\n", .{h});
    return end - start;
}

fn hashBenchmarkSmall(iter: usize) i128 {
    const content = "!___Some_Short_String__gnirtS_trohS_emoS___!";
    var hasher = sha1.SHA1{};
    hasher.updateSlice(content);
    const h = hasher.end();
    const start = std.time.nanoTimestamp();
    for (0..iter) |_| {
        hasher = sha1.SHA1{};
        hasher.updateSlice(content);
        const hbis = hasher.end();
        if (h != hbis) @panic("Invalid benchmark");
    }
    const end = std.time.nanoTimestamp();
    std.debug.print("Hash {x}\n", .{h});
    return end - start;
}

fn decompressBenchmark(comptime contentFilePath: []const u8, iter: usize) !i128 {
    const content = @embedFile(contentFilePath);
    var out: [200_000]u8 = undefined;
    var allocationBuffer: [600_000]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&allocationBuffer);

    const start = std.time.nanoTimestamp();
    for (0..iter) |_| {
        allocator.reset();
        var testReaderWriter = zlib.TestReaderWriter{ .input = content, .output = &out };
        _ = try zlib.decode(allocator.allocator(), &testReaderWriter, &testReaderWriter);
    }

    const end = std.time.nanoTimestamp();
    return end - start;
}

fn decompressRef(comptime contentFilePath: []const u8, iter: usize) !i128 {
    const content = @embedFile(contentFilePath);
    var allocationBuffer: [600_000]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&allocationBuffer);

    const start = std.time.nanoTimestamp();
    for (0..iter) |_| {
        allocator.reset();
        var in_stream = std.io.fixedBufferStream(content);

        var zlib_stream = try std.compress.zlib.decompressStream(allocator.allocator(), in_stream.reader());
        defer zlib_stream.deinit();

        // Read and decompress the whole file
        _ = try zlib_stream.reader().readAllAlloc(allocator.allocator(), std.math.maxInt(usize));
    }

    const end = std.time.nanoTimestamp();
    return end - start;
}
