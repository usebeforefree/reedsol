const std = @import("std");
const testing = std.testing;

const reedsol = @import("reedsol");
const encode = reedsol.encode;
const decode = reedsol.decode;

test "encode 8 data 8 parity 64 bytes" {
    try encodeTest(8, 8, 64, @import("./encode_data_8_8_64.zon"));
}

test "encode 16 data 8 parity 128 bytes" {
    try encodeTest(16, 8, 128, @import("./encode_data_16_8_128.zon"));
}

test "encode 16 data 16 parity 64 bytes" {
    try encodeTest(16, 16, 64, @import("./encode_data_16_16_64.zon"));
}

test "encode 32 data 32 parity 64 bytes" {
    try encodeTest(32, 32, 64, @import("./encode_data_32_32_64.zon"));
}

test "encode 8 data 4 parity 64 bytes" {
    try encodeTest(8, 4, 64, @import("./encode_data_8_4_64.zon"));
}

test "encode 32 data 16 parity 64 bytes" {
    try encodeTest(32, 16, 64, @import("./encode_data_32_16_64.zon"));
}

test "encode 32 data 15 parity 64 bytes" {
    try encodeTest(32, 15, 64, @import("./encode_data_32_15_64.zon"));
}

test "encode 33 data 16 parity 64 bytes" {
    try encodeTest(33, 16, 64, @import("./encode_data_33_16_64.zon"));
}

// test "encode 101 data 13 parity 64 bytes" {
//     try encodeTest(101, 13, 64, @import("./encode_data_101_13_64.zon"));
// }

// test "encode and decode 5 data and 5 parity 64 bytes with all combinations" {
//     const data_shard_count = 5;
//     const parity_shard_count = 5;
//     const SHARD_BYTES = 64;
//
//     var input: [SHARD_BYTES * data_shard_count]u8 = undefined;
//     for (0..input.len) |i| input[i] = @intCast(i % 256);
//
//     var original_shards_present: [data_shard_count]bool = undefined;
//     var recovery_shards_present: [parity_shard_count]bool = undefined;
//
//     const total_combinations = 1 << (data_shard_count * 2);
//
//     for (0..total_combinations) |mask| {
//         original_shards_present = @splat(true);
//         recovery_shards_present = @splat(true);
//
//         for (0..data_shard_count * 2) |i| {
//             if ((mask & (@as(usize, 1) << @as(u6, @intCast(i)))) != 0) {
//                 if (i < data_shard_count) {
//                     original_shards_present[i] = false;
//                 } else {
//                     recovery_shards_present[i - data_shard_count] = false;
//                 }
//             }
//         }
//
//         const result = roundtrip(
//             data_shard_count,
//             parity_shard_count,
//             SHARD_BYTES,
//             original_shards_present,
//             recovery_shards_present,
//         );
//
//         if (@popCount(mask) <= data_shard_count)
//             try result
//         else
//             try testing.expectError(error.NotEnoughShards, result);
//     }
// }

fn encodeTest(
    comptime data_shard_count: usize,
    comptime parity_shard_count: usize,
    comptime shard_bytes: usize,
    comptime expected: [parity_shard_count][shard_bytes]u8,
) !void {
    var input: [shard_bytes * data_shard_count]u8 = undefined;
    for (0..input.len) |i| input[i] = @intCast(i % 256);

    const shards: [data_shard_count][shard_bytes]u8 = @bitCast(input);

    var original: [data_shard_count][]const u8 = undefined;
    for (&original, &shards) |*o, *shard| o.* = shard;

    var parity_buf: [parity_shard_count][shard_bytes]u8 = undefined;
    var parity: [parity_shard_count][]u8 = undefined;
    for (&parity, &parity_buf) |*p, *shard| p.* = shard;

    try encode(
        &original,
        &parity,
        shard_bytes,
    );

    for (expected, parity) |e_sh, r_sh| for (e_sh, r_sh) |e, r| try testing.expectEqual(e, r);
}

fn roundtrip(
    comptime data_shard_count: usize,
    comptime parity_shard_count: usize,
    comptime shard_bytes: usize,
    data_present: [data_shard_count]bool,
    parity_present: [parity_shard_count]bool,
) !void {
    var input: [shard_bytes * data_shard_count]u8 = undefined;
    for (0..input.len) |i| input[i] = @intCast(i % 256);

    const original_buf: [data_shard_count][shard_bytes]u8 = @bitCast(input);
    var original: [data_shard_count][]const u8 = undefined;
    for (&original, &original_buf) |*o, *shard| o.* = shard;

    var parity_buf: [parity_shard_count][shard_bytes]u8 = undefined;
    var parity: [parity_shard_count][]u8 = undefined;
    for (&parity, &parity_buf) |*p, *shard| p.* = shard;

    try encode(
        testing.allocator,
        &original,
        &parity,
        shard_bytes,
    );

    var recovered_buf: [data_shard_count][shard_bytes]u8 = @bitCast(input);

    var recovered: [data_shard_count][]u8 = undefined;
    for (&recovered, &recovered_buf, 0..) |*o, *shard, i| {
        o.* = shard;
        if (!data_present[i]) @memset(o.*, 0);
    }

    var parity_opt: [parity_shard_count]?[]u8 = undefined;
    for (&parity_opt, &parity_buf, 0..) |*p, *shard, i| {
        p.* = if (parity_present[i]) shard else null;
    }

    try decode(
        testing.allocator,
        &recovered,
        &data_present,
        &parity_opt,
        shard_bytes,
    );

    for (original, recovered) |o_sh, r_sh| for (o_sh, r_sh) |e, r| try testing.expectEqual(e, r);
}
