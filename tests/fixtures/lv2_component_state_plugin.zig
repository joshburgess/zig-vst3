const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const ComponentStateProbe = struct {
    mode: u32 = 7,
    pending_mode: u32 = 7,
    worker_schedule: ?*core.lv2.WorkerScheduleSink = null,
    worker_requested: bool = false,
    worker_value: u32 = 0,
    worker_end_run_count: usize = 0,
    resource_path: [128]u8 = undefined,
    resource_path_length: usize = 0,
    pending_resource_path: [128]u8 = undefined,
    pending_resource_path_length: usize = 0,
    generated_path: [128]u8 = undefined,
    generated_path_length: usize = 0,
    pending_generated_path: [128]u8 = undefined,
    pending_generated_path_length: usize = 0,

    pub const name = "LV2 Component State Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const component_state_maximum_encoded_size = 265;
    pub const lv2_state_requires_make_path = true;
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

    pub fn endLv2WorkerRun(self: *@This()) !void {
        self.worker_end_run_count += 1;
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

    pub fn writeLv2ComponentState(
        self: *const @This(),
        writer: anytype,
        paths: core.lv2.StatePathFeatures,
    ) !void {
        const default_path = "/samples/original.wav";
        const source = if (self.resource_path_length == 0)
            default_path
        else
            self.resource_path[0..self.resource_path_length];
        var terminated: [129]u8 = @splat(0);
        @memcpy(terminated[0..source.len], source);
        var mapped = try paths.mapAbsolute(
            terminated[0..source.len :0],
        );
        defer mapped.deinit();
        const mapped_bytes = mapped.bytes();
        if (mapped_bytes.len > 128) return error.StatePathTooLong;
        var generated = try paths.makePath("generated/cache.bin");
        defer generated.deinit();
        var generated_terminated: [129]u8 = @splat(0);
        const generated_bytes = generated.bytes();
        if (generated_bytes.len > 128) return error.StatePathTooLong;
        @memcpy(
            generated_terminated[0..generated_bytes.len],
            generated_bytes,
        );
        var mapped_generated = try paths.mapAbsolute(
            generated_terminated[0..generated_bytes.len :0],
        );
        defer mapped_generated.deinit();
        const mapped_generated_bytes = mapped_generated.bytes();
        if (mapped_generated_bytes.len > 128)
            return error.StatePathTooLong;
        try writer.writeByte(0xa5);
        try writer.writeInt(u32, self.mode, .little);
        try writer.writeInt(u16, @intCast(mapped_bytes.len), .little);
        try writer.writeAll(mapped_bytes);
        try writer.writeInt(
            u16,
            @intCast(mapped_generated_bytes.len),
            .little,
        );
        try writer.writeAll(mapped_generated_bytes);
    }

    pub fn readLv2ComponentState(
        self: *@This(),
        reader: anytype,
        paths: core.lv2.StatePathFeatures,
    ) !void {
        if (try reader.takeByte() != 0xa5)
            return error.InvalidComponentState;
        self.pending_mode = try reader.takeInt(u32, .little);
        const mapped_length = try reader.takeInt(u16, .little);
        if (mapped_length == 0 or mapped_length > 128)
            return error.InvalidStatePath;
        var mapped: [129]u8 = @splat(0);
        try reader.readSliceAll(mapped[0..mapped_length]);
        var resolved = try paths.resolveAbstract(
            mapped[0..mapped_length :0],
        );
        defer resolved.deinit();
        const resolved_bytes = resolved.bytes();
        if (resolved_bytes.len > self.pending_resource_path.len)
            return error.StatePathTooLong;
        @memcpy(
            self.pending_resource_path[0..resolved_bytes.len],
            resolved_bytes,
        );
        self.pending_resource_path_length = resolved_bytes.len;
        const generated_length = try reader.takeInt(u16, .little);
        if (generated_length == 0 or generated_length > 128)
            return error.InvalidStatePath;
        var generated: [129]u8 = @splat(0);
        try reader.readSliceAll(generated[0..generated_length]);
        var resolved_generated = try paths.resolveAbstract(
            generated[0..generated_length :0],
        );
        defer resolved_generated.deinit();
        const resolved_generated_bytes = resolved_generated.bytes();
        if (resolved_generated_bytes.len >
            self.pending_generated_path.len)
            return error.StatePathTooLong;
        @memcpy(
            self.pending_generated_path[0..resolved_generated_bytes.len],
            resolved_generated_bytes,
        );
        self.pending_generated_path_length =
            resolved_generated_bytes.len;
    }

    pub fn afterComponentStateRestore(self: *@This()) void {
        self.mode = self.pending_mode;
        @memcpy(
            self.resource_path[0..self.pending_resource_path_length],
            self.pending_resource_path[0..self.pending_resource_path_length],
        );
        self.resource_path_length = self.pending_resource_path_length;
        @memcpy(
            self.generated_path[0..self.pending_generated_path_length],
            self.pending_generated_path[0..self.pending_generated_path_length],
        );
        self.generated_path_length = self.pending_generated_path_length;
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
