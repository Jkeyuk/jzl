//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

test  {
    _  = @import("text_wrap.zig");
    _  = @import("tree.zig");
    _  = @import("static_buf_map.zig");
}
