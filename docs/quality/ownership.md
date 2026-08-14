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
