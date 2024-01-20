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
    }

    pub fn end(self: ExpectTest) !void {
        try std.testing.expectEqual(@as(usize, 0), self.lines.items.len);
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
        var match = true;
        while (it.next()) |line| {
            if (expectCursor >= self.lines.items.len) {
                std.debug.print("Missing line at index {d}\n=>\n{s}\n<=\n", .{ expectCursor, line });
                match = false;
                break;
            } else {
                if (std.mem.eql(u8, line, self.lines.items[expectCursor])) {
                    expectCursor += 1;
                } else {
                    match = false;
                    break;
                }
            }
        }
        if (!match or expectCursor < self.lines.items.len) {
            std.debug.print("Expect error, expected===>\n{s}\n<===\nactual ===>\n", .{s});
            for (self.lines.items) |l| {
                std.debug.print("{s}\n", .{l});
            }
            std.debug.print("<===\n", .{});
            return error.UnexpectedLine;
        }
        self.lines.clearAndFree(self.arena.allocator());
    }

    pub fn stringWriter(self: *ExpectTest) StringWriter {
        return StringWriter{ .et = self };
    }

    pub const StringWriter = struct {
        et: *ExpectTest,
        pub fn write(self: *const StringWriter, s: []const String) !void {
            for (s) |l| {
                try self.et.println(l);
            }
        }
    };
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
