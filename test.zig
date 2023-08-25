const std = @import("std");
const libcoro = @import("libcoro");

test "simple" {
    const allocator = std.heap.c_allocator;

    const T = struct {
        fn simple_coro(x: *i32) void {
            x.* += 1;

            // Use yield to switch back to the calling coroutine (which may be the main
            // thread)
            libcoro.xsuspend();

            x.* += 3;
        }
    };

    // Create the coroutine.
    // It has a dedicated stack. You can specify the allocator and stack size
    // (initAlloc) or provide a stack directly (init).
    var x: i32 = 0;
    var coro = try libcoro.Coro.initAlloc(T.simple_coro, .{&x}, allocator, null);
    defer coro.deinit();

    // Coroutines start off paused.
    try std.testing.expectEqual(x, 0);

    // xresume switches to the coroutine.
    libcoro.xresume(coro);
    try std.testing.expectEqual(x, 1);

    libcoro.xresume(coro);
    try std.testing.expectEqual(x, 4);

    // Finished coroutines are marked done
    try std.testing.expect(coro.done);
}

var idx: usize = 0;
var steps = [_]usize{0} ** 8;

fn set_idx(val: usize) void {
    steps[idx] = val;
    idx += 1;
}

fn test_fn(x: *usize) void {
    set_idx(2);
    x.* += 2;
    libcoro.xsuspend();
    set_idx(4);
    x.* += 7;
    libcoro.xsuspend();
    set_idx(6);
    x.* += 1;
}

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stack_size: usize = 1024 * 2;
    const stack = try allocator.alignedAlloc(u8, libcoro.stack_align, stack_size);
    defer allocator.free(stack);

    set_idx(0);
    var x: usize = 88;
    var test_coro = libcoro.Coro.init(test_fn, .{&x}, stack);

    set_idx(1);
    try std.testing.expect(!test_coro.done);
    libcoro.xresume(test_coro);
    try std.testing.expectEqual(x, 90);
    set_idx(3);
    try std.testing.expect(!test_coro.done);
    libcoro.xresume(test_coro);
    try std.testing.expect(!test_coro.done);
    try std.testing.expectEqual(x, 97);
    x += 3;
    set_idx(5);
    libcoro.xresume(test_coro);
    try std.testing.expectEqual(x, 101);
    set_idx(7);

    try std.testing.expect(test_coro.done);

    for (0..steps.len) |i| {
        try std.testing.expectEqual(i, steps[i]);
    }
}
