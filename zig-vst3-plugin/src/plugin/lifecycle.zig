const std = @import("std");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const config = @import("config.zig");

pub const PrepareConfig = config.PrepareConfig;

pub fn validateLifecycle(comptime Plugin: type) void {
    if (@hasDecl(Plugin, "init")) {
        const init_info = @typeInfo(@TypeOf(Plugin.init)).@"fn";
        if (init_info.params.len != 1 or init_info.params[0].type.? != std.mem.Allocator) {
            @compileError("init must be fn (std.mem.Allocator) !Plugin");
        }
        const return_type = init_info.return_type orelse @compileError("init must return !Plugin");
        const return_info = @typeInfo(return_type);
        if (return_info != .error_union or return_info.error_union.payload != Plugin) {
            @compileError("init must return !Plugin");
        }
    }
    if (@hasDecl(Plugin, "prepare")) {
        const prepare = @typeInfo(@TypeOf(Plugin.prepare)).@"fn";
        if (prepare.params.len != 2 or prepare.params[0].type.? != *Plugin or prepare.params[1].type.? != PrepareConfig or prepare.return_type.? != void) {
            @compileError("prepare must be fn (*Plugin, PrepareConfig) void");
        }
    }
    if (@hasDecl(Plugin, "process")) {
        const process = @typeInfo(@TypeOf(Plugin.process)).@"fn";
        if (process.params.len != 2 or process.params[0].type.? != *Plugin or process.params[1].type.? != *process_api.ProcessContext(f32) or process.return_type.? != void) {
            @compileError("process must be fn (*Plugin, *process.ProcessContext(f32)) void");
        }
    }
    if (@hasDecl(Plugin, "processWithParameterView")) {
        const process = @typeInfo(@TypeOf(Plugin.processWithParameterView)).@"fn";
        if (process.params.len != 3 or
            process.params[0].type.? != *Plugin or
            process.params[1].type.? != *process_api.ProcessContext(f32) or
            process.params[2].type.? != parameters.ParameterView(Plugin.Params) or
            process.return_type.? != void)
        {
            @compileError("processWithParameterView must be fn (*Plugin, *process.ProcessContext(f32), ParameterView) void");
        }
    }
    if (@hasDecl(Plugin, "processWithParameters")) {
        const process = @typeInfo(@TypeOf(Plugin.processWithParameters)).@"fn";
        if (process.params.len != 4 or
            process.params[0].type.? != *Plugin or
            process.params[1].type.? != *process_api.ProcessContext(f32) or
            process.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process.return_type.? != void)
        {
            @compileError("processWithParameters must be fn (*Plugin, *process.ProcessContext(f32), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "process64")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64)).@"fn";
        if (process64.params.len != 2 or process64.params[0].type.? != *Plugin or process64.params[1].type.? != *process_api.ProcessContext(f64) or process64.return_type.? != void) {
            @compileError("process64 must be fn (*Plugin, *process.ProcessContext(f64)) void");
        }
    }
    if (@hasDecl(Plugin, "process64WithParameterView")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64WithParameterView)).@"fn";
        if (process64.params.len != 3 or
            process64.params[0].type.? != *Plugin or
            process64.params[1].type.? != *process_api.ProcessContext(f64) or
            process64.params[2].type.? != parameters.ParameterView(Plugin.Params) or
            process64.return_type.? != void)
        {
            @compileError("process64WithParameterView must be fn (*Plugin, *process.ProcessContext(f64), ParameterView) void");
        }
    }
    if (@hasDecl(Plugin, "process64WithParameters")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64WithParameters)).@"fn";
        if (process64.params.len != 4 or
            process64.params[0].type.? != *Plugin or
            process64.params[1].type.? != *process_api.ProcessContext(f64) or
            process64.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process64.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process64.return_type.? != void)
        {
            @compileError("process64WithParameters must be fn (*Plugin, *process.ProcessContext(f64), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "deinit")) {
        const deinit = @typeInfo(@TypeOf(Plugin.deinit)).@"fn";
        if (deinit.params.len != 1 or deinit.params[0].type.? != *Plugin or deinit.return_type.? != void) {
            @compileError("deinit must be fn (*Plugin) void");
        }
    }
}
