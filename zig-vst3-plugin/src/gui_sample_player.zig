const std = @import("std");
const sample_store = @import("gui_audio_sample_store.zig");

pub const Envelope = struct {
    attack_seconds: f64 = 0.005,
    decay_seconds: f64 = 0.08,
    sustain: f64 = 0.8,
    release_seconds: f64 = 0.15,
};

pub const Playback = struct {
    gain: f64 = 1.0,
    pan: f64 = 0.0,
    coarse_semitones: f64 = 0.0,
    fine_cents: f64 = 0.0,
    start: f64 = 0.0,
    end: f64 = 1.0,
    loop_start: f64 = 0.0,
    loop_end: f64 = 1.0,
    loop_enabled: bool = false,
    reverse: bool = false,
    release_on_note_off: bool = true,
    voice_limit: usize = std.math.maxInt(usize),
    root_note: i16 = 60,
    envelope: Envelope = .{},
};

pub fn Player(comptime maximum_frames: usize, comptime voice_count: usize) type {
    if (voice_count == 0 or voice_count > 64) @compileError("sample player voice count must be between 1 and 64");
    const SampleStore = sample_store.Store(maximum_frames);

    return struct {
        const Self = @This();

        const Stage = enum { idle, attack, decay, sustain, release };
        const Voice = struct {
            stage: Stage = .idle,
            note: i16 = 0,
            velocity: f64 = 0.0,
            position: f64 = 0.0,
            level: f64 = 0.0,
            age: u64 = 0,
        };

        store: SampleStore = .{},
        voices: [voice_count]Voice = @splat(.{}),
        next_age: u64 = 1,
        output_sample_rate: f64 = 48_000.0,

        pub fn prepare(self: *Self, sample_rate: f64) void {
            self.output_sample_rate = std.math.clamp(finiteOr(sample_rate, 48_000.0), 8_000.0, 384_000.0);
        }

        pub fn reset(self: *Self) void {
            self.voices = @splat(.{});
        }

        pub fn audioImportReceiver(self: *Self) *SampleStore {
            return &self.store;
        }

        pub fn adoptPending(self: *Self) bool {
            const adopted = self.store.adoptPending();
            if (adopted) self.reset();
            return adopted;
        }

        pub fn noteOn(self: *Self, note: i16, velocity: f64, playback: Playback) void {
            if (!self.outputRateValid() or note < 0 or note > 127) return;
            const metadata = self.store.activeMetadata() orelse return;
            if (metadata.frames == 0 or !std.math.isFinite(velocity) or velocity <= 0.0) {
                self.noteOff(note, playback);
                return;
            }
            self.ensureVoiceAgeSpace();
            const index = self.voiceForAttack(playback.voice_limit);
            const bounds = frameBounds(metadata.frames, playback.start, playback.end);
            self.voices[index] = .{
                .stage = if (playback.envelope.attack_seconds <= 0.0) .decay else .attack,
                .note = note,
                .velocity = std.math.clamp(velocity, 0.0, 1.0),
                .position = if (playback.reverse) bounds.end else bounds.start,
                .level = if (playback.envelope.attack_seconds <= 0.0) 1.0 else 0.0,
                .age = self.next_age,
            };
            self.next_age += 1;
        }

        pub fn noteOff(self: *Self, note: i16, playback: Playback) void {
            if (!playback.release_on_note_off) return;
            for (&self.voices) |*voice| {
                if (voice.stage != .idle and voice.note == note) voice.stage = .release;
            }
        }

        pub fn allNotesOff(self: *Self) void {
            for (&self.voices) |*voice| {
                if (voice.stage != .idle) voice.stage = .release;
            }
        }

        pub fn processFrame(self: *Self, playback: Playback) [2]f32 {
            if (!self.outputRateValid()) {
                self.reset();
                return .{ 0.0, 0.0 };
            }
            const metadata = self.store.activeMetadata() orelse return .{ 0.0, 0.0 };
            if (metadata.frames == 0) return .{ 0.0, 0.0 };
            const bounds = frameBounds(metadata.frames, playback.start, playback.end);
            const loop = loopBounds(bounds, playback.loop_start, playback.loop_end);
            const pan = std.math.clamp(finiteOr(playback.pan, 0.0), -1.0, 1.0);
            const left_pan = if (pan > 0.0) 1.0 - pan else 1.0;
            const right_pan = if (pan < 0.0) 1.0 + pan else 1.0;
            const gain = std.math.clamp(finiteOr(playback.gain, 1.0), 0.0, 16.0);
            const active_limit = std.math.clamp(playback.voice_limit, 1, voice_count);
            var output: [2]f64 = .{ 0.0, 0.0 };

            for (&self.voices, 0..) |*voice, index| {
                if (index >= active_limit) {
                    voice.* = .{};
                    continue;
                }
                if (voice.stage == .idle) continue;
                if (!voiceValid(voice.*)) {
                    voice.* = .{};
                    continue;
                }
                const level = self.advanceEnvelope(voice, playback.envelope);
                if (voice.stage == .idle) continue;
                const left = self.store.sample(0, voice.position);
                const right = self.store.sample(if (metadata.channels == 1) 0 else 1, voice.position);
                const amplitude = level * voice.velocity * gain;
                output[0] += left * amplitude * left_pan;
                output[1] += right * amplitude * right_pan;

                const semitones = @as(f64, @floatFromInt(voice.note)) -
                    @as(f64, @floatFromInt(std.math.clamp(playback.root_note, 0, 127))) +
                    std.math.clamp(finiteOr(playback.coarse_semitones, 0.0), -48.0, 48.0) +
                    std.math.clamp(finiteOr(playback.fine_cents, 0.0), -100.0, 100.0) / 100.0;
                const rate = @as(f64, @floatFromInt(metadata.sample_rate)) / self.output_sample_rate *
                    std.math.pow(f64, 2.0, semitones / 12.0);
                voice.position += if (playback.reverse) -rate else rate;
                self.advancePosition(voice, bounds, loop, playback.loop_enabled, playback.reverse);
            }
            return .{ boundedOutput(output[0]), boundedOutput(output[1]) };
        }

        pub fn playhead(self: *const Self) ?f64 {
            if (!self.outputRateValid()) return null;
            const metadata = self.store.activeMetadata() orelse return null;
            if (metadata.frames <= 1) return null;
            var newest: ?Voice = null;
            for (self.voices) |voice| {
                if (voice.stage == .idle or !voiceValid(voice)) continue;
                if (newest) |current| {
                    if (voice.age > current.age) newest = voice;
                } else {
                    newest = voice;
                }
            }
            const voice = newest orelse return null;
            return std.math.clamp(voice.position / @as(f64, @floatFromInt(metadata.frames - 1)), 0.0, 1.0);
        }

        fn outputRateValid(self: *const Self) bool {
            return std.math.isFinite(self.output_sample_rate) and
                self.output_sample_rate >= 8_000.0 and self.output_sample_rate <= 384_000.0;
        }

        fn voiceForAttack(self: *Self, requested_limit: usize) usize {
            const limit = std.math.clamp(requested_limit, 1, voice_count);
            for (self.voices[0..limit], 0..) |voice, index| {
                if (voice.stage == .idle) return index;
            }
            var oldest_index: usize = 0;
            for (self.voices[1..limit], 1..) |voice, index| {
                if (voice.age < self.voices[oldest_index].age) oldest_index = index;
            }
            return oldest_index;
        }

        fn ensureVoiceAgeSpace(self: *Self) void {
            if (self.next_age != 0 and self.next_age != std.math.maxInt(u64)) return;
            var assigned: [voice_count]bool = @splat(false);
            var next: u64 = 1;
            for (0..voice_count) |_| {
                var oldest: ?usize = null;
                for (self.voices, 0..) |voice, index| {
                    if (voice.stage == .idle or assigned[index]) continue;
                    if (oldest) |oldest_index| {
                        if (voice.age < self.voices[oldest_index].age)
                            oldest = index;
                    } else {
                        oldest = index;
                    }
                }
                const index = oldest orelse break;
                self.voices[index].age = next;
                assigned[index] = true;
                next += 1;
            }
            self.next_age = next;
        }

        fn advanceEnvelope(self: *Self, voice: *Voice, envelope: Envelope) f64 {
            const sustain = std.math.clamp(finiteOr(envelope.sustain, 0.8), 0.0, 1.0);
            switch (voice.stage) {
                .idle => return 0.0,
                .attack => {
                    voice.level += envelopeStep(envelope.attack_seconds, self.output_sample_rate);
                    if (voice.level >= 1.0) {
                        voice.level = 1.0;
                        voice.stage = .decay;
                    }
                },
                .decay => {
                    voice.level -= envelopeStep(envelope.decay_seconds, self.output_sample_rate) * (1.0 - sustain);
                    if (voice.level <= sustain) {
                        voice.level = sustain;
                        voice.stage = .sustain;
                    }
                },
                .sustain => voice.level = sustain,
                .release => {
                    voice.level -= envelopeStep(envelope.release_seconds, self.output_sample_rate);
                    if (voice.level <= 0.0) voice.* = .{};
                },
            }
            return voice.level;
        }

        fn advancePosition(
            _: *Self,
            voice: *Voice,
            bounds: Bounds,
            loop: Bounds,
            loop_enabled: bool,
            reverse: bool,
        ) void {
            if (loop_enabled) {
                const span = loop.end - loop.start;
                if (!reverse and voice.position > loop.end) voice.position = loop.start + @mod(voice.position - loop.start, span);
                if (reverse and voice.position < loop.start) voice.position = loop.end - @mod(loop.end - voice.position, span);
                return;
            }
            if ((!reverse and voice.position > bounds.end) or (reverse and voice.position < bounds.start)) voice.* = .{};
        }

        fn voiceValid(voice: Voice) bool {
            return voice.note >= 0 and voice.note <= 127 and
                voice.age != 0 and
                std.math.isFinite(voice.velocity) and voice.velocity >= 0.0 and voice.velocity <= 1.0 and
                std.math.isFinite(voice.position) and
                std.math.isFinite(voice.level) and voice.level >= 0.0 and voice.level <= 1.0;
        }
    };
}

const Bounds = struct { start: f64, end: f64 };

fn frameBounds(frame_count: usize, start: f64, end: f64) Bounds {
    const last = @as(f64, @floatFromInt(frame_count - 1));
    const bounded_start = std.math.clamp(finiteOr(start, 0.0), 0.0, 1.0) * last;
    const bounded_end = std.math.clamp(finiteOr(end, 1.0), 0.0, 1.0) * last;
    return .{ .start = @min(bounded_start, bounded_end), .end = @max(bounded_start, bounded_end) };
}

fn loopBounds(playback: Bounds, loop_start: f64, loop_end: f64) Bounds {
    const span = playback.end - playback.start;
    const start = playback.start + std.math.clamp(finiteOr(loop_start, 0.0), 0.0, 1.0) * span;
    const end = playback.start + std.math.clamp(finiteOr(loop_end, 1.0), 0.0, 1.0) * span;
    const ordered_start = @min(start, end);
    return .{ .start = ordered_start, .end = @max(ordered_start + 0.000001, @max(start, end)) };
}

fn envelopeStep(seconds: f64, sample_rate: f64) f64 {
    if (!std.math.isFinite(seconds) or seconds <= 0.0) return 1.0;
    return 1.0 / @max(1.0, seconds * sample_rate);
}

fn finiteOr(value: f64, fallback: f64) f64 {
    return if (std.math.isFinite(value)) value else fallback;
}

fn boundedOutput(value: f64) f32 {
    if (!std.math.isFinite(value)) return 0.0;
    return @floatCast(std.math.clamp(value, -16.0, 16.0));
}

test "sample player adopts complete media and renders interpolated notes" {
    var player = Player(4, 2){};
    player.prepare(48_000);
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 4 });
    try player.store.write(1, 0, &.{ 0.0, 0.5, 1.0, 0.0 });
    try player.store.commit(1);
    try std.testing.expect(player.adoptPending());
    player.noteOn(60, 1.0, .{ .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 } });
    const first = player.processFrame(.{ .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 } });
    const second = player.processFrame(.{ .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 } });
    try std.testing.expectEqual(@as(f32, 0.0), first[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), second[0], 0.000001);
    try std.testing.expectEqual(second[0], second[1]);
}

test "sample player steals the oldest voice deterministically" {
    var player = Player(2, 2){};
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 1.0, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();
    const playback = Playback{ .loop_enabled = true, .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0 } };
    player.noteOn(60, 1.0, playback);
    player.noteOn(61, 1.0, playback);
    player.noteOn(62, 1.0, playback);
    try std.testing.expectEqual(@as(i16, 62), player.voices[0].note);
    try std.testing.expectEqual(@as(i16, 61), player.voices[1].note);
    const mixed = player.processFrame(playback);
    try std.testing.expectEqual(@as([2]f32, .{ 2.0, 2.0 }), mixed);

    const mono_limit = Playback{ .loop_enabled = true, .voice_limit = 1, .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0 } };
    const limited = player.processFrame(mono_limit);
    try std.testing.expectEqual(@as([2]f32, .{ 1.0, 1.0 }), limited);
    try std.testing.expect(player.voices[1].stage == .idle);
}

test "sample player rebases exhausted voice ages before stealing" {
    var player = Player(2, 2){};
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 1.0, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();
    const playback = Playback{
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 },
    };
    player.noteOn(60, 1.0, playback);
    player.noteOn(61, 1.0, playback);
    player.voices[0].age = std.math.maxInt(u64) - 2;
    player.voices[1].age = std.math.maxInt(u64) - 1;
    player.next_age = std.math.maxInt(u64);

    player.noteOn(62, 1.0, playback);
    try std.testing.expectEqual(@as(i16, 62), player.voices[0].note);
    try std.testing.expectEqual(@as(i16, 61), player.voices[1].note);
    try std.testing.expect(player.voices[0].age > player.voices[1].age);
    try std.testing.expectEqual(@as(u64, 4), player.next_age);
}

test "sample player releases notes and bounds reverse loops" {
    var player = Player(4, 1){};
    player.prepare(1_000);
    try player.store.begin(.{ .generation = 1, .sample_rate = 8_000, .channels = 2, .frames = 4 });
    try player.store.write(1, 0, &.{ 0.2, -0.2, 0.4, -0.4, 0.6, -0.6, 0.8, -0.8 });
    try player.store.commit(1);
    _ = player.adoptPending();
    const playback = Playback{
        .reverse = true,
        .loop_enabled = true,
        .loop_start = 0.25,
        .loop_end = 0.75,
        .pan = -0.5,
        .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0, .release_seconds = 0.001 },
    };
    player.noteOn(60, 1.0, playback);
    for (0..32) |_| {
        const output = player.processFrame(playback);
        try std.testing.expect(std.math.isFinite(output[0]));
        try std.testing.expect(std.math.isFinite(output[1]));
    }
    player.noteOff(60, playback);
    for (0..8) |_| _ = player.processFrame(playback);
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}

test "sample player applies gain pan coarse and fine tuning" {
    var player = Player(8, 1){};
    player.prepare(48_000);
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 8 });
    try player.store.write(1, 0, &.{ 0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875 });
    try player.store.commit(1);
    _ = player.adoptPending();

    const playback = Playback{
        .gain = 0.5,
        .pan = -1.0,
        .coarse_semitones = 11.0,
        .fine_cents = 100.0,
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 },
    };
    player.noteOn(60, 1.0, playback);
    const first = player.processFrame(playback);
    const second = player.processFrame(playback);
    try std.testing.expectEqual(@as(f32, 0.0), first[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), second[0], 0.000001);
    try std.testing.expectEqual(@as(f32, 0.0), second[1]);
}

test "sample player honors playback bounds and one shot note release" {
    var player = Player(5, 1){};
    player.prepare(48_000);
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 5 });
    try player.store.write(1, 0, &.{ 0.0, 0.25, 0.5, 0.75, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();

    const playback = Playback{
        .start = 0.5,
        .end = 0.75,
        .release_on_note_off = false,
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 },
    };
    player.noteOn(60, 1.0, playback);
    player.noteOff(60, playback);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), player.processFrame(playback)[0], 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), player.processFrame(playback)[0], 0.000001);
    _ = player.processFrame(playback);
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}

test "sample player advances attack decay sustain and release" {
    var player = Player(2, 1){};
    player.prepare(8_000);
    try player.store.begin(.{ .generation = 1, .sample_rate = 8_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 1.0, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();

    const playback = Playback{
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.001, .decay_seconds = 0.001, .sustain = 0.5, .release_seconds = 0.001 },
    };
    player.noteOn(60, 1.0, playback);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), player.processFrame(playback)[0], 0.000001);
    for (0..15) |_| _ = player.processFrame(playback);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), player.processFrame(playback)[0], 0.000001);
    player.noteOff(60, playback);
    for (0..8) |_| _ = player.processFrame(playback);
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}

test "sample player is silent without media and all notes off releases voices" {
    var player = Player(2, 2){};
    const silent = player.processFrame(.{});
    try std.testing.expectEqual(@as([2]f32, .{ 0.0, 0.0 }), silent);
    player.noteOn(60, 1.0, .{});
    try std.testing.expectEqual(@as(?f64, null), player.playhead());

    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 1.0, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();
    const playback = Playback{
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0, .release_seconds = 0.0 },
    };
    player.noteOn(60, 1.0, playback);
    player.noteOn(64, 1.0, playback);
    player.allNotesOff();
    _ = player.processFrame(playback);
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}

test "sample player renders exact forward reverse and loop sequences offline" {
    const expected_forward = [_]f32{ 0.25, 0.5, 0.75, 1.0, 0.0 };
    const expected_reverse = [_]f32{ 1.0, 0.75, 0.5, 0.25, 0.0 };
    const expected_loop = [_]f32{ 0.25, 0.5, 0.75, 0.5, 0.75, 0.5 };
    const sustained = Envelope{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 };

    var forward = Player(4, 1){};
    try forward.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 4 });
    try forward.store.write(1, 0, &.{ 0.25, 0.5, 0.75, 1.0 });
    try forward.store.commit(1);
    _ = forward.adoptPending();
    forward.noteOn(60, 1.0, .{ .envelope = sustained });
    for (expected_forward) |expected| {
        try std.testing.expectApproxEqAbs(expected, forward.processFrame(.{ .envelope = sustained })[0], 0.000001);
    }

    var reverse = Player(4, 1){};
    try reverse.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 4 });
    try reverse.store.write(1, 0, &.{ 0.25, 0.5, 0.75, 1.0 });
    try reverse.store.commit(1);
    _ = reverse.adoptPending();
    reverse.noteOn(60, 1.0, .{ .reverse = true, .envelope = sustained });
    for (expected_reverse) |expected| {
        try std.testing.expectApproxEqAbs(expected, reverse.processFrame(.{ .reverse = true, .envelope = sustained })[0], 0.000001);
    }

    var looped = Player(5, 1){};
    try looped.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 5 });
    try looped.store.write(1, 0, &.{ 0.0, 0.25, 0.5, 0.75, 1.0 });
    try looped.store.commit(1);
    _ = looped.adoptPending();
    const loop_playback = Playback{
        .start = 0.25,
        .end = 0.75,
        .loop_start = 0.5,
        .loop_end = 1.0,
        .loop_enabled = true,
        .envelope = sustained,
    };
    looped.noteOn(60, 1.0, loop_playback);
    for (expected_loop) |expected| {
        try std.testing.expectApproxEqAbs(expected, looped.processFrame(loop_playback)[0], 0.000001);
    }
}

test "sample player contains non-finite public playback inputs" {
    var player = Player(2, 1){};
    player.prepare(std.math.nan(f64));
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 0.5, 1.0 });
    try player.store.commit(1);
    _ = player.adoptPending();

    const invalid = Playback{
        .gain = std.math.nan(f64),
        .pan = std.math.inf(f64),
        .coarse_semitones = -std.math.inf(f64),
        .fine_cents = std.math.nan(f64),
        .start = std.math.nan(f64),
        .end = std.math.inf(f64),
        .loop_start = std.math.nan(f64),
        .loop_end = -std.math.inf(f64),
        .loop_enabled = true,
        .root_note = std.math.minInt(i16),
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = std.math.nan(f64) },
    };
    player.noteOn(60, std.math.nan(f64), invalid);
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
    player.noteOn(60, 1.0, invalid);
    for (0..8) |_| {
        const frame = player.processFrame(invalid);
        try std.testing.expect(std.math.isFinite(frame[0]));
        try std.testing.expect(std.math.isFinite(frame[1]));
        try std.testing.expect(player.playhead() != null);
    }
}

test "sample player rejects malformed retained realtime state" {
    var player = Player(2, 1){};
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 0.5, 1.0 });
    try player.store.commit(1);
    try std.testing.expect(player.adoptPending());

    player.noteOn(-1, 1.0, .{});
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
    player.noteOn(128, 1.0, .{});
    try std.testing.expectEqual(@as(?f64, null), player.playhead());

    player.noteOn(60, 1.0, .{ .loop_enabled = true });
    player.voices[0].position = std.math.nan(f64);
    try std.testing.expectEqual(@as([2]f32, .{ 0.0, 0.0 }), player.processFrame(.{ .loop_enabled = true }));
    try std.testing.expectEqual(@as(?f64, null), player.playhead());

    player.noteOn(60, 1.0, .{});
    player.output_sample_rate = 0.0;
    try std.testing.expectEqual(@as([2]f32, .{ 0.0, 0.0 }), player.processFrame(.{}));
    try std.testing.expectEqual(@as(?f64, null), player.playhead());

    player.prepare(48_000.0);
    player.noteOn(60, 1.0, .{
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0 },
    });
    player.voices[0].level = std.math.floatMax(f64);
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        player.processFrame(.{ .loop_enabled = true }),
    );
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}

test "sample player generated lifecycle sequences remain finite and bounded" {
    const seed = 0x5a6d_91e2_2026_0721;
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();

    for (0..64) |case_index| {
        var player = Player(32, 4){};
        var generation: u64 = 1;
        var samples: [64]f32 = undefined;
        for (&samples) |*sample| sample.* = random.float(f32) * 2.0 - 1.0;
        try player.store.begin(.{ .generation = generation, .sample_rate = 48_000, .channels = 2, .frames = 32 });
        try player.store.write(generation, 0, &samples);
        try player.store.commit(generation);
        try std.testing.expect(player.adoptPending());

        for (0..512) |operation_index| {
            const inject_non_finite = operation_index % 47 == 0;
            const playback = Playback{
                .gain = if (inject_non_finite) std.math.nan(f64) else random.float(f64) * 24.0 - 4.0,
                .pan = random.float(f64) * 4.0 - 2.0,
                .coarse_semitones = random.float(f64) * 160.0 - 80.0,
                .fine_cents = random.float(f64) * 400.0 - 200.0,
                .start = random.float(f64) * 3.0 - 1.0,
                .end = random.float(f64) * 3.0 - 1.0,
                .loop_start = random.float(f64) * 3.0 - 1.0,
                .loop_end = random.float(f64) * 3.0 - 1.0,
                .loop_enabled = random.boolean(),
                .reverse = random.boolean(),
                .release_on_note_off = random.boolean(),
                .voice_limit = random.uintLessThan(usize, 9),
                .root_note = if (inject_non_finite) std.math.minInt(i16) else @intCast(random.uintLessThan(u8, 128)),
                .envelope = .{
                    .attack_seconds = random.float(f64) * 0.06 - 0.01,
                    .decay_seconds = random.float(f64) * 0.06 - 0.01,
                    .sustain = if (inject_non_finite) std.math.nan(f64) else random.float(f64) * 3.0 - 1.0,
                    .release_seconds = random.float(f64) * 0.06 - 0.01,
                },
            };
            const note: i16 = if (inject_non_finite) std.math.maxInt(i16) else @intCast(random.uintLessThan(u8, 128));

            switch (random.uintLessThan(u8, 7)) {
                0 => player.noteOn(note, random.float(f64) * 2.0 - 0.5, playback),
                1 => player.noteOff(note, playback),
                2 => player.allNotesOff(),
                3 => player.reset(),
                4 => player.prepare(if (inject_non_finite) std.math.nan(f64) else random.float(f64) * 450_000.0),
                5 => {
                    generation += 1;
                    for (&samples) |*sample| sample.* = random.float(f32) * 2.0 - 1.0;
                    try player.store.begin(.{ .generation = generation, .sample_rate = 48_000, .channels = 2, .frames = 32 });
                    try player.store.write(generation, 0, &samples);
                    try player.store.commit(generation);
                    try std.testing.expect(player.adoptPending());
                },
                else => {},
            }

            const frame = player.processFrame(playback);
            const valid = std.math.isFinite(frame[0]) and std.math.isFinite(frame[1]) and
                @abs(frame[0]) <= 16.0 and @abs(frame[1]) <= 16.0 and
                if (player.playhead()) |position| std.math.isFinite(position) and position >= 0.0 and position <= 1.0 else true;
            if (!valid) {
                std.debug.print("sample player seed={x} case={} operation={}\n", .{ seed, case_index, operation_index });
                return error.GeneratedSamplePlayerInvariantFailed;
            }
        }
    }
}
