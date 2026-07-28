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
    abstract_path_count: usize = 0,
    absolute_path_count: usize = 0,
    make_path_count: usize = 0,
    free_path_count: usize = 0,
    fail_path_mapping: bool = false,

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

    fn abstractPath(
        handle: core.lv2.StateHandle,
        absolute_path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8 {
        const self: *@This() = @ptrCast(
            @alignCast(handle orelse return null),
        );
        self.abstract_path_count += 1;
        if (self.fail_path_mapping) return null;
        const path = std.mem.span(absolute_path);
        const mapped = if (std.mem.eql(u8, path, "/samples/original.wav") or
            std.mem.eql(u8, path, "/restored/original.wav"))
            "resource/original.wav"
        else if (std.mem.eql(
            u8,
            path,
            "/state/generated/cache.bin",
        ) or std.mem.eql(
            u8,
            path,
            "/restored/generated/cache.bin",
        ))
            "state/generated/cache.bin"
        else
            return null;
        const copy = std.heap.page_allocator.dupeZ(
            u8,
            mapped,
        ) catch return null;
        return copy.ptr;
    }

    fn absolutePath(
        handle: core.lv2.StateHandle,
        abstract_path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8 {
        const self: *@This() = @ptrCast(
            @alignCast(handle orelse return null),
        );
        self.absolute_path_count += 1;
        if (self.fail_path_mapping) return null;
        const path = std.mem.span(abstract_path);
        const resolved = if (std.mem.eql(
            u8,
            path,
            "resource/original.wav",
        ))
            "/restored/original.wav"
        else if (std.mem.eql(
            u8,
            path,
            "state/generated/cache.bin",
        ))
            "/restored/generated/cache.bin"
        else
            return null;
        const copy = std.heap.page_allocator.dupeZ(
            u8,
            resolved,
        ) catch return null;
        return copy.ptr;
    }

    fn makePath(
        handle: core.lv2.StateHandle,
        path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8 {
        const self: *@This() = @ptrCast(
            @alignCast(handle orelse return null),
        );
        self.make_path_count += 1;
        if (self.fail_path_mapping or
            !std.mem.eql(
                u8,
                std.mem.span(path),
                "generated/cache.bin",
            ))
            return null;
        const copy = std.heap.page_allocator.dupeZ(
            u8,
            "/state/generated/cache.bin",
        ) catch return null;
        return copy.ptr;
    }

    fn freePath(
        handle: core.lv2.StateHandle,
        path: [*:0]u8,
    ) callconv(.c) void {
        const self: *@This() = @ptrCast(
            @alignCast(handle orelse return),
        );
        const length = std.mem.span(path).len;
        std.heap.page_allocator.free(path[0 .. length + 1]);
        self.free_path_count += 1;
    }
};

const WorkerHost = struct {
    const maximum_message_size = 16;

    interface: *const core.lv2.WorkerInterface,
    instance: core.lv2.Handle = null,
    request_bytes: [maximum_message_size]u8 = undefined,
    request_size: usize = 0,
    request_pending: bool = false,
    response_bytes: [maximum_message_size]u8 = undefined,
    response_size: usize = 0,
    response_pending: bool = false,
    work_count: usize = 0,
    response_count: usize = 0,
    delivery_count: usize = 0,
    work_status: core.lv2.WorkerStatus = .unknown,
    respond_entered: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),
    allow_response: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),
    work_finished: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),

    fn schedule(
        context: ?*anyopaque,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) core.lv2.WorkerStatus {
        const self: *@This() = @ptrCast(
            @alignCast(context orelse return .unknown),
        );
        if (self.request_pending or size > self.request_bytes.len)
            return .no_space;
        if (size != 0 and data == null) return .unknown;
        if (data) |raw| {
            const bytes: [*]const u8 = @ptrCast(raw);
            @memcpy(
                self.request_bytes[0..size],
                bytes[0..size],
            );
        }
        self.request_size = size;
        self.request_pending = true;
        return .success;
    }

    fn respond(
        context: core.lv2.WorkerRespondHandle,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) core.lv2.WorkerStatus {
        const self: *@This() = @ptrCast(
            @alignCast(context orelse return .unknown),
        );
        if (self.response_pending or size > self.response_bytes.len)
            return .no_space;
        if (size != 0 and data == null) return .unknown;
        self.respond_entered.store(true, .release);
        while (!self.allow_response.load(.acquire))
            std.Thread.yield() catch {};
        if (data) |raw| {
            const bytes: [*]const u8 = @ptrCast(raw);
            @memcpy(
                self.response_bytes[0..size],
                bytes[0..size],
            );
        }
        self.response_size = size;
        self.response_pending = true;
        self.response_count += 1;
        return .success;
    }

    fn runWork(self: *@This()) void {
        self.work_count += 1;
        const data: ?*const anyopaque = if (self.request_size == 0)
            null
        else
            self.request_bytes[0..self.request_size].ptr;
        self.work_status = self.interface.work(
            self.instance,
            respond,
            self,
            @intCast(self.request_size),
            data,
        );
        self.request_pending = false;
        self.work_finished.store(true, .release);
    }

    fn waitForResponse(self: *@This()) bool {
        while (!self.respond_entered.load(.acquire) and
            !self.work_finished.load(.acquire))
            std.Thread.yield() catch {};
        return self.respond_entered.load(.acquire);
    }

    fn deliverResponse(self: *@This()) core.lv2.WorkerStatus {
        if (!self.response_pending) return .unknown;
        const data: ?*const anyopaque = if (self.response_size == 0)
            null
        else
            self.response_bytes[0..self.response_size].ptr;
        const status = self.interface.work_response(
            self.instance,
            @intCast(self.response_size),
            data,
        );
        if (status == .success) {
            self.response_pending = false;
            self.delivery_count += 1;
        }
        return status;
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
    var state_host = StateHost{};
    var state_map_path = core.lv2.StateMapPath{
        .handle = &state_host,
        .abstract_path = StateHost.abstractPath,
        .absolute_path = StateHost.absolutePath,
    };
    var state_map_feature = core.lv2.Feature{
        .URI = core.lv2.state_map_path_uri,
        .data = &state_map_path,
    };
    var state_free_path = core.lv2.StateFreePath{
        .handle = &state_host,
        .free_path = StateHost.freePath,
    };
    var state_free_feature = core.lv2.Feature{
        .URI = core.lv2.state_free_path_uri,
        .data = &state_free_path,
    };
    var state_make_path = core.lv2.StateMakePath{
        .handle = &state_host,
        .path = StateHost.makePath,
    };
    var state_make_feature = core.lv2.Feature{
        .URI = core.lv2.state_make_path_uri,
        .data = &state_make_path,
    };
    const state_features = [_:null]?*const core.lv2.Feature{
        &state_map_feature,
        &state_free_feature,
        &state_make_feature,
    };
    const raw_worker = descriptor.extension_data(
        core.lv2.worker_interface_uri,
    ) orelse return error.MissingWorkerInterface;
    const worker_interface: *const core.lv2.WorkerInterface =
        @ptrCast(@alignCast(raw_worker));
    const end_run = worker_interface.end_run orelse
        return error.MissingWorkerEndRun;
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
    if (!worker_host.request_pending or worker_host.work_count != 0)
        return error.WorkerWasNotScheduled;
    if (worker_host.response_count != 0)
        return error.WorkerRespondedSynchronously;
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    var worker_thread = try std.Thread.spawn(
        .{},
        WorkerHost.runWork,
        .{&worker_host},
    );
    var worker_joined = false;
    defer if (!worker_joined) {
        worker_host.allow_response.store(true, .release);
        worker_thread.join();
    };
    if (!worker_host.waitForResponse()) {
        worker_thread.join();
        worker_joined = true;
        return error.WorkerDidNotRespond;
    }
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75 },
        &output,
    );
    worker_host.allow_response.store(true, .release);
    worker_thread.join();
    worker_joined = true;
    if (worker_host.work_status != .success or
        worker_host.work_count != 1 or
        worker_host.response_count != 1)
        return error.WorkerExecutionFailed;
    if (worker_host.deliverResponse() != .success)
        return error.WorkerResponseDeliveryFailed;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;
    if (worker_host.delivery_count != 1)
        return error.WorkerResponseWasNotDelivered;

    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 3.375, 2.25 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        null,
    ) != .no_feature) return error.MissingPathFeaturesAccepted;
    if (state_host.parameter_present or state_host.component_present)
        return error.PartialStateStoredWithoutPathFeatures;
    const map_only_features = [_:null]?*const core.lv2.Feature{
        &state_map_feature,
    };
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        map_only_features[0..].ptr,
    ) != .no_feature) return error.MissingFreePathAccepted;
    const without_make_features = [_:null]?*const core.lv2.Feature{
        &state_map_feature,
        &state_free_feature,
    };
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        without_make_features[0..].ptr,
    ) != .no_feature) return error.MissingMakePathAccepted;
    var misaligned_free_feature = core.lv2.Feature{
        .URI = core.lv2.state_free_path_uri,
        .data = @ptrFromInt(1),
    };
    const misaligned_features = [_:null]?*const core.lv2.Feature{
        &state_map_feature,
        &misaligned_free_feature,
    };
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        misaligned_features[0..].ptr,
    ) != .no_feature) return error.MisalignedPathFeatureAccepted;
    state_host.fail_path_mapping = true;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .unknown) return error.PathMappingFailureAccepted;
    if (state_host.parameter_present or state_host.component_present)
        return error.PathMappingFailureStoredPartialState;
    state_host.fail_path_mapping = false;
    state_host.abstract_path_count = 0;
    state_host.make_path_count = 0;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (!state_host.parameter_present or
        !state_host.component_present or
        state_host.component_size != 55 or
        state_host.abstract_path_count != 2 or
        state_host.make_path_count != 1 or
        state_host.free_path_count != 3)
        return error.IncompleteState;

    state_host.component_bytes[1] = 9;
    state_host.component_bytes[2] = 0;
    state_host.component_bytes[3] = 0;
    state_host.component_bytes[4] = 0;
    gain = 0.5;
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    if (state.restore(
        handle,
        StateHost.retrieve,
        &state_host,
        0,
        null,
    ) != .no_feature) return error.MissingRestorePathFeaturesAccepted;
    var before_path_failure = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &before_path_failure,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    state_host.fail_path_mapping = true;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .bad_type) return error.RestorePathMappingFailureAccepted;
    state_host.fail_path_mapping = false;
    var after_path_failure = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &after_path_failure,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        before_path_failure.parameter_bytes[0..before_path_failure.parameter_size],
        after_path_failure.parameter_bytes[0..after_path_failure.parameter_size],
    ) or !std.mem.eql(
        u8,
        before_path_failure.component_bytes[0..before_path_failure.component_size],
        after_path_failure.component_bytes[0..after_path_failure.component_size],
    )) return error.FailedPathRestoreMutatedState;
    state_host.absolute_path_count = 0;
    state_host.free_path_count = 0;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateRestoreFailed;
    if (state_host.absolute_path_count != 2 or
        state_host.free_path_count != 2)
        return error.IncompletePathRestore;
    var restored = StateHost{};
    state_map_path.handle = &restored;
    state_free_path.handle = &restored;
    state_make_path.handle = &restored;
    if (state.save(
        handle,
        StateHost.store,
        &restored,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        state_host.parameter_bytes[0..state_host.parameter_size],
        restored.parameter_bytes[0..restored.parameter_size],
    ) or !std.mem.eql(
        u8,
        state_host.component_bytes[0..state_host.component_size],
        restored.component_bytes[0..restored.component_size],
    )) return error.StateRoundTripMismatch;
    state_map_path.handle = &state_host;
    state_free_path.handle = &state_host;
    state_make_path.handle = &state_host;

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
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    state_host.component_bytes[0] = 0;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .bad_type) return error.MalformedStateAccepted;
    var after_failure = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &after_failure,
        0,
        state_features[0..].ptr,
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

    state_host.component_bytes[0] = 0xa5;
    state_host.component_bytes[state_host.component_size] = 0;
    state_host.component_size += 1;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .bad_type) return error.TrailingStateAccepted;
}
