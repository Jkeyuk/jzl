//The MIT License (MIT)
//Copyright © 2026 <Jonathan Keyuk>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");

pub const WrappedLayout = struct {
    text: []const u8,
    total_size: @Vector(2, f32),
};

/// Wraps text in-place by replacing spaces with newlines based on a maximum width.
/// 
/// This function uses a 'greedy' algorithm and accounts for contextual 
/// measurement (like kerning) by passing the entire line slice to the 
/// provided `calc_text_func`.
///
/// - `text`: The mutable buffer to wrap. Newlines ('\n') will be written here.
/// - `max_width`: The threshold at which a line must break.
/// - `line_spacing`: Extra vertical space added between wrapped lines.
/// - `calc_text_func`: A function matching `fn([]const u8, anytype) @Vector(2, f32)`.
/// - `calc_data`: Arbitrary context (font, scale, etc.) passed to the calc function.
///
/// Returns a `WrappedLayout` containing the modified slice and the total bounding box.
pub fn wrap_on_words(
    text: []u8,
    max_width: f32,
    line_spacing: f32,
    calc_text_func: anytype,
    calc_data: anytype,
) WrappedLayout {
    if (text.len == 0) return .{ .text = text, .total_size = .{ 0, 0 } };

    var final_width: f32 = 0;
    var final_height: f32 = 0;
    var line_start: usize = 0;
    var last_space: ?usize = null;

    var current_line_height: f32 = 0;
    var last_known_good_width: f32 = 0;

    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        const is_end = (i == text.len);
        const is_space = if (!is_end) text[i] == ' ' else false;

        if (is_space or is_end) {
            const current_line_slice = text[line_start..i];
            const size = calc_text_func(current_line_slice, calc_data);

            if (size[0] > max_width and last_space != null) {
                const break_at = last_space.?;
                text[break_at] = '\n';

                final_width = @max(final_width, last_known_good_width);
                final_height += current_line_height + line_spacing;

                line_start = break_at + 1;
                last_space = null;
                current_line_height = 0;

                i = break_at;
                continue;
            }

            if (is_space) last_space = i;
            last_known_good_width = size[0];
            current_line_height = @max(current_line_height, size[1]);
        }
    }

    // Add the very last line
    final_width = @max(final_width, last_known_good_width);
    final_height += current_line_height;

    return .{
        .text = text,
        .total_size = .{ final_width, final_height },
    };
}

pub fn CALC_TEXT_DEFAULT(t: []const u8, _: anytype) @Vector(2, f32) {
    return .{ @as(f32, @floatFromInt(t.len)), if (t.len == 0) 0 else 1 };
}

test "Test_Empty" {
    var buff = "".*;
    const slice: []u8 = buff[0..];
    const wrap = wrap_on_words(
        slice,
        10,
        0,
        CALC_TEXT_DEFAULT,
        void,
    );
    try std.testing.expectEqualStrings("", wrap.text);
    try std.testing.expectEqualDeep(.{ 0, 0 }, wrap.total_size);
}

test "Test_Equal_Wrap" {
    var buff = "123 456 789".*;
    const slice: []u8 = buff[0..];
    const wrap = wrap_on_words(
        slice,
        3,
        0,
        CALC_TEXT_DEFAULT,
        1,
    );
    try std.testing.expectEqualStrings("123\n456\n789", wrap.text);
    try std.testing.expectEqualDeep(.{ 3, 3 }, wrap.total_size);
}

test "Test_Wrap" {
    var buff = "1234 6789 123 98765432100".*;
    const slice: []u8 = buff[0..];
    const wrap = wrap_on_words(slice, 10, 0, CALC_TEXT_DEFAULT, 1234);
    try std.testing.expectEqualStrings("1234 6789\n123\n98765432100", wrap.text);
    try std.testing.expectEqualDeep(.{ 11, 3 }, wrap.total_size);
}

fn print_tracker(text: []const u8, cursor: usize) void {
    for (text, 0..) |_, i| {
        if (i == cursor) {
            std.debug.print("V", .{});
        } else {
            std.debug.print(" ", .{});
        }
    }
    std.debug.print("\n", .{});
    for (text) |v| {
        if (v == '\n') {
            std.debug.print("X", .{});
        } else {
            std.debug.print("{c}", .{v});
        }
    }
    std.debug.print("\n", .{});
}

test "Test_Single_Long_Word" {
    // Word is longer than max_width. It should stay on one line (no space to wrap).
    var buff = "supercalifragilistic".*;
    const wrap = wrap_on_words(&buff, 5, 0, CALC_TEXT_DEFAULT, 1);

    try std.testing.expectEqualStrings("supercalifragilistic", wrap.text);
    // Width is 20 (len), height is 1
    try std.testing.expectEqualDeep(@Vector(2, f32){ 20, 1 }, wrap.total_size);
}

test "Test_Multiple_Spaces" {
    // Greedy behavior: keep as many spaces as fit.
    // "word" (4) + "  " (2) = 6.
    // The next space would make it 7 (overflow), so it wraps at the SECOND space.
    var buff = "word    word".*;
    const wrap = wrap_on_words(&buff, 6, 0, CALC_TEXT_DEFAULT, null);

    // Current code result: "word  \n word"
    try std.testing.expectEqualStrings("word  \n word", wrap.text);
}

test "Test_Exact_Width_Boundary" {
    // Fits exactly on the boundary
    var buff = "123 456".*;
    const wrap = wrap_on_words(&buff, 7, 0, CALC_TEXT_DEFAULT, null);

    try std.testing.expectEqualStrings("123 456", wrap.text);
    try std.testing.expectEqualDeep(@Vector(2, f32){ 7, 1 }, wrap.total_size);
}

test "Test_Line_Spacing" {
    var buff = "abc def".*;
    // Width 3 forces wrap at the space
    const wrap = wrap_on_words(&buff, 3, 2.5, CALC_TEXT_DEFAULT, null);

    try std.testing.expectEqualStrings("abc\ndef", wrap.text);
    // Height: Line1 (1.0) + Spacing (2.5) + Line2 (1.0) = 4.5
    try std.testing.expectEqualDeep(@Vector(2, f32){ 3, 4.5 }, wrap.total_size);
}

test "Test_Leading_Trailing_Spaces" {
    var buff = " leading ".*;
    const wrap = wrap_on_words(&buff, 20, 0, CALC_TEXT_DEFAULT, null);

    try std.testing.expectEqualStrings(" leading ", wrap.text);
    try std.testing.expectEqualDeep(@Vector(2, f32){ 9, 1 }, wrap.total_size);
}
