const std = @import("std");
const edit_controller = @import("vst3-zig").pluginterfaces.vst.ivsteditcontroller;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kVstComponentControllerClass {s}\n", .{edit_controller.kVstComponentControllerClass});
    try stdout.print("ViewType.kEditor {s}\n", .{edit_controller.ViewType.kEditor});
    try stdout.print("ParameterInfo.kNoFlags {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kNoFlags});
    try stdout.print("ParameterInfo.kCanAutomate {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kCanAutomate});
    try stdout.print("ParameterInfo.kIsReadOnly {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsReadOnly});
    try stdout.print("ParameterInfo.kIsWrapAround {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsWrapAround});
    try stdout.print("ParameterInfo.kIsList {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsList});
    try stdout.print("ParameterInfo.kIsHidden {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsHidden});
    try stdout.print("ParameterInfo.kIsProgramChange {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsProgramChange});
    try stdout.print("ParameterInfo.kIsBypass {}\n", .{edit_controller.ParameterInfo.ParameterFlags.kIsBypass});
    try stdout.print("RestartFlags.kReloadComponent {}\n", .{edit_controller.RestartFlags.kReloadComponent});
    try stdout.print("RestartFlags.kIoChanged {}\n", .{edit_controller.RestartFlags.kIoChanged});
    try stdout.print("RestartFlags.kParamValuesChanged {}\n", .{edit_controller.RestartFlags.kParamValuesChanged});
    try stdout.print("RestartFlags.kLatencyChanged {}\n", .{edit_controller.RestartFlags.kLatencyChanged});
    try stdout.print("RestartFlags.kParamTitlesChanged {}\n", .{edit_controller.RestartFlags.kParamTitlesChanged});
    try stdout.print("RestartFlags.kMidiCCAssignmentChanged {}\n", .{edit_controller.RestartFlags.kMidiCCAssignmentChanged});
    try stdout.print("RestartFlags.kNoteExpressionChanged {}\n", .{edit_controller.RestartFlags.kNoteExpressionChanged});
    try stdout.print("RestartFlags.kIoTitlesChanged {}\n", .{edit_controller.RestartFlags.kIoTitlesChanged});
    try stdout.print("RestartFlags.kPrefetchableSupportChanged {}\n", .{edit_controller.RestartFlags.kPrefetchableSupportChanged});
    try stdout.print("RestartFlags.kRoutingInfoChanged {}\n", .{edit_controller.RestartFlags.kRoutingInfoChanged});
    try stdout.print("RestartFlags.kKeyswitchChanged {}\n", .{edit_controller.RestartFlags.kKeyswitchChanged});
    try stdout.print("RestartFlags.kParamIDMappingChanged {}\n", .{edit_controller.RestartFlags.kParamIDMappingChanged});
    try stdout.print("ProgressType.AsyncStateRestoration {}\n", .{@intFromEnum(edit_controller.ProgressType.AsyncStateRestoration)});
    try stdout.print("ProgressType.UIBackgroundTask {}\n", .{@intFromEnum(edit_controller.ProgressType.UIBackgroundTask)});
    try stdout.print("KnobModes.kCircularMode {}\n", .{@intFromEnum(edit_controller.KnobModes.kCircularMode)});
    try stdout.print("KnobModes.kRelativCircularMode {}\n", .{@intFromEnum(edit_controller.KnobModes.kRelativCircularMode)});
    try stdout.print("KnobModes.kLinearMode {}\n", .{@intFromEnum(edit_controller.KnobModes.kLinearMode)});

    try printType(stdout, "ParameterInfo", edit_controller.ParameterInfo);
    try printOffset(stdout, "ParameterInfo", "id", edit_controller.ParameterInfo, "id");
    try printOffset(stdout, "ParameterInfo", "title", edit_controller.ParameterInfo, "title");
    try printOffset(stdout, "ParameterInfo", "shortTitle", edit_controller.ParameterInfo, "shortTitle");
    try printOffset(stdout, "ParameterInfo", "units", edit_controller.ParameterInfo, "units");
    try printOffset(stdout, "ParameterInfo", "stepCount", edit_controller.ParameterInfo, "stepCount");
    try printOffset(stdout, "ParameterInfo", "defaultNormalizedValue", edit_controller.ParameterInfo, "defaultNormalizedValue");
    try printOffset(stdout, "ParameterInfo", "unitId", edit_controller.ParameterInfo, "unitId");
    try printOffset(stdout, "ParameterInfo", "flags", edit_controller.ParameterInfo, "flags");

    try printTuid(stdout, "IComponentHandler", edit_controller.icomponent_handler_iid);
    try printTuid(stdout, "IComponentHandler2", edit_controller.icomponent_handler2_iid);
    try printTuid(stdout, "IComponentHandlerBusActivation", edit_controller.icomponent_handler_bus_activation_iid);
    try printTuid(stdout, "IProgress", edit_controller.iprogress_iid);
    try printTuid(stdout, "IEditController", edit_controller.iedit_controller_iid);
    try printTuid(stdout, "IEditController2", edit_controller.iedit_controller2_iid);
    try printTuid(stdout, "IMidiMapping", edit_controller.imidi_mapping_iid);
    try printTuid(stdout, "IEditControllerHostEditing", edit_controller.iedit_controller_host_editing_iid);
    try printTuid(stdout, "IComponentHandlerSystemTime", edit_controller.icomponent_handler_system_time_iid);
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
