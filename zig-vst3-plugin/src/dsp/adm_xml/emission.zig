const std = @import("std");
const adm = @import("../adm.zig");
const adm_time = @import("../adm_time.zig");
const common = @import("common.zig");
const metadata = @import("metadata.zig");
const model = @import("model.zig");
const xml = @import("../xml.zig");

const max_identifier_bytes = common.max_identifier_bytes;
const max_profile_text_bytes = common.max_profile_text_bytes;
const isXmlNamespaceDeclaration = common.isXmlNamespaceDeclaration;
const MetadataEventIterator = metadata.MetadataEventIterator;
const parseAdmFlag = model.parseAdmFlag;
const parseAdmMatrixGain = model.parseAdmMatrixGain;
const parseFiniteAdmFloat = model.parseFiniteAdmFloat;
const parseGainUnit = model.parseGainUnit;
const BlockFormat = model.BlockFormat;
const Gain = model.Gain;
const GainUnit = model.GainUnit;
const Position = model.Position;
const Coordinate = model.Coordinate;
const AdmText = model.AdmText;
const Tag = model.Tag;

const max_emission_name_bytes: usize = 64 * 4;
const emission_language_word_count: usize = (26 * 26 * 26 + 63) / 64;
pub const iso_639_2_codes =
    "aarabkaceachadaadyafaafhafrainakaakkalbalealgaltamhanganpapaaraarcargarmarnarpartarwasmastathaus" ++
    "avaaveawaaymazebadbaibakbalbambanbaqbasbatbejbelbembenberbhobihbikbinbisblabntbodbosbrabrebtkbua" ++
    "bugbulburbyncadcaicarcatcaucebcelceschachbchechgchichkchmchnchochpchrchuchvchycmccnrcopcorcoscpe" ++
    "cpfcppcrecrhcrpcsbcuscymczedakdandardaydeldendeudgrdindivdoidradsbduadumdutdyudzoefiegyekaellelx" ++
    "engenmepoesteuseweewofanfaofasfatfijfilfinfiufonfrafrefrmfrofrrfrsfryfulfurgaagaygbagemgeogergez" ++
    "gilglagleglgglvgmhgohgongorgotgrbgrcgregrngswgujgwihaihathauhawhebherhilhimhinhithmnhmohrvhsbhun" ++
    "huphyeibaiboiceidoiiiijoikuileiloinaincindineinhipkirairoislitajavjbojpnjprjrbkaakabkackalkamkan" ++
    "karkaskatkaukawkazkbdkhakhikhmkhokikkinkirkmbkokkomkonkorkoskpekrckrlkrokrukuakumkurkutladlahlam" ++
    "laolatlavlezlimlinlitlollozltzlualublugluilunluolusmacmadmagmahmaimakmalmanmaomapmarmasmaymdfmdr" ++
    "menmgamicminmismkdmkhmlgmltmncmnimnomohmonmosmrimsamulmunmusmwlmwrmyamynmyvnahnainapnaunavnblnde" ++
    "ndondsnepnewnianicniunldnnonobnognonnornqonsonubnwcnyanymnynnyonziociojioriormosaossotaotopaapag" ++
    "palpampanpappaupeoperphiphnplipolponporprapropusquerajraprarroarohromronrumrunruprussadsagsahsai" ++
    "salsamsansassatscnscoselsemsgasgnshnsidsinsiositslaslksloslvsmasmesmismjsmnsmosmssnasndsnksogsom" ++
    "sonsotspasqisrdsrnsrpsrrssasswsuksunsussuxswaswesycsyrtahtaitamtatteltemtertettgktglthatibtigtir" ++
    "tivtkltlhtlitmhtogtontpitsitsntsotuktumtupturtuttvltwityvudmugauigukrumbundurduzbvaivenvievolvot" ++
    "wakwalwarwaswelwenwlnwolxalxhoyaoyapyidyorypkzapzblzenzghzhazhozndzulzunzxxzza";

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

pub const EmissionPcmEssence = struct {
    sample_rate: u32,
    bit_depth: u16,
    channel_count: u16,
    frame_count: u64,
};

pub const EmissionSerialFlowState = struct {
    initialized: bool = false,
    next_frame_index: u32 = 1,
    next_start: ?adm_time.Value = null,
    flow_id: ?[36]u8 = null,

    pub fn reset(self: *EmissionSerialFlowState) void {
        self.* = .{};
    }
};

pub const SerialLookup = struct {
    context: *const anyopaque,
    transport_id_count: *const fn (
        *const anyopaque,
        []const u8,
    ) anyerror!usize,
    track_id_count: *const fn (
        *const anyopaque,
        []const u8,
        u32,
    ) anyerror!usize,
    contains_identifier: *const fn (
        *const anyopaque,
        adm.IdentifierKind,
        u32,
        ?u32,
    ) anyerror!bool,

    fn transportIdCount(self: SerialLookup, wanted: []const u8) !usize {
        return self.transport_id_count(self.context, wanted);
    }

    fn trackIdCount(
        self: SerialLookup,
        transport_identifier: []const u8,
        wanted: u32,
    ) !usize {
        return self.track_id_count(
            self.context,
            transport_identifier,
            wanted,
        );
    }

    fn containsIdentifier(
        self: SerialLookup,
        kind: adm.IdentifierKind,
        primary: u32,
        secondary: ?u32,
    ) !bool {
        return self.contains_identifier(
            self.context,
            kind,
            primary,
            secondary,
        );
    }
};

pub const EmissionElementCounts = struct {
    programmes: usize = 0,
    contents: usize = 0,
    objects: usize = 0,
    pack_formats: usize = 0,
    channel_formats: usize = 0,
    track_uids: usize = 0,

    pub fn exceeds(
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

pub const EmissionSubelementOwner = enum {
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

pub const EmissionSubelementCounts = struct {
    programme_content_refs: usize = 0,
    programme_alternative_refs: usize = 0,
    programme_labels: usize = 0,
    content_labels: usize = 0,
    object_children: usize = 0,
    complementary_objects: usize = 0,
    alternative_value_sets: usize = 0,
    complementary_labels: usize = 0,

    pub fn note(
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

pub const EmissionObjectParent = struct {
    kind: adm.IdentifierKind,
    primary: u32,
};

pub const EmissionPackChannels = struct {
    primaries: [24]u32 = @splat(0),
    len: usize = 0,

    pub fn append(self: *EmissionPackChannels, primary: u32) !void {
        if (self.len == self.primaries.len)
            return error.AdmEmissionProfileLayoutChannelLimitExceeded;
        self.primaries[self.len] = primary;
        self.len += 1;
    }

    pub fn indexOf(self: EmissionPackChannels, primary: u32) ?usize {
        for (self.primaries[0..self.len], 0..) |candidate, index| {
            if (candidate == primary) return index;
        }
        return null;
    }
};

pub const EmissionMatrixPack = struct {
    input_pack: u32,
    output_pack: u32,
    channels: EmissionPackChannels,
};

const EmissionComplementaryLimits = struct {
    groups: usize,
    non_complementary_tracks: usize,
    independent_groups: usize,
};

const EmissionInteractionRange = struct {
    minimum: f64,
    maximum: f64,
    minimum_parameter: Gain,
    maximum_parameter: Gain,
};

const EmissionPositionCoordinate = enum {
    azimuth,
    x,
};

const EmissionPositionRange = struct {
    coordinate: EmissionPositionCoordinate,
    minimum: f64,
    maximum: f64,
};

pub const EmissionObjectInteraction = struct {
    gain_interact: ?bool = null,
    position_interact: ?bool = null,
    gain_range: ?EmissionInteractionRange = null,
    position_range: ?EmissionPositionRange = null,
};

const EmissionPositionOffset = struct {
    coordinate: EmissionPositionCoordinate,
    value: f64,
};

pub const EmissionObjectParameterState = struct {
    primary: u32,
    top_level: bool,
    interact: bool,
    interaction: ?EmissionObjectInteraction = null,
    gain: ?Gain = null,
    position: ?EmissionPositionOffset = null,
    uses_position_controls: bool = false,
    has_alternative_value_sets: bool = false,
};

pub const EmissionAlternativeParameters = struct {
    gain: ?Gain = null,
    interaction: ?EmissionObjectInteraction = null,
    position: ?EmissionPositionOffset = null,

    pub fn usesPositionControls(self: EmissionAlternativeParameters) bool {
        if (self.position != null) return true;
        const interaction = self.interaction orelse return false;
        return interaction.position_range != null;
    }
};

pub const EmissionLanguageSet = struct {
    words: [emission_language_word_count]u64 = @splat(0),

    pub fn note(self: *EmissionLanguageSet, code: [3]u8) !void {
        const index = emissionLanguageIndex(code);
        const word = index / 64;
        const mask = @as(u64, 1) << @intCast(index % 64);
        if (self.words[word] & mask != 0)
            return error.DuplicateAdmEmissionProfileLabelLanguage;
        self.words[word] |= mask;
    }

    pub fn eql(self: EmissionLanguageSet, other: EmissionLanguageSet) bool {
        return std.mem.eql(u64, &self.words, &other.words);
    }
};

const EmissionFormatOwnerKind = enum {
    matrix_pack,
    objects_pack,
    matrix_channel,
    objects_channel,
    track_uid,
};

pub const EmissionFormatOwner = struct {
    kind: EmissionFormatOwnerKind,
    depth: usize,
    channel_references: usize = 0,
    input_references: usize = 0,
    output_references: usize = 0,
    block_count: usize = 0,
    pack_references: usize = 0,
};

pub fn emissionProfileLimits(
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

pub fn emissionSubelementLimits(
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

pub fn emissionMaximumLayoutChannels(
    level: EmissionProfileLevel,
) usize {
    return switch (level) {
        .level_0 => std.math.maxInt(usize),
        .level_1 => 12,
        .level_2 => 24,
    };
}

pub fn emissionComplementaryLimits(
    level: EmissionProfileLevel,
) EmissionComplementaryLimits {
    const unlimited = std.math.maxInt(usize);
    return switch (level) {
        .level_0 => .{
            .groups = unlimited,
            .non_complementary_tracks = unlimited,
            .independent_groups = unlimited,
        },
        .level_1 => .{
            .groups = 8,
            .non_complementary_tracks = 16,
            .independent_groups = 16,
        },
        .level_2 => .{
            .groups = 14,
            .non_complementary_tracks = 28,
            .independent_groups = 16,
        },
    };
}

pub fn commonEmissionPackChannelIndexes(
    pack_index: u16,
) ?[]const u16 {
    return switch (pack_index) {
        0x0001 => &.{0x0003},
        0x0002 => &.{ 0x0001, 0x0002 },
        0x000a => &.{ 0x0001, 0x0002, 0x0003 },
        0x0003 => &.{
            0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006,
        },
        0x000c => &.{ 0x0001, 0x0002, 0x0003, 0x0005, 0x0006 },
        0x000f => &.{
            0x0001, 0x0002, 0x0003, 0x0004,
            0x000a, 0x000b, 0x001c, 0x001d,
        },
        0x001b => &.{
            0x0001, 0x0002, 0x0003, 0x000a,
            0x000b, 0x001c, 0x001d,
        },
        0x0004 => &.{
            0x0001, 0x0002, 0x0003, 0x0004,
            0x0005, 0x0006, 0x000d, 0x000f,
        },
        0x001c => &.{
            0x0001, 0x0002, 0x0003, 0x0005,
            0x0006, 0x000d, 0x000f,
        },
        0x0005 => &.{
            0x0001, 0x0002, 0x0003, 0x0004, 0x0005,
            0x0006, 0x000d, 0x000f, 0x0010, 0x0012,
        },
        0x001e => &.{
            0x0001, 0x0002, 0x0003, 0x0005, 0x0006,
            0x000d, 0x000f, 0x0010, 0x0012,
        },
        0x0017 => &.{
            0x0001, 0x0002, 0x0003, 0x0004,
            0x000a, 0x000b, 0x001c, 0x001d,
            0x0022, 0x0023, 0x001e, 0x001f,
        },
        0x001f => &.{
            0x0001, 0x0002, 0x0003, 0x000a,
            0x000b, 0x001c, 0x001d, 0x0022,
            0x0023, 0x001e, 0x001f,
        },
        0x0010 => &.{
            0x0018, 0x0019, 0x0003, 0x001c, 0x001d, 0x0001,
            0x0002, 0x0009, 0x000a, 0x000b, 0x0022, 0x0023,
            0x000e, 0x000c, 0x001e, 0x001f, 0x0013, 0x0014,
            0x0011, 0x0015, 0x0016, 0x0017,
        },
        0x0009 => &.{
            0x0018, 0x0019, 0x0003, 0x0020, 0x001c, 0x001d,
            0x0001, 0x0002, 0x0009, 0x0021, 0x000a, 0x000b,
            0x0022, 0x0023, 0x000e, 0x000c, 0x001e, 0x001f,
            0x0013, 0x0014, 0x0011, 0x0015, 0x0016, 0x0017,
        },
        0x0801 => &.{0x0803},
        0x0802 => &.{ 0x0801, 0x0802 },
        0x080a => &.{ 0x0801, 0x0802, 0x0803 },
        0x0803 => &.{
            0x0801, 0x0802, 0x0803, 0x0804, 0x0805, 0x0806,
        },
        0x080c => &.{ 0x0801, 0x0802, 0x0803, 0x0805, 0x0806 },
        0x080f => &.{
            0x0801, 0x0802, 0x0803, 0x0804,
            0x080a, 0x080b, 0x0805, 0x0806,
        },
        0x081b => &.{
            0x0801, 0x0802, 0x0803, 0x080a,
            0x080b, 0x0805, 0x0806,
        },
        0x0804 => &.{
            0x0801, 0x0802, 0x0803, 0x0804,
            0x0805, 0x0806, 0x080d, 0x080f,
        },
        0x081c => &.{
            0x0801, 0x0802, 0x0803, 0x0805,
            0x0806, 0x080d, 0x080f,
        },
        0x0805 => &.{
            0x0801, 0x0802, 0x0803, 0x0804, 0x0805,
            0x0806, 0x080d, 0x080f, 0x0810, 0x0812,
        },
        0x081e => &.{
            0x0801, 0x0802, 0x0803, 0x0805, 0x0806,
            0x080d, 0x080f, 0x0810, 0x0812,
        },
        0x0817 => &.{
            0x0801, 0x0802, 0x0803, 0x0804,
            0x080a, 0x080b, 0x0805, 0x0806,
            0x080d, 0x080f, 0x0810, 0x0812,
        },
        0x081f => &.{
            0x0801, 0x0802, 0x0803, 0x080a,
            0x080b, 0x0805, 0x0806, 0x080d,
            0x080f, 0x0810, 0x0812,
        },
        0x0810 => &.{
            0x0801, 0x0802, 0x0803, 0x0805, 0x0806, 0x0807,
            0x0808, 0x0809, 0x080a, 0x080b, 0x080d, 0x080f,
            0x080e, 0x080c, 0x0810, 0x0812, 0x0813, 0x0814,
            0x0811, 0x0815, 0x0816, 0x0817,
        },
        0x0809 => &.{
            0x0801, 0x0802, 0x0803, 0x0820, 0x0805, 0x0806,
            0x0807, 0x0808, 0x0809, 0x0821, 0x080a, 0x080b,
            0x080d, 0x080f, 0x080e, 0x080c, 0x0810, 0x0812,
            0x0813, 0x0814, 0x0811, 0x0815, 0x0816, 0x0817,
        },
        else => null,
    };
}

pub fn commonEmissionPackIsMatrixOutput(pack_index: u16) bool {
    return switch (pack_index) {
        0x000a,
        0x000c,
        0x001b,
        0x001c,
        0x001e,
        0x001f,
        0x0010,
        0x080a,
        0x080c,
        0x081b,
        0x081c,
        0x081e,
        0x081f,
        0x0810,
        => false,
        else => commonEmissionPackChannelIndexes(pack_index) != null,
    };
}

pub fn emissionCommonPackChannels(pack_primary: u32) !EmissionPackChannels {
    const type_label: u16 = @intCast(pack_primary >> 16);
    const pack_index: u16 = @truncate(pack_primary);
    if (type_label != 0x0001)
        return error.InvalidAdmEmissionProfileMatrixPack;
    const indexes = commonEmissionPackChannelIndexes(pack_index) orelse
        return error.InvalidAdmEmissionProfileMatrixPack;
    var result = EmissionPackChannels{};
    for (indexes) |index| {
        try result.append(
            (@as(u32, 0x0001) << 16) | @as(u32, index),
        );
    }
    return result;
}

pub fn validateEmissionMatrixCoefficients(
    block: BlockFormat,
    input_channels: EmissionPackChannels,
) !void {
    var used_inputs: [24]bool = @splat(false);
    for (block.matrixCoefficientSlice()) |coefficient| {
        const identifier = try coefficient.channelIdentifier();
        if (identifier.typeLabel() != 0x0001 or
            !identifier.isCommonDefinition())
        {
            return error.InvalidAdmEmissionProfileMatrixCoefficient;
        }
        const input_index = input_channels.indexOf(identifier.primary) orelse
            return error.InvalidAdmEmissionProfileMatrixCoefficient;
        if (used_inputs[input_index])
            return error.DuplicateAdmEmissionProfileMatrixCoefficient;
        used_inputs[input_index] = true;
        switch (coefficient.gain.unit) {
            .linear => if (coefficient.gain.value < 0.0 or
                coefficient.gain.value > 10.0)
            {
                return error.InvalidAdmEmissionProfileMatrixGain;
            },
            .decibels => if (coefficient.gain.value > 20.0 or
                (std.math.isInf(coefficient.gain.value) and
                    coefficient.gain.value > 0.0))
            {
                return error.InvalidAdmEmissionProfileMatrixGain;
            },
        }
    }
}

pub fn emissionElementIdentifier(
    element: xml.StartElement,
    attribute_name: []const u8,
    kind: adm.IdentifierKind,
) !adm.Identifier {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmIdentifier;
    var storage: [max_identifier_bytes]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    const identifier = try adm.Identifier.parse(raw);
    if (identifier.kind != kind) return error.InvalidAdmDeclarationKind;
    return identifier;
}

pub fn validateEmissionObjectAttributes(element: xml.StartElement) !void {
    var name_seen = false;
    var interact_seen = false;
    var attributes = xml.AttributeIterator.init(element.attributes);
    while (try attributes.next()) |attribute| {
        if (isXmlNamespaceDeclaration(attribute.name)) continue;
        const name = attribute.name;
        if (std.mem.eql(u8, name, "audioObjectID")) continue;
        if (std.mem.eql(u8, name, "audioObjectName")) {
            if (name_seen) return error.DuplicateXmlLocalAttribute;
            name_seen = true;
            var storage: [max_emission_name_bytes]u8 = undefined;
            const decoded = xml.decodeContent(
                &storage,
                attribute.value,
            ) catch |err| switch (err) {
                error.XmlDecodeBufferTooSmall => return error.InvalidAdmEmissionProfileObjectName,
                else => return err,
            };
            const characters = utf8ScalarCount(decoded);
            if (characters == 0 or characters > 64)
                return error.InvalidAdmEmissionProfileObjectName;
            continue;
        }
        if (std.mem.eql(u8, name, "interact")) {
            if (interact_seen) return error.DuplicateXmlLocalAttribute;
            interact_seen = true;
            continue;
        }
        return error.InvalidAdmEmissionProfileObjectAttribute;
    }
    if (!name_seen) return error.MissingAdmEmissionProfileObjectName;
    if (!interact_seen) return error.MissingAdmEmissionProfileInteract;
}

fn utf8ScalarCount(bytes: []const u8) usize {
    var count: usize = 0;
    for (bytes) |byte| {
        if (byte & 0xc0 != 0x80) count += 1;
    }
    return count;
}

fn emissionLanguageIndex(code: [3]u8) usize {
    return (@as(usize, code[0] - 'a') * 26 * 26) +
        (@as(usize, code[1] - 'a') * 26) +
        @as(usize, code[2] - 'a');
}

pub fn isIso6392Code(code: []const u8) bool {
    if (code.len != 3) return false;
    for (code) |byte| {
        if (byte < 'a' or byte > 'z') return false;
    }
    if (std.mem.order(u8, code, "qaa") != .lt and
        std.mem.order(u8, code, "qtz") != .gt)
    {
        return true;
    }
    var low: usize = 0;
    var high: usize = iso_639_2_codes.len / 3;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate = iso_639_2_codes[middle * 3 ..][0..3];
        switch (std.mem.order(u8, code, candidate)) {
            .lt => high = middle,
            .eq => return true,
            .gt => low = middle + 1,
        }
    }
    return false;
}

pub fn emissionRequiredLanguageAttribute(
    element: xml.StartElement,
    attribute_name: []const u8,
) ![3]u8 {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileLanguage;
    var storage: [16]u8 = undefined;
    const decoded = try xml.decodeContent(&storage, encoded);
    if (!isIso6392Code(decoded))
        return error.InvalidAdmEmissionProfileLanguage;
    return decoded[0..3].*;
}

fn validateEmissionRequiredName(
    element: xml.StartElement,
    attribute_name: []const u8,
) !void {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileName;
    var storage: [max_emission_name_bytes]u8 = undefined;
    const decoded = xml.decodeContent(&storage, encoded) catch |err| switch (err) {
        error.XmlDecodeBufferTooSmall => return error.InvalidAdmEmissionProfileName,
        else => return err,
    };
    const characters = utf8ScalarCount(decoded);
    if (characters == 0 or characters > 64)
        return error.InvalidAdmEmissionProfileName;
}

fn emissionRequiredAttributeValue(
    element: xml.StartElement,
    attribute_name: []const u8,
    expected: []const u8,
) !void {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileFormatAttribute;
    var storage: [max_profile_text_bytes]u8 = undefined;
    const decoded = try xml.decodeContent(&storage, encoded);
    if (!std.mem.eql(u8, decoded, expected))
        return error.InvalidAdmEmissionProfileFormatAttribute;
}

pub fn emissionRequiredAttributeValueAs(
    element: xml.StartElement,
    attribute_name: []const u8,
    expected: []const u8,
    missing_error: anyerror,
    invalid_error: anyerror,
) !void {
    const encoded = try element.attribute(attribute_name) orelse
        return missing_error;
    var storage: [64]u8 = undefined;
    const decoded = try xml.decodeContent(&storage, encoded);
    if (!std.mem.eql(u8, decoded, expected)) return invalid_error;
}

pub fn validateEmissionFormatDeclarationAttributes(
    element: xml.StartElement,
    identifier_attribute: []const u8,
    name_attribute: []const u8,
    type_label: u16,
) !void {
    try validateEmissionAttributes(
        element,
        &.{
            identifier_attribute,
            name_attribute,
            "typeLabel",
            "typeDefinition",
        },
        error.InvalidAdmEmissionProfileFormatAttribute,
    );
    try validateEmissionRequiredName(element, name_attribute);
    const expected_label, const expected_definition = switch (type_label) {
        0x0002 => .{ "0002", "Matrix" },
        0x0003 => .{ "0003", "Objects" },
        else => return error.InvalidAdmEmissionProfileFormatAttribute,
    };
    try emissionRequiredAttributeValue(
        element,
        "typeLabel",
        expected_label,
    );
    try emissionRequiredAttributeValue(
        element,
        "typeDefinition",
        expected_definition,
    );
}

pub fn validateEmissionTrackUidAttributes(element: xml.StartElement) !void {
    try validateEmissionAttributes(
        element,
        &.{ "UID", "sampleRate", "bitDepth" },
        error.InvalidAdmEmissionProfileTrackAttribute,
    );
    for ([_][]const u8{ "sampleRate", "bitDepth" }) |attribute_name| {
        _ = try emissionOptionalPositiveAttribute(element, attribute_name);
    }
}

pub fn emissionOptionalPositiveAttribute(
    element: xml.StartElement,
    attribute_name: []const u8,
) !?u32 {
    return emissionOptionalPositiveAttributeAs(
        element,
        attribute_name,
        error.InvalidAdmEmissionProfileTrackAttribute,
    );
}

pub fn emissionOptionalPositiveAttributeAs(
    element: xml.StartElement,
    attribute_name: []const u8,
    invalid_error: anyerror,
) !?u32 {
    const encoded = try element.attribute(attribute_name) orelse return null;
    var storage: [32]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    const value = std.fmt.parseInt(u32, raw, 10) catch return invalid_error;
    if (value == 0) return invalid_error;
    return value;
}

pub fn emissionRequiredFlagAttribute(
    element: xml.StartElement,
    attribute_name: []const u8,
) !bool {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileInteractionAttribute;
    var storage: [8]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    return parseAdmFlag(raw);
}

fn emissionOptionalFlagAttribute(
    element: xml.StartElement,
    attribute_name: []const u8,
) !?bool {
    const encoded = try element.attribute(attribute_name) orelse return null;
    var storage: [8]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    return try parseAdmFlag(raw);
}

pub fn isEmissionObjectReferenceOrLabel(name: []const u8) bool {
    return std.mem.eql(u8, name, "audioPackFormatIDRef") or
        std.mem.eql(u8, name, "audioObjectIDRef") or
        std.mem.eql(u8, name, "audioTrackUIDRef") or
        std.mem.eql(u8, name, "audioComplementaryObjectGroupLabel") or
        std.mem.eql(u8, name, "audioComplementaryObjectIDRef");
}

pub fn readEmissionObjectInteraction(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !EmissionObjectInteraction {
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileObjectInteraction;
    var result = EmissionObjectInteraction{
        .gain_interact = try emissionOptionalFlagAttribute(
            start,
            "gainInteract",
        ),
        .position_interact = try emissionOptionalFlagAttribute(
            start,
            "positionInteract",
        ),
    };
    const on_off = try emissionRequiredFlagAttribute(start, "onOffInteract");
    if (on_off) return error.InvalidAdmEmissionProfileObjectInteraction;
    var attributes = xml.AttributeIterator.init(start.attributes);
    while (try attributes.next()) |attribute| {
        if (isXmlNamespaceDeclaration(attribute.name)) continue;
        const name = attribute.name;
        if (!std.mem.eql(u8, name, "onOffInteract") and
            !std.mem.eql(u8, name, "gainInteract") and
            !std.mem.eql(u8, name, "positionInteract"))
        {
            return error.InvalidAdmEmissionProfileInteractionAttribute;
        }
    }

    var gain_minimum: ?f64 = null;
    var gain_maximum: ?f64 = null;
    var gain_minimum_parameter: ?Gain = null;
    var gain_maximum_parameter: ?Gain = null;
    var position_coordinate: ?EmissionPositionCoordinate = null;
    var position_minimum: ?f64 = null;
    var position_maximum: ?f64 = null;
    while (try events.next()) |event| {
        switch (event) {
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileObjectInteraction;
            },
            .start => |element| {
                const name = element.localName();
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileObjectInteraction;
                if (std.mem.eql(u8, name, "gainInteractionRange")) {
                    const bound, const value, const parameter =
                        try readEmissionGainInteractionRange(events, element);
                    switch (bound) {
                        .minimum => {
                            if (gain_minimum != null)
                                return error.InvalidAdmEmissionProfileGainInteractionRange;
                            gain_minimum = value;
                            gain_minimum_parameter = parameter;
                        },
                        .maximum => {
                            if (gain_maximum != null)
                                return error.InvalidAdmEmissionProfileGainInteractionRange;
                            gain_maximum = value;
                            gain_maximum_parameter = parameter;
                        },
                    }
                    continue;
                }
                if (std.mem.eql(u8, name, "positionInteractionRange")) {
                    const coordinate, const bound, const value =
                        try readEmissionPositionInteractionRange(
                            events,
                            element,
                        );
                    if (position_coordinate) |existing| {
                        if (existing != coordinate)
                            return error.InvalidAdmEmissionProfilePositionInteractionRange;
                    } else {
                        position_coordinate = coordinate;
                    }
                    switch (bound) {
                        .minimum => {
                            if (position_minimum != null)
                                return error.InvalidAdmEmissionProfilePositionInteractionRange;
                            position_minimum = value;
                        },
                        .maximum => {
                            if (position_maximum != null)
                                return error.InvalidAdmEmissionProfilePositionInteractionRange;
                            position_maximum = value;
                        },
                    }
                    continue;
                }
                return error.InvalidAdmEmissionProfileInteractionSubelement;
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileObjectInteraction;
                }
                break;
            },
        }
    } else return error.InvalidAdmEmissionProfileObjectInteraction;

    if (result.gain_interact != null) {
        result.gain_range = .{
            .minimum = gain_minimum orelse
                return error.InvalidAdmEmissionProfileGainInteractionRange,
            .maximum = gain_maximum orelse
                return error.InvalidAdmEmissionProfileGainInteractionRange,
            .minimum_parameter = gain_minimum_parameter orelse
                return error.InvalidAdmEmissionProfileGainInteractionRange,
            .maximum_parameter = gain_maximum_parameter orelse
                return error.InvalidAdmEmissionProfileGainInteractionRange,
        };
    } else if (gain_minimum != null or gain_maximum != null) {
        return error.InvalidAdmEmissionProfileGainInteractionRange;
    }
    if (result.position_interact != null) {
        result.position_range = .{
            .coordinate = position_coordinate orelse
                return error.InvalidAdmEmissionProfilePositionInteractionRange,
            .minimum = position_minimum orelse
                return error.InvalidAdmEmissionProfilePositionInteractionRange,
            .maximum = position_maximum orelse
                return error.InvalidAdmEmissionProfilePositionInteractionRange,
        };
    } else if (position_coordinate != null or
        position_minimum != null or
        position_maximum != null)
    {
        return error.InvalidAdmEmissionProfilePositionInteractionRange;
    }
    return result;
}

const EmissionRangeBound = enum {
    minimum,
    maximum,
};

fn readEmissionGainInteractionRange(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !struct { EmissionRangeBound, f64, Gain } {
    const bound = try emissionRangeBound(start);
    const unit = try emissionGainUnitAttribute(start);
    try validateEmissionAttributes(
        start,
        &.{ "bound", "gainUnit" },
        error.InvalidAdmEmissionProfileGainInteractionRange,
    );
    var storage: [max_profile_text_bytes]u8 = undefined;
    const raw = try readEmissionSimpleElement(events, start, &storage);
    const parameter_value = try parseAdmMatrixGain(raw, unit);
    const linear = emissionGainLinear(parameter_value, unit);
    switch (bound) {
        .minimum => if (linear < 0.0 or linear > 1.0)
            return error.InvalidAdmEmissionProfileGainInteractionRange,
        .maximum => if (linear < 1.0 or
            linear > emissionMaximumLinearGain())
        {
            return error.InvalidAdmEmissionProfileGainInteractionRange;
        },
    }
    return .{
        bound,
        linear,
        .{ .value = parameter_value, .unit = unit },
    };
}

fn readEmissionPositionInteractionRange(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !struct { EmissionPositionCoordinate, EmissionRangeBound, f64 } {
    const coordinate = try emissionPositionCoordinate(start);
    const bound = try emissionRangeBound(start);
    try validateEmissionAttributes(
        start,
        &.{ "coordinate", "bound" },
        error.InvalidAdmEmissionProfilePositionInteractionRange,
    );
    var storage: [max_profile_text_bytes]u8 = undefined;
    const raw = try readEmissionSimpleElement(events, start, &storage);
    const value = try parseFiniteAdmFloat(raw);
    const limit: f64 = switch (coordinate) {
        .azimuth => 30.0,
        .x => 1.0,
    };
    switch (bound) {
        .minimum => if (value < -limit or value > 0.0)
            return error.InvalidAdmEmissionProfilePositionInteractionRange,
        .maximum => if (value < 0.0 or value > limit)
            return error.InvalidAdmEmissionProfilePositionInteractionRange,
    }
    return .{ coordinate, bound, value };
}

pub fn readEmissionGain(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !Gain {
    const unit = try emissionGainUnitAttribute(start);
    try validateEmissionAttributes(
        start,
        &.{"gainUnit"},
        error.InvalidAdmEmissionProfileObjectGain,
    );
    var storage: [max_profile_text_bytes]u8 = undefined;
    const raw = try readEmissionSimpleElement(events, start, &storage);
    const value = try parseAdmMatrixGain(raw, unit);
    const linear = emissionGainLinear(value, unit);
    if (linear < 0.0 or linear > emissionMaximumLinearGain())
        return error.InvalidAdmEmissionProfileObjectGain;
    return .{ .value = value, .unit = unit };
}

pub fn readEmissionPositionOffset(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !EmissionPositionOffset {
    const coordinate = try emissionPositionCoordinate(start);
    try validateEmissionAttributes(
        start,
        &.{"coordinate"},
        error.InvalidAdmEmissionProfilePositionOffset,
    );
    var storage: [max_profile_text_bytes]u8 = undefined;
    const raw = try readEmissionSimpleElement(events, start, &storage);
    const value = try parseFiniteAdmFloat(raw);
    const limit: f64 = switch (coordinate) {
        .azimuth => 30.0,
        .x => 1.0,
    };
    if (value < -limit or value > limit)
        return error.InvalidAdmEmissionProfilePositionOffset;
    return .{ .coordinate = coordinate, .value = value };
}

pub fn readEmissionAlternativeValueSet(
    events: *MetadataEventIterator,
    start: xml.StartElement,
    parent_interaction: ?EmissionObjectInteraction,
) !EmissionAlternativeParameters {
    _ = try emissionElementIdentifier(
        start,
        "alternativeValueSetID",
        .alternative_value_set,
    );
    try validateEmissionAttributes(
        start,
        &.{"alternativeValueSetID"},
        error.InvalidAdmEmissionProfileAlternativeValueSet,
    );
    if (start.self_closing) return .{};

    var result = EmissionAlternativeParameters{};
    while (try events.next()) |event| {
        switch (event) {
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileAlternativeValueSet;
            },
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileAlternativeValueSet;
                const name = element.localName();
                if (std.mem.eql(u8, name, "gain")) {
                    if (result.gain != null)
                        return error.InvalidAdmEmissionProfileAlternativeValueSet;
                    result.gain = try readEmissionGain(events, element);
                    continue;
                }
                if (std.mem.eql(u8, name, "positionOffset")) {
                    if (result.position != null)
                        return error.InvalidAdmEmissionProfileAlternativeValueSet;
                    result.position = try readEmissionPositionOffset(
                        events,
                        element,
                    );
                    continue;
                }
                if (std.mem.eql(u8, name, "audioObjectInteraction")) {
                    if (result.interaction != null or
                        parent_interaction == null)
                    {
                        return error.InvalidAdmEmissionProfileAlternativeInteraction;
                    }
                    result.interaction = try readEmissionObjectInteraction(
                        events,
                        element,
                    );
                    continue;
                }
                return error.InvalidAdmEmissionProfileAlternativeValueSet;
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileAlternativeValueSet;
                }
                break;
            },
        }
    } else return error.InvalidAdmEmissionProfileAlternativeValueSet;

    if (result.interaction) |alternative| {
        const parent = parent_interaction orelse
            return error.InvalidAdmEmissionProfileAlternativeInteraction;
        if (!emissionInteractionBaseEqual(
            parent,
            alternative,
        )) {
            return error.InvalidAdmEmissionProfileAlternativeInteraction;
        }
    }
    if (parent_interaction) |parent| {
        try validateEmissionGainWithinRange(
            if (result.gain) |value|
                emissionGainLinear(value.value, value.unit)
            else
                1.0,
            parent.gain_range,
        );
        try validateEmissionPositionWithinRange(
            result.position,
            parent.position_range,
        );
    }
    return result;
}

pub fn validateEmissionGainWithinRange(
    gain: f64,
    range: ?EmissionInteractionRange,
) !void {
    const bounds = range orelse return;
    if (gain < bounds.minimum or gain > bounds.maximum)
        return error.AdmEmissionProfileGainOutsideInteractionRange;
}

pub fn validateEmissionPositionWithinRange(
    position: ?EmissionPositionOffset,
    range: ?EmissionPositionRange,
) !void {
    const offset = position orelse return;
    const bounds = range orelse return;
    if (offset.coordinate != bounds.coordinate or
        offset.value < bounds.minimum or
        offset.value > bounds.maximum)
    {
        return error.AdmEmissionProfilePositionOutsideInteractionRange;
    }
}

fn emissionInteractionBaseEqual(
    parent: EmissionObjectInteraction,
    alternative: EmissionObjectInteraction,
) bool {
    return std.meta.eql(parent.gain_range, alternative.gain_range) and
        std.meta.eql(parent.position_range, alternative.position_range);
}

pub fn emissionObjectParametersEqual(
    left: EmissionObjectParameterState,
    right: EmissionObjectParameterState,
) bool {
    return left.interact == right.interact and
        std.meta.eql(left.interaction, right.interaction) and
        std.meta.eql(left.gain, right.gain) and
        std.meta.eql(left.position, right.position);
}

pub fn emissionObjectBlockHasNeutralPosition(block: BlockFormat) bool {
    var first_required = false;
    var second_required = false;
    for (block.positionSlice()) |position| {
        if (position.bound != .exact) return false;
        if (block.cartesian) {
            switch (position.coordinate) {
                .x => {
                    if (position.value != 0.0) return false;
                    first_required = true;
                },
                .y => {
                    if (position.value != 1.0) return false;
                    second_required = true;
                },
                .z => if (position.value != 0.0) return false,
                else => return false,
            }
        } else {
            switch (position.coordinate) {
                .azimuth => {
                    if (position.value != 0.0) return false;
                    first_required = true;
                },
                .elevation => {
                    if (position.value != 0.0) return false;
                    second_required = true;
                },
                .distance => if (position.value != 1.0) return false,
                else => return false,
            }
        }
    }
    return first_required and second_required;
}

fn emissionMaximumLinearGain() f64 {
    return std.math.pow(f64, 10.0, 21.0 / 20.0);
}

pub fn emissionGainLinear(value: f64, unit: GainUnit) f64 {
    return switch (unit) {
        .linear => value,
        .decibels => if (std.math.isInf(value) and value < 0.0)
            0.0
        else
            std.math.pow(f64, 10.0, value / 20.0),
    };
}

fn emissionGainUnitAttribute(start: xml.StartElement) !GainUnit {
    const encoded = try start.attribute("gainUnit") orelse
        return GainUnit.linear;
    var storage: [16]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    return parseGainUnit(raw);
}

fn emissionPositionCoordinate(
    start: xml.StartElement,
) !EmissionPositionCoordinate {
    const encoded = try start.attribute("coordinate") orelse
        return error.MissingAdmEmissionProfileCoordinate;
    var storage: [16]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    if (std.mem.eql(u8, raw, "azimuth")) return .azimuth;
    if (std.mem.eql(u8, raw, "X")) return .x;
    return error.InvalidAdmEmissionProfileCoordinate;
}

fn emissionRangeBound(start: xml.StartElement) !EmissionRangeBound {
    const encoded = try start.attribute("bound") orelse
        return error.MissingAdmEmissionProfileRangeBound;
    var storage: [8]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    if (std.mem.eql(u8, raw, "min")) return .minimum;
    if (std.mem.eql(u8, raw, "max")) return .maximum;
    return error.InvalidAdmEmissionProfileRangeBound;
}

pub fn validateEmissionAttributes(
    start: xml.StartElement,
    allowed: []const []const u8,
    invalid_error: anyerror,
) !void {
    return validateAdmAttributes(start, allowed, invalid_error);
}

pub fn validateAdmAttributes(
    start: xml.StartElement,
    allowed: []const []const u8,
    invalid_error: anyerror,
) !void {
    var attributes = xml.AttributeIterator.init(start.attributes);
    while (try attributes.next()) |attribute| {
        if (isXmlNamespaceDeclaration(attribute.name)) continue;
        for (allowed) |name| {
            if (std.mem.eql(u8, attribute.name, name)) break;
        } else return invalid_error;
    }
}

pub fn readEmissionSimpleElement(
    events: *MetadataEventIterator,
    start: xml.StartElement,
    decoded_storage: []u8,
) ![]const u8 {
    if (start.self_closing) return error.EmptyAdmEmissionProfileParameter;
    var encoded_storage: [max_profile_text_bytes * 5]u8 = undefined;
    var encoded_bytes: usize = 0;
    while (try events.next()) |event| {
        switch (event) {
            .text => |text| {
                encoded_bytes = xml.appendEncodedText(
                    &encoded_storage,
                    encoded_bytes,
                    text,
                ) catch return error.AdmEmissionProfileParameterTooLong;
            },
            .start => return error.NestedAdmEmissionProfileParameter,
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileParameter;
                }
                const encoded = std.mem.trim(
                    u8,
                    encoded_storage[0..encoded_bytes],
                    " \t\r\n",
                );
                const decoded = xml.decodeContent(
                    decoded_storage,
                    encoded,
                ) catch |err| switch (err) {
                    error.XmlDecodeBufferTooSmall => return error.AdmEmissionProfileParameterTooLong,
                    else => return err,
                };
                const trimmed = std.mem.trim(u8, decoded, " \t\r\n");
                if (trimmed.len == 0)
                    return error.EmptyAdmEmissionProfileParameter;
                return trimmed;
            },
        }
    }
    return error.UnclosedAdmEmissionProfileParameter;
}

fn readEmissionProfileLabel(
    events: *MetadataEventIterator,
    start: xml.StartElement,
    languages: *EmissionLanguageSet,
) !void {
    try validateEmissionAttributes(
        start,
        &.{"language"},
        error.InvalidAdmEmissionProfileLabelAttribute,
    );
    const language = try emissionRequiredLanguageAttribute(
        start,
        "language",
    );
    try languages.note(language);
    var storage: [max_emission_name_bytes]u8 = undefined;
    const value = readEmissionSimpleElement(
        events,
        start,
        &storage,
    ) catch |err| switch (err) {
        error.AdmEmissionProfileParameterTooLong,
        error.EmptyAdmEmissionProfileParameter,
        => return error.InvalidAdmEmissionProfileLabel,
        else => return err,
    };
    const characters = utf8ScalarCount(value);
    if (characters == 0 or characters > 64)
        return error.InvalidAdmEmissionProfileLabel;
}

fn readEmissionLoudnessMetadata(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{},
        error.InvalidAdmEmissionProfileLoudnessAttribute,
    );
    if (start.self_closing)
        return error.MissingAdmEmissionProfileLoudnessValue;
    var integrated_seen = false;
    var dialogue_seen = false;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileLoudnessSubelement;
                try validateEmissionAttributes(
                    element,
                    &.{},
                    error.InvalidAdmEmissionProfileLoudnessAttribute,
                );
                const name = element.localName();
                const seen = if (std.mem.eql(
                    u8,
                    name,
                    "integratedLoudness",
                ))
                    &integrated_seen
                else if (std.mem.eql(
                    u8,
                    name,
                    "dialogueLoudness",
                ))
                    &dialogue_seen
                else
                    return error.InvalidAdmEmissionProfileLoudnessSubelement;
                if (seen.*)
                    return error.DuplicateAdmEmissionProfileLoudnessValue;
                seen.* = true;
                var storage: [max_profile_text_bytes]u8 = undefined;
                const raw = try readEmissionSimpleElement(
                    events,
                    element,
                    &storage,
                );
                const value = std.fmt.parseFloat(f64, raw) catch
                    return error.InvalidAdmEmissionProfileLoudnessValue;
                if (!std.math.isFinite(value))
                    return error.InvalidAdmEmissionProfileLoudnessValue;
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileLoudnessSubelement;
                }
                if (!integrated_seen and !dialogue_seen)
                    return error.MissingAdmEmissionProfileLoudnessValue;
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileLoudnessSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileLoudnessSubelement;
}

fn readEmissionDialogue(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    var storage: [16]u8 = undefined;
    const raw = try readEmissionSimpleElement(events, start, &storage);
    const dialogue = std.fmt.parseInt(u8, raw, 10) catch
        return error.InvalidAdmEmissionProfileDialogue;
    const attribute_name: []const u8, const maximum: u8 = switch (dialogue) {
        0 => .{ "nonDialogueContentKind", 3 },
        1 => .{ "dialogueContentKind", 6 },
        2 => .{ "mixedContentKind", 4 },
        else => return error.InvalidAdmEmissionProfileDialogue,
    };
    try validateEmissionAttributes(
        start,
        &.{attribute_name},
        error.InvalidAdmEmissionProfileDialogueAttribute,
    );
    const encoded_kind = try start.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileDialogueKind;
    var kind_storage: [16]u8 = undefined;
    const raw_kind = try xml.decodeContent(&kind_storage, encoded_kind);
    const kind = std.fmt.parseInt(u8, raw_kind, 10) catch
        return error.InvalidAdmEmissionProfileDialogueKind;
    if (kind > maximum)
        return error.InvalidAdmEmissionProfileDialogueKind;
}

fn readEmissionReferenceElement(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{},
        error.InvalidAdmEmissionProfileReferenceAttribute,
    );
    var storage: [max_identifier_bytes]u8 = undefined;
    _ = try readEmissionSimpleElement(events, start, &storage);
}

pub fn emissionSerialTimeAttribute(
    element: xml.StartElement,
    attribute_name: []const u8,
) !adm_time.Value {
    const encoded = try element.attribute(attribute_name) orelse
        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
    var storage: [64]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    return adm_time.Value.parse(raw) catch
        return error.InvalidAdmEmissionProfileSerialFrameTime;
}

pub fn decodeEmissionSerialFlowIdentifier(encoded: []const u8) ![36]u8 {
    var result: [36]u8 = undefined;
    var storage: [36]u8 = undefined;
    const raw = xml.decodeContent(&storage, encoded) catch
        return error.InvalidAdmEmissionProfileSerialFlowIdentifier;
    if (raw.len != result.len)
        return error.InvalidAdmEmissionProfileSerialFlowIdentifier;
    for (raw, 0..) |byte, index| {
        const separator = index == 8 or index == 13 or
            index == 18 or index == 23;
        if ((separator and byte != '-') or
            (!separator and !std.ascii.isHex(byte)))
        {
            return error.InvalidAdmEmissionProfileSerialFlowIdentifier;
        }
    }
    @memcpy(&result, raw);
    return result;
}

pub fn sumAdmTime(
    left: adm_time.Value,
    right: adm_time.Value,
) ?adm_time.Value {
    if (left.fractional_denominator == 0 or
        right.fractional_denominator == 0)
    {
        return null;
    }
    const divisor = greatestCommonDivisor(
        left.fractional_denominator,
        right.fractional_denominator,
    );
    const left_scale = right.fractional_denominator / divisor;
    const denominator = std.math.mul(
        u64,
        left.fractional_denominator,
        left_scale,
    ) catch return null;
    const right_scale = denominator / right.fractional_denominator;
    const numerator =
        @as(u128, left.fractional_numerator) * left_scale +
        @as(u128, right.fractional_numerator) * right_scale;
    const carry = numerator / denominator;
    if (carry > std.math.maxInt(u64)) return null;
    const whole = std.math.add(
        u64,
        left.whole_seconds,
        right.whole_seconds,
    ) catch return null;
    return .{
        .whole_seconds = std.math.add(
            u64,
            whole,
            @intCast(carry),
        ) catch return null,
        .fractional_numerator = @intCast(numerator % denominator),
        .fractional_denominator = denominator,
        .format = left.format,
    };
}

fn greatestCommonDivisor(left: u64, right: u64) u64 {
    var a = left;
    var b = right;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

fn readEmissionSerialFrameFormat(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{
            "frameFormatID",
            "start",
            "duration",
            "type",
            "timeReference",
            "flowID",
        },
        error.InvalidAdmEmissionProfileSerialFrameFormatAttribute,
    );
    const encoded_identifier = try start.attribute("frameFormatID") orelse
        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
    var identifier_storage: [32]u8 = undefined;
    const identifier = try xml.decodeContent(
        &identifier_storage,
        encoded_identifier,
    );
    if (identifier.len != 11 or
        !std.mem.eql(u8, identifier[0..3], "FF_"))
    {
        return error.InvalidAdmEmissionProfileSerialFrameFormatIdentifier;
    }
    for (identifier[3..]) |byte| {
        if (!std.ascii.isHex(byte))
            return error.InvalidAdmEmissionProfileSerialFrameFormatIdentifier;
    }

    for ([_][]const u8{ "start", "duration" }) |attribute_name| {
        const encoded = try start.attribute(attribute_name) orelse
            return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
        var storage: [64]u8 = undefined;
        const raw = try xml.decodeContent(&storage, encoded);
        const value = adm_time.Value.parse(raw) catch
            return error.InvalidAdmEmissionProfileSerialFrameTime;
        if (std.mem.eql(u8, attribute_name, "duration")) {
            const minimum = adm_time.Value{
                .whole_seconds = 0,
                .fractional_numerator = 5,
                .fractional_denominator = 1000,
                .format = .decimal,
            };
            if (value.compare(minimum) == .lt)
                return error.InvalidAdmEmissionProfileSerialFrameDuration;
        }
    }

    const encoded_type = try start.attribute("type") orelse
        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
    var type_storage: [16]u8 = undefined;
    const frame_type = try xml.decodeContent(&type_storage, encoded_type);
    if (!std.mem.eql(u8, frame_type, "header") and
        !std.mem.eql(u8, frame_type, "full"))
    {
        return error.InvalidAdmEmissionProfileSerialFrameType;
    }
    try emissionRequiredAttributeValueAs(
        start,
        "timeReference",
        "local",
        error.MissingAdmEmissionProfileSerialFrameFormatAttribute,
        error.InvalidAdmEmissionProfileSerialFrameFormatAttribute,
    );
    if (try start.attribute("flowID")) |encoded_flow_id|
        _ = try decodeEmissionSerialFlowIdentifier(encoded_flow_id);
    if (start.self_closing) return;
    while (try events.next()) |event| {
        switch (event) {
            .start => return error.InvalidAdmEmissionProfileSerialFrameFormatSubelement,
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileSerialFrameFormatSubelement;
                }
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileSerialFrameFormatSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileSerialFrameFormat;
}

pub fn readEmissionSerialFrameHeader(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{},
        error.InvalidAdmEmissionProfileSerialFrameHeaderAttribute,
    );
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileSerialFrameHeader;
    var frame_format_count: usize = 0;
    var transport_count: usize = 0;
    var profile_list_count: usize = 0;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileSerialFrameHeaderSubelement;
                const name = element.localName();
                if (std.mem.eql(u8, name, "frameFormat")) {
                    frame_format_count += 1;
                    if (frame_format_count > 1)
                        return error.InvalidAdmEmissionProfileSerialFrameHeader;
                    try readEmissionSerialFrameFormat(events, element);
                } else if (std.mem.eql(
                    u8,
                    name,
                    "transportTrackFormat",
                )) {
                    transport_count += 1;
                    try skipEmissionElement(events, element);
                } else if (std.mem.eql(u8, name, "profileList")) {
                    profile_list_count += 1;
                    if (profile_list_count > 1)
                        return error.InvalidAdmEmissionProfileSerialFrameHeader;
                    try skipEmissionElement(events, element);
                } else {
                    return error.InvalidAdmEmissionProfileSerialFrameHeaderSubelement;
                }
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileSerialFrameHeaderSubelement;
                }
                if (frame_format_count != 1 or
                    transport_count == 0 or
                    profile_list_count != 1)
                {
                    return error.InvalidAdmEmissionProfileSerialFrameHeader;
                }
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileSerialFrameHeaderSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileSerialFrameHeader;
}

fn readEmissionSerialAudioTrack(
    lookup: SerialLookup,
    events: *MetadataEventIterator,
    start: xml.StartElement,
    transport_identifier: []const u8,
) !void {
    try validateEmissionAttributes(
        start,
        &.{ "trackID", "formatLabel", "formatDefinition" },
        error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
    );
    const track_id = try emissionOptionalPositiveAttributeAs(
        start,
        "trackID",
        error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
    ) orelse return error.MissingAdmEmissionProfileSerialAudioTrackAttribute;
    if (try lookup.trackIdCount(
        transport_identifier,
        track_id,
    ) != 1) {
        return error.DuplicateAdmEmissionProfileSerialTrackIdentifier;
    }
    try emissionRequiredAttributeValueAs(
        start,
        "formatLabel",
        "0001",
        error.MissingAdmEmissionProfileSerialAudioTrackAttribute,
        error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
    );
    try emissionRequiredAttributeValueAs(
        start,
        "formatDefinition",
        "PCM",
        error.MissingAdmEmissionProfileSerialAudioTrackAttribute,
        error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
    );
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileSerialAudioTrack;
    var reference_count: usize = 0;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1 or
                    !std.mem.eql(
                        u8,
                        element.localName(),
                        "audioTrackUIDRef",
                    ))
                {
                    return error.InvalidAdmEmissionProfileSerialAudioTrackSubelement;
                }
                reference_count += 1;
                if (reference_count > 1)
                    return error.InvalidAdmEmissionProfileSerialAudioTrack;
                try validateEmissionAttributes(
                    element,
                    &.{},
                    error.InvalidAdmEmissionProfileReferenceAttribute,
                );
                var storage: [max_identifier_bytes]u8 = undefined;
                const raw = try readEmissionSimpleElement(
                    events,
                    element,
                    &storage,
                );
                const identifier = try adm.Identifier.parse(raw);
                if (identifier.kind != .track_uid or identifier.primary == 0)
                    return error.InvalidAdmEmissionProfileSerialTrackReference;
                if (!try lookup.containsIdentifier(
                    .track_uid,
                    identifier.primary,
                    identifier.secondary,
                )) {
                    return error.InvalidAdmEmissionProfileSerialTrackReference;
                }
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileSerialAudioTrackSubelement;
                }
                if (reference_count != 1)
                    return error.InvalidAdmEmissionProfileSerialAudioTrack;
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileSerialAudioTrackSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileSerialAudioTrack;
}

pub fn readEmissionSerialTransport(
    lookup: SerialLookup,
    events: *MetadataEventIterator,
    start: xml.StartElement,
    declared_tracks: usize,
) !void {
    try validateEmissionAttributes(
        start,
        &.{ "transportID", "transportName", "numTracks", "numIDs" },
        error.InvalidAdmEmissionProfileSerialTransportAttribute,
    );
    const encoded_identifier = try start.attribute("transportID") orelse
        return error.MissingAdmEmissionProfileSerialTransportAttribute;
    var identifier_storage: [16]u8 = undefined;
    const identifier = try xml.decodeContent(
        &identifier_storage,
        encoded_identifier,
    );
    if (identifier.len != 7 or
        !std.mem.eql(u8, identifier[0..3], "TP_"))
    {
        return error.InvalidAdmEmissionProfileSerialTransportIdentifier;
    }
    for (identifier[3..]) |byte| {
        if (!std.ascii.isHex(byte))
            return error.InvalidAdmEmissionProfileSerialTransportIdentifier;
    }
    if (try lookup.transportIdCount(identifier) != 1)
        return error.DuplicateAdmEmissionProfileSerialTransportIdentifier;
    try validateEmissionRequiredName(start, "transportName");
    const num_tracks = try emissionOptionalPositiveAttributeAs(
        start,
        "numTracks",
        error.InvalidAdmEmissionProfileSerialTransportAttribute,
    ) orelse return error.MissingAdmEmissionProfileSerialTransportAttribute;
    const num_ids = try emissionOptionalPositiveAttributeAs(
        start,
        "numIDs",
        error.InvalidAdmEmissionProfileSerialTransportAttribute,
    ) orelse return error.MissingAdmEmissionProfileSerialTransportAttribute;
    if (num_tracks != num_ids or num_ids > declared_tracks)
        return error.InvalidAdmEmissionProfileSerialTransportCount;
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileSerialTransport;

    var audio_track_count: usize = 0;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1 or
                    !std.mem.eql(u8, element.localName(), "audioTrack"))
                {
                    return error.InvalidAdmEmissionProfileSerialTransportSubelement;
                }
                audio_track_count += 1;
                try readEmissionSerialAudioTrack(
                    lookup,
                    events,
                    element,
                    identifier,
                );
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileSerialTransportSubelement;
                }
                if (audio_track_count != num_tracks)
                    return error.InvalidAdmEmissionProfileSerialTransportCount;
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileSerialTransportSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileSerialTransport;
}

pub fn readEmissionProgrammeMetadata(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{
            "audioProgrammeID",
            "audioProgrammeName",
            "audioProgrammeLanguage",
        },
        error.InvalidAdmEmissionProfileProgrammeAttribute,
    );
    try validateEmissionRequiredName(start, "audioProgrammeName");
    _ = try emissionRequiredLanguageAttribute(
        start,
        "audioProgrammeLanguage",
    );
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileProgrammeMetadata;

    var content_references: usize = 0;
    var loudness_count: usize = 0;
    var label_languages = EmissionLanguageSet{};
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileProgrammeSubelement;
                const name = element.localName();
                if (std.mem.eql(u8, name, "audioContentIDRef")) {
                    content_references += 1;
                    try readEmissionReferenceElement(events, element);
                } else if (std.mem.eql(
                    u8,
                    name,
                    "audioProgrammeLabel",
                )) {
                    try readEmissionProfileLabel(
                        events,
                        element,
                        &label_languages,
                    );
                } else if (std.mem.eql(
                    u8,
                    name,
                    "loudnessMetadata",
                )) {
                    loudness_count += 1;
                    if (loudness_count > 1)
                        return error.DuplicateAdmEmissionProfileLoudnessMetadata;
                    try readEmissionLoudnessMetadata(events, element);
                } else if (std.mem.eql(
                    u8,
                    name,
                    "alternativeValueSetIDRef",
                )) {
                    try readEmissionReferenceElement(events, element);
                } else {
                    return error.InvalidAdmEmissionProfileProgrammeSubelement;
                }
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileProgrammeSubelement;
                }
                if (content_references == 0)
                    return error.MissingAdmEmissionProfileProgrammeContent;
                if (loudness_count != 1)
                    return error.MissingAdmEmissionProfileLoudnessMetadata;
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileProgrammeSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileProgrammeMetadata;
}

pub fn readEmissionContentMetadata(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    try validateEmissionAttributes(
        start,
        &.{
            "audioContentID",
            "audioContentName",
            "audioContentLanguage",
        },
        error.InvalidAdmEmissionProfileContentAttribute,
    );
    try validateEmissionRequiredName(start, "audioContentName");
    _ = try emissionRequiredLanguageAttribute(
        start,
        "audioContentLanguage",
    );
    if (start.self_closing)
        return error.InvalidAdmEmissionProfileContentMetadata;

    var object_references: usize = 0;
    var loudness_count: usize = 0;
    var dialogue_count: usize = 0;
    var label_languages = EmissionLanguageSet{};
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileContentSubelement;
                const name = element.localName();
                if (std.mem.eql(u8, name, "audioObjectIDRef")) {
                    object_references += 1;
                    if (object_references > 1)
                        return error.InvalidAdmEmissionProfileContentReference;
                    try readEmissionReferenceElement(events, element);
                } else if (std.mem.eql(
                    u8,
                    name,
                    "audioContentLabel",
                )) {
                    try readEmissionProfileLabel(
                        events,
                        element,
                        &label_languages,
                    );
                } else if (std.mem.eql(
                    u8,
                    name,
                    "loudnessMetadata",
                )) {
                    loudness_count += 1;
                    if (loudness_count > 1)
                        return error.DuplicateAdmEmissionProfileLoudnessMetadata;
                    try readEmissionLoudnessMetadata(events, element);
                } else if (std.mem.eql(u8, name, "dialogue")) {
                    dialogue_count += 1;
                    if (dialogue_count > 1)
                        return error.DuplicateAdmEmissionProfileDialogue;
                    try readEmissionDialogue(events, element);
                } else {
                    return error.InvalidAdmEmissionProfileContentSubelement;
                }
            },
            .end => |element| {
                if (element.depth != start.depth or
                    !std.mem.eql(u8, element.name, start.name))
                {
                    return error.InvalidAdmEmissionProfileContentSubelement;
                }
                if (object_references != 1)
                    return error.InvalidAdmEmissionProfileContentReference;
                if (loudness_count != 1)
                    return error.MissingAdmEmissionProfileLoudnessMetadata;
                if (dialogue_count != 1)
                    return error.MissingAdmEmissionProfileDialogue;
                return;
            },
            .text => |text| {
                if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    return error.InvalidAdmEmissionProfileContentSubelement;
            },
        }
    }
    return error.InvalidAdmEmissionProfileContentMetadata;
}

pub fn noteEmissionFormatChild(
    owner: *EmissionFormatOwner,
    element: xml.StartElement,
) !void {
    const name = element.localName();
    switch (owner.kind) {
        .matrix_pack => {
            if (std.mem.eql(u8, name, "audioChannelFormatIDRef")) {
                owner.channel_references += 1;
            } else if (std.mem.eql(u8, name, "inputPackFormatIDRef")) {
                owner.input_references += 1;
            } else if (std.mem.eql(u8, name, "outputPackFormatIDRef")) {
                owner.output_references += 1;
            } else {
                return error.InvalidAdmEmissionProfilePackSubelement;
            }
            try validateEmissionAttributes(
                element,
                &.{},
                error.InvalidAdmEmissionProfileReferenceAttribute,
            );
        },
        .objects_pack => {
            if (!std.mem.eql(u8, name, "audioChannelFormatIDRef"))
                return error.InvalidAdmEmissionProfilePackSubelement;
            owner.channel_references += 1;
            try validateEmissionAttributes(
                element,
                &.{},
                error.InvalidAdmEmissionProfileReferenceAttribute,
            );
        },
        .matrix_channel => {
            if (!std.mem.eql(u8, name, "audioBlockFormatMatrix"))
                return error.InvalidAdmEmissionProfileChannelSubelement;
            owner.block_count += 1;
        },
        .objects_channel => {
            if (!std.mem.eql(u8, name, "audioBlockFormatObjects"))
                return error.InvalidAdmEmissionProfileChannelSubelement;
            owner.block_count += 1;
        },
        .track_uid => {
            if (std.mem.eql(u8, name, "audioPackFormatIDRef")) {
                owner.pack_references += 1;
            } else if (std.mem.eql(
                u8,
                name,
                "audioChannelFormatIDRef",
            )) {
                owner.channel_references += 1;
            } else {
                return error.InvalidAdmEmissionProfileTrackSubelement;
            }
            try validateEmissionAttributes(
                element,
                &.{},
                error.InvalidAdmEmissionProfileReferenceAttribute,
            );
        },
    }
}

pub fn validateEmissionFormatOwner(owner: EmissionFormatOwner) !void {
    switch (owner.kind) {
        .matrix_pack => {
            if (owner.channel_references == 0 or
                owner.channel_references > 24 or
                owner.input_references != 1 or
                owner.output_references != 1)
            {
                return error.InvalidAdmEmissionProfilePackStructure;
            }
        },
        .objects_pack => {
            if (owner.channel_references != 1)
                return error.InvalidAdmEmissionProfilePackStructure;
        },
        .matrix_channel => {
            if (owner.block_count != 1)
                return error.InvalidAdmEmissionProfileChannelStructure;
        },
        .objects_channel => {
            if (owner.block_count == 0)
                return error.InvalidAdmEmissionProfileChannelStructure;
        },
        .track_uid => {
            if (owner.pack_references != 1 or
                owner.channel_references != 1)
            {
                return error.InvalidAdmEmissionProfileTrackStructure;
            }
        },
    }
}

pub fn readEmissionObjectBlockSyntax(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    return readEmissionObjectBlockSyntaxWithTiming(events, start, .file);
}

const EmissionBlockTiming = enum {
    file,
    serial,
};

pub fn readEmissionObjectBlockSyntaxWithTiming(
    events: *MetadataEventIterator,
    start: xml.StartElement,
    timing: EmissionBlockTiming,
) !void {
    switch (timing) {
        .file => {
            try validateEmissionAttributes(
                start,
                &.{ "audioBlockFormatID", "rtime", "duration" },
                error.InvalidAdmEmissionProfileBlockAttribute,
            );
            if (try start.attribute("rtime") == null or
                try start.attribute("duration") == null)
            {
                return error.MissingAdmEmissionProfileBlockTiming;
            }
        },
        .serial => {
            try validateEmissionAttributes(
                start,
                &.{
                    "audioBlockFormatID",
                    "initializeBlock",
                    "lstart",
                    "lduration",
                },
                error.InvalidAdmEmissionProfileSerialBlockAttribute,
            );
            const initialize = try start.attribute("initializeBlock");
            const lstart = try start.attribute("lstart");
            const lduration = try start.attribute("lduration");
            if (initialize) |_| {
                try emissionRequiredAttributeValueAs(
                    start,
                    "initializeBlock",
                    "1",
                    error.InvalidAdmEmissionProfileSerialInitializeBlock,
                    error.InvalidAdmEmissionProfileSerialInitializeBlock,
                );
                if (lstart != null or lduration != null)
                    return error.InvalidAdmEmissionProfileSerialInitializeBlock;
            } else if (lstart == null or lduration == null) {
                return error.MissingAdmEmissionProfileSerialBlockTiming;
            }
        },
    }
    if (start.self_closing) return;

    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1)
                    return error.InvalidAdmEmissionProfileBlockSubelement;
                const name = element.localName();
                if (std.mem.eql(u8, name, "cartesian")) {
                    try validateEmissionAttributes(
                        element,
                        &.{},
                        error.InvalidAdmEmissionProfileBlockParameterAttribute,
                    );
                    var storage: [max_profile_text_bytes]u8 = undefined;
                    const value = try readEmissionSimpleElement(
                        events,
                        element,
                        &storage,
                    );
                    if (!std.mem.eql(u8, value, "1"))
                        return error.InvalidAdmEmissionProfileCartesianFlag;
                } else if (std.mem.eql(u8, name, "position")) {
                    try validateEmissionAttributes(
                        element,
                        &.{"coordinate"},
                        error.InvalidAdmEmissionProfileBlockParameterAttribute,
                    );
                    if (try element.attribute("coordinate") == null)
                        return error.InvalidAdmEmissionProfileBlockPosition;
                } else if (std.mem.eql(u8, name, "objectDivergence")) {
                    try validateEmissionAttributes(
                        element,
                        &.{ "azimuthRange", "positionRange" },
                        error.InvalidAdmEmissionProfileBlockParameterAttribute,
                    );
                    const azimuth_range =
                        try element.attribute("azimuthRange");
                    const position_range =
                        try element.attribute("positionRange");
                    if ((azimuth_range == null) == (position_range == null))
                        return error.InvalidAdmEmissionProfileObjectDivergence;
                } else if (std.mem.eql(u8, name, "gain")) {
                    try validateEmissionAttributes(
                        element,
                        &.{"gainUnit"},
                        error.InvalidAdmEmissionProfileBlockParameterAttribute,
                    );
                } else if (std.mem.eql(u8, name, "jumpPosition")) {
                    try validateEmissionAttributes(
                        element,
                        &.{"interpolationLength"},
                        error.InvalidAdmEmissionProfileBlockParameterAttribute,
                    );
                } else {
                    return error.InvalidAdmEmissionProfileBlockSubelement;
                }
            },
            .end => |element| {
                if (element.depth == start.depth and
                    std.mem.eql(u8, element.name, start.name))
                {
                    return;
                }
            },
            .text => |text| {
                if (text.depth == start.depth + 1 and
                    std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                {
                    return error.InvalidAdmEmissionProfileBlockSubelement;
                }
            },
        }
    }
    return error.InvalidAdmEmissionProfileBlockSubelement;
}

const EmissionObjectLabels = struct {
    languages: EmissionLanguageSet = .{},
    complementary_references: usize = 0,
    label_count: usize = 0,
};

pub fn readEmissionObjectLabels(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !EmissionObjectLabels {
    var result = EmissionObjectLabels{};
    if (start.self_closing) return result;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth != start.depth + 1) continue;
                const name = element.localName();
                if (std.mem.eql(
                    u8,
                    name,
                    "audioComplementaryObjectGroupLabel",
                )) {
                    result.label_count += 1;
                    try readEmissionProfileLabel(
                        events,
                        element,
                        &result.languages,
                    );
                } else if (std.mem.eql(
                    u8,
                    name,
                    "audioComplementaryObjectIDRef",
                )) {
                    result.complementary_references += 1;
                    try readEmissionReferenceElement(events, element);
                } else if (std.mem.eql(
                    u8,
                    name,
                    "audioPackFormatIDRef",
                ) or std.mem.eql(
                    u8,
                    name,
                    "audioObjectIDRef",
                ) or std.mem.eql(
                    u8,
                    name,
                    "audioTrackUIDRef",
                )) {
                    try readEmissionReferenceElement(events, element);
                }
            },
            .end => |element| {
                if (element.depth == start.depth and
                    std.mem.eql(u8, element.name, start.name))
                {
                    if (result.label_count != 0 and
                        result.complementary_references == 0)
                    {
                        return error.InvalidAdmEmissionProfileComplementaryLabelOwner;
                    }
                    return result;
                }
            },
            else => {},
        }
    }
    return error.InvalidAdmEmissionProfileComplementaryLabel;
}

pub fn readEmissionOwnerLabelLanguages(
    events: *MetadataEventIterator,
    start: xml.StartElement,
    label_name: []const u8,
) !EmissionLanguageSet {
    var languages = EmissionLanguageSet{};
    if (start.self_closing) return languages;
    while (try events.next()) |event| {
        switch (event) {
            .start => |element| {
                if (element.depth == start.depth + 1 and
                    std.mem.eql(u8, element.localName(), label_name))
                {
                    try readEmissionProfileLabel(
                        events,
                        element,
                        &languages,
                    );
                }
            },
            .end => |element| {
                if (element.depth == start.depth and
                    std.mem.eql(u8, element.name, start.name))
                {
                    return languages;
                }
            },
            else => {},
        }
    }
    return error.InvalidAdmEmissionProfileLabel;
}

pub fn skipEmissionElement(
    events: *MetadataEventIterator,
    start: xml.StartElement,
) !void {
    if (start.self_closing) return;
    while (try events.next()) |event| {
        switch (event) {
            .end => |element| {
                if (element.depth == start.depth and
                    std.mem.eql(u8, element.name, start.name))
                {
                    return;
                }
            },
            else => {},
        }
    }
    return error.UnclosedAdmEmissionProfileParameter;
}

pub fn emissionElementTypeLabel(
    element: xml.StartElement,
    identifier_attribute: []const u8,
) !u16 {
    const encoded = try element.attribute(identifier_attribute) orelse
        return error.MissingAdmIdentifier;
    var storage: [max_identifier_bytes]u8 = undefined;
    const raw = try xml.decodeContent(&storage, encoded);
    const identifier = try adm.Identifier.parse(raw);
    return identifier.typeLabel() orelse
        error.InvalidAdmEmissionProfileFormat;
}

pub fn profilesEqual(left: Profile, right: Profile) bool {
    return std.mem.eql(u8, left.name, right.name) and
        std.mem.eql(u8, left.version, right.version) and
        std.mem.eql(u8, left.level, right.level) and
        std.mem.eql(u8, left.reference, right.reference);
}

pub fn isEmissionProfile(profile: Profile) bool {
    return std.mem.eql(
        u8,
        profile.name,
        "Advanced sound system: ADM and S-ADM profile for emission",
    ) and
        std.mem.eql(u8, profile.version, "1") and
        (std.mem.eql(u8, profile.level, "0") or
            std.mem.eql(u8, profile.level, "1") or
            std.mem.eql(u8, profile.level, "2")) and
        std.mem.eql(u8, profile.reference, "ITU-R BS.2168");
}
