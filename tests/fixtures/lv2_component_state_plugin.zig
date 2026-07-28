const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const ComponentStateProbe = struct {
    mode: u32 = 7,
    pending_mode: u32 = 7,
    worker_schedule: ?*core.lv2.WorkerScheduleSink = null,
    worker_requested: bool = false,
    worker_value: u32 = 0,

    pub const name = "LV2 Component State Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const component_state_maximum_encoded_size = 6;
    pub const lv2_worker_maximum_request_size = @sizeOf(u32);
    pub const lv2_worker_maximum_response_size = @sizeOf(u32);
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(
        self: *@This(),
        context: *core.process.ProcessContext(f32),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        if (!self.worker_requested) {
            self.worker_requested = true;
            const request: u32 = 2;
            const bytes = std.mem.asBytes(&request);
            if (self.worker_schedule) |schedule|
                _ = schedule.schedule(bytes);
        }
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const gain: f32 = @floatCast(parameters.load("gain"));
        for (input, output) |sample, *destination|
            destination.* = sample * gain +
                @as(f32, @floatFromInt(self.worker_value));
    }

    pub fn bindLv2WorkerSchedule(
        self: *@This(),
        schedule: *core.lv2.WorkerScheduleSink,
    ) void {
        self.worker_schedule = schedule;
    }

    pub fn runLv2Worker(
        _: *@This(),
        request: []const u8,
        response: *core.lv2.WorkerResponseSink,
    ) !void {
        if (request.len != @sizeOf(u32))
            return error.InvalidWorkerRequest;
        const value = @as(
            *align(1) const u32,
            @ptrCast(request.ptr),
        ).*;
        const result = value + 1;
        if (response.respond(std.mem.asBytes(&result)) != .success)
            return error.WorkerResponseRejected;
    }

    pub fn applyLv2WorkerResponse(
        self: *@This(),
        response: []const u8,
    ) !void {
        if (response.len != @sizeOf(u32))
            return error.InvalidWorkerResponse;
        self.worker_value = @as(
            *align(1) const u32,
            @ptrCast(response.ptr),
        ).*;
    }

    pub fn writeComponentState(
        self: *const @This(),
        writer: anytype,
    ) !void {
        try writer.writeByte(0xa5);
        try writer.writeInt(u32, self.mode, .little);
    }

    pub fn readComponentState(
        self: *@This(),
        reader: anytype,
    ) !void {
        if (try reader.takeByte() != 0xa5)
            return error.InvalidComponentState;
        self.pending_mode = try reader.takeInt(u32, .little);
    }

    pub fn afterComponentStateRestore(self: *@This()) void {
        self.mode = self.pending_mode;
    }
};

const Adapter = core.lv2.CoreAdapter(
    ComponentStateProbe,
    "https://zig-vst3.dev/tests/lv2-component-state",
    64,
);

pub export fn lv2_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor {
    return Adapter.descriptorAt(index);
}
