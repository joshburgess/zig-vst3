const std = @import("std");
const bypass = @import("vst3-zig").pluginterfaces.vst.vstbypassprocessor;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kMaxChannelsSupported {}\n", .{bypass.kMaxChannelsSupported});

    var in32 = [_]f32{ 1, 2, 3, 4, 5 };
    var out32 = [_]f32{0} ** 5;
    var delay32 = [_]f32{ 10, 20, 30, 40 };
    const result32 = bypass.delay(f32, 5, &in32, &out32, &delay32, 4, 2, 0);
    try stdout.print("delay32.result {}\n", .{@intFromBool(result32)});
    try stdout.print("delay32.out0 {d:.1}\n", .{out32[0]});
    try stdout.print("delay32.out1 {d:.1}\n", .{out32[1]});
    try stdout.print("delay32.out4 {d:.1}\n", .{out32[4]});
    try stdout.print("delay32.buffer0 {d:.1}\n", .{delay32[0]});
    try stdout.print("delay32.buffer3 {d:.1}\n", .{delay32[3]});

    var in64 = [_]f64{ 1.5, 2.5, 3.5, 4.5 };
    var out64 = [_]f64{0} ** 4;
    var delay64 = [_]f64{ 9.5, 8.5, 7.5 };
    const result64 = bypass.delay(f64, 4, &in64, &out64, &delay64, 3, 1, 0);
    try stdout.print("delay64.result {}\n", .{@intFromBool(result64)});
    try stdout.print("delay64.out0 {d:.1}\n", .{out64[0]});
    try stdout.print("delay64.out3 {d:.1}\n", .{out64[3]});
    try stdout.print("delay64.buffer0 {d:.1}\n", .{delay64[0]});
    try stdout.print("delay64.buffer2 {d:.1}\n", .{delay64[2]});
}
