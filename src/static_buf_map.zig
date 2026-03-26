//The MIT License (MIT)
//Copyright © 2026 <Jonathan Keyuk>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");

/// Allocator-free Hash Map with a fixed capacity.
/// CAPACITY must be a power of 2
pub fn StaticBufferMap(comptime V: type, comptime CAPACITY: usize) type {
    comptime {
        if (CAPACITY == 0 or (CAPACITY & (CAPACITY - 1)) != 0)
            @compileError("CAPACITY must be a power of 2");
    }

    return struct {
        const Self = @This();
        const MASK = CAPACITY - 1;
        const MAX_PROBE = 8; // UI performance sweet spot

        const Entry = struct {
            hash: u64 = 0,
            value: V = undefined,
        };

        entries: [CAPACITY]Entry = [_]Entry{.{}} ** CAPACITY,

        /// Retrieves a value by its key. Returns `null` if the key is not found.
        pub fn get(self: *const Self, key: u64) ?V {
            // Ensure key is never 0 (sentinel for empty)
            const h = if (key == 0) 1 else key;
            const start_slot = h & MASK;

            var i: usize = 0;
            while (i < MAX_PROBE) : (i += 1) {
                const slot = (start_slot + i) & MASK;
                const entry = self.entries[slot];

                if (entry.hash == h) return entry.value;
                if (entry.hash == 0) return null; // Hit an empty slot, stop searching
            }
            return null;
        }

        /// Inserts a value or updates an existing key.
        /// Returns `error.NoSpace` if the map is full.
        pub fn put(self: *Self, key: u64, value: V) !void {
            const h = if (key == 0) 1 else key;
            const start_slot = h & MASK;

            var i: usize = 0;
            while (i < MAX_PROBE) : (i += 1) {
                const slot = (start_slot + i) & MASK;

                // Overwrite if same key OR slot is empty
                if (self.entries[slot].hash == h or self.entries[slot].hash == 0) {
                    self.entries[slot] = .{ .hash = h, .value = value };
                    return;
                }
            }
            // Map is too crowded at this hash location
            return error.NoSpace;
        }

        /// Wipes the map clean, making it empty.
        pub fn clear(self: *Self) void {
            // Only zeroing the hashes is enough to "reset" the map
            for (&self.entries) |*entry| {
                entry.hash = 0;
            }
        }

        /// Removes a key from the map
        pub fn remove(self: *Self, key: u64) void {
            const h = if (key == 0) 1 else key;
            const start_slot = h & MASK;

            var i: usize = 0;
            while (i < MAX_PROBE) : (i += 1) {
                const slot = (start_slot + i) & MASK;
                if (self.entries[slot].hash == h) {
                    self.entries[slot].hash = 0;
                    return;
                }
                if (self.entries[slot].hash == 0) return;
            }
        }
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn hash(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key);
}

test "StaticBufferMap: basic put and get" {
    var map = StaticBufferMap(i32, 8){};

    const key1 = hash("apple");
    const key2 = hash("bannana");

    try map.put(key1, 100);
    try map.put(key2, 200);

    try expectEqual(100, map.get(key1));
    try expectEqual(200, map.get(key2));
    try expectEqual(null, map.get(hash("cherry")));
}

test "StaticBufferMap: overwrite existing key" {
    var map = StaticBufferMap(i32, 8){};

    try map.put(hash("test"), 1);
    try map.put(hash("test"), 2); // Should update

    try expectEqual(2, map.get(hash("test")));
}

test "StaticBufferMap: clear/wipe the map" {
    var map = StaticBufferMap(i32, 8){};

    try map.put(hash("data"), 500);
    map.clear(); // Resets the bitset

    try expectEqual(null, map.get(hash("data")));
}

test "StaticBufferMap: overflow error" {
    var map = StaticBufferMap(i32, 2){};

    try map.put(1, 1);
    try map.put(2, 2);

    // Attempting to add a 3rd item should fail
    const result = map.put(3, 3);
    try std.testing.expectError(error.NoSpace, result);
}

test "StaticBufferMap: removal" {
    // Small capacity to force collisions
    var map = StaticBufferMap(i32, 4){};

    // 1. Fill enough to potentially cause a collision chain
    try map.put(1, 1);
    try map.put(2, 2);
    try map.put(3, 3);

    // 2. Remove the middle element
    map.remove(2);

    // 3. Verify 'key2' is gone but 'key3' is still reachable (chain is not broken)
    try expectEqual(null, map.get(2));
    try expectEqual(3, map.get(3));

    // 4. Verify we can reuse the tombstone slot
    try map.put(4, 4);
    try expectEqual(4, map.get(4));
}

test "StaticBufferMap: performance benchmark" {
    const CAPACITY = 65536;
    const FILL_COUNT = 45000;
    var map = StaticBufferMap(u64, CAPACITY){};

    var timer = try std.time.Timer.start();

    // Benchmark PUT
    timer.reset();
    for (0..FILL_COUNT) |i| {
        try map.put(i, i);
    }
    const put_total = timer.read();

    // Benchmark GET
    timer.reset();
    var sink: u64 = 0;
    for (0..FILL_COUNT) |i| {
        sink += map.get(i).?;
    }
    const get_total = timer.read();

    // Ensure the compiler doesn't optimize away the GET loop
    std.mem.doNotOptimizeAway(sink);

    // Benchmark REMOVE
    timer.reset();
    for (0..FILL_COUNT) |i| {
        map.remove(i);
    }
    const remove_total = timer.read();

    const put_ns = @as(f64, @floatFromInt(put_total)) / FILL_COUNT;
    const get_ns = @as(f64, @floatFromInt(get_total)) / FILL_COUNT;
    const remove_ns = @as(f64, @floatFromInt(remove_total)) / FILL_COUNT;

    // Convert to Million Operations Per Second (MOPS)
    const put_mops = 1000.0 / put_ns;
    const get_mops = 1000.0 / get_ns;
    const remove_mops = 1000.0 / remove_ns;

    std.debug.print("\n📊 BENCHMARK: {d} items @ CAPACITY {d}\n", .{ FILL_COUNT, CAPACITY });
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    
    std.debug.print("PUT:    {d: >6.2} M ops/sec  |  {d: >7.2} ns/op  |  ({d: >4.1} ms total)\n", 
        .{ put_mops, put_ns, @as(f64, @floatFromInt(put_total)) / 1_000_000.0 });
        
    std.debug.print("GET:    {d: >6.2} M ops/sec  |  {d: >7.2} ns/op  |  ({d: >4.1} ms total)\n", 
        .{ get_mops, get_ns, @as(f64, @floatFromInt(get_total)) / 1_000_000.0 });
        
    std.debug.print("REMOVE: {d: >6.2} M ops/sec  |  {d: >7.2} ns/op  |  ({d: >4.1} ms total)\n", 
        .{ remove_mops, remove_ns, @as(f64, @floatFromInt(remove_total)) / 1_000_000.0 });
        
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
}
