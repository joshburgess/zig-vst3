const std = @import("std");
const common = @import("../common.zig");
const changes_mod = @import("changes.zig");
const events_mod = @import("events.zig");

pub const max_audio_channels = 64;

pub const BlockSegment = changes_mod.BlockSegment;
pub const BlockSegmentIterator = changes_mod.BlockSegmentIterator;
pub const ParameterChange = changes_mod.ParameterChange;
pub const ParameterChangeIdIterator = changes_mod.ParameterChangeIdIterator;
pub const ParameterChangeIdOffsetIterator = changes_mod.ParameterChangeIdOffsetIterator;
pub const ParameterChangeOffsetIterator = changes_mod.ParameterChangeOffsetIterator;
pub const ParameterChanges = changes_mod.ParameterChanges;
pub const ParameterSegment = changes_mod.ParameterSegment;
pub const ParameterSegmentIterator = changes_mod.ParameterSegmentIterator;
pub const Event = events_mod.Event;
pub const Events = events_mod.Events;
pub const EventWriter = events_mod.EventWriter;
pub const EventBlockSegmentIterator = events_mod.EventBlockSegmentIterator;
pub const EventBusChannelIterator = events_mod.EventBusChannelIterator;
pub const EventBusIterator = events_mod.EventBusIterator;
pub const EventChannelIterator = events_mod.EventChannelIterator;
pub const EventKind = events_mod.EventKind;
pub const EventKindIterator = events_mod.EventKindIterator;
pub const EventOffsetIterator = events_mod.EventOffsetIterator;

fn validateAudioChannels(channels: anytype) !usize {
    if (channels.len > max_audio_channels) return error.TooManyChannels;
    const frame_count = if (channels.len == 0) 0 else channels[0].len;
    for (channels) |channel_samples| {
        if (channel_samples.len != frame_count) return error.MismatchedFrameCount;
    }
    return frame_count;
}

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

pub fn AudioInputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: [max_audio_channels][]const Sample = [_][]const Sample{&.{}} ** max_audio_channels,
        channel_count: usize = 0,
        frame_count: usize = 0,

        pub fn init(channels: []const []const Sample) !Self {
            const frame_count = try validateAudioChannels(channels);
            var self = Self{
                .channel_count = channels.len,
                .frame_count = frame_count,
            };
            @memcpy(self.channels[0..channels.len], channels);
            return self;
        }

        pub fn channel(self: *const Self, index: usize) ?[]const Sample {
            if (index >= self.channelCount()) return null;
            return self.channels[index];
        }

        pub fn sample(self: *const Self, channel_index: usize, frame_index: usize) ?Sample {
            const channel_samples = self.channel(channel_index) orelse return null;
            if (frame_index >= channel_samples.len) return null;
            return channel_samples[frame_index];
        }

        pub fn hasChannel(self: *const Self, index: usize) bool {
            return self.channel(index) != null;
        }

        pub fn channelEmpty(self: *const Self, index: usize) bool {
            return !self.hasChannel(index);
        }

        pub fn channelCount(self: *const Self) usize {
            return @min(self.channel_count, max_audio_channels);
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.channelCount() == 0;
        }

        pub fn hasChannels(self: *const Self) bool {
            return self.channelCount() != 0;
        }

        pub fn frameCount(self: *const Self) usize {
            return self.frame_count;
        }
    };
}

pub fn AudioOutputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: [max_audio_channels][]Sample = [_][]Sample{&.{}} ** max_audio_channels,
        channel_count: usize = 0,
        frame_count: usize = 0,

        pub fn init(channels: []const []Sample) !Self {
            const frame_count = try validateAudioChannels(channels);
            var self = Self{
                .channel_count = channels.len,
                .frame_count = frame_count,
            };
            @memcpy(self.channels[0..channels.len], channels);
            return self;
        }

        pub fn channel(self: *const Self, index: usize) ?[]Sample {
            if (index >= self.channelCount()) return null;
            return self.channels[index];
        }

        pub fn sample(self: *const Self, channel_index: usize, frame_index: usize) ?Sample {
            const channel_samples = self.channel(channel_index) orelse return null;
            if (frame_index >= channel_samples.len) return null;
            return channel_samples[frame_index];
        }

        pub fn setSample(self: *const Self, channel_index: usize, frame_index: usize, value: Sample) bool {
            const channel_samples = self.channel(channel_index) orelse return false;
            if (frame_index >= channel_samples.len) return false;
            channel_samples[frame_index] = value;
            return true;
        }

        pub fn hasChannel(self: *const Self, index: usize) bool {
            return self.channel(index) != null;
        }

        pub fn channelEmpty(self: *const Self, index: usize) bool {
            return !self.hasChannel(index);
        }

        pub fn channelCount(self: *const Self) usize {
            return @min(self.channel_count, max_audio_channels);
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.channelCount() == 0;
        }

        pub fn hasChannels(self: *const Self) bool {
            return self.channelCount() != 0;
        }

        pub fn frameCount(self: *const Self) usize {
            return self.frame_count;
        }

        pub fn fill(self: *const Self, value: Sample) void {
            for (self.channels[0..self.channelCount()]) |channel_samples| {
                @memset(channel_samples, value);
            }
        }

        pub fn clear(self: *const Self) void {
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
        inputs: AudioInputs(Sample) = .{},
        outputs: AudioOutputs(Sample) = .{},
        parameter_changes: ParameterChanges = .{},
        events: Events = .{},
        output_events: ?*EventWriter = null,

        pub const InitOptions = struct {
            sample_rate: f64,
            input_channels: []const []const Sample = &.{},
            output_channels: []const []Sample = &.{},
            attachments: ProcessAttachments = .{},
        };

        pub fn init(sample_rate: f64, input_channels: []const []const Sample, output_channels: []const []Sample) !@This() {
            return @This().initWithOptions(.{
                .sample_rate = sample_rate,
                .input_channels = input_channels,
                .output_channels = output_channels,
            });
        }

        pub fn initWithOptions(options: InitOptions) !@This() {
            if (!common.isPositiveFinite(options.sample_rate)) {
                return error.InvalidSampleRate;
            }
            const inputs = try AudioInputs(Sample).init(options.input_channels);
            const outputs = try AudioOutputs(Sample).init(options.output_channels);
            if (!inputs.isEmpty() and !outputs.isEmpty() and inputs.frameCount() != outputs.frameCount()) {
                return error.MismatchedFrameCount;
            }
            var context = @This(){
                .sample_rate = options.sample_rate,
                .inputs = inputs,
                .outputs = outputs,
            };
            try context.setParameterChanges(options.attachments.parameter_changes);
            try context.setEvents(options.attachments.events);
            if (options.attachments.output_events) |writer| try context.setOutputEvents(writer);
            return context;
        }

        pub fn initWith(
            sample_rate: f64,
            input_channels: []const []const Sample,
            output_channels: []const []Sample,
            attachments: ProcessAttachments,
        ) !@This() {
            return @This().initWithOptions(.{
                .sample_rate = sample_rate,
                .input_channels = input_channels,
                .output_channels = output_channels,
                .attachments = attachments,
            });
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

        pub fn outputEventWriter(self: *const @This()) ?*EventWriter {
            return self.output_events;
        }

        pub fn sampleRate(self: *const @This()) f64 {
            return self.sample_rate;
        }

        pub fn sampleDurationSeconds(self: *const @This()) f64 {
            return 1.0 / self.sample_rate;
        }

        pub fn blockDurationSeconds(self: *const @This()) f64 {
            return @as(f64, @floatFromInt(self.frameCount())) / self.sample_rate;
        }

        pub fn blockSegment(self: *const @This()) BlockSegment {
            return .{ .start_offset = 0, .end_offset = self.frameCount() };
        }

        pub fn sampleOffsetSeconds(self: *const @This(), sample_offset: usize) f64 {
            return @as(f64, @floatFromInt(sample_offset)) / self.sample_rate;
        }

        pub fn containsSampleOffset(self: *const @This(), sample_offset: usize) bool {
            return sample_offset < self.frameCount();
        }

        pub fn isEndOffset(self: *const @This(), sample_offset: usize) bool {
            return sample_offset == self.frameCount();
        }

        pub fn isPastEndOffset(self: *const @This(), sample_offset: usize) bool {
            return sample_offset > self.frameCount();
        }

        pub fn remainingFramesFromOffset(self: *const @This(), sample_offset: usize) usize {
            return self.frameCount() -| sample_offset;
        }

        pub fn remainingSecondsFromOffset(self: *const @This(), sample_offset: usize) f64 {
            return @as(f64, @floatFromInt(self.remainingFramesFromOffset(sample_offset))) / self.sample_rate;
        }

        pub fn parameterChanges(self: *const @This()) ParameterChanges {
            return self.parameter_changes;
        }

        pub fn parameterChangesForId(self: *const @This(), id: u32) ParameterChangeIdIterator {
            return self.parameter_changes.forId(id);
        }

        pub fn parameterChangesAtOffset(self: *const @This(), sample_offset: usize) ParameterChangeOffsetIterator {
            return self.parameter_changes.atOffset(sample_offset);
        }

        pub fn parameterChangesForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) ParameterChangeIdOffsetIterator {
            return self.parameter_changes.forIdAtOffset(id, sample_offset);
        }

        pub fn parameterChangeCount(self: *const @This()) usize {
            return self.parameter_changes.changeCount();
        }

        pub fn parameterChangesEmpty(self: *const @This()) bool {
            return self.parameter_changes.isEmpty();
        }

        pub fn hasParameterChanges(self: *const @This()) bool {
            return self.parameter_changes.hasChanges();
        }

        pub fn firstParameterChangeOffset(self: *const @This()) ?usize {
            return self.parameter_changes.firstSampleOffset();
        }

        pub fn latestParameterChangeOffset(self: *const @This()) ?usize {
            return self.parameter_changes.latestSampleOffset();
        }

        pub fn firstParameterChangeOffsetForId(self: *const @This(), id: u32) ?usize {
            return self.parameter_changes.firstSampleOffsetForId(id);
        }

        pub fn latestParameterChangeOffsetForId(self: *const @This(), id: u32) ?usize {
            return self.parameter_changes.latestSampleOffsetForId(id);
        }

        pub fn firstAnyParameterChange(self: *const @This()) ?ParameterChange {
            return self.parameter_changes.firstChange();
        }

        pub fn latestAnyParameterChange(self: *const @This()) ?ParameterChange {
            return self.parameter_changes.latestChange();
        }

        pub fn firstAnyParameterNormalized(self: *const @This()) ?f64 {
            return self.parameter_changes.firstAnyNormalized();
        }

        pub fn latestAnyParameterNormalized(self: *const @This()) ?f64 {
            return self.parameter_changes.latestAnyNormalized();
        }

        pub fn firstAnyParameterNormalizedOr(self: *const @This(), default: f64) f64 {
            return self.parameter_changes.firstAnyNormalizedOr(default);
        }

        pub fn latestAnyParameterNormalizedOr(self: *const @This(), default: f64) f64 {
            return self.parameter_changes.latestAnyNormalizedOr(default);
        }

        pub fn latestParameterChange(self: *const @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.latest(id);
        }

        pub fn firstParameterChange(self: *const @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.first(id);
        }

        pub fn firstParameterChangeAtOffset(self: *const @This(), sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.firstAtOffset(sample_offset);
        }

        pub fn latestParameterChangeAtOffset(self: *const @This(), sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestAtOffset(sample_offset);
        }

        pub fn firstParameterChangeForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.firstForIdAtOffset(id, sample_offset);
        }

        pub fn latestParameterChangeForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestForIdAtOffset(id, sample_offset);
        }

        pub fn countParameterChanges(self: *const @This(), id: u32) usize {
            return self.parameter_changes.count(id);
        }

        pub fn countParameterChangesAtOffset(self: *const @This(), sample_offset: usize) usize {
            return self.parameter_changes.countAtOffset(sample_offset);
        }

        pub fn countParameterChangesForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) usize {
            return self.parameter_changes.countForIdAtOffset(id, sample_offset);
        }

        pub fn hasParameterChange(self: *const @This(), id: u32) bool {
            return self.parameter_changes.has(id);
        }

        pub fn hasParameterChangeAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.parameter_changes.hasAtOffset(sample_offset);
        }

        pub fn hasParameterChangeForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) bool {
            return self.parameter_changes.hasForIdAtOffset(id, sample_offset);
        }

        pub fn parameterChangesForIdEmpty(self: *const @This(), id: u32) bool {
            return self.parameter_changes.empty(id);
        }

        pub fn parameterChangesAtOffsetEmpty(self: *const @This(), sample_offset: usize) bool {
            return self.parameter_changes.offsetEmpty(sample_offset);
        }

        pub fn parameterChangesForIdAtOffsetEmpty(self: *const @This(), id: u32, sample_offset: usize) bool {
            return self.parameter_changes.idAtOffsetEmpty(id, sample_offset);
        }

        pub fn onlyParameterChangesForId(self: *const @This(), id: u32) bool {
            return self.parameter_changes.only(id);
        }

        pub fn onlyParameterChangesAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.parameter_changes.onlyAtOffset(sample_offset);
        }

        pub fn onlyParameterChangesForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) bool {
            return self.parameter_changes.onlyForIdAtOffset(id, sample_offset);
        }

        pub fn latestParameterNormalized(self: *const @This(), id: u32) ?f64 {
            return self.parameter_changes.latestNormalized(id);
        }

        pub fn firstParameterNormalized(self: *const @This(), id: u32) ?f64 {
            return self.parameter_changes.firstNormalized(id);
        }

        pub fn firstParameterNormalizedAtOffset(self: *const @This(), sample_offset: usize) ?f64 {
            return self.parameter_changes.firstNormalizedAtOffset(sample_offset);
        }

        pub fn latestParameterNormalizedAtOffset(self: *const @This(), sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedAtOffset(sample_offset);
        }

        pub fn firstParameterNormalizedForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.firstNormalizedForIdAtOffset(id, sample_offset);
        }

        pub fn latestParameterNormalizedForIdAtOffset(self: *const @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedForIdAtOffset(id, sample_offset);
        }

        pub fn firstParameterNormalizedAtOffsetOr(self: *const @This(), sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.firstNormalizedAtOffsetOr(sample_offset, default);
        }

        pub fn latestParameterNormalizedAtOffsetOr(self: *const @This(), sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.latestNormalizedAtOffsetOr(sample_offset, default);
        }

        pub fn firstParameterNormalizedForIdAtOffsetOr(self: *const @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.firstNormalizedForIdAtOffsetOr(id, sample_offset, default);
        }

        pub fn latestParameterNormalizedForIdAtOffsetOr(self: *const @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.latestNormalizedForIdAtOffsetOr(id, sample_offset, default);
        }

        pub fn firstParameterNormalizedOr(self: *const @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.firstNormalizedOr(id, default);
        }

        pub fn latestParameterNormalizedOr(self: *const @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.latestNormalizedOr(id, default);
        }

        pub fn latestParameterChangeAtOrBefore(self: *const @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestAtOrBefore(id, sample_offset);
        }

        pub fn latestParameterNormalizedAtOrBefore(self: *const @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedAtOrBefore(id, sample_offset);
        }

        pub fn parameterNormalizedAtOrBeforeOr(self: *const @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.normalizedAtOrBeforeOr(id, sample_offset, default);
        }

        pub fn nextParameterChangeOffset(self: *const @This(), after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffset(after_sample_offset);
        }

        pub fn nextParameterChangeOffsetForId(self: *const @This(), id: u32, after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffsetForId(id, after_sample_offset);
        }

        pub fn parameterSegmentAt(self: *const @This(), id: u32, start_offset: usize, default: f64) ?ParameterSegment {
            return self.parameter_changes.segmentAt(id, start_offset, self.frameCount(), default);
        }

        pub fn parameterSegments(self: *const @This(), id: u32, default: f64) ParameterSegmentIterator {
            return self.parameter_changes.segments(id, self.frameCount(), default);
        }

        pub fn parameterBlockSegments(self: *const @This()) BlockSegmentIterator {
            return self.parameter_changes.blockSegments(self.frameCount());
        }

        pub fn processBlockSegments(self: *const @This()) ProcessBlockSegmentIterator {
            return .{
                .parameter_changes = self.parameter_changes,
                .events = self.events,
                .frame_count = self.frameCount(),
            };
        }

        pub fn inputEvents(self: *const @This()) Events {
            return self.events;
        }

        pub fn inputEventsOfKind(self: *const @This(), kind: EventKind) EventKindIterator {
            return self.events.ofKind(kind);
        }

        pub fn inputEventsAtOffset(self: *const @This(), sample_offset: usize) EventOffsetIterator {
            return self.events.atOffset(sample_offset);
        }

        pub fn inputEventsForBus(self: *const @This(), bus_index: i32) EventBusIterator {
            return self.events.forBus(bus_index);
        }

        pub fn inputEventsForChannel(self: *const @This(), channel: i16) EventChannelIterator {
            return self.events.forChannel(channel);
        }

        pub fn inputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) EventBusChannelIterator {
            return self.events.forBusChannel(bus_index, channel);
        }

        pub fn inputEventBlockSegments(self: *const @This()) EventBlockSegmentIterator {
            return self.events.blockSegments(self.frameCount());
        }

        pub fn eventBlockSegments(self: *const @This()) EventBlockSegmentIterator {
            return self.inputEventBlockSegments();
        }

        pub fn inputEventCount(self: *const @This()) usize {
            return self.events.eventCount();
        }

        pub fn eventCount(self: *const @This()) usize {
            return self.inputEventCount();
        }

        pub fn inputEventsEmpty(self: *const @This()) bool {
            return self.events.isEmpty();
        }

        pub fn eventsEmpty(self: *const @This()) bool {
            return self.inputEventsEmpty();
        }

        pub fn hasInputEvents(self: *const @This()) bool {
            return self.events.hasEvents();
        }

        pub fn hasEvents(self: *const @This()) bool {
            return self.hasInputEvents();
        }

        pub fn firstEventOffset(self: *const @This()) ?usize {
            return self.events.firstSampleOffset();
        }

        pub fn firstInputEventOffset(self: *const @This()) ?usize {
            return self.firstEventOffset();
        }

        pub fn latestEventOffset(self: *const @This()) ?usize {
            return self.events.latestSampleOffset();
        }

        pub fn latestInputEventOffset(self: *const @This()) ?usize {
            return self.latestEventOffset();
        }

        pub fn firstInputEvent(self: *const @This()) ?Event {
            return self.events.first();
        }

        pub fn latestInputEvent(self: *const @This()) ?Event {
            return self.events.latest();
        }

        pub fn firstEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.events.firstAtOffset(sample_offset);
        }

        pub fn firstInputEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.firstEventAtOffset(sample_offset);
        }

        pub fn latestEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.events.latestAtOffset(sample_offset);
        }

        pub fn latestInputEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.latestEventAtOffset(sample_offset);
        }

        pub fn firstEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            return self.events.firstSampleOffsetForKind(kind);
        }

        pub fn firstInputEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            return self.firstEventOffsetForKind(kind);
        }

        pub fn latestEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            return self.events.latestSampleOffsetForKind(kind);
        }

        pub fn latestInputEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            return self.latestEventOffsetForKind(kind);
        }

        pub fn firstEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.events.firstSampleOffsetForBus(bus_index);
        }

        pub fn firstInputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.firstEventOffsetForBus(bus_index);
        }

        pub fn latestEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.events.latestSampleOffsetForBus(bus_index);
        }

        pub fn latestInputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.latestEventOffsetForBus(bus_index);
        }

        pub fn firstEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.events.firstSampleOffsetForChannel(channel);
        }

        pub fn firstInputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.firstEventOffsetForChannel(channel);
        }

        pub fn latestEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.events.latestSampleOffsetForChannel(channel);
        }

        pub fn latestInputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.latestEventOffsetForChannel(channel);
        }

        pub fn firstEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.events.firstSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn firstInputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.firstEventOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.events.latestSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestInputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.latestEventOffsetForBusChannel(bus_index, channel);
        }

        pub fn firstEvent(self: *const @This(), kind: EventKind) ?Event {
            return self.events.firstKind(kind);
        }

        pub fn firstInputEventOfKind(self: *const @This(), kind: EventKind) ?Event {
            return self.firstEvent(kind);
        }

        pub fn latestEvent(self: *const @This(), kind: EventKind) ?Event {
            return self.events.latestKind(kind);
        }

        pub fn latestInputEventOfKind(self: *const @This(), kind: EventKind) ?Event {
            return self.latestEvent(kind);
        }

        pub fn firstEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.events.firstKindAtOffset(kind, sample_offset);
        }

        pub fn firstInputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.firstEventOfKindAtOffset(kind, sample_offset);
        }

        pub fn latestEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.events.latestKindAtOffset(kind, sample_offset);
        }

        pub fn latestInputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.latestEventOfKindAtOffset(kind, sample_offset);
        }

        pub fn firstEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.events.firstBus(bus_index);
        }

        pub fn firstInputEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.firstEventForBus(bus_index);
        }

        pub fn latestEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.events.latestBus(bus_index);
        }

        pub fn latestInputEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.latestEventForBus(bus_index);
        }

        pub fn firstEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.events.firstChannel(channel);
        }

        pub fn firstInputEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.firstEventForChannel(channel);
        }

        pub fn latestEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.events.latestChannel(channel);
        }

        pub fn latestInputEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.latestEventForChannel(channel);
        }

        pub fn firstEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.events.firstBusChannel(bus_index, channel);
        }

        pub fn firstInputEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.firstEventForBusChannel(bus_index, channel);
        }

        pub fn latestEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.events.latestBusChannel(bus_index, channel);
        }

        pub fn latestInputEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.latestEventForBusChannel(bus_index, channel);
        }

        pub fn hasEvent(self: *const @This(), kind: EventKind) bool {
            return self.events.hasKind(kind);
        }

        pub fn hasInputEvent(self: *const @This(), kind: EventKind) bool {
            return self.hasEvent(kind);
        }

        pub fn eventsOfKindEmpty(self: *const @This(), kind: EventKind) bool {
            return self.events.kindEmpty(kind);
        }

        pub fn inputEventsOfKindEmpty(self: *const @This(), kind: EventKind) bool {
            return self.eventsOfKindEmpty(kind);
        }

        pub fn countEvents(self: *const @This(), kind: EventKind) usize {
            return self.events.countKind(kind);
        }

        pub fn countInputEvents(self: *const @This(), kind: EventKind) usize {
            return self.countEvents(kind);
        }

        pub fn countNoteAttacks(self: *const @This()) usize {
            return self.events.countNoteAttacks();
        }

        pub fn countInputNoteAttacks(self: *const @This()) usize {
            return self.countNoteAttacks();
        }

        pub fn countNoteReleases(self: *const @This()) usize {
            return self.events.countNoteReleases();
        }

        pub fn countInputNoteReleases(self: *const @This()) usize {
            return self.countNoteReleases();
        }

        pub fn countEventsAtOffset(self: *const @This(), sample_offset: usize) usize {
            return self.events.countAtOffset(sample_offset);
        }

        pub fn countInputEventsAtOffset(self: *const @This(), sample_offset: usize) usize {
            return self.countEventsAtOffset(sample_offset);
        }

        pub fn countEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) usize {
            return self.events.countKindAtOffset(kind, sample_offset);
        }

        pub fn countInputEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) usize {
            return self.countEventsOfKindAtOffset(kind, sample_offset);
        }

        pub fn countEventsForBus(self: *const @This(), bus_index: i32) usize {
            return self.events.countBus(bus_index);
        }

        pub fn countInputEventsForBus(self: *const @This(), bus_index: i32) usize {
            return self.countEventsForBus(bus_index);
        }

        pub fn countEventsForChannel(self: *const @This(), channel: i16) usize {
            return self.events.countChannel(channel);
        }

        pub fn countInputEventsForChannel(self: *const @This(), channel: i16) usize {
            return self.countEventsForChannel(channel);
        }

        pub fn countEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) usize {
            return self.events.countBusChannel(bus_index, channel);
        }

        pub fn countInputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) usize {
            return self.countEventsForBusChannel(bus_index, channel);
        }

        pub fn hasEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.events.hasBus(bus_index);
        }

        pub fn hasInputEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.hasEventsForBus(bus_index);
        }

        pub fn eventsForBusEmpty(self: *const @This(), bus_index: i32) bool {
            return self.events.busEmpty(bus_index);
        }

        pub fn inputEventsForBusEmpty(self: *const @This(), bus_index: i32) bool {
            return self.eventsForBusEmpty(bus_index);
        }

        pub fn hasEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.events.hasChannel(channel);
        }

        pub fn hasInputEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.hasEventsForChannel(channel);
        }

        pub fn hasEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.events.hasBusChannel(bus_index, channel);
        }

        pub fn hasInputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.hasEventsForBusChannel(bus_index, channel);
        }

        pub fn hasEventAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.events.hasAtOffset(sample_offset);
        }

        pub fn hasInputEventAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.hasEventAtOffset(sample_offset);
        }

        pub fn hasEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.hasKindAtOffset(kind, sample_offset);
        }

        pub fn hasInputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.hasEventOfKindAtOffset(kind, sample_offset);
        }

        pub fn hasNoteAttacks(self: *const @This()) bool {
            return self.events.hasNoteAttacks();
        }

        pub fn hasInputNoteAttacks(self: *const @This()) bool {
            return self.hasNoteAttacks();
        }

        pub fn hasNoteReleases(self: *const @This()) bool {
            return self.events.hasNoteReleases();
        }

        pub fn hasInputNoteReleases(self: *const @This()) bool {
            return self.hasNoteReleases();
        }

        pub fn eventsForChannelEmpty(self: *const @This(), channel: i16) bool {
            return self.events.channelEmpty(channel);
        }

        pub fn inputEventsForChannelEmpty(self: *const @This(), channel: i16) bool {
            return self.eventsForChannelEmpty(channel);
        }

        pub fn eventsForBusChannelEmpty(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.events.busChannelEmpty(bus_index, channel);
        }

        pub fn inputEventsForBusChannelEmpty(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.eventsForBusChannelEmpty(bus_index, channel);
        }

        pub fn eventsAtOffsetEmpty(self: *const @This(), sample_offset: usize) bool {
            return self.events.offsetEmpty(sample_offset);
        }

        pub fn inputEventsAtOffsetEmpty(self: *const @This(), sample_offset: usize) bool {
            return self.eventsAtOffsetEmpty(sample_offset);
        }

        pub fn eventsOfKindAtOffsetEmpty(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.kindAtOffsetEmpty(kind, sample_offset);
        }

        pub fn inputEventsOfKindAtOffsetEmpty(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.eventsOfKindAtOffsetEmpty(kind, sample_offset);
        }

        pub fn onlyEventsAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.events.onlyAtOffset(sample_offset);
        }

        pub fn onlyInputEventsAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.onlyEventsAtOffset(sample_offset);
        }

        pub fn onlyEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.events.onlyKindAtOffset(kind, sample_offset);
        }

        pub fn onlyInputEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.onlyEventsOfKindAtOffset(kind, sample_offset);
        }

        pub fn noteAttacksEmpty(self: *const @This()) bool {
            return self.events.noteAttacksEmpty();
        }

        pub fn inputNoteAttacksEmpty(self: *const @This()) bool {
            return self.noteAttacksEmpty();
        }

        pub fn noteReleasesEmpty(self: *const @This()) bool {
            return self.events.noteReleasesEmpty();
        }

        pub fn inputNoteReleasesEmpty(self: *const @This()) bool {
            return self.noteReleasesEmpty();
        }

        pub fn onlyEventsOfKind(self: *const @This(), kind: EventKind) bool {
            return self.events.onlyKind(kind);
        }

        pub fn onlyInputEventsOfKind(self: *const @This(), kind: EventKind) bool {
            return self.onlyEventsOfKind(kind);
        }

        pub fn onlyNoteAttacks(self: *const @This()) bool {
            return self.events.onlyNoteAttacks();
        }

        pub fn onlyInputNoteAttacks(self: *const @This()) bool {
            return self.onlyNoteAttacks();
        }

        pub fn onlyNoteReleases(self: *const @This()) bool {
            return self.events.onlyNoteReleases();
        }

        pub fn onlyInputNoteReleases(self: *const @This()) bool {
            return self.onlyNoteReleases();
        }

        pub fn onlyEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.events.onlyBus(bus_index);
        }

        pub fn onlyInputEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.onlyEventsForBus(bus_index);
        }

        pub fn onlyEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.events.onlyChannel(channel);
        }

        pub fn onlyInputEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.onlyEventsForChannel(channel);
        }

        pub fn onlyEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.events.onlyBusChannel(bus_index, channel);
        }

        pub fn onlyInputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.onlyEventsForBusChannel(bus_index, channel);
        }

        pub fn nextEventOffset(self: *const @This(), after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffset(after_sample_offset);
        }

        pub fn nextInputEventOffset(self: *const @This(), after_sample_offset: usize) ?usize {
            return self.nextEventOffset(after_sample_offset);
        }

        pub fn nextEventOffsetForKind(self: *const @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForKind(kind, after_sample_offset);
        }

        pub fn nextInputEventOffsetForKind(self: *const @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.nextEventOffsetForKind(kind, after_sample_offset);
        }

        pub fn nextEventOffsetForBus(self: *const @This(), bus_index: i32, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForBus(bus_index, after_sample_offset);
        }

        pub fn nextInputEventOffsetForBus(self: *const @This(), bus_index: i32, after_sample_offset: usize) ?usize {
            return self.nextEventOffsetForBus(bus_index, after_sample_offset);
        }

        pub fn nextEventOffsetForChannel(self: *const @This(), channel: i16, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForChannel(channel, after_sample_offset);
        }

        pub fn nextInputEventOffsetForChannel(self: *const @This(), channel: i16, after_sample_offset: usize) ?usize {
            return self.nextEventOffsetForChannel(channel, after_sample_offset);
        }

        pub fn nextEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForBusChannel(bus_index, channel, after_sample_offset);
        }

        pub fn nextInputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
            return self.nextEventOffsetForBusChannel(bus_index, channel, after_sample_offset);
        }

        pub fn appendOutputEvent(self: *@This(), event: Event) !void {
            _ = try self.appendOutputEventCount(event);
        }

        pub fn appendOutputEventCount(self: *@This(), event: Event) !usize {
            const writer = self.outputEventWriter() orelse return error.OutputEventsUnavailable;
            return writer.appendCount(event);
        }

        pub fn appendOutputEvents(self: *@This(), events: Events) !void {
            _ = try self.appendOutputEventsCount(events);
        }

        pub fn appendOutputEventsCount(self: *@This(), events: Events) !usize {
            const writer = self.outputEventWriter() orelse return error.OutputEventsUnavailable;
            return writer.appendAllCount(events);
        }

        pub fn canAppendOutputEvent(self: *const @This()) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.canAppend(1);
        }

        pub fn canAppendOutputEvents(self: *const @This(), event_count: usize) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.canAppend(event_count);
        }

        pub fn canAppendOutputEventValue(self: *const @This(), event: Event) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.canAppendEvent(event);
        }

        pub fn canAppendOutputEventValues(self: *const @This(), events: Events) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.canAppendEvents(events);
        }

        pub fn writtenOutputEvents(self: *const @This()) Events {
            const writer = self.outputEventWriter() orelse return .{};
            return writer.events();
        }

        pub fn outputEvents(self: *const @This()) Events {
            return self.writtenOutputEvents();
        }

        pub fn outputEventBlockSegments(self: *const @This()) EventBlockSegmentIterator {
            const writer = self.outputEventWriter() orelse return (Events{}).blockSegments(self.frameCount());
            return writer.blockSegments();
        }

        pub fn outputEventsAtOffset(self: *const @This(), sample_offset: usize) EventOffsetIterator {
            return self.writtenOutputEvents().atOffset(sample_offset);
        }

        pub fn outputEventsOfKind(self: *const @This(), kind: EventKind) EventKindIterator {
            return self.writtenOutputEvents().ofKind(kind);
        }

        pub fn outputEventsForBus(self: *const @This(), bus_index: i32) EventBusIterator {
            return self.writtenOutputEvents().forBus(bus_index);
        }

        pub fn outputEventsForChannel(self: *const @This(), channel: i16) EventChannelIterator {
            return self.writtenOutputEvents().forChannel(channel);
        }

        pub fn outputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) EventBusChannelIterator {
            return self.writtenOutputEvents().forBusChannel(bus_index, channel);
        }

        pub fn firstOutputEventOffset(self: *const @This()) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.firstSampleOffset();
        }

        pub fn latestOutputEventOffset(self: *const @This()) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.latestSampleOffset();
        }

        pub fn firstWrittenOutputEvent(self: *const @This()) ?Event {
            return self.writtenOutputEvents().first();
        }

        pub fn latestWrittenOutputEvent(self: *const @This()) ?Event {
            return self.writtenOutputEvents().latest();
        }

        pub fn firstOutputEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.writtenOutputEvents().firstAtOffset(sample_offset);
        }

        pub fn latestOutputEventAtOffset(self: *const @This(), sample_offset: usize) ?Event {
            return self.writtenOutputEvents().latestAtOffset(sample_offset);
        }

        pub fn firstOutputEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.firstSampleOffsetForKind(kind);
        }

        pub fn latestOutputEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.latestSampleOffsetForKind(kind);
        }

        pub fn firstOutputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.firstSampleOffsetForBus(bus_index);
        }

        pub fn latestOutputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.latestSampleOffsetForBus(bus_index);
        }

        pub fn firstOutputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.firstSampleOffsetForChannel(channel);
        }

        pub fn latestOutputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.latestSampleOffsetForChannel(channel);
        }

        pub fn firstOutputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.firstSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestOutputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            const writer = self.outputEventWriter() orelse return null;
            return writer.latestSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn firstOutputEvent(self: *const @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().firstKind(kind);
        }

        pub fn firstOutputEventOfKind(self: *const @This(), kind: EventKind) ?Event {
            return self.firstOutputEvent(kind);
        }

        pub fn latestOutputEvent(self: *const @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().latestKind(kind);
        }

        pub fn latestOutputEventOfKind(self: *const @This(), kind: EventKind) ?Event {
            return self.latestOutputEvent(kind);
        }

        pub fn firstOutputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.writtenOutputEvents().firstKindAtOffset(kind, sample_offset);
        }

        pub fn latestOutputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) ?Event {
            return self.writtenOutputEvents().latestKindAtOffset(kind, sample_offset);
        }

        pub fn firstOutputEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.writtenOutputEvents().firstBus(bus_index);
        }

        pub fn latestOutputEventForBus(self: *const @This(), bus_index: i32) ?Event {
            return self.writtenOutputEvents().latestBus(bus_index);
        }

        pub fn firstOutputEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.writtenOutputEvents().firstChannel(channel);
        }

        pub fn latestOutputEventForChannel(self: *const @This(), channel: i16) ?Event {
            return self.writtenOutputEvents().latestChannel(channel);
        }

        pub fn firstOutputEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.writtenOutputEvents().firstBusChannel(bus_index, channel);
        }

        pub fn latestOutputEventForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?Event {
            return self.writtenOutputEvents().latestBusChannel(bus_index, channel);
        }

        pub fn hasOutputEvent(self: *const @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().hasKind(kind);
        }

        pub fn outputEventsOfKindEmpty(self: *const @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().kindEmpty(kind);
        }

        pub fn countOutputEvents(self: *const @This(), kind: EventKind) usize {
            return self.writtenOutputEvents().countKind(kind);
        }

        pub fn countOutputNoteAttacks(self: *const @This()) usize {
            return self.writtenOutputEvents().countNoteAttacks();
        }

        pub fn countOutputNoteReleases(self: *const @This()) usize {
            return self.writtenOutputEvents().countNoteReleases();
        }

        pub fn countOutputEventsAtOffset(self: *const @This(), sample_offset: usize) usize {
            return self.writtenOutputEvents().countAtOffset(sample_offset);
        }

        pub fn countOutputEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) usize {
            return self.writtenOutputEvents().countKindAtOffset(kind, sample_offset);
        }

        pub fn countOutputEventsForBus(self: *const @This(), bus_index: i32) usize {
            return self.writtenOutputEvents().countBus(bus_index);
        }

        pub fn countOutputEventsForChannel(self: *const @This(), channel: i16) usize {
            return self.writtenOutputEvents().countChannel(channel);
        }

        pub fn countOutputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) usize {
            return self.writtenOutputEvents().countBusChannel(bus_index, channel);
        }

        pub fn hasOutputEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().hasBus(bus_index);
        }

        pub fn outputEventsForBusEmpty(self: *const @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().busEmpty(bus_index);
        }

        pub fn hasOutputEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.writtenOutputEvents().hasChannel(channel);
        }

        pub fn hasOutputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().hasBusChannel(bus_index, channel);
        }

        pub fn hasOutputEventAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().hasAtOffset(sample_offset);
        }

        pub fn hasOutputEventOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().hasKindAtOffset(kind, sample_offset);
        }

        pub fn hasOutputNoteAttacks(self: *const @This()) bool {
            return self.writtenOutputEvents().hasNoteAttacks();
        }

        pub fn hasOutputNoteReleases(self: *const @This()) bool {
            return self.writtenOutputEvents().hasNoteReleases();
        }

        pub fn outputEventsForChannelEmpty(self: *const @This(), channel: i16) bool {
            return self.writtenOutputEvents().channelEmpty(channel);
        }

        pub fn outputEventsForBusChannelEmpty(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().busChannelEmpty(bus_index, channel);
        }

        pub fn outputEventsAtOffsetEmpty(self: *const @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().offsetEmpty(sample_offset);
        }

        pub fn outputEventsOfKindAtOffsetEmpty(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().kindAtOffsetEmpty(kind, sample_offset);
        }

        pub fn onlyOutputEventsAtOffset(self: *const @This(), sample_offset: usize) bool {
            return self.writtenOutputEvents().onlyAtOffset(sample_offset);
        }

        pub fn onlyOutputEventsOfKindAtOffset(self: *const @This(), kind: EventKind, sample_offset: usize) bool {
            return self.writtenOutputEvents().onlyKindAtOffset(kind, sample_offset);
        }

        pub fn outputNoteAttacksEmpty(self: *const @This()) bool {
            return self.writtenOutputEvents().noteAttacksEmpty();
        }

        pub fn outputNoteReleasesEmpty(self: *const @This()) bool {
            return self.writtenOutputEvents().noteReleasesEmpty();
        }

        pub fn onlyOutputEventsOfKind(self: *const @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().onlyKind(kind);
        }

        pub fn onlyOutputNoteAttacks(self: *const @This()) bool {
            return self.writtenOutputEvents().onlyNoteAttacks();
        }

        pub fn onlyOutputNoteReleases(self: *const @This()) bool {
            return self.writtenOutputEvents().onlyNoteReleases();
        }

        pub fn onlyOutputEventsForBus(self: *const @This(), bus_index: i32) bool {
            return self.writtenOutputEvents().onlyBus(bus_index);
        }

        pub fn onlyOutputEventsForChannel(self: *const @This(), channel: i16) bool {
            return self.writtenOutputEvents().onlyChannel(channel);
        }

        pub fn onlyOutputEventsForBusChannel(self: *const @This(), bus_index: i32, channel: i16) bool {
            return self.writtenOutputEvents().onlyBusChannel(bus_index, channel);
        }

        pub fn nextOutputEventOffset(self: *const @This(), after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffset(after_sample_offset);
        }

        pub fn nextOutputEventOffsetForKind(self: *const @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForKind(kind, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForBus(self: *const @This(), bus_index: i32, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForBus(bus_index, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForChannel(self: *const @This(), channel: i16, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForChannel(channel, after_sample_offset);
        }

        pub fn nextOutputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForBusChannel(bus_index, channel, after_sample_offset);
        }

        pub fn clearOutputEvents(self: *const @This()) void {
            _ = self.clearOutputEventsCount();
        }

        pub fn clearOutputEventsCount(self: *const @This()) usize {
            const writer = self.outputEventWriter() orelse return 0;
            return writer.clearCount();
        }

        pub fn hasOutputEventWriter(self: *const @This()) bool {
            return self.outputEventWriter() != null;
        }

        pub fn outputEventCount(self: *const @This()) usize {
            const writer = self.outputEventWriter() orelse return 0;
            return writer.eventCount();
        }

        pub fn outputEventCapacity(self: *const @This()) usize {
            const writer = self.outputEventWriter() orelse return 0;
            return writer.capacity();
        }

        pub fn outputEventRemainingCapacity(self: *const @This()) usize {
            const writer = self.outputEventWriter() orelse return 0;
            return writer.remainingCapacity();
        }

        pub fn outputEventFrameCount(self: *const @This()) usize {
            const writer = self.outputEventWriter() orelse return 0;
            return writer.frameCount();
        }

        pub fn outputEventsEmpty(self: *const @This()) bool {
            const writer = self.outputEventWriter() orelse return true;
            return writer.isEmpty();
        }

        pub fn hasOutputEvents(self: *const @This()) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.hasEvents();
        }

        pub fn outputEventsFull(self: *const @This()) bool {
            const writer = self.outputEventWriter() orelse return true;
            return writer.isFull();
        }

        pub fn inputAudio(self: *const @This()) AudioInputs(Sample) {
            return self.inputs;
        }

        pub fn outputAudio(self: *const @This()) AudioOutputs(Sample) {
            return self.outputs;
        }

        pub fn fillOutputs(self: *const @This(), value: Sample) void {
            self.outputs.fill(value);
        }

        pub fn clearOutputs(self: *const @This()) void {
            self.outputs.clear();
        }

        pub fn inputChannel(self: *const @This(), index: usize) ?[]const Sample {
            return self.inputs.channel(index);
        }

        pub fn outputChannel(self: *const @This(), index: usize) ?[]Sample {
            return self.outputs.channel(index);
        }

        pub fn inputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.inputs.sample(channel_index, frame_index);
        }

        pub fn outputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.outputs.sample(channel_index, frame_index);
        }

        pub fn setOutputSample(self: *const @This(), channel_index: usize, frame_index: usize, value: Sample) bool {
            return self.outputs.setSample(channel_index, frame_index, value);
        }

        pub fn hasInputChannel(self: *const @This(), index: usize) bool {
            return self.inputs.hasChannel(index);
        }

        pub fn inputChannelEmpty(self: *const @This(), index: usize) bool {
            return self.inputs.channelEmpty(index);
        }

        pub fn hasOutputChannel(self: *const @This(), index: usize) bool {
            return self.outputs.hasChannel(index);
        }

        pub fn outputChannelEmpty(self: *const @This(), index: usize) bool {
            return self.outputs.channelEmpty(index);
        }

        pub fn inputChannelCount(self: *const @This()) usize {
            return self.inputs.channelCount();
        }

        pub fn outputChannelCount(self: *const @This()) usize {
            return self.outputs.channelCount();
        }

        pub fn inputChannelsEmpty(self: *const @This()) bool {
            return self.inputs.isEmpty();
        }

        pub fn hasInputChannels(self: *const @This()) bool {
            return self.inputs.hasChannels();
        }

        pub fn outputChannelsEmpty(self: *const @This()) bool {
            return self.outputs.isEmpty();
        }

        pub fn hasOutputChannels(self: *const @This()) bool {
            return self.outputs.hasChannels();
        }

        pub fn inputFrameCount(self: *const @This()) usize {
            return self.inputs.frameCount();
        }

        pub fn outputFrameCount(self: *const @This()) usize {
            return self.outputs.frameCount();
        }

        pub fn frameCount(self: *const @This()) usize {
            if (self.inputChannelCount() == 0) return self.outputFrameCount();
            if (self.outputChannelCount() == 0) return self.inputFrameCount();
            return self.inputFrameCount();
        }
    };
}
test "audio input view validates channel frame counts" {
    const left = [_]f32{ 0.1, 0.2 };
    const right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]const f32{ &left, &right };
    const inputs = try AudioInputs(f32).init(&channels);

    try std.testing.expectEqual(@as(usize, 2), inputs.channelCount());
    try std.testing.expect(!inputs.isEmpty());
    try std.testing.expect(inputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 2), inputs.frame_count);
    try std.testing.expectEqual(@as(usize, 2), inputs.frameCount());
    try std.testing.expectEqual(@as(f32, 0.3), inputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?f32, 0.4), inputs.sample(1, 1));
    try std.testing.expectEqual(@as(?f32, null), inputs.sample(1, 2));
    try std.testing.expectEqual(@as(?f32, null), inputs.sample(2, 0));
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

test "audio input view keeps its own channel slice headers" {
    const left = [_]f32{ 0.1, 0.2 };
    const right = [_]f32{ 0.3, 0.4 };
    const replacement = [_]f32{ 9.0, 9.0 };
    var channels = [_][]const f32{ &left, &right };
    const inputs = try AudioInputs(f32).init(&channels);

    channels[1] = &replacement;

    try std.testing.expectEqual(@as(f32, 0.3), inputs.channel(1).?[0]);
}

test "audio views reject too many channels" {
    const input_samples = [_]f32{};
    var input_channels: [max_audio_channels + 1][]const f32 = undefined;
    for (&input_channels) |*channel| channel.* = &input_samples;

    var output_samples = [_]f32{};
    var output_channels: [max_audio_channels + 1][]f32 = undefined;
    for (&output_channels) |*channel| channel.* = &output_samples;

    try std.testing.expectError(error.TooManyChannels, AudioInputs(f32).init(&input_channels));
    try std.testing.expectError(error.TooManyChannels, AudioOutputs(f32).init(&output_channels));
}

test "audio views clamp corrupted channel counts" {
    const input_samples = [_]f32{ 0.1, 0.2 };
    var output_samples = [_]f32{ 0.3, 0.4 };
    const input_channels = [_][]const f32{&input_samples};
    const output_channels = [_][]f32{&output_samples};

    var inputs = try AudioInputs(f32).init(&input_channels);
    inputs.channel_count = max_audio_channels + 1;
    try std.testing.expectEqual(@as(usize, max_audio_channels), inputs.channelCount());
    try std.testing.expect(inputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 0), inputs.channel(1).?.len);
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(max_audio_channels));

    var outputs = try AudioOutputs(f32).init(&output_channels);
    outputs.channel_count = max_audio_channels + 1;
    try std.testing.expectEqual(@as(usize, max_audio_channels), outputs.channelCount());
    try std.testing.expect(outputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 0), outputs.channel(1).?.len);
    try std.testing.expectEqual(@as(?[]f32, null), outputs.channel(max_audio_channels));
    outputs.fill(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), output_samples[0]);
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
    try std.testing.expectEqual(@as(?f32, 0.3), outputs.sample(1, 0));
    try std.testing.expect(outputs.setSample(1, 0, 0.8));
    try std.testing.expectEqual(@as(?f32, 0.8), outputs.sample(1, 0));
    try std.testing.expectEqual(@as(f32, 0.8), right[0]);
    try std.testing.expect(!outputs.setSample(1, 2, 0.9));
    try std.testing.expect(!outputs.setSample(2, 0, 0.9));
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

test "audio output view keeps its own channel slice headers" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{ 0.3, 0.4 };
    var replacement = [_]f32{ 9.0, 9.0 };
    var channels = [_][]f32{ &left, &right };
    const outputs = try AudioOutputs(f32).init(&channels);

    channels[1] = &replacement;
    try std.testing.expect(outputs.setSample(1, 0, 0.8));

    try std.testing.expectEqual(@as(f32, 0.8), right[0]);
    try std.testing.expectEqual(@as(f32, 9.0), replacement[0]);
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
    const input_audio = context.inputAudio();
    const output_audio = context.outputAudio();
    try std.testing.expectEqual(@as(usize, 2), input_audio.channelCount());
    try std.testing.expectEqual(@as(usize, 2), output_audio.channelCount());
    try std.testing.expectEqual(@as(f64, 0.4), input_audio.channel(1).?[0]);
    try std.testing.expectEqual(@as(?f64, 0.5), input_audio.sample(1, 1));
    try std.testing.expectEqual(@as(f64, 0.0), output_audio.channel(1).?[0]);
    try std.testing.expectEqual(@as(?f64, 0.0), output_audio.sample(1, 1));
    try std.testing.expect(!context.inputChannelsEmpty());
    try std.testing.expect(!context.outputChannelsEmpty());
    try std.testing.expect(context.hasInputChannels());
    try std.testing.expect(context.hasOutputChannels());
    try std.testing.expectEqual(@as(f64, 0.4), context.inputChannel(1).?[0]);
    try std.testing.expectEqual(@as(?f64, 0.5), context.inputSample(1, 1));
    try std.testing.expectEqual(@as(?f64, null), context.inputSample(1, 3));
    try std.testing.expectEqual(@as(?f64, null), context.inputSample(2, 0));
    try std.testing.expect(context.hasInputChannel(1));
    try std.testing.expect(!context.inputChannelEmpty(1));
    try std.testing.expectEqual(@as(?[]const f64, null), context.inputChannel(2));
    try std.testing.expect(!context.hasInputChannel(2));
    try std.testing.expect(context.inputChannelEmpty(2));
    try std.testing.expectEqual(@as(f64, 0.0), context.outputChannel(1).?[0]);
    try std.testing.expectEqual(@as(?f64, 0.0), context.outputSample(1, 1));
    try std.testing.expect(context.setOutputSample(1, 1, 0.25));
    try std.testing.expectEqual(@as(?f64, 0.25), context.outputSample(1, 1));
    try std.testing.expectEqual(@as(f64, 0.25), out_right[1]);
    try std.testing.expect(!context.setOutputSample(1, 3, 0.5));
    try std.testing.expect(!context.setOutputSample(2, 0, 0.5));
    try std.testing.expect(context.hasOutputChannel(1));
    try std.testing.expect(!context.outputChannelEmpty(1));
    try std.testing.expectEqual(@as(?[]f64, null), context.outputChannel(2));
    try std.testing.expect(!context.hasOutputChannel(2));
    try std.testing.expect(context.outputChannelEmpty(2));
    try std.testing.expectEqual(@as(?f64, null), context.firstAnyParameterNormalized());
    try std.testing.expectEqual(@as(?f64, null), context.latestAnyParameterNormalized());
    try std.testing.expectEqual(@as(f64, 0.25), context.firstAnyParameterNormalizedOr(0.25));
    try std.testing.expectEqual(@as(f64, 0.75), context.latestAnyParameterNormalizedOr(0.75));

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

test "process context supports named init options" {
    const input = [_]f32{ 0.1, 0.2, 0.3 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const parameter_changes = [_]ParameterChange{.{ .id = 7, .sample_offset = 1, .normalized = 0.25 }};
    const events = [_]Event{Event.noteOn(2, 0, 60, 0.5)};
    var output_event_storage: [1]Event = undefined;
    var output_events = EventWriter.init(&output_event_storage, output.len);

    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 44_100.0,
        .input_channels = &input_channels,
        .output_channels = &output_channels,
        .attachments = .{
            .parameter_changes = &parameter_changes,
            .events = &events,
            .output_events = &output_events,
        },
    });

    try std.testing.expectEqual(@as(f64, 44_100.0), context.sampleRate());
    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
    try std.testing.expectEqual(@as(usize, 1), context.parameterChangeCount());
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try std.testing.expect(context.outputEventWriter() != null);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCapacity());
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
    try std.testing.expect(output_only.outputEventWriter().? == &output_writer);

    const input_only = try ProcessContext(f32).initWith(48_000.0, &input_channels, &no_output_channels, .{
        .parameter_changes = &input_changes,
        .events = &input_events,
        .output_events = &input_writer,
    });
    try std.testing.expectEqual(@as(usize, input.len), input_only.frameCount());
    try std.testing.expectEqual(@as(?usize, 2), input_only.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 2), input_only.latestEventOffset());
    try std.testing.expect(input_only.hasOutputEventWriter());
    try std.testing.expect(input_only.outputEventWriter().? == &input_writer);
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
    try std.testing.expectEqual(@as(f64, 0.5), context.firstAnyParameterNormalizedOr(0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestAnyParameterNormalizedOr(0.25));
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
    try std.testing.expect(context.onlyParameterChangesAtOffset(1));
    try std.testing.expect(!context.onlyParameterChangesAtOffset(0));
    try std.testing.expect(context.onlyParameterChangesForIdAtOffset(1, 1));
    try std.testing.expect(!context.onlyParameterChangesForIdAtOffset(2, 1));
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
    try std.testing.expectEqual(@as(usize, 1), context.eventCount());
    try std.testing.expect(!context.inputEventsEmpty());
    try std.testing.expect(!context.eventsEmpty());
    try std.testing.expect(context.hasInputEvents());
    try std.testing.expect(context.hasEvents());
    try std.testing.expectEqual(@as(usize, 1), context.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), context.countInputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 0), context.countNoteReleases());
    try std.testing.expectEqual(@as(usize, 0), context.countInputNoteReleases());
    try std.testing.expect(context.hasNoteAttacks());
    try std.testing.expect(context.hasInputNoteAttacks());
    try std.testing.expect(!context.hasNoteReleases());
    try std.testing.expect(!context.hasInputNoteReleases());
    try std.testing.expect(!context.noteAttacksEmpty());
    try std.testing.expect(!context.inputNoteAttacksEmpty());
    try std.testing.expect(context.noteReleasesEmpty());
    try std.testing.expect(context.inputNoteReleasesEmpty());
    try std.testing.expect(context.onlyNoteAttacks());
    try std.testing.expect(context.onlyInputNoteAttacks());
    try std.testing.expect(!context.onlyNoteReleases());
    try std.testing.expect(!context.onlyInputNoteReleases());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.firstInputEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffset());
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEvent().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEvent().?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventAtOffset(1).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), context.firstInputEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), context.latestEventAtOffset(0));
    try std.testing.expectEqual(@as(?Event, null), context.latestInputEventAtOffset(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.firstInputEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstInputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstInputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.firstInputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffsetForBus(1));
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffsetForChannel(1));
    try std.testing.expect(context.hasEvent(.note_on));
    try std.testing.expect(context.hasInputEvent(.note_on));
    try std.testing.expect(!context.hasEvent(.note_off));
    try std.testing.expect(!context.eventsOfKindEmpty(.note_on));
    try std.testing.expect(!context.inputEventsOfKindEmpty(.note_on));
    try std.testing.expect(context.eventsOfKindEmpty(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEventsAtOffset(1));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForBus(1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForChannel(1));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 1), context.countInputEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), context.countEventsForBusChannel(1, 0));
    try std.testing.expect(context.hasEventsForBus(0));
    try std.testing.expect(context.hasInputEventsForBus(0));
    try std.testing.expect(!context.hasEventsForBus(1));
    try std.testing.expect(!context.eventsForBusEmpty(0));
    try std.testing.expect(!context.inputEventsForBusEmpty(0));
    try std.testing.expect(context.eventsForBusEmpty(1));
    try std.testing.expect(context.hasEventsForChannel(0));
    try std.testing.expect(context.hasInputEventsForChannel(0));
    try std.testing.expect(!context.hasEventsForChannel(1));
    try std.testing.expect(context.hasEventsForBusChannel(0, 0));
    try std.testing.expect(context.hasInputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.hasEventsForBusChannel(0, 1));
    try std.testing.expect(context.hasEventAtOffset(1));
    try std.testing.expect(context.hasInputEventAtOffset(1));
    try std.testing.expect(!context.hasEventAtOffset(0));
    try std.testing.expect(context.hasEventOfKindAtOffset(.note_on, 1));
    try std.testing.expect(context.hasInputEventOfKindAtOffset(.note_on, 1));
    try std.testing.expect(!context.hasEventOfKindAtOffset(.note_off, 1));
    try std.testing.expect(!context.eventsForChannelEmpty(0));
    try std.testing.expect(!context.inputEventsForChannelEmpty(0));
    try std.testing.expect(context.eventsForChannelEmpty(1));
    try std.testing.expect(!context.eventsForBusChannelEmpty(0, 0));
    try std.testing.expect(!context.inputEventsForBusChannelEmpty(0, 0));
    try std.testing.expect(context.eventsForBusChannelEmpty(1, 0));
    try std.testing.expect(!context.eventsAtOffsetEmpty(1));
    try std.testing.expect(!context.inputEventsAtOffsetEmpty(1));
    try std.testing.expect(context.eventsAtOffsetEmpty(0));
    try std.testing.expect(!context.eventsOfKindAtOffsetEmpty(.note_on, 1));
    try std.testing.expect(!context.inputEventsOfKindAtOffsetEmpty(.note_on, 1));
    try std.testing.expect(context.eventsOfKindAtOffsetEmpty(.note_off, 1));
    try std.testing.expect(context.onlyEventsAtOffset(1));
    try std.testing.expect(context.onlyInputEventsAtOffset(1));
    try std.testing.expect(!context.onlyEventsAtOffset(0));
    try std.testing.expect(!context.onlyInputEventsAtOffset(0));
    try std.testing.expect(context.onlyEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expect(context.onlyInputEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expect(!context.onlyEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expect(!context.onlyInputEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expect(context.onlyEventsOfKind(.note_on));
    try std.testing.expect(context.onlyInputEventsOfKind(.note_on));
    try std.testing.expect(context.onlyEventsForBus(0));
    try std.testing.expect(context.onlyInputEventsForBus(0));
    try std.testing.expect(context.onlyEventsForChannel(0));
    try std.testing.expect(context.onlyInputEventsForChannel(0));
    try std.testing.expect(context.onlyEventsForBusChannel(0, 0));
    try std.testing.expect(context.onlyInputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.onlyEventsForBusChannel(0, 1));
    try std.testing.expect(!context.onlyInputEventsForBusChannel(0, 1));
    try std.testing.expect(!context.onlyEventsForChannel(1));
    try std.testing.expect(!context.onlyInputEventsForChannel(1));
    try std.testing.expectEqual(@as(i16, 60), context.firstEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventOfKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventOfKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventOfKindAtOffset(.note_on, 1).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEventOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(?Event, null), context.latestEventOfKindAtOffset(.note_off, 1));
    try std.testing.expectEqual(@as(?Event, null), context.firstEvent(.note_off));
    try std.testing.expectEqual(@as(?Event, null), context.latestEvent(.note_off));
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventForBus(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventForChannel(0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.firstInputEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestInputEventForBusChannel(0, 0).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEventForBus(1));
    try std.testing.expectEqual(@as(?Event, null), context.latestEventForChannel(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffset(0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextInputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextInputEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForKind(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextInputEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForBus(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextInputEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForChannel(1, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForBusChannel(0, 0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextInputEventOffsetForBusChannel(0, 0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForBusChannel(0, 1, 0));
    var note_events = context.inputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), note_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), note_events.next());
    var offset_events = context.inputEventsAtOffset(1);
    try std.testing.expectEqual(EventKind.note_on, offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());
    var bus_events = context.inputEventsForBus(0);
    try std.testing.expectEqual(@as(i16, 60), bus_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), bus_events.next());
    var channel_events = context.inputEventsForChannel(0);
    try std.testing.expectEqual(@as(i16, 60), channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), channel_events.next());
    var bus_channel_events = context.inputEventsForBusChannel(0, 0);
    try std.testing.expectEqual(@as(i16, 60), bus_channel_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), bus_channel_events.next());
    var event_segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, event_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, event_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), event_segments.next());
    var generic_event_segments = context.eventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, generic_event_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, generic_event_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), generic_event_segments.next());
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

test "process block segments generated offsets match reference union" {
    const Reference = struct {
        fn nextOffset(changes: []const ParameterChange, events: []const Event, start: usize, frame_count: usize) usize {
            var result = frame_count;
            for (changes) |change| {
                if (change.sample_offset > start and change.sample_offset < result) {
                    result = change.sample_offset;
                }
            }
            for (events) |event| {
                if (event.sample_offset > start and event.sample_offset < result) {
                    result = event.sample_offset;
                }
            }
            return result;
        }
    };

    const frame_count = 7;
    for (0..32) |seed| {
        var change_storage: [4]ParameterChange = undefined;
        var event_storage: [4]Event = undefined;
        for (&change_storage, 0..) |*change, index| {
            change.* = .{
                .id = @intCast(7 + index % 2),
                .sample_offset = (seed + index * 2) % frame_count,
                .normalized = @as(f64, @floatFromInt((seed + index) % 5)) / 4.0,
            };
        }
        for (&event_storage, 0..) |*event, index| {
            event.* = Event.noteOn((seed * 2 + index * 3) % frame_count, @intCast(index % 2), @intCast(60 + index), 0.5);
        }

        for (0..change_storage.len + 1) |change_count| {
            for (0..event_storage.len + 1) |event_count| {
                const changes = change_storage[0..change_count];
                const events = event_storage[0..event_count];
                var iterator = ProcessBlockSegmentIterator{
                    .parameter_changes = try ParameterChanges.init(changes, frame_count),
                    .events = try Events.init(events, frame_count),
                    .frame_count = frame_count,
                };

                var start: usize = 0;
                while (start < frame_count) {
                    const end = Reference.nextOffset(changes, events, start, frame_count);
                    try std.testing.expectEqual(BlockSegment{ .start_offset = start, .end_offset = end }, iterator.next().?);
                    start = end;
                }
                try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
            }
        }
    }
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
    try std.testing.expect(context.outputEventWriter().? == &writer);
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
    try std.testing.expectEqual(@as(usize, 1), context.outputEvents().eventCount());
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
    var output_bus_events = context.outputEventsForBus(0);
    try std.testing.expectEqual(EventKind.note_on, output_bus_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, output_bus_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), output_bus_events.next());
    var output_channel_events = context.outputEventsForChannel(0);
    try std.testing.expectEqual(EventKind.note_on, output_channel_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, output_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), output_channel_events.next());
    var output_bus_channel_events = context.outputEventsForBusChannel(0, 0);
    try std.testing.expectEqual(EventKind.note_on, output_bus_channel_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_off, output_bus_channel_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), output_bus_channel_events.next());
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
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEventOfKind(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.firstOutputEvent(.note_off).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.firstOutputEventOfKind(.note_off).?.kind);
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
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEventOfKind(.note_off).?.kind);
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
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEventOfKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEventOfKind(.note_on));
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
    try std.testing.expectEqual(@as(?*EventWriter, null), no_writer.outputEventWriter());
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
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEventOfKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEventOfKind(.note_on));
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
    var missing_output_bus_events = no_writer.outputEventsForBus(0);
    try std.testing.expectEqual(@as(?Event, null), missing_output_bus_events.next());
    var missing_output_channel_events = no_writer.outputEventsForChannel(0);
    try std.testing.expectEqual(@as(?Event, null), missing_output_channel_events.next());
    var missing_output_bus_channel_events = no_writer.outputEventsForBusChannel(0, 0);
    try std.testing.expectEqual(@as(?Event, null), missing_output_bus_channel_events.next());
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvent(events[0]));
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvents(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
    no_writer.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
}
