const std = @import("std");
const adm = @import("../adm.zig");
const adm_time = @import("../adm_time.zig");
const common = @import("common.zig");
const emission = @import("emission.zig");
const metadata = @import("metadata.zig");
const model = @import("model.zig");
const xml = @import("../xml.zig");

const MetadataSource = metadata.MetadataSource;
const MetadataEventIterator = metadata.MetadataEventIterator;
const insideAfe = common.insideAfe;
const max_identifier_bytes = common.max_identifier_bytes;
const max_profile_text_bytes = common.max_profile_text_bytes;
const parseAdmFlag = model.parseAdmFlag;
const parseGainUnit = model.parseGainUnit;
const parseAdmMatrixGain = model.parseAdmMatrixGain;
const parseFiniteAdmFloat = model.parseFiniteAdmFloat;
const validateAdmAttributes = emission.validateAdmAttributes;
const GainUnit = model.GainUnit;
const Gain = model.Gain;
const Frequency = model.Frequency;
const JumpPosition = model.JumpPosition;
const HeadphoneVirtualise = model.HeadphoneVirtualise;
const Coordinate = model.Coordinate;
const PositionBound = model.PositionBound;
const ScreenEdge = model.ScreenEdge;
const Position = model.Position;
const SpeakerLabel = model.SpeakerLabel;
const ObjectDivergence = model.ObjectDivergence;
const ChannelLock = model.ChannelLock;
const CartesianExclusionZone = model.CartesianExclusionZone;
const PolarExclusionZone = model.PolarExclusionZone;
const ExclusionZone = model.ExclusionZone;
const HoaNormalization = model.HoaNormalization;
const AdmText = model.AdmText;
const MatrixCoefficient = model.MatrixCoefficient;
const BlockFormat = model.BlockFormat;
const max_adm_positions = model.max_adm_positions;
const max_adm_speaker_labels = model.max_adm_speaker_labels;
const max_adm_speaker_label_bytes = model.max_adm_speaker_label_bytes;
const max_adm_matrix_coefficients = model.max_adm_matrix_coefficients;
const max_adm_exclusion_zones = model.max_adm_exclusion_zones;

pub const BlockIterator = struct {
    events: MetadataEventIterator,
    afe_depth: ?usize = null,
    channel_identifier: ?adm.Identifier = null,
    channel_name: ?AdmText = null,
    channel_frequency: Frequency = .{},
    channel_depth: ?usize = null,
    channel_storage: [max_identifier_bytes]u8 = undefined,
    identifier_storage: [max_identifier_bytes]u8 = undefined,
    value_storage: [max_profile_text_bytes]u8 = undefined,

    pub fn init(source: MetadataSource) BlockIterator {
        return .{ .events = MetadataEventIterator.init(source) };
    }

    /// Returned identifiers remain valid until the next iterator call.
    pub fn next(self: *BlockIterator) !?BlockFormat {
        const checkpoint = self.*;
        return self.nextInPlace() catch |err| {
            self.* = checkpoint;
            return err;
        };
    }

    fn nextInPlace(self: *BlockIterator) !?BlockFormat {
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
                            self.channel_frequency = .{};
                            self.channel_depth = null;
                        } else {
                            self.channel_identifier = identifier;
                            self.channel_frequency = .{};
                            self.channel_depth = element.depth;
                        }
                        continue;
                    }
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "frequency",
                    )) {
                        const channel_depth = self.channel_depth orelse
                            return error.InvalidAdmFrequencyOwner;
                        if (!isDirectChild(channel_depth, element.depth))
                            return error.InvalidAdmFrequencyOwner;
                        const type_definition =
                            try element.attribute("typeDefinition") orelse
                            return error.MissingAdmFrequencyType;
                        const value = try self.readFloatElement(element);
                        if (value < 0.0)
                            return error.InvalidAdmFrequency;
                        if (std.mem.eql(
                            u8,
                            type_definition,
                            "lowPass",
                        )) {
                            if (self.channel_frequency.low_pass_hz != null)
                                return error.DuplicateAdmFrequency;
                            self.channel_frequency.low_pass_hz = value;
                        } else if (std.mem.eql(
                            u8,
                            type_definition,
                            "highPass",
                        )) {
                            if (self.channel_frequency.high_pass_hz != null)
                                return error.DuplicateAdmFrequency;
                            self.channel_frequency.high_pass_hz = value;
                        } else {
                            return error.InvalidAdmFrequencyType;
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
                    if (!isDirectChild(channel_depth, element.depth))
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
                        self.channel_frequency = .{};
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
        const encoded_lstart = try start.attribute("lstart");
        const encoded_lduration = try start.attribute("lduration");
        const encoded_initialize = try start.attribute("initializeBlock");
        var block = BlockFormat{
            .identifier = identifier,
            .channel_identifier = channel,
            .channel_name = channel_name,
            .channel_frequency = self.channel_frequency,
            .rtime = if (encoded_rtime) |value|
                try adm_time.Value.parse(value)
            else
                zeroAdmTime(),
            .rtime_explicit = encoded_rtime != null,
            .duration = if (encoded_duration) |value|
                try adm_time.Value.parse(value)
            else
                null,
            .lstart = if (encoded_lstart) |value|
                try adm_time.Value.parse(value)
            else
                null,
            .lduration = if (encoded_lduration) |value|
                try adm_time.Value.parse(value)
            else
                null,
            .initialize_block = if (encoded_initialize) |value|
                try parseAdmFlag(value)
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
        var zone_exclusion_seen = false;
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
                                block.lduration orelse
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
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        "zoneExclusion",
                    )) {
                        if (zone_exclusion_seen)
                            return error.DuplicateAdmBlockParameter;
                        zone_exclusion_seen = true;
                        try self.readZoneExclusion(element, &block);
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
                            .zone_exclusion = zone_exclusion_seen,
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

    fn readZoneExclusion(
        self: *BlockIterator,
        start: xml.StartElement,
        block: *BlockFormat,
    ) !void {
        try validateAdmAttributes(
            start,
            &.{},
            error.InvalidAdmZoneExclusion,
        );
        if (start.self_closing) return;
        while (try self.events.next()) |event| {
            switch (event) {
                .text => |text| {
                    if (std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                        return error.InvalidAdmZoneExclusion;
                },
                .start => |element| {
                    if (element.depth != start.depth + 1 or
                        !std.mem.eql(u8, element.localName(), "zone"))
                    {
                        return error.InvalidAdmZoneExclusion;
                    }
                    if (block.exclusion_zone_count ==
                        max_adm_exclusion_zones)
                    {
                        return error.TooManyAdmExclusionZones;
                    }
                    block.exclusion_zones[block.exclusion_zone_count] =
                        try self.readExclusionZone(element);
                    block.exclusion_zone_count += 1;
                },
                .end => |element| {
                    if (element.depth != start.depth or
                        !std.mem.eql(u8, element.name, start.name))
                    {
                        return error.InvalidAdmZoneExclusion;
                    }
                    return;
                },
            }
        }
        return error.UnclosedAdmZoneExclusion;
    }

    fn readExclusionZone(
        self: *BlockIterator,
        start: xml.StartElement,
    ) !ExclusionZone {
        const min_x = try start.attribute("minX");
        const min_y = try start.attribute("minY");
        const min_z = try start.attribute("minZ");
        const max_x = try start.attribute("maxX");
        const max_y = try start.attribute("maxY");
        const max_z = try start.attribute("maxZ");
        const min_azimuth = try start.attribute("minAzimuth");
        const max_azimuth = try start.attribute("maxAzimuth");
        const min_elevation = try start.attribute("minElevation");
        const max_elevation = try start.attribute("maxElevation");
        const has_cartesian = min_x != null or
            min_y != null or
            min_z != null or
            max_x != null or
            max_y != null or
            max_z != null;
        const has_polar = min_azimuth != null or
            max_azimuth != null or
            min_elevation != null or
            max_elevation != null;
        if (has_cartesian == has_polar)
            return error.InvalidAdmExclusionZone;

        const zone: ExclusionZone = if (has_cartesian) cartesian: {
            try validateAdmAttributes(
                start,
                &.{ "minX", "minY", "minZ", "maxX", "maxY", "maxZ" },
                error.InvalidAdmExclusionZoneAttribute,
            );
            const value = CartesianExclusionZone{
                .min_x = try parseFiniteAdmFloat(
                    min_x orelse return error.MissingAdmExclusionZoneAttribute,
                ),
                .min_y = try parseFiniteAdmFloat(
                    min_y orelse return error.MissingAdmExclusionZoneAttribute,
                ),
                .min_z = try parseFiniteAdmFloat(
                    min_z orelse return error.MissingAdmExclusionZoneAttribute,
                ),
                .max_x = try parseFiniteAdmFloat(
                    max_x orelse return error.MissingAdmExclusionZoneAttribute,
                ),
                .max_y = try parseFiniteAdmFloat(
                    max_y orelse return error.MissingAdmExclusionZoneAttribute,
                ),
                .max_z = try parseFiniteAdmFloat(
                    max_z orelse return error.MissingAdmExclusionZoneAttribute,
                ),
            };
            try validateCartesianExclusionZone(value);
            break :cartesian .{ .cartesian = value };
        } else polar: {
            try validateAdmAttributes(
                start,
                &.{
                    "minAzimuth",
                    "maxAzimuth",
                    "minElevation",
                    "maxElevation",
                },
                error.InvalidAdmExclusionZoneAttribute,
            );
            const value = PolarExclusionZone{
                .min_azimuth = try parseFiniteAdmFloat(
                    min_azimuth orelse
                        return error.MissingAdmExclusionZoneAttribute,
                ),
                .max_azimuth = try parseFiniteAdmFloat(
                    max_azimuth orelse
                        return error.MissingAdmExclusionZoneAttribute,
                ),
                .min_elevation = try parseFiniteAdmFloat(
                    min_elevation orelse
                        return error.MissingAdmExclusionZoneAttribute,
                ),
                .max_elevation = try parseFiniteAdmFloat(
                    max_elevation orelse
                        return error.MissingAdmExclusionZoneAttribute,
                ),
            };
            try validatePolarExclusionZone(value);
            break :polar .{ .polar = value };
        };
        try self.consumeEmptyElement(start);
        return zone;
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
                    encoded_bytes = xml.appendEncodedText(
                        &encoded_storage,
                        encoded_bytes,
                        text,
                    ) catch return error.AdmBlockValueTooLong;
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
    zone_exclusion: bool = false,
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
                present.zone_exclusion or
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
        present.zone_exclusion or
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
        present.zone_exclusion or
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
    for (block.exclusionZoneSlice()) |zone| {
        switch (zone) {
            .cartesian => |value| try validateCartesianExclusionZone(value),
            .polar => |value| try validatePolarExclusionZone(value),
        }
    }
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
        present.zone_exclusion or
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
        present.zone_exclusion or
        present.screen_ref or
        hasHoaParameters(present))
    {
        return error.AdmBlockParameterNotAllowedForType;
    }
}

fn validateCartesianExclusionZone(
    zone: CartesianExclusionZone,
) !void {
    try validateInclusive(zone.min_x, -1.0, 1.0);
    try validateInclusive(zone.min_y, -1.0, 1.0);
    try validateInclusive(zone.min_z, -1.0, 1.0);
    try validateInclusive(zone.max_x, -1.0, 1.0);
    try validateInclusive(zone.max_y, -1.0, 1.0);
    try validateInclusive(zone.max_z, -1.0, 1.0);
    if (zone.min_x > zone.max_x or
        zone.min_y > zone.max_y or
        zone.min_z > zone.max_z)
    {
        return error.InvalidAdmExclusionZoneBounds;
    }
}

fn validatePolarExclusionZone(
    zone: PolarExclusionZone,
) !void {
    try validateInclusive(zone.min_azimuth, -180.0, 180.0);
    try validateInclusive(zone.max_azimuth, -180.0, 180.0);
    try validateInclusive(zone.min_elevation, -90.0, 90.0);
    try validateInclusive(zone.max_elevation, -90.0, 90.0);
    if (zone.min_elevation > zone.max_elevation)
        return error.InvalidAdmExclusionZoneBounds;
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
                if (coordinate != .azimuth and
                    minimum_value > maximum_value)
                {
                    return error.InvalidAdmPositionBounds;
                }
            }
        }
        if (exact) |value| {
            if (coordinate == .azimuth) {
                if (minimum) |minimum_value| {
                    if (maximum) |maximum_value| {
                        if (!insideAdmAngleRange(
                            value,
                            minimum_value,
                            maximum_value,
                        )) {
                            return error.InvalidAdmPositionBounds;
                        }
                    } else {
                        if (value < minimum_value)
                            return error.InvalidAdmPositionBounds;
                    }
                } else {
                    if (maximum) |maximum_value| {
                        if (value > maximum_value)
                            return error.InvalidAdmPositionBounds;
                    }
                }
            } else {
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
}

fn insideAdmAngleRange(value: f64, start: f64, end: f64) bool {
    if (start == -180.0 and end == 180.0) return true;
    const arc = positiveAdmAngle(end - start);
    const offset = positiveAdmAngle(value - start);
    return offset <= arc;
}

fn positiveAdmAngle(value: f64) f64 {
    var normalized = @mod(value, 360.0);
    if (normalized < 0.0) normalized += 360.0;
    return normalized;
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

fn zeroAdmTime() adm_time.Value {
    return .{
        .whole_seconds = 0,
        .fractional_numerator = 0,
        .fractional_denominator = 1,
        .format = .decimal,
    };
}

fn isDirectChild(parent_depth: usize, child_depth: usize) bool {
    return child_depth > parent_depth and child_depth - parent_depth == 1;
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte))
            return false;
    }
    return true;
}
