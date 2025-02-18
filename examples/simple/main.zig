const std = @import("std");
const zigtress = @import("zigtress");
const Actor = zigtress.actor.Actor;

const quitCmd: []const u8 = "quit";

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

fn handlePrinter(s: *u32, msg: []u8) !void {
    s.* += 1;
    try std.fmt.format(stdout, "< #{d}: {s}\n> ", .{ s.*, msg });
}

fn inputLoop(printer: *Actor(u32, []u8)) void {
    var buf: [128]u8 = undefined;
    _ = stdout.write("> ") catch |err| std.debug.print("err: {any}", .{err});
    while (true) {
        if (stdin.readUntilDelimiterOrEof(buf[0..], '\n') catch |err| {
            std.debug.print("could not read stdin: '{any}', breaking up", .{err});
            break;
        }) |input| {
            if (std.mem.eql(u8, input, quitCmd)) {
                break;
            }
            printer.send(input) catch |err| {
                std.debug.print("could not senf to printer: '{any}', breaking up", .{err});
                break;
            };
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("leak");
    }

    var printerState: u32 = @intCast(0);
    var printer = try Actor(u32, []u8).init(
        alloc,
        &printerState,
        handlePrinter,
    );
    defer printer.deinit();
    std.log.default.info("# starting printer actor ...", .{});
    try printer.run();

    std.log.default.info("# starting input loop ...", .{});
    var reader = try std.Thread.spawn(.{}, inputLoop, .{&printer});
    reader.join();
    std.log.default.info("# input loop ended ...", .{});

    std.log.default.info("# stopping printer actor ...", .{});
    printer.stop();
    std.log.default.info("# bye ...", .{});
}
