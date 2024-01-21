const std = @import("std");
const String = []const u8;

pub fn argParse(args: []const String, comptime Spec: type) ParseError!Spec {
    comptime validateSpec(Spec);
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

fn validateSpec(comptime Spec: type) void {
    const info = @typeInfo(Spec);
    inline for (info.Struct.fields) |f| {
        if (@hasDecl(f.type, "parse")) {
            validateParseFn(f);
        } else if (@hasDecl(f.type, "set")) {
            validateSetFn(f);
        } else {
            const msg = std.fmt.comptimePrint("Option {s} does not implement set() or parse()", .{f.name});
            @compileError(msg);
        }
    }
}

fn validateParseFn(comptime f: std.builtin.Type.StructField) void {
    const fnSpec = @typeInfo(@TypeOf(f.type.parse)).Fn;
    const fnParams = fnSpec.params;
    const expectedReturnType = ParseError!f.type;
    if (fnParams.len != 1 or fnParams[0].type.? != String or fnSpec.return_type.? != expectedReturnType) {
        var fnParamTypes: [fnParams.len]type = undefined;
        inline for (fnParams, 0..) |p, i| {
            fnParamTypes[i] = p.type.?;
        }
        const msg = std.fmt.comptimePrint("Option {s} does not implement parse({{ {any} }}){any}, found parse({any}){any}", .{ f.name, String, expectedReturnType, fnParamTypes, fnSpec.return_type });
        @compileError(msg);
    }
}

fn validateSetFn(comptime f: std.builtin.Type.StructField) void {
    const fnSpec = @typeInfo(@TypeOf(f.type.set)).Fn;
    const fnParams = fnSpec.params;
    const expectedReturnType = ParseError!f.type;
    if (fnParams.len != 0 or fnSpec.return_type.? != expectedReturnType) {
        var fnParamTypes: [fnParams.len]type = undefined;
        inline for (fnParams, 0..) |p, i| {
            fnParamTypes[i] = p.type.?;
        }
        const msg = std.fmt.comptimePrint("Option {s} does not implement set(){any}, found set({any}){any}", .{ f.name, expectedReturnType, fnParamTypes, fnSpec.return_type });
        @compileError(msg);
    }
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

test "argParse missing option" {
    const TestArgs = struct {
        a: StringArg,
        b: StringArg,
    };

    var args = &[_]String{
        "--a=AAA",
    };
    var parsed = argParse(args, TestArgs);
    try std.testing.expectError(ParseError.MissingArgument, parsed);

    args = &[_]String{
        "--b=BBB",
    };
    parsed = argParse(args, TestArgs);
    try std.testing.expectError(ParseError.MissingArgument, parsed);
}

test "argParse invalid option value" {
    const TestArgs = struct {
        b: BoolArg,
    };

    var args = &[_]String{
        "--b=not_a_boolean",
    };
    var parsed = argParse(args, TestArgs);
    try std.testing.expectError(ParseError.InvalidValue, parsed);
}
