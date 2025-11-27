/// Benchmarks based off of:
/// https://github.com/AndersTrier/reed-solomon-simd/blob/df1b4fee7f28e2ea9b02e05169b7b93150fdf932/benches/benchmarks.rs
const std = @import("std");
const reedsol = @import("reedsol");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    try roundtrip(allocator);
}

const ITERATIONS = 10_000;

fn roundtrip(gpa: std.mem.Allocator) !void {
    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var progress = std.Progress.start(.{});

    inline for ([_]struct { usize, usize, usize }{
        .{ 32, 32, 1024 },
        .{ 64, 64, 1024 },
    }) |entry| {
        const data_shard_count, const parity_shard_count, const shard_bytes = entry;

        const input = try arena.alloc(u8, shard_bytes * data_shard_count);
        defer arena.free(input);
        std.crypto.random.bytes(input);

        const original_buf: *[data_shard_count][shard_bytes]u8 = @ptrCast(input);
        var original: [data_shard_count][]const u8 = undefined;
        for (&original, original_buf) |*o, *shard| o.* = shard;

        var parity_buf: [parity_shard_count][shard_bytes]u8 = undefined;
        var parity: [parity_shard_count][]u8 = undefined;
        for (&parity, &parity_buf) |*p, *shard| p.* = shard;

        {
            var name_buffer: [100]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buffer, "encode:{d}/{d}/{d}", .{ data_shard_count, parity_shard_count, shard_bytes });
            const node = progress.start(name, ITERATIONS);
            defer node.end();

            var total_ns: u64 = 0;

            for (0..ITERATIONS) |i| {
                defer node.completeOne();
                std.mem.doNotOptimizeAway(i);

                var start = try std.time.Timer.start();
                std.mem.doNotOptimizeAway(try reedsol.encode(
                    &original,
                    &parity,
                    shard_bytes,
                ));
                total_ns += start.read();
            }

            const average = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(ITERATIONS));
            try stdout.print("{s} - average of {d}us per encode\n", .{ name, @floor(average) / std.time.ns_per_us });
            try stdout.flush();
        }
    }
}
