const std = @import("std");

pub fn Actor(comptime T: type) type {
    return struct {
        handleFn: *const fn (ptr: *Actor(T), message: T) anyerror!?T,

        pub fn handle(self: *Actor(T), message: T) !?T {
            return try self.handleFn(self, message);
        }
    };
}

// tests

const testing = std.testing;

pub const TestActor = struct {
    pub const T = union(enum) {
        add: i32,
        sub: i32,
        get: void,
        status: i32,
    };

    actor: Actor(T),

    count: i32,

    pub fn init() TestActor {
        return .{
            .actor = Actor(T){ .handleFn = handle },
            .count = 0,
        };
    }

    fn handle(actor: *Actor(T), message: T) anyerror!?T {
        const self: *TestActor = @fieldParentPtr("actor", actor);
        var ret: ?T = null;
        switch (message) {
            .add => |x| self.count += x,
            .sub => |x| self.count -= x,
            .get => ret = .{ .status = self.count },
            else => unreachable,
        }
        return ret;
    }
};

test "actor" {
    var myActor = TestActor.init();
    _ = try myActor.actor.handle(.{ .add = 2 });
    _ = try myActor.actor.handle(.{ .sub = 4 });
    try testing.expect(myActor.count == -2);
    const ret = try myActor.actor.handle(.{ .get = undefined }) orelse @panic("woops");
    try testing.expect(ret.status == -2);
}
