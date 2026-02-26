const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var arr = [_]i32{ 0, 0, 0 };
    var mutex = std.Io.Mutex.init;
    var threads: [5]std.Thread = undefined;

    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, task, .{ &arr, &mutex, init.io });
    }

    for (threads) |t| t.join();
    std.debug.print("Result: {any}\n", .{arr});
}

fn task(arr: *[3]i32, mutex: *std.Io.Mutex, io: std.Io) !void {
    for (0..100000) |_| {
        {
            try mutex.lock(io);
            defer mutex.unlock(io); // released at the end of this block
            for (0..3) |j| arr[j] += 1;
        }
    }
}
