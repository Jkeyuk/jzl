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

        hashes: [CAPACITY]u64 = undefined,
        values: [CAPACITY]V = undefined,
        used_mask: std.StaticBitSet(CAPACITY) = .initEmpty(),
        max_probe: usize = 0,

        /// Retrieves a value by its key. Returns `null` if the key is not found.
        pub fn get(self: Self, key: u64) ?V {
            var i: usize = 0;
            // Stop at max_probe instead of CAPACITY
            while (i <= self.max_probe) : (i += 1) {
                const slot = (key + i) & MASK;

                if (!self.used_mask.isSet(slot)) return null;

                if (self.hashes[slot] == key) {
                    return self.values[slot];
                }
            }
            return null;
        }

        /// Inserts a value or updates an existing key.
        /// Returns `error.NoSpace` if the map is full.
        pub fn put(self: *Self, key: u64, value: V) !void {
            var curr_key = key;
            var curr_val = value;
            var i: usize = 0;

            while (i < CAPACITY) : (i += 1) {
                const slot = (curr_key + i) & MASK;

                if (self.used_mask.isSet(slot)) {
                    if (self.hashes[slot] == curr_key) {
                        self.values[slot] = curr_val;
                        return;
                    }

                    // Robin Hood Swap
                    // Calculate how far the current occupant is from its home
                    const occupied_ideal = self.hashes[slot] & MASK;
                    const occupied_distance = (slot + CAPACITY - occupied_ideal) & MASK;

                    if (i > occupied_distance) {
                        // The incoming item is "poorer" (further from home). Swap!
                        std.mem.swap(u64, &self.hashes[slot], &curr_key);
                        std.mem.swap(V, &self.values[slot], &curr_val);
                        // After swapping, 'i' must reflect the distance of the NEW curr_key
                        i = occupied_distance;
                    }
                    continue;
                }

                self.hashes[slot] = curr_key;
                self.values[slot] = curr_val;
                self.used_mask.set(slot);
                self.max_probe = @max(self.max_probe, i);
                return;
            }
            return error.NoSpace;
        }

        /// Wipes the map clean, making it empty.
        pub fn clear(self: *Self) void {
            self.used_mask = std.StaticBitSet(CAPACITY).initEmpty();
        }

        /// Removes a key from the map
        pub fn remove(self: *Self, key: u64) void {
            var i: usize = 0;
            while (i <= self.max_probe) : (i += 1) {
                const slot = (key + i) & MASK;
                if (!self.used_mask.isSet(slot)) return; // Key not found

                if (self.hashes[slot] == key) {
                    // 1. Clear the target
                    self.used_mask.unset(slot);

                    // 2. Backward Shift: Move following elements back to fill the gap
                    var j: usize = 1;
                    while (true) : (j += 1) {
                        const curr = (slot + j) & MASK;
                        const prev = (slot + j - 1) & MASK;

                        if (!self.used_mask.isSet(curr)) break;

                        // Check if the current element is at its "ideal" home.
                        // If it is, we can't move it back any further.
                        const ideal = self.hashes[curr] & MASK;
                        if (curr == ideal) break;

                        // Move it back!
                        self.hashes[prev] = self.hashes[curr];
                        self.values[prev] = self.values[curr];
                        self.used_mask.set(prev);
                        self.used_mask.unset(curr);
                    }
                    return;
                }
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
