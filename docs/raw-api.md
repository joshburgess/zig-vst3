# Raw VST3 API

`zig-vst3` is the raw VST3 API package. It exposes Zig translations of Steinberg's COM-style interfaces, helper objects for host-side tests, and reusable component/controller/processor shells used by the bundled examples.

The raw API deliberately keeps ABI details visible:

- Vtables are explicit `extern struct` values.
- Interface methods use C calling convention function pointers.
- `queryInterface`, `addRef`, and `release` behavior is implemented by small reusable helpers.
- SDK layout assumptions are checked by `zig build raw-api-abi`.

Use `zig-vst3-plugin` when you want a higher-level plugin framework. Use `zig-vst3` directly when you need access to VST3 interfaces, host callback objects, custom shell behavior, or ABI tests.

## When To Use The Raw API

The raw API is useful when the plugin framework is too opinionated for the job:

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
zig build raw-api-abi
zig build validator
zig build validate-examples
```

`zig build raw-api-abi` compares Zig declarations against SDK-backed C++ fixture programs and entry-symbol checks. Public CI runs that gate on Linux and macOS.

`zig build validate-examples` runs the Steinberg validator for native macOS and Linux builds. Public CI also runs the Steinberg validator against the cross-built Windows bundles. Real host coverage still needs manual hosts.

## Helper Objects

The raw API includes fixed-capacity helper objects for tests and shell integration:

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

## Implement An SDK Helper Object

Most raw helper objects follow the same pattern:

1. Store one or more SDK interface structs as fields. Each interface field points at a static vtable.
2. Store reference-count state with `std.atomic.Value(types.uint32)`.
3. Add `asInterfaceName` helpers that return pointers to the embedded interface fields.
4. Use `@fieldParentPtr` in vtable methods to recover the owning helper object.
5. Implement `queryInterface` with `interface_map.queryWithAddRef`.
6. Clear host-visible output values on failure when stale data would be misleading.

The `vst_string_result.StringResult` helper is a small example because it exposes both `IStringResult` and `IString` from one object:

```zig
pub fn StringResult(comptime max_text8_bytes: usize, comptime max_text16_units: usize) type {
    return extern struct {
        const Self = @This();

        result_iface: istringresult.IStringResult = .{ .vtable = &result_vtable },
        string_iface: istringresult.IString = .{ .vtable = &string_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        text8: [max_text8_bytes]types.char8 = [_]types.char8{0} ** max_text8_bytes,
        text16: [max_text16_units]types.char16 = [_]types.char16{0} ** max_text16_units,

        pub fn asResult(self: *Self) *istringresult.IStringResult {
            return &self.result_iface;
        }

        fn ownerFromResult(ptr: *anyopaque) *Self {
            const iface: *istringresult.IStringResult = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("result_iface", iface);
        }

        fn queryCanonical(
            self: *Self,
            add_ref_ptr: *anyopaque,
            requested_iid: *const tuid.TUID,
            out: *?*anyopaque,
        ) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.result_iface },
                .{ .iid = &istringresult.istring_result_iid, .ptr = &self.result_iface },
                .{ .iid = &istringresult.istring_iid, .ptr = &self.string_iface },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, resultAddRef, &entries, requested_iid, out);
        }
    };
}
```

For production helpers, keep vtable methods small and test both the direct helper API and the raw interface calls. If the object implements several interfaces, test `queryInterface` from each exposed interface pointer so canonical identity and reference-count behavior stay correct.

## Query Interfaces Directly

Raw helpers expose SDK interface pointers through `asInterface`-style methods. Call the vtable exactly as a host would:

```zig
const Stream = vst_stream.FixedBufferStream(64);
var stream = Stream{};
const iface = stream.asStream();

var queried: ?*anyopaque = null;
try std.testing.expectEqual(
    types.kResultOk,
    iface.vtable.queryInterface(iface, &ibstream.isizeable_stream_iid, &queried),
);

const queried_ptr = queried orelse return error.MissingSizeableStream;
const sizeable: *ibstream.ISizeableStream = @ptrCast(@alignCast(queried_ptr));
defer _ = sizeable.vtable.release(sizeable);

var size: types.int64 = -1;
try std.testing.expectEqual(types.kResultOk, sizeable.vtable.getStreamSize(sizeable, &size));
```

Always release successful `queryInterface` results in tests and host adapters. The helpers increment the shared reference count through `interface_map.queryWithAddRef`.

## Use IBStream Helpers

`vst_stream.FixedBufferStream` is useful for state, preset, and stream callback tests:

```zig
const Stream = vst_stream.FixedBufferStream(16);
var stream = Stream{};
const iface = stream.asStream();

var input = [_]u8{ 1, 2, 3 };
var written: types.int32 = 0;
try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, &written));

var pos: types.int64 = -1;
try std.testing.expectEqual(
    types.kResultOk,
    iface.vtable.seek(iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &pos),
);

var output = [_]u8{0} ** 3;
var read: types.int32 = 0;
try std.testing.expectEqual(types.kResultOk, iface.vtable.read(iface, &output, output.len, &read));
```

The helper implements both `IBStream` and `ISizeableStream`. Failed reads and writes leave reported byte counts at zero where the SDK method provides an output count.

## Use Event Lists

`vst_event_list.EventList` gives tests a bounded `IEventList`:

```zig
const List = vst_event_list.EventList(4);
var list = List{};
const iface = list.asInterface();

var event = ivstevents.Event{
    .sampleOffset = 3,
    .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
    .data = .{ .noteOn = .{ .pitch = 60, .velocity = 0.5 } },
};

try std.testing.expectEqual(types.kResultOk, iface.vtable.addEvent(iface, &event));
try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getEventCount(iface));

var read_event = ivstevents.Event{};
try std.testing.expectEqual(types.kResultOk, iface.vtable.getEvent(iface, 0, &read_event));
```

Out-of-range reads clear the output event before returning an error result. This prevents stale event data from being misread by the caller.

## Use Parameter Changes

`vst_parameter_changes.ParameterChanges` and `ParamValueQueue` model VST3 automation queues:

```zig
const Changes = vst_parameter_changes.ParameterChanges(2, 8);
var changes = Changes{};

const queue = changes.addQueue(7) orelse return error.MissingParameterQueue;
try std.testing.expectEqual(types.kResultOk, queue.appendPoint(0, 0.25));
try std.testing.expectEqual(types.kResultOk, queue.appendPoint(32, 0.75));

const iface = changes.asInterface();
try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getParameterCount(iface));

const queue_iface = iface.vtable.getParameterData(iface, 0) orelse return error.MissingParameterQueue;
try std.testing.expectEqual(@as(vsttypes.ParamID, 7), queue_iface.vtable.getParameterId(queue_iface));

var offset: types.int32 = -1;
var value: vsttypes.ParamValue = -1;
try std.testing.expectEqual(types.kResultOk, queue_iface.vtable.getPoint(queue_iface, 1, &offset, &value));
```

`addParameterData` returns an existing queue for a repeated parameter id and reports the queue index through the SDK output pointer. When capacity is exhausted, it returns `null` and writes `-1` to the index output.

## Direct Raw Workflow

Raw API code usually follows this shape:

1. Translate or import the relevant SDK interface from `zig-vst3/src/pluginterfaces`.
2. Use `funknown.zig` and `interface_map.zig` helpers to implement reference counting and interface lookup.
3. Expose the object through `factory.zig` and `entry.zig`, or attach it to one of the reusable shells.
4. Add a Zig test for behavior and, when ABI layout is involved, an SDK-backed fixture under `tests/abi`.
5. Run `zig build test` and `zig build raw-api-abi`.

Keep raw objects conservative around host-visible outputs. If a method fails, clear output buffers, counts, and pointers when stale values could be misread by a host.

## Bundle And Validator Flow

Use the bundle steps when validating raw API changes against real VST3 loading:

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
- Windows validator execution now runs in CI against the cross-built Windows bundles. Real embedded host coverage on Windows is still pending.
- Manual host coverage is currently macOS REAPER-heavy, with MIDI-heavy and analyzer/instrument examples still deferred.
