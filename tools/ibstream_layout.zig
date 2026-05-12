const std = @import("std");
const ibstream = @import("zig-vst3").pluginterfaces.base.ibstream;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try printType(stdout, "Steinberg::IBStream", ibstream.IBStream);
    try printType(stdout, "Steinberg::ISizeableStream", ibstream.ISizeableStream);
    try stdout.print("IBStream.kIBSeekSet {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet)});
    try stdout.print("IBStream.kIBSeekCur {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekCur)});
    try stdout.print("IBStream.kIBSeekEnd {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd)});
    try printTuid(stdout, "IBStream", ibstream.ibstream_iid);
    try printTuid(stdout, "ISizeableStream", ibstream.isizeable_stream_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime T: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(T), @alignOf(T) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
