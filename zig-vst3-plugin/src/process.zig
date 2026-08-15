const std = @import("std");
pub const AudioBusLayout = @import("plugin/audio_layout.zig").AudioBusLayout;
pub const max_auxiliary_audio_buses =
    @import("plugin/audio_layout.zig").max_auxiliary_audio_buses;
const changes_mod = @import("process/changes.zig");
const events_mod = @import("process/events.zig");
pub const midi1 = @import("process/midi1.zig");
pub const midi_ci = @import("process/midi_ci.zig");
pub const midi_ci_device = @import("process/midi_ci_device.zig");
pub const midi_ci_process = @import("process/midi_ci_process.zig");
pub const midi_ci_process_report = @import("process/midi_ci_process_report.zig");
pub const midi_ci_profile = @import("process/midi_ci_profile.zig");
pub const midi_ci_profile_host = @import("process/midi_ci_profile_host.zig");
pub const midi_ci_property = @import("process/midi_ci_property.zig");
pub const midi_ci_property_cache = @import("process/midi_ci_property_cache.zig");
pub const midi_ci_property_host = @import("process/midi_ci_property_host.zig");
pub const midi_ci_property_json = @import("process/midi_ci_property_json.zig");
pub const midi_ci_property_resources = @import("process/midi_ci_property_resources.zig");
pub const midi_ci_property_controller_resources =
    @import("process/midi_ci_property_controller_resources.zig");
pub const midi_ci_property_standard_resources =
    @import("process/midi_ci_property_standard_resources.zig");
pub const midi_ci_property_session = @import("process/midi_ci_property_session.zig");
pub const midi_file = @import("process/midi_file.zig");
pub const midi_flex = @import("process/midi_flex.zig");
pub const midi_flex_text = @import("process/midi_flex_text.zig");
pub const midi_mixed_data = @import("process/midi_mixed_data.zig");
pub const midi_rpn = @import("process/midi_rpn.zig");
pub const midi_system = @import("process/midi_system.zig");
pub const midi_ump = @import("process/midi_ump.zig");
pub const midi_utility = @import("process/midi_utility.zig");
pub const midi2 = @import("process/midi2.zig");
pub const midi_sysex7 = @import("process/midi_sysex7.zig");
pub const midi_sysex8 = @import("process/midi_sysex8.zig");
pub const midi_stream = @import("process/midi_stream.zig");
pub const midi_endpoint_session = @import("process/midi_endpoint_session.zig");
pub const midi_stream_text = @import("process/midi_stream_text.zig");
pub const mpe = @import("process/mpe.zig");
pub const mpe_instrument = @import("process/mpe_instrument.zig");
const context_mod = @import("process/context.zig");

pub const midi = struct {
    pub const protocol_1 = midi1;
    pub const protocol_2 = midi2;
    pub const ump = midi_ump;
    pub const rpn = midi_rpn;
    pub const system = midi_system;
    pub const utility = midi_utility;
    pub const file = midi_file;
    pub const sysex = struct {
        pub const seven = midi_sysex7;
        pub const eight = midi_sysex8;
    };
    pub const flex = struct {
        pub const data = midi_flex;
        pub const text = midi_flex_text;
    };
    pub const mixed_data = midi_mixed_data;
    pub const endpoint = struct {
        pub const protocol = midi_stream;
        pub const text = midi_stream_text;
        pub const session = midi_endpoint_session;
    };
    pub const ci = struct {
        pub const protocol = midi_ci;
        pub const device = midi_ci_device;
        pub const process = struct {
            pub const protocol = midi_ci_process;
            pub const report = midi_ci_process_report;
        };
        pub const profile = struct {
            pub const protocol = midi_ci_profile;
            pub const host = midi_ci_profile_host;
        };
        pub const property = struct {
            pub const protocol = midi_ci_property;
            pub const cache = midi_ci_property_cache;
            pub const host = midi_ci_property_host;
            pub const json = midi_ci_property_json;
            pub const resources = midi_ci_property_resources;
            pub const controller_resources = midi_ci_property_controller_resources;
            pub const standard_resources = midi_ci_property_standard_resources;
            pub const session = midi_ci_property_session;
        };
    };
    pub const expression = struct {
        pub const zones = mpe;
        pub const instrument = mpe_instrument;
    };
};

pub const max_audio_channels = context_mod.max_audio_channels;
pub const midi_channel_min = events_mod.midi_channel_min;
pub const midi_channel_max = events_mod.midi_channel_max;
pub const midi_pitch_min = events_mod.midi_pitch_min;
pub const midi_pitch_max = events_mod.midi_pitch_max;
pub const midiPitchCount = events_mod.midiPitchCount;
pub const midiPitchIndex = events_mod.midiPitchIndex;
pub const midi_control_number_min = events_mod.midi_control_number_min;
pub const midi_control_number_max = events_mod.midi_control_number_max;
pub const event_value_min = events_mod.event_value_min;
pub const event_value_max = events_mod.event_value_max;
pub const bipolar_event_value_min = events_mod.bipolar_event_value_min;
pub const bipolar_event_value_max = events_mod.bipolar_event_value_max;
pub const max_data_event_bytes = events_mod.max_data_event_bytes;

pub const ParameterChange = changes_mod.ParameterChange;
pub const ParameterRamp = changes_mod.ParameterRamp;
pub const BlockParameterLatch = changes_mod.BlockParameterLatch;
pub const ParameterSegment = changes_mod.ParameterSegment;
pub const BlockSegment = changes_mod.BlockSegment;
pub const BlockSegmentIterator = changes_mod.BlockSegmentIterator;
pub const ParameterSegmentIterator = changes_mod.ParameterSegmentIterator;
pub const ParameterChangeIdIterator = changes_mod.ParameterChangeIdIterator;
pub const ParameterChangeOffsetIterator = changes_mod.ParameterChangeOffsetIterator;
pub const ParameterChangeIdOffsetIterator = changes_mod.ParameterChangeIdOffsetIterator;
pub const ParameterChanges = changes_mod.ParameterChanges;

pub const EventKind = events_mod.EventKind;
pub const NoteLifecycle = events_mod.NoteLifecycle;
pub const NoteOn = events_mod.NoteOn;
pub const NoteOff = events_mod.NoteOff;
pub const MidiCC = events_mod.MidiCC;
pub const PitchBend = events_mod.PitchBend;
pub const Aftertouch = events_mod.Aftertouch;
pub const NoteExpressionValue = events_mod.NoteExpressionValue;
pub const NoteExpressionInt = events_mod.NoteExpressionInt;
pub const NoteExpressionText = events_mod.NoteExpressionText;
pub const DataEvent = events_mod.DataEvent;
pub const EventKindIterator = events_mod.EventKindIterator;
pub const EventOffsetIterator = events_mod.EventOffsetIterator;
pub const EventBusIterator = events_mod.EventBusIterator;
pub const EventChannelIterator = events_mod.EventChannelIterator;
pub const EventBusChannelIterator = events_mod.EventBusChannelIterator;
pub const EventBlockSegmentIterator = events_mod.EventBlockSegmentIterator;
pub const Event = events_mod.Event;
pub const Events = events_mod.Events;
pub const EventWriter = events_mod.EventWriter;
pub const Midi1Message = midi1.Message;
pub const Midi1MessageKind = midi1.MessageKind;
pub const Midi1StreamDecoder = midi1.StreamDecoder;
pub const MidiRpnEvent = midi_rpn.Event;
pub const MidiRpnDecoder = midi_rpn.Decoder;
pub const midiRpnCoarseMessages = midi_rpn.coarseMessages;
pub const midiRpnFineMessages = midi_rpn.fineMessages;
pub const midiRpnNullSelectionMessages = midi_rpn.nullSelectionMessages;
pub const MidiSystemStatus = midi_system.Status;
pub const MidiSystemPayload = midi_system.Payload;
pub const MidiSystemMessage = midi_system.Message;
pub const MidiFlexAddress = midi_flex.Address;
pub const MidiFlexTarget = midi_flex.Target;
pub const MidiFlexStatus = midi_flex.Status;
pub const MidiFlexTimeSignature = midi_flex.TimeSignature;
pub const MidiFlexMetronome = midi_flex.Metronome;
pub const MidiFlexTonic = midi_flex.Tonic;
pub const MidiFlexKeySignature = midi_flex.KeySignature;
pub const MidiFlexChordType = midi_flex.ChordType;
pub const MidiFlexAlterationType = midi_flex.AlterationType;
pub const MidiFlexAlteration = midi_flex.Alteration;
pub const MidiFlexChordName = midi_flex.ChordName;
pub const MidiFlexPayload = midi_flex.Payload;
pub const MidiFlexMessage = midi_flex.Message;
pub const MidiFlexTextForm = midi_flex_text.Form;
pub const MidiFlexTextKind = midi_flex_text.Kind;
pub const MidiFlexTextChunk = midi_flex_text.Chunk;
pub const MidiFlexTextPacketizer = midi_flex_text.Packetizer;
pub const MidiFlexTextReassembler = midi_flex_text.Reassembler;
pub const MidiMixedDataMetadata = midi_mixed_data.Metadata;
pub const MidiMixedDataHeader = midi_mixed_data.Header;
pub const MidiMixedDataPayload = midi_mixed_data.Payload;
pub const MidiMixedDataPacketizer = midi_mixed_data.Packetizer;
pub const MidiMixedDataReassembler = midi_mixed_data.Reassembler;
pub const MidiUtilityStatus = midi_utility.Status;
pub const MidiUtilityPayload = midi_utility.Payload;
pub const MidiUtilityMessage = midi_utility.Message;
pub const UmpMessageType = midi_ump.MessageType;
pub const UmpPacket = midi_ump.Packet;
pub const UmpIterator = midi_ump.Iterator;
pub const UmpLimits = midi_ump.Limits;
pub const default_ump_limits = midi_ump.default_limits;
pub const Midi1UmpPacket = midi_ump.Midi1Packet;
pub const umpFromMidi1 = midi_ump.fromMidi1;
pub const umpToMidi1 = midi_ump.toMidi1;
pub const umpScale7To8 = midi_ump.scale7To8;
pub const umpScale7To16 = midi_ump.scale7To16;
pub const umpScale14To16 = midi_ump.scale14To16;
pub const umpScale7To32 = midi_ump.scale7To32;
pub const umpScale14To32 = midi_ump.scale14To32;
pub const umpScale8To7 = midi_ump.scale8To7;
pub const umpScale16To7 = midi_ump.scale16To7;
pub const umpScale32To7 = midi_ump.scale32To7;
pub const umpScale16To14 = midi_ump.scale16To14;
pub const umpScale32To14 = midi_ump.scale32To14;
pub const Midi2Status = midi2.Status;
pub const Midi2NoteAttribute = midi2.NoteAttribute;
pub const Midi2IndexedController = midi2.IndexedController;
pub const Midi2PerNoteValue = midi2.PerNoteValue;
pub const Midi2Note = midi2.Note;
pub const Midi2IndexedValue = midi2.IndexedValue;
pub const Midi2Program = midi2.Program;
pub const Midi2PerNoteManagement = midi2.PerNoteManagement;
pub const Midi2Payload = midi2.Payload;
pub const Midi2ChannelMessage = midi2.ChannelMessage;
pub const Sysex7Kind = midi_sysex7.Kind;
pub const Sysex7Chunk = midi_sysex7.Chunk;
pub const Sysex7Packetizer = midi_sysex7.Packetizer;
pub const Sysex7Reassembler = midi_sysex7.Reassembler;
pub const Sysex8Kind = midi_sysex8.Kind;
pub const Sysex8Chunk = midi_sysex8.Chunk;
pub const Sysex8Packetizer = midi_sysex8.Packetizer;
pub const Sysex8Reassembler = midi_sysex8.Reassembler;
pub const MidiStreamStatus = midi_stream.Status;
pub const MidiStreamProtocol = midi_stream.Protocol;
pub const MidiStreamConfiguration = midi_stream.StreamConfiguration;
pub const MidiEndpointDiscovery = midi_stream.EndpointDiscovery;
pub const MidiEndpointInfo = midi_stream.EndpointInfo;
pub const MidiDeviceIdentity = midi_stream.DeviceIdentity;
pub const MidiFunctionBlockSelector = midi_stream.FunctionBlockSelector;
pub const MidiFunctionBlockDiscovery = midi_stream.FunctionBlockDiscovery;
pub const MidiFunctionBlockDirection = midi_stream.Direction;
pub const MidiFunctionBlockUiHint = midi_stream.UiHint;
pub const MidiFunctionBlockMidi1Proxy = midi_stream.Midi1Proxy;
pub const MidiFunctionBlockInfo = midi_stream.FunctionBlockInfo;
pub const MidiStreamPayload = midi_stream.Payload;
pub const MidiStreamMessage = midi_stream.Message;
pub const MidiStreamTextForm = midi_stream_text.Form;
pub const MidiStreamTextKind = midi_stream_text.Kind;
pub const MidiStreamTextChunk = midi_stream_text.Chunk;
pub const MidiStreamTextPacketizer = midi_stream_text.Packetizer;
pub const MidiStreamTextReassembler = midi_stream_text.Reassembler;
pub const MidiEndpointFilter = midi_endpoint_session.EndpointFilter;
pub const MidiFunctionBlockFilter = midi_endpoint_session.FunctionBlockFilter;
pub const MidiEndpointRequester = midi_endpoint_session.Requester;
pub const MidiFunctionBlockDescriptor = midi_endpoint_session.FunctionBlockDescriptor;
pub const MidiEndpointDescriptor = midi_endpoint_session.Descriptor;
pub const MidiEndpointResponder = midi_endpoint_session.Responder;
pub const MidiEndpointReplies = midi_endpoint_session.Replies;
pub const MidiCiMuid = midi_ci.Muid;
pub const MidiCiCategories = midi_ci.Categories;
pub const MidiCiParticipant = midi_ci.Participant;
pub const MidiCiDiscovery = midi_ci.Discovery;
pub const MidiCiDiscoveryReply = midi_ci.Reply;
pub const MidiCiDiscoveryKind = midi_ci.Kind;
pub const MidiCiDiscoveryMessage = midi_ci.Message;
pub const MidiCiDiscoveryTransaction = midi_ci.DiscoveryTransaction;
pub const MidiCiDiscoveryResponder = midi_ci.DiscoveryResponder;
pub const MidiCiInvalidation = midi_ci.Invalidation;
pub const MidiCiProductInstanceId = midi_ci.ProductInstanceId;
pub const MidiCiEndpointInformationInquiry = midi_ci.EndpointInformationInquiry;
pub const MidiCiEndpointInformationReply = midi_ci.EndpointInformationReply;
pub const MidiCiEndpointInformationKind = midi_ci.EndpointInformationKind;
pub const MidiCiEndpointInformationMessage = midi_ci.EndpointInformationMessage;
pub const MidiCiEndpointInformationTransaction = midi_ci.EndpointInformationTransaction;
pub const MidiCiEndpointInformationResponder = midi_ci.EndpointInformationResponder;
pub const MidiCiAddress = midi_ci.Address;
pub const MidiCiMessageText = midi_ci.MessageText;
pub const MidiCiAcknowledgementKind = midi_ci.AcknowledgementKind;
pub const MidiCiAcknowledgement = midi_ci.Acknowledgement;
pub const MidiCiProcessInquiryFeatures = midi_ci_process.Features;
pub const MidiCiProcessInquiry = midi_ci_process.Inquiry;
pub const MidiCiProcessInquiryReply = midi_ci_process.Reply;
pub const MidiCiProcessInquiryKind = midi_ci_process.Kind;
pub const MidiCiProcessInquiryMessage = midi_ci_process.Message;
pub const MidiCiProcessInquiryTransaction = midi_ci_process.Transaction;
pub const MidiCiProcessInquiryResponder = midi_ci_process.Responder;
pub const MidiCiReportDataControl = midi_ci_process_report.DataControl;
pub const MidiCiReportSystemMessages = midi_ci_process_report.SystemMessages;
pub const MidiCiReportChannelMessages = midi_ci_process_report.ChannelMessages;
pub const MidiCiReportNoteMessages = midi_ci_process_report.NoteMessages;
pub const MidiCiReportRequests = midi_ci_process_report.Requests;
pub const MidiCiMessageReportInquiry = midi_ci_process_report.Inquiry;
pub const MidiCiMessageReportReply = midi_ci_process_report.Reply;
pub const MidiCiMessageReportEnd = midi_ci_process_report.End;
pub const MidiCiMessageReportKind = midi_ci_process_report.Kind;
pub const MidiCiMessageReportMessage = midi_ci_process_report.Message;
pub const MidiCiMessageReportTransaction = midi_ci_process_report.Transaction;
pub const MidiCiMessageReportResponder = midi_ci_process_report.Responder;
pub const MidiCiProfileId = midi_ci_profile.Id;
pub const MidiCiProfileList = midi_ci_profile.List;
pub const MidiCiProfileInquiry = midi_ci_profile.Inquiry;
pub const MidiCiProfileReply = midi_ci_profile.Reply;
pub const MidiCiProfileSetKind = midi_ci_profile.SetKind;
pub const MidiCiProfileSet = midi_ci_profile.Set;
pub const MidiCiProfileReportKind = midi_ci_profile.ReportKind;
pub const MidiCiProfileReport = midi_ci_profile.Report;
pub const MidiCiProfilePresenceKind = midi_ci_profile.PresenceKind;
pub const MidiCiProfilePresence = midi_ci_profile.Presence;
pub const MidiCiProfileDetailsInquiry = midi_ci_profile.DetailsInquiry;
pub const MidiCiProfileDetailsReply = midi_ci_profile.DetailsReply;
pub const MidiCiProfileSpecificData = midi_ci_profile.SpecificData;
pub const MidiCiProfileChannelCountDetails = midi_ci_profile.ChannelCountDetails;
pub const MidiCiProfileDetailsTransaction = midi_ci_profile.DetailsTransaction;
pub const MidiCiProfileInquiryTransaction = midi_ci_profile.InquiryTransaction;
pub const MidiCiProfileSetTransaction = midi_ci_profile.SetTransaction;
pub const MidiCiProfileHostEntry = midi_ci_profile_host.Entry;
pub const MidiCiProfileHostSpecificDataRequest =
    midi_ci_profile_host.SpecificDataRequest;
pub const MidiCiProfileHost = midi_ci_profile_host.Host;
pub const MidiCiPropertyCapabilities = midi_ci_property.Capabilities;
pub const midi_ci_current_property_exchange_major =
    midi_ci_property.current_property_exchange_major;
pub const midi_ci_current_property_exchange_minor =
    midi_ci_property.current_property_exchange_minor;
pub const MidiCiPropertyCapabilitiesKind = midi_ci_property.Kind;
pub const MidiCiPropertyCapabilitiesMessage = midi_ci_property.Message;
pub const MidiCiPropertyCapabilitiesAgreement = midi_ci_property.Agreement;
pub const MidiCiPropertyCapabilitiesTransaction = midi_ci_property.Transaction;
pub const MidiCiPropertyCapabilitiesResponder = midi_ci_property.Responder;
pub const MidiCiPropertyDataKind = midi_ci_property.DataKind;
pub const MidiCiPropertyDataMessage = midi_ci_property.DataMessage;
pub const MidiCiPropertyChunkResult = midi_ci_property.ChunkResult;
pub const MidiCiPropertyReassembler = midi_ci_property.Reassembler;
pub const MidiCiPropertyRequestIds = midi_ci_property.RequestIds;
pub const MidiCiPropertyReceiveResult = midi_ci_property_session.ReceiveResult;
pub const MidiCiPropertyInitiator = midi_ci_property_session.Initiator;
pub const MidiCiPropertyResponder = midi_ci_property_session.Responder;
pub const MidiCiPropertySubscriptionUpdate = midi_ci_property_session.SubscriptionUpdate;
pub const MidiCiPropertySubscription = midi_ci_property_session.Subscription;
pub const MidiCiPropertySubscriptionRegistry =
    midi_ci_property_session.SubscriptionRegistry;
pub const MidiCiPropertyCacheKey = midi_ci_property_cache.Key;
pub const MidiCiPropertyCacheEntry = midi_ci_property_cache.Entry;
pub const MidiCiPropertyRemoteCache = midi_ci_property_cache.RemoteCache;
pub const MidiCiPropertyHostRequest = midi_ci_property_host.Request;
pub const MidiCiPropertyHostSubscriptionRequest =
    midi_ci_property_host.SubscriptionRequest;
pub const MidiCiPropertyHostReply = midi_ci_property_host.Reply;
pub const MidiCiPropertyHostResult = midi_ci_property_host.Result;
pub const MidiCiPropertyHost = midi_ci_property_host.Host;
pub const MidiCiDeviceConfig = midi_ci_device.Config;
pub const MidiCiDeviceOptions = midi_ci_device.Options;
pub const MidiCiDeviceProfileState = midi_ci_device.ProfileState;
pub const MidiCiDeviceRemote = midi_ci_device.Remote;
pub const MidiCiDeviceCleanup = midi_ci_device.Cleanup;
pub const MidiCiDeviceInvalidationResult = midi_ci_device.InvalidationResult;
pub const MidiCiDeviceDiscoveryResult = midi_ci_device.DiscoveryResult;
pub const MidiCiDevicePropertyCompletion = midi_ci_device.PropertyCompletion;
pub const MidiCiDevicePropertyUpdate = midi_ci_device.PropertyUpdate;
pub const MidiCiDevice = midi_ci_device.Device;
pub const MidiCiPropertyEncoding = midi_ci_property_json.Encoding;
pub const MidiCiPropertyMaximumHeaderBytes =
    midi_ci_property_json.maximum_header_bytes;
pub const MidiCiPropertyMcoded7 = midi_ci_property_json.Mcoded7;
pub const MidiCiPropertyZlibMcoded7 = midi_ci_property_json.ZlibMcoded7;
pub const MidiCiPropertyPagination = midi_ci_property_json.Pagination;
pub const MidiCiPropertyRequestHeader = midi_ci_property_json.RequestHeader;
pub const MidiCiPropertyReplyStatus = midi_ci_property_json.ReplyStatus;
pub const MidiCiPropertyReplyHeader = midi_ci_property_json.ReplyHeader;
pub const MidiCiPropertySubscriptionCommand = midi_ci_property_json.SubscriptionCommand;
pub const MidiCiPropertySubscriptionHeader = midi_ci_property_json.SubscriptionHeader;
pub const MidiCiPropertyNotifyStatus = midi_ci_property_json.NotifyStatus;
pub const MidiCiPropertyNotifyHeader = midi_ci_property_json.NotifyHeader;
pub const MidiCiPropertyLink = midi_ci_property_resources.Link;
pub const MidiCiPropertyDeviceInfo = midi_ci_property_resources.DeviceInfo;
pub const MidiCiPropertyClusterType = midi_ci_property_resources.ClusterType;
pub const MidiCiPropertyChannel = midi_ci_property_resources.Channel;
pub const MidiCiPropertyChannelList = midi_ci_property_resources.ChannelList;
pub const MidiCiPropertyProgram = midi_ci_property_resources.Program;
pub const MidiCiPropertyProgramList = midi_ci_property_resources.ProgramList;
pub const midi_ci_property_program_list_resource =
    midi_ci_property_resources.program_list_resource;
pub const MidiCiPropertySetSupport = midi_ci_property_resources.SetSupport;
pub const MidiCiPropertyColumn = midi_ci_property_resources.Column;
pub const MidiCiPropertyResource = midi_ci_property_resources.Resource;
pub const MidiCiPropertyResourceList = midi_ci_property_resources.ResourceList;
pub const parseMidiCiPropertyJsonSchema = midi_ci_property_resources.parseJsonSchema;
pub const MidiCiPropertyMode = midi_ci_property_standard_resources.Mode;
pub const MidiCiPropertyModeList = midi_ci_property_standard_resources.ModeList;
pub const MidiCiPropertyCurrentMode = midi_ci_property_standard_resources.CurrentMode;
pub const MidiCiPropertyChannelMode = midi_ci_property_standard_resources.ChannelMode;
pub const MidiCiPropertyBasicChannel = midi_ci_property_standard_resources.BasicChannel;
pub const MidiCiPropertyLocalOn = midi_ci_property_standard_resources.LocalOn;
pub const MidiCiPropertyExternalSync = midi_ci_property_standard_resources.ExternalSync;
pub const MidiCiPropertyState = midi_ci_property_standard_resources.State;
pub const MidiCiPropertyStateList = midi_ci_property_standard_resources.StateList;
pub const midi_ci_property_mode_list_resource =
    midi_ci_property_standard_resources.mode_list_resource;
pub const midi_ci_property_current_mode_resource =
    midi_ci_property_standard_resources.current_mode_resource;
pub const midi_ci_property_channel_mode_resource =
    midi_ci_property_standard_resources.channel_mode_resource;
pub const midi_ci_property_basic_channel_rx_resource =
    midi_ci_property_standard_resources.basic_channel_rx_resource;
pub const midi_ci_property_basic_channel_tx_resource =
    midi_ci_property_standard_resources.basic_channel_tx_resource;
pub const midi_ci_property_local_on_resource =
    midi_ci_property_standard_resources.local_on_resource;
pub const midi_ci_property_external_sync_resource =
    midi_ci_property_standard_resources.external_sync_resource;
pub const midi_ci_property_state_list_resource =
    midi_ci_property_standard_resources.state_list_resource;
pub const midi_ci_property_state_resource =
    midi_ci_property_standard_resources.state_resource;
pub const MidiCiPropertyControllerType =
    midi_ci_property_controller_resources.ControllerType;
pub const MidiCiPropertyControllerDirection =
    midi_ci_property_controller_resources.Direction;
pub const MidiCiPropertyControllerTypeHint =
    midi_ci_property_controller_resources.TypeHint;
pub const MidiCiPropertyController =
    midi_ci_property_controller_resources.Controller;
pub const MidiCiPropertyAllControllerList =
    midi_ci_property_controller_resources.AllControllerList;
pub const MidiCiPropertyChannelControllerList =
    midi_ci_property_controller_resources.ChannelControllerList;
pub const MidiCiPropertyControllerMapEntry =
    midi_ci_property_controller_resources.ControllerMapEntry;
pub const MidiCiPropertyControllerMapList =
    midi_ci_property_controller_resources.ControllerMapList;
pub const midi_ci_property_all_controller_list_resource =
    midi_ci_property_controller_resources.all_controller_list_resource;
pub const midi_ci_property_channel_controller_list_resource =
    midi_ci_property_controller_resources.channel_controller_list_resource;
pub const midi_ci_property_controller_map_list_resource =
    midi_ci_property_controller_resources.controller_map_list_resource;
pub const MidiFile = midi_file.File;
pub const MidiFileLimits = midi_file.Limits;
pub const default_midi_file_limits = midi_file.default_limits;
pub const MidiFileFormat = midi_file.Format;
pub const MidiFileDivision = midi_file.Division;
pub const MidiFileSmpteRate = midi_file.SmpteRate;
pub const MidiFileSmpteDivision = midi_file.SmpteDivision;
pub const MidiFileTimeSignature = midi_file.TimeSignature;
pub const MidiFileTrack = midi_file.Track;
pub const MidiFileTrackIterator = midi_file.TrackIterator;
pub const MidiFileEvent = midi_file.Event;
pub const MidiFileEventPayload = midi_file.EventPayload;
pub const MidiFileMetaEvent = midi_file.MetaEvent;
pub const MidiFileSysExEvent = midi_file.SysExEvent;
pub const MidiFileWriter = midi_file.Writer;
pub const MpeZoneType = mpe.ZoneType;
pub const MpeZone = mpe.Zone;
pub const MpeZoneLayout = mpe.Layout;
pub const MpeZoneSynchronizer = mpe.Synchronizer;
pub const mpeConfigurationMessages = mpe.configurationMessages;
pub const mpePitchBendRangeMessages = mpe.pitchBendRangeMessages;
pub const MpeTrackingMode = mpe_instrument.TrackingMode;
pub const MpeKeyState = mpe_instrument.KeyState;
pub const MpeNote = mpe_instrument.Note;
pub const MpeInstrumentChangeKind = mpe_instrument.ChangeKind;
pub const MpeInstrumentChange = mpe_instrument.Change;
pub const MpeInstrument = mpe_instrument.Instrument;
pub const MpeStealPolicy = mpe_instrument.StealPolicy;
pub const MpeMemberChannelAssignment = mpe_instrument.Assignment;
pub const MpeMemberChannelAllocation = mpe_instrument.Allocation;
pub const MpeMemberChannelAllocator = mpe_instrument.MemberChannelAllocator;

pub const ProcessBlockSegmentIterator = context_mod.ProcessBlockSegmentIterator;
pub const ProcessMode = context_mod.ProcessMode;
pub const TimeSignature = context_mod.TimeSignature;
pub const CycleRange = context_mod.CycleRange;
pub const Transport = context_mod.Transport;
pub const ProcessAttachments = context_mod.ProcessAttachments;
pub const AudioInputs = context_mod.AudioInputs;
pub const AudioOutputs = context_mod.AudioOutputs;
pub const AudioBusRange = context_mod.AudioBusRange;
pub const BoundedAudioBusRanges =
    context_mod.BoundedAudioBusRanges;
pub const AudioBusRanges = context_mod.AudioBusRanges;
pub const BoundedProcessContext =
    context_mod.BoundedProcessContext;
pub const ProcessContext = context_mod.ProcessContext;

test {
    _ = @import("process/midi_stream_fuzz.zig");
}
