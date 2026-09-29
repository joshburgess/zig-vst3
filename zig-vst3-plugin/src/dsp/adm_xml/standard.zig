const std = @import("std");
const adm = @import("../adm.zig");
const common = @import("common.zig");
const emission = @import("emission.zig");
const metadata = @import("metadata.zig");
const model = @import("model.zig");
const xml = @import("../xml.zig");

const declarationSpec = common.declarationSpec;
const insideAfe = common.insideAfe;
const max_identifier_bytes = common.max_identifier_bytes;
const max_profile_text_bytes = common.max_profile_text_bytes;
const validateEmissionAttributes = emission.validateEmissionAttributes;
const MetadataSource = metadata.MetadataSource;
const MetadataEventIterator = metadata.MetadataEventIterator;
const Profile = emission.Profile;
const TagItem = model.TagItem;

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

pub const ProfileIterator = struct {
    const Scope = enum {
        audio_format_extended,
        serial_frame_header,

        fn elementName(self: Scope) []const u8 {
            return switch (self) {
                .audio_format_extended => "audioFormatExtended",
                .serial_frame_header => "frameHeader",
            };
        }
    };

    events: MetadataEventIterator,
    scope: Scope = .audio_format_extended,
    owner_depth: ?usize = null,
    profile_list_depth: ?usize = null,
    profile_list_seen: bool = false,
    profiles_in_list: usize = 0,
    name_storage: [max_profile_text_bytes]u8 = undefined,
    version_storage: [max_profile_text_bytes]u8 = undefined,
    level_storage: [max_profile_text_bytes]u8 = undefined,
    reference_storage: [max_profile_text_bytes]u8 = undefined,

    pub fn init(source: MetadataSource) ProfileIterator {
        return .{ .events = MetadataEventIterator.init(source) };
    }

    pub fn initSerialHeader(source: MetadataSource) ProfileIterator {
        return .{
            .events = MetadataEventIterator.init(source),
            .scope = .serial_frame_header,
        };
    }

    /// Returned fields remain valid until the next iterator call.
    pub fn next(self: *ProfileIterator) !?Profile {
        const checkpoint = self.*;
        return self.nextInPlace() catch |err| {
            self.* = checkpoint;
            return err;
        };
    }

    fn nextInPlace(self: *ProfileIterator) !?Profile {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (std.mem.eql(
                        u8,
                        element.localName(),
                        self.scope.elementName(),
                    )) {
                        self.owner_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        continue;
                    }
                    const owner_depth = self.owner_depth orelse continue;
                    if (element.depth <= owner_depth) continue;
                    if (std.mem.eql(u8, element.localName(), "profileList")) {
                        if (!isDirectChild(owner_depth, element.depth))
                            return error.InvalidAdmProfileListOwner;
                        if (self.profile_list_seen)
                            return error.MultipleAdmProfileLists;
                        if (self.scope == .serial_frame_header) {
                            try validateEmissionAttributes(
                                element,
                                &.{},
                                error.InvalidAdmEmissionProfileSerialProfileListAttribute,
                            );
                        }
                        if (element.self_closing)
                            return error.EmptyAdmProfileList;
                        self.profile_list_seen = true;
                        self.profile_list_depth = element.depth;
                        self.profiles_in_list = 0;
                        continue;
                    }
                    if (!std.mem.eql(u8, element.localName(), "profile")) {
                        if (self.scope == .serial_frame_header and
                            self.profile_list_depth != null)
                        {
                            return error.InvalidAdmEmissionProfileSerialProfileListSubelement;
                        }
                        continue;
                    }
                    const list_depth = self.profile_list_depth orelse
                        return error.InvalidAdmProfileOwner;
                    if (!isDirectChild(list_depth, element.depth))
                        return error.InvalidAdmProfileOwner;
                    if (self.scope == .serial_frame_header) {
                        try validateEmissionAttributes(
                            element,
                            &.{ "profileName", "profileVersion", "profileLevel" },
                            error.InvalidAdmEmissionProfileSerialProfileAttribute,
                        );
                    }
                    if (element.self_closing)
                        return error.EmptyAdmProfileReference;
                    const profile = try self.readProfile(element);
                    self.profiles_in_list = std.math.add(
                        usize,
                        self.profiles_in_list,
                        1,
                    ) catch return error.InvalidAdmProfileIteratorState;
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
                    if (self.owner_depth == element.depth and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            self.scope.elementName(),
                        ))
                    {
                        self.owner_depth = null;
                    }
                },
                .text => |text| {
                    if (self.scope == .serial_frame_header and
                        self.profile_list_depth != null and
                        std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    {
                        return error.InvalidAdmEmissionProfileSerialProfileListText;
                    }
                },
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
                    encoded_bytes = xml.appendEncodedText(
                        &encoded_reference,
                        encoded_bytes,
                        text,
                    ) catch return error.AdmProfileValueTooLong;
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
    events: MetadataEventIterator,
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

    pub fn init(source: MetadataSource) TagIterator {
        return .{ .events = MetadataEventIterator.init(source) };
    }

    /// Returned text and identifiers remain valid until the next iterator call.
    pub fn next(self: *TagIterator) !?TagItem {
        const checkpoint = self.*;
        return self.nextInPlace() catch |err| {
            self.* = checkpoint;
            return err;
        };
    }

    fn nextInPlace(self: *TagIterator) !?TagItem {
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
                        if (!isDirectChild(afe_depth, element.depth))
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
                        if (!isDirectChild(list_depth, element.depth) or
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
                        if (!isDirectChild(depth, element.depth))
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
                        self.tags_in_group = std.math.add(
                            usize,
                            self.tags_in_group,
                            1,
                        ) catch return error.InvalidAdmTagIteratorState;
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
                    if (!isDirectChild(depth, element.depth))
                        return error.InvalidAdmTagTargetOwner;
                    const raw = try self.readText(element);
                    const identifier = try adm.Identifier.parse(raw);
                    if (identifier.kind != target_kind)
                        return error.InvalidAdmTagTargetKind;
                    @memcpy(
                        self.identifier_storage[0..raw.len],
                        raw,
                    );
                    self.targets_in_group = std.math.add(
                        usize,
                        self.targets_in_group,
                        1,
                    ) catch return error.InvalidAdmTagIteratorState;
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
                        self.group_count = std.math.add(
                            usize,
                            self.group_count,
                            1,
                        ) catch return error.InvalidAdmTagIteratorState;
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
                    encoded_bytes = xml.appendEncodedText(
                        &encoded_storage,
                        encoded_bytes,
                        text,
                    ) catch return error.AdmTagValueTooLong;
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

pub const DeclarationIterator = struct {
    events: MetadataEventIterator,
    afe_depth: ?usize = null,
    identifier_storage: [max_identifier_bytes]u8 = undefined,

    pub fn init(source: MetadataSource) DeclarationIterator {
        return .{ .events = MetadataEventIterator.init(source) };
    }

    /// The returned identifier remains valid until the next iterator call.
    pub fn next(self: *DeclarationIterator) !?Declaration {
        const checkpoint = self.*;
        return self.nextInPlace() catch |err| {
            self.* = checkpoint;
            return err;
        };
    }

    fn nextInPlace(self: *DeclarationIterator) !?Declaration {
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
    events: MetadataEventIterator,
    afe_depth: ?usize = null,
    tag_group_depth: ?usize = null,
    owners: [xml.max_depth]?adm.Identifier = @splat(null),
    owner_depths: [xml.max_depth]?usize = @splat(null),
    owner_storage: [xml.max_depth][max_identifier_bytes]u8 = undefined,
    identifier_storage: [max_identifier_bytes]u8 = undefined,

    pub fn init(source: MetadataSource) ReferenceIterator {
        return .{ .events = MetadataEventIterator.init(source) };
    }

    /// Returned identifiers remain valid until the next iterator call.
    pub fn next(self: *ReferenceIterator) !?Reference {
        const checkpoint = self.*;
        return self.nextInPlace() catch |err| {
            self.* = checkpoint;
            return err;
        };
    }

    fn nextInPlace(self: *ReferenceIterator) !?Reference {
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
                    encoded_bytes = xml.appendEncodedText(
                        &encoded_storage,
                        encoded_bytes,
                        text,
                    ) catch return error.AdmIdentifierTooLong;
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

fn isDirectChild(parent_depth: usize, child_depth: usize) bool {
    return child_depth > parent_depth and child_depth - parent_depth == 1;
}

fn directOwner(owner_depth: ?usize, reference_depth: usize) bool {
    const depth = owner_depth orelse return false;
    return isDirectChild(depth, reference_depth);
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte))
            return false;
    }
    return true;
}
