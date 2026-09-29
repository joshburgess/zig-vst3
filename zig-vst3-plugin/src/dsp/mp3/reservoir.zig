const std = @import("std");
const syntax = @import("syntax.zig");

const Version = syntax.Version;
const Header = syntax.Header;
const sampleRateIndex = syntax.sampleRateIndex;

fn frameMainDataOffset(header: Header) usize {
    return (if (header.crc_present) @as(usize, 6) else 4) +
        header.sideInformationBytes();
}

pub const ReservoirQuantizerBudget = struct {
    physical_bits: usize,
    history_bits: usize,
    logical_bits: usize,
};

pub const ReservoirCreditDecision = struct {
    history_bytes: u16,
    physical_bytes: u16,
    logical_bytes: u16,
    next_history_bytes: u16,
};

pub const ReservoirCreditTracker = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
    maximum_history_bytes: u16,
    available_history_bytes: u16 = 0,
    frames_committed: u64 = 0,

    pub fn init(
        header: Header,
        maximum_history_bytes: u16,
    ) !ReservoirCreditTracker {
        _ = try reservoirQuantizerBudget(
            header,
            maximum_history_bytes,
        );
        return .{
            .version = header.version,
            .sample_rate = header.sample_rate,
            .channel_count = @intCast(header.channels()),
            .maximum_history_bytes = maximum_history_bytes,
        };
    }

    pub fn reset(self: *ReservoirCreditTracker) void {
        self.available_history_bytes = 0;
        self.frames_committed = 0;
    }

    pub fn valid(self: *const ReservoirCreditTracker) bool {
        if (self.channel_count == 0 or self.channel_count > 2 or
            sampleRateIndex(self.version, self.sample_rate) == null or
            self.available_history_bytes > self.maximum_history_bytes or
            self.frames_committed == 0 and
                self.available_history_bytes != 0)
            return false;
        const format_limit: u16 =
            if (self.version == .mpeg1) 511 else 255;
        return self.maximum_history_bytes <= format_limit;
    }

    pub fn budget(
        self: ReservoirCreditTracker,
        header: Header,
    ) !ReservoirQuantizerBudget {
        try self.validateHeader(header);
        return reservoirQuantizerBudget(
            header,
            self.available_history_bytes,
        );
    }

    pub fn commit(
        self: *ReservoirCreditTracker,
        header: Header,
        logical_main_data_bits: u16,
    ) !ReservoirCreditDecision {
        try self.validateHeader(header);
        const main_data_offset = frameMainDataOffset(header);
        const frame_bytes = header.frameBytes();
        if (main_data_offset > frame_bytes)
            return error.InvalidMp3EncoderFrameSize;
        const physical_bytes = frame_bytes - main_data_offset;
        const logical_bytes = try std.math.divCeil(
            usize,
            logical_main_data_bits,
            8,
        );
        const available_bytes = std.math.add(
            usize,
            physical_bytes,
            self.available_history_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        if (logical_bytes > available_bytes)
            return error.Mp3ReservoirCreditExceeded;
        const next_history = @min(
            available_bytes - logical_bytes,
            self.maximum_history_bytes,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_committed,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const result = ReservoirCreditDecision{
            .history_bytes = self.available_history_bytes,
            .physical_bytes = @intCast(physical_bytes),
            .logical_bytes = @intCast(logical_bytes),
            .next_history_bytes = @intCast(next_history),
        };
        self.available_history_bytes = result.next_history_bytes;
        self.frames_committed = next_frames;
        return result;
    }

    fn validateHeader(
        self: ReservoirCreditTracker,
        header: Header,
    ) !void {
        if (!self.valid())
            return error.InvalidMp3ReservoirCreditState;
        _ = try reservoirQuantizerBudget(header, 0);
        if (header.version != self.version or
            header.sample_rate != self.sample_rate or
            header.channels() != self.channel_count)
            return error.Mp3ReservoirFormatChanged;
    }
};

pub fn reservoirQuantizerBudget(
    header: Header,
    available_history_bytes: u16,
) !ReservoirQuantizerBudget {
    _ = try header.encode();
    if (header.free_format)
        return error.UnsupportedFreeFormatMp3;
    const maximum_history: u16 =
        if (header.version == .mpeg1) 511 else 255;
    if (available_history_bytes > maximum_history)
        return error.InvalidMp3ReservoirHistoryLimit;
    const frame_bytes = header.frameBytes();
    const main_data_offset = frameMainDataOffset(header);
    if (main_data_offset > frame_bytes)
        return error.InvalidMp3EncoderFrameSize;
    const physical_bits = (frame_bytes - main_data_offset) * 8;
    const history_bits = @as(usize, available_history_bytes) * 8;
    const active_channels = @as(usize, header.channels()) *
        (if (header.version == .mpeg1) @as(usize, 2) else 1);
    const side_information_limit =
        active_channels * std.math.maxInt(u12);
    return .{
        .physical_bits = physical_bits,
        .history_bits = history_bits,
        .logical_bits = @min(
            physical_bits + history_bits,
            side_information_limit,
        ),
    };
}
