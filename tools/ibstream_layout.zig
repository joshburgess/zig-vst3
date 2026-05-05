const std = @import("std");
const ibstream = @import("vst3-zig").pluginterfaces.base.ibstream;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("IBStream.kIBSeekSet {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet)});
    try stdout.print("IBStream.kIBSeekCur {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekCur)});
    try stdout.print("IBStream.kIBSeekEnd {}\n", .{@intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd)});
    try printTuid(stdout, "IBStream", ibstream.ibstream_iid);
    try printTuid(stdout, "ISizeableStream", ibstream.isizeable_stream_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
