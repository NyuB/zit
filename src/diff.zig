const std = @import("std");

const DiffTag = enum(u2) {
    Add,
    Del,
};

fn DiffItem(comptime T: type) type {
    return union(DiffTag) {
        Add: struct {
            position: usize,
            symbols: []const T,
        },
        Del: struct { position: usize },
    };
}

fn Diff(comptime T: type) type {
    return []const DiffItem(T);
}

const KArray = struct {
    arr: []usize,
    d: i64,
    allocator: std.mem.Allocator,
    fn init(allocator: std.mem.Allocator, d: usize) !KArray {
        var arr = try allocator.alloc(usize, d * 2 + 1);
        return .{ .arr = arr, .d = @intCast(d), .allocator = allocator };
    }

    fn set(self: *KArray, signedIndex: i64, value: usize) void {
        const index: usize = @intCast(signedIndex + self.d);
        self.arr[index] = value;
    }

    fn get(self: KArray, signedIndex: i64) usize {
        const index: usize = @intCast(signedIndex + self.d);
        return self.arr[index];
    }

    fn deinit(self: *KArray) void {
        self.allocator.free(self.arr);
    }

    fn copy(self: KArray) !KArray {
        var arrCopy = try self.allocator.alloc(usize, self.arr.len);
        std.mem.copy(usize, arrCopy, self.arr);
        return .{ .arr = arrCopy, .d = self.d, .allocator = self.allocator };
    }
};

pub fn Myers(comptime T: type, comptime eq: fn (T, T) callconv(.Inline) bool) type {
    const BackTracker = struct {
        reverseDiff: std.ArrayList(DiffItem(T)),
        target: []const T,
        const Self = @This();
        fn init(allocator: std.mem.Allocator, dMax: usize, target: []const T) !Self {
            var arr = try std.ArrayList(DiffItem(T)).initCapacity(allocator, dMax);
            return .{ .reverseDiff = arr, .target = target };
        }

        fn deinit(self: *Self) void {
            self.reverseDiff.deinit();
        }

        fn deletion(self: *Self, position: usize) void {
            self.reverseDiff.appendAssumeCapacity(DiffItem(T){ .Del = .{ .position = position } });
        }

        fn insertion(self: *Self, position: usize, targetIndex: usize) void {
            self.reverseDiff.appendAssumeCapacity(DiffItem(T){ .Add = .{ .position = position, .symbols = self.target[targetIndex .. targetIndex + 1] } });
        }

        fn toOwnedSlice(self: *Self) ![]const DiffItem(T) {
            if (self.reverseDiff.items.len >= 2) {
                const half = self.reverseDiff.items.len / 2;
                for (0..half) |i| {
                    const mirror = self.reverseDiff.items.len - 1 - i;
                    const save = self.reverseDiff.items[i];
                    self.reverseDiff.items[i] = self.reverseDiff.items[mirror];
                    self.reverseDiff.items[mirror] = save;
                }
            }
            return try self.reverseDiff.toOwnedSlice();
        }
    };

    return struct {
        pub fn diff(allocator: std.mem.Allocator, original: []const T, target: []const T) !Diff(T) {
            const n = original.len;
            const m = target.len;
            const dMax = n + m;
            if (dMax == 0) return try noDiff(allocator);
            if (n == 0) return try addTarget(allocator, target);
            if (m == 0) return try delOriginal(allocator, original.len);

            var history = std.ArrayList(KArray).init(allocator);
            defer {
                for (history.items) |*i| {
                    i.deinit();
                }
                history.deinit();
            }
            var v = try KArray.init(allocator, dMax);
            v.set(1, 0);
            for (0..dMax) |d| {
                const kMax: i64 = @intCast(d);
                const kMin = -kMax;
                var k = kMin;
                while (k <= kMax) : (k += 2) {
                    var x: usize = if (chooseDecreaseDiagonal(k, kMin, kMax, v)) blk: {
                        // Increase y <==> Add
                        break :blk v.get(k + 1);
                    } else blk: {
                        // Increase x <==> Del
                        break :blk v.get(k - 1) + 1;
                    };

                    var y: usize = y_of_x_and_k(x, k);
                    while (x < n and y < m and eq(original[x], target[y])) {
                        x += 1;
                        y += 1;
                    }
                    v.set(k, x);

                    if (x >= n and y >= m) {
                        try history.append(v);
                        var backTracker = try BackTracker.init(allocator, dMax, target);
                        errdefer backTracker.deinit();
                        backTrack(&backTracker, history.items, d, x, y, k);
                        return try backTracker.toOwnedSlice();
                    }
                }
                try history.append(try v.copy());
            }
            unreachable;
        }

        fn backTrack(backTracker: *BackTracker, history: []const KArray, d: usize, xEnd: usize, yEnd: usize, kEnd: i64) void {
            var k = kEnd;
            var x = xEnd;
            var y = yEnd;
            var dBack = d;
            while ((x > 0 or y > 0) and dBack >= 1) : (dBack -= 1) {
                const kBackMax: i64 = @intCast(dBack);
                const kBackMin: i64 = -kBackMax;
                var vH = history[dBack - 1];
                if (chooseDecreaseDiagonal(k, kBackMin, kBackMax, vH)) {
                    k = k + 1;
                    x = vH.get(k);
                    y = y_of_x_and_k(x, k);
                    backTracker.insertion(x, y);
                } else {
                    k = k - 1;
                    x = vH.get(k);
                    y = y_of_x_and_k(x, k);
                    backTracker.deletion(x + 1);
                }
            }
        }

        fn addTarget(allocator: std.mem.Allocator, target: []const T) !Diff(T) {
            var res = try allocator.alloc(DiffItem(T), 1);
            res[0] = DiffItem(T){ .Add = .{ .position = 0, .symbols = target } };
            return res;
        }

        fn delOriginal(allocator: std.mem.Allocator, len: usize) !Diff(T) {
            var res = try allocator.alloc(DiffItem(T), len);
            for (0..len) |i| {
                res[i] = DiffItem(T){ .Del = .{ .position = i + 1 } };
            }
            return res;
        }

        inline fn noDiff(allocator: std.mem.Allocator) !Diff(T) {
            return try allocator.alloc(DiffItem(T), 0);
        }

        fn chooseDecreaseDiagonal(k: i64, kMin: i64, kMax: i64, v: KArray) bool {
            return k == kMin or (k != kMax and v.get(k - 1) < v.get(k + 1));
        }

        fn y_of_x_and_k(x: usize, k: i64) usize {
            var sx: i64 = @intCast(x);
            return @intCast(sx - k);
        }
    };
}

// Tests
const String = []const u8;
const Lines = []const String;
const ExpectTest = @import("zunit.zig").ExpectTest;

test "Brute diff" {
    const original = [_]String{
        "Je vis cette faucheuse,",
        "Elle était dans son champ,",
    };
    const target = [_]String{
        "Elle allait à grands pas moissonnant et fauchant,",
        "Noir squelette laissant passer le crépuscule,",
    };
    const diff = try bruteDiff(std.testing.allocator, String, &original, &target);
    defer std.testing.allocator.free(diff);
    var et = ExpectTest.init(std.testing.allocator);
    defer et.deinit();

    try printDiff(&et, diff, &original);

    try et.expect(
        \\- Je vis cette faucheuse,
        \\- Elle était dans son champ,
        \\+ Elle allait à grands pas moissonnant et fauchant,
        \\+ Noir squelette laissant passer le crépuscule,
    );
    try et.end();
}

test "Myers diff on code sample" {
    const original = [_]String{
        "def f(n):",
        "    k = n * (n - 1)",
        "    return k / 2",
    };
    const corrected = [_]String{
        "def f(n):",
        "    k = n * (n + 1)",
        "    return k / 2",
    };
    var diff = try Myers(String, strEq).diff(std.testing.allocator, &original, &corrected);
    defer std.testing.allocator.free(diff);
    var et = ExpectTest.init(std.testing.allocator);
    defer et.deinit();
    try printDiff(&et, diff, &original);
    try et.expect(
        \\-     k = n * (n - 1)
        \\+     k = n * (n + 1)
    );
    var writer = et.stringWriter();
    try applyDiff(String, diff, &original, writer);
    try et.expect(
        \\def f(n):
        \\    k = n * (n + 1)
        \\    return k / 2
    );
    try et.end();
}

test "Sample diff from Myers paper" {
    var result = std.ArrayList(u8).init(std.testing.allocator);
    defer result.deinit();
    var writer = result.writer();

    const original = "abcabba";
    const expected = "cbabac";
    const diff = [_]DiffItem(u8){
        DiffItem(u8){ .Del = .{ .position = 1 } },
        DiffItem(u8){ .Del = .{ .position = 2 } },
        DiffItem(u8){ .Add = .{ .position = 3, .symbols = &[_]u8{'b'} } },
        DiffItem(u8){ .Del = .{ .position = 6 } },
        DiffItem(u8){ .Add = .{ .position = 7, .symbols = &[_]u8{'c'} } },
    };
    try applyDiff(u8, &diff, original, writer);
    try std.testing.expectEqualStrings(expected, result.items);
}

test "Multiple inserts at once" {
    var result = std.ArrayList(u8).init(std.testing.allocator);
    defer result.deinit();
    var writer = result.writer();

    const original = "xxAAA";
    const expected = "AAAAAA";
    const diff = [_]DiffItem(u8){
        DiffItem(u8){ .Del = .{ .position = 1 } },
        DiffItem(u8){ .Del = .{ .position = 2 } },
        DiffItem(u8){ .Add = .{ .position = 2, .symbols = "AAA" } },
    };
    try applyDiff(u8, &diff, original, writer);
    try std.testing.expectEqualStrings(expected, result.items);
}

test "KArray" {
    var arrOdd = try KArray.init(std.testing.allocator, 1);
    defer arrOdd.deinit();
    var arrEven = try KArray.init(std.testing.allocator, 2);
    defer arrEven.deinit();

    arrOdd.set(-1, 0);
    arrOdd.set(0, 1);
    arrOdd.set(1, 2);
    try std.testing.expect(arrOdd.get(-1) == 0);
    try std.testing.expect(arrOdd.get(0) == 1);
    try std.testing.expect(arrOdd.get(1) == 2);

    arrEven.set(2, 4);
    arrEven.set(-2, 0);
    arrEven.set(1, 3);
    arrEven.set(-1, 1);
    arrEven.set(0, 2);
    try std.testing.expect(arrEven.get(-2) == 0);
    try std.testing.expect(arrEven.get(-1) == 1);
    try std.testing.expect(arrEven.get(0) == 2);
    try std.testing.expect(arrEven.get(1) == 3);
    try std.testing.expect(arrEven.get(2) == 4);
}

test "Paper sample" {
    const original = "abcabba";
    const target = "cbabac";
    const diff = try Myers(u8, charEq).diff(std.testing.allocator, original, target);
    defer std.testing.allocator.free(diff);
    try std.testing.expectEqual(@as(usize, 5), diff.len);
    try std.testing.expectEqualDeep(DiffItem(u8){ .Del = .{ .position = 1 } }, diff[0]);
    try std.testing.expectEqualDeep(DiffItem(u8){ .Del = .{ .position = 2 } }, diff[1]);
    try std.testing.expectEqualDeep(DiffItem(u8){ .Add = .{ .position = 3, .symbols = "b" } }, diff[2]);
    try std.testing.expectEqualDeep(DiffItem(u8){ .Del = .{ .position = 6 } }, diff[3]);
    try std.testing.expectEqualDeep(DiffItem(u8){ .Add = .{ .position = 7, .symbols = "c" } }, diff[4]);
}

test "No difference" {
    const original = "aaa";
    const diff = try Myers(u8, charEq).diff(std.testing.allocator, original, original);
    defer std.testing.allocator.free(diff);
    try std.testing.expectEqual(@as(usize, 0), diff.len);
}

test "Empty original" {
    const diff = try Myers(u8, charEq).diff(std.testing.allocator, "", "target");
    defer std.testing.allocator.free(diff);
    try std.testing.expectEqual(@as(usize, 1), diff.len);
    try std.testing.expectEqual(@as(usize, 0), diff[0].Add.position);
    try std.testing.expectEqualStrings("target", diff[0].Add.symbols);
    var result = std.ArrayList(u8).init(std.testing.allocator);
    var writer = result.writer();
    defer result.deinit();
    try applyDiff(u8, diff, "", writer);
    try std.testing.expectEqualStrings("target", result.items);
}

test "Empty target" {
    const diff = try Myers(u8, charEq).diff(std.testing.allocator, "original", "");
    defer std.testing.allocator.free(diff);
    try std.testing.expectEqual(@as(usize, 8), diff.len);
    for (0.."original".len) |i| {
        try std.testing.expectEqual(@as(usize, i + 1), diff[i].Del.position);
    }
    var result = std.ArrayList(u8).init(std.testing.allocator);
    var writer = result.writer();
    defer result.deinit();
    try applyDiff(u8, diff, "original", writer);
    try std.testing.expectEqualStrings("", result.items);
}

test "Empty target and original" {
    const diff = try Myers(u8, charEq).diff(std.testing.allocator, "", "");
    defer std.testing.allocator.free(diff);
    try std.testing.expectEqual(@as(usize, 0), diff.len);
}

/// Callers owns returned memory
fn bruteDiff(allocator: std.mem.Allocator, comptime T: type, original: []const T, target: []const T) !Diff(T) {
    var res = try allocator.alloc(DiffItem(T), original.len + 1);
    for (original, 0..) |_, i| {
        res[i] = DiffItem(T){ .Del = .{ .position = i + 1 } };
    }
    res[original.len] = DiffItem(T){ .Add = .{ .position = 0, .symbols = target } };
    return res;
}

fn printDiff(expectTest: *ExpectTest, diff: Diff(String), original: Lines) !void {
    for (diff) |d| {
        switch (d) {
            .Del => |i| try expectTest.printfmt("- {s}", .{original[i.position - 1]}),
            .Add => |a| {
                for (a.symbols) |s| {
                    try expectTest.printfmt("+ {s}", .{s});
                }
            },
        }
    }
}

fn applyDiff(comptime T: type, diff: Diff(T), original: []const T, writer: anytype) !void {
    var currentIndex: usize = 0;
    for (diff) |d| {
        switch (d) {
            .Add => |add| {
                _ = try writer.write(original[currentIndex..add.position]);
                _ = try writer.write(add.symbols);
                currentIndex = add.position;
            },
            .Del => |di| {
                _ = try writer.write(original[currentIndex .. di.position - 1]);
                currentIndex = di.position;
            },
        }
    }
    _ = try writer.write(original[currentIndex..original.len]);
}

inline fn charEq(a: u8, b: u8) bool {
    return a == b;
}

inline fn strEq(a: String, b: String) bool {
    return std.mem.eql(u8, a, b);
}
