const std = @import("std");

extern fn zv3_pipewire_shim_self_test() callconv(.c) i32;

test "PipeWire native shim format and buffer contracts" {
    try std.testing.expectEqual(
        @as(i32, 0),
        zv3_pipewire_shim_self_test(),
    );
}
