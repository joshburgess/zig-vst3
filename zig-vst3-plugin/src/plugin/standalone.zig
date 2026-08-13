const std = @import("std");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const realtime_audit = @import("../realtime_audit.zig");
const resampler = @import("../dsp/resampler.zig");
const audio_layout = @import("audio_layout.zig");
const runtime_mod = @import("runtime.zig");
const spec_mod = @import("spec.zig");

pub const DeviceConfiguration = struct {
    sample_rate: f64,
    max_block_size: u32,
    input_channel_count: usize,
    auxiliary_input_bus_channel_counts: []const usize = &.{},
    output_channel_count: usize,
    auxiliary_output_bus_channel_counts: []const usize = &.{},

    pub fn validate(self: DeviceConfiguration) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate <= 0.0)
            return error.InvalidSampleRate;
        if (self.max_block_size == 0)
            return error.InvalidMaxBlockSize;
        if (self.input_channel_count > process_api.max_audio_channels or
            self.output_channel_count > process_api.max_audio_channels)
            return error.TooManyChannels;
        try validateBusChannelCounts(
            self.auxiliary_input_bus_channel_counts,
        );
        try validateBusChannelCounts(
            self.auxiliary_output_bus_channel_counts,
        );
    }
};

pub const ClockDriftConfig = struct {
    target_buffer_frames: usize,
    maximum_correction_ppm: f64 = 1_000.0,
    proportional_gain_ppm_per_frame: f64 = 2.0,
    integral_gain_ppm_per_frame_second: f64 = 0.5,
    maximum_slew_ppm_per_second: f64 = 250.0,

    pub fn validate(self: ClockDriftConfig) !void {
        if (self.target_buffer_frames == 0)
            return error.InvalidClockDriftTarget;
        if (!std.math.isFinite(self.maximum_correction_ppm) or
            self.maximum_correction_ppm <= 0.0 or
            self.maximum_correction_ppm >
                resampler.maximum_rate_correction_ppm)
            return error.InvalidClockDriftCorrection;
        if (!std.math.isFinite(
            self.proportional_gain_ppm_per_frame,
        ) or
            self.proportional_gain_ppm_per_frame <= 0.0 or
            !std.math.isFinite(
                self.integral_gain_ppm_per_frame_second,
            ) or
            self.integral_gain_ppm_per_frame_second < 0.0 or
            !std.math.isFinite(self.maximum_slew_ppm_per_second) or
            self.maximum_slew_ppm_per_second <= 0.0)
            return error.InvalidClockDriftGain;
    }
};

pub const ClockDriftController = struct {
    config: ClockDriftConfig,
    integral_error_frame_seconds: f64 = 0.0,
    correction_ppm: f64 = 0.0,

    pub fn init(config: ClockDriftConfig) !ClockDriftController {
        try config.validate();
        return .{ .config = config };
    }

    pub fn update(
        self: *ClockDriftController,
        buffered_input_frames: usize,
        output_frames: usize,
        output_sample_rate: f64,
    ) !f64 {
        if (!self.valid())
            return error.InvalidClockDriftController;
        if (!std.math.isFinite(output_sample_rate) or
            output_sample_rate <= 0.0)
            return error.InvalidSampleRate;
        if (output_frames == 0) return self.correction_ppm;

        const duration_seconds =
            @as(f64, @floatFromInt(output_frames)) /
            output_sample_rate;
        if (!std.math.isFinite(duration_seconds))
            return error.ClockDriftDurationOverflow;
        const error_frames =
            @as(f64, @floatFromInt(buffered_input_frames)) -
            @as(f64, @floatFromInt(
                self.config.target_buffer_frames,
            ));
        var next_integral =
            self.integral_error_frame_seconds +
            error_frames * duration_seconds;
        if (!std.math.isFinite(next_integral))
            return error.ClockDriftIntegralOverflow;
        if (self.config.integral_gain_ppm_per_frame_second == 0.0) {
            next_integral = 0.0;
        } else {
            const integral_limit =
                self.config.maximum_correction_ppm /
                self.config.integral_gain_ppm_per_frame_second;
            next_integral = std.math.clamp(
                next_integral,
                -integral_limit,
                integral_limit,
            );
        }
        const desired_correction = std.math.clamp(
            error_frames *
                self.config.proportional_gain_ppm_per_frame +
                next_integral *
                    self.config
                        .integral_gain_ppm_per_frame_second,
            -self.config.maximum_correction_ppm,
            self.config.maximum_correction_ppm,
        );
        const maximum_delta =
            self.config.maximum_slew_ppm_per_second *
            duration_seconds;
        if (!std.math.isFinite(maximum_delta))
            return error.ClockDriftDurationOverflow;
        const next_correction = self.correction_ppm +
            std.math.clamp(
                desired_correction - self.correction_ppm,
                -maximum_delta,
                maximum_delta,
            );
        if (!std.math.isFinite(next_correction))
            return error.ClockDriftCorrectionOverflow;

        self.integral_error_frame_seconds = next_integral;
        self.correction_ppm = next_correction;
        return next_correction;
    }

    pub fn updateResampler(
        self: *ClockDriftController,
        target_resampler: anytype,
        buffered_input_frames: usize,
        output_frames: usize,
        output_sample_rate: f64,
    ) !f64 {
        var trial = self.*;
        const correction = try trial.update(
            buffered_input_frames,
            output_frames,
            output_sample_rate,
        );
        try target_resampler.setRateCorrectionPpm(correction);
        self.* = trial;
        return correction;
    }

    pub fn reset(self: *ClockDriftController) void {
        self.integral_error_frame_seconds = 0.0;
        self.correction_ppm = 0.0;
    }

    pub fn valid(self: *const ClockDriftController) bool {
        self.config.validate() catch return false;
        if (!std.math.isFinite(
            self.integral_error_frame_seconds,
        ) or
            !std.math.isFinite(self.correction_ppm) or
            @abs(self.correction_ppm) >
                self.config.maximum_correction_ppm)
            return false;
        if (self.config.integral_gain_ppm_per_frame_second == 0.0)
            return self.integral_error_frame_seconds == 0.0;
        const integral_contribution =
            @abs(self.integral_error_frame_seconds) *
            self.config.integral_gain_ppm_per_frame_second;
        return std.math.isFinite(integral_contribution) and
            integral_contribution <=
                self.config.maximum_correction_ppm;
    }
};

pub const CaptureFifoWriteReport = struct {
    written_frames: usize,
    dropped_frames: usize,
};

pub const CaptureFifoReadReport = struct {
    read_frames: usize,
    silent_frames: usize,
};

pub const CaptureFifoStatistics = struct {
    buffered_frames: usize,
    written_frames: usize,
    read_frames: usize,
    dropped_frames: usize,
    silent_frames: usize,
};

/// Fixed-storage planar audio queue for one capture producer and one render
/// consumer. Keep the queue at a stable address while either side is running.
pub fn BoundedCaptureFifo(
    comptime Sample: type,
    comptime maximum_channels: usize,
    comptime frame_capacity: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("BoundedCaptureFifo supports f32 and f64");
    if (maximum_channels == 0)
        @compileError("BoundedCaptureFifo requires channel capacity");
    if (maximum_channels > process_api.max_audio_channels)
        @compileError("BoundedCaptureFifo channel capacity is too large");
    if (frame_capacity == 0)
        @compileError("BoundedCaptureFifo requires frame capacity");
    if (frame_capacity >= std.math.maxInt(usize))
        @compileError("BoundedCaptureFifo frame capacity is too large");

    const slot_count = frame_capacity + 1;

    return struct {
        const Self = @This();
        pub const channel_capacity = maximum_channels;
        pub const capacity_frames = frame_capacity;

        storage: [maximum_channels][slot_count]Sample = @splat(@splat(0.0)),
        channel_count: usize,
        read_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        write_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        written_frames: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        read_frames: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        dropped_frames: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        silent_frames: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        pub fn init(channel_count: usize) !Self {
            if (channel_count == 0 or
                channel_count > maximum_channels)
                return error.InvalidCaptureChannelCount;
            return .{ .channel_count = channel_count };
        }

        /// Publish as many complete frames as fit. Newest excess frames are
        /// dropped so the producer never modifies the consumer-owned cursor.
        pub fn write(
            self: *Self,
            input_channels: []const []const Sample,
        ) !CaptureFifoWriteReport {
            const frame_count =
                try self.validateInputChannels(input_channels);
            const write_cursor = self.write_index.load(.monotonic);
            const read_cursor = self.read_index.load(.acquire);
            const buffered = try bufferedFrameCount(
                read_cursor,
                write_cursor,
            );
            const writable = frame_capacity - buffered;
            const accepted = @min(frame_count, writable);
            const dropped = frame_count - accepted;

            if (accepted != 0) {
                const first_count =
                    @min(accepted, slot_count - write_cursor);
                const second_count = accepted - first_count;
                for (input_channels, 0..) |input, channel| {
                    @memcpy(
                        self.storage[channel][write_cursor..][0..first_count],
                        input[0..first_count],
                    );
                    if (second_count != 0) {
                        @memcpy(
                            self.storage[channel][0..second_count],
                            input[first_count..accepted],
                        );
                    }
                }
                self.write_index.store(
                    advanceFifoIndex(write_cursor, accepted, slot_count),
                    .release,
                );
                recordSaturatingAmount(
                    &self.written_frames,
                    accepted,
                );
            }
            recordSaturatingAmount(&self.dropped_frames, dropped);
            return .{
                .written_frames = accepted,
                .dropped_frames = dropped,
            };
        }

        /// Consume available frames and zero only the unavailable tail.
        pub fn read(
            self: *Self,
            output_channels: []const []Sample,
        ) !CaptureFifoReadReport {
            const requested =
                try self.validateOutputChannels(output_channels);
            const read_cursor = self.read_index.load(.monotonic);
            const write_cursor = self.write_index.load(.acquire);
            const buffered = try bufferedFrameCount(
                read_cursor,
                write_cursor,
            );
            const available = @min(requested, buffered);
            const silent = requested - available;

            if (available != 0) {
                const first_count =
                    @min(available, slot_count - read_cursor);
                const second_count = available - first_count;
                for (output_channels, 0..) |output, channel| {
                    @memcpy(
                        output[0..first_count],
                        self.storage[channel][read_cursor..][0..first_count],
                    );
                    if (second_count != 0) {
                        @memcpy(
                            output[first_count..available],
                            self.storage[channel][0..second_count],
                        );
                    }
                }
            }
            if (silent != 0) {
                for (output_channels) |output|
                    @memset(output[available..requested], 0.0);
            }
            if (available != 0) {
                self.read_index.store(
                    advanceFifoIndex(read_cursor, available, slot_count),
                    .release,
                );
                recordSaturatingAmount(&self.read_frames, available);
            }
            recordSaturatingAmount(&self.silent_frames, silent);
            return .{
                .read_frames = available,
                .silent_frames = silent,
            };
        }

        pub fn bufferedFrames(self: *const Self) !usize {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return error.InvalidCaptureFifo;
            return bufferedFrameCount(
                self.read_index.load(.acquire),
                self.write_index.load(.acquire),
            );
        }

        pub fn statistics(self: *const Self) !CaptureFifoStatistics {
            return .{
                .buffered_frames = try self.bufferedFrames(),
                .written_frames = self.written_frames.load(.monotonic),
                .read_frames = self.read_frames.load(.monotonic),
                .dropped_frames = self.dropped_frames.load(.monotonic),
                .silent_frames = self.silent_frames.load(.monotonic),
            };
        }

        pub fn updateDriftCorrection(
            self: *const Self,
            controller: *ClockDriftController,
            target_resampler: anytype,
            output_frames: usize,
            output_sample_rate: f64,
        ) !f64 {
            if (controller.config.target_buffer_frames >
                frame_capacity)
                return error.ClockDriftTargetExceedsFifoCapacity;
            return controller.updateResampler(
                target_resampler,
                try self.bufferedFrames(),
                output_frames,
                output_sample_rate,
            );
        }

        /// Reset only after both capture and render callbacks have stopped.
        pub fn reset(self: *Self) void {
            self.storage = @splat(@splat(0.0));
            self.read_index.store(0, .release);
            self.write_index.store(0, .release);
            self.written_frames.store(0, .monotonic);
            self.read_frames.store(0, .monotonic);
            self.dropped_frames.store(0, .monotonic);
            self.silent_frames.store(0, .monotonic);
        }

        pub fn valid(self: *const Self) bool {
            _ = self.bufferedFrames() catch return false;
            return true;
        }

        fn validateInputChannels(
            self: *const Self,
            channels: []const []const Sample,
        ) !usize {
            try self.validateChannelCount(channels.len);
            const frame_count = channels[0].len;
            for (channels) |channel| {
                if (channel.len != frame_count)
                    return error.CaptureFrameCountMismatch;
                for (self.storage[0..self.channel_count]) |*retained| {
                    if (try sampleSlicesOverlap(
                        Sample,
                        channel,
                        retained,
                    ))
                        return error.CaptureBufferAliasesFifo;
                }
            }
            return frame_count;
        }

        fn validateOutputChannels(
            self: *const Self,
            channels: []const []Sample,
        ) !usize {
            try self.validateChannelCount(channels.len);
            const frame_count = channels[0].len;
            for (channels, 0..) |channel, channel_index| {
                if (channel.len != frame_count)
                    return error.CaptureFrameCountMismatch;
                for (channels[0..channel_index]) |previous| {
                    if (try sampleSlicesOverlap(
                        Sample,
                        channel,
                        previous,
                    ))
                        return error.OverlappingCaptureOutputs;
                }
                for (self.storage[0..self.channel_count]) |*retained| {
                    if (try sampleSlicesOverlap(
                        Sample,
                        channel,
                        retained,
                    ))
                        return error.CaptureBufferAliasesFifo;
                }
            }
            return frame_count;
        }

        fn validateChannelCount(
            self: *const Self,
            supplied: usize,
        ) !void {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return error.InvalidCaptureFifo;
            if (supplied != self.channel_count)
                return error.CaptureChannelCountMismatch;
            _ = try self.bufferedFrames();
        }

        fn bufferedFrameCount(
            read_cursor: usize,
            write_cursor: usize,
        ) !usize {
            if (read_cursor >= slot_count or
                write_cursor >= slot_count)
                return error.InvalidCaptureFifo;
            return if (write_cursor >= read_cursor)
                write_cursor - read_cursor
            else
                slot_count - read_cursor + write_cursor;
        }
    };
}

pub const CaptureRateBridgeConfig = struct {
    channel_count: usize,
    capture_sample_rate: f64,
    render_sample_rate: f64,
    drift: ClockDriftConfig,
    lifecycle: CaptureRateLifecycleConfig = .{},
};

pub const CaptureRateUnderflowPolicy = enum(u8) {
    continue_with_silence,
    rebuffer,
    _,
};

pub const CaptureRateOverflowPolicy = enum(u8) {
    drop_newest_and_continue,
    drop_newest_and_rebuffer,
    _,
};

pub const CaptureRateLifecycleConfig = struct {
    startup_buffer_frames: usize = 0,
    recovery_buffer_frames: usize = 0,
    control_interval_frames: usize = 0,
    underflow_policy: CaptureRateUnderflowPolicy =
        .continue_with_silence,
    overflow_policy: CaptureRateOverflowPolicy =
        .drop_newest_and_continue,

    pub fn validate(
        self: CaptureRateLifecycleConfig,
        fifo_capacity_frames: usize,
    ) !void {
        switch (self.underflow_policy) {
            .continue_with_silence, .rebuffer => {},
            else => return error.InvalidCaptureRateUnderflowPolicy,
        }
        switch (self.overflow_policy) {
            .drop_newest_and_continue,
            .drop_newest_and_rebuffer,
            => {},
            else => return error.InvalidCaptureRateOverflowPolicy,
        }
        if (self.startup_buffer_frames > fifo_capacity_frames or
            self.recovery_buffer_frames > fifo_capacity_frames)
            return error.CaptureRateBufferThresholdExceedsCapacity;
        if ((self.underflow_policy == .rebuffer or
            self.overflow_policy == .drop_newest_and_rebuffer) and
            self.recovery_buffer_frames == 0)
            return error.InvalidCaptureRateRecoveryThreshold;
    }
};

pub const CaptureRateOperatingState = enum(u8) {
    priming,
    running,
    _,
};

pub const CaptureRateRenderReport = struct {
    output_frames: usize,
    capture_frames: usize,
    silent_capture_frames: usize,
    discarded_capture_frames: usize,
    buffered_before: usize,
    buffered_after: usize,
    correction_ppm: f64,
    state_before: CaptureRateOperatingState,
    state_after: CaptureRateOperatingState,
};

/// Bounded disparate-clock input path for one capture callback and one render
/// callback. Capture publication and rendering perform no allocation or locks.
pub fn BoundedCaptureRateBridge(
    comptime Sample: type,
    comptime maximum_channels: usize,
    comptime fifo_frame_capacity: usize,
    comptime maximum_capture_chunk: usize,
    comptime maximum_output_frames: usize,
) type {
    if (maximum_capture_chunk == 0)
        @compileError(
            "BoundedCaptureRateBridge requires capture scratch",
        );
    if (maximum_output_frames == 0)
        @compileError(
            "BoundedCaptureRateBridge requires output capacity",
        );

    const Fifo = BoundedCaptureFifo(
        Sample,
        maximum_channels,
        fifo_frame_capacity,
    );
    const Resampler = resampler.StreamingResampler(Sample);

    return struct {
        const Self = @This();
        pub const fifo_capacity_frames = fifo_frame_capacity;
        pub const output_capacity_frames = maximum_output_frames;

        fifo: Fifo,
        resamplers: [maximum_channels]Resampler = @splat(.{}),
        controller: ClockDriftController,
        channel_count: usize,
        capture_sample_rate: f64,
        render_sample_rate: f64,
        lifecycle: CaptureRateLifecycleConfig,
        operating_state: CaptureRateOperatingState,
        priming_target_frames: usize,
        control_frames_remaining: usize = 0,
        overflow_recovery_requested: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        capture_scratch: [maximum_channels][maximum_capture_chunk]Sample =
            undefined,

        pub fn init(
            config: CaptureRateBridgeConfig,
        ) !Self {
            if (config.channel_count == 0 or
                config.channel_count > maximum_channels)
                return error.InvalidCaptureChannelCount;
            try config.drift.validate();
            if (config.drift.target_buffer_frames >
                fifo_frame_capacity)
                return error.ClockDriftTargetExceedsFifoCapacity;
            try config.lifecycle.validate(fifo_frame_capacity);
            try (resampler.Config{
                .input_rate = config.capture_sample_rate,
                .output_rate = config.render_sample_rate,
            }).validate();

            var result = Self{
                .fifo = try Fifo.init(config.channel_count),
                .controller = try ClockDriftController.init(config.drift),
                .channel_count = config.channel_count,
                .capture_sample_rate = config.capture_sample_rate,
                .render_sample_rate = config.render_sample_rate,
                .lifecycle = config.lifecycle,
                .operating_state = if (config.lifecycle.startup_buffer_frames == 0) .running else .priming,
                .priming_target_frames = config.lifecycle.startup_buffer_frames,
            };
            for (result.resamplers[0..config.channel_count]) |*stream| {
                try stream.configure(.{
                    .input_rate = config.capture_sample_rate,
                    .output_rate = config.render_sample_rate,
                });
            }
            return result;
        }

        /// Called only by the capture producer.
        pub fn capture(
            self: *Self,
            input_channels: []const []const Sample,
        ) !CaptureFifoWriteReport {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return error.InvalidCaptureRateBridge;
            for (input_channels) |input| {
                if (try self.aliasesRetainedAudio(input))
                    return error.CaptureBufferAliasesBridge;
            }
            const report = try self.fifo.write(input_channels);
            if (report.dropped_frames != 0 and
                self.lifecycle.overflow_policy ==
                    .drop_newest_and_rebuffer)
                self.overflow_recovery_requested.store(true, .release);
            return report;
        }

        /// Called only by the render consumer.
        pub fn render(
            self: *Self,
            output_channels: []const []Sample,
        ) !CaptureRateRenderReport {
            try self.validateRenderOutputs(output_channels);
            errdefer for (output_channels) |output|
                @memset(output, 0.0);
            const output_count = output_channels[0].len;
            const buffered_before = try self.fifo.bufferedFrames();
            const state_before = self.operating_state;

            if (self.overflow_recovery_requested.swap(false, .acq_rel)) {
                const discarded = try self.beginRecovery(true);
                for (output_channels) |output|
                    @memset(output, 0.0);
                return .{
                    .output_frames = output_count,
                    .capture_frames = 0,
                    .silent_capture_frames = 0,
                    .discarded_capture_frames = discarded,
                    .buffered_before = buffered_before,
                    .buffered_after = try self.fifo.bufferedFrames(),
                    .correction_ppm = self.controller.correction_ppm,
                    .state_before = state_before,
                    .state_after = .priming,
                };
            }
            if (self.operating_state == .priming) {
                if (buffered_before < self.priming_target_frames) {
                    for (output_channels) |output|
                        @memset(output, 0.0);
                    return .{
                        .output_frames = output_count,
                        .capture_frames = 0,
                        .silent_capture_frames = 0,
                        .discarded_capture_frames = 0,
                        .buffered_before = buffered_before,
                        .buffered_after = buffered_before,
                        .correction_ppm = self.controller.correction_ppm,
                        .state_before = state_before,
                        .state_after = .priming,
                    };
                }
                self.operating_state = .running;
            }

            var produced: usize = 0;
            var capture_frames: usize = 0;
            var silent_capture_frames: usize = 0;
            var correction = self.controller.correction_ppm;
            while (produced < output_count) {
                const control_interval =
                    self.lifecycle.control_interval_frames;
                if (control_interval == 0 or
                    self.control_frames_remaining == 0)
                {
                    const update_frames = if (control_interval == 0)
                        output_count
                    else
                        control_interval;
                    var trial_controller = self.controller;
                    correction = try trial_controller.update(
                        try self.fifo.bufferedFrames(),
                        update_frames,
                        self.render_sample_rate,
                    );
                    for (self.resamplers[0..self.channel_count]) |*stream|
                        try stream.setRateCorrectionPpm(correction);
                    self.controller = trial_controller;
                    self.control_frames_remaining = if (control_interval == 0) output_count - produced else control_interval;
                }
                const segment_frames = @min(
                    output_count - produced,
                    self.control_frames_remaining,
                );
                const segment = try self.renderSegment(
                    output_channels,
                    produced,
                    segment_frames,
                    correction,
                );
                produced += segment_frames;
                capture_frames += segment.capture_frames;
                silent_capture_frames += segment.silent_capture_frames;
                self.control_frames_remaining -= segment_frames;
                if (control_interval == 0) {
                    self.control_frames_remaining = 0;
                }
            }

            if (silent_capture_frames != 0 and
                self.lifecycle.underflow_policy == .rebuffer)
            {
                _ = try self.beginRecovery(false);
                for (output_channels) |output|
                    @memset(output, 0.0);
                correction = self.controller.correction_ppm;
            }

            return .{
                .output_frames = produced,
                .capture_frames = capture_frames,
                .silent_capture_frames = silent_capture_frames,
                .discarded_capture_frames = 0,
                .buffered_before = buffered_before,
                .buffered_after = try self.fifo.bufferedFrames(),
                .correction_ppm = correction,
                .state_before = state_before,
                .state_after = self.operating_state,
            };
        }

        pub fn statistics(
            self: *const Self,
        ) !CaptureFifoStatistics {
            return self.fifo.statistics();
        }

        /// Reset only after capture and render callbacks have stopped.
        pub fn reset(self: *Self) !void {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return error.InvalidCaptureRateBridge;
            try (resampler.Config{
                .input_rate = self.capture_sample_rate,
                .output_rate = self.render_sample_rate,
            }).validate();
            for (self.resamplers[0..self.channel_count]) |*stream| {
                try stream.configure(.{
                    .input_rate = self.capture_sample_rate,
                    .output_rate = self.render_sample_rate,
                });
            }
            self.controller.reset();
            self.fifo.reset();
            self.operating_state = if (self.lifecycle.startup_buffer_frames == 0) .running else .priming;
            self.priming_target_frames =
                self.lifecycle.startup_buffer_frames;
            self.control_frames_remaining = 0;
            self.overflow_recovery_requested.store(false, .release);
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels or
                self.fifo.channel_count != self.channel_count or
                !self.fifo.valid() or
                !self.controller.valid() or
                self.controller.config.target_buffer_frames >
                    fifo_frame_capacity or
                self.priming_target_frames > fifo_frame_capacity or
                (self.lifecycle.control_interval_frames == 0 and
                    self.control_frames_remaining != 0) or
                (self.lifecycle.control_interval_frames != 0 and
                    self.control_frames_remaining >
                        self.lifecycle.control_interval_frames) or
                (self.operating_state != .priming and
                    self.operating_state != .running))
                return false;
            self.lifecycle.validate(fifo_frame_capacity) catch return false;
            (resampler.Config{
                .input_rate = self.capture_sample_rate,
                .output_rate = self.render_sample_rate,
            }).validate() catch return false;
            const reference = &self.resamplers[0];
            if (!reference.validState() or
                reference.drain_target != null)
                return false;
            for (self.resamplers[0..self.channel_count]) |*stream| {
                if (!stream.validState() or
                    stream.drain_target != null or
                    !sameResamplerTimeline(reference, stream) or
                    stream.input_rate != self.capture_sample_rate or
                    stream.output_rate != self.render_sample_rate)
                    return false;
            }
            return true;
        }

        fn preflightInputDemand(
            self: *const Self,
            output_count: usize,
            correction_ppm: f64,
        ) !usize {
            var required: ?usize = null;
            for (self.resamplers[0..self.channel_count]) |*stream| {
                const channel_required =
                    try stream.requiredInputSamplesAtCorrection(
                        output_count,
                        correction_ppm,
                    );
                if (required) |expected| {
                    if (channel_required != expected)
                        return error.CaptureRateTimelineMismatch;
                } else {
                    required = channel_required;
                }
            }
            return required orelse
                error.InvalidCaptureRateBridge;
        }

        const RenderSegmentReport = struct {
            capture_frames: usize,
            silent_capture_frames: usize,
        };

        fn renderSegment(
            self: *Self,
            output_channels: []const []Sample,
            output_offset: usize,
            output_count: usize,
            correction_ppm: f64,
        ) !RenderSegmentReport {
            const input_needed = try self.preflightInputDemand(
                output_count,
                correction_ppm,
            );
            var segment_outputs: [maximum_channels][]Sample = undefined;
            for (
                segment_outputs[0..self.channel_count],
                output_channels,
            ) |*segment, output| {
                segment.* = output[output_offset..][0..output_count];
            }
            var produced = try self.processSynchronized(
                &.{},
                segment_outputs[0..self.channel_count],
                0,
            );
            var capture_frames: usize = 0;
            var silent_capture_frames: usize = 0;
            while (capture_frames < input_needed) {
                const chunk = @min(
                    input_needed - capture_frames,
                    maximum_capture_chunk,
                );
                var scratch_views: [maximum_channels][]Sample = undefined;
                for (
                    scratch_views[0..self.channel_count],
                    self.capture_scratch[0..self.channel_count],
                ) |*view, *storage| {
                    view.* = storage[0..chunk];
                }
                const read_report = try self.fifo.read(
                    scratch_views[0..self.channel_count],
                );
                silent_capture_frames += read_report.silent_frames;
                capture_frames += chunk;
                produced += try self.processSynchronized(
                    scratch_views[0..self.channel_count],
                    segment_outputs[0..self.channel_count],
                    produced,
                );
            }
            if (produced != output_count)
                return error.CaptureRateOutputUnderflow;
            return .{
                .capture_frames = capture_frames,
                .silent_capture_frames = silent_capture_frames,
            };
        }

        fn beginRecovery(self: *Self, discard_buffered: bool) !usize {
            var discarded: usize = 0;
            if (discard_buffered) {
                const snapshot = try self.fifo.bufferedFrames();
                while (discarded < snapshot) {
                    const chunk = @min(
                        snapshot - discarded,
                        maximum_capture_chunk,
                    );
                    var scratch_views: [maximum_channels][]Sample = undefined;
                    for (
                        scratch_views[0..self.channel_count],
                        self.capture_scratch[0..self.channel_count],
                    ) |*view, *storage| {
                        view.* = storage[0..chunk];
                    }
                    const report = try self.fifo.read(
                        scratch_views[0..self.channel_count],
                    );
                    discarded += report.read_frames;
                    if (report.read_frames != chunk)
                        return error.CaptureRateRecoveryDiscardUnderflow;
                }
            }
            for (self.resamplers[0..self.channel_count]) |*stream| {
                try stream.configure(.{
                    .input_rate = self.capture_sample_rate,
                    .output_rate = self.render_sample_rate,
                });
            }
            self.controller.reset();
            self.operating_state = .priming;
            self.priming_target_frames =
                self.lifecycle.recovery_buffer_frames;
            self.control_frames_remaining = 0;
            return discarded;
        }

        fn processSynchronized(
            self: *Self,
            input_channels: []const []Sample,
            output_channels: []const []Sample,
            output_offset: usize,
        ) !usize {
            var expected: ?resampler.ProcessResult = null;
            for (
                self.resamplers[0..self.channel_count],
                output_channels,
                0..,
            ) |*stream, output, channel| {
                const input: []const Sample =
                    if (input_channels.len == 0)
                        &.{}
                    else
                        input_channels[channel];
                const result = try stream.process(
                    input,
                    output[output_offset..],
                );
                if (expected) |first| {
                    if (result.consumed != first.consumed or
                        result.produced != first.produced)
                        return error.CaptureRateTimelineMismatch;
                } else {
                    expected = result;
                }
            }
            const result = expected orelse
                return error.InvalidCaptureRateBridge;
            if (result.consumed !=
                (if (input_channels.len == 0)
                    0
                else
                    input_channels[0].len))
                return error.CaptureRateInputNotConsumed;
            return result.produced;
        }

        fn validateRenderOutputs(
            self: *const Self,
            channels: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidCaptureRateBridge;
            if (channels.len != self.channel_count)
                return error.CaptureChannelCountMismatch;
            const output_count = channels[0].len;
            if (output_count > maximum_output_frames)
                return error.CaptureRateOutputCapacityExceeded;
            for (channels, 0..) |channel, channel_index| {
                if (channel.len != output_count)
                    return error.CaptureFrameCountMismatch;
                if (try self.aliasesRetainedAudio(channel))
                    return error.CaptureBufferAliasesBridge;
                for (channels[0..channel_index]) |previous| {
                    if (try sampleSlicesOverlap(
                        Sample,
                        channel,
                        previous,
                    ))
                        return error.OverlappingCaptureOutputs;
                }
            }
        }

        fn aliasesRetainedAudio(
            self: *const Self,
            samples: anytype,
        ) !bool {
            for (self.fifo.storage[0..self.channel_count]) |*channel| {
                if (try sampleSlicesOverlap(
                    Sample,
                    samples,
                    channel,
                ))
                    return true;
            }
            for (
                self.capture_scratch[0..self.channel_count],
            ) |*channel| {
                if (try sampleSlicesOverlap(
                    Sample,
                    samples,
                    channel,
                ))
                    return true;
            }
            for (self.resamplers[0..self.channel_count]) |*stream| {
                if (try sampleSlicesOverlap(
                    Sample,
                    samples,
                    &stream.history,
                ))
                    return true;
                const coefficients: []const Sample = @as(
                    [*]const Sample,
                    @ptrCast(&stream.coefficients),
                )[0 .. resampler.phase_count * resampler.tap_count];
                if (try sampleSlicesOverlap(
                    Sample,
                    samples,
                    coefficients,
                ))
                    return true;
            }
            return false;
        }

        fn sameResamplerTimeline(
            left: *const Resampler,
            right: *const Resampler,
        ) bool {
            return left.input_rate == right.input_rate and
                left.output_rate == right.output_rate and
                left.delay_input_samples ==
                    right.delay_input_samples and
                left.input_count == right.input_count and
                left.next_output_index ==
                    right.next_output_index and
                left.next_input_position ==
                    right.next_input_position and
                left.rate_correction_ppm ==
                    right.rate_correction_ppm and
                left.input_step == right.input_step and
                left.drain_target == right.drain_target and
                left.backend == right.backend and
                left.configured == right.configured;
        }
    };
}

pub fn CaptureRenderBlock(comptime Sample: type) type {
    return struct {
        frame_count: usize,
        output_channels: []const []Sample = &.{},
        auxiliary_output_channels: []const []Sample = &.{},
        auxiliary_output_bus_channel_counts: []const usize = &.{},
        parameter_changes: []const process_api.ParameterChange = &.{},
        events: []const process_api.Event = &.{},
        output_events: ?*process_api.EventWriter = null,
        transport: ?process_api.Transport = null,
    };
}

pub fn SplitAudioCallback(comptime Sample: type) type {
    return struct {
        context: *anyopaque,
        capture_block: *const fn (
            *anyopaque,
            []const []const Sample,
        ) void,
        render_block: *const fn (
            *anyopaque,
            CaptureRenderBlock(Sample),
        ) void,
    };
}

pub const CaptureRateCallbackAdapterConfig = struct {
    main_input_channel_count: usize,
    auxiliary_input_bus_channel_counts: []const usize = &.{},
    capture_sample_rate: f64,
    render_sample_rate: f64,
    drift: ClockDriftConfig,
    lifecycle: CaptureRateLifecycleConfig = .{},
};

pub const CaptureRateCallbackStatistics = struct {
    fifo: CaptureFifoStatistics,
    capture_failures: usize,
    render_failures: usize,
};

/// Adapts asynchronous planar capture and render callbacks to the ordinary
/// standalone processor callback.
pub fn BoundedCaptureRateCallbackAdapter(
    comptime Sample: type,
    comptime maximum_channels: usize,
    comptime fifo_frame_capacity: usize,
    comptime maximum_capture_chunk: usize,
    comptime maximum_output_frames: usize,
    comptime maximum_auxiliary_buses: usize,
) type {
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError(
            "capture-rate adapter supports at most 254 auxiliary buses",
        );
    const Bridge = BoundedCaptureRateBridge(
        Sample,
        maximum_channels,
        fifo_frame_capacity,
        maximum_capture_chunk,
        maximum_output_frames,
    );

    return struct {
        const Self = @This();

        bridge: Bridge,
        downstream: AudioCallback(Sample),
        main_input_channel_count: usize,
        auxiliary_input_bus_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_input_bus_count: usize,
        corrected_input: [maximum_channels][maximum_output_frames]Sample =
            undefined,
        corrected_input_views: [maximum_channels][]const Sample = undefined,
        capture_failures: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        render_failures: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        pub fn init(
            config: CaptureRateCallbackAdapterConfig,
            downstream: AudioCallback(Sample),
        ) !Self {
            if (config.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            try validateBusChannelCounts(
                config.auxiliary_input_bus_channel_counts,
            );
            const channel_count = std.math.add(
                usize,
                config.main_input_channel_count,
                sumBusChannels(
                    config.auxiliary_input_bus_channel_counts,
                ),
            ) catch return error.TooManyChannels;
            if (channel_count == 0 or
                channel_count > maximum_channels or
                channel_count > process_api.max_audio_channels)
                return error.InvalidCaptureChannelCount;
            var result = Self{
                .bridge = try Bridge.init(.{
                    .channel_count = channel_count,
                    .capture_sample_rate = config.capture_sample_rate,
                    .render_sample_rate = config.render_sample_rate,
                    .drift = config.drift,
                    .lifecycle = config.lifecycle,
                }),
                .downstream = downstream,
                .main_input_channel_count = config.main_input_channel_count,
                .auxiliary_input_bus_count = config
                    .auxiliary_input_bus_channel_counts.len,
            };
            @memcpy(
                result
                    .auxiliary_input_bus_channel_counts[0..result.auxiliary_input_bus_count],
                config.auxiliary_input_bus_channel_counts,
            );
            return result;
        }

        /// Keep the adapter at a stable address until both callbacks stop.
        pub fn splitCallback(
            self: *Self,
        ) SplitAudioCallback(Sample) {
            return .{
                .context = self,
                .capture_block = captureFromDevice,
                .render_block = renderFromDevice,
            };
        }

        /// Called only by the capture producer.
        pub fn capture(
            self: *Self,
            input_channels: []const []const Sample,
        ) !CaptureFifoWriteReport {
            if (self.bridge.channel_count == 0 or
                self.bridge.channel_count > maximum_channels)
                return error.InvalidCaptureRateCallbackAdapter;
            for (input_channels) |input| {
                for (
                    self.corrected_input[0..self.bridge.channel_count],
                ) |*retained| {
                    if (try sampleSlicesOverlap(
                        Sample,
                        input,
                        retained,
                    ))
                        return error.CaptureBufferAliasesAdapter;
                }
            }
            return self.bridge.capture(input_channels);
        }

        /// Called only by the render consumer.
        pub fn render(
            self: *Self,
            block: CaptureRenderBlock(Sample),
        ) !CaptureRateRenderReport {
            try self.validateRenderBlock(block);
            var corrected: [maximum_channels][]Sample = undefined;
            for (
                corrected[0..self.bridge.channel_count],
                self.corrected_input[0..self.bridge.channel_count],
            ) |*view, *storage| {
                view.* = storage[0..block.frame_count];
            }
            const report = try self.bridge.render(
                corrected[0..self.bridge.channel_count],
            );
            if (report.state_after == .priming) {
                clearRenderOutputs(block);
                return report;
            }
            for (
                self.corrected_input_views[0..self.bridge.channel_count],
                corrected[0..self.bridge.channel_count],
            ) |*view, input| {
                view.* = input;
            }
            const main_end = self.main_input_channel_count;
            self.downstream.process_block(
                self.downstream.context,
                .{
                    .input_channels = self.corrected_input_views[0..main_end],
                    .auxiliary_input_channels = self.corrected_input_views[main_end..self.bridge.channel_count],
                    .auxiliary_input_bus_channel_counts = self.auxiliaryInputBusChannelCounts(),
                    .output_channels = block.output_channels,
                    .auxiliary_output_channels = block.auxiliary_output_channels,
                    .auxiliary_output_bus_channel_counts = block
                        .auxiliary_output_bus_channel_counts,
                    .parameter_changes = block.parameter_changes,
                    .events = block.events,
                    .output_events = block.output_events,
                    .transport = block.transport,
                },
            );
            return report;
        }

        pub fn statistics(
            self: *const Self,
        ) !CaptureRateCallbackStatistics {
            return .{
                .fifo = try self.bridge.statistics(),
                .capture_failures = self.capture_failures.load(.acquire),
                .render_failures = self.render_failures.load(.acquire),
            };
        }

        /// Reset only after capture and render callbacks have stopped.
        pub fn reset(self: *Self) !void {
            try self.bridge.reset();
            self.capture_failures.store(0, .release);
            self.render_failures.store(0, .release);
        }

        pub fn valid(self: *const Self) bool {
            if (!self.bridge.valid() or
                self.main_input_channel_count >
                    self.bridge.channel_count or
                self.auxiliary_input_bus_count >
                    maximum_auxiliary_buses)
                return false;
            return sumBusChannels(
                self.auxiliaryInputBusChannelCounts(),
            ) == self.bridge.channel_count -
                self.main_input_channel_count;
        }

        fn auxiliaryInputBusChannelCounts(
            self: *const Self,
        ) []const usize {
            return self
                .auxiliary_input_bus_channel_counts[0..self.auxiliary_input_bus_count];
        }

        fn validateRenderBlock(
            self: *const Self,
            block: CaptureRenderBlock(Sample),
        ) !void {
            if (!self.valid())
                return error.InvalidCaptureRateCallbackAdapter;
            if (block.frame_count > maximum_output_frames)
                return error.CaptureRateOutputCapacityExceeded;
            try validateBusChannelCounts(
                block.auxiliary_output_bus_channel_counts,
            );
            if (sumBusChannels(
                block.auxiliary_output_bus_channel_counts,
            ) != block.auxiliary_output_channels.len)
                return error.InvalidAuxiliaryOutputBusPartition;

            var previous: [maximum_routed_channels][]const Sample =
                undefined;
            var previous_count: usize = 0;
            for (block.output_channels) |output| {
                try self.validateOutput(
                    output,
                    block.frame_count,
                    previous[0..previous_count],
                );
                if (previous_count == previous.len)
                    return error.TooManyRoutedChannels;
                previous[previous_count] = output;
                previous_count += 1;
            }
            for (block.auxiliary_output_channels) |output| {
                try self.validateOutput(
                    output,
                    block.frame_count,
                    previous[0..previous_count],
                );
                if (previous_count == previous.len)
                    return error.TooManyRoutedChannels;
                previous[previous_count] = output;
                previous_count += 1;
            }
        }

        fn validateOutput(
            self: *const Self,
            output: []Sample,
            frame_count: usize,
            previous: []const []const Sample,
        ) !void {
            if (output.len != frame_count)
                return error.CaptureFrameCountMismatch;
            for (
                self.corrected_input[0..self.bridge.channel_count],
            ) |*retained| {
                if (try sampleSlicesOverlap(
                    Sample,
                    output,
                    retained,
                ))
                    return error.CaptureBufferAliasesAdapter;
            }
            for (previous) |prior| {
                if (try sampleSlicesOverlap(
                    Sample,
                    output,
                    prior,
                ))
                    return error.OverlappingCaptureOutputs;
            }
        }

        fn clearRenderOutputs(
            block: CaptureRenderBlock(Sample),
        ) void {
            for (block.output_channels) |output|
                @memset(output, 0.0);
            for (block.auxiliary_output_channels) |output|
                @memset(output, 0.0);
        }

        fn captureFromDevice(
            context: *anyopaque,
            input_channels: []const []const Sample,
        ) void {
            const self: *Self = @ptrCast(@alignCast(context));
            _ = self.capture(input_channels) catch {
                recordSaturating(&self.capture_failures);
                return;
            };
        }

        fn renderFromDevice(
            context: *anyopaque,
            block: CaptureRenderBlock(Sample),
        ) void {
            const self: *Self = @ptrCast(@alignCast(context));
            _ = self.render(block) catch {
                clearRenderOutputs(block);
                recordSaturating(&self.render_failures);
                return;
            };
        }
    };
}

pub fn CallbackBlock(comptime Sample: type) type {
    return struct {
        input_channels: []const []const Sample = &.{},
        auxiliary_input_channels: []const []const Sample = &.{},
        auxiliary_input_bus_channel_counts: []const usize = &.{},
        output_channels: []const []Sample = &.{},
        auxiliary_output_channels: []const []Sample = &.{},
        auxiliary_output_bus_channel_counts: []const usize = &.{},
        parameter_changes: []const process_api.ParameterChange = &.{},
        events: []const process_api.Event = &.{},
        output_events: ?*process_api.EventWriter = null,
        transport: ?process_api.Transport = null,
    };
}

pub const maximum_routed_channels =
    process_api.max_audio_channels * 2;

pub const DeviceChannelRouting = struct {
    device_input_channel_count: usize,
    device_output_channel_count: usize,
    input_routes: []const ?usize,
    output_routes: []const usize,

    pub fn validate(
        self: DeviceChannelRouting,
        configuration: DeviceConfiguration,
    ) !void {
        try configuration.validate();
        if (self.device_input_channel_count >
            process_api.max_audio_channels or
            self.device_output_channel_count >
                process_api.max_audio_channels)
            return error.TooManyDeviceChannels;
        const expected_input_count = configuration.input_channel_count +
            sumBusChannels(
                configuration.auxiliary_input_bus_channel_counts,
            );
        const expected_output_count = configuration.output_channel_count +
            sumBusChannels(
                configuration.auxiliary_output_bus_channel_counts,
            );
        if (self.input_routes.len != expected_input_count)
            return error.InputRouteCountMismatch;
        if (self.output_routes.len != expected_output_count)
            return error.OutputRouteCountMismatch;
        if (self.input_routes.len > maximum_routed_channels or
            self.output_routes.len > maximum_routed_channels)
            return error.TooManyRoutedChannels;
        for (self.input_routes) |route| {
            if (route) |device_channel| {
                if (device_channel >= self.device_input_channel_count)
                    return error.DeviceInputChannelOutOfRange;
            }
        }
        for (self.output_routes, 0..) |device_channel, index| {
            if (device_channel >= self.device_output_channel_count)
                return error.DeviceOutputChannelOutOfRange;
            for (self.output_routes[0..index]) |previous| {
                if (device_channel == previous)
                    return error.DuplicateDeviceOutputRoute;
            }
        }
    }
};

pub fn DeviceAudioBlock(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DeviceAudioBlock supports f32 and f64");

    return struct {
        frame_count: usize,
        input_channels: []const []const Sample = &.{},
        output_channels: []const []Sample = &.{},
        parameter_changes: []const process_api.ParameterChange = &.{},
        events: []const process_api.Event = &.{},
        output_events: ?*process_api.EventWriter = null,
        transport: ?process_api.Transport = null,
    };
}

pub fn DeviceChannelRouter(
    comptime Sample: type,
    comptime maximum_block_size: usize,
) type {
    return BoundedDeviceChannelRouter(
        Sample,
        maximum_block_size,
        audio_layout.max_auxiliary_audio_buses,
    );
}

pub fn BoundedDeviceChannelRouter(
    comptime Sample: type,
    comptime maximum_block_size: usize,
    comptime maximum_auxiliary_buses: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DeviceChannelRouter supports f32 and f64");
    if (maximum_block_size == 0)
        @compileError("DeviceChannelRouter requires a block capacity");
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError(
            "DeviceChannelRouter supports at most 254 auxiliary buses",
        );

    return struct {
        const Self = @This();

        main_input_channel_count: usize,
        main_output_channel_count: usize,
        auxiliary_input_bus_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_input_bus_count: usize,
        auxiliary_output_bus_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_output_bus_count: usize,
        device_input_channel_count: usize,
        device_output_channel_count: usize,
        input_routes: [maximum_routed_channels]?usize = @splat(null),
        input_route_count: usize,
        output_routes: [maximum_routed_channels]usize = @splat(0),
        output_route_count: usize,
        input_views: [maximum_routed_channels][]const Sample = undefined,
        output_views: [maximum_routed_channels][]Sample = undefined,
        silent_input: [maximum_block_size]Sample = @splat(0.0),

        pub fn init(
            configuration: DeviceConfiguration,
            routing: DeviceChannelRouting,
        ) !Self {
            if (configuration.max_block_size > maximum_block_size)
                return error.RoutingBlockCapacityExceeded;
            if (configuration.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses or
                configuration.auxiliary_output_bus_channel_counts.len >
                    maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            try routing.validate(configuration);
            var result = Self{
                .main_input_channel_count = configuration.input_channel_count,
                .main_output_channel_count = configuration.output_channel_count,
                .auxiliary_input_bus_count = configuration.auxiliary_input_bus_channel_counts.len,
                .auxiliary_output_bus_count = configuration.auxiliary_output_bus_channel_counts.len,
                .device_input_channel_count = routing.device_input_channel_count,
                .device_output_channel_count = routing.device_output_channel_count,
                .input_route_count = routing.input_routes.len,
                .output_route_count = routing.output_routes.len,
            };
            @memcpy(
                result.auxiliary_input_bus_channel_counts[0..result.auxiliary_input_bus_count],
                configuration.auxiliary_input_bus_channel_counts,
            );
            @memcpy(
                result.auxiliary_output_bus_channel_counts[0..result.auxiliary_output_bus_count],
                configuration.auxiliary_output_bus_channel_counts,
            );
            @memcpy(
                result.input_routes[0..result.input_route_count],
                routing.input_routes,
            );
            @memcpy(
                result.output_routes[0..result.output_route_count],
                routing.output_routes,
            );
            return result;
        }

        pub fn processCallback(
            self: *Self,
            runtime: anytype,
            block: DeviceAudioBlock(Sample),
        ) !void {
            errdefer clearDeviceOutputs(Sample, block);
            try self.validateBlock(block);
            clearDeviceOutputs(Sample, block);

            for (
                self.input_routes[0..self.input_route_count],
                self.input_views[0..self.input_route_count],
            ) |route, *view| {
                view.* = if (route) |device_channel|
                    block.input_channels[device_channel]
                else
                    self.silent_input[0..block.frame_count];
            }
            for (
                self.output_routes[0..self.output_route_count],
                self.output_views[0..self.output_route_count],
            ) |device_channel, *view| {
                view.* = block.output_channels[device_channel];
            }

            const main_input_end = self.main_input_channel_count;
            const main_output_end = self.main_output_channel_count;
            try runtime.processCallback(.{
                .input_channels = self.input_views[0..main_input_end],
                .auxiliary_input_channels = self.input_views[main_input_end..self.input_route_count],
                .auxiliary_input_bus_channel_counts = self.auxiliary_input_bus_channel_counts[0..self.auxiliary_input_bus_count],
                .output_channels = self.output_views[0..main_output_end],
                .auxiliary_output_channels = self.output_views[main_output_end..self.output_route_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_bus_channel_counts[0..self.auxiliary_output_bus_count],
                .parameter_changes = block.parameter_changes,
                .events = block.events,
                .output_events = block.output_events,
                .transport = block.transport,
            });
        }

        pub fn valid(self: *const Self) bool {
            if (self.main_input_channel_count >
                self.input_route_count or
                self.main_output_channel_count >
                    self.output_route_count or
                self.auxiliary_input_bus_count >
                    maximum_auxiliary_buses or
                self.auxiliary_output_bus_count >
                    maximum_auxiliary_buses or
                self.device_input_channel_count >
                    process_api.max_audio_channels or
                self.device_output_channel_count >
                    process_api.max_audio_channels or
                self.input_route_count > maximum_routed_channels or
                self.output_route_count > maximum_routed_channels)
                return false;
            if (sumBusChannels(
                self.auxiliary_input_bus_channel_counts[0..self.auxiliary_input_bus_count],
            ) != self.input_route_count -
                self.main_input_channel_count)
                return false;
            if (sumBusChannels(
                self.auxiliary_output_bus_channel_counts[0..self.auxiliary_output_bus_count],
            ) != self.output_route_count -
                self.main_output_channel_count)
                return false;
            for (self.input_routes[0..self.input_route_count]) |route| {
                if (route) |device_channel| {
                    if (device_channel >= self.device_input_channel_count)
                        return false;
                }
            }
            for (
                self.output_routes[0..self.output_route_count],
                0..,
            ) |device_channel, index| {
                if (device_channel >= self.device_output_channel_count)
                    return false;
                for (self.output_routes[0..index]) |previous| {
                    if (device_channel == previous) return false;
                }
            }
            return true;
        }

        fn validateBlock(
            self: *const Self,
            block: DeviceAudioBlock(Sample),
        ) !void {
            if (!self.valid()) return error.InvalidDeviceChannelRouter;
            if (block.frame_count > maximum_block_size)
                return error.RoutingBlockCapacityExceeded;
            if (block.input_channels.len !=
                self.device_input_channel_count)
                return error.DeviceInputChannelCountMismatch;
            if (block.output_channels.len !=
                self.device_output_channel_count)
                return error.DeviceOutputChannelCountMismatch;
            for (block.input_channels) |channel| {
                if (channel.len != block.frame_count)
                    return error.DeviceChannelFrameCountMismatch;
            }
            for (block.output_channels) |channel| {
                if (channel.len != block.frame_count)
                    return error.DeviceChannelFrameCountMismatch;
            }
        }
    };
}

pub fn StandaloneRuntime(
    comptime Plugin: type,
    comptime Sample: type,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StandaloneRuntime supports f32 and f64");

    const Runtime = runtime_mod.ProcessorRuntime(Plugin);
    const Spec = spec_mod.PluginSpec(Plugin);

    return struct {
        const Self = @This();

        runtime: Runtime,
        configuration: ?struct {
            sample_rate: f64,
            max_block_size: u32,
        } = null,
        processed_frames: u64 = 0,

        pub fn init(
            allocator: std.mem.Allocator,
            params: Plugin.Params,
        ) !Self {
            return .{
                .runtime = try Runtime.init(allocator, params),
            };
        }

        pub fn start(
            self: *Self,
            configuration: DeviceConfiguration,
        ) !void {
            try configuration.validate();
            try validatePluginBusConfiguration(Spec, configuration);
            try self.runtime.prepare(.{
                .sample_rate = configuration.sample_rate,
                .max_block_size = configuration.max_block_size,
                .process_mode = .realtime,
            });
            self.runtime.activate() catch |activate_error| {
                self.runtime.releaseResources() catch {};
                return activate_error;
            };
            self.configuration = .{
                .sample_rate = configuration.sample_rate,
                .max_block_size = configuration.max_block_size,
            };
            self.processed_frames = 0;
        }

        pub fn processCallback(
            self: *Self,
            block: CallbackBlock(Sample),
        ) !void {
            errdefer clearOutputs(Sample, block);
            const configuration = self.configuration orelse
                return error.DeviceNotStarted;
            try validateCallbackBusConfiguration(Spec, block);
            var context = try process_api.BoundedProcessContext(
                Sample,
                Spec.auxiliary_audio_bus_capacity,
            ).initWithOptions(.{
                .sample_rate = configuration.sample_rate,
                .process_mode = .realtime,
                .input_channels = block.input_channels,
                .sidechain_input_channels = block.auxiliary_input_channels,
                .auxiliary_input_bus_channel_counts = block.auxiliary_input_bus_channel_counts,
                .output_channels = block.output_channels,
                .auxiliary_output_channels = block.auxiliary_output_channels,
                .auxiliary_output_bus_channel_counts = block.auxiliary_output_bus_channel_counts,
                .attachments = .{
                    .parameter_changes = block.parameter_changes,
                    .events = block.events,
                    .output_events = block.output_events,
                },
                .transport = block.transport,
            });
            if (context.frameCount() > configuration.max_block_size)
                return error.BlockTooLarge;

            if (Sample == f32)
                try self.runtime.process(&context)
            else
                try self.runtime.process64(&context);

            const frame_count =
                std.math.cast(u64, context.frameCount()) orelse
                std.math.maxInt(u64);
            self.processed_frames +|= frame_count;
        }

        pub fn stop(self: *Self) !void {
            try self.runtime.deactivate();
            try self.runtime.releaseResources();
            self.configuration = null;
        }

        pub fn processedFrameCount(self: *const Self) u64 {
            return self.processed_frames;
        }

        pub fn deinit(self: *Self) void {
            self.runtime.deinit();
            self.configuration = null;
        }
    };
}

pub const Midi1CallbackPacket = struct {
    sample_offset: usize = 0,
    bus_index: i32 = 0,
    message: process_api.Midi1Message = .{
        .storage = @splat(0),
        .length = 0,
    },

    pub fn valid(
        self: Midi1CallbackPacket,
        frame_count: usize,
    ) bool {
        return self.sample_offset < frame_count and
            self.bus_index >= 0 and
            self.message.valid();
    }
};

pub fn Midi1EventBuffer(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("Midi1EventBuffer capacity must be positive");

    return struct {
        storage: [capacity]process_api.Event = @splat(process_api.Event.other(0)),
        count: usize = 0,

        pub fn reset(self: *@This()) void {
            self.storage = @splat(process_api.Event.other(0));
            self.count = 0;
        }

        pub fn append(
            self: *@This(),
            packet: Midi1CallbackPacket,
            frame_count: usize,
        ) !void {
            if (self.count > capacity)
                return error.InvalidMidiEventBuffer;
            if (!packet.valid(frame_count))
                return error.InvalidMidiPacket;
            if (self.count == capacity)
                return error.EventCapacityExceeded;
            const event = packet.message.toEvent(
                packet.sample_offset,
                packet.bus_index,
            ) orelse return error.UnsupportedMidiMessage;
            self.storage[self.count] = event;
            self.count += 1;
        }

        pub fn events(
            self: *const @This(),
            frame_count: usize,
        ) !process_api.Events {
            if (!self.valid())
                return error.InvalidMidiEventBuffer;
            return process_api.Events.init(
                self.storage[0..self.count],
                frame_count,
            );
        }

        pub fn valid(self: *const @This()) bool {
            return self.count <= capacity;
        }
    };
}

pub const Midi1OutputReport = struct {
    sent: usize = 0,
    unsupported: usize = 0,
    rejected: usize = 0,
};

pub const Midi1OutputSink = struct {
    context: *anyopaque,
    send_message: *const fn (
        *anyopaque,
        Midi1CallbackPacket,
    ) bool,

    pub fn sendEvents(
        self: *Midi1OutputSink,
        events: process_api.Events,
    ) Midi1OutputReport {
        var report = Midi1OutputReport{};
        for (events.items) |event| {
            const message = process_api.Midi1Message.fromEvent(event) catch {
                report.rejected += 1;
                continue;
            } orelse {
                report.unsupported += 1;
                continue;
            };
            const packet = Midi1CallbackPacket{
                .sample_offset = event.sample_offset,
                .bus_index = event.bus_index,
                .message = message,
            };
            if (self.send_message(self.context, packet))
                report.sent += 1
            else
                report.rejected += 1;
        }
        return report;
    }
};

pub const TimestampedMidi1Packet = struct {
    timestamp_nanoseconds: u64 = 0,
    message: process_api.Midi1Message = .{
        .storage = @splat(0),
        .length = 0,
    },
};

/// Use from exactly one device producer and one audio-thread consumer
pub fn Midi1InputQueue(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("Midi1InputQueue capacity must be positive");
    if (capacity == std.math.maxInt(usize))
        @compileError("Midi1InputQueue capacity is too large");

    const slot_count = capacity + 1;

    return struct {
        const Self = @This();

        storage: [slot_count]TimestampedMidi1Packet = @splat(.{}),
        read_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        write_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        last_timestamp_nanoseconds: ?u64 = null,

        pub fn push(
            self: *Self,
            packet: TimestampedMidi1Packet,
        ) !void {
            if (!packet.message.valid())
                return error.InvalidMidiPacket;
            if (self.last_timestamp_nanoseconds) |last_timestamp| {
                if (packet.timestamp_nanoseconds < last_timestamp)
                    return error.OutOfOrderMidiTimestamp;
            }
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            if (write >= slot_count or read >= slot_count)
                return error.InvalidMidiInputQueue;
            const next = nextQueueIndex(write, slot_count);
            if (next == read) return error.MidiInputQueueFull;
            self.storage[write] = packet;
            self.write_index.store(next, .release);
            self.last_timestamp_nanoseconds =
                packet.timestamp_nanoseconds;
        }

        pub fn peek(self: *const Self) !?TimestampedMidi1Packet {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidMidiInputQueue;
            return if (read == write) null else self.storage[read];
        }

        pub fn pop(self: *Self) !?TimestampedMidi1Packet {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidMidiInputQueue;
            if (read == write) return null;
            const packet = self.storage[read];
            self.read_index.store(
                nextQueueIndex(read, slot_count),
                .release,
            );
            return packet;
        }

        pub fn pendingCount(self: *const Self) !usize {
            const read = self.read_index.load(.acquire);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidMidiInputQueue;
            return if (write >= read)
                write - read
            else
                slot_count - read + write;
        }

        /// Reset only after both producer and consumer have stopped
        pub fn reset(self: *Self) void {
            self.storage = @splat(.{});
            self.read_index.store(0, .release);
            self.write_index.store(0, .release);
            self.last_timestamp_nanoseconds = null;
        }

        pub fn valid(self: *const Self) bool {
            return self.read_index.load(.acquire) < slot_count and
                self.write_index.load(.acquire) < slot_count;
        }
    };
}

pub const Midi1BlockScheduleReport = struct {
    scheduled: usize = 0,
    late: usize = 0,
    capacity_exhausted: bool = false,
    future_pending: bool = false,
};

/// Bridge one MIDI device callback to one audio-thread block consumer
pub fn Midi1BlockScheduler(comptime queue_capacity: usize) type {
    return struct {
        const Self = @This();

        queue: Midi1InputQueue(queue_capacity) = .{},
        rejected_packets: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        pub fn receive(
            self: *Self,
            packet: TimestampedMidi1Packet,
        ) !void {
            try self.queue.push(packet);
        }

        /// Keep the scheduler at a stable address until input has stopped
        pub fn inputCallback(self: *Self) Midi1InputCallback {
            return .{
                .context = self,
                .receive = receiveFromDevice,
            };
        }

        pub fn rejectedPacketCount(self: *const Self) usize {
            return self.rejected_packets.load(.monotonic);
        }

        pub fn fillBlock(
            self: *Self,
            comptime event_capacity: usize,
            output: *Midi1EventBuffer(event_capacity),
            block_start_nanoseconds: u64,
            sample_rate: f64,
            frame_count: usize,
            bus_index: i32,
        ) !Midi1BlockScheduleReport {
            if (!std.math.isFinite(sample_rate) or
                sample_rate <= 0.0)
                return error.InvalidSampleRate;
            if (bus_index < 0) return error.InvalidMidiBusIndex;
            if (!output.valid())
                return error.InvalidMidiEventBuffer;

            var report = Midi1BlockScheduleReport{};
            while (try self.queue.peek()) |packet| {
                const sample_offset = if (packet.timestamp_nanoseconds <=
                    block_start_nanoseconds)
                    0
                else blk: {
                    const delta_nanoseconds =
                        packet.timestamp_nanoseconds -
                        block_start_nanoseconds;
                    const offset = @floor(
                        @as(f64, @floatFromInt(delta_nanoseconds)) *
                            sample_rate /
                            @as(f64, std.time.ns_per_s),
                    );
                    if (!std.math.isFinite(offset) or
                        offset >= @as(f64, @floatFromInt(frame_count)))
                        break;
                    break :blk @as(usize, @intFromFloat(offset));
                };
                if (frame_count == 0) break;
                if (output.count == event_capacity) {
                    report.capacity_exhausted = true;
                    break;
                }
                try output.append(.{
                    .sample_offset = sample_offset,
                    .bus_index = bus_index,
                    .message = packet.message,
                }, frame_count);
                _ = try self.queue.pop() orelse
                    return error.InvalidMidiInputQueue;
                report.scheduled += 1;
                if (packet.timestamp_nanoseconds <
                    block_start_nanoseconds)
                    report.late += 1;
            }
            report.future_pending = (try self.queue.peek()) != null;
            return report;
        }

        /// Reset only after the MIDI callback and audio callback have stopped
        pub fn reset(self: *Self) void {
            self.queue.reset();
            self.rejected_packets.store(0, .monotonic);
        }

        fn receiveFromDevice(
            context: *anyopaque,
            packet: TimestampedMidi1Packet,
        ) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.receive(packet) catch
                recordSaturating(&self.rejected_packets);
        }
    };
}

pub const Midi1InputCallback = struct {
    context: *anyopaque,
    receive: *const fn (
        *anyopaque,
        TimestampedMidi1Packet,
    ) void,
};

pub const Midi1InputDevice = struct {
    context: *anyopaque,
    start_input: *const fn (
        *anyopaque,
        Midi1InputCallback,
    ) anyerror!void,
    stop_input: *const fn (*anyopaque) void,

    pub fn start(
        self: *Midi1InputDevice,
        callback: Midi1InputCallback,
    ) !void {
        try self.start_input(self.context, callback);
    }

    pub fn stop(self: *Midi1InputDevice) void {
        self.stop_input(self.context);
    }
};

pub const Midi1OutputDevice = struct {
    context: *anyopaque,
    send_output: *const fn (
        *anyopaque,
        TimestampedMidi1Packet,
    ) anyerror!void,

    pub fn send(
        self: *Midi1OutputDevice,
        packet: TimestampedMidi1Packet,
    ) !void {
        if (!packet.message.valid())
            return error.InvalidMidiPacket;
        try self.send_output(self.context, packet);
    }
};

pub const TimestampedUmpPacket = struct {
    timestamp_nanoseconds: u64 = 0,
    packet: process_api.UmpPacket = .{
        .storage = @splat(0),
        .word_count = 0,
    },

    pub fn valid(self: TimestampedUmpPacket) bool {
        return self.packet.valid();
    }
};

pub const UmpBlockPacket = struct {
    sample_offset: usize = 0,
    packet: process_api.UmpPacket = .{
        .storage = @splat(0),
        .word_count = 0,
    },

    pub fn valid(
        self: UmpBlockPacket,
        frame_count: usize,
    ) bool {
        return self.sample_offset < frame_count and
            self.packet.valid();
    }
};

pub fn UmpBlockBuffer(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("UmpBlockBuffer capacity must be positive");

    return struct {
        storage: [capacity]UmpBlockPacket = @splat(.{}),
        count: usize = 0,

        pub fn reset(self: *@This()) void {
            self.storage = @splat(.{});
            self.count = 0;
        }

        pub fn append(
            self: *@This(),
            packet: UmpBlockPacket,
            frame_count: usize,
        ) !void {
            if (self.count > capacity)
                return error.InvalidUmpBlockBuffer;
            if (!packet.valid(frame_count))
                return error.InvalidUmpPacket;
            if (self.count == capacity)
                return error.UmpCapacityExceeded;
            self.storage[self.count] = packet;
            self.count += 1;
        }

        pub fn packets(self: *const @This()) ![]const UmpBlockPacket {
            if (!self.valid())
                return error.InvalidUmpBlockBuffer;
            return self.storage[0..self.count];
        }

        pub fn valid(self: *const @This()) bool {
            return self.count <= capacity;
        }
    };
}

/// Use from exactly one device producer and one audio-thread consumer
pub fn UmpInputQueue(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("UmpInputQueue capacity must be positive");
    if (capacity == std.math.maxInt(usize))
        @compileError("UmpInputQueue capacity is too large");

    const slot_count = capacity + 1;

    return struct {
        const Self = @This();

        storage: [slot_count]TimestampedUmpPacket = @splat(.{}),
        read_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        write_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        last_timestamp_nanoseconds: ?u64 = null,

        pub fn push(
            self: *Self,
            packet: TimestampedUmpPacket,
        ) !void {
            if (!packet.valid())
                return error.InvalidUmpPacket;
            if (self.last_timestamp_nanoseconds) |last_timestamp| {
                if (packet.timestamp_nanoseconds < last_timestamp)
                    return error.OutOfOrderUmpTimestamp;
            }
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            if (write >= slot_count or read >= slot_count)
                return error.InvalidUmpInputQueue;
            const next = nextQueueIndex(write, slot_count);
            if (next == read) return error.UmpInputQueueFull;
            self.storage[write] = packet;
            self.write_index.store(next, .release);
            self.last_timestamp_nanoseconds =
                packet.timestamp_nanoseconds;
        }

        pub fn peek(self: *const Self) !?TimestampedUmpPacket {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidUmpInputQueue;
            return if (read == write) null else self.storage[read];
        }

        pub fn pop(self: *Self) !?TimestampedUmpPacket {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidUmpInputQueue;
            if (read == write) return null;
            const packet = self.storage[read];
            self.read_index.store(
                nextQueueIndex(read, slot_count),
                .release,
            );
            return packet;
        }

        pub fn pendingCount(self: *const Self) !usize {
            const read = self.read_index.load(.acquire);
            const write = self.write_index.load(.acquire);
            if (read >= slot_count or write >= slot_count)
                return error.InvalidUmpInputQueue;
            return if (write >= read)
                write - read
            else
                slot_count - read + write;
        }

        /// Reset only after both producer and consumer have stopped
        pub fn reset(self: *Self) void {
            self.storage = @splat(.{});
            self.read_index.store(0, .release);
            self.write_index.store(0, .release);
            self.last_timestamp_nanoseconds = null;
        }

        pub fn valid(self: *const Self) bool {
            return self.read_index.load(.acquire) < slot_count and
                self.write_index.load(.acquire) < slot_count;
        }
    };
}

pub const UmpBlockScheduleReport = struct {
    scheduled: usize = 0,
    late: usize = 0,
    capacity_exhausted: bool = false,
    future_pending: bool = false,
};

/// Bridge one UMP device callback to one audio-thread block consumer
pub fn UmpBlockScheduler(comptime queue_capacity: usize) type {
    return struct {
        const Self = @This();

        queue: UmpInputQueue(queue_capacity) = .{},
        rejected_packets: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        pub fn receive(
            self: *Self,
            packet: TimestampedUmpPacket,
        ) !void {
            try self.queue.push(packet);
        }

        /// Keep the scheduler at a stable address until input has stopped
        pub fn inputCallback(self: *Self) UmpInputCallback {
            return .{
                .context = self,
                .receive = receiveFromDevice,
            };
        }

        pub fn rejectedPacketCount(self: *const Self) usize {
            return self.rejected_packets.load(.monotonic);
        }

        pub fn fillBlock(
            self: *Self,
            comptime packet_capacity: usize,
            output: *UmpBlockBuffer(packet_capacity),
            block_start_nanoseconds: u64,
            sample_rate: f64,
            frame_count: usize,
        ) !UmpBlockScheduleReport {
            if (!std.math.isFinite(sample_rate) or
                sample_rate <= 0.0)
                return error.InvalidSampleRate;
            if (!output.valid())
                return error.InvalidUmpBlockBuffer;

            var report = UmpBlockScheduleReport{};
            while (try self.queue.peek()) |packet| {
                const sample_offset = if (packet.timestamp_nanoseconds <=
                    block_start_nanoseconds)
                    0
                else blk: {
                    const delta_nanoseconds =
                        packet.timestamp_nanoseconds -
                        block_start_nanoseconds;
                    const offset = @floor(
                        @as(f64, @floatFromInt(delta_nanoseconds)) *
                            sample_rate /
                            @as(f64, std.time.ns_per_s),
                    );
                    if (!std.math.isFinite(offset) or
                        offset >= @as(f64, @floatFromInt(frame_count)))
                        break;
                    break :blk @as(usize, @intFromFloat(offset));
                };
                if (frame_count == 0) break;
                if (output.count == packet_capacity) {
                    report.capacity_exhausted = true;
                    break;
                }
                try output.append(.{
                    .sample_offset = sample_offset,
                    .packet = packet.packet,
                }, frame_count);
                _ = try self.queue.pop() orelse
                    return error.InvalidUmpInputQueue;
                report.scheduled += 1;
                if (packet.timestamp_nanoseconds <
                    block_start_nanoseconds)
                    report.late += 1;
            }
            report.future_pending = (try self.queue.peek()) != null;
            return report;
        }

        /// Reset only after the UMP callback and audio callback have stopped
        pub fn reset(self: *Self) void {
            self.queue.reset();
            self.rejected_packets.store(0, .monotonic);
        }

        fn receiveFromDevice(
            context: *anyopaque,
            packet: TimestampedUmpPacket,
        ) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.receive(packet) catch
                recordSaturating(&self.rejected_packets);
        }
    };
}

pub const UmpInputCallback = struct {
    context: *anyopaque,
    receive: *const fn (
        *anyopaque,
        TimestampedUmpPacket,
    ) void,
};

pub const UmpInputDevice = struct {
    context: *anyopaque,
    start_input: *const fn (
        *anyopaque,
        UmpInputCallback,
    ) anyerror!void,
    stop_input: *const fn (*anyopaque) void,

    pub fn start(
        self: *UmpInputDevice,
        callback: UmpInputCallback,
    ) !void {
        try self.start_input(self.context, callback);
    }

    pub fn stop(self: *UmpInputDevice) void {
        self.stop_input(self.context);
    }
};

pub const UmpOutputReport = struct {
    sent: usize = 0,
    invalid: usize = 0,
    rejected: usize = 0,
};

pub const UmpOutputDevice = struct {
    context: *anyopaque,
    send_output: *const fn (
        *anyopaque,
        TimestampedUmpPacket,
    ) anyerror!void,

    pub fn send(
        self: *UmpOutputDevice,
        packet: TimestampedUmpPacket,
    ) !void {
        if (!packet.valid())
            return error.InvalidUmpPacket;
        try self.send_output(self.context, packet);
    }

    pub fn sendBlock(
        self: *UmpOutputDevice,
        packets: []const UmpBlockPacket,
        block_start_nanoseconds: u64,
        sample_rate: f64,
        frame_count: usize,
    ) !UmpOutputReport {
        if (!std.math.isFinite(sample_rate) or
            sample_rate <= 0.0)
            return error.InvalidSampleRate;

        var report = UmpOutputReport{};
        for (packets) |packet| {
            if (!packet.valid(frame_count)) {
                report.invalid += 1;
                continue;
            }
            const delta_float = @floor(
                @as(f64, @floatFromInt(packet.sample_offset)) *
                    @as(f64, std.time.ns_per_s) /
                    sample_rate,
            );
            if (!std.math.isFinite(delta_float) or
                delta_float >= @as(
                    f64,
                    @floatFromInt(std.math.maxInt(u64)),
                ))
            {
                report.invalid += 1;
                continue;
            }
            const delta_nanoseconds: u64 =
                @intFromFloat(delta_float);
            const timestamp_nanoseconds = std.math.add(
                u64,
                block_start_nanoseconds,
                delta_nanoseconds,
            ) catch {
                report.invalid += 1;
                continue;
            };
            self.send(.{
                .timestamp_nanoseconds = timestamp_nanoseconds,
                .packet = packet.packet,
            }) catch {
                report.rejected += 1;
                continue;
            };
            report.sent += 1;
        }
        return report;
    }
};

pub fn AudioCallback(comptime Sample: type) type {
    return struct {
        context: *anyopaque,
        process_block: *const fn (
            *anyopaque,
            CallbackBlock(Sample),
        ) void,
    };
}

pub fn AudioDevice(comptime Sample: type) type {
    return struct {
        context: *anyopaque,
        start_audio: *const fn (
            *anyopaque,
            DeviceConfiguration,
            AudioCallback(Sample),
        ) anyerror!void,
        stop_audio: *const fn (*anyopaque) void,

        pub fn start(
            self: *@This(),
            configuration: DeviceConfiguration,
            callback: AudioCallback(Sample),
        ) !void {
            try configuration.validate();
            // Backends must copy the borrowed bus-count slices before returning
            try self.start_audio(
                self.context,
                configuration,
                callback,
            );
        }

        pub fn stop(self: *@This()) void {
            self.stop_audio(self.context);
        }
    };
}

pub fn StandaloneApplication(
    comptime Plugin: type,
    comptime Sample: type,
) type {
    const Runtime = StandaloneRuntime(Plugin, Sample);

    return struct {
        const Self = @This();

        runtime: Runtime,
        audio_device: AudioDevice(Sample),
        running: bool = false,
        callback_failures: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        pub fn init(
            allocator: std.mem.Allocator,
            params: Plugin.Params,
            audio_device: AudioDevice(Sample),
        ) !Self {
            return .{
                .runtime = try Runtime.init(allocator, params),
                .audio_device = audio_device,
            };
        }

        /// Keep the application at a stable address until `stop` returns.
        pub fn start(
            self: *Self,
            configuration: DeviceConfiguration,
        ) !void {
            if (self.running) return error.ApplicationAlreadyRunning;
            try self.runtime.start(configuration);
            self.audio_device.start(configuration, .{
                .context = self,
                .process_block = processAudioBlock,
            }) catch |start_error| {
                self.runtime.stop() catch {};
                return start_error;
            };
            self.running = true;
        }

        pub fn stop(self: *Self) !void {
            if (!self.running) return error.ApplicationNotRunning;
            self.audio_device.stop();
            self.running = false;
            try self.runtime.stop();
        }

        pub fn callbackFailureCount(self: *const Self) usize {
            return self.callback_failures.load(.acquire);
        }

        pub fn deinit(self: *Self) void {
            if (self.running) {
                self.audio_device.stop();
                self.runtime.stop() catch {};
                self.running = false;
            }
            self.runtime.deinit();
        }

        fn processAudioBlock(
            context: *anyopaque,
            block: CallbackBlock(Sample),
        ) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.runtime.processCallback(block) catch
                recordSaturating(&self.callback_failures);
        }
    };
}

fn validateBusChannelCounts(counts: []const usize) !void {
    if (counts.len >= std.math.maxInt(u8))
        return error.TooManyAudioBuses;
    var total: usize = 0;
    for (counts) |count| {
        if (count == 0 or count > process_api.max_audio_channels)
            return error.InvalidAudioBusChannelCount;
        total = std.math.add(usize, total, count) catch
            return error.TooManyChannels;
        if (total > process_api.max_audio_channels)
            return error.TooManyChannels;
    }
}

fn validatePluginBusConfiguration(
    comptime Spec: type,
    configuration: DeviceConfiguration,
) !void {
    if (configuration.input_channel_count !=
        Spec.audio_input_layout.channelCount())
        return error.UnsupportedInputLayout;
    if (configuration.output_channel_count !=
        Spec.audio_output_layout.channelCount())
        return error.UnsupportedOutputLayout;
    if (!matchingAuxiliaryInputBuses(
        Spec,
        configuration.auxiliary_input_bus_channel_counts,
    ))
        return error.UnsupportedAuxiliaryInputLayout;
    if (!matchingAuxiliaryOutputBuses(
        Spec,
        configuration.auxiliary_output_bus_channel_counts,
    ))
        return error.UnsupportedAuxiliaryOutputLayout;
}

fn validateCallbackBusConfiguration(
    comptime Spec: type,
    block: anytype,
) !void {
    if (block.input_channels.len !=
        Spec.audio_input_layout.channelCount())
        return error.UnsupportedInputLayout;
    if (block.output_channels.len !=
        Spec.audio_output_layout.channelCount())
        return error.UnsupportedOutputLayout;
    if (!matchingAuxiliaryInputBuses(
        Spec,
        block.auxiliary_input_bus_channel_counts,
    ))
        return error.UnsupportedAuxiliaryInputLayout;
    if (!matchingAuxiliaryOutputBuses(
        Spec,
        block.auxiliary_output_bus_channel_counts,
    ))
        return error.UnsupportedAuxiliaryOutputLayout;
    if (sumBusChannels(
        block.auxiliary_input_bus_channel_counts,
    ) != block.auxiliary_input_channels.len)
        return error.UnsupportedAuxiliaryInputLayout;
    if (sumBusChannels(
        block.auxiliary_output_bus_channel_counts,
    ) != block.auxiliary_output_channels.len)
        return error.UnsupportedAuxiliaryOutputLayout;
}

fn matchingAuxiliaryInputBuses(
    comptime Spec: type,
    counts: []const usize,
) bool {
    const layouts = Spec.audio_auxiliary_input_layouts;
    if (counts.len != layouts.len) return false;
    for (layouts, counts) |layout, count| {
        if (count != layout.channelCount()) return false;
    }
    return true;
}

fn matchingAuxiliaryOutputBuses(
    comptime Spec: type,
    counts: []const usize,
) bool {
    const compatibility_count: usize =
        @intFromBool(Spec.audio_auxiliary_output_layout.hasBus());
    const layouts = Spec.audio_auxiliary_output_layouts;
    if (layouts.len != 0) {
        if (counts.len != layouts.len) return false;
        for (layouts, counts) |layout, count| {
            if (count != layout.channelCount()) return false;
        }
        return true;
    }
    if (counts.len != compatibility_count) return false;
    if (compatibility_count == 1 and
        counts[0] !=
            Spec.audio_auxiliary_output_layout.channelCount())
        return false;
    return true;
}

fn sumBusChannels(counts: []const usize) usize {
    var total: usize = 0;
    for (counts) |count|
        total +|= count;
    return total;
}

fn nextQueueIndex(index: usize, slot_count: usize) usize {
    const next = index + 1;
    return if (next == slot_count) 0 else next;
}

fn advanceFifoIndex(
    index: usize,
    count: usize,
    slot_count: usize,
) usize {
    const until_end = slot_count - index;
    return if (count < until_end)
        index + count
    else
        count - until_end;
}

fn sampleSlicesOverlap(
    comptime Sample: type,
    left: anytype,
    right: anytype,
) !bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_bytes = std.math.mul(
        usize,
        left.len,
        @sizeOf(Sample),
    ) catch return error.InvalidCaptureBuffer;
    const right_bytes = std.math.mul(
        usize,
        right.len,
        @sizeOf(Sample),
    ) catch return error.InvalidCaptureBuffer;
    const left_end = std.math.add(
        usize,
        left_start,
        left_bytes,
    ) catch return error.InvalidCaptureBuffer;
    const right_end = std.math.add(
        usize,
        right_start,
        right_bytes,
    ) catch return error.InvalidCaptureBuffer;
    return left_start < right_end and right_start < left_end;
}

fn clearOutputs(
    comptime Sample: type,
    block: CallbackBlock(Sample),
) void {
    for (block.output_channels) |channel|
        @memset(channel, 0);
    for (block.auxiliary_output_channels) |channel|
        @memset(channel, 0);
}

fn clearDeviceOutputs(
    comptime Sample: type,
    block: DeviceAudioBlock(Sample),
) void {
    for (block.output_channels) |channel|
        @memset(channel, 0);
}

fn recordSaturating(value: *std.atomic.Value(usize)) void {
    recordSaturatingAmount(value, 1);
}

fn recordSaturatingAmount(
    value: *std.atomic.Value(usize),
    amount: usize,
) void {
    if (amount == 0) return;
    var current = value.load(.monotonic);
    while (current != std.math.maxInt(usize)) {
        const next = std.math.add(
            usize,
            current,
            amount,
        ) catch std.math.maxInt(usize);
        if (value.cmpxchgWeak(
            current,
            next,
            .monotonic,
            .monotonic,
        )) |observed| {
            current = observed;
        } else return;
    }
}

test "bounded capture FIFO preserves planar order across wraparound" {
    const Fifo = BoundedCaptureFifo(f32, 2, 5);
    var fifo = try Fifo.init(2);
    for (fifo.storage) |channel| {
        try std.testing.expectEqual(@as([6]f32, @splat(0.0)), channel);
    }
    const first_left = [_]f32{ 1, 2, 3, 4 };
    const first_right = [_]f32{ 11, 12, 13, 14 };
    const first = [_][]const f32{ &first_left, &first_right };
    try std.testing.expectEqual(
        CaptureFifoWriteReport{
            .written_frames = 4,
            .dropped_frames = 0,
        },
        try fifo.write(&first),
    );

    var prefix_left: [3]f32 = undefined;
    var prefix_right: [3]f32 = undefined;
    const prefix = [_][]f32{ &prefix_left, &prefix_right };
    try std.testing.expectEqual(
        CaptureFifoReadReport{
            .read_frames = 3,
            .silent_frames = 0,
        },
        try fifo.read(&prefix),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 2, 3 },
        &prefix_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 11, 12, 13 },
        &prefix_right,
    );

    const second_left = [_]f32{ 5, 6, 7, 8 };
    const second_right = [_]f32{ 15, 16, 17, 18 };
    const second = [_][]const f32{ &second_left, &second_right };
    try std.testing.expectEqual(
        @as(usize, 4),
        (try fifo.write(&second)).written_frames,
    );
    try std.testing.expectEqual(@as(usize, 5), try fifo.bufferedFrames());

    var output_left: [6]f32 = @splat(-1);
    var output_right: [6]f32 = @splat(-1);
    const output = [_][]f32{ &output_left, &output_right };
    try std.testing.expectEqual(
        CaptureFifoReadReport{
            .read_frames = 5,
            .silent_frames = 1,
        },
        try fifo.read(&output),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 4, 5, 6, 7, 8, 0 },
        &output_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 14, 15, 16, 17, 18, 0 },
        &output_right,
    );
    try std.testing.expectEqual(
        CaptureFifoStatistics{
            .buffered_frames = 0,
            .written_frames = 8,
            .read_frames = 8,
            .dropped_frames = 0,
            .silent_frames = 1,
        },
        try fifo.statistics(),
    );
    fifo.reset();
    for (fifo.storage) |channel| {
        try std.testing.expectEqual(@as([6]f32, @splat(0.0)), channel);
    }
}

test "bounded capture FIFO drops newest overflow and reports saturation" {
    const Fifo = BoundedCaptureFifo(f64, 1, 4);
    var fifo = try Fifo.init(1);
    const input = [_]f64{ 1, 2, 3, 4, 5, 6 };
    const channels = [_][]const f64{&input};
    try std.testing.expectEqual(
        CaptureFifoWriteReport{
            .written_frames = 4,
            .dropped_frames = 2,
        },
        try fifo.write(&channels),
    );

    var output: [4]f64 = undefined;
    const outputs = [_][]f64{&output};
    _ = try fifo.read(&outputs);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4 },
        &output,
    );

    fifo.written_frames.store(
        std.math.maxInt(usize) - 1,
        .monotonic,
    );
    fifo.dropped_frames.store(
        std.math.maxInt(usize) - 1,
        .monotonic,
    );
    _ = try fifo.write(&channels);
    const statistics = try fifo.statistics();
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        statistics.written_frames,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        statistics.dropped_frames,
    );
}

test "bounded capture FIFO rejects hostile state and aliases transactionally" {
    const Fifo = BoundedCaptureFifo(f32, 2, 4);
    try std.testing.expectError(
        error.InvalidCaptureChannelCount,
        Fifo.init(0),
    );
    try std.testing.expectError(
        error.InvalidCaptureChannelCount,
        Fifo.init(3),
    );

    var fifo = try Fifo.init(2);
    const left = [_]f32{ 1, 2 };
    const short_right = [_]f32{3};
    const mismatched = [_][]const f32{ &left, &short_right };
    try std.testing.expectError(
        error.CaptureFrameCountMismatch,
        fifo.write(&mismatched),
    );
    try std.testing.expectEqual(@as(usize, 0), try fifo.bufferedFrames());

    const one_channel = [_][]const f32{&left};
    try std.testing.expectError(
        error.CaptureChannelCountMismatch,
        fifo.write(&one_channel),
    );
    const aliased_input = [_][]const f32{
        fifo.storage[0][0..2],
        &left,
    };
    try std.testing.expectError(
        error.CaptureBufferAliasesFifo,
        fifo.write(&aliased_input),
    );

    const right = [_]f32{ 3, 4 };
    const valid_input = [_][]const f32{ &left, &right };
    _ = try fifo.write(&valid_input);
    var shared: [2]f32 = @splat(99);
    const overlapping_outputs = [_][]f32{ &shared, &shared };
    try std.testing.expectError(
        error.OverlappingCaptureOutputs,
        fifo.read(&overlapping_outputs),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 99, 99 },
        &shared,
    );
    try std.testing.expectEqual(@as(usize, 2), try fifo.bufferedFrames());

    var other: [2]f32 = @splat(77);
    const aliased_output = [_][]f32{
        fifo.storage[0][0..2],
        &other,
    };
    try std.testing.expectError(
        error.CaptureBufferAliasesFifo,
        fifo.read(&aliased_output),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 77, 77 },
        &other,
    );

    fifo.read_index.store(5, .release);
    try std.testing.expect(!fifo.valid());
    try std.testing.expectError(
        error.InvalidCaptureFifo,
        fifo.bufferedFrames(),
    );
    var preserved_left: [2]f32 = @splat(55);
    var preserved_right: [2]f32 = @splat(66);
    const preserved = [_][]f32{
        &preserved_left,
        &preserved_right,
    };
    try std.testing.expectError(
        error.InvalidCaptureFifo,
        fifo.read(&preserved),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 55, 55 },
        &preserved_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 66, 66 },
        &preserved_right,
    );

    fifo.reset();
    try std.testing.expect(fifo.valid());
    try std.testing.expectEqual(
        CaptureFifoStatistics{
            .buffered_frames = 0,
            .written_frames = 0,
            .read_frames = 0,
            .dropped_frames = 0,
            .silent_frames = 0,
        },
        try fifo.statistics(),
    );
}

test "bounded capture FIFO composes drift correction transactionally" {
    const Fifo = BoundedCaptureFifo(f64, 1, 1_024);
    var fifo = try Fifo.init(1);
    const input: [600]f64 = @splat(0.25);
    const channels = [_][]const f64{&input};
    _ = try fifo.write(&channels);

    var controller = try ClockDriftController.init(.{
        .target_buffer_frames = 512,
    });
    const Resampler = resampler.StreamingResampler(f64);
    var stream = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var stream_input: [64]f64 = @splat(0.5);
    var stream_output: [32]f64 = undefined;
    _ = try stream.process(&stream_input, &stream_output);
    const phase_before = stream.next_input_position;
    const correction = try fifo.updateDriftCorrection(
        &controller,
        &stream,
        480,
        48_000.0,
    );
    try std.testing.expect(correction > 0.0);
    try std.testing.expectEqual(
        phase_before,
        stream.next_input_position,
    );
    try std.testing.expectEqual(
        correction,
        stream.rate_correction_ppm,
    );

    var oversized_target = try ClockDriftController.init(.{
        .target_buffer_frames = Fifo.capacity_frames + 1,
    });
    const oversized_before = oversized_target;
    try std.testing.expectError(
        error.ClockDriftTargetExceedsFifoCapacity,
        fifo.updateDriftCorrection(
            &oversized_target,
            &stream,
            480,
            48_000.0,
        ),
    );
    try std.testing.expectEqual(oversized_before, oversized_target);

    const controller_before = controller;
    stream.output_rate = 0.0;
    try std.testing.expectError(
        error.InvalidState,
        fifo.updateDriftCorrection(
            &controller,
            &stream,
            480,
            48_000.0,
        ),
    );
    try std.testing.expectEqual(controller_before, controller);
}

test "bounded capture FIFO publishes complete frames between threads" {
    const Fifo = BoundedCaptureFifo(f32, 2, 31);
    const frame_total = 10_000;
    const Producer = struct {
        fn run(
            fifo: *Fifo,
            failed: *std.atomic.Value(bool),
        ) void {
            for (0..frame_total) |frame| {
                const left = [_]f32{@floatFromInt(frame)};
                const right = [_]f32{@floatFromInt(frame + frame_total)};
                const channels = [_][]const f32{ &left, &right };
                while (true) {
                    const report = fifo.write(&channels) catch {
                        failed.store(true, .release);
                        return;
                    };
                    if (report.written_frames == 1) break;
                    std.Thread.yield() catch {};
                }
            }
        }
    };

    var fifo = try Fifo.init(2);
    var failed = std.atomic.Value(bool).init(false);
    const producer = try std.Thread.spawn(
        .{},
        Producer.run,
        .{ &fifo, &failed },
    );
    var consumed: usize = 0;
    while (consumed < frame_total) {
        var left: [1]f32 = undefined;
        var right: [1]f32 = undefined;
        const outputs = [_][]f32{ &left, &right };
        const report = try fifo.read(&outputs);
        if (report.read_frames == 0) {
            std.Thread.yield() catch {};
            continue;
        }
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(consumed)),
            left[0],
        );
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(consumed + frame_total)),
            right[0],
        );
        consumed += 1;
    }
    producer.join();
    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), try fifo.bufferedFrames());
}

test "capture rate bridge matches synchronized reference resamplers" {
    const Bridge = BoundedCaptureRateBridge(
        f64,
        2,
        1_024,
        31,
        128,
    );
    var bridge = try Bridge.init(.{
        .channel_count = 2,
        .capture_sample_rate = 44_100.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 800,
        },
    });
    var left: [800]f64 = undefined;
    var right: [800]f64 = undefined;
    for (&left, &right, 0..) |*left_sample, *right_sample, frame| {
        left_sample.* = @sin(
            @as(f64, @floatFromInt(frame)) * 0.031,
        );
        right_sample.* = @cos(
            @as(f64, @floatFromInt(frame)) * 0.047,
        );
    }
    const input = [_][]const f64{ &left, &right };
    _ = try bridge.capture(&input);

    const Resampler = resampler.StreamingResampler(f64);
    var left_reference = try Resampler.init(.{
        .input_rate = 44_100.0,
        .output_rate = 48_000.0,
    });
    var right_reference = left_reference;
    const required =
        try left_reference.requiredInputSamples(128);
    var expected_left: [128]f64 = undefined;
    var expected_right: [128]f64 = undefined;
    const left_result = try left_reference.process(
        left[0..required],
        &expected_left,
    );
    const right_result = try right_reference.process(
        right[0..required],
        &expected_right,
    );
    try std.testing.expectEqual(required, left_result.consumed);
    try std.testing.expectEqual(left_result, right_result);

    var actual_left: [128]f64 = undefined;
    var actual_right: [128]f64 = undefined;
    const output = [_][]f64{ &actual_left, &actual_right };
    const report = try bridge.render(&output);
    try std.testing.expectEqual(@as(f64, 0.0), report.correction_ppm);
    try std.testing.expectEqual(required, report.capture_frames);
    try std.testing.expectEqual(@as(usize, 0), report.silent_capture_frames);
    try std.testing.expectEqual(
        @as(usize, 800),
        report.buffered_before,
    );
    try std.testing.expectEqual(
        800 - required,
        report.buffered_after,
    );
    try std.testing.expectEqualSlices(
        f64,
        &expected_left,
        &actual_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &expected_right,
        &actual_right,
    );
    try std.testing.expect(bridge.valid());
}

test "capture rate bridge fills bounded underflow with silence" {
    const Bridge = BoundedCaptureRateBridge(
        f32,
        2,
        128,
        7,
        96,
    );
    var bridge = try Bridge.init(.{
        .channel_count = 2,
        .capture_sample_rate = 96_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 64,
            .maximum_slew_ppm_per_second = 10_000.0,
        },
    });
    var left: [96]f32 = @splat(9);
    var right: [96]f32 = @splat(9);
    const outputs = [_][]f32{ &left, &right };
    const report = try bridge.render(&outputs);
    try std.testing.expectEqual(
        report.capture_frames,
        report.silent_capture_frames,
    );
    try std.testing.expect(report.capture_frames > 96);
    try std.testing.expect(report.correction_ppm < 0.0);
    try std.testing.expectEqual(
        @as(usize, 0),
        report.buffered_after,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 96),
        &left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 96),
        &right,
    );
    const statistics = try bridge.statistics();
    try std.testing.expectEqual(
        report.silent_capture_frames,
        statistics.silent_frames,
    );
}

test "capture rate bridge validates aliases capacity and state transactionally" {
    const Bridge = BoundedCaptureRateBridge(
        f64,
        2,
        32,
        8,
        16,
    );
    try std.testing.expectError(
        error.ClockDriftTargetExceedsFifoCapacity,
        Bridge.init(.{
            .channel_count = 2,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{
                .target_buffer_frames = 33,
            },
        }),
    );
    var bridge = try Bridge.init(.{
        .channel_count = 2,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 16,
        },
    });

    var too_large_left: [17]f64 = @splat(71);
    var too_large_right: [17]f64 = @splat(72);
    const too_large = [_][]f64{
        &too_large_left,
        &too_large_right,
    };
    try std.testing.expectError(
        error.CaptureRateOutputCapacityExceeded,
        bridge.render(&too_large),
    );
    try std.testing.expectEqual(
        @as(f64, 71),
        too_large_left[0],
    );

    var shared: [8]f64 = @splat(81);
    const overlapping = [_][]f64{ &shared, &shared };
    try std.testing.expectError(
        error.OverlappingCaptureOutputs,
        bridge.render(&overlapping),
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{81} ** 8),
        &shared,
    );

    var other: [8]f64 = @splat(82);
    const aliased_output = [_][]f64{
        bridge.capture_scratch[0][0..8],
        &other,
    };
    try std.testing.expectError(
        error.CaptureBufferAliasesBridge,
        bridge.render(&aliased_output),
    );
    const aliased_input = [_][]const f64{
        bridge.capture_scratch[0][0..8],
        bridge.capture_scratch[1][0..8],
    };
    try std.testing.expectError(
        error.CaptureBufferAliasesBridge,
        bridge.capture(&aliased_input),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try bridge.fifo.bufferedFrames(),
    );

    bridge.resamplers[1].input_count = 1;
    try std.testing.expect(!bridge.valid());
    var preserved_left: [8]f64 = @splat(91);
    var preserved_right: [8]f64 = @splat(92);
    const preserved = [_][]f64{
        &preserved_left,
        &preserved_right,
    };
    try std.testing.expectError(
        error.InvalidCaptureRateBridge,
        bridge.render(&preserved),
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{91} ** 8),
        &preserved_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{92} ** 8),
        &preserved_right,
    );

    try bridge.reset();
    try std.testing.expect(bridge.valid());
    bridge.fifo.read_index.store(33, .release);
    try std.testing.expect(!bridge.valid());
    try std.testing.expectError(
        error.InvalidCaptureRateBridge,
        bridge.render(&preserved),
    );
    try bridge.reset();
    try std.testing.expect(bridge.valid());
}

test "capture rate bridge remains synchronized across changing blocks" {
    const Bridge = BoundedCaptureRateBridge(
        f32,
        2,
        512,
        13,
        97,
    );
    var bridge = try Bridge.init(.{
        .channel_count = 2,
        .capture_sample_rate = 48_024.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 256,
            .maximum_correction_ppm = 1_000.0,
            .proportional_gain_ppm_per_frame = 4.0,
            .integral_gain_ppm_per_frame_second = 2.0,
            .maximum_slew_ppm_per_second = 2_000.0,
        },
    });
    var absolute_frame: usize = 0;
    var random = std.Random.DefaultPrng.init(0x4341_5054_5552_45);
    for (0..2_000) |_| {
        const capture_count =
            random.random().intRangeAtMost(usize, 40, 70);
        var left: [70]f32 = undefined;
        var right: [70]f32 = undefined;
        for (
            left[0..capture_count],
            right[0..capture_count],
            0..,
        ) |*left_sample, *right_sample, frame| {
            const value: f32 = @floatCast(@sin(
                @as(f64, @floatFromInt(
                    absolute_frame + frame,
                )) * 0.019,
            ));
            left_sample.* = value;
            right_sample.* = value;
        }
        const input = [_][]const f32{
            left[0..capture_count],
            right[0..capture_count],
        };
        _ = try bridge.capture(&input);
        absolute_frame += capture_count;

        const output_count =
            random.random().intRangeAtMost(usize, 32, 97);
        var output_left: [97]f32 = undefined;
        var output_right: [97]f32 = undefined;
        const output = [_][]f32{
            output_left[0..output_count],
            output_right[0..output_count],
        };
        const report = try bridge.render(&output);
        try std.testing.expectEqual(
            output_count,
            report.output_frames,
        );
        try std.testing.expectEqualSlices(
            f32,
            output_left[0..output_count],
            output_right[0..output_count],
        );
        try std.testing.expect(bridge.valid());
    }
}

test "capture rate bridge primes and recovers under caller policy" {
    const Bridge = BoundedCaptureRateBridge(f32, 1, 64, 8, 16);
    var bridge = try Bridge.init(.{
        .channel_count = 1,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{ .target_buffer_frames = 32 },
        .lifecycle = .{
            .startup_buffer_frames = 32,
            .recovery_buffer_frames = 24,
            .underflow_policy = .rebuffer,
            .overflow_policy = .drop_newest_and_rebuffer,
        },
    });
    const initial_position = bridge.resamplers[0].next_input_position;
    var output: [16]f32 = @splat(9);
    var report = try bridge.render(&.{&output});
    try std.testing.expectEqual(
        CaptureRateOperatingState.priming,
        report.state_after,
    );
    try std.testing.expectEqual(@as(usize, 0), report.capture_frames);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 16), &output);
    try std.testing.expectEqual(
        initial_position,
        bridge.resamplers[0].next_input_position,
    );

    const startup: [40]f32 = @splat(0.25);
    _ = try bridge.capture(&.{&startup});
    report = try bridge.render(&.{&output});
    try std.testing.expectEqual(
        CaptureRateOperatingState.running,
        report.state_after,
    );
    try std.testing.expectEqual(@as(usize, 0), report.silent_capture_frames);

    while (bridge.operating_state == .running) {
        @memset(&output, 9);
        report = try bridge.render(&.{&output});
    }
    try std.testing.expect(report.silent_capture_frames != 0);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 16), &output);
    try std.testing.expectEqual(@as(f64, 0), report.correction_ppm);
    const recovery_position = bridge.resamplers[0].next_input_position;
    report = try bridge.render(&.{&output});
    try std.testing.expectEqual(
        CaptureRateOperatingState.priming,
        report.state_after,
    );
    try std.testing.expectEqual(
        recovery_position,
        bridge.resamplers[0].next_input_position,
    );

    const refill: [24]f32 = @splat(0.5);
    _ = try bridge.capture(&.{&refill});
    report = try bridge.render(&.{&output});
    try std.testing.expectEqual(
        CaptureRateOperatingState.running,
        report.state_after,
    );

    const overflow: [64]f32 = @splat(0.75);
    const write = try bridge.capture(&.{&overflow});
    try std.testing.expect(write.dropped_frames != 0);
    @memset(&output, 9);
    report = try bridge.render(&.{&output});
    try std.testing.expectEqual(
        CaptureRateOperatingState.priming,
        report.state_after,
    );
    try std.testing.expect(report.discarded_capture_frames != 0);
    try std.testing.expectEqual(@as(usize, 0), report.buffered_after);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 16), &output);

    try bridge.reset();
    try std.testing.expectEqual(
        CaptureRateOperatingState.priming,
        bridge.operating_state,
    );
    try std.testing.expectEqual(@as(usize, 0), try bridge.fifo.bufferedFrames());
    try std.testing.expectEqual(@as(f64, 0.0), bridge.controller.correction_ppm);
}

test "capture rate bridge fixed control cadence is partition independent" {
    const Bridge = BoundedCaptureRateBridge(f64, 1, 256, 17, 64);
    const config = CaptureRateBridgeConfig{
        .channel_count = 1,
        .capture_sample_rate = 48_024.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 128,
            .maximum_correction_ppm = 1_000.0,
            .proportional_gain_ppm_per_frame = 4.0,
            .integral_gain_ppm_per_frame_second = 2.0,
            .maximum_slew_ppm_per_second = 2_000.0,
        },
        .lifecycle = .{
            .startup_buffer_frames = 128,
            .recovery_buffer_frames = 96,
            .control_interval_frames = 16,
            .underflow_policy = .rebuffer,
        },
    };
    var whole = try Bridge.init(config);
    var partitioned = try Bridge.init(config);
    var input: [224]f64 = undefined;
    for (&input, 0..) |*sample, frame| {
        sample.* = @sin(@as(f64, @floatFromInt(frame)) * 0.017);
    }
    _ = try whole.capture(&.{&input});
    _ = try partitioned.capture(&.{&input});

    var expected: [64]f64 = undefined;
    _ = try whole.render(&.{&expected});
    var actual: [64]f64 = undefined;
    const partitions = [_]usize{ 7, 13, 3, 19, 22 };
    var offset: usize = 0;
    for (partitions) |count| {
        _ = try partitioned.render(&.{actual[offset..][0..count]});
        offset += count;
    }
    try std.testing.expectEqual(@as(usize, 64), offset);
    try std.testing.expectEqualSlices(f64, &expected, &actual);
    try std.testing.expectEqual(
        whole.controller.correction_ppm,
        partitioned.controller.correction_ppm,
    );
    try std.testing.expectEqual(
        whole.resamplers[0].next_input_position,
        partitioned.resamplers[0].next_input_position,
    );
    try std.testing.expectEqual(
        try whole.statistics(),
        try partitioned.statistics(),
    );
}

test "capture rate bridge rejects malformed lifecycle state transactionally" {
    const Bridge = BoundedCaptureRateBridge(f64, 1, 32, 8, 8);
    try std.testing.expectError(
        error.CaptureRateBufferThresholdExceedsCapacity,
        Bridge.init(.{
            .channel_count = 1,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{ .target_buffer_frames = 16 },
            .lifecycle = .{ .startup_buffer_frames = 33 },
        }),
    );
    try std.testing.expectError(
        error.InvalidCaptureRateRecoveryThreshold,
        Bridge.init(.{
            .channel_count = 1,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{ .target_buffer_frames = 16 },
            .lifecycle = .{ .underflow_policy = .rebuffer },
        }),
    );
    try std.testing.expectError(
        error.InvalidCaptureRateUnderflowPolicy,
        Bridge.init(.{
            .channel_count = 1,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{ .target_buffer_frames = 16 },
            .lifecycle = .{
                .underflow_policy = @enumFromInt(255),
            },
        }),
    );
    try std.testing.expectError(
        error.InvalidCaptureRateOverflowPolicy,
        Bridge.init(.{
            .channel_count = 1,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{ .target_buffer_frames = 16 },
            .lifecycle = .{
                .overflow_policy = @enumFromInt(255),
            },
        }),
    );
    var bridge = try Bridge.init(.{
        .channel_count = 1,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{ .target_buffer_frames = 16 },
        .lifecycle = .{
            .startup_buffer_frames = 16,
            .recovery_buffer_frames = 8,
            .control_interval_frames = 4,
            .underflow_policy = .rebuffer,
        },
    });
    bridge.control_frames_remaining = 5;
    var output: [8]f64 = @splat(7);
    try std.testing.expectError(
        error.InvalidCaptureRateBridge,
        bridge.render(&.{&output}),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{7} ** 8), &output);
    try bridge.reset();
    try std.testing.expect(bridge.valid());
}

fn testSustainedCaptureClockDrift(
    comptime Sample: type,
    drift_ppm: f64,
) !void {
    const Bridge = BoundedCaptureRateBridge(Sample, 1, 2_048, 64, 48);
    var bridge = try Bridge.init(.{
        .channel_count = 1,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 1_024,
            .maximum_correction_ppm = 1_000.0,
            .proportional_gain_ppm_per_frame = 4.0,
            .integral_gain_ppm_per_frame_second = 2.0,
            .maximum_slew_ppm_per_second = 2_000.0,
        },
        .lifecycle = .{
            .startup_buffer_frames = 1_024,
            .recovery_buffer_frames = 768,
            .control_interval_frames = 48,
            .underflow_policy = .rebuffer,
            .overflow_policy = .drop_newest_and_rebuffer,
        },
    });
    const initial: [1_024]Sample = @splat(0.125);
    _ = try bridge.capture(&.{&initial});
    var capture_phase: f64 = 0.0;
    var minimum_fill: usize = 2_048;
    var maximum_fill: usize = 0;
    for (0..60_000) |block_index| {
        capture_phase += 48.0 * (1.0 + drift_ppm / 1_000_000.0);
        const capture_count: usize = @intFromFloat(@floor(capture_phase));
        capture_phase -= @floatFromInt(capture_count);
        var capture: [49]Sample = @splat(0.125);
        const write = try bridge.capture(&.{capture[0..capture_count]});
        try std.testing.expectEqual(@as(usize, 0), write.dropped_frames);
        var output: [48]Sample = undefined;
        const report = try bridge.render(&.{&output});
        try std.testing.expectEqual(@as(usize, 0), report.silent_capture_frames);
        try std.testing.expectEqual(
            CaptureRateOperatingState.running,
            report.state_after,
        );
        minimum_fill = @min(minimum_fill, report.buffered_after);
        maximum_fill = @max(maximum_fill, report.buffered_after);
        for (output) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            if (block_index > 8) {
                try std.testing.expectApproxEqAbs(
                    @as(Sample, 0.125),
                    sample,
                    @as(Sample, 2.0e-5),
                );
            }
        }
    }
    try std.testing.expect(minimum_fill > 512);
    try std.testing.expect(maximum_fill < 1_536);
    try std.testing.expectApproxEqAbs(
        drift_ppm,
        bridge.controller.correction_ppm,
        50.0,
    );
}

test "capture rate bridge controls sustained positive and negative drift" {
    try testSustainedCaptureClockDrift(f32, 500.0);
    try testSustainedCaptureClockDrift(f32, -500.0);
    try testSustainedCaptureClockDrift(f64, 500.0);
    try testSustainedCaptureClockDrift(f64, -500.0);
}

fn testJitteredCaptureClockDrift(comptime Sample: type) !void {
    const Bridge = BoundedCaptureRateBridge(Sample, 1, 2_048, 67, 97);
    var bridge = try Bridge.init(.{
        .channel_count = 1,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 1_024,
            .maximum_correction_ppm = 1_000.0,
            .proportional_gain_ppm_per_frame = 4.0,
            .integral_gain_ppm_per_frame_second = 2.0,
            .maximum_slew_ppm_per_second = 2_000.0,
        },
        .lifecycle = .{
            .startup_buffer_frames = 1_024,
            .recovery_buffer_frames = 768,
            .control_interval_frames = 32,
            .underflow_policy = .rebuffer,
            .overflow_policy = .drop_newest_and_rebuffer,
        },
    });
    const initial: [1_024]Sample = @splat(0.25);
    _ = try bridge.capture(&.{&initial});
    var random = std.Random.DefaultPrng.init(0x4452_4946_544a_4954);
    var capture_credit: f64 = 0.0;
    var pending_capture: usize = 0;
    var source_frame: usize = 0;
    var total_requested_capture: usize = 0;
    for (0..40_000) |_| {
        const render_count = random.random().intRangeAtMost(usize, 17, 97);
        capture_credit += @as(f64, @floatFromInt(render_count)) * 1.00035;
        const due: usize = @intFromFloat(@floor(capture_credit));
        capture_credit -= @floatFromInt(due);
        pending_capture += due;
        while (pending_capture != 0) {
            const capture_limit = random.random().intRangeAtMost(
                usize,
                13,
                67,
            );
            const capture_count = @min(pending_capture, capture_limit);
            pending_capture -= capture_count;
            var capture: [67]Sample = undefined;
            for (capture[0..capture_count]) |*sample| {
                sample.* = @floatCast(@sin(
                    @as(f64, @floatFromInt(source_frame)) * 0.003,
                ));
                source_frame += 1;
            }
            const write = try bridge.capture(&.{capture[0..capture_count]});
            try std.testing.expectEqual(
                @as(usize, 0),
                write.dropped_frames,
            );
            total_requested_capture += capture_count;
        }

        var output: [97]Sample = undefined;
        const report = try bridge.render(&.{output[0..render_count]});
        try std.testing.expectEqual(@as(usize, 0), report.silent_capture_frames);
        try std.testing.expectEqual(
            CaptureRateOperatingState.running,
            report.state_after,
        );
        for (output[0..render_count]) |sample|
            try std.testing.expect(std.math.isFinite(sample));
    }
    const statistics = try bridge.statistics();
    try std.testing.expectEqual(
        initial.len + total_requested_capture,
        statistics.written_frames,
    );
    try std.testing.expectEqual(
        statistics.written_frames,
        statistics.read_frames + statistics.buffered_frames,
    );
    try std.testing.expectEqual(@as(usize, 0), statistics.dropped_frames);
    try std.testing.expectEqual(@as(usize, 0), statistics.silent_frames);
    try std.testing.expect(statistics.buffered_frames > 512);
    try std.testing.expect(statistics.buffered_frames < 1_536);
    try std.testing.expectApproxEqAbs(
        @as(f64, 350.0),
        bridge.controller.correction_ppm,
        75.0,
    );
    try bridge.reset();
    try std.testing.expectEqual(
        CaptureFifoStatistics{
            .buffered_frames = 0,
            .written_frames = 0,
            .read_frames = 0,
            .dropped_frames = 0,
            .silent_frames = 0,
        },
        try bridge.statistics(),
    );
}

test "capture rate bridge tolerates jitter and changing callback sizes" {
    try testJitteredCaptureClockDrift(f32);
    try testJitteredCaptureClockDrift(f64);
}

test "capture-rate callback adapter reconstructs processor buses" {
    const Probe = struct {
        main_input_count: usize = 0,
        auxiliary_input_count: usize = 0,
        auxiliary_bus_count: usize = 0,
        tempo: ?f64 = null,

        fn process(
            context: *anyopaque,
            block: CallbackBlock(f64),
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context));
            self.main_input_count = block.input_channels.len;
            self.auxiliary_input_count =
                block.auxiliary_input_channels.len;
            self.auxiliary_bus_count =
                block.auxiliary_input_bus_channel_counts.len;
            self.tempo = if (block.transport) |transport|
                transport.tempo_bpm
            else
                null;
            if (block.output_channels.len == 1 and
                block.input_channels.len == 1)
                @memcpy(
                    block.output_channels[0],
                    block.input_channels[0],
                );
            if (block.auxiliary_output_channels.len == 1 and
                block.auxiliary_input_channels.len == 1)
                @memcpy(
                    block.auxiliary_output_channels[0],
                    block.auxiliary_input_channels[0],
                );
        }
    };
    const Adapter = BoundedCaptureRateCallbackAdapter(
        f64,
        2,
        64,
        5,
        16,
        2,
    );
    var probe = Probe{};
    var adapter = try Adapter.init(
        .{
            .main_input_channel_count = 1,
            .auxiliary_input_bus_channel_counts = &.{1},
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{
                .target_buffer_frames = 32,
            },
        },
        .{
            .context = &probe,
            .process_block = Probe.process,
        },
    );
    const main_input: [40]f64 = @splat(0.25);
    const auxiliary_input: [40]f64 = @splat(0.5);
    const capture = [_][]const f64{
        &main_input,
        &auxiliary_input,
    };
    _ = try adapter.capture(&capture);

    var main_output: [16]f64 = undefined;
    var auxiliary_output: [16]f64 = undefined;
    const report = try adapter.render(.{
        .frame_count = 16,
        .output_channels = &.{&main_output},
        .auxiliary_output_channels = &.{&auxiliary_output},
        .auxiliary_output_bus_channel_counts = &.{1},
        .transport = .{
            .project_time_samples = 0,
            .tempo_bpm = 123.0,
        },
    });
    try std.testing.expectEqual(@as(usize, 16), report.output_frames);
    try std.testing.expectEqual(@as(usize, 1), probe.main_input_count);
    try std.testing.expectEqual(
        @as(usize, 1),
        probe.auxiliary_input_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        probe.auxiliary_bus_count,
    );
    try std.testing.expectEqual(@as(?f64, 123.0), probe.tempo);
    for (main_output, auxiliary_output) |main, auxiliary| {
        try std.testing.expectApproxEqAbs(
            main * 2.0,
            auxiliary,
            1.0e-12,
        );
    }
    try std.testing.expect(adapter.valid());
}

test "capture-rate callback adapter wrappers count and silence failures" {
    const Probe = struct {
        fn process(
            _: *anyopaque,
            block: CallbackBlock(f32),
        ) void {
            for (block.output_channels) |output|
                @memset(output, 0.75);
        }
    };
    const Adapter = BoundedCaptureRateCallbackAdapter(
        f32,
        2,
        32,
        4,
        8,
        1,
    );
    var probe: u8 = 0;
    var adapter = try Adapter.init(
        .{
            .main_input_channel_count = 2,
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{
                .target_buffer_frames = 16,
            },
        },
        .{
            .context = &probe,
            .process_block = Probe.process,
        },
    );
    const callback = adapter.splitCallback();
    const one_channel: [4]f32 = @splat(1);
    callback.capture_block(
        callback.context,
        &.{&one_channel},
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try adapter.statistics()).capture_failures,
    );

    var oversized: [9]f32 = @splat(8);
    callback.render_block(callback.context, .{
        .frame_count = 9,
        .output_channels = &.{&oversized},
    });
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 9),
        &oversized,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try adapter.statistics()).render_failures,
    );

    const left: [20]f32 = @splat(0.25);
    const right: [20]f32 = @splat(0.5);
    callback.capture_block(
        callback.context,
        &.{ &left, &right },
    );
    var output: [8]f32 = @splat(0);
    callback.render_block(callback.context, .{
        .frame_count = 8,
        .output_channels = &.{&output},
    });
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0.75} ** 8),
        &output,
    );

    var alias_other: [8]f32 = undefined;
    try std.testing.expectError(
        error.CaptureBufferAliasesAdapter,
        adapter.render(.{
            .frame_count = 8,
            .output_channels = &.{
                adapter.corrected_input[0][0..8],
                &alias_other,
            },
        }),
    );

    adapter.bridge.resamplers[1].input_count +%= 1;
    @memset(&output, 9);
    callback.render_block(callback.context, .{
        .frame_count = 8,
        .output_channels = &.{&output},
    });
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 8),
        &output,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        (try adapter.statistics()).render_failures,
    );

    try adapter.reset();
    try std.testing.expect(adapter.valid());
    const statistics = try adapter.statistics();
    try std.testing.expectEqual(@as(usize, 0), statistics.capture_failures);
    try std.testing.expectEqual(@as(usize, 0), statistics.render_failures);

    adapter.bridge.channel_count = 3;
    callback.capture_block(
        callback.context,
        &.{ &left, &right },
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try adapter.statistics()).capture_failures,
    );
    adapter.bridge.channel_count = 2;
    try adapter.reset();
    try std.testing.expect(adapter.valid());
}

test "capture-rate callback adapter bypasses processing while priming" {
    const Probe = struct {
        calls: usize = 0,

        fn process(
            context: *anyopaque,
            block: CallbackBlock(f32),
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            for (block.output_channels) |output| @memset(output, 1.0);
        }
    };
    const Adapter = BoundedCaptureRateCallbackAdapter(
        f32,
        1,
        64,
        8,
        16,
        0,
    );
    var probe = Probe{};
    var adapter = try Adapter.init(.{
        .main_input_channel_count = 1,
        .capture_sample_rate = 48_000.0,
        .render_sample_rate = 48_000.0,
        .drift = .{ .target_buffer_frames = 32 },
        .lifecycle = .{
            .startup_buffer_frames = 32,
            .recovery_buffer_frames = 24,
            .control_interval_frames = 8,
            .underflow_policy = .rebuffer,
        },
    }, .{
        .context = &probe,
        .process_block = Probe.process,
    });
    var output: [16]f32 = @splat(9);
    var report = try adapter.render(.{
        .frame_count = output.len,
        .output_channels = &.{&output},
    });
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 16), &output);
    try std.testing.expectEqual(
        CaptureRateOperatingState.priming,
        report.state_after,
    );

    const input: [40]f32 = @splat(0.25);
    _ = try adapter.capture(&.{&input});
    report = try adapter.render(.{
        .frame_count = output.len,
        .output_channels = &.{&output},
    });
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(
        CaptureRateOperatingState.running,
        report.state_after,
    );
    try std.testing.expectEqualSlices(f32, &([_]f32{1} ** 16), &output);
}

test "clock drift controller slews continuous resampler correction transactionally" {
    try std.testing.expectError(
        error.InvalidClockDriftTarget,
        ClockDriftController.init(.{
            .target_buffer_frames = 0,
        }),
    );
    try std.testing.expectError(
        error.InvalidClockDriftCorrection,
        ClockDriftController.init(.{
            .target_buffer_frames = 512,
            .maximum_correction_ppm = resampler.maximum_rate_correction_ppm + 1.0,
        }),
    );

    var controller = try ClockDriftController.init(.{
        .target_buffer_frames = 512,
        .maximum_correction_ppm = 1_000.0,
        .proportional_gain_ppm_per_frame = 4.0,
        .integral_gain_ppm_per_frame_second = 1.0,
        .maximum_slew_ppm_per_second = 1_000.0,
    });
    try std.testing.expectEqual(
        @as(f64, 0.0),
        try controller.update(512, 480, 48_000.0),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 10.0),
        try controller.update(612, 480, 48_000.0),
        1.0e-12,
    );
    try std.testing.expectError(
        error.InvalidSampleRate,
        controller.update(512, 480, 0.0),
    );

    const Resampler = resampler.StreamingResampler(f64);
    var stream = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var input: [128]f64 = @splat(0.25);
    var output: [64]f64 = undefined;
    _ = try stream.process(&input, &output);
    const phase_before = stream.next_input_position;
    _ = try controller.updateResampler(
        &stream,
        612,
        480,
        48_000.0,
    );
    try std.testing.expectEqual(
        phase_before,
        stream.next_input_position,
    );
    try std.testing.expectEqual(
        controller.correction_ppm,
        stream.rate_correction_ppm,
    );

    const controller_before = controller;
    stream.output_rate = 0.0;
    try std.testing.expectError(
        error.InvalidState,
        controller.updateResampler(
            &stream,
            612,
            480,
            48_000.0,
        ),
    );
    try std.testing.expectEqual(
        controller_before,
        controller,
    );

    controller.reset();
    try std.testing.expect(controller.valid());
    try std.testing.expectEqual(
        @as(f64, 0.0),
        controller.correction_ppm,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -10.0),
        try controller.update(412, 480, 48_000.0),
        1.0e-12,
    );
    controller.correction_ppm =
        controller.config.maximum_correction_ppm + 1.0;
    try std.testing.expect(!controller.valid());
    try std.testing.expectError(
        error.InvalidClockDriftController,
        controller.update(512, 480, 48_000.0),
    );
}

test "clock drift controller converges on sustained capture mismatch" {
    const frame_count: usize = 480;
    const sample_rate = 48_000.0;
    const source_drift_ppm = 500.0;
    var controller = try ClockDriftController.init(.{
        .target_buffer_frames = 1_024,
        .maximum_correction_ppm = 1_000.0,
        .proportional_gain_ppm_per_frame = 10.0,
        .integral_gain_ppm_per_frame_second = 5.0,
        .maximum_slew_ppm_per_second = 2_000.0,
    });
    var buffered_frames: f64 = 1_024.0;
    for (0..10_000) |_| {
        buffered_frames +=
            @as(f64, @floatFromInt(frame_count)) *
            (1.0 + source_drift_ppm / 1_000_000.0);
        buffered_frames -=
            @as(f64, @floatFromInt(frame_count)) *
            (1.0 + controller.correction_ppm / 1_000_000.0);
        _ = try controller.update(
            @intFromFloat(@round(buffered_frames)),
            frame_count,
            sample_rate,
        );
    }
    try std.testing.expectApproxEqAbs(
        source_drift_ppm,
        controller.correction_ppm,
        25.0,
    );
    try std.testing.expect(
        @abs(buffered_frames - 1_024.0) < 16.0,
    );
}

test "standalone runtime carries audio MIDI transport and output events" {
    const Probe = struct {
        observed_tempo: ?f64 = null,
        observed_note: ?i16 = null,

        pub const name = "Standalone Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout =
            .stereo;
        pub const audio_output_layout: audio_layout.AudioBusLayout =
            .stereo;
        pub const event_input = true;
        pub const event_output = true;
        pub const Params = struct {
            gain: parameters.FloatParam =
                parameters.FloatParam.init(
                    0,
                    "Gain",
                    0.0,
                    1.0,
                    0.5,
                ),
        };

        pub fn processWithParameterView(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed_tempo = context.hostTempoBpm();
            const gain: f32 = @floatCast(view.load("gain"));
            for (0..context.outputChannelCount()) |index| {
                const input = context.inputChannel(index) orelse
                    continue;
                const output = context.outputChannel(index) orelse
                    continue;
                for (input, output) |sample, *destination|
                    destination.* = sample * gain;
            }
            for (context.inputEvents().items) |event| {
                if (event.asNoteOn()) |note|
                    self.observed_note = note.pitch;
                context.appendOutputEvent(event) catch {};
            }
        }
    };

    const Runtime = StandaloneRuntime(Probe, f32);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 16,
        .input_channel_count = 2,
        .output_channel_count = 2,
    });

    var midi = Midi1EventBuffer(4){};
    try midi.append(.{
        .sample_offset = 1,
        .message = try process_api.Midi1Message.noteOn(
            2,
            64,
            100,
        ),
    }, 4);
    const input_events = try midi.events(4);
    const changes = [_]process_api.ParameterChange{.{
        .id = 0,
        .sample_offset = 0,
        .normalized = 0.25,
    }};
    const input_left = [_]f32{ 1.0, 0.5, -1.0, -0.5 };
    const input_right = [_]f32{ 0.25, 0.5, 0.75, 1.0 };
    var output_left: [4]f32 = undefined;
    var output_right: [4]f32 = undefined;
    const inputs = [_][]const f32{ &input_left, &input_right };
    const outputs = [_][]f32{ &output_left, &output_right };
    var output_storage: [4]process_api.Event = undefined;
    var output_writer =
        process_api.EventWriter.init(&output_storage, 4);
    const scope = realtime_audit.Scope.enter();
    try runtime.processCallback(.{
        .input_channels = &inputs,
        .output_channels = &outputs,
        .parameter_changes = &changes,
        .events = input_events.items,
        .output_events = &output_writer,
        .transport = .{
            .project_time_samples = 256,
            .state_valid = true,
            .playing = true,
            .tempo_bpm = 137.0,
        },
    });
    const report = scope.leave();

    try std.testing.expect(report.clean());
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, 0.125, -0.25, -0.125 },
        &output_left,
    );
    try std.testing.expectEqual(@as(?f64, 137.0), runtime.runtime.instance.plugin.observed_tempo);
    try std.testing.expectEqual(@as(?i16, 64), runtime.runtime.instance.plugin.observed_note);
    try std.testing.expectEqual(
        @as(usize, 1),
        output_writer.eventCount(),
    );
    try std.testing.expectEqual(@as(u64, 4), runtime.processedFrameCount());
    try runtime.stop();
}

test "standalone runtime and router carry selected auxiliary bus capacity" {
    const Probe = struct {
        pub const name = "Standalone Large Bus Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 12;
        pub const audio_input_layout: audio_layout.AudioBusLayout = .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout = .none;
        pub const auxiliary_layouts =
            [_]audio_layout.AudioBusLayout{.mono} ** 12;
        pub const audio_auxiliary_input_layouts: []const audio_layout.AudioBusLayout =
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
    const Runtime = StandaloneRuntime(Probe, f32);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const channel_counts =
        [_]usize{1} ** Probe.maximum_auxiliary_audio_buses;
    try runtime.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 1,
        .input_channel_count = 1,
        .auxiliary_input_bus_channel_counts = &channel_counts,
        .output_channel_count = 0,
    });
    const main_input = [_]f32{1.0};
    const auxiliary_samples =
        [_][1]f32{.{2.0}} **
        Probe.maximum_auxiliary_audio_buses;
    var auxiliary_inputs: [Probe.maximum_auxiliary_audio_buses][]const f32 =
        undefined;
    for (&auxiliary_samples, &auxiliary_inputs) |*samples, *view|
        view.* = samples;
    try runtime.processCallback(.{
        .input_channels = &.{&main_input},
        .auxiliary_input_channels = &auxiliary_inputs,
        .auxiliary_input_bus_channel_counts = &channel_counts,
    });
    try std.testing.expectEqual(
        @as(usize, 12),
        runtime.runtime.instance.plugin
            .auxiliary_input_count,
    );
    try runtime.stop();

    const Router =
        BoundedDeviceChannelRouter(f32, 1, 12);
    const routes =
        [_]?usize{
            0, 1, 2, 3,  4,  5,  6,
            7, 8, 9, 10, 11, 12,
        };
    const configuration = DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 1,
        .input_channel_count = 1,
        .auxiliary_input_bus_channel_counts = &channel_counts,
        .output_channel_count = 0,
    };
    const routing = DeviceChannelRouting{
        .device_input_channel_count = routes.len,
        .device_output_channel_count = 0,
        .input_routes = &routes,
        .output_routes = &.{},
    };
    const router = try Router.init(configuration, routing);
    try std.testing.expect(router.valid());
}

test "standalone callback failure clears every output bus" {
    const Probe = struct {
        pub const name = "Standalone Failure Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const audio_auxiliary_output_layout: audio_layout.AudioBusLayout = .stereo;
        pub const Params = struct {};

        pub fn process64(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
        ) void {}
    };

    const Runtime = StandaloneRuntime(Probe, f64);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
        .auxiliary_output_bus_channel_counts = &.{2},
    });

    const input = [_]f64{ 1.0, -1.0, 0.5 };
    var output = [_]f64{ 1.0, 1.0, 1.0 };
    var auxiliary_left = [_]f64{ 1.0, 1.0, 1.0 };
    var auxiliary_right = [_]f64{ 1.0, 1.0, 1.0 };
    const inputs = [_][]const f64{&input};
    const outputs = [_][]f64{&output};
    const auxiliary_outputs =
        [_][]f64{ &auxiliary_left, &auxiliary_right };
    try std.testing.expectError(error.BlockTooLarge, runtime.processCallback(.{
        .input_channels = &inputs,
        .output_channels = &outputs,
        .auxiliary_output_channels = &auxiliary_outputs,
        .auxiliary_output_bus_channel_counts = &.{2},
    }));
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0, 0.0 },
        &output,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0, 0.0 },
        &auxiliary_left,
    );
    try runtime.stop();
}

test "device router maps main and auxiliary buses without allocation" {
    const Probe = struct {
        pub const name = "Standalone Routing Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout =
            .stereo;
        pub const audio_sidechain_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout =
            .stereo;
        pub const audio_auxiliary_output_layouts: []const audio_layout.AudioBusLayout = &.{.mono};
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const left = context.inputChannel(0) orelse return;
            const right = context.inputChannel(1) orelse return;
            const sidechain_bus =
                context.auxiliaryInputBus(0) orelse return;
            const sidechain = sidechain_bus.channel(0) orelse return;
            const output_left = context.outputChannel(0) orelse return;
            const output_right = context.outputChannel(1) orelse return;
            const auxiliary_bus =
                context.auxiliaryOutputBus(0) orelse return;
            const auxiliary = auxiliary_bus.channel(0) orelse return;
            for (
                left,
                right,
                sidechain,
                output_left,
                output_right,
                auxiliary,
            ) |
                left_sample,
                right_sample,
                sidechain_sample,
                *left_destination,
                *right_destination,
                *auxiliary_destination,
            | {
                left_destination.* = left_sample + sidechain_sample;
                right_destination.* =
                    right_sample - sidechain_sample;
                auxiliary_destination.* =
                    left_sample + right_sample;
            }
        }
    };

    const configuration = DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 4,
        .input_channel_count = 2,
        .auxiliary_input_bus_channel_counts = &.{1},
        .output_channel_count = 2,
        .auxiliary_output_bus_channel_counts = &.{1},
    };
    const Runtime = StandaloneRuntime(Probe, f32);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(configuration);
    defer runtime.stop() catch {};

    const Router = DeviceChannelRouter(f32, 4);
    var router = try Router.init(configuration, .{
        .device_input_channel_count = 3,
        .device_output_channel_count = 4,
        .input_routes = &.{ 2, 0, 1 },
        .output_routes = &.{ 3, 1, 0 },
    });
    try std.testing.expect(router.valid());

    const device_right = [_]f32{ 10.0, 20.0 };
    const device_sidechain = [_]f32{ 1.0, 2.0 };
    const device_left = [_]f32{ 3.0, 4.0 };
    const device_inputs = [_][]const f32{
        &device_right,
        &device_sidechain,
        &device_left,
    };
    var device_auxiliary = [_]f32{ 99.0, 99.0 };
    var device_main_right = [_]f32{ 99.0, 99.0 };
    var device_unmapped = [_]f32{ 99.0, 99.0 };
    var device_main_left = [_]f32{ 99.0, 99.0 };
    const device_outputs = [_][]f32{
        &device_auxiliary,
        &device_main_right,
        &device_unmapped,
        &device_main_left,
    };
    const scope = realtime_audit.Scope.enter();
    try router.processCallback(&runtime, .{
        .frame_count = 2,
        .input_channels = &device_inputs,
        .output_channels = &device_outputs,
    });
    const report = scope.leave();

    try std.testing.expect(report.clean());
    try std.testing.expectEqualSlices(
        f32,
        &.{ 4.0, 6.0 },
        &device_main_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 9.0, 18.0 },
        &device_main_right,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 13.0, 24.0 },
        &device_auxiliary,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0 },
        &device_unmapped,
    );
}

test "device router supports silent input routes and validates mappings" {
    const Probe = struct {
        pub const name = "Standalone Silent Route Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const Params = struct {};

        pub fn process64(
            _: *@This(),
            context: *process_api.ProcessContext(f64),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };

    const configuration = DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 8,
        .input_channel_count = 1,
        .output_channel_count = 1,
    };
    const valid_routing = DeviceChannelRouting{
        .device_input_channel_count = 0,
        .device_output_channel_count = 2,
        .input_routes = &.{null},
        .output_routes = &.{1},
    };
    try valid_routing.validate(configuration);
    const Router = DeviceChannelRouter(f64, 8);
    var router = try Router.init(configuration, valid_routing);
    try std.testing.expect(router.valid());
    const Runtime = StandaloneRuntime(Probe, f64);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(configuration);
    defer runtime.stop() catch {};
    var unmapped = [_]f64{ 3.0, 3.0 };
    var mapped = [_]f64{ 3.0, 3.0 };
    const outputs = [_][]f64{ &unmapped, &mapped };
    try router.processCallback(&runtime, .{
        .frame_count = 2,
        .output_channels = &outputs,
    });
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0 },
        &unmapped,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0 },
        &mapped,
    );

    try std.testing.expectError(
        error.RoutingBlockCapacityExceeded,
        DeviceChannelRouter(f64, 4).init(
            configuration,
            valid_routing,
        ),
    );
    try std.testing.expectError(
        error.InputRouteCountMismatch,
        (DeviceChannelRouting{
            .device_input_channel_count = 1,
            .device_output_channel_count = 2,
            .input_routes = &.{},
            .output_routes = &.{1},
        }).validate(configuration),
    );
    try std.testing.expectError(
        error.DeviceInputChannelOutOfRange,
        (DeviceChannelRouting{
            .device_input_channel_count = 1,
            .device_output_channel_count = 2,
            .input_routes = &.{1},
            .output_routes = &.{0},
        }).validate(configuration),
    );
    try std.testing.expectError(
        error.DuplicateDeviceOutputRoute,
        (DeviceChannelRouting{
            .device_input_channel_count = 2,
            .device_output_channel_count = 1,
            .input_routes = &.{0},
            .output_routes = &.{ 0, 0 },
        }).validate(.{
            .sample_rate = 48_000.0,
            .max_block_size = 8,
            .input_channel_count = 1,
            .output_channel_count = 2,
        }),
    );
}

test "device router clears physical outputs on validation and runtime failure" {
    const Probe = struct {
        pub const name = "Standalone Routing Failure Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout =
            .mono;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const output = context.outputChannel(0) orelse return;
            @memset(output, 1.0);
        }
    };

    const configuration = DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
    };
    const Runtime = StandaloneRuntime(Probe, f32);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(configuration);
    defer runtime.stop() catch {};

    const Router = DeviceChannelRouter(f32, 4);
    var router = try Router.init(configuration, .{
        .device_input_channel_count = 1,
        .device_output_channel_count = 2,
        .input_routes = &.{0},
        .output_routes = &.{1},
    });
    const input = [_]f32{ 0.0, 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    var unmapped = [_]f32{ 9.0, 9.0, 9.0 };
    var mapped = [_]f32{ 9.0, 9.0, 9.0 };
    const outputs = [_][]f32{ &unmapped, &mapped };
    try std.testing.expectError(
        error.BlockTooLarge,
        router.processCallback(&runtime, .{
            .frame_count = 3,
            .input_channels = &inputs,
            .output_channels = &outputs,
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0, 0.0 },
        &unmapped,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0, 0.0 },
        &mapped,
    );

    unmapped = @splat(7.0);
    mapped = @splat(7.0);
    const short_output = [_][]f32{unmapped[0..2]};
    try std.testing.expectError(
        error.DeviceOutputChannelCountMismatch,
        router.processCallback(&runtime, .{
            .frame_count = 2,
            .input_channels = &inputs,
            .output_channels = &short_output,
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0 },
        short_output[0],
    );

    router.output_routes[0] = 2;
    mapped = @splat(5.0);
    try std.testing.expectError(
        error.InvalidDeviceChannelRouter,
        router.processCallback(&runtime, .{
            .frame_count = 3,
            .input_channels = &inputs,
            .output_channels = &outputs,
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0, 0.0 },
        &mapped,
    );
}

test "MIDI device interfaces preserve timestamps and rejection" {
    const Probe = struct {
        received: ?TimestampedMidi1Packet = null,
        sent: ?TimestampedMidi1Packet = null,
        started: bool = false,
        stopped: bool = false,

        fn receive(
            context: *anyopaque,
            packet: TimestampedMidi1Packet,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.received = packet;
        }

        fn startInput(
            context: *anyopaque,
            callback: Midi1InputCallback,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.started = true;
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = 90,
                .message = try process_api.Midi1Message.noteOn(
                    0,
                    60,
                    127,
                ),
            });
        }

        fn stopInput(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.stopped = true;
        }

        fn sendOutput(
            context: *anyopaque,
            packet: TimestampedMidi1Packet,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.sent = packet;
        }
    };

    var probe = Probe{};
    var input = Midi1InputDevice{
        .context = &probe,
        .start_input = Probe.startInput,
        .stop_input = Probe.stopInput,
    };
    try input.start(.{
        .context = &probe,
        .receive = Probe.receive,
    });
    input.stop();
    try std.testing.expect(probe.started);
    try std.testing.expect(probe.stopped);
    try std.testing.expectEqual(@as(u64, 90), probe.received.?.timestamp_nanoseconds);

    var output = Midi1OutputDevice{
        .context = &probe,
        .send_output = Probe.sendOutput,
    };
    try output.send(.{
        .timestamp_nanoseconds = 120,
        .message = try process_api.Midi1Message.noteOff(
            0,
            60,
            0,
        ),
    });
    try std.testing.expectEqual(@as(u64, 120), probe.sent.?.timestamp_nanoseconds);
}

test "MIDI block scheduler preserves late current and future packets" {
    var scheduler = Midi1BlockScheduler(4){};
    try scheduler.receive(.{
        .timestamp_nanoseconds = 999_000_000,
        .message = try process_api.Midi1Message.noteOn(
            0,
            60,
            100,
        ),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 1_001_500_000,
        .message = try process_api.Midi1Message.noteOn(
            0,
            61,
            100,
        ),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 1_004_000_000,
        .message = try process_api.Midi1Message.noteOn(
            0,
            62,
            100,
        ),
    });

    var events = Midi1EventBuffer(4){};
    const first = try scheduler.fillBlock(
        4,
        &events,
        1_000_000_000,
        1_000.0,
        4,
        2,
    );
    try std.testing.expectEqual(@as(usize, 2), first.scheduled);
    try std.testing.expectEqual(@as(usize, 1), first.late);
    try std.testing.expect(!first.capacity_exhausted);
    try std.testing.expect(first.future_pending);
    try std.testing.expectEqual(@as(usize, 2), events.count);
    try std.testing.expectEqual(@as(usize, 0), events.storage[0].sample_offset);
    try std.testing.expectEqual(@as(usize, 1), events.storage[1].sample_offset);
    try std.testing.expectEqual(@as(i32, 2), events.storage[1].bus_index);

    events.reset();
    for (events.storage) |event|
        try std.testing.expectEqualDeep(process_api.Event.other(0), event);
    const second = try scheduler.fillBlock(
        4,
        &events,
        1_004_000_000,
        1_000.0,
        4,
        2,
    );
    try std.testing.expectEqual(@as(usize, 1), second.scheduled);
    try std.testing.expectEqual(@as(usize, 0), second.late);
    try std.testing.expect(!second.future_pending);
    try std.testing.expectEqual(@as(usize, 0), events.storage[0].sample_offset);
    try std.testing.expectEqual(@as(usize, 0), try scheduler.queue.pendingCount());
}

test "MIDI block scheduler retains packets when event capacity is exhausted" {
    var scheduler = Midi1BlockScheduler(2){};
    try scheduler.receive(.{
        .timestamp_nanoseconds = 10,
        .message = try process_api.Midi1Message.noteOn(
            0,
            60,
            100,
        ),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 11,
        .message = try process_api.Midi1Message.noteOff(
            0,
            60,
            0,
        ),
    });
    try std.testing.expectError(
        error.MidiInputQueueFull,
        scheduler.receive(.{
            .timestamp_nanoseconds = 12,
            .message = try process_api.Midi1Message.noteOn(
                0,
                61,
                100,
            ),
        }),
    );
    const callback = scheduler.inputCallback();
    callback.receive(callback.context, .{
        .timestamp_nanoseconds = 12,
        .message = try process_api.Midi1Message.noteOn(
            0,
            61,
            100,
        ),
    });
    try std.testing.expectEqual(
        @as(usize, 1),
        scheduler.rejectedPacketCount(),
    );

    var events = Midi1EventBuffer(1){};
    const first = try scheduler.fillBlock(
        1,
        &events,
        10,
        48_000.0,
        64,
        0,
    );
    try std.testing.expectEqual(@as(usize, 1), first.scheduled);
    try std.testing.expect(first.capacity_exhausted);
    try std.testing.expect(first.future_pending);
    try std.testing.expectEqual(@as(usize, 1), try scheduler.queue.pendingCount());

    events.reset();
    const second = try scheduler.fillBlock(
        1,
        &events,
        10,
        48_000.0,
        64,
        0,
    );
    try std.testing.expectEqual(@as(usize, 1), second.scheduled);
    try std.testing.expect(!second.capacity_exhausted);
    try std.testing.expect(!second.future_pending);
    try std.testing.expectError(
        error.OutOfOrderMidiTimestamp,
        scheduler.receive(.{
            .timestamp_nanoseconds = 9,
            .message = try process_api.Midi1Message.noteOn(
                0,
                61,
                100,
            ),
        }),
    );
    scheduler.reset();
    try std.testing.expectEqual(
        @as(usize, 0),
        scheduler.rejectedPacketCount(),
    );
    try scheduler.receive(.{
        .timestamp_nanoseconds = 9,
        .message = try process_api.Midi1Message.noteOn(
            0,
            61,
            100,
        ),
    });
}

test "MIDI input queue is stable under concurrent SPSC traffic" {
    const packet_count = 20_000;
    const Queue = Midi1InputQueue(32);
    const Producer = struct {
        queue: *Queue,
        failed: *std.atomic.Value(bool),

        fn run(self: @This()) void {
            for (0..packet_count) |index| {
                const message = process_api.Midi1Message.noteOn(
                    0,
                    @intCast(index % 128),
                    100,
                ) catch {
                    self.failed.store(true, .release);
                    return;
                };
                while (true) {
                    self.queue.push(.{
                        .timestamp_nanoseconds = index,
                        .message = message,
                    }) catch |err| switch (err) {
                        error.MidiInputQueueFull => {
                            std.Thread.yield() catch {};
                            continue;
                        },
                        else => {
                            self.failed.store(true, .release);
                            return;
                        },
                    };
                    break;
                }
            }
        }
    };

    var queue = Queue{};
    var failed = std.atomic.Value(bool).init(false);
    const producer = try std.Thread.spawn(
        .{},
        Producer.run,
        .{Producer{ .queue = &queue, .failed = &failed }},
    );
    var expected_timestamp: usize = 0;
    while (expected_timestamp < packet_count) {
        const packet = try queue.pop() orelse {
            std.Thread.yield() catch {};
            continue;
        };
        if (packet.timestamp_nanoseconds != expected_timestamp) {
            failed.store(true, .release);
        }
        expected_timestamp += 1;
    }
    producer.join();
    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expectEqual(
        @as(usize, packet_count),
        expected_timestamp,
    );
    try std.testing.expectEqual(@as(usize, 0), try queue.pendingCount());
    try std.testing.expect(queue.valid());
    queue.read_index.store(queue.storage.len, .release);
    try std.testing.expect(!queue.valid());
    try std.testing.expectError(
        error.InvalidMidiInputQueue,
        queue.pop(),
    );
    queue.reset();
    for (queue.storage) |packet|
        try std.testing.expectEqualDeep(TimestampedMidi1Packet{}, packet);
}

test "UMP device interfaces preserve complete packets and timestamps" {
    const Probe = struct {
        received: ?TimestampedUmpPacket = null,
        sent: ?TimestampedUmpPacket = null,
        started: bool = false,
        stopped: bool = false,

        fn receive(
            context: *anyopaque,
            packet: TimestampedUmpPacket,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.received = packet;
        }

        fn startInput(
            context: *anyopaque,
            callback: UmpInputCallback,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.started = true;
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = 90,
                .packet = try process_api.UmpPacket.init(
                    &.{ 0x4090_3C00, 0x7FFF_FFFF },
                ),
            });
        }

        fn stopInput(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.stopped = true;
        }

        fn sendOutput(
            context: *anyopaque,
            packet: TimestampedUmpPacket,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.sent = packet;
        }
    };

    var probe = Probe{};
    var input = UmpInputDevice{
        .context = &probe,
        .start_input = Probe.startInput,
        .stop_input = Probe.stopInput,
    };
    try input.start(.{
        .context = &probe,
        .receive = Probe.receive,
    });
    input.stop();
    try std.testing.expect(probe.started);
    try std.testing.expect(probe.stopped);
    try std.testing.expectEqual(
        @as(u64, 90),
        probe.received.?.timestamp_nanoseconds,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x4090_3C00, 0x7FFF_FFFF },
        probe.received.?.packet.words(),
    );

    var output = UmpOutputDevice{
        .context = &probe,
        .send_output = Probe.sendOutput,
    };
    try output.send(.{
        .timestamp_nanoseconds = 120,
        .packet = try process_api.UmpPacket.init(
            &.{ 0x5000_0000, 1, 2, 3 },
        ),
    });
    try std.testing.expectEqual(
        @as(u64, 120),
        probe.sent.?.timestamp_nanoseconds,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x5000_0000, 1, 2, 3 },
        probe.sent.?.packet.words(),
    );
    try std.testing.expectError(error.InvalidUmpPacket, output.send(.{
        .timestamp_nanoseconds = 121,
        .packet = .{
            .storage = .{ 0x4000_0000, 0, 0, 0 },
            .word_count = 1,
        },
    }));
}

test "UMP output device schedules block-relative packets" {
    const Probe = struct {
        timestamps: [2]u64 = undefined,
        count: usize = 0,

        fn sendOutput(
            context: *anyopaque,
            packet: TimestampedUmpPacket,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (packet.packet.storage[0] == 0x2090_3D7F)
                return error.OutputRejected;
            if (self.count == self.timestamps.len)
                return error.OutputCapacityExceeded;
            self.timestamps[self.count] =
                packet.timestamp_nanoseconds;
            self.count += 1;
        }
    };

    const valid = try process_api.UmpPacket.init(&.{0x2090_3C7F});
    const rejected = try process_api.UmpPacket.init(&.{0x2090_3D7F});
    const malformed = process_api.UmpPacket{
        .storage = .{ 0x4000_0000, 0, 0, 0 },
        .word_count = 1,
    };
    const packets = [_]UmpBlockPacket{
        .{ .sample_offset = 0, .packet = valid },
        .{ .sample_offset = 24, .packet = valid },
        .{ .sample_offset = 47, .packet = rejected },
        .{ .sample_offset = 48, .packet = valid },
        .{ .sample_offset = 1, .packet = malformed },
    };

    var probe = Probe{};
    var output = UmpOutputDevice{
        .context = &probe,
        .send_output = Probe.sendOutput,
    };
    const report = try output.sendBlock(
        &packets,
        1_000_000_000,
        48_000.0,
        48,
    );
    try std.testing.expectEqual(@as(usize, 2), report.sent);
    try std.testing.expectEqual(@as(usize, 2), report.invalid);
    try std.testing.expectEqual(@as(usize, 1), report.rejected);
    try std.testing.expectEqual(@as(usize, 2), probe.count);
    try std.testing.expectEqual(
        @as(u64, 1_000_000_000),
        probe.timestamps[0],
    );
    try std.testing.expectEqual(
        @as(u64, 1_000_500_000),
        probe.timestamps[1],
    );

    try std.testing.expectError(
        error.InvalidSampleRate,
        output.sendBlock(&packets, 0, 0.0, 48),
    );
    const overflow = try output.sendBlock(
        &.{.{ .sample_offset = 1, .packet = valid }},
        std.math.maxInt(u64),
        1_000_000_000.0,
        2,
    );
    try std.testing.expectEqual(@as(usize, 1), overflow.invalid);
    try std.testing.expectEqual(@as(usize, 0), overflow.sent);
}

test "UMP block scheduler preserves every packet width and timing" {
    var scheduler = UmpBlockScheduler(4){};
    try scheduler.receive(.{
        .timestamp_nanoseconds = 999_000_000,
        .packet = try process_api.UmpPacket.init(&.{0x2090_3C7F}),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 1_001_500_000,
        .packet = try process_api.UmpPacket.init(
            &.{ 0x4090_3D00, 0x7FFF_FFFF },
        ),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 1_004_000_000,
        .packet = try process_api.UmpPacket.init(
            &.{ 0xB000_0000, 1, 2 },
        ),
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 1_005_000_000,
        .packet = try process_api.UmpPacket.init(
            &.{ 0x5000_0000, 3, 4, 5 },
        ),
    });

    var packets = UmpBlockBuffer(4){};
    const first = try scheduler.fillBlock(
        4,
        &packets,
        1_000_000_000,
        1_000.0,
        4,
    );
    try std.testing.expectEqual(@as(usize, 2), first.scheduled);
    try std.testing.expectEqual(@as(usize, 1), first.late);
    try std.testing.expect(first.future_pending);
    try std.testing.expectEqual(@as(usize, 0), packets.storage[0].sample_offset);
    try std.testing.expectEqual(@as(usize, 1), packets.storage[1].sample_offset);
    try std.testing.expectEqualSlices(
        u32,
        &.{0x2090_3C7F},
        packets.storage[0].packet.words(),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x4090_3D00, 0x7FFF_FFFF },
        packets.storage[1].packet.words(),
    );

    packets.reset();
    for (packets.storage) |packet|
        try std.testing.expectEqualDeep(UmpBlockPacket{}, packet);
    const second = try scheduler.fillBlock(
        4,
        &packets,
        1_004_000_000,
        1_000.0,
        4,
    );
    try std.testing.expectEqual(@as(usize, 2), second.scheduled);
    try std.testing.expect(!second.future_pending);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xB000_0000, 1, 2 },
        packets.storage[0].packet.words(),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x5000_0000, 3, 4, 5 },
        packets.storage[1].packet.words(),
    );
    try std.testing.expectEqual(@as(usize, 0), try scheduler.queue.pendingCount());
}

test "UMP queue and scheduler retain rejected packets safely" {
    var scheduler = UmpBlockScheduler(2){};
    const first_packet = try process_api.UmpPacket.init(&.{0x2090_3C7F});
    const second_packet = try process_api.UmpPacket.init(
        &.{ 0x4090_3C00, 0x7FFF_FFFF },
    );
    try scheduler.receive(.{
        .timestamp_nanoseconds = 10,
        .packet = first_packet,
    });
    try scheduler.receive(.{
        .timestamp_nanoseconds = 11,
        .packet = second_packet,
    });
    try std.testing.expectError(
        error.UmpInputQueueFull,
        scheduler.receive(.{
            .timestamp_nanoseconds = 12,
            .packet = first_packet,
        }),
    );
    const callback = scheduler.inputCallback();
    callback.receive(callback.context, .{
        .timestamp_nanoseconds = 12,
        .packet = first_packet,
    });
    try std.testing.expectEqual(
        @as(usize, 1),
        scheduler.rejectedPacketCount(),
    );

    var packets = UmpBlockBuffer(1){};
    const first = try scheduler.fillBlock(
        1,
        &packets,
        10,
        48_000.0,
        64,
    );
    try std.testing.expectEqual(@as(usize, 1), first.scheduled);
    try std.testing.expect(first.capacity_exhausted);
    try std.testing.expect(first.future_pending);
    try std.testing.expectEqual(@as(usize, 1), try scheduler.queue.pendingCount());

    packets.reset();
    const second = try scheduler.fillBlock(
        1,
        &packets,
        10,
        48_000.0,
        64,
    );
    try std.testing.expectEqual(@as(usize, 1), second.scheduled);
    try std.testing.expect(!second.capacity_exhausted);
    try std.testing.expect(!second.future_pending);
    try std.testing.expectError(
        error.OutOfOrderUmpTimestamp,
        scheduler.receive(.{
            .timestamp_nanoseconds = 9,
            .packet = first_packet,
        }),
    );
    try std.testing.expectError(
        error.InvalidSampleRate,
        scheduler.fillBlock(1, &packets, 10, 0.0, 64),
    );

    scheduler.reset();
    try std.testing.expectEqual(
        @as(usize, 0),
        scheduler.rejectedPacketCount(),
    );
    for (scheduler.queue.storage) |packet|
        try std.testing.expectEqualDeep(TimestampedUmpPacket{}, packet);
    try scheduler.receive(.{
        .timestamp_nanoseconds = 9,
        .packet = first_packet,
    });
    scheduler.queue.read_index.store(
        scheduler.queue.storage.len,
        .release,
    );
    try std.testing.expect(!scheduler.queue.valid());
    try std.testing.expectError(
        error.InvalidUmpInputQueue,
        scheduler.queue.pop(),
    );
}

test "standalone MIDI block buffers contain hostile counts before queue consumption" {
    const midi_message = try process_api.Midi1Message.noteOn(
        0,
        60,
        100,
    );
    var midi_buffer = Midi1EventBuffer(1){};
    midi_buffer.count = 2;
    try std.testing.expect(!midi_buffer.valid());
    try std.testing.expectError(
        error.InvalidMidiEventBuffer,
        midi_buffer.append(.{
            .sample_offset = 0,
            .message = midi_message,
        }, 1),
    );
    try std.testing.expectError(
        error.InvalidMidiEventBuffer,
        midi_buffer.events(1),
    );

    var midi_scheduler = Midi1BlockScheduler(1){};
    try midi_scheduler.receive(.{
        .timestamp_nanoseconds = 10,
        .message = midi_message,
    });
    try std.testing.expectError(
        error.InvalidMidiEventBuffer,
        midi_scheduler.fillBlock(
            1,
            &midi_buffer,
            10,
            48_000.0,
            64,
            0,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        try midi_scheduler.queue.pendingCount(),
    );
    midi_buffer.reset();
    try std.testing.expect(midi_buffer.valid());
    try std.testing.expectEqualDeep(
        process_api.Event.other(0),
        midi_buffer.storage[0],
    );
    const midi_report = try midi_scheduler.fillBlock(
        1,
        &midi_buffer,
        10,
        48_000.0,
        64,
        0,
    );
    try std.testing.expectEqual(@as(usize, 1), midi_report.scheduled);

    const ump_packet = try process_api.UmpPacket.init(
        &.{0x2090_3C64},
    );
    var ump_buffer = UmpBlockBuffer(1){};
    ump_buffer.count = 2;
    try std.testing.expect(!ump_buffer.valid());
    try std.testing.expectError(
        error.InvalidUmpBlockBuffer,
        ump_buffer.append(.{
            .sample_offset = 0,
            .packet = ump_packet,
        }, 1),
    );
    try std.testing.expectError(
        error.InvalidUmpBlockBuffer,
        ump_buffer.packets(),
    );

    var ump_scheduler = UmpBlockScheduler(1){};
    try ump_scheduler.receive(.{
        .timestamp_nanoseconds = 10,
        .packet = ump_packet,
    });
    try std.testing.expectError(
        error.InvalidUmpBlockBuffer,
        ump_scheduler.fillBlock(
            1,
            &ump_buffer,
            10,
            48_000.0,
            64,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        try ump_scheduler.queue.pendingCount(),
    );
    ump_buffer.reset();
    try std.testing.expect(ump_buffer.valid());
    try std.testing.expectEqualDeep(UmpBlockPacket{}, ump_buffer.storage[0]);
    const ump_report = try ump_scheduler.fillBlock(
        1,
        &ump_buffer,
        10,
        48_000.0,
        64,
    );
    try std.testing.expectEqual(@as(usize, 1), ump_report.scheduled);
}

test "audio device interface validates configuration and owns callback timing" {
    const Probe = struct {
        started: bool = false,
        stopped: bool = false,
        callback_count: usize = 0,

        fn processBlock(
            context: *anyopaque,
            block: CallbackBlock(f32),
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.callback_count += 1;
            @memcpy(
                block.output_channels[0],
                block.input_channels[0],
            );
        }

        fn startAudio(
            context: *anyopaque,
            _: DeviceConfiguration,
            callback: AudioCallback(f32),
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.started = true;
            const input = [_]f32{ 0.25, -0.5 };
            var output = [_]f32{ 0.0, 0.0 };
            const inputs = [_][]const f32{&input};
            const outputs = [_][]f32{&output};
            callback.process_block(callback.context, .{
                .input_channels = &inputs,
                .output_channels = &outputs,
            });
            try std.testing.expectEqualSlices(f32, &input, &output);
        }

        fn stopAudio(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.stopped = true;
        }
    };

    var probe = Probe{};
    var device = AudioDevice(f32){
        .context = &probe,
        .start_audio = Probe.startAudio,
        .stop_audio = Probe.stopAudio,
    };
    try device.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 64,
        .input_channel_count = 1,
        .output_channel_count = 1,
    }, .{
        .context = &probe,
        .process_block = Probe.processBlock,
    });
    device.stop();
    try std.testing.expect(probe.started);
    try std.testing.expect(probe.stopped);
    try std.testing.expectEqual(
        @as(usize, 1),
        probe.callback_count,
    );
    try std.testing.expectError(
        error.InvalidSampleRate,
        device.start(.{
            .sample_rate = 0.0,
            .max_block_size = 64,
            .input_channel_count = 1,
            .output_channel_count = 1,
        }, .{
            .context = &probe,
            .process_block = Probe.processBlock,
        }),
    );
}

test "MIDI output sink reports converted unsupported and rejected events" {
    const Probe = struct {
        sent_count: usize = 0,

        fn send(
            context: *anyopaque,
            packet: Midi1CallbackPacket,
        ) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (packet.message.kind() == .note_off) return false;
            self.sent_count += 1;
            return true;
        }
    };

    const event_storage = [_]process_api.Event{
        process_api.Event.noteOn(0, 0, 60, 1.0),
        process_api.Event.noteOff(1, 0, 60, 0.0),
        process_api.Event.other(2),
    };
    const events = try process_api.Events.init(&event_storage, 4);
    var probe = Probe{};
    var sink = Midi1OutputSink{
        .context = &probe,
        .send_message = Probe.send,
    };
    const report = sink.sendEvents(events);
    try std.testing.expectEqual(@as(usize, 1), report.sent);
    try std.testing.expectEqual(@as(usize, 1), report.rejected);
    try std.testing.expectEqual(@as(usize, 1), report.unsupported);
    try std.testing.expectEqual(
        @as(usize, 1),
        probe.sent_count,
    );
}

test "standalone application owns device and processor lifecycle" {
    const Plugin = struct {
        pub const name = "Standalone Application Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout = .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout = .mono;
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
    const Probe = struct {
        callback: ?AudioCallback(f32) = null,
        stop_count: usize = 0,

        fn startAudio(
            context: *anyopaque,
            _: DeviceConfiguration,
            callback: AudioCallback(f32),
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.callback = callback;
        }

        fn stopAudio(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.stop_count += 1;
            self.callback = null;
        }
    };

    var probe = Probe{};
    const Application = StandaloneApplication(Plugin, f32);
    var application = try Application.init(
        std.testing.allocator,
        .{},
        .{
            .context = &probe,
            .start_audio = Probe.startAudio,
            .stop_audio = Probe.stopAudio,
        },
    );
    defer application.deinit();
    try application.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
    });

    const input = [_]f32{ 0.5, -0.25 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    const callback = probe.callback orelse
        return error.MissingAudioCallback;
    callback.process_block(callback.context, .{
        .input_channels = &inputs,
        .output_channels = &outputs,
    });
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(
        @as(usize, 0),
        application.callbackFailureCount(),
    );

    var oversized_output = [_]f32{ 1.0, 1.0, 1.0 };
    const oversized_input = [_]f32{ 1.0, 1.0, 1.0 };
    const oversized_inputs = [_][]const f32{&oversized_input};
    const oversized_outputs = [_][]f32{&oversized_output};
    callback.process_block(callback.context, .{
        .input_channels = &oversized_inputs,
        .output_channels = &oversized_outputs,
    });
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0, 0.0 },
        &oversized_output,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        application.callbackFailureCount(),
    );
    try application.stop();
    try std.testing.expectEqual(@as(usize, 1), probe.stop_count);
}

test "standalone application contains callbacks across stop and restart" {
    const Plugin = struct {
        pub const name = "Standalone Teardown Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout = .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout = .mono;
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
    const Probe = struct {
        callback: ?AudioCallback(f32) = null,
        retained_callback: ?AudioCallback(f32) = null,
        start_count: usize = 0,
        stop_count: usize = 0,
        stop_callback_output: f32 = 0,

        fn startAudio(
            context: *anyopaque,
            _: DeviceConfiguration,
            callback: AudioCallback(f32),
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.callback = callback;
            self.retained_callback = callback;
            self.start_count += 1;
        }

        fn stopAudio(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            const callback = self.callback orelse return;
            const input = [_]f32{0.375};
            var output = [_]f32{9};
            const inputs = [_][]const f32{&input};
            const outputs = [_][]f32{&output};
            callback.process_block(callback.context, .{
                .input_channels = &inputs,
                .output_channels = &outputs,
            });
            self.stop_callback_output = output[0];
            self.callback = null;
            self.stop_count += 1;
        }
    };

    var probe = Probe{};
    const Application = StandaloneApplication(Plugin, f32);
    var application = try Application.init(
        std.testing.allocator,
        .{},
        .{
            .context = &probe,
            .start_audio = Probe.startAudio,
            .stop_audio = Probe.stopAudio,
        },
    );
    defer application.deinit();
    const configuration = DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 1,
        .input_channel_count = 1,
        .output_channel_count = 1,
    };

    try application.start(configuration);
    try application.stop();
    try std.testing.expectEqual(@as(f32, 0.375), probe.stop_callback_output);
    try std.testing.expectEqual(@as(usize, 1), probe.stop_count);

    const stale_callback = probe.retained_callback orelse
        return error.MissingRetainedAudioCallback;
    const stale_input = [_]f32{0.75};
    var stale_output = [_]f32{9};
    const stale_inputs = [_][]const f32{&stale_input};
    const stale_outputs = [_][]f32{&stale_output};
    stale_callback.process_block(stale_callback.context, .{
        .input_channels = &stale_inputs,
        .output_channels = &stale_outputs,
    });
    try std.testing.expectEqual(@as(f32, 0), stale_output[0]);
    try std.testing.expectEqual(
        @as(usize, 1),
        application.callbackFailureCount(),
    );

    try application.start(configuration);
    const restarted_callback = probe.callback orelse
        return error.MissingRestartedAudioCallback;
    var restarted_output = [_]f32{9};
    const restarted_outputs = [_][]f32{&restarted_output};
    restarted_callback.process_block(restarted_callback.context, .{
        .input_channels = &stale_inputs,
        .output_channels = &restarted_outputs,
    });
    try std.testing.expectEqual(@as(f32, 0.75), restarted_output[0]);
    try application.stop();
    try std.testing.expectEqual(@as(usize, 2), probe.start_count);
    try std.testing.expectEqual(@as(usize, 2), probe.stop_count);
}

test "standalone application rolls back a failed device start" {
    const Plugin = struct {
        pub const name = "Standalone Rollback Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: audio_layout.AudioBusLayout = .mono;
        pub const audio_output_layout: audio_layout.AudioBusLayout = .mono;
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
    const Probe = struct {
        callback: ?AudioCallback(f32) = null,
        retained_callback: ?AudioCallback(f32) = null,
        start_count: usize = 0,
        stop_count: usize = 0,
        callback_before_failure_output: f32 = 0,

        fn startAudio(
            context: *anyopaque,
            _: DeviceConfiguration,
            callback: AudioCallback(f32),
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.callback = callback;
            self.retained_callback = callback;
            self.start_count += 1;
            const input = [_]f32{0.625};
            var output = [_]f32{9};
            const inputs = [_][]const f32{&input};
            const outputs = [_][]f32{&output};
            callback.process_block(callback.context, .{
                .input_channels = &inputs,
                .output_channels = &outputs,
            });
            self.callback_before_failure_output = output[0];
            if (self.start_count == 1) {
                self.callback = null;
                return error.DeviceUnavailable;
            }
        }

        fn stopAudio(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.callback = null;
            self.stop_count += 1;
        }
    };

    var probe = Probe{};
    const Application = StandaloneApplication(Plugin, f32);
    var application = try Application.init(
        std.testing.allocator,
        .{},
        .{
            .context = &probe,
            .start_audio = Probe.startAudio,
            .stop_audio = Probe.stopAudio,
        },
    );
    defer application.deinit();
    try std.testing.expectError(
        error.DeviceUnavailable,
        application.start(.{
            .sample_rate = 48_000.0,
            .max_block_size = 64,
            .input_channel_count = 1,
            .output_channel_count = 1,
        }),
    );
    try std.testing.expect(!application.running);
    try std.testing.expectEqual(
        runtime_mod.RuntimeState.initialized,
        application.runtime.runtime.runtimeState(),
    );
    try std.testing.expectEqual(
        @as(f32, 0.625),
        probe.callback_before_failure_output,
    );

    const stale_callback = probe.retained_callback orelse
        return error.MissingFailedStartAudioCallback;
    const stale_input = [_]f32{0.25};
    var stale_output = [_]f32{9};
    const stale_inputs = [_][]const f32{&stale_input};
    const stale_outputs = [_][]f32{&stale_output};
    stale_callback.process_block(stale_callback.context, .{
        .input_channels = &stale_inputs,
        .output_channels = &stale_outputs,
    });
    try std.testing.expectEqual(@as(f32, 0), stale_output[0]);
    try std.testing.expectEqual(
        @as(usize, 1),
        application.callbackFailureCount(),
    );

    try application.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 64,
        .input_channel_count = 1,
        .output_channel_count = 1,
    });
    try std.testing.expect(application.running);
    try std.testing.expectEqual(@as(usize, 2), probe.start_count);
    try application.stop();
    try std.testing.expectEqual(@as(usize, 1), probe.stop_count);
}

test "MIDI event buffer rejects unsupported overflow and late packets" {
    var buffer = Midi1EventBuffer(1){};
    try std.testing.expectError(
        error.UnsupportedMidiMessage,
        buffer.append(.{
            .sample_offset = 0,
            .message = try process_api.Midi1Message.programChange(
                0,
                7,
            ),
        }, 2),
    );
    try buffer.append(.{
        .sample_offset = 1,
        .message = try process_api.Midi1Message.noteOn(
            0,
            60,
            127,
        ),
    }, 2);
    try std.testing.expectError(
        error.EventCapacityExceeded,
        buffer.append(.{
            .sample_offset = 0,
            .message = try process_api.Midi1Message.noteOff(
                0,
                60,
                0,
            ),
        }, 2),
    );
    buffer.reset();
    try std.testing.expectError(
        error.InvalidMidiPacket,
        buffer.append(.{
            .sample_offset = 2,
            .message = try process_api.Midi1Message.noteOn(
                0,
                60,
                127,
            ),
        }, 2),
    );
}
