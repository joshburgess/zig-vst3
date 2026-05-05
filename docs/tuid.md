# TUID and FUID

VST3 interface identifiers are 16-byte `TUID` values. Steinberg's SDK builds those bytes with the `INLINE_UID(l1, l2, l3, l4)` macro in `pluginterfaces/base/funknown.h`.

The byte order is platform-dependent:

- Windows sets `COM_COMPATIBLE` and stores the first GUID fields in COM layout.
- Linux and macOS store all four 32-bit words in big-endian byte order.

`vst3-zig/src/tuid.zig` mirrors those two paths. The first tests cover the P0 identifiers needed by the COM layer: `FUnknown`, `IPluginBase`, `IComponent`, `IAudioProcessor`, and `IEditController`.

The next ABI step is a generated C++ fixture that prints SDK bytes for the same identifiers on each target triple, then compares those bytes against Zig output in CI.
