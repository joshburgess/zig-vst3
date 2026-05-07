const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-plug-core");

pub fn readParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *plug.parameters.ParameterValues(Params),
) types.tresult {
    const input = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var read: types.int32 = 0;
    const result = input.vtable.read(input, &bytes, bytes.len, &read);
    if (result != types.kResultOk or read != bytes.len) return types.kResultFalse;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.readParameterState(Params, set, values, state_stream.reader()) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn writeParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *const plug.parameters.ParameterValues(Params),
) types.tresult {
    const output = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.writeParameterState(Params, set, values, state_stream.writer()) catch return types.kResultFalse;
    var written: types.int32 = 0;
    const result = output.vtable.write(output, &bytes, bytes.len, &written);
    if (result != types.kResultOk or written != bytes.len) return types.kResultFalse;
    return types.kResultOk;
}
