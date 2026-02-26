# Parallel Programming in Zig: Threads, Shared Memory, and 

## Introduction

This post continues my exploration of low-level programming and the Zig language. Today, we will explore the fundamental concepts of parallel programming. We'll start by defining what threads are, then move on to spawning them in Zig, and finally, we'll see how to handle shared memory safely using synchronization primitives.

---

## Step 1: The Basic Process

Every program runs as a process with at least one thread. Let's start by creating a simple task and running it in our `main` function. At this stage, everything is sequential.

```zig
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
```

```
Output:
Starting main thread...
task 1 is running
Finished main thread.
```

---

## Step 2: Spawning Your First Thread

Now, let's use `std.Thread.spawn` to run the task on a separate path of execution. We use `thread.join()` to tell the main thread to wait for the worker to finish.

Note that in Zig 0.16, `main` can receive a `std.process.Init` argument, which gives us access to `std.Io` — used here to measure elapsed time with `std.Io.Clock`.

```zig
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
```

```
Output:
Task 1 is running thread: 1134137
Time: 1000ms
```

---

## Step 3: Running in Parallel

To use your CPU cores effectively, we can spawn multiple threads. By storing them in an array and joining them after spawning all of them, they all work at the same time.

Notice that 4 threads each sleeping for 1 second still complete in ~1000ms total — they truly run in parallel.

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const start = std.Io.Clock.now(.real, init.io);
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, task, .{i});
    }
    for (threads) |t| t.join();
    const end = std.Io.Clock.now(.real, init.io);
    const duration = start.durationTo(end);
    std.debug.print("Time: {}ms\n", .{duration.toMilliseconds()});
}

fn task(id: usize) void {
    std.debug.print("Task {} is running thread: {} \n", .{ id, std.Thread.getCurrentId() });
    var ts = std.posix.timespec{ .sec = 1, .nsec = 0 };
    _ = std.posix.system.nanosleep(&ts, &ts);
}
```

```
Output:
Task 0 is running thread: 1134350
Task 1 is running thread: 1134351
Task 2 is running thread: 1134352
Task 3 is running thread: 1134353
Time: 1000ms
```

---

## Step 4: The Shared Memory Problem (Race Condition)

Threads share the same memory space. If multiple threads try to update the same variable at once, they will overwrite each other's changes, causing a **race condition** — the final result will be inconsistent and unpredictable.

```zig
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
```

```
Output:
Result: { 311264, 289236, 273695 }
```

The expected result would be `{ 500000, 500000, 500000 }` (5 threads × 100000 iterations), but we get something different — and it changes on every run. That is the race condition in action.

---

## Step 5: Fixing it with Mutex and Defer

To fix the bug, we use a `Mutex` to lock the critical section — the block of code that accesses shared data. Only one thread can hold the lock at a time, so the others wait their turn.

In Zig 0.16, the mutex is `std.Io.Mutex` and its `lock`/`unlock` methods require passing the `std.Io` handle. We also pass `io` down to the task function for this reason.

Notice that we lock and unlock **inside** the loop, wrapping only the minimal critical section. Locking outside the loop would force threads to run one at a time for their entire duration, eliminating any parallelism benefit.

We also use `defer mutex.unlock(io)` immediately after the lock. This ensures the lock is always released when the block exits, even if an error occurs.

```zig
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
```

```
Output:
Result: { 500000, 500000, 500000 }
```

Now the result is consistent and correct on every run.

> **Tip:** For simple numeric operations on a single variable, Zig also provides `std.atomic.Value`, which can be more efficient than a Mutex since it avoids the overhead of locking entirely.

---

## Conclusion

Parallel programming is a powerful tool for building high-performance software, but it requires a solid understanding of how threads interact. We've seen how easy it is to spawn threads in Zig, but also how quickly shared memory can lead to subtle bugs. By using tools like `std.Io.Mutex` — and understanding *where* to apply them — we can protect our data and ensure our programs remain correct and reliable as they scale across multiple CPU cores.

---

## References

### Sources & Further Reading

* [Zig Language Official Site](https://ziglang.org/)
* [Zig-Book: Threads Chapter](https://pedropark99.github.io/zig-book/Chapters/14-threads.html)
* [Andrew Kelley: Zig's New Async/IO](https://andrewkelley.me/post/zig-new-async-io-text-version.html)
* [Reddit: Multithreading in Zig Discussion](https://www.reddit.com/r/Zig/comments/mytkpv/multithreading_in_zig/)
* [Visualizing Threading Concepts (Video)](https://www.youtube.com/watch?v=axphlFa3xB4)

---

## Contact

Feel free to reach out or follow my work:

- **GitHub:** [source](https://github.com/llllOllOOll/zig_thread_tutorial)
- **x:** [https://x.com/1111O11OO11](https://x.com/1111O11OO11)
- **Email:** 7b37b3@gmail.com

---



*Written with 0.16.0-dev.2565+684032671 — All code tested and verified.*


