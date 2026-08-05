const builtin = @import("builtin");
const std = @import("std");
const hrtf = @import("hrtf.zig");

pub const PositionEncoding = enum {
    spherical_degrees,
    cartesian_metres,
};

pub const DecodedDataset = struct {
    measurement_count: usize,
    response_frame_count: usize,
    sampling_rates: []const f64,
    source_positions: []const f64,
    position_encoding: PositionEncoding,
    responses_measurement_ear_frame: []const f64,
    delays_measurement_ear: []const f64 = &.{},
};

pub fn databaseFromDecoded(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
    allocator: std.mem.Allocator,
    decoded: DecodedDataset,
) !hrtf.Database(maximum_measurements, maximum_frames) {
    var result: hrtf.Database(
        maximum_measurements,
        maximum_frames,
    ) = undefined;
    try databaseFromDecodedInto(
        maximum_measurements,
        maximum_frames,
        allocator,
        decoded,
        &result,
    );
    return result;
}

pub fn databaseFromDecodedInto(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
    allocator: std.mem.Allocator,
    decoded: DecodedDataset,
    destination: *hrtf.Database(
        maximum_measurements,
        maximum_frames,
    ),
) !void {
    if (decoded.measurement_count == 0 or
        decoded.measurement_count > maximum_measurements)
        return error.InvalidSofaMeasurementCount;
    if (decoded.response_frame_count == 0 or
        decoded.response_frame_count > maximum_frames)
        return error.InvalidSofaResponseShape;
    if (decoded.sampling_rates.len == 0 or
        (decoded.sampling_rates.len != 1 and
            decoded.sampling_rates.len != decoded.measurement_count))
        return error.InvalidSofaSamplingRateShape;
    const position_count = std.math.mul(
        usize,
        decoded.measurement_count,
        3,
    ) catch return error.InvalidSofaPositionShape;
    if (decoded.source_positions.len != position_count)
        return error.InvalidSofaPositionShape;

    const response_count = try responseValueCount(
        decoded.measurement_count,
        decoded.response_frame_count,
    );
    if (decoded.responses_measurement_ear_frame.len != response_count)
        return error.InvalidSofaResponseShape;
    const expanded_delay_count = std.math.mul(
        usize,
        decoded.measurement_count,
        2,
    ) catch return error.InvalidSofaDelayShape;
    if (decoded.delays_measurement_ear.len != 0 and
        decoded.delays_measurement_ear.len != 2 and
        decoded.delays_measurement_ear.len !=
            expanded_delay_count)
        return error.InvalidSofaDelayShape;

    const first_rate = try sampleRate(decoded.sampling_rates[0]);
    for (decoded.sampling_rates[1..]) |rate| {
        if (try sampleRate(rate) != first_rate)
            return error.VariableSofaSamplingRate;
    }

    var directions: [maximum_measurements]hrtf.Direction = @splat(.{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    });
    var distances_metres: [maximum_measurements]f64 = @splat(1.0);
    for (0..decoded.measurement_count) |measurement_index| {
        const position =
            decoded.source_positions[measurement_index * 3 ..][0..3];
        for (position) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidSofaPosition;
        }
        const measurement_position = switch (decoded.position_encoding) {
            .spherical_degrees => blk: {
                if (position[2] <= 0.0 or
                    position[0] < -180.0 or
                    position[0] >= 360.0 or
                    position[1] < -90.0 or
                    position[1] > 90.0)
                    return error.InvalidSofaPosition;
                const azimuth = if (position[0] > 180.0)
                    position[0] - 360.0
                else
                    position[0];
                break :blk hrtf.MeasurementPosition{
                    .direction = .{
                        .azimuth_degrees = azimuth,
                        .elevation_degrees = position[1],
                    },
                    .distance_metres = position[2],
                };
            },
            .cartesian_metres => hrtf.measurementFromPositions(
                .{
                    .x = position[0],
                    .y = position[1],
                    .z = position[2],
                },
                .{
                    .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                },
            ) catch return error.InvalidSofaPosition,
        };
        directions[measurement_index] = measurement_position.direction;
        distances_metres[measurement_index] =
            measurement_position.distance_metres;
    }

    for (decoded.responses_measurement_ear_frame) |value| {
        if (!std.math.isFinite(value) or
            @abs(value) > std.math.floatMax(f32))
            return error.InvalidSofaResponse;
    }
    const available_delay_frames =
        maximum_frames - decoded.response_frame_count;
    const maximum_delay_samples: f64 =
        @floatFromInt(available_delay_frames);
    for (decoded.delays_measurement_ear) |delay| {
        if (!std.math.isFinite(delay) or delay < 0.0)
            return error.InvalidHrtfDelay;
        if (delay > maximum_delay_samples)
            return error.HrtfFrameCapacityExceeded;
    }

    const interleaved = try allocator.alloc(f32, response_count);
    defer allocator.free(interleaved);
    for (0..decoded.measurement_count) |measurement_index| {
        for (0..decoded.response_frame_count) |frame_index| {
            for (0..2) |ear_index| {
                const source_index =
                    (measurement_index * 2 + ear_index) *
                    decoded.response_frame_count +
                    frame_index;
                interleaved[
                    (measurement_index *
                        decoded.response_frame_count +
                        frame_index) *
                        2 +
                        ear_index
                ] = @floatCast(
                    decoded.responses_measurement_ear_frame[source_index],
                );
            }
        }
    }

    return hrtf.Database(
        maximum_measurements,
        maximum_frames,
    ).initWithDistancesAndDelaysInto(
        destination,
        first_rate,
        directions[0..decoded.measurement_count],
        distances_metres[0..decoded.measurement_count],
        interleaved,
        decoded.delays_measurement_ear,
    );
}

fn sampleRate(value: f64) !u32 {
    if (!std.math.isFinite(value) or value < 8_000.0 or
        value > 384_000.0 or @abs(value - @round(value)) > 0.000_001)
        return error.InvalidSofaSamplingRate;
    return @intFromFloat(value);
}

fn responseValueCount(
    measurement_count: usize,
    response_frame_count: usize,
) !usize {
    const values_per_measurement = std.math.mul(
        usize,
        response_frame_count,
        2,
    ) catch return error.InvalidSofaResponseShape;
    return std.math.mul(
        usize,
        measurement_count,
        values_per_measurement,
    ) catch return error.InvalidSofaResponseShape;
}

fn validateResponseShape(
    shape: [4]usize,
    maximum_measurements: usize,
    maximum_frames: usize,
) !void {
    if (shape[0] > maximum_measurements)
        return error.InvalidSofaMeasurementCount;
    if (shape[2] > maximum_frames)
        return error.InvalidSofaResponseShape;
}

fn terminatedPath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![:0]u8 {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null)
        return error.InvalidSofaPath;
    return allocator.dupeZ(u8, path);
}

fn terminatedRuntimePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![:0]u8 {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null)
        return error.InvalidSofaRuntimePath;
    return allocator.dupeZ(u8, path);
}

pub fn Loader(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
) type {
    return struct {
        const Self = @This();
        const DatabaseType =
            hrtf.Database(maximum_measurements, maximum_frames);

        library: ?DynamicLibrary,
        api: ?Api,

        pub fn openRuntime(
            allocator: std.mem.Allocator,
            path: []const u8,
        ) !Self {
            const terminated_path = try terminatedRuntimePath(
                allocator,
                path,
            );
            defer allocator.free(terminated_path);
            return openTerminated(terminated_path);
        }

        pub fn openDefault() !Self {
            const names = switch (builtin.os.tag) {
                .windows => &[_][:0]const u8{
                    "netcdf.dll",
                    "netcdf-19.dll",
                },
                .macos => &[_][:0]const u8{
                    "libnetcdf.22.dylib",
                    "libnetcdf.21.dylib",
                    "libnetcdf.20.dylib",
                    "libnetcdf.19.dylib",
                    "libnetcdf.dylib",
                    "/opt/homebrew/opt/netcdf/lib/libnetcdf.dylib",
                    "/usr/local/opt/netcdf/lib/libnetcdf.dylib",
                    "/opt/local/lib/libnetcdf.dylib",
                },
                else => &[_][:0]const u8{
                    "libnetcdf.so.22",
                    "libnetcdf.so.21",
                    "libnetcdf.so.20",
                    "libnetcdf.so.19",
                    "libnetcdf.so",
                },
            };
            for (names) |name| {
                return openTerminated(name) catch continue;
            }
            return error.SofaRuntimeUnavailable;
        }

        fn openTerminated(path: [:0]const u8) !Self {
            var library = DynamicLibrary.open(path) catch
                return error.SofaRuntimeUnavailable;
            errdefer library.close();
            const api = try Api.load(&library);
            return .{ .library = library, .api = api };
        }

        pub fn deinit(self: *Self) void {
            self.api = null;
            if (self.library) |*library| library.close();
            self.library = null;
        }

        pub fn isOpen(self: *const Self) bool {
            return self.library != null and self.api != null;
        }

        pub fn loadFile(
            self: *const Self,
            allocator: std.mem.Allocator,
            path: []const u8,
        ) !DatabaseType {
            var result: DatabaseType = undefined;
            try self.loadFileInto(
                allocator,
                path,
                &result,
            );
            return result;
        }

        pub fn loadFileInto(
            self: *const Self,
            allocator: std.mem.Allocator,
            path: []const u8,
            destination: *DatabaseType,
        ) !void {
            if (self.library == null) return error.SofaLoaderClosed;
            const api = self.api orelse return error.SofaLoaderClosed;
            const terminated_path = try terminatedPath(allocator, path);
            defer allocator.free(terminated_path);

            var file_id: c_int = 0;
            try check(api.open(
                terminated_path.ptr,
                nc_nowrite,
                &file_id,
            ));
            defer _ = api.close(file_id);

            try requireAttribute(
                &api,
                file_id,
                nc_global,
                "Conventions",
                "SOFA",
            );
            try requireContainerConventionVersions(
                &api,
                file_id,
            );
            try requireAttribute(
                &api,
                file_id,
                nc_global,
                "SOFAConventions",
                "SimpleFreeFieldHRIR",
            );
            try requireAttribute(
                &api,
                file_id,
                nc_global,
                "DataType",
                "FIR",
            );
            try requireAttribute(
                &api,
                file_id,
                nc_global,
                "RoomType",
                "free field",
            );
            const maximum_ir_values = responseValueCount(
                maximum_measurements,
                maximum_frames,
            ) catch return error.SofaDatasetTooLarge;

            const ir = try readVariable(
                &api,
                allocator,
                file_id,
                "Data.IR",
                3,
                maximum_ir_values,
            );
            defer allocator.free(ir.values);
            if (ir.shape[1] != 2)
                return error.UnsupportedSofaReceiverCount;
            if (!responseDimensionsAreDistinct(ir.dimension_ids))
                return error.InvalidSofaResponseShape;
            try validateResponseShape(
                ir.shape,
                maximum_measurements,
                maximum_frames,
            );

            const position_value_count = std.math.mul(
                usize,
                ir.shape[0],
                3,
            ) catch return error.SofaDatasetTooLarge;

            const positions = try readVariable(
                &api,
                allocator,
                file_id,
                "SourcePosition",
                2,
                position_value_count,
            );
            defer allocator.free(positions.values);
            if (positions.shape[0] != ir.shape[0] or
                positions.shape[1] != 3 or
                !instanceOrMeasurementDimensionMatches(
                    positions,
                    0,
                    ir.dimension_ids[0],
                    ir.shape[0],
                ) or
                std.mem.indexOfScalar(
                    c_int,
                    ir.dimension_ids[0..3],
                    positions.dimension_ids[1],
                ) != null)
                return error.InvalidSofaPositionShape;
            try requireDefaultListenerGeometry(
                &api,
                allocator,
                file_id,
                ir.shape[0],
                ir.dimension_ids[0],
                ir.dimension_ids[1],
                positions.dimension_ids[1],
            );
            try requireDefaultEmitterGeometry(
                &api,
                allocator,
                file_id,
                ir.shape[0],
                ir.dimension_ids[0],
                positions.dimension_ids[1],
            );
            const position_encoding = try positionEncoding(
                &api,
                file_id,
                positions.variable_id,
            );

            const rates = try readVariable(
                &api,
                allocator,
                file_id,
                "Data.SamplingRate",
                null,
                ir.shape[0],
            );
            defer allocator.free(rates.values);
            if (!validSamplingRateVariable(rates, ir.shape[0]) or
                !instanceOrMeasurementDimensionMatches(
                    rates,
                    0,
                    ir.dimension_ids[0],
                    ir.shape[0],
                ))
                return error.InvalidSofaSamplingRateShape;
            try requireAttribute(
                &api,
                file_id,
                rates.variable_id,
                "Units",
                "hertz",
            );

            var delays: []f64 = &.{};
            var delay_variable_id: c_int = 0;
            if (api.inquire_variable_id(
                file_id,
                "Data.Delay",
                &delay_variable_id,
            ) == nc_no_error) {
                const loaded = try readVariableById(
                    &api,
                    allocator,
                    file_id,
                    delay_variable_id,
                    null,
                    std.math.mul(
                        usize,
                        ir.shape[0],
                        2,
                    ) catch return error.SofaDatasetTooLarge,
                );
                delays = loaded.values;
                if (!validDelayVariable(loaded, ir.shape[0]) or
                    !instanceOrMeasurementDimensionMatches(
                        loaded,
                        0,
                        ir.dimension_ids[0],
                        ir.shape[0],
                    ) or
                    loaded.dimension_ids[1] != ir.dimension_ids[1])
                {
                    allocator.free(delays);
                    return error.InvalidSofaDelayShape;
                }
            }
            defer if (delays.len != 0) allocator.free(delays);

            return databaseFromDecodedInto(
                maximum_measurements,
                maximum_frames,
                allocator,
                .{
                    .measurement_count = ir.shape[0],
                    .response_frame_count = ir.shape[2],
                    .sampling_rates = rates.values,
                    .source_positions = positions.values,
                    .position_encoding = position_encoding,
                    .responses_measurement_ear_frame = ir.values,
                    .delays_measurement_ear = delays,
                },
                destination,
            );
        }
    };
}

const nc_no_error: c_int = 0;
const nc_nowrite: c_int = 0;
const nc_global: c_int = -1;
const nc_double: c_int = 6;

const DynamicLibrary = switch (builtin.os.tag) {
    .windows => WindowsDynamicLibrary,
    .linux => LinuxDynamicLibrary,
    else => std.DynLib,
};

const LinuxDynamicLibrary = struct {
    handle: ?*anyopaque,

    fn open(name: [:0]const u8) !LinuxDynamicLibrary {
        return .{
            .handle = std.c.dlopen(name.ptr, .{ .NOW = true }) orelse
                return error.LoadDynamicLibraryFailed,
        };
    }

    fn close(self: *LinuxDynamicLibrary) void {
        const handle = self.handle orelse return;
        _ = std.c.dlclose(handle);
        self.handle = null;
    }

    fn lookup(
        self: *LinuxDynamicLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        const handle = self.handle orelse return null;
        const symbol = @call(
            .never_tail,
            std.c.dlsym,
            .{ handle, name.ptr },
        ) orelse return null;
        return @ptrCast(@alignCast(symbol));
    }
};

const WindowsDynamicLibrary = struct {
    const windows = std.os.windows;

    handle: ?windows.HMODULE,

    fn open(name: [:0]const u8) !WindowsDynamicLibrary {
        return .{
            .handle = LoadLibraryA(name.ptr) orelse
                return error.LoadDynamicLibraryFailed,
        };
    }

    fn close(self: *WindowsDynamicLibrary) void {
        const handle = self.handle orelse return;
        _ = FreeLibrary(handle);
        self.handle = null;
    }

    fn lookup(
        self: *WindowsDynamicLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        const handle = self.handle orelse return null;
        const procedure =
            GetProcAddress(handle, name.ptr) orelse return null;
        return @ptrCast(procedure);
    }

    extern "kernel32" fn LoadLibraryA(
        name: [*:0]const u8,
    ) callconv(.winapi) ?windows.HMODULE;
    extern "kernel32" fn GetProcAddress(
        module: windows.HMODULE,
        name: [*:0]const u8,
    ) callconv(.winapi) ?windows.FARPROC;
    extern "kernel32" fn FreeLibrary(
        module: windows.HMODULE,
    ) callconv(.winapi) windows.BOOL;
};

const Api = struct {
    open: *const fn (
        [*:0]const u8,
        c_int,
        *c_int,
    ) callconv(.c) c_int,
    close: *const fn (c_int) callconv(.c) c_int,
    inquire_variable_id: *const fn (
        c_int,
        [*:0]const u8,
        *c_int,
    ) callconv(.c) c_int,
    inquire_variable_dimension_count: *const fn (
        c_int,
        c_int,
        *c_int,
    ) callconv(.c) c_int,
    inquire_variable_type: *const fn (
        c_int,
        c_int,
        *c_int,
    ) callconv(.c) c_int,
    inquire_variable_dimension_ids: *const fn (
        c_int,
        c_int,
        [*]c_int,
    ) callconv(.c) c_int,
    inquire_dimension_length: *const fn (
        c_int,
        c_int,
        *usize,
    ) callconv(.c) c_int,
    inquire_attribute_length: *const fn (
        c_int,
        c_int,
        [*:0]const u8,
        *usize,
    ) callconv(.c) c_int,
    get_attribute_text: *const fn (
        c_int,
        c_int,
        [*:0]const u8,
        [*]u8,
    ) callconv(.c) c_int,
    get_variable_double: *const fn (
        c_int,
        c_int,
        [*]f64,
    ) callconv(.c) c_int,

    fn load(library: *DynamicLibrary) !Api {
        return .{
            .open = library.lookup(
                @FieldType(Api, "open"),
                "nc_open",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .close = library.lookup(
                @FieldType(Api, "close"),
                "nc_close",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_variable_id = library.lookup(
                @FieldType(Api, "inquire_variable_id"),
                "nc_inq_varid",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_variable_dimension_count = library.lookup(
                @FieldType(Api, "inquire_variable_dimension_count"),
                "nc_inq_varndims",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_variable_type = library.lookup(
                @FieldType(Api, "inquire_variable_type"),
                "nc_inq_vartype",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_variable_dimension_ids = library.lookup(
                @FieldType(Api, "inquire_variable_dimension_ids"),
                "nc_inq_vardimid",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_dimension_length = library.lookup(
                @FieldType(Api, "inquire_dimension_length"),
                "nc_inq_dimlen",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .inquire_attribute_length = library.lookup(
                @FieldType(Api, "inquire_attribute_length"),
                "nc_inq_attlen",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .get_attribute_text = library.lookup(
                @FieldType(Api, "get_attribute_text"),
                "nc_get_att_text",
            ) orelse return error.MissingSofaRuntimeSymbol,
            .get_variable_double = library.lookup(
                @FieldType(Api, "get_variable_double"),
                "nc_get_var_double",
            ) orelse return error.MissingSofaRuntimeSymbol,
        };
    }
};

const Variable = struct {
    variable_id: c_int,
    rank: usize,
    shape: [4]usize,
    dimension_ids: [4]c_int = @splat(0),
    values: []f64,
};

fn validSamplingRateVariable(
    variable: Variable,
    measurement_count: usize,
) bool {
    return variable.rank == 1 and
        variable.values.len == variable.shape[0] and
        (variable.shape[0] == 1 or
            variable.shape[0] == measurement_count);
}

fn validDelayVariable(
    variable: Variable,
    measurement_count: usize,
) bool {
    const value_count = std.math.mul(
        usize,
        variable.shape[0],
        2,
    ) catch return false;
    return variable.rank == 2 and
        variable.shape[1] == 2 and
        variable.values.len == value_count and
        (variable.shape[0] == 1 or
            variable.shape[0] == measurement_count);
}

fn readVariable(
    api: *const Api,
    allocator: std.mem.Allocator,
    file_id: c_int,
    name: [:0]const u8,
    expected_rank: ?usize,
    maximum_value_count: usize,
) !Variable {
    var variable_id: c_int = 0;
    try check(api.inquire_variable_id(
        file_id,
        name.ptr,
        &variable_id,
    ));
    return readVariableById(
        api,
        allocator,
        file_id,
        variable_id,
        expected_rank,
        maximum_value_count,
    );
}

fn readVariableById(
    api: *const Api,
    allocator: std.mem.Allocator,
    file_id: c_int,
    variable_id: c_int,
    expected_rank: ?usize,
    maximum_value_count: usize,
) !Variable {
    var variable_type: c_int = 0;
    try check(api.inquire_variable_type(
        file_id,
        variable_id,
        &variable_type,
    ));
    if (!supportedVariableType(variable_type))
        return error.UnsupportedSofaVariableType;

    var rank_c: c_int = 0;
    try check(api.inquire_variable_dimension_count(
        file_id,
        variable_id,
        &rank_c,
    ));
    if (rank_c < 0 or rank_c > 4)
        return error.UnsupportedSofaVariableRank;
    const rank: usize = @intCast(rank_c);
    if (expected_rank) |expected| {
        if (rank != expected)
            return error.InvalidSofaVariableRank;
    }

    var dimension_ids: [4]c_int = @splat(0);
    if (rank != 0) {
        try check(api.inquire_variable_dimension_ids(
            file_id,
            variable_id,
            &dimension_ids,
        ));
    }
    var shape: [4]usize = @splat(1);
    for (0..rank) |dimension_index| {
        try check(api.inquire_dimension_length(
            file_id,
            dimension_ids[dimension_index],
            &shape[dimension_index],
        ));
    }
    const value_count = try boundedShapeValueCount(
        shape[0..rank],
        maximum_value_count,
    );
    const values = try allocator.alloc(f64, value_count);
    errdefer allocator.free(values);
    try check(api.get_variable_double(
        file_id,
        variable_id,
        values.ptr,
    ));
    return .{
        .variable_id = variable_id,
        .rank = rank,
        .shape = shape,
        .dimension_ids = dimension_ids,
        .values = values,
    };
}

fn supportedVariableType(variable_type: c_int) bool {
    return variable_type == nc_double;
}

fn boundedShapeValueCount(
    shape: []const usize,
    maximum_value_count: usize,
) !usize {
    var value_count: usize = 1;
    for (shape) |dimension| {
        if (dimension == 0) return error.InvalidSofaVariableShape;
        value_count = std.math.mul(
            usize,
            value_count,
            dimension,
        ) catch return error.SofaDatasetTooLarge;
        if (value_count > maximum_value_count)
            return error.SofaDatasetTooLarge;
    }
    return value_count;
}

fn responseDimensionsAreDistinct(dimension_ids: [4]c_int) bool {
    return dimension_ids[0] != dimension_ids[1] and
        dimension_ids[0] != dimension_ids[2] and
        dimension_ids[1] != dimension_ids[2];
}

fn instanceOrMeasurementDimensionMatches(
    variable: Variable,
    dimension_index: usize,
    measurement_dimension_id: c_int,
    measurement_count: usize,
) bool {
    return variable.shape[dimension_index] == 1 or
        (variable.shape[dimension_index] == measurement_count and
            variable.dimension_ids[dimension_index] ==
                measurement_dimension_id);
}

fn requireAttribute(
    api: *const Api,
    file_id: c_int,
    variable_id: c_int,
    name: [:0]const u8,
    expected: []const u8,
) !void {
    var buffer: [256]u8 = undefined;
    const value = try attribute(
        api,
        file_id,
        variable_id,
        name,
        &buffer,
    );
    if (!std.mem.eql(u8, value, expected))
        return error.UnsupportedSofaConvention;
}

fn requireContainerConventionVersions(
    api: *const Api,
    file_id: c_int,
) !void {
    var container_buffer: [256]u8 = undefined;
    const container_version = try attribute(
        api,
        file_id,
        nc_global,
        "Version",
        &container_buffer,
    );
    var convention_buffer: [256]u8 = undefined;
    const convention_version = try attribute(
        api,
        file_id,
        nc_global,
        "SOFAConventionsVersion",
        &convention_buffer,
    );
    if (!supportedContainerConventionVersions(
        container_version,
        convention_version,
    )) return error.UnsupportedSofaConvention;
}

fn supportedContainerConventionVersions(
    container_version: []const u8,
    convention_version: []const u8,
) bool {
    if (std.mem.eql(u8, container_version, "1.0"))
        return std.mem.eql(u8, convention_version, "1.0");
    if (!std.mem.eql(u8, container_version, "2.1")) return false;
    return std.mem.eql(u8, convention_version, "1.0") or
        std.mem.eql(u8, convention_version, "1.1") or
        std.mem.eql(u8, convention_version, "1.2");
}

fn positionEncoding(
    api: *const Api,
    file_id: c_int,
    variable_id: c_int,
) !PositionEncoding {
    var buffer: [256]u8 = undefined;
    const value = try attribute(
        api,
        file_id,
        variable_id,
        "Type",
        &buffer,
    );
    var units_buffer: [256]u8 = undefined;
    const units = try attribute(
        api,
        file_id,
        variable_id,
        "Units",
        &units_buffer,
    );
    return positionEncodingFromAttributes(value, units);
}

fn positionEncodingFromAttributes(
    value: []const u8,
    units: []const u8,
) !PositionEncoding {
    if (std.ascii.eqlIgnoreCase(value, "spherical")) {
        if (!std.ascii.eqlIgnoreCase(
            units,
            "degree, degree, metre",
        ))
            return error.UnsupportedSofaPositionUnits;
        return .spherical_degrees;
    }
    if (std.ascii.eqlIgnoreCase(value, "cartesian")) {
        if (!std.ascii.eqlIgnoreCase(units, "metre"))
            return error.UnsupportedSofaPositionUnits;
        return .cartesian_metres;
    }
    return error.UnsupportedSofaPositionEncoding;
}

fn requireDefaultListenerGeometry(
    api: *const Api,
    allocator: std.mem.Allocator,
    file_id: c_int,
    measurement_count: usize,
    measurement_dimension_id: c_int,
    receiver_dimension_id: c_int,
    coordinate_dimension_id: c_int,
) !void {
    const maximum_listener_values = std.math.mul(
        usize,
        measurement_count,
        3,
    ) catch return error.SofaDatasetTooLarge;
    const listener_position = try readVariable(
        api,
        allocator,
        file_id,
        "ListenerPosition",
        2,
        maximum_listener_values,
    );
    defer allocator.free(listener_position.values);
    const listener_position_encoding = positionEncoding(
        api,
        file_id,
        listener_position.variable_id,
    ) catch return error.UnsupportedSofaListenerGeometry;
    const listener_view = try readVariable(
        api,
        allocator,
        file_id,
        "ListenerView",
        2,
        maximum_listener_values,
    );
    defer allocator.free(listener_view.values);
    const listener_view_encoding = positionEncoding(
        api,
        file_id,
        listener_view.variable_id,
    ) catch return error.UnsupportedSofaListenerGeometry;
    const listener_up = try readVariable(
        api,
        allocator,
        file_id,
        "ListenerUp",
        2,
        maximum_listener_values,
    );
    defer allocator.free(listener_up.values);
    if (listener_position_encoding != .cartesian_metres or
        listener_view_encoding != .cartesian_metres)
        return error.UnsupportedSofaListenerGeometry;
    try requireDefaultVectors(
        listener_position,
        measurement_count,
        measurement_dimension_id,
        coordinate_dimension_id,
        .{ 0.0, 0.0, 0.0 },
    );
    try requireDefaultVectors(
        listener_view,
        measurement_count,
        measurement_dimension_id,
        coordinate_dimension_id,
        .{ 1.0, 0.0, 0.0 },
    );
    try requireDefaultVectors(
        listener_up,
        measurement_count,
        measurement_dimension_id,
        coordinate_dimension_id,
        .{ 0.0, 0.0, 1.0 },
    );

    const receivers = try readVariable(
        api,
        allocator,
        file_id,
        "ReceiverPosition",
        3,
        std.math.mul(
            usize,
            measurement_count,
            6,
        ) catch return error.SofaDatasetTooLarge,
    );
    defer allocator.free(receivers.values);
    const receiver_encoding = positionEncoding(
        api,
        file_id,
        receivers.variable_id,
    ) catch return error.UnsupportedSofaReceiverGeometry;
    if (receiver_encoding != .cartesian_metres)
        return error.UnsupportedSofaReceiverGeometry;
    try requireStereoReceiverGeometry(
        receivers,
        measurement_count,
        measurement_dimension_id,
        receiver_dimension_id,
        coordinate_dimension_id,
    );
}

fn requireStereoReceiverGeometry(
    receivers: Variable,
    measurement_count: usize,
    measurement_dimension_id: c_int,
    receiver_dimension_id: c_int,
    coordinate_dimension_id: c_int,
) !void {
    if (receivers.shape[0] != 2 or
        receivers.shape[1] != 3 or
        (receivers.shape[2] != 1 and
            receivers.shape[2] != measurement_count) or
        receivers.dimension_ids[0] != receiver_dimension_id or
        receivers.dimension_ids[1] != coordinate_dimension_id or
        !instanceOrMeasurementDimensionMatches(
            receivers,
            2,
            measurement_dimension_id,
            measurement_count,
        ))
        return error.UnsupportedSofaReceiverGeometry;
    for (receivers.values) |value| {
        if (!std.math.isFinite(value))
            return error.UnsupportedSofaReceiverGeometry;
    }
    const receiver_measurements = receivers.shape[2];
    for (0..receiver_measurements) |measurement_index| {
        const left_y = receivers.values[
            receiver_measurements + measurement_index
        ];
        const right_y = receivers.values[
            4 * receiver_measurements + measurement_index
        ];
        if (left_y <= 0.0 or right_y >= 0.0)
            return error.UnsupportedSofaReceiverGeometry;
    }
}

fn requireDefaultVectors(
    variable: Variable,
    measurement_count: usize,
    measurement_dimension_id: c_int,
    coordinate_dimension_id: c_int,
    expected: [3]f64,
) !void {
    if ((variable.shape[0] != 1 and
        variable.shape[0] != measurement_count) or
        variable.shape[1] != 3 or
        !instanceOrMeasurementDimensionMatches(
            variable,
            0,
            measurement_dimension_id,
            measurement_count,
        ) or
        variable.dimension_ids[1] != coordinate_dimension_id)
        return error.UnsupportedSofaListenerGeometry;
    for (0..variable.shape[0]) |measurement_index| {
        for (0..3) |coordinate_index| {
            const value =
                variable.values[measurement_index * 3 + coordinate_index];
            if (!std.math.isFinite(value) or
                @abs(value - expected[coordinate_index]) > 1.0e-9)
                return error.UnsupportedSofaListenerGeometry;
        }
    }
}

fn requireDefaultEmitterGeometry(
    api: *const Api,
    allocator: std.mem.Allocator,
    file_id: c_int,
    measurement_count: usize,
    measurement_dimension_id: c_int,
    coordinate_dimension_id: c_int,
) !void {
    const emitter = try readVariable(
        api,
        allocator,
        file_id,
        "EmitterPosition",
        3,
        std.math.mul(
            usize,
            measurement_count,
            3,
        ) catch return error.SofaDatasetTooLarge,
    );
    defer allocator.free(emitter.values);
    const encoding = positionEncoding(
        api,
        file_id,
        emitter.variable_id,
    ) catch return error.UnsupportedSofaEmitterGeometry;
    if (encoding != .cartesian_metres)
        return error.UnsupportedSofaEmitterGeometry;
    try requireDefaultEmitterVectors(
        emitter,
        measurement_count,
        measurement_dimension_id,
        coordinate_dimension_id,
    );
}

fn requireDefaultEmitterVectors(
    variable: Variable,
    measurement_count: usize,
    measurement_dimension_id: c_int,
    coordinate_dimension_id: c_int,
) !void {
    if (variable.shape[0] != 1 or
        variable.shape[1] != 3 or
        (variable.shape[2] != 1 and
            variable.shape[2] != measurement_count) or
        variable.dimension_ids[1] != coordinate_dimension_id or
        !instanceOrMeasurementDimensionMatches(
            variable,
            2,
            measurement_dimension_id,
            measurement_count,
        ))
        return error.UnsupportedSofaEmitterGeometry;
    const emitter_measurements = variable.shape[2];
    for (0..emitter_measurements) |measurement_index| {
        for (0..3) |coordinate_index| {
            const value = variable.values[
                coordinate_index * emitter_measurements + measurement_index
            ];
            if (!std.math.isFinite(value) or @abs(value) > 1.0e-9)
                return error.UnsupportedSofaEmitterGeometry;
        }
    }
}

fn attribute(
    api: *const Api,
    file_id: c_int,
    variable_id: c_int,
    name: [:0]const u8,
    buffer: []u8,
) ![]const u8 {
    var length: usize = 0;
    try check(api.inquire_attribute_length(
        file_id,
        variable_id,
        name.ptr,
        &length,
    ));
    if (length == 0 or length > buffer.len)
        return error.InvalidSofaAttribute;
    try check(api.get_attribute_text(
        file_id,
        variable_id,
        name.ptr,
        buffer.ptr,
    ));
    return std.mem.trim(u8, buffer[0..length], " \t\r\n\x00");
}

fn check(status: c_int) !void {
    if (status != nc_no_error) return error.InvalidSofaFile;
}

test "decoded standard HRTF dataset converts layout and positions" {
    const decoded = DecodedDataset{
        .measurement_count = 2,
        .response_frame_count = 2,
        .sampling_rates = &.{ 48_000.0, 48_000.0 },
        .source_positions = &.{
            0.0, 0.0, 1.0,
            0.0, 1.0, 0.0,
        },
        .position_encoding = .cartesian_metres,
        .responses_measurement_ear_frame = &.{
            1.0,  0.5,
            0.25, 0.125,
            0.75, 0.375,
            0.2,  0.1,
        },
        .delays_measurement_ear = &.{ 0.0, 0.0, 1.0, 1.0 },
    };
    const database = try databaseFromDecoded(
        2,
        4,
        std.testing.allocator,
        decoded,
    );
    try std.testing.expectEqual(@as(u32, 48_000), database.sample_rate);
    try std.testing.expectEqual(@as(usize, 3), database.frame_count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 90.0),
        database.directions[1].azimuth_degrees,
        0.000_001,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1.0, 1.0 },
        database.distances_metres[0..2],
    );
    var output: [6]f32 = undefined;
    try database.interpolate(
        database.directions[0],
        .nearest,
        &output,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 0.25, 0.5, 0.125, 0.0, 0.0 },
        output,
    );
}

test "decoded standard HRTF dataset preserves measurement radii" {
    const decoded = DecodedDataset{
        .measurement_count = 2,
        .response_frame_count = 1,
        .sampling_rates = &.{48_000.0},
        .source_positions = &.{
            0.0, 0.0, 0.5,
            0.0, 0.0, 1.5,
        },
        .position_encoding = .spherical_degrees,
        .responses_measurement_ear_frame = &.{ 1.0, 2.0, 3.0, 4.0 },
    };
    const database = try databaseFromDecoded(
        2,
        1,
        std.testing.allocator,
        decoded,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.5, 1.5 },
        database.distances_metres[0..2],
    );
    var output: [2]f32 = undefined;
    try database.interpolateAt(
        .{
            .direction = database.directions[0],
            .distance_metres = 1.0,
        },
        .inverse_distance,
        &output,
    );
    try std.testing.expectEqualDeep([_]f32{ 2.0, 3.0 }, output);

    var duplicate = decoded;
    duplicate.source_positions = &.{
        0.0, 0.0, 0.5,
        0.0, 0.0, 0.5,
    };
    try std.testing.expectError(
        error.DuplicateHrtfDirection,
        databaseFromDecoded(2, 1, std.testing.allocator, duplicate),
    );
}

test "decoded standard HRTF dataset normalizes spherical azimuth" {
    const decoded = DecodedDataset{
        .measurement_count = 1,
        .response_frame_count = 1,
        .sampling_rates = &.{48_000.0},
        .source_positions = &.{ 270.0, 15.0, 1.0 },
        .position_encoding = .spherical_degrees,
        .responses_measurement_ear_frame = &.{ 1.0, 1.0 },
    };
    const database = try databaseFromDecoded(
        1,
        1,
        std.testing.allocator,
        decoded,
    );
    try std.testing.expectEqual(
        @as(f64, -90.0),
        database.directions[0].azimuth_degrees,
    );
    try std.testing.expectEqual(
        @as(f64, 15.0),
        database.directions[0].elevation_degrees,
    );

    var invalid = decoded;
    invalid.source_positions = &.{ 0.0, 0.0, 0.0 };
    try std.testing.expectError(
        error.InvalidSofaPosition,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
    invalid.source_positions = &.{ 360.0, 0.0, 1.0 };
    try std.testing.expectError(
        error.InvalidSofaPosition,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
}

test "decoded standard HRTF response shape arithmetic is bounded" {
    try std.testing.expectEqual(
        @as(usize, 30),
        try responseValueCount(3, 5),
    );
    try std.testing.expectError(
        error.InvalidSofaResponseShape,
        responseValueCount(1, std.math.maxInt(usize)),
    );
    try std.testing.expectError(
        error.InvalidSofaResponseShape,
        responseValueCount(std.math.maxInt(usize), 1),
    );
}

test "standard HRTF file variables require convention ranks" {
    var values: [6]f64 = @splat(0.0);
    var variable = Variable{
        .variable_id = 0,
        .rank = 1,
        .shape = .{ 1, 1, 1, 1 },
        .values = values[0..1],
    };
    try std.testing.expect(validSamplingRateVariable(variable, 3));
    variable.shape[0] = 3;
    variable.values = values[0..3];
    try std.testing.expect(validSamplingRateVariable(variable, 3));
    variable.rank = 0;
    try std.testing.expect(!validSamplingRateVariable(variable, 3));
    variable.rank = 1;
    variable.shape[0] = 2;
    try std.testing.expect(!validSamplingRateVariable(variable, 3));

    variable.rank = 2;
    variable.shape = .{ 1, 2, 1, 1 };
    variable.values = values[0..2];
    try std.testing.expect(validDelayVariable(variable, 3));
    variable.shape[0] = 3;
    variable.values = values[0..6];
    try std.testing.expect(validDelayVariable(variable, 3));
    variable.rank = 1;
    try std.testing.expect(!validDelayVariable(variable, 3));
    variable.rank = 2;
    variable.shape = .{ 2, 3, 1, 1 };
    try std.testing.expect(!validDelayVariable(variable, 3));
}

test "standard HRTF variables require double precision storage" {
    try std.testing.expect(supportedVariableType(nc_double));
    try std.testing.expect(!supportedVariableType(5));
    try std.testing.expect(!supportedVariableType(9));

    const Fake = struct {
        fn inquire(
            _: c_int,
            _: c_int,
            variable_type: *c_int,
        ) callconv(.c) c_int {
            variable_type.* = 5;
            return nc_no_error;
        }
    };
    var api: Api = undefined;
    api.inquire_variable_type = Fake.inquire;
    try std.testing.expectError(
        error.UnsupportedSofaVariableType,
        readVariableById(
            &api,
            std.testing.allocator,
            0,
            0,
            null,
            1,
        ),
    );
}

test "standard HRTF file variable sizes are bounded before allocation" {
    try std.testing.expectEqual(
        @as(usize, 24),
        try boundedShapeValueCount(&.{ 3, 2, 4 }, 24),
    );
    try std.testing.expectError(
        error.SofaDatasetTooLarge,
        boundedShapeValueCount(&.{ 3, 2, 4 }, 23),
    );
    try std.testing.expectError(
        error.SofaDatasetTooLarge,
        boundedShapeValueCount(&.{ std.math.maxInt(usize), 2 }, 24),
    );
    try std.testing.expectError(
        error.InvalidSofaVariableShape,
        boundedShapeValueCount(&.{ 3, 0, 4 }, 24),
    );
}

test "standard HRTF response dimensions honor independent capacities" {
    try validateResponseShape(.{ 3, 2, 4, 1 }, 3, 4);
    try std.testing.expectError(
        error.InvalidSofaMeasurementCount,
        validateResponseShape(.{ 4, 2, 4, 1 }, 3, 4),
    );
    try std.testing.expectError(
        error.InvalidSofaResponseShape,
        validateResponseShape(.{ 3, 2, 5, 1 }, 3, 4),
    );
}

test "standard HRTF variables retain compatible dimensions" {
    try std.testing.expect(responseDimensionsAreDistinct(.{ 10, 20, 30, 0 }));
    try std.testing.expect(!responseDimensionsAreDistinct(.{ 10, 20, 10, 0 }));

    var values: [3]f64 = @splat(0.0);
    var variable = Variable{
        .variable_id = 0,
        .rank = 1,
        .shape = .{ 3, 1, 1, 1 },
        .dimension_ids = .{ 10, 0, 0, 0 },
        .values = &values,
    };
    try std.testing.expect(instanceOrMeasurementDimensionMatches(
        variable,
        0,
        10,
        3,
    ));
    variable.dimension_ids[0] = 40;
    try std.testing.expect(!instanceOrMeasurementDimensionMatches(
        variable,
        0,
        10,
        3,
    ));
    variable.shape[0] = 1;
    variable.values = values[0..1];
    try std.testing.expect(instanceOrMeasurementDimensionMatches(
        variable,
        0,
        10,
        3,
    ));
}

test "standard HRTF position attributes select supported encodings" {
    try std.testing.expectEqual(
        PositionEncoding.cartesian_metres,
        try positionEncodingFromAttributes("CaRtEsIaN", "MeTrE"),
    );
    try std.testing.expectEqual(
        PositionEncoding.spherical_degrees,
        try positionEncodingFromAttributes(
            "SpHeRiCaL",
            "DeGrEe, DeGrEe, MeTrE",
        ),
    );
    try std.testing.expectError(
        error.UnsupportedSofaPositionUnits,
        positionEncodingFromAttributes("cartesian", "centimetre"),
    );
    try std.testing.expectError(
        error.UnsupportedSofaPositionEncoding,
        positionEncodingFromAttributes("geodetic", "metre"),
    );
}

test "standard HRTF container and convention versions stay compatible" {
    try std.testing.expect(supportedContainerConventionVersions("1.0", "1.0"));
    try std.testing.expect(supportedContainerConventionVersions("2.1", "1.0"));
    try std.testing.expect(supportedContainerConventionVersions("2.1", "1.1"));
    try std.testing.expect(supportedContainerConventionVersions("2.1", "1.2"));
    try std.testing.expect(!supportedContainerConventionVersions("1.0", "1.1"));
    try std.testing.expect(!supportedContainerConventionVersions("2.0", "1.0"));
    try std.testing.expect(!supportedContainerConventionVersions("2.1", "1.3"));
}

test "standard HRTF emitter geometry requires the default origin" {
    var values = [_]f64{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    var emitter = Variable{
        .variable_id = 0,
        .rank = 3,
        .shape = .{ 1, 3, 2, 1 },
        .dimension_ids = .{ 30, 20, 10, 0 },
        .values = &values,
    };
    try requireDefaultEmitterVectors(emitter, 2, 10, 20);

    emitter.dimension_ids[1] = 40;
    try std.testing.expectError(
        error.UnsupportedSofaEmitterGeometry,
        requireDefaultEmitterVectors(emitter, 2, 10, 20),
    );
    emitter.dimension_ids[1] = 20;
    emitter.dimension_ids[2] = 40;
    try std.testing.expectError(
        error.UnsupportedSofaEmitterGeometry,
        requireDefaultEmitterVectors(emitter, 2, 10, 20),
    );
    emitter.dimension_ids[2] = 10;
    emitter.shape[0] = 2;
    try std.testing.expectError(
        error.UnsupportedSofaEmitterGeometry,
        requireDefaultEmitterVectors(emitter, 2, 10, 20),
    );
    emitter.shape[0] = 1;
    values[3] = 0.01;
    try std.testing.expectError(
        error.UnsupportedSofaEmitterGeometry,
        requireDefaultEmitterVectors(emitter, 2, 10, 20),
    );
    values[3] = std.math.nan(f64);
    try std.testing.expectError(
        error.UnsupportedSofaEmitterGeometry,
        requireDefaultEmitterVectors(emitter, 2, 10, 20),
    );
}

test "standard HRTF receiver geometry is finite and ordered" {
    var values = [_]f64{
        0.0,   0.0,
        0.09,  0.09,
        0.0,   0.0,
        0.0,   0.0,
        -0.09, -0.09,
        0.0,   0.0,
    };
    var receivers = Variable{
        .variable_id = 0,
        .rank = 3,
        .shape = .{ 2, 3, 2, 1 },
        .dimension_ids = .{ 20, 40, 10, 0 },
        .values = &values,
    };
    try requireStereoReceiverGeometry(receivers, 2, 10, 20, 40);

    values[0] = std.math.nan(f64);
    try std.testing.expectError(
        error.UnsupportedSofaReceiverGeometry,
        requireStereoReceiverGeometry(receivers, 2, 10, 20, 40),
    );
    values[0] = 0.0;
    values[8] = 0.09;
    try std.testing.expectError(
        error.UnsupportedSofaReceiverGeometry,
        requireStereoReceiverGeometry(receivers, 2, 10, 20, 40),
    );
    values[8] = -0.09;
    receivers.dimension_ids[1] = 30;
    try std.testing.expectError(
        error.UnsupportedSofaReceiverGeometry,
        requireStereoReceiverGeometry(receivers, 2, 10, 20, 40),
    );
}

test "decoded standard HRTF dataset rejects inconsistent data" {
    const base = DecodedDataset{
        .measurement_count = 1,
        .response_frame_count = 1,
        .sampling_rates = &.{48_000.0},
        .source_positions = &.{ 0.0, 0.0, 1.0 },
        .position_encoding = .cartesian_metres,
        .responses_measurement_ear_frame = &.{ 1.0, 1.0 },
    };
    var invalid = base;
    invalid.sampling_rates = &.{ 48_000.0, 44_100.0 };
    try std.testing.expectError(
        error.InvalidSofaSamplingRateShape,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
    invalid = base;
    invalid.source_positions = &.{ 0.0, 0.0, 0.0 };
    try std.testing.expectError(
        error.InvalidSofaPosition,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
    invalid = base;
    invalid.responses_measurement_ear_frame =
        &.{ 1.0, std.math.nan(f64) };
    try std.testing.expectError(
        error.InvalidSofaResponse,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
    invalid = base;
    invalid.responses_measurement_ear_frame =
        &.{ std.math.floatMax(f64), 1.0 };
    try std.testing.expectError(
        error.InvalidSofaResponse,
        databaseFromDecoded(1, 1, std.testing.allocator, invalid),
    );
    var invalid_failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.InvalidSofaResponse,
        databaseFromDecoded(1, 1, invalid_failing.allocator(), invalid),
    );
    invalid = base;
    invalid.responses_measurement_ear_frame = &.{
        std.math.floatMax(f32),
        -std.math.floatMax(f32),
    };
    const boundary = try databaseFromDecoded(
        1,
        1,
        std.testing.allocator,
        invalid,
    );
    try std.testing.expect(boundary.valid());

    invalid = base;
    invalid.delays_measurement_ear = &.{ std.math.nan(f64), 0.0 };
    var delay_failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.InvalidHrtfDelay,
        databaseFromDecoded(1, 1, delay_failing.allocator(), invalid),
    );
    invalid.delays_measurement_ear = &.{ 0.25, 0.0 };
    var delay_capacity_failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.HrtfFrameCapacityExceeded,
        databaseFromDecoded(
            1,
            1,
            delay_capacity_failing.allocator(),
            invalid,
        ),
    );

    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        databaseFromDecoded(1, 1, failing.allocator(), base),
    );
}

test "standard HRTF loader rejects ambiguous paths" {
    try std.testing.expectError(
        error.InvalidSofaPath,
        terminatedPath(std.testing.allocator, ""),
    );
    try std.testing.expectError(
        error.InvalidSofaPath,
        terminatedPath(std.testing.allocator, "fixture.sofa\x00ignored"),
    );

    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        terminatedPath(failing.allocator(), "fixture.sofa"),
    );

    const path = try terminatedPath(
        std.testing.allocator,
        "fixture.sofa",
    );
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("fixture.sofa", path);

    const TestLoader = Loader(1, 1);
    try std.testing.expectError(
        error.InvalidSofaRuntimePath,
        TestLoader.openRuntime(std.testing.allocator, ""),
    );
    try std.testing.expectError(
        error.InvalidSofaRuntimePath,
        TestLoader.openRuntime(
            std.testing.allocator,
            "libnetcdf.so\x00ignored",
        ),
    );
    var runtime_failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        TestLoader.openRuntime(
            runtime_failing.allocator(),
            "libnetcdf.so",
        ),
    );
    try std.testing.expectError(
        error.SofaRuntimeUnavailable,
        TestLoader.openRuntime(
            std.testing.allocator,
            "/zig-vst3/missing/libnetcdf",
        ),
    );
}

test "standard HRTF loader contains closed ownership state" {
    const TestLoader = Loader(1, 1);
    var loader = TestLoader{
        .library = null,
        .api = null,
    };
    try std.testing.expect(!loader.isOpen());
    loader.deinit();
    loader.deinit();

    const DatabaseType = hrtf.Database(1, 1);
    var destination = try DatabaseType.init(
        48_000,
        &.{.{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        }},
        &.{ 0.25, -0.25 },
    );
    const before = destination;
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.SofaLoaderClosed,
        loader.loadFileInto(
            failing.allocator(),
            "fixture.sofa",
            &destination,
        ),
    );
    try std.testing.expectEqualDeep(before, destination);
    try std.testing.expectError(
        error.SofaLoaderClosed,
        loader.loadFile(std.testing.allocator, "fixture.sofa"),
    );
}

fn openPublicTestLoader(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
) !Loader(maximum_measurements, maximum_frames) {
    const runtime_path = std.testing.environ.getAlloc(
        std.testing.allocator,
        "ZIG_VST3_NETCDF_TEST_LIBRARY",
    ) catch |load_error| switch (load_error) {
        error.EnvironmentVariableMissing => return Loader(
            maximum_measurements,
            maximum_frames,
        ).openDefault(),
        else => return load_error,
    };
    defer std.testing.allocator.free(runtime_path);
    return Loader(
        maximum_measurements,
        maximum_frames,
    ).openRuntime(std.testing.allocator, runtime_path);
}

test "standard HRTF loader reads a CC BY public fixture" {
    const path = std.testing.environ.getAlloc(
        std.testing.allocator,
        "ZIG_VST3_VIKING_SOFA_TEST_FILE",
    ) catch |load_error| switch (load_error) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return load_error,
    };
    defer std.testing.allocator.free(path);

    var loader = try openPublicTestLoader(1_513, 128);
    defer loader.deinit();
    const database = try std.testing.allocator.create(
        hrtf.Database(1_513, 128),
    );
    defer std.testing.allocator.destroy(database);
    try loader.loadFileInto(
        std.testing.allocator,
        path,
        database,
    );
    try std.testing.expectEqual(
        @as(usize, 1_513),
        database.measurement_count,
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        database.response_frame_count,
    );
    try std.testing.expectEqual(@as(u32, 48_000), database.sample_rate);
    try std.testing.expectEqual(
        hrtf.Direction{
            .azimuth_degrees = 0.0,
            .elevation_degrees = -45.0,
        },
        database.directions[0],
    );
    try std.testing.expectEqual(
        hrtf.Direction{
            .azimuth_degrees = -5.0,
            .elevation_degrees = -45.0,
        },
        database.directions[1],
    );
    try std.testing.expectEqual(
        @as(f32, @floatCast(-3.291246727869612e-05)),
        database.responses[0][1][0],
    );
    try std.testing.expectEqual(
        @as(f32, @floatCast(-4.532169016517203e-06)),
        database.responses[0][1][1],
    );
    try std.testing.expect(database.valid());

    const ReferenceRenderer = hrtf.Renderer(128, 8);
    var renderer = try ReferenceRenderer.init(48_000, .zero);
    try renderer.prepare(
        database,
        database.directions[0],
        .nearest,
        1,
    );
    try std.testing.expect(renderer.adoptPending());
    const landmarks = [_]struct {
        frame: usize,
        left: f32,
        right: f32,
    }{
        .{ .frame = 0, .left = 0.0, .right = -0.0 },
        .{
            .frame = 1,
            .left = @floatCast(-3.291246727869612e-05),
            .right = @floatCast(-4.532169016517203e-06),
        },
        .{
            .frame = 2,
            .left = @floatCast(0.00016669660850223125),
            .right = @floatCast(7.105737413937792e-05),
        },
        .{
            .frame = 3,
            .left = @floatCast(-0.0003543910958605596),
            .right = @floatCast(-0.0002460186435713287),
        },
        .{
            .frame = 20,
            .left = @floatCast(-0.07695341805993125),
            .right = @floatCast(-0.07333583739130722),
        },
        .{
            .frame = 50,
            .left = @floatCast(-0.0017677580567186757),
            .right = @floatCast(-0.029643876148183076),
        },
        .{
            .frame = 100,
            .left = @floatCast(-0.002584351474286651),
            .right = @floatCast(-0.004129589743778246),
        },
        .{ .frame = 127, .left = -0.0, .right = -0.0 },
    };
    var landmark_index: usize = 0;
    const render_tolerance = 4.0 * std.math.floatEps(f32);
    for (0..database.response_frame_count) |frame_index| {
        const output = renderer.processSample(
            if (frame_index == 0) 1.0 else 0.0,
        );
        if (landmark_index < landmarks.len and
            landmarks[landmark_index].frame == frame_index)
        {
            const expected = landmarks[landmark_index];
            try std.testing.expectApproxEqAbs(
                expected.left,
                output[0],
                render_tolerance,
            );
            try std.testing.expectApproxEqAbs(
                expected.right,
                output[1],
                render_tolerance,
            );
            landmark_index += 1;
        }
    }
    try std.testing.expectEqual(landmarks.len, landmark_index);

    const interpolated_direction = hrtf.Direction{
        .azimuth_degrees = -2.5,
        .elevation_degrees = -45.0,
    };
    var interpolated_response: [128 * 2]f32 = undefined;
    try database.interpolate(
        interpolated_direction,
        .inverse_distance,
        &interpolated_response,
    );
    const interpolated_landmark = [2]f32{
        @floatCast(-1.559319374694078e-05),
        @floatCast(1.1734604178882786e-05),
    };
    try std.testing.expectApproxEqAbs(
        interpolated_landmark[0],
        interpolated_response[2],
        render_tolerance,
    );
    try std.testing.expectApproxEqAbs(
        interpolated_landmark[1],
        interpolated_response[3],
        render_tolerance,
    );

    var delay_aligned_response: [128 * 2]f32 = undefined;
    try database.interpolate(
        interpolated_direction,
        .delay_aligned,
        &delay_aligned_response,
    );
    try std.testing.expectEqualSlices(
        f32,
        &interpolated_response,
        &delay_aligned_response,
    );

    var spectral_response: [128 * 2]f32 = undefined;
    try database.interpolate(
        interpolated_direction,
        .spectral,
        &spectral_response,
    );
    const spectral_landmarks = [_]struct {
        frame: usize,
        left: f32,
        right: f32,
    }{
        .{
            .frame = 0,
            .left = @floatCast(-0.00014641554476879407),
            .right = @floatCast(-9.148596076930889e-05),
        },
        .{
            .frame = 1,
            .left = @floatCast(0.00015262090927269274),
            .right = @floatCast(0.00024302195280927777),
        },
        .{
            .frame = 2,
            .left = @floatCast(8.613873591142176e-06),
            .right = @floatCast(-0.00025036630872719747),
        },
        .{
            .frame = 3,
            .left = @floatCast(-5.0358229486740674e-05),
            .right = @floatCast(-6.403247162809e-05),
        },
        .{
            .frame = 20,
            .left = @floatCast(-0.03704562866046532),
            .right = @floatCast(-0.054655135276875204),
        },
        .{
            .frame = 50,
            .left = @floatCast(0.0006635550719462254),
            .right = @floatCast(-0.0055680119137851555),
        },
        .{
            .frame = 100,
            .left = @floatCast(-0.000767226936593954),
            .right = @floatCast(-0.003674241841979325),
        },
        .{
            .frame = 127,
            .left = @floatCast(1.8607992171651274e-05),
            .right = @floatCast(-2.2031422763795755e-05),
        },
    };
    for (spectral_landmarks) |expected| {
        try std.testing.expectApproxEqAbs(
            expected.left,
            spectral_response[expected.frame * 2],
            render_tolerance,
        );
        try std.testing.expectApproxEqAbs(
            expected.right,
            spectral_response[expected.frame * 2 + 1],
            render_tolerance,
        );
    }

    var interpolation_renderer = try ReferenceRenderer.init(
        48_000,
        .zero,
    );
    try interpolation_renderer.prepare(
        database,
        interpolated_direction,
        .inverse_distance,
        2,
    );
    try std.testing.expect(interpolation_renderer.adoptPending());
    _ = interpolation_renderer.processSample(1.0);
    const interpolated_output = interpolation_renderer.processSample(0.0);
    try std.testing.expectApproxEqAbs(
        interpolated_landmark[0],
        interpolated_output[0],
        render_tolerance,
    );
    try std.testing.expectApproxEqAbs(
        interpolated_landmark[1],
        interpolated_output[1],
        render_tolerance,
    );
    loader.deinit();
    try std.testing.expect(!loader.isOpen());
    loader.deinit();
}

test "standard HRTF loader reads an independent CC BY fixture" {
    const path = std.testing.environ.getAlloc(
        std.testing.allocator,
        "ZIG_VST3_HUTUBS_SOFA_TEST_FILE",
    ) catch |load_error| switch (load_error) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return load_error,
    };
    defer std.testing.allocator.free(path);

    var loader = try openPublicTestLoader(440, 256);
    defer loader.deinit();
    const database = try std.testing.allocator.create(
        hrtf.Database(440, 256),
    );
    defer std.testing.allocator.destroy(database);
    try loader.loadFileInto(
        std.testing.allocator,
        path,
        database,
    );
    try std.testing.expectEqual(
        @as(usize, 440),
        database.measurement_count,
    );
    try std.testing.expectEqual(
        @as(usize, 256),
        database.response_frame_count,
    );
    try std.testing.expectEqual(@as(u32, 44_100), database.sample_rate);
    try std.testing.expectEqual(
        hrtf.Direction{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 90.0,
        },
        database.directions[0],
    );
    try std.testing.expectEqual(
        hrtf.Direction{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 80.0,
        },
        database.directions[1],
    );
    try std.testing.expectEqual(
        @as(f32, @floatCast(1.492182190074992e-06)),
        database.responses[0][1][0],
    );
    try std.testing.expectEqual(
        @as(f32, @floatCast(-5.014584512366679e-06)),
        database.responses[0][1][1],
    );
    try std.testing.expect(database.valid());
}
