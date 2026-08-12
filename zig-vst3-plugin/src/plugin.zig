const std = @import("std");
const audio_layout = @import("plugin/audio_layout.zig");
const spec = @import("plugin/spec.zig");
const config = @import("plugin/config.zig");
const device_catalog = @import("plugin/device_catalog.zig");
const instance = @import("plugin/instance.zig");
const lifecycle = @import("plugin/lifecycle.zig");
const host_requests = @import("plugin/host_requests.zig");
const offline_renderer = @import("plugin/offline_renderer.zig");
const runtime = @import("plugin/runtime.zig");
const standalone = @import("plugin/standalone.zig");
const standalone_shell = @import("plugin/standalone_shell.zig");

pub const PluginSpec = spec.PluginSpec;
pub const AudioBusLayout = audio_layout.AudioBusLayout;
pub const AudioBusDirection = audio_layout.AudioBusDirection;
pub const AudioBusLayoutSet = audio_layout.AudioBusLayoutSet;
pub const DynamicAudioBus = audio_layout.DynamicAudioBus;
pub const DynamicAudioBusState = audio_layout.DynamicAudioBusState;
pub const BoundedDynamicAudioBusSnapshot =
    audio_layout.BoundedDynamicAudioBusSnapshot;
pub const BoundedDynamicAudioBusTopology =
    audio_layout.BoundedDynamicAudioBusTopology;
pub const DynamicAudioBusSnapshot =
    audio_layout.DynamicAudioBusSnapshot;
pub const DynamicAudioBusTopology =
    audio_layout.DynamicAudioBusTopology;
pub const max_auxiliary_audio_buses = audio_layout.max_auxiliary_audio_buses;
pub const max_audio_buses_per_direction =
    audio_layout.max_audio_buses_per_direction;
pub const PrepareConfig = config.PrepareConfig;
pub const PluginInstance = instance.PluginInstance;
pub const OfflineRenderer = offline_renderer.OfflineRenderer;
pub const ProcessorRuntime = runtime.ProcessorRuntime;
pub const RuntimeState = runtime.RuntimeState;
pub const AudioCallback = standalone.AudioCallback;
pub const AudioDevice = standalone.AudioDevice;
pub const CallbackBlock = standalone.CallbackBlock;
pub const ClockDriftConfig = standalone.ClockDriftConfig;
pub const ClockDriftController = standalone.ClockDriftController;
pub const BoundedCaptureFifo = standalone.BoundedCaptureFifo;
pub const BoundedCaptureRateBridge =
    standalone.BoundedCaptureRateBridge;
pub const BoundedCaptureRateCallbackAdapter =
    standalone.BoundedCaptureRateCallbackAdapter;
pub const CaptureRateCallbackAdapterConfig =
    standalone.CaptureRateCallbackAdapterConfig;
pub const CaptureRateCallbackStatistics =
    standalone.CaptureRateCallbackStatistics;
pub const CaptureFifoReadReport =
    standalone.CaptureFifoReadReport;
pub const CaptureFifoStatistics =
    standalone.CaptureFifoStatistics;
pub const CaptureFifoWriteReport =
    standalone.CaptureFifoWriteReport;
pub const CaptureRateBridgeConfig =
    standalone.CaptureRateBridgeConfig;
pub const CaptureRateLifecycleConfig =
    standalone.CaptureRateLifecycleConfig;
pub const CaptureRateOperatingState =
    standalone.CaptureRateOperatingState;
pub const CaptureRateOverflowPolicy =
    standalone.CaptureRateOverflowPolicy;
pub const CaptureRateUnderflowPolicy =
    standalone.CaptureRateUnderflowPolicy;
pub const CaptureRateRenderReport =
    standalone.CaptureRateRenderReport;
pub const CaptureRenderBlock = standalone.CaptureRenderBlock;
pub const SplitAudioCallback = standalone.SplitAudioCallback;
pub const DeviceAudioBlock = standalone.DeviceAudioBlock;
pub const DeviceChannelRouter = standalone.DeviceChannelRouter;
pub const BoundedDeviceChannelRouter =
    standalone.BoundedDeviceChannelRouter;
pub const DeviceChannelRouting = standalone.DeviceChannelRouting;
pub const DeviceConfiguration = standalone.DeviceConfiguration;
pub const DeviceCatalog = device_catalog.DeviceCatalog;
pub const DeviceDescriptor = device_catalog.DeviceDescriptor;
pub const DeviceIdentifier = device_catalog.DeviceIdentifier;
pub const DeviceKind = device_catalog.DeviceKind;
pub const maximum_device_identifier_bytes =
    device_catalog.maximum_device_identifier_bytes;
pub const maximum_device_name_bytes =
    device_catalog.maximum_device_name_bytes;
pub const DeviceSelection = device_catalog.DeviceSelection;
pub const DeviceSelectionResolution =
    device_catalog.DeviceSelectionResolution;
pub const DeviceSelectionTracker =
    device_catalog.DeviceSelectionTracker;
pub const DeviceRecoveryCallback =
    device_catalog.DeviceRecoveryCallback;
pub const DeviceRecoveryController =
    device_catalog.DeviceRecoveryController;
pub const DeviceRecoveryReason =
    device_catalog.DeviceRecoveryReason;
pub const DeviceRecoveryResult =
    device_catalog.DeviceRecoveryResult;
pub const DeviceFailureMonitor =
    device_catalog.DeviceFailureMonitor;
pub const DeviceFailureMonitorSet =
    device_catalog.DeviceFailureMonitorSet;
pub const DeviceFailureReport =
    device_catalog.DeviceFailureReport;
pub const DeviceFailureSnapshot =
    device_catalog.DeviceFailureSnapshot;
pub const DeviceFailureSource =
    device_catalog.DeviceFailureSource;
pub const HostRequestSink = host_requests.HostRequestSink;
pub const HostChange = host_requests.HostChange;
pub const Midi1CallbackPacket = standalone.Midi1CallbackPacket;
pub const Midi1BlockScheduleReport =
    standalone.Midi1BlockScheduleReport;
pub const Midi1BlockScheduler = standalone.Midi1BlockScheduler;
pub const Midi1EventBuffer = standalone.Midi1EventBuffer;
pub const Midi1InputCallback = standalone.Midi1InputCallback;
pub const Midi1InputDevice = standalone.Midi1InputDevice;
pub const Midi1InputQueue = standalone.Midi1InputQueue;
pub const Midi1OutputDevice = standalone.Midi1OutputDevice;
pub const Midi1OutputReport = standalone.Midi1OutputReport;
pub const Midi1OutputSink = standalone.Midi1OutputSink;
pub const maximum_routed_channels =
    standalone.maximum_routed_channels;
pub const StandaloneRuntime = standalone.StandaloneRuntime;
pub const StandaloneApplication =
    standalone.StandaloneApplication;
pub const StandaloneShell = standalone_shell.StandaloneShell;
pub const StandaloneWindow = standalone_shell.StandaloneWindow;
pub const StandaloneWindowBackend = standalone_shell.WindowBackend;
pub const StandaloneWindowEvent = standalone_shell.WindowEvent;
pub const StandaloneWindowEventPumpReport =
    standalone_shell.EventPumpReport;
pub const StandaloneControlCycleReport =
    standalone_shell.ControlCycleReport;
pub const maximum_device_failure_sources =
    standalone_shell.maximum_device_failure_sources;
pub const TimestampedMidi1Packet =
    standalone.TimestampedMidi1Packet;
pub const TimestampedUmpPacket =
    standalone.TimestampedUmpPacket;
pub const UmpBlockBuffer = standalone.UmpBlockBuffer;
pub const UmpBlockPacket = standalone.UmpBlockPacket;
pub const UmpBlockScheduleReport =
    standalone.UmpBlockScheduleReport;
pub const UmpBlockScheduler = standalone.UmpBlockScheduler;
pub const UmpInputCallback = standalone.UmpInputCallback;
pub const UmpInputDevice = standalone.UmpInputDevice;
pub const UmpInputQueue = standalone.UmpInputQueue;
pub const UmpOutputDevice = standalone.UmpOutputDevice;
pub const UmpOutputReport = standalone.UmpOutputReport;
pub const validateLifecycle = lifecycle.validateLifecycle;

test {
    std.testing.refAllDecls(@import("plugin/tests.zig"));
}
