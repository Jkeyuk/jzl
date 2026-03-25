//The MIT License (MIT)
//Copyright © 2026 <Jonathan Keyuk>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");

/// A generic tree node using the "First-Child/Next-Sibling" representation.
/// This allows each node to have an arbitrary number of children while
/// maintaining a constant memory overhead per node.
pub fn Node(comptime T: type) type {
    return struct {
        const Self = @This();
        /// The value stored within this node.
        data: T,
        /// Pointer to the parent node. Null if this is the root.
        parent: ?*Self = null,
        /// Pointer to the first child in this node's linked list of children.
        first_child: ?*Self = null,
        /// Pointer to the next sibling in the parent's list of children
        next_sibling: ?*Self = null,

        /// Allocates a new node on the heap and initializes its data.
        /// Caller owns the memory and must call `deinit`.
        pub inline fn init(allocator: std.mem.Allocator, data: T) !*Self {
            const new_node = try allocator.create(Node(T));
            new_node.* = .{
                .data = data,
            };
            return new_node;
        }

        /// Recursively frees this node and all of its descendants.
        /// This should only be called on the root of the subtree you wish to delete.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            var current_child = self.first_child;
            while (current_child) |child| {
                const next = child.next_sibling;
                child.deinit(allocator);
                current_child = next;
            }
            allocator.destroy(self);
        }

        /// Creates a new node and attaches it as the last child of the current node.
        /// Note: This is an O(N) operation where N is the number of existing children.
        pub inline fn beginChild(self: *Self, allocator: std.mem.Allocator, data: T) !*Self {
            const child = try Self.init(allocator, data);
            child.parent = self;

            if (self.first_child) |first| {
                var curr = first;
                while (curr.next_sibling) |next| : (curr = next) {}
                curr.next_sibling = child;
            } else {
                self.first_child = child;
            }
            return child;
        }

        /// Returns the parent of the current node.
        /// Useful for "closing" a level when building a tree fluently.
        pub inline fn endChild(self: *Self) ?*Self {
            return self.parent;
        }

        /// An iterator for traversing the immediate children of a node.
        pub const ChildIterator = struct {
            next_child: ?*Self,
            /// Returns the next sibling or null if at the end of the list.
            pub fn next(self: *ChildIterator) ?*Self {
                const node = self.next_child;
                if (self.next_child) |nc| {
                    self.next_child = nc.next_sibling;
                }
                return node;
            }
        };

        /// Creates an iterator for the immediate children of this node.
        pub fn child_iter(self: *Self) ChildIterator {
            return .{ .next_child = self.first_child };
        }

        /// A Depth-First Search iterator that uses a provided buffer as a stack.
        pub const DfsIterator = struct {
            stack: std.ArrayList(*Self) = .empty,

            /// Returns the next node in the DFS traversal.
            /// Caller must ensure the stack buffer is large enough.
            pub fn next(self: *DfsIterator) !?*Self {
                const node = self.stack.pop() orelse return null;
                if (node.next_sibling) |sib| self.stack.appendAssumeCapacity(sib);
                if (node.first_child) |child| self.stack.appendAssumeCapacity(child);
                return node;
            }
        };

        /// Initializes a DFS iterator using `buf` as the backing storage for the stack.
        /// The buffer must be large enough to hold the maximum expected tree depth/breadth.
        pub fn dfs_iter(self: *Self, buf: []*Self) !DfsIterator {
            var it = DfsIterator{
                .stack = .empty,
            };
            it.stack = std.ArrayList(*Self).initBuffer(buf);
            it.stack.appendAssumeCapacity(self);
            return it;
        }
    };
}

const TestNode = Node(u8);

const expectEqual = std.testing.expectEqual;

test "Tree_build" {
    const all = std.testing.allocator;

    const root = try TestNode.init(all, 0);
    defer root.deinit(all);

    const child = try root.beginChild(all, 1);
    const child2 = try root.beginChild(all, 2);

    try expectEqual(0, root.data);
    try expectEqual(1, child.data);
    try expectEqual(2, child2.data);

    var iter = root.child_iter();
    var count: usize = 0;
    while (iter.next()) |c| {
        count += 1;
        try expectEqual(count, c.data);
    }

    // expect 2 children
    try expectEqual(2, count);

    var child_iter = child.child_iter();
    count = 0;
    while (child_iter.next()) |_| {
        count += 1;
    }
    // expect 0 children
    try expectEqual(0, count);
}
