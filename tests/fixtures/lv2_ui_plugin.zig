const builtin = @import("builtin");
const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const Probe = struct {
    pub const name = "LV2 UI Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 7,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn process(
        _: *@This(),
        _: *core.process.ProcessContext(f32),
    ) void {}
};

const CoreAdapter = core.lv2.CoreAdapter(
    Probe,
    "https://zig-vst3.dev/tests/lv2-ui-probe",
    64,
);

const Backend = struct {
    const State = struct {
        size: core.gui.Size = .{ .width = 320, .height = 200 },
        parameter: f64 = 0.5,
        idle_count: usize = 0,
    };

    pub fn create(context: core.gui.Context) core.gui.Error!core.gui.Editor {
        const state = std.heap.page_allocator.create(State) catch
            return error.Rejected;
        state.* = .{};
        return .{
            .context = context,
            .adapter = .{
                .userdata = state,
                .vtable = &vtable,
            },
            .size = state.size,
            .resize_policy = .{
                .resizable = .{
                    .minimum = .{ .width = 160, .height = 100 },
                    .maximum = .{ .width = 800, .height = 600 },
                },
            },
        };
    }

    pub fn widget(adapter: core.gui.Adapter) ?*anyopaque {
        return adapter.userdata;
    }

    pub fn idle(adapter: core.gui.Adapter) bool {
        from(adapter.userdata).idle_count += 1;
        return true;
    }

    fn from(raw: *anyopaque) *State {
        return @ptrCast(@alignCast(raw));
    }

    fn attach(
        _: *anyopaque,
        _: core.gui.NativeParent,
        _: core.gui.Size,
        _: core.gui.Scale,
    ) core.gui.Error!void {}

    fn detach(_: *anyopaque) void {}

    fn resize(
        raw: *anyopaque,
        size: core.gui.Size,
    ) core.gui.Error!void {
        from(raw).size = size;
    }

    fn scale(
        _: *anyopaque,
        _: core.gui.Scale,
    ) core.gui.Error!void {}

    fn focus(_: *anyopaque, _: bool) void {}

    fn parameterChanged(
        raw: *anyopaque,
        _: u32,
        value: f64,
    ) void {
        from(raw).parameter = value;
    }

    fn destroy(raw: *anyopaque) void {
        std.heap.page_allocator.destroy(from(raw));
    }

    const vtable = core.gui.Adapter.VTable{
        .attach = attach,
        .detach = detach,
        .resize = resize,
        .scale = scale,
        .focus = focus,
        .parameter_changed = parameterChanged,
        .destroy = destroy,
    };
};

const platform: core.gui.Platform = switch (builtin.os.tag) {
    .macos => .macos,
    .windows => .windows,
    else => .x11,
};

const UiAdapter = core.lv2.ui.Adapter(
    Probe,
    CoreAdapter,
    "https://zig-vst3.dev/tests/lv2-ui-probe",
    "https://zig-vst3.dev/tests/lv2-ui-probe#ui",
    .{},
    platform,
    Backend,
);

pub export fn lv2ui_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.ui.Descriptor {
    return UiAdapter.descriptorAt(index);
}
