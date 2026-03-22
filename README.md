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
