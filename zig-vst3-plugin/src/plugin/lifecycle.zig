const std = @import("std");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const audio_layout = @import("audio_layout.zig");
const config = @import("config.zig");
const host_requests = @import("host_requests.zig");

pub const PrepareConfig = config.PrepareConfig;

fn validateVoidHook(
    comptime Plugin: type,
    comptime hook_name: []const u8,
    comptime hook_params: anytype,
    comptime message: []const u8,
) void {
    if (!@hasDecl(Plugin, hook_name)) return;

    const hook = @typeInfo(@TypeOf(@field(Plugin, hook_name))).@"fn";
    if (hook.params.len != hook_params.len) @compileError(message);
    if (hook.return_type.? != void) @compileError(message);
    inline for (hook_params, 0..) |expected_type, index| {
        if (hook.params[index].type.? != expected_type) {
            @compileError(message);
        }
    }
}

fn validateInitHook(comptime Plugin: type) void {
    if (!@hasDecl(Plugin, "init")) return;

    const init_info = @typeInfo(@TypeOf(Plugin.init)).@"fn";
    if (init_info.params.len != 1) {
        @compileError("init must be fn (std.mem.Allocator) !Plugin");
    }
    if (init_info.params[0].type.? != std.mem.Allocator) {
        @compileError("init must be fn (std.mem.Allocator) !Plugin");
    }

    const return_type = init_info.return_type orelse @compileError("init must return !Plugin");
    const return_info = @typeInfo(return_type);
    if (return_info != .error_union) @compileError("init must return !Plugin");
    if (return_info.error_union.payload != Plugin) @compileError("init must return !Plugin");
}

fn validateU32Hook(
    comptime Plugin: type,
    comptime hook_name: []const u8,
    comptime message: []const u8,
) void {
    if (!@hasDecl(Plugin, hook_name)) return;

    const hook = @typeInfo(@TypeOf(@field(Plugin, hook_name))).@"fn";
    if (hook.params.len != 1 or
        hook.params[0].type.? != *const Plugin or
        hook.return_type.? != u32)
        @compileError(message);
}

pub fn validateLifecycle(comptime Plugin: type) void {
    const auxiliary_audio_bus_capacity =
        if (@hasDecl(Plugin, "audio_bus_topology"))
            @TypeOf(Plugin.audio_bus_topology).auxiliary_capacity
        else if (@hasDecl(
            Plugin,
            "maximum_auxiliary_audio_buses",
        ))
            Plugin.maximum_auxiliary_audio_buses
        else
            audio_layout.max_auxiliary_audio_buses;
    const ProcessContext32 =
        process_api.BoundedProcessContext(
            f32,
            auxiliary_audio_bus_capacity,
        );
    const ProcessContext64 =
        process_api.BoundedProcessContext(
            f64,
            auxiliary_audio_bus_capacity,
        );
    validateInitHook(Plugin);
    validateVoidHook(
        Plugin,
        "prepare",
        .{ *Plugin, PrepareConfig },
        "prepare must be fn (*Plugin, PrepareConfig) void",
    );
    validateVoidHook(
        Plugin,
        "activate",
        .{*Plugin},
        "activate must be fn (*Plugin) void",
    );
    validateVoidHook(
        Plugin,
        "deactivate",
        .{*Plugin},
        "deactivate must be fn (*Plugin) void",
    );
    validateVoidHook(
        Plugin,
        "reset",
        .{*Plugin},
        "reset must be fn (*Plugin) void",
    );
    validateVoidHook(
        Plugin,
        "releaseResources",
        .{*Plugin},
        "releaseResources must be fn (*Plugin) void",
    );
    validateVoidHook(
        Plugin,
        "afterStateRestore",
        .{*Plugin},
        "afterStateRestore must be fn (*Plugin) void",
    );
    validateVoidHook(
        Plugin,
        "bindHostRequests",
        .{ *Plugin, *host_requests.HostRequestSink },
        "bindHostRequests must be fn (*Plugin, *plugin.HostRequestSink) void",
    );
    validateU32Hook(
        Plugin,
        "latencySamples",
        "latencySamples must be fn (*const Plugin) u32",
    );
    validateU32Hook(
        Plugin,
        "tailSamples",
        "tailSamples must be fn (*const Plugin) u32",
    );
    validateVoidHook(
        Plugin,
        "process",
        .{ *Plugin, *ProcessContext32 },
        "process must use the plugin's selected f32 ProcessContext type",
    );
    validateVoidHook(
        Plugin,
        "processWithParameterView",
        .{ *Plugin, *ProcessContext32, parameters.ParameterView(Plugin.Params) },
        "processWithParameterView must use the plugin's selected f32 ProcessContext type",
    );
    validateVoidHook(
        Plugin,
        "processWithParameters",
        .{
            *Plugin,
            *ProcessContext32,
            *const parameters.ParameterSet(Plugin.Params),
            *const parameters.ParameterValues(Plugin.Params),
        },
        "processWithParameters must use the plugin's selected f32 ProcessContext type",
    );
    validateVoidHook(
        Plugin,
        "process64",
        .{ *Plugin, *ProcessContext64 },
        "process64 must use the plugin's selected f64 ProcessContext type",
    );
    validateVoidHook(
        Plugin,
        "process64WithParameterView",
        .{ *Plugin, *ProcessContext64, parameters.ParameterView(Plugin.Params) },
        "process64WithParameterView must use the plugin's selected f64 ProcessContext type",
    );
    validateVoidHook(
        Plugin,
        "process64WithParameters",
        .{
            *Plugin,
            *ProcessContext64,
            *const parameters.ParameterSet(Plugin.Params),
            *const parameters.ParameterValues(Plugin.Params),
        },
        "process64WithParameters must use the plugin's selected f64 ProcessContext type",
    );
    validateVoidHook(Plugin, "deinit", .{*Plugin}, "deinit must be fn (*Plugin) void");
}
