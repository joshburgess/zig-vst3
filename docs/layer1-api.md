# Layer 1 Raw API

`zig-vst3` is the raw VST3 binding layer. It exposes Zig translations of Steinberg's COM-style interfaces, helper objects for host-side tests, and reusable component/controller/processor shells used by the bundled examples.

The raw layer deliberately keeps ABI details visible:

- Vtables are explicit `extern struct` values.
- Interface methods use C calling convention function pointers.
- `queryInterface`, `addRef`, and `release` behavior is implemented by small reusable helpers.
- SDK layout assumptions are checked by `zig build layer1-abi`.

Use `zig-vst3-plugin` when you want a higher-level plugin framework. Use `zig-vst3` directly when you need access to VST3 interfaces, host callback objects, custom shell behavior, or ABI tests.

## When To Use Layer 1 Directly

The raw layer is useful when the framework layer is too opinionated for the job:

- You need to expose or test a specific SDK interface directly.
- You are building a custom component, controller, processor, editor, or host-side test object.
- You need exact control over `queryInterface` results and optional interfaces.
- You are checking ABI layout, TUID bytes, entry symbols, or bundle structure.
- You want to prototype a VST3 behavior before deciding whether it belongs in `zig-vst3-plugin`.

For normal audio effects, instruments, analyzers, parameters, state, automation, and event routing, start with `zig-vst3-plugin`.

## Modules

- `zig-vst3/src/pluginterfaces/base`: raw base interfaces, base types, stream, persistence, update, compatibility, and factory declarations.
- `zig-vst3/src/pluginterfaces/gui`: raw plug-view, plug-frame, content-scale, Linux run-loop, and Wayland declarations.
- `zig-vst3/src/pluginterfaces/vst`: raw VST component, processor, controller, parameter, event, unit, MIDI, note-expression, context-menu, data-exchange, representation, and helper declarations.
- `zig-vst3/src/funknown.zig`: reference-count and `FUnknown` helper behavior.
- `zig-vst3/src/interface_map.zig`: `queryInterface` dispatch helpers.
- `zig-vst3/src/factory.zig` and `zig-vst3/src/entry.zig`: factory metadata, `IPluginFactory3` support, and platform entry exports.
- `zig-vst3/src/zig_vst3_plugin_effect.zig`: reusable VST3 shell used by the checked examples.

## Local Checks

```sh
zig build test
zig build layer1-abi
zig build validator
zig build validate-examples
```

`zig build layer1-abi` compares Zig declarations against SDK-backed C++ fixture programs and entry-symbol checks. Public CI runs that gate on Linux and macOS.

`zig build validate-examples` runs the Steinberg validator for native macOS and Linux builds. Windows bundle generation is covered in CI, but Windows validator and real host coverage still need dedicated runners or manual hosts.

## Helper Objects

The raw layer includes fixed-capacity helper objects for tests and shell integration:

- `vst_stream.FixedBufferStream` for `IBStream` and `ISizeableStream`
- `vst_parameter_changes.ParameterChanges` and `ParamValueQueue`
- `vst_event_list.EventList`
- `vst_message.Message`, `AttributeList`, and `StreamAttributes`
- `vst_string_result` and `vst_error_context` for bounded strings and error-message callbacks
- `vst_update_handler` for dependent registration and deferred update tests
- `vst_component_handler` host callback helpers
- `vst_host_application` and `vst_host_context` host-side callback helpers for channel context, automation state, data exchange, wrappers, and host-created objects
- `vst_plugin_compatibility` for fixed compatibility JSON providers and basic metadata fixtures
- `vst_capability_support` helpers for interface support, prefetch state, MIDI learn, MIDI 2 mapping, and physical UI mapping
- `vst_note_expression` for fixed-capacity note-expression and keyswitch metadata helpers
- `vst_parameter_finder` for coordinate lookup, host function-name lookup, and compatible-ID remapping helpers
- `vst_representation` for fixed XML representation streams
- `vst_plug_view`, `vst_plug_frame`, `vst_content_scale_support`, `vst_linux_run_loop`, and `vst_wayland_frame` GUI helper objects
- `vst_unit_data` for fixed-capacity unit, program-list, and unit-data helpers
- `vst_context_menu`, `vst_test_plug_provider`, and `vst_test_interfaces`

These helpers favor deterministic failure behavior. Failed reads, writes, lookups, queue opens, event reads, and string writes clear their output values where that prevents stale host-visible data.

## Direct Raw Workflow

Raw-layer code usually follows this shape:

1. Translate or import the relevant SDK interface from `zig-vst3/src/pluginterfaces`.
2. Use `funknown.zig` and `interface_map.zig` helpers to implement reference counting and interface lookup.
3. Expose the object through `factory.zig` and `entry.zig`, or attach it to one of the reusable shells.
4. Add a Zig test for behavior and, when ABI layout is involved, an SDK-backed fixture under `tests/abi`.
5. Run `zig build test` and `zig build layer1-abi`.

Keep raw objects conservative around host-visible outputs. If a method fails, clear output buffers, counts, and pointers when stale values could be misread by a host.

## Bundle And Validator Flow

Use the bundle steps when validating raw-layer changes against real VST3 loading:

```sh
zig build clean-bundles
zig build bundle-examples
zig build validator
zig build validate-examples
```

`bundle-examples-linux` and `bundle-examples-windows` cross-build target bundle layouts. They prove the bundle shape and compilation target, but they do not replace native validator or real-host smoke tests on those platforms.

## Current Limits

- The binding surface is broad and now includes reusable helpers for the known SDK 3.8.0 interface groups in the inventory. Some rare interfaces still expose raw declarations rather than production-oriented convenience wrappers.
- GUI/editor coverage is unit-test and ABI-test based. Real embedded editor behavior still needs host-specific smoke tests.
- Windows validator execution is not yet part of CI.
- Manual host coverage is currently macOS REAPER-heavy, with MIDI-heavy and analyzer/instrument examples still deferred.
