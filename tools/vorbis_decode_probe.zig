const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2) return error.InvalidArguments;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
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
            const selected =
                try sequential_seek.select(decoded.stream);
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
            if (cursor.reached)
                return error.VorbisPcmSeekPositionUnavailable;
            continue;
        }
        const selected = try cursor.select(decoded);
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
    if (!std.meta.eql(expected, digest.result()))
        return error.VorbisSeekPcmMismatch;
}

fn requireLogicalStream(
    packet: plug.dsp.OggPacket,
    logical_stream_index: u32,
) !void {
    if (packet.logical_stream_index != logical_stream_index)
        return error.TruncatedVorbisLogicalStream;
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
