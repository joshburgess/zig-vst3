const std = @import("std");
const ara = @import("zig-vst3-ara");
const controller_api = @import("ara_document_controller.zig");
const model_api = @import("ara_model.zig");

pub const raw = ara.raw;

pub const Error = controller_api.Error || error{
    InvalidConfiguration,
    AlreadyInitialized,
    NotInitialized,
    ControllerPoolExhausted,
    ControllerExtensionFailed,
    ActiveControllers,
};

pub fn Factory(
    comptime config: anytype,
    comptime limits: model_api.Limits,
    comptime controller_capacity: usize,
) type {
    if (controller_capacity == 0 or
        controller_capacity > std.math.maxInt(u16))
        @compileError(
            "ARA controller capacity must be between 1 and 65535",
        );
    validateFactoryString(config.factory_id, "factory_id");
    validateFactoryString(config.plugin_name, "plugin_name");
    validateFactoryString(
        config.manufacturer_name,
        "manufacturer_name",
    );
    validateFactoryString(
        config.information_url,
        "information_url",
    );
    validateFactoryString(config.version, "version");
    validateFactoryString(
        config.document_archive_id,
        "document_archive_id",
    );
    const analyzeable_content_types: []const raw.ARAContentType =
        if (@hasField(@TypeOf(config), "analyzeable_content_types"))
            config.analyzeable_content_types
        else
            &.{};
    for (analyzeable_content_types, 0..) |content_type, index| {
        if (!ara.validContentType(content_type))
            @compileError("invalid analyzeable ARA content type");
        for (analyzeable_content_types[0..index]) |previous| {
            if (previous == content_type)
                @compileError("duplicate analyzeable ARA content type");
        }
    }

    const ControllerType = controller_api.Controller(limits);
    const ControllerExtension =
        if (@hasField(@TypeOf(config), "controller_extension"))
            config.controller_extension.Type(ControllerType)
        else
            struct {
                fn init(controller: *ControllerType) @This() {
                    _ = controller;
                    return .{};
                }

                fn attach(self: *@This()) !void {
                    _ = self;
                }

                fn detach(self: *@This()) !void {
                    _ = self;
                }
            };

    return struct {
        const Self = @This();

        const Slot = struct {
            occupied: bool = false,
            controller: ControllerType = undefined,
            extension: ControllerExtension = undefined,
        };

        const State = struct {
            mutex: std.atomic.Mutex = .unlocked,
            initialized: bool = false,
            generation: raw.ARAAPIGeneration = 0,
            last_error: ?Error = null,
            slots: [controller_capacity]Slot = @splat(.{}),
        };

        var state: State = .{};

        pub const factory = raw.ARAFactory{
            .structSize = @sizeOf(raw.ARAFactory),
            .lowestSupportedApiGeneration = ara.minimum_generation,
            .highestSupportedApiGeneration = ara.current_generation,
            .factoryID = config.factory_id,
            .initializeARAWithConfiguration = initializeARAWithConfiguration,
            .uninitializeARA = uninitializeARA,
            .plugInName = config.plugin_name,
            .manufacturerName = config.manufacturer_name,
            .informationURL = config.information_url,
            .version = config.version,
            .createDocumentControllerWithDocument = createDocumentControllerWithDocument,
            .documentArchiveID = config.document_archive_id,
            .compatibleDocumentArchiveIDsCount = 0,
            .compatibleDocumentArchiveIDs = null,
            .analyzeableContentTypesCount = analyzeable_content_types.len,
            .analyzeableContentTypes = if (analyzeable_content_types.len == 0)
                null
            else
                analyzeable_content_types.ptr,
            .supportedPlaybackTransformationFlags = supportedTransformationFlags(config),
            .supportsStoringAudioFileChunks = raw.kARAFalse,
        };

        pub fn factoryPointer() *const raw.ARAFactory {
            return &factory;
        }

        pub fn takeLastError() ?Error {
            lockState();
            defer state.mutex.unlock();
            const result = state.last_error;
            state.last_error = null;
            return result;
        }

        pub fn activeControllerCount() usize {
            lockState();
            defer state.mutex.unlock();
            var count: usize = 0;
            for (&state.slots) |*slot| {
                if (slot.occupied) count += 1;
            }
            return count;
        }

        pub fn resetForTesting() void {
            if (!@import("builtin").is_test)
                @compileError("resetForTesting is only available in tests");
            lockState();
            defer state.mutex.unlock();
            state.initialized = false;
            state.generation = 0;
            state.last_error = null;
            for (&state.slots) |*slot| slot.occupied = false;
        }

        fn initializeARAWithConfiguration(
            configuration_pointer: [*c]const raw.ARAInterfaceConfiguration,
        ) callconv(.c) void {
            lockState();
            defer state.mutex.unlock();
            if (state.initialized) {
                state.last_error = error.AlreadyInitialized;
                return;
            }
            if (configuration_pointer == null) {
                state.last_error = error.InvalidConfiguration;
                return;
            }
            const configuration: *const raw.ARAInterfaceConfiguration =
                @ptrCast(configuration_pointer);
            ara.validateConfiguration(configuration) catch {
                state.last_error = error.InvalidConfiguration;
                return;
            };
            state.initialized = true;
            state.generation = configuration.desiredApiGeneration;
        }

        fn uninitializeARA() callconv(.c) void {
            lockState();
            defer state.mutex.unlock();
            if (!state.initialized) {
                state.last_error = error.NotInitialized;
                return;
            }
            for (&state.slots) |*slot| {
                if (slot.occupied) {
                    state.last_error = error.ActiveControllers;
                    return;
                }
            }
            state.initialized = false;
            state.generation = 0;
        }

        fn createDocumentControllerWithDocument(
            host_pointer: [*c]const raw.ARADocumentControllerHostInstance,
            properties_pointer: [*c]const raw.ARADocumentProperties,
        ) callconv(.c) [*c]const raw.ARADocumentControllerInstance {
            lockState();
            defer state.mutex.unlock();
            if (!state.initialized) {
                state.last_error = error.NotInitialized;
                return null;
            }
            if (host_pointer == null or properties_pointer == null) {
                state.last_error = error.InvalidProperties;
                return null;
            }
            const host: *const raw.ARADocumentControllerHostInstance =
                @ptrCast(host_pointer);
            const properties: *const raw.ARADocumentProperties =
                @ptrCast(properties_pointer);
            for (&state.slots) |*slot| {
                if (slot.occupied) continue;
                slot.occupied = true;
                slot.controller.initWithRelease(
                    &factory,
                    host,
                    properties,
                    @ptrCast(slot),
                    releaseController,
                ) catch |failure| {
                    slot.occupied = false;
                    state.last_error = failure;
                    return null;
                };
                slot.extension =
                    ControllerExtension.init(&slot.controller);
                slot.extension.attach() catch {
                    slot.extension.detach() catch {};
                    slot.occupied = false;
                    state.last_error =
                        error.ControllerExtensionFailed;
                    return null;
                };
                return slot.controller.documentControllerInstance();
            }
            state.last_error = error.ControllerPoolExhausted;
            return null;
        }

        fn releaseController(
            context: ?*anyopaque,
            controller: *ControllerType,
        ) void {
            const opaque_slot = context orelse return;
            const slot: *Slot = @ptrCast(@alignCast(opaque_slot));
            lockState();
            defer state.mutex.unlock();
            if (&slot.controller != controller or !slot.occupied) {
                state.last_error = error.InvalidController;
                return;
            }
            slot.extension.detach() catch {
                state.last_error = error.ControllerExtensionFailed;
            };
            slot.occupied = false;
        }

        fn lockState() void {
            while (!state.mutex.tryLock())
                std.atomic.spinLoopHint();
        }
    };
}

fn supportedTransformationFlags(
    comptime config: anytype,
) raw.ARAPlaybackTransformationFlags {
    if (@hasField(
        @TypeOf(config),
        "supported_playback_transformation_flags",
    ))
        return config.supported_playback_transformation_flags;
    return raw.kARAPlaybackTransformationNoChanges;
}

fn validateFactoryString(
    comptime value: anytype,
    comptime field_name: []const u8,
) void {
    if (value.len == 0)
        @compileError("ARA factory field " ++ field_name ++
            " must not be empty");
}

test "ARA factory validates and owns a bounded controller pool" {
    const TestFactory = Factory(.{
        .factory_id = "org.zig-vst3.ara.test.factory.v1",
        .plugin_name = "ARA Test",
        .manufacturer_name = "zig-vst3",
        .information_url = "https://example.invalid",
        .version = "1.0.0",
        .document_archive_id = "org.zig-vst3.ara.test.archive.v1",
    }, .{}, 1);
    TestFactory.resetForTesting();
    try ara.validateFactory(TestFactory.factoryPointer());

    var assert_function: raw.ARAAssertFunction = null;
    var configuration = raw.ARAInterfaceConfiguration{
        .structSize = @sizeOf(raw.ARAInterfaceConfiguration),
        .desiredApiGeneration = ara.current_generation,
        .assertFunctionAddress = &assert_function,
    };
    TestFactory.factory.initializeARAWithConfiguration.?(
        &configuration,
    );
    try std.testing.expect(TestFactory.takeLastError() == null);

    var host = testHost();
    var properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    const first =
        TestFactory.factory.createDocumentControllerWithDocument.?(
            &host,
            &properties,
        );
    try std.testing.expect(first != null);
    try std.testing.expectEqual(
        @as(usize, 1),
        TestFactory.activeControllerCount(),
    );
    const exhausted =
        TestFactory.factory.createDocumentControllerWithDocument.?(
            &host,
            &properties,
        );
    try std.testing.expect(exhausted == null);
    try std.testing.expectEqual(
        error.ControllerPoolExhausted,
        TestFactory.takeLastError().?,
    );

    const instance: *const raw.ARADocumentControllerInstance =
        @ptrCast(first);
    const controller_interface: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    controller_interface.destroyDocumentController.?(
        instance.documentControllerRef,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        TestFactory.activeControllerCount(),
    );
    TestFactory.factory.uninitializeARA.?();
    try std.testing.expect(TestFactory.takeLastError() == null);
}

test "ARA factory exports its validated analyzeable content types" {
    const TestFactory = Factory(.{
        .factory_id = "org.zig-vst3.ara.analysis.factory.v1",
        .plugin_name = "ARA Analysis Test",
        .manufacturer_name = "zig-vst3",
        .information_url = "https://example.invalid",
        .version = "1.0.0",
        .document_archive_id = "org.zig-vst3.ara.analysis.archive.v1",
        .analyzeable_content_types = &.{
            raw.kARAContentTypeNotes,
            raw.kARAContentTypeStaticTuning,
        },
    }, .{}, 1);

    try ara.validateFactory(TestFactory.factoryPointer());
    try std.testing.expectEqual(
        @as(usize, 2),
        TestFactory.factory.analyzeableContentTypesCount,
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeNotes,
        TestFactory.factory.analyzeableContentTypes[0],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeStaticTuning,
        TestFactory.factory.analyzeableContentTypes[1],
    );
}

test "ARA factory owns controller extension lifecycle" {
    const ExtensionDefinition = struct {
        pub fn Type(comptime ControllerType: type) type {
            return struct {
                var attach_count: usize = 0;
                var detach_count: usize = 0;
                controller: *ControllerType,

                fn init(controller: *ControllerType) @This() {
                    return .{ .controller = controller };
                }

                fn attach(self: *@This()) !void {
                    _ = self.controller;
                    @This().attach_count += 1;
                }

                fn detach(self: *@This()) !void {
                    _ = self.controller;
                    @This().detach_count += 1;
                }
            };
        }
    };
    const TestExtension =
        ExtensionDefinition.Type(controller_api.Controller(.{}));
    const TestFactory = Factory(.{
        .factory_id = "org.zig-vst3.ara.extension.factory.v1",
        .plugin_name = "ARA Extension Test",
        .manufacturer_name = "zig-vst3",
        .information_url = "https://example.invalid",
        .version = "1.0.0",
        .document_archive_id = "org.zig-vst3.ara.extension.archive.v1",
        .controller_extension = ExtensionDefinition,
    }, .{}, 1);
    TestFactory.resetForTesting();
    TestExtension.attach_count = 0;
    TestExtension.detach_count = 0;

    var assert_function: raw.ARAAssertFunction = null;
    var configuration = raw.ARAInterfaceConfiguration{
        .structSize = @sizeOf(raw.ARAInterfaceConfiguration),
        .desiredApiGeneration = ara.current_generation,
        .assertFunctionAddress = &assert_function,
    };
    TestFactory.factory.initializeARAWithConfiguration.?(
        &configuration,
    );
    var host = testHost();
    var properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    const instance_pointer =
        TestFactory.factory.createDocumentControllerWithDocument.?(
            &host,
            &properties,
        );
    try std.testing.expect(instance_pointer != null);
    try std.testing.expectEqual(
        @as(usize, 1),
        TestExtension.attach_count,
    );
    const instance: *const raw.ARADocumentControllerInstance =
        @ptrCast(instance_pointer);
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    api.destroyDocumentController.?(
        instance.documentControllerRef,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        TestExtension.detach_count,
    );
    TestFactory.factory.uninitializeARA.?();
    try std.testing.expect(TestFactory.takeLastError() == null);
}

fn testHost() raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio = raw.ARAAudioAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
        };
        const archive = raw.ARAArchivingControllerInterface{
            .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
        };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
        };
        const model_update = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
        };
        const playback = raw.ARAPlaybackControllerInterface{
            .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
        };
    };
    return .{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerInterface = &Host.audio,
        .archivingControllerInterface = &Host.archive,
        .contentAccessControllerInterface = &Host.content,
        .modelUpdateControllerInterface = &Host.model_update,
        .playbackControllerInterface = &Host.playback,
    };
}
