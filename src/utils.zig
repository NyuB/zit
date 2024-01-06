const std = @import("std");

pub inline fn powerOfTwo(n: usize) usize {
    return std.math.shl(usize, 1, n);
}
