const std = @import("std");
const midi_ci = @import("midi_ci.zig");
const process = @import("midi_ci_process.zig");
const profile = @import("midi_ci_profile.zig");
const profile_host = @import("midi_ci_profile_host.zig");
const property = @import("midi_ci_property.zig");
const property_cache = @import("midi_ci_property_cache.zig");
const property_host = @import("midi_ci_property_host.zig");
const property_json = @import("midi_ci_property_json.zig");
const property_session = @import("midi_ci_property_session.zig");

pub const Config = struct {
    remote_capacity: usize = 8,
    profile_capacity: usize = 32,
    profile_details_capacity: usize = 256,
    property_session_capacity: usize = 8,
    subscription_capacity: usize = 8,
    property_cache_capacity: usize = 8,
    property_header_capacity: usize = 256,
    property_data_capacity: usize = 4096,
};

pub const Options = struct {
    participant: midi_ci.Participant,
    output_path: u7 = 0,
    function_block: ?u5 = null,
    product_instance_id: midi_ci.ProductInstanceId = .{},
    process_features: process.Features = .{},
    simultaneous_property_requests: u7 = 8,
    property_exchange_major: u7 = property.current_property_exchange_major,
    property_exchange_minor: u7 = property.current_property_exchange_minor,
};

pub const ProfileState = struct {
    address: midi_ci.Address,
    id: profile.Id,
    enabled: bool,
    channels: u14 = 0,
};

pub const Remote = struct {
    participant: midi_ci.Participant,
    output_path: u7,
    function_block: ?u5,
    product_instance_id: ?midi_ci.ProductInstanceId,
    property_agreement: ?property.Agreement,
    process_features: ?process.Features,
    profiles: []const ProfileState,
};

pub const Cleanup = struct {
    remotes: usize = 0,
    property_requests: usize = 0,
    property_responses: usize = 0,
    subscriptions: usize = 0,
    cached_properties: usize = 0,

    fn add(self: *Cleanup, other: Cleanup) void {
        self.remotes += other.remotes;
        self.property_requests += other.property_requests;
        self.property_responses += other.property_responses;
        self.subscriptions += other.subscriptions;
        self.cached_properties += other.cached_properties;
    }
};

pub const InvalidationResult = union(enum) {
    ignored,
    remote: Cleanup,
    local: Cleanup,
};

pub const DiscoveryResult = struct {
    handle: u7,
    reply: midi_ci.Message,
};

pub const PropertyCompletion = struct {
    request_id: u7,
    status: property_json.ReplyStatus,
    cached: bool,
};

pub const PropertyUpdate = union(enum) {
    more: u7,
    complete: PropertyCompletion,
    aborted: u7,
    timeout_wait: u7,
    terminated: u7,
    timed_out: u7,
};

pub fn Device(comptime config: Config) type {
    validateConfig(config);
    const PropertyInitiator = property_session.Initiator(
        config.property_session_capacity,
        config.property_header_capacity,
        config.property_data_capacity,
    );
    const PropertyResponder = property_session.Responder(
        config.property_session_capacity,
        config.property_header_capacity,
        config.property_data_capacity,
    );
    const Subscriptions = property_session.SubscriptionRegistry(
        config.subscription_capacity,
    );
    const PropertyCache = property_cache.RemoteCache(
        config.property_cache_capacity,
        36,
        36,
        config.property_data_capacity,
    );

    return struct {
        const Self = @This();

        const RemoteSlot = struct {
            active: bool = false,
            participant: midi_ci.Participant = undefined,
            output_path: u7 = 0,
            function_block: ?u5 = null,
            product_instance_id: ?midi_ci.ProductInstanceId = null,
            property_agreement: ?property.Agreement = null,
            process_features: ?process.Features = null,
            profile_storage: [config.profile_capacity]ProfileState = undefined,
            profile_count: usize = 0,

            fn value(self: *const RemoteSlot) Remote {
                return .{
                    .participant = self.participant,
                    .output_path = self.output_path,
                    .function_block = self.function_block,
                    .product_instance_id = self.product_instance_id,
                    .property_agreement = self.property_agreement,
                    .process_features = self.process_features,
                    .profiles = self.profile_storage[0..self.profile_count],
                };
            }
        };

        const PendingProperty = struct {
            active: bool = false,
            remote: midi_ci.Muid = .{ .value = 0 },
            resource_storage: [36]u8 = undefined,
            resource_count: usize = 0,
            has_res_id: bool = false,
            res_id_storage: [36]u8 = undefined,
            res_id_count: usize = 0,

            fn key(self: *const PendingProperty) !property_cache.Key {
                if (!self.active or
                    !self.remote.validSource() or
                    self.resource_count == 0 or
                    self.resource_count > self.resource_storage.len or
                    self.res_id_count > self.res_id_storage.len)
                    return error.InvalidMidiCiPropertyGetRequest;
                return .{
                    .remote = self.remote,
                    .resource = self.resource_storage[0..self.resource_count],
                    .res_id = if (self.has_res_id)
                        self.res_id_storage[0..self.res_id_count]
                    else
                        null,
                };
            }
        };

        pub const PropertyDataMessage = PropertyInitiator.DataMessage;

        participant: midi_ci.Participant,
        output_path: u7,
        function_block: ?u5,
        product_instance_id: midi_ci.ProductInstanceId,
        process_features: process.Features,
        simultaneous_property_requests: u7,
        property_exchange_major: u7,
        property_exchange_minor: u7,
        remotes: [config.remote_capacity]RemoteSlot =
            [_]RemoteSlot{.{}} ** config.remote_capacity,
        remote_count: usize = 0,
        property_initiator: PropertyInitiator,
        property_responder: PropertyResponder,
        subscriptions: Subscriptions = .{},
        property_cache: PropertyCache = .{},
        pending_properties: [config.property_session_capacity]PendingProperty =
            [_]PendingProperty{.{}} ** config.property_session_capacity,
        local_profiles: [config.profile_capacity]profile_host.Entry = undefined,
        local_profile_count: usize = 0,

        pub fn init(options: Options) !Self {
            if (!options.participant.valid())
                return error.InvalidMidiCiParticipant;
            if (options.participant.version == 1 and
                (options.output_path != 0 or options.function_block != null))
                return error.UnsupportedMidiCiVersionField;
            if (options.simultaneous_property_requests == 0)
                return error.InvalidMidiCiPropertyCapabilities;
            if (!options.product_instance_id.valid())
                return error.InvalidMidiCiProductInstanceId;
            if (!options.process_features.valid())
                return error.InvalidMidiCiProcessInquiryFeatures;
            if (options.participant.version == 1 and
                (options.property_exchange_major != 0 or
                    options.property_exchange_minor != 0))
                return error.UnsupportedMidiCiVersionField;
            return .{
                .participant = options.participant,
                .output_path = options.output_path,
                .function_block = options.function_block,
                .product_instance_id = options.product_instance_id,
                .process_features = options.process_features,
                .simultaneous_property_requests = options.simultaneous_property_requests,
                .property_exchange_major = options.property_exchange_major,
                .property_exchange_minor = options.property_exchange_minor,
                .property_initiator = try PropertyInitiator.init(
                    options.participant.muid,
                    options.participant.version,
                ),
                .property_responder = try PropertyResponder.init(
                    options.participant.muid,
                ),
            };
        }

        pub fn discovery(self: *const Self) midi_ci.Message {
            return .{ .discovery = .{
                .participant = self.participant,
                .output_path = self.output_path,
            } };
        }

        pub fn acceptDiscoveryReply(
            self: *Self,
            message: midi_ci.Message,
        ) !u7 {
            const transaction = try midi_ci.DiscoveryTransaction.init(
                self.participant,
                self.output_path,
            );
            const reply = try transaction.accept(message);
            return self.upsertRemote(
                reply.participant,
                reply.output_path,
                reply.function_block,
            );
        }

        pub fn handleDiscovery(
            self: *Self,
            message: midi_ci.Message,
        ) !DiscoveryResult {
            const discovery_value = switch (message) {
                .discovery => |value| value,
                .reply => return error.UnexpectedMidiCiReply,
            };
            const responder = try midi_ci.DiscoveryResponder.init(
                self.participant,
                self.function_block,
            );
            const reply = try responder.handle(message);
            const handle = try self.upsertRemote(
                discovery_value.participant,
                discovery_value.output_path,
                null,
            );
            return .{ .handle = handle, .reply = reply };
        }

        pub fn remote(self: *const Self, handle: u7) !Remote {
            return (try self.remoteSlot(handle)).value();
        }

        pub fn remoteCount(self: *const Self) usize {
            return self.remote_count;
        }

        pub fn findRemote(
            self: *const Self,
            muid: midi_ci.Muid,
        ) ?u7 {
            for (self.remotes, 0..) |slot, index| {
                if (slot.active and
                    slot.participant.muid.value == muid.value)
                    return @intCast(index);
            }
            return null;
        }

        pub fn endpointInformationInquiry(
            self: *const Self,
            handle: u7,
        ) !midi_ci.EndpointInformationMessage {
            const slot = try self.remoteSlot(handle);
            const transaction = try midi_ci.EndpointInformationTransaction.init(
                self.participant.muid,
                slot.participant.muid,
            );
            return transaction.inquiry();
        }

        pub fn handleEndpointInformation(
            self: *const Self,
            message: midi_ci.EndpointInformationMessage,
        ) !midi_ci.EndpointInformationMessage {
            const responder = try midi_ci.EndpointInformationResponder.init(
                self.participant.muid,
                self.product_instance_id,
            );
            return responder.handle(message);
        }

        pub fn acceptEndpointInformation(
            self: *Self,
            handle: u7,
            message: midi_ci.EndpointInformationMessage,
        ) !void {
            const slot = try self.mutableRemoteSlot(handle);
            const transaction = try midi_ci.EndpointInformationTransaction.init(
                self.participant.muid,
                slot.participant.muid,
            );
            const reply = try transaction.accept(message);
            slot.product_instance_id = reply.product_instance_id;
        }

        pub fn propertyCapabilitiesInquiry(
            self: *const Self,
            handle: u7,
        ) !property.Message {
            const slot = try self.remoteSlot(handle);
            try self.requireCategory(slot, .property_exchange);
            const transaction = try property.Transaction.init(
                self.localPropertyCapabilities(slot.participant.muid),
            );
            return transaction.inquiry();
        }

        pub fn handlePropertyCapabilities(
            self: *const Self,
            message: property.Message,
        ) !property.Message {
            if (!self.participant.categories.property_exchange)
                return error.MidiCiPropertyExchangeNotSupported;
            const inquiry = switch (message) {
                .inquiry => |value| value,
                .reply => return error.UnexpectedMidiCiPropertyReply,
            };
            const responder = try property.Responder.init(
                self.localPropertyCapabilities(inquiry.source),
            );
            return responder.handle(message);
        }

        pub fn propertyHost(
            self: *Self,
            delegate: anytype,
        ) !property_host.BorrowedHost(
            PropertyResponder,
            Subscriptions,
            @TypeOf(delegate.*),
            config.property_header_capacity,
        ) {
            if (!self.participant.categories.property_exchange)
                return error.MidiCiPropertyExchangeNotSupported;
            return property_host.borrowed(
                config.property_header_capacity,
                &self.property_responder,
                &self.subscriptions,
                delegate,
            );
        }

        pub fn profileHost(
            self: *Self,
            delegate: anytype,
        ) !profile_host.BorrowedHost(
            config.profile_capacity,
            config.profile_details_capacity,
            @TypeOf(delegate.*),
        ) {
            if (!self.participant.categories.profile_configuration)
                return error.MidiCiProfileConfigurationNotSupported;
            return .{
                .source = self.participant.muid,
                .version = self.participant.version,
                .entries = &self.local_profiles,
                .count = &self.local_profile_count,
                .delegate = delegate,
            };
        }

        pub fn acceptPropertyCapabilities(
            self: *Self,
            handle: u7,
            message: property.Message,
        ) !property.Agreement {
            const slot = try self.mutableRemoteSlot(handle);
            try self.requireCategory(slot, .property_exchange);
            const transaction = try property.Transaction.init(
                self.localPropertyCapabilities(slot.participant.muid),
            );
            const agreement = try transaction.accept(message);
            slot.property_agreement = agreement;
            return agreement;
        }

        pub fn beginPropertyGet(
            self: *Self,
            handle: u7,
            header: property_json.RequestHeader,
        ) !PropertyDataMessage {
            const slot = try self.remoteSlot(handle);
            try self.requireCategory(slot, .property_exchange);
            const agreement = slot.property_agreement orelse
                return error.MidiCiPropertyCapabilitiesRequired;
            if (!agreement.property_exchange_compatible)
                return error.IncompatibleMidiCiPropertyExchange;
            if (!header.valid())
                return error.InvalidMidiCiPropertyRequestHeader;
            if (header.pagination != null)
                return error.MidiCiPropertyCachePaginationUnsupported;

            var header_storage: [config.property_header_capacity]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&header_storage);
            try header.writeJson(&writer);
            const message = try self.property_initiator.begin(
                .get,
                slot.participant.muid,
                writer.buffered(),
                1,
                &.{},
            );
            var pending = PendingProperty{
                .active = true,
                .remote = slot.participant.muid,
                .resource_count = header.resource.len,
                .has_res_id = header.res_id != null,
                .res_id_count = if (header.res_id) |value| value.len else 0,
            };
            @memcpy(
                pending.resource_storage[0..header.resource.len],
                header.resource,
            );
            if (header.res_id) |value|
                @memcpy(pending.res_id_storage[0..value.len], value);
            self.pending_properties[message.request_id] = pending;
            return message;
        }

        pub fn acceptPropertyGet(
            self: *Self,
            allocator: std.mem.Allocator,
            message: anytype,
        ) !PropertyUpdate {
            return switch (try self.property_initiator.accept(message)) {
                .more => |request_id| .{ .more = request_id },
                .complete => |request_id| .{
                    .complete = try self.finishPropertyGet(
                        allocator,
                        request_id,
                    ),
                },
                .aborted => |request_id| result: {
                    try self.property_initiator.release(request_id);
                    self.pending_properties[request_id] = .{};
                    break :result .{ .aborted = request_id };
                },
                else => error.InvalidMidiCiPropertyGetState,
            };
        }

        pub fn acceptPropertyGetNotify(
            self: *Self,
            message: anytype,
            status: property_json.NotifyStatus,
        ) !PropertyUpdate {
            return switch (try self.property_initiator.acceptNotify(
                message,
                status,
            )) {
                .timeout_wait => |request_id| .{ .timeout_wait = request_id },
                .terminated => |request_id| result: {
                    self.pending_properties[request_id] = .{};
                    break :result .{ .terminated = request_id };
                },
                .timed_out => |request_id| result: {
                    self.pending_properties[request_id] = .{};
                    break :result .{ .timed_out = request_id };
                },
                else => error.InvalidMidiCiPropertyGetState,
            };
        }

        pub fn finishPropertyGet(
            self: *Self,
            allocator: std.mem.Allocator,
            request_id: u7,
        ) !PropertyCompletion {
            if (request_id >= config.property_session_capacity or
                !self.pending_properties[request_id].active)
                return error.InvalidMidiCiPropertyGetRequest;
            const response =
                try self.property_initiator.response(request_id);
            if (response.aborted)
                return error.MidiCiPropertyResponseAborted;
            const parsed = try property_json.ReplyHeader.parseJson(
                allocator,
                response.header(),
            );
            defer parsed.deinit();
            const cached = parsed.value.status == .ok;
            if (cached) {
                _ = try self.property_cache.put(
                    try self.pending_properties[request_id].key(),
                    response.data(),
                );
            }
            try self.property_initiator.release(request_id);
            self.pending_properties[request_id] = .{};
            return .{
                .request_id = request_id,
                .status = parsed.value.status,
                .cached = cached,
            };
        }

        pub fn cachedProperty(
            self: *const Self,
            handle: u7,
            resource: []const u8,
            res_id: ?[]const u8,
        ) !property_cache.Entry {
            const slot = try self.remoteSlot(handle);
            return self.property_cache.get(.{
                .remote = slot.participant.muid,
                .resource = resource,
                .res_id = res_id,
            });
        }

        pub fn propertyCacheSnapshotSize(self: *const Self) !usize {
            return self.property_cache.snapshotSize();
        }

        pub fn writePropertyCacheSnapshot(
            self: *const Self,
            destination: []u8,
        ) ![]const u8 {
            return self.property_cache.writeSnapshot(destination);
        }

        pub fn restorePropertyCacheSnapshot(
            self: *Self,
            source: []const u8,
        ) !void {
            try self.property_cache.restoreSnapshot(source);
        }

        pub fn clearPropertyCache(self: *Self) void {
            self.property_cache.clear();
        }

        pub fn processInquiry(
            self: *const Self,
            handle: u7,
        ) !process.Message {
            const slot = try self.remoteSlot(handle);
            try self.requireCategory(slot, .process_inquiry);
            const transaction = try process.Transaction.init(
                self.participant.muid,
                slot.participant.muid,
            );
            return transaction.inquiry();
        }

        pub fn handleProcessInquiry(
            self: *const Self,
            message: process.Message,
        ) !process.Message {
            if (!self.participant.categories.process_inquiry)
                return error.MidiCiProcessInquiryNotSupported;
            const responder = try process.Responder.init(
                self.participant.muid,
                self.process_features,
            );
            return responder.handle(message);
        }

        pub fn acceptProcessInquiry(
            self: *Self,
            handle: u7,
            message: process.Message,
        ) !process.Features {
            const slot = try self.mutableRemoteSlot(handle);
            try self.requireCategory(slot, .process_inquiry);
            const transaction = try process.Transaction.init(
                self.participant.muid,
                slot.participant.muid,
            );
            const reply = try transaction.accept(message);
            slot.process_features = reply.features;
            return reply.features;
        }

        pub fn profileInquiry(
            self: *const Self,
            handle: u7,
            address: midi_ci.Address,
        ) !profile.Inquiry {
            const slot = try self.remoteSlot(handle);
            try self.requireCategory(slot, .profile_configuration);
            const inquiry = profile.Inquiry{
                .address = address,
                .version = @min(self.participant.version, slot.participant.version),
                .source = self.participant.muid,
                .destination = slot.participant.muid,
            };
            if (!inquiry.valid()) return error.InvalidMidiCiProfileInquiry;
            return inquiry;
        }

        pub fn applyProfileReply(
            self: *Self,
            handle: u7,
            reply: anytype,
        ) !void {
            const slot = try self.mutableRemoteSlot(handle);
            try self.requireCategory(slot, .profile_configuration);
            if (!reply.valid()) return error.InvalidMidiCiProfileReply;
            if (reply.source.value != slot.participant.muid.value or
                reply.destination.value != self.participant.muid.value)
                return error.MidiCiProfileReplyMismatch;
            const incoming = reply.enabled.slice().len +
                reply.disabled.slice().len;
            var retained: usize = 0;
            for (slot.profile_storage[0..slot.profile_count]) |state| {
                if (!std.meta.eql(state.address, reply.address))
                    retained += 1;
            }
            if (retained + incoming > config.profile_capacity)
                return error.MidiCiDeviceProfileCapacityExceeded;

            var next: usize = 0;
            for (slot.profile_storage[0..slot.profile_count]) |state| {
                if (!std.meta.eql(state.address, reply.address)) {
                    slot.profile_storage[next] = state;
                    next += 1;
                }
            }
            for (reply.enabled.slice()) |id| {
                slot.profile_storage[next] = .{
                    .address = reply.address,
                    .id = id,
                    .enabled = true,
                };
                next += 1;
            }
            for (reply.disabled.slice()) |id| {
                slot.profile_storage[next] = .{
                    .address = reply.address,
                    .id = id,
                    .enabled = false,
                };
                next += 1;
            }
            slot.profile_count = next;
        }

        pub fn applyProfileReport(
            self: *Self,
            handle: u7,
            report: profile.Report,
        ) !void {
            if (!report.valid()) return error.InvalidMidiCiProfileReport;
            const slot = try self.mutableRemoteSlot(handle);
            try self.requireCategory(slot, .profile_configuration);
            if (report.source.value != slot.participant.muid.value)
                return error.MidiCiProfileReportMismatch;
            try setProfileState(
                slot,
                report.address,
                report.profile,
                report.kind == .enabled,
                report.channels,
            );
        }

        pub fn applyProfilePresence(
            self: *Self,
            handle: u7,
            presence: profile.Presence,
        ) !void {
            if (!presence.valid()) return error.InvalidMidiCiProfilePresence;
            const slot = try self.mutableRemoteSlot(handle);
            try self.requireCategory(slot, .profile_configuration);
            if (presence.source.value != slot.participant.muid.value)
                return error.MidiCiProfilePresenceMismatch;
            if (presence.kind == .removed) {
                removeProfileState(slot, presence.address, presence.profile);
            } else {
                try setProfileState(
                    slot,
                    presence.address,
                    presence.profile,
                    false,
                    0,
                );
            }
        }

        pub fn removeRemote(
            self: *Self,
            muid: midi_ci.Muid,
        ) !Cleanup {
            const handle = self.findRemote(muid) orelse
                return error.MidiCiDeviceRemoteNotFound;
            return self.removeRemoteHandle(handle);
        }

        pub fn acceptInvalidation(
            self: *Self,
            invalidation: midi_ci.Invalidation,
        ) !InvalidationResult {
            if (!invalidation.valid())
                return error.InvalidMidiCiInvalidation;
            if (invalidation.target.value == self.participant.muid.value)
                return .{ .local = self.removeAllRemotes() };
            const handle = self.findRemote(invalidation.target) orelse
                return .ignored;
            return .{ .remote = self.removeRemoteHandle(handle) };
        }

        fn localPropertyCapabilities(
            self: *const Self,
            destination: midi_ci.Muid,
        ) property.Capabilities {
            return .{
                .version = self.participant.version,
                .source = self.participant.muid,
                .destination = destination,
                .simultaneous_requests = self.simultaneous_property_requests,
                .property_exchange_major = self.property_exchange_major,
                .property_exchange_minor = self.property_exchange_minor,
            };
        }

        fn upsertRemote(
            self: *Self,
            participant: midi_ci.Participant,
            output_path: u7,
            function_block: ?u5,
        ) !u7 {
            if (!participant.valid() or
                participant.muid.value == self.participant.muid.value)
                return error.InvalidMidiCiParticipant;
            if (self.findRemote(participant.muid)) |handle| {
                const slot = &self.remotes[handle];
                if (!std.meta.eql(slot.participant, participant)) {
                    _ = self.property_initiator.releaseRemote(participant.muid);
                    _ = self.property_responder.releaseRemote(participant.muid);
                    _ = self.subscriptions.releaseRemote(participant.muid);
                    _ = self.property_cache.releaseRemote(participant.muid);
                    self.clearPendingProperties(participant.muid);
                    slot.product_instance_id = null;
                    slot.property_agreement = null;
                    slot.process_features = null;
                    slot.profile_count = 0;
                }
                slot.participant = participant;
                slot.output_path = output_path;
                slot.function_block = function_block;
                return handle;
            }
            for (&self.remotes, 0..) |*slot, index| {
                if (!slot.active) {
                    slot.* = .{
                        .active = true,
                        .participant = participant,
                        .output_path = output_path,
                        .function_block = function_block,
                    };
                    self.remote_count += 1;
                    return @intCast(index);
                }
            }
            return error.MidiCiDeviceRemoteCapacityExceeded;
        }

        fn removeRemoteHandle(self: *Self, handle: u7) Cleanup {
            const remote_muid = self.remotes[handle].participant.muid;
            self.remotes[handle] = .{};
            self.remote_count -= 1;
            self.clearPendingProperties(remote_muid);
            return .{
                .remotes = 1,
                .property_requests = self.property_initiator.releaseRemote(remote_muid),
                .property_responses = self.property_responder.releaseRemote(remote_muid),
                .subscriptions = self.subscriptions.releaseRemote(remote_muid),
                .cached_properties = self.property_cache.releaseRemote(remote_muid),
            };
        }

        fn removeAllRemotes(self: *Self) Cleanup {
            var cleanup = Cleanup{};
            for (0..config.remote_capacity) |index| {
                if (self.remotes[index].active)
                    cleanup.add(self.removeRemoteHandle(@intCast(index)));
            }
            return cleanup;
        }

        fn clearPendingProperties(
            self: *Self,
            remote_muid: midi_ci.Muid,
        ) void {
            for (&self.pending_properties) |*pending| {
                if (pending.active and
                    pending.remote.value == remote_muid.value)
                    pending.* = .{};
            }
        }

        fn remoteSlot(
            self: *const Self,
            handle: u7,
        ) !*const RemoteSlot {
            if (handle >= config.remote_capacity or
                !self.remotes[handle].active)
                return error.InvalidMidiCiDeviceRemoteHandle;
            return &self.remotes[handle];
        }

        const Category = enum {
            profile_configuration,
            property_exchange,
            process_inquiry,
        };

        fn requireCategory(
            self: *const Self,
            slot: *const RemoteSlot,
            category: Category,
        ) !void {
            const supported = switch (category) {
                .profile_configuration => self.participant.categories.profile_configuration and
                    slot.participant.categories.profile_configuration,
                .property_exchange => self.participant.categories.property_exchange and
                    slot.participant.categories.property_exchange,
                .process_inquiry => self.participant.categories.process_inquiry and
                    slot.participant.categories.process_inquiry,
            };
            if (!supported) return switch (category) {
                .profile_configuration => error.MidiCiProfileConfigurationNotSupported,
                .property_exchange => error.MidiCiPropertyExchangeNotSupported,
                .process_inquiry => error.MidiCiProcessInquiryNotSupported,
            };
        }

        fn mutableRemoteSlot(
            self: *Self,
            handle: u7,
        ) !*RemoteSlot {
            if (handle >= config.remote_capacity or
                !self.remotes[handle].active)
                return error.InvalidMidiCiDeviceRemoteHandle;
            return &self.remotes[handle];
        }

        fn setProfileState(
            slot: *RemoteSlot,
            address: midi_ci.Address,
            id: profile.Id,
            enabled: bool,
            channels: u14,
        ) !void {
            for (slot.profile_storage[0..slot.profile_count]) |*state| {
                if (std.meta.eql(state.address, address) and
                    std.meta.eql(state.id, id))
                {
                    state.enabled = enabled;
                    state.channels = channels;
                    return;
                }
            }
            if (slot.profile_count >= config.profile_capacity)
                return error.MidiCiDeviceProfileCapacityExceeded;
            slot.profile_storage[slot.profile_count] = .{
                .address = address,
                .id = id,
                .enabled = enabled,
                .channels = channels,
            };
            slot.profile_count += 1;
        }

        fn removeProfileState(
            slot: *RemoteSlot,
            address: midi_ci.Address,
            id: profile.Id,
        ) void {
            for (slot.profile_storage[0..slot.profile_count], 0..) |state, index| {
                if (!std.meta.eql(state.address, address) or
                    !std.meta.eql(state.id, id))
                    continue;
                const remaining = slot.profile_count - index - 1;
                if (remaining != 0) {
                    std.mem.copyForwards(
                        ProfileState,
                        slot.profile_storage[index .. index + remaining],
                        slot.profile_storage[index + 1 .. index + 1 + remaining],
                    );
                }
                slot.profile_count -= 1;
                return;
            }
        }
    };
}

fn validateConfig(comptime config: Config) void {
    if (config.remote_capacity == 0 or config.remote_capacity > 127)
        @compileError("MIDI-CI device remote capacity must be 1 through 127");
    if (config.profile_capacity == 0)
        @compileError("MIDI-CI device profile capacity must be nonzero");
    if (config.profile_details_capacity > 0x3FFF)
        @compileError("MIDI-CI device Profile Details capacity exceeds u14");
}

fn testParticipant(value: u32) !midi_ci.Participant {
    return .{
        .muid = try midi_ci.Muid.init(value),
        .identity = .{
            .manufacturer = .{ 1, 2, 3 },
            .family = .{ 4, 5 },
            .model = .{ 6, 7 },
            .revision = .{ 1, 0, 0, 0 },
        },
        .categories = .{
            .profile_configuration = true,
            .property_exchange = true,
            .process_inquiry = true,
        },
    };
}

const DeviceTestPropertyDelegate = struct {
    get_count: usize = 0,

    pub fn getData(
        self: *DeviceTestPropertyDelegate,
        request: property_host.Request,
    ) !property_host.Reply {
        self.get_count += 1;
        if (!std.mem.eql(u8, request.header.resource, "LocalState"))
            return .{ .header = .{ .status = .not_found } };
        return .{
            .header = .{ .status = .ok },
            .data = "{\"enabled\":true}",
        };
    }

    pub fn setData(
        _: *DeviceTestPropertyDelegate,
        _: property_host.Request,
    ) !property_host.Reply {
        return .{ .header = .{ .status = .not_allowed } };
    }

    pub fn subscriptionChanged(
        _: *DeviceTestPropertyDelegate,
        _: property_host.SubscriptionRequest,
    ) !property_host.Reply {
        return .{ .header = .{ .status = .not_allowed } };
    }
};

const DeviceTestProfileDelegate = struct {
    enablement_requests: usize = 0,

    pub fn profileEnablementRequested(
        self: *DeviceTestProfileDelegate,
        request: profile.Set,
    ) !bool {
        _ = request;
        self.enablement_requests += 1;
        return true;
    }

    pub fn profileDetails(
        _: *DeviceTestProfileDelegate,
        _: profile.DetailsInquiry,
    ) ![]const u8 {
        return &.{ 1, 2 };
    }

    pub fn profileSpecificData(
        _: *DeviceTestProfileDelegate,
        _: profile_host.SpecificDataRequest,
    ) !void {}
};

test "MIDI-CI device composes discovery capabilities profiles and cleanup" {
    const LocalDevice = Device(.{
        .remote_capacity = 2,
        .profile_capacity = 4,
        .property_session_capacity = 2,
        .subscription_capacity = 2,
        .property_header_capacity = 64,
        .property_data_capacity = 128,
    });
    const local_participant = try testParticipant(1);
    const remote_participant = try testParticipant(2);
    var device = try LocalDevice.init(.{
        .participant = local_participant,
        .output_path = 3,
        .function_block = 4,
        .product_instance_id = try midi_ci.ProductInstanceId.init("local-1"),
        .process_features = .{ .midi_message_report = true },
        .simultaneous_property_requests = 2,
    });

    const discovery_result = try device.handleDiscovery(.{ .discovery = .{
        .participant = remote_participant,
        .output_path = 3,
    } });
    try std.testing.expectEqual(@as(u7, 0), discovery_result.handle);
    try std.testing.expectEqual(@as(usize, 1), device.remoteCount());
    try std.testing.expectEqual(
        local_participant.muid.value,
        discovery_result.reply.reply.participant.muid.value,
    );

    try device.acceptEndpointInformation(
        discovery_result.handle,
        .{ .reply = .{
            .source = remote_participant.muid,
            .destination = local_participant.muid,
            .product_instance_id = try midi_ci.ProductInstanceId.init("remote-2"),
        } },
    );
    const property_inquiry =
        try device.propertyCapabilitiesInquiry(discovery_result.handle);
    const property_responder = try property.Responder.init(.{
        .source = remote_participant.muid,
        .destination = local_participant.muid,
        .simultaneous_requests = 1,
        .property_exchange_major = 1,
        .property_exchange_minor = 1,
    });
    const agreement = try device.acceptPropertyCapabilities(
        discovery_result.handle,
        try property_responder.handle(property_inquiry),
    );
    try std.testing.expect(agreement.property_exchange_compatible);
    try std.testing.expectEqual(@as(u7, 1), agreement.simultaneous_requests);
    const property_get = try device.beginPropertyGet(
        discovery_result.handle,
        .{ .resource = "DeviceInfo" },
    );
    const property_get_reply = try property.DataMessage(64, 128).init(
        .get_reply,
        2,
        remote_participant.muid,
        local_participant.muid,
        property_get.request_id,
        "{\"status\":200}",
        1,
        1,
        "{\"manufacturer\":\"Remote\"}",
    );
    const property_update = try device.acceptPropertyGet(
        std.testing.allocator,
        property_get_reply,
    );
    try std.testing.expect(property_update.complete.cached);
    try std.testing.expectEqualStrings(
        "{\"manufacturer\":\"Remote\"}",
        (try device.property_cache.get(.{
            .remote = remote_participant.muid,
            .resource = "DeviceInfo",
        })).data,
    );
    const cancelled_get = try device.beginPropertyGet(
        discovery_result.handle,
        .{ .resource = "State" },
    );
    const terminated = try device.acceptPropertyGetNotify(
        try property.DataMessage(64, 128).init(
            .notify,
            2,
            remote_participant.muid,
            local_participant.muid,
            cancelled_get.request_id,
            "{\"status\":144}",
            1,
            1,
            &.{},
        ),
        .terminate,
    );
    try std.testing.expectEqual(
        PropertyUpdate{ .terminated = cancelled_get.request_id },
        terminated,
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyGetRequest,
        device.finishPropertyGet(
            std.testing.allocator,
            cancelled_get.request_id,
        ),
    );

    var property_delegate = DeviceTestPropertyDelegate{};
    var property_host_value = try device.propertyHost(&property_delegate);
    const property_host_result = try property_host_value.accept(
        std.testing.allocator,
        try property.DataMessage(64, 128).init(
            .get,
            2,
            remote_participant.muid,
            local_participant.muid,
            6,
            "{\"resource\":\"LocalState\"}",
            1,
            1,
            &.{},
        ),
    );
    try std.testing.expectEqualStrings(
        "{\"enabled\":true}",
        property_host_result.reply.data(),
    );
    try std.testing.expectEqual(@as(usize, 1), property_delegate.get_count);

    const local_property_transaction = try property.Transaction.init(.{
        .source = remote_participant.muid,
        .destination = local_participant.muid,
        .simultaneous_requests = 1,
        .property_exchange_major = 1,
        .property_exchange_minor = 0,
    });
    const local_property_reply = try device.handlePropertyCapabilities(
        local_property_transaction.inquiry(),
    );
    try std.testing.expect(local_property_reply == .reply);

    const process_responder = try process.Responder.init(
        remote_participant.muid,
        .{ .midi_message_report = true },
    );
    const features = try device.acceptProcessInquiry(
        discovery_result.handle,
        try process_responder.handle(
            try device.processInquiry(discovery_result.handle),
        ),
    );
    try std.testing.expect(features.midi_message_report);
    const local_process_transaction = try process.Transaction.init(
        remote_participant.muid,
        local_participant.muid,
    );
    const local_process_reply = try device.handleProcessInquiry(
        local_process_transaction.inquiry(),
    );
    try std.testing.expect(local_process_reply.reply.features.midi_message_report);
    const endpoint_transaction = try midi_ci.EndpointInformationTransaction.init(
        remote_participant.muid,
        local_participant.muid,
    );
    const endpoint_reply = try device.handleEndpointInformation(
        endpoint_transaction.inquiry(),
    );
    try std.testing.expectEqualSlices(
        u7,
        &.{ 'l', 'o', 'c', 'a', 'l', '-', '1' },
        endpoint_reply.reply.product_instance_id.text(),
    );
    const profile_inquiry = try device.profileInquiry(
        discovery_result.handle,
        .function_block,
    );
    try std.testing.expectEqual(
        remote_participant.muid.value,
        profile_inquiry.destination.value,
    );

    const enabled = profile.Id.standard(0, 1, 1, 0);
    const disabled = profile.Id.standard(0, 2, 1, 0);
    var profile_delegate = DeviceTestProfileDelegate{};
    var local_profile_host = try device.profileHost(&profile_delegate);
    _ = try local_profile_host.addProfile(.function_block, enabled);
    const local_profile_reply = try local_profile_host.handleInquiry(.{
        .source = remote_participant.muid,
        .destination = local_participant.muid,
    }, .function_block);
    try std.testing.expectEqual(
        @as(usize, 1),
        local_profile_reply.disabled.slice().len,
    );
    const local_profile_report = try local_profile_host.handleSet(.{
        .kind = .on,
        .source = remote_participant.muid,
        .destination = local_participant.muid,
        .profile = enabled,
    });
    try std.testing.expectEqual(
        profile.ReportKind.enabled,
        local_profile_report.kind,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        profile_delegate.enablement_requests,
    );

    const ProfileReply = profile.Reply(2);
    try device.applyProfileReply(discovery_result.handle, ProfileReply{
        .source = remote_participant.muid,
        .destination = local_participant.muid,
        .enabled = try profile.List(2).init(&.{enabled}),
        .disabled = try profile.List(2).init(&.{disabled}),
    });
    try device.applyProfileReport(discovery_result.handle, .{
        .kind = .enabled,
        .source = remote_participant.muid,
        .profile = disabled,
    });
    const remote = try device.remote(discovery_result.handle);
    try std.testing.expectEqualSlices(
        u7,
        &.{ 'r', 'e', 'm', 'o', 't', 'e', '-', '2' },
        remote.product_instance_id.?.text(),
    );
    try std.testing.expect(remote.property_agreement != null);
    try std.testing.expect(remote.process_features.?.midi_message_report);
    try std.testing.expectEqual(@as(usize, 2), remote.profiles.len);
    try std.testing.expect(remote.profiles[0].enabled);
    try std.testing.expect(remote.profiles[1].enabled);

    _ = try device.property_initiator.begin(
        .get,
        remote_participant.muid,
        "{}",
        1,
        &.{},
    );
    const Request = property.DataMessage(64, 128);
    _ = try device.property_responder.push(try Request.init(
        .get,
        2,
        remote_participant.muid,
        local_participant.muid,
        4,
        "{}",
        1,
        1,
        &.{},
    ));
    _ = try device.subscriptions.register(
        remote_participant.muid,
        "DeviceInfo",
        "sub_1",
    );
    _ = try device.property_cache.put(.{
        .remote = remote_participant.muid,
        .resource = "DeviceInfo",
    }, "{}");

    const result = try device.acceptInvalidation(.{
        .source = try midi_ci.Muid.init(3),
        .target = remote_participant.muid,
    });
    const cleanup = result.remote;
    try std.testing.expectEqual(@as(usize, 1), cleanup.remotes);
    try std.testing.expectEqual(@as(usize, 1), cleanup.property_requests);
    try std.testing.expectEqual(@as(usize, 1), cleanup.property_responses);
    try std.testing.expectEqual(@as(usize, 1), cleanup.subscriptions);
    try std.testing.expectEqual(@as(usize, 1), cleanup.cached_properties);
    try std.testing.expectEqual(@as(usize, 0), device.remoteCount());
}

test "MIDI-CI device capacity failures preserve remote state" {
    const SmallDevice = Device(.{
        .remote_capacity = 1,
        .profile_capacity = 2,
        .property_session_capacity = 1,
        .subscription_capacity = 1,
        .property_header_capacity = 16,
        .property_data_capacity = 16,
    });
    const local = try testParticipant(1);
    const first = try testParticipant(2);
    const second = try testParticipant(3);
    var device = try SmallDevice.init(.{ .participant = local });
    const handle = (try device.handleDiscovery(.{ .discovery = .{
        .participant = first,
    } })).handle;

    try std.testing.expectError(
        error.MidiCiDeviceRemoteCapacityExceeded,
        device.handleDiscovery(.{ .discovery = .{ .participant = second } }),
    );
    try std.testing.expectEqual(@as(usize, 1), device.remoteCount());
    try std.testing.expectEqual(first.muid.value, (try device.remote(handle)).participant.muid.value);

    const ProfileReply = profile.Reply(3);
    try std.testing.expectError(
        error.MidiCiDeviceProfileCapacityExceeded,
        device.applyProfileReply(handle, ProfileReply{
            .source = first.muid,
            .destination = local.muid,
            .enabled = try profile.List(3).init(&.{
                profile.Id.standard(0, 1, 1, 0),
                profile.Id.standard(0, 2, 1, 0),
                profile.Id.standard(0, 3, 1, 0),
            }),
            .disabled = try profile.List(3).init(&.{}),
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), (try device.remote(handle)).profiles.len);
}

test "MIDI-CI device rejects unsupported categories and version fields" {
    const TestDevice = Device(.{
        .remote_capacity = 1,
        .profile_capacity = 1,
        .property_session_capacity = 1,
        .subscription_capacity = 1,
        .property_header_capacity = 16,
        .property_data_capacity = 16,
    });
    var version_one = try testParticipant(1);
    version_one.version = 1;
    try std.testing.expectError(
        error.UnsupportedMidiCiVersionField,
        TestDevice.init(.{ .participant = version_one }),
    );

    var local = try testParticipant(1);
    local.categories = .{};
    var remote_participant = try testParticipant(2);
    remote_participant.categories = .{};
    var device = try TestDevice.init(.{ .participant = local });
    const handle = (try device.handleDiscovery(.{ .discovery = .{
        .participant = remote_participant,
    } })).handle;
    try std.testing.expectError(
        error.MidiCiProfileConfigurationNotSupported,
        device.profileInquiry(handle, .function_block),
    );
    try std.testing.expectError(
        error.MidiCiPropertyExchangeNotSupported,
        device.propertyCapabilitiesInquiry(handle),
    );
    try std.testing.expectError(
        error.MidiCiProcessInquiryNotSupported,
        device.processInquiry(handle),
    );
}
