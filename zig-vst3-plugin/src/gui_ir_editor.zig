const std = @import("std");
const gui_file_importer = @import("gui_file_importer.zig");

pub const maximum_channels = 2;
pub const preview_capacity = 256;

pub const Command = enum {
    trim,
    normalize,
    reverse,
    fade_in,
    fade_out,
    reset,
};

pub const Snapshot = struct {
    import: gui_file_importer.Snapshot,
    sample_rate: u32,
    channels: u8,
    sample_frames: u64,
    decoded_frames: usize,
    original_frames: usize,
    original_peak: f32,
    edited_peak: f32,
    edited: bool,
};

pub fn Editor(comptime frame_capacity: usize) type {
    if (frame_capacity == 0) @compileError("IR editor frame capacity must be positive");
    return struct {
        const Self = @This();

        original: [frame_capacity * maximum_channels]f32 = @splat(0.0),
        edited: [frame_capacity * maximum_channels]f32 = @splat(0.0),
        rollback: [frame_capacity * maximum_channels]f32 = @splat(0.0),
        sample_rate: u32 = 0,
        channels: u8 = 0,
        original_frames: usize = 0,
        edited_frames: usize = 0,
        generation: u64 = 0,
        original_peak: f32 = 0.0,
        edited_peak: f32 = 0.0,
        dirty: bool = false,
        rollback_frames: usize = 0,
        rollback_peak: f32 = 0.0,
        rollback_dirty: bool = false,
        rollback_generation: u64 = 0,
        has_rollback: bool = false,

        pub fn loadFrom(self: *Self, importer: anytype) !void {
            if (self.has_rollback) return error.EditPending;
            const source = importer.snapshot();
            if (!validSource(source)) return error.InvalidSource;
            const sample_count = source.decoded_frames * source.channels;
            var offset: usize = 0;
            while (offset < sample_count) {
                const requested = sample_count - offset;
                const count = importer.copyDecoded(offset, self.rollback[offset..sample_count]);
                if (count == 0) return error.TruncatedSource;
                if (count > requested) return error.InvalidSource;
                for (self.rollback[offset .. offset + count]) |sample| {
                    if (!std.math.isFinite(sample)) return error.InvalidSource;
                }
                offset += count;
            }
            if (!sameSource(source, importer.snapshot())) return error.StaleSource;
            @memcpy(self.original[0..sample_count], self.rollback[0..sample_count]);
            @memcpy(self.edited[0..sample_count], self.rollback[0..sample_count]);
            self.sample_rate = source.sample_rate;
            self.channels = source.channels;
            self.original_frames = source.decoded_frames;
            self.edited_frames = source.decoded_frames;
            self.original_peak = peak(self.original[0..sample_count]);
            self.edited_peak = self.original_peak;
            self.dirty = false;
            self.has_rollback = false;
            self.advanceGeneration();
        }

        fn validSource(source: anytype) bool {
            return source.import.status == .ready and source.import.generation != 0 and
                source.sample_rate >= 8_000 and source.sample_rate <= 384_000 and
                source.channels > 0 and source.channels <= maximum_channels and
                source.decoded_frames > 0 and source.decoded_frames <= frame_capacity and
                source.sample_frames == source.decoded_frames;
        }

        fn sameSource(first: anytype, second: anytype) bool {
            return validSource(second) and first.import.generation == second.import.generation and
                first.sample_rate == second.sample_rate and first.channels == second.channels and
                first.sample_frames == second.sample_frames and first.decoded_frames == second.decoded_frames;
        }

        pub fn apply(self: *Self, command: Command, selection_start: f64, selection_end: f64) !bool {
            if (!self.valid()) return error.InvalidState;
            if (self.edited_frames == 0 or self.channels == 0) return error.Empty;
            if (!std.math.isFinite(selection_start) or !std.math.isFinite(selection_end) or
                selection_start < 0.0 or selection_end > 1.0 or selection_end < selection_start)
            {
                return error.InvalidSelection;
            }
            self.saveRollback();
            errdefer self.rollbackLastEdit();
            if (command == .reset) {
                const changed = self.resetEdited();
                if (!changed) self.has_rollback = false;
                return changed;
            }
            const range = frameRange(self.edited_frames, selection_start, selection_end) orelse
                return error.EmptySelection;
            const changed = switch (command) {
                .trim => self.trim(range.start, range.end),
                .normalize => try self.normalize(range.start, range.end),
                .reverse => self.reverse(range.start, range.end),
                .fade_in => self.fade(range.start, range.end, true),
                .fade_out => self.fade(range.start, range.end, false),
                .reset => unreachable,
            };
            if (!changed) {
                self.has_rollback = false;
                return false;
            }
            self.edited_peak = peak(self.edited[0 .. self.edited_frames * self.channels]);
            self.dirty = true;
            self.advanceGeneration();
            return true;
        }

        pub fn commitLastEdit(self: *Self) void {
            self.has_rollback = false;
        }

        pub fn rollbackLastEdit(self: *Self) void {
            if (!self.has_rollback) return;
            if (!self.valid()) {
                self.has_rollback = false;
                return;
            }
            const sample_count = self.rollback_frames * self.channels;
            @memcpy(self.edited[0..sample_count], self.rollback[0..sample_count]);
            self.edited_frames = self.rollback_frames;
            self.edited_peak = self.rollback_peak;
            self.dirty = self.rollback_dirty;
            self.generation = self.rollback_generation;
            self.has_rollback = false;
        }

        pub fn reset(self: *Self) bool {
            if (!self.valid()) return false;
            self.has_rollback = false;
            return self.resetEdited();
        }

        fn resetEdited(self: *Self) bool {
            if (self.original_frames == 0 or !self.dirty) return false;
            const sample_count = self.original_frames * self.channels;
            @memcpy(self.edited[0..sample_count], self.original[0..sample_count]);
            self.edited_frames = self.original_frames;
            self.edited_peak = self.original_peak;
            self.dirty = false;
            self.advanceGeneration();
            return true;
        }

        pub fn clear(self: *Self) bool {
            if (self.original_frames == 0 and self.edited_frames == 0) return false;
            self.sample_rate = 0;
            self.channels = 0;
            self.original_frames = 0;
            self.edited_frames = 0;
            self.original_peak = 0.0;
            self.edited_peak = 0.0;
            self.dirty = false;
            self.has_rollback = false;
            self.advanceGeneration();
            return true;
        }

        pub fn snapshot(self: *const Self) Snapshot {
            if (!self.valid()) return emptySnapshot();
            const ready = self.edited_frames != 0;
            return .{
                .import = .{
                    .status = if (ready) .ready else .idle,
                    .entry_point = .picker,
                    .path_count = @intFromBool(ready),
                    .completed_units = self.edited_frames,
                    .total_units = self.edited_frames,
                    .generation = self.generation,
                    .cancellation_pending = false,
                },
                .sample_rate = self.sample_rate,
                .channels = self.channels,
                .sample_frames = self.edited_frames,
                .decoded_frames = self.edited_frames,
                .original_frames = self.original_frames,
                .original_peak = self.original_peak,
                .edited_peak = self.edited_peak,
                .edited = self.dirty,
            };
        }

        pub fn copyDecoded(self: *const Self, sample_offset: usize, output: []f32) usize {
            if (!self.valid()) return 0;
            const sample_count = self.edited_frames * self.channels;
            if (sample_offset >= sample_count) return 0;
            const count = @min(output.len, sample_count - sample_offset);
            @memcpy(output[0..count], self.edited[sample_offset .. sample_offset + count]);
            return count;
        }

        pub fn copyPreview(self: *const Self, output: []@import("gui_audio_file_importer.zig").PreviewPoint) usize {
            if (!self.valid()) return 0;
            if (self.edited_frames == 0 or output.len == 0) return 0;
            const count = @min(output.len, preview_capacity, self.edited_frames);
            for (0..count) |index| {
                const first = index * self.edited_frames / count;
                const end = @max(first + 1, (index + 1) * self.edited_frames / count);
                var sum: f64 = 0.0;
                var samples: usize = 0;
                for (first..@min(end, self.edited_frames)) |frame| {
                    for (0..self.channels) |channel| {
                        sum += self.edited[frame * self.channels + channel];
                        samples += 1;
                    }
                }
                output[index] = .{
                    .x = if (count == 1) 0.0 else @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(count - 1)),
                    .y = std.math.clamp(sum / @as(f64, @floatFromInt(samples)), -1.0, 1.0),
                };
            }
            return count;
        }

        fn trim(self: *Self, start: usize, end: usize) bool {
            if (start == 0 and end == self.edited_frames) return false;
            const frames = end - start;
            const channels: usize = self.channels;
            for (0..frames * channels) |sample| {
                self.edited[sample] = self.edited[start * channels + sample];
            }
            self.edited_frames = frames;
            return true;
        }

        fn normalize(self: *Self, start: usize, end: usize) !bool {
            const channels: usize = self.channels;
            const samples = self.edited[start * channels .. end * channels];
            const selected_peak = peak(samples);
            if (selected_peak == 0.0) return error.SilentSelection;
            if (@abs(selected_peak - 1.0) <= 1e-6) return false;
            const scale = 1.0 / selected_peak;
            for (samples) |*sample| sample.* *= scale;
            return true;
        }

        fn reverse(self: *Self, start: usize, end: usize) bool {
            if (end - start < 2) return false;
            const channels: usize = self.channels;
            for (0..(end - start) / 2) |offset| {
                const left = start + offset;
                const right = end - 1 - offset;
                for (0..channels) |channel| {
                    std.mem.swap(
                        f32,
                        &self.edited[left * channels + channel],
                        &self.edited[right * channels + channel],
                    );
                }
            }
            return true;
        }

        fn fade(self: *Self, start: usize, end: usize, fade_in: bool) bool {
            const frames = end - start;
            if (frames < 2) return false;
            const channels: usize = self.channels;
            for (0..frames) |offset| {
                const position = @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(frames - 1));
                const gain = if (fade_in) position else 1.0 - position;
                for (0..channels) |channel| self.edited[(start + offset) * channels + channel] *= gain;
            }
            return true;
        }

        fn advanceGeneration(self: *Self) void {
            self.generation +%= 1;
            if (self.generation == 0) self.generation = 1;
        }

        fn saveRollback(self: *Self) void {
            const sample_count = self.edited_frames * self.channels;
            @memcpy(self.rollback[0..sample_count], self.edited[0..sample_count]);
            self.rollback_frames = self.edited_frames;
            self.rollback_peak = self.edited_peak;
            self.rollback_dirty = self.dirty;
            self.rollback_generation = self.generation;
            self.has_rollback = true;
        }

        pub fn valid(self: *const Self) bool {
            const empty = self.original_frames == 0 and self.edited_frames == 0;
            if (empty) {
                if (self.channels != 0 or self.sample_rate != 0) return false;
            } else {
                if (self.sample_rate < 8_000 or self.sample_rate > 384_000) return false;
                if (self.channels == 0 or self.channels > maximum_channels) return false;
                if (self.original_frames == 0 or self.edited_frames == 0) return false;
                if (self.original_frames > frame_capacity or self.edited_frames > frame_capacity) return false;
            }
            if (!validPeak(self.original_peak) or !validPeak(self.edited_peak)) return false;
            if (self.has_rollback) {
                if (self.rollback_frames == 0 or self.rollback_frames > frame_capacity) return false;
                if (!validPeak(self.rollback_peak)) return false;
            }
            return true;
        }

        fn emptySnapshot() Snapshot {
            return .{
                .import = .{
                    .status = .idle,
                    .entry_point = .picker,
                    .path_count = 0,
                    .completed_units = 0,
                    .total_units = 0,
                    .generation = 0,
                    .cancellation_pending = false,
                },
                .sample_rate = 0,
                .channels = 0,
                .sample_frames = 0,
                .decoded_frames = 0,
                .original_frames = 0,
                .original_peak = 0.0,
                .edited_peak = 0.0,
                .edited = false,
            };
        }
    };
}

const FrameRange = struct { start: usize, end: usize };

fn frameRange(frames: usize, start: f64, end: f64) ?FrameRange {
    if (frames == 0) return null;
    const first: usize = @min(frames - 1, @as(usize, @intFromFloat(@floor(start * @as(f64, @floatFromInt(frames))))));
    const last: usize = @min(frames, @as(usize, @intFromFloat(@ceil(end * @as(f64, @floatFromInt(frames))))));
    if (last <= first) return null;
    return .{ .start = first, .end = last };
}

fn peak(samples: []const f32) f32 {
    var result: f32 = 0.0;
    for (samples) |sample| result = @max(result, @abs(sample));
    return result;
}

fn validPeak(value: f32) bool {
    return std.math.isFinite(value) and value >= 0.0;
}

const TestImporter = struct {
    samples: []const f32,

    fn snapshot(self: *const TestImporter) struct {
        import: gui_file_importer.Snapshot,
        sample_rate: u32,
        channels: u8,
        sample_frames: u64,
        decoded_frames: usize,
    } {
        return .{
            .import = .{ .status = .ready, .entry_point = .picker, .path_count = 1, .completed_units = 1, .total_units = 1, .generation = 1, .cancellation_pending = false },
            .sample_rate = 48_000,
            .channels = 1,
            .sample_frames = self.samples.len,
            .decoded_frames = self.samples.len,
        };
    }

    fn copyDecoded(self: *const TestImporter, offset: usize, output: []f32) usize {
        if (offset >= self.samples.len) return 0;
        const count = @min(output.len, self.samples.len - offset);
        @memcpy(output[0..count], self.samples[offset .. offset + count]);
        return count;
    }
};

const HostileImporter = struct {
    samples: []const f32,
    generation: u64 = 1,
    reported_count_delta: usize = 0,
    replace_after_copy: bool = false,

    fn snapshot(self: *const HostileImporter) struct {
        import: gui_file_importer.Snapshot,
        sample_rate: u32,
        channels: u8,
        sample_frames: u64,
        decoded_frames: usize,
    } {
        return .{
            .import = .{ .status = .ready, .entry_point = .picker, .path_count = 1, .completed_units = 1, .total_units = 1, .generation = self.generation, .cancellation_pending = false },
            .sample_rate = 48_000,
            .channels = 1,
            .sample_frames = self.samples.len,
            .decoded_frames = self.samples.len,
        };
    }

    fn copyDecoded(self: *HostileImporter, offset: usize, output: []f32) usize {
        if (offset >= self.samples.len) return 0;
        const count = @min(output.len, self.samples.len - offset);
        @memcpy(output[0..count], self.samples[offset .. offset + count]);
        if (self.replace_after_copy) self.generation += 1;
        return count + self.reported_count_delta;
    }
};

test "IR editor composes edits and resets to the immutable source" {
    const samples = [_]f32{ 0.25, 0.5, -0.25, -0.5, 0.125, -0.125 };
    const importer = TestImporter{ .samples = &samples };
    var editor = Editor(8){};
    try editor.loadFrom(&importer);
    try std.testing.expect(try editor.apply(.trim, 1.0 / 6.0, 5.0 / 6.0));
    try std.testing.expectEqual(@as(usize, 4), editor.snapshot().decoded_frames);
    try std.testing.expect(try editor.apply(.reverse, 0.0, 1.0));
    try std.testing.expect(try editor.apply(.normalize, 0.0, 1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), editor.snapshot().edited_peak, 1e-6);
    var transformed: [4]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 4), editor.copyDecoded(0, &transformed));
    try std.testing.expectEqualSlices(f32, &.{ 0.25, -1.0, -0.5, 1.0 }, &transformed);
    try std.testing.expect(editor.reset());
    var restored: [6]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 6), editor.copyDecoded(0, &restored));
    try std.testing.expectEqualSlices(f32, &samples, &restored);
}

test "IR editor applies bounded fades and rejects silent normalization" {
    const samples = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const importer = TestImporter{ .samples = &samples };
    var editor = Editor(4){};
    try editor.loadFrom(&importer);
    try std.testing.expect(try editor.apply(.fade_in, 0.0, 1.0));
    var faded: [4]f32 = undefined;
    _ = editor.copyDecoded(0, &faded);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), faded[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), faded[3], 1e-6);
    try std.testing.expect(editor.reset());
    try std.testing.expect(try editor.apply(.fade_out, 0.0, 1.0));
    _ = editor.copyDecoded(0, &faded);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), faded[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), faded[3], 1e-6);
    const silence = [_]f32{ 0.0, 0.0 };
    const silent_importer = TestImporter{ .samples = &silence };
    var silent = Editor(2){};
    try silent.loadFrom(&silent_importer);
    try std.testing.expectError(error.SilentSelection, silent.apply(.normalize, 0.0, 1.0));
}

test "IR editor rolls back a rejected publication" {
    const samples = [_]f32{ 0.25, 0.5, -0.25, -0.5 };
    const importer = TestImporter{ .samples = &samples };
    var editor = Editor(4){};
    try editor.loadFrom(&importer);
    const generation = editor.snapshot().import.generation;
    try std.testing.expect(try editor.apply(.reverse, 0.0, 1.0));
    editor.rollbackLastEdit();
    var restored: [4]f32 = undefined;
    _ = editor.copyDecoded(0, &restored);
    try std.testing.expectEqualSlices(f32, &samples, &restored);
    try std.testing.expectEqual(generation, editor.snapshot().import.generation);
    try std.testing.expect(!editor.snapshot().edited);
}

test "IR editor replacement is transactional for hostile sources" {
    const original = [_]f32{ 0.25, 0.5, -0.25, -0.5 };
    const original_importer = TestImporter{ .samples = &original };
    var editor = Editor(4){};
    try editor.loadFrom(&original_importer);
    const original_snapshot = editor.snapshot();

    const malformed = [_]f32{ 1.0, std.math.nan(f32), 0.5, 0.25 };
    var non_finite = HostileImporter{ .samples = &malformed };
    try std.testing.expectError(error.InvalidSource, editor.loadFrom(&non_finite));
    var oversized = HostileImporter{ .samples = &original, .reported_count_delta = 1 };
    try std.testing.expectError(error.InvalidSource, editor.loadFrom(&oversized));
    var replaced = HostileImporter{ .samples = &original, .replace_after_copy = true };
    try std.testing.expectError(error.StaleSource, editor.loadFrom(&replaced));

    try std.testing.expectEqual(original_snapshot.import.generation, editor.snapshot().import.generation);
    var retained: [4]f32 = undefined;
    try std.testing.expectEqual(retained.len, editor.copyDecoded(0, &retained));
    try std.testing.expectEqualSlices(f32, &original, &retained);
}

test "IR editor refuses replacement while publication rollback is pending" {
    const samples = [_]f32{ 0.25, 0.5, -0.25, -0.5 };
    const importer = TestImporter{ .samples = &samples };
    var editor = Editor(4){};
    try editor.loadFrom(&importer);
    try std.testing.expect(try editor.apply(.reverse, 0.0, 1.0));
    try std.testing.expectError(error.EditPending, editor.loadFrom(&importer));
    editor.commitLastEdit();
    try editor.loadFrom(&importer);
    try std.testing.expect(!editor.snapshot().edited);
}

test "IR editor rejects malformed public bounds and clear recovers" {
    const samples = [_]f32{ 0.25, 0.5, -0.25, -0.5 };
    const importer = TestImporter{ .samples = &samples };
    var editor = Editor(4){};
    try editor.loadFrom(&importer);

    editor.edited_frames = 5;
    try std.testing.expect(!editor.valid());
    try std.testing.expectError(error.InvalidState, editor.apply(.reverse, 0.0, 1.0));
    var decoded: [4]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 0), editor.copyDecoded(0, &decoded));
    try std.testing.expectEqual(@as(usize, 0), editor.snapshot().decoded_frames);
    try std.testing.expect(editor.clear());
    try std.testing.expect(editor.valid());

    try editor.loadFrom(&importer);
    try std.testing.expect(try editor.apply(.reverse, 0.0, 1.0));
    editor.rollback_frames = 5;
    try std.testing.expect(!editor.valid());
    editor.rollbackLastEdit();
    try std.testing.expect(editor.valid());

    editor.channels = maximum_channels + 1;
    try std.testing.expect(!editor.valid());
    try std.testing.expect(!editor.reset());
    try std.testing.expect(editor.clear());
    try std.testing.expect(editor.valid());
}
