const std = @import("std");
const inter_app_audio = @import("zig-vst3").pluginterfaces.vst.ivstinterappaudio;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try printType(stdout, "IInterAppAudioHost", inter_app_audio.IInterAppAudioHost);
    try printType(stdout, "IInterAppAudioConnectionNotification", inter_app_audio.IInterAppAudioConnectionNotification);
    try printType(stdout, "IInterAppAudioPresetManager", inter_app_audio.IInterAppAudioPresetManager);

    try printTuid(stdout, "IInterAppAudioHost", inter_app_audio.iinter_app_audio_host_iid);
    try printTuid(stdout, "IInterAppAudioConnectionNotification", inter_app_audio.iinter_app_audio_connection_notification_iid);
    try printTuid(stdout, "IInterAppAudioPresetManager", inter_app_audio.iinter_app_audio_preset_manager_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
