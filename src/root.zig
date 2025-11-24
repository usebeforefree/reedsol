const std = @import("std");
const builtin = @import("builtin");

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
    if (data[0].len != shard_bytes) return error.DataShardBytesMismatch;
    if (parity[0].len != shard_bytes) return error.ParityShardBytesMismatch;

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
    const parity_buf_size = std.mem.alignForward(u64, data.len, parity_count_next_pow2);

    if (parity.len == parity_buf_size)
        // No need for allocating a work buffer
        return Engine.encode(data, parity, parity.len, parity_count_next_pow2)
    else {
        // Alloc a work buffer

        var parity_work_buf = try allocator.alloc(u8, parity_buf_size * shard_bytes);
        defer allocator.free(parity_work_buf);

        const parity_work = try allocator.alloc([]u8, parity_buf_size);
        defer allocator.free(parity_work);

        for (parity_work, 0..) |*p, i| {
            const start = i * shard_bytes;
            p.* = parity_work_buf[start..][0..shard_bytes];
        }

        Engine.encode(data, parity_work, parity.len, parity_count_next_pow2);

        for (parity, 0..) |*p, i| {
            const start = i * shard_bytes;
            @memcpy(p.*, parity_work_buf[start..][0..shard_bytes]);
        }

        return;
    }
}
