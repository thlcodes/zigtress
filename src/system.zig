const std = @import("std");

const Actor = @import("actor.zig").Actor;

const Ref = union(enum) {
    id: u32,
};

const Error = error{
    ActorNotFound,
};

allocator: std.mem.Allocator,

registry: std.AutoHashMap(u32, *anyopaque),

const System = @This();

pub fn init(allocator: std.mem.Allocator) System {
    return System{
        .allocator = allocator,
        .registry = std.AutoHashMap(u32, *anyopaque).init(allocator),
    };
}

pub fn deinit(self: *System) void {
    self.registry.deinit();
}

pub fn spawn(self: *System, actor: *anyopaque) !Ref {
    const id = self.registry.count();
    try self.registry.put(id, actor);
    return Ref{ .id = id };
}

pub fn send(self: *System, comptime T: type, ref: Ref, msg: T) !?T {
    const ptr = self.registry.get(ref.id) orelse return Error.ActorNotFound;
    // const T = @TypeOf(msg);
    const actorPtr: *Actor(T) = @ptrCast(@alignCast(ptr));
    // var actor = actorPtr.*;
    return try actorPtr.handle(msg);
}

// tests

const testing = std.testing;

test "system" {
    var system = init(testing.allocator);
    defer system.deinit();
    try testing.expect(system.registry.count() == 0);

    const TestActor = @import("actor.zig").TestActor;
    var testActor = TestActor.init();
    const ref = try system.spawn(&testActor.actor);
    try testing.expect(ref.id == 0);
    try testing.expect(system.registry.count() == 1);

    _ = try system.send(TestActor.T, ref, .{ .add = 1 });
    const ret = try system.send(TestActor.T, ref, .{ .get = undefined }) orelse @panic("woops");
    try testing.expectEqual(ret.status, 1);
}
