const std = @import("std");
const zigtress = @import("zigtress");

pub fn main() !void {
    std.debug.print("{}", .{zigtress.add(1, 2)});
}
