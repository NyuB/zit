const std = @import("std");

fn Huffman(comptime Symbol: type) type {
    return struct {
        // null => nodes, non-null => leaves
        arr: []?Symbol,
        allocator: std.mem.Allocator,

        const H = @This();

        pub fn deinit(self: *H) void {
            self.allocator.free(self.arr);
        }

        pub fn cursor(self: *const H) Cursor {
            return Cursor{ .huffman = self };
        }

        inline fn left(nodeIndex: usize) usize {
            return nodeIndex * 2 + 1;
        }

        inline fn right(nodeIndex: usize) usize {
            return nodeIndex * 2 + 2;
        }

        /// from RFC-1951 3.2.2 algorithm
        /// `symbols` should be in lexicographic order
        fn fromCodeLengths(allocator: std.mem.Allocator, symbols: []const Symbol, lengths: []const usize) CodeLengthInitError!H {
            if (symbols.len != lengths.len) return CodeLengthInitError.MismatchingCounts;

            var info = try CodeLengthInfo.init(allocator, lengths);
            defer info.deinit();

            const treeSize = powerOfTwo(info.max_length + 1) - 1; //2^depth(tree) - 1
            var arr = allocator.alloc(?Symbol, treeSize) catch return CodeLengthInitError.AllocationError;
            for (arr) |*s| {
                s.* = null;
            }

            for (symbols, 0..) |s, i| {
                insert(arr, 0, info.codes[i], s);
            }
            return .{ .arr = arr, .allocator = allocator };
        }

        fn insert(arr: []?Symbol, index: usize, code: Code, symbol: Symbol) void {
            if (code.bit_length == 0) {
                arr[index] = symbol;
                return;
            }
            if (code.firstBitSet()) {
                insert(arr, right(index), code.skipBit(), symbol);
            } else {
                insert(arr, left(index), code.skipBit(), symbol);
            }
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
    allocator: std.mem.Allocator,

    /// from RFC-1951 3.2.2 algorithm
    fn init(allocator: std.mem.Allocator, lengths: []const usize) CodeLengthInitError!CodeLengthInfo {
        var max_length: usize = sliceMax(lengths);

        var length_occurences = allocator.alloc(usize, max_length + 1) catch return CodeLengthInitError.AllocationError;
        defer allocator.free(length_occurences);

        for (length_occurences) |*o| {
            o.* = 0;
        }

        for (lengths) |l| {
            length_occurences[l] += 1;
            if (length_occurences[l] > powerOfTwo(l)) {
                return CodeLengthInitError.IllegalCodeLengthCount;
            }
        }

        var codes = allocator.alloc(Code, lengths.len) catch return CodeLengthInitError.AllocationError;
        var codeValue: usize = 0;
        var next_code = allocator.alloc(usize, max_length + 1) catch return CodeLengthInitError.AllocationError;
        defer allocator.free(next_code);

        for (1..max_length + 1) |bits| {
            codeValue = (codeValue + length_occurences[bits - 1]) << 1;
            next_code[bits] = codeValue;
        }

        for (lengths, 0..) |l, i| {
            codes[i] = Code{ .bit_length = l, .value = next_code[l] };
            next_code[l] += 1;
        }

        return .{ .max_length = max_length, .allocator = allocator, .codes = codes };
    }

    fn deinit(self: *CodeLengthInfo) void {
        self.allocator.free(self.codes);
    }

    fn sliceMax(s: []const usize) usize {
        var res: usize = 0;
        for (s) |u| {
            res = @max(u, res);
        }
        return res;
    }
};

const Code = struct {
    value: usize,
    bit_length: usize,

    fn firstBitSet(self: Code) bool {
        const oneBitMask = powerOfTwo(self.bit_length - 1);
        return self.value & oneBitMask > 0;
    }

    fn skipBit(self: Code) Code {
        return Code{ .value = self.value, .bit_length = self.bit_length - 1 };
    }
};

inline fn powerOfTwo(n: usize) usize {
    return std.math.shl(usize, 1, n);
}

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

test "fromCodeLengths single symbol" {
    const symbols = "A";
    const lengths = &[_]usize{1};
    var huffman = try Huffman(u8).fromCodeLengths(std.testing.allocator, symbols, lengths);
    defer huffman.deinit();
    var cursor = huffman.cursor();
    try std.testing.expectEqual(@as(?u8, 'A'), cursor.next(false));
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
