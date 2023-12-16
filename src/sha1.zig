const std = @import("std");
const expect = std.testing.expect;

const sha1 = u160;

pub const SHA1 = struct {
    h0: u32 = 0x67452301,
    h1: u32 = 0xEFCDAB89,
    h2: u32 = 0x98BADCFE,
    h3: u32 = 0x10325476,
    h4: u32 = 0xC3D2E1F0,
    ml: usize = 0,
    chunkProcessBuffer: [BUFFER_SIZE]u8 = undefined,
    endIndex: usize = 0,

    const CHUNK_NB: usize = 64;
    const CHUNK_SIZE: usize = 64;
    const BUFFER_SIZE: usize = CHUNK_NB * CHUNK_SIZE;

    pub fn end(self: *SHA1) sha1 {
        const mlAsBytes: [8]u8 = @bitCast(@byteSwap(self.ml));
        self.update(0x80);

        while ((self.endIndex % CHUNK_SIZE) != 56) {
            self.update(0x00);
        }
        for (mlAsBytes) |c| {
            self.update(c);
        }
        var buf = &self.chunkProcessBuffer;
        for (0..self.endIndex / CHUNK_SIZE) |i| {
            self.processChunk(buf[i * CHUNK_SIZE .. (i + 1) * CHUNK_SIZE]);
        }

        const hh0: sha1 = @as(sha1, self.h0) << 128;
        const hh1: sha1 = @as(sha1, self.h1) << 96;
        const hh2: sha1 = @as(sha1, self.h2) << 64;
        const hh3: sha1 = @as(sha1, self.h3) << 32;
        const hh4: sha1 = self.h4;
        return (hh0 | hh1 | hh2 | hh3 | hh4);
    }

    inline fn update(self: *SHA1, c: u8) void {
        self.chunkProcessBuffer[self.endIndex] = c;
        self.ml += 8;
        self.endIndex = (self.endIndex + 1) % (BUFFER_SIZE);
        if (self.endIndex == 0) {
            self.processAllChunks();
        }
    }

    pub fn updateSlice(self: *SHA1, slice: []const u8) void {
        var diff = (BUFFER_SIZE) - self.endIndex;
        var buf = &self.chunkProcessBuffer;
        if (slice.len < diff) {
            @memcpy(buf[self.endIndex .. self.endIndex + slice.len], slice);
            self.ml += slice.len * 8;
            self.endIndex += slice.len;
            return;
        }
        @memcpy(buf[self.endIndex..(BUFFER_SIZE)], slice[0..diff]);
        self.processAllChunks();
        self.endIndex = 0;
        self.ml += diff * 8;
        if (slice.len > diff) self.updateSlice(slice[diff..]);
    }

    inline fn processAllChunks(self: *SHA1) void {
        var buf = &self.chunkProcessBuffer;
        for (0..CHUNK_NB) |i| {
            self.processChunk(buf[i * CHUNK_SIZE .. (i + 1) * CHUNK_SIZE]);
        }
    }

    inline fn processChunk(self: *SHA1, chunk: []u8) void {
        var w: [80]u32 = undefined;
        for (0..16) |i| {
            // Reorder for big Endian
            var chunkAsInt = [4]u8{
                chunk[(i * 4) + 3],
                chunk[(i * 4) + 2],
                chunk[(i * 4) + 1],
                chunk[(i * 4)],
            };
            w[i] = @bitCast(chunkAsInt);
        }
        for (16..80) |i| {
            w[i] = leftRotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        }
        var a = self.h0;
        var b = self.h1;
        var c = self.h2;
        var d = self.h3;
        var e = self.h4;

        var f: u32 = undefined;
        var k: u32 = undefined;

        for (0..80) |i| {
            if (0 <= i and i <= 19) {
                f = (b & c) | (~b & d);
                k = 0x5A827999;
            } else if (20 <= i and i <= 39) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1;
            } else if (40 <= i and i <= 59) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDC;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6;
            }

            const temp = leftRotate(a, 5) +% f +% e +% k +% w[i];
            e = d;
            d = c;
            c = leftRotate(b, 30);
            b = a;
            a = temp;
        }

        self.h0 +%= a;
        self.h1 +%= b;
        self.h2 +%= c;
        self.h3 +%= d;
        self.h4 +%= e;
    }
};

inline fn leftRotate(u: u32, n: anytype) u32 {
    return std.math.rotl(u32, u, n);
}

fn hexOfSha1(hash: sha1) [40]u8 {
    const asBytes: [20]u8 = @bitCast(@byteSwap(hash));
    return std.fmt.bytesToHex(asBytes, std.fmt.Case.lower);
}

test "abc" {
    const message = "abc";
    var hasher = SHA1{};
    hasher.updateSlice(message);
    const res = hasher.end();
    try std.testing.expectEqualStrings("a9993e364706816aba3e25717850c26c9cd0d89d", &hexOfSha1(res));
}

test "SHA1LongMsg NIST Vectors" {
    const content = @embedFile("test-vectors/shabytetestvectors/SHA1LongMsg.rsp");
    try testNISTVector(content);
}

test "SHA1ShortMsg NIST Vectors" {
    const content = @embedFile("test-vectors/shabytetestvectors/SHA1ShortMsg.rsp");
    try testNISTVector(content);
}

fn testNISTVector(content: []const u8) !void {
    var lines = LineIterator.new(content);
    while (lines.next()) |line| {
        const lenLine = split_n_str(2, line, "Len = ");
        if (lenLine[1]) |lenStr| {
            const msgLine = lines.next() orelse unreachable;
            const mdLine = lines.next() orelse unreachable;
            const msg = split_n_str(2, msgLine, "Msg = ")[1] orelse unreachable;
            const md = split_n_str(2, mdLine, "MD = ")[1] orelse unreachable;
            var hasher = SHA1{};
            var msgFromHex = try std.testing.allocator.alloc(u8, msg.len / 2);
            defer std.testing.allocator.free(msgFromHex);
            const len = try std.fmt.parseInt(usize, lenStr, 10);
            const written = try std.fmt.hexToBytes(msgFromHex, msg[0 .. len / 4]);
            if (written.len != len / 8) unreachable;
            hasher.updateSlice(written);
            const h = hasher.end();
            try std.testing.expectEqualStrings(md, &hexOfSha1(h));
        }
    }
}

fn split_n_str(comptime n: usize, content: []const u8, delimiter: []const u8) [n]?[]const u8 {
    var res: [n]?[]const u8 = undefined;
    var it = std.mem.splitSequence(u8, content, delimiter);
    for (0..n) |i| {
        res[i] = it.next();
    }
    return res;
}

const LineIterator = struct {
    backing: []const u8,
    fn next(self: *LineIterator) ?[]const u8 {
        var l = self.backing.len;
        if (l == 0) return null;
        var endIndex: usize = 0;
        while (endIndex < l) : (endIndex += 1) {
            if (self.backing[endIndex] == '\n') {
                var actualEndIndex = if (endIndex == 0 or self.backing[endIndex - 1] != '\r') endIndex else endIndex - 1;
                var res = self.backing[0..actualEndIndex];
                self.backing = if (endIndex == l - 1) self.backing[endIndex..endIndex] else self.backing[endIndex + 1 ..];
                return res;
            }
        }
        var res = self.backing;
        self.backing = self.backing[l - 1 .. l - 1];
        return res;
    }

    fn new(text: []const u8) LineIterator {
        return LineIterator{ .backing = text };
    }
};
