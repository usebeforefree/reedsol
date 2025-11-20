const std = @import("std");
const testing = std.testing;

const reedsol = @import("reedsol");
const encode = reedsol.encode;

test "encode 8 data 8 parity 64 bytes" {
    try encodeTest(8, 8, 64, @import("./encode_data_8_8_64.zon"));
}

test "encode 16 data 16 parity 64 bytes" {
    try encodeTest(16, 16, 64, @import("./encode_data_16_16_64.zon"));
}

test "encode 32 data 32 parity 64 bytes" {
    try encodeTest(32, 32, 64, @import("./encode_data_32_32_64.zon"));
}

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

    var parity_shards: [parity_shard_count][shard_bytes]u8 = undefined;
    var parity: [parity_shard_count][]u8 = undefined;
    for (&parity, &parity_shards) |*p, *shard| p.* = shard;

    try encode(
        &original,
        &parity,
        shard_bytes,
    );

    for (expected, parity) |e_sh, r_sh| for (e_sh, r_sh) |e, r| try testing.expectEqual(e, r);
}
