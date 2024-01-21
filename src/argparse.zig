const std = @import("std");
const String = []const u8;

pub fn argParse(args: []const String, comptime Spec: type) ParseError!Spec {
    const info = @typeInfo(Spec);
    var result: Spec = undefined;
    inline for (info.Struct.fields) |f| {
        if (@hasDecl(f.type, "parse")) {
            try searchParsable(Spec, f, args, &result);
        } else if (@hasDecl(f.type, "set")) {
            try searchSettable(Spec, f, args, &result);
        }
    }
    return result;
}

fn searchParsable(comptime Spec: type, comptime f: std.builtin.Type.StructField, args: []const String, spec: *Spec) ParseError!void {
    var found = false;
    for (args) |a| {
        const prefix = std.fmt.comptimePrint("--{s}=", .{f.name});
        if (std.mem.startsWith(u8, a, prefix)) {
            if (found) return ParseError.DuplicatedArgument;
            @field(spec.*, f.name) = try f.type.parse(a[prefix.len..]);
            found = true;
        }
    }
    if (!found) return ParseError.MissingArgument;
}

fn searchSettable(comptime Spec: type, comptime f: std.builtin.Type.StructField, args: []const String, spec: *Spec) ParseError!void {
    var found = false;
    for (args) |a| {
        const flagSet = std.fmt.comptimePrint("--{s}", .{f.name});
        if (strEq(a, flagSet)) {
            if (found) return ParseError.DuplicatedArgument;
            @field(spec.*, f.name) = try f.type.set();
            found = true;
        }
    }
    if (!found) return ParseError.MissingArgument;
}

pub const ParseError = error{
    DuplicatedArgument,
    InvalidValue,
    MissingArgument,
};

pub const BoolArg = struct {
    value: bool,
    fn parse(s: String) ParseError!BoolArg {
        if (strEq(s, "true")) return .{ .value = true };
        if (strEq(s, "false")) return .{ .value = false };
        return ParseError.InvalidValue;
    }
};

pub const StringArg = struct {
    value: String,
    fn parse(s: String) ParseError!StringArg {
        return .{ .value = s };
    }
};

inline fn strEq(a: String, b: String) bool {
    return std.mem.eql(u8, a, b);
}

// Tests

test "argParse two options" {
    const TestArgs = struct {
        verbose: BoolArg,
        name: StringArg,
    };
    const args = &[_]String{
        "--verbose=true",
        "--name=test",
    };
    const parsed = try argParse(args, TestArgs);
    try std.testing.expectEqualDeep(TestArgs{ .verbose = .{ .value = true }, .name = .{ .value = "test" } }, parsed);
}

test "argParse flag" {
    const VerboseFlag = struct {
        value: bool,
        fn set() ParseError!@This() {
            return .{ .value = true };
        }
    };
    const TestArgs = struct {
        verbose: VerboseFlag,
    };
    const args = &[_]String{
        "--verbose",
    };
    const parsed = try argParse(args, TestArgs);
    try std.testing.expectEqualDeep(TestArgs{ .verbose = .{ .value = true } }, parsed);
}
