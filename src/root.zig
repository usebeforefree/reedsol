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
    /// Shards have to be defined.
    data: []const []const u8,
    parity_count: usize,
    /// Length of each shard. This applies to both data and parity.
    shard_bytes: usize,
) !struct { []const []const u8, []const u8 } {
    // Assertions

    if (data.len == 0) return error.DataSizeIsZero;
    if (data.len < parity_count) return error.ParityCountTooHigh;
    if (shard_bytes == 0 or shard_bytes & 1 != 0) return error.InvalidShardBytes;
    if (parity_count == 0) return error.ParityCountIsZero;

    // Encoding

    // AVX512 instructions for 32/32/64 encoding
    if (has_gfni and data.len == 32 and parity_count == 32) {
        var parity_buf = try allocator.alloc(u8, parity_count * shard_bytes);
        errdefer allocator.free(parity_buf);

        var parity = try allocator.alloc([]u8, parity_count);
        errdefer allocator.free(parity);

        for (&parity, 0..) |*p, i| {
            const start = i * shard_bytes;
            const end = start + shard_bytes;
            p.* = parity_buf[start..end];
        }

        @import("engines/AVX512.zig").encode(data, parity, shard_bytes);

        return .{ parity, parity_buf };
    }

    // Generic instructions for data.len/parity_count/shard_bytes encoding
    const parity_count_next_pow2 = std.math.ceilPowerOfTwo(usize, parity_count) catch {
        if (parity_count == 0)
            return error.ParityCountIsZero
        else
            return error.ParityCountTooHigh;
    };
    const parity_buf_size = std.mem.alignForward(u64, data.len, parity_count_next_pow2);

    var parity_work_buf = try allocator.alloc(u8, parity_buf_size * shard_bytes);
    defer allocator.free(parity_work_buf);

    const parity_work = try allocator.alloc([]u8, parity_buf_size);
    defer allocator.free(parity_work);

    for (parity_work, 0..) |*p, i| {
        const start = i * shard_bytes;
        const end = start + shard_bytes;
        p.* = parity_work_buf[start..end];
    }

    Engine.encode(data, parity_work, parity_count, parity_count_next_pow2);

    var parity_buf = try allocator.alloc(u8, parity_count * shard_bytes);
    errdefer allocator.free(parity_buf);
    @memcpy(parity_buf, parity_work_buf[0..parity_buf.len]);

    const parity = try allocator.alloc([]u8, parity_count);
    errdefer allocator.free(parity);

    for (parity, 0..) |*p, i| {
        const start = i * shard_bytes;
        const end = start + shard_bytes;
        p.* = parity_buf[start..end];
    }

    return .{ parity, parity_buf };
}
