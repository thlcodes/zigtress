const std = @import("std");

pub const ChannelError = error{ Full, Empty };

pub fn Channel(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = Channel(T, size);

        allocator: std.mem.Allocator,
        data: []T,

        reader: std.atomic.Value(usize),
        writer: std.atomic.Value(usize),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .data = try allocator.alloc(T, size),
                .reader = std.atomic.Value(usize).init(0),
                .writer = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn push(self: *Self, item: T) !void {
            const reader = self.reader.load(.seq_cst);
            const writer = self.writer.load(.seq_cst);

            if ((writer - reader) >= size) return ChannelError.Full;

            self.data[writer % size] = item;

            const newWriter = writer + 1;
            self.writer.store(newWriter, .seq_cst);
        }

        pub fn pop(self: *Self) !T {
            const reader = self.reader.load(.seq_cst);
            const writer = self.writer.load(.seq_cst);

            if (reader >= writer) return ChannelError.Empty;

            const newReader = reader + 1;

            self.reader.store(newReader, .seq_cst);
            return self.data[reader % size];
        }

        pub fn popOrNull(self: *Self) ?T {
            return self.pop() catch return null;
        }

        pub fn count(self: *Self) usize {
            const reader = self.reader.load(.seq_cst);
            const writer = self.writer.load(.seq_cst);
            return writer - reader;
        }
    };
}

// testing

const testing = std.testing;

test "channel" {
    {
        var channel = try Channel(i32, 10).init(testing.allocator);
        defer channel.deinit();

        // initially empty
        try testing.expectError(ChannelError.Empty, channel.pop());

        // push till full
        for (0..10) |i| {
            const res = channel.push(@intCast(i));
            if (i < 10) {
                try res;
            } else {
                try testing.expectError(ChannelError.Full, res);
            }
        }

        // read till empty
        for (0..10) |i| {
            const res = channel.pop();
            std.debug.print("{} {any}\n", .{ i, res });
            if (i < 10) {
                try testing.expectEqual(@as(i32, @intCast(i)), try res);
            } else {
                try testing.expectError(ChannelError.Empty, res);
                break;
            }
        }

        // push and pop
        for (0..100) |i| {
            try channel.push(@intCast(i));
            try testing.expectEqual(@as(i32, @intCast(i)), try channel.pop());
        }
    }

    {
        // threading
        var channel = try Channel(i32, 500).init(testing.allocator);
        defer channel.deinit();
        const H = struct {
            fn h(ch: *Channel(i32, 500)) !void {
                for (0..1000) |i| {
                    while (if (ch.push(@intCast(i))) |_| false else |_| true) {
                        std.Thread.sleep(1 * std.time.ns_per_us);
                    }
                    std.debug.print(" wrote: {}, count: {}\n", .{ i, ch.count() });
                    std.Thread.sleep(1 * std.time.ns_per_us);
                }
                std.debug.print("byte ...", .{});
            }
        };
        const t = try std.Thread.spawn(.{}, H.h, .{&channel});

        std.Thread.sleep(600 * std.time.ns_per_us);

        var check: i32 = @intCast(0);
        while (true) {
            if (channel.popOrNull()) |i| {
                std.debug.print("get: {}\n", .{i});
                try testing.expectEqual(i, check);
                check += 1;
                if (i == 999) break;
            } else {
                std.debug.print("empty, waiting ...\n", .{});
                std.Thread.sleep(1 * std.time.ns_per_ms);
            }
        }

        t.join();
    }
}
