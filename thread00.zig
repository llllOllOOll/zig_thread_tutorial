const std = @import("std");

pub fn main() !void {
    std.debug.print("Starting main thread...\n", .{});
    task(1);
    std.debug.print("Finished main thread.\n", .{});
}

fn task(id: usize) void {
    std.debug.print("task {} is running\n", .{id});

    var ts = std.posix.timespec{ .sec = 1, .nsec = 0 };
    _ = std.posix.system.nanosleep(&ts, &ts);
}
