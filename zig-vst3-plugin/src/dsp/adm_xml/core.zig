const std = @import("std");
const adm = @import("../adm.zig");
const adm_time = @import("../adm_time.zig");
const block_reader = @import("block.zig");
const common = @import("common.zig");
const emission = @import("emission.zig");
const metadata = @import("metadata.zig");
const model = @import("model.zig");
const standard = @import("standard.zig");
const xml = @import("../xml.zig");

const MetadataSource = metadata.MetadataSource;
const MetadataEventIterator = metadata.MetadataEventIterator;
const parseAdmFlag = model.parseAdmFlag;
const parseGainUnit = model.parseGainUnit;
const parseAdmMatrixGain = model.parseAdmMatrixGain;
const parseFiniteAdmFloat = model.parseFiniteAdmFloat;
const DeclarationSpec = common.DeclarationSpec;
const declarationSpec = common.declarationSpec;
const insideAfe = common.insideAfe;
const isXmlNamespaceDeclaration = common.isXmlNamespaceDeclaration;
pub const Extension = metadata.Extension;
pub const UntypedElement = metadata.UntypedElement;
pub const ExtensionIterator = metadata.ExtensionIterator;
pub const UntypedElementIterator = metadata.UntypedElementIterator;
pub const ExtensionAttribute = metadata.ExtensionAttribute;
pub const ExtensionAttributeIterator = metadata.ExtensionAttributeIterator;
pub const UntypedAttribute = metadata.UntypedAttribute;
pub const UntypedAttributeIterator = metadata.UntypedAttributeIterator;
pub const Profile = emission.Profile;
pub const EmissionProfileLevel = emission.EmissionProfileLevel;
pub const EmissionPcmEssence = emission.EmissionPcmEssence;
pub const EmissionSerialFlowState = emission.EmissionSerialFlowState;
const EmissionSerialLookup = emission.SerialLookup;
const EmissionElementCounts = emission.EmissionElementCounts;
const EmissionSubelementOwner = emission.EmissionSubelementOwner;
const EmissionSubelementCounts = emission.EmissionSubelementCounts;
const EmissionObjectParent = emission.EmissionObjectParent;
const EmissionPackChannels = emission.EmissionPackChannels;
const EmissionMatrixPack = emission.EmissionMatrixPack;
const EmissionObjectInteraction = emission.EmissionObjectInteraction;
const EmissionObjectParameterState = emission.EmissionObjectParameterState;
const EmissionAlternativeParameters = emission.EmissionAlternativeParameters;
const EmissionLanguageSet = emission.EmissionLanguageSet;
const EmissionFormatOwner = emission.EmissionFormatOwner;
const emissionProfileLimits = emission.emissionProfileLimits;
const emissionSubelementLimits = emission.emissionSubelementLimits;
const emissionMaximumLayoutChannels = emission.emissionMaximumLayoutChannels;
const emissionComplementaryLimits = emission.emissionComplementaryLimits;
const commonEmissionPackChannelIndexes = emission.commonEmissionPackChannelIndexes;
const commonEmissionPackIsMatrixOutput = emission.commonEmissionPackIsMatrixOutput;
const emissionCommonPackChannels = emission.emissionCommonPackChannels;
const validateEmissionMatrixCoefficients = emission.validateEmissionMatrixCoefficients;
const emissionElementIdentifier = emission.emissionElementIdentifier;
const validateEmissionObjectAttributes = emission.validateEmissionObjectAttributes;
const isIso6392Code = emission.isIso6392Code;
const emissionRequiredLanguageAttribute = emission.emissionRequiredLanguageAttribute;
const emissionRequiredAttributeValueAs = emission.emissionRequiredAttributeValueAs;
const validateEmissionFormatDeclarationAttributes = emission.validateEmissionFormatDeclarationAttributes;
const validateEmissionTrackUidAttributes = emission.validateEmissionTrackUidAttributes;
const emissionOptionalPositiveAttribute = emission.emissionOptionalPositiveAttribute;
const emissionOptionalPositiveAttributeAs = emission.emissionOptionalPositiveAttributeAs;
const emissionRequiredFlagAttribute = emission.emissionRequiredFlagAttribute;
const isEmissionObjectReferenceOrLabel = emission.isEmissionObjectReferenceOrLabel;
const readEmissionObjectInteraction = emission.readEmissionObjectInteraction;
const readEmissionGain = emission.readEmissionGain;
const readEmissionPositionOffset = emission.readEmissionPositionOffset;
const readEmissionAlternativeValueSet = emission.readEmissionAlternativeValueSet;
const validateEmissionGainWithinRange = emission.validateEmissionGainWithinRange;
const validateEmissionPositionWithinRange = emission.validateEmissionPositionWithinRange;
const emissionObjectParametersEqual = emission.emissionObjectParametersEqual;
const emissionObjectBlockHasNeutralPosition = emission.emissionObjectBlockHasNeutralPosition;
const emissionGainLinear = emission.emissionGainLinear;
const validateEmissionAttributes = emission.validateEmissionAttributes;
const validateAdmAttributes = emission.validateAdmAttributes;
const readEmissionSimpleElement = emission.readEmissionSimpleElement;
const emissionSerialTimeAttribute = emission.emissionSerialTimeAttribute;
const decodeEmissionSerialFlowIdentifier = emission.decodeEmissionSerialFlowIdentifier;
const sumAdmTime = emission.sumAdmTime;
const readEmissionSerialFrameHeader = emission.readEmissionSerialFrameHeader;
const readEmissionSerialTransport = emission.readEmissionSerialTransport;
const readEmissionProgrammeMetadata = emission.readEmissionProgrammeMetadata;
const readEmissionContentMetadata = emission.readEmissionContentMetadata;
const noteEmissionFormatChild = emission.noteEmissionFormatChild;
const validateEmissionFormatOwner = emission.validateEmissionFormatOwner;
const readEmissionObjectBlockSyntax = emission.readEmissionObjectBlockSyntax;
const readEmissionObjectBlockSyntaxWithTiming = emission.readEmissionObjectBlockSyntaxWithTiming;
const readEmissionObjectLabels = emission.readEmissionObjectLabels;
const readEmissionOwnerLabelLanguages = emission.readEmissionOwnerLabelLanguages;
const skipEmissionElement = emission.skipEmissionElement;
const emissionElementTypeLabel = emission.emissionElementTypeLabel;
const profilesEqual = emission.profilesEqual;
const isEmissionProfile = emission.isEmissionProfile;
const iso_639_2_codes = emission.iso_639_2_codes;

const max_identifier_bytes = common.max_identifier_bytes;
const max_profile_text_bytes = common.max_profile_text_bytes;
pub const max_adm_positions = model.max_adm_positions;
pub const max_adm_speaker_labels = model.max_adm_speaker_labels;
pub const max_adm_speaker_label_bytes = model.max_adm_speaker_label_bytes;
pub const max_adm_matrix_coefficients = model.max_adm_matrix_coefficients;
pub const max_adm_exclusion_zones = model.max_adm_exclusion_zones;
pub const Tag = model.Tag;
pub const TagTarget = model.TagTarget;
pub const TagItem = model.TagItem;
pub const GainUnit = model.GainUnit;
pub const Gain = model.Gain;
pub const Frequency = model.Frequency;
pub const JumpPosition = model.JumpPosition;
pub const HeadphoneVirtualise = model.HeadphoneVirtualise;
pub const Coordinate = model.Coordinate;
pub const PositionBound = model.PositionBound;
pub const ScreenEdge = model.ScreenEdge;
pub const Position = model.Position;
pub const SpeakerLabel = model.SpeakerLabel;
pub const ObjectDivergence = model.ObjectDivergence;
pub const ChannelLock = model.ChannelLock;
pub const CartesianExclusionZone = model.CartesianExclusionZone;
pub const PolarExclusionZone = model.PolarExclusionZone;
pub const ExclusionZone = model.ExclusionZone;
pub const HoaNormalization = model.HoaNormalization;
pub const AdmText = model.AdmText;
pub const MatrixCoefficient = model.MatrixCoefficient;
pub const BlockFormat = model.BlockFormat;
pub const BlockIterator = block_reader.BlockIterator;

pub const Limits = struct {
    max_document_bytes: usize = 16 * 1024 * 1024,
    max_xml_events: usize = 1_000_000,
    max_declarations: usize = 4_096,
    max_references: usize = 16_384,
    max_profiles: usize = 1_024,
    max_tag_groups: usize = 4_096,
    max_tags: usize = 16_384,
    max_tag_targets: usize = 16_384,
    max_blocks: usize = 16_384,
    max_extensions: usize = 16_384,
    max_extension_attributes: usize = 65_536,
    max_untyped_elements: usize = 16_384,
    max_untyped_attributes: usize = 65_536,
    max_validation_work: usize = 4_000_000,

    pub fn validate(self: Limits) !void {
        if (self.max_document_bytes == 0 or
            self.max_xml_events == 0 or
            self.max_declarations == 0 or
            self.max_references == 0 or
            self.max_profiles == 0 or
            self.max_tag_groups == 0 or
            self.max_tags == 0 or
            self.max_tag_targets == 0 or
            self.max_blocks == 0 or
            self.max_extensions == 0 or
            self.max_extension_attributes == 0 or
            self.max_untyped_elements == 0 or
            self.max_untyped_attributes == 0 or
            self.max_validation_work == 0 or
            self.max_declarations > declaration_index_capacity)
        {
            return error.InvalidAdmXmlLimits;
        }
    }
};

pub const default_limits = Limits{};

pub const Declaration = standard.Declaration;
pub const ReferenceKind = standard.ReferenceKind;
pub const Reference = standard.Reference;
pub const ProfileIterator = standard.ProfileIterator;
pub const TagIterator = standard.TagIterator;
pub const DeclarationIterator = standard.DeclarationIterator;
pub const ReferenceIterator = standard.ReferenceIterator;

const ValidationBudget = struct {
    remaining: usize,

    fn init(limits: Limits) ValidationBudget {
        return .{ .remaining = limits.max_validation_work };
    }

    fn consume(self: *ValidationBudget) !void {
        if (self.remaining == 0) return error.AdmXmlValidationWorkLimitExceeded;
        self.remaining -= 1;
    }
};

const declaration_index_capacity: usize = 4_096;
const declaration_slot_count: usize = declaration_index_capacity * 2;

fn identifierKey(identifier: adm.Identifier) u128 {
    // Identifier parsing fixes every prefix and digit count, so this tuple is
    // the exact case-insensitive identity represented by `raw`.
    return @as(u128, identifier.primary) |
        (@as(u128, identifier.secondary orelse 0) << 32) |
        (@as(u128, @intFromEnum(identifier.kind)) << 64) |
        (@as(u128, @intFromBool(identifier.secondary != null)) << 72);
}

fn mixedKeyIndex(key: u128, comptime slot_count: usize) usize {
    comptime {
        if (!std.math.isPowerOfTwo(slot_count))
            @compileError("ADM identifier index slot count must be a power of two");
    }
    var value: u64 = @truncate(key ^ (key >> 64));
    value ^= value >> 30;
    value *%= 0xbf58476d1ce4e5b9;
    value ^= value >> 27;
    value *%= 0x94d049bb133111eb;
    value ^= value >> 31;
    return @as(usize, @truncate(value)) & (slot_count - 1);
}

const CardinalityCounts = struct {
    channel: u8 = 0,
    pack: u8 = 0,
    stream: u8 = 0,
    track: u8 = 0,
    matrix_output: u8 = 0,
};

const DeclarationSlot = struct {
    key: u128 = 0,
    counts: CardinalityCounts = .{},
};

const DeclarationIndex = struct {
    slots: [declaration_slot_count]DeclarationSlot = @splat(.{}),
    occupied: [declaration_index_capacity]u16 = @splat(0),
    count: usize = 0,

    fn insert(
        self: *DeclarationIndex,
        identifier: adm.Identifier,
        budget: *ValidationBudget,
    ) !void {
        const key = identifierKey(identifier);
        var slot_index = mixedKeyIndex(key, declaration_slot_count);
        for (0..declaration_slot_count) |_| {
            try budget.consume();
            const slot = &self.slots[slot_index];
            if (slot.key == 0) {
                if (self.count >= declaration_index_capacity)
                    return error.TooManyAdmDeclarations;
                slot.key = key;
                self.occupied[self.count] = @intCast(slot_index);
                self.count += 1;
                return;
            }
            if (slot.key == key) return error.DuplicateAdmDeclaration;
            slot_index = (slot_index + 1) & (declaration_slot_count - 1);
        }
        return error.TooManyAdmDeclarations;
    }

    fn find(
        self: *DeclarationIndex,
        identifier: adm.Identifier,
        budget: *ValidationBudget,
    ) !?*DeclarationSlot {
        const key = identifierKey(identifier);
        var slot_index = mixedKeyIndex(key, declaration_slot_count);
        for (0..declaration_slot_count) |_| {
            try budget.consume();
            const slot = &self.slots[slot_index];
            if (slot.key == 0) return null;
            if (slot.key == key) return slot;
            slot_index = (slot_index + 1) & (declaration_slot_count - 1);
        }
        return null;
    }
};

fn noteIndexedCardinality(
    slot: *DeclarationSlot,
    reference_kind: ReferenceKind,
) void {
    const count = switch (reference_kind) {
        .channel_format => &slot.counts.channel,
        .pack_format => &slot.counts.pack,
        .stream_format => &slot.counts.stream,
        .track_format => &slot.counts.track,
        .matrix_output_channel => &slot.counts.matrix_output,
        else => return,
    };
    if (count.* < 2) count.* += 1;
}

fn validateIndexedCardinalities(
    index: *const DeclarationIndex,
    budget: *ValidationBudget,
) !void {
    for (index.occupied[0..index.count]) |slot_index| {
        try budget.consume();
        const slot = index.slots[slot_index];
        const kind: adm.IdentifierKind = @enumFromInt(
            @as(u8, @truncate(slot.key >> 64)),
        );
        switch (kind) {
            .stream_format => {
                if (slot.counts.channel > 1 or slot.counts.pack > 1)
                    return error.TooManyAdmStreamReferences;
                if (slot.counts.channel != 0 and slot.counts.pack != 0)
                    return error.AmbiguousAdmStreamFormat;
            },
            .track_format => {
                if (slot.counts.stream > 1)
                    return error.TooManyAdmTrackStreamReferences;
            },
            .track_uid => {
                if (slot.counts.track > 1 or slot.counts.channel > 1)
                    return error.TooManyAdmTrackReferences;
                if (slot.counts.track != 0 and slot.counts.channel != 0)
                    return error.AmbiguousAdmTrackReference;
                if (slot.counts.pack > 1)
                    return error.TooManyAdmPackReferences;
            },
            .block_format => {
                if (slot.counts.matrix_output > 1)
                    return error.TooManyAdmMatrixOutputReferences;
            },
            else => {},
        }
    }
}

const reciprocal_slot_count: usize = declaration_index_capacity * 2;

const ReciprocalTrackIndex = struct {
    keys: [reciprocal_slot_count]u128 = @splat(0),
    directions: [reciprocal_slot_count]u8 = @splat(0),
    unmatched_forward: usize = 0,

    fn pairKey(stream: adm.Identifier, track: adm.Identifier) u128 {
        return @as(u128, stream.primary) |
            (@as(u128, track.primary) << 32) |
            (@as(u128, track.secondary orelse 0) << 64) |
            (@as(u128, 1) << 96);
    }

    fn note(
        self: *ReciprocalTrackIndex,
        stream: adm.Identifier,
        track: adm.Identifier,
        direction: u8,
        budget: *ValidationBudget,
    ) !void {
        const key = pairKey(stream, track);
        var slot_index = mixedKeyIndex(key, reciprocal_slot_count);
        for (0..reciprocal_slot_count) |_| {
            try budget.consume();
            if (self.keys[slot_index] == 0) {
                self.keys[slot_index] = key;
                self.directions[slot_index] = direction;
                if (direction == 0b01) self.unmatched_forward += 1;
                return;
            }
            if (self.keys[slot_index] == key) {
                const previous = self.directions[slot_index];
                self.directions[slot_index] |= direction;
                if (previous == 0b01 and direction == 0b10)
                    self.unmatched_forward -= 1;
                return;
            }
            slot_index = (slot_index + 1) & (reciprocal_slot_count - 1);
        }
        return error.AdmXmlValidationWorkLimitExceeded;
    }

    fn validate(self: *const ReciprocalTrackIndex) !void {
        if (self.unmatched_forward != 0)
            return error.MissingReciprocalAdmTrackReference;
    }
};

const block_channel_slot_count: usize = declaration_index_capacity * 2;

const BlockChannelSlot = struct {
    primary: u32 = 0,
    count: usize = 0,
    preceding_blocks_have_timing: bool = true,
};

const BlockChannelIndex = struct {
    slots: [block_channel_slot_count]BlockChannelSlot = @splat(.{}),

    fn findOrInsert(
        self: *BlockChannelIndex,
        primary: u32,
        budget: *ValidationBudget,
    ) !*BlockChannelSlot {
        var slot_index = mixedKeyIndex(primary, block_channel_slot_count);
        for (0..block_channel_slot_count) |_| {
            try budget.consume();
            const slot = &self.slots[slot_index];
            if (slot.primary == 0) {
                slot.primary = primary;
                return slot;
            }
            if (slot.primary == primary) return slot;
            slot_index = (slot_index + 1) & (block_channel_slot_count - 1);
        }
        return error.TooManyAdmBlocks;
    }
};

fn emissionTransportIdCount(
    context: *const anyopaque,
    wanted: []const u8,
) !usize {
    const document: *const Document = @ptrCast(@alignCast(context));
    return document.emissionSerialTransportIdCount(wanted);
}

fn emissionTrackIdCount(
    context: *const anyopaque,
    transport_identifier: []const u8,
    wanted: u32,
) !usize {
    const document: *const Document = @ptrCast(@alignCast(context));
    return document.emissionSerialTrackIdCount(
        transport_identifier,
        wanted,
    );
}

fn emissionContainsIdentifier(
    context: *const anyopaque,
    kind: adm.IdentifierKind,
    primary: u32,
    secondary: ?u32,
) !bool {
    const document: *const Document = @ptrCast(@alignCast(context));
    return document.containsIdentifierValue(kind, primary, secondary);
}

pub const Document = struct {
    xml_document: xml.Document,
    namespace_name: ?xml.NamespaceName,
    limits: Limits,
    declaration_count: usize,
    reference_count: usize,
    profile_count: usize,
    tag_group_count: usize,
    tag_count: usize,
    tag_target_count: usize,
    block_count: usize,
    extension_count: usize,
    extension_attribute_count: usize,
    untyped_element_count: usize,
    untyped_attribute_count: usize,

    /// Parses and validates using the bounded defaults in `default_limits`.
    pub fn init(bytes: []const u8) !Document {
        return initWithLimits(bytes, default_limits);
    }

    /// Parses and validates without allocation, retaining `bytes` by reference.
    pub fn initWithLimits(bytes: []const u8, limits: Limits) !Document {
        try limits.validate();
        if (bytes.len > limits.max_document_bytes)
            return error.AdmXmlDocumentTooLarge;
        const xml_document = try xml.Document.init(bytes);
        var afe_count: usize = 0;
        var xml_event_count: usize = 0;
        var namespace_name: ?xml.NamespaceName = null;
        var afe_depth: ?usize = null;
        var foreign_depth: ?usize = null;
        var events = xml_document.iterator();
        while (try events.next()) |event| {
            if (xml_event_count >= limits.max_xml_events)
                return error.TooManyAdmXmlEvents;
            xml_event_count += 1;
            switch (event) {
                .start => |element| {
                    if (foreign_depth != null) continue;
                    if (insideAfe(afe_depth, element.depth)) {
                        if (!try xml.namespaceNamesEql(
                            namespace_name,
                            element.namespace_name,
                        )) {
                            if (!element.self_closing)
                                foreign_depth = element.depth;
                            continue;
                        }
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "audioFormatExtended",
                    )) {
                        afe_count += 1;
                        if (afe_count == 1) {
                            namespace_name = element.namespace_name;
                            afe_depth = if (element.self_closing)
                                null
                            else
                                element.depth;
                        }
                    }
                },
                .end => |element| {
                    if (foreign_depth == element.depth) {
                        foreign_depth = null;
                    } else if (afe_depth == element.depth) {
                        afe_depth = null;
                    }
                },
                else => {},
            }
        }
        if (afe_count == 0) return error.MissingAudioFormatExtended;
        if (afe_count != 1) return error.MultipleAudioFormatExtended;

        var document = Document{
            .xml_document = xml_document,
            .namespace_name = namespace_name,
            .limits = limits,
            .declaration_count = 0,
            .reference_count = 0,
            .profile_count = 0,
            .tag_group_count = 0,
            .tag_count = 0,
            .tag_target_count = 0,
            .block_count = 0,
            .extension_count = 0,
            .extension_attribute_count = 0,
            .untyped_element_count = 0,
            .untyped_attribute_count = 0,
        };
        var declaration_iterator = document.declarations();
        while (try declaration_iterator.next()) |_| {
            if (document.declaration_count >= limits.max_declarations)
                return error.TooManyAdmDeclarations;
            document.declaration_count += 1;
        }
        var profile_iterator = document.profiles();
        while (try profile_iterator.next()) |_| {
            if (document.profile_count >= limits.max_profiles)
                return error.TooManyAdmProfiles;
            document.profile_count += 1;
        }
        var tag_iterator = document.tags();
        while (try tag_iterator.next()) |item| {
            switch (item) {
                .tag => {
                    if (document.tag_count >= limits.max_tags)
                        return error.TooManyAdmTags;
                    document.tag_count += 1;
                },
                .target => {
                    if (document.tag_target_count >= limits.max_tag_targets)
                        return error.TooManyAdmTagTargets;
                    document.tag_target_count += 1;
                },
            }
        }
        document.tag_group_count = tag_iterator.group_count;
        if (document.tag_group_count > limits.max_tag_groups)
            return error.TooManyAdmTagGroups;
        var reference_iterator = document.references();
        while (try reference_iterator.next()) |_| {
            if (document.reference_count >= limits.max_references)
                return error.TooManyAdmReferences;
            document.reference_count += 1;
        }
        var block_iterator = document.blocks();
        while (try block_iterator.next()) |_| {
            if (document.block_count >= limits.max_blocks)
                return error.TooManyAdmBlocks;
            document.block_count += 1;
        }
        var extension_iterator = document.extensions();
        while (try extension_iterator.next()) |_| {
            if (document.extension_count >= limits.max_extensions)
                return error.TooManyAdmExtensions;
            document.extension_count += 1;
        }
        var extension_attribute_iterator =
            document.extensionAttributes();
        while (try extension_attribute_iterator.next()) |_| {
            if (document.extension_attribute_count >=
                limits.max_extension_attributes)
            {
                return error.TooManyAdmExtensionAttributes;
            }
            document.extension_attribute_count += 1;
        }
        var untyped_element_iterator = document.untypedElements();
        while (try untyped_element_iterator.next()) |_| {
            if (document.untyped_element_count >= limits.max_untyped_elements)
                return error.TooManyUntypedAdmElements;
            document.untyped_element_count += 1;
        }
        var untyped_attribute_iterator = document.untypedAttributes();
        while (try untyped_attribute_iterator.next()) |_| {
            if (document.untyped_attribute_count >=
                limits.max_untyped_attributes)
            {
                return error.TooManyUntypedAdmAttributes;
            }
            document.untyped_attribute_count += 1;
        }
        var validation_budget = ValidationBudget.init(limits);
        var declaration_index = DeclarationIndex{};
        try document.indexDeclarations(
            &declaration_index,
            &validation_budget,
        );
        try document.validateReferencesWithIndex(
            &declaration_index,
            &validation_budget,
        );
        try validateIndexedCardinalities(
            &declaration_index,
            &validation_budget,
        );
        try document.validateBlockSequencesWithIndex(
            &declaration_index,
            &validation_budget,
        );
        return document;
    }

    fn metadataSource(self: Document) MetadataSource {
        return .{
            .document = self.xml_document,
            .namespace_name = self.namespace_name,
        };
    }

    fn metadataEvents(self: Document) MetadataEventIterator {
        return MetadataEventIterator.init(self.metadataSource());
    }

    pub fn declarations(self: Document) DeclarationIterator {
        return DeclarationIterator.init(self.metadataSource());
    }

    pub fn references(self: Document) ReferenceIterator {
        return ReferenceIterator.init(self.metadataSource());
    }

    pub fn profiles(self: Document) ProfileIterator {
        return ProfileIterator.init(self.metadataSource());
    }

    fn serialHeaderProfiles(self: Document) ProfileIterator {
        return ProfileIterator.initSerialHeader(self.metadataSource());
    }

    pub fn blocks(self: Document) BlockIterator {
        return BlockIterator.init(self.metadataSource());
    }

    pub fn tags(self: Document) TagIterator {
        return TagIterator.init(self.metadataSource());
    }

    pub fn extensions(self: Document) ExtensionIterator {
        return ExtensionIterator.init(self.metadataSource());
    }

    pub fn extensionAttributes(
        self: Document,
    ) ExtensionAttributeIterator {
        return ExtensionAttributeIterator.init(self.metadataSource());
    }

    pub fn untypedElements(self: Document) UntypedElementIterator {
        return UntypedElementIterator.init(self.metadataSource());
    }

    pub fn untypedAttributes(
        self: Document,
    ) UntypedAttributeIterator {
        return UntypedAttributeIterator.init(self.metadataSource());
    }

    pub fn validateTypedVocabulary(self: Document) !void {
        if (self.untyped_element_count != 0 or
            self.untyped_attribute_count != 0)
            return error.UnsupportedAdmMetadataVocabulary;
    }

    pub fn contains(self: Document, wanted: adm.Identifier) !bool {
        var budget = ValidationBudget.init(self.limits);
        return self.containsWithBudget(wanted, &budget);
    }

    fn containsWithBudget(
        self: Document,
        wanted: adm.Identifier,
        budget: *ValidationBudget,
    ) !bool {
        var iterator = self.declarations();
        while (try iterator.next()) |declaration| {
            try budget.consume();
            if (declaration.identifier.eql(wanted)) return true;
        }
        return false;
    }

    pub fn validateReferences(self: Document) !void {
        var budget = ValidationBudget.init(self.limits);
        return self.validateReferencesWithBudget(&budget);
    }

    fn validateReferencesWithBudget(
        self: Document,
        budget: *ValidationBudget,
    ) !void {
        var declaration_index = DeclarationIndex{};
        try self.indexDeclarations(&declaration_index, budget);
        try self.validateReferencesWithIndex(&declaration_index, budget);
        try validateIndexedCardinalities(&declaration_index, budget);
    }

    fn validateReferencesWithIndex(
        self: Document,
        declaration_index: *DeclarationIndex,
        budget: *ValidationBudget,
    ) !void {
        var reciprocal_tracks = ReciprocalTrackIndex{};
        var iterator = self.references();
        while (try iterator.next()) |reference| {
            try budget.consume();
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
            const skips_resolution = identifier.kind == .track_uid or
                identifier.isCommonDefinition();
            if (!skips_resolution and
                (try declaration_index.find(identifier, budget)) == null)
            {
                return error.UnresolvedAdmReference;
            }
            if (reference.direct_owner) {
                const owner = reference.owner orelse
                    return error.InvalidAdmReferenceOwner;
                const owner_slot = (try declaration_index.find(
                    owner,
                    budget,
                )) orelse return error.InvalidAdmReferenceOwner;
                noteIndexedCardinality(owner_slot, reference.kind);
            }
            if (skips_resolution) continue;
            if (reference.kind == .stream_format) {
                const owner = reference.owner orelse continue;
                if (owner.kind == .track_format)
                    try reciprocal_tracks.note(
                        identifier,
                        owner,
                        0b01,
                        budget,
                    );
            } else if (reference.kind == .track_format) {
                const owner = reference.owner orelse continue;
                if (owner.kind == .stream_format)
                    try reciprocal_tracks.note(
                        owner,
                        identifier,
                        0b10,
                        budget,
                    );
            }
        }
        try reciprocal_tracks.validate();
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
        var events = self.metadataEvents();
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
        var events = self.metadataEvents();
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
        var events = self.metadataEvents();
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
                        const current = owner orelse
                            return error.InvalidAdmEmissionProfileFormatStructure;
                        try validateEmissionFormatOwner(current);
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
            const duration = block.duration orelse
                return error.MissingAdmEmissionProfileBlockTiming;
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

    /// Validates complementary group labels and object reference attributes.
    pub fn validateEmissionProfileComplementaryLabels(
        self: Document,
    ) !void {
        try self.validateEmissionProfileObjectBlocks();
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(u8, element.localName(), "audioObject"))
                        continue;
                    _ = try readEmissionObjectLabels(&events, element);
                },
                else => {},
            }
        }
    }

    /// Checks the profile's recommended cross-element label languages.
    pub fn validateEmissionProfileConsistentLabelLanguages(
        self: Document,
    ) !void {
        try self.validateEmissionProfileComplementaryLabels();
        var expected: ?EmissionLanguageSet = null;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    const languages = if (std.mem.eql(
                        u8,
                        name,
                        "audioProgramme",
                    ))
                        try readEmissionOwnerLabelLanguages(
                            &events,
                            element,
                            "audioProgrammeLabel",
                        )
                    else if (std.mem.eql(u8, name, "audioContent"))
                        try readEmissionOwnerLabelLanguages(
                            &events,
                            element,
                            "audioContentLabel",
                        )
                    else if (std.mem.eql(u8, name, "audioObject")) blk: {
                        const labels = try readEmissionObjectLabels(
                            &events,
                            element,
                        );
                        if (labels.complementary_references == 0) continue;
                        break :blk labels.languages;
                    } else continue;

                    if (expected) |wanted| {
                        if (!wanted.eql(languages))
                            return error.InconsistentAdmEmissionProfileLabelLanguages;
                    } else {
                        expected = languages;
                    }
                },
                else => {},
            }
        }
    }

    /// Checks the recommended programme language for multilingual
    /// complementary-object groups.
    pub fn validateEmissionProfileRecommendedProgrammeLanguages(
        self: Document,
    ) !void {
        try self.validateEmissionProfileComplementaryLabels();
        var programme_iterator = self.declarations();
        while (try programme_iterator.next()) |declaration| {
            const programme = declaration.identifier;
            if (programme.kind != .programme) continue;
            const programme_language = try self.emissionDeclarationLanguage(
                .programme,
                programme.primary,
            );

            var object_iterator = self.declarations();
            while (try object_iterator.next()) |object_declaration| {
                const root = object_declaration.identifier;
                if (root.kind != .object or
                    try self.emissionComplementaryChildCount(root.primary) == 0)
                {
                    continue;
                }
                const root_parent = try self.emissionObjectParent(root.primary);
                if (root_parent.kind != .content or
                    !try self.emissionProgrammeIncludesContent(
                        programme.primary,
                        root_parent.primary,
                    ))
                {
                    continue;
                }
                const root_language = try self.emissionDeclarationLanguage(
                    .content,
                    root_parent.primary,
                );
                var complete_group = true;
                var multilingual = false;
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
                    const member_parent = try self.emissionObjectParent(
                        member.primary,
                    );
                    if (member_parent.kind != .content or
                        !try self.emissionProgrammeIncludesContent(
                            programme.primary,
                            member_parent.primary,
                        ))
                    {
                        complete_group = false;
                        continue;
                    }
                    const member_language =
                        try self.emissionDeclarationLanguage(
                            .content,
                            member_parent.primary,
                        );
                    multilingual = multilingual or
                        !std.meta.eql(root_language, member_language);
                }
                if (complete_group and
                    multilingual and
                    !std.mem.eql(u8, &programme_language, "und"))
                {
                    return error.InvalidAdmEmissionProfileRecommendedProgrammeLanguage;
                }
            }
        }
    }

    /// Checks the recommended dialogue-loudness presence for content that
    /// metadata classifies as containing dialogue.
    pub fn validateEmissionProfileRecommendedDialogueLoudness(
        self: Document,
    ) !void {
        try self.validateEmissionProfileProgrammeContentMetadata();
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const owner = declaration.identifier;
            const contains_dialogue = switch (owner.kind) {
                .content => try self.emissionContentContainsDialogue(
                    owner.primary,
                ),
                .programme => try self.emissionProgrammeContainsDialogue(
                    owner.primary,
                ),
                else => continue,
            };
            if (contains_dialogue and
                !try self.emissionOwnerHasDialogueLoudness(
                    owner.kind,
                    owner.primary,
                ))
            {
                return error.MissingAdmEmissionProfileRecommendedDialogueLoudness;
            }
        }
    }

    /// Validates file-level PCM properties and Objects block coverage.
    pub fn validateEmissionProfilePcmEssence(
        self: Document,
        essence: EmissionPcmEssence,
    ) !void {
        try self.validateEmissionProfileComplementaryLabels();
        if (essence.sample_rate == 0 or
            essence.bit_depth == 0 or
            essence.channel_count == 0)
        {
            return error.InvalidAdmEmissionProfilePcmEssence;
        }

        var track_count: usize = 0;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "audioTrackUID",
                    )) {
                        continue;
                    }
                    track_count += 1;
                    if (try emissionOptionalPositiveAttribute(
                        element,
                        "sampleRate",
                    )) |sample_rate| {
                        if (sample_rate != essence.sample_rate)
                            return error.AdmEmissionProfileSampleRateMismatch;
                    }
                    if (try emissionOptionalPositiveAttribute(
                        element,
                        "bitDepth",
                    )) |bit_depth| {
                        if (bit_depth != essence.bit_depth)
                            return error.AdmEmissionProfileBitDepthMismatch;
                    }
                },
                else => {},
            }
        }
        if (track_count != essence.channel_count)
            return error.AdmEmissionProfileTrackCountMismatch;

        const duration = adm_time.Value{
            .whole_seconds = essence.frame_count / essence.sample_rate,
            .fractional_numerator = essence.frame_count % essence.sample_rate,
            .fractional_denominator = essence.sample_rate,
            .format = .fractional_samples,
        };
        const zero = zeroAdmTime();
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const channel = declaration.identifier;
            if (channel.kind != .channel_format or
                channel.typeLabel() != 0x0003)
            {
                continue;
            }
            var last: ?BlockFormat = null;
            var block_iterator = self.blocks();
            while (try block_iterator.next()) |block| {
                if (block.channel_identifier.primary != channel.primary)
                    continue;
                if (last == null and block.rtime.compare(zero) != .eq)
                    return error.AdmEmissionProfileEssenceCoverageMismatch;
                last = block;
            }
            const final_block = last orelse
                return error.AdmEmissionProfileEssenceCoverageMismatch;
            if (!final_block.rtime.sumEquals(
                final_block.duration orelse
                    return error.AdmEmissionProfileEssenceCoverageMismatch,
                duration,
            )) {
                return error.AdmEmissionProfileEssenceCoverageMismatch;
            }
        }
    }

    /// Validates the S-ADM frame, header, and frame-format envelope.
    pub fn validateEmissionProfileSerialFrameEnvelope(
        self: Document,
    ) !void {
        try self.validateEmissionProfileFormatMetadata();
        var frame_depth: ?usize = null;
        var frame_count: usize = 0;
        var header_count: usize = 0;
        var format_extended_count: usize = 0;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (frame_depth == null) {
                        if (element.depth != 0 or
                            !std.mem.eql(u8, name, "frame"))
                        {
                            return error.InvalidAdmEmissionProfileSerialFrame;
                        }
                        frame_count += 1;
                        try validateEmissionAttributes(
                            element,
                            &.{"version"},
                            error.InvalidAdmEmissionProfileSerialFrameAttribute,
                        );
                        try emissionRequiredAttributeValueAs(
                            element,
                            "version",
                            "ITU-R_BS.2125-1",
                            error.MissingAdmEmissionProfileSerialFrameAttribute,
                            error.InvalidAdmEmissionProfileSerialFrameAttribute,
                        );
                        if (element.self_closing)
                            return error.InvalidAdmEmissionProfileSerialFrame;
                        frame_depth = element.depth;
                        continue;
                    }
                    const depth = frame_depth orelse
                        return error.InvalidAdmEmissionProfileSerialFrame;
                    if (element.depth != depth + 1) continue;
                    if (std.mem.eql(u8, name, "frameHeader")) {
                        header_count += 1;
                        if (header_count > 1)
                            return error.InvalidAdmEmissionProfileSerialFrame;
                        try readEmissionSerialFrameHeader(&events, element);
                    } else if (std.mem.eql(
                        u8,
                        name,
                        "audioFormatExtended",
                    )) {
                        format_extended_count += 1;
                        if (format_extended_count > 1)
                            return error.InvalidAdmEmissionProfileSerialFrame;
                    }
                },
                .end => |element| {
                    if (frame_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "frame"))
                    {
                        frame_depth = null;
                    }
                },
                else => {},
            }
        }
        if (frame_count != 1 or
            frame_depth != null or
            header_count != 1 or
            format_extended_count != 1)
        {
            return error.InvalidAdmEmissionProfileSerialFrame;
        }
    }

    /// Validates S-ADM transport tracks and their ADM track UID mapping.
    pub fn validateEmissionProfileSerialTransportTracks(
        self: Document,
    ) !void {
        try self.validateEmissionProfileSerialFrameEnvelope();
        var declared_tracks: usize = 0;
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            if (declaration.identifier.kind == .track_uid)
                declared_tracks += 1;
        }

        var lookup_document = self;
        const lookup = EmissionSerialLookup{
            .context = &lookup_document,
            .transport_id_count = emissionTransportIdCount,
            .track_id_count = emissionTrackIdCount,
            .contains_identifier = emissionContainsIdentifier,
        };
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "transportTrackFormat",
                    )) {
                        continue;
                    }
                    try readEmissionSerialTransport(
                        lookup,
                        &events,
                        element,
                        declared_tracks,
                    );
                },
                else => {},
            }
        }

        declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            const identifier = declaration.identifier;
            if (identifier.kind != .track_uid) continue;
            if (try self.emissionSerialTrackReferenceCount(
                identifier.primary,
            ) != 1) {
                return error.InvalidAdmEmissionProfileSerialTrackMapping;
            }
        }
    }

    /// Validates S-ADM header profiles and their embedded ADM counterparts.
    pub fn validateEmissionProfileSerialHeaderProfiles(
        self: Document,
    ) !void {
        try self.validateEmissionProfileSerialTransportTracks();

        var outer = self.serialHeaderProfiles();
        var index: usize = 0;
        while (try outer.next()) |profile| : (index += 1) {
            var inner = self.serialHeaderProfiles();
            var previous_index: usize = 0;
            while (previous_index < index) : (previous_index += 1) {
                const previous = (try inner.next()) orelse
                    return error.InvalidAdmProfileIteration;
                if (profilesEqual(profile, previous))
                    return error.DuplicateAdmEmissionProfileSerialHeaderProfile;
            }
        }

        var emission_profiles: usize = 0;
        var header_profiles = self.serialHeaderProfiles();
        while (try header_profiles.next()) |header_profile| {
            if (!isEmissionProfile(header_profile)) continue;
            emission_profiles += 1;
            var found = false;
            var embedded_profiles = self.profiles();
            while (try embedded_profiles.next()) |embedded_profile| {
                if (profilesEqual(header_profile, embedded_profile)) {
                    found = true;
                    break;
                }
            }
            if (!found)
                return error.MismatchedAdmEmissionProfileSerialHeaderProfile;
        }
        if (emission_profiles == 0)
            return error.MissingAdmEmissionProfileSerialHeaderProfile;
    }

    /// Validates S-ADM Objects block timing and initialization within a frame.
    pub fn validateEmissionProfileSerialObjectBlocks(
        self: Document,
    ) !void {
        try self.validateEmissionProfileSerialHeaderProfiles();
        try self.validateEmissionSerialObjectBlockSyntax();
        const frame_duration = try self.emissionSerialFrameDuration();
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
            var previous_timed: ?BlockFormat = null;
            var preceding_blocks: usize = 0;
            var earlier = self.blocks();
            while (try earlier.next()) |candidate| {
                if (!candidate.channel_identifier.eql(
                    block.channel_identifier,
                )) {
                    continue;
                }
                if (candidate.identifier.eql(block.identifier)) break;
                preceding_blocks += 1;
                if (candidate.initialize_block == null)
                    previous_timed = candidate;
            }

            if (block.initialize_block != null) {
                if (sequence != 0 or preceding_blocks != 0)
                    return error.InvalidAdmEmissionProfileSerialInitializeBlock;
                var has_timed_block = false;
                var candidates = self.blocks();
                while (try candidates.next()) |candidate| {
                    if (candidate.channel_identifier.eql(
                        block.channel_identifier,
                    ) and candidate.initialize_block == null) {
                        has_timed_block = true;
                        break;
                    }
                }
                if (!has_timed_block)
                    return error.MissingAdmEmissionProfileSerialBlockTiming;
                continue;
            }

            if (sequence == 0)
                return error.InvalidAdmEmissionProfileSerialBlockIdentifier;
            const lstart = block.lstart orelse
                return error.MissingAdmEmissionProfileSerialBlockTiming;
            const lduration = block.lduration orelse
                return error.MissingAdmEmissionProfileSerialBlockTiming;
            if (lduration.compare(zero) != .eq and
                lduration.compare(minimum_duration) == .lt)
            {
                return error.InvalidAdmEmissionProfileSerialBlockDuration;
            }
            if (previous_timed) |previous| {
                const previous_start = previous.lstart orelse
                    return error.MissingAdmEmissionProfileSerialBlockTiming;
                const previous_duration = previous.lduration orelse
                    return error.MissingAdmEmissionProfileSerialBlockTiming;
                if (!previous_start.sumEquals(previous_duration, lstart))
                    return error.InvalidAdmEmissionProfileSerialBlockTiming;
                const previous_sequence = previous.identifier.secondary orelse
                    return error.InvalidAdmBlockIdentifier;
                const expected_sequence = std.math.add(
                    u32,
                    previous_sequence,
                    1,
                ) catch
                    return error.InvalidAdmEmissionProfileSerialBlockIdentifier;
                if (sequence != expected_sequence)
                    return error.InvalidAdmEmissionProfileSerialBlockIdentifier;
            } else if (lstart.compare(zero) != .eq) {
                return error.InvalidAdmEmissionProfileSerialBlockTiming;
            }

            var has_later_timed_block = false;
            var found_current = false;
            var remainder = self.blocks();
            while (try remainder.next()) |candidate| {
                if (!candidate.channel_identifier.eql(
                    block.channel_identifier,
                )) {
                    continue;
                }
                if (!found_current) {
                    found_current = candidate.identifier.eql(block.identifier);
                    continue;
                }
                if (candidate.initialize_block == null) {
                    has_later_timed_block = true;
                    break;
                }
            }
            if (!has_later_timed_block and
                !lstart.sumEquals(lduration, frame_duration))
            {
                return error.InvalidAdmEmissionProfileSerialFrameCoverage;
            }
        }
    }

    /// Validates and advances one frame in an original S-ADM flow.
    pub fn validateEmissionProfileSerialFlowFrame(
        self: Document,
        state: *EmissionSerialFlowState,
    ) !void {
        try self.validateEmissionProfileSerialObjectBlocks();
        const frame = try self.emissionSerialFrameFlowFields();
        if (state.initialized) {
            const expected_start = state.next_start orelse
                return error.InvalidAdmEmissionProfileSerialFlowState;
            if (frame.index != state.next_frame_index)
                return error.InvalidAdmEmissionProfileSerialFrameSequence;
            if (frame.start.compare(expected_start) != .eq)
                return error.InvalidAdmEmissionProfileSerialFrameContinuity;
            if (!std.mem.eql(u8, frame.frame_type, "full"))
                return error.InvalidAdmEmissionProfileSerialFrameType;
            if (state.flow_id) |expected_id| {
                if (frame.flow_id) |actual_id| {
                    if (!std.mem.eql(u8, &expected_id, &actual_id))
                        return error.InvalidAdmEmissionProfileSerialFlowIdentifier;
                }
            }
        } else {
            if (state.next_start != null or state.next_frame_index != 1 or
                state.flow_id != null)
            {
                return error.InvalidAdmEmissionProfileSerialFlowState;
            }
            if (frame.index != 1)
                return error.InvalidAdmEmissionProfileSerialFrameSequence;
        }

        const next_index = std.math.add(
            u32,
            frame.index,
            1,
        ) catch return error.InvalidAdmEmissionProfileSerialFrameSequence;
        const next_start = sumAdmTime(
            frame.start,
            frame.duration,
        ) orelse return error.InvalidAdmEmissionProfileSerialFrameContinuity;
        state.* = .{
            .initialized = true,
            .next_frame_index = next_index,
            .next_start = next_start,
            .flow_id = state.flow_id orelse frame.flow_id,
        };
    }

    const EmissionSerialFrameFlowFields = struct {
        index: u32,
        start: adm_time.Value,
        duration: adm_time.Value,
        frame_type: []const u8,
        flow_id: ?[36]u8,
    };

    fn emissionSerialFrameFlowFields(
        self: Document,
    ) !EmissionSerialFrameFlowFields {
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "frameFormat",
                    )) {
                        continue;
                    }
                    const encoded_identifier =
                        try element.attribute("frameFormatID") orelse
                        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
                    var identifier_storage: [32]u8 = undefined;
                    const identifier = try xml.decodeContent(
                        &identifier_storage,
                        encoded_identifier,
                    );
                    const index = std.fmt.parseInt(
                        u32,
                        identifier[3..],
                        16,
                    ) catch
                        return error.InvalidAdmEmissionProfileSerialFrameFormatIdentifier;
                    const start = try emissionSerialTimeAttribute(
                        element,
                        "start",
                    );
                    const duration = try emissionSerialTimeAttribute(
                        element,
                        "duration",
                    );
                    const encoded_type = try element.attribute("type") orelse
                        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
                    var type_storage: [16]u8 = undefined;
                    const frame_type = try xml.decodeContent(
                        &type_storage,
                        encoded_type,
                    );
                    const flow_id =
                        if (try element.attribute("flowID")) |encoded|
                            try decodeEmissionSerialFlowIdentifier(encoded)
                        else
                            null;
                    return .{
                        .index = index,
                        .start = start,
                        .duration = duration,
                        .frame_type = if (std.mem.eql(
                            u8,
                            frame_type,
                            "header",
                        ))
                            "header"
                        else
                            "full",
                        .flow_id = flow_id,
                    };
                },
                else => {},
            }
        }
        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
    }

    fn validateEmissionSerialObjectBlockSyntax(self: Document) !void {
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "audioBlockFormatObjects",
                    )) {
                        continue;
                    }
                    try readEmissionObjectBlockSyntaxWithTiming(
                        &events,
                        element,
                        .serial,
                    );
                },
                else => {},
            }
        }
    }

    fn emissionSerialFrameDuration(self: Document) !adm_time.Value {
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "frameFormat",
                    )) {
                        continue;
                    }
                    const encoded = try element.attribute("duration") orelse
                        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
                    var storage: [64]u8 = undefined;
                    const raw = try xml.decodeContent(&storage, encoded);
                    return adm_time.Value.parse(raw) catch
                        return error.InvalidAdmEmissionProfileSerialFrameTime;
                },
                else => {},
            }
        }
        return error.MissingAdmEmissionProfileSerialFrameFormatAttribute;
    }

    fn emissionSerialTransportIdCount(
        self: Document,
        wanted: []const u8,
    ) !usize {
        var count: usize = 0;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "transportTrackFormat",
                    )) {
                        continue;
                    }
                    const encoded = try element.attribute("transportID") orelse
                        continue;
                    var storage: [16]u8 = undefined;
                    const identifier = try xml.decodeContent(
                        &storage,
                        encoded,
                    );
                    if (std.ascii.eqlIgnoreCase(identifier, wanted))
                        count += 1;
                },
                else => {},
            }
        }
        return count;
    }

    fn emissionSerialTrackIdCount(
        self: Document,
        transport_identifier: []const u8,
        wanted: u32,
    ) !usize {
        var count: usize = 0;
        var matching_transport_depth: ?usize = null;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "transportTrackFormat")) {
                        const encoded =
                            try element.attribute("transportID") orelse
                            continue;
                        var storage: [16]u8 = undefined;
                        const identifier = try xml.decodeContent(
                            &storage,
                            encoded,
                        );
                        if (std.ascii.eqlIgnoreCase(
                            identifier,
                            transport_identifier,
                        )) {
                            matching_transport_depth = element.depth;
                        }
                        continue;
                    }
                    const depth = matching_transport_depth orelse continue;
                    if (element.depth != depth + 1 or
                        !std.mem.eql(u8, name, "audioTrack"))
                    {
                        continue;
                    }
                    const track_id = try emissionOptionalPositiveAttributeAs(
                        element,
                        "trackID",
                        error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
                    ) orelse continue;
                    if (track_id == wanted) count += 1;
                },
                .end => |element| {
                    if (matching_transport_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "transportTrackFormat",
                        ))
                    {
                        matching_transport_depth = null;
                    }
                },
                else => {},
            }
        }
        return count;
    }

    fn emissionSerialTrackReferenceCount(
        self: Document,
        wanted_primary: u32,
    ) !usize {
        var count: usize = 0;
        var audio_track_depth: ?usize = null;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const name = element.localName();
                    if (std.mem.eql(u8, name, "audioTrack")) {
                        audio_track_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    const depth = audio_track_depth orelse continue;
                    if (element.depth != depth + 1 or
                        !std.mem.eql(u8, name, "audioTrackUIDRef"))
                    {
                        continue;
                    }
                    var storage: [max_identifier_bytes]u8 = undefined;
                    const raw = try readEmissionSimpleElement(
                        &events,
                        element,
                        &storage,
                    );
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind == .track_uid and
                        identifier.primary == wanted_primary)
                    {
                        count += 1;
                    }
                },
                .end => |element| {
                    if (audio_track_depth == element.depth and
                        std.mem.eql(u8, element.localName(), "audioTrack"))
                    {
                        audio_track_depth = null;
                    }
                },
                else => {},
            }
        }
        return count;
    }

    fn validateEmissionObjectBlockSyntax(self: Document) !void {
        var frame_depth: ?usize = null;
        var afe_depth: ?usize = null;
        var events = self.metadataEvents();
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
        var events = self.metadataEvents();
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
        var events = self.metadataEvents();
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
                        const interaction = parameters.interaction orelse
                            return error.InvalidAdmEmissionProfileObjectInteraction;
                        if (interaction.position_range != null)
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
        var events = self.metadataEvents();
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

    fn emissionProgrammeIncludesContent(
        self: Document,
        programme_primary: u32,
        content_primary: u32,
    ) !bool {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            if (!reference.direct_owner or reference.kind != .content)
                continue;
            const owner = reference.owner orelse continue;
            const content = reference.identifier orelse continue;
            if (owner.kind == .programme and
                owner.primary == programme_primary and
                content.primary == content_primary)
            {
                return true;
            }
        }
        return false;
    }

    fn emissionDeclarationLanguage(
        self: Document,
        kind: adm.IdentifierKind,
        primary: u32,
    ) ![3]u8 {
        const element_name, const identifier_name, const language_name =
            switch (kind) {
                .programme => .{
                    "audioProgramme",
                    "audioProgrammeID",
                    "audioProgrammeLanguage",
                },
                .content => .{
                    "audioContent",
                    "audioContentID",
                    "audioContentLanguage",
                },
                else => return error.InvalidAdmEmissionProfileLanguageOwner,
            };
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        element_name,
                    )) {
                        continue;
                    }
                    const identifier = try emissionElementIdentifier(
                        element,
                        identifier_name,
                        kind,
                    );
                    if (identifier.primary == primary) {
                        return emissionRequiredLanguageAttribute(
                            element,
                            language_name,
                        );
                    }
                },
                else => {},
            }
        }
        return error.MissingAdmEmissionProfileLanguageOwner;
    }

    fn emissionContentContainsDialogue(
        self: Document,
        content_primary: u32,
    ) !bool {
        var owner_depth: ?usize = null;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (owner_depth) |depth| {
                        if (element.depth == depth + 1 and
                            std.mem.eql(
                                u8,
                                element.localName(),
                                "dialogue",
                            ))
                        {
                            var storage: [16]u8 = undefined;
                            const raw = try readEmissionSimpleElement(
                                &events,
                                element,
                                &storage,
                            );
                            const value = std.fmt.parseInt(
                                u8,
                                raw,
                                10,
                            ) catch
                                return error.InvalidAdmEmissionProfileDialogue;
                            return value != 0;
                        }
                        continue;
                    }
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        "audioContent",
                    )) {
                        continue;
                    }
                    const identifier = try emissionElementIdentifier(
                        element,
                        "audioContentID",
                        .content,
                    );
                    if (identifier.primary == content_primary)
                        owner_depth = element.depth;
                },
                .end => |element| {
                    if (owner_depth == element.depth)
                        return error.MissingAdmEmissionProfileDialogue;
                },
                else => {},
            }
        }
        return error.MissingAdmEmissionProfileLanguageOwner;
    }

    fn emissionProgrammeContainsDialogue(
        self: Document,
        programme_primary: u32,
    ) !bool {
        var reference_iterator = self.references();
        while (try reference_iterator.next()) |reference| {
            const owner = reference.owner orelse continue;
            if (!reference.direct_owner or
                owner.kind != .programme or
                owner.primary != programme_primary or
                reference.kind != .content)
            {
                continue;
            }
            const content = reference.identifier orelse
                return error.InvalidAdmEmissionProfileProgrammeContent;
            if (try self.emissionContentContainsDialogue(content.primary))
                return true;
        }
        return false;
    }

    fn emissionOwnerHasDialogueLoudness(
        self: Document,
        kind: adm.IdentifierKind,
        primary: u32,
    ) !bool {
        const element_name, const identifier_name = switch (kind) {
            .programme => .{ "audioProgramme", "audioProgrammeID" },
            .content => .{ "audioContent", "audioContentID" },
            else => return error.InvalidAdmEmissionProfileLoudnessOwner,
        };
        var owner_depth: ?usize = null;
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (owner_depth) |depth| {
                        if (element.depth == depth + 2 and
                            std.mem.eql(
                                u8,
                                element.localName(),
                                "dialogueLoudness",
                            ))
                        {
                            return true;
                        }
                        continue;
                    }
                    if (!std.mem.eql(
                        u8,
                        element.localName(),
                        element_name,
                    )) {
                        continue;
                    }
                    const identifier = try emissionElementIdentifier(
                        element,
                        identifier_name,
                        kind,
                    );
                    if (identifier.primary == primary)
                        owner_depth = element.depth;
                },
                .end => |element| {
                    if (owner_depth == element.depth) return false;
                },
                else => {},
            }
        }
        return error.MissingAdmEmissionProfileLoudnessOwner;
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
                    const definition_index = target.definitionIndex() orelse
                        return error.InvalidAdmEmissionProfileMatrixPack;
                    if (target.typeLabel() != 0x0002 or
                        definition_index < 0x1000 or
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
        var events = self.metadataEvents();
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
                                    attribute.name,
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
                        const name = attribute.name;
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
        var events = self.metadataEvents();
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
        var events = self.metadataEvents();
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

    fn indexDeclarations(
        self: Document,
        index: *DeclarationIndex,
        budget: *ValidationBudget,
    ) !void {
        var declaration_iterator = self.declarations();
        while (try declaration_iterator.next()) |declaration| {
            try index.insert(declaration.identifier, budget);
        }
    }

    fn validateUniqueProfiles(self: Document) !void {
        var budget = ValidationBudget.init(self.limits);
        var outer = self.profiles();
        var index: usize = 0;
        while (try outer.next()) |profile| : (index += 1) {
            var inner = self.profiles();
            var previous_index: usize = 0;
            while (previous_index < index) : (previous_index += 1) {
                try budget.consume();
                const previous = (try inner.next()) orelse
                    return error.InvalidAdmProfileIteration;
                if (profilesEqual(profile, previous))
                    return error.DuplicateAdmProfile;
            }
        }
    }

    fn validateBlockSequencesWithIndex(
        self: Document,
        declaration_index: *DeclarationIndex,
        budget: *ValidationBudget,
    ) !void {
        const serial_frame = try self.hasSerialFrameRoot();
        var channels = BlockChannelIndex{};
        var block_iterator = self.blocks();
        while (try block_iterator.next()) |block| {
            try budget.consume();
            if (block.identifier.primary != block.channel_identifier.primary)
                return error.AdmBlockIdentifierMismatch;
            for (block.matrixCoefficientSlice()) |coefficient| {
                try budget.consume();
                const identifier = try coefficient.channelIdentifier();
                if (!identifier.isCommonDefinition() and
                    (try declaration_index.find(identifier, budget)) == null)
                {
                    return error.UnresolvedAdmReference;
                }
            }
            if (serial_frame) continue;

            const channel = try channels.findOrInsert(
                block.channel_identifier.primary,
                budget,
            );
            const sequence = block.identifier.secondary orelse
                return error.InvalidAdmBlockIdentifier;
            if (sequence != @as(u32, @intCast(channel.count + 1)))
                return error.InvalidAdmBlockSequence;
            const has_timing = block.rtime_explicit and block.duration != null;
            if (channel.count != 0 and
                (!channel.preceding_blocks_have_timing or !has_timing))
            {
                return error.MissingDynamicAdmBlockTiming;
            }
            channel.count += 1;
            channel.preceding_blocks_have_timing =
                channel.preceding_blocks_have_timing and has_timing;
        }
    }

    fn hasSerialFrameRoot(self: Document) !bool {
        var events = self.metadataEvents();
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (element.depth == 0)
                        return std.mem.eql(u8, element.localName(), "frame");
                },
                else => {},
            }
        }
        return false;
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

fn zeroAdmTime() adm_time.Value {
    return .{
        .whole_seconds = 0,
        .fractional_numerator = 0,
        .fractional_denominator = 1,
        .format = .decimal,
    };
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte))
            return false;
    }
    return true;
}

const adm_xml_fuzz_minimal = "<audioFormatExtended/>";
const adm_xml_fuzz_graph =
    "<audioFormatExtended>" ++
    "<audioContent audioContentID=\"ACO_1001\">" ++
    "<audioObjectIDRef>AO_1001</audioObjectIDRef>" ++
    "</audioContent>" ++
    "<audioObject audioObjectID=\"AO_1001\"/>" ++
    "</audioFormatExtended>";

test "fuzz bounded ADM XML parsing and traversal" {
    try std.testing.fuzz({}, fuzzAdmXml, .{
        .corpus = &.{ adm_xml_fuzz_minimal, adm_xml_fuzz_graph },
    });
}

fn fuzzAdmXml(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var storage: [64 * 1024]u8 = undefined;
    var length: usize = switch (smith.valueRangeAtMost(u8, 0, 2)) {
        0 => smith.slice(&storage),
        1 => seed: {
            @memcpy(storage[0..adm_xml_fuzz_minimal.len], adm_xml_fuzz_minimal);
            break :seed adm_xml_fuzz_minimal.len;
        },
        2 => seed: {
            @memcpy(storage[0..adm_xml_fuzz_graph.len], adm_xml_fuzz_graph);
            break :seed adm_xml_fuzz_graph.len;
        },
        else => smith.slice(&storage),
    };
    if (length != 0 and smith.value(bool)) {
        const mutation_count = smith.valueRangeAtMost(u8, 1, 32);
        for (0..mutation_count) |_|
            storage[smith.index(length)] ^= smith.value(u8);
    }
    if (smith.value(bool)) {
        const maximum: u16 = @intCast(@min(length, std.math.maxInt(u16)));
        length = smith.valueRangeAtMost(u16, 0, maximum);
    } else if (length < storage.len and smith.value(bool)) {
        const maximum_append: u16 = @intCast(@min(
            storage.len - length,
            std.math.maxInt(u16),
        ));
        const append_length = smith.valueRangeAtMost(u16, 0, maximum_append);
        smith.bytes(storage[length..][0..append_length]);
        length += append_length;
    }

    const limits = Limits{
        .max_document_bytes = storage.len,
        .max_xml_events = 20_000,
        .max_declarations = 256,
        .max_references = 1_024,
        .max_profiles = 256,
        .max_tag_groups = 256,
        .max_tags = 1_024,
        .max_tag_targets = 1_024,
        .max_blocks = 1_024,
        .max_extensions = 1_024,
        .max_extension_attributes = 4_096,
        .max_untyped_elements = 1_024,
        .max_untyped_attributes = 4_096,
        .max_validation_work = 100_000,
    };
    const document = Document.initWithLimits(
        storage[0..length],
        limits,
    ) catch return;
    try document.validateReferences();

    var declaration_count: usize = 0;
    var declarations = document.declarations();
    while (try declarations.next()) |_| declaration_count += 1;
    if (declaration_count != document.declaration_count)
        return error.FuzzAdmDeclarationCountMismatch;

    var reference_count: usize = 0;
    var references = document.references();
    while (try references.next()) |_| reference_count += 1;
    if (reference_count != document.reference_count)
        return error.FuzzAdmReferenceCountMismatch;

    var block_count: usize = 0;
    var blocks = document.blocks();
    while (try blocks.next()) |_| block_count += 1;
    if (block_count != document.block_count)
        return error.FuzzAdmBlockCountMismatch;
}

fn expectAdmCountLimit(
    comptime field_name: []const u8,
    expected_error: anyerror,
    bytes: []const u8,
) !void {
    var limits = default_limits;
    @field(limits, field_name) = 1;
    try std.testing.expectError(
        expected_error,
        Document.initWithLimits(bytes, limits),
    );
}

test "ADM XML enforces construction and validation limits" {
    var limits = default_limits;
    limits.max_document_bytes = "<audioFormatExtended/>".len - 1;
    try std.testing.expectError(
        error.AdmXmlDocumentTooLarge,
        Document.initWithLimits("<audioFormatExtended/>", limits),
    );

    limits = default_limits;
    limits.max_xml_events = 1;
    try std.testing.expectError(
        error.TooManyAdmXmlEvents,
        Document.initWithLimits(
            "<audioFormatExtended><audioObject " ++
                "audioObjectID=\"AO_1001\"/></audioFormatExtended>",
            limits,
        ),
    );

    const two_declarations =
        "<audioFormatExtended>" ++
        "<audioObject audioObjectID=\"AO_1001\"/>" ++
        "<audioObject audioObjectID=\"AO_1002\"/>" ++
        "</audioFormatExtended>";
    limits = default_limits;
    limits.max_declarations = 1;
    try std.testing.expectError(
        error.TooManyAdmDeclarations,
        Document.initWithLimits(two_declarations, limits),
    );

    limits = default_limits;
    limits.max_validation_work = 1;
    try std.testing.expectError(
        error.AdmXmlValidationWorkLimitExceeded,
        Document.initWithLimits(two_declarations, limits),
    );

    limits = default_limits;
    limits.max_declarations = declaration_index_capacity + 1;
    try std.testing.expectError(
        error.InvalidAdmXmlLimits,
        Document.initWithLimits("<audioFormatExtended/>", limits),
    );

    try expectAdmCountLimit(
        "max_references",
        error.TooManyAdmReferences,
        "<audioFormatExtended>" ++
            "<audioContent audioContentID=\"ACO_1001\">" ++
            "<audioObjectIDRef>AO_1001</audioObjectIDRef>" ++
            "<audioObjectIDRef>AO_1002</audioObjectIDRef>" ++
            "</audioContent>" ++
            "<audioObject audioObjectID=\"AO_1001\"/>" ++
            "<audioObject audioObjectID=\"AO_1002\"/>" ++
            "</audioFormatExtended>",
    );
    try expectAdmCountLimit(
        "max_profiles",
        error.TooManyAdmProfiles,
        "<audioFormatExtended><profileList>" ++
            "<profile profileName=\"A\" profileVersion=\"1\" " ++
            "profileLevel=\"1\">A</profile>" ++
            "<profile profileName=\"B\" profileVersion=\"1\" " ++
            "profileLevel=\"1\">B</profile>" ++
            "</profileList></audioFormatExtended>",
    );
    const two_tag_groups =
        "<audioFormatExtended><audioObject audioObjectID=\"AO_1001\"/>" ++
        "<tagList>" ++
        "<tagGroup><tag>a</tag>" ++
        "<audioObjectIDRef>AO_1001</audioObjectIDRef></tagGroup>" ++
        "<tagGroup><tag>b</tag>" ++
        "<audioObjectIDRef>AO_1001</audioObjectIDRef></tagGroup>" ++
        "</tagList></audioFormatExtended>";
    try expectAdmCountLimit(
        "max_tag_groups",
        error.TooManyAdmTagGroups,
        two_tag_groups,
    );
    try expectAdmCountLimit(
        "max_tags",
        error.TooManyAdmTags,
        two_tag_groups,
    );
    try expectAdmCountLimit(
        "max_tag_targets",
        error.TooManyAdmTagTargets,
        two_tag_groups,
    );
    try expectAdmCountLimit(
        "max_blocks",
        error.TooManyAdmBlocks,
        "<audioFormatExtended>" ++
            "<audioChannelFormat audioChannelFormatID=\"AC_00051001\" " ++
            "audioChannelFormatName=\"LeftEar\">" ++
            "<audioBlockFormatBinaural " ++
            "audioBlockFormatID=\"AB_00051001_00000001\"/>" ++
            "<audioBlockFormatBinaural " ++
            "audioBlockFormatID=\"AB_00051001_00000002\"/>" ++
            "</audioChannelFormat></audioFormatExtended>",
    );
    try expectAdmCountLimit(
        "max_extensions",
        error.TooManyAdmExtensions,
        "<a:audioFormatExtended xmlns:a=\"urn:adm\" xmlns:v=\"urn:v\">" ++
            "<v:one/><v:two/></a:audioFormatExtended>",
    );
    try expectAdmCountLimit(
        "max_extension_attributes",
        error.TooManyAdmExtensionAttributes,
        "<a:audioFormatExtended xmlns:a=\"urn:adm\" xmlns:v=\"urn:v\" " ++
            "v:one=\"1\" v:two=\"2\"/>",
    );
    try expectAdmCountLimit(
        "max_untyped_elements",
        error.TooManyUntypedAdmElements,
        "<audioFormatExtended><future/><later/></audioFormatExtended>",
    );
    try expectAdmCountLimit(
        "max_untyped_attributes",
        error.TooManyUntypedAdmAttributes,
        "<a:audioFormatExtended xmlns:a=\"urn:adm\">" ++
            "<a:audioObject audioObjectID=\"AO_1001\" " ++
            "a:future=\"1\" a:later=\"2\"/>" ++
            "</a:audioFormatExtended>",
    );
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

test "ADM XML public iterators roll back malformed nested cursors" {
    const document = try Document.init("<audioFormatExtended/>");

    var declarations = document.declarations();
    declarations.events.events.offset = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidXmlEventIteratorState,
        declarations.next(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        declarations.events.events.offset,
    );

    var attributes = document.extensionAttributes();
    attributes.iterator.events.offset = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidXmlEventIteratorState,
        attributes.next(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        attributes.iterator.events.offset,
    );
}

test "ADM XML resolves typed namespace identity" {
    const default_namespace = try Document.init(
        \\<audioFormatExtended xmlns="urn:adm">
        \\  <audioObject audioObjectID="AO_1001"/>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        default_namespace.declaration_count,
    );

    const aliased_namespace = try Document.init(
        \\<a:audioFormatExtended xmlns:a="urn:&#97;dm" xmlns:b="urn:adm">
        \\  <b:audioObject audioObjectID="AO_1001"/>
        \\</a:audioFormatExtended>
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        aliased_namespace.declaration_count,
    );

    const foreign_element = try Document.init(
        \\<a:audioFormatExtended xmlns:a="urn:adm" xmlns:b="urn:other">
        \\  <b:audioObject audioObjectID="AO_1001"/>
        \\</a:audioFormatExtended>
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        foreign_element.declaration_count,
    );
    try std.testing.expect(!try foreign_element.contains(
        try adm.Identifier.parse("AO_1001"),
    ));

    const undeclared_default = try Document.init(
        \\<audioFormatExtended xmlns="urn:adm">
        \\  <audioObject xmlns="" audioObjectID="AO_1001"/>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        undeclared_default.declaration_count,
    );

    const foreign_wrapper = try Document.init(
        \\<w:wrapper xmlns:w="urn:wrapper">
        \\  <a:audioFormatExtended xmlns:a="urn:adm">
        \\    <a:audioObject audioObjectID="AO_1001"/>
        \\  </a:audioFormatExtended>
        \\</w:wrapper>
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        foreign_wrapper.declaration_count,
    );
    try std.testing.expectError(
        error.MissingAdmIdentifier,
        Document.init(
            \\<audioFormatExtended xmlns:v="urn:vendor">
            \\  <audioObject v:audioObjectID="AO_1001"/>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML preserves owned foreign extension subtrees" {
    const bytes =
        \\<a:audioFormatExtended xmlns:a="urn:adm" xmlns:v="urn:ven&#100;or" v:session="one &amp; two">
        \\  <a:audioObject audioObjectID="AO_1001" v:priority='high' a:future="standard">
        \\    <v:control mode="wide"><![CDATA[literal < & >]]><v:nested><!--keep--><?vendor keep?><v:audioFormatExtended/><a:audioObject audioObjectID="AO_9999"/></v:nested></v:control>
        \\    <o:empty xmlns:o="urn:other"/>
        \\    <plain xmlns=""/>
        \\  </a:audioObject>
        \\  <v:root/>
        \\</a:audioFormatExtended>
    ;
    const document = try Document.init(bytes);
    try std.testing.expectEqual(@as(usize, 1), document.declaration_count);
    try std.testing.expectEqual(@as(usize, 4), document.extension_count);
    try std.testing.expectEqual(
        @as(usize, 2),
        document.extension_attribute_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        document.untyped_attribute_count,
    );
    try std.testing.expect(!try document.contains(
        try adm.Identifier.parse("AO_9999"),
    ));

    var extensions = document.extensions();
    const control = (try extensions.next()).?;
    try std.testing.expectEqualStrings("v:control", control.qualified_name);
    try std.testing.expectEqualStrings("control", control.localName());
    try std.testing.expectEqualStrings(
        "urn:vendor",
        control.namespace_uri.?,
    );
    try std.testing.expectEqualStrings(
        "audioObject",
        control.parent_element_name,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        control.declaration_owner.?.raw,
    );
    try std.testing.expectEqual(
        std.mem.indexOf(u8, bytes, "<v:control").?,
        control.source_offset,
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        control.source,
        "<v:control mode=\"wide\">",
    ));
    try std.testing.expect(std.mem.indexOf(
        u8,
        control.source,
        "<!--keep--><?vendor keep?><v:audioFormatExtended/>",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        control.source,
        "<![CDATA[literal < & >]]>",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        control.source,
        "<a:audioObject audioObjectID=\"AO_9999\"/>",
    ) != null);
    try std.testing.expect(std.mem.endsWith(
        u8,
        control.source,
        "</v:control>",
    ));

    const empty = (try extensions.next()).?;
    try std.testing.expectEqualStrings("urn:other", empty.namespace_uri.?);
    try std.testing.expectEqualStrings(
        "<o:empty xmlns:o=\"urn:other\"/>",
        empty.source,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        empty.declaration_owner.?.raw,
    );

    const unqualified = (try extensions.next()).?;
    try std.testing.expect(unqualified.namespace_uri == null);
    try std.testing.expectEqualStrings("<plain xmlns=\"\"/>", unqualified.source);
    try std.testing.expectEqualStrings(
        "audioObject",
        unqualified.parent_element_name,
    );

    const root_extension = (try extensions.next()).?;
    try std.testing.expectEqualStrings("v:root", root_extension.qualified_name);
    try std.testing.expectEqualStrings(
        "audioFormatExtended",
        root_extension.parent_element_name,
    );
    try std.testing.expect(root_extension.declaration_owner == null);
    try std.testing.expect((try extensions.next()) == null);

    var extension_attributes = document.extensionAttributes();
    const session = (try extension_attributes.next()).?;
    try std.testing.expectEqualStrings("v:session", session.qualified_name);
    try std.testing.expectEqualStrings("session", session.localName());
    try std.testing.expectEqualStrings("urn:vendor", session.namespace_uri);
    try std.testing.expectEqualStrings(
        "audioFormatExtended",
        session.element_name,
    );
    try std.testing.expectEqualStrings(
        "v:session=\"one &amp; two\"",
        session.source,
    );
    var decoded_value: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "one & two",
        try session.decodeValue(&decoded_value),
    );
    try std.testing.expect(session.declaration_owner == null);

    const priority = (try extension_attributes.next()).?;
    try std.testing.expectEqualStrings("v:priority", priority.qualified_name);
    try std.testing.expectEqualStrings("v:priority='high'", priority.source);
    try std.testing.expectEqualStrings("audioObject", priority.element_name);
    try std.testing.expectEqualStrings(
        "AO_1001",
        priority.declaration_owner.?.raw,
    );
    try std.testing.expect((try extension_attributes.next()) == null);

    var untyped_attributes = document.untypedAttributes();
    const future = (try untyped_attributes.next()).?;
    try std.testing.expectEqualStrings("a:future", future.qualified_name);
    try std.testing.expectEqualStrings("future", future.localName());
    try std.testing.expectEqualStrings("urn:adm", future.namespace_uri);
    try std.testing.expectEqualStrings("standard", future.encoded_value);
    try std.testing.expectEqualStrings(
        "a:future=\"standard\"",
        future.source,
    );
    try std.testing.expectEqualStrings(
        "audioObject",
        future.element_name,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        future.declaration_owner.?.raw,
    );
    try std.testing.expect((try untyped_attributes.next()) == null);
}

test "ADM XML classifies untyped metadata-namespace subtrees" {
    const bytes =
        \\<a:audioFormatExtended xmlns:a="urn:adm" xmlns:v="urn:vendor">
        \\  <a:audioObject audioObjectID="AO_1001">
        \\    <a:future mode="wide"><![CDATA[literal < & >]]><a:audioObject audioObjectID="AO_9999"/><v:nested/><a:nested/></a:future>
        \\    <v:foreign/>
        \\    <a:futureEmpty/>
        \\  </a:audioObject>
        \\</a:audioFormatExtended>
    ;
    const document = try Document.init(bytes);
    try std.testing.expectEqual(@as(usize, 2), document.untyped_element_count);
    try std.testing.expectEqual(@as(usize, 1), document.extension_count);
    try std.testing.expectError(
        error.UnsupportedAdmMetadataVocabulary,
        document.validateTypedVocabulary(),
    );

    var elements = document.untypedElements();
    const future = (try elements.next()).?;
    try std.testing.expectEqualStrings("a:future", future.qualified_name);
    try std.testing.expectEqualStrings("future", future.localName());
    try std.testing.expectEqualStrings("urn:adm", future.namespace_uri.?);
    try std.testing.expectEqualStrings(
        "audioObject",
        future.parent_element_name,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        future.declaration_owner.?.raw,
    );
    try std.testing.expectEqual(
        std.mem.indexOf(u8, bytes, "<a:future").?,
        future.source_offset,
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        future.source,
        "<![CDATA[literal < & >]]>",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        future.source,
        "<a:audioObject audioObjectID=\"AO_9999\"/>",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        future.source,
        "<v:nested/>",
    ) != null);
    try std.testing.expect(std.mem.endsWith(
        u8,
        future.source,
        "</a:future>",
    ));

    const empty = (try elements.next()).?;
    try std.testing.expectEqualStrings(
        "<a:futureEmpty/>",
        empty.source,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        empty.declaration_owner.?.raw,
    );
    try std.testing.expect((try elements.next()) == null);
}

test "ADM XML resolves common definitions and rejects missing custom ones" {
    _ = try Document.init(
        \\<audioFormatExtended>
        \\  <audioObject audioObjectID="AO_1001">
        \\    <audioPackFormatIDRef><![CDATA[AP_00010002]]></audioPackFormatIDRef>
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

test "ADM XML profile iterator contains hostile retained state" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <profileList>
        \\    <profile profileName="A" profileVersion="1" profileLevel="1">A</profile>
        \\    <profile profileName="B" profileVersion="1" profileLevel="1">B</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    var profiles = document.profiles();
    _ = (try profiles.next()).?;

    profiles.profile_list_depth = std.math.maxInt(usize);
    const hostile_depth_offset = profiles.events.events.offset;
    try std.testing.expectError(
        error.InvalidAdmProfileOwner,
        profiles.next(),
    );
    try std.testing.expectEqual(
        hostile_depth_offset,
        profiles.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        profiles.profile_list_depth.?,
    );

    profiles.profile_list_depth = 1;
    profiles.profiles_in_list = std.math.maxInt(usize);
    const hostile_count_offset = profiles.events.events.offset;
    try std.testing.expectError(
        error.InvalidAdmProfileIteratorState,
        profiles.next(),
    );
    try std.testing.expectEqual(
        hostile_count_offset,
        profiles.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        profiles.profiles_in_list,
    );
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

test "ADM XML emission profile validates PCM essence agreement" {
    const document = try Document.init(
        valid_emission_object_parameters_xml,
    );
    const essence = EmissionPcmEssence{
        .sample_rate = 48_000,
        .bit_depth = 24,
        .channel_count = 1,
        .frame_count = 48_000,
    };
    try document.validateEmissionProfilePcmEssence(essence);

    var mismatch = essence;
    mismatch.sample_rate = 96_000;
    try std.testing.expectError(
        error.AdmEmissionProfileSampleRateMismatch,
        document.validateEmissionProfilePcmEssence(mismatch),
    );
    mismatch = essence;
    mismatch.bit_depth = 16;
    try std.testing.expectError(
        error.AdmEmissionProfileBitDepthMismatch,
        document.validateEmissionProfilePcmEssence(mismatch),
    );
    mismatch = essence;
    mismatch.channel_count = 2;
    try std.testing.expectError(
        error.AdmEmissionProfileTrackCountMismatch,
        document.validateEmissionProfilePcmEssence(mismatch),
    );
    mismatch = essence;
    mismatch.frame_count -= 1;
    try std.testing.expectError(
        error.AdmEmissionProfileEssenceCoverageMismatch,
        document.validateEmissionProfilePcmEssence(mismatch),
    );

    const late_start = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "rtime=\"00:00:00.00000\"",
        "rtime=\"00:00:00.00500\"",
    );
    defer std.testing.allocator.free(late_start);
    const late_document = try Document.init(late_start);
    try std.testing.expectError(
        error.AdmEmissionProfileEssenceCoverageMismatch,
        late_document.validateEmissionProfilePcmEssence(essence),
    );
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

const valid_emission_labels_xml =
    \\<audioFormatExtended version="ITU-R_BS.2076-3">
    \\  <audioProgramme audioProgrammeID="APR_1001" audioProgrammeName="Programme" audioProgrammeLanguage="und">
    \\    <audioProgrammeLabel language="eng">Programme</audioProgrammeLabel>
    \\    <audioProgrammeLabel language="deu">Programm</audioProgrammeLabel>
    \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
    \\    <audioContentIDRef>ACO_1002</audioContentIDRef>
    \\    <loudnessMetadata>
    \\      <integratedLoudness>-23.0</integratedLoudness>
    \\    </loudnessMetadata>
    \\  </audioProgramme>
    \\  <audioContent audioContentID="ACO_1001" audioContentName="Main" audioContentLanguage="eng">
    \\    <audioContentLabel language="eng">Main</audioContentLabel>
    \\    <audioContentLabel language="deu">Hauptfassung</audioContentLabel>
    \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
    \\    <loudnessMetadata>
    \\      <dialogueLoudness>-24.0</dialogueLoudness>
    \\    </loudnessMetadata>
    \\    <dialogue dialogueContentKind="5">1</dialogue>
    \\  </audioContent>
    \\  <audioContent audioContentID="ACO_1002" audioContentName="Alternative" audioContentLanguage="deu">
    \\    <audioContentLabel language="eng">Alternative</audioContentLabel>
    \\    <audioContentLabel language="deu">Alternative</audioContentLabel>
    \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
    \\    <loudnessMetadata>
    \\      <dialogueLoudness>-24.0</dialogueLoudness>
    \\    </loudnessMetadata>
    \\    <dialogue dialogueContentKind="5">1</dialogue>
    \\  </audioContent>
    \\  <audioObject audioObjectID="AO_1001" audioObjectName="Main" interact="0">
    \\    <audioComplementaryObjectGroupLabel language="eng">Language</audioComplementaryObjectGroupLabel>
    \\    <audioComplementaryObjectGroupLabel language="deu">Sprache</audioComplementaryObjectGroupLabel>
    \\    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioObject audioObjectID="AO_1002" audioObjectName="Alternative" interact="0">
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
    \\  </audioObject>
    \\  <audioTrackUID UID="ATU_00000001" sampleRate="48000" bitDepth="24">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <audioTrackUID UID="ATU_00000002" sampleRate="48000" bitDepth="24">
    \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
    \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
    \\  </audioTrackUID>
    \\  <profileList>
    \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
    \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\  </profileList>
    \\</audioFormatExtended>
;

fn expectEmissionLabelReplacement(
    expected_error: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const replaced = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(replaced);
    try std.testing.expect(!std.mem.eql(
        u8,
        replaced,
        valid_emission_labels_xml,
    ));
    const document = try Document.init(replaced);
    try std.testing.expectError(
        expected_error,
        document.validateEmissionProfileComplementaryLabels(),
    );
}

test "ADM XML emission profile validates complementary labels" {
    const document = try Document.init(valid_emission_labels_xml);
    try document.validateEmissionProfileComplementaryLabels();
    try document.validateEmissionProfileConsistentLabelLanguages();

    const without_labels = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "    <audioComplementaryObjectGroupLabel language=\"eng\">Language</audioComplementaryObjectGroupLabel>\n" ++
            "    <audioComplementaryObjectGroupLabel language=\"deu\">Sprache</audioComplementaryObjectGroupLabel>\n",
        "",
    );
    defer std.testing.allocator.free(without_labels);
    const unlabeled_document = try Document.init(without_labels);
    try unlabeled_document.validateEmissionProfileComplementaryLabels();
}

test "ADM XML emission profile restricts complementary labels" {
    try expectEmissionLabelReplacement(
        error.MissingAdmEmissionProfileLanguage,
        "audioComplementaryObjectGroupLabel language=\"eng\"",
        "audioComplementaryObjectGroupLabel",
    );
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileLanguage,
        "audioComplementaryObjectGroupLabel language=\"eng\"",
        "audioComplementaryObjectGroupLabel language=\"ENG\"",
    );
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileLabel,
        ">Language</audioComplementaryObjectGroupLabel>",
        "></audioComplementaryObjectGroupLabel>",
    );
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileLabelAttribute,
        "audioComplementaryObjectGroupLabel language=\"eng\"",
        "audioComplementaryObjectGroupLabel language=\"eng\" role=\"menu\"",
    );
    try expectEmissionLabelReplacement(
        error.DuplicateAdmEmissionProfileLabelLanguage,
        "audioComplementaryObjectGroupLabel language=\"deu\"",
        "audioComplementaryObjectGroupLabel language=\"eng\"",
    );
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileReferenceAttribute,
        "<audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>",
        "<audioPackFormatIDRef role=\"main\">AP_00010001</audioPackFormatIDRef>",
    );
}

test "ADM XML emission profile requires labels on complementary leaders" {
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileComplementaryLabelOwner,
        "    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>\n" ++
            "    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>",
        "    <audioComplementaryObjectGroupLabel language=\"eng\">Invalid</audioComplementaryObjectGroupLabel>\n" ++
            "    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>\n" ++
            "    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>",
    );
    try expectEmissionLabelReplacement(
        error.InvalidAdmEmissionProfileComplementaryLabelOwner,
        "    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>\n",
        "",
    );
}

test "ADM XML emission profile checks recommended label languages" {
    const inconsistent = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "    <audioContentLabel language=\"deu\">Alternative</audioContentLabel>\n",
        "",
    );
    defer std.testing.allocator.free(inconsistent);
    const document = try Document.init(inconsistent);
    try document.validateEmissionProfileComplementaryLabels();
    try std.testing.expectError(
        error.InconsistentAdmEmissionProfileLabelLanguages,
        document.validateEmissionProfileConsistentLabelLanguages(),
    );
}

test "ADM XML emission profile checks recommended programme languages" {
    const document = try Document.init(valid_emission_labels_xml);
    try document.validateEmissionProfileRecommendedProgrammeLanguages();

    const non_recommended = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "audioProgrammeLanguage=\"und\"",
        "audioProgrammeLanguage=\"eng\"",
    );
    defer std.testing.allocator.free(non_recommended);
    const non_recommended_document = try Document.init(non_recommended);
    try non_recommended_document.validateEmissionProfileComplementaryLabels();
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileRecommendedProgrammeLanguage,
        non_recommended_document
            .validateEmissionProfileRecommendedProgrammeLanguages(),
    );

    const single_language_content = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        non_recommended,
        "audioContentLanguage=\"deu\"",
        "audioContentLanguage=\"eng\"",
    );
    defer std.testing.allocator.free(single_language_content);
    const single_language_document = try Document.init(
        single_language_content,
    );
    try single_language_document
        .validateEmissionProfileRecommendedProgrammeLanguages();
}

test "ADM XML emission profile checks recommended dialogue loudness" {
    const document = try Document.init(valid_emission_labels_xml);
    try std.testing.expectError(
        error.MissingAdmEmissionProfileRecommendedDialogueLoudness,
        document.validateEmissionProfileRecommendedDialogueLoudness(),
    );

    const programme_dialogue = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "      <integratedLoudness>-23.0</integratedLoudness>",
        "      <integratedLoudness>-23.0</integratedLoudness>\n" ++
            "      <dialogueLoudness>-24.0</dialogueLoudness>",
    );
    defer std.testing.allocator.free(programme_dialogue);
    const complete_document = try Document.init(programme_dialogue);
    try complete_document
        .validateEmissionProfileRecommendedDialogueLoudness();

    const mixed_content = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        programme_dialogue,
        "<dialogue dialogueContentKind=\"5\">1</dialogue>",
        "<dialogue mixedContentKind=\"0\">2</dialogue>",
    );
    defer std.testing.allocator.free(mixed_content);
    const mixed_content_document = try Document.init(mixed_content);
    try mixed_content_document
        .validateEmissionProfileRecommendedDialogueLoudness();

    const missing_content_dialogue = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        programme_dialogue,
        "    <audioContentLabel language=\"deu\">Hauptfassung</audioContentLabel>\n" ++
            "    <audioObjectIDRef>AO_1001</audioObjectIDRef>\n" ++
            "    <loudnessMetadata>\n" ++
            "      <dialogueLoudness>-24.0</dialogueLoudness>",
        "    <audioContentLabel language=\"deu\">Hauptfassung</audioContentLabel>\n" ++
            "    <audioObjectIDRef>AO_1001</audioObjectIDRef>\n" ++
            "    <loudnessMetadata>\n" ++
            "      <integratedLoudness>-24.0</integratedLoudness>",
    );
    defer std.testing.allocator.free(missing_content_dialogue);
    const missing_content_document = try Document.init(
        missing_content_dialogue,
    );
    try std.testing.expectError(
        error.MissingAdmEmissionProfileRecommendedDialogueLoudness,
        missing_content_document
            .validateEmissionProfileRecommendedDialogueLoudness(),
    );

    const non_dialogue_values = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "<dialogue dialogueContentKind=\"5\">1</dialogue>",
        "<dialogue nonDialogueContentKind=\"0\">0</dialogue>",
    );
    defer std.testing.allocator.free(non_dialogue_values);
    const non_dialogue_document = try Document.init(non_dialogue_values);
    try non_dialogue_document
        .validateEmissionProfileRecommendedDialogueLoudness();
}

const valid_serial_transport_xml =
    \\    <transportTrackFormat transportID="TP_0001" transportName="PCM" numTracks="2" numIDs="2">
    \\      <audioTrack trackID="1" formatLabel="0001" formatDefinition="PCM">
    \\        <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\      </audioTrack>
    \\      <audioTrack trackID="2" formatLabel="0001" formatDefinition="PCM">
    \\        <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
    \\      </audioTrack>
    \\    </transportTrackFormat>
;

const valid_serial_object_transport_xml =
    \\    <transportTrackFormat transportID="TP_0001" transportName="PCM" numTracks="1" numIDs="1">
    \\      <audioTrack trackID="1" formatLabel="0001" formatDefinition="PCM">
    \\        <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
    \\      </audioTrack>
    \\    </transportTrackFormat>
;

const valid_serial_profile_list_xml =
    \\    <profileList>
    \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
    \\    </profileList>
;

fn makeValidSerialEmissionFrame() ![]u8 {
    const framed_start = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_labels_xml,
        "<audioFormatExtended version=\"ITU-R_BS.2076-3\">",
        "<frame version=\"ITU-R_BS.2125-1\">\n" ++
            "  <frameHeader>\n" ++
            "    <frameFormat frameFormatID=\"FF_00000001\" start=\"00:00:00.00000\" duration=\"00:00:00.01000\" type=\"header\" timeReference=\"local\"/>\n" ++
            valid_serial_transport_xml ++ "\n" ++
            valid_serial_profile_list_xml ++ "\n" ++
            "  </frameHeader>\n" ++
            "  <audioFormatExtended version=\"ITU-R_BS.2076-3\">",
    );
    defer std.testing.allocator.free(framed_start);
    return std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed_start,
        "</audioFormatExtended>",
        "</audioFormatExtended>\n</frame>",
    );
}

fn makeValidSerialEmissionObjectFrame() ![]u8 {
    const serial_timing = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_emission_object_parameters_xml,
        "rtime=\"00:00:00.00000\" duration=\"00:00:01.00000\"",
        "lstart=\"00:00:00.00000\" lduration=\"00:00:01.00000\"",
    );
    defer std.testing.allocator.free(serial_timing);
    const framed_start = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        serial_timing,
        "<audioFormatExtended version=\"ITU-R_BS.2076-3\">",
        "<frame version=\"ITU-R_BS.2125-1\">\n" ++
            "  <frameHeader>\n" ++
            "    <frameFormat frameFormatID=\"FF_00000001\" start=\"00:00:00.00000\" duration=\"00:00:01.00000\" type=\"header\" timeReference=\"local\"/>\n" ++
            valid_serial_object_transport_xml ++ "\n" ++
            valid_serial_profile_list_xml ++ "\n" ++
            "  </frameHeader>\n" ++
            "  <audioFormatExtended version=\"ITU-R_BS.2076-3\">",
    );
    defer std.testing.allocator.free(framed_start);
    return std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed_start,
        "</audioFormatExtended>",
        "</audioFormatExtended>\n</frame>",
    );
}

test "ADM XML emission profile validates the serial frame envelope" {
    const framed = try makeValidSerialEmissionFrame();
    defer std.testing.allocator.free(framed);
    const document = try Document.init(framed);
    try document.validateEmissionProfileSerialFrameEnvelope();
    try document.validateEmissionProfileSerialTransportTracks();
    try document.validateEmissionProfileSerialHeaderProfiles();
}

test "ADM XML emission profile restricts the serial frame envelope" {
    const framed = try makeValidSerialEmissionFrame();
    defer std.testing.allocator.free(framed);
    const cases = [_]struct {
        expected: anyerror,
        needle: []const u8,
        replacement: []const u8,
    }{
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameAttribute,
            .needle = "version=\"ITU-R_BS.2125-1\"",
            .replacement = "version=\"ITU-R_BS.2125-1\" custom=\"1\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameAttribute,
            .needle = "version=\"ITU-R_BS.2125-1\"",
            .replacement = "version=\"ITU-R_BS.2125-0\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameDuration,
            .needle = "duration=\"00:00:00.01000\"",
            .replacement = "duration=\"00:00:00.00499\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameFormatAttribute,
            .needle = "timeReference=\"local\"",
            .replacement = "timeReference=\"global\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameHeader,
            .needle = valid_serial_transport_xml,
            .replacement = "",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameHeader,
            .needle = valid_serial_profile_list_xml ++ "\n",
            .replacement = "",
        },
    };
    for (cases) |case| {
        const replaced = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            framed,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(replaced);
        const document = try Document.init(replaced);
        try std.testing.expectError(
            case.expected,
            document.validateEmissionProfileSerialFrameEnvelope(),
        );
    }
}

test "ADM XML emission profile restricts serial transport tracks" {
    const framed = try makeValidSerialEmissionFrame();
    defer std.testing.allocator.free(framed);
    const cases = [_]struct {
        expected: anyerror,
        needle: []const u8,
        replacement: []const u8,
    }{
        .{
            .expected = error.DuplicateAdmEmissionProfileSerialTransportIdentifier,
            .needle = valid_serial_transport_xml,
            .replacement = valid_serial_transport_xml ++ "\n" ++
                valid_serial_transport_xml,
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialTransportCount,
            .needle = "numTracks=\"2\"",
            .replacement = "numTracks=\"1\"",
        },
        .{
            .expected = error.DuplicateAdmEmissionProfileSerialTrackIdentifier,
            .needle = "trackID=\"2\"",
            .replacement = "trackID=\"1\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialAudioTrackAttribute,
            .needle = "formatDefinition=\"PCM\"",
            .replacement = "formatDefinition=\"FLOAT\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialTrackReference,
            .needle = "        <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>",
            .replacement = "        <audioTrackUIDRef>ATU_00000003</audioTrackUIDRef>",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialTrackMapping,
            .needle = "        <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>",
            .replacement = "        <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>",
        },
    };
    for (cases) |case| {
        const replaced = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            framed,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(replaced);
        const document = try Document.init(replaced);
        try std.testing.expectError(
            case.expected,
            document.validateEmissionProfileSerialTransportTracks(),
        );
    }
}

test "ADM XML emission profile restricts serial header profiles" {
    const framed = try makeValidSerialEmissionFrame();
    defer std.testing.allocator.free(framed);
    const cases = [_]struct {
        expected: anyerror,
        replacement: []const u8,
    }{
        .{
            .expected = error.DuplicateAdmEmissionProfileSerialHeaderProfile,
            .replacement =
            \\    <profileList>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.MissingAdmEmissionProfileSerialHeaderProfile,
            .replacement =
            \\    <profileList>
            \\      <profile profileName="Other profile" profileVersion="1" profileLevel="1">Example</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.MismatchedAdmEmissionProfileSerialHeaderProfile,
            .replacement =
            \\    <profileList>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="2">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialProfileAttribute,
            .replacement =
            \\    <profileList>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1" custom="1">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialProfileListAttribute,
            .replacement =
            \\    <profileList custom="1">
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.MissingAdmProfileLevel,
            .replacement =
            \\    <profileList>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialProfileListSubelement,
            .replacement =
            \\    <profileList>
            \\      <custom/>
            \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
            \\    </profileList>
            ,
        },
    };
    for (cases) |case| {
        const replaced = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            framed,
            valid_serial_profile_list_xml,
            case.replacement,
        );
        defer std.testing.allocator.free(replaced);
        const document = try Document.init(replaced);
        try std.testing.expectError(
            case.expected,
            document.validateEmissionProfileSerialHeaderProfiles(),
        );
    }

    const additional_profile =
        \\    <profileList>
        \\      <profile profileName="Other profile" profileVersion="1" profileLevel="1">Example</profile>
        \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\    </profileList>
    ;
    const with_additional = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        valid_serial_profile_list_xml,
        additional_profile,
    );
    defer std.testing.allocator.free(with_additional);
    const additional_document = try Document.init(with_additional);
    try additional_document.validateEmissionProfileSerialHeaderProfiles();

    const encoded_reference = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        valid_serial_profile_list_xml,
        \\    <profileList>
        \\      <profile profileName="Advanced sound system: ADM and S-ADM profile for emission" profileVersion="1" profileLevel="1">ITU-R&#32;BS.2168</profile>
        \\    </profileList>
        ,
    );
    defer std.testing.allocator.free(encoded_reference);
    const encoded_document = try Document.init(encoded_reference);
    try encoded_document.validateEmissionProfileSerialHeaderProfiles();
}

test "ADM XML emission profile validates serial object block timing" {
    const framed = try makeValidSerialEmissionObjectFrame();
    defer std.testing.allocator.free(framed);
    const document = try Document.init(framed);
    try document.validateEmissionProfileSerialObjectBlocks();
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.MissingAdmEmissionProfileSerialBlockTiming;
    try std.testing.expect(block.lstart != null);
    try std.testing.expect(block.lduration != null);
    try std.testing.expect(block.initialize_block == null);

    const split_blocks = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001" lstart="00:00:00.00000" lduration="00:00:01.00000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
    ,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000007" lstart="0S48000" lduration="24000S48000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000008" lstart="24000S48000" lduration="00:00:00.50000">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
        ,
    );
    defer std.testing.allocator.free(split_blocks);
    const split_document = try Document.init(split_blocks);
    try split_document.validateEmissionProfileSerialObjectBlocks();

    const discontinuous = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        split_blocks,
        "lstart=\"24000S48000\"",
        "lstart=\"23000S48000\"",
    );
    defer std.testing.allocator.free(discontinuous);
    const discontinuous_document = try Document.init(discontinuous);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileSerialBlockTiming,
        discontinuous_document.validateEmissionProfileSerialObjectBlocks(),
    );

    const skipped_counter = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        split_blocks,
        "AB_00031001_00000008",
        "AB_00031001_00000009",
    );
    defer std.testing.allocator.free(skipped_counter);
    const skipped_counter_document = try Document.init(skipped_counter);
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileSerialBlockIdentifier,
        skipped_counter_document.validateEmissionProfileSerialObjectBlocks(),
    );

    const initialized = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001" lstart="00:00:00.00000" lduration="00:00:01.00000">
    ,
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000000" initializeBlock="1">
        \\      <position coordinate="azimuth">0.0</position>
        \\      <position coordinate="elevation">0.0</position>
        \\      <position coordinate="distance">1.0</position>
        \\    </audioBlockFormatObjects>
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000009" lstart="00:00:00.00000" lduration="00:00:01.00000">
        ,
    );
    defer std.testing.allocator.free(initialized);
    const initialized_document = try Document.init(initialized);
    try initialized_document.validateEmissionProfileSerialObjectBlocks();

    const invalid_initialize_id = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        initialized,
        "AB_00031001_00000000",
        "AB_00031001_0000000a",
    );
    defer std.testing.allocator.free(invalid_initialize_id);
    const invalid_initialize_document = try Document.init(
        invalid_initialize_id,
    );
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileSerialInitializeBlock,
        invalid_initialize_document.validateEmissionProfileSerialObjectBlocks(),
    );
}

test "ADM XML emission profile restricts serial object block timing" {
    const framed = try makeValidSerialEmissionObjectFrame();
    defer std.testing.allocator.free(framed);
    const cases = [_]struct {
        expected: anyerror,
        needle: []const u8,
        replacement: []const u8,
    }{
        .{
            .expected = error.InvalidAdmEmissionProfileSerialBlockAttribute,
            .needle = "lstart=\"00:00:00.00000\"",
            .replacement = "rtime=\"00:00:00.00000\"",
        },
        .{
            .expected = error.MissingAdmEmissionProfileSerialBlockTiming,
            .needle = " lduration=\"00:00:01.00000\"",
            .replacement = "",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialBlockDuration,
            .needle = "lduration=\"00:00:01.00000\"",
            .replacement = "lduration=\"00:00:00.00499\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialBlockTiming,
            .needle = "lstart=\"00:00:00.00000\"",
            .replacement = "lstart=\"00:00:00.00500\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameCoverage,
            .needle = "lduration=\"00:00:01.00000\"",
            .replacement = "lduration=\"00:00:00.50000\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialBlockIdentifier,
            .needle = "audioBlockFormatID=\"AB_00031001_00000001\"",
            .replacement = "audioBlockFormatID=\"AB_00031001_00000000\"",
        },
    };
    for (cases) |case| {
        const replaced = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            framed,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(replaced);
        const document = try Document.init(replaced);
        try std.testing.expectError(
            case.expected,
            document.validateEmissionProfileSerialObjectBlocks(),
        );
    }
}

test "ADM XML emission profile validates serial flow continuity" {
    const framed = try makeValidSerialEmissionObjectFrame();
    defer std.testing.allocator.free(framed);
    const first = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        "timeReference=\"local\"",
        "timeReference=\"local\" flowID=\"12345678-abcd-4000-a000-112233445566\"",
    );
    defer std.testing.allocator.free(first);
    const second_index = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        first,
        "frameFormatID=\"FF_00000001\" start=\"00:00:00.00000\"",
        "frameFormatID=\"FF_00000002\" start=\"00:00:01.00000\"",
    );
    defer std.testing.allocator.free(second_index);
    const second = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        second_index,
        "type=\"header\"",
        "type=\"full\"",
    );
    defer std.testing.allocator.free(second);

    var state = EmissionSerialFlowState{};
    const first_document = try Document.init(first);
    try first_document.validateEmissionProfileSerialFlowFrame(&state);
    try std.testing.expect(state.initialized);
    try std.testing.expectEqual(@as(u32, 2), state.next_frame_index);
    const second_document = try Document.init(second);
    try second_document.validateEmissionProfileSerialFlowFrame(&state);
    try std.testing.expectEqual(@as(u32, 3), state.next_frame_index);
    const expected_start = try adm_time.Value.parse("00:00:02.00000");
    try std.testing.expectEqual(
        std.math.Order.eq,
        expected_start.compare(state.next_start.?),
    );
    state.reset();
    try std.testing.expect(!state.initialized);
}

test "ADM XML emission profile rejects invalid serial flow transitions" {
    const framed = try makeValidSerialEmissionObjectFrame();
    defer std.testing.allocator.free(framed);
    const first = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        framed,
        "timeReference=\"local\"",
        "timeReference=\"local\" flowID=\"12345678-abcd-4000-a000-112233445566\"",
    );
    defer std.testing.allocator.free(first);
    const second_index = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        first,
        "frameFormatID=\"FF_00000001\" start=\"00:00:00.00000\"",
        "frameFormatID=\"FF_00000002\" start=\"00:00:01.00000\"",
    );
    defer std.testing.allocator.free(second_index);
    const second = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        second_index,
        "type=\"header\"",
        "type=\"full\"",
    );
    defer std.testing.allocator.free(second);
    const cases = [_]struct {
        expected: anyerror,
        needle: []const u8,
        replacement: []const u8,
    }{
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameSequence,
            .needle = "FF_00000002",
            .replacement = "FF_00000003",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameContinuity,
            .needle = "start=\"00:00:01.00000\"",
            .replacement = "start=\"00:00:00.50000\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFrameType,
            .needle = "type=\"full\"",
            .replacement = "type=\"header\"",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFlowIdentifier,
            .needle = "12345678-abcd-4000-a000-112233445566",
            .replacement = "12345678-abcd-4000-a000-112233445567",
        },
        .{
            .expected = error.InvalidAdmEmissionProfileSerialFlowIdentifier,
            .needle = "12345678-abcd-4000-a000-112233445566",
            .replacement = "12345678-abcd-4000-a000-11223344556z",
        },
    };
    const first_document = try Document.init(first);
    for (cases) |case| {
        var state = EmissionSerialFlowState{};
        try first_document.validateEmissionProfileSerialFlowFrame(&state);
        const replaced = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            second,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(replaced);
        const document = try Document.init(replaced);
        try std.testing.expectError(
            case.expected,
            document.validateEmissionProfileSerialFlowFrame(&state),
        );
        try std.testing.expectEqual(@as(u32, 2), state.next_frame_index);
    }

    const invalid_first = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        first,
        "FF_00000001",
        "FF_00000002",
    );
    defer std.testing.allocator.free(invalid_first);
    const invalid_first_document = try Document.init(invalid_first);
    var state = EmissionSerialFlowState{};
    try std.testing.expectError(
        error.InvalidAdmEmissionProfileSerialFrameSequence,
        invalid_first_document.validateEmissionProfileSerialFlowFrame(&state),
    );
    try std.testing.expect(!state.initialized);
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
        \\      <tag class="format">NGA &amp; <![CDATA[immersive <mix>]]></tag>
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
    try std.testing.expectEqualStrings(
        "NGA & immersive <mix>",
        first.value,
    );
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

test "ADM XML tag iterator contains hostile retained state" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <tagList><tagGroup>
        \\    <tag>first</tag><tag>second</tag>
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\  </tagGroup></tagList>
        \\</audioFormatExtended>
    );
    var items = document.tags();
    _ = (try items.next()).?.tag;

    items.tag_group_depth = std.math.maxInt(usize);
    const hostile_depth_offset = items.events.events.offset;
    try std.testing.expectError(error.InvalidAdmTagOwner, items.next());
    try std.testing.expectEqual(
        hostile_depth_offset,
        items.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        items.tag_group_depth.?,
    );

    items.tag_group_depth = 2;
    items.tags_in_group = std.math.maxInt(usize);
    const hostile_count_offset = items.events.events.offset;
    try std.testing.expectError(
        error.InvalidAdmTagIteratorState,
        items.next(),
    );
    try std.testing.expectEqual(
        hostile_count_offset,
        items.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        items.tags_in_group,
    );

    var target_items = document.tags();
    _ = (try target_items.next()).?.tag;
    _ = (try target_items.next()).?.tag;
    target_items.targets_in_group = std.math.maxInt(usize);
    const hostile_target_offset = target_items.events.events.offset;
    try std.testing.expectError(
        error.InvalidAdmTagIteratorState,
        target_items.next(),
    );
    try std.testing.expectEqual(
        hostile_target_offset,
        target_items.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        target_items.targets_in_group,
    );

    var group_items = document.tags();
    _ = (try group_items.next()).?.tag;
    _ = (try group_items.next()).?.tag;
    _ = (try group_items.next()).?.target;
    group_items.group_count = std.math.maxInt(usize);
    const hostile_group_offset = group_items.events.events.offset;
    try std.testing.expectError(
        error.InvalidAdmTagIteratorState,
        group_items.next(),
    );
    try std.testing.expectEqual(
        hostile_group_offset,
        group_items.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        group_items.group_count,
    );
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
        \\      <gain gainUnit="dB"><![CDATA[-6.0]]></gain>
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
    for (first.positions[first.position_count..]) |position|
        try std.testing.expectEqualDeep(Position{}, position);
    for (first.speaker_labels) |label| {
        try std.testing.expectEqual(@as(u8, 0), label.len);
        try std.testing.expectEqual(
            @as([max_adm_speaker_label_bytes]u8, @splat(0)),
            label.bytes,
        );
    }
    for (first.exclusion_zones) |zone| switch (zone) {
        .cartesian => |cartesian| try std.testing.expectEqualDeep(
            CartesianExclusionZone{},
            cartesian,
        ),
        .polar => return error.TestUnexpectedResult,
    };
    for (first.matrix_coefficients) |coefficient| {
        try std.testing.expectEqual(
            @as(u8, 0),
            coefficient.channel_identifier_len,
        );
        try std.testing.expectEqual(
            @as([max_identifier_bytes]u8, @splat(0)),
            coefficient.channel_identifier_bytes,
        );
    }

    var malformed_block = first;
    malformed_block.position_count = std.math.maxInt(usize);
    malformed_block.speaker_label_count = std.math.maxInt(usize);
    malformed_block.exclusion_zone_count = std.math.maxInt(usize);
    malformed_block.matrix_coefficient_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_block.retainedCountsValid());
    try std.testing.expectEqual(@as(usize, 0), malformed_block.positionSlice().len);
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.speakerLabelSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.exclusionZoneSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.matrixCoefficientSlice().len,
    );

    const malformed_text = AdmText{ .len = std.math.maxInt(u8) };
    try std.testing.expect(!malformed_text.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed_text.value().len);
    try std.testing.expectEqual(
        @as([max_profile_text_bytes]u8, @splat(0)),
        (AdmText{}).bytes,
    );

    const malformed_label = SpeakerLabel{ .len = std.math.maxInt(u8) };
    try std.testing.expect(!malformed_label.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed_label.value().len);
    try std.testing.expectEqual(
        @as([max_adm_speaker_label_bytes]u8, @splat(0)),
        (SpeakerLabel{}).bytes,
    );

    const malformed_coefficient = MatrixCoefficient{
        .channel_identifier_len = std.math.maxInt(u8),
    };
    try std.testing.expectError(
        error.InvalidAdmMatrixCoefficientState,
        malformed_coefficient.channelIdentifier(),
    );
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

    blocks.channel_depth = std.math.maxInt(usize);
    const hostile_depth_offset = blocks.events.events.offset;
    try std.testing.expectError(error.InvalidAdmBlockOwner, blocks.next());
    try std.testing.expectEqual(
        hostile_depth_offset,
        blocks.events.events.offset,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        blocks.channel_depth.?,
    );
    blocks.channel_depth = 1;

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

test "ADM XML exposes channel frequency and circular speaker bounds" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <frequency typeDefinition="lowPass">120</frequency>
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth" bound="min">90</position>
        \\      <position coordinate="azimuth">180</position>
        \\      <position coordinate="azimuth" bound="max">-90</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    try std.testing.expect(block.channel_frequency.isLfe());
    try std.testing.expectEqual(
        @as(?f64, 120.0),
        block.channel_frequency.low_pass_hz,
    );
    try std.testing.expectEqual(
        @as(?f64, null),
        block.channel_frequency.high_pass_hz,
    );

    const high_pass_document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <frequency typeDefinition="lowPass">80</frequency>
        \\    <frequency typeDefinition="highPass">20</frequency>
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var high_pass_blocks = high_pass_document.blocks();
    const high_pass_block = (try high_pass_blocks.next()).?;
    try std.testing.expect(!high_pass_block.channel_frequency.isLfe());
}

test "ADM XML rejects malformed channel frequency metadata" {
    try std.testing.expectError(
        error.DuplicateAdmFrequency,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
            \\    <frequency typeDefinition="lowPass">120</frequency>
            \\    <frequency typeDefinition="lowPass">80</frequency>
            \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\    </audioBlockFormatDirectSpeakers>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );

    try std.testing.expectError(
        error.InvalidAdmFrequencyType,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
            \\    <frequency typeDefinition="bandPass">120</frequency>
            \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\    </audioBlockFormatDirectSpeakers>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
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

test "ADM XML retains bounded polar and Cartesian exclusion zones" {
    const document = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <zoneExclusion>
        \\        <zone minX="-1" minY="-1" minZ="-1" maxX="1" maxY="-0.5" maxZ="1"/>
        \\        <zone minAzimuth="175" maxAzimuth="-175" minElevation="-30" maxElevation="30"></zone>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    try std.testing.expectEqual(@as(usize, 2), block.exclusion_zone_count);
    const zones = block.exclusionZoneSlice();
    try std.testing.expectEqual(@as(f64, -0.5), zones[0].cartesian.max_y);
    try std.testing.expectEqual(@as(f64, 175.0), zones[1].polar.min_azimuth);
    try std.testing.expectEqual(@as(f64, -175.0), zones[1].polar.max_azimuth);

    const empty = try Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <zoneExclusion/>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var empty_blocks = empty.blocks();
    const empty_block = (try empty_blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    try std.testing.expectEqual(
        @as(usize, 0),
        empty_block.exclusion_zone_count,
    );
}

test "ADM XML rejects malformed exclusion zones" {
    try std.testing.expectError(
        error.InvalidAdmExclusionZone,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\      <zoneExclusion>
            \\        <zone minX="-1" minY="-1" minZ="-1" maxX="1" maxY="1" maxZ="1"
            \\          minAzimuth="-30" maxAzimuth="30" minElevation="-30" maxElevation="30"/>
            \\      </zoneExclusion>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.MissingAdmExclusionZoneAttribute,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\      <zoneExclusion>
            \\        <zone minAzimuth="-30" maxAzimuth="30" minElevation="-30"/>
            \\      </zoneExclusion>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmExclusionZoneBounds,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
            \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\      <zoneExclusion>
            \\        <zone minX="0.5" minY="-1" minZ="-1" maxX="-0.5" maxY="1" maxZ="1"/>
            \\      </zoneExclusion>
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
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\      <zoneExclusion>
            \\        <zone minAzimuth="-181" maxAzimuth="30" minElevation="-30" maxElevation="30"/>
            \\      </zoneExclusion>
            \\    </audioBlockFormatObjects>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
    try std.testing.expectError(
        error.AdmBlockParameterNotAllowedForType,
        Document.init(
            \\<audioFormatExtended>
            \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
            \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
            \\      <position coordinate="azimuth">0</position>
            \\      <position coordinate="elevation">0</position>
            \\      <zoneExclusion/>
            \\    </audioBlockFormatDirectSpeakers>
            \\  </audioChannelFormat>
            \\</audioFormatExtended>
        ),
    );
}

test "ADM XML bounds exclusion zone storage" {
    var storage: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    try writer.writeAll(
        "<audioFormatExtended><audioChannelFormat " ++
            "audioChannelFormatID=\"AC_00031001\">" ++
            "<audioBlockFormatObjects " ++
            "audioBlockFormatID=\"AB_00031001_00000001\">" ++
            "<position coordinate=\"azimuth\">0</position>" ++
            "<position coordinate=\"elevation\">0</position>" ++
            "<zoneExclusion>",
    );
    for (0..max_adm_exclusion_zones + 1) |_|
        try writer.writeAll(
            "<zone minAzimuth=\"0\" maxAzimuth=\"0\" " ++
                "minElevation=\"0\" maxElevation=\"0\"/>",
        );
    try writer.writeAll(
        "</zoneExclusion></audioBlockFormatObjects>" ++
            "</audioChannelFormat></audioFormatExtended>",
    );
    try std.testing.expectError(
        error.TooManyAdmExclusionZones,
        Document.init(writer.buffered()),
    );
}
