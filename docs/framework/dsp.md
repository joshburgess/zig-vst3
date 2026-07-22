# DSP Utilities

`zig-vst3-plugin.dsp` provides bounded processing utilities that can run inside a plugin audio callback. The current public surface includes scoped denormal control, smoothed biquads, streaming sample-rate conversion, and a two-stage fixed-rate processing pipeline.

## Denormal handling

`DenormalScope` enables flush-to-zero behavior for the current thread on aarch64 and x86-64, then restores the exact floating-point control state it observed. On x86-64 it enables both FTZ and DAZ in MXCSR. On aarch64 it enables FZ in FPCR.

```zig
const plug = @import("zig-vst3-plugin");

pub fn process(self: *Processor, context: *plug.process.ProcessContext(f32)) void {
    var denormals = plug.dsp.DenormalScope.enter();
    defer denormals.leave();

    self.model.process(context);
}
```

Create the scope at the outer edge of the audio callback, not inside a sample or layer loop. Leave it on the same thread and do not copy an active scope. Nested scopes are safe. If the host already enabled the policy, leaving the scope does not alter it. Unsupported architectures use a no-op scope and should avoid subnormal state algorithmically until they gain an explicit implementation.

This policy is preferable to injecting noise into a neural or convolution signal path because it preserves deterministic silence and numerical parity above the subnormal range. It does not replace stable recurrence design, bounded state, or explicit resets.

## Streaming sample-rate conversion

`StreamingResampler(f32)` and `StreamingResampler(f64)` use a 32-tap, 256-phase Blackman-windowed sinc filter. Each instance owns fixed inline coefficient and history storage. Configuration builds the coefficient table during preparation. `process`, `reset`, and draining do not allocate or lock.

```zig
const plug = @import("zig-vst3-plugin");

var resampler = try plug.dsp.StreamingResampler(f32).init(.{
    .input_rate = 44_100.0,
    .output_rate = 48_000.0,
});

const result = try resampler.process(input, output);
```

`process` reports both consumed input and produced output. A caller may provide partial input or output slices and continue with the remaining data. `beginDrain` fixes the end of the stream, and `drain` emits the bounded filter tail. `reset` clears history and returns the instance to its configured startup state.

Rates must be finite and between 1 kHz and 2 MHz. Non-finite input samples are replaced with zero. The filter cutoff is reduced while downsampling to reject content above the destination Nyquist limit. The implementation is part of this repository and uses the repository license.

## Fixed-rate processing

`FixedRatePipeline(Sample)` converts host audio to a declared model rate and converts the result back to the host rate. It is intended for neural models and other DSP implementations trained or designed for one sample rate.

```zig
var pipeline = try plug.dsp.FixedRatePipeline(f32).init(.{
    .host_rate = 44_100.0,
    .model_rate = 48_000.0,
});

const required = try pipeline.requiredModelCapacity(host_input.len);
if (model_scratch.len < required) return error.InsufficientScratch;

const model_frames = try pipeline.convertInput(host_input, model_scratch);
model.process(model_scratch[0..model_frames]);
try pipeline.convertOutput(model_scratch[0..model_frames], host_output);
```

The caller owns model-rate scratch storage. Allocate it during preparation using the maximum host block size and `requiredModelCapacity`. The supported host-to-model ratio is bounded to 8:1 in either direction. The pipeline keeps at most ten model frames in fixed pending storage while reconciling arbitrary host block boundaries.

The two resampling stages choose their delays so the round-trip latency is an exact integer number of host samples. `latencySamples` returns that value. Call `reset` after transport discontinuities, processing restarts, or a prepared mode change.

The deterministic tests cover:

- 44.1, 48, 88.2, and 96 kHz host rates with a 48 kHz model rate.
- Exact impulse-peak latency.
- Randomized host block boundaries.
- Passband amplitude and stopband attenuation.
- Reset, drain, invalid configuration, and insufficient scratch behavior.

The Fixed Rate Processor example applies a trivial gain at 48 kHz. It uses only the public framework API and safely passes through unsupported validator rates. On the current macOS development machine, the complete two-stage conversion measured 30.0 to 44.7 ns per host sample across the four common host rates.

## Dynamic latency

A processor that can change latency may declare this optional hook:

```zig
pub fn bindHostRequests(self: *Processor, requests: *plug.HostRequestSink) void {
    self.host_requests = requests;
}
```

Use `markLatencyChanged` to coalesce a pending notification. Call `dispatchPending` only from a control, background, or UI thread. Debug and test builds reject dispatch from a real-time audit scope before making a host call.

The safe transition order is:

1. Prepare the new processing configuration without exposing it to the audio thread.
2. Publish the new value returned by `latencySamples`.
3. Mark and dispatch the latency change outside processing.
4. After successful dispatch, make the prepared mode eligible for adoption.
5. Adopt the new mode at the next audio block boundary and reset its history.

The raw VST3 shell sends a component-to-controller message. The reflected controller then asks the host to restart the component with `kLatencyChanged`. Repeated marks before dispatch produce one restart request. A failed dispatch remains pending for a later non-real-time retry.

The host request sink belongs to the component. Do not retain it beyond processor teardown, invoke it after component destruction, or call `dispatchPending` from `process`.

## Reference implementation

The complete public-API example is split between `examples/fixed_rate_core.zig` and `examples/fixed_rate_plugin.zig`.

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-fixed-rate validate-fixed-rate
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build benchmark
```
