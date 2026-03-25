# Jon Zig Library

Collection of single file MIT licenced utilities to be dropped into projects as needed. Licence's are included in file headers.

## Overview

### color.zig

Color data type with convience functions.

### text_wrap.zig

Wraps text in-place by replacing spaces with newlines based on a maximum width.

This function uses a 'greedy' algorithm and accounts for contextual 
measurement (like kerning) by passing the entire line slice to the 
provided `calc_text_func`.

- `text`: The mutable buffer to wrap. Newlines ('\n') will be written here.
- `max_width`: The threshold at which a line must break.
- `line_spacing`: Extra vertical space added between wrapped lines.
- `calc_text_func`: A function matching `fn([]const u8, anytype) @Vector(2, f32)`.
- `calc_data`: Arbitrary context (font, scale, etc.) passed to the calc function.

Returns a `WrappedLayout` containing the modified slice and the total bounding box.

### tree.zig

#### Node(comptime T: type)

A generic tree node implementation using the **First-Child/Next-Sibling** representation. This structure allows each node to have an arbitrary number of children while maintaining a constant memory overhead (three pointers) per node.

---

#### Struct Definition


| Field | Type | Description |
| :--- | :--- | :--- |
| `data` | `T` | The value stored within this node. |
| `parent` | `?*Self` | Pointer to the parent node. `null` if this is the root. |
| `first_child` | `?*Self` | Pointer to the first child in the linked list of children. |
| `next_sibling` | `?*Self` | Pointer to the next sibling in the parent's list of children. |

---

#### Methods

##### `init(allocator: std.mem.Allocator, data: T) !*Self`
Allocates a new node on the heap and initializes its data.
- **Returns**: A pointer to the newly allocated node.
- **Error**: Returns `Allocator.Error` if memory allocation fails.
- **Note**: Caller owns the memory and must eventually call `deinit`.

##### `deinit(self: *Self, allocator: std.mem.Allocator) void`
Recursively frees the current node and all of its descendants (children, grandchildren, etc.).
- **Warning**: Only call this on the root of the subtree you wish to delete to avoid double-frees.

##### `beginChild(self: *Self, allocator: std.mem.Allocator, data: T) !*Self`
Creates a new node and attaches it as the **last child** of the current node.
- **Complexity**: **O(N)**, where N is the number of existing children (traverses the sibling list).
- **Returns**: A pointer to the newly created child node.

##### `endChild(self: *Self) ?*Self`
Returns the `parent` of the current node.
- **Use Case**: Useful for "closing" a level when building a tree fluently (e.g., `root.beginChild(...).beginChild(...).endChild()`).

---

## Iterators

##### `ChildIterator`
A non-recursive iterator for traversing the immediate children of a node.
- **`next(self: *ChildIterator) ?*Self`**: Returns the next sibling or `null` if the end of the list is reached.

##### `DfsIterator`
A Depth-First Search iterator that performs a pre-order traversal (Parent → First Child → Sibling).
- **Stack Requirement**: This iterator does not allocate; it uses a user-provided buffer as a stack.
- **`next(self: *DfsIterator) ?*Self`**: Returns the next node in the traversal.

---

## Iterator Helpers

##### `child_iter(self: *Self) ChildIterator`
Returns a `ChildIterator` initialized to the node's `first_child`.

##### `dfs_iter(self: *Self, buf: []*Self) DfsIterator`
Initializes a `DfsIterator` using `buf` as the backing storage for the stack.
- **Safety**: The buffer `buf` must be large enough to hold the maximum expected depth/breadth of the tree during traversal.
