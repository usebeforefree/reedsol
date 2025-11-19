const std = @import("std");
const gf = @import("gf.zig");

/// multiplies x by an element who's log is log_m in GF, mod 2^16 - 1
pub fn mul16(x: u16, log_m: u16, exp: *const [gf.order]u16, log: *const [gf.order]u16) u16 {
    if (x == 0) return 0;
    return exp[addMod(log[x], log_m)];
}

pub fn addMod(x: u32, y: u32) u16 {
    const sum = x + y;
    return @truncate(sum + (sum >> 16));
}

pub fn subMod(x: u32, y: u32) u16 {
    const dif = x + gf.modulus - y;
    return @truncate(dif + (dif >> 16));
}

pub fn xor(a: []const []u8, b: []const []u8) void {
    std.debug.assert(a.len == b.len);
    std.debug.assert(a.len >= 0);
    std.debug.assert(a[0].len == 64);
    std.debug.assert(b[0].len == 64);
    for (a, b) |ac, bc| {
        const c: @Vector(64, u8) = ac[0..64].*;
        const d: @Vector(64, u8) = bc[0..64].*;
        ac[0..64].* = c ^ d;
    }
}
