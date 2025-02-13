const std = @import("std");

fn HandleFn(comptime S: type, comptime T: type) type {
    return *const fn (s: *S, msg: T) anyerror!void;
}

pub fn Actor(comptime S: type, comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,

        state: *S,
        handle: HandleFn(S, T),

        channel: std.ArrayList(T),
        thread: ?std.Thread = null,
        mutex: std.Thread.Mutex,
        cond: std.Thread.Condition,

        running: bool = false,

        pub fn init(alloc: std.mem.Allocator, initial: *S, handle: HandleFn(S, T)) @This() {
            return .{
                .alloc = alloc,
                .state = initial,
                .handle = handle,
                .channel = std.ArrayList(T).init(alloc),
                .mutex = std.Thread.Mutex{},
                .cond = std.Thread.Condition{},
            };
        }

        pub fn run(self: *@This()) !void {
            self.thread = try std.Thread.spawn(.{}, loop, .{self});
        }

        pub fn wait(self: @This()) void {
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn loop(self: *@This()) void {
            self.running = true;
            while (true) {
                std.debug.print("loop:lock\n", .{});
                self.mutex.lock();

                defer {
                    std.debug.print("loop:unlock\n", .{});
                    self.mutex.unlock();
                }

                if (!self.running) {
                    std.debug.print("loop:running = false", .{});
                    break;
                }

                const msg = self.channel.popOrNull();
                std.debug.print("loop:popped {?}\n", .{msg});

                if (msg == null) {
                    std.debug.print("loop:msg is null, waiting for cond\n", .{});
                    self.cond.wait(&self.mutex);
                    std.debug.print("loop:cond signalled\n", .{});
                    continue;
                }

                std.debug.print("sending msg ...\n", .{});
                self.handle(self.state, msg orelse unreachable) catch @panic("woops");
            }
        }

        pub fn deinit(self: *@This()) void {
            self.channel.deinit();
        }

        pub fn send(self: *@This(), msg: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.channel.insert(0, msg);
            self.cond.signal();
        }

        pub fn stop(self: *@This()) void {
            defer self.wait();
            self.mutex.lock();
            defer self.mutex.unlock();
            self.running = false;
            self.cond.signal();
        }
    };
}

const testing = std.testing;

test "actor" {
    var state: i32 = 0;
    const H = struct {
        fn handle(s: *i32, msg: i32) !void {
            s.* += msg;
        }
    };
    var actor = Actor(i32, i32).init(testing.allocator, &state, H.handle);
    defer actor.deinit();
    try actor.run();
    std.Thread.sleep(0.5 * std.time.ns_per_s);
    try actor.send(1);
    try actor.send(1);
    std.Thread.sleep(0.5 * std.time.ns_per_s);
    try actor.send(1);
    std.Thread.sleep(0.5 * std.time.ns_per_s);
    actor.stop();
    try testing.expectEqual(state, 3);
}
