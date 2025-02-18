const std = @import("std");

const channel = @import("channel.zig");
const Channel = channel.Channel;

fn HandleFn(comptime S: type, comptime T: type) type {
    return *const fn (s: *S, msg: T) anyerror!void;
}

pub fn Actor(comptime S: type, comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,

        state: *S,
        handle: HandleFn(S, T),

        channel: Channel(T, 128),
        thread: ?std.Thread = null,

        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        semaphore: std.Thread.Semaphore = std.Thread.Semaphore{},

        pub fn init(alloc: std.mem.Allocator, initial: *S, handle: HandleFn(S, T)) !@This() {
            return .{
                .alloc = alloc,
                .state = initial,
                .handle = handle,
                .channel = try Channel(T, 128).init(alloc),
            };
        }

        pub fn run(self: *@This()) !void {
            self.running.store(true, .seq_cst);
            self.thread = try std.Thread.spawn(.{}, loop, .{self});
        }

        pub fn wait(self: @This()) void {
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn loop(self: *@This()) void {
            var firstRun: bool = true;
            while (firstRun or self.running.load(.seq_cst)) {
                firstRun = false;
                if (self.channel.pop()) |msg| {
                    // TODO: define how to check errors here
                    self.handle(self.state, msg) catch @panic("woops");
                } else {
                    self.semaphore.wait();
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.channel.deinit();
        }

        pub fn send(self: *@This(), msg: T) !void {
            try self.channel.push(msg);
            self.semaphore.post();
        }

        pub fn stop(self: *@This()) void {
            defer self.wait();
            self.running.store(false, .seq_cst);
            self.semaphore.post();
        }
    };
}

const testing = std.testing;

test "actor" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var state = std.ArrayList(u8).init(fba.allocator());
    defer state.deinit();
    const H = struct {
        fn handle(s: *std.ArrayList(u8), msg: []const u8) !void {
            s.appendSlice(msg) catch @panic("woops");
        }
    };
    var actor = try Actor(std.ArrayList(u8), []const u8).init(testing.allocator, &state, H.handle);
    defer actor.deinit();
    try actor.run();
    std.Thread.sleep(0.1 * std.time.ns_per_s);
    try actor.send("Hi ");
    try actor.send("t");
    const run2 = struct {
        fn run(act: *Actor(std.ArrayList(u8), []const u8)) void {
            act.send("h") catch unreachable;
            act.send("e") catch unreachable;
        }
    }.run;
    var t2 = try std.Thread.spawn(.{}, run2, .{&actor});
    t2.join();
    try actor.send("r");
    try actor.send("e");
    try actor.send(" ");
    std.Thread.sleep(0.1 * std.time.ns_per_s);
    try actor.send("Peter");
    std.Thread.sleep(0.1 * std.time.ns_per_s);
    actor.stop();
    try testing.expectEqualStrings(state.items, "Hi there Peter");
}
