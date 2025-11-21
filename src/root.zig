const std = @import("std");
const builtin = @import("builtin");

const has_gfni = builtin.target.cpu.has(.x86, .gfni) and builtin.zig_backend == .stage2_llvm;
pub const Engine = switch (builtin.target.cpu.arch) {
    else => @import("engines/Generic.zig"),
};

pub fn encode(
    /// The input data shards. It's required by the caller to keep the memory
    /// alive during the encoding process, since we don't gain ownership of it.
    /// Shards have to be defined.
    data: []const []const u8,
    /// The output parity shards. Again, the caller owns the destination pointers,
    /// and is required to make sure they are valid while we write into them.
    /// Shards can be undefined.
    parity: []const []u8,
    parity_count: usize,
    /// Length of each shard. This applies to both data and parity.
    shard_bytes: usize,
) !void {
    if (data.len == 0) return error.DataSizeIsZero;
    if (parity.len == 0) return error.ParitySizeIsZero;
    if (data.len < parity_count) return error.ParityCountTooHigh;
    if (shard_bytes == 0 or shard_bytes & 1 != 0) return error.InvalidShardBytes;
    if (data[0].len != parity[0].len) return error.DataAndParityShardBytesDiffer;

    const parity_count_next_pow2 = try std.math.ceilPowerOfTwo(usize, parity_count);
    const parity_buff_size = std.mem.alignForward(u64, data.len, parity_count_next_pow2);
    if (parity.len < parity_buff_size) return error.ParityBufferSizeTooSmall;

    if (has_gfni and data.len == 32 and parity.len == 32) {
        return @import("engines/AVX512.zig").encode(data, parity, shard_bytes);
    }

    return Engine.encode(data, parity, parity_count_next_pow2);
}
