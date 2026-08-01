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
    for (0..decoded.measurement_count) |measurement_index| {
        const position =
            decoded.source_positions[measurement_index * 3 ..][0..3];
        for (position) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidSofaPosition;
        }
        directions[measurement_index] = switch (decoded.position_encoding) {
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
                const direction = hrtf.Direction{
                    .azimuth_degrees = azimuth,
                    .elevation_degrees = position[1],
                };
                break :blk direction;
            },
            .cartesian_metres => hrtf.directionFromPositions(
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
    ).initWithDelays(
        first_rate,
        directions[0..decoded.measurement_count],
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

fn terminatedPath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![:0]u8 {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null)
        return error.InvalidSofaPath;
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

        library: DynamicLibrary,
        api: Api,

        pub fn openDefault() !Self {
            const names = switch (builtin.os.tag) {
                .windows => &[_][:0]const u8{
                    "netcdf.dll",
                    "netcdf-19.dll",
                },
                .macos => &[_][:0]const u8{
                    "libnetcdf.19.dylib",
                    "libnetcdf.dylib",
                },
                else => &[_][:0]const u8{
                    "libnetcdf.so.19",
                    "libnetcdf.so",
                },
            };
            for (names) |name| {
                var library =
                    DynamicLibrary.open(name) catch continue;
                const api = Api.load(&library) catch {
                    library.close();
                    continue;
                };
                return .{ .library = library, .api = api };
            }
            return error.SofaRuntimeUnavailable;
        }

        pub fn deinit(self: *Self) void {
            self.library.close();
            self.* = undefined;
        }

        pub fn loadFile(
            self: *const Self,
            allocator: std.mem.Allocator,
            path: []const u8,
        ) !DatabaseType {
            const terminated_path = try terminatedPath(allocator, path);
            defer allocator.free(terminated_path);

            var file_id: c_int = 0;
            try check(self.api.open(
                terminated_path.ptr,
                nc_nowrite,
                &file_id,
            ));
            defer _ = self.api.close(file_id);

            try requireAttribute(
                &self.api,
                file_id,
                nc_global,
                "SOFAConventions",
                "SimpleFreeFieldHRIR",
            );
            try requireAttribute(
                &self.api,
                file_id,
                nc_global,
                "DataType",
                "FIR",
            );
            try requireAttribute(
                &self.api,
                file_id,
                nc_global,
                "RoomType",
                "free field",
            );
            try requireOneOfAttributes(
                &self.api,
                file_id,
                nc_global,
                "SOFAConventionsVersion",
                &.{ "1.0", "1.1", "1.2" },
            );

            const maximum_ir_values = responseValueCount(
                maximum_measurements,
                maximum_frames,
            ) catch return error.SofaDatasetTooLarge;

            const ir = try readVariable(
                &self.api,
                allocator,
                file_id,
                "Data.IR",
                3,
                maximum_ir_values,
            );
            defer allocator.free(ir.values);
            if (ir.shape[1] != 2)
                return error.UnsupportedSofaReceiverCount;

            const positions = try readVariable(
                &self.api,
                allocator,
                file_id,
                "SourcePosition",
                2,
                std.math.mul(
                    usize,
                    maximum_measurements,
                    3,
                ) catch return error.SofaDatasetTooLarge,
            );
            defer allocator.free(positions.values);
            if (positions.shape[0] != ir.shape[0] or
                positions.shape[1] != 3)
                return error.InvalidSofaPositionShape;
            try requireDefaultListenerGeometry(
                &self.api,
                allocator,
                file_id,
                ir.shape[0],
            );
            const position_encoding = try positionEncoding(
                &self.api,
                file_id,
                positions.variable_id,
            );

            const rates = try readVariable(
                &self.api,
                allocator,
                file_id,
                "Data.SamplingRate",
                null,
                maximum_measurements,
            );
            defer allocator.free(rates.values);
            if (!validSamplingRateVariable(rates, ir.shape[0]))
                return error.InvalidSofaSamplingRateShape;
            try requireAttribute(
                &self.api,
                file_id,
                rates.variable_id,
                "Units",
                "hertz",
            );

            var delays: []f64 = &.{};
            var delay_variable_id: c_int = 0;
            if (self.api.inquire_variable_id(
                file_id,
                "Data.Delay",
                &delay_variable_id,
            ) == nc_no_error) {
                const loaded = try readVariableById(
                    &self.api,
                    allocator,
                    file_id,
                    delay_variable_id,
                    null,
                    std.math.mul(
                        usize,
                        maximum_measurements,
                        2,
                    ) catch return error.SofaDatasetTooLarge,
                );
                delays = loaded.values;
                if (!validDelayVariable(loaded, ir.shape[0])) {
                    allocator.free(delays);
                    return error.InvalidSofaDelayShape;
                }
            }
            defer if (delays.len != 0) allocator.free(delays);

            return databaseFromDecoded(
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
            );
        }
    };
}

const nc_no_error: c_int = 0;
const nc_nowrite: c_int = 0;
const nc_global: c_int = -1;

const DynamicLibrary = if (builtin.os.tag == .windows)
    WindowsDynamicLibrary
else
    std.DynLib;

const WindowsDynamicLibrary = struct {
    const windows = std.os.windows;

    handle: windows.HMODULE,

    fn open(name: [:0]const u8) !WindowsDynamicLibrary {
        return .{
            .handle = LoadLibraryA(name.ptr) orelse
                return error.LoadDynamicLibraryFailed,
        };
    }

    fn close(self: *WindowsDynamicLibrary) void {
        _ = FreeLibrary(self.handle);
        self.* = undefined;
    }

    fn lookup(
        self: *WindowsDynamicLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        const procedure =
            GetProcAddress(self.handle, name.ptr) orelse return null;
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
        .values = values,
    };
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

fn requireOneOfAttributes(
    api: *const Api,
    file_id: c_int,
    variable_id: c_int,
    name: [:0]const u8,
    expected: []const []const u8,
) !void {
    var buffer: [256]u8 = undefined;
    const value = try attribute(
        api,
        file_id,
        variable_id,
        name,
        &buffer,
    );
    for (expected) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return;
    }
    return error.UnsupportedSofaConvention;
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
    const listener_up_encoding = positionEncoding(
        api,
        file_id,
        listener_up.variable_id,
    ) catch return error.UnsupportedSofaListenerGeometry;
    if (listener_position_encoding != .cartesian_metres or
        listener_view_encoding != .cartesian_metres or
        listener_up_encoding != .cartesian_metres)
        return error.UnsupportedSofaListenerGeometry;
    try requireDefaultVectors(
        listener_position,
        measurement_count,
        .{ 0.0, 0.0, 0.0 },
    );
    try requireDefaultVectors(
        listener_view,
        measurement_count,
        .{ 1.0, 0.0, 0.0 },
    );
    try requireDefaultVectors(
        listener_up,
        measurement_count,
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
    if (receivers.shape[0] != 2 or
        receivers.shape[1] != 3 or
        (receivers.shape[2] != 1 and
            receivers.shape[2] != measurement_count))
        return error.UnsupportedSofaReceiverGeometry;
    const receiver_measurements = receivers.shape[2];
    for (0..receiver_measurements) |measurement_index| {
        const left_y = receivers.values[
            receiver_measurements + measurement_index
        ];
        const right_y = receivers.values[
            4 * receiver_measurements + measurement_index
        ];
        if (!std.math.isFinite(left_y) or
            !std.math.isFinite(right_y) or
            left_y <= 0.0 or right_y >= 0.0)
            return error.UnsupportedSofaReceiverGeometry;
    }
}

fn requireDefaultVectors(
    variable: Variable,
    measurement_count: usize,
    expected: [3]f64,
) !void {
    if ((variable.shape[0] != 1 and
        variable.shape[0] != measurement_count) or
        variable.shape[1] != 3)
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
}

test "standard HRTF loader reads an external public fixture" {
    const path = std.testing.environ.getAlloc(
        std.testing.allocator,
        "ZIG_VST3_SOFA_TEST_FILE",
    ) catch |load_error| switch (load_error) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return load_error,
    };
    defer std.testing.allocator.free(path);

    const PublicLoader = Loader(1_250, 260);
    var loader =
        PublicLoader.openDefault() catch return error.SkipZigTest;
    defer loader.deinit();
    const database = try loader.loadFile(
        std.testing.allocator,
        path,
    );
    try std.testing.expectEqual(
        @as(usize, 1_250),
        database.measurement_count,
    );
    try std.testing.expectEqual(
        @as(usize, 256),
        database.response_frame_count,
    );
    try std.testing.expect(database.valid());
}
