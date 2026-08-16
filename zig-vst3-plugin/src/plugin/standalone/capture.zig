const std = @import("std");
const process_api = @import("../../process.zig");
const resampler = @import("../../dsp/resampler.zig");
const common = @import("common.zig");

const advanceFifoIndex = common.advanceFifoIndex;
const recordSaturatingAmount = common.recordSaturatingAmount;
const sampleSlicesOverlap = common.sampleSlicesOverlap;

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
