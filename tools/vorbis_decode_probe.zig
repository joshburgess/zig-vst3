const plug = @import("zig-vst3-plugin");
const std = @import("std");

const maximum_peak_error = 0.05;
const maximum_normalized_rms_error = 0.02;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2 and args.len != 3 and args.len != 4)
        return error.InvalidArguments;
    const require_midpoint_seek = args.len == 3;
    if (require_midpoint_seek and
        !std.mem.eql(
            u8,
            args[2],
            "--require-midpoint-seek",
        ))
    {
        return error.InvalidArguments;
    }
    const compare_reference = args.len == 4;
    const reference_encoding: ReferenceEncoding = if (compare_reference)
        if (std.mem.eql(u8, args[2], "--reference-f32le"))
            .f32le
        else if (std.mem.eql(u8, args[2], "--reference-s16le"))
            .s16le
        else
            return error.InvalidArguments
    else
        .f32le;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    const reference = if (compare_reference)
        ReferencePcm{
            .bytes = try std.Io.Dir.cwd().readFileAlloc(
                init.io,
                args[3],
                allocator,
                .limited(64 * 1024 * 1024),
            ),
            .encoding = reference_encoding,
        }
    else
        null;
    const seek_point_count =
        try plug.dsp.requiredVorbisSeekPoints(encoded);
    const seek_storage = try allocator.alloc(
        plug.dsp.VorbisSeekPoint,
        seek_point_count,
    );
    const seek_index = try plug.dsp.buildVorbisSeekIndex(
        encoded,
        seek_storage,
    );
    const file = try std.Io.Dir.cwd().openFile(
        init.io,
        args[1],
        .{},
    );
    defer file.close(init.io);
    const page_storage = try allocator.alloc(
        u8,
        plug.dsp.maximum_ogg_page_bytes,
    );
    const file_seek_storage = try allocator.alloc(
        plug.dsp.VorbisSeekPoint,
        seek_point_count,
    );
    const file_seek_index = try plug.dsp.buildVorbisFileSeekIndex(
        init.io,
        file,
        page_storage,
        file_seek_storage,
    );
    if (seek_index.len != file_seek_index.len)
        return error.VorbisMemoryAndFileSeekIndexesDiffer;
    for (seek_index, file_seek_index) |memory_point, file_point| {
        if (!std.meta.eql(memory_point, file_point))
            return error.VorbisMemoryAndFileSeekIndexesDiffer;
    }

    const packet_storage = try allocator.alloc(u8, 4 * 1024 * 1024);
    const file_packet_storage =
        try allocator.alloc(u8, 4 * 1024 * 1024);
    var packets = plug.dsp.OggPacketIterator.initChained(
        encoded,
        packet_storage,
    );

    const first_identification_packet =
        try packets.next() orelse return error.MissingIdentification;
    const identification = try plug.dsp.VorbisIdentification.parse(
        first_identification_packet.bytes,
    );

    if (identification.small_block_size == 64 and
        identification.large_block_size == 64)
    {
        switch (identification.channel_count) {
            1 => try decodeStreams(
                1,
                64,
                64,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            else => return error.UnsupportedVorbisChannelCount,
        }
    } else if (identification.small_block_size == 512 and
        identification.large_block_size == 512)
    {
        switch (identification.channel_count) {
            1 => try decodeStreams(
                1,
                512,
                512,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            2 => try decodeStreams(
                2,
                512,
                512,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            else => return error.UnsupportedVorbisChannelCount,
        }
    } else if (identification.small_block_size == 512 and
        identification.large_block_size == 1_024)
    {
        switch (identification.channel_count) {
            1 => try decodeStreams(
                1,
                512,
                1_024,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            2 => try decodeStreams(
                2,
                512,
                1_024,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            else => return error.UnsupportedVorbisChannelCount,
        }
    } else if (identification.small_block_size == 512 and
        identification.large_block_size == 4_096)
    {
        switch (identification.channel_count) {
            1 => try decodeStreams(
                1,
                512,
                4_096,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            2 => try decodeStreams(
                2,
                512,
                4_096,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            else => return error.UnsupportedVorbisChannelCount,
        }
    } else if (identification.small_block_size == 256 and
        identification.large_block_size == 2_048)
    {
        switch (identification.channel_count) {
            1 => try decodeStreams(
                1,
                256,
                2_048,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            2 => try decodeStreams(
                2,
                256,
                2_048,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            6 => try decodeStreams(
                6,
                256,
                2_048,
                allocator,
                init.io,
                file,
                &packets,
                seek_index,
                page_storage,
                file_packet_storage,
                first_identification_packet,
                require_midpoint_seek,
                reference,
            ),
            else => return error.UnsupportedVorbisChannelCount,
        }
    } else {
        return error.UnexpectedVorbisGeometry;
    }
}

fn decodeStreams(
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    packets: *plug.dsp.OggPacketIterator,
    seek_index: []const plug.dsp.VorbisSeekPoint,
    page_storage: []u8,
    file_packet_storage: []u8,
    first_identification_packet: plug.dsp.OggPacket,
    require_midpoint_seek: bool,
    reference: ?ReferencePcm,
) !void {
    var decoder = plug.dsp.VorbisChainedPcmStreamDecoder(
        f32,
        channel_count,
        small_block_size,
        large_block_size,
    ).init();
    var spectra: [channel_count * large_block_size / 2]f32 = undefined;
    var floors: [channel_count * large_block_size / 2]f32 = undefined;
    var coupling: [channel_count * large_block_size / 2]f32 = undefined;
    var time: [channel_count * large_block_size]f32 = undefined;
    var classifications: [large_block_size * channel_count]u8 =
        undefined;
    var windowed: [channel_count * large_block_size]f32 = undefined;
    var output_storage: [channel_count][large_block_size]f32 = undefined;
    var outputs: [channel_count][]f32 = undefined;
    for (&outputs, &output_storage) |*output, *storage|
        output.* = storage;
    const scratch = plug.dsp.VorbisPcmStreamScratch(f32){
        .packet = .{
            .spectra = &spectra,
            .floor_curves = &floors,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
        .windowed = &windowed,
    };

    var next_identification_packet: ?plug.dsp.OggPacket = first_identification_packet;
    var logical_stream_count: u32 = 0;
    var audio_packets: usize = 0;
    var sample_count: u64 = 0;
    var energy: f64 = 0.0;
    var comparison = ReferenceComparison.init(reference, true);
    while (next_identification_packet) |identification_packet| {
        if (!identification_packet.beginning)
            return error.MissingVorbisBeginningOfStream;
        const logical_stream_index =
            identification_packet.logical_stream_index;
        if (logical_stream_index != logical_stream_count)
            return error.UnexpectedVorbisLogicalStreamIndex;
        const identification =
            try plug.dsp.VorbisIdentification.parse(
                identification_packet.bytes,
            );
        if (identification.channel_count != channel_count or
            identification.small_block_size != small_block_size or
            identification.large_block_size != large_block_size)
        {
            return error.VorbisChainedGeometryChanged;
        }

        const comment_packet =
            try packets.next() orelse return error.MissingComments;
        try requireLogicalStream(comment_packet, logical_stream_index);
        var comments = try plug.dsp.VorbisCommentIterator.init(
            comment_packet.bytes,
        );
        while (try comments.next()) |_| {}

        const setup_packet =
            try packets.next() orelse return error.MissingSetup;
        try requireLogicalStream(setup_packet, logical_stream_index);
        const setup = try parseSetup(
            allocator,
            setup_packet.bytes,
            identification.channel_count,
        );
        try decoder.beginLogicalStream(identification);
        const seek_target = try logicalStreamSeekTarget(
            seek_index,
            logical_stream_index,
            require_midpoint_seek,
        );
        var sequential_seek =
            plug.dsp.VorbisPcmSeekCursor.init(seek_target);
        var sequential_digest = PcmDigest.init();

        var stream_audio_packets: usize = 0;
        while (true) {
            const packet =
                try packets.next() orelse
                return error.MissingVorbisEndOfStream;
            try requireLogicalStream(packet, logical_stream_index);
            const decoded = try decoder.decode(
                packet,
                identification,
                setup,
                &outputs,
                scratch,
            );
            if (decoded.stream.packet.floor_truncated)
                return error.TruncatedVorbisFloorPacket;
            if (decoded.global_pcm_start != sample_count)
                return error.DiscontinuousVorbisPcmPosition;
            const selected = try selectSeekSuffix(
                &sequential_seek,
                decoded.stream,
            );
            sequential_digest.update(
                outputs,
                selected.source_start,
                selected.sample_count,
            );
            stream_audio_packets += 1;
            audio_packets += 1;
            const expected_end = std.math.add(
                u64,
                sample_count,
                @intCast(decoded.stream.sample_count),
            ) catch return error.VorbisPcmPositionOverflow;
            if (decoded.global_pcm_end != expected_end)
                return error.DiscontinuousVorbisPcmPosition;
            sample_count = expected_end;
            for (outputs) |output| {
                for (output[0..decoded.stream.sample_count]) |sample|
                    energy += @as(f64, sample) * sample;
            }
            try comparison.update(
                outputs,
                decoded.stream.sample_count,
            );
            if (packet.end) break;
        }
        if (stream_audio_packets == 0)
            return error.EmptyVorbisLogicalStream;
        if (!sequential_seek.reached or
            sequential_digest.sample_count == 0)
        {
            return error.VorbisSeekTargetNotReached;
        }
        try validateSeekParity(
            channel_count,
            small_block_size,
            large_block_size,
            io,
            file,
            page_storage,
            file_packet_storage,
            seek_index,
            logical_stream_index,
            seek_target,
            identification,
            setup,
            sequential_digest.result(),
        );
        logical_stream_count = std.math.add(
            u32,
            logical_stream_count,
            1,
        ) catch return error.VorbisLogicalStreamIndexOverflow;
        next_identification_packet = try packets.next();
    }
    if (!decoder.stream.ended) return error.MissingVorbisEndOfStream;
    if (logical_stream_count == 0 or
        audio_packets == 0 or
        sample_count == 0)
    {
        return error.EmptyVorbisStream;
    }
    if (!std.math.isFinite(energy) or energy <= 0.0)
        return error.SilentVorbisStream;
    try comparison.finish();
}

const ReferenceEncoding = enum {
    f32le,
    s16le,

    fn sampleSize(self: ReferenceEncoding) usize {
        return switch (self) {
            .f32le => @sizeOf(f32),
            .s16le => @sizeOf(i16),
        };
    }
};

const ReferencePcm = struct {
    bytes: []const u8,
    encoding: ReferenceEncoding,
};

const ReferenceComparison = struct {
    reference: ?ReferencePcm,
    report: bool,
    offset: usize = 0,
    project_values: u64 = 0,
    sample_values: u64 = 0,
    reference_energy: f64 = 0,
    project_energy: f64 = 0,
    cross_energy: f64 = 0,
    error_energy: f64 = 0,
    peak_error: f64 = 0,
    peak_index: u64 = 0,
    peak_project: f64 = 0,
    peak_reference: f64 = 0,

    fn init(
        reference: ?ReferencePcm,
        report: bool,
    ) ReferenceComparison {
        return .{ .reference = reference, .report = report };
    }

    fn update(
        self: *ReferenceComparison,
        outputs: anytype,
        sample_count: usize,
    ) !void {
        const reference = self.reference orelse return;
        const sample_size = reference.encoding.sampleSize();
        for (0..sample_count) |sample_index| {
            for (outputs) |output| {
                self.project_values = std.math.add(
                    u64,
                    self.project_values,
                    1,
                ) catch return error.VorbisPcmReferenceSizeOverflow;
                if (self.offset + sample_size > reference.bytes.len) {
                    continue;
                }
                const reference_sample = switch (reference.encoding) {
                    .f32le => @as(f64, @floatCast(@as(f32, @bitCast(
                        std.mem.readInt(
                            u32,
                            reference.bytes[self.offset..][0..4],
                            .little,
                        ),
                    )))),
                    .s16le => @as(f64, @floatFromInt(@as(i16, @bitCast(
                        std.mem.readInt(
                            u16,
                            reference.bytes[self.offset..][0..2],
                            .little,
                        ),
                    )))) / 32_768.0,
                };
                self.offset += sample_size;
                const project_sample = output[sample_index];
                if (!std.math.isFinite(project_sample) or
                    !std.math.isFinite(reference_sample))
                {
                    return error.NonFiniteVorbisPcmReference;
                }
                const difference = @as(f64, project_sample) -
                    reference_sample;
                const absolute_difference = @abs(difference);
                self.reference_energy +=
                    reference_sample * reference_sample;
                self.project_energy +=
                    @as(f64, project_sample) * project_sample;
                self.cross_energy +=
                    @as(f64, project_sample) * reference_sample;
                self.error_energy += difference * difference;
                if (absolute_difference > self.peak_error) {
                    self.peak_error = absolute_difference;
                    self.peak_index = self.sample_values;
                    self.peak_project = project_sample;
                    self.peak_reference = reference_sample;
                }
                self.sample_values = std.math.add(
                    u64,
                    self.sample_values,
                    1,
                ) catch return error.VorbisPcmReferenceSizeOverflow;
            }
        }
    }

    fn finish(self: ReferenceComparison) !void {
        const reference = self.reference orelse return;
        const sample_size = reference.encoding.sampleSize();
        if (reference.bytes.len % sample_size != 0)
            return error.VorbisPcmReferenceSampleCountMismatch;
        const reference_values = reference.bytes.len / sample_size;
        if (self.project_values != reference_values) {
            if (self.report) {
                std.debug.print(
                    "Vorbis PCM reference sample-count mismatch project={d} reference={d}\n",
                    .{ self.project_values, reference_values },
                );
            }
            return error.VorbisPcmReferenceSampleCountMismatch;
        }
        if (self.sample_values == 0 or self.reference_energy <= 0)
            return error.SilentVorbisPcmReference;
        const divisor: f64 = @floatFromInt(self.sample_values);
        const error_rms = @sqrt(self.error_energy / divisor);
        const reference_rms = @sqrt(self.reference_energy / divisor);
        const normalized_rms_error = error_rms / reference_rms;
        const optimal_project_gain = if (self.project_energy > 0)
            self.cross_energy / self.project_energy
        else
            0;
        const aligned_error_energy = @max(
            0,
            self.reference_energy -
                self.cross_energy * self.cross_energy /
                    @max(self.project_energy, std.math.floatMin(f64)),
        );
        const gain_aligned_normalized_rms =
            @sqrt(aligned_error_energy / divisor) / reference_rms;
        if (self.report) {
            std.debug.print(
                "Vorbis PCM reference samples={d} peak_error={d:.9} peak_index={d} project_at_peak={d:.9} reference_at_peak={d:.9} rms_error={d:.9} normalized_rms_error={d:.9} optimal_project_gain={d:.9} gain_aligned_normalized_rms={d:.9}\n",
                .{
                    self.sample_values,
                    self.peak_error,
                    self.peak_index,
                    self.peak_project,
                    self.peak_reference,
                    error_rms,
                    normalized_rms_error,
                    optimal_project_gain,
                    gain_aligned_normalized_rms,
                },
            );
        }
        if (self.peak_error > maximum_peak_error)
            return error.VorbisPcmReferencePeakErrorExceeded;
        if (normalized_rms_error > maximum_normalized_rms_error)
            return error.VorbisPcmReferenceRmsErrorExceeded;
    }
};

test "Vorbis PCM reference comparison accepts exact interleaved samples" {
    const samples = [_]f32{ 0.25, -0.5 };
    var reference: [samples.len * @sizeOf(f32)]u8 = undefined;
    for (samples, 0..) |sample, index| {
        std.mem.writeInt(
            u32,
            reference[index * @sizeOf(f32) ..][0..4],
            @bitCast(sample),
            .little,
        );
    }
    var output_storage = samples;
    const outputs = [_][]f32{&output_storage};
    var comparison = ReferenceComparison.init(.{
        .bytes = &reference,
        .encoding = .f32le,
    }, false);
    try comparison.update(outputs, samples.len);
    try comparison.finish();
}

test "Vorbis PCM reference comparison rejects size and finite-value mismatches" {
    const reference_sample: f32 = 0.5;
    var reference: [@sizeOf(f32)]u8 = undefined;
    std.mem.writeInt(
        u32,
        &reference,
        @bitCast(reference_sample),
        .little,
    );
    var two_samples = [_]f32{ 0.5, 0.5 };
    const oversized_outputs = [_][]f32{&two_samples};
    var oversized = ReferenceComparison.init(.{
        .bytes = &reference,
        .encoding = .f32le,
    }, false);
    try oversized.update(oversized_outputs, two_samples.len);
    try std.testing.expectError(
        error.VorbisPcmReferenceSampleCountMismatch,
        oversized.finish(),
    );

    var nonfinite_sample = [_]f32{std.math.nan(f32)};
    const nonfinite_outputs = [_][]f32{&nonfinite_sample};
    var nonfinite = ReferenceComparison.init(.{
        .bytes = &reference,
        .encoding = .f32le,
    }, false);
    try std.testing.expectError(
        error.NonFiniteVorbisPcmReference,
        nonfinite.update(nonfinite_outputs, 1),
    );
}

test "Vorbis PCM reference comparison accepts signed 16-bit samples" {
    const samples = [_]i16{ 8_192, -16_384 };
    var reference: [samples.len * @sizeOf(i16)]u8 = undefined;
    for (samples, 0..) |sample, index| {
        std.mem.writeInt(
            i16,
            reference[index * @sizeOf(i16) ..][0..2],
            sample,
            .little,
        );
    }
    var output_storage = [_]f32{ 0.25, -0.5 };
    const outputs = [_][]f32{&output_storage};
    var comparison = ReferenceComparison.init(.{
        .bytes = &reference,
        .encoding = .s16le,
    }, false);
    try comparison.update(outputs, output_storage.len);
    try comparison.finish();

    var malformed = ReferenceComparison.init(.{
        .bytes = reference[0 .. reference.len - 1],
        .encoding = .s16le,
    }, false);
    try std.testing.expectError(
        error.VorbisPcmReferenceSampleCountMismatch,
        malformed.finish(),
    );
}

const PcmDigest = struct {
    hasher: std.hash.Wyhash,
    sample_count: u64 = 0,

    const Result = struct {
        hash: u64,
        sample_count: u64,
    };

    fn init() PcmDigest {
        return .{ .hasher = std.hash.Wyhash.init(0) };
    }

    fn update(
        self: *PcmDigest,
        outputs: anytype,
        source_start: usize,
        sample_count: usize,
    ) void {
        for (0..sample_count) |sample_index| {
            for (outputs) |output| {
                const bits: u32 =
                    @bitCast(output[source_start + sample_index]);
                self.hasher.update(std.mem.asBytes(&bits));
            }
        }
        self.sample_count += @intCast(sample_count);
    }

    fn result(self: *PcmDigest) Result {
        return .{
            .hash = self.hasher.final(),
            .sample_count = self.sample_count,
        };
    }
};

fn logicalStreamSeekTarget(
    seek_index: []const plug.dsp.VorbisSeekPoint,
    logical_stream_index: u32,
    require_midpoint: bool,
) !i64 {
    var first_pcm_end: ?i64 = null;
    var pcm_end: ?i64 = null;
    for (seek_index) |point| {
        if (point.packet.logical_stream_index ==
            logical_stream_index)
        {
            if (first_pcm_end == null)
                first_pcm_end = point.pcm_end;
            pcm_end = point.pcm_end;
        }
    }
    const end = pcm_end orelse
        return error.VorbisSeekLogicalStreamNotFound;
    if (end < 2) return error.VorbisStreamTooShortToSeek;
    const midpoint = @divTrunc(end, 2);
    for (seek_index) |point| {
        if (point.packet.logical_stream_index ==
            logical_stream_index and
            point.pcm_end <= midpoint)
        {
            return midpoint;
        }
    }
    if (require_midpoint)
        return error.VorbisMidpointSeekUnavailable;
    const first_end = first_pcm_end orelse
        return error.VorbisSeekLogicalStreamNotFound;
    if (first_end < 1) return error.VorbisStreamTooShortToSeek;
    return first_end - 1;
}

fn validateSeekParity(
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    packet_storage: []u8,
    seek_index: []const plug.dsp.VorbisSeekPoint,
    logical_stream_index: u32,
    seek_target: i64,
    identification: plug.dsp.VorbisIdentification,
    setup: plug.dsp.VorbisSetup,
    expected: PcmDigest.Result,
) !void {
    const seek_point = try plug.dsp.findVorbisSeekPoint(
        seek_index,
        logical_stream_index,
        seek_target,
    );
    var packets = try plug.dsp.OggFilePacketReader.initChained(
        io,
        file,
    );
    try packets.seek(seek_point);
    var decoder = plug.dsp.VorbisPcmStreamDecoder(
        f32,
        channel_count,
        small_block_size,
        large_block_size,
    ).init();
    var spectra: [channel_count * large_block_size / 2]f32 =
        undefined;
    var floors: [channel_count * large_block_size / 2]f32 =
        undefined;
    var coupling: [channel_count * large_block_size / 2]f32 =
        undefined;
    var time: [channel_count * large_block_size]f32 = undefined;
    var classifications: [large_block_size * channel_count]u8 =
        undefined;
    var windowed: [channel_count * large_block_size]f32 = undefined;
    var output_storage: [channel_count][large_block_size]f32 =
        undefined;
    var outputs: [channel_count][]f32 = undefined;
    for (&outputs, &output_storage) |*output, *storage|
        output.* = storage;
    const scratch = plug.dsp.VorbisPcmStreamScratch(f32){
        .packet = .{
            .spectra = &spectra,
            .floor_curves = &floors,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
        .windowed = &windowed,
    };
    var cursor = plug.dsp.VorbisPcmSeekCursor.init(seek_target);
    var digest = PcmDigest.init();
    var ended = false;
    var unpositioned_frames: u64 = 0;
    var first_positioned_pcm: ?i64 = null;
    var final_positioned_pcm: ?i64 = null;
    while (try packets.next(
        page_storage,
        packet_storage,
    )) |packet| {
        try requireLogicalStream(packet, logical_stream_index);
        const decoded = try decoder.decode(
            packet,
            identification,
            setup,
            &outputs,
            scratch,
        );
        if (decoded.packet.floor_truncated)
            return error.TruncatedVorbisFloorPacket;
        if (decoded.sample_count != 0 and
            (decoded.pcm_start == null or decoded.pcm_end == null))
        {
            unpositioned_frames += @intCast(decoded.sample_count);
        } else if (decoded.sample_count != 0) {
            if (first_positioned_pcm == null)
                first_positioned_pcm = decoded.pcm_start;
            final_positioned_pcm = decoded.pcm_end;
        }
        const selected = try selectSeekSuffix(&cursor, decoded);
        digest.update(
            outputs,
            selected.source_start,
            selected.sample_count,
        );
        if (packet.end) {
            ended = true;
            break;
        }
    }
    if (!ended) return error.MissingVorbisEndOfStream;
    if (!cursor.reached) return error.VorbisSeekTargetNotReached;
    const actual = digest.result();
    if (!std.meta.eql(expected, actual)) {
        std.debug.print(
            "Vorbis seek mismatch: stream={d} target={d} point_end={d} decode_page={d} decode_packet={d} expected_frames={d} expected_hash={x} actual_frames={d} actual_hash={x} unpositioned_frames={d} positioned_start={?d} positioned_end={?d}\n",
            .{
                logical_stream_index,
                seek_target,
                seek_point.pcm_end,
                seek_point.decode.sequence_number,
                seek_point.decode.logical_packet_index,
                expected.sample_count,
                expected.hash,
                actual.sample_count,
                actual.hash,
                unpositioned_frames,
                first_positioned_pcm,
                final_positioned_pcm,
            },
        );
        return error.VorbisSeekPcmMismatch;
    }
}

fn selectSeekSuffix(
    cursor: *plug.dsp.VorbisPcmSeekCursor,
    decoded: plug.dsp.VorbisPcmStreamResult,
) !plug.dsp.VorbisGranuleRange {
    if (decoded.sample_count != 0 and
        (decoded.pcm_start == null or decoded.pcm_end == null))
    {
        if (cursor.reached)
            return error.VorbisPcmSeekPositionUnavailable;
        return .{
            .source_start = 0,
            .sample_count = 0,
            .pcm_start = null,
            .pcm_end = null,
        };
    }
    return cursor.select(decoded);
}

fn requireLogicalStream(
    packet: plug.dsp.OggPacket,
    logical_stream_index: u32,
) !void {
    if (packet.logical_stream_index != logical_stream_index)
        return error.TruncatedVorbisLogicalStream;
}

test "Vorbis seek targets require an indexed midpoint or use a positioned tail" {
    const fixture = struct {
        fn point(
            logical_stream_index: u32,
            pcm_end: i64,
        ) plug.dsp.VorbisSeekPoint {
            const location = plug.dsp.VorbisPacketLocation{
                .byte_offset = 0,
                .serial_number = logical_stream_index + 1,
                .sequence_number = 0,
                .logical_stream_index = logical_stream_index,
                .logical_packet_index = 3,
                .completed_packets_before = 0,
                .continued = false,
            };
            return .{
                .pcm_end = pcm_end,
                .decode = location,
                .packet = location,
            };
        }
    };

    const single = [_]plug.dsp.VorbisSeekPoint{
        fixture.point(0, 100),
    };
    try std.testing.expectEqual(
        @as(i64, 99),
        try logicalStreamSeekTarget(&single, 0, false),
    );
    try std.testing.expectError(
        error.VorbisMidpointSeekUnavailable,
        logicalStreamSeekTarget(&single, 0, true),
    );

    const multiple = [_]plug.dsp.VorbisSeekPoint{
        fixture.point(0, 40),
        fixture.point(0, 100),
    };
    try std.testing.expectEqual(
        @as(i64, 50),
        try logicalStreamSeekTarget(&multiple, 0, true),
    );

    const other_stream = [_]plug.dsp.VorbisSeekPoint{
        fixture.point(0, 40),
        fixture.point(1, 100),
    };
    try std.testing.expectEqual(
        @as(i64, 99),
        try logicalStreamSeekTarget(&other_stream, 1, false),
    );
    try std.testing.expectError(
        error.VorbisStreamTooShortToSeek,
        logicalStreamSeekTarget(
            &.{fixture.point(0, 1)},
            0,
            false,
        ),
    );
    try std.testing.expectError(
        error.VorbisSeekLogicalStreamNotFound,
        logicalStreamSeekTarget(&.{}, 0, false),
    );
}

test "Vorbis seek selection discards only unpositioned prime output" {
    const packet = plug.dsp.VorbisAudioPacketResult{
        .header = .{
            .mode_number = 0,
            .large_block = false,
            .previous_window_flag = null,
            .next_window_flag = null,
            .block_size = 64,
            .payload_bit_offset = 1,
        },
        .decoded_bit_count = 0,
        .truncated = false,
        .floor_truncated = false,
        .residue_truncated = false,
    };
    const unpositioned = plug.dsp.VorbisPcmStreamResult{
        .packet = packet,
        .sample_count = 4,
        .pcm_start = null,
        .pcm_end = null,
    };
    var cursor = plug.dsp.VorbisPcmSeekCursor.init(10);
    try std.testing.expectEqualDeep(
        plug.dsp.VorbisGranuleRange{
            .source_start = 0,
            .sample_count = 0,
            .pcm_start = null,
            .pcm_end = null,
        },
        try selectSeekSuffix(&cursor, unpositioned),
    );
    try std.testing.expect(!cursor.reached);

    const positioned = plug.dsp.VorbisPcmStreamResult{
        .packet = packet,
        .sample_count = 4,
        .pcm_start = 8,
        .pcm_end = 12,
    };
    try std.testing.expectEqualDeep(
        plug.dsp.VorbisGranuleRange{
            .source_start = 2,
            .sample_count = 2,
            .pcm_start = 10,
            .pcm_end = 12,
        },
        try selectSeekSuffix(&cursor, positioned),
    );
    try std.testing.expect(cursor.reached);
    try std.testing.expectError(
        error.VorbisPcmSeekPositionUnavailable,
        selectSeekSuffix(&cursor, unpositioned),
    );
}

fn parseSetup(
    allocator: std.mem.Allocator,
    packet: []const u8,
    channel_count: u8,
) !plug.dsp.VorbisSetup {
    const summary = try plug.dsp.validateVorbisSetup(
        packet,
        channel_count,
    );
    const entry_count = std.math.cast(
        usize,
        summary.codebook_entry_count,
    ) orelse return error.VorbisSetupTooLarge;
    const node_count = std.math.cast(
        usize,
        summary.huffman_node_count,
    ) orelse return error.VorbisSetupTooLarge;
    const multiplicand_count = std.math.cast(
        usize,
        summary.codebook_multiplicand_count,
    ) orelse return error.VorbisSetupTooLarge;
    return plug.dsp.parseVorbisSetup(
        packet,
        channel_count,
        .{
            .codebooks = try allocator.alloc(
                plug.dsp.VorbisCodebook,
                summary.codebook_count,
            ),
            .codebook_entries = try allocator.alloc(
                plug.dsp.VorbisCodebookEntry,
                entry_count,
            ),
            .huffman_nodes = try allocator.alloc(
                plug.dsp.VorbisHuffmanNode,
                node_count,
            ),
            .codebook_multiplicands = try allocator.alloc(
                u32,
                multiplicand_count,
            ),
            .floors = try allocator.alloc(
                plug.dsp.VorbisFloor,
                summary.floor_count,
            ),
            .residues = try allocator.alloc(
                plug.dsp.VorbisResidue,
                summary.residue_count,
            ),
            .mappings = try allocator.alloc(
                plug.dsp.VorbisMapping,
                summary.mapping_count,
            ),
            .modes = try allocator.alloc(
                plug.dsp.VorbisMode,
                summary.mode_count,
            ),
        },
    );
}
