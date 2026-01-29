const std = @import("std");
const reedsol = @import("reedsol");

// Number of shards being encoded
const DATA_SHARD_COUNT = 4;
// Maximum amount of shards we can lose
const PARITY_SHARD_COUNT = 2;
// Shard size
const SHARD_BYTES = 64;

pub fn main() !void {
    var da_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da_state.deinit();
    const allocator = da_state.allocator();

    // Starting data
    var input: [DATA_SHARD_COUNT * SHARD_BYTES]u8 = .{
        // Shard 1
        4, 8, 1, 2, 4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0,
        4, 8, 1, 2, 4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0,
        1, 0, 7, 3, 4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0,
        1, 0, 7, 3, 1, 3, 1, 5, 4, 8, 1, 2, 4, 8, 1, 2,
        // Shard 2
        1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3, 4, 8, 1, 2,
        1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 4, 8, 1, 2, 4,
        8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3, 4,
        8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3, 1,
        // Shard 3
        3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3, 4, 8, 1, 2, 1,
        3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3, 3, 1, 3, 1, 5,
        7, 4, 9, 0, 1, 0, 7, 3, 4, 8, 1, 2, 1, 3, 1, 5,
        7, 4, 9, 0, 1, 0, 7, 3, 7, 4, 9, 0, 1, 0, 7, 3,
        // Shard 4
        4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3,
        1, 0, 7, 3, 4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0,
        1, 0, 7, 3, 1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3,
        4, 8, 1, 2, 1, 3, 1, 5, 7, 4, 9, 0, 1, 0, 7, 3,
    };
    for (0..input.len) |i| input[i] = @intCast(i % 256);

    const original_buf: [DATA_SHARD_COUNT][SHARD_BYTES]u8 = @bitCast(input);
    var original: [DATA_SHARD_COUNT][]const u8 = undefined;
    for (&original, &original_buf) |*o, *shard| o.* = shard;

    // Memory reserved for parity shards
    var parity_buf: [PARITY_SHARD_COUNT][SHARD_BYTES]u8 = undefined;
    var parity: [PARITY_SHARD_COUNT][]u8 = undefined;
    for (&parity, &parity_buf) |*p, *shard| p.* = shard;

    try reedsol.encode(
        allocator,
        &original,
        &parity,
        SHARD_BYTES,
    );

    // Create an array of lost data
    var data_present: [DATA_SHARD_COUNT]bool = .{ true, true, true, false };

    // Create an array of lost parity
    const parity_present: [PARITY_SHARD_COUNT]bool = .{ true, false };

    // Copy the starting data
    var recovered_buf: [DATA_SHARD_COUNT][SHARD_BYTES]u8 = @bitCast(input);

    // Explicitly set lost data to 0
    var recovered: [DATA_SHARD_COUNT][]u8 = undefined;
    for (&recovered, &recovered_buf, 0..) |*o, *shard, i| {
        o.* = shard;
        // Set whole shard to 0
        if (!data_present[i]) @memset(o.*, 0);
    }

    // Explicitly set lost parity to null
    var parity_opt: [PARITY_SHARD_COUNT]?[]u8 = undefined;
    for (&parity_opt, &parity_buf, 0..) |*p, *shard, i| {
        // Set whole shard to 0
        p.* = if (parity_present[i]) shard else null;
    }

    // Start data:
    // [ Shard 1,
    //   Shard 2,
    //   Shard 3,
    //   0000000, ] <- Shard 4 is missing
    //
    // Parity data:
    // [ Shard 1,
    //   null, ] <- Shard 2 is missing

    try reedsol.decode(
        allocator,
        &recovered,
        &data_present,
        &parity_opt,
        SHARD_BYTES,
    );

    // Assert the recovered data is equal to start data
    for (original, recovered) |o_sh, r_sh| for (o_sh, r_sh) |e, r| try std.testing.expectEqual(e, r);
}
