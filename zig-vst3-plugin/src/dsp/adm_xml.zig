const std = @import("std");
const adm = @import("adm.zig");
const adm_time = @import("adm_time.zig");
const xml = @import("xml.zig");

const max_identifier_bytes: usize = 20;
const max_profile_text_bytes: usize = 128;
const max_emission_name_bytes: usize = 64 * 4;
const emission_language_word_count: usize = (26 * 26 * 26 + 63) / 64;
const iso_639_2_codes =
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

const EmissionObjectParent = struct {
    kind: adm.IdentifierKind,
    primary: u32,
};

const EmissionPackChannels = struct {
    primaries: [24]u32 = undefined,
    len: usize = 0,

    fn append(self: *EmissionPackChannels, primary: u32) !void {
        if (self.len == self.primaries.len)
            return error.AdmEmissionProfileLayoutChannelLimitExceeded;
        self.primaries[self.len] = primary;
        self.len += 1;
    }

    fn indexOf(self: EmissionPackChannels, primary: u32) ?usize {
        for (self.primaries[0..self.len], 0..) |candidate, index| {
            if (candidate == primary) return index;
        }
        return null;
    }
};

const EmissionMatrixPack = struct {
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

const EmissionObjectInteraction = struct {
    gain_interact: ?bool = null,
    position_interact: ?bool = null,
    gain_range: ?EmissionInteractionRange = null,
    position_range: ?EmissionPositionRange = null,
};

const EmissionPositionOffset = struct {
    coordinate: EmissionPositionCoordinate,
    value: f64,
};

const EmissionObjectParameterState = struct {
    primary: u32,
    top_level: bool,
    interact: bool,
    interaction: ?EmissionObjectInteraction = null,
    gain: ?Gain = null,
    position: ?EmissionPositionOffset = null,
    uses_position_controls: bool = false,
    has_alternative_value_sets: bool = false,
};

const EmissionAlternativeParameters = struct {
    gain: ?Gain = null,
    interaction: ?EmissionObjectInteraction = null,
    position: ?EmissionPositionOffset = null,

    fn usesPositionControls(self: EmissionAlternativeParameters) bool {
        return self.position != null or
            (self.interaction != null and
                self.interaction.?.position_range != null);
    }
};

const EmissionLanguageSet = struct {
    words: [emission_language_word_count]u64 = @splat(0),

    fn note(self: *EmissionLanguageSet, code: [3]u8) !void {
        const index = emissionLanguageIndex(code);
        const word = index / 64;
        const mask = @as(u64, 1) << @intCast(index % 64);
        if (self.words[word] & mask != 0)
            return error.DuplicateAdmEmissionProfileLabelLanguage;
        self.words[word] |= mask;
    }
};

const EmissionFormatOwnerKind = enum {
    matrix_pack,
    objects_pack,
    matrix_channel,
    objects_channel,
    track_uid,
};

const EmissionFormatOwner = struct {
    kind: EmissionFormatOwnerKind,
    depth: usize,
    channel_references: usize = 0,
    input_references: usize = 0,
    output_references: usize = 0,
    block_count: usize = 0,
    pack_references: usize = 0,
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

fn emissionMaximumLayoutChannels(
    level: EmissionProfileLevel,
) usize {
    return switch (level) {
        .level_0 => std.math.maxInt(usize),
        .level_1 => 12,
        .level_2 => 24,
    };
}

fn emissionComplementaryLimits(
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

fn commonEmissionPackChannelIndexes(
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

fn commonEmissionPackIsMatrixOutput(pack_index: u16) bool {
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

fn emissionCommonPackChannels(pack_primary: u32) !EmissionPackChannels {
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

fn validateEmissionMatrixCoefficients(
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

fn emissionElementIdentifier(
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

fn validateEmissionObjectAttributes(element: xml.StartElement) !void {
    var name_seen = false;
    var interact_seen = false;
    var attributes = xml.AttributeIterator.init(element.attributes);
    while (try attributes.next()) |attribute| {
        if (isXmlNamespaceDeclaration(attribute.name)) continue;
        const name = attribute.localName();
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

fn isIso6392Code(code: []const u8) bool {
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

fn emissionRequiredLanguageAttribute(
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

fn validateEmissionFormatDeclarationAttributes(
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

fn validateEmissionTrackUidAttributes(element: xml.StartElement) !void {
    try validateEmissionAttributes(
        element,
        &.{ "UID", "sampleRate", "bitDepth" },
        error.InvalidAdmEmissionProfileTrackAttribute,
    );
    for ([_][]const u8{ "sampleRate", "bitDepth" }) |attribute_name| {
        const encoded = try element.attribute(attribute_name);
        if (encoded == null) continue;
        var storage: [32]u8 = undefined;
        const raw = try xml.decodeContent(&storage, encoded.?);
        const value = std.fmt.parseInt(u32, raw, 10) catch
            return error.InvalidAdmEmissionProfileTrackAttribute;
        if (value == 0)
            return error.InvalidAdmEmissionProfileTrackAttribute;
    }
}

fn emissionRequiredFlagAttribute(
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

fn isEmissionObjectReferenceOrLabel(name: []const u8) bool {
    return std.mem.eql(u8, name, "audioPackFormatIDRef") or
        std.mem.eql(u8, name, "audioObjectIDRef") or
        std.mem.eql(u8, name, "audioTrackUIDRef") or
        std.mem.eql(u8, name, "audioComplementaryObjectGroupLabel") or
        std.mem.eql(u8, name, "audioComplementaryObjectIDRef");
}

fn readEmissionObjectInteraction(
    events: *xml.EventIterator,
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
        const name = attribute.localName();
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
    events: *xml.EventIterator,
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
    events: *xml.EventIterator,
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

fn readEmissionGain(
    events: *xml.EventIterator,
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

fn readEmissionPositionOffset(
    events: *xml.EventIterator,
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

fn readEmissionAlternativeValueSet(
    events: *xml.EventIterator,
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
        if (!emissionInteractionBaseEqual(
            parent_interaction.?,
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

fn validateEmissionGainWithinRange(
    gain: f64,
    range: ?EmissionInteractionRange,
) !void {
    const bounds = range orelse return;
    if (gain < bounds.minimum or gain > bounds.maximum)
        return error.AdmEmissionProfileGainOutsideInteractionRange;
}

fn validateEmissionPositionWithinRange(
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

fn emissionObjectParametersEqual(
    left: EmissionObjectParameterState,
    right: EmissionObjectParameterState,
) bool {
    return left.interact == right.interact and
        std.meta.eql(left.interaction, right.interaction) and
        std.meta.eql(left.gain, right.gain) and
        std.meta.eql(left.position, right.position);
}

fn emissionObjectBlockHasNeutralPosition(block: BlockFormat) bool {
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

fn emissionGainLinear(value: f64, unit: GainUnit) f64 {
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

fn validateEmissionAttributes(
    start: xml.StartElement,
    allowed: []const []const u8,
    invalid_error: anyerror,
) !void {
    var attributes = xml.AttributeIterator.init(start.attributes);
    while (try attributes.next()) |attribute| {
        if (isXmlNamespaceDeclaration(attribute.name)) continue;
        for (allowed) |name| {
            if (std.mem.eql(u8, attribute.localName(), name)) break;
        } else return invalid_error;
    }
}

fn readEmissionSimpleElement(
    events: *xml.EventIterator,
    start: xml.StartElement,
    decoded_storage: []u8,
) ![]const u8 {
    if (start.self_closing) return error.EmptyAdmEmissionProfileParameter;
    var encoded_storage: [max_profile_text_bytes * 5]u8 = undefined;
    var encoded_bytes: usize = 0;
    while (try events.next()) |event| {
        switch (event) {
            .text => |text| {
                const next_offset = std.math.add(
                    usize,
                    encoded_bytes,
                    text.bytes.len,
                ) catch return error.AdmEmissionProfileParameterTooLong;
                if (next_offset > encoded_storage.len)
                    return error.AdmEmissionProfileParameterTooLong;
                @memcpy(
                    encoded_storage[encoded_bytes..next_offset],
                    text.bytes,
                );
                encoded_bytes = next_offset;
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
    events: *xml.EventIterator,
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
    events: *xml.EventIterator,
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
    events: *xml.EventIterator,
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
    events: *xml.EventIterator,
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

fn readEmissionProgrammeMetadata(
    events: *xml.EventIterator,
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

fn readEmissionContentMetadata(
    events: *xml.EventIterator,
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

fn noteEmissionFormatChild(
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

fn validateEmissionFormatOwner(owner: EmissionFormatOwner) !void {
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

fn readEmissionObjectBlockSyntax(
    events: *xml.EventIterator,
    start: xml.StartElement,
) !void {
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

fn skipEmissionElement(
    events: *xml.EventIterator,
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

fn emissionElementTypeLabel(
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

fn isXmlNamespaceDeclaration(attribute_name: []const u8) bool {
    return std.mem.eql(u8, attribute_name, "xmlns") or
        std.mem.startsWith(u8, attribute_name, "xmlns:");
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

    /// Validates content reachability and the profile's object ownership
    /// and nesting constraints.
    pub fn validateEmissionProfileObjectTopology(self: Document) !void {
        try self.validateEmissionProfileIdentifiers();
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            switch (declaration.identifier.kind) {
                .content => try self.validateEmissionContentOwner(
                    declaration.identifier,
                ),
                .object => try self.validateEmissionObjectAncestry(
                    declaration.identifier,
                ),
                else => {},
            }
        }
    }

    /// Validates emission object sources through pack, channel, and track UID
    /// references, including the permitted common speaker layouts.
    pub fn validateEmissionProfileObjectSources(self: Document) !void {
        try self.validateEmissionProfileObjectTopology();
        const maximum_channels = emissionMaximumLayoutChannels(
            try self.emissionProfileLevel(),
        );

        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind == .object) {
                try self.validateEmissionObjectSource(
                    declaration.identifier.primary,
                    maximum_channels,
                );
            }
        }
        try self.validateEmissionFormatOwnership();
    }

    /// Validates emission downmix definitions against their common input and
    /// output layouts.
    pub fn validateEmissionProfileMatrices(self: Document) !void {
        try self.validateEmissionProfileObjectSources();
        try self.validateEmissionMatrixXmlSyntax();

        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const identifier = declaration.identifier;
            if (identifier.kind == .pack_format and
                identifier.typeLabel() == 0x0002)
            {
                const matrix_pack = try self.emissionMatrixPack(identifier);
                try self.validateEmissionMatrixPair(
                    identifier,
                    matrix_pack.input_pack,
                    matrix_pack.output_pack,
                );
                try self.validateEmissionMatrixChannels(
                    matrix_pack,
                );
            } else if (identifier.kind == .channel_format and
                identifier.typeLabel() == 0x0002)
            {
                try self.validateEmissionMatrixChannelParent(identifier);
            }
        }
    }

    /// Validates complementary-object groups and their profile-level derived
    /// counts.
    pub fn validateEmissionProfileComplementaryObjects(
        self: Document,
    ) !void {
        try self.validateEmissionProfileMatrices();
        const limits = emissionComplementaryLimits(
            try self.emissionProfileLevel(),
        );
        var group_count: usize = 0;
        var independent_group_count: usize = 0;
        var non_complementary_track_count: usize = 0;

        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const object = declaration.identifier;
            if (object.kind != .object) continue;

            const complementary_parent_count =
                try self.emissionComplementaryParentCount(object.primary);
            if (complementary_parent_count > 1)
                return error.InvalidAdmEmissionProfileComplementaryObject;
            const complementary_child_count =
                try self.emissionComplementaryChildCount(object.primary);
            const parent = try self.emissionObjectParent(object.primary);
            if (parent.kind != .content) {
                if (complementary_parent_count != 0 or
                    complementary_child_count != 0)
                {
                    return error.InvalidAdmEmissionProfileComplementaryObject;
                }
                continue;
            }

            if (complementary_child_count != 0) {
                if (complementary_parent_count != 0)
                    return error.InvalidAdmEmissionProfileComplementaryObject;
                group_count = std.math.add(
                    usize,
                    group_count,
                    1,
                ) catch
                    return error.AdmEmissionProfileComplementaryGroupLimitExceeded;
                independent_group_count = std.math.add(
                    usize,
                    independent_group_count,
                    1,
                ) catch
                    return error.AdmEmissionProfileIndependentGroupLimitExceeded;
                const group_tracks =
                    try self.validateEmissionComplementaryGroup(
                        object,
                        complementary_child_count,
                    );
                non_complementary_track_count = std.math.add(
                    usize,
                    non_complementary_track_count,
                    group_tracks,
                ) catch
                    return error.AdmEmissionProfileNonComplementaryTrackLimitExceeded;
            } else if (complementary_parent_count == 0) {
                independent_group_count = std.math.add(
                    usize,
                    independent_group_count,
                    1,
                ) catch
                    return error.AdmEmissionProfileIndependentGroupLimitExceeded;
                non_complementary_track_count = std.math.add(
                    usize,
                    non_complementary_track_count,
                    try self.emissionObjectTrackCount(object.primary),
                ) catch
                    return error.AdmEmissionProfileNonComplementaryTrackLimitExceeded;
            }
        }

        if (group_count > limits.groups)
            return error.AdmEmissionProfileComplementaryGroupLimitExceeded;
        if (independent_group_count == 0 or
            independent_group_count > limits.independent_groups)
        {
            return error.AdmEmissionProfileIndependentGroupLimitExceeded;
        }
        if (non_complementary_track_count == 0 or
            non_complementary_track_count > limits.non_complementary_tracks)
        {
            return error.AdmEmissionProfileNonComplementaryTrackLimitExceeded;
        }
    }

    /// Validates the emission profile's audioObject interaction parameters.
    pub fn validateEmissionProfileObjectParameters(
        self: Document,
    ) !void {
        try self.validateEmissionProfileComplementaryObjects();
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind != .object) continue;
            _ = try self.emissionObjectParameterState(
                declaration.identifier.primary,
            );
        }
    }

    /// Validates complementary object parameters and programme overrides.
    pub fn validateEmissionProfileComplementaryParameters(
        self: Document,
    ) !void {
        try self.validateEmissionProfileObjectParameters();
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind == .programme) {
                try self.validateEmissionProgrammeAlternativeReferences(
                    declaration.identifier.primary,
                );
                continue;
            }
            if (declaration.identifier.kind != .object) continue;
            const child_count = try self.emissionComplementaryChildCount(
                declaration.identifier.primary,
            );
            if (child_count == 0) continue;
            try self.validateEmissionComplementaryParameterGroup(
                declaration.identifier,
                child_count + 1,
            );
        }
    }

    /// Validates programme and content names, languages, labels, loudness,
    /// dialogue classification, and permitted direct sub-elements.
    pub fn validateEmissionProfileProgrammeContentMetadata(
        self: Document,
    ) !void {
        try self.validateEmissionProfileComplementaryParameters();
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "audioProgramme")) {
                        try readEmissionProgrammeMetadata(&events, element);
                    } else if (std.mem.eql(u8, name, "audioContent")) {
                        try readEmissionContentMetadata(&events, element);
                    }
                },
                else => {},
            }
        }
    }

    /// Validates local pack, channel, and track UID metadata and structure.
    pub fn validateEmissionProfileFormatMetadata(
        self: Document,
    ) !void {
        try self.validateEmissionProfileProgrammeContentMetadata();
        var owner: ?EmissionFormatOwner = null;
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (owner) |*current| {
                        if (element.depth == current.depth + 1)
                            try noteEmissionFormatChild(current, element);
                        continue;
                    }
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "audioPackFormat")) {
                        const type_label = try emissionElementTypeLabel(
                            element,
                            "audioPackFormatID",
                        );
                        try validateEmissionFormatDeclarationAttributes(
                            element,
                            "audioPackFormatID",
                            "audioPackFormatName",
                            type_label,
                        );
                        owner = .{
                            .kind = if (type_label == 0x0002)
                                .matrix_pack
                            else
                                .objects_pack,
                            .depth = element.depth,
                        };
                    } else if (std.mem.eql(
                        u8,
                        name,
                        "audioChannelFormat",
                    )) {
                        const type_label = try emissionElementTypeLabel(
                            element,
                            "audioChannelFormatID",
                        );
                        try validateEmissionFormatDeclarationAttributes(
                            element,
                            "audioChannelFormatID",
                            "audioChannelFormatName",
                            type_label,
                        );
                        owner = .{
                            .kind = if (type_label == 0x0002)
                                .matrix_channel
                            else
                                .objects_channel,
                            .depth = element.depth,
                        };
                    } else if (std.mem.eql(u8, name, "audioTrackUID")) {
                        try validateEmissionTrackUidAttributes(element);
                        owner = .{
                            .kind = .track_uid,
                            .depth = element.depth,
                        };
                    } else {
                        continue;
                    }
                    if (element.self_closing) {
                        try validateEmissionFormatOwner(owner.?);
                        owner = null;
                    }
                },
                .end => |element| {
                    const current = owner orelse continue;
                    if (element.depth != current.depth) continue;
                    try validateEmissionFormatOwner(current);
                    owner = null;
                },
                else => {},
            }
        }
        if (owner != null)
            return error.InvalidAdmEmissionProfileFormatStructure;
    }

    /// Validates file-based Objects block timing and parameters.
    pub fn validateEmissionProfileObjectBlocks(self: Document) !void {
        try self.validateEmissionProfileFormatMetadata();
        try self.validateEmissionObjectBlockSyntax();

        const minimum_duration = adm_time.Value{
            .whole_seconds = 0,
            .fractional_numerator = 5,
            .fractional_denominator = 1000,
            .format = .decimal,
        };
        const zero = zeroAdmTime();
        var coordinate_system: ?bool = null;
        var block_iterator = self.blocks();
        while (try block_iterator.next()) |block| {
            if (block.identifier.typeLabel() != 0x0003) continue;
            if (!block.rtime_explicit or block.duration == null)
                return error.MissingAdmEmissionProfileBlockTiming;
            const duration = block.duration.?;
            if (duration.compare(zero) != .eq and
                duration.compare(minimum_duration) == .lt)
            {
                return error.InvalidAdmEmissionProfileBlockDuration;
            }
            if (block.position_count != 3)
                return error.InvalidAdmEmissionProfileBlockPosition;
            if (coordinate_system) |expected| {
                if (block.cartesian != expected)
                    return error.MixedAdmEmissionProfileCoordinateSystems;
            } else {
                coordinate_system = block.cartesian;
            }
            if (block.jump_position.interpolation_length != null)
                return error.InvalidAdmEmissionProfileJumpPosition;
            const linear_gain = emissionGainLinear(
                block.gain.value,
                block.gain.unit,
            );
            if (!std.math.isFinite(linear_gain) or
                linear_gain > @sqrt(10.0))
            {
                return error.InvalidAdmEmissionProfileObjectBlockGain;
            }

            const sequence = block.identifier.secondary orelse
                return error.InvalidAdmBlockIdentifier;
            if (sequence == 1) continue;
            var previous_iterator = self.blocks();
            while (try previous_iterator.next()) |previous| {
                if (!previous.channel_identifier.eql(
                    block.channel_identifier,
                ) or previous.identifier.secondary != sequence - 1) {
                    continue;
                }
                const previous_duration = previous.duration orelse
                    return error.MissingAdmEmissionProfileBlockTiming;
                if (!previous.rtime.sumEquals(
                    previous_duration,
                    block.rtime,
                )) {
                    return error.InvalidAdmEmissionProfileBlockTiming;
                }
                break;
            } else return error.InvalidAdmBlockSequence;
        }
    }

    fn validateEmissionObjectBlockSyntax(self: Document) !void {
        var frame_depth: ?usize = null;
        var afe_depth: ?usize = null;
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "frame") and
                        !element.self_closing)
                    {
                        frame_depth = element.depth;
                    } else if (std.mem.eql(
                        u8,
                        name,
                        "audioFormatExtended",
                    )) {
                        if (frame_depth != null)
                            return error.AdmEmissionProfileSerialBlocksRequireSerialValidation;
                        afe_depth = element.depth;
                    } else if (std.mem.eql(
                        u8,
                        name,
                        "audioBlockFormatObjects",
                    ) and insideAfe(afe_depth, element.depth)) {
                        try readEmissionObjectBlockSyntax(&events, element);
                    }
                },
                .end => |element| {
                    if (afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        afe_depth = null;
                    } else if (frame_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "frame"))
                    {
                        frame_depth = null;
                    }
                },
                else => {},
            }
        }
    }

    fn validateEmissionComplementaryParameterGroup(
        self: Document,
        root: adm.Identifier,
        group_size: usize,
    ) !void {
        const root_parameters = try self.emissionObjectParameterState(
            root.primary,
        );
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != root.primary or
                reference.kind != .complementary_object)
            {
                continue;
            }
            const member = reference.identifier orelse
                return error.InvalidAdmEmissionProfileComplementaryObject;
            const member_parameters = try self.emissionObjectParameterState(
                member.primary,
            );
            if (!emissionObjectParametersEqual(
                root_parameters,
                member_parameters,
            )) {
                return error.InvalidAdmEmissionProfileComplementaryParameters;
            }
        }

        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind != .programme) continue;
            try self.validateEmissionProgrammeComplementaryAlternatives(
                declaration.identifier.primary,
                root,
                root_parameters,
                group_size,
            );
        }
    }

    fn validateEmissionProgrammeAlternativeReferences(
        self: Document,
        programme_primary: u32,
    ) !void {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .programme or
                owner.primary != programme_primary or
                reference.kind != .alternative_value_set)
            {
                continue;
            }
            const alternative = reference.identifier orelse
                return error.InvalidAdmEmissionProfileProgrammeAlternative;
            if (!try self.emissionProgrammeIncludesObject(
                programme_primary,
                alternative.primary,
            )) {
                return error.InvalidAdmEmissionProfileProgrammeAlternative;
            }
            _ = try self.emissionProgrammeAlternativeForObject(
                programme_primary,
                alternative.primary,
            );
        }
    }

    fn validateEmissionProgrammeComplementaryAlternatives(
        self: Document,
        programme_primary: u32,
        root: adm.Identifier,
        root_parameters: EmissionObjectParameterState,
        group_size: usize,
    ) !void {
        var included_count: usize = @intFromBool(
            try self.emissionProgrammeIncludesObject(
                programme_primary,
                root.primary,
            ),
        );
        var referenced_count: usize = 0;
        var first_parameters: ?EmissionAlternativeParameters = null;
        if (try self.emissionProgrammeAlternativeForObject(
            programme_primary,
            root.primary,
        )) |alternative| {
            referenced_count += 1;
            first_parameters = try self.emissionAlternativeValueSetParameters(
                alternative,
                root_parameters.interaction,
            );
        }

        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != root.primary or
                reference.kind != .complementary_object)
            {
                continue;
            }
            const member = reference.identifier orelse
                return error.InvalidAdmEmissionProfileComplementaryObject;
            included_count += @intFromBool(
                try self.emissionProgrammeIncludesObject(
                    programme_primary,
                    member.primary,
                ),
            );
            const alternative =
                try self.emissionProgrammeAlternativeForObject(
                    programme_primary,
                    member.primary,
                ) orelse continue;
            referenced_count += 1;
            const member_parameters = try self.emissionObjectParameterState(
                member.primary,
            );
            const alternative_parameters =
                try self.emissionAlternativeValueSetParameters(
                    alternative,
                    member_parameters.interaction,
                );
            if (first_parameters) |expected| {
                if (!std.meta.eql(expected, alternative_parameters))
                    return error.InvalidAdmEmissionProfileComplementaryAlternative;
            } else {
                first_parameters = alternative_parameters;
            }
        }
        if (included_count == group_size and
            referenced_count != 0 and
            referenced_count != group_size)
        {
            return error.InvalidAdmEmissionProfileComplementaryAlternative;
        }
    }

    fn emissionProgrammeAlternativeForObject(
        self: Document,
        programme_primary: u32,
        object_primary: u32,
    ) !?adm.Identifier {
        var result: ?adm.Identifier = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .programme or
                owner.primary != programme_primary or
                reference.kind != .alternative_value_set)
            {
                continue;
            }
            const alternative = reference.identifier orelse
                return error.InvalidAdmEmissionProfileProgrammeAlternative;
            if (alternative.primary != object_primary) continue;
            if (result != null)
                return error.InvalidAdmEmissionProfileProgrammeAlternative;
            result = alternative;
        }
        return result;
    }

    fn emissionAlternativeValueSetParameters(
        self: Document,
        wanted: adm.Identifier,
        parent_interaction: ?EmissionObjectInteraction,
    ) !EmissionAlternativeParameters {
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "alternativeValueSet",
                    )) {
                        continue;
                    }
                    const identifier = try emissionElementIdentifier(
                        element,
                        "alternativeValueSetID",
                        .alternative_value_set,
                    );
                    if (identifier.kind != wanted.kind or
                        identifier.primary != wanted.primary or
                        identifier.secondary != wanted.secondary)
                    {
                        continue;
                    }
                    return readEmissionAlternativeValueSet(
                        &events,
                        element,
                        parent_interaction,
                    );
                },
                else => {},
            }
        }
        return error.InvalidAdmEmissionProfileProgrammeAlternative;
    }

    fn emissionObjectParameterState(
        self: Document,
        object_primary: u32,
    ) !EmissionObjectParameterState {
        var object_depth: ?usize = null;
        var state: ?EmissionObjectParameterState = null;
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "audioObject")) {
                        const identifier = try emissionElementIdentifier(
                            element,
                            "audioObjectID",
                            .object,
                        );
                        if (identifier.primary != object_primary) continue;
                        try validateEmissionObjectAttributes(element);
                        const interact = try emissionRequiredFlagAttribute(
                            element,
                            "interact",
                        );
                        const parent = try self.emissionObjectParent(
                            identifier.primary,
                        );
                        if (element.self_closing)
                            return error.InvalidAdmEmissionProfileObjectParameters;
                        object_depth = element.depth;
                        state = .{
                            .primary = identifier.primary,
                            .top_level = parent.kind == .content,
                            .interact = interact,
                        };
                        continue;
                    }
                    const depth = object_depth orelse continue;
                    if (element.depth != depth + 1) continue;
                    const parameters = &(state orelse
                        return error.InvalidAdmEmissionProfileObjectParameters);
                    if (isEmissionObjectReferenceOrLabel(name)) {
                        try skipEmissionElement(&events, element);
                        continue;
                    }
                    if (std.mem.eql(u8, name, "audioObjectInteraction")) {
                        if (!parameters.top_level or
                            parameters.interaction != null)
                        {
                            return error.InvalidAdmEmissionProfileObjectInteraction;
                        }
                        parameters.interaction =
                            try readEmissionObjectInteraction(
                                &events,
                                element,
                            );
                        if (parameters.interaction.?.position_range != null)
                            parameters.uses_position_controls = true;
                        continue;
                    }
                    if (std.mem.eql(u8, name, "gain")) {
                        if (!parameters.top_level or parameters.gain != null)
                            return error.InvalidAdmEmissionProfileObjectGain;
                        parameters.gain = try readEmissionGain(
                            &events,
                            element,
                        );
                        continue;
                    }
                    if (std.mem.eql(u8, name, "positionOffset")) {
                        if (!parameters.top_level or
                            parameters.position != null)
                        {
                            return error.InvalidAdmEmissionProfilePositionOffset;
                        }
                        parameters.position = try readEmissionPositionOffset(
                            &events,
                            element,
                        );
                        parameters.uses_position_controls = true;
                        continue;
                    }
                    if (std.mem.eql(u8, name, "alternativeValueSet")) {
                        if (!parameters.top_level)
                            return error.InvalidAdmEmissionProfileAlternativeValueSet;
                        parameters.has_alternative_value_sets = true;
                        try skipEmissionElement(&events, element);
                        continue;
                    }
                    return error.InvalidAdmEmissionProfileObjectSubelement;
                },
                .end => |element| {
                    if (object_depth != element.depth or
                        !std.mem.eql(
                            u8,
                            element.localName(),
                            "audioObject",
                        ))
                    {
                        continue;
                    }
                    var result = state orelse
                        return error.InvalidAdmEmissionProfileObjectParameters;
                    if (result.has_alternative_value_sets and
                        try self.validateEmissionObjectAlternativeValueSets(
                            result.primary,
                            result.interaction,
                        ))
                    {
                        result.uses_position_controls = true;
                    }
                    try self.validateEmissionObjectParameterState(result);
                    return result;
                },
                else => {},
            }
        }
        return error.InvalidAdmEmissionProfileObjectParameters;
    }

    fn validateEmissionObjectParameterState(
        self: Document,
        state: EmissionObjectParameterState,
    ) !void {
        if (state.interact != (state.interaction != null))
            return error.InvalidAdmEmissionProfileObjectInteraction;
        if (state.interaction) |interaction| {
            try validateEmissionGainWithinRange(
                if (state.gain) |gain|
                    emissionGainLinear(gain.value, gain.unit)
                else
                    1.0,
                interaction.gain_range,
            );
            try validateEmissionPositionWithinRange(
                state.position,
                interaction.position_range,
            );
        }
        if (state.uses_position_controls)
            try self.validateEmissionObjectPositioning(state.primary);
    }

    fn validateEmissionObjectPositioning(
        self: Document,
        object_primary: u32,
    ) !void {
        const pack_primary = try self.emissionObjectPack(object_primary);
        if (@as(u16, @intCast(pack_primary >> 16)) != 0x0003)
            return error.InvalidAdmEmissionProfilePositionOffset;

        var channels = EmissionPackChannels{};
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .pack_format or
                owner.primary != pack_primary or
                reference.kind != .channel_format)
            {
                continue;
            }
            const channel = reference.identifier orelse
                return error.InvalidAdmEmissionProfilePositionOffset;
            try channels.append(channel.primary);
        }
        var block_iterator = self.blocks();
        while (try block_iterator.next()) |block| {
            if (channels.indexOf(block.channel_identifier.primary) == null)
                continue;
            if (!emissionObjectBlockHasNeutralPosition(block))
                return error.InvalidAdmEmissionProfilePositionOffset;
        }
    }

    fn emissionObjectPack(
        self: Document,
        object_primary: u32,
    ) !u32 {
        var result: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary)
            {
                continue;
            }
            if (reference.kind == .object)
                return error.InvalidAdmEmissionProfilePositionOffset;
            if (reference.kind != .pack_format) continue;
            if (result != null)
                return error.InvalidAdmEmissionProfilePositionOffset;
            result = (reference.identifier orelse
                return error.InvalidAdmEmissionProfilePositionOffset).primary;
        }
        return result orelse error.InvalidAdmEmissionProfilePositionOffset;
    }

    fn validateEmissionObjectAlternativeValueSets(
        self: Document,
        object_primary: u32,
        parent_interaction: ?EmissionObjectInteraction,
    ) !bool {
        var object_depth: ?usize = null;
        var uses_position_controls = false;
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioObject",
                    )) {
                        const identifier = try emissionElementIdentifier(
                            element,
                            "audioObjectID",
                            .object,
                        );
                        if (identifier.primary == object_primary)
                            object_depth = element.depth;
                        continue;
                    }
                    const depth = object_depth orelse continue;
                    if (element.depth != depth + 1 or
                        !std.mem.eql(
                            u8,
                            element.localName(),
                            "alternativeValueSet",
                        ))
                    {
                        continue;
                    }
                    const parameters = try readEmissionAlternativeValueSet(
                        &events,
                        element,
                        parent_interaction,
                    );
                    if (parameters.usesPositionControls()) {
                        uses_position_controls = true;
                    }
                },
                .end => |element| {
                    if (object_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioObject",
                        ))
                    {
                        return uses_position_controls;
                    }
                },
                else => {},
            }
        }
        return error.InvalidAdmEmissionProfileAlternativeValueSet;
    }

    fn validateEmissionComplementaryGroup(
        self: Document,
        root: adm.Identifier,
        child_count: usize,
    ) !usize {
        const source_type = try self.emissionObjectSourceType(root.primary);
        var maximum_tracks = try self.emissionObjectTrackCount(root.primary);
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != root.primary or
                reference.kind != .complementary_object)
            {
                continue;
            }
            const child = reference.identifier orelse
                return error.InvalidAdmEmissionProfileComplementaryObject;
            const child_parent = try self.emissionObjectParent(child.primary);
            if (child_parent.kind != .content or
                try self.emissionComplementaryChildCount(child.primary) != 0 or
                try self.emissionComplementaryParentCount(child.primary) != 1)
            {
                return error.InvalidAdmEmissionProfileComplementaryObject;
            }
            if (try self.emissionObjectSourceType(child.primary) != source_type)
                return error.InvalidAdmEmissionProfileComplementaryPackType;
            maximum_tracks = @max(
                maximum_tracks,
                try self.emissionObjectTrackCount(child.primary),
            );
        }
        try self.validateEmissionComplementaryProgrammeInclusion(
            root.primary,
            child_count + 1,
        );
        return maximum_tracks;
    }

    fn validateEmissionComplementaryProgrammeInclusion(
        self: Document,
        root_primary: u32,
        group_size: usize,
    ) !void {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const programme = declaration.identifier;
            if (programme.kind != .programme) continue;
            var included: usize = @intFromBool(
                try self.emissionProgrammeIncludesObject(
                    programme.primary,
                    root_primary,
                ),
            );
            var reference_iterator = self.references();
            while (try reference_iterator.next()) |reference| {
                const owner = reference.owner orelse continue;
                if (!reference.direct_owner or
                    owner.kind != .object or
                    owner.primary != root_primary or
                    reference.kind != .complementary_object)
                {
                    continue;
                }
                const child = reference.identifier orelse
                    return error.InvalidAdmEmissionProfileComplementaryObject;
                included += @intFromBool(
                    try self.emissionProgrammeIncludesObject(
                        programme.primary,
                        child.primary,
                    ),
                );
            }
            if (included != 0 and included != 1 and included != group_size)
                return error.InvalidAdmEmissionProfileComplementaryProgramme;
        }
    }

    fn emissionProgrammeIncludesObject(
        self: Document,
        programme_primary: u32,
        object_primary: u32,
    ) !bool {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or reference.kind != .content)
                continue;
            const owner = reference.owner orelse continue;
            const content = reference.identifier orelse continue;
            if (owner.kind == .programme and
                owner.primary == programme_primary and
                content.primary == object_primary)
            {
                return true;
            }
        }
        return false;
    }

    fn emissionComplementaryChildCount(
        self: Document,
        object_primary: u32,
    ) !usize {
        var count: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (reference.direct_owner and
                owner.kind == .object and
                owner.primary == object_primary and
                reference.kind == .complementary_object)
            {
                count = std.math.add(usize, count, 1) catch
                    return error.AdmEmissionProfileComplementaryGroupLimitExceeded;
            }
        }
        return count;
    }

    fn emissionComplementaryParentCount(
        self: Document,
        object_primary: u32,
    ) !usize {
        var count: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or
                reference.kind != .complementary_object)
            {
                continue;
            }
            const child = reference.identifier orelse continue;
            if (child.primary == object_primary) {
                count = std.math.add(usize, count, 1) catch
                    return error.InvalidAdmEmissionProfileComplementaryObject;
            }
        }
        return count;
    }

    fn emissionObjectSourceType(
        self: Document,
        object_primary: u32,
    ) !u16 {
        var child_count: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary)
            {
                continue;
            }
            if (reference.kind == .pack_format) {
                const pack = reference.identifier orelse
                    return error.InvalidAdmEmissionProfileComplementaryObject;
                return pack.typeLabel() orelse
                    error.InvalidAdmEmissionProfileComplementaryObject;
            }
            if (reference.kind == .object) child_count += 1;
        }
        if (child_count != 0) return 0x0003;
        return error.InvalidAdmEmissionProfileComplementaryObject;
    }

    fn emissionObjectTrackCount(
        self: Document,
        object_primary: u32,
    ) !usize {
        var count: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary)
            {
                continue;
            }
            if (reference.kind == .track_uid) {
                count = std.math.add(usize, count, 1) catch
                    return error.AdmEmissionProfileNonComplementaryTrackLimitExceeded;
            } else if (reference.kind == .object) {
                count = std.math.add(
                    usize,
                    count,
                    try self.emissionObjectTrackCount(
                        (reference.identifier orelse
                            return error.InvalidAdmEmissionProfileComplementaryObject).primary,
                    ),
                ) catch
                    return error.AdmEmissionProfileNonComplementaryTrackLimitExceeded;
            }
        }
        return count;
    }

    fn emissionMatrixPack(
        self: Document,
        identifier: adm.Identifier,
    ) !EmissionMatrixPack {
        var input_pack: ?u32 = null;
        var output_pack: ?u32 = null;
        var channels = EmissionPackChannels{};
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .pack_format or
                owner.primary != identifier.primary)
            {
                continue;
            }
            const target = reference.identifier orelse
                return error.InvalidAdmEmissionProfileMatrixPack;
            switch (reference.kind) {
                .matrix_input_pack => {
                    if (input_pack != null)
                        return error.InvalidAdmEmissionProfileMatrixPack;
                    input_pack = target.primary;
                },
                .matrix_output_pack => {
                    if (output_pack != null)
                        return error.InvalidAdmEmissionProfileMatrixPack;
                    output_pack = target.primary;
                },
                .channel_format => {
                    if (target.typeLabel() != 0x0002 or
                        target.definitionIndex().? < 0x1000 or
                        channels.indexOf(target.primary) != null)
                    {
                        return error.InvalidAdmEmissionProfileMatrixPack;
                    }
                    try channels.append(target.primary);
                },
                else => return error.InvalidAdmEmissionProfileMatrixPack,
            }
        }
        if (channels.len == 0)
            return error.InvalidAdmEmissionProfileMatrixPack;

        const input = input_pack orelse
            return error.InvalidAdmEmissionProfileMatrixPack;
        const output = output_pack orelse
            return error.InvalidAdmEmissionProfileMatrixPack;
        const input_index: u16 = @truncate(input);
        const output_index: u16 = @truncate(output);
        if (@as(u16, @intCast(input >> 16)) != 0x0001 or
            @as(u16, @intCast(output >> 16)) != 0x0001 or
            commonEmissionPackChannelIndexes(input_index) == null or
            !commonEmissionPackIsMatrixOutput(output_index) or
            input == output)
        {
            return error.InvalidAdmEmissionProfileMatrixPack;
        }
        if (try self.directReferenceCount(
            .object,
            .pack_format,
            input,
        ) == 0) {
            return error.UnreferencedAdmEmissionProfileMatrixInput;
        }
        if (try self.directReferenceCount(
            .object,
            .pack_format,
            identifier.primary,
        ) != 0 or
            try self.directReferenceCount(
                .track_uid,
                .pack_format,
                identifier.primary,
            ) != 0)
        {
            return error.InvalidAdmEmissionProfileMatrixSourceReference;
        }
        return .{
            .input_pack = input,
            .output_pack = output,
            .channels = channels,
        };
    }

    fn validateEmissionMatrixPair(
        self: Document,
        identifier: adm.Identifier,
        input_pack: u32,
        output_pack: u32,
    ) !void {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |other| {
            if (other.identifier.kind != .pack_format or
                other.identifier.typeLabel() != 0x0002 or
                other.identifier.primary == identifier.primary)
            {
                continue;
            }
            const other_pack = try self.emissionMatrixPack(other.identifier);
            if (other_pack.input_pack == input_pack and
                other_pack.output_pack == output_pack)
            {
                return error.DuplicateAdmEmissionProfileMatrixPair;
            }
        }
    }

    fn validateEmissionMatrixChannels(
        self: Document,
        matrix_pack: EmissionMatrixPack,
    ) !void {
        const input_channels = try emissionCommonPackChannels(
            matrix_pack.input_pack,
        );
        const output_channels = try emissionCommonPackChannels(
            matrix_pack.output_pack,
        );
        var used_outputs: [24]bool = @splat(false);
        for (matrix_pack.channels.primaries[0..matrix_pack.channels.len]) |channel| {
            const block = try self.emissionMatrixChannelBlock(channel);
            const output = try self.emissionMatrixBlockOutput(block.identifier);
            const output_index = output_channels.indexOf(output) orelse
                return error.InvalidAdmEmissionProfileMatrixOutput;
            if (used_outputs[output_index])
                return error.DuplicateAdmEmissionProfileMatrixOutput;
            used_outputs[output_index] = true;
            try validateEmissionMatrixCoefficients(
                block,
                input_channels,
            );
            if (try self.directReferenceCount(
                .track_uid,
                .channel_format,
                channel,
            ) != 0) {
                return error.InvalidAdmEmissionProfileMatrixSourceReference;
            }
        }
    }

    fn emissionMatrixChannelBlock(
        self: Document,
        channel_primary: u32,
    ) !BlockFormat {
        var result: ?BlockFormat = null;
        var block_iterator = self.blocks();
        while (try block_iterator.next()) |block| {
            if (block.channel_identifier.kind != .channel_format or
                block.channel_identifier.primary != channel_primary)
            {
                continue;
            }
            if (result != null)
                return error.InvalidAdmEmissionProfileMatrixBlockCount;
            result = block;
        }
        return result orelse
            error.InvalidAdmEmissionProfileMatrixBlockCount;
    }

    fn emissionMatrixBlockOutput(
        self: Document,
        block: adm.Identifier,
    ) !u32 {
        var result: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .block_format or
                owner.primary != block.primary or
                owner.secondary != block.secondary or
                reference.kind != .matrix_output_channel)
            {
                continue;
            }
            if (result != null)
                return error.InvalidAdmEmissionProfileMatrixOutput;
            const output = reference.identifier orelse
                return error.InvalidAdmEmissionProfileMatrixOutput;
            if (output.typeLabel() != 0x0001 or
                !output.isCommonDefinition())
            {
                return error.InvalidAdmEmissionProfileMatrixOutput;
            }
            result = output.primary;
        }
        return result orelse
            error.InvalidAdmEmissionProfileMatrixOutput;
    }

    fn validateEmissionMatrixChannelParent(
        self: Document,
        channel: adm.Identifier,
    ) !void {
        var result: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or
                reference.kind != .channel_format)
            {
                continue;
            }
            const target = reference.identifier orelse continue;
            if (target.primary != channel.primary) continue;
            const owner = reference.owner orelse continue;
            if (owner.kind != .pack_format or owner.typeLabel() != 0x0002)
                return error.InvalidAdmEmissionProfileMatrixChannelParent;
            if (result != null)
                return error.InvalidAdmEmissionProfileMatrixChannelParent;
            result = owner.primary;
        }
        if (result == null)
            return error.InvalidAdmEmissionProfileMatrixChannelParent;
    }

    fn validateEmissionMatrixXmlSyntax(self: Document) !void {
        var afe_depth: ?usize = null;
        var matrix_pack_depth: ?usize = null;
        var matrix_channel_depth: ?usize = null;
        var matrix_block_depth: ?usize = null;
        var matrix_depth: ?usize = null;
        var events = self.xml_document.iterator();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const local_name = element.localName();
                    if (std.mem.eql(
                        u8,
                        local_name,
                        "audioFormatExtended",
                    )) {
                        afe_depth = element.depth;
                        continue;
                    }
                    if (afe_depth == null) continue;
                    if (std.mem.eql(u8, local_name, "outputChannelIDRef"))
                        return error.InvalidAdmEmissionProfileMatrixOutput;
                    if (matrix_pack_depth) |depth| {
                        if (element.depth == depth + 1 and
                            !std.mem.eql(
                                u8,
                                local_name,
                                "audioChannelFormatIDRef",
                            ) and
                            !std.mem.eql(
                                u8,
                                local_name,
                                "inputPackFormatIDRef",
                            ) and
                            !std.mem.eql(
                                u8,
                                local_name,
                                "outputPackFormatIDRef",
                            ))
                        {
                            return error.InvalidAdmEmissionProfileMatrixElement;
                        }
                    }
                    if (matrix_channel_depth) |depth| {
                        if (element.depth == depth + 1 and
                            !std.mem.eql(
                                u8,
                                local_name,
                                "audioBlockFormatMatrix",
                            ))
                        {
                            return error.InvalidAdmEmissionProfileMatrixElement;
                        }
                    }
                    if (matrix_block_depth) |depth| {
                        if (element.depth == depth + 1 and
                            !std.mem.eql(
                                u8,
                                local_name,
                                "outputChannelFormatIDRef",
                            ) and
                            !std.mem.eql(u8, local_name, "matrix"))
                        {
                            return error.InvalidAdmEmissionProfileMatrixElement;
                        }
                    }
                    if (matrix_depth) |depth| {
                        if (element.depth == depth + 1 and
                            !std.mem.eql(u8, local_name, "coefficient"))
                        {
                            return error.InvalidAdmEmissionProfileMatrixElement;
                        }
                    }
                    if (std.mem.eql(u8, local_name, "audioPackFormat")) {
                        const type_label = try emissionElementTypeLabel(
                            element,
                            "audioPackFormatID",
                        );
                        if (type_label == 0x0002) {
                            if (element.self_closing)
                                return error.InvalidAdmEmissionProfileMatrixPack;
                            matrix_pack_depth = element.depth;
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, local_name, "audioChannelFormat")) {
                        const type_label = try emissionElementTypeLabel(
                            element,
                            "audioChannelFormatID",
                        );
                        if (type_label == 0x0002) {
                            if (element.self_closing)
                                return error.InvalidAdmEmissionProfileMatrixBlockCount;
                            matrix_channel_depth = element.depth;
                        }
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        local_name,
                        "audioBlockFormatMatrix",
                    )) {
                        var attributes = xml.AttributeIterator.init(
                            element.attributes,
                        );
                        while (try attributes.next()) |attribute| {
                            if (!isXmlNamespaceDeclaration(attribute.name) and
                                !std.mem.eql(
                                    u8,
                                    attribute.localName(),
                                    "audioBlockFormatID",
                                ))
                            {
                                return error.InvalidAdmEmissionProfileMatrixBlockAttribute;
                            }
                        }
                        matrix_block_depth = element.depth;
                        continue;
                    }
                    if (std.mem.eql(u8, local_name, "matrix")) {
                        matrix_depth = element.depth;
                        continue;
                    }
                    if (!std.mem.eql(u8, local_name, "coefficient"))
                        continue;
                    var attributes = xml.AttributeIterator.init(
                        element.attributes,
                    );
                    while (try attributes.next()) |attribute| {
                        const name = attribute.localName();
                        if (!isXmlNamespaceDeclaration(attribute.name) and
                            !std.mem.eql(u8, name, "gain") and
                            !std.mem.eql(u8, name, "gainUnit"))
                        {
                            return error.InvalidAdmEmissionProfileMatrixCoefficientAttribute;
                        }
                    }
                },
                .end => |element| {
                    if (matrix_pack_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioPackFormat",
                        ))
                    {
                        matrix_pack_depth = null;
                    }
                    if (matrix_channel_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioChannelFormat",
                        ))
                    {
                        matrix_channel_depth = null;
                    }
                    if (matrix_block_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioBlockFormatMatrix",
                        ))
                    {
                        matrix_block_depth = null;
                    }
                    if (matrix_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "matrix"))
                    {
                        matrix_depth = null;
                    }
                    if (afe_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        afe_depth = null;
                    }
                },
                else => {},
            }
        }
    }

    fn validateEmissionFormatOwnership(self: Document) !void {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const identifier = declaration.identifier;
            switch (identifier.kind) {
                .pack_format => {
                    if (identifier.typeLabel() != 0x0003) continue;
                    _ = try self.emissionPackChannels(identifier.primary);
                    if (try self.directReferenceCount(
                        .object,
                        .pack_format,
                        identifier.primary,
                    ) == 0) {
                        return error.UnreferencedAdmEmissionProfilePack;
                    }
                },
                .channel_format => {
                    if (try self.directReferenceCount(
                        .pack_format,
                        .channel_format,
                        identifier.primary,
                    ) != 1) {
                        return error.InvalidAdmEmissionProfileChannelParent;
                    }
                },
                .track_uid => {
                    if (try self.directReferenceCount(
                        .object,
                        .track_uid,
                        identifier.primary,
                    ) != 1) {
                        return error.InvalidAdmEmissionProfileTrackParent;
                    }
                },
                else => {},
            }
        }
    }

    fn validateEmissionObjectSource(
        self: Document,
        object_primary: u32,
        maximum_channels: usize,
    ) !void {
        var child_count: usize = 0;
        var track_count: usize = 0;
        var pack_primary: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary)
            {
                continue;
            }
            switch (reference.kind) {
                .object => child_count += 1,
                .pack_format => {
                    if (pack_primary != null)
                        return error.InvalidAdmEmissionProfileObjectSource;
                    pack_primary = (reference.identifier orelse
                        return error.InvalidAdmEmissionProfileObjectSource).primary;
                },
                .track_uid => {
                    if (reference.virtual_silent_track)
                        return error.SilentAdmEmissionProfileTrack;
                    track_count += 1;
                },
                else => {},
            }
        }

        if (child_count != 0) {
            if (pack_primary != null or track_count != 0)
                return error.InvalidAdmEmissionProfileObjectSource;
            var children = self.references();
            while (try children.next()) |reference| {
                const owner = reference.owner orelse continue;
                if (!reference.direct_owner or
                    owner.kind != .object or
                    owner.primary != object_primary or
                    reference.kind != .object)
                {
                    continue;
                }
                const child = reference.identifier orelse
                    return error.InvalidAdmEmissionProfileObjectSource;
                try self.validateEmissionNestedObjectPack(child.primary);
            }
            return;
        }

        const pack = pack_primary orelse
            return error.InvalidAdmEmissionProfileObjectSource;
        const channels = try self.emissionPackChannels(pack);
        if (channels.len > maximum_channels)
            return error.AdmEmissionProfileLayoutChannelLimitExceeded;
        if (track_count != channels.len)
            return error.InvalidAdmEmissionProfileTrackCount;

        var seen_channels: [24]bool = @splat(false);
        var tracks = self.references();
        while (try tracks.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary or
                reference.kind != .track_uid)
            {
                continue;
            }
            if (reference.virtual_silent_track)
                return error.SilentAdmEmissionProfileTrack;
            const track_uid = reference.identifier orelse
                return error.InvalidAdmEmissionProfileTrackReference;
            if (!try self.containsIdentifierValue(
                .track_uid,
                track_uid.primary,
                null,
            )) {
                return error.InvalidAdmEmissionProfileTrackReference;
            }
            const channel = try self.emissionTrackUidChannel(
                track_uid.primary,
                pack,
            );
            const channel_index = channels.indexOf(channel) orelse
                return error.InvalidAdmEmissionProfileTrackReference;
            if (seen_channels[channel_index])
                return error.InvalidAdmEmissionProfileTrackReference;
            seen_channels[channel_index] = true;
        }
        for (seen_channels[0..channels.len]) |seen| {
            if (!seen) return error.InvalidAdmEmissionProfileTrackReference;
        }
    }

    fn validateEmissionNestedObjectPack(
        self: Document,
        object_primary: u32,
    ) !void {
        var pack_primary: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .object or
                owner.primary != object_primary or
                reference.kind != .pack_format)
            {
                continue;
            }
            if (pack_primary != null)
                return error.InvalidAdmEmissionProfileNestedObjectPack;
            pack_primary = (reference.identifier orelse
                return error.InvalidAdmEmissionProfileNestedObjectPack).primary;
        }
        const primary = pack_primary orelse
            return error.InvalidAdmEmissionProfileNestedObjectPack;
        const type_label: u16 = @intCast(primary >> 16);
        const definition_index: u16 = @truncate(primary);
        if (type_label != 0x0003 or definition_index < 0x1000)
            return error.InvalidAdmEmissionProfileNestedObjectPack;
    }

    fn emissionPackChannels(
        self: Document,
        pack_primary: u32,
    ) !EmissionPackChannels {
        const type_label: u16 = @intCast(pack_primary >> 16);
        const definition_index: u16 = @truncate(pack_primary);
        var channels = EmissionPackChannels{};
        if (type_label == 0x0001) {
            const indexes = commonEmissionPackChannelIndexes(
                definition_index,
            ) orelse return error.InvalidAdmEmissionProfilePackReference;
            for (indexes) |index| {
                try channels.append(
                    (@as(u32, 0x0001) << 16) | @as(u32, index),
                );
            }
            return channels;
        }
        if (type_label != 0x0003 or definition_index < 0x1000)
            return error.InvalidAdmEmissionProfilePackReference;

        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .pack_format or
                owner.primary != pack_primary or
                reference.kind != .channel_format)
            {
                continue;
            }
            const channel = reference.identifier orelse
                return error.InvalidAdmEmissionProfilePackReference;
            if (channel.typeLabel() != 0x0003)
                return error.InvalidAdmEmissionProfilePackReference;
            try channels.append(channel.primary);
        }
        if (channels.len != 1)
            return error.InvalidAdmEmissionProfilePackReference;
        return channels;
    }

    fn emissionTrackUidChannel(
        self: Document,
        track_uid_primary: u32,
        pack_primary: u32,
    ) !u32 {
        var referenced_pack: ?u32 = null;
        var referenced_channel: ?u32 = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .track_uid or
                owner.primary != track_uid_primary)
            {
                continue;
            }
            switch (reference.kind) {
                .pack_format => {
                    if (referenced_pack != null)
                        return error.InvalidAdmEmissionProfileTrackReference;
                    referenced_pack = (reference.identifier orelse
                        return error.InvalidAdmEmissionProfileTrackReference).primary;
                },
                .channel_format => {
                    if (referenced_channel != null)
                        return error.InvalidAdmEmissionProfileTrackReference;
                    referenced_channel = (reference.identifier orelse
                        return error.InvalidAdmEmissionProfileTrackReference).primary;
                },
                .track_format => return error.InvalidAdmEmissionProfileTrackReference,
                else => {},
            }
        }
        if (referenced_pack != pack_primary)
            return error.InvalidAdmEmissionProfileTrackReference;
        return referenced_channel orelse
            error.InvalidAdmEmissionProfileTrackReference;
    }

    fn directReferenceCount(
        self: Document,
        owner_kind: adm.IdentifierKind,
        reference_kind: ReferenceKind,
        identifier_primary: u32,
    ) !usize {
        var count: usize = 0;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or
                reference.kind != reference_kind or
                reference.virtual_silent_track)
            {
                continue;
            }
            const owner = reference.owner orelse continue;
            const identifier = reference.identifier orelse continue;
            if (owner.kind == owner_kind and
                identifier.primary == identifier_primary)
            {
                count += 1;
            }
        }
        return count;
    }

    fn containsIdentifierValue(
        self: Document,
        kind: adm.IdentifierKind,
        primary: u32,
        secondary: ?u32,
    ) !bool {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const identifier = declaration.identifier;
            if (identifier.kind == kind and
                identifier.primary == primary and
                identifier.secondary == secondary)
            {
                return true;
            }
        }
        return false;
    }

    fn validateEmissionContentOwner(
        self: Document,
        content: adm.Identifier,
    ) !void {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (reference.tag_target or
                !reference.direct_owner or
                reference.kind != .content)
            {
                continue;
            }
            const owner = reference.owner orelse continue;
            const identifier = reference.identifier orelse continue;
            if (owner.kind == .programme and identifier.eql(content)) return;
        }
        return error.UnreferencedAdmEmissionProfileContent;
    }

    fn validateEmissionObjectAncestry(
        self: Document,
        object: adm.Identifier,
    ) !void {
        var visited: [2]u32 = undefined;
        visited[0] = object.primary;
        var visited_count: usize = 1;
        var parent = try self.emissionObjectParent(object.primary);
        var nesting_level: usize = 0;
        while (parent.kind == .object) {
            for (visited[0..visited_count]) |primary| {
                if (primary == parent.primary)
                    return error.CyclicAdmEmissionProfileObjectReference;
            }
            nesting_level += 1;
            if (nesting_level > 1)
                return error.AdmEmissionProfileObjectNestingLimitExceeded;
            visited[visited_count] = parent.primary;
            visited_count += 1;
            parent = try self.emissionObjectParent(parent.primary);
        }
        if (parent.kind != .content)
            return error.InvalidAdmEmissionProfileObjectParent;
    }

    fn emissionObjectParent(
        self: Document,
        object_primary: u32,
    ) !EmissionObjectParent {
        var result: ?EmissionObjectParent = null;
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (reference.tag_target or
                !reference.direct_owner or
                reference.kind != .object)
            {
                continue;
            }
            const identifier = reference.identifier orelse continue;
            if (identifier.primary != object_primary) continue;
            const owner = reference.owner orelse continue;
            if (owner.kind != .content and owner.kind != .object) continue;
            if (result != null)
                return error.InvalidAdmEmissionProfileObjectParent;
            result = .{
                .kind = owner.kind,
                .primary = owner.primary,
            };
        }
        return result orelse error.InvalidAdmEmissionProfileObjectParent;
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
                    const gain_unit =
                        if (try element.attribute("gainUnit")) |raw|
                            try parseGainUnit(raw)
                        else
                            GainUnit.linear;
                    coefficient.gain = .{
                        .value = if (gain_attribute) |raw|
                            try parseAdmMatrixGain(raw, gain_unit)
                        else switch (gain_unit) {
                            .linear => 1.0,
                            .decibels => 0.0,
                        },
                        .unit = gain_unit,
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

fn parseAdmMatrixGain(encoded: []const u8, unit: GainUnit) !f64 {
    const value = std.fmt.parseFloat(f64, encoded) catch
        return error.InvalidAdmFloat;
    if (std.math.isFinite(value)) return value;
    if (unit == .decibels and
        std.math.isInf(value) and
        value < 0.0)
    {
        return value;
    }
    return error.InvalidAdmFloat;
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

test "ADM XML emission profile accepts object nesting through level two" {
    const document = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try document.validateEmissionProfileObjectTopology();
}

test "ADM XML emission profile rejects invalid object ownership" {
    const orphan = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
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
        error.InvalidAdmEmissionProfileObjectParent,
        orphan.validateEmissionProfileObjectTopology(),
    );

    const multiple_parents = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\    <audioObjectIDRef>AO_1003</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002"/>
        \\  <audioObject audioObjectID="AO_1003">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileObjectParent,
        multiple_parents.validateEmissionProfileObjectTopology(),
    );
}

test "ADM XML emission profile rejects excessive or cyclic object nesting" {
    const excessive = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioObjectIDRef>AO_1003</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1003"/>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.AdmEmissionProfileObjectNestingLimitExceeded,
        excessive.validateEmissionProfileObjectTopology(),
    );

    const cycle = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioObjectIDRef>AO_1003</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1003">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001"/>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.CyclicAdmEmissionProfileObjectReference,
        cycle.validateEmissionProfileObjectTopology(),
    );
}

test "ADM XML emission profile requires every content in a programme" {
    const document = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioContent audioContentID="ACO_1002">
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
        error.UnreferencedAdmEmissionProfileContent,
        document.validateEmissionProfileObjectTopology(),
    );
}

const valid_emission_matrix_xml =
    \\<audioFormatExtended version="ITU-R_BS.2076-3">
    \\  <audioProgramme audioProgrammeID="APR_1001">
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\  </audioProgramme>
    \\  <audioContent audioContentID="ACO_1001">
    \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioObject audioObjectID="AO_1001">
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioPackFormat audioPackFormatID="AP_00021001">
    \\    <audioChannelFormatIDRef>AC_00021001</audioChannelFormatIDRef>
    \\    <audioChannelFormatIDRef>AC_00021002</audioChannelFormatIDRef>
    \\    <inputPackFormatIDRef>AP_00010001</inputPackFormatIDRef>
    \\    <outputPackFormatIDRef>AP_00010002</outputPackFormatIDRef>
    \\  </audioPackFormat>
    \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
    \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
    \\      <outputChannelFormatIDRef>AC_00010001</outputChannelFormatIDRef>
    \\      <matrix>
    \\        <coefficient gain="0.5">AC_00010003</coefficient>
    \\      </matrix>
    \\    </audioBlockFormatMatrix>
    \\  </audioChannelFormat>
    \\  <audioChannelFormat audioChannelFormatID="AC_00021002">
    \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021002_00000001">
    \\      <outputChannelFormatIDRef>AC_00010002</outputChannelFormatIDRef>
    \\      <matrix>
    \\        <coefficient gain="-3" gainUnit="dB">AC_00010003</coefficient>
    \\      </matrix>
    \\    </audioBlockFormatMatrix>
    \\  </audioChannelFormat>
    \\  <audioTrackUID UID="ATU_00000001">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <profileList>
    \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
    \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\  </profileList>
    \\</audioFormatExtended>
;

fn expectEmissionMatrixReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_matrix_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileMatrices(),
    );
}

test "ADM XML emission profile validates downmix matrices" {
    const document = try Document.init(valid_emission_matrix_xml);
    try document.validateEmissionProfileMatrices();

    const negative_infinity = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "gain=\"-3\" gainUnit=\"dB\"",
        "gain=\"-inf\" gainUnit=\"dB\"",
    );
    defer std.testing.allocator.free(negative_infinity);
    const muted_document = try Document.init(negative_infinity);
    try muted_document.validateEmissionProfileMatrices();

    const default_decibels = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "gain=\"-3\" gainUnit=\"dB\"",
        "gainUnit=\"dB\"",
    );
    defer std.testing.allocator.free(default_decibels);
    const default_document = try Document.init(default_decibels);
    var blocks = default_document.blocks();
    _ = (try blocks.next()).?;
    const default_block = (try blocks.next()).?;
    try std.testing.expectEqual(
        GainUnit.decibels,
        default_block.matrixCoefficientSlice()[0].gain.unit,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        default_block.matrixCoefficientSlice()[0].gain.value,
    );
    try default_document.validateEmissionProfileMatrices();

    const namespace_binding = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "<coefficient gain=\"0.5\"",
        "<coefficient xmlns:vendor=\"urn:vendor\" gain=\"0.5\"",
    );
    defer std.testing.allocator.free(namespace_binding);
    const namespace_document = try Document.init(namespace_binding);
    try namespace_document.validateEmissionProfileMatrices();

    const wrapped_start = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "<audioFormatExtended ",
        "<wrapper><audioFormatExtended ",
    );
    defer std.testing.allocator.free(wrapped_start);
    const wrapped = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        wrapped_start,
        "</audioFormatExtended>",
        "</audioFormatExtended></wrapper>",
    );
    defer std.testing.allocator.free(wrapped);
    const wrapped_document = try Document.init(wrapped);
    try wrapped_document.validateEmissionProfileMatrices();

    const cartesian_input_pack = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "AP_00010001",
        "AP_00010801",
    );
    defer std.testing.allocator.free(cartesian_input_pack);
    const cartesian_input = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        cartesian_input_pack,
        "AC_00010003",
        "AC_00010803",
    );
    defer std.testing.allocator.free(cartesian_input);
    const cartesian_input_document = try Document.init(cartesian_input);
    try cartesian_input_document.validateEmissionProfileMatrices();

    const cartesian_output_pack = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_matrix_xml,
        "AP_00010002",
        "AP_00010802",
    );
    defer std.testing.allocator.free(cartesian_output_pack);
    const cartesian_output_left = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        cartesian_output_pack,
        "AC_00010001",
        "AC_00010801",
    );
    defer std.testing.allocator.free(cartesian_output_left);
    const cartesian_output = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        cartesian_output_left,
        "AC_00010002",
        "AC_00010802",
    );
    defer std.testing.allocator.free(cartesian_output);
    const cartesian_output_document = try Document.init(cartesian_output);
    try cartesian_output_document.validateEmissionProfileMatrices();
}

test "ADM XML emission profile validates matrix pack relationships" {
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixPack,
        "<outputPackFormatIDRef>AP_00010002</outputPackFormatIDRef>",
        "<outputPackFormatIDRef>AP_00010001</outputPackFormatIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixPack,
        "<outputPackFormatIDRef>AP_00010002</outputPackFormatIDRef>",
        "<outputPackFormatIDRef>AP_0001000A</outputPackFormatIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.UnreferencedAdmEmissionProfileMatrixInput,
        "<inputPackFormatIDRef>AP_00010001</inputPackFormatIDRef>",
        "<inputPackFormatIDRef>AP_00010003</inputPackFormatIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileChannelParent,
        "    <audioChannelFormatIDRef>AC_00021001</audioChannelFormatIDRef>\n" ++
            "    <audioChannelFormatIDRef>AC_00021002</audioChannelFormatIDRef>\n",
        "",
    );

    try expectEmissionMatrixReplacement(
        error.DuplicateAdmEmissionProfileMatrixPair,
        "</audioFormatExtended>",
        \\  <audioPackFormat audioPackFormatID="AP_00021003">
        \\    <audioChannelFormatIDRef>AC_00021003</audioChannelFormatIDRef>
        \\    <inputPackFormatIDRef>AP_00010001</inputPackFormatIDRef>
        \\    <outputPackFormatIDRef>AP_00010002</outputPackFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021003">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021003_00000001">
        \\      <outputChannelFormatIDRef>AC_00010001</outputChannelFormatIDRef>
        \\      <matrix><coefficient>AC_00010003</coefficient></matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
        ,
    );
}

test "ADM XML emission profile validates matrix channel mappings" {
    try expectEmissionMatrixReplacement(
        error.DuplicateAdmEmissionProfileMatrixOutput,
        "<outputChannelFormatIDRef>AC_00010002</outputChannelFormatIDRef>",
        "<outputChannelFormatIDRef>AC_00010001</outputChannelFormatIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixOutput,
        "<outputChannelFormatIDRef>AC_00010002</outputChannelFormatIDRef>",
        "<outputChannelFormatIDRef>AC_00010003</outputChannelFormatIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixOutput,
        "<outputChannelFormatIDRef>AC_00010001</outputChannelFormatIDRef>",
        "<outputChannelIDRef>AC_00010001</outputChannelIDRef>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixBlockCount,
        \\  <audioChannelFormat audioChannelFormatID="AC_00021002">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021002_00000001">
        \\      <outputChannelFormatIDRef>AC_00010002</outputChannelFormatIDRef>
        \\      <matrix>
        \\        <coefficient gain="-3" gainUnit="dB">AC_00010003</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
    ,
        \\  <audioChannelFormat audioChannelFormatID="AC_00021002"/>
        ,
    );
}

test "ADM XML emission profile validates matrix coefficients" {
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixCoefficient,
        "<coefficient gain=\"0.5\">AC_00010003</coefficient>",
        "<coefficient gain=\"0.5\">AC_00010001</coefficient>",
    );
    try expectEmissionMatrixReplacement(
        error.DuplicateAdmEmissionProfileMatrixCoefficient,
        "<coefficient gain=\"0.5\">AC_00010003</coefficient>",
        "<coefficient gain=\"0.5\">AC_00010003</coefficient>\n" ++
            "        <coefficient>AC_00010003</coefficient>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixGain,
        "gain=\"0.5\"",
        "gain=\"10.1\"",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixGain,
        "gain=\"0.5\"",
        "gain=\"-0.1\"",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixGain,
        "gain=\"-3\" gainUnit=\"dB\"",
        "gain=\"20.1\" gainUnit=\"dB\"",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixCoefficientAttribute,
        "gain=\"0.5\"",
        "gainVar=\"mix\"",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixElement,
        "<coefficient gain=\"0.5\">AC_00010003</coefficient>",
        "<unknown/>\n" ++
            "        <coefficient>AC_00010003</coefficient>",
    );
    try expectEmissionMatrixReplacement(
        error.InvalidAdmEmissionProfileMatrixBlockAttribute,
        "audioBlockFormatID=\"AB_00021001_00000001\"",
        "audioBlockFormatID=\"AB_00021001_00000001\" rtime=\"00:00:00.00000\"",
    );
}

const valid_emission_complementary_xml =
    \\<audioFormatExtended version="ITU-R_BS.2076-3">
    \\  <audioProgramme audioProgrammeID="APR_1001">
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\    <audioContentIDRef>ACO_1002</audioContentIDRef>
    \\    <audioContentIDRef>ACO_1003</audioContentIDRef>
    \\  </audioProgramme>
    \\  <audioProgramme audioProgrammeID="APR_1002">
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\  </audioProgramme>
    \\  <audioContent audioContentID="ACO_1001">
    \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioContent audioContentID="ACO_1002">
    \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioContent audioContentID="ACO_1003">
    \\    <audioObjectIDRef>AO_1003</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioObject audioObjectID="AO_1001">
    \\    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>
    \\    <audioComplementaryObjectIDRef>AO_1003</audioComplementaryObjectIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioObject audioObjectID="AO_1002">
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioObject audioObjectID="AO_1003">
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000003</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioTrackUID UID="ATU_00000001">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <audioTrackUID UID="ATU_00000002">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <audioTrackUID UID="ATU_00000003">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <profileList>
    \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
    \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\  </profileList>
    \\</audioFormatExtended>
;

fn expectEmissionComplementaryReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_complementary_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileComplementaryObjects(),
    );
}

fn writeEmissionIndependentObjects(
    output: *std.Io.Writer.Allocating,
    level: u8,
    pack_indexes: []const u16,
    complementary_group: bool,
) !void {
    try output.writer.print(
        "<audioFormatExtended version=\"ITU-R_BS.2076-3\">\n" ++
            "  <audioProgramme audioProgrammeID=\"APR_1001\">\n",
        .{},
    );
    for (pack_indexes, 0..) |_, object_index| {
        try output.writer.print(
            "    <audioContentIDRef>ACO_{X:0>4}</audioContentIDRef>\n",
            .{0x1001 + object_index},
        );
    }
    try output.writer.print("  </audioProgramme>\n", .{});

    for (pack_indexes, 0..) |_, object_index| {
        try output.writer.print(
            "  <audioContent audioContentID=\"ACO_{X:0>4}\">\n" ++
                "    <audioObjectIDRef>AO_{X:0>4}</audioObjectIDRef>\n" ++
                "  </audioContent>\n",
            .{ 0x1001 + object_index, 0x1001 + object_index },
        );
    }

    var next_track: usize = 1;
    for (pack_indexes, 0..) |pack_index, object_index| {
        const channels = commonEmissionPackChannelIndexes(pack_index).?;
        try output.writer.print(
            "  <audioObject audioObjectID=\"AO_{X:0>4}\">\n" ++
                "    <audioPackFormatIDRef>AP_0001{X:0>4}</audioPackFormatIDRef>\n",
            .{ 0x1001 + object_index, pack_index },
        );
        if (complementary_group and object_index == 0) {
            for (1..pack_indexes.len) |child_index| {
                try output.writer.print(
                    "    <audioComplementaryObjectIDRef>AO_{X:0>4}</audioComplementaryObjectIDRef>\n",
                    .{0x1001 + child_index},
                );
            }
        }
        for (channels) |_| {
            try output.writer.print(
                "    <audioTrackUIDRef>ATU_{X:0>8}</audioTrackUIDRef>\n",
                .{next_track},
            );
            next_track += 1;
        }
        try output.writer.print("  </audioObject>\n", .{});
    }

    next_track = 1;
    for (pack_indexes) |pack_index| {
        const channels = commonEmissionPackChannelIndexes(pack_index).?;
        for (channels) |channel_index| {
            try output.writer.print(
                "  <audioTrackUID UID=\"ATU_{X:0>8}\">\n" ++
                    "    <audioChannelFormatIDRef>AC_0001{X:0>4}</audioChannelFormatIDRef>\n" ++
                    "    <audioPackFormatIDRef>AP_0001{X:0>4}</audioPackFormatIDRef>\n" ++
                    "  </audioTrackUID>\n",
                .{ next_track, channel_index, pack_index },
            );
            next_track += 1;
        }
    }

    try output.writer.print(
        "  <profileList>\n" ++
            "    <profile profileName=\"Advanced sound system: ADM and S-ADM profile for emission\"\n" ++
            "      profileVersion=\"1\" profileLevel=\"{d}\">ITU-R BS.2168</profile>\n" ++
            "  </profileList>\n" ++
            "</audioFormatExtended>\n",
        .{level},
    );
}

test "ADM XML emission profile validates complementary object groups" {
    const document = try Document.init(valid_emission_complementary_xml);
    try document.validateEmissionProfileComplementaryObjects();

    const level_zero = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_xml,
        "profileLevel=\"1\"",
        "profileLevel=\"0\"",
    );
    defer std.testing.allocator.free(level_zero);
    const level_zero_document = try Document.init(level_zero);
    try level_zero_document.validateEmissionProfileComplementaryObjects();

    const level_two = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_xml,
        "profileLevel=\"1\"",
        "profileLevel=\"2\"",
    );
    defer std.testing.allocator.free(level_two);
    const level_two_document = try Document.init(level_two);
    try level_two_document.validateEmissionProfileComplementaryObjects();
}

test "ADM XML emission profile rejects invalid complementary ownership" {
    try expectEmissionComplementaryReplacement(
        error.InvalidAdmEmissionProfileComplementaryObject,
        "  <audioObject audioObjectID=\"AO_1002\">\n",
        "  <audioObject audioObjectID=\"AO_1002\">\n" ++
            "    <audioComplementaryObjectIDRef>AO_1003</audioComplementaryObjectIDRef>\n",
    );
    try expectEmissionComplementaryReplacement(
        error.InvalidAdmEmissionProfileComplementaryObject,
        "  <audioObject audioObjectID=\"AO_1003\">\n",
        "  <audioObject audioObjectID=\"AO_1003\">\n" ++
            "    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>\n",
    );
}

test "ADM XML emission profile requires whole complementary programme groups" {
    const without_third = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_xml,
        "    <audioContentIDRef>ACO_1003</audioContentIDRef>\n",
        "",
    );
    defer std.testing.allocator.free(without_third);
    const partial = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        without_third,
        "  <audioContent audioContentID=\"ACO_1001\">",
        "  <audioProgramme audioProgrammeID=\"APR_1003\">\n" ++
            "    <audioContentIDRef>ACO_1003</audioContentIDRef>\n" ++
            "  </audioProgramme>\n" ++
            "  <audioContent audioContentID=\"ACO_1001\">",
    );
    defer std.testing.allocator.free(partial);
    const document = try Document.init(partial);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileComplementaryProgramme,
        document.validateEmissionProfileComplementaryObjects(),
    );
}

test "ADM XML emission profile requires one complementary source type" {
    const member_object = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_xml,
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
    ,
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        ,
    );
    defer std.testing.allocator.free(member_object);
    const member_track = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        member_object,
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
    ,
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        ,
    );
    defer std.testing.allocator.free(member_track);
    const mixed_sources = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        member_track,
        "  <audioTrackUID UID=\"ATU_00000001\">",
        \\  <audioPackFormat audioPackFormatID="AP_00031001">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001">
        ,
    );
    defer std.testing.allocator.free(mixed_sources);
    const document = try Document.init(mixed_sources);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileComplementaryPackType,
        document.validateEmissionProfileComplementaryObjects(),
    );
}

test "ADM XML emission profile enforces derived complementary limits" {
    var excessive_tracks: std.Io.Writer.Allocating =
        .init(std.testing.allocator);
    defer excessive_tracks.deinit();
    try writeEmissionIndependentObjects(
        &excessive_tracks,
        1,
        &.{ 0x0017, 0x0003 },
        false,
    );
    const track_document = try Document.init(excessive_tracks.written());
    try std.testing.expectError(
        error.AdmEmissionProfileNonComplementaryTrackLimitExceeded,
        track_document.validateEmissionProfileComplementaryObjects(),
    );

    var excessive_groups: std.Io.Writer.Allocating =
        .init(std.testing.allocator);
    defer excessive_groups.deinit();
    try writeEmissionIndependentObjects(
        &excessive_groups,
        2,
        &([_]u16{0x0001} ** 17),
        false,
    );
    const group_document = try Document.init(excessive_groups.written());
    try std.testing.expectError(
        error.AdmEmissionProfileIndependentGroupLimitExceeded,
        group_document.validateEmissionProfileComplementaryObjects(),
    );

    var complementary_tracks: std.Io.Writer.Allocating =
        .init(std.testing.allocator);
    defer complementary_tracks.deinit();
    try writeEmissionIndependentObjects(
        &complementary_tracks,
        1,
        &.{ 0x000f, 0x000f, 0x000f },
        true,
    );
    const complementary_document = try Document.init(
        complementary_tracks.written(),
    );
    try complementary_document.validateEmissionProfileComplementaryObjects();
}

test "ADM XML emission profile exposes complementary level limits" {
    const level_zero = emissionComplementaryLimits(.level_0);
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        level_zero.groups,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        level_zero.non_complementary_tracks,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        level_zero.independent_groups,
    );
    const level_one = emissionComplementaryLimits(.level_1);
    try std.testing.expectEqual(@as(usize, 8), level_one.groups);
    try std.testing.expectEqual(
        @as(usize, 16),
        level_one.non_complementary_tracks,
    );
    try std.testing.expectEqual(
        @as(usize, 16),
        level_one.independent_groups,
    );
    const level_two = emissionComplementaryLimits(.level_2);
    try std.testing.expectEqual(@as(usize, 14), level_two.groups);
    try std.testing.expectEqual(
        @as(usize, 28),
        level_two.non_complementary_tracks,
    );
    try std.testing.expectEqual(
        @as(usize, 16),
        level_two.independent_groups,
    );
}

const valid_emission_object_parameters_xml =
    \\<audioFormatExtended version="ITU-R_BS.2076-3">
    \\  <audioProgramme audioProgrammeID="APR_1001" audioProgrammeName="News" audioProgrammeLanguage="eng">
    \\    <audioProgrammeLabel language="eng">Evening News</audioProgrammeLabel>
    \\    <audioProgrammeLabel language="deu">Abendnachrichten</audioProgrammeLabel>
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\    <loudnessMetadata>
    \\      <integratedLoudness>-23.0</integratedLoudness>
    \\      <dialogueLoudness>-24.0</dialogueLoudness>
    \\    </loudnessMetadata>
    \\  </audioProgramme>
    \\  <audioContent audioContentID="ACO_1001" audioContentName="Commentary" audioContentLanguage="eng">
    \\    <audioContentLabel language="eng">Commentary</audioContentLabel>
    \\    <audioContentLabel language="fra">Commentaires</audioContentLabel>
    \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
    \\    <loudnessMetadata>
    \\      <integratedLoudness>-24.0</integratedLoudness>
    \\    </loudnessMetadata>
    \\    <dialogue dialogueContentKind="5">1</dialogue>
    \\  </audioContent>
    \\  <audioObject audioObjectID="AO_1001" audioObjectName="Commentary" interact="1">
    \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\    <audioObjectInteraction onOffInteract="0" gainInteract="1" positionInteract="1">
    \\      <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\      <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\      <positionInteractionRange coordinate="azimuth" bound="min">-10.0</positionInteractionRange>
    \\      <positionInteractionRange coordinate="azimuth" bound="max">10.0</positionInteractionRange>
    \\    </audioObjectInteraction>
    \\    <gain gainUnit="dB">-3.0</gain>
    \\    <positionOffset coordinate="azimuth">5.0</positionOffset>
    \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0001">
    \\      <gain gainUnit="dB">0.0</gain>
    \\      <audioObjectInteraction onOffInteract="0" gainInteract="0" positionInteract="0">
    \\        <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\        <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\        <positionInteractionRange coordinate="azimuth" bound="min">-10.0</positionInteractionRange>
    \\        <positionInteractionRange coordinate="azimuth" bound="max">10.0</positionInteractionRange>
    \\      </audioObjectInteraction>
    \\      <positionOffset coordinate="azimuth">0.0</positionOffset>
    \\    </alternativeValueSet>
    \\  </audioObject>
    \\  <audioPackFormat audioPackFormatID="AP_00031001" audioPackFormatName="Commentary Object" typeLabel="0003" typeDefinition="Objects">
    \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
    \\  </audioPackFormat>
    \\  <audioChannelFormat audioChannelFormatID="AC_00031001" audioChannelFormatName="Commentary Object" typeLabel="0003" typeDefinition="Objects">
    \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001" rtime="00:00:00.00000" duration="00:00:01.00000">
    \\      <position coordinate="azimuth">0.0</position>
    \\      <position coordinate="elevation">0.0</position>
    \\      <position coordinate="distance">1.0</position>
    \\    </audioBlockFormatObjects>
    \\  </audioChannelFormat>
    \\  <audioTrackUID UID="ATU_00000001" sampleRate="48000" bitDepth="24">
    \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <profileList>
    \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
    \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\  </profileList>
    \\</audioFormatExtended>
;

fn expectEmissionObjectParameterReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_object_parameters_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileObjectParameters(),
    );
}

test "ADM XML emission profile validates object interaction parameters" {
    const document = try Document.init(
        valid_emission_object_parameters_xml,
    );
    try document.validateEmissionProfileObjectParameters();

    const without_parameters = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        \\ interact="1">
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\    <audioObjectInteraction onOffInteract="0" gainInteract="1" positionInteract="1">
        \\      <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
        \\      <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
        \\      <positionInteractionRange coordinate="azimuth" bound="min">-10.0</positionInteractionRange>
        \\      <positionInteractionRange coordinate="azimuth" bound="max">10.0</positionInteractionRange>
        \\    </audioObjectInteraction>
        \\    <gain gainUnit="dB">-3.0</gain>
        \\    <positionOffset coordinate="azimuth">5.0</positionOffset>
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0001">
        \\      <gain gainUnit="dB">0.0</gain>
        \\      <audioObjectInteraction onOffInteract="0" gainInteract="0" positionInteract="0">
        \\        <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
        \\        <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
        \\        <positionInteractionRange coordinate="azimuth" bound="min">-10.0</positionInteractionRange>
        \\        <positionInteractionRange coordinate="azimuth" bound="max">10.0</positionInteractionRange>
        \\      </audioObjectInteraction>
        \\      <positionOffset coordinate="azimuth">0.0</positionOffset>
        \\    </alternativeValueSet>
    ,
        \\ interact="0">
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        ,
    );
    defer std.testing.allocator.free(without_parameters);
    const static_document = try Document.init(without_parameters);
    try static_document.validateEmissionProfileObjectParameters();
}

test "ADM XML emission profile requires object parameter attributes" {
    const multilingual_name = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "audioObjectName=\"Commentary\"",
        "audioObjectName=\"评论\"",
    );
    defer std.testing.allocator.free(multilingual_name);
    const multilingual_document = try Document.init(multilingual_name);
    try multilingual_document.validateEmissionProfileObjectParameters();

    try expectEmissionObjectParameterReplacement(
        error.MissingAdmEmissionProfileObjectName,
        " audioObjectName=\"Commentary\"",
        "",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileObjectName,
        "audioObjectName=\"Commentary\"",
        "audioObjectName=\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
    );
    try expectEmissionObjectParameterReplacement(
        error.MissingAdmEmissionProfileInteract,
        " interact=\"1\"",
        "",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileObjectAttribute,
        " interact=\"1\"",
        " interact=\"1\" disableDucking=\"1\"",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileObjectInteraction,
        " interact=\"1\"",
        " interact=\"0\"",
    );
}

test "ADM XML emission profile validates interaction ranges" {
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileObjectInteraction,
        "onOffInteract=\"0\" gainInteract=\"1\"",
        "onOffInteract=\"1\" gainInteract=\"1\"",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileGainInteractionRange,
        "      <gainInteractionRange bound=\"max\" gainUnit=\"dB\">6.0</gainInteractionRange>\n",
        "",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileGainInteractionRange,
        ">6.0</gainInteractionRange>",
        ">22.0</gainInteractionRange>",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfilePositionInteractionRange,
        "coordinate=\"azimuth\" bound=\"max\"",
        "coordinate=\"X\" bound=\"max\"",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileInteractionAttribute,
        "positionInteract=\"1\">",
        "positionInteract=\"1\" divergenceInteract=\"1\">",
    );
}

test "ADM XML emission profile bounds object parameter values" {
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileObjectGain,
        ">-3.0</gain>",
        ">22.0</gain>",
    );
    try expectEmissionObjectParameterReplacement(
        error.AdmEmissionProfileGainOutsideInteractionRange,
        ">-3.0</gain>",
        ">-7.0</gain>",
    );
    try expectEmissionObjectParameterReplacement(
        error.AdmEmissionProfilePositionOutsideInteractionRange,
        ">5.0</positionOffset>",
        ">11.0</positionOffset>",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfilePositionOffset,
        "<position coordinate=\"azimuth\">0.0</position>",
        "<position coordinate=\"azimuth\">1.0</position>",
    );
}

test "ADM XML emission profile rejects parameters on nested objects" {
    const nested_content = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        \\  <audioContent audioContentID="ACO_1001" audioContentName="Commentary" audioContentLanguage="eng">
        \\    <audioContentLabel language="eng">Commentary</audioContentLabel>
        \\    <audioContentLabel language="fra">Commentaires</audioContentLabel>
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\    <loudnessMetadata>
        \\      <integratedLoudness>-24.0</integratedLoudness>
        \\    </loudnessMetadata>
        \\    <dialogue dialogueContentKind="5">1</dialogue>
        \\  </audioContent>
    ,
        \\  <audioContent audioContentID="ACO_1001" audioContentName="Commentary" audioContentLanguage="eng">
        \\    <audioContentLabel language="eng">Commentary</audioContentLabel>
        \\    <audioContentLabel language="fra">Commentaires</audioContentLabel>
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\    <loudnessMetadata>
        \\      <integratedLoudness>-24.0</integratedLoudness>
        \\    </loudnessMetadata>
        \\    <dialogue dialogueContentKind="5">1</dialogue>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001" audioObjectName="Parent" interact="0">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        ,
    );
    defer std.testing.allocator.free(nested_content);
    const nested_object = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        nested_content,
        "audioObjectID=\"AO_1001\" audioObjectName=\"Commentary\"",
        "audioObjectID=\"AO_1002\" audioObjectName=\"Commentary\"",
    );
    defer std.testing.allocator.free(nested_object);
    const nested_alternative = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        nested_object,
        "alternativeValueSetID=\"AVS_1001_0001\"",
        "alternativeValueSetID=\"AVS_1002_0001\"",
    );
    defer std.testing.allocator.free(nested_alternative);
    const document = try Document.init(nested_alternative);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileObjectInteraction,
        document.validateEmissionProfileObjectParameters(),
    );
}

test "ADM XML emission profile validates alternative object parameters" {
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileAlternativeInteraction,
        "        <positionInteractionRange coordinate=\"azimuth\" bound=\"max\">10.0</positionInteractionRange>",
        "        <positionInteractionRange coordinate=\"azimuth\" bound=\"max\">9.0</positionInteractionRange>",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileAlternativeInteraction,
        "        <gainInteractionRange bound=\"min\" gainUnit=\"dB\">-6.0</gainInteractionRange>",
        "        <gainInteractionRange bound=\"min\" gainUnit=\"linear\">0.5011872336272722</gainInteractionRange>",
    );
    try expectEmissionObjectParameterReplacement(
        error.AdmEmissionProfileGainOutsideInteractionRange,
        "      <gain gainUnit=\"dB\">0.0</gain>",
        "      <gain gainUnit=\"dB\">-7.0</gain>",
    );
    try expectEmissionObjectParameterReplacement(
        error.InvalidAdmEmissionProfileAlternativeValueSet,
        "      <positionOffset coordinate=\"azimuth\">0.0</positionOffset>",
        "      <width>1.0</width>",
    );
}

test "ADM XML emission profile accepts Cartesian object controls" {
    const cartesian_ranges = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "positionInteractionRange coordinate=\"azimuth\"",
        "positionInteractionRange coordinate=\"X\"",
    );
    defer std.testing.allocator.free(cartesian_ranges);
    const cartesian_offsets = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        cartesian_ranges,
        "positionOffset coordinate=\"azimuth\"",
        "positionOffset coordinate=\"X\"",
    );
    defer std.testing.allocator.free(cartesian_offsets);
    const bounded = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        cartesian_offsets,
        ">-10.0</positionInteractionRange>",
        ">-1.0</positionInteractionRange>",
    );
    defer std.testing.allocator.free(bounded);
    const positioned = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        bounded,
        ">10.0</positionInteractionRange>",
        ">1.0</positionInteractionRange>",
    );
    defer std.testing.allocator.free(positioned);
    const offset = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        positioned,
        ">5.0</positionOffset>",
        ">0.5</positionOffset>",
    );
    defer std.testing.allocator.free(offset);
    const cartesian_block = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        offset,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001" rtime="00:00:00.00000" duration="00:00:01.00000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
    ,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001" rtime="00:00:00.00000" duration="00:00:01.00000">
        \\      <cartesian>1</cartesian>
        \\      <gain gainUnit="linear">3.1622776601683795</gain>
        \\      <objectDivergence positionRange="1.0">1.0</objectDivergence>
        \\      <position coordinate="X">0.0</position>
        \\      <position coordinate="Y">1.0</position>
        \\      <position coordinate="Z">0.0</position>
        ,
    );
    defer std.testing.allocator.free(cartesian_block);
    const document = try Document.init(cartesian_block);
    try document.validateEmissionProfileObjectParameters();
    try document.validateEmissionProfileObjectBlocks();
}

fn expectEmissionMetadataReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_object_parameters_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileProgrammeContentMetadata(),
    );
}

test "ADM XML emission profile validates programme and content metadata" {
    const document = try Document.init(
        valid_emission_object_parameters_xml,
    );
    try document.validateEmissionProfileProgrammeContentMetadata();

    const private_language = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "audioProgrammeLanguage=\"eng\"",
        "audioProgrammeLanguage=\"qaz\"",
    );
    defer std.testing.allocator.free(private_language);
    const private_document = try Document.init(private_language);
    try private_document.validateEmissionProfileProgrammeContentMetadata();

    try std.testing.expect(isIso6392Code("eng"));
    try std.testing.expect(isIso6392Code("fre"));
    try std.testing.expect(isIso6392Code("fra"));
    try std.testing.expect(isIso6392Code("und"));
    try std.testing.expect(isIso6392Code("qaz"));
    try std.testing.expect(!isIso6392Code("aaa"));
    try std.testing.expect(!isIso6392Code("ENG"));
    try std.testing.expect(!isIso6392Code("en"));
    try std.testing.expectEqual(
        @as(usize, 0),
        iso_639_2_codes.len % 3,
    );
    var code_index: usize = 0;
    while (code_index < iso_639_2_codes.len / 3) : (code_index += 1) {
        const code = iso_639_2_codes[code_index * 3 ..][0..3];
        try std.testing.expect(isIso6392Code(code));
        if (code_index != 0) {
            const previous =
                iso_639_2_codes[(code_index - 1) * 3 ..][0..3];
            try std.testing.expectEqual(
                std.math.Order.lt,
                std.mem.order(u8, previous, code),
            );
        }
    }
}

test "ADM XML emission profile requires metadata attributes" {
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileName,
        " audioProgrammeName=\"News\"",
        "",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileName,
        "audioContentName=\"Commentary\"",
        "audioContentName=\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
    );
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileLanguage,
        " audioContentLanguage=\"eng\"",
        "",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLanguage,
        "audioProgrammeLanguage=\"eng\"",
        "audioProgrammeLanguage=\"aaa\"",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileProgrammeAttribute,
        " audioProgrammeLanguage=\"eng\"",
        " audioProgrammeLanguage=\"eng\" start=\"00:00:00.00000\"",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileContentAttribute,
        " audioContentLanguage=\"eng\"",
        " audioContentLanguage=\"eng\" custom=\"value\"",
    );
}

test "ADM XML emission profile validates localized labels" {
    try expectEmissionMetadataReplacement(
        error.DuplicateAdmEmissionProfileLabelLanguage,
        "<audioProgrammeLabel language=\"deu\">Abendnachrichten</audioProgrammeLabel>",
        "<audioProgrammeLabel language=\"eng\">Evening Bulletin</audioProgrammeLabel>",
    );
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileLanguage,
        "audioContentLabel language=\"fra\"",
        "audioContentLabel",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLabel,
        ">Commentaires</audioContentLabel>",
        "></audioContentLabel>",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLabelAttribute,
        "audioProgrammeLabel language=\"deu\"",
        "audioProgrammeLabel language=\"deu\" role=\"short\"",
    );
}

test "ADM XML emission profile validates loudness metadata" {
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileLoudnessMetadata,
        "    <loudnessMetadata>\n" ++
            "      <integratedLoudness>-24.0</integratedLoudness>\n" ++
            "    </loudnessMetadata>\n" ++
            "    <dialogue dialogueContentKind=\"5\">1</dialogue>\n",
        "    <dialogue dialogueContentKind=\"5\">1</dialogue>\n",
    );
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileLoudnessValue,
        "      <integratedLoudness>-24.0</integratedLoudness>\n",
        "",
    );
    try expectEmissionMetadataReplacement(
        error.DuplicateAdmEmissionProfileLoudnessValue,
        "      <integratedLoudness>-24.0</integratedLoudness>",
        "      <integratedLoudness>-24.0</integratedLoudness>\n" ++
            "      <integratedLoudness>-23.0</integratedLoudness>",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLoudnessValue,
        ">-24.0</dialogueLoudness>",
        ">nan</dialogueLoudness>",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLoudnessAttribute,
        "<loudnessMetadata>",
        "<loudnessMetadata loudnessMethod=\"ITU-R BS.1770\">",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileLoudnessSubelement,
        "      <integratedLoudness>-24.0</integratedLoudness>",
        "      <maxTruePeak>-1.0</maxTruePeak>",
    );
}

test "ADM XML emission profile validates dialogue classification" {
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileDialogue,
        "    <dialogue dialogueContentKind=\"5\">1</dialogue>\n",
        "",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileDialogue,
        ">1</dialogue>",
        ">3</dialogue>",
    );
    try expectEmissionMetadataReplacement(
        error.MissingAdmEmissionProfileDialogueKind,
        " dialogueContentKind=\"5\"",
        "",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileDialogueAttribute,
        "dialogue dialogueContentKind=\"5\"",
        "dialogue nonDialogueContentKind=\"1\"",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileDialogueKind,
        "dialogueContentKind=\"5\"",
        "dialogueContentKind=\"7\"",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileContentSubelement,
        "    <dialogue dialogueContentKind=\"5\">1</dialogue>",
        "    <dialogue dialogueContentKind=\"5\">1</dialogue>\n" ++
            "    <authoringInformation/>",
    );
    try expectEmissionMetadataReplacement(
        error.InvalidAdmEmissionProfileProgrammeSubelement,
        "    <audioContentIDRef>ACO_1001</audioContentIDRef>",
        "    <audioContentIDRef>ACO_1001</audioContentIDRef>\n" ++
            "    <authoringInformation/>",
    );
}

fn expectEmissionFormatMetadataReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_object_parameters_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileFormatMetadata(),
    );
}

test "ADM XML emission profile validates format metadata" {
    const document = try Document.init(
        valid_emission_object_parameters_xml,
    );
    try document.validateEmissionProfileFormatMetadata();
}

test "ADM XML emission profile requires format attributes" {
    try expectEmissionFormatMetadataReplacement(
        error.MissingAdmEmissionProfileName,
        " audioPackFormatName=\"Commentary Object\"",
        "",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileFormatAttribute,
        "typeLabel=\"0003\" typeDefinition=\"Objects\"",
        "typeLabel=\"0002\" typeDefinition=\"Objects\"",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileFormatAttribute,
        "typeLabel=\"0003\" typeDefinition=\"Objects\"",
        "typeLabel=\"0003\" typeDefinition=\"Matrix\"",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileFormatAttribute,
        " typeDefinition=\"Objects\">",
        " typeDefinition=\"Objects\" importance=\"10\">",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileFormatAttribute,
        "audioChannelFormatName=\"Commentary Object\"",
        "audioChannelFormatName=\"Commentary Object\" frequency=\"120\"",
    );
}

test "ADM XML emission profile restricts format structure" {
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfilePackSubelement,
        "    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>\n" ++
            "  </audioPackFormat>",
        "    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>\n" ++
            "    <absoluteDistance>1.0</absoluteDistance>\n" ++
            "  </audioPackFormat>",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileReferenceAttribute,
        "<audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>",
        "<audioChannelFormatIDRef role=\"main\">AC_00031001</audioChannelFormatIDRef>",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileChannelSubelement,
        "    <audioBlockFormatObjects audioBlockFormatID=\"AB_00031001_00000001\" rtime=\"00:00:00.00000\" duration=\"00:00:01.00000\">",
        "    <frequency typeDefinition=\"lowPass\">120</frequency>\n" ++
            "    <audioBlockFormatObjects audioBlockFormatID=\"AB_00031001_00000001\" rtime=\"00:00:00.00000\" duration=\"00:00:01.00000\">",
    );
}

test "ADM XML emission profile restricts track metadata" {
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileTrackAttribute,
        " sampleRate=\"48000\"",
        " sampleRate=\"0\"",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileTrackAttribute,
        " bitDepth=\"24\">",
        " bitDepth=\"24\" custom=\"value\">",
    );
    try expectEmissionFormatMetadataReplacement(
        error.InvalidAdmEmissionProfileTrackSubelement,
        "    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>\n" ++
            "  </audioTrackUID>",
        "    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>\n" ++
            "    <audioMXFLookUp>1</audioMXFLookUp>\n" ++
            "  </audioTrackUID>",
    );
}

fn expectEmissionObjectBlockReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_object_parameters_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileObjectBlocks(),
    );
}

test "ADM XML emission profile validates file object blocks" {
    const document = try Document.init(
        valid_emission_object_parameters_xml,
    );
    try document.validateEmissionProfileObjectBlocks();

    const minimum_duration = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "duration=\"00:00:01.00000\"",
        "duration=\"00:00:00.00500\"",
    );
    defer std.testing.allocator.free(minimum_duration);
    const minimum_document = try Document.init(minimum_duration);
    try minimum_document.validateEmissionProfileObjectBlocks();

    const zero_duration = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "duration=\"00:00:01.00000\"",
        "duration=\"00:00:00.00000\"",
    );
    defer std.testing.allocator.free(zero_duration);
    const zero_document = try Document.init(zero_duration);
    try zero_document.validateEmissionProfileObjectBlocks();
}

test "ADM XML emission profile requires continuous file block timing" {
    try expectEmissionObjectBlockReplacement(
        error.MissingAdmEmissionProfileBlockTiming,
        " rtime=\"00:00:00.00000\"",
        "",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileBlockDuration,
        "duration=\"00:00:01.00000\"",
        "duration=\"00:00:00.00499\"",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileBlockAttribute,
        " duration=\"00:00:01.00000\">",
        " duration=\"00:00:01.00000\" initializeBlock=\"1\">",
    );

    const discontinuous = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "    </audioBlockFormatObjects>\n  </audioChannelFormat>",
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000002" rtime="00:00:00.50000" duration="00:00:01.00000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        ,
    );
    defer std.testing.allocator.free(discontinuous);
    const discontinuous_document = try Document.init(discontinuous);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileBlockTiming,
        discontinuous_document.validateEmissionProfileObjectBlocks(),
    );

    const fractional_duration = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "duration=\"00:00:01.00000\"",
        "duration=\"48000S48000\"",
    );
    defer std.testing.allocator.free(fractional_duration);
    const continuous = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        fractional_duration,
        "    </audioBlockFormatObjects>\n  </audioChannelFormat>",
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000002" rtime="00:00:01.00000" duration="00:00:00.00000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        ,
    );
    defer std.testing.allocator.free(continuous);
    const continuous_document = try Document.init(continuous);
    try continuous_document.validateEmissionProfileObjectBlocks();
}

test "ADM XML emission profile restricts file block positions" {
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileBlockPosition,
        "      <position coordinate=\"distance\">1.0</position>\n",
        "",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileBlockParameterAttribute,
        "<position coordinate=\"azimuth\">0.0</position>",
        "<position coordinate=\"azimuth\" screenEdgeLock=\"left\">0.0</position>",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileCartesianFlag,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <cartesian>0</cartesian>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );

    const mixed = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "    </audioBlockFormatObjects>\n  </audioChannelFormat>",
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000002" rtime="00:00:01.00000" duration="00:00:00.00000">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0.0</position>
        \\      <position coordinate="Y">1.0</position>
        \\      <position coordinate="Z">0.0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        ,
    );
    defer std.testing.allocator.free(mixed);
    const mixed_document = try Document.init(mixed);
    try std.testing.expectError(
        error.MixedAdmEmissionProfileCoordinateSystems,
        mixed_document.validateEmissionProfileObjectBlocks(),
    );
}

test "ADM XML emission profile restricts file block parameters" {
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileBlockSubelement,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <width>1.0</width>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileObjectDivergence,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <objectDivergence>0.5</objectDivergence>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileObjectBlockGain,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <gain gainUnit=\"dB\">10.001</gain>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );
    try expectEmissionObjectBlockReplacement(
        error.InvalidAdmEmissionProfileJumpPosition,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <jumpPosition interpolationLength=\"00:00:00.50000\">1</jumpPosition>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );

    const boundary_gain = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "      <position coordinate=\"azimuth\">0.0</position>",
        "      <gain gainUnit=\"dB\">10.0</gain>\n" ++
            "      <objectDivergence azimuthRange=\"180.0\">1.0</objectDivergence>\n" ++
            "      <jumpPosition>1</jumpPosition>\n" ++
            "      <position coordinate=\"azimuth\">0.0</position>",
    );
    defer std.testing.allocator.free(boundary_gain);
    const boundary_document = try Document.init(boundary_gain);
    try boundary_document.validateEmissionProfileObjectBlocks();
}

test "ADM XML file block validation rejects serial frames" {
    const framed_start = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "<audioFormatExtended version=\"ITU-R_BS.2076-3\">",
        "<frame><audioFormatExtended version=\"ITU-R_BS.2076-3\">",
    );
    defer std.testing.allocator.free(framed_start);
    const framed = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed_start,
        "</audioFormatExtended>",
        "</audioFormatExtended></frame>",
    );
    defer std.testing.allocator.free(framed);
    const document = try Document.init(framed);
    try std.testing.expectError(
        error.AdmEmissionProfileSerialBlocksRequireSerialValidation,
        document.validateEmissionProfileObjectBlocks(),
    );
}

const valid_emission_complementary_parameters_xml =
    \\<audioFormatExtended version="ITU-R_BS.2076-3">
    \\  <audioProgramme audioProgrammeID="APR_1001">
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\    <audioContentIDRef>ACO_1002</audioContentIDRef>
    \\    <alternativeValueSetIDRef>AVS_1001_0001</alternativeValueSetIDRef>
    \\    <alternativeValueSetIDRef>AVS_1002_0001</alternativeValueSetIDRef>
    \\  </audioProgramme>
    \\  <audioContent audioContentID="ACO_1001">
    \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioContent audioContentID="ACO_1002">
    \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
    \\  </audioContent>
    \\  <audioObject audioObjectID="AO_1001" audioObjectName="English" interact="1">
    \\    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\    <audioObjectInteraction onOffInteract="0" gainInteract="1">
    \\      <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\      <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\    </audioObjectInteraction>
    \\    <gain gainUnit="dB">-3.0</gain>
    \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0001">
    \\      <gain gainUnit="dB">0.0</gain>
    \\      <audioObjectInteraction onOffInteract="0" gainInteract="0">
    \\        <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\        <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\      </audioObjectInteraction>
    \\    </alternativeValueSet>
    \\  </audioObject>
    \\  <audioObject audioObjectID="AO_1002" audioObjectName="French" interact="1">
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
    \\    <audioObjectInteraction onOffInteract="0" gainInteract="1">
    \\      <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\      <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\    </audioObjectInteraction>
    \\    <gain gainUnit="dB">-3.0</gain>
    \\    <alternativeValueSet alternativeValueSetID="AVS_1002_0001">
    \\      <gain gainUnit="dB">0.0</gain>
    \\      <audioObjectInteraction onOffInteract="0" gainInteract="0">
    \\        <gainInteractionRange bound="min" gainUnit="dB">-6.0</gainInteractionRange>
    \\        <gainInteractionRange bound="max" gainUnit="dB">6.0</gainInteractionRange>
    \\      </audioObjectInteraction>
    \\    </alternativeValueSet>
    \\  </audioObject>
    \\  <audioTrackUID UID="ATU_00000001">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <audioTrackUID UID="ATU_00000002">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <profileList>
    \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
    \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\  </profileList>
    \\</audioFormatExtended>
;

fn expectEmissionComplementaryParameterReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_parameters_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_complementary_parameters_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileComplementaryParameters(),
    );
}

test "ADM XML emission profile validates complementary parameters" {
    const document = try Document.init(
        valid_emission_complementary_parameters_xml,
    );
    try document.validateEmissionProfileComplementaryParameters();

    const without_alternatives = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_parameters_xml,
        "    <alternativeValueSetIDRef>AVS_1001_0001</alternativeValueSetIDRef>\n" ++
            "    <alternativeValueSetIDRef>AVS_1002_0001</alternativeValueSetIDRef>\n",
        "",
    );
    defer std.testing.allocator.free(without_alternatives);
    const static_document = try Document.init(without_alternatives);
    try static_document.validateEmissionProfileComplementaryParameters();

    const fixed_first = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_parameters_xml,
        "    <audioContentIDRef>ACO_1002</audioContentIDRef>\n" ++
            "    <alternativeValueSetIDRef>AVS_1002_0001</alternativeValueSetIDRef>\n",
        "",
    );
    defer std.testing.allocator.free(fixed_first);
    const fixed_programmes = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        fixed_first,
        "  <audioContent audioContentID=\"ACO_1001\">",
        "  <audioProgramme audioProgrammeID=\"APR_1002\">\n" ++
            "    <audioContentIDRef>ACO_1002</audioContentIDRef>\n" ++
            "    <alternativeValueSetIDRef>AVS_1002_0001</alternativeValueSetIDRef>\n" ++
            "  </audioProgramme>\n" ++
            "  <audioContent audioContentID=\"ACO_1001\">",
    );
    defer std.testing.allocator.free(fixed_programmes);
    const fixed_document = try Document.init(fixed_programmes);
    try fixed_document.validateEmissionProfileComplementaryParameters();
}

test "ADM XML emission profile requires equal complementary defaults" {
    try expectEmissionComplementaryParameterReplacement(
        error.InvalidAdmEmissionProfileComplementaryParameters,
        "    <gain gainUnit=\"dB\">-3.0</gain>\n" ++
            "    <alternativeValueSet alternativeValueSetID=\"AVS_1002_0001\">",
        "    <gain gainUnit=\"dB\">-2.0</gain>\n" ++
            "    <alternativeValueSet alternativeValueSetID=\"AVS_1002_0001\">",
    );
    try expectEmissionComplementaryParameterReplacement(
        error.InvalidAdmEmissionProfileComplementaryParameters,
        "  <audioObject audioObjectID=\"AO_1002\" audioObjectName=\"French\" interact=\"1\">\n" ++
            "    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>\n" ++
            "    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>\n" ++
            "    <audioObjectInteraction onOffInteract=\"0\" gainInteract=\"1\">",
        "  <audioObject audioObjectID=\"AO_1002\" audioObjectName=\"French\" interact=\"1\">\n" ++
            "    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>\n" ++
            "    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>\n" ++
            "    <audioObjectInteraction onOffInteract=\"0\" gainInteract=\"0\">",
    );
}

test "ADM XML emission profile requires complete programme alternatives" {
    try expectEmissionComplementaryParameterReplacement(
        error.InvalidAdmEmissionProfileComplementaryAlternative,
        "    <alternativeValueSetIDRef>AVS_1002_0001</alternativeValueSetIDRef>\n",
        "",
    );
    try expectEmissionComplementaryParameterReplacement(
        error.InvalidAdmEmissionProfileComplementaryAlternative,
        "      <gain gainUnit=\"dB\">0.0</gain>\n" ++
            "      <audioObjectInteraction onOffInteract=\"0\" gainInteract=\"0\">\n" ++
            "        <gainInteractionRange bound=\"min\" gainUnit=\"dB\">-6.0</gainInteractionRange>\n" ++
            "        <gainInteractionRange bound=\"max\" gainUnit=\"dB\">6.0</gainInteractionRange>\n" ++
            "      </audioObjectInteraction>\n" ++
            "    </alternativeValueSet>\n" ++
            "  </audioObject>\n" ++
            "  <audioTrackUID UID=\"ATU_00000001\">",
        "      <gain gainUnit=\"dB\">-1.0</gain>\n" ++
            "      <audioObjectInteraction onOffInteract=\"0\" gainInteract=\"0\">\n" ++
            "        <gainInteractionRange bound=\"min\" gainUnit=\"dB\">-6.0</gainInteractionRange>\n" ++
            "        <gainInteractionRange bound=\"max\" gainUnit=\"dB\">6.0</gainInteractionRange>\n" ++
            "      </audioObjectInteraction>\n" ++
            "    </alternativeValueSet>\n" ++
            "  </audioObject>\n" ++
            "  <audioTrackUID UID=\"ATU_00000001\">",
    );
    try expectEmissionComplementaryParameterReplacement(
        error.InvalidAdmEmissionProfileProgrammeAlternative,
        "    <alternativeValueSetIDRef>AVS_1001_0001</alternativeValueSetIDRef>\n",
        "    <alternativeValueSetIDRef>AVS_1001_0001</alternativeValueSetIDRef>\n" ++
            "    <alternativeValueSetIDRef>AVS_1001_0001</alternativeValueSetIDRef>\n",
    );

    const unassociated_content = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_complementary_parameters_xml,
        "    <audioContentIDRef>ACO_1002</audioContentIDRef>\n",
        "",
    );
    defer std.testing.allocator.free(unassociated_content);
    const unassociated_programme = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        unassociated_content,
        "  <audioContent audioContentID=\"ACO_1001\">",
        "  <audioProgramme audioProgrammeID=\"APR_1002\">\n" ++
            "    <audioContentIDRef>ACO_1002</audioContentIDRef>\n" ++
            "  </audioProgramme>\n" ++
            "  <audioContent audioContentID=\"ACO_1001\">",
    );
    defer std.testing.allocator.free(unassociated_programme);
    const document = try Document.init(unassociated_programme);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileProgrammeAlternative,
        document.validateEmissionProfileComplementaryParameters(),
    );
}

test "ADM XML emission profile validates complete object sources" {
    const document = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\    <audioContentIDRef>ACO_1002</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioContent audioContentID="ACO_1002">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1003</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1003">
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000003</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioPackFormat audioPackFormatID="AP_00031001">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00010002</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000003">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try document.validateEmissionProfileObjectSources();
}

test "ADM XML emission profile registers every permitted common pack" {
    const cases = [_]struct {
        index: u16,
        channels: usize,
    }{
        .{ .index = 0x0001, .channels = 1 },
        .{ .index = 0x0002, .channels = 2 },
        .{ .index = 0x000a, .channels = 3 },
        .{ .index = 0x0003, .channels = 6 },
        .{ .index = 0x000c, .channels = 5 },
        .{ .index = 0x000f, .channels = 8 },
        .{ .index = 0x001b, .channels = 7 },
        .{ .index = 0x0004, .channels = 8 },
        .{ .index = 0x001c, .channels = 7 },
        .{ .index = 0x0005, .channels = 10 },
        .{ .index = 0x001e, .channels = 9 },
        .{ .index = 0x0017, .channels = 12 },
        .{ .index = 0x001f, .channels = 11 },
        .{ .index = 0x0009, .channels = 24 },
        .{ .index = 0x0010, .channels = 22 },
        .{ .index = 0x0801, .channels = 1 },
        .{ .index = 0x0802, .channels = 2 },
        .{ .index = 0x080a, .channels = 3 },
        .{ .index = 0x0803, .channels = 6 },
        .{ .index = 0x080c, .channels = 5 },
        .{ .index = 0x080f, .channels = 8 },
        .{ .index = 0x081b, .channels = 7 },
        .{ .index = 0x0804, .channels = 8 },
        .{ .index = 0x081c, .channels = 7 },
        .{ .index = 0x0805, .channels = 10 },
        .{ .index = 0x081e, .channels = 9 },
        .{ .index = 0x0817, .channels = 12 },
        .{ .index = 0x081f, .channels = 11 },
        .{ .index = 0x0809, .channels = 24 },
        .{ .index = 0x0810, .channels = 22 },
    };
    for (cases) |case| {
        const channels = commonEmissionPackChannelIndexes(case.index).?;
        try std.testing.expectEqual(case.channels, channels.len);
        for (channels, 0..) |channel, index| {
            for (channels[0..index]) |previous| {
                try std.testing.expect(channel != previous);
            }
        }
    }
    try std.testing.expectEqual(
        @as(?[]const u16, null),
        commonEmissionPackChannelIndexes(0x0006),
    );

    const forbidden_outputs = [_]u16{
        0x000a, 0x000c, 0x001b, 0x001c, 0x001e, 0x001f, 0x0010,
        0x080a, 0x080c, 0x081b, 0x081c, 0x081e, 0x081f, 0x0810,
    };
    for (forbidden_outputs) |index| {
        try std.testing.expect(!commonEmissionPackIsMatrixOutput(index));
    }
    for (cases) |case| {
        var forbidden = false;
        for (forbidden_outputs) |index| {
            if (case.index == index) forbidden = true;
        }
        if (!forbidden)
            try std.testing.expect(commonEmissionPackIsMatrixOutput(case.index));
    }
    try std.testing.expect(!commonEmissionPackIsMatrixOutput(0x0006));
}

test "ADM XML emission profile enforces conditional object sources" {
    const missing_leaf_pack = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileObjectSource,
        missing_leaf_pack.validateEmissionProfileObjectSources(),
    );

    const source_on_branch = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioPackFormat audioPackFormatID="AP_00031001">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00031001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileObjectSource,
        source_on_branch.validateEmissionProfileObjectSources(),
    );
}

test "ADM XML emission profile restricts nested and common packs" {
    const nested_speaker_source = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileNestedObjectPack,
        nested_speaker_source.validateEmissionProfileObjectSources(),
    );

    const unsupported_common_pack = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010006</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010006</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfilePackReference,
        unsupported_common_pack.validateEmissionProfileObjectSources(),
    );

    const excessive_level_one_layout = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010009</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010018</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010009</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.AdmEmissionProfileLayoutChannelLimitExceeded,
        excessive_level_one_layout.validateEmissionProfileObjectSources(),
    );
}

test "ADM XML emission profile validates exact track mappings" {
    const wrong_common_channel = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileTrackReference,
        wrong_common_channel.validateEmissionProfileObjectSources(),
    );

    const duplicate_channel = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00010001</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010002</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileTrackReference,
        duplicate_channel.validateEmissionProfileObjectSources(),
    );

    const silent_track = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000000</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.SilentAdmEmissionProfileTrack,
        silent_track.validateEmissionProfileObjectSources(),
    );
}

test "ADM XML emission profile requires every declared source to be used" {
    const orphan_track = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000002">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileTrackParent,
        orphan_track.validateEmissionProfileObjectSources(),
    );

    const orphan_pack = try Document.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001">
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001">
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioPackFormat audioPackFormatID="AP_00031001">
        \\    <audioChannelFormatIDRef>AC_00031001</audioChannelFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001"/>
        \\  <audioTrackUID UID="ATU_00000001">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectError(
        error.UnreferencedAdmEmissionProfilePack,
        orphan_pack.validateEmissionProfileObjectSources(),
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
