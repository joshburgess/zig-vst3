const std = @import("std");
const adm = @import("adm.zig");
const adm_time = @import("adm_time.zig");
const xml = @import("xml.zig");

const max_identifier_bytes: usize = 20;
const max_profile_text_bytes: usize = 128;
pub const max_adm_positions: usize = 9;
pub const max_adm_speaker_labels: usize = 16;
pub const max_adm_speaker_label_bytes: usize = 64;
pub const max_adm_matrix_coefficients: usize = 32;

pub const Declaration = struct {
    identifier: adm.Identifier,
    element_name: []const u8,
};

pub const ReferenceKind = enum {
    programme,
    content,
    object,
    complementary_object,
    pack_format,
    matrix_encode_pack,
    matrix_decode_pack,
    matrix_input_pack,
    matrix_output_pack,
    channel_format,
    matrix_output_channel,
    stream_format,
    track_format,
    track_uid,
    alternative_value_set,
    block_format,
};

pub const Reference = struct {
    identifier: ?adm.Identifier,
    kind: ReferenceKind,
    owner: ?adm.Identifier,
    direct_owner: bool,
    tag_target: bool = false,
    virtual_silent_track: bool = false,
};

pub const Profile = struct {
    name: []const u8,
    version: []const u8,
    level: []const u8,
    reference: []const u8,
};

pub const EmissionProfileLevel = enum {
    level_0,
    level_1,
    level_2,
};

const EmissionElementCounts = struct {
    programmes: usize = 0,
    contents: usize = 0,
    objects: usize = 0,
    pack_formats: usize = 0,
    channel_formats: usize = 0,
    track_uids: usize = 0,

    fn exceeds(
        self: EmissionElementCounts,
        limits: EmissionElementCounts,
    ) bool {
        return self.programmes > limits.programmes or
            self.contents > limits.contents or
            self.objects > limits.objects or
            self.pack_formats > limits.pack_formats or
            self.channel_formats > limits.channel_formats or
            self.track_uids > limits.track_uids;
    }
};

const EmissionSubelementOwner = enum {
    programme,
    content,
    object,
};

const EmissionSubelementLimits = struct {
    programme_content: usize,
    programme_labels: usize,
    content_labels: usize,
    object_children: usize,
    complementary_objects: usize,
    alternative_value_sets: usize,
    complementary_labels: usize,
};

const EmissionSubelementCounts = struct {
    programme_content_refs: usize = 0,
    programme_alternative_refs: usize = 0,
    programme_labels: usize = 0,
    content_labels: usize = 0,
    object_children: usize = 0,
    complementary_objects: usize = 0,
    alternative_value_sets: usize = 0,
    complementary_labels: usize = 0,

    fn note(
        self: *EmissionSubelementCounts,
        owner: EmissionSubelementOwner,
        local_name: []const u8,
        limits: EmissionSubelementLimits,
    ) !void {
        const count, const limit = switch (owner) {
            .programme => if (std.mem.eql(
                u8,
                local_name,
                "audioContentIDRef",
            ))
                .{ &self.programme_content_refs, limits.programme_content }
            else if (std.mem.eql(
                u8,
                local_name,
                "alternativeValueSetIDRef",
            ))
                .{ &self.programme_alternative_refs, limits.programme_content }
            else if (std.mem.eql(
                u8,
                local_name,
                "audioProgrammeLabel",
            ))
                .{ &self.programme_labels, limits.programme_labels }
            else
                return,
            .content => if (std.mem.eql(
                u8,
                local_name,
                "audioContentLabel",
            ))
                .{ &self.content_labels, limits.content_labels }
            else
                return,
            .object => if (std.mem.eql(
                u8,
                local_name,
                "audioObjectIDRef",
            ))
                .{ &self.object_children, limits.object_children }
            else if (std.mem.eql(
                u8,
                local_name,
                "audioComplementaryObjectIDRef",
            ))
                .{ &self.complementary_objects, limits.complementary_objects }
            else if (std.mem.eql(
                u8,
                local_name,
                "alternativeValueSet",
            ))
                .{ &self.alternative_value_sets, limits.alternative_value_sets }
            else if (std.mem.eql(
                u8,
                local_name,
                "audioComplementaryObjectGroupLabel",
            ))
                .{ &self.complementary_labels, limits.complementary_labels }
            else
                return,
        };
        count.* += 1;
        if (count.* > limit)
            return error.AdmEmissionProfileSubelementLimitExceeded;
    }
};

fn emissionProfileLimits(
    level: EmissionProfileLevel,
) EmissionElementCounts {
    return switch (level) {
        .level_0 => .{
            .programmes = std.math.maxInt(usize),
            .contents = std.math.maxInt(usize),
            .objects = std.math.maxInt(usize),
            .pack_formats = std.math.maxInt(usize),
            .channel_formats = std.math.maxInt(usize),
            .track_uids = std.math.maxInt(usize),
        },
        .level_1 => .{
            .programmes = 8,
            .contents = 16,
            .objects = 48,
            .pack_formats = 32,
            .channel_formats = 32,
            .track_uids = 32,
        },
        .level_2 => .{
            .programmes = 16,
            .contents = 28,
            .objects = 84,
            .pack_formats = 56,
            .channel_formats = 56,
            .track_uids = 56,
        },
    };
}

fn emissionSubelementLimits(
    level: EmissionProfileLevel,
) EmissionSubelementLimits {
    const unlimited = std.math.maxInt(usize);
    return switch (level) {
        .level_0 => .{
            .programme_content = unlimited,
            .programme_labels = unlimited,
            .content_labels = unlimited,
            .object_children = unlimited,
            .complementary_objects = unlimited,
            .alternative_value_sets = unlimited,
            .complementary_labels = unlimited,
        },
        .level_1 => .{
            .programme_content = 16,
            .programme_labels = 4,
            .content_labels = 4,
            .object_children = 16,
            .complementary_objects = 15,
            .alternative_value_sets = 8,
            .complementary_labels = 4,
        },
        .level_2 => .{
            .programme_content = 28,
            .programme_labels = 8,
            .content_labels = 8,
            .object_children = 28,
            .complementary_objects = 27,
            .alternative_value_sets = 16,
            .complementary_labels = 8,
        },
    };
}

fn profilesEqual(left: Profile, right: Profile) bool {
    return std.mem.eql(u8, left.name, right.name) and
        std.mem.eql(u8, left.version, right.version) and
        std.mem.eql(u8, left.level, right.level) and
        std.mem.eql(u8, left.reference, right.reference);
}

pub const Tag = struct {
    group_index: usize,
    value: []const u8,
    class: ?[]const u8,
};

pub const TagTarget = struct {
    group_index: usize,
    identifier: adm.Identifier,
};

pub const TagItem = union(enum) {
    tag: Tag,
    target: TagTarget,
};

pub const GainUnit = enum {
    linear,
    decibels,
};

pub const Gain = struct {
    value: f64 = 1.0,
    unit: GainUnit = .linear,
};

pub const JumpPosition = struct {
    enabled: bool = false,
    interpolation_length: ?adm_time.Value = null,
};

pub const HeadphoneVirtualise = struct {
    bypass: bool = false,
    direct_to_reverberant_ratio_db: f64 = 130.0,
};

pub const Coordinate = enum {
    azimuth,
    elevation,
    distance,
    x,
    y,
    z,
};

pub const PositionBound = enum {
    exact,
    minimum,
    maximum,
};

pub const ScreenEdge = enum {
    left,
    right,
    top,
    bottom,
};

pub const Position = struct {
    coordinate: Coordinate,
    bound: PositionBound,
    value: f64,
    screen_edge_lock: ?ScreenEdge = null,
};

pub const SpeakerLabel = struct {
    bytes: [max_adm_speaker_label_bytes]u8 = undefined,
    len: u8 = 0,

    pub fn value(self: *const SpeakerLabel) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const ObjectDivergence = struct {
    value: f64 = 0.0,
    azimuth_range: ?f64 = null,
    position_range: ?f64 = null,
};

pub const ChannelLock = struct {
    enabled: bool = false,
    max_distance: ?f64 = null,
};

pub const HoaNormalization = enum {
    n3d,
    sn3d,
    fuma,
};

pub const AdmText = struct {
    bytes: [max_profile_text_bytes]u8 = undefined,
    len: u8 = 0,

    pub fn value(self: *const AdmText) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const MatrixCoefficient = struct {
    channel_identifier_bytes: [max_identifier_bytes]u8 = undefined,
    channel_identifier_len: u8,
    gain: Gain = .{},
    gain_variable: ?AdmText = null,
    phase_degrees: f64 = 0.0,
    phase_variable: ?AdmText = null,
    delay_milliseconds: f64 = 0.0,
    delay_variable: ?AdmText = null,

    pub fn channelIdentifier(
        self: *const MatrixCoefficient,
    ) !adm.Identifier {
        return adm.Identifier.parse(
            self.channel_identifier_bytes[0..self.channel_identifier_len],
        );
    }
};

pub const BlockFormat = struct {
    identifier: adm.Identifier,
    channel_identifier: adm.Identifier,
    channel_name: ?AdmText,
    rtime: adm_time.Value,
    rtime_explicit: bool,
    duration: ?adm_time.Value,
    gain: Gain = .{},
    importance: u8 = 10,
    jump_position: JumpPosition = .{},
    head_locked: bool = false,
    headphone_virtualise: HeadphoneVirtualise = .{},
    cartesian: bool = false,
    positions: [max_adm_positions]Position = undefined,
    position_count: usize = 0,
    speaker_labels: [max_adm_speaker_labels]SpeakerLabel = undefined,
    speaker_label_count: usize = 0,
    width: f64 = 0.0,
    height: f64 = 0.0,
    depth: f64 = 0.0,
    diffuse: f64 = 0.0,
    object_divergence: ObjectDivergence = .{},
    channel_lock: ChannelLock = .{},
    screen_ref: bool = false,
    hoa_equation: ?AdmText = null,
    hoa_order: ?u32 = null,
    hoa_degree: ?i32 = null,
    hoa_normalization: HoaNormalization = .sn3d,
    hoa_nfc_reference_distance: f64 = 0.0,
    matrix_coefficients: [max_adm_matrix_coefficients]MatrixCoefficient =
        undefined,
    matrix_coefficient_count: usize = 0,

    pub fn positionSlice(self: *const BlockFormat) []const Position {
        return self.positions[0..self.position_count];
    }

    pub fn speakerLabelSlice(
        self: *const BlockFormat,
    ) []const SpeakerLabel {
        return self.speaker_labels[0..self.speaker_label_count];
    }

    pub fn matrixCoefficientSlice(
        self: *const BlockFormat,
    ) []const MatrixCoefficient {
        return self.matrix_coefficients[0..self.matrix_coefficient_count];
    }
};

pub const Document = struct {
    xml_document: xml.Document,
    declaration_count: usize,
    reference_count: usize,
    profile_count: usize,
    tag_group_count: usize,
    tag_count: usize,
    tag_target_count: usize,
    block_count: usize,

    pub fn init(bytes: []const u8) !Document {
        const xml_document = try xml.Document.init(bytes);
        var afe_count: usize = 0;
        var events = xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        afe_count += 1;
                    }
                },
                else => {},
            }
        }
        if (afe_count == 0) return error.MissingAudioFormatExtended;
        if (afe_count != 1) return error.MultipleAudioFormatExtended;

        var document = Document{
            .xml_document = xml_document,
            .declaration_count = 0,
            .reference_count = 0,
            .profile_count = 0,
            .tag_group_count = 0,
            .tag_count = 0,
            .tag_target_count = 0,
            .block_count = 0,
        };
        var declaration_iterator = document.declarations();
        while (try declaration_iterator.next()) |_| {
            document.declaration_count += 1;
        }
        var profile_iterator = document.profiles();
        while (try profile_iterator.next()) |_| {
            document.profile_count += 1;
        }
        var tag_iterator = document.tags();
        while (try tag_iterator.next()) |item| {
            switch (item) {
                .tag => document.tag_count += 1,
                .target => document.tag_target_count += 1,
            }
        }
        document.tag_group_count = tag_iterator.group_count;
        var reference_iterator = document.references();
        while (try reference_iterator.next()) |_| {
            document.reference_count += 1;
        }
        var block_iterator = document.blocks();
        while (try block_iterator.next()) |_| {
            document.block_count += 1;
        }
        try document.validateDuplicateDeclarations();
        try document.validateReferences();
        try document.validateCardinalities();
        try document.validateBlockSequences();
        return document;
    }

    pub fn declarations(self: Document) DeclarationIterator {
        return DeclarationIterator.init(self);
    }

    pub fn references(self: Document) ReferenceIterator {
        return ReferenceIterator.init(self);
    }

    pub fn profiles(self: Document) ProfileIterator {
        return ProfileIterator.init(self);
    }

    pub fn blocks(self: Document) BlockIterator {
        return BlockIterator.init(self);
    }

    pub fn tags(self: Document) TagIterator {
        return TagIterator.init(self);
    }

    pub fn contains(self: Document, wanted: adm.Identifier) !bool {
        var iterator = self.declarations();
        while (try iterator.next()) |declaration| {
            if (declaration.identifier.eql(wanted)) return true;
        }
        return false;
    }

    pub fn validateReferences(self: Document) !void {
        var iterator = self.references();
        while (try iterator.next()) |reference| {
            if (reference.virtual_silent_track) {
                const owner = reference.owner orelse
                    return error.InvalidAdmReferenceOwner;
                if (owner.kind != .object)
                    return error.InvalidAdmReferenceOwner;
                continue;
            }
            const identifier = reference.identifier orelse
                return error.InvalidAdmXmlReference;
            try validateReferenceRelationship(reference, identifier);
            if (reference.owner) |owner| {
                if (owner.eql(identifier) and
                    (identifier.kind == .object or
                        identifier.kind == .pack_format))
                {
                    return error.SelfReferentialAdmDefinition;
                }
            }
            if (identifier.kind == .track_uid or
                identifier.isCommonDefinition())
            {
                continue;
            }
            if (!try self.contains(identifier))
                return error.UnresolvedAdmReference;
            if (reference.kind == .stream_format) {
                const owner = reference.owner orelse continue;
                if (owner.kind == .track_format and
                    !try self.hasReciprocalTrackReference(
                        identifier,
                        owner,
                    ))
                {
                    return error.MissingReciprocalAdmTrackReference;
                }
            }
        }
    }

    pub fn validateChannelAllocation(
        self: Document,
        allocation: adm.ChannelAllocation,
    ) !void {
        try allocation.validate();
        try self.validateChannelEntries(.{ .allocation = allocation });
    }

    pub fn validateChannelAllocationView(
        self: Document,
        allocation: adm.View,
    ) !void {
        try self.validateChannelEntries(.{ .view = allocation });
    }

    /// Identifies the declared BS.2168 version and level.
    /// This does not establish document conformance.
    pub fn emissionProfileLevel(
        self: Document,
    ) !EmissionProfileLevel {
        try self.validateUniqueProfiles();
        var result: ?EmissionProfileLevel = null;
        var profile_iterator = self.profiles();
        while (try profile_iterator.next()) |profile| {
            if (!std.mem.eql(u8, profile.reference, "ITU-R BS.2168"))
                continue;
            if (!std.mem.eql(
                u8,
                profile.name,
                "Advanced sound system: ADM and S-ADM profile for emission",
            )) {
                return error.InvalidAdmEmissionProfileName;
            }
            if (!std.mem.eql(u8, profile.version, "1"))
                return error.UnsupportedAdmEmissionProfileVersion;
            const level: EmissionProfileLevel =
                if (std.mem.eql(u8, profile.level, "0"))
                    .level_0
                else if (std.mem.eql(u8, profile.level, "1"))
                    .level_1
                else if (std.mem.eql(u8, profile.level, "2"))
                    .level_2
                else
                    return error.UnsupportedAdmEmissionProfileLevel;
            if (result != null)
                return error.DuplicateAdmEmissionProfile;
            result = level;
        }
        return result orelse error.MissingAdmEmissionProfile;
    }

    /// Validates the supported BS.2168 document and element-count subset.
    /// Other profile requirements require separate validation.
    pub fn validateEmissionProfileElementLimits(
        self: Document,
    ) !EmissionProfileLevel {
        try self.validateEmissionProfileDocumentVersion();
        const level = try self.emissionProfileLevel();
        const limits = emissionProfileLimits(level);
        var counts = EmissionElementCounts{};
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            switch (declaration.identifier.kind) {
                .programme => counts.programmes += 1,
                .content => counts.contents += 1,
                .object => counts.objects += 1,
                .pack_format => {
                    const type_label = declaration.identifier.typeLabel() orelse
                        return error.InvalidAdmEmissionProfileFormat;
                    if (type_label != 0x0002 and type_label != 0x0003)
                        return error.InvalidAdmEmissionProfileFormat;
                    if (type_label != 0x0002) counts.pack_formats += 1;
                },
                .channel_format => {
                    const type_label = declaration.identifier.typeLabel() orelse
                        return error.InvalidAdmEmissionProfileFormat;
                    if (type_label != 0x0002 and type_label != 0x0003)
                        return error.InvalidAdmEmissionProfileFormat;
                    if (type_label != 0x0002) counts.channel_formats += 1;
                },
                .track_uid => counts.track_uids += 1,
                .track_format, .stream_format => return error.ForbiddenAdmEmissionProfileFormat,
                .alternative_value_set, .block_format => {},
            }
        }
        if (counts.programmes == 0 or
            counts.contents == 0 or
            counts.objects == 0 or
            counts.track_uids == 0)
        {
            return error.MissingAdmEmissionProfileElement;
        }
        if (counts.exceeds(limits))
            return error.AdmEmissionProfileElementLimitExceeded;
        return level;
    }

    /// Validates the profile level's maximum occurrences for direct
    /// programme, content, and object children.
    pub fn validateEmissionProfileSubelementLimits(
        self: Document,
    ) !void {
        const level = try self.validateEmissionProfileElementLimits();
        const limits = emissionSubelementLimits(level);
        var owner: [xml.max_depth]?EmissionSubelementOwner =
            @splat(null);
        var owner_depth: [xml.max_depth]?usize = @splat(null);
        var counts: [xml.max_depth]EmissionSubelementCounts =
            @splat(.{});
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (element.depth != 0) {
                        owner[element.depth] = owner[element.depth - 1];
                        owner_depth[element.depth] =
                            owner_depth[element.depth - 1];
                    }
                    if (owner[element.depth]) |current_owner| {
                        const current_depth =
                            owner_depth[element.depth] orelse
                            return error.InvalidAdmEmissionProfileOwnerState;
                        if (current_depth + 1 == element.depth) {
                            try counts[current_depth].note(
                                current_owner,
                                element.localName(),
                                limits,
                            );
                        }
                    }
                    const next_owner: ?EmissionSubelementOwner =
                        if (std.mem.eql(
                            u8,
                            element.localName(),
                            "audioProgramme",
                        ))
                            .programme
                        else if (std.mem.eql(
                            u8,
                            element.localName(),
                            "audioContent",
                        ))
                            .content
                        else if (std.mem.eql(
                            u8,
                            element.localName(),
                            "audioObject",
                        ))
                            .object
                        else
                            null;
                    if (next_owner) |value| {
                        owner[element.depth] = value;
                        owner_depth[element.depth] = element.depth;
                        counts[element.depth] = .{};
                    }
                },
                else => {},
            }
        }
    }

    /// Validates the supported BS.2168 identifier and content-link subset.
    /// Other profile relationships require separate validation.
    pub fn validateEmissionProfileIdentifiers(self: Document) !void {
        _ = try self.validateEmissionProfileElementLimits();
        var expected_track_uid: u32 = 1;
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const identifier = declaration.identifier;
            switch (identifier.kind) {
                .programme, .object, .alternative_value_set => {
                    if (identifier.primary < 0x1001)
                        return error.InvalidAdmEmissionProfileIdentifier;
                },
                .content => {
                    if (identifier.primary < 0x1001)
                        return error.InvalidAdmEmissionProfileIdentifier;
                    try self.validateEmissionContentReference(identifier);
                },
                .pack_format, .channel_format => {
                    const index = identifier.definitionIndex() orelse
                        return error.InvalidAdmEmissionProfileIdentifier;
                    if (index < 0x1001)
                        return error.InvalidAdmEmissionProfileIdentifier;
                },
                .block_format => {
                    const index = identifier.definitionIndex() orelse
                        return error.InvalidAdmEmissionProfileIdentifier;
                    if (index < 0x1001)
                        return error.InvalidAdmEmissionProfileIdentifier;
                    if (identifier.typeLabel() == 0x0002 and
                        identifier.secondary != 1)
                    {
                        return error.InvalidAdmEmissionProfileIdentifier;
                    }
                },
                .track_uid => {
                    if (identifier.primary != expected_track_uid)
                        return error.InvalidAdmEmissionProfileTrackUidSequence;
                    expected_track_uid = std.math.add(
                        u32,
                        expected_track_uid,
                        1,
                    ) catch return error.InvalidAdmEmissionProfileTrackUidSequence;
                },
                .track_format, .stream_format => return error.ForbiddenAdmEmissionProfileFormat,
            }
        }
        try self.validateEmissionAlternativeValueSetIdentifiers();
    }

    fn validateEmissionContentReference(
        self: Document,
        content: adm.Identifier,
    ) !void {
        var matching_references: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or reference.kind != .object)
                continue;
            const owner = reference.owner orelse continue;
            if (!owner.eql(content)) continue;
            const object = reference.identifier orelse
                return error.InvalidAdmEmissionProfileContentReference;
            matching_references += 1;
            if (object.primary != content.primary)
                return error.InvalidAdmEmissionProfileContentReference;
        }
        if (matching_references != 1)
            return error.InvalidAdmEmissionProfileContentReference;
    }

    fn validateEmissionAlternativeValueSetIdentifiers(
        self: Document,
    ) !void {
        var object_primary: [xml.max_depth]?u32 = @splat(null);
        var object_depth: [xml.max_depth]?usize = @splat(null);
        var next_sequence: [xml.max_depth]u64 = @splat(1);
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (element.depth != 0) {
                        object_primary[element.depth] =
                            object_primary[element.depth - 1];
                        object_depth[element.depth] =
                            object_depth[element.depth - 1];
                    }
                    if (std.mem.eql(u8, element.localName(), "audioObject")) {
                        const encoded =
                            try element.attribute("audioObjectID") orelse
                            return error.MissingAdmIdentifier;
                        var storage: [max_identifier_bytes]u8 = undefined;
                        const raw = try xml.decodeContent(&storage, encoded);
                        const identifier = try adm.Identifier.parse(raw);
                        if (identifier.kind != .object)
                            return error.InvalidAdmDeclarationKind;
                        object_primary[element.depth] = identifier.primary;
                        object_depth[element.depth] = element.depth;
                        next_sequence[element.depth] = 1;
                        continue;
                    }
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "alternativeValueSet",
                    )) {
                        continue;
                    }
                    const parent_depth = object_depth[element.depth] orelse
                        return error.InvalidAdmEmissionAlternativeValueSetOwner;
                    if (parent_depth + 1 != element.depth)
                        return error.InvalidAdmEmissionAlternativeValueSetOwner;
                    const parent_primary =
                        object_primary[element.depth] orelse
                        return error.InvalidAdmEmissionAlternativeValueSetOwner;
                    const encoded =
                        try element.attribute("alternativeValueSetID") orelse
                        return error.MissingAdmIdentifier;
                    var storage: [max_identifier_bytes]u8 = undefined;
                    const raw = try xml.decodeContent(&storage, encoded);
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind != .alternative_value_set)
                        return error.InvalidAdmDeclarationKind;
                    const sequence = identifier.secondary orelse
                        return error.InvalidAdmEmissionProfileIdentifier;
                    if (identifier.primary != parent_primary or
                        @as(u64, sequence) != next_sequence[parent_depth])
                    {
                        return error.InvalidAdmEmissionProfileIdentifier;
                    }
                    next_sequence[parent_depth] += 1;
                },
                else => {},
            }
        }
    }

    fn validateEmissionProfileDocumentVersion(self: Document) !void {
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        continue;
                    }
                    const encoded = try element.attribute("version") orelse
                        return error.MissingAdmEmissionProfileDocumentVersion;
                    var storage: [max_profile_text_bytes]u8 = undefined;
                    const version = try xml.decodeContent(&storage, encoded);
                    if (!std.mem.eql(u8, version, "ITU-R_BS.2076-3"))
                        return error.UnsupportedAdmEmissionProfileDocumentVersion;
                    return;
                },
                else => {},
            }
        }
        return error.MissingAudioFormatExtended;
    }

    fn validateDuplicateDeclarations(self: Document) !void {
        var outer = self.declarations();
        var index: usize = 0;
        while (try outer.next()) |declaration| : (index += 1) {
            var inner = self.declarations();
            var previous_index: usize = 0;
            while (previous_index < index) : (previous_index += 1) {
                const previous = (try inner.next()) orelse
                    return error.InvalidAdmDeclarationIteration;
                if (previous.identifier.eql(declaration.identifier))
                    return error.DuplicateAdmDeclaration;
            }
        }
    }

    fn validateUniqueProfiles(self: Document) !void {
        var outer = self.profiles();
        var index: usize = 0;
        while (try outer.next()) |profile| : (index += 1) {
            var inner = self.profiles();
            var previous_index: usize = 0;
            while (previous_index < index) : (previous_index += 1) {
                const previous = (try inner.next()) orelse
                    return error.InvalidAdmProfileIteration;
                if (profilesEqual(profile, previous))
                    return error.DuplicateAdmProfile;
            }
        }
    }

    fn validateCardinalities(self: Document) !void {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind != .stream_format and
                declaration.identifier.kind != .track_format and
                declaration.identifier.kind != .track_uid and
                declaration.identifier.kind != .block_format)
            {
                continue;
            }
            var channel_references: usize = 0;
            var pack_references: usize = 0;
            var stream_references: usize = 0;
            var track_references: usize = 0;
            var matrix_output_references: usize = 0;
            var reference_iterator = self.references();
            while (try reference_iterator.next()) |reference| {
                const owner = reference.owner orelse continue;
                if (!reference.direct_owner or
                    !owner.eql(declaration.identifier))
                {
                    continue;
                }
                switch (reference.kind) {
                    .channel_format => channel_references += 1,
                    .pack_format => pack_references += 1,
                    .stream_format => stream_references += 1,
                    .track_format => track_references += 1,
                    .matrix_output_channel => matrix_output_references += 1,
                    else => {},
                }
            }
            switch (declaration.identifier.kind) {
                .stream_format => {
                    if (channel_references > 1 or pack_references > 1) {
                        return error.TooManyAdmStreamReferences;
                    }
                    if (channel_references != 0 and pack_references != 0)
                        return error.AmbiguousAdmStreamFormat;
                },
                .track_format => {
                    if (stream_references > 1)
                        return error.TooManyAdmTrackStreamReferences;
                },
                .track_uid => {
                    if (track_references > 1 or channel_references > 1)
                        return error.TooManyAdmTrackReferences;
                    if (track_references != 0 and channel_references != 0)
                        return error.AmbiguousAdmTrackReference;
                    if (pack_references > 1)
                        return error.TooManyAdmPackReferences;
                },
                .block_format => {
                    if (matrix_output_references > 1)
                        return error.TooManyAdmMatrixOutputReferences;
                },
                else => return error.InvalidAdmCardinalityState,
            }
        }
    }

    fn hasReciprocalTrackReference(
        self: Document,
        stream: adm.Identifier,
        track: adm.Identifier,
    ) !bool {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (reference.kind != .track_format or
                !reference.direct_owner)
            {
                continue;
            }
            const owner = reference.owner orelse continue;
            const identifier = reference.identifier orelse continue;
            if (owner.eql(stream) and identifier.eql(track)) return true;
        }
        return false;
    }

    fn validateBlockSequences(self: Document) !void {
        var block_iterator = self.blocks();
        while (try block_iterator.next()) |block| {
            if (block.identifier.primary != block.channel_identifier.primary)
                return error.AdmBlockIdentifierMismatch;
            for (block.matrixCoefficientSlice()) |coefficient| {
                const identifier = try coefficient.channelIdentifier();
                if (!identifier.isCommonDefinition() and
                    !try self.contains(identifier))
                {
                    return error.UnresolvedAdmReference;
                }
            }
            var channel_block_count: usize = 0;
            var preceding_blocks: usize = 0;
            var all_blocks = self.blocks();
            while (try all_blocks.next()) |candidate| {
                if (!candidate.channel_identifier.eql(
                    block.channel_identifier,
                )) {
                    continue;
                }
                channel_block_count += 1;
                if (candidate.identifier.eql(block.identifier)) break;
                preceding_blocks += 1;
            }
            const sequence = block.identifier.secondary orelse
                return error.InvalidAdmBlockIdentifier;
            if (sequence != @as(u32, @intCast(preceding_blocks + 1)))
                return error.InvalidAdmBlockSequence;

            if (channel_block_count == 1) {
                var remainder = self.blocks();
                while (try remainder.next()) |candidate| {
                    if (candidate.channel_identifier.eql(
                        block.channel_identifier,
                    ) and !candidate.identifier.eql(block.identifier)) {
                        channel_block_count += 1;
                        break;
                    }
                }
            }
            if (channel_block_count > 1 and
                (!block.rtime_explicit or block.duration == null))
            {
                return error.MissingDynamicAdmBlockTiming;
            }
        }
    }

    fn validateChannelEntries(
        self: Document,
        entries: ChannelEntries,
    ) !void {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (reference.kind != .track_uid or
                reference.virtual_silent_track)
            {
                continue;
            }
            const identifier = reference.identifier orelse
                return error.InvalidAdmXmlReference;
            if (!try entries.containsUid(identifier))
                return error.AdmTrackUidMissingFromChannelAllocation;
        }

        var index: usize = 0;
        while (index < entries.count()) : (index += 1) {
            const entry = try entries.entry(index);
            const uid = try adm.Identifier.parse(entry.uid);
            const track_reference = try channelTrackReference(entry.track_ref);
            if (track_reference.requiresLocalDefinition() and
                !try self.contains(track_reference))
            {
                return error.AdmChannelReferenceMissingFromXml;
            }
            const pack_reference = if (entry.pack_ref) |raw|
                try adm.Identifier.parse(raw)
            else
                null;
            if (pack_reference) |identifier| {
                if (identifier.requiresLocalDefinition() and
                    !try self.contains(identifier))
                {
                    return error.AdmPackReferenceMissingFromXml;
                }
            }
            try self.validateTrackUidReferences(
                uid,
                track_reference,
                pack_reference,
            );
        }
    }

    fn validateTrackUidReferences(
        self: Document,
        uid: adm.Identifier,
        track_reference: adm.Identifier,
        pack_reference: ?adm.Identifier,
    ) !void {
        if (!try self.contains(uid)) return;
        var found_track = false;
        var found_pack = false;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!owner.eql(uid) or !reference.direct_owner) continue;
            const identifier = reference.identifier orelse continue;
            switch (reference.kind) {
                .track_format, .channel_format => {
                    if (found_track) return error.DuplicateAdmTrackReference;
                    if (!identifier.eql(track_reference))
                        return error.AdmTrackReferenceMismatch;
                    found_track = true;
                },
                .pack_format => {
                    if (found_pack) return error.DuplicateAdmPackReference;
                    const expected = pack_reference orelse
                        return error.AdmPackReferenceMismatch;
                    if (!identifier.eql(expected))
                        return error.AdmPackReferenceMismatch;
                    found_pack = true;
                },
                else => {},
            }
        }
        if (pack_reference == null and found_pack)
            return error.AdmPackReferenceMismatch;
    }
};

pub const ProfileIterator = struct {
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    profile_list_depth: ?usize = null,
    profile_list_seen: bool = false,
    profiles_in_list: usize = 0,
    name_storage: [max_profile_text_bytes]u8 = undefined,
    version_storage: [max_profile_text_bytes]u8 = undefined,
    level_storage: [max_profile_text_bytes]u8 = undefined,
    reference_storage: [max_profile_text_bytes]u8 = undefined,

    fn init(document: Document) ProfileIterator {
        return .{ .events = document.xml_document.iterator() };
    }

    /// Returned fields remain valid until the next iterator call.
    pub fn next(self: *ProfileIterator) !?Profile {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    if (!insideAfe(self.afe_depth, element.depth)) continue;
                    if (std.mem.eql(u8, element.localName(), "profileList")) {
                        const afe_depth = self.afe_depth orelse
                            return error.InvalidAdmProfileListOwner;
                        if (element.depth != afe_depth + 1)
                            return error.InvalidAdmProfileListOwner;
                        if (self.profile_list_seen)
                            return error.MultipleAdmProfileLists;
                        if (element.self_closing)
                            return error.EmptyAdmProfileList;
                        self.profile_list_seen = true;
                        self.profile_list_depth = element.depth;
                        self.profiles_in_list = 0;
                        continue;
                    }
                    if (!std.mem.eql(u8, element.localName(), "profile"))
                        continue;
                    const list_depth = self.profile_list_depth orelse
                        return error.InvalidAdmProfileOwner;
                    if (element.depth != list_depth + 1)
                        return error.InvalidAdmProfileOwner;
                    if (element.self_closing)
                        return error.EmptyAdmProfileReference;
                    const profile = try self.readProfile(element);
                    self.profiles_in_list += 1;
                    return profile;
                },
                .end => |element| {
                    if (self.profile_list_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "profileList"))
                    {
                        if (self.profiles_in_list == 0)
                            return error.EmptyAdmProfileList;
                        self.profile_list_depth = null;
                    }
                    if (self.afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn readProfile(
        self: *ProfileIterator,
        start: xml.StartElement,
    ) !Profile {
        const encoded_name = try start.attribute("profileName") orelse
            return error.MissingAdmProfileName;
        const encoded_version = try start.attribute("profileVersion") orelse
            return error.MissingAdmProfileVersion;
        const encoded_level = try start.attribute("profileLevel") orelse
            return error.MissingAdmProfileLevel;
        const name = try decodeNonEmptyProfileValue(
            &self.name_storage,
            encoded_name,
        );
        const version = try decodeNonEmptyProfileValue(
            &self.version_storage,
            encoded_version,
        );
        const level = try decodeNonEmptyProfileValue(
            &self.level_storage,
            encoded_level,
        );

        var encoded_reference: [max_profile_text_bytes * 5]u8 = undefined;
        var encoded_bytes: usize = 0;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    const next_offset = std.math.add(
                        usize,
                        encoded_bytes,
                        text.bytes.len,
                    ) catch return error.AdmProfileValueTooLong;
                    if (next_offset > encoded_reference.len)
                        return error.AdmProfileValueTooLong;
                    @memcpy(
                        encoded_reference[encoded_bytes..next_offset],
                        text.bytes,
                    );
                    encoded_bytes = next_offset;
                },
                .start => return error.NestedAdmProfileReference,
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmProfile;
                    }
                    const encoded = std.mem.trim(
                        u8,
                        encoded_reference[0..encoded_bytes],
                        " \t\r\n",
                    );
                    const reference = try decodeNonEmptyProfileValue(
                        &self.reference_storage,
                        encoded,
                    );
                    return .{
                        .name = name,
                        .version = version,
                        .level = level,
                        .reference = reference,
                    };
                },
            }
        }
        return error.UnclosedAdmProfile;
    }
};

pub const TagIterator = struct {
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    tag_list_depth: ?usize = null,
    tag_group_depth: ?usize = null,
    tag_list_seen: bool = false,
    group_count: usize = 0,
    tags_in_group: usize = 0,
    targets_in_group: usize = 0,
    value_storage: [max_profile_text_bytes]u8 = undefined,
    class_storage: [max_profile_text_bytes]u8 = undefined,
    identifier_storage: [max_identifier_bytes]u8 = undefined,

    fn init(document: Document) TagIterator {
        return .{ .events = document.xml_document.iterator() };
    }

    /// Returned text and identifiers remain valid until the next iterator call.
    pub fn next(self: *TagIterator) !?TagItem {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    if (!insideAfe(self.afe_depth, element.depth)) continue;
                    if (std.mem.eql(u8, element.localName(), "tagList")) {
                        const afe_depth = self.afe_depth orelse
                            return error.InvalidAdmTagListOwner;
                        if (element.depth != afe_depth + 1)
                            return error.InvalidAdmTagListOwner;
                        if (self.tag_list_seen)
                            return error.MultipleAdmTagLists;
                        if (element.self_closing)
                            return error.EmptyAdmTagList;
                        self.tag_list_seen = true;
                        self.tag_list_depth = element.depth;
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "tagGroup")) {
                        const list_depth = self.tag_list_depth orelse
                            return error.InvalidAdmTagGroupOwner;
                        if (element.depth != list_depth + 1 or
                            self.tag_group_depth != null)
                        {
                            return error.InvalidAdmTagGroupOwner;
                        }
                        if (element.self_closing)
                            return error.EmptyAdmTagGroup;
                        self.tag_group_depth = element.depth;
                        self.tags_in_group = 0;
                        self.targets_in_group = 0;
                        continue;
                    }
                    const group_depth = self.tag_group_depth;
                    if (std.mem.eql(u8, element.localName(), "tag")) {
                        const depth = group_depth orelse
                            return error.InvalidAdmTagOwner;
                        if (element.depth != depth + 1)
                            return error.InvalidAdmTagOwner;
                        const encoded_class = try element.attribute("class");
                        const class = if (encoded_class) |encoded|
                            try decodeOptionalTagValue(
                                &self.class_storage,
                                encoded,
                            )
                        else
                            null;
                        const value = try self.readText(element);
                        self.tags_in_group += 1;
                        return .{ .tag = .{
                            .group_index = self.group_count,
                            .value = value,
                            .class = class,
                        } };
                    }
                    const target_kind = tagTargetKind(
                        element.localName(),
                    ) orelse continue;
                    if (self.tag_list_depth == null) continue;
                    const depth = group_depth orelse
                        return error.InvalidAdmTagTargetOwner;
                    if (element.depth != depth + 1)
                        return error.InvalidAdmTagTargetOwner;
                    const raw = try self.readText(element);
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind != target_kind)
                        return error.InvalidAdmTagTargetKind;
                    @memcpy(
                        self.identifier_storage[0..raw.len],
                        raw,
                    );
                    self.targets_in_group += 1;
                    return .{ .target = .{
                        .group_index = self.group_count,
                        .identifier = try adm.Identifier.parse(
                            self.identifier_storage[0..raw.len],
                        ),
                    } };
                },
                .end => |element| {
                    if (self.tag_group_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "tagGroup"))
                    {
                        if (self.tags_in_group == 0)
                            return error.AdmTagGroupMissingTag;
                        if (self.targets_in_group == 0)
                            return error.AdmTagGroupMissingTarget;
                        self.tag_group_depth = null;
                        self.group_count += 1;
                    }
                    if (self.tag_list_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "tagList"))
                    {
                        if (self.group_count == 0)
                            return error.EmptyAdmTagList;
                        self.tag_list_depth = null;
                    }
                    if (self.afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn readText(
        self: *TagIterator,
        start: xml.StartElement,
    ) ![]const u8 {
        if (start.self_closing) return error.EmptyAdmTagValue;
        var encoded_storage: [max_profile_text_bytes * 5]u8 = undefined;
        var encoded_bytes: usize = 0;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    const next_offset = std.math.add(
                        usize,
                        encoded_bytes,
                        text.bytes.len,
                    ) catch return error.AdmTagValueTooLong;
                    if (next_offset > encoded_storage.len)
                        return error.AdmTagValueTooLong;
                    @memcpy(
                        encoded_storage[encoded_bytes..next_offset],
                        text.bytes,
                    );
                    encoded_bytes = next_offset;
                },
                .start => return error.NestedAdmTagValue,
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmTagValue;
                    }
                    const encoded = std.mem.trim(
                        u8,
                        encoded_storage[0..encoded_bytes],
                        " \t\r\n",
                    );
                    return decodeRequiredTagValue(
                        &self.value_storage,
                        encoded,
                    );
                },
            }
        }
        return error.UnclosedAdmTagValue;
    }
};

pub const BlockIterator = struct {
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    channel_identifier: ?adm.Identifier = null,
    channel_name: ?AdmText = null,
    channel_depth: ?usize = null,
    channel_storage: [max_identifier_bytes]u8 = undefined,
    identifier_storage: [max_identifier_bytes]u8 = undefined,
    value_storage: [max_profile_text_bytes]u8 = undefined,

    fn init(document: Document) BlockIterator {
        return .{ .events = document.xml_document.iterator() };
    }

    /// Returned identifiers remain valid until the next iterator call.
    pub fn next(self: *BlockIterator) !?BlockFormat {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    if (!insideAfe(self.afe_depth, element.depth)) continue;
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioChannelFormat",
                    )) {
                        const encoded =
                            try element.attribute("audioChannelFormatID") orelse
                            return error.MissingAdmIdentifier;
                        const raw = try xml.decodeContent(
                            &self.channel_storage,
                            encoded,
                        );
                        const identifier = try adm.Identifier.parse(raw);
                        if (identifier.kind != .channel_format)
                            return error.InvalidAdmDeclarationKind;
                        self.channel_name =
                            if (try element.attribute(
                                "audioChannelFormatName",
                            )) |encoded_name|
                                try self.decodeAdmTextAttribute(encoded_name)
                            else
                                null;
                        if (element.self_closing) {
                            self.channel_identifier = null;
                            self.channel_name = null;
                            self.channel_depth = null;
                        } else {
                            self.channel_identifier = identifier;
                            self.channel_depth = element.depth;
                        }
                        continue;
                    }
                    if (!std.mem.startsWith(
                        u8,
                        element.localName(),
                        "audioBlockFormat",
                    )) {
                        continue;
                    }
                    const channel = self.channel_identifier orelse
                        return error.InvalidAdmBlockOwner;
                    const channel_depth = self.channel_depth orelse
                        return error.InvalidAdmBlockOwner;
                    if (element.depth != channel_depth + 1)
                        return error.InvalidAdmBlockOwner;
                    return try self.readBlock(
                        element,
                        channel,
                        self.channel_name,
                    );
                },
                .end => |element| {
                    if (self.channel_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioChannelFormat",
                        ))
                    {
                        self.channel_identifier = null;
                        self.channel_name = null;
                        self.channel_depth = null;
                    }
                    if (self.afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn readBlock(
        self: *BlockIterator,
        start: xml.StartElement,
        channel: adm.Identifier,
        channel_name: ?AdmText,
    ) !BlockFormat {
        const encoded_identifier =
            try start.attribute("audioBlockFormatID") orelse
            return error.MissingAdmIdentifier;
        const raw_identifier = try xml.decodeContent(
            &self.identifier_storage,
            encoded_identifier,
        );
        const identifier = try adm.Identifier.parse(raw_identifier);
        if (identifier.kind != .block_format)
            return error.InvalidAdmDeclarationKind;

        const encoded_rtime = try start.attribute("rtime");
        const encoded_duration = try start.attribute("duration");
        var block = BlockFormat{
            .identifier = identifier,
            .channel_identifier = channel,
            .channel_name = channel_name,
            .rtime = if (encoded_rtime) |value|
                try adm_time.Value.parse(value)
            else
                zeroAdmTime(),
            .rtime_explicit = encoded_rtime != null,
            .duration = if (encoded_duration) |value|
                try adm_time.Value.parse(value)
            else
                null,
        };
        if (start.self_closing) {
            try validateBlockTypeParameters(block, .{});
            return block;
        }

        var gain_seen = false;
        var importance_seen = false;
        var jump_seen = false;
        var head_locked_seen = false;
        var headphone_virtualise_seen = false;
        var cartesian_seen = false;
        var width_seen = false;
        var height_seen = false;
        var depth_seen = false;
        var diffuse_seen = false;
        var object_divergence_seen = false;
        var channel_lock_seen = false;
        var screen_ref_seen = false;
        var hoa_equation_seen = false;
        var hoa_order_seen = false;
        var hoa_degree_seen = false;
        var hoa_normalization_seen = false;
        var hoa_nfc_reference_distance_seen = false;
        var matrix_seen = false;
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (element.depth != start.depth + 1) continue;
                    if (std.mem.eql(u8, element.localName(), "gain")) {
                        if (gain_seen) return error.DuplicateAdmBlockParameter;
                        gain_seen = true;
                        const unit = if (try element.attribute("gainUnit")) |raw|
                            try parseGainUnit(raw)
                        else
                            GainUnit.linear;
                        const value = try self.readFloatElement(element);
                        if (unit == .linear and value < 0.0)
                            return error.InvalidAdmLinearGain;
                        block.gain = .{ .value = value, .unit = unit };
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "importance")) {
                        if (importance_seen)
                            return error.DuplicateAdmBlockParameter;
                        importance_seen = true;
                        const value = try self.readUnsignedElement(element);
                        if (value > 10) return error.InvalidAdmImportance;
                        block.importance = @intCast(value);
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "jumpPosition",
                    )) {
                        if (jump_seen) return error.DuplicateAdmBlockParameter;
                        jump_seen = true;
                        const interpolation = if (try element.attribute(
                            "interpolationLength",
                        )) |raw|
                            try adm_time.Value.parse(raw)
                        else
                            null;
                        const enabled = try self.readFlagElement(element);
                        if (!enabled and interpolation != null)
                            return error.InvalidAdmInterpolationLength;
                        if (interpolation) |length| {
                            const duration = block.duration orelse
                                return error.UnboundedAdmInterpolation;
                            if (length.compare(duration) == .gt)
                                return error.AdmInterpolationExceedsDuration;
                        }
                        block.jump_position = .{
                            .enabled = enabled,
                            .interpolation_length = interpolation,
                        };
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "headLocked",
                    )) {
                        if (head_locked_seen)
                            return error.DuplicateAdmBlockParameter;
                        head_locked_seen = true;
                        block.head_locked = try self.readFlagElement(element);
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "headphoneVirtualise",
                    )) {
                        if (headphone_virtualise_seen)
                            return error.DuplicateAdmBlockParameter;
                        headphone_virtualise_seen = true;
                        const bypass = if (try element.attribute("bypass")) |raw|
                            try parseAdmFlag(raw)
                        else
                            false;
                        const direct_to_reverberant_ratio_db =
                            if (try element.attribute("DRR")) |raw|
                                try parseFiniteAdmFloat(raw)
                            else
                                130.0;
                        try self.consumeEmptyElement(element);
                        block.headphone_virtualise = .{
                            .bypass = bypass,
                            .direct_to_reverberant_ratio_db = direct_to_reverberant_ratio_db,
                        };
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "speakerLabel",
                    )) {
                        if (block.speaker_label_count ==
                            max_adm_speaker_labels)
                        {
                            return error.TooManyAdmSpeakerLabels;
                        }
                        const value = try self.readSimpleElement(element);
                        if (value.len > max_adm_speaker_label_bytes)
                            return error.AdmSpeakerLabelTooLong;
                        const index = block.speaker_label_count;
                        @memcpy(
                            block.speaker_labels[index].bytes[0..value.len],
                            value,
                        );
                        block.speaker_labels[index].len = @intCast(value.len);
                        block.speaker_label_count += 1;
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "position")) {
                        if (block.position_count == max_adm_positions)
                            return error.TooManyAdmPositions;
                        const encoded_coordinate =
                            try element.attribute("coordinate") orelse
                            return error.MissingAdmCoordinate;
                        const position = Position{
                            .coordinate = try parseAdmCoordinate(
                                encoded_coordinate,
                            ),
                            .bound = if (try element.attribute("bound")) |raw|
                                try parseAdmPositionBound(raw)
                            else
                                .exact,
                            .value = try self.readFloatElement(element),
                            .screen_edge_lock = if (try element.attribute(
                                "screenEdgeLock",
                            )) |raw|
                                try parseAdmScreenEdge(raw)
                            else
                                null,
                        };
                        for (block.positionSlice()) |previous| {
                            if (previous.coordinate == position.coordinate and
                                previous.bound == position.bound)
                            {
                                return error.DuplicateAdmPosition;
                            }
                        }
                        block.positions[block.position_count] = position;
                        block.position_count += 1;
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "cartesian")) {
                        if (cartesian_seen)
                            return error.DuplicateAdmBlockParameter;
                        cartesian_seen = true;
                        block.cartesian = try self.readFlagElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "width")) {
                        if (width_seen) return error.DuplicateAdmBlockParameter;
                        width_seen = true;
                        block.width = try self.readFloatElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "height")) {
                        if (height_seen)
                            return error.DuplicateAdmBlockParameter;
                        height_seen = true;
                        block.height = try self.readFloatElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "depth")) {
                        if (depth_seen) return error.DuplicateAdmBlockParameter;
                        depth_seen = true;
                        block.depth = try self.readFloatElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "diffuse")) {
                        if (diffuse_seen)
                            return error.DuplicateAdmBlockParameter;
                        diffuse_seen = true;
                        block.diffuse = try self.readFloatElement(element);
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "objectDivergence",
                    )) {
                        if (object_divergence_seen)
                            return error.DuplicateAdmBlockParameter;
                        object_divergence_seen = true;
                        block.object_divergence = .{
                            .value = try self.readFloatElement(element),
                            .azimuth_range = if (try element.attribute(
                                "azimuthRange",
                            )) |raw|
                                try parseFiniteAdmFloat(raw)
                            else
                                null,
                            .position_range = if (try element.attribute(
                                "positionRange",
                            )) |raw|
                                try parseFiniteAdmFloat(raw)
                            else
                                null,
                        };
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "channelLock")) {
                        if (channel_lock_seen)
                            return error.DuplicateAdmBlockParameter;
                        channel_lock_seen = true;
                        block.channel_lock = .{
                            .enabled = try self.readFlagElement(element),
                            .max_distance = if (try element.attribute(
                                "maxDistance",
                            )) |raw|
                                try parseFiniteAdmFloat(raw)
                            else
                                null,
                        };
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "screenRef")) {
                        if (screen_ref_seen)
                            return error.DuplicateAdmBlockParameter;
                        screen_ref_seen = true;
                        block.screen_ref = try self.readFlagElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "equation")) {
                        if (hoa_equation_seen)
                            return error.DuplicateAdmBlockParameter;
                        hoa_equation_seen = true;
                        const value = try self.readSimpleElement(element);
                        if (value.len > max_profile_text_bytes)
                            return error.AdmEquationTooLong;
                        var equation = AdmText{ .len = @intCast(value.len) };
                        @memcpy(equation.bytes[0..value.len], value);
                        block.hoa_equation = equation;
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "order")) {
                        if (hoa_order_seen)
                            return error.DuplicateAdmBlockParameter;
                        hoa_order_seen = true;
                        const value = try self.readUnsignedElement(element);
                        if (value > std.math.maxInt(u32))
                            return error.InvalidAdmHoaOrder;
                        block.hoa_order = @intCast(value);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "degree")) {
                        if (hoa_degree_seen)
                            return error.DuplicateAdmBlockParameter;
                        hoa_degree_seen = true;
                        block.hoa_degree = try self.readSignedElement(element);
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "normalization",
                    )) {
                        if (hoa_normalization_seen)
                            return error.DuplicateAdmBlockParameter;
                        hoa_normalization_seen = true;
                        block.hoa_normalization = try parseHoaNormalization(
                            try self.readSimpleElement(element),
                        );
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "nfcRefDist")) {
                        if (hoa_nfc_reference_distance_seen)
                            return error.DuplicateAdmBlockParameter;
                        hoa_nfc_reference_distance_seen = true;
                        block.hoa_nfc_reference_distance =
                            try self.readFloatElement(element);
                        continue;
                    }
                    if (std.mem.eql(u8, element.localName(), "matrix")) {
                        if (matrix_seen)
                            return error.DuplicateAdmBlockParameter;
                        matrix_seen = true;
                        try self.readMatrix(element, &block);
                        continue;
                    }
                },
                .end => |element| {
                    if (element.depth > start.depth) continue;
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmBlockFormat;
                    }
                    try validateBlockTypeParameters(
                        block,
                        .{
                            .head_locked = head_locked_seen,
                            .headphone_virtualise = headphone_virtualise_seen,
                            .cartesian = cartesian_seen,
                            .width = width_seen,
                            .height = height_seen,
                            .depth = depth_seen,
                            .diffuse = diffuse_seen,
                            .object_divergence = object_divergence_seen,
                            .channel_lock = channel_lock_seen,
                            .screen_ref = screen_ref_seen,
                            .hoa_equation = hoa_equation_seen,
                            .hoa_order = hoa_order_seen,
                            .hoa_degree = hoa_degree_seen,
                            .hoa_normalization = hoa_normalization_seen,
                            .hoa_nfc_reference_distance = hoa_nfc_reference_distance_seen,
                            .matrix = matrix_seen,
                        },
                    );
                    return block;
                },
                else => {},
            }
        }
        return error.UnclosedAdmBlockFormat;
    }

    fn readMatrix(
        self: *BlockIterator,
        start: xml.StartElement,
        block: *BlockFormat,
    ) !void {
        if (start.self_closing) return error.EmptyAdmMatrix;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                        return error.InvalidAdmMatrix;
                },
                .start => |element| {
                    if (element.depth != start.depth + 1) continue;
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "coefficient",
                    )) {
                        continue;
                    }
                    if (block.matrix_coefficient_count ==
                        max_adm_matrix_coefficients)
                    {
                        return error.TooManyAdmMatrixCoefficients;
                    }
                    const gain_attribute = try element.attribute("gain");
                    const gain_variable_attribute =
                        try element.attribute("gainVar");
                    const phase_attribute = try element.attribute("phase");
                    const phase_variable_attribute =
                        try element.attribute("phaseVar");
                    const delay_attribute = try element.attribute("delay");
                    const delay_variable_attribute =
                        try element.attribute("delayVar");
                    if ((gain_attribute != null and
                        gain_variable_attribute != null) or
                        (phase_attribute != null and
                            phase_variable_attribute != null) or
                        (delay_attribute != null and
                            delay_variable_attribute != null))
                    {
                        return error.AmbiguousAdmMatrixCoefficient;
                    }
                    const raw_identifier = try self.readSimpleElement(element);
                    const identifier = try adm.Identifier.parse(raw_identifier);
                    if (identifier.kind != .channel_format)
                        return error.InvalidAdmMatrixCoefficientReference;
                    var coefficient = MatrixCoefficient{
                        .channel_identifier_len = @intCast(raw_identifier.len),
                    };
                    @memcpy(
                        coefficient.channel_identifier_bytes[0..raw_identifier.len],
                        raw_identifier,
                    );
                    coefficient.gain = .{
                        .value = if (gain_attribute) |raw|
                            try parseFiniteAdmFloat(raw)
                        else
                            1.0,
                        .unit = if (try element.attribute("gainUnit")) |raw|
                            try parseGainUnit(raw)
                        else
                            .linear,
                    };
                    if (gain_variable_attribute) |raw| {
                        coefficient.gain_variable =
                            try self.decodeAdmTextAttribute(raw);
                    }
                    coefficient.phase_degrees = if (phase_attribute) |raw|
                        try parseFiniteAdmFloat(raw)
                    else
                        0.0;
                    if (phase_variable_attribute) |raw| {
                        coefficient.phase_variable =
                            try self.decodeAdmTextAttribute(raw);
                    }
                    coefficient.delay_milliseconds =
                        if (delay_attribute) |raw|
                            try parseFiniteAdmFloat(raw)
                        else
                            0.0;
                    if (delay_variable_attribute) |raw| {
                        coefficient.delay_variable =
                            try self.decodeAdmTextAttribute(raw);
                    }
                    block.matrix_coefficients[
                        block.matrix_coefficient_count
                    ] = coefficient;
                    block.matrix_coefficient_count += 1;
                },
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmMatrix;
                    }
                    if (block.matrix_coefficient_count == 0)
                        return error.EmptyAdmMatrix;
                    return;
                },
            }
        }
        return error.UnclosedAdmMatrix;
    }

    fn decodeAdmTextAttribute(
        self: *BlockIterator,
        encoded: []const u8,
    ) !AdmText {
        const decoded = xml.decodeContent(
            &self.value_storage,
            encoded,
        ) catch |err| switch (err) {
            error.XmlDecodeBufferTooSmall => return error.AdmBlockValueTooLong,
            else => return err,
        };
        const value = std.mem.trim(u8, decoded, " \t\r\n");
        if (value.len == 0) return error.EmptyAdmBlockParameter;
        var result = AdmText{ .len = @intCast(value.len) };
        @memcpy(result.bytes[0..value.len], value);
        return result;
    }

    fn readFloatElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !f64 {
        const raw = try self.readSimpleElement(start);
        return parseFiniteAdmFloat(raw);
    }

    fn readUnsignedElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !u64 {
        const raw = try self.readSimpleElement(start);
        for (raw) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidAdmInteger;
        }
        return std.fmt.parseInt(u64, raw, 10) catch
            return error.InvalidAdmInteger;
    }

    fn readSignedElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !i32 {
        const raw = try self.readSimpleElement(start);
        return std.fmt.parseInt(i32, raw, 10) catch
            return error.InvalidAdmInteger;
    }

    fn readFlagElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !bool {
        return parseAdmFlag(try self.readSimpleElement(start));
    }

    fn consumeEmptyElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !void {
        if (start.self_closing) return;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                        return error.InvalidAdmEmptyElement;
                },
                .start => return error.InvalidAdmEmptyElement,
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmEmptyElement;
                    }
                    return;
                },
            }
        }
        return error.UnclosedAdmBlockParameter;
    }

    fn readSimpleElement(
        self: *BlockIterator,
        start: xml.StartElement,
    ) ![]const u8 {
        if (start.self_closing) return error.EmptyAdmBlockParameter;
        var encoded_storage: [max_profile_text_bytes * 5]u8 = undefined;
        var encoded_bytes: usize = 0;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    const next_offset = std.math.add(
                        usize,
                        encoded_bytes,
                        text.bytes.len,
                    ) catch return error.AdmBlockValueTooLong;
                    if (next_offset > encoded_storage.len)
                        return error.AdmBlockValueTooLong;
                    @memcpy(
                        encoded_storage[encoded_bytes..next_offset],
                        text.bytes,
                    );
                    encoded_bytes = next_offset;
                },
                .start => return error.NestedAdmBlockParameter,
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmBlockParameter;
                    }
                    const encoded = std.mem.trim(
                        u8,
                        encoded_storage[0..encoded_bytes],
                        " \t\r\n",
                    );
                    const decoded = xml.decodeContent(
                        &self.value_storage,
                        encoded,
                    ) catch |err| switch (err) {
                        error.XmlDecodeBufferTooSmall => return error.AdmBlockValueTooLong,
                        else => return err,
                    };
                    const trimmed = std.mem.trim(
                        u8,
                        decoded,
                        " \t\r\n",
                    );
                    if (trimmed.len == 0)
                        return error.EmptyAdmBlockParameter;
                    return trimmed;
                },
            }
        }
        return error.UnclosedAdmBlockParameter;
    }
};

pub const DeclarationIterator = struct {
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    identifier_storage: [max_identifier_bytes]u8 = undefined,

    fn init(document: Document) DeclarationIterator {
        return .{ .events = document.xml_document.iterator() };
    }

    /// The returned identifier remains valid until the next iterator call.
    pub fn next(self: *DeclarationIterator) !?Declaration {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    if (!insideAfe(self.afe_depth, element.depth)) continue;
                    const spec = declarationSpec(element.localName()) orelse
                        continue;
                    const encoded = try element.attribute(spec.attribute_name) orelse
                        return error.MissingAdmIdentifier;
                    const raw = try xml.decodeContent(
                        &self.identifier_storage,
                        encoded,
                    );
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind != spec.kind)
                        return error.InvalidAdmDeclarationKind;
                    return .{
                        .identifier = identifier,
                        .element_name = element.localName(),
                    };
                },
                .end => |element| {
                    if (self.afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                },
                else => {},
            }
        }
        return null;
    }
};

pub const ReferenceIterator = struct {
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    tag_group_depth: ?usize = null,
    owners: [xml.max_depth]?adm.Identifier = @splat(null),
    owner_depths: [xml.max_depth]?usize = @splat(null),
    owner_storage: [xml.max_depth][max_identifier_bytes]u8 = undefined,
    identifier_storage: [max_identifier_bytes]u8 = undefined,

    fn init(document: Document) ReferenceIterator {
        return .{ .events = document.xml_document.iterator() };
    }

    /// Returned identifiers remain valid until the next iterator call.
    pub fn next(self: *ReferenceIterator) !?Reference {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const inherited = if (element.depth == 0)
                        null
                    else
                        self.owners[element.depth - 1];
                    const inherited_depth = if (element.depth == 0)
                        null
                    else
                        self.owner_depths[element.depth - 1];
                    self.owners[element.depth] = inherited;
                    self.owner_depths[element.depth] = inherited_depth;
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    if (!insideAfe(self.afe_depth, element.depth)) continue;
                    if (std.mem.eql(u8, element.localName(), "tagGroup")) {
                        self.tag_group_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                    }
                    if (declarationSpec(element.localName())) |declaration_spec| {
                        const encoded =
                            try element.attribute(declaration_spec.attribute_name) orelse
                            return error.MissingAdmIdentifier;
                        const raw = try xml.decodeContent(
                            &self.owner_storage[element.depth],
                            encoded,
                        );
                        const identifier = try adm.Identifier.parse(raw);
                        if (identifier.kind != declaration_spec.kind)
                            return error.InvalidAdmDeclarationKind;
                        self.owners[element.depth] = identifier;
                        self.owner_depths[element.depth] = element.depth;
                    }
                    const spec = referenceSpec(element.localName()) orelse
                        continue;
                    if (element.self_closing)
                        return error.EmptyAdmXmlReference;
                    return try self.readReference(
                        element,
                        spec,
                        self.owners[element.depth],
                        self.owner_depths[element.depth],
                        if (self.tag_group_depth) |depth|
                            element.depth == depth + 1
                        else
                            false,
                    );
                },
                .end => |element| {
                    if (self.tag_group_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "tagGroup"))
                    {
                        self.tag_group_depth = null;
                    }
                    if (self.afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn readReference(
        self: *ReferenceIterator,
        start: xml.StartElement,
        spec: ReferenceSpec,
        owner: ?adm.Identifier,
        owner_depth: ?usize,
        tag_target: bool,
    ) !Reference {
        var encoded_storage: [max_identifier_bytes * 5]u8 = undefined;
        var encoded_bytes: usize = 0;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    const next_offset = std.math.add(
                        usize,
                        encoded_bytes,
                        text.bytes.len,
                    ) catch return error.AdmIdentifierTooLong;
                    if (next_offset > encoded_storage.len)
                        return error.AdmIdentifierTooLong;
                    @memcpy(
                        encoded_storage[encoded_bytes..next_offset],
                        text.bytes,
                    );
                    encoded_bytes = next_offset;
                },
                .start => return error.NestedAdmXmlReference,
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmXmlReference;
                    }
                    const encoded = std.mem.trim(
                        u8,
                        encoded_storage[0..encoded_bytes],
                        " \t\r\n",
                    );
                    const raw = try xml.decodeContent(
                        &self.identifier_storage,
                        encoded,
                    );
                    if (spec.kind == .track_uid and
                        asciiEqlIgnoreCase(raw, "ATU_00000000"))
                    {
                        return .{
                            .identifier = null,
                            .kind = spec.kind,
                            .owner = owner,
                            .direct_owner = directOwner(
                                owner_depth,
                                start.depth,
                            ),
                            .tag_target = tag_target,
                            .virtual_silent_track = true,
                        };
                    }
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind != spec.identifier_kind)
                        return error.InvalidAdmReferenceKind;
                    return .{
                        .identifier = identifier,
                        .kind = spec.kind,
                        .owner = owner,
                        .direct_owner = directOwner(
                            owner_depth,
                            start.depth,
                        ),
                        .tag_target = tag_target,
                    };
                },
            }
        }
        return error.UnclosedAdmXmlReference;
    }
};

const DeclarationSpec = struct {
    kind: adm.IdentifierKind,
    attribute_name: []const u8,
};

fn declarationSpec(local_name: []const u8) ?DeclarationSpec {
    if (std.mem.eql(u8, local_name, "audioProgramme"))
        return .{ .kind = .programme, .attribute_name = "audioProgrammeID" };
    if (std.mem.eql(u8, local_name, "audioContent"))
        return .{ .kind = .content, .attribute_name = "audioContentID" };
    if (std.mem.eql(u8, local_name, "audioObject"))
        return .{ .kind = .object, .attribute_name = "audioObjectID" };
    if (std.mem.eql(u8, local_name, "audioPackFormat"))
        return .{ .kind = .pack_format, .attribute_name = "audioPackFormatID" };
    if (std.mem.eql(u8, local_name, "audioChannelFormat"))
        return .{ .kind = .channel_format, .attribute_name = "audioChannelFormatID" };
    if (std.mem.eql(u8, local_name, "audioStreamFormat"))
        return .{ .kind = .stream_format, .attribute_name = "audioStreamFormatID" };
    if (std.mem.eql(u8, local_name, "audioTrackFormat"))
        return .{ .kind = .track_format, .attribute_name = "audioTrackFormatID" };
    if (std.mem.eql(u8, local_name, "audioTrackUID"))
        return .{ .kind = .track_uid, .attribute_name = "UID" };
    if (std.mem.eql(u8, local_name, "alternativeValueSet"))
        return .{ .kind = .alternative_value_set, .attribute_name = "alternativeValueSetID" };
    if (std.mem.startsWith(u8, local_name, "audioBlockFormat"))
        return .{ .kind = .block_format, .attribute_name = "audioBlockFormatID" };
    return null;
}

const ReferenceSpec = struct {
    kind: ReferenceKind,
    identifier_kind: adm.IdentifierKind,
};

fn referenceSpec(local_name: []const u8) ?ReferenceSpec {
    if (std.mem.eql(u8, local_name, "audioProgrammeIDRef"))
        return .{ .kind = .programme, .identifier_kind = .programme };
    if (std.mem.eql(u8, local_name, "audioContentIDRef"))
        return .{ .kind = .content, .identifier_kind = .content };
    if (std.mem.eql(u8, local_name, "audioObjectIDRef"))
        return .{ .kind = .object, .identifier_kind = .object };
    if (std.mem.eql(u8, local_name, "audioComplementaryObjectIDRef"))
        return .{ .kind = .complementary_object, .identifier_kind = .object };
    if (std.mem.eql(u8, local_name, "audioTrackUIDRef"))
        return .{ .kind = .track_uid, .identifier_kind = .track_uid };
    if (std.mem.eql(u8, local_name, "audioStreamFormatIDRef"))
        return .{ .kind = .stream_format, .identifier_kind = .stream_format };
    if (std.mem.eql(u8, local_name, "audioTrackFormatIDRef"))
        return .{ .kind = .track_format, .identifier_kind = .track_format };
    if (std.mem.eql(u8, local_name, "alternativeValueSetIDRef"))
        return .{ .kind = .alternative_value_set, .identifier_kind = .alternative_value_set };
    if (std.mem.eql(u8, local_name, "audioBlockFormatIDRef"))
        return .{ .kind = .block_format, .identifier_kind = .block_format };
    if (std.mem.eql(u8, local_name, "encodePackFormatIDRef"))
        return .{ .kind = .matrix_encode_pack, .identifier_kind = .pack_format };
    if (std.mem.eql(u8, local_name, "decodePackFormatIDRef"))
        return .{ .kind = .matrix_decode_pack, .identifier_kind = .pack_format };
    if (std.mem.eql(u8, local_name, "inputPackFormatIDRef"))
        return .{ .kind = .matrix_input_pack, .identifier_kind = .pack_format };
    if (std.mem.eql(u8, local_name, "outputPackFormatIDRef"))
        return .{ .kind = .matrix_output_pack, .identifier_kind = .pack_format };
    if (std.mem.eql(u8, local_name, "outputChannelFormatIDRef"))
        return .{ .kind = .matrix_output_channel, .identifier_kind = .channel_format };
    if (std.mem.eql(u8, local_name, "outputChannelIDRef"))
        return .{ .kind = .matrix_output_channel, .identifier_kind = .channel_format };
    if (std.mem.endsWith(u8, local_name, "PackFormatIDRef"))
        return .{ .kind = .pack_format, .identifier_kind = .pack_format };
    if (std.mem.endsWith(u8, local_name, "ChannelFormatIDRef"))
        return .{ .kind = .channel_format, .identifier_kind = .channel_format };
    return null;
}

const ChannelEntries = union(enum) {
    allocation: adm.ChannelAllocation,
    view: adm.View,

    fn count(self: ChannelEntries) usize {
        return switch (self) {
            .allocation => |allocation| allocation.entries.len,
            .view => |view| view.num_uids,
        };
    }

    fn entry(self: ChannelEntries, index: usize) !adm.Entry {
        return switch (self) {
            .allocation => |allocation| allocation.entries[index],
            .view => |view| view.entry(index),
        };
    }

    fn containsUid(self: ChannelEntries, wanted: adm.Identifier) !bool {
        var index: usize = 0;
        while (index < self.count()) : (index += 1) {
            const identifier = try adm.Identifier.parse(
                (try self.entry(index)).uid,
            );
            if (identifier.eql(wanted)) return true;
        }
        return false;
    }
};

fn channelTrackReference(raw: []const u8) !adm.Identifier {
    if (raw.len == 14 and asciiEqlIgnoreCase(raw[0..3], "AC_"))
        return adm.Identifier.parse(raw[0..11]);
    return adm.Identifier.parse(raw);
}

fn insideAfe(afe_depth: ?usize, element_depth: usize) bool {
    const depth = afe_depth orelse return false;
    return element_depth > depth;
}

fn directOwner(owner_depth: ?usize, reference_depth: usize) bool {
    const depth = owner_depth orelse return false;
    return depth + 1 == reference_depth;
}

fn validateReferenceRelationship(
    reference: Reference,
    identifier: adm.Identifier,
) !void {
    if (reference.tag_target) {
        if (reference.owner != null or
            (reference.kind != .programme and
                reference.kind != .content and
                reference.kind != .object))
        {
            return error.InvalidAdmTagTargetOwner;
        }
        return;
    }
    const owner = reference.owner orelse
        return error.InvalidAdmReferenceOwner;
    const valid_owner = switch (reference.kind) {
        .programme => false,
        .content => owner.kind == .programme,
        .object => owner.kind == .content or owner.kind == .object,
        .complementary_object => owner.kind == .object,
        .pack_format => owner.kind == .object or
            owner.kind == .pack_format or
            owner.kind == .stream_format or
            owner.kind == .track_uid,
        .matrix_encode_pack,
        .matrix_decode_pack,
        .matrix_input_pack,
        .matrix_output_pack,
        => owner.kind == .pack_format,
        .channel_format => owner.kind == .pack_format or
            owner.kind == .stream_format or
            owner.kind == .track_uid or
            owner.kind == .block_format,
        .matrix_output_channel => owner.kind == .block_format,
        .stream_format => owner.kind == .track_format,
        .track_format => owner.kind == .stream_format or
            owner.kind == .track_uid,
        .track_uid => owner.kind == .object,
        .alternative_value_set => owner.kind == .programme or
            owner.kind == .object,
        .block_format => owner.kind == .channel_format,
    };
    if (!valid_owner) return error.InvalidAdmReferenceOwner;

    const primary_must_match =
        (owner.kind == .track_format and identifier.kind == .stream_format) or
        (owner.kind == .stream_format and
            (identifier.kind == .track_format or
                identifier.kind == .channel_format)) or
        (owner.kind == .channel_format and identifier.kind == .block_format);
    if (primary_must_match and owner.primary != identifier.primary)
        return error.AdmFormatIdentifierMismatch;

    const type_must_match =
        (owner.kind == .pack_format and
            (reference.kind == .pack_format or
                reference.kind == .channel_format)) or
        (owner.kind == .stream_format and
            reference.kind == .pack_format);
    if (type_must_match and owner.typeLabel() != identifier.typeLabel())
        return error.AdmFormatTypeMismatch;
}

fn decodeNonEmptyProfileValue(
    storage: []u8,
    encoded: []const u8,
) ![]const u8 {
    const decoded = xml.decodeContent(storage, encoded) catch |err| switch (err) {
        error.XmlDecodeBufferTooSmall => return error.AdmProfileValueTooLong,
        else => return err,
    };
    const trimmed = std.mem.trim(u8, decoded, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyAdmProfileValue;
    return trimmed;
}

fn decodeRequiredTagValue(
    storage: []u8,
    encoded: []const u8,
) ![]const u8 {
    const decoded = xml.decodeContent(storage, encoded) catch |err| switch (err) {
        error.XmlDecodeBufferTooSmall => return error.AdmTagValueTooLong,
        else => return err,
    };
    const trimmed = std.mem.trim(u8, decoded, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyAdmTagValue;
    return trimmed;
}

fn decodeOptionalTagValue(
    storage: []u8,
    encoded: []const u8,
) ![]const u8 {
    const value = try decodeRequiredTagValue(storage, encoded);
    return value;
}

fn tagTargetKind(local_name: []const u8) ?adm.IdentifierKind {
    if (std.mem.eql(u8, local_name, "audioProgrammeIDRef"))
        return .programme;
    if (std.mem.eql(u8, local_name, "audioContentIDRef"))
        return .content;
    if (std.mem.eql(u8, local_name, "audioObjectIDRef"))
        return .object;
    return null;
}

fn zeroAdmTime() adm_time.Value {
    return .{
        .whole_seconds = 0,
        .fractional_numerator = 0,
        .fractional_denominator = 1,
        .format = .decimal,
    };
}

fn parseGainUnit(encoded: []const u8) !GainUnit {
    if (std.mem.eql(u8, encoded, "linear")) return .linear;
    if (std.mem.eql(u8, encoded, "dB")) return .decibels;
    return error.InvalidAdmGainUnit;
}

fn parseFiniteAdmFloat(encoded: []const u8) !f64 {
    const value = std.fmt.parseFloat(f64, encoded) catch
        return error.InvalidAdmFloat;
    if (!std.math.isFinite(value)) return error.InvalidAdmFloat;
    return value;
}

fn parseAdmFlag(encoded: []const u8) !bool {
    if (std.mem.eql(u8, encoded, "0")) return false;
    if (std.mem.eql(u8, encoded, "1")) return true;
    return error.InvalidAdmFlag;
}

fn parseAdmCoordinate(encoded: []const u8) !Coordinate {
    if (std.mem.eql(u8, encoded, "azimuth")) return .azimuth;
    if (std.mem.eql(u8, encoded, "elevation")) return .elevation;
    if (std.mem.eql(u8, encoded, "distance")) return .distance;
    if (std.mem.eql(u8, encoded, "X")) return .x;
    if (std.mem.eql(u8, encoded, "Y")) return .y;
    if (std.mem.eql(u8, encoded, "Z")) return .z;
    return error.InvalidAdmCoordinate;
}

fn parseAdmPositionBound(encoded: []const u8) !PositionBound {
    if (std.mem.eql(u8, encoded, "min")) return .minimum;
    if (std.mem.eql(u8, encoded, "max")) return .maximum;
    return error.InvalidAdmPositionBound;
}

fn parseAdmScreenEdge(encoded: []const u8) !ScreenEdge {
    if (asciiEqlIgnoreCase(encoded, "left")) return .left;
    if (asciiEqlIgnoreCase(encoded, "right")) return .right;
    if (asciiEqlIgnoreCase(encoded, "top")) return .top;
    if (asciiEqlIgnoreCase(encoded, "bottom")) return .bottom;
    return error.InvalidAdmScreenEdge;
}

fn parseHoaNormalization(encoded: []const u8) !HoaNormalization {
    if (std.mem.eql(u8, encoded, "N3D")) return .n3d;
    if (std.mem.eql(u8, encoded, "SN3D")) return .sn3d;
    if (std.mem.eql(u8, encoded, "FuMa")) return .fuma;
    return error.InvalidAdmHoaNormalization;
}

const BlockParameterPresence = struct {
    head_locked: bool = false,
    headphone_virtualise: bool = false,
    cartesian: bool = false,
    width: bool = false,
    height: bool = false,
    depth: bool = false,
    diffuse: bool = false,
    object_divergence: bool = false,
    channel_lock: bool = false,
    screen_ref: bool = false,
    hoa_equation: bool = false,
    hoa_order: bool = false,
    hoa_degree: bool = false,
    hoa_normalization: bool = false,
    hoa_nfc_reference_distance: bool = false,
    matrix: bool = false,
};

fn validateBlockTypeParameters(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    const type_label = block.identifier.typeLabel() orelse
        return error.InvalidAdmBlockIdentifier;
    if ((type_label == 0x0002 or type_label == 0x0005) and
        (present.head_locked or present.headphone_virtualise))
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
    switch (type_label) {
        0x0001 => try validateDirectSpeakersBlock(block, present),
        0x0002 => try validateMatrixBlock(block, present),
        0x0003 => try validateObjectsBlock(block, present),
        0x0004 => try validateHoaBlock(block, present),
        0x0005 => try validateBinauralBlock(block, present),
        else => {
            if (block.position_count != 0 or
                block.speaker_label_count != 0 or
                present.cartesian or
                present.width or
                present.height or
                present.depth or
                present.diffuse or
                present.object_divergence or
                present.channel_lock or
                present.screen_ref or
                hasHoaParameters(present) or
                present.matrix)
            {
                return error.AdmBlockParameterNotAllowedForType;
            }
        },
    }
}

fn validateBinauralBlock(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    const channel_name = block.channel_name orelse
        return error.MissingAdmBinauralChannelName;
    const name = channel_name.value();
    if (!std.mem.eql(u8, name, "LeftEar") and
        !std.mem.eql(u8, name, "RightEar") and
        !std.mem.eql(u8, name, "leftEar") and
        !std.mem.eql(u8, name, "rightEar"))
    {
        return error.InvalidAdmBinauralChannelName;
    }
    if (block.position_count != 0 or
        block.speaker_label_count != 0 or
        present.cartesian or
        present.width or
        present.height or
        present.depth or
        present.diffuse or
        present.object_divergence or
        present.channel_lock or
        present.screen_ref or
        hasHoaParameters(present) or
        present.matrix)
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
}

fn validateDirectSpeakersBlock(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    if (present.width or
        present.height or
        present.depth or
        present.diffuse or
        present.object_divergence or
        present.channel_lock or
        present.screen_ref or
        hasHoaParameters(present) or
        present.matrix)
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
    if (block.cartesian and !present.cartesian)
        return error.MissingAdmCartesianFlag;
    try validatePositions(block.positionSlice(), block.cartesian, true);
    if (block.cartesian) {
        if (!hasExactPosition(block.positionSlice(), .x) or
            !hasExactPosition(block.positionSlice(), .y))
        {
            return error.MissingAdmPosition;
        }
    } else if (!hasExactPosition(block.positionSlice(), .azimuth) or
        !hasExactPosition(block.positionSlice(), .elevation))
    {
        return error.MissingAdmPosition;
    }
    try validatePositionBounds(block.positionSlice());
}

fn validateObjectsBlock(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    if (block.speaker_label_count != 0)
        return error.AdmBlockParameterNotAllowedForType;
    if (hasHoaParameters(present) or present.matrix)
        return error.AdmBlockParameterNotAllowedForType;
    try validatePositions(block.positionSlice(), block.cartesian, false);
    if (block.cartesian) {
        if (!hasExactPosition(block.positionSlice(), .x) or
            !hasExactPosition(block.positionSlice(), .y))
        {
            return error.MissingAdmPosition;
        }
        try validateInclusive(block.width, 0.0, 1.0);
        try validateInclusive(block.height, 0.0, 1.0);
        try validateInclusive(block.depth, 0.0, 1.0);
    } else {
        if (!hasExactPosition(block.positionSlice(), .azimuth) or
            !hasExactPosition(block.positionSlice(), .elevation))
        {
            return error.MissingAdmPosition;
        }
        try validateInclusive(block.width, 0.0, 360.0);
        try validateInclusive(block.height, 0.0, 360.0);
        try validateInclusive(block.depth, 0.0, 1.0);
    }
    try validateInclusive(block.diffuse, 0.0, 1.0);
    try validateInclusive(block.object_divergence.value, 0.0, 1.0);
    if (block.cartesian) {
        if (block.object_divergence.azimuth_range != null)
            return error.InvalidAdmObjectDivergence;
        if (block.object_divergence.position_range) |range|
            try validateInclusive(range, 0.0, 1.0);
    } else {
        if (block.object_divergence.position_range != null)
            return error.InvalidAdmObjectDivergence;
        if (block.object_divergence.azimuth_range) |range|
            try validateInclusive(range, 0.0, 180.0);
    }
    if (!block.channel_lock.enabled and
        block.channel_lock.max_distance != null)
    {
        return error.InvalidAdmChannelLock;
    }
    if (block.channel_lock.max_distance) |distance|
        try validateInclusive(distance, 0.0, 2.0 * @sqrt(3.0));
}

fn validateHoaBlock(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    if (block.position_count != 0 or
        block.speaker_label_count != 0 or
        present.cartesian or
        present.width or
        present.height or
        present.depth or
        present.diffuse or
        present.object_divergence or
        present.channel_lock or
        present.matrix)
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
    const order = block.hoa_order orelse return error.MissingAdmHoaOrder;
    const degree = block.hoa_degree orelse return error.MissingAdmHoaDegree;
    const order_signed: i64 = @intCast(order);
    if (@as(i64, degree) < -order_signed or
        @as(i64, degree) > order_signed)
    {
        return error.InvalidAdmHoaDegree;
    }
    if (block.hoa_nfc_reference_distance < 0.0)
        return error.InvalidAdmParameterRange;
}

fn validateMatrixBlock(
    block: BlockFormat,
    present: BlockParameterPresence,
) !void {
    if (!present.matrix or block.matrix_coefficient_count == 0)
        return error.MissingAdmMatrix;
    if (block.position_count != 0 or
        block.speaker_label_count != 0 or
        present.cartesian or
        present.width or
        present.height or
        present.depth or
        present.diffuse or
        present.object_divergence or
        present.channel_lock or
        present.screen_ref or
        hasHoaParameters(present))
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
}

fn hasHoaParameters(present: BlockParameterPresence) bool {
    return present.hoa_equation or
        present.hoa_order or
        present.hoa_degree or
        present.hoa_normalization or
        present.hoa_nfc_reference_distance;
}

fn validatePositions(
    positions: []const Position,
    cartesian: bool,
    bounds_allowed: bool,
) !void {
    var screen_edge_count: usize = 0;
    for (positions) |position| {
        if (!bounds_allowed and position.bound != .exact)
            return error.AdmPositionBoundNotAllowed;
        switch (position.coordinate) {
            .azimuth => {
                if (cartesian) return error.MixedAdmCoordinateSystems;
                try validateInclusive(position.value, -180.0, 180.0);
            },
            .elevation => {
                if (cartesian) return error.MixedAdmCoordinateSystems;
                try validateInclusive(position.value, -90.0, 90.0);
            },
            .distance => {
                if (cartesian) return error.MixedAdmCoordinateSystems;
                try validateInclusive(position.value, 0.0, 1.0);
            },
            .x, .y, .z => {
                if (!cartesian) return error.MixedAdmCoordinateSystems;
                try validateInclusive(position.value, -1.0, 1.0);
            },
        }
        if (position.screen_edge_lock) |edge| {
            screen_edge_count += 1;
            if (screen_edge_count > 2)
                return error.TooManyAdmScreenEdgeLocks;
            const valid = switch (edge) {
                .left, .right => position.coordinate == .azimuth or
                    position.coordinate == .x,
                .top, .bottom => position.coordinate == .elevation or
                    position.coordinate == .z,
            };
            if (!valid) return error.InvalidAdmScreenEdgeCoordinate;
        }
    }
}

fn validatePositionBounds(positions: []const Position) !void {
    inline for (std.meta.tags(Coordinate)) |coordinate| {
        var exact: ?f64 = null;
        var minimum: ?f64 = null;
        var maximum: ?f64 = null;
        for (positions) |position| {
            if (position.coordinate != coordinate) continue;
            switch (position.bound) {
                .exact => exact = position.value,
                .minimum => minimum = position.value,
                .maximum => maximum = position.value,
            }
        }
        if (minimum) |minimum_value| {
            if (maximum) |maximum_value| {
                if (minimum_value > maximum_value)
                    return error.InvalidAdmPositionBounds;
            }
        }
        if (exact) |value| {
            if (minimum) |minimum_value| {
                if (value < minimum_value)
                    return error.InvalidAdmPositionBounds;
            }
            if (maximum) |maximum_value| {
                if (value > maximum_value)
                    return error.InvalidAdmPositionBounds;
            }
        }
    }
}

fn hasExactPosition(
    positions: []const Position,
    coordinate: Coordinate,
) bool {
    for (positions) |position| {
        if (position.coordinate == coordinate and position.bound == .exact)
            return true;
    }
    return false;
}

fn validateInclusive(value: f64, minimum: f64, maximum: f64) !void {
    if (!std.math.isFinite(value) or value < minimum or value > maximum)
        return error.InvalidAdmParameterRange;
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte))
            return false;
    }
    return true;
}

test "ADM XML validates a namespaced custom reference graph" {
    const bytes =
        \\<?xml version="1.0"?>
        \\<ebu:ebuCoreMain xmlns:ebu="urn:ebu">
        \\  <ebu:audioFormatExtended>
        \\    <ebu:audioProgramme audioProgrammeID="APR_1001">
        \\      <ebu:audioContentIDRef>ACO_1001</ebu:audioContentIDRef>
        \\    </ebu:audioProgramme>
        \\    <ebu:audioContent audioContentID="ACO_1001">
        \\      <ebu:audioObjectIDRef>AO_1001</ebu:audioObjectIDRef>
        \\    </ebu:audioContent>
        \\    <ebu:audioObject audioObjectID="AO_1001">
        \\      <ebu:audioPackFormatIDRef>AP_00031001</ebu:audioPackFormatIDRef>
        \\      <ebu:audioTrackUIDRef>ATU_00000001</ebu:audioTrackUIDRef>
        \\      <ebu:alternativeValueSet alternativeValueSetID="AVS_1001_0001"/>
        \\    </ebu:audioObject>
        \\    <ebu:audioPackFormat audioPackFormatID="AP_00031001">
        \\      <ebu:audioChannelFormatIDRef>AC_00031001</ebu:audioChannelFormatIDRef>
        \\    </ebu:audioPackFormat>
        \\    <ebu:audioChannelFormat audioChannelFormatID="AC_00031001">
        \\      <ebu:audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\        <ebu:position coordinate="azimuth">0.0</ebu:position>
        \\        <ebu:position coordinate="elevation">0.0</ebu:position>
        \\      </ebu:audioBlockFormatObjects>
        \\    </ebu:audioChannelFormat>
        \\    <ebu:audioStreamFormat audioStreamFormatID="AS_00031001">
        \\      <ebu:audioChannelFormatIDRef>AC_00031001</ebu:audioChannelFormatIDRef>
        \\      <ebu:audioTrackFormatIDRef>AT_00031001_01</ebu:audioTrackFormatIDRef>
        \\    </ebu:audioStreamFormat>
        \\    <ebu:audioTrackFormat audioTrackFormatID="AT_00031001_01">
        \\      <ebu:audioStreamFormatIDRef>AS_00031001</ebu:audioStreamFormatIDRef>
        \\    </ebu:audioTrackFormat>
        \\    <ebu:audioTrackUID UID="ATU_00000001">
        \\      <ebu:audioTrackFormatIDRef>AT_00031001_01</ebu:audioTrackFormatIDRef>
        \\      <ebu:audioPackFormatIDRef>AP_00031001</ebu:audioPackFormatIDRef>
        \\    </ebu:audioTrackUID>
        \\  </ebu:audioFormatExtended>
        \\</ebu:ebuCoreMain>
    ;
    const document = try Document.init(bytes);
    try std.testing.expectEqual(@as(usize, 10), document.declaration_count);
    try std.testing.expectEqual(@as(usize, 10), document.reference_count);
    try std.testing.expect(try document.contains(
        try adm.Identifier.parse("AB_00031001_00000001"),
    ));
}

test "ADM XML resolves common definitions and rejects missing custom ones" {
    _ = try Document.init(
        \\<audioFormatExtended>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000000</audioTrackUIDRef>
        \\  </audioObject>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.UnresolvedAdmReference,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="AO_1001">
            \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
            \\  </audioObject>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML rejects duplicate IDs wrong kinds and self references" {
    try std.testing.expectError(
        error.DuplicateAdmDeclaration,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="AO_1001"/>
            \\  <audioObject audioObjectID="ao_1001"/>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmDeclarationKind,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="ACO_1001"/>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.SelfReferentialAdmDefinition,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="AO_1001">
            \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
            \\  </audioObject>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML enforces relationship types identifiers and cardinalities" {
    try std.testing.expectError(
        error.InvalidAdmReferenceOwner,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioContent audioContentID="ACO_1001">
            \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
            \\  </audioContent>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmFormatIdentifierMismatch,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioStreamFormat audioStreamFormatID="AS_00031001">
            \\    <audioChannelFormatIDRef>AC_00031002</audioChannelFormatIDRef>
            \\  </audioStreamFormat>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031002"/>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MissingReciprocalAdmTrackReference,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioStreamFormat audioStreamFormatID="AS_00031001"/>
            \\  <audioTrackFormat audioTrackFormatID="AT_00031001_01">
            \\    <audioStreamFormatIDRef>AS_00031001</audioStreamFormatIDRef>
            \\  </audioTrackFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AmbiguousAdmStreamFormat,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioStreamFormat audioStreamFormatID="AS_00010001">
            \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
            \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
            \\  </audioStreamFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML validates CHNA common and custom mappings" {
    const common_document = try Document.init("<audioFormatExtended/>");
    const common_entries = [_]adm.Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    try common_document.validateChannelAllocation(.{
        .num_tracks = 1,
        .entries = &common_entries,
    });

    const custom_document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioPackFormat audioPackFormatID="AP_00031001"/>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackFormat audioTrackFormatID="AT_00031001_01"/>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioTrackFormatIDRef>AT_00031001_01</audioTrackFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\</audioFormatExtended>
    );
    const custom_entries = [_]adm.Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00031001_01",
        .pack_ref = "AP_00031001",
    }};
    try custom_document.validateChannelAllocation(.{
        .num_tracks = 1,
        .entries = &custom_entries,
    });

    const mismatched_entries = [_]adm.Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AC_00031001_00",
        .pack_ref = "AP_00031001",
    }};
    try std.testing.expectError(
        error.AdmTrackReferenceMismatch,
        custom_document.validateChannelAllocation(.{
            .num_tracks = 1,
            .entries = &mismatched_entries,
        }),
    );
}

test "ADM XML requires CHNA entries for referenced physical track UIDs" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        \\</audioFormatExtended>
    );
    const entries = [_]adm.Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
    }};
    try std.testing.expectError(
        error.AdmTrackUidMissingFromChannelAllocation,
        document.validateChannelAllocation(.{
            .num_tracks = 1,
            .entries = &entries,
        }),
    );
}

test "ADM XML exposes complete profile declarations" {
    const document = try Document.init(
        \\<ebu:audioFormatExtended xmlns:ebu="urn:ebu" version="ITU-R_BS.2076-3">
        \\  <ebu:profileList>
        \\    <ebu:profile profileName="AdvSS &amp; NGA"
        \\      profileVersion="1.0.0" profileLevel="1">
        \\      ITU-R BS.2168-0
        \\    </ebu:profile>
        \\    <ebu:profile profileName="Production Profile"
        \\      profileVersion="2.0.0" profileLevel="2">
        \\      EBU R 143
        \\    </ebu:profile>
        \\  </ebu:profileList>
        \\</ebu:audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 2), document.profile_count);

    var profiles = document.profiles();
    const first = (try profiles.next()).?;
    try std.testing.expectEqualStrings("AdvSS & NGA", first.name);
    try std.testing.expectEqualStrings("1.0.0", first.version);
    try std.testing.expectEqualStrings("1", first.level);
    try std.testing.expectEqualStrings("ITU-R BS.2168-0", first.reference);
    const second = (try profiles.next()).?;
    try std.testing.expectEqualStrings("Production Profile", second.name);
    try std.testing.expectEqualStrings("2.0.0", second.version);
    try std.testing.expectEqualStrings("2", second.level);
    try std.testing.expectEqualStrings("EBU R 143", second.reference);
    try std.testing.expect((try profiles.next()) == null);
}

test "ADM XML rejects malformed profile lists" {
    try std.testing.expectError(
        error.MultipleAdmProfileLists,
        Document.init(
            \\<audioFormatExtended>
            \\  <profileList>
            \\    <profile profileName="A" profileVersion="1" profileLevel="1">A</profile>
            \\  </profileList>
            \\  <profileList>
            \\    <profile profileName="B" profileVersion="1" profileLevel="1">B</profile>
            \\  </profileList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.EmptyAdmProfileList,
        Document.init(
            \\<audioFormatExtended><profileList/></audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MissingAdmProfileVersion,
        Document.init(
            \\<audioFormatExtended>
            \\  <profileList>
            \\    <profile profileName="A" profileLevel="1">A</profile>
            \\  </profileList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.EmptyAdmProfileValue,
        Document.init(
            \\<audioFormatExtended>
            \\  <profileList>
            \\    <profile profileName="A" profileVersion="1" profileLevel="1"> </profile>
            \\  </profileList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmProfileOwner,
        Document.init(
            \\<audioFormatExtended>
            \\  <profile profileName="A" profileVersion="1" profileLevel="1">A</profile>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML identifies and bounds the emission profile" {
    const document = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioPackFormat audioPackFormatID="AP_00021001"/>
        \\  <audioPackFormat audioPackFormatID="AP_00031001"/>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001"/>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(
        EmissionProfileLevel.level_1,
        try document.emissionProfileLevel(),
    );
    try std.testing.expectEqual(
        EmissionProfileLevel.level_1,
        try document.validateEmissionProfileElementLimits(),
    );
}

test "ADM XML emission profile rejects invalid declarations" {
    const wrong_name = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <profileList>
        \\    <profile profileName="Emission Profile"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileName,
        wrong_name.emissionProfileLevel(),
    );

    const wrong_version = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="2" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.UnsupportedAdmEmissionProfileVersion,
        wrong_version.emissionProfileLevel(),
    );

    const wrong_level = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="3">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.UnsupportedAdmEmissionProfileLevel,
        wrong_level.emissionProfileLevel(),
    );

    const duplicate = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.DuplicateAdmProfile,
        duplicate.emissionProfileLevel(),
    );
}

test "ADM XML emission profile enforces core element limits" {
    const too_many_programmes = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioProgramme audioProgrammeID="APR_1002"/>
        \\  <audioProgramme audioProgrammeID="APR_1003"/>
        \\  <audioProgramme audioProgrammeID="APR_1004"/>
        \\  <audioProgramme audioProgrammeID="APR_1005"/>
        \\  <audioProgramme audioProgrammeID="APR_1006"/>
        \\  <audioProgramme audioProgrammeID="APR_1007"/>
        \\  <audioProgramme audioProgrammeID="APR_1008"/>
        \\  <audioProgramme audioProgrammeID="APR_1009"/>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.AdmEmissionProfileElementLimitExceeded,
        too_many_programmes.validateEmissionProfileElementLimits(),
    );

    const forbidden_track_format = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <audioTrackFormat audioTrackFormatID="AT_00011001_01"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.ForbiddenAdmEmissionProfileFormat,
        forbidden_track_format.validateEmissionProfileElementLimits(),
    );

    const wrong_document_version = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-2">
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.UnsupportedAdmEmissionProfileDocumentVersion,
        wrong_document_version.validateEmissionProfileElementLimits(),
    );
}

test "ADM XML emission profile validates core identifiers" {
    const valid = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0001"/>
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0002"/>
        \\  </audioObject>
        \\  <audioPackFormat audioPackFormatID="AP_00031001"/>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <audioTrackUID UID="ATU_00000002"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try valid.validateEmissionProfileIdentifiers();

    const low_programme_id = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1000"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileIdentifier,
        low_programme_id.validateEmissionProfileIdentifiers(),
    );

    const mismatched_content = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioObject audioObjectID="AO_1002"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileContentReference,
        mismatched_content.validateEmissionProfileIdentifiers(),
    );

    const skipped_track_uid = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000002"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileTrackUidSequence,
        skipped_track_uid.validateEmissionProfileIdentifiers(),
    );
}

test "ADM XML emission profile validates alternative value set identifiers" {
    const mismatched_parent = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <alternativeValueSet alternativeValueSetID="AVS_1002_0001"/>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileIdentifier,
        mismatched_parent.validateEmissionProfileIdentifiers(),
    );

    const skipped_sequence = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0002"/>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileIdentifier,
        skipped_sequence.validateEmissionProfileIdentifiers(),
    );

    const indirect_owner = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <extension>
        \\      <alternativeValueSet alternativeValueSetID="AVS_1001_0001"/>
        \\    </extension>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionAlternativeValueSetOwner,
        indirect_owner.validateEmissionProfileIdentifiers(),
    );
}

test "ADM XML emission profile sub-element counters cover every level limit" {
    for ([_]EmissionProfileLevel{ .level_1, .level_2 }) |level| {
        const limits = emissionSubelementLimits(level);
        const cases = [_]struct {
            owner: EmissionSubelementOwner,
            local_name: []const u8,
            limit: usize,
        }{
            .{
                .owner = .programme,
                .local_name = "audioContentIDRef",
                .limit = limits.programme_content,
            },
            .{
                .owner = .programme,
                .local_name = "alternativeValueSetIDRef",
                .limit = limits.programme_content,
            },
            .{
                .owner = .programme,
                .local_name = "audioProgrammeLabel",
                .limit = limits.programme_labels,
            },
            .{
                .owner = .content,
                .local_name = "audioContentLabel",
                .limit = limits.content_labels,
            },
            .{
                .owner = .object,
                .local_name = "audioObjectIDRef",
                .limit = limits.object_children,
            },
            .{
                .owner = .object,
                .local_name = "audioComplementaryObjectIDRef",
                .limit = limits.complementary_objects,
            },
            .{
                .owner = .object,
                .local_name = "alternativeValueSet",
                .limit = limits.alternative_value_sets,
            },
            .{
                .owner = .object,
                .local_name = "audioComplementaryObjectGroupLabel",
                .limit = limits.complementary_labels,
            },
        };
        for (cases) |case| {
            var counts = EmissionSubelementCounts{};
            for (0..case.limit) |_| {
                try counts.note(case.owner, case.local_name, limits);
            }
            try std.testing.expectError(
                error.AdmEmissionProfileSubelementLimitExceeded,
                counts.note(case.owner, case.local_name, limits),
            );
        }
    }
}

test "ADM XML emission profile enforces direct sub-element limits" {
    const boundary = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try boundary.validateEmissionProfileSubelementLimits();

    const overflow = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\    <audioProgrammeLabel/>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.AdmEmissionProfileSubelementLimitExceeded,
        overflow.validateEmissionProfileSubelementLimits(),
    );
}

test "ADM XML exposes tag groups and typed targets" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioProgramme audioProgrammeID="APR_1001"/>
        \\  <audioContent audioContentID="ACO_1001"/>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <tagList>
        \\    <tagGroup>
        \\      <tag class="format">NGA &amp; immersive</tag>
        \\      <tag>final</tag>
        \\      <audioProgrammeIDRef>APR_1001</audioProgrammeIDRef>
        \\      <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\    </tagGroup>
        \\    <tagGroup>
        \\      <tag class="dialogue type">boosted dialogue</tag>
        \\      <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\    </tagGroup>
        \\  </tagList>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 2), document.tag_group_count);
    try std.testing.expectEqual(@as(usize, 3), document.tag_count);
    try std.testing.expectEqual(@as(usize, 3), document.tag_target_count);

    var items = document.tags();
    const first = (try items.next()).?.tag;
    try std.testing.expectEqual(@as(usize, 0), first.group_index);
    try std.testing.expectEqualStrings("NGA & immersive", first.value);
    try std.testing.expectEqualStrings("format", first.class.?);
    const second = (try items.next()).?.tag;
    try std.testing.expectEqualStrings("final", second.value);
    try std.testing.expect(second.class == null);
    const programme = (try items.next()).?.target;
    try std.testing.expectEqual(adm.IdentifierKind.programme, programme.identifier.kind);
    const content = (try items.next()).?.target;
    try std.testing.expectEqual(adm.IdentifierKind.content, content.identifier.kind);
    const third = (try items.next()).?.tag;
    try std.testing.expectEqual(@as(usize, 1), third.group_index);
    const object = (try items.next()).?.target;
    try std.testing.expectEqual(adm.IdentifierKind.object, object.identifier.kind);
}

test "ADM XML rejects malformed tag groups and misplaced references" {
    try std.testing.expectError(
        error.AdmTagGroupMissingTarget,
        Document.init(
            \\<audioFormatExtended>
            \\  <tagList><tagGroup><tag>orphan</tag></tagGroup></tagList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmTagGroupMissingTag,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="AO_1001"/>
            \\  <tagList><tagGroup>
            \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
            \\  </tagGroup></tagList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmTagTargetKind,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioContent audioContentID="ACO_1001"/>
            \\  <tagList><tagGroup>
            \\    <tag>bad kind</tag>
            \\    <audioObjectIDRef>ACO_1001</audioObjectIDRef>
            \\  </tagGroup></tagList>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmReferenceOwner,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioObject audioObjectID="AO_1001"/>
            \\  <audioObjectIDRef>AO_1001</audioObjectIDRef>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MultipleAdmTagLists,
        Document.init(
            \\<audioFormatExtended>
            \\  <tagList><tagGroup><tag>a</tag><audioObjectIDRef>AO_1001</audioObjectIDRef></tagGroup></tagList>
            \\  <tagList><tagGroup><tag>b</tag><audioObjectIDRef>AO_1001</audioObjectIDRef></tagGroup></tagList>
            \\  <audioObject audioObjectID="AO_1001"/>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML exposes block timing and common parameters" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001"
        \\      rtime="00:00:00.00000" duration="00:00:01.00000">
        \\      <gain gainUnit="dB">-6.0</gain>
        \\      <importance>8</importance>
        \\      <jumpPosition interpolationLength="12000S48000">1</jumpPosition>
        \\      <headLocked>1</headLocked>
        \\      <headphoneVirtualise bypass="1" DRR="96.5"/>
        \\      <position coordinate="azimuth">-22.5</position>
        \\      <position coordinate="elevation">5.0</position>
        \\      <position coordinate="distance">0.9</position>
        \\      <width>45.0</width>
        \\      <height>20.0</height>
        \\      <depth>0.2</depth>
        \\      <diffuse>0.5</diffuse>
        \\      <objectDivergence azimuthRange="60.0">0.5</objectDivergence>
        \\      <channelLock maxDistance="1.0">1</channelLock>
        \\      <screenRef>1</screenRef>
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000002"
        \\      rtime="00:00:01.00000" duration="00:00:01.00000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 2), document.block_count);

    var blocks = document.blocks();
    const first = (try blocks.next()).?;
    try std.testing.expect(first.rtime_explicit);
    try std.testing.expectEqual(@as(u64, 0), first.rtime.whole_seconds);
    try std.testing.expectEqual(@as(u64, 1), first.duration.?.whole_seconds);
    try std.testing.expectEqual(GainUnit.decibels, first.gain.unit);
    try std.testing.expectEqual(@as(f64, -6.0), first.gain.value);
    try std.testing.expectEqual(@as(u8, 8), first.importance);
    try std.testing.expect(first.jump_position.enabled);
    try std.testing.expectEqual(
        @as(u64, 12_000),
        first.jump_position.interpolation_length.?.fractional_numerator,
    );
    try std.testing.expect(first.head_locked);
    try std.testing.expect(first.headphone_virtualise.bypass);
    try std.testing.expectEqual(
        @as(f64, 96.5),
        first.headphone_virtualise.direct_to_reverberant_ratio_db,
    );
    try std.testing.expectEqual(@as(usize, 3), first.position_count);
    try std.testing.expectEqual(@as(f64, 45.0), first.width);
    try std.testing.expectEqual(@as(f64, 20.0), first.height);
    try std.testing.expectEqual(@as(f64, 0.2), first.depth);
    try std.testing.expectEqual(@as(f64, 0.5), first.diffuse);
    try std.testing.expectEqual(
        @as(?f64, 60.0),
        first.object_divergence.azimuth_range,
    );
    try std.testing.expect(first.channel_lock.enabled);
    try std.testing.expectEqual(
        @as(?f64, 1.0),
        first.channel_lock.max_distance,
    );
    try std.testing.expect(first.screen_ref);

    const second = (try blocks.next()).?;
    try std.testing.expectEqual(GainUnit.linear, second.gain.unit);
    try std.testing.expectEqual(@as(f64, 1.0), second.gain.value);
    try std.testing.expectEqual(@as(u8, 10), second.importance);
    try std.testing.expect(!second.jump_position.enabled);
    try std.testing.expect(!second.head_locked);
    try std.testing.expect(!second.headphone_virtualise.bypass);
    try std.testing.expectEqual(
        @as(f64, 130.0),
        second.headphone_virtualise.direct_to_reverberant_ratio_db,
    );
}

test "ADM XML validates DirectSpeakers and Cartesian Objects parameters" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M-SC</speakerLabel>
        \\      <position coordinate="azimuth" bound="min">-30.0</position>
        \\      <position coordinate="azimuth" screenEdgeLock="right">-29.0</position>
        \\      <position coordinate="azimuth" bound="max">-22.5</position>
        \\      <position coordinate="elevation" screenEdgeLock="top">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031002">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031002_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">-0.2</position>
        \\      <position coordinate="Y">0.1</position>
        \\      <position coordinate="Z">-0.5</position>
        \\      <width>0.03</width>
        \\      <depth>0.05</depth>
        \\      <height>0.07</height>
        \\      <objectDivergence positionRange="0.25">0.5</objectDivergence>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const direct = (try blocks.next()).?;
    try std.testing.expectEqual(@as(usize, 1), direct.speaker_label_count);
    try std.testing.expectEqualStrings(
        "M-SC",
        direct.speakerLabelSlice()[0].value(),
    );
    try std.testing.expectEqual(@as(usize, 5), direct.position_count);
    try std.testing.expectEqual(
        ScreenEdge.right,
        direct.positionSlice()[1].screen_edge_lock.?,
    );

    const object = (try blocks.next()).?;
    try std.testing.expect(object.cartesian);
    try std.testing.expectEqual(@as(f64, 0.03), object.width);
    try std.testing.expectEqual(@as(f64, 0.05), object.depth);
    try std.testing.expectEqual(@as(f64, 0.07), object.height);
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        object.object_divergence.position_range,
    );
}

test "ADM XML validates HOA component parameters" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <equation>cos(A)*sin(E)</equation>
        \\      <order>2</order>
        \\      <degree>-1</degree>
        \\      <normalization>N3D</normalization>
        \\      <nfcRefDist>2.5</nfcRefDist>
        \\      <screenRef>1</screenRef>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    try std.testing.expectEqual(@as(?u32, 2), block.hoa_order);
    try std.testing.expectEqual(@as(?i32, -1), block.hoa_degree);
    try std.testing.expectEqual(HoaNormalization.n3d, block.hoa_normalization);
    try std.testing.expectEqual(
        @as(f64, 2.5),
        block.hoa_nfc_reference_distance,
    );
    try std.testing.expectEqualStrings(
        "cos(A)*sin(E)",
        block.hoa_equation.?.value(),
    );
    try std.testing.expect(block.screen_ref);

    try std.testing.expectError(
        error.MissingAdmHoaDegree,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
            \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
            \\      <order>1</order>
            \\    </audioBlockFormatHoa>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmHoaDegree,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
            \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
            \\      <order>1</order>
            \\      <degree>2</degree>
            \\    </audioBlockFormatHoa>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmHoaNormalization,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
            \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
            \\      <order>1</order>
            \\      <degree>0</degree>
            \\      <normalization>unknown</normalization>
            \\    </audioBlockFormatHoa>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML exposes and validates Matrix coefficients" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <outputChannelIDRef>AC_00010003</outputChannelIDRef>
        \\      <matrix>
        \\        <coefficient gain="-0.5">AC_00010001</coefficient>
        \\        <coefficient gainUnit="dB" gain="-3" phase="90" delay="1.5">AC_00010002</coefficient>
        \\        <coefficient gainVar="g &amp; 1" phaseVar="p" delayVar="d">AC_00010003</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 1), document.block_count);
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const coefficients = block.matrixCoefficientSlice();
    try std.testing.expectEqual(@as(usize, 3), coefficients.len);
    try std.testing.expectEqual(@as(f64, -0.5), coefficients[0].gain.value);
    try std.testing.expectEqual(GainUnit.decibels, coefficients[1].gain.unit);
    try std.testing.expectEqual(@as(f64, 90.0), coefficients[1].phase_degrees);
    try std.testing.expectEqual(
        @as(f64, 1.5),
        coefficients[1].delay_milliseconds,
    );
    try std.testing.expectEqualStrings(
        "g & 1",
        coefficients[2].gain_variable.?.value(),
    );
    try std.testing.expectEqualStrings(
        "AC_00010003",
        (try coefficients[2].channelIdentifier()).raw,
    );
    var references = document.references();
    const output = (try references.next()).?;
    try std.testing.expectEqual(
        ReferenceKind.matrix_output_channel,
        output.kind,
    );
}

test "ADM XML rejects invalid Matrix coefficients" {
    try std.testing.expectError(
        error.MissingAdmMatrix,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.EmptyAdmMatrix,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
            \\      <matrix/>
            \\    </audioBlockFormatMatrix>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AmbiguousAdmMatrixCoefficient,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
            \\      <matrix>
            \\        <coefficient gain="0.5" gainVar="g">AC_00010001</coefficient>
            \\      </matrix>
            \\    </audioBlockFormatMatrix>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmMatrixCoefficientReference,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
            \\      <matrix>
            \\        <coefficient>AP_00010001</coefficient>
            \\      </matrix>
            \\    </audioBlockFormatMatrix>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.UnresolvedAdmReference,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
            \\      <matrix>
            \\        <coefficient>AC_00011001</coefficient>
            \\      </matrix>
            \\    </audioBlockFormatMatrix>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML rejects invalid spatial block parameters" {
    try std.testing.expectError(
        error.MissingAdmPosition,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0.0</position>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MixedAdmCoordinateSystems,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <cartesian>1</cartesian>
            \\      <position coordinate="X">0.0</position>
            \\      <position coordinate="azimuth">0.0</position>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmPositionBounds,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
            \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
            \\      <position coordinate="azimuth" bound="min">10.0</position>
            \\      <position coordinate="azimuth">0.0</position>
            \\      <position coordinate="elevation">0.0</position>
            \\    </audioBlockFormatDirectSpeakers>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmObjectDivergence,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0.0</position>
            \\      <position coordinate="elevation">0.0</position>
            \\      <objectDivergence positionRange="0.2">0.5</objectDivergence>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmChannelLock,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0.0</position>
            \\      <position coordinate="elevation">0.0</position>
            \\      <channelLock maxDistance="1.0">0</channelLock>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmParameterRange,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">181.0</position>
            \\      <position coordinate="elevation">0.0</position>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML validates current and legacy Binaural channel names" {
    const current = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 1), current.block_count);
    const legacy = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="leftEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 1), legacy.block_count);

    try std.testing.expectError(
        error.MissingAdmBinauralChannelName,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmBinauralChannelName,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="Centre">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmBlockParameterNotAllowedForType,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001">
            \\      <screenRef>1</screenRef>
            \\    </audioBlockFormatBinaural>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML validates block sequences timing and common values" {
    try std.testing.expectError(
        error.InvalidAdmBlockOwner,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
            \\  <extension>
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001"/>
            \\  </extension>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MissingDynamicAdmBlockTiming,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000002"
            \\      rtime="00:00:01.00000" duration="00:00:01.00000"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmBlockSequence,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000002"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmBlockIdentifierMismatch,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000001"/>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmImportance,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001">
            \\      <importance>11</importance>
            \\    </audioBlockFormatBinaural>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmInterpolationExceedsDuration,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"
            \\      duration="00:00:01.00000">
            \\      <jumpPosition interpolationLength="2.00000">1</jumpPosition>
            \\    </audioBlockFormatBinaural>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.DuplicateAdmBlockParameter,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
            \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001">
            \\      <gain>1.0</gain>
            \\      <gain>0.5</gain>
            \\    </audioBlockFormatBinaural>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmBlockParameterNotAllowedForType,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
            \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
            \\      <headLocked>1</headLocked>
            \\    </audioBlockFormatMatrix>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmFlag,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <headphoneVirtualise bypass="true"/>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmEmptyElement,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <headphoneVirtualise>unexpected</headphoneVirtualise>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}
