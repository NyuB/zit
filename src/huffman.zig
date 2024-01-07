const std = @import("std");
const utils = @import("utils.zig");

pub fn Huffman(comptime Symbol: type) type {
    return struct {
        // null => nodes, non-null => leaves
        arr: []?Symbol,
        allocator: ?std.mem.Allocator,

        const H = @This();

        pub fn deinit(self: *H) void {
            if (self.allocator) |a| {
                a.free(self.arr);
            }
        }

        pub fn cursor(self: *const H) Cursor {
            return Cursor{ .huffman = self };
        }

        pub fn getCode(self: H, code: Code) ?Symbol {
            var current_cursor = self.cursor();
            var res: ?Symbol = null;
            var current_code = code;
            for (0..code.bit_length) |_| {
                res = current_cursor.next(current_code.firstBitSet());
                current_code = current_code.skipBit();
            }
            return res;
        }

        /// `symbols` should be in lexicographic order
        pub fn fromCodeLengths(allocator: std.mem.Allocator, symbols: []const Symbol, lengths: []const usize) CodeLengthInitError!H {
            if (symbols.len != lengths.len) return CodeLengthInitError.MismatchingCounts;

            var info = try CodeLengthInfo.init(allocator, lengths);
            defer info.deinit();

            const treeSize = utils.powerOfTwo(info.max_length + 1) - 1; //2^depth(tree) - 1
            var arr = allocator.alloc(?Symbol, treeSize) catch return CodeLengthInitError.AllocationError;
            for (arr) |*s| {
                s.* = null;
            }

            _fromCodeLengths(arr, symbols, info);

            return .{ .arr = arr, .allocator = allocator };
        }

        /// `symbols` should be in lexicographic order
        ///
        /// `backingTreeArray` must have exactly the required size to hold the corresponding huffman tree = 2^max(`lengths`) - 1
        pub fn fromComptimeCodeLengths(comptime symbols: []const Symbol, comptime lengths: []const usize, comptime backingTreeArray: []?Symbol) CodeLengthInitError!H {
            if (symbols.len != lengths.len) return CodeLengthInitError.MismatchingCounts;

            comptime var info = try CodeLengthInfo.comptimeInit(lengths);
            const treeSize = comptime utils.powerOfTwo(info.max_length + 1) - 1; //2^depth(tree) - 1
            if (treeSize > backingTreeArray.len) {
                @compileError("Backing array size is insufficient to hold huffman code tree");
            }
            if (treeSize < backingTreeArray.len) {
                @compileError("Backing array is larger than necessary to hold huffman code tree");
            }

            for (0..backingTreeArray.len) |i| {
                backingTreeArray[i] = null;
            }
            _fromCodeLengths(backingTreeArray, symbols, info);

            return .{ .arr = backingTreeArray, .allocator = null };
        }

        fn _fromCodeLengths(arr: []?Symbol, symbols: []const Symbol, info: CodeLengthInfo) void {
            for (symbols, 0..) |s, i| {
                if (info.codes[i].bit_length > 0) { // Ignore lengths 0
                    insert(arr, 0, info.codes[i], s);
                }
            }
        }

        fn insert(arr: []?Symbol, index: usize, code: Code, symbol: Symbol) void {
            var current_code = code;
            var current_index = index;
            while (current_code.bit_length != 0) : (current_code = current_code.skipBit()) {
                if (current_code.firstBitSet()) {
                    current_index = right(current_index);
                } else {
                    current_index = left(current_index);
                }
            }
            arr[current_index] = symbol;
        }

        inline fn left(nodeIndex: usize) usize {
            return nodeIndex * 2 + 1;
        }

        inline fn right(nodeIndex: usize) usize {
            return nodeIndex * 2 + 2;
        }

        pub const Cursor = struct {
            current: usize = 0, // root node
            huffman: *const H,

            pub fn next(self: *Cursor, b: bool) ?Symbol {
                if (b) {
                    self.current = right(self.current);
                } else {
                    self.current = left(self.current);
                }
                const res = self.huffman.arr[self.current];
                if (res != null) {
                    self.current = 0;
                }
                return res;
            }
        };
    };
}

const CodeLengthInitError = error{
    MismatchingCounts,
    IllegalCodeLengthCount,
    AllocationError,
};

const CodeLengthInfo = struct {
    codes: []const Code,
    max_length: usize,
    allocator: ?std.mem.Allocator,

    /// from RFC-1951 3.2.2 algorithm
    fn init(allocator: std.mem.Allocator, lengths: []const usize) CodeLengthInitError!CodeLengthInfo {
        var max_length: usize = sliceMax(lengths);

        var length_occurences = allocator.alloc(usize, max_length + 1) catch return CodeLengthInitError.AllocationError;
        defer allocator.free(length_occurences);

        var codes = allocator.alloc(Code, lengths.len) catch return CodeLengthInitError.AllocationError;
        errdefer allocator.free(codes);

        var next_code = allocator.alloc(usize, max_length + 1) catch return CodeLengthInitError.AllocationError;
        defer allocator.free(next_code);

        try _initCodes(length_occurences, next_code, codes, lengths, max_length);

        return .{ .max_length = max_length, .allocator = allocator, .codes = codes };
    }

    fn comptimeInit(comptime lengths: []const usize) CodeLengthInitError!CodeLengthInfo {
        var max_length: usize = comptime sliceMaxComptime(lengths);
        var length_occurences: [max_length + 1]usize = undefined;

        var codes: [lengths.len]Code = undefined;

        var next_code: [max_length + 1]usize = undefined;
        try _initCodes(&length_occurences, &next_code, &codes, lengths, max_length);
        return CodeLengthInfo{ .allocator = null, .max_length = max_length, .codes = &codes };
    }

    fn _initCodes(length_occurences_buffer: []usize, next_code_buffer: []usize, codes_out: []Code, lengths: []const usize, max_length: usize) CodeLengthInitError!void {
        for (length_occurences_buffer) |*o| {
            o.* = 0;
        }

        for (lengths) |l| {
            if (l == 0) continue;
            length_occurences_buffer[l] += 1;
            if (length_occurences_buffer[l] > utils.powerOfTwo(l)) {
                return CodeLengthInitError.IllegalCodeLengthCount;
            }
        }

        var codeValue: usize = 0;

        for (1..max_length + 1) |bits| {
            codeValue = (codeValue + length_occurences_buffer[bits - 1]) << 1;
            next_code_buffer[bits] = codeValue;
        }

        for (lengths, 0..) |l, i| {
            codes_out[i] = Code{ .bit_length = l, .value = next_code_buffer[l] };
            next_code_buffer[l] += 1;
        }
    }

    fn deinit(self: *CodeLengthInfo) void {
        if (self.allocator) |a| {
            a.free(self.codes);
        }
    }

    fn sliceMax(s: []const usize) usize {
        var res: usize = 0;
        for (s) |u| {
            res = @max(u, res);
        }
        return res;
    }

    fn sliceMaxComptime(comptime s: []const usize) usize {
        var res: usize = 0;
        for (s) |u| {
            res = @max(u, res);
        }
        return res;
    }
};

pub const Code = struct {
    value: usize,
    bit_length: usize,

    fn firstBitSet(self: Code) bool {
        const oneBitMask = utils.powerOfTwo(self.bit_length - 1);
        return self.value & oneBitMask > 0;
    }

    fn skipBit(self: Code) Code {
        return Code{ .value = self.value, .bit_length = self.bit_length - 1 };
    }
};

// Tests

test "fromCodeLengths: RFC-1951 example" {
    const symbols = "ABCDEFGH";
    const lengths = [_]usize{ 3, 3, 3, 3, 3, 2, 4, 4 };

    var huffman = try Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, &lengths);
    defer huffman.deinit();

    // Symbol Length   Code
    // ------ ------   ----
    // A       3        010
    // B       3        011
    // C       3        100
    // D       3        101
    // E       3        110
    // F       2         00
    // G       4       1110
    // H       4       1111

    try expectSymbol(u8, 'A', huffman, Code{ .value = 0b010, .bit_length = 3 });
    try expectSymbol(u8, 'B', huffman, Code{ .value = 0b011, .bit_length = 3 });
    try expectSymbol(u8, 'C', huffman, Code{ .value = 0b100, .bit_length = 3 });
    try expectSymbol(u8, 'D', huffman, Code{ .value = 0b101, .bit_length = 3 });
    try expectSymbol(u8, 'E', huffman, Code{ .value = 0b110, .bit_length = 3 });
    try expectSymbol(u8, 'F', huffman, Code{ .value = 0b00, .bit_length = 2 });
    try expectSymbol(u8, 'G', huffman, Code{ .value = 0b1110, .bit_length = 4 });
    try expectSymbol(u8, 'H', huffman, Code{ .value = 0b1111, .bit_length = 4 });
}

var comptimeBackingArray: [31]?u8 = undefined;
test "fromComptimeCodeLengths: RFC-1951 example" {
    const symbols = "ABCDEFGH";
    const lengths = [_]usize{ 3, 3, 3, 3, 3, 2, 4, 4 };

    var huffman = try Huffman(u8).fromComptimeCodeLengths(symbols, &lengths, &comptimeBackingArray);

    try expectSymbol(u8, 'A', huffman, Code{ .value = 0b010, .bit_length = 3 });
    try expectSymbol(u8, 'B', huffman, Code{ .value = 0b011, .bit_length = 3 });
    try expectSymbol(u8, 'C', huffman, Code{ .value = 0b100, .bit_length = 3 });
    try expectSymbol(u8, 'D', huffman, Code{ .value = 0b101, .bit_length = 3 });
    try expectSymbol(u8, 'E', huffman, Code{ .value = 0b110, .bit_length = 3 });
    try expectSymbol(u8, 'F', huffman, Code{ .value = 0b00, .bit_length = 2 });
    try expectSymbol(u8, 'G', huffman, Code{ .value = 0b1110, .bit_length = 4 });
    try expectSymbol(u8, 'H', huffman, Code{ .value = 0b1111, .bit_length = 4 });
    try std.testing.expect(huffman.getCode(Code{ .bit_length = 3, .value = 0b011 }) == 'B');
}

test "fromCodeLengths single symbol" {
    const symbols = "A";
    const lengths = &[_]usize{1};
    var huffman = try Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, lengths);
    defer huffman.deinit();
    var cursor = huffman.cursor();
    try std.testing.expectEqual(@as(?u8, 'A'), cursor.next(false));
}

test "fromCodeLengths ignore zero length" {
    const symbols = "ABCDEFGH";
    const lengths = &[_]usize{ 1, 0, 2, 0, 0, 0, 0, 2 };
    var huffman = try Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, lengths);
    defer huffman.deinit();
    try std.testing.expectEqualSlices(?u8, &[_]?u8{ null, 'A', null, null, null, 'C', 'H' }, huffman.arr);
}

test "fromCodeLengths illegal input (too many occurence of a given code length)" {
    const symbols = "ABC";
    const lengths = &[_]usize{ 1, 1, 1 };
    const huffman = Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, lengths);
    try std.testing.expectError(CodeLengthInitError.IllegalCodeLengthCount, huffman);
}

test "fromCodeLengths illegal input (symbols and lengths counts differ)" {
    const symbols = "A";
    const lengths = &[_]usize{ 1, 1 };
    const huffman = Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, lengths);
    try std.testing.expectError(CodeLengthInitError.MismatchingCounts, huffman);
}

fn expectSymbol(comptime S: type, expected: S, huffman: Huffman(S), code: Code) !void {
    var cursor = huffman.cursor();
    var currentCode = code;
    var symbol: ?S = null;
    for (0..code.bit_length - 1) |_| {
        symbol = cursor.next(currentCode.firstBitSet());
        try std.testing.expectEqual(@as(?S, null), symbol);
        currentCode = currentCode.skipBit();
    }

    var actual = cursor.next(currentCode.firstBitSet());
    try std.testing.expectEqual(expected, actual orelse unreachable);
}
