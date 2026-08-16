const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor;

const PatchIds = struct {
    sequence: core.lv2.Urid,
    chunk: core.lv2.Urid,
    object: core.lv2.Urid,
    blank: core.lv2.Urid,
    int: core.lv2.Urid,
    path: core.lv2.Urid,
    urid: core.lv2.Urid,
    get: core.lv2.Urid,
    set: core.lv2.Urid,
    ack: core.lv2.Urid,
    graph_error: core.lv2.Urid,
    put: core.lv2.Urid,
    insert: core.lv2.Urid,
    patch: core.lv2.Urid,
    delete: core.lv2.Urid,
    copy: core.lv2.Urid,
    move: core.lv2.Urid,
    accept: core.lv2.Urid,
    add: core.lv2.Urid,
    remove: core.lv2.Urid,
    body: core.lv2.Urid,
    context: core.lv2.Urid,
    destination: core.lv2.Urid,
    property: core.lv2.Urid,
    request: core.lv2.Urid,
    sequence_number: core.lv2.Urid,
    subject: core.lv2.Urid,
    value: core.lv2.Urid,
    plugin: core.lv2.Urid,
    mode: core.lv2.Urid,
    resource: core.lv2.Urid,
    graph_subject: core.lv2.Urid,
    graph_subject_two: core.lv2.Urid,
    graph_destination: core.lv2.Urid,
    graph_context: core.lv2.Urid,
    state_changed: core.lv2.Urid,
};

const PatchSequence = extern struct {
    sequence: core.lv2.AtomSequence,
    storage: [4096]u8,

    fn empty(ids: PatchIds) PatchSequence {
        var result = std.mem.zeroes(PatchSequence);
        result.sequence = .{
            .atom = .{
                .size = @sizeOf(core.lv2.AtomSequenceBody),
                .type = ids.sequence,
            },
            .body = .{ .unit = 0, .pad = 0 },
        };
        return result;
    }

    fn resetOutput(self: *PatchSequence, ids: PatchIds) void {
        self.* = std.mem.zeroes(PatchSequence);
        self.sequence.atom = .{
            .size = @sizeOf(core.lv2.AtomSequenceBody) +
                self.storage.len,
            .type = ids.chunk,
        };
    }
};

const PatchBuilder = struct {
    buffer: *PatchSequence,
    event: *core.lv2.AtomEvent,
    payload_start: usize,
    cursor: usize,

    fn init(
        buffer: *PatchSequence,
        ids: PatchIds,
        frame_offset: i64,
        message_type: core.lv2.Urid,
    ) PatchBuilder {
        buffer.* = PatchSequence.empty(ids);
        const bytes: [*]u8 = @ptrCast(&buffer.sequence.body);
        const event_offset = @sizeOf(core.lv2.AtomSequenceBody);
        const event: *core.lv2.AtomEvent = @ptrCast(
            @alignCast(bytes + event_offset),
        );
        event.* = .{
            .time = .{ .frames = frame_offset },
            .body = .{
                .size = @sizeOf(core.lv2.AtomObjectBody),
                .type = ids.object,
            },
        };
        const payload_start = event_offset +
            @sizeOf(core.lv2.AtomEvent);
        const object: *core.lv2.AtomObjectBody = @ptrCast(
            @alignCast(bytes + payload_start),
        );
        object.* = .{ .id = 0, .otype = message_type };
        var result = PatchBuilder{
            .buffer = buffer,
            .event = event,
            .payload_start = payload_start,
            .cursor = payload_start +
                @sizeOf(core.lv2.AtomObjectBody),
        };
        result.finish();
        return result;
    }

    fn append(
        self: *PatchBuilder,
        key: core.lv2.Urid,
        value_type: core.lv2.Urid,
        value: []const u8,
    ) !void {
        const raw_size = @sizeOf(core.lv2.AtomPropertyBody) +
            value.len;
        const padded_size = std.mem.alignForward(
            usize,
            raw_size,
            8,
        );
        const bytes: [*]u8 = @ptrCast(&self.buffer.sequence.body);
        if (self.cursor + padded_size >
            @sizeOf(core.lv2.AtomSequenceBody) +
                self.buffer.storage.len)
            return error.PatchMessageTooLarge;
        const property: *core.lv2.AtomPropertyBody = @ptrCast(
            @alignCast(bytes + self.cursor),
        );
        property.* = .{
            .key = key,
            .context = 0,
            .value = .{
                .size = @intCast(value.len),
                .type = value_type,
            },
        };
        @memcpy(
            bytes[self.cursor + @sizeOf(core.lv2.AtomPropertyBody) .. self.cursor + @sizeOf(core.lv2.AtomPropertyBody) +
                value.len],
            value,
        );
        @memset(
            bytes[self.cursor + raw_size .. self.cursor + padded_size],
            0,
        );
        self.cursor += padded_size;
        self.finish();
    }

    fn appendString(
        self: *PatchBuilder,
        key: core.lv2.Urid,
        value_type: core.lv2.Urid,
        value: []const u8,
    ) !void {
        var terminated: [257]u8 = @splat(0);
        if (value.len > terminated.len - 1)
            return error.PatchMessageTooLarge;
        @memcpy(terminated[0..value.len], value);
        try self.append(
            key,
            value_type,
            terminated[0 .. value.len + 1],
        );
    }

    fn identify(
        self: *PatchBuilder,
        atom_type: core.lv2.Urid,
        id: u32,
    ) void {
        self.event.body.type = atom_type;
        const bytes: [*]u8 = @ptrCast(&self.buffer.sequence.body);
        const object: *align(1) core.lv2.AtomObjectBody =
            @ptrCast(bytes + self.payload_start);
        object.id = id;
    }

    fn finish(self: *PatchBuilder) void {
        const payload_size = self.cursor - self.payload_start;
        self.event.body.size = @intCast(payload_size);
        self.buffer.sequence.atom.size = @intCast(self.cursor);
    }
};

fn readPatchRequestReference(
    atom_type: core.lv2.Urid,
    body: []const u8,
    ids: PatchIds,
) !core.lv2.PatchRequestReference {
    if ((atom_type != ids.object and atom_type != ids.blank) or
        body.len != @sizeOf(core.lv2.AtomObjectBody))
        return error.InvalidPatchRequestReference;
    const object: *align(1) const core.lv2.AtomObjectBody =
        @ptrCast(body.ptr);
    if (object.id == 0 or object.otype == 0)
        return error.InvalidPatchRequestReference;
    return .{
        .atom_type = atom_type,
        .id = object.id,
        .object_type = object.otype,
    };
}

fn readStateChanged(
    buffer: *const PatchSequence,
    ids: PatchIds,
) !i64 {
    const event_size = std.mem.alignForward(
        usize,
        @sizeOf(core.lv2.AtomEvent) +
            @sizeOf(core.lv2.AtomObjectBody),
        8,
    );
    if (buffer.sequence.atom.type != ids.sequence or
        buffer.sequence.atom.size !=
            @sizeOf(core.lv2.AtomSequenceBody) + event_size)
        return error.InvalidStateChangedEvent;
    const bytes: [*]const u8 = @ptrCast(&buffer.sequence.body);
    const event: *align(1) const core.lv2.AtomEvent = @ptrCast(
        bytes + @sizeOf(core.lv2.AtomSequenceBody),
    );
    if (event.body.type != ids.object or
        event.body.size != @sizeOf(core.lv2.AtomObjectBody))
        return error.InvalidStateChangedEvent;
    const object: *align(1) const core.lv2.AtomObjectBody = @ptrCast(
        bytes + @sizeOf(core.lv2.AtomSequenceBody) +
            @sizeOf(core.lv2.AtomEvent),
    );
    if (object.id != 0 or object.otype != ids.state_changed)
        return error.InvalidStateChangedEvent;
    return event.time.frames;
}

const PatchResponse = struct {
    frame_offset: i64,
    property: core.lv2.Urid,
    sequence_number: ?i32,
    request: ?core.lv2.PatchRequestReference,
    subject: ?core.lv2.Urid,
    value_type: core.lv2.Urid,
    value: []const u8,
};

fn readPatchResponse(
    buffer: *const PatchSequence,
    ids: PatchIds,
) !PatchResponse {
    if (buffer.sequence.atom.type != ids.sequence or
        buffer.sequence.atom.size < @sizeOf(core.lv2.AtomSequenceBody) +
            @sizeOf(core.lv2.AtomEvent) +
            @sizeOf(core.lv2.AtomObjectBody))
        return error.InvalidPatchResponse;
    const bytes: [*]const u8 = @ptrCast(&buffer.sequence.body);
    const event_offset = @sizeOf(core.lv2.AtomSequenceBody);
    const event: *const core.lv2.AtomEvent = @ptrCast(
        @alignCast(bytes + event_offset),
    );
    if (event.body.type != ids.object)
        return error.InvalidPatchResponse;
    const payload_start = event_offset + @sizeOf(core.lv2.AtomEvent);
    const payload_size: usize = event.body.size;
    if (payload_start + payload_size > buffer.sequence.atom.size)
        return error.InvalidPatchResponse;
    const object: *align(1) const core.lv2.AtomObjectBody =
        @ptrCast(bytes + payload_start);
    if (object.otype != ids.set) return error.InvalidPatchResponse;
    var property_urid: ?core.lv2.Urid = null;
    var sequence_number: ?i32 = null;
    var request: ?core.lv2.PatchRequestReference = null;
    var subject: ?core.lv2.Urid = null;
    var value_type: ?core.lv2.Urid = null;
    var value: []const u8 = &.{};
    var cursor: usize =
        payload_start + @sizeOf(core.lv2.AtomObjectBody);
    const payload_end = payload_start + payload_size;
    while (cursor < payload_end) {
        if (payload_end - cursor <
            @sizeOf(core.lv2.AtomPropertyBody))
            return error.InvalidPatchResponse;
        const property: *align(1) const core.lv2.AtomPropertyBody =
            @ptrCast(bytes + cursor);
        const raw_size = @sizeOf(core.lv2.AtomPropertyBody) +
            property.value.size;
        const padded_size = std.mem.alignForward(
            usize,
            raw_size,
            8,
        );
        if (padded_size > payload_end - cursor)
            return error.InvalidPatchResponse;
        const body = bytes[cursor +
            @sizeOf(core.lv2.AtomPropertyBody) .. cursor + raw_size];
        if (property.key == ids.property) {
            if (property_urid != null or
                property.value.type != ids.urid or
                body.len != @sizeOf(core.lv2.Urid))
                return error.InvalidPatchResponse;
            property_urid = @as(
                *align(1) const core.lv2.Urid,
                @ptrCast(body.ptr),
            ).*;
        } else if (property.key == ids.sequence_number) {
            if (sequence_number != null or
                property.value.type != ids.int or
                body.len != @sizeOf(i32))
                return error.InvalidPatchResponse;
            sequence_number = @as(
                *align(1) const i32,
                @ptrCast(body.ptr),
            ).*;
        } else if (property.key == ids.request) {
            if (request != null) return error.InvalidPatchResponse;
            request = try readPatchRequestReference(
                property.value.type,
                body,
                ids,
            );
        } else if (property.key == ids.subject) {
            if (subject != null or
                property.value.type != ids.urid or
                body.len != @sizeOf(core.lv2.Urid))
                return error.InvalidPatchResponse;
            subject = @as(
                *align(1) const core.lv2.Urid,
                @ptrCast(body.ptr),
            ).*;
        } else if (property.key == ids.value) {
            if (value_type != null) return error.InvalidPatchResponse;
            value_type = property.value.type;
            value = body;
        }
        cursor += padded_size;
    }
    return .{
        .frame_offset = event.time.frames,
        .property = property_urid orelse
            return error.InvalidPatchResponse,
        .sequence_number = sequence_number,
        .request = request,
        .subject = subject,
        .value_type = value_type orelse
            return error.InvalidPatchResponse,
        .value = value,
    };
}

const PatchGraphPutResponse = struct {
    frame_offset: i64,
    subject: ?core.lv2.Urid,
    context: ?core.lv2.Urid,
    sequence_number: ?i32,
    request: ?core.lv2.PatchRequestReference,
    body_type: core.lv2.Urid,
    body: []const u8,
};

fn readPatchGraphPutResponse(
    buffer: *const PatchSequence,
    ids: PatchIds,
) !PatchGraphPutResponse {
    if (buffer.sequence.atom.type != ids.sequence or
        buffer.sequence.atom.size < @sizeOf(core.lv2.AtomSequenceBody) +
            @sizeOf(core.lv2.AtomEvent) +
            @sizeOf(core.lv2.AtomObjectBody))
        return error.InvalidPatchGraphPutResponse;
    const bytes: [*]const u8 = @ptrCast(&buffer.sequence.body);
    const event_offset = @sizeOf(core.lv2.AtomSequenceBody);
    const event: *const core.lv2.AtomEvent = @ptrCast(
        @alignCast(bytes + event_offset),
    );
    if (event.body.type != ids.object)
        return error.InvalidPatchGraphPutResponse;
    const payload_start = event_offset + @sizeOf(core.lv2.AtomEvent);
    const payload_size: usize = event.body.size;
    if (payload_start + payload_size > buffer.sequence.atom.size)
        return error.InvalidPatchGraphPutResponse;
    const object: *align(1) const core.lv2.AtomObjectBody =
        @ptrCast(bytes + payload_start);
    if (object.otype != ids.put)
        return error.InvalidPatchGraphPutResponse;

    var subject: ?core.lv2.Urid = null;
    var context: ?core.lv2.Urid = null;
    var sequence_number: ?i32 = null;
    var request: ?core.lv2.PatchRequestReference = null;
    var body_type: ?core.lv2.Urid = null;
    var body: []const u8 = &.{};
    var cursor: usize = payload_start + @sizeOf(core.lv2.AtomObjectBody);
    const payload_end = payload_start + payload_size;
    while (cursor < payload_end) {
        if (payload_end - cursor < @sizeOf(core.lv2.AtomPropertyBody))
            return error.InvalidPatchGraphPutResponse;
        const property: *align(1) const core.lv2.AtomPropertyBody =
            @ptrCast(bytes + cursor);
        const raw_size = @sizeOf(core.lv2.AtomPropertyBody) +
            property.value.size;
        const padded_size = std.mem.alignForward(usize, raw_size, 8);
        if (padded_size > payload_end - cursor)
            return error.InvalidPatchGraphPutResponse;
        const value = bytes[cursor +
            @sizeOf(core.lv2.AtomPropertyBody) .. cursor + raw_size];
        if (property.key == ids.subject) {
            if (subject != null or property.value.type != ids.urid or
                value.len != @sizeOf(core.lv2.Urid))
                return error.InvalidPatchGraphPutResponse;
            subject = @as(
                *align(1) const core.lv2.Urid,
                @ptrCast(value.ptr),
            ).*;
        } else if (property.key == ids.context) {
            if (context != null or property.value.type != ids.urid or
                value.len != @sizeOf(core.lv2.Urid))
                return error.InvalidPatchGraphPutResponse;
            context = @as(
                *align(1) const core.lv2.Urid,
                @ptrCast(value.ptr),
            ).*;
        } else if (property.key == ids.sequence_number) {
            if (sequence_number != null or
                property.value.type != ids.int or
                value.len != @sizeOf(i32))
                return error.InvalidPatchGraphPutResponse;
            sequence_number = @as(
                *align(1) const i32,
                @ptrCast(value.ptr),
            ).*;
        } else if (property.key == ids.request) {
            if (request != null)
                return error.InvalidPatchGraphPutResponse;
            request = try readPatchRequestReference(
                property.value.type,
                value,
                ids,
            );
        } else if (property.key == ids.body) {
            if (body_type != null or property.value.type == 0)
                return error.InvalidPatchGraphPutResponse;
            body_type = property.value.type;
            body = value;
        }
        cursor += padded_size;
    }
    return .{
        .frame_offset = event.time.frames,
        .subject = subject,
        .context = context,
        .sequence_number = sequence_number,
        .request = request,
        .body_type = body_type orelse
            return error.InvalidPatchGraphPutResponse,
        .body = body,
    };
}

const PatchGraphResponse = struct {
    frame_offset: i64,
    response_type: core.lv2.Urid,
    context: ?core.lv2.Urid,
    sequence_number: ?i32,
    request: ?core.lv2.PatchRequestReference,
};

fn readPatchGraphResponse(
    buffer: *const PatchSequence,
    ids: PatchIds,
) !PatchGraphResponse {
    if (buffer.sequence.atom.type != ids.sequence or
        buffer.sequence.atom.size < @sizeOf(core.lv2.AtomSequenceBody) +
            @sizeOf(core.lv2.AtomEvent) +
            @sizeOf(core.lv2.AtomObjectBody))
        return error.InvalidPatchGraphResponse;
    const bytes: [*]const u8 = @ptrCast(&buffer.sequence.body);
    const event_offset = @sizeOf(core.lv2.AtomSequenceBody);
    const event: *const core.lv2.AtomEvent = @ptrCast(
        @alignCast(bytes + event_offset),
    );
    if (event.body.type != ids.object)
        return error.InvalidPatchGraphResponse;
    const payload_start = event_offset + @sizeOf(core.lv2.AtomEvent);
    const payload_size: usize = event.body.size;
    if (payload_start + payload_size > buffer.sequence.atom.size)
        return error.InvalidPatchGraphResponse;
    const object: *align(1) const core.lv2.AtomObjectBody =
        @ptrCast(bytes + payload_start);
    if (object.otype != ids.ack and
        object.otype != ids.graph_error)
        return error.InvalidPatchGraphResponse;
    var sequence_number: ?i32 = null;
    var context: ?core.lv2.Urid = null;
    var request: ?core.lv2.PatchRequestReference = null;
    var cursor: usize =
        payload_start + @sizeOf(core.lv2.AtomObjectBody);
    const payload_end = payload_start + payload_size;
    while (cursor < payload_end) {
        if (payload_end - cursor <
            @sizeOf(core.lv2.AtomPropertyBody))
            return error.InvalidPatchGraphResponse;
        const property: *align(1) const core.lv2.AtomPropertyBody =
            @ptrCast(bytes + cursor);
        const raw_size = @sizeOf(core.lv2.AtomPropertyBody) +
            property.value.size;
        const padded_size = std.mem.alignForward(
            usize,
            raw_size,
            8,
        );
        if (padded_size > payload_end - cursor)
            return error.InvalidPatchGraphResponse;
        const body = bytes[cursor +
            @sizeOf(core.lv2.AtomPropertyBody) .. cursor + raw_size];
        if (property.key == ids.sequence_number) {
            if (sequence_number != null or
                property.value.type != ids.int or
                body.len != @sizeOf(i32))
                return error.InvalidPatchGraphResponse;
            sequence_number = @as(
                *align(1) const i32,
                @ptrCast(body.ptr),
            ).*;
        } else if (property.key == ids.context) {
            if (context != null or property.value.type != ids.urid or
                body.len != @sizeOf(core.lv2.Urid))
                return error.InvalidPatchGraphResponse;
            context = @as(
                *align(1) const core.lv2.Urid,
                @ptrCast(body.ptr),
            ).*;
        } else if (property.key == ids.request) {
            if (request != null)
                return error.InvalidPatchGraphResponse;
            request = try readPatchRequestReference(
                property.value.type,
                body,
                ids,
            );
        }
        cursor += padded_size;
    }
    return .{
        .frame_offset = event.time.frames,
        .response_type = object.otype,
        .context = context,
        .sequence_number = sequence_number,
        .request = request,
    };
}

fn runPatchGraphRequest(
    descriptor: *const core.lv2.Descriptor,
    handle: core.lv2.Handle,
    end_run: *const fn (
        core.lv2.Handle,
    ) callconv(.c) core.lv2.WorkerStatus,
    output: *[2]f32,
    event_output: *PatchSequence,
    ids: PatchIds,
    sequence_number: i32,
    response_type: core.lv2.Urid,
    expected_mode: u32,
) !void {
    event_output.resetOutput(ids);
    descriptor.run(handle, output.len);
    const response = try readPatchGraphResponse(event_output, ids);
    if (response.frame_offset != 0 or
        response.response_type != response_type or
        response.sequence_number != sequence_number or
        response.request != null)
        return error.InvalidPatchGraphResponse;
    const mode: f32 = @floatFromInt(expected_mode);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ mode + 3.375, mode + 2.25 },
        output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;
}

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

const ResizePortHost = struct {
    call_count: usize = 0,
    port_index: u32 = std.math.maxInt(u32),
    size: usize = 0,

    fn resize(
        raw: ?*anyopaque,
        port_index: u32,
        size: usize,
    ) callconv(.c) core.lv2.ResizePortStatus {
        const self: *@This() = @ptrCast(
            @alignCast(raw orelse return .unknown),
        );
        self.call_count += 1;
        self.port_index = port_index;
        self.size = size;
        return .success;
    }
};

const LogCapture = extern struct {
    call_count: u32 = 0,
    last_type: core.lv2.Urid = 0,
    result: c_int = 28,
    format_size: usize = 0,
    message_size: usize = 0,
    format: [16]u8 = @splat(0),
    message: [128]u8 = @splat(0),
};

extern fn zig_lv2_log_capture_printf(
    raw_capture: ?*anyopaque,
    log_type: core.lv2.Urid,
    format: [*:0]const u8,
    ...,
) callconv(.c) c_int;

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
    const patch_ids = PatchIds{
        .sequence = StateHost.map(null, core.lv2.atom_sequence_uri),
        .chunk = StateHost.map(null, core.lv2.atom_chunk_uri),
        .object = StateHost.map(null, core.lv2.atom_object_uri),
        .blank = StateHost.map(null, core.lv2.atom_blank_uri),
        .int = StateHost.map(null, core.lv2.atom_int_uri),
        .path = StateHost.map(null, core.lv2.atom_path_uri),
        .urid = StateHost.map(null, core.lv2.atom_urid_uri),
        .get = StateHost.map(null, core.lv2.patch_get_uri),
        .set = StateHost.map(null, core.lv2.patch_set_uri),
        .ack = StateHost.map(null, core.lv2.patch_ack_uri),
        .graph_error = StateHost.map(null, core.lv2.patch_error_uri),
        .put = StateHost.map(null, core.lv2.patch_put_uri),
        .insert = StateHost.map(null, core.lv2.patch_insert_uri),
        .patch = StateHost.map(null, core.lv2.patch_patch_uri),
        .delete = StateHost.map(null, core.lv2.patch_delete_uri),
        .copy = StateHost.map(null, core.lv2.patch_copy_uri),
        .move = StateHost.map(null, core.lv2.patch_move_uri),
        .accept = StateHost.map(null, core.lv2.patch_accept_uri),
        .add = StateHost.map(null, core.lv2.patch_add_uri),
        .remove = StateHost.map(null, core.lv2.patch_remove_uri),
        .body = StateHost.map(null, core.lv2.patch_body_uri),
        .context = StateHost.map(null, core.lv2.patch_context_uri),
        .destination = StateHost.map(
            null,
            core.lv2.patch_destination_uri,
        ),
        .property = StateHost.map(null, core.lv2.patch_property_uri),
        .request = StateHost.map(null, core.lv2.patch_request_uri),
        .sequence_number = StateHost.map(
            null,
            core.lv2.patch_sequence_number_uri,
        ),
        .subject = StateHost.map(null, core.lv2.patch_subject_uri),
        .value = StateHost.map(null, core.lv2.patch_value_uri),
        .plugin = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state",
        ),
        .mode = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#mode",
        ),
        .resource = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#resource",
        ),
        .graph_subject = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#graph-a",
        ),
        .graph_subject_two = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#graph-b",
        ),
        .graph_destination = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#graph-dest",
        ),
        .graph_context = StateHost.map(
            null,
            "https://zig-vst3.dev/tests/lv2-component-state#graph-context",
        ),
        .state_changed = StateHost.map(
            null,
            core.lv2.state_changed_uri,
        ),
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
    const thread_safe_state_features =
        [_:null]?*const core.lv2.Feature{
            &state_map_feature,
            &state_free_feature,
            &state_make_feature,
            &worker_feature,
        };
    var resize_port_host = ResizePortHost{};
    var resize_port = core.lv2.ResizePortFeature{
        .data = &resize_port_host,
        .resize = ResizePortHost.resize,
    };
    var resize_port_feature = core.lv2.Feature{
        .URI = core.lv2.resize_port_resize_uri,
        .data = &resize_port,
    };
    var log_capture = LogCapture{};
    var log = core.lv2.LogFeature{
        .handle = &log_capture,
        .printf = zig_lv2_log_capture_printf,
        .vprintf = null,
    };
    var log_feature = core.lv2.Feature{
        .URI = core.lv2.log_log_uri,
        .data = &log,
    };
    var null_worker_schedule = core.lv2.WorkerSchedule{
        .handle = null,
        .schedule_work = null,
    };
    const null_worker_feature = core.lv2.Feature{
        .URI = core.lv2.worker_schedule_uri,
        .data = &null_worker_schedule,
    };
    const null_worker_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &null_worker_feature,
    };
    var null_resize_port = core.lv2.ResizePortFeature{
        .data = null,
        .resize = null,
    };
    const null_resize_port_feature = core.lv2.Feature{
        .URI = core.lv2.resize_port_resize_uri,
        .data = &null_resize_port,
    };
    const null_resize_port_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &null_resize_port_feature,
    };
    var null_log = core.lv2.LogFeature{
        .handle = null,
        .printf = null,
        .vprintf = null,
    };
    const null_log_feature = core.lv2.Feature{
        .URI = core.lv2.log_log_uri,
        .data = &null_log,
    };
    const null_log_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &null_log_feature,
    };
    const features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &resize_port_feature,
        &log_feature,
    };
    const duplicate_map_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &map_feature,
    };
    const duplicate_worker_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &worker_feature,
    };
    const duplicate_resize_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &resize_port_feature,
        &resize_port_feature,
    };
    const duplicate_log_features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &worker_feature,
        &log_feature,
        &log_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        null,
    ) != null) return error.NullFeatureListAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        null_worker_features[0..].ptr,
    ) != null) return error.NullWorkerScheduleCallbackAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        null_resize_port_features[0..].ptr,
    ) != null) return error.NullResizePortCallbackAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        null_log_features[0..].ptr,
    ) != null) return error.NullLogCallbackAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        duplicate_map_features[0..].ptr,
    ) != null) return error.DuplicateUridMapAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        duplicate_worker_features[0..].ptr,
    ) != null) return error.DuplicateWorkerFeatureAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        duplicate_resize_features[0..].ptr,
    ) != null) return error.DuplicateResizeFeatureAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        duplicate_log_features[0..].ptr,
    ) != null) return error.DuplicateLogFeatureAccepted;
    var unterminated_features: [256]?*const core.lv2.Feature =
        @splat(&map_feature);
    const unterminated_list: ?[*:null]const ?*const core.lv2.Feature =
        @ptrCast(&unterminated_features);
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        unterminated_list,
    ) != null) return error.UnterminatedFeatureListAccepted;
    const missing_uri_feature = core.lv2.Feature{
        .URI = null,
        .data = null,
    };
    const missing_uri_features = [_:null]?*const core.lv2.Feature{
        &missing_uri_feature,
        &map_feature,
    };
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        &missing_uri_features,
    ) != null) return error.MissingFeatureUriAccepted;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-component-state.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    worker_host.instance = handle;
    if (worker_interface.work(
        handle,
        null,
        &worker_host,
        1,
        "x".ptr,
    ) != .unknown) return error.NullWorkerRespondCallbackAccepted;

    const raw_state = descriptor.extension_data(
        core.lv2.state_interface_uri,
    ) orelse return error.MissingStateInterface;
    const state: *const core.lv2.StateInterface =
        @ptrCast(@alignCast(raw_state));
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{0.0} ** input.len;
    var event_input = PatchSequence.empty(patch_ids);
    var event_output = std.mem.zeroes(PatchSequence);
    var gain: f32 = 1.5;
    var latency: f32 = 0;
    descriptor.connect_port(handle, 0, @constCast(&input));
    descriptor.connect_port(handle, 1, &output);
    descriptor.connect_port(handle, 2, &event_input);
    descriptor.connect_port(handle, 3, &event_output);
    descriptor.connect_port(handle, 4, &gain);
    descriptor.connect_port(handle, 5, &latency);

    if (descriptor.activate) |activate| activate(handle);
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    if (resize_port_host.call_count != 1 or
        resize_port_host.port_index != 3 or
        resize_port_host.size != 4096)
        return error.PortResizeRequestMismatch;
    if (log_capture.call_count != 1 or
        log_capture.last_type != StateHost.map(null, core.lv2.log_trace_uri) or
        log_capture.format_size != 2 or
        !std.mem.eql(u8, log_capture.format[0..2], "%s") or
        log_capture.message_size != "component-state process 100%".len or
        !std.mem.eql(
            u8,
            log_capture.message[0..log_capture.message_size],
            "component-state process 100%",
        ))
        return error.LogMessageMismatch;
    if (!worker_host.request_pending or worker_host.work_count != 0)
        return error.WorkerWasNotScheduled;
    if (worker_host.response_count != 0)
        return error.WorkerRespondedSynchronously;
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 7.375, 6.25 },
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
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 7.375, 6.25 },
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

    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 10.375, 9.25 },
        &output,
    );
    if (try readStateChanged(&event_output, patch_ids) !=
        input.len - 1)
        return error.InvalidStateChangedFrame;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    var patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        1,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.plugin),
    );
    const next_mode: i32 = 11;
    try patch.append(
        patch_ids.value,
        patch_ids.int,
        std.mem.asBytes(&next_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 10.375, 13.25 },
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.UnexpectedPatchSetResponse;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    var graph_sequence: i32 = 100;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.put,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const put_mode: i32 = 21;
    try patch.append(
        patch_ids.body,
        patch_ids.int,
        std.mem.asBytes(&put_mode),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        21,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.accept,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.put),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const graph_get_response = try readPatchGraphPutResponse(
        &event_output,
        patch_ids,
    );
    if (graph_get_response.frame_offset != 0 or
        graph_get_response.subject != patch_ids.graph_subject or
        graph_get_response.context != patch_ids.graph_context or
        graph_get_response.sequence_number != graph_sequence or
        graph_get_response.request != null or
        graph_get_response.body_type != patch_ids.int or
        graph_get_response.body.len != @sizeOf(u32) or
        @as(
            *align(1) const i32,
            @ptrCast(graph_get_response.body.ptr),
        ).* != 21)
    {
        return error.InvalidPatchGraphPutResponse;
    }
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.accept,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.put),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const uncorrelated_graph_response = try readPatchGraphPutResponse(
        &event_output,
        patch_ids,
    );
    if (uncorrelated_graph_response.subject !=
        patch_ids.graph_subject or
        uncorrelated_graph_response.context !=
            patch_ids.graph_context or
        uncorrelated_graph_response.sequence_number != null or
        uncorrelated_graph_response.request != null or
        uncorrelated_graph_response.body_type != patch_ids.int or
        uncorrelated_graph_response.body.len != @sizeOf(i32) or
        @as(
            *align(1) const i32,
            @ptrCast(uncorrelated_graph_response.body.ptr),
        ).* != 21)
    {
        return error.InvalidUncorrelatedPatchGraphPutResponse;
    }
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    const blank_request_id: u32 = 73;
    patch.identify(patch_ids.blank, blank_request_id);
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.accept,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.put),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const identified_graph_response = try readPatchGraphPutResponse(
        &event_output,
        patch_ids,
    );
    const graph_request = identified_graph_response.request orelse
        return error.MissingPatchGraphRequestReference;
    if (identified_graph_response.sequence_number != null or
        identified_graph_response.context != patch_ids.graph_context or
        graph_request.atom_type != patch_ids.blank or
        graph_request.id != blank_request_id or
        graph_request.object_type != patch_ids.get)
        return error.InvalidPatchGraphRequestReference;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.accept,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.put),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    const zero_graph_sequence: i32 = 0;
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&zero_graph_sequence),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 24.375, 23.25 },
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.ZeroSequenceProducedPatchGraphPutResponse;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.graph_error,
        21,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.insert,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const insert_mode: i32 = 22;
    try patch.append(
        patch_ids.body,
        patch_ids.int,
        std.mem.asBytes(&insert_mode),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        22,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.patch,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const add_mode: i32 = 23;
    const remove_mode: i32 = 24;
    try patch.append(
        patch_ids.add,
        patch_ids.int,
        std.mem.asBytes(&add_mode),
    );
    try patch.append(
        patch_ids.remove,
        patch_ids.int,
        std.mem.asBytes(&remove_mode),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        23,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.delete,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject_two),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        25,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.copy,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject_two),
    );
    try patch.append(
        patch_ids.destination,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_destination),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        26,
    );

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.move,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.destination,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_destination),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.ack,
        27,
    );

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.insert,
    );
    const graph_mutation_request_id = patch_ids.graph_destination;
    patch.identify(patch_ids.object, graph_mutation_request_id);
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const request_only_mode: i32 = 28;
    try patch.append(
        patch_ids.body,
        patch_ids.int,
        std.mem.asBytes(&request_only_mode),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const identified_graph_ack = try readPatchGraphResponse(
        &event_output,
        patch_ids,
    );
    const mutation_request = identified_graph_ack.request orelse
        return error.MissingPatchGraphMutationRequestReference;
    if (identified_graph_ack.response_type != patch_ids.ack or
        identified_graph_ack.context != patch_ids.graph_context or
        identified_graph_ack.sequence_number != null or
        mutation_request.atom_type != patch_ids.object or
        mutation_request.id != graph_mutation_request_id or
        mutation_request.object_type != patch_ids.insert)
        return error.InvalidPatchGraphMutationRequestReference;
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 31.375, 30.25 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.insert,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const uncorrelated_mode: i32 = 28;
    try patch.append(
        patch_ids.body,
        patch_ids.int,
        std.mem.asBytes(&uncorrelated_mode),
    );
    const zero_sequence: i32 = 0;
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&zero_sequence),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 31.375, 30.25 },
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.ZeroSequenceProducedPatchGraphResponse;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    graph_sequence += 1;
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.put,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    const invalid_mode: i32 = -1;
    try patch.append(
        patch_ids.body,
        patch_ids.int,
        std.mem.asBytes(&invalid_mode),
    );
    try patch.append(
        patch_ids.context,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_context),
    );
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&graph_sequence),
    );
    try runPatchGraphRequest(
        descriptor,
        handle,
        end_run,
        &output,
        &event_output,
        patch_ids,
        graph_sequence,
        patch_ids.graph_error,
        28,
    );

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.put,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    try patch.append(
        patch_ids.body,
        0,
        std.mem.asBytes(&put_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.ZeroTypePatchGraphProducedOutput;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.put,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.graph_subject),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.MalformedPatchGraphProducedOutput;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.plugin),
    );
    try patch.append(
        patch_ids.value,
        patch_ids.int,
        std.mem.asBytes(&next_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.plugin),
    );
    const sequence_number: i32 = 37;
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&sequence_number),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const mode_response = try readPatchResponse(
        &event_output,
        patch_ids,
    );
    if (mode_response.frame_offset != 0 or
        mode_response.property != patch_ids.mode or
        mode_response.sequence_number != sequence_number or
        mode_response.subject != patch_ids.plugin or
        mode_response.value_type != patch_ids.int or
        mode_response.value.len != @sizeOf(i32) or
        @as(
            *align(1) const i32,
            @ptrCast(mode_response.value.ptr),
        ).* != next_mode)
        return error.InvalidModePatchResponse;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.resource),
    );
    try patch.appendString(
        patch_ids.value,
        patch_ids.path,
        "/restored/original.wav",
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    const named_request_id = patch_ids.graph_destination;
    patch.identify(patch_ids.object, named_request_id);
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.resource),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const path_response = try readPatchResponse(
        &event_output,
        patch_ids,
    );
    if (path_response.property != patch_ids.resource or
        path_response.sequence_number != null or
        path_response.request == null or
        path_response.value_type != patch_ids.path or
        path_response.value.len == 0 or
        path_response.value[path_response.value.len - 1] != 0 or
        !std.mem.eql(
            u8,
            path_response.value[0 .. path_response.value.len - 1],
            "/restored/original.wav",
        ))
        return error.InvalidPathPatchResponse;
    const path_request = path_response.request orelse
        return error.MissingPathPatchRequestReference;
    if (path_request.atom_type != patch_ids.object or
        path_request.id != named_request_id or
        path_request.object_type != patch_ids.get)
        return error.InvalidPathPatchRequestReference;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.MalformedPatchProducedOutput;

    const foreign_property = StateHost.map(
        null,
        "https://example.test/foreign-property",
    );
    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.subject,
        patch_ids.urid,
        std.mem.asBytes(&foreign_property),
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    const ignored_mode: i32 = 99;
    try patch.append(
        patch_ids.value,
        patch_ids.int,
        std.mem.asBytes(&ignored_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 14.375, 13.25 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&foreign_property),
    );
    try patch.append(
        patch_ids.value,
        patch_ids.int,
        std.mem.asBytes(&ignored_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 14.375, 13.25 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.appendString(
        patch_ids.value,
        patch_ids.path,
        "/wrong/type",
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.set,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    try patch.append(
        patch_ids.value,
        patch_ids.int,
        std.mem.asBytes(&ignored_mode),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    const no_response: i32 = 0;
    try patch.append(
        patch_ids.sequence_number,
        patch_ids.int,
        std.mem.asBytes(&no_response),
    );
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.ZeroSequenceProducedPatchResponse;
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 14.375, 13.25 },
        &output,
    );
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    patch = PatchBuilder.init(
        &event_input,
        patch_ids,
        0,
        patch_ids.get,
    );
    try patch.append(
        patch_ids.property,
        patch_ids.urid,
        std.mem.asBytes(&patch_ids.mode),
    );
    event_output.resetOutput(patch_ids);
    event_output.sequence.atom.size =
        @sizeOf(core.lv2.AtomSequenceBody) + 24;
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.0} ** input.len),
        &output,
    );
    if (event_output.sequence.atom.size !=
        @sizeOf(core.lv2.AtomSequenceBody))
        return error.SmallPatchOutputWasNotCleared;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    const retained_response = try readPatchResponse(
        &event_output,
        patch_ids,
    );
    if (retained_response.value_type != patch_ids.int or
        retained_response.value.len != @sizeOf(i32) or
        @as(
            *align(1) const i32,
            @ptrCast(retained_response.value.ptr),
        ).* != next_mode)
        return error.FailedPatchRunsMutatedState;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;

    event_input = PatchSequence.empty(patch_ids);
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    if (state.save(
        handle,
        null,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .unknown) return error.NullStateStoreCallbackAccepted;
    if (state.restore(
        handle,
        null,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .unknown) return error.NullStateRetrieveCallbackAccepted;
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

    state_map_path.abstract_path = null;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .no_feature) return error.NullAbstractPathCallbackAccepted;
    state_map_path.abstract_path = StateHost.abstractPath;
    state_map_path.absolute_path = null;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .no_feature) return error.NullAbsolutePathCallbackAccepted;
    state_map_path.absolute_path = StateHost.absolutePath;
    state_make_path.path = null;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .no_feature) return error.NullMakePathCallbackAccepted;
    state_make_path.path = StateHost.makePath;
    state_free_path.free_path = null;
    if (state.save(
        handle,
        StateHost.store,
        &state_host,
        0,
        state_features[0..].ptr,
    ) != .no_feature) return error.NullFreePathCallbackAccepted;
    state_free_path.free_path = StateHost.freePath;

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
    event_output.resetOutput(patch_ids);
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

    var thread_safe_saved = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &thread_safe_saved,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    gain = 0.25;
    if (descriptor.activate) |activate| activate(handle);
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    var before_thread_safe_restore = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &before_thread_safe_restore,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (std.mem.eql(
        u8,
        thread_safe_saved.parameter_bytes[0..thread_safe_saved.parameter_size],
        before_thread_safe_restore.parameter_bytes[0..before_thread_safe_restore.parameter_size],
    )) return error.ThreadSafeRestoreFixtureDidNotMutateState;

    worker_host.respond_entered.store(false, .release);
    worker_host.allow_response.store(false, .release);
    worker_host.work_finished.store(false, .release);
    worker_host.work_status = .unknown;
    state_host.fail_path_mapping = true;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &thread_safe_saved,
        0,
        thread_safe_state_features[0..].ptr,
    ) != .bad_type) return error.ThreadSafePathFailureAccepted;
    if (worker_host.request_pending)
        return error.FailedThreadSafeRestoreWasScheduled;
    state_host.fail_path_mapping = false;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &thread_safe_saved,
        0,
        thread_safe_state_features[0..].ptr,
    ) != .success) return error.ThreadSafeStateRestoreWasNotScheduled;
    if (!worker_host.request_pending or worker_host.request_size != 0)
        return error.ThreadSafeStateRestoreRequestMismatch;
    if (state.restore(
        handle,
        StateHost.retrieve,
        &thread_safe_saved,
        0,
        thread_safe_state_features[0..].ptr,
    ) != .no_space) return error.ConcurrentThreadSafeRestoreAccepted;
    var staged_but_unapplied = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &staged_but_unapplied,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        before_thread_safe_restore.parameter_bytes[0..before_thread_safe_restore.parameter_size],
        staged_but_unapplied.parameter_bytes[0..staged_but_unapplied.parameter_size],
    )) return error.ThreadSafeRestoreAppliedBeforeWorkerResponse;

    var restore_worker_thread = try std.Thread.spawn(
        .{},
        WorkerHost.runWork,
        .{&worker_host},
    );
    var restore_worker_joined = false;
    defer if (!restore_worker_joined) {
        worker_host.allow_response.store(true, .release);
        restore_worker_thread.join();
    };
    if (!worker_host.waitForResponse()) {
        restore_worker_thread.join();
        restore_worker_joined = true;
        return error.ThreadSafeRestoreWorkerDidNotRespond;
    }
    event_output.resetOutput(patch_ids);
    descriptor.run(handle, input.len);
    worker_host.allow_response.store(true, .release);
    restore_worker_thread.join();
    restore_worker_joined = true;
    if (worker_host.work_status != .success or
        !worker_host.response_pending or
        worker_host.response_size != 0)
        return error.ThreadSafeRestoreWorkerFailed;
    if (worker_host.deliverResponse() != .success)
        return error.ThreadSafeRestoreResponseFailed;
    if (end_run(handle) != .success)
        return error.WorkerEndRunFailed;
    if (descriptor.deactivate) |deactivate| deactivate(handle);
    var after_thread_safe_restore = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &after_thread_safe_restore,
        0,
        state_features[0..].ptr,
    ) != .success) return error.StateSaveFailed;
    if (!std.mem.eql(
        u8,
        thread_safe_saved.parameter_bytes[0..thread_safe_saved.parameter_size],
        after_thread_safe_restore.parameter_bytes[0..after_thread_safe_restore.parameter_size],
    ) or !std.mem.eql(
        u8,
        thread_safe_saved.component_bytes[0..thread_safe_saved.component_size],
        after_thread_safe_restore.component_bytes[0..after_thread_safe_restore.component_size],
    )) return error.ThreadSafeRestoreRoundTripMismatch;

    gain = 0.25;
    if (descriptor.activate) |activate| activate(handle);
    event_output.resetOutput(patch_ids);
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
