const std = @import("std");
const common = @import("common.zig");
const plugin_api = @import("plugin.zig");
const process_api = @import("process.zig");
const units_api = @import("units.zig");

pub const metadata = @import("lv2_metadata.zig");
pub const ui = @import("lv2_ui.zig");

pub const core_uri = "http://lv2plug.in/ns/lv2core";
pub const hard_rt_capable_uri =
    "http://lv2plug.in/ns/lv2core#hardRTCapable";
pub const urid_map_uri =
    "http://lv2plug.in/ns/ext/urid#map";
pub const urid_unmap_uri =
    "http://lv2plug.in/ns/ext/urid#unmap";
pub const options_options_uri =
    "http://lv2plug.in/ns/ext/options#options";
pub const options_interface_uri =
    "http://lv2plug.in/ns/ext/options#interface";
pub const state_interface_uri =
    "http://lv2plug.in/ns/ext/state#interface";
pub const state_map_path_uri =
    "http://lv2plug.in/ns/ext/state#mapPath";
pub const state_make_path_uri =
    "http://lv2plug.in/ns/ext/state#makePath";
pub const state_free_path_uri =
    "http://lv2plug.in/ns/ext/state#freePath";
pub const worker_interface_uri =
    "http://lv2plug.in/ns/ext/worker#interface";
pub const worker_schedule_uri =
    "http://lv2plug.in/ns/ext/worker#schedule";
pub const programs_interface_uri =
    "http://kxstudio.sf.net/ns/lv2ext/programs#Interface";
pub const atom_chunk_uri =
    "http://lv2plug.in/ns/ext/atom#Chunk";
pub const atom_sequence_uri =
    "http://lv2plug.in/ns/ext/atom#Sequence";
pub const atom_frame_time_uri =
    "http://lv2plug.in/ns/ext/atom#frameTime";
pub const atom_blank_uri =
    "http://lv2plug.in/ns/ext/atom#Blank";
pub const atom_object_uri =
    "http://lv2plug.in/ns/ext/atom#Object";
pub const atom_bool_uri =
    "http://lv2plug.in/ns/ext/atom#Bool";
pub const atom_float_uri =
    "http://lv2plug.in/ns/ext/atom#Float";
pub const atom_double_uri =
    "http://lv2plug.in/ns/ext/atom#Double";
pub const atom_int_uri =
    "http://lv2plug.in/ns/ext/atom#Int";
pub const atom_long_uri =
    "http://lv2plug.in/ns/ext/atom#Long";
pub const atom_path_uri =
    "http://lv2plug.in/ns/ext/atom#Path";
pub const atom_string_uri =
    "http://lv2plug.in/ns/ext/atom#String";
pub const atom_uri_uri =
    "http://lv2plug.in/ns/ext/atom#URI";
pub const atom_urid_uri =
    "http://lv2plug.in/ns/ext/atom#URID";
pub const midi_event_uri =
    "http://lv2plug.in/ns/ext/midi#MidiEvent";
pub const patch_message_uri =
    "http://lv2plug.in/ns/ext/patch#Message";
pub const patch_get_uri =
    "http://lv2plug.in/ns/ext/patch#Get";
pub const patch_set_uri =
    "http://lv2plug.in/ns/ext/patch#Set";
pub const patch_ack_uri =
    "http://lv2plug.in/ns/ext/patch#Ack";
pub const patch_error_uri =
    "http://lv2plug.in/ns/ext/patch#Error";
pub const patch_put_uri =
    "http://lv2plug.in/ns/ext/patch#Put";
pub const patch_insert_uri =
    "http://lv2plug.in/ns/ext/patch#Insert";
pub const patch_patch_uri =
    "http://lv2plug.in/ns/ext/patch#Patch";
pub const patch_delete_uri =
    "http://lv2plug.in/ns/ext/patch#Delete";
pub const patch_copy_uri =
    "http://lv2plug.in/ns/ext/patch#Copy";
pub const patch_move_uri =
    "http://lv2plug.in/ns/ext/patch#Move";
pub const patch_add_uri =
    "http://lv2plug.in/ns/ext/patch#add";
pub const patch_remove_uri =
    "http://lv2plug.in/ns/ext/patch#remove";
pub const patch_body_uri =
    "http://lv2plug.in/ns/ext/patch#body";
pub const patch_context_uri =
    "http://lv2plug.in/ns/ext/patch#context";
pub const patch_destination_uri =
    "http://lv2plug.in/ns/ext/patch#destination";
pub const patch_property_uri =
    "http://lv2plug.in/ns/ext/patch#property";
pub const patch_sequence_number_uri =
    "http://lv2plug.in/ns/ext/patch#sequenceNumber";
pub const patch_subject_uri =
    "http://lv2plug.in/ns/ext/patch#subject";
pub const patch_value_uri =
    "http://lv2plug.in/ns/ext/patch#value";
pub const time_position_uri =
    "http://lv2plug.in/ns/ext/time#Position";
pub const time_bar_uri =
    "http://lv2plug.in/ns/ext/time#bar";
pub const time_bar_beat_uri =
    "http://lv2plug.in/ns/ext/time#barBeat";
pub const time_beat_uri =
    "http://lv2plug.in/ns/ext/time#beat";
pub const time_beat_unit_uri =
    "http://lv2plug.in/ns/ext/time#beatUnit";
pub const time_beats_per_bar_uri =
    "http://lv2plug.in/ns/ext/time#beatsPerBar";
pub const time_beats_per_minute_uri =
    "http://lv2plug.in/ns/ext/time#beatsPerMinute";
pub const time_frame_uri =
    "http://lv2plug.in/ns/ext/time#frame";
pub const time_frames_per_second_uri =
    "http://lv2plug.in/ns/ext/time#framesPerSecond";
pub const time_speed_uri =
    "http://lv2plug.in/ns/ext/time#speed";
pub const buffer_minimum_block_length_uri =
    "http://lv2plug.in/ns/ext/buf-size#minBlockLength";
pub const buffer_maximum_block_length_uri =
    "http://lv2plug.in/ns/ext/buf-size#maxBlockLength";
pub const buffer_nominal_block_length_uri =
    "http://lv2plug.in/ns/ext/buf-size#nominalBlockLength";
pub const buffer_sequence_size_uri =
    "http://lv2plug.in/ns/ext/buf-size#sequenceSize";
pub const Handle = ?*anyopaque;

pub const Feature = extern struct {
    URI: [*:0]const u8,
    data: ?*anyopaque,
};

pub const Urid = u32;

pub const UridMap = extern struct {
    handle: ?*anyopaque,
    map: *const fn (
        handle: ?*anyopaque,
        URI: [*:0]const u8,
    ) callconv(.c) Urid,
};

pub const UridUnmap = extern struct {
    handle: ?*anyopaque,
    unmap: *const fn (
        handle: ?*anyopaque,
        urid: Urid,
    ) callconv(.c) ?[*:0]const u8,
};

pub const Atom = extern struct {
    size: u32,
    type: Urid,
};

pub const AtomEventTime = extern union {
    frames: i64,
    beats: f64,
};

pub const AtomEvent = extern struct {
    time: AtomEventTime,
    body: Atom,
};

pub const AtomSequenceBody = extern struct {
    unit: Urid,
    pad: u32,
};

pub const AtomSequence = extern struct {
    atom: Atom,
    body: AtomSequenceBody,
};

pub const AtomObjectBody = extern struct {
    id: Urid,
    otype: Urid,
};

pub const AtomObject = extern struct {
    atom: Atom,
    body: AtomObjectBody,
};

pub const AtomPropertyBody = extern struct {
    key: Urid,
    context: Urid,
    value: Atom,
};

pub const AtomBool = extern struct {
    atom: Atom,
    body: i32,
};

pub const AtomFloat = extern struct {
    atom: Atom,
    body: f32,
};

pub const AtomDouble = extern struct {
    atom: Atom,
    body: f64,
};

pub const AtomInt = extern struct {
    atom: Atom,
    body: i32,
};

pub const AtomLong = extern struct {
    atom: Atom,
    body: i64,
};

pub const AtomUrid = extern struct {
    atom: Atom,
    body: Urid,
};

pub const PatchValueKind = enum {
    boolean,
    int,
    long,
    float,
    double,
    string,
    path,
    uri,
    urid,
};

/// String-like values borrow storage only for the enclosing patch callback.
pub const PatchValue = union(PatchValueKind) {
    boolean: bool,
    int: i32,
    long: i64,
    float: f32,
    double: f64,
    string: []const u8,
    path: []const u8,
    uri: []const u8,
    urid: Urid,
};

pub const PatchProperty = struct {
    uri: [:0]const u8,
    value_kind: PatchValueKind,
    readable: bool = false,
    writable: bool = false,
};

/// Body storage is valid only while the graph request callback is running.
pub const PatchAtomValue = struct {
    atom_type: Urid,
    body: []const u8,
};

pub const maximum_patch_graph_subject_count = 16;

pub const PatchGraphOperation = union(enum) {
    put: struct {
        subject: Urid,
        body: PatchAtomValue,
    },
    insert: struct {
        subject: Urid,
        body: PatchAtomValue,
    },
    patch: struct {
        subject: Urid,
        add: PatchAtomValue,
        remove: PatchAtomValue,
    },
    delete: struct {
        subjects: []const Urid,
    },
    copy: struct {
        subjects: []const Urid,
        destination: Urid,
    },
    move: struct {
        subject: Urid,
        destination: Urid,
    },
};

/// Subject and Atom body slices are valid only during the callback.
pub const PatchGraphRequest = struct {
    operation: PatchGraphOperation,
    context: ?Urid = null,
    sequence_number: ?i32 = null,
};

pub const OptionsContext = enum(c_int) {
    instance = 0,
    resource = 1,
    blank = 2,
    port = 3,
};

pub const OptionsOption = extern struct {
    context: c_int = @intFromEnum(OptionsContext.instance),
    subject: u32 = 0,
    key: Urid = 0,
    size: u32 = 0,
    type: Urid = 0,
    value: ?*const anyopaque = null,
};

pub const OptionsStatus = u32;
pub const options_status_success: OptionsStatus = 0;
pub const options_status_unknown: OptionsStatus = 1 << 0;
pub const options_status_bad_subject: OptionsStatus = 1 << 1;
pub const options_status_bad_key: OptionsStatus = 1 << 2;
pub const options_status_bad_value: OptionsStatus = 1 << 3;

pub const OptionsInterface = extern struct {
    get: *const fn (
        instance: Handle,
        options: ?[*]OptionsOption,
    ) callconv(.c) OptionsStatus,
    set: *const fn (
        instance: Handle,
        options: ?[*]const OptionsOption,
    ) callconv(.c) OptionsStatus,
};

pub const WorkerStatus = enum(c_int) {
    success = 0,
    unknown = 1,
    no_space = 2,
};

pub const WorkerRespondHandle = ?*anyopaque;
pub const WorkerRespondFunction = *const fn (
    handle: WorkerRespondHandle,
    size: u32,
    data: ?*const anyopaque,
) callconv(.c) WorkerStatus;

pub const WorkerSchedule = extern struct {
    handle: ?*anyopaque,
    schedule_work: *const fn (
        handle: ?*anyopaque,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) WorkerStatus,
};

pub const WorkerInterface = extern struct {
    work: *const fn (
        instance: Handle,
        respond: WorkerRespondFunction,
        handle: WorkerRespondHandle,
        size: u32,
        data: ?*const anyopaque,
    ) callconv(.c) WorkerStatus,
    work_response: *const fn (
        instance: Handle,
        size: u32,
        body: ?*const anyopaque,
    ) callconv(.c) WorkerStatus,
    end_run: ?*const fn (
        instance: Handle,
    ) callconv(.c) WorkerStatus,
};

pub const ProgramDescriptor = extern struct {
    bank: u32,
    program: u32,
    name: [*:0]const u8,
};

pub const ProgramsInterface = extern struct {
    get_program: *const fn (
        instance: Handle,
        index: u32,
    ) callconv(.c) ?*const ProgramDescriptor,
    select_program: *const fn (
        instance: Handle,
        bank: u32,
        program: u32,
    ) callconv(.c) void,
};

pub const WorkerScheduleSink = struct {
    context: *anyopaque,
    maximum_size: usize,
    schedule_work: *const fn (
        context: *anyopaque,
        data: []const u8,
    ) WorkerStatus,

    pub fn schedule(
        self: *WorkerScheduleSink,
        data: []const u8,
    ) WorkerStatus {
        if (data.len > self.maximum_size) return .no_space;
        return self.schedule_work(self.context, data);
    }
};

pub const WorkerResponseSink = struct {
    context: *anyopaque,
    maximum_size: usize,
    respond_work: *const fn (
        context: *anyopaque,
        data: []const u8,
    ) WorkerStatus,

    /// Use only during the worker callback that supplied this sink
    pub fn respond(
        self: *WorkerResponseSink,
        data: []const u8,
    ) WorkerStatus {
        if (data.len > self.maximum_size) return .no_space;
        return self.respond_work(self.context, data);
    }
};

pub const StateHandle = ?*anyopaque;

pub const StateStatus = enum(c_int) {
    success = 0,
    unknown = 1,
    bad_type = 2,
    bad_flags = 3,
    no_feature = 4,
    no_property = 5,
    no_space = 6,
};

pub const state_is_pod: u32 = 1 << 0;
pub const state_is_portable: u32 = 1 << 1;
pub const state_is_native: u32 = 1 << 2;

pub const StateStoreFunction = *const fn (
    handle: StateHandle,
    key: Urid,
    value: *const anyopaque,
    size: usize,
    value_type: Urid,
    flags: u32,
) callconv(.c) StateStatus;

pub const StateRetrieveFunction = *const fn (
    handle: StateHandle,
    key: Urid,
    size: *usize,
    value_type: *Urid,
    flags: *u32,
) callconv(.c) ?*const anyopaque;

pub const StateInterface = extern struct {
    save: *const fn (
        instance: Handle,
        store: StateStoreFunction,
        handle: StateHandle,
        flags: u32,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) StateStatus,
    restore: *const fn (
        instance: Handle,
        retrieve: StateRetrieveFunction,
        handle: StateHandle,
        flags: u32,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) StateStatus,
};

pub const StateMapPath = extern struct {
    handle: StateHandle,
    abstract_path: *const fn (
        handle: StateHandle,
        absolute_path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8,
    absolute_path: *const fn (
        handle: StateHandle,
        abstract_path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8,
};

pub const StateMakePath = extern struct {
    handle: StateHandle,
    path: *const fn (
        handle: StateHandle,
        path: [*:0]const u8,
    ) callconv(.c) ?[*:0]u8,
};

pub const StateFreePath = extern struct {
    handle: StateHandle,
    free_path: *const fn (
        handle: StateHandle,
        path: [*:0]u8,
    ) callconv(.c) void,
};

/// Host-owned path returned by an LV2 State feature. Call `deinit` once
/// before the enclosing state callback returns.
pub const OwnedStatePath = struct {
    pointer: [*:0]u8,
    free_path: *const StateFreePath,

    pub fn bytes(self: OwnedStatePath) []const u8 {
        return std.mem.span(self.pointer);
    }

    pub fn deinit(self: *OwnedStatePath) void {
        self.free_path.free_path(
            self.free_path.handle,
            self.pointer,
        );
        self.* = undefined;
    }
};

/// Valid only during the State save or restore callback that supplied it.
pub const StatePathFeatures = struct {
    map_path: *const StateMapPath,
    make_path: ?*const StateMakePath,
    free_path: *const StateFreePath,

    pub fn mapAbsolute(
        self: StatePathFeatures,
        path: [:0]const u8,
    ) !OwnedStatePath {
        if (path.len == 0) return error.InvalidStatePath;
        const mapped = self.map_path.abstract_path(
            self.map_path.handle,
            path.ptr,
        ) orelse return error.StatePathMappingFailed;
        return self.owned(mapped);
    }

    pub fn resolveAbstract(
        self: StatePathFeatures,
        path: [:0]const u8,
    ) !OwnedStatePath {
        if (path.len == 0) return error.InvalidStatePath;
        const resolved = self.map_path.absolute_path(
            self.map_path.handle,
            path.ptr,
        ) orelse return error.StatePathMappingFailed;
        return self.owned(resolved);
    }

    pub fn makePath(
        self: StatePathFeatures,
        path: [:0]const u8,
    ) !OwnedStatePath {
        if (path.len == 0) return error.InvalidStatePath;
        const make_path = self.make_path orelse
            return error.StateMakePathUnavailable;
        const created = make_path.path(
            make_path.handle,
            path.ptr,
        ) orelse return error.StatePathMappingFailed;
        return self.owned(created);
    }

    fn owned(
        self: StatePathFeatures,
        path: [*:0]u8,
    ) !OwnedStatePath {
        if (std.mem.span(path).len == 0) {
            self.free_path.free_path(
                self.free_path.handle,
                path,
            );
            return error.InvalidStatePath;
        }
        return .{
            .pointer = path,
            .free_path = self.free_path,
        };
    }
};

pub const Descriptor = extern struct {
    URI: [*:0]const u8,
    instantiate: *const fn (
        descriptor: ?*const Descriptor,
        sample_rate: f64,
        bundle_path: ?[*:0]const u8,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) Handle,
    connect_port: *const fn (
        instance: Handle,
        port: u32,
        data_location: ?*anyopaque,
    ) callconv(.c) void,
    activate: ?*const fn (instance: Handle) callconv(.c) void,
    run: *const fn (
        instance: Handle,
        sample_count: u32,
    ) callconv(.c) void,
    deactivate: ?*const fn (instance: Handle) callconv(.c) void,
    cleanup: *const fn (instance: Handle) callconv(.c) void,
    extension_data: *const fn (
        URI: ?[*:0]const u8,
    ) callconv(.c) ?*const anyopaque,
};

pub const RunStatus = enum {
    ready,
    succeeded,
    inactive,
    block_too_large,
    unconnected_port,
    invalid_control,
    invalid_context,
    processing_failed,
    activation_failed,
    deactivation_failed,
};

pub const PortKind = enum {
    audio_input,
    audio_output,
    event_input,
    event_output,
    control_input,
    freewheeling_input,
    latency_output,
};

pub fn CoreAdapter(
    comptime Plugin: type,
    comptime plugin_uri: [:0]const u8,
    comptime maximum_block_size: usize,
) type {
    return CoreAdapterWithParameters(
        Plugin,
        plugin_uri,
        maximum_block_size,
        .{},
    );
}

fn totalProgramCount(comptime config: units_api.Config) usize {
    var count: usize = 0;
    for (config.program_lists) |list| {
        count = std.math.add(
            usize,
            count,
            list.programs.len,
        ) catch @compileError("LV2 program count overflows usize");
    }
    return count;
}

fn maximumProgramNameLength(comptime config: units_api.Config) usize {
    var maximum: usize = 0;
    for (config.program_lists) |list| {
        for (list.programs) |program| {
            maximum = @max(maximum, program.name.len);
        }
    }
    return maximum;
}

pub fn CoreAdapterWithParameters(
    comptime Plugin: type,
    comptime plugin_uri: [:0]const u8,
    comptime maximum_block_size: usize,
    comptime initial_parameters: Plugin.Params,
) type {
    if (!validPluginUri(plugin_uri))
        @compileError("LV2 plugin URI must be an absolute ASCII URI");
    if (maximum_block_size == 0 or
        maximum_block_size > std.math.maxInt(i32))
        @compileError("LV2 maximum block size must fit Atom Int");

    const Runtime = plugin_api.ProcessorRuntime(Plugin);
    const Spec = plugin_api.PluginSpec(Plugin);
    const program_count = totalProgramCount(Spec.unit_config);
    const maximum_program_name_length =
        maximumProgramNameLength(Spec.unit_config);
    const has_programs = program_count != 0;
    if (program_count > std.math.maxInt(u32))
        @compileError("LV2 program count exceeds the Programs ABI");
    for (Spec.unit_config.program_lists) |list| {
        if (list.programs.len > std.math.maxInt(u32))
            @compileError("LV2 program count exceeds the Programs ABI");
        if (list.programs.len != 0 and list.id < 0)
            @compileError(
                "LV2 program list ids must be nonnegative bank numbers",
            );
    }
    const has_freewheeling =
        @hasDecl(Plugin, "lv2_freewheeling") and
        Plugin.lv2_freewheeling;
    if (has_freewheeling and !Spec.allow_dynamic_process_mode)
        @compileError(
            "LV2 freewheeling requires allow_dynamic_process_mode",
        );
    const requires_lv2_urid_unmap =
        @hasDecl(Plugin, "lv2_urid_unmap_required") and
        Plugin.lv2_urid_unmap_required;
    const declares_lv2_urid_unmap_binding = @hasDecl(
        Plugin,
        "bindLv2UridUnmap",
    );
    if (requires_lv2_urid_unmap !=
        declares_lv2_urid_unmap_binding)
        @compileError(
            "LV2 URID unmap support requires lv2_urid_unmap_required and bindLv2UridUnmap",
        );
    const declares_component_state_size = @hasDecl(
        Plugin,
        "component_state_maximum_encoded_size",
    );
    const declares_component_state_reader = @hasDecl(
        Plugin,
        "readComponentState",
    );
    const declares_component_state_writer = @hasDecl(
        Plugin,
        "writeComponentState",
    );
    const has_component_state =
        declares_component_state_size and
        declares_component_state_reader and
        declares_component_state_writer;
    if ((declares_component_state_size or
        declares_component_state_reader or
        declares_component_state_writer) and
        !has_component_state)
        @compileError(
            "LV2 component state requires maximum size, read, and write declarations",
        );
    const declares_lv2_component_state_reader = @hasDecl(
        Plugin,
        "readLv2ComponentState",
    );
    const declares_lv2_component_state_writer = @hasDecl(
        Plugin,
        "writeLv2ComponentState",
    );
    const has_lv2_component_state_paths =
        declares_lv2_component_state_reader and
        declares_lv2_component_state_writer;
    if ((declares_lv2_component_state_reader or
        declares_lv2_component_state_writer) and
        (!has_component_state or
            !has_lv2_component_state_paths))
        @compileError(
            "LV2 portable component state requires generic component state and both LV2 path-aware hooks",
        );
    const requires_lv2_state_make_path =
        @hasDecl(Plugin, "lv2_state_requires_make_path") and
        Plugin.lv2_state_requires_make_path;
    if (requires_lv2_state_make_path and
        !has_lv2_component_state_paths)
        @compileError(
            "LV2 makePath requires path-aware component state hooks",
        );
    const component_state_maximum_encoded_size =
        if (has_component_state)
            Plugin.component_state_maximum_encoded_size
        else
            0;
    if (has_component_state and
        (component_state_maximum_encoded_size == 0 or
            component_state_maximum_encoded_size > 64 * 1024))
        @compileError(
            "LV2 component state maximum size must be 1 through 64 KiB",
        );
    const patch_properties = if (@hasDecl(
        Plugin,
        "lv2_patch_properties",
    ))
        Plugin.lv2_patch_properties
    else
        &[_]PatchProperty{};
    if (patch_properties.len > 256)
        @compileError("LV2 Patch property count exceeds 256");
    const patch_access = comptime blk: {
        var readable = false;
        var writable = false;
        for (patch_properties, 0..) |property, property_index| {
            if (!validPluginUri(property.uri))
                @compileError(
                    "LV2 Patch property URI must be absolute ASCII",
                );
            if (!property.readable and !property.writable)
                @compileError(
                    "LV2 Patch properties must be readable or writable",
                );
            readable = readable or property.readable;
            writable = writable or property.writable;
            for (patch_properties[0..property_index]) |previous| {
                if (std.mem.eql(u8, previous.uri, property.uri))
                    @compileError(
                        "LV2 Patch property URIs must be unique",
                    );
            }
        }
        break :blk .{ .readable = readable, .writable = writable };
    };
    const has_readable_patch_properties = patch_access.readable;
    const has_writable_patch_properties = patch_access.writable;
    const has_patch_properties = patch_properties.len != 0;
    const has_patch_graph_operations = if (@hasDecl(
        Plugin,
        "lv2_patch_graph_operations",
    ))
        Plugin.lv2_patch_graph_operations
    else
        false;
    const declares_patch_graph_handler = @hasDecl(
        Plugin,
        "applyLv2PatchGraphRequest",
    );
    if (has_patch_graph_operations != declares_patch_graph_handler)
        @compileError(
            "LV2 Patch graph operations require lv2_patch_graph_operations and applyLv2PatchGraphRequest",
        );
    const has_patch_messages =
        has_patch_properties or has_patch_graph_operations;
    const declares_patch_reader = @hasDecl(
        Plugin,
        "readLv2PatchProperty",
    );
    const declares_patch_writer = @hasDecl(
        Plugin,
        "writeLv2PatchProperty",
    );
    if (has_readable_patch_properties != declares_patch_reader)
        @compileError(
            "Readable LV2 Patch properties require readLv2PatchProperty",
        );
    if (has_writable_patch_properties != declares_patch_writer)
        @compileError(
            "Writable LV2 Patch properties require writeLv2PatchProperty",
        );
    const needs_patch_responses =
        has_readable_patch_properties or has_patch_graph_operations;
    const patch_response_capacity = if (needs_patch_responses and
        @hasDecl(Plugin, "lv2_patch_response_capacity"))
        Plugin.lv2_patch_response_capacity
    else
        0;
    if (needs_patch_responses and
        (patch_response_capacity < 64 or
            patch_response_capacity > 64 * 1024))
        @compileError(
            "LV2 Patch responses require a 64 byte through 64 KiB response capacity",
        );
    const declares_worker_request_size = @hasDecl(
        Plugin,
        "lv2_worker_maximum_request_size",
    );
    const declares_worker_response_size = @hasDecl(
        Plugin,
        "lv2_worker_maximum_response_size",
    );
    const declares_worker_binding = @hasDecl(
        Plugin,
        "bindLv2WorkerSchedule",
    );
    const declares_worker_work = @hasDecl(
        Plugin,
        "runLv2Worker",
    );
    const declares_worker_response = @hasDecl(
        Plugin,
        "applyLv2WorkerResponse",
    );
    const has_worker =
        declares_worker_request_size and
        declares_worker_response_size and
        declares_worker_binding and
        declares_worker_work and
        declares_worker_response;
    if ((declares_worker_request_size or
        declares_worker_response_size or
        declares_worker_binding or
        declares_worker_work or
        declares_worker_response) and
        !has_worker)
        @compileError(
            "LV2 worker support requires request and response sizes, binding, work, and response declarations",
        );
    const worker_maximum_request_size =
        if (has_worker)
            Plugin.lv2_worker_maximum_request_size
        else
            0;
    const worker_maximum_response_size =
        if (has_worker)
            Plugin.lv2_worker_maximum_response_size
        else
            0;
    if (has_worker and
        (worker_maximum_request_size == 0 or
            worker_maximum_request_size > 64 * 1024 or
            worker_maximum_response_size == 0 or
            worker_maximum_response_size > 64 * 1024))
        @compileError(
            "LV2 worker request and response sizes must be 1 through 64 KiB",
        );
    if (!Spec.has_process32_hook)
        @compileError("LV2 core audio ports require f32 processing");
    if (Spec.dynamic_audio_bus_topology != null)
        @compileError("LV2 core ports require static audio buses");
    const parameter_count = Spec.ParameterSet.count;
    const main_input_channel_count: usize =
        Spec.audio_input_layout.channelCount();
    const main_output_channel_count: usize =
        Spec.audio_output_layout.channelCount();
    const auxiliary_input_channel_count =
        totalLayoutChannels(Spec.audio_auxiliary_input_layouts);
    const auxiliary_output_channel_count =
        totalLayoutChannels(Spec.audio_auxiliary_output_layouts);
    const input_channel_count =
        main_input_channel_count + auxiliary_input_channel_count;
    const output_channel_count =
        main_output_channel_count + auxiliary_output_channel_count;
    const has_event_input = Spec.event_input;
    const has_event_output = Spec.event_output;
    if (has_patch_messages and !has_event_input)
        @compileError("LV2 Patch messages require an event input");
    if (needs_patch_responses and !has_event_output)
        @compileError("LV2 Patch responses require an event output");
    const event_port_count =
        @as(usize, @intFromBool(has_event_input)) +
        @as(usize, @intFromBool(has_event_output));
    const maximum_event_count = 256;
    if (input_channel_count > process_api.max_audio_channels or
        output_channel_count > process_api.max_audio_channels)
        @compileError("LV2 audio channel count exceeds ProcessContext capacity");

    return struct {
        const Self = @This();

        pub const audio_input_port_start = 0;
        pub const audio_output_port_start =
            audio_input_port_start + input_channel_count;
        pub const event_input_port: ?usize = if (has_event_input)
            audio_output_port_start + output_channel_count
        else
            null;
        pub const event_output_port: ?usize = if (has_event_output)
            audio_output_port_start +
                output_channel_count +
                @intFromBool(has_event_input)
        else
            null;
        pub const control_input_port_start =
            audio_output_port_start +
            output_channel_count +
            event_port_count;
        pub const freewheeling_input_port: ?usize =
            if (has_freewheeling)
                control_input_port_start + parameter_count
            else
                null;
        pub const latency_output_port =
            control_input_port_start +
            parameter_count +
            @intFromBool(has_freewheeling);
        pub const port_count = latency_output_port + 1;
        pub const maximum_frames = maximum_block_size;
        pub const worker_enabled = has_worker;
        pub const programs_enabled = has_programs;
        pub const portable_state_paths_enabled =
            has_lv2_component_state_paths;
        pub const state_make_path_required =
            requires_lv2_state_make_path;
        pub const urid_unmap_required =
            requires_lv2_urid_unmap;
        pub const patch_enabled = has_patch_messages;
        pub const patch_readable = has_readable_patch_properties;
        pub const patch_writable = has_writable_patch_properties;
        pub const input_channels = input_channel_count;
        pub const output_channels = output_channel_count;
        pub const parameters = parameter_count;
        pub const auxiliary_input_bus_channel_counts =
            layoutChannelCounts(Spec.audio_auxiliary_input_layouts);
        pub const auxiliary_output_bus_channel_counts =
            layoutChannelCounts(Spec.audio_auxiliary_output_layouts);

        runtime: Runtime,
        sample_rate: f64,
        ports: [port_count]?*anyopaque = @splat(null),
        state_key: Urid = 0,
        component_state_key: Urid = 0,
        state_type: Urid = 0,
        sequence_type: Urid = 0,
        frame_time_type: Urid = 0,
        midi_event_type: Urid = 0,
        atom_blank_type: Urid = 0,
        atom_object_type: Urid = 0,
        atom_bool_type: Urid = 0,
        atom_float_type: Urid = 0,
        atom_double_type: Urid = 0,
        atom_int_type: Urid = 0,
        atom_long_type: Urid = 0,
        atom_path_type: Urid = 0,
        atom_string_type: Urid = 0,
        atom_uri_type: Urid = 0,
        atom_urid_type: Urid = 0,
        patch_get_type: Urid = 0,
        patch_set_type: Urid = 0,
        patch_ack_type: Urid = 0,
        patch_error_type: Urid = 0,
        patch_put_type: Urid = 0,
        patch_insert_type: Urid = 0,
        patch_patch_type: Urid = 0,
        patch_delete_type: Urid = 0,
        patch_copy_type: Urid = 0,
        patch_move_type: Urid = 0,
        patch_add_key: Urid = 0,
        patch_remove_key: Urid = 0,
        patch_body_key: Urid = 0,
        patch_context_key: Urid = 0,
        patch_destination_key: Urid = 0,
        patch_property_key: Urid = 0,
        patch_sequence_number_key: Urid = 0,
        patch_subject_key: Urid = 0,
        patch_value_key: Urid = 0,
        patch_subject: Urid = 0,
        patch_property_urids: [patch_properties.len]Urid =
            @splat(0),
        time_position_type: Urid = 0,
        time_bar_key: Urid = 0,
        time_bar_beat_key: Urid = 0,
        time_beat_key: Urid = 0,
        time_beat_unit_key: Urid = 0,
        time_beats_per_bar_key: Urid = 0,
        time_beats_per_minute_key: Urid = 0,
        time_frame_key: Urid = 0,
        time_frames_per_second_key: Urid = 0,
        time_speed_key: Urid = 0,
        minimum_block_length_key: Urid = 0,
        maximum_block_length_key: Urid = 0,
        nominal_block_length_key: Urid = 0,
        sequence_size_key: Urid = 0,
        configured_minimum_frames: i32 = 0,
        configured_maximum_frames: usize = maximum_block_size,
        configured_maximum_value: i32 = @intCast(maximum_block_size),
        configured_nominal_frames: i32 = @intCast(maximum_block_size),
        configured_sequence_size_value: i32 = 0,
        sequence_size_configured: bool = false,
        worker_schedule: ?*const WorkerSchedule = null,
        worker_schedule_sink: WorkerScheduleSink = undefined,
        inside_run: bool = false,
        transport: ?process_api.Transport = null,
        transport_speed: f64 = 0.0,
        beats_per_bar: ?f64 = null,
        beat_unit: ?u32 = null,
        bar: ?i64 = null,
        bar_beat: ?f64 = null,
        beat: ?f64 = null,
        last_run_status: RunStatus = .ready,
        program_descriptor: ProgramDescriptor = undefined,
        program_name: [maximum_program_name_length + 1]u8 = @splat(0),
        program_overrides: [parameter_count]?f64 = @splat(null),
        program_control_baselines: [parameter_count]?f32 = @splat(null),

        pub const descriptor = Descriptor{
            .URI = plugin_uri.ptr,
            .instantiate = instantiate,
            .connect_port = connectPort,
            .activate = activate,
            .run = run,
            .deactivate = deactivate,
            .cleanup = cleanup,
            .extension_data = extensionData,
        };
        pub const state_interface = StateInterface{
            .save = saveState,
            .restore = restoreState,
        };
        pub const options_interface = OptionsInterface{
            .get = getOptions,
            .set = setOptions,
        };
        pub const worker_interface = WorkerInterface{
            .work = runWorker,
            .work_response = applyWorkerResponse,
            .end_run = if (has_worker and
                @hasDecl(Plugin, "endLv2WorkerRun"))
                endWorkerRun
            else
                null,
        };
        pub const programs_interface = ProgramsInterface{
            .get_program = getProgram,
            .select_program = selectProgram,
        };

        pub fn descriptorAt(index: u32) ?*const Descriptor {
            return if (index == 0) &descriptor else null;
        }

        pub fn portKind(index: usize) ?PortKind {
            if (index < audio_output_port_start)
                return .audio_input;
            if (index < control_input_port_start)
                return if (event_input_port != null and
                    index == event_input_port.?)
                    .event_input
                else if (event_output_port != null and
                    index == event_output_port.?)
                    .event_output
                else
                    .audio_output;
            if (index < control_input_port_start + parameter_count)
                return .control_input;
            if (freewheeling_input_port != null and
                index == freewheeling_input_port.?)
                return .freewheeling_input;
            if (index == latency_output_port)
                return .latency_output;
            return null;
        }

        pub fn controlPort(parameter_index: usize) ?usize {
            if (parameter_index >= parameter_count) return null;
            return control_input_port_start + parameter_index;
        }

        pub fn instanceFromHandle(instance: Handle) ?*Self {
            const raw = instance orelse return null;
            if (@intFromPtr(raw) % @alignOf(Self) != 0) return null;
            return @ptrCast(@alignCast(raw));
        }

        pub fn configuredMaximumFrames(self: *const Self) usize {
            return self.configured_maximum_frames;
        }

        pub fn configuredMinimumFrames(self: *const Self) usize {
            return @intCast(self.configured_minimum_frames);
        }

        pub fn configuredNominalFrames(self: *const Self) usize {
            return @intCast(self.configured_nominal_frames);
        }

        pub fn configuredSequenceSize(self: *const Self) ?usize {
            if (!self.sequence_size_configured) return null;
            return @intCast(self.configured_sequence_size_value);
        }

        fn instantiate(
            raw_descriptor: ?*const Descriptor,
            sample_rate: f64,
            raw_bundle_path: ?[*:0]const u8,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) Handle {
            _ = raw_descriptor orelse return null;
            _ = raw_bundle_path orelse return null;
            if (!common.isPositiveFinite(sample_rate)) return null;
            const allocator = std.heap.page_allocator;
            const self = allocator.create(Self) catch return null;
            self.* = .{
                .runtime = Runtime.init(
                    allocator,
                    initial_parameters,
                ) catch {
                    allocator.destroy(self);
                    return null;
                },
                .sample_rate = sample_rate,
            };
            if (comptime requires_lv2_urid_unmap) {
                const unmap = featureStruct(
                    UridUnmap,
                    features,
                    urid_unmap_uri,
                ) orelse {
                    self.runtime.deinit();
                    allocator.destroy(self);
                    return null;
                };
                self.runtime.instance.plugin.bindLv2UridUnmap(unmap);
            }
            if (comptime has_worker) {
                if (featureWithUri(
                    features,
                    worker_schedule_uri,
                )) |feature| {
                    self.worker_schedule = featureValue(
                        WorkerSchedule,
                        feature,
                    ) orelse {
                        self.runtime.deinit();
                        allocator.destroy(self);
                        return null;
                    };
                }
                self.worker_schedule_sink = .{
                    .context = self,
                    .maximum_size = worker_maximum_request_size,
                    .schedule_work = scheduleWorker,
                };
                self.runtime.instance.plugin.bindLv2WorkerSchedule(
                    &self.worker_schedule_sink,
                );
            }
            if (featureWithUri(features, urid_map_uri)) |map_feature| {
                const map = featureValue(
                    UridMap,
                    map_feature,
                ) orelse {
                    self.runtime.deinit();
                    allocator.destroy(self);
                    return null;
                };
                self.state_key = map.map(
                    map.handle,
                    plugin_uri ++ "#parameterState",
                );
                if (comptime has_component_state) {
                    self.component_state_key = map.map(
                        map.handle,
                        plugin_uri ++ "#componentState",
                    );
                }
                self.state_type = map.map(
                    map.handle,
                    atom_chunk_uri,
                );
                self.sequence_type = map.map(
                    map.handle,
                    atom_sequence_uri,
                );
                self.frame_time_type = map.map(
                    map.handle,
                    atom_frame_time_uri,
                );
                self.midi_event_type = map.map(
                    map.handle,
                    midi_event_uri,
                );
                self.atom_blank_type = map.map(map.handle, atom_blank_uri);
                self.atom_object_type = map.map(map.handle, atom_object_uri);
                if (comptime has_patch_messages) {
                    self.atom_bool_type = map.map(
                        map.handle,
                        atom_bool_uri,
                    );
                    self.atom_path_type = map.map(
                        map.handle,
                        atom_path_uri,
                    );
                    self.atom_string_type = map.map(
                        map.handle,
                        atom_string_uri,
                    );
                    self.atom_uri_type = map.map(
                        map.handle,
                        atom_uri_uri,
                    );
                    self.atom_urid_type = map.map(
                        map.handle,
                        atom_urid_uri,
                    );
                    self.patch_get_type = map.map(
                        map.handle,
                        patch_get_uri,
                    );
                    self.patch_set_type = map.map(
                        map.handle,
                        patch_set_uri,
                    );
                    self.patch_ack_type = map.map(
                        map.handle,
                        patch_ack_uri,
                    );
                    self.patch_error_type = map.map(
                        map.handle,
                        patch_error_uri,
                    );
                    self.patch_put_type = map.map(
                        map.handle,
                        patch_put_uri,
                    );
                    self.patch_insert_type = map.map(
                        map.handle,
                        patch_insert_uri,
                    );
                    self.patch_patch_type = map.map(
                        map.handle,
                        patch_patch_uri,
                    );
                    self.patch_delete_type = map.map(
                        map.handle,
                        patch_delete_uri,
                    );
                    self.patch_copy_type = map.map(
                        map.handle,
                        patch_copy_uri,
                    );
                    self.patch_move_type = map.map(
                        map.handle,
                        patch_move_uri,
                    );
                    self.patch_add_key = map.map(
                        map.handle,
                        patch_add_uri,
                    );
                    self.patch_remove_key = map.map(
                        map.handle,
                        patch_remove_uri,
                    );
                    self.patch_body_key = map.map(
                        map.handle,
                        patch_body_uri,
                    );
                    self.patch_context_key = map.map(
                        map.handle,
                        patch_context_uri,
                    );
                    self.patch_destination_key = map.map(
                        map.handle,
                        patch_destination_uri,
                    );
                    self.patch_property_key = map.map(
                        map.handle,
                        patch_property_uri,
                    );
                    self.patch_sequence_number_key = map.map(
                        map.handle,
                        patch_sequence_number_uri,
                    );
                    self.patch_subject_key = map.map(
                        map.handle,
                        patch_subject_uri,
                    );
                    self.patch_value_key = map.map(
                        map.handle,
                        patch_value_uri,
                    );
                    self.patch_subject = map.map(
                        map.handle,
                        plugin_uri,
                    );
                    inline for (patch_properties, 0..) |property, index| {
                        self.patch_property_urids[index] = map.map(
                            map.handle,
                            property.uri,
                        );
                    }
                }
                self.atom_float_type = map.map(map.handle, atom_float_uri);
                self.atom_double_type = map.map(map.handle, atom_double_uri);
                self.atom_int_type = map.map(map.handle, atom_int_uri);
                self.atom_long_type = map.map(map.handle, atom_long_uri);
                self.time_position_type = map.map(
                    map.handle,
                    time_position_uri,
                );
                self.time_bar_key = map.map(map.handle, time_bar_uri);
                self.time_bar_beat_key = map.map(
                    map.handle,
                    time_bar_beat_uri,
                );
                self.time_beat_key = map.map(map.handle, time_beat_uri);
                self.time_beat_unit_key = map.map(
                    map.handle,
                    time_beat_unit_uri,
                );
                self.time_beats_per_bar_key = map.map(
                    map.handle,
                    time_beats_per_bar_uri,
                );
                self.time_beats_per_minute_key = map.map(
                    map.handle,
                    time_beats_per_minute_uri,
                );
                self.time_frame_key = map.map(map.handle, time_frame_uri);
                self.time_frames_per_second_key = map.map(
                    map.handle,
                    time_frames_per_second_uri,
                );
                self.time_speed_key = map.map(map.handle, time_speed_uri);
                self.minimum_block_length_key = map.map(
                    map.handle,
                    buffer_minimum_block_length_uri,
                );
                self.maximum_block_length_key = map.map(
                    map.handle,
                    buffer_maximum_block_length_uri,
                );
                self.nominal_block_length_key = map.map(
                    map.handle,
                    buffer_nominal_block_length_uri,
                );
                if (comptime event_port_count != 0) {
                    self.sequence_size_key = map.map(
                        map.handle,
                        buffer_sequence_size_uri,
                    );
                }
                if (self.state_key == 0 or
                    (has_component_state and
                        self.component_state_key == 0) or
                    self.state_type == 0 or
                    self.sequence_type == 0 or
                    self.frame_time_type == 0 or
                    self.midi_event_type == 0 or
                    self.atom_blank_type == 0 or
                    self.atom_object_type == 0 or
                    (has_patch_messages and
                        (self.atom_bool_type == 0 or
                            self.atom_path_type == 0 or
                            self.atom_string_type == 0 or
                            self.atom_uri_type == 0 or
                            self.atom_urid_type == 0 or
                            self.patch_get_type == 0 or
                            self.patch_set_type == 0 or
                            self.patch_ack_type == 0 or
                            self.patch_error_type == 0 or
                            self.patch_put_type == 0 or
                            self.patch_insert_type == 0 or
                            self.patch_patch_type == 0 or
                            self.patch_delete_type == 0 or
                            self.patch_copy_type == 0 or
                            self.patch_move_type == 0 or
                            self.patch_add_key == 0 or
                            self.patch_remove_key == 0 or
                            self.patch_body_key == 0 or
                            self.patch_context_key == 0 or
                            self.patch_destination_key == 0 or
                            self.patch_property_key == 0 or
                            self.patch_sequence_number_key == 0 or
                            self.patch_subject_key == 0 or
                            self.patch_value_key == 0 or
                            self.patch_subject == 0 or
                            std.mem.indexOfScalar(
                                Urid,
                                &self.patch_property_urids,
                                0,
                            ) != null)) or
                    self.atom_float_type == 0 or
                    self.atom_double_type == 0 or
                    self.atom_int_type == 0 or
                    self.atom_long_type == 0 or
                    self.time_position_type == 0 or
                    self.time_bar_key == 0 or
                    self.time_bar_beat_key == 0 or
                    self.time_beat_key == 0 or
                    self.time_beat_unit_key == 0 or
                    self.time_beats_per_bar_key == 0 or
                    self.time_beats_per_minute_key == 0 or
                    self.time_frame_key == 0 or
                    self.time_frames_per_second_key == 0 or
                    self.time_speed_key == 0 or
                    self.minimum_block_length_key == 0 or
                    self.maximum_block_length_key == 0 or
                    self.nominal_block_length_key == 0 or
                    (event_port_count != 0 and
                        self.sequence_size_key == 0))
                {
                    self.runtime.deinit();
                    allocator.destroy(self);
                    return null;
                }
                if (featureWithUri(
                    features,
                    options_options_uri,
                )) |options_feature| {
                    const options = featureValue(
                        OptionsOption,
                        options_feature,
                    ) orelse {
                        self.runtime.deinit();
                        allocator.destroy(self);
                        return null;
                    };
                    self.readInstantiationOptions(options) catch {
                        self.runtime.deinit();
                        allocator.destroy(self);
                        return null;
                    };
                }
            }
            self.runtime.prepare(.{
                .sample_rate = sample_rate,
                .max_block_size = @intCast(
                    self.configured_maximum_frames,
                ),
                .process_mode = .realtime,
            }) catch {
                self.runtime.deinit();
                allocator.destroy(self);
                return null;
            };
            return self;
        }

        fn connectPort(
            instance: Handle,
            port: u32,
            data_location: ?*anyopaque,
        ) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            if (port >= port_count) return;
            self.ports[port] = data_location;
        }

        fn activate(instance: Handle) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            self.runtime.activate() catch {
                self.last_run_status = .activation_failed;
                return;
            };
            self.last_run_status = .ready;
        }

        fn run(
            instance: Handle,
            sample_count: u32,
        ) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            if (self.inside_run) {
                self.last_run_status = .processing_failed;
                self.clearConnectedOutputs(sample_count);
                self.clearConnectedEventOutput();
                self.writeLatency();
                return;
            }
            self.inside_run = true;
            defer self.inside_run = false;
            self.processBlock(sample_count) catch |err| {
                self.last_run_status = statusForError(err);
                self.clearConnectedOutputs(sample_count);
                self.clearConnectedEventOutput();
                self.writeLatency();
            };
        }

        fn deactivate(instance: Handle) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            if (self.runtime.runtimeState() != .active) {
                self.last_run_status = .deactivation_failed;
                return;
            }
            self.runtime.deactivate() catch {
                self.last_run_status = .deactivation_failed;
                return;
            };
            self.last_run_status = .ready;
        }

        fn cleanup(instance: Handle) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            self.runtime.deinit();
            std.heap.page_allocator.destroy(self);
        }

        fn extensionData(
            raw_uri: ?[*:0]const u8,
        ) callconv(.c) ?*const anyopaque {
            const URI = raw_uri orelse return null;
            if (std.mem.eql(
                u8,
                std.mem.span(URI),
                state_interface_uri,
            )) return &state_interface;
            if (std.mem.eql(
                u8,
                std.mem.span(URI),
                options_interface_uri,
            )) return &options_interface;
            if (comptime has_worker) {
                if (std.mem.eql(
                    u8,
                    std.mem.span(URI),
                    worker_interface_uri,
                )) return &worker_interface;
            }
            if (comptime has_programs) {
                if (std.mem.eql(
                    u8,
                    std.mem.span(URI),
                    programs_interface_uri,
                )) return &programs_interface;
            }
            return null;
        }

        fn getProgram(
            instance: Handle,
            index: u32,
        ) callconv(.c) ?*const ProgramDescriptor {
            const self = instanceFromHandle(instance) orelse return null;
            var remaining: usize = index;
            for (Spec.unit_config.program_lists) |list| {
                if (remaining >= list.programs.len) {
                    remaining -= list.programs.len;
                    continue;
                }
                const item = list.programs[remaining];
                @memcpy(
                    self.program_name[0..item.name.len],
                    item.name,
                );
                self.program_name[item.name.len] = 0;
                self.program_descriptor = .{
                    .bank = @intCast(list.id),
                    .program = @intCast(remaining),
                    .name = self.program_name[0..item.name.len :0].ptr,
                };
                return &self.program_descriptor;
            }
            return null;
        }

        fn selectProgram(
            instance: Handle,
            bank: u32,
            program: u32,
        ) callconv(.c) void {
            const self = instanceFromHandle(instance) orelse return;
            if (bank > std.math.maxInt(i32)) return;
            const list = self.runtime.instance.programListById(
                @intCast(bank),
            ) orelse return;
            const item = list.program(@intCast(program)) orelse return;
            _ = self.runtime.instance.applyProgramCount(
                list.id,
                @intCast(program),
            ) catch return;
            self.clearProgramOverrides();
            for (item.parameters) |parameter| {
                const index = self.runtime.instance.parameterIndexOfId(
                    parameter.parameter_id,
                ) orelse continue;
                self.program_overrides[index] = parameter.normalized;
                self.program_control_baselines[index] =
                    self.writeProgramControlValue(
                        index,
                        parameter.normalized,
                    ) orelse self.controlInputValue(index);
            }
        }

        fn clearProgramOverrides(self: *Self) void {
            self.program_overrides = @splat(null);
            self.program_control_baselines = @splat(null);
        }

        fn controlInputValue(
            self: *const Self,
            parameter_index: usize,
        ) ?f32 {
            const port = controlPort(parameter_index) orelse return null;
            const raw = self.ports[port] orelse return null;
            if (@intFromPtr(raw) % @alignOf(f32) != 0) return null;
            const value: *const f32 = @ptrCast(@alignCast(raw));
            return if (std.math.isFinite(value.*)) value.* else null;
        }

        fn writeProgramControlValue(
            self: *Self,
            parameter_index: usize,
            normalized: f64,
        ) ?f32 {
            const port = controlPort(parameter_index) orelse return null;
            const raw = self.ports[port] orelse return null;
            if (@intFromPtr(raw) % @alignOf(f32) != 0) return null;
            const plain = self.runtime.instance
                .parameterPlainFromNormalizedIndex(
                parameter_index,
                normalized,
            ) orelse return null;
            const value: f32 = @floatCast(plain);
            if (!std.math.isFinite(value)) return null;
            const destination: *f32 = @ptrCast(@alignCast(raw));
            destination.* = value;
            return value;
        }

        fn scheduleWorker(
            context: *anyopaque,
            data: []const u8,
        ) WorkerStatus {
            const self: *Self = @ptrCast(@alignCast(context));
            if (!self.inside_run) return .unknown;
            const schedule = self.worker_schedule orelse
                return .unknown;
            const raw: ?*const anyopaque =
                if (data.len == 0) null else data.ptr;
            return schedule.schedule_work(
                schedule.handle,
                @intCast(data.len),
                raw,
            );
        }

        fn runWorker(
            instance: Handle,
            respond: WorkerRespondFunction,
            handle: WorkerRespondHandle,
            size: u32,
            data: ?*const anyopaque,
        ) callconv(.c) WorkerStatus {
            const self = instanceFromHandle(instance) orelse
                return .unknown;
            const request = workerBytes(
                size,
                data,
                worker_maximum_request_size,
            ) catch |err| return workerStatusForBytesError(err);
            var response_context = WorkerRespondContext{
                .respond = respond,
                .handle = handle,
            };
            var response = WorkerResponseSink{
                .context = &response_context,
                .maximum_size = worker_maximum_response_size,
                .respond_work = sendWorkerResponse,
            };
            self.runtime.instance.plugin.runLv2Worker(
                request,
                &response,
            ) catch return .unknown;
            return .success;
        }

        fn applyWorkerResponse(
            instance: Handle,
            size: u32,
            body: ?*const anyopaque,
        ) callconv(.c) WorkerStatus {
            const self = instanceFromHandle(instance) orelse
                return .unknown;
            const response = workerBytes(
                size,
                body,
                worker_maximum_response_size,
            ) catch |err| return workerStatusForBytesError(err);
            self.runtime.instance.plugin.applyLv2WorkerResponse(
                response,
            ) catch return .unknown;
            return .success;
        }

        fn endWorkerRun(
            instance: Handle,
        ) callconv(.c) WorkerStatus {
            const self = instanceFromHandle(instance) orelse
                return .unknown;
            self.runtime.instance.plugin.endLv2WorkerRun() catch
                return .unknown;
            return .success;
        }

        fn saveState(
            instance: Handle,
            store: StateStoreFunction,
            handle: StateHandle,
            _: u32,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) StateStatus {
            const self = instanceFromHandle(instance) orelse
                return .unknown;
            if (self.state_key == 0 or self.state_type == 0)
                return .no_feature;
            const path_features: ?StatePathFeatures =
                if (comptime has_lv2_component_state_paths)
                    statePathFeatures(
                        features,
                        requires_lv2_state_make_path,
                    ) orelse
                        return .no_feature
                else
                    null;
            var bytes: [Spec.encoded_parameter_state_size]u8 = undefined;
            var writer = std.Io.Writer.fixed(&bytes);
            self.runtime.writeParameterState(&writer) catch
                return .unknown;
            var component_bytes: [component_state_maximum_encoded_size]u8 = undefined;
            var component_size: usize = 0;
            if (comptime has_component_state) {
                var component_writer =
                    std.Io.Writer.fixed(&component_bytes);
                if (comptime has_lv2_component_state_paths) {
                    self.runtime.instance.plugin.writeLv2ComponentState(
                        &component_writer,
                        path_features.?,
                    ) catch return .unknown;
                } else {
                    self.runtime.instance.plugin.writeComponentState(
                        &component_writer,
                    ) catch return .unknown;
                }
                component_size = component_writer.end;
            }
            const parameter_status = store(
                handle,
                self.state_key,
                &bytes,
                writer.end,
                self.state_type,
                state_is_pod | state_is_portable,
            );
            if (parameter_status != .success)
                return parameter_status;
            if (comptime has_component_state) {
                return store(
                    handle,
                    self.component_state_key,
                    &component_bytes,
                    component_size,
                    self.state_type,
                    state_is_pod | state_is_portable,
                );
            }
            return .success;
        }

        fn restoreState(
            instance: Handle,
            retrieve: StateRetrieveFunction,
            handle: StateHandle,
            _: u32,
            features: ?[*:null]const ?*const Feature,
        ) callconv(.c) StateStatus {
            const self = instanceFromHandle(instance) orelse
                return .unknown;
            if (self.state_key == 0 or self.state_type == 0)
                return .no_feature;
            const path_features: ?StatePathFeatures =
                if (comptime has_lv2_component_state_paths)
                    statePathFeatures(
                        features,
                        requires_lv2_state_make_path,
                    ) orelse
                        return .no_feature
                else
                    null;
            var parameter_size: usize = 0;
            var parameter_type: Urid = 0;
            var parameter_flags: u32 = 0;
            const parameter_raw = retrieve(
                handle,
                self.state_key,
                &parameter_size,
                &parameter_type,
                &parameter_flags,
            );
            if (parameter_raw != null) {
                if (parameter_type != self.state_type)
                    return .bad_type;
                if (parameter_flags & state_is_pod == 0)
                    return .bad_flags;
                if (parameter_size !=
                    Spec.encoded_parameter_state_size)
                    return .bad_type;
            }

            var component_raw: ?*const anyopaque = null;
            var component_size: usize = 0;
            var component_type: Urid = 0;
            var component_flags: u32 = 0;
            if (comptime has_component_state) {
                component_raw = retrieve(
                    handle,
                    self.component_state_key,
                    &component_size,
                    &component_type,
                    &component_flags,
                );
                if (component_raw != null) {
                    if (component_type != self.state_type)
                        return .bad_type;
                    if (component_flags & state_is_pod == 0)
                        return .bad_flags;
                    if (component_size >
                        component_state_maximum_encoded_size)
                        return .bad_type;
                }
            }

            var previous_parameter_bytes: [Spec.encoded_parameter_state_size]u8 = undefined;
            var previous_writer =
                std.Io.Writer.fixed(&previous_parameter_bytes);
            self.runtime.writeParameterState(&previous_writer) catch
                return .unknown;

            if (parameter_raw) |raw| {
                const data: [*]const u8 = @ptrCast(raw);
                var reader = std.Io.Reader.fixed(
                    data[0..parameter_size],
                );
                self.runtime.readParameterStateExclusive(&reader) catch
                    return .bad_type;
            } else {
                self.runtime.instance.resetParametersToDefaults();
                self.runtime.instance.afterStateRestore();
            }

            if (comptime has_component_state) {
                if (component_raw) |raw| {
                    const data: [*]const u8 = @ptrCast(raw);
                    var reader = std.Io.Reader.fixed(
                        data[0..component_size],
                    );
                    const restored = if (comptime has_lv2_component_state_paths) blk: {
                        self.runtime.instance.plugin
                            .readLv2ComponentState(
                            &reader,
                            path_features.?,
                        ) catch break :blk false;
                        break :blk true;
                    } else blk: {
                        self.runtime.instance.plugin
                            .readComponentState(&reader) catch
                            break :blk false;
                        break :blk true;
                    };
                    if (!restored) {
                        if (!self.restoreParameterSnapshot(
                            &previous_parameter_bytes,
                        )) return .unknown;
                        return .bad_type;
                    }
                    if (reader.seek != reader.end) {
                        if (!self.restoreParameterSnapshot(
                            &previous_parameter_bytes,
                        )) return .unknown;
                        return .bad_type;
                    }
                    if (comptime @hasDecl(
                        Plugin,
                        "afterComponentStateRestore",
                    )) {
                        self.runtime.instance.plugin
                            .afterComponentStateRestore();
                    }
                }
            }
            self.clearProgramOverrides();
            return .success;
        }

        fn restoreParameterSnapshot(
            self: *Self,
            bytes: *const [Spec.encoded_parameter_state_size]u8,
        ) bool {
            var reader = std.Io.Reader.fixed(bytes);
            self.runtime.readParameterStateExclusive(&reader) catch
                return false;
            return true;
        }

        fn getOptions(
            instance: Handle,
            raw_options: ?[*]OptionsOption,
        ) callconv(.c) OptionsStatus {
            const self = instanceFromHandle(instance) orelse
                return options_status_unknown;
            const options = raw_options orelse
                return options_status_unknown;
            var status = options_status_success;
            var terminated = false;
            for (0..256) |index| {
                const option = &options[index];
                if (option.key == 0 and option.value == null) {
                    terminated = true;
                    break;
                }
                if (option.context !=
                    @intFromEnum(OptionsContext.instance))
                {
                    status |= options_status_bad_subject;
                    continue;
                }
                if (option.size != 0 or
                    option.type != 0 or
                    option.value != null)
                {
                    status |= options_status_bad_value;
                    continue;
                }
                const value: *const i32 =
                    if (option.key == self.minimum_block_length_key)
                        &self.configured_minimum_frames
                    else if (option.key == self.maximum_block_length_key)
                        &self.configured_maximum_value
                    else if (option.key == self.nominal_block_length_key)
                        &self.configured_nominal_frames
                    else if (event_port_count != 0 and
                    option.key == self.sequence_size_key)
                        if (self.sequence_size_configured)
                            &self.configured_sequence_size_value
                        else {
                            status |= options_status_unknown;
                            continue;
                        }
                    else {
                        status |= options_status_bad_key;
                        continue;
                    };
                option.size = @sizeOf(i32);
                option.type = self.atom_int_type;
                option.value = value;
            }
            if (!terminated) status |= options_status_unknown;
            return status;
        }

        fn setOptions(
            instance: Handle,
            raw_options: ?[*]const OptionsOption,
        ) callconv(.c) OptionsStatus {
            const self = instanceFromHandle(instance) orelse
                return options_status_unknown;
            const options = raw_options orelse
                return options_status_unknown;
            var minimum: ?usize = null;
            var maximum: ?usize = null;
            var nominal: ?usize = null;
            var sequence_size: ?usize = null;
            var status = options_status_success;
            var terminated = false;
            for (0..256) |index| {
                const option = options[index];
                if (option.key == 0 and option.value == null) {
                    terminated = true;
                    break;
                }
                if (option.context !=
                    @intFromEnum(OptionsContext.instance))
                {
                    status |= options_status_bad_subject;
                    continue;
                }
                const destination: *?usize =
                    if (option.key == self.minimum_block_length_key)
                        &minimum
                    else if (option.key == self.maximum_block_length_key)
                        &maximum
                    else if (option.key == self.nominal_block_length_key)
                        &nominal
                    else if (event_port_count != 0 and
                    option.key == self.sequence_size_key)
                        &sequence_size
                    else {
                        status |= options_status_bad_key;
                        continue;
                    };
                if (destination.* != null) {
                    status |= options_status_bad_value;
                    continue;
                }
                const allow_zero =
                    option.key != self.maximum_block_length_key;
                destination.* = self.readBlockLengthOption(
                    option,
                    allow_zero,
                ) catch {
                    status |= options_status_bad_value;
                    continue;
                };
            }
            if (!terminated) status |= options_status_unknown;
            if (status != options_status_success) return status;

            const next_minimum = minimum orelse
                @as(usize, @intCast(self.configured_minimum_frames));
            const next_maximum = maximum orelse
                self.configured_maximum_frames;
            const next_nominal = nominal orelse
                @as(usize, @intCast(self.configured_nominal_frames));
            if (!validBlockLengths(
                next_minimum,
                next_maximum,
                next_nominal,
                maximum_block_size,
            )) return options_status_bad_value;
            if (next_maximum != self.configured_maximum_frames) {
                if (self.runtime.runtimeState() == .active)
                    return options_status_bad_value;
                const previous_maximum =
                    self.configured_maximum_frames;
                self.runtime.prepare(.{
                    .sample_rate = self.sample_rate,
                    .max_block_size = @intCast(next_maximum),
                    .process_mode = .realtime,
                }) catch {
                    self.runtime.prepare(.{
                        .sample_rate = self.sample_rate,
                        .max_block_size = @intCast(previous_maximum),
                        .process_mode = .realtime,
                    }) catch {};
                    return options_status_unknown;
                };
            }
            self.configured_minimum_frames = @intCast(next_minimum);
            self.configured_maximum_frames = next_maximum;
            self.configured_maximum_value = @intCast(next_maximum);
            self.configured_nominal_frames = @intCast(next_nominal);
            if (sequence_size) |value| {
                self.configured_sequence_size_value = @intCast(value);
                self.sequence_size_configured = true;
            }
            return options_status_success;
        }

        fn readInstantiationOptions(
            self: *Self,
            data: *const OptionsOption,
        ) !void {
            const options: [*]const OptionsOption =
                @ptrCast(data);
            var minimum: ?usize = null;
            var maximum: ?usize = null;
            var nominal: ?usize = null;
            var sequence_size: ?usize = null;
            var terminated = false;
            for (0..256) |index| {
                const option = options[index];
                if (option.key == 0 and option.value == null) {
                    terminated = true;
                    break;
                }
                if (option.key == 0)
                    return error.InvalidOptions;
                if (option.context !=
                    @intFromEnum(OptionsContext.instance))
                    continue;
                if (option.key == self.minimum_block_length_key) {
                    if (minimum != null)
                        return error.InvalidOptions;
                    minimum = try self.readBlockLengthOption(
                        option,
                        true,
                    );
                } else if (option.key == self.maximum_block_length_key) {
                    if (maximum != null)
                        return error.InvalidOptions;
                    maximum = try self.readBlockLengthOption(
                        option,
                        false,
                    );
                } else if (option.key == self.nominal_block_length_key) {
                    if (nominal != null)
                        return error.InvalidOptions;
                    nominal = try self.readBlockLengthOption(
                        option,
                        true,
                    );
                } else if (event_port_count != 0 and
                    option.key == self.sequence_size_key)
                {
                    if (sequence_size != null)
                        return error.InvalidOptions;
                    sequence_size = try self.readBlockLengthOption(
                        option,
                        true,
                    );
                }
            }
            if (!terminated) return error.InvalidOptions;
            const effective_minimum = minimum orelse 0;
            const effective_maximum = maximum orelse maximum_block_size;
            const effective_nominal = nominal orelse effective_maximum;
            if (!validBlockLengths(
                effective_minimum,
                effective_maximum,
                effective_nominal,
                maximum_block_size,
            )) return error.InvalidOptions;
            self.configured_minimum_frames =
                @intCast(effective_minimum);
            self.configured_maximum_frames = effective_maximum;
            self.configured_maximum_value =
                @intCast(effective_maximum);
            self.configured_nominal_frames =
                @intCast(effective_nominal);
            if (sequence_size) |value| {
                self.configured_sequence_size_value = @intCast(value);
                self.sequence_size_configured = true;
            }
        }

        fn readBlockLengthOption(
            self: *const Self,
            option: OptionsOption,
            allow_zero: bool,
        ) !usize {
            if (option.type != self.atom_int_type or
                option.size != @sizeOf(i32))
                return error.InvalidOptions;
            const raw = option.value orelse
                return error.InvalidOptions;
            const value = @as(
                *align(1) const i32,
                @ptrCast(raw),
            ).*;
            if (value < 0 or (!allow_zero and value == 0))
                return error.InvalidOptions;
            return @intCast(value);
        }

        fn processBlock(
            self: *Self,
            sample_count_u32: u32,
        ) !void {
            if (self.runtime.runtimeState() != .active)
                return error.Inactive;
            self.writeLatency();
            if (sample_count_u32 == 0) {
                self.clearConnectedEventOutput();
                self.last_run_status = .succeeded;
                return;
            }
            const sample_count: usize = sample_count_u32;
            if (sample_count > self.configured_maximum_frames)
                return error.BlockTooLarge;
            const process_mode = try self.readProcessMode();
            const transport_before = self.transport;
            const speed_before = self.transport_speed;
            const beats_per_bar_before = self.beats_per_bar;
            const beat_unit_before = self.beat_unit;
            const bar_before = self.bar;
            const bar_beat_before = self.bar_beat;
            const beat_before = self.beat;
            errdefer {
                self.transport = transport_before;
                self.transport_speed = speed_before;
                self.beats_per_bar = beats_per_bar_before;
                self.beat_unit = beat_unit_before;
                self.bar = bar_before;
                self.bar_beat = bar_beat_before;
                self.beat = beat_before;
            }

            var main_inputs: [main_input_channel_count][]const f32 = undefined;
            var auxiliary_inputs: [auxiliary_input_channel_count][]const f32 = undefined;
            var main_outputs: [main_output_channel_count][]f32 = undefined;
            var auxiliary_outputs: [auxiliary_output_channel_count][]f32 = undefined;
            try self.bindInputChannels(
                sample_count,
                &main_inputs,
                &auxiliary_inputs,
            );
            try self.bindOutputChannels(
                sample_count,
                &main_outputs,
                &auxiliary_outputs,
            );

            var changes: [parameter_count]process_api.ParameterChange =
                undefined;
            var input_events: [maximum_event_count]process_api.Event =
                undefined;
            var position_updates: [maximum_event_count]TimedPositionUpdate = undefined;
            var patch_requests: [maximum_event_count]TimedPatchRequest =
                undefined;
            const input = try self.readInputEvents(
                sample_count,
                &input_events,
                &position_updates,
                &patch_requests,
            );
            var output_event_storage: [maximum_event_count]process_api.Event = undefined;
            var patch_response_storage: [patch_response_capacity]u8 =
                undefined;
            var patch_response_size: usize = 0;
            try self.readControlChanges(&changes);
            var output_event_count: usize = 0;
            var frame_cursor: usize = 0;
            var position_index: usize = 0;
            var patch_index: usize = 0;
            var controls_pending = true;
            while (position_index < input.position_count or
                patch_index < input.patch_count)
            {
                const position_boundary = if (position_index <
                    input.position_count)
                    position_updates[position_index].sample_offset
                else
                    sample_count;
                const patch_boundary = if (patch_index <
                    input.patch_count)
                    patch_requests[patch_index].sample_offset
                else
                    sample_count;
                const boundary = @min(
                    position_boundary,
                    patch_boundary,
                );
                if (boundary > frame_cursor) {
                    try self.processSegment(
                        frame_cursor,
                        boundary,
                        &main_inputs,
                        &auxiliary_inputs,
                        &main_outputs,
                        &auxiliary_outputs,
                        if (controls_pending) &changes else &.{},
                        input_events[0..input.event_count],
                        &output_event_storage,
                        &output_event_count,
                        process_mode,
                    );
                    controls_pending = false;
                    try self.advanceTransport(boundary - frame_cursor);
                    frame_cursor = boundary;
                }
                while (position_index < input.position_count and
                    position_updates[position_index].sample_offset ==
                        frame_cursor)
                {
                    try self.applyTimePosition(
                        position_updates[position_index].update,
                    );
                    position_index += 1;
                }
                while (patch_index < input.patch_count and
                    patch_requests[patch_index].sample_offset ==
                        frame_cursor)
                {
                    try self.applyPatchRequest(
                        patch_requests[patch_index],
                        &output_event_storage,
                        &output_event_count,
                        &patch_response_storage,
                        &patch_response_size,
                    );
                    patch_index += 1;
                }
            }
            if (frame_cursor < sample_count) {
                try self.processSegment(
                    frame_cursor,
                    sample_count,
                    &main_inputs,
                    &auxiliary_inputs,
                    &main_outputs,
                    &auxiliary_outputs,
                    if (controls_pending) &changes else &.{},
                    input_events[0..input.event_count],
                    &output_event_storage,
                    &output_event_count,
                    process_mode,
                );
                try self.advanceTransport(sample_count - frame_cursor);
            }
            try self.writeOutputEvents(
                output_event_storage[0..output_event_count],
            );
            self.last_run_status = .succeeded;
        }

        fn processSegment(
            self: *Self,
            start: usize,
            end: usize,
            main_inputs: *const [main_input_channel_count][]const f32,
            auxiliary_inputs: *const [auxiliary_input_channel_count][]const f32,
            main_outputs: *const [main_output_channel_count][]f32,
            auxiliary_outputs: *const [auxiliary_output_channel_count][]f32,
            changes: []const process_api.ParameterChange,
            input_events: []const process_api.Event,
            output_events: *[maximum_event_count]process_api.Event,
            output_event_count: *usize,
            process_mode: process_api.ProcessMode,
        ) !void {
            if (end <= start) return error.InvalidContext;
            const frame_count = end - start;
            var segment_main_inputs: [main_input_channel_count][]const f32 = undefined;
            var segment_auxiliary_inputs: [auxiliary_input_channel_count][]const f32 = undefined;
            var segment_main_outputs: [main_output_channel_count][]f32 = undefined;
            var segment_auxiliary_outputs: [auxiliary_output_channel_count][]f32 = undefined;
            for (main_inputs, 0..) |channel, index|
                segment_main_inputs[index] = channel[start..end];
            for (auxiliary_inputs, 0..) |channel, index|
                segment_auxiliary_inputs[index] = channel[start..end];
            for (main_outputs, 0..) |channel, index|
                segment_main_outputs[index] = channel[start..end];
            for (auxiliary_outputs, 0..) |channel, index|
                segment_auxiliary_outputs[index] = channel[start..end];

            var segment_input_storage: [maximum_event_count]process_api.Event = undefined;
            var segment_input_count: usize = 0;
            for (input_events) |event| {
                if (event.sample_offset < start or
                    event.sample_offset >= end)
                    continue;
                segment_input_storage[segment_input_count] =
                    event.withSampleOffset(event.sample_offset - start);
                segment_input_count += 1;
            }

            var output_event_writer = process_api.EventWriter.init(
                output_events[output_event_count.*..],
                frame_count,
            );
            var context =
                process_api.BoundedProcessContext(
                    f32,
                    Spec.auxiliary_audio_bus_capacity,
                ).initWithOptions(.{
                    .sample_rate = self.sample_rate,
                    .process_mode = process_mode,
                    .input_channels = &segment_main_inputs,
                    .sidechain_input_channels = &segment_auxiliary_inputs,
                    .auxiliary_input_bus_channel_counts = &auxiliary_input_bus_channel_counts,
                    .output_channels = &segment_main_outputs,
                    .auxiliary_output_channels = &segment_auxiliary_outputs,
                    .auxiliary_output_bus_channel_counts = &auxiliary_output_bus_channel_counts,
                    .attachments = .{
                        .parameter_changes = changes,
                        .events = segment_input_storage[0..segment_input_count],
                        .output_events = if (has_event_output)
                            &output_event_writer
                        else
                            null,
                    },
                    .transport = self.transport,
                }) catch return error.InvalidContext;
            self.runtime.process(&context) catch
                return error.ProcessingFailed;
            const emitted_count = output_event_writer.eventCount();
            for (output_events[output_event_count.* .. output_event_count.* + emitted_count]) |*event| {
                event.* = event.withSampleOffset(
                    event.sample_offset + start,
                );
            }
            output_event_count.* += emitted_count;
        }

        fn readInputEvents(
            self: *Self,
            sample_count: usize,
            storage: *[maximum_event_count]process_api.Event,
            position_storage: *[maximum_event_count]TimedPositionUpdate,
            patch_storage: *[maximum_event_count]TimedPatchRequest,
        ) !InputReadResult {
            const port = event_input_port orelse return .{};
            const raw = self.ports[port] orelse return .{};
            const sequence: *align(1) const AtomSequence =
                @ptrCast(raw);
            if (sequence.atom.type != self.sequence_type or
                sequence.atom.size < @sizeOf(AtomSequenceBody) or
                (sequence.body.unit != 0 and
                    sequence.body.unit != self.frame_time_type))
                return error.InvalidEvents;

            const body_size: usize = sequence.atom.size;
            var offset: usize = @sizeOf(AtomSequenceBody);
            var count: usize = 0;
            var position_count: usize = 0;
            var patch_count: usize = 0;
            var previous_frame: ?i64 = null;
            const bytes: [*]const u8 = @ptrCast(&sequence.body);
            while (offset < body_size) {
                if (body_size - offset < @sizeOf(AtomEvent))
                    return error.InvalidEvents;
                const event: *align(1) const AtomEvent =
                    @ptrCast(bytes + offset);
                const payload_size: usize = event.body.size;
                const raw_event_size = std.math.add(
                    usize,
                    @sizeOf(AtomEvent),
                    payload_size,
                ) catch return error.InvalidEvents;
                const padded_size = alignAtomSize(raw_event_size) orelse
                    return error.InvalidEvents;
                if (padded_size > body_size - offset)
                    return error.InvalidEvents;
                if (event.time.frames < 0 or
                    event.time.frames >= sample_count)
                    return error.InvalidEvents;
                if (previous_frame) |frame| {
                    if (event.time.frames < frame)
                        return error.InvalidEvents;
                }
                previous_frame = event.time.frames;
                if (event.body.type == self.midi_event_type) {
                    if (count >= storage.len)
                        return error.EventStorageFull;
                    const payload = bytes[offset + @sizeOf(AtomEvent) .. offset + @sizeOf(AtomEvent) + payload_size];
                    try validateMidiEvent(payload);
                    const sample_offset: usize =
                        @intCast(event.time.frames);
                    storage[count] = if (process_api.Midi1Message.parse(
                        payload,
                    )) |message|
                        message.toEvent(sample_offset, 0) orelse
                            process_api.Event.dataEvent(
                                sample_offset,
                                self.midi_event_type,
                                payload,
                            )
                    else |_|
                        process_api.Event.dataEvent(
                            sample_offset,
                            self.midi_event_type,
                            payload,
                        );
                    count += 1;
                } else if (event.body.type == self.atom_object_type or
                    event.body.type == self.atom_blank_type)
                {
                    if (try self.readTimePosition(
                        bytes[offset + @sizeOf(AtomEvent) .. offset + @sizeOf(AtomEvent) + payload_size],
                    )) |update| {
                        if (position_count >= position_storage.len)
                            return error.EventStorageFull;
                        position_storage[position_count] = .{
                            .sample_offset = @intCast(event.time.frames),
                            .update = update,
                        };
                        position_count += 1;
                    } else if (try self.readPatchRequest(
                        @intCast(event.time.frames),
                        bytes[offset + @sizeOf(AtomEvent) .. offset + @sizeOf(AtomEvent) + payload_size],
                    )) |request| {
                        if (patch_count >= patch_storage.len)
                            return error.EventStorageFull;
                        patch_storage[patch_count] = request;
                        patch_count += 1;
                    } else {
                        if (count >= storage.len)
                            return error.EventStorageFull;
                        storage[count] = process_api.Event.dataEvent(
                            @intCast(event.time.frames),
                            event.body.type,
                            bytes[offset + @sizeOf(AtomEvent) .. offset + @sizeOf(AtomEvent) + payload_size],
                        );
                        count += 1;
                    }
                } else {
                    if (event.body.type == 0)
                        return error.InvalidEvents;
                    if (count >= storage.len)
                        return error.EventStorageFull;
                    storage[count] = process_api.Event.dataEvent(
                        @intCast(event.time.frames),
                        event.body.type,
                        bytes[offset + @sizeOf(AtomEvent) .. offset + @sizeOf(AtomEvent) + payload_size],
                    );
                    count += 1;
                }
                offset += padded_size;
            }
            return .{
                .event_count = count,
                .position_count = position_count,
                .patch_count = patch_count,
            };
        }

        fn readTimePosition(
            self: *const Self,
            payload: []const u8,
        ) !?PositionUpdate {
            if (payload.len < @sizeOf(AtomObjectBody))
                return error.InvalidTransport;
            const object: *align(1) const AtomObjectBody =
                @ptrCast(payload.ptr);
            if (object.otype != self.time_position_type) return null;

            var update = PositionUpdate{};
            var offset: usize = @sizeOf(AtomObjectBody);
            while (offset < payload.len) {
                if (payload.len - offset < @sizeOf(AtomPropertyBody))
                    return error.InvalidTransport;
                const property: *align(1) const AtomPropertyBody =
                    @ptrCast(payload.ptr + offset);
                const value_size: usize = property.value.size;
                const raw_size = std.math.add(
                    usize,
                    @sizeOf(AtomPropertyBody),
                    value_size,
                ) catch return error.InvalidTransport;
                const padded_size = alignAtomSize(raw_size) orelse
                    return error.InvalidTransport;
                if (padded_size > payload.len - offset)
                    return error.InvalidTransport;
                const value = payload[offset + @sizeOf(AtomPropertyBody) .. offset + @sizeOf(AtomPropertyBody) + value_size];
                try self.readTimeProperty(
                    &update,
                    property.key,
                    property.value.type,
                    value,
                );
                offset += padded_size;
            }
            return update;
        }

        fn readPatchRequest(
            self: *const Self,
            sample_offset: usize,
            payload: []const u8,
        ) !?TimedPatchRequest {
            if (comptime !has_patch_messages) return null;
            if (payload.len < @sizeOf(AtomObjectBody))
                return error.InvalidPatch;
            const object: *align(1) const AtomObjectBody =
                @ptrCast(payload.ptr);
            const kind: PatchRequestKind =
                if (object.otype == self.patch_get_type)
                    .get
                else if (object.otype == self.patch_set_type)
                    .set
                else if (object.otype == self.patch_put_type)
                    .put
                else if (object.otype == self.patch_insert_type)
                    .insert
                else if (object.otype == self.patch_patch_type)
                    .patch
                else if (object.otype == self.patch_delete_type)
                    .delete
                else if (object.otype == self.patch_copy_type)
                    .copy
                else if (object.otype == self.patch_move_type)
                    .move
                else
                    return null;

            var property_urid: ?Urid = null;
            var sequence_number: ?i32 = null;
            var subject_matches = true;
            var subject: ?Urid = null;
            var graph_subjects =
                [_]Urid{0} ** maximum_patch_graph_subject_count;
            var graph_subject_count: usize = 0;
            var destination: ?Urid = null;
            var context: ?Urid = null;
            var raw_value: ?RawPatchValue = null;
            var body: ?RawPatchValue = null;
            var add: ?RawPatchValue = null;
            var remove: ?RawPatchValue = null;
            var offset: usize = @sizeOf(AtomObjectBody);
            while (offset < payload.len) {
                if (payload.len - offset < @sizeOf(AtomPropertyBody))
                    return error.InvalidPatch;
                const property: *align(1) const AtomPropertyBody =
                    @ptrCast(payload.ptr + offset);
                const value_size: usize = property.value.size;
                const raw_size = std.math.add(
                    usize,
                    @sizeOf(AtomPropertyBody),
                    value_size,
                ) catch return error.InvalidPatch;
                const padded_size = alignAtomSize(raw_size) orelse
                    return error.InvalidPatch;
                if (padded_size > payload.len - offset)
                    return error.InvalidPatch;
                const value =
                    payload[offset + @sizeOf(AtomPropertyBody) .. offset + @sizeOf(AtomPropertyBody) + value_size];
                if (property.key == self.patch_property_key) {
                    if (property_urid != null)
                        return error.InvalidPatch;
                    property_urid = try self.readPatchUrid(
                        property.value.type,
                        value,
                    );
                } else if (property.key ==
                    self.patch_sequence_number_key)
                {
                    if (sequence_number != null)
                        return error.InvalidPatch;
                    sequence_number = try self.readPatchInt(
                        property.value.type,
                        value,
                    );
                } else if (property.key == self.patch_subject_key) {
                    const parsed_subject = try self.readPatchUrid(
                        property.value.type,
                        value,
                    );
                    if (kind == .get or kind == .set) {
                        if (subject != null) return error.InvalidPatch;
                        subject = parsed_subject;
                        subject_matches =
                            parsed_subject == self.patch_subject;
                    } else {
                        if (graph_subject_count >= graph_subjects.len)
                            return error.InvalidPatch;
                        graph_subjects[graph_subject_count] =
                            parsed_subject;
                        graph_subject_count += 1;
                    }
                } else if (property.key ==
                    self.patch_destination_key)
                {
                    if (destination != null) return error.InvalidPatch;
                    destination = try self.readPatchUrid(
                        property.value.type,
                        value,
                    );
                } else if (property.key == self.patch_context_key) {
                    if (context != null) return error.InvalidPatch;
                    context = try self.readPatchUrid(
                        property.value.type,
                        value,
                    );
                } else if (property.key == self.patch_body_key) {
                    if (body != null) return error.InvalidPatch;
                    body = .{
                        .atom_type = property.value.type,
                        .body = value,
                    };
                } else if (property.key == self.patch_add_key) {
                    if (add != null) return error.InvalidPatch;
                    add = .{
                        .atom_type = property.value.type,
                        .body = value,
                    };
                } else if (property.key == self.patch_remove_key) {
                    if (remove != null) return error.InvalidPatch;
                    remove = .{
                        .atom_type = property.value.type,
                        .body = value,
                    };
                } else if (property.key == self.patch_value_key) {
                    if (raw_value != null) return error.InvalidPatch;
                    raw_value = .{
                        .atom_type = property.value.type,
                        .body = value,
                    };
                }
                offset += padded_size;
            }
            if (kind != .get and kind != .set) {
                if (comptime !has_patch_graph_operations) return null;
                if (property_urid != null or raw_value != null)
                    return error.InvalidPatch;
                if (graph_subject_count == 0)
                    return error.InvalidPatch;
                const request = TimedPatchRequest{
                    .sample_offset = sample_offset,
                    .kind = kind,
                    .sequence_number = sequence_number,
                    .graph_subjects = graph_subjects,
                    .graph_subject_count = graph_subject_count,
                    .destination = destination,
                    .context = context,
                    .body = body,
                    .add = add,
                    .remove = remove,
                };
                switch (kind) {
                    .put, .insert => {
                        if (graph_subject_count != 1 or body == null or
                            destination != null or
                            add != null or remove != null)
                            return error.InvalidPatch;
                    },
                    .patch => {
                        if (graph_subject_count != 1 or add == null or
                            remove == null or
                            body != null or destination != null)
                            return error.InvalidPatch;
                    },
                    .delete => {
                        if (body != null or destination != null or
                            add != null or remove != null)
                            return error.InvalidPatch;
                    },
                    .copy, .move => {
                        if ((kind == .move and
                            graph_subject_count != 1) or
                            destination == null or body != null or
                            add != null or remove != null)
                            return error.InvalidPatch;
                    },
                    .get, .set => unreachable,
                }
                return request;
            }
            if (body != null or add != null or remove != null or
                destination != null or context != null)
                return error.InvalidPatch;
            const property_id = property_urid orelse
                return error.InvalidPatch;
            const property_index = self.patchPropertyIndex(property_id);
            if (!subject_matches or property_index == null)
                return .{
                    .sample_offset = sample_offset,
                    .kind = kind,
                    .property_index = null,
                    .sequence_number = sequence_number,
                    .subject = subject,
                };
            const index = property_index.?;
            return switch (kind) {
                .get => blk: {
                    if (raw_value != null) return error.InvalidPatch;
                    break :blk .{
                        .sample_offset = sample_offset,
                        .kind = .get,
                        .property_index = index,
                        .sequence_number = sequence_number,
                        .subject = subject,
                    };
                },
                .set => .{
                    .sample_offset = sample_offset,
                    .kind = .set,
                    .property_index = index,
                    .value = try self.readPatchValue(
                        patch_properties[index].value_kind,
                        raw_value orelse return error.InvalidPatch,
                    ),
                    .sequence_number = sequence_number,
                    .subject = subject,
                },
                .put,
                .insert,
                .patch,
                .delete,
                .copy,
                .move,
                => return error.InvalidPatch,
            };
        }

        fn patchPropertyIndex(
            self: *const Self,
            property: Urid,
        ) ?usize {
            for (self.patch_property_urids, 0..) |candidate, index| {
                if (candidate == property) return index;
            }
            return null;
        }

        fn readPatchValue(
            self: *const Self,
            kind: PatchValueKind,
            raw: RawPatchValue,
        ) !PatchValue {
            return switch (kind) {
                .boolean => .{ .boolean = (try self.readPatchIntType(
                    self.atom_bool_type,
                    raw,
                )) != 0 },
                .int => .{ .int = try self.readPatchIntType(
                    self.atom_int_type,
                    raw,
                ) },
                .long => .{ .long = try self.readPatchLongType(
                    self.atom_long_type,
                    raw,
                ) },
                .float => .{ .float = try self.readPatchFloatType(
                    self.atom_float_type,
                    raw,
                ) },
                .double => .{ .double = try self.readPatchDoubleType(
                    self.atom_double_type,
                    raw,
                ) },
                .string => .{ .string = try self.readPatchStringType(
                    self.atom_string_type,
                    raw,
                ) },
                .path => blk: {
                    const value = try self.readPatchStringType(
                        self.atom_path_type,
                        raw,
                    );
                    if (!std.fs.path.isAbsolute(value))
                        return error.InvalidPatch;
                    break :blk .{ .path = value };
                },
                .uri => .{ .uri = try self.readPatchStringType(
                    self.atom_uri_type,
                    raw,
                ) },
                .urid => .{ .urid = try self.readPatchUrid(
                    raw.atom_type,
                    raw.body,
                ) },
            };
        }

        fn readPatchInt(
            self: *const Self,
            atom_type: Urid,
            body: []const u8,
        ) !i32 {
            return self.readPatchIntType(
                self.atom_int_type,
                .{ .atom_type = atom_type, .body = body },
            );
        }

        fn readPatchUrid(
            self: *const Self,
            atom_type: Urid,
            body: []const u8,
        ) !Urid {
            if (atom_type != self.atom_urid_type or
                body.len != @sizeOf(Urid))
                return error.InvalidPatch;
            const value = @as(
                *align(1) const Urid,
                @ptrCast(body.ptr),
            ).*;
            if (value == 0) return error.InvalidPatch;
            return value;
        }

        fn readPatchIntType(
            _: *const Self,
            expected_type: Urid,
            raw: RawPatchValue,
        ) !i32 {
            if (raw.atom_type != expected_type or
                raw.body.len != @sizeOf(i32))
                return error.InvalidPatch;
            return @as(
                *align(1) const i32,
                @ptrCast(raw.body.ptr),
            ).*;
        }

        fn readPatchLongType(
            _: *const Self,
            expected_type: Urid,
            raw: RawPatchValue,
        ) !i64 {
            if (raw.atom_type != expected_type or
                raw.body.len != @sizeOf(i64))
                return error.InvalidPatch;
            return @as(
                *align(1) const i64,
                @ptrCast(raw.body.ptr),
            ).*;
        }

        fn readPatchFloatType(
            _: *const Self,
            expected_type: Urid,
            raw: RawPatchValue,
        ) !f32 {
            if (raw.atom_type != expected_type or
                raw.body.len != @sizeOf(f32))
                return error.InvalidPatch;
            const value = @as(
                *align(1) const f32,
                @ptrCast(raw.body.ptr),
            ).*;
            if (!std.math.isFinite(value)) return error.InvalidPatch;
            return value;
        }

        fn readPatchDoubleType(
            _: *const Self,
            expected_type: Urid,
            raw: RawPatchValue,
        ) !f64 {
            if (raw.atom_type != expected_type or
                raw.body.len != @sizeOf(f64))
                return error.InvalidPatch;
            const value = @as(
                *align(1) const f64,
                @ptrCast(raw.body.ptr),
            ).*;
            if (!std.math.isFinite(value)) return error.InvalidPatch;
            return value;
        }

        fn readPatchStringType(
            _: *const Self,
            expected_type: Urid,
            raw: RawPatchValue,
        ) ![]const u8 {
            if (raw.atom_type != expected_type or raw.body.len == 0 or
                raw.body[raw.body.len - 1] != 0)
                return error.InvalidPatch;
            const value = raw.body[0 .. raw.body.len - 1];
            if (std.mem.indexOfScalar(u8, value, 0) != null or
                !std.unicode.utf8ValidateSlice(value))
                return error.InvalidPatch;
            return value;
        }

        fn applyPatchRequest(
            self: *Self,
            request: TimedPatchRequest,
            output_events: *[maximum_event_count]process_api.Event,
            output_event_count: *usize,
            response_storage: *[patch_response_capacity]u8,
            response_size: *usize,
        ) !void {
            if (comptime !has_patch_messages) return;
            if (request.kind != .get and request.kind != .set) {
                if (comptime has_patch_graph_operations) {
                    const graph_request = try patchGraphRequest(&request);
                    var succeeded = true;
                    self.runtime.instance.plugin
                        .applyLv2PatchGraphRequest(graph_request) catch {
                        succeeded = false;
                    };
                    if (request.sequence_number == null or
                        request.sequence_number == 0)
                        return;
                    const payload = try self.appendPatchGraphResponse(
                        response_storage,
                        response_size,
                        request.sequence_number.?,
                        succeeded,
                    );
                    if (output_event_count.* >= output_events.len)
                        return error.EventStorageFull;
                    output_events[output_event_count.*] =
                        process_api.Event.dataEvent(
                            request.sample_offset,
                            self.atom_object_type,
                            payload,
                        );
                    output_event_count.* += 1;
                }
                return;
            }
            const property_index = request.property_index orelse return;
            const property = patch_properties[property_index];
            switch (request.kind) {
                .set => {
                    if (!property.writable) return;
                    if (comptime has_writable_patch_properties) {
                        try self.runtime.instance.plugin
                            .writeLv2PatchProperty(
                            property_index,
                            request.value orelse
                                return error.InvalidPatch,
                        );
                    }
                },
                .get => {
                    if (!property.readable or
                        request.sequence_number == 0)
                        return;
                    if (comptime has_readable_patch_properties) {
                        const value = try self.runtime.instance.plugin
                            .readLv2PatchProperty(property_index);
                        if (std.meta.activeTag(value) !=
                            property.value_kind)
                            return error.InvalidPatchValue;
                        const payload = try self.appendPatchSetResponse(
                            response_storage,
                            response_size,
                            property_index,
                            request.sequence_number,
                            request.subject,
                            value,
                        );
                        if (output_event_count.* >= output_events.len)
                            return error.EventStorageFull;
                        output_events[output_event_count.*] =
                            process_api.Event.dataEvent(
                                request.sample_offset,
                                self.atom_object_type,
                                payload,
                            );
                        output_event_count.* += 1;
                    }
                },
                .put, .insert, .patch, .delete, .copy, .move => unreachable,
            }
        }

        fn appendPatchGraphResponse(
            self: *const Self,
            storage: *[patch_response_capacity]u8,
            used: *usize,
            sequence_number: i32,
            succeeded: bool,
        ) ![]const u8 {
            const start = alignAtomSize(used.*) orelse
                return error.EventStorageFull;
            if (start > storage.len or
                @sizeOf(AtomObjectBody) > storage.len - start)
                return error.EventStorageFull;
            @memset(storage[used.*..start], 0);
            const object: *align(1) AtomObjectBody =
                @ptrCast(storage[start..].ptr);
            object.* = .{
                .id = 0,
                .otype = if (succeeded)
                    self.patch_ack_type
                else
                    self.patch_error_type,
            };
            var cursor = start + @sizeOf(AtomObjectBody);
            try appendPatchAtomProperty(
                storage,
                &cursor,
                self.patch_sequence_number_key,
                self.atom_int_type,
                std.mem.asBytes(&sequence_number),
            );
            used.* = cursor;
            return storage[start..cursor];
        }

        fn appendPatchSetResponse(
            self: *const Self,
            storage: *[patch_response_capacity]u8,
            used: *usize,
            property_index: usize,
            sequence_number: ?i32,
            subject: ?Urid,
            value: PatchValue,
        ) ![]const u8 {
            const start = alignAtomSize(used.*) orelse
                return error.EventStorageFull;
            if (start > storage.len or
                @sizeOf(AtomObjectBody) > storage.len - start)
                return error.EventStorageFull;
            @memset(storage[used.*..start], 0);
            const object: *align(1) AtomObjectBody =
                @ptrCast(storage[start..].ptr);
            object.* = .{ .id = 0, .otype = self.patch_set_type };
            var cursor = start + @sizeOf(AtomObjectBody);
            if (subject) |item| {
                try appendPatchAtomProperty(
                    storage,
                    &cursor,
                    self.patch_subject_key,
                    self.atom_urid_type,
                    std.mem.asBytes(&item),
                );
            }
            const property_urid =
                self.patch_property_urids[property_index];
            try appendPatchAtomProperty(
                storage,
                &cursor,
                self.patch_property_key,
                self.atom_urid_type,
                std.mem.asBytes(&property_urid),
            );
            if (sequence_number) |number| {
                try appendPatchAtomProperty(
                    storage,
                    &cursor,
                    self.patch_sequence_number_key,
                    self.atom_int_type,
                    std.mem.asBytes(&number),
                );
            }
            try self.appendPatchValueProperty(
                storage,
                &cursor,
                value,
            );
            used.* = cursor;
            return storage[start..cursor];
        }

        fn appendPatchValueProperty(
            self: *const Self,
            storage: *[patch_response_capacity]u8,
            cursor: *usize,
            value: PatchValue,
        ) !void {
            switch (value) {
                .boolean => |item| {
                    const encoded: i32 = @intFromBool(item);
                    try appendPatchAtomProperty(
                        storage,
                        cursor,
                        self.patch_value_key,
                        self.atom_bool_type,
                        std.mem.asBytes(&encoded),
                    );
                },
                .int => |item| try appendPatchAtomProperty(
                    storage,
                    cursor,
                    self.patch_value_key,
                    self.atom_int_type,
                    std.mem.asBytes(&item),
                ),
                .long => |item| try appendPatchAtomProperty(
                    storage,
                    cursor,
                    self.patch_value_key,
                    self.atom_long_type,
                    std.mem.asBytes(&item),
                ),
                .float => |item| {
                    if (!std.math.isFinite(item))
                        return error.InvalidPatchValue;
                    try appendPatchAtomProperty(
                        storage,
                        cursor,
                        self.patch_value_key,
                        self.atom_float_type,
                        std.mem.asBytes(&item),
                    );
                },
                .double => |item| {
                    if (!std.math.isFinite(item))
                        return error.InvalidPatchValue;
                    try appendPatchAtomProperty(
                        storage,
                        cursor,
                        self.patch_value_key,
                        self.atom_double_type,
                        std.mem.asBytes(&item),
                    );
                },
                .string => |item| try appendPatchStringProperty(
                    storage,
                    cursor,
                    self.patch_value_key,
                    self.atom_string_type,
                    item,
                ),
                .path => |item| try appendPatchStringProperty(
                    storage,
                    cursor,
                    self.patch_value_key,
                    self.atom_path_type,
                    blk: {
                        if (!std.fs.path.isAbsolute(item))
                            return error.InvalidPatchValue;
                        break :blk item;
                    },
                ),
                .uri => |item| try appendPatchStringProperty(
                    storage,
                    cursor,
                    self.patch_value_key,
                    self.atom_uri_type,
                    item,
                ),
                .urid => |item| {
                    if (item == 0) return error.InvalidPatchValue;
                    try appendPatchAtomProperty(
                        storage,
                        cursor,
                        self.patch_value_key,
                        self.atom_urid_type,
                        std.mem.asBytes(&item),
                    );
                },
            }
        }

        fn readTimeProperty(
            self: *const Self,
            update: *PositionUpdate,
            key: Urid,
            value_type: Urid,
            value: []const u8,
        ) !void {
            if (key == self.time_bar_key) {
                if (update.bar != null)
                    return error.InvalidTransport;
                update.bar = try self.readLong(value_type, value);
            } else if (key == self.time_bar_beat_key) {
                if (update.bar_beat != null)
                    return error.InvalidTransport;
                update.bar_beat = try self.readFloat(value_type, value);
            } else if (key == self.time_beat_key) {
                if (update.beat != null)
                    return error.InvalidTransport;
                update.beat = try self.readDouble(value_type, value);
            } else if (key == self.time_beat_unit_key) {
                if (update.beat_unit != null)
                    return error.InvalidTransport;
                const raw = try self.readInt(value_type, value);
                if (raw <= 0) return error.InvalidTransport;
                update.beat_unit = @intCast(raw);
            } else if (key == self.time_beats_per_bar_key) {
                if (update.beats_per_bar != null)
                    return error.InvalidTransport;
                update.beats_per_bar =
                    try self.readFloat(value_type, value);
            } else if (key == self.time_beats_per_minute_key) {
                if (update.beats_per_minute != null)
                    return error.InvalidTransport;
                update.beats_per_minute =
                    try self.readFloat(value_type, value);
            } else if (key == self.time_frame_key) {
                if (update.frame != null)
                    return error.InvalidTransport;
                update.frame = try self.readLong(value_type, value);
            } else if (key == self.time_frames_per_second_key) {
                if (update.frames_per_second != null)
                    return error.InvalidTransport;
                update.frames_per_second =
                    try self.readFloat(value_type, value);
            } else if (key == self.time_speed_key) {
                if (update.speed != null)
                    return error.InvalidTransport;
                update.speed = try self.readFloat(value_type, value);
            }
        }

        fn readFloat(
            self: *const Self,
            value_type: Urid,
            value: []const u8,
        ) !f64 {
            if (value_type != self.atom_float_type or
                value.len != @sizeOf(f32))
                return error.InvalidTransport;
            const result = @as(
                *align(1) const f32,
                @ptrCast(value.ptr),
            ).*;
            if (!std.math.isFinite(result))
                return error.InvalidTransport;
            return result;
        }

        fn readDouble(
            self: *const Self,
            value_type: Urid,
            value: []const u8,
        ) !f64 {
            if (value_type != self.atom_double_type or
                value.len != @sizeOf(f64))
                return error.InvalidTransport;
            const result = @as(
                *align(1) const f64,
                @ptrCast(value.ptr),
            ).*;
            if (!std.math.isFinite(result))
                return error.InvalidTransport;
            return result;
        }

        fn readInt(
            self: *const Self,
            value_type: Urid,
            value: []const u8,
        ) !i32 {
            if (value_type != self.atom_int_type or
                value.len != @sizeOf(i32))
                return error.InvalidTransport;
            return @as(
                *align(1) const i32,
                @ptrCast(value.ptr),
            ).*;
        }

        fn readLong(
            self: *const Self,
            value_type: Urid,
            value: []const u8,
        ) !i64 {
            if (value_type != self.atom_long_type or
                value.len != @sizeOf(i64))
                return error.InvalidTransport;
            return @as(
                *align(1) const i64,
                @ptrCast(value.ptr),
            ).*;
        }

        fn applyTimePosition(
            self: *Self,
            update: PositionUpdate,
        ) !void {
            if (update.frames_per_second) |rate| {
                if (rate <= 0.0 or
                    !approximatelyEqual(rate, self.sample_rate))
                    return error.InvalidTransport;
            }
            var next_beats_per_bar = self.beats_per_bar;
            var next_beat_unit = self.beat_unit;
            var next_bar = self.bar;
            var next_bar_beat = self.bar_beat;
            var next_beat = self.beat;
            var next_speed = self.transport_speed;
            if (update.beats_per_bar) |value| {
                if (value <= 0.0) return error.InvalidTransport;
                next_beats_per_bar = value;
            }
            if (update.beat_unit) |value|
                next_beat_unit = value;
            if (update.bar) |value| next_bar = value;
            if (update.bar_beat) |value| {
                if (value < 0.0) return error.InvalidTransport;
                next_bar_beat = value;
            }
            if (update.beat) |value| next_beat = value;
            if (update.speed) |value| next_speed = value;

            var transport = self.transport orelse
                process_api.Transport{ .project_time_samples = 0 };
            transport.state_valid = true;
            transport.playing = next_speed != 0.0;
            if (update.frame) |value|
                transport.project_time_samples = value;
            if (update.beats_per_minute) |value|
                transport.tempo_bpm = value;

            if (next_beat_unit) |unit| {
                const quarter_notes_per_beat =
                    4.0 / @as(f64, @floatFromInt(unit));
                if (next_beat) |value| {
                    transport.project_quarter_notes =
                        value * quarter_notes_per_beat;
                } else if (next_bar) |bar| {
                    if (next_beats_per_bar) |per_bar| {
                        const within_bar = next_bar_beat orelse 0.0;
                        if (within_bar > per_bar)
                            return error.InvalidTransport;
                        transport.project_quarter_notes =
                            (@as(f64, @floatFromInt(bar)) *
                                per_bar +
                                within_bar) *
                            quarter_notes_per_beat;
                    }
                }
                if (next_bar) |bar| {
                    if (next_beats_per_bar) |per_bar| {
                        transport.bar_position_quarter_notes =
                            @as(f64, @floatFromInt(bar)) *
                            per_bar *
                            quarter_notes_per_beat;
                    }
                }
            }
            transport.time_signature = timeSignature(
                next_beats_per_bar,
                next_beat_unit,
            );
            if (!transport.valid())
                return error.InvalidTransport;
            self.beats_per_bar = next_beats_per_bar;
            self.beat_unit = next_beat_unit;
            self.bar = next_bar;
            self.bar_beat = next_bar_beat;
            self.beat = next_beat;
            self.transport_speed = next_speed;
            self.transport = transport;
        }

        fn advanceTransport(
            self: *Self,
            frame_count: usize,
        ) !void {
            var transport = self.transport orelse return;
            const frame_delta =
                @as(f64, @floatFromInt(frame_count)) *
                self.transport_speed;
            const next_frame =
                @as(f64, @floatFromInt(
                    transport.project_time_samples,
                )) +
                frame_delta;
            const rounded_frame = @round(next_frame);
            if (!std.math.isFinite(rounded_frame) or
                rounded_frame < -9_223_372_036_854_775_808.0 or
                rounded_frame >= 9_223_372_036_854_775_808.0)
                return error.InvalidTransport;
            transport.project_time_samples =
                @intFromFloat(rounded_frame);
            if (transport.project_quarter_notes) |position| {
                if (transport.tempo_bpm) |tempo| {
                    const quarter_note_delta =
                        @as(f64, @floatFromInt(frame_count)) /
                        self.sample_rate *
                        tempo /
                        60.0 *
                        self.transport_speed;
                    const next_position = position + quarter_note_delta;
                    if (!std.math.isFinite(next_position))
                        return error.InvalidTransport;
                    transport.project_quarter_notes = next_position;
                    if (transport.time_signature) |signature| {
                        const quarter_notes_per_bar =
                            @as(f64, @floatFromInt(signature.numerator)) *
                            4.0 /
                            @as(f64, @floatFromInt(signature.denominator));
                        transport.bar_position_quarter_notes =
                            @floor(
                                next_position / quarter_notes_per_bar,
                            ) *
                            quarter_notes_per_bar;
                    }
                }
            }
            if (!transport.valid())
                return error.InvalidTransport;
            self.transport = transport;
        }

        fn writeOutputEvents(
            self: *const Self,
            events: []const process_api.Event,
        ) !void {
            const port = event_output_port orelse return;
            const raw = self.ports[port] orelse return;
            const sequence: *align(1) AtomSequence = @ptrCast(raw);
            const capacity: usize = sequence.atom.size;
            if (capacity < @sizeOf(AtomSequenceBody))
                return error.EventStorageFull;
            sequence.atom = .{
                .size = @sizeOf(AtomSequenceBody),
                .type = self.sequence_type,
            };
            sequence.body = .{ .unit = 0, .pad = 0 };
            const bytes: [*]u8 = @ptrCast(&sequence.body);
            var offset: usize = @sizeOf(AtomSequenceBody);
            for (events) |event| {
                if (try process_api.Midi1Message.fromEvent(event)) |message| {
                    try self.appendOutputAtomEvent(
                        bytes,
                        capacity,
                        &offset,
                        event.sample_offset,
                        self.midi_event_type,
                        message.bytes(),
                    );
                } else if (event.kind == .data and
                    event.data_type == self.midi_event_type)
                {
                    try validateMidiEvent(event.data);
                    try self.appendOutputAtomEvent(
                        bytes,
                        capacity,
                        &offset,
                        event.sample_offset,
                        self.midi_event_type,
                        event.data,
                    );
                } else if (event.kind == .data and
                    event.data_type != 0)
                {
                    try self.appendOutputAtomEvent(
                        bytes,
                        capacity,
                        &offset,
                        event.sample_offset,
                        event.data_type,
                        event.data,
                    );
                }
            }
            sequence.atom.size = @intCast(offset);
        }

        fn appendOutputAtomEvent(
            _: *const Self,
            bytes: [*]u8,
            capacity: usize,
            offset: *usize,
            sample_offset: usize,
            atom_type: Urid,
            payload: []const u8,
        ) !void {
            const raw_event_size = std.math.add(
                usize,
                @sizeOf(AtomEvent),
                payload.len,
            ) catch return error.EventStorageFull;
            const padded_size = alignAtomSize(raw_event_size) orelse
                return error.EventStorageFull;
            if (offset.* > capacity or
                padded_size > capacity - offset.*)
                return error.EventStorageFull;
            const atom_event: *align(1) AtomEvent =
                @ptrCast(bytes + offset.*);
            atom_event.* = .{
                .time = .{ .frames = @intCast(sample_offset) },
                .body = .{
                    .size = @intCast(payload.len),
                    .type = atom_type,
                },
            };
            @memcpy(
                bytes[offset.* + @sizeOf(AtomEvent) .. offset.* + @sizeOf(AtomEvent) + payload.len],
                payload,
            );
            @memset(
                bytes[offset.* + raw_event_size .. offset.* + padded_size],
                0,
            );
            offset.* += padded_size;
        }

        fn bindInputChannels(
            self: *const Self,
            sample_count: usize,
            main: *[main_input_channel_count][]const f32,
            auxiliary: *[auxiliary_input_channel_count][]const f32,
        ) !void {
            for (0..main_input_channel_count) |index| {
                const raw = self.ports[
                    audio_input_port_start + index
                ] orelse return error.UnconnectedPort;
                if (@intFromPtr(raw) % @alignOf(f32) != 0)
                    return error.InvalidContext;
                const samples: [*]const f32 =
                    @ptrCast(@alignCast(raw));
                main[index] = samples[0..sample_count];
            }
            for (0..auxiliary_input_channel_count) |index| {
                const raw = self.ports[
                    audio_input_port_start +
                        main_input_channel_count +
                        index
                ] orelse return error.UnconnectedPort;
                if (@intFromPtr(raw) % @alignOf(f32) != 0)
                    return error.InvalidContext;
                const samples: [*]const f32 =
                    @ptrCast(@alignCast(raw));
                auxiliary[index] = samples[0..sample_count];
            }
        }

        fn bindOutputChannels(
            self: *const Self,
            sample_count: usize,
            main: *[main_output_channel_count][]f32,
            auxiliary: *[auxiliary_output_channel_count][]f32,
        ) !void {
            for (0..main_output_channel_count) |index| {
                const raw = self.ports[
                    audio_output_port_start + index
                ] orelse return error.UnconnectedPort;
                if (@intFromPtr(raw) % @alignOf(f32) != 0)
                    return error.InvalidContext;
                const samples: [*]f32 = @ptrCast(@alignCast(raw));
                main[index] = samples[0..sample_count];
            }
            for (0..auxiliary_output_channel_count) |index| {
                const raw = self.ports[
                    audio_output_port_start +
                        main_output_channel_count +
                        index
                ] orelse return error.UnconnectedPort;
                if (@intFromPtr(raw) % @alignOf(f32) != 0)
                    return error.InvalidContext;
                const samples: [*]f32 = @ptrCast(@alignCast(raw));
                auxiliary[index] = samples[0..sample_count];
            }
        }

        fn readControlChanges(
            self: *Self,
            changes: *[parameter_count]process_api.ParameterChange,
        ) !void {
            const set = &self.runtime.instance.spec.parameter_set;
            for (0..parameter_count) |index| {
                const port = controlPort(index) orelse
                    return error.InvalidControl;
                const raw = self.ports[port] orelse
                    return error.UnconnectedPort;
                if (@intFromPtr(raw) % @alignOf(f32) != 0)
                    return error.InvalidControl;
                const value: *const f32 = @ptrCast(@alignCast(raw));
                const plain: f64 = value.*;
                if (!std.math.isFinite(plain))
                    return error.InvalidControl;
                var normalized: f64 = undefined;
                if (self.program_overrides[index]) |program_value| {
                    if (self.program_control_baselines[index]) |baseline| {
                        if (value.* == baseline) {
                            normalized = program_value;
                        } else {
                            self.program_overrides[index] = null;
                            self.program_control_baselines[index] = null;
                            normalized = set.normalizedFromPlain(
                                index,
                                plain,
                            ) orelse return error.InvalidControl;
                        }
                    } else {
                        self.program_control_baselines[index] = value.*;
                        normalized = program_value;
                    }
                } else {
                    normalized = set.normalizedFromPlain(
                        index,
                        plain,
                    ) orelse return error.InvalidControl;
                }
                const id = set.id(index) orelse
                    return error.InvalidControl;
                changes[index] = .{
                    .id = id,
                    .sample_offset = 0,
                    .normalized = normalized,
                };
            }
        }

        fn readProcessMode(
            self: *const Self,
        ) !process_api.ProcessMode {
            const port = freewheeling_input_port orelse
                return .realtime;
            const raw = self.ports[port] orelse
                return error.UnconnectedPort;
            if (@intFromPtr(raw) % @alignOf(f32) != 0)
                return error.InvalidControl;
            const value: *const f32 = @ptrCast(@alignCast(raw));
            if (!std.math.isFinite(value.*))
                return error.InvalidControl;
            return if (value.* > 0.0) .offline else .realtime;
        }

        fn clearConnectedOutputs(
            self: *const Self,
            sample_count: usize,
        ) void {
            for (0..output_channel_count) |index| {
                const raw = self.ports[
                    audio_output_port_start + index
                ] orelse continue;
                const samples: [*]align(1) f32 = @ptrCast(raw);
                @memset(samples[0..sample_count], 0.0);
            }
        }

        fn clearConnectedEventOutput(self: *const Self) void {
            const port = event_output_port orelse return;
            const raw = self.ports[port] orelse return;
            const sequence: *align(1) AtomSequence = @ptrCast(raw);
            const capacity: usize = sequence.atom.size;
            sequence.atom = .{
                .size = if (capacity >= @sizeOf(AtomSequenceBody))
                    @sizeOf(AtomSequenceBody)
                else
                    0,
                .type = self.sequence_type,
            };
            if (capacity >= @sizeOf(AtomSequenceBody)) {
                sequence.body = .{
                    .unit = self.frame_time_type,
                    .pad = 0,
                };
            }
        }

        fn writeLatency(self: *const Self) void {
            const raw = self.ports[latency_output_port] orelse return;
            const latency: *align(1) f32 = @ptrCast(raw);
            latency.* = @floatFromInt(self.runtime.latencySamples());
        }
    };
}

fn totalLayoutChannels(
    comptime layouts: []const plugin_api.AudioBusLayout,
) usize {
    var total: usize = 0;
    for (layouts) |layout| total += layout.channelCount();
    return total;
}

fn validPluginUri(comptime uri: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, uri, ':') orelse
        return false;
    if (colon == 0) return false;
    for (uri) |byte| {
        if (byte <= 0x20 or byte >= 0x7f) return false;
    }
    return true;
}

fn featureWithUri(
    features: ?[*:null]const ?*const Feature,
    wanted_uri: []const u8,
) ?*const Feature {
    const list = features orelse return null;
    for (0..256) |index| {
        const feature = list[index] orelse return null;
        if (std.mem.eql(
            u8,
            std.mem.span(feature.URI),
            wanted_uri,
        )) return feature;
    }
    return null;
}

fn featureValue(
    comptime T: type,
    feature: *const Feature,
) ?*const T {
    const raw = feature.data orelse return null;
    if (@intFromPtr(raw) % @alignOf(T) != 0) return null;
    return @ptrCast(@alignCast(raw));
}

fn statePathFeatures(
    features: ?[*:null]const ?*const Feature,
    require_make_path: bool,
) ?StatePathFeatures {
    const map_path = featureStruct(
        StateMapPath,
        features,
        state_map_path_uri,
    ) orelse return null;
    const free_path = featureStruct(
        StateFreePath,
        features,
        state_free_path_uri,
    ) orelse return null;
    const make_path = featureStruct(
        StateMakePath,
        features,
        state_make_path_uri,
    );
    if (require_make_path and make_path == null) return null;
    return .{
        .map_path = map_path,
        .make_path = make_path,
        .free_path = free_path,
    };
}

fn featureStruct(
    comptime T: type,
    features: ?[*:null]const ?*const Feature,
    wanted_uri: []const u8,
) ?*const T {
    const feature = featureWithUri(features, wanted_uri) orelse
        return null;
    return featureValue(T, feature);
}

fn layoutChannelCounts(
    comptime layouts: []const plugin_api.AudioBusLayout,
) [layouts.len]usize {
    var counts: [layouts.len]usize = undefined;
    for (layouts, 0..) |layout, index|
        counts[index] = layout.channelCount();
    return counts;
}

fn statusForError(err: anyerror) RunStatus {
    return switch (err) {
        error.Inactive => .inactive,
        error.BlockTooLarge => .block_too_large,
        error.UnconnectedPort => .unconnected_port,
        error.InvalidControl => .invalid_control,
        error.InvalidContext => .invalid_context,
        error.InvalidEvents,
        error.EventStorageFull,
        error.InvalidTransport,
        error.UnsupportedTransportOffset,
        => .invalid_context,
        error.ProcessingFailed => .processing_failed,
        else => .processing_failed,
    };
}

fn alignAtomSize(size: usize) ?usize {
    return std.mem.alignForward(usize, size, 8);
}

fn validBlockLengths(
    minimum: usize,
    maximum: usize,
    nominal: usize,
    compile_time_maximum: usize,
) bool {
    return maximum > 0 and
        maximum <= compile_time_maximum and
        minimum <= nominal and
        nominal <= maximum;
}

fn validateMidiEvent(payload: []const u8) !void {
    if (payload.len == 0 or
        payload.len > process_api.max_data_event_bytes)
        return error.InvalidEvents;
    const status = payload[0];
    if (status < 0x80) return error.InvalidEvents;
    if (status < 0xf0) {
        _ = process_api.Midi1Message.parse(payload) catch
            return error.InvalidEvents;
        if (status & 0xf0 == 0x90 and payload[2] == 0)
            return error.InvalidEvents;
        return;
    }
    const expected_length: ?usize = switch (status) {
        0xf0 => null,
        0xf1, 0xf3 => 2,
        0xf2 => 3,
        0xf6, 0xf8, 0xfa, 0xfb, 0xfc, 0xfe, 0xff => 1,
        else => return error.InvalidEvents,
    };
    if (expected_length) |length| {
        if (payload.len != length) return error.InvalidEvents;
        for (payload[1..]) |byte| {
            if (byte >= 0x80) return error.InvalidEvents;
        }
        return;
    }
    if (payload.len < 2 or payload[payload.len - 1] != 0xf7)
        return error.InvalidEvents;
    for (payload[1 .. payload.len - 1]) |byte| {
        if (byte >= 0x80) return error.InvalidEvents;
    }
}

const PositionUpdate = struct {
    bar: ?i64 = null,
    bar_beat: ?f64 = null,
    beat: ?f64 = null,
    beat_unit: ?u32 = null,
    beats_per_bar: ?f64 = null,
    beats_per_minute: ?f64 = null,
    frame: ?i64 = null,
    frames_per_second: ?f64 = null,
    speed: ?f64 = null,
};

const TimedPositionUpdate = struct {
    sample_offset: usize,
    update: PositionUpdate,
};

const PatchRequestKind = enum {
    get,
    set,
    put,
    insert,
    patch,
    delete,
    copy,
    move,
};

const RawPatchValue = struct {
    atom_type: Urid,
    body: []const u8,
};

const TimedPatchRequest = struct {
    sample_offset: usize,
    kind: PatchRequestKind,
    property_index: ?usize = null,
    value: ?PatchValue = null,
    sequence_number: ?i32 = null,
    subject: ?Urid = null,
    graph_subjects: [maximum_patch_graph_subject_count]Urid =
        [_]Urid{0} ** maximum_patch_graph_subject_count,
    graph_subject_count: usize = 0,
    destination: ?Urid = null,
    context: ?Urid = null,
    body: ?RawPatchValue = null,
    add: ?RawPatchValue = null,
    remove: ?RawPatchValue = null,
};

fn patchGraphRequest(request: *const TimedPatchRequest) !PatchGraphRequest {
    if (request.graph_subject_count == 0 or
        request.graph_subject_count > request.graph_subjects.len)
        return error.InvalidPatch;
    const subjects =
        request.graph_subjects[0..request.graph_subject_count];
    const subject = subjects[0];
    return .{
        .operation = switch (request.kind) {
            .put => .{ .put = .{
                .subject = subject,
                .body = patchAtomValue(
                    request.body orelse return error.InvalidPatch,
                ),
            } },
            .insert => .{ .insert = .{
                .subject = subject,
                .body = patchAtomValue(
                    request.body orelse return error.InvalidPatch,
                ),
            } },
            .patch => .{ .patch = .{
                .subject = subject,
                .add = patchAtomValue(
                    request.add orelse return error.InvalidPatch,
                ),
                .remove = patchAtomValue(
                    request.remove orelse return error.InvalidPatch,
                ),
            } },
            .delete => .{ .delete = .{ .subjects = subjects } },
            .copy => .{ .copy = .{
                .subjects = subjects,
                .destination = request.destination orelse
                    return error.InvalidPatch,
            } },
            .move => .{ .move = .{
                .subject = subject,
                .destination = request.destination orelse
                    return error.InvalidPatch,
            } },
            .get, .set => return error.InvalidPatch,
        },
        .context = request.context,
        .sequence_number = request.sequence_number,
    };
}

fn patchAtomValue(raw: RawPatchValue) PatchAtomValue {
    return .{
        .atom_type = raw.atom_type,
        .body = raw.body,
    };
}

const InputReadResult = struct {
    event_count: usize = 0,
    position_count: usize = 0,
    patch_count: usize = 0,
};

fn appendPatchAtomProperty(
    storage: anytype,
    cursor: *usize,
    key: Urid,
    atom_type: Urid,
    body: []const u8,
) !void {
    const raw_size = std.math.add(
        usize,
        @sizeOf(AtomPropertyBody),
        body.len,
    ) catch return error.EventStorageFull;
    const padded_size = alignAtomSize(raw_size) orelse
        return error.EventStorageFull;
    if (cursor.* > storage.len or
        padded_size > storage.len - cursor.*)
        return error.EventStorageFull;
    const property: *align(1) AtomPropertyBody =
        @ptrCast(storage[cursor.*..].ptr);
    property.* = .{
        .key = key,
        .context = 0,
        .value = .{
            .size = @intCast(body.len),
            .type = atom_type,
        },
    };
    @memcpy(
        storage[cursor.* + @sizeOf(AtomPropertyBody) .. cursor.* + @sizeOf(AtomPropertyBody) + body.len],
        body,
    );
    @memset(
        storage[cursor.* + raw_size .. cursor.* + padded_size],
        0,
    );
    cursor.* += padded_size;
}

fn appendPatchStringProperty(
    storage: anytype,
    cursor: *usize,
    key: Urid,
    atom_type: Urid,
    value: []const u8,
) !void {
    if (!std.unicode.utf8ValidateSlice(value) or
        std.mem.indexOfScalar(u8, value, 0) != null)
        return error.InvalidPatchValue;
    const body_size = std.math.add(
        usize,
        value.len,
        1,
    ) catch return error.EventStorageFull;
    const raw_size = std.math.add(
        usize,
        @sizeOf(AtomPropertyBody),
        body_size,
    ) catch return error.EventStorageFull;
    const padded_size = alignAtomSize(raw_size) orelse
        return error.EventStorageFull;
    if (cursor.* > storage.len or
        padded_size > storage.len - cursor.*)
        return error.EventStorageFull;
    const property: *align(1) AtomPropertyBody =
        @ptrCast(storage[cursor.*..].ptr);
    property.* = .{
        .key = key,
        .context = 0,
        .value = .{
            .size = @intCast(body_size),
            .type = atom_type,
        },
    };
    const start = cursor.* + @sizeOf(AtomPropertyBody);
    @memcpy(storage[start .. start + value.len], value);
    @memset(
        storage[start + value.len .. cursor.* + padded_size],
        0,
    );
    cursor.* += padded_size;
}

const WorkerRespondContext = struct {
    respond: WorkerRespondFunction,
    handle: WorkerRespondHandle,
};

fn sendWorkerResponse(
    context: *anyopaque,
    data: []const u8,
) WorkerStatus {
    const response: *const WorkerRespondContext =
        @ptrCast(@alignCast(context));
    const raw: ?*const anyopaque =
        if (data.len == 0) null else data.ptr;
    return response.respond(
        response.handle,
        @intCast(data.len),
        raw,
    );
}

fn workerBytes(
    size: u32,
    data: ?*const anyopaque,
    maximum_size: usize,
) ![]const u8 {
    if (size > maximum_size) return error.WorkerNoSpace;
    if (size == 0) return &.{};
    const raw = data orelse return error.InvalidWorkerData;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..size];
}

fn workerStatusForBytesError(err: anyerror) WorkerStatus {
    return if (err == error.WorkerNoSpace) .no_space else .unknown;
}

fn approximatelyEqual(a: f64, b: f64) bool {
    const scale = @max(@abs(a), @abs(b));
    return @abs(a - b) <= @max(1.0, scale) * 1.0e-6;
}

fn timeSignature(
    beats_per_bar: ?f64,
    beat_unit: ?u32,
) ?process_api.TimeSignature {
    const numerator_float = beats_per_bar orelse return null;
    const denominator_u32 = beat_unit orelse return null;
    if (numerator_float <= 0.0 or
        numerator_float > std.math.maxInt(u16) or
        numerator_float != @trunc(numerator_float) or
        denominator_u32 == 0 or
        denominator_u32 > std.math.maxInt(u16) or
        !std.math.isPowerOfTwo(denominator_u32))
        return null;
    return .{
        .numerator = @intFromFloat(numerator_float),
        .denominator = @intCast(denominator_u32),
    };
}

const TestStateHost = struct {
    key: Urid = 0,
    value_type: Urid = 0,
    flags: u32 = 0,
    bytes: [4096]u8 = undefined,
    size: usize = 0,
    present: bool = false,
    component_value_type: Urid = 0,
    component_flags: u32 = 0,
    component_bytes: [4096]u8 = undefined,
    component_size: usize = 0,
    component_present: bool = false,
    store_status: StateStatus = .success,
    component_store_status: StateStatus = .success,

    fn map(
        _: ?*anyopaque,
        URI: [*:0]const u8,
    ) callconv(.c) Urid {
        const uri = std.mem.span(URI);
        if (std.mem.eql(u8, uri, atom_chunk_uri)) return 23;
        if (std.mem.eql(u8, uri, atom_sequence_uri)) return 29;
        if (std.mem.eql(u8, uri, atom_frame_time_uri)) return 31;
        if (std.mem.eql(u8, uri, midi_event_uri)) return 37;
        if (std.mem.eql(u8, uri, atom_blank_uri)) return 41;
        if (std.mem.eql(u8, uri, atom_object_uri)) return 43;
        if (std.mem.eql(u8, uri, atom_float_uri)) return 47;
        if (std.mem.eql(u8, uri, atom_double_uri)) return 53;
        if (std.mem.eql(u8, uri, atom_int_uri)) return 59;
        if (std.mem.eql(u8, uri, atom_long_uri)) return 61;
        if (std.mem.eql(u8, uri, time_position_uri)) return 67;
        if (std.mem.eql(u8, uri, time_bar_uri)) return 71;
        if (std.mem.eql(u8, uri, time_bar_beat_uri)) return 73;
        if (std.mem.eql(u8, uri, time_beat_uri)) return 79;
        if (std.mem.eql(u8, uri, time_beat_unit_uri)) return 83;
        if (std.mem.eql(u8, uri, time_beats_per_bar_uri)) return 89;
        if (std.mem.eql(u8, uri, time_beats_per_minute_uri))
            return 97;
        if (std.mem.eql(u8, uri, time_frame_uri)) return 101;
        if (std.mem.eql(u8, uri, time_frames_per_second_uri))
            return 103;
        if (std.mem.eql(u8, uri, time_speed_uri)) return 107;
        if (std.mem.eql(u8, uri, buffer_minimum_block_length_uri))
            return 109;
        if (std.mem.eql(u8, uri, buffer_maximum_block_length_uri))
            return 113;
        if (std.mem.eql(u8, uri, buffer_nominal_block_length_uri))
            return 127;
        if (std.mem.eql(u8, uri, buffer_sequence_size_uri))
            return 131;
        if (std.mem.endsWith(u8, uri, "#parameterState")) return 17;
        if (std.mem.endsWith(u8, uri, "#componentState")) return 19;
        return 0;
    }

    fn store(
        handle: StateHandle,
        key: Urid,
        value: *const anyopaque,
        size: usize,
        value_type: Urid,
        flags: u32,
    ) callconv(.c) StateStatus {
        const raw = handle orelse return .unknown;
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (self.store_status != .success)
            return self.store_status;
        if (key == 19) {
            if (self.component_store_status != .success)
                return self.component_store_status;
            if (size > self.component_bytes.len) return .no_space;
            const source: [*]const u8 = @ptrCast(value);
            @memcpy(
                self.component_bytes[0..size],
                source[0..size],
            );
            self.component_value_type = value_type;
            self.component_flags = flags;
            self.component_size = size;
            self.component_present = true;
            return .success;
        }
        if (size > self.bytes.len) return .no_space;
        const source: [*]const u8 = @ptrCast(value);
        @memcpy(self.bytes[0..size], source[0..size]);
        self.key = key;
        self.value_type = value_type;
        self.flags = flags;
        self.size = size;
        self.present = true;
        return .success;
    }

    fn retrieve(
        handle: StateHandle,
        key: Urid,
        size: *usize,
        value_type: *Urid,
        flags: *u32,
    ) callconv(.c) ?*const anyopaque {
        const raw = handle orelse return null;
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (key == 19) {
            if (!self.component_present) return null;
            size.* = self.component_size;
            value_type.* = self.component_value_type;
            flags.* = self.component_flags;
            return &self.component_bytes;
        }
        if (!self.present or key != self.key) return null;
        size.* = self.size;
        value_type.* = self.value_type;
        flags.* = self.flags;
        return &self.bytes;
    }
};

const TestSequenceBuffer = extern struct {
    sequence: AtomSequence,
    storage: [512]u8,

    fn empty(sequence_type: Urid) TestSequenceBuffer {
        var result = std.mem.zeroes(TestSequenceBuffer);
        result.sequence = .{
            .atom = .{
                .size = @sizeOf(AtomSequenceBody),
                .type = sequence_type,
            },
            .body = .{ .unit = 0, .pad = 0 },
        };
        return result;
    }
};

const TestTimeBuilder = struct {
    buffer: *TestSequenceBuffer,
    event: *AtomEvent,
    payload_start: usize,
    cursor: usize,

    fn init(
        buffer: *TestSequenceBuffer,
        sequence_type: Urid,
        object_type: Urid,
        position_type: Urid,
        frame_offset: i64,
    ) TestTimeBuilder {
        buffer.* = TestSequenceBuffer.empty(sequence_type);
        const bytes: [*]u8 = @ptrCast(&buffer.sequence.body);
        const event_offset = @sizeOf(AtomSequenceBody);
        const event: *AtomEvent = @ptrCast(
            @alignCast(bytes + event_offset),
        );
        event.* = .{
            .time = .{ .frames = frame_offset },
            .body = .{
                .size = @sizeOf(AtomObjectBody),
                .type = object_type,
            },
        };
        const payload_start = event_offset + @sizeOf(AtomEvent);
        const object: *AtomObjectBody = @ptrCast(
            @alignCast(bytes + payload_start),
        );
        object.* = .{ .id = 0, .otype = position_type };
        var result = TestTimeBuilder{
            .buffer = buffer,
            .event = event,
            .payload_start = payload_start,
            .cursor = payload_start + @sizeOf(AtomObjectBody),
        };
        result.finish();
        return result;
    }

    fn append(
        self: *TestTimeBuilder,
        comptime Value: type,
        key: Urid,
        value_type: Urid,
        value: Value,
    ) void {
        const bytes: [*]u8 = @ptrCast(&self.buffer.sequence.body);
        const property: *AtomPropertyBody = @ptrCast(
            @alignCast(bytes + self.cursor),
        );
        property.* = .{
            .key = key,
            .context = 0,
            .value = .{
                .size = @sizeOf(Value),
                .type = value_type,
            },
        };
        const destination = @as(
            *align(1) Value,
            @ptrCast(bytes + self.cursor + @sizeOf(AtomPropertyBody)),
        );
        destination.* = value;
        self.cursor += std.mem.alignForward(
            usize,
            @sizeOf(AtomPropertyBody) + @sizeOf(Value),
            8,
        );
        self.finish();
    }

    fn finish(self: *TestTimeBuilder) void {
        const bytes: [*]u8 = @ptrCast(&self.buffer.sequence.body);
        self.event.body.size = @intCast(
            self.cursor - self.payload_start,
        );
        const event_end = std.mem.alignForward(
            usize,
            @sizeOf(AtomSequenceBody) +
                @sizeOf(AtomEvent) +
                self.event.body.size,
            8,
        );
        @memset(bytes[self.cursor..event_end], 0);
        self.buffer.sequence.atom.size = @intCast(event_end);
    }
};

test "LV2 core ABI has C pointer layout" {
    const pointer_size = @sizeOf(?*anyopaque);
    try std.testing.expectEqual(pointer_size * 2, @sizeOf(Feature));
    try std.testing.expectEqual(pointer_size * 2, @sizeOf(UridMap));
    try std.testing.expectEqual(pointer_size * 2, @sizeOf(UridUnmap));
    try std.testing.expectEqual(pointer_size * 8, @sizeOf(Descriptor));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Atom));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(AtomEvent));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(AtomSequence));
    try std.testing.expectEqual(
        pointer_size,
        @alignOf(Descriptor),
    );
    try std.testing.expectEqual(
        pointer_size * 7,
        @offsetOf(Descriptor, "extension_data"),
    );
    try std.testing.expectEqual(
        @as(usize, 8) + pointer_size,
        @sizeOf(ProgramDescriptor),
    );
    try std.testing.expectEqual(
        pointer_size * 2,
        @sizeOf(ProgramsInterface),
    );
}

test "LV2 URID unmap opt-in binds stable host reverse mappings" {
    const Probe = struct {
        pub const name = "LV2 URID Unmap Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .none;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .none;
        pub const Params = struct {};
        pub const lv2_urid_unmap_required = true;

        urid_unmap: ?*const UridUnmap = null,

        pub fn bindLv2UridUnmap(
            self: *@This(),
            unmap: *const UridUnmap,
        ) void {
            self.urid_unmap = unmap;
        }

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-urid-unmap",
        16,
    );
    const Host = struct {
        fn unmap(
            _: ?*anyopaque,
            urid: Urid,
        ) callconv(.c) ?[*:0]const u8 {
            return switch (urid) {
                23 => "https://example.test/known-type",
                else => null,
            };
        }
    };
    var unmap = UridUnmap{
        .handle = null,
        .unmap = Host.unmap,
    };
    var feature = Feature{
        .URI = urid_unmap_uri,
        .data = &unmap,
    };
    const features = [_:null]?*const Feature{&feature};
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingDescriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-urid-unmap.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    const bound =
        instance.runtime.instance.plugin.urid_unmap orelse
        return error.MissingUridUnmap;
    const known = bound.unmap(bound.handle, 23) orelse
        return error.MissingKnownUri;
    try std.testing.expectEqualStrings(
        "https://example.test/known-type",
        std.mem.span(known),
    );
    try std.testing.expectEqual(
        @as(?[*:0]const u8, null),
        bound.unmap(bound.handle, 24),
    );
}

test "LV2 URID unmap opt-in rejects missing and malformed features" {
    const Probe = struct {
        pub const name = "LV2 URID Unmap Validation Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .none;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .none;
        pub const Params = struct {};
        pub const lv2_urid_unmap_required = true;

        pub fn bindLv2UridUnmap(
            _: *@This(),
            _: *const UridUnmap,
        ) void {}

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-urid-unmap-validation",
        16,
    );
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingDescriptor;
    try std.testing.expectEqual(
        @as(Handle, null),
        descriptor.instantiate(
            descriptor,
            48_000.0,
            "/tmp/lv2-urid-unmap-validation.lv2",
            null,
        ),
    );

    var null_feature = Feature{
        .URI = urid_unmap_uri,
        .data = null,
    };
    const null_features = [_:null]?*const Feature{&null_feature};
    try std.testing.expectEqual(
        @as(Handle, null),
        descriptor.instantiate(
            descriptor,
            48_000.0,
            "/tmp/lv2-urid-unmap-validation.lv2",
            null_features[0..].ptr,
        ),
    );

    var storage: [@sizeOf(UridUnmap) + 1]u8 align(@alignOf(UridUnmap)) = undefined;
    var misaligned_feature = Feature{
        .URI = urid_unmap_uri,
        .data = @ptrCast(&storage[1]),
    };
    const misaligned_features =
        [_:null]?*const Feature{&misaligned_feature};
    try std.testing.expectEqual(
        @as(Handle, null),
        descriptor.instantiate(
            descriptor,
            48_000.0,
            "/tmp/lv2-urid-unmap-validation.lv2",
            misaligned_features[0..].ptr,
        ),
    );
}

test "LV2 Programs enumerates banks and holds selections until host control changes" {
    const Probe = struct {
        pub const name = "LV2 Programs Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const event_input = false;
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 3,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
            mix: @import("parameters.zig").FloatParam = .{
                .id = 7,
                .name = "Mix",
                .min = 0.0,
                .max = 1.0,
                .default = 0.5,
            },
        };
        pub const units: units_api.Config = .{
            .program_lists = &.{
                .{
                    .id = 11,
                    .name = "Factory",
                    .programs = &.{
                        .{
                            .name = "Init",
                            .parameters = &.{
                                .{ .parameter_id = 3, .normalized = 0.5 },
                                .{ .parameter_id = 7, .normalized = 0.5 },
                            },
                        },
                        .{
                            .name = "Wide",
                            .parameters = &.{
                                .{ .parameter_id = 3, .normalized = 1.0 },
                                .{ .parameter_id = 7, .normalized = 0.25 },
                            },
                        },
                    },
                },
                .{
                    .id = 29,
                    .name = "User",
                    .programs = &.{
                        .{
                            .name = "Louder",
                            .parameters = &.{
                                .{ .parameter_id = 3, .normalized = 0.75 },
                            },
                        },
                    },
                },
            },
        };

        pub fn processWithParameterView(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
            view: @import("parameters.zig").ParameterView(Params),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            const gain: f32 = @floatCast(view.load("gain"));
            const mix: f32 = @floatCast(view.load("mix"));
            for (input, output) |sample, *destination|
                destination.* = sample * gain * mix;
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-programs-probe",
        2,
    );
    try std.testing.expect(Adapter.programs_enabled);
    const raw_interface = Adapter.descriptor.extension_data(
        programs_interface_uri,
    ) orelse return error.MissingProgramsInterface;
    const programs: *const ProgramsInterface =
        @ptrCast(@alignCast(raw_interface));
    const handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-programs-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(handle);

    const first = programs.get_program(handle, 0) orelse
        return error.MissingProgram;
    try std.testing.expectEqual(@as(u32, 11), first.bank);
    try std.testing.expectEqual(@as(u32, 0), first.program);
    try std.testing.expectEqualStrings("Init", std.mem.span(first.name));
    const second = programs.get_program(handle, 1) orelse
        return error.MissingProgram;
    try std.testing.expectEqual(@as(u32, 11), second.bank);
    try std.testing.expectEqual(@as(u32, 1), second.program);
    try std.testing.expectEqualStrings("Wide", std.mem.span(second.name));
    const third = programs.get_program(handle, 2) orelse
        return error.MissingProgram;
    try std.testing.expectEqual(@as(u32, 29), third.bank);
    try std.testing.expectEqual(@as(u32, 0), third.program);
    try std.testing.expectEqualStrings("Louder", std.mem.span(third.name));
    try std.testing.expect(programs.get_program(handle, 3) == null);
    try std.testing.expect(programs.get_program(null, 0) == null);
    const misaligned: Handle = @ptrFromInt(@intFromPtr(handle) + 1);
    try std.testing.expect(programs.get_program(misaligned, 0) == null);
    programs.select_program(misaligned, 0, 0);

    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.InvalidHandle;
    const input = [_]f32{ 1.0, -1.0 };
    var output = [_]f32{0.0} ** 2;
    var gain: f32 = 1.0;
    var mix: f32 = 0.5;
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        &gain,
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.control_input_port_start + 1,
        &mix,
    );

    programs.select_program(handle, 11, 1);
    try std.testing.expectEqual(@as(f32, 2.0), gain);
    try std.testing.expectEqual(@as(f32, 0.25), mix);
    try std.testing.expectEqual(
        @as(?f64, 2.0),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        instance.runtime.instance.loadParameterPlainIndex(1),
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.5, -0.5 },
        &output,
    );
    output = @splat(0.0);
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.5, -0.5 },
        &output,
    );

    gain = 0.5;
    output = @splat(0.0);
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.125, -0.125 },
        &output,
    );
    programs.select_program(handle, 99, 0);
    programs.select_program(handle, 11, 99);
    try std.testing.expectEqual(
        @as(?f64, 0.5),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        instance.runtime.instance.loadParameterPlainIndex(1),
    );

    programs.select_program(handle, 29, 0);
    output = @splat(0.0);
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.375 },
        &output,
    );

    var unaligned_storage: [@sizeOf(f32) + @alignOf(f32)]u8 align(@alignOf(f32)) =
        @splat(0);
    Adapter.descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        unaligned_storage[1..].ptr,
    );
    programs.select_program(handle, 11, 0);
    try std.testing.expectEqual(
        @as(?f64, 1.0),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
}

test "LV2 instantiation options constrain block length" {
    const Probe = struct {
        pub const name = "LV2 Options Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const event_input = true;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-options-probe",
        4,
    );
    try std.testing.expect(!Adapter.programs_enabled);
    try std.testing.expect(
        Adapter.descriptor.extension_data(programs_interface_uri) == null,
    );
    var urid_map = UridMap{
        .handle = null,
        .map = TestStateHost.map,
    };
    var map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const minimum: i32 = 0;
    const maximum: i32 = 2;
    const nominal: i32 = 2;
    const sequence_size: i32 = 512;
    const options = [_]OptionsOption{
        .{
            .subject = 123,
            .key = 109,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &minimum,
        },
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &maximum,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &nominal,
        },
        .{
            .key = 131,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &sequence_size,
        },
        .{},
    };
    var options_feature = Feature{
        .URI = options_options_uri,
        .data = @constCast(&options),
    };
    const features = [_:null]?*const Feature{
        &map_feature,
        &options_feature,
    };
    var misaligned_map_storage: [@sizeOf(UridMap) + 1]u8 align(@alignOf(UridMap)) = undefined;
    map_feature.data = @ptrCast(&misaligned_map_storage[1]);
    try std.testing.expectEqual(
        @as(Handle, null),
        Adapter.descriptor.instantiate(
            &Adapter.descriptor,
            48_000.0,
            "/tmp/lv2-options-probe.lv2",
            features[0..].ptr,
        ),
    );
    map_feature.data = &urid_map;

    var misaligned_options_storage: [@sizeOf(OptionsOption) + 1]u8 align(@alignOf(OptionsOption)) = undefined;
    options_feature.data =
        @ptrCast(&misaligned_options_storage[1]);
    try std.testing.expectEqual(
        @as(Handle, null),
        Adapter.descriptor.instantiate(
            &Adapter.descriptor,
            48_000.0,
            "/tmp/lv2-options-probe.lv2",
            features[0..].ptr,
        ),
    );
    options_feature.data = @constCast(&options);

    const handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-options-probe.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(handle);

    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        @as(usize, 2),
        instance.configuredMaximumFrames(),
    );
    try std.testing.expectEqual(
        @as(?usize, 512),
        instance.configuredSequenceSize(),
    );
    try std.testing.expect(
        Adapter.descriptor.extension_data(null) == null,
    );
    const raw_options_interface =
        Adapter.descriptor.extension_data(
            options_interface_uri,
        ) orelse return error.MissingOptionsInterface;
    const runtime_options: *const OptionsInterface =
        @ptrCast(@alignCast(raw_options_interface));
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.get(handle, null),
    );
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.set(handle, null),
    );
    const map_only_features = [_:null]?*const Feature{&map_feature};
    const default_handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-options-probe.lv2",
        map_only_features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(default_handle);
    const default_instance = Adapter.instanceFromHandle(default_handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        @as(?usize, null),
        default_instance.configuredSequenceSize(),
    );
    var missing_sequence_query = [_]OptionsOption{
        .{ .key = 131 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_unknown,
        runtime_options.get(default_handle, &missing_sequence_query),
    );
    var queries = [_]OptionsOption{
        .{ .subject = 91, .key = 109 },
        .{ .subject = 92, .key = 113 },
        .{ .subject = 93, .key = 127 },
        .{ .subject = 94, .key = 131 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.get(handle, &queries),
    );
    try std.testing.expectEqual(@as(u32, @sizeOf(i32)), queries[0].size);
    try std.testing.expectEqual(@as(Urid, 59), queries[0].type);
    try std.testing.expectEqual(
        @as(i32, 0),
        @as(
            *align(1) const i32,
            @ptrCast(queries[0].value.?),
        ).*,
    );
    try std.testing.expectEqual(
        @as(i32, 2),
        @as(
            *align(1) const i32,
            @ptrCast(queries[1].value.?),
        ).*,
    );
    try std.testing.expectEqual(
        @as(i32, 2),
        @as(
            *align(1) const i32,
            @ptrCast(queries[2].value.?),
        ).*,
    );
    try std.testing.expectEqual(
        @as(i32, 512),
        @as(
            *align(1) const i32,
            @ptrCast(queries[3].value.?),
        ).*,
    );

    var unknown_query = [_]OptionsOption{
        .{ .key = 999 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_key,
        runtime_options.get(handle, &unknown_query),
    );
    var malformed_query = [_]OptionsOption{
        .{ .key = 113, .size = 1 },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.get(handle, &malformed_query),
    );
    var unsupported_subject_query = [_]OptionsOption{
        .{
            .context = @intFromEnum(OptionsContext.port),
            .subject = 0,
            .key = 113,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_subject,
        runtime_options.get(handle, &unsupported_subject_query),
    );

    const expanded_maximum: i32 = 3;
    const expanded_nominal: i32 = 3;
    const expanded_sequence_size: i32 = 1024;
    const expanded_options = [_]OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &expanded_maximum,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &expanded_nominal,
        },
        .{
            .key = 131,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &expanded_sequence_size,
        },
        .{},
    };
    const duplicate_runtime_options = [_]OptionsOption{
        expanded_options[0],
        expanded_options[0],
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &duplicate_runtime_options),
    );
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &expanded_options),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        instance.configuredMaximumFrames(),
    );
    try std.testing.expectEqual(
        @as(?usize, 1024),
        instance.configuredSequenceSize(),
    );
    const input = [_]f32{ 0.25, -0.5, 0.75 };
    var output = [_]f32{0.0} ** input.len;
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    Adapter.descriptor.run(handle, 3);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &input,
        &output,
    );
    const active_sequence_size: i32 = 2048;
    const active_sequence_options = [_]OptionsOption{
        .{
            .key = 131,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &active_sequence_size,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &active_sequence_options),
    );
    try std.testing.expectEqual(
        @as(?usize, 2048),
        instance.configuredSequenceSize(),
    );
    const invalid_sequence_size: i32 = -1;
    const invalid_sequence_options = [_]OptionsOption{
        .{
            .key = 131,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &invalid_sequence_size,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &invalid_sequence_options),
    );
    try std.testing.expectEqual(
        @as(?usize, 2048),
        instance.configuredSequenceSize(),
    );

    const reduced_maximum: i32 = 2;
    const reduced_nominal: i32 = 2;
    const reduced_options = [_]OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &reduced_maximum,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &reduced_nominal,
        },
        .{},
    };
    try std.testing.expectEqual(
        options_status_bad_value,
        runtime_options.set(handle, &reduced_options),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        instance.configuredMaximumFrames(),
    );
    if (Adapter.descriptor.deactivate) |deactivate|
        deactivate(handle);
    try std.testing.expectEqual(
        options_status_success,
        runtime_options.set(handle, &reduced_options),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        instance.configuredMaximumFrames(),
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    output = @splat(1.0);
    Adapter.descriptor.run(handle, 3);
    try std.testing.expectEqual(
        RunStatus.block_too_large,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0, 0.0 },
        &output,
    );

    const excessive_maximum: i32 = 5;
    const excessive_options = [_]OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &excessive_maximum,
        },
        .{},
    };
    options_feature.data = @constCast(&excessive_options);
    try std.testing.expect(Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-options-probe.lv2",
        features[0..].ptr,
    ) == null);

    const wrong_type_options = [_]OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 53,
            .value = &maximum,
        },
        .{},
    };
    options_feature.data = @constCast(&wrong_type_options);
    try std.testing.expect(Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-options-probe.lv2",
        features[0..].ptr,
    ) == null);

    const duplicate_options = [_]OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &maximum,
        },
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &maximum,
        },
        .{},
    };
    options_feature.data = @constCast(&duplicate_options);
    try std.testing.expect(Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-options-probe.lv2",
        features[0..].ptr,
    ) == null);
}

test "LV2 state path features own mapped resolved and generated paths" {
    const Host = struct {
        storage: [128]u8 = @splat(0),
        free_count: usize = 0,
        return_empty: bool = false,

        fn abstractPath(
            handle: StateHandle,
            path: [*:0]const u8,
        ) callconv(.c) ?[*:0]u8 {
            const self: *@This() = @ptrCast(
                @alignCast(handle orelse return null),
            );
            if (!std.mem.eql(
                u8,
                std.mem.span(path),
                "/samples/source.wav",
            )) return null;
            return self.publish(if (self.return_empty)
                ""
            else
                "resource/source.wav");
        }

        fn absolutePath(
            handle: StateHandle,
            path: [*:0]const u8,
        ) callconv(.c) ?[*:0]u8 {
            const self: *@This() = @ptrCast(
                @alignCast(handle orelse return null),
            );
            if (!std.mem.eql(
                u8,
                std.mem.span(path),
                "resource/source.wav",
            )) return null;
            return self.publish("/restored/source.wav");
        }

        fn makePath(
            handle: StateHandle,
            path: [*:0]const u8,
        ) callconv(.c) ?[*:0]u8 {
            const self: *@This() = @ptrCast(
                @alignCast(handle orelse return null),
            );
            if (!std.mem.eql(
                u8,
                std.mem.span(path),
                "generated/cache.bin",
            )) return null;
            return self.publish("/state/generated/cache.bin");
        }

        fn freePath(
            handle: StateHandle,
            _: [*:0]u8,
        ) callconv(.c) void {
            const self: *@This() = @ptrCast(
                @alignCast(handle orelse return),
            );
            self.free_count += 1;
        }

        fn publish(
            self: *@This(),
            value: []const u8,
        ) ?[*:0]u8 {
            if (value.len >= self.storage.len) return null;
            @memset(&self.storage, 0);
            @memcpy(self.storage[0..value.len], value);
            return self.storage[0..value.len :0].ptr;
        }
    };

    var host = Host{};
    const map_path = StateMapPath{
        .handle = &host,
        .abstract_path = Host.abstractPath,
        .absolute_path = Host.absolutePath,
    };
    const make_path = StateMakePath{
        .handle = &host,
        .path = Host.makePath,
    };
    const free_path = StateFreePath{
        .handle = &host,
        .free_path = Host.freePath,
    };
    const paths = StatePathFeatures{
        .map_path = &map_path,
        .make_path = &make_path,
        .free_path = &free_path,
    };

    var mapped = try paths.mapAbsolute("/samples/source.wav");
    try std.testing.expectEqualStrings(
        "resource/source.wav",
        mapped.bytes(),
    );
    mapped.deinit();
    var resolved = try paths.resolveAbstract("resource/source.wav");
    try std.testing.expectEqualStrings(
        "/restored/source.wav",
        resolved.bytes(),
    );
    resolved.deinit();
    var generated = try paths.makePath("generated/cache.bin");
    try std.testing.expectEqualStrings(
        "/state/generated/cache.bin",
        generated.bytes(),
    );
    generated.deinit();
    try std.testing.expectEqual(@as(usize, 3), host.free_count);

    const without_make = StatePathFeatures{
        .map_path = &map_path,
        .make_path = null,
        .free_path = &free_path,
    };
    try std.testing.expectError(
        error.StateMakePathUnavailable,
        without_make.makePath("generated/cache.bin"),
    );
    host.return_empty = true;
    try std.testing.expectError(
        error.InvalidStatePath,
        paths.mapAbsolute("/samples/source.wav"),
    );
    try std.testing.expectEqual(@as(usize, 4), host.free_count);
}

test "LV2 state interface saves restores validates and resets parameters" {
    const Probe = struct {
        component_value: u32 = 7,
        pending_component_value: u32 = 7,
        component_restore_count: usize = 0,

        pub const name = "LV2 State Probe";
        pub const vendor = "zig-vst3";
        pub const component_state_maximum_encoded_size = 6;
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 0,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
        pub const units: units_api.Config = .{
            .program_lists = &.{.{
                .id = 4,
                .name = "Factory",
                .programs = &.{.{
                    .name = "Maximum",
                    .parameters = &.{
                        .{ .parameter_id = 0, .normalized = 1.0 },
                    },
                }},
            }},
        };

        pub fn processWithParameterView(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
            view: @import("parameters.zig").ParameterView(Params),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            const gain: f32 = @floatCast(view.load("gain"));
            for (input, output) |sample, *destination|
                destination.* = sample * gain;
        }

        pub fn writeComponentState(
            self: *const @This(),
            writer: anytype,
        ) !void {
            try writer.writeByte(0xa5);
            try writer.writeInt(
                u32,
                self.component_value,
                .little,
            );
        }

        pub fn readComponentState(
            self: *@This(),
            reader: anytype,
        ) !void {
            if (try reader.takeByte() != 0xa5)
                return error.InvalidComponentState;
            self.pending_component_value =
                try reader.takeInt(u32, .little);
        }

        pub fn afterComponentStateRestore(self: *@This()) void {
            self.component_value = self.pending_component_value;
            self.component_restore_count += 1;
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-state-probe",
        2,
    );
    var urid_map = UridMap{
        .handle = null,
        .map = TestStateHost.map,
    };
    var map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const features = [_:null]?*const Feature{&map_feature};
    const handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-state-probe.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(handle);

    const raw_interface = Adapter.descriptor.extension_data(
        state_interface_uri,
    ) orelse return error.MissingStateInterface;
    const state: *const StateInterface =
        @ptrCast(@alignCast(raw_interface));
    const raw_programs = Adapter.descriptor.extension_data(
        programs_interface_uri,
    ) orelse return error.MissingProgramsInterface;
    const programs: *const ProgramsInterface =
        @ptrCast(@alignCast(raw_programs));
    var host = TestStateHost{};
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{0.0} ** 2;
    var gain: f32 = 1.75;
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        &gain,
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqual(
        StateStatus.success,
        state.save(handle, TestStateHost.store, &host, 0, null),
    );
    try std.testing.expectEqual(@as(Urid, 17), host.key);
    try std.testing.expectEqual(@as(Urid, 23), host.value_type);
    try std.testing.expectEqual(
        state_is_pod | state_is_portable,
        host.flags,
    );
    try std.testing.expect(host.component_present);
    try std.testing.expectEqual(
        @as(Urid, 23),
        host.component_value_type,
    );
    try std.testing.expectEqual(
        state_is_pod | state_is_portable,
        host.component_flags,
    );
    try std.testing.expectEqual(@as(usize, 5), host.component_size);
    host.component_store_status = .no_space;
    try std.testing.expectEqual(
        StateStatus.no_space,
        state.save(handle, TestStateHost.store, &host, 0, null),
    );
    host.component_store_status = .success;

    gain = 0.25;
    Adapter.descriptor.run(handle, 2);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    instance.runtime.instance.plugin.component_value = 99;
    instance.runtime.instance.plugin.pending_component_value = 99;
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    programs.select_program(handle, 4, 0);
    try std.testing.expectEqual(
        @as(?f64, 2.0),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        StateStatus.success,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 1.75),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(u32, 7),
        instance.runtime.instance.plugin.component_value,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        instance.runtime.instance.plugin.component_restore_count,
    );
    gain = 1.75;
    Adapter.descriptor.run(handle, 2);
    try std.testing.expectEqual(
        @as(?f64, 1.75),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );

    host.value_type = 99;
    try std.testing.expectEqual(
        StateStatus.bad_type,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 1.75),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(u32, 7),
        instance.runtime.instance.plugin.component_value,
    );

    host.value_type = 23;
    gain = 0.25;
    Adapter.descriptor.run(handle, 2);
    instance.runtime.instance.plugin.component_value = 99;
    instance.runtime.instance.plugin.pending_component_value = 99;
    host.component_bytes[0] = 0;
    try std.testing.expectEqual(
        StateStatus.bad_type,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(u32, 99),
        instance.runtime.instance.plugin.component_value,
    );

    host.component_bytes[0] = 0xa5;
    host.component_bytes[5] = 0;
    host.component_size = 6;
    try std.testing.expectEqual(
        StateStatus.bad_type,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(u32, 99),
        instance.runtime.instance.plugin.component_value,
    );

    host.component_size = 5;
    try std.testing.expectEqual(
        StateStatus.success,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 1.75),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(u32, 7),
        instance.runtime.instance.plugin.component_value,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        instance.runtime.instance.plugin.component_restore_count,
    );

    host.present = false;
    try std.testing.expectEqual(
        StateStatus.success,
        state.restore(
            handle,
            TestStateHost.retrieve,
            &host,
            0,
            null,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 1.0),
        instance.runtime.instance.loadParameterPlainIndex(0),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        instance.runtime.instance.plugin.component_restore_count,
    );
}

test "LV2 host fixture drives audio control buses latency and lifecycle" {
    const Probe = struct {
        pub const name = "LV2 Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .stereo;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .stereo;
        pub const audio_auxiliary_input_layouts =
            &.{plugin_api.AudioBusLayout.mono};
        pub const audio_auxiliary_output_layouts =
            &.{plugin_api.AudioBusLayout.mono};
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 7,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };

        pub fn latencySamples(_: *const @This()) u32 {
            return 23;
        }

        pub fn processWithParameterView(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
            view: @import("parameters.zig").ParameterView(Params),
        ) void {
            const gain: f32 = @floatCast(view.load("gain"));
            for (0..2) |channel| {
                const input = context.inputChannel(channel) orelse
                    return;
                const output = context.outputChannel(channel) orelse
                    return;
                for (input, output) |sample, *destination|
                    destination.* = sample * gain;
            }
            const sidechain = context.sidechainInputChannel(0) orelse
                return;
            const auxiliary =
                context.auxiliaryOutputChannel(0) orelse return;
            @memcpy(auxiliary, sidechain);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-probe",
        4,
    );
    try std.testing.expectEqual(@as(usize, 9), Adapter.port_count);
    try std.testing.expectEqual(
        PortKind.control_input,
        Adapter.portKind(Adapter.control_input_port_start).?,
    );
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingDescriptor;
    try std.testing.expect(Adapter.descriptorAt(1) == null);
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    const input_left = [_]f32{ 0.25, 0.5, -0.5, -0.25 };
    const input_right = [_]f32{ 1.0, -1.0, 0.75, -0.75 };
    const sidechain = [_]f32{ 0.1, 0.2, 0.3, 0.4 };
    var output_left = [_]f32{0.0} ** 4;
    var output_right = [_]f32{0.0} ** 4;
    var auxiliary = [_]f32{0.0} ** 4;
    var event_input = AtomSequence{
        .atom = .{
            .size = @sizeOf(AtomSequenceBody),
            .type = 0,
        },
        .body = .{ .unit = 0, .pad = 0 },
    };
    var gain: f32 = 2.0;
    var latency: f32 = 0.0;
    const ports = [_]*anyopaque{
        @constCast(&input_left),
        @constCast(&input_right),
        @constCast(&sidechain),
        &output_left,
        &output_right,
        &auxiliary,
        &event_input,
        &gain,
        &latency,
    };
    try std.testing.expectEqual(ports.len, Adapter.port_count);
    for (ports, 0..) |port, index|
        descriptor.connect_port(handle, @intCast(index), port);

    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, 4);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.5, 1.0, -1.0, -0.5 },
        &output_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 2.0, -2.0, 1.5, -1.5 },
        &output_right,
    );
    try std.testing.expectEqualSlices(f32, &sidechain, &auxiliary);
    try std.testing.expectEqual(@as(f32, 23.0), latency);

    if (descriptor.deactivate) |deactivate| deactivate(handle);
    try std.testing.expectEqual(
        plugin_api.RuntimeState.prepared,
        instance.runtime.runtimeState(),
    );
}

test "LV2 static ports carry selected auxiliary bus capacity" {
    const Probe = struct {
        pub const name = "LV2 Large Bus Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 12;
        pub const event_input = false;
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .none;
        pub const auxiliary_layouts =
            [_]plugin_api.AudioBusLayout{.mono} ** 12;
        pub const audio_auxiliary_input_layouts: []const plugin_api.AudioBusLayout =
            &auxiliary_layouts;

        auxiliary_input_count: usize = 0,

        pub fn process(
            self: *@This(),
            context: *process_api.BoundedProcessContext(
                f32,
                maximum_auxiliary_audio_buses,
            ),
        ) void {
            self.auxiliary_input_count =
                context.auxiliaryInputBusCount();
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-large-bus-probe",
        1,
    );
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingDescriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-large-bus-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    var input_samples: [1 + Probe.maximum_auxiliary_audio_buses][1]f32 =
        @splat(.{1.0});
    for (&input_samples, 0..) |*samples, index|
        descriptor.connect_port(
            handle,
            @intCast(index),
            samples,
        );
    var latency: f32 = 0.0;
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );

    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, 1);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        instance.runtime.instance.plugin
            .auxiliary_input_count,
    );
}

test "LV2 worker supports immediate offline and bounded responses" {
    const Probe = struct {
        pub const name = "LV2 Worker Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const allow_dynamic_process_mode = true;
        pub const lv2_freewheeling = true;
        pub const lv2_worker_maximum_request_size = 8;
        pub const lv2_worker_maximum_response_size = 8;
        pub const Params = struct {};

        schedule: ?*WorkerScheduleSink = null,
        schedule_status: WorkerStatus = .unknown,
        requested: bool = false,
        response: [8]u8 = undefined,
        response_size: usize = 0,
        end_run_count: usize = 0,
        last_process_mode: process_api.ProcessMode = .realtime,

        pub fn bindLv2WorkerSchedule(
            self: *@This(),
            schedule: *WorkerScheduleSink,
        ) void {
            self.schedule = schedule;
        }

        pub fn process(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            self.last_process_mode = context.processMode();
            if (!self.requested) {
                self.requested = true;
                self.schedule_status =
                    if (self.schedule) |schedule|
                        schedule.schedule("load")
                    else
                        .unknown;
            }
            const output = context.outputChannel(0) orelse return;
            const value: f32 = if (self.response_size == 4)
                @floatFromInt(self.response[0])
            else
                0.0;
            @memset(output, value);
        }

        pub fn runLv2Worker(
            _: *@This(),
            request: []const u8,
            response: *WorkerResponseSink,
        ) !void {
            if (!std.mem.eql(u8, request, "load"))
                return error.InvalidRequest;
            if (response.respond("done") != .success)
                return error.ResponseRejected;
        }

        pub fn applyLv2WorkerResponse(
            self: *@This(),
            response: []const u8,
        ) !void {
            if (response.len > self.response.len)
                return error.ResponseTooLarge;
            @memcpy(self.response[0..response.len], response);
            self.response_size = response.len;
        }

        pub fn endLv2WorkerRun(self: *@This()) !void {
            self.end_run_count += 1;
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-worker",
        8,
    );
    const Host = struct {
        interface: *const WorkerInterface,
        instance: Handle = null,
        work_count: usize = 0,
        response_count: usize = 0,

        fn schedule(
            context: ?*anyopaque,
            size: u32,
            data: ?*const anyopaque,
        ) callconv(.c) WorkerStatus {
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
            context: WorkerRespondHandle,
            size: u32,
            data: ?*const anyopaque,
        ) callconv(.c) WorkerStatus {
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

    const raw_interface = Adapter.descriptor.extension_data(
        worker_interface_uri,
    ) orelse return error.MissingWorkerInterface;
    const worker: *const WorkerInterface =
        @ptrCast(@alignCast(raw_interface));
    var host = Host{ .interface = worker };
    var schedule = WorkerSchedule{
        .handle = &host,
        .schedule_work = Host.schedule,
    };
    var schedule_feature = Feature{
        .URI = worker_schedule_uri,
        .data = &schedule,
    };
    const features = [_:null]?*const Feature{&schedule_feature};
    var misaligned_schedule_storage: [@sizeOf(WorkerSchedule) + 1]u8 align(@alignOf(WorkerSchedule)) = undefined;
    schedule_feature.data =
        @ptrCast(&misaligned_schedule_storage[1]);
    try std.testing.expectEqual(
        @as(Handle, null),
        Adapter.descriptor.instantiate(
            &Adapter.descriptor,
            48_000.0,
            "/tmp/lv2-worker.lv2",
            features[0..].ptr,
        ),
    );
    schedule_feature.data = &schedule;

    const handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-worker.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(handle);
    host.instance = handle;

    const input = [_]f32{0.0} ** 4;
    var output = [_]f32{0.0} ** input.len;
    var freewheeling: f32 = 1.0;
    var latency: f32 = -1.0;
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.freewheeling_input_port.?,
        &freewheeling,
    );
    Adapter.descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    Adapter.descriptor.run(handle, input.len);
    try std.testing.expectEqual(WorkerStatus.success, worker.end_run.?(handle));

    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    const plugin = &instance.runtime.instance.plugin;
    try std.testing.expectEqual(
        process_api.ProcessMode.offline,
        plugin.last_process_mode,
    );
    try std.testing.expectEqual(WorkerStatus.success, plugin.schedule_status);
    try std.testing.expectEqual(@as(usize, 1), host.work_count);
    try std.testing.expectEqual(@as(usize, 1), host.response_count);
    try std.testing.expectEqualStrings(
        "done",
        plugin.response[0..plugin.response_size],
    );
    try std.testing.expectEqual(@as(usize, 1), plugin.end_run_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{100.0} ** input.len),
        &output,
    );
    try std.testing.expectEqual(
        WorkerStatus.unknown,
        plugin.schedule.?.schedule("late"),
    );
    try std.testing.expectEqual(
        WorkerStatus.no_space,
        worker.work(
            handle,
            Host.respond,
            &host,
            9,
            "oversized".ptr,
        ),
    );
    try std.testing.expectEqual(
        WorkerStatus.unknown,
        worker.work(
            handle,
            Host.respond,
            &host,
            1,
            null,
        ),
    );
    try std.testing.expectEqual(
        WorkerStatus.no_space,
        worker.work_response(
            handle,
            9,
            "oversized".ptr,
        ),
    );

    const no_feature_handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        48_000.0,
        "/tmp/lv2-worker-without-feature.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(no_feature_handle);
    var no_feature_output = [_]f32{1.0} ** input.len;
    var no_feature_latency: f32 = -1.0;
    Adapter.descriptor.connect_port(
        no_feature_handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    Adapter.descriptor.connect_port(
        no_feature_handle,
        Adapter.audio_output_port_start,
        &no_feature_output,
    );
    Adapter.descriptor.connect_port(
        no_feature_handle,
        Adapter.latency_output_port,
        &no_feature_latency,
    );
    if (Adapter.descriptor.activate) |activate|
        activate(no_feature_handle);
    Adapter.descriptor.run(no_feature_handle, input.len);
    const no_feature_instance =
        Adapter.instanceFromHandle(no_feature_handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        WorkerStatus.unknown,
        no_feature_instance.runtime.instance.plugin.schedule_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &no_feature_output,
    );
}

test "LV2 Atom MIDI sequences reach input and output event buses" {
    const Probe = struct {
        pub const name = "LV2 MIDI Echo";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const event_output = true;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const writer = context.outputEventWriter() orelse return;
            _ = writer.appendAllIfPossible(context.inputEvents());
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-midi-echo",
        64,
    );
    try std.testing.expectEqual(@as(usize, 5), Adapter.port_count);
    try std.testing.expectEqual(
        PortKind.event_input,
        Adapter.portKind(Adapter.event_input_port.?).?,
    );
    try std.testing.expectEqual(
        PortKind.event_output,
        Adapter.portKind(Adapter.event_output_port.?).?,
    );

    var urid_map = UridMap{
        .handle = null,
        .map = TestStateHost.map,
    };
    var map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const features = [_:null]?*const Feature{&map_feature};
    const descriptor = &Adapter.descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-midi-echo.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    const SequenceBuffer = extern struct {
        sequence: AtomSequence,
        storage: [192]u8,
    };
    var input: SequenceBuffer align(8) = std.mem.zeroes(SequenceBuffer);
    input.sequence.atom = .{
        .size = @sizeOf(AtomSequenceBody) + 144,
        .type = 29,
    };
    input.sequence.body = .{ .unit = 0, .pad = 0 };
    const input_bytes: [*]u8 = @ptrCast(&input.sequence.body);
    const input_event: *AtomEvent = @ptrCast(
        @alignCast(input_bytes + @sizeOf(AtomSequenceBody)),
    );
    input_event.* = .{
        .time = .{ .frames = 11 },
        .body = .{ .size = 3, .type = 37 },
    };
    @memcpy(
        input_bytes[@sizeOf(AtomSequenceBody) + @sizeOf(AtomEvent) .. @sizeOf(AtomSequenceBody) + @sizeOf(AtomEvent) + 3],
        &[_]u8{ 0x92, 64, 100 },
    );
    const position_event: *AtomEvent = @ptrCast(
        @alignCast(input_bytes + @sizeOf(AtomSequenceBody) + 24),
    );
    position_event.* = .{
        .time = .{ .frames = 12 },
        .body = .{ .size = 32, .type = 43 },
    };
    const position_payload =
        @sizeOf(AtomSequenceBody) + 24 + @sizeOf(AtomEvent);
    const position_object: *AtomObjectBody = @ptrCast(
        @alignCast(input_bytes + position_payload),
    );
    position_object.* = .{ .id = 0, .otype = 67 };
    const tempo_property: *AtomPropertyBody = @ptrCast(
        @alignCast(
            input_bytes + position_payload +
                @sizeOf(AtomObjectBody),
        ),
    );
    tempo_property.* = .{
        .key = 97,
        .context = 0,
        .value = .{ .size = @sizeOf(f32), .type = 47 },
    };
    const tempo_value: *align(1) f32 = @ptrCast(
        input_bytes + position_payload +
            @sizeOf(AtomObjectBody) +
            @sizeOf(AtomPropertyBody),
    );
    tempo_value.* = 90.0;
    const clock_event: *AtomEvent = @ptrCast(
        @alignCast(input_bytes + @sizeOf(AtomSequenceBody) + 72),
    );
    clock_event.* = .{
        .time = .{ .frames = 12 },
        .body = .{ .size = 1, .type = 37 },
    };
    input_bytes[
        @sizeOf(AtomSequenceBody) + 72 + @sizeOf(AtomEvent)
    ] = 0xf8;
    const sysex_event: *AtomEvent = @ptrCast(
        @alignCast(input_bytes + @sizeOf(AtomSequenceBody) + 96),
    );
    sysex_event.* = .{
        .time = .{ .frames = 13 },
        .body = .{ .size = 5, .type = 37 },
    };
    @memcpy(
        input_bytes[@sizeOf(AtomSequenceBody) + 96 + @sizeOf(AtomEvent) .. @sizeOf(AtomSequenceBody) + 96 + @sizeOf(AtomEvent) + 5],
        &[_]u8{ 0xf0, 0x7d, 1, 2, 0xf7 },
    );
    const integer_event: *AtomEvent = @ptrCast(
        @alignCast(input_bytes + @sizeOf(AtomSequenceBody) + 120),
    );
    integer_event.* = .{
        .time = .{ .frames = 14 },
        .body = .{ .size = @sizeOf(i32), .type = 59 },
    };
    const integer_value: *align(1) i32 = @ptrCast(
        input_bytes + @sizeOf(AtomSequenceBody) + 120 +
            @sizeOf(AtomEvent),
    );
    integer_value.* = 0x1234_5678;

    var output: SequenceBuffer align(8) = std.mem.zeroes(SequenceBuffer);
    output.sequence.atom.size =
        @sizeOf(AtomSequenceBody) + output.storage.len;
    const audio_input = [_]f32{0.0} ** 64;
    var audio_output = [_]f32{0.0} ** 64;
    var latency: f32 = 0;
    descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&audio_input),
    );
    descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &audio_output,
    );
    descriptor.connect_port(
        handle,
        @intCast(Adapter.event_input_port.?),
        &input,
    );
    descriptor.connect_port(
        handle,
        @intCast(Adapter.event_output_port.?),
        &output,
    );
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, 64);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqual(@as(Urid, 29), output.sequence.atom.type);
    try std.testing.expectEqual(
        @as(u32, @sizeOf(AtomSequenceBody) + 96),
        output.sequence.atom.size,
    );
    const output_bytes: [*]const u8 = @ptrCast(&output.sequence.body);
    const output_event: *const AtomEvent = @ptrCast(
        @alignCast(output_bytes + @sizeOf(AtomSequenceBody)),
    );
    try std.testing.expectEqual(@as(i64, 11), output_event.time.frames);
    try std.testing.expectEqual(@as(Urid, 37), output_event.body.type);
    try std.testing.expectEqual(@as(u32, 3), output_event.body.size);
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x92, 64, 100 },
        output_bytes[@sizeOf(AtomSequenceBody) + @sizeOf(AtomEvent) .. @sizeOf(AtomSequenceBody) + @sizeOf(AtomEvent) + 3],
    );
    const output_clock: *const AtomEvent = @ptrCast(
        @alignCast(output_bytes + @sizeOf(AtomSequenceBody) + 24),
    );
    try std.testing.expectEqual(@as(i64, 12), output_clock.time.frames);
    try std.testing.expectEqual(@as(u32, 1), output_clock.body.size);
    try std.testing.expectEqual(
        @as(u8, 0xf8),
        output_bytes[
            @sizeOf(AtomSequenceBody) + 24 + @sizeOf(AtomEvent)
        ],
    );
    const output_sysex: *const AtomEvent = @ptrCast(
        @alignCast(output_bytes + @sizeOf(AtomSequenceBody) + 48),
    );
    try std.testing.expectEqual(@as(i64, 13), output_sysex.time.frames);
    try std.testing.expectEqual(@as(u32, 5), output_sysex.body.size);
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0xf0, 0x7d, 1, 2, 0xf7 },
        output_bytes[@sizeOf(AtomSequenceBody) + 48 + @sizeOf(AtomEvent) .. @sizeOf(AtomSequenceBody) + 48 + @sizeOf(AtomEvent) + 5],
    );
    const output_integer: *const AtomEvent = @ptrCast(
        @alignCast(output_bytes + @sizeOf(AtomSequenceBody) + 72),
    );
    try std.testing.expectEqual(
        @as(i64, 14),
        output_integer.time.frames,
    );
    try std.testing.expectEqual(@as(Urid, 59), output_integer.body.type);
    try std.testing.expectEqual(
        @as(u32, @sizeOf(i32)),
        output_integer.body.size,
    );
    const output_integer_value: *align(1) const i32 = @ptrCast(
        output_bytes + @sizeOf(AtomSequenceBody) + 72 +
            @sizeOf(AtomEvent),
    );
    try std.testing.expectEqual(
        @as(i32, 0x1234_5678),
        output_integer_value.*,
    );

    @memset(&audio_output, 1.0);
    output.sequence.atom.size = @sizeOf(AtomSequenceBody);
    descriptor.run(handle, 64);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** 64),
        &audio_output,
    );
    try std.testing.expectEqual(@as(Urid, 29), output.sequence.atom.type);
    try std.testing.expectEqual(
        @as(u32, @sizeOf(AtomSequenceBody)),
        output.sequence.atom.size,
    );
    try std.testing.expectEqual(
        @as(Urid, 31),
        output.sequence.body.unit,
    );

    output.sequence.atom.size =
        @sizeOf(AtomSequenceBody) + output.storage.len;
    sysex_event.time.frames = 10;
    @memset(&audio_output, 1.0);
    descriptor.run(handle, 64);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** 64),
        &audio_output,
    );
    try std.testing.expectEqual(
        @as(u32, @sizeOf(AtomSequenceBody)),
        output.sequence.atom.size,
    );

    sysex_event.time.frames = 13;
    input_bytes[
        @sizeOf(AtomSequenceBody) + 96 + @sizeOf(AtomEvent) + 4
    ] = 0x7f;
    @memset(&audio_output, 1.0);
    descriptor.run(handle, 64);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** 64),
        &audio_output,
    );

    input_bytes[
        @sizeOf(AtomSequenceBody) + 96 + @sizeOf(AtomEvent) + 4
    ] = 0xf7;
    var misaligned_input_storage: [@sizeOf(SequenceBuffer) + 1]u8 align(@alignOf(SequenceBuffer)) =
        @splat(0);
    @memcpy(
        misaligned_input_storage[1..],
        std.mem.asBytes(&input),
    );
    var misaligned_output_storage: [@sizeOf(SequenceBuffer) + 1]u8 align(@alignOf(SequenceBuffer)) =
        @splat(0);
    const misaligned_output: *align(1) SequenceBuffer =
        @ptrCast(&misaligned_output_storage[1]);
    misaligned_output.sequence.atom.size =
        @sizeOf(AtomSequenceBody) + misaligned_output.storage.len;
    descriptor.connect_port(
        handle,
        @intCast(Adapter.event_input_port.?),
        @ptrCast(&misaligned_input_storage[1]),
    );
    descriptor.connect_port(
        handle,
        @intCast(Adapter.event_output_port.?),
        @ptrCast(misaligned_output),
    );
    descriptor.run(handle, 64);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqual(
        @as(Urid, 29),
        misaligned_output.sequence.atom.type,
    );
    try std.testing.expectEqual(
        @as(u32, @sizeOf(AtomSequenceBody) + 96),
        misaligned_output.sequence.atom.size,
    );
}

test "LV2 time Position reaches transport and advances between runs" {
    const Probe = struct {
        pub const name = "LV2 Transport Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {};

        seen: [5]?process_api.Transport = @splat(null),
        seen_frames: [5]usize = @splat(0),
        process_count: usize = 0,

        pub fn process(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            if (self.process_count < self.seen.len) {
                self.seen[self.process_count] = context.transport();
                self.seen_frames[self.process_count] =
                    context.frameCount();
                self.process_count += 1;
            }
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-transport",
        480,
    );
    var urid_map = UridMap{
        .handle = null,
        .map = TestStateHost.map,
    };
    var map_feature = Feature{
        .URI = urid_map_uri,
        .data = &urid_map,
    };
    const features = [_:null]?*const Feature{&map_feature};
    const descriptor = &Adapter.descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-transport.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    const input = [_]f32{0.25} ** 480;
    var output = [_]f32{0.0} ** input.len;
    var sequence = TestSequenceBuffer.empty(29);
    var builder = TestTimeBuilder.init(
        &sequence,
        29,
        43,
        67,
        0,
    );
    builder.append(i64, 101, 61, 96_000);
    builder.append(f32, 107, 47, 1.0);
    builder.append(f64, 79, 53, 6.0);
    builder.append(i64, 71, 61, 2);
    builder.append(f32, 73, 47, 0.0);
    builder.append(i32, 83, 59, 4);
    builder.append(f32, 89, 47, 3.0);
    builder.append(f32, 97, 47, 120.0);
    builder.append(f32, 103, 47, 48_000.0);
    var latency: f32 = 0;
    descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    descriptor.connect_port(
        handle,
        @intCast(Adapter.event_input_port.?),
        &sequence,
    );
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    const first = instance.runtime.instance.plugin.seen[0] orelse
        return error.MissingTransport;
    try std.testing.expect(first.state_valid);
    try std.testing.expect(first.playing);
    try std.testing.expectEqual(@as(i64, 96_000), first.project_time_samples);
    try std.testing.expectEqual(@as(?f64, 120.0), first.tempo_bpm);
    try std.testing.expectEqual(@as(?f64, 6.0), first.project_quarter_notes);
    try std.testing.expectEqual(
        @as(?f64, 6.0),
        first.bar_position_quarter_notes,
    );
    try std.testing.expectEqual(
        @as(?process_api.TimeSignature, .{
            .numerator = 3,
            .denominator = 4,
        }),
        first.time_signature,
    );

    sequence = TestSequenceBuffer.empty(29);
    descriptor.run(handle, input.len);
    const second = instance.runtime.instance.plugin.seen[1] orelse
        return error.MissingTransport;
    try std.testing.expectEqual(
        @as(i64, 96_480),
        second.project_time_samples,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 6.02),
        second.project_quarter_notes orelse
            return error.MissingMusicalPosition,
        1.0e-12,
    );
    try std.testing.expectEqualSlices(f32, &input, &output);

    builder = TestTimeBuilder.init(
        &sequence,
        29,
        43,
        67,
        1,
    );
    builder.append(f32, 97, 47, 90.0);
    @memset(&output, 1.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    const before_change =
        instance.runtime.instance.plugin.seen[2] orelse
        return error.MissingTransport;
    const after_change =
        instance.runtime.instance.plugin.seen[3] orelse
        return error.MissingTransport;
    try std.testing.expectEqual(
        @as(usize, 1),
        instance.runtime.instance.plugin.seen_frames[2],
    );
    try std.testing.expectEqual(
        @as(usize, 479),
        instance.runtime.instance.plugin.seen_frames[3],
    );
    try std.testing.expectEqual(
        @as(?f64, 120.0),
        before_change.tempo_bpm,
    );
    try std.testing.expectEqual(
        @as(i64, 96_960),
        before_change.project_time_samples,
    );
    try std.testing.expectEqual(
        @as(?f64, 90.0),
        after_change.tempo_bpm,
    );
    try std.testing.expectEqual(
        @as(i64, 96_961),
        after_change.project_time_samples,
    );
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(
        @as(i64, 97_440),
        instance.transport.?.project_time_samples,
    );

    builder = TestTimeBuilder.init(
        &sequence,
        29,
        43,
        67,
        0,
    );
    builder.append(f64, 97, 53, 90.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqual(
        @as(?f64, 90.0),
        instance.transport.?.tempo_bpm,
    );

    builder = TestTimeBuilder.init(
        &sequence,
        29,
        43,
        67,
        0,
    );
    builder.append(f32, 107, 47, 0.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    const stopped = instance.runtime.instance.plugin.seen[4] orelse
        return error.MissingTransport;
    try std.testing.expect(!stopped.playing);
    try std.testing.expectEqual(
        @as(i64, 97_440),
        stopped.project_time_samples,
    );
    try std.testing.expectEqual(
        @as(i64, 97_440),
        instance.transport.?.project_time_samples,
    );
}

test "LV2 freewheeling control switches process mode at block boundaries" {
    const Probe = struct {
        observed: [3]process_api.ProcessMode = undefined,
        observed_count: usize = 0,

        pub const name = "LV2 Freewheeling Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const event_input = false;
        pub const allow_dynamic_process_mode = true;
        pub const lv2_freewheeling = true;
        pub const Params = struct {};

        pub fn process(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            if (self.observed_count < self.observed.len) {
                self.observed[self.observed_count] =
                    context.processMode();
                self.observed_count += 1;
            }
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-freewheeling-probe",
        2,
    );
    try std.testing.expectEqual(@as(usize, 4), Adapter.port_count);
    try std.testing.expectEqual(
        @as(?usize, 2),
        Adapter.freewheeling_input_port,
    );
    try std.testing.expectEqual(
        PortKind.freewheeling_input,
        Adapter.portKind(Adapter.freewheeling_input_port.?).?,
    );

    const descriptor = &Adapter.descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-freewheeling-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 1.0, 1.0 };
    var freewheeling: f32 = 0.0;
    var latency: f32 = -1.0;
    descriptor.connect_port(handle, 0, @constCast(&input));
    descriptor.connect_port(handle, 1, &output);
    descriptor.connect_port(handle, 3, &latency);
    if (descriptor.activate) |activate| activate(handle);

    descriptor.run(handle, input.len);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.unconnected_port,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        &output,
    );

    descriptor.connect_port(handle, 2, &freewheeling);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    freewheeling = 1.0;
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    freewheeling = -1.0;
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        process_api.ProcessMode,
        &.{ .realtime, .offline, .realtime },
        &instance.runtime.instance.plugin.observed,
    );
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(@as(f32, 0.0), latency);

    freewheeling = std.math.nan(f32);
    output = @splat(1.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.invalid_control,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        &output,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        instance.runtime.instance.plugin.observed_count,
    );

    freewheeling = 0.0;
    var misaligned_latency_storage: [@sizeOf(f32) + 1]u8 align(@alignOf(f32)) = @splat(0xff);
    const misaligned_latency: *align(1) f32 =
        @ptrCast(&misaligned_latency_storage[1]);
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        @ptrCast(misaligned_latency),
    );
    output = @splat(1.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqual(@as(f32, 0.0), misaligned_latency.*);

    var misaligned_mode_storage: [@sizeOf(f32) + 1]u8 align(@alignOf(f32)) = @splat(0);
    const misaligned_mode: *align(1) f32 =
        @ptrCast(&misaligned_mode_storage[1]);
    misaligned_mode.* = 1.0;
    descriptor.connect_port(
        handle,
        Adapter.freewheeling_input_port.?,
        @ptrCast(misaligned_mode),
    );
    output = @splat(1.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqual(
        RunStatus.invalid_control,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        &output,
    );
}

test "LV2 run failures clear connected outputs and remain bounded" {
    const Probe = struct {
        pub const name = "LV2 Failure Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 0,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };

        pub fn process(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-failure-probe",
        2,
    );
    const descriptor = &Adapter.descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-failure-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    var output = [_]f32{ 1.0, 1.0, 1.0 };
    descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    if (descriptor.activate) |activate| activate(handle);

    descriptor.run(handle, 2);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        RunStatus.unconnected_port,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        output[0..2],
    );

    const input = [_]f32{ 0.5, -0.5 };
    var invalid_gain = std.math.nan(f32);
    descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        &invalid_gain,
    );
    output = @splat(1.0);
    descriptor.run(handle, 2);
    try std.testing.expectEqual(
        RunStatus.invalid_control,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        output[0..2],
    );

    output = @splat(1.0);
    descriptor.run(handle, 3);
    try std.testing.expectEqual(
        RunStatus.block_too_large,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0, 0.0 },
        &output,
    );

    var misaligned_input_storage: [2 * @sizeOf(f32) + 1]u8 align(@alignOf(f32)) = @splat(0);
    const misaligned_input: [*]align(1) f32 =
        @ptrCast(&misaligned_input_storage[1]);
    misaligned_input[0] = 0.25;
    misaligned_input[1] = -0.25;
    descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @ptrCast(misaligned_input),
    );
    var valid_gain: f32 = 1.0;
    descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        &valid_gain,
    );
    output = @splat(1.0);
    descriptor.run(handle, 2);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        output[0..2],
    );

    var misaligned_output_storage: [2 * @sizeOf(f32) + 1]u8 align(@alignOf(f32)) = @splat(0xff);
    const misaligned_output: [*]align(1) f32 =
        @ptrCast(&misaligned_output_storage[1]);
    descriptor.connect_port(
        handle,
        Adapter.audio_input_port_start,
        @constCast(&input),
    );
    descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        @ptrCast(misaligned_output),
    );
    descriptor.run(handle, 2);
    try std.testing.expectEqual(
        RunStatus.invalid_context,
        instance.last_run_status,
    );
    try std.testing.expectEqual(@as(f32, 0.0), misaligned_output[0]);
    try std.testing.expectEqual(@as(f32, 0.0), misaligned_output[1]);

    var misaligned_control_storage: [@sizeOf(f32) + 1]u8 align(@alignOf(f32)) = @splat(0);
    const misaligned_control: *align(1) f32 =
        @ptrCast(&misaligned_control_storage[1]);
    misaligned_control.* = 1.0;
    descriptor.connect_port(
        handle,
        Adapter.audio_output_port_start,
        &output,
    );
    descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        @ptrCast(misaligned_control),
    );
    output = @splat(1.0);
    descriptor.run(handle, 2);
    try std.testing.expectEqual(
        RunStatus.invalid_control,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.0 },
        output[0..2],
    );
}

test "LV2 zero-frame run updates control outputs without audio ports" {
    const Probe = struct {
        pub const name = "LV2 Zero Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {};

        pub fn latencySamples(_: *const @This()) u32 {
            return 41;
        }

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = CoreAdapter(
        Probe,
        "https://example.test/lv2-zero-probe",
        16,
    );
    var latency: f32 = 0.0;
    const handle = Adapter.descriptor.instantiate(
        &Adapter.descriptor,
        44_100.0,
        "/tmp/lv2-zero-probe.lv2",
        null,
    ) orelse return error.InstantiateFailed;
    defer Adapter.descriptor.cleanup(handle);
    Adapter.descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (Adapter.descriptor.activate) |activate| activate(handle);
    Adapter.descriptor.run(handle, 0);
    try std.testing.expectEqual(@as(f32, 41.0), latency);
}
