const std = @import("std");
const utils = @import("utils.zig");
const huffman = @import("huffman.zig");

const DecodeErrors = error{ IllegalFlagCheck, ReservedBlockType, IllegalLiteralLength };

fn decode(reader: anytype, writer: void) DecodeErrors!void {
    _ = writer;

    const compressionMethodAndFlags = reader.readCompressionMethodAndFlags();

    switch (compressionMethodAndFlags.compressionMethod) {
        8 => {},
        else => unreachable,
    }

    try compressionMethodAndFlags.check();

    var b_final = false;
    while (!b_final) {
        b_final = reader.readBits(1) > 0;
        const blockType: BlockType = @enumFromInt(reader.readBitsRev(2));
        switch (blockType) {
            .Raw => unreachable,
            .Fixed => {
                switch (readLiteralLength(reader)) {
                    .Literal => |c| {
                        _ = c;
                    },
                    .Length => |l| {
                        _ = l;
                        unreachable;
                    },
                    .EndOfBlock => {
                        unreachable;
                    },
                    .Unused => return DecodeErrors.IllegalLiteralLength,
                }
            },
            .Dynamic => unreachable,
            .Reserved => return DecodeErrors.ReservedBlockType,
        }
    }
}

fn readLiteralLength(reader: anytype) LiteralLengthCode {
    var cursor = FIXED_LITERAL_LENGTH_HUFFMAN.cursor();
    var s: ?u9 = null;
    while (s == null) {
        const b = reader.readBits(1);
        s = cursor.next(b > 0);
    }
    return LITERAL_LENGTH_CODE_TABLE[s orelse unreachable];
}

const BlockType = enum(u2) {
    Raw = 0b00,
    Fixed = 0b01,
    Dynamic = 0b10,
    Reserved = 0b11,
};

const CompressionMethodAndFlags = packed struct(u16) {
    compressionMethod: u4,
    compressionInfo: u4,
    checkNumber: u5,
    flagDict: bool, // u1
    compressionLevel: u2,

    fn check(self: CompressionMethodAndFlags) DecodeErrors!void {
        if (self.asInt() % 31 != 0) return DecodeErrors.IllegalFlagCheck;
    }

    fn asInt(self: CompressionMethodAndFlags) u16 {
        const bytes = std.mem.asBytes(&self);
        const left: u16 = @intCast(bytes[0]);
        const right: u16 = @intCast(bytes[1]);
        return 256 * left + right;
    }
};

const LengthCode = packed struct(u16) {
    extra_bits: u3,
    min_value: u13,
};

const LiteralLengthCodeTag = enum(u2) {
    Literal,
    Length,
    EndOfBlock,
    Unused,
};

const LiteralLengthCode = union(LiteralLengthCodeTag) {
    Literal: u8,
    Length: LengthCode,
    EndOfBlock: void,
    Unused: void,
};

const DistanceCode = struct {
    extra_bits: u4,
    min_value: u16,
};

const TestReaderWriter = struct {
    input: []const u8,
    output: []u8,

    read_index: usize = 0,
    read_bit_index: u4 = 0,
    write_index: usize = 0,

    fn readBits(self: *TestReaderWriter, n: usize) usize {
        var res: usize = 0;
        for (0..n) |_| {
            var mask: usize = utils.powerOfTwo(self.read_bit_index);
            res = std.math.shl(usize, res, 1);
            if (mask & self.input[self.read_index] > 0) {
                res |= 1;
            }
            self.read_bit_index += 1;
            if (self.read_bit_index == 8) {
                self.read_bit_index = 0;
                self.read_index += 1;
            }
        }
        return res;
    }

    fn readBitsRev(self: *TestReaderWriter, n: usize) usize {
        var res: usize = 0;
        for (0..n) |i| {
            var mask: usize = utils.powerOfTwo(self.read_bit_index);
            if (mask & self.input[self.read_index] > 0) {
                res |= utils.powerOfTwo(i);
            }
            self.read_bit_index += 1;
            if (self.read_bit_index == 8) {
                self.read_bit_index = 0;
                self.read_index += 1;
            }
        }
        return res;
    }

    /// Assumes **little endian**
    fn readCompressionMethodAndFlags(self: *TestReaderWriter) CompressionMethodAndFlags {
        const res = [2]u8{ self.input[self.read_index], self.input[self.read_index + 1] };
        self.read_index += 2;
        return std.mem.bytesToValue(CompressionMethodAndFlags, &res);
    }

    fn skipToNextByte(self: *TestReaderWriter) void {
        if (self.read_bit_index == 0) {
            return;
        }
        self.read_bit_index = 0;
        self.read_index += 1;
    }

    fn readNLen(self: *TestReaderWriter) u16 {
        const bytesAsU16 = [2]u8{ self.input[self.read_index + 1], self.input[self.read_index] };
        self.read_index += 2;
        return @bitCast(bytesAsU16);
    }

    fn readLen(self: *TestReaderWriter) u16 {
        const bytesAsU16 = [2]u8{ self.input[self.read_index + 1], self.input[self.read_index] };
        self.read_index += 2;
        return @bitCast(bytesAsU16);
    }
};

// Fixed tables

const LITERAL_LENGTH_CODE_TABLE: [288]LiteralLengthCode = fill: {
    var table: [288]LiteralLengthCode = undefined;
    for (0..256) |c| {
        const char: u8 = @truncate(c);
        table[c] = .{ .Literal = char };
    }
    table[256] = .{ .EndOfBlock = {} };

    //         Extra               Extra               Extra
    // Code Bits Length(s) Code Bits Lengths   Code Bits Length(s)
    // ---- ---- ------     ---- ---- -------   ---- ---- -------
    //     257   0     3       267   1   15,16     277   4   67-82
    //     258   0     4       268   1   17,18     278   4   83-98
    //     259   0     5       269   2   19-22     279   4   99-114
    //     260   0     6       270   2   23-26     280   4  115-130
    //     261   0     7       271   2   27-30     281   5  131-162
    //     262   0     8       272   2   31-34     282   5  163-194
    //     263   0     9       273   3   35-42     283   5  195-226
    //     264   0    10       274   3   43-50     284   5  227-257
    //     265   1  11,12      275   3   51-58     285   0    258
    //     266   1  13,14      276   3   59-66

    table[257] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 3 } };
    table[258] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 4 } };
    table[259] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 5 } };
    table[260] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 6 } };
    table[261] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 7 } };
    table[262] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 8 } };
    table[263] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 9 } };
    table[264] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 10 } };

    table[265] = .{ .Length = LengthCode{ .extra_bits = 1, .min_value = 11 } };
    table[266] = .{ .Length = LengthCode{ .extra_bits = 1, .min_value = 13 } };
    table[267] = .{ .Length = LengthCode{ .extra_bits = 1, .min_value = 15 } };
    table[268] = .{ .Length = LengthCode{ .extra_bits = 1, .min_value = 17 } };

    table[269] = .{ .Length = LengthCode{ .extra_bits = 2, .min_value = 19 } };
    table[270] = .{ .Length = LengthCode{ .extra_bits = 2, .min_value = 23 } };
    table[271] = .{ .Length = LengthCode{ .extra_bits = 2, .min_value = 27 } };
    table[272] = .{ .Length = LengthCode{ .extra_bits = 2, .min_value = 31 } };

    table[273] = .{ .Length = LengthCode{ .extra_bits = 3, .min_value = 35 } };
    table[274] = .{ .Length = LengthCode{ .extra_bits = 3, .min_value = 43 } };
    table[275] = .{ .Length = LengthCode{ .extra_bits = 3, .min_value = 51 } };
    table[276] = .{ .Length = LengthCode{ .extra_bits = 3, .min_value = 59 } };

    table[277] = .{ .Length = LengthCode{ .extra_bits = 4, .min_value = 67 } };
    table[278] = .{ .Length = LengthCode{ .extra_bits = 4, .min_value = 83 } };
    table[279] = .{ .Length = LengthCode{ .extra_bits = 4, .min_value = 99 } };
    table[280] = .{ .Length = LengthCode{ .extra_bits = 4, .min_value = 115 } };

    table[281] = .{ .Length = LengthCode{ .extra_bits = 5, .min_value = 131 } };
    table[282] = .{ .Length = LengthCode{ .extra_bits = 5, .min_value = 163 } };
    table[283] = .{ .Length = LengthCode{ .extra_bits = 5, .min_value = 195 } };
    table[284] = .{ .Length = LengthCode{ .extra_bits = 5, .min_value = 227 } };
    table[285] = .{ .Length = LengthCode{ .extra_bits = 0, .min_value = 258 } };

    table[286] = .{ .Unused = {} };
    table[287] = .{ .Unused = {} };

    break :fill table;
};

const LITERAL_LENGTH_SYMBOLS: [288]u9 = fill: {
    comptime var symbols: [288]u9 = undefined;
    for (0..288) |i| {
        const symbol: u9 = @truncate(i);
        symbols[i] = symbol;
    }
    break :fill symbols;
};

const FIXED_LITERAL_LENGTH_LENGTHS: [288]usize = fill: {
    // Lit Value    Bits
    // ---------    ----
    //   0 - 143     8
    // 144 - 255     9
    // 256 - 279     7
    // 280 - 287     8
    comptime var lengths: [288]usize = undefined;
    fillPortion(0, 143, &lengths, 8);
    fillPortion(144, 255, &lengths, 9);
    fillPortion(256, 279, &lengths, 7);
    fillPortion(280, 287, &lengths, 8);
    break :fill lengths;
};

fn fillPortion(startInclusive: usize, endInclusive: usize, arr: []usize, value: usize) void {
    for (startInclusive..endInclusive + 1) |i| {
        arr[i] = value;
    }
}

const FIXED_LITERAL_LENGTH_HUFFMAN = blk: {
    comptime var comptime_fixed_literal_length_huffman_array: [1023]?u9 = undefined;
    @setEvalBranchQuota(100_000);
    const res = huffman.Huffman(u9).fromComptimeCodeLengths(&LITERAL_LENGTH_SYMBOLS, &FIXED_LITERAL_LENGTH_LENGTHS, &comptime_fixed_literal_length_huffman_array) catch @compileError("Error initializaing huffman code");
    break :blk res;
};

//         Extra           Extra               Extra
// Code Bits Dist  Code Bits   Dist     Code Bits Distance
// ---- ---- ----  ---- ----  ------    ---- ---- --------
// 0   0    1     10   4     33-48    20    9   1025-1536
// 1   0    2     11   4     49-64    21    9   1537-2048
// 2   0    3     12   5     65-96    22   10   2049-3072
// 3   0    4     13   5     97-128   23   10   3073-4096
// 4   1   5,6    14   6    129-192   24   11   4097-6144
// 5   1   7,8    15   6    193-256   25   11   6145-8192
// 6   2   9-12   16   7    257-384   26   12  8193-12288
// 7   2  13-16   17   7    385-512   27   12 12289-16384
// 8   3  17-24   18   8    513-768   28   13 16385-24576
// 9   3  25-32   19   8   769-1024   29   13 24577-32768
const DISTANCE_TABLE = [32]DistanceCode{
    DistanceCode{ .extra_bits = 0, .min_value = 1 },
    DistanceCode{ .extra_bits = 0, .min_value = 2 },
    DistanceCode{ .extra_bits = 0, .min_value = 3 },
    DistanceCode{ .extra_bits = 0, .min_value = 4 },

    DistanceCode{ .extra_bits = 1, .min_value = 5 },
    DistanceCode{ .extra_bits = 1, .min_value = 7 },

    DistanceCode{ .extra_bits = 2, .min_value = 9 },
    DistanceCode{ .extra_bits = 2, .min_value = 13 },

    DistanceCode{ .extra_bits = 3, .min_value = 17 },
    DistanceCode{ .extra_bits = 3, .min_value = 25 },

    DistanceCode{ .extra_bits = 4, .min_value = 33 },
    DistanceCode{ .extra_bits = 4, .min_value = 49 },

    DistanceCode{ .extra_bits = 5, .min_value = 65 },
    DistanceCode{ .extra_bits = 5, .min_value = 97 },

    DistanceCode{ .extra_bits = 6, .min_value = 129 },
    DistanceCode{ .extra_bits = 6, .min_value = 193 },

    DistanceCode{ .extra_bits = 7, .min_value = 257 },
    DistanceCode{ .extra_bits = 7, .min_value = 385 },

    DistanceCode{ .extra_bits = 8, .min_value = 513 },
    DistanceCode{ .extra_bits = 8, .min_value = 769 },

    DistanceCode{ .extra_bits = 9, .min_value = 1025 },
    DistanceCode{ .extra_bits = 9, .min_value = 1537 },

    DistanceCode{ .extra_bits = 10, .min_value = 2049 },
    DistanceCode{ .extra_bits = 10, .min_value = 3073 },

    DistanceCode{ .extra_bits = 11, .min_value = 4097 },
    DistanceCode{ .extra_bits = 11, .min_value = 6145 },

    DistanceCode{ .extra_bits = 12, .min_value = 8193 },
    DistanceCode{ .extra_bits = 12, .min_value = 12289 },

    DistanceCode{ .extra_bits = 13, .min_value = 16385 },
    DistanceCode{ .extra_bits = 13, .min_value = 24577 },

    DistanceCode{ .extra_bits = 0, .min_value = 0 },
    DistanceCode{ .extra_bits = 0, .min_value = 0 },
};

// Tests

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;

test "Decode" {
    const content = @embedFile("test-zlib/git-blob.z");
    const output = &[_]u8{};
    var testWR = TestReaderWriter{ .input = content, .output = output };
    try decode(&testWR, {});
}

test "Tables consistency" {
    for (0..256) |c| {
        const char: u8 = @truncate(c);
        try expect(LITERAL_LENGTH_CODE_TABLE[c].Literal == char);
    }

    try expectEqualDeep(LiteralLengthCode{ .EndOfBlock = {} }, LITERAL_LENGTH_CODE_TABLE[256]);

    for (257..284) |i| {
        const len = LITERAL_LENGTH_CODE_TABLE[i].Length;
        const next_len = LITERAL_LENGTH_CODE_TABLE[i + 1].Length;
        try expect(next_len.min_value == len.min_value + utils.powerOfTwo(len.extra_bits));
    }

    try expectEqualDeep(LiteralLengthCode{ .Length = LengthCode{ .extra_bits = 0, .min_value = 258 } }, LITERAL_LENGTH_CODE_TABLE[285]);
    try expectEqualDeep(LiteralLengthCode{ .Unused = {} }, LITERAL_LENGTH_CODE_TABLE[286]);
    try expectEqualDeep(LiteralLengthCode{ .Unused = {} }, LITERAL_LENGTH_CODE_TABLE[287]);

    for (0..29) |i| {
        const dist = DISTANCE_TABLE[i];
        const next_dist = DISTANCE_TABLE[i + 1];
        try expect(next_dist.min_value == dist.min_value + utils.powerOfTwo(dist.extra_bits));
    }
}

test "Memory layouts" {
    try expect(@sizeOf(LiteralLengthCode) == 4); // max is u16 + enum tag
    try expect(@sizeOf(DistanceCode) == 4); // max is u16 + extra_bits field
}

test "Fixed Hufffman Literal/Lengths codes" {

    // Lit Value    Bits   Codes
    // ---------    ----   -----
    //   0 - 143     8     00110000  through 10111111
    // 144 - 255     9    110010000  through 111111111
    // 256 - 279     7      0000000  through 0010111
    // 280 - 287     8     11000000  through 11000111

    for (0..144) |n| {
        const code: u9 = @truncate(n);
        try expectEqual(@as(?u9, code), FIXED_LITERAL_LENGTH_HUFFMAN.getCode(huffman.Code{ .bit_length = 8, .value = 0b0011_0000 + n }));
    }
    for (144..256) |n| {
        const code: u9 = @truncate(n);
        try expectEqual(@as(?u9, code), FIXED_LITERAL_LENGTH_HUFFMAN.getCode(huffman.Code{ .bit_length = 9, .value = 0b1_1001_0000 + n - 144 }));
    }

    for (256..280) |n| {
        const code: u9 = @truncate(n);
        try expectEqual(@as(?u9, code), FIXED_LITERAL_LENGTH_HUFFMAN.getCode(huffman.Code{ .bit_length = 7, .value = 0b000_0000 + n - 256 }));
    }

    for (280..288) |n| {
        const code: u9 = @truncate(n);
        try expectEqual(@as(?u9, code), FIXED_LITERAL_LENGTH_HUFFMAN.getCode(huffman.Code{ .bit_length = 8, .value = 0b1100_0000 + n - 280 }));
    }
}
