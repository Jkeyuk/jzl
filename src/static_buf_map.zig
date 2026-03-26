//The MIT License (MIT)
//Copyright © 2026 <Jonathan Keyuk>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");

/// A high-performance, allocator-free Hash Map with a fixed capacity.
/// Uses open addressing with linear probing and tombstones for efficient deletions.
pub fn StaticBufferMap(comptime V: type, comptime CAPACITY: usize) type {
    comptime {
        if (CAPACITY == 0 or (CAPACITY & (CAPACITY - 1)) != 0)
            @compileError("CAPACITY must be a power of 2");
    }

    const Entry = struct { value: V, hash: u64 };

    return struct {
        const Self = @This();
        const MASK = CAPACITY - 1;

        entries: [CAPACITY]Entry = undefined,
        used_mask: std.StaticBitSet(CAPACITY) = .initEmpty(),
        tombstone_mask: std.StaticBitSet(CAPACITY) = .initEmpty(),

        /// Inserts a value or updates an existing key.
        /// Returns `error.NoSpace` if the map is full.
        pub fn put(self: *Self, key: []const u8, value: V) !void {
            const h = hash(key);
            var first_tombstone: ?usize = null;
            var i: usize = 0;

            while (i < CAPACITY) : (i += 1) {
                const slot = (h + i) & MASK;

                // 1. Found a used slot?
                if (self.used_mask.isSet(slot)) {
                    if (self.entries[slot].hash == h) {
                        self.entries[slot].value = value; // Update existing
                        return;
                    }
                    continue; // Keep looking for the key
                }

                // 2. Found a tombstone?
                if (self.tombstone_mask.isSet(slot)) {
                    if (first_tombstone == null) first_tombstone = slot; // Remember it to reuse
                    continue; // Keep looking to make sure the key isn't later in the chain
                }

                // 3. Found a truly empty slot?
                // If we found a tombstone earlier, use that. Otherwise, use this empty slot.
                const insert_at = first_tombstone orelse slot;
                self.entries[insert_at] = .{ .value = value, .hash = h };
                self.used_mask.set(insert_at);
                self.tombstone_mask.unset(insert_at); // It's no longer a tombstone
                return;
            }
            return error.NoSpace;
        }

        /// Retrieves a value by its key. Returns `null` if the key is not found.
        pub fn get(self: Self, key: []const u8) ?V {
            const h = hash(key);
            var i: usize = 0;
            while (i < CAPACITY) : (i += 1) {
                const slot = (h + i) & MASK;
                if (!self.used_mask.isSet(slot) and
                    !self.tombstone_mask.isSet(slot)) return null;

                if (self.used_mask.isSet(slot) and
                    self.entries[slot].hash == h)
                {
                    return self.entries[slot].value;
                }
            }
            return null;
        }

        fn hash(key: []const u8) u64 {
            return std.hash.Wyhash.hash(0, key);
        }

        /// Wipes the map clean, making it empty.
        /// Note: This also clears all tombstones, improving subsequent lookup performance.
        pub fn clear(self: *Self) void {
            self.used_mask = std.StaticBitSet(CAPACITY).initEmpty();
            self.tombstone_mask = std.StaticBitSet(CAPACITY).initEmpty();
        }

        /// Logically removes a key from the map by placing a tombstone.
        pub fn remove(self: *Self, key: []const u8) void {
            const h = hash(key);
            var i: usize = 0;
            while (i < CAPACITY) : (i += 1) {
                const slot = (h + i) & MASK;
                // Stop if we hit a truly empty slot (not a tombstone)
                if (!self.used_mask.isSet(slot) and !self.tombstone_mask.isSet(slot)) return;

                if (self.used_mask.isSet(slot) and self.entries[slot].hash == h) {
                    self.used_mask.unset(slot);
                    self.tombstone_mask.set(slot); // Leave the tombstone
                    return;
                }
            }
        }
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "StaticBufferMap: basic put and get" {
    var map = StaticBufferMap(i32, 8){};

    try map.put("apple", 100);
    try map.put("banana", 200);

    try expectEqual(100, map.get("apple"));
    try expectEqual(200, map.get("banana"));
    try expectEqual(null, map.get("cherry"));
}

test "StaticBufferMap: overwrite existing key" {
    var map = StaticBufferMap(i32, 8){};

    try map.put("test", 1);
    try map.put("test", 2); // Should update

    try expectEqual(2, map.get("test"));
}

test "StaticBufferMap: clear/wipe the map" {
    var map = StaticBufferMap(i32, 8){};

    try map.put("data", 500);
    map.clear(); // Resets the bitset

    try expectEqual(null, map.get("data"));
}

test "StaticBufferMap: removal with tombstones" {
    // Small capacity to force collisions
    var map = StaticBufferMap(i32, 4){};

    // 1. Fill enough to potentially cause a collision chain
    try map.put("key1", 1);
    try map.put("key2", 2);
    try map.put("key3", 3);

    // 2. Remove the middle element
    map.remove("key2");

    // 3. Verify 'key2' is gone but 'key3' is still reachable (chain is not broken)
    try expectEqual(null, map.get("key2"));
    try expectEqual(3, map.get("key3"));

    // 4. Verify we can reuse the tombstone slot
    try map.put("key4", 4);
    try expectEqual(4, map.get("key4"));
}

test "StaticBufferMap: overflow error" {
    var map = StaticBufferMap(i32, 2){};

    try map.put("a", 1);
    try map.put("b", 2);

    // Attempting to add a 3rd item should fail
    const result = map.put("c", 3);
    try std.testing.expectError(error.NoSpace, result);
}
