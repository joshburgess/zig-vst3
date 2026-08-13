# Framework API Compatibility Inventory

This inventory defines the reviewed public framework surface for
`zig-vst3-0.3.0-rc.1`. Compatibility-ready declarations follow the
[Framework Compatibility Policy](compatibility-policy.md). Experimental
declarations ship without that promise.

The inventory unit is a public declaration in an installed module root. Public
members of a listed generic or namespace inherit that declaration's category
unless an exception is stated below. Protocol constants and ABI records inherit
the compatibility status of the specification they mirror. Product-specific
types returned by a generic inherit the status of that generic.

## Categories

| Category | Meaning |
| --- | --- |
| Compatibility-ready | The name, role, ownership, and failure contract are suitable for the first compatibility-bearing framework release. |
| Experimental | Useful and tested, but product or external-host evidence can still require source changes before a compatibility promise. |
| Mixed namespace | The root is retained, but its public descendants keep their individual compatibility-ready or experimental classification. |
| Internal leakage | An implementation detail or duplicate path that should not be part of the installed API. |
| Redundant | A public spelling with no distinct supported workflow. |
| Insufficiently documented | A supported workflow whose ownership or behavioral contract is not clear enough to freeze. |

No retained declaration remains classified as internal leakage, redundant, or
insufficiently documented after this pass. The two internal leaks found by the
inventory were removed. Migration is recorded below.

## `zig-vst3-plugin`

| Public declarations | Classification | Contract |
| --- | --- | --- |
| `core` | Mixed namespace | The root remains available. Its descendants keep the classifications listed in this inventory. |
| `version`, `parameters`, `realtime_audit`, `dsp`, `resource`, `process`, `state`, `units` | Compatibility-ready | Format-neutral value, processing, state, resource, and DSP namespaces. Their public constructors and methods are covered by native, installed-package, retained-state, and supported cross-target tests. |
| `plugin` | Mixed namespace | High-level, routing, device, MIDI, shell, and split-device declarations retain the classifications below. |
| `PluginSpec`, `PluginInstance`, `ProcessorRuntime`, `OfflineRenderer`, `PrepareConfig`, `RuntimeState`, `AudioBusLayout`, `AudioBusDirection`, `AudioBusLayoutSet`, `DynamicAudioBus`, `DynamicAudioBusState`, `BoundedDynamicAudioBusSnapshot`, `BoundedDynamicAudioBusTopology`, `DynamicAudioBusSnapshot`, `DynamicAudioBusTopology`, `max_auxiliary_audio_buses`, `max_audio_buses_per_direction`, `HostRequestSink`, `HostChange`, `validateLifecycle` | Compatibility-ready | High-level declarations, lifecycle, topology, and host requests. The top-level host-request aliases are retained because shipped high-level plugin declarations use them directly. |
| `Vst3Processor`, `Vst3ProcessorWithParameters`, `Vst3Effect`, `Vst3EffectWithParameters`, `Vst3Controller`, `Vst3ControllerWithParameters`, `vst3_adapter` | Compatibility-ready | The high-level VST3 construction path. Raw ABI compatibility remains governed separately by the raw API policy. |
| `gui`, `editor_state`, `gui_preset_browser`, `gui_telemetry`, `gui_graph`, `gui_piano`, `gui_step_sequencer`, `gui_file_drop`, `gui_file_importer`, `gui_audio_file_importer`, `gui_audio_sample_store`, `gui_sample_player`, `gui_ir_convolution`, `gui_ir_editor`, `gui_progress`, `gui_range_selection`, `gui_viewport` | Experimental | Toolkit-neutral authoring and telemetry are automated, but live platform accessibility, clipboard, visual, and host lifecycle evidence is incomplete. |
| `lv2` and every declaration rooted at `lv2`, including `metadata`, `ui`, protocol URI and status constants, ABI records, feature sinks, `Descriptor`, `CoreAdapter`, and `CoreAdapterWithParameters` | Experimental | ABI, metadata, dynamic loading, state, worker, programs, UI, and cross-target gates pass. Two-host external validation is still required. Specification constants and external records change only to follow LV2. |
| `core.audio_unit`, `core.audio_unit_v2`, and every declaration rooted there, including `RenderAdapter`, AUv2 ABI records, selectors, properties, factories, and dispatch adapters | Experimental | Portable ABI, component, automation, state, multi-output, installed-package, and cross-target tests pass. Real Apple-host validation is still required. Specification constants and external records change only to follow Audio Unit v2. |

Every public declaration re-exported by `parameters`, `realtime_audit`, `dsp`,
`resource`, `process`, `state`, and `units` is compatibility-ready. That status
does not imply that every possible DSP algorithm is complete. It means existing
names and checked behavior are candidates for compatibility preservation. New
algorithms remain additive.

## Standalone API

| Public declarations | Classification | Contract |
| --- | --- | --- |
| `AudioCallback`, `AudioDevice`, `CallbackBlock`, `DeviceAudioBlock`, `DeviceChannelRouter`, `BoundedDeviceChannelRouter`, `DeviceChannelRouting`, `DeviceConfiguration`, `StandaloneRuntime`, `StandaloneApplication` | Compatibility-ready | Format-neutral callback, routing, processor, and transactional application lifecycle. Callback owners stay at a stable address until stop drains callbacks. |
| `DeviceCatalog`, `DeviceDescriptor`, `DeviceIdentifier`, `DeviceKind`, `maximum_device_identifier_bytes`, `maximum_device_name_bytes`, `DeviceSelection`, `DeviceSelectionResolution`, `DeviceSelectionTracker`, `DeviceRecoveryCallback`, `DeviceRecoveryController`, `DeviceRecoveryReason`, `DeviceRecoveryResult`, `DeviceFailureMonitor`, `DeviceFailureMonitorSet`, `DeviceFailureReport`, `DeviceFailureSnapshot`, `DeviceFailureSource` | Compatibility-ready | Bounded discovery, persistence, failure observation, and transactional recovery. Physical recovery remains external evidence, not a reason to weaken the format-neutral contract. |
| `Midi1CallbackPacket`, `Midi1BlockScheduleReport`, `Midi1BlockScheduler`, `Midi1EventBuffer`, `Midi1InputCallback`, `Midi1InputDevice`, `Midi1InputQueue`, `Midi1OutputDevice`, `Midi1OutputReport`, `Midi1OutputSink`, `TimestampedMidi1Packet`, `TimestampedUmpPacket`, `UmpBlockBuffer`, `UmpBlockPacket`, `UmpBlockScheduleReport`, `UmpBlockScheduler`, `UmpInputCallback`, `UmpInputDevice`, `UmpInputQueue`, `UmpOutputDevice`, `UmpOutputReport` | Compatibility-ready | Fixed-capacity MIDI and UMP device boundaries and schedulers. Queue and callback owners require stable addresses until close or reset. |
| `StandaloneShell`, `StandaloneWindow`, `StandaloneWindowBackend`, `StandaloneWindowEvent`, `StandaloneWindowEventPumpReport`, `StandaloneControlCycleReport`, `maximum_device_failure_sources` | Experimental | The toolkit-neutral shell contract is coherent, but physical window integration is incomplete. |
| `ClockDriftConfig`, `ClockDriftController`, `BoundedCaptureFifo`, `BoundedCaptureRateBridge`, `BoundedCaptureRateCallbackAdapter`, `CaptureRateCallbackAdapterConfig`, `CaptureRateCallbackStatistics`, `CaptureFifoReadReport`, `CaptureFifoStatistics`, `CaptureFifoWriteReport`, `CaptureRateBridgeConfig`, `CaptureRateLifecycleConfig`, `CaptureRateOperatingState`, `CaptureRateOverflowPolicy`, `CaptureRateUnderflowPolicy`, `CaptureRateRenderReport`, `CaptureRenderBlock`, `SplitAudioCallback` | Experimental | Names and defaults are retained after review. Zero thresholds and cadence preserve immediate rendering, per-callback correction, and silence substitution. Rebuffering is opt-in. Reports are output records, not caller construction inputs. Unknown policy values fail before state or output mutation. `reset` requires quiescent capture and render callbacks and restores configured startup state. The bridge, adapter, FIFO, scheduler, and callback context must remain at stable addresses while callbacks retain them. Physical disparate-clock confirmation is still required. |
| `maximum_routed_channels` | Compatibility-ready | A checked bound used by the format-neutral routing contract. |

Standalone enums that describe repository-owned, growing state use an explicit
integer tag and an unnamed value so additions do not make the ABI itself
exhaustive. Public operations still reject values they do not understand.
Protocol enums remain exhaustive when the external specification defines a
closed value set.

## ARA

Every public declaration rooted at `ara_document_controller`,
`ara_content_fades`, `ara_extension`, `ara_factory`, `ara_model`,
`ara_playback_renderer`, `ara_registration`, `ara_source_cache`,
`ara_spectral_transform`, `ara_tempo_warp`, and `ara_tuning_analysis` is
experimental. This includes their `Error`, `Limits`, `Config`, analysis result,
cache, renderer, controller, extension, registration, and construction
declarations. The implementation and host-contract fixtures are substantial,
but a real ARA host has not confirmed the product-facing shape.

Every declaration rooted at `ara_vst3` is compatibility-ready as an external
ABI mirror. Its interface records, identifiers, role flags, and entry-point
construction change only to follow the official ARA VST3 companion API.

## Supported VSTGUI Authoring Layer

Every declaration rooted at `vstgui` and `vstgui_lv2_backend` is experimental.
This includes parameters, meters, graph and viewport models, range selection,
preset and action controls, editable labels, progress, piano and sequencer
models, file import, assets, drawing, fonts, skin, theme, layout, style,
composition, editor descriptions, editor constructors, LV2 controls, peak
sources, and backend constructors.

These declarations are the supported optional VSTGUI authoring layer. Native
adapter, sanitizer, accessibility bridge, visual regression, headless editor,
and installed-package tests protect them. Live assistive-technology behavior,
Wayland clipboard behavior, native visual confirmation, and broader real-host
editor lifecycle evidence remain external.

## Removed Leakage and Migration

| Removed declaration | Classification | Migration |
| --- | --- | --- |
| `zig-vst3-plugin.backendVersion()` | Internal leakage | Use `zig-vst3-plugin.version`. The removed function only forwarded the same raw-package development string and had no repository or installed-consumer use. |
| `zig-vst3-plugin-core.lv2_metadata` | Redundant internal leakage | Use `zig-vst3-plugin-core.lv2.metadata`. Metadata is part of the LV2 namespace, and the duplicate root path had no repository or installed-consumer use. |

## Enforcement

`tests/installed-consumer/framework_api_manifest.zig` uses compile-time
reflection to require an explicit classification for every declaration in the
two installed framework module roots. Additions, removals, and duplicate
manifest entries fail the staged installed-package gate.

`tests/installed-consumer/rc1_api_baseline.zig` freezes the compatibility-ready
module-root declarations at exact candidate commit
`7650781a5625c041ec474a5377d859a427a344f3`.
`framework_api_compatibility.zig` compares that baseline with the current
manifest. A silent removal or reclassification fails. An accepted later-minor
removal must name its deprecation release, effective release, last supported
release, replacement, and release note.

`tests/installed-consumer/public_api.zig` compiles the compatibility-ready entry
points and all provisional integration roots from a staged installed package.
It rejects restoration of the two removed leaks and verifies that a split
callback retains the adapter's stable address. Existing focused tests cover
malformed retained state, failure silence, quiescent reset, callback drain, and
retry. ABI, validator, sanitizer, native, and cross-target gates remain separate
because a compile fixture cannot establish those properties.
