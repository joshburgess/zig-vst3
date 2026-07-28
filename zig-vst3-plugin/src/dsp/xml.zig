const std = @import("std");

pub const max_depth: usize = 64;

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

pub const StartElement = struct {
    name: []const u8,
    attributes: []const u8,
    depth: usize,
    self_closing: bool,

    pub fn localName(self: StartElement) []const u8 {
        return qualifiedLocalName(self.name);
    }

    pub fn attribute(self: StartElement, wanted_local_name: []const u8) !?[]const u8 {
        var found: ?[]const u8 = null;
        var iterator = AttributeIterator.init(self.attributes);
        while (try iterator.next()) |attribute_value| {
            if (!std.mem.eql(
                u8,
                attribute_value.localName(),
                wanted_local_name,
            )) {
                continue;
            }
            if (found != null) return error.DuplicateXmlLocalAttribute;
            found = attribute_value.value;
        }
        return found;
    }
};

pub const EndElement = struct {
    name: []const u8,
    depth: usize,

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
    names: [max_depth][]const u8 = undefined,
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
        try validateAttributes(attributes);
        const element_depth = self.depth;
        if (!self_closing) {
            if (self.depth == max_depth) return error.XmlNestingTooDeep;
            self.names[self.depth] = name;
            self.depth += 1;
        }
        self.offset = closing + 1;
        return .{ .start = .{
            .name = name,
            .attributes = attributes,
            .depth = element_depth,
            .self_closing = self_closing,
        } };
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
        if (!std.mem.eql(u8, name, self.names[self.depth - 1]))
            return error.MismatchedXmlElement;
        self.depth -= 1;
        self.offset = cursor + 1;
        return .{ .end = .{ .name = name, .depth = self.depth } };
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
        (try root.attribute("ebu")).?,
    );
    const item = (try iterator.next()).?.start;
    try std.testing.expectEqualStrings("one", (try item.attribute("id")).?);
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
