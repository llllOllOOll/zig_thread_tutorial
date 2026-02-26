const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const start = std.Io.Clock.now(.real, init.io);

    const thread = try std.Thread.spawn(.{}, task, .{1});
    thread.join(); // This blocks the main thread until the task is done

    const end = std.Io.Clock.now(.real, init.io);
    const duration = start.durationTo(end);

    std.debug.print("Time: {}ms\n", .{duration.toMilliseconds()});
}

fn task(id: usize) void {
    std.debug.print("Task {} is running thread: {} \n", .{ id, std.Thread.getCurrentId() });
    var ts = std.posix.timespec{ .sec = 1, .nsec = 0 };
    _ = std.posix.system.nanosleep(&ts, &ts);
}
