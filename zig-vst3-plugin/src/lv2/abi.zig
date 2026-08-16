pub const Handle = ?*anyopaque;

pub const Feature = extern struct {
    URI: ?[*:0]const u8,
    data: ?*anyopaque,
};

pub const Urid = u32;

pub const UridMapFunction = *const fn (
    handle: ?*anyopaque,
    URI: [*:0]const u8,
) callconv(.c) Urid;

pub const UridMap = extern struct {
    handle: ?*anyopaque,
    map: ?UridMapFunction,
};

pub const UridUnmap = extern struct {
    handle: ?*anyopaque,
    unmap: ?UridUnmapFunction,
};

pub const UridUnmapFunction = *const fn (
    handle: ?*anyopaque,
    urid: Urid,
) callconv(.c) ?[*:0]const u8;

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
        options: ?[*]align(1) OptionsOption,
    ) callconv(.c) OptionsStatus,
    set: *const fn (
        instance: Handle,
        options: ?[*]align(1) const OptionsOption,
    ) callconv(.c) OptionsStatus,
};

pub const WorkerStatus = enum(c_int) {
    success = 0,
    unknown = 1,
    no_space = 2,
    _,
};

pub const WorkerRespondHandle = ?*anyopaque;
pub const WorkerRespondFunction = *const fn (
    handle: WorkerRespondHandle,
    size: u32,
    data: ?*const anyopaque,
) callconv(.c) WorkerStatus;

pub const WorkerScheduleFunction = *const fn (
    handle: ?*anyopaque,
    size: u32,
    data: ?*const anyopaque,
) callconv(.c) WorkerStatus;

pub const WorkerSchedule = extern struct {
    handle: ?*anyopaque,
    schedule_work: ?WorkerScheduleFunction,
};

pub const ResizePortStatus = enum(c_int) {
    success = 0,
    unknown = 1,
    no_space = 2,
    _,
};

pub const ResizePortFunction = *const fn (
    data: ?*anyopaque,
    port_index: u32,
    size: usize,
) callconv(.c) ResizePortStatus;

pub const ResizePortFeature = extern struct {
    data: ?*anyopaque,
    resize: ?ResizePortFunction,
};

pub const LogPrintfFunction = *const fn (
    handle: ?*anyopaque,
    type: Urid,
    format: [*:0]const u8,
    ...,
) callconv(.c) c_int;

pub const LogFeature = extern struct {
    handle: ?*anyopaque,
    printf: ?LogPrintfFunction,
    vprintf: ?*const anyopaque,
};

pub const WorkerInterface = extern struct {
    work: *const fn (
        instance: Handle,
        respond: ?WorkerRespondFunction,
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

pub const StateHandle = ?*anyopaque;

pub const StateStatus = enum(c_int) {
    success = 0,
    unknown = 1,
    bad_type = 2,
    bad_flags = 3,
    no_feature = 4,
    no_property = 5,
    no_space = 6,
    _,
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
        store: ?StateStoreFunction,
        handle: StateHandle,
        flags: u32,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) StateStatus,
    restore: *const fn (
        instance: Handle,
        retrieve: ?StateRetrieveFunction,
        handle: StateHandle,
        flags: u32,
        features: ?[*:null]const ?*const Feature,
    ) callconv(.c) StateStatus,
};

pub const StateMapPathFunction = *const fn (
    handle: StateHandle,
    path: [*:0]const u8,
) callconv(.c) ?[*:0]u8;

pub const StateFreePathFunction = *const fn (
    handle: StateHandle,
    path: [*:0]u8,
) callconv(.c) void;

pub const StateMapPath = extern struct {
    handle: StateHandle,
    abstract_path: ?StateMapPathFunction,
    absolute_path: ?StateMapPathFunction,
};

pub const StateMakePath = extern struct {
    handle: StateHandle,
    path: ?StateMapPathFunction,
};

pub const StateFreePath = extern struct {
    handle: StateHandle,
    free_path: ?StateFreePathFunction,
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
