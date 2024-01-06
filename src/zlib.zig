const std = @import("std");
const utils = @import("utils.zig");

const DecodeErrors = error{ IllegalFlagCheck, ReservedBlockType };

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
            .Fixed => {},
            .Dynamic => unreachable,
            .Reserved => return DecodeErrors.ReservedBlockType,
        }
    }
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

const TestReaderWriter = struct {
    input: []const u8,
    output: []u8,

    read_index: usize = 0,
    read_bit_index: u3 = 0,
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
