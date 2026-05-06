const std = @import("std");
const component = @import("vst3-zig").pluginterfaces.vst.ivstcomponent;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kDefaultFactoryFlags {}\n", .{component.kDefaultFactoryFlags});
    try stdout.print("MediaTypes.kAudio {}\n", .{@intFromEnum(component.MediaTypes.kAudio)});
    try stdout.print("MediaTypes.kEvent {}\n", .{@intFromEnum(component.MediaTypes.kEvent)});
    try stdout.print("MediaTypes.kNumMediaTypes {}\n", .{@intFromEnum(component.MediaTypes.kNumMediaTypes)});
    try stdout.print("BusDirections.kInput {}\n", .{@intFromEnum(component.BusDirections.kInput)});
    try stdout.print("BusDirections.kOutput {}\n", .{@intFromEnum(component.BusDirections.kOutput)});
    try stdout.print("BusTypes.kMain {}\n", .{@intFromEnum(component.BusTypes.kMain)});
    try stdout.print("BusTypes.kAux {}\n", .{@intFromEnum(component.BusTypes.kAux)});
    try stdout.print("IoModes.kSimple {}\n", .{@intFromEnum(component.IoModes.kSimple)});
    try stdout.print("IoModes.kAdvanced {}\n", .{@intFromEnum(component.IoModes.kAdvanced)});
    try stdout.print("IoModes.kOfflineProcessing {}\n", .{@intFromEnum(component.IoModes.kOfflineProcessing)});
    try stdout.print("BusInfo.kDefaultActive {}\n", .{component.BusFlags.kDefaultActive});
    try stdout.print("BusInfo.kIsControlVoltage {}\n", .{component.BusFlags.kIsControlVoltage});

    try printType(stdout, "BusInfo", component.BusInfo);
    try printOffset(stdout, "BusInfo", "mediaType", component.BusInfo, "mediaType");
    try printOffset(stdout, "BusInfo", "direction", component.BusInfo, "direction");
    try printOffset(stdout, "BusInfo", "channelCount", component.BusInfo, "channelCount");
    try printOffset(stdout, "BusInfo", "name", component.BusInfo, "name");
    try printOffset(stdout, "BusInfo", "busType", component.BusInfo, "busType");
    try printOffset(stdout, "BusInfo", "flags", component.BusInfo, "flags");

    try printType(stdout, "RoutingInfo", component.RoutingInfo);
    try printOffset(stdout, "RoutingInfo", "mediaType", component.RoutingInfo, "mediaType");
    try printOffset(stdout, "RoutingInfo", "busIndex", component.RoutingInfo, "busIndex");
    try printOffset(stdout, "RoutingInfo", "channel", component.RoutingInfo, "channel");

    try printTuid(stdout, "IComponent", component.icomponent_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
