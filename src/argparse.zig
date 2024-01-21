const std = @import("std");
const String = []const u8;

/// Used as nullable return type to signal that the caller should comptime fail
/// Allow to implement tests for comptime checks behaviour
/// May be a more complex structure in future implementations ...
const ComptimeFailWithMessage = ?String;

pub fn argParse(args: []const String, comptime Spec: type) ParseError!Spec {
    comptime if (validateSpec(Spec)) |failWithMessage| {
        @compileError(failWithMessage);
    };
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

fn validateSpec(comptime Spec: type) ComptimeFailWithMessage {
    const info = @typeInfo(Spec);
    inline for (info.Struct.fields) |f| {
        if (@hasDecl(f.type, "default")) {
            if (validateDefaultFn(f)) |failWithMessage| return failWithMessage;
        }
        if (@hasDecl(f.type, "parse")) {
            if (validateParseFn(f)) |failWithMessage| return failWithMessage;
        } else if (@hasDecl(f.type, "set")) {
            if (validateSetFn(f)) |failWithMessage| return failWithMessage;
        } else {
            const failWithMessage = std.fmt.comptimePrint("Option '{s}':{any} does not implement set() or parse()", .{ f.name, f.type });
            return failWithMessage;
        }
    }
    return null;
}

fn validateParseFn(comptime f: std.builtin.Type.StructField) ComptimeFailWithMessage {
    const fnSpec = @typeInfo(@TypeOf(f.type.parse)).Fn;
    const fnParams = fnSpec.params;
    const expectedReturnType = ParseError!f.type;
    if (fnParams.len != 1 or fnParams[0].type.? != String or fnSpec.return_type.? != expectedReturnType) {
        comptime var fnParamTypes: [fnParams.len]type = undefined;
        inline for (fnParams, 0..) |p, i| {
            fnParamTypes[i] = p.type.?;
        }
        const msg = std.fmt.comptimePrint("Option '{s}':{any} does not implement parse({{ {any} }}){any}, found parse({any}){any}", .{ f.name, f.type, String, expectedReturnType, fnParamTypes, fnSpec.return_type });
        return msg;
    }
    return null;
}

fn validateSetFn(comptime f: std.builtin.Type.StructField) ComptimeFailWithMessage {
    const fnSpec = @typeInfo(@TypeOf(f.type.set)).Fn;
    const fnParams = fnSpec.params;
    if (fnParams.len != 0 or fnSpec.return_type.? != f.type) {
        comptime var fnParamTypes: [fnParams.len]type = undefined;
        inline for (fnParams, 0..) |p, i| {
            fnParamTypes[i] = p.type.?;
        }
        const msg = std.fmt.comptimePrint("Option '{s}':{any} does not implement set(){any}, found set({any}){any}", .{ f.name, f.type, f.type, fnParamTypes, fnSpec.return_type });
        return msg;
    }
    return null;
}

fn validateDefaultFn(comptime f: std.builtin.Type.StructField) ComptimeFailWithMessage {
    const fnSpec = @typeInfo(@TypeOf(f.type.default)).Fn;
    const fnParams = fnSpec.params;
    if (fnParams.len != 0 or fnSpec.return_type.? != f.type) {
        comptime var fnParamTypes: [fnParams.len]type = undefined;
        inline for (fnParams, 0..) |p, i| {
            fnParamTypes[i] = p.type.?;
        }
        const msg = std.fmt.comptimePrint("Option '{s}':{any} does not implement default(){any}, found default({any}){any}", .{ f.name, f.type, f.type, fnParamTypes, fnSpec.return_type });
        return msg;
    }
    return null;
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
    if (!found) {
        if (@hasDecl(f.type, "default")) {
            @field(spec.*, f.name) = f.type.default();
        } else {
            return ParseError.MissingArgument;
        }
    }
}

fn searchSettable(comptime Spec: type, comptime f: std.builtin.Type.StructField, args: []const String, spec: *Spec) ParseError!void {
    var found = false;
    for (args) |a| {
        const flagSet = std.fmt.comptimePrint("--{s}", .{f.name});
        if (strEq(a, flagSet)) {
            if (found) return ParseError.DuplicatedArgument;
            @field(spec.*, f.name) = f.type.set();
            found = true;
        }
    }
    if (!found) {
        if (@hasDecl(f.type, "default")) {
            comptime if (validateDefaultFn(f)) |failMessage| {
                @compileError(failMessage);
            };
            @field(spec.*, f.name) = f.type.default();
        } else {
            return ParseError.MissingArgument;
        }
    }
}

pub const ParseError = error{
    DuplicatedArgument,
    IntegerValueOutOfRange,
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

pub fn BoolArgWithDefault(comptime d: bool) type {
    return struct {
        value: bool,
        fn parse(s: String) ParseError!@This() {
            if (strEq(s, "true")) return .{ .value = true };
            if (strEq(s, "false")) return .{ .value = false };
            return ParseError.InvalidValue;
        }
        fn default() @This() {
            return .{ .value = d };
        }
    };
}

pub const BoolFlag = struct {
    value: bool,
    fn set() BoolFlag {
        return .{ .value = true };
    }

    fn default() BoolFlag {
        return .{ .value = false };
    }
};

pub const StringArg = struct {
    value: String,
    fn parse(s: String) ParseError!StringArg {
        return .{ .value = s };
    }
};

pub fn IntArg(comptime I: type) type {
    return struct {
        value: I,

        fn parse(s: String) ParseError!@This() {
            if (std.fmt.parseInt(I, s, 10)) |res| {
                return .{ .value = res };
            } else |err| switch (err) {
                error.Overflow => {
                    return ParseError.IntegerValueOutOfRange;
                },
                error.InvalidCharacter => {
                    return ParseError.InvalidValue;
                },
            }
        }
    };
}

inline fn strEq(a: String, b: String) bool {
    return std.mem.eql(u8, a, b);
}

// Tests

test "argParse: nominal" {
    const TestArgs = struct {
        verbose: BoolArg,
        name: StringArg,
        optimize: IntArg(u2),
    };
    const args = &[_]String{ "--verbose=true", "--name=test", "--optimize=3" };
    const parsed = try argParse(args, TestArgs);
    try std.testing.expectEqualDeep(TestArgs{ .verbose = .{ .value = true }, .name = .{ .value = "test" }, .optimize = .{ .value = 3 } }, parsed);
}

test "argParse: flag" {
    const VerboseFlag = struct {
        value: bool,
        fn set() @This() {
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

test "argParse: missing option" {
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

test "argParse: invalid option value" {
    const TestArgs = struct {
        b: BoolArg,
    };

    var args = &[_]String{
        "--b=not_a_boolean",
    };
    var parsed = argParse(args, TestArgs);
    try std.testing.expectError(ParseError.InvalidValue, parsed);
}

test "argParse: out of range integer value" {
    const TestArgs = struct {
        i: IntArg(u2),
    };

    var args = &[_]String{
        "--i=4",
    };
    var parsed = argParse(args, TestArgs);
    try std.testing.expectError(ParseError.IntegerValueOutOfRange, parsed);
}

test "validateSpec: missing set() or parse()" {
    const InvalidSpec = struct {
        invalidField: InvalidSpecOption,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.InvalidSpecOption does not implement set() or parse()", InvalidSpec);
}

test "validateSpec: parse() too many parameters" {
    const InvalidSpec = struct {
        invalidField: TooManyParseParameters,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.TooManyParseParameters does not implement parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.TooManyParseParameters, found parse({ []const u8, []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.TooManyParseParameters", InvalidSpec);
}

test "validateSpec: parse() missing parameter" {
    const InvalidSpec = struct {
        invalidField: MissingParseParameter,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.MissingParseParameter does not implement parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.MissingParseParameter, found parse({  })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.MissingParseParameter", InvalidSpec);
}

test "validateSpec: parse() wrong parameter type" {
    const InvalidSpec = struct {
        invalidField: WrongParseParameterType,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.WrongParseParameterType does not implement parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.WrongParseParameterType, found parse({ u32 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.WrongParseParameterType", InvalidSpec);
}

test "validateSpec: parse() wrong return type" {
    const InvalidSpec = struct {
        invalidField: WrongParseReturnType,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.WrongParseReturnType does not implement parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.WrongParseReturnType, found parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!u32", InvalidSpec);
}

test "validateSpec: parse() wrong error type" {
    const InvalidSpec = struct {
        invalidField: WrongParseErrorType,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.WrongParseErrorType does not implement parse({ []const u8 })error{DuplicatedArgument,IntegerValueOutOfRange,InvalidValue,MissingArgument}!argparse.WrongParseErrorType, found parse({ []const u8 })argparse.WrongParseErrorType", InvalidSpec);
}

test "validateSpec: set() too many parameters" {
    const InvalidSpec = struct {
        invalidField: TooManySetParameters,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.TooManySetParameters does not implement set()argparse.TooManySetParameters, found set({ u32 })argparse.TooManySetParameters", InvalidSpec);
}

test "validateSpec: set() wrong return type" {
    const InvalidSpec = struct {
        invalidField: WrongSetReturnType,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.WrongSetReturnType does not implement set()argparse.WrongSetReturnType, found set({  })u32", InvalidSpec);
}

test "validateSpec: default() too many parameters" {
    const InvalidSpec = struct {
        invalidField: TooManyDefaultParameters,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.TooManyDefaultParameters does not implement default()argparse.TooManyDefaultParameters, found default({ u32 })argparse.TooManyDefaultParameters", InvalidSpec);
}
test "validateSpec: default() wrong return type" {
    const InvalidSpec = struct {
        invalidField: WrongDefaultReturnType,
    };
    try expectFailWithMessage("Option 'invalidField':argparse.WrongDefaultReturnType does not implement default()argparse.WrongDefaultReturnType, found default({  })u32", InvalidSpec);
}

fn expectFailWithMessage(msg: String, comptime Spec: type) !void {
    const failMessage = validateSpec(Spec);
    try std.testing.expect(failMessage != null);
    try std.testing.expectEqualStrings(msg, failMessage.?);
}

// Declare failing structs outside of their respective tests to simplify error messages

const InvalidSpecOption = struct {
    value: void,
};

const TooManyParseParameters = struct {
    value: void,
    fn parse(s: String, oups: String) ParseError!TooManyParseParameters {
        _ = oups;
        _ = s;
        return .{ .value = {} };
    }
};

const TooManySetParameters = struct {
    value: void,
    fn set(oups: u32) TooManySetParameters {
        _ = oups;
        return .{ .value = {} };
    }
};

const TooManyDefaultParameters = struct {
    value: void,
    fn set() TooManyDefaultParameters {
        return .{ .value = {} };
    }
    fn default(oups: u32) TooManyDefaultParameters {
        _ = oups;
        return .{ .value = {} };
    }
};

const MissingParseParameter = struct {
    value: void,
    fn parse() ParseError!MissingParseParameter {
        return .{ .value = {} };
    }
};

const WrongParseParameterType = struct {
    value: void,
    fn parse(oups: u32) ParseError!WrongParseParameterType {
        _ = oups;
        return .{ .value = {} };
    }
};

const WrongParseReturnType = struct {
    value: void,
    fn parse(s: String) ParseError!u32 {
        _ = s;
        return 0;
    }
};

const WrongSetReturnType = struct {
    value: void,
    fn set() u32 {
        return 0;
    }
};

const WrongDefaultReturnType = struct {
    value: void,
    fn set() WrongDefaultReturnType {
        return .{{}};
    }
    fn default() u32 {
        return 0;
    }
};

const WrongParseErrorType = struct {
    value: void,
    fn parse(s: String) WrongParseErrorType {
        _ = s;
        return .{ .value = {} };
    }
};
