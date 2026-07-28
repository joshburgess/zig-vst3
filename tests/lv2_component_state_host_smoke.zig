const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor;

const StateHost = struct {
    parameter_bytes: [4096]u8 = undefined,
    parameter_size: usize = 0,
    parameter_type: core.lv2.Urid = 0,
    parameter_flags: u32 = 0,
    parameter_present: bool = false,
    component_bytes: [4096]u8 = undefined,
    component_size: usize = 0,
    component_type: core.lv2.Urid = 0,
    component_flags: u32 = 0,
    component_present: bool = false,

    fn map(
        _: ?*anyopaque,
        URI: [*:0]const u8,
    ) callconv(.c) core.lv2.Urid {
        const uri = std.mem.span(URI);
        if (std.mem.eql(u8, uri, core.lv2.atom_chunk_uri))
            return 23;
        if (std.mem.endsWith(u8, uri, "#parameterState"))
            return 17;
        if (std.mem.endsWith(u8, uri, "#componentState"))
            return 19;
        return @as(
            core.lv2.Urid,
            @truncate(std.hash.Wyhash.hash(0, uri)),
        ) | 0x8000_0000;
    }

    fn store(
        handle: core.lv2.StateHandle,
        key: core.lv2.Urid,
        value: *const anyopaque,
        size: usize,
        value_type: core.lv2.Urid,
        flags: u32,
    ) callconv(.c) core.lv2.StateStatus {
        const raw = handle orelse return .unknown;
        const self: *@This() = @ptrCast(@alignCast(raw));
        const source: [*]const u8 = @ptrCast(value);
        if (key == 17) {
            if (size > self.parameter_bytes.len) return .no_space;
            @memcpy(
                self.parameter_bytes[0..size],
                source[0..size],
            );
            self.parameter_size = size;
            self.parameter_type = value_type;
            self.parameter_flags = flags;
            self.parameter_present = true;
            return .success;
        }
        if (key == 19) {
            if (size > self.component_bytes.len) return .no_space;
            @memcpy(
                self.component_bytes[0..size],
                source[0..size],
            );
            self.component_size = size;
            self.component_type = value_type;
            self.component_flags = flags;
            self.component_present = true;
            return .success;
        }
        return .no_property;
    }

    fn retrieve(
        handle: core.lv2.StateHandle,
        key: core.lv2.Urid,
        size: *usize,
        value_type: *core.lv2.Urid,
        flags: *u32,
    ) callconv(.c) ?*const anyopaque {
        const raw = handle orelse return null;
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (key == 17 and self.parameter_present) {
            size.* = self.parameter_size;
            value_type.* = self.parameter_type;
            flags.* = self.parameter_flags;
            return &self.parameter_bytes;
        }
        if (key == 19 and self.component_present) {
            size.* = self.component_size;
            value_type.* = self.component_type;
            flags.* = self.component_flags;
            return &self.component_bytes;
        }
        return null;
    }
};

const WorkerHost = struct {
    interface: *const core.lv2.WorkerInterface,
    instance: core.lv2.Handle = null,
    work_count: usize = 0,
    response_count: usize = 0,

    fn schedule(
        context: ?*anyopaque,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) core.lv2.WorkerStatus {
        const self: *@This() = @ptrCast(
            @alignCast(context orelse return .unknown),
        );
        self.work_count += 1;
        return self.interface.work(
            self.instance,
            respond,
            self,
            size,
            data,
        );
    }

    fn respond(
        context: core.lv2.WorkerRespondHandle,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) core.lv2.WorkerStatus {
        const self: *@This() = @ptrCast(
            @alignCast(context orelse return .unknown),
        );
        self.response_count += 1;
        return self.interface.work_response(
            self.instance,
            size,
            data,
        );
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );
    if (args.len != 2) return error.InvalidArguments;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const descriptor_function = library.lookup(
        DescriptorFunction,
        "lv2_descriptor",
    ) orelse return error.MissingLv2Descriptor;
    const descriptor = descriptor_function(0) orelse
        return error.MissingPluginDescriptor;

    var urid_map = core.lv2.UridMap{
        .handle = null,
        .map = StateHost.map,
    };
    var map_feature = core.lv2.Feature{
        .URI = core.lv2.urid_map_uri,
        .data = &urid_map,
    };
    const raw_worker = descriptor.extension_data(
        core.lv2.worker_interface_uri,
    ) orelse return error.MissingWorkerInterface;
    const worker_interface: *const core.lv2.WorkerInterface =
        @ptrCast(@alignCast(raw_worker));
    var worker_host = WorkerHost{
        .interface = worker_interface,
    };
    var worker_schedule = core.lv2.WorkerSchedule{
        .handle = &worker_host,
        .schedule_work = WorkerHost.schedule,
    };
    var worker_feature = core.lv2.Feature{
        .URI = core.lv2.worker_schedule_uri,
        .data = &worker_schedule,
    };
    const features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
    };
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    worker_host.instance = handle;

    const raw_state = descriptor.extension_data(
        core.lv2.state_interface_uri,
    ) orelse return error.MissingStateInterface;
    const state: *const core.lv2.StateInterface =
        @ptrCast(@alignCast(raw_state));
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{0.0} ** input.len;
    var gain: f32 = 1.5;
    var latency: f32 = 0;
    descriptor.connect_port(handle, 0, @constCast(&input));
    descriptor.connect_port(handle, 1, &output);
    descriptor.connect_port(handle, 2, &gain);
    descriptor.connect_port(handle, 3, &latency);

    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    if (worker_host.work_count != 1)
        return error.WorkerWasNotScheduled;
    if (worker_host.response_count != 1)
        return error.WorkerDidNotRespond;
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 3.375, 2.25 },
        &output,
    );
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    var original = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &original,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    if (!original.parameter_present or
        !original.component_present or
        original.component_size != 5)
        return error.IncompleteState;

    original.component_bytes[1] = 9;
    original.component_bytes[2] = 0;
    original.component_bytes[3] = 0;
    original.component_bytes[4] = 0;
    gain = 0.5;
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    if (state.restore(
        handle,
        StateHost.retrieve,
        &original,
        0,
        null,
    ) != .success) return error.StateRestoreFailed;
    var restored = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &restored,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        original.parameter_bytes[0..original.parameter_size],
        restored.parameter_bytes[0..restored.parameter_size],
    ) or !std.mem.eql(
        u8,
        original.component_bytes[0..original.component_size],
        restored.component_bytes[0..restored.component_size],
    )) return error.StateRoundTripMismatch;

    gain = 0.25;
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    var before_failure = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &before_failure,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    original.component_bytes[0] = 0;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &original,
        0,
        null,
    ) != .bad_type) return error.MalformedStateAccepted;
    var after_failure = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &after_failure,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        before_failure.parameter_bytes[0..before_failure.parameter_size],
        after_failure.parameter_bytes[0..after_failure.parameter_size],
    ) or !std.mem.eql(
        u8,
        before_failure.component_bytes[0..before_failure.component_size],
        after_failure.component_bytes[0..after_failure.component_size],
    )) return error.FailedRestoreMutatedState;

    original.component_bytes[0] = 0xa5;
    original.component_bytes[5] = 0;
    original.component_size = 6;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &original,
        0,
        null,
    ) != .bad_type) return error.TrailingStateAccepted;
}
