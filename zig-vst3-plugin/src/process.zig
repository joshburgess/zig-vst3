const std = @import("std");

pub const ParameterChange = struct {
    id: u32,
    sample_offset: usize,
    normalized: f64,

    pub fn isForId(self: ParameterChange, wanted_id: u32) bool {
        return self.id == wanted_id;
    }

    pub fn isAtOffset(self: ParameterChange, wanted_offset: usize) bool {
        return self.sample_offset == wanted_offset;
    }

    pub fn isForIdAtOffset(self: ParameterChange, wanted_id: u32, wanted_offset: usize) bool {
        return self.isForId(wanted_id) and self.isAtOffset(wanted_offset);
    }
};

pub const ParameterSegment = struct {
    start_offset: usize,
    end_offset: usize,
    normalized: f64,

    pub fn frameCount(self: ParameterSegment) usize {
        return self.end_offset - self.start_offset;
    }

    pub fn isEmpty(self: ParameterSegment) bool {
        return self.frameCount() == 0;
    }

    pub fn contains(self: ParameterSegment, sample_offset: usize) bool {
        return sample_offset >= self.start_offset and sample_offset < self.end_offset;
    }

    pub fn startsAt(self: ParameterSegment, sample_offset: usize) bool {
        return self.start_offset == sample_offset;
    }

    pub fn endsAt(self: ParameterSegment, sample_offset: usize) bool {
        return self.end_offset == sample_offset;
    }
};

fn clampNormalized(value: f64) f64 {
    if (std.math.isNan(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

fn isFiniteInRange(comptime T: type, value: T, min: T, max: T) bool {
    return std.math.isFinite(value) and value >= min and value <= max;
}

pub const BlockSegment = struct {
    start_offset: usize,
    end_offset: usize,

    pub fn frameCount(self: BlockSegment) usize {
        return self.end_offset - self.start_offset;
    }

    pub fn isEmpty(self: BlockSegment) bool {
        return self.frameCount() == 0;
    }

    pub fn contains(self: BlockSegment, sample_offset: usize) bool {
        return sample_offset >= self.start_offset and sample_offset < self.end_offset;
    }

    pub fn startsAt(self: BlockSegment, sample_offset: usize) bool {
        return self.start_offset == sample_offset;
    }

    pub fn endsAt(self: BlockSegment, sample_offset: usize) bool {
        return self.end_offset == sample_offset;
    }
};

pub const BlockSegmentIterator = struct {
    changes: ParameterChanges,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *BlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const end = self.changes.nextSampleOffset(start) orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const ProcessBlockSegmentIterator = struct {
    parameter_changes: ParameterChanges,
    events: Events,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *ProcessBlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const next_parameter_offset = self.parameter_changes.nextSampleOffset(start);
        const next_event_offset = self.events.nextSampleOffset(start);
        const end = if (next_parameter_offset) |parameter_offset|
            if (next_event_offset) |event_offset| @min(parameter_offset, event_offset) else parameter_offset
        else
            next_event_offset orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const ParameterSegmentIterator = struct {
    changes: ParameterChanges,
    id: u32,
    frame_count: usize,
    default: f64,
    next_start: usize = 0,

    pub fn next(self: *ParameterSegmentIterator) ?ParameterSegment {
        const segment = self.changes.segmentAt(self.id, self.next_start, self.frame_count, self.default) orelse return null;
        self.next_start = segment.end_offset;
        return segment;
    }
};

pub const ParameterChanges = struct {
    items: []const ParameterChange = &.{},

    pub fn init(items: []const ParameterChange, frame_count: usize) !ParameterChanges {
        for (items) |item| {
            if (item.sample_offset >= frame_count) {
                return error.ParameterChangeOutsideBlock;
            }
            if (!isFiniteInRange(f64, item.normalized, 0.0, 1.0)) {
                return error.ParameterChangeOutsideNormalizedRange;
            }
        }
        return .{ .items = items };
    }

    pub fn changeCount(self: ParameterChanges) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: ParameterChanges) bool {
        return self.items.len == 0;
    }

    pub fn hasChanges(self: ParameterChanges) bool {
        return self.items.len != 0;
    }

    pub fn firstSampleOffset(self: ParameterChanges) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn latestSampleOffset(self: ParameterChanges) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset > result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn firstChange(self: ParameterChanges) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestChange(self: ParameterChanges) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstSampleOffsetForId(self: ParameterChanges, id: u32) ?usize {
        const change = self.first(id) orelse return null;
        return change.sample_offset;
    }

    pub fn latestSampleOffsetForId(self: ParameterChanges, id: u32) ?usize {
        const change = self.latest(id) orelse return null;
        return change.sample_offset;
    }

    pub fn latest(self: ParameterChanges, id: u32) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (!item.isForId(id)) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn first(self: ParameterChanges, id: u32) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (!item.isForId(id)) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstAtOffset(self: ParameterChanges, sample_offset: usize) ?ParameterChange {
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) return item;
        }
        return null;
    }

    pub fn latestAtOffset(self: ParameterChanges, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) result = item;
        }
        return result;
    }

    pub fn firstForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        for (self.items) |item| {
            if (item.isForIdAtOffset(id, sample_offset)) return item;
        }
        return null;
    }

    pub fn latestForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.isForIdAtOffset(id, sample_offset)) result = item;
        }
        return result;
    }

    pub fn count(self: ParameterChanges, id: u32) usize {
        var result: usize = 0;
        for (self.items) |item| {
            if (item.isForId(id)) result += 1;
        }
        return result;
    }

    pub fn countAtOffset(self: ParameterChanges, sample_offset: usize) usize {
        var result: usize = 0;
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) result += 1;
        }
        return result;
    }

    pub fn countForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) usize {
        var result: usize = 0;
        for (self.items) |item| {
            if (item.isForIdAtOffset(id, sample_offset)) result += 1;
        }
        return result;
    }

    pub fn has(self: ParameterChanges, id: u32) bool {
        return self.first(id) != null;
    }

    pub fn hasAtOffset(self: ParameterChanges, sample_offset: usize) bool {
        return self.countAtOffset(sample_offset) != 0;
    }

    pub fn hasForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) bool {
        return self.countForIdAtOffset(id, sample_offset) != 0;
    }

    pub fn empty(self: ParameterChanges, id: u32) bool {
        return !self.has(id);
    }

    pub fn offsetEmpty(self: ParameterChanges, sample_offset: usize) bool {
        return !self.hasAtOffset(sample_offset);
    }

    pub fn idAtOffsetEmpty(self: ParameterChanges, id: u32, sample_offset: usize) bool {
        return !self.hasForIdAtOffset(id, sample_offset);
    }

    pub fn only(self: ParameterChanges, id: u32) bool {
        return self.hasChanges() and self.count(id) == self.items.len;
    }

    pub fn latestNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.latest(id) orelse return null;
        return change.normalized;
    }

    pub fn firstAnyNormalized(self: ParameterChanges) ?f64 {
        const change = self.firstChange() orelse return null;
        return change.normalized;
    }

    pub fn latestAnyNormalized(self: ParameterChanges) ?f64 {
        const change = self.latestChange() orelse return null;
        return change.normalized;
    }

    pub fn firstNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.first(id) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedAtOffset(self: ParameterChanges, sample_offset: usize) ?f64 {
        const change = self.firstAtOffset(sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn latestNormalizedAtOffset(self: ParameterChanges, sample_offset: usize) ?f64 {
        const change = self.latestAtOffset(sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedAtOffsetOr(self: ParameterChanges, sample_offset: usize, default: f64) f64 {
        return self.firstNormalizedAtOffset(sample_offset) orelse clampNormalized(default);
    }

    pub fn latestNormalizedAtOffsetOr(self: ParameterChanges, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedAtOffset(sample_offset) orelse clampNormalized(default);
    }

    pub fn firstNormalizedForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.firstForIdAtOffset(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn latestNormalizedForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.latestForIdAtOffset(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedForIdAtOffsetOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.firstNormalizedForIdAtOffset(id, sample_offset) orelse clampNormalized(default);
    }

    pub fn latestNormalizedForIdAtOffsetOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedForIdAtOffset(id, sample_offset) orelse clampNormalized(default);
    }

    pub fn latestNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.latestNormalized(id) orelse clampNormalized(default);
    }

    pub fn firstNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.firstNormalized(id) orelse clampNormalized(default);
    }

    pub fn latestAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (!item.isForId(id) or item.sample_offset > sample_offset) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestNormalizedAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.latestAtOrBefore(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn normalizedAtOrBeforeOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedAtOrBefore(id, sample_offset) orelse clampNormalized(default);
    }

    pub fn nextSampleOffset(self: ParameterChanges, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn nextSampleOffsetForId(self: ParameterChanges, id: u32, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (!item.isForId(id) or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn segmentAt(self: ParameterChanges, id: u32, start_offset: usize, frame_count: usize, default: f64) ?ParameterSegment {
        if (start_offset >= frame_count) return null;
        const next_offset = self.nextSampleOffsetForId(id, start_offset) orelse frame_count;
        return .{
            .start_offset = start_offset,
            .end_offset = @min(next_offset, frame_count),
            .normalized = self.normalizedAtOrBeforeOr(id, start_offset, default),
        };
    }

    pub fn segments(self: ParameterChanges, id: u32, frame_count: usize, default: f64) ParameterSegmentIterator {
        return .{
            .changes = self,
            .id = id,
            .frame_count = frame_count,
            .default = default,
        };
    }

    pub fn blockSegments(self: ParameterChanges, frame_count: usize) BlockSegmentIterator {
        return .{
            .changes = self,
            .frame_count = frame_count,
        };
    }
};

pub const EventKind = enum {
    note_on,
    note_off,
    midi_cc,
    pitch_bend,
    aftertouch,
    note_expression_value,
    note_expression_int,
    note_expression_text,
    data,
    other,
};

pub const NoteLifecycle = enum {
    none,
    attack,
    release,
};

pub const NoteOn = struct {
    bus_index: i32,
    sample_offset: usize,
    channel: i16,
    pitch: i16,
    velocity: f32,
};

pub const NoteOff = struct {
    bus_index: i32,
    sample_offset: usize,
    channel: i16,
    pitch: i16,
    velocity: f32,
};

pub const MidiCC = struct {
    bus_index: i32,
    sample_offset: usize,
    channel: i16,
    control_number: i16,
    value: f32,
};

pub const PitchBend = struct {
    bus_index: i32,
    sample_offset: usize,
    channel: i16,
    value: f32,
};

pub const Aftertouch = struct {
    bus_index: i32,
    sample_offset: usize,
    channel: i16,
    pitch: i16,
    value: f32,
};

pub const NoteExpressionValue = struct {
    bus_index: i32,
    sample_offset: usize,
    note_id: i32,
    expression_type_id: u32,
    value: f32,
};

pub const NoteExpressionInt = struct {
    bus_index: i32,
    sample_offset: usize,
    note_id: i32,
    expression_type_id: u32,
    value: u64,
};

pub const NoteExpressionText = struct {
    bus_index: i32,
    sample_offset: usize,
    note_id: i32,
    expression_type_id: u32,
};

pub const DataEvent = struct {
    bus_index: i32,
    sample_offset: usize,
    data_type: u32,
    data: []const u8,
};

pub const EventKindIterator = struct {
    events: Events,
    kind: EventKind,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *EventKindIterator) ?Event {
        var result: ?Event = null;
        var result_index: usize = 0;
        for (self.events.items, 0..) |item, index| {
            if (!item.isKind(self.kind)) continue;
            if (self.last_offset) |offset| {
                if (item.sample_offset < offset) continue;
                if (item.sample_offset == offset and index <= self.last_index) continue;
            }
            if (result == null or item.sample_offset < result.?.sample_offset or
                (item.sample_offset == result.?.sample_offset and index < result_index))
            {
                result = item;
                result_index = index;
            }
        }
        if (result) |item| {
            self.last_offset = item.sample_offset;
            self.last_index = result_index;
        }
        return result;
    }
};

pub const EventOffsetIterator = struct {
    events: Events,
    sample_offset: usize,
    next_index: usize = 0,

    pub fn next(self: *EventOffsetIterator) ?Event {
        while (self.next_index < self.events.items.len) : (self.next_index += 1) {
            const item = self.events.items[self.next_index];
            if (item.isAtOffset(self.sample_offset)) {
                self.next_index += 1;
                return item;
            }
        }
        return null;
    }
};

pub const EventBlockSegmentIterator = struct {
    events: Events,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *EventBlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const end = self.events.nextSampleOffset(start) orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const Event = struct {
    kind: EventKind,
    bus_index: i32,
    sample_offset: usize,
    channel: i16 = 0,
    pitch: i16 = 0,
    control_number: i16 = 0,
    note_id: i32 = 0,
    expression_type_id: u32 = 0,
    data_type: u32 = 0,
    data: []const u8 = &.{},
    velocity: f32 = 0,
    value: f32 = 0,
    int_value: u64 = 0,

    pub fn withBusIndex(self: Event, bus_index: i32) Event {
        var event = self;
        event.bus_index = bus_index;
        return event;
    }

    pub fn withSampleOffset(self: Event, sample_offset: usize) Event {
        var event = self;
        event.sample_offset = sample_offset;
        return event;
    }

    pub fn withChannel(self: Event, channel: i16) Event {
        var event = self;
        event.channel = channel;
        return event;
    }

    pub fn withPitch(self: Event, pitch: i16) Event {
        var event = self;
        event.pitch = pitch;
        return event;
    }

    pub fn withControlNumber(self: Event, control_number: i16) Event {
        var event = self;
        event.control_number = control_number;
        return event;
    }

    pub fn withValue(self: Event, value: f32) Event {
        var event = self;
        event.value = value;
        return event;
    }

    pub fn withIntValue(self: Event, int_value: u64) Event {
        var event = self;
        event.int_value = int_value;
        return event;
    }

    pub fn withVelocity(self: Event, velocity: f32) Event {
        var event = self;
        event.velocity = velocity;
        return event;
    }

    pub fn withNoteId(self: Event, note_id: i32) Event {
        var event = self;
        event.note_id = note_id;
        return event;
    }

    pub fn withExpressionTypeId(self: Event, expression_type_id: u32) Event {
        var event = self;
        event.expression_type_id = expression_type_id;
        return event;
    }

    pub fn withDataType(self: Event, data_type: u32) Event {
        var event = self;
        event.data_type = data_type;
        return event;
    }

    pub fn withData(self: Event, data: []const u8) Event {
        var event = self;
        event.data = data;
        return event;
    }

    pub fn isKind(self: Event, kind: EventKind) bool {
        return self.kind == kind;
    }

    pub fn isAtOffset(self: Event, sample_offset: usize) bool {
        return self.sample_offset == sample_offset;
    }

    pub fn isKindAtOffset(self: Event, kind: EventKind, sample_offset: usize) bool {
        return self.isKind(kind) and self.isAtOffset(sample_offset);
    }

    pub fn noteOn(sample_offset: usize, channel: i16, pitch: i16, velocity: f32) Event {
        return .{
            .kind = .note_on,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .velocity = velocity,
        };
    }

    pub fn noteOff(sample_offset: usize, channel: i16, pitch: i16, velocity: f32) Event {
        return .{
            .kind = .note_off,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .velocity = velocity,
        };
    }

    pub fn midiCc(sample_offset: usize, channel: i16, control_number: i16, value: f32) Event {
        return .{
            .kind = .midi_cc,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .control_number = control_number,
            .value = value,
        };
    }

    pub fn pitchBend(sample_offset: usize, channel: i16, value: f32) Event {
        return .{
            .kind = .pitch_bend,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .value = value,
        };
    }

    pub fn aftertouch(sample_offset: usize, channel: i16, pitch: i16, value: f32) Event {
        return .{
            .kind = .aftertouch,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .value = value,
        };
    }

    pub fn noteExpressionValue(sample_offset: usize, note_id: i32, expression_type_id: u32, value: f32) Event {
        return .{
            .kind = .note_expression_value,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
            .value = value,
        };
    }

    pub fn noteExpressionInt(sample_offset: usize, note_id: i32, expression_type_id: u32, value: u64) Event {
        return .{
            .kind = .note_expression_int,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
            .int_value = value,
        };
    }

    pub fn noteExpressionText(sample_offset: usize, note_id: i32, expression_type_id: u32) Event {
        return .{
            .kind = .note_expression_text,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
        };
    }

    pub fn dataEvent(sample_offset: usize, data_type: u32, data: []const u8) Event {
        return .{
            .kind = .data,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .data_type = data_type,
            .data = data,
        };
    }

    pub fn other(sample_offset: usize) Event {
        return .{
            .kind = .other,
            .bus_index = 0,
            .sample_offset = sample_offset,
        };
    }

    pub fn isNoteAttack(self: Event) bool {
        return self.isKind(.note_on) and self.velocity > 0.0;
    }

    pub fn isNoteRelease(self: Event) bool {
        return self.isKind(.note_off) or (self.isKind(.note_on) and self.velocity == 0.0);
    }

    pub fn noteLifecycle(self: Event) NoteLifecycle {
        if (self.isNoteAttack()) return .attack;
        if (self.isNoteRelease()) return .release;
        return .none;
    }

    pub fn isNote(self: Event) bool {
        return self.isKind(.note_on) or self.isKind(.note_off);
    }

    pub fn isMidi(self: Event) bool {
        return self.isKind(.midi_cc) or self.isKind(.pitch_bend) or self.isKind(.aftertouch);
    }

    pub fn isNoteExpression(self: Event) bool {
        return self.isKind(.note_expression_value) or
            self.isKind(.note_expression_int) or
            self.isKind(.note_expression_text);
    }

    pub fn isData(self: Event) bool {
        return self.isKind(.data);
    }

    pub fn isOther(self: Event) bool {
        return self.isKind(.other);
    }

    pub fn hasChannel(self: Event) bool {
        return self.isNote() or self.isMidi();
    }

    pub fn isForChannel(self: Event, channel: i16) bool {
        return self.hasChannel() and self.channel == channel;
    }

    pub fn isForBus(self: Event, bus_index: i32) bool {
        return self.bus_index == bus_index;
    }

    pub fn isForBusChannel(self: Event, bus_index: i32, channel: i16) bool {
        return self.isForBus(bus_index) and self.isForChannel(channel);
    }

    pub fn isNoteForPitch(self: Event, pitch: i16) bool {
        return self.isNote() and self.pitch == pitch;
    }

    pub fn asNoteOn(self: Event) ?NoteOn {
        if (!self.isKind(.note_on)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .channel = self.channel,
            .pitch = self.pitch,
            .velocity = self.velocity,
        };
    }

    pub fn asNoteAttack(self: Event) ?NoteOn {
        const note = self.asNoteOn() orelse return null;
        if (note.velocity <= 0.0) return null;
        return note;
    }

    pub fn asNoteOff(self: Event) ?NoteOff {
        if (!self.isKind(.note_off)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .channel = self.channel,
            .pitch = self.pitch,
            .velocity = self.velocity,
        };
    }

    pub fn asNoteRelease(self: Event) ?NoteOff {
        if (self.asNoteOff()) |note| return note;
        const note = self.asNoteOn() orelse return null;
        if (note.velocity != 0.0) return null;
        return .{
            .bus_index = note.bus_index,
            .sample_offset = note.sample_offset,
            .channel = note.channel,
            .pitch = note.pitch,
            .velocity = 0.0,
        };
    }

    pub fn asMidiCC(self: Event) ?MidiCC {
        if (!self.isKind(.midi_cc)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .channel = self.channel,
            .control_number = self.control_number,
            .value = self.value,
        };
    }

    pub fn asPitchBend(self: Event) ?PitchBend {
        if (!self.isKind(.pitch_bend)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .channel = self.channel,
            .value = self.value,
        };
    }

    pub fn asAftertouch(self: Event) ?Aftertouch {
        if (!self.isKind(.aftertouch)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .channel = self.channel,
            .pitch = self.pitch,
            .value = self.value,
        };
    }

    pub fn asNoteExpressionValue(self: Event) ?NoteExpressionValue {
        if (!self.isKind(.note_expression_value)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .note_id = self.note_id,
            .expression_type_id = self.expression_type_id,
            .value = self.value,
        };
    }

    pub fn asNoteExpressionInt(self: Event) ?NoteExpressionInt {
        if (!self.isKind(.note_expression_int)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .note_id = self.note_id,
            .expression_type_id = self.expression_type_id,
            .value = self.int_value,
        };
    }

    pub fn asNoteExpressionText(self: Event) ?NoteExpressionText {
        if (!self.isKind(.note_expression_text)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .note_id = self.note_id,
            .expression_type_id = self.expression_type_id,
        };
    }

    pub fn asData(self: Event) ?DataEvent {
        if (!self.isKind(.data)) return null;
        return .{
            .bus_index = self.bus_index,
            .sample_offset = self.sample_offset,
            .data_type = self.data_type,
            .data = self.data,
        };
    }

    pub fn validate(self: Event, frame_count: usize) !void {
        if (self.sample_offset >= frame_count) return error.EventOutsideBlock;
        if (self.bus_index < 0) return error.InvalidEventBusIndex;
        switch (self.kind) {
            .note_on, .note_off => {
                try validateMidiChannel(self.channel);
                try validateMidiPitch(self.pitch);
                try validateUnitEventValue(self.velocity);
            },
            .midi_cc => {
                try validateMidiChannel(self.channel);
                try validateMidiControlNumber(self.control_number);
                try validateUnitEventValue(self.value);
            },
            .pitch_bend => {
                try validateMidiChannel(self.channel);
                try validateBipolarEventValue(self.value);
            },
            .aftertouch => {
                try validateMidiChannel(self.channel);
                try validateMidiPitch(self.pitch);
                try validateUnitEventValue(self.value);
            },
            .note_expression_value => try validateUnitEventValue(self.value),
            .note_expression_int, .note_expression_text, .data, .other => {},
        }
    }
};

fn validateMidiChannel(channel: i16) !void {
    if (channel < 0 or channel > 15) return error.InvalidEventChannel;
}

fn validateMidiPitch(pitch: i16) !void {
    if (pitch < 0 or pitch > 127) return error.InvalidEventPitch;
}

fn validateMidiControlNumber(control_number: i16) !void {
    if (control_number < 0 or control_number > 127) return error.InvalidEventControlNumber;
}

fn validateUnitEventValue(value: f32) !void {
    if (!isFiniteInRange(f32, value, 0.0, 1.0)) return error.EventValueOutsideNormalizedRange;
}

fn validateBipolarEventValue(value: f32) !void {
    if (!isFiniteInRange(f32, value, -1.0, 1.0)) return error.EventValueOutsideNormalizedRange;
}

pub const Events = struct {
    items: []const Event = &.{},

    pub fn init(items: []const Event, frame_count: usize) !Events {
        for (items) |item| {
            try item.validate(frame_count);
        }
        return .{ .items = items };
    }

    pub fn eventCount(self: Events) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: Events) bool {
        return self.items.len == 0;
    }

    pub fn hasEvents(self: Events) bool {
        return self.items.len != 0;
    }

    pub fn firstSampleOffset(self: Events) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn latestSampleOffset(self: Events) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset > result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn firstSampleOffsetForKind(self: Events, kind: EventKind) ?usize {
        const event = self.firstKind(kind) orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffsetForKind(self: Events, kind: EventKind) ?usize {
        const event = self.latestKind(kind) orelse return null;
        return event.sample_offset;
    }

    pub fn firstSampleOffsetForBus(self: Events, bus_index: i32) ?usize {
        const event = self.firstBus(bus_index) orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffsetForBus(self: Events, bus_index: i32) ?usize {
        const event = self.latestBus(bus_index) orelse return null;
        return event.sample_offset;
    }

    pub fn firstSampleOffsetForChannel(self: Events, channel: i16) ?usize {
        const event = self.firstChannel(channel) orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffsetForChannel(self: Events, channel: i16) ?usize {
        const event = self.latestChannel(channel) orelse return null;
        return event.sample_offset;
    }

    pub fn firstSampleOffsetForBusChannel(self: Events, bus_index: i32, channel: i16) ?usize {
        const event = self.firstBusChannel(bus_index, channel) orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffsetForBusChannel(self: Events, bus_index: i32, channel: i16) ?usize {
        const event = self.latestBusChannel(bus_index, channel) orelse return null;
        return event.sample_offset;
    }

    pub fn first(self: Events) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latest(self: Events) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstAtOffset(self: Events, sample_offset: usize) ?Event {
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) return item;
        }
        return null;
    }

    pub fn latestAtOffset(self: Events, sample_offset: usize) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) result = item;
        }
        return result;
    }

    pub fn countKind(self: Events, kind: EventKind) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isKind(kind)) count += 1;
        }
        return count;
    }

    pub fn countNoteAttacks(self: Events) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isNoteAttack()) count += 1;
        }
        return count;
    }

    pub fn countNoteReleases(self: Events) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isNoteRelease()) count += 1;
        }
        return count;
    }

    pub fn countAtOffset(self: Events, sample_offset: usize) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isAtOffset(sample_offset)) count += 1;
        }
        return count;
    }

    pub fn countKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isKindAtOffset(kind, sample_offset)) count += 1;
        }
        return count;
    }

    pub fn countBus(self: Events, bus_index: i32) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isForBus(bus_index)) count += 1;
        }
        return count;
    }

    pub fn countChannel(self: Events, channel: i16) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isForChannel(channel)) count += 1;
        }
        return count;
    }

    pub fn countBusChannel(self: Events, bus_index: i32, channel: i16) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.isForBusChannel(bus_index, channel)) count += 1;
        }
        return count;
    }

    pub fn hasBus(self: Events, bus_index: i32) bool {
        for (self.items) |item| {
            if (item.isForBus(bus_index)) return true;
        }
        return false;
    }

    pub fn busEmpty(self: Events, bus_index: i32) bool {
        return !self.hasBus(bus_index);
    }

    pub fn hasChannel(self: Events, channel: i16) bool {
        for (self.items) |item| {
            if (item.isForChannel(channel)) return true;
        }
        return false;
    }

    pub fn channelEmpty(self: Events, channel: i16) bool {
        return !self.hasChannel(channel);
    }

    pub fn hasBusChannel(self: Events, bus_index: i32, channel: i16) bool {
        for (self.items) |item| {
            if (item.isForBusChannel(bus_index, channel)) return true;
        }
        return false;
    }

    pub fn busChannelEmpty(self: Events, bus_index: i32, channel: i16) bool {
        return !self.hasBusChannel(bus_index, channel);
    }

    pub fn firstKind(self: Events, kind: EventKind) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isKind(kind)) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestKind(self: Events, kind: EventKind) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isKind(kind)) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) ?Event {
        for (self.items) |item| {
            if (item.isKindAtOffset(kind, sample_offset)) return item;
        }
        return null;
    }

    pub fn latestKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (item.isKindAtOffset(kind, sample_offset)) result = item;
        }
        return result;
    }

    pub fn firstBus(self: Events, bus_index: i32) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForBus(bus_index)) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestBus(self: Events, bus_index: i32) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForBus(bus_index)) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstChannel(self: Events, channel: i16) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForChannel(channel)) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestChannel(self: Events, channel: i16) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForChannel(channel)) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn firstBusChannel(self: Events, bus_index: i32, channel: i16) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForBusChannel(bus_index, channel)) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestBusChannel(self: Events, bus_index: i32, channel: i16) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (!item.isForBusChannel(bus_index, channel)) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn hasKind(self: Events, kind: EventKind) bool {
        return self.firstKind(kind) != null;
    }

    pub fn hasNoteAttacks(self: Events) bool {
        return self.countNoteAttacks() != 0;
    }

    pub fn hasNoteReleases(self: Events) bool {
        return self.countNoteReleases() != 0;
    }

    pub fn hasAtOffset(self: Events, sample_offset: usize) bool {
        return self.countAtOffset(sample_offset) != 0;
    }

    pub fn hasKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) bool {
        return self.countKindAtOffset(kind, sample_offset) != 0;
    }

    pub fn kindEmpty(self: Events, kind: EventKind) bool {
        return !self.hasKind(kind);
    }

    pub fn noteAttacksEmpty(self: Events) bool {
        return !self.hasNoteAttacks();
    }

    pub fn noteReleasesEmpty(self: Events) bool {
        return !self.hasNoteReleases();
    }

    pub fn offsetEmpty(self: Events, sample_offset: usize) bool {
        return !self.hasAtOffset(sample_offset);
    }

    pub fn kindAtOffsetEmpty(self: Events, kind: EventKind, sample_offset: usize) bool {
        return !self.hasKindAtOffset(kind, sample_offset);
    }

    pub fn onlyAtOffset(self: Events, sample_offset: usize) bool {
        return self.hasEvents() and self.countAtOffset(sample_offset) == self.items.len;
    }

    pub fn onlyKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) bool {
        return self.hasEvents() and self.countKindAtOffset(kind, sample_offset) == self.items.len;
    }

    pub fn onlyKind(self: Events, kind: EventKind) bool {
        return self.hasEvents() and self.countKind(kind) == self.items.len;
    }

    pub fn onlyNoteAttacks(self: Events) bool {
        return self.hasEvents() and self.countNoteAttacks() == self.items.len;
    }

    pub fn onlyNoteReleases(self: Events) bool {
        return self.hasEvents() and self.countNoteReleases() == self.items.len;
    }

    pub fn onlyBus(self: Events, bus_index: i32) bool {
        return self.hasEvents() and self.countBus(bus_index) == self.items.len;
    }

    pub fn onlyChannel(self: Events, channel: i16) bool {
        return self.hasEvents() and self.countChannel(channel) == self.items.len;
    }

    pub fn onlyBusChannel(self: Events, bus_index: i32, channel: i16) bool {
        return self.hasEvents() and self.countBusChannel(bus_index, channel) == self.items.len;
    }

    pub fn nextSampleOffset(self: Events, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn nextSampleOffsetForKind(self: Events, kind: EventKind, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (!item.isKind(kind) or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn nextSampleOffsetForBus(self: Events, bus_index: i32, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (!item.isForBus(bus_index) or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn nextSampleOffsetForChannel(self: Events, channel: i16, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (!item.isForChannel(channel) or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn nextSampleOffsetForBusChannel(self: Events, bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (!item.isForBusChannel(bus_index, channel) or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn ofKind(self: Events, kind: EventKind) EventKindIterator {
        return .{ .events = self, .kind = kind };
    }

    pub fn atOffset(self: Events, sample_offset: usize) EventOffsetIterator {
        return .{ .events = self, .sample_offset = sample_offset };
    }

    pub fn blockSegments(self: Events, frame_count: usize) EventBlockSegmentIterator {
        return .{
            .events = self,
            .frame_count = frame_count,
        };
    }
};

pub const EventWriter = struct {
    storage: []Event,
    count: usize = 0,
    frame_count: usize,

    pub fn init(storage: []Event, frame_count: usize) EventWriter {
        return .{
            .storage = storage,
            .frame_count = frame_count,
        };
    }

    pub fn append(self: *EventWriter, event: Event) !void {
        _ = try self.appendCount(event);
    }

    pub fn appendCount(self: *EventWriter, event: Event) !usize {
        try event.validate(self.frame_count);
        if (self.count >= self.storage.len) return error.EventStorageFull;
        self.storage[self.count] = event;
        self.count += 1;
        return 1;
    }

    pub fn appendAll(self: *EventWriter, source: Events) !void {
        _ = try self.appendAllCount(source);
    }

    pub fn appendAllCount(self: *EventWriter, source: Events) !usize {
        for (source.items) |event| {
            try event.validate(self.frame_count);
        }
        if (source.items.len > self.storage.len - self.count) return error.EventStorageFull;
        for (source.items) |event| {
            self.storage[self.count] = event;
            self.count += 1;
        }
        return source.items.len;
    }

    pub fn canAppend(self: *const EventWriter, event_count: usize) bool {
        return event_count <= self.remainingCapacity();
    }

    pub fn canAppendEvent(self: *const EventWriter, event: Event) bool {
        event.validate(self.frame_count) catch return false;
        return self.canAppend(1);
    }

    pub fn canAppendEvents(self: *const EventWriter, source: Events) bool {
        for (source.items) |event| {
            event.validate(self.frame_count) catch return false;
        }
        return self.canAppend(source.eventCount());
    }

    pub fn clear(self: *EventWriter) void {
        _ = self.clearCount();
    }

    pub fn clearCount(self: *EventWriter) usize {
        const cleared = self.count;
        self.count = 0;
        return cleared;
    }

    pub fn eventCount(self: *const EventWriter) usize {
        return self.count;
    }

    pub fn isEmpty(self: *const EventWriter) bool {
        return self.count == 0;
    }

    pub fn hasEvents(self: *const EventWriter) bool {
        return self.count != 0;
    }

    pub fn isFull(self: *const EventWriter) bool {
        return self.count == self.storage.len;
    }

    pub fn capacity(self: *const EventWriter) usize {
        return self.storage.len;
    }

    pub fn remainingCapacity(self: *const EventWriter) usize {
        return self.storage.len - self.count;
    }

    pub fn frameCount(self: *const EventWriter) usize {
        return self.frame_count;
    }

    pub fn firstSampleOffset(self: *const EventWriter) ?usize {
        return self.events().firstSampleOffset();
    }

    pub fn latestSampleOffset(self: *const EventWriter) ?usize {
        return self.events().latestSampleOffset();
    }

    pub fn first(self: *const EventWriter) ?Event {
        return self.events().first();
    }

    pub fn latest(self: *const EventWriter) ?Event {
        return self.events().latest();
    }

    pub fn firstAtOffset(self: *const EventWriter, sample_offset: usize) ?Event {
        return self.events().firstAtOffset(sample_offset);
    }

    pub fn latestAtOffset(self: *const EventWriter, sample_offset: usize) ?Event {
        return self.events().latestAtOffset(sample_offset);
    }

    pub fn firstSampleOffsetForKind(self: *const EventWriter, kind: EventKind) ?usize {
        return self.events().firstSampleOffsetForKind(kind);
    }

    pub fn latestSampleOffsetForKind(self: *const EventWriter, kind: EventKind) ?usize {
        return self.events().latestSampleOffsetForKind(kind);
    }

    pub fn firstSampleOffsetForBus(self: *const EventWriter, bus_index: i32) ?usize {
        return self.events().firstSampleOffsetForBus(bus_index);
    }

    pub fn latestSampleOffsetForBus(self: *const EventWriter, bus_index: i32) ?usize {
        return self.events().latestSampleOffsetForBus(bus_index);
    }

    pub fn firstSampleOffsetForChannel(self: *const EventWriter, channel: i16) ?usize {
        return self.events().firstSampleOffsetForChannel(channel);
    }

    pub fn latestSampleOffsetForChannel(self: *const EventWriter, channel: i16) ?usize {
        return self.events().latestSampleOffsetForChannel(channel);
    }

    pub fn firstSampleOffsetForBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) ?usize {
        return self.events().firstSampleOffsetForBusChannel(bus_index, channel);
    }

    pub fn latestSampleOffsetForBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) ?usize {
        return self.events().latestSampleOffsetForBusChannel(bus_index, channel);
    }

    pub fn countKind(self: *const EventWriter, kind: EventKind) usize {
        return self.events().countKind(kind);
    }

    pub fn countNoteAttacks(self: *const EventWriter) usize {
        return self.events().countNoteAttacks();
    }

    pub fn countNoteReleases(self: *const EventWriter) usize {
        return self.events().countNoteReleases();
    }

    pub fn countAtOffset(self: *const EventWriter, sample_offset: usize) usize {
        return self.events().countAtOffset(sample_offset);
    }

    pub fn countKindAtOffset(self: *const EventWriter, kind: EventKind, sample_offset: usize) usize {
        return self.events().countKindAtOffset(kind, sample_offset);
    }

    pub fn countBus(self: *const EventWriter, bus_index: i32) usize {
        return self.events().countBus(bus_index);
    }

    pub fn countChannel(self: *const EventWriter, channel: i16) usize {
        return self.events().countChannel(channel);
    }

    pub fn countBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) usize {
        return self.events().countBusChannel(bus_index, channel);
    }

    pub fn hasBus(self: *const EventWriter, bus_index: i32) bool {
        return self.events().hasBus(bus_index);
    }

    pub fn busEmpty(self: *const EventWriter, bus_index: i32) bool {
        return self.events().busEmpty(bus_index);
    }

    pub fn hasChannel(self: *const EventWriter, channel: i16) bool {
        return self.events().hasChannel(channel);
    }

    pub fn channelEmpty(self: *const EventWriter, channel: i16) bool {
        return self.events().channelEmpty(channel);
    }

    pub fn hasBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) bool {
        return self.events().hasBusChannel(bus_index, channel);
    }

    pub fn busChannelEmpty(self: *const EventWriter, bus_index: i32, channel: i16) bool {
        return self.events().busChannelEmpty(bus_index, channel);
    }

    pub fn firstKind(self: *const EventWriter, kind: EventKind) ?Event {
        return self.events().firstKind(kind);
    }

    pub fn latestKind(self: *const EventWriter, kind: EventKind) ?Event {
        return self.events().latestKind(kind);
    }

    pub fn firstKindAtOffset(self: *const EventWriter, kind: EventKind, sample_offset: usize) ?Event {
        return self.events().firstKindAtOffset(kind, sample_offset);
    }

    pub fn latestKindAtOffset(self: *const EventWriter, kind: EventKind, sample_offset: usize) ?Event {
        return self.events().latestKindAtOffset(kind, sample_offset);
    }

    pub fn firstBus(self: *const EventWriter, bus_index: i32) ?Event {
        return self.events().firstBus(bus_index);
    }

    pub fn latestBus(self: *const EventWriter, bus_index: i32) ?Event {
        return self.events().latestBus(bus_index);
    }

    pub fn firstChannel(self: *const EventWriter, channel: i16) ?Event {
        return self.events().firstChannel(channel);
    }

    pub fn latestChannel(self: *const EventWriter, channel: i16) ?Event {
        return self.events().latestChannel(channel);
    }

    pub fn firstBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) ?Event {
        return self.events().firstBusChannel(bus_index, channel);
    }

    pub fn latestBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) ?Event {
        return self.events().latestBusChannel(bus_index, channel);
    }

    pub fn hasKind(self: *const EventWriter, kind: EventKind) bool {
        return self.events().hasKind(kind);
    }

    pub fn hasNoteAttacks(self: *const EventWriter) bool {
        return self.events().hasNoteAttacks();
    }

    pub fn hasNoteReleases(self: *const EventWriter) bool {
        return self.events().hasNoteReleases();
    }

    pub fn hasAtOffset(self: *const EventWriter, sample_offset: usize) bool {
        return self.events().hasAtOffset(sample_offset);
    }

    pub fn hasKindAtOffset(self: *const EventWriter, kind: EventKind, sample_offset: usize) bool {
        return self.events().hasKindAtOffset(kind, sample_offset);
    }

    pub fn kindEmpty(self: *const EventWriter, kind: EventKind) bool {
        return self.events().kindEmpty(kind);
    }

    pub fn noteAttacksEmpty(self: *const EventWriter) bool {
        return self.events().noteAttacksEmpty();
    }

    pub fn noteReleasesEmpty(self: *const EventWriter) bool {
        return self.events().noteReleasesEmpty();
    }

    pub fn offsetEmpty(self: *const EventWriter, sample_offset: usize) bool {
        return self.events().offsetEmpty(sample_offset);
    }

    pub fn kindAtOffsetEmpty(self: *const EventWriter, kind: EventKind, sample_offset: usize) bool {
        return self.events().kindAtOffsetEmpty(kind, sample_offset);
    }

    pub fn onlyAtOffset(self: *const EventWriter, sample_offset: usize) bool {
        return self.events().onlyAtOffset(sample_offset);
    }

    pub fn onlyKindAtOffset(self: *const EventWriter, kind: EventKind, sample_offset: usize) bool {
        return self.events().onlyKindAtOffset(kind, sample_offset);
    }

    pub fn onlyKind(self: *const EventWriter, kind: EventKind) bool {
        return self.events().onlyKind(kind);
    }

    pub fn onlyNoteAttacks(self: *const EventWriter) bool {
        return self.events().onlyNoteAttacks();
    }

    pub fn onlyNoteReleases(self: *const EventWriter) bool {
        return self.events().onlyNoteReleases();
    }

    pub fn onlyBus(self: *const EventWriter, bus_index: i32) bool {
        return self.events().onlyBus(bus_index);
    }

    pub fn onlyChannel(self: *const EventWriter, channel: i16) bool {
        return self.events().onlyChannel(channel);
    }

    pub fn onlyBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) bool {
        return self.events().onlyBusChannel(bus_index, channel);
    }

    pub fn nextSampleOffset(self: *const EventWriter, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffset(after_sample_offset);
    }

    pub fn nextSampleOffsetForKind(self: *const EventWriter, kind: EventKind, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffsetForKind(kind, after_sample_offset);
    }

    pub fn nextSampleOffsetForBus(self: *const EventWriter, bus_index: i32, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffsetForBus(bus_index, after_sample_offset);
    }

    pub fn nextSampleOffsetForChannel(self: *const EventWriter, channel: i16, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffsetForChannel(channel, after_sample_offset);
    }

    pub fn nextSampleOffsetForBusChannel(self: *const EventWriter, bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffsetForBusChannel(bus_index, channel, after_sample_offset);
    }

    pub fn ofKind(self: *const EventWriter, kind: EventKind) EventKindIterator {
        return self.events().ofKind(kind);
    }

    pub fn atOffset(self: *const EventWriter, sample_offset: usize) EventOffsetIterator {
        return self.events().atOffset(sample_offset);
    }

    pub fn blockSegments(self: *const EventWriter) EventBlockSegmentIterator {
        return self.events().blockSegments(self.frame_count);
    }

    pub fn events(self: *const EventWriter) Events {
        return .{ .items = self.storage[0..self.count] };
    }
};

pub fn AudioInputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []const Sample,
        frame_count: usize,

        pub fn init(channels: []const []const Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]const Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }

        pub fn hasChannel(self: Self, index: usize) bool {
            return self.channel(index) != null;
        }

        pub fn channelEmpty(self: Self, index: usize) bool {
            return !self.hasChannel(index);
        }

        pub fn channelCount(self: Self) usize {
            return self.channels.len;
        }

        pub fn isEmpty(self: Self) bool {
            return self.channels.len == 0;
        }

        pub fn hasChannels(self: Self) bool {
            return self.channels.len != 0;
        }

        pub fn frameCount(self: Self) usize {
            return self.frame_count;
        }
    };
}

pub fn AudioOutputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []Sample,
        frame_count: usize,

        pub fn init(channels: []const []Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }

        pub fn hasChannel(self: Self, index: usize) bool {
            return self.channel(index) != null;
        }

        pub fn channelEmpty(self: Self, index: usize) bool {
            return !self.hasChannel(index);
        }

        pub fn channelCount(self: Self) usize {
            return self.channels.len;
        }

        pub fn isEmpty(self: Self) bool {
            return self.channels.len == 0;
        }

        pub fn hasChannels(self: Self) bool {
            return self.channels.len != 0;
        }

        pub fn frameCount(self: Self) usize {
            return self.frame_count;
        }

        pub fn fill(self: Self, value: Sample) void {
            for (self.channels) |channel_samples| {
                @memset(channel_samples, value);
            }
        }

        pub fn clear(self: Self) void {
            self.fill(0);
        }
    };
}

pub const ProcessAttachments = struct {
    parameter_changes: []const ParameterChange = &.{},
    events: []const Event = &.{},
    output_events: ?*EventWriter = null,
};

pub fn ProcessContext(comptime Sample: type) type {
    return struct {
        sample_rate: f64,
        inputs: AudioInputs(Sample),
        outputs: AudioOutputs(Sample),
        parameter_changes: ParameterChanges = .{},
        events: Events = .{},
        output_events: ?*EventWriter = null,

        pub fn init(sample_rate: f64, input_channels: []const []const Sample, output_channels: []const []Sample) !@This() {
            if (sample_rate <= 0.0 or !std.math.isFinite(sample_rate)) return error.InvalidSampleRate;
            const inputs = try AudioInputs(Sample).init(input_channels);
            const outputs = try AudioOutputs(Sample).init(output_channels);
            if (!inputs.isEmpty() and !outputs.isEmpty() and inputs.frameCount() != outputs.frameCount()) {
                return error.MismatchedFrameCount;
            }
            return .{
                .sample_rate = sample_rate,
                .inputs = inputs,
                .outputs = outputs,
            };
        }

        pub fn initWith(
            sample_rate: f64,
            input_channels: []const []const Sample,
            output_channels: []const []Sample,
            attachments: ProcessAttachments,
        ) !@This() {
            var context = try @This().init(sample_rate, input_channels, output_channels);
            try context.setParameterChanges(attachments.parameter_changes);
            try context.setEvents(attachments.events);
            if (attachments.output_events) |writer| try context.setOutputEvents(writer);
            return context;
        }

        pub fn setParameterChanges(self: *@This(), changes: []const ParameterChange) !void {
            self.parameter_changes = try ParameterChanges.init(changes, self.frameCount());
        }

        pub fn setEvents(self: *@This(), events: []const Event) !void {
            self.events = try Events.init(events, self.frameCount());
        }

        pub fn setOutputEvents(self: *@This(), writer: *EventWriter) !void {
            if (writer.frame_count != self.frameCount()) return error.MismatchedFrameCount;
            self.output_events = writer;
        }

        pub fn sampleRate(self: @This()) f64 {
            return self.sample_rate;
        }

        pub fn sampleDurationSeconds(self: @This()) f64 {
            return 1.0 / self.sample_rate;
        }

        pub fn blockDurationSeconds(self: @This()) f64 {
            return @as(f64, @floatFromInt(self.frameCount())) / self.sample_rate;
        }

        pub fn blockSegment(self: @This()) BlockSegment {
            return .{ .start_offset = 0, .end_offset = self.frameCount() };
        }

        pub fn sampleOffsetSeconds(self: @This(), sample_offset: usize) f64 {
            return @as(f64, @floatFromInt(sample_offset)) / self.sample_rate;
        }

        pub fn containsSampleOffset(self: @This(), sample_offset: usize) bool {
            return sample_offset < self.frameCount();
        }

        pub fn isEndOffset(self: @This(), sample_offset: usize) bool {
            return sample_offset == self.frameCount();
        }

        pub fn isPastEndOffset(self: @This(), sample_offset: usize) bool {
            return sample_offset > self.frameCount();
        }

        pub fn remainingFramesFromOffset(self: @This(), sample_offset: usize) usize {
            return self.frameCount() -| sample_offset;
        }

        pub fn remainingSecondsFromOffset(self: @This(), sample_offset: usize) f64 {
            return @as(f64, @floatFromInt(self.remainingFramesFromOffset(sample_offset))) / self.sample_rate;
        }

        pub fn parameterChanges(self: @This()) ParameterChanges {
            return self.parameter_changes;
        }

        pub fn parameterChangeCount(self: @This()) usize {
            return self.parameter_changes.changeCount();
        }

        pub fn parameterChangesEmpty(self: @This()) bool {
            return self.parameter_changes.isEmpty();
        }

        pub fn hasParameterChanges(self: @This()) bool {
            return self.parameter_changes.hasChanges();
        }

        pub fn firstParameterChangeOffset(self: @This()) ?usize {
            return self.parameter_changes.firstSampleOffset();
        }

        pub fn latestParameterChangeOffset(self: @This()) ?usize {
            return self.parameter_changes.latestSampleOffset();
        }

        pub fn firstParameterChangeOffsetForId(self: @This(), id: u32) ?usize {
            return self.parameter_changes.firstSampleOffsetForId(id);
        }

        pub fn latestParameterChangeOffsetForId(self: @This(), id: u32) ?usize {
            return self.parameter_changes.latestSampleOffsetForId(id);
        }

        pub fn firstAnyParameterChange(self: @This()) ?ParameterChange {
            return self.parameter_changes.firstChange();
        }

        pub fn latestAnyParameterChange(self: @This()) ?ParameterChange {
            return self.parameter_changes.latestChange();
        }

        pub fn firstAnyParameterNormalized(self: @This()) ?f64 {
            return self.parameter_changes.firstAnyNormalized();
        }

        pub fn latestAnyParameterNormalized(self: @This()) ?f64 {
            return self.parameter_changes.latestAnyNormalized();
        }

        pub fn latestParameterChange(self: @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.latest(id);
        }

        pub fn firstParameterChange(self: @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.first(id);
        }

        pub fn firstParameterChangeAtOffset(self: @This(), sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.firstAtOffset(sample_offset);
        }

        pub fn latestParameterChangeAtOffset(self: @This(), sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestAtOffset(sample_offset);
        }

        pub fn firstParameterChangeForIdAtOffset(self: @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.firstForIdAtOffset(id, sample_offset);
        }

        pub fn latestParameterChangeForIdAtOffset(self: @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestForIdAtOffset(id, sample_offset);
        }

        pub fn countParameterChanges(self: @This(), id: u32) usize {
            return self.parameter_changes.count(id);
        }

        pub fn countParameterChangesAtOffset(self: @This(), sample_offset: usize) usize {
            return self.parameter_changes.countAtOffset(sample_offset);
        }

        pub fn countParameterChangesForIdAtOffset(self: @This(), id: u32, sample_offset: usize) usize {
            return self.parameter_changes.countForIdAtOffset(id, sample_offset);
        }

        pub fn hasParameterChange(self: @This(), id: u32) bool {
            return self.parameter_changes.has(id);
        }

        pub fn hasParameterChangeAtOffset(self: @This(), sample_offset: usize) bool {
            return self.parameter_changes.hasAtOffset(sample_offset);
        }

        pub fn hasParameterChangeForIdAtOffset(self: @This(), id: u32, sample_offset: usize) bool {
            return self.parameter_changes.hasForIdAtOffset(id, sample_offset);
        }

        pub fn parameterChangesForIdEmpty(self: @This(), id: u32) bool {
            return self.parameter_changes.empty(id);
        }

        pub fn parameterChangesAtOffsetEmpty(self: @This(), sample_offset: usize) bool {
            return self.parameter_changes.offsetEmpty(sample_offset);
        }

        pub fn parameterChangesForIdAtOffsetEmpty(self: @This(), id: u32, sample_offset: usize) bool {
            return self.parameter_changes.idAtOffsetEmpty(id, sample_offset);
        }

        pub fn onlyParameterChangesForId(self: @This(), id: u32) bool {
            return self.parameter_changes.only(id);
        }

        pub fn latestParameterNormalized(self: @This(), id: u32) ?f64 {
            return self.parameter_changes.latestNormalized(id);
        }

        pub fn firstParameterNormalized(self: @This(), id: u32) ?f64 {
            return self.parameter_changes.firstNormalized(id);
        }

        pub fn firstParameterNormalizedAtOffset(self: @This(), sample_offset: usize) ?f64 {
            return self.parameter_changes.firstNormalizedAtOffset(sample_offset);
        }

        pub fn latestParameterNormalizedAtOffset(self: @This(), sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedAtOffset(sample_offset);
        }

        pub fn firstParameterNormalizedForIdAtOffset(self: @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.firstNormalizedForIdAtOffset(id, sample_offset);
        }

        pub fn latestParameterNormalizedForIdAtOffset(self: @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedForIdAtOffset(id, sample_offset);
        }

        pub fn firstParameterNormalizedAtOffsetOr(self: @This(), sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.firstNormalizedAtOffsetOr(sample_offset, default);
        }

        pub fn latestParameterNormalizedAtOffsetOr(self: @This(), sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.latestNormalizedAtOffsetOr(sample_offset, default);
        }

        pub fn firstParameterNormalizedForIdAtOffsetOr(self: @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.firstNormalizedForIdAtOffsetOr(id, sample_offset, default);
        }

        pub fn latestParameterNormalizedForIdAtOffsetOr(self: @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.latestNormalizedForIdAtOffsetOr(id, sample_offset, default);
        }

        pub fn firstParameterNormalizedOr(self: @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.firstNormalizedOr(id, default);
        }

        pub fn latestParameterNormalizedOr(self: @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.latestNormalizedOr(id, default);
        }

        pub fn latestParameterChangeAtOrBefore(self: @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestAtOrBefore(id, sample_offset);
        }

        pub fn latestParameterNormalizedAtOrBefore(self: @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedAtOrBefore(id, sample_offset);
        }

        pub fn parameterNormalizedAtOrBeforeOr(self: @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.normalizedAtOrBeforeOr(id, sample_offset, default);
        }

        pub fn nextParameterChangeOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffset(after_sample_offset);
        }

        pub fn nextParameterChangeOffsetForId(self: @This(), id: u32, after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffsetForId(id, after_sample_offset);
        }

        pub fn parameterSegmentAt(self: @This(), id: u32, start_offset: usize, default: f64) ?ParameterSegment {
            return self.parameter_changes.segmentAt(id, start_offset, self.frameCount(), default);
        }

        pub fn parameterSegments(self: @This(), id: u32, default: f64) ParameterSegmentIterator {
            return self.parameter_changes.segments(id, self.frameCount(), default);
        }

        pub fn parameterBlockSegments(self: @This()) BlockSegmentIterator {
            return self.parameter_changes.blockSegments(self.frameCount());
        }

        pub fn processBlockSegments(self: @This()) ProcessBlockSegmentIterator {
            return .{
                .parameter_changes = self.parameter_changes,
                .events = self.events,
                .frame_count = self.frameCount(),
            };
        }

        pub fn inputEvents(self: @This()) Events {
            return self.events;
        }

        pub fn inputEventsOfKind(self: @This(), kind: EventKind) EventKindIterator {
            return self.events.ofKind(kind);
        }

        pub fn inputEventsAtOffset(self: @This(), sample_offset: usize) EventOffsetIterator {
            return self.events.atOffset(sample_offset);
        }

        pub fn inputEventBlockSegments(self: @This()) EventBlockSegmentIterator {
            return self.events.blockSegments(self.frameCount());
        }

        pub fn inputEventCount(self: @This()) usize {
            return self.events.eventCount();
        }

        pub fn inputEventsEmpty(self: @This()) bool {
            return self.events.isEmpty();
        }

        pub fn hasInputEvents(self: @This()) bool {
            return self.events.hasEvents();
        }

        pub fn firstEventOffset(self: @This()) ?usize {
            return self.events.firstSampleOffset();
        }

        pub fn latestEventOffset(self: @This()) ?usize {
            return self.events.latestSampleOffset();
        }

        pub fn firstInputEvent(self: @This()) ?Event {
            return self.events.first();
        }

        pub fn latestInputEvent(self: @This()) ?Event {
            return self.events.latest();
        }

        pub fn firstInputEventAtOffset(self: @This(), sample_offset: usize) ?Event {
            return self.events.firstAtOffset(sample_offset);
        }

        pub fn latestInputEventAtOffset(self: @This(), sample_offset: usize) ?Event {
            return self.events.latestAtOffset(sample_offset);
        }

        pub fn firstEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            return self.events.firstSampleOffsetForKind(kind);
        }

        pub fn latestEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            return self.events.latestSampleOffsetForKind(kind);
        }

        pub fn firstEventOffsetForBus(self: @This(), bus_index: i32) ?usize {
            return self.events.firstSampleOffsetForBus(bus_index);
        }

        pub fn latestEventOffsetForBus(self: @This(), bus_index: i32) ?usize {
            return self.events.latestSampleOffsetForBus(bus_index);
        }

        pub fn firstEventOffsetForChannel(self: @This(), channel: i16) ?usize {
            return self.events.firstSampleOffsetForChannel(channel);
        }

        pub fn latestEventOffsetForChannel(self: @This(), channel: i16) ?usize {
            return self.events.latestSampleOffsetForChannel(channel);
        }

        pub fn firstEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16) ?usize {
            return self.events.firstSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16) ?usize {
            return self.events.latestSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn firstEvent(self: @This(), kind: EventKind) ?Event {
            return self.events.firstKind(kind);
        }

        pub fn latestEvent(self: @This(), kind: EventKind) ?Event {
            return self.events.latestKind(kind);
        }

        pub fn firstEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.events.firstKindAtOffset(kind, sample_offset);
        }

        pub fn latestEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.events.latestKindAtOffset(kind, sample_offset);
        }

        pub fn firstEventForBus(self: @This(), bus_index: i32) ?Event {
            return self.events.firstBus(bus_index);
        }

        pub fn latestEventForBus(self: @This(), bus_index: i32) ?Event {
            return self.events.latestBus(bus_index);
        }

        pub fn firstEventForChannel(self: @This(), channel: i16) ?Event {
            return self.events.firstChannel(channel);
        }

        pub fn latestEventForChannel(self: @This(), channel: i16) ?Event {
            return self.events.latestChannel(channel);
        }

        pub fn firstEventForBusChannel(self: @This(), bus_index: i32, channel: i16) ?Event {
            return self.events.firstBusChannel(bus_index, channel);
        }

        pub fn latestEventForBusChannel(self: @This(), bus_index: i32, channel: i16) ?Event {
            return self.events.latestBusChannel(bus_index, channel);
        }

        pub fn hasEvent(self: @This(), kind: EventKind) bool {
            return self.events.hasKind(kind);
        }

        pub fn eventsOfKindEmpty(self: @This(), kind: EventKind) bool {
            return self.events.kindEmpty(kind);
        }

        pub fn countEvents(self: @This(), kind: EventKind) usize {
            return self.events.countKind(kind);
        }

        pub fn countNoteAttacks(self: @This()) usize {
            return self.events.countNoteAttacks();
        }

        pub fn countNoteReleases(self: @This()) usize {
            return self.events.countNoteReleases();
        }

        pub fn countEventsAtOffset(self: @This(), sample_offset: usize) usize {
            return self.events.countAtOffset(sample_offset);
        }

        pub fn countEventsOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) usize {
            return self.events.countKindAtOffset(kind, sample_offset);
        }

        pub fn countEventsForBus(self: @This(), bus_index: i32) usize {
            return self.events.countBus(bus_index);
        }

        pub fn countEventsForChannel(self: @This(), channel: i16) usize {
            return self.events.countChannel(channel);
        }

        pub fn countEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) usize {
            return self.events.countBusChannel(bus_index, channel);
        }

        pub fn hasEventsForBus(self: @This(), bus_index: i32) bool {
            return self.events.hasBus(bus_index);
        }

        pub fn eventsForBusEmpty(self: @This(), bus_index: i32) bool {
            return self.events.busEmpty(bus_index);
        }

        pub fn hasEventsForChannel(self: @This(), channel: i16) bool {
            return self.events.hasChannel(channel);
        }

        pub fn hasEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) bool {
            return self.events.hasBusChannel(bus_index, channel);
        }

        pub fn hasEventAtOffset(self: @This(), sample_offset: usize) bool {
            return self.events.hasAtOffset(sample_offset);
        }

        pub fn hasEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.hasKindAtOffset(kind, sample_offset);
        }

        pub fn hasNoteAttacks(self: @This()) bool {
            return self.events.hasNoteAttacks();
        }

        pub fn hasNoteReleases(self: @This()) bool {
            return self.events.hasNoteReleases();
        }

        pub fn eventsForChannelEmpty(self: @This(), channel: i16) bool {
            return self.events.channelEmpty(channel);
        }

        pub fn eventsForBusChannelEmpty(self: @This(), bus_index: i32, channel: i16) bool {
            return self.events.busChannelEmpty(bus_index, channel);
        }

        pub fn eventsAtOffsetEmpty(self: @This(), sample_offset: usize) bool {
            return self.events.offsetEmpty(sample_offset);
        }

        pub fn eventsOfKindAtOffsetEmpty(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.kindAtOffsetEmpty(kind, sample_offset);
        }

        pub fn onlyInputEventsAtOffset(self: @This(), sample_offset: usize) bool {
            return self.events.onlyAtOffset(sample_offset);
        }

        pub fn onlyInputEventsOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.onlyKindAtOffset(kind, sample_offset);
        }

        pub fn noteAttacksEmpty(self: @This()) bool {
            return self.events.noteAttacksEmpty();
        }

        pub fn noteReleasesEmpty(self: @This()) bool {
            return self.events.noteReleasesEmpty();
        }

        pub fn onlyInputEventsOfKind(self: @This(), kind: EventKind) bool {
            return self.events.onlyKind(kind);
        }

        pub fn onlyInputNoteAttacks(self: @This()) bool {
            return self.events.onlyNoteAttacks();
        }

        pub fn onlyInputNoteReleases(self: @This()) bool {
            return self.events.onlyNoteReleases();
        }

        pub fn onlyInputEventsForBus(self: @This(), bus_index: i32) bool {
            return self.events.onlyBus(bus_index);
        }

        pub fn onlyInputEventsForChannel(self: @This(), channel: i16) bool {
            return self.events.onlyChannel(channel);
        }

        pub fn onlyInputEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) bool {
            return self.events.onlyBusChannel(bus_index, channel);
        }

        pub fn nextEventOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffset(after_sample_offset);
        }

        pub fn nextEventOffsetForKind(self: @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForKind(kind, after_sample_offset);
        }

        pub fn nextEventOffsetForBus(self: @This(), bus_index: i32, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForBus(bus_index, after_sample_offset);
        }

        pub fn nextEventOffsetForChannel(self: @This(), channel: i16, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForChannel(channel, after_sample_offset);
        }

        pub fn nextEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForBusChannel(bus_index, channel, after_sample_offset);
        }

        pub fn appendOutputEvent(self: *@This(), event: Event) !void {
            _ = try self.appendOutputEventCount(event);
        }

        pub fn appendOutputEventCount(self: *@This(), event: Event) !usize {
            const writer = self.output_events orelse return error.OutputEventsUnavailable;
            return writer.appendCount(event);
        }

        pub fn appendOutputEvents(self: *@This(), events: Events) !void {
            _ = try self.appendOutputEventsCount(events);
        }

        pub fn appendOutputEventsCount(self: *@This(), events: Events) !usize {
            const writer = self.output_events orelse return error.OutputEventsUnavailable;
            return writer.appendAllCount(events);
        }

        pub fn canAppendOutputEvent(self: @This()) bool {
            const writer = self.output_events orelse return false;
            return writer.canAppend(1);
        }

        pub fn canAppendOutputEvents(self: @This(), event_count: usize) bool {
            const writer = self.output_events orelse return false;
            return writer.canAppend(event_count);
        }

        pub fn canAppendOutputEventValue(self: @This(), event: Event) bool {
            const writer = self.output_events orelse return false;
            return writer.canAppendEvent(event);
        }

        pub fn canAppendOutputEventValues(self: @This(), events: Events) bool {
            const writer = self.output_events orelse return false;
            return writer.canAppendEvents(events);
        }

        pub fn writtenOutputEvents(self: @This()) Events {
            const writer = self.output_events orelse return .{};
            return writer.events();
        }

        pub fn outputEventBlockSegments(self: @This()) EventBlockSegmentIterator {
            const writer = self.output_events orelse return (Events{}).blockSegments(self.frameCount());
            return writer.blockSegments();
        }

        pub fn outputEventsAtOffset(self: @This(), sample_offset: usize) EventOffsetIterator {
            return self.writtenOutputEvents().atOffset(sample_offset);
        }

        pub fn outputEventsOfKind(self: @This(), kind: EventKind) EventKindIterator {
            return self.writtenOutputEvents().ofKind(kind);
        }

        pub fn firstOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffset();
        }

        pub fn latestOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffset();
        }

        pub fn firstWrittenOutputEvent(self: @This()) ?Event {
            return self.writtenOutputEvents().first();
        }

        pub fn latestWrittenOutputEvent(self: @This()) ?Event {
            return self.writtenOutputEvents().latest();
        }

        pub fn firstOutputEventAtOffset(self: @This(), sample_offset: usize) ?Event {
            return self.writtenOutputEvents().firstAtOffset(sample_offset);
        }

        pub fn latestOutputEventAtOffset(self: @This(), sample_offset: usize) ?Event {
            return self.writtenOutputEvents().latestAtOffset(sample_offset);
        }

        pub fn firstOutputEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffsetForKind(kind);
        }

        pub fn latestOutputEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffsetForKind(kind);
        }

        pub fn firstOutputEventOffsetForBus(self: @This(), bus_index: i32) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffsetForBus(bus_index);
        }

        pub fn latestOutputEventOffsetForBus(self: @This(), bus_index: i32) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffsetForBus(bus_index);
        }

        pub fn firstOutputEventOffsetForChannel(self: @This(), channel: i16) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffsetForChannel(channel);
        }

        pub fn latestOutputEventOffsetForChannel(self: @This(), channel: i16) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffsetForChannel(channel);
        }

        pub fn firstOutputEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestOutputEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn firstOutputEvent(self: @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().firstKind(kind);
        }

        pub fn latestOutputEvent(self: @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().latestKind(kind);
        }

        pub fn firstOutputEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.writtenOutputEvents().firstKindAtOffset(kind, sample_offset);
        }

        pub fn latestOutputEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.writtenOutputEvents().latestKindAtOffset(kind, sample_offset);
        }

        pub fn firstOutputEventForBus(self: @This(), bus_index: i32) ?Event {
            return self.writtenOutputEvents().firstBus(bus_index);
        }

        pub fn latestOutputEventForBus(self: @This(), bus_index: i32) ?Event {
            return self.writtenOutputEvents().latestBus(bus_index);
        }

        pub fn firstOutputEventForChannel(self: @This(), channel: i16) ?Event {
            return self.writtenOutputEvents().firstChannel(channel);
        }

        pub fn latestOutputEventForChannel(self: @This(), channel: i16) ?Event {
            return self.writtenOutputEvents().latestChannel(channel);
        }

        pub fn firstOutputEventForBusChannel(self: @This(), bus_index: i32, channel: i16) ?Event {
            return self.writtenOutputEvents().firstBusChannel(bus_index, channel);
        }

        pub fn latestOutputEventForBusChannel(self: @This(), bus_index: i32, channel: i16) ?Event {
            return self.writtenOutputEvents().latestBusChannel(bus_index, channel);
        }

        pub fn hasOutputEvent(self: @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().hasKind(kind);
        }

        pub fn outputEventsOfKindEmpty(self: @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().kindEmpty(kind);
        }

        pub fn countOutputEvents(self: @This(), kind: EventKind) usize {
            return self.writtenOutputEvents().countKind(kind);
        }

        pub fn countOutputNoteAttacks(self: @This()) usize {
            return self.writtenOutputEvents().countNoteAttacks();
        }

        pub fn countOutputNoteReleases(self: @This()) usize {
            return self.writtenOutputEvents().countNoteReleases();
        }

        pub fn countOutputEventsAtOffset(self: @This(), sample_offset: usize) usize {
            return self.writtenOutputEvents().countAtOffset(sample_offset);
        }

        pub fn countOutputEventsOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) usize {
            return self.writtenOutputEvents().countKindAtOffset(kind, sample_offset);
        }

        pub fn countOutputEventsForBus(self: @This(), bus_index: i32) usize {
            return self.writtenOutputEvents().countBus(bus_index);
        }

        pub fn countOutputEventsForChannel(self: @This(), channel: i16) usize {
            return self.writtenOutputEvents().countChannel(channel);
        }

        pub fn countOutputEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) usize {
            return self.writtenOutputEvents().countBusChannel(bus_index, channel);
        }

        pub fn hasOutputEventsForBus(self: @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().hasBus(bus_index);
        }

        pub fn outputEventsForBusEmpty(self: @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().busEmpty(bus_index);
        }

        pub fn hasOutputEventsForChannel(self: @This(), channel: i16) bool {
            return self.writtenOutputEvents().hasChannel(channel);
        }

        pub fn hasOutputEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().hasBusChannel(bus_index, channel);
        }

        pub fn hasOutputEventAtOffset(self: @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().hasAtOffset(sample_offset);
        }

        pub fn hasOutputEventOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().hasKindAtOffset(kind, sample_offset);
        }

        pub fn hasOutputNoteAttacks(self: @This()) bool {
            return self.writtenOutputEvents().hasNoteAttacks();
        }

        pub fn hasOutputNoteReleases(self: @This()) bool {
            return self.writtenOutputEvents().hasNoteReleases();
        }

        pub fn outputEventsForChannelEmpty(self: @This(), channel: i16) bool {
            return self.writtenOutputEvents().channelEmpty(channel);
        }

        pub fn outputEventsForBusChannelEmpty(self: @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().busChannelEmpty(bus_index, channel);
        }

        pub fn outputEventsAtOffsetEmpty(self: @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().offsetEmpty(sample_offset);
        }

        pub fn outputEventsOfKindAtOffsetEmpty(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().kindAtOffsetEmpty(kind, sample_offset);
        }

        pub fn onlyOutputEventsAtOffset(self: @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().onlyAtOffset(sample_offset);
        }

        pub fn onlyOutputEventsOfKindAtOffset(self: @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().onlyKindAtOffset(kind, sample_offset);
        }

        pub fn outputNoteAttacksEmpty(self: @This()) bool {
            return self.writtenOutputEvents().noteAttacksEmpty();
        }

        pub fn outputNoteReleasesEmpty(self: @This()) bool {
            return self.writtenOutputEvents().noteReleasesEmpty();
        }

        pub fn onlyOutputEventsOfKind(self: @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().onlyKind(kind);
        }

        pub fn onlyOutputNoteAttacks(self: @This()) bool {
            return self.writtenOutputEvents().onlyNoteAttacks();
        }

        pub fn onlyOutputNoteReleases(self: @This()) bool {
            return self.writtenOutputEvents().onlyNoteReleases();
        }

        pub fn onlyOutputEventsForBus(self: @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().onlyBus(bus_index);
        }

        pub fn onlyOutputEventsForChannel(self: @This(), channel: i16) bool {
            return self.writtenOutputEvents().onlyChannel(channel);
        }

        pub fn onlyOutputEventsForBusChannel(self: @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().onlyBusChannel(bus_index, channel);
        }

        pub fn nextOutputEventOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffset(after_sample_offset);
        }

        pub fn nextOutputEventOffsetForKind(self: @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForKind(kind, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForBus(self: @This(), bus_index: i32, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForBus(bus_index, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForChannel(self: @This(), channel: i16, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForChannel(channel, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForBusChannel(self: @This(), bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForBusChannel(bus_index, channel, after_sample_offset);
        }

        pub fn clearOutputEvents(self: @This()) void {
            _ = self.clearOutputEventsCount();
        }

        pub fn clearOutputEventsCount(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.clearCount();
        }

        pub fn hasOutputEventWriter(self: @This()) bool {
            return self.output_events != null;
        }

        pub fn outputEventCount(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.eventCount();
        }

        pub fn outputEventCapacity(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.capacity();
        }

        pub fn outputEventRemainingCapacity(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.remainingCapacity();
        }

        pub fn outputEventFrameCount(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.frameCount();
        }

        pub fn outputEventsEmpty(self: @This()) bool {
            const writer = self.output_events orelse return true;
            return writer.isEmpty();
        }

        pub fn hasOutputEvents(self: @This()) bool {
            const writer = self.output_events orelse return false;
            return writer.hasEvents();
        }

        pub fn outputEventsFull(self: @This()) bool {
            const writer = self.output_events orelse return true;
            return writer.isFull();
        }

        pub fn fillOutputs(self: @This(), value: Sample) void {
            self.outputs.fill(value);
        }

        pub fn clearOutputs(self: @This()) void {
            self.outputs.clear();
        }

        pub fn inputChannel(self: @This(), index: usize) ?[]const Sample {
            return self.inputs.channel(index);
        }

        pub fn outputChannel(self: @This(), index: usize) ?[]Sample {
            return self.outputs.channel(index);
        }

        pub fn hasInputChannel(self: @This(), index: usize) bool {
            return self.inputs.hasChannel(index);
        }

        pub fn inputChannelEmpty(self: @This(), index: usize) bool {
            return self.inputs.channelEmpty(index);
        }

        pub fn hasOutputChannel(self: @This(), index: usize) bool {
            return self.outputs.hasChannel(index);
        }

        pub fn outputChannelEmpty(self: @This(), index: usize) bool {
            return self.outputs.channelEmpty(index);
        }

        pub fn inputChannelCount(self: @This()) usize {
            return self.inputs.channelCount();
        }

        pub fn outputChannelCount(self: @This()) usize {
            return self.outputs.channelCount();
        }

        pub fn inputChannelsEmpty(self: @This()) bool {
            return self.inputs.isEmpty();
        }

        pub fn hasInputChannels(self: @This()) bool {
            return self.inputs.hasChannels();
        }

        pub fn outputChannelsEmpty(self: @This()) bool {
            return self.outputs.isEmpty();
        }

        pub fn hasOutputChannels(self: @This()) bool {
            return self.outputs.hasChannels();
        }

        pub fn inputFrameCount(self: @This()) usize {
            return self.inputs.frameCount();
        }

        pub fn outputFrameCount(self: @This()) usize {
            return self.outputs.frameCount();
        }

        pub fn frameCount(self: @This()) usize {
            if (self.inputs.channelCount() == 0) return self.outputs.frame_count;
            if (self.outputs.channelCount() == 0) return self.inputs.frame_count;
            return self.inputs.frame_count;
        }
    };
}

test "audio input view validates channel frame counts" {
    const left = [_]f32{ 0.1, 0.2 };
    const right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]const f32{ &left, &right };
    const inputs = try AudioInputs(f32).init(&channels);

    try std.testing.expectEqual(@as(usize, 2), inputs.channels.len);
    try std.testing.expectEqual(@as(usize, 2), inputs.channelCount());
    try std.testing.expect(!inputs.isEmpty());
    try std.testing.expect(inputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 2), inputs.frame_count);
    try std.testing.expectEqual(@as(usize, 2), inputs.frameCount());
    try std.testing.expectEqual(@as(f32, 0.3), inputs.channel(1).?[0]);
    try std.testing.expect(inputs.hasChannel(1));
    try std.testing.expect(!inputs.channelEmpty(1));
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(2));
    try std.testing.expect(!inputs.hasChannel(2));
    try std.testing.expect(inputs.channelEmpty(2));
    const empty_inputs = try AudioInputs(f32).init(&[_][]const f32{});
    try std.testing.expect(empty_inputs.isEmpty());
    try std.testing.expect(!empty_inputs.hasChannels());
    try std.testing.expect(empty_inputs.channelEmpty(0));
}

test "audio output view rejects mismatched channel frame counts" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{0.3};
    const channels = [_][]f32{ &left, &right };

    try std.testing.expectError(error.MismatchedFrameCount, AudioOutputs(f32).init(&channels));
}

test "audio output view fills and clears channels" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]f32{ &left, &right };
    const outputs = try AudioOutputs(f32).init(&channels);

    try std.testing.expect(!outputs.isEmpty());
    try std.testing.expect(outputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 2), outputs.frameCount());
    try std.testing.expect(outputs.hasChannel(1));
    try std.testing.expect(!outputs.channelEmpty(1));
    try std.testing.expect(!outputs.hasChannel(2));
    try std.testing.expect(outputs.channelEmpty(2));
    const empty_outputs = try AudioOutputs(f32).init(&[_][]f32{});
    try std.testing.expect(empty_outputs.isEmpty());
    try std.testing.expect(!empty_outputs.hasChannels());
    try std.testing.expect(empty_outputs.channelEmpty(0));

    outputs.fill(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), left[0]);
    try std.testing.expectEqual(@as(f32, 0.5), left[1]);
    try std.testing.expectEqual(@as(f32, 0.5), right[0]);
    try std.testing.expectEqual(@as(f32, 0.5), right[1]);

    outputs.clear();
    try std.testing.expectEqual(@as(f32, 0.0), left[0]);
    try std.testing.expectEqual(@as(f32, 0.0), left[1]);
    try std.testing.expectEqual(@as(f32, 0.0), right[0]);
    try std.testing.expectEqual(@as(f32, 0.0), right[1]);
}

test "process context reports usable frame count" {
    const in_left = [_]f64{ 0.1, 0.2, 0.3 };
    const in_right = [_]f64{ 0.4, 0.5, 0.6 };
    var out_left = [_]f64{ 0.0, 0.0, 0.0 };
    var out_right = [_]f64{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f64{ &in_left, &in_right };
    const output_channels = [_][]f64{ &out_left, &out_right };
    const context = try ProcessContext(f64).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
    try std.testing.expectEqual(@as(usize, 3), context.inputFrameCount());
    try std.testing.expectEqual(@as(usize, 3), context.outputFrameCount());
    try std.testing.expectEqual(@as(f64, 48_000.0), context.sampleRate());
    try std.testing.expectEqual(@as(f64, 1.0 / 48_000.0), context.sampleDurationSeconds());
    try std.testing.expectEqual(@as(f64, 3.0 / 48_000.0), context.blockDurationSeconds());
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 3 }, context.blockSegment());
    try std.testing.expect(context.blockSegment().contains(2));
    try std.testing.expect(!context.blockSegment().contains(3));
    try std.testing.expectEqual(@as(f64, 2.0 / 48_000.0), context.sampleOffsetSeconds(2));
    try std.testing.expect(context.containsSampleOffset(0));
    try std.testing.expect(context.containsSampleOffset(2));
    try std.testing.expect(!context.containsSampleOffset(3));
    try std.testing.expect(!context.isEndOffset(2));
    try std.testing.expect(context.isEndOffset(3));
    try std.testing.expect(!context.isEndOffset(4));
    try std.testing.expect(!context.isPastEndOffset(3));
    try std.testing.expect(context.isPastEndOffset(4));
    try std.testing.expectEqual(@as(usize, 1), context.remainingFramesFromOffset(2));
    try std.testing.expectEqual(@as(usize, 0), context.remainingFramesFromOffset(3));
    try std.testing.expectEqual(@as(usize, 0), context.remainingFramesFromOffset(4));
    try std.testing.expectEqual(@as(f64, 1.0 / 48_000.0), context.remainingSecondsFromOffset(2));
    try std.testing.expectEqual(@as(f64, 0.0), context.remainingSecondsFromOffset(3));
    try std.testing.expectEqual(@as(f64, 0.0), context.remainingSecondsFromOffset(4));
    try std.testing.expectEqual(@as(usize, 2), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputChannelCount());
    try std.testing.expect(!context.inputChannelsEmpty());
    try std.testing.expect(!context.outputChannelsEmpty());
    try std.testing.expect(context.hasInputChannels());
    try std.testing.expect(context.hasOutputChannels());
    try std.testing.expectEqual(@as(f64, 0.4), context.inputChannel(1).?[0]);
    try std.testing.expect(context.hasInputChannel(1));
    try std.testing.expect(!context.inputChannelEmpty(1));
    try std.testing.expectEqual(@as(?[]const f64, null), context.inputChannel(2));
    try std.testing.expect(!context.hasInputChannel(2));
    try std.testing.expect(context.inputChannelEmpty(2));
    try std.testing.expectEqual(@as(f64, 0.0), context.outputChannel(1).?[0]);
    try std.testing.expect(context.hasOutputChannel(1));
    try std.testing.expect(!context.outputChannelEmpty(1));
    try std.testing.expectEqual(@as(?[]f64, null), context.outputChannel(2));
    try std.testing.expect(!context.hasOutputChannel(2));
    try std.testing.expect(context.outputChannelEmpty(2));

    context.fillOutputs(0.5);
    try std.testing.expectEqual(@as(f64, 0.5), out_left[0]);
    try std.testing.expectEqual(@as(f64, 0.5), out_right[2]);

    context.clearOutputs();
    try std.testing.expectEqual(@as(f64, 0.0), out_left[0]);
    try std.testing.expectEqual(@as(f64, 0.0), out_right[2]);
}

test "process context rejects side-to-side frame count mismatch" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};

    try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).init(48_000.0, &input_channels, &output_channels));
}

test "process context reports frame count for input-only and output-only processors" {
    const input = [_]f32{ 0.1, 0.2, 0.3 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const no_input_channels = [_][]const f32{};
    const no_output_channels = [_][]f32{};

    const output_only = try ProcessContext(f32).init(48_000.0, &no_input_channels, &output_channels);
    try std.testing.expectEqual(@as(usize, 4), output_only.frameCount());
    try std.testing.expectEqual(@as(usize, 0), output_only.inputFrameCount());
    try std.testing.expectEqual(@as(usize, 4), output_only.outputFrameCount());
    try std.testing.expectEqual(@as(usize, 0), output_only.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 1), output_only.outputChannelCount());
    try std.testing.expect(output_only.inputChannelsEmpty());
    try std.testing.expect(!output_only.outputChannelsEmpty());
    try std.testing.expect(!output_only.hasInputChannels());
    try std.testing.expect(output_only.hasOutputChannels());

    const input_only = try ProcessContext(f32).init(48_000.0, &input_channels, &no_output_channels);
    try std.testing.expectEqual(@as(usize, 3), input_only.frameCount());
    try std.testing.expectEqual(@as(usize, 3), input_only.inputFrameCount());
    try std.testing.expectEqual(@as(usize, 0), input_only.outputFrameCount());
    try std.testing.expectEqual(@as(usize, 1), input_only.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 0), input_only.outputChannelCount());
    try std.testing.expect(!input_only.inputChannelsEmpty());
    try std.testing.expect(input_only.outputChannelsEmpty());
    try std.testing.expect(input_only.hasInputChannels());
    try std.testing.expect(!input_only.hasOutputChannels());
}

test "process context validates attachments for input-only and output-only processors" {
    const input = [_]f32{ 0.1, 0.2, 0.3 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const no_input_channels = [_][]const f32{};
    const no_output_channels = [_][]f32{};
    const output_changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 3, .normalized = 0.75 },
    };
    const input_changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 2, .normalized = 0.5 },
    };
    const output_events = [_]Event{
        Event.noteOn(3, 0, 60, 1.0),
    };
    const input_events = [_]Event{
        Event.noteOn(2, 0, 60, 1.0),
    };
    var output_storage: [1]Event = undefined;
    var output_writer = EventWriter.init(&output_storage, output.len);
    var input_storage: [1]Event = undefined;
    var input_writer = EventWriter.init(&input_storage, input.len);

    const output_only = try ProcessContext(f32).initWith(48_000.0, &no_input_channels, &output_channels, .{
        .parameter_changes = &output_changes,
        .events = &output_events,
        .output_events = &output_writer,
    });
    try std.testing.expectEqual(@as(usize, output.len), output_only.frameCount());
    try std.testing.expectEqual(@as(?usize, 3), output_only.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 3), output_only.latestEventOffset());
    try std.testing.expect(output_only.hasOutputEventWriter());

    const input_only = try ProcessContext(f32).initWith(48_000.0, &input_channels, &no_output_channels, .{
        .parameter_changes = &input_changes,
        .events = &input_events,
        .output_events = &input_writer,
    });
    try std.testing.expectEqual(@as(usize, input.len), input_only.frameCount());
    try std.testing.expectEqual(@as(?usize, 2), input_only.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 2), input_only.latestEventOffset());
    try std.testing.expect(input_only.hasOutputEventWriter());
}

test "process context rejects invalid sample rates" {
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};

    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(0.0, &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(-48_000.0, &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(std.math.inf(f64), &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(std.math.nan(f64), &input_channels, &output_channels));
}

test "process context validates attached parameter changes and events" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 1, .normalized = 0.5 },
    };
    const events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
    };
    var storage: [1]Event = undefined;
    var writer = EventWriter.init(&storage, input.len);
    const context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
        .events = &events,
        .output_events = &writer,
    });

    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(usize, 1), context.parameterChangeCount());
    try std.testing.expect(!context.parameterChangesEmpty());
    try std.testing.expect(context.hasParameterChanges());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffsetForId(1));
    try std.testing.expectEqual(@as(?usize, 1), context.latestParameterChangeOffsetForId(1));
    try std.testing.expectEqual(@as(?usize, null), context.firstParameterChangeOffsetForId(2));
    try std.testing.expectEqual(@as(?usize, null), context.latestParameterChangeOffsetForId(2));
    try std.testing.expectEqual(changes[0], context.firstAnyParameterChange().?);
    try std.testing.expectEqual(changes[0], context.latestAnyParameterChange().?);
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstAnyParameterNormalized());
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestAnyParameterNormalized());
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterChangeAtOffset(1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeAtOffset(1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterChangeForIdAtOffset(1, 1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeForIdAtOffset(1, 1).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), context.firstParameterChangeAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), context.latestParameterChangeAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), context.firstParameterChangeForIdAtOffset(2, 1));
    try std.testing.expectEqual(@as(?ParameterChange, null), context.latestParameterChangeForIdAtOffset(2, 1));
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChanges(1));
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChangesAtOffset(1));
    try std.testing.expectEqual(@as(usize, 0), context.countParameterChangesAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChangesForIdAtOffset(1, 1));
    try std.testing.expectEqual(@as(usize, 0), context.countParameterChangesForIdAtOffset(1, 0));
    try std.testing.expect(context.hasParameterChange(1));
    try std.testing.expect(!context.hasParameterChange(2));
    try std.testing.expect(context.hasParameterChangeAtOffset(1));
    try std.testing.expect(!context.hasParameterChangeAtOffset(0));
    try std.testing.expect(context.hasParameterChangeForIdAtOffset(1, 1));
    try std.testing.expect(!context.hasParameterChangeForIdAtOffset(2, 1));
    try std.testing.expect(!context.parameterChangesForIdEmpty(1));
    try std.testing.expect(context.parameterChangesForIdEmpty(2));
    try std.testing.expect(!context.parameterChangesAtOffsetEmpty(1));
    try std.testing.expect(context.parameterChangesAtOffsetEmpty(0));
    try std.testing.expect(!context.parameterChangesForIdAtOffsetEmpty(1, 1));
    try std.testing.expect(context.parameterChangesForIdAtOffsetEmpty(2, 1));
    try std.testing.expect(context.onlyParameterChangesForId(1));
    try std.testing.expect(!context.onlyParameterChangesForId(2));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalized(1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalized(1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalizedForIdAtOffset(1, 1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalizedForIdAtOffset(1, 1));
    try std.testing.expectEqual(@as(?f64, null), context.firstParameterNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), context.latestParameterNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), context.firstParameterNormalizedForIdAtOffset(2, 1));
    try std.testing.expectEqual(@as(?f64, null), context.latestParameterNormalizedForIdAtOffset(2, 1));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedAtOffsetOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.firstParameterNormalizedAtOffsetOr(0, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterNormalizedAtOffsetOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedAtOffsetOr(0, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedForIdAtOffsetOr(1, 1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.firstParameterNormalizedForIdAtOffsetOr(2, 1, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterNormalizedForIdAtOffsetOr(1, 1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedForIdAtOffsetOr(2, 1, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.firstParameterNormalizedOr(2, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterNormalizedOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedOr(2, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeAtOrBefore(1, 1).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), context.latestParameterChangeAtOrBefore(1, 0));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalizedAtOrBefore(1, 1));
    try std.testing.expectEqual(@as(?f64, null), context.latestParameterNormalizedAtOrBefore(1, 0));
    try std.testing.expectEqual(@as(f64, 0.5), context.parameterNormalizedAtOrBeforeOr(1, 1, 0.0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextParameterChangeOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffsetForId(1, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextParameterChangeOffsetForId(2, 0));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.25 }, context.parameterSegmentAt(1, 0, 0.25).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 2, .normalized = 0.5 }, context.parameterSegmentAt(1, 1, 0.25).?);
    var parameter_segments = context.parameterSegments(1, 0.25);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.25 }, parameter_segments.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 2, .normalized = 0.5 }, parameter_segments.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), parameter_segments.next());
    var block_segments = context.parameterBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, block_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, block_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), block_segments.next());
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try std.testing.expect(!context.inputEventsEmpty());
    try std.testing.expect(context.hasInputEvents());
    try std.testing.expectEqual(@as(usize, 1), context.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), context.countNoteReleases());
    try std.testing.expect(context.hasNoteAttacks());
    try std.testing.expect(!context.hasNoteReleases());
    try std.testing.expect(!context.noteAttacksEmpty());
    try std.testing.expect(context.noteReleasesEmpty());
    try std.testing.expect(context.onlyInputNoteAttacks());
    try std.testing.expect(!context.onlyInputNoteReleases());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffset());
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEvent().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEvent().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstInputEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), context.latestInputEventAtOffset(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffsetForBus(1));
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffsetForChannel(1));
    try std.testing.expect(context.hasEvent(.note_on));
    try std.testing.expect(!context.hasEvent(.note_off));
    try std.testing.expect(!context.eventsOfKindEmpty(.note_on));
    try std.testing.expect(context.eventsOfKindEmpty(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsAtOffset(1));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForBus(1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForChannel(1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForBusChannel(1, 0));
    try std.testing.expect(context.hasEventsForBus(0));
    try std.testing.expect(!context.hasEventsForBus(1));
    try std.testing.expect(!context.eventsForBusEmpty(0));
    try std.testing.expect(context.eventsForBusEmpty(1));
    try std.testing.expect(context.hasEventsForChannel(0));
    try std.testing.expect(!context.hasEventsForChannel(1));
    try std.testing.expect(context.hasEventsForBusChannel(0, 0));
    try std.testing.expect(!context.hasEventsForBusChannel(0, 1));
    try std.testing.expect(context.hasEventAtOffset(1));
    try std.testing.expect(!context.hasEventAtOffset(0));
    try std.testing.expect(context.hasEventOfKindAtOffset(.note_on, 1));
    try std.testing.expect(!context.hasEventOfKindAtOffset(.note_off, 1));
    try std.testing.expect(!context.eventsForChannelEmpty(0));
    try std.testing.expect(context.eventsForChannelEmpty(1));
    try std.testing.expect(!context.eventsForBusChannelEmpty(0, 0));
    try std.testing.expect(context.eventsForBusChannelEmpty(1, 0));
    try std.testing.expect(!context.eventsAtOffsetEmpty(1));
    try std.testing.expect(context.eventsAtOffsetEmpty(0));
    try std.testing.expect(!context.eventsOfKindAtOffsetEmpty(.note_on, 1));
    try std.testing.expect(context.eventsOfKindAtOffsetEmpty(.note_off, 1));
    try std.testing.expect(context.onlyInputEventsAtOffset(1));
    try std.testing.expect(!context.onlyInputEventsAtOffset(0));
    try std.testing.expect(context.onlyInputEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expect(!context.onlyInputEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expect(context.onlyInputEventsOfKind(.note_on));
    try std.testing.expect(context.onlyInputEventsForBus(0));
    try std.testing.expect(context.onlyInputEventsForChannel(0));
    try std.testing.expect(context.onlyInputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.onlyInputEventsForBusChannel(0, 1));
    try std.testing.expect(!context.onlyInputEventsForChannel(1));
    try std.testing.expectEqual(@as(i16, 60), context.firstEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEventOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(?Event, null), context.latestEventOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(?Event, null), context.firstEvent(.note_off));
    try std.testing.expectEqual(@as(?Event, null), context.latestEvent(.note_off));
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEventForBus(1));
    try std.testing.expectEqual(@as(?Event, null), context.latestEventForChannel(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForKind(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForBus(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForChannel(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForBusChannel(0, 0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForBusChannel(0, 1, 0));
    var note_events = context.inputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), note_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), note_events.next());
    var offset_events = context.inputEventsAtOffset(1);
    try std.testing.expectEqual(EventKind.note_on, offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());
    var event_segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, event_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, event_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), event_segments.next());
    var process_segments = context.processBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, process_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, process_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), process_segments.next());
    try std.testing.expect(context.hasOutputEventWriter());
}

test "process context rejects attached changes outside frame count" {
    const input = [_]f32{0.1};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 1, .normalized = 0.5 },
    };
    const events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
    };
    var context = try ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectError(error.ParameterChangeOutsideBlock, context.setParameterChanges(&changes));
    try std.testing.expectError(error.EventOutsideBlock, context.setEvents(&events));
    try std.testing.expectError(error.ParameterChangeOutsideBlock, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .parameter_changes = &changes },
    ));
    try std.testing.expectError(error.EventOutsideBlock, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .events = &events },
    ));

    var output_storage: [1]Event = undefined;
    var mismatched_writer = EventWriter.init(&output_storage, 2);
    try std.testing.expectError(error.MismatchedFrameCount, context.setOutputEvents(&mismatched_writer));
    try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .output_events = &mismatched_writer },
    ));
}

test "parameter changes validate block offsets and normalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(usize, 3), view.changeCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expect(changes[0].isForId(7));
    try std.testing.expect(!changes[0].isForId(8));
    try std.testing.expect(changes[0].isAtOffset(0));
    try std.testing.expect(!changes[0].isAtOffset(1));
    try std.testing.expect(changes[0].isForIdAtOffset(7, 0));
    try std.testing.expect(!changes[0].isForIdAtOffset(7, 1));
    try std.testing.expect(!changes[0].isForIdAtOffset(8, 0));
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(changes[0], view.firstChange().?);
    try std.testing.expectEqual(changes[1], view.latestChange().?);
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstAnyNormalized());
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestAnyNormalized());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, 2), view.firstSampleOffsetForId(8));
    try std.testing.expectEqual(@as(?usize, 2), view.latestSampleOffsetForId(8));
    try std.testing.expectEqual(@as(?usize, null), view.firstSampleOffsetForId(9));
    try std.testing.expectEqual(@as(?usize, null), view.latestSampleOffsetForId(9));
    try std.testing.expect(view.has(7));
    try std.testing.expect(!view.has(9));
    try std.testing.expect(!view.empty(7));
    try std.testing.expect(view.empty(9));
    try std.testing.expectEqual(@as(usize, 2), view.count(7));
    try std.testing.expectEqual(@as(usize, 1), view.count(8));
    try std.testing.expectEqual(@as(usize, 0), view.count(9));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(2));
    try std.testing.expectEqual(@as(usize, 0), view.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), view.countForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(usize, 0), view.countForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstAtOffset(0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestAtOffset(2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.firstForIdAtOffset(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestForIdAtOffset(7, 0).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstAtOffset(1));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOffset(1));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestForIdAtOffset(7, 2));
    try std.testing.expect(view.hasAtOffset(0));
    try std.testing.expect(!view.hasAtOffset(1));
    try std.testing.expect(view.hasForIdAtOffset(7, 0));
    try std.testing.expect(!view.hasForIdAtOffset(8, 0));
    try std.testing.expect(!view.offsetEmpty(0));
    try std.testing.expect(view.offsetEmpty(1));
    try std.testing.expect(!view.idAtOffsetEmpty(7, 0));
    try std.testing.expect(view.idAtOffsetEmpty(8, 0));
    try std.testing.expect(!view.only(7));
    const gain_only_changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
    };
    const gain_only = try ParameterChanges.init(&gain_only_changes, 4);
    try std.testing.expect(gain_only.only(7));
    try std.testing.expect(!gain_only.only(8));
    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(f64, 0.75), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.75), view.latestNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedAtOffset(2));
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalizedForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedAtOffsetOr(0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedAtOffsetOr(1, 0.5));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedAtOffsetOr(2, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedAtOffsetOr(1, 0.5));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedForIdAtOffsetOr(7, 0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedForIdAtOffsetOr(7, 2, 0.5));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestNormalizedForIdAtOffsetOr(7, 0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedForIdAtOffsetOr(7, 2, 0.5));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalized(9));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalized(9));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latest(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.latestAtOrBefore(7, 3).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.normalizedAtOrBeforeOr(7, 2, 0.0));
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalizedAtOrBefore(7, 3));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(f64, 0.5), view.normalizedAtOrBeforeOr(8, 1, 0.5));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffsetForId(7, 0));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(7, 3));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(9, 0));
    const first_segment = view.segmentAt(7, 0, 4, 1.0).?;
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 3, .normalized = 0.25 }, first_segment);
    try std.testing.expectEqual(@as(usize, 3), first_segment.frameCount());
    try std.testing.expect(!first_segment.isEmpty());
    try std.testing.expect(first_segment.contains(2));
    try std.testing.expect(!first_segment.contains(3));
    try std.testing.expect(first_segment.startsAt(0));
    try std.testing.expect(!first_segment.startsAt(1));
    try std.testing.expect(first_segment.endsAt(3));
    try std.testing.expect(!first_segment.endsAt(2));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 3, .end_offset = 4, .normalized = 0.75 }, view.segmentAt(7, 3, 4, 1.0).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 2, .normalized = 0.5 }, view.segmentAt(8, 0, 4, 0.5).?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), view.segmentAt(7, 4, 4, 1.0));
    try std.testing.expect((ParameterSegment{ .start_offset = 2, .end_offset = 2, .normalized = 0.0 }).isEmpty());
    try std.testing.expectEqual(@as(usize, 0), (ParameterChanges{}).changeCount());
    try std.testing.expect((ParameterChanges{}).isEmpty());
    try std.testing.expect(!(ParameterChanges{}).hasChanges());
    try std.testing.expect((ParameterChanges{}).empty(7));
    try std.testing.expect(!(ParameterChanges{}).only(7));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstChange());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestChange());
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstAnyNormalized());
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestAnyNormalized());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffset());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestNormalizedForIdAtOffset(7, 0));
}

test "parameter changes query by sample offset without requiring sorted input" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);

    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.firstAtOffset(5).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestAtOffset(5).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.firstForIdAtOffset(7, 5).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestForIdAtOffset(7, 5).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstForIdAtOffset(8, 5));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestForIdAtOffset(8, 5));
    try std.testing.expectEqual(@as(?f64, 0.75), view.firstNormalizedForIdAtOffset(7, 5));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedForIdAtOffset(7, 5));
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 4));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedAtOrBefore(7, 5));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffsetForId(7, 1));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, view.segmentAt(7, 1, 8, 0.0).?);
}

test "parameter changes iterate stable automation segments without allocation" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.segments(7, 8, 0.0);

    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.0 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 5, .end_offset = 8, .normalized = 0.75 }, iterator.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), iterator.next());
}

test "parameter changes collapse same-offset values into one segment" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 4, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.segments(7, 8, 0.0);

    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.0 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 4, .normalized = 0.75 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 4, .end_offset = 8, .normalized = 1.0 }, iterator.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), iterator.next());
}

test "parameter changes iterate block segments split at change offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 9, .sample_offset = 3, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.blockSegments(8);

    const first_segment = iterator.next().?;
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, first_segment);
    try std.testing.expectEqual(@as(usize, 1), first_segment.frameCount());
    try std.testing.expect(!first_segment.isEmpty());
    try std.testing.expect(first_segment.contains(0));
    try std.testing.expect(!first_segment.contains(1));
    try std.testing.expect(first_segment.startsAt(0));
    try std.testing.expect(!first_segment.startsAt(1));
    try std.testing.expect(first_segment.endsAt(1));
    try std.testing.expect(!first_segment.endsAt(0));
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
    try std.testing.expect((BlockSegment{ .start_offset = 2, .end_offset = 2 }).isEmpty());

    var empty = (ParameterChanges{}).blockSegments(4);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = view.blockSegments(0);
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "parameter changes block segments ignore duplicate offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.5 },
        .{ .id = 9, .sample_offset = 3, .normalized = 0.75 },
    };
    const view = try ParameterChanges.init(&changes, 5);
    var iterator = view.blockSegments(5);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
}

test "parameter changes reject values outside the process block" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 4, .normalized = 0.25 },
    };

    try std.testing.expectError(error.ParameterChangeOutsideBlock, ParameterChanges.init(&changes, 4));
}

test "parameter changes reject denormalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 1.5 },
    };
    const infinite = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = std.math.inf(f64) },
    };

    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&changes, 4));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&infinite, 4));
}

test "parameter changes clamp defaulted normalized reads" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 2, .normalized = 0.5 },
    };
    const view = try ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(f64, 1.0), view.firstNormalizedOr(9, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.latestNormalizedOr(9, -0.25));
    try std.testing.expectEqual(@as(f64, 0.0), view.firstNormalizedAtOffsetOr(1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedAtOffsetOr(1, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.firstNormalizedForIdAtOffsetOr(7, 1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedForIdAtOffsetOr(7, 1, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.normalizedAtOrBeforeOr(7, 1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.5), view.normalizedAtOrBeforeOr(7, 2, 1.5));

    var segments = view.segments(9, 4, 1.5);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 4, .normalized = 1.0 }, segments.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), segments.next());
}

test "events validate block offsets and count kinds" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 0.75),
        Event.midiCc(1, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.pitchBend(3, 0, 1.0),
        Event.aftertouch(3, 0, 60, 0.25),
        Event.noteExpressionValue(3, 42, 5, 0.5),
        Event.noteExpressionInt(3, 42, 5, 7),
        Event.noteExpressionText(3, 42, 5),
        Event.dataEvent(3, 1, &.{ 0x01, 0x02 }),
        Event.other(3),
    };
    const view = try Events.init(&items, 4);

    try std.testing.expectEqual(@as(usize, 10), view.eventCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expect(view.hasEvents());
    try std.testing.expect(items[0].isKind(.note_on));
    try std.testing.expect(!items[0].isKind(.note_off));
    try std.testing.expect(items[0].isAtOffset(0));
    try std.testing.expect(!items[0].isAtOffset(1));
    try std.testing.expect(items[0].isKindAtOffset(.note_on, 0));
    try std.testing.expect(!items[0].isKindAtOffset(.note_on, 1));
    try std.testing.expect(!items[0].isKindAtOffset(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 3), view.firstSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, 0), view.latestSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), view.firstSampleOffsetForKind(.other));
    try std.testing.expectEqual(EventKind.note_off, view.firstAtOffset(3).?.kind);
    try std.testing.expectEqual(EventKind.other, view.latestAtOffset(3).?.kind);
    try std.testing.expectEqual(@as(?Event, null), view.firstAtOffset(2));
    try std.testing.expectEqual(@as(?Event, null), view.latestAtOffset(2));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_off));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.data));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.other));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(0));
    try std.testing.expectEqual(@as(usize, 8), view.countAtOffset(3));
    try std.testing.expectEqual(@as(usize, 0), view.countAtOffset(2));
    try std.testing.expectEqual(@as(usize, 1), view.countKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(usize, 0), view.countKindAtOffset(.note_on, 3));
    try std.testing.expect(view.hasKind(.note_on));
    try std.testing.expect(view.hasAtOffset(3));
    try std.testing.expect(!view.hasAtOffset(2));
    try std.testing.expect(view.hasKindAtOffset(.note_on, 0));
    try std.testing.expect(!view.hasKindAtOffset(.note_on, 3));
    try std.testing.expect(!view.kindEmpty(.note_on));
    try std.testing.expect(!view.offsetEmpty(3));
    try std.testing.expect(view.offsetEmpty(2));
    try std.testing.expect(!view.kindAtOffsetEmpty(.note_on, 0));
    try std.testing.expect(view.kindAtOffsetEmpty(.note_on, 3));
    try std.testing.expect(!view.busEmpty(0));
    try std.testing.expect(view.busEmpty(1));
    try std.testing.expect(!view.channelEmpty(0));
    try std.testing.expect(view.channelEmpty(1));
    try std.testing.expectEqual(@as(i16, 60), view.firstKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(usize, 0), view.latestKind(.note_on).?.sample_offset);
    try std.testing.expectEqual(EventKind.note_off, view.firstKindAtOffset(.note_off, 3).?.kind);
    try std.testing.expectEqual(EventKind.note_off, view.latestKindAtOffset(.note_off, 3).?.kind);
    try std.testing.expectEqual(@as(?Event, null), view.firstKindAtOffset(.note_on, 3));
    try std.testing.expectEqual(@as(?Event, null), view.latestKindAtOffset(.note_on, 3));
    try std.testing.expect(view.hasKind(.data));
    try std.testing.expect(!view.onlyKind(.note_on));
    try std.testing.expect(!view.onlyBus(0));
    try std.testing.expect(!view.onlyChannel(0));
    const note_only_items = [_]Event{
        Event.noteOn(0, 0, 60, 0.75),
        Event.noteOn(1, 0, 67, 0.5),
    };
    const note_only = try Events.init(&note_only_items, 4);
    try std.testing.expect(note_only.onlyKind(.note_on));
    try std.testing.expect(note_only.kindEmpty(.note_off));
    try std.testing.expect(note_only.onlyBus(0));
    try std.testing.expect(note_only.onlyChannel(0));
    try std.testing.expect(!note_only.onlyChannel(1));
    try std.testing.expectEqual(@as(usize, 0), (Events{}).eventCount());
    try std.testing.expect((Events{}).isEmpty());
    try std.testing.expect(!(Events{}).hasEvents());
    try std.testing.expect((Events{}).kindEmpty(.note_on));
    try std.testing.expect((Events{}).busEmpty(0));
    try std.testing.expect((Events{}).channelEmpty(0));
    try std.testing.expect(!(Events{}).onlyKind(.note_on));
    try std.testing.expect(!(Events{}).onlyBus(0));
    try std.testing.expect(!(Events{}).onlyChannel(0));
    try std.testing.expectEqual(@as(?usize, null), (Events{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), (Events{}).latestSampleOffset());
    try std.testing.expectEqual(@as(?Event, null), (Events{}).firstAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).latestAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).firstKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).latestKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).firstKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).latestKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, 1), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
    var offset_events = view.atOffset(3);
    try std.testing.expectEqual(EventKind.note_off, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.pitch_bend, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.aftertouch, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_value, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_int, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_text, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.data, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.other, offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());
}

test "events iterate block segments split at event offsets" {
    const items = [_]Event{
        Event.noteOn(5, 0, 60, 1.0),
        Event.midiCc(1, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.pitchBend(5, 0, 0.25),
    };
    const view = try Events.init(&items, 8);
    var iterator = view.blockSegments(8);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());

    var empty = (Events{}).blockSegments(4);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = view.blockSegments(0);
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "events block segments ignore duplicate offsets" {
    const items = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
        Event.midiCc(1, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
    };
    const view = try Events.init(&items, 5);
    var iterator = view.blockSegments(5);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
}

test "process block segments split at parameter and event offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 2, .normalized = 0.25 },
    };
    const events = [_]Event{
        Event.noteOn(3, 0, 60, 1.0),
        Event.noteOff(5, 0, 60, 0.0),
    };
    const parameter_changes = try ParameterChanges.init(&changes, 8);
    const input_events = try Events.init(&events, 8);
    var iterator = ProcessBlockSegmentIterator{
        .parameter_changes = parameter_changes,
        .events = input_events,
        .frame_count = 8,
    };

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 2 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 2, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());

    var empty = ProcessBlockSegmentIterator{ .parameter_changes = .{}, .events = .{}, .frame_count = 4 };
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = ProcessBlockSegmentIterator{ .parameter_changes = parameter_changes, .events = input_events, .frame_count = 0 };
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "process block segments ignore duplicate parameter and event offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
    };
    const events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
        Event.midiCc(3, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
    };
    const parameter_changes = try ParameterChanges.init(&changes, 5);
    const input_events = try Events.init(&events, 5);
    var iterator = ProcessBlockSegmentIterator{
        .parameter_changes = parameter_changes,
        .events = input_events,
        .frame_count = 5,
    };

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
}

test "events query by sample offset without requiring sorted input" {
    const items = [_]Event{
        Event.noteOn(5, 0, 67, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.noteOn(1, 0, 60, 1.0),
        Event.noteOn(5, 0, 72, 0.25),
        Event.noteOn(2, 1, 64, 0.75).withBusIndex(1),
        Event.noteOff(6, 1, 64, 0.0).withBusIndex(1),
    };
    const view = try Events.init(&items, 8);

    try std.testing.expectEqual(@as(usize, 1), view.first().?.sample_offset);
    try std.testing.expectEqual(EventKind.note_on, view.first().?.kind);
    try std.testing.expectEqual(@as(i16, 60), view.first().?.pitch);
    try std.testing.expectEqual(@as(usize, 6), view.latest().?.sample_offset);
    try std.testing.expectEqual(EventKind.note_off, view.latest().?.kind);
    try std.testing.expectEqual(@as(i16, 64), view.latest().?.pitch);
    try std.testing.expectEqual(@as(usize, 1), view.firstKind(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 60), view.firstKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(usize, 5), view.latestKind(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 72), view.latestKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), view.firstAtOffset(5).?.pitch);
    try std.testing.expectEqual(@as(i16, 72), view.latestAtOffset(5).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), view.firstKindAtOffset(.note_on, 5).?.pitch);
    try std.testing.expectEqual(@as(i16, 72), view.latestKindAtOffset(.note_on, 5).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), view.firstKindAtOffset(.note_off, 5));
    try std.testing.expectEqual(@as(?Event, null), view.latestKindAtOffset(.note_off, 5));
    try std.testing.expect(!view.onlyAtOffset(5));
    try std.testing.expect(!view.onlyKindAtOffset(.note_on, 5));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffsetForKind(.note_on, 1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForKind(.note_off, 3));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForBus(1, 1));
    try std.testing.expectEqual(@as(?usize, 6), view.nextSampleOffsetForBus(1, 2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForBus(1, 6));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForChannel(1, 1));
    try std.testing.expectEqual(@as(?usize, 6), view.nextSampleOffsetForChannel(1, 2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForChannel(1, 6));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForBusChannel(1, 1, 1));
    try std.testing.expectEqual(@as(?usize, 6), view.nextSampleOffsetForBusChannel(1, 1, 2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForBusChannel(1, 0, 1));
    try std.testing.expectEqual(@as(usize, 4), view.countBus(0));
    try std.testing.expectEqual(@as(usize, 2), view.countBus(1));
    try std.testing.expectEqual(@as(usize, 4), view.countChannel(0));
    try std.testing.expectEqual(@as(usize, 2), view.countChannel(1));
    try std.testing.expect(view.hasBus(0));
    try std.testing.expect(view.hasBus(1));
    try std.testing.expect(view.hasChannel(0));
    try std.testing.expect(view.hasChannel(1));
    try std.testing.expectEqual(@as(?usize, 2), view.firstSampleOffsetForBus(1));
    try std.testing.expectEqual(@as(?usize, 6), view.latestSampleOffsetForBus(1));
    try std.testing.expectEqual(@as(?usize, 2), view.firstSampleOffsetForChannel(1));
    try std.testing.expectEqual(@as(?usize, 6), view.latestSampleOffsetForChannel(1));
    try std.testing.expectEqual(@as(?usize, 2), view.firstSampleOffsetForBusChannel(1, 1));
    try std.testing.expectEqual(@as(?usize, 6), view.latestSampleOffsetForBusChannel(1, 1));
    try std.testing.expectEqual(@as(i16, 64), view.firstBus(1).?.pitch);
    try std.testing.expectEqual(EventKind.note_off, view.latestBus(1).?.kind);
    try std.testing.expectEqual(@as(i16, 64), view.firstChannel(1).?.pitch);
    try std.testing.expectEqual(EventKind.note_off, view.latestChannel(1).?.kind);
    try std.testing.expectEqual(@as(i16, 64), view.firstBusChannel(1, 1).?.pitch);
    try std.testing.expectEqual(EventKind.note_off, view.latestBusChannel(1, 1).?.kind);
    try std.testing.expectEqual(@as(?Event, null), view.firstBus(2));
    try std.testing.expectEqual(@as(?Event, null), view.latestChannel(2));
    var note_ons = view.ofKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(i16, 64), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(i16, 67), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(i16, 72), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), note_ons.next());

    const same_offset_items = [_]Event{
        Event.noteOn(2, 0, 60, 1.0),
        Event.noteOn(2, 0, 64, 0.5),
    };
    const same_offset_view = try Events.init(&same_offset_items, 8);
    try std.testing.expect(same_offset_view.onlyAtOffset(2));
    try std.testing.expect(!same_offset_view.onlyAtOffset(3));
    try std.testing.expect(same_offset_view.onlyKindAtOffset(.note_on, 2));
    try std.testing.expect(!same_offset_view.onlyKindAtOffset(.note_off, 2));
}

test "event constructors can target non-main buses" {
    const event = Event.noteOn(1, 0, 60, 0.75).withBusIndex(2);

    try std.testing.expectEqual(EventKind.note_on, event.kind);
    try std.testing.expectEqual(@as(i32, 2), event.bus_index);
    try std.testing.expectEqual(@as(usize, 1), event.sample_offset);
    try std.testing.expectEqual(@as(i16, 60), event.pitch);
}

test "event note helpers classify attacks and releases" {
    const attack = Event.noteOn(0, 1, 60, 0.75);
    const zero_velocity_release = Event.noteOn(1, 1, 60, 0.0);
    const release = Event.noteOff(2, 1, 60, 0.0);
    const cc = Event.midiCc(3, 1, 64, 1.0);

    try std.testing.expect(attack.isNoteAttack());
    try std.testing.expect(!attack.isNoteRelease());
    try std.testing.expectEqual(NoteLifecycle.attack, attack.noteLifecycle());
    try std.testing.expect(attack.isNoteForPitch(60));
    try std.testing.expect(!attack.isNoteForPitch(61));
    try std.testing.expectEqual(NoteOn{
        .bus_index = 0,
        .sample_offset = 0,
        .channel = 1,
        .pitch = 60,
        .velocity = 0.75,
    }, attack.asNoteAttack().?);
    try std.testing.expectEqual(@as(?NoteOff, null), attack.asNoteRelease());

    try std.testing.expect(!zero_velocity_release.isNoteAttack());
    try std.testing.expect(zero_velocity_release.isNoteRelease());
    try std.testing.expectEqual(NoteLifecycle.release, zero_velocity_release.noteLifecycle());
    try std.testing.expect(zero_velocity_release.isNoteForPitch(60));
    try std.testing.expectEqual(@as(?NoteOn, null), zero_velocity_release.asNoteAttack());
    try std.testing.expectEqual(NoteOff{
        .bus_index = 0,
        .sample_offset = 1,
        .channel = 1,
        .pitch = 60,
        .velocity = 0.0,
    }, zero_velocity_release.asNoteRelease().?);

    try std.testing.expect(!release.isNoteAttack());
    try std.testing.expect(release.isNoteRelease());
    try std.testing.expectEqual(NoteLifecycle.release, release.noteLifecycle());
    try std.testing.expect(release.isNoteForPitch(60));
    try std.testing.expectEqual(@as(?NoteOn, null), release.asNoteAttack());
    try std.testing.expectEqual(NoteOff{
        .bus_index = 0,
        .sample_offset = 2,
        .channel = 1,
        .pitch = 60,
        .velocity = 0.0,
    }, release.asNoteRelease().?);

    try std.testing.expect(!cc.isNoteAttack());
    try std.testing.expect(!cc.isNoteRelease());
    try std.testing.expectEqual(NoteLifecycle.none, cc.noteLifecycle());
    try std.testing.expect(!cc.isNoteForPitch(60));
    try std.testing.expectEqual(@as(?NoteOn, null), cc.asNoteAttack());
    try std.testing.expectEqual(@as(?NoteOff, null), cc.asNoteRelease());
}

test "events count note attacks and releases" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 0.75),
        Event.noteOn(1, 0, 60, 0.0),
        Event.noteOff(2, 0, 60, 0.25),
        Event.midiCc(3, 0, 64, 1.0),
    };
    const view = try Events.init(&items, 4);

    try std.testing.expectEqual(@as(usize, 1), view.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 2), view.countNoteReleases());
    try std.testing.expect(view.hasNoteAttacks());
    try std.testing.expect(view.hasNoteReleases());
    try std.testing.expect(!view.noteAttacksEmpty());
    try std.testing.expect(!view.noteReleasesEmpty());
    try std.testing.expect(!view.onlyNoteAttacks());
    try std.testing.expect(!view.onlyNoteReleases());

    const attacks = try Events.init(&[_]Event{
        Event.noteOn(0, 0, 60, 0.75),
        Event.noteOn(1, 0, 67, 0.5),
    }, 4);
    try std.testing.expect(attacks.onlyNoteAttacks());
    try std.testing.expect(!attacks.onlyNoteReleases());

    const releases = try Events.init(&[_]Event{
        Event.noteOn(0, 0, 60, 0.0),
        Event.noteOff(1, 0, 67, 0.25),
    }, 4);
    try std.testing.expect(releases.onlyNoteReleases());
    try std.testing.expect(!releases.onlyNoteAttacks());

    try std.testing.expectEqual(@as(usize, 0), (Events{}).countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), (Events{}).countNoteReleases());
    try std.testing.expect(!((Events{}).hasNoteAttacks()));
    try std.testing.expect(!((Events{}).hasNoteReleases()));
    try std.testing.expect((Events{}).noteAttacksEmpty());
    try std.testing.expect((Events{}).noteReleasesEmpty());
    try std.testing.expect(!((Events{}).onlyNoteAttacks()));
    try std.testing.expect(!((Events{}).onlyNoteReleases()));
}

test "event category helpers classify routable event groups" {
    const note = Event.noteOn(0, 2, 60, 0.75);
    const cc = Event.midiCc(1, 3, 74, 0.5);
    const bend = Event.pitchBend(2, 4, -0.25);
    const pressure = Event.aftertouch(3, 5, 64, 0.4);
    const expression_value = Event.noteExpressionValue(4, 42, 7, 0.8);
    const expression_int = Event.noteExpressionInt(5, 42, 8, 99);
    const expression_text = Event.noteExpressionText(6, 42, 9);
    const data = Event.dataEvent(7, 1, "abc");
    const other = Event.other(8);

    try std.testing.expect(note.isNote());
    try std.testing.expect(!note.isMidi());
    try std.testing.expect(note.hasChannel());
    try std.testing.expect(note.isForChannel(2));
    try std.testing.expect(!note.isForChannel(3));
    try std.testing.expect(note.isForBus(0));
    try std.testing.expect(!note.isForBus(1));
    try std.testing.expect(note.isForBusChannel(0, 2));
    try std.testing.expect(!note.isForBusChannel(0, 3));
    try std.testing.expect(!note.isForBusChannel(1, 2));

    try std.testing.expect(!cc.isNote());
    try std.testing.expect(cc.isMidi());
    try std.testing.expect(cc.hasChannel());
    try std.testing.expect(cc.isForChannel(3));
    try std.testing.expect(bend.isMidi());
    try std.testing.expect(pressure.isMidi());

    try std.testing.expect(expression_value.isNoteExpression());
    try std.testing.expect(expression_int.isNoteExpression());
    try std.testing.expect(expression_text.isNoteExpression());
    try std.testing.expect(!expression_value.hasChannel());
    try std.testing.expect(!expression_value.isForChannel(0));
    try std.testing.expect(!expression_value.isForBusChannel(0, 0));

    try std.testing.expect(data.isData());
    try std.testing.expect(!data.isNoteExpression());
    try std.testing.expect(!data.hasChannel());
    try std.testing.expect(other.isOther());
    try std.testing.expect(!other.isData());
    try std.testing.expect(Event.other(8).withBusIndex(2).isForBus(2));
}

test "events expose typed payload views" {
    const sysex = [_]u8{ 0xf0, 0x7d, 0x00, 0xf7 };
    const note_on = Event.noteOn(1, 2, 60, 0.75).withBusIndex(3);
    const note_off = Event.noteOff(2, 2, 60, 0.25);
    const cc = Event.midiCc(3, 4, 74, 0.5);
    const bend = Event.pitchBend(4, 5, -0.25);
    const pressure = Event.aftertouch(5, 6, 64, 0.4);
    const expression_value = Event.noteExpressionValue(6, 42, 7, 0.8).withBusIndex(2);
    const expression_int = Event.noteExpressionInt(7, 43, 8, 99);
    const expression_text = Event.noteExpressionText(8, 44, 9);
    const data = Event.dataEvent(9, 1, &sysex).withBusIndex(4);
    const other = Event.other(10);

    try std.testing.expectEqual(NoteOn{
        .bus_index = 3,
        .sample_offset = 1,
        .channel = 2,
        .pitch = 60,
        .velocity = 0.75,
    }, note_on.asNoteOn().?);
    try std.testing.expectEqual(NoteOn{
        .bus_index = 3,
        .sample_offset = 1,
        .channel = 2,
        .pitch = 60,
        .velocity = 0.75,
    }, note_on.asNoteAttack().?);
    try std.testing.expectEqual(NoteOff{
        .bus_index = 0,
        .sample_offset = 2,
        .channel = 2,
        .pitch = 60,
        .velocity = 0.25,
    }, note_off.asNoteOff().?);
    try std.testing.expectEqual(NoteOff{
        .bus_index = 0,
        .sample_offset = 2,
        .channel = 2,
        .pitch = 60,
        .velocity = 0.25,
    }, note_off.asNoteRelease().?);
    try std.testing.expectEqual(MidiCC{
        .bus_index = 0,
        .sample_offset = 3,
        .channel = 4,
        .control_number = 74,
        .value = 0.5,
    }, cc.asMidiCC().?);
    try std.testing.expectEqual(PitchBend{
        .bus_index = 0,
        .sample_offset = 4,
        .channel = 5,
        .value = -0.25,
    }, bend.asPitchBend().?);
    try std.testing.expectEqual(Aftertouch{
        .bus_index = 0,
        .sample_offset = 5,
        .channel = 6,
        .pitch = 64,
        .value = 0.4,
    }, pressure.asAftertouch().?);
    try std.testing.expectEqual(NoteExpressionValue{
        .bus_index = 2,
        .sample_offset = 6,
        .note_id = 42,
        .expression_type_id = 7,
        .value = 0.8,
    }, expression_value.asNoteExpressionValue().?);
    try std.testing.expectEqual(NoteExpressionInt{
        .bus_index = 0,
        .sample_offset = 7,
        .note_id = 43,
        .expression_type_id = 8,
        .value = 99,
    }, expression_int.asNoteExpressionInt().?);
    try std.testing.expectEqual(NoteExpressionText{
        .bus_index = 0,
        .sample_offset = 8,
        .note_id = 44,
        .expression_type_id = 9,
    }, expression_text.asNoteExpressionText().?);
    try std.testing.expectEqual(DataEvent{
        .bus_index = 4,
        .sample_offset = 9,
        .data_type = 1,
        .data = &sysex,
    }, data.asData().?);

    try std.testing.expectEqual(@as(?NoteOn, null), cc.asNoteOn());
    try std.testing.expectEqual(@as(?NoteOn, null), cc.asNoteAttack());
    try std.testing.expectEqual(@as(?NoteOff, null), cc.asNoteRelease());
    try std.testing.expectEqual(@as(?MidiCC, null), note_on.asMidiCC());
    try std.testing.expectEqual(@as(?DataEvent, null), other.asData());
}

test "event constructors can keep legacy MIDI controller numbers" {
    const event = Event.pitchBend(3, 1, 0.25).withControlNumber(129);

    try std.testing.expectEqual(EventKind.pitch_bend, event.kind);
    try std.testing.expectEqual(@as(i16, 129), event.control_number);
    try std.testing.expectEqual(@as(usize, 3), event.sample_offset);
    try std.testing.expectEqual(@as(i16, 1), event.channel);
    try std.testing.expectEqual(@as(f32, 0.25), event.value);
}

test "event constructors can retarget common payload fields" {
    const note = Event.noteOn(1, 0, 60, 0.25)
        .withSampleOffset(3)
        .withChannel(4)
        .withPitch(67)
        .withVelocity(0.75)
        .withBusIndex(2);
    const expression = Event.noteExpressionValue(1, 10, 20, 0.25)
        .withNoteId(11)
        .withExpressionTypeId(21)
        .withValue(0.5)
        .withBusIndex(3);
    const int_expression = Event.noteExpressionInt(2, 12, 22, 99)
        .withNoteId(13)
        .withExpressionTypeId(23)
        .withIntValue(100);
    const data = Event.dataEvent(4, 1, "abc")
        .withDataType(2)
        .withData("def");

    try std.testing.expectEqual(NoteOn{
        .bus_index = 2,
        .sample_offset = 3,
        .channel = 4,
        .pitch = 67,
        .velocity = 0.75,
    }, note.asNoteOn().?);
    try std.testing.expectEqual(NoteExpressionValue{
        .bus_index = 3,
        .sample_offset = 1,
        .note_id = 11,
        .expression_type_id = 21,
        .value = 0.5,
    }, expression.asNoteExpressionValue().?);
    try std.testing.expectEqual(NoteExpressionInt{
        .bus_index = 0,
        .sample_offset = 2,
        .note_id = 13,
        .expression_type_id = 23,
        .value = 100,
    }, int_expression.asNoteExpressionInt().?);
    try std.testing.expectEqual(DataEvent{
        .bus_index = 0,
        .sample_offset = 4,
        .data_type = 2,
        .data = "def",
    }, data.asData().?);
}

test "events reject values outside the process block" {
    const items = [_]Event{
        Event.noteOn(4, 0, 60, 1.0),
    };

    try std.testing.expectError(error.EventOutsideBlock, Events.init(&items, 4));
}

test "events reject invalid normalized values" {
    const too_loud_note = [_]Event{
        Event.noteOn(0, 0, 60, 1.5),
    };
    const nan_cc = [_]Event{
        Event.midiCc(0, 0, 1, std.math.nan(f32)),
    };
    const infinite_aftertouch = [_]Event{
        Event.aftertouch(0, 0, 60, std.math.inf(f32)),
    };
    const wide_bend = [_]Event{
        Event.pitchBend(0, 0, 1.5),
    };
    const infinite_bend = [_]Event{
        Event.pitchBend(0, 0, -std.math.inf(f32)),
    };

    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&too_loud_note, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&nan_cc, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&infinite_aftertouch, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&wide_bend, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&infinite_bend, 4));
}

test "events reject invalid MIDI metadata" {
    const bad_channel = [_]Event{
        Event.noteOn(0, 16, 60, 1.0),
    };
    const bad_pitch = [_]Event{
        Event.noteOff(0, 0, 128, 0.0),
    };
    const bad_control = [_]Event{
        Event.midiCc(0, 0, 128, 0.5),
    };
    const bad_bus = [_]Event{
        Event.pitchBend(0, 0, 0.0).withBusIndex(-1),
    };

    try std.testing.expectError(error.InvalidEventChannel, Events.init(&bad_channel, 4));
    try std.testing.expectError(error.InvalidEventPitch, Events.init(&bad_pitch, 4));
    try std.testing.expectError(error.InvalidEventControlNumber, Events.init(&bad_control, 4));
    try std.testing.expectError(error.InvalidEventBusIndex, Events.init(&bad_bus, 4));
}

test "event writer validates offsets and capacity" {
    var storage: [1]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.hasEvents());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expectEqual(@as(usize, 4), writer.frameCount());
    try std.testing.expect(writer.canAppendEvent(Event.noteOn(0, 0, 60, 1.0)));
    try std.testing.expect(writer.canAppendEvents(try Events.init(&[_]Event{Event.noteOn(0, 0, 60, 1.0)}, 4)));
    try std.testing.expect(!writer.canAppendEvent(Event.noteOn(4, 0, 60, 1.0)));
    try std.testing.expect(!writer.canAppendEvent(Event.midiCc(0, 0, 1, 2.0)));
    try std.testing.expect(!writer.canAppendEvents(try Events.init(&[_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    }, 4)));
    try writer.append(Event.noteOn(0, 0, 60, 1.0));
    try std.testing.expect(!writer.isEmpty());
    try std.testing.expect(writer.hasEvents());
    try std.testing.expect(writer.isFull());
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    try std.testing.expect(writer.canAppend(0));
    try std.testing.expect(!writer.canAppend(1));
    try std.testing.expect(!writer.canAppendEvent(Event.noteOn(1, 0, 60, 1.0)));
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 0), writer.latestSampleOffset());
    try std.testing.expect(writer.hasKind(.note_on));
    try std.testing.expect(!writer.hasKind(.note_off));
    try std.testing.expect(!writer.kindEmpty(.note_on));
    try std.testing.expect(writer.kindEmpty(.note_off));
    try std.testing.expect(writer.hasAtOffset(0));
    try std.testing.expect(!writer.hasAtOffset(1));
    try std.testing.expect(writer.hasKindAtOffset(.note_on, 0));
    try std.testing.expect(!writer.hasKindAtOffset(.note_off, 0));
    try std.testing.expect(!writer.offsetEmpty(0));
    try std.testing.expect(writer.offsetEmpty(1));
    try std.testing.expect(!writer.kindAtOffsetEmpty(.note_on, 0));
    try std.testing.expect(writer.kindAtOffsetEmpty(.note_off, 0));
    try std.testing.expect(!writer.busEmpty(0));
    try std.testing.expect(writer.busEmpty(1));
    try std.testing.expect(!writer.channelEmpty(0));
    try std.testing.expect(writer.channelEmpty(1));
    try std.testing.expect(writer.hasBusChannel(0, 0));
    try std.testing.expect(!writer.hasBusChannel(0, 1));
    try std.testing.expect(!writer.busChannelEmpty(0, 0));
    try std.testing.expect(writer.busChannelEmpty(1, 0));
    try std.testing.expect(writer.onlyKind(.note_on));
    try std.testing.expect(writer.onlyBus(0));
    try std.testing.expect(writer.onlyChannel(0));
    try std.testing.expect(writer.onlyBusChannel(0, 0));
    try std.testing.expect(!writer.onlyBusChannel(0, 1));
    try std.testing.expect(!writer.onlyChannel(1));
    try std.testing.expectEqual(@as(usize, 1), writer.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), writer.countAtOffset(0));
    try std.testing.expectEqual(@as(usize, 0), writer.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), writer.countKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(usize, 0), writer.countKindAtOffset(.note_off, 0));
    try std.testing.expectEqual(EventKind.note_on, writer.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.latestKind(.note_on).?.kind);
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForKind(.note_on, 1));
    try std.testing.expectEqual(@as(usize, 1), writer.countBus(0));
    try std.testing.expectEqual(@as(usize, 0), writer.countBus(1));
    try std.testing.expectEqual(@as(usize, 1), writer.countChannel(0));
    try std.testing.expectEqual(@as(usize, 0), writer.countChannel(1));
    try std.testing.expectEqual(@as(usize, 1), writer.countBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), writer.countBusChannel(1, 0));
    try std.testing.expect(writer.hasBus(0));
    try std.testing.expect(!writer.hasBus(1));
    try std.testing.expect(writer.hasChannel(0));
    try std.testing.expect(!writer.hasChannel(1));
    var written_notes = writer.ofKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), written_notes.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_notes.next());
    try std.testing.expectEqual(@as(usize, 1), writer.capacity());
    try std.testing.expectEqual(@as(usize, 0), writer.remainingCapacity());
    try std.testing.expectEqual(@as(usize, 4), writer.frameCount());
    try std.testing.expectError(error.EventStorageFull, writer.append(Event.noteOff(1, 0, 60, 0.0)));
    try std.testing.expectEqual(@as(usize, 1), writer.clearCount());
    try std.testing.expectEqual(@as(usize, 0), writer.clearCount());
    try writer.append(Event.noteOn(0, 0, 60, 1.0));
    writer.clear();
    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.hasEvents());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expect(writer.canAppend(1));
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), writer.latestSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), writer.latestSampleOffsetForKind(.note_on));
    try std.testing.expect(!writer.hasKind(.note_on));
    try std.testing.expectEqual(@as(usize, 0), writer.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), writer.countNoteReleases());
    try std.testing.expect(!writer.hasNoteAttacks());
    try std.testing.expect(!writer.hasNoteReleases());
    try std.testing.expect(writer.noteAttacksEmpty());
    try std.testing.expect(writer.noteReleasesEmpty());
    try std.testing.expect(writer.kindEmpty(.note_on));
    try std.testing.expect(!writer.hasAtOffset(0));
    try std.testing.expect(writer.offsetEmpty(0));
    try std.testing.expect(!writer.hasKindAtOffset(.note_on, 0));
    try std.testing.expect(writer.kindAtOffsetEmpty(.note_on, 0));
    try std.testing.expect(writer.busEmpty(0));
    try std.testing.expect(writer.channelEmpty(0));
    try std.testing.expect(writer.busChannelEmpty(0, 0));
    try std.testing.expect(!writer.onlyKind(.note_on));
    try std.testing.expect(!writer.onlyNoteAttacks());
    try std.testing.expect(!writer.onlyNoteReleases());
    try std.testing.expect(!writer.onlyBus(0));
    try std.testing.expect(!writer.onlyChannel(0));
    try std.testing.expect(!writer.onlyBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), writer.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 0), writer.countAtOffset(0));
    try std.testing.expectEqual(@as(usize, 0), writer.countKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), writer.firstKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), writer.latestKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffset(0));
    try std.testing.expectEqual(@as(usize, 1), writer.remainingCapacity());

    var empty_storage: [1]Event = undefined;
    var empty_writer = EventWriter.init(&empty_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, empty_writer.append(Event.noteOn(4, 0, 60, 1.0)));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, empty_writer.append(Event.noteOn(0, 0, 60, -0.25)));
}

test "event writer queries written events by offset" {
    var storage: [3]Event = undefined;
    var writer = EventWriter.init(&storage, 8);

    try writer.append(Event.noteOn(5, 0, 67, 0.5));
    try writer.append(Event.noteOff(3, 0, 60, 0.0));
    try writer.append(Event.noteOn(1, 0, 60, 1.0));

    try std.testing.expectEqual(@as(usize, 2), writer.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), writer.countNoteReleases());
    try std.testing.expect(writer.hasNoteAttacks());
    try std.testing.expect(writer.hasNoteReleases());
    try std.testing.expect(!writer.noteAttacksEmpty());
    try std.testing.expect(!writer.noteReleasesEmpty());
    try std.testing.expect(!writer.onlyNoteAttacks());
    try std.testing.expect(!writer.onlyNoteReleases());
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 5), writer.latestSampleOffset());
    try std.testing.expectEqual(EventKind.note_on, writer.first().?.kind);
    try std.testing.expectEqual(@as(i16, 60), writer.first().?.pitch);
    try std.testing.expectEqual(EventKind.note_on, writer.latest().?.kind);
    try std.testing.expectEqual(@as(i16, 67), writer.latest().?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.firstAtOffset(5).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.latestAtOffset(5).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), writer.firstAtOffset(7));
    try std.testing.expectEqual(@as(?Event, null), writer.latestAtOffset(7));
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 5), writer.latestSampleOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 5), writer.latestSampleOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 5), writer.latestSampleOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(i16, 60), writer.firstBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.latestBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), writer.firstChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.latestChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), writer.firstBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.latestBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.firstKindAtOffset(.note_on, 5).?.pitch);
    try std.testing.expectEqual(@as(i16, 67), writer.latestKindAtOffset(.note_on, 5).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), writer.firstKindAtOffset(.note_off, 5));
    try std.testing.expectEqual(@as(?Event, null), writer.latestKindAtOffset(.note_off, 5));
    try std.testing.expect(!writer.onlyAtOffset(5));
    try std.testing.expect(!writer.onlyKindAtOffset(.note_on, 5));
    try std.testing.expectEqual(@as(?Event, null), writer.firstBus(1));
    try std.testing.expectEqual(@as(?Event, null), writer.latestChannel(1));
    try std.testing.expectEqual(@as(?usize, 3), writer.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, 5), writer.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 5), writer.nextSampleOffsetForKind(.note_on, 1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForKind(.note_off, 3));
    try std.testing.expectEqual(@as(?usize, 3), writer.nextSampleOffsetForBus(0, 1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForBus(1, 1));
    try std.testing.expectEqual(@as(?usize, 3), writer.nextSampleOffsetForChannel(0, 1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForChannel(1, 1));
    try std.testing.expectEqual(@as(?usize, 3), writer.nextSampleOffsetForBusChannel(0, 0, 1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForBusChannel(0, 1, 1));

    var offset_events = writer.atOffset(5);
    try std.testing.expectEqual(@as(i16, 67), offset_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());

    var same_offset_storage: [2]Event = undefined;
    var same_offset_writer = EventWriter.init(&same_offset_storage, 8);
    try same_offset_writer.append(Event.noteOn(2, 0, 60, 1.0));
    try same_offset_writer.append(Event.noteOn(2, 0, 64, 0.5));
    try std.testing.expect(same_offset_writer.onlyAtOffset(2));
    try std.testing.expect(!same_offset_writer.onlyAtOffset(3));
    try std.testing.expect(same_offset_writer.onlyKindAtOffset(.note_on, 2));
    try std.testing.expect(!same_offset_writer.onlyKindAtOffset(.note_off, 2));
}

test "event writer appends event views atomically" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var storage: [2]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try std.testing.expectEqual(@as(usize, 1), try writer.appendCount(items[0]));
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    writer.clear();

    try std.testing.expectEqual(@as(usize, 2), try writer.appendAllCount(try Events.init(&items, 4)));
    try std.testing.expectEqual(@as(usize, 2), writer.eventCount());
    try std.testing.expect(writer.canAppend(0));
    try std.testing.expect(!writer.canAppend(1));
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffset());
    try std.testing.expectEqual(EventKind.note_on, writer.first().?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latest().?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.firstAtOffset(0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestAtOffset(1).?.kind);
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffsetForKind(.midi_cc));
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffsetForBusChannel(0, 0));
    try std.testing.expect(writer.hasKind(.note_on));
    try std.testing.expect(!writer.onlyKind(.note_on));
    try std.testing.expect(writer.onlyBus(0));
    try std.testing.expect(writer.onlyChannel(0));
    try std.testing.expectEqual(@as(usize, 1), writer.countKind(.note_off));
    try std.testing.expectEqual(EventKind.note_on, writer.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestKind(.note_off).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.firstKindAtOffset(.note_on, 0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestKindAtOffset(.note_off, 1).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.firstBus(0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestBus(0).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.firstChannel(0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestChannel(0).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.firstBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), writer.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.nextSampleOffsetForKind(.note_off, 0));
    var written_note_offs = writer.ofKind(.note_off);
    try std.testing.expectEqual(@as(i16, 60), written_note_offs.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_note_offs.next());
    var written_offset_events = writer.atOffset(1);
    try std.testing.expectEqual(EventKind.note_off, written_offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), written_offset_events.next());
    var written_segments = writer.blockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, written_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 4 }, written_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), written_segments.next());
    try std.testing.expectEqual(EventKind.note_on, writer.events().items[0].kind);
    try std.testing.expectEqual(EventKind.note_off, writer.events().items[1].kind);

    var full_storage: [1]Event = undefined;
    var full_writer = EventWriter.init(&full_storage, 4);
    try std.testing.expectEqual(@as(usize, 1), try full_writer.appendCount(items[0]));
    try std.testing.expectError(error.EventStorageFull, full_writer.appendCount(items[1]));
    try std.testing.expectEqual(@as(usize, 1), full_writer.eventCount());
    full_writer.clear();
    try std.testing.expect(!full_writer.canAppend(items.len));
    try std.testing.expectError(error.EventStorageFull, full_writer.appendAllCount(try Events.init(&items, 4)));
    try std.testing.expectEqual(@as(usize, 0), full_writer.eventCount());

    const invalid_and_too_large = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOn(0, 0, 128, 1.0),
    };
    try std.testing.expectError(error.InvalidEventPitch, full_writer.appendAllCount(.{ .items = &invalid_and_too_large }));
    try std.testing.expectEqual(@as(usize, 0), full_writer.eventCount());

    const outside = [_]Event{Event.noteOn(4, 0, 60, 1.0)};
    var outside_storage: [1]Event = undefined;
    var outside_writer = EventWriter.init(&outside_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, outside_writer.appendAllCount(.{ .items = &outside }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());

    const invalid = [_]Event{Event.midiCc(0, 0, 1, 2.0)};
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, outside_writer.appendAllCount(.{ .items = &invalid }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());
}

test "process context exposes output event helpers" {
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var storage: [2]Event = undefined;
    var writer = EventWriter.init(&storage, input.len);
    var context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .output_events = &writer,
    });

    try std.testing.expect(context.hasOutputEventWriter());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, input.len), context.outputEventFrameCount());
    try std.testing.expect(context.canAppendOutputEvent());
    try std.testing.expect(context.canAppendOutputEvents(2));
    try std.testing.expect(!context.canAppendOutputEvents(3));
    try std.testing.expect(context.canAppendOutputEventValue(events[0]));
    try std.testing.expect(context.canAppendOutputEventValues(try Events.init(&events, input.len)));
    try std.testing.expect(!context.canAppendOutputEventValue(Event.noteOn(input.len, 0, 60, 1.0)));
    try std.testing.expect(!context.canAppendOutputEventValue(Event.midiCc(0, 0, 1, 2.0)));
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expect(!context.hasOutputEvents());
    try std.testing.expect(!context.outputEventsFull());

    try std.testing.expectEqual(@as(usize, 1), try context.appendOutputEventCount(events[0]));
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 1), context.outputEventRemainingCapacity());
    try std.testing.expect(context.canAppendOutputEvent());
    try std.testing.expect(!context.canAppendOutputEvents(2));
    try std.testing.expect(!context.canAppendOutputEventValues(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 0), context.latestOutputEventOffset());
    try std.testing.expectEqual(EventKind.note_on, context.firstWrittenOutputEvent().?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.latestWrittenOutputEvent().?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventAtOffset(0).?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.latestOutputEventAtOffset(0).?.kind);
    try std.testing.expect(context.onlyOutputEventsAtOffset(0));
    try std.testing.expect(context.onlyOutputEventsOfKindAtOffset(.note_on, 0));
    try std.testing.expect(!context.onlyOutputEventsOfKindAtOffset(.note_off, 0));
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventAtOffset(1));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventAtOffset(1));
    try std.testing.expect(!context.outputEventsEmpty());
    try std.testing.expect(context.hasOutputEvents());
    try std.testing.expectEqual(@as(usize, 1), try context.appendOutputEventsCount(try Events.init(events[1..], input.len)));

    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteReleases());
    try std.testing.expect(context.hasOutputNoteAttacks());
    try std.testing.expect(context.hasOutputNoteReleases());
    try std.testing.expect(!context.outputNoteAttacksEmpty());
    try std.testing.expect(!context.outputNoteReleasesEmpty());
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffsetForKind(.midi_cc));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffsetForBus(1));
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffsetForChannel(1));
    var output_offset_events = context.outputEventsAtOffset(1);
    try std.testing.expectEqual(EventKind.note_off, output_offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), output_offset_events.next());
    var output_note_offs = context.outputEventsOfKind(.note_off);
    try std.testing.expectEqual(@as(i16, 60), output_note_offs.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), output_note_offs.next());
    var output_segments = context.outputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, output_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, output_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), output_segments.next());
    try std.testing.expect(context.outputEventsFull());
    try std.testing.expect(context.canAppendOutputEvents(0));
    try std.testing.expect(!context.canAppendOutputEvent());
    try std.testing.expect(!context.canAppendOutputEventValue(events[0]));
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEvent(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.firstOutputEvent(.note_off).?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventOfKindAtOffset(.note_on, 0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEventOfKindAtOffset(.note_off, 1).?.kind);
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventOfKindAtOffset(.note_off, 0));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventOfKindAtOffset(.note_on, 1));
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventForBus(0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEventForBus(0).?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventForChannel(0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEventForChannel(0).?.kind);
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventForBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEventForBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventForBus(1));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventForChannel(1));
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expect(!context.hasOutputEvent(.midi_cc));
    try std.testing.expect(!context.outputEventsOfKindEmpty(.note_on));
    try std.testing.expect(context.outputEventsOfKindEmpty(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForBus(1));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForChannel(1));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForBusChannel(1, 0));
    try std.testing.expect(context.hasOutputEventsForBus(0));
    try std.testing.expect(!context.hasOutputEventsForBus(1));
    try std.testing.expect(!context.outputEventsForBusEmpty(0));
    try std.testing.expect(context.outputEventsForBusEmpty(1));
    try std.testing.expect(context.hasOutputEventsForChannel(0));
    try std.testing.expect(!context.hasOutputEventsForChannel(1));
    try std.testing.expect(context.hasOutputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.hasOutputEventsForBusChannel(0, 1));
    try std.testing.expect(!context.outputEventsForChannelEmpty(0));
    try std.testing.expect(context.outputEventsForChannelEmpty(1));
    try std.testing.expect(!context.outputEventsForBusChannelEmpty(0, 0));
    try std.testing.expect(context.outputEventsForBusChannelEmpty(1, 0));
    try std.testing.expect(!context.onlyOutputEventsAtOffset(1));
    try std.testing.expect(!context.onlyOutputEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expect(!context.onlyOutputEventsOfKind(.note_on));
    try std.testing.expect(!context.onlyOutputNoteAttacks());
    try std.testing.expect(!context.onlyOutputNoteReleases());
    try std.testing.expect(context.onlyOutputEventsForBus(0));
    try std.testing.expect(context.onlyOutputEventsForChannel(0));
    try std.testing.expect(context.onlyOutputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.onlyOutputEventsForBusChannel(0, 1));
    try std.testing.expect(!context.onlyOutputEventsForChannel(1));
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEvent(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEvent(.note_off).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForKind(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBus(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForChannel(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForBusChannel(0, 0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBusChannel(0, 1, 0));
    try std.testing.expectEqual(@as(usize, 2), context.clearOutputEventsCount());
    try std.testing.expectEqual(@as(usize, 0), context.clearOutputEventsCount());
    try context.appendOutputEvent(events[0]);
    context.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?Event, null), context.firstWrittenOutputEvent());
    try std.testing.expectEqual(@as(?Event, null), context.latestWrittenOutputEvent());
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventAtOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffsetForChannel(0));
    try std.testing.expect(!context.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), context.countOutputNoteReleases());
    try std.testing.expect(!context.hasOutputNoteAttacks());
    try std.testing.expect(!context.hasOutputNoteReleases());
    try std.testing.expect(context.outputNoteAttacksEmpty());
    try std.testing.expect(context.outputNoteReleasesEmpty());
    try std.testing.expect(context.outputEventsOfKindEmpty(.note_on));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.hasOutputEventsForBus(0));
    try std.testing.expect(!context.hasOutputEventsForChannel(0));
    try std.testing.expect(!context.hasOutputEventsForBusChannel(0, 0));
    try std.testing.expect(context.outputEventsForBusEmpty(0));
    try std.testing.expect(context.outputEventsForChannelEmpty(0));
    try std.testing.expect(context.outputEventsForBusChannelEmpty(0, 0));
    try std.testing.expect(!context.onlyOutputEventsOfKind(.note_on));
    try std.testing.expect(!context.onlyOutputNoteAttacks());
    try std.testing.expect(!context.onlyOutputNoteReleases());
    try std.testing.expect(!context.onlyOutputEventsAtOffset(0));
    try std.testing.expect(!context.onlyOutputEventsOfKindAtOffset(.note_on, 0));
    try std.testing.expect(!context.onlyOutputEventsForBus(0));
    try std.testing.expect(!context.onlyOutputEventsForChannel(0));
    try std.testing.expect(!context.onlyOutputEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventOfKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventOfKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventForBus(0));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventForChannel(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBusChannel(0, 0, 0));
    var cleared_output_notes = context.outputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(?Event, null), cleared_output_notes.next());
    var cleared_output_segments = context.outputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 2 }, cleared_output_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), cleared_output_segments.next());
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expect(!context.hasOutputEvents());

    var no_writer = try ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try std.testing.expect(!no_writer.hasOutputEventWriter());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventFrameCount());
    try std.testing.expect(!no_writer.canAppendOutputEvent());
    try std.testing.expect(!no_writer.canAppendOutputEvents(0));
    try std.testing.expect(!no_writer.canAppendOutputEventValue(events[0]));
    try std.testing.expect(!no_writer.canAppendOutputEventValues(try Events.init(&events, input.len)));
    try std.testing.expect(no_writer.outputEventsEmpty());
    try std.testing.expect(!no_writer.hasOutputEvents());
    try std.testing.expect(no_writer.outputEventsFull());
    try std.testing.expectEqual(@as(?usize, null), no_writer.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), no_writer.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstWrittenOutputEvent());
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestWrittenOutputEvent());
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEventAtOffset(0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.firstOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.latestOutputEventOffsetForChannel(0));
    try std.testing.expect(!no_writer.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputNoteReleases());
    try std.testing.expect(!no_writer.hasOutputNoteAttacks());
    try std.testing.expect(!no_writer.hasOutputNoteReleases());
    try std.testing.expect(no_writer.outputNoteAttacksEmpty());
    try std.testing.expect(no_writer.outputNoteReleasesEmpty());
    try std.testing.expect(no_writer.outputEventsOfKindEmpty(.note_on));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputEventsForBusChannel(0, 0));
    try std.testing.expect(!no_writer.hasOutputEventsForBus(0));
    try std.testing.expect(!no_writer.hasOutputEventsForChannel(0));
    try std.testing.expect(!no_writer.hasOutputEventsForBusChannel(0, 0));
    try std.testing.expect(no_writer.outputEventsForBusEmpty(0));
    try std.testing.expect(no_writer.outputEventsForChannelEmpty(0));
    try std.testing.expect(no_writer.outputEventsForBusChannelEmpty(0, 0));
    try std.testing.expect(!no_writer.onlyOutputEventsOfKind(.note_on));
    try std.testing.expect(!no_writer.onlyOutputNoteAttacks());
    try std.testing.expect(!no_writer.onlyOutputNoteReleases());
    try std.testing.expect(!no_writer.onlyOutputEventsAtOffset(0));
    try std.testing.expect(!no_writer.onlyOutputEventsOfKindAtOffset(.note_on, 0));
    try std.testing.expect(!no_writer.onlyOutputEventsForBus(0));
    try std.testing.expect(!no_writer.onlyOutputEventsForChannel(0));
    try std.testing.expect(!no_writer.onlyOutputEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEventOfKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEventOfKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEventForBus(0));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEventForChannel(0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffsetForBusChannel(0, 0, 0));
    var missing_output_notes = no_writer.outputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(?Event, null), missing_output_notes.next());
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvent(events[0]));
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvents(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
    no_writer.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
}
