const std = @import("std");
const adm = @import("../adm.zig");
const common = @import("common.zig");
const xml = @import("../xml.zig");

const max_identifier_bytes = common.max_identifier_bytes;
const declarationSpec = common.declarationSpec;
const insideAfe = common.insideAfe;
const isXmlNamespaceDeclaration = common.isXmlNamespaceDeclaration;

pub const MetadataSource = struct {
    document: xml.Document,
    namespace_name: ?xml.NamespaceName,
};

pub const MetadataEventIterator = struct {
    events: xml.EventIterator,
    namespace_name: ?xml.NamespaceName,
    afe_depth: ?usize = null,

    pub fn init(source: MetadataSource) MetadataEventIterator {
        return .{
            .events = source.document.iterator(),
            .namespace_name = source.namespace_name,
        };
    }

    pub fn next(self: *MetadataEventIterator) !?xml.Event {
        while (try self.events.next()) |event| {
            switch (event) {
                .start => |element| {
                    const namespace_matches = try xml.namespaceNamesEql(
                        self.namespace_name,
                        element.namespace_name,
                    );
                    if (namespace_matches and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                    }
                    if (insideAfe(self.afe_depth, element.depth) and
                        !namespace_matches)
                    {
                        if (!element.self_closing)
                            try skipXmlSubtree(&self.events, element);
                        continue;
                    }
                    return event;
                },
                .end => |element| {
                    if (self.afe_depth == element.depth and
                        try xml.namespaceNamesEql(
                            self.namespace_name,
                            element.namespace_name,
                        ) and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        ))
                    {
                        self.afe_depth = null;
                    }
                    return event;
                },
                .text => return event,
            }
        }
        return null;
    }
};

fn skipXmlSubtree(
    events: *xml.EventIterator,
    start: xml.StartElement,
) !void {
    _ = try consumeXmlSubtree(events, start);
}

fn consumeXmlSubtree(
    events: *xml.EventIterator,
    start: xml.StartElement,
) !xml.EndElement {
    while (try events.next()) |event| {
        switch (event) {
            .end => |element| {
                if (element.depth == start.depth and
                    std.mem.eql(u8, element.name, start.name))
                {
                    return element;
                }
            },
            else => {},
        }
    }
    return error.UnclosedAdmExtension;
}

fn isTypedMetadataElementName(local_name: []const u8) bool {
    // New typed readers must add their element names to this inventory.
    const names = [_][]const u8{
        "alternativeValueSet",
        "alternativeValueSetIDRef",
        "audioBlockFormatBinaural",
        "audioBlockFormatDirectSpeakers",
        "audioBlockFormatHoa",
        "audioBlockFormatIDRef",
        "audioBlockFormatMatrix",
        "audioBlockFormatObjects",
        "audioChannelFormat",
        "audioChannelFormatIDRef",
        "audioComplementaryObjectGroupLabel",
        "audioComplementaryObjectIDRef",
        "audioContent",
        "audioContentIDRef",
        "audioContentLabel",
        "audioFormatExtended",
        "audioObject",
        "audioObjectIDRef",
        "audioObjectInteraction",
        "audioPackFormat",
        "audioPackFormatIDRef",
        "audioProgramme",
        "audioProgrammeIDRef",
        "audioProgrammeLabel",
        "audioStreamFormat",
        "audioStreamFormatIDRef",
        "audioTrack",
        "audioTrackFormat",
        "audioTrackFormatIDRef",
        "audioTrackUID",
        "audioTrackUIDRef",
        "cartesian",
        "channelLock",
        "coefficient",
        "decodePackFormatIDRef",
        "degree",
        "depth",
        "dialogue",
        "dialogueLoudness",
        "diffuse",
        "encodePackFormatIDRef",
        "equation",
        "frameFormat",
        "frameHeader",
        "frequency",
        "gain",
        "gainInteractionRange",
        "headLocked",
        "headphoneVirtualise",
        "height",
        "importance",
        "inputPackFormatIDRef",
        "integratedLoudness",
        "jumpPosition",
        "loudnessMetadata",
        "matrix",
        "nfcRefDist",
        "normalization",
        "objectDivergence",
        "order",
        "outputChannelFormatIDRef",
        "outputChannelIDRef",
        "outputPackFormatIDRef",
        "position",
        "positionInteractionRange",
        "positionOffset",
        "profile",
        "profileList",
        "screenRef",
        "speakerLabel",
        "tag",
        "tagGroup",
        "tagList",
        "transportTrackFormat",
        "width",
        "zone",
        "zoneExclusion",
    };
    for (names) |name| {
        if (std.mem.eql(u8, local_name, name)) return true;
    }
    return false;
}

fn extensionDeclarationOwner(
    element: xml.StartElement,
    storage: []u8,
) !?adm.Identifier {
    const spec = declarationSpec(element.localName()) orelse return null;
    const encoded = try element.attribute(spec.attribute_name) orelse
        return error.MissingAdmIdentifier;
    const raw = try xml.decodeContent(storage, encoded);
    const identifier = try adm.Identifier.parse(raw);
    if (identifier.kind != spec.kind)
        return error.InvalidAdmDeclarationKind;
    return identifier;
}

pub const Extension = struct {
    qualified_name: []const u8,
    namespace_uri: ?[]const u8,
    attributes: []const u8,
    source: []const u8,
    source_offset: usize,
    depth: usize,
    parent_element_name: []const u8,
    declaration_owner: ?adm.Identifier,

    pub fn localName(self: Extension) []const u8 {
        return xml.qualifiedLocalName(self.qualified_name);
    }
};

pub const UntypedElement = struct {
    qualified_name: []const u8,
    namespace_uri: ?[]const u8,
    attributes: []const u8,
    source: []const u8,
    source_offset: usize,
    depth: usize,
    parent_element_name: []const u8,
    declaration_owner: ?adm.Identifier,

    pub fn localName(self: UntypedElement) []const u8 {
        return xml.qualifiedLocalName(self.qualified_name);
    }
};

const MetadataElementRelation = enum {
    foreign,
    untyped,
};

fn MetadataElementIterator(comptime relation: MetadataElementRelation) type {
    const Result = switch (relation) {
        .foreign => Extension,
        .untyped => UntypedElement,
    };
    return struct {
        source: MetadataSource,
        events: xml.EventIterator,
        afe_depth: ?usize = null,
        element_names: [xml.max_depth]?[]const u8 = @splat(null),
        owners: [xml.max_depth]?adm.Identifier = @splat(null),
        owner_storage: [xml.max_depth][max_identifier_bytes]u8 = undefined,
        namespace_uri_storage: [xml.max_namespace_uri_bytes]u8 = undefined,

        const Self = @This();

        pub fn init(source: MetadataSource) Self {
            return .{
                .source = source,
                .events = source.document.iterator(),
            };
        }

        /// Returned namespace and owner identifier storage remain valid until
        /// the next iterator call.
        pub fn next(self: *Self) !?Result {
            const checkpoint = self.*;
            return self.nextInPlace() catch |err| {
                self.* = checkpoint;
                return err;
            };
        }

        fn nextInPlace(self: *Self) !?Result {
            while (try self.events.next()) |event| {
                switch (event) {
                    .start => |element| {
                        const inherited_owner = if (element.depth == 0)
                            null
                        else
                            self.owners[element.depth - 1];
                        self.owners[element.depth] = inherited_owner;
                        self.element_names[element.depth] = null;

                        const namespace_matches = try xml.namespaceNamesEql(
                            self.source.namespace_name,
                            element.namespace_name,
                        );
                        if (namespace_matches and
                            std.mem.eql(
                                u8,
                                element.localName(),
                                "audioFormatExtended",
                            ))
                        {
                            self.afe_depth = if (element.self_closing)
                                null
                            else
                                element.depth;
                            self.element_names[element.depth] =
                                element.localName();
                            self.owners[element.depth] = null;
                            continue;
                        }
                        if (!insideAfe(self.afe_depth, element.depth))
                            continue;

                        const typed = namespace_matches and
                            isTypedMetadataElementName(element.localName());
                        const target = switch (relation) {
                            .foreign => !namespace_matches,
                            .untyped => namespace_matches and !typed,
                        };
                        if (target) return try self.readElement(element);
                        if (!typed) {
                            if (!element.self_closing)
                                try skipXmlSubtree(&self.events, element);
                            continue;
                        }

                        self.element_names[element.depth] =
                            element.localName();
                        if (try extensionDeclarationOwner(
                            element,
                            &self.owner_storage[element.depth],
                        )) |identifier| {
                            self.owners[element.depth] = identifier;
                        }
                    },
                    .end => |element| {
                        if (self.afe_depth == element.depth and
                            try xml.namespaceNamesEql(
                                self.source.namespace_name,
                                element.namespace_name,
                            ) and
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

        fn readElement(
            self: *Self,
            element: xml.StartElement,
        ) !Result {
            const parent_element_name = if (element.depth == 0)
                null
            else
                self.element_names[element.depth - 1];
            const parent = parent_element_name orelse switch (relation) {
                .foreign => return error.InvalidAdmExtensionOwner,
                .untyped => return error.InvalidAdmUntypedElementOwner,
            };
            const source_end = if (element.self_closing)
                element.source_end
            else
                (try consumeXmlSubtree(&self.events, element)).source_end;
            const namespace_uri =
                if (element.namespace_name) |namespace_name|
                    try xml.decodeContent(
                        &self.namespace_uri_storage,
                        namespace_name.encoded,
                    )
                else
                    null;
            return .{
                .qualified_name = element.name,
                .namespace_uri = namespace_uri,
                .attributes = element.attributes,
                .source = self.source.document.bytes[element.source_start..source_end],
                .source_offset = element.source_start,
                .depth = element.depth,
                .parent_element_name = parent,
                .declaration_owner = self.owners[element.depth],
            };
        }
    };
}

pub const ExtensionIterator = MetadataElementIterator(.foreign);
pub const UntypedElementIterator = MetadataElementIterator(.untyped);

pub const ExtensionAttribute = struct {
    qualified_name: []const u8,
    namespace_uri: []const u8,
    encoded_value: []const u8,
    source: []const u8,
    element_name: []const u8,
    declaration_owner: ?adm.Identifier,

    pub fn localName(self: ExtensionAttribute) []const u8 {
        return xml.qualifiedLocalName(self.qualified_name);
    }

    pub fn decodeValue(
        self: ExtensionAttribute,
        destination: []u8,
    ) ![]const u8 {
        return xml.decodeContent(destination, self.encoded_value);
    }
};

const MetadataAttributeRelation = enum {
    foreign,
    metadata,
};

const MetadataAttributeIterator = struct {
    source: MetadataSource,
    events: xml.EventIterator,
    afe_depth: ?usize = null,
    owners: [xml.max_depth]?adm.Identifier = @splat(null),
    owner_storage: [xml.max_depth][max_identifier_bytes]u8 = undefined,
    namespace_uri_storage: [xml.max_namespace_uri_bytes]u8 = undefined,
    current_element: ?xml.StartElement = null,
    attributes: xml.AttributeIterator = xml.AttributeIterator.init(""),

    fn init(source: MetadataSource) MetadataAttributeIterator {
        return .{
            .source = source,
            .events = source.document.iterator(),
        };
    }

    /// Returned namespace and owner identifier storage remain valid until
    /// the next iterator call.
    fn next(
        self: *MetadataAttributeIterator,
        relation: MetadataAttributeRelation,
    ) !?ExtensionAttribute {
        while (true) {
            if (self.current_element) |element| {
                while (try self.attributes.next()) |attribute| {
                    if (isXmlNamespaceDeclaration(attribute.name) or
                        std.mem.indexOfScalar(
                            u8,
                            attribute.name,
                            ':',
                        ) == null)
                    {
                        continue;
                    }
                    const namespace_name =
                        (try self.events.attributeNamespaceName(
                            element,
                            attribute,
                        )) orelse return error.InvalidAdmExtensionNamespace;
                    const namespace_matches = try xml.namespaceNamesEql(
                        self.source.namespace_name,
                        namespace_name,
                    );
                    if ((relation == .foreign and namespace_matches) or
                        (relation == .metadata and !namespace_matches))
                    {
                        continue;
                    }
                    const namespace_uri = try xml.decodeContent(
                        &self.namespace_uri_storage,
                        namespace_name.encoded,
                    );
                    return .{
                        .qualified_name = attribute.name,
                        .namespace_uri = namespace_uri,
                        .encoded_value = attribute.value,
                        .source = attribute.source,
                        .element_name = element.localName(),
                        .declaration_owner = self.owners[element.depth],
                    };
                }
                self.current_element = null;
            }

            const event = (try self.events.next()) orelse return null;
            switch (event) {
                .start => |element| {
                    const inherited_owner = if (element.depth == 0)
                        null
                    else
                        self.owners[element.depth - 1];
                    self.owners[element.depth] = inherited_owner;
                    const namespace_matches = try xml.namespaceNamesEql(
                        self.source.namespace_name,
                        element.namespace_name,
                    );
                    const is_afe = namespace_matches and
                        std.mem.eql(
                            u8,
                            element.localName(),
                            "audioFormatExtended",
                        );
                    if (is_afe) {
                        self.afe_depth = if (element.self_closing)
                            null
                        else
                            element.depth;
                        self.owners[element.depth] = null;
                    } else if (!insideAfe(
                        self.afe_depth,
                        element.depth,
                    )) {
                        continue;
                    } else if (!namespace_matches) {
                        if (!element.self_closing)
                            try skipXmlSubtree(&self.events, element);
                        continue;
                    } else if (!isTypedMetadataElementName(
                        element.localName(),
                    )) {
                        if (!element.self_closing)
                            try skipXmlSubtree(&self.events, element);
                        continue;
                    } else if (try extensionDeclarationOwner(
                        element,
                        &self.owner_storage[element.depth],
                    )) |identifier| {
                        self.owners[element.depth] = identifier;
                    }
                    self.current_element = element;
                    self.attributes =
                        xml.AttributeIterator.init(element.attributes);
                },
                .end => |element| {
                    if (self.afe_depth == element.depth and
                        try xml.namespaceNamesEql(
                            self.source.namespace_name,
                            element.namespace_name,
                        ) and
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
    }
};

pub const ExtensionAttributeIterator = struct {
    iterator: MetadataAttributeIterator,

    pub fn init(source: MetadataSource) ExtensionAttributeIterator {
        return .{ .iterator = MetadataAttributeIterator.init(source) };
    }

    pub fn next(
        self: *ExtensionAttributeIterator,
    ) !?ExtensionAttribute {
        const checkpoint = self.*;
        return self.iterator.next(.foreign) catch |err| {
            self.* = checkpoint;
            return err;
        };
    }
};

pub const UntypedAttribute = ExtensionAttribute;

pub const UntypedAttributeIterator = struct {
    iterator: MetadataAttributeIterator,

    pub fn init(source: MetadataSource) UntypedAttributeIterator {
        return .{ .iterator = MetadataAttributeIterator.init(source) };
    }

    pub fn next(
        self: *UntypedAttributeIterator,
    ) !?UntypedAttribute {
        const checkpoint = self.*;
        return self.iterator.next(.metadata) catch |err| {
            self.* = checkpoint;
            return err;
        };
    }
};
