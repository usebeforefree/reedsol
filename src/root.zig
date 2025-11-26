const std = @import("std");
const builtin = @import("builtin");

const gf = @import("gf.zig");

const has_gfni = builtin.target.cpu.has(.x86, .gfni) and builtin.zig_backend == .stage2_llvm;
pub const Engine = switch (builtin.target.cpu.arch) {
    else => @import("engines/Generic.zig"),
};

pub fn encode(
    allocator: std.mem.Allocator,
    /// The input data shards. It's required by the caller to keep the memory
    /// alive during the encoding process, since we don't gain ownership of it.
    /// Shards have to be defined and of `shard_bytes` length. `data.len` must
    /// be bigger than 0.
    data: []const []const u8,
    /// The output parity shards. It's required by the caller to keep the memory
    /// alive during the encoding process, since we don't gain ownership of it.
    /// `parity.len` is the number of parity shards, which must be smaller than
    /// `data.len`, and bigger than 0. Shards must be of `shard_bytes` length.
    parity: []const []u8,
    /// Length of each shard. This applies to both data and parity.
    /// Must be divisible by 64.
    shard_bytes: usize,
) !void {
    // Assertions

    if (data.len == 0) return error.DataShardCountIsZero;
    if (parity.len == 0) return error.ParityShardCountIsZero;
    if (data.len < parity.len) return error.ParityShardCountTooHigh;
    if (shard_bytes == 0) return error.InvalidShardBytes;
    if (shard_bytes % 64 != 0) return error.ShardBytesNotDivisableBy64;
    for (data) |d| {
        if (d.len != shard_bytes) return error.DataShardBytesMismatch;
    }
    for (parity) |p| {
        if (p.len != shard_bytes) return error.ParityShardBytesMismatch;
    }

    // Encoding

    // AVX512 instructions for 32/32/64 encoding
    if (has_gfni and data.len == 32 and parity.len == 32) {
        return @import("engines/AVX512.zig").encode(data, parity, shard_bytes);
    }

    // Generic instructions for data.len/parity_count/shard_bytes encoding

    const parity_count_next_pow2 = std.math.ceilPowerOfTwo(usize, parity.len) catch {
        if (parity.len == 0)
            return error.ParityShardCountIsZero
        else
            return error.ParityShardCountTooHigh;
    };
    const work_buf_size = std.mem.alignForward(u64, data.len, parity_count_next_pow2);

    if (parity.len == work_buf_size)
        // No need for allocating a work buffer
        return Engine.encode(data, parity, parity.len, parity_count_next_pow2)
    else {
        // Alloc a work buffer

        var work_buf = try allocator.alloc(u8, work_buf_size * shard_bytes);
        defer allocator.free(work_buf);

        const work = try allocator.alloc([]u8, work_buf_size);
        defer allocator.free(work);

        for (work, 0..) |*p, i| {
            const start = i * shard_bytes;
            p.* = work_buf[start..][0..shard_bytes];
        }

        Engine.encode(data, work, parity.len, parity_count_next_pow2);

        for (parity, 0..) |*p, i| {
            const start = i * shard_bytes;
            @memcpy(p.*, work_buf[start..][0..shard_bytes]);
        }

        return;
    }
}

pub fn decode(
    allocator: std.mem.Allocator,
    /// The input data shards. It's required by the caller to keep the memory
    /// alive during the encoding process, since we don't gain ownership of it.
    /// Shards must be of `shard_bytes` length. `data.len` must be bigger than 0.
    data: []const []u8,
    /// `true` for present data shards. Must be of `data.len` length.
    data_present: []const bool,
    /// The output parity shards. It's required by the caller to keep the memory
    /// alive during the encoding process, since we don't gain ownership of it.
    /// `parity.len` is the number of parity shards, which must be smaller than
    /// `data.len`, and bigger than 0. Shards must be of `shard_bytes` length.
    parity: []const ?[]const u8,
    /// Length of each shard. This applies to both data and parity.
    /// Must be divisible by 64.
    shard_bytes: usize,
) !void {
    // Assertions

    if (data.len == 0) return error.DataShardCountIsZero;
    if (parity.len == 0) return error.ParityShardCountIsZero;
    if (data.len < parity.len) return error.ParityShardCountTooHigh;
    if (shard_bytes == 0) return error.InvalidShardBytes;
    if (shard_bytes % 64 != 0) return error.ShardBytesNotDivisableBy64;
    if (data.len != data_present.len) return error.DataAndDataPresentMismatch;

    const data_present_count = blk: {
        var i: usize = 0;
        for (data, 0..) |data_shard, j| {
            if (data_present[j]) {
                if (data_shard.len != shard_bytes) return error.DataShardBytesMismatch;
                i += 1;
            }
        }
        break :blk i;
    };

    const parity_present_count = blk: {
        var i: usize = 0;
        for (parity) |parity_shard| {
            if (parity_shard) |d| {
                if (d.len != shard_bytes) return error.ParityShardBytesMismatch;
                i += 1;
            }
        }
        break :blk i;
    };

    if (data_present_count + parity_present_count < data.len)
        return error.NotEnoughShards;

    // All data is already present
    if (data_present_count == data.len) return;

    // Decoding

    // AVX512 instructions for 32/32/64 encoding
    if (has_gfni and data.len == 32 and parity.len == 32) {
        @panic("TODO");
    }

    // Generic instructions for data.len/parity_count/shard_bytes encoding

    const parity_count_next_pow2 = std.math.ceilPowerOfTwo(usize, parity.len) catch {
        if (parity.len == 0)
            return error.ParityShardCountIsZero
        else
            return error.ParityShardCountTooHigh;
    };
    const work_buf_size = try std.math.ceilPowerOfTwo(usize, parity_count_next_pow2 + data.len);

    // Alloc a work buffer

    var work_buf = try allocator.alloc(u8, work_buf_size * shard_bytes);
    defer allocator.free(work_buf);
    @memset(work_buf, 0);

    const work = try allocator.alloc([]u8, work_buf_size);
    defer allocator.free(work);

    const erasures = try allocator.alloc(u16, gf.order);
    defer allocator.free(erasures);
    @memset(erasures, 0);

    // TODO check size here
    const shards_present = try allocator.alloc(bool, work_buf_size);
    defer allocator.free(shards_present);
    @memset(shards_present, false);

    for (work, 0..) |*p, i| {
        const start = i * shard_bytes;
        p.* = work_buf[start..][0..shard_bytes];
    }

    // load data into work buf

    for (0..data.len) |i| {
        if (data_present[i]) {
            @memcpy(work[parity_count_next_pow2 + i], data[i]);
            shards_present[parity_count_next_pow2 + i] = true;
        }
    }

    for (0..parity.len) |i| {
        if (parity[i]) |d| {
            @memcpy(work[i], d);
            shards_present[i] = true;
        }
    }

    Engine.decode(work, data.len, shards_present, parity, erasures, parity_count_next_pow2);

    for (0..data.len) |i| {
        if (!data_present[i])
            @memcpy(data[i], work[parity_count_next_pow2 + i]);
    }
}
