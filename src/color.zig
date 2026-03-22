//The MIT License (MIT)
//Copyright © 2026 <Jonathan Keyuk>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    /// Returns [r,g,b,a]
    pub fn flatten(self: Color) @Vector(4, u8) {
        return .{ self.r, self.g, self.b, self.a };
    }

    /// Takes [r,g,b,a]
    pub fn unflatten(vec: @Vector(4, u8)) Color {
        return .{ .r = vec[0], .g = vec[1], .b = vec[2], .a = vec[3] };
    }

    pub fn pack(self: Color) u32 {
        const r = @as(u32, self.r);
        const g = @as(u32, self.g);
        const b = @as(u32, self.b);
        const a = @as(u32, self.a);
        // Pack as RGBA in memory (Little-Endian order)
        return r | (g << 8) | (b << 16) | (a << 24);
    }

    pub fn unpack(val: u32) Color {
        return .{
            .r = @truncate(val),
            .g = @truncate(val >> 8),
            .b = @truncate(val >> 16),
            .a = @truncate(val >> 24),
        };
    }

    pub fn rgbaToHsv(self: Color) [3]f32 {
        const r = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b = @as(f32, @floatFromInt(self.b)) / 255.0;

        const max = @max(r, @max(g, b));
        const min = @min(r, @min(g, b));
        const delta = max - min;

        var h: f32 = 0;
        if (delta > 1e-5) {
            if (max == r) {
                h = (g - b) / delta;
                if (g < b) h += 6.0;
            } else if (max == g) {
                h = (b - r) / delta + 2.0;
            } else {
                h = (r - g) / delta + 4.0;
            }
            h /= 6.0;
        }

        const s = if (max > 1e-5) delta / max else 0;
        const v = max;

        return .{ h, s, v };
    }

    pub fn hsvToRgba(h: f32, s: f32, v: f32, a: f32) Color {
        const hue = h - @floor(h);
        const i = @floor(hue * 6.0);
        const f = hue * 6.0 - i;
        const p = v * (1.0 - s);
        const q = v * (1.0 - f * s);
        const t = v * (1.0 - (1.0 - f) * s);

        const sector = @as(i32, @intFromFloat(i));
        const rgb: [3]f32 = switch (sector) {
            0 => .{ v, t, p },
            1 => .{ q, v, p },
            2 => .{ p, v, t },
            3 => .{ p, q, v },
            4 => .{ t, p, v },
            else => .{ v, p, q },
        };

        return Color{
            .r = @as(u8, @intFromFloat(@round(rgb[0] * 255.0))),
            .g = @as(u8, @intFromFloat(@round(rgb[1] * 255.0))),
            .b = @as(u8, @intFromFloat(@round(rgb[2] * 255.0))),
            .a = @as(u8, @intFromFloat(@round(a * 255.0))),
        };
    }
};
