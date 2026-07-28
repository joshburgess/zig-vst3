const std = @import("std");

pub const raw = @import("ara-raw");

pub const current_generation: raw.ARAAPIGeneration =
    raw.kARAAPIGeneration_2_3_Final;
pub const minimum_generation: raw.ARAAPIGeneration =
    raw.kARAAPIGeneration_2_0_Final;

pub const Error = error{
    InvalidStructSize,
    InvalidGeneration,
    MissingRequiredValue,
    InvalidBoolean,
    InvalidCountedPointer,
    InvalidContentType,
    DuplicateContentType,
    InvalidTransformationFlags,
};

pub fn implementsField(
    comptime T: type,
    value: *const T,
    comptime field_name: []const u8,
) bool {
    const end = @offsetOf(T, field_name) +
        @sizeOf(@FieldType(T, field_name));
    return value.structSize >= end;
}

pub fn validateConfiguration(
    configuration: *const raw.ARAInterfaceConfiguration,
) Error!void {
    if (configuration.structSize <
        raw.kARAInterfaceConfigurationMinSize)
        return error.InvalidStructSize;
    if (!validGeneration(configuration.desiredApiGeneration))
        return error.InvalidGeneration;
    if (configuration.assertFunctionAddress == null)
        return error.MissingRequiredValue;
}

pub fn validateFactory(factory: *const raw.ARAFactory) Error!void {
    if (factory.structSize < raw.kARAFactoryMinSize)
        return error.InvalidStructSize;
    if (!validGeneration(factory.lowestSupportedApiGeneration) or
        !validGeneration(factory.highestSupportedApiGeneration) or
        factory.lowestSupportedApiGeneration >
            factory.highestSupportedApiGeneration)
        return error.InvalidGeneration;
    if (factory.factoryID == null or
        factory.initializeARAWithConfiguration == null or
        factory.uninitializeARA == null or
        factory.plugInName == null or
        factory.manufacturerName == null or
        factory.informationURL == null or
        factory.version == null or
        factory.createDocumentControllerWithDocument == null or
        factory.documentArchiveID == null)
        return error.MissingRequiredValue;
    try validateCountedPointer(
        factory.compatibleDocumentArchiveIDsCount,
        factory.compatibleDocumentArchiveIDs,
    );
    try validateCountedPointer(
        factory.analyzeableContentTypesCount,
        factory.analyzeableContentTypes,
    );
    if (factory.analyzeableContentTypesCount > 0)
        try validateContentTypes(
            factory.analyzeableContentTypes[0..factory.analyzeableContentTypesCount],
        );
    const supported_transformations =
        raw.kARAPlaybackTransformationTimestretch |
        raw.kARAPlaybackTransformationTimestretchReflectingTempo |
        raw.kARAPlaybackTransformationContentBasedFades;
    if (factory.supportedPlaybackTransformationFlags &
        ~supported_transformations != 0)
        return error.InvalidTransformationFlags;
    if (implementsField(
        raw.ARAFactory,
        factory,
        "supportsStoringAudioFileChunks",
    ))
        try validateBoolean(factory.supportsStoringAudioFileChunks);
}

pub fn validateDocumentControllerInstance(
    instance: *const raw.ARADocumentControllerInstance,
) Error!void {
    if (instance.structSize < raw.kARADocumentControllerInstanceMinSize)
        return error.InvalidStructSize;
    if (instance.documentControllerRef == null or
        instance.documentControllerInterface == null)
        return error.MissingRequiredValue;
    const interface: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    if (interface.structSize < raw.kARADocumentControllerInterfaceMinSize)
        return error.InvalidStructSize;
    if (interface.destroyDocumentController == null or
        interface.getFactory == null or
        interface.beginEditing == null or
        interface.endEditing == null or
        interface.notifyModelUpdates == null or
        interface.createAudioSource == null or
        interface.destroyAudioSource == null or
        interface.createAudioModification == null or
        interface.destroyAudioModification == null or
        interface.createPlaybackRegion == null or
        interface.destroyPlaybackRegion == null or
        interface.destroyContentReader == null)
        return error.MissingRequiredValue;
}

pub fn validateContentTypes(
    content_types: []const raw.ARAContentType,
) Error!void {
    for (content_types, 0..) |content_type, index| {
        if (!validContentType(content_type))
            return error.InvalidContentType;
        for (content_types[0..index]) |previous| {
            if (content_type == previous)
                return error.DuplicateContentType;
        }
    }
}

pub fn validContentType(content_type: raw.ARAContentType) bool {
    return switch (content_type) {
        raw.kARAContentTypeNotes,
        raw.kARAContentTypeTempoEntries,
        raw.kARAContentTypeBarSignatures,
        raw.kARAContentTypeStaticTuning,
        raw.kARAContentTypeKeySignatures,
        raw.kARAContentTypeSheetChords,
        => true,
        else => false,
    };
}

pub fn validateBoolean(value: raw.ARABool) Error!void {
    if (value != raw.kARAFalse and value != raw.kARATrue)
        return error.InvalidBoolean;
}

fn validGeneration(generation: raw.ARAAPIGeneration) bool {
    return generation >= minimum_generation and
        generation <= current_generation;
}

fn validateCountedPointer(
    count: raw.ARASize,
    pointer: anytype,
) Error!void {
    if ((count == 0) != (pointer == null))
        return error.InvalidCountedPointer;
}

test "official ARA declarations expose generation 2.3" {
    try std.testing.expectEqual(
        @as(raw.ARAAPIGeneration, 6),
        current_generation,
    );
    try std.testing.expect(
        @sizeOf(raw.ARAFactory) >= raw.kARAFactoryMinSize,
    );
    try std.testing.expect(
        @sizeOf(raw.ARADocumentControllerInterface) >=
            raw.kARADocumentControllerInterfaceMinSize,
    );
    try std.testing.expect(
        implementsField(
            raw.ARAFactory,
            &std.mem.zeroes(raw.ARAFactory),
            "supportedPlaybackTransformationFlags",
        ) == false,
    );
}

test "ARA configuration validation requires a complete supported request" {
    var assert_function: raw.ARAAssertFunction = null;
    var configuration = std.mem.zeroes(raw.ARAInterfaceConfiguration);
    configuration.structSize = @sizeOf(raw.ARAInterfaceConfiguration);
    configuration.desiredApiGeneration = current_generation;
    configuration.assertFunctionAddress = &assert_function;
    try validateConfiguration(&configuration);

    configuration.desiredApiGeneration = current_generation + 1;
    try std.testing.expectError(
        error.InvalidGeneration,
        validateConfiguration(&configuration),
    );
    configuration.desiredApiGeneration = current_generation;
    configuration.assertFunctionAddress = null;
    try std.testing.expectError(
        error.MissingRequiredValue,
        validateConfiguration(&configuration),
    );
}

test "ARA content validation rejects unknown and duplicate declarations" {
    try validateContentTypes(&.{
        raw.kARAContentTypeNotes,
        raw.kARAContentTypeTempoEntries,
        raw.kARAContentTypeSheetChords,
    });
    try std.testing.expectError(
        error.DuplicateContentType,
        validateContentTypes(&.{
            raw.kARAContentTypeNotes,
            raw.kARAContentTypeNotes,
        }),
    );
    try std.testing.expectError(
        error.InvalidContentType,
        validateContentTypes(&.{999}),
    );
}
