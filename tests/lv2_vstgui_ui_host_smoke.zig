const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const ui = core.lv2.ui;
const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const ui.Descriptor;

fn discardWrite(
    _: ui.Controller,
    _: u32,
    _: u32,
    _: u32,
    _: ?*const anyopaque,
) callconv(.c) void {}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );
    if (args.len != 2) return error.InvalidArguments;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const descriptor_at = library.lookup(
        DescriptorFunction,
        "lv2ui_descriptor",
    ) orelse return error.MissingLv2UiDescriptor;
    const descriptor = descriptor_at(0) orelse
        return error.MissingLv2UiDescriptor;
    if (descriptor_at(1) != null)
        return error.UnexpectedLv2UiDescriptor;
    if (!std.mem.eql(
        u8,
        std.mem.span(descriptor.URI),
        "https://zig-vst3.dev/plugins/mono-gain#vstgui-ui",
    )) return error.InvalidLv2UiUri;

    for ([_][]const u8{
        ui.idle_interface_uri,
        ui.resize_uri,
        ui.show_interface_uri,
    }) |uri| {
        if (descriptor.extension_data(
            @ptrCast(uri.ptr),
        ) == null) return error.MissingLv2UiExtension;
    }

    var widget: ui.Widget = null;
    const no_features = [_:null]?*const ui.Feature{};
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/plugins/mono-gain",
        "/tmp/mono-gain.lv2",
        discardWrite,
        null,
        &widget,
        &no_features,
    ) != null) return error.MissingParentAccepted;

    var parent_feature = ui.Feature{
        .URI = ui.parent_uri,
        .data = null,
    };
    const null_parent = [_:null]?*const ui.Feature{
        &parent_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/plugins/mono-gain",
        "/tmp/mono-gain.lv2",
        discardWrite,
        null,
        &widget,
        &null_parent,
    ) != null) return error.NullParentAccepted;

    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/plugins/wrong",
        "/tmp/mono-gain.lv2",
        discardWrite,
        null,
        &widget,
        &null_parent,
    ) != null) return error.WrongPluginAccepted;
    if (descriptor.instantiate(
        descriptor,
        "https://zig-vst3.dev/plugins/mono-gain",
        "/tmp/mono-gain.lv2",
        null,
        null,
        &widget,
        &null_parent,
    ) != null) return error.MissingWriteFunctionAccepted;
}
