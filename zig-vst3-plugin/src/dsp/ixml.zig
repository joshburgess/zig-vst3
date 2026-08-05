const std = @import("std");

const xml_declaration =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";

pub const Track = struct {
    channel_index: ?u32 = null,
    interleave_index: ?u32 = null,
    name: ?[]const u8 = null,
    function: ?[]const u8 = null,
};

pub const Ratio = struct {
    numerator: u32,
    denominator: u32,

    pub fn validate(self: Ratio) !void {
        if (self.numerator == 0 or self.denominator == 0)
            return error.InvalidIxmlRatio;
    }
};

pub const TimecodeFlag = enum {
    ndf,
    df,
};

pub const Speed = struct {
    note: ?[]const u8 = null,
    master: ?Ratio = null,
    current: ?Ratio = null,
    timecode_rate: ?Ratio = null,
    timecode_flag: ?TimecodeFlag = null,
    file_sample_rate: ?u32 = null,
    audio_bit_depth: ?u16 = null,
    digitizer_sample_rate: ?u32 = null,
    timestamp_samples_high: ?u32 = null,
    timestamp_samples_low: ?u32 = null,
    timestamp_sample_rate: ?u32 = null,
};

pub const FileSet = struct {
    total_files: ?u32 = null,
    family_uid: ?[]const u8 = null,
    family_name: ?[]const u8 = null,
    index: ?[]const u8 = null,
    start_time_high: ?u32 = null,
    start_time_low: ?u32 = null,
};

pub const SyncPointType = enum {
    relative,
    absolute,
};

pub const SyncPoint = struct {
    kind: ?SyncPointType = null,
    function: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    low: ?u32 = null,
    high: ?u32 = null,
    event_duration: ?u64 = null,
};

pub const Loudness = struct {
    value: ?f64 = null,
    range: ?f64 = null,
    max_true_peak_level: ?f64 = null,
    max_momentary: ?f64 = null,
    max_short_term: ?f64 = null,
};

pub const History = struct {
    original_filename: ?[]const u8 = null,
    parent_filename: ?[]const u8 = null,
    parent_uid: ?[]const u8 = null,
};

pub const Bext = struct {
    description: ?[]const u8 = null,
    originator: ?[]const u8 = null,
    originator_reference: ?[]const u8 = null,
    origination_date: ?[]const u8 = null,
    origination_time: ?[]const u8 = null,
    time_reference_low: ?u32 = null,
    time_reference_high: ?u32 = null,
    version: ?[]const u8 = null,
    umid: ?[]const u8 = null,
    reserved: ?[]const u8 = null,
    coding_history: ?[]const u8 = null,
    loudness: ?Loudness = null,
};

pub const LocationGps = struct {
    latitude: f64,
    longitude: f64,
};

pub const Location = struct {
    name: ?[]const u8 = null,
    gps: ?LocationGps = null,
    altitude: ?f64 = null,
    kind: ?[]const u8 = null,
    time: ?[]const u8 = null,
};

pub const User = struct {
    text: ?[]const u8 = null,
    full_title: ?[]const u8 = null,
    director_name: ?[]const u8 = null,
    production_name: ?[]const u8 = null,
    production_address: ?[]const u8 = null,
    production_email: ?[]const u8 = null,
    production_phone: ?[]const u8 = null,
    production_note: ?[]const u8 = null,
    sound_mixer_name: ?[]const u8 = null,
    sound_mixer_address: ?[]const u8 = null,
    sound_mixer_email: ?[]const u8 = null,
    sound_mixer_phone: ?[]const u8 = null,
    sound_mixer_note: ?[]const u8 = null,
    audio_recorder_model: ?[]const u8 = null,
    audio_recorder_serial_number: ?[]const u8 = null,
    audio_recorder_firmware: ?[]const u8 = null,
};

pub const Metadata = struct {
    ixml_version: ?[]const u8 = null,
    project: ?[]const u8 = null,
    scene: ?[]const u8 = null,
    take: ?[]const u8 = null,
    tape: ?[]const u8 = null,
    circled: ?bool = null,
    no_good: ?bool = null,
    false_start: ?bool = null,
    wild_track: ?bool = null,
    file_uid: ?[]const u8 = null,
    ubits: ?[]const u8 = null,
    note: ?[]const u8 = null,
    speed: ?Speed = null,
    loudness: ?Loudness = null,
    history: ?History = null,
    bext: ?Bext = null,
    location: ?Location = null,
    user: ?User = null,
    file_set: ?FileSet = null,
    sync_points: []const SyncPoint = &.{},
    tracks: []const Track = &.{},
};

pub const View = struct {
    ixml_version: ?[]const u8,
    project: ?[]const u8,
    scene: ?[]const u8,
    take: ?[]const u8,
    tape: ?[]const u8,
    circled: ?bool,
    no_good: ?bool,
    false_start: ?bool,
    wild_track: ?bool,
    file_uid: ?[]const u8,
    ubits: ?[]const u8,
    note: ?[]const u8,
    speed: ?Speed,
    loudness: ?Loudness,
    history: ?History,
    bext: ?Bext,
    location: ?Location,
    user: ?User,
    file_set: ?FileSet,
    sync_points: []const SyncPoint,
    tracks: []const Track,
};

pub const Requirements = struct {
    text_bytes: usize,
    sync_point_count: usize,
    track_count: usize,
};

pub const ParseStorage = struct {
    tracks: []Track,
    sync_points: []SyncPoint,
    text: []u8,
};

pub fn requiredBytes(metadata: Metadata) !usize {
    var output = Output{};
    try writeMetadata(&output, metadata);
    return output.offset;
}

pub fn encode(
    destination: []u8,
    metadata: Metadata,
) ![]const u8 {
    const required = try requiredBytes(metadata);
    if (destination.len < required)
        return error.IxmlOutputTooSmall;
    if (metadataOverlaps(destination[0..required], metadata))
        return error.IxmlOutputOverlapsInput;
    var output = Output{ .destination = destination };
    try writeMetadata(&output, metadata);
    return destination[0..required];
}

pub fn requirements(document: []const u8) !Requirements {
    const analysis = try analyze(document);
    return .{
        .text_bytes = analysis.text_bytes,
        .sync_point_count = analysis.sync_point_count,
        .track_count = analysis.track_count,
    };
}

pub fn parse(
    document: []const u8,
    storage: ParseStorage,
) !View {
    const analysis = try analyze(document);
    if (storage.tracks.len < analysis.track_count)
        return error.IxmlTrackStorageTooSmall;
    if (storage.sync_points.len < analysis.sync_point_count)
        return error.IxmlSyncPointStorageTooSmall;
    if (storage.text.len < analysis.text_bytes)
        return error.IxmlTextStorageTooSmall;
    if (byteRangesOverlap(
        document.ptr,
        document.len,
        storage.text.ptr,
        storage.text.len,
    ) or byteRangesOverlap(
        document.ptr,
        document.len,
        storage.tracks.ptr,
        std.math.mul(
            usize,
            storage.tracks.len,
            @sizeOf(Track),
        ) catch return error.IxmlSizeOverflow,
    ) or byteRangesOverlap(
        document.ptr,
        document.len,
        storage.sync_points.ptr,
        std.math.mul(
            usize,
            storage.sync_points.len,
            @sizeOf(SyncPoint),
        ) catch return error.IxmlSizeOverflow,
    ) or byteRangesOverlap(
        storage.text.ptr,
        storage.text.len,
        storage.tracks.ptr,
        std.math.mul(
            usize,
            storage.tracks.len,
            @sizeOf(Track),
        ) catch return error.IxmlSizeOverflow,
    ) or byteRangesOverlap(
        storage.text.ptr,
        storage.text.len,
        storage.sync_points.ptr,
        std.math.mul(
            usize,
            storage.sync_points.len,
            @sizeOf(SyncPoint),
        ) catch return error.IxmlSizeOverflow,
    ) or byteRangesOverlap(
        storage.tracks.ptr,
        std.math.mul(
            usize,
            storage.tracks.len,
            @sizeOf(Track),
        ) catch return error.IxmlSizeOverflow,
        storage.sync_points.ptr,
        std.math.mul(
            usize,
            storage.sync_points.len,
            @sizeOf(SyncPoint),
        ) catch return error.IxmlSizeOverflow,
    )) {
        return error.IxmlStorageOverlapsInput;
    }

    var materializer = Materializer{
        .tracks = storage.tracks[0..analysis.track_count],
        .sync_points = storage.sync_points[0..analysis.sync_point_count],
        .text = storage.text[0..analysis.text_bytes],
    };
    return materializer.materialize(analysis);
}

const RawTrack = struct {
    channel_index: ?u32 = null,
    interleave_index: ?u32 = null,
    name: ?[]const u8 = null,
    function: ?[]const u8 = null,
};

const Analysis = struct {
    ixml_version: ?[]const u8 = null,
    project: ?[]const u8 = null,
    scene: ?[]const u8 = null,
    take: ?[]const u8 = null,
    tape: ?[]const u8 = null,
    circled: ?bool = null,
    no_good: ?bool = null,
    false_start: ?bool = null,
    wild_track: ?bool = null,
    file_uid: ?[]const u8 = null,
    ubits: ?[]const u8 = null,
    note: ?[]const u8 = null,
    speed: ?RawSpeed = null,
    loudness: ?Loudness = null,
    history: ?History = null,
    bext: ?Bext = null,
    location: ?Location = null,
    user: ?User = null,
    file_set: ?RawFileSet = null,
    sync_point_list: ?[]const u8 = null,
    track_list: ?[]const u8 = null,
    text_bytes: usize = 0,
    sync_point_count: usize = 0,
    track_count: usize = 0,
};

const RawSpeed = struct {
    note: ?[]const u8 = null,
    master: ?Ratio = null,
    current: ?Ratio = null,
    timecode_rate: ?Ratio = null,
    timecode_flag: ?TimecodeFlag = null,
    file_sample_rate: ?u32 = null,
    audio_bit_depth: ?u16 = null,
    digitizer_sample_rate: ?u32 = null,
    timestamp_samples_high: ?u32 = null,
    timestamp_samples_low: ?u32 = null,
    timestamp_sample_rate: ?u32 = null,
};

const RawFileSet = struct {
    total_files: ?u32 = null,
    family_uid: ?[]const u8 = null,
    family_name: ?[]const u8 = null,
    index: ?[]const u8 = null,
    start_time_high: ?u32 = null,
    start_time_low: ?u32 = null,
};

const RawSyncPoint = struct {
    kind: ?SyncPointType = null,
    function: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    low: ?u32 = null,
    high: ?u32 = null,
    event_duration: ?u64 = null,
};

fn analyze(document: []const u8) !Analysis {
    if (!std.unicode.utf8ValidateSlice(document))
        return error.InvalidIxmlEncoding;
    if (std.mem.indexOfScalar(u8, document, 0) != null)
        return error.IxmlContainsNul;

    var iterator = ElementIterator.init(document);
    const root = (try iterator.next()) orelse
        return error.MissingIxmlRoot;
    if (!std.mem.eql(u8, root.name, "BWFXML") or root.has_attributes)
        return error.InvalidIxmlRoot;
    if ((try iterator.next()) != null)
        return error.MultipleIxmlRoots;

    var result = Analysis{};
    var children = ElementIterator.init(root.content);
    while (try children.next()) |child| {
        if (child.has_attributes)
            return error.InvalidIxmlField;
        if (std.mem.eql(u8, child.name, "IXML_VERSION")) {
            try setTextField(&result.ixml_version, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "PROJECT")) {
            try setTextField(&result.project, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "SCENE")) {
            try setTextField(&result.scene, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "TAKE")) {
            try setTextField(&result.take, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "TAPE")) {
            try setTextField(&result.tape, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "CIRCLED")) {
            try setBooleanField(&result.circled, child.content);
        } else if (std.mem.eql(u8, child.name, "NO_GOOD")) {
            try setBooleanField(&result.no_good, child.content);
        } else if (std.mem.eql(u8, child.name, "FALSE_START")) {
            try setBooleanField(&result.false_start, child.content);
        } else if (std.mem.eql(u8, child.name, "WILD_TRACK")) {
            try setBooleanField(&result.wild_track, child.content);
        } else if (std.mem.eql(u8, child.name, "FILE_UID")) {
            try setTextField(&result.file_uid, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "UBITS")) {
            try setTextField(&result.ubits, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "NOTE")) {
            try setTextField(&result.note, child.content, &result);
        } else if (std.mem.eql(u8, child.name, "SPEED")) {
            if (result.speed != null)
                return error.DuplicateIxmlField;
            result.speed = try analyzeSpeed(child.content);
            if (result.speed) |speed| {
                if (speed.note) |note| {
                    result.text_bytes = try addSize(
                        result.text_bytes,
                        try decodedTextBytes(note),
                    );
                }
            }
        } else if (std.mem.eql(u8, child.name, "LOUDNESS")) {
            if (result.loudness != null)
                return error.DuplicateIxmlField;
            result.loudness = try analyzeLoudness(
                child.content,
                "",
            );
        } else if (std.mem.eql(u8, child.name, "HISTORY")) {
            if (result.history != null)
                return error.DuplicateIxmlField;
            result.history = try analyzeHistory(child.content);
            const history = result.history orelse
                return error.InvalidIxmlField;
            try addOptionalTextBytes(&result, &.{
                history.original_filename,
                history.parent_filename,
                history.parent_uid,
            });
        } else if (std.mem.eql(u8, child.name, "BEXT")) {
            if (result.bext != null)
                return error.DuplicateIxmlField;
            result.bext = try analyzeBext(child.content);
            const bext = result.bext orelse
                return error.InvalidIxmlField;
            try addOptionalTextBytes(&result, &.{
                bext.description,
                bext.originator,
                bext.originator_reference,
                bext.origination_date,
                bext.origination_time,
                bext.version,
                bext.umid,
                bext.reserved,
                bext.coding_history,
            });
        } else if (std.mem.eql(u8, child.name, "LOCATION")) {
            if (result.location != null)
                return error.DuplicateIxmlField;
            result.location = try analyzeLocation(child.content);
            const location = result.location orelse
                return error.InvalidIxmlField;
            try addOptionalTextBytes(&result, &.{
                location.name,
                location.kind,
                location.time,
            });
        } else if (std.mem.eql(u8, child.name, "USER")) {
            if (result.user != null)
                return error.DuplicateIxmlField;
            result.user = try analyzeUser(child.content);
            const user = result.user orelse
                return error.InvalidIxmlField;
            try addOptionalTextBytes(
                &result,
                &userTextFields(user),
            );
        } else if (std.mem.eql(u8, child.name, "FILE_SET")) {
            if (result.file_set != null)
                return error.DuplicateIxmlField;
            result.file_set = try analyzeFileSet(child.content);
            const file_set = result.file_set orelse
                return error.InvalidIxmlField;
            const fields = [_]?[]const u8{
                file_set.family_uid,
                file_set.family_name,
                file_set.index,
            };
            for (fields) |field| {
                const text = field orelse continue;
                result.text_bytes = try addSize(
                    result.text_bytes,
                    try decodedTextBytes(text),
                );
            }
        } else if (std.mem.eql(
            u8,
            child.name,
            "SYNC_POINT_LIST",
        )) {
            if (result.sync_point_list != null)
                return error.DuplicateIxmlField;
            result.sync_point_list = child.content;
            const sync_points =
                try analyzeSyncPoints(child.content);
            result.sync_point_count = sync_points.count;
            result.text_bytes = try addSize(
                result.text_bytes,
                sync_points.text_bytes,
            );
        } else if (std.mem.eql(u8, child.name, "TRACK_LIST")) {
            if (result.track_list != null)
                return error.DuplicateIxmlField;
            result.track_list = child.content;
            const tracks = try analyzeTracks(child.content);
            result.track_count = tracks.track_count;
            result.text_bytes = try addSize(
                result.text_bytes,
                tracks.text_bytes,
            );
        }
    }
    return result;
}

const SyncPointAnalysis = struct {
    count: usize,
    text_bytes: usize,
};

fn analyzeSyncPoints(content: []const u8) !SyncPointAnalysis {
    var declared_count: ?u32 = null;
    var count: usize = 0;
    var text_bytes: usize = 0;
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlSyncPointList;
        if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_COUNT",
        )) {
            if (declared_count != null)
                return error.DuplicateIxmlField;
            declared_count = try parseUnsigned(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT",
        )) {
            const sync_point =
                try analyzeSyncPoint(element.content);
            count = try addSize(count, 1);
            const fields = [_]?[]const u8{
                sync_point.function,
                sync_point.comment,
            };
            for (fields) |field| {
                const text = field orelse continue;
                text_bytes = try addSize(
                    text_bytes,
                    try decodedTextBytes(text),
                );
            }
        }
    }
    if (declared_count) |declared| {
        if (declared != count)
            return error.IxmlSyncPointCountMismatch;
    }
    return .{ .count = count, .text_bytes = text_bytes };
}

fn analyzeSyncPoint(content: []const u8) !RawSyncPoint {
    var sync_point = RawSyncPoint{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlSyncPoint;
        if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_TYPE",
        )) {
            if (sync_point.kind != null)
                return error.DuplicateIxmlField;
            const kind = std.mem.trim(
                u8,
                element.content,
                " \t\r\n",
            );
            if (std.mem.eql(u8, kind, "RELATIVE")) {
                sync_point.kind = .relative;
            } else if (std.mem.eql(u8, kind, "ABSOLUTE")) {
                sync_point.kind = .absolute;
            } else {
                return error.InvalidIxmlSyncPointType;
            }
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_FUNCTION",
        )) {
            try setRawField(
                &sync_point.function,
                element.content,
            );
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_COMMENT",
        )) {
            try setRawField(
                &sync_point.comment,
                element.content,
            );
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_LOW",
        )) {
            try setUnsignedField(
                &sync_point.low,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_HIGH",
        )) {
            try setUnsignedField(
                &sync_point.high,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "SYNC_POINT_EVENT_DURATION",
        )) {
            if (sync_point.event_duration != null)
                return error.DuplicateIxmlField;
            sync_point.event_duration =
                try parseUnsigned64(element.content);
        }
    }
    return sync_point;
}

fn analyzeSpeed(content: []const u8) !RawSpeed {
    var speed = RawSpeed{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlSpeed;
        if (std.mem.eql(u8, element.name, "NOTE")) {
            try setRawField(&speed.note, element.content);
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(u8, element.name, "MASTER_SPEED")) {
            try setRatioField(&speed.master, element.content);
        } else if (std.mem.eql(u8, element.name, "CURRENT_SPEED")) {
            try setRatioField(&speed.current, element.content);
        } else if (std.mem.eql(u8, element.name, "TIMECODE_RATE")) {
            try setRatioField(
                &speed.timecode_rate,
                element.content,
            );
        } else if (std.mem.eql(u8, element.name, "TIMECODE_FLAG")) {
            if (speed.timecode_flag != null)
                return error.DuplicateIxmlField;
            const flag = std.mem.trim(
                u8,
                element.content,
                " \t\r\n",
            );
            if (std.mem.eql(u8, flag, "NDF")) {
                speed.timecode_flag = .ndf;
            } else if (std.mem.eql(u8, flag, "DF")) {
                speed.timecode_flag = .df;
            } else {
                return error.InvalidIxmlTimecodeFlag;
            }
        } else if (std.mem.eql(
            u8,
            element.name,
            "FILE_SAMPLE_RATE",
        )) {
            try setPositiveUnsignedField(
                &speed.file_sample_rate,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "AUDIO_BIT_DEPTH",
        )) {
            if (speed.audio_bit_depth != null)
                return error.DuplicateIxmlField;
            var value: ?u32 = null;
            try setPositiveUnsignedField(&value, element.content);
            const bit_depth = value orelse
                return error.InvalidIxmlBitDepth;
            if (bit_depth > 64)
                return error.InvalidIxmlBitDepth;
            speed.audio_bit_depth = @intCast(bit_depth);
        } else if (std.mem.eql(
            u8,
            element.name,
            "DIGITIZER_SAMPLE_RATE",
        )) {
            try setPositiveUnsignedField(
                &speed.digitizer_sample_rate,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI",
        )) {
            try setUnsignedField(
                &speed.timestamp_samples_high,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO",
        )) {
            try setUnsignedField(
                &speed.timestamp_samples_low,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "TIMESTAMP_SAMPLE_RATE",
        )) {
            try setPositiveUnsignedField(
                &speed.timestamp_sample_rate,
                element.content,
            );
        }
    }
    return speed;
}

fn analyzeLoudness(
    content: []const u8,
    prefix: []const u8,
) !Loudness {
    var loudness = Loudness{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlLoudness;
        if (matchesPrefixed(
            element.name,
            prefix,
            "LOUDNESS_VALUE",
        )) {
            try setFloatField(&loudness.value, element.content);
        } else if (matchesPrefixed(
            element.name,
            prefix,
            "LOUDNESS_RANGE",
        )) {
            try setFloatField(&loudness.range, element.content);
        } else if (matchesPrefixed(
            element.name,
            prefix,
            "MAX_TRUE_PEAK_LEVEL",
        )) {
            try setFloatField(
                &loudness.max_true_peak_level,
                element.content,
            );
        } else if (matchesPrefixed(
            element.name,
            prefix,
            "MAX_MOMENTARY_LOUDNESS",
        )) {
            try setFloatField(
                &loudness.max_momentary,
                element.content,
            );
        } else if (matchesPrefixed(
            element.name,
            prefix,
            "MAX_SHORT_TERM_LOUDNESS",
        )) {
            try setFloatField(
                &loudness.max_short_term,
                element.content,
            );
        }
    }
    return loudness;
}

fn analyzeHistory(content: []const u8) !History {
    var history = History{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlHistory;
        if (std.mem.eql(
            u8,
            element.name,
            "ORIGINAL_FILENAME",
        )) {
            try setDecodedRawField(
                &history.original_filename,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "PARENT_FILENAME",
        )) {
            try setDecodedRawField(
                &history.parent_filename,
                element.content,
            );
        } else if (std.mem.eql(u8, element.name, "PARENT_UID")) {
            try setDecodedRawField(
                &history.parent_uid,
                element.content,
            );
        }
    }
    return history;
}

fn analyzeBext(content: []const u8) !Bext {
    var bext = Bext{};
    var loudness_content = Loudness{};
    var has_loudness = false;
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes) return error.InvalidIxmlBext;
        if (std.mem.eql(
            u8,
            element.name,
            "BWF_DESCRIPTION",
        )) {
            try setDecodedRawField(
                &bext.description,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_ORIGINATOR",
        )) {
            try setDecodedRawField(
                &bext.originator,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_ORIGINATOR_REFERENCE",
        )) {
            try setDecodedRawField(
                &bext.originator_reference,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_ORIGINATION_DATE",
        )) {
            try setDecodedRawField(
                &bext.origination_date,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_ORIGINATION_TIME",
        )) {
            try setDecodedRawField(
                &bext.origination_time,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_TIME_REFERENCE_LOW",
        )) {
            try setUnsignedField(
                &bext.time_reference_low,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_TIME_REFERENCE_HIGH",
        )) {
            try setUnsignedField(
                &bext.time_reference_high,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_VERSION",
        )) {
            try setDecodedRawField(&bext.version, element.content);
        } else if (std.mem.eql(u8, element.name, "BWF_UMID")) {
            try setDecodedRawField(&bext.umid, element.content);
        } else if (std.mem.eql(u8, element.name, "BWF_RESERVED")) {
            try setDecodedRawField(&bext.reserved, element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "BWF_CODING_HISTORY",
        )) {
            try setDecodedRawField(
                &bext.coding_history,
                element.content,
            );
        } else if (std.mem.startsWith(
            u8,
            element.name,
            "BWF_LOUDNESS",
        ) or std.mem.startsWith(
            u8,
            element.name,
            "BWF_MAX_",
        )) {
            has_loudness = true;
            try analyzeLoudnessElement(
                &loudness_content,
                element,
                "BWF_",
            );
        }
    }
    if (has_loudness) bext.loudness = loudness_content;
    return bext;
}

fn analyzeLoudnessElement(
    loudness: *Loudness,
    element: Element,
    prefix: []const u8,
) !void {
    if (matchesPrefixed(element.name, prefix, "LOUDNESS_VALUE")) {
        try setFloatField(&loudness.value, element.content);
    } else if (matchesPrefixed(
        element.name,
        prefix,
        "LOUDNESS_RANGE",
    )) {
        try setFloatField(&loudness.range, element.content);
    } else if (matchesPrefixed(
        element.name,
        prefix,
        "MAX_TRUE_PEAK_LEVEL",
    )) {
        try setFloatField(
            &loudness.max_true_peak_level,
            element.content,
        );
    } else if (matchesPrefixed(
        element.name,
        prefix,
        "MAX_MOMENTARY_LOUDNESS",
    )) {
        try setFloatField(
            &loudness.max_momentary,
            element.content,
        );
    } else if (matchesPrefixed(
        element.name,
        prefix,
        "MAX_SHORT_TERM_LOUDNESS",
    )) {
        try setFloatField(
            &loudness.max_short_term,
            element.content,
        );
    }
}

fn analyzeLocation(content: []const u8) !Location {
    var location = Location{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlLocation;
        if (std.mem.eql(u8, element.name, "LOCATION_NAME")) {
            try setDecodedRawField(&location.name, element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "LOCATION_GPS",
        )) {
            if (location.gps != null)
                return error.DuplicateIxmlField;
            location.gps = try parseGps(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "LOCATION_ALTITUDE",
        )) {
            try setFloatField(&location.altitude, element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "LOCATION_TYPE",
        )) {
            try setDecodedRawField(&location.kind, element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "LOCATION_TIME",
        )) {
            try setDecodedRawField(&location.time, element.content);
        }
    }
    return location;
}

fn analyzeUser(content: []const u8) !User {
    const trimmed = std.mem.trim(u8, content, " \t\r\n");
    if (trimmed.len == 0) return .{};
    if (trimmed[0] != '<') {
        _ = try decodedTextBytes(trimmed);
        return .{ .text = trimmed };
    }

    var user = User{};
    var iterator = ElementIterator.init(trimmed);
    while (try iterator.next()) |element| {
        if (element.has_attributes) return error.InvalidIxmlUser;
        const field = userField(&user, element.name) orelse continue;
        try setDecodedRawField(field, element.content);
    }
    return user;
}

fn userField(user: *User, name: []const u8) ?*?[]const u8 {
    if (std.mem.eql(u8, name, "FULL_TITLE"))
        return &user.full_title;
    if (std.mem.eql(u8, name, "DIRECTOR_NAME"))
        return &user.director_name;
    if (std.mem.eql(u8, name, "PRODUCTION_NAME"))
        return &user.production_name;
    if (std.mem.eql(u8, name, "PRODUCTION_ADDRESS"))
        return &user.production_address;
    if (std.mem.eql(u8, name, "PRODUCTION_EMAIL"))
        return &user.production_email;
    if (std.mem.eql(u8, name, "PRODUCTION_PHONE"))
        return &user.production_phone;
    if (std.mem.eql(u8, name, "PRODUCTION_NOTE"))
        return &user.production_note;
    if (std.mem.eql(u8, name, "SOUND_MIXER_NAME"))
        return &user.sound_mixer_name;
    if (std.mem.eql(u8, name, "SOUND_MIXER_ADDRESS"))
        return &user.sound_mixer_address;
    if (std.mem.eql(u8, name, "SOUND_MIXER_EMAIL"))
        return &user.sound_mixer_email;
    if (std.mem.eql(u8, name, "SOUND_MIXER_PHONE"))
        return &user.sound_mixer_phone;
    if (std.mem.eql(u8, name, "SOUND_MIXER_NOTE"))
        return &user.sound_mixer_note;
    if (std.mem.eql(u8, name, "AUDIO_RECORDER_MODEL"))
        return &user.audio_recorder_model;
    if (std.mem.eql(u8, name, "AUDIO_RECORDER_SERIAL_NUMBER"))
        return &user.audio_recorder_serial_number;
    if (std.mem.eql(u8, name, "AUDIO_RECORDER_FIRMWARE"))
        return &user.audio_recorder_firmware;
    return null;
}

fn analyzeFileSet(content: []const u8) !RawFileSet {
    var file_set = RawFileSet{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlFileSet;
        if (std.mem.eql(u8, element.name, "TOTAL_FILES")) {
            try setPositiveUnsignedField(
                &file_set.total_files,
                element.content,
            );
        } else if (std.mem.eql(u8, element.name, "FAMILY_UID")) {
            try setRawField(
                &file_set.family_uid,
                element.content,
            );
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(u8, element.name, "FAMILY_NAME")) {
            try setRawField(
                &file_set.family_name,
                element.content,
            );
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "FILE_SET_INDEX",
        )) {
            try setRawField(&file_set.index, element.content);
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(
            u8,
            element.name,
            "FILE_SET_START_TIME_HI",
        )) {
            try setUnsignedField(
                &file_set.start_time_high,
                element.content,
            );
        } else if (std.mem.eql(
            u8,
            element.name,
            "FILE_SET_START_TIME_LO",
        )) {
            try setUnsignedField(
                &file_set.start_time_low,
                element.content,
            );
        }
    }
    return file_set;
}

const TrackAnalysis = struct {
    track_count: usize,
    text_bytes: usize,
};

fn analyzeTracks(content: []const u8) !TrackAnalysis {
    var declared_count: ?u32 = null;
    var track_count: usize = 0;
    var text_bytes: usize = 0;
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlTrackList;
        if (std.mem.eql(u8, element.name, "TRACK_COUNT")) {
            if (declared_count != null)
                return error.DuplicateIxmlField;
            declared_count = try parseUnsigned(element.content);
        } else if (std.mem.eql(u8, element.name, "TRACK")) {
            const track = try analyzeTrack(element.content);
            track_count = try addSize(track_count, 1);
            if (track.name) |name|
                text_bytes = try addSize(
                    text_bytes,
                    try decodedTextBytes(name),
                );
            if (track.function) |function|
                text_bytes = try addSize(
                    text_bytes,
                    try decodedTextBytes(function),
                );
        }
    }
    if (declared_count) |count| {
        if (count != track_count)
            return error.IxmlTrackCountMismatch;
    }
    return .{
        .track_count = track_count,
        .text_bytes = text_bytes,
    };
}

fn analyzeTrack(content: []const u8) !RawTrack {
    var track = RawTrack{};
    var iterator = ElementIterator.init(content);
    while (try iterator.next()) |element| {
        if (element.has_attributes)
            return error.InvalidIxmlTrack;
        if (std.mem.eql(u8, element.name, "CHANNEL_INDEX")) {
            try setPositiveUnsignedField(
                &track.channel_index,
                element.content,
            );
        } else if (std.mem.eql(u8, element.name, "INTERLEAVE_INDEX")) {
            try setPositiveUnsignedField(
                &track.interleave_index,
                element.content,
            );
        } else if (std.mem.eql(u8, element.name, "NAME")) {
            try setRawField(&track.name, element.content);
            _ = try decodedTextBytes(element.content);
        } else if (std.mem.eql(u8, element.name, "FUNCTION")) {
            try setRawField(&track.function, element.content);
            _ = try decodedTextBytes(element.content);
        }
    }
    return track;
}

fn setTextField(
    field: *?[]const u8,
    value: []const u8,
    analysis: *Analysis,
) !void {
    try setRawField(field, value);
    analysis.text_bytes = try addSize(
        analysis.text_bytes,
        try decodedTextBytes(value),
    );
}

fn setRawField(field: *?[]const u8, value: []const u8) !void {
    if (field.* != null) return error.DuplicateIxmlField;
    field.* = value;
}

fn setDecodedRawField(
    field: *?[]const u8,
    value: []const u8,
) !void {
    try setRawField(field, value);
    _ = try decodedTextBytes(value);
}

fn setFloatField(field: *?f64, value: []const u8) !void {
    if (field.* != null) return error.DuplicateIxmlField;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return;
    const parsed = std.fmt.parseFloat(f64, trimmed) catch
        return error.InvalidIxmlFloat;
    if (!std.math.isFinite(parsed)) return error.InvalidIxmlFloat;
    field.* = parsed;
}

fn parseGps(value: []const u8) !LocationGps {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    const separator = std.mem.indexOfScalar(u8, trimmed, ',') orelse
        return error.InvalidIxmlGps;
    if (std.mem.indexOfScalarPos(
        u8,
        trimmed,
        separator + 1,
        ',',
    ) != null) return error.InvalidIxmlGps;
    const latitude = std.fmt.parseFloat(
        f64,
        std.mem.trim(u8, trimmed[0..separator], " \t\r\n"),
    ) catch return error.InvalidIxmlGps;
    const longitude = std.fmt.parseFloat(
        f64,
        std.mem.trim(u8, trimmed[separator + 1 ..], " \t\r\n"),
    ) catch return error.InvalidIxmlGps;
    if (!std.math.isFinite(latitude) or
        !std.math.isFinite(longitude) or
        latitude < -90 or latitude > 90 or
        longitude < -180 or longitude > 180)
        return error.InvalidIxmlGps;
    return .{ .latitude = latitude, .longitude = longitude };
}

fn matchesPrefixed(
    actual: []const u8,
    prefix: []const u8,
    suffix: []const u8,
) bool {
    return actual.len == prefix.len + suffix.len and
        std.mem.eql(u8, actual[0..prefix.len], prefix) and
        std.mem.eql(u8, actual[prefix.len..], suffix);
}

fn addOptionalTextBytes(
    analysis: *Analysis,
    fields: []const ?[]const u8,
) !void {
    for (fields) |field| {
        const text = field orelse continue;
        analysis.text_bytes = try addSize(
            analysis.text_bytes,
            try decodedTextBytes(text),
        );
    }
}

fn userTextFields(user: User) [16]?[]const u8 {
    return .{
        user.text,
        user.full_title,
        user.director_name,
        user.production_name,
        user.production_address,
        user.production_email,
        user.production_phone,
        user.production_note,
        user.sound_mixer_name,
        user.sound_mixer_address,
        user.sound_mixer_email,
        user.sound_mixer_phone,
        user.sound_mixer_note,
        user.audio_recorder_model,
        user.audio_recorder_serial_number,
        user.audio_recorder_firmware,
    };
}

fn setBooleanField(field: *?bool, value: []const u8) !void {
    if (field.* != null) return error.DuplicateIxmlField;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "TRUE")) {
        field.* = true;
    } else if (std.mem.eql(u8, trimmed, "FALSE")) {
        field.* = false;
    } else {
        return error.InvalidIxmlBoolean;
    }
}

fn setUnsignedField(field: *?u32, value: []const u8) !void {
    if (field.* != null) return error.DuplicateIxmlField;
    field.* = try parseUnsigned(value);
}

fn setPositiveUnsignedField(field: *?u32, value: []const u8) !void {
    try setUnsignedField(field, value);
    const parsed = field.* orelse return error.InvalidIxmlNumber;
    if (parsed == 0) return error.InvalidIxmlNumber;
}

fn setRatioField(field: *?Ratio, value: []const u8) !void {
    if (field.* != null) return error.DuplicateIxmlField;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    const separator = std.mem.indexOfScalar(u8, trimmed, '/') orelse
        return error.InvalidIxmlRatio;
    if (std.mem.indexOfScalarPos(
        u8,
        trimmed,
        separator + 1,
        '/',
    ) != null) return error.InvalidIxmlRatio;
    const ratio = Ratio{
        .numerator = std.fmt.parseInt(
            u32,
            trimmed[0..separator],
            10,
        ) catch return error.InvalidIxmlRatio,
        .denominator = std.fmt.parseInt(
            u32,
            trimmed[separator + 1 ..],
            10,
        ) catch return error.InvalidIxmlRatio,
    };
    try ratio.validate();
    field.* = ratio;
}

fn parseUnsigned(value: []const u8) !u32 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidIxmlNumber;
    return std.fmt.parseInt(u32, trimmed, 10) catch
        return error.InvalidIxmlNumber;
}

fn parseUnsigned64(value: []const u8) !u64 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidIxmlNumber;
    return std.fmt.parseInt(u64, trimmed, 10) catch
        return error.InvalidIxmlNumber;
}

const Materializer = struct {
    tracks: []Track,
    sync_points: []SyncPoint,
    text: []u8,
    text_offset: usize = 0,

    fn materialize(self: *Materializer, analysis: Analysis) !View {
        var view = View{
            .ixml_version = try self.copyOptional(analysis.ixml_version),
            .project = try self.copyOptional(analysis.project),
            .scene = try self.copyOptional(analysis.scene),
            .take = try self.copyOptional(analysis.take),
            .tape = try self.copyOptional(analysis.tape),
            .circled = analysis.circled,
            .no_good = analysis.no_good,
            .false_start = analysis.false_start,
            .wild_track = analysis.wild_track,
            .file_uid = try self.copyOptional(analysis.file_uid),
            .ubits = try self.copyOptional(analysis.ubits),
            .note = try self.copyOptional(analysis.note),
            .speed = try self.materializeSpeed(analysis.speed),
            .loudness = analysis.loudness,
            .history = try self.materializeHistory(analysis.history),
            .bext = try self.materializeBext(analysis.bext),
            .location = try self.materializeLocation(
                analysis.location,
            ),
            .user = try self.materializeUser(analysis.user),
            .file_set = try self.materializeFileSet(
                analysis.file_set,
            ),
            .sync_points = self.sync_points,
            .tracks = self.tracks,
        };
        _ = &view;
        if (analysis.track_list) |track_list|
            try self.materializeTracks(track_list);
        if (analysis.sync_point_list) |sync_point_list|
            try self.materializeSyncPoints(sync_point_list);
        return view;
    }

    fn materializeSpeed(
        self: *Materializer,
        raw: ?RawSpeed,
    ) !?Speed {
        const speed = raw orelse return null;
        return .{
            .note = try self.copyOptional(speed.note),
            .master = speed.master,
            .current = speed.current,
            .timecode_rate = speed.timecode_rate,
            .timecode_flag = speed.timecode_flag,
            .file_sample_rate = speed.file_sample_rate,
            .audio_bit_depth = speed.audio_bit_depth,
            .digitizer_sample_rate = speed.digitizer_sample_rate,
            .timestamp_samples_high = speed.timestamp_samples_high,
            .timestamp_samples_low = speed.timestamp_samples_low,
            .timestamp_sample_rate = speed.timestamp_sample_rate,
        };
    }

    fn materializeFileSet(
        self: *Materializer,
        raw: ?RawFileSet,
    ) !?FileSet {
        const file_set = raw orelse return null;
        return .{
            .total_files = file_set.total_files,
            .family_uid = try self.copyOptional(
                file_set.family_uid,
            ),
            .family_name = try self.copyOptional(
                file_set.family_name,
            ),
            .index = try self.copyOptional(file_set.index),
            .start_time_high = file_set.start_time_high,
            .start_time_low = file_set.start_time_low,
        };
    }

    fn materializeHistory(
        self: *Materializer,
        raw: ?History,
    ) !?History {
        const history = raw orelse return null;
        return .{
            .original_filename = try self.copyOptional(
                history.original_filename,
            ),
            .parent_filename = try self.copyOptional(
                history.parent_filename,
            ),
            .parent_uid = try self.copyOptional(history.parent_uid),
        };
    }

    fn materializeBext(
        self: *Materializer,
        raw: ?Bext,
    ) !?Bext {
        const bext = raw orelse return null;
        return .{
            .description = try self.copyOptional(bext.description),
            .originator = try self.copyOptional(bext.originator),
            .originator_reference = try self.copyOptional(
                bext.originator_reference,
            ),
            .origination_date = try self.copyOptional(
                bext.origination_date,
            ),
            .origination_time = try self.copyOptional(
                bext.origination_time,
            ),
            .time_reference_low = bext.time_reference_low,
            .time_reference_high = bext.time_reference_high,
            .version = try self.copyOptional(bext.version),
            .umid = try self.copyOptional(bext.umid),
            .reserved = try self.copyOptional(bext.reserved),
            .coding_history = try self.copyOptional(
                bext.coding_history,
            ),
            .loudness = bext.loudness,
        };
    }

    fn materializeLocation(
        self: *Materializer,
        raw: ?Location,
    ) !?Location {
        const location = raw orelse return null;
        return .{
            .name = try self.copyOptional(location.name),
            .gps = location.gps,
            .altitude = location.altitude,
            .kind = try self.copyOptional(location.kind),
            .time = try self.copyOptional(location.time),
        };
    }

    fn materializeUser(
        self: *Materializer,
        raw: ?User,
    ) !?User {
        const user = raw orelse return null;
        return .{
            .text = try self.copyOptional(user.text),
            .full_title = try self.copyOptional(user.full_title),
            .director_name = try self.copyOptional(
                user.director_name,
            ),
            .production_name = try self.copyOptional(
                user.production_name,
            ),
            .production_address = try self.copyOptional(
                user.production_address,
            ),
            .production_email = try self.copyOptional(
                user.production_email,
            ),
            .production_phone = try self.copyOptional(
                user.production_phone,
            ),
            .production_note = try self.copyOptional(
                user.production_note,
            ),
            .sound_mixer_name = try self.copyOptional(
                user.sound_mixer_name,
            ),
            .sound_mixer_address = try self.copyOptional(
                user.sound_mixer_address,
            ),
            .sound_mixer_email = try self.copyOptional(
                user.sound_mixer_email,
            ),
            .sound_mixer_phone = try self.copyOptional(
                user.sound_mixer_phone,
            ),
            .sound_mixer_note = try self.copyOptional(
                user.sound_mixer_note,
            ),
            .audio_recorder_model = try self.copyOptional(
                user.audio_recorder_model,
            ),
            .audio_recorder_serial_number = try self.copyOptional(
                user.audio_recorder_serial_number,
            ),
            .audio_recorder_firmware = try self.copyOptional(
                user.audio_recorder_firmware,
            ),
        };
    }

    fn materializeTracks(
        self: *Materializer,
        content: []const u8,
    ) !void {
        var track_index: usize = 0;
        var iterator = ElementIterator.init(content);
        while (try iterator.next()) |element| {
            if (!std.mem.eql(u8, element.name, "TRACK")) continue;
            const raw = try analyzeTrack(element.content);
            self.tracks[track_index] = .{
                .channel_index = raw.channel_index,
                .interleave_index = raw.interleave_index,
                .name = try self.copyOptional(raw.name),
                .function = try self.copyOptional(raw.function),
            };
            track_index += 1;
        }
    }

    fn materializeSyncPoints(
        self: *Materializer,
        content: []const u8,
    ) !void {
        var sync_point_index: usize = 0;
        var iterator = ElementIterator.init(content);
        while (try iterator.next()) |element| {
            if (!std.mem.eql(
                u8,
                element.name,
                "SYNC_POINT",
            )) continue;
            const raw = try analyzeSyncPoint(element.content);
            self.sync_points[sync_point_index] = .{
                .kind = raw.kind,
                .function = try self.copyOptional(raw.function),
                .comment = try self.copyOptional(raw.comment),
                .low = raw.low,
                .high = raw.high,
                .event_duration = raw.event_duration,
            };
            sync_point_index += 1;
        }
    }

    fn copyOptional(
        self: *Materializer,
        value: ?[]const u8,
    ) !?[]const u8 {
        const encoded = value orelse return null;
        const required = try decodedTextBytes(encoded);
        const destination =
            self.text[self.text_offset .. self.text_offset + required];
        try decodeText(destination, encoded);
        self.text_offset += required;
        return destination;
    }
};

const Element = struct {
    name: []const u8,
    content: []const u8,
    has_attributes: bool,
};

const ElementIterator = struct {
    bytes: []const u8,
    offset: usize = 0,

    fn init(bytes: []const u8) ElementIterator {
        var content = bytes;
        if (std.mem.startsWith(u8, content, "\xef\xbb\xbf"))
            content = content[3..];
        return .{ .bytes = content };
    }

    fn next(self: *ElementIterator) !?Element {
        try self.skipMisc();
        if (self.offset == self.bytes.len) return null;
        if (self.bytes[self.offset] != '<')
            return error.InvalidIxmlXml;
        const scanned = try scanElement(self.bytes, self.offset);
        self.offset = scanned.next_offset;
        return scanned.element;
    }

    fn skipMisc(self: *ElementIterator) !void {
        while (true) {
            while (self.offset < self.bytes.len and
                std.ascii.isWhitespace(self.bytes[self.offset]))
            {
                self.offset += 1;
            }
            if (std.mem.startsWith(
                u8,
                self.bytes[self.offset..],
                "<?",
            )) {
                const end = std.mem.indexOf(
                    u8,
                    self.bytes[self.offset + 2 ..],
                    "?>",
                ) orelse return error.InvalidIxmlXml;
                self.offset += 2 + end + 2;
                continue;
            }
            if (std.mem.startsWith(
                u8,
                self.bytes[self.offset..],
                "<!--",
            )) {
                const end = std.mem.indexOf(
                    u8,
                    self.bytes[self.offset + 4 ..],
                    "-->",
                ) orelse return error.InvalidIxmlXml;
                self.offset += 4 + end + 3;
                continue;
            }
            break;
        }
    }
};

const ScannedElement = struct {
    element: Element,
    next_offset: usize,
};

fn scanElement(bytes: []const u8, start: usize) !ScannedElement {
    const opening = try parseTag(bytes, start);
    if (opening.closing or opening.special)
        return error.InvalidIxmlXml;
    if (opening.self_closing) {
        return .{
            .element = .{
                .name = opening.name,
                .content = bytes[opening.end..opening.end],
                .has_attributes = opening.has_attributes,
            },
            .next_offset = opening.end,
        };
    }

    var names: [32][]const u8 = undefined;
    names[0] = opening.name;
    var depth: usize = 1;
    var cursor = opening.end;
    while (cursor < bytes.len) {
        const tag_start = std.mem.indexOfScalarPos(
            u8,
            bytes,
            cursor,
            '<',
        ) orelse return error.InvalidIxmlXml;
        const tag = try parseTag(bytes, tag_start);
        cursor = tag.end;
        if (tag.special) continue;
        if (tag.closing) {
            if (depth == 0 or
                !std.mem.eql(u8, tag.name, names[depth - 1]))
            {
                return error.MismatchedIxmlTag;
            }
            depth -= 1;
            if (depth == 0) {
                return .{
                    .element = .{
                        .name = opening.name,
                        .content = bytes[opening.end..tag_start],
                        .has_attributes = opening.has_attributes,
                    },
                    .next_offset = tag.end,
                };
            }
        } else if (!tag.self_closing) {
            if (depth == names.len)
                return error.IxmlNestingTooDeep;
            names[depth] = tag.name;
            depth += 1;
        }
    }
    return error.InvalidIxmlXml;
}

const Tag = struct {
    name: []const u8,
    end: usize,
    closing: bool,
    self_closing: bool,
    special: bool,
    has_attributes: bool,
};

fn parseTag(bytes: []const u8, start: usize) !Tag {
    if (start >= bytes.len or bytes[start] != '<')
        return error.InvalidIxmlXml;
    if (std.mem.startsWith(u8, bytes[start..], "<!--")) {
        const end = std.mem.indexOf(u8, bytes[start + 4 ..], "-->") orelse
            return error.InvalidIxmlXml;
        return .{
            .name = "",
            .end = start + 4 + end + 3,
            .closing = false,
            .self_closing = true,
            .special = true,
            .has_attributes = false,
        };
    }
    if (std.mem.startsWith(u8, bytes[start..], "<?")) {
        const end = std.mem.indexOf(u8, bytes[start + 2 ..], "?>") orelse
            return error.InvalidIxmlXml;
        return .{
            .name = "",
            .end = start + 2 + end + 2,
            .closing = false,
            .self_closing = true,
            .special = true,
            .has_attributes = false,
        };
    }
    if (start + 1 >= bytes.len or bytes[start + 1] == '!')
        return error.UnsupportedIxmlDeclaration;

    var cursor = start + 1;
    const closing = bytes[cursor] == '/';
    if (closing) cursor += 1;
    const name_start = cursor;
    while (cursor < bytes.len and isNameByte(bytes[cursor]))
        cursor += 1;
    if (cursor == name_start) return error.InvalidIxmlXml;
    const name = bytes[name_start..cursor];
    const attributes_start = cursor;
    var quote: ?u8 = null;
    while (cursor < bytes.len) : (cursor += 1) {
        const byte = bytes[cursor];
        if (quote) |delimiter| {
            if (byte == delimiter) quote = null;
            continue;
        }
        if (byte == '"' or byte == '\'') {
            quote = byte;
        } else if (byte == '>') {
            var body = std.mem.trim(
                u8,
                bytes[attributes_start..cursor],
                " \t\r\n",
            );
            const self_closing =
                !closing and body.len != 0 and body[body.len - 1] == '/';
            if (self_closing)
                body = std.mem.trimEnd(
                    u8,
                    body[0 .. body.len - 1],
                    " \t\r\n",
                );
            if (closing and body.len != 0)
                return error.InvalidIxmlXml;
            return .{
                .name = name,
                .end = cursor + 1,
                .closing = closing,
                .self_closing = self_closing,
                .special = false,
                .has_attributes = body.len != 0,
            };
        }
    }
    return error.InvalidIxmlXml;
}

fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '_' or byte == '-' or byte == ':' or byte == '.';
}

fn decodedTextBytes(encoded: []const u8) !usize {
    try validateXmlText(encoded);
    var required: usize = 0;
    var offset: usize = 0;
    while (offset < encoded.len) {
        if (encoded[offset] != '&') {
            const sequence_length = std.unicode.utf8ByteSequenceLength(
                encoded[offset],
            ) catch return error.InvalidIxmlEncoding;
            required = try addSize(required, sequence_length);
            offset += sequence_length;
            continue;
        }
        const entity = try parseEntity(encoded, offset);
        required = try addSize(
            required,
            std.unicode.utf8CodepointSequenceLength(entity.codepoint) catch
                return error.InvalidIxmlEntity,
        );
        offset = entity.end;
    }
    return required;
}

fn decodeText(destination: []u8, encoded: []const u8) !void {
    var source_offset: usize = 0;
    var destination_offset: usize = 0;
    while (source_offset < encoded.len) {
        if (encoded[source_offset] != '&') {
            const sequence_length = try std.unicode.utf8ByteSequenceLength(
                encoded[source_offset],
            );
            @memcpy(
                destination[destination_offset..][0..sequence_length],
                encoded[source_offset..][0..sequence_length],
            );
            source_offset += sequence_length;
            destination_offset += sequence_length;
            continue;
        }
        const entity = try parseEntity(encoded, source_offset);
        var codepoint_storage: [4]u8 = undefined;
        const encoded_bytes = try std.unicode.utf8Encode(
            entity.codepoint,
            &codepoint_storage,
        );
        @memcpy(
            destination[destination_offset..][0..encoded_bytes],
            codepoint_storage[0..encoded_bytes],
        );
        destination_offset += encoded_bytes;
        source_offset = entity.end;
    }
}

const Entity = struct {
    codepoint: u21,
    end: usize,
};

fn parseEntity(encoded: []const u8, start: usize) !Entity {
    const semicolon = std.mem.indexOfScalarPos(
        u8,
        encoded,
        start + 1,
        ';',
    ) orelse return error.InvalidIxmlEntity;
    const name = encoded[start + 1 .. semicolon];
    const codepoint: u21 =
        if (std.mem.eql(u8, name, "amp"))
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
                return error.InvalidIxmlEntity
        else if (std.mem.startsWith(u8, name, "#"))
            std.fmt.parseInt(u21, name[1..], 10) catch
                return error.InvalidIxmlEntity
        else
            return error.InvalidIxmlEntity;
    if (!validXmlCodepoint(codepoint))
        return error.InvalidIxmlEntity;
    return .{ .codepoint = codepoint, .end = semicolon + 1 };
}

fn validateXmlText(text: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(text))
        return error.InvalidIxmlEncoding;
    if (std.mem.indexOfScalar(u8, text, '<') != null)
        return error.NestedIxmlText;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (!validXmlCodepoint(codepoint))
            return error.InvalidIxmlCharacter;
    }
}

fn validXmlCodepoint(codepoint: u21) bool {
    return codepoint == '\t' or codepoint == '\n' or
        codepoint == '\r' or
        (codepoint >= 0x20 and codepoint <= 0xd7ff) or
        (codepoint >= 0xe000 and codepoint <= 0xfffd) or
        (codepoint >= 0x10000 and codepoint <= 0x10ffff);
}

const Output = struct {
    destination: ?[]u8 = null,
    offset: usize = 0,

    fn append(self: *Output, bytes: []const u8) !void {
        const next = try addSize(self.offset, bytes.len);
        if (self.destination) |destination|
            @memcpy(destination[self.offset..next], bytes);
        self.offset = next;
    }
};

fn writeMetadata(output: *Output, metadata: Metadata) !void {
    try output.append(xml_declaration);
    try output.append("<BWFXML>\n");
    try writeOptionalText(
        output,
        "IXML_VERSION",
        metadata.ixml_version,
        2,
    );
    try writeOptionalText(output, "PROJECT", metadata.project, 2);
    try writeOptionalText(output, "SCENE", metadata.scene, 2);
    try writeOptionalText(output, "TAKE", metadata.take, 2);
    try writeOptionalText(output, "TAPE", metadata.tape, 2);
    try writeOptionalBoolean(output, "CIRCLED", metadata.circled, 2);
    try writeOptionalBoolean(output, "NO_GOOD", metadata.no_good, 2);
    try writeOptionalBoolean(
        output,
        "FALSE_START",
        metadata.false_start,
        2,
    );
    try writeOptionalBoolean(
        output,
        "WILD_TRACK",
        metadata.wild_track,
        2,
    );
    try writeOptionalText(output, "FILE_UID", metadata.file_uid, 2);
    if (metadata.speed) |speed|
        try writeSpeed(output, speed);
    if (metadata.loudness) |loudness|
        try writeLoudness(output, loudness);
    if (metadata.history) |history|
        try writeHistory(output, history);
    if (metadata.location) |location|
        try writeLocation(output, location);
    try writeOptionalText(output, "UBITS", metadata.ubits, 2);
    if (metadata.sync_points.len != 0)
        try writeSyncPoints(output, metadata.sync_points);
    try writeOptionalText(output, "NOTE", metadata.note, 2);
    if (metadata.file_set) |file_set|
        try writeFileSet(output, file_set);
    if (metadata.tracks.len != 0) {
        if (metadata.tracks.len > std.math.maxInt(u32))
            return error.IxmlTrackCountOverflow;
        try output.append("  <TRACK_LIST>\n");
        try writeUnsigned(
            output,
            "TRACK_COUNT",
            @as(u32, @intCast(metadata.tracks.len)),
            4,
        );
        for (metadata.tracks) |track| {
            if (track.channel_index) |index|
                if (index == 0) return error.InvalidIxmlTrackIndex;
            if (track.interleave_index) |index|
                if (index == 0) return error.InvalidIxmlTrackIndex;
            try output.append("    <TRACK>\n");
            if (track.channel_index) |value|
                try writeUnsigned(output, "CHANNEL_INDEX", value, 6);
            if (track.interleave_index) |value|
                try writeUnsigned(output, "INTERLEAVE_INDEX", value, 6);
            try writeOptionalText(output, "NAME", track.name, 6);
            try writeOptionalText(
                output,
                "FUNCTION",
                track.function,
                6,
            );
            try output.append("    </TRACK>\n");
        }
        try output.append("  </TRACK_LIST>\n");
    }
    if (metadata.bext) |bext|
        try writeBext(output, bext);
    if (metadata.user) |user|
        try writeUser(output, user);
    try output.append("</BWFXML>\n");
}

fn writeSyncPoints(
    output: *Output,
    sync_points: []const SyncPoint,
) !void {
    if (sync_points.len > std.math.maxInt(u32))
        return error.IxmlSyncPointCountOverflow;
    try output.append("  <SYNC_POINT_LIST>\n");
    try writeUnsigned(
        output,
        "SYNC_POINT_COUNT",
        sync_points.len,
        4,
    );
    for (sync_points) |sync_point| {
        try output.append("    <SYNC_POINT>\n");
        if (sync_point.kind) |kind| {
            try writeOptionalText(
                output,
                "SYNC_POINT_TYPE",
                switch (kind) {
                    .relative => "RELATIVE",
                    .absolute => "ABSOLUTE",
                },
                6,
            );
        }
        try writeOptionalText(
            output,
            "SYNC_POINT_FUNCTION",
            sync_point.function,
            6,
        );
        try writeOptionalText(
            output,
            "SYNC_POINT_COMMENT",
            sync_point.comment,
            6,
        );
        try writeOptionalUnsigned(
            output,
            "SYNC_POINT_LOW",
            sync_point.low,
            6,
        );
        try writeOptionalUnsigned(
            output,
            "SYNC_POINT_HIGH",
            sync_point.high,
            6,
        );
        try writeOptionalUnsigned(
            output,
            "SYNC_POINT_EVENT_DURATION",
            sync_point.event_duration,
            6,
        );
        try output.append("    </SYNC_POINT>\n");
    }
    try output.append("  </SYNC_POINT_LIST>\n");
}

fn writeSpeed(output: *Output, speed: Speed) !void {
    try validateSpeed(speed);
    try output.append("  <SPEED>\n");
    try writeOptionalText(output, "NOTE", speed.note, 4);
    try writeOptionalRatio(output, "MASTER_SPEED", speed.master, 4);
    try writeOptionalRatio(output, "CURRENT_SPEED", speed.current, 4);
    try writeOptionalRatio(
        output,
        "TIMECODE_RATE",
        speed.timecode_rate,
        4,
    );
    if (speed.timecode_flag) |flag| {
        try writeOptionalText(
            output,
            "TIMECODE_FLAG",
            switch (flag) {
                .ndf => "NDF",
                .df => "DF",
            },
            4,
        );
    }
    try writeOptionalUnsigned(
        output,
        "FILE_SAMPLE_RATE",
        speed.file_sample_rate,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "AUDIO_BIT_DEPTH",
        speed.audio_bit_depth,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "DIGITIZER_SAMPLE_RATE",
        speed.digitizer_sample_rate,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI",
        speed.timestamp_samples_high,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO",
        speed.timestamp_samples_low,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "TIMESTAMP_SAMPLE_RATE",
        speed.timestamp_sample_rate,
        4,
    );
    try output.append("  </SPEED>\n");
}

fn validateSpeed(speed: Speed) !void {
    if (speed.master) |ratio| try ratio.validate();
    if (speed.current) |ratio| try ratio.validate();
    if (speed.timecode_rate) |ratio| try ratio.validate();
    const positive_rates = [_]?u32{
        speed.file_sample_rate,
        speed.digitizer_sample_rate,
        speed.timestamp_sample_rate,
    };
    for (positive_rates) |rate| {
        if (rate) |value|
            if (value == 0) return error.InvalidIxmlNumber;
    }
    if (speed.audio_bit_depth) |bit_depth| {
        if (bit_depth == 0 or bit_depth > 64)
            return error.InvalidIxmlBitDepth;
    }
}

fn writeLoudness(output: *Output, loudness: Loudness) !void {
    try output.append("  <LOUDNESS>\n");
    try writeLoudnessFields(output, loudness, "", 4);
    try output.append("  </LOUDNESS>\n");
}

fn writeLoudnessFields(
    output: *Output,
    loudness: Loudness,
    prefix: []const u8,
    indentation: usize,
) !void {
    try writeOptionalFloat(
        output,
        prefix,
        "LOUDNESS_VALUE",
        loudness.value,
        indentation,
    );
    try writeOptionalFloat(
        output,
        prefix,
        "LOUDNESS_RANGE",
        loudness.range,
        indentation,
    );
    try writeOptionalFloat(
        output,
        prefix,
        "MAX_TRUE_PEAK_LEVEL",
        loudness.max_true_peak_level,
        indentation,
    );
    try writeOptionalFloat(
        output,
        prefix,
        "MAX_MOMENTARY_LOUDNESS",
        loudness.max_momentary,
        indentation,
    );
    try writeOptionalFloat(
        output,
        prefix,
        "MAX_SHORT_TERM_LOUDNESS",
        loudness.max_short_term,
        indentation,
    );
}

fn writeHistory(output: *Output, history: History) !void {
    try output.append("  <HISTORY>\n");
    try writeOptionalText(
        output,
        "ORIGINAL_FILENAME",
        history.original_filename,
        4,
    );
    try writeOptionalText(
        output,
        "PARENT_FILENAME",
        history.parent_filename,
        4,
    );
    try writeOptionalText(
        output,
        "PARENT_UID",
        history.parent_uid,
        4,
    );
    try output.append("  </HISTORY>\n");
}

fn writeBext(output: *Output, bext: Bext) !void {
    try output.append("  <BEXT>\n");
    try writeOptionalText(
        output,
        "BWF_DESCRIPTION",
        bext.description,
        4,
    );
    try writeOptionalText(
        output,
        "BWF_ORIGINATOR",
        bext.originator,
        4,
    );
    try writeOptionalText(
        output,
        "BWF_ORIGINATOR_REFERENCE",
        bext.originator_reference,
        4,
    );
    try writeOptionalText(
        output,
        "BWF_ORIGINATION_DATE",
        bext.origination_date,
        4,
    );
    try writeOptionalText(
        output,
        "BWF_ORIGINATION_TIME",
        bext.origination_time,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "BWF_TIME_REFERENCE_LOW",
        bext.time_reference_low,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "BWF_TIME_REFERENCE_HIGH",
        bext.time_reference_high,
        4,
    );
    try writeOptionalText(output, "BWF_VERSION", bext.version, 4);
    try writeOptionalText(output, "BWF_UMID", bext.umid, 4);
    try writeOptionalText(output, "BWF_RESERVED", bext.reserved, 4);
    try writeOptionalText(
        output,
        "BWF_CODING_HISTORY",
        bext.coding_history,
        4,
    );
    if (bext.loudness) |loudness|
        try writeLoudnessFields(output, loudness, "BWF_", 4);
    try output.append("  </BEXT>\n");
}

fn writeLocation(output: *Output, location: Location) !void {
    try output.append("  <LOCATION>\n");
    try writeOptionalText(
        output,
        "LOCATION_NAME",
        location.name,
        4,
    );
    if (location.gps) |gps| {
        try validateGps(gps);
        var storage: [64]u8 = undefined;
        const text = std.fmt.bufPrint(
            &storage,
            "{d}, {d}",
            .{ gps.latitude, gps.longitude },
        ) catch return error.IxmlSizeOverflow;
        try writeOptionalText(output, "LOCATION_GPS", text, 4);
    }
    try writeOptionalFloat(
        output,
        "",
        "LOCATION_ALTITUDE",
        location.altitude,
        4,
    );
    try writeOptionalText(
        output,
        "LOCATION_TYPE",
        location.kind,
        4,
    );
    try writeOptionalText(
        output,
        "LOCATION_TIME",
        location.time,
        4,
    );
    try output.append("  </LOCATION>\n");
}

fn writeUser(output: *Output, user: User) !void {
    const structured = [_]?[]const u8{
        user.full_title,
        user.director_name,
        user.production_name,
        user.production_address,
        user.production_email,
        user.production_phone,
        user.production_note,
        user.sound_mixer_name,
        user.sound_mixer_address,
        user.sound_mixer_email,
        user.sound_mixer_phone,
        user.sound_mixer_note,
        user.audio_recorder_model,
        user.audio_recorder_serial_number,
        user.audio_recorder_firmware,
    };
    var has_structured = false;
    for (structured) |field| {
        if (field != null) has_structured = true;
    }
    if (user.text != null and has_structured)
        return error.AmbiguousIxmlUser;
    if (user.text) |text| {
        try writeOptionalText(output, "USER", text, 2);
        return;
    }

    try output.append("  <USER>\n");
    const names = [_][]const u8{
        "FULL_TITLE",
        "DIRECTOR_NAME",
        "PRODUCTION_NAME",
        "PRODUCTION_ADDRESS",
        "PRODUCTION_EMAIL",
        "PRODUCTION_PHONE",
        "PRODUCTION_NOTE",
        "SOUND_MIXER_NAME",
        "SOUND_MIXER_ADDRESS",
        "SOUND_MIXER_EMAIL",
        "SOUND_MIXER_PHONE",
        "SOUND_MIXER_NOTE",
        "AUDIO_RECORDER_MODEL",
        "AUDIO_RECORDER_SERIAL_NUMBER",
        "AUDIO_RECORDER_FIRMWARE",
    };
    for (names, structured) |name, field|
        try writeOptionalText(output, name, field, 4);
    try output.append("  </USER>\n");
}

fn writeFileSet(output: *Output, file_set: FileSet) !void {
    if (file_set.total_files) |total|
        if (total == 0) return error.InvalidIxmlNumber;
    try output.append("  <FILE_SET>\n");
    try writeOptionalUnsigned(
        output,
        "TOTAL_FILES",
        file_set.total_files,
        4,
    );
    try writeOptionalText(
        output,
        "FAMILY_UID",
        file_set.family_uid,
        4,
    );
    try writeOptionalText(
        output,
        "FAMILY_NAME",
        file_set.family_name,
        4,
    );
    try writeOptionalText(
        output,
        "FILE_SET_INDEX",
        file_set.index,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "FILE_SET_START_TIME_HI",
        file_set.start_time_high,
        4,
    );
    try writeOptionalUnsigned(
        output,
        "FILE_SET_START_TIME_LO",
        file_set.start_time_low,
        4,
    );
    try output.append("  </FILE_SET>\n");
}

fn writeOptionalText(
    output: *Output,
    name: []const u8,
    value: ?[]const u8,
    indentation: usize,
) !void {
    const text = value orelse return;
    try validateXmlTextForEncoding(text);
    try writeIndent(output, indentation);
    try output.append("<");
    try output.append(name);
    try output.append(">");
    try writeEscaped(output, text);
    try output.append("</");
    try output.append(name);
    try output.append(">\n");
}

fn writeOptionalBoolean(
    output: *Output,
    name: []const u8,
    value: ?bool,
    indentation: usize,
) !void {
    const boolean = value orelse return;
    try writeIndent(output, indentation);
    try output.append("<");
    try output.append(name);
    try output.append(if (boolean) ">TRUE</" else ">FALSE</");
    try output.append(name);
    try output.append(">\n");
}

fn writeOptionalRatio(
    output: *Output,
    name: []const u8,
    value: ?Ratio,
    indentation: usize,
) !void {
    const ratio = value orelse return;
    try ratio.validate();
    var storage: [21]u8 = undefined;
    const text = try std.fmt.bufPrint(
        &storage,
        "{d}/{d}",
        .{ ratio.numerator, ratio.denominator },
    );
    try writeOptionalText(output, name, text, indentation);
}

fn writeOptionalUnsigned(
    output: *Output,
    name: []const u8,
    value: anytype,
    indentation: usize,
) !void {
    const integer = value orelse return;
    try writeUnsigned(output, name, integer, indentation);
}

fn writeOptionalFloat(
    output: *Output,
    prefix: []const u8,
    name: []const u8,
    value: ?f64,
    indentation: usize,
) !void {
    const number = value orelse return;
    if (!std.math.isFinite(number))
        return error.InvalidIxmlFloat;
    var storage: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&storage, "{d}", .{number}) catch
        return error.IxmlSizeOverflow;
    try writeIndent(output, indentation);
    try output.append("<");
    try output.append(prefix);
    try output.append(name);
    try output.append(">");
    try output.append(text);
    try output.append("</");
    try output.append(prefix);
    try output.append(name);
    try output.append(">\n");
}

fn validateGps(gps: LocationGps) !void {
    if (!std.math.isFinite(gps.latitude) or
        !std.math.isFinite(gps.longitude) or
        gps.latitude < -90 or gps.latitude > 90 or
        gps.longitude < -180 or gps.longitude > 180)
        return error.InvalidIxmlGps;
}

fn writeUnsigned(
    output: *Output,
    name: []const u8,
    value: anytype,
    indentation: usize,
) !void {
    var storage: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&storage, "{d}", .{value}) catch
        return error.IxmlSizeOverflow;
    try writeOptionalText(output, name, text, indentation);
}

fn writeIndent(output: *Output, count: usize) !void {
    const spaces = "        ";
    try output.append(spaces[0..count]);
}

fn writeEscaped(output: *Output, text: []const u8) !void {
    var start: usize = 0;
    for (text, 0..) |byte, index| {
        const entity: ?[]const u8 = switch (byte) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            else => null,
        };
        if (entity) |replacement| {
            try output.append(text[start..index]);
            try output.append(replacement);
            start = index + 1;
        }
    }
    try output.append(text[start..]);
}

fn validateXmlTextForEncoding(text: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(text))
        return error.InvalidIxmlEncoding;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (!validXmlCodepoint(codepoint))
            return error.InvalidIxmlCharacter;
    }
}

fn metadataOverlaps(destination: []u8, metadata: Metadata) bool {
    const track_bytes = std.math.mul(
        usize,
        metadata.tracks.len,
        @sizeOf(Track),
    ) catch return true;
    if (byteRangesOverlap(
        destination.ptr,
        destination.len,
        metadata.tracks.ptr,
        track_bytes,
    )) return true;
    const sync_point_bytes = std.math.mul(
        usize,
        metadata.sync_points.len,
        @sizeOf(SyncPoint),
    ) catch return true;
    if (byteRangesOverlap(
        destination.ptr,
        destination.len,
        metadata.sync_points.ptr,
        sync_point_bytes,
    )) return true;
    const fields = [_]?[]const u8{
        metadata.ixml_version,
        metadata.project,
        metadata.scene,
        metadata.take,
        metadata.tape,
        metadata.file_uid,
        metadata.ubits,
        metadata.note,
    };
    for (fields) |field| {
        const text = field orelse continue;
        if (byteRangesOverlap(
            destination.ptr,
            destination.len,
            text.ptr,
            text.len,
        )) return true;
    }
    if (metadata.speed) |speed| {
        if (speed.note) |text| {
            if (byteRangesOverlap(
                destination.ptr,
                destination.len,
                text.ptr,
                text.len,
            )) return true;
        }
    }
    if (metadata.file_set) |file_set| {
        const file_set_fields = [_]?[]const u8{
            file_set.family_uid,
            file_set.family_name,
            file_set.index,
        };
        for (file_set_fields) |field| {
            const text = field orelse continue;
            if (byteRangesOverlap(
                destination.ptr,
                destination.len,
                text.ptr,
                text.len,
            )) return true;
        }
    }
    if (metadata.history) |history| {
        const history_fields = [_]?[]const u8{
            history.original_filename,
            history.parent_filename,
            history.parent_uid,
        };
        if (textFieldsOverlap(destination, &history_fields))
            return true;
    }
    if (metadata.bext) |bext| {
        const bext_fields = [_]?[]const u8{
            bext.description,
            bext.originator,
            bext.originator_reference,
            bext.origination_date,
            bext.origination_time,
            bext.version,
            bext.umid,
            bext.reserved,
            bext.coding_history,
        };
        if (textFieldsOverlap(destination, &bext_fields))
            return true;
    }
    if (metadata.location) |location| {
        const location_fields = [_]?[]const u8{
            location.name,
            location.kind,
            location.time,
        };
        if (textFieldsOverlap(destination, &location_fields))
            return true;
    }
    if (metadata.user) |user| {
        const user_fields = userTextFields(user);
        if (textFieldsOverlap(destination, &user_fields))
            return true;
    }
    for (metadata.sync_points) |sync_point| {
        const sync_point_fields = [_]?[]const u8{
            sync_point.function,
            sync_point.comment,
        };
        for (sync_point_fields) |field| {
            const text = field orelse continue;
            if (byteRangesOverlap(
                destination.ptr,
                destination.len,
                text.ptr,
                text.len,
            )) return true;
        }
    }
    for (metadata.tracks) |track| {
        const track_fields = [_]?[]const u8{ track.name, track.function };
        for (track_fields) |field| {
            const text = field orelse continue;
            if (byteRangesOverlap(
                destination.ptr,
                destination.len,
                text.ptr,
                text.len,
            )) return true;
        }
    }
    return false;
}

fn textFieldsOverlap(
    destination: []u8,
    fields: []const ?[]const u8,
) bool {
    for (fields) |field| {
        const text = field orelse continue;
        if (byteRangesOverlap(
            destination.ptr,
            destination.len,
            text.ptr,
            text.len,
        )) return true;
    }
    return false;
}

fn byteRangesOverlap(
    left_pointer: anytype,
    left_length: usize,
    right_pointer: anytype,
    right_length: usize,
) bool {
    if (left_length == 0 or right_length == 0) return false;
    const left_start = @intFromPtr(left_pointer);
    const right_start = @intFromPtr(right_pointer);
    const left_end = std.math.add(
        usize,
        left_start,
        left_length,
    ) catch return true;
    const right_end = std.math.add(
        usize,
        right_start,
        right_length,
    ) catch return true;
    return left_start < right_end and right_start < left_end;
}

fn addSize(left: usize, right: usize) !usize {
    return std.math.add(usize, left, right) catch
        return error.IxmlSizeOverflow;
}

test "iXML metadata round trips common recorder fields and tracks" {
    const tracks = [_]Track{
        .{
            .channel_index = 1,
            .interleave_index = 1,
            .name = "Boom & Mix",
            .function = "DIALOG",
        },
        .{
            .channel_index = 2,
            .name = "Lavalier <A>",
        },
    };
    const sync_points = [_]SyncPoint{
        .{
            .kind = .relative,
            .function = "PRE_RECORD_SAMPLECOUNT",
            .low = 480_000,
            .high = 0,
            .event_duration = 0,
        },
        .{
            .kind = .relative,
            .function = "SLATE_GENERIC",
            .comment = "Camera A",
            .low = 6_544_645,
            .high = 0,
            .event_duration = 120,
        },
    };
    const metadata = Metadata{
        .ixml_version = "1.52",
        .project = "Feature",
        .scene = "21A",
        .take = "10",
        .tape = "15",
        .circled = true,
        .file_uid = "MTIPMX17654200508051445053840001",
        .note = "Exterior & traffic",
        .speed = .{
            .note = "camera overcranked",
            .master = .{ .numerator = 24, .denominator = 1 },
            .current = .{ .numerator = 48, .denominator = 1 },
            .timecode_rate = .{
                .numerator = 24_000,
                .denominator = 1_001,
            },
            .timecode_flag = .ndf,
            .file_sample_rate = 48_000,
            .audio_bit_depth = 24,
            .digitizer_sample_rate = 48_048,
            .timestamp_samples_high = 0,
            .timestamp_samples_low = 48_048_000,
            .timestamp_sample_rate = 48_000,
        },
        .file_set = .{
            .total_files = 2,
            .family_uid = "MTIPMX17654200508051445053840000",
            .family_name = "21A/10",
            .index = "A",
        },
        .sync_points = &sync_points,
        .tracks = &tracks,
    };
    var encoded_storage: [4096]u8 = undefined;
    const encoded = try encode(&encoded_storage, metadata);
    const required = try requirements(encoded);
    try std.testing.expectEqual(@as(usize, 2), required.track_count);
    try std.testing.expectEqual(
        @as(usize, 2),
        required.sync_point_count,
    );
    var parsed_tracks: [2]Track = undefined;
    var parsed_sync_points: [2]SyncPoint = undefined;
    var text_storage: [256]u8 = undefined;
    const view = try parse(
        encoded,
        .{
            .tracks = &parsed_tracks,
            .sync_points = &parsed_sync_points,
            .text = &text_storage,
        },
    );
    try std.testing.expectEqualStrings("Feature", view.project.?);
    try std.testing.expectEqualStrings(
        "Exterior & traffic",
        view.note.?,
    );
    try std.testing.expect(view.circled.?);
    try std.testing.expectEqual(
        Ratio{ .numerator = 24_000, .denominator = 1_001 },
        view.speed.?.timecode_rate.?,
    );
    try std.testing.expectEqual(
        @as(?u32, 48_048),
        view.speed.?.digitizer_sample_rate,
    );
    try std.testing.expectEqualStrings(
        "camera overcranked",
        view.speed.?.note.?,
    );
    try std.testing.expectEqualStrings(
        "21A/10",
        view.file_set.?.family_name.?,
    );
    try std.testing.expectEqual(@as(usize, 2), view.tracks.len);
    try std.testing.expectEqualStrings(
        "Boom & Mix",
        view.tracks[0].name.?,
    );
    try std.testing.expectEqualStrings(
        "Lavalier <A>",
        view.tracks[1].name.?,
    );
    try std.testing.expectEqual(
        SyncPointType.relative,
        view.sync_points[1].kind.?,
    );
    try std.testing.expectEqualStrings(
        "Camera A",
        view.sync_points[1].comment.?,
    );
    try std.testing.expectEqual(
        @as(?u64, 120),
        view.sync_points[1].event_duration,
    );
}

test "iXML metadata round trips BEXT loudness history location and user" {
    const metadata = Metadata{
        .loudness = .{
            .value = -23.0,
            .range = 7.5,
            .max_true_peak_level = -1.2,
            .max_momentary = -18.25,
            .max_short_term = -20.5,
        },
        .history = .{
            .original_filename = "Original & first.wav",
            .parent_filename = "Parent.wav",
            .parent_uid = "parent-123",
        },
        .bext = .{
            .description = "Portable BEXT",
            .originator = "Recorder",
            .originator_reference = "ref-42",
            .origination_date = "2026-07-27",
            .origination_time = "18:45:00",
            .time_reference_low = 123_456,
            .time_reference_high = 1,
            .version = "2.0",
            .umid = "060a2b340101010501010f2013000000",
            .reserved = "0000",
            .coding_history = "A=PCM,F=48000,W=24,M=mono",
            .loudness = .{
                .value = -23.0,
                .max_true_peak_level = -1.2,
            },
        },
        .location = .{
            .name = "Olympic National Park",
            .gps = .{
                .latitude = 47.756787,
                .longitude = -123.729977,
            },
            .altitude = 412.5,
            .kind = "EXTERIOR",
            .time = "DAY",
        },
        .user = .{
            .full_title = "Production Title",
            .director_name = "Director",
            .production_email = "production@example.test",
            .sound_mixer_name = "Mixer",
            .audio_recorder_model = "Recorder 8",
            .audio_recorder_firmware = "3.2",
        },
    };
    var encoded_storage: [4096]u8 = undefined;
    const encoded = try encode(&encoded_storage, metadata);
    const required = try requirements(encoded);
    var text_storage: [1024]u8 = undefined;
    try std.testing.expect(required.text_bytes <= text_storage.len);
    const view = try parse(encoded, .{
        .tracks = &.{},
        .sync_points = &.{},
        .text = &text_storage,
    });

    try std.testing.expectApproxEqAbs(
        @as(f64, -23.0),
        view.loudness.?.value.?,
        1.0e-12,
    );
    try std.testing.expectEqualStrings(
        "Original & first.wav",
        view.history.?.original_filename.?,
    );
    try std.testing.expectEqualStrings(
        "Portable BEXT",
        view.bext.?.description.?,
    );
    try std.testing.expectEqual(
        @as(?u32, 123_456),
        view.bext.?.time_reference_low,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -1.2),
        view.bext.?.loudness.?.max_true_peak_level.?,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 47.756787),
        view.location.?.gps.?.latitude,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -123.729977),
        view.location.?.gps.?.longitude,
        1.0e-12,
    );
    try std.testing.expectEqualStrings(
        "EXTERIOR",
        view.location.?.kind.?,
    );
    try std.testing.expectEqualStrings(
        "production@example.test",
        view.user.?.production_email.?,
    );
    try std.testing.expectEqualStrings(
        "Recorder 8",
        view.user.?.audio_recorder_model.?,
    );
}

test "iXML USER accepts legacy text and structured unknown extensions" {
    const legacy =
        "<BWFXML><USER>Mixer &amp; contact</USER></BWFXML>";
    var text_storage: [64]u8 = undefined;
    const legacy_view = try parse(legacy, .{
        .tracks = &.{},
        .sync_points = &.{},
        .text = &text_storage,
    });
    try std.testing.expectEqualStrings(
        "Mixer & contact",
        legacy_view.user.?.text.?,
    );

    const structured =
        "<BWFXML><USER>" ++
        "<FULL_TITLE>Feature</FULL_TITLE>" ++
        "<VENDOR><PRIVATE>ignored</PRIVATE></VENDOR>" ++
        "<SOUND_MIXER_NAME>Mixer</SOUND_MIXER_NAME>" ++
        "</USER></BWFXML>";
    const structured_view = try parse(structured, .{
        .tracks = &.{},
        .sync_points = &.{},
        .text = &text_storage,
    });
    try std.testing.expectEqualStrings(
        "Feature",
        structured_view.user.?.full_title.?,
    );
    try std.testing.expectEqualStrings(
        "Mixer",
        structured_view.user.?.sound_mixer_name.?,
    );
}

test "iXML extended object validation is transactional" {
    var output: [512]u8 = @splat(0xa5);
    const before = output;
    try std.testing.expectError(
        error.InvalidIxmlGps,
        encode(&output, .{
            .location = .{
                .gps = .{ .latitude = 91, .longitude = 0 },
            },
        }),
    );
    try std.testing.expectEqualSlices(u8, &before, &output);
    try std.testing.expectError(
        error.InvalidIxmlFloat,
        requirements(
            "<BWFXML><LOUDNESS>" ++
                "<LOUDNESS_VALUE>nan</LOUDNESS_VALUE>" ++
                "</LOUDNESS></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.AmbiguousIxmlUser,
        requiredBytes(.{
            .user = .{
                .text = "legacy",
                .full_title = "structured",
            },
        }),
    );
    try std.testing.expectError(
        error.DuplicateIxmlField,
        requirements(
            "<BWFXML><HISTORY>" ++
                "<PARENT_UID>a</PARENT_UID>" ++
                "<PARENT_UID>b</PARENT_UID>" ++
                "</HISTORY></BWFXML>",
        ),
    );
}

test "iXML parser accepts unknown extensions and numeric entities" {
    const document =
        "<?xml version=\"1.0\"?><BWFXML>" ++
        "<PROJECT>R&#xE9;gie</PROJECT>" ++
        "<VENDOR><NESTED enabled=\"yes\">ignored</NESTED></VENDOR>" ++
        "<TRACK_LIST><TRACK_COUNT>1</TRACK_COUNT>" ++
        "<TRACK><CHANNEL_INDEX>7</CHANNEL_INDEX>" ++
        "<FUNCTION>LEFT</FUNCTION></TRACK></TRACK_LIST>" ++
        "</BWFXML>";
    var tracks: [1]Track = undefined;
    var sync_points: [0]SyncPoint = .{};
    var text: [32]u8 = undefined;
    const view = try parse(document, .{
        .tracks = &tracks,
        .sync_points = &sync_points,
        .text = &text,
    });
    try std.testing.expectEqualStrings("Régie", view.project.?);
    try std.testing.expectEqual(@as(?u32, 7), view.tracks[0].channel_index);
}

test "iXML validation is transactional and rejects malformed documents" {
    var tracks: [1]Track = @splat(.{ .channel_index = 99 });
    var text: [32]u8 = @splat(0xa5);
    const tracks_before = tracks;
    const text_before = text;
    try std.testing.expectError(
        error.IxmlTrackCountMismatch,
        parse(
            "<BWFXML><TRACK_LIST><TRACK_COUNT>2</TRACK_COUNT>" ++
                "<TRACK/></TRACK_LIST></BWFXML>",
            .{
                .tracks = &tracks,
                .sync_points = &.{},
                .text = &text,
            },
        ),
    );
    try std.testing.expectEqual(tracks_before, tracks);
    try std.testing.expectEqual(text_before, text);
    try std.testing.expectError(
        error.DuplicateIxmlField,
        requirements(
            "<BWFXML><SCENE>A</SCENE><SCENE>B</SCENE></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.MismatchedIxmlTag,
        requirements("<BWFXML><SCENE>A</TAKE></BWFXML>"),
    );
    try std.testing.expectError(
        error.InvalidIxmlEntity,
        requirements("<BWFXML><NOTE>&unknown;</NOTE></BWFXML>"),
    );
    try std.testing.expectError(
        error.InvalidIxmlRatio,
        requirements(
            "<BWFXML><SPEED><TIMECODE_RATE>30000/0" ++
                "</TIMECODE_RATE></SPEED></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.InvalidIxmlBitDepth,
        requirements(
            "<BWFXML><SPEED><AUDIO_BIT_DEPTH>128" ++
                "</AUDIO_BIT_DEPTH></SPEED></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.InvalidIxmlNumber,
        requirements(
            "<BWFXML><TRACK_LIST><TRACK>" ++
                "<CHANNEL_INDEX>0</CHANNEL_INDEX>" ++
                "</TRACK></TRACK_LIST></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.IxmlSyncPointCountMismatch,
        requirements(
            "<BWFXML><SYNC_POINT_LIST>" ++
                "<SYNC_POINT_COUNT>2</SYNC_POINT_COUNT>" ++
                "<SYNC_POINT/></SYNC_POINT_LIST></BWFXML>",
        ),
    );
    try std.testing.expectError(
        error.InvalidIxmlSyncPointType,
        requirements(
            "<BWFXML><SYNC_POINT_LIST><SYNC_POINT>" ++
                "<SYNC_POINT_TYPE>OFFSET</SYNC_POINT_TYPE>" ++
                "</SYNC_POINT></SYNC_POINT_LIST></BWFXML>",
        ),
    );
}

test "iXML encoding validates before mutating output" {
    var storage: [64]u8 = @splat(0xa5);
    const before = storage;
    try std.testing.expectError(
        error.InvalidIxmlCharacter,
        encode(&storage, .{ .project = "bad\x01value" }),
    );
    try std.testing.expectEqual(before, storage);
    try std.testing.expectError(
        error.IxmlOutputTooSmall,
        encode(&storage, .{ .project = "A feature project" }),
    );
    try std.testing.expectEqual(before, storage);
    try std.testing.expectError(
        error.InvalidIxmlRatio,
        encode(&storage, .{ .speed = .{
            .master = .{ .numerator = 24, .denominator = 0 },
        } }),
    );
    try std.testing.expectEqual(before, storage);
    try std.testing.expectError(
        error.InvalidIxmlTrackIndex,
        encode(&storage, .{
            .tracks = &.{.{ .channel_index = 0 }},
        }),
    );
    try std.testing.expectEqual(before, storage);
}

test "iXML unsigned formatting overflow preserves output" {
    var storage: [64]u8 = @splat(0xa5);
    const before = storage;
    var output = Output{ .destination = &storage, .offset = 7 };
    try std.testing.expectError(
        error.IxmlSizeOverflow,
        writeUnsigned(&output, "COUNT", std.math.maxInt(u128), 2),
    );
    try std.testing.expectEqual(@as(usize, 7), output.offset);
    try std.testing.expectEqual(before, storage);
}

test "iXML rejects overlapping encoded and decoded storage" {
    var encoding_storage: [256]u8 = undefined;
    @memcpy(encoding_storage[60..67], "Project");
    try std.testing.expectError(
        error.IxmlOutputOverlapsInput,
        encode(
            &encoding_storage,
            .{ .project = encoding_storage[60..67] },
        ),
    );

    const document = "<BWFXML><PROJECT>Feature</PROJECT></BWFXML>";
    var parsing_storage: [128]u8 = undefined;
    @memcpy(parsing_storage[0..document.len], document);
    var tracks: [1]Track = undefined;
    try std.testing.expectError(
        error.IxmlStorageOverlapsInput,
        parse(
            parsing_storage[0..document.len],
            .{
                .tracks = &tracks,
                .sync_points = &.{},
                .text = parsing_storage[20..],
            },
        ),
    );
}

test "iXML parse capacity checks preserve caller storage" {
    const document =
        "<BWFXML><PROJECT>Feature</PROJECT><TRACK_LIST>" ++
        "<TRACK_COUNT>1</TRACK_COUNT><TRACK><NAME>Boom</NAME>" ++
        "</TRACK></TRACK_LIST></BWFXML>";
    var tracks: [1]Track = @splat(.{ .channel_index = 99 });
    var text: [16]u8 = @splat(0xa5);
    const tracks_before = tracks;
    const text_before = text;
    try std.testing.expectError(
        error.IxmlTrackStorageTooSmall,
        parse(document, .{
            .tracks = tracks[0..0],
            .sync_points = &.{},
            .text = &text,
        }),
    );
    try std.testing.expectError(
        error.IxmlTextStorageTooSmall,
        parse(document, .{
            .tracks = &tracks,
            .sync_points = &.{},
            .text = text[0..4],
        }),
    );
    try std.testing.expectError(
        error.IxmlSyncPointStorageTooSmall,
        parse(
            "<BWFXML><SYNC_POINT_LIST><SYNC_POINT/>" ++
                "</SYNC_POINT_LIST></BWFXML>",
            .{
                .tracks = &tracks,
                .sync_points = &.{},
                .text = &text,
            },
        ),
    );
    try std.testing.expectEqual(tracks_before, tracks);
    try std.testing.expectEqual(text_before, text);
}
