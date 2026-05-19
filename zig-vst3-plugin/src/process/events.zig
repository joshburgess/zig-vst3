const std = @import("std");
const common = @import("../common.zig");
const changes = @import("changes.zig");

pub const BlockSegment = changes.BlockSegment;

pub const midi_channel_min: i16 = 0;
pub const midi_channel_max: i16 = 15;
pub const midi_pitch_min: i16 = 0;
pub const midi_pitch_max: i16 = 127;
pub const midi_control_number_min: i16 = 0;
pub const midi_control_number_max: i16 = 127;
pub const event_value_min: f32 = 0.0;
pub const event_value_max: f32 = 1.0;
pub const bipolar_event_value_min: f32 = -1.0;
pub const bipolar_event_value_max: f32 = 1.0;
pub const max_data_event_bytes: usize = 4096;

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
        if (nextMatchingEvent(self.events.items, self.last_offset, self.last_index, self.kind, matchesKind)) |result| {
            self.last_offset = result.item.sample_offset;
            self.last_index = result.index;
            return result.item;
        }
        return null;
    }
};

pub const EventOffsetIterator = struct {
    events: Events,
    sample_offset: usize,
    next_index: usize = 0,

    pub fn next(self: *EventOffsetIterator) ?Event {
        while (self.next_index < self.events.items.len) {
            const item = self.events.items[self.next_index];
            self.next_index += 1;
            if (item.isAtOffset(self.sample_offset)) return item;
        }
        return null;
    }
};

pub const EventBusIterator = struct {
    events: Events,
    bus_index: i32,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *EventBusIterator) ?Event {
        if (nextMatchingEvent(self.events.items, self.last_offset, self.last_index, self.bus_index, matchesBus)) |result| {
            self.last_offset = result.item.sample_offset;
            self.last_index = result.index;
            return result.item;
        }
        return null;
    }
};

pub const EventChannelIterator = struct {
    events: Events,
    channel: i16,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *EventChannelIterator) ?Event {
        if (nextMatchingEvent(self.events.items, self.last_offset, self.last_index, self.channel, matchesChannel)) |result| {
            self.last_offset = result.item.sample_offset;
            self.last_index = result.index;
            return result.item;
        }
        return null;
    }
};

pub const EventBusChannelIterator = struct {
    events: Events,
    bus_index: i32,
    channel: i16,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *EventBusChannelIterator) ?Event {
        const context = BusChannel{ .bus_index = self.bus_index, .channel = self.channel };
        if (nextMatchingEvent(self.events.items, self.last_offset, self.last_index, context, matchesBusChannel)) |result| {
            self.last_offset = result.item.sample_offset;
            self.last_index = result.index;
            return result.item;
        }
        return null;
    }
};

const IndexedEvent = struct {
    item: Event,
    index: usize,
};

const BusChannel = struct {
    bus_index: i32,
    channel: i16,
};

const KindOffset = struct {
    kind: EventKind,
    sample_offset: usize,
};

fn matchesAny(_: Event, _: void) bool {
    return true;
}

fn matchesKind(item: Event, kind: EventKind) bool {
    return item.isKind(kind);
}

fn matchesOffset(item: Event, sample_offset: usize) bool {
    return item.isAtOffset(sample_offset);
}

fn matchesKindOffset(item: Event, context: KindOffset) bool {
    return item.isKindAtOffset(context.kind, context.sample_offset);
}

fn matchesBus(item: Event, bus_index: i32) bool {
    return item.isForBus(bus_index);
}

fn matchesChannel(item: Event, channel: i16) bool {
    return item.isForChannel(channel);
}

fn matchesBusChannel(item: Event, context: BusChannel) bool {
    return item.isForBusChannel(context.bus_index, context.channel);
}

fn matchesNoteAttack(item: Event, _: void) bool {
    return item.isNoteAttack();
}

fn matchesNoteRelease(item: Event, _: void) bool {
    return item.isNoteRelease();
}

fn firstMatchingEvent(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
    var result: ?Event = null;
    for (items) |item| {
        if (!matches(item, context)) continue;
        if (result) |current| {
            if (item.sample_offset < current.sample_offset) result = item;
        } else {
            result = item;
        }
    }
    return result;
}

fn latestMatchingEvent(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
    var result: ?Event = null;
    for (items) |item| {
        if (!matches(item, context)) continue;
        if (result) |current| {
            if (item.sample_offset >= current.sample_offset) result = item;
        } else {
            result = item;
        }
    }
    return result;
}

fn firstStoredMatchingEvent(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
    for (items) |item| {
        if (matches(item, context)) return item;
    }
    return null;
}

fn latestStoredMatchingEvent(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
    var result: ?Event = null;
    for (items) |item| {
        if (matches(item, context)) result = item;
    }
    return result;
}

fn countMatchingEvents(items: []const Event, context: anytype, comptime matches: anytype) usize {
    var count: usize = 0;
    for (items) |item| {
        if (matches(item, context)) count +|= 1;
    }
    return count;
}

fn hasMatchingEvent(items: []const Event, context: anytype, comptime matches: anytype) bool {
    for (items) |item| {
        if (matches(item, context)) return true;
    }
    return false;
}

fn nextMatchingEvent(items: []const Event, last_offset: ?usize, last_index: usize, context: anytype, comptime matches: anytype) ?IndexedEvent {
    var result: ?IndexedEvent = null;
    for (items, 0..) |item, index| {
        if (!matches(item, context)) continue;
        if (last_offset) |offset| {
            if (item.sample_offset < offset) continue;
            if (item.sample_offset == offset and index <= last_index) continue;
        }
        const replace = if (result) |current|
            item.sample_offset < current.item.sample_offset or
                (item.sample_offset == current.item.sample_offset and index < current.index)
        else
            true;
        if (replace) {
            result = .{ .item = item, .index = index };
        }
    }
    return result;
}

fn nextMatchingSampleOffset(items: []const Event, after_sample_offset: usize, context: anytype, comptime matches: anytype) ?usize {
    var result: ?usize = null;
    for (items) |item| {
        if (!matches(item, context) or item.sample_offset <= after_sample_offset) continue;
        if (result) |current| {
            if (item.sample_offset < current) result = item.sample_offset;
        } else {
            result = item.sample_offset;
        }
    }
    return result;
}

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
            .data => {
                if (self.data.len > max_data_event_bytes) return error.DataEventTooLarge;
            },
            .note_expression_int, .note_expression_text, .other => {},
        }
    }
};

fn validateMidiChannel(channel: i16) !void {
    if (channel < midi_channel_min or channel > midi_channel_max) return error.InvalidEventChannel;
}

fn validateMidiPitch(pitch: i16) !void {
    if (pitch < midi_pitch_min or pitch > midi_pitch_max) return error.InvalidEventPitch;
}

fn validateMidiControlNumber(control_number: i16) !void {
    if (control_number < midi_control_number_min or control_number > midi_control_number_max) return error.InvalidEventControlNumber;
}

fn validateUnitEventValue(value: f32) !void {
    if (!common.isFiniteInRange(f32, value, event_value_min, event_value_max)) return error.EventValueOutsideNormalizedRange;
}

fn validateBipolarEventValue(value: f32) !void {
    if (!common.isFiniteInRange(f32, value, bipolar_event_value_min, bipolar_event_value_max)) return error.EventValueOutsideNormalizedRange;
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
        const event = self.first() orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffset(self: Events) ?usize {
        const event = latestMatchingEvent(self.items, {}, matchesAny) orelse return null;
        return event.sample_offset;
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
        return firstMatchingEvent(self.items, {}, matchesAny);
    }

    pub fn latest(self: Events) ?Event {
        return latestMatchingEvent(self.items, {}, matchesAny);
    }

    pub fn firstAtOffset(self: Events, sample_offset: usize) ?Event {
        return firstStoredMatchingEvent(self.items, sample_offset, matchesOffset);
    }

    pub fn latestAtOffset(self: Events, sample_offset: usize) ?Event {
        return latestStoredMatchingEvent(self.items, sample_offset, matchesOffset);
    }

    pub fn countKind(self: Events, kind: EventKind) usize {
        return countMatchingEvents(self.items, kind, matchesKind);
    }

    pub fn countNoteAttacks(self: Events) usize {
        return countMatchingEvents(self.items, {}, matchesNoteAttack);
    }

    pub fn countNoteReleases(self: Events) usize {
        return countMatchingEvents(self.items, {}, matchesNoteRelease);
    }

    pub fn countAtOffset(self: Events, sample_offset: usize) usize {
        return countMatchingEvents(self.items, sample_offset, matchesOffset);
    }

    pub fn countKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) usize {
        const context = KindOffset{ .kind = kind, .sample_offset = sample_offset };
        return countMatchingEvents(self.items, context, matchesKindOffset);
    }

    pub fn countBus(self: Events, bus_index: i32) usize {
        return countMatchingEvents(self.items, bus_index, matchesBus);
    }

    pub fn countChannel(self: Events, channel: i16) usize {
        return countMatchingEvents(self.items, channel, matchesChannel);
    }

    pub fn countBusChannel(self: Events, bus_index: i32, channel: i16) usize {
        const context = BusChannel{ .bus_index = bus_index, .channel = channel };
        return countMatchingEvents(self.items, context, matchesBusChannel);
    }

    pub fn hasBus(self: Events, bus_index: i32) bool {
        return hasMatchingEvent(self.items, bus_index, matchesBus);
    }

    pub fn busEmpty(self: Events, bus_index: i32) bool {
        return !self.hasBus(bus_index);
    }

    pub fn hasChannel(self: Events, channel: i16) bool {
        return hasMatchingEvent(self.items, channel, matchesChannel);
    }

    pub fn channelEmpty(self: Events, channel: i16) bool {
        return !self.hasChannel(channel);
    }

    pub fn hasBusChannel(self: Events, bus_index: i32, channel: i16) bool {
        const context = BusChannel{ .bus_index = bus_index, .channel = channel };
        return hasMatchingEvent(self.items, context, matchesBusChannel);
    }

    pub fn busChannelEmpty(self: Events, bus_index: i32, channel: i16) bool {
        return !self.hasBusChannel(bus_index, channel);
    }

    pub fn firstKind(self: Events, kind: EventKind) ?Event {
        return firstMatchingEvent(self.items, kind, matchesKind);
    }

    pub fn latestKind(self: Events, kind: EventKind) ?Event {
        return latestMatchingEvent(self.items, kind, matchesKind);
    }

    pub fn firstKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) ?Event {
        const context = KindOffset{ .kind = kind, .sample_offset = sample_offset };
        return firstStoredMatchingEvent(self.items, context, matchesKindOffset);
    }

    pub fn latestKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) ?Event {
        const context = KindOffset{ .kind = kind, .sample_offset = sample_offset };
        return latestStoredMatchingEvent(self.items, context, matchesKindOffset);
    }

    pub fn firstBus(self: Events, bus_index: i32) ?Event {
        return firstMatchingEvent(self.items, bus_index, matchesBus);
    }

    pub fn latestBus(self: Events, bus_index: i32) ?Event {
        return latestMatchingEvent(self.items, bus_index, matchesBus);
    }

    pub fn firstChannel(self: Events, channel: i16) ?Event {
        return firstMatchingEvent(self.items, channel, matchesChannel);
    }

    pub fn latestChannel(self: Events, channel: i16) ?Event {
        return latestMatchingEvent(self.items, channel, matchesChannel);
    }

    pub fn firstBusChannel(self: Events, bus_index: i32, channel: i16) ?Event {
        const context = BusChannel{ .bus_index = bus_index, .channel = channel };
        return firstMatchingEvent(self.items, context, matchesBusChannel);
    }

    pub fn latestBusChannel(self: Events, bus_index: i32, channel: i16) ?Event {
        const context = BusChannel{ .bus_index = bus_index, .channel = channel };
        return latestMatchingEvent(self.items, context, matchesBusChannel);
    }

    pub fn hasKind(self: Events, kind: EventKind) bool {
        return hasMatchingEvent(self.items, kind, matchesKind);
    }

    pub fn hasNoteAttacks(self: Events) bool {
        return hasMatchingEvent(self.items, {}, matchesNoteAttack);
    }

    pub fn hasNoteReleases(self: Events) bool {
        return hasMatchingEvent(self.items, {}, matchesNoteRelease);
    }

    pub fn hasAtOffset(self: Events, sample_offset: usize) bool {
        return hasMatchingEvent(self.items, sample_offset, matchesOffset);
    }

    pub fn hasKindAtOffset(self: Events, kind: EventKind, sample_offset: usize) bool {
        const context = KindOffset{ .kind = kind, .sample_offset = sample_offset };
        return hasMatchingEvent(self.items, context, matchesKindOffset);
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
        return nextMatchingSampleOffset(self.items, after_sample_offset, {}, matchesAny);
    }

    pub fn nextSampleOffsetForKind(self: Events, kind: EventKind, after_sample_offset: usize) ?usize {
        return nextMatchingSampleOffset(self.items, after_sample_offset, kind, matchesKind);
    }

    pub fn nextSampleOffsetForBus(self: Events, bus_index: i32, after_sample_offset: usize) ?usize {
        return nextMatchingSampleOffset(self.items, after_sample_offset, bus_index, matchesBus);
    }

    pub fn nextSampleOffsetForChannel(self: Events, channel: i16, after_sample_offset: usize) ?usize {
        return nextMatchingSampleOffset(self.items, after_sample_offset, channel, matchesChannel);
    }

    pub fn nextSampleOffsetForBusChannel(self: Events, bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
        const context = BusChannel{ .bus_index = bus_index, .channel = channel };
        return nextMatchingSampleOffset(self.items, after_sample_offset, context, matchesBusChannel);
    }

    pub fn ofKind(self: Events, kind: EventKind) EventKindIterator {
        return .{ .events = self, .kind = kind };
    }

    pub fn atOffset(self: Events, sample_offset: usize) EventOffsetIterator {
        return .{ .events = self, .sample_offset = sample_offset };
    }

    pub fn forBus(self: Events, bus_index: i32) EventBusIterator {
        return .{ .events = self, .bus_index = bus_index };
    }

    pub fn forChannel(self: Events, channel: i16) EventChannelIterator {
        return .{ .events = self, .channel = channel };
    }

    pub fn forBusChannel(self: Events, bus_index: i32, channel: i16) EventBusChannelIterator {
        return .{ .events = self, .bus_index = bus_index, .channel = channel };
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
        try self.appendValidated(event);
        return 1;
    }

    pub fn appendAll(self: *EventWriter, source: Events) !void {
        _ = try self.appendAllCount(source);
    }

    pub fn appendAllCount(self: *EventWriter, source: Events) !usize {
        for (source.items) |event| {
            try event.validate(self.frame_count);
        }
        if (source.items.len > self.remainingCapacity()) return error.EventStorageFull;
        for (source.items) |event| {
            try self.appendValidated(event);
        }
        return source.items.len;
    }

    fn appendValidated(self: *EventWriter, event: Event) !void {
        if (self.count >= self.storage.len) return error.EventStorageFull;
        self.storage[self.count] = event;
        self.count +|= 1;
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
        const cleared = self.eventCount();
        self.count = 0;
        return cleared;
    }

    pub fn eventCount(self: *const EventWriter) usize {
        return @min(self.count, self.storage.len);
    }

    pub fn isEmpty(self: *const EventWriter) bool {
        return self.eventCount() == 0;
    }

    pub fn hasEvents(self: *const EventWriter) bool {
        return self.eventCount() != 0;
    }

    pub fn isFull(self: *const EventWriter) bool {
        return self.count >= self.storage.len;
    }

    pub fn capacity(self: *const EventWriter) usize {
        return self.storage.len;
    }

    pub fn remainingCapacity(self: *const EventWriter) usize {
        return self.storage.len - self.eventCount();
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

    pub fn forBus(self: *const EventWriter, bus_index: i32) EventBusIterator {
        return self.events().forBus(bus_index);
    }

    pub fn forChannel(self: *const EventWriter, channel: i16) EventChannelIterator {
        return self.events().forChannel(channel);
    }

    pub fn forBusChannel(self: *const EventWriter, bus_index: i32, channel: i16) EventBusChannelIterator {
        return self.events().forBusChannel(bus_index, channel);
    }

    pub fn blockSegments(self: *const EventWriter) EventBlockSegmentIterator {
        return self.events().blockSegments(self.frame_count);
    }

    pub fn events(self: *const EventWriter) Events {
        return .{ .items = self.storage[0..self.eventCount()] };
    }
};

const GeneratedRoutableEventKind = enum {
    note_on,
    note_off,
    midi_cc,
    pitch_bend,
};

fn generatedRoutableEvent(kind: GeneratedRoutableEventKind, sample_offset: usize, channel: i16, pitch: i16, control_number: i16) Event {
    return switch (kind) {
        .note_on => Event.noteOn(sample_offset, channel, pitch, 0.25),
        .note_off => Event.noteOff(sample_offset, channel, pitch, 0.0),
        .midi_cc => Event.midiCc(sample_offset, channel, control_number, 0.5),
        .pitch_bend => Event.pitchBend(sample_offset, channel, 0.75),
    };
}

fn generatedRoutableEventKind(kind: GeneratedRoutableEventKind) EventKind {
    return switch (kind) {
        .note_on => .note_on,
        .note_off => .note_off,
        .midi_cc => .midi_cc,
        .pitch_bend => .pitch_bend,
    };
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
    try std.testing.expectEqual(@as(?usize, 3), view.firstSampleOffsetForKind(.other));
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
    try std.testing.expect(view.onlyBus(0));
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
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForKind(.note_on, 1));
    try std.testing.expectEqual(@as(?usize, 6), view.nextSampleOffsetForKind(.note_off, 3));
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
    var bus_one_events = view.forBus(1);
    try std.testing.expectEqual(@as(i16, 64), bus_one_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, bus_one_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), bus_one_events.next());
    var channel_one_events = view.forChannel(1);
    try std.testing.expectEqual(@as(i16, 64), channel_one_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, channel_one_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), channel_one_events.next());
    var bus_channel_events = view.forBusChannel(1, 1);
    try std.testing.expectEqual(@as(i16, 64), bus_channel_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, bus_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), bus_channel_events.next());
    var missing_bus_events = view.forBus(2);
    try std.testing.expectEqual(@as(?Event, null), missing_bus_events.next());

    const same_offset_items = [_]Event{
        Event.noteOn(2, 0, 60, 1.0),
        Event.noteOn(2, 0, 64, 0.5),
    };
    const same_offset_view = try Events.init(&same_offset_items, 8);
    try std.testing.expect(same_offset_view.onlyAtOffset(2));
    try std.testing.expect(!same_offset_view.onlyAtOffset(3));
    try std.testing.expect(same_offset_view.onlyKindAtOffset(.note_on, 2));
    try std.testing.expect(!same_offset_view.onlyKindAtOffset(.note_off, 2));
    try std.testing.expectEqual(@as(i16, 60), same_offset_view.first().?.pitch);
    try std.testing.expectEqual(@as(i16, 64), same_offset_view.latest().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), same_offset_view.firstAtOffset(2).?.pitch);
    try std.testing.expectEqual(@as(i16, 64), same_offset_view.latestAtOffset(2).?.pitch);
}

test "events generated queries match reference scans" {
    const Reference = struct {
        fn itemMatchesKind(item: Event, kind: EventKind) bool {
            return item.kind == kind;
        }

        fn itemMatchesBus(item: Event, bus_index: i32) bool {
            return item.bus_index == bus_index;
        }

        fn itemMatchesChannel(item: Event, channel: i16) bool {
            return item.hasChannel() and item.channel == channel;
        }

        fn itemMatchesBusChannel(item: Event, bus_channel: BusChannel) bool {
            return itemMatchesBus(item, bus_channel.bus_index) and itemMatchesChannel(item, bus_channel.channel);
        }

        fn countKind(items: []const Event, kind: EventKind) usize {
            var result: usize = 0;
            for (items) |item| {
                if (itemMatchesKind(item, kind)) result += 1;
            }
            return result;
        }

        fn hasKind(items: []const Event, kind: EventKind) bool {
            return countKind(items, kind) != 0;
        }

        fn onlyKind(items: []const Event, kind: EventKind) bool {
            return items.len != 0 and countKind(items, kind) == items.len;
        }

        fn countMatching(items: []const Event, context: anytype, comptime matches: anytype) usize {
            var result: usize = 0;
            for (items) |item| {
                if (matches(item, context)) result += 1;
            }
            return result;
        }

        fn hasMatching(items: []const Event, context: anytype, comptime matches: anytype) bool {
            return countMatching(items, context, matches) != 0;
        }

        fn onlyMatching(items: []const Event, context: anytype, comptime matches: anytype) bool {
            return items.len != 0 and countMatching(items, context, matches) == items.len;
        }

        fn firstMatching(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
            var result: ?Event = null;
            for (items) |item| {
                if (!matches(item, context)) continue;
                if (result) |current| {
                    if (item.sample_offset < current.sample_offset) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        fn latestMatching(items: []const Event, context: anytype, comptime matches: anytype) ?Event {
            var result: ?Event = null;
            for (items) |item| {
                if (!matches(item, context)) continue;
                if (result) |current| {
                    if (item.sample_offset >= current.sample_offset) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        fn nextOffsetMatching(items: []const Event, context: anytype, after_sample_offset: usize, comptime matches: anytype) ?usize {
            var result: ?usize = null;
            for (items) |item| {
                if (!matches(item, context) or item.sample_offset <= after_sample_offset) continue;
                if (result) |current| {
                    if (item.sample_offset < current) result = item.sample_offset;
                } else {
                    result = item.sample_offset;
                }
            }
            return result;
        }

        fn nextAnyOffset(items: []const Event, after_sample_offset: usize) ?usize {
            var result: ?usize = null;
            for (items) |item| {
                if (item.sample_offset <= after_sample_offset) continue;
                if (result) |current| {
                    if (item.sample_offset < current) result = item.sample_offset;
                } else {
                    result = item.sample_offset;
                }
            }
            return result;
        }

        fn firstKind(items: []const Event, kind: EventKind) ?Event {
            return firstMatching(items, kind, itemMatchesKind);
        }

        fn latestKind(items: []const Event, kind: EventKind) ?Event {
            return latestMatching(items, kind, itemMatchesKind);
        }

        fn nextOffsetForKind(items: []const Event, kind: EventKind, after_sample_offset: usize) ?usize {
            return nextOffsetMatching(items, kind, after_sample_offset, itemMatchesKind);
        }

        fn countAtOffset(items: []const Event, sample_offset: usize) usize {
            var result: usize = 0;
            for (items) |item| {
                if (item.sample_offset == sample_offset) result += 1;
            }
            return result;
        }

        fn hasAtOffset(items: []const Event, sample_offset: usize) bool {
            return countAtOffset(items, sample_offset) != 0;
        }

        fn onlyAtOffset(items: []const Event, sample_offset: usize) bool {
            return items.len != 0 and countAtOffset(items, sample_offset) == items.len;
        }

        fn countKindAtOffset(items: []const Event, kind: EventKind, sample_offset: usize) usize {
            var result: usize = 0;
            for (items) |item| {
                if (item.kind == kind and item.sample_offset == sample_offset) result += 1;
            }
            return result;
        }

        fn hasKindAtOffset(items: []const Event, kind: EventKind, sample_offset: usize) bool {
            return countKindAtOffset(items, kind, sample_offset) != 0;
        }

        fn onlyKindAtOffset(items: []const Event, kind: EventKind, sample_offset: usize) bool {
            return items.len != 0 and countKindAtOffset(items, kind, sample_offset) == items.len;
        }
    };

    const kinds = [_]GeneratedRoutableEventKind{ .note_on, .note_off, .midi_cc, .pitch_bend };
    const bus_indexes = [_]i32{ 0, 1, 2 };
    const channels = [_]i16{ 0, 1, 2 };
    const frame_count = 6;

    for (0..32) |seed| {
        var storage: [4]Event = undefined;
        for (&storage, 0..) |*item, index| {
            const sample_offset = (seed * 3 + index * 2) % frame_count;
            const channel: i16 = @intCast((seed + index) % 3);
            item.* = generatedRoutableEvent(kinds[(seed + index * 2) % kinds.len], sample_offset, channel, @intCast(60 + index), @intCast(1 + index))
                .withBusIndex(@intCast((seed + index * 2) % 3));
        }

        for (0..storage.len + 1) |len| {
            const items = storage[0..len];
            const view = try Events.init(items, frame_count);

            for (kinds) |kind| {
                const event_kind = generatedRoutableEventKind(kind);
                try std.testing.expectEqual(Reference.countKind(items, event_kind), view.countKind(event_kind));
                try std.testing.expectEqual(Reference.hasKind(items, event_kind), view.hasKind(event_kind));
                try std.testing.expectEqual(!Reference.hasKind(items, event_kind), view.kindEmpty(event_kind));
                try std.testing.expectEqual(Reference.onlyKind(items, event_kind), view.onlyKind(event_kind));
                try std.testing.expectEqual(Reference.firstKind(items, event_kind), view.firstKind(event_kind));
                try std.testing.expectEqual(Reference.latestKind(items, event_kind), view.latestKind(event_kind));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(Reference.countKindAtOffset(items, event_kind, sample_offset), view.countKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(Reference.hasKindAtOffset(items, event_kind, sample_offset), view.hasKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(!Reference.hasKindAtOffset(items, event_kind, sample_offset), view.kindAtOffsetEmpty(event_kind, sample_offset));
                    try std.testing.expectEqual(Reference.onlyKindAtOffset(items, event_kind, sample_offset), view.onlyKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(
                        Reference.nextOffsetForKind(items, event_kind, sample_offset),
                        view.nextSampleOffsetForKind(event_kind, sample_offset),
                    );
                }
            }

            for (0..frame_count) |sample_offset| {
                try std.testing.expectEqual(Reference.countAtOffset(items, sample_offset), view.countAtOffset(sample_offset));
                try std.testing.expectEqual(Reference.hasAtOffset(items, sample_offset), view.hasAtOffset(sample_offset));
                try std.testing.expectEqual(!Reference.hasAtOffset(items, sample_offset), view.offsetEmpty(sample_offset));
                try std.testing.expectEqual(Reference.onlyAtOffset(items, sample_offset), view.onlyAtOffset(sample_offset));
                try std.testing.expectEqual(Reference.nextAnyOffset(items, sample_offset), view.nextSampleOffset(sample_offset));
            }

            for (bus_indexes) |bus_index| {
                try std.testing.expectEqual(Reference.countMatching(items, bus_index, Reference.itemMatchesBus), view.countBus(bus_index));
                try std.testing.expectEqual(Reference.hasMatching(items, bus_index, Reference.itemMatchesBus), view.hasBus(bus_index));
                try std.testing.expectEqual(!Reference.hasMatching(items, bus_index, Reference.itemMatchesBus), view.busEmpty(bus_index));
                try std.testing.expectEqual(Reference.onlyMatching(items, bus_index, Reference.itemMatchesBus), view.onlyBus(bus_index));
                try std.testing.expectEqual(Reference.firstMatching(items, bus_index, Reference.itemMatchesBus), view.firstBus(bus_index));
                try std.testing.expectEqual(Reference.latestMatching(items, bus_index, Reference.itemMatchesBus), view.latestBus(bus_index));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(
                        Reference.nextOffsetMatching(items, bus_index, sample_offset, Reference.itemMatchesBus),
                        view.nextSampleOffsetForBus(bus_index, sample_offset),
                    );
                }
            }

            for (channels) |channel| {
                try std.testing.expectEqual(Reference.countMatching(items, channel, Reference.itemMatchesChannel), view.countChannel(channel));
                try std.testing.expectEqual(Reference.hasMatching(items, channel, Reference.itemMatchesChannel), view.hasChannel(channel));
                try std.testing.expectEqual(!Reference.hasMatching(items, channel, Reference.itemMatchesChannel), view.channelEmpty(channel));
                try std.testing.expectEqual(Reference.onlyMatching(items, channel, Reference.itemMatchesChannel), view.onlyChannel(channel));
                try std.testing.expectEqual(Reference.firstMatching(items, channel, Reference.itemMatchesChannel), view.firstChannel(channel));
                try std.testing.expectEqual(Reference.latestMatching(items, channel, Reference.itemMatchesChannel), view.latestChannel(channel));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(
                        Reference.nextOffsetMatching(items, channel, sample_offset, Reference.itemMatchesChannel),
                        view.nextSampleOffsetForChannel(channel, sample_offset),
                    );
                }
            }

            for (bus_indexes) |bus_index| {
                for (channels) |channel| {
                    const bus_channel = BusChannel{ .bus_index = bus_index, .channel = channel };
                    try std.testing.expectEqual(Reference.countMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.countBusChannel(bus_index, channel));
                    try std.testing.expectEqual(Reference.hasMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.hasBusChannel(bus_index, channel));
                    try std.testing.expectEqual(!Reference.hasMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.busChannelEmpty(bus_index, channel));
                    try std.testing.expectEqual(Reference.onlyMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.onlyBusChannel(bus_index, channel));
                    try std.testing.expectEqual(Reference.firstMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.firstBusChannel(bus_index, channel));
                    try std.testing.expectEqual(Reference.latestMatching(items, bus_channel, Reference.itemMatchesBusChannel), view.latestBusChannel(bus_index, channel));
                    for (0..frame_count) |sample_offset| {
                        try std.testing.expectEqual(
                            Reference.nextOffsetMatching(items, bus_channel, sample_offset, Reference.itemMatchesBusChannel),
                            view.nextSampleOffsetForBusChannel(bus_index, channel, sample_offset),
                        );
                    }
                }
            }
        }
    }
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
        Event.noteOn(0, midi_channel_max + 1, 60, 1.0),
    };
    const bad_pitch = [_]Event{
        Event.noteOff(0, 0, midi_pitch_max + 1, 0.0),
    };
    const bad_control = [_]Event{
        Event.midiCc(0, 0, midi_control_number_max + 1, 0.5),
    };
    const bad_bus = [_]Event{
        Event.pitchBend(0, 0, 0.0).withBusIndex(-1),
    };

    try std.testing.expectError(error.InvalidEventChannel, Events.init(&bad_channel, 4));
    try std.testing.expectError(error.InvalidEventPitch, Events.init(&bad_pitch, 4));
    try std.testing.expectError(error.InvalidEventControlNumber, Events.init(&bad_control, 4));
    try std.testing.expectError(error.InvalidEventBusIndex, Events.init(&bad_bus, 4));
}

test "events reject oversized data payloads" {
    const max_payload = [_]u8{0} ** max_data_event_bytes;
    const max_data = [_]Event{
        Event.dataEvent(0, 1, &max_payload),
    };
    const oversized_payload = [_]u8{0} ** (max_data_event_bytes + 1);
    const oversized_data = [_]Event{
        Event.dataEvent(0, 1, &oversized_payload),
    };

    _ = try Events.init(&max_data, 4);
    try std.testing.expectError(error.DataEventTooLarge, oversized_data[0].validate(4));
    try std.testing.expectError(error.DataEventTooLarge, Events.init(&oversized_data, 4));
}

test "events validate generated boundary cases" {
    const valid_offsets = [_]usize{ 0, 1, 3 };
    for (valid_offsets) |offset| {
        const events = [_]Event{
            Event.noteOn(offset, midi_channel_min, midi_pitch_min, event_value_min),
            Event.noteOn(offset, midi_channel_max, midi_pitch_max, event_value_max),
            Event.noteOff(offset, midi_channel_min, midi_pitch_min, event_value_min),
            Event.noteOff(offset, midi_channel_max, midi_pitch_max, event_value_max),
            Event.midiCc(offset, midi_channel_min, midi_control_number_min, event_value_min),
            Event.midiCc(offset, midi_channel_max, midi_control_number_max, event_value_max),
            Event.pitchBend(offset, midi_channel_min, bipolar_event_value_min),
            Event.pitchBend(offset, midi_channel_max, bipolar_event_value_max),
            Event.aftertouch(offset, midi_channel_min, midi_pitch_min, event_value_min),
            Event.aftertouch(offset, midi_channel_max, midi_pitch_max, event_value_max),
            Event.noteExpressionValue(offset, -1, 0, event_value_min),
            Event.noteExpressionValue(offset, 7, std.math.maxInt(u32), event_value_max),
            Event.noteExpressionInt(offset, -1, 0, 0),
            Event.noteExpressionText(offset, -1, 0),
            Event.dataEvent(offset, std.math.maxInt(u32), &.{ 1, 2, 3 }),
            Event.other(offset),
        };
        for (events) |event| try event.validate(4);
        _ = try Events.init(&events, 4);
    }

    const invalid_offsets = [_]usize{ 4, 5, std.math.maxInt(usize) };
    for (invalid_offsets) |offset| {
        try std.testing.expectError(error.EventOutsideBlock, Event.other(offset).validate(4));
    }

    const invalid_bus_events = [_]Event{
        Event.noteOn(0, 0, 60, 1.0).withBusIndex(-1),
        Event.noteExpressionInt(0, 42, 7, 11).withBusIndex(-1),
        Event.dataEvent(0, 1, &.{}).withBusIndex(-1),
        Event.other(0).withBusIndex(-1),
    };
    for (invalid_bus_events) |event| {
        try std.testing.expectError(error.InvalidEventBusIndex, event.validate(4));
    }

    const invalid_channel_events = [_]Event{
        Event.noteOn(0, midi_channel_min - 1, 60, 1.0),
        Event.noteOn(0, midi_channel_max + 1, 60, 1.0),
        Event.noteOff(0, midi_channel_min - 1, 60, 0.0),
        Event.noteOff(0, midi_channel_max + 1, 60, 0.0),
        Event.midiCc(0, midi_channel_min - 1, 1, 0.5),
        Event.midiCc(0, midi_channel_max + 1, 1, 0.5),
        Event.pitchBend(0, midi_channel_min - 1, 0.0),
        Event.pitchBend(0, midi_channel_max + 1, 0.0),
        Event.aftertouch(0, midi_channel_min - 1, 60, 0.5),
        Event.aftertouch(0, midi_channel_max + 1, 60, 0.5),
    };
    for (invalid_channel_events) |event| {
        try std.testing.expectError(error.InvalidEventChannel, event.validate(4));
    }

    const invalid_pitch_events = [_]Event{
        Event.noteOn(0, 0, midi_pitch_min - 1, 1.0),
        Event.noteOn(0, 0, midi_pitch_max + 1, 1.0),
        Event.noteOff(0, 0, midi_pitch_min - 1, 0.0),
        Event.noteOff(0, 0, midi_pitch_max + 1, 0.0),
        Event.aftertouch(0, 0, midi_pitch_min - 1, 0.5),
        Event.aftertouch(0, 0, midi_pitch_max + 1, 0.5),
    };
    for (invalid_pitch_events) |event| {
        try std.testing.expectError(error.InvalidEventPitch, event.validate(4));
    }

    const invalid_control_events = [_]Event{
        Event.midiCc(0, 0, midi_control_number_min - 1, 0.5),
        Event.midiCc(0, 0, midi_control_number_max + 1, 0.5),
    };
    for (invalid_control_events) |event| {
        try std.testing.expectError(error.InvalidEventControlNumber, event.validate(4));
    }

    const invalid_value_events = [_]Event{
        Event.noteOn(0, 0, 60, event_value_min - 0.01),
        Event.noteOn(0, 0, 60, event_value_max + 0.01),
        Event.noteOff(0, 0, 60, std.math.nan(f32)),
        Event.midiCc(0, 0, 1, std.math.inf(f32)),
        Event.pitchBend(0, 0, bipolar_event_value_min - 0.01),
        Event.pitchBend(0, 0, bipolar_event_value_max + 0.01),
        Event.aftertouch(0, 0, 60, event_value_min - 0.01),
        Event.noteExpressionValue(0, 42, 7, event_value_max + 0.01),
    };
    for (invalid_value_events) |event| {
        try std.testing.expectError(error.EventValueOutsideNormalizedRange, event.validate(4));
    }
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
    var written_bus_events = writer.forBus(0);
    try std.testing.expectEqual(@as(i16, 60), written_bus_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_bus_events.next());
    var written_channel_events = writer.forChannel(0);
    try std.testing.expectEqual(@as(i16, 60), written_channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_channel_events.next());
    var written_bus_channel_events = writer.forBusChannel(0, 0);
    try std.testing.expectEqual(@as(i16, 60), written_bus_channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_bus_channel_events.next());
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
    var bus_events = writer.forBus(0);
    try std.testing.expectEqual(@as(i16, 60), bus_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, bus_events.next().?.kind);
    try std.testing.expectEqual(@as(i16, 67), bus_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), bus_events.next());
    var channel_events = writer.forChannel(0);
    try std.testing.expectEqual(@as(i16, 60), channel_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, channel_events.next().?.kind);
    try std.testing.expectEqual(@as(i16, 67), channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), channel_events.next());
    var bus_channel_events = writer.forBusChannel(0, 0);
    try std.testing.expectEqual(@as(i16, 60), bus_channel_events.next().?.pitch);
    try std.testing.expectEqual(EventKind.note_off, bus_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(i16, 67), bus_channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), bus_channel_events.next());

    var same_offset_storage: [2]Event = undefined;
    var same_offset_writer = EventWriter.init(&same_offset_storage, 8);
    try same_offset_writer.append(Event.noteOn(2, 0, 60, 1.0));
    try same_offset_writer.append(Event.noteOn(2, 0, 64, 0.5));
    try std.testing.expect(same_offset_writer.onlyAtOffset(2));
    try std.testing.expect(!same_offset_writer.onlyAtOffset(3));
    try std.testing.expect(same_offset_writer.onlyKindAtOffset(.note_on, 2));
    try std.testing.expect(!same_offset_writer.onlyKindAtOffset(.note_off, 2));
    try std.testing.expectEqual(@as(i16, 60), same_offset_writer.first().?.pitch);
    try std.testing.expectEqual(@as(i16, 64), same_offset_writer.latest().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), same_offset_writer.firstAtOffset(2).?.pitch);
    try std.testing.expectEqual(@as(i16, 64), same_offset_writer.latestAtOffset(2).?.pitch);
}

test "event writer generated queries match event views" {
    const kinds = [_]GeneratedRoutableEventKind{ .note_on, .note_off, .midi_cc, .pitch_bend };
    const bus_indexes = [_]i32{ 0, 1, 2 };
    const channels = [_]i16{ 0, 1, 2 };
    const frame_count = 6;

    for (0..32) |seed| {
        var source: [4]Event = undefined;
        for (&source, 0..) |*item, index| {
            const sample_offset = (seed * 3 + index * 2) % frame_count;
            const channel: i16 = @intCast((seed + index) % 3);
            item.* = generatedRoutableEvent(kinds[(seed + index * 2) % kinds.len], sample_offset, channel, @intCast(60 + index), @intCast(1 + index))
                .withBusIndex(@intCast((seed + index * 2) % 3));
        }

        for (0..source.len + 1) |len| {
            var storage: [source.len]Event = undefined;
            var writer = EventWriter.init(&storage, frame_count);
            try writer.appendAll(try Events.init(source[0..len], frame_count));
            const view = writer.events();

            try std.testing.expectEqual(view.eventCount(), writer.eventCount());
            try std.testing.expectEqual(view.isEmpty(), writer.isEmpty());
            try std.testing.expectEqual(view.hasEvents(), writer.hasEvents());
            try std.testing.expectEqual(view.firstSampleOffset(), writer.firstSampleOffset());
            try std.testing.expectEqual(view.latestSampleOffset(), writer.latestSampleOffset());
            try std.testing.expectEqual(view.first(), writer.first());
            try std.testing.expectEqual(view.latest(), writer.latest());

            for (kinds) |kind| {
                const event_kind = generatedRoutableEventKind(kind);
                try std.testing.expectEqual(view.countKind(event_kind), writer.countKind(event_kind));
                try std.testing.expectEqual(view.hasKind(event_kind), writer.hasKind(event_kind));
                try std.testing.expectEqual(view.kindEmpty(event_kind), writer.kindEmpty(event_kind));
                try std.testing.expectEqual(view.onlyKind(event_kind), writer.onlyKind(event_kind));
                try std.testing.expectEqual(view.firstSampleOffsetForKind(event_kind), writer.firstSampleOffsetForKind(event_kind));
                try std.testing.expectEqual(view.latestSampleOffsetForKind(event_kind), writer.latestSampleOffsetForKind(event_kind));
                try std.testing.expectEqual(view.firstKind(event_kind), writer.firstKind(event_kind));
                try std.testing.expectEqual(view.latestKind(event_kind), writer.latestKind(event_kind));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(view.countKindAtOffset(event_kind, sample_offset), writer.countKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(view.hasKindAtOffset(event_kind, sample_offset), writer.hasKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(view.kindAtOffsetEmpty(event_kind, sample_offset), writer.kindAtOffsetEmpty(event_kind, sample_offset));
                    try std.testing.expectEqual(view.onlyKindAtOffset(event_kind, sample_offset), writer.onlyKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(view.firstKindAtOffset(event_kind, sample_offset), writer.firstKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(view.latestKindAtOffset(event_kind, sample_offset), writer.latestKindAtOffset(event_kind, sample_offset));
                    try std.testing.expectEqual(view.nextSampleOffsetForKind(event_kind, sample_offset), writer.nextSampleOffsetForKind(event_kind, sample_offset));
                }
            }

            for (0..frame_count) |sample_offset| {
                try std.testing.expectEqual(view.countAtOffset(sample_offset), writer.countAtOffset(sample_offset));
                try std.testing.expectEqual(view.hasAtOffset(sample_offset), writer.hasAtOffset(sample_offset));
                try std.testing.expectEqual(view.offsetEmpty(sample_offset), writer.offsetEmpty(sample_offset));
                try std.testing.expectEqual(view.onlyAtOffset(sample_offset), writer.onlyAtOffset(sample_offset));
                try std.testing.expectEqual(view.firstAtOffset(sample_offset), writer.firstAtOffset(sample_offset));
                try std.testing.expectEqual(view.latestAtOffset(sample_offset), writer.latestAtOffset(sample_offset));
                try std.testing.expectEqual(view.nextSampleOffset(sample_offset), writer.nextSampleOffset(sample_offset));
            }

            for (bus_indexes) |bus_index| {
                try std.testing.expectEqual(view.countBus(bus_index), writer.countBus(bus_index));
                try std.testing.expectEqual(view.hasBus(bus_index), writer.hasBus(bus_index));
                try std.testing.expectEqual(view.busEmpty(bus_index), writer.busEmpty(bus_index));
                try std.testing.expectEqual(view.onlyBus(bus_index), writer.onlyBus(bus_index));
                try std.testing.expectEqual(view.firstSampleOffsetForBus(bus_index), writer.firstSampleOffsetForBus(bus_index));
                try std.testing.expectEqual(view.latestSampleOffsetForBus(bus_index), writer.latestSampleOffsetForBus(bus_index));
                try std.testing.expectEqual(view.firstBus(bus_index), writer.firstBus(bus_index));
                try std.testing.expectEqual(view.latestBus(bus_index), writer.latestBus(bus_index));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(view.nextSampleOffsetForBus(bus_index, sample_offset), writer.nextSampleOffsetForBus(bus_index, sample_offset));
                }
            }

            for (channels) |channel| {
                try std.testing.expectEqual(view.countChannel(channel), writer.countChannel(channel));
                try std.testing.expectEqual(view.hasChannel(channel), writer.hasChannel(channel));
                try std.testing.expectEqual(view.channelEmpty(channel), writer.channelEmpty(channel));
                try std.testing.expectEqual(view.onlyChannel(channel), writer.onlyChannel(channel));
                try std.testing.expectEqual(view.firstSampleOffsetForChannel(channel), writer.firstSampleOffsetForChannel(channel));
                try std.testing.expectEqual(view.latestSampleOffsetForChannel(channel), writer.latestSampleOffsetForChannel(channel));
                try std.testing.expectEqual(view.firstChannel(channel), writer.firstChannel(channel));
                try std.testing.expectEqual(view.latestChannel(channel), writer.latestChannel(channel));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(view.nextSampleOffsetForChannel(channel, sample_offset), writer.nextSampleOffsetForChannel(channel, sample_offset));
                }
            }

            for (bus_indexes) |bus_index| {
                for (channels) |channel| {
                    try std.testing.expectEqual(view.countBusChannel(bus_index, channel), writer.countBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.hasBusChannel(bus_index, channel), writer.hasBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.busChannelEmpty(bus_index, channel), writer.busChannelEmpty(bus_index, channel));
                    try std.testing.expectEqual(view.onlyBusChannel(bus_index, channel), writer.onlyBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.firstSampleOffsetForBusChannel(bus_index, channel), writer.firstSampleOffsetForBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.latestSampleOffsetForBusChannel(bus_index, channel), writer.latestSampleOffsetForBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.firstBusChannel(bus_index, channel), writer.firstBusChannel(bus_index, channel));
                    try std.testing.expectEqual(view.latestBusChannel(bus_index, channel), writer.latestBusChannel(bus_index, channel));
                    for (0..frame_count) |sample_offset| {
                        try std.testing.expectEqual(
                            view.nextSampleOffsetForBusChannel(bus_index, channel, sample_offset),
                            writer.nextSampleOffsetForBusChannel(bus_index, channel, sample_offset),
                        );
                    }
                }
            }
        }
    }
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
    var written_bus_events = writer.forBus(0);
    try std.testing.expectEqual(EventKind.note_on, written_bus_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, written_bus_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), written_bus_events.next());
    var written_channel_events = writer.forChannel(0);
    try std.testing.expectEqual(EventKind.note_on, written_channel_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, written_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), written_channel_events.next());
    var written_bus_channel_events = writer.forBusChannel(0, 0);
    try std.testing.expectEqual(EventKind.note_on, written_bus_channel_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, written_bus_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), written_bus_channel_events.next());
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

    var existing_storage: [2]Event = undefined;
    var existing_writer = EventWriter.init(&existing_storage, 4);
    try existing_writer.append(items[0]);
    try std.testing.expectError(error.EventStorageFull, existing_writer.appendAllCount(try Events.init(&items, 4)));
    try std.testing.expectEqual(@as(usize, 1), existing_writer.eventCount());
    try std.testing.expectEqual(EventKind.note_on, existing_writer.events().items[0].kind);
    try std.testing.expectEqual(@as(i16, 60), existing_writer.events().items[0].pitch);

    const invalid_and_too_large = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOn(0, 0, 128, 1.0),
    };
    try std.testing.expectError(error.InvalidEventPitch, full_writer.appendAllCount(.{ .items = &invalid_and_too_large }));
    try std.testing.expectEqual(@as(usize, 0), full_writer.eventCount());

    var preserved_storage: [3]Event = undefined;
    var preserved_writer = EventWriter.init(&preserved_storage, 4);
    try preserved_writer.append(items[0]);
    try std.testing.expectError(error.InvalidEventPitch, preserved_writer.appendAllCount(.{ .items = &invalid_and_too_large }));
    try std.testing.expectEqual(@as(usize, 1), preserved_writer.eventCount());
    try std.testing.expectEqual(EventKind.note_on, preserved_writer.events().items[0].kind);
    try std.testing.expectEqual(@as(i16, 60), preserved_writer.events().items[0].pitch);

    const outside = [_]Event{Event.noteOn(4, 0, 60, 1.0)};
    var outside_storage: [1]Event = undefined;
    var outside_writer = EventWriter.init(&outside_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, outside_writer.appendAllCount(.{ .items = &outside }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());

    const invalid = [_]Event{Event.midiCc(0, 0, 1, 2.0)};
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, outside_writer.appendAllCount(.{ .items = &invalid }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());

    const oversized_payload = [_]u8{0} ** (max_data_event_bytes + 1);
    const oversized_data = [_]Event{
        Event.dataEvent(0, 1, &oversized_payload),
    };
    try std.testing.expectError(error.DataEventTooLarge, outside_writer.appendAllCount(.{ .items = &oversized_data }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());
}

test "event writer clamps corrupted counts" {
    var storage = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var writer = EventWriter.init(&storage, 4);
    writer.count = storage.len + 10;

    try std.testing.expectEqual(@as(usize, storage.len), writer.eventCount());
    try std.testing.expectEqual(@as(usize, 0), writer.remainingCapacity());
    try std.testing.expect(writer.isFull());
    try std.testing.expect(writer.hasEvents());
    try std.testing.expect(!writer.isEmpty());
    try std.testing.expect(!writer.canAppend(1));
    try std.testing.expectError(error.EventStorageFull, writer.append(Event.other(2)));
    try std.testing.expectError(error.EventStorageFull, writer.appendAll(.{ .items = &[_]Event{Event.other(2)} }));
    try std.testing.expectEqual(@as(usize, storage.len), writer.events().eventCount());
    try std.testing.expectEqual(@as(usize, storage.len), writer.clearCount());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
}
