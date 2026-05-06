const std = @import("std");
const function_name = @import("vst3-zig").pluginterfaces.vst.ivstparameterfunctionname;
const parameter_finder = @import("vst3-zig").pluginterfaces.vst.ivstplugview;
const remap = @import("vst3-zig").pluginterfaces.vst.ivstremapparamid;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("FunctionNameType.kCompGainReduction {s}\n", .{std.mem.span(function_name.FunctionNameType.kCompGainReduction)});
    try stdout.print("FunctionNameType.kCompGainReductionMax {s}\n", .{std.mem.span(function_name.FunctionNameType.kCompGainReductionMax)});
    try stdout.print("FunctionNameType.kCompGainReductionPeakHold {s}\n", .{std.mem.span(function_name.FunctionNameType.kCompGainReductionPeakHold)});
    try stdout.print("FunctionNameType.kCompResetGainReductionMax {s}\n", .{std.mem.span(function_name.FunctionNameType.kCompResetGainReductionMax)});
    try stdout.print("FunctionNameType.kLowLatencyMode {s}\n", .{std.mem.span(function_name.FunctionNameType.kLowLatencyMode)});
    try stdout.print("FunctionNameType.kDryWetMix {s}\n", .{std.mem.span(function_name.FunctionNameType.kDryWetMix)});
    try stdout.print("FunctionNameType.kRandomize {s}\n", .{std.mem.span(function_name.FunctionNameType.kRandomize)});
    try stdout.print("FunctionNameType.kPanPosCenterX {s}\n", .{std.mem.span(function_name.FunctionNameType.kPanPosCenterX)});
    try stdout.print("FunctionNameType.kPanPosCenterY {s}\n", .{std.mem.span(function_name.FunctionNameType.kPanPosCenterY)});
    try stdout.print("FunctionNameType.kPanPosCenterZ {s}\n", .{std.mem.span(function_name.FunctionNameType.kPanPosCenterZ)});

    try printTuid(stdout, "IParameterFunctionName", function_name.iparameter_function_name_iid);
    try printTuid(stdout, "IParameterFinder", parameter_finder.iparameter_finder_iid);
    try printTuid(stdout, "IRemapParamID", remap.iremap_param_id_iid);
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
