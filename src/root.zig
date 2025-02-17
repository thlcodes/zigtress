//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

pub const actor = @import("actor.zig");

// tests

const testing = std.testing;

test {
    testing.refAllDecls(@import("actor.zig"));
    testing.refAllDecls(@import("channel.zig"));
}
