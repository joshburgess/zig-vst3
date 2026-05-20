const std = @import("std");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const config = @import("config.zig");

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

pub fn validateLifecycle(comptime Plugin: type) void {
    validateInitHook(Plugin);
    validateVoidHook(
        Plugin,
        "prepare",
        .{ *Plugin, PrepareConfig },
        "prepare must be fn (*Plugin, PrepareConfig) void",
    );
    validateVoidHook(
        Plugin,
        "process",
        .{ *Plugin, *process_api.ProcessContext(f32) },
        "process must be fn (*Plugin, *process.ProcessContext(f32)) void",
    );
    validateVoidHook(
        Plugin,
        "processWithParameterView",
        .{ *Plugin, *process_api.ProcessContext(f32), parameters.ParameterView(Plugin.Params) },
        "processWithParameterView must be fn (*Plugin, *process.ProcessContext(f32), ParameterView) void",
    );
    validateVoidHook(
        Plugin,
        "processWithParameters",
        .{
            *Plugin,
            *process_api.ProcessContext(f32),
            *const parameters.ParameterSet(Plugin.Params),
            *const parameters.ParameterValues(Plugin.Params),
        },
        "processWithParameters must be fn (*Plugin, *process.ProcessContext(f32), *const ParameterSet, *const ParameterValues) void",
    );
    validateVoidHook(
        Plugin,
        "process64",
        .{ *Plugin, *process_api.ProcessContext(f64) },
        "process64 must be fn (*Plugin, *process.ProcessContext(f64)) void",
    );
    validateVoidHook(
        Plugin,
        "process64WithParameterView",
        .{ *Plugin, *process_api.ProcessContext(f64), parameters.ParameterView(Plugin.Params) },
        "process64WithParameterView must be fn (*Plugin, *process.ProcessContext(f64), ParameterView) void",
    );
    validateVoidHook(
        Plugin,
        "process64WithParameters",
        .{
            *Plugin,
            *process_api.ProcessContext(f64),
            *const parameters.ParameterSet(Plugin.Params),
            *const parameters.ParameterValues(Plugin.Params),
        },
        "process64WithParameters must be fn (*Plugin, *process.ProcessContext(f64), *const ParameterSet, *const ParameterValues) void",
    );
    validateVoidHook(Plugin, "deinit", .{*Plugin}, "deinit must be fn (*Plugin) void");
}
