const std = @import("std");

// This will produce inconsistent results!

pub fn main() !void {
    var arr = [_]i32{ 0, 0, 0 };
    var threads: [5]std.Thread = undefined;

    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, task, .{&arr});
    }

    for (threads) |t| t.join();
    std.debug.print("Result: {any}\n", .{arr});
}

fn task(arr: *[3]i32) void {
    for (0..100000) |_| {
        for (0..3) |j| arr[j] += 1;
    }
}
