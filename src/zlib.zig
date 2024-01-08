const std = @import("std");
const utils = @import("utils.zig");
const huffman = @import("huffman.zig");

const DecodeErrors = error{
    AllocationError,
    IllegalBlockType,
    IllegalCodeLength,
    IllegalCompressionMethod,
    IllegalFlagCheck,
    IllegalLiteralLength,
    MismatchingCheckSum,
    Unexpected,
    NotImplemented,
};

fn decode(allocator: std.mem.Allocator, reader: anytype, writer: anytype) DecodeErrors!void {
    const compressionMethodAndFlags = reader.readCompressionMethodAndFlags();
    if (compressionMethodAndFlags.flagDict) return DecodeErrors.NotImplemented;

    switch (compressionMethodAndFlags.compressionMethod) {
        8 => {},
        else => return DecodeErrors.NotImplemented,
    }

    try compressionMethodAndFlags.check();

    var b_final = false;
    while (!b_final) {
        b_final = reader.readBits(1) > 0;
        const blockType: BlockType = @enumFromInt(reader.readBitsRev(2));
        switch (blockType) {
            .Raw => return DecodeErrors.NotImplemented,
            .Fixed => {
                block: while (true) {
                    switch (readLiteralLength(reader)) {
                        .Literal => |c| writer.write(c),
                        .Length => |l| {
                            _ = l;
                            return DecodeErrors.NotImplemented;
                        },
                        .EndOfBlock => {
                            break :block;
                        },
                        .Unused => return DecodeErrors.IllegalLiteralLength,
                    }
                }
            },
            .Dynamic => {
                var codex = try DynamicCodex.init(allocator, reader);
                defer codex.deinit();
                try readBlock(codex, reader, writer);
            },
            .Reserved => return DecodeErrors.IllegalBlockType,
        }
    }
    reader.skipToNextByte();
    const checkSum = readCheckSum(reader);
    const actualCheckSum = writer.computeAdler32AndReset();
    if (checkSum != actualCheckSum) return DecodeErrors.MismatchingCheckSum;
}

fn readCheckSum(reader: anytype) u32 {
    const res: u32 = @truncate(reader.readBitsRev(32));
    return @byteSwap(res);
}

fn readBlock(codex: anytype, reader: anytype, writer: anytype) DecodeErrors!void {
    block: while (true) {
        switch (codex.readLiteralLength(reader)) {
            .Literal => |c| writer.write(c),
            .Length => |l| {
                const len = l.min_value + reader.readBitsRev(l.extra_bits);
                const d = codex.readDistance(reader);
                const distance: usize = d.min_value + reader.readBitsRev(d.extra_bits);
                writer.writeFromPast(len, distance);
            },
            .EndOfBlock => break :block,
            .Unused => return DecodeErrors.IllegalLiteralLength,
        }
    }
}

const DynamicCodex = struct {
    literalLengths: huffman.Huffman(u9),
    distances: huffman.Huffman(u5),

    fn init(allocator: std.mem.Allocator, reader: anytype) DecodeErrors!DynamicCodex {
        const hlit = reader.readBitsRev(5);
        const hdist = reader.readBitsRev(5);
        const hlen = reader.readBitsRev(4);

        var dynamicCodeLength = try DynamicCodeLength.init(allocator, hlen + 4, reader);
        defer dynamicCodeLength.deinit();

        var literalLengthCode = try dynamicCodeLength.buildHuffmanCode(allocator, u9, &LITERAL_LENGTH_SYMBOLS, hlit + 257, reader);
        errdefer literalLengthCode.deinit();

        var distanceCode = try dynamicCodeLength.buildHuffmanCode(allocator, u5, &DISTANCE_CODE_SYMBOLS, hdist + 1, reader);
        errdefer distanceCode.deinit();

        return .{ .literalLengths = literalLengthCode, .distances = distanceCode };
    }

    fn readLiteralLength(self: DynamicCodex, reader: anytype) LiteralLengthCode {
        const index = readSymbol(u9, self.literalLengths, reader);
        return LITERAL_LENGTH_CODE_TABLE[index];
    }

    fn readDistance(self: DynamicCodex, reader: anytype) DistanceCode {
        const index = readSymbol(u5, self.distances, reader);
        return DISTANCE_TABLE[index];
    }

    fn deinit(self: *DynamicCodex) void {
        self.literalLengths.deinit();
        self.distances.deinit();
    }
};

const DynamicCodeLength = struct {
    huffmanCode: huffman.Huffman(u5),

    fn init(allocator: std.mem.Allocator, lengthsToRead: usize, reader: anytype) DecodeErrors!DynamicCodeLength {
        var codeLengthAlphabet: [19]usize = undefined;
        for (0..19) |i| {
            codeLengthAlphabet[i] = 0;
        }
        for (0..lengthsToRead) |l| {
            codeLengthAlphabet[DYNAMIC_CODE_LENGTH_SYMBOLS_ORDER[l]] = reader.readBitsRev(3);
        }
        var huffmanCode = huffman.Huffman(u5).fromCodeLengths(allocator, &DYNAMIC_CODE_LENGTH_SYMBOLS, &codeLengthAlphabet) catch return DecodeErrors.Unexpected;
        return .{ .huffmanCode = huffmanCode };
    }

    fn deinit(self: *DynamicCodeLength) void {
        self.huffmanCode.deinit();
    }

    fn buildHuffmanCode(self: DynamicCodeLength, allocator: std.mem.Allocator, comptime Symbol: type, symbols: []const Symbol, lengthsToRead: usize, reader: anytype) DecodeErrors!huffman.Huffman(Symbol) {
        var lengths = allocator.alloc(usize, symbols.len) catch return DecodeErrors.AllocationError;
        defer allocator.free(lengths);
        for (0..symbols.len) |i| {
            lengths[i] = 0;
        }
        var index: usize = 0;
        while (index < lengthsToRead) {
            index = try self.readOneCodeLength(reader, lengths, index);
        }
        if (index != lengthsToRead) return DecodeErrors.Unexpected;
        return huffman.Huffman(Symbol).fromCodeLengths(allocator, symbols, lengths) catch return DecodeErrors.Unexpected;
    }

    fn readOneCodeLength(self: DynamicCodeLength, reader: anytype, output: []usize, outputIndex: usize) DecodeErrors!usize {
        const s = readSymbol(u5, self.huffmanCode, reader);
        switch (s) {
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 => {
                output[outputIndex] = s;
                return outputIndex + 1;
            },
            16 => {
                const extra = reader.readBitsRev(2);
                for (0..extra + 3) |i| {
                    output[outputIndex + i] = output[outputIndex - 1];
                }
                return outputIndex + extra + 3;
            },
            17 => {
                const extra = reader.readBitsRev(3);
                for (0..extra + 3) |i| {
                    output[outputIndex + i] = 0;
                }
                return outputIndex + extra + 3;
            },
            18 => {
                const extra = reader.readBitsRev(7);
                for (0..extra + 11) |i| {
                    output[outputIndex + i] = 0;
                }
                return outputIndex + extra + 11;
            },
            else => return DecodeErrors.IllegalCodeLength,
        }
    }
};

fn readSymbol(comptime Symbol: type, h: huffman.Huffman(Symbol), reader: anytype) Symbol {
    var s: ?Symbol = null;
    var cursor = h.cursor();
    while (s == null) {
        const b = reader.readBits(1);
        s = cursor.next(b > 0);
    }
    return s orelse unreachable;
}

fn readLiteralLength(reader: anytype) LiteralLengthCode {
    const s = readSymbol(u9, FIXED_LITERAL_LENGTH_HUFFMAN, reader);
    return LITERAL_LENGTH_CODE_TABLE[s];
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

const DISTANCE_CODE_SYMBOLS = [32]u5{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 };

const DYNAMIC_CODE_LENGTH_SYMBOLS = [19]u5{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 };
const DYNAMIC_CODE_LENGTH_SYMBOLS_ORDER = [19]usize{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

// Tests

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualStrings = std.testing.expectEqualStrings;

test "decode (only literals)" {
    const content = @embedFile("test-zlib/git-blob.z");
    var output: [16]u8 = undefined;
    var testWR = TestReaderWriter{ .input = content, .output = &output };
    try decode(std.testing.allocator, &testWR, &testWR);
    try expectEqualStrings("blob 9\x00Hello Zit", testWR.written());
}

test "decode (dynamic encoding)" {
    const content = @embedFile("test-zlib/poeme.z");
    var output: [1000]u8 = undefined;
    var testWR = TestReaderWriter{ .input = content, .output = &output };
    try decode(std.testing.allocator, &testWR, &testWR);
    const expected =
        \\Demain, dès l'aube, à l'heure où blanchit la campagne,
        \\Je partirai. Vois-tu, je sais que tu m'attends.
        \\J'irai par la forêt, j'irai par la montagne.
        \\Je ne puis demeurer loin de toi plus longtemps.
        \\
        \\Je marcherai les yeux fixés sur mes pensées,
        \\Sans rien voir au dehors, sans entendre aucun bruit,
        \\Seul, inconnu, le dos courbé, les mains croisées,
        \\Triste, et le jour pour moi sera comme la nuit.
        \\
        \\Je ne regarderai ni l'or du soir qui tombe,
        \\Ni les voiles au loin descendant vers Harfleur,
        \\Et quand j'arriverai, je mettrai sur ta tombe
        \\Un bouquet de houx vert et de bruyère en fleur.
    ;
    try expectEqualStrings(expected, testWR.written());
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

const TestReaderWriter = struct {
    input: []const u8,
    output: []u8,

    read_index: usize = 0,
    read_bit_index: u4 = 0,
    write_index: usize = 0,
    adler32: std.hash.Adler32 = std.hash.Adler32.init(),

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

    fn write(self: *TestReaderWriter, b: u8) void {
        self.output[self.write_index] = b;
        self.adler32.update(self.output[self.write_index .. self.write_index + 1]);
        self.write_index += 1;
    }

    fn writeSlice(self: *TestReaderWriter, bs: []const u8) void {
        @memcpy(self.output[self.write_index..], bs);
        self.adler32.update(bs);
        self.write_index += bs.len;
    }

    fn writeFromPast(self: *TestReaderWriter, len: usize, distance: usize) void {
        for (0..len) |i| {
            self.output[self.write_index + i] = self.output[self.write_index - distance + i];
        }
        self.adler32.update(self.output[self.write_index .. self.write_index + len]);
        self.write_index += len;
    }

    fn written(self: TestReaderWriter) []const u8 {
        return self.output[0..self.write_index];
    }

    fn computeAdler32AndReset(self: *TestReaderWriter) u32 {
        const res = self.adler32.final();
        self.adler32 = std.hash.Adler32.init();
        return res;
    }
};
