# Plugin Framework Interface

`zig-vst3-plugin` is the framework package for writing plugins without hand-writing VST3 COM objects. A plugin is a Zig type with host metadata, a `Params` declaration, and optional lifecycle hooks. The framework reflects that type into parameter metadata, state, automation, events, bus topology, units, programs, and the reusable raw VST3 shells.

Use this package for normal effects, instruments, analyzers, and event processors. Drop to `zig-vst3` only when you need direct SDK interface control.

## Minimal Plugin

```zig
const plug = @import("zig-vst3-plugin");

pub const Gain = struct {
    pub const name = "Simple Gain";
    pub const vendor = "Example Audio";

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(
        _: *Gain,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        const gain: f32 = @floatCast(params.load("gain"));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Gain);
pub const Instance = plug.plugin.PluginInstance(Gain);
pub const Runtime = plug.plugin.ProcessorRuntime(Gain);
```

`PluginSpec(Plugin)` validates and reflects the declaration. `PluginInstance(Plugin)` owns a plugin value, parameter storage, state helpers, and bound metadata handles used by tests and the VST3 shell.

`ProcessorRuntime(Plugin)` adds a format-neutral lifecycle contract around the instance. VST3, future plugin formats, standalone applications, and offline tools can translate their host data into the same `ProcessContext` instead of defining different processor lifecycles.

## Metadata

Every plugin declares:

- `name`: host-facing plugin name.
- `vendor`: factory vendor string.
- `Params`: a struct of parameter descriptors. Use `struct {}` for plugins without parameters.

Optional declarations include:

- `url` and `email`: factory contact metadata.
- `component_class_name` and `controller_class_name`: VST3 class names.
- `component_category` and `controller_category`: VST3 class categories.
- `audio_input_layout` and `audio_output_layout`: main audio bus layouts. Valid values cover `.none`, mono, ordinary and wide, surround, center, and side stereo pairs, cinematic and music 3.x, 4.x, 6.x, and 7.x layouts, 5.0, 5.1, 5.0.2, 5.1.2, 5.0.4, 5.1.4, 7.0.2, 7.1.2, 7.0.4, 7.1.4, and first- through seventh-order ACN ambisonics.
- `maximum_auxiliary_audio_buses`: compile-time capacity from zero through 254. The default is eight.
- `audio_auxiliary_input_layouts`: auxiliary input layouts within the selected capacity. They require a main audio input.
- `audio_auxiliary_output_layouts`: auxiliary output layouts within the selected capacity. They require a main audio output.
- `audio_sidechain_layout` and `audio_auxiliary_output_layout`: compatibility declarations for one auxiliary bus in the corresponding direction.
- `audio_input`, `audio_output`, `event_input`, and `event_output`: legacy audio-presence flags and event bus topology flags.
- `units`: unit and program-list metadata.

Default topology is a stereo effect with audio input, audio output, event input, and no event output. Declare matching layouts for ordinary effects, `.mono` input with `.stereo` output for a mono-to-stereo effect, `.none` input for a generator, or `.none` output for an analyzer. The older `audio_input = false` and `audio_output = false` declarations remain supported. Do not declare a legacy flag that conflicts with an explicit layout. Set `event_output = true` for processors that emit events.

```zig
pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
```

Declare a sidechain effect with a main stereo input, an inactive-by-default mono auxiliary input, and a main stereo output:

```zig
pub const audio_input_layout: plug.plugin.AudioBusLayout = .stereo;
pub const audio_sidechain_layout: plug.plugin.AudioBusLayout = .mono;
pub const audio_output_layout: plug.plugin.AudioBusLayout = .stereo;
```

Declare multiple auxiliary buses with fixed layout slices:

```zig
pub const audio_auxiliary_input_layouts:
    []const plug.plugin.AudioBusLayout = &.{ .mono, .stereo };
pub const audio_auxiliary_output_layouts:
    []const plug.plugin.AudioBusLayout = &.{ .mono, .stereo };
```

`PluginInstance` exposes the bus lists through `audioAuxiliaryInputBusCount`, `audioAuxiliaryInputLayout`, `audioAuxiliaryOutputBusCount`, and `audioAuxiliaryOutputLayoutAt`. The older single-bus accessors return the first declared auxiliary bus. Do not declare a list and its compatibility declaration together.

Processing contexts retain the flattened `sidechainInput*` and `auxiliaryOutput*` accessors for compatibility. Use `auxiliaryInputBus`, `auxiliaryOutputBus`, `auxiliaryInputBusCount`, and `auxiliaryOutputBusCount` when bus boundaries matter. A host may omit inactive trailing auxiliary buses or provide fewer active channels, but it cannot expose more buses or channels than the declaration permits.

`BoundedDynamicAudioBusTopology(maximum_auxiliary_buses)` and its matching snapshot type provide the allocation-free live topology model for compile-time capacities from zero through 254 auxiliaries per direction. Each bus owns its current layout, checked supported-layout set, default activation state, and current activation state. Whole-arrangement negotiation, activation, insertion, and removal validate before mutation and advance a rollover-safe generation after each effective change. Invalid and no-op requests preserve the complete topology and generation. State counts remain one byte, so every capacity uses the existing version-2 encoding. Larger capacities read smaller states, while smaller capacities reject oversized states before reading any bus payload.

`DynamicAudioBusTopology` and `DynamicAudioBusSnapshot` remain the eight-auxiliary compatibility instantiations. Declare `audio_bus_topology` with a bounded topology type to enable plugin-initiated VST3 changes; its capacity becomes the plugin capacity. Static plugins select another capacity with `maximum_auxiliary_audio_buses`. `PluginSpec` carries the selected topology, snapshot, process-context, and wrapper storage types. VST3 retains that type through metadata, negotiation, processing, publication, and state. LV2 and AUv2 use it for their static ports and buses. Standalone, offline, routing, ALSA, CoreAudio, and WASAPI paths expose matching bounded types. Integrations that construct `SimpleEffect` directly may declare the topology or capacity. Eight remains the default, so existing declarations and process signatures do not change.

The component owns the mutable control-thread model and publishes fixed-size immutable snapshots to processing. `getBusCount`, `getBusInfo`, `activateBus`, arrangement negotiation, zero-sample flush validation, and nonzero process-context construction consume that shared topology contract. The audio callback performs no allocation and takes no topology mutex.

Plugin control code can use `HostRequestSink.setAudioBusLayout`, `addAuxiliaryAudioBus`, or `removeAuxiliaryAudioBus`. Successful effective changes publish one snapshot and mark `kIoChanged`; call `dispatchPending` outside processing to notify the host. The raw `SimpleEffect` type exposes matching operations plus `audioBusTopologySnapshot` for integrations that own the component interface directly. Host-initiated arrangement and activation callbacks update the published topology without sending a redundant restart.

Dynamic topology is included in the versioned component-state envelope, remains readable by the reflected controller, and restores transactionally. Layout-set state version 2 uses a forward-capable 64-bit mask and accepts version-1 16-bit masks without reinterpreting any existing layout identifier. A changed restore publishes a fresh local generation and marks `kIoChanged`. Advertised and processed topology share one bounded bus-count contract.

## Lifecycle Hooks

The framework calls only the hooks a plugin declares:

```zig
pub fn init(allocator: std.mem.Allocator) !Plugin
pub fn prepare(self: *Plugin, config: plug.plugin.PrepareConfig) void
pub fn activate(self: *Plugin) void
pub fn deactivate(self: *Plugin) void
pub fn reset(self: *Plugin) void
pub fn releaseResources(self: *Plugin) void
pub fn afterStateRestore(self: *Plugin) void
pub fn latencySamples(self: *const Plugin) u32
pub fn tailSamples(self: *const Plugin) u32
pub fn process(self: *Plugin, context: *plug.process.ProcessContext(f32)) void
pub fn process64(self: *Plugin, context: *plug.process.ProcessContext(f64)) void
pub fn processWithParameterView(
    self: *Plugin,
    context: *plug.process.ProcessContext(f32),
    params: plug.parameters.ParameterView(Plugin.Params),
) void
pub fn process64WithParameterView(
    self: *Plugin,
    context: *plug.process.ProcessContext(f64),
    params: plug.parameters.ParameterView(Plugin.Params),
) void
pub fn processWithParameters(
    self: *Plugin,
    context: *plug.process.ProcessContext(f32),
    set: *const plug.parameters.ParameterSet(Plugin.Params),
    values: *const plug.parameters.ParameterValues(Plugin.Params),
) void
pub fn process64WithParameters(
    self: *Plugin,
    context: *plug.process.ProcessContext(f64),
    set: *const plug.parameters.ParameterSet(Plugin.Params),
    values: *const plug.parameters.ParameterValues(Plugin.Params),
) void
pub fn deinit(self: *Plugin) void
```

Use `processWithParameterView` for most plugins. Use the plain `process` hook when you want to read sample-accurate automation from the `ProcessContext`. Use the `process64` variants when the plugin supports 64-bit processing.

`ProcessorRuntime` enforces `initialized -> prepared -> active` transitions. Processing requires an active runtime and a context whose sample rate, mode, and block size match the preparation contract. Deactivation calls `deactivate` and `reset`. Resource release returns the runtime to its initialized state. Teardown performs any remaining deactivation, reset, and release before `deinit`.

Parameter-only host flushes use `flushParameterChanges`. State restore is rejected while the processor is active and invokes `afterStateRestore` after a successful parameter-state decode. State encoding remains available through `writeParameterState`.

The runtime rejects f32 or f64 processing when the plugin does not declare a hook for that precision. It also rejects malformed audio views, parameter queues, event queues, transport state, and output-event writers before invoking plugin processing.

`audio_unit.RenderAdapter(Plugin, maximum_block_size)` is the host-independent Audio Unit render core. It maps negotiated sample rate, maximum frames, initialize, uninitialize, reset, f32 or f64 deinterleaved rendering, main and auxiliary buses, automation, events, output events, transport, latency, and tail reporting onto `ProcessorRuntime`. Rejected blocks clear every supplied output and increment retained statistics. `audio_unit_v2` supplies SDK-checked component, buffer-list, timestamp, parameter-info, parameter-event, stream-description, callback, selector, scope, property, render-flag, and status declarations. Its dispatch layer covers lifecycle, property sizing and writability, static bus counts, f32 or f64 planar stream negotiation, maximum frames, latency, tail, input pull callbacks, reflected parameter lists and metadata, immediate get and set, bounded transactional point and ramp scheduling, Core Foundation class-info state, bounded property listeners, bounded pre-render and post-render notifications, and allocation-free multi-output rendering. Continuous writable parameters advertise `kAudioUnitParameterFlag_CanRamp`. Native `ParameterRamp` attachments interpolate without per-sample event expansion, accept negative start offsets for cross-block progress, preserve stored ordering at equal offsets, and publish the boundary value for the next block. Valid sample-time or host-time identities key a fixed-storage block cache so main and auxiliary output buses can be requested in any order without duplicate processing or automation application. Render failures clear supplied outputs, set `kAudioUnitRenderAction_OutputIsSilence`, and issue a post-render-error notification. Callback tuple registration is idempotent, precise removal includes user data, deprecated listener removal clears every matching procedure, and callback snapshots permit removal during notification without invalidating the current pass. `audio_unit_v2.ComponentFactory` owns stable per-instance render, property, and dispatch storage through host close. On macOS, `NativeComponentFactory` returns retained class-info dictionaries that contain the bounded generic parameter state. Restore is transactional and invalidates cached render and automation data. The Mono Gain reference exports that factory from a dynamic library, builds a registered sandbox-safe `.component` bundle, validates its plist and symbol, and passes a dynamic host fixture that exercises property listeners and render notifications, renders an exact four-frame gain ramp, then saves, mutates, and restores state. The Auxiliary Output Splitter reference builds a second registered component with stereo main, mono auxiliary, and stereo auxiliary outputs. Its dynamic host requests output buses out of order, verifies all five channels, and observes one input pull for the shared block. The public installed package and Linux AArch64, Linux x86-64, and Windows x86-64 cross-builds cover the portable layers and the complete multi-output reference. External AU host validation remains.

## VST3 Runtime Adapter

`Vst3Effect(Plugin, Config)` builds a VST3 component from the same high-level declaration used by `PluginInstance`, `ProcessorRuntime`, and `OfflineRenderer`:

```zig
const Effect = plug.Vst3Effect(Gain, struct {
    pub const component_name = "GainComponent";
    pub const controller_cid = controller_cid;
});

const Controller = plug.Vst3Controller(
    Gain,
    "GainController",
);
```

The effect constructor derives main and auxiliary audio layouts, dynamic topology, event buses, host-transport requirements, parameter metadata, and `Vst3Processor(Plugin)`. Its configuration retains only VST3 integration choices: component name, controller class ID, optional resource or decoded-audio target IDs, GUI note input, and explicit extra process-context requirements. `Vst3Controller` creates an ordinary reflected controller from the same declaration. Specialized controllers continue to use `ReflectedEditController` directly. `Vst3EffectWithParameters` and `Vst3ControllerWithParameters` accept configured parameter descriptors and own matching parameter sets.

The processor adapter uses the page allocator only during component construction. It maps VST3 setup and activation to the checked runtime state machine, releases prepared resources on deactivation, and prepares them again on reactivation. VST3 precision negotiation, latency, and tail reporting reflect the hooks declared by the plugin. Processing remains allocation-free. `Vst3Processor` remains available when an integration needs to construct `SimpleEffect` directly.

The VST3 component remains authoritative for host parameter serialization. The adapter synchronizes runtime values before processing, after zero-sample parameter flushes, and after component-state restore. A successful restore invokes the high-level `afterStateRestore` hook. Bounded component payloads, connection readiness, and the format-neutral `HostRequestSink` also pass through the adapter. Optional plugin hooks receive resource paths, decoded-audio imports, scalar, graph, and bounded text telemetry requests, and editor-open and editor-close notifications. Compile-time capability flags keep unsupported interfaces undiscoverable. `Vst3ProcessorWithParameters` accepts a non-default compile-time `Params` value when parameter descriptors are configured rather than default constructed.

The low-level `SimpleEffect` processor contract remains supported for conformance probes and direct component extensions outside the high-level contract. A high-level plugin with self-referential state can allocate its engine first, initialize it at that stable address, and destroy it from `deinit`.

IR Loader is the reference decoded-audio migration. Its controller still imports, edits, publishes, clears, and rolls back bounded impulse responses through the existing component messages, while `Vst3Processor` owns the processor lifecycle and forwards the import receiver. The large partitioned convolver remains at a stable heap address and supports both VST3 sample precisions.

Resource Swap is the reference stable-address background-worker migration. Its runtime allocates the engine before `initInPlace` submits a request containing the address of the engine's publication exchange. Runtime teardown stops and joins the worker, retires published resources, and only then destroys the engine. This pattern is required whenever initialization publishes or captures an internal address.

Model Shell extends the stable-address pattern to persistent resource recovery. Its high-level wrapper forwards component state, import and relink commands, latency host requests, scalar and bounded text telemetry, and typed f32 and f64 processing. The recovery worker is joined before the engine address is released.

Sample Player is the combined payload reference. The high-level runtime receives decoded samples, processes MIDI events and sample-accurate parameter changes in f32 or f64, publishes its bounded playhead graph, and enables that publication only while an editor is open. Its specialized controller continues to own file decoding, waveform preview, view state, actions, and import replacement.

Channel Strip is the combined scalar and graph telemetry reference. It runs f32 and f64 processing through typed parameter views, publishes three activity-gated meters plus waveform and spectrum graphs, and forwards editor activity without moving importer or editor state into the processor.

Parametric EQ and Resonant Filter are the graph-only references. Their high-level processors publish activity-gated spectrum data while specialized controllers retain parameter-driven response curves, linked handles, presets, view state, and responsive editor composition.

## LV2 Core Adapter

`plug.lv2.CoreAdapter(Plugin, plugin_uri, maximum_block_size)` exports a static f32 plugin declaration through the LV2 core ABI. `CoreAdapterWithParameters` accepts a configured compile-time parameter set.

Ports use deterministic declaration order:

1. Main input channels, followed by every auxiliary input bus.
2. Main output channels, followed by every auxiliary output bus.
3. An Atom Sequence input when the declaration accepts events.
4. An Atom Sequence output when the declaration emits events.
5. One control input for each reflected parameter.
6. One latency control output.

Control inputs use each parameter's plain-unit range. Values are validated and converted through the reflected parameter descriptors before each nonzero run. The adapter supports zero-frame latency queries, activation and reactivation, unconnected ports, and deterministic output silence for malformed controls, oversized blocks, inactive processing, or processor failure. Instantiation and cleanup use the allocator. Port connection and run callbacks do not allocate or lock.

Generated LV2 metadata groups the flattened audio ports back into their declared streams. Main input and output resources use `pg:mainInput` and `pg:mainOutput`. Every auxiliary input is an input group with `pg:sideChainOf` when a main input exists, and the main output identifies the main input as its source. Mono, stereo, common surround, and first- through third-order ACN layouts use the matching standard port-group classes and channel designations. Other discrete, immersive, and fourth- through seventh-order ACN layouts retain generic discrete or ambisonic group classes where the vocabulary has no exact class or designation. Group symbols are generated in the same namespace as port symbols, and parameter metadata that collides with them is rejected before output.

Atom event ports use frame timestamps and a fixed 256-event stack bound per run. MIDI note on, note off, polyphonic key pressure, control change, and pitch bend translate to and from typed framework events. Other complete valid MIDI messages, including Program Change, Channel Pressure, System Common, System Real-Time, and SysEx, cross the processor boundary as data events tagged with the host's MIDI event URID. Other nonzero Atom types retain their URID and bounded body bytes in data events. Plugins may inspect, transform, or echo those bytes without allocation. Malformed sequence boundaries, timestamps, types, or MIDI payloads reject the run transactionally. Output serialization observes the capacity supplied by the host and preserves 64-bit Atom offsets. Boundary reads and writes remain safe even if a hostile host supplies a port base with only byte alignment.

Time Position objects update a persistent transport snapshot. The adapter validates native Atom scalar types for frame, speed, beat, bar, meter, tempo, and frame rate, converts LV2 beat units to framework quarter notes, and advances real and musical positions between updates and runs. A Position object after frame zero splits the block at that offset. Audio slices, MIDI input, parameter changes, emitted events, and transport snapshots retain block-relative semantics across every segment. Partial Position updates retain prior fields. Rejected runs restore the prior transport snapshot and clear connected audio and event outputs.

A plugin may declare both `allow_dynamic_process_mode = true` and `lv2_freewheeling = true`. The adapter then publishes a toggled control input designated `lv2:freeWheeling`. It samples that control once at each non-empty `run` boundary and supplies `.offline` to every segment when the finite value is positive, or `.realtime` when it is zero or negative. The port is required for opted-in products. A missing or non-finite control rejects the block and clears connected outputs. Dynamic process modes remain disabled by default, so other runtime consumers continue to require the mode used during preparation.

Plugins that inspect host-defined Atom types may opt into URI reverse mapping by declaring `lv2_urid_unmap_required = true` and implementing `bindLv2UridUnmap`. The binding receives the host's `UridUnmap` feature for the plugin instance lifetime. Its `unmap` callback returns a stable null-terminated URI for a known identifier or null when the identifier is unknown. The adapter rejects construction when the required feature is absent, null, or misaligned, and generated metadata adds `urid:unmap` to the required features. Plugins that do not declare the opt-in retain the existing construction contract.

The adapter exposes the LV2 State interface through `extension_data`. When the host supplies the standard URID map feature, parameter state is stored under the plugin URI plus `#parameterState` as a portable POD Atom Chunk. A plugin that declares `component_state_maximum_encoded_size`, `writeComponentState`, and `readComponentState` receives a second property under `#componentState`. Component state is limited to 64 KiB. Resource-backed plugins may add `writeLv2ComponentState` and `readLv2ComponentState`. These hooks receive `StatePathFeatures`, which maps absolute paths to portable abstract paths, resolves abstract paths during restore, creates host-managed paths when `lv2_state_requires_make_path` is true, and returns `OwnedStatePath` values that must be released with `deinit`. Generated metadata requires `state:mapPath` and `state:freePath`, plus `state:makePath` when declared. The adapter rejects missing or misaligned required features before state access. Restore validates both properties before mutation, rejects unread trailing bytes, and restores the previous parameter snapshot when component or path decoding fails. A successful component restore invokes `afterComponentStateRestore` when present. Missing parameter state resets parameters to defaults; missing component state leaves the current component payload unchanged.

Plugins can expose dynamic LV2 properties with `lv2_patch_properties`, `readLv2PatchProperty`, and `writeLv2PatchProperty`:

```zig
pub const event_input = true;
pub const event_output = true;
pub const lv2_patch_response_capacity = 1024;
pub const lv2_patch_properties = &[_]plug.lv2.PatchProperty{
    .{
        .uri = "https://example.test/plugin#resource",
        .value_kind = .path,
        .readable = true,
        .writable = true,
    },
};

pub fn readLv2PatchProperty(
    self: *const @This(),
    index: usize,
) !plug.lv2.PatchValue {
    if (index != 0) return error.UnknownPatchProperty;
    return .{ .path = self.resource_path };
}

pub fn writeLv2PatchProperty(
    self: *@This(),
    index: usize,
    value: plug.lv2.PatchValue,
) !void {
    if (index != 0) return error.UnknownPatchProperty;
    const path = switch (value) {
        .path => |item| item,
        else => return error.InvalidPatchValue,
    };
    try self.setResourcePath(path);
}
```

Writable properties require an event input. Readable properties also require an event output and an explicit aggregate response capacity from 64 bytes through 64 KiB. The adapter handles property-specific `patch:Set` and `patch:Get` objects. Sets take effect at their event frame before the following audio segment. Gets return a `patch:Set` at the same frame and preserve an explicit subject and sequence number. Sequence number zero suppresses the response. Supported values are Bool, Int, Long, Float, Double, String, Path, URI, and URID Atoms. String-like input borrows host storage only for the write callback, and Path values must be absolute. The adapter validates the complete input sequence before invoking a property hook, ignores unknown properties and foreign subjects, bounds response serialization, and clears connected outputs when a recognized message is malformed or a response does not fit. Generated metadata lists readable and writable properties and marks both event ports as supporting `patch:Message`. General Put, Patch, Insert, Delete, Copy, and Move requests are not part of this typed property boundary.

Plugins with declared program lists expose the KXStudio LV2 Programs interface automatically. Each nonnegative `ProgramList.id` is the LV2 bank number and each program's declaration index is its program number. Enumeration uses fixed instance storage, so descriptors and names remain valid for the required lifetime. A valid selection applies the program's normalized parameter snapshot on the next run and updates connected writable control ports immediately when their storage is valid. If a port cannot be written safely, the selected value remains active until the host sends a different control value. Invalid selections are ignored, partial programs retain unspecified values, and successful state restore clears any pending program override.

The optional LV2 Worker extension is enabled when a plugin declares `lv2_worker_maximum_request_size`, `lv2_worker_maximum_response_size`, `bindLv2WorkerSchedule`, `runLv2Worker`, and `applyLv2WorkerResponse`. Both size limits must be between 1 byte and 64 KiB. The binding hook receives an instance-owned `WorkerScheduleSink`; its `schedule` method accepts work only while the adapter is inside `run` and returns the host's Worker status. A missing host schedule feature leaves the plugin usable but makes scheduling return `unknown`. An advertised schedule feature with null or misaligned data rejects construction.

`runLv2Worker` receives bounded request bytes on the host's non-realtime worker and may send bounded responses through the supplied `WorkerResponseSink`. The response sink is valid only for that callback. `applyLv2WorkerResponse` receives responses in the host's `run` context. A plugin may also declare `endLv2WorkerRun`. Worker execution may overlap audio processing, so plugin state shared between `runLv2Worker` and processing needs an explicit realtime-safe synchronization design. The adapter performs no allocation or locking in its schedule or response paths.

`plug.lv2.metadata.Generator` writes the manifest, plugin description, and standard Presets vocabulary data from the same plugin, adapter, URI, and initial parameter declaration used by the binary. It derives port indexes, symbols, names, ranges, defaults, event capabilities, Options, State, optional Worker declarations, and the Programs interface when program lists exist. Factory presets identify values by parameter field symbol. Optional `ProjectMetadata` writes a linked project name, license URI, and maintainer name, `mailto:` URI, and homepage. The top-level metadata can also declare long and short descriptions and live-use intent. Optional `UiMetadata` associates the plugin with a separate UI URI, class, and binary and declares parent, resize, touch, idle, show, hide, and Programs UI capabilities. Generation rejects malformed URIs, maintainer email URIs, filenames, text, symbols, duplicate preset slugs or parameters, unknown parameters, and non-finite or out-of-range values. The Mono Gain build generates Unity and Muted metadata plus its project and distribution metadata into a transactional staged bundle, so hosts can discover them without loading the shared library. The generated Turtle passes the LV2 1.18.10 schema validator with zero errors and passes `lv2lint` 0.16.2 with warnings treated as errors in direct-distribution mode. `zig build lint-lv2-mono-gain` reproduces both checks when the external tools are installed. `LV2_VALIDATE` and `LV2LINT` select explicit executables.

The optional LV2 Options feature may provide instance-level minimum, maximum, and nominal block lengths as Atom Int values during construction. The maximum narrows the adapter's compile-time capacity and the runtime preparation contract. A null or misaligned advertised feature, zero or negative maximum, negative minimum or nominal value, oversized maximum, repeated or mistyped value, unterminated array, or internally inconsistent set rejects instantiation without publishing a partial instance. The same checked decoding applies to the advertised URID map feature before any callback is invoked.

The Options interface returns stable Atom Int values for all three supported bounds. `set` validates the complete request before changing the instance. A maximum change while active is rejected. While inactive, a valid maximum change reprepares the processor; the published bounds change only after preparation succeeds, and a preparation failure returns the unknown status after attempting to restore the previous preparation. Unknown keys, unsupported subjects, repeated keys, invalid Atom values, and unterminated arrays return the standard composable Options status bits.

`plug.lv2.ui.Adapter` exports one LV2 UI descriptor over the shared `gui.Editor` contract. A backend constructs the editor and returns its native child widget after parent attachment. The bridge converts plain f32 control-port events to normalized editor values and normalized editor gestures back to host writes. It supports optional host touch and resize features plus idle, host resize, show, hide, and Programs UI interfaces. Program selection updates affected editor parameters without echoing writes or gestures to the host. Instantiation validates the plugin URI, required parent feature, write callback, widget output, backend construction, attachment, and widget creation before publishing a handle. Null or misaligned optional touch and resize data is ignored rather than cast. Descriptor callbacks and editor callbacks share the same checked handle conversion, so a misaligned handle cannot reach editor state through either path. Malformed port events and resize requests are ignored or rejected without partially updating the editor.

`vst3.vstgui_lv2_backend.Backend` is the optional production backend for reflected parameter editors:

```zig
const VstguiBackend = vst3.vstgui_lv2_backend.Backend(.{
    .controls = &.{.{
        .parameter_id = 0,
        .kind = .decibel_slider,
        .tooltip = "Adjust the output gain.",
    }},
    .initial_size = .{ .width = 400, .height = 300 },
});
```

It derives parameter names, units, values, and formatting from the shared GUI context. Control declarations can select a continuous, integer, or decibel slider, a toggle, or an enum menu. Attachment opens a VSTGUI editor against the required platform parent and publishes its native platform widget only after the complete operation succeeds. Idle flushing, focus, host parameter changes, host and UI resize, scale changes, gestures, parsing, formatting, context menus, detach, and destruction pass through checked callbacks. Failed opens, widget lookup, and rejected resize requests do not leave a partially attached editor.

The current LV2 boundary intentionally excludes dynamic audio topology and f64 audio ports. URI reverse mapping is available only through an explicit plugin opt-in because most plugins do not need to inspect host-defined identifiers. The VSTGUI backend covers parameter-driven editors. Products with advanced custom components still need a product-specific backend or an extension of this binding for every advertised UI class.

Build and exercise the included shared library and bundle with:

```sh
zig build test-lv2
zig build bundle-lv2-mono-gain
```

## Offline Rendering

`OfflineRenderer` is a host-independent, one-shot render consumer built on `ProcessorRuntime`. Its fixed capacities are compile-time bounds:

```zig
const Renderer = plug.plugin.OfflineRenderer(
    Gain,
    f32,
    512,
    64,
    128,
    128,
);

var renderer = try Renderer.init(allocator, .{});
defer renderer.deinit();

try renderer.render(.{
    .sample_rate = 48_000.0,
    .input_channels = &input_channels,
    .output_channels = &output_channels,
    .parameter_changes = &parameter_changes,
    .events = &events,
    .output_events = &output_events,
    .transport = transport,
});
```

The renderer validates the complete timeline, checks per-block input capacities before processing starts, slices main and auxiliary audio without allocation, rebases automation and events into each block, advances sample and musical transport positions, and restores emitted event offsets to the complete timeline. It supports f32 and f64 processors.

This is an offline standalone core, not a device-backed application. Audio device selection, live callback scheduling, device MIDI I/O, window ownership, and platform application lifecycle remain separate work.

## ARA Controller And Plugin Extension

`vst3.ara_factory.Factory(config, limits, controller_capacity)` publishes an ARA 2.0–2.3 factory backed by a fixed controller pool. Initialization validates the host generation and callback tables. `analyzeable_content_types` publishes a compile-time validated, duplicate-free list. An optional `controller_extension` supplies fixed state that the factory constructs, attaches, detaches, and retains beside each controller. Explicit slot phases reserve construction and teardown without holding the factory lock across product hooks, so attach and detach may query factory state reentrantly. Attach failure rolls back the reservation, detach failure still releases the slot, and active phases prevent factory shutdown. Pool exhaustion, invalid host input, extension failure, active-controller shutdown, and controller construction failures remain queryable through `takeLastError`.

`vst3.ara_document_controller.Controller(limits)` owns the document graph and complete ARA controller callback table. The graph uses fixed storage, generational object references, copied bounded names and persistent identifiers, transactional edits, dependency-aware destruction, and exact revision tracking. Model publication snapshots observer identities and checks each generation immediately before invocation. Observers added reentrantly wait for the next revision, while observers removed before their turn are skipped. A bounded generational pool permits multiple non-realtime host readers for the same source. Audio access supports planar f32 and f64 reads, validates channel and frame bounds, and republishes source-access transitions. Each read holds an atomic slot lease. The synchronous disable callback rejects new leases, waits for active reads, destroys every matching host reader, and only then returns. Controller destruction applies the same ordering.

A `ContentProvider` can publish notes, tempo entries, bar signatures, static tuning, key signatures, and sheet chords for an audio source, audio modification, or playback region. It may also report whether source analysis is incomplete, accept a validated nonempty subset of the factory's advertised analysis types, expose a stable list of processing algorithms, report and change the per-source selection, and invalidate product state when the host reports source-content changes. Algorithm changes require an active model edit and reject negative, unavailable, malformed, or provider-inconsistent indexes. Licensing queries validate the requested boolean, counted content-type pointer, unique advertised types, and transformation subset. Count and data callbacks receive one immutable query containing the object, content type, and optional time range. The count callback returns `null` when no reader is available and otherwise returns the exact bounded event count, avoiding mutable output storage across callback boundaries. Each reader retains its query, event count, and generation in bounded controller storage. `EventType(content_type)` maps a compile-time content type to the official ARA event structure. Public controller methods validate and send source-analysis progress and source-content-change notifications through the host model-update interface.

`vst3.ara_music_analysis.Analyzer(ControllerType, limits)`, also available through the compatibility name `ara_tuning_analysis`, is a bounded reference analysis extension. On the non-realtime model thread it reads a fixed leading source window, validates every channel, selects the channel with the greatest AC energy to avoid phase-cancellation loss, removes DC, and estimates a monophonic fundamental with normalized autocorrelation and sub-sample peak interpolation. Its polyphonic note path applies Hann-windowed semitone analysis with sub-semitone frequency refinement, fixed maximum polyphony, gap-tolerant temporal tracking, perceptually scaled volume, checked attack, note-off, and signal-end durations, and sorted transactional output. Multichannel sources are analyzed independently, then overlapping same-pitch events are merged so channel panning and polarity cannot erase notes. Silence publishes an available empty result. For tempo, it streams bounded source chunks into fixed per-channel RMS envelopes, selects the energetic channel, and derives a positive onset envelope. Overlapping local windows establish beat phase and estimate constant or piecewise variable tempo, prefer the shortest strong autocorrelation lag, stabilize octave relationships between adjacent windows, suppress changes below a configured ratio, and integrate continuous quarter positions into a bounded multi-point `ARAContentTempoEntry` map with an explicit quarter-zero sync point. A whole-source estimate is only a fallback when no local window succeeds, so continuously changing material does not require a misleading constant-tempo result. Output-capacity failure is transactional. It exposes stable General and Low-register processing algorithms through the official controller callbacks, and both algorithms support every content type advertised by the product. The selected per-source algorithm controls the tuning frequency and confidence range used for future tuning analysis. Changing it invalidates prior note, tuning, tempo, meter, key-signature, and chord results and notifies the host. Silence, malformed samples, insufficient data, unsupported channel counts, low-confidence pitch or tempo, and capacity exhaustion remain explicit. `approveEqualTemperament` publishes a checked 300–500 Hz user override with approved grade and a bounded copied name. Host source updates independently preserve note, timing, tuning, and harmonic scopes according to the official flags without discarding the algorithm selection. Version-8 records persist selection, tuning grade, concert pitch, name, tempo grade and points, note grade, and every checked note, bar-signature, key-signature, and chord field. Restore accepts versions 1 through 7 and converts version-3 phase and period records into two-point maps. Full and filtered restore use the controller's persistent-ID mapping, preserve unrelated sources, reject duplicate or malformed records, and commit only after the entire payload validates.

Meter analysis samples source onset strength on a tempo-mapped eighth-note grid. It distinguishes simple, odd, and compound templates for 2/4 through 12/8, selects the first downbeat phase, and confirms changes across configurable bounded bar windows. Every published change lies on an integer number of bars in the preceding signature. Tempo and meter commit together, so failed meter inference does not replace existing timing content. Version-8 analysis records persist validated bar signatures, key signatures, and chords and accept versions 1 through 7.

Key-signature analysis converts detected note times through the staged tempo map, weighs pitch classes by overlap duration and volume, and correlates all 24 major and natural-minor profiles in bounded quarter-note windows. Configurable score and runner-up margins reject weak or ambiguous material. Sustained evidence confirms changes before publication. Results use official circle-of-fifths roots, exact ARA interval masks, nullable display names, sorted quarter positions, harmonic-scope invalidation, and transactional capacity checks. A key request owns its note and tempo prerequisites, so caller request order cannot expose stale dependent content.

Chord analysis uses the same staged note and tempo prerequisites. It filters notes shorter than a configurable quarter-note duration, scores triad, suspended, sixth, seventh, added-tone, extended, and power-chord templates, identifies inversions from the lowest active pitch, rejects incomplete or ambiguous windows, confirms changes before publication, and emits all-unused interval events for sustained gaps. Events use official root, bass, diatonic-degree interval values, nullable names, and quarter positions. Combined chord and key requests run in canonical dependency order and retain prior dependent content only when refreshed notes and tempo are identical.

Controller archive version 2 appends a length-delimited product payload after the generic persistent-ID lists. `limits.archive_extension_bytes` bounds its inline storage and defaults to zero. Providers calculate an exact size, write into the controller's archive buffer, and restore from immutable bytes plus resolved source mappings. Version-1 archives remain readable. Restore binds its two-phase transaction to the initiating reader, clears pending state after failed decoding so the host may retry, and does not replace live document state until the complete archive validates. Oversized payloads, missing provider hooks, unknown versions, invalid filters, every truncated prefix, trailing bytes, corrupt headers, and provider rejection fail without partial provider mutation.

The controller implements full and filtered archive callbacks through the host archiving interface. Its encoding is bounded and versioned. Restore rejects malformed data, invalid mappings, missing current objects, oversized archives, and host I/O failure without publishing partial state.

`vst3.ara_extension.Extension(limits)` exposes bounded playback-renderer, editor-renderer, and editor-view roles. It copies assignments, selections, time ranges, and hidden sequences into stable control-thread state. Successful changes increment a revision and invoke a product callback, which can publish the snapshot through the product's realtime-safe exchange.

`vst3.ara_source_cache.Cache(ControllerType, Sample, limits)` bridges the non-realtime ARA reader API to realtime playback. `loadSource` opens the requested f32 or f64 host reader on a host-authorized model or control callback, fills an inactive fixed-capacity generation in place, closes the reader, and publishes only after the complete read succeeds. A failed open, read, capacity check, or publication leaves the previous generation active. `invalidate` publishes an unavailable generation, while generational source identity prevents a recycled model slot from exposing stale audio. The returned renderer provider performs no allocation, locking, I/O, or waiting. It acquires a bounded reference, validates source identity and format, copies the requested planar range, and releases the reference. Cache memory is fully inline and scales with sources, channels, frames per source, and publication slots, so products must choose limits deliberately. Keep the cache at a stable address from provider creation until every renderer using that provider has detached.

`vst3.ara_source_cache.PagedCache(ControllerType, Sample, limits)` provides the same renderer-provider contract for sources larger than a practical whole-source generation. Its fixed storage is divided into independently reference-counted pages and one reference-counted directory. `loadRegion` computes the source-frame working set for a render description, including interpolation padding. `loadRange` merges a caller-selected range, retaining matching pages and replacing the least-recently-used unprotected pages. `refreshRegion` and `refreshRange` force replacement after source-content changes. All required page writers and the next directory writer are reserved before host I/O. The cache fills every page, commits their immutable generations, and publishes the directory last. Failed validation, reservation, open, or read leaves the old directory active. Realtime reads pin one directory and validate each acquired page against its recorded generation, source identity, and logical page before copying. A publication race can produce a checked cache miss but cannot produce a successful mixed-page read. Explicit invalidation removes every matching directory entry without touching readers. Page count, page size, channel count, source slots, and publication depth are compile-time bounds.

`vst3.ara_content_fades.Analyzer(ControllerType, Sample, limits)` derives content-based head and tail fade descriptors without audio-thread host access. On the model thread it reads bounded source windows, validates every sample, selects the channel with the greatest AC energy, and searches for a zero crossing after the configured minimum fade. A bounded fallback applies when no crossing is present. Durations are converted through the region's modification-to-playback ratio and proportionally reduced when two requested fades would overlap beyond the region duration. The fixed-capacity analyzer publishes only for the exact source, region, transformation, format, and timing description it analyzed. Failed analysis leaves the prior descriptor intact, while source invalidation removes every matching entry. `configureProvider` attaches this state to a renderer provider without changing its realtime sample source.

`Controller.copyHostMusicalContextContent` and `copyHostAudioSourceContent` copy typed ARA content from optional host readers into caller-bounded storage. They validate availability, ranges, event counts, event pointers, and grades, and always destroy a successfully created host reader on success or failure. `vst3.ara_tempo_warp.Builder(ControllerType, limits)` uses those methods for host-provided tempo entries or accepts product-provided modification and context maps directly. Maps require finite, strictly increasing time and quarter positions, at least two sync points, and an explicit quarter-zero point. The builder merges every relevant source and context tempo boundary, verifies that mapped endpoints agree with the playback region, and publishes a bounded, strictly increasing piecewise warp only for the exact model revision and render description. Failed preparation retains the prior plan. Source or global invalidation removes stale plans.

`vst3.ara_playback_renderer.Renderer(ControllerType, Sample, limits)` is a reusable playback-role implementation for f32 or f64 products. It observes assignment and graph publications, resolves generational region references, and publishes an immutable render plan through `RealtimeSnapshotPublisher`. Construction requires a `SourceProvider`. Its control-thread `ready` callback confirms that product-owned cached or analyzed audio matches a render description, while its realtime `read` callback supplies samples without allocation, locks, I/O, or blocking. Optional model-thread callbacks supply exact fade descriptors and copy tempo-warp points into the immutable plan. `refreshSourceState` republishes the plan after cache readiness changes. The renderer never calls ARA's potentially blocking host audio or content readers from the audio thread. Rendering uses fixed planar scratch storage, binary-searched piecewise tempo mapping or ordinary playback-to-modification mapping, selectable linear, Catmull-Rom cubic, or eight-tap windowed-sinc source interpolation, linear, smoothstep, or equal-power content fades, overlap summing, and deterministic failure silence. Cubic mode reserves one preceding and two following source samples. Windowed-sinc mode reserves three preceding and four following samples, selects normalized Lanczos weights from a compile-time 1,024-phase table, preserves constant signals and exact source samples, and duplicates the nearest endpoint where the source has no neighbor. Its realtime path performs one phase lookup and eight multiply-adds per rendered sample and channel, without interpolation trigonometry. Its analytic high-frequency test verifies at least a tenfold RMS error reduction relative to linear interpolation. The current renderer accepts ordinary playback, duration-ratio time stretching, tempo-reflecting time stretching, and content-based head and tail fades. A product that needs phase-vocoder or other spectral editing should supply its own renderer over the same controller and extension contracts.

`vst3.ara_registration.MainFactoryRegistration(Config)` provides the matching VST3 main-factory class metadata and creation callback. `appendMainFactoryClass(product_classes, Registration)` produces the complete compile-time class array and rejects an ARA class ID that duplicates a product class ID. `SimpleEffect` and `HighLevelEffect` aggregate `IPlugInEntryPoint` and `IPlugInEntryPoint2` into the audio component when their config supplies `AraExtension`, `AraEntryPoint`, `ara_factory`, and `initAraExtension`. Optional `bindAraExtension(processor, extension)` and `unbindAraExtension(processor, extension)` hooks connect a processor to the extension only after both objects have reached their final addresses, then disconnect it before extension and processor teardown. This supports products whose audio callback delegates ARA rendering through processor-owned cache or analysis state without constructing dangling self-references. Queries through either ARA interface retain the canonical audio component identity. The exact ABI harness verifies the `getFactory` and bind vtable slots in addition to interface IDs and structure layouts.

`examples/ara_playback_plugin.zig` is the concrete reference assembly. It owns a bounded f64 stereo paged cache, content-fade analyzer, tempo-warp builder, and eight-tap windowed-sinc renderer. It advertises note, static-tuning, and source-tempo analysis, tempo reflection, and content-based head and tail fades, gives each factory-created document controller a bounded music analyzer, advertises the ARA main factory beside its VST3 component and controller, follows project sample time in the audio callback, and republishes silence after source invalidation. The f64 VST3 path renders directly. The f32 path converts through fixed component-owned scratch without allocation or locking. Its end-to-end playback test constructs a real document graph, copies source and context tempo maps, analyzes and loads the region through host callbacks, binds the role-specific entry point, assigns the playback region, and verifies exact fade and tempo-reflection samples through direct rendering and both `IAudioProcessor` precisions. A factory-created controller test verifies all three advertised analysis types, stable processing-algorithm properties, raw host sample access, an actual note-analysis request, and the returned A4 event. Native validation passes all 47 Steinberg checks for both precisions and reports the requested transport context, and the bundle cross-compiles for Linux x86-64, Linux AArch64, and Windows x86-64.

A product may use the music analyzer and reusable playback renderer or convert the published assignments into custom analysis, editing, and audio-rendering behavior. It must still choose any key, chord, or spectral behavior and validate the complete lifecycle in real ARA hosts.

## Live Standalone And Device Boundary

`StandaloneRuntime(Plugin, Sample)` runs the same high-level plugin declaration in realtime audio-device callbacks. `DeviceConfiguration` fixes the sample rate, maximum block size, main channel counts, and static auxiliary bus layouts before activation. Every callback is checked against that contract and against the plugin layouts.

`CallbackBlock(Sample)` carries non-interleaved main and auxiliary audio, sample-accurate parameter changes, input and output events, and transport. Callback processing performs no allocation or locking. Invalid layouts, malformed events, oversized blocks, and processor failures clear every main and auxiliary output before returning an error.

`DeviceChannelRouting` maps the processor's flattened input and output order onto a flat physical device stream. The order is main channels followed by each complete auxiliary bus. Input routes may repeat a physical channel or use `null` for deterministic silence. Output routes must be distinct, which prevents writable plugin channels from aliasing each other. `DeviceChannelRouter(Sample, maximum_block_size)` copies the route table and auxiliary bus boundaries into fixed storage, creates only borrowed channel views during callbacks, and clears every physical output before dispatch. Mapped outputs are then written by the processor while unmapped outputs remain silent. Validation failures, oversized device blocks, corrupted router state, and processor failures leave every supplied device output silent.

`ClockDriftController` converts a retained capture FIFO fill error into a bounded proportional-integral rate correction with an independent ppm limit and slew limit. `updateResampler` applies the correction to `StreamingResampler` without resetting its continuous phase or filter history, then commits controller state only after the resampler accepts it. Positive fill error consumes capture input faster; negative error consumes it more slowly. The controller owns no audio storage and performs no allocation or locking.

`BoundedCaptureFifo(Sample, maximum_channels, frame_capacity)` owns fixed inline planar storage for exactly one capture producer and one render consumer. A write publishes complete multichannel frames with release ordering after every channel is copied. A read acquires that publication, preserves frame order across wraparound, and zeroes only its unavailable tail. Overflow drops newest frames rather than racing the consumer-owned cursor. Statistics expose current fill plus saturating written, read, dropped, and silent frame totals. All channel, frame, cursor, alias, and overlapping-output validation finishes before publication or caller-output mutation. `updateDriftCorrection` samples the consumer-side fill, rejects a controller target larger than FIFO capacity, and transactionally updates the resampler. Keep the FIFO at a stable address while callbacks run. Stop both callbacks before `reset`. The product still decides its startup priming threshold and when device replacement, underflow, or overflow should reset the controller.

`BoundedCaptureRateBridge(Sample, maximum_channels, fifo_frame_capacity, maximum_capture_chunk, maximum_output_frames)` composes the FIFO, controller, bounded planar scratch, and one synchronized `StreamingResampler` per channel. The capture callback publishes planar blocks through `capture`. The render callback calls `render` with a complete output block. Rendering preflights the proposed correction and exact phase-dependent input demand for every channel, applies one correction, pulls exactly that many FIFO frames in bounded chunks, and produces the complete output span. It neither over-reads capture data nor needs a pending-input buffer. The returned report separates real and silent capture demand and includes the FIFO fill before and after the block. Mismatched timelines, malformed retained state, oversized blocks, and aliases fail before output mutation. Unexpected processing failures clear every supplied output. Stop both callbacks before rebuilding the bridge with `reset`.

`SplitAudioCallback(Sample)` is the native integration boundary for independently timed devices. Its capture function receives only flattened planar input channels. Its render function receives `CaptureRenderBlock`, which carries the render frame count, main and auxiliary outputs, parameter changes, events, output events, and transport. `BoundedCaptureRateCallbackAdapter` binds this split contract to an ordinary `AudioCallback`. It owns corrected planar input storage, restores the configured main and auxiliary input bus boundaries, invokes the existing processor callback on the render thread, counts capture and render failures independently, and clears every output when the device-facing render wrapper rejects a block. Direct `capture` and `render` methods retain checked error and report access for injected backends. Keep the adapter stable while either callback runs and call `reset` only after both stop.

`StandaloneApplication(Plugin, Sample)` coordinates a supplied `AudioDevice(Sample)` backend with the processor runtime. Starting the device is transactional: a backend start failure releases the prepared processor, and the same application may retry. Stopping drains device callbacks before deactivating and releasing the processor. A callback that outlives stop or failed startup is contained by the inactive runtime, clears every supplied output, and increments the retained failure count. The application must remain at a stable address while running because the device retains its callback context. Callback failures are counted atomically.

`Midi1InputDevice` and `Midi1OutputDevice` use owned three-byte channel messages with nanosecond timestamps. `Midi1InputQueue(capacity)` is a bounded single-producer, single-consumer bridge from the device callback to the audio callback. Producers must submit nondecreasing timestamps. `Midi1BlockScheduler` converts absolute timestamps to floor-rounded sample offsets, clamps late packets to offset zero, and retains future packets or packets that exceed the current event-buffer capacity. Its device callback adapter counts rejected packets atomically. Keep the scheduler at a stable address while the device retains its callback. Stop both callbacks before reset, and do not attach multiple producers or consumers to one scheduler. `Midi1EventBuffer` converts block-relative device packets into checked plugin events without allocation. Its validity and event view reject a corrupted public count, and `reset` restores the buffer. The scheduler validates that destination before removing any queued packet. `Midi1OutputSink` converts emitted events back to MIDI 1 and reports sent, unsupported, and rejected messages separately.

`UmpInputDevice` and `UmpOutputDevice` provide the same timestamped device boundary for complete Universal MIDI Packets. `UmpInputQueue(capacity)` and `UmpBlockScheduler(capacity)` preserve 32, 64, 96, and 128-bit packets in fixed storage, enforce nondecreasing producer timestamps, assign floor-rounded sample offsets, clamp late packets to offset zero, and retain future or capacity-limited packets. `UmpBlockBuffer(capacity)` deliberately carries raw packets rather than narrowing Utility, System, SysEx, Flex Data, Stream, or MIDI 2 messages into the plugin event model. Its checked `packets` view rejects a corrupted public count, `reset` restores it, and the scheduler validates it before consuming queued input. `UmpOutputDevice.sendBlock` converts valid block-relative offsets back to absolute nanosecond timestamps, continues after individual backend rejections, and reports sent, invalid, and rejected packets separately. The same stable-address, one-producer, one-consumer, and stopped-before-reset rules apply. Linux connects these contracts to ALSA UMP RawMIDI. Windows connects them to the optional Windows MIDI Services App SDK backend.

`DeviceCatalog(capacity)` is a control-thread discovery snapshot with bounded UTF-8 identifiers and display names. Refresh validates the entire replacement, rejects duplicate identifiers and defaults, and publishes a new generation only after success. Unified audio devices and directional audio input or output endpoints are distinct kinds, so platforms with independent capture and render defaults do not need synthetic device pairs. Selection resolves a requested stable identifier first, then the platform default, then the first device of that kind.

`DeviceSelection` persists unified audio, directional audio input and output, MIDI input, and MIDI output identifiers in a versioned bounded record and restores transactionally. Version 2 adds the directional audio fields; the decoder restores version-1 records with those fields empty. `DeviceSelectionTracker` retains requested identifiers independently from active fallbacks, reports each kind separately, and restores a preferred endpoint when it reappears.

The optional `zig-vst3-coreaudio` module supplies a macOS AUHAL backend without adding CoreAudio to ordinary plugin binaries. `Backend(f32)` and `Backend(f64)` enumerate audio devices with stable `coreaudio:<device-uid>` identifiers, report the current nominal sample rate and hardware buffer size, select a device, and adapt non-interleaved device buffers to `AudioDevice(Sample)`:

```zig
const core_audio = @import("zig-vst3-coreaudio");

var backend = core_audio.Backend(f32){};
var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const device_count = try backend.enumerate(&devices);
if (device_count == 0) return error.NoAudioDevice;

try backend.select(devices[0].identifier);
const info = try backend.runtimeInfo(devices[0].identifier);
if (info.buffer_frames > 1024) return error.AudioBufferTooLarge;

var device = backend.audioDevice();
try device.start(.{
    .sample_rate = 48_000.0,
    .max_block_size = 1024,
    .input_channel_count = 2,
    .output_channel_count = 2,
}, callback);
defer device.stop();
```

Keep the backend at a stable address while it is running. The source-compatible `start` path uses one selected AUHAL device. A configuration may use its first N channels, and combined duplex requires a device that exposes both directions, such as a physical interface or aggregate device. `selectInput` and `selectOutput` choose devices independently for `startSplit`. Split mode creates one input AUHAL unit and one output AUHAL unit, preserves their independent callback clocks, and publishes their planar buffers through `SplitAudioCallback`. Pair it with `BoundedCaptureRateCallbackAdapter` for sustained clock correction.

Both paths copy auxiliary bus boundaries and allocate AUHAL input scratch before processing begins. The realtime bridge performs no allocation or locking and clears every hardware output when pointer validation, frame-capacity validation, input rendering, or the callback fails. Legacy native failures increment a unified saturating device counter. Split input and output failures increment directional counters exposed through `directionalDeviceFailures()` and `failureSource()`. Processor callback rejection remains separate and does not request device recovery.

Call `startObservingTopology` to receive CoreAudio device-list and default-device notifications as atomic generation changes. The backend must remain at a stable address until `stopObservingTopology` returns. Refresh the catalog with `enumerate` on the control thread after its generation changes. `refreshTopology` also provides an explicit polling path. Enumeration rejects a notification or fingerprint mutation observed while it builds the snapshot. Hardware callback size must not exceed `max_block_size`; start fails transactionally when device capacity, buffer size, or AUHAL setup does not satisfy the configuration.

Injected tests cover discovery, unified and directional selection, runtime properties, topology notifications and snapshot races, combined and split f64 planar callbacks, capture-rate adapter composition, auxiliary buses, null and misaligned buffers, oversized blocks, insufficient channels, failed starts, directional callback and device failures, retained stop statistics, reset, retry, and non-macOS portability. The native test installs real CoreAudio property listeners and queries device records and runtime properties without starting hardware. Run this gate with `zig build test-coreaudio`. Physical full-duplex and dual-device processing, device hot-plug, failure-triggered restart, aggregate devices, and sample-rate conversion remain manual checks.

The optional `zig-vst3-wasapi` module supplies a Windows shared-mode backend. It enumerates active capture and render endpoints separately, hashes each opaque Windows endpoint ID into a stable directional identifier, tracks independent multimedia defaults, and publishes IMMNotificationClient changes through atomic topology generations. Select endpoints before starting, or leave either selection empty to use its current default:

```zig
const wasapi = @import("zig-vst3-wasapi");

var backend = wasapi.Backend(f32){};
defer backend.deinit();
try backend.startObservingTopology();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .audio_output and
        descriptor.is_default)
    {
        try backend.selectOutput(descriptor.identifier);
        break;
    }
}

var device = backend.audioDevice();
try device.start(.{
    .sample_rate = 48_000.0,
    .max_block_size = 1024,
    .input_channel_count = 0,
    .output_channel_count = 2,
}, callback);
defer device.stop();
```

The backend requests f32 or f64 interleaved shared-mode streams with Windows sample-rate and PCM conversion, then exposes planar buffers to the processor. An MMCSS Pro Audio worker owns COM, endpoint clients, event waits, interleaving, and teardown. The source-compatible `start` path keeps output-driven duplex timing and a fixed four-block capture ring for short-term clock differences. `startSplit` instead publishes each raw planar capture packet and each independent render event through `SplitAudioCallback`, which lets `BoundedCaptureRateCallbackAdapter` apply sustained clock correction without the native ring discarding timing information.

Start validates integral sample rates, block capacity, endpoint channel capacity, callback mode, and every COM stage before publishing a running session. Split mode additionally requires duplex endpoints. Callback failures release silent render buffers without stopping the worker. Device invalidation and wait failures stop processing and remain visible in retained statistics after teardown. Endpoint notification, discovery, combined and split callbacks, failure, retry, and persistence behavior is covered by injected tests. A Windows x86-64 ReleaseSafe executable fully links discovery, notifications, audio startup, statistics, and teardown against the production shim. Run `zig build test-wasapi`. Real Windows endpoint enumeration, exclusive device behavior, audible timing, drift, unplug, and recovery remain external tests.

The optional `zig-vst3-alsa` module supplies a Linux PCM backend without requiring ALSA development headers or adding libasound to ordinary plugin binaries. The module loads `libasound.so.2` at runtime, enumerates directional PCM hints, hashes raw PCM names into stable input and output identifiers, and treats the `default` PCM as preferred when it is present:

```zig
const alsa = @import("zig-vst3-alsa");

var backend = alsa.Backend(f32){};
defer backend.deinit();
if (!backend.available()) return error.AlsaUnavailable;

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .audio_output and
        descriptor.is_default)
    {
        try backend.selectOutput(descriptor.identifier);
        break;
    }
}

var device = backend.audioDevice();
try device.start(.{
    .sample_rate = 48_000.0,
    .max_block_size = 1024,
    .input_channel_count = 0,
    .output_channel_count = 2,
}, callback);
defer device.stop();
```

The worker requests interleaved native-endian float or double PCM and presents preallocated planar buffers to the processor. The source-compatible `start` path keeps one output-driven duplex worker. `startSplit` creates independent capture and playback workers, preserves each PCM's negotiated period, and publishes raw planar capture and render events through `SplitAudioCallback`. Pair it with `BoundedCaptureRateCallbackAdapter` for sustained independent-device clock correction. Capture shortages produce silent input and increment underflow statistics. ALSA stream recovery increments separate recovery, capture-overflow, and device-failure counters. Each worker attempts `SCHED_FIFO` priority but continues when the process lacks permission, and statistics report whether either request succeeded.

Call `pollTopology` on a control thread to compare the current directional hint fingerprint with the previous snapshot. ALSA PCM has no backend-wide device notification contract comparable to CoreAudio or WASAPI, so applications choose their polling interval. Start validates integral rates, channel capacity, callback mode, ALSA format negotiation, and every negotiated period before publishing the session. Split mode additionally requires capture and playback. Injected tests cover discovery, directional identities and defaults, polling, combined and split f64 planar callbacks, main and auxiliary bus reconstruction through the capture-rate adapter, hostile pointers and frame counts, statistics, transactional start, stop, and retry. Fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64. Run `zig build test-alsa`. Physical device enumeration, audible timing, realtime-priority policy, hot-plug polling, cross-device drift, unplug, and recovery remain external tests.

The optional `zig-vst3-pipewire` module connects standalone audio to a running PipeWire graph without development headers or a link-time PipeWire dependency. It loads `libpipewire-0.3.so.0` at runtime, enumerates bounded audio source and sink node snapshots, hashes node names into directional identifiers, and also exposes stable default input and output identifiers. Named selection sets the stream target. Empty selection follows the session manager default:

```zig
const pipewire = @import("zig-vst3-pipewire");

var backend = pipewire.Backend(f32){};
defer backend.deinit();
if (!backend.available()) return error.PipeWireUnavailable;

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .audio_output and
        descriptor.is_default)
    {
        try backend.selectOutput(descriptor.identifier);
        break;
    }
}

var device = backend.audioDevice();
try device.start(.{
    .sample_rate = 48_000.0,
    .max_block_size = 1024,
    .input_channel_count = 0,
    .output_channel_count = 2,
}, callback);
defer device.stop();
```

The native stream requests planar f32 or f64 buffers at the configured integral rate and channel count. Output-only and input-only callbacks use the negotiated graph quantum directly. Combined duplex processing uses a bounded single-producer, single-consumer capture FIFO and output-driven callbacks. Capture shortages supply silence, capture excess is dropped as whole packets, and both conditions remain visible in statistics. `startSplit` publishes independent capture and render callbacks without the FIFO so `BoundedCaptureRateCallbackAdapter` can own sustained rate correction.

Discovery snapshots are control-thread operations. `pollTopology` fingerprints node direction, name, and channel count. Enumeration rejects a graph change observed between its initial and final snapshots. Start resolves a named identifier against a fresh snapshot and fails transactionally if the node disappeared. Stream errors feed `failureSource`, callback rejection clears the entire output quantum, and stop drains the PipeWire loop before releasing callback state.

Injected tests cover default and named discovery, stable identifiers, topology changes, target resolution, combined and split callback reconstruction, malformed configuration, failed-start rollback, retained failures, planar format descriptors, FIFO wrap and pressure, deterministic silence, and malformed native buffer layouts. A separate ABI probe matched the listener, buffer, method-table, event-table, and SPA interface layouts against the current official headers. Fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64, and the installed-package consumer imports the public module. Run `zig build test-pipewire`. Physical daemon discovery, graph quantum behavior, named routing, audible duplex timing, hot-plug recovery, and session-manager policy remain external Linux checks.

The optional `zig-vst3-coremidi` module implements the MIDI device contracts on macOS without adding CoreMIDI to ordinary plugin binaries. Keep its `Backend` at a stable address from `open` through `close`. `enumerate` writes MIDI input and output descriptors with `coremidi:<unique-id>` identifiers into caller storage. It rejects a refresh if CoreMIDI reports a topology change while the snapshot is being built. Select endpoints before starting input or sending output:

```zig
const core_midi = @import("zig-vst3-coremidi");

var backend = core_midi.Backend{};
try backend.open("Example Audio");
defer backend.close();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const device_count = try backend.enumerate(&devices);
var input_identifier: ?plug.plugin.DeviceIdentifier = null;
for (devices[0..device_count]) |descriptor| {
    if (descriptor.kind == .midi_input) {
        input_identifier = descriptor.identifier;
        break;
    }
}

try backend.selectInput(
    input_identifier orelse return error.NoMidiInput,
);
var scheduler = plug.plugin.Midi1BlockScheduler(256){};
var input = backend.inputDevice();
try input.start(scheduler.inputCallback());
defer input.stop();
```

Input timestamps use Mach host time converted to nanoseconds. `nowNanoseconds` exposes the same clock for audio-block scheduling. Output timestamps convert back to host ticks with upward rounding, so a scheduled packet is not emitted before its requested nanosecond. The backend accepts MIDI 1 channel-voice messages. It skips complete System Common, System Real-Time, and SysEx traffic and counts unsupported and malformed input separately. Open, port creation, input connection, and output failures leave the backend reusable.

The native test opens a real CoreMIDI client and input and output ports without requiring attached hardware. Injected-system tests cover enumeration, topology races, endpoint selection, scheduling, parser rejection, output bytes, timestamp conversion, connection failure, send failure, disconnect failure, cleanup, and retry. Physical-device timing remains a manual test.

Run the focused native and portability gate with `zig build test-coremidi`.

The optional `zig-vst3-alsamidi` module implements the MIDI 1 device contracts through ALSA RawMIDI on Linux. It runtime-loads `libasound.so.2`, filters `rawmidi` hints by direction, hashes raw names into stable input and output identifiers, and uses the `default` hint when available. The backend must remain at a stable address from `open` through `close`:

```zig
const alsa_midi = @import("zig-vst3-alsamidi");

var backend = alsa_midi.Backend{};
try backend.open("My Standalone");
defer backend.close();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .midi_input and
        descriptor.is_default)
    {
        try backend.selectInput(descriptor.identifier);
        break;
    }
}

var scheduler = plug.plugin.Midi1BlockScheduler(256){};
var input = backend.inputDevice();
try input.start(scheduler.inputCallback());
defer input.stop();
```

The input worker polls a nonblocking RawMIDI handle and timestamps each read from `CLOCK_MONOTONIC`. Its retained parser accepts fragmented channel messages and running status across reads. System Common, System Realtime, and SysEx traffic is skipped and counted, while malformed stream state is contained without allocating. Read failures remain visible after stop.

RawMIDI output owns a 256-message native scheduling queue and worker. `send` accepts current, late, and future timestamps, inserts them in timestamp order while preserving submission order for equal timestamps, and returns without waiting for delivery. Enqueue uses a non-blocking mutex attempt, so contention or capacity exhaustion returns `error.AlsaMidiOutputQueueFull` instead of blocking the caller. Replacement and close cancel queued messages before closing the handle. `outputStatistics` reports queued, delivered, late, rejected, canceled, and write-failure counts. Output write failures feed the backend's `DeviceFailureSource`. Output selection opens the replacement before closing the current handle, so a busy or missing replacement preserves the working device.

Call `pollTopology` on a control thread to detect directional hint changes. Injected tests cover discovery, defaults, topology polling, fragmented and running-status input, system-message containment, future timestamp forwarding, queue rejection, transactional selection, retained input and output failures, stop, and retry. A shared native C queue test directly covers timestamp ordering, stable equal-time ordering, due-time removal, saturation, validation, and cancellation. Fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64. Run `zig build test-alsamidi`. Physical input timing, future-output timing accuracy, busy-device behavior, hot-plug polling, output delivery and cancellation, unplug handling, stop, reconnect, and teardown remain external tests.

The optional `zig-vst3-alsaump` module connects the complete UMP device contracts to Linux UMP RawMIDI endpoints. It runtime-loads the current ALSA UMP and control APIs. Older `libasound.so.2` installations remain usable by the other ALSA modules, but this backend reports unavailable when the UMP symbols are absent.

```zig
const alsa_ump = @import("zig-vst3-alsaump");

var backend = alsa_ump.Backend{};
try backend.open("My Standalone");
defer backend.close();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .midi_input) {
        try backend.selectInput(descriptor.identifier);
        break;
    }
}

var scheduler = plug.plugin.UmpBlockScheduler(256){};
var input = backend.inputDevice();
try input.start(scheduler.inputCallback());
defer input.stop();
```

Discovery walks ALSA cards, UMP endpoints, and active function blocks through the control API. It publishes directions supported by each endpoint and derives persisted identifiers from the card ID, endpoint device number, and product ID rather than the mutable card index. The first endpoint in each direction is the deterministic default when no saved selection matches. `pollTopology` detects endpoint or direction changes.

The input worker reads CPU-native 32-bit words from a nonblocking UMP handle and timestamps each read with `CLOCK_MONOTONIC`. The retained parser reconstructs 32-, 64-, 96-, and 128-bit packets across read boundaries. Malformed callback boundaries are counted without publishing partial packets. The output worker owns a 256-packet timestamp queue, preserves equal-time submission order and every packet width, and retains delivery, rejection, cancellation, lateness, and write-failure statistics. Replacement selection opens the new endpoint before closing the current output.

Injected tests cover directional discovery, stable identities, topology changes, fragmented packet reconstruction, all four packet widths, invalid callback containment, timestamped output, queue rejection, transactional selection, retained failures, stop, and retry. Fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64. Run `zig build test-alsaump`. Physical endpoint discovery, timestamp accuracy, hot-plug, protocol negotiation, scheduled output, unplug recovery, and teardown remain external tests.

The optional `zig-vst3-winmidi` module implements the MIDI 1 device contracts through WinMM on Windows. It enumerates input and output devices independently and hashes each driver-provided device-interface path into a stable directional identifier. Drivers that do not expose an interface path use a bounded capability-and-index fallback identifier, which is not guaranteed to remain stable after device reordering. WinMM does not expose mapper association for enumerated devices, so the backend does not claim a false default. The format-neutral catalog falls back deterministically when no persisted selection is available. The backend must remain at a stable address from `open` through `close`:

```zig
const win_midi = @import("zig-vst3-winmidi");

var backend = win_midi.Backend{};
try backend.open("My Standalone");
defer backend.close();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .midi_input) {
        try backend.selectInput(descriptor.identifier);
        break;
    }
}

var scheduler = plug.plugin.Midi1BlockScheduler(256){};
var input = backend.inputDevice();
try input.start(scheduler.inputCallback());
defer input.stop();
```

The input callback converts WinMM's relative millisecond timestamps to the backend's QueryPerformanceCounter-based monotonic nanosecond clock. It also tracks the 32-bit millisecond wrap for sessions longer than the timestamp range. Complete MIDI 1 channel messages are accepted. System messages, SysEx, and malformed input are contained and counted separately.

WinMM short-message output owns a 256-message native scheduling queue and worker. It accepts current, late, and future timestamps, preserves equal-time submission order, and delivers due packets with `midiOutShortMsg`. Enqueue uses `TryEnterCriticalSection`, so contention or saturation returns `error.WinMidiOutputQueueFull` without blocking. Device replacement and close wake and join the worker, cancel queued messages, reset the driver, and then close the handle. `outputStatistics` reports queued, delivered, late, rejected, canceled, and driver-error counts. Output driver errors feed the backend's `DeviceFailureSource`. Output selection opens the replacement before closing the active device. Call `pollTopology` on a control thread to compare the current directional fingerprint with the previous snapshot.

Injected tests cover discovery, directional identifiers, input adaptation, retained input and output statistics, future timestamp forwarding, queue rejection, transactional selection, topology polling, failure, stop, and retry. The shared native C queue test covers ordering, saturation, and cancellation. A fully linked ReleaseSafe executable compiles for Windows x86-64 GNU. Run `zig build test-winmidi`. Physical enumeration, input timing, future-output timing accuracy, output delivery and cancellation, busy-device behavior, hot-plug polling, unplug handling, stop, reconnect, and teardown remain external Windows tests.

## Windows UMP Device Backend

The optional `zig-vst3-winump` module connects the complete UMP device contracts to Windows MIDI Services. Its App SDK is an isolated build-time dependency. Builds that do not provide the SDK compile an unavailable stub, so ordinary plugin binaries and the WinMM backend do not acquire it.

From a Windows source checkout, download the pinned package, verify its SHA-256 digest, and generate its C++/WinRT projection:

```powershell
pwsh -File scripts/prepare_windows_midi_sdk.ps1
zig build test-winump
```

The preparation script locates the matching Windows SDK C++/WinRT and WinRT platform headers plus the installed MSVC C++ standard library. It records all three include paths inside the prepared SDK directory for later Zig builds. `-Dwindows-cppwinrt-include-path`, `-Dwindows-sdk-winrt-include-path`, and `-Dwindows-msvc-include-path` override those recorded paths when a build uses a separate toolchain.

To keep the SDK outside the checkout, pass the same directory to both commands:

```powershell
pwsh -File scripts/prepare_windows_midi_sdk.ps1 `
    -SdkDirectory C:\SDKs\zig-vst3-midi
zig build test-winump `
    -Dwindows-midi-sdk-path=C:\SDKs\zig-vst3-midi
```

The backend must remain at a stable address from `open` through `close`. Open and close it on the same control thread because that thread owns the Windows Runtime apartment:

```zig
const win_ump = @import("zig-vst3-winump");

var backend = win_ump.Backend{};
try backend.open("My Standalone");
defer backend.close();

var devices: [64]plug.plugin.DeviceDescriptor = undefined;
const count = try backend.enumerate(&devices);
for (devices[0..count]) |descriptor| {
    if (descriptor.kind == .midi_input) {
        try backend.selectInput(descriptor.identifier);
        break;
    }
}

var scheduler = plug.plugin.UmpBlockScheduler(256){};
var input = backend.inputDevice();
try input.start(scheduler.inputCallback());
defer input.stop();
```

Discovery uses endpoint device IDs as persisted identities and active function blocks to determine direction. Function-block directions are interpreted from the device's point of view. A block output is therefore an application input, while a block input is an application output. Endpoints without active declarations remain available in both directions.

Input callbacks convert QueryPerformanceCounter timestamps to monotonic nanoseconds and pass complete UMP words into the retained packet assembler. Output accepts exactly one complete 32-, 64-, 96-, or 128-bit packet and converts its absolute nanosecond timestamp back to QueryPerformanceCounter ticks. `outputStatistics` reports admission attempts, service-accepted packets, late submissions, rejections, queue-full responses, and write failures. A delivered count means that the service accepted the packet, not that a physical endpoint confirmed transmission.

Injected tests cover SDK acquisition and release, refreshed topology, directional identifiers, fragmented 128-bit packet reconstruction, complete-packet output, and unavailable builds. Run `zig build test-winump`. Native service startup, physical endpoint discovery, all packet widths, input and output timestamp accuracy, hot-plug, unplug recovery, and teardown remain external Windows tests.

`DeviceRecoveryController` turns catalog reconciliation into a transactional control-thread recovery operation. Its callback stops affected devices, applies the candidate selection, and restarts them. The controller publishes the candidate only after the callback succeeds. Failed fallback or restart attempts retain the active selection and retry on the next call. A returning preferred device replaces its fallback, and `requestRecovery` supports a backend-reported failure when the identifier did not change. Build replacement catalogs and run recovery away from the audio thread.

`DeviceFailureSource` exposes monotonic failure counters for unified audio, directional audio, and directional MIDI devices. `DeviceFailureMonitorSet(capacity)` establishes a baseline when each source is added, combines new increases across sources, ignores counter resets after restart, and commits no baselines if any source read fails. CoreAudio maps combined-session failures to unified audio and split-session failures to their input or output AUHAL unit. WASAPI and ALSA PCM map native device-failure counts to the configured audio directions. CoreMIDI, WinMM, and ALSA RawMIDI map retained input disconnect, driver, or read failures. Keep every backend at a stable address while its source is registered:

```zig
try shell.addDeviceFailureSource(audio_backend.failureSource());
try shell.addDeviceFailureSource(midi_backend.failureSource());
```

`StandaloneWindowBackend` is the platform boundary for a top-level application window. It creates the native parent used by `gui.Editor`, controls visibility and native resize negotiation, supplies bounded window events, and destroys its platform state after editor detachment. `StandaloneWindow` validates size and scale, rolls back a failed editor attachment by closing the native window, propagates resize, scale, and focus events on the control thread, retains quit requests, and tears down each resource once.

`StandaloneShell(catalog_capacity)` combines the window with `DeviceRecoveryController` and as many as eight failure sources. `pumpControlCycle` processes at most the caller's event budget, polls all registered failure sources transactionally, requests a same-selection restart when a counter increases, and then reconciles device recovery. `StandaloneControlCycleReport.device_failures` identifies the affected device domains. A close request suppresses failure polling and recovery so the application can stop audio before destroying the editor and native window.

The optional `zig-vst3-winwindow` module implements `StandaloneWindowBackend` with a Win32 top-level window. Initialize the backend, keep it at a stable address through shell teardown, and pass `windowBackend()` to `StandaloneShell`:

```zig
const win_window = @import("zig-vst3-winwindow");

var backend = try win_window.Backend.init("My Standalone");
var shell = try plug.plugin.StandaloneShell(64).init(
    editor,
    backend.windowBackend(),
    restored_selection,
);
defer shell.deinit();

try shell.window.open();
try shell.window.show();
```

The Win32 shim converts the bounded UTF-8 title to UTF-16, creates a hidden overlapped window, exposes its `HWND` as the editor parent, negotiates client-area resize, and coalesces native resize, DPI-scale, focus, and close state. Its message poll dispatches at most 32 native messages per call. `WM_CLOSE` becomes a retained quit request rather than destroying the parent under the editor. Create, pump, resize, show, hide, and teardown calls must remain on the window thread.

Injected tests cover initialization, lifecycle, visibility, resize, event adaptation, retry, and unsupported platforms. A fully linked ReleaseSafe executable compiles against User32 for Windows x86-64 GNU. Run `zig build test-winwindow`. Real DPI transitions, keyboard and pointer delivery to the child editor, minimize and restore, close ordering, accessibility, appearance, and repeated reopen remain external Windows tests.

The optional `zig-vst3-cocoawindow` module implements the same boundary with an AppKit top-level window:

```zig
const cocoa_window = @import("zig-vst3-cocoawindow");

var backend = try cocoa_window.Backend.init("My Standalone");
var shell = try plug.plugin.StandaloneShell(64).init(
    editor,
    backend.windowBackend(),
    restored_selection,
);
defer shell.deinit();

try shell.window.open();
try shell.window.show();
```

The Cocoa shim creates a hidden resizable `NSWindow`, exposes its content `NSView` as the editor parent, controls content-area resize, and coalesces resize, backing-scale, focus, and close state. Each poll dispatches at most 32 AppKit events. A native close request remains pending until the shell stops audio and tears down the editor and window. Create, pump, resize, show, hide, and teardown calls must remain on the main thread.

Injected tests cover initialization, lifecycle, visibility, resize, event adaptation, retry, and unsupported platforms. A fully linked ReleaseSafe executable compiles against AppKit and Foundation on macOS, while portability tests compile for Linux and Windows. Run `zig build test-cocoawindow`. Real display-scale transitions, keyboard and pointer delivery to the child editor, minimize and restore, close ordering, VoiceOver, appearance, and repeated reopen remain external macOS tests.

The optional `zig-vst3-x11window` module implements the top-level boundary on Linux. It loads Xlib at runtime, creates a hidden resizable child-parent window, installs `WM_DELETE_WINDOW`, and adapts bounded configure, focus, and close events. It does not add X11 linkage to ordinary plugin binaries:

```zig
const x11_window = @import("zig-vst3-x11window");

var backend = try x11_window.Backend.init("My Standalone");
var shell = try plug.plugin.StandaloneShell(64).init(
    editor,
    backend.windowBackend(),
    restored_selection,
);
defer shell.deinit();

try shell.window.open();
try shell.window.show();
```

Injected tests cover title validation, lifecycle, visibility, resize, event adaptation, failed-open retry, and unsupported platforms. Fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64, and the unsupported path compiles for Windows. Run `zig build test-x11window`. Native display connection, window-manager behavior, child-editor input, X11 DPI policy, accessibility, repeated reopen, and teardown remain external Linux checks.

The optional `zig-vst3-waylandwindow` module implements the toolkit-neutral top-level boundary through core Wayland and stable xdg-shell:

```zig
const wayland_window = @import("zig-vst3-waylandwindow");

var backend = try wayland_window.Backend.init("My Standalone");
var shell = try plug.plugin.StandaloneShell(64).init(
    editor,
    backend.windowBackend(),
    restored_selection,
);
defer shell.deinit();

try shell.window.open();
try shell.window.show();
```

The backend resolves libwayland-client and its core protocol interfaces at runtime. It carries the stable xdg-shell metadata used for the top-level role, so consumers do not need Wayland development headers or hard linkage. Opening discovers the compositor, shared-memory, seat, and output globals, creates the `wl_surface`, `xdg_surface`, and `xdg_toplevel`, acknowledges the initial configure, and prepares a one-pixel shared-memory background that maps the parent surface tree without scaling allocations with the editor size. Hiding commits a null buffer, while showing reattaches that background.

Compositor configure, output-scale, keyboard-focus, and close callbacks coalesce into the common standalone event contract. `poll_event` performs a nonblocking display read and returns at most one retained event. Client-driven resize accepts the constrained logical size; the attached editor child publishes the corresponding surface extent, while later compositor configure events remain authoritative. Keep all calls on one Wayland thread and keep the backend at a stable address until editor detachment.

`display()`, `parentSurface()`, `xdgSurface()`, `xdgToplevel()`, and `currentSize()` expose the checked state used by the standalone VST3 bridge. Toolkit-neutral editors can use the `NativeParent` surface directly.

`vst_wayland_standalone_frame.StandaloneBridge` combines the backend, `IPlugFrame`, `IWaylandFrame`, `IWaylandHost`, and the standalone Steinberg run loop:

```zig
const vst3 = @import("zig-vst3");
const Bridge = vst3.vst_wayland_standalone_frame.StandaloneBridge(
    wayland_window.Backend,
);

var run_loop = vst3.vst_linux_run_loop.initStandaloneDriver(
    64,
    64,
    io,
);
defer run_loop.deinit();

var bridge = Bridge.init(&backend, run_loop.asInterface());
```

Provide `bridge.asWaylandHost()` when the controller requests the Wayland host object, and pass `bridge.asPlugFrame()` to the plugin view before attaching the view to the parent surface. The bridge exposes the frame and host interfaces through one COM identity, delegates `IRunLoop` queries to the retained driver, validates every requested native object against the active display, and routes child resize requests through the backend.

Detach the plugin view and release all queried interfaces and display borrows before closing the backend. Call `try bridge.validateDetached()` at that boundary. It rejects a retained frame interface or an unmatched `IWaylandHost.openWaylandConnection` borrow, which makes invalid teardown ordering observable before native objects are destroyed.

Injected backend tests cover title validation, lifecycle, visibility, resize, event adaptation, native-handle exposure, failed-open retry, and unsupported platforms. Strict-C11 shims and fully linked ReleaseSafe executables compile for Linux x86-64 and AArch64, while the unsupported path compiles for Windows. The bridge tests cover COM identity, interface queries, delegated run-loop retention, native-object validation, connection borrows, resize acceptance and rejection, and detached-state validation. The installed-package consumer composes the public backend, run loop, and bridge. Run `zig build test-waylandwindow` and `zig build test-wayland-standalone-frame`. Real compositor discovery, xdg-shell behavior, VSTGUI child attachment, parent mapping, resize, multi-output scale, focus, input delivery, close ordering, accessibility, repeated reopen, and teardown remain external Linux checks.

`vst_linux_run_loop.initStandaloneDriver` supplies the Steinberg `IRunLoop` needed by VSTGUI's X11 child adapter. The driver retains registered event and timer handlers, polls registered file descriptors without allocating, derives a bounded wait from the next timer deadline, coalesces missed periodic intervals, and releases every retained handler during teardown. Keep the driver at a stable address, provide `driver.asInterface()` as the Linux host run-loop context, and call `driver.pump(maximum_wait_milliseconds)` from the window thread alongside the standalone shell's control cycle. Stop new registrations before calling `driver.deinit()`.

Injected tests cover duplicate registration, capacity, malformed retained entries, ready descriptors, timer deadlines, missed intervals, clock regression, callback removal, and exact reference releases. The focused gate also compiles ReleaseSafe Linux x86-64, Linux AArch64, and unsupported Windows paths. Run `zig build test-linux-run-loop`. Physical VSTGUI registration, X11 input delivery, timer cadence under load, close ordering, and teardown remain external Linux checks.

Physical PipeWire routing and recovery, Linux and Windows UMP timing and recovery, disparate-device clock-correction confirmation, Linux VSTGUI confirmation, and restart or fallback confirmation remain open.

A high-level or low-level processor that changes host-visible state may declare `bindHostRequests`. The framework supplies a component-owned, format-neutral `HostRequestSink`. Call `markChanged` with `HostChange`, or `markChanges` for a group, then call `dispatchPending` outside processing. `HostChange` covers component reload, audio I/O, parameter values, latency, parameter titles, MIDI CC assignments, note expression, I/O titles, prefetchable support, routing information, keyswitches, and parameter ID mapping. `markLatencyChanged` and `markIoChanged` remain convenience methods. Topology mutations mark audio I/O automatically. Pending changes coalesce into one component-to-controller message and one host `restartComponent` call. A missing peer or failed host call restores the complete set for retry without losing changes marked concurrently. Adopt prepared processing changes only at a block boundary. See [DSP Utilities](dsp.md#dynamic-latency) for the latency ordering contract and Fixed Rate Processor example.

A high-level or low-level processor that owns state beyond parameters may declare a bounded component-state payload:

```zig
pub const component_state_maximum_encoded_size = 4096;
pub fn writeComponentState(self: *const Plugin, writer: anytype) !void
pub fn readComponentState(self: *Plugin, reader: anytype) !void
```

The VST3 shell stores the payload beside parameter state in a versioned envelope. Decoders must reject malformed or trailing data without partially changing the processor. The optional `afterComponentStateRestore` hook runs after a successful restore. The optional `componentConnectionReady` hook runs after the component and controller connection is available, which lets a restored processor dispatch deferred host notifications. Keep payloads bounded and do not serialize unbounded audio or model data. See [Resource Lifecycles](resources.md#persistent-references) for external-file persistence and recovery.

`PrepareConfig` rejects non-finite or non-positive sample rates and zero maximum block sizes before `prepare` runs. It also exposes the host's requested `process_mode` as `.realtime`, `.prefetch`, or `.offline`. Directly constructed configurations default to `.realtime`. The VST3 shell applies the same validation and mode mapping when hosts set up processing.

During VST3 processing, the shell uses the host process context sample rate when it is valid. If the host omits the process context, it uses the validated sample rate from `setupProcessing`.

## Process Context

`process.ProcessContext(Sample)` carries typed audio buffers, parameter points and ramps, input events, optional output-event storage, the current process mode, checked host transport, and sample-rate timing helpers. `parameterNormalizedAtOrBeforeOr` resolves point and ramp ordering and returns the interpolated value at a sample offset. `parameterRamps`, `parameterRampCount`, and `hasParameterRamps` expose the bounded ramp view directly. Use `processMode`, `isRealtime`, `isPrefetch`, or `isOffline` when processing policy depends on the host's current mode. `transport()` returns tempo, musical position, bar position, cycle range, time signature, and play or record state only when the corresponding host values are valid.

Set `pub const follow_host_transport = true` on a VST3 effect configuration that consumes these fields. The wrapper then requests the required tempo, musical-position, time-signature, cycle, and transport-state fields through `IProcessContextRequirements`.

Block-rate state-aware hooks receive a fixed stack snapshot of the parameter state at the start of the block. The snapshot includes the previously persisted values and the latest valid point or interpolated ramp value at sample offset zero. Later automation is persisted for the next block but is not exposed early through `processWithParameterView`, `processWithParameters`, or the reflected VST3 processor parameter-state argument. Raw process hooks retain the complete point and ramp views in `ProcessContext` for sample-accurate handling.

The reflected VST3 shell also handles the SDK parameter-flush form where `numSamples` and the audio bus counts are zero. Valid offset-zero changes update persistent component state without invoking DSP or requiring audio buffers. A later audio block observes the flushed values.

Use `ProcessContext(Sample).initWithOptions` in tests and host adapters when constructing contexts directly. The named fields keep input channels, output channels, and optional attachments clear at the call site:

```zig
var context = try plug.process.ProcessContext(f32).initWithOptions(.{
    .sample_rate = 48_000.0,
    .process_mode = .offline,
    .input_channels = &input_channels,
    .sidechain_input_channels = &sidechain_input_channels,
    .output_channels = &output_channels,
    .auxiliary_output_channels = &auxiliary_output_channels,
    .attachments = .{
        .parameter_changes = &parameter_changes,
        .parameter_ramps = &parameter_ramps,
        .events = &events,
        .output_events = &output_events,
    },
});
```

For sample-accurate automation, split the block at automation points:

```zig
pub fn process(_: *Gain, context: *plug.process.ProcessContext(f32)) void {
    var segments = context.parameterBlockSegments();
    while (segments.next()) |segment| {
        const gain: f32 = @floatCast(
            context.parameterNormalizedAtOrBeforeOr(0, segment.start_offset, 1.0),
        );
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (segment.start_offset..segment.end_offset) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
}
```

Structural parameters such as quality modes, oversampling factors, and processing topologies often cannot change within a block. `process.BlockParameterLatch` gives them a deterministic boundary contract:

```zig
const persisted = params.loadNormalized("quality");
const quality = quality_latch.beginBlock(context.parameterChanges(), persisted);
```

Initialize the latch with the parameter ID and its initial normalized value. At each process call, `beginBlock` returns the most recent change at sample offset zero when one exists. A later change in the block is saved for the next block instead of taking effect early. When the host supplies no change for that parameter, the latch synchronizes from the persisted value so state restoration and controller updates remain visible. The latch is fixed-size and performs no allocation or locking.

For a parameter that remains sample-accurate inside the block, call `beginBlock` once and use `valueAt` at each process segment. `valueAt` combines the pre-block value with automation points at or before the requested sample offset. This avoids both reverting to a declaration default on quiet blocks and applying the final queue value before its offset.

Useful context helpers include:

- `sampleRate`, `sampleDurationSeconds`, `blockDurationSeconds`, and `sampleOffsetSeconds`.
- `inputChannel`, `outputChannel`, `inputSample`, `outputSample`, and `setOutputSample`.
- `sidechainInputChannel`, `sidechainInputSample`, `sidechainInputChannelCount`, and `hasSidechainInputChannels`.
- `auxiliaryOutputChannel`, `auxiliaryOutputSample`, `setAuxiliaryOutputSample`, and `auxiliaryOutputChannelCount`.
- `fillOutputs` and `clearOutputs`.
- `parameterBlockSegments`, `eventBlockSegments`, `inputEventBlockSegments`, and `processBlockSegments`.

`frameCount` uses the shared input/output frame count for effects, the output frame count for generators, and the input frame count for analyzers.

## Events

Events are value types. Processors can inspect typed payloads, route by offset, bus, channel, or kind, and append validated output events when an output writer is attached.

```zig
pub const EventEcho = struct {
    pub const name = "Event Echo";
    pub const vendor = "Example Audio";
    pub const event_output = true;
    pub const Params = struct {};

    pub fn process(_: *EventEcho, context: *plug.process.ProcessContext(f32)) void {
        _ = context.appendOutputEventsIfPossible(context.inputEvents());
    }
};
```

Constructors include `Event.noteOn`, `Event.noteOff`, `Event.midiCc`, `Event.pitchBend`, `Event.aftertouch`, `Event.noteExpressionValue`, `Event.dataEvent`, and `Event.other`. `Event.asNoteOn`, `asNoteOff`, `asMidiCC`, and related helpers expose typed views without switching on the whole event struct.

The VST3 bridge validates event offsets, channels, pitches, normalized values, and bounded data-event payloads before exposing events to plugin code. The accepted MIDI and event-value bounds are exported from `plug.process` as `midi_channel_min`, `midi_channel_max`, `midi_pitch_min`, `midi_pitch_max`, `midi_control_number_min`, `midi_control_number_max`, `event_value_min`, `event_value_max`, `bipolar_event_value_min`, and `bipolar_event_value_max`. Use `midiPitchIndex` and `midiPitchCount` when mapping validated MIDI pitches into fixed-size note state arrays.

MIDI protocol modules are grouped under `plug.process.midi`. The namespace separates MIDI 1 and MIDI 2 channel protocols, UMP packets, SysEx, Flex Data, endpoint discovery, MIDI-CI process, profile, and property layers, Standard MIDI Files, and MPE state. Existing flat module and type names remain available for source compatibility.

```zig
const packet = try plug.process.midi.ump.Packet.init(words);
const Device = plug.process.midi.ci.device.Device;
const PropertySession = plug.process.midi.ci.property.session.Initiator;
```

### MIDI 1 Channel Messages

`process.Midi1Message` parses and generates complete MIDI 1 channel voice messages:

```zig
const message = try plug.process.Midi1Message.parse(&.{ 0x92, 64, 127 });
const event = message.toEvent(12, 0) orelse return error.UnsupportedProcessEvent;
```

Constructors cover note on, note off, polyphonic key pressure, control change, program change, channel pressure, and 14-bit pitch bend. `normalized7`, `normalizedPitchBend`, `dataByteFromNormalized`, and `pitchBendFromNormalized` provide checked value conversion through `plug.process.midi1`.

Note on with zero velocity converts to a typed note-off event. Note messages, polyphonic key pressure, control changes, and pitch bend convert in both directions between `Midi1Message` and the framework event model through `toEvent` and `fromEvent`. Program change and channel pressure remain valid MIDI messages but return `null` from `toEvent` because the current typed process-event model has no equivalent. `Midi1Message.parse` intentionally accepts one complete channel message at a time.

`process.Midi1StreamDecoder` accepts one byte at a time and emits complete channel messages. It supports running status, preserves partial channel messages across interleaved realtime bytes, and replaces an incomplete message when a new channel status arrives. Unsupported system-common and SysEx status bytes reset the decoder and return an error. Higher-level MPE state is provided separately. UMP and MIDI-CI remain outside this utility.

### Standard MIDI Files

`process.MidiFile` validates a complete Standard MIDI File from caller-owned bytes. It supports formats 0, 1, and 2, metric and SMPTE time divisions, running status, channel messages, meta events, and `F0` or `F7` SysEx events. Tracks must end with an end-of-track event, and malformed lengths, truncated events, invalid data bytes, zero tempos, and trailing data are rejected.

```zig
const file = try plug.process.MidiFile.parse(bytes);
var events = file.track(0) orelse return error.MissingMidiTrack;
var iterator = events.iterator();
while (try iterator.next()) |event| {
    _ = event.absolute_ticks;
}
const seconds = try file.secondsAtTick(0, 960);
```

`secondsAtTick` follows tempo changes for metric files and converts fixed-rate SMPTE ticks directly. In format 1 it reads tempo from conductor track 0. In format 2 it reads tempo from the selected independent track.

`process.MidiFileWriter` writes into a caller-provided buffer and backpatches track lengths when `endTrack` is called:

```zig
var storage: [1024]u8 = undefined;
var writer = try plug.process.MidiFileWriter.init(
    &storage,
    .single_track,
    1,
    .{ .ticks_per_quarter_note = 480 },
);
try writer.beginTrack();
try writer.writeMessage(0, try plug.process.Midi1Message.noteOn(0, 60, 100));
try writer.endTrack(480);
const bytes = try writer.finish();
```

The parser and writer borrow caller storage and do not allocate. Keep source bytes alive while using a parsed file or its event slices.

### MPE Zone Layouts

`process.MpeZone` and `process.MpeZoneLayout` describe lower and upper MPE zones with zero-based MIDI channel indexes. Zones validate their member-channel count and 0–96 semitone pitch-bend ranges. Layouts reject overlapping active zones and update transactionally.

```zig
var layout = try plug.process.MpeZoneLayout.init(
    try plug.process.MpeZone.init(.lower, 8, 48, 2),
    try plug.process.MpeZone.init(.upper, 6, 48, 2),
);
const zone = layout.memberZone(9) orelse return error.ChannelOutsideMpeZone;
```

`memberZone` and `masterZone` classify channels without allocation. A single active zone may use all 15 remaining channels. Two active zones may use at most 14 member channels between them because channels 0 and 15 remain their masters.

`process.MidiRpnDecoder` keeps independent selection and Data Entry state for all 16 channels. It emits coarse events on CC 6 and full 14-bit events after CC 38. RPN null selection, NRPN selection, and Reset All Controllers clear stale RPN state. `midiRpnCoarseMessages`, `midiRpnFineMessages`, and `midiRpnNullSelectionMessages` generate fixed-size message arrays.

`process.MpeZoneSynchronizer` consumes channel messages and updates a checked layout from MPE Configuration RPN 6 and Pitch Bend Sensitivity RPN 0:

```zig
var synchronizer = try plug.process.MpeZoneSynchronizer.init(layout);
const messages = try plug.process.mpeConfigurationMessages(.upper, 10);
for (messages) |message| {
    _ = try synchronizer.push(message);
}
layout = synchronizer.layout;
```

MPE Configuration messages are accepted only on manager channels 0 and 15. The latest configuration takes precedence, shrinking or disabling the other zone when channels would overlap. `mpePitchBendRangeMessages` generates RPN 0 messages for manager or member channels.

`process.MpeInstrument(capacity)` is a fixed-capacity expressive note model. It accepts checked MIDI 1 channel messages, tracks stable note IDs and key state, combines manager and member pitch bend using each zone's configured ranges, and applies pressure and CC 74 timbre. Member-channel expression can target the last, lowest, highest, or all key-down notes on a channel. Manager-channel expression broadcasts to the corresponding zone. Sustain on manager-channel CC 64 retains released notes until pedal-up.

```zig
const Instrument = plug.process.MpeInstrument(32);
var instrument = try Instrument.init(layout);

_ = try instrument.process(try plug.process.Midi1Message.noteOn(1, 60, 100));
_ = try instrument.process(try plug.process.Midi1Message.pitchBend(1, 12_288));

for (instrument.notes()) |note| {
    renderVoice(note.id, note.total_pitch_bend_semitones, note.pressure, note.timbre);
}
```

The instrument never allocates. Capacity overflow returns `error.MpeNoteCapacityExceeded` without changing existing notes. `setLayout` and `reset` validate the replacement layout and clear active notes. `valid` and fail-closed accessors contain malformed retained state.

`process.MpeMemberChannelAllocator` assigns one outgoing note to each member channel. Free channels are selected in ascending order. A full zone either returns `error.NoFreeMpeMemberChannel` or replaces the oldest assignment, according to `MpeStealPolicy`. A stealing result includes the displaced assignment so the sender can emit its note-off before reusing the channel.

```zig
var allocator = try plug.process.MpeMemberChannelAllocator.init(layout.lower);
const result = try allocator.allocate(60, .oldest);
if (result.stolen) |stolen| {
    send(try plug.process.Midi1Message.noteOff(stolen.channel_index, stolen.note, 0));
}
send(try plug.process.Midi1Message.noteOn(result.assignment.channel_index, 60, 100));
```

The allocator is intentionally a one-note-per-member-channel sender policy. The receiver-side instrument also handles MIDI Mode 3 streams where several notes share a channel.

### Universal MIDI Packets

`process.UmpPacket` owns one checked 32, 64, 96, or 128-bit Universal MIDI Packet in fixed storage. Its expected word count comes from the first word's Message Type nibble. `process.UmpIterator` walks a caller-owned word slice and rejects a truncated final packet without advancing past it.

```zig
const source = try plug.process.Midi1Message.noteOn(3, 60, 100);
const packet = try plug.process.umpFromMidi1(7, source);
const decoded = try plug.process.umpToMidi1(packet);
```

MIDI 1 channel-voice translation preserves the group, status, channel, and data bytes. It covers note on and off, polyphonic pressure, control change, program change, channel pressure, and pitch bend. Program change and channel pressure packets require their unused final byte to be zero. The UMP storage and iterator do not allocate.

The standalone UMP device and block-scheduling contracts described above retain this complete packet representation through device callbacks and into sample-offset block buffers. They do not allocate or reinterpret packet payloads.

The `umpScale*` helpers implement the MIDI 2 widening and narrowing rules between 7 or 14-bit MIDI 1 values and 8, 16, or 32-bit values. Widening distributes the available source resolution across the destination range instead of only shifting bits. Narrowing every widened input recovers the original value exactly.

`process.Midi2ChannelMessage` provides typed payloads for registered and assignable controllers, per-note controllers and pitch bend, note on and off with attributes, pressure, control change, program and bank changes, pitch bend, and per-note management. Parsing rejects the reserved status, invalid 7-bit fields, and nonzero reserved fields. Unknown note-attribute values remain available to callers as extensions.

`process.MidiSystemMessage` covers MIDI Time Code quarter frame, Song Position Pointer, Song Select, Tune Request, Timing Clock, Start, Continue, Stop, Active Sensing, and Reset as checked Message Type 1 packets.

`process.MidiUtilityMessage` covers groupless NOOP, JR Clock, JR Timestamp, Delta Clockstamp Ticks Per Quarter Note, and Delta Clockstamp packets. Reserved addressing and data bits are rejected. Delta clock tick resolution must be nonzero.

`process.Sysex7Packetizer` and `process.Sysex8Packetizer` borrow caller-owned messages and emit complete, begin, continuation, and end packets. Their fixed-capacity reassemblers validate packet order, capacity, group continuity, and, for SysEx8, stream identity before changing retained data. SysEx7 accepts only 7-bit data. SysEx8 preserves all byte values.

`process.MidiStreamMessage` provides checked endpoint discovery and information, device identity, stream configuration, function block discovery and information, and MIDI Clip start and end marker packets. Function block counts are limited to 32, discovery can target one declared block or all blocks, and group ranges must fit the 16 UMP groups. Clip sequencing and the required preceding Delta Clockstamp belong to the caller's MIDI Clip writer. `process.MidiStreamTextPacketizer` emits UTF-8 endpoint and function-block names plus printable-ASCII product instance IDs. Its fixed-capacity reassembler rejects sequence, notification-kind, function-block, padding, encoding, and capacity mismatches without partial mutation.

`process.MidiEndpointRequester` tracks requester-side discovery, configuration negotiation, and function-block replies without allocation. Independent endpoint-discovery replies can arrive in any order. Configuration changes remain pending until a notification arrives. The session rejects undeclared blocks, unsupported protocols or JR timestamp modes, changed function-block counts, and changes to discovered static blocks without mutating retained state. Endpoint and function-block filters expose named fields instead of raw bit positions.

`process.MidiEndpointResponder` validates a borrowed endpoint descriptor and answers requester packets through a lazy `MidiEndpointReplies` iterator. Endpoint descriptors include identity, names, the initial configuration, and up to 32 function blocks. The responder accepts supported configuration requests and returns its retained configuration when a request is unsupported. All-block discovery with maximum-length names remains allocation-free and does not build an intermediate packet queue. Keep borrowed descriptor strings and function-block storage unchanged while the responder or its reply iterators use them.

`process.MidiCiDiscoveryMessage` encodes and parses mandatory MIDI-CI Discovery and Reply to Discovery messages without allocation. Versions 1 and 2, 28-bit MUID restrictions, device identity, category flags, minimum receivable SysEx size, output-path correlation, and function-block association are checked before publication. `process.MidiCiDiscoveryTransaction` and `process.MidiCiDiscoveryResponder` provide the two sides of a discovery exchange. `process.MidiCiInvalidation` handles the mandatory broadcast Invalidate MUID message and identifies whether a local or cached MUID is its target. Encoded bytes omit `F0` and `F7` as required for UMP carriage and can be passed directly to `process.Sysex7Packetizer`.

`process.MidiCiEndpointInformationTransaction` and `process.MidiCiEndpointInformationResponder` exchange the printable 16-byte Product Instance ID introduced by MIDI-CI version 2. `process.MidiCiAcknowledgement` covers ACK and NAK wire forms, channel, group, and function-block addressing, version 1 NAK compatibility, bounded message text, and timeout-wait status data.

`process.MidiCiProcessInquiryTransaction` negotiates support for MIDI Message Reports. `process.MidiCiMessageReportTransaction` then validates the report request, the responder's supported subset, and the correlated Begin and End markers. The caller emits or consumes the declared MIDI messages between those markers because the current values and transport belong to the plugin or device. System-message requests require function-block addressing. Channel and note requests may target a channel, group, or function block.

`process.MidiCiProfileInquiryTransaction` discovers bounded enabled and disabled Profile lists and enforces the required channel, group, then function-block reply order. `process.MidiCiProfileSetTransaction` correlates Set Profile On or Off messages with Enabled or Disabled reports. Added and Removed reports, Profile Details inquiries, registered channel-count details, and bounded Profile Specific Data cover the optional generic Profile Configuration messages. Profile-defined targets and payload semantics remain the caller's responsibility.

`process.MidiCiProfileHost` owns a bounded local profile registry. It produces Added and Removed presence reports, answers address-scoped inquiries, publishes local enablement changes, and dispatches incoming enablement, details, and profile-specific-data requests through a typed delegate. Delegate rejection leaves enablement state unchanged. `process.MidiCiDevice.profileHost` borrows the same policy surface while keeping local profile state in the unified device.

`process.MidiCiPropertyCapabilitiesTransaction` and `process.MidiCiPropertyCapabilitiesResponder` negotiate the supported number of simultaneous Property Exchange requests. They cover MIDI-CI message formats 1 and 2, Property Exchange version fields, responder version downgrade, MUID correlation, and the required whole-function-block address. `process.MidiCiPropertyDataMessage` provides bounded wire envelopes for Get, Set, Subscription, their replies, and Notify. It validates request IDs, chunk fields, first-chunk header placement, fixed header-only forms, 7-bit payload bytes, and exact lengths. `process.MidiCiPropertyReassembler` joins known-length and initially unknown-length chunk sequences, reports aborted transfers, rejects identity and ordering changes, and preserves retained data when a chunk is rejected. `process.MidiCiPropertyRequestIds` allocates a negotiated fixed number of concurrent request IDs without heap allocation.

`process.MidiCiPropertyInitiator` owns a fixed request-ID pool, sequences outgoing chunks, correlates responses by version and both MUIDs, retains completed data until release, and handles timeout-wait, terminate, and timeout notifications. `process.MidiCiPropertyResponder` bounds simultaneous remote requests, reassembles each request by remote MUID and request ID, and sequences its reply. `process.MidiCiPropertySubscriptionRegistry` owns bounded resource and subscription identifiers, correlates partial, full, notify, and end commands, and can release every subscription for a disconnected remote.

`process.MidiCiPropertyHost` combines the bounded responder and subscription registry with a typed application delegate. It parses completed Get, Set, and Subscription headers, dispatches policy only after complete reassembly, builds checked reply headers, and changes subscription ownership only after a valid response is available. `process.MidiCiDevice.propertyHost` borrows the device's responder and subscription state. The device can also begin a negotiated remote Get, accept chunks and Notify state, and cache successful non-paginated replies by remote, resource, and optional resource ID.

`process.MidiCiPropertyRemoteCache` writes a versioned snapshot into caller storage and restores it transactionally. Snapshots retain resource IDs, values, and generation counters. A malformed, truncated, oversized, duplicated, or trailing entry leaves the live cache unchanged. `process.MidiCiDevice` exposes the same snapshot size, write, restore, and handle-scoped lookup operations.

`process.MidiCiPropertyRequestHeader`, `process.MidiCiPropertyReplyHeader`, `process.MidiCiPropertySubscriptionHeader`, and `process.MidiCiPropertyNotifyHeader` parse and write the flat JSON header forms. They enforce the required first property, structural whitespace restriction, 7-bit bytes, field types, resource and subscription identifiers, pagination pairs, partial-set flags, media types, encodings, and the defined reply and Notify status sets. Parsed strings belong to the returned `std.json.Parsed` value and are released by calling `deinit`.

`process.MidiCiPropertyMcoded7` converts arbitrary bytes to and from the canonical 7-bit payload encoding in caller storage. `process.MidiCiPropertyZlibMcoded7` adds the standardized zlib container and checksum using caller-provided compression, history, staging, and output buffers. Decode failures do not change the destination. `process.MidiCiPropertyResourceList`, `process.MidiCiPropertyDeviceInfo`, `process.MidiCiPropertyChannelList`, and `process.MidiCiPropertyProgramList` provide bounded models for the mandatory ResourceList, foundational DeviceInfo and ChannelList resources, and the paginated ProgramList resource. They cover capability defaults and overrides, identity fields, channel clusters, links, zero-based bank and program identities, categories, tags, escaped Unicode output, and bounded JSON parsing. `process.parseMidiCiPropertyJsonSchema` validates and retains a bounded JSON Schema object for the conditional JSONSchema foundational resource.

`process.MidiFlexMessage` covers Set Tempo, Set Time Signature, Set Metronome, Set Key Signature, and Set Chord Name. Group-only setup events enforce their required target. Key and chord messages support channel or group targets. Parsers reject reserved target, format, status, chord-type, alteration, tonic, and payload fields. A time-signature numerator from 1 through 256 round trips through the one-byte wire representation.

`process.MidiFlexTextPacketizer` supports every standardized Metadata Text and Performance Text status, including project and composition names, credits, recording metadata, lyrics, language tags, and Ruby text. It validates complete UTF-8 before emission and caps messages at the protocol limit of 32 packets. The fixed-capacity reassembler preserves target and text kind across segments, checks the same packet limit, and changes retained bytes only after sequence, capacity, and identity checks pass.

`process.MidiMixedDataPacketizer` emits one checked Mixed Data Set header followed by the required 14-byte payload packets. The header carries group, MDS ID, byte count, chunk position, manufacturer, device, and sub-IDs. Its fixed-capacity reassembler derives the final payload length from the header, validates padding and packet identity before copying, and supports header-only chunks.

Additional standardized resources and device-facing MIDI I/O are not yet included. The common header implementation follows the publicly available Property Exchange 1.1 rules. The current 1.2 specification must be reviewed before claiming 1.2 semantic conformance.

## Units And Programs

Units group host-facing parameters. Program lists can publish named parameter snapshots.

```zig
const voice_unit_id: i32 = 1;
const voice_program_list_id: i32 = 7;

pub const VoiceMix = struct {
    pub const name = "Voice Mix";
    pub const vendor = "Example Audio";
    pub const units = plug.units.Config{
        .units = &.{
            plug.units.Unit.root("Main"),
            .{
                .id = voice_unit_id,
                .name = "Voices",
                .parent_id = plug.units.root_unit_id,
                .program_list_id = voice_program_list_id,
            },
        },
        .program_lists = &.{.{
            .id = voice_program_list_id,
            .name = "Voice Presets",
            .programs = &.{
                .{ .name = "Single", .parameters = &.{.{ .parameter_id = 0, .normalized = 0.0 }} },
                .{ .name = "Quad", .parameters = &.{.{ .parameter_id = 0, .normalized = 1.0 }} },
            },
        }},
    };

    pub const Params = struct {
        voices: plug.parameters.IntParam = .{
            .id = 0,
            .name = "Voices",
            .min = 1,
            .max = 4,
            .default = 1,
            .unit_id = voice_unit_id,
        },
    };
};
```

`PluginInstance.unitSet()` and the direct `plug.units.UnitSet` helpers expose unit, program-list, program, parameter snapshot, and metadata lookups by index, id, name, unit, or list. They also report duplicate ids, duplicate names, and cyclic unit-parent links before validation fails.

## Local Checks

Use these checks while changing framework declarations or examples:

```sh
zig build test
zig build validate-examples
```

The checked examples in `examples/*_core.zig` cover the public framework API. The bundled VST3 examples in `zig-vst3/src/*_plugin.zig` exercise the reusable VST3 shells. `examples/mono_gain_lv2.zig` and `zig build test-lv2` cover the LV2 core adapter, shared-library entry points, declaration-driven bundle metadata and factory presets, independent C ABI layout for core, Atom, Options, Worker, State path, and UI declarations, bounded MIDI input and output, segmented sample-offset time Position transport, typed Patch Set and Get properties, block-size option queries and inactive reconfiguration, block-boundary freewheeling transitions, immediate offline and delayed threaded Worker delivery, parameter and component state, portable external and generated resource paths, malformed-state rollback, simultaneous UI instances, repeated close and reopen lifecycles, automation in both directions, touch, idle, show, hide, resize, malformed host inputs, three dynamically loaded libraries, and nine cross-target libraries.

## Current Limits

- The API is pre-release. Names and helper organization can still change before a public compatibility promise.
- Host smoke rows for Note Gate, Event Echo output observation, Event Monitor, and Sine Synth are still deferred.
- LV2 independent metadata validation is complete. External-host testing remains deferred, and the in-process and dynamically loaded host fixtures do not replace interoperability confirmation.
- ARA factory, controller, graph, backward-compatible generic and product-extension archives, concurrent non-realtime audio-reader, validated analysis-request and notification routing, persisted bounded polyphonic-note, static-tuning, piecewise variable-tempo, constant or changing meter, and constant or changing major or minor key-signature detection, and bounded sheet-chord detection, approved tuning editing, content-reader, bounded assignments, editor-view state, transactional source caching, cached realtime playback rendering, main-factory class registration, compile-time class-list assembly, audio-component aggregation, VST3 companion behavior, and a concrete playback reference product are covered internally. Advanced transformation algorithms, and external ARA-host behavior remain deferred.
- There is no bundled GUI toolkit. The raw API exposes editor protocols and the framework can delegate editor creation, but plugin authors bring their own UI stack.
