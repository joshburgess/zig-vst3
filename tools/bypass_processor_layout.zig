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
    var processor_storage32 = [_]f32{0} ** 8;
    var processor_delay32 = bypass.Delay(f32).init(&processor_storage32, 5, 3);
    processor_delay32.flush();
    var delay_input32 = [_]f32{ 1, 2, 3, 4, 5 };
    var delay_output32 = [_]f32{0} ** 5;
    const silent32 = processor_delay32.process(&delay_input32, &delay_output32, 5, false);
    try stdout.print("Delay32.hasDelay {}\n", .{@intFromBool(processor_delay32.hasDelay())});
    try stdout.print("Delay32.bufferSamples {}\n", .{processor_delay32.getBufferSamples()});
    try stdout.print("Delay32.process.silent {}\n", .{@intFromBool(silent32)});
    try stdout.print("Delay32.output0 {d:.1}\n", .{delay_output32[0]});
    try stdout.print("Delay32.output4 {d:.1}\n", .{delay_output32[4]});
    var no_delay_storage32 = [_]f32{};
    var no_delay32 = bypass.Delay(f32).init(&no_delay_storage32, 5, 0);
    var no_delay_output32 = [_]f32{0} ** 3;
    const no_delay_silent32 = no_delay32.process(&delay_input32, &no_delay_output32, 3, false);
    try stdout.print("Delay32.noDelay.silent {}\n", .{@intFromBool(no_delay_silent32)});
    try stdout.print("Delay32.noDelay.output2 {d:.1}\n", .{no_delay_output32[2]});
    const null_silent32 = no_delay32.process(null, &no_delay_output32, 3, true);
    try stdout.print("Delay32.nullInput.silent {}\n", .{@intFromBool(null_silent32)});
    try stdout.print("Delay32.nullInput.output2 {d:.1}\n", .{no_delay_output32[2]});
}
