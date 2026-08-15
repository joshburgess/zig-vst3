const std = @import("std");
const fft = @import("../fft.zig");
const file_reader_io = @import("../file_reader_io.zig");
const file_writer_io = @import("../file_writer_io.zig");
const ogg_container = @import("container.zig");

pub const unknown_granule = ogg_container.unknown_granule;
pub const maximum_page_segments = ogg_container.maximum_page_segments;
pub const maximum_page_body_bytes = ogg_container.maximum_page_body_bytes;
pub const maximum_page_bytes = ogg_container.maximum_page_bytes;
pub const Limits = ogg_container.Limits;
pub const default_limits = ogg_container.default_limits;
pub const Page = ogg_container.Page;
pub const PageIterator = ogg_container.PageIterator;
pub const validateEncodedLimits = ogg_container.validateEncodedLimits;
pub const Packet = ogg_container.Packet;
pub const PacketIterator = ogg_container.PacketIterator;
pub const RetainedOggPageState = ogg_container.RetainedOggPageState;
pub const validateRetainedOggPage = ogg_container.validateRetainedOggPage;
pub const validateRetainedPageStorageRanges = ogg_container.validateRetainedPageStorageRanges;
pub const VorbisPacketLocation = ogg_container.VorbisPacketLocation;
pub const VorbisSeekPoint = ogg_container.VorbisSeekPoint;
pub const VorbisSeekIndexer = ogg_container.VorbisSeekIndexer;
pub const vorbisPacketLocation = ogg_container.vorbisPacketLocation;
pub const requiredVorbisSeekPoints = ogg_container.requiredVorbisSeekPoints;
pub const requiredVorbisSeekPointsWithLimits = ogg_container.requiredVorbisSeekPointsWithLimits;
pub const buildVorbisSeekIndex = ogg_container.buildVorbisSeekIndex;
pub const buildVorbisSeekIndexWithLimits = ogg_container.buildVorbisSeekIndexWithLimits;
pub const findVorbisSeekPoint = ogg_container.findVorbisSeekPoint;
pub const FilePageReader = ogg_container.FilePageReader;
pub const oggReaderLifecycleValid = ogg_container.oggReaderLifecycleValid;
pub const requiredVorbisFileSeekPoints = ogg_container.requiredVorbisFileSeekPoints;
pub const requiredVorbisFileSeekPointsWithLimits = ogg_container.requiredVorbisFileSeekPointsWithLimits;
pub const buildVorbisFileSeekIndex = ogg_container.buildVorbisFileSeekIndex;
pub const buildVorbisFileSeekIndexWithLimits = ogg_container.buildVorbisFileSeekIndexWithLimits;
pub const buildVorbisFileSeekIndexTransactional = ogg_container.buildVorbisFileSeekIndexTransactional;
pub const buildVorbisFileSeekIndexTransactionalWithLimits = ogg_container.buildVorbisFileSeekIndexTransactionalWithLimits;
pub const FilePacketReader = ogg_container.FilePacketReader;
pub const FilePacketCheckpoint = ogg_container.FilePacketCheckpoint;
pub const validatePacketPageCursor = ogg_container.validatePacketPageCursor;
pub const PacketLayout = ogg_container.PacketLayout;
pub const packetLayout = ogg_container.packetLayout;
pub const committedPageStateValid = ogg_container.committedPageStateValid;
pub const StreamWriter = ogg_container.StreamWriter;
pub const FileWriter = ogg_container.FileWriter;

pub const VorbisIdentification = struct {
    channel_count: u8,
    sample_rate: u32,
    bitrate_maximum: i32,
    bitrate_nominal: i32,
    bitrate_minimum: i32,
    small_block_size: u16,
    large_block_size: u16,

    pub fn parse(packet: []const u8) !VorbisIdentification {
        if (packet.len != 30 or packet[0] != 1 or
            !std.mem.eql(u8, packet[1..7], "vorbis"))
            return error.InvalidVorbisIdentificationHeader;
        if (std.mem.readInt(u32, packet[7..11], .little) != 0)
            return error.UnsupportedVorbisVersion;
        const channels = packet[11];
        const sample_rate =
            std.mem.readInt(u32, packet[12..16], .little);
        const blocks = packet[28];
        const small_exponent = blocks & 0x0f;
        const large_exponent = blocks >> 4;
        if (channels == 0 or sample_rate == 0 or
            small_exponent < 6 or large_exponent > 13 or
            small_exponent > large_exponent or packet[29] != 1)
            return error.InvalidVorbisIdentificationHeader;
        return .{
            .channel_count = channels,
            .sample_rate = sample_rate,
            .bitrate_maximum = std.mem.readInt(i32, packet[16..20], .little),
            .bitrate_nominal = std.mem.readInt(i32, packet[20..24], .little),
            .bitrate_minimum = std.mem.readInt(i32, packet[24..28], .little),
            .small_block_size = @as(u16, 1) << @intCast(small_exponent),
            .large_block_size = @as(u16, 1) << @intCast(large_exponent),
        };
    }
};

pub fn encodeVorbisIdentificationPacket(
    destination: []u8,
    identification: VorbisIdentification,
) ![]const u8 {
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        !validVorbisBitrate(identification.bitrate_maximum) or
        !validVorbisBitrate(identification.bitrate_nominal) or
        !validVorbisBitrate(identification.bitrate_minimum) or
        !validVorbisBlockSize(identification.small_block_size) or
        !validVorbisBlockSize(identification.large_block_size) or
        identification.small_block_size >
            identification.large_block_size)
        return error.InvalidVorbisIdentification;
    if (identification.bitrate_minimum > 0 and
        identification.bitrate_maximum > 0 and
        identification.bitrate_minimum >
            identification.bitrate_maximum)
        return error.InvalidVorbisIdentification;
    if (destination.len < 30)
        return error.VorbisIdentificationOutputTooSmall;

    var packet: [30]u8 = @splat(0);
    packet[0] = 1;
    @memcpy(packet[1..7], "vorbis");
    packet[11] = identification.channel_count;
    std.mem.writeInt(
        u32,
        packet[12..16],
        identification.sample_rate,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[16..20],
        identification.bitrate_maximum,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[20..24],
        identification.bitrate_nominal,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[24..28],
        identification.bitrate_minimum,
        .little,
    );
    packet[28] =
        try vorbisBlockExponent(identification.small_block_size) |
        (try vorbisBlockExponent(identification.large_block_size) << 4);
    packet[29] = 1;
    @memcpy(destination[0..30], &packet);
    return destination[0..30];
}

pub const VorbisComment = struct {
    name: []const u8,
    value: []const u8,
};

pub fn requiredVorbisCommentPacketBytes(
    vendor: []const u8,
    comments: []const VorbisComment,
) !usize {
    try validateVorbisCommentText(vendor);
    if (vendor.len > std.math.maxInt(u32) or
        comments.len > std.math.maxInt(u32))
        return error.VorbisCommentSizeOverflow;
    var required: usize = 16;
    required = std.math.add(
        usize,
        required,
        vendor.len,
    ) catch return error.VorbisCommentSizeOverflow;
    for (comments) |comment| {
        try validateVorbisCommentName(comment.name);
        try validateVorbisCommentText(comment.value);
        const field_bytes = std.math.add(
            usize,
            comment.name.len,
            1,
        ) catch return error.VorbisCommentSizeOverflow;
        const complete_field_bytes = std.math.add(
            usize,
            field_bytes,
            comment.value.len,
        ) catch return error.VorbisCommentSizeOverflow;
        if (complete_field_bytes > std.math.maxInt(u32))
            return error.VorbisCommentSizeOverflow;
        required = std.math.add(
            usize,
            required,
            4,
        ) catch return error.VorbisCommentSizeOverflow;
        required = std.math.add(
            usize,
            required,
            complete_field_bytes,
        ) catch return error.VorbisCommentSizeOverflow;
    }
    return required;
}

pub fn encodeVorbisCommentPacket(
    destination: []u8,
    vendor: []const u8,
    comments: []const VorbisComment,
) ![]const u8 {
    const required = try requiredVorbisCommentPacketBytes(
        vendor,
        comments,
    );
    if (destination.len < required)
        return error.VorbisCommentOutputTooSmall;
    if (byteRangesOverlap(
        @intFromPtr(destination.ptr),
        required,
        @intFromPtr(vendor.ptr),
        vendor.len,
    )) return error.OverlappingVorbisCommentStorage;
    if (vorbisSliceOverlapsBytes(
        VorbisComment,
        comments,
        destination[0..required],
    )) return error.OverlappingVorbisCommentStorage;
    for (comments) |comment| {
        if (byteRangesOverlap(
            @intFromPtr(destination.ptr),
            required,
            @intFromPtr(comment.name.ptr),
            comment.name.len,
        ) or byteRangesOverlap(
            @intFromPtr(destination.ptr),
            required,
            @intFromPtr(comment.value.ptr),
            comment.value.len,
        )) return error.OverlappingVorbisCommentStorage;
    }

    destination[0] = 3;
    @memcpy(destination[1..7], "vorbis");
    std.mem.writeInt(
        u32,
        destination[7..11],
        @intCast(vendor.len),
        .little,
    );
    var offset: usize = 11;
    @memcpy(destination[offset..][0..vendor.len], vendor);
    offset += vendor.len;
    std.mem.writeInt(
        u32,
        destination[offset..][0..4],
        @intCast(comments.len),
        .little,
    );
    offset += 4;
    for (comments) |comment| {
        const field_bytes =
            comment.name.len + 1 + comment.value.len;
        std.mem.writeInt(
            u32,
            destination[offset..][0..4],
            @intCast(field_bytes),
            .little,
        );
        offset += 4;
        @memcpy(
            destination[offset..][0..comment.name.len],
            comment.name,
        );
        offset += comment.name.len;
        destination[offset] = '=';
        offset += 1;
        @memcpy(
            destination[offset..][0..comment.value.len],
            comment.value,
        );
        offset += comment.value.len;
    }
    destination[offset] = 1;
    offset += 1;
    if (offset != required)
        return error.InvalidVorbisCommentSize;
    return destination[0..required];
}

pub const VorbisCommentIterator = struct {
    packet: []const u8,
    vendor: []const u8,
    offset: usize,
    remaining: u32,
    validated_packet: ?[]const u8 = null,
    validated_vendor: ?[]const u8 = null,
    validated_offset: usize = 0,
    validated_remaining: u32 = 0,

    pub fn init(packet: []const u8) !VorbisCommentIterator {
        var result = try initPrefix(packet);
        var validation = result;
        while (try validation.nextInPlace()) |_| {}
        result.recordWitness();
        return result;
    }

    fn initPrefix(packet: []const u8) !VorbisCommentIterator {
        if (packet.len < 16 or packet[0] != 3 or
            !std.mem.eql(u8, packet[1..7], "vorbis"))
            return error.InvalidVorbisCommentHeader;
        const vendor_bytes =
            std.mem.readInt(u32, packet[7..11], .little);
        if (vendor_bytes > packet.len - 16)
            return error.InvalidVorbisCommentHeader;
        const vendor_end = 11 + @as(usize, vendor_bytes);
        const vendor = packet[11..vendor_end];
        try validateVorbisCommentText(vendor);
        return .{
            .packet = packet,
            .vendor = vendor,
            .offset = vendor_end + 4,
            .remaining = std.mem.readInt(
                u32,
                packet[vendor_end..][0..4],
                .little,
            ),
        };
    }

    pub fn next(self: *VorbisCommentIterator) !?VorbisComment {
        try self.validateState();
        var trial = self.*;
        const comment = try trial.nextInPlace();
        trial.recordWitness();
        self.* = trial;
        return comment;
    }

    pub fn valid(self: *const VorbisCommentIterator) bool {
        self.validateState() catch return false;
        var trial = self.*;
        while (trial.nextInPlace() catch return false) |_| {}
        return true;
    }

    fn validateState(self: *const VorbisCommentIterator) !void {
        if (self.witnessMatches()) return;
        var canonical = try initPrefix(self.packet);
        if (!sameByteRange(self.vendor, canonical.vendor))
            return error.InvalidVorbisCommentIteratorState;
        while (true) {
            if (self.offset == canonical.offset and
                self.remaining == canonical.remaining)
            {
                return;
            }
            if (canonical.offset >= self.offset)
                return error.InvalidVorbisCommentIteratorState;
            _ = (try canonical.nextInPlace()) orelse
                return error.InvalidVorbisCommentIteratorState;
        }
    }

    fn witnessMatches(self: *const VorbisCommentIterator) bool {
        const packet = self.validated_packet orelse return false;
        const vendor = self.validated_vendor orelse return false;
        return sameByteRange(self.packet, packet) and
            sameByteRange(self.vendor, vendor) and
            self.offset == self.validated_offset and
            self.remaining == self.validated_remaining;
    }

    fn recordWitness(self: *VorbisCommentIterator) void {
        self.validated_packet = self.packet;
        self.validated_vendor = self.vendor;
        self.validated_offset = self.offset;
        self.validated_remaining = self.remaining;
    }

    fn nextInPlace(self: *VorbisCommentIterator) !?VorbisComment {
        if (self.offset > self.packet.len)
            return error.InvalidVorbisCommentHeader;
        if (self.remaining == 0) {
            if (self.packet.len - self.offset != 1 or
                self.packet[self.offset] != 1)
                return error.InvalidVorbisCommentHeader;
            return null;
        }
        if (self.packet.len - self.offset < 5)
            return error.InvalidVorbisCommentHeader;
        const field_bytes =
            std.mem.readInt(u32, self.packet[self.offset..][0..4], .little);
        self.offset += 4;
        if (field_bytes > self.packet.len - self.offset -| 1)
            return error.InvalidVorbisCommentHeader;
        const field = self.packet[self.offset..][0..field_bytes];
        self.offset += field_bytes;
        self.remaining -= 1;
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse
            return error.InvalidVorbisCommentField;
        const name = field[0..separator];
        try validateVorbisCommentName(name);
        const value = field[separator + 1 ..];
        try validateVorbisCommentText(value);
        return .{ .name = name, .value = value };
    }
};

pub fn sameByteRange(first: []const u8, second: []const u8) bool {
    return first.len == second.len and first.ptr == second.ptr;
}

pub fn validVorbisBitrate(bitrate: i32) bool {
    return bitrate >= -1;
}

pub fn validVorbisBlockSize(block_size: u16) bool {
    return block_size >= 64 and
        block_size <= 8_192 and
        std.math.isPowerOfTwo(block_size);
}

pub fn vorbisBlockExponent(block_size: u16) !u8 {
    if (!validVorbisBlockSize(block_size))
        return error.InvalidVorbisBlockSize;
    return @intCast(@ctz(block_size));
}

pub fn validateVorbisCommentName(name: []const u8) !void {
    if (name.len == 0)
        return error.InvalidVorbisCommentField;
    for (name) |byte| {
        if (byte < 0x20 or byte > 0x7d or byte == '=')
            return error.InvalidVorbisCommentField;
    }
}

pub fn validateVorbisCommentText(text: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(text))
        return error.InvalidVorbisCommentUtf8;
}

pub const VorbisHeaders = struct {
    identification: VorbisIdentification,
    comments: VorbisCommentIterator,
    setup: VorbisSetupSummary,

    pub fn parse(
        identification_packet: []const u8,
        comment_packet: []const u8,
        setup_packet: []const u8,
    ) !VorbisHeaders {
        const identification =
            try VorbisIdentification.parse(identification_packet);
        const comments = try VorbisCommentIterator.init(comment_packet);
        const setup = try validateVorbisSetup(
            setup_packet,
            identification.channel_count,
        );
        return .{
            .identification = identification,
            .comments = comments,
            .setup = setup,
        };
    }
};

pub const VorbisCodebook = struct {
    dimensions: u16,
    entries: u32,
    entry_offset: u64,
    active_entry_count: u32,
    tree_node_offset: u64 = 0,
    tree_node_count: u32 = 0,
    lookup_type: u2,
    minimum_value: f64 = 0,
    delta_value: f64 = 0,
    sequence: bool = false,
    multiplicand_offset: u64 = 0,
    multiplicand_count: u64 = 0,
};

pub const VorbisCodebookEntry = struct {
    codeword: u32,
    length: u8,
};

pub const VorbisHuffmanNode = struct {
    branches: [2]u32,
};

pub const VorbisFloorZero = struct {
    order: u8,
    rate: u16,
    bark_map_size: u16,
    amplitude_bits: u6,
    amplitude_offset: u8,
    book_count: u5,
    books: [16]u8,
};

pub const VorbisFloorOneClass = struct {
    dimensions: u4,
    subclass_bits: u2,
    masterbook: i16,
    subclass_books: [8]i16,
};

pub const VorbisFloorOne = struct {
    partition_count: u5,
    partition_classes: [31]u4,
    class_count: u5,
    classes: [16]VorbisFloorOneClass,
    multiplier: u3,
    range_bits: u4,
    point_count: u7,
    x_list: [65]u16,
};

pub const VorbisFloor = union(enum) {
    zero: VorbisFloorZero,
    one: VorbisFloorOne,
};

pub const VorbisResidueKind = enum(u2) {
    zero,
    one,
    two,
};

pub const VorbisResidue = struct {
    kind: VorbisResidueKind,
    begin: u24,
    end: u24,
    partition_size: u25,
    classification_count: u7,
    classbook: u8,
    cascades: [64]u8,
    books: [64][8]i16,
};

pub const VorbisCouplingStep = struct {
    magnitude: u8,
    angle: u8,
};

pub const VorbisSubmap = struct {
    floor: u8,
    residue: u8,
};

pub const VorbisMapping = struct {
    submap_count: u5,
    coupling_step_count: u9,
    coupling_steps: [256]VorbisCouplingStep,
    channel_mux: [255]u4,
    submaps: [16]VorbisSubmap,
};

pub const VorbisSetupSummary = struct {
    codebook_count: u16,
    codebook_entry_count: u64,
    huffman_node_count: u64 = 0,
    codebook_multiplicand_count: u64 = 0,
    time_count: u8,
    floor_count: u8,
    residue_count: u8,
    mapping_count: u8,
    mode_count: u8,
    maximum_codebook_dimensions: u16,
    maximum_codebook_entries: u32,
};

pub const VorbisSetup = struct {
    summary: VorbisSetupSummary,
    codebooks: []const VorbisCodebook,
    codebook_entries: []const VorbisCodebookEntry,
    huffman_nodes: []const VorbisHuffmanNode,
    codebook_multiplicands: []const u32,
    floors: []const VorbisFloor,
    residues: []const VorbisResidue,
    mappings: []const VorbisMapping,
    modes: []const VorbisMode,
};

pub const VorbisMode = struct {
    large_block: bool,
    mapping: u8,
};

pub const VorbisSetupStorage = struct {
    codebooks: []VorbisCodebook,
    codebook_entries: []VorbisCodebookEntry,
    huffman_nodes: []VorbisHuffmanNode,
    codebook_multiplicands: []u32,
    floors: []VorbisFloor,
    residues: []VorbisResidue,
    mappings: []VorbisMapping,
    modes: []VorbisMode,
};

/// Validate first to obtain exact entry, Huffman node, and multiplicand counts.
/// Returned slices borrow `storage`.
pub fn parseVorbisSetup(
    packet: []const u8,
    channel_count: u8,
    storage: VorbisSetupStorage,
) !VorbisSetup {
    const summary = try parseVorbisSetupInternal(packet, channel_count, null);
    if (storage.codebooks.len < summary.codebook_count or
        summary.codebook_entry_count > std.math.maxInt(usize) or
        storage.codebook_entries.len < summary.codebook_entry_count or
        summary.huffman_node_count > std.math.maxInt(usize) or
        storage.huffman_nodes.len < summary.huffman_node_count or
        summary.codebook_multiplicand_count > std.math.maxInt(usize) or
        storage.codebook_multiplicands.len <
            summary.codebook_multiplicand_count or
        storage.floors.len < summary.floor_count or
        storage.residues.len < summary.residue_count or
        storage.mappings.len < summary.mapping_count or
        storage.modes.len < summary.mode_count)
        return error.VorbisSetupStorageTooSmall;
    const destination = VorbisSetupDestination{
        .codebooks = storage.codebooks[0..summary.codebook_count],
        .codebook_entries = storage.codebook_entries[0..@intCast(summary.codebook_entry_count)],
        .huffman_nodes = storage.huffman_nodes[0..@intCast(summary.huffman_node_count)],
        .codebook_multiplicands = storage.codebook_multiplicands[0..@intCast(summary.codebook_multiplicand_count)],
        .floors = storage.floors[0..summary.floor_count],
        .residues = storage.residues[0..summary.residue_count],
        .mappings = storage.mappings[0..summary.mapping_count],
        .modes = storage.modes[0..summary.mode_count],
    };
    _ = try parseVorbisSetupInternal(
        packet,
        channel_count,
        destination,
    );
    return .{
        .summary = summary,
        .codebooks = destination.codebooks,
        .codebook_entries = destination.codebook_entries,
        .huffman_nodes = destination.huffman_nodes,
        .codebook_multiplicands = destination.codebook_multiplicands,
        .floors = destination.floors,
        .residues = destination.residues,
        .mappings = destination.mappings,
        .modes = destination.modes,
    };
}

pub fn validateVorbisSetup(
    packet: []const u8,
    channel_count: u8,
) !VorbisSetupSummary {
    return parseVorbisSetupInternal(packet, channel_count, null);
}

pub fn requiredVorbisSetupPacketBytes(
    setup: VorbisSetup,
    channel_count: u8,
) !usize {
    var encoder = VorbisSetupPacketEncoder{};
    try encoder.writeSetup(setup, channel_count);
    return try encoder.byteCount();
}

pub fn encodeVorbisSetupPacket(
    destination: []u8,
    setup: VorbisSetup,
    channel_count: u8,
) ![]const u8 {
    const required = try requiredVorbisSetupPacketBytes(
        setup,
        channel_count,
    );
    if (destination.len < required)
        return error.VorbisSetupOutputTooSmall;
    try rejectVorbisSetupOverlap(
        destination[0..required],
        setup,
    );
    @memset(destination[0..required], 0);
    var encoder = VorbisSetupPacketEncoder{
        .destination = destination[7..required],
    };
    try encoder.writeSetup(setup, channel_count);
    if (try encoder.byteCount() != required)
        return error.InvalidVorbisSetupState;
    @memcpy(destination[0..7], "\x05vorbis");
    return destination[0..required];
}

pub const VorbisSetupPacketEncoder = struct {
    destination: ?[]u8 = null,
    bit_offset: usize = 0,

    fn writeSetup(
        self: *VorbisSetupPacketEncoder,
        setup: VorbisSetup,
        channel_count: u8,
    ) !void {
        if (channel_count == 0)
            return error.InvalidVorbisChannelCount;
        if (setup.codebooks.len == 0 or setup.codebooks.len > 256)
            return error.InvalidVorbisSetupCodebookCount;
        if (setup.summary.time_count == 0 or
            setup.summary.time_count > 64)
            return error.InvalidVorbisTimeCount;
        try validateVorbisSetupSliceCounts(setup);

        try self.write(
            @as(u32, @intCast(setup.codebooks.len - 1)),
            8,
        );
        var entry_count: u64 = 0;
        var node_count: u64 = 0;
        var multiplicand_count: u64 = 0;
        var maximum_dimensions: u16 = 0;
        var maximum_entries: u32 = 0;
        for (setup.codebooks) |codebook| {
            const entries = try vorbisSetupSlice(
                VorbisCodebookEntry,
                setup.codebook_entries,
                codebook.entry_offset,
                codebook.entries,
            );
            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            try self.writeCodebook(
                codebook,
                entries,
                multiplicands,
            );
            entry_count = std.math.add(
                u64,
                entry_count,
                codebook.entries,
            ) catch return error.VorbisSetupSizeOverflow;
            node_count = std.math.add(
                u64,
                node_count,
                if (codebook.active_entry_count > 1)
                    codebook.active_entry_count - 1
                else
                    0,
            ) catch return error.VorbisSetupSizeOverflow;
            multiplicand_count = std.math.add(
                u64,
                multiplicand_count,
                codebook.multiplicand_count,
            ) catch return error.VorbisSetupSizeOverflow;
            maximum_dimensions = @max(
                maximum_dimensions,
                codebook.dimensions,
            );
            maximum_entries = @max(
                maximum_entries,
                codebook.entries,
            );
        }

        try self.write(
            setup.summary.time_count - 1,
            6,
        );
        for (0..setup.summary.time_count) |_|
            try self.write(0, 16);

        try self.write(
            @as(u32, @intCast(setup.floors.len - 1)),
            6,
        );
        for (setup.floors) |floor|
            try self.writeFloor(floor, setup.codebooks);

        try self.write(
            @as(u32, @intCast(setup.residues.len - 1)),
            6,
        );
        for (setup.residues) |residue|
            try self.writeResidue(residue, setup.codebooks);

        try self.write(
            @as(u32, @intCast(setup.mappings.len - 1)),
            6,
        );
        for (setup.mappings) |mapping| {
            try self.writeMapping(
                mapping,
                channel_count,
                setup.floors.len,
                setup.residues.len,
            );
        }

        try self.write(
            @as(u32, @intCast(setup.modes.len - 1)),
            6,
        );
        for (setup.modes) |mode| {
            try self.write(@intFromBool(mode.large_block), 1);
            try self.write(0, 16);
            try self.write(0, 16);
            if (mode.mapping >= setup.mappings.len)
                return error.InvalidVorbisModeMapping;
            try self.write(mode.mapping, 8);
        }
        try self.write(1, 1);

        const expected = VorbisSetupSummary{
            .codebook_count = @intCast(setup.codebooks.len),
            .codebook_entry_count = entry_count,
            .huffman_node_count = node_count,
            .codebook_multiplicand_count = multiplicand_count,
            .time_count = setup.summary.time_count,
            .floor_count = @intCast(setup.floors.len),
            .residue_count = @intCast(setup.residues.len),
            .mapping_count = @intCast(setup.mappings.len),
            .mode_count = @intCast(setup.modes.len),
            .maximum_codebook_dimensions = maximum_dimensions,
            .maximum_codebook_entries = maximum_entries,
        };
        if (!std.meta.eql(expected, setup.summary))
            return error.InconsistentVorbisSetupSummary;
    }

    fn writeCodebook(
        self: *VorbisSetupPacketEncoder,
        codebook: VorbisCodebook,
        entries: []const VorbisCodebookEntry,
        multiplicands: []const u32,
    ) !void {
        if (codebook.dimensions == 0 or codebook.entries == 0 or
            codebook.entries > 0xffffff)
            return error.InvalidVorbisCodebook;
        if (entries.len != codebook.entries)
            return error.InvalidVorbisCodebook;

        var length_counts = [_]u32{0} ** 32;
        var active_entries: u32 = 0;
        for (entries) |entry| {
            if (entry.length > 32)
                return error.InvalidVorbisCodebookLengths;
            if (entry.length != 0) {
                length_counts[entry.length - 1] += 1;
                active_entries += 1;
            }
        }
        try validateVorbisCodebookTree(
            &length_counts,
            active_entries,
        );
        if (active_entries != codebook.active_entry_count)
            return error.InconsistentVorbisCodebook;

        try self.write(0x564342, 24);
        try self.write(codebook.dimensions, 16);
        try self.write(codebook.entries, 24);
        try self.write(0, 1);
        const sparse = active_entries != codebook.entries;
        try self.write(@intFromBool(sparse), 1);
        for (entries) |entry| {
            if (sparse) try self.write(
                @intFromBool(entry.length != 0),
                1,
            );
            if (entry.length != 0)
                try self.write(entry.length - 1, 5);
        }

        if (codebook.lookup_type > 2)
            return error.UnsupportedVorbisCodebookLookup;
        try self.write(codebook.lookup_type, 4);
        if (codebook.lookup_type == 0) {
            if (codebook.multiplicand_count != 0 or
                multiplicands.len != 0)
                return error.InconsistentVorbisCodebook;
            return;
        }

        const expected_multiplicands: u64 =
            if (codebook.lookup_type == 1)
                vorbisLookupOneValues(
                    codebook.entries,
                    codebook.dimensions,
                )
            else
                @as(u64, codebook.entries) * codebook.dimensions;
        if (codebook.multiplicand_count != expected_multiplicands or
            multiplicands.len != expected_multiplicands)
            return error.InconsistentVorbisCodebook;
        try self.write(
            try vorbisFloat32PackExact(codebook.minimum_value),
            32,
        );
        try self.write(
            try vorbisFloat32PackExact(codebook.delta_value),
            32,
        );
        var maximum_multiplicand: u32 = 0;
        for (multiplicands) |value|
            maximum_multiplicand = @max(maximum_multiplicand, value);
        const value_bits: u6 = @max(
            1,
            vorbisILog(maximum_multiplicand),
        );
        if (value_bits > 16)
            return error.VorbisCodebookMultiplicandTooLarge;
        try self.write(value_bits - 1, 4);
        try self.write(@intFromBool(codebook.sequence), 1);
        for (multiplicands) |value|
            try self.write(value, value_bits);
    }

    fn writeFloor(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloor,
        codebooks: []const VorbisCodebook,
    ) !void {
        switch (floor) {
            .zero => |zero| try self.writeFloorZero(
                zero,
                codebooks,
            ),
            .one => |one| try self.writeFloorOne(
                one,
                codebooks,
            ),
        }
    }

    fn writeFloorZero(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloorZero,
        codebooks: []const VorbisCodebook,
    ) !void {
        if (floor.order == 0 or floor.rate == 0 or
            floor.bark_map_size == 0 or floor.book_count == 0 or
            floor.book_count > 16)
            return error.InvalidVorbisFloorConfiguration;
        try self.write(0, 16);
        try self.write(floor.order, 8);
        try self.write(floor.rate, 16);
        try self.write(floor.bark_map_size, 16);
        try self.write(floor.amplitude_bits, 6);
        try self.write(floor.amplitude_offset, 8);
        try self.write(floor.book_count - 1, 4);
        for (floor.books[0..floor.book_count]) |book| {
            if (book >= codebooks.len or
                codebooks[book].lookup_type == 0)
                return error.InvalidVorbisFloorCodebook;
            try self.write(book, 8);
        }
    }

    fn writeFloorOne(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloorOne,
        codebooks: []const VorbisCodebook,
    ) !void {
        try self.write(1, 16);
        try self.write(floor.partition_count, 5);
        var maximum_class: ?u4 = null;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            maximum_class = @max(maximum_class orelse 0, class);
            try self.write(class, 4);
        }
        const class_count: u5 = if (maximum_class) |highest|
            @as(u5, highest) + 1
        else
            0;
        if (floor.class_count != class_count)
            return error.InvalidVorbisFloorConfiguration;
        for (floor.classes[0..class_count]) |class| {
            if (class.dimensions == 0 or class.dimensions > 8)
                return error.InvalidVorbisFloorConfiguration;
            try self.write(class.dimensions - 1, 3);
            try self.write(class.subclass_bits, 2);
            if (class.subclass_bits != 0) {
                if (class.masterbook < 0 or
                    class.masterbook >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                try self.write(
                    @as(u32, @intCast(class.masterbook)),
                    8,
                );
            } else if (class.masterbook != -1) {
                return error.InvalidVorbisFloorConfiguration;
            }
            const subclass_count =
                @as(usize, 1) << @intCast(class.subclass_bits);
            for (class.subclass_books[0..subclass_count]) |book| {
                if (book < -1 or book >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                try self.write(@as(u32, @intCast(book + 1)), 8);
            }
        }
        if (floor.multiplier == 0 or floor.multiplier > 4)
            return error.InvalidVorbisFloorConfiguration;
        try self.write(floor.multiplier - 1, 2);
        try self.write(floor.range_bits, 4);

        var expected_points: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            expected_points = std.math.add(
                usize,
                expected_points,
                floor.classes[class].dimensions,
            ) catch return error.TooManyVorbisFloorPoints;
        }
        if (expected_points > floor.x_list.len or
            floor.point_count != expected_points or
            floor.x_list[0] != 0 or
            floor.x_list[1] !=
                @as(u16, 1) << @intCast(floor.range_bits))
            return error.InvalidVorbisFloorConfiguration;
        var point_index: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            for (0..floor.classes[class].dimensions) |_| {
                const point = floor.x_list[point_index];
                for (floor.x_list[0..point_index]) |existing| {
                    if (point == existing)
                        return error.DuplicateVorbisFloorPoint;
                }
                if (point >=
                    @as(u32, 1) << @intCast(floor.range_bits))
                    return error.InvalidVorbisFloorConfiguration;
                try self.write(point, floor.range_bits);
                point_index += 1;
            }
        }
    }

    fn writeResidue(
        self: *VorbisSetupPacketEncoder,
        residue: VorbisResidue,
        codebooks: []const VorbisCodebook,
    ) !void {
        if (residue.partition_size == 0 or
            residue.partition_size > 0x1000000 or
            residue.classification_count == 0 or
            residue.classification_count > 64)
            return error.InvalidVorbisResidueConfiguration;
        if (residue.classbook >= codebooks.len)
            return error.InvalidVorbisResidueCodebook;
        const classbook = codebooks[residue.classbook];
        if (!powerAtMost(
            residue.classification_count,
            classbook.dimensions,
            classbook.entries,
        )) return error.InvalidVorbisResidueClassbook;

        try self.write(@intFromEnum(residue.kind), 16);
        try self.write(residue.begin, 24);
        try self.write(residue.end, 24);
        try self.write(residue.partition_size - 1, 24);
        try self.write(residue.classification_count - 1, 6);
        try self.write(residue.classbook, 8);
        for (residue.cascades[0..residue.classification_count]) |cascade| {
            try self.write(cascade & 7, 3);
            const has_high_bits = cascade > 7;
            try self.write(@intFromBool(has_high_bits), 1);
            if (has_high_bits) try self.write(cascade >> 3, 5);
        }
        for (
            residue.cascades[0..residue.classification_count],
            0..,
        ) |cascade, classification| {
            for (0..8) |pass| {
                const book = residue.books[classification][pass];
                if (cascade & (@as(u8, 1) << @intCast(pass)) == 0) {
                    if (book != -1)
                        return error.InvalidVorbisResidueConfiguration;
                    continue;
                }
                if (book < 0 or book >= codebooks.len or
                    codebooks[@intCast(book)].lookup_type == 0 or
                    residue.partition_size %
                        codebooks[@intCast(book)].dimensions != 0)
                    return error.InvalidVorbisResidueCodebook;
                try self.write(@as(u32, @intCast(book)), 8);
            }
        }
    }

    fn writeMapping(
        self: *VorbisSetupPacketEncoder,
        mapping: VorbisMapping,
        channel_count: u8,
        floor_count: usize,
        residue_count: usize,
    ) !void {
        if (mapping.submap_count == 0 or
            mapping.submap_count > 16)
            return error.InvalidVorbisMapping;
        if (channel_count == 1 and mapping.coupling_step_count != 0)
            return error.InvalidVorbisChannelCoupling;
        try self.write(0, 16);
        const multiple_submaps = mapping.submap_count > 1;
        try self.write(@intFromBool(multiple_submaps), 1);
        if (multiple_submaps)
            try self.write(mapping.submap_count - 1, 4);
        const coupled = mapping.coupling_step_count != 0;
        try self.write(@intFromBool(coupled), 1);
        if (coupled) {
            try self.write(mapping.coupling_step_count - 1, 8);
            const channel_bits = vorbisILog(channel_count - 1);
            for (
                mapping.coupling_steps[0..mapping.coupling_step_count],
            ) |step| {
                if (step.magnitude == step.angle or
                    step.magnitude >= channel_count or
                    step.angle >= channel_count)
                    return error.InvalidVorbisChannelCoupling;
                try self.write(step.magnitude, channel_bits);
                try self.write(step.angle, channel_bits);
            }
        }
        try self.write(0, 2);
        if (multiple_submaps) {
            for (mapping.channel_mux[0..channel_count]) |mux| {
                if (mux >= mapping.submap_count)
                    return error.InvalidVorbisChannelMux;
                try self.write(mux, 4);
            }
        }
        for (mapping.submaps[0..mapping.submap_count]) |submap| {
            if (submap.floor >= floor_count)
                return error.InvalidVorbisMappingFloor;
            if (submap.residue >= residue_count)
                return error.InvalidVorbisMappingResidue;
            try self.write(0, 8);
            try self.write(submap.floor, 8);
            try self.write(submap.residue, 8);
        }
    }

    fn write(
        self: *VorbisSetupPacketEncoder,
        value: anytype,
        bit_count: u6,
    ) !void {
        const next_offset = std.math.add(
            usize,
            self.bit_offset,
            bit_count,
        ) catch return error.VorbisSetupSizeOverflow;
        if (self.destination) |destination| {
            if (next_offset > destination.len * 8)
                return error.VorbisSetupOutputTooSmall;
            const encoded: u32 = @intCast(value);
            for (0..bit_count) |index| {
                const destination_bit = self.bit_offset + index;
                destination[destination_bit / 8] |=
                    @as(u8, @intCast(
                        (encoded >> @intCast(index)) & 1,
                    )) << @intCast(destination_bit % 8);
            }
        }
        self.bit_offset = next_offset;
    }

    fn byteCount(self: *const VorbisSetupPacketEncoder) !usize {
        const payload_bytes = std.math.add(
            usize,
            self.bit_offset,
            7,
        ) catch return error.VorbisSetupSizeOverflow;
        return std.math.add(
            usize,
            7,
            payload_bytes / 8,
        ) catch return error.VorbisSetupSizeOverflow;
    }
};

pub fn validateVorbisSetupSliceCounts(setup: VorbisSetup) !void {
    if (setup.floors.len == 0 or setup.floors.len > 64 or
        setup.residues.len == 0 or setup.residues.len > 64 or
        setup.mappings.len == 0 or setup.mappings.len > 64 or
        setup.modes.len == 0 or setup.modes.len > 64)
        return error.InvalidVorbisSetupCount;
    if (setup.summary.codebook_count != setup.codebooks.len or
        setup.summary.floor_count != setup.floors.len or
        setup.summary.residue_count != setup.residues.len or
        setup.summary.mapping_count != setup.mappings.len or
        setup.summary.mode_count != setup.modes.len)
        return error.InconsistentVorbisSetupSummary;
}

pub fn vorbisSetupSlice(
    comptime T: type,
    values: []const T,
    offset: u64,
    count: u64,
) ![]const T {
    if (offset > std.math.maxInt(usize) or
        count > std.math.maxInt(usize))
        return error.InvalidVorbisSetupStorage;
    const start: usize = @intCast(offset);
    const length: usize = @intCast(count);
    if (start > values.len or length > values.len - start)
        return error.InvalidVorbisSetupStorage;
    return values[start..][0..length];
}

pub fn rejectVorbisSetupOverlap(
    destination: []u8,
    setup: VorbisSetup,
) !void {
    const destination_address = @intFromPtr(destination.ptr);
    inline for (.{
        setup.codebooks,
        setup.codebook_entries,
        setup.huffman_nodes,
        setup.codebook_multiplicands,
        setup.floors,
        setup.residues,
        setup.mappings,
        setup.modes,
    }) |values| {
        if (byteRangesOverlap(
            destination_address,
            destination.len,
            @intFromPtr(values.ptr),
            std.math.mul(
                usize,
                values.len,
                @sizeOf(@TypeOf(values[0])),
            ) catch return error.VorbisSetupSizeOverflow,
        )) return error.OverlappingVorbisSetupStorage;
    }
}

pub const VorbisBitReader = struct {
    bytes: []const u8,
    bit_offset: usize = 0,

    fn read(self: *VorbisBitReader, bit_count: u6) !u32 {
        if (@as(usize, bit_count) > self.remainingBits())
            return error.TruncatedVorbisSetup;
        var value: u32 = 0;
        for (0..bit_count) |index| {
            const source_bit = self.bit_offset + index;
            value |= @as(u32, (self.bytes[source_bit / 8] >>
                @intCast(source_bit % 8)) & 1) << @intCast(index);
        }
        self.bit_offset += bit_count;
        return value;
    }

    fn skip(self: *VorbisBitReader, bit_count: u64) !void {
        if (bit_count > self.remainingBits())
            return error.TruncatedVorbisSetup;
        self.bit_offset += @intCast(bit_count);
    }

    fn remainingBits(self: *const VorbisBitReader) usize {
        return self.bytes.len * 8 -| self.bit_offset;
    }
};

pub const VorbisSetupDestination = struct {
    codebooks: []VorbisCodebook,
    codebook_entries: []VorbisCodebookEntry,
    huffman_nodes: []VorbisHuffmanNode,
    codebook_multiplicands: []u32,
    floors: []VorbisFloor,
    residues: []VorbisResidue,
    mappings: []VorbisMapping,
    modes: []VorbisMode,
};

pub fn parseVorbisSetupInternal(
    packet: []const u8,
    channel_count: u8,
    destination: ?VorbisSetupDestination,
) !VorbisSetupSummary {
    if (packet.len < 8 or packet[0] != 5 or
        !std.mem.eql(u8, packet[1..7], "vorbis"))
        return error.InvalidVorbisSetupHeader;
    if (channel_count == 0) return error.InvalidVorbisChannelCount;

    var reader = VorbisBitReader{ .bytes = packet[7..] };
    const codebook_count: u16 = @intCast(try reader.read(8) + 1);
    var codebooks: [256]VorbisCodebook = undefined;
    var codebook_entry_count: u64 = 0;
    var huffman_node_count: u64 = 0;
    var codebook_multiplicand_count: u64 = 0;
    var maximum_dimensions: u16 = 0;
    var maximum_entries: u32 = 0;
    for (codebooks[0..codebook_count], 0..) |*codebook, index| {
        const entry_destination: ?[]VorbisCodebookEntry =
            if (destination) |output|
                output.codebook_entries[@intCast(codebook_entry_count)..]
            else
                null;
        const node_destination: ?[]VorbisHuffmanNode =
            if (destination) |output|
                output.huffman_nodes[@intCast(huffman_node_count)..]
            else
                null;
        const multiplicand_destination: ?[]u32 =
            if (destination) |output|
                output.codebook_multiplicands[@intCast(codebook_multiplicand_count)..]
            else
                null;
        codebook.* = try parseVorbisCodebook(
            &reader,
            codebook_entry_count,
            entry_destination,
            huffman_node_count,
            node_destination,
            codebook_multiplicand_count,
            multiplicand_destination,
        );
        codebook_entry_count = std.math.add(
            u64,
            codebook_entry_count,
            codebook.entries,
        ) catch return error.VorbisSetupSizeOverflow;
        huffman_node_count = std.math.add(
            u64,
            huffman_node_count,
            codebook.tree_node_count,
        ) catch return error.VorbisSetupSizeOverflow;
        codebook_multiplicand_count = std.math.add(
            u64,
            codebook_multiplicand_count,
            codebook.multiplicand_count,
        ) catch return error.VorbisSetupSizeOverflow;
        maximum_dimensions = @max(maximum_dimensions, codebook.dimensions);
        maximum_entries = @max(maximum_entries, codebook.entries);
        if (destination) |output| output.codebooks[index] = codebook.*;
    }

    const time_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..time_count) |_| {
        if (try reader.read(16) != 0)
            return error.UnsupportedVorbisTimeTransform;
    }

    const floor_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..floor_count) |index| {
        const floor: VorbisFloor = switch (try reader.read(16)) {
            0 => .{
                .zero = try parseVorbisFloorZero(
                    &reader,
                    codebooks[0..codebook_count],
                ),
            },
            1 => .{
                .one = try parseVorbisFloorOne(
                    &reader,
                    codebooks[0..codebook_count],
                ),
            },
            else => return error.UnsupportedVorbisFloorType,
        };
        if (destination) |output| output.floors[index] = floor;
    }

    const residue_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..residue_count) |index| {
        const residue = try parseVorbisResidue(
            &reader,
            codebooks[0..codebook_count],
        );
        if (destination) |output| output.residues[index] = residue;
    }

    const mapping_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..mapping_count) |index| {
        const mapping = try parseVorbisMapping(
            &reader,
            channel_count,
            floor_count,
            residue_count,
        );
        if (destination) |output| output.mappings[index] = mapping;
    }

    const mode_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..mode_count) |index| {
        const large_block = try reader.read(1) != 0;
        if (try reader.read(16) != 0 or try reader.read(16) != 0)
            return error.UnsupportedVorbisMode;
        const mapping: u8 = @intCast(try reader.read(8));
        if (mapping >= mapping_count)
            return error.InvalidVorbisModeMapping;
        if (destination) |output| {
            output.modes[index] = .{
                .large_block = large_block,
                .mapping = mapping,
            };
        }
    }
    if (try reader.read(1) != 1) return error.InvalidVorbisSetupFraming;

    return .{
        .codebook_count = codebook_count,
        .codebook_entry_count = codebook_entry_count,
        .huffman_node_count = huffman_node_count,
        .codebook_multiplicand_count = codebook_multiplicand_count,
        .time_count = time_count,
        .floor_count = floor_count,
        .residue_count = residue_count,
        .mapping_count = mapping_count,
        .mode_count = mode_count,
        .maximum_codebook_dimensions = maximum_dimensions,
        .maximum_codebook_entries = maximum_entries,
    };
}

pub const VorbisVectorCursor = struct {
    codebook: VorbisCodebook,
    multiplicands: []const u32,
    entry: u32,
    index_divisor: u64 = 1,
    explicit_offset: u64,
    last: f64 = 0,

    fn next(self: *VorbisVectorCursor) f64 {
        const multiplicand_index: usize =
            if (self.codebook.lookup_type == 1)
                @intCast(
                    (self.entry / self.index_divisor) %
                        self.multiplicands.len,
                )
            else blk: {
                const index: usize = @intCast(self.explicit_offset);
                self.explicit_offset += 1;
                break :blk index;
            };
        const decoded =
            @as(f64, @floatFromInt(
                self.multiplicands[multiplicand_index],
            )) *
            self.codebook.delta_value +
            self.codebook.minimum_value +
            self.last;
        if (self.codebook.sequence) self.last = decoded;
        if (self.codebook.lookup_type == 1)
            self.index_divisor *= self.multiplicands.len;
        return decoded;
    }
};

pub const VorbisVectorQuantization = struct {
    entry: u32,
    squared_error: f64,
};

pub const VorbisVectorBatchQuantization = struct {
    entries: []u32,
    squared_error: f64,
};

pub fn quantizeVorbisVector(
    comptime Float: type,
    setup: VorbisSetup,
    codebook_number: u8,
    target: []const Float,
) !VorbisVectorQuantization {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis vector quantization requires f32 or f64");
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    try validateVorbisVectorCodebookState(codebook, setup);
    if (target.len != codebook.dimensions)
        return error.InvalidVorbisQuantizationShape;
    for (target) |value| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisQuantizationTarget;
    }
    if (!std.math.isFinite(codebook.minimum_value) or
        !std.math.isFinite(codebook.delta_value))
        return error.InvalidVorbisSetupState;

    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    const multiplicands = try vorbisSetupSlice(
        u32,
        setup.codebook_multiplicands,
        codebook.multiplicand_offset,
        codebook.multiplicand_count,
    );
    const expected_multiplicands: u64 =
        if (codebook.lookup_type == 1)
            vorbisLookupOneValues(
                codebook.entries,
                codebook.dimensions,
            )
        else
            @as(u64, codebook.entries) * codebook.dimensions;
    if (codebook.multiplicand_count != expected_multiplicands or
        multiplicands.len == 0)
        return error.InvalidVorbisSetupState;

    var best_entry: ?u32 = null;
    var best_error = std.math.inf(f128);
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var index_divisor: u64 = 1;
        var explicit_offset =
            @as(u64, @intCast(entry_number)) * codebook.dimensions;
        var last: f64 = 0;
        var error_sum: f128 = 0;
        for (target) |target_value| {
            const multiplicand_index: usize =
                if (codebook.lookup_type == 1)
                    @intCast(
                        (@as(u64, @intCast(entry_number)) /
                            index_divisor) %
                            multiplicands.len,
                    )
                else blk: {
                    const index: usize =
                        @intCast(explicit_offset);
                    explicit_offset += 1;
                    break :blk index;
                };
            const decoded =
                @as(f64, @floatFromInt(
                    multiplicands[multiplicand_index],
                )) *
                codebook.delta_value +
                codebook.minimum_value +
                last;
            if (!std.math.isFinite(decoded))
                return error.InvalidVorbisSetupState;
            if (codebook.sequence) last = decoded;
            if (codebook.lookup_type == 1)
                index_divisor *= multiplicands.len;
            const difference =
                @as(f128, @floatCast(target_value)) -
                @as(f128, @floatCast(decoded));
            error_sum += difference * difference;
        }
        if (error_sum < best_error) {
            best_error = error_sum;
            best_entry = @intCast(entry_number);
        }
    }
    return .{
        .entry = best_entry orelse
            return error.InvalidVorbisSetupState,
        .squared_error = @floatCast(best_error),
    };
}

pub fn quantizeVorbisVectors(
    comptime Float: type,
    setup: VorbisSetup,
    codebook_number: u8,
    targets: []const Float,
    destination: []u32,
) !VorbisVectorBatchQuantization {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis vector quantization requires f32 or f64");
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const dimensions: usize = setup.codebooks[codebook_number].dimensions;
    if (dimensions == 0)
        return error.InvalidVorbisSetupState;
    if (targets.len % dimensions != 0)
        return error.InvalidVorbisQuantizationShape;
    const vector_count = targets.len / dimensions;
    if (destination.len < vector_count)
        return error.VorbisQuantizationOutputTooSmall;

    const output = destination[0..vector_count];
    const output_bytes = std.mem.sliceAsBytes(output);
    if (vorbisSliceOverlapsBytes(Float, targets, output_bytes) or
        vorbisSliceOverlapsBytes(
            VorbisCodebook,
            setup.codebooks,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            VorbisCodebookEntry,
            setup.codebook_entries,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            VorbisHuffmanNode,
            setup.huffman_nodes,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            u32,
            setup.codebook_multiplicands,
            output_bytes,
        ))
        return error.OverlappingVorbisQuantization;

    var total_error: f128 = 0;
    for (0..vector_count) |index| {
        const start = index * dimensions;
        const quantized = try quantizeVorbisVector(
            Float,
            setup,
            codebook_number,
            targets[start .. start + dimensions],
        );
        total_error += quantized.squared_error;
    }
    for (output, 0..) |*entry, index| {
        const start = index * dimensions;
        entry.* = (try quantizeVorbisVector(
            Float,
            setup,
            codebook_number,
            targets[start .. start + dimensions],
        )).entry;
    }
    return .{
        .entries = output,
        .squared_error = @floatCast(total_error),
    };
}

pub const VorbisFloorZeroEncoding = struct {
    amplitude: u64 = 0,
    book_number: u8 = 0,
    entries: []const u32 = &.{},
};

pub const VorbisFloorOneEncoding = struct {
    used: bool = false,
    y_values: []const u32 = &.{},
};

pub const VorbisFloorOneFit = struct {
    encoding: VorbisFloorOneEncoding,
    squared_control_point_error: f64,
};

pub const VorbisAudioFloorOneStorageRequirements = struct {
    encodings: usize,
    y_values: usize,
    curve_values: usize,
};

pub fn VorbisAudioFloorOneScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        y_values: []u32,
        curves: []Float,
    };
}

pub fn VorbisAudioFloorOneStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        encodings: []VorbisFloorPacketEncoding,
        y_values: []u32,
        curves: []Float,
    };
}

pub fn VorbisAudioFloorOnePlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        encodings: []const VorbisFloorPacketEncoding,
        y_values: []const u32,
        curves: []const Float,
        coefficient_count: usize,
        squared_control_point_error: f64,
    };
}

pub const VorbisAudioResiduePreparationStorageRequirements = struct {
    floor_encodings: usize,
    floor_y_values: usize,
    floor_curve_values: usize,
    residue_values: usize,
    threshold_values: usize,
    coupling_values: usize,
    do_not_encode: usize,
};

pub fn VorbisAudioResiduePreparationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_fit_y_values: []u32,
        floor_fit_curves: []Float,
        floor_encodings: []VorbisFloorPacketEncoding,
        floor_y_values: []u32,
        floor_curves: []Float,
        residue_values: []Float,
        noise_thresholds: []Float,
        coupling_values: []Float,
        coupling_thresholds: []Float,
        do_not_encode: []bool,
    };
}

pub fn VorbisAudioResiduePreparationStorage(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_encodings: []VorbisFloorPacketEncoding,
        floor_y_values: []u32,
        floor_curves: []Float,
        residue_values: []Float,
        noise_thresholds: []Float,
        do_not_encode: []bool,
    };
}

pub fn VorbisAudioResiduePreparationPlan(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_encodings: []const VorbisFloorPacketEncoding,
        floor_y_values: []const u32,
        floor_curves: []const Float,
        residue_values: []const Float,
        noise_thresholds: []const Float,
        do_not_encode: []const bool,
        coefficient_count: usize,
        fixed_packet_bits: u32,
        squared_control_point_error: f64,
    };
}

pub const VorbisResidueEncoding = struct {
    do_not_encode: []const bool,
    classifications: []const u8,
    entries: []const u32,
};

pub fn VorbisResidueQuantizationScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
    };
}

pub const VorbisResidueQuantizationScratchRequirements = struct {
    partition_values: usize,
    vector_values: usize,
    classifications: usize,
};

pub const VorbisResidueQuantization = struct {
    encoding: VorbisResidueEncoding,
    squared_error: f64,
};

pub fn VorbisAdaptiveResidueScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("adaptive Vorbis quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
        best_classifications: []u8,
    };
}

pub const VorbisAdaptiveResidueConfig = struct {
    target_bits: u32,
    maximum_iterations: u8 = 32,
    initial_lambda: f64 = 0.000_001,
};

pub const VorbisAdaptiveResidueQuantization = struct {
    encoding: VorbisResidueEncoding,
    squared_error: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
    encoded_bits: u32,
    budget_met: bool,
    lambda: f64,
    iterations: u8,
};

pub const VorbisAudioResidueQuantizationConfig = struct {
    maximum_iterations: u8 = 32,
    initial_lambda: f64 = 0.000_001,
};

pub const VorbisAudioResidueSubmapResult = struct {
    target_bits: u32,
    encoded_bits: u32,
    budget_met: bool,
    squared_error: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
    lambda: f64,
    iterations: u8,
};

pub const VorbisAudioResidueQuantizationStorageRequirements = struct {
    encodings: usize,
    submap_results: usize,
    do_not_encode: usize,
    classifications: usize,
    entries: usize,
    partition_values: usize,
    vector_values: usize,
    classification_scratch: usize,
};

pub fn VorbisAudioResidueQuantizationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis audio residue quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
        best_classifications: []u8,
        output_classifications: []u8,
        entries: []u32,
        do_not_encode: []bool,
    };
}

pub const VorbisAudioResidueQuantizationStorage = struct {
    encodings: []VorbisResidueEncoding,
    submap_results: []VorbisAudioResidueSubmapResult,
    do_not_encode: []bool,
    classifications: []u8,
    entries: []u32,
};

pub const VorbisAudioResidueQuantizationPlan = struct {
    encodings: []const VorbisResidueEncoding,
    submap_results: []const VorbisAudioResidueSubmapResult,
    do_not_encode: []const bool,
    classifications: []const u8,
    entries: []const u32,
    allocation: VorbisResidueBitAllocation,
};

pub const VorbisPcmPacketEncodingStorageRequirements = struct {
    preparation: VorbisAudioResiduePreparationStorageRequirements,
    quantization: VorbisAudioResidueQuantizationStorageRequirements,
};

pub fn VorbisPcmPacketEncodingScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        preparation: VorbisAudioResiduePreparationScratch(Float),
        preparation_storage: VorbisAudioResiduePreparationStorage(Float),
        quantization: VorbisAudioResidueQuantizationScratch(Float),
        quantization_storage: VorbisAudioResidueQuantizationStorage,
    };
}

pub fn VorbisPcmPacketEncodingStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        preparation: VorbisAudioResiduePreparationStorage(Float),
        quantization: VorbisAudioResidueQuantizationStorage,
    };
}

pub fn VorbisPcmPacketEncodingTrial(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        packet: VorbisAudioPacketEncodingResult,
        commit: VorbisPcmPacketCommit,
        preparation: VorbisAudioResiduePreparationPlan(Float),
        quantization: VorbisAudioResidueQuantizationPlan,
    };
}

pub fn VorbisPcmPacketOrchestrationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet orchestration requires f32 or f64");
    return struct {
        analysis: VorbisPcmFrameAnalysisScratch(Float),
        analysis_storage: VorbisPcmFrameAnalysisStorage(Float),
        encoding: VorbisPcmPacketEncodingScratch(Float),
    };
}

pub const VorbisFloorPacketEncoding = union(enum) {
    zero: VorbisFloorZeroEncoding,
    one: VorbisFloorOneEncoding,
};

pub const VorbisAudioPacketEncoding = struct {
    mode_number: u8,
    previous_window_flag: ?bool = null,
    next_window_flag: ?bool = null,
    floors: []const VorbisFloorPacketEncoding,
    residues: []const VorbisResidueEncoding,
};

pub const VorbisAudioPacketPrefixEncoding = struct {
    mode_number: u8,
    previous_window_flag: ?bool = null,
    next_window_flag: ?bool = null,
    floors: []const VorbisFloorPacketEncoding,
};

pub const VorbisAudioPacketEncodingResult = struct {
    bytes: []const u8,
    bit_count: usize,
    header: VorbisAudioPacketHeader,
};

pub const VorbisAudioPacketFixedCost = struct {
    bit_count: u32,
    header: VorbisAudioPacketHeader,
    do_not_encode: []const bool,
};

pub const VorbisPacketWriter = struct {
    destination: []u8,
    bit_offset: usize = 0,
    count_only: bool = false,

    pub fn init(destination: []u8) VorbisPacketWriter {
        @memset(destination, 0);
        return .{ .destination = destination };
    }

    pub fn valid(self: *const VorbisPacketWriter) bool {
        if (self.count_only) return self.destination.len == 0;
        const capacity = std.math.mul(
            usize,
            self.destination.len,
            8,
        ) catch return false;
        return self.bit_offset <= capacity;
    }

    pub fn counting() VorbisPacketWriter {
        return .{
            .destination = &.{},
            .count_only = true,
        };
    }

    pub fn writeBits(
        self: *VorbisPacketWriter,
        value: u64,
        bit_count: u6,
    ) !void {
        if (bit_count < 64 and value >> bit_count != 0)
            return error.VorbisPacketValueDoesNotFit;
        try self.ensureCapacity(bit_count);
        self.writeBitsUnchecked(value, bit_count);
    }

    pub fn writeScalar(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) !void {
        const codeword = try writableVorbisCodeword(
            setup,
            codebook_number,
            entry_number,
        );
        const entry = codeword.entry;
        try self.ensureCapacity(entry.length);
        if (codeword.single_entry) {
            self.writeBitsUnchecked(0, 1);
            return;
        }
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            self.writeBitsUnchecked(
                (entry.codeword >> shift) & 1,
                1,
            );
        }
    }

    pub fn writeVectorEntry(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) !void {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        if (setup.codebooks[codebook_number].lookup_type == 0)
            return error.VorbisCodebookHasNoVectorLookup;
        try self.writeScalar(
            setup,
            codebook_number,
            entry_number,
        );
    }

    pub fn writeFloorZero(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        floor_number: u8,
        encoding: VorbisFloorZeroEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .zero => |value| value,
            .one => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorZeroState(floor, setup.codebooks);
        if (encoding.amplitude == 0) {
            if (encoding.entries.len != 0)
                return error.InvalidVorbisFloorEncoding;
            try self.ensureCapacity(floor.amplitude_bits);
            self.writeBitsUnchecked(0, floor.amplitude_bits);
            return;
        }
        if (floor.amplitude_bits == 0 or
            encoding.amplitude >>
                @intCast(floor.amplitude_bits) != 0 or
            encoding.book_number >= floor.book_count)
            return error.InvalidVorbisFloorEncoding;
        const codebook_number = floor.books[encoding.book_number];
        const dimensions = setup.codebooks[codebook_number].dimensions;
        const entry_count =
            (@as(usize, floor.order) + dimensions - 1) / dimensions;
        if (encoding.entries.len != entry_count)
            return error.InvalidVorbisFloorEncoding;

        var staged_entries: [255]u32 = undefined;
        @memcpy(
            staged_entries[0..entry_count],
            encoding.entries,
        );
        var required_bits: usize =
            @as(usize, floor.amplitude_bits) +
            vorbisILog(floor.book_count);
        for (staged_entries[0..entry_count]) |entry| {
            const codeword = try writableVorbisCodeword(
                setup,
                codebook_number,
                entry,
            );
            required_bits = try addVorbisPacketBits(
                required_bits,
                codeword.entry.length,
            );
        }
        try self.ensureCapacity(required_bits);
        self.writeBitsUnchecked(
            encoding.amplitude,
            floor.amplitude_bits,
        );
        self.writeBitsUnchecked(
            encoding.book_number,
            vorbisILog(floor.book_count),
        );
        for (staged_entries[0..entry_count]) |entry|
            self.writeScalarAssumeCapacity(
                setup,
                codebook_number,
                entry,
            );
    }

    pub fn writeFloorOne(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        floor_number: u8,
        encoding: VorbisFloorOneEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        if (!encoding.used) {
            if (encoding.y_values.len != 0)
                return error.InvalidVorbisFloorEncoding;
            try self.ensureCapacity(1);
            self.writeBitsUnchecked(0, 1);
            return;
        }
        if (encoding.y_values.len != floor.point_count)
            return error.InvalidVorbisFloorEncoding;
        var y_values: [65]u32 = undefined;
        @memcpy(
            y_values[0..floor.point_count],
            encoding.y_values,
        );
        const ranges = [_]u16{ 256, 128, 86, 64 };
        const value_bits = vorbisILog(ranges[floor.multiplier - 1] - 1);
        if (y_values[0] >= ranges[floor.multiplier - 1] or
            y_values[1] >= ranges[floor.multiplier - 1])
            return error.InvalidVorbisFloorEncoding;

        var classwords = [_]u32{0} ** 31;
        var required_bits: usize = 1 + 2 * @as(usize, value_bits);
        var value_offset: usize = 2;
        for (
            floor.partition_classes[0..floor.partition_count],
            0..,
        ) |class_index, partition| {
            const class = floor.classes[class_index];
            if (class.dimensions == 0 or class.dimensions > 8)
                return error.InvalidVorbisSetupState;
            const class_values =
                y_values[value_offset..][0..class.dimensions];
            if (class.subclass_bits != 0) {
                const masterbook: u8 = @intCast(class.masterbook);
                classwords[partition] =
                    try findVorbisFloorOneClassword(
                        setup,
                        class,
                        class_values,
                    );
                const masterword = try writableVorbisCodeword(
                    setup,
                    masterbook,
                    classwords[partition],
                );
                required_bits = try addVorbisPacketBits(
                    required_bits,
                    masterword.entry.length,
                );
            }
            var classword = classwords[partition];
            const mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (class_values) |value| {
                const book = class.subclass_books[classword & mask];
                classword >>= @intCast(class.subclass_bits);
                if (book < 0) {
                    if (value != 0)
                        return error.UnencodableVorbisFloorValue;
                    continue;
                }
                const codeword = try writableVorbisCodeword(
                    setup,
                    @intCast(book),
                    value,
                );
                required_bits = try addVorbisPacketBits(
                    required_bits,
                    codeword.entry.length,
                );
            }
            value_offset += class.dimensions;
        }
        if (value_offset != floor.point_count)
            return error.InvalidVorbisSetupState;
        try self.ensureCapacity(required_bits);

        self.writeBitsUnchecked(1, 1);
        self.writeBitsUnchecked(y_values[0], value_bits);
        self.writeBitsUnchecked(y_values[1], value_bits);
        value_offset = 2;
        for (
            floor.partition_classes[0..floor.partition_count],
            0..,
        ) |class_index, partition| {
            const class = floor.classes[class_index];
            var classword = classwords[partition];
            if (class.subclass_bits != 0) {
                self.writeScalarAssumeCapacity(
                    setup,
                    @intCast(class.masterbook),
                    classword,
                );
            }
            const mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (0..class.dimensions) |_| {
                const book = class.subclass_books[classword & mask];
                classword >>= @intCast(class.subclass_bits);
                if (book >= 0) {
                    self.writeScalarAssumeCapacity(
                        setup,
                        @intCast(book),
                        y_values[value_offset],
                    );
                }
                value_offset += 1;
            }
        }
    }

    pub fn writeResidue(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        residue_number: u8,
        vector_length: usize,
        encoding: VorbisResidueEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (residue_number >= setup.residues.len)
            return error.InvalidVorbisResidueNumber;
        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        const shape = try vorbisResidueShape(
            residue,
            vector_length,
            encoding.do_not_encode.len,
        );
        var all_skipped = true;
        for (encoding.do_not_encode) |skip|
            all_skipped = all_skipped and skip;
        const type_two_skipped =
            residue.kind == .two and all_skipped;
        const expected_classifications =
            if (type_two_skipped)
                0
            else
                shape.required_classifications;
        if (encoding.classifications.len !=
            expected_classifications)
            return error.InvalidVorbisResidueEncoding;
        for (encoding.classifications) |classification| {
            if (classification >= residue.classification_count)
                return error.InvalidVorbisResidueEncoding;
        }
        if (type_two_skipped or shape.partition_count == 0) {
            if (encoding.entries.len != 0)
                return error.InvalidVorbisResidueEncoding;
            return;
        }
        if (vorbisSliceOverlapsBytes(
            bool,
            encoding.do_not_encode,
            self.destination,
        ) or vorbisSliceOverlapsBytes(
            u8,
            encoding.classifications,
            self.destination,
        ) or vorbisSliceOverlapsBytes(
            u32,
            encoding.entries,
            self.destination,
        )) return error.OverlappingVorbisPacketEncoding;

        var required_bits: usize = 0;
        var entry_offset: usize = 0;
        try walkVorbisResidueEncoding(
            setup,
            residue,
            shape,
            encoding,
            &required_bits,
            &entry_offset,
            null,
        );
        if (entry_offset != encoding.entries.len)
            return error.InvalidVorbisResidueEncoding;
        try self.ensureCapacity(required_bits);

        entry_offset = 0;
        var ignored_bits: usize = 0;
        try walkVorbisResidueEncoding(
            setup,
            residue,
            shape,
            encoding,
            &ignored_bits,
            &entry_offset,
            self,
        );
        if (entry_offset != encoding.entries.len)
            return error.InvalidVorbisResidueEncoding;
    }

    pub fn writeAudioHeader(
        self: *VorbisPacketWriter,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mode_number: u8,
        previous_window_flag: ?bool,
        next_window_flag: ?bool,
    ) !VorbisAudioPacketHeader {
        if (mode_number >= setup.modes.len)
            return error.InvalidVorbisModeNumber;
        const mode = setup.modes[mode_number];
        const block_size = if (mode.large_block)
            identification.large_block_size
        else
            identification.small_block_size;
        const header = VorbisAudioPacketHeader{
            .mode_number = mode_number,
            .large_block = mode.large_block,
            .previous_window_flag = if (mode.large_block)
                previous_window_flag orelse
                    return error.MissingVorbisWindowFlag
            else
                null,
            .next_window_flag = if (mode.large_block)
                next_window_flag orelse
                    return error.MissingVorbisWindowFlag
            else
                null,
            .block_size = block_size,
            .payload_bit_offset = 0,
        };
        _ = try validateVorbisAudioDecodeState(
            identification,
            setup,
            header,
        );
        const mode_bits = vorbisILog(setup.modes.len - 1);
        const header_bits: usize =
            1 + @as(usize, mode_bits) +
            if (mode.large_block) @as(usize, 2) else 0;
        try self.ensureCapacity(header_bits);
        self.writeBitsUnchecked(0, 1);
        self.writeBitsUnchecked(mode_number, mode_bits);
        if (mode.large_block) {
            self.writeBitsUnchecked(
                @intFromBool(header.previous_window_flag orelse
                    return error.MissingVorbisWindowFlag),
                1,
            );
            self.writeBitsUnchecked(
                @intFromBool(header.next_window_flag orelse
                    return error.MissingVorbisWindowFlag),
                1,
            );
        }
        var written = header;
        written.payload_bit_offset = self.bit_offset;
        return written;
    }

    pub fn bytes(self: *const VorbisPacketWriter) []const u8 {
        if (!self.valid() or self.count_only) return &.{};
        const byte_count =
            self.bit_offset / 8 +
            @intFromBool(self.bit_offset % 8 != 0);
        return self.destination[0..byte_count];
    }

    fn ensureCapacity(
        self: *const VorbisPacketWriter,
        bit_count: usize,
    ) !void {
        if (!self.valid()) return error.InvalidVorbisPacketWriterState;
        const next = std.math.add(
            usize,
            self.bit_offset,
            bit_count,
        ) catch return error.VorbisAudioPacketSizeOverflow;
        if (self.count_only) return;
        const capacity = std.math.mul(
            usize,
            self.destination.len,
            8,
        ) catch return error.VorbisAudioPacketSizeOverflow;
        if (next > capacity)
            return error.VorbisAudioPacketOutputTooSmall;
    }

    fn writeBitsUnchecked(
        self: *VorbisPacketWriter,
        value: anytype,
        bit_count: u6,
    ) void {
        const encoded: u64 = @intCast(value);
        if (!self.count_only) {
            for (0..bit_count) |index| {
                const destination_bit = self.bit_offset + index;
                const mask =
                    @as(u8, 1) << @intCast(destination_bit % 8);
                if ((encoded >> @intCast(index)) & 1 != 0)
                    self.destination[destination_bit / 8] |= mask
                else
                    self.destination[destination_bit / 8] &= ~mask;
            }
        }
        self.bit_offset += bit_count;
    }

    fn writeScalarAssumeCapacity(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) void {
        const codebook = setup.codebooks[codebook_number];
        const start: usize = @intCast(codebook.entry_offset);
        const entry = setup.codebook_entries[start + entry_number];
        if (codebook.active_entry_count == 1) {
            self.writeBitsUnchecked(0, 1);
            return;
        }
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            self.writeBitsUnchecked(
                (entry.codeword >> shift) & 1,
                1,
            );
        }
    }
};

pub fn requiredVorbisAudioPacketBytes(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !usize {
    var writer = VorbisPacketWriter.counting();
    _ = try writeVorbisAudioPacket(
        &writer,
        identification,
        setup,
        encoding,
    );
    return writer.bit_offset / 8 +
        @intFromBool(writer.bit_offset % 8 != 0);
}

pub fn encodeVorbisAudioPacket(
    destination: []u8,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !VorbisAudioPacketEncodingResult {
    var counter = VorbisPacketWriter.counting();
    _ = try writeVorbisAudioPacket(
        &counter,
        identification,
        setup,
        encoding,
    );
    const required =
        counter.bit_offset / 8 +
        @intFromBool(counter.bit_offset % 8 != 0);
    if (destination.len < required)
        return error.VorbisAudioPacketOutputTooSmall;
    try rejectVorbisAudioPacketEncodingOverlap(
        destination[0..required],
        setup,
        encoding,
    );

    var writer = VorbisPacketWriter.init(
        destination[0..required],
    );
    const header = try writeVorbisAudioPacket(
        &writer,
        identification,
        setup,
        encoding,
    );
    if (writer.bit_offset != counter.bit_offset)
        return error.InvalidVorbisPacketBitOffset;
    return .{
        .bytes = writer.bytes(),
        .bit_count = writer.bit_offset,
        .header = header,
    };
}

pub fn measureVorbisAudioPacketFixedCost(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    do_not_encode_destination: []bool,
) !VorbisAudioPacketFixedCost {
    if (do_not_encode_destination.len <
        identification.channel_count)
        return error.VorbisAudioPacketSkipOutputTooSmall;
    const output = do_not_encode_destination[0..identification.channel_count];
    try rejectVorbisAudioPacketPrefixOutputOverlap(
        setup,
        encoding,
        output,
    );
    var staged = [_]bool{true} ** 255;
    var writer = VorbisPacketWriter.counting();
    const header = try writeVorbisAudioPacketPrefix(
        &writer,
        identification,
        setup,
        encoding,
        &staged,
    );
    const bit_count = std.math.cast(
        u32,
        writer.bit_offset,
    ) orelse return error.VorbisAudioPacketSizeOverflow;
    @memcpy(output, staged[0..identification.channel_count]);
    return .{
        .bit_count = bit_count,
        .header = header,
        .do_not_encode = output,
    };
}

pub fn writeVorbisAudioPacket(
    writer: *VorbisPacketWriter,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !VorbisAudioPacketHeader {
    var no_residue = [_]bool{true} ** 255;
    const header = try writeVorbisAudioPacketPrefix(
        writer,
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = encoding.floors,
        },
        &no_residue,
    );
    const mode = setup.modes[encoding.mode_number];
    const mapping = setup.mappings[mode.mapping];
    if (encoding.residues.len != mapping.submap_count)
        return error.InvalidVorbisAudioResidueEncoding;

    const coefficient_count = header.block_size / 2;
    for (0..mapping.submap_count) |submap_index| {
        var expected_skips = [_]bool{false} ** 255;
        var bundle_count: usize = 0;
        for (0..identification.channel_count) |channel| {
            if (mapping.channel_mux[channel] != submap_index)
                continue;
            expected_skips[bundle_count] = no_residue[channel];
            bundle_count += 1;
        }
        const residue_encoding = encoding.residues[submap_index];
        if (!std.mem.eql(
            bool,
            residue_encoding.do_not_encode,
            expected_skips[0..bundle_count],
        )) return error.InvalidVorbisAudioResidueEncoding;
        if (bundle_count == 0) {
            if (residue_encoding.classifications.len != 0 or
                residue_encoding.entries.len != 0)
                return error.InvalidVorbisAudioResidueEncoding;
            continue;
        }
        try writer.writeResidue(
            setup,
            mapping.submaps[submap_index].residue,
            coefficient_count,
            residue_encoding,
        );
    }
    return header;
}

pub fn writeVorbisAudioPacketPrefix(
    writer: *VorbisPacketWriter,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    no_residue: *[255]bool,
) !VorbisAudioPacketHeader {
    if (encoding.floors.len != identification.channel_count)
        return error.InvalidVorbisAudioFloorEncoding;
    const header = try writer.writeAudioHeader(
        identification,
        setup,
        encoding.mode_number,
        encoding.previous_window_flag,
        encoding.next_window_flag,
    );
    const mode = setup.modes[encoding.mode_number];
    const mapping = setup.mappings[mode.mapping];
    for (encoding.floors, 0..) |floor_encoding, channel| {
        const submap = mapping.submaps[mapping.channel_mux[channel]];
        switch (floor_encoding) {
            .zero => |value| {
                switch (setup.floors[submap.floor]) {
                    .zero => {},
                    .one => return error.InvalidVorbisAudioFloorEncoding,
                }
                try writer.writeFloorZero(
                    setup,
                    submap.floor,
                    value,
                );
                no_residue[channel] = value.amplitude == 0;
            },
            .one => |value| {
                switch (setup.floors[submap.floor]) {
                    .one => {},
                    .zero => return error.InvalidVorbisAudioFloorEncoding,
                }
                try writer.writeFloorOne(
                    setup,
                    submap.floor,
                    value,
                );
                no_residue[channel] = !value.used;
            },
        }
    }
    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (!no_residue[step.magnitude] or
            !no_residue[step.angle])
        {
            no_residue[step.magnitude] = false;
            no_residue[step.angle] = false;
        }
    }
    return header;
}

pub fn rejectVorbisAudioPacketPrefixOutputOverlap(
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    output: []bool,
) !void {
    const bytes = std.mem.sliceAsBytes(output);
    rejectVorbisSetupOverlap(bytes, setup) catch |err| switch (err) {
        error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPacketEncoding,
        else => return err,
    };
    if (vorbisSliceOverlapsBytes(
        VorbisFloorPacketEncoding,
        encoding.floors,
        bytes,
    )) return error.OverlappingVorbisPacketEncoding;
    for (encoding.floors) |floor| {
        const overlap = switch (floor) {
            .zero => |value| vorbisSliceOverlapsBytes(
                u32,
                value.entries,
                bytes,
            ),
            .one => |value| vorbisSliceOverlapsBytes(
                u32,
                value.y_values,
                bytes,
            ),
        };
        if (overlap) return error.OverlappingVorbisPacketEncoding;
    }
}

pub fn rejectVorbisAudioPacketEncodingOverlap(
    destination: []u8,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !void {
    try rejectVorbisPacketSetupOverlap(destination, setup);
    if (vorbisSliceOverlapsBytes(
        VorbisFloorPacketEncoding,
        encoding.floors,
        destination,
    ) or vorbisSliceOverlapsBytes(
        VorbisResidueEncoding,
        encoding.residues,
        destination,
    )) return error.OverlappingVorbisPacketEncoding;
    for (encoding.floors) |floor| {
        const overlap = switch (floor) {
            .zero => |value| vorbisSliceOverlapsBytes(
                u32,
                value.entries,
                destination,
            ),
            .one => |value| vorbisSliceOverlapsBytes(
                u32,
                value.y_values,
                destination,
            ),
        };
        if (overlap) return error.OverlappingVorbisPacketEncoding;
    }
    for (encoding.residues) |residue| {
        if (vorbisSliceOverlapsBytes(
            bool,
            residue.do_not_encode,
            destination,
        ) or vorbisSliceOverlapsBytes(
            u8,
            residue.classifications,
            destination,
        ) or vorbisSliceOverlapsBytes(
            u32,
            residue.entries,
            destination,
        )) return error.OverlappingVorbisPacketEncoding;
    }
}

pub fn rejectVorbisPacketSetupOverlap(
    destination: []u8,
    setup: VorbisSetup,
) !void {
    rejectVorbisSetupOverlap(destination, setup) catch |err| switch (err) {
        error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPacketEncoding,
        else => return err,
    };
}

pub fn walkVorbisResidueEncoding(
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    encoding: VorbisResidueEncoding,
    bit_count: *usize,
    entry_offset: *usize,
    writer: ?*VorbisPacketWriter,
) !void {
    const classbook = setup.codebooks[residue.classbook];
    const classwords: usize = classbook.dimensions;
    const effective_vectors: usize =
        if (residue.kind == .two)
            1
        else
            encoding.do_not_encode.len;
    for (0..8) |pass| {
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            if (pass == 0) {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        encoding.do_not_encode[vector])
                        continue;
                    const classifications = encoding.classifications[vector * shape.partition_count ..][partition..@min(
                        partition + classwords,
                        shape.partition_count,
                    )];
                    const classword =
                        findVorbisResidueClassword(
                            setup,
                            residue,
                            classifications,
                        ) orelse
                        return error.UnencodableVorbisResidueClassifications;
                    const codeword = try writableVorbisCodeword(
                        setup,
                        residue.classbook,
                        classword,
                    );
                    bit_count.* = try addVorbisPacketBits(
                        bit_count.*,
                        codeword.entry.length,
                    );
                    if (writer) |output| {
                        output.writeScalarAssumeCapacity(
                            setup,
                            residue.classbook,
                            classword,
                        );
                    }
                }
            }

            var classword_index: usize = 0;
            while (classword_index < classwords and
                partition < shape.partition_count) : (classword_index += 1)
            {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        encoding.do_not_encode[vector])
                        continue;
                    const classification = encoding.classifications[
                        vector * shape.partition_count + partition
                    ];
                    const book = residue.books[classification][pass];
                    if (book < 0) continue;
                    const codebook = setup.codebooks[@intCast(book)];
                    const vector_count =
                        @as(usize, residue.partition_size) /
                        codebook.dimensions;
                    if (vector_count >
                        encoding.entries.len -| entry_offset.*)
                        return error.InvalidVorbisResidueEncoding;
                    for (
                        encoding.entries[entry_offset.*..][0..vector_count],
                    ) |entry| {
                        const codeword = try writableVorbisCodeword(
                            setup,
                            @intCast(book),
                            entry,
                        );
                        bit_count.* = try addVorbisPacketBits(
                            bit_count.*,
                            codeword.entry.length,
                        );
                        if (writer) |output| {
                            output.writeScalarAssumeCapacity(
                                setup,
                                @intCast(book),
                                entry,
                            );
                        }
                    }
                    entry_offset.* += vector_count;
                }
                partition += 1;
            }
        }
    }
}

pub fn findVorbisResidueClassword(
    setup: VorbisSetup,
    residue: VorbisResidue,
    classifications: []const u8,
) ?u32 {
    const classbook = setup.codebooks[residue.classbook];
    const entries = vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    ) catch return null;
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var encoded: u32 = @intCast(entry_number);
        var omitted =
            @as(usize, classbook.dimensions) - classifications.len;
        while (omitted != 0) : (omitted -= 1)
            encoded /= residue.classification_count;
        var matches = true;
        var index = classifications.len;
        while (index != 0) {
            index -= 1;
            if (classifications[index] !=
                encoded % residue.classification_count)
            {
                matches = false;
                break;
            }
            encoded /= residue.classification_count;
        }
        if (matches) return @intCast(entry_number);
    }
    return null;
}

pub const WritableVorbisCodeword = struct {
    entry: VorbisCodebookEntry,
    single_entry: bool,
};

pub fn writableVorbisCodeword(
    setup: VorbisSetup,
    codebook_number: u8,
    entry_number: u32,
) !WritableVorbisCodeword {
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    if (entry_number >= entries.len or
        codebook.active_entry_count == 0 or
        codebook.active_entry_count > entries.len)
        return error.InvalidVorbisSetupState;
    const entry = entries[entry_number];
    if (entry.length == 0 or entry.length > 32)
        return error.InvalidVorbisCodebookEntry;
    const single_entry = codebook.active_entry_count == 1;
    if (single_entry) {
        if (entry.length != 1)
            return error.InvalidVorbisSetupState;
    } else {
        try validateVorbisCodewordForWrite(
            setup,
            codebook,
            entry_number,
            entry,
        );
    }
    return .{
        .entry = entry,
        .single_entry = single_entry,
    };
}

pub fn findVorbisFloorOneClassword(
    setup: VorbisSetup,
    class: VorbisFloorOneClass,
    values: []const u32,
) !u32 {
    const masterbook_number: u8 = @intCast(class.masterbook);
    const masterbook = setup.codebooks[masterbook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        masterbook.entry_offset,
        masterbook.entries,
    );
    const mask =
        (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var classword: u32 = @intCast(entry_number);
        var compatible = true;
        for (values) |value| {
            const book = class.subclass_books[classword & mask];
            classword >>= @intCast(class.subclass_bits);
            if (book < 0) {
                compatible = compatible and value == 0;
            } else {
                _ = writableVorbisCodeword(
                    setup,
                    @intCast(book),
                    value,
                ) catch {
                    compatible = false;
                    continue;
                };
            }
        }
        if (compatible) return @intCast(entry_number);
    }
    return error.UnencodableVorbisFloorValue;
}

pub fn addVorbisPacketBits(total: usize, count: usize) !usize {
    return std.math.add(
        usize,
        total,
        count,
    ) catch error.VorbisAudioPacketSizeOverflow;
}

pub fn validateVorbisCodewordForWrite(
    setup: VorbisSetup,
    codebook: VorbisCodebook,
    entry_number: u32,
    entry: VorbisCodebookEntry,
) !void {
    if (codebook.tree_node_count !=
        codebook.active_entry_count - 1)
        return error.InvalidVorbisSetupState;
    const nodes = try vorbisSetupSlice(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        codebook.tree_node_offset,
        codebook.tree_node_count,
    );
    var node_index: u32 = 0;
    for (0..entry.length) |depth| {
        if (node_index >= nodes.len)
            return error.InvalidVorbisSetupState;
        const shift: u5 = @intCast(entry.length - 1 - depth);
        const bit: usize = @intCast(
            (entry.codeword >> shift) & 1,
        );
        const branch = nodes[node_index].branches[bit];
        if (depth + 1 == entry.length) {
            if (branch != huffman_leaf_flag | entry_number)
                return error.InvalidVorbisSetupState;
        } else {
            if (branch & huffman_leaf_flag != 0 or
                branch >= nodes.len)
                return error.InvalidVorbisSetupState;
            node_index = branch;
        }
    }
}

pub const VorbisPacketReader = struct {
    packet: []const u8,
    bit_offset: usize = 0,

    pub fn init(packet: []const u8, bit_offset: usize) !VorbisPacketReader {
        const reader = VorbisPacketReader{
            .packet = packet,
            .bit_offset = bit_offset,
        };
        if (!reader.valid())
            return error.InvalidVorbisPacketBitOffset;
        return reader;
    }

    pub fn valid(self: *const VorbisPacketReader) bool {
        const bit_count = std.math.mul(usize, self.packet.len, 8) catch
            return false;
        return self.bit_offset <= bit_count;
    }

    /// Decode one scalar entry. Failures preserve the cursor.
    pub fn decodeScalar(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        codebook_number: u8,
    ) !u32 {
        if (!self.valid()) return error.InvalidVorbisPacketBitOffset;
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        const start = std.math.cast(usize, codebook.entry_offset) orelse
            return error.InvalidVorbisSetupState;
        if (codebook.entries == 0 or
            codebook.active_entry_count == 0 or
            codebook.active_entry_count > codebook.entries or
            start > setup.codebook_entries.len or
            codebook.entries > setup.codebook_entries.len - start)
            return error.InvalidVorbisSetupState;
        const entries =
            setup.codebook_entries[start..][0..codebook.entries];

        var trial = VorbisBitReader{
            .bytes = self.packet,
            .bit_offset = self.bit_offset,
        };
        if (codebook.active_entry_count == 1) {
            _ = readVorbisAudioBits(&trial, 1) catch |err| return err;
            for (entries, 0..) |entry, index| {
                if (entry.length != 0) {
                    self.bit_offset = trial.bit_offset;
                    return @intCast(index);
                }
            }
            return error.InvalidVorbisSetupState;
        }

        if (codebook.tree_node_count != codebook.active_entry_count - 1)
            return error.InvalidVorbisSetupState;
        const node_start =
            std.math.cast(usize, codebook.tree_node_offset) orelse
            return error.InvalidVorbisSetupState;
        if (codebook.tree_node_count >
            setup.huffman_nodes.len -| node_start)
            return error.InvalidVorbisSetupState;
        const nodes = setup.huffman_nodes[node_start..][0..codebook.tree_node_count];
        var node_index: u32 = 0;
        for (0..32) |_| {
            const bit =
                readVorbisAudioBits(&trial, 1) catch |err| return err;
            const branch = nodes[node_index].branches[bit];
            if (branch == invalid_huffman_branch)
                return error.InvalidVorbisCodeword;
            if (branch & huffman_leaf_flag != 0) {
                const entry_index = branch & ~huffman_leaf_flag;
                if (entry_index >= entries.len or
                    entries[entry_index].length == 0)
                    return error.InvalidVorbisSetupState;
                self.bit_offset = trial.bit_offset;
                return entry_index;
            }
            if (branch >= nodes.len)
                return error.InvalidVorbisSetupState;
            node_index = branch;
        }
        return error.InvalidVorbisCodeword;
    }

    /// Decode one VQ entry. Failures preserve the cursor and output.
    pub fn decodeVector(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        codebook_number: u8,
        output: []Float,
    ) !void {
        if (Float != f32 and Float != f64)
            @compileError("Vorbis vectors require f32 or f64 output");
        if (!self.valid()) return error.InvalidVorbisPacketBitOffset;
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (output.len < codebook.dimensions)
            return error.VorbisVectorOutputTooSmall;
        try self.decodeVectorPrefix(
            Float,
            setup,
            codebook_number,
            output[0..codebook.dimensions],
        );
    }

    fn decodeVectorPrefix(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        codebook_number: u8,
        output: []Float,
    ) !void {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (output.len > codebook.dimensions)
            return error.InvalidVorbisSetupState;
        var cursor = try self.decodeVectorCursor(setup, codebook_number);
        for (output) |*value| value.* = @floatCast(cursor.next());
    }

    fn decodeVectorCursor(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        codebook_number: u8,
    ) !VorbisVectorCursor {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (codebook.lookup_type == 0)
            return error.VorbisCodebookHasNoVectorLookup;
        if (codebook.lookup_type > 2 or
            codebook.dimensions == 0 or
            codebook.entries == 0)
            return error.InvalidVorbisSetupState;
        const start =
            std.math.cast(usize, codebook.multiplicand_offset) orelse
            return error.InvalidVorbisSetupState;
        if (start > setup.codebook_multiplicands.len or
            codebook.multiplicand_count >
                setup.codebook_multiplicands.len - start)
            return error.InvalidVorbisSetupState;
        const multiplicands = setup.codebook_multiplicands[start..][0..@intCast(codebook.multiplicand_count)];
        if (multiplicands.len == 0)
            return error.InvalidVorbisSetupState;
        const expected_multiplicands: u64 = if (codebook.lookup_type == 1)
            vorbisLookupOneValues(codebook.entries, codebook.dimensions)
        else
            @as(u64, codebook.entries) * codebook.dimensions;
        if (codebook.multiplicand_count != expected_multiplicands)
            return error.InvalidVorbisSetupState;

        const entry = try self.decodeScalar(setup, codebook_number);
        return .{
            .codebook = codebook,
            .multiplicands = multiplicands,
            .entry = entry,
            .explicit_offset = @as(u64, entry) * codebook.dimensions,
        };
    }

    /// Truncation consumes the packet remainder and returns an unused floor.
    pub fn decodeFloorZero(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        floor_number: u8,
        coefficients: []f64,
    ) !VorbisFloorZeroPacket {
        if (!self.valid()) return error.InvalidVorbisPacketBitOffset;
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .zero => |value| value,
            .one => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorZeroState(floor, setup.codebooks);
        if (coefficients.len < floor.order)
            return error.VorbisFloorOutputTooSmall;

        var trial = self.*;
        const amplitude = trial.readBits64(floor.amplitude_bits) catch |err|
            return self.finishTruncatedFloorZero(err);
        if (amplitude == 0) {
            self.bit_offset = trial.bit_offset;
            return .{ .used = false };
        }
        const book_number = trial.readBits(
            vorbisILog(floor.book_count),
        ) catch |err| return self.finishTruncatedFloorZero(err);
        if (book_number >= floor.book_count)
            return error.InvalidVorbisFloorBookNumber;
        const codebook_number = floor.books[book_number];
        const dimensions = setup.codebooks[codebook_number].dimensions;

        var decoded: [255]f64 = undefined;
        var decoded_count: usize = 0;
        var last: f64 = 0;
        while (decoded_count < floor.order) {
            const count = @min(
                @as(usize, dimensions),
                @as(usize, floor.order) - decoded_count,
            );
            trial.decodeVectorPrefix(
                f64,
                setup,
                codebook_number,
                decoded[decoded_count..][0..count],
            ) catch |err| return self.finishTruncatedFloorZero(err);
            for (decoded[decoded_count..][0..count]) |*value| {
                value.* += last;
            }
            last = decoded[decoded_count + count - 1];
            decoded_count += count;
        }
        @memcpy(coefficients[0..floor.order], decoded[0..floor.order]);
        self.bit_offset = trial.bit_offset;
        return .{
            .used = true,
            .amplitude = amplitude,
            .coefficient_count = floor.order,
        };
    }

    /// Truncation consumes the packet remainder and returns an unused floor.
    pub fn decodeFloorOne(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        floor_number: u8,
        y_values: []u32,
    ) !VorbisFloorOnePacket {
        if (!self.valid()) return error.InvalidVorbisPacketBitOffset;
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        if (y_values.len < floor.point_count)
            return error.VorbisFloorOutputTooSmall;

        var trial = self.*;
        const nonzero = trial.readBits(1) catch |err|
            return self.finishTruncatedFloorOne(err);
        if (nonzero == 0) {
            self.bit_offset = trial.bit_offset;
            return .{ .used = false };
        }

        const ranges = [_]u16{ 256, 128, 86, 64 };
        const range = ranges[floor.multiplier - 1];
        const value_bits = vorbisILog(range - 1);
        var decoded = [_]u32{0} ** 65;
        decoded[0] = trial.readBits(value_bits) catch |err|
            return self.finishTruncatedFloorOne(err);
        decoded[1] = trial.readBits(value_bits) catch |err|
            return self.finishTruncatedFloorOne(err);
        var offset: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class_index| {
            const class = floor.classes[class_index];
            var class_value: u32 = 0;
            if (class.subclass_bits != 0) {
                class_value = trial.decodeScalar(
                    setup,
                    @intCast(class.masterbook),
                ) catch |err| return self.finishTruncatedFloorOne(err);
            }
            const subclass_mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (0..class.dimensions) |_| {
                const book =
                    class.subclass_books[class_value & subclass_mask];
                class_value >>= @intCast(class.subclass_bits);
                decoded[offset] = if (book < 0)
                    0
                else
                    trial.decodeScalar(
                        setup,
                        @intCast(book),
                    ) catch |err|
                        return self.finishTruncatedFloorOne(err);
                offset += 1;
            }
        }
        if (offset != floor.point_count)
            return error.InvalidVorbisSetupState;
        @memcpy(y_values[0..floor.point_count], decoded[0..floor.point_count]);
        self.bit_offset = trial.bit_offset;
        return .{
            .used = true,
            .value_count = floor.point_count,
        };
    }

    /// End-of-packet returns decoded partial residue and consumes the remainder.
    pub fn decodeResidue(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue_number: u8,
        do_not_decode: []const bool,
        outputs: []const []Float,
        classification_scratch: []u8,
    ) !VorbisResiduePacket {
        if (Float != f32 and Float != f64)
            @compileError("Vorbis residue requires f32 or f64 output");
        if (!self.valid()) return error.InvalidVorbisPacketBitOffset;
        if (residue_number >= setup.residues.len)
            return error.InvalidVorbisResidueNumber;
        if (outputs.len == 0 or outputs.len > 255 or
            do_not_decode.len != outputs.len)
            return error.InvalidVorbisResidueBundle;
        const vector_length = outputs[0].len;
        for (outputs, 0..) |output, index| {
            if (output.len != vector_length)
                return error.InvalidVorbisResidueBundle;
            for (outputs[0..index]) |earlier| {
                if (vorbisSlicesOverlap(Float, output, earlier))
                    return error.OverlappingVorbisResidueOutput;
            }
            if (vorbisSliceOverlapsBytes(
                Float,
                output,
                classification_scratch,
            )) return error.OverlappingVorbisResidueScratch;
        }

        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        const shape = try vorbisResidueShape(
            residue,
            vector_length,
            outputs.len,
        );
        if (classification_scratch.len < shape.required_classifications)
            return error.VorbisResidueScratchTooSmall;

        for (outputs) |output| @memset(output, 0);
        if (shape.partition_count == 0) return .{};
        if (residue.kind == .two) {
            var all_skipped = true;
            for (do_not_decode) |skip| all_skipped = all_skipped and skip;
            if (all_skipped) return .{};
        }

        var trial = self.*;
        trial.decodeResidueInternal(
            Float,
            setup,
            residue,
            shape,
            do_not_decode,
            outputs,
            classification_scratch,
        ) catch |err| {
            if (err == error.TruncatedVorbisAudioPacket) {
                self.bit_offset = self.packet.len * 8;
                return .{ .truncated = true };
            }
            for (outputs) |output| @memset(output, 0);
            return err;
        };
        self.bit_offset = trial.bit_offset;
        return .{};
    }

    fn decodeResidueInternal(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue: VorbisResidue,
        shape: VorbisResidueShape,
        do_not_decode: []const bool,
        outputs: []const []Float,
        classifications: []u8,
    ) !void {
        const classbook = setup.codebooks[residue.classbook];
        const classwords: usize = classbook.dimensions;
        const effective_vectors: usize =
            if (residue.kind == .two) 1 else outputs.len;
        for (0..8) |pass| {
            var partition: usize = 0;
            while (partition < shape.partition_count) {
                if (pass == 0) {
                    for (0..effective_vectors) |vector| {
                        if (residue.kind != .two and do_not_decode[vector])
                            continue;
                        var encoded = try self.decodeScalar(
                            setup,
                            residue.classbook,
                        );
                        var classword = classwords;
                        while (classword != 0) {
                            classword -= 1;
                            const target = partition + classword;
                            if (target < shape.partition_count) {
                                classifications[
                                    vector * shape.partition_count + target
                                ] = @intCast(
                                    encoded % residue.classification_count,
                                );
                            }
                            encoded /= residue.classification_count;
                        }
                    }
                }

                var classword: usize = 0;
                while (classword < classwords and
                    partition < shape.partition_count) : (classword += 1)
                {
                    for (0..effective_vectors) |vector| {
                        if (residue.kind != .two and do_not_decode[vector])
                            continue;
                        const classification = classifications[
                            vector * shape.partition_count + partition
                        ];
                        const book = residue.books[classification][pass];
                        if (book >= 0) {
                            try self.decodeResiduePartition(
                                Float,
                                setup,
                                residue,
                                @intCast(book),
                                vector,
                                shape.begin +
                                    partition *
                                        @as(usize, residue.partition_size),
                                outputs,
                            );
                        }
                    }
                    partition += 1;
                }
            }
        }
    }

    fn decodeResiduePartition(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue: VorbisResidue,
        codebook_number: u8,
        vector: usize,
        partition_offset: usize,
        outputs: []const []Float,
    ) !void {
        const dimensions: usize =
            setup.codebooks[codebook_number].dimensions;
        const partition_size: usize = residue.partition_size;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            var decoded =
                try self.decodeVectorCursor(setup, codebook_number);
            for (0..dimensions) |component| {
                const within_partition = switch (residue.kind) {
                    .zero => entry_index +
                        component * vector_count,
                    .one, .two => entry_index * dimensions + component,
                };
                const flat_index =
                    partition_offset + within_partition;
                if (residue.kind == .two) {
                    const channel = flat_index % outputs.len;
                    const sample = flat_index / outputs.len;
                    outputs[channel][sample] +=
                        @as(Float, @floatCast(decoded.next()));
                } else {
                    outputs[vector][flat_index] +=
                        @as(Float, @floatCast(decoded.next()));
                }
            }
        }
    }

    fn finishTruncatedFloorZero(
        self: *VorbisPacketReader,
        err: anyerror,
    ) anyerror!VorbisFloorZeroPacket {
        if (err != error.TruncatedVorbisAudioPacket) return err;
        self.bit_offset = self.packet.len * 8;
        return .{ .used = false, .truncated = true };
    }

    fn readBits(self: *VorbisPacketReader, bit_count: u6) !u32 {
        var reader = VorbisBitReader{
            .bytes = self.packet,
            .bit_offset = self.bit_offset,
        };
        const value = try readVorbisAudioBits(&reader, bit_count);
        self.bit_offset = reader.bit_offset;
        return value;
    }

    fn readBits64(self: *VorbisPacketReader, bit_count: u6) !u64 {
        if (@as(usize, bit_count) > self.packet.len * 8 -| self.bit_offset)
            return error.TruncatedVorbisAudioPacket;
        var value: u64 = 0;
        for (0..bit_count) |index| {
            const source_bit = self.bit_offset + index;
            value |= @as(u64, (self.packet[source_bit / 8] >>
                @intCast(source_bit % 8)) & 1) << @intCast(index);
        }
        self.bit_offset += bit_count;
        return value;
    }

    fn finishTruncatedFloorOne(
        self: *VorbisPacketReader,
        err: anyerror,
    ) anyerror!VorbisFloorOnePacket {
        if (err != error.TruncatedVorbisAudioPacket) return err;
        self.bit_offset = self.packet.len * 8;
        return .{ .used = false, .truncated = true };
    }
};

pub const VorbisFloorZeroPacket = struct {
    used: bool,
    truncated: bool = false,
    amplitude: u64 = 0,
    coefficient_count: u8 = 0,
};

pub const VorbisFloorOnePacket = struct {
    used: bool,
    truncated: bool = false,
    value_count: u7 = 0,
};

pub const VorbisResiduePacket = struct {
    truncated: bool = false,
};

pub const VorbisResidueShape = struct {
    begin: usize,
    partition_count: usize,
    required_classifications: usize,
};

/// Returns the caller-owned classification scratch required by `decodeResidue`.
pub fn requiredVorbisResidueClassifications(
    residue: VorbisResidue,
    vector_length: usize,
    vector_count: usize,
) !usize {
    return (try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    )).required_classifications;
}

pub fn requiredVorbisResidueQuantizationScratch(
    setup: VorbisSetup,
    residue_number: u8,
    vector_length: usize,
    vector_count: usize,
) !VorbisResidueQuantizationScratchRequirements {
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    );
    var maximum_dimensions: usize = 0;
    for (
        residue.books[0..residue.classification_count],
    ) |passes| {
        for (passes) |book_number| {
            if (book_number >= 0) {
                maximum_dimensions = @max(
                    maximum_dimensions,
                    setup.codebooks[@intCast(book_number)].dimensions,
                );
            }
        }
    }
    return .{
        .partition_values = residue.partition_size,
        .vector_values = maximum_dimensions,
        .classifications = shape.required_classifications,
    };
}

pub fn requiredVorbisResidueQuantizationEntries(
    setup: VorbisSetup,
    residue_number: u8,
    vector_length: usize,
    vector_count: usize,
) !usize {
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    );
    if (shape.partition_count == 0) return 0;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    var classification_entries = [_]usize{0} ** 64;
    for (0..residue.classification_count) |classification| {
        for (0..8) |pass| {
            const book_number = residue.books[classification][pass];
            if (book_number < 0) continue;
            const dimensions: usize =
                setup.codebooks[@intCast(book_number)].dimensions;
            classification_entries[classification] = std.math.add(
                usize,
                classification_entries[classification],
                @as(usize, residue.partition_size) / dimensions,
            ) catch return error.VorbisResidueEntryCountOverflow;
        }
    }

    const classword_dimensions: usize = classbook.dimensions;
    var entries_per_vector: usize = 0;
    var partition: usize = 0;
    while (partition < shape.partition_count) {
        const group_count = @min(
            classword_dimensions,
            shape.partition_count - partition,
        );
        var maximum_group_entries: ?usize = null;
        for (classbook_entries, 0..) |entry, entry_number| {
            if (entry.length == 0) continue;
            var encoded: u32 = @intCast(entry_number);
            var omitted = classword_dimensions - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var group_entries: usize = 0;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                const classification: usize =
                    encoded % residue.classification_count;
                encoded /= residue.classification_count;
                group_entries = std.math.add(
                    usize,
                    group_entries,
                    classification_entries[classification],
                ) catch return error.VorbisResidueEntryCountOverflow;
            }
            maximum_group_entries = @max(
                maximum_group_entries orelse 0,
                group_entries,
            );
        }
        entries_per_vector = std.math.add(
            usize,
            entries_per_vector,
            maximum_group_entries orelse
                return error.InvalidVorbisSetupState,
        ) catch return error.VorbisResidueEntryCountOverflow;
        partition += group_count;
    }
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else vector_count;
    return std.math.mul(
        usize,
        entries_per_vector,
        effective_vectors,
    ) catch return error.VorbisResidueEntryCountOverflow;
}

pub fn quantizeVorbisResidue(
    comptime Float: type,
    setup: VorbisSetup,
    residue_number: u8,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    scratch: VorbisResidueQuantizationScratch(Float),
    classification_destination: []u8,
    entry_destination: []u32,
) !VorbisResidueQuantization {
    if (inputs.len == 0 or inputs.len > 255 or
        do_not_encode.len != inputs.len)
        return error.InvalidVorbisResidueBundle;
    const vector_length = inputs[0].len;
    for (inputs) |input| {
        if (input.len != vector_length)
            return error.InvalidVorbisResidueBundle;
        for (input) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisQuantizationTarget;
        }
    }
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        inputs.len,
    );
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            residue_number,
            vector_length,
            inputs.len,
        );
    var all_skipped = true;
    for (do_not_encode) |skip| all_skipped = all_skipped and skip;
    const type_two_skipped = residue.kind == .two and all_skipped;
    const classification_count =
        if (type_two_skipped) 0 else shape.required_classifications;
    if (classification_destination.len < classification_count)
        return error.VorbisResidueClassificationOutputTooSmall;
    if (classification_count == 0) {
        return .{
            .encoding = .{
                .do_not_encode = do_not_encode,
                .classifications = classification_destination[0..0],
                .entries = entry_destination[0..0],
            },
            .squared_error = 0,
        };
    }
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len < requirements.classifications)
        return error.VorbisResidueQuantizationScratchTooSmall;
    try rejectVorbisResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        scratch,
        classification_destination,
        entry_destination,
    );

    const planned_classifications =
        scratch.classifications[0..classification_count];
    try selectVorbisResidueClassifications(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        planned_classifications,
    );
    const entry_count = try countVorbisResidueQuantizedEntries(
        setup,
        residue,
        shape,
        do_not_encode,
        planned_classifications,
    );
    if (entry_destination.len < entry_count)
        return error.VorbisResidueEntryOutputTooSmall;

    const classifications =
        classification_destination[0..classification_count];
    const entries = entry_destination[0..entry_count];

    const total_error = try measureVorbisResidueQuantization(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        planned_classifications,
    );
    @memcpy(classifications, planned_classifications);
    var entry_offset: usize = 0;
    try assembleVorbisResidueEntries(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        classifications,
        entries,
        &entry_offset,
    );
    if (entry_offset != entries.len)
        return error.InvalidVorbisResidueEncoding;
    return .{
        .encoding = .{
            .do_not_encode = do_not_encode,
            .classifications = classifications,
            .entries = entries,
        },
        .squared_error = @floatCast(total_error),
    };
}

pub fn quantizeVorbisResidueAdaptive(
    comptime Float: type,
    setup: VorbisSetup,
    residue_number: u8,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    config: VorbisAdaptiveResidueConfig,
    scratch: VorbisAdaptiveResidueScratch(Float),
    classification_destination: []u8,
    entry_destination: []u32,
) !VorbisAdaptiveResidueQuantization {
    if (Float != f32 and Float != f64)
        @compileError("adaptive Vorbis quantization requires f32 or f64");
    if (config.maximum_iterations == 0 or
        config.maximum_iterations > 64 or
        !std.math.isFinite(config.initial_lambda) or
        config.initial_lambda <= 0)
        return error.InvalidVorbisAdaptiveResidueConfig;
    if (inputs.len == 0 or inputs.len > 255 or
        do_not_encode.len != inputs.len or
        noise_thresholds.len != inputs.len)
        return error.InvalidVorbisResidueBundle;
    const vector_length = inputs[0].len;
    for (inputs, noise_thresholds) |input, thresholds| {
        if (input.len != vector_length or
            thresholds.len != vector_length)
            return error.InvalidVorbisResidueBundle;
        for (input, thresholds) |value, threshold| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisQuantizationTarget;
            if (!std.math.isFinite(threshold) or threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
        }
    }
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        inputs.len,
    );
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            residue_number,
            vector_length,
            inputs.len,
        );
    var all_skipped = true;
    for (do_not_encode) |skip| all_skipped = all_skipped and skip;
    const classification_count =
        if (residue.kind == .two and all_skipped)
            0
        else
            shape.required_classifications;
    if (classification_destination.len < classification_count)
        return error.VorbisResidueClassificationOutputTooSmall;
    if (classification_count == 0) {
        return .{
            .encoding = .{
                .do_not_encode = do_not_encode,
                .classifications = classification_destination[0..0],
                .entries = entry_destination[0..0],
            },
            .squared_error = 0,
            .weighted_squared_error = 0,
            .audible_excess_power = 0,
            .encoded_bits = 0,
            .budget_met = true,
            .lambda = 0,
            .iterations = 0,
        };
    }
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len < requirements.classifications or
        scratch.best_classifications.len < requirements.classifications)
        return error.VorbisResidueQuantizationScratchTooSmall;
    try rejectVorbisAdaptiveResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        noise_thresholds,
        scratch,
        classification_destination,
        entry_destination,
    );

    const partition_scratch =
        scratch.partition[0..requirements.partition_values];
    const vector_scratch =
        scratch.vector[0..requirements.vector_values];
    const trial_classifications =
        scratch.classifications[0..classification_count];
    const best_classifications =
        scratch.best_classifications[0..classification_count];

    var iterations: u8 = 1;
    var selected = try planVorbisAdaptiveResidueCandidate(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        trial_classifications,
        0,
    );
    @memcpy(best_classifications, trial_classifications);
    if (selected.encoded_bits > config.target_bits) {
        var lower_lambda: f64 = 0;
        var upper_lambda: ?f64 = null;
        var lambda = config.initial_lambda;
        while (iterations < config.maximum_iterations and
            upper_lambda == null)
        {
            const candidate = try planVorbisAdaptiveResidueCandidate(
                Float,
                setup,
                residue,
                shape,
                do_not_encode,
                inputs,
                noise_thresholds,
                partition_scratch,
                vector_scratch,
                trial_classifications,
                lambda,
            );
            iterations += 1;
            if (candidate.encoded_bits <= config.target_bits) {
                upper_lambda = lambda;
                selected = candidate;
                @memcpy(best_classifications, trial_classifications);
            } else {
                lower_lambda = lambda;
                if (candidate.encoded_bits < selected.encoded_bits or
                    (candidate.encoded_bits == selected.encoded_bits and
                        candidate.metrics.weighted_squared_error <
                            selected.metrics.weighted_squared_error))
                {
                    selected = candidate;
                    @memcpy(best_classifications, trial_classifications);
                }
                lambda *= 2;
                if (!std.math.isFinite(lambda)) break;
            }
        }
        if (upper_lambda) |initial_upper| {
            var upper = initial_upper;
            while (iterations < config.maximum_iterations) {
                const midpoint = lower_lambda +
                    (upper - lower_lambda) / 2;
                if (midpoint == lower_lambda or midpoint == upper)
                    break;
                const candidate =
                    try planVorbisAdaptiveResidueCandidate(
                        Float,
                        setup,
                        residue,
                        shape,
                        do_not_encode,
                        inputs,
                        noise_thresholds,
                        partition_scratch,
                        vector_scratch,
                        trial_classifications,
                        midpoint,
                    );
                iterations += 1;
                if (candidate.encoded_bits <= config.target_bits) {
                    upper = midpoint;
                    if (candidate.metrics.weighted_squared_error <
                        selected.metrics.weighted_squared_error or
                        (candidate.metrics.weighted_squared_error ==
                            selected.metrics.weighted_squared_error and
                            candidate.encoded_bits >
                                selected.encoded_bits))
                    {
                        selected = candidate;
                        @memcpy(
                            best_classifications,
                            trial_classifications,
                        );
                    }
                } else {
                    lower_lambda = midpoint;
                }
            }
        }
    }

    const entry_count = try countVorbisResidueQuantizedEntries(
        setup,
        residue,
        shape,
        do_not_encode,
        best_classifications,
    );
    if (entry_destination.len < entry_count)
        return error.VorbisResidueEntryOutputTooSmall;
    const classifications =
        classification_destination[0..classification_count];
    const entries = entry_destination[0..entry_count];
    @memcpy(classifications, best_classifications);
    var entry_offset: usize = 0;
    try assembleVorbisResidueEntries(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        partition_scratch,
        vector_scratch,
        classifications,
        entries,
        &entry_offset,
    );
    if (entry_offset != entries.len)
        return error.InvalidVorbisResidueEncoding;
    return .{
        .encoding = .{
            .do_not_encode = do_not_encode,
            .classifications = classifications,
            .entries = entries,
        },
        .squared_error = @floatCast(selected.metrics.squared_error),
        .weighted_squared_error = @floatCast(
            selected.metrics.weighted_squared_error,
        ),
        .audible_excess_power = @floatCast(
            selected.metrics.audible_excess_power,
        ),
        .encoded_bits = selected.encoded_bits,
        .budget_met = selected.encoded_bits <= config.target_bits,
        .lambda = selected.lambda,
        .iterations = iterations,
    };
}

pub fn requiredVorbisCouplingScratch(
    channel_count: usize,
    vector_length: usize,
) !usize {
    if (channel_count == 0 or channel_count > 255)
        return error.InvalidVorbisChannelBundle;
    return std.math.mul(usize, channel_count, vector_length) catch
        return error.InvalidVorbisChannelBundle;
}

/// Applies retained channel coupling through caller-owned transactional scratch.
pub fn forwardCoupleVorbisChannels(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []Float,
    scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis channel coupling requires f32 or f64 vectors");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    for (channels, 0..) |channel, channel_index| {
        if (channel.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (channels[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(Float, channel, earlier))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(Float, channel, scratch))
            return error.OverlappingVorbisCouplingScratch;
        for (channel) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
        }
        @memcpy(
            scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
    }

    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude = scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle = scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (magnitude, angle) |*magnitude_value, *angle_value| {
            const first = magnitude_value.*;
            const second = angle_value.*;
            const first_dominates =
                @abs(first) > @abs(second);
            const coupled = if (first_dominates)
                .{
                    first,
                    if (first > 0)
                        first - second
                    else
                        second - first,
                }
            else
                .{
                    second,
                    if (second > 0)
                        first - second
                    else
                        second - first,
                };
            if (!std.math.isFinite(coupled[0]) or
                !std.math.isFinite(coupled[1]))
                return error.InvalidVorbisChannelValue;
            magnitude_value.* = coupled[0];
            angle_value.* = coupled[1];
        }
    }
    for (channels, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

/// Keeps inverse coupling within its continuous branch and the original bounds.
pub fn forwardCoupleVorbisNoiseThresholds(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []const Float,
    thresholds: []const []Float,
    value_scratch: []Float,
    threshold_scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis noise thresholds require f32 or f64");
    if (channels.len == 0 or channels.len > 255 or
        thresholds.len != channels.len)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (value_scratch.len < required or
        threshold_scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    if (vorbisSlicesOverlap(
        Float,
        value_scratch,
        threshold_scratch,
    )) return error.OverlappingVorbisCouplingScratch;
    for (channels, thresholds, 0..) |
        channel,
        channel_thresholds,
        channel_index,
    | {
        if (channel.len != vector_length or
            channel_thresholds.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (thresholds[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                channel_thresholds,
                earlier,
            ))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(
            Float,
            channel_thresholds,
            value_scratch,
        ) or vorbisSlicesOverlap(
            Float,
            channel_thresholds,
            threshold_scratch,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            channel_thresholds,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            value_scratch,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            threshold_scratch,
        ))
            return error.OverlappingVorbisCouplingScratch;
        for (channel, channel_thresholds) |value, threshold| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
            if (!std.math.isFinite(threshold) or threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
        }
        @memcpy(
            value_scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
        @memcpy(
            threshold_scratch[channel_index * vector_length ..][0..vector_length],
            channel_thresholds,
        );
    }

    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude_values =
            value_scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle_values =
            value_scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        const magnitude_thresholds =
            threshold_scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle_thresholds =
            threshold_scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (
            magnitude_values,
            angle_values,
            magnitude_thresholds,
            angle_thresholds,
        ) |
            *magnitude_value,
            *angle_value,
            *magnitude_threshold,
            *angle_threshold,
        | {
            const first = magnitude_value.*;
            const second = angle_value.*;
            const first_dominates = @abs(first) > @abs(second);
            const coupled_magnitude = if (first_dominates)
                first
            else
                second;
            const coupled_angle = if (first_dominates)
                if (first > 0) first - second else second - first
            else if (second > 0)
                first - second
            else
                second - first;
            var coupled_threshold = @min(
                magnitude_threshold.*,
                angle_threshold.*,
            ) / 2;
            if (coupled_angle != 0) {
                coupled_threshold = @min(
                    coupled_threshold,
                    @abs(coupled_magnitude) / 2,
                );
            }
            if (!std.math.isFinite(coupled_magnitude) or
                !std.math.isFinite(coupled_angle))
                return error.InvalidVorbisChannelValue;
            if (!std.math.isFinite(coupled_threshold) or
                coupled_threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
            magnitude_value.* = coupled_magnitude;
            angle_value.* = coupled_angle;
            magnitude_threshold.* = coupled_threshold;
            angle_threshold.* = coupled_threshold;
        }
    }
    for (thresholds, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            threshold_scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

/// Inverts retained channel coupling through caller-owned transactional scratch.
pub fn inverseCoupleVorbisChannels(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []Float,
    scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis channel coupling requires f32 or f64 vectors");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    for (channels, 0..) |channel, channel_index| {
        if (channel.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (channels[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(Float, channel, earlier))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(Float, channel, scratch))
            return error.OverlappingVorbisCouplingScratch;
        for (channel) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
        }
        @memcpy(
            scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
    }

    var remaining: usize = mapping.coupling_step_count;
    while (remaining != 0) {
        remaining -= 1;
        const step = mapping.coupling_steps[remaining];
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude = scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle = scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (magnitude, angle) |*magnitude_value, *angle_value| {
            const coupled_magnitude = magnitude_value.*;
            const coupled_angle = angle_value.*;
            const decoded = if (coupled_magnitude > 0)
                if (coupled_angle > 0)
                    .{
                        coupled_magnitude,
                        coupled_magnitude - coupled_angle,
                    }
                else
                    .{
                        coupled_magnitude + coupled_angle,
                        coupled_magnitude,
                    }
            else if (coupled_angle > 0)
                .{
                    coupled_magnitude,
                    coupled_magnitude + coupled_angle,
                }
            else
                .{
                    coupled_magnitude - coupled_angle,
                    coupled_magnitude,
                };
            if (!std.math.isFinite(decoded[0]) or
                !std.math.isFinite(decoded[1]))
                return error.InvalidVorbisChannelValue;
            magnitude_value.* = decoded[0];
            angle_value.* = decoded[1];
        }
    }
    for (channels, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

pub const VorbisAudioPacketHeader = struct {
    mode_number: u8,
    large_block: bool,
    previous_window_flag: ?bool,
    next_window_flag: ?bool,
    block_size: u16,
    payload_bit_offset: usize,
};

pub fn inferVorbisMissingPacketLargeBlock(
    identification: VorbisIdentification,
    following: VorbisAudioPacketHeader,
) !bool {
    if (identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    if (following.large_block) {
        if (following.block_size != identification.large_block_size)
            return error.InvalidVorbisAudioPacketHeader;
        const previous_window_flag = following.previous_window_flag orelse
            return error.InvalidVorbisAudioPacketHeader;
        _ = following.next_window_flag orelse
            return error.InvalidVorbisAudioPacketHeader;
        return previous_window_flag;
    }
    if (following.block_size != identification.small_block_size or
        following.previous_window_flag != null or
        following.next_window_flag != null)
        return error.InvalidVorbisAudioPacketHeader;
    if (identification.small_block_size ==
        identification.large_block_size)
        return false;
    return error.VorbisFollowingPacketBlockSizeUnavailable;
}

/// Resolves an ambiguous missing size from the following packet's exact granule.
/// The retained tracker must already have an absolute PCM position.
pub fn inferVorbisMissingPacketLargeBlockFromFollowingGranule(
    identification: VorbisIdentification,
    previous_block_size: usize,
    following: VorbisAudioPacketHeader,
    granules: VorbisGranuleTracker,
    following_granule_position: u64,
    following_end: bool,
) !bool {
    if (!granules.valid())
        return error.InvalidVorbisGranuleTrackerState;
    const header_inference = inferVorbisMissingPacketLargeBlock(
        identification,
        following,
    ) catch |err| switch (err) {
        error.VorbisFollowingPacketBlockSizeUnavailable => null,
        else => return err,
    };
    if (header_inference) |large_block| return large_block;
    if (granules.ended)
        return error.VorbisGranuleStreamAlreadyEnded;
    if (following_end or following_granule_position == unknown_granule)
        return error.VorbisFollowingGranuleUnavailable;
    const position_offset = granules.position_offset orelse
        return error.VorbisFollowingGranuleUnavailable;
    if (previous_block_size != identification.small_block_size and
        previous_block_size != identification.large_block_size)
        return error.InvalidVorbisPreviousBlockSize;

    const declared_end: i64 = @bitCast(following_granule_position);
    const candidate_sizes = [_]u16{
        identification.small_block_size,
        identification.large_block_size,
    };
    for (candidate_sizes, 0..) |missing_block_size, candidate_index| {
        const nominal_sample_count = std.math.add(
            u64,
            previous_block_size / 4,
            missing_block_size / 2,
        ) catch return error.VorbisGranulePositionOverflow;
        const complete_sample_count = std.math.add(
            u64,
            nominal_sample_count,
            following.block_size / 4,
        ) catch return error.VorbisGranulePositionOverflow;
        const decoded_after = std.math.add(
            u64,
            granules.decoded_samples,
            complete_sample_count,
        ) catch return error.VorbisGranulePositionOverflow;
        if (decoded_after > std.math.maxInt(i64))
            return error.VorbisGranulePositionOverflow;
        const expected_end = std.math.add(
            i64,
            position_offset,
            @intCast(decoded_after),
        ) catch return error.VorbisGranulePositionOverflow;
        if (declared_end == expected_end)
            return candidate_index != 0;
    }
    return error.InvalidVorbisGranulePosition;
}

pub const VorbisPcmBlockAnalysisConfig = struct {
    transient_energy_ratio: f64 = 4,
    minimum_rms: f64 = 0.000_01,
};

pub const VorbisPcmBlockAnalysis = struct {
    recommended_large_block: bool,
    peak: f64,
    rms: f64,
    maximum_energy_ratio: f64,
    transient_segment: ?u16,
};

pub const VorbisPcmBlockClassifierConfig = struct {
    analysis: VorbisPcmBlockAnalysisConfig = .{},
    cross_block_energy_ratio: f64 = 3,
    stable_energy_ratio: f64 = 1.5,
    energy_smoothing: f64 = 0.25,
    minimum_short_blocks: u8 = 2,
};

pub const VorbisPcmBlockClassification = struct {
    analysis: VorbisPcmBlockAnalysis,
    recommended_large_block: bool,
    cross_block_energy_ratio: f64,
    short_blocks_remaining: u8,
};

pub const VorbisPcmBlockClassifier = struct {
    initialized: bool = false,
    smoothed_mean_square: f64 = 0,
    large_block: bool = true,
    short_blocks_remaining: u8 = 0,

    pub fn reset(self: *VorbisPcmBlockClassifier) void {
        self.* = .{};
    }

    pub fn valid(self: *const VorbisPcmBlockClassifier) bool {
        if (!self.initialized) {
            return self.smoothed_mean_square == 0 and
                self.large_block and
                self.short_blocks_remaining == 0;
        }
        return std.math.isFinite(self.smoothed_mean_square) and
            self.smoothed_mean_square >= 0 and
            (self.short_blocks_remaining == 0 or !self.large_block);
    }

    pub fn classify(
        self: *VorbisPcmBlockClassifier,
        comptime Float: type,
        channels: []const []const Float,
        small_block_size: u16,
        large_block_size: u16,
        config: VorbisPcmBlockClassifierConfig,
    ) !VorbisPcmBlockClassification {
        if (!self.valid())
            return error.InvalidVorbisPcmBlockClassifierState;
        try validateVorbisPcmBlockClassifierConfig(config);
        const analysis = try analyzeVorbisPcmBlock(
            Float,
            channels,
            small_block_size,
            large_block_size,
            config.analysis,
        );
        const current_mean_square = analysis.rms * analysis.rms;
        const floor_power =
            config.analysis.minimum_rms *
            config.analysis.minimum_rms;
        const reference_power = if (self.initialized)
            @max(self.smoothed_mean_square, floor_power)
        else
            @max(current_mean_square, floor_power);
        const bounded_current = @max(current_mean_square, floor_power);
        const cross_ratio = if (bounded_current == 0 and
            reference_power == 0)
            1
        else if (bounded_current == 0 or reference_power == 0)
            std.math.floatMax(f64)
        else
            @max(
                bounded_current / reference_power,
                reference_power / bounded_current,
            );
        var next_large = if (self.initialized)
            self.large_block
        else
            analysis.recommended_large_block;
        var next_hold = if (self.initialized)
            self.short_blocks_remaining
        else
            0;
        const transient =
            !analysis.recommended_large_block or
            (self.initialized and
                cross_ratio >= config.cross_block_energy_ratio);
        if (transient) {
            next_large = false;
            next_hold = config.minimum_short_blocks;
        } else if (next_hold != 0) {
            next_large = false;
            next_hold -= 1;
        } else if (cross_ratio <= config.stable_energy_ratio) {
            next_large = true;
        }

        const next_smoothed = if (self.initialized)
            self.smoothed_mean_square +
                config.energy_smoothing *
                    (current_mean_square -
                        self.smoothed_mean_square)
        else
            current_mean_square;
        if (!std.math.isFinite(next_smoothed) or next_smoothed < 0)
            return error.InvalidVorbisPcmBlockClassifierState;
        self.* = .{
            .initialized = true,
            .smoothed_mean_square = next_smoothed,
            .large_block = next_large,
            .short_blocks_remaining = next_hold,
        };
        return .{
            .analysis = analysis,
            .recommended_large_block = next_large,
            .cross_block_energy_ratio = cross_ratio,
            .short_blocks_remaining = next_hold,
        };
    }
};

pub const VorbisPsychoacousticConfig = struct {
    band_count: u8 = 24,
    absolute_threshold: f64 = 0.000_001,
    tonal_masking_offset_db: f64 = 14.5,
    noise_masking_offset_db: f64 = 5.5,
    lower_spread_db_per_bark: f64 = 27,
    upper_spread_db_per_bark: f64 = 12,
    quality: f64 = 0.75,
    maximum_masking_relaxation_db: f64 = 18,
};

/// Select a quality request on the conventional Vorbis q0 through q10 scale.
pub const VorbisQualityPreset = enum(u4) {
    q0 = 0,
    q1 = 1,
    q2 = 2,
    q3 = 3,
    q4 = 4,
    q5 = 5,
    q6 = 6,
    q7 = 7,
    q8 = 8,
    q9 = 9,
    q10 = 10,

    pub fn quality(self: VorbisQualityPreset) f64 {
        return @as(f64, @floatFromInt(@intFromEnum(self))) / 10;
    }

    pub fn applyTo(
        self: VorbisQualityPreset,
        config: VorbisPsychoacousticConfig,
    ) VorbisPsychoacousticConfig {
        var result = config;
        result.quality = self.quality();
        return result;
    }
};

pub const VorbisPcmQualityMeasurement = struct {
    sample_count: u64,
    reference_rms: f64,
    candidate_rms: f64,
    rms_error: f64,
    normalized_rms_error: f64,
    peak_absolute_error: f64,
    peak_sample_index: u64,
    optimal_candidate_gain: f64,
    gain_aligned_normalized_rms_error: f64,
    signal_to_noise_db: f64,
};

pub const VorbisPcmQualityMeter = struct {
    sample_count: u64 = 0,
    reference_energy: f128 = 0,
    candidate_energy: f128 = 0,
    cross_energy: f128 = 0,
    error_energy: f128 = 0,
    peak_absolute_error: f64 = 0,
    peak_sample_index: u64 = 0,

    pub fn valid(self: *const VorbisPcmQualityMeter) bool {
        if (!std.math.isFinite(self.reference_energy) or
            !std.math.isFinite(self.candidate_energy) or
            !std.math.isFinite(self.cross_energy) or
            !std.math.isFinite(self.error_energy) or
            !std.math.isFinite(self.peak_absolute_error) or
            self.reference_energy < 0 or
            self.candidate_energy < 0 or
            self.error_energy < 0 or
            self.peak_absolute_error < 0)
        {
            return false;
        }
        if (self.sample_count == 0) {
            return self.reference_energy == 0 and
                self.candidate_energy == 0 and
                self.cross_energy == 0 and
                self.error_energy == 0 and
                self.peak_absolute_error == 0 and
                self.peak_sample_index == 0;
        }
        const has_error_energy = self.error_energy != 0;
        const has_peak_error = self.peak_absolute_error != 0;
        if (self.reference_energy == 0 and
            (self.cross_energy != 0 or
                self.error_energy != self.candidate_energy))
        {
            return false;
        }
        if (self.candidate_energy == 0 and
            (self.cross_energy != 0 or
                self.error_energy != self.reference_energy))
        {
            return false;
        }
        if (self.error_energy == 0 and
            (self.reference_energy != self.candidate_energy or
                self.cross_energy != self.reference_energy))
        {
            return false;
        }
        return has_error_energy == has_peak_error and
            (has_peak_error or self.peak_sample_index == 0) and
            self.peak_sample_index < self.sample_count;
    }

    pub fn reset(self: *VorbisPcmQualityMeter) void {
        self.* = .{};
    }

    pub fn updateSample(
        self: *VorbisPcmQualityMeter,
        comptime Float: type,
        reference: Float,
        candidate: Float,
    ) !void {
        const reference_samples = [_]Float{reference};
        const candidate_samples = [_]Float{candidate};
        return self.update(
            Float,
            &.{&reference_samples},
            &.{&candidate_samples},
        );
    }

    pub fn update(
        self: *VorbisPcmQualityMeter,
        comptime Float: type,
        reference: []const []const Float,
        candidate: []const []const Float,
    ) !void {
        if (Float != f32 and Float != f64)
            @compileError("Vorbis PCM quality measurement requires f32 or f64");
        if (!self.valid()) return error.InvalidVorbisPcmQualityMeter;
        if (reference.len == 0 or reference.len != candidate.len)
            return error.InvalidVorbisPcmQualityShape;
        const frame_count = reference[0].len;
        if (frame_count == 0)
            return error.InvalidVorbisPcmQualityShape;
        for (reference, candidate) |reference_channel, candidate_channel| {
            if (reference_channel.len != frame_count or
                candidate_channel.len != frame_count)
            {
                return error.InvalidVorbisPcmQualityShape;
            }
            for (reference_channel, candidate_channel) |
                reference_sample,
                candidate_sample,
            | {
                if (!std.math.isFinite(reference_sample) or
                    !std.math.isFinite(candidate_sample))
                {
                    return error.NonFiniteVorbisPcmQualitySample;
                }
            }
        }
        const value_count = std.math.mul(
            usize,
            reference.len,
            frame_count,
        ) catch return error.VorbisPcmQualitySampleCountOverflow;
        const next_count = std.math.add(
            u64,
            self.sample_count,
            std.math.cast(u64, value_count) orelse
                return error.VorbisPcmQualitySampleCountOverflow,
        ) catch return error.VorbisPcmQualitySampleCountOverflow;

        var trial = self.*;
        var local_index: u64 = 0;
        for (reference, candidate) |reference_channel, candidate_channel| {
            for (reference_channel, candidate_channel) |
                reference_sample,
                candidate_sample,
            | {
                const reference_wide: f128 = @floatCast(reference_sample);
                const candidate_wide: f128 = @floatCast(candidate_sample);
                const difference = candidate_wide - reference_wide;
                const absolute_difference: f64 = @floatCast(@abs(difference));
                trial.reference_energy += reference_wide * reference_wide;
                trial.candidate_energy += candidate_wide * candidate_wide;
                trial.cross_energy += reference_wide * candidate_wide;
                trial.error_energy += difference * difference;
                if (absolute_difference > trial.peak_absolute_error) {
                    trial.peak_absolute_error = absolute_difference;
                    trial.peak_sample_index = self.sample_count + local_index;
                }
                local_index += 1;
            }
        }
        trial.sample_count = next_count;
        if (!trial.valid()) return error.VorbisPcmQualityAccumulationOverflow;
        self.* = trial;
    }

    pub fn measurement(
        self: *const VorbisPcmQualityMeter,
    ) !VorbisPcmQualityMeasurement {
        if (!self.valid()) return error.InvalidVorbisPcmQualityMeter;
        if (self.sample_count == 0)
            return error.EmptyVorbisPcmQualityMeasurement;
        if (self.reference_energy == 0)
            return error.SilentVorbisPcmQualityReference;
        const divisor: f128 = @floatFromInt(self.sample_count);
        const reference_rms_wide = @sqrt(self.reference_energy / divisor);
        const candidate_rms_wide = @sqrt(self.candidate_energy / divisor);
        const rms_error_wide = @sqrt(self.error_energy / divisor);
        const normalized_rms_error_wide =
            rms_error_wide / reference_rms_wide;
        const optimal_candidate_gain_wide = if (self.candidate_energy > 0)
            self.cross_energy / self.candidate_energy
        else
            0;
        const gain_aligned_energy = @max(
            0,
            self.reference_energy -
                self.cross_energy * self.cross_energy /
                    @max(self.candidate_energy, std.math.floatMin(f128)),
        );
        const gain_aligned_normalized_rms_error_wide =
            @sqrt(gain_aligned_energy / divisor) / reference_rms_wide;
        const signal_to_noise_db_wide = if (self.error_energy == 0)
            std.math.inf(f128)
        else
            10 * @log10(self.reference_energy / self.error_energy);
        return .{
            .sample_count = self.sample_count,
            .reference_rms = @floatCast(reference_rms_wide),
            .candidate_rms = @floatCast(candidate_rms_wide),
            .rms_error = @floatCast(rms_error_wide),
            .normalized_rms_error = @floatCast(normalized_rms_error_wide),
            .peak_absolute_error = self.peak_absolute_error,
            .peak_sample_index = self.peak_sample_index,
            .optimal_candidate_gain = @floatCast(optimal_candidate_gain_wide),
            .gain_aligned_normalized_rms_error = @floatCast(
                gain_aligned_normalized_rms_error_wide,
            ),
            .signal_to_noise_db = @floatCast(signal_to_noise_db_wide),
        };
    }
};

pub const VorbisPsychoacousticAnalysis = struct {
    silent: bool,
    active_band_count: u8,
    peak: f64,
    rms: f64,
    spectral_flatness: f64,
    tonality: f64,
    masking_relaxation_db: f64,
};

pub const VorbisAudioPsychoacousticStorageRequirements = struct {
    analyses: usize,
    floor_values: usize,
    threshold_values: usize,
};

pub fn VorbisAudioPsychoacousticScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisAudioPsychoacousticStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        analyses: []VorbisPsychoacousticAnalysis,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisAudioPsychoacousticPlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        analyses: []const VorbisPsychoacousticAnalysis,
        floor_targets: []const Float,
        noise_thresholds: []const Float,
        coefficient_count: usize,
    };
}

pub const VorbisRateDistortion = struct {
    within_mask: bool,
    maximum_noise_ratio: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
};

pub fn analyzeVorbisPsychoacoustics(
    comptime Float: type,
    spectrum: []const Float,
    sample_rate: u32,
    config: VorbisPsychoacousticConfig,
    floor_target: []Float,
    noise_threshold: []Float,
) !VorbisPsychoacousticAnalysis {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    if (spectrum.len < 32 or spectrum.len > 4096 or
        !std.math.isPowerOfTwo(spectrum.len) or
        floor_target.len != spectrum.len or
        noise_threshold.len != spectrum.len)
        return error.InvalidVorbisSpectrumShape;
    if (sample_rate == 0)
        return error.InvalidVorbisSampleRate;
    if (config.band_count == 0 or config.band_count > 64 or
        !std.math.isFinite(config.absolute_threshold) or
        config.absolute_threshold < 0 or
        !std.math.isFinite(config.tonal_masking_offset_db) or
        !std.math.isFinite(config.noise_masking_offset_db) or
        config.noise_masking_offset_db < 0 or
        config.tonal_masking_offset_db <
            config.noise_masking_offset_db or
        !std.math.isFinite(config.lower_spread_db_per_bark) or
        config.lower_spread_db_per_bark <= 0 or
        !std.math.isFinite(config.upper_spread_db_per_bark) or
        config.upper_spread_db_per_bark <= 0 or
        !std.math.isFinite(config.quality) or
        config.quality < 0 or config.quality > 1 or
        !std.math.isFinite(
            config.maximum_masking_relaxation_db,
        ) or
        config.maximum_masking_relaxation_db < 0 or
        config.maximum_masking_relaxation_db > 120)
        return error.InvalidVorbisPsychoacousticConfig;
    if (vorbisSlicesOverlap(
        Float,
        floor_target,
        noise_threshold,
    )) return error.OverlappingVorbisPsychoacousticOutput;

    var band_energy = [_]f128{0} ** 64;
    var band_log_power = [_]f128{0} ** 64;
    var band_counts = [_]u32{0} ** 64;
    var total_energy: f128 = 0;
    var total_log_power: f128 = 0;
    var peak: f128 = 0;
    const absolute_power =
        @as(f128, config.absolute_threshold) *
        @as(f128, config.absolute_threshold);
    const logarithm_floor =
        @max(absolute_power, std.math.floatMin(f128));

    for (spectrum, 0..) |coefficient, index| {
        if (!std.math.isFinite(coefficient))
            return error.InvalidVorbisSpectrumValue;
        const widened: f128 = @floatCast(coefficient);
        const magnitude = @abs(widened);
        const power = widened * widened;
        if (!std.math.isFinite(power))
            return error.InvalidVorbisSpectrumValue;
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        band_energy[band] += power;
        band_log_power[band] += @log(@max(power, logarithm_floor));
        band_counts[band] += 1;
        total_energy += power;
        total_log_power += @log(@max(power, logarithm_floor));
        peak = @max(peak, magnitude);
    }

    if (total_energy == 0) {
        @memset(floor_target, 0);
        @memset(noise_threshold, 0);
        return .{
            .silent = true,
            .active_band_count = 0,
            .peak = 0,
            .rms = 0,
            .spectral_flatness = 1,
            .tonality = 0,
            .masking_relaxation_db = 0,
        };
    }

    var band_mean_power = [_]f128{0} ** 64;
    var band_masker_power = [_]f128{0} ** 64;
    var active_band_count: u8 = 0;
    for (0..config.band_count) |band| {
        const count = band_counts[band];
        if (count == 0) continue;
        const denominator: f128 = @floatFromInt(count);
        const mean_power = band_energy[band] / denominator;
        band_mean_power[band] = mean_power;
        if (mean_power == 0) continue;
        active_band_count += 1;
        const geometric_mean =
            @exp(band_log_power[band] / denominator);
        const flatness = std.math.clamp(
            geometric_mean / mean_power,
            0,
            1,
        );
        const tonality = 1 - flatness;
        const offset_db =
            @as(f128, config.noise_masking_offset_db) +
            tonality *
                @as(
                    f128,
                    config.tonal_masking_offset_db -
                        config.noise_masking_offset_db,
                );
        band_masker_power[band] =
            mean_power * @exp(
                -offset_db *
                    (@as(f128, std.math.ln10) / 10),
            );
    }

    const nyquist_bark =
        vorbisBark(@as(f64, @floatFromInt(sample_rate)) / 2);
    const bark_per_band =
        nyquist_bark / @as(f64, @floatFromInt(config.band_count));
    const relaxation_db =
        (1 - config.quality) *
        config.maximum_masking_relaxation_db;
    const relaxation_power = @exp(
        @as(f128, relaxation_db) *
            (@as(f128, std.math.ln10) / 10),
    );
    var band_threshold_power = [_]f128{0} ** 64;
    for (0..config.band_count) |target_band| {
        var threshold = absolute_power;
        const target_bark =
            (@as(f64, @floatFromInt(target_band)) + 0.5) *
            bark_per_band;
        for (0..config.band_count) |source_band| {
            if (band_masker_power[source_band] == 0) continue;
            const source_bark =
                (@as(f64, @floatFromInt(source_band)) + 0.5) *
                bark_per_band;
            const distance = @abs(target_bark - source_bark);
            const slope = if (target_bark < source_bark)
                config.lower_spread_db_per_bark
            else
                config.upper_spread_db_per_bark;
            const attenuation = @exp(
                -@as(f128, distance * slope) *
                    (@as(f128, std.math.ln10) / 10),
            );
            threshold +=
                band_masker_power[source_band] * attenuation;
        }
        band_threshold_power[target_band] =
            threshold * relaxation_power;
    }

    for (0..spectrum.len) |index| {
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        const threshold = @sqrt(band_threshold_power[band]);
        const envelope = @sqrt(band_mean_power[band]);
        const floor_value = @max(threshold, envelope);
        if (!std.math.isFinite(threshold) or
            !std.math.isFinite(floor_value) or
            threshold > std.math.floatMax(Float) or
            floor_value > std.math.floatMax(Float))
            return error.InvalidVorbisPsychoacousticResult;
    }
    for (
        floor_target,
        noise_threshold,
        0..,
    ) |*floor_value, *threshold_value, index| {
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        const threshold = @sqrt(band_threshold_power[band]);
        threshold_value.* = @floatCast(threshold);
        floor_value.* = @floatCast(@max(
            threshold,
            @sqrt(band_mean_power[band]),
        ));
    }

    const denominator: f128 = @floatFromInt(spectrum.len);
    const mean_power = total_energy / denominator;
    const geometric_mean = @exp(total_log_power / denominator);
    const flatness = std.math.clamp(
        geometric_mean / mean_power,
        0,
        1,
    );
    return .{
        .silent = false,
        .active_band_count = active_band_count,
        .peak = @floatCast(peak),
        .rms = @floatCast(@sqrt(mean_power)),
        .spectral_flatness = @floatCast(flatness),
        .tonality = @floatCast(1 - flatness),
        .masking_relaxation_db = relaxation_db,
    };
}

pub fn requiredVorbisAudioPsychoacousticStorage(
    channel_count: usize,
    coefficient_count: usize,
) !VorbisAudioPsychoacousticStorageRequirements {
    if (channel_count == 0 or channel_count > 255)
        return error.InvalidVorbisChannelCount;
    if (coefficient_count < 32 or coefficient_count > 4096 or
        !std.math.isPowerOfTwo(coefficient_count))
        return error.InvalidVorbisSpectrumShape;
    const value_count = std.math.mul(
        usize,
        channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioPsychoacousticSizeOverflow;
    return .{
        .analyses = channel_count,
        .floor_values = value_count,
        .threshold_values = value_count,
    };
}

pub fn analyzeVorbisAudioPsychoacoustics(
    comptime Float: type,
    spectra: []const []const Float,
    sample_rate: u32,
    config: VorbisPsychoacousticConfig,
    scratch: VorbisAudioPsychoacousticScratch(Float),
    storage: VorbisAudioPsychoacousticStorage(Float),
) !VorbisAudioPsychoacousticPlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    if (spectra.len == 0 or spectra.len > 255)
        return error.InvalidVorbisChannelCount;
    const coefficient_count = spectra[0].len;
    const requirements = try requiredVorbisAudioPsychoacousticStorage(
        spectra.len,
        coefficient_count,
    );
    for (spectra) |spectrum| {
        if (spectrum.len != coefficient_count)
            return error.InvalidVorbisSpectrumBundle;
        for (spectrum) |coefficient| {
            if (!std.math.isFinite(coefficient))
                return error.InvalidVorbisSpectrumValue;
        }
    }
    if (scratch.floor_targets.len < requirements.floor_values or
        scratch.noise_thresholds.len <
            requirements.threshold_values)
        return error.VorbisAudioPsychoacousticScratchTooSmall;
    if (storage.analyses.len < requirements.analyses or
        storage.floor_targets.len < requirements.floor_values or
        storage.noise_thresholds.len <
            requirements.threshold_values)
        return error.VorbisAudioPsychoacousticStorageTooSmall;

    const trial_floor =
        scratch.floor_targets[0..requirements.floor_values];
    const trial_thresholds =
        scratch.noise_thresholds[0..requirements.threshold_values];
    const analyses = storage.analyses[0..requirements.analyses];
    const floor_targets =
        storage.floor_targets[0..requirements.floor_values];
    const noise_thresholds =
        storage.noise_thresholds[0..requirements.threshold_values];
    try rejectVorbisAudioPsychoacousticOverlap(
        Float,
        spectra,
        trial_floor,
        trial_thresholds,
        analyses,
        floor_targets,
        noise_thresholds,
    );

    var trial_analyses: [255]VorbisPsychoacousticAnalysis =
        undefined;
    for (spectra, 0..) |spectrum, channel| {
        const start = channel * coefficient_count;
        trial_analyses[channel] = try analyzeVorbisPsychoacoustics(
            Float,
            spectrum,
            sample_rate,
            config,
            trial_floor[start..][0..coefficient_count],
            trial_thresholds[start..][0..coefficient_count],
        );
    }

    @memcpy(floor_targets, trial_floor);
    @memcpy(noise_thresholds, trial_thresholds);
    @memcpy(analyses, trial_analyses[0..requirements.analyses]);
    return .{
        .analyses = analyses,
        .floor_targets = floor_targets,
        .noise_thresholds = noise_thresholds,
        .coefficient_count = coefficient_count,
    };
}

pub fn rejectVorbisAudioPsychoacousticOverlap(
    comptime Float: type,
    spectra: []const []const Float,
    trial_floor: []Float,
    trial_thresholds: []Float,
    analyses: []VorbisPsychoacousticAnalysis,
    floor_targets: []Float,
    noise_thresholds: []Float,
) !void {
    if (vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        trial_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        VorbisPsychoacousticAnalysis,
        analyses,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        VorbisPsychoacousticAnalysis,
        analyses,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        VorbisPsychoacousticAnalysis,
        analyses,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        VorbisPsychoacousticAnalysis,
        analyses,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        floor_targets,
        Float,
        noise_thresholds,
    ))
        return error.OverlappingVorbisAudioPsychoacousticStorage;

    inline for (.{
        trial_floor,
        trial_thresholds,
        analyses,
        floor_targets,
        noise_thresholds,
    }) |destination| {
        const destination_bytes = std.mem.sliceAsBytes(destination);
        if (vorbisSliceOverlapsBytes(
            []const Float,
            spectra,
            destination_bytes,
        )) return error.OverlappingVorbisAudioPsychoacousticStorage;
        for (spectra) |spectrum| {
            if (vorbisSliceOverlapsBytes(
                Float,
                spectrum,
                destination_bytes,
            )) return error.OverlappingVorbisAudioPsychoacousticStorage;
        }
    }
}

pub fn vorbisPsychoacousticBand(
    index: usize,
    coefficient_count: usize,
    sample_rate: u32,
    band_count: u8,
) usize {
    const frequency =
        (@as(f64, @floatFromInt(index)) + 0.5) *
        @as(f64, @floatFromInt(sample_rate)) /
        (2 * @as(f64, @floatFromInt(coefficient_count)));
    const nyquist_bark =
        vorbisBark(@as(f64, @floatFromInt(sample_rate)) / 2);
    return @min(
        @as(usize, @intFromFloat(@floor(
            vorbisBark(frequency) / nyquist_bark *
                @as(f64, @floatFromInt(band_count)),
        ))),
        band_count - 1,
    );
}

pub fn evaluateVorbisRateDistortion(
    comptime Float: type,
    original: []const Float,
    reconstructed: []const Float,
    noise_threshold: []const Float,
) !VorbisRateDistortion {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis rate-distortion evaluation requires f32 or f64");
    if (original.len == 0 or
        reconstructed.len != original.len or
        noise_threshold.len != original.len)
        return error.InvalidVorbisSpectrumShape;
    var maximum_ratio: f128 = 0;
    var weighted_error: f128 = 0;
    var audible_excess_power: f128 = 0;
    for (
        original,
        reconstructed,
        noise_threshold,
    ) |source, decoded, threshold| {
        if (!std.math.isFinite(source) or
            !std.math.isFinite(decoded) or
            !std.math.isFinite(threshold) or
            threshold < 0)
            return error.InvalidVorbisSpectrumValue;
        const difference =
            @abs(@as(f128, @floatCast(source)) -
                @as(f128, @floatCast(decoded)));
        const widened_threshold: f128 = @floatCast(threshold);
        if (widened_threshold == 0) {
            if (difference != 0) {
                return .{
                    .within_mask = false,
                    .maximum_noise_ratio = std.math.inf(f64),
                    .weighted_squared_error = std.math.inf(f64),
                    .audible_excess_power = std.math.inf(f64),
                };
            }
            continue;
        }
        const ratio = difference / widened_threshold;
        const ratio_squared = ratio * ratio;
        maximum_ratio = @max(maximum_ratio, ratio);
        weighted_error += ratio_squared;
        audible_excess_power += @max(
            difference * difference -
                widened_threshold * widened_threshold,
            0,
        );
    }
    if (maximum_ratio > std.math.floatMax(f64) or
        weighted_error > std.math.floatMax(f64) or
        audible_excess_power > std.math.floatMax(f64))
        return error.InvalidVorbisRateDistortionResult;
    return .{
        .within_mask = maximum_ratio <= 1,
        .maximum_noise_ratio = @floatCast(maximum_ratio),
        .weighted_squared_error = @floatCast(weighted_error),
        .audible_excess_power = @floatCast(audible_excess_power),
    };
}

pub const VorbisRateControlConfig = struct {
    target_bitrate: u32,
    reservoir_capacity_bits: u32,
    minimum_packet_bits: u32 = 1,
    maximum_packet_bits: u32 = std.math.maxInt(u32),
    correction_window_packets: u8 = 4,
};

pub const VorbisAdaptiveRatePolicyConfig = struct {
    quiet_rms: f64 = 0.000_1,
    full_activity_rms: f64 = 0.25,
    full_transient_ratio: f64 = 8,
    full_crest_factor: f64 = 6,
    transient_weight: f64 = 0.4,
    crest_weight: f64 = 0.2,
    minimum_target_scale: f64 = 0.6,
    maximum_target_scale: f64 = 1.4,
};

pub const VorbisAdaptiveRateDecision = struct {
    budget: VorbisPacketBitBudget,
    activity: f64,
    transient: f64,
    crest: f64,
    complexity: f64,
    target_scale: f64,
};

pub const VorbisQualityRateControllerConfig = struct {
    minimum_quality: f64,
    maximum_quality: f64,
    initial_quality: f64,
    adjustment_per_packet: f64,
    headroom_ratio: f64,
};

pub const VorbisQualityRateAction = enum {
    hold,
    increase_quality,
    decrease_quality,
};

pub const VorbisQualityRateDecision = struct {
    previous_quality: f64,
    quality: f64,
    actual_to_target_ratio: f64,
    action: VorbisQualityRateAction,
};

pub const VorbisQualitySignalDecision = struct {
    rate: VorbisQualityRateDecision,
    within_mask: bool,
    has_rate_headroom: bool,
    audible_excess_power: f64,
};

pub const VorbisQualityRateController = struct {
    config: VorbisQualityRateControllerConfig,
    current_quality: f64,

    pub fn init(
        config: VorbisQualityRateControllerConfig,
    ) !VorbisQualityRateController {
        try validateVorbisQualityRateControllerConfig(config);
        return .{
            .config = config,
            .current_quality = config.initial_quality,
        };
    }

    pub fn valid(self: *const VorbisQualityRateController) bool {
        validateVorbisQualityRateControllerConfig(self.config) catch
            return false;
        return std.math.isFinite(self.current_quality) and
            self.current_quality >= self.config.minimum_quality and
            self.current_quality <= self.config.maximum_quality;
    }

    pub fn quality(self: *const VorbisQualityRateController) !f64 {
        if (!self.valid())
            return error.InvalidVorbisQualityRateController;
        return self.current_quality;
    }

    pub fn applyTo(
        self: *const VorbisQualityRateController,
        config: VorbisPsychoacousticConfig,
    ) !VorbisPsychoacousticConfig {
        if (!self.valid())
            return error.InvalidVorbisQualityRateController;
        var result = config;
        result.quality = self.current_quality;
        return result;
    }

    /// Adjust quality after a committed packet. A missed residue budget always
    /// lowers quality, even when the reported total remains within target.
    pub fn observe(
        self: *VorbisQualityRateController,
        target_bits: u32,
        actual_bits: u32,
        budget_met: bool,
    ) !VorbisQualityRateDecision {
        if (!self.valid())
            return error.InvalidVorbisQualityRateController;
        if (target_bits == 0 or actual_bits == 0)
            return error.InvalidVorbisQualityRateObservation;

        const previous = self.current_quality;
        const target: f64 = @floatFromInt(target_bits);
        const actual: f64 = @floatFromInt(actual_bits);
        const ratio = actual / target;
        const headroom_boundary = 1 - self.config.headroom_ratio;
        const action: VorbisQualityRateAction = if (!budget_met or
            actual_bits > target_bits)
            .decrease_quality
        else if (ratio <= headroom_boundary)
            .increase_quality
        else
            .hold;
        return self.applyObservation(
            previous,
            ratio,
            action,
        );
    }

    /// Raises quality only when audible excess and packet headroom coincide.
    pub fn observeSignal(
        self: *VorbisQualityRateController,
        budget: VorbisPacketBitBudget,
        commit: VorbisRateCommit,
        submaps: []const VorbisAudioResidueSubmapResult,
    ) !VorbisQualitySignalDecision {
        if (!self.valid())
            return error.InvalidVorbisQualityRateController;
        if (budget.packet_index != commit.packet_index)
            return error.MismatchedVorbisQualityRateObservation;
        if (budget.target_bits == 0 or commit.actual_bits == 0 or
            submaps.len == 0 or submaps.len > 16)
            return error.InvalidVorbisQualitySignalObservation;

        var all_budgets_met = true;
        var target_bits: u64 = 0;
        var encoded_bits: u64 = 0;
        var audible_excess_power: f128 = 0;
        for (submaps) |submap| {
            if (submap.budget_met !=
                (submap.encoded_bits <= submap.target_bits) or
                !std.math.isFinite(submap.squared_error) or
                submap.squared_error < 0 or
                !std.math.isFinite(submap.weighted_squared_error) or
                submap.weighted_squared_error < 0 or
                !std.math.isFinite(submap.audible_excess_power) or
                submap.audible_excess_power < 0 or
                !std.math.isFinite(submap.lambda) or
                submap.lambda < 0)
                return error.InvalidVorbisQualitySignalObservation;
            all_budgets_met = all_budgets_met and submap.budget_met;
            target_bits += submap.target_bits;
            encoded_bits += submap.encoded_bits;
            audible_excess_power += submap.audible_excess_power;
            if (target_bits > budget.target_bits or
                encoded_bits > commit.actual_bits or
                !std.math.isFinite(audible_excess_power) or
                audible_excess_power > std.math.floatMax(f64))
                return error.InvalidVorbisQualitySignalObservation;
        }

        const target: f64 = @floatFromInt(budget.target_bits);
        const actual: f64 = @floatFromInt(commit.actual_bits);
        const ratio = actual / target;
        const has_rate_headroom =
            ratio <= 1 - self.config.headroom_ratio;
        const within_mask = audible_excess_power == 0;
        const action: VorbisQualityRateAction = if (!all_budgets_met or
            commit.actual_bits > budget.target_bits)
            .decrease_quality
        else if (!within_mask and has_rate_headroom)
            .increase_quality
        else
            .hold;
        const previous = self.current_quality;
        return .{
            .rate = self.applyObservation(previous, ratio, action),
            .within_mask = within_mask,
            .has_rate_headroom = has_rate_headroom,
            .audible_excess_power = @floatCast(audible_excess_power),
        };
    }

    pub fn observePcmPacketTrial(
        self: *VorbisQualityRateController,
        comptime Float: type,
        plan: VorbisPcmPacketPlan,
        trial: VorbisPcmPacketEncodingTrial(Float),
    ) !VorbisQualitySignalDecision {
        if (!self.valid())
            return error.InvalidVorbisQualityRateController;
        if (trial.quantization.submap_results.len == 0 or
            trial.quantization.submap_results.len > 16)
            return error.InvalidVorbisQualityPcmPacketTrial;
        const allocation = trial.quantization.allocation;
        const packet_bits = std.math.cast(
            u32,
            trial.packet.bit_count,
        ) orelse return error.InvalidVorbisQualityPcmPacketTrial;
        const packet_bytes = trial.packet.bit_count / 8 +
            @intFromBool(trial.packet.bit_count % 8 != 0);
        const allocated_bits = std.math.add(
            u32,
            allocation.fixed_packet_bits,
            allocation.residue_bits,
        ) catch return error.InvalidVorbisQualityPcmPacketTrial;
        var residue_target_bits: u64 = 0;
        for (trial.quantization.submap_results) |submap| {
            residue_target_bits = std.math.add(
                u64,
                residue_target_bits,
                submap.target_bits,
            ) catch return error.InvalidVorbisQualityPcmPacketTrial;
        }
        if (!std.meta.eql(plan.frame, trial.commit.frame) or
            !std.meta.eql(plan.frame.header, trial.packet.header) or
            packet_bits != trial.commit.rate.actual_bits or
            packet_bytes != trial.packet.bytes.len or
            trial.preparation.fixed_packet_bits !=
                allocation.fixed_packet_bits or
            allocation.packet_target_bits != plan.budget.target_bits or
            allocated_bits != allocation.packet_target_bits or
            residue_target_bits != allocation.residue_bits)
            return error.InvalidVorbisQualityPcmPacketTrial;
        return self.observeSignal(
            plan.budget,
            trial.commit.rate,
            trial.quantization.submap_results,
        );
    }

    fn applyObservation(
        self: *VorbisQualityRateController,
        previous: f64,
        ratio: f64,
        action: VorbisQualityRateAction,
    ) VorbisQualityRateDecision {
        const unbounded = switch (action) {
            .hold => previous,
            .increase_quality => previous + self.config.adjustment_per_packet,
            .decrease_quality => previous - self.config.adjustment_per_packet,
        };
        const next = std.math.clamp(
            unbounded,
            self.config.minimum_quality,
            self.config.maximum_quality,
        );
        const applied_action: VorbisQualityRateAction = if (next > previous)
            .increase_quality
        else if (next < previous)
            .decrease_quality
        else
            .hold;
        self.current_quality = next;
        return .{
            .previous_quality = previous,
            .quality = next,
            .actual_to_target_ratio = ratio,
            .action = applied_action,
        };
    }

    pub fn observeCommit(
        self: *VorbisQualityRateController,
        budget: VorbisPacketBitBudget,
        commit: VorbisRateCommit,
        budget_met: bool,
    ) !VorbisQualityRateDecision {
        if (budget.packet_index != commit.packet_index)
            return error.MismatchedVorbisQualityRateObservation;
        return self.observe(
            budget.target_bits,
            commit.actual_bits,
            budget_met,
        );
    }

    pub fn reset(self: *VorbisQualityRateController) !void {
        validateVorbisQualityRateControllerConfig(self.config) catch
            return error.InvalidVorbisQualityRateController;
        self.current_quality = self.config.initial_quality;
    }
};

pub const VorbisPacketBitBudget = struct {
    packet_index: u64,
    nominal_bits: u32,
    target_bits: u32,
    reservoir_balance_before: i64,
};

pub fn adaptVorbisPacketBitBudget(
    budget: VorbisPacketBitBudget,
    classification: VorbisPcmBlockClassification,
    rate_control: VorbisRateControlConfig,
    policy: VorbisAdaptiveRatePolicyConfig,
) !VorbisAdaptiveRateDecision {
    try validateVorbisRateControlConfig(rate_control);
    try validateVorbisAdaptiveRatePolicyConfig(policy);
    if (budget.nominal_bits == 0 or
        budget.target_bits < rate_control.minimum_packet_bits or
        budget.target_bits > rate_control.maximum_packet_bits or
        budget.reservoir_balance_before <
            -@as(i64, rate_control.reservoir_capacity_bits) or
        budget.reservoir_balance_before >
            @as(i64, rate_control.reservoir_capacity_bits))
        return error.InvalidVorbisPacketBitBudget;
    if (!vorbisPcmBlockClassificationValid(classification))
        return error.InvalidVorbisBlockAnalysis;
    const analysis = classification.analysis;

    const activity = std.math.clamp(
        (analysis.rms - policy.quiet_rms) /
            (policy.full_activity_rms - policy.quiet_rms),
        0,
        1,
    );
    const transient = std.math.clamp(
        @log2(@max(
            analysis.maximum_energy_ratio,
            classification.cross_block_energy_ratio,
        )) /
            @log2(policy.full_transient_ratio),
        0,
        1,
    );
    const crest_factor = if (analysis.rms == 0)
        @as(f64, 1)
    else
        analysis.peak / analysis.rms;
    const crest = std.math.clamp(
        (crest_factor - 1) / (policy.full_crest_factor - 1),
        0,
        1,
    );
    const activity_weight =
        1 - policy.transient_weight - policy.crest_weight;
    const complexity = std.math.clamp(
        activity * activity_weight +
            transient * policy.transient_weight +
            crest * policy.crest_weight,
        0,
        1,
    );
    const target_scale = if (complexity <= 0.5)
        policy.minimum_target_scale +
            complexity * 2 *
                (1 - policy.minimum_target_scale)
    else
        1 + (complexity - 0.5) * 2 *
            (policy.maximum_target_scale - 1);
    const exact_target =
        @as(f128, @floatFromInt(budget.target_bits)) *
        @as(f128, target_scale);
    if (!std.math.isFinite(exact_target) or exact_target < 0 or
        exact_target > std.math.maxInt(u64))
        return error.VorbisAdaptiveRateTargetOverflow;
    const rounded_target: u64 = @intFromFloat(@floor(
        exact_target + 0.5,
    ));

    const reservoir_center =
        @as(i128, budget.reservoir_balance_before) +
        @as(i128, budget.nominal_bits);
    const reservoir_capacity: i128 =
        rate_control.reservoir_capacity_bits;
    const safe_minimum_i128 = @max(
        reservoir_center - reservoir_capacity,
        1,
    );
    const safe_maximum_i128 =
        reservoir_center + reservoir_capacity;
    if (safe_maximum_i128 < 1)
        return error.InvalidVorbisPacketBitBudget;
    const safe_minimum: u64 = @intCast(@min(
        safe_minimum_i128,
        std.math.maxInt(u64),
    ));
    const safe_maximum: u64 = @intCast(@min(
        safe_maximum_i128,
        std.math.maxInt(u64),
    ));
    const minimum = @max(
        @as(u64, rate_control.minimum_packet_bits),
        safe_minimum,
    );
    const maximum = @min(
        @as(u64, rate_control.maximum_packet_bits),
        safe_maximum,
    );
    if (minimum > maximum)
        return error.VorbisAdaptiveRateRangeUnavailable;
    var adjusted = budget;
    adjusted.target_bits = @intCast(std.math.clamp(
        rounded_target,
        minimum,
        maximum,
    ));
    return .{
        .budget = adjusted,
        .activity = activity,
        .transient = transient,
        .crest = crest,
        .complexity = complexity,
        .target_scale = target_scale,
    };
}

pub const VorbisRateCommit = struct {
    packet_index: u64,
    actual_bits: u32,
    reservoir_balance_after: i64,
};

pub const VorbisResidueBitAllocation = struct {
    packet_target_bits: u32,
    fixed_packet_bits: u32,
    residue_bits: u32,
};

pub fn allocateVorbisResidueBitBudgets(
    budget: VorbisPacketBitBudget,
    fixed_packet_bits: u32,
    weights: []const f64,
    destination: []u32,
) !VorbisResidueBitAllocation {
    if (weights.len == 0 or weights.len > 255)
        return error.InvalidVorbisResidueBitWeights;
    if (destination.len < weights.len)
        return error.VorbisResidueBitBudgetOutputTooSmall;
    if (vorbisTypedSlicesOverlap(
        f64,
        weights,
        u32,
        destination[0..weights.len],
    )) return error.OverlappingVorbisResidueBitBudgets;
    if (fixed_packet_bits > budget.target_bits)
        return error.VorbisPacketBudgetBelowFixedCost;
    var total_weight: f128 = 0;
    for (weights) |weight| {
        if (!std.math.isFinite(weight) or weight < 0)
            return error.InvalidVorbisResidueBitWeights;
        total_weight += weight;
    }
    const residue_bits = budget.target_bits - fixed_packet_bits;
    const effective_total = if (total_weight == 0)
        @as(f128, @floatFromInt(weights.len))
    else
        total_weight;
    var allocated: u64 = 0;
    for (weights, destination[0..weights.len]) |weight, *output| {
        const effective_weight = if (total_weight == 0) 1 else weight;
        const exact =
            @as(f128, @floatFromInt(residue_bits)) *
            @as(f128, effective_weight) /
            effective_total;
        const base: u32 = @intFromFloat(@floor(exact));
        output.* = base;
        allocated += base;
    }
    var remaining: usize = @intCast(
        @as(u64, residue_bits) - allocated,
    );
    while (remaining != 0) : (remaining -= 1) {
        var selected: ?usize = null;
        var selected_remainder: f128 = -1;
        for (weights, 0..) |weight, index| {
            const effective_weight =
                if (total_weight == 0) 1 else weight;
            const exact =
                @as(f128, @floatFromInt(residue_bits)) *
                @as(f128, effective_weight) /
                effective_total;
            const base: u32 = @intFromFloat(@floor(exact));
            if (destination[index] != base) continue;
            const remainder = exact - @floor(exact);
            if (remainder > selected_remainder) {
                selected = index;
                selected_remainder = remainder;
            }
        }
        const index = selected orelse
            return error.InvalidVorbisResidueBitWeights;
        destination[index] += 1;
    }
    return .{
        .packet_target_bits = budget.target_bits,
        .fixed_packet_bits = fixed_packet_bits,
        .residue_bits = residue_bits,
    };
}

pub fn requiredVorbisAudioResidueQuantizationStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioResidueQuantizationStorageRequirements {
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    const coefficient_count: usize = header.block_size / 2;
    var classifications: usize = 0;
    var entries: usize = 0;
    var partition_values: usize = 0;
    var vector_values: usize = 0;
    var classification_scratch: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var vector_count: usize = 0;
        for (mapping.channel_mux[0..identification.channel_count]) |mux| {
            if (mux == submap_index) vector_count += 1;
        }
        if (vector_count == 0) continue;
        const residue_number =
            mapping.submaps[submap_index].residue;
        const scratch =
            try requiredVorbisResidueQuantizationScratch(
                setup,
                residue_number,
                coefficient_count,
                vector_count,
            );
        const maximum_entries =
            try requiredVorbisResidueQuantizationEntries(
                setup,
                residue_number,
                coefficient_count,
                vector_count,
            );
        classifications = std.math.add(
            usize,
            classifications,
            scratch.classifications,
        ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
        entries = std.math.add(
            usize,
            entries,
            maximum_entries,
        ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
        partition_values =
            @max(partition_values, scratch.partition_values);
        vector_values = @max(vector_values, scratch.vector_values);
        classification_scratch =
            @max(classification_scratch, scratch.classifications);
    }
    return .{
        .encodings = mapping.submap_count,
        .submap_results = mapping.submap_count,
        .do_not_encode = identification.channel_count,
        .classifications = classifications,
        .entries = entries,
        .partition_values = partition_values,
        .vector_values = vector_values,
        .classification_scratch = classification_scratch,
    };
}

pub fn quantizeVorbisAudioResiduesAdaptive(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    residue_values: []const Float,
    noise_thresholds: []const Float,
    do_not_encode: []const bool,
    budget: VorbisPacketBitBudget,
    fixed_packet_bits: u32,
    weights: []const f64,
    config: VorbisAudioResidueQuantizationConfig,
    scratch: VorbisAudioResidueQuantizationScratch(Float),
    storage: VorbisAudioResidueQuantizationStorage,
) !VorbisAudioResidueQuantizationPlan {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis audio residue quantization requires f32 or f64");
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    const requirements =
        try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            header,
        );
    const coefficient_count: usize = header.block_size / 2;
    const value_count = std.math.mul(
        usize,
        identification.channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
    if (residue_values.len != value_count or
        noise_thresholds.len != value_count or
        do_not_encode.len != identification.channel_count)
        return error.InvalidVorbisResidueBundle;
    for (residue_values, noise_thresholds) |value, threshold| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisQuantizationTarget;
        if (!std.math.isFinite(threshold) or threshold <= 0)
            return error.InvalidVorbisNoiseThreshold;
    }
    if (weights.len != mapping.submap_count)
        return error.InvalidVorbisResidueBitWeights;
    if (config.maximum_iterations == 0 or
        config.maximum_iterations > 64 or
        !std.math.isFinite(config.initial_lambda) or
        config.initial_lambda <= 0)
        return error.InvalidVorbisAdaptiveResidueConfig;
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len <
            requirements.classification_scratch or
        scratch.best_classifications.len <
            requirements.classification_scratch or
        scratch.output_classifications.len <
            requirements.classifications or
        scratch.entries.len < requirements.entries or
        scratch.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResidueQuantizationScratchTooSmall;
    if (storage.encodings.len < requirements.encodings or
        storage.submap_results.len <
            requirements.submap_results or
        storage.do_not_encode.len <
            requirements.do_not_encode or
        storage.classifications.len <
            requirements.classifications or
        storage.entries.len < requirements.entries)
        return error.VorbisAudioResidueQuantizationStorageTooSmall;

    const partition =
        scratch.partition[0..requirements.partition_values];
    const vector = scratch.vector[0..requirements.vector_values];
    const classification_scratch =
        scratch.classifications[0..requirements.classification_scratch];
    const best_classifications =
        scratch.best_classifications[0..requirements.classification_scratch];
    const trial_classifications =
        scratch.output_classifications[0..requirements.classifications];
    const trial_entries = scratch.entries[0..requirements.entries];
    const trial_skips =
        scratch.do_not_encode[0..requirements.do_not_encode];
    const encodings = storage.encodings[0..requirements.encodings];
    const submap_results =
        storage.submap_results[0..requirements.submap_results];
    const retained_skips =
        storage.do_not_encode[0..requirements.do_not_encode];
    const retained_classifications =
        storage.classifications[0..requirements.classifications];
    const retained_entries =
        storage.entries[0..requirements.entries];
    try rejectVorbisAudioResidueQuantizationOverlap(
        Float,
        setup,
        residue_values,
        noise_thresholds,
        do_not_encode,
        weights,
        partition,
        vector,
        classification_scratch,
        best_classifications,
        trial_classifications,
        trial_entries,
        trial_skips,
        encodings,
        submap_results,
        retained_skips,
        retained_classifications,
        retained_entries,
    );

    var submap_budgets: [16]u32 = undefined;
    const allocation = try allocateVorbisResidueBitBudgets(
        budget,
        fixed_packet_bits,
        weights,
        submap_budgets[0..mapping.submap_count],
    );
    var trial_results: [16]VorbisAudioResidueSubmapResult =
        undefined;
    var skip_counts = [_]usize{0} ** 16;
    var classification_counts = [_]usize{0} ** 16;
    var entry_counts = [_]usize{0} ** 16;
    var skip_offset: usize = 0;
    var classification_offset: usize = 0;
    var entry_offset: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var bundle_inputs: [255][]const Float = undefined;
        var bundle_thresholds: [255][]const Float = undefined;
        var bundle_count: usize = 0;
        for (
            mapping.channel_mux[0..identification.channel_count],
            0..,
        ) |mux, channel| {
            if (mux != submap_index) continue;
            const start = channel * coefficient_count;
            bundle_inputs[bundle_count] =
                residue_values[start..][0..coefficient_count];
            bundle_thresholds[bundle_count] =
                noise_thresholds[start..][0..coefficient_count];
            trial_skips[skip_offset + bundle_count] =
                do_not_encode[channel];
            bundle_count += 1;
        }
        skip_counts[submap_index] = bundle_count;
        if (bundle_count == 0) {
            trial_results[submap_index] = .{
                .target_bits = submap_budgets[submap_index],
                .encoded_bits = 0,
                .budget_met = true,
                .squared_error = 0,
                .weighted_squared_error = 0,
                .audible_excess_power = 0,
                .lambda = 0,
                .iterations = 0,
            };
            continue;
        }
        const quantized = try quantizeVorbisResidueAdaptive(
            Float,
            setup,
            mapping.submaps[submap_index].residue,
            trial_skips[skip_offset..][0..bundle_count],
            bundle_inputs[0..bundle_count],
            bundle_thresholds[0..bundle_count],
            .{
                .target_bits = submap_budgets[submap_index],
                .maximum_iterations = config.maximum_iterations,
                .initial_lambda = config.initial_lambda,
            },
            .{
                .partition = partition,
                .vector = vector,
                .classifications = classification_scratch,
                .best_classifications = best_classifications,
            },
            trial_classifications[classification_offset..],
            trial_entries[entry_offset..],
        );
        const classification_count =
            quantized.encoding.classifications.len;
        const entry_count = quantized.encoding.entries.len;
        classification_counts[submap_index] = classification_count;
        entry_counts[submap_index] = entry_count;
        trial_results[submap_index] = .{
            .target_bits = submap_budgets[submap_index],
            .encoded_bits = quantized.encoded_bits,
            .budget_met = quantized.budget_met,
            .squared_error = quantized.squared_error,
            .weighted_squared_error = quantized.weighted_squared_error,
            .audible_excess_power = quantized.audible_excess_power,
            .lambda = quantized.lambda,
            .iterations = quantized.iterations,
        };
        skip_offset += bundle_count;
        classification_offset += classification_count;
        entry_offset += entry_count;
    }
    if (skip_offset != requirements.do_not_encode)
        return error.InvalidVorbisResidueBundle;

    @memcpy(retained_skips, trial_skips);
    @memcpy(
        retained_classifications[0..classification_offset],
        trial_classifications[0..classification_offset],
    );
    @memcpy(
        retained_entries[0..entry_offset],
        trial_entries[0..entry_offset],
    );
    @memcpy(submap_results, trial_results[0..mapping.submap_count]);
    skip_offset = 0;
    classification_offset = 0;
    entry_offset = 0;
    for (encodings, 0..) |*encoding, submap_index| {
        const skip_count = skip_counts[submap_index];
        const classification_count =
            classification_counts[submap_index];
        const entry_count = entry_counts[submap_index];
        encoding.* = .{
            .do_not_encode = retained_skips[skip_offset..][0..skip_count],
            .classifications = retained_classifications[classification_offset..][0..classification_count],
            .entries = retained_entries[entry_offset..][0..entry_count],
        };
        skip_offset += skip_count;
        classification_offset += classification_count;
        entry_offset += entry_count;
    }
    return .{
        .encodings = encodings,
        .submap_results = submap_results,
        .do_not_encode = retained_skips,
        .classifications = retained_classifications[0..classification_offset],
        .entries = retained_entries[0..entry_offset],
        .allocation = allocation,
    };
}

pub fn rejectVorbisAudioResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    residue_values: []const Float,
    noise_thresholds: []const Float,
    do_not_encode: []const bool,
    weights: []const f64,
    partition: []Float,
    vector: []Float,
    classification_scratch: []u8,
    best_classifications: []u8,
    trial_classifications: []u8,
    trial_entries: []u32,
    trial_skips: []bool,
    encodings: []VorbisResidueEncoding,
    submap_results: []VorbisAudioResidueSubmapResult,
    retained_skips: []bool,
    retained_classifications: []u8,
    retained_entries: []u32,
) !void {
    const destinations = [_][]u8{
        std.mem.sliceAsBytes(partition),
        std.mem.sliceAsBytes(vector),
        std.mem.sliceAsBytes(classification_scratch),
        std.mem.sliceAsBytes(best_classifications),
        std.mem.sliceAsBytes(trial_classifications),
        std.mem.sliceAsBytes(trial_entries),
        std.mem.sliceAsBytes(trial_skips),
        std.mem.sliceAsBytes(encodings),
        std.mem.sliceAsBytes(submap_results),
        std.mem.sliceAsBytes(retained_skips),
        std.mem.sliceAsBytes(retained_classifications),
        std.mem.sliceAsBytes(retained_entries),
    };
    inline for (.{
        std.mem.sliceAsBytes(residue_values),
        std.mem.sliceAsBytes(noise_thresholds),
        std.mem.sliceAsBytes(do_not_encode),
        std.mem.sliceAsBytes(weights),
    }) |source| {
        for (destinations) |destination| {
            if (vorbisConstSlicesOverlap(
                u8,
                source,
                destination,
            )) return error.OverlappingVorbisAudioResidueQuantizationStorage;
        }
    }
    for (destinations, 0..) |destination, index| {
        for (destinations[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(
                u8,
                destination,
                earlier,
            )) return error.OverlappingVorbisAudioResidueQuantizationStorage;
        }
        rejectVorbisSetupOverlap(
            destination,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioResidueQuantizationStorage,
            else => return err,
        };
    }
}

pub const VorbisBitReservoir = struct {
    config: VorbisRateControlConfig,
    packet_index: u64 = 0,
    balance_bits: i64 = 0,
    pending: ?VorbisPacketBitBudget = null,

    pub fn init(
        config: VorbisRateControlConfig,
    ) !VorbisBitReservoir {
        try validateVorbisRateControlConfig(config);
        return .{ .config = config };
    }

    pub fn reset(self: *VorbisBitReservoir) void {
        self.packet_index = 0;
        self.balance_bits = 0;
        self.pending = null;
    }

    pub fn valid(self: *const VorbisBitReservoir) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn plan(
        self: *VorbisBitReservoir,
        sample_rate: u32,
        pcm_advance: u16,
    ) !VorbisPacketBitBudget {
        try self.validateState();
        if (self.pending != null)
            return error.VorbisRateBudgetAlreadyPending;
        if (self.packet_index == std.math.maxInt(u64))
            return error.VorbisAudioPacketCountOverflow;
        if (sample_rate == 0 or pcm_advance == 0)
            return error.InvalidVorbisRateInterval;
        const numerator =
            @as(u64, self.config.target_bitrate) * pcm_advance;
        const rounded =
            (numerator + sample_rate / 2) / sample_rate;
        const nominal: u32 = @intCast(@min(
            @max(rounded, 1),
            std.math.maxInt(u32),
        ));
        const correction = @divTrunc(
            self.balance_bits,
            self.config.correction_window_packets,
        );
        const desired = std.math.add(
            i64,
            nominal,
            correction,
        ) catch if (correction < 0)
            @as(i64, std.math.minInt(i64))
        else
            @as(i64, std.math.maxInt(i64));
        const target: u32 = @intCast(std.math.clamp(
            desired,
            self.config.minimum_packet_bits,
            self.config.maximum_packet_bits,
        ));
        const budget = VorbisPacketBitBudget{
            .packet_index = self.packet_index,
            .nominal_bits = nominal,
            .target_bits = target,
            .reservoir_balance_before = self.balance_bits,
        };
        self.pending = budget;
        return budget;
    }

    pub fn commit(
        self: *VorbisBitReservoir,
        actual_bits: u32,
    ) !VorbisRateCommit {
        try self.validateState();
        const budget = self.pending orelse
            return error.VorbisRateBudgetNotPending;
        const capacity: i64 = self.config.reservoir_capacity_bits;
        const credited = std.math.add(
            i64,
            self.balance_bits,
            budget.nominal_bits,
        ) catch return error.VorbisBitReservoirExceeded;
        const next_balance = std.math.sub(
            i64,
            credited,
            actual_bits,
        ) catch return error.VorbisBitReservoirExceeded;
        if (next_balance < -capacity or next_balance > capacity)
            return error.VorbisBitReservoirExceeded;
        const result = VorbisRateCommit{
            .packet_index = budget.packet_index,
            .actual_bits = actual_bits,
            .reservoir_balance_after = next_balance,
        };
        self.balance_bits = next_balance;
        self.pending = null;
        self.packet_index += 1;
        return result;
    }

    pub fn cancel(self: *VorbisBitReservoir) !void {
        try self.validateState();
        if (self.pending == null)
            return error.VorbisRateBudgetNotPending;
        self.pending = null;
    }

    fn validateState(self: *const VorbisBitReservoir) !void {
        try validateVorbisRateControlConfig(self.config);
        const capacity: i64 = self.config.reservoir_capacity_bits;
        if (self.balance_bits < -capacity or
            self.balance_bits > capacity)
            return error.InvalidVorbisBitReservoirState;
        if (self.pending) |budget| {
            if (self.packet_index == std.math.maxInt(u64) or
                budget.packet_index != self.packet_index or
                budget.reservoir_balance_before != self.balance_bits or
                budget.nominal_bits == 0 or
                budget.target_bits < self.config.minimum_packet_bits or
                budget.target_bits > self.config.maximum_packet_bits)
                return error.InvalidVorbisBitReservoirState;
        }
    }
};

pub fn validateVorbisRateControlConfig(
    config: VorbisRateControlConfig,
) !void {
    if (config.target_bitrate == 0 or
        config.minimum_packet_bits > config.maximum_packet_bits or
        config.correction_window_packets == 0 or
        config.correction_window_packets > 64)
        return error.InvalidVorbisRateControlConfig;
}

pub fn validateVorbisAdaptiveRatePolicyConfig(
    config: VorbisAdaptiveRatePolicyConfig,
) !void {
    if (!std.math.isFinite(config.quiet_rms) or
        config.quiet_rms < 0 or
        !std.math.isFinite(config.full_activity_rms) or
        config.full_activity_rms <= config.quiet_rms or
        !std.math.isFinite(config.full_transient_ratio) or
        config.full_transient_ratio <= 1 or
        !std.math.isFinite(config.full_crest_factor) or
        config.full_crest_factor <= 1 or
        !std.math.isFinite(config.transient_weight) or
        config.transient_weight < 0 or
        !std.math.isFinite(config.crest_weight) or
        config.crest_weight < 0 or
        config.transient_weight + config.crest_weight > 1 or
        !std.math.isFinite(config.minimum_target_scale) or
        config.minimum_target_scale <= 0 or
        config.minimum_target_scale > 1 or
        !std.math.isFinite(config.maximum_target_scale) or
        config.maximum_target_scale < 1 or
        config.maximum_target_scale > 8)
        return error.InvalidVorbisAdaptiveRatePolicyConfig;
}

pub fn validateVorbisQualityRateControllerConfig(
    config: VorbisQualityRateControllerConfig,
) !void {
    if (!std.math.isFinite(config.minimum_quality) or
        !std.math.isFinite(config.maximum_quality) or
        config.minimum_quality < 0 or
        config.maximum_quality > 1 or
        config.minimum_quality > config.maximum_quality or
        !std.math.isFinite(config.initial_quality) or
        config.initial_quality < config.minimum_quality or
        config.initial_quality > config.maximum_quality or
        !std.math.isFinite(config.adjustment_per_packet) or
        config.adjustment_per_packet <= 0 or
        config.adjustment_per_packet > 1 or
        !std.math.isFinite(config.headroom_ratio) or
        config.headroom_ratio < 0 or
        config.headroom_ratio > 1)
        return error.InvalidVorbisQualityRateControllerConfig;
}

pub fn validateVorbisPcmBlockClassifierConfig(
    config: VorbisPcmBlockClassifierConfig,
) !void {
    if (!std.math.isFinite(config.cross_block_energy_ratio) or
        config.cross_block_energy_ratio <= 1 or
        !std.math.isFinite(config.stable_energy_ratio) or
        config.stable_energy_ratio < 1 or
        config.stable_energy_ratio >=
            config.cross_block_energy_ratio or
        !std.math.isFinite(config.energy_smoothing) or
        config.energy_smoothing <= 0 or
        config.energy_smoothing > 1)
        return error.InvalidVorbisPcmBlockClassifierConfig;
}

/// Recommends a block size from short-window energy changes.
pub fn analyzeVorbisPcmBlock(
    comptime Float: type,
    channels: []const []const Float,
    small_block_size: u16,
    large_block_size: u16,
    config: VorbisPcmBlockAnalysisConfig,
) !VorbisPcmBlockAnalysis {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM analysis requires f32 or f64 input");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        return error.InvalidVorbisBlockSizes;
    if (!std.math.isFinite(config.transient_energy_ratio) or
        config.transient_energy_ratio <= 1 or
        !std.math.isFinite(config.minimum_rms) or
        config.minimum_rms < 0)
        return error.InvalidVorbisBlockAnalysisConfig;
    for (channels) |channel| {
        if (channel.len != large_block_size)
            return error.InvalidVorbisPcmBlockShape;
        for (channel) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidVorbisPcmSample;
        }
    }

    const segment_length = @as(usize, small_block_size) / 2;
    const segment_count =
        @as(usize, large_block_size) / segment_length;
    const values_per_segment = segment_length * channels.len;
    const total_values = @as(usize, large_block_size) * channels.len;
    var total_energy: f128 = 0;
    var peak: f128 = 0;
    var previous_energy: f128 = 0;
    var maximum_ratio: f128 = 1;
    var transient_segment: ?u16 = null;
    const minimum_energy =
        @as(f128, config.minimum_rms) *
        @as(f128, config.minimum_rms);

    for (0..segment_count) |segment| {
        const start = segment * segment_length;
        var segment_energy: f128 = 0;
        for (channels) |channel| {
            for (channel[start..][0..segment_length]) |sample| {
                const widened: f128 = @floatCast(sample);
                const magnitude = @abs(widened);
                peak = @max(peak, magnitude);
                segment_energy += widened * widened;
            }
        }
        total_energy += segment_energy;
        const mean_energy =
            segment_energy /
            @as(f128, @floatFromInt(values_per_segment));
        if (segment != 0) {
            const high = @max(previous_energy, mean_energy);
            if (high > 0 and high >= minimum_energy) {
                const low = @max(
                    @min(previous_energy, mean_energy),
                    @max(minimum_energy, std.math.floatMin(f128)),
                );
                const ratio = high / low;
                if (ratio > maximum_ratio) {
                    maximum_ratio = ratio;
                    transient_segment = @intCast(segment);
                }
            }
        }
        previous_energy = mean_energy;
    }

    const mean_total_energy =
        total_energy / @as(f128, @floatFromInt(total_values));
    const transient =
        maximum_ratio >= @as(f128, config.transient_energy_ratio);
    return .{
        .recommended_large_block = small_block_size != large_block_size and !transient,
        .peak = @floatCast(peak),
        .rms = @floatCast(@sqrt(mean_total_energy)),
        .maximum_energy_ratio = @floatCast(@min(
            maximum_ratio,
            std.math.floatMax(f64),
        )),
        .transient_segment = if (transient)
            transient_segment
        else
            null,
    };
}

pub fn selectVorbisEncodingMode(
    setup: VorbisSetup,
    mapping_number: u8,
    large_block: bool,
) !u8 {
    if (setup.modes.len == 0 or
        setup.modes.len != setup.summary.mode_count or
        setup.mappings.len != setup.summary.mapping_count)
        return error.InvalidVorbisSetupState;
    if (mapping_number >= setup.mappings.len)
        return error.InvalidVorbisMappingNumber;
    for (setup.modes) |mode| {
        if (mode.mapping >= setup.mappings.len)
            return error.InvalidVorbisSetupState;
    }
    for (setup.modes, 0..) |mode, mode_number| {
        if (mode.mapping == mapping_number and
            mode.large_block == large_block)
            return @intCast(mode_number);
    }
    return error.VorbisEncodingModeUnavailable;
}

pub fn planVorbisEncodingBlock(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    mapping_number: u8,
    previous_large_block: bool,
    current_large_block: bool,
    next_large_block: bool,
) !VorbisAudioPacketHeader {
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size >
            identification.large_block_size or
        !std.math.isPowerOfTwo(
            identification.small_block_size,
        ) or
        !std.math.isPowerOfTwo(
            identification.large_block_size,
        ))
        return error.InvalidVorbisIdentificationState;
    const mode_number = try selectVorbisEncodingMode(
        setup,
        mapping_number,
        current_large_block,
    );
    var counter = VorbisPacketWriter.counting();
    return counter.writeAudioHeader(
        identification,
        setup,
        mode_number,
        if (current_large_block) previous_large_block else null,
        if (current_large_block) next_large_block else null,
    );
}

pub const VorbisPcmFramePlan = struct {
    packet_index: u64,
    header: VorbisAudioPacketHeader,
    source_start: i64,
    pcm_advance: u16,
    next_center: i64,
};

pub const VorbisPcmFramePlanner = struct {
    packet_index: u64 = 0,
    center: i64 = 0,
    previous_large_block: bool,

    pub fn init(previous_large_block: bool) VorbisPcmFramePlanner {
        return .{ .previous_large_block = previous_large_block };
    }

    pub fn reset(
        self: *VorbisPcmFramePlanner,
        previous_large_block: bool,
    ) void {
        self.* = .{ .previous_large_block = previous_large_block };
    }

    pub fn valid(self: *const VorbisPcmFramePlanner) bool {
        if (self.packet_index == 0)
            return self.center == 0;
        if (self.center <= 0 or @mod(self.center, 16) != 0)
            return false;
        const packet_count = std.math.cast(
            i64,
            self.packet_index,
        ) orelse return false;
        const minimum_pcm_advance: i64 = 32;
        const maximum_pcm_advance: i64 = 4096;
        const minimum_center = std.math.mul(
            i64,
            packet_count,
            minimum_pcm_advance,
        ) catch return false;
        const maximum_center = std.math.mul(
            i64,
            packet_count,
            maximum_pcm_advance,
        ) catch std.math.maxInt(i64);
        return self.center >= minimum_center and
            self.center <= maximum_center;
    }

    pub fn plan(
        self: *VorbisPcmFramePlanner,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
        current_large_block: bool,
        next_large_block: bool,
    ) !VorbisPcmFramePlan {
        if (!self.valid())
            return error.InvalidVorbisPcmFramePlannerState;
        if (self.packet_index == std.math.maxInt(u64))
            return error.VorbisAudioPacketCountOverflow;
        const header = try planVorbisEncodingBlock(
            identification,
            setup,
            mapping_number,
            self.previous_large_block,
            current_large_block,
            next_large_block,
        );
        const next_block_size: u16 = if (next_large_block)
            identification.large_block_size
        else
            identification.small_block_size;
        const half_block: i64 = header.block_size / 2;
        const source_start = std.math.sub(
            i64,
            self.center,
            half_block,
        ) catch return error.VorbisPcmFramePositionOverflow;
        const pcm_advance: u16 =
            header.block_size / 4 + next_block_size / 4;
        const next_center = std.math.add(
            i64,
            self.center,
            pcm_advance,
        ) catch return error.VorbisPcmFramePositionOverflow;
        const result = VorbisPcmFramePlan{
            .packet_index = self.packet_index,
            .header = header,
            .source_start = source_start,
            .pcm_advance = pcm_advance,
            .next_center = next_center,
        };
        self.packet_index += 1;
        self.center = next_center;
        self.previous_large_block = current_large_block;
        return result;
    }
};

pub const VorbisPcmBlockLookahead = struct {
    frames: VorbisPcmFramePlanner,
    pending_large_block: ?bool = null,

    pub fn init(
        previous_large_block: bool,
    ) VorbisPcmBlockLookahead {
        return .{
            .frames = .init(previous_large_block),
        };
    }

    pub fn reset(
        self: *VorbisPcmBlockLookahead,
        previous_large_block: bool,
    ) void {
        self.* = .init(previous_large_block);
    }

    pub fn valid(self: *const VorbisPcmBlockLookahead) bool {
        return self.frames.valid();
    }

    pub fn prime(
        self: *VorbisPcmBlockLookahead,
        analysis: VorbisPcmBlockAnalysis,
    ) !void {
        if (!self.valid())
            return error.InvalidVorbisPcmBlockLookaheadState;
        if (self.pending_large_block != null)
            return error.VorbisBlockLookaheadAlreadyPrimed;
        self.pending_large_block =
            analysis.recommended_large_block;
    }

    pub fn push(
        self: *VorbisPcmBlockLookahead,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
        next_analysis: VorbisPcmBlockAnalysis,
    ) !VorbisPcmFramePlan {
        if (!self.valid())
            return error.InvalidVorbisPcmBlockLookaheadState;
        const current_large_block =
            self.pending_large_block orelse
            return error.VorbisBlockLookaheadNotPrimed;
        const result = try self.frames.plan(
            identification,
            setup,
            mapping_number,
            current_large_block,
            next_analysis.recommended_large_block,
        );
        self.pending_large_block =
            next_analysis.recommended_large_block;
        return result;
    }

    pub fn finish(
        self: *VorbisPcmBlockLookahead,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
    ) !VorbisPcmFramePlan {
        if (!self.valid())
            return error.InvalidVorbisPcmBlockLookaheadState;
        const current_large_block =
            self.pending_large_block orelse
            return error.VorbisBlockLookaheadNotPrimed;
        const result = try self.frames.plan(
            identification,
            setup,
            mapping_number,
            current_large_block,
            current_large_block,
        );
        self.pending_large_block = null;
        return result;
    }
};

pub const VorbisPcmPacketSequenceConfig = struct {
    mapping_number: u8 = 0,
    classifier: VorbisPcmBlockClassifierConfig = .{},
    rate_control: VorbisRateControlConfig,
    adaptive_rate: ?VorbisAdaptiveRatePolicyConfig = null,
};

pub const VorbisPcmPacketPlan = struct {
    base_revision: u64,
    frame: VorbisPcmFramePlan,
    classification: ?VorbisPcmBlockClassification,
    budget: VorbisPacketBitBudget,
    granule_position: u64,
    end: bool,
    classifier_after: VorbisPcmBlockClassifier,
    lookahead_after: VorbisPcmBlockLookahead,
    reservoir_pending: VorbisBitReservoir,
};

pub const VorbisPcmPacketCommit = struct {
    frame: VorbisPcmFramePlan,
    rate: VorbisRateCommit,
    granule_position: u64,
    end: bool,
};

pub const VorbisPcmPacketSequence = struct {
    config: VorbisPcmPacketSequenceConfig,
    classifier: VorbisPcmBlockClassifier = .{},
    lookahead: VorbisPcmBlockLookahead,
    reservoir: VorbisBitReservoir,
    revision: u64 = 0,
    granule_position: u64 = 0,
    ended: bool = false,

    pub fn init(
        config: VorbisPcmPacketSequenceConfig,
        previous_large_block: bool,
    ) !VorbisPcmPacketSequence {
        try validateVorbisPcmBlockClassifierConfig(
            config.classifier,
        );
        if (config.adaptive_rate) |adaptive_rate| {
            try validateVorbisAdaptiveRatePolicyConfig(adaptive_rate);
        }
        return .{
            .config = config,
            .lookahead = .init(previous_large_block),
            .reservoir = try .init(config.rate_control),
        };
    }

    pub fn valid(self: *const VorbisPcmPacketSequence) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn prime(
        self: *VorbisPcmPacketSequence,
        comptime Float: type,
        channels: []const []const Float,
        identification: VorbisIdentification,
    ) !VorbisPcmBlockClassification {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        var classifier_after = self.classifier;
        const classification = try classifier_after.classify(
            Float,
            channels,
            identification.small_block_size,
            identification.large_block_size,
            self.config.classifier,
        );
        var lookahead_after = self.lookahead;
        try lookahead_after.prime(
            vorbisPcmBlockDecision(classification),
        );
        self.classifier = classifier_after;
        self.lookahead = lookahead_after;
        self.revision += 1;
        return classification;
    }

    pub fn planNext(
        self: *const VorbisPcmPacketSequence,
        comptime Float: type,
        channels: []const []const Float,
        identification: VorbisIdentification,
        setup: VorbisSetup,
    ) !VorbisPcmPacketPlan {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        var classifier_after = self.classifier;
        const classification = try classifier_after.classify(
            Float,
            channels,
            identification.small_block_size,
            identification.large_block_size,
            self.config.classifier,
        );
        var lookahead_after = self.lookahead;
        const frame = try lookahead_after.push(
            identification,
            setup,
            self.config.mapping_number,
            vorbisPcmBlockDecision(classification),
        );
        var reservoir_pending = self.reservoir;
        var budget = try reservoir_pending.plan(
            identification.sample_rate,
            frame.pcm_advance,
        );
        if (self.config.adaptive_rate) |adaptive_rate| {
            budget = (try adaptVorbisPacketBitBudget(
                budget,
                classification,
                self.config.rate_control,
                adaptive_rate,
            )).budget;
            reservoir_pending.pending = budget;
        }
        const granule_position =
            try vorbisPcmFrameGranule(frame);
        if (granule_position < self.granule_position)
            return error.InvalidVorbisEncoderGranulePosition;
        return .{
            .base_revision = self.revision,
            .frame = frame,
            .classification = classification,
            .budget = budget,
            .granule_position = granule_position,
            .end = false,
            .classifier_after = classifier_after,
            .lookahead_after = lookahead_after,
            .reservoir_pending = reservoir_pending,
        };
    }

    pub fn planFinish(
        self: *const VorbisPcmPacketSequence,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        total_pcm_frames: u64,
    ) !VorbisPcmPacketPlan {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        if (total_pcm_frames > std.math.maxInt(i64))
            return error.InvalidVorbisEncoderGranulePosition;
        var lookahead_after = self.lookahead;
        const frame = try lookahead_after.finish(
            identification,
            setup,
            self.config.mapping_number,
        );
        const maximum_granule = try vorbisPcmFrameGranule(frame);
        if (total_pcm_frames < self.granule_position or
            total_pcm_frames > maximum_granule)
            return error.InvalidVorbisEncoderGranulePosition;
        var reservoir_pending = self.reservoir;
        const budget = try reservoir_pending.plan(
            identification.sample_rate,
            frame.pcm_advance,
        );
        return .{
            .base_revision = self.revision,
            .frame = frame,
            .classification = null,
            .budget = budget,
            .granule_position = total_pcm_frames,
            .end = true,
            .classifier_after = self.classifier,
            .lookahead_after = lookahead_after,
            .reservoir_pending = reservoir_pending,
        };
    }

    pub fn commit(
        self: *VorbisPcmPacketSequence,
        plan: VorbisPcmPacketPlan,
        actual_bits: u32,
    ) !VorbisPcmPacketCommit {
        if (actual_bits == 0)
            return error.InvalidVorbisAudioPacketBitCount;
        try self.validatePlan(plan);
        var reservoir_after = plan.reservoir_pending;
        const rate = try reservoir_after.commit(actual_bits);
        const result = VorbisPcmPacketCommit{
            .frame = plan.frame,
            .rate = rate,
            .granule_position = plan.granule_position,
            .end = plan.end,
        };
        self.classifier = plan.classifier_after;
        self.lookahead = plan.lookahead_after;
        self.reservoir = reservoir_after;
        self.revision += 1;
        self.granule_position = plan.granule_position;
        self.ended = plan.end;
        return result;
    }

    pub fn appendMemory(
        self: *VorbisPcmPacketSequence,
        writer: *StreamWriter,
        plan: VorbisPcmPacketPlan,
        packet: []const u8,
        packet_bit_count: usize,
    ) !VorbisPcmPacketCommit {
        const actual_bits = std.math.cast(
            u32,
            packet_bit_count,
        ) orelse return error.VorbisAudioPacketSizeOverflow;
        if (packet_bit_count > packet.len *| 8)
            return error.InvalidVorbisAudioPacketBitCount;
        var sequence_after = self.*;
        const result = try sequence_after.commit(plan, actual_bits);
        var writer_after = writer.*;
        try writer_after.appendPacket(
            packet,
            plan.granule_position,
            false,
            plan.end,
        );
        self.* = sequence_after;
        writer.* = writer_after;
        return result;
    }

    pub fn appendFile(
        self: *VorbisPcmPacketSequence,
        writer: *FileWriter,
        plan: VorbisPcmPacketPlan,
        packet: []const u8,
        packet_bit_count: usize,
    ) !VorbisPcmPacketCommit {
        const actual_bits = std.math.cast(
            u32,
            packet_bit_count,
        ) orelse return error.VorbisAudioPacketSizeOverflow;
        if (packet_bit_count > packet.len *| 8)
            return error.InvalidVorbisAudioPacketBitCount;
        var sequence_after = self.*;
        const result = try sequence_after.commit(plan, actual_bits);
        try writer.appendPacket(
            packet,
            plan.granule_position,
            false,
            plan.end,
        );
        self.* = sequence_after;
        return result;
    }

    fn validateReady(
        self: *const VorbisPcmPacketSequence,
        identification: VorbisIdentification,
    ) !void {
        if (self.ended)
            return error.VorbisPcmPacketSequenceAlreadyEnded;
        self.validateState() catch
            return error.InvalidVorbisPcmPacketSequenceState;
        if (identification.sample_rate == 0)
            return error.InvalidVorbisPcmPacketSequenceState;
    }

    fn validatePlan(
        self: *const VorbisPcmPacketSequence,
        plan: VorbisPcmPacketPlan,
    ) !void {
        if (self.ended)
            return error.VorbisPcmPacketSequenceAlreadyEnded;
        self.validateState() catch
            return error.InvalidVorbisPcmPacketSequenceState;
        if (plan.base_revision != self.revision)
            return error.StaleVorbisPcmPacketPlan;
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        const pending_budget = plan.reservoir_pending.pending orelse
            return error.InvalidVorbisPcmPacketPlan;
        try validateVorbisPcmFrameTransition(
            self.lookahead,
            plan.frame,
            plan.lookahead_after,
            plan.end,
        );
        if (!plan.reservoir_pending.valid() or
            !plan.classifier_after.valid())
            return error.InvalidVorbisPcmPacketPlan;
        const maximum_granule = vorbisPcmFrameGranule(plan.frame) catch
            return error.InvalidVorbisPcmPacketPlan;
        if (plan.frame.packet_index !=
            self.lookahead.frames.packet_index or
            plan.budget.packet_index != self.reservoir.packet_index or
            plan.frame.packet_index != plan.budget.packet_index or
            plan.reservoir_pending.packet_index !=
                self.reservoir.packet_index or
            plan.reservoir_pending.balance_bits !=
                self.reservoir.balance_bits or
            plan.budget.reservoir_balance_before !=
                self.reservoir.balance_bits or
            !std.meta.eql(
                pending_budget,
                plan.budget,
            ) or !std.meta.eql(
            plan.reservoir_pending.config,
            self.config.rate_control,
        ) or plan.granule_position < self.granule_position or
            plan.granule_position > maximum_granule or
            (!plan.end and plan.granule_position != maximum_granule) or
            plan.end != (plan.classification == null) or
            plan.end !=
                (plan.lookahead_after.pending_large_block == null))
            return error.InvalidVorbisPcmPacketPlan;

        if (plan.end) {
            if (!std.meta.eql(plan.classifier_after, self.classifier))
                return error.InvalidVorbisPcmPacketPlan;
        } else {
            const classification = plan.classification orelse
                return error.InvalidVorbisPcmPacketPlan;
            if (!vorbisPcmBlockClassificationValid(classification) or
                plan.classifier_after.large_block !=
                    classification.recommended_large_block or
                plan.classifier_after.short_blocks_remaining !=
                    classification.short_blocks_remaining or
                plan.lookahead_after.pending_large_block !=
                    classification.recommended_large_block)
                return error.InvalidVorbisPcmPacketPlan;
        }
    }

    fn validateState(self: *const VorbisPcmPacketSequence) !void {
        try validateVorbisPcmBlockClassifierConfig(
            self.config.classifier,
        );
        try validateVorbisRateControlConfig(
            self.config.rate_control,
        );
        if (self.config.adaptive_rate) |adaptive_rate| {
            try validateVorbisAdaptiveRatePolicyConfig(adaptive_rate);
        }
        if (!self.classifier.valid() or
            !self.lookahead.valid() or
            !self.reservoir.valid() or
            !std.meta.eql(
                self.reservoir.config,
                self.config.rate_control,
            ) or
            self.reservoir.pending != null or
            self.lookahead.frames.packet_index !=
                self.reservoir.packet_index or
            self.lookahead.frames.center < 0 or
            self.granule_position >
                @as(u64, @intCast(self.lookahead.frames.center)))
            return error.InvalidVorbisPcmPacketSequenceState;

        if (self.revision == 0) {
            if (self.ended or
                self.granule_position != 0 or
                self.lookahead.frames.packet_index != 0 or
                self.lookahead.frames.center != 0 or
                self.lookahead.pending_large_block != null or
                self.classifier.initialized)
                return error.InvalidVorbisPcmPacketSequenceState;
            return;
        }

        if (!self.ended) {
            const pending_large_block =
                self.lookahead.pending_large_block orelse
                return error.InvalidVorbisPcmPacketSequenceState;
            if (self.classifier.large_block != pending_large_block)
                return error.InvalidVorbisPcmPacketSequenceState;
        }

        if (self.lookahead.frames.packet_index != 0) {
            const center: u64 = @intCast(self.lookahead.frames.center);
            if (self.granule_position >= center)
                return error.InvalidVorbisPcmPacketSequenceState;
            const lag = center - self.granule_position;
            const maximum_lag: u64 = if (self.ended) 8192 else 4096;
            if (lag < 32 or lag > maximum_lag)
                return error.InvalidVorbisPcmPacketSequenceState;
        }

        const expected_revision = std.math.add(
            u64,
            self.lookahead.frames.packet_index,
            1,
        ) catch return error.InvalidVorbisPcmPacketSequenceState;
        if (self.revision != expected_revision or
            !self.classifier.initialized or
            self.ended !=
                (self.lookahead.pending_large_block == null))
            return error.InvalidVorbisPcmPacketSequenceState;
    }
};

pub fn validateVorbisPcmFrameTransition(
    before: VorbisPcmBlockLookahead,
    frame: VorbisPcmFramePlan,
    after: VorbisPcmBlockLookahead,
    end: bool,
) !void {
    if (!before.valid() or !after.valid())
        return error.InvalidVorbisPcmPacketPlan;
    const current_large_block = before.pending_large_block orelse
        return error.InvalidVorbisPcmPacketPlan;
    const next_large_block = if (end)
        current_large_block
    else
        after.pending_large_block orelse
            return error.InvalidVorbisPcmPacketPlan;
    if (end != (after.pending_large_block == null) or
        frame.header.large_block != current_large_block or
        frame.header.block_size < 64 or
        frame.header.block_size > 8192 or
        !std.math.isPowerOfTwo(frame.header.block_size) or
        frame.header.payload_bit_offset == 0 or
        frame.header.payload_bit_offset > 11 or
        frame.pcm_advance < 32 or
        frame.pcm_advance > 4096 or
        frame.pcm_advance % 16 != 0)
        return error.InvalidVorbisPcmPacketPlan;

    if (current_large_block) {
        if (frame.header.previous_window_flag !=
            before.frames.previous_large_block or
            frame.header.next_window_flag != next_large_block or
            frame.header.payload_bit_offset < 3)
            return error.InvalidVorbisPcmPacketPlan;
    } else if (frame.header.previous_window_flag != null or
        frame.header.next_window_flag != null)
        return error.InvalidVorbisPcmPacketPlan;

    const source_start = std.math.sub(
        i64,
        before.frames.center,
        frame.header.block_size / 2,
    ) catch return error.InvalidVorbisPcmPacketPlan;
    const next_center = std.math.add(
        i64,
        before.frames.center,
        frame.pcm_advance,
    ) catch return error.InvalidVorbisPcmPacketPlan;
    const next_packet_index = std.math.add(
        u64,
        before.frames.packet_index,
        1,
    ) catch return error.InvalidVorbisPcmPacketPlan;
    if (frame.packet_index != before.frames.packet_index or
        frame.source_start != source_start or
        frame.next_center != next_center or
        after.frames.packet_index != next_packet_index or
        after.frames.center != next_center or
        after.frames.previous_large_block != current_large_block)
        return error.InvalidVorbisPcmPacketPlan;
}

pub fn vorbisPcmBlockClassificationValid(
    classification: VorbisPcmBlockClassification,
) bool {
    const analysis = classification.analysis;
    return std.math.isFinite(analysis.peak) and
        analysis.peak >= 0 and
        std.math.isFinite(analysis.rms) and
        analysis.rms >= 0 and
        analysis.rms <= analysis.peak and
        std.math.isFinite(analysis.maximum_energy_ratio) and
        analysis.maximum_energy_ratio >= 1 and
        std.math.isFinite(classification.cross_block_energy_ratio) and
        classification.cross_block_energy_ratio >= 1;
}

pub fn vorbisPcmBlockDecision(
    classification: VorbisPcmBlockClassification,
) VorbisPcmBlockAnalysis {
    var decision = classification.analysis;
    decision.recommended_large_block =
        classification.recommended_large_block;
    return decision;
}

pub fn vorbisPcmPacketGranule(next_center: i64) !u64 {
    if (next_center < 0)
        return error.InvalidVorbisEncoderGranulePosition;
    return @intCast(next_center);
}

pub fn vorbisPcmFrameGranule(frame: VorbisPcmFramePlan) !u64 {
    const completed_center = std.math.sub(
        i64,
        frame.next_center,
        frame.pcm_advance,
    ) catch return error.InvalidVorbisEncoderGranulePosition;
    return vorbisPcmPacketGranule(completed_center);
}

/// Copies one planned block and zero-pads outside the source range.
pub fn extractVorbisPcmBlock(
    comptime Float: type,
    inputs: []const []const Float,
    source_start: i64,
    block_size: u16,
    outputs: []const []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM extraction requires f32 or f64");
    if (inputs.len == 0 or inputs.len > 255 or
        outputs.len != inputs.len)
        return error.InvalidVorbisChannelBundle;
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        return error.InvalidVorbisBlockSizes;
    const source_length = inputs[0].len;
    if (source_length > std.math.maxInt(i64))
        return error.InvalidVorbisPcmFrameRange;
    const block_end = std.math.add(
        i64,
        source_start,
        block_size,
    ) catch return error.InvalidVorbisPcmFrameRange;

    for (inputs, 0..) |input, channel| {
        if (input.len != source_length or
            outputs[channel].len != block_size)
            return error.InvalidVorbisPcmBlockShape;
        for (input) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidVorbisPcmSample;
        }
        if (vorbisConstSlicesOverlap(
            Float,
            input,
            outputs[channel],
        )) return error.OverlappingVorbisPcmBlockOutput;
        for (outputs[0..channel]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                outputs[channel],
                earlier,
            )) return error.OverlappingVorbisPcmBlockOutput;
        }
    }

    const copy_start = @max(source_start, 0);
    const copy_end = @min(
        block_end,
        @as(i64, @intCast(source_length)),
    );
    const copy_count: usize = if (copy_end > copy_start)
        @intCast(copy_end - copy_start)
    else
        0;
    const source_offset: usize = if (copy_count != 0)
        @intCast(copy_start)
    else
        0;
    const destination_offset: usize = if (copy_count != 0)
        @intCast(copy_start - source_start)
    else
        0;
    for (inputs, outputs) |input, output| {
        @memset(output, 0);
        if (copy_count != 0) {
            @memcpy(
                output[destination_offset..][0..copy_count],
                input[source_offset..][0..copy_count],
            );
        }
    }
}

pub fn parseVorbisAudioPacketHeader(
    packet: []const u8,
    identification: VorbisIdentification,
    setup: VorbisSetup,
) !VorbisAudioPacketHeader {
    if (setup.modes.len == 0 or setup.modes.len != setup.summary.mode_count)
        return error.InvalidVorbisSetupState;
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    for (setup.modes) |mode| {
        if (mode.mapping >= setup.summary.mapping_count)
            return error.InvalidVorbisSetupState;
    }
    var reader = VorbisBitReader{ .bytes = packet };
    const packet_type =
        readVorbisAudioBits(&reader, 1) catch |err| return err;
    if (packet_type != 0)
        return error.InvalidVorbisAudioPacketType;
    const mode_bits = vorbisILog(setup.modes.len - 1);
    const mode_number =
        readVorbisAudioBits(&reader, mode_bits) catch |err| return err;
    if (mode_number >= setup.modes.len)
        return error.InvalidVorbisAudioPacketMode;
    const mode = setup.modes[mode_number];
    const previous_window_flag: ?bool = if (mode.large_block)
        (readVorbisAudioBits(&reader, 1) catch |err| return err) != 0
    else
        null;
    const next_window_flag: ?bool = if (mode.large_block)
        (readVorbisAudioBits(&reader, 1) catch |err| return err) != 0
    else
        null;
    return .{
        .mode_number = @intCast(mode_number),
        .large_block = mode.large_block,
        .previous_window_flag = previous_window_flag,
        .next_window_flag = next_window_flag,
        .block_size = if (mode.large_block)
            identification.large_block_size
        else
            identification.small_block_size,
        .payload_bit_offset = reader.bit_offset,
    };
}

pub fn synthesizeVorbisWindow(
    comptime Float: type,
    identification: VorbisIdentification,
    packet: VorbisAudioPacketHeader,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis windows require f32 or f64 output");
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    const block_size: usize = packet.block_size;
    const expected_block_size: usize = if (packet.large_block)
        identification.large_block_size
    else
        identification.small_block_size;
    if (block_size != expected_block_size or output.len != block_size)
        return error.InvalidVorbisWindowShape;
    if (packet.large_block) {
        if (packet.previous_window_flag == null or
            packet.next_window_flag == null)
            return error.InvalidVorbisWindowState;
    } else if (packet.previous_window_flag != null or
        packet.next_window_flag != null)
        return error.InvalidVorbisWindowState;

    fillVorbisWindow(
        Float,
        identification.small_block_size,
        packet.previous_window_flag orelse true,
        packet.next_window_flag orelse true,
        output,
    );
}

pub fn VorbisWindowPlan(
    comptime Float: type,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis windows require f32 or f64");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    return struct {
        const Self = @This();

        small: [small_block_size]Float,
        large: [2][2][large_block_size]Float,

        pub fn init() Self {
            var self: Self = undefined;
            fillVorbisWindow(
                Float,
                small_block_size,
                true,
                true,
                &self.small,
            );
            for (0..2) |previous| {
                for (0..2) |next| {
                    fillVorbisWindow(
                        Float,
                        small_block_size,
                        previous != 0,
                        next != 0,
                        &self.large[previous][next],
                    );
                }
            }
            return self;
        }

        pub fn get(
            self: *const Self,
            packet: VorbisAudioPacketHeader,
        ) ![]const Float {
            if (packet.large_block) {
                if (packet.block_size != large_block_size or
                    packet.previous_window_flag == null or
                    packet.next_window_flag == null)
                    return error.InvalidVorbisWindowState;
                const previous = packet.previous_window_flag orelse
                    return error.InvalidVorbisWindowState;
                const next = packet.next_window_flag orelse
                    return error.InvalidVorbisWindowState;
                return &self.large[
                    @intFromBool(previous)
                ][@intFromBool(next)];
            }
            if (packet.block_size != small_block_size or
                packet.previous_window_flag != null or
                packet.next_window_flag != null)
                return error.InvalidVorbisWindowState;
            return &self.small;
        }
    };
}

pub fn fillVorbisWindow(
    comptime Float: type,
    small_block_size: usize,
    previous_large: bool,
    next_large: bool,
    output: []Float,
) void {
    const block_size = output.len;
    const left_start: usize =
        if (block_size != small_block_size and !previous_large)
            block_size / 4 - small_block_size / 4
        else
            0;
    const left_end: usize =
        if (block_size != small_block_size and !previous_large)
            block_size / 4 + small_block_size / 4
        else
            block_size / 2;
    const right_start: usize =
        if (block_size != small_block_size and !next_large)
            block_size * 3 / 4 - small_block_size / 4
        else
            block_size / 2;
    const right_end: usize =
        if (block_size != small_block_size and !next_large)
            block_size * 3 / 4 + small_block_size / 4
        else
            block_size;

    @memset(output, 0);
    fillVorbisWindowSlope(Float, output[left_start..left_end], false);
    @memset(output[left_end..right_start], 1);
    fillVorbisWindowSlope(Float, output[right_start..right_end], true);
}

pub fn fillVorbisWindowSlope(
    comptime Float: type,
    output: []Float,
    reverse: bool,
) void {
    const length: f64 = @floatFromInt(output.len);
    for (output, 0..) |*value, index| {
        const position: f64 = if (reverse)
            @floatFromInt(output.len - index)
        else
            @floatFromInt(index + 1);
        const inner = @sin(
            ((position - 0.5) / length) * (std.math.pi / 2.0),
        );
        value.* = @floatCast(@sin(
            (std.math.pi / 2.0) * inner * inner,
        ));
    }
}

pub fn VorbisInverseMdct(
    comptime Float: type,
    comptime block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis inverse MDCT requires f32 or f64");
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        @compileError("Vorbis block size must be a power of two from 64 to 8192");

    const Transform = fft.Transform(Float, block_size);
    const coefficient_count = block_size / 2;

    return struct {
        const Self = @This();

        transform: Transform,
        coefficient_rotations: [coefficient_count]Transform.Value,
        output_rotations: [block_size]Transform.Value,
        work: [block_size]Transform.Value,

        pub fn init() Self {
            var self: Self = undefined;
            self.transform = Transform.init();
            const coefficient_scale =
                std.math.pi /
                @as(Float, @floatFromInt(coefficient_count));
            const rotation_offset =
                @as(Float, @floatFromInt(coefficient_count)) / 2.0 + 0.5;
            for (&self.coefficient_rotations, 0..) |*rotation, index| {
                const angle = coefficient_scale * rotation_offset *
                    (@as(Float, @floatFromInt(index)) + 0.5);
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            const output_scale =
                std.math.pi / @as(Float, @floatFromInt(block_size));
            for (&self.output_rotations, 0..) |*rotation, index| {
                const angle =
                    output_scale * @as(Float, @floatFromInt(index));
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            return self;
        }

        /// Input and output may overlap. Failures preserve output.
        pub fn process(
            self: *Self,
            input: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, null, output);
        }

        pub fn processWindowed(
            self: *Self,
            input: []const Float,
            window: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, window, output);
        }

        fn processInternal(
            self: *Self,
            input: []const Float,
            window: ?[]const Float,
            output: []Float,
        ) !void {
            if (input.len != coefficient_count or output.len != block_size)
                return error.InvalidVorbisMdctShape;
            for (input) |coefficient| {
                if (!std.math.isFinite(coefficient))
                    return error.InvalidVorbisMdctInput;
            }
            if (window) |values| {
                if (values.len != block_size)
                    return error.InvalidVorbisMdctShape;
                for (values) |value| {
                    if (!std.math.isFinite(value))
                        return error.InvalidVorbisMdctInput;
                }
            }

            @memset(&self.work, .{});
            for (
                input,
                self.coefficient_rotations,
                self.work[0..coefficient_count],
            ) |
                coefficient,
                rotation,
                *value,
            | {
                value.* = .{
                    .real = coefficient * rotation.real,
                    .imaginary = coefficient * rotation.imaginary,
                };
            }
            try self.transform.inverse(&self.work);

            for (&self.work, self.output_rotations, 0..) |
                *value,
                rotation,
                index,
            | {
                var sample = @as(Float, @floatFromInt(block_size)) *
                    (value.real * rotation.real -
                        value.imaginary * rotation.imaginary);
                if (window) |values| sample *= values[index];
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisMdctOutput;
                value.real = sample;
            }
            for (output, self.work) |*sample, value| {
                sample.* = value.real;
            }
        }
    };
}

pub fn VorbisForwardMdct(
    comptime Float: type,
    comptime block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis forward MDCT requires f32 or f64");
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        @compileError("Vorbis block size must be a power of two from 64 to 8192");

    const Transform = fft.Transform(Float, block_size);
    const coefficient_count = block_size / 2;

    return struct {
        const Self = @This();

        transform: Transform,
        input_rotations: [block_size]Transform.Value,
        coefficient_rotations: [coefficient_count]Transform.Value,
        work: [block_size]Transform.Value,

        pub fn init() Self {
            var self: Self = undefined;
            self.transform = Transform.init();
            const input_scale =
                std.math.pi / @as(Float, @floatFromInt(block_size));
            for (&self.input_rotations, 0..) |*rotation, index| {
                const angle =
                    input_scale * @as(Float, @floatFromInt(index));
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            const coefficient_scale =
                std.math.pi /
                @as(Float, @floatFromInt(coefficient_count));
            const rotation_offset =
                @as(Float, @floatFromInt(coefficient_count)) / 2.0 + 0.5;
            for (&self.coefficient_rotations, 0..) |*rotation, index| {
                const angle = coefficient_scale * rotation_offset *
                    (@as(Float, @floatFromInt(index)) + 0.5);
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            return self;
        }

        /// Input and output may overlap. Failures preserve output.
        pub fn process(
            self: *Self,
            input: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, null, output);
        }

        pub fn processWindowed(
            self: *Self,
            input: []const Float,
            window: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, window, output);
        }

        fn processInternal(
            self: *Self,
            input: []const Float,
            window: ?[]const Float,
            output: []Float,
        ) !void {
            if (input.len != block_size or
                output.len != coefficient_count)
                return error.InvalidVorbisMdctShape;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisMdctInput;
            }
            if (window) |values| {
                if (values.len != block_size)
                    return error.InvalidVorbisMdctShape;
                for (values) |value| {
                    if (!std.math.isFinite(value))
                        return error.InvalidVorbisMdctInput;
                }
            }

            for (
                input,
                self.input_rotations,
                &self.work,
                0..,
            ) |sample, rotation, *value, index| {
                const windowed = if (window) |values|
                    sample * values[index]
                else
                    sample;
                if (!std.math.isFinite(windowed))
                    return error.InvalidVorbisMdctInput;
                value.* = .{
                    .real = windowed * rotation.real,
                    .imaginary = windowed * rotation.imaginary,
                };
            }
            try self.transform.inverse(&self.work);

            const scale: Float = 4.0;
            for (
                self.work[0..coefficient_count],
                self.coefficient_rotations,
            ) |*value, rotation| {
                const coefficient = scale *
                    (value.real * rotation.real -
                        value.imaginary * rotation.imaginary);
                if (!std.math.isFinite(coefficient))
                    return error.InvalidVorbisMdctOutput;
                value.real = coefficient;
            }
            for (
                output,
                self.work[0..coefficient_count],
            ) |*coefficient, value| {
                coefficient.* = value.real;
            }
        }
    };
}

pub fn VorbisPcmBlockTransform(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM transforms require f32 or f64");
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis PCM transforms require 1 through 255 channels");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    const Windows =
        VorbisWindowPlan(Float, small_block_size, large_block_size);
    const SmallMdct = VorbisForwardMdct(Float, small_block_size);
    const LargeMdct = VorbisForwardMdct(Float, large_block_size);

    return struct {
        const Self = @This();

        windows: Windows,
        small_mdct: SmallMdct,
        large_mdct: LargeMdct,

        pub fn init() Self {
            return .{
                .windows = .init(),
                .small_mdct = .init(),
                .large_mdct = .init(),
            };
        }

        pub fn requiredScratch(
            header: VorbisAudioPacketHeader,
        ) !usize {
            const block_size = try checkedBlockSize(header);
            return channel_count * (block_size / 2);
        }

        /// All channel outputs commit after every transform succeeds.
        pub fn process(
            self: *Self,
            header: VorbisAudioPacketHeader,
            inputs: []const []const Float,
            outputs: []const []Float,
            scratch: []Float,
        ) !void {
            const block_size = try checkedBlockSize(header);
            const coefficient_count = block_size / 2;
            const required_scratch = channel_count * coefficient_count;
            if (inputs.len != channel_count or outputs.len != channel_count)
                return error.InvalidVorbisPcmBlockShape;
            if (scratch.len < required_scratch)
                return error.VorbisPcmBlockScratchTooSmall;
            const used_scratch = scratch[0..required_scratch];
            for (inputs, 0..) |input, channel| {
                if (input.len != block_size or
                    outputs[channel].len != coefficient_count)
                    return error.InvalidVorbisPcmBlockShape;
                for (input) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.InvalidVorbisPcmSample;
                }
                if (vorbisConstSlicesOverlap(
                    Float,
                    input,
                    used_scratch,
                )) return error.OverlappingVorbisPcmBlockScratch;
                for (outputs[0..channel]) |earlier| {
                    if (vorbisSlicesOverlap(
                        Float,
                        outputs[channel],
                        earlier,
                    )) return error.OverlappingVorbisPcmBlockOutput;
                }
                if (vorbisSlicesOverlap(
                    Float,
                    outputs[channel],
                    used_scratch,
                )) return error.OverlappingVorbisPcmBlockScratch;
            }

            const window = try self.windows.get(header);
            for (inputs, 0..) |input, channel| {
                const staged =
                    used_scratch[channel * coefficient_count ..][0..coefficient_count];
                if (header.large_block) {
                    try self.large_mdct.processWindowed(
                        input,
                        window,
                        staged,
                    );
                } else {
                    try self.small_mdct.processWindowed(
                        input,
                        window,
                        staged,
                    );
                }
            }
            for (outputs, 0..) |output, channel| {
                @memcpy(
                    output,
                    used_scratch[channel * coefficient_count ..][0..coefficient_count],
                );
            }
        }

        fn checkedBlockSize(
            header: VorbisAudioPacketHeader,
        ) !usize {
            const expected: usize = if (header.large_block)
                large_block_size
            else
                small_block_size;
            if (header.block_size != expected)
                return error.InvalidVorbisPcmBlockShape;
            if (header.large_block) {
                if (header.previous_window_flag == null or
                    header.next_window_flag == null)
                    return error.InvalidVorbisWindowState;
            } else if (header.previous_window_flag != null or
                header.next_window_flag != null)
                return error.InvalidVorbisWindowState;
            return expected;
        }
    };
}

pub const VorbisPcmFrameAnalysisStorageRequirements = struct {
    pcm_values: usize,
    transform_values: usize,
    spectrum_values: usize,
    analyses: usize,
    floor_values: usize,
    threshold_values: usize,
};

pub fn VorbisPcmFrameAnalysisScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        pcm: []Float,
        transform: []Float,
        spectra: []Float,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisPcmFrameAnalysisStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        spectra: []Float,
        analyses: []VorbisPsychoacousticAnalysis,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisPcmFrameAnalysisPlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        frame: VorbisPcmFramePlan,
        spectra: []const Float,
        analyses: []const VorbisPsychoacousticAnalysis,
        floor_targets: []const Float,
        noise_thresholds: []const Float,
        coefficient_count: usize,
    };
}

pub fn VorbisPcmFrameAnalyzer(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const Transform = VorbisPcmBlockTransform(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );

    return struct {
        const Self = @This();

        transform: Transform,

        pub fn init() Self {
            return .{ .transform = .init() };
        }

        pub fn requiredStorage(
            header: VorbisAudioPacketHeader,
        ) !VorbisPcmFrameAnalysisStorageRequirements {
            const transform_values =
                try Transform.requiredScratch(header);
            const block_size: usize = header.block_size;
            const pcm_values = std.math.mul(
                usize,
                channel_count,
                block_size,
            ) catch return error.VorbisPcmFrameAnalysisSizeOverflow;
            const psychoacoustic =
                try requiredVorbisAudioPsychoacousticStorage(
                    channel_count,
                    block_size / 2,
                );
            return .{
                .pcm_values = pcm_values,
                .transform_values = transform_values,
                .spectrum_values = psychoacoustic.floor_values,
                .analyses = psychoacoustic.analyses,
                .floor_values = psychoacoustic.floor_values,
                .threshold_values = psychoacoustic.threshold_values,
            };
        }

        pub fn analyze(
            self: *Self,
            inputs: []const []const Float,
            frame: VorbisPcmFramePlan,
            config: VorbisPsychoacousticConfig,
            sample_rate: u32,
            scratch: VorbisPcmFrameAnalysisScratch(Float),
            storage: VorbisPcmFrameAnalysisStorage(Float),
        ) !VorbisPcmFrameAnalysisPlan(Float) {
            const requirements =
                try requiredStorage(frame.header);
            if (inputs.len != channel_count)
                return error.InvalidVorbisChannelBundle;
            if (scratch.pcm.len < requirements.pcm_values or
                scratch.transform.len <
                    requirements.transform_values or
                scratch.spectra.len <
                    requirements.spectrum_values or
                scratch.floor_targets.len <
                    requirements.floor_values or
                scratch.noise_thresholds.len <
                    requirements.threshold_values)
                return error.VorbisPcmFrameAnalysisScratchTooSmall;
            if (storage.spectra.len <
                requirements.spectrum_values or
                storage.analyses.len < requirements.analyses or
                storage.floor_targets.len <
                    requirements.floor_values or
                storage.noise_thresholds.len <
                    requirements.threshold_values)
                return error.VorbisPcmFrameAnalysisStorageTooSmall;

            const pcm = scratch.pcm[0..requirements.pcm_values];
            const transform =
                scratch.transform[0..requirements.transform_values];
            const trial_spectra =
                scratch.spectra[0..requirements.spectrum_values];
            const trial_floor =
                scratch.floor_targets[0..requirements.floor_values];
            const trial_thresholds =
                scratch.noise_thresholds[0..requirements.threshold_values];
            const spectra =
                storage.spectra[0..requirements.spectrum_values];
            const analyses =
                storage.analyses[0..requirements.analyses];
            const floor_targets =
                storage.floor_targets[0..requirements.floor_values];
            const noise_thresholds =
                storage.noise_thresholds[0..requirements.threshold_values];
            try rejectVorbisPcmFrameAnalysisOverlap(
                Float,
                inputs,
                pcm,
                transform,
                trial_spectra,
                trial_floor,
                trial_thresholds,
                spectra,
                analyses,
                floor_targets,
                noise_thresholds,
            );

            const block_size: usize = frame.header.block_size;
            const coefficient_count = block_size / 2;
            var pcm_channels: [channel_count][]Float = undefined;
            var pcm_inputs: [channel_count][]const Float = undefined;
            var spectrum_channels: [channel_count][]Float = undefined;
            var spectrum_inputs: [channel_count][]const Float =
                undefined;
            for (0..channel_count) |channel| {
                pcm_channels[channel] =
                    pcm[channel * block_size ..][0..block_size];
                pcm_inputs[channel] = pcm_channels[channel];
                spectrum_channels[channel] =
                    trial_spectra[channel * coefficient_count ..][0..coefficient_count];
                spectrum_inputs[channel] =
                    spectrum_channels[channel];
            }
            try extractVorbisPcmBlock(
                Float,
                inputs,
                frame.source_start,
                frame.header.block_size,
                &pcm_channels,
            );
            try self.transform.process(
                frame.header,
                &pcm_inputs,
                &spectrum_channels,
                transform,
            );
            const psychoacoustic =
                try analyzeVorbisAudioPsychoacoustics(
                    Float,
                    &spectrum_inputs,
                    sample_rate,
                    config,
                    .{
                        .floor_targets = trial_floor,
                        .noise_thresholds = trial_thresholds,
                    },
                    .{
                        .analyses = analyses,
                        .floor_targets = floor_targets,
                        .noise_thresholds = noise_thresholds,
                    },
                );
            @memcpy(spectra, trial_spectra);
            return .{
                .frame = frame,
                .spectra = spectra,
                .analyses = psychoacoustic.analyses,
                .floor_targets = psychoacoustic.floor_targets,
                .noise_thresholds = psychoacoustic.noise_thresholds,
                .coefficient_count = coefficient_count,
            };
        }
    };
}

pub fn rejectVorbisPcmFrameAnalysisOverlap(
    comptime Float: type,
    inputs: []const []const Float,
    pcm: []Float,
    transform: []Float,
    trial_spectra: []Float,
    trial_floor: []Float,
    trial_thresholds: []Float,
    spectra: []Float,
    analyses: []VorbisPsychoacousticAnalysis,
    floor_targets: []Float,
    noise_thresholds: []Float,
) !void {
    const values = [_][]Float{
        pcm,
        transform,
        trial_spectra,
        trial_floor,
        trial_thresholds,
        spectra,
        floor_targets,
        noise_thresholds,
    };
    for (values, 0..) |current, index| {
        for (values[0..index]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                current,
                earlier,
            )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        }
        if (vorbisTypedSlicesOverlap(
            Float,
            current,
            VorbisPsychoacousticAnalysis,
            analyses,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    }
    const analysis_bytes = std.mem.sliceAsBytes(analyses);
    if (vorbisSliceOverlapsBytes(
        []const Float,
        inputs,
        analysis_bytes,
    )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    for (inputs) |input| {
        if (vorbisSliceOverlapsBytes(
            Float,
            input,
            analysis_bytes,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    }
    for (values) |destination| {
        const destination_bytes = std.mem.sliceAsBytes(destination);
        if (vorbisSliceOverlapsBytes(
            []const Float,
            inputs,
            destination_bytes,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        for (inputs) |input| {
            if (vorbisSliceOverlapsBytes(
                Float,
                input,
                destination_bytes,
            )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        }
    }
}

pub fn VorbisOverlapAdd(
    comptime Float: type,
    comptime maximum_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis overlap-add requires f32 or f64");
    if (maximum_block_size < 64 or maximum_block_size > 8192 or
        !std.math.isPowerOfTwo(maximum_block_size))
        @compileError("maximum block size must be a power of two from 64 to 8192");

    return struct {
        const Self = @This();

        previous: [maximum_block_size]Float = @splat(0),
        pending: [maximum_block_size / 2]Float = @splat(0),
        previous_size: usize = 0,

        pub fn reset(self: *Self) void {
            self.previous = @splat(0);
            self.pending = @splat(0);
            self.previous_size = 0;
        }

        pub fn primed(self: *const Self) bool {
            return self.valid() and self.previous_size != 0;
        }

        pub fn previousBlockSize(self: *const Self) usize {
            return if (self.valid()) self.previous_size else 0;
        }

        pub fn valid(self: *const Self) bool {
            if (self.previous_size == 0) return true;
            if (self.previous_size > maximum_block_size or
                self.previous_size < 64 or
                !std.math.isPowerOfTwo(self.previous_size))
            {
                return false;
            }
            for (self.previous[0..self.previous_size]) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }

        /// The first block primes state and returns no samples.
        pub fn push(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
        ) !usize {
            const output_count = try self.prepare(windowed_block, output);
            self.commitPrepared(windowed_block, output, output_count);
            return output_count;
        }

        fn prepare(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
        ) !usize {
            if (!self.valid()) return error.InvalidVorbisOverlapState;
            if (windowed_block.len < 64 or
                windowed_block.len > maximum_block_size or
                !std.math.isPowerOfTwo(windowed_block.len))
                return error.InvalidVorbisOverlapBlock;
            for (windowed_block) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisOverlapInput;
            }
            if (self.previous_size == 0) {
                return 0;
            }
            const output_count =
                self.previous_size / 4 + windowed_block.len / 4;
            if (output.len < output_count)
                return error.VorbisOverlapOutputTooSmall;
            if (vorbisConstSlicesOverlap(Float, windowed_block, output) or
                vorbisConstSlicesOverlap(
                    Float,
                    windowed_block,
                    self.previous[0..self.previous_size],
                ) or
                vorbisConstSlicesOverlap(
                    Float,
                    output,
                    self.previous[0..self.previous_size],
                ) or
                vorbisConstSlicesOverlap(
                    Float,
                    output,
                    self.pending[0..output_count],
                ))
                return error.OverlappingVorbisOverlapBuffer;

            const previous_size: i64 = @intCast(self.previous_size);
            const current_size: i64 = @intCast(windowed_block.len);
            const current_start =
                @divExact(previous_size * 3, 4) -
                @divExact(current_size, 4);
            const output_start = @divExact(previous_size, 2);
            for (self.pending[0..output_count], 0..) |*sample, index| {
                const position =
                    output_start + @as(i64, @intCast(index));
                var sum: Float = 0;
                if (position >= 0 and position < previous_size) {
                    sum += self.previous[@intCast(position)];
                }
                const current_index = position - current_start;
                if (current_index >= 0 and current_index < current_size) {
                    sum += windowed_block[@intCast(current_index)];
                }
                if (!std.math.isFinite(sum))
                    return error.InvalidVorbisOverlapOutput;
                sample.* = sum;
            }

            return output_count;
        }

        fn commitPrepared(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
            output_count: usize,
        ) void {
            @memcpy(output[0..output_count], self.pending[0..output_count]);
            @memcpy(
                self.previous[0..windowed_block.len],
                windowed_block,
            );
            self.previous_size = windowed_block.len;
        }
    };
}

pub fn VorbisChannelOverlapAdd(
    comptime Float: type,
    comptime channel_count: usize,
    comptime maximum_block_size: usize,
) type {
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis channel count must be from 1 to 255");
    const ChannelState = VorbisOverlapAdd(Float, maximum_block_size);

    return struct {
        const Self = @This();

        channels: [channel_count]ChannelState =
            [_]ChannelState{.{}} ** channel_count,

        pub fn reset(self: *Self) void {
            for (&self.channels) |*channel| channel.reset();
        }

        pub fn primed(self: *const Self) bool {
            return self.valid() and self.channels[0].primed();
        }

        pub fn valid(self: *const Self) bool {
            const previous_size = self.channels[0].previous_size;
            for (&self.channels) |*channel| {
                if (!channel.valid() or
                    channel.previous_size != previous_size)
                {
                    return false;
                }
            }
            return true;
        }

        pub fn previousBlockSize(self: *const Self) !usize {
            if (!self.valid())
                return error.InvalidVorbisChannelOverlapState;
            return self.channels[0].previous_size;
        }

        /// Failures preserve outputs and logical overlap history.
        pub fn push(
            self: *Self,
            windowed_blocks: []const []const Float,
            outputs: []const []Float,
        ) !usize {
            if (windowed_blocks.len != channel_count or
                outputs.len != channel_count)
                return error.InvalidVorbisChannelOverlapBundle;
            _ = try self.previousBlockSize();
            for (windowed_blocks, 0..) |input, channel| {
                for (outputs, 0..) |output, output_channel| {
                    if (vorbisConstSlicesOverlap(Float, input, output))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                    if (channel != output_channel and
                        vorbisConstSlicesOverlap(
                            Float,
                            outputs[channel],
                            output,
                        ))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                }
                for (&self.channels) |*state| {
                    if (vorbisConstSlicesOverlap(
                        Float,
                        input,
                        &state.previous,
                    ) or vorbisConstSlicesOverlap(
                        Float,
                        input,
                        &state.pending,
                    ))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                    for (outputs) |output| {
                        if (vorbisConstSlicesOverlap(
                            Float,
                            output,
                            &state.previous,
                        ) or vorbisConstSlicesOverlap(
                            Float,
                            output,
                            &state.pending,
                        ))
                            return error.OverlappingVorbisChannelOverlapBuffer;
                    }
                }
            }

            var output_count: ?usize = null;
            for (&self.channels, windowed_blocks, outputs) |
                *state,
                input,
                output,
            | {
                const count = try state.prepare(input, output);
                if (output_count) |expected| {
                    if (count != expected)
                        return error.InvalidVorbisChannelOverlapState;
                } else {
                    output_count = count;
                }
            }
            const prepared_output_count = output_count orelse
                return error.InvalidVorbisChannelOverlapState;
            for (&self.channels, windowed_blocks, outputs) |
                *state,
                input,
                output,
            | {
                state.commitPrepared(input, output, prepared_output_count);
            }
            return prepared_output_count;
        }
    };
}

pub const VorbisGranuleRange = struct {
    source_start: usize,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
};

pub const VorbisGranuleTracker = struct {
    decoded_samples: u64 = 0,
    position_offset: ?i64 = null,
    ended: bool = false,

    pub fn reset(self: *VorbisGranuleTracker) void {
        self.* = .{};
    }

    pub fn valid(self: *const VorbisGranuleTracker) bool {
        if (self.decoded_samples > std.math.maxInt(i64)) return false;
        if (self.decoded_samples == 0) {
            return self.position_offset == null and !self.ended;
        }
        if (self.position_offset) |offset| {
            const pcm_end = std.math.add(
                i64,
                offset,
                @intCast(self.decoded_samples),
            ) catch return false;
            if (pcm_end < 0) return false;
        }
        return !self.ended or self.position_offset != null;
    }

    /// Return the portion of one finished overlap range that belongs to the stream.
    pub fn trim(
        self: *VorbisGranuleTracker,
        nominal_sample_count: usize,
        granule_position: u64,
        end: bool,
    ) !VorbisGranuleRange {
        if (!self.valid())
            return error.InvalidVorbisGranuleTrackerState;
        if (self.ended) return error.VorbisGranuleStreamAlreadyEnded;
        if (nominal_sample_count == 0)
            return error.InvalidVorbisGranuleSampleCount;
        if (end and granule_position == unknown_granule)
            return error.MissingVorbisEndGranule;
        const decoded_before = self.decoded_samples;
        const decoded_after = std.math.add(
            u64,
            decoded_before,
            nominal_sample_count,
        ) catch return error.VorbisGranulePositionOverflow;
        if (decoded_after > std.math.maxInt(i64))
            return error.VorbisGranulePositionOverflow;

        var offset = self.position_offset;
        var source_start: usize = 0;
        var sample_count = nominal_sample_count;
        if (granule_position != unknown_granule) {
            const declared_end: i64 = @bitCast(granule_position);
            if (offset == null) {
                if (end and declared_end >= 0 and
                    declared_end <= @as(i64, @intCast(decoded_after)))
                {
                    if (declared_end <
                        @as(i64, @intCast(decoded_before)))
                        return error.InvalidVorbisEndGranule;
                    offset = 0;
                    sample_count =
                        @intCast(
                            declared_end -
                                @as(i64, @intCast(decoded_before)),
                        );
                } else {
                    offset = std.math.sub(
                        i64,
                        declared_end,
                        @intCast(decoded_after),
                    ) catch return error.VorbisGranulePositionOverflow;
                    const initial_offset = offset orelse
                        return error.VorbisGranulePositionOverflow;
                    if (initial_offset < 0) {
                        if (decoded_before != 0)
                            return error.LateVorbisInitialGranule;
                        const discarded: u64 = @intCast(-initial_offset);
                        if (discarded > nominal_sample_count)
                            return error.InvalidVorbisInitialGranule;
                        source_start = @intCast(discarded);
                        sample_count -= source_start;
                    }
                }
            } else {
                const known_offset = offset orelse
                    return error.VorbisGranulePositionOverflow;
                const expected_end = std.math.add(
                    i64,
                    known_offset,
                    @intCast(decoded_after),
                ) catch return error.VorbisGranulePositionOverflow;
                if (!end) {
                    if (declared_end != expected_end)
                        return error.InvalidVorbisGranulePosition;
                } else {
                    const earliest_end = std.math.add(
                        i64,
                        known_offset,
                        @intCast(decoded_before),
                    ) catch return error.VorbisGranulePositionOverflow;
                    if (declared_end < earliest_end or
                        declared_end > expected_end)
                        return error.InvalidVorbisEndGranule;
                    sample_count = @intCast(declared_end - earliest_end);
                }
            }
        }

        const pcm_start: ?i64 = if (offset) |known_offset|
            std.math.add(
                i64,
                known_offset,
                @as(i64, @intCast(decoded_before + source_start)),
            ) catch return error.VorbisGranulePositionOverflow
        else
            null;
        const pcm_end: ?i64 = if (pcm_start) |start|
            std.math.add(
                i64,
                start,
                @intCast(sample_count),
            ) catch return error.VorbisGranulePositionOverflow
        else
            null;

        self.decoded_samples = decoded_after;
        self.position_offset = offset;
        self.ended = end;
        return .{
            .source_start = source_start,
            .sample_count = sample_count,
            .pcm_start = pcm_start,
            .pcm_end = pcm_end,
        };
    }
};

pub fn vorbisDecodedSampleTimelineValid(
    audio_packet_count: u64,
    decoded_samples: u64,
) bool {
    if (audio_packet_count == 0) return decoded_samples == 0;
    const completed_packets = audio_packet_count - 1;
    const minimum_samples = std.math.mul(
        u64,
        completed_packets,
        32,
    ) catch return false;
    const maximum_samples = std.math.mul(
        u64,
        completed_packets,
        4096,
    ) catch std.math.maxInt(u64);
    return decoded_samples >= minimum_samples and
        decoded_samples <= maximum_samples;
}

pub fn vorbisGranuleOutputUpperBound(
    granules: VorbisGranuleTracker,
) ?u64 {
    if (!granules.valid()) return null;
    const offset = granules.position_offset orelse
        return granules.decoded_samples;
    if (offset >= 0) return granules.decoded_samples;
    const discarded = @as(u64, @intCast(-(offset + 1))) + 1;
    if (discarded > granules.decoded_samples) return null;
    return granules.decoded_samples - discarded;
}

pub fn VorbisPcmStreamScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis stream decoding requires f32 or f64");
    return struct {
        packet: VorbisAudioPacketScratch(Float),
        windowed: []Float,
    };
}

pub const VorbisPcmStreamResult = struct {
    packet: VorbisAudioPacketResult,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
};

pub const VorbisPcmConcealmentResult = struct {
    block_size: u16,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
    concealed_packet_count: u64,
};

pub const VorbisPcmSignalConcealmentConfig = struct {
    initial_gain: f64 = 1,
    final_gain: f64 = 0.5,
};

pub const VorbisChainedPcmStreamResult = struct {
    stream: VorbisPcmStreamResult,
    logical_stream_index: u64,
    global_pcm_start: u64,
    global_pcm_end: u64,
};

pub const VorbisChainedPcmConcealmentResult = struct {
    stream: VorbisPcmConcealmentResult,
    logical_stream_index: u64,
    global_pcm_start: u64,
    global_pcm_end: u64,
};

pub const VorbisPcmSeekCursor = struct {
    target_pcm: i64,
    reached: bool = false,

    pub fn init(target_pcm: i64) VorbisPcmSeekCursor {
        return .{ .target_pcm = target_pcm };
    }

    /// Select the suffix at or after the target from one decoded PCM range.
    pub fn select(
        self: *VorbisPcmSeekCursor,
        decoded: VorbisPcmStreamResult,
    ) !VorbisGranuleRange {
        if (decoded.sample_count == 0) {
            if (decoded.pcm_start != null or decoded.pcm_end != null)
                return error.InvalidVorbisPcmSeekRange;
            return .{
                .source_start = 0,
                .sample_count = 0,
                .pcm_start = null,
                .pcm_end = null,
            };
        }
        const pcm_start = decoded.pcm_start orelse
            return error.VorbisPcmSeekPositionUnavailable;
        const pcm_end = decoded.pcm_end orelse
            return error.VorbisPcmSeekPositionUnavailable;
        if (pcm_end < pcm_start or
            @as(u64, @intCast(pcm_end - pcm_start)) !=
                decoded.sample_count)
            return error.InvalidVorbisPcmSeekRange;

        if (self.reached or self.target_pcm <= pcm_start) {
            self.reached = true;
            return .{
                .source_start = 0,
                .sample_count = decoded.sample_count,
                .pcm_start = pcm_start,
                .pcm_end = pcm_end,
            };
        }
        if (self.target_pcm >= pcm_end) {
            self.reached = self.target_pcm == pcm_end;
            return .{
                .source_start = decoded.sample_count,
                .sample_count = 0,
                .pcm_start = pcm_end,
                .pcm_end = pcm_end,
            };
        }

        const source_start: usize =
            @intCast(self.target_pcm - pcm_start);
        self.reached = true;
        return .{
            .source_start = source_start,
            .sample_count = decoded.sample_count - source_start,
            .pcm_start = self.target_pcm,
            .pcm_end = pcm_end,
        };
    }
};

pub fn VorbisPcmStreamDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const PacketDecoder = VorbisAudioPacketDecoder(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );
    const ChannelOverlap = VorbisChannelOverlapAdd(
        Float,
        channel_count,
        large_block_size,
    );

    return struct {
        const Self = @This();
        const ConcealmentSource = union(enum) {
            silence,
            previous_signal: VorbisPcmSignalConcealmentConfig,
        };

        packets: PacketDecoder,
        overlap: ChannelOverlap = .{},
        granules: VorbisGranuleTracker = .{},
        audio_packet_count: u64 = 0,
        concealed_packet_count: u64 = 0,
        ended: bool = false,

        pub fn init() Self {
            return .{ .packets = .init() };
        }

        pub fn reset(self: *Self) void {
            self.overlap.reset();
            self.granules.reset();
            self.audio_packet_count = 0;
            self.concealed_packet_count = 0;
            self.ended = false;
        }

        pub fn valid(self: *const Self) bool {
            if (!self.overlap.valid() or
                !self.granules.valid() or
                self.concealed_packet_count > self.audio_packet_count or
                self.ended != self.granules.ended)
                return false;
            if (self.audio_packet_count == 0) {
                return !self.overlap.primed() and
                    self.concealed_packet_count == 0 and
                    self.granules.decoded_samples == 0 and
                    !self.ended;
            }
            return self.overlap.primed() and
                vorbisDecodedSampleTimelineValid(
                    self.audio_packet_count,
                    self.granules.decoded_samples,
                );
        }

        /// Returned samples occupy the prefix of every output channel.
        pub fn decode(
            self: *Self,
            packet: Packet,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisPcmStreamScratch(Float),
        ) !VorbisPcmStreamResult {
            if (!self.valid())
                return error.InvalidVorbisPcmStreamState;
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            if (self.audio_packet_count == std.math.maxInt(u64))
                return error.VorbisAudioPacketCountOverflow;
            if (self.concealed_packet_count > self.audio_packet_count)
                return error.InvalidVorbisPcmStreamState;
            const header = try parseVorbisAudioPacketHeader(
                packet.bytes,
                identification,
                setup,
            );
            const previous_size =
                try self.overlap.previousBlockSize();
            const nominal_sample_count = if (previous_size == 0)
                0
            else
                previous_size / 4 + header.block_size / 4;
            if (packet.end and nominal_sample_count == 0)
                return error.VorbisStreamEndedBeforePcm;
            if (outputs.len != channel_count)
                return error.InvalidVorbisAudioOutput;
            for (outputs) |output| {
                if (output.len < nominal_sample_count)
                    return error.VorbisOverlapOutputTooSmall;
            }
            const windowed_values = std.math.mul(
                usize,
                channel_count,
                header.block_size,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            if (scratch.windowed.len < windowed_values)
                return error.VorbisPcmStreamScratchTooSmall;

            var granule_trial = self.granules;
            const granule_range: VorbisGranuleRange =
                if (nominal_sample_count == 0)
                    .{
                        .source_start = 0,
                        .sample_count = 0,
                        .pcm_start = null,
                        .pcm_end = null,
                    }
                else
                    try granule_trial.trim(
                        nominal_sample_count,
                        packet.granule_position,
                        packet.end,
                    );

            var windowed_channels: [channel_count][]Float = undefined;
            for (&windowed_channels, 0..) |*channel, index| {
                channel.* =
                    scratch.windowed[index * header.block_size ..][0..header.block_size];
            }
            const packet_result = try self.packets.decode(
                packet.bytes,
                identification,
                setup,
                &windowed_channels,
                scratch.packet,
            );
            var const_windowed_channels: [channel_count][]const Float = undefined;
            for (&const_windowed_channels, windowed_channels) |
                *destination,
                source,
            | {
                destination.* = source;
            }
            _ = try self.overlap.push(
                &const_windowed_channels,
                outputs,
            );
            if (granule_range.source_start != 0) {
                for (outputs) |output| {
                    std.mem.copyForwards(
                        Float,
                        output[0..granule_range.sample_count],
                        output[granule_range.source_start..][0..granule_range.sample_count],
                    );
                }
            }

            self.granules = granule_trial;
            self.audio_packet_count += 1;
            self.ended = packet.end;
            return .{
                .packet = packet_result,
                .sample_count = granule_range.sample_count,
                .pcm_start = granule_range.pcm_start,
                .pcm_end = granule_range.pcm_end,
            };
        }

        /// Inserts one silent block while retaining overlap and granule timing.
        pub fn concealMissingPacket(
            self: *Self,
            large_block: bool,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            return self.concealMissingPacketWithSource(
                .silence,
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Repeats the retained windowed signal with bounded linear decay.
        pub fn concealMissingPacketWithPreviousSignal(
            self: *Self,
            large_block: bool,
            config: VorbisPcmSignalConcealmentConfig,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            return self.concealMissingPacketWithSource(
                .{ .previous_signal = config },
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        pub fn concealMissingPacketUsingPreviousBlockSignal(
            self: *Self,
            config: VorbisPcmSignalConcealmentConfig,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            const previous_size =
                try self.overlap.previousBlockSize();
            if (previous_size == 0)
                return error.VorbisPreviousSignalUnavailable;
            if (previous_size != small_block_size and
                previous_size != large_block_size)
                return error.InvalidVorbisChannelOverlapState;
            return self.concealMissingPacketWithPreviousSignal(
                previous_size == large_block_size,
                config,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        fn concealMissingPacketWithSource(
            self: *Self,
            source: ConcealmentSource,
            large_block: bool,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            if (!self.valid())
                return error.InvalidVorbisPcmStreamState;
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            if (self.audio_packet_count == std.math.maxInt(u64) or
                self.concealed_packet_count == std.math.maxInt(u64))
                return error.VorbisAudioPacketCountOverflow;
            if (self.concealed_packet_count > self.audio_packet_count)
                return error.InvalidVorbisPcmStreamState;
            if (identification.channel_count != channel_count or
                identification.small_block_size != small_block_size or
                identification.large_block_size != large_block_size)
                return error.VorbisDecoderConfigurationMismatch;
            if (identification.sample_rate == 0)
                return error.InvalidVorbisSampleRate;
            const block_size: u16 = if (large_block)
                large_block_size
            else
                small_block_size;
            const previous_size =
                try self.overlap.previousBlockSize();
            switch (source) {
                .silence => {},
                .previous_signal => |config| {
                    try validateVorbisPcmSignalConcealmentConfig(config);
                    if (previous_size == 0)
                        return error.VorbisPreviousSignalUnavailable;
                    if (previous_size > large_block_size or
                        previous_size < 64 or
                        !std.math.isPowerOfTwo(previous_size))
                    {
                        return error.InvalidVorbisChannelOverlapState;
                    }
                    for (self.overlap.channels) |channel| {
                        for (channel.previous[0..previous_size]) |sample| {
                            if (!std.math.isFinite(sample))
                                return error.InvalidVorbisChannelOverlapState;
                        }
                    }
                },
            }
            const nominal_sample_count = if (previous_size == 0)
                0
            else
                previous_size / 4 + block_size / 4;
            if (end and nominal_sample_count == 0)
                return error.VorbisStreamEndedBeforePcm;
            if (outputs.len != channel_count)
                return error.InvalidVorbisAudioOutput;
            for (outputs) |output| {
                if (output.len < nominal_sample_count)
                    return error.VorbisOverlapOutputTooSmall;
            }
            const windowed_values = std.math.mul(
                usize,
                channel_count,
                block_size,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            if (windowed_scratch.len < windowed_values)
                return error.VorbisPcmStreamScratchTooSmall;
            const used_windowed = windowed_scratch[0..windowed_values];
            for (outputs) |output| {
                if (vorbisConstSlicesOverlap(
                    Float,
                    output,
                    used_windowed,
                )) return error.OverlappingVorbisPcmStreamScratch;
            }
            for (&self.overlap.channels) |*channel| {
                if (vorbisConstSlicesOverlap(
                    Float,
                    &channel.previous,
                    used_windowed,
                ) or vorbisConstSlicesOverlap(
                    Float,
                    &channel.pending,
                    used_windowed,
                )) return error.OverlappingVorbisPcmStreamScratch;
            }

            var granule_trial = self.granules;
            const granule_range: VorbisGranuleRange =
                if (nominal_sample_count == 0)
                    .{
                        .source_start = 0,
                        .sample_count = 0,
                        .pcm_start = null,
                        .pcm_end = null,
                    }
                else
                    try granule_trial.trim(
                        nominal_sample_count,
                        granule_position,
                        end,
                    );
            switch (source) {
                .silence => @memset(used_windowed, 0),
                .previous_signal => |config| {
                    for (self.overlap.channels, 0..) |channel, index| {
                        synthesizeVorbisPreviousSignal(
                            Float,
                            channel.previous[0..previous_size],
                            used_windowed[index * block_size ..][0..block_size],
                            config,
                        );
                    }
                },
            }
            var windowed_channels: [channel_count][]const Float = undefined;
            for (&windowed_channels, 0..) |*channel, index| {
                channel.* = used_windowed[index * block_size ..][0..block_size];
            }
            _ = try self.overlap.push(
                &windowed_channels,
                outputs,
            );
            if (granule_range.source_start != 0) {
                for (outputs) |output| {
                    std.mem.copyForwards(
                        Float,
                        output[0..granule_range.sample_count],
                        output[granule_range.source_start..][0..granule_range.sample_count],
                    );
                }
            }

            self.granules = granule_trial;
            self.audio_packet_count += 1;
            self.concealed_packet_count += 1;
            self.ended = end;
            return .{
                .block_size = block_size,
                .sample_count = granule_range.sample_count,
                .pcm_start = granule_range.pcm_start,
                .pcm_end = granule_range.pcm_end,
                .concealed_packet_count = self.concealed_packet_count,
            };
        }

        /// Selects the missing block size from the retained preceding block.
        pub fn concealMissingPacketUsingPreviousBlockSize(
            self: *Self,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            const previous_size =
                try self.overlap.previousBlockSize();
            if (previous_size == 0)
                return error.VorbisPreviousBlockSizeUnavailable;
            if (previous_size != small_block_size and
                previous_size != large_block_size)
                return error.InvalidVorbisChannelOverlapState;
            return self.concealMissingPacket(
                previous_size == large_block_size,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing size from a following packet header when exact.
        pub fn concealMissingPacketUsingFollowingHeader(
            self: *Self,
            following: VorbisAudioPacketHeader,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            const large_block = try inferVorbisMissingPacketLargeBlock(
                identification,
                following,
            );
            return self.concealMissingPacket(
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Uses the exact granule immediately after an ambiguous following packet.
        pub fn concealMissingPacketUsingFollowingGranule(
            self: *Self,
            following: VorbisAudioPacketHeader,
            following_granule_position: u64,
            following_end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            const previous_size =
                try self.overlap.previousBlockSize();
            const large_block =
                try inferVorbisMissingPacketLargeBlockFromFollowingGranule(
                    identification,
                    previous_size,
                    following,
                    self.granules,
                    following_granule_position,
                    following_end,
                );
            return self.concealMissingPacket(
                large_block,
                unknown_granule,
                false,
                identification,
                outputs,
                windowed_scratch,
            );
        }
    };
}

pub fn validateVorbisPcmSignalConcealmentConfig(
    config: VorbisPcmSignalConcealmentConfig,
) !void {
    if (!std.math.isFinite(config.initial_gain) or
        !std.math.isFinite(config.final_gain) or
        config.initial_gain < 0 or config.initial_gain > 1 or
        config.final_gain < 0 or
        config.final_gain > config.initial_gain)
    {
        return error.InvalidVorbisPcmSignalConcealmentConfig;
    }
}

pub fn synthesizeVorbisPreviousSignal(
    comptime Float: type,
    previous: []const Float,
    destination: []Float,
    config: VorbisPcmSignalConcealmentConfig,
) void {
    const source_offset =
        @divExact(@as(i64, @intCast(previous.len)), 2) -
        @divExact(@as(i64, @intCast(destination.len)), 2);
    const denominator: f64 =
        @floatFromInt(destination.len - 1);
    for (destination, 0..) |*sample, index| {
        const source_index =
            source_offset + @as(i64, @intCast(index));
        const retained: f64 = if (source_index >= 0 and
            source_index < previous.len)
            @floatCast(previous[@intCast(source_index)])
        else
            0;
        const progress =
            @as(f64, @floatFromInt(index)) / denominator;
        const gain = config.initial_gain +
            (config.final_gain - config.initial_gain) * progress;
        sample.* = @floatCast(retained * gain);
    }
}

pub fn VorbisChainedPcmStreamDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const StreamDecoder = VorbisPcmStreamDecoder(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );

    return struct {
        const Self = @This();
        const MissingPacketBlockSelection = union(enum) {
            explicit: bool,
            previous,
            previous_signal: struct {
                large_block: bool,
                config: VorbisPcmSignalConcealmentConfig,
            },
            previous_block_signal: VorbisPcmSignalConcealmentConfig,
        };

        stream: StreamDecoder,
        sample_rate: ?u32 = null,
        logical_stream_index: u64 = 0,
        completed_pcm: u64 = 0,
        current_stream_pcm: u64 = 0,
        started: bool = false,

        pub fn init() Self {
            return .{ .stream = .init() };
        }

        pub fn reset(self: *Self) void {
            self.stream.reset();
            self.sample_rate = null;
            self.logical_stream_index = 0;
            self.completed_pcm = 0;
            self.current_stream_pcm = 0;
            self.started = false;
        }

        pub fn valid(self: *const Self) bool {
            if (!self.stream.valid()) return false;
            if (!self.started) {
                return self.sample_rate == null and
                    self.logical_stream_index == 0 and
                    self.completed_pcm == 0 and
                    self.current_stream_pcm == 0 and
                    self.stream.audio_packet_count == 0;
            }
            const sample_rate = self.sample_rate orelse return false;
            if (sample_rate == 0) return false;
            const output_upper_bound =
                vorbisGranuleOutputUpperBound(self.stream.granules) orelse
                return false;
            if (self.current_stream_pcm > output_upper_bound or
                (!self.stream.ended and
                    self.current_stream_pcm != output_upper_bound))
                return false;
            _ = std.math.add(
                u64,
                self.completed_pcm,
                self.current_stream_pcm,
            ) catch return false;
            return true;
        }

        pub fn beginLogicalStream(
            self: *Self,
            identification: VorbisIdentification,
        ) !void {
            if (!self.valid())
                return error.InvalidVorbisChainedPcmStreamState;
            try validateIdentification(identification);
            if (self.started and !self.stream.ended)
                return error.VorbisPreviousLogicalStreamNotEnded;
            if (self.sample_rate) |sample_rate| {
                if (identification.sample_rate != sample_rate)
                    return error.VorbisChainedSampleRateChanged;
            }

            var next_completed = self.completed_pcm;
            var next_index = self.logical_stream_index;
            if (self.started) {
                next_completed = std.math.add(
                    u64,
                    next_completed,
                    self.current_stream_pcm,
                ) catch return error.VorbisChainedPcmPositionOverflow;
                next_index = std.math.add(
                    u64,
                    next_index,
                    1,
                ) catch return error.VorbisLogicalStreamIndexOverflow;
            }

            self.stream.reset();
            self.sample_rate = identification.sample_rate;
            self.logical_stream_index = next_index;
            self.completed_pcm = next_completed;
            self.current_stream_pcm = 0;
            self.started = true;
        }

        pub fn decode(
            self: *Self,
            packet: Packet,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisPcmStreamScratch(Float),
        ) !VorbisChainedPcmStreamResult {
            if (!self.valid())
                return error.InvalidVorbisChainedPcmStreamState;
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            try validateIdentification(identification);
            const sample_rate = self.sample_rate orelse
                return error.VorbisLogicalStreamNotStarted;
            if (identification.sample_rate != sample_rate)
                return error.VorbisChainedSampleRateChanged;

            const global_start = std.math.add(
                u64,
                self.completed_pcm,
                self.current_stream_pcm,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            _ = std.math.add(
                u64,
                global_start,
                large_block_size / 2,
            ) catch return error.VorbisChainedPcmPositionOverflow;

            const decoded = try self.stream.decode(
                packet,
                identification,
                setup,
                outputs,
                scratch,
            );
            const global_end = global_start +
                @as(u64, @intCast(decoded.sample_count));
            self.current_stream_pcm +=
                @as(u64, @intCast(decoded.sample_count));
            return .{
                .stream = decoded,
                .logical_stream_index = self.logical_stream_index,
                .global_pcm_start = global_start,
                .global_pcm_end = global_end,
            };
        }

        pub fn concealMissingPacket(
            self: *Self,
            large_block: bool,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .{ .explicit = large_block },
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Repeats the retained windowed signal with bounded linear decay.
        pub fn concealMissingPacketWithPreviousSignal(
            self: *Self,
            large_block: bool,
            config: VorbisPcmSignalConcealmentConfig,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .{ .previous_signal = .{
                    .large_block = large_block,
                    .config = config,
                } },
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        pub fn concealMissingPacketUsingPreviousBlockSignal(
            self: *Self,
            config: VorbisPcmSignalConcealmentConfig,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .{ .previous_block_signal = config },
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing block size from the retained preceding block.
        pub fn concealMissingPacketUsingPreviousBlockSize(
            self: *Self,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .previous,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing size from a following packet header when exact.
        pub fn concealMissingPacketUsingFollowingHeader(
            self: *Self,
            following: VorbisAudioPacketHeader,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            if (!self.valid())
                return error.InvalidVorbisChainedPcmStreamState;
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            const large_block = try inferVorbisMissingPacketLargeBlock(
                identification,
                following,
            );
            return self.concealMissingPacket(
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Uses the exact granule immediately after an ambiguous following packet.
        pub fn concealMissingPacketUsingFollowingGranule(
            self: *Self,
            following: VorbisAudioPacketHeader,
            following_granule_position: u64,
            following_end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            if (!self.valid())
                return error.InvalidVorbisChainedPcmStreamState;
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            const previous_size =
                try self.stream.overlap.previousBlockSize();
            const large_block =
                try inferVorbisMissingPacketLargeBlockFromFollowingGranule(
                    identification,
                    previous_size,
                    following,
                    self.stream.granules,
                    following_granule_position,
                    following_end,
                );
            return self.concealMissingPacket(
                large_block,
                unknown_granule,
                false,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        fn concealMissingPacketSelected(
            self: *Self,
            selection: MissingPacketBlockSelection,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            if (!self.valid())
                return error.InvalidVorbisChainedPcmStreamState;
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            try validateIdentification(identification);
            const sample_rate = self.sample_rate orelse
                return error.VorbisLogicalStreamNotStarted;
            if (identification.sample_rate != sample_rate)
                return error.VorbisChainedSampleRateChanged;

            const global_start = std.math.add(
                u64,
                self.completed_pcm,
                self.current_stream_pcm,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            _ = std.math.add(
                u64,
                global_start,
                large_block_size / 2,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            const concealed = switch (selection) {
                .explicit => |large_block| try self.stream.concealMissingPacket(
                    large_block,
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
                .previous => try self.stream.concealMissingPacketUsingPreviousBlockSize(
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
                .previous_signal => |policy| try self.stream.concealMissingPacketWithPreviousSignal(
                    policy.large_block,
                    policy.config,
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
                .previous_block_signal => |config| try self.stream.concealMissingPacketUsingPreviousBlockSignal(
                    config,
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
            };
            const global_end = global_start +
                @as(u64, @intCast(concealed.sample_count));
            self.current_stream_pcm +=
                @as(u64, @intCast(concealed.sample_count));
            return .{
                .stream = concealed,
                .logical_stream_index = self.logical_stream_index,
                .global_pcm_start = global_start,
                .global_pcm_end = global_end,
            };
        }

        fn validateIdentification(
            identification: VorbisIdentification,
        ) !void {
            if (@as(usize, identification.channel_count) != channel_count or
                @as(usize, identification.small_block_size) !=
                    small_block_size or
                @as(usize, identification.large_block_size) !=
                    large_block_size)
                return error.VorbisChainedStreamGeometryChanged;
            if (identification.sample_rate == 0)
                return error.InvalidVorbisSampleRate;
        }
    };
}

pub fn applyVorbisFloor(
    comptime Float: type,
    spectrum: []Float,
    floor: []const Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor application requires f32 or f64");
    if (spectrum.len != floor.len)
        return error.InvalidVorbisSpectrumShape;
    for (spectrum, floor) |spectrum_value, floor_value| {
        if (!std.math.isFinite(spectrum_value) or
            !std.math.isFinite(floor_value) or
            !std.math.isFinite(spectrum_value * floor_value))
            return error.InvalidVorbisSpectrumValue;
    }
    for (spectrum, floor) |*spectrum_value, floor_value| {
        spectrum_value.* *= floor_value;
    }
}

pub const VorbisAudioPacketScratchRequirements = struct {
    spectrum_values: usize,
    floor_values: usize,
    coupling_values: usize,
    time_values: usize,
    classification_bytes: usize,
};

pub fn VorbisAudioPacketScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis packet decoding requires f32 or f64");
    return struct {
        spectra: []Float,
        floor_curves: []Float,
        coupling: []Float,
        time: []Float,
        classifications: []u8,
    };
}

pub const VorbisAudioPacketResult = struct {
    header: VorbisAudioPacketHeader,
    decoded_bit_count: usize,
    truncated: bool,
    floor_truncated: bool,
    residue_truncated: bool,
};

pub fn requiredVorbisAudioPacketScratch(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioPacketScratchRequirements {
    const mapping = try validateVorbisAudioDecodeState(
        identification,
        setup,
        header,
    );
    const channel_count: usize = identification.channel_count;
    const coefficient_count: usize = header.block_size / 2;
    const spectrum_values = std.math.mul(
        usize,
        channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioPacketSizeOverflow;
    const time_values = std.math.mul(
        usize,
        channel_count,
        header.block_size,
    ) catch return error.VorbisAudioPacketSizeOverflow;

    var classification_bytes: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var bundle_count: usize = 0;
        for (mapping.channel_mux[0..channel_count]) |mux| {
            if (mux == submap_index) bundle_count += 1;
        }
        if (bundle_count == 0) continue;
        const residue_number = mapping.submaps[submap_index].residue;
        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        classification_bytes = @max(
            classification_bytes,
            try requiredVorbisResidueClassifications(
                residue,
                coefficient_count,
                bundle_count,
            ),
        );
    }
    return .{
        .spectrum_values = spectrum_values,
        .floor_values = spectrum_values,
        .coupling_values = spectrum_values,
        .time_values = time_values,
        .classification_bytes = classification_bytes,
    };
}

pub fn VorbisAudioPacketDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis packet decoding requires f32 or f64");
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis channel count must be from 1 to 255");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    return struct {
        const Self = @This();

        windows: VorbisWindowPlan(
            Float,
            small_block_size,
            large_block_size,
        ),
        small_mdct: VorbisInverseMdct(Float, small_block_size),
        large_mdct: VorbisInverseMdct(Float, large_block_size),

        pub fn init() Self {
            return .{
                .windows = .init(),
                .small_mdct = .init(),
                .large_mdct = .init(),
            };
        }

        /// Failures preserve every output channel.
        pub fn decode(
            self: *Self,
            packet: []const u8,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisAudioPacketScratch(Float),
        ) !VorbisAudioPacketResult {
            if (identification.channel_count != channel_count or
                identification.small_block_size != small_block_size or
                identification.large_block_size != large_block_size)
                return error.VorbisDecoderConfigurationMismatch;
            const header = try parseVorbisAudioPacketHeader(
                packet,
                identification,
                setup,
            );
            const requirements = try requiredVorbisAudioPacketScratch(
                identification,
                setup,
                header,
            );
            try validateVorbisAudioPacketBuffers(
                Float,
                outputs,
                header.block_size,
                scratch,
                requirements,
            );

            const coefficient_count: usize = header.block_size / 2;
            const spectra =
                scratch.spectra[0..requirements.spectrum_values];
            const floor_curves =
                scratch.floor_curves[0..requirements.floor_values];
            const coupling =
                scratch.coupling[0..requirements.coupling_values];
            const time = scratch.time[0..requirements.time_values];
            const classifications =
                scratch.classifications[0..requirements.classification_bytes];
            @memset(spectra, 0);

            const mode = setup.modes[header.mode_number];
            const mapping = setup.mappings[mode.mapping];
            var reader = try VorbisPacketReader.init(
                packet,
                header.payload_bit_offset,
            );
            var no_residue = [_]bool{true} ** channel_count;
            var floor_truncated = false;
            var residue_truncated = false;
            var floor_zero_coefficients: [255]f64 = undefined;
            var floor_one_values: [65]u32 = undefined;
            for (0..channel_count) |channel| {
                const submap = mapping.submaps[
                    mapping.channel_mux[channel]
                ];
                const floor_curve =
                    floor_curves[channel * coefficient_count ..][0..coefficient_count];
                switch (setup.floors[submap.floor]) {
                    .zero => |floor| {
                        const floor_packet = try reader.decodeFloorZero(
                            setup,
                            submap.floor,
                            &floor_zero_coefficients,
                        );
                        floor_truncated =
                            floor_truncated or floor_packet.truncated;
                        no_residue[channel] = !floor_packet.used;
                        try synthesizeVorbisFloorZero(
                            Float,
                            floor,
                            floor_packet,
                            &floor_zero_coefficients,
                            floor_curve,
                        );
                    },
                    .one => |floor| {
                        const floor_packet = try reader.decodeFloorOne(
                            setup,
                            submap.floor,
                            &floor_one_values,
                        );
                        floor_truncated =
                            floor_truncated or floor_packet.truncated;
                        no_residue[channel] = !floor_packet.used;
                        try synthesizeVorbisFloorOne(
                            Float,
                            floor,
                            floor_packet,
                            &floor_one_values,
                            floor_curve,
                        );
                    },
                }
            }

            var channel_spectra: [channel_count][]Float = undefined;
            for (&channel_spectra, 0..) |*channel, index| {
                channel.* =
                    spectra[index * coefficient_count ..][0..coefficient_count];
            }

            if (!floor_truncated) {
                for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
                    if (!no_residue[step.magnitude] or
                        !no_residue[step.angle])
                    {
                        no_residue[step.magnitude] = false;
                        no_residue[step.angle] = false;
                    }
                }

                var bundle_outputs: [channel_count][]Float = undefined;
                var bundle_skips: [channel_count]bool = undefined;
                for (0..mapping.submap_count) |submap_index| {
                    var bundle_count: usize = 0;
                    for (0..channel_count) |channel| {
                        if (mapping.channel_mux[channel] != submap_index)
                            continue;
                        bundle_outputs[bundle_count] =
                            spectra[channel * coefficient_count ..][0..coefficient_count];
                        bundle_skips[bundle_count] = no_residue[channel];
                        bundle_count += 1;
                    }
                    if (bundle_count == 0) continue;
                    const residue_packet = try reader.decodeResidue(
                        Float,
                        setup,
                        mapping.submaps[submap_index].residue,
                        bundle_skips[0..bundle_count],
                        bundle_outputs[0..bundle_count],
                        classifications,
                    );
                    residue_truncated =
                        residue_truncated or residue_packet.truncated;
                }

                try inverseCoupleVorbisChannels(
                    Float,
                    mapping,
                    &channel_spectra,
                    coupling,
                );
                for (channel_spectra, 0..) |spectrum, channel| {
                    try applyVorbisFloor(
                        Float,
                        spectrum,
                        floor_curves[channel * coefficient_count ..][0..coefficient_count],
                    );
                }
            }

            const window = try self.windows.get(header);
            for (channel_spectra, 0..) |spectrum, channel| {
                const time_block =
                    time[channel * header.block_size ..][0..header.block_size];
                if (header.large_block) {
                    try self.large_mdct.processWindowed(
                        spectrum,
                        window,
                        time_block,
                    );
                } else {
                    try self.small_mdct.processWindowed(
                        spectrum,
                        window,
                        time_block,
                    );
                }
            }
            for (outputs, 0..) |output, channel| {
                @memcpy(
                    output,
                    time[channel * header.block_size ..][0..header.block_size],
                );
            }
            return .{
                .header = header,
                .decoded_bit_count = reader.bit_offset,
                .truncated = floor_truncated or residue_truncated,
                .floor_truncated = floor_truncated,
                .residue_truncated = residue_truncated,
            };
        }
    };
}

pub fn validateVorbisAudioDecodeState(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisMapping {
    if (identification.channel_count == 0 or
        setup.modes.len != setup.summary.mode_count or
        setup.floors.len != setup.summary.floor_count or
        setup.residues.len != setup.summary.residue_count or
        setup.mappings.len != setup.summary.mapping_count or
        header.mode_number >= setup.modes.len)
        return error.InvalidVorbisSetupState;
    const mode = setup.modes[header.mode_number];
    if (mode.large_block != header.large_block or
        mode.mapping >= setup.mappings.len)
        return error.InvalidVorbisSetupState;
    const mapping = setup.mappings[mode.mapping];
    if (mapping.submap_count == 0 or
        mapping.submap_count > mapping.submaps.len or
        mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    for (mapping.channel_mux[0..identification.channel_count]) |mux| {
        if (mux >= mapping.submap_count)
            return error.InvalidVorbisMappingState;
    }
    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= identification.channel_count or
            step.angle >= identification.channel_count or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
    }
    for (mapping.submaps[0..mapping.submap_count]) |submap| {
        if (submap.floor >= setup.floors.len or
            submap.residue >= setup.residues.len)
            return error.InvalidVorbisMappingState;
    }
    return mapping;
}

pub fn validateVorbisAudioPacketBuffers(
    comptime Float: type,
    outputs: []const []Float,
    block_size: usize,
    scratch: VorbisAudioPacketScratch(Float),
    requirements: VorbisAudioPacketScratchRequirements,
) !void {
    if (outputs.len == 0 or outputs.len > 255)
        return error.InvalidVorbisAudioOutput;
    if (scratch.spectra.len < requirements.spectrum_values or
        scratch.floor_curves.len < requirements.floor_values or
        scratch.coupling.len < requirements.coupling_values or
        scratch.time.len < requirements.time_values or
        scratch.classifications.len < requirements.classification_bytes)
        return error.VorbisAudioPacketScratchTooSmall;

    const spectra = scratch.spectra[0..requirements.spectrum_values];
    const floor_curves =
        scratch.floor_curves[0..requirements.floor_values];
    const coupling = scratch.coupling[0..requirements.coupling_values];
    const time = scratch.time[0..requirements.time_values];
    const classifications =
        scratch.classifications[0..requirements.classification_bytes];
    const float_scratch = [_][]Float{
        spectra,
        floor_curves,
        coupling,
        time,
    };
    for (float_scratch, 0..) |values, index| {
        for (float_scratch[0..index]) |earlier| {
            if (vorbisSlicesOverlap(Float, values, earlier))
                return error.OverlappingVorbisAudioPacketScratch;
        }
        if (vorbisSliceOverlapsBytes(Float, values, classifications))
            return error.OverlappingVorbisAudioPacketScratch;
    }
    for (outputs, 0..) |output, channel| {
        if (output.len != block_size)
            return error.InvalidVorbisAudioOutput;
        for (outputs[0..channel]) |earlier| {
            if (vorbisSlicesOverlap(Float, output, earlier))
                return error.OverlappingVorbisAudioOutput;
        }
        for (float_scratch) |values| {
            if (vorbisSlicesOverlap(Float, output, values))
                return error.OverlappingVorbisAudioPacketScratch;
        }
        if (vorbisSliceOverlapsBytes(Float, output, classifications))
            return error.OverlappingVorbisAudioPacketScratch;
    }
}

pub fn vorbisResidueShape(
    residue: VorbisResidue,
    vector_length: usize,
    vector_count: usize,
) !VorbisResidueShape {
    if (vector_count == 0 or vector_count > 255 or
        residue.partition_size == 0)
        return error.InvalidVorbisResidueBundle;
    const available = if (residue.kind == .two)
        std.math.mul(usize, vector_length, vector_count) catch
            return error.InvalidVorbisResidueBundle
    else
        vector_length;
    const begin = @min(@as(usize, residue.begin), available);
    const end = @min(@as(usize, residue.end), available);
    const sample_count = end -| begin;
    const partition_count =
        sample_count / @as(usize, residue.partition_size);
    const classification_vectors =
        if (residue.kind == .two) 1 else vector_count;
    const required_classifications = std.math.mul(
        usize,
        partition_count,
        classification_vectors,
    ) catch return error.InvalidVorbisResidueBundle;
    return .{
        .begin = begin,
        .partition_count = partition_count,
        .required_classifications = required_classifications,
    };
}

pub const VorbisResidueRateMetrics = struct {
    squared_error: f128 = 0,
    weighted_squared_error: f128 = 0,
    audible_excess_power: f128 = 0,
    encoded_bits: u64 = 0,

    fn add(
        self: *VorbisResidueRateMetrics,
        other: VorbisResidueRateMetrics,
    ) !void {
        self.squared_error += other.squared_error;
        self.weighted_squared_error += other.weighted_squared_error;
        self.audible_excess_power += other.audible_excess_power;
        self.encoded_bits = std.math.add(
            u64,
            self.encoded_bits,
            other.encoded_bits,
        ) catch return error.VorbisAudioPacketSizeOverflow;
    }
};

pub const VorbisAdaptiveResidueCandidate = struct {
    metrics: VorbisResidueRateMetrics,
    encoded_bits: u32,
    lambda: f64,
};

pub fn planVorbisAdaptiveResidueCandidate(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
    lambda: f64,
) !VorbisAdaptiveResidueCandidate {
    try selectVorbisResidueClassificationsRateDistortion(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        classifications,
        lambda,
    );
    const metrics = try measureVorbisResidueRateDistortion(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        classifications,
    );
    return .{
        .metrics = metrics,
        .encoded_bits = std.math.cast(
            u32,
            metrics.encoded_bits,
        ) orelse return error.VorbisAudioPacketSizeOverflow,
        .lambda = lambda,
    };
}

pub fn selectVorbisResidueClassificationsRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
    lambda: f64,
) !void {
    @memset(classifications, 0);
    if (shape.partition_count == 0) return;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group_count = @min(
                @as(usize, classbook.dimensions),
                shape.partition_count - partition,
            );
            var best_entry: ?u32 = null;
            var best_score = std.math.inf(f128);
            var best_bits: u64 = std.math.maxInt(u64);
            for (classbook_entries, 0..) |entry, entry_number| {
                if (entry.length == 0) continue;
                var encoded: u32 = @intCast(entry_number);
                var omitted =
                    @as(usize, classbook.dimensions) - group_count;
                while (omitted != 0) : (omitted -= 1)
                    encoded /= residue.classification_count;
                var metrics = VorbisResidueRateMetrics{
                    .encoded_bits = entry.length,
                };
                var index = group_count;
                while (index != 0) {
                    index -= 1;
                    const classification: u8 = @intCast(
                        encoded % residue.classification_count,
                    );
                    encoded /= residue.classification_count;
                    try metrics.add(
                        try measureVorbisResiduePartitionRateDistortion(
                            Float,
                            setup,
                            residue,
                            shape,
                            inputs,
                            noise_thresholds,
                            vector,
                            partition + index,
                            classification,
                            partition_scratch,
                            vector_scratch,
                        ),
                    );
                }
                const score =
                    metrics.weighted_squared_error +
                    @as(f128, lambda) *
                        @as(f128, @floatFromInt(metrics.encoded_bits));
                const earlier_entry = if (best_entry) |selected_entry|
                    entry_number < selected_entry
                else
                    true;
                if (score < best_score or
                    (score == best_score and
                        (metrics.encoded_bits < best_bits or
                            (metrics.encoded_bits == best_bits and
                                earlier_entry))))
                {
                    best_score = score;
                    best_bits = metrics.encoded_bits;
                    best_entry = @intCast(entry_number);
                }
            }
            const selected = best_entry orelse
                return error.InvalidVorbisSetupState;
            var encoded = selected;
            var omitted =
                @as(usize, classbook.dimensions) - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                classifications[
                    vector * shape.partition_count + partition + index
                ] = @intCast(encoded % residue.classification_count);
                encoded /= residue.classification_count;
            }
            partition += group_count;
        }
    }
}

pub fn measureVorbisResidueRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
) !VorbisResidueRateMetrics {
    var total = VorbisResidueRateMetrics{};
    const classbook = setup.codebooks[residue.classbook];
    const classwords: usize = classbook.dimensions;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group = classifications[vector * shape.partition_count + partition ..][0..@min(
                classwords,
                shape.partition_count - partition,
            )];
            const classword = findVorbisResidueClassword(
                setup,
                residue,
                group,
            ) orelse
                return error.UnencodableVorbisResidueClassifications;
            const codeword = try writableVorbisCodeword(
                setup,
                residue.classbook,
                classword,
            );
            total.encoded_bits = std.math.add(
                u64,
                total.encoded_bits,
                codeword.entry.length,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            partition += group.len;
        }
        for (0..shape.partition_count) |partition_index| {
            try total.add(
                try measureVorbisResiduePartitionRateDistortion(
                    Float,
                    setup,
                    residue,
                    shape,
                    inputs,
                    noise_thresholds,
                    vector,
                    partition_index,
                    classifications[
                        vector * shape.partition_count + partition_index
                    ],
                    partition_scratch,
                    vector_scratch,
                ),
            );
        }
    }
    return total;
}

pub fn measureVorbisResiduePartitionRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    vector: usize,
    partition: usize,
    classification: u8,
    partition_scratch: []Float,
    vector_scratch: []Float,
) !VorbisResidueRateMetrics {
    const partition_size: usize = residue.partition_size;
    const partition_values = partition_scratch[0..partition_size];
    const partition_offset =
        shape.begin + partition * partition_size;
    for (partition_values, 0..) |*destination, index| {
        destination.* = vorbisResidueInputValue(
            Float,
            residue.kind,
            inputs,
            vector,
            partition_offset + index,
        );
    }

    var metrics = VorbisResidueRateMetrics{};
    for (0..8) |pass| {
        const book_number = residue.books[classification][pass];
        if (book_number < 0) continue;
        const codebook_number: u8 = @intCast(book_number);
        const codebook = setup.codebooks[codebook_number];
        const dimensions: usize = codebook.dimensions;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            const target = vector_scratch[0..dimensions];
            for (target, 0..) |*value, component| {
                value.* = partition_values[
                    vorbisResiduePartitionIndex(
                        residue.kind,
                        dimensions,
                        vector_count,
                        entry_index,
                        component,
                    )
                ];
            }
            const quantized = try quantizeVorbisVector(
                Float,
                setup,
                codebook_number,
                target,
            );
            const codeword = try writableVorbisCodeword(
                setup,
                codebook_number,
                quantized.entry,
            );
            metrics.encoded_bits = std.math.add(
                u64,
                metrics.encoded_bits,
                codeword.entry.length,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            var decoded = VorbisVectorCursor{
                .codebook = codebook,
                .multiplicands = multiplicands,
                .entry = quantized.entry,
                .explicit_offset = @as(u64, quantized.entry) * codebook.dimensions,
            };
            for (0..dimensions) |component| {
                const index = vorbisResiduePartitionIndex(
                    residue.kind,
                    dimensions,
                    vector_count,
                    entry_index,
                    component,
                );
                partition_values[index] -=
                    @as(Float, @floatCast(decoded.next()));
            }
        }
    }

    for (partition_values, 0..) |residual, index| {
        const wide_residual: f128 = @floatCast(residual);
        const threshold: f128 = @floatCast(vorbisResidueInputValue(
            Float,
            residue.kind,
            noise_thresholds,
            vector,
            partition_offset + index,
        ));
        const squared = wide_residual * wide_residual;
        const ratio = wide_residual / threshold;
        const excess = @max(@abs(wide_residual) - threshold, 0);
        metrics.squared_error += squared;
        metrics.weighted_squared_error += ratio * ratio;
        metrics.audible_excess_power += excess * excess;
    }
    return metrics;
}

pub fn selectVorbisResidueClassifications(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
) !void {
    @memset(classifications, 0);
    if (shape.partition_count == 0) return;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group_count = @min(
                @as(usize, classbook.dimensions),
                shape.partition_count - partition,
            );
            var best_entry: ?u32 = null;
            var best_error = std.math.inf(f128);
            for (classbook_entries, 0..) |entry, entry_number| {
                if (entry.length == 0) continue;
                var encoded: u32 = @intCast(entry_number);
                var omitted =
                    @as(usize, classbook.dimensions) - group_count;
                while (omitted != 0) : (omitted -= 1)
                    encoded /= residue.classification_count;
                var candidate_error: f128 = 0;
                var index = group_count;
                while (index != 0) {
                    index -= 1;
                    const classification: u8 = @intCast(
                        encoded % residue.classification_count,
                    );
                    encoded /= residue.classification_count;
                    candidate_error +=
                        try quantizeVorbisResiduePartition(
                            Float,
                            setup,
                            residue,
                            shape,
                            inputs,
                            vector,
                            partition + index,
                            classification,
                            partition_scratch,
                            vector_scratch,
                            null,
                            null,
                            null,
                        );
                }
                if (candidate_error < best_error) {
                    best_error = candidate_error;
                    best_entry = @intCast(entry_number);
                }
            }
            const selected = best_entry orelse
                return error.InvalidVorbisSetupState;
            var encoded = selected;
            var omitted =
                @as(usize, classbook.dimensions) - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                classifications[
                    vector * shape.partition_count + partition + index
                ] = @intCast(encoded % residue.classification_count);
                encoded /= residue.classification_count;
            }
            partition += group_count;
        }
    }
}

pub fn countVorbisResidueQuantizedEntries(
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    classifications: []const u8,
) !usize {
    var count: usize = 0;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else do_not_encode.len;
    for (0..8) |pass| {
        for (0..shape.partition_count) |partition| {
            for (0..effective_vectors) |vector| {
                if (residue.kind != .two and do_not_encode[vector])
                    continue;
                const classification = classifications[
                    vector * shape.partition_count + partition
                ];
                const book_number = residue.books[classification][pass];
                if (book_number < 0) continue;
                const dimensions: usize =
                    setup.codebooks[@intCast(book_number)].dimensions;
                count = std.math.add(
                    usize,
                    count,
                    @as(usize, residue.partition_size) / dimensions,
                ) catch return error.VorbisResidueEntryCountOverflow;
            }
        }
    }
    return count;
}

pub fn measureVorbisResidueQuantization(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
) !f128 {
    var total_error: f128 = 0;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        for (0..shape.partition_count) |partition| {
            total_error += try quantizeVorbisResiduePartition(
                Float,
                setup,
                residue,
                shape,
                inputs,
                vector,
                partition,
                classifications[
                    vector * shape.partition_count + partition
                ],
                partition_scratch,
                vector_scratch,
                null,
                null,
                null,
            );
        }
    }
    return total_error;
}

pub fn assembleVorbisResidueEntries(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
    entries: []u32,
    entry_offset: *usize,
) !void {
    const classwords: usize =
        setup.codebooks[residue.classbook].dimensions;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..8) |pass| {
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            var classword_index: usize = 0;
            while (classword_index < classwords and
                partition < shape.partition_count) : (classword_index += 1)
            {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        do_not_encode[vector])
                        continue;
                    const classification = classifications[
                        vector * shape.partition_count + partition
                    ];
                    if (residue.books[classification][pass] < 0)
                        continue;
                    _ = try quantizeVorbisResiduePartition(
                        Float,
                        setup,
                        residue,
                        shape,
                        inputs,
                        vector,
                        partition,
                        classification,
                        partition_scratch,
                        vector_scratch,
                        pass,
                        entries,
                        entry_offset,
                    );
                }
                partition += 1;
            }
        }
    }
}

pub fn quantizeVorbisResiduePartition(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    inputs: []const []const Float,
    vector: usize,
    partition: usize,
    classification: u8,
    partition_scratch: []Float,
    vector_scratch: []Float,
    record_pass: ?usize,
    entries: ?[]u32,
    entry_offset: ?*usize,
) !f128 {
    const partition_size: usize = residue.partition_size;
    const partition_values = partition_scratch[0..partition_size];
    const partition_offset =
        shape.begin + partition * partition_size;
    for (partition_values, 0..) |*destination, index| {
        destination.* = vorbisResidueInputValue(
            Float,
            residue.kind,
            inputs,
            vector,
            partition_offset + index,
        );
    }

    for (0..8) |pass| {
        const book_number = residue.books[classification][pass];
        if (book_number < 0) continue;
        const codebook_number: u8 = @intCast(book_number);
        const codebook = setup.codebooks[codebook_number];
        const dimensions: usize = codebook.dimensions;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            const target = vector_scratch[0..dimensions];
            for (target, 0..) |*value, component| {
                value.* = partition_values[
                    vorbisResiduePartitionIndex(
                        residue.kind,
                        dimensions,
                        vector_count,
                        entry_index,
                        component,
                    )
                ];
            }
            const quantized = try quantizeVorbisVector(
                Float,
                setup,
                codebook_number,
                target,
            );
            if (record_pass) |selected_pass| {
                if (selected_pass == pass) {
                    const offset = entry_offset orelse
                        return error.InvalidVorbisResidueEncoding;
                    const output_entries = entries orelse
                        return error.InvalidVorbisResidueEncoding;
                    if (offset.* >= output_entries.len)
                        return error.VorbisResidueEntryOutputTooSmall;
                    output_entries[offset.*] = quantized.entry;
                    offset.* += 1;
                }
            }

            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            var decoded = VorbisVectorCursor{
                .codebook = codebook,
                .multiplicands = multiplicands,
                .entry = quantized.entry,
                .explicit_offset = @as(u64, quantized.entry) * codebook.dimensions,
            };
            for (0..dimensions) |component| {
                const index = vorbisResiduePartitionIndex(
                    residue.kind,
                    dimensions,
                    vector_count,
                    entry_index,
                    component,
                );
                partition_values[index] -=
                    @as(Float, @floatCast(decoded.next()));
            }
        }
    }

    var squared_error: f128 = 0;
    for (partition_values) |value| {
        const wide: f128 = @floatCast(value);
        squared_error += wide * wide;
    }
    return squared_error;
}

pub fn vorbisResiduePartitionIndex(
    kind: VorbisResidueKind,
    dimensions: usize,
    vector_count: usize,
    entry_index: usize,
    component: usize,
) usize {
    return switch (kind) {
        .zero => entry_index + component * vector_count,
        .one, .two => entry_index * dimensions + component,
    };
}

pub fn vorbisResidueInputValue(
    comptime Float: type,
    kind: VorbisResidueKind,
    inputs: []const []const Float,
    vector: usize,
    flat_index: usize,
) Float {
    if (kind != .two) return inputs[vector][flat_index];
    return inputs[flat_index % inputs.len][flat_index / inputs.len];
}

pub fn rejectVorbisResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    scratch: VorbisResidueQuantizationScratch(Float),
    classifications: []u8,
    entries: []u32,
) !void {
    if (vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.vector,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.vector,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        scratch.classifications,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        u32,
        entries,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        u8,
        scratch.classifications,
    )) return error.OverlappingVorbisResidueQuantization;
    for (inputs) |input| {
        if (vorbisTypedSlicesOverlap(
            u8,
            classifications,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            u32,
            entries,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            Float,
            scratch.partition,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            Float,
            scratch.vector,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            u8,
            scratch.classifications,
            Float,
            input,
        )) return error.OverlappingVorbisResidueQuantization;
    }
    const classification_bytes = std.mem.sliceAsBytes(classifications);
    const entry_bytes = std.mem.sliceAsBytes(entries);
    const partition_bytes = std.mem.sliceAsBytes(scratch.partition);
    const vector_bytes = std.mem.sliceAsBytes(scratch.vector);
    const scratch_classification_bytes =
        std.mem.sliceAsBytes(scratch.classifications);
    if (vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        scratch_classification_bytes,
    )) return error.OverlappingVorbisResidueQuantization;
}

pub fn rejectVorbisAdaptiveResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    scratch: VorbisAdaptiveResidueScratch(Float),
    classifications: []u8,
    entries: []u32,
) !void {
    try rejectVorbisResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        .{
            .partition = scratch.partition,
            .vector = scratch.vector,
            .classifications = scratch.classifications,
        },
        classifications,
        entries,
    );
    const best = scratch.best_classifications;
    if (vorbisTypedSlicesOverlap(
        u8,
        best,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u8,
        classifications,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u32,
        entries,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        bool,
        do_not_encode,
    )) return error.OverlappingVorbisResidueQuantization;
    for (inputs) |input| {
        if (vorbisTypedSlicesOverlap(u8, best, Float, input))
            return error.OverlappingVorbisResidueQuantization;
    }
    for (noise_thresholds) |thresholds| {
        if (vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            Float,
            scratch.partition,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            Float,
            scratch.vector,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            scratch.classifications,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            best,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            classifications,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u32,
            entries,
        )) return error.OverlappingVorbisResidueQuantization;
    }
    const best_bytes = std.mem.sliceAsBytes(best);
    if (vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        best_bytes,
    )) return error.OverlappingVorbisResidueQuantization;
}

pub fn validateVorbisResidueState(
    residue: VorbisResidue,
    setup: VorbisSetup,
) !void {
    if (residue.partition_size == 0 or
        residue.classification_count == 0 or
        residue.classification_count > residue.cascades.len or
        residue.classbook >= setup.codebooks.len)
        return error.InvalidVorbisSetupState;
    const classbook = setup.codebooks[residue.classbook];
    try validateVorbisScalarCodebookState(classbook, setup);
    if (classbook.dimensions == 0 or !powerAtMost(
        residue.classification_count,
        classbook.dimensions,
        classbook.entries,
    )) return error.InvalidVorbisSetupState;

    for (
        residue.cascades[0..residue.classification_count],
        0..,
    ) |cascade, classification| {
        for (0..8) |pass| {
            const selected =
                cascade & (@as(u8, 1) << @intCast(pass)) != 0;
            const book_number = residue.books[classification][pass];
            if (!selected) {
                if (book_number != -1)
                    return error.InvalidVorbisSetupState;
                continue;
            }
            if (book_number < 0 or book_number >= setup.codebooks.len)
                return error.InvalidVorbisSetupState;
            const codebook = setup.codebooks[@intCast(book_number)];
            try validateVorbisVectorCodebookState(codebook, setup);
            if (residue.partition_size % codebook.dimensions != 0)
                return error.InvalidVorbisSetupState;
        }
    }
}

pub fn validateVorbisScalarCodebookState(
    codebook: VorbisCodebook,
    setup: VorbisSetup,
) !void {
    if (codebook.entries == 0 or codebook.active_entry_count == 0 or
        codebook.active_entry_count > codebook.entries)
        return error.InvalidVorbisSetupState;
    const entry_start =
        std.math.cast(usize, codebook.entry_offset) orelse
        return error.InvalidVorbisSetupState;
    if (entry_start > setup.codebook_entries.len or
        codebook.entries > setup.codebook_entries.len - entry_start)
        return error.InvalidVorbisSetupState;
    if (codebook.active_entry_count > 1) {
        const node_start =
            std.math.cast(usize, codebook.tree_node_offset) orelse
            return error.InvalidVorbisSetupState;
        if (node_start > setup.huffman_nodes.len or
            codebook.tree_node_count >
                setup.huffman_nodes.len - node_start or
            codebook.tree_node_count == 0)
            return error.InvalidVorbisSetupState;
    }
}

pub fn validateVorbisVectorCodebookState(
    codebook: VorbisCodebook,
    setup: VorbisSetup,
) !void {
    try validateVorbisScalarCodebookState(codebook, setup);
    if (codebook.lookup_type == 0 or codebook.lookup_type > 2 or
        codebook.dimensions == 0)
        return error.InvalidVorbisSetupState;
    const multiplicand_start =
        std.math.cast(usize, codebook.multiplicand_offset) orelse
        return error.InvalidVorbisSetupState;
    if (multiplicand_start > setup.codebook_multiplicands.len or
        codebook.multiplicand_count >
            setup.codebook_multiplicands.len - multiplicand_start)
        return error.InvalidVorbisSetupState;
    const expected: u64 = if (codebook.lookup_type == 1)
        vorbisLookupOneValues(codebook.entries, codebook.dimensions)
    else
        @as(u64, codebook.entries) * codebook.dimensions;
    if (codebook.multiplicand_count == 0 or
        codebook.multiplicand_count != expected)
        return error.InvalidVorbisSetupState;
}

pub fn vorbisSlicesOverlap(
    comptime Element: type,
    first: []Element,
    second: []Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(Element)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Element)) catch return true,
    );
}

pub fn vorbisConstSlicesOverlap(
    comptime Element: type,
    first: []const Element,
    second: []const Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(Element)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Element)) catch return true,
    );
}

pub fn vorbisSliceOverlapsBytes(
    comptime Element: type,
    values: []const Element,
    bytes: []const u8,
) bool {
    if (values.len == 0 or bytes.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(values.ptr),
        std.math.mul(usize, values.len, @sizeOf(Element)) catch return true,
        @intFromPtr(bytes.ptr),
        bytes.len,
    );
}

pub fn vorbisTypedSlicesOverlap(
    comptime First: type,
    first: []const First,
    comptime Second: type,
    second: []const Second,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(First)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Second)) catch return true,
    );
}

pub fn byteRangesOverlap(
    first_start: usize,
    first_length: usize,
    second_start: usize,
    second_length: usize,
) bool {
    const first_end =
        std.math.add(usize, first_start, first_length) catch return true;
    const second_end =
        std.math.add(usize, second_start, second_length) catch return true;
    return first_start < second_end and second_start < first_end;
}

pub fn validateVorbisFloorZeroState(
    floor: VorbisFloorZero,
    codebooks: []const VorbisCodebook,
) !void {
    try validateVorbisFloorZeroSynthesisState(floor);
    for (floor.books[0..floor.book_count]) |book_number| {
        if (book_number >= codebooks.len)
            return error.InvalidVorbisSetupState;
        const codebook = codebooks[book_number];
        if (codebook.dimensions == 0 or codebook.lookup_type == 0 or
            codebook.lookup_type > 2)
            return error.InvalidVorbisSetupState;
    }
}

pub fn validateVorbisFloorZeroSynthesisState(
    floor: VorbisFloorZero,
) !void {
    if (floor.order == 0 or floor.rate == 0 or
        floor.bark_map_size == 0 or floor.book_count == 0 or
        floor.book_count > floor.books.len)
        return error.InvalidVorbisSetupState;
}

pub fn validateVorbisFloorOneState(
    floor: VorbisFloorOne,
    codebooks: ?[]const VorbisCodebook,
) !void {
    if (floor.partition_count > floor.partition_classes.len or
        floor.class_count > floor.classes.len or
        floor.multiplier == 0 or floor.multiplier > 4 or
        floor.point_count < 2 or floor.point_count > floor.x_list.len or
        floor.x_list[0] != 0 or
        floor.x_list[1] != @as(u16, 1) << @intCast(floor.range_bits))
        return error.InvalidVorbisSetupState;

    var expected_points: usize = 2;
    for (floor.partition_classes[0..floor.partition_count]) |class_index| {
        if (class_index >= floor.class_count)
            return error.InvalidVorbisSetupState;
        expected_points += floor.classes[class_index].dimensions;
        if (expected_points > floor.x_list.len)
            return error.InvalidVorbisSetupState;
    }
    if (expected_points != floor.point_count)
        return error.InvalidVorbisSetupState;
    for (floor.x_list[0..floor.point_count], 0..) |point, index| {
        if (index >= 2 and
            (point == 0 or point >= floor.x_list[1]))
            return error.InvalidVorbisSetupState;
        for (floor.x_list[0..index]) |earlier| {
            if (point == earlier) return error.InvalidVorbisSetupState;
        }
    }

    for (floor.classes[0..floor.class_count]) |class| {
        if (class.dimensions == 0 or class.subclass_bits > 3)
            return error.InvalidVorbisSetupState;
        if (class.subclass_bits == 0) {
            if (class.masterbook != -1)
                return error.InvalidVorbisSetupState;
        } else if (class.masterbook < 0) {
            return error.InvalidVorbisSetupState;
        }
        if (codebooks) |books| {
            if (class.masterbook >= books.len and class.masterbook >= 0)
                return error.InvalidVorbisSetupState;
        }
        const subclass_count =
            @as(usize, 1) << @intCast(class.subclass_bits);
        for (class.subclass_books[0..subclass_count]) |book| {
            if (book < -1)
                return error.InvalidVorbisSetupState;
            if (codebooks) |books| {
                if (book >= books.len)
                    return error.InvalidVorbisSetupState;
            }
        }
    }
}

pub fn synthesizeVorbisFloorZero(
    comptime Float: type,
    floor: VorbisFloorZero,
    packet: VorbisFloorZeroPacket,
    coefficients: []const f64,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor synthesis requires f32 or f64 output");
    try validateVorbisFloorZeroSynthesisState(floor);
    if (!packet.used) {
        @memset(output, 0);
        return;
    }
    if (floor.amplitude_bits == 0 or
        packet.coefficient_count != floor.order or
        coefficients.len < floor.order)
        return error.InvalidVorbisFloorPacketState;
    const maximum_amplitude =
        (@as(u64, 1) << floor.amplitude_bits) - 1;
    if (packet.amplitude == 0 or packet.amplitude > maximum_amplitude)
        return error.InvalidVorbisFloorPacketState;

    var cosines: [255]f64 = undefined;
    for (coefficients[0..floor.order], 0..) |coefficient, index| {
        if (!std.math.isFinite(coefficient))
            return error.InvalidVorbisFloorPacketState;
        cosines[index] = 2.0 * @cos(coefficient);
    }
    const amplitude =
        @as(f64, @floatFromInt(packet.amplitude)) /
        @as(f64, @floatFromInt(maximum_amplitude)) *
        @as(f64, floor.amplitude_offset);
    const bark_limit = vorbisBark(@as(f64, floor.rate) / 2.0);
    const map_scale = @as(f64, floor.bark_map_size) / bark_limit;
    for (output, 0..) |*value, index| {
        const frequency =
            (@as(f64, floor.rate) / 2.0) /
            @as(f64, @floatFromInt(output.len)) *
            @as(f64, @floatFromInt(index));
        const mapped: u16 = @intFromFloat(@min(
            @floor(vorbisBark(frequency) * map_scale),
            @as(f64, floor.bark_map_size - 1),
        ));
        const angular =
            std.math.pi * @as(f64, @floatFromInt(mapped)) /
            @as(f64, floor.bark_map_size);
        const frequency_cosine = 2.0 * @cos(angular);
        var log_p: f64 = @log(0.5);
        var log_q: f64 = @log(0.5);
        var coefficient_index: usize = 1;
        while (coefficient_index < floor.order) : (coefficient_index += 2) {
            log_q += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index - 1],
            );
            log_p += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index],
            );
        }
        if (coefficient_index == floor.order) {
            log_q += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index - 1],
            );
            log_p = 2.0 * log_p +
                vorbisLogAbsolute(
                    4.0 - frequency_cosine * frequency_cosine,
                );
            log_q *= 2.0;
        } else {
            log_p = 2.0 * log_p +
                vorbisLogAbsolute(2.0 - frequency_cosine);
            log_q = 2.0 * log_q +
                vorbisLogAbsolute(2.0 + frequency_cosine);
        }
        const inverse_denominator =
            @exp(-0.5 * vorbisLogAddExp(log_p, log_q));
        const linear = @exp(
            (amplitude * inverse_denominator -
                @as(f64, floor.amplitude_offset)) *
                0.11512925,
        );
        value.* = @floatCast(linear);
    }
}

pub fn vorbisLogAbsolute(value: f64) f64 {
    const magnitude = @abs(value);
    return if (magnitude == 0)
        -std.math.inf(f64)
    else
        @log(magnitude);
}

pub fn vorbisLogAddExp(left: f64, right: f64) f64 {
    const maximum = @max(left, right);
    if (maximum == -std.math.inf(f64)) return maximum;
    return maximum + @log(
        @exp(left - maximum) + @exp(right - maximum),
    );
}

pub fn vorbisBark(frequency: f64) f64 {
    return 13.1 * std.math.atan(0.00074 * frequency) +
        2.24 * std.math.atan(0.0000000185 * frequency * frequency) +
        0.0001 * frequency;
}

pub fn synthesizeVorbisFloorOne(
    comptime Float: type,
    floor: VorbisFloorOne,
    packet: VorbisFloorOnePacket,
    y_values: []const u32,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor synthesis requires f32 or f64 output");
    try validateVorbisFloorOneState(floor, null);
    if (!packet.used) {
        @memset(output, 0);
        return;
    }
    if (packet.value_count != floor.point_count or
        y_values.len < floor.point_count)
        return error.InvalidVorbisFloorPacketState;

    const ranges = [_]i32{ 256, 128, 86, 64 };
    const range = ranges[floor.multiplier - 1];
    var final_y = [_]i32{0} ** 65;
    var render = [_]bool{false} ** 65;
    final_y[0] = @intCast(@min(y_values[0], @as(u32, @intCast(range - 1))));
    final_y[1] = @intCast(@min(y_values[1], @as(u32, @intCast(range - 1))));
    render[0] = true;
    render[1] = true;

    for (2..floor.point_count) |index| {
        const low = vorbisFloorLowNeighbor(floor.x_list[0..floor.point_count], index);
        const high = vorbisFloorHighNeighbor(floor.x_list[0..floor.point_count], index);
        const predicted = vorbisFloorRenderPoint(
            floor.x_list[low],
            final_y[low],
            floor.x_list[high],
            final_y[high],
            floor.x_list[index],
        );
        if (y_values[index] != 0) {
            render[low] = true;
            render[high] = true;
            render[index] = true;
        }
        final_y[index] = decodeVorbisFloorOneValue(
            predicted,
            range,
            y_values[index],
        );
    }

    var order: [65]u7 = undefined;
    for (order[0..floor.point_count], 0..) |*destination, index| {
        destination.* = @intCast(index);
    }
    std.mem.sort(
        u7,
        order[0..floor.point_count],
        &floor.x_list,
        struct {
            fn lessThan(
                points: *const [65]u16,
                left: u7,
                right: u7,
            ) bool {
                return points[left] < points[right];
            }
        }.lessThan,
    );

    var low_x: u16 = 0;
    var low_y: i32 = final_y[0] * floor.multiplier;
    for (order[1..floor.point_count]) |index| {
        if (!render[index]) continue;
        const high_x = floor.x_list[index];
        const high_y = final_y[index] * floor.multiplier;
        renderVorbisFloorLine(
            Float,
            low_x,
            low_y,
            high_x,
            high_y,
            output,
        );
        low_x = high_x;
        low_y = high_y;
        if (low_x >= output.len) return;
    }
    if (low_x < output.len) {
        @memset(
            output[low_x..],
            vorbisFloorOneInverseDb(Float, @intCast(low_y)),
        );
    }
}

pub fn requiredVorbisAudioFloorOneStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioFloorOneStorageRequirements {
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    var y_values: usize = 0;
    for (mapping.channel_mux[0..identification.channel_count]) |mux| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        y_values = std.math.add(
            usize,
            y_values,
            floor.point_count,
        ) catch return error.VorbisAudioPacketSizeOverflow;
    }
    const curve_values = std.math.mul(
        usize,
        identification.channel_count,
        header.block_size / 2,
    ) catch return error.VorbisAudioPacketSizeOverflow;
    return .{
        .encodings = identification.channel_count,
        .y_values = y_values,
        .curve_values = curve_values,
    };
}

pub fn fitVorbisAudioFloorOne(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    floor_targets: []const []const Float,
    scratch: VorbisAudioFloorOneScratch(Float),
    storage: VorbisAudioFloorOneStorage(Float),
) !VorbisAudioFloorOnePlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    const requirements = try requiredVorbisAudioFloorOneStorage(
        identification,
        setup,
        header,
    );
    if (floor_targets.len != requirements.encodings)
        return error.InvalidVorbisSpectrumBundle;
    const coefficient_count = header.block_size / 2;
    for (floor_targets) |target| {
        if (target.len != coefficient_count)
            return error.InvalidVorbisSpectrumShape;
        for (target) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisSpectrumValue;
        }
    }
    if (scratch.y_values.len < requirements.y_values or
        scratch.curves.len < requirements.curve_values)
        return error.VorbisAudioFloorScratchTooSmall;
    if (storage.encodings.len < requirements.encodings or
        storage.y_values.len < requirements.y_values or
        storage.curves.len < requirements.curve_values)
        return error.VorbisAudioFloorStorageTooSmall;

    const trial_y = scratch.y_values[0..requirements.y_values];
    const trial_curves =
        scratch.curves[0..requirements.curve_values];
    const encodings = storage.encodings[0..requirements.encodings];
    const y_values = storage.y_values[0..requirements.y_values];
    const curves = storage.curves[0..requirements.curve_values];
    try rejectVorbisAudioFloorOneOverlap(
        Float,
        setup,
        floor_targets,
        trial_y,
        trial_curves,
        encodings,
        y_values,
        curves,
    );

    const mapping = setup.mappings[
        setup.modes[header.mode_number].mapping
    ];
    var used = [_]bool{false} ** 255;
    var y_offset: usize = 0;
    var total_error: f128 = 0;
    @memset(trial_y, 0);
    for (
        mapping.channel_mux[0..identification.channel_count],
        floor_targets,
        0..,
    ) |mux, target, channel| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        const channel_y =
            trial_y[y_offset..][0..floor.point_count];
        const fit = try fitVorbisFloorOne(
            Float,
            setup,
            floor_number,
            target,
            channel_y,
        );
        const channel_curve =
            trial_curves[channel * coefficient_count ..][0..coefficient_count];
        try synthesizeVorbisFloorOne(
            Float,
            floor,
            .{
                .used = fit.encoding.used,
                .value_count = if (fit.encoding.used)
                    floor.point_count
                else
                    0,
            },
            channel_y,
            channel_curve,
        );
        used[channel] = fit.encoding.used;
        total_error += fit.squared_control_point_error;
        y_offset += floor.point_count;
    }
    if (y_offset != requirements.y_values)
        return error.InvalidVorbisAudioFloorState;

    @memcpy(y_values, trial_y);
    @memcpy(curves, trial_curves);
    y_offset = 0;
    for (
        mapping.channel_mux[0..identification.channel_count],
        encodings,
        used[0..identification.channel_count],
    ) |mux, *encoding, channel_used| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        encoding.* = .{ .one = if (channel_used)
            .{
                .used = true,
                .y_values = y_values[y_offset..][0..floor.point_count],
            }
        else
            .{} };
        y_offset += floor.point_count;
    }
    return .{
        .encodings = encodings,
        .y_values = y_values,
        .curves = curves,
        .coefficient_count = coefficient_count,
        .squared_control_point_error = @floatCast(total_error),
    };
}

pub fn requiredVorbisAudioResiduePreparationStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioResiduePreparationStorageRequirements {
    const floor = try requiredVorbisAudioFloorOneStorage(
        identification,
        setup,
        header,
    );
    const coupling = try requiredVorbisCouplingScratch(
        identification.channel_count,
        header.block_size / 2,
    );
    return .{
        .floor_encodings = floor.encodings,
        .floor_y_values = floor.y_values,
        .floor_curve_values = floor.curve_values,
        .residue_values = floor.curve_values,
        .threshold_values = floor.curve_values,
        .coupling_values = coupling,
        .do_not_encode = identification.channel_count,
    };
}

pub fn prepareVorbisAudioResidue(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    spectra: []const []const Float,
    floor_targets: []const []const Float,
    noise_thresholds: []const []const Float,
    scratch: VorbisAudioResiduePreparationScratch(Float),
    storage: VorbisAudioResiduePreparationStorage(Float),
) !VorbisAudioResiduePreparationPlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    const requirements =
        try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            header,
        );
    if (spectra.len != identification.channel_count or
        floor_targets.len != identification.channel_count or
        noise_thresholds.len != identification.channel_count)
        return error.InvalidVorbisSpectrumBundle;
    const coefficient_count: usize = header.block_size / 2;
    for (spectra, floor_targets, noise_thresholds) |
        spectrum,
        floor_target,
        thresholds,
    | {
        if (spectrum.len != coefficient_count or
            floor_target.len != coefficient_count or
            thresholds.len != coefficient_count)
            return error.InvalidVorbisSpectrumShape;
        for (spectrum) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisSpectrumValue;
        }
        for (floor_target) |value| {
            if (!std.math.isFinite(value) or value < 0)
                return error.InvalidVorbisSpectrumValue;
        }
        for (thresholds) |value| {
            if (!std.math.isFinite(value) or value < 0)
                return error.InvalidVorbisNoiseThreshold;
        }
    }
    if (scratch.floor_fit_y_values.len <
        requirements.floor_y_values or
        scratch.floor_fit_curves.len <
            requirements.floor_curve_values or
        scratch.floor_encodings.len <
            requirements.floor_encodings or
        scratch.floor_y_values.len <
            requirements.floor_y_values or
        scratch.floor_curves.len <
            requirements.floor_curve_values or
        scratch.residue_values.len <
            requirements.residue_values or
        scratch.noise_thresholds.len <
            requirements.threshold_values or
        scratch.coupling_values.len <
            requirements.coupling_values or
        scratch.coupling_thresholds.len <
            requirements.coupling_values or
        scratch.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResiduePreparationScratchTooSmall;
    if (storage.floor_encodings.len <
        requirements.floor_encodings or
        storage.floor_y_values.len <
            requirements.floor_y_values or
        storage.floor_curves.len <
            requirements.floor_curve_values or
        storage.residue_values.len <
            requirements.residue_values or
        storage.noise_thresholds.len <
            requirements.threshold_values or
        storage.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResiduePreparationStorageTooSmall;

    const fit_y =
        scratch.floor_fit_y_values[0..requirements.floor_y_values];
    const fit_curves =
        scratch.floor_fit_curves[0..requirements.floor_curve_values];
    const trial_encodings =
        scratch.floor_encodings[0..requirements.floor_encodings];
    const trial_y =
        scratch.floor_y_values[0..requirements.floor_y_values];
    const trial_curves =
        scratch.floor_curves[0..requirements.floor_curve_values];
    const trial_residue =
        scratch.residue_values[0..requirements.residue_values];
    const trial_thresholds =
        scratch.noise_thresholds[0..requirements.threshold_values];
    const coupling_values =
        scratch.coupling_values[0..requirements.coupling_values];
    const coupling_thresholds =
        scratch.coupling_thresholds[0..requirements.coupling_values];
    const trial_skips =
        scratch.do_not_encode[0..requirements.do_not_encode];
    const floor_encodings =
        storage.floor_encodings[0..requirements.floor_encodings];
    const floor_y_values =
        storage.floor_y_values[0..requirements.floor_y_values];
    const floor_curves =
        storage.floor_curves[0..requirements.floor_curve_values];
    const residue_values =
        storage.residue_values[0..requirements.residue_values];
    const retained_thresholds =
        storage.noise_thresholds[0..requirements.threshold_values];
    const do_not_encode =
        storage.do_not_encode[0..requirements.do_not_encode];
    try rejectVorbisAudioResiduePreparationOverlap(
        Float,
        setup,
        spectra,
        floor_targets,
        noise_thresholds,
        fit_y,
        fit_curves,
        trial_encodings,
        trial_y,
        trial_curves,
        trial_residue,
        trial_thresholds,
        coupling_values,
        coupling_thresholds,
        trial_skips,
        floor_encodings,
        floor_y_values,
        floor_curves,
        residue_values,
        retained_thresholds,
        do_not_encode,
    );

    const floor = try fitVorbisAudioFloorOne(
        Float,
        identification,
        setup,
        header,
        floor_targets,
        .{
            .y_values = fit_y,
            .curves = fit_curves,
        },
        .{
            .encodings = trial_encodings,
            .y_values = trial_y,
            .curves = trial_curves,
        },
    );
    var residue_channels: [255][]Float = undefined;
    var residue_inputs: [255][]const Float = undefined;
    var threshold_channels: [255][]Float = undefined;
    for (0..identification.channel_count) |channel| {
        const start = channel * coefficient_count;
        const channel_residue =
            trial_residue[start..][0..coefficient_count];
        const channel_thresholds =
            trial_thresholds[start..][0..coefficient_count];
        const floor_curve =
            floor.curves[start..][0..coefficient_count];
        if (floor.encodings[channel].one.used) {
            try normalizeVorbisResidue(
                Float,
                spectra[channel],
                floor_curve,
                channel_residue,
            );
            try normalizeVorbisNoiseThresholds(
                Float,
                noise_thresholds[channel],
                floor_curve,
                channel_thresholds,
            );
        } else {
            @memset(channel_residue, 0);
            @memset(
                channel_thresholds,
                std.math.floatMax(Float),
            );
        }
        residue_channels[channel] = channel_residue;
        residue_inputs[channel] = channel_residue;
        threshold_channels[channel] = channel_thresholds;
    }

    const mapping =
        setup.mappings[setup.modes[header.mode_number].mapping];
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        mapping,
        residue_inputs[0..identification.channel_count],
        threshold_channels[0..identification.channel_count],
        coupling_values,
        coupling_thresholds,
    );
    try forwardCoupleVorbisChannels(
        Float,
        mapping,
        residue_channels[0..identification.channel_count],
        coupling_values,
    );
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = header.mode_number,
            .previous_window_flag = header.previous_window_flag,
            .next_window_flag = header.next_window_flag,
            .floors = floor.encodings,
        },
        trial_skips,
    );
    if (!std.meta.eql(fixed.header, header))
        return error.InvalidVorbisPacketBitOffset;

    @memcpy(floor_y_values, trial_y);
    @memcpy(floor_curves, trial_curves);
    @memcpy(residue_values, trial_residue);
    @memcpy(retained_thresholds, trial_thresholds);
    @memcpy(do_not_encode, trial_skips);
    var y_offset: usize = 0;
    for (0..identification.channel_count) |channel| {
        const floor_number =
            mapping.submaps[mapping.channel_mux[channel]].floor;
        const floor_one = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        const used = floor.encodings[channel].one.used;
        floor_encodings[channel] = .{ .one = if (used)
            .{
                .used = true,
                .y_values = floor_y_values[y_offset..][0..floor_one.point_count],
            }
        else
            .{} };
        y_offset += floor_one.point_count;
    }
    if (y_offset != requirements.floor_y_values)
        return error.InvalidVorbisAudioFloorState;
    return .{
        .floor_encodings = floor_encodings,
        .floor_y_values = floor_y_values,
        .floor_curves = floor_curves,
        .residue_values = residue_values,
        .noise_thresholds = retained_thresholds,
        .do_not_encode = do_not_encode,
        .coefficient_count = coefficient_count,
        .fixed_packet_bits = fixed.bit_count,
        .squared_control_point_error = floor.squared_control_point_error,
    };
}

pub fn requiredVorbisPcmPacketEncodingStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    frame: VorbisPcmFramePlan,
) !VorbisPcmPacketEncodingStorageRequirements {
    return .{
        .preparation = try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            frame.header,
        ),
        .quantization = try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            frame.header,
        ),
    };
}

pub fn encodeVorbisPcmPacket(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
    analyzer: *VorbisPcmFrameAnalyzer(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    ),
    sequence: *const VorbisPcmPacketSequence,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    plan: VorbisPcmPacketPlan,
    inputs: []const []const Float,
    psychoacoustic_config: VorbisPsychoacousticConfig,
    residue_weights: []const f64,
    residue_config: VorbisAudioResidueQuantizationConfig,
    destination: []u8,
    scratch: VorbisPcmPacketOrchestrationScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !VorbisPcmPacketEncodingTrial(Float) {
    if (identification.channel_count != channel_count or
        identification.small_block_size != small_block_size or
        identification.large_block_size != large_block_size)
        return error.InvalidVorbisPcmEncoderConfiguration;
    const analysis = try analyzer.analyze(
        inputs,
        plan.frame,
        psychoacoustic_config,
        identification.sample_rate,
        scratch.analysis,
        scratch.analysis_storage,
    );
    return encodeVorbisPcmPacketTrial(
        Float,
        sequence,
        identification,
        setup,
        plan,
        analysis,
        residue_weights,
        residue_config,
        destination,
        scratch.encoding,
        storage,
    );
}

pub fn encodeVorbisPcmPacketTrial(
    comptime Float: type,
    sequence: *const VorbisPcmPacketSequence,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    plan: VorbisPcmPacketPlan,
    analysis: VorbisPcmFrameAnalysisPlan(Float),
    weights: []const f64,
    config: VorbisAudioResidueQuantizationConfig,
    destination: []u8,
    scratch: VorbisPcmPacketEncodingScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !VorbisPcmPacketEncodingTrial(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    try sequence.validatePlan(plan);
    if (!std.meta.eql(analysis.frame, plan.frame))
        return error.InvalidVorbisPcmFrameAnalysisPlan;
    const coefficient_count: usize = plan.frame.header.block_size / 2;
    const value_count = std.math.mul(
        usize,
        identification.channel_count,
        coefficient_count,
    ) catch return error.VorbisPcmPacketEncodingSizeOverflow;
    if (analysis.coefficient_count != coefficient_count or
        analysis.spectra.len != value_count or
        analysis.analyses.len != identification.channel_count or
        analysis.floor_targets.len != value_count or
        analysis.noise_thresholds.len != value_count)
        return error.InvalidVorbisPcmFrameAnalysisPlan;

    const requirements =
        try requiredVorbisPcmPacketEncodingStorage(
            identification,
            setup,
            plan.frame,
        );
    try validateVorbisPcmPacketEncodingStorage(
        Float,
        setup,
        analysis,
        weights,
        destination,
        requirements,
        scratch,
        storage,
    );

    var spectra: [255][]const Float = undefined;
    var floor_targets: [255][]const Float = undefined;
    var noise_thresholds: [255][]const Float = undefined;
    for (0..identification.channel_count) |channel| {
        const start = channel * coefficient_count;
        spectra[channel] =
            analysis.spectra[start..][0..coefficient_count];
        floor_targets[channel] =
            analysis.floor_targets[start..][0..coefficient_count];
        noise_thresholds[channel] =
            analysis.noise_thresholds[start..][0..coefficient_count];
    }
    const prepared = try prepareVorbisAudioResidue(
        Float,
        identification,
        setup,
        plan.frame.header,
        spectra[0..identification.channel_count],
        floor_targets[0..identification.channel_count],
        noise_thresholds[0..identification.channel_count],
        scratch.preparation,
        scratch.preparation_storage,
    );
    const quantized = try quantizeVorbisAudioResiduesAdaptive(
        Float,
        identification,
        setup,
        plan.frame.header,
        prepared.residue_values,
        prepared.noise_thresholds,
        prepared.do_not_encode,
        plan.budget,
        prepared.fixed_packet_bits,
        weights,
        config,
        scratch.quantization,
        scratch.quantization_storage,
    );
    const encoding = VorbisAudioPacketEncoding{
        .mode_number = plan.frame.header.mode_number,
        .previous_window_flag = plan.frame.header.previous_window_flag,
        .next_window_flag = plan.frame.header.next_window_flag,
        .floors = prepared.floor_encodings,
        .residues = quantized.encodings,
    };

    var counter = VorbisPacketWriter.counting();
    const counted_header = try writeVorbisAudioPacket(
        &counter,
        identification,
        setup,
        encoding,
    );
    if (!std.meta.eql(counted_header, plan.frame.header))
        return error.InvalidVorbisPcmFrameAnalysisPlan;
    const actual_bits = std.math.cast(
        u32,
        counter.bit_offset,
    ) orelse return error.VorbisAudioPacketSizeOverflow;
    var sequence_after = sequence.*;
    const commit = try sequence_after.commit(plan, actual_bits);
    const required_bytes =
        counter.bit_offset / 8 +
        @intFromBool(counter.bit_offset % 8 != 0);
    if (destination.len < required_bytes)
        return error.VorbisAudioPacketOutputTooSmall;

    const packet = try encodeVorbisAudioPacket(
        destination[0..required_bytes],
        identification,
        setup,
        encoding,
    );
    const retained_preparation =
        try retainVorbisAudioResiduePreparation(
            identification,
            setup,
            plan.frame.header,
            prepared,
            storage.preparation,
        );
    const retained_quantization =
        retainVorbisAudioResidueQuantization(
            quantized,
            storage.quantization,
        );
    return .{
        .packet = packet,
        .commit = commit,
        .preparation = retained_preparation,
        .quantization = retained_quantization,
    };
}

pub fn validateVorbisPcmPacketEncodingStorage(
    comptime Float: type,
    setup: VorbisSetup,
    analysis: VorbisPcmFrameAnalysisPlan(Float),
    weights: []const f64,
    destination: []u8,
    requirements: VorbisPcmPacketEncodingStorageRequirements,
    scratch: VorbisPcmPacketEncodingScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !void {
    const preparation = requirements.preparation;
    const quantization = requirements.quantization;
    if (scratch.preparation_storage.floor_encodings.len <
        preparation.floor_encodings or
        scratch.preparation_storage.floor_y_values.len <
            preparation.floor_y_values or
        scratch.preparation_storage.floor_curves.len <
            preparation.floor_curve_values or
        scratch.preparation_storage.residue_values.len <
            preparation.residue_values or
        scratch.preparation_storage.noise_thresholds.len <
            preparation.threshold_values or
        scratch.preparation_storage.do_not_encode.len <
            preparation.do_not_encode or
        scratch.quantization_storage.encodings.len <
            quantization.encodings or
        scratch.quantization_storage.submap_results.len <
            quantization.submap_results or
        scratch.quantization_storage.do_not_encode.len <
            quantization.do_not_encode or
        scratch.quantization_storage.classifications.len <
            quantization.classifications or
        scratch.quantization_storage.entries.len <
            quantization.entries)
        return error.VorbisPcmPacketEncodingScratchTooSmall;
    if (storage.preparation.floor_encodings.len <
        preparation.floor_encodings or
        storage.preparation.floor_y_values.len <
            preparation.floor_y_values or
        storage.preparation.floor_curves.len <
            preparation.floor_curve_values or
        storage.preparation.residue_values.len <
            preparation.residue_values or
        storage.preparation.noise_thresholds.len <
            preparation.threshold_values or
        storage.preparation.do_not_encode.len <
            preparation.do_not_encode or
        storage.quantization.encodings.len <
            quantization.encodings or
        storage.quantization.submap_results.len <
            quantization.submap_results or
        storage.quantization.do_not_encode.len <
            quantization.do_not_encode or
        storage.quantization.classifications.len <
            quantization.classifications or
        storage.quantization.entries.len <
            quantization.entries)
        return error.VorbisPcmPacketEncodingStorageTooSmall;

    const buffers = [_][]u8{
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_encodings[0..preparation.floor_encodings],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_y_values[0..preparation.floor_y_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_curves[0..preparation.floor_curve_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.residue_values[0..preparation.residue_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.noise_thresholds[0..preparation.threshold_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.do_not_encode[0..preparation.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.encodings[0..quantization.encodings],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.submap_results[0..quantization.submap_results],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.do_not_encode[0..quantization.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.classifications[0..quantization.classifications],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.entries[0..quantization.entries],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_encodings[0..preparation.floor_encodings],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_y_values[0..preparation.floor_y_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_curves[0..preparation.floor_curve_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.residue_values[0..preparation.residue_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.noise_thresholds[0..preparation.threshold_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.do_not_encode[0..preparation.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.encodings[0..quantization.encodings],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.submap_results[0..quantization.submap_results],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.do_not_encode[0..quantization.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.classifications[0..quantization.classifications],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.entries[0..quantization.entries],
        ),
    };
    const sources = [_][]const u8{
        std.mem.sliceAsBytes(analysis.spectra),
        std.mem.sliceAsBytes(analysis.analyses),
        std.mem.sliceAsBytes(analysis.floor_targets),
        std.mem.sliceAsBytes(analysis.noise_thresholds),
        std.mem.sliceAsBytes(weights),
        destination,
    };
    for (buffers, 0..) |buffer, index| {
        for (buffers[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(u8, buffer, earlier))
                return error.OverlappingVorbisPcmPacketEncodingStorage;
        }
        for (sources) |source| {
            if (vorbisConstSlicesOverlap(u8, buffer, source))
                return error.OverlappingVorbisPcmPacketEncodingStorage;
        }
        rejectVorbisSetupOverlap(
            buffer,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPcmPacketEncodingStorage,
            else => return err,
        };
    }
    for (sources[0 .. sources.len - 1]) |source| {
        if (vorbisConstSlicesOverlap(u8, destination, source))
            return error.OverlappingVorbisPcmPacketEncodingStorage;
    }
}

pub fn retainVorbisAudioResiduePreparation(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    plan: anytype,
    storage: anytype,
) !@TypeOf(plan) {
    @memcpy(
        storage.floor_y_values[0..plan.floor_y_values.len],
        plan.floor_y_values,
    );
    @memcpy(
        storage.floor_curves[0..plan.floor_curves.len],
        plan.floor_curves,
    );
    @memcpy(
        storage.residue_values[0..plan.residue_values.len],
        plan.residue_values,
    );
    @memcpy(
        storage.noise_thresholds[0..plan.noise_thresholds.len],
        plan.noise_thresholds,
    );
    @memcpy(
        storage.do_not_encode[0..plan.do_not_encode.len],
        plan.do_not_encode,
    );
    const mapping =
        setup.mappings[setup.modes[header.mode_number].mapping];
    var y_offset: usize = 0;
    for (0..identification.channel_count) |channel| {
        const floor_number =
            mapping.submaps[mapping.channel_mux[channel]].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        const used = plan.floor_encodings[channel].one.used;
        storage.floor_encodings[channel] = .{
            .one = if (used)
                .{
                    .used = true,
                    .y_values = storage.floor_y_values[y_offset..][0..floor.point_count],
                }
            else
                .{},
        };
        y_offset += floor.point_count;
    }
    return .{
        .floor_encodings = storage.floor_encodings[0..plan.floor_encodings.len],
        .floor_y_values = storage.floor_y_values[0..plan.floor_y_values.len],
        .floor_curves = storage.floor_curves[0..plan.floor_curves.len],
        .residue_values = storage.residue_values[0..plan.residue_values.len],
        .noise_thresholds = storage.noise_thresholds[0..plan.noise_thresholds.len],
        .do_not_encode = storage.do_not_encode[0..plan.do_not_encode.len],
        .coefficient_count = plan.coefficient_count,
        .fixed_packet_bits = plan.fixed_packet_bits,
        .squared_control_point_error = plan.squared_control_point_error,
    };
}

pub fn retainVorbisAudioResidueQuantization(
    plan: VorbisAudioResidueQuantizationPlan,
    storage: VorbisAudioResidueQuantizationStorage,
) VorbisAudioResidueQuantizationPlan {
    @memcpy(
        storage.submap_results[0..plan.submap_results.len],
        plan.submap_results,
    );
    @memcpy(
        storage.do_not_encode[0..plan.do_not_encode.len],
        plan.do_not_encode,
    );
    @memcpy(
        storage.classifications[0..plan.classifications.len],
        plan.classifications,
    );
    @memcpy(
        storage.entries[0..plan.entries.len],
        plan.entries,
    );
    var skip_offset: usize = 0;
    var classification_offset: usize = 0;
    var entry_offset: usize = 0;
    for (plan.encodings, 0..) |source, index| {
        storage.encodings[index] = .{
            .do_not_encode = storage.do_not_encode[skip_offset..][0..source.do_not_encode.len],
            .classifications = storage.classifications[classification_offset..][0..source.classifications.len],
            .entries = storage.entries[entry_offset..][0..source.entries.len],
        };
        skip_offset += source.do_not_encode.len;
        classification_offset += source.classifications.len;
        entry_offset += source.entries.len;
    }
    return .{
        .encodings = storage.encodings[0..plan.encodings.len],
        .submap_results = storage.submap_results[0..plan.submap_results.len],
        .do_not_encode = storage.do_not_encode[0..plan.do_not_encode.len],
        .classifications = storage.classifications[0..plan.classifications.len],
        .entries = storage.entries[0..plan.entries.len],
        .allocation = plan.allocation,
    };
}

pub fn rejectVorbisAudioResiduePreparationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    spectra: []const []const Float,
    floor_targets: []const []const Float,
    noise_thresholds: []const []const Float,
    fit_y: []u32,
    fit_curves: []Float,
    trial_encodings: []VorbisFloorPacketEncoding,
    trial_y: []u32,
    trial_curves: []Float,
    trial_residue: []Float,
    trial_thresholds: []Float,
    coupling_values: []Float,
    coupling_thresholds: []Float,
    trial_skips: []bool,
    floor_encodings: []VorbisFloorPacketEncoding,
    floor_y_values: []u32,
    floor_curves: []Float,
    residue_values: []Float,
    retained_thresholds: []Float,
    do_not_encode: []bool,
) !void {
    const destinations = [_][]u8{
        std.mem.sliceAsBytes(fit_y),
        std.mem.sliceAsBytes(fit_curves),
        std.mem.sliceAsBytes(trial_encodings),
        std.mem.sliceAsBytes(trial_y),
        std.mem.sliceAsBytes(trial_curves),
        std.mem.sliceAsBytes(trial_residue),
        std.mem.sliceAsBytes(trial_thresholds),
        std.mem.sliceAsBytes(coupling_values),
        std.mem.sliceAsBytes(coupling_thresholds),
        std.mem.sliceAsBytes(trial_skips),
        std.mem.sliceAsBytes(floor_encodings),
        std.mem.sliceAsBytes(floor_y_values),
        std.mem.sliceAsBytes(floor_curves),
        std.mem.sliceAsBytes(residue_values),
        std.mem.sliceAsBytes(retained_thresholds),
        std.mem.sliceAsBytes(do_not_encode),
    };
    const bundles = [_][]const []const Float{
        spectra,
        floor_targets,
        noise_thresholds,
    };
    for (destinations, 0..) |destination, index| {
        for (destinations[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(
                u8,
                destination,
                earlier,
            )) return error.OverlappingVorbisAudioResiduePreparationStorage;
        }
        rejectVorbisSetupOverlap(
            destination,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioResiduePreparationStorage,
            else => return err,
        };
        for (bundles) |bundle| {
            if (vorbisSliceOverlapsBytes(
                []const Float,
                bundle,
                destination,
            )) return error.OverlappingVorbisAudioResiduePreparationStorage;
            for (bundle) |values| {
                if (vorbisSliceOverlapsBytes(
                    Float,
                    values,
                    destination,
                )) return error.OverlappingVorbisAudioResiduePreparationStorage;
            }
        }
    }
}

pub fn validateVorbisAudioFloorOneState(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisMapping {
    if (identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size >
            identification.large_block_size or
        !std.math.isPowerOfTwo(
            identification.small_block_size,
        ) or
        !std.math.isPowerOfTwo(
            identification.large_block_size,
        ))
        return error.InvalidVorbisIdentificationState;
    const mapping = try validateVorbisAudioDecodeState(
        identification,
        setup,
        header,
    );
    const expected_block_size: u16 = if (header.large_block)
        identification.large_block_size
    else
        identification.small_block_size;
    if (header.block_size != expected_block_size)
        return error.InvalidVorbisPcmBlockShape;
    if (header.large_block) {
        if (header.previous_window_flag == null or
            header.next_window_flag == null)
            return error.InvalidVorbisWindowState;
    } else if (header.previous_window_flag != null or
        header.next_window_flag != null)
        return error.InvalidVorbisWindowState;
    return mapping;
}

pub fn rejectVorbisAudioFloorOneOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    floor_targets: []const []const Float,
    trial_y: []u32,
    trial_curves: []Float,
    encodings: []VorbisFloorPacketEncoding,
    y_values: []u32,
    curves: []Float,
) !void {
    if (vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        Float,
        trial_curves,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        VorbisFloorPacketEncoding,
        encodings,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        VorbisFloorPacketEncoding,
        encodings,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        VorbisFloorPacketEncoding,
        encodings,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        VorbisFloorPacketEncoding,
        encodings,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        u32,
        y_values,
        Float,
        curves,
    ))
        return error.OverlappingVorbisAudioFloorStorage;

    inline for (.{
        trial_y,
        trial_curves,
        encodings,
        y_values,
        curves,
    }) |destination| {
        const destination_bytes =
            std.mem.sliceAsBytes(destination);
        rejectVorbisSetupOverlap(
            destination_bytes,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioFloorStorage,
            else => return err,
        };
        if (vorbisSliceOverlapsBytes(
            []const Float,
            floor_targets,
            destination_bytes,
        )) return error.OverlappingVorbisAudioFloorStorage;
        for (floor_targets) |target| {
            if (vorbisSliceOverlapsBytes(
                Float,
                target,
                destination_bytes,
            )) return error.OverlappingVorbisAudioFloorStorage;
        }
    }
}

pub fn fitVorbisFloorOne(
    comptime Float: type,
    setup: VorbisSetup,
    floor_number: u8,
    target_spectrum: []const Float,
    y_destination: []u32,
) !VorbisFloorOneFit {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor fitting requires f32 or f64 input");
    if (floor_number >= setup.floors.len)
        return error.InvalidVorbisFloorNumber;
    const floor = switch (setup.floors[floor_number]) {
        .one => |value| value,
        .zero => return error.InvalidVorbisFloorType,
    };
    try validateVorbisFloorOneState(floor, setup.codebooks);
    if (target_spectrum.len != floor.x_list[1])
        return error.InvalidVorbisSpectrumShape;

    var silent = true;
    for (target_spectrum) |value| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisSpectrumValue;
        silent = silent and value == 0;
    }
    if (silent) {
        return .{
            .encoding = .{},
            .squared_control_point_error = 0,
        };
    }
    if (y_destination.len < floor.point_count)
        return error.VorbisFloorOutputTooSmall;
    const output = y_destination[0..floor.point_count];
    try rejectVorbisFloorFitOverlap(
        Float,
        setup,
        target_spectrum,
        output,
    );

    const ranges = [_]i32{ 256, 128, 86, 64 };
    const range = ranges[floor.multiplier - 1];
    var desired_y = [_]i32{0} ** 65;
    desired_y[0] = vorbisFloorOneTargetY(
        Float,
        target_spectrum[0],
        floor.multiplier,
        range,
    );
    desired_y[1] = vorbisFloorOneTargetY(
        Float,
        target_spectrum[target_spectrum.len - 1],
        floor.multiplier,
        range,
    );
    for (2..floor.point_count) |index| {
        desired_y[index] = vorbisFloorOneTargetY(
            Float,
            target_spectrum[floor.x_list[index]],
            floor.multiplier,
            range,
        );
    }

    var staged_y = [_]u32{0} ** 65;
    var final_y = [_]i32{0} ** 65;
    staged_y[0] = @intCast(desired_y[0]);
    staged_y[1] = @intCast(desired_y[1]);
    final_y[0] = desired_y[0];
    final_y[1] = desired_y[1];
    var total_error: f128 = 0;
    var point_offset: usize = 2;
    for (floor.partition_classes[0..floor.partition_count]) |class_index| {
        const class = floor.classes[class_index];
        total_error += try fitVorbisFloorOneClass(
            setup,
            floor,
            class,
            point_offset,
            desired_y,
            &staged_y,
            &final_y,
            range,
        );
        point_offset += class.dimensions;
    }
    if (point_offset != floor.point_count)
        return error.InvalidVorbisSetupState;

    var counter = VorbisPacketWriter.counting();
    try counter.writeFloorOne(
        setup,
        floor_number,
        .{
            .used = true,
            .y_values = staged_y[0..floor.point_count],
        },
    );
    @memcpy(output, staged_y[0..floor.point_count]);
    return .{
        .encoding = .{
            .used = true,
            .y_values = output,
        },
        .squared_control_point_error = @floatCast(total_error),
    };
}

pub fn normalizeVorbisResidue(
    comptime Float: type,
    spectrum: []const Float,
    floor_curve: []const Float,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue normalization requires f32 or f64");
    if (spectrum.len != floor_curve.len or output.len != spectrum.len)
        return error.InvalidVorbisSpectrumShape;
    const exact_in_place =
        spectrum.len == output.len and spectrum.ptr == output.ptr;
    if ((!exact_in_place and
        vorbisConstSlicesOverlap(Float, spectrum, output)) or
        vorbisConstSlicesOverlap(Float, floor_curve, output))
        return error.OverlappingVorbisResidueNormalization;

    for (spectrum, floor_curve) |spectrum_value, floor_value| {
        if (!std.math.isFinite(spectrum_value) or
            !std.math.isFinite(floor_value) or floor_value <= 0)
            return error.InvalidVorbisSpectrumValue;
        if (!std.math.isFinite(spectrum_value / floor_value))
            return error.InvalidVorbisSpectrumValue;
    }
    for (spectrum, floor_curve, output) |
        spectrum_value,
        floor_value,
        *destination,
    | {
        destination.* = spectrum_value / floor_value;
    }
}

pub fn normalizeVorbisNoiseThresholds(
    comptime Float: type,
    thresholds: []const Float,
    floor_curve: []const Float,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis noise thresholds require f32 or f64");
    if (thresholds.len == 0 or
        thresholds.len != floor_curve.len or
        output.len != thresholds.len)
        return error.InvalidVorbisSpectrumShape;
    const exact_in_place =
        thresholds.len == output.len and thresholds.ptr == output.ptr;
    if ((!exact_in_place and
        vorbisConstSlicesOverlap(Float, thresholds, output)) or
        vorbisConstSlicesOverlap(Float, floor_curve, output))
        return error.OverlappingVorbisNoiseThresholdNormalization;

    for (thresholds, floor_curve) |threshold, floor_value| {
        if (!std.math.isFinite(threshold) or threshold <= 0 or
            !std.math.isFinite(floor_value) or floor_value <= 0 or
            !std.math.isFinite(threshold / floor_value) or
            threshold / floor_value <= 0)
            return error.InvalidVorbisNoiseThreshold;
    }
    for (thresholds, floor_curve, output) |
        threshold,
        floor_value,
        *destination,
    | {
        destination.* = threshold / floor_value;
    }
}

pub fn fitVorbisFloorOneClass(
    setup: VorbisSetup,
    floor: VorbisFloorOne,
    class: VorbisFloorOneClass,
    point_offset: usize,
    desired_y: [65]i32,
    staged_y: *[65]u32,
    final_y: *[65]i32,
    range: i32,
) !f128 {
    var best_error = std.math.inf(f128);
    var best_raw = [_]u32{0} ** 8;
    var best_final = final_y.*;
    var found = false;

    if (class.subclass_bits == 0) {
        best_error = try fitVorbisFloorOneClassword(
            setup,
            floor,
            class,
            point_offset,
            desired_y,
            final_y.*,
            0,
            &best_raw,
            &best_final,
            range,
        );
        found = true;
    } else {
        const masterbook_number: u8 = @intCast(class.masterbook);
        const masterbook = setup.codebooks[masterbook_number];
        const entries = try vorbisSetupSlice(
            VorbisCodebookEntry,
            setup.codebook_entries,
            masterbook.entry_offset,
            masterbook.entries,
        );
        for (entries, 0..) |entry, entry_number| {
            if (entry.length == 0) continue;
            _ = try writableVorbisCodeword(
                setup,
                masterbook_number,
                @intCast(entry_number),
            );
            var candidate_raw = [_]u32{0} ** 8;
            var candidate_final = final_y.*;
            const candidate_error = try fitVorbisFloorOneClassword(
                setup,
                floor,
                class,
                point_offset,
                desired_y,
                final_y.*,
                @intCast(entry_number),
                &candidate_raw,
                &candidate_final,
                range,
            );
            if (!found or candidate_error < best_error) {
                found = true;
                best_error = candidate_error;
                best_raw = candidate_raw;
                best_final = candidate_final;
            }
        }
    }
    if (!found) return error.UnencodableVorbisFloorValue;
    @memcpy(
        staged_y[point_offset..][0..class.dimensions],
        best_raw[0..class.dimensions],
    );
    for (point_offset..point_offset + class.dimensions) |index| {
        final_y[index] = best_final[index];
    }
    return best_error;
}

pub fn fitVorbisFloorOneClassword(
    setup: VorbisSetup,
    floor: VorbisFloorOne,
    class: VorbisFloorOneClass,
    point_offset: usize,
    desired_y: [65]i32,
    base_final_y: [65]i32,
    encoded_classword: u32,
    raw_values: *[8]u32,
    fitted_final_y: *[65]i32,
    range: i32,
) !f128 {
    fitted_final_y.* = base_final_y;
    var classword = encoded_classword;
    const mask =
        (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
    var error_sum: f128 = 0;
    for (0..class.dimensions) |dimension| {
        const point_index = point_offset + dimension;
        const low = vorbisFloorLowNeighbor(
            floor.x_list[0..floor.point_count],
            point_index,
        );
        const high = vorbisFloorHighNeighbor(
            floor.x_list[0..floor.point_count],
            point_index,
        );
        const predicted = vorbisFloorRenderPoint(
            floor.x_list[low],
            fitted_final_y[low],
            floor.x_list[high],
            fitted_final_y[high],
            floor.x_list[point_index],
        );
        const book = class.subclass_books[classword & mask];
        classword >>= @intCast(class.subclass_bits);
        const fitted = if (book < 0)
            VorbisFloorOneValueFit{
                .raw = 0,
                .final_y = predicted,
            }
        else
            try fitVorbisFloorOneValue(
                setup,
                @intCast(book),
                predicted,
                desired_y[point_index],
                range,
            );
        raw_values[dimension] = fitted.raw;
        fitted_final_y[point_index] = fitted.final_y;
        const difference =
            @as(f128, @floatFromInt(
                fitted.final_y - desired_y[point_index],
            ));
        error_sum += difference * difference;
    }
    return error_sum;
}

pub const VorbisFloorOneValueFit = struct {
    raw: u32,
    final_y: i32,
};

pub fn fitVorbisFloorOneValue(
    setup: VorbisSetup,
    codebook_number: u8,
    predicted: i32,
    desired: i32,
    range: i32,
) !VorbisFloorOneValueFit {
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    var result: ?VorbisFloorOneValueFit = null;
    var best_error: i64 = std.math.maxInt(i64);
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        const raw: u32 = @intCast(entry_number);
        _ = try writableVorbisCodeword(
            setup,
            codebook_number,
            raw,
        );
        const final_y = decodeVorbisFloorOneValue(
            predicted,
            range,
            raw,
        );
        const difference: i64 = final_y - desired;
        const squared = difference * difference;
        if (squared < best_error) {
            best_error = squared;
            result = .{
                .raw = raw,
                .final_y = final_y,
            };
        }
    }
    return result orelse error.UnencodableVorbisFloorValue;
}

pub fn decodeVorbisFloorOneValue(
    predicted: i32,
    range: i32,
    raw_value: u32,
) i32 {
    const value: i64 = raw_value;
    const high_room: i64 = range - predicted;
    const low_room: i64 = predicted;
    const room = 2 * @min(high_room, low_room);
    var decoded: i64 = predicted;
    if (value != 0) {
        if (value >= room) {
            decoded = if (high_room > low_room)
                value - low_room + predicted
            else
                predicted - value + high_room - 1;
        } else if (value & 1 != 0) {
            decoded = predicted - @divTrunc(value + 1, 2);
        } else {
            decoded = predicted + @divTrunc(value, 2);
        }
    }
    return @intCast(std.math.clamp(
        decoded,
        0,
        @as(i64, range - 1),
    ));
}

pub fn vorbisFloorOneTargetY(
    comptime Float: type,
    value: Float,
    multiplier: u3,
    range: i32,
) i32 {
    const magnitude: f64 = @abs(@as(f64, @floatCast(value)));
    if (magnitude <= vorbis_floor_one_inverse_db[0]) return 0;
    const step: f64 = 0.11512925 * 140.0 / 256.0;
    const table_index = std.math.clamp(
        @round(255.0 + @log(magnitude) / step),
        0.0,
        255.0,
    );
    return @intFromFloat(std.math.clamp(
        @round(table_index / @as(f64, @floatFromInt(multiplier))),
        0.0,
        @as(f64, @floatFromInt(range - 1)),
    ));
}

pub fn rejectVorbisFloorFitOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    target_spectrum: []const Float,
    output: []u32,
) !void {
    const output_bytes = std.mem.sliceAsBytes(output);
    if (vorbisSliceOverlapsBytes(
        Float,
        target_spectrum,
        output_bytes,
    )) return error.OverlappingVorbisFloorFit;
    inline for (.{
        setup.codebooks,
        setup.codebook_entries,
        setup.huffman_nodes,
        setup.codebook_multiplicands,
        setup.floors,
        setup.residues,
        setup.mappings,
        setup.modes,
    }) |values| {
        if (vorbisSliceOverlapsBytes(
            @TypeOf(values[0]),
            values,
            output_bytes,
        )) return error.OverlappingVorbisFloorFit;
    }
}

pub fn vorbisFloorLowNeighbor(points: []const u16, index: usize) usize {
    var result: usize = 0;
    for (1..index) |candidate| {
        if (points[candidate] < points[index] and
            points[candidate] > points[result])
            result = candidate;
    }
    return result;
}

pub fn vorbisFloorHighNeighbor(points: []const u16, index: usize) usize {
    var result: usize = 1;
    for (2..index) |candidate| {
        if (points[candidate] > points[index] and
            points[candidate] < points[result])
            result = candidate;
    }
    return result;
}

pub fn vorbisFloorRenderPoint(
    x0: u16,
    y0: i32,
    x1: u16,
    y1: i32,
    x: u16,
) i32 {
    const difference = y1 - y0;
    const absolute_difference: i32 = @intCast(@abs(difference));
    const offset = @divTrunc(
        absolute_difference * @as(i32, x - x0),
        @as(i32, x1 - x0),
    );
    return if (difference < 0) y0 - offset else y0 + offset;
}

pub fn renderVorbisFloorLine(
    comptime Float: type,
    x0: u16,
    y0: i32,
    x1: u16,
    y1: i32,
    output: []Float,
) void {
    const delta_x: i32 = x1 - x0;
    const delta_y = y1 - y0;
    var remainder: i32 = @intCast(@abs(delta_y));
    const base = @divTrunc(delta_y, delta_x);
    const step = if (delta_y < 0) base - 1 else base + 1;
    remainder -= @as(i32, @intCast(@abs(base))) * delta_x;
    var error_accumulator: i32 = 0;
    var y = y0;
    const end = @min(@as(usize, x1), output.len);
    for (x0..end) |x| {
        output[x] = vorbisFloorOneInverseDb(Float, @intCast(y));
        error_accumulator += remainder;
        if (error_accumulator >= delta_x) {
            error_accumulator -= delta_x;
            y += step;
        } else {
            y += base;
        }
    }
}

pub fn vorbisFloorOneInverseDb(comptime Float: type, index: u8) Float {
    return @floatCast(vorbis_floor_one_inverse_db[index]);
}

pub const vorbis_floor_one_inverse_db = table: {
    var values: [256]f64 = undefined;
    const step: f64 = 0.11512925 * 140.0 / 256.0;
    for (&values, 0..) |*value, index| {
        value.* = @exp(
            (@as(f64, @floatFromInt(index)) - 255.0) * step,
        );
    }
    break :table values;
};

pub fn readVorbisAudioBits(reader: *VorbisBitReader, bit_count: u6) !u32 {
    return reader.read(bit_count) catch |err| switch (err) {
        error.TruncatedVorbisSetup => error.TruncatedVorbisAudioPacket,
    };
}

pub fn parseVorbisCodebook(
    reader: *VorbisBitReader,
    entry_offset: u64,
    entry_destination: ?[]VorbisCodebookEntry,
    tree_node_offset: u64,
    node_destination: ?[]VorbisHuffmanNode,
    multiplicand_offset: u64,
    multiplicand_destination: ?[]u32,
) !VorbisCodebook {
    if (try reader.read(24) != 0x564342)
        return error.InvalidVorbisCodebookSync;
    const dimensions: u16 = @intCast(try reader.read(16));
    const entries = try reader.read(24);
    if (dimensions == 0 or entries == 0)
        return error.InvalidVorbisCodebook;
    const output = if (entry_destination) |destination|
        destination[0..entries]
    else
        null;
    if (output) |entry_output| {
        @memset(entry_output, .{ .codeword = 0, .length = 0 });
    }

    var length_counts = [_]u32{0} ** 32;
    var active_entries: u32 = 0;
    if (try reader.read(1) == 0) {
        const sparse = try reader.read(1) != 0;
        for (0..entries) |index| {
            if (sparse and try reader.read(1) == 0) continue;
            const length = try reader.read(5) + 1;
            length_counts[length - 1] += 1;
            active_entries += 1;
            if (output) |entry_output| {
                entry_output[index].length = @intCast(length);
            }
        }
    } else {
        var current_entry: u32 = 0;
        var current_length = try reader.read(5) + 1;
        while (current_entry < entries) : (current_length += 1) {
            if (current_length > 32)
                return error.InvalidVorbisCodebookLengths;
            const number = try reader.read(vorbisILog(entries - current_entry));
            if (number > entries - current_entry)
                return error.InvalidVorbisCodebookLengths;
            length_counts[current_length - 1] += number;
            active_entries += number;
            if (output) |entry_output| {
                for (entry_output[current_entry..][0..number]) |*entry| {
                    entry.length = @intCast(current_length);
                }
            }
            current_entry += number;
        }
    }
    try validateVorbisCodebookTree(&length_counts, active_entries);
    const tree_node_count = if (active_entries > 1)
        active_entries - 1
    else
        0;
    if (output) |entry_output| {
        assignVorbisCodewords(entry_output);
        if (node_destination) |destination| {
            try buildVorbisHuffmanTree(
                entry_output,
                destination[0..tree_node_count],
            );
        }
    }

    const lookup_value = try reader.read(4);
    if (lookup_value > 2) return error.UnsupportedVorbisCodebookLookup;
    const lookup_type: u2 = @intCast(lookup_value);
    var minimum_value: f64 = 0;
    var delta_value: f64 = 0;
    var sequence = false;
    var multiplicand_count: u64 = 0;
    if (lookup_type != 0) {
        minimum_value = vorbisFloat32Unpack(try reader.read(32));
        delta_value = vorbisFloat32Unpack(try reader.read(32));
        const value_bits = try reader.read(4) + 1;
        sequence = try reader.read(1) != 0;
        multiplicand_count = if (lookup_type == 1)
            vorbisLookupOneValues(entries, dimensions)
        else
            @as(u64, entries) * dimensions;
        if (multiplicand_destination) |destination| {
            const output_values =
                destination[0..@intCast(multiplicand_count)];
            for (output_values) |*value| {
                value.* = try reader.read(@intCast(value_bits));
            }
        } else {
            try reader.skip(multiplicand_count * value_bits);
        }
    }
    return .{
        .dimensions = dimensions,
        .entries = entries,
        .entry_offset = entry_offset,
        .active_entry_count = active_entries,
        .tree_node_offset = tree_node_offset,
        .tree_node_count = tree_node_count,
        .lookup_type = lookup_type,
        .minimum_value = minimum_value,
        .delta_value = delta_value,
        .sequence = sequence,
        .multiplicand_offset = multiplicand_offset,
        .multiplicand_count = multiplicand_count,
    };
}

pub const invalid_huffman_branch = std.math.maxInt(u32);
pub const huffman_leaf_flag: u32 = 1 << 31;

pub fn buildVorbisHuffmanTree(
    entries: []const VorbisCodebookEntry,
    nodes: []VorbisHuffmanNode,
) !void {
    if (nodes.len == 0) return;
    @memset(nodes, .{
        .branches = .{ invalid_huffman_branch, invalid_huffman_branch },
    });
    var next_node: u32 = 1;
    for (entries, 0..) |entry, entry_index| {
        if (entry.length == 0) continue;
        var node_index: u32 = 0;
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            const branch_index: usize =
                @intCast((entry.codeword >> shift) & 1);
            const branch = &nodes[node_index].branches[branch_index];
            if (depth + 1 == entry.length) {
                if (branch.* != invalid_huffman_branch)
                    return error.InvalidVorbisCodebookTree;
                branch.* = huffman_leaf_flag | @as(u32, @intCast(entry_index));
            } else if (branch.* == invalid_huffman_branch) {
                if (next_node >= nodes.len)
                    return error.InvalidVorbisCodebookTree;
                branch.* = next_node;
                node_index = next_node;
                next_node += 1;
            } else {
                if (branch.* & huffman_leaf_flag != 0)
                    return error.InvalidVorbisCodebookTree;
                node_index = branch.*;
            }
        }
    }
    if (next_node != nodes.len)
        return error.InvalidVorbisCodebookTree;
}

pub fn vorbisFloat32Unpack(encoded: u32) f64 {
    const unsigned_mantissa = encoded & 0x1fffff;
    const mantissa: i32 = if (encoded & 0x80000000 != 0)
        -@as(i32, @intCast(unsigned_mantissa))
    else
        @intCast(unsigned_mantissa);
    const exponent: i32 = @intCast((encoded & 0x7fe00000) >> 21);
    return std.math.ldexp(@as(f64, @floatFromInt(mantissa)), exponent - 788);
}

pub fn vorbisFloat32PackExact(value: f64) !u32 {
    if (!std.math.isFinite(value))
        return error.InvalidVorbisCodebookFloat;
    if (value == 0) return 0;
    const magnitude = @abs(value);
    for (0..1024) |exponent| {
        const scaled = std.math.ldexp(
            magnitude,
            788 - @as(i32, @intCast(exponent)),
        );
        if (!std.math.isFinite(scaled) or scaled < 1 or
            scaled > 0x1fffff or @trunc(scaled) != scaled)
            continue;
        const mantissa: u32 = @intFromFloat(scaled);
        const encoded =
            (@as(u32, @intCast(exponent)) << 21) |
            mantissa |
            if (std.math.signbit(value))
                @as(u32, 0x80000000)
            else
                0;
        if (vorbisFloat32Unpack(encoded) == value)
            return encoded;
    }
    return error.UnrepresentableVorbisCodebookFloat;
}

pub fn assignVorbisCodewords(entries: []VorbisCodebookEntry) void {
    var markers = [_]u32{0} ** 33;
    for (entries) |*entry| {
        if (entry.length == 0) continue;
        const length: usize = entry.length;
        const assigned_codeword = markers[length];

        var level = length;
        while (level != 0) {
            if (markers[level] & 1 != 0) {
                if (level == 1)
                    markers[1] += 1
                else
                    markers[level] = markers[level - 1] << 1;
                break;
            }
            markers[level] += 1;
            level -= 1;
        }

        var branch = assigned_codeword;
        for (length + 1..markers.len) |deeper| {
            if (markers[deeper] >> 1 != branch) break;
            branch = markers[deeper];
            markers[deeper] = markers[deeper - 1] << 1;
        }

        entry.codeword = assigned_codeword;
    }
}

pub fn validateVorbisCodebookTree(
    length_counts: *const [32]u32,
    active_entries: u32,
) !void {
    if (active_entries == 1) {
        if (length_counts[0] != 1)
            return error.InvalidVorbisCodebookLengths;
        return;
    }
    var available: u64 = 1;
    for (length_counts) |count| {
        available *= 2;
        if (count > available)
            return error.InvalidVorbisCodebookLengths;
        available -= count;
    }
    if (active_entries == 0 or available != 0)
        return error.InvalidVorbisCodebookLengths;
}

pub fn parseVorbisFloorZero(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisFloorZero {
    const order: u8 = @intCast(try reader.read(8));
    const rate: u16 = @intCast(try reader.read(16));
    const bark_map_size: u16 = @intCast(try reader.read(16));
    const amplitude_bits: u6 = @intCast(try reader.read(6));
    const amplitude_offset: u8 = @intCast(try reader.read(8));
    const book_count: u5 = @intCast(try reader.read(4) + 1);
    if (order == 0 or rate == 0 or bark_map_size == 0)
        return error.InvalidVorbisFloorConfiguration;
    var books = [_]u8{0} ** 16;
    for (books[0..book_count]) |*destination| {
        const book = try reader.read(8);
        if (book >= codebooks.len)
            return error.InvalidVorbisFloorCodebook;
        if (codebooks[book].lookup_type == 0)
            return error.InvalidVorbisFloorCodebook;
        destination.* = @intCast(book);
    }
    return .{
        .order = order,
        .rate = rate,
        .bark_map_size = bark_map_size,
        .amplitude_bits = amplitude_bits,
        .amplitude_offset = amplitude_offset,
        .book_count = book_count,
        .books = books,
    };
}

pub fn parseVorbisFloorOne(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisFloorOne {
    const partition_count: u5 = @intCast(try reader.read(5));
    var partition_classes = [_]u4{0} ** 31;
    var maximum_class: ?u4 = null;
    for (partition_classes[0..partition_count]) |*class| {
        class.* = @intCast(try reader.read(4));
        maximum_class = @max(maximum_class orelse 0, class.*);
    }
    var classes = [_]VorbisFloorOneClass{.{
        .dimensions = 0,
        .subclass_bits = 0,
        .masterbook = -1,
        .subclass_books = [_]i16{-1} ** 8,
    }} ** 16;
    const class_count: u5 = if (maximum_class) |highest|
        @as(u5, highest) + 1
    else
        0;
    if (maximum_class) |highest| {
        for (classes[0 .. @as(usize, highest) + 1]) |*class| {
            class.dimensions = @intCast(try reader.read(3) + 1);
            class.subclass_bits = @intCast(try reader.read(2));
            if (class.subclass_bits != 0) {
                const masterbook = try reader.read(8);
                if (masterbook >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                class.masterbook = @intCast(masterbook);
            }
            const subclass_count =
                @as(usize, 1) << @intCast(class.subclass_bits);
            for (class.subclass_books[0..subclass_count]) |*destination| {
                const encoded_book = try reader.read(8);
                if (encoded_book != 0 and encoded_book - 1 >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                destination.* = @as(i16, @intCast(encoded_book)) - 1;
            }
        }
    }
    const multiplier: u3 = @intCast(try reader.read(2) + 1);
    const range_bits: u6 = @intCast(try reader.read(4));
    var points = [_]u16{0} ** 65;
    points[1] = @as(u16, 1) << @intCast(range_bits);
    var point_count: usize = 2;
    for (partition_classes[0..partition_count]) |class| {
        const dimensions = classes[class].dimensions;
        if (dimensions > 65 - point_count)
            return error.TooManyVorbisFloorPoints;
        for (0..dimensions) |_| {
            const point: u16 = @intCast(try reader.read(range_bits));
            for (points[0..point_count]) |existing| {
                if (point == existing)
                    return error.DuplicateVorbisFloorPoint;
            }
            points[point_count] = point;
            point_count += 1;
        }
    }
    return .{
        .partition_count = partition_count,
        .partition_classes = partition_classes,
        .class_count = class_count,
        .classes = classes,
        .multiplier = multiplier,
        .range_bits = @intCast(range_bits),
        .point_count = @intCast(point_count),
        .x_list = points,
    };
}

pub fn parseVorbisResidue(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisResidue {
    const residue_type = try reader.read(16);
    if (residue_type > 2) return error.UnsupportedVorbisResidueType;
    const begin: u24 = @intCast(try reader.read(24));
    const end: u24 = @intCast(try reader.read(24));
    const partition_size: u25 = @intCast(try reader.read(24) + 1);
    const classification_count: u7 = @intCast(try reader.read(6) + 1);
    const classbook_index = try reader.read(8);
    if (classbook_index >= codebooks.len)
        return error.InvalidVorbisResidueCodebook;
    const classbook = codebooks[classbook_index];
    if (!powerAtMost(
        classification_count,
        classbook.dimensions,
        classbook.entries,
    )) return error.InvalidVorbisResidueClassbook;

    var cascades = [_]u8{0} ** 64;
    for (cascades[0..classification_count]) |*cascade| {
        const low: u8 = @intCast(try reader.read(3));
        const high: u8 = if (try reader.read(1) != 0)
            @intCast(try reader.read(5))
        else
            0;
        cascade.* = high * 8 + low;
    }
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    for (cascades[0..classification_count], 0..) |cascade, classification| {
        for (0..8) |pass| {
            if (cascade & (@as(u8, 1) << @intCast(pass)) == 0) continue;
            const book_index = try reader.read(8);
            if (book_index >= codebooks.len or
                codebooks[book_index].lookup_type == 0 or
                partition_size % codebooks[book_index].dimensions != 0)
                return error.InvalidVorbisResidueCodebook;
            books[classification][pass] = @intCast(book_index);
        }
    }
    return .{
        .kind = @enumFromInt(residue_type),
        .begin = begin,
        .end = end,
        .partition_size = partition_size,
        .classification_count = classification_count,
        .classbook = @intCast(classbook_index),
        .cascades = cascades,
        .books = books,
    };
}

pub fn parseVorbisMapping(
    reader: *VorbisBitReader,
    channel_count: u8,
    floor_count: u8,
    residue_count: u8,
) !VorbisMapping {
    if (try reader.read(16) != 0)
        return error.UnsupportedVorbisMappingType;
    const submap_count: u8 = if (try reader.read(1) != 0)
        @intCast(try reader.read(4) + 1)
    else
        1;
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    var coupling_step_count: u9 = 0;
    if (try reader.read(1) != 0) {
        coupling_step_count = @intCast(try reader.read(8) + 1);
        const channel_bits = vorbisILog(channel_count - 1);
        for (coupling_steps[0..coupling_step_count]) |*step| {
            const magnitude = try reader.read(channel_bits);
            const angle = try reader.read(channel_bits);
            if (magnitude == angle or magnitude >= channel_count or
                angle >= channel_count)
                return error.InvalidVorbisChannelCoupling;
            step.* = .{
                .magnitude = @intCast(magnitude),
                .angle = @intCast(angle),
            };
        }
    }
    if (try reader.read(2) != 0)
        return error.InvalidVorbisMappingReservedBits;
    var channel_mux = [_]u4{0} ** 255;
    if (submap_count > 1) {
        for (channel_mux[0..channel_count]) |*mux| {
            const decoded = try reader.read(4);
            if (decoded >= submap_count)
                return error.InvalidVorbisChannelMux;
            mux.* = @intCast(decoded);
        }
    }
    var submaps = [_]VorbisSubmap{.{
        .floor = 0,
        .residue = 0,
    }} ** 16;
    for (submaps[0..submap_count]) |*submap| {
        _ = try reader.read(8);
        const floor = try reader.read(8);
        if (floor >= floor_count)
            return error.InvalidVorbisMappingFloor;
        const residue = try reader.read(8);
        if (residue >= residue_count)
            return error.InvalidVorbisMappingResidue;
        submap.* = .{
            .floor = @intCast(floor),
            .residue = @intCast(residue),
        };
    }
    return .{
        .submap_count = @intCast(submap_count),
        .coupling_step_count = coupling_step_count,
        .coupling_steps = coupling_steps,
        .channel_mux = channel_mux,
        .submaps = submaps,
    };
}

pub fn vorbisILog(value: anytype) u6 {
    var remaining: u64 = @intCast(value);
    var bits: u6 = 0;
    while (remaining != 0) : (remaining >>= 1) bits += 1;
    return bits;
}

pub fn vorbisLookupOneValues(entries: u32, dimensions: u16) u32 {
    if (dimensions == 1) return entries;
    var low: u32 = 1;
    var high: u32 = entries;
    while (low < high) {
        const midpoint = low + (high - low + 1) / 2;
        if (powerAtMost(midpoint, dimensions, entries))
            low = midpoint
        else
            high = midpoint - 1;
    }
    return low;
}

pub fn powerAtMost(base: anytype, exponent: anytype, limit: anytype) bool {
    var product: u64 = 1;
    for (0..exponent) |_| {
        if (base != 0 and product > @as(u64, limit) / base)
            return false;
        product *= base;
    }
    return product <= limit;
}

pub fn pageChecksum(page: []const u8) u32 {
    var crc: u32 = 0;
    for (page, 0..) |byte, index| {
        const value: u8 = if (index >= 22 and index < 26) 0 else byte;
        crc ^= @as(u32, value) << 24;
        for (0..8) |_| {
            crc = if (crc & 0x80000000 != 0)
                (crc << 1) ^ 0x04c11db7
            else
                crc << 1;
        }
    }
    return crc;
}

pub fn encodePage(
    destination: []u8,
    serial_number: u32,
    sequence_number: u32,
    flags: u8,
    granule_position: u64,
    lacing_values: []const u8,
    body: []const u8,
) !usize {
    if (flags & 0xf8 != 0 or
        lacing_values.len > maximum_page_segments)
        return error.InvalidOggPage;
    var expected_body_bytes: usize = 0;
    for (lacing_values) |value|
        expected_body_bytes += value;
    if (expected_body_bytes != body.len)
        return error.InvalidOggPage;
    const header_bytes = std.math.add(
        usize,
        27,
        lacing_values.len,
    ) catch return error.OggSizeOverflow;
    const page_bytes = std.math.add(
        usize,
        header_bytes,
        body.len,
    ) catch return error.OggSizeOverflow;
    if (destination.len < page_bytes)
        return error.OggPageBufferTooSmall;
    const page = destination[0..page_bytes];
    @memset(page[0..27], 0);
    @memcpy(page[0..4], "OggS");
    page[5] = flags;
    std.mem.writeInt(u64, page[6..14], granule_position, .little);
    std.mem.writeInt(u32, page[14..18], serial_number, .little);
    std.mem.writeInt(u32, page[18..22], sequence_number, .little);
    page[26] = @intCast(lacing_values.len);
    @memcpy(page[27..header_bytes], lacing_values);
    @memcpy(page[header_bytes..], body);
    std.mem.writeInt(u32, page[22..26], pageChecksum(page), .little);
    return page_bytes;
}

pub fn readExactAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    destination: []u8,
) !void {
    return file_reader_io.readExactAt(
        io,
        file,
        offset,
        destination,
        error.TruncatedOggPage,
    );
}

pub fn appendTestOggPage(
    destination: []u8,
    offset: usize,
    serial_number: u32,
    sequence_number: u32,
    flags: u8,
    granule_position: u64,
    lacing_values: []const u8,
    body: []const u8,
) !usize {
    var expected_body_bytes: usize = 0;
    for (lacing_values) |value| expected_body_bytes += value;
    if (lacing_values.len > 255 or expected_body_bytes != body.len)
        return error.InvalidTestOggPage;
    const page_bytes = 27 + lacing_values.len + body.len;
    if (page_bytes > destination.len -| offset)
        return error.TestOggOutputTooSmall;
    const page = destination[offset..][0..page_bytes];
    @memset(page[0..27], 0);
    @memcpy(page[0..4], "OggS");
    page[5] = flags;
    std.mem.writeInt(u64, page[6..14], granule_position, .little);
    std.mem.writeInt(u32, page[14..18], serial_number, .little);
    std.mem.writeInt(u32, page[18..22], sequence_number, .little);
    page[26] = @intCast(lacing_values.len);
    @memcpy(page[27..][0..lacing_values.len], lacing_values);
    @memcpy(page[27 + lacing_values.len ..], body);
    std.mem.writeInt(u32, page[22..26], pageChecksum(page), .little);
    return offset + page_bytes;
}

pub const TestVorbisCodebookEncoding = enum {
    unordered,
    unordered_deep,
    ordered,
    ordered_gap,
    sparse,
};

pub const OggFileFaults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    set_length_calls: usize = 0,
    sync_calls: usize = 0,
    maximum_write_bytes: usize = 0,
    fail_write_call: ?usize = null,
    fail_set_length_call: ?usize = null,
    fail_sync_call: ?usize = null,
    partial_write_bytes: usize = 0,

    pub fn operations(self: *@This()) file_writer_io.Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    pub fn clearFailures(self: *@This()) void {
        self.fail_write_call = null;
        self.fail_set_length_call = null;
        self.fail_sync_call = null;
        self.partial_write_bytes = 0;
    }

    fn writeAt(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !usize {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingOggFaultContext,
        ));
        self.write_calls += 1;
        if (self.fail_write_call == self.write_calls) {
            const partial = @min(self.partial_write_bytes, bytes.len);
            if (partial != 0)
                try self.delegate.writeAt(
                    io,
                    file,
                    offset,
                    bytes[0..partial],
                );
            return error.InjectedOggWriteFailure;
        }
        const count = if (self.maximum_write_bytes == 0)
            bytes.len
        else
            @min(self.maximum_write_bytes, bytes.len);
        try self.delegate.writeAt(io, file, offset, bytes[0..count]);
        return count;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingOggFaultContext,
        ));
        self.set_length_calls += 1;
        if (self.fail_set_length_call == self.set_length_calls)
            return error.InjectedOggTruncateFailure;
        try self.delegate.setLength(io, file, length);
    }

    fn sync(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
    ) !void {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingOggFaultContext,
        ));
        self.sync_calls += 1;
        if (self.fail_sync_call == self.sync_calls)
            return error.InjectedOggSyncFailure;
        try self.delegate.sync(io, file);
    }

    const vtable = file_writer_io.Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
        .sync = sync,
    };
};

pub const TestVorbisSetupPacket = struct {
    bytes: []const u8,
    framing_bit: usize,
    mapping_reserved_bit: usize,
    floor_point_bit: ?usize,
};

pub const TestVorbisBitWriter = struct {
    bytes: []u8,
    bit_offset: usize = 0,

    pub fn init(bytes: []u8) TestVorbisBitWriter {
        @memset(bytes, 0);
        return .{ .bytes = bytes };
    }

    pub fn write(
        self: *TestVorbisBitWriter,
        value: u32,
        bit_count: u6,
    ) void {
        for (0..bit_count) |index| {
            const destination_bit = self.bit_offset + index;
            self.bytes[destination_bit / 8] |= @as(u8, @intCast(
                (value >> @intCast(index)) & 1,
            )) << @intCast(destination_bit % 8);
        }
        self.bit_offset += bit_count;
    }
};

pub fn makeTestVorbisSetup(
    destination: []u8,
    encoding: TestVorbisCodebookEncoding,
    rich: bool,
    floor_zero: bool,
) TestVorbisSetupPacket {
    @memcpy(destination[0..7], "\x05vorbis");
    var writer = TestVorbisBitWriter.init(destination[7..]);
    writer.write(0, 8);
    writer.write(0x564342, 24);
    writer.write(1, 16);
    const codebook_entries: u32 = switch (encoding) {
        .unordered_deep, .ordered_gap => 4,
        else => 2,
    };
    writer.write(codebook_entries, 24);
    switch (encoding) {
        .unordered => {
            writer.write(0, 1);
            writer.write(0, 1);
            writer.write(0, 5);
            writer.write(0, 5);
        },
        .unordered_deep => {
            writer.write(0, 1);
            writer.write(0, 1);
            for (0..4) |_| writer.write(1, 5);
        },
        .ordered => {
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(2, 2);
        },
        .ordered_gap => {
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(0, 3);
            writer.write(4, 3);
        },
        .sparse => {
            writer.write(0, 1);
            writer.write(1, 1);
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(0, 1);
        },
    }
    writer.write(1, 4);
    writer.write(0, 32);
    writer.write((@as(u32, 788) << 21) | 1, 32);
    writer.write(1, 4);
    writer.write(0, 1);
    for (0..codebook_entries) |index| {
        writer.write(@intCast(index), 2);
    }

    writer.write(0, 6);
    writer.write(0, 16);

    writer.write(0, 6);
    writer.write(if (floor_zero) 0 else 1, 16);
    var floor_point_bit: ?usize = null;
    if (floor_zero) {
        writer.write(1, 8);
        writer.write(48_000, 16);
        writer.write(64, 16);
        writer.write(8, 6);
        writer.write(60, 8);
        writer.write(0, 4);
        writer.write(0, 8);
    } else if (rich) {
        writer.write(1, 5);
        writer.write(0, 4);
        writer.write(0, 3);
        writer.write(1, 2);
        writer.write(0, 8);
        writer.write(1, 8);
        writer.write(1, 8);
        writer.write(0, 2);
        writer.write(2, 4);
        floor_point_bit = 7 * 8 + writer.bit_offset;
        writer.write(1, 2);
    } else {
        writer.write(0, 5);
        writer.write(0, 2);
        writer.write(0, 4);
    }

    writer.write(0, 6);
    writer.write(0, 16);
    writer.write(0, 24);
    writer.write(0, 24);
    writer.write(0, 24);
    writer.write(0, 6);
    writer.write(0, 8);
    writer.write(if (rich) 1 else 0, 3);
    writer.write(0, 1);
    if (rich) writer.write(0, 8);

    writer.write(0, 6);
    writer.write(0, 16);
    writer.write(if (rich) 1 else 0, 1);
    if (rich) writer.write(1, 4);
    writer.write(if (rich) 1 else 0, 1);
    if (rich) {
        writer.write(0, 8);
        writer.write(0, 1);
        writer.write(1, 1);
    }
    const mapping_reserved_bit = 7 * 8 + writer.bit_offset;
    writer.write(0, 2);
    if (rich) {
        writer.write(0, 4);
        writer.write(1, 4);
    }
    const submap_count: usize = if (rich) 2 else 1;
    for (0..submap_count) |_| {
        writer.write(0, 8);
        writer.write(0, 8);
        writer.write(0, 8);
    }

    writer.write(0, 6);
    writer.write(if (rich) 1 else 0, 1);
    writer.write(0, 16);
    writer.write(0, 16);
    writer.write(0, 8);
    const framing_bit = 7 * 8 + writer.bit_offset;
    writer.write(1, 1);
    return .{
        .bytes = destination[0 .. 7 + (writer.bit_offset + 7) / 8],
        .framing_bit = framing_bit,
        .mapping_reserved_bit = mapping_reserved_bit,
        .floor_point_bit = floor_point_bit,
    };
}

pub fn flipTestBit(bytes: []u8, bit_offset: usize) void {
    bytes[bit_offset / 8] ^= @as(u8, 1) << @intCast(bit_offset % 8);
}
