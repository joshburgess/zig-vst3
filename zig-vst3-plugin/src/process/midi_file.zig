const std = @import("std");
const midi1 = @import("midi1.zig");

pub const Format = enum(u16) {
    single_track = 0,
    simultaneous_tracks = 1,
    independent_tracks = 2,
};

pub const SmpteRate = enum {
    fps_24,
    fps_25,
    fps_29_97_drop,
    fps_30,
};

pub const SmpteDivision = struct {
    rate: SmpteRate,
    ticks_per_frame: u8,
};

pub const Division = union(enum) {
    ticks_per_quarter_note: u16,
    smpte: SmpteDivision,

    pub fn decode(raw: u16) !Division {
        if ((raw & 0x8000) == 0) {
            if (raw == 0) return error.InvalidMidiDivision;
            return .{ .ticks_per_quarter_note = raw };
        }

        const encoded_rate: i8 = @bitCast(@as(u8, @truncate(raw >> 8)));
        const rate: SmpteRate = switch (encoded_rate) {
            -24 => .fps_24,
            -25 => .fps_25,
            -29 => .fps_29_97_drop,
            -30 => .fps_30,
            else => return error.InvalidMidiDivision,
        };
        const ticks_per_frame: u8 = @truncate(raw);
        if (ticks_per_frame == 0) return error.InvalidMidiDivision;
        return .{ .smpte = .{
            .rate = rate,
            .ticks_per_frame = ticks_per_frame,
        } };
    }

    pub fn encode(self: Division) u16 {
        return switch (self) {
            .ticks_per_quarter_note => |ticks| ticks,
            .smpte => |division| blk: {
                const encoded_rate: i8 = switch (division.rate) {
                    .fps_24 => -24,
                    .fps_25 => -25,
                    .fps_29_97_drop => -29,
                    .fps_30 => -30,
                };
                const rate_byte: u8 = @bitCast(encoded_rate);
                break :blk (@as(u16, rate_byte) << 8) | division.ticks_per_frame;
            },
        };
    }

    pub fn validate(self: Division) !void {
        switch (self) {
            .ticks_per_quarter_note => |ticks| {
                if (ticks == 0 or ticks > 0x7FFF) return error.InvalidMidiDivision;
            },
            .smpte => |division| {
                if (division.ticks_per_frame == 0) return error.InvalidMidiDivision;
            },
        }
    }
};

pub const TimeSignature = struct {
    numerator: u8,
    denominator: u32,
    midi_clocks_per_metronome_click: u8,
    thirty_seconds_per_quarter_note: u8,
};

pub const MetaEvent = struct {
    kind: u8,
    data: []const u8,

    pub fn isEndOfTrack(self: MetaEvent) bool {
        return self.kind == 0x2F and self.data.len == 0;
    }

    pub fn tempoMicrosecondsPerQuarterNote(self: MetaEvent) ?u32 {
        if (self.kind != 0x51 or self.data.len != 3) return null;
        return (@as(u32, self.data[0]) << 16) |
            (@as(u32, self.data[1]) << 8) |
            self.data[2];
    }

    pub fn timeSignature(self: MetaEvent) ?TimeSignature {
        if (self.kind != 0x58 or self.data.len != 4 or self.data[1] >= 32) return null;
        return .{
            .numerator = self.data[0],
            .denominator = @as(u32, 1) << @intCast(self.data[1]),
            .midi_clocks_per_metronome_click = self.data[2],
            .thirty_seconds_per_quarter_note = self.data[3],
        };
    }

    pub fn trackName(self: MetaEvent) ?[]const u8 {
        if (self.kind != 0x03) return null;
        return self.data;
    }
};

pub const SysExEvent = struct {
    status: u8,
    data: []const u8,
};

pub const EventPayload = union(enum) {
    message: midi1.Message,
    meta: MetaEvent,
    sysex: SysExEvent,
};

pub const Event = struct {
    delta_ticks: u32,
    absolute_ticks: u64,
    payload: EventPayload,
};

pub const TrackIterator = struct {
    bytes: []const u8,
    position: usize = 0,
    absolute_ticks: u64 = 0,
    running_status: ?u8 = null,
    ended: bool = false,

    pub fn validate(self: *const TrackIterator) !void {
        if (self.position > self.bytes.len)
            return error.InvalidMidiTrackIteratorState;
        var canonical = TrackIterator{ .bytes = self.bytes };
        while (true) {
            if (trackStatesEqual(self.*, canonical)) return;
            if (canonical.position >= self.position)
                return error.InvalidMidiTrackIteratorState;
            _ = (try canonical.nextInPlace()) orelse
                return error.InvalidMidiTrackIteratorState;
        }
    }

    pub fn valid(self: *const TrackIterator) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn next(self: *TrackIterator) !?Event {
        try self.validate();
        var staged = self.*;
        const result = try staged.nextInPlace();
        self.* = staged;
        return result;
    }

    fn nextInPlace(self: *TrackIterator) !?Event {
        if (self.ended) {
            if (self.position != self.bytes.len) return error.EventAfterEndOfTrack;
            return null;
        }
        if (self.position == self.bytes.len) return null;

        const delta_ticks = try readVariableLength(self.bytes, &self.position);
        self.absolute_ticks = std.math.add(u64, self.absolute_ticks, delta_ticks) catch
            return error.MidiTickOverflow;
        if (self.position >= self.bytes.len) return error.TruncatedMidiEvent;

        const first = self.bytes[self.position];
        const payload = if (first == 0xFF)
            try self.readMetaEvent()
        else if (first == 0xF0 or first == 0xF7)
            try self.readSysExEvent()
        else
            try self.readChannelMessage();

        if (payload == .meta and payload.meta.isEndOfTrack()) {
            self.ended = true;
        }
        return .{
            .delta_ticks = delta_ticks,
            .absolute_ticks = self.absolute_ticks,
            .payload = payload,
        };
    }

    fn readMetaEvent(self: *TrackIterator) !EventPayload {
        self.running_status = null;
        self.position += 1;
        if (self.position >= self.bytes.len) return error.TruncatedMidiEvent;
        const kind = self.bytes[self.position];
        self.position += 1;
        const length = try readVariableLength(self.bytes, &self.position);
        const data = try takeBytes(self.bytes, &self.position, length);
        try validateMetaEvent(kind, data);
        return .{ .meta = .{ .kind = kind, .data = data } };
    }

    fn readSysExEvent(self: *TrackIterator) !EventPayload {
        self.running_status = null;
        const status = self.bytes[self.position];
        self.position += 1;
        const length = try readVariableLength(self.bytes, &self.position);
        const data = try takeBytes(self.bytes, &self.position, length);
        return .{ .sysex = .{ .status = status, .data = data } };
    }

    fn readChannelMessage(self: *TrackIterator) !EventPayload {
        const first = self.bytes[self.position];
        const status = if ((first & 0x80) != 0) status: {
            if (first < 0x80 or first > 0xEF) return error.UnsupportedMidiFileStatus;
            self.position += 1;
            self.running_status = first;
            break :status first;
        } else self.running_status orelse return error.MissingRunningStatus;

        const length = messageLength(status);
        var storage = [_]u8{ status, 0, 0 };
        const data_length = length - 1;
        const data = try takeBytes(self.bytes, &self.position, @intCast(data_length));
        for (data, 0..) |byte, index| {
            if (byte > 0x7F) return error.InvalidMidiDataByte;
            storage[index + 1] = byte;
        }
        return .{ .message = try midi1.Message.parse(storage[0..length]) };
    }
};

fn trackStatesEqual(left: TrackIterator, right: TrackIterator) bool {
    return left.position == right.position and
        left.absolute_ticks == right.absolute_ticks and
        left.running_status == right.running_status and
        left.ended == right.ended;
}

pub const Track = struct {
    bytes: []const u8,

    pub fn iterator(self: Track) TrackIterator {
        return .{ .bytes = self.bytes };
    }

    pub fn validate(self: Track) !void {
        var events = self.iterator();
        var saw_end = false;
        while (try events.next()) |event| {
            if (event.payload == .meta and event.payload.meta.isEndOfTrack()) {
                saw_end = true;
                if (events.position != self.bytes.len) return error.EventAfterEndOfTrack;
            }
        }
        if (!saw_end) return error.MissingEndOfTrack;
    }
};

pub const File = struct {
    bytes: []const u8,
    format: Format,
    track_count: u16,
    division: Division,

    pub fn parse(bytes: []const u8) !File {
        if (bytes.len < 14) return error.TruncatedMidiFile;
        if (!std.mem.eql(u8, bytes[0..4], "MThd")) return error.MissingMidiHeader;
        if (readU32(bytes[4..8]) != 6) return error.InvalidMidiHeaderLength;

        const format: Format = switch (readU16(bytes[8..10])) {
            0 => .single_track,
            1 => .simultaneous_tracks,
            2 => .independent_tracks,
            else => return error.UnsupportedMidiFileFormat,
        };
        const track_count = readU16(bytes[10..12]);
        if (track_count == 0) return error.InvalidMidiTrackCount;
        if (format == .single_track and track_count != 1) return error.InvalidMidiTrackCount;
        const division = try Division.decode(readU16(bytes[12..14]));

        var position: usize = 14;
        for (0..track_count) |_| {
            const track_value = try readTrack(bytes, &position);
            try track_value.validate();
        }
        if (position != bytes.len) return error.TrailingMidiFileData;

        return .{
            .bytes = bytes,
            .format = format,
            .track_count = track_count,
            .division = division,
        };
    }

    pub fn validate(self: File) !void {
        try self.division.validate();
        const parsed = File.parse(self.bytes) catch
            return error.InvalidMidiFileState;
        if (parsed.format != self.format or
            parsed.track_count != self.track_count or
            !std.meta.eql(parsed.division, self.division))
        {
            return error.InvalidMidiFileState;
        }
    }

    pub fn valid(self: File) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn track(self: File, index: usize) ?Track {
        if (index >= self.track_count) return null;
        var position: usize = 14;
        for (0..self.track_count) |track_index| {
            const track_value = readTrack(self.bytes, &position) catch return null;
            if (track_index == index) return track_value;
        }
        return null;
    }

    pub fn secondsAtTick(self: File, track_index: usize, tick: u64) !f64 {
        if (track_index >= self.track_count) return error.InvalidMidiTrackIndex;
        try self.validate();
        return switch (self.division) {
            .smpte => |division| smpteSecondsAtTick(division, tick),
            .ticks_per_quarter_note => |ticks_per_quarter_note| blk: {
                const tempo_track_index: usize = switch (self.format) {
                    .single_track, .simultaneous_tracks => 0,
                    .independent_tracks => track_index,
                };
                const tempo_track = self.track(tempo_track_index) orelse
                    return error.InvalidMidiFileState;
                var iterator = tempo_track.iterator();
                var segment_start_tick: u64 = 0;
                var tempo_microseconds: u32 = 500_000;
                var seconds: f64 = 0.0;
                while (try iterator.next()) |event| {
                    if (event.absolute_ticks > tick) break;
                    const tempo = switch (event.payload) {
                        .meta => |meta| meta.tempoMicrosecondsPerQuarterNote() orelse continue,
                        else => continue,
                    };
                    seconds += metricTickDuration(
                        event.absolute_ticks - segment_start_tick,
                        ticks_per_quarter_note,
                        tempo_microseconds,
                    );
                    segment_start_tick = event.absolute_ticks;
                    tempo_microseconds = tempo;
                }
                seconds += metricTickDuration(
                    tick - segment_start_tick,
                    ticks_per_quarter_note,
                    tempo_microseconds,
                );
                break :blk seconds;
            },
        };
    }
};

pub const Writer = struct {
    buffer: []u8,
    position: usize,
    expected_track_count: u16,
    completed_track_count: u16 = 0,
    active_track_header: ?usize = null,

    pub fn init(buffer: []u8, format: Format, track_count: u16, division: Division) !Writer {
        if (track_count == 0) return error.InvalidMidiTrackCount;
        if (format == .single_track and track_count != 1) return error.InvalidMidiTrackCount;
        try division.validate();
        if (buffer.len < 14) return error.MidiFileBufferTooSmall;

        @memcpy(buffer[0..4], "MThd");
        std.mem.writeInt(u32, buffer[4..8], 6, .big);
        std.mem.writeInt(u16, buffer[8..10], @intFromEnum(format), .big);
        std.mem.writeInt(u16, buffer[10..12], track_count, .big);
        std.mem.writeInt(u16, buffer[12..14], division.encode(), .big);
        return .{
            .buffer = buffer,
            .position = 14,
            .expected_track_count = track_count,
        };
    }

    pub fn beginTrack(self: *Writer) !void {
        if (self.active_track_header != null) return error.MidiTrackAlreadyActive;
        if (self.completed_track_count >= self.expected_track_count) return error.TooManyMidiTracks;
        try self.requireCapacity(8);

        const header = self.position;
        @memcpy(self.buffer[header..][0..4], "MTrk");
        @memset(self.buffer[header + 4 ..][0..4], 0);
        self.position += 8;
        self.active_track_header = header;
    }

    pub fn writeMessage(self: *Writer, delta_ticks: u32, message: midi1.Message) !void {
        _ = try self.checkedActiveTrackHeader();
        if (!message.valid()) return error.InvalidMidiMessage;
        var delta_storage: [4]u8 = undefined;
        const delta = try encodeVariableLength(delta_ticks, &delta_storage);
        const bytes = message.bytes();
        try self.requireCapacity(delta.len + bytes.len);
        self.append(delta);
        self.append(bytes);
    }

    pub fn writeMeta(self: *Writer, delta_ticks: u32, kind: u8, data: []const u8) !void {
        _ = try self.checkedActiveTrackHeader();
        if (kind == 0x2F) return error.UseEndMidiTrack;
        try validateMetaEvent(kind, data);
        const data_length = std.math.cast(u32, data.len) orelse return error.MidiEventTooLarge;
        var delta_storage: [4]u8 = undefined;
        var length_storage: [4]u8 = undefined;
        const delta = try encodeVariableLength(delta_ticks, &delta_storage);
        const length = try encodeVariableLength(data_length, &length_storage);
        const required = std.math.add(usize, delta.len + 2 + length.len, data.len) catch
            return error.MidiEventTooLarge;
        try self.requireCapacity(required);
        self.append(delta);
        self.append(&.{ 0xFF, kind });
        self.append(length);
        self.append(data);
    }

    pub fn writeSysEx(self: *Writer, delta_ticks: u32, status: u8, data: []const u8) !void {
        _ = try self.checkedActiveTrackHeader();
        if (status != 0xF0 and status != 0xF7) return error.InvalidMidiSysExStatus;
        const data_length = std.math.cast(u32, data.len) orelse return error.MidiEventTooLarge;
        var delta_storage: [4]u8 = undefined;
        var length_storage: [4]u8 = undefined;
        const delta = try encodeVariableLength(delta_ticks, &delta_storage);
        const length = try encodeVariableLength(data_length, &length_storage);
        const required = std.math.add(usize, delta.len + 1 + length.len, data.len) catch
            return error.MidiEventTooLarge;
        try self.requireCapacity(required);
        self.append(delta);
        self.append(&.{status});
        self.append(length);
        self.append(data);
    }

    pub fn endTrack(self: *Writer, delta_ticks: u32) !void {
        const header = try self.checkedActiveTrackHeader();
        var delta_storage: [4]u8 = undefined;
        const delta = try encodeVariableLength(delta_ticks, &delta_storage);
        try self.requireCapacity(delta.len + 3);
        const final_position = std.math.add(usize, self.position, delta.len + 3) catch
            return error.MidiTrackTooLarge;
        const track_length = final_position - (header + 8);
        const encoded_track_length = std.math.cast(u32, track_length) orelse
            return error.MidiTrackTooLarge;

        self.append(delta);
        self.append(&.{ 0xFF, 0x2F, 0 });
        std.mem.writeInt(u32, self.buffer[header + 4 ..][0..4], encoded_track_length, .big);
        self.active_track_header = null;
        self.completed_track_count += 1;
    }

    pub fn finish(self: *const Writer) ![]const u8 {
        if (self.active_track_header != null) return error.MidiTrackStillActive;
        if (self.completed_track_count != self.expected_track_count) return error.MissingMidiTracks;
        if (self.position < 14 or self.position > self.buffer.len)
            return error.InvalidMidiWriterState;
        return self.buffer[0..self.position];
    }

    fn requireCapacity(self: *const Writer, additional: usize) !void {
        if (self.position < 14 or self.position > self.buffer.len)
            return error.InvalidMidiWriterState;
        const end = std.math.add(usize, self.position, additional) catch
            return error.MidiFileBufferTooSmall;
        if (end > self.buffer.len) return error.MidiFileBufferTooSmall;
    }

    fn checkedActiveTrackHeader(self: *const Writer) !usize {
        const header = self.active_track_header orelse
            return error.NoActiveMidiTrack;
        if (self.position < 14 or self.position > self.buffer.len)
            return error.InvalidMidiWriterState;
        const payload_start = std.math.add(usize, header, 8) catch
            return error.InvalidMidiWriterState;
        if (payload_start > self.position or payload_start > self.buffer.len)
            return error.InvalidMidiWriterState;
        if (!std.mem.eql(u8, self.buffer[header..][0..4], "MTrk"))
            return error.InvalidMidiWriterState;
        return header;
    }

    fn append(self: *Writer, bytes: []const u8) void {
        std.mem.copyForwards(u8, self.buffer[self.position..][0..bytes.len], bytes);
        self.position += bytes.len;
    }
};

fn readTrack(bytes: []const u8, position: *usize) !Track {
    const header = try takeBytes(bytes, position, 8);
    if (!std.mem.eql(u8, header[0..4], "MTrk")) return error.MissingMidiTrack;
    const length = readU32(header[4..8]);
    return .{ .bytes = try takeBytes(bytes, position, length) };
}

fn readVariableLength(bytes: []const u8, position: *usize) !u32 {
    var value: u32 = 0;
    for (0..4) |_| {
        if (position.* >= bytes.len) return error.TruncatedVariableLengthQuantity;
        const byte = bytes[position.*];
        position.* += 1;
        value = (value << 7) | (byte & 0x7F);
        if ((byte & 0x80) == 0) return value;
    }
    return error.InvalidVariableLengthQuantity;
}

fn encodeVariableLength(value: u32, storage: *[4]u8) ![]const u8 {
    if (value > 0x0FFF_FFFF) return error.InvalidVariableLengthQuantity;
    var encoded = value;
    var index: usize = storage.len;
    index -= 1;
    storage[index] = @truncate(encoded & 0x7F);
    encoded >>= 7;
    while (encoded != 0) {
        index -= 1;
        storage[index] = @as(u8, @truncate(encoded & 0x7F)) | 0x80;
        encoded >>= 7;
    }
    return storage[index..];
}

fn takeBytes(bytes: []const u8, position: *usize, length: u32) ![]const u8 {
    const count: usize = length;
    const end = std.math.add(usize, position.*, count) catch return error.TruncatedMidiFile;
    if (end > bytes.len) return error.TruncatedMidiFile;
    const result = bytes[position.*..end];
    position.* = end;
    return result;
}

fn messageLength(status: u8) usize {
    return switch (status & 0xF0) {
        0xC0, 0xD0 => 2,
        else => 3,
    };
}

fn validateMetaEvent(kind: u8, data: []const u8) !void {
    const expected: ?usize = switch (kind) {
        0x00 => 2,
        0x20, 0x21 => 1,
        0x2F => 0,
        0x51 => 3,
        0x54 => 5,
        0x58 => 4,
        0x59 => 2,
        else => null,
    };
    if (expected) |value| {
        if (data.len != value) return error.InvalidMidiMetaEventLength;
    }
    if (kind == 0x51 and data[0] == 0 and data[1] == 0 and data[2] == 0) {
        return error.InvalidMidiTempo;
    }
}

fn metricTickDuration(ticks: u64, ticks_per_quarter_note: u16, tempo_microseconds: u32) f64 {
    return @as(f64, @floatFromInt(ticks)) *
        @as(f64, @floatFromInt(tempo_microseconds)) /
        (1_000_000.0 * @as(f64, @floatFromInt(ticks_per_quarter_note)));
}

fn smpteSecondsAtTick(division: SmpteDivision, tick: u64) f64 {
    const frames_per_second: f64 = switch (division.rate) {
        .fps_24 => 24.0,
        .fps_25 => 25.0,
        .fps_29_97_drop => 30_000.0 / 1_001.0,
        .fps_30 => 30.0,
    };
    return @as(f64, @floatFromInt(tick)) /
        (frames_per_second * @as(f64, @floatFromInt(division.ticks_per_frame)));
}

fn readU16(bytes: *const [2]u8) u16 {
    return std.mem.readInt(u16, bytes, .big);
}

fn readU32(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .big);
}

test "MIDI file parser reads channel, running-status, tempo, signature, and SysEx events" {
    const bytes = [_]u8{
        'M',  'T',  'h',  'd',  0,    0,    0,    6,
        0,    1,    0,    1,    0x01, 0xE0, 'M',  'T',
        'r',  'k',  0,    0,    0,    40,   0,    0xFF,
        0x03, 4,    'T',  'e',  's',  't',  0,    0xFF,
        0x51, 3,    0x07, 0xA1, 0x20, 0,    0xFF, 0x58,
        4,    4,    2,    24,   8,    0,    0x90, 60,
        100,  0x60, 64,   80,   0,    0xF0, 3,    0x7D,
        1,    0xF7, 0,    0xFF, 0x2F, 0,
    };
    const file = try File.parse(&bytes);

    try std.testing.expectEqual(Format.simultaneous_tracks, file.format);
    try std.testing.expectEqual(@as(u16, 1), file.track_count);
    try std.testing.expectEqual(@as(u16, 480), file.division.ticks_per_quarter_note);

    var iterator = file.track(0).?.iterator();
    const name = (try iterator.next()).?;
    try std.testing.expectEqualSlices(u8, "Test", name.payload.meta.trackName().?);
    const tempo = (try iterator.next()).?;
    try std.testing.expectEqual(@as(?u32, 500_000), tempo.payload.meta.tempoMicrosecondsPerQuarterNote());
    const signature = (try iterator.next()).?.payload.meta.timeSignature().?;
    try std.testing.expectEqual(@as(u8, 4), signature.numerator);
    try std.testing.expectEqual(@as(u32, 4), signature.denominator);

    const first_note = (try iterator.next()).?;
    try std.testing.expectEqual(@as(?u8, 60), first_note.payload.message.data1());
    const running_note = (try iterator.next()).?;
    try std.testing.expectEqual(@as(u32, 96), running_note.delta_ticks);
    try std.testing.expectEqual(@as(u64, 96), running_note.absolute_ticks);
    try std.testing.expectEqual(@as(?u8, 64), running_note.payload.message.data1());

    const sysex = (try iterator.next()).?.payload.sysex;
    try std.testing.expectEqual(@as(u8, 0xF0), sysex.status);
    try std.testing.expectEqualSlices(u8, &.{ 0x7D, 1, 0xF7 }, sysex.data);
    try std.testing.expect((try iterator.next()).?.payload.meta.isEndOfTrack());
    try std.testing.expect((try iterator.next()) == null);
}

test "MIDI file parser supports format zero and SMPTE division" {
    const bytes = [_]u8{
        'M',  'T', 'h', 'd', 0,    0,  0,   6,
        0,    0,   0,   1,   0xE7, 40, 'M', 'T',
        'r',  'k', 0,   0,   0,    4,  0,   0xFF,
        0x2F, 0,
    };
    const file = try File.parse(&bytes);
    try std.testing.expectEqual(Format.single_track, file.format);
    try std.testing.expectEqual(SmpteRate.fps_25, file.division.smpte.rate);
    try std.testing.expectEqual(@as(u8, 40), file.division.smpte.ticks_per_frame);
    try std.testing.expectEqual(@as(u16, 0xE728), file.division.encode());
}

test "MIDI file parser rejects malformed structure and event streams" {
    const valid = [_]u8{
        'M',  'T', 'h', 'd', 0, 0,  0,   6,
        0,    0,   0,   1,   0, 96, 'M', 'T',
        'r',  'k', 0,   0,   0, 4,  0,   0xFF,
        0x2F, 0,
    };

    try std.testing.expectError(error.TruncatedMidiFile, File.parse(valid[0..13]));

    var bad_magic = valid;
    bad_magic[0] = 'X';
    try std.testing.expectError(error.MissingMidiHeader, File.parse(&bad_magic));

    var bad_track_count = valid;
    bad_track_count[11] = 2;
    try std.testing.expectError(error.InvalidMidiTrackCount, File.parse(&bad_track_count));

    const missing_end = [_]u8{
        'M', 'T', 'h', 'd', 0, 0,  0,   6,
        0,   0,   0,   1,   0, 96, 'M', 'T',
        'r', 'k', 0,   0,   0, 4,  0,   0x90,
        60,  1,
    };
    try std.testing.expectError(error.MissingEndOfTrack, File.parse(&missing_end));

    var trailing_event = [_]u8{
        'M',  'T', 'h', 'd',  0,  0,  0,   6,
        0,    0,   0,   1,    0,  96, 'M', 'T',
        'r',  'k', 0,   0,    0,  8,  0,   0xFF,
        0x2F, 0,   0,   0x90, 60, 1,
    };
    try std.testing.expectError(error.EventAfterEndOfTrack, File.parse(&trailing_event));

    const invalid_vlq = [_]u8{
        'M',  'T',  'h', 'd', 0, 0,  0,    6,
        0,    0,    0,   1,   0, 96, 'M',  'T',
        'r',  'k',  0,   0,   0, 4,  0x81, 0x80,
        0x80, 0x80,
    };
    try std.testing.expectError(error.InvalidVariableLengthQuantity, File.parse(&invalid_vlq));

    var zero_tempo = [_]u8{
        'M',  'T', 'h', 'd', 0,    0,    0,    6,
        0,    0,   0,   1,   0x01, 0xE0, 'M',  'T',
        'r',  'k', 0,   0,   0,    11,   0,    0xFF,
        0x51, 3,   0,   0,   0,    0,    0xFF, 0x2F,
        0,
    };
    try std.testing.expectError(error.InvalidMidiTempo, File.parse(&zero_tempo));
}

test "MIDI file parser rejects every truncated prefix" {
    const valid = [_]u8{
        'M',  'T', 'h', 'd', 0, 0,  0,   6,
        0,    0,   0,   1,   0, 96, 'M', 'T',
        'r',  'k', 0,   0,   0, 4,  0,   0xFF,
        0x2F, 0,
    };

    for (0..valid.len) |prefix_length| {
        if (File.parse(valid[0..prefix_length])) |_| {
            return error.TestExpectedError;
        } else |_| {}
    }
    _ = try File.parse(&valid);
}

test "MIDI file parser contains generated structural mutations" {
    const valid = [_]u8{
        'M',  'T', 'h',  'd',  0,    0,    0,    6,
        0,    0,   0,    1,    0x01, 0xe0, 'M',  'T',
        'r',  'k', 0,    0,    0,    11,   0,    0xff,
        0x51, 3,   0x07, 0xa1, 0x20, 0,    0xff, 0x2f,
        0,
    };
    var rejected: usize = 0;
    var accepted: usize = 0;
    for (0..valid.len) |index| {
        for ([_]u8{ 0x01, 0x55, 0xff }) |mask| {
            var mutated = valid;
            mutated[index] ^= mask;
            const file = File.parse(&mutated) catch {
                rejected += 1;
                continue;
            };
            accepted += 1;
            for (0..file.track_count) |track_index| {
                const track = file.track(track_index) orelse
                    return error.InvalidAcceptedMidiTrack;
                var iterator = track.iterator();
                while (try iterator.next()) |_| {}
            }
            _ = try file.secondsAtTick(0, std.math.maxInt(u64));
        }
    }
    try std.testing.expect(rejected != 0);
    try std.testing.expect(accepted != 0);
}

test "MIDI track iteration preserves state after malformed input" {
    var truncated = (Track{ .bytes = &.{0x81} }).iterator();
    try std.testing.expectError(
        error.TruncatedVariableLengthQuantity,
        truncated.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), truncated.position);
    try std.testing.expectEqual(@as(u64, 0), truncated.absolute_ticks);
    try std.testing.expectEqual(@as(?u8, null), truncated.running_status);
    try std.testing.expect(!truncated.ended);

    var overflowing = (Track{
        .bytes = &.{ 1, 0xff, 0x2f, 0 },
    }).iterator();
    overflowing.absolute_ticks = std.math.maxInt(u64);
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        overflowing.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), overflowing.position);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        overflowing.absolute_ticks,
    );
    try std.testing.expectEqual(@as(?u8, null), overflowing.running_status);
    try std.testing.expect(!overflowing.ended);

    var hostile = (Track{ .bytes = &.{0} }).iterator();
    hostile.position = std.math.maxInt(usize);
    try std.testing.expect(!hostile.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        hostile.next(),
    );
    try std.testing.expectEqual(std.math.maxInt(usize), hostile.position);

    hostile.position = 0;
    hostile.running_status = 0xF0;
    try std.testing.expect(!hostile.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        hostile.next(),
    );
    hostile.running_status = null;
    try hostile.validate();

    const valid_events = [_]u8{
        0,    0x90, 60, 100,
        0,    61,   0,  0,
        0xff, 0x2f, 0,
    };
    var middle = (Track{ .bytes = &valid_events }).iterator();
    middle.position = 1;
    try std.testing.expect(!middle.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        middle.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), middle.position);

    var stale_running = (Track{ .bytes = &valid_events }).iterator();
    _ = try stale_running.next();
    stale_running.running_status = 0x91;
    try std.testing.expect(!stale_running.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        stale_running.next(),
    );
    try std.testing.expectEqual(@as(usize, 4), stale_running.position);
    try std.testing.expectEqual(@as(u64, 0), stale_running.absolute_ticks);
    try std.testing.expectEqual(@as(?u8, 0x91), stale_running.running_status);
}

test "MIDI file writer round trips multiple tracks and event kinds" {
    var storage: [256]u8 = undefined;
    var writer = try Writer.init(
        &storage,
        .simultaneous_tracks,
        2,
        .{ .ticks_per_quarter_note = 480 },
    );

    try writer.beginTrack();
    try writer.writeMeta(0, 0x03, "Conductor");
    try writer.writeMeta(0, 0x51, &.{ 0x07, 0xA1, 0x20 });
    try writer.endTrack(0);

    try writer.beginTrack();
    try writer.writeMessage(0, try midi1.Message.noteOn(0, 60, 100));
    try writer.writeMessage(480, try midi1.Message.noteOff(0, 60, 64));
    try writer.writeSysEx(0, 0xF0, &.{ 0x7D, 0x01, 0xF7 });
    try writer.endTrack(0);

    const encoded = try writer.finish();
    const file = try File.parse(encoded);
    try std.testing.expectEqual(@as(u16, 2), file.track_count);

    var conductor = file.track(0).?.iterator();
    try std.testing.expectEqualSlices(u8, "Conductor", (try conductor.next()).?.payload.meta.trackName().?);
    try std.testing.expectEqual(@as(?u32, 500_000), (try conductor.next()).?.payload.meta.tempoMicrosecondsPerQuarterNote());

    var notes = file.track(1).?.iterator();
    try std.testing.expectEqual(midi1.MessageKind.note_on, (try notes.next()).?.payload.message.kind().?);
    const note_off = (try notes.next()).?;
    try std.testing.expectEqual(@as(u32, 480), note_off.delta_ticks);
    try std.testing.expectEqual(midi1.MessageKind.note_off, note_off.payload.message.kind().?);
    try std.testing.expectEqualSlices(u8, &.{ 0x7D, 0x01, 0xF7 }, (try notes.next()).?.payload.sysex.data);
}

test "MIDI file writer rejects invalid state and preserves bounded writes" {
    var storage: [32]u8 = undefined;
    try std.testing.expectError(error.InvalidMidiTrackCount, Writer.init(
        &storage,
        .single_track,
        2,
        .{ .ticks_per_quarter_note = 96 },
    ));
    try std.testing.expectError(error.InvalidMidiDivision, Writer.init(
        &storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 0 },
    ));

    var writer = try Writer.init(
        &storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    try std.testing.expectError(error.NoActiveMidiTrack, writer.writeMessage(
        0,
        try midi1.Message.noteOn(0, 60, 100),
    ));
    try writer.beginTrack();
    try std.testing.expectError(error.MidiTrackAlreadyActive, writer.beginTrack());
    try std.testing.expectError(error.UseEndMidiTrack, writer.writeMeta(0, 0x2F, &.{}));
    try std.testing.expectError(error.InvalidMidiTempo, writer.writeMeta(0, 0x51, &.{ 0, 0, 0 }));
    try std.testing.expectError(error.InvalidMidiSysExStatus, writer.writeSysEx(0, 0xF1, &.{}));

    const before_position = writer.position;
    try std.testing.expectError(error.MidiFileBufferTooSmall, writer.writeMeta(
        0,
        0x01,
        "this text cannot fit in the remaining fixed buffer",
    ));
    try std.testing.expectEqual(before_position, writer.position);
    try writer.endTrack(0);
    try std.testing.expectError(error.TooManyMidiTracks, writer.beginTrack());
    _ = try writer.finish();
}

test "MIDI file writer contains malformed retained cursors" {
    var position_storage = [_]u8{0} ** 64;
    var invalid_position = try Writer.init(
        &position_storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    invalid_position.position = std.math.maxInt(usize);
    const position_before = position_storage;
    try std.testing.expectError(
        error.InvalidMidiWriterState,
        invalid_position.beginTrack(),
    );
    try std.testing.expectEqualSlices(
        u8,
        &position_before,
        &position_storage,
    );

    var header_storage = [_]u8{0} ** 64;
    var invalid_header = try Writer.init(
        &header_storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    try invalid_header.beginTrack();
    invalid_header.active_track_header = std.math.maxInt(usize);
    const header_before = header_storage;
    const header_position = invalid_header.position;
    try std.testing.expectError(
        error.InvalidMidiWriterState,
        invalid_header.writeMessage(
            0,
            try midi1.Message.noteOn(0, 60, 100),
        ),
    );
    try std.testing.expectEqual(header_position, invalid_header.position);
    try std.testing.expectEqualSlices(
        u8,
        &header_before,
        &header_storage,
    );

    var magic_storage = [_]u8{0} ** 64;
    var invalid_magic = try Writer.init(
        &magic_storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    try invalid_magic.beginTrack();
    magic_storage[14] = 'X';
    const magic_position = invalid_magic.position;
    try std.testing.expectError(
        error.InvalidMidiWriterState,
        invalid_magic.endTrack(0),
    );
    try std.testing.expectEqual(magic_position, invalid_magic.position);

    var finish_storage = [_]u8{0} ** 64;
    var invalid_finish = try Writer.init(
        &finish_storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    try invalid_finish.beginTrack();
    try invalid_finish.endTrack(0);
    invalid_finish.position = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidMidiWriterState,
        invalid_finish.finish(),
    );
}

test "MIDI file converts metric and SMPTE ticks to seconds" {
    var storage: [128]u8 = undefined;
    var writer = try Writer.init(
        &storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 480 },
    );
    try writer.beginTrack();
    try writer.writeMeta(0, 0x51, &.{ 0x07, 0xA1, 0x20 });
    try writer.writeMeta(480, 0x51, &.{ 0x03, 0xD0, 0x90 });
    try writer.endTrack(480);
    const metric = try File.parse(try writer.finish());

    try metric.validate();
    try std.testing.expect(metric.valid());
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), try metric.secondsAtTick(0, 480), 0.000_001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), try metric.secondsAtTick(0, 960), 0.000_001);
    try std.testing.expectError(error.InvalidMidiTrackIndex, metric.secondsAtTick(1, 0));

    var truncated_metric = metric;
    truncated_metric.bytes = truncated_metric.bytes[0..14];
    try std.testing.expectError(
        error.InvalidMidiFileState,
        truncated_metric.secondsAtTick(0, 480),
    );
    try std.testing.expect(!truncated_metric.valid());
    var invalid_track_count = metric;
    invalid_track_count.track_count = 2;
    try std.testing.expectError(
        error.InvalidMidiFileState,
        invalid_track_count.validate(),
    );
    var invalid_division = metric;
    invalid_division.division = .{ .ticks_per_quarter_note = 0 };
    try std.testing.expectError(
        error.InvalidMidiDivision,
        invalid_division.secondsAtTick(0, 480),
    );

    const smpte_bytes = [_]u8{
        'M',  'T', 'h', 'd', 0,    0,  0,   6,
        0,    0,   0,   1,   0xE7, 40, 'M', 'T',
        'r',  'k', 0,   0,   0,    4,  0,   0xFF,
        0x2F, 0,
    };
    const smpte = try File.parse(&smpte_bytes);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), try smpte.secondsAtTick(0, 1_500), 0.000_001);
}
