const std = @import("std");
const gui_file_importer = @import("gui_file_importer.zig");

pub const preview_capacity = 256;
pub const maximum_input_bytes = 32 * 1024 * 1024;
pub const maximum_sample_frames = 8 * 1024 * 1024;
pub const maximum_channels = 2;

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
    x: f64,
    y: f64,
};

pub const Snapshot = struct {
    import: gui_file_importer.Snapshot,
    failure: Failure,
    sample_rate: u32,
    channels: u8,
    sample_frames: u64,
    preview_points: usize,
    decoded_frames: usize,
};

const WavInfo = struct {
    data_offset: u64,
    data_bytes: usize,
    sample_rate: u32,
    channels: u8,
    bits_per_sample: u8,
    block_align: u8,
    sample_frames: usize,
};

pub fn DecodedImporter(comptime decoded_frame_capacity: usize) type {
    if (decoded_frame_capacity > maximum_sample_frames) {
        @compileError("DecodedImporter capacity exceeds the WAV frame limit");
    }
    return struct {
        const Model = gui_file_importer.Model(1, 1);
        const Self = @This();

        mutex: std.Io.Mutex = .init,
        model: Model,
        failure: Failure = .none,
        sample_rate: u32 = 0,
        channels: u8 = 0,
        sample_frames: u64 = 0,
        preview: [preview_capacity]PreviewPoint = undefined,
        preview_points: usize = 0,
        decoded: [decoded_frame_capacity * maximum_channels]f32 = @splat(0.0),
        decoded_frames: usize = 0,
        thread: ?std.Thread = null,
        worker_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub fn init() Self {
            return .{ .model = Model.init(&.{".wav"}) catch unreachable };
        }

        pub fn deinit(self: *Self) void {
            self.lock();
            if (self.model.snapshot().canCancel()) self.model.requestCancel() catch {};
            self.unlock();
            self.joinWorker();
        }

        pub fn begin(self: *Self, entry_point: gui_file_importer.EntryPoint, paths: []const []const u8) bool {
            if (self.worker_running.load(.acquire)) return false;
            self.reapWorker();

            self.lock();
            const status = self.model.begin(entry_point, paths);
            self.failure = .none;
            self.sample_rate = 0;
            self.channels = 0;
            self.sample_frames = 0;
            self.preview_points = 0;
            self.decoded_frames = 0;
            self.unlock();
            if (status != .validating) return false;
            return self.spawnWorker();
        }

        pub fn retry(self: *Self) bool {
            if (self.worker_running.load(.acquire)) return false;
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
            defer self.unlock();
            self.model.requestCancel() catch return false;
            return true;
        }

        pub fn reset(self: *Self) bool {
            if (self.worker_running.load(.acquire)) return false;
            self.reapWorker();
            self.lock();
            defer self.unlock();
            self.model.reset();
            self.failure = .none;
            self.sample_rate = 0;
            self.channels = 0;
            self.sample_frames = 0;
            self.preview_points = 0;
            self.decoded_frames = 0;
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
            const count = @min(output.len, self.preview_points);
            @memcpy(output[0..count], self.preview[0..count]);
            return count;
        }

        pub fn copyDecoded(self: *Self, sample_offset: usize, output: []f32) usize {
            self.lock();
            defer self.unlock();
            const sample_count = self.decoded_frames * self.channels;
            if (sample_offset >= sample_count) return 0;
            const count = @min(output.len, sample_count - sample_offset);
            @memcpy(output[0..count], self.decoded[sample_offset .. sample_offset + count]);
            return count;
        }

        fn spawnWorker(self: *Self) bool {
            self.worker_running.store(true, .release);
            self.thread = std.Thread.spawn(.{}, run, .{self}) catch {
                self.worker_running.store(false, .release);
                self.finishFailure(.worker_unavailable);
                return false;
            };
            return true;
        }

        fn run(self: *Self) void {
            defer self.worker_running.store(false, .release);
            var path_storage: [1024]u8 = undefined;
            self.lock();
            const path = self.model.path(0) orelse {
                self.unlock();
                self.finishFailure(.malformed);
                return;
            };
            @memcpy(path_storage[0..path.len], path);
            const path_length = path.len;
            self.unlock();
            self.decode(path_storage[0..path_length]);
        }

        fn decode(self: *Self, path: []const u8) void {
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
            const info = parseWav(io, file, file_size) catch |err| {
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
                if (self.model.cancellationRequested()) {
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
                        const sample = decodePcm(buffer[start .. start + sample_bytes], info.bits_per_sample);
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
            const status: gui_file_importer.Status = switch (failure) {
                .too_large => .capacity_limit,
                .unsupported_format => .unsupported_file,
                .cancelled => .cancelled,
                else => .failed,
            };
            self.model.finishWith(status) catch {};
        }

        fn reapWorker(self: *Self) void {
            if (self.worker_running.load(.acquire)) return;
            self.joinWorker();
        }

        fn joinWorker(self: *Self) void {
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
        }

        fn lock(self: *Self) void {
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        }

        fn unlock(self: *Self) void {
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    };
}

pub const Importer = DecodedImporter(0);

fn parseWav(io: std.Io, file: std.Io.File, file_size: u64) !WavInfo {
    if (file_size < 12) return error.Truncated;
    var header: [12]u8 = undefined;
    if (try file.readPositionalAll(io, &header, 0) != header.len) return error.Truncated;
    if (!std.mem.eql(u8, header[0..4], "RIFF") or !std.mem.eql(u8, header[8..12], "WAVE")) {
        return error.Malformed;
    }
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
                sample_rate < 8_000 or sample_rate > 384_000) return error.UnsupportedFormat;
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
    };
}

fn decodePcm(bytes: []const u8, bits_per_sample: u8) f64 {
    return switch (bits_per_sample) {
        16 => @as(f64, @floatFromInt(@as(i16, @bitCast(readU16(bytes[0..2]))))) / 32768.0,
        24 => blk: {
            var value = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16);
            if (value & 0x0080_0000 != 0) value |= 0xff00_0000;
            break :blk @as(f64, @floatFromInt(@as(i32, @bitCast(value)))) / 8_388_608.0;
        },
        32 => @as(f64, @floatFromInt(@as(i32, @bitCast(readU32(bytes[0..4]))))) / 2_147_483_648.0,
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

fn waitForWorker(importer: anytype) void {
    while (importer.worker_running.load(.acquire)) std.Thread.yield() catch {};
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
    try std.testing.expect(importer.begin(.picker, &.{path[0..path_length]}));
    waitForWorker(&importer);
    try std.testing.expectEqual(@as(usize, 16), importer.snapshot().decoded_frames);
    var samples: [32]f32 = undefined;
    try std.testing.expectEqual(samples.len, importer.copyDecoded(0, &samples));
    try std.testing.expectEqual(samples[0], samples[1]);
    try std.testing.expectEqual(samples[30], samples[31]);
    try std.testing.expectEqual(@as(usize, 2), importer.copyDecoded(30, samples[0..4]));

    var too_small = DecodedImporter(8).init();
    defer too_small.deinit();
    try std.testing.expect(too_small.begin(.drop, &.{path[0..path_length]}));
    waitForWorker(&too_small);
    try std.testing.expectEqual(Failure.too_large, too_small.snapshot().failure);
    try std.testing.expectEqual(@as(usize, 0), too_small.snapshot().decoded_frames);
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
    try std.testing.expect(!importer.begin(.drop, &.{"unsupported.aiff"}));
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
