const std = @import("std");
const common = @import("../common.zig");
const changes_mod = @import("changes.zig");
const events_mod = @import("events.zig");
const ordered = @import("ordered.zig");

pub const max_audio_channels = 64;
pub const max_auxiliary_audio_buses =
    @import("../plugin/audio_layout.zig").max_auxiliary_audio_buses;

pub const ProcessMode = enum {
    realtime,
    prefetch,
    offline,
};

pub const TimeSignature = struct {
    numerator: u16,
    denominator: u16,

    pub fn valid(self: TimeSignature) bool {
        return self.numerator > 0 and
            self.denominator > 0 and
            std.math.isPowerOfTwo(self.denominator);
    }
};

pub const CycleRange = struct {
    start_quarter_notes: f64,
    end_quarter_notes: f64,

    pub fn valid(self: CycleRange) bool {
        return std.math.isFinite(self.start_quarter_notes) and
            std.math.isFinite(self.end_quarter_notes) and
            self.end_quarter_notes >= self.start_quarter_notes;
    }
};

pub const Transport = struct {
    project_time_samples: i64,
    state_valid: bool = false,
    playing: bool = false,
    recording: bool = false,
    cycle_active: bool = false,
    tempo_bpm: ?f64 = null,
    project_quarter_notes: ?f64 = null,
    bar_position_quarter_notes: ?f64 = null,
    cycle: ?CycleRange = null,
    time_signature: ?TimeSignature = null,

    pub fn valid(self: Transport) bool {
        if (self.tempo_bpm) |tempo| {
            if (!std.math.isFinite(tempo) or tempo <= 0.0 or tempo > 1_000.0)
                return false;
        }
        if (self.project_quarter_notes) |position| {
            if (!std.math.isFinite(position)) return false;
        }
        if (self.bar_position_quarter_notes) |position| {
            if (!std.math.isFinite(position)) return false;
        }
        if (self.cycle) |cycle| {
            if (!cycle.valid()) return false;
        }
        if (self.time_signature) |signature| {
            if (!signature.valid()) return false;
        }
        return true;
    }

    pub fn tempoOr(self: Transport, fallback_bpm: f64) f64 {
        if (self.tempo_bpm) |tempo| {
            if (std.math.isFinite(tempo) and
                tempo > 0.0 and
                tempo <= 1_000.0)
                return tempo;
        }
        return if (std.math.isFinite(fallback_bpm) and
            fallback_bpm > 0.0 and
            fallback_bpm <= 1_000.0)
            fallback_bpm
        else
            120.0;
    }
};

pub const BlockSegment = changes_mod.BlockSegment;
pub const BlockSegmentIterator = changes_mod.BlockSegmentIterator;
pub const ParameterChange = changes_mod.ParameterChange;
pub const ParameterRamp = changes_mod.ParameterRamp;
pub const BlockParameterLatch = changes_mod.BlockParameterLatch;
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

fn AudioChannelType(comptime ChannelsPointer: type) type {
    return @typeInfo(@typeInfo(ChannelsPointer).pointer.child).array.child;
}

fn audioChannel(channels: anytype, channel_count: usize, index: usize) ?AudioChannelType(@TypeOf(channels)) {
    if (channel_count > max_audio_channels) return null;
    if (index >= channel_count) return null;
    return channels[index];
}

fn processFrameCount(input_channel_count: usize, input_frame_count: usize, output_frame_count: usize) usize {
    if (input_channel_count == 0) return output_frame_count;
    return input_frame_count;
}

fn validateProcessFrameCounts(
    input_channel_count: usize,
    input_frame_count: usize,
    output_channel_count: usize,
    output_frame_count: usize,
) !void {
    if (input_channel_count == 0) return;
    if (output_channel_count == 0) return;
    if (input_frame_count == output_frame_count) return;
    return error.MismatchedFrameCount;
}

fn framesToSeconds(frame_count: usize, sample_rate: f64) f64 {
    if (!common.isPositiveFinite(sample_rate)) return 0.0;
    return @as(f64, @floatFromInt(frame_count)) / sample_rate;
}

pub const ProcessBlockSegmentIterator = struct {
    parameter_changes: ParameterChanges,
    events: Events,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *ProcessBlockSegmentIterator) ?BlockSegment {
        if (!self.valid()) return null;
        if (self.next_start >= self.frame_count) return null;
        const next_parameter_offset = self.parameter_changes.nextSampleOffset(self.next_start);
        const next_event_offset = self.events.nextSampleOffset(self.next_start);
        const boundary = ordered.earliestOffset(next_parameter_offset, next_event_offset, self.frame_count);
        return changes_mod.advanceBlockSegment(&self.next_start, self.frame_count, boundary);
    }

    pub fn valid(self: *const ProcessBlockSegmentIterator) bool {
        return self.next_start <= self.frame_count and
            self.parameter_changes.valid(self.frame_count) and
            self.events.valid(self.frame_count);
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
            if (!self.valid()) return null;
            return audioChannel(&self.channels, self.channel_count, index);
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
            return if (self.valid()) self.channel_count else 0;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.channelCount() == 0;
        }

        pub fn hasChannels(self: *const Self) bool {
            return self.channelCount() != 0;
        }

        pub fn frameCount(self: *const Self) usize {
            return if (self.valid()) self.frame_count else 0;
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count > max_audio_channels) return false;
            if (self.channel_count == 0) return self.frame_count == 0;
            for (self.channels[0..self.channel_count]) |channel_samples| {
                if (channel_samples.len != self.frame_count) return false;
            }
            return true;
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
            if (!self.valid()) return null;
            return audioChannel(&self.channels, self.channel_count, index);
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
            return if (self.valid()) self.channel_count else 0;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.channelCount() == 0;
        }

        pub fn hasChannels(self: *const Self) bool {
            return self.channelCount() != 0;
        }

        pub fn frameCount(self: *const Self) usize {
            return if (self.valid()) self.frame_count else 0;
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count > max_audio_channels) return false;
            if (self.channel_count == 0) return self.frame_count == 0;
            for (self.channels[0..self.channel_count]) |channel_samples| {
                if (channel_samples.len != self.frame_count) return false;
            }
            return true;
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

pub const AudioBusRange = struct {
    channel_offset: usize,
    channel_count: usize,
};

pub fn BoundedAudioBusRanges(
    comptime maximum_auxiliary_buses: usize,
) type {
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError("audio bus range capacity must be at most 254");

    return struct {
        const Self = @This();

        pub const capacity = maximum_auxiliary_buses;

        ranges: [maximum_auxiliary_buses]AudioBusRange =
            [_]AudioBusRange{.{ .channel_offset = 0, .channel_count = 0 }} **
            maximum_auxiliary_buses,
        count: usize = 0,

        pub fn init(
            channel_counts: []const usize,
            total_channels: usize,
        ) !Self {
            if (channel_counts.len > maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            if (channel_counts.len == 0) {
                if (total_channels == 0) return .{};
                if (maximum_auxiliary_buses == 0)
                    return error.TooManyAudioBuses;
                return .{
                    .ranges = init_ranges: {
                        var ranges =
                            [_]AudioBusRange{.{ .channel_offset = 0, .channel_count = 0 }} **
                            maximum_auxiliary_buses;
                        ranges[0].channel_count = total_channels;
                        break :init_ranges ranges;
                    },
                    .count = 1,
                };
            }
            var result = Self{ .count = channel_counts.len };
            var offset: usize = 0;
            for (channel_counts, 0..) |channel_count, index| {
                const next = std.math.add(
                    usize,
                    offset,
                    channel_count,
                ) catch return error.TooManyChannels;
                if (next > total_channels)
                    return error.InvalidAudioBusChannels;
                if (comptime maximum_auxiliary_buses != 0) {
                    result.ranges[index] = .{
                        .channel_offset = offset,
                        .channel_count = channel_count,
                    };
                }
                offset = next;
            }
            if (offset != total_channels)
                return error.InvalidAudioBusChannels;
            return result;
        }

        pub fn range(
            self: Self,
            index: usize,
        ) ?AudioBusRange {
            if (index >= self.count or
                self.count > maximum_auxiliary_buses)
                return null;
            return self.ranges[index];
        }

        pub fn busCount(self: Self) usize {
            return if (self.count <= maximum_auxiliary_buses)
                self.count
            else
                0;
        }

        pub fn valid(
            self: Self,
            total_channels: usize,
        ) bool {
            if (self.count > maximum_auxiliary_buses) return false;
            if (self.count == 0) return total_channels == 0;
            var expected_offset: usize = 0;
            for (self.ranges[0..self.count]) |item| {
                if (item.channel_offset != expected_offset)
                    return false;
                expected_offset = std.math.add(
                    usize,
                    expected_offset,
                    item.channel_count,
                ) catch return false;
                if (expected_offset > total_channels) return false;
            }
            return expected_offset == total_channels;
        }
    };
}

pub const AudioBusRanges =
    BoundedAudioBusRanges(max_auxiliary_audio_buses);

pub const ProcessAttachments = struct {
    parameter_changes: []const ParameterChange = &.{},
    parameter_change_sequences: []const usize = &.{},
    parameter_ramps: []const ParameterRamp = &.{},
    events: []const Event = &.{},
    output_events: ?*EventWriter = null,
};

pub fn BoundedProcessContext(
    comptime Sample: type,
    comptime maximum_auxiliary_buses: usize,
) type {
    const BusRanges =
        BoundedAudioBusRanges(maximum_auxiliary_buses);

    return struct {
        pub const auxiliary_bus_capacity =
            maximum_auxiliary_buses;

        sample_rate: f64,
        mode: ProcessMode = .realtime,
        inputs: AudioInputs(Sample) = .{},
        sidechain_inputs: AudioInputs(Sample) = .{},
        auxiliary_input_ranges: BusRanges = .{},
        outputs: AudioOutputs(Sample) = .{},
        auxiliary_outputs: AudioOutputs(Sample) = .{},
        auxiliary_output_ranges: BusRanges = .{},
        explicit_frame_count: ?usize = null,
        parameter_changes: ParameterChanges = .{},
        events: Events = .{},
        output_events: ?*EventWriter = null,
        host_transport: ?Transport = null,

        pub const InitOptions = struct {
            sample_rate: f64,
            process_mode: ProcessMode = .realtime,
            input_channels: []const []const Sample = &.{},
            sidechain_input_channels: []const []const Sample = &.{},
            auxiliary_input_bus_channel_counts: []const usize = &.{},
            output_channels: []const []Sample = &.{},
            auxiliary_output_channels: []const []Sample = &.{},
            auxiliary_output_bus_channel_counts: []const usize = &.{},
            frame_count: ?usize = null,
            attachments: ProcessAttachments = .{},
            transport: ?Transport = null,
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
            if (options.transport) |host_transport| {
                if (!host_transport.valid()) return error.InvalidTransport;
            }
            const inputs = try AudioInputs(Sample).init(options.input_channels);
            const sidechain_inputs = try AudioInputs(Sample).init(options.sidechain_input_channels);
            const auxiliary_input_ranges = try BusRanges.init(
                options.auxiliary_input_bus_channel_counts,
                sidechain_inputs.channelCount(),
            );
            const outputs = try AudioOutputs(Sample).init(options.output_channels);
            const auxiliary_outputs = try AudioOutputs(Sample).init(options.auxiliary_output_channels);
            const auxiliary_output_ranges = try BusRanges.init(
                options.auxiliary_output_bus_channel_counts,
                auxiliary_outputs.channelCount(),
            );
            try validateProcessFrameCounts(inputs.channelCount(), inputs.frameCount(), outputs.channelCount(), outputs.frameCount());
            const audio_frame_count = processFrameCount(inputs.channelCount(), inputs.frameCount(), outputs.frameCount());
            const frame_count = options.frame_count orelse audio_frame_count;
            if (options.frame_count != null and
                (inputs.hasChannels() or outputs.hasChannels()) and
                frame_count != audio_frame_count)
            {
                return error.MismatchedFrameCount;
            }
            if (sidechain_inputs.hasChannels() and sidechain_inputs.frameCount() != frame_count) {
                return error.MismatchedFrameCount;
            }
            if (auxiliary_outputs.hasChannels() and auxiliary_outputs.frameCount() != frame_count) {
                return error.MismatchedFrameCount;
            }
            var context = @This(){
                .sample_rate = options.sample_rate,
                .mode = options.process_mode,
                .inputs = inputs,
                .sidechain_inputs = sidechain_inputs,
                .auxiliary_input_ranges = auxiliary_input_ranges,
                .outputs = outputs,
                .auxiliary_outputs = auxiliary_outputs,
                .auxiliary_output_ranges = auxiliary_output_ranges,
                .explicit_frame_count = options.frame_count,
                .host_transport = options.transport,
            };
            try context.setParameterAutomation(
                options.attachments.parameter_changes,
                options.attachments.parameter_change_sequences,
                options.attachments.parameter_ramps,
            );
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

        pub fn setParameterAutomation(
            self: *@This(),
            changes: []const ParameterChange,
            change_sequences: []const usize,
            ramps: []const ParameterRamp,
        ) !void {
            self.parameter_changes = try ParameterChanges.initWithRamps(
                changes,
                change_sequences,
                ramps,
                self.frameCount(),
            );
        }

        pub fn setEvents(self: *@This(), events: []const Event) !void {
            self.events = try Events.init(events, self.frameCount());
        }

        pub fn setOutputEvents(self: *@This(), writer: *EventWriter) !void {
            if (writer.frame_count != self.frameCount()) return error.MismatchedFrameCount;
            if (!writer.valid()) return error.InvalidState;
            self.output_events = writer;
        }

        pub fn outputEventWriter(self: *const @This()) ?*EventWriter {
            const writer = self.output_events orelse return null;
            if (writer.frame_count != self.frameCount() or !writer.valid()) return null;
            return writer;
        }

        fn requireOutputEventWriter(self: *const @This()) !*EventWriter {
            return self.outputEventWriter() orelse error.OutputEventsUnavailable;
        }

        pub fn sampleRate(self: *const @This()) f64 {
            return self.sample_rate;
        }

        pub fn processMode(self: *const @This()) ProcessMode {
            return self.mode;
        }

        pub fn transport(self: *const @This()) ?Transport {
            const value = self.host_transport orelse return null;
            return if (value.valid()) value else null;
        }

        pub fn hostTempoBpm(self: *const @This()) ?f64 {
            const value = self.transport() orelse return null;
            return value.tempo_bpm;
        }

        pub fn projectTimeSamples(self: *const @This()) ?i64 {
            const value = self.transport() orelse return null;
            return value.project_time_samples;
        }

        pub fn isRealtime(self: *const @This()) bool {
            return self.mode == .realtime;
        }

        pub fn isPrefetch(self: *const @This()) bool {
            return self.mode == .prefetch;
        }

        pub fn isOffline(self: *const @This()) bool {
            return self.mode == .offline;
        }

        pub fn sampleDurationSeconds(self: *const @This()) f64 {
            return framesToSeconds(1, self.sample_rate);
        }

        pub fn blockDurationSeconds(self: *const @This()) f64 {
            return framesToSeconds(self.frameCount(), self.sample_rate);
        }

        pub fn blockSegment(self: *const @This()) BlockSegment {
            return .{ .start_offset = 0, .end_offset = self.frameCount() };
        }

        pub fn sampleOffsetSeconds(self: *const @This(), sample_offset: usize) f64 {
            return framesToSeconds(sample_offset, self.sample_rate);
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
            return framesToSeconds(self.remainingFramesFromOffset(sample_offset), self.sample_rate);
        }

        pub fn parameterChanges(self: *const @This()) ParameterChanges {
            return self.parameter_changes;
        }

        pub fn parameterRamps(
            self: *const @This(),
        ) []const ParameterRamp {
            return self.parameter_changes.ramps;
        }

        pub fn parameterRampCount(self: *const @This()) usize {
            return self.parameter_changes.rampCount();
        }

        pub fn hasParameterRamps(self: *const @This()) bool {
            return self.parameterRampCount() != 0;
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
            return (try self.requireOutputEventWriter()).appendCount(event);
        }

        pub fn appendOutputEventIfPossible(self: *@This(), event: Event) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.appendIfPossible(event);
        }

        pub fn appendOutputEvents(self: *@This(), events: Events) !void {
            _ = try self.appendOutputEventsCount(events);
        }

        pub fn appendOutputEventsCount(self: *@This(), events: Events) !usize {
            return (try self.requireOutputEventWriter()).appendAllCount(events);
        }

        pub fn appendOutputEventsIfPossible(self: *@This(), events: Events) bool {
            const writer = self.outputEventWriter() orelse return false;
            return writer.appendAllIfPossible(events);
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
            return self.writtenOutputEvents().firstSampleOffset();
        }

        pub fn latestOutputEventOffset(self: *const @This()) ?usize {
            return self.writtenOutputEvents().latestSampleOffset();
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
            return self.writtenOutputEvents().firstSampleOffsetForKind(kind);
        }

        pub fn latestOutputEventOffsetForKind(self: *const @This(), kind: EventKind) ?usize {
            return self.writtenOutputEvents().latestSampleOffsetForKind(kind);
        }

        pub fn firstOutputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.writtenOutputEvents().firstSampleOffsetForBus(bus_index);
        }

        pub fn latestOutputEventOffsetForBus(self: *const @This(), bus_index: i32) ?usize {
            return self.writtenOutputEvents().latestSampleOffsetForBus(bus_index);
        }

        pub fn firstOutputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.writtenOutputEvents().firstSampleOffsetForChannel(channel);
        }

        pub fn latestOutputEventOffsetForChannel(self: *const @This(), channel: i16) ?usize {
            return self.writtenOutputEvents().latestSampleOffsetForChannel(channel);
        }

        pub fn firstOutputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.writtenOutputEvents().firstSampleOffsetForBusChannel(bus_index, channel);
        }

        pub fn latestOutputEventOffsetForBusChannel(self: *const @This(), bus_index: i32, channel: i16) ?usize {
            return self.writtenOutputEvents().latestSampleOffsetForBusChannel(bus_index, channel);
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
            return self.writtenOutputEvents().eventCount();
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

        pub fn sidechainInputAudio(self: *const @This()) AudioInputs(Sample) {
            return self.sidechain_inputs;
        }

        pub fn auxiliaryOutputAudio(self: *const @This()) AudioOutputs(Sample) {
            return self.auxiliary_outputs;
        }

        pub fn auxiliaryInputBus(
            self: *const @This(),
            index: usize,
        ) ?AudioInputs(Sample) {
            const range = self.auxiliary_input_ranges.range(index) orelse
                return null;
            const channel_end = std.math.add(
                usize,
                range.channel_offset,
                range.channel_count,
            ) catch return null;
            if (channel_end > self.sidechain_inputs.channelCount()) return null;
            return AudioInputs(Sample).init(
                self.sidechain_inputs.channels[range.channel_offset..channel_end],
            ) catch null;
        }

        pub fn auxiliaryOutputBus(
            self: *const @This(),
            index: usize,
        ) ?AudioOutputs(Sample) {
            const range = self.auxiliary_output_ranges.range(index) orelse
                return null;
            const channel_end = std.math.add(
                usize,
                range.channel_offset,
                range.channel_count,
            ) catch return null;
            if (channel_end > self.auxiliary_outputs.channelCount()) return null;
            return AudioOutputs(Sample).init(
                self.auxiliary_outputs.channels[range.channel_offset..channel_end],
            ) catch null;
        }

        pub fn auxiliaryInputBusCount(self: *const @This()) usize {
            return self.auxiliary_input_ranges.busCount();
        }

        pub fn auxiliaryOutputBusCount(self: *const @This()) usize {
            return self.auxiliary_output_ranges.busCount();
        }

        pub fn fillOutputs(self: *const @This(), value: Sample) void {
            self.outputs.fill(value);
        }

        pub fn clearOutputs(self: *const @This()) void {
            self.outputs.clear();
        }

        pub fn fillAuxiliaryOutputs(self: *const @This(), value: Sample) void {
            self.auxiliary_outputs.fill(value);
        }

        pub fn clearAuxiliaryOutputs(self: *const @This()) void {
            self.auxiliary_outputs.clear();
        }

        pub fn inputChannel(self: *const @This(), index: usize) ?[]const Sample {
            return self.inputs.channel(index);
        }

        pub fn outputChannel(self: *const @This(), index: usize) ?[]Sample {
            return self.outputs.channel(index);
        }

        pub fn sidechainInputChannel(self: *const @This(), index: usize) ?[]const Sample {
            return self.sidechain_inputs.channel(index);
        }

        pub fn auxiliaryOutputChannel(self: *const @This(), index: usize) ?[]Sample {
            return self.auxiliary_outputs.channel(index);
        }

        pub fn inputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.inputs.sample(channel_index, frame_index);
        }

        pub fn outputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.outputs.sample(channel_index, frame_index);
        }

        pub fn sidechainInputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.sidechain_inputs.sample(channel_index, frame_index);
        }

        pub fn auxiliaryOutputSample(self: *const @This(), channel_index: usize, frame_index: usize) ?Sample {
            return self.auxiliary_outputs.sample(channel_index, frame_index);
        }

        pub fn setOutputSample(self: *const @This(), channel_index: usize, frame_index: usize, value: Sample) bool {
            return self.outputs.setSample(channel_index, frame_index, value);
        }

        pub fn setAuxiliaryOutputSample(self: *const @This(), channel_index: usize, frame_index: usize, value: Sample) bool {
            return self.auxiliary_outputs.setSample(channel_index, frame_index, value);
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

        pub fn sidechainInputChannelCount(self: *const @This()) usize {
            return self.sidechain_inputs.channelCount();
        }

        pub fn auxiliaryOutputChannelCount(self: *const @This()) usize {
            return self.auxiliary_outputs.channelCount();
        }

        pub fn inputChannelsEmpty(self: *const @This()) bool {
            return self.inputs.isEmpty();
        }

        pub fn hasInputChannels(self: *const @This()) bool {
            return self.inputs.hasChannels();
        }

        pub fn hasSidechainInputChannels(self: *const @This()) bool {
            return self.sidechain_inputs.hasChannels();
        }

        pub fn sidechainInputChannelsEmpty(self: *const @This()) bool {
            return self.sidechain_inputs.isEmpty();
        }

        pub fn hasAuxiliaryOutputChannels(self: *const @This()) bool {
            return self.auxiliary_outputs.hasChannels();
        }

        pub fn auxiliaryOutputChannelsEmpty(self: *const @This()) bool {
            return self.auxiliary_outputs.isEmpty();
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

        pub fn sidechainInputFrameCount(self: *const @This()) usize {
            return self.sidechain_inputs.frameCount();
        }

        pub fn auxiliaryOutputFrameCount(self: *const @This()) usize {
            return self.auxiliary_outputs.frameCount();
        }

        pub fn frameCount(self: *const @This()) usize {
            if (self.explicit_frame_count) |frame_count|
                return frame_count;
            return processFrameCount(self.inputChannelCount(), self.inputFrameCount(), self.outputFrameCount());
        }
    };
}

pub fn ProcessContext(comptime Sample: type) type {
    return BoundedProcessContext(
        Sample,
        max_auxiliary_audio_buses,
    );
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

test "audio input view rejects malformed public bounds" {
    const samples = [_]f32{ 0.1, 0.2 };
    const channels = [_][]const f32{&samples};
    var inputs = try AudioInputs(f32).init(&channels);

    inputs.channel_count = max_audio_channels + 1;
    try std.testing.expect(!inputs.valid());
    try std.testing.expectEqual(@as(usize, 0), inputs.channelCount());
    try std.testing.expectEqual(@as(usize, 0), inputs.frameCount());
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(0));
    try std.testing.expectEqual(@as(?f32, null), inputs.sample(0, 0));

    inputs.channel_count = 1;
    inputs.frame_count = samples.len + 1;
    try std.testing.expect(!inputs.valid());
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(0));
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

test "audio output view rejects malformed public bounds without writing" {
    var samples = [_]f32{ 0.1, 0.2 };
    const channels = [_][]f32{&samples};
    var outputs = try AudioOutputs(f32).init(&channels);

    outputs.channel_count = max_audio_channels + 1;
    try std.testing.expect(!outputs.valid());
    try std.testing.expectEqual(@as(usize, 0), outputs.channelCount());
    try std.testing.expect(!outputs.setSample(0, 0, 0.9));
    outputs.fill(0.8);
    try std.testing.expectEqual(@as(f32, 0.1), samples[0]);

    outputs.channel_count = 1;
    outputs.frame_count = samples.len + 1;
    try std.testing.expect(!outputs.valid());
    outputs.clear();
    try std.testing.expectEqual(@as(f32, 0.1), samples[0]);
}

test "process timing helpers fail closed for malformed sample rate" {
    var context = try ProcessContext(f32).init(48_000.0, &.{}, &.{});
    context.sample_rate = std.math.nan(f64);

    try std.testing.expectEqual(@as(f64, 0.0), context.sampleDurationSeconds());
    try std.testing.expectEqual(@as(f64, 0.0), context.blockDurationSeconds());
    try std.testing.expectEqual(@as(f64, 0.0), context.sampleOffsetSeconds(12));
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
    try std.testing.expectEqual(@as(f64, 0.0), context.firstAnyParameterNormalizedOr(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), context.latestAnyParameterNormalizedOr(1.5));

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

test "process context supports event-only processing blocks" {
    var output_storage: [2]Event = undefined;
    var output_events = EventWriter.init(&output_storage, 8);
    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .frame_count = 8,
        .attachments = .{ .output_events = &output_events },
    });

    try std.testing.expectEqual(@as(usize, 8), context.frameCount());
    try std.testing.expect(context.inputChannelsEmpty());
    try std.testing.expect(context.outputChannelsEmpty());
    try std.testing.expect(context.outputEventWriter() != null);
}

test "process context rejects explicit frame count that conflicts with audio" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0 };

    try std.testing.expectError(
        error.MismatchedFrameCount,
        ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .frame_count = 3,
            .input_channels = &.{&input},
            .output_channels = &.{&output},
        }),
    );
}

test "process context keeps sidechain input separate from main audio" {
    const main_left = [_]f32{ 0.1, 0.2, 0.3 };
    const main_right = [_]f32{ 0.4, 0.5, 0.6 };
    const sidechain = [_]f32{ 0.7, 0.8, 0.9 };
    var output_left = [_]f32{ 0.0, 0.0, 0.0 };
    var output_right = [_]f32{ 0.0, 0.0, 0.0 };
    const main_channels = [_][]const f32{ &main_left, &main_right };
    const sidechain_channels = [_][]const f32{&sidechain};
    const output_channels = [_][]f32{ &output_left, &output_right };

    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &main_channels,
        .sidechain_input_channels = &sidechain_channels,
        .output_channels = &output_channels,
    });

    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
    try std.testing.expectEqual(@as(usize, 2), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 1), context.sidechainInputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputChannelCount());
    try std.testing.expectEqual(@as(usize, 3), context.sidechainInputFrameCount());
    try std.testing.expect(context.hasSidechainInputChannels());
    try std.testing.expect(!context.sidechainInputChannelsEmpty());
    try std.testing.expectEqual(@as(?f32, 0.5), context.inputSample(1, 1));
    try std.testing.expectEqual(@as(?f32, 0.8), context.sidechainInputSample(0, 1));
    try std.testing.expectEqual(@as(?f32, null), context.sidechainInputSample(1, 0));
    try std.testing.expectEqual(@as(f32, 0.9), context.sidechainInputChannel(0).?[2]);
    try std.testing.expectEqual(@as(usize, 1), context.sidechainInputAudio().channelCount());
}

test "process context rejects mismatched sidechain frame count" {
    const main = [_]f32{ 0.1, 0.2, 0.3 };
    const sidechain = [_]f32{ 0.4, 0.5 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };

    try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{&main},
        .sidechain_input_channels = &[_][]const f32{&sidechain},
        .output_channels = &[_][]f32{&output},
    }));
}

test "process context keeps auxiliary output separate from the main output" {
    const input = [_]f32{ 0.1, 0.2 };
    var main_output = [_]f32{ 0.0, 0.0 };
    var auxiliary_output = [_]f32{ 0.0, 0.0 };
    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{&input},
        .output_channels = &[_][]f32{&main_output},
        .auxiliary_output_channels = &[_][]f32{&auxiliary_output},
    });

    try std.testing.expectEqual(@as(usize, 1), context.auxiliaryOutputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.auxiliaryOutputFrameCount());
    try std.testing.expect(context.hasAuxiliaryOutputChannels());
    try std.testing.expect(!context.auxiliaryOutputChannelsEmpty());
    try std.testing.expect(context.setAuxiliaryOutputSample(0, 1, 0.75));
    try std.testing.expectEqual(@as(?f32, 0.75), context.auxiliaryOutputSample(0, 1));
    try std.testing.expectEqual(@as(f32, 0.0), main_output[1]);
    context.fillAuxiliaryOutputs(0.25);
    try std.testing.expectEqual(@as(f32, 0.25), auxiliary_output[0]);
    context.clearAuxiliaryOutputs();
    try std.testing.expectEqual(@as(f32, 0.0), auxiliary_output[0]);
}

test "process context rejects mismatched auxiliary output frame count" {
    const input = [_]f32{ 0.1, 0.2 };
    var main_output = [_]f32{ 0.0, 0.0 };
    var auxiliary_output = [_]f32{0.0};

    try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{&input},
        .output_channels = &[_][]f32{&main_output},
        .auxiliary_output_channels = &[_][]f32{&auxiliary_output},
    }));
}

test "process context preserves auxiliary input and output bus boundaries" {
    const main_input = [_]f32{ 0.1, 0.2 };
    const auxiliary_input_mono = [_]f32{ 1.0, 1.1 };
    const auxiliary_input_left = [_]f32{ 2.0, 2.1 };
    const auxiliary_input_right = [_]f32{ 3.0, 3.1 };
    var main_output = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_mono = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_left = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_right = [_]f32{ 0.0, 0.0 };
    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &.{&main_input},
        .sidechain_input_channels = &.{
            &auxiliary_input_mono,
            &auxiliary_input_left,
            &auxiliary_input_right,
        },
        .auxiliary_input_bus_channel_counts = &.{ 1, 2 },
        .output_channels = &.{&main_output},
        .auxiliary_output_channels = &.{
            &auxiliary_output_mono,
            &auxiliary_output_left,
            &auxiliary_output_right,
        },
        .auxiliary_output_bus_channel_counts = &.{ 1, 2 },
    });

    try std.testing.expectEqual(@as(usize, 2), context.auxiliaryInputBusCount());
    try std.testing.expectEqual(@as(usize, 2), context.auxiliaryOutputBusCount());
    const input_bus_0 = context.auxiliaryInputBus(0).?;
    const input_bus_1 = context.auxiliaryInputBus(1).?;
    try std.testing.expectEqual(@as(usize, 1), input_bus_0.channelCount());
    try std.testing.expectEqual(@as(usize, 2), input_bus_1.channelCount());
    try std.testing.expectEqual(@as(f32, 1.1), input_bus_0.channel(0).?[1]);
    try std.testing.expectEqual(@as(f32, 3.1), input_bus_1.channel(1).?[1]);

    const output_bus_0 = context.auxiliaryOutputBus(0).?;
    const output_bus_1 = context.auxiliaryOutputBus(1).?;
    output_bus_0.channel(0).?[0] = 4.0;
    output_bus_1.channel(1).?[1] = 5.0;
    try std.testing.expectEqual(@as(f32, 4.0), auxiliary_output_mono[0]);
    try std.testing.expectEqual(@as(f32, 5.0), auxiliary_output_right[1]);
    try std.testing.expectEqual(@as(?AudioInputs(f32), null), context.auxiliaryInputBus(2));
    try std.testing.expectEqual(@as(?AudioOutputs(f32), null), context.auxiliaryOutputBus(2));
}

test "bounded process context selects auxiliary bus capacity" {
    const Context = BoundedProcessContext(f32, 12);
    const main_input = [_]f32{ 0.0, 0.0 };
    var main_output = [_]f32{ 0.0, 0.0 };
    var auxiliary_inputs: [12][2]f32 = undefined;
    var auxiliary_outputs: [12][2]f32 = undefined;
    var input_views: [12][]const f32 = undefined;
    var output_views: [12][]f32 = undefined;
    var channel_counts: [12]usize = @splat(1);
    for (
        &auxiliary_inputs,
        &auxiliary_outputs,
        &input_views,
        &output_views,
        0..,
    ) |*input, *output, *input_view, *output_view, index| {
        input.* = @splat(@as(f32, @floatFromInt(index + 1)));
        output.* = @splat(0.0);
        input_view.* = input;
        output_view.* = output;
    }

    const context = try Context.initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &.{&main_input},
        .sidechain_input_channels = &input_views,
        .auxiliary_input_bus_channel_counts = &channel_counts,
        .output_channels = &.{&main_output},
        .auxiliary_output_channels = &output_views,
        .auxiliary_output_bus_channel_counts = &channel_counts,
    });

    try std.testing.expectEqual(@as(usize, 12), Context.auxiliary_bus_capacity);
    try std.testing.expectEqual(@as(usize, 12), context.auxiliaryInputBusCount());
    try std.testing.expectEqual(@as(usize, 12), context.auxiliaryOutputBusCount());
    try std.testing.expectEqual(
        @as(f32, 12.0),
        context.auxiliaryInputBus(11).?.sample(0, 1).?,
    );
    try std.testing.expect(
        context.auxiliaryOutputBus(11).?.setSample(0, 1, 0.75),
    );
    try std.testing.expectEqual(@as(f32, 0.75), auxiliary_outputs[11][1]);
}

test "zero-capacity process context rejects auxiliary channels" {
    const Context = BoundedProcessContext(f32, 0);
    const auxiliary_input = [_]f32{ 1.0, 2.0 };

    try std.testing.expectError(
        error.TooManyAudioBuses,
        Context.initWithOptions(.{
            .sample_rate = 48_000.0,
            .sidechain_input_channels = &.{&auxiliary_input},
        }),
    );
    const context = try Context.initWithOptions(.{
        .sample_rate = 48_000.0,
    });
    try std.testing.expectEqual(@as(usize, 0), context.auxiliaryInputBusCount());
    try std.testing.expectEqual(@as(usize, 0), context.auxiliaryOutputBusCount());
}

test "process context rejects invalid auxiliary bus channel partitions" {
    const input = [_]f32{ 0.1, 0.2 };
    const auxiliary_input = [_]f32{ 1.0, 1.1 };
    var output = [_]f32{ 0.0, 0.0 };

    try std.testing.expectError(
        error.InvalidAudioBusChannels,
        ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .input_channels = &.{&input},
            .sidechain_input_channels = &.{&auxiliary_input},
            .auxiliary_input_bus_channel_counts = &.{ 1, 1 },
            .output_channels = &.{&output},
        }),
    );
    try std.testing.expectError(
        error.TooManyAudioBuses,
        ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .input_channels = &.{&input},
            .auxiliary_input_bus_channel_counts = &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            .output_channels = &.{&output},
        }),
    );
}

test "process context rejects malformed auxiliary bus ranges on access" {
    var context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .sidechain_input_channels = &.{},
        .auxiliary_input_bus_channel_counts = &.{0},
        .auxiliary_output_channels = &.{},
        .auxiliary_output_bus_channel_counts = &.{0},
    });
    context.auxiliary_input_ranges.ranges[0] = .{
        .channel_offset = std.math.maxInt(usize),
        .channel_count = 1,
    };
    context.auxiliary_output_ranges.ranges[0] = .{
        .channel_offset = 1,
        .channel_count = 0,
    };

    try std.testing.expect(context.auxiliaryInputBus(0) == null);
    try std.testing.expect(context.auxiliaryOutputBus(0) == null);
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
        .process_mode = .offline,
        .input_channels = &input_channels,
        .output_channels = &output_channels,
        .attachments = .{
            .parameter_changes = &parameter_changes,
            .events = &events,
            .output_events = &output_events,
        },
    });

    try std.testing.expectEqual(@as(f64, 44_100.0), context.sampleRate());
    try std.testing.expectEqual(ProcessMode.offline, context.processMode());
    try std.testing.expect(!context.isRealtime());
    try std.testing.expect(!context.isPrefetch());
    try std.testing.expect(context.isOffline());
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

test "process context generated frame count cases match process side rules" {
    const input_empty = [_]f32{};
    const input_one = [_]f32{0.1};
    const input_two = [_]f32{ 0.1, 0.2 };
    const input_three = [_]f32{ 0.1, 0.2, 0.3 };
    var output_empty = [_]f32{};
    var output_one = [_]f32{0.0};
    var output_two = [_]f32{ 0.0, 0.0 };
    var output_three = [_]f32{ 0.0, 0.0, 0.0 };
    const input_buffers = [_][]const f32{ &input_empty, &input_one, &input_two, &input_three };
    const output_buffers = [_][]f32{ &output_empty, &output_one, &output_two, &output_three };
    const no_input_channels = [_][]const f32{};
    const no_output_channels = [_][]f32{};

    for (input_buffers) |input_buffer| {
        for (output_buffers) |output_buffer| {
            const input_channels = [_][]const f32{input_buffer};
            const output_channels = [_][]f32{output_buffer};
            if (input_buffer.len == output_buffer.len) {
                const context = try ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
                try std.testing.expectEqual(input_buffer.len, context.frameCount());
            } else {
                try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).init(48_000.0, &input_channels, &output_channels));
            }
        }

        const input_only = try ProcessContext(f32).init(48_000.0, &[_][]const f32{input_buffer}, &no_output_channels);
        try std.testing.expectEqual(input_buffer.len, input_only.frameCount());
    }

    for (output_buffers) |output_buffer| {
        const output_only = try ProcessContext(f32).init(48_000.0, &no_input_channels, &[_][]f32{output_buffer});
        try std.testing.expectEqual(output_buffer.len, output_only.frameCount());
    }

    const silent = try ProcessContext(f32).init(48_000.0, &no_input_channels, &no_output_channels);
    try std.testing.expectEqual(@as(usize, 0), silent.frameCount());
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

test "process context carries native parameter ramps" {
    const input = [_]f32{ 0, 0, 0, 0 };
    var output = [_]f32{ 0, 0, 0, 0 };
    const ramps = [_]ParameterRamp{.{
        .id = 4,
        .start_offset = 0,
        .duration_frames = 4,
        .start_normalized = 0.0,
        .end_normalized = 1.0,
        .sequence = 0,
    }};
    const context = try ProcessContext(f32).initWith(
        48_000.0,
        &.{&input},
        &.{&output},
        .{ .parameter_ramps = &ramps },
    );

    try std.testing.expect(context.hasParameterRamps());
    try std.testing.expectEqual(
        @as(usize, 1),
        context.parameterRampCount(),
    );
    try std.testing.expectEqualSlices(
        ParameterRamp,
        &ramps,
        context.parameterRamps(),
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        context.parameterNormalizedAtOrBeforeOr(4, 2, 0.0),
    );
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

    var malformed_count_writer = EventWriter.init(&output_storage, input.len);
    malformed_count_writer.count = output_storage.len + 1;
    try std.testing.expectError(error.InvalidState, context.setOutputEvents(&malformed_count_writer));
    try std.testing.expectError(error.InvalidState, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .output_events = &malformed_count_writer },
    ));

    var malformed_event_writer = EventWriter.init(&output_storage, input.len);
    malformed_event_writer.count = 1;
    malformed_event_writer.storage[0] = Event.noteOn(input.len, 0, 60, 0.5);
    try std.testing.expectError(error.InvalidState, context.setOutputEvents(&malformed_event_writer));
    try std.testing.expectError(error.InvalidState, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .output_events = &malformed_event_writer },
    ));
}

test "process context keeps existing attachments after rejected setters" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const valid_changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.5 },
    };
    const invalid_changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 2, .normalized = 0.75 },
    };
    const valid_events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
    };
    const invalid_events = [_]Event{
        Event.noteOff(2, 0, 60, 0.0),
    };
    var output_storage: [1]Event = undefined;
    var valid_writer = EventWriter.init(&output_storage, input.len);
    var mismatched_storage: [1]Event = undefined;
    var mismatched_writer = EventWriter.init(&mismatched_storage, input.len + 1);
    var context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &valid_changes,
        .events = &valid_events,
        .output_events = &valid_writer,
    });

    try std.testing.expectError(error.ParameterChangeOutsideBlock, context.setParameterChanges(&invalid_changes));
    try std.testing.expectEqual(@as(usize, 1), context.parameterChangeCount());
    try std.testing.expectEqual(@as(?usize, 1), context.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalized(7));

    try std.testing.expectError(error.EventOutsideBlock, context.setEvents(&invalid_events));
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try std.testing.expectEqual(@as(?usize, 1), context.latestInputEventOffset());
    try std.testing.expectEqual(EventKind.note_on, context.latestInputEvent().?.kind);

    try std.testing.expectError(error.MismatchedFrameCount, context.setOutputEvents(&mismatched_writer));
    try std.testing.expect(context.hasOutputEventWriter());
    try std.testing.expect(context.outputEventWriter().? == &valid_writer);
}

test "process context hides an attached writer that later becomes invalid" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var output_storage: [1]Event = undefined;
    var writer = EventWriter.init(&output_storage, input.len);
    var context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .output_events = &writer,
    });

    writer.count = output_storage.len + 1;
    try std.testing.expect(!context.hasOutputEventWriter());
    try std.testing.expectEqual(@as(?*EventWriter, null), context.outputEventWriter());
    try std.testing.expectError(error.OutputEventsUnavailable, context.appendOutputEvent(Event.noteOn(0, 0, 60, 0.5)));

    writer.clear();
    try std.testing.expect(context.outputEventWriter().? == &writer);

    writer.frame_count = input.len + 1;
    try std.testing.expect(!context.hasOutputEventWriter());
    try std.testing.expect(!context.appendOutputEventIfPossible(Event.noteOn(0, 0, 60, 0.5)));

    writer.frame_count = input.len;
    try std.testing.expect(context.outputEventWriter().? == &writer);
    try context.appendOutputEvent(Event.noteOn(0, 0, 60, 0.5));
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
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
    try std.testing.expect(iterator.valid());

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 2 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 2, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
    try std.testing.expect(iterator.valid());
    iterator.next_start = 9;
    try std.testing.expect(!iterator.valid());
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
    try std.testing.expectEqual(@as(usize, 9), iterator.next_start);

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
    try std.testing.expect(!context.appendOutputEventIfPossible(events[0]));
    try std.testing.expect(!context.appendOutputEventsIfPossible(try Events.init(events[0..1], input.len)));

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

    try std.testing.expect(context.appendOutputEventIfPossible(events[0]));
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(EventKind.note_on, context.outputEvents().items[0].kind);
    context.clearOutputEvents();

    try std.testing.expect(context.appendOutputEventsIfPossible(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(EventKind.note_on, context.outputEvents().items[0].kind);
    try std.testing.expectEqual(EventKind.note_off, context.outputEvents().items[1].kind);
    context.clearOutputEvents();

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
    try std.testing.expect(!no_writer.appendOutputEventIfPossible(events[0]));
    try std.testing.expect(!no_writer.appendOutputEventsIfPossible(try Events.init(&events, input.len)));
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

test "process context exposes checked host transport" {
    const context = try ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .transport = .{
            .project_time_samples = 48_000,
            .state_valid = true,
            .playing = true,
            .tempo_bpm = 125.0,
            .project_quarter_notes = 16.0,
            .time_signature = .{
                .numerator = 5,
                .denominator = 4,
            },
        },
    });
    try std.testing.expect(context.transport().?.playing);
    try std.testing.expectEqual(
        @as(?i64, 48_000),
        context.projectTimeSamples(),
    );
    try std.testing.expectEqual(@as(?f64, 125.0), context.hostTempoBpm());
    try std.testing.expectEqual(
        @as(f64, 120.0),
        (Transport{ .project_time_samples = 0 }).tempoOr(120.0),
    );
    try std.testing.expectEqual(
        @as(f64, 90.0),
        (Transport{
            .project_time_samples = 0,
            .tempo_bpm = std.math.nan(f64),
        }).tempoOr(90.0),
    );
    try std.testing.expectEqual(
        @as(f64, 120.0),
        (Transport{
            .project_time_samples = 0,
            .tempo_bpm = std.math.inf(f64),
        }).tempoOr(std.math.nan(f64)),
    );
    try std.testing.expectEqual(
        @as(f64, 120.0),
        (Transport{
            .project_time_samples = 0,
            .tempo_bpm = 1_001.0,
        }).tempoOr(-1.0),
    );

    try std.testing.expectError(
        error.InvalidTransport,
        ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .transport = .{
                .project_time_samples = 0,
                .tempo_bpm = std.math.nan(f64),
            },
        }),
    );
}
