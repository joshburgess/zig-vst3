const std = @import("std");

pub const max_depth: usize = 64;
pub const max_namespace_uri_bytes: usize = 2048;
pub const xml_namespace_uri = "http://www.w3.org/XML/1998/namespace";
pub const xmlns_namespace_uri = "http://www.w3.org/2000/xmlns/";

pub const Document = struct {
    bytes: []const u8,

    pub fn init(bytes: []const u8) !Document {
        if (bytes.len == 0) return error.EmptyXmlDocument;
        if (!std.unicode.utf8ValidateSlice(bytes))
            return error.InvalidXmlEncoding;
        if (std.mem.indexOfScalar(u8, bytes, 0) != null)
            return error.XmlDocumentContainsNul;

        var events = EventIterator.init(bytes);
        var root_seen = false;
        var root_closed = false;
        while (try events.next()) |event| {
            switch (event) {
                .start => |element| {
                    if (element.depth == 0) {
                        if (root_seen or root_closed)
                            return error.MultipleXmlRoots;
                        root_seen = true;
                        if (element.self_closing) root_closed = true;
                    } else if (root_closed) {
                        return error.MultipleXmlRoots;
                    }
                },
                .end => |element| {
                    if (element.depth == 0) root_closed = true;
                },
                .text => |text| {
                    if ((!root_seen or root_closed) and
                        std.mem.trim(u8, text.bytes, " \t\r\n").len != 0)
                    {
                        return error.XmlTextOutsideRoot;
                    }
                },
            }
        }
        if (!root_seen or !root_closed) return error.InvalidXmlDocument;
        return .{ .bytes = bytes };
    }

    pub fn iterator(self: Document) EventIterator {
        return EventIterator.init(self.bytes);
    }
};

pub const Event = union(enum) {
    start: StartElement,
    end: EndElement,
    text: Text,
};

pub const NamespaceName = struct {
    encoded: []const u8,

    pub fn eql(self: NamespaceName, other: NamespaceName) !bool {
        return encodedContentEql(self.encoded, other.encoded);
    }

    pub fn eqlBytes(self: NamespaceName, decoded: []const u8) !bool {
        return encodedContentEql(self.encoded, decoded);
    }
};

pub fn namespaceNamesEql(
    left: ?NamespaceName,
    right: ?NamespaceName,
) !bool {
    if (left) |left_name| {
        const right_name = right orelse return false;
        return left_name.eql(right_name);
    }
    return right == null;
}

pub const StartElement = struct {
    name: []const u8,
    attributes: []const u8,
    depth: usize,
    self_closing: bool,
    namespace_name: ?NamespaceName,

    pub fn localName(self: StartElement) []const u8 {
        return qualifiedLocalName(self.name);
    }

    pub fn attribute(self: StartElement, wanted_name: []const u8) !?[]const u8 {
        var iterator = AttributeIterator.init(self.attributes);
        while (try iterator.next()) |attribute_value| {
            if (std.mem.eql(u8, attribute_value.name, wanted_name))
                return attribute_value.value;
        }
        return null;
    }

    pub fn namespaceDeclaration(
        self: StartElement,
        prefix: []const u8,
    ) !?NamespaceName {
        var iterator = AttributeIterator.init(self.attributes);
        while (try iterator.next()) |attribute_value| {
            if (prefix.len == 0) {
                if (std.mem.eql(u8, attribute_value.name, "xmlns"))
                    return .{ .encoded = attribute_value.value };
                continue;
            }
            if (!std.mem.startsWith(
                u8,
                attribute_value.name,
                "xmlns:",
            )) {
                continue;
            }
            if (std.mem.eql(u8, attribute_value.name[6..], prefix))
                return .{ .encoded = attribute_value.value };
        }
        return null;
    }
};

pub const EndElement = struct {
    name: []const u8,
    depth: usize,
    namespace_name: ?NamespaceName,

    pub fn localName(self: EndElement) []const u8 {
        return qualifiedLocalName(self.name);
    }
};

pub const Text = struct {
    bytes: []const u8,
    depth: usize,
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,

    pub fn localName(self: Attribute) []const u8 {
        return qualifiedLocalName(self.name);
    }
};

pub const AttributeIterator = struct {
    bytes: []const u8,
    offset: usize = 0,

    pub fn init(bytes: []const u8) AttributeIterator {
        return .{ .bytes = bytes };
    }

    pub fn next(self: *AttributeIterator) !?Attribute {
        self.skipWhitespace();
        if (self.offset == self.bytes.len) return null;

        const name_start = self.offset;
        self.offset = try scanName(self.bytes, self.offset);
        const name = self.bytes[name_start..self.offset];
        self.skipWhitespace();
        if (self.offset == self.bytes.len or self.bytes[self.offset] != '=')
            return error.InvalidXmlAttribute;
        self.offset += 1;
        self.skipWhitespace();
        if (self.offset == self.bytes.len or
            (self.bytes[self.offset] != '"' and
                self.bytes[self.offset] != '\''))
        {
            return error.InvalidXmlAttribute;
        }
        const quote = self.bytes[self.offset];
        self.offset += 1;
        const value_start = self.offset;
        while (self.offset < self.bytes.len and
            self.bytes[self.offset] != quote)
        {
            if (self.bytes[self.offset] == '<')
                return error.InvalidXmlAttribute;
            self.offset += 1;
        }
        if (self.offset == self.bytes.len)
            return error.InvalidXmlAttribute;
        const value = self.bytes[value_start..self.offset];
        try validateXmlContent(value);
        self.offset += 1;
        return .{ .name = name, .value = value };
    }

    fn skipWhitespace(self: *AttributeIterator) void {
        while (self.offset < self.bytes.len and
            std.ascii.isWhitespace(self.bytes[self.offset]))
        {
            self.offset += 1;
        }
    }
};

pub const EventIterator = struct {
    bytes: []const u8,
    offset: usize,
    elements: [max_depth]StartElement = undefined,
    depth: usize = 0,

    pub fn init(bytes: []const u8) EventIterator {
        return .{
            .bytes = bytes,
            .offset = if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf"))
                3
            else
                0,
        };
    }

    pub fn next(self: *EventIterator) !?Event {
        while (self.offset < self.bytes.len) {
            if (self.bytes[self.offset] != '<')
                return @as(?Event, try self.readText());
            if (std.mem.startsWith(u8, self.bytes[self.offset..], "<!--")) {
                try self.skipComment();
                continue;
            }
            if (std.mem.startsWith(u8, self.bytes[self.offset..], "<?")) {
                try self.skipProcessingInstruction();
                continue;
            }
            if (std.mem.startsWith(u8, self.bytes[self.offset..], "<!"))
                return error.UnsupportedXmlDeclaration;
            if (std.mem.startsWith(u8, self.bytes[self.offset..], "</"))
                return @as(?Event, try self.readEnd());
            return @as(?Event, try self.readStart());
        }
        if (self.depth != 0) return error.UnclosedXmlElement;
        return null;
    }

    fn readText(self: *EventIterator) !Event {
        const start = self.offset;
        self.offset = std.mem.indexOfScalarPos(
            u8,
            self.bytes,
            self.offset,
            '<',
        ) orelse self.bytes.len;
        const bytes = self.bytes[start..self.offset];
        try validateXmlContent(bytes);
        return .{ .text = .{ .bytes = bytes, .depth = self.depth } };
    }

    fn readStart(self: *EventIterator) !Event {
        const name_start = self.offset + 1;
        const name_end = try scanName(self.bytes, name_start);
        const name = self.bytes[name_start..name_end];
        const closing = try findTagClose(self.bytes, name_end);
        var attributes = std.mem.trim(
            u8,
            self.bytes[name_end..closing],
            " \t\r\n",
        );
        const self_closing =
            attributes.len != 0 and attributes[attributes.len - 1] == '/';
        if (self_closing) {
            attributes = std.mem.trimEnd(
                u8,
                attributes[0 .. attributes.len - 1],
                " \t\r\n",
            );
        }
        const element_depth = self.depth;
        var element = StartElement{
            .name = name,
            .attributes = attributes,
            .depth = element_depth,
            .self_closing = self_closing,
            .namespace_name = null,
        };
        try validateAttributes(attributes);
        try self.validateNamespaceDeclarations(element);
        element.namespace_name = try self.resolveElementNamespace(element);
        try self.validateAttributeNamespaces(element);
        if (!self_closing) {
            if (self.depth == max_depth) return error.XmlNestingTooDeep;
            self.elements[self.depth] = element;
            self.depth += 1;
        }
        self.offset = closing + 1;
        return .{ .start = element };
    }

    fn readEnd(self: *EventIterator) !Event {
        const name_start = self.offset + 2;
        const name_end = try scanName(self.bytes, name_start);
        var cursor = name_end;
        while (cursor < self.bytes.len and
            std.ascii.isWhitespace(self.bytes[cursor]))
        {
            cursor += 1;
        }
        if (cursor == self.bytes.len or self.bytes[cursor] != '>')
            return error.InvalidXmlEndElement;
        if (self.depth == 0) return error.UnexpectedXmlEndElement;
        const name = self.bytes[name_start..name_end];
        try validateQualifiedName(name);
        const start = self.elements[self.depth - 1];
        if (!std.mem.eql(u8, name, start.name))
            return error.MismatchedXmlElement;
        self.depth -= 1;
        self.offset = cursor + 1;
        return .{ .end = .{
            .name = name,
            .depth = self.depth,
            .namespace_name = start.namespace_name,
        } };
    }

    fn validateNamespaceDeclarations(
        self: *const EventIterator,
        element: StartElement,
    ) !void {
        try validateQualifiedName(element.name);
        const element_prefix = qualifiedPrefix(element.name);
        if (element_prefix) |prefix| {
            if (std.mem.eql(u8, prefix, "xmlns"))
                return error.ReservedXmlNamespacePrefix;
        }

        var attributes = AttributeIterator.init(element.attributes);
        while (try attributes.next()) |attribute| {
            try validateQualifiedName(attribute.name);
            if (!isNamespaceDeclaration(attribute.name)) continue;
            const namespace_name = NamespaceName{
                .encoded = attribute.value,
            };
            try validateNamespaceUri(namespace_name);
            const prefix = namespaceDeclarationPrefix(attribute.name);
            if (prefix) |declared_prefix| {
                if (declared_prefix.len == 0)
                    return error.InvalidXmlQualifiedName;
                if (namespace_name.encoded.len == 0)
                    return error.EmptyXmlPrefixedNamespace;
                if (std.mem.eql(u8, declared_prefix, "xmlns"))
                    return error.ReservedXmlNamespacePrefix;
                if (std.mem.eql(u8, declared_prefix, "xml")) {
                    if (!try namespace_name.eqlBytes(xml_namespace_uri))
                        return error.InvalidXmlNamespaceBinding;
                } else if (try namespace_name.eqlBytes(xml_namespace_uri)) {
                    return error.InvalidXmlNamespaceBinding;
                }
            } else if (try namespace_name.eqlBytes(xml_namespace_uri)) {
                return error.InvalidXmlNamespaceBinding;
            }
            if (try namespace_name.eqlBytes(xmlns_namespace_uri))
                return error.InvalidXmlNamespaceBinding;
        }
        _ = self;
    }

    fn resolveElementNamespace(
        self: *const EventIterator,
        element: StartElement,
    ) !?NamespaceName {
        const prefix = qualifiedPrefix(element.name);
        if (prefix) |value| return self.resolvePrefix(element, value);
        const default_name = try self.resolvePrefix(element, "");
        if (default_name) |name| {
            if (name.encoded.len == 0) return null;
        }
        return default_name;
    }

    fn validateAttributeNamespaces(
        self: *const EventIterator,
        element: StartElement,
    ) !void {
        var attributes = AttributeIterator.init(element.attributes);
        var attribute_index: usize = 0;
        while (try attributes.next()) |attribute| : (attribute_index += 1) {
            if (isNamespaceDeclaration(attribute.name)) continue;
            const namespace_name = try self.attributeNamespace(
                element,
                attribute,
            );
            var previous = AttributeIterator.init(element.attributes);
            var previous_index: usize = 0;
            while (previous_index < attribute_index) : (previous_index += 1) {
                const prior = (try previous.next()) orelse
                    return error.InvalidXmlAttribute;
                if (isNamespaceDeclaration(prior.name)) continue;
                if (!std.mem.eql(
                    u8,
                    prior.localName(),
                    attribute.localName(),
                )) {
                    continue;
                }
                const prior_namespace = try self.attributeNamespace(
                    element,
                    prior,
                );
                if (try namespaceNamesEql(
                    prior_namespace,
                    namespace_name,
                )) {
                    return error.DuplicateXmlExpandedAttribute;
                }
            }
        }
    }

    fn attributeNamespace(
        self: *const EventIterator,
        element: StartElement,
        attribute: Attribute,
    ) !?NamespaceName {
        const prefix = qualifiedPrefix(attribute.name) orelse return null;
        if (std.mem.eql(u8, prefix, "xml"))
            return .{ .encoded = xml_namespace_uri };
        return self.resolvePrefix(element, prefix);
    }

    fn resolvePrefix(
        self: *const EventIterator,
        element: StartElement,
        prefix: []const u8,
    ) !?NamespaceName {
        if (std.mem.eql(u8, prefix, "xml"))
            return .{ .encoded = xml_namespace_uri };
        if (try element.namespaceDeclaration(prefix)) |binding|
            return binding;
        var ancestor_count = self.depth;
        while (ancestor_count != 0) {
            ancestor_count -= 1;
            if (try self.elements[ancestor_count]
                .namespaceDeclaration(prefix)) |binding|
            {
                return binding;
            }
        }
        if (prefix.len == 0) return null;
        return error.UndeclaredXmlNamespacePrefix;
    }

    fn skipComment(self: *EventIterator) !void {
        const content_start = self.offset + 4;
        const relative_end = std.mem.indexOf(
            u8,
            self.bytes[content_start..],
            "-->",
        ) orelse return error.UnclosedXmlComment;
        const content = self.bytes[content_start .. content_start + relative_end];
        if (std.mem.indexOf(u8, content, "--") != null or
            (content.len != 0 and content[content.len - 1] == '-'))
        {
            return error.InvalidXmlComment;
        }
        try validateXmlCharacters(content);
        self.offset = content_start + relative_end + 3;
    }

    fn skipProcessingInstruction(self: *EventIterator) !void {
        const content_start = self.offset + 2;
        const relative_end = std.mem.indexOf(
            u8,
            self.bytes[content_start..],
            "?>",
        ) orelse return error.UnclosedXmlProcessingInstruction;
        const content = self.bytes[content_start .. content_start + relative_end];
        if (std.mem.trim(u8, content, " \t\r\n").len == 0)
            return error.InvalidXmlProcessingInstruction;
        try validateXmlCharacters(content);
        self.offset = content_start + relative_end + 2;
    }
};

pub fn qualifiedLocalName(qualified_name: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, qualified_name, ':') orelse
        return qualified_name;
    return qualified_name[separator + 1 ..];
}

fn qualifiedPrefix(qualified_name: []const u8) ?[]const u8 {
    const separator = std.mem.indexOfScalar(u8, qualified_name, ':') orelse
        return null;
    return qualified_name[0..separator];
}

fn validateQualifiedName(name: []const u8) !void {
    const first = std.mem.indexOfScalar(u8, name, ':') orelse {
        try validateNamespaceComponent(name);
        return;
    };
    if (first == 0 or first + 1 == name.len)
        return error.InvalidXmlQualifiedName;
    if (std.mem.indexOfScalarPos(u8, name, first + 1, ':') != null)
        return error.InvalidXmlQualifiedName;
    try validateNamespaceComponent(name[0..first]);
    try validateNamespaceComponent(name[first + 1 ..]);
}

fn validateNamespaceComponent(name: []const u8) !void {
    if (name.len == 0 or !isNameStartByte(name[0]) or name[0] == ':')
        return error.InvalidXmlQualifiedName;
    for (name[1..]) |byte| {
        if (!isNameByte(byte) or byte == ':')
            return error.InvalidXmlQualifiedName;
    }
}

fn isNamespaceDeclaration(name: []const u8) bool {
    return std.mem.eql(u8, name, "xmlns") or
        std.mem.startsWith(u8, name, "xmlns:");
}

fn namespaceDeclarationPrefix(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "xmlns")) return null;
    return name[6..];
}

pub fn decodedContentBytes(encoded: []const u8) !usize {
    try validateXmlContent(encoded);
    var required: usize = 0;
    var offset: usize = 0;
    while (offset < encoded.len) {
        if (encoded[offset] != '&') {
            const length = std.unicode.utf8ByteSequenceLength(
                encoded[offset],
            ) catch return error.InvalidXmlEncoding;
            required = std.math.add(usize, required, length) catch
                return error.XmlDecodedSizeOverflow;
            offset += length;
            continue;
        }
        const entity = try parseEntity(encoded, offset);
        required = std.math.add(
            usize,
            required,
            std.unicode.utf8CodepointSequenceLength(entity.codepoint) catch
                return error.InvalidXmlEntity,
        ) catch return error.XmlDecodedSizeOverflow;
        offset = entity.end;
    }
    return required;
}

pub fn decodeContent(destination: []u8, encoded: []const u8) ![]const u8 {
    const required = try decodedContentBytes(encoded);
    if (destination.len < required) return error.XmlDecodeBufferTooSmall;
    var source_offset: usize = 0;
    var destination_offset: usize = 0;
    while (source_offset < encoded.len) {
        if (encoded[source_offset] != '&') {
            const length = try std.unicode.utf8ByteSequenceLength(
                encoded[source_offset],
            );
            @memcpy(
                destination[destination_offset..][0..length],
                encoded[source_offset..][0..length],
            );
            source_offset += length;
            destination_offset += length;
            continue;
        }
        const entity = try parseEntity(encoded, source_offset);
        var storage: [4]u8 = undefined;
        const length = try std.unicode.utf8Encode(
            entity.codepoint,
            &storage,
        );
        @memcpy(
            destination[destination_offset..][0..length],
            storage[0..length],
        );
        destination_offset += length;
        source_offset = entity.end;
    }
    return destination[0..required];
}

fn encodedContentEql(left: []const u8, right: []const u8) !bool {
    var left_offset: usize = 0;
    var right_offset: usize = 0;
    while (true) {
        const left_codepoint = try nextEncodedCodepoint(
            left,
            &left_offset,
        );
        const right_codepoint = try nextEncodedCodepoint(
            right,
            &right_offset,
        );
        if (left_codepoint == null or right_codepoint == null)
            return left_codepoint == null and right_codepoint == null;
        if (left_codepoint.? != right_codepoint.?) return false;
    }
}

fn validateNamespaceUri(namespace_name: NamespaceName) !void {
    var storage: [max_namespace_uri_bytes]u8 = undefined;
    const decoded = decodeContent(
        &storage,
        namespace_name.encoded,
    ) catch |err| switch (err) {
        error.XmlDecodeBufferTooSmall => return error.XmlNamespaceUriTooLong,
        else => return err,
    };
    if (decoded.len == 0) return;
    _ = std.Uri.parse(decoded) catch {
        _ = std.Uri.parseAfterScheme("", decoded) catch
            return error.InvalidXmlNamespaceUri;
    };

    var offset: usize = 0;
    var fragment_seen = false;
    while (try nextEncodedCodepoint(
        namespace_name.encoded,
        &offset,
    )) |codepoint| {
        if (codepoint == '#') {
            if (fragment_seen) return error.InvalidXmlNamespaceUri;
            fragment_seen = true;
        }
        if (codepoint == '%') {
            const high = (try nextEncodedCodepoint(
                namespace_name.encoded,
                &offset,
            )) orelse return error.InvalidXmlNamespaceUri;
            const low = (try nextEncodedCodepoint(
                namespace_name.encoded,
                &offset,
            )) orelse return error.InvalidXmlNamespaceUri;
            if (high > 0x7f or low > 0x7f or
                !std.ascii.isHex(@intCast(high)) or
                !std.ascii.isHex(@intCast(low)))
            {
                return error.InvalidXmlNamespaceUri;
            }
            continue;
        }
        if (codepoint > 0x7f or
            (!std.ascii.isAlphanumeric(@intCast(codepoint)) and
                std.mem.indexOfScalar(
                    u8,
                    "-._~:/?#[]@!$&'()*+,;=",
                    @intCast(codepoint),
                ) == null))
        {
            return error.InvalidXmlNamespaceUri;
        }
    }
}

fn nextEncodedCodepoint(
    encoded: []const u8,
    offset: *usize,
) !?u21 {
    if (offset.* == encoded.len) return null;
    if (encoded[offset.*] == '&') {
        const entity = try parseEntity(encoded, offset.*);
        offset.* = entity.end;
        return entity.codepoint;
    }
    const length = std.unicode.utf8ByteSequenceLength(
        encoded[offset.*],
    ) catch return error.InvalidXmlEncoding;
    const end = std.math.add(usize, offset.*, length) catch
        return error.InvalidXmlEncoding;
    if (end > encoded.len) return error.InvalidXmlEncoding;
    const codepoint = std.unicode.utf8Decode(
        encoded[offset.*..end],
    ) catch return error.InvalidXmlEncoding;
    offset.* = end;
    return codepoint;
}

fn validateAttributes(bytes: []const u8) !void {
    var iterator = AttributeIterator.init(bytes);
    var count: usize = 0;
    while (try iterator.next()) |attribute_value| {
        var previous = AttributeIterator.init(bytes);
        var previous_index: usize = 0;
        while (previous_index < count) : (previous_index += 1) {
            const prior = (try previous.next()) orelse
                return error.InvalidXmlAttribute;
            if (std.mem.eql(u8, prior.name, attribute_value.name))
                return error.DuplicateXmlAttribute;
        }
        count += 1;
    }
}

fn scanName(bytes: []const u8, start: usize) !usize {
    if (start == bytes.len or !isNameStartByte(bytes[start]))
        return error.InvalidXmlName;
    var cursor = start + 1;
    while (cursor < bytes.len and isNameByte(bytes[cursor]))
        cursor += 1;
    return cursor;
}

fn isNameStartByte(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_' or byte == ':' or
        byte >= 0x80;
}

fn isNameByte(byte: u8) bool {
    return isNameStartByte(byte) or std.ascii.isDigit(byte) or
        byte == '-' or byte == '.';
}

fn findTagClose(bytes: []const u8, start: usize) !usize {
    var cursor = start;
    var quote: ?u8 = null;
    while (cursor < bytes.len) : (cursor += 1) {
        const byte = bytes[cursor];
        if (quote) |delimiter| {
            if (byte == delimiter) quote = null;
        } else if (byte == '"' or byte == '\'') {
            quote = byte;
        } else if (byte == '>') {
            return cursor;
        } else if (byte == '<') {
            return error.InvalidXmlStartElement;
        }
    }
    return error.UnclosedXmlStartElement;
}

fn validateXmlContent(bytes: []const u8) !void {
    try validateXmlCharacters(bytes);
    if (std.mem.indexOf(u8, bytes, "]]>") != null)
        return error.InvalidXmlContent;
    var offset: usize = 0;
    while (std.mem.indexOfScalarPos(u8, bytes, offset, '&')) |start| {
        const end = std.mem.indexOfScalarPos(
            u8,
            bytes,
            start + 1,
            ';',
        ) orelse return error.InvalidXmlEntity;
        try validateEntity(bytes[start + 1 .. end]);
        offset = end + 1;
    }
}

fn validateEntity(name: []const u8) !void {
    _ = try entityCodepoint(name);
}

const ParsedEntity = struct {
    codepoint: u21,
    end: usize,
};

fn parseEntity(encoded: []const u8, start: usize) !ParsedEntity {
    const semicolon = std.mem.indexOfScalarPos(
        u8,
        encoded,
        start + 1,
        ';',
    ) orelse return error.InvalidXmlEntity;
    return .{
        .codepoint = try entityCodepoint(encoded[start + 1 .. semicolon]),
        .end = semicolon + 1,
    };
}

fn entityCodepoint(name: []const u8) !u21 {
    const codepoint: u21 = if (std.mem.eql(u8, name, "amp"))
        '&'
    else if (std.mem.eql(u8, name, "lt"))
        '<'
    else if (std.mem.eql(u8, name, "gt"))
        '>'
    else if (std.mem.eql(u8, name, "quot"))
        '"'
    else if (std.mem.eql(u8, name, "apos"))
        '\''
    else if (std.mem.startsWith(u8, name, "#x"))
        std.fmt.parseInt(u21, name[2..], 16) catch
            return error.InvalidXmlEntity
    else if (std.mem.startsWith(u8, name, "#"))
        std.fmt.parseInt(u21, name[1..], 10) catch
            return error.InvalidXmlEntity
    else
        return error.InvalidXmlEntity;
    if (!validXmlCodepoint(codepoint)) return error.InvalidXmlEntity;
    return codepoint;
}

fn validateXmlCharacters(bytes: []const u8) !void {
    var view = std.unicode.Utf8View.init(bytes) catch
        return error.InvalidXmlEncoding;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (!validXmlCodepoint(codepoint))
            return error.InvalidXmlCharacter;
    }
}

fn validXmlCodepoint(codepoint: u21) bool {
    return codepoint == '\t' or codepoint == '\n' or
        codepoint == '\r' or
        (codepoint >= 0x20 and codepoint <= 0xd7ff) or
        (codepoint >= 0xe000 and codepoint <= 0xfffd) or
        (codepoint >= 0x10000 and codepoint <= 0x10ffff);
}

test "XML document iterates namespaces attributes text and empty elements" {
    const document = try Document.init(
        "\xef\xbb\xbf<?xml version=\"1.0\"?>" ++
            "<ebu:root xmlns:ebu=\"urn:test\"><ebu:item id=\"one\">" ++
            "value &amp; more<empty/></ebu:item></ebu:root>",
    );
    var iterator = document.iterator();
    const root = (try iterator.next()).?.start;
    try std.testing.expectEqualStrings("root", root.localName());
    try std.testing.expectEqualStrings(
        "urn:test",
        (try root.namespaceDeclaration("ebu")).?.encoded,
    );
    try std.testing.expect(
        try root.namespace_name.?.eqlBytes("urn:test"),
    );
    const item = (try iterator.next()).?.start;
    try std.testing.expectEqualStrings("one", (try item.attribute("id")).?);
    try std.testing.expect(
        try item.namespace_name.?.eql(root.namespace_name.?),
    );
    try std.testing.expectEqualStrings(
        "value &amp; more",
        (try iterator.next()).?.text.bytes,
    );
    var decoded: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "value & more",
        try decodeContent(&decoded, "value &amp; more"),
    );
    const empty = (try iterator.next()).?.start;
    try std.testing.expect(empty.self_closing);
    try std.testing.expectEqualStrings(
        "item",
        (try iterator.next()).?.end.localName(),
    );
    try std.testing.expectEqualStrings(
        "root",
        (try iterator.next()).?.end.localName(),
    );
    try std.testing.expect((try iterator.next()) == null);
}

test "XML document rejects malformed structure attributes and entities" {
    try std.testing.expectError(
        error.MismatchedXmlElement,
        Document.init("<root><item></root>"),
    );
    try std.testing.expectError(
        error.DuplicateXmlAttribute,
        Document.init("<root id=\"a\" id=\"b\"/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlEntity,
        Document.init("<root>broken &value;</root>"),
    );
    try std.testing.expectError(
        error.MultipleXmlRoots,
        Document.init("<one/><two/>"),
    );
    try std.testing.expectError(
        error.UnsupportedXmlDeclaration,
        Document.init("<!DOCTYPE root><root/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlContent,
        Document.init("<root>invalid ]]></root>"),
    );
}

test "XML document enforces namespace bindings and expanded attributes" {
    try std.testing.expectError(
        error.UndeclaredXmlNamespacePrefix,
        Document.init("<p:root/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlQualifiedName,
        Document.init("<a:b:c xmlns:a=\"urn:a\"/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlQualifiedName,
        Document.init("<a:1item xmlns:a=\"urn:a\"/>"),
    );
    try std.testing.expectError(
        error.EmptyXmlPrefixedNamespace,
        Document.init("<root xmlns:p=\"\"><p:item/></root>"),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceBinding,
        Document.init(
            "<root xmlns:xml=\"urn:not-xml\"/>",
        ),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceBinding,
        Document.init(
            "<root xmlns:p=\"http://www.w3.org/XML/1998/namespace\"/>",
        ),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceBinding,
        Document.init(
            "<root xmlns=\"http://www.w3.org/2000/xmlns/\"/>",
        ),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceUri,
        Document.init("<root xmlns:p=\"urn:not valid\"/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceUri,
        Document.init("<root xmlns:p=\"urn:bad%escape\"/>"),
    );
    try std.testing.expectError(
        error.InvalidXmlNamespaceUri,
        Document.init("<root xmlns:p=\"urn:bad#one#two\"/>"),
    );
    try std.testing.expectError(
        error.ReservedXmlNamespacePrefix,
        Document.init(
            "<xmlns:root xmlns:xmlns=\"urn:namespace\"/>",
        ),
    );
    try std.testing.expectError(
        error.DuplicateXmlExpandedAttribute,
        Document.init(
            "<root xmlns:a=\"urn:same\" xmlns:b=\"urn:same\" " ++
                "a:value=\"one\" b:value=\"two\"/>",
        ),
    );

    const scoped = try Document.init(
        "<root xmlns=\"urn:outer\" xmlns:a=\"urn:attribute\">" ++
            "<child value=\"plain\" a:value=\"qualified\">" ++
            "<leaf xmlns=\"urn:inner\"/></child>" ++
            "<plain xmlns=\"\"/></root>",
    );
    var events = scoped.iterator();
    const root = (try events.next()).?.start;
    try std.testing.expect(
        try root.namespace_name.?.eqlBytes("urn:outer"),
    );
    const child = (try events.next()).?.start;
    try std.testing.expect(
        try child.namespace_name.?.eqlBytes("urn:outer"),
    );
    try std.testing.expectEqualStrings(
        "plain",
        (try child.attribute("value")).?,
    );
    try std.testing.expectEqualStrings(
        "qualified",
        (try child.attribute("a:value")).?,
    );
    const leaf = (try events.next()).?.start;
    try std.testing.expect(
        try leaf.namespace_name.?.eqlBytes("urn:inner"),
    );
    _ = try events.next();
    const plain = (try events.next()).?.start;
    try std.testing.expect(plain.namespace_name == null);

    _ = try Document.init(
        "<root xmlns=\"relative/namespace\"/>",
    );
}

test "XML document enforces bounded nesting" {
    var bytes: [max_depth * 7 + max_depth * 4 + 7]u8 = undefined;
    var offset: usize = 0;
    for (0..max_depth + 1) |_| {
        @memcpy(bytes[offset..][0..3], "<x>");
        offset += 3;
    }
    for (0..max_depth + 1) |_| {
        @memcpy(bytes[offset..][0..4], "</x>");
        offset += 4;
    }
    try std.testing.expectError(
        error.XmlNestingTooDeep,
        Document.init(bytes[0..offset]),
    );
}
