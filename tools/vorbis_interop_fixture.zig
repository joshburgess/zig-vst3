const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 3) {
        if (!std.mem.eql(u8, args[2], "--stb-standard"))
            return error.InvalidArguments;
        return writeFixtureForBlock(512, init, args, .{});
    }
    if (args.len != 2 and args.len != 4) return error.InvalidArguments;
    const psychoacoustics: plug.dsp.VorbisPsychoacousticConfig =
        if (args.len == 4) quality: {
            const level = try std.fmt.parseInt(u4, args[2], 10);
            if (level > 10) return error.InvalidArguments;
            const preset: plug.dsp.VorbisQualityPreset =
                @enumFromInt(level);
            break :quality preset.applyTo(.{});
        } else .{};
    return writeFixtureForBlock(64, init, args, psychoacoustics);
}

fn writeFixtureForBlock(
    comptime block_size: usize,
    init: std.process.Init,
    args: []const []const u8,
    psychoacoustics: plug.dsp.VorbisPsychoacousticConfig,
) !void {
    const spectrum_size = block_size / 2;
    const identification = plug.dsp.VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = -1,
        .bitrate_nominal = 768_000,
        .bitrate_minimum = -1,
        .small_block_size = block_size,
        .large_block_size = block_size,
    };
    const setup = interoperabilitySetup(spectrum_size);

    var identification_storage: [30]u8 = undefined;
    const identification_packet =
        try plug.dsp.encodeVorbisIdentificationPacket(
            &identification_storage,
            identification,
        );
    var comment_storage: [128]u8 = undefined;
    const comment_packet =
        try plug.dsp.encodeVorbisCommentPacket(
            &comment_storage,
            "zig-vst3",
            &.{.{
                .name = "TITLE",
                .value = "Vorbis interoperability fixture",
            }},
        );
    var setup_storage: [512]u8 = undefined;
    const setup_packet = try plug.dsp.encodeVorbisSetupPacket(
        &setup_storage,
        setup,
        identification.channel_count,
    );

    var ogg_storage: [64 * 1024]u8 = undefined;
    var writer = plug.dsp.OggStreamWriter.init(
        &ogg_storage,
        0x696e_7465,
    );
    try writer.appendPacket(
        identification_packet,
        0,
        true,
        false,
    );
    try writer.appendPacket(comment_packet, 0, false, false);
    try writer.appendPacket(setup_packet, 0, false, false);

    var pcm: [block_size]f32 = undefined;
    for (&pcm, 0..) |*sample, index| {
        const phase = @as(f32, @floatFromInt(index)) *
            (2.0 * std.math.pi / 16.0);
        sample.* = @sin(phase) * 0.75;
    }
    var sequence = try plug.dsp.VorbisPcmPacketSequence.init(
        .{
            .rate_control = .{
                .target_bitrate = 768_000,
                .reservoir_capacity_bits = if (block_size == 64)
                    4_096
                else
                    65_536,
                .maximum_packet_bits = if (block_size == 64)
                    4_096
                else
                    65_536,
            },
        },
        false,
    );
    _ = try sequence.prime(
        f32,
        &.{&pcm},
        identification,
    );

    const Analyzer =
        plug.dsp.VorbisPcmFrameAnalyzer(
            f32,
            1,
            block_size,
            block_size,
        );
    var analyzer = Analyzer.init();
    var analysis_pcm: [block_size]f32 = undefined;
    var analysis_transform: [spectrum_size]f32 = undefined;
    var analysis_spectrum_scratch: [spectrum_size]f32 = undefined;
    var analysis_floor_scratch: [spectrum_size]f32 = undefined;
    var analysis_threshold_scratch: [spectrum_size]f32 = undefined;
    var analysis_spectra: [spectrum_size]f32 = undefined;
    var analysis_values: [1]plug.dsp.VorbisPsychoacousticAnalysis =
        undefined;
    var analysis_floor: [spectrum_size]f32 = undefined;
    var analysis_thresholds: [spectrum_size]f32 = undefined;

    var floor_fit_y: [65]u32 = undefined;
    var floor_fit_curves: [spectrum_size]f32 = undefined;
    var preparation_floor_encodings: [1]plug.dsp.VorbisFloorPacketEncoding =
        undefined;
    var preparation_y: [65]u32 = undefined;
    var preparation_curves: [spectrum_size]f32 = undefined;
    var preparation_residue: [spectrum_size]f32 = undefined;
    var preparation_thresholds: [spectrum_size]f32 = undefined;
    var coupling_values: [spectrum_size]f32 = undefined;
    var coupling_thresholds: [spectrum_size]f32 = undefined;
    var preparation_skips: [1]bool = undefined;
    var trial_floor_encodings: [1]plug.dsp.VorbisFloorPacketEncoding =
        undefined;
    var trial_floor_y: [65]u32 = undefined;
    var trial_floor_curves: [spectrum_size]f32 = undefined;
    var trial_residue: [spectrum_size]f32 = undefined;
    var trial_thresholds: [spectrum_size]f32 = undefined;
    var trial_preparation_skips: [1]bool = undefined;

    var partition: [spectrum_size]f32 = undefined;
    var vector: [spectrum_size]f32 = undefined;
    var classifications: [spectrum_size]u8 = undefined;
    var best_classifications: [spectrum_size]u8 = undefined;
    var output_classifications: [spectrum_size]u8 = undefined;
    var quantization_entries: [spectrum_size]u32 = undefined;
    var quantization_skips: [1]bool = undefined;
    var trial_residue_encodings: [1]plug.dsp.VorbisResidueEncoding =
        undefined;
    var trial_submap_results: [1]plug.dsp.VorbisAudioResidueSubmapResult =
        undefined;
    var trial_quantization_skips: [1]bool = undefined;
    var trial_classifications: [spectrum_size]u8 = undefined;
    var trial_entries: [spectrum_size]u32 = undefined;

    var retained_floor_encodings: [1]plug.dsp.VorbisFloorPacketEncoding =
        undefined;
    var retained_floor_y: [65]u32 = undefined;
    var retained_floor_curves: [spectrum_size]f32 = undefined;
    var retained_residue: [spectrum_size]f32 = undefined;
    var retained_thresholds: [spectrum_size]f32 = undefined;
    var retained_preparation_skips: [1]bool = undefined;
    var retained_residue_encodings: [1]plug.dsp.VorbisResidueEncoding =
        undefined;
    var retained_submap_results: [1]plug.dsp.VorbisAudioResidueSubmapResult =
        undefined;
    var retained_quantization_skips: [1]bool = undefined;
    var retained_classifications: [spectrum_size]u8 = undefined;
    var retained_entries: [spectrum_size]u32 = undefined;
    var packet_storage: [16 * 1024]u8 = undefined;

    const orchestration_scratch =
        plug.dsp.VorbisPcmPacketOrchestrationScratch(f32){
            .analysis = .{
                .pcm = &analysis_pcm,
                .transform = &analysis_transform,
                .spectra = &analysis_spectrum_scratch,
                .floor_targets = &analysis_floor_scratch,
                .noise_thresholds = &analysis_threshold_scratch,
            },
            .analysis_storage = .{
                .spectra = &analysis_spectra,
                .analyses = &analysis_values,
                .floor_targets = &analysis_floor,
                .noise_thresholds = &analysis_thresholds,
            },
            .encoding = .{
                .preparation = .{
                    .floor_fit_y_values = &floor_fit_y,
                    .floor_fit_curves = &floor_fit_curves,
                    .floor_encodings = &preparation_floor_encodings,
                    .floor_y_values = &preparation_y,
                    .floor_curves = &preparation_curves,
                    .residue_values = &preparation_residue,
                    .noise_thresholds = &preparation_thresholds,
                    .coupling_values = &coupling_values,
                    .coupling_thresholds = &coupling_thresholds,
                    .do_not_encode = &preparation_skips,
                },
                .preparation_storage = .{
                    .floor_encodings = &trial_floor_encodings,
                    .floor_y_values = &trial_floor_y,
                    .floor_curves = &trial_floor_curves,
                    .residue_values = &trial_residue,
                    .noise_thresholds = &trial_thresholds,
                    .do_not_encode = &trial_preparation_skips,
                },
                .quantization = .{
                    .partition = &partition,
                    .vector = &vector,
                    .classifications = &classifications,
                    .best_classifications = &best_classifications,
                    .output_classifications = &output_classifications,
                    .entries = &quantization_entries,
                    .do_not_encode = &quantization_skips,
                },
                .quantization_storage = .{
                    .encodings = &trial_residue_encodings,
                    .submap_results = &trial_submap_results,
                    .do_not_encode = &trial_quantization_skips,
                    .classifications = &trial_classifications,
                    .entries = &trial_entries,
                },
            },
        };
    const encoding_storage =
        plug.dsp.VorbisPcmPacketEncodingStorage(f32){
            .preparation = .{
                .floor_encodings = &retained_floor_encodings,
                .floor_y_values = &retained_floor_y,
                .floor_curves = &retained_floor_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_preparation_skips,
            },
            .quantization = .{
                .encodings = &retained_residue_encodings,
                .submap_results = &retained_submap_results,
                .do_not_encode = &retained_quantization_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        };

    const first_plan = try sequence.planNext(
        f32,
        &.{&pcm},
        identification,
        setup,
    );
    const first_audio = try plug.dsp.encodeVorbisPcmPacket(
        f32,
        1,
        block_size,
        block_size,
        &analyzer,
        &sequence,
        identification,
        setup,
        first_plan,
        &.{&pcm},
        psychoacoustics,
        &.{1},
        .{},
        &packet_storage,
        orchestration_scratch,
        encoding_storage,
    );
    _ = try sequence.appendMemory(
        &writer,
        first_plan,
        first_audio.packet.bytes,
        first_audio.packet.bit_count,
    );

    const middle_plan = try sequence.planNext(
        f32,
        &.{&pcm},
        identification,
        setup,
    );
    const middle_audio = try plug.dsp.encodeVorbisPcmPacket(
        f32,
        1,
        block_size,
        block_size,
        &analyzer,
        &sequence,
        identification,
        setup,
        middle_plan,
        &.{&pcm},
        psychoacoustics,
        &.{1},
        .{},
        &packet_storage,
        orchestration_scratch,
        encoding_storage,
    );
    _ = try sequence.appendMemory(
        &writer,
        middle_plan,
        middle_audio.packet.bytes,
        middle_audio.packet.bit_count,
    );

    const final_plan = try sequence.planFinish(
        identification,
        setup,
        pcm.len,
    );
    const final_audio = try plug.dsp.encodeVorbisPcmPacket(
        f32,
        1,
        block_size,
        block_size,
        &analyzer,
        &sequence,
        identification,
        setup,
        final_plan,
        &.{&pcm},
        psychoacoustics,
        &.{1},
        .{},
        &packet_storage,
        orchestration_scratch,
        encoding_storage,
    );
    _ = try sequence.appendMemory(
        &writer,
        final_plan,
        final_audio.packet.bytes,
        final_audio.packet.bit_count,
    );

    try writeFixture(init, args[1], writer.bytes());
    if (args.len == 4)
        try writeSourcePcm(init, args[3], &pcm);
}

fn writeFixture(
    init: std.process.Init,
    path: []const u8,
    bytes: []const u8,
) !void {
    var file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, bytes);
}

fn writeSourcePcm(
    init: std.process.Init,
    path: []const u8,
    samples: []const f32,
) !void {
    var file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
    defer file.close(init.io);
    var bytes: [@sizeOf(f32)]u8 = undefined;
    for (samples) |sample| {
        std.mem.writeInt(u32, &bytes, @bitCast(sample), .little);
        try file.writeStreamingAll(init.io, &bytes);
    }
}

fn interoperabilitySetup(comptime spectrum_size: usize) plug.dsp.VorbisSetup {
    const Static = struct {
        const entries = block: {
            var values: [17]plug.dsp.VorbisCodebookEntry = undefined;
            values[0] = .{ .codeword = 0, .length = 1 };
            for (0..16) |index| {
                values[index + 1] = .{
                    .codeword = @intCast(index),
                    .length = 4,
                };
            }
            break :block values;
        };
        const multiplicands = block: {
            var values: [16]u32 = undefined;
            for (&values, 0..) |*value, index|
                value.* = @intCast(index);
            break :block values;
        };
        const huffman_nodes = block: {
            const invalid = std.math.maxInt(u32);
            const leaf: u32 = 1 << 31;
            var nodes: [15]plug.dsp.VorbisHuffmanNode =
                @splat(.{ .branches = .{ invalid, invalid } });
            var next_node: u32 = 1;
            for (0..16) |entry_index| {
                var node_index: u32 = 0;
                for (0..4) |depth| {
                    const shift: u5 = @intCast(3 - depth);
                    const branch_index: usize = @intCast(
                        (entry_index >> shift) & 1,
                    );
                    const branch =
                        &nodes[node_index].branches[branch_index];
                    if (depth == 3) {
                        branch.* = leaf | @as(u32, @intCast(entry_index));
                    } else if (branch.* == invalid) {
                        branch.* = next_node;
                        node_index = next_node;
                        next_node += 1;
                    } else {
                        node_index = branch.*;
                    }
                }
            }
            break :block nodes;
        };
        const codebooks = [_]plug.dsp.VorbisCodebook{
            .{
                .dimensions = 1,
                .entries = 1,
                .entry_offset = 0,
                .active_entry_count = 1,
                .tree_node_offset = 0,
                .tree_node_count = 0,
                .lookup_type = 0,
            },
            .{
                .dimensions = 1,
                .entries = 16,
                .entry_offset = 1,
                .active_entry_count = 16,
                .tree_node_offset = 0,
                .tree_node_count = 15,
                .lookup_type = 1,
                .minimum_value = -8,
                .delta_value = 1,
                .sequence = false,
                .multiplicand_offset = 0,
                .multiplicand_count = 16,
            },
        };
        const floor = block: {
            var x_list = [_]u16{0} ** 65;
            x_list[1] = spectrum_size;
            break :block plug.dsp.VorbisFloor{ .one = .{
                .partition_count = 0,
                .partition_classes = [_]u4{0} ** 31,
                .class_count = 0,
                .classes = [_]plug.dsp.VorbisFloorOneClass{.{
                    .dimensions = 0,
                    .subclass_bits = 0,
                    .masterbook = -1,
                    .subclass_books = [_]i16{-1} ** 8,
                }} ** 16,
                .multiplier = 1,
                .range_bits = if (spectrum_size == 32) 5 else 8,
                .point_count = 2,
                .x_list = x_list,
            } };
        };
        const floors = [_]plug.dsp.VorbisFloor{floor};
        const residues = block: {
            var cascades = [_]u8{0} ** 64;
            cascades[0] = 1;
            var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
            books[0][0] = 1;
            break :block [_]plug.dsp.VorbisResidue{.{
                .kind = .one,
                .begin = 0,
                .end = spectrum_size,
                .partition_size = 1,
                .classification_count = 1,
                .classbook = 0,
                .cascades = cascades,
                .books = books,
            }};
        };
        const mappings = [_]plug.dsp.VorbisMapping{.{
            .submap_count = 1,
            .coupling_step_count = 0,
            .coupling_steps = [_]plug.dsp.VorbisCouplingStep{.{
                .magnitude = 0,
                .angle = 0,
            }} ** 256,
            .channel_mux = [_]u4{0} ** 255,
            .submaps = [_]plug.dsp.VorbisSubmap{.{
                .floor = 0,
                .residue = 0,
            }} ** 16,
        }};
        const modes = [_]plug.dsp.VorbisMode{.{
            .large_block = false,
            .mapping = 0,
        }};
    };
    return .{
        .summary = .{
            .codebook_count = 2,
            .codebook_entry_count = 17,
            .huffman_node_count = 15,
            .codebook_multiplicand_count = 16,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 16,
        },
        .codebooks = &Static.codebooks,
        .codebook_entries = &Static.entries,
        .huffman_nodes = &Static.huffman_nodes,
        .codebook_multiplicands = &Static.multiplicands,
        .floors = &Static.floors,
        .residues = &Static.residues,
        .mappings = &Static.mappings,
        .modes = &Static.modes,
    };
}
