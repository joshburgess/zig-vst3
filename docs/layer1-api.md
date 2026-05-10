# Layer 1 Raw API

`vst3-zig` is the raw VST3 binding layer. It exposes Zig translations of Steinberg's COM-style interfaces, helper objects for host-side tests, and reusable component/controller/processor shells used by the bundled examples.

The raw layer deliberately keeps ABI details visible:

- Vtables are explicit `extern struct` values.
- Interface methods use C calling convention function pointers.
- `queryInterface`, `addRef`, and `release` behavior is implemented by small reusable helpers.
- SDK layout assumptions are checked by `zig build layer1-abi`.

Use `zig-plug` when you want a higher-level plugin framework. Use `vst3-zig` directly when you need access to VST3 interfaces, host callback objects, custom shell behavior, or ABI tests.

## Modules

- `vst3-zig/src/pluginterfaces/base`: raw base interfaces, base types, stream, persistence, update, compatibility, and factory declarations.
- `vst3-zig/src/pluginterfaces/gui`: raw plug-view, plug-frame, content-scale, Linux run-loop, and Wayland declarations.
- `vst3-zig/src/pluginterfaces/vst`: raw VST component, processor, controller, parameter, event, unit, MIDI, note-expression, context-menu, data-exchange, representation, and helper declarations.
- `vst3-zig/src/funknown.zig`: reference-count and `FUnknown` helper behavior.
- `vst3-zig/src/interface_map.zig`: `queryInterface` dispatch helpers.
- `vst3-zig/src/factory.zig` and `vst3-zig/src/entry.zig`: factory metadata and platform entry exports.
- `vst3-zig/src/zig_plug_effect.zig`: reusable VST3 shell used by the checked examples.

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
- `vst_component_handler` host callback helpers
- `vst_host_application` and `vst_host_context` host-side callback helpers
- `vst_capability_support` helpers for interface support, prefetch state, MIDI learn, MIDI 2 mapping, and physical UI mapping
- `vst_note_expression` for fixed-capacity note-expression and keyswitch metadata helpers
- `vst_representation` for fixed XML representation streams
- `vst_plug_view`, `vst_plug_frame`, `vst_content_scale_support`, `vst_linux_run_loop`, and `vst_wayland_frame` GUI helper objects
- `vst_unit_data` for fixed-capacity unit, program-list, and unit-data helpers
- `vst_context_menu`, `vst_test_plug_provider`, and `vst_test_interfaces`

These helpers favor deterministic failure behavior. Failed reads, writes, lookups, queue opens, event reads, and string writes clear their output values where that prevents stale host-visible data.

## Current Limits

- The binding surface is broad, but not every rare interface has a production-oriented convenience wrapper.
- GUI/editor coverage is unit-test and ABI-test based. Real embedded editor behavior still needs host-specific smoke tests.
- Windows validator execution is not yet part of CI.
- Manual host coverage is currently macOS REAPER-heavy.
