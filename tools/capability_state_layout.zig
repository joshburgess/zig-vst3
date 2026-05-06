const std = @import("std");
const automation = @import("vst3-zig").pluginterfaces.vst.ivstautomationstate;
const interface_support = @import("vst3-zig").pluginterfaces.vst.ivstpluginterfacesupport;
const prefetch = @import("vst3-zig").pluginterfaces.vst.ivstprefetchablesupport;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ePrefetchableSupport.kIsNeverPrefetchable {}\n", .{@intFromEnum(prefetch.ePrefetchableSupport.kIsNeverPrefetchable)});
    try stdout.print("ePrefetchableSupport.kIsYetPrefetchable {}\n", .{@intFromEnum(prefetch.ePrefetchableSupport.kIsYetPrefetchable)});
    try stdout.print("ePrefetchableSupport.kIsNotYetPrefetchable {}\n", .{@intFromEnum(prefetch.ePrefetchableSupport.kIsNotYetPrefetchable)});
    try stdout.print("ePrefetchableSupport.kNumPrefetchableSupport {}\n", .{@intFromEnum(prefetch.ePrefetchableSupport.kNumPrefetchableSupport)});
    try stdout.print("IAutomationState.kNoAutomation {}\n", .{automation.AutomationStates.kNoAutomation});
    try stdout.print("IAutomationState.kReadState {}\n", .{automation.AutomationStates.kReadState});
    try stdout.print("IAutomationState.kWriteState {}\n", .{automation.AutomationStates.kWriteState});
    try stdout.print("IAutomationState.kReadWriteState {}\n", .{automation.AutomationStates.kReadWriteState});

    try printType(stdout, "IPlugInterfaceSupport", interface_support.IPlugInterfaceSupport);
    try printType(stdout, "IPrefetchableSupport", prefetch.IPrefetchableSupport);
    try printType(stdout, "IAutomationState", automation.IAutomationState);

    try printTuid(stdout, "IPlugInterfaceSupport", interface_support.iplug_interface_support_iid);
    try printTuid(stdout, "IPrefetchableSupport", prefetch.iprefetchable_support_iid);
    try printTuid(stdout, "IAutomationState", automation.iautomation_state_iid);
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
