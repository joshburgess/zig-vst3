# TUID and FUID

VST3 interface identifiers are 16-byte `TUID` values. Steinberg's SDK builds those bytes with the `INLINE_UID(l1, l2, l3, l4)` macro in `pluginterfaces/base/funknown.h`.

The byte order is platform-dependent:

- Windows sets `COM_COMPATIBLE` and stores the first GUID fields in COM layout.
- Linux and macOS store all four 32-bit words in big-endian byte order.

`zig-vst3/src/tuid.zig` mirrors those two paths. The tests cover the P0 identifiers needed by the COM path: `FUnknown`, `IPluginBase`, `IComponent`, `IAudioProcessor`, and `IEditController`.

The ABI fixtures build small SDK-backed C++ programs and compare their printed bytes against the Zig implementation. `zig build raw-api-abi` runs those checks with the rest of the raw API ABI harness, and public CI runs that step on Linux and macOS.
