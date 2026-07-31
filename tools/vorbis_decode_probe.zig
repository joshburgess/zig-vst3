const plug = @import("zig-vst3-plugin");
const std = @import("std");

const channel_count = 2;
const small_block_size = 256;
const large_block_size = 2_048;

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
    const packet_storage = try allocator.alloc(u8, 4 * 1024 * 1024);
    var packets = plug.dsp.OggPacketIterator.init(
        encoded,
        packet_storage,
    );

    const identification_packet =
        try packets.next() orelse return error.MissingIdentification;
    const identification = try plug.dsp.VorbisIdentification.parse(
        identification_packet.bytes,
    );
    if (identification.channel_count != channel_count or
        identification.small_block_size != small_block_size or
        identification.large_block_size != large_block_size)
        return error.UnexpectedVorbisGeometry;

    const comment_packet =
        try packets.next() orelse return error.MissingComments;
    var comments = try plug.dsp.VorbisCommentIterator.init(
        comment_packet.bytes,
    );
    while (try comments.next()) |_| {}

    const setup_packet =
        try packets.next() orelse return error.MissingSetup;
    const summary = try plug.dsp.validateVorbisSetup(
        setup_packet.bytes,
        identification.channel_count,
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
    const setup = try plug.dsp.parseVorbisSetup(
        setup_packet.bytes,
        identification.channel_count,
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

    var decoder = plug.dsp.VorbisPcmStreamDecoder(
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
    var left: [large_block_size]f32 = undefined;
    var right: [large_block_size]f32 = undefined;
    const outputs = [_][]f32{ &left, &right };
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

    var audio_packets: usize = 0;
    var sample_count: usize = 0;
    var energy: f64 = 0.0;
    while (try packets.next()) |packet| {
        const decoded = try decoder.decode(
            packet,
            identification,
            setup,
            &outputs,
            scratch,
        );
        if (decoded.packet.truncated)
            return error.TruncatedVorbisAudioPacket;
        audio_packets += 1;
        sample_count += decoded.sample_count;
        for (left[0..decoded.sample_count]) |sample|
            energy += @as(f64, sample) * sample;
        for (right[0..decoded.sample_count]) |sample|
            energy += @as(f64, sample) * sample;
    }
    if (!decoder.ended) return error.MissingVorbisEndOfStream;
    if (audio_packets == 0 or sample_count == 0)
        return error.EmptyVorbisStream;
    if (!std.math.isFinite(energy) or energy <= 0.0)
        return error.SilentVorbisStream;
}
