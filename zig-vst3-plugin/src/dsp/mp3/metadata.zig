const std = @import("std");

pub const XingKind = enum {
    variable,
    constant,
};

pub const Xing = struct {
    kind: XingKind,
    frame_count: ?u32,
    stream_bytes: ?u32,
    toc: ?[100]u8,
    quality: ?u32,
    encoder: ?[9]u8,
    encoder_delay: ?u12,
    encoder_padding: ?u12,
};

pub const Vbri = struct {
    version: u16,
    delay: u16,
    quality: u16,
    stream_bytes: u32,
    frame_count: u32,
    toc_entries: u16,
    toc_scale: u16,
    entry_bytes: u16,
    frames_per_entry: u16,
    toc: []const u8,

    /// Approximate an audio-relative byte offset for an encoded frame.
    pub fn approximateByteOffsetForFrame(
        self: Vbri,
        target_frame: u32,
    ) !u32 {
        if (self.version != 1)
            return error.UnsupportedVbriVersion;
        if (self.entry_bytes < 1 or self.entry_bytes > 4)
            return error.InvalidVbriEntrySize;
        if (self.toc_scale == 0)
            return error.InvalidVbriTocScale;
        if (self.frames_per_entry == 0)
            return error.InvalidVbriFramesPerEntry;
        if (self.frame_count == 0 or target_frame > self.frame_count)
            return error.InvalidVbriTargetFrame;
        const expected_toc_bytes = std.math.mul(
            usize,
            self.toc_entries,
            self.entry_bytes,
        ) catch return error.VbriSizeOverflow;
        if (self.toc.len != expected_toc_bytes)
            return error.InvalidVbriTocSize;
        const covered_frames = std.math.mul(
            u64,
            self.toc_entries,
            self.frames_per_entry,
        ) catch return error.VbriFrameCoverageOverflow;
        const uncovered_frames =
            @as(u64, self.frame_count) -| covered_frames;
        if (uncovered_frames > 1)
            return error.IncompleteVbriFrameCoverage;

        const target_frame_wide: u64 = target_frame;
        var cumulative_bytes: u64 = 0;
        var target_offset: ?u64 = if (target_frame == 0) 0 else null;
        for (0..self.toc_entries) |entry_index| {
            const entry_offset = entry_index * self.entry_bytes;
            var entry: u32 = 0;
            for (self.toc[entry_offset..][0..self.entry_bytes]) |byte| {
                entry = (entry << 8) | byte;
            }
            if (entry == 0) return error.InvalidVbriTocEntry;
            const segment_bytes = std.math.mul(
                u64,
                entry,
                self.toc_scale,
            ) catch return error.VbriByteOffsetOverflow;

            const segment_first_frame = std.math.mul(
                u64,
                @intCast(entry_index),
                self.frames_per_entry,
            ) catch return error.VbriFrameCoverageOverflow;
            var segment_end_frame = std.math.add(
                u64,
                segment_first_frame,
                self.frames_per_entry,
            ) catch return error.VbriFrameCoverageOverflow;
            if (entry_index + 1 == self.toc_entries and
                uncovered_frames == 1)
            {
                segment_end_frame += 1;
            }
            if (target_offset == null and
                target_frame_wide >= segment_first_frame and
                target_frame_wide < segment_end_frame)
            {
                const frame_in_segment =
                    target_frame_wide - segment_first_frame;
                const segment_frames =
                    segment_end_frame - segment_first_frame;
                const partial_bytes =
                    segment_bytes * frame_in_segment / segment_frames;
                target_offset = std.math.add(
                    u64,
                    cumulative_bytes,
                    partial_bytes,
                ) catch return error.VbriByteOffsetOverflow;
            }
            cumulative_bytes = std.math.add(
                u64,
                cumulative_bytes,
                segment_bytes,
            ) catch return error.VbriByteOffsetOverflow;
            if (cumulative_bytes > self.stream_bytes)
                return error.InvalidVbriStreamBytes;
        }
        if (target_frame == self.frame_count)
            target_offset = self.stream_bytes;
        const result = target_offset orelse
            return error.IncompleteVbriFrameCoverage;
        if (result > self.stream_bytes or result > std.math.maxInt(u32))
            return error.InvalidVbriStreamBytes;
        return @intCast(result);
    }
};

pub const VbriSummary = struct {
    version: u16,
    delay: u16,
    quality: u16,
    stream_bytes: u32,
    frame_count: u32,
    toc_entries: u16,
    toc_scale: u16,
    entry_bytes: u16,
    frames_per_entry: u16,

    pub fn from(vbri: Vbri) VbriSummary {
        return .{
            .version = vbri.version,
            .delay = vbri.delay,
            .quality = vbri.quality,
            .stream_bytes = vbri.stream_bytes,
            .frame_count = vbri.frame_count,
            .toc_entries = vbri.toc_entries,
            .toc_scale = vbri.toc_scale,
            .entry_bytes = vbri.entry_bytes,
            .frames_per_entry = vbri.frames_per_entry,
        };
    }
};

pub const Summary = struct {
    audio_offset: usize,
    audio_bytes: usize,
    frame_count: u64,
    sample_count: u64,
    sample_rate: u32,
    channels: u8,
    first_xing: ?Xing,
    first_vbri: ?Vbri,

    pub fn durationSeconds(self: Summary) f64 {
        return @as(f64, @floatFromInt(self.sample_count)) /
            @as(f64, @floatFromInt(self.sample_rate));
    }
};
