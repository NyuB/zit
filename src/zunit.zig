const std = @import("std");
const String = []const u8;
const Lines = []const String;

pub const ExpectTest = struct {
    lines: std.ArrayListUnmanaged(String),
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) ExpectTest {
        var arena = std.heap.ArenaAllocator.init(allocator);
        return ExpectTest{ .lines = std.ArrayListUnmanaged(String){}, .arena = arena };
    }

    pub fn deinit(self: *ExpectTest) void {
        defer self.arena.deinit();
        std.testing.expectEqual(@as(usize, 0), self.lines.items.len) catch unreachable;
    }

    pub fn println(self: *ExpectTest, l: String) !void {
        try self.lines.append(self.arena.allocator(), l);
    }

    pub fn printfmt(self: *ExpectTest, comptime format: String, args: anytype) !void {
        var line = std.ArrayList(u8).init(self.arena.allocator());
        var lineWriter = line.writer();
        try std.fmt.format(lineWriter, format, args);
        try self.lines.append(self.arena.allocator(), line.items);
    }

    pub fn expect(self: *ExpectTest, s: String) !void {
        var expectCursor: usize = 0;
        var it = std.mem.splitSequence(u8, s, "\n");
        while (it.next()) |line| {
            if (expectCursor >= self.lines.items.len) {
                std.debug.print("Missing line at index {d}\n=>\n{s}\n<=\n", .{ expectCursor, line });
                return error.UnexpectedLine;
            } else {
                try std.testing.expectEqualStrings(line, self.lines.items[expectCursor]);
                expectCursor += 1;
            }
        }
        try std.testing.expectEqual(self.lines.items.len, expectCursor);
        self.lines.clearAndFree(self.arena.allocator());
    }
};

test "Expect test" {
    var expectTest = ExpectTest.init(std.testing.allocator);
    defer expectTest.deinit();

    try expectTest.println("AAA");
    try expectTest.println("BBB");
    try expectTest.println("CCC");

    try expectTest.expect(
        \\AAA
        \\BBB
        \\CCC
    );

    try expectTest.println("DDD");
    try expectTest.expect("DDD");
}
