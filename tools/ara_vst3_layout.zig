const std = @import("std");
const ara = @import("zig-vst3").ara_vst3;
const api = @import("zig-vst3-ara").raw;

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try printType(stdout, "ARA::IMainFactory", ara.IMainFactory);
    try printType(
        stdout,
        "ARA::IPlugInEntryPoint",
        ara.IPlugInEntryPoint,
    );
    try printType(
        stdout,
        "ARA::IPlugInEntryPoint2",
        ara.IPlugInEntryPoint2,
    );
    try printTuid(
        stdout,
        "ARA::IMainFactory",
        ara.main_factory_iid,
    );
    try printTuid(
        stdout,
        "ARA::IPlugInEntryPoint",
        ara.plug_in_entry_point_iid,
    );
    try printTuid(
        stdout,
        "ARA::IPlugInEntryPoint2",
        ara.plug_in_entry_point_2_iid,
    );
    try stdout.print(
        "ARA::IPlugInEntryPoint getFactory slot {} bind slot {}\n",
        .{
            @offsetOf(
                ara.IPlugInEntryPointVTable,
                "getFactory",
            ) / @sizeOf(*anyopaque),
            @offsetOf(
                ara.IPlugInEntryPointVTable,
                "bindToDocumentController",
            ) / @sizeOf(*anyopaque),
        },
    );

    try printType(
        stdout,
        "ARAInterfaceConfiguration",
        api.ARAInterfaceConfiguration,
    );
    try printType(stdout, "ARAFactory", api.ARAFactory);
    try printType(
        stdout,
        "ARADocumentControllerHostInstance",
        api.ARADocumentControllerHostInstance,
    );
    try printType(
        stdout,
        "ARADocumentControllerInterface",
        api.ARADocumentControllerInterface,
    );
    try printType(
        stdout,
        "ARADocumentControllerInstance",
        api.ARADocumentControllerInstance,
    );
    try printType(
        stdout,
        "ARAPlaybackRegionProperties",
        api.ARAPlaybackRegionProperties,
    );
    try printType(
        stdout,
        "ARAPlugInExtensionInstance",
        api.ARAPlugInExtensionInstance,
    );

    try stdout.print(
        "ARAFactory.supportedPlaybackTransformationFlags offset {}\n",
        .{@offsetOf(
            api.ARAFactory,
            "supportedPlaybackTransformationFlags",
        )},
    );
    try stdout.print(
        "ARADocumentControllerInterface.destroyContentReader offset {}\n",
        .{@offsetOf(
            api.ARADocumentControllerInterface,
            "destroyContentReader",
        )},
    );
    try stdout.print(
        "ARAPlugInExtensionInstance.editorViewInterface offset {}\n",
        .{@offsetOf(
            api.ARAPlugInExtensionInstance,
            "editorViewInterface",
        )},
    );
    try stdout.print(
        "ARA generation current {}\n",
        .{api.kARAAPIGeneration_2_3_Final},
    );
    try stdout.print(
        "ARA role flags {} {} {}\n",
        .{
            ara.playback_renderer_role,
            ara.editor_renderer_role,
            ara.editor_view_role,
        },
    );
}

fn printType(
    writer: anytype,
    comptime name: []const u8,
    comptime Type: type,
) !void {
    try writer.print(
        "{s} size {} align {}\n",
        .{ name, @sizeOf(Type), @alignOf(Type) },
    );
}

fn printTuid(
    writer: anytype,
    comptime name: []const u8,
    bytes: [16]u8,
) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
