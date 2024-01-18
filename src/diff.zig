const std = @import("std");

const DiffTag = enum(u2) {
    Add,
    Del,
};

fn DiffItem(comptime T: type) type {
    return union(DiffTag) {
        Add: struct {
            index: usize,
            symbols: []const T,
        },
        Del: struct { index: usize },
    };
}

fn Diff(comptime T: type) type {
    return []const DiffItem(T);
}

// Tests
const String = []const u8;
const Lines = []const String;
const ExpectTest = @import("zunit.zig").ExpectTest;

/// Callers owns returned memory
fn bruteDiff(allocator: std.mem.Allocator, comptime T: type, original: []const T, target: []const T) !Diff(T) {
    var res = try allocator.alloc(DiffItem(T), original.len + 1);
    for (original, 0..) |_, i| {
        res[i] = DiffItem(T){ .Del = .{ .index = i } };
    }
    res[original.len] = DiffItem(T){ .Add = .{ .index = 0, .symbols = target } };
    return res;
}

fn printDiff(expectTest: *ExpectTest, diff: Diff(String), original: Lines) !void {
    for (diff) |d| {
        switch (d) {
            .Del => |i| try expectTest.printfmt("- {s}", .{original[i.index]}),
            .Add => |a| {
                for (a.symbols) |s| {
                    try expectTest.printfmt("+ {s}", .{s});
                }
            },
        }
    }
}

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
    var expectTest = ExpectTest.init(std.testing.allocator);
    defer expectTest.deinit();

    try printDiff(&expectTest, diff, &original);

    try expectTest.expect(
        \\- Je vis cette faucheuse,
        \\- Elle était dans son champ,
        \\+ Elle allait à grands pas moissonnant et fauchant,
        \\+ Noir squelette laissant passer le crépuscule,
    );
}

test "Sample diff from Myers paper" {
    var result = std.ArrayList(u8).init(std.testing.allocator);
    defer result.deinit();
    var writer = result.writer();

    const original = "abcabba";
    const expected = "cbabac";
    const diff = [_]DiffItem(u8){
        DiffItem(u8){ .Del = .{ .index = 0 } },
        DiffItem(u8){ .Del = .{ .index = 1 } },
        DiffItem(u8){ .Add = .{ .index = 2, .symbols = &[_]u8{'b'} } },
        DiffItem(u8){ .Del = .{ .index = 5 } },
        DiffItem(u8){ .Add = .{ .index = 6, .symbols = &[_]u8{'c'} } },
    };
    try applyDiff(u8, &diff, original, writer);
    try std.testing.expectEqualStrings(expected, result.items);
}

test "Multiple inserts at once" {
    var result = std.ArrayList(u8).init(std.testing.allocator);
    defer result.deinit();
    var writer = result.writer();

    const original = "xxAAA";
    const expected = "AAA";
    const diff = [_]DiffItem(u8){
        DiffItem(u8){ .Del = .{ .index = 0 } },
        DiffItem(u8){ .Del = .{ .index = 1 } },
        DiffItem(u8){ .Add = .{ .index = 1, .symbols = expected } },
    };
    try applyDiff(u8, &diff, original, writer);
    try std.testing.expectEqualStrings(expected, result.items);
}

fn applyDiff(comptime T: type, diff: Diff(T), original: []const T, writer: anytype) !void {
    var currentIndex: usize = 0;
    for (diff) |d| {
        switch (d) {
            .Add => |add| {
                _ = try writer.write(original[currentIndex .. add.index + 1]);
                _ = try writer.write(add.symbols);
                currentIndex = add.index + 1;
            },
            .Del => |di| {
                _ = try writer.write(original[currentIndex..di.index]);
                currentIndex = di.index + 1;
            },
        }
    }
}
