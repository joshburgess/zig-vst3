const std = @import("std");
const gui_file_importer = @import("gui_file_importer.zig");
const realtime_audit = @import("realtime_audit.zig");
const resource_job = @import("resource/job.zig");

pub const preview_capacity = 256;
pub const maximum_input_bytes = 32 * 1024 * 1024;
pub const maximum_sample_frames = 8 * 1024 * 1024;
pub const maximum_channels = 2;
pub const minimum_sample_rate = 8_000;
pub const maximum_sample_rate = 384_000;

pub const Failure = enum {
    none,
    open_failed,
    too_large,
    malformed,
    truncated,
    unsupported_format,
    cancelled,
    worker_unavailable,
};

pub const PreviewPoint = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
};

pub const Snapshot = struct {
    import: gui_file_importer.Snapshot,
    failure: Failure,
    sample_rate: u32,
    channels: u8,
    sample_frames: u64,
    preview_points: usize,
    decoded_frames: usize,

    pub fn validate(self: Snapshot) !void {
        try self.import.validate();
        if (self.preview_points > preview_capacity or
            self.sample_frames > maximum_sample_frames or
            self.decoded_frames > maximum_sample_frames or
            self.decoded_frames > self.sample_frames or
            self.preview_points > self.sample_frames or
            self.channels > maximum_channels)
        {
            return error.InvalidAudioImportBounds;
        }
        const has_metadata = self.sample_rate != 0 or self.channels != 0 or self.sample_frames != 0;
        if (has_metadata and
            (self.sample_rate < minimum_sample_rate or
                self.sample_rate > maximum_sample_rate or
                self.channels == 0 or
                self.sample_frames == 0))
        {
            return error.InvalidAudioImportMetadata;
        }
        if (!has_metadata and (self.preview_points != 0 or self.decoded_frames != 0)) {
            return error.InvalidAudioImportMetadata;
        }
        if (self.import.status == .ready) {
            if (self.import.generation == 0 or
                !has_metadata or
                self.preview_points == 0 or
                (self.decoded_frames != 0 and self.decoded_frames != self.sample_frames))
            {
                return error.InvalidAudioImportMetadata;
            }
        } else if (self.preview_points != 0 or self.decoded_frames != 0) {
            return error.InvalidAudioImportState;
        }

        const failure_matches_status = switch (self.import.status) {
            .cancelled => self.failure == .cancelled,
            .failed => self.failure == .open_failed or
                self.failure == .malformed or
                self.failure == .truncated or
                self.failure == .worker_unavailable,
            .unsupported_file => self.failure == .none or self.failure == .unsupported_format,
            .capacity_limit => self.failure == .none or self.failure == .too_large,
            else => self.failure == .none,
        };
        if (!failure_matches_status) return error.InvalidAudioImportState;
    }

    pub fn valid(self: Snapshot) bool {
        self.validate() catch return false;
        return true;
    }
};

test "audio import snapshot validates bounded metadata" {
    const import_snapshot = gui_file_importer.Snapshot{
        .status = .ready,
        .entry_point = .picker,
        .path_count = 1,
        .completed_units = 16,
        .total_units = 16,
        .generation = 4,
        .cancellation_pending = false,
    };
    const valid = Snapshot{
        .import = import_snapshot,
        .failure = .none,
        .sample_rate = 48_000,
        .channels = 2,
        .sample_frames = 8,
        .preview_points = 8,
        .decoded_frames = 8,
    };
    try valid.validate();

    var malformed = valid;
    malformed.preview_points = preview_capacity + 1;
    try std.testing.expectError(error.InvalidAudioImportBounds, malformed.validate());
    malformed = valid;
    malformed.decoded_frames = 9;
    try std.testing.expectError(error.InvalidAudioImportBounds, malformed.validate());
    malformed = valid;
    malformed.sample_rate = maximum_sample_rate + 1;
    try std.testing.expectError(error.InvalidAudioImportMetadata, malformed.validate());
    malformed = valid;
    malformed.channels = 0;
    try std.testing.expectError(error.InvalidAudioImportMetadata, malformed.validate());
    malformed = valid;
    malformed.failure = .malformed;
    try std.testing.expectError(error.InvalidAudioImportState, malformed.validate());
    malformed = valid;
    malformed.import.status = .failed;
    try std.testing.expectError(error.InvalidAudioImportState, malformed.validate());
    malformed = valid;
    malformed.import.status = .failed;
    malformed.failure = .truncated;
    malformed.preview_points = 0;
    malformed.decoded_frames = 0;
    try malformed.validate();
    malformed = valid;
    malformed.decoded_frames = 7;
    try std.testing.expectError(error.InvalidAudioImportMetadata, malformed.validate());
    try std.testing.expect(valid.valid());
}

const ByteOrder = enum { little, big };

const AudioInfo = struct {
    data_offset: u64,
    data_bytes: usize,
    sample_rate: u32,
    channels: u8,
    bits_per_sample: u8,
    block_align: u8,
    sample_frames: usize,
    byte_order: ByteOrder,
};

pub fn DecodedImporter(comptime decoded_frame_capacity: usize) type {
    if (decoded_frame_capacity > maximum_sample_frames) {
        @compileError("DecodedImporter capacity exceeds the WAV frame limit");
    }
    return struct {
        const Model = gui_file_importer.Model(1, 3);
        const Self = @This();
        const WorkerFailure = enum { decode_failed };
        const Worker = resource_job.Job(struct {
            pub const Request = *Self;
            pub const Result = u8;
            pub const Failure = WorkerFailure;
            pub const maximum_work_units = maximum_input_bytes;
            pub const maximum_result_units = 1;
            pub const maximum_runtime_nanoseconds = 60 * std.time.ns_per_s;

            pub fn run(importer: *Self, context: *resource_job.WorkerContext) resource_job.Outcome(Result, WorkerFailure) {
                return importer.runWorker(context);
            }
        });

        mutex: std.Io.Mutex = .init,
        model: Model,
        failure: Failure = .none,
        sample_rate: u32 = 0,
        channels: u8 = 0,
        sample_frames: u64 = 0,
        preview: [preview_capacity]PreviewPoint = @splat(.{}),
        preview_points: usize = 0,
        decoded: [decoded_frame_capacity * maximum_channels]f32 = @splat(0.0),
        decoded_frames: usize = 0,
        worker: Worker,

        pub fn init() Self {
            var self: Self = undefined;
            self.initInto();
            return self;
        }

        pub fn initInto(self: *Self) void {
            self.mutex = .init;
            self.model = comptime Model.init(
                &.{ ".wav", ".aif", ".aiff" },
            ) catch @compileError("invalid built-in audio extensions");
            self.failure = .none;
            self.sample_rate = 0;
            self.channels = 0;
            self.sample_frames = 0;
            self.clearMediaStorage();
            self.worker = Worker.init();
        }

        pub fn deinit(self: *Self) void {
            self.lock();
            if (self.model.snapshot().canCancel()) self.model.requestCancel() catch {};
            self.unlock();
            _ = self.worker.requestCancel();
            self.worker.deinit();
            self.lock();
            if (self.model.cancellationRequested()) {
                self.model.acknowledgeCancel() catch {};
                self.failure = .cancelled;
                self.clearMediaStorage();
            }
            self.unlock();
        }

        pub fn begin(self: *Self, entry_point: gui_file_importer.EntryPoint, paths: []const []const u8) bool {
            const file_allowed = realtime_audit.observe(.file_access);
            const allocation_allowed = realtime_audit.observe(.allocation);
            if (!file_allowed or !allocation_allowed) return false;
            if (self.workerRunning()) return false;
            self.reapWorker();

            self.lock();
            const status = self.model.begin(entry_point, paths);
            self.failure = .none;
            self.sample_rate = 0;
            self.channels = 0;
            self.sample_frames = 0;
            self.clearMediaStorage();
            self.unlock();
            if (status != .validating) return false;
            return self.spawnWorker();
        }

        pub fn retry(self: *Self) bool {
            if (self.workerRunning()) return false;
            self.reapWorker();
            self.lock();
            self.model.retry() catch {
                self.unlock();
                return false;
            };
            self.failure = .none;
            self.unlock();
            return self.spawnWorker();
        }

        pub fn requestCancel(self: *Self) bool {
            self.lock();
            self.model.requestCancel() catch {
                self.unlock();
                return false;
            };
            self.unlock();
            _ = self.worker.requestCancel();
            return true;
        }

        pub fn canReset(self: *const Self) bool {
            return !self.workerRunning();
        }

        pub fn workerRunning(self: *const Self) bool {
            if (!self.worker.worker_running.load(.acquire)) return false;
            const mutable: *Self = @constCast(self);
            mutable.lock();
            defer mutable.unlock();
            const status = self.model.snapshot().status;
            return status == .validating or status == .importing;
        }

        pub fn reset(self: *Self) bool {
            if (!self.canReset()) return false;
            self.reapWorker();
            self.lock();
            defer self.unlock();
            self.model.reset();
            self.failure = .none;
            self.sample_rate = 0;
            self.channels = 0;
            self.sample_frames = 0;
            self.clearMediaStorage();
            return true;
        }

        pub fn snapshot(self: *Self) Snapshot {
            self.lock();
            defer self.unlock();
            return .{
                .import = self.model.snapshot(),
                .failure = self.failure,
                .sample_rate = self.sample_rate,
                .channels = self.channels,
                .sample_frames = self.sample_frames,
                .preview_points = self.preview_points,
                .decoded_frames = self.decoded_frames,
            };
        }

        pub fn copyPreview(self: *Self, output: []PreviewPoint) usize {
            self.lock();
            defer self.unlock();
            if (self.preview_points > preview_capacity) return 0;
            const count = @min(output.len, self.preview_points);
            for (self.preview[0..count]) |point| {
                if (!std.math.isFinite(point.x) or
                    !std.math.isFinite(point.y)) return 0;
            }
            @memcpy(output[0..count], self.preview[0..count]);
            return count;
        }

        pub fn copyDecoded(self: *Self, sample_offset: usize, output: []f32) usize {
            self.lock();
            defer self.unlock();
            if (self.decoded_frames > decoded_frame_capacity or self.channels == 0 or self.channels > maximum_channels) {
                return 0;
            }
            const sample_count = std.math.mul(usize, self.decoded_frames, self.channels) catch return 0;
            if (sample_count > self.decoded.len) return 0;
            if (sample_offset >= sample_count) return 0;
            const count = @min(output.len, sample_count - sample_offset);
            const source = self.decoded[sample_offset .. sample_offset + count];
            for (source) |sample| {
                if (!std.math.isFinite(sample)) return 0;
            }
            @memcpy(output[0..count], source);
            return count;
        }

        fn spawnWorker(self: *Self) bool {
            if (!self.worker.submit(self)) {
                self.finishFailure(.worker_unavailable);
                return false;
            }
            return true;
        }

        fn runWorker(self: *Self, context: *resource_job.WorkerContext) resource_job.Outcome(u8, WorkerFailure) {
            var path_storage: [1024]u8 = undefined;
            self.lock();
            const path = self.model.path(0) orelse {
                self.unlock();
                self.finishFailure(.malformed);
                return .{ .failure = .decode_failed };
            };
            @memcpy(path_storage[0..path.len], path);
            const path_length = path.len;
            self.unlock();
            self.decode(path_storage[0..path_length], context);
            const result = self.snapshot();
            return switch (result.import.status) {
                .ready => .{ .success = .{ .value = 0, .result_units = 1 } },
                .cancelled => .cancelled,
                else => .{ .failure = .decode_failed },
            };
        }

        fn decode(self: *Self, path: []const u8, context: *resource_job.WorkerContext) void {
            const io = std.Io.Threaded.global_single_threaded.io();
            const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
                self.finishFailure(.open_failed);
                return;
            };
            defer file.close(io);
            const file_size = file.length(io) catch {
                self.finishFailure(.open_failed);
                return;
            };
            if (file_size > maximum_input_bytes) {
                self.finishFailure(.too_large);
                return;
            }
            const info = parseAudio(io, file, file_size) catch |err| {
                self.finishFailure(switch (err) {
                    error.Truncated => .truncated,
                    error.UnsupportedFormat => .unsupported_format,
                    error.TooLarge => .too_large,
                    else => .malformed,
                });
                return;
            };
            if (decoded_frame_capacity != 0 and info.sample_frames > decoded_frame_capacity) {
                self.finishFailure(.too_large);
                return;
            }
            context.setPhase(.loading) catch {
                self.finishFailure(.cancelled);
                return;
            };
            context.setTotalUnits(info.data_bytes) catch {
                self.finishFailure(.too_large);
                return;
            };

            self.lock();
            self.model.startImport(info.data_bytes) catch {
                self.unlock();
                self.finishFailure(.malformed);
                return;
            };
            self.sample_rate = info.sample_rate;
            self.channels = info.channels;
            self.sample_frames = info.sample_frames;
            self.unlock();

            var sums: [preview_capacity]f64 = @splat(0.0);
            var counts: [preview_capacity]u32 = @splat(0);
            var buffer: [4096]u8 = undefined;
            var bytes_done: usize = 0;
            var frame_index: usize = 0;
            while (bytes_done < info.data_bytes) {
                if (self.model.cancellationRequested() or context.cancellationRequested()) {
                    self.finishFailure(.cancelled);
                    return;
                }
                const remaining = info.data_bytes - bytes_done;
                var amount = @min(remaining, buffer.len);
                amount -= amount % info.block_align;
                if (amount == 0) amount = info.block_align;
                const read = file.readPositionalAll(io, buffer[0..amount], info.data_offset + bytes_done) catch {
                    self.finishFailure(.truncated);
                    return;
                };
                if (read != amount) {
                    self.finishFailure(.truncated);
                    return;
                }
                var offset: usize = 0;
                while (offset < read) : (offset += info.block_align) {
                    var mixed: f64 = 0.0;
                    const sample_bytes = info.bits_per_sample / 8;
                    for (0..info.channels) |channel| {
                        const start = offset + channel * sample_bytes;
                        const sample = decodePcm(buffer[start .. start + sample_bytes], info.bits_per_sample, info.byte_order);
                        mixed += sample;
                        if (decoded_frame_capacity != 0) {
                            self.decoded[frame_index * info.channels + channel] = @floatCast(sample);
                        }
                    }
                    mixed /= @floatFromInt(info.channels);
                    const bin = @min(preview_capacity - 1, frame_index * preview_capacity / info.sample_frames);
                    sums[bin] += mixed;
                    counts[bin] += 1;
                    frame_index += 1;
                }
                bytes_done += read;
                self.lock();
                self.model.advance(bytes_done) catch {};
                self.unlock();
                context.advance(bytes_done, info.data_bytes) catch {
                    self.finishFailure(.cancelled);
                    return;
                };
            }

            var points: [preview_capacity]PreviewPoint = undefined;
            var point_count: usize = 0;
            for (sums, counts, 0..) |sum, count, index| {
                if (count == 0) continue;
                points[point_count] = .{
                    .x = if (preview_capacity == 1) 0.0 else @as(f64, @floatFromInt(index)) / @as(f64, preview_capacity - 1),
                    .y = std.math.clamp(sum / @as(f64, @floatFromInt(count)), -1.0, 1.0),
                };
                point_count += 1;
            }

            self.lock();
            @memcpy(self.preview[0..point_count], points[0..point_count]);
            self.preview_points = point_count;
            self.decoded_frames = if (decoded_frame_capacity == 0) 0 else info.sample_frames;
            self.failure = .none;
            self.model.complete(point_count) catch {};
            self.unlock();
        }

        fn finishFailure(self: *Self, failure: Failure) void {
            self.lock();
            defer self.unlock();
            self.failure = failure;
            self.clearMediaStorage();
            const status: gui_file_importer.Status = switch (failure) {
                .too_large => .capacity_limit,
                .unsupported_format => .unsupported_file,
                .cancelled => .cancelled,
                else => .failed,
            };
            self.model.finishWith(status) catch {};
        }

        fn reapWorker(self: *Self) void {
            if (self.workerRunning()) return;
            self.joinWorker();
        }

        fn joinWorker(self: *Self) void {
            self.worker.wait();
        }

        fn clearMediaStorage(self: *Self) void {
            self.preview = @splat(.{});
            self.preview_points = 0;
            @memset(&self.decoded, 0.0);
            self.decoded_frames = 0;
        }

        fn lock(self: *Self) void {
            _ = realtime_audit.observe(.lock);
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        }

        fn unlock(self: *Self) void {
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    };
}

pub const Importer = DecodedImporter(0);

fn parseAudio(io: std.Io, file: std.Io.File, file_size: u64) !AudioInfo {
    if (file_size < 12) return error.Truncated;
    var header: [12]u8 = undefined;
    if (try file.readPositionalAll(io, &header, 0) != header.len) return error.Truncated;
    if (std.mem.eql(u8, header[0..4], "RIFF") and std.mem.eql(u8, header[8..12], "WAVE")) {
        return parseWav(io, file, file_size, header);
    }
    if (std.mem.eql(u8, header[0..4], "FORM") and
        (std.mem.eql(u8, header[8..12], "AIFF") or std.mem.eql(u8, header[8..12], "AIFC")))
    {
        return parseAiff(io, file, file_size, header);
    }
    return error.Malformed;
}

fn parseWav(io: std.Io, file: std.Io.File, file_size: u64, header: [12]u8) !AudioInfo {
    if (file_size < 12) return error.Truncated;
    const riff_bytes = readU32(header[4..8]);
    if (@as(u64, riff_bytes) + 8 > file_size) return error.Truncated;

    var format: ?struct {
        sample_rate: u32,
        channels: u16,
        bits_per_sample: u16,
        block_align: u16,
    } = null;
    var data_offset: ?u64 = null;
    var data_bytes: usize = 0;
    var offset: u64 = 12;
    while (offset + 8 <= file_size) {
        var chunk_header: [8]u8 = undefined;
        if (try file.readPositionalAll(io, &chunk_header, offset) != chunk_header.len) return error.Truncated;
        const chunk_size = readU32(chunk_header[4..8]);
        const payload_offset = offset + 8;
        const payload_end = std.math.add(u64, payload_offset, chunk_size) catch return error.Malformed;
        if (payload_end > file_size) return error.Truncated;
        if (std.mem.eql(u8, chunk_header[0..4], "fmt ")) {
            if (chunk_size < 16) return error.Malformed;
            var bytes: [16]u8 = undefined;
            if (try file.readPositionalAll(io, &bytes, payload_offset) != bytes.len) return error.Truncated;
            const audio_format = readU16(bytes[0..2]);
            const channels = readU16(bytes[2..4]);
            const sample_rate = readU32(bytes[4..8]);
            const byte_rate = readU32(bytes[8..12]);
            const block_align = readU16(bytes[12..14]);
            const bits_per_sample = readU16(bytes[14..16]);
            if (audio_format != 1 or channels == 0 or channels > maximum_channels or
                (bits_per_sample != 16 and bits_per_sample != 24 and bits_per_sample != 32) or
                sample_rate < minimum_sample_rate or sample_rate > maximum_sample_rate) return error.UnsupportedFormat;
            const expected_align = channels * (bits_per_sample / 8);
            if (block_align != expected_align or byte_rate != sample_rate * block_align) return error.Malformed;
            format = .{
                .sample_rate = sample_rate,
                .channels = channels,
                .bits_per_sample = bits_per_sample,
                .block_align = block_align,
            };
        } else if (std.mem.eql(u8, chunk_header[0..4], "data")) {
            data_offset = payload_offset;
            data_bytes = chunk_size;
        }
        offset = payload_end + (chunk_size & 1);
    }

    const wav_format = format orelse return error.Malformed;
    const wav_data_offset = data_offset orelse return error.Malformed;
    if (data_bytes == 0) return error.Malformed;
    if (data_bytes % wav_format.block_align != 0) return error.Truncated;
    const sample_frames = data_bytes / wav_format.block_align;
    if (sample_frames > maximum_sample_frames) return error.TooLarge;
    return .{
        .data_offset = wav_data_offset,
        .data_bytes = data_bytes,
        .sample_rate = wav_format.sample_rate,
        .channels = @intCast(wav_format.channels),
        .bits_per_sample = @intCast(wav_format.bits_per_sample),
        .block_align = @intCast(wav_format.block_align),
        .sample_frames = sample_frames,
        .byte_order = .little,
    };
}

fn parseAiff(io: std.Io, file: std.Io.File, file_size: u64, header: [12]u8) !AudioInfo {
    const form_bytes = readU32Be(header[4..8]);
    if (@as(u64, form_bytes) + 8 > file_size) return error.Truncated;
    const is_aifc = std.mem.eql(u8, header[8..12], "AIFC");

    var format: ?struct {
        sample_rate: u32,
        channels: u16,
        bits_per_sample: u16,
        sample_frames: u32,
    } = null;
    var data_offset: ?u64 = null;
    var data_bytes: usize = 0;
    var offset: u64 = 12;
    while (offset + 8 <= file_size) {
        var chunk_header: [8]u8 = undefined;
        if (try file.readPositionalAll(io, &chunk_header, offset) != chunk_header.len) return error.Truncated;
        const chunk_size = readU32Be(chunk_header[4..8]);
        const payload_offset = offset + 8;
        const payload_end = std.math.add(u64, payload_offset, chunk_size) catch return error.Malformed;
        if (payload_end > file_size) return error.Truncated;
        if (std.mem.eql(u8, chunk_header[0..4], "COMM")) {
            if (chunk_size < 18 or (is_aifc and chunk_size < 22)) return error.Malformed;
            var bytes: [22]u8 = @splat(0);
            const required: usize = if (is_aifc) 22 else 18;
            if (try file.readPositionalAll(io, bytes[0..required], payload_offset) != required) return error.Truncated;
            if (is_aifc and !std.mem.eql(u8, bytes[18..22], "NONE")) return error.UnsupportedFormat;
            const channels = readU16Be(bytes[0..2]);
            const sample_frames = readU32Be(bytes[2..6]);
            const bits_per_sample = readU16Be(bytes[6..8]);
            const sample_rate = try decodeExtendedSampleRate(bytes[8..18]);
            if (channels == 0 or channels > maximum_channels or
                (bits_per_sample != 16 and bits_per_sample != 24 and bits_per_sample != 32) or
                sample_frames == 0)
            {
                return error.UnsupportedFormat;
            }
            format = .{
                .sample_rate = sample_rate,
                .channels = channels,
                .bits_per_sample = bits_per_sample,
                .sample_frames = sample_frames,
            };
        } else if (std.mem.eql(u8, chunk_header[0..4], "SSND")) {
            if (chunk_size < 8) return error.Malformed;
            var sound_header: [8]u8 = undefined;
            if (try file.readPositionalAll(io, &sound_header, payload_offset) != sound_header.len) return error.Truncated;
            const sound_offset = readU32Be(sound_header[0..4]);
            if (@as(u64, sound_offset) > chunk_size - 8) return error.Malformed;
            data_offset = payload_offset + 8 + sound_offset;
            data_bytes = chunk_size - 8 - sound_offset;
        }
        offset = payload_end + (chunk_size & 1);
    }

    const aiff_format = format orelse return error.Malformed;
    const aiff_data_offset = data_offset orelse return error.Malformed;
    const block_align = aiff_format.channels * (aiff_format.bits_per_sample / 8);
    if (data_bytes == 0 or data_bytes % block_align != 0) return error.Truncated;
    const sample_frames = data_bytes / block_align;
    if (sample_frames != aiff_format.sample_frames) return error.Truncated;
    if (sample_frames > maximum_sample_frames) return error.TooLarge;
    return .{
        .data_offset = aiff_data_offset,
        .data_bytes = data_bytes,
        .sample_rate = aiff_format.sample_rate,
        .channels = @intCast(aiff_format.channels),
        .bits_per_sample = @intCast(aiff_format.bits_per_sample),
        .block_align = @intCast(block_align),
        .sample_frames = sample_frames,
        .byte_order = .big,
    };
}

fn decodeExtendedSampleRate(bytes: []const u8) !u32 {
    const exponent_bits = readU16Be(bytes[0..2]);
    if (exponent_bits & 0x8000 != 0) return error.UnsupportedFormat;
    const exponent = exponent_bits & 0x7fff;
    const mantissa = readU64Be(bytes[2..10]);
    if (exponent == 0 or exponent == 0x7fff or mantissa & (@as(u64, 1) << 63) == 0) return error.UnsupportedFormat;
    const shift: i32 = @as(i32, exponent) - 16383 - 63;
    const value = std.math.ldexp(@as(f64, @floatFromInt(mantissa)), shift);
    if (!std.math.isFinite(value) or value < minimum_sample_rate or value > maximum_sample_rate) return error.UnsupportedFormat;
    const rounded = @round(value);
    if (@abs(value - rounded) > 0.001) return error.UnsupportedFormat;
    return @intFromFloat(rounded);
}

fn decodePcm(bytes: []const u8, bits_per_sample: u8, byte_order: ByteOrder) f64 {
    return switch (bits_per_sample) {
        16 => @as(f64, @floatFromInt(@as(i16, @bitCast(switch (byte_order) {
            .little => readU16(bytes[0..2]),
            .big => readU16Be(bytes[0..2]),
        })))) / 32768.0,
        24 => blk: {
            var value = switch (byte_order) {
                .little => @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16),
                .big => (@as(u32, bytes[0]) << 16) | (@as(u32, bytes[1]) << 8) | bytes[2],
            };
            if (value & 0x0080_0000 != 0) value |= 0xff00_0000;
            break :blk @as(f64, @floatFromInt(@as(i32, @bitCast(value)))) / 8_388_608.0;
        },
        32 => @as(f64, @floatFromInt(@as(i32, @bitCast(switch (byte_order) {
            .little => readU32(bytes[0..4]),
            .big => readU32Be(bytes[0..4]),
        })))) / 2_147_483_648.0,
        else => 0.0,
    };
}

fn readU16(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn readU32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

fn readU16Be(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32Be(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}

fn readU64Be(bytes: []const u8) u64 {
    var value: u64 = 0;
    for (bytes[0..8]) |byte| value = (value << 8) | byte;
    return value;
}

fn writeU16(bytes: []u8, value: u16) void {
    bytes[0] = @truncate(value);
    bytes[1] = @truncate(value >> 8);
}

fn writeU32(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value);
    bytes[1] = @truncate(value >> 8);
    bytes[2] = @truncate(value >> 16);
    bytes[3] = @truncate(value >> 24);
}

fn writeU16Be(bytes: []u8, value: u16) void {
    bytes[0] = @truncate(value >> 8);
    bytes[1] = @truncate(value);
}

fn writeU32Be(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value >> 24);
    bytes[1] = @truncate(value >> 16);
    bytes[2] = @truncate(value >> 8);
    bytes[3] = @truncate(value);
}

fn pcm16Fixture(comptime frame_count: usize) [44 + frame_count * 4]u8 {
    var bytes: [44 + frame_count * 4]u8 = @splat(0);
    @memcpy(bytes[0..4], "RIFF");
    writeU32(bytes[4..8], bytes.len - 8);
    @memcpy(bytes[8..12], "WAVE");
    @memcpy(bytes[12..16], "fmt ");
    writeU32(bytes[16..20], 16);
    writeU16(bytes[20..22], 1);
    writeU16(bytes[22..24], 2);
    writeU32(bytes[24..28], 48_000);
    writeU32(bytes[28..32], 48_000 * 4);
    writeU16(bytes[32..34], 4);
    writeU16(bytes[34..36], 16);
    @memcpy(bytes[36..40], "data");
    writeU32(bytes[40..44], frame_count * 4);
    for (0..frame_count) |frame| {
        const phase = @as(i32, @intCast(frame % 64)) - 32;
        const sample: i16 = @intCast(phase * 900);
        const bits: u16 = @bitCast(sample);
        const offset = 44 + frame * 4;
        writeU16(bytes[offset .. offset + 2], bits);
        writeU16(bytes[offset + 2 .. offset + 4], bits);
    }
    return bytes;
}

fn pcm16AiffFixture(comptime frame_count: usize) [54 + frame_count * 4]u8 {
    var bytes: [54 + frame_count * 4]u8 = @splat(0);
    @memcpy(bytes[0..4], "FORM");
    writeU32Be(bytes[4..8], bytes.len - 8);
    @memcpy(bytes[8..12], "AIFF");
    @memcpy(bytes[12..16], "COMM");
    writeU32Be(bytes[16..20], 18);
    writeU16Be(bytes[20..22], 2);
    writeU32Be(bytes[22..26], frame_count);
    writeU16Be(bytes[26..28], 16);
    writeU16Be(bytes[28..30], 0x400e);
    bytes[30] = 0xbb;
    bytes[31] = 0x80;
    @memcpy(bytes[38..42], "SSND");
    writeU32Be(bytes[42..46], 8 + frame_count * 4);
    for (0..frame_count) |frame| {
        const phase = @as(i32, @intCast(frame % 64)) - 32;
        const sample: i16 = @intCast(phase * 900);
        const bits: u16 = @bitCast(sample);
        const offset = 54 + frame * 4;
        writeU16Be(bytes[offset .. offset + 2], bits);
        writeU16Be(bytes[offset + 2 .. offset + 4], bits);
    }
    return bytes;
}

fn waitForWorker(importer: anytype) void {
    while (importer.workerRunning()) std.Thread.yield() catch {};
    importer.reapWorker();
}

test "audio importer decodes a bounded PCM WAV preview" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16Fixture(1024);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "valid.wav", .data = &fixture });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "valid.wav", &path);

    var importer = Importer.init();
    defer importer.deinit();
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);

    const result = importer.snapshot();
    try std.testing.expectEqual(gui_file_importer.Status.ready, result.import.status);
    try std.testing.expectEqual(Failure.none, result.failure);
    try std.testing.expectEqual(@as(u32, 48_000), result.sample_rate);
    try std.testing.expectEqual(@as(u8, 2), result.channels);
    try std.testing.expectEqual(@as(u64, 1024), result.sample_frames);
    try std.testing.expectEqual(@as(usize, preview_capacity), result.preview_points);
    var points: [preview_capacity]PreviewPoint = undefined;
    try std.testing.expectEqual(@as(usize, preview_capacity), importer.copyPreview(&points));
    try std.testing.expectEqual(@as(f64, 0.0), points[0].x);
    try std.testing.expectEqual(@as(f64, 1.0), points[preview_capacity - 1].x);
    try std.testing.expect(points[7].y >= -1.0 and points[7].y <= 1.0);
}

test "decoded importer keeps bounded interleaved PCM for non-audio-thread handoff" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16Fixture(16);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "decoded.wav", .data = &fixture });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "decoded.wav", &path);

    var importer = DecodedImporter(16).init();
    defer importer.deinit();
    for (importer.preview) |point|
        try std.testing.expectEqualDeep(PreviewPoint{}, point);
    for (importer.decoded) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(@as(usize, 16), importer.snapshot().decoded_frames);
    var samples: [32]f32 = undefined;
    try std.testing.expectEqual(samples.len, importer.copyDecoded(0, &samples));
    try std.testing.expectEqual(samples[0], samples[1]);
    try std.testing.expectEqual(samples[30], samples[31]);
    try std.testing.expectEqual(@as(usize, 2), importer.copyDecoded(30, samples[0..4]));
    try std.testing.expect(importer.reset());
    for (importer.preview) |point|
        try std.testing.expectEqualDeep(PreviewPoint{}, point);
    for (importer.decoded) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);

    var too_small = DecodedImporter(8).init();
    defer too_small.deinit();
    try std.testing.expect(too_small.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&too_small);
    try std.testing.expectEqual(Failure.too_large, too_small.snapshot().failure);
    try std.testing.expectEqual(@as(usize, 0), too_small.snapshot().decoded_frames);
}

test "decoded importer reports file, allocation, and lock use in realtime scope" {
    var importer = Importer.init();
    defer importer.deinit();
    const scope = realtime_audit.Scope.enter();
    _ = importer.snapshot();
    try std.testing.expect(!importer.begin(.picker, &.{"fixture.wav"}));
    const report = scope.leave();
    try std.testing.expectEqual(realtime_audit.Operation.lock, report.first_violation.?);
    try std.testing.expectEqual(@as(u32, 1), report.count(.lock));
    try std.testing.expectEqual(@as(u32, 1), report.count(.file_access));
    try std.testing.expectEqual(@as(u32, 1), report.count(.allocation));
}

test "decoded importer normalizes PCM AIFF into the shared interleaved format" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16AiffFixture(16);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "decoded.aiff", .data = &fixture });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "decoded.aiff", &path);

    var importer = DecodedImporter(16).init();
    defer importer.deinit();
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);
    const snapshot = importer.snapshot();
    try std.testing.expectEqual(gui_file_importer.Status.ready, snapshot.import.status);
    try std.testing.expectEqual(@as(u32, 48_000), snapshot.sample_rate);
    try std.testing.expectEqual(@as(u8, 2), snapshot.channels);
    try std.testing.expectEqual(@as(usize, 16), snapshot.decoded_frames);
    var samples: [32]f32 = undefined;
    try std.testing.expectEqual(samples.len, importer.copyDecoded(0, &samples));
    try std.testing.expectEqual(samples[0], samples[1]);
    try std.testing.expect(samples[0] < 0.0);
    try std.testing.expect(samples[30] < 0.0);
}

test "audio importer bounds malformed truncated and unsupported AIFF input" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16AiffFixture(16);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "truncated.aiff", .data = fixture[0 .. fixture.len - 3] });
    var unsupported = fixture;
    writeU16Be(unsupported[26..28], 8);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "unsupported.aiff", .data = &unsupported });
    var malformed = fixture;
    @memcpy(malformed[12..16], "JUNK");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "malformed.aiff", .data = &malformed });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "oversized.aiff", .data = &fixture });

    var importer = DecodedImporter(16).init();
    defer importer.deinit();
    var path: [1024]u8 = undefined;

    var path_length = try temporary.dir.realPathFile(std.testing.io, "truncated.aiff", &path);
    try std.testing.expect(importer.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.truncated, importer.snapshot().failure);

    path_length = try temporary.dir.realPathFile(std.testing.io, "unsupported.aiff", &path);
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.unsupported_format, importer.snapshot().failure);

    path_length = try temporary.dir.realPathFile(std.testing.io, "malformed.aiff", &path);
    try std.testing.expect(importer.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.malformed, importer.snapshot().failure);

    var bounded = DecodedImporter(8).init();
    defer bounded.deinit();
    path_length = try temporary.dir.realPathFile(std.testing.io, "oversized.aiff", &path);
    try std.testing.expect(bounded.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&bounded);
    try std.testing.expectEqual(Failure.too_large, bounded.snapshot().failure);
}

test "audio importer reports malformed truncated and unsupported files" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16Fixture(32);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "truncated.wav", .data = fixture[0 .. fixture.len - 3] });
    var unsupported = fixture;
    writeU16(unsupported[20..22], 3);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "unsupported.wav", .data = &unsupported });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "malformed.wav", .data = "not a wave file" });

    var importer = Importer.init();
    defer importer.deinit();
    var path: [1024]u8 = undefined;

    var path_length = try temporary.dir.realPathFile(std.testing.io, "truncated.wav", &path);
    try std.testing.expect(importer.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.truncated, importer.snapshot().failure);
    try std.testing.expect(importer.retry());
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.truncated, importer.snapshot().failure);

    path_length = try temporary.dir.realPathFile(std.testing.io, "unsupported.wav", &path);
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(gui_file_importer.Status.unsupported_file, importer.snapshot().import.status);
    try std.testing.expectEqual(Failure.unsupported_format, importer.snapshot().failure);

    path_length = try temporary.dir.realPathFile(std.testing.io, "malformed.wav", &path);
    try std.testing.expect(importer.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(Failure.malformed, importer.snapshot().failure);
    try std.testing.expect(!importer.begin(.drop, &.{"unsupported.flac"}));
    try std.testing.expectEqual(gui_file_importer.Status.unsupported_file, importer.snapshot().import.status);
}

test "audio importer instances publish isolated previews" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = pcm16Fixture(64);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "isolated.wav", .data = &fixture });
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "isolated.wav", &path);

    var first = Importer.init();
    defer first.deinit();
    var second = Importer.init();
    defer second.deinit();
    try std.testing.expect(first.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&first);
    try std.testing.expectEqual(gui_file_importer.Status.ready, first.snapshot().import.status);
    try std.testing.expectEqual(gui_file_importer.Status.idle, second.snapshot().import.status);
    try std.testing.expectEqual(@as(usize, 0), second.snapshot().preview_points);
}

test "audio importer replaces completed media without exposing stale decoded data" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const first_fixture = pcm16Fixture(8);
    const second_fixture = pcm16Fixture(16);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "first.wav", .data = &first_fixture });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "second.wav", .data = &second_fixture });
    var first_path: [1024]u8 = undefined;
    const first_length = try temporary.dir.realPathFile(std.testing.io, "first.wav", &first_path);
    var second_path: [1024]u8 = undefined;
    const second_length = try temporary.dir.realPathFile(std.testing.io, "second.wav", &second_path);

    var importer = DecodedImporter(16).init();
    defer importer.deinit();
    try std.testing.expect(importer.begin(.picker, &.{first_path[0..first_length]}));
    waitForWorker(&importer);
    const first_generation = importer.snapshot().import.generation;
    try std.testing.expectEqual(@as(usize, 8), importer.snapshot().decoded_frames);

    try std.testing.expect(importer.begin(.drop, &.{second_path[0..second_length]}));
    const during_replacement = importer.snapshot();
    try std.testing.expect(during_replacement.import.generation > first_generation);
    try std.testing.expect(during_replacement.decoded_frames == 0 or during_replacement.decoded_frames == 16);
    waitForWorker(&importer);
    const replacement = importer.snapshot();
    try std.testing.expectEqual(gui_file_importer.Status.ready, replacement.import.status);
    try std.testing.expect(replacement.import.generation > first_generation);
    try std.testing.expectEqual(@as(usize, 16), replacement.decoded_frames);
}

test "audio importer acknowledges cancellation before teardown joins the worker" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const frame_count = 2 * 1024 * 1024;
    var header = pcm16Fixture(0);
    writeU32(header[4..8], 36 + frame_count * 4);
    writeU32(header[40..44], frame_count * 4);
    var file = try temporary.dir.createFile(std.testing.io, "cancel.wav", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, &header);
    const frames = pcm16Fixture(1024);
    var written: usize = 0;
    while (written < frame_count) : (written += 1024) {
        try file.writeStreamingAll(std.testing.io, frames[44..]);
    }
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "cancel.wav", &path);

    var importer = Importer.init();
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    try std.testing.expect(importer.requestCancel());
    importer.deinit();
    try std.testing.expectEqual(gui_file_importer.Status.cancelled, importer.snapshot().import.status);
    try std.testing.expectEqual(Failure.cancelled, importer.snapshot().failure);
}

test "audio importer copy accessors reject malformed direct counts" {
    var importer = DecodedImporter(4).init();
    defer importer.deinit();
    var preview: [preview_capacity + 1]PreviewPoint = undefined;
    var decoded: [maximum_channels * 4]f32 = undefined;

    importer.preview_points = preview_capacity + 1;
    try std.testing.expectEqual(@as(usize, 0), importer.copyPreview(&preview));

    importer.decoded_frames = 5;
    importer.channels = 2;
    try std.testing.expectEqual(@as(usize, 0), importer.copyDecoded(0, &decoded));
    importer.decoded_frames = 4;
    importer.channels = maximum_channels + 1;
    try std.testing.expectEqual(@as(usize, 0), importer.copyDecoded(0, &decoded));
    importer.channels = 0;
    try std.testing.expectEqual(@as(usize, 0), importer.copyDecoded(0, &decoded));

    importer.preview_points = 1;
    importer.preview[0] = .{ .x = std.math.nan(f64), .y = 0.5 };
    preview[0] = .{ .x = 9.0, .y = 9.0 };
    try std.testing.expectEqual(@as(usize, 0), importer.copyPreview(&preview));
    try std.testing.expectEqual(@as(f64, 9.0), preview[0].x);
    try std.testing.expectEqual(@as(f64, 9.0), preview[0].y);

    importer.decoded_frames = 1;
    importer.channels = 1;
    importer.decoded[0] = std.math.inf(f32);
    decoded[0] = 9.0;
    try std.testing.expectEqual(@as(usize, 0), importer.copyDecoded(0, &decoded));
    try std.testing.expectEqual(@as(f32, 9.0), decoded[0]);

    importer.preview[0] = .{ .x = 0.25, .y = 0.5 };
    importer.decoded[0] = 0.75;
    try std.testing.expectEqual(@as(usize, 1), importer.copyPreview(&preview));
    try std.testing.expectEqual(@as(usize, 1), importer.copyDecoded(0, &decoded));
}

fn generatedAudioResultIsBounded(info: AudioInfo, file_size: usize) bool {
    const sample_bytes = info.bits_per_sample / 8;
    return info.data_offset <= file_size and
        info.data_bytes <= file_size - @as(usize, @intCast(info.data_offset)) and
        info.sample_rate >= 8_000 and info.sample_rate <= 384_000 and
        info.channels > 0 and info.channels <= maximum_channels and
        (info.bits_per_sample == 16 or info.bits_per_sample == 24 or info.bits_per_sample == 32) and
        info.block_align == info.channels * sample_bytes and
        info.sample_frames > 0 and info.sample_frames <= maximum_sample_frames and
        info.data_bytes == info.sample_frames * info.block_align;
}

fn parseGeneratedAudio(dir: *std.Io.Dir, bytes: []const u8) !?AudioInfo {
    const io = std.testing.io;
    try dir.writeFile(io, .{ .sub_path = "generated-audio.bin", .data = bytes });
    const file = try dir.openFile(io, "generated-audio.bin", .{});
    defer file.close(io);
    return parseAudio(io, file, bytes.len) catch |err| switch (err) {
        error.Truncated, error.Malformed, error.UnsupportedFormat, error.TooLarge => null,
        else => return err,
    };
}

test "audio parser bounds deterministic generated RIFF FORM and arbitrary inputs" {
    const seed = 0xa110_f11e_2026_0720;
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var bytes: [512]u8 = undefined;

    for (0..512) |case_index| {
        const length = random.uintLessThan(usize, bytes.len + 1);
        random.bytes(bytes[0..length]);
        if (length >= 12) switch (case_index % 4) {
            0 => {
                @memcpy(bytes[0..4], "RIFF");
                @memcpy(bytes[8..12], "WAVE");
            },
            1 => {
                @memcpy(bytes[0..4], "FORM");
                @memcpy(bytes[8..12], "AIFF");
            },
            2 => {
                @memcpy(bytes[0..4], "FORM");
                @memcpy(bytes[8..12], "AIFC");
            },
            else => {},
        };
        const info = parseGeneratedAudio(&temporary.dir, bytes[0..length]) catch |err| {
            std.debug.print("generated audio seed={x} case={} error={s}\n", .{ seed, case_index, @errorName(err) });
            return err;
        };
        if (info) |parsed| {
            if (!generatedAudioResultIsBounded(parsed, length)) {
                std.debug.print("generated audio seed={x} case={} returned unbounded metadata\n", .{ seed, case_index });
                return error.UnboundedGeneratedAudioMetadata;
            }
        }
    }
}

test "audio parser rejects every strict prefix of valid WAV and AIFF" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const wav = pcm16Fixture(32);
    const aiff = pcm16AiffFixture(32);

    for (1..wav.len) |length| {
        try std.testing.expectEqual(@as(?AudioInfo, null), try parseGeneratedAudio(&temporary.dir, wav[0..length]));
    }
    for (1..aiff.len) |length| {
        try std.testing.expectEqual(@as(?AudioInfo, null), try parseGeneratedAudio(&temporary.dir, aiff[0..length]));
    }
    try std.testing.expect(generatedAudioResultIsBounded((try parseGeneratedAudio(&temporary.dir, &wav)).?, wav.len));
    try std.testing.expect(generatedAudioResultIsBounded((try parseGeneratedAudio(&temporary.dir, &aiff)).?, aiff.len));
}
