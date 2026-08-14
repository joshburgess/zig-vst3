# Quality Ownership Record

This record names allocation provenance, transfer, teardown, and failure
evidence for owning types reviewed in Phase 1. A row covers only the stated
type and boundary.

## Q04: VST3 Framework Adapters

| Owner | Acquired resources | Transfer and borrows | Teardown contract | Failure evidence |
| --- | --- | --- | --- | --- |
| Reflected edit `Controller` | Its own allocation; optional controller state; retained component peer, telemetry source, component handlers, unit handlers, progress interface, and host application | VST3 interface queries retain the same controlling object. Returned editor and controller-state pointers borrow the controller lifetime. | The final COM release deinitializes optional state, releases every retained interface, then destroys the object with its stored allocator. `terminate` releases host-facing references early, and final release tolerates the cleared slots. | `reflected edit controller reports outer allocation failure` verifies a null output and no retained allocation when object creation fails. Existing replacement and lifecycle tests verify balanced interface retains. |
| Simple effect `Component` | Its own allocation; processor runtime allocations; embedded ARA extension and entry point; retained connection peer, host application, channel listener, automation state, and data-exchange handler | Delegated VST3, telemetry, and ARA identities retain the component. The processor, ARA extension, host-request sink, and bus snapshots are embedded and cannot outlive it. | The final COM release unbinds and deinitializes ARA, deinitializes the processor, releases retained interfaces, then destroys the object with its stored allocator. Processor construction receives that same allocator. | `simple effect cleans up allocation failures with owning allocator` injects failure at outer-object and processor-storage allocation, then verifies successful final release through the same allocator. The existing fallible-construction test verifies null output on a plugin-defined initialization error. |
| Runtime adapter `ProcessorWithParameters` | `ProcessorRuntime`, the plugin instance, reflected parameter storage, and plugin-owned resources allocated through the caller allocator | Resource and import receiver pointers borrow the embedded plugin lifetime. The host-request sink is borrowed from the containing component and must be unbound or become unreachable before component destruction. | `deinit` delegates to `ProcessorRuntime.deinit`. Deactivation releases prepared resources while preserving an initialized runtime that may be prepared again. | Runtime-adapter tests use `std.testing.allocator` for initialization and deinitialization. The enclosing component failure test now reaches allocator failure inside processor construction. |

### Q04 callback context rule

The component address is stable from successful allocation until the final COM
release. Every callback context that points into the component is either an
embedded interface whose query increments the component reference count or a
borrow passed to the embedded processor. Final release deinitializes the
processor before destroying the component allocation. A retained external
interface is released before destruction, and all release helpers clear their
slots so `terminate` followed by final release is idempotent.

## Q06: Framework Runtime Core

| Owner | Acquired resources | Transfer and borrows | Teardown contract | Failure evidence |
| --- | --- | --- | --- | --- |
| `PluginInstance` | The concrete plugin value returned by its optional `init(Allocator)` hook | Reflected parameter and unit declarations are compile-time values. Views into parameter state and plugin fields borrow the instance lifetime. | If initialization succeeds, the instance exclusively owns the plugin value and invokes its optional `deinit` hook exactly once through its runtime owner. A failing plugin initializer never transfers a value to the instance. | Lifecycle validation requires the allocator-taking fallible initializer and matching pointer-based `deinit` signature. Runtime tests use the Debug allocator for plugin-owned storage. |
| `ProcessorRuntime` | One `PluginInstance` and its prepared plugin resources | Process contexts, host request sinks, and state readers or writers are call-scoped borrows. The runtime does not retain their slices. | `deinit` is idempotent. It deactivates an active instance, releases prepared resources, enters the terminal state, then deinitializes the plugin. Reinitialization requires a new successful `initInto`. | `processor runtime propagates allocation failure without ownership` exhaustively injects allocation failure into a representative plugin initializer. Existing terminal-state tests verify one successful allocation is released and repeated teardown is harmless. |
| `OfflineRenderer` | One `ProcessorRuntime`; all block headers and event staging are fixed stack storage | Render option slices and the optional output event writer borrow the caller for the duration of `render`. | Failure after prepare invokes state-aware cleanup. Normal and error exits deactivate and release prepared resources; `deinit` delegates final plugin ownership release to the runtime. | Existing tests cover invalid options, processing failure cleanup, repeated render, output capacity, and final Debug allocator teardown. |
