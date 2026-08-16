const plug = @import("zig-vst3-plugin");
const std = @import("std");

const xvc_ok = 0;
const xvc_invalid_argument = 1;
const xvc_output_too_small = 6;
const xvc_previous_block = 1 << 0;
const xvc_following_header = 1 << 1;
const xvc_following_granule = 1 << 2;
const xvc_chained = 1 << 3;
const xiph_not_audio = -135;
const stream_capacity = 4 * 1024 * 1024;
const reference_capacity = 1024 * 1024;
const maximum_peak_error = 2.5e-4;
const maximum_normalized_rms_error = 2.5e-5;

const XiphCaseInfo = extern struct {
    abi_version: u32,
    case_index: u32,
    channel_count: u32,
    sample_rate: u32,
    small_block_size: u32,
    large_block_size: u32,
    logical_stream_count: u32,
    loss_logical_stream_index: u32,
    loss_after_audio_packets: u32,
    missing_block_size: u32,
    previous_block_size: u32,
    following_block_size: u32,
    policy_flags: u32,
    strict_xiph_status: i32,
    reserved: u32,
    missing_granule: u64,
    following_granule: u64,
    terminal_frames: u64,
    clean_stream_bytes: u64,
    missing_stream_bytes: u64,
    corrupt_stream_bytes: u64,
    reference_frames: u64,
};

extern fn xvc_case_count() callconv(.c) u32;
extern fn xvc_generate_case(
    case_index: u32,
    clean_stream: [*]u8,
    clean_capacity: usize,
    missing_stream: [*]u8,
    missing_capacity: usize,
    corrupt_stream: [*]u8,
    corrupt_capacity: usize,
    silence_reference: [*]f32,
    silence_capacity: usize,
    signal_reference: [*]f32,
    signal_capacity: usize,
    info: *XiphCaseInfo,
) callconv(.c) c_int;

const ConcealmentMode = enum {
    explicit_silence,
    explicit_signal,
    previous_silence,
    previous_signal,
    following_header,
    following_granule,
};

const Metrics = struct {
    values: u64,
    peak_error: f64,
    normalized_rms_error: f64,
    error_squared: f64,
    reference_squared: f64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const clean_storage = try allocator.alloc(u8, stream_capacity);
    const missing_storage = try allocator.alloc(u8, stream_capacity);
    const corrupt_storage = try allocator.alloc(u8, stream_capacity);
    const silence_storage = try allocator.alloc(f32, reference_capacity);
    const signal_storage = try allocator.alloc(f32, reference_capacity);
    const case_count = xvc_case_count();
    if (case_count != 5) return error.UnexpectedXiphVorbisCaseCount;

    var aggregate_values: u64 = 0;
    var aggregate_error_squared: f64 = 0;
    var aggregate_reference_squared: f64 = 0;
    var aggregate_peak: f64 = 0;
    var covered_flags: u32 = 0;
    for (0..case_count) |case_index| {
        var info: XiphCaseInfo = undefined;
        const status = xvc_generate_case(
            @intCast(case_index),
            clean_storage.ptr,
            clean_storage.len,
            missing_storage.ptr,
            missing_storage.len,
            corrupt_storage.ptr,
            corrupt_storage.len,
            silence_storage.ptr,
            silence_storage.len,
            signal_storage.ptr,
            signal_storage.len,
            &info,
        );
        if (status != xvc_ok) return error.XiphVorbisCaseGenerationFailed;
        try validateCaseInfo(info, case_index);
        covered_flags |= info.policy_flags;

        const clean = clean_storage[0..try castSize(info.clean_stream_bytes)];
        const missing = missing_storage[0..try castSize(info.missing_stream_bytes)];
        const corrupt = corrupt_storage[0..try castSize(info.corrupt_stream_bytes)];
        const reference_values = try referenceValueCount(info);
        const silence = silence_storage[0..reference_values];
        const signal = signal_storage[0..reference_values];
        try validateReference(silence, info);
        try validateReference(signal, info);
        if (std.mem.eql(u8, clean, missing) or
            std.mem.eql(u8, clean, corrupt) or
            clean.len != corrupt.len)
            return error.InvalidXiphVorbisDamageFixture;
        if (std.mem.eql(u8, std.mem.sliceAsBytes(silence), std.mem.sliceAsBytes(signal)))
            return error.IndistinguishableXiphVorbisConcealmentPolicies;

        if (case_index == 0) {
            try verifyShortOutputRejection(
                clean,
                missing,
                corrupt,
                silence,
                signal,
                info,
            );
        }
        try expectStrictRejection(
            info.channel_count,
            corrupt,
            info,
            allocator,
        );

        const silence_metrics = try compareProject(
            info.channel_count,
            missing,
            info,
            .explicit_silence,
            silence,
            allocator,
        );
        try includeMetrics(
            silence_metrics,
            &aggregate_values,
            &aggregate_error_squared,
            &aggregate_reference_squared,
            &aggregate_peak,
        );
        const signal_metrics = try compareProject(
            info.channel_count,
            missing,
            info,
            .explicit_signal,
            signal,
            allocator,
        );
        try includeMetrics(
            signal_metrics,
            &aggregate_values,
            &aggregate_error_squared,
            &aggregate_reference_squared,
            &aggregate_peak,
        );

        if (info.policy_flags & xvc_previous_block != 0) {
            _ = try compareProject(
                info.channel_count,
                missing,
                info,
                .previous_silence,
                silence,
                allocator,
            );
            _ = try compareProject(
                info.channel_count,
                missing,
                info,
                .previous_signal,
                signal,
                allocator,
            );
        }
        if (info.policy_flags & xvc_following_header != 0) {
            _ = try compareProject(
                info.channel_count,
                missing,
                info,
                .following_header,
                silence,
                allocator,
            );
        }
        if (info.policy_flags & xvc_following_granule != 0) {
            _ = try compareProject(
                info.channel_count,
                missing,
                info,
                .following_granule,
                silence,
                allocator,
            );
        }
    }
    if (covered_flags != xvc_previous_block | xvc_following_header |
        xvc_following_granule | xvc_chained)
        return error.IncompleteXiphVorbisPolicyCoverage;
    if (aggregate_values == 0 or aggregate_reference_squared <= 0)
        return error.EmptyXiphVorbisMetrics;
    const normalized_rms = @sqrt(
        aggregate_error_squared / aggregate_reference_squared,
    );
    std.debug.print(
        "matched {d} Xiph Vorbis concealment values " ++
            "(peak {e:.3}, normalized RMS {e:.3})\n",
        .{ aggregate_values, aggregate_peak, normalized_rms },
    );
}

fn castSize(value: u64) !usize {
    return std.math.cast(usize, value) orelse error.XiphVorbisSizeOverflow;
}

fn referenceValueCount(info: XiphCaseInfo) !usize {
    const frames = try castSize(info.reference_frames);
    return std.math.mul(
        usize,
        frames,
        @as(usize, @intCast(info.channel_count)),
    ) catch error.XiphVorbisSizeOverflow;
}

fn validateCaseInfo(info: XiphCaseInfo, case_index: usize) !void {
    if (info.abi_version != 1 or info.case_index != case_index or
        (info.channel_count != 1 and info.channel_count != 2) or
        info.sample_rate != 48_000 or info.small_block_size != 256 or
        info.large_block_size != 2_048 or
        (info.logical_stream_count != 1 and info.logical_stream_count != 2) or
        info.loss_logical_stream_index >= info.logical_stream_count or
        info.loss_after_audio_packets == 0 or
        (info.missing_block_size != info.small_block_size and
            info.missing_block_size != info.large_block_size) or
        (info.previous_block_size != info.small_block_size and
            info.previous_block_size != info.large_block_size) or
        (info.following_block_size != info.small_block_size and
            info.following_block_size != info.large_block_size) or
        info.policy_flags == 0 or info.strict_xiph_status != xiph_not_audio or
        info.missing_granule == 0 or
        info.following_granule <= info.missing_granule or
        info.reference_frames != info.terminal_frames or
        info.clean_stream_bytes == 0 or info.missing_stream_bytes == 0 or
        info.corrupt_stream_bytes != info.clean_stream_bytes or
        info.missing_stream_bytes >= info.clean_stream_bytes)
        return error.InvalidXiphVorbisCaseInfo;
    if (info.policy_flags & xvc_previous_block != 0 and
        info.previous_block_size != info.missing_block_size)
        return error.InvalidXiphVorbisPreviousBlockCase;
    if (info.policy_flags & xvc_following_header != 0 and
        info.following_block_size != info.large_block_size)
        return error.InvalidXiphVorbisFollowingHeaderCase;
    if (info.policy_flags & xvc_following_granule != 0 and
        info.following_block_size != info.small_block_size)
        return error.InvalidXiphVorbisFollowingGranuleCase;
    if ((info.policy_flags & xvc_chained != 0) !=
        (info.logical_stream_count == 2))
        return error.InvalidXiphVorbisChainCase;
}

fn validateReference(reference: []const f32, info: XiphCaseInfo) !void {
    if (reference.len != try referenceValueCount(info))
        return error.TruncatedXiphVorbisReference;
    var energy: f64 = 0;
    for (reference) |sample| {
        if (!std.math.isFinite(sample))
            return error.NonFiniteXiphVorbisReference;
        energy += @as(f64, sample) * sample;
    }
    if (!std.math.isFinite(energy) or energy <= 0)
        return error.SilentXiphVorbisReference;
}

fn verifyShortOutputRejection(
    clean: []u8,
    missing: []u8,
    corrupt: []u8,
    silence: []f32,
    signal: []f32,
    retained_info: XiphCaseInfo,
) !void {
    const clean_hash = std.hash.Wyhash.hash(0, clean);
    const missing_hash = std.hash.Wyhash.hash(0, missing);
    const corrupt_hash = std.hash.Wyhash.hash(0, corrupt);
    const silence_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(silence));
    const signal_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(signal));
    var rejected_info = XiphCaseInfo{
        .abi_version = 0xfeed_beef,
        .case_index = 0,
        .channel_count = 0,
        .sample_rate = 0,
        .small_block_size = 0,
        .large_block_size = 0,
        .logical_stream_count = 0,
        .loss_logical_stream_index = 0,
        .loss_after_audio_packets = 0,
        .missing_block_size = 0,
        .previous_block_size = 0,
        .following_block_size = 0,
        .policy_flags = 0,
        .strict_xiph_status = 0,
        .reserved = 0,
        .missing_granule = 0,
        .following_granule = 0,
        .terminal_frames = 0,
        .clean_stream_bytes = 0,
        .missing_stream_bytes = 0,
        .corrupt_stream_bytes = 0,
        .reference_frames = 0,
    };
    const status = xvc_generate_case(
        retained_info.case_index,
        clean.ptr,
        try castSize(retained_info.clean_stream_bytes) - 1,
        missing.ptr,
        missing.len,
        corrupt.ptr,
        corrupt.len,
        silence.ptr,
        silence.len,
        signal.ptr,
        signal.len,
        &rejected_info,
    );
    if (status != xvc_output_too_small or rejected_info.abi_version != 0xfeed_beef or
        clean_hash != std.hash.Wyhash.hash(0, clean) or
        missing_hash != std.hash.Wyhash.hash(0, missing) or
        corrupt_hash != std.hash.Wyhash.hash(0, corrupt) or
        silence_hash != std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(silence)) or
        signal_hash != std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(signal)))
        return error.NonTransactionalXiphVorbisOutputRejection;
    var unused: XiphCaseInfo = undefined;
    if (xvc_generate_case(
        xvc_case_count(),
        clean.ptr,
        clean.len,
        missing.ptr,
        missing.len,
        corrupt.ptr,
        corrupt.len,
        silence.ptr,
        silence.len,
        signal.ptr,
        signal.len,
        &unused,
    ) != xvc_invalid_argument) return error.XiphVorbisInvalidCaseAccepted;
}

fn expectStrictRejection(
    channel_count: u32,
    encoded: []const u8,
    info: XiphCaseInfo,
    allocator: std.mem.Allocator,
) !void {
    switch (channel_count) {
        1 => try expectStrictRejectionForChannels(1, encoded, info, allocator),
        2 => try expectStrictRejectionForChannels(2, encoded, info, allocator),
        else => return error.UnsupportedXiphVorbisChannelCount,
    }
}

fn expectStrictRejectionForChannels(
    comptime channel_count: usize,
    encoded: []const u8,
    info: XiphCaseInfo,
    allocator: std.mem.Allocator,
) !void {
    var decoder = plug.dsp.VorbisChainedPcmStreamDecoder(
        f32,
        channel_count,
        256,
        2_048,
    ).init();
    var spectra: [channel_count * 1_024]f32 = undefined;
    var floors: [channel_count * 1_024]f32 = undefined;
    var coupling: [channel_count * 1_024]f32 = undefined;
    var time: [channel_count * 2_048]f32 = undefined;
    var classifications: [channel_count * 2_048]u8 = undefined;
    var windowed: [channel_count * 2_048]f32 = undefined;
    var output_storage: [channel_count][2_048]f32 = undefined;
    var outputs: [channel_count][]f32 = undefined;
    for (&outputs, &output_storage) |*output, *storage| output.* = storage;
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
    const packet_storage = try allocator.alloc(u8, 4 * 1024 * 1024);
    var packets = plug.dsp.OggPacketIterator.initChained(encoded, packet_storage);
    var logical_stream_index: u32 = 0;
    while (try packets.next()) |identification_packet| {
        const identification = try parseStreamHeaders(
            &packets,
            identification_packet,
            channel_count,
            allocator,
        );
        try decoder.beginLogicalStream(identification.value);
        var audio_packets: u32 = 0;
        while (try packets.next()) |packet| {
            if (packet.logical_stream_index != logical_stream_index)
                return error.TruncatedXiphVorbisLogicalStream;
            if (logical_stream_index == info.loss_logical_stream_index and
                audio_packets == info.loss_after_audio_packets)
            {
                const before = decoder;
                for (&output_storage) |*channel| @memset(channel, 91);
                if (decoder.decode(
                    packet,
                    identification.value,
                    identification.setup,
                    &outputs,
                    scratch,
                )) |_| return error.ProjectAcceptedCorruptXiphVorbisPacket else |err| {
                    if (err != error.InvalidVorbisAudioPacketType)
                        return err;
                }
                if (!std.meta.eql(before, decoder))
                    return error.CorruptXiphVorbisPacketChangedDecoder;
                for (output_storage) |channel| {
                    for (channel) |sample| {
                        if (sample != 91)
                            return error.CorruptXiphVorbisPacketChangedOutput;
                    }
                }
                return;
            }
            _ = try decoder.decode(
                packet,
                identification.value,
                identification.setup,
                &outputs,
                scratch,
            );
            audio_packets += 1;
            if (packet.end) break;
        }
        logical_stream_index += 1;
    }
    return error.MissingCorruptXiphVorbisPacket;
}

const ParsedStream = struct {
    value: plug.dsp.VorbisIdentification,
    setup: plug.dsp.VorbisSetup,
};

fn parseStreamHeaders(
    packets: *plug.dsp.OggPacketIterator,
    identification_packet: plug.dsp.OggPacket,
    comptime channel_count: usize,
    allocator: std.mem.Allocator,
) !ParsedStream {
    if (!identification_packet.beginning)
        return error.MissingXiphVorbisBeginningOfStream;
    const identification = try plug.dsp.VorbisIdentification.parse(
        identification_packet.bytes,
    );
    if (identification.channel_count != channel_count or
        identification.sample_rate != 48_000 or
        identification.small_block_size != 256 or
        identification.large_block_size != 2_048)
        return error.UnexpectedXiphVorbisGeometry;
    const comment_packet = try packets.next() orelse
        return error.MissingXiphVorbisComments;
    if (comment_packet.logical_stream_index !=
        identification_packet.logical_stream_index)
        return error.TruncatedXiphVorbisLogicalStream;
    var comments = try plug.dsp.VorbisCommentIterator.init(comment_packet.bytes);
    while (try comments.next()) |_| {}
    const setup_packet = try packets.next() orelse
        return error.MissingXiphVorbisSetup;
    if (setup_packet.logical_stream_index !=
        identification_packet.logical_stream_index)
        return error.TruncatedXiphVorbisLogicalStream;
    return .{
        .value = identification,
        .setup = try parseSetup(
            allocator,
            setup_packet.bytes,
            identification.channel_count,
        ),
    };
}

fn compareProject(
    channel_count: u32,
    encoded: []const u8,
    info: XiphCaseInfo,
    mode: ConcealmentMode,
    reference: []const f32,
    allocator: std.mem.Allocator,
) !Metrics {
    return switch (channel_count) {
        1 => compareProjectForChannels(1, encoded, info, mode, reference, allocator),
        2 => compareProjectForChannels(2, encoded, info, mode, reference, allocator),
        else => error.UnsupportedXiphVorbisChannelCount,
    };
}

fn compareProjectForChannels(
    comptime channel_count: usize,
    encoded: []const u8,
    info: XiphCaseInfo,
    mode: ConcealmentMode,
    reference: []const f32,
    allocator: std.mem.Allocator,
) !Metrics {
    var decoder = plug.dsp.VorbisChainedPcmStreamDecoder(
        f32,
        channel_count,
        256,
        2_048,
    ).init();
    var spectra: [channel_count * 1_024]f32 = undefined;
    var floors: [channel_count * 1_024]f32 = undefined;
    var coupling: [channel_count * 1_024]f32 = undefined;
    var time: [channel_count * 2_048]f32 = undefined;
    var classifications: [channel_count * 2_048]u8 = undefined;
    var windowed: [channel_count * 2_048]f32 = undefined;
    var output_storage: [channel_count][2_048]f32 = undefined;
    var outputs: [channel_count][]f32 = undefined;
    for (&outputs, &output_storage) |*output, *storage| output.* = storage;
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
    const project = try allocator.alloc(f32, reference.len);
    var project_offset: usize = 0;
    const packet_storage = try allocator.alloc(u8, 4 * 1024 * 1024);
    var packets = plug.dsp.OggPacketIterator.initChained(encoded, packet_storage);
    var logical_stream_index: u32 = 0;
    var inserted = false;
    while (try packets.next()) |identification_packet| {
        const identification = try parseStreamHeaders(
            &packets,
            identification_packet,
            channel_count,
            allocator,
        );
        try decoder.beginLogicalStream(identification.value);
        var audio_packets: u32 = 0;
        while (try packets.next()) |packet| {
            if (packet.logical_stream_index != logical_stream_index)
                return error.TruncatedXiphVorbisLogicalStream;
            if (!inserted and
                logical_stream_index == info.loss_logical_stream_index and
                audio_packets == info.loss_after_audio_packets)
            {
                const following = try plug.dsp.parseVorbisAudioPacketHeader(
                    packet.bytes,
                    identification.value,
                    identification.setup,
                );
                const concealed: plug.dsp.VorbisChainedPcmConcealmentResult =
                    switch (mode) {
                        .explicit_silence => try decoder.concealMissingPacket(
                            info.missing_block_size == 2_048,
                            info.missing_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                        .explicit_signal => try decoder.concealMissingPacketWithPreviousSignal(
                            info.missing_block_size == 2_048,
                            .{},
                            info.missing_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                        .previous_silence => try decoder.concealMissingPacketUsingPreviousBlockSize(
                            info.missing_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                        .previous_signal => try decoder.concealMissingPacketUsingPreviousBlockSignal(
                            .{},
                            info.missing_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                        .following_header => try decoder.concealMissingPacketUsingFollowingHeader(
                            following,
                            info.missing_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                        .following_granule => try decoder.concealMissingPacketUsingFollowingGranule(
                            following,
                            info.following_granule,
                            false,
                            identification.value,
                            &outputs,
                            &windowed,
                        ),
                    };
                try appendProjectPcm(
                    channel_count,
                    &outputs,
                    concealed.stream.sample_count,
                    concealed.global_pcm_start,
                    concealed.global_pcm_end,
                    project,
                    &project_offset,
                );
                if (concealed.stream.block_size != info.missing_block_size or
                    concealed.stream.concealed_packet_count != 1)
                    return error.IncorrectProjectXiphVorbisConcealment;
                inserted = true;
            }
            const decoded = try decoder.decode(
                packet,
                identification.value,
                identification.setup,
                &outputs,
                scratch,
            );
            try appendProjectPcm(
                channel_count,
                &outputs,
                decoded.stream.sample_count,
                decoded.global_pcm_start,
                decoded.global_pcm_end,
                project,
                &project_offset,
            );
            audio_packets += 1;
            if (packet.end) break;
        }
        logical_stream_index += 1;
    }
    if (!inserted or logical_stream_index != info.logical_stream_count or
        !decoder.stream.ended or project_offset != reference.len or
        project_offset / channel_count != info.terminal_frames)
        return error.IncompleteProjectXiphVorbisConcealment;
    return compareComplete(project[0..project_offset], reference);
}

fn appendProjectPcm(
    comptime channel_count: usize,
    outputs: *const [channel_count][]f32,
    sample_count: usize,
    global_start: u64,
    global_end: u64,
    destination: []f32,
    offset: *usize,
) !void {
    const current_frame = offset.* / channel_count;
    if (global_start != current_frame or
        global_end != current_frame + sample_count)
        return error.DiscontinuousProjectXiphVorbisPcm;
    const values = std.math.mul(
        usize,
        sample_count,
        channel_count,
    ) catch return error.ProjectXiphVorbisPcmOverflow;
    if (values > destination.len - offset.*)
        return error.ProjectXiphVorbisPcmOverflow;
    for (0..sample_count) |frame| {
        for (0..channel_count) |channel| {
            destination[offset.*] = outputs[channel][frame];
            offset.* += 1;
        }
    }
}

fn compareComplete(project: []const f32, reference: []const f32) !Metrics {
    if (project.len != reference.len or project.len == 0)
        return error.XiphVorbisReferenceShapeMismatch;
    var reference_squared: f64 = 0;
    var project_squared: f64 = 0;
    var error_squared: f64 = 0;
    var peak_error: f64 = 0;
    for (project, reference) |project_sample, reference_sample| {
        if (!std.math.isFinite(project_sample) or
            !std.math.isFinite(reference_sample))
            return error.NonFiniteXiphVorbisComparison;
        const actual: f64 = project_sample;
        const expected: f64 = reference_sample;
        const difference = actual - expected;
        project_squared += actual * actual;
        reference_squared += expected * expected;
        error_squared += difference * difference;
        peak_error = @max(peak_error, @abs(difference));
    }
    if (!std.math.isFinite(reference_squared) or reference_squared <= 0 or
        !std.math.isFinite(project_squared) or project_squared <= 0 or
        !std.math.isFinite(error_squared))
        return error.InvalidXiphVorbisComparisonEnergy;
    const normalized_rms = @sqrt(error_squared / reference_squared);
    if (peak_error > maximum_peak_error or
        normalized_rms > maximum_normalized_rms_error)
        return error.XiphVorbisConcealmentMismatch;
    return .{
        .values = project.len,
        .peak_error = peak_error,
        .normalized_rms_error = normalized_rms,
        .error_squared = error_squared,
        .reference_squared = reference_squared,
    };
}

fn includeMetrics(
    metrics: Metrics,
    values: *u64,
    error_squared: *f64,
    reference_squared: *f64,
    peak: *f64,
) !void {
    values.* = std.math.add(u64, values.*, metrics.values) catch
        return error.XiphVorbisMetricOverflow;
    peak.* = @max(peak.*, metrics.peak_error);
    reference_squared.* += metrics.reference_squared;
    error_squared.* += metrics.error_squared;
}

fn parseSetup(
    allocator: std.mem.Allocator,
    packet: []const u8,
    channel_count: u8,
) !plug.dsp.VorbisSetup {
    const summary = try plug.dsp.validateVorbisSetup(packet, channel_count);
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
            .codebook_multiplicands = try allocator.alloc(u32, multiplicand_count),
            .floors = try allocator.alloc(plug.dsp.VorbisFloor, summary.floor_count),
            .residues = try allocator.alloc(plug.dsp.VorbisResidue, summary.residue_count),
            .mappings = try allocator.alloc(plug.dsp.VorbisMapping, summary.mapping_count),
            .modes = try allocator.alloc(plug.dsp.VorbisMode, summary.mode_count),
        },
    );
}

test "Xiph Vorbis reference validation rejects malformed PCM" {
    const info = XiphCaseInfo{
        .abi_version = 1,
        .case_index = 0,
        .channel_count = 1,
        .sample_rate = 48_000,
        .small_block_size = 256,
        .large_block_size = 2_048,
        .logical_stream_count = 1,
        .loss_logical_stream_index = 0,
        .loss_after_audio_packets = 1,
        .missing_block_size = 256,
        .previous_block_size = 256,
        .following_block_size = 256,
        .policy_flags = xvc_previous_block,
        .strict_xiph_status = xiph_not_audio,
        .reserved = 0,
        .missing_granule = 64,
        .following_granule = 128,
        .terminal_frames = 2,
        .clean_stream_bytes = 1,
        .missing_stream_bytes = 1,
        .corrupt_stream_bytes = 1,
        .reference_frames = 2,
    };
    try std.testing.expectError(
        error.TruncatedXiphVorbisReference,
        validateReference(&.{1}, info),
    );
    try std.testing.expectError(
        error.SilentXiphVorbisReference,
        validateReference(&.{ 0, 0 }, info),
    );
    try std.testing.expectError(
        error.NonFiniteXiphVorbisReference,
        validateReference(&.{ 1, std.math.nan(f32) }, info),
    );
    try std.testing.expectError(
        error.XiphVorbisReferenceShapeMismatch,
        compareComplete(&.{1}, &.{ 1, 2 }),
    );
    try std.testing.expectError(
        error.NonFiniteXiphVorbisComparison,
        compareComplete(&.{ std.math.inf(f32), 1 }, &.{ 1, 1 }),
    );
}
