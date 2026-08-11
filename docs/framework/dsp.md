# DSP Utilities

`zig-vst3-plugin.dsp` provides bounded processing utilities that can run inside a plugin audio callback. The current public surface includes scoped denormal control, FFT and FIR processing, oscillators, fractional delay, dry/wet mixing, panning, waveshaping, modulation effects, dynamics and envelope tracking, algorithmic reverb, partitioned convolution, biquad and topology-preserving filters, crossover splitting, gain and bias, logarithmic ramping, lookup tables, processor composition and duplication, finite impulse-response and streaming sample-rate conversion, and a two-stage fixed-rate processing pipeline.

Root configuration names identify their processor or algorithm, such as `BiquadConfig`, `ResamplerConfig`, and `FixedRateConfig`. Invalid configurations return the matching domain-qualified error tag rather than a generic configuration error.

## FFT And FIR

`Fft(Sample, size)` provides an in-place radix-2 complex transform for `f32` or `f64`. The size is fixed at compile time and must be a power of two. `forward` is unnormalized, while `inverse` scales by `1 / size`. Both validate the complete complex input before changing it. `forwardReal` converts real input into the full complex spectrum. `inverseReal` reconstructs the real component without changing its spectrum input. `forwardMagnitudes` writes the nonnegative-frequency magnitudes.

```zig
const Transform = plug.dsp.Fft(f32, 1_024);
const fft = Transform.init();
var spectrum: [1_024]Transform.Value = undefined;
try fft.forwardReal(&input, &spectrum);
```

Each transform owns `size` precomputed twiddle components split between forward and inverse tables. It has no heap allocation, planner, SIMD backend, arbitrary-size fallback, or packed real-only layout.

`FirFilter(Sample, coefficient_capacity)` owns fixed coefficient and history storage. `configure` validates the complete replacement, publishes it transactionally, and resets history.

```zig
var fir = try plug.dsp.FirFilter(f32, 64).init(coefficients);
fir.process(samples);
```

The FIR uses direct time-domain convolution. Long impulse responses should use `PartitionedConvolver`.

## Windows And FIR Design

`fillWindow` and `applyWindow` support rectangular, triangular, Hann, Hamming, Blackman, Blackman-Harris, and flat-top windows. `fillKaiserWindow` and `applyKaiserWindow` accept a nonnegative Kaiser beta. A window can use symmetric filter-design endpoints or a periodic FFT layout. Unit-sum and unit-peak normalization are optional.

```zig
var analysis_window: [1_024]f32 = undefined;
try plug.dsp.fillWindow(
    f32,
    &analysis_window,
    .hann,
    true,
    .unit_peak,
);
```

```zig
try plug.dsp.fillKaiserWindow(
    f32,
    &analysis_window,
    8.0,
    false,
    .unit_peak,
);
```

`FirDesigner(Sample)` writes odd-length low-pass, high-pass, band-pass, and band-stop coefficients using a selected window. Frequencies use cycles per sample from `0.0` through the Nyquist limit at `0.5`. Invalid lengths and cutoff ranges are rejected before the output changes.

```zig
var coefficients: [63]f32 = undefined;
try plug.dsp.FirDesigner(f32).lowPass(
    &coefficients,
    0.125,
    .blackman_harris,
);
var filter = try plug.dsp.FirFilter(f32, 63).init(&coefficients);
```

The designer normalizes low-pass and band-stop filters at DC, high-pass filters at Nyquist, and band-pass filters at the center of their requested pass band. `magnitude` evaluates the resulting response at a normalized frequency.

`leastSquares` designs odd-length linear-phase FIR filters of up to 255 taps from weighted, non-overlapping frequency bands. Each band can specify a constant or linearly changing desired gain. Midpoint samples include the represented frequency width in the weighted objective, so changing a band's width changes its total error contribution as it does in the continuous least-squares integral. The bounded solver incrementally updates a QR factorization, so it does not allocate or form condition-number-squaring normal equations. Validation and solution checks complete before the output coefficients change.

`FirEquirippleDesigner(Sample)` designs minimax linear-phase FIR filters of up to 255 taps. `design` selects Type I or Type II even symmetry from the odd or even tap count. `designWithSymmetry` also supports Type III and Type IV odd symmetry. It accepts as many as eight weighted bands with constant or linearly changing desired gain. The bounded exchange solver uses a configurable dense grid, partial-pivot linear solves, alternating-extremum selection, explicit convergence limits, and transactional publication. The returned report provides the iteration count, weighted ripple, and extremum count.

```zig
var differentiator: [32]f32 = undefined;
_ = try plug.dsp.FirEquirippleDesigner(f32).designWithSymmetry(
    &differentiator,
    &.{
        .{
            .lower_frequency = 0.0,
            .upper_frequency = 0.45,
            .lower_gain = 0.0,
            .upper_gain = 0.9,
        },
    },
    .odd,
    .{},
);
```

Type II designs enforce the zero at Nyquist. Type III designs enforce zeros at DC and Nyquist, and Type IV designs enforce the zero at DC. A requested nonzero gain at a constrained endpoint is rejected before output changes.

`PolyphaseFirBank(Sample, phase_count, taps_per_phase)` decomposes a caller-provided FIR prototype into fixed-capacity phases and reconstructs it without loss. `lowPass` designs and decomposes an odd-length windowed prototype in one operation. `processPhase` evaluates one phase against newest-first history, with finite input and output checks.

Independent response tests use [SciPy 1.17 signal design](https://docs.scipy.org/doc/scipy/reference/signal.html) and `upfirdn` results for weighted least-squares, all four equiripple symmetry forms, and polyphase interpolation. The test vectors are fixed in the Zig suite, so SciPy is not a build dependency.

`ButterworthDesigner(Sample)` designs low-pass and high-pass cascades from order 1 through order 16. `lowPassOrder` and `highPassOrder` return a `ButterworthCascade` with the active section count and requested order. Odd orders begin with a first-order section. Cascade validation includes the retained order, section count, and every active coefficient, and `active` returns an empty slice for malformed retained state. The slice-based `lowPass` and `highPass` functions remain available for even orders, with each output element representing one second-order section.

```zig
const cascade = try plug.dsp.ButterworthDesigner(f32).lowPassOrder(
    5,
    sample_rate,
    2_000.0,
);
for (cascade.active()) |section| {
    _ = section;
}

const specified =
    try plug.dsp.ButterworthDesigner(f32).lowPassForSpecification(.{
        .sample_rate = sample_rate,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 60.0,
    });
```

`lowPassForSpecification` and `highPassForSpecification` prewarp the passband and stopband edges, derive the minimum Butterworth order, and return the adjusted cutoff. Requests that need more than sixteen poles are rejected.

`ChebyshevDesigner(Sample)` returns similarly bounded Type I low-pass or high-pass cascades. The checked configuration accepts orders 1 through 16 and pass-band ripple from 0.01 dB through 12 dB.

```zig
const cascade = try plug.dsp.ChebyshevDesigner(f32).lowPass(.{
    .order = 7,
    .sample_rate = sample_rate,
    .frequency_hz = 2_000.0,
    .ripple_db = 1.0,
});

const specified =
    try plug.dsp.ChebyshevDesigner(f32).lowPassForSpecification(.{
        .sample_rate = sample_rate,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 60.0,
    });
```

The specification methods derive the minimum Type I order while retaining the requested pass-band ripple. Invalid frequency, sample-rate, order, section-count, and ripple requests are rejected. Slice output remains unchanged after a failed Butterworth request.

`ChebyshevTypeIIDesigner(Sample)` designs inverse-Chebyshev low-pass and high-pass cascades from order 1 through order 16. Its fixed-order critical frequency is the stopband point where attenuation first reaches the configured value. The specification methods derive the minimum order and adjusted critical frequency needed to satisfy both requested edges.

```zig
const specified =
    try plug.dsp.ChebyshevTypeIIDesigner(f32)
        .lowPassForSpecification(.{
            .sample_rate = sample_rate,
            .passband_hz = 1_000.0,
            .stopband_hz = 2_000.0,
            .maximum_passband_loss_db = 1.0,
            .minimum_stopband_attenuation_db = 60.0,
        });
```

`EllipticDesigner(Sample)` provides the same bounded low-pass and high-pass surface with independent passband ripple and stopband attenuation. Its specification methods derive the minimum order through complete elliptic integrals. The normalized pole and zero construction uses the checked real Jacobian elliptic functions.

```zig
const elliptic =
    try plug.dsp.EllipticDesigner(f32).lowPassForSpecification(.{
        .sample_rate = sample_rate,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 60.0,
    });
```

Low-pass and high-pass Chebyshev Type II and elliptic response tests use fixed [SciPy signal](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.cheby2.html) reference vectors. Forward real Jacobian functions and their principal real inverses also have fixed SciPy 1.17 vector coverage.

`PolyphaseAllpassDesigner(Sample).halfBandLowPass` designs a bounded half-band IIR as two parallel cascades of second-order all-pass sections. The request specifies normalized transition width and stopband attenuation. The returned design exposes direct and delayed path coefficients, low-pass and complementary high-pass magnitude evaluation, section counts, and the derived odd order. Count and coefficient accessors return zero or null for malformed retained counts and for section-index arithmetic overflow.

```zig
const design =
    try plug.dsp.PolyphaseAllpassDesigner(f32)
        .halfBandLowPass(0.05, -90.0);
var filter =
    try plug.dsp.PolyphaseAllpassHalfBandFilter(f32).init(design);
const split = try filter.processSampleSplit(input);
const low = split.low_pass;
const high = split.high_pass;
```

The processor averages the direct and one-sample-delayed paths for unity low-pass gain. `processSampleSplit` also returns their complementary difference. Design is bounded to 32 total all-pass sections, and overly narrow or deep requests return a capacity error. Series convergence, coefficient stability, input samples, retained state, analytic response requests, and reconfiguration are checked. Reconfiguration is transactional and resets filter history only after a complete valid replacement is available.

All four real linear-phase equiripple forms are covered. Complex-coefficient and arbitrary-phase minimax design remain outside this module.

## Oversampling

`Oversampler(Sample, maximum_frames, factor)` provides bounded 2x, 4x, 8x, or 16x single-channel oversampling. `upsample` returns mutable instance-owned storage for the high-rate processing step. Pass an output block with the original frame count to `downsample`.

`DummyOversampler(Sample, maximum_frames)` presents the same upsample, mutable processing, downsample, reset, and sequencing contract at factor 1 with zero latency. `SelectableOversampler(Sample, maximum_frames, factor)` owns both dummy and filtered pipelines and switches only between complete blocks. This keeps one processing call shape for products with an Off plus 2x, 4x, 8x, or 16x quality selection. `oversamplingFactor` and `latencySamples` report the active path.

```zig
var oversampler = try plug.dsp.Oversampler(f32, 512, 4).init();
const high_rate = try oversampler.upsample(input);
processNonlinear(high_rate);
try oversampler.downsample(output);
```

`MultichannelOversampler(Sample, maximum_frames, factor, maximum_channels)` owns one independent conversion pipeline per active channel. It validates the complete planar input shape before advancing any channel and returns one mutable high-rate view per channel.

```zig
var oversampler = try plug.dsp.MultichannelOversampler(
    f32,
    512,
    4,
    8,
).init(2);
const high_rate = try oversampler.upsample(input_channels);
processNonlinearChannels(high_rate);
try oversampler.downsample(output_channels);
```

Each conversion filter uses `factor * 8 + 1` Blackman-Harris-windowed FIR taps. The round trip has eight base-rate samples of latency. State continues across blocks, and `reset` clears both filter histories. A nonempty upsampled block must be downsampled before the next call to `upsample`.

`PolyphaseIirOversampler(Sample, maximum_frames, factor)` provides an alternative 2x, 4x, 8x, or 16x pipeline built from the polyphase all-pass design. Its configuration chooses transition width and stopband attenuation. Every 2x stage runs at its natural rate and uses separate interpolation and decimation history. `init` applies one checked design to every stage. `initStages` accepts one configuration per stage. The corresponding `initWithOptions` and `initStagesWithOptions` forms can enable integer latency.

```zig
var oversampler =
    try plug.dsp.PolyphaseIirOversampler(f32, 512, 4).init(.{
        .normalized_transition_width = 0.08,
        .stopband_attenuation_db = -90.0,
    });
const high_rate = try oversampler.upsample(input);
processNonlinear(high_rate);
try oversampler.downsample(output);
const wet_latency = try oversampler.latencySamples();
```

Without integer-latency adjustment, `latencySamples` returns the fractional base-rate group delay for the selected designs. Integer mode adds a stable first-order all-pass fractional delay after decimation and reports the resulting whole-sample latency. The compensation preserves magnitude while changing phase.

`MultichannelPolyphaseIirOversampler(Sample, maximum_frames, factor, maximum_channels)` owns one independent IIR pipeline per active channel. It supports the common and per-stage initializers, validates the complete planar input before advancing state, and delays all caller-output writes until every channel has decimated successfully.

```zig
var oversampler =
    try plug.dsp.MultichannelPolyphaseIirOversampler(
        f32,
        512,
        4,
        8,
    ).init(2, .{});
const high_rate = try oversampler.upsample(input_channels);
processNonlinearChannels(high_rate);
try oversampler.downsample(output_channels);
```

`RuntimePolyphaseIirOversampler(Sample, maximum_frames, maximum_stages)` chooses its active stage count at initialization or between complete blocks. An empty configuration slice is a mutable factor-1 path, and each additional independently specified half-band stage doubles the rate up to the compile-time maximum. `reconfigure` designs a complete replacement before changing live state, resets all histories on success, rejects changes while a high-rate block is pending, and can enable exact integer latency. `RuntimeMultichannelPolyphaseIirOversampler` applies the same runtime sequence and transactional output contract to every active channel.

`MixedOversampler(Sample, maximum_frames, maximum_stages)` accepts a bounded runtime list containing equiripple FIR, polyphase IIR, and dummy stages. Real stages double the rate while dummy stages preserve both the samples and factor. FIR and IIR stages accept independent upsampling and downsampling transition widths and stopband attenuations. FIR tap count is selected automatically, the completed equiripple response is normalized to exact DC gain, and a dense response check must satisfy both directional specifications before the configuration is published. `MixedMultichannelOversampler` applies the same list to independent channel histories and commits caller output only after every channel succeeds. Multichannel FIR, fixed and runtime polyphase IIR, and mixed accessors reject malformed retained channel counts before indexing fixed processor storage.

All oversampler families preserve state across blocks and reject a second upsample before the pending high-rate block is consumed. Input validation completes before filter histories advance. The IIR and mixed forms additionally validate user mutations to high-rate storage before decimation and reset all stages if an internal arithmetic failure occurs. Automatic dry-path latency compensation remains a product-level routing policy.

## Mixing And Waveshaping

`DryWetMixer(Sample, maximum_frames, maximum_latency_samples)` pairs a retained dry block with a wet block. `pushDry` applies zero through `maximum_latency_samples` of fractional latency compensation. `mixWet` supports linear, balanced, equal-power, sine-based 3 dB, 4.5 dB, and 6 dB laws, plus square-root 3 dB and 4.5 dB laws.

```zig
var mixer = try plug.dsp.DryWetMixer(f32, 512, 64).init(.{
    .wet = 0.5,
    .wet_latency_samples = 8.0,
});
try mixer.pushDry(input);
processWet(wet);
try mixer.mixWet(wet);
```

Only one dry block may be pending. Pending storage starts at zero and is scrubbed after successful mixing or reset. Frame mismatches, non-finite samples, and reconfiguration while a block is pending are rejected without releasing that block. Use one mixer per independently compensated channel.

`WaveShaper(Sample)` supplies hard-clip, hyperbolic-tangent, arctangent, and cubic curves with checked drive, output gain, dry/wet mix, and gain law.

```zig
var shaper = try plug.dsp.WaveShaper(f32).init(.{
    .kind = .tanh,
    .drive_db = 12.0,
    .output_db = -3.0,
});
shaper.process(samples);
```

Configuration changes take effect immediately. The waveshaper does not smooth parameters or suppress aliasing. Use `Oversampler` around nonlinear processing when the workload requires alias reduction.

## Modulation Effects

`Chorus(Sample, maximum_delay_samples)` uses a sine-modulated cubic delay with checked rate, center delay, depth, feedback, mix, and gain law. It is single-channel and retains its LFO, delay, and feedback state across blocks.

```zig
var chorus = try plug.dsp.Chorus(f32, 2_048).init(.{
    .sample_rate = sample_rate,
    .rate_hz = 0.8,
    .center_delay_ms = 7.0,
    .depth_ms = 2.5,
});
try chorus.process(input, output);
```

`Flanger(Sample, maximum_delay_samples)` uses the same bounded cubic-delay core with short delays, linear dry/wet mixing, and feedback. `Vibrato(Sample, maximum_delay_samples)` exposes only the modulated delayed path and disables feedback. All three delay effects preserve their delay and LFO state across arbitrary block partitions.

```zig
var flanger = try plug.dsp.Flanger(f32, 512).init(.{
    .sample_rate = sample_rate,
});
var vibrato = try plug.dsp.Vibrato(f32, 2_048).init(.{
    .sample_rate = sample_rate,
});

const StereoFlanger = plug.dsp.StereoModulation(
    f32,
    plug.dsp.Flanger(f32, 512),
);
var stereo_flanger = try StereoFlanger.init(
    try plug.dsp.Flanger(f32, 512).init(.{
        .sample_rate = sample_rate,
    }),
    try plug.dsp.Flanger(f32, 512).init(.{
        .sample_rate = sample_rate,
    }),
    0.25,
);
try stereo_flanger.process(
    left_input,
    right_input,
    left_output,
    right_output,
);
```

`StereoModulation(Sample, Processor)` coordinates matching left and right processors, resets them with a fixed fractional-cycle phase offset, validates all four channel lengths before processing, and preserves arbitrary block partitioning. Matching processor rates are required to preserve the offset over time.

`Phaser(Sample, stage_count)` cascades one through sixteen first-order all-pass stages. Its sine LFO sweeps logarithmically between the configured minimum and maximum frequencies. `configureSmooth` ramps both frequency bounds together, plus feedback, wet mix, and LFO rate. The paired frequency ramps share one sample count, preserve their ordering, and reject hostile desynchronization.

```zig
var phaser = try plug.dsp.Phaser(f32, 6).init(.{
    .sample_rate = sample_rate,
    .minimum_hz = 300.0,
    .maximum_hz = 2_000.0,
});
try phaser.process(input, output);
```

`ModulationNoteDivision` covers straight, dotted, and triplet divisions from whole notes through thirty-second notes. `modulationRateHz` converts quarter-note BPM to cycles per second. `modulationTempoFromTransport` validates the complete host value and applies a checked caller fallback when tempo is absent. `modulationPhaseFromTransport` derives a wrapped fractional cycle from the project quarter-note position for custom modulation processors. It returns `null` when position is absent, the transport is invalid, or subdivision scaling overflows. `syncTempo` applies tempo conversion to chorus, flanger, vibrato, modulated delay, and phaser. `syncTransport` follows the same checked tempo contract. Repeating the same target each block does not restart the ramp.

```zig
try chorus.syncTempo(
    120.0,
    .dotted_quarter,
    0.05,
);

try chorus.syncTransport(
    context.transport(),
    120.0,
    .dotted_eighth,
    0.05,
);
```

The reusable `ModulationRateSmoother`, `LinearSmoothedValue`, and positive-domain `MultiplicativeSmoothedValue` preserve exact sample counts across arbitrary blocks. The multiplicative form follows equal ratios, which suits frequency, gain, and ratio controls, rejects zero and negative bounds, and lands on the exact target without accumulated endpoint drift. Every advancement validates retained state before use. Derived overflow, underflow, or range escape settles at the finite target, while malformed state repairs to a deterministic neutral configuration. `configureSmooth` ramps delay center, modulation depth, sweep bounds, feedback, wet mix, and LFO rate across chorus, flanger, vibrato, modulated delay, and phaser. Dynamics-style channel linking remains separate.

## Filters And Crossovers

`FirstOrderTptFilter(Sample)` provides low-pass, high-pass, and all-pass processing. `StateVariableFilter(Sample)` is a second-order topology-preserving filter with low-pass, band-pass, high-pass, notch, and all-pass outputs. Configuration checks sample rate, cutoff, and Q before publishing new coefficients.

```zig
var first_order = try plug.dsp.FirstOrderTptFilter(f32).init(.{
    .kind = .high_pass,
    .sample_rate = sample_rate,
    .frequency_hz = 40.0,
});

var filter = try plug.dsp.StateVariableFilter(f32).init(.{
    .kind = .low_pass,
    .sample_rate = sample_rate,
    .frequency_hz = 1_000.0,
});
filter.process(input, output);
```

`LinkwitzRileyFilter(Sample)` splits one input into fourth-order low-pass and high-pass branches. Both branches are down 6 dB at the configured crossover frequency. `configure` can move both cascades to new coefficients over a bounded number of samples.

```zig
var crossover = try plug.dsp.LinkwitzRileyFilter(f32).init(.{
    .sample_rate = sample_rate,
    .frequency_hz = 2_000.0,
});
try crossover.process(input, low, high);
```

`LadderFilter(Sample)` is a bounded nonlinear four-stage approximation with 12 dB and 24 dB low-pass, high-pass, and band-pass modes. Its cutoff, resonance, and drive controls are checked before coefficient publication.

```zig
var ladder = try plug.dsp.LadderFilter(f32).init(.{
    .mode = .low_pass_24,
    .sample_rate = sample_rate,
    .frequency_hz = 1_000.0,
    .resonance = 0.5,
    .drive = 2.0,
});
try ladder.process(input, output);
```

These processors retain state across blocks and reject invalid configuration without changing the active setup. The ladder has its own coefficient and nonlinear-response contract. The filters do not provide multiband routing or automatic latency alignment with external paths.

## Reverb

`Reverb(Sample, maximum_delay_samples)` provides a bounded stereo feedback-delay network with four damped comb filters and two serial all-pass filters per channel. Sample rate determines the active delay lengths. Room size, damping, stereo width, and dry/wet mix can change without allocation.

```zig
var reverb = try plug.dsp.Reverb(f32, 8_192).init(.{
    .sample_rate = sample_rate,
    .room_size = 0.7,
    .damping = 0.4,
});
try reverb.process(input_left, input_right, output_left, output_right);
```

Changing to a sample rate with different delay lengths clears the tail. The processor does not provide convolution reverb, freeze mode, pre-delay, modulation, or decay-time calibration.

## Lookup And Composition

`LookupTable(Sample, point_count)` samples a function over a checked finite range whose span and derived scale are also finite. Scalar and block processing clamp inputs to that range and linearly interpolate adjacent points. Malformed retained range metadata bypasses the table without indexing its stored points.

```zig
const table = try plug.dsp.LookupTable(f32, 1_025).init(
    -1.0,
    1.0,
    transferFunction,
);
table.process(input, output);
```

`ProcessorChain(Sample, Processors)` owns a nonempty tuple of scalar processors. It applies members in tuple order and supports compile-time indexed access, bypass mutation, and bypass inspection. `ProcessorDuplicator(Sample, Processor, maximum_channels)` copies one prototype into bounded per-channel processor state.

```zig
const Chain = plug.dsp.ProcessorChain(
    f32,
    struct { Gain, Filter },
);
var chain = Chain.init(.{ gain, filter });
chain.process(input, output);
chain.setBypassed(0, true);

var channels = try plug.dsp.ProcessorDuplicator(
    f32,
    Filter,
    8,
).init(filter, 2);
try channels.processChannel(0, input_left, output_left);
```

`SharedProcessorDuplicator(Sample, State, Processor, maximum_channels)` retains independent channel histories while passing one caller-owned immutable state pointer to every `processSample` call. The state must outlive the wrapper or be replaced through `setState`.

```zig
var shared = try plug.dsp.SharedProcessorDuplicator(
    f32,
    Coefficients,
    FilterState,
    8,
).init(&coefficients, .{}, 2);
```

Chain and independent duplicator members must expose `processSample(Sample) Sample`. Shared duplicator processors accept the state pointer as a second argument. These utilities do not negotiate channel layouts, latency, reference-counted state ownership, or block-only processors.

## Audio Blocks And Process Contexts

`AudioBlock(Sample, maximum_channels)` and `ConstAudioBlock(Sample, maximum_channels)` are allocation-free views over caller-owned planar channel slices. Construction checks the channel bound and equal frame counts. Every indexing, view, arithmetic, and aggregate operation revalidates retained shape before accessing caller storage. Sub-block and channel-subset views retain aliasing with the original storage. Mutable blocks support checked copy, addition, subtraction, scaled addition, multiplication by a scalar, and replacement with the pointwise sum or product of two blocks. Const views report minimum, maximum, peak magnitude, and sum of squares.

```zig
var block = try plug.dsp.AudioBlock(f32, 8).init(channels);
var middle = try block.subBlock(frame_offset, frame_count);
try middle.multiply(0.5);
try middle.addScaled(source, 0.25);
const analysis = middle.asConst();
const peak = try analysis.peakMagnitude();
```

The caller must keep every channel slice and its sample storage alive while a block or derived view exists. Arithmetic validates shapes and finite results before mutation, so an error does not leave a partial result. `ProcessSpec` validates the preparation sample rate, maximum frame count, and channel count. `ProcessContextReplacing` aliases its input and output, while `ProcessContextNonReplacing` requires matching input and output shapes and can copy a bypass block without allocation.

These contexts are reusable DSP contracts. They are separate from the VST3 callback context in `plug.process`, and they do not own buffers, prepare processors, report latency, or synchronize shared coefficients.

## Fixed Math Primitives

`Vector(Sample, dimensions)` owns finite fixed-size storage with checked arithmetic, dot product, overflow-stable magnitude, and normalization. `Matrix(Sample, rows, columns)` provides checked addition, subtraction, and scaling, transpose, identity construction for square matrices, dimension-safe matrix and vector multiplication, and partial-pivot solving for square linear systems. `DynamicMatrix(Sample)` provides allocator-owned row-major storage for runtime dimensions. It validates checked element counts and finite values, exposes checked indexing and rows, and returns separately owned results for cloning, identity construction, addition, subtraction, scaling, transpose, rectangular multiplication, and matrix-vector multiplication. Addition, subtraction, scaling, transpose, matrix multiplication, and matrix-vector multiplication also have caller-buffer forms with explicit workspace. They permit the destination to alias an input, reject workspace overlap, prevent matrix-vector output from overwriting retained matrix values, contain overflowing address spans, and preserve the destination on validation or arithmetic failure. `Polynomial` root results initialize unused bounded complex-root capacity to zero. Allocating operations belong outside the realtime path.

Square fixed matrices can produce a reusable `LuDecomposition` that solves vectors or multiple right-hand sides and computes a determinant or inverse without repeating factorization. Matrices with at least as many rows as columns can produce a Householder `QrDecomposition`. It exposes the orthogonal and upper factors and solves full-rank least-squares systems without forming normal equations. Every fixed matrix can produce a compact one-sided Jacobi `SvdDecomposition` with `min(rows, columns)` factors. It retains sorted singular values, numerical rank, convergence state, convergence tolerance, and compact left and right factors, and provides reconstruction, condition-number reporting, pseudoinverse construction, and minimum-norm overdetermined, rank-deficient, or underdetermined least-squares solutions through the retained numerical rank. `DynamicMatrix` provides allocator-owned reusable LU, QR, and compact SVD decompositions with the corresponding runtime-sized solves, determinant, inverse, reconstruction, rank, condition-number, pseudoinverse, and minimum-norm least-squares operations. Caller-buffer matrix-vector destinations and workspaces cannot overlap matrix storage. Caller-buffer decomposition solves reject every writable destination or workspace that overlaps retained factors, reflectors, singular values, or basis vectors, preserving the reusable decomposition on failure. Fixed and dynamic LU validation derives permutation parity and requires it to match the retained determinant sign. Both LU owners plus fixed and dynamic QR retain their construction matrix scale and require the public pivot or rank tolerance to equal the exact scale-derived value. LU pivot selection and QR rank selection therefore remain invariant under finite nonzero scaling instead of rejecting well-conditioned tiny systems against an absolute machine-epsilon cutoff. Dynamic SVD uses relative convergence and rank thresholds and is covered by the same extreme-scale solve fixture as dynamic LU and QR. Fixed and dynamic QR validation also verifies the mathematical relation between each retained Householder scalar and its complete reflector tail before any factor or solve operation. Fixed and dynamic SVD validation recomputes every retained basis-column magnitude with overflow-stable accumulation, requires normalized or zero columns according to the retained shape and numerical rank, and verifies pairwise orthogonality for every rotation-derived basis column plus every result-bearing normalized column. Both SVD owners retain the configured maximum sweep count, reject zero or out-of-range completed counts, and require a nonconverged result to have exhausted that exact budget. Dynamic factorization and allocating convenience operations belong outside the realtime path. SVD initialization validates the complete result before transferring tall-factor ownership into a wide decomposition. Every dynamic owner supports repeated teardown, rejects later operations, and checks retained shape products before indexing. Invalid shapes, tolerances, sweep exhaustion, corrupted retained state, and allocation failure return errors without leaking partial ownership.

`Polynomial(Sample, capacity)` stores coefficients from the constant term upward and provides bounded evaluation, derivative, integral, addition, subtraction, multiplication, composition, quotient and remainder division, interpolation, least-squares fitting, standard orthogonal-family construction, and allocation-free complex root solving. `coefficient_capacity` and `maximum_degree` expose the selected type bounds. Root results expose `valid` and return an empty slice when their public retained count is malformed. `legendre`, `chebyshevFirstKind`, and `chebyshevSecondKind` construct their degree-bounded families through checked three-term recurrences. `hermitePhysicists` and `hermiteProbabilists` name both common Hermite normalizations explicitly. `laguerre` selects the ordinary family, while `generalizedLaguerre` accepts a finite alpha greater than -1. `jacobi` accepts finite alpha and beta values greater than -1 and includes Legendre when both are zero. Every family rejects capacity overflow and non-finite recurrence results. Interpolation converts a checked distinct point set through divided differences. `fitLeastSquares` builds a fixed Vandermonde design and uses QR for full-rank fits. `fitLeastSquaresMinimumNorm` uses SVD when repeated or linearly dependent sample locations require a rank-aware minimum-norm coefficient vector.

`findRoots` trims trailing zero coefficients, solves linear polynomials directly, and uses simultaneous Durand-Kerner refinement for higher degrees. The default relative correction tolerance is `1e-5` for `f32` and `1e-12` for `f64`; the default limit is 256 iterations. The polynomial type exposes these values as `default_root_tolerance` and `default_root_maximum_iterations`. Exhausting the limit returns the deterministic real-then-imaginary ordered candidates with `converged` clear, while invalid options, indeterminate all-zero input, or a stalled non-finite iteration return errors.

```zig
const M = plug.dsp.Matrix(f32, 2, 2);
const transformed = try matrix.multiply(2, M.identity());
const decomposition = try matrix.decompose();
const solution = try decomposition.solve(right_hand_side);
const inverse = try decomposition.inverse();

const curve = try plug.dsp.Polynomial(f32, 4).init(
    &.{ 1.0, 2.0, 3.0 },
);
const value = curve.evaluate(0.5);
const roots = try curve.findRoots(.{});
if (!roots.converged) return error.PolynomialDidNotConverge;
```

The fixed math types reject non-finite construction and arithmetic results. Their dimensions, fit point counts, degrees, and storage capacities remain compile-time bounds. Capacity-bearing type constructors require an explicit bound and have no hidden default. Select bounds from the product's prepared block, channel, delay, coefficient, or point limits because each bound contributes directly to the generated type's inline storage. Runtime-sized matrix decompositions remain outside this layer.

Algorithm limits that constrain valid public configuration or caller storage are exported from `plug.dsp`. These include Butterworth sections, least-squares and equiripple FIR sizes, polyphase all-pass sections, multiband bands and linked channels, PCM dither channels, Ogg page storage, fixed-rate conversion ratio, MP3 free-format frame size, and resampler rate correction. Internal staging counts remain module implementation details.

## Fast Math

`FastMathApproximations(Sample)` provides limited-range Padé approximations for `cosh`, `sinh`, `tanh`, `cos`, `sin`, `tan`, `exp`, and `log(1 + x)`. The hyperbolic range is `[-5, 5]`, sine and cosine use `[-pi, pi]`, tangent uses the open interval around `[-pi / 2, pi / 2]`, exponential uses `[-6, 4]`, and `logOnePlus` uses `[-0.8, 5]`.

```zig
const FastMath = plug.dsp.FastMathApproximations(f32);
const sine = try FastMath.sin(phase);
try FastMath.applyNative(.exponential, samples);
```

Scalar calls reject non-finite or out-of-range inputs. `apply`, `applyVector`, and `applyNative` validate the complete slice before replacing any value. `applyVector` accepts a compile-time width and handles its scalar tail. `applyNative` selects the compile target's native width. `KernelDispatcher.applyFastMath` selects the detected runtime backend.

## SIMD Registers

`SimdRegister(Sample, lane_count)` wraps Zig fixed-lane vectors for f32 or f64 arithmetic. It supports splat, unaligned slice load and store, addition, subtraction, multiplication, division, multiply-add, minimum, maximum, absolute value, square root, comparisons, mask selection, checked lane access, horizontal sum, and dot product.

```zig
const Simd = plug.dsp.SimdRegister(f32, 4);
const left = try Simd.load(left_samples);
const right = try Simd.load(right_samples);
const mixed = try left.multiplyAdd(gain, right);
try mixed.store(output_samples);
```

Loads reject non-finite values, stores validate the destination before mutation, and arithmetic rejects non-finite results, zero divisors, and negative square roots. `NativeSimdRegister` selects the compile target's AVX2, baseline x86-64, NEON, or scalar width. `ComplexSimdRegister` provides split-real complex arithmetic plus aligned and unaligned plane access. Complex stores require disjoint destination prefixes and validate both planes before mutation. `KernelDispatcher` detects the strongest available native backend and dispatches transactional copy, gain, affine, add, real and split-complex pointwise multiply, all eight fast-math operations, weighted two-buffer mixing, sum, inner product, absolute peak, minimum, maximum, sum-of-squares, and RMS with scalar tail handling. Minimum and maximum require at least one sample. Other reductions return zero for empty input. Sum-of-squares rejects overflow, while RMS scales by the absolute peak before accumulating normalized energy so finite maximum-magnitude input remains representable. Each operation completes one full validation pass before mutation or result publication, then uses direct unaligned vectors without repeating checked-register validation inside the hot loop. Exact corresponding aliases are valid for copy, add, real and complex multiply, and mixing. Copy becomes a validated no-op, add doubles the destination, real multiply squares it, and paired complex aliases square the complex input. Shifted and cross-plane overlaps are rejected before mutation. The dispatcher also converts stereo planar and interleaved layouts in backend-width blocks. Layout conversion rejects shape, non-finite input, and any writable-buffer overlap before mutation.

`BufferProcessorDispatcher(Sample, Context)` applies the same runtime backend selection to product-supplied one-input, one-output processor callbacks. A scalar callback is required, while NEON and AVX2 callbacks are optional. Detection selects the strongest supplied callback and falls back to scalar when the machine supports a backend that the processor does not implement. Forced selection supports deterministic tests and controlled environments. The dispatcher validates equal lengths and rejects shifted overlap before invoking the callback. Exact in-place replacement, arbitrary alignment, empty buffers, and scalar tails are part of the callback contract.

`Phase(Sample)` stores radians in the half-open range from zero through `2 * pi`. `advance` returns the current value, accepts only a finite nonnegative increment, and wraps the next value. `besselI0` exposes the finite-contained modified Bessel function used by Kaiser windows. `ellipticIntegralK` computes the complete elliptic integral for a checked real modulus and its complementary modulus through arithmetic-geometric mean iteration. `ellipticIntegralF` computes the real incomplete integral of the first kind for parameter `m` through Carlson's symmetric integral.

```zig
var phase = try plug.dsp.Phase(f32).init(0.0);
const current = try phase.advance(increment_radians);
const kaiser_denominator = plug.dsp.besselI0(beta);
const elliptic = try plug.dsp.ellipticIntegralK(modulus);
```

`jacobiElliptic` computes checked real `sn`, `cn`, `dn`, and the principal amplitude. `jacobiEllipticFunction` selects any of the twelve standard functions through `JacobiFunction`: the three primary functions plus `ns`, `nc`, `nd`, `sc`, `sd`, `cs`, `cd`, `ds`, and `dc`. Reciprocal and quotient evaluation reports `error.JacobiPole` when its denominator is numerically indistinguishable from zero. Parameter-based paths start the arithmetic-geometric mean from `sqrt(1 - m)` instead of reconstructing a modulus, so the largest representable parameter below one retains its finite quarter period. Bounded modulo reduction contains maximum finite arguments without an overflowing period multiply. `inverseJacobiSn`, `inverseJacobiCn`, and `inverseJacobiDn` cover their principal real branches on `[-K, K]`, `[0, 2K]`, and `[0, K]`. The corresponding `*Branch` functions accept `JacobiInverseBranch` and return periodic or reflected roots. At `m = 1`, they reject nonexistent periodic roots while retaining the real reflected roots of the even `cn` and `dn` limits. Dense round trips include parameters through `0.99`, both precisions at the closest representable value below one, forced endpoints, degenerate parameter-zero behavior, and the narrower parameter-one domains.

`complexJacobiElliptic` accepts `std.math.complex.Complex(f32)` or `Complex(f64)` and a real parameter `m` from zero through one. It returns checked complex `sn`, `cn`, and `dn`. `complexJacobiEllipticFunction` evaluates the same twelve-function selector for complex arguments according to the [DLMF quotient definitions](https://dlmf.nist.gov/22.2). `complexJacobiCd` remains as the direct `cn / dn` convenience entry point, and `inverseComplexJacobiSn` returns the principal complex argument. Endpoint formulas use complex sine or hyperbolic functions. Generic forward evaluation combines the real AGM solutions through [Jacobi's imaginary transformation](https://dlmf.nist.gov/22.6) and [addition theorem](https://dlmf.nist.gov/22.8), while the inverse uses a convergent descending-modulus transform. Non-finite arguments, non-finite results, and numerically unresolved pole or branch neighborhoods return errors.

`complexParameterJacobiElliptic` also accepts a complex parameter. It follows the defining `sn`, `cn`, and `dn` differential system from zero along the straight segment to the requested argument. Step doubling, fifth-order extrapolation, checked identities, a maximum 16,384-step refinement grid, and fewer than 32,768 total Runge-Kutta steps make accuracy and worst-case work explicit. A real parameter from zero through one delegates exactly to `complexJacobiElliptic`. Non-finite input, a pole on the continuation path, non-finite intermediate state, or exhausted refinement returns an error. `complexParameterJacobiEllipticFunction` applies the same twelve-function selector and checked pole contract to the result.

This module uses raw arguments and the parameter `m = k * k`. For references expressed in quarter-period units with modulus `k`, multiply forward units by `K(k)` or divide the returned inverse by `K(k)`.

## Envelopes, Gain, And Ramping

`BallisticsFilter(Sample)` tracks peak or RMS magnitude with independent attack and release times. Zero-millisecond times follow the detector immediately. RMS reset rejects a finite magnitude whose squared envelope cannot be represented and leaves the prior envelope unchanged.

```zig
var envelope = try plug.dsp.BallisticsFilter(f32).init(.{
    .sample_rate = sample_rate,
    .attack_ms = 5.0,
    .release_ms = 100.0,
    .mode = .rms,
});
const level = envelope.processSample(input);
```

`Gain(Sample)` applies nonnegative linear gain with an optional sample-counted linear ramp. `setDecibels` accepts values from -160 dB through 36 dB. A malformed retained step that would leave the supported gain range settles at the finite target before processing. `Bias(Sample)` adds a checked finite offset.

`LogRampedValue(Sample)` interpolates strictly positive values geometrically. `setTarget` defines the exact ramp length. `next` advances one sample, while `skip` advances a bounded group without looping. If hostile retained arithmetic would overflow or underflow, the ramp settles at its finite target and returns to a valid inactive state.

```zig
var frequency = try plug.dsp.LogRampedValue(f32).init(100.0);
try frequency.setTarget(6_400.0, 512);
const next_frequency = frequency.next();
```

These utilities retain state across blocks. They do not derive ramp lengths from wall-clock time or share state across plugin instances.

## Oscillator

`Oscillator(f32)` and `Oscillator(f64)` generate sine, triangle, saw, or square waveforms without allocation. Configuration rejects non-finite rates, frequencies above Nyquist, and sample rates below 1 kHz. Phase is retained across output blocks.

```zig
var oscillator = try plug.dsp.Oscillator(f32).init(
    sample_rate,
    440.0,
    .sine,
);
oscillator.process(output);
```

The triangle, saw, and square forms are direct waveforms without band limiting. Use oversampling or a band-limited source when alias rejection matters.

## Delay And Panning

`DelayLine(Sample, capacity)` owns fixed inline storage and retains its write position across blocks. Linear interpolation supports delays from one through `capacity - 1` samples. Four-point cubic interpolation supports one through `capacity - 2` samples.

```zig
var delay = plug.dsp.DelayLine(f32, 96_000){};
try delay.process(
    input,
    output,
    delay_samples,
    .cubic,
);
```

`RealtimeSnapshotPublisher(State)` provides fixed-storage mutable-state publication for one non-realtime writer and one realtime reader. Three inline slots and reader pinning prevent the writer from changing the slot being copied. `tryRead` performs one bounded nonblocking attempt, so the audio thread can retain its previous snapshot when publication races a block boundary. Publication skips generation zero and every generation still represented by an inline slot, including after counter rollover or malformed retained counter state. State containing pointers still requires the pointed-to storage to outlive every published snapshot.

`RealtimeReferencePublisher(State, slot_count)` provides retained immutable generations for one non-realtime writer and multiple realtime readers. It owns three through 64 inline slots. `tryAcquire` performs one bounded atomic attempt and returns a handle that pins its generation until `release`. `retain` makes another independently released handle. `release` uses a generation-checked atomic decrement, so concurrently releasing malformed raw copies cannot underflow the slot count or terminate the process. Raw copies do not create references and remain invalid ownership practice; use `retain` for every independently released handle. `beginPublish` reserves a non-active unreferenced slot and returns a control-thread writer whose `value` pointer can be filled in place. `beginUpdate` reserves a slot, pins the active generation, copies it into the reservation, and returns the same writer for partial mutation. It makes at most `slot_count` bounded acquisition attempts and releases the reservation if the snapshot cannot be acquired. `commit` atomically publishes the complete generation, while `cancel` releases the reservation without changing the active generation. The convenience `publish` path uses the same reservation internally. Publication fails with `RealtimeReferenceUnavailable` instead of waiting when every reusable slot is pinned. Generation allocation skips zero and every generation still represented by an inline slot, including across `u64` rollover. A stale copied handle therefore cannot become valid again when its former slot is reused. State containing pointers still requires the pointed-to storage to remain valid for every retained generation.

```zig
var writer = try publisher.beginUpdate();
defer writer.cancel();
const pending = writer.value() orelse
    return error.InvalidRealtimeReferenceWriter;
pending.gain = 0.25;
_ = try writer.commit();
```

The publisher must remain at a stable address while handles or a writer reservation exist. Handles follow manual move semantics: do not bit-copy a handle as a substitute for `retain`, and release every successful acquisition or retention exactly once. A writer must be committed or cancelled exactly once; both operations make later cancellation harmless. The publisher retains inline state, not storage reached through pointers inside that state. Such pointed-to storage must remain alive independently. Publication is single-writer; acquisition, retention, dereference, and release support concurrent readers.

`NativeSimdRegister(Sample)` selects the compile target's AVX2, baseline x86-64, NEON, or scalar width. Fixed-width `SimdRegister` remains available when serialized layouts or algorithms require a particular lane count. Both expose checked aligned and unaligned loads and stores. `ComplexSimdRegister` adds split-real complex addition, subtraction, multiplication, conjugation, squared magnitude, and checked aligned or unaligned plane storage. `KernelDispatcher` detects native AVX2 or NEON support and dispatches transactional copy, gain, affine, add, real and split-complex pointwise multiply, Padé fast math, weighted mix processing, sum, inner product, absolute peak, minimum, maximum, sum-of-squares, and overflow-stable RMS to the matching vector width with scalar tail handling. Complex multiplication supports exact paired in-place buffers while rejecting shifted and cross-plane overlap. Stereo interleave and deinterleave operations use the same runtime-selected block width and require disjoint writable and source storage.

Delay changes take effect immediately. Smooth a user-controlled delay before passing it to `process` when discontinuities are not intentional.

`StereoPanner(f32)` and `StereoPanner(f64)` map mono input to stereo. Pan positions run from `-1.0` for left through `1.0` for right. The panner supports the same eight linear, balanced, sine, and square-root laws as `DryWetMixer`; equal-power is the default.

```zig
const panner = try plug.dsp.StereoPanner(f32).init(0.0);
try panner.process(mono, left, right);

var linear = try plug.dsp.StereoPanner(f32).initWithRule(0.0, .linear);
```

## Dynamics

`Compressor(f32)` and `Compressor(f64)` apply a peak-envelope compressor with configurable threshold, ratio, attack, release, and makeup gain. Configuration is validated before publication, including the derived attack and release coefficients. Finite but unrepresentable sample-rate and duration products are rejected rather than constructing an envelope that cannot advance. Non-finite samples become silence, and malformed public state causes a safe unity-gain reset. Output arithmetic is checked in the processor's sample precision. Linked frames validate every channel before mutation and become silent as a unit when makeup gain would overflow.

```zig
var compressor = try plug.dsp.Compressor(f32).init(.{
    .sample_rate = sample_rate,
    .threshold_db = -18.0,
    .ratio = 4.0,
    .attack_ms = 10.0,
    .release_ms = 100.0,
});
compressor.process(samples);
```

`LookaheadLimiter(Sample, maximum_lookahead_samples)` delays the signal by an exact, configured number of samples and derives gain from the complete lookahead window. `LookaheadCompressor(Sample, maximum_lookahead_samples)` applies the complete threshold, ratio, attack, release, and makeup curve to an exactly delayed signal while its detector observes future samples. Storage is inline and bounded. Retained cursor progression and the next delayed output are validated without scanning the compressor's complete buffer. The limiter rejects non-finite retained samples as part of its existing peak scan. Malformed delay state resets before it can publish a non-finite output. `latencySamples` reports the delay that the plugin must publish to its host, or zero when retained configuration and latency metadata disagree.

`InterSampleLimiter(Sample, maximum_frames, factor)` performs fixed-capacity oversampling, high-rate peak limiting with a configurable reconstruction guard, and a final sample-peak safety stage. The oversampling factor is a compile-time 2x, 4x, 8x, or 16x choice. `process` is transactional when a block exceeds its declared capacity.

`TwoBandCompressor(Sample)` splits the signal through a fourth-order Linkwitz-Riley crossover and applies independently configured compressors to the low and high bands. `MultibandCompressor(Sample, band_count)` expands the same contract to two through eight compile-time bands. Its ordered crossover tree applies the later Linkwitz-Riley all-pass responses to earlier bands, preserving unity recombination magnitude while retaining independent compressor state and gain-reduction reporting for every band. `LinkedMultibandCompressor(Sample, band_count, channel_count)` retains independent crossover history for as many as 16 channels while using one peak detector and identical gain for every channel in each band. This preserves stereo and surround image relationships without leaking audio between channels. Configuration changes validate and prepare the complete crossover, phase-compensation, and compressor graph before replacing active state.

The ReleaseFast benchmark covers representative setup and processing costs for the advanced filter designers, lookahead and 4x inter-sample limiting, four-band compression, and realtime snapshot publication with and without a concurrent reader. These budgets are regression limits, not claims about every target. Fixed external or independent vectors cover lookahead gain behavior, sinc-reconstructed inter-sample containment, and three-band Linkwitz-Riley recombination.

The base compressor's `gainReductionDb` returns its current non-positive gain reduction. It has no knee or sidechain filter. Lookahead and shared-detector channel-linking policies are provided by the dedicated wrappers above.

`NoiseGate(Sample)` uses the same checked peak-envelope model as a downward expander below its threshold. `Limiter(Sample)` applies instantaneous gain reduction and a configurable release to keep individual samples at or below its threshold. Their configurations also reject derived coefficients that round to a non-advancing value. This derived check retains supported multi-megahertz high-rate limiting, including the maximum 192 kHz by 16x inter-sample path. The basic limiter has no lookahead, oversampling, inter-sample peak detection, or channel-linking policy.

## Partitioned Convolution

`PartitionedConvolver(maximum_frames, partition_size)` is the same fixed-capacity convolution engine used by the IR Loader. It stages mono or stereo `f32` impulse responses outside processing, precomputes their spectra, and lets the audio callback adopt only a complete generation. Pending adoption, active access, and sample-rate reprepare validate the retained metadata, received extent, prepared extent, partition count, and prepared rate before using a slot. A malformed pending generation is released without replacing valid active audio. The quiescent `valid` query additionally covers slot ownership, staged and prepared content, processing phase, finite spectra and histories, and live cursors. Realtime processing performs constant-time shape checks per sample and validates the complete active filter and processing history at FFT block boundaries. Malformed retained state returns silence without advancing the processing phase. When source and processing rates differ, preparation uses the bounded 32-tap, 256-phase Blackman-windowed sinc converter and preserves each channel's coefficient sum within destination precision. This prevents sample-rate conversion from changing the response's DC gain. `ConvolutionOptions` selects partitioned or zero-latency processing and independent-stereo or mono routing. Zero-latency mode processes the first partition directly and keeps the remaining impulse response in the FFT tail. Mono routing averages the input channels, uses the first impulse-response channel, and writes the same result to both outputs.

The partition size must be a power of two of at least eight samples. `latencySamples` reports that size in partitioned mode and zero in zero-latency mode. Each instance owns three impulse-response slots, the direct-head history, and all transform history inline, so memory use grows with both template arguments. Import, resampling, `commit`, and option changes belong outside the audio callback. `adoptPending`, `processFrame`, and `resetProcessing` are the processing-side operations.

`ConvolutionPreparationQueue(maximum_frames, queue_capacity)` owns a bounded SPSC queue of complete mono or stereo impulse-response jobs. One producer submits validated generations while one consumer prepares them through `PartitionedConvolver`. Consumer operations revalidate ready metadata before changing a slot or cursor, so malformed retained jobs remain available after a checked failure and can be repaired or discarded. The quiescent `valid` query covers cursor bounds, contiguous ring occupancy, slot state, metadata, finite active samples, and serial generation order. A busy convolver also leaves the front job ready for retry. The consumer can explicitly discard a job that cannot become current. The queue does not create or own a thread; the product chooses its worker or message-loop policy.

## Headless fixture parity

`BlockProcessor(Sample)` is a type-erased mono processing interface for deterministic tests outside a plugin host. A processor supplies public `reset` and `processBlock` methods. They must be public because the framework instantiates the generic from a different module. The fixture runner can render the same input using fixed or deterministically randomized block boundaries.

```zig
var model = Model{};
const processor = plug.dsp.BlockProcessor(f32).init(Model, &model);

try plug.dsp.fixture_runner.renderFixed(
    f32,
    processor,
    input,
    output,
    64,
);
```

`fixture_runner.compare` reports maximum absolute error, maximum relative error, and RMS error. A sample satisfies the pointwise limit when either its absolute error is within the near-zero bound or its relative error is within the scale-dependent bound. The complete render must also satisfy the RMS limit. Set `relative_floor` explicitly when a workload needs a denominator floor other than the default.

## Audio File Writing

`requiredWavBytes` computes the exact RIFF size for a checked `WavSpec`. `writeInterleavedWav` writes PCM16, PCM24, PCM32, or IEEE f32 samples into caller-owned byte storage. `WavWriter` appends complete interleaved frames to fixed caller storage and keeps the RIFF and data sizes current after each successful append. Odd PCM24 payloads carry the required RIFF pad byte without including it in the data chunk size, and a later append replaces that padding before extending the audio. Input may be `f32` or `f64`.

```zig
const spec = plug.dsp.WavSpec{
    .sample_rate = 48_000,
    .channel_count = 2,
    .encoding = .pcm_i16,
};
const required = try plug.dsp.requiredWavBytes(spec, frame_count);
if (wav_storage.len < required) return error.InsufficientWavStorage;
const wav = try plug.dsp.writeInterleavedWav(
    f32,
    wav_storage,
    interleaved_samples,
    spec,
);

var writer = try plug.dsp.WavWriter.init(wav_storage, spec);
try writer.append(f32, first_interleaved_block);
try writer.append(f32, second_interleaved_block);
const streamed_wav = writer.bytes();
```

Both paths validate the complete specification, sample shape, finite input, size arithmetic, and destination capacity before changing encoded data. A failed append preserves the previous valid file and counters. PCM output clamps to the normalized range. The in-memory WAV and AIFF writers return an empty byte view if their public retained counters no longer describe a complete file inside caller storage.

`PcmDither` provides deterministic, allocation-free signed PCM quantization from 2 through 32 bits across as many as 64 channels. Modes include direct rounding, TPDF dither at one quantization step in each direction, and first-order noise-shaped TPDF with a checked feedback coefficient. Each channel has an independent seeded sequence and error history. `validate` checks the public configuration and active error history, while count and bit-depth accessors fail closed for malformed retained state. Quantization clamps every finite sample before scaling, including finite values outside the normalized range. `reset` reproduces the original sequence exactly. Caller-buffer WAV and AIFF support 16-, 24-, and 32-bit dithered output. `WavFileWriter`, `AiffFileWriter`, `Rf64FileWriter`, and `Wave64FileWriter` expose `appendDithered` for their integer PCM encodings. One internal codec supplies signed PCM16, PCM24, PCM32, and IEEE f32 byte conversion, normalized decoding, bit and byte widths, little- and big-endian handling, and fixed 4 KiB positional-write staging to every PCM container and the bounded reader. A shared checked checkpoint restores either an exact committed length or an aligned payload boundary with canonical zero padding. It rejects inconsistent committed state before file mutation. Dithered staging preserves interleaved channel phase across chunk boundaries. Format, channel, bit-depth, finite-sample, retained-state, and capacity checks finish before dither state advances. A failed audio write restores the last committed file length, prior padding, and caller dither state when truncation succeeds. If truncation also fails, the writer remains recoverable but rejects further appends until `recover` succeeds.

`WavFileWriter` writes the same classic RIFF formats directly to a caller-owned `std.Io.File`. It truncates and initializes the file, streams samples through fixed staging storage, keeps the header current after each successful append, and provides `finalize` for header recovery, exact truncation, and durable sync. The caller retains responsibility for closing the file. All four PCM container writers also expose `initWithOperations`. `FileWriterOperations` supplies positional-write, length, and sync callbacks for deterministic fault injection or another file implementation. Positional callbacks report the bytes written; the framework retries short writes and rejects zero progress or counts larger than the supplied slice. `FileWriterCheckpoint` exposes the validated exact or aligned committed-boundary primitive used by the file-backed writers. Header, padding, audio, dithered staging, rollback, recovery, and final synchronization use the same operations after initialization. Focused failure coverage includes partial audio writes over an existing pad byte, truncation failure, header failure after committed audio, short writes, final sync failure, recovery, and dither rollback.

PCM container readers, FLAC, Ogg, and MP3 share one internal exact positional-read primitive. It rejects an overflowing `offset + length` before entering the file API, and each format maps a short read to its established truncation error. Container boundary discovery, buffered scanning, append transactions, and recovery remain format-specific.

`requiredAiffBytes` and `writeInterleavedAiff` provide the same caller-storage model for big-endian PCM16, PCM24, and PCM32 AIFF data. `AiffWriter` appends complete interleaved frames and keeps the FORM, COMM, and SSND sizes current. It overwrites prior padding when odd-sized PCM24 data grows. Both paths emit an integer extended-precision sample rate and validate the complete request before changing encoded data.

```zig
const spec = plug.dsp.AiffSpec{
    .sample_rate = 48_000,
    .channel_count = 2,
    .encoding = .pcm_i24,
};
const aiff = try plug.dsp.writeInterleavedAiff(
    f32,
    aiff_storage,
    interleaved_samples,
    spec,
);

var writer = try plug.dsp.AiffWriter.init(aiff_storage, spec);
try writer.append(f32, first_interleaved_block);
try writer.append(f32, second_interleaved_block);
```

`AiffFileWriter` provides the same file-backed lifecycle for PCM16, PCM24, and PCM32 AIFF output. It handles the transition between odd-sized padded PCM24 data and a later append without leaving padding inside the sound data.

`AudioMetadataEntry` represents a borrowed FourCC and byte string. `encodeRiffInfoMetadata` and `encodeAiffTextMetadata` write complete metadata chunks into caller storage, while their iterators validate and expose both known and unknown FourCC entries without allocation. The encoded output prefix must not overlap the entry descriptors or any borrowed value. Alias rejection leaves the destination unchanged. Both iterator kinds expose `valid`, revalidate the complete retained payload, and accept only cursors at exact entry boundaries. Rejection does not change the cursor. `WavFileWriter`, `AiffFileWriter`, and `Rf64FileWriter` accept these tags through `initWithMetadata`. Metadata values need to remain valid only for that initialization call.

`BroadcastExtension` implements the complete 602-byte Broadcast Audio Extension defined by [EBU Tech 3285](https://tech.ebu.ch/publications/tech3285). Its version-aware contract covers fixed ASCII fields, typed calendar date and time, the 64-bit sample time reference, 64-byte UMID, version-2 loudness values and unused-value sentinels, zeroed reserved storage, and CR/LF-terminated coding history. Encoding rejects output overlap with every borrowed text field before clearing the destination. `BroadcastMetadataView` validates a complete borrowed `bext` chunk without allocation. Invalid loudness values from external files are ignored as required by the specification, while invalid structure, reserved bytes, text padding, dates, times, versions, and chunk padding are rejected.

`RiffXmlKind`, `encodeRiffXmlMetadata`, and `RiffXmlView` frame borrowed UTF-8 iXML and aXML documents. They validate UTF-8, NUL exclusion, the XML envelope, RIFF sizes, word padding, and source/output separation before mutation. `IxmlMetadata` adds allocation-free encoding and caller-storage parsing for production-recorder fields, take flags, file identity, notes, speed and timecode-rate data, sync points, file-set identity, track lists, derivation history, loudness, portable BEXT data, location data, and user data. Ratios retain exact integer numerators and denominators. Sample rates, bit depth, split timestamps, drop-frame flags, relative and absolute sample positions, event durations, file-set grouping, and file-set start times are typed. `IxmlLoudness` carries the five EBU R 128 values in either the native `LOUDNESS` object or the redundant BEXT form. `IxmlLocation` validates finite latitude and longitude ranges plus finite altitude. `IxmlUser` supports legacy human-readable text or the standardized iXML 2.0 AFSI production, mixer, and recorder fields, but rejects an ambiguous mixture during encoding. Every field is optional. Parsing accepts arbitrary field order, XML declarations, numeric and named entities, and structurally nested unknown extension subtrees, which it ignores. It rejects duplicate known fields, mismatched tags, zero-denominator ratios, non-finite values, invalid GPS coordinates, invalid Unicode, inconsistent list counts, insufficient storage, and input/output overlap before mutation. The decoded-text materialization pass and exact-ratio formatting pass propagate any disagreement with their preflight instead of treating it as unreachable. CDATA, DTD, and untyped vendor extension values remain outside the typed view. When an iXML BEXT object and an official Wave `bext` chunk coexist, the caller must keep their redundant values equal.

`AdmIdentifier` parses every core ID family defined by ITU-R BS.2076-3: programme, content, object, pack, channel, stream, track format, track UID, alternative value set, and block format. It accepts hexadecimal case differences, provides case-insensitive identity, exposes format type labels and definition indexes, and distinguishes externally supplied common definitions from custom definitions that require local metadata. `AdmChannelAllocation` and `AdmChannelAllocationView` encode and parse the fixed-layout `chna` chunk defined by ITU-R BS.2088-2. They validate track indexes, exact UID and reference shapes, direct audio-channel references, optional pack references, duplicate UIDs, complete track coverage, zeroed reserved entries, and the padding byte without allocation. Encoding rejects output that overlaps the entry descriptors or any UID, track, or pack reference before mutation. Reserved entry capacity supports later metadata growth. WAV, RF64, and BW64 writers reject a `chna` track count that disagrees with the audio channel count before mutating the file.

`AdmXmlDocument` adds an allocation-free typed graph over a bounded XML scanner. It recognizes all core declaration families inside one `audioFormatExtended` subtree and exposes declaration and reference iterators. Validation rejects duplicate IDs, wrong reference kinds, unresolved custom definitions, invalid owners, self-references, incompatible type labels, broken stream/track reciprocity, invalid identifier continuity, and excess or mutually exclusive references. Common format definitions may resolve outside the document. The XML scanner resolves scoped default and prefixed namespace declarations, validates namespace URI references through 2,048 decoded bytes and reserved bindings, compares entity-normalized namespace names, and rejects undeclared prefixes or duplicate expanded attributes. Attribute iteration revalidates its complete retained source and accepts only exact attribute boundaries. Event iteration reconstructs its retained prefix and accepts only an exact event boundary with the matching open-element stack and borrowed ranges. Attribute and event iteration commit cursor and nested state only after a complete parse step succeeds. Ordinary escaped text and CDATA sections share one bounded typed-text path. CDATA remains literal while entity references in ordinary text decode normally, including when the two forms are adjacent. DTD declarations remain explicitly unsupported. The typed graph matches elements against the expanded namespace of `audioFormatExtended`. It omits complete foreign-vocabulary subtrees, so nested elements cannot impersonate metadata fields. Attributes are matched by exact qualified name, so a foreign namespace cannot satisfy a required unqualified field.

`AdmXmlExtensionIterator` returns each outermost foreign-vocabulary subtree inside `audioFormatExtended` without allocation. Each item exposes its decoded namespace URI, qualified and local names, root attributes, exact source bytes and offset, immediate typed parent, and nearest declaration owner. Nested markup, comments, processing instructions, entity spelling, and typed-looking descendants remain byte-for-byte intact. `AdmXmlExtensionAttributeIterator` returns foreign-prefixed attributes attached to typed elements with their decoded namespace URI, exact source spelling, encoded value, typed element, and declaration owner. Callers can decode an attribute value into their own buffer. Extension namespace aliases are compared by decoded URI identity.

`AdmXmlUntypedElementIterator` separately returns each outermost subtree whose namespace matches `audioFormatExtended` but whose local name is outside the supported typed vocabulary. It preserves the same exact source and ownership information as a foreign extension. `AdmXmlUntypedAttributeIterator` returns prefixed attributes bound to the metadata namespace on typed elements. XML default namespaces do not apply to unprefixed attributes, so those remain under each typed validator's element-specific attribute rules. `untyped_element_count` and `untyped_attribute_count` allow a caller to inspect compatibility before consuming typed views. `validateTypedVocabulary` provides an opt-in strict policy without changing the existing profile-specific validation errors.

Every public ADM iterator checkpoints its nested scanner, ownership, counters, and inline decoded storage before advancing. A rejected item restores that complete state, while slices from successful calls continue to refer to the iterator's own storage until the next call.

`AdmXmlProfileIterator` exposes each profile's required name, version, level, and document-reference text. It accepts multiple profiles in one direct `profileList`, but rejects multiple lists, empty lists, missing or empty values, nested profile content, and misplaced lists or profiles. Profile, tag, target, tag-group, and block iteration use overflow-safe retained depth and count checks. A corrupted public iterator reports an error and preserves its cursor and retained state. It validates the generic BS.2076-3 profile declaration contract.

The BS.2168 emission validators apply the declared level's element and direct sub-element limits, identifier rules, content reachability, and two-level object ownership. Object-source validation requires leaf objects to select one permitted local Objects or common DirectSpeakers pack and branching objects to omit pack and track references. A nested object must select a local Objects pack. Every local Objects pack, local channel, and track UID must participate in the required graph. Track UIDs cover each channel in the selected pack exactly once, refer back to that pack, and cannot select the silent UID. The common pack registry covers the polar and Cartesian layouts permitted by the profile and applies the level-specific 12- or 24-channel limit.

`validateEmissionProfileMatrices` validates downmix side information after object-source validation. Each local Matrix pack has one distinct common DirectSpeakers input and output layout, one through 24 local Matrix channels, and a unique input/output pair. The input layout must be used by an object, while Matrix packs and channels cannot serve as object or track sources. Output layouts exclude the common configurations without an LFE channel. Each Matrix channel has one block and a unique output channel from the selected output layout. Coefficients identify distinct channels from the input layout, accept only constant gain and gain-unit attributes, and remain within `-inf` through 20 dB or zero through 10 linear. The profile path requires the current output-reference name and rejects extra Matrix pack, channel, block, matrix, and coefficient structure.

`validateEmissionProfileComplementaryObjects` validates mutually exclusive top-level object groups. A group member belongs to one group, cannot own another group, and uses the same source pack type as the root. Each programme includes every member, exactly one member, or none. Derived level limits count one independent group per complementary set and use the maximum direct or nested track count among its alternatives. Non-complementary top-level objects contribute their complete direct or nested track counts.

`validateEmissionProfileObjectParameters` validates the profile subset for object interaction controls. Every object has a bounded name and explicit `interact` flag. Interaction metadata is limited to gain and azimuth or Cartesian-X ranges with the required minimum and maximum bounds. Object and alternative-value-set gains cannot exceed 21 dB or their interaction range. Position offsets cannot exceed the profile or interaction range and require a local Objects source whose blocks stay at the neutral position. Alternative interaction metadata retains the parent ranges while allowing different gain and position interaction flags. Nested objects cannot carry these controls.

`validateEmissionProfileComplementaryParameters` requires every member of a complementary group to use identical interaction flags and metadata, gain, and position offsets. Programme alternative-value-set references must belong to included top-level objects and select at most one set per object. A programme that includes an entire complementary group either references no alternative sets for that group or one semantically identical set for every member. Fixed single-member selections may reference that member's set independently.

`validateEmissionProfileProgrammeContentMetadata` validates the profile's programme and content metadata after the complementary-parameter checks. Programme and content names contain one through 64 Unicode scalar values. Required language attributes and label languages must be registered ISO 639-2 codes, including bibliographic and terminology aliases and the reserved private-use range. Labels carry no extra attributes and use each language at most once per owner. Every programme and content has exactly one attribute-free loudness block containing one or both finite integrated and dialogue loudness values. Every content has exactly one dialogue element whose required kind attribute and enumerated range match its non-dialogue, dialogue, or mixed value. Direct children and attributes outside the profile subset are rejected.

`validateEmissionProfileFormatMetadata` validates every local Matrix or Objects pack and channel declaration plus every track UID. Packs and channels require bounded names, matching type labels and definitions, and only the profile attributes. Objects packs select exactly one Objects channel. Matrix packs select one through 24 Matrix channels plus exactly one input and output pack. Matrix channels contain one Matrix block, while Objects channels contain at least one Objects block. Track UIDs accept only optional positive sample-rate and bit-depth attributes and exactly one permitted pack and channel reference. Reference elements cannot carry attributes, and format or track children outside the profile subset are rejected.

`validateEmissionProfileObjectBlocks` validates file-based Objects blocks. Every block requires relative start time and duration, consecutive blocks must be continuous, and nonzero durations must be at least 5 ms. A document uses one coordinate system throughout. Each block supplies all three coordinates and accepts only position, coordinate-system, divergence, gain, and jump parameters. Divergence requires the matching range, gain cannot exceed 10 dB, and jump interpolation is forbidden. Serial frames require the separate serial validation path.

`validateEmissionProfilePcmEssence` accepts the physical PCM sample rate, bit depth, channel count, and frame count. It requires one track UID per physical channel, compares every present track sample-rate and bit-depth attribute with the supplied properties, starts every local Objects block sequence at zero, and ends it exactly at the file duration using rational time arithmetic. `RiffMetadata.validateEmissionProfileAdm` also requires a one-to-one channel-allocation entry for every physical track. `AudioFileAdmMetadata.validateEmissionProfilePcmEssence` applies the equivalent check to parsed CHNA storage, while `AudioFileReader.readEmissionProfileAdmMetadata` derives the essence descriptor from an integer-PCM file and rejects floating-point essence. Its transactional counterpart stages both chunks and completes profile validation before replacing either caller destination.

`validateEmissionProfileSerialFrameEnvelope` starts the S-ADM path without claiming complete serial interoperability. It requires one `frame` root at BS.2125-1, one `frameHeader`, one `audioFormatExtended`, one empty `frameFormat`, at least one transport-track container, and one header profile list. Frame-format IDs use the eight-digit hexadecimal counter shape. Start and duration use exact ADM time syntax, duration is at least 5 ms, type is `header` or `full`, and the time reference is local. `validateEmissionProfileSerialTransportTracks` validates unique four-digit hexadecimal transport IDs, bounded names, equal positive track and ID counts, unique positive physical track IDs within each transport, PCM format declarations, exact one-reference track structure, and one-to-one coverage of every ADM track UID across all transport containers. `validateEmissionProfileSerialHeaderProfiles` requires a well-formed, duplicate-free header profile list with at least one emission-profile declaration and an identical declaration in the embedded ADM profile list. Other header profiles remain permitted. `validateEmissionProfileSerialObjectBlocks` retains typed local start, local duration, and initialization state. Timed Objects blocks use only local timing, start at zero, remain exactly continuous, use zero or at least 5 ms durations, increment their within-frame identifiers, and cover the frame duration exactly. An optional initialization block comes first, uses identifier counter zero, carries no timing, and does not constrain the first timed counter. `validateEmissionProfileSerialFlowFrame` accepts caller-owned `EmissionSerialFlowState` for an original flow. The first frame counter is one, later counters increment exactly, only the first frame may use the `header` type, and each start equals the preceding start plus duration across decimal and sample-fraction representations. Optional flow identifiers use the UUID text shape and must remain equal whenever present. Failed validation leaves the state unchanged, and `reset` starts a new flow. Modified flows that intentionally no longer preserve original counter semantics remain outside this strict opt-in path.

`AdmStaticMatrixMixer` binds one typed Matrix block to a caller-supplied, duplicate-free channel identifier order and retains fixed input indexes and gains. Linear and dB coefficients render in f32 or f64 without allocation. Plan construction rejects missing inputs, duplicate terms, non-Matrix blocks, variable values, phase, and delay. `AdmMatrixCoefficientMixer(Sample, maximum_delay_samples)` adds stateful nonnegative constant delay. It converts milliseconds at initialization using nearest-sample rounding with half-sample ties toward zero, rejects requests beyond the caller-selected capacity, and preserves its histories across arbitrary processing partitions. For a valid resolved plan, `reset` clears every delay path. Both mixers initialize inactive input indexes, gains, and delays deterministically. Their retained-state validation binds the live input and term counts to the construction-time plan. A count mismatch fails before reset, output, or history mutation. They validate every buffer length and reject overlapping input and output storage before mutation. Non-finite coefficient input is treated as silence.

`AdmVariableMatrixCoefficientMixer(Sample, maximum_delay_samples, maximum_variables, maximum_points, maximum_phase_taps)` is the opt-in product-policy layer for variable values and phase. Caller-defined `AdmMatrixVariableTimeline` values bind metadata names to linear gain, phase in degrees, or delay in milliseconds. Each bounded lane starts at sample zero, uses strictly increasing absolute `u64` sample positions, and selects held or linear interpolation. Variable delay endpoints use the constant-delay nearest-sample rule, then interpolate fractionally between those endpoints to avoid integer-delay jumps. Inactive coefficient, lane, point, and phase-filter capacity starts deterministically. Processing is sequential, allocation-free, and invariant to host partitioning. Retained-state validation binds the live input and term counts to the resolved construction-time plan. For a valid plan, `resetAt` clears signal history and selects an exact absolute restart position without converting the sample index to floating point. A count mismatch fails without changing the current cursor, absolute position, or history.

Phase processing uses a caller-supplied odd-length antisymmetric quadrature FIR. The mixer aligns the real path to the FIR group delay, evaluates `real * cos(angle) + quadrature * sin(angle)`, applies the same latency to every term, and reports it through `latencySamples`. The caller therefore owns the useful phase bandwidth, ripple, tap count, and resulting latency. The existing odd-symmetry equiripple designer can prepare the FIR outside the realtime path. Products that do not use phase can select zero phase-tap capacity and incur no added latency. Initialization rejects missing, duplicate, mistyped, unused, non-finite, over-capacity, or malformed control lanes and phase filters before publishing state. Processing rejects discontinuous sample ranges, invalid retained state, shape errors, range overflow, and aliases before changing output or history.

`AdmHoaMatrixDecoder(Sample, maximum_inputs, maximum_outputs)` accepts an ordered slice of typed HOA blocks and an output-major coefficient matrix already defined for the declared channel normalization. Initialization requires unique valid order-degree pairs, orders through 50, one normalization, one NFC reference distance, and one screen-reference value. N3D and SN3D are accepted through the supported order. FuMa is limited through order three. Equation-defined component bases are rejected because the metadata does not define a portable formula language. Static block gains are composed into the retained matrix, inactive component metadata is zero-initialized, and the live input and output counts remain bound to the construction-time shape. Processing replaces every output bus without allocation and validates retained counts, all shapes, and aliases before mutation.

`AdmHoaLoudspeakerMatrix(Sample, maximum_inputs, maximum_outputs)` generates that matrix outside the realtime path. It evaluates the real spherical-harmonic basis defined by [ITU-R BS.2076-3](https://www.itu.int/rec/R-REC-BS.2076-3-202502-I/en) at each non-LFE loudspeaker direction, then computes the minimum-norm mode-matching pseudoinverse with the bounded SVD. The basis uses azimuth from `-180` through `180` degrees, elevation from `-90` through `90` degrees, sine terms for negative degree, the zonal term for degree zero, cosine terms for positive degree, and no Condon-Shortley phase. N3D and SN3D are supported through order 50. The specified FuMa weights are supported through order three.

Generation requires at least as many distinct non-LFE directions as components and rejects a numerically rank-deficient layout. The result reports rank and condition number, keeps LFE rows exactly zero, retains the exact ordered component identity, zero-initializes inactive component metadata, and refuses to initialize a decoder with a different block set. Basic weights preserve the mode-matching solution. Optional max-rE weights apply the per-order Legendre approximation documented in the [AES AllRAD2 paper](https://www.aes.org/e-lib/download.cfm/19460.pdf?ID=19460). The generated matrix is angular and far-field. It retains the common NFC reference distance for use by a separate radial filter bank. Automatic generation rejects screen-referenced HOA by default. `AdmHoaScreenReferencePolicy.render_unchanged` explicitly opts into the BS.2127 reference-renderer behavior: require one consistent screen-reference value, retain the flag, and use the same angular coefficients because the standard does not define an HOA screen transform. The generic matrix decoder also retains a consistent flag for caller-supplied product matrices. Equation-defined HOA remains rejected.

The native reference gate uses a separate C++ basis evaluator and pivoted Gram-system inversion instead of the production basis, SVD, matrix, or decoder code. It compares SN3D, N3D, and order-three FuMa basis values at poles, axes, and off-axis directions. A golden-angle layout and a regular 8-by-4 full-sphere grid, each with an LFE row, cover basic and max-rE matrices and complete rendered sample blocks for all three normalizations, canonical and permuted component orderings, and mixed linear and decibel component gains.

`AdmHoaDualBandDecoder(Sample, maximum_inputs, maximum_outputs)` applies one fourth-order Linkwitz-Riley split to every ordered HOA component, then evaluates independent caller-supplied low- and high-band output-major matrices. Both matrices use the existing typed decoder validation, so component identity, normalization, NFC reference distance, screen-reference state, static block gains, and output count must agree. Every crossover capacity slot starts in the configured canonical state, including inactive slots. Processing is allocation-free, replaces every output, contains non-finite input and accumulation, and is invariant to host partitioning. Shape and alias checks complete before crossover history or output changes. The caller selects sample rate and crossover frequency and may transition to a new valid crossover transactionally. This layer supplies explicit dual-band policy without assuming which basic, max-rE, or product-specific matrix belongs in either band.

`AdmHoaRadialFilterBank(Sample, maximum_inputs, maximum_order)` adapts typed HOA components from their common NFC reference distance to the caller's physical loudspeaker radius. One reverse-Bessel near-field ratio is designed per used order, transformed into bounded first- and second-order digital sections, and shared by every component of that order. Inactive component metadata is zero-initialized. Retained-state validation binds the live input count to the construction-time component set and requires the exact cascade length implied by each order and optional regularizing shelf. It also rejects a screen-referenced bank when its retained policy does not permit unchanged rendering. The implemented normalization is unity at Nyquist. Its low-frequency gain approaches the loudspeaker-to-reference distance ratio raised to the component order. An optional gain-limit policy adds a first-order regularizing shelf when that ideal low-frequency gain exceeds the caller's decibel limit. The caller selects sample rate, loudspeaker distance, speed of sound, gain limit, and transition frequency outside the realtime path.

The radial-filter verification evaluates the same physical transfer independently from the closed-form reverse-Bessel coefficients. It applies the bilinear frequency mapping and optional analog shelf directly, without the production polynomial root solver, section construction, or cascade response. The comparison covers orders 1–16, three sample-rate and distance geometries, ten frequencies from DC through Nyquist, and a regularized eighth-order design.

Processing is allocation-free, supports exact in-place buffers, contains non-finite input, and is invariant to host partitioning. All channel shapes and aliases are checked before output or history changes. Initialization rejects missing or mixed reference distances, equation-defined components, unsupported orders, malformed policy, or a failed bounded root solve. Screen-referenced HOA is rejected by default. The same explicit `render_unchanged` policy accepts a consistent flag and leaves radial design unchanged. This layer does not infer loudspeaker radius from ADM metadata, choose a gain limit, invent a screen transform, or combine the filter bank with an angular decoder. Those remain explicit product policy.

`AdmBinauralStereoMixer(Sample)` handles one static block per ear for content already encoded as left-ear and right-ear signals. It accepts the current and legacy ADM channel names, requires exactly one channel per ear, maps either input ordering to stereo output, and composes linear or dB block gain. Block processing replaces both outputs without allocation, treats non-finite input as silence, and rejects every input-output or output-output overlap before mutation.

`AdmBinauralStereoGainTimeline(Sample, maximum_blocks_per_ear)` handles explicit block timing for the same direct-ear content. Initialization accepts one ordered block sequence per input channel, maps those channels to ears, and retains exact rational start, interpolation-end, and end positions. Each live per-ear segment count remains bound to its construction-time sequence. An ordinary adjacent block ramps from the previous gain over its full duration. A jump block switches immediately unless it supplies a nonzero interpolation length. Gaps render silence and prevent cross-gap interpolation. `process` replaces an arbitrary absolute sample range without allocation, and its result is independent of host-buffer partitioning.

`HrtfDatabase(maximum_measurements, maximum_frames)` copies a measured stereo impulse-response set, optional positive measurement radii, and optional fractional per-ear delays into fixed storage. Directions use head-relative azimuth from -180 through 180 degrees and elevation from -90 through 90 degrees. Constructors without radii retain the source-compatible one-metre default. Initialization rejects non-finite samples, empty responses, malformed shapes, invalid delays, radii, or directions, and duplicate three-dimensional measurement positions, including wrapped azimuth and pole aliases at the same radius. Measurements may share a direction when their radii differ. Live measurement, response-frame, and rendered-frame counts remain bound to the imported dataset. `interpolate` retains direction-only nearest and three-neighbor angular interpolation. `interpolateAt` selects neighbors by full three-dimensional measurement position when the database contains multiple radii, using the same nearest, inverse-distance, delay-aligned, and optional spectral reconstruction modes. Both interpolation paths reject a destination that overlaps the database's retained response capacity, preserving the reusable measurements before staged output publication. A single-radius database ignores the query radius so its directional results remain exact. `HrtfMeasurementPosition` and `hrtfMeasurementFromPositions` expose the direction-plus-distance query and world-space derivation through the public DSP package.

`HrtfRenderer(maximum_frames, partition_size)` stages an interpolated response through the immutable convolution publication path. Preparation and sample-rate conversion are non-realtime operations. `adoptPending` is the bounded audio-thread publication point, and `processSample` sends one finite mono source through the independent measured left and right filters without allocation. The quiescent `valid` query composes the complete convolver state contract, including publication slots, prepared filters, processing histories, and live cursors. Malformed nested processing state returns silence without advancing the renderer. Partitioned and zero-latency modes, generation ordering, reset, non-finite input containment, active-generation reporting, and explicit latency are available. The product owns the worker or message-loop execution that prepares and publishes a new static filter.

`HrtfFirstOrderRoomPathPlan` derives the direct path and up to six first-order reflections for an axis-aligned `HrtfShoeboxRoom`. Source and listener positions must be strictly inside finite room bounds. Named surface values express energy absorption from zero through one; unspecified surfaces default to complete absorption. Each non-fully-absorbed surface produces an image-source direction in the current head pose, pressure reflection `sqrt(1 - absorption)`, relative spherical-spreading gain, and excess-path delay from a caller-supplied finite positive speed of sound. The direct path retains unit gain and zero added delay. The plan binds its live path count to the constructed route set and rejects malformed geometry, absorption, sample rate, speed, pose, and retained state.

`HrtfSecondOrderRoomPathPlan` extends the same room model through two reflections. Its complete image lattice contains the direct path, six first-order images, six same-axis second-order images, and twelve cross-axis second-order images. Each second-order gain multiplies the pressure-reflection coefficients of the two encountered surfaces before applying direct-relative spherical spreading. Fully absorbed paths are omitted, so the retained plan contains between one and 25 paths. Its live path count remains bound to that constructed set.

`HrtfImageSourceRoomPathPlan(reflection_order)` generalizes the same lattice from direct-only order zero through reflection order eight. The capacity is fixed at compile time and available through `hrtfRoomPathCapacityForOrder`; it grows from one direct path to 833 paths at order eight. Each signed image index determines the exact alternating wall sequence on that axis, so repeated and cross-axis reflections multiply the correct surface coefficients. The planner rejects an unsupported compile-time order, retains only non-fully-absorbed paths, and binds the live path and image-index views to the constructed route count.

`HrtfRoomSurfaceImpulseResponses(maximum_frames)` copies one finite, nonempty causal f32 response for each of the six room surfaces and retains their common sample rate. Its live sample rate and six frame counts remain bound to the imported response set. `HrtfFrequencyDependentRoomResponseComposer(maximum_frames, reflection_order, maximum_surface_frames)` accepts the HRTF database by pointer, requires the material rate to match it, then convolves the responses in each image path's exact wall order before applying the directional HRTF, spherical spreading, broadband pressure-reflection gain, and fractional propagation delay. A path through `n` surfaces has at most `1 + n * (maximum_surface_frames - 1)` material frames. Set a surface's scalar absorption to zero when its impulse response already contains the complete reflection magnitude; otherwise the impulse response multiplies the scalar pressure term. Preparation uses fixed f64 convolution and accumulation storage, leaves caller output unchanged after validation or numeric failure, rejects output that overlaps the database, path plan, surface responses, or composer storage, and runs outside the audio thread.

`HrtfRoomResponseComposer(maximum_frames, maximum_paths)` accepts the HRTF database by pointer and sums a bounded set of `HrtfRoomPath` values into one interleaved stereo response outside the audio thread. Each path selects a head-relative direction, positive physical source or image distance, finite signed gain, and nonnegative fractional delay added after the database's measured per-ear delay. The room planners derive that distance from their direct and image-source geometry, allowing multi-radius databases to select near-field measurements independently for each path. Fractional delay uses linear interpolation against zero padding. Composition uses fixed f32 interpolation storage and f64 accumulation, returns the required response length, leaves destination storage beyond that response unchanged, and rejects overlap with the retained database, path input, or internal storage. Validation and numeric failures leave the destination unchanged. `HrtfRenderer.prepareInterleavedResponse` publishes the composed response through the same generation boundary as a database interpolation.

`HrtfMotionRenderer(maximum_frames, maximum_points, maximum_crossfade_samples)` precomputes a bounded sequence of source and head poses outside the audio thread. Every preparation method accepts the HRTF database by pointer. Positions use a right-handed coordinate system with positive X forward, positive Y left, and positive Z up. Head yaw, pitch, and roll transform world-space source positions into head-relative directions while source-to-head length supplies the measurement radius. `prepare` interpolates one direct measured response per point. `prepareRoom` plans and composes the complete first-order room response, `prepareSecondOrderRoom` includes both reflection orders, and `prepareImageSourceRoom` accepts any supported compile-time order. `prepareFrequencyDependentImageSourceRoom` also composes the six retained surface impulse responses along every image path. Every room path zero-pads shorter tails to the schedule's longest filter. A room tail beyond `maximum_frames` reports a frame-capacity failure. Strictly increasing absolute sample positions select filters, and smooth fixed-duration crossfades avoid filter-switch discontinuities. Every scheduled crossfade must finish within the `u64` sample timeline. `valid` covers canonical unprepared state, processing geometry, schedule order, source and head geometry, derived directions, finite filters and history, and the temporal relationship between the live sample and point cursors. Realtime processing performs an O(1) shape preflight, evaluates the candidate input before committing history or cursor state, allocates nothing, and returns silence without mutation for malformed retained data. Schedule validation and every preparation path are transactional.

`HrtfMotionClock` maps ordered timestamps from a tracker clock onto absolute audio sample positions. Construction binds an audio sample rate, tracker ticks per second, and one corresponding timestamp and sample anchor. `initCalibrated` estimates the effective integer tick rate from two ordered synchronized tracker and audio observations, rounds to the nearest tick per second, and anchors the mapping at the newer observation. `HrtfMotionClockCalibrator(capacity)` adds a rolling fixed window for three through 64 observations. It computes every valid pairwise rate, selects their median, requires at least half of consecutive intervals to fall within a caller-selected parts-per-million tolerance, and requires the newest interval to be an inlier before anchoring at the newest observation. This contains interior timing outliers without allowing a delayed newest observation to move the active anchor. `observeAndCalibrate` retains the first two valid observations without producing a clock, then admits each later observation only when the complete staged window calibrates successfully. A rejected newest outlier does not pollute the retained window. Mapping uses checked integer arithmetic, rejects timestamps before the anchor or out of order, and reports timestamps that are too close to resolve as distinct audio samples. `reanchor` supports a future synchronization point without accepting tracker or sample rollback. Both types expose `valid`. The clock query covers canonical unmapped state, exact mapped clock arithmetic, and the valid post-reanchor phase. The calibrator query covers retained capacity and strict observation order. Calibration, mapping, and reanchoring validate retained state before arithmetic and leave active state unchanged on failure.

`HrtfMotionPointQueue(capacity)` carries absolute-sample source and head-pose updates from one tracker producer to one preparation consumer without allocation or locks. Submission validates every finite pose and requires strictly increasing sample positions. `submitTracked` composes a producer-owned `HrtfMotionClock` with queue publication, leaving the clock retryable when validation fails or the queue is full. A full queue preserves its contents, returns `false`, and increments a saturating drop counter. Cursor corruption is reported without reading a slot. Before returning a published point, the consumer revalidates its source and head geometry and its strict ordering relative to the next already-published point. Malformed retained geometry or ordering reports `InvalidHrtfMotionQueueState` without advancing the read cursor, so repaired data remains retryable. The consumer receives complete points in order and can query the bounded pending count. The quiescent-only `valid` query also checks producer scheduling phase, every pending point, and strict queued order. Consumer operations never inspect producer-owned non-atomic scheduling fields. Fixed point storage starts deterministically. `reset` scrubs every point and clears cursors, scheduling history, and drop evidence only while both participating threads are stopped. Live receive does not clear a slot because the producer may still validate it before the consumer publishes the read cursor or reuse it afterward. Device acquisition, synchronized observation capture, product tolerance selection, and preparation-executor selection remain product responsibilities outside the audio callback.

`HrtfStreamingMotionRenderer(maximum_frames, queue_capacity, maximum_crossfade_samples)` connects non-audio filter preparation to allocation-free scheduled rendering. One preparation thread validates each ordered motion point, resolves its head-relative direction and source distance, interpolates the complete stereo filter into a free fixed slot, and publishes the slot with release ordering. The audio thread retains the active slot, begins a smoothstep fade at the absolute target sample, crossfades to the next prepared filter without copying or allocating, and releases the preceding slot only after the transition completes. It scrubs the retired slot before publishing that release. A late filter still receives a full click-free transition beginning when it becomes available. The first filter fades in from silence. Queue saturation preserves every retained filter, returns `false`, and records a saturating drop count so the producer can retry the same point. At least two slots are required because the active filter remains owned until its replacement completes. Every prepared point reserves a representable post-crossfade sample position. The renderer binds its live start position and crossfade length to its initialized configuration. Each published slot binds its live sample rate and frame count to the database used to prepare that filter. Producer preflight validates its latest immutable submission before interpolation or publication. Consumer preflight validates the complete pending sequence before history, cursor, or output mutation. Quiescent validation rechecks that every queued point follows the renderer start, remains at least one crossfade after its predecessor, and owns any retained fade that claims to be adopting it. Consumer preflight applies the timeline bound to a late fade and rejects an active fade at or beyond its retained completion point. Sample-rate changes, schedules closer than the configured crossfade, cursor corruption, a stored direction that disagrees with its source and head geometry, malformed published filters, non-finite history, and sample-position overflow fail before unintended publication or audio-state mutation. Its quiescent-only `valid` query checks the complete producer, consumer, slot, filter, schedule, history, and transition state. Fixed slots start deterministically, and quiescent `reset` scrubs every slot. A product can drain `HrtfMotionPointQueue` into this renderer on its preparation thread; device callbacks and the selection of a preparation executor remain product responsibilities.

`HrtfSofaLoader(maximum_measurements, maximum_frames)` reads SimpleFreeFieldHRIR files through an optional runtime-loaded NetCDF library. `openDefault` probes supported platform names, current NetCDF ABI names from 19 through 22, and the stable Homebrew and MacPorts macOS locations. `openRuntime` accepts a product-selected library path, rejects empty or embedded-NUL paths before allocation or native loading, and permits package managers or deployments outside the default search locations without adding a link-time dependency. `isOpen` reports whether both the library owner and its resolved API are live. `deinit` clears the callable API before closing the library and is safe to repeat. Loading through a closed or partially initialized loader reports `SofaLoaderClosed` before allocating or changing the destination. The loader accepts the SOFA 1.0 container only with convention 1.0 and the SOFA 2.1 container with convention versions 1.0, 1.1, or 1.2. It rejects empty dataset paths and embedded NUL bytes before calling the runtime. Every variable dimension must be nonzero, and each variable's checked value count must fit the configured loader capacity before allocation or native decoding. Response measurement and frame dimensions must fit their independent capacities before dependent variables are read. Source positions, sampling rates, delays, and geometry are capped by the file's accepted measurement count. The response measurement, receiver, and frame axes must be distinct. Dependent variables must use compatible measurement, receiver, and coordinate dimension identities instead of relying on coincident lengths. The loader requires standard double-precision storage before NetCDF conversion, then validates free-field FIR data, stereo receiver count and ordering, finite receiver geometry, coordinate encoding and units, one-dimensional sampling-rate shape and consistency, checked impulse dimensions, two-dimensional per-ear delay shape, finite f32-representable responses, nonnegative finite delays, and default listener and emitter geometry before publication. Standard spherical azimuths from zero through less than 360 degrees normalize to the renderer's signed range. Spherical radius and Cartesian vector length are preserved as positive measurement radii, so files may contain multiple responses on one ray at distinct distances. A file with measurement-varying listener geometry remains unsupported. `loadFileInto` and `hrtf_sofa.databaseFromDecodedInto` commit into caller-owned storage only after complete validation, which avoids full-capacity stack copies for large datasets. The by-value APIs remain available for smaller capacities. Two independently authored CC BY 4.0 measured datasets exercise 44.1 and 48 kHz, 440 and 1,513 directions, and 128- and 256-frame responses. The Viking fixture passes an exact-direction impulse render against independently extracted NetCDF landmarks from both ears and across the complete response span. Its three-direction inverse-distance render matches an independently calculated response landmark, its zero-delay aligned response is bit-identical, and its spectral response matches a separate direct-DFT calculation at landmarks spanning both ears and the complete response. The public-dataset gate also compiles a separate C++ implementation that links directly to NetCDF, selects its own neighbors, calculates its own weights and transforms, and compares every sample from exact and off-grid inverse-distance and spectral responses for both datasets. The ordinary framework has no link-time NetCDF dependency. Product-specific dataset selection, tracker device integration, reflection orders above eight, diffraction, and headphone audition remain outside this layer.

The Linux established-renderer gate builds libmysofa 1.3.5 from commit `6cc5b15a73e9bd97810d03767082edda7f315881` under its three-clause BSD license and libspatialaudio 0.4.1 from commit `d149ed9744fd399b835c6f2920511f8cbcfce5ea` under LGPL-2.1-or-later. Both source archives have pinned SHA-256 hashes and are installed into isolated temporary prefixes. Libmysofa supplies unnormalized measured responses and per-ear delays for four stored directions in each public dataset. Every complete response is compared with the independently loaded raw measurement, then rendered as an impulse through `HrtfRenderer` and compared sample by sample. Libspatialaudio supplies its own preset decoder matrices and complete output buffers for first-, second-, and third-order three-dimensional HOA at 44.1, 48, and 96 kHz over 5.1 and 7.1 layouts. The project matrix engine reproduces all 5,654 output samples across FuMa, N3D, and SN3D inputs, including a permuted component order. The gate reports bounded peak and normalized RMS error, rejects silent, short, non-finite, malformed, and partially written references, and tests download, hash, build, signal, and missing-environment failures without publishing partial installations.

`AdmDirectSpeakerRouter` handles one unambiguous exact label, while `AdmDirectSpeakerPositionRouter` adds common-layout gain mapping, bounded polar or Cartesian selection, screen-edge transforms, LFE routing, discard behavior, and explicit point-panner fallback. Both routers bind their live output count to the construction-time destination layout and reject a mismatch before reading input or changing output. Supply `AdmDirectSpeakerCommonPackMapping` with the source pack identifier and output layout name to enable common-layout rules. A rule applies only to a block with exactly one normalized speaker label and only when every destination label exists. The first complete ordered rule wins before ordinary label, bound, LFE, or panner fallback. Multi-output routes use `mix` or a fallback mixer because `processSample` cannot represent them. `AdmPolarPointSourcePanner` renders nominal speaker regions through measured reproduction positions, including virtual layer and pole downmixes and the dedicated stereo path. Its inactive vertices, nominal positions, output mappings, and regions start deterministically. `AdmCartesianPointSourcePanner` applies the bounded allocentric point-source algorithm over caller-owned room positions. Both panners exclude LFE outputs and preflight block aliases.

`AdmPolarExtentPanner` retains the 1,652 spreading directions and a copy of its point panner. Its precomputed per-direction gains live in caller-owned storage whose length is returned by `requiredGainStorage`; that storage must remain alive and unchanged while the extent panner is used. Initialization preflights every direction before filling the table. Gain calculation covers width, height, distance, and depth without allocation and rejects an output slice that overlaps the retained table. `AdmObjectPolarExtentGainPlan.initPolarExtent` applies screen transforms, polar channel lock, divergence, block gain, and direct/diffuse splitting before retaining the final gain vectors.

`AdmCartesianExtentPanner` copies a validated allocentric point panner and evaluates the separable virtual-source grid without retained gain storage. Both point and extent panners initialize inactive position capacity to the origin and mark it disabled. Layouts with three or more height planes use 40 samples on every axis. Other layouts use 20 samples over the nonnegative height range. Gain calculation applies extent scaling, layout-dimensional weighting, inside and boundary accumulation, boundary fading, point-to-extent crossfade, normalization, and LFE suppression. `AdmObjectCartesianExtentGainPlan.initCartesianExtent` applies the common Objects transforms and gain stages. `AdmObjectPointGainPlan.init` remains the smaller zero-extent path for polar or Cartesian point panners. Its direct and diffuse gain views return empty if the live output count differs from the construction-time layout or either active gain vector is invalid, and their inactive capacity starts at zero. Objects timelines initialize unused segment capacity with an empty gain target and valid zero sample positions. Objects and Binaural timeline block counts report zero when any retained timeline invariant is invalid.

Objects blocks retain up to 32 typed polar or Cartesian exclusion zones. Polar rendering selects speakers from nominal positions, groups destination speakers by layer, front/back change, unit-vector distance, and front/back distance, and redistributes excluded gain power through the first available priority group. Cartesian rendering applies the additional allocentric row repair, cancels an exclusion that would remove every speaker, excludes removed speakers from channel lock, and runs point or extent panning on a reduced layout before mapping gains back to the complete output order. LFE outputs remain silent in both paths.

`AdmObjectGainTimeline(Sample, maximum_blocks)` precomputes one direct and diffuse gain target per explicitly timed Objects block. Use `init` for point rendering, `initPolarExtent` for polar extent, or `initCartesianExtent` for Cartesian extent. Exact rational time remains intact through sample-boundary selection and interpolation phase calculation. An ordinary adjacent block ramps from the preceding target across its full duration. A jump block switches immediately unless it supplies a nonzero interpolation length, in which case the ramp occupies that initial interval and the target remains fixed afterward. The first block and every block after a gap remain fixed for their full span. A zero-duration block renders no samples but supplies the source target for an adjacent successor. Live output and segment counts remain bound to the construction-time layout and block sequence. Objects and Binaural timelines initialize unused segment capacity with empty targets and valid zero sample positions.

Timeline construction is a non-realtime operation because it calculates every spatial target. `mix` accepts an absolute first-sample index and arbitrary input partition, performs no allocation, adds into separate direct and diffuse output buses, and preflights all shapes and aliases before mutation. The caller chooses the maximum metadata-block count at compile time. A single block without explicit timing continues to use its static gain plan.

`AdmObjectDiffuseProcessor(Sample, maximum_outputs)` completes the Objects direct and diffuse bus path. Initialization is non-realtime. It designs one deterministic 512-sample random-phase all-pass FIR per canonical output label using that label's rank in the sorted layout. Layout reordering therefore preserves each channel's filter. `process` decorrelates each diffuse bus with f64 accumulation, delays the corresponding direct bus by 255 samples, and replaces the final output buses. It accepts arbitrary partitions, allocates no memory, treats non-finite input as silence, and preflights state, shapes, and aliases before mutation. `latencySamples` reports the direct-path match that the enclosing renderer must include in its latency contract. `reset` clears both paths. The caller chooses the maximum output count at compile time, which bounds all coefficients and history. The local ReleaseFast benchmark covers fully active 12-channel f32 and f64 layouts at 16, 64, and 512 frames.

`validateEmissionProfileComplementaryLabels` validates complementary-group labels on the group leader. Labels contain one through 64 Unicode scalar values, require a unique registered ISO 639-2 language per leader, and accept no other attributes. Object reference elements accept no attributes. `validateEmissionProfileConsistentLabelLanguages` is a separate opt-in check for the recommendation that every programme, content, and complementary-group leader expose the same label-language set. `validateEmissionProfileRecommendedProgrammeLanguages` is another opt-in check. A programme that includes every member of a complementary group whose contents use multiple languages declares `und` as its programme language. `validateEmissionProfileRecommendedDialogueLoudness` separately requires dialogue loudness on each dialogue or mixed content and on every programme that references such content. None of these recommendations is part of the conformance chain.

`AdmXmlTagIterator` exposes bounded tag groups as typed tag or target items. Tags retain decoded text and an optional class. Targets are limited to programme, content, or object identifiers and participate in the same local custom-reference validation as the main graph. Each direct group must contain at least one tag and one target.

`AdmTimeValue` preserves ADM decimal and fractional-sample time forms as an integer whole part plus an exact rational fraction. It accepts clock-form decimal time, clock-form sample fractions, and short sample counts. Decimal fractions require at least five digits. Long sample fractions require matching numerator and denominator digit counts and a numerator below the rate. Exact comparison and sum equality work across unlike denominators, while `toSeconds` provides an explicit floating-point conversion.

`AdmXmlBlockIterator` exposes block IDs, parent channel IDs and names, exact `rtime` and `duration`, gain, importance, jump position and optional interpolation length, head locking, and headphone virtualization. One static block may omit timing and receives the BS.2076-3 defaults. Every block in a multi-block channel must provide both timing attributes. Validation also enforces direct channel ownership, matching channel and block identifiers, block indexes starting at one in document order, finite nonnegative common linear gain, finite dB gain, importance from zero through ten, unique common parameters, flag syntax, and interpolation no longer than a bounded block duration.

Type-specific block models cover DirectSpeakers polar or Cartesian positions, bounds, speaker labels, and screen-edge locks; Objects positions, dimensions, diffuse amount, divergence, channel locking, screen references, and bounded polar or Cartesian exclusion zones; HOA equation, order, degree, normalization, and NFC reference distance; and Binaural current or legacy ear channel names. Matrix blocks expose bounded coefficients with typed input channel identifiers and constant or variable gain, phase, and delay. Public block slices return empty for a retained count beyond their fixed storage, and `retainedCountsValid` reports the combined count state. Inactive position, speaker-label, exclusion-zone, and Matrix-coefficient capacity starts with defined empty values. Bounded ADM text and speaker-label views likewise return empty for hostile lengths, while Matrix identifier access reports invalid retained state. Their inactive bytes start at zero. The generic ADM model permits negative Matrix coefficient gains and accepts the current `outputChannelFormatIDRef` name or legacy `outputChannelIDRef` name, with one output reference per block. The emission-profile validator applies its narrower gain, attribute, and reference-name rules. Custom coefficient references must resolve locally.

`AdmXmlDocument.validateChannelAllocation` cross-checks physical track UID references and custom track, channel, and pack definitions against CHNA. The public CHNA view revalidates its borrowed header, payload extent, retained counts, capacity, every active entry, unused zero slots, UID uniqueness, and complete track coverage. Its iterator applies that complete validation and rejects malformed view state or a cursor beyond the retained entry count without advancing. `RiffMetadata.validateAdm` validates an in-memory aXML and CHNA pair. `AudioFileReader.readAdmMetadata` retrieves both chunks into separate caller buffers and returns a validated typed document and channel-allocation view. It returns no ADM metadata when neither chunk exists and rejects incomplete pairs, overlapping buffers, malformed XML, invalid graph structure, and inconsistent mappings.

`RiffMetadata` composes Broadcast Wave, iXML, aXML, CHNA, and INFO data in interoperable order. `WavFileWriter.initWithRiffMetadata` places this package before the format chunk, as required for BWF. `Rf64FileWriter.initWithRiffMetadata` and `Bw64FileWriter.initBw64WithRiffMetadata` place it after the mandatory `ds64` chunk and before the format chunk. External loudness measurement accuracy, the remaining dynamic rendering layers, and independent tool exchange remain separate work.

`encodeId3` and `Id3View` implement complete allocation-free ID3v2.4 tag framing independently of an audio container. The codec validates syncsafe tag and frame sizes, frame identifiers and flags, optional extended-header update, CRC, and restriction fields, zero padding, matching footers, and whole-tag unsynchronisation consistency. The encoder rejects output overlap with the frame descriptor array or any payload before mutation. The UTF-8 text payload encoder applies the same source/output rule. Iteration retains unknown frame identifiers and encoded bodies. Public ID3v2.4 and ID3v2.3 iterators expose `valid`, revalidate every retained frame, and accept only cursors at exact frame boundaries. Rejection does not change the cursor. Decoding into caller storage reverses per-frame unsynchronisation before exposing grouping identity, encryption method, data-length indication, compression state, and the remaining payload. UTF-8 text payload helpers and `Id3DecodedFrame.text` cover the four standard ID3 text encodings, including UTF-8 validation, UTF-16 byte-order marks, and surrogate pairs.

`encodeId3V23` and `Id3V23View` provide a separate [ID3v2.3](https://id3.org/id3v2.3.0) contract. Frame sizes are ordinary big-endian 32-bit integers. The status flags, format flags, and compression-size, encryption-method, and grouping-identity prefixes use v2.3 bit positions and ordering. Optional extended headers retain declared padding and CRC-32 values. Requested tag-wide unsynchronisation is emitted only when a false sync or terminal `0xff` requires transformation, and parsing reverses the complete encoded body into caller storage before interpreting headers. The frame descriptor array, every payload, and text helper input must remain disjoint from the output prefix. Unknown frames remain iterable. Text helpers accept Latin-1 or BOM-qualified UTF-16, the two encodings defined by v2.3.

`encodeId3V1` and `Id3V1View` cover exact 128-byte [ID3v1.0 and ID3v1.1](https://id3.org/ID3v1) tail records. The encoder validates field capacities, embedded NUL bytes, four-digit years, and nonzero v1.1 track numbers before replacing caller storage. The view distinguishes v1.1 only when the 29th comment byte is zero and the following track byte is nonzero. It retains arbitrary genre identifiers, including the conventional unknown value 255.

Compression and encryption algorithms remain external policies: the generic v2 frame layers carry their flags and auxiliary fields without claiming to interpret transformed payloads. Source and destination overlap is rejected before mutation.

`Mp3Header`, `Mp3Frame`, and `Mp3Stream` provide bounded MPEG-1, MPEG-2, and MPEG-2.5 Layer III framing. Header parsing validates the sync, version, Layer III selector, bitrate index, sample-rate index, channel mode, CRC-protection bit, and padding bit. It computes the standard 1,152- or 576-sample frame duration and checked frame byte length. Free-format headers retain an unresolved zero bitrate and frame length until the stream infers an unpadded base length. Inference scans at most 16 KiB, accounts for each frame's padding bit, and parses the complete first, candidate, and following frames before accepting a size. Aligned payload sync patterns with malformed metadata, side information, or protected CRCs cannot establish the base. A standalone free-format frame is rejected as ambiguous.

Stream parsing requires a stable version, sample rate, channel count, and free-format mode, skips one bounded leading ID3v2.2, v2.3, or v2.4 tag and one trailing ID3v1 record, and rejects truncated frames or trailing data. ID3 extent checks use ordered subtraction rather than potentially overflowing end-offset addition. Cursor, first-header, free-format base length, frame-count, and sample-count changes commit together only after all derived values validate. The reader exposes `valid` for retained boundaries, header fields, frame-to-sample counter coherence, free-format base state, and enough consumed bytes to contain every completed frame at the format's smallest compatible Layer III frame size. The same validation runs before iteration and recovery. The tables and ordinary bitrate frame formulas follow FFmpeg's maintained [MPEG Audio header decoder](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/mpegaudiodecheader.c).

The first frame retains bounded Xing or Info fields, the 100-byte seek table, optional quality, encoder identity, gapless delay and padding for validated printable identifiers, and version-1 VBRI fields and table bytes. Xing and Info metadata begin at the fixed byte after the nominal side-information area; a protection word changes the side-information payload start but not this metadata position. Generated metadata uses a truthful project identifier by default. Direct Xing and Info emitters accept a caller-supplied nine-byte printable identifier, reject control-only or blank identities before changing destination storage, and retain compatibility with existing metadata literals through the default. CBR and VBR stream, reservoir, and file encoders expose matching `WithEncoder` start methods, retain the identifier through final replacement, and restore it after recoverable file failures. VBRI placement follows FFmpeg's maintained [MP3 demuxer](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mp3dec.c). Parsing rejects malformed VBRI table shape, zero segments, incomplete frame coverage, arithmetic overflow, and cumulative offsets beyond the declared stream bytes. `Mp3Vbri.approximateByteOffsetForFrame` interprets the validated one- through four-byte scaled segments and returns an audio-relative offset, including bounded linear approximation inside a multi-frame segment. It repeats validation so hostile retained-field changes fail without producing an offset. `Mp3Summary` reports the scanned encoded frame count, sample count, byte range, sample rate, channel count, and duration. `Mp3GaplessPlan` validates paired delay and padding fields and derives the exact audible range. `Mp3StreamDecoder` accepts only a nonempty summary whose sample count equals its frame count times the version-specific frame length. Its retained encoded-sample cursor must remain on that same frame cadence before decoding or finishing.

`Mp3PcmStreamEncoder` accepts complete PCM frames, flushes the fixed analysis delay, and reports encoded, input, delay, padding, frame, and byte counts. Call `startGaplessMetadata` before the first PCM append to reserve a silent CBR Info frame. After `finish`, call `gaplessMetadataFrame` with the original frame-sized destination to replace the provisional counts. The reserved frame advances the encoder analysis state, and its duration is included in the reported delay. Protected Info and Xing frames place metadata after the CRC and complete side-information region, then repair the CRC over the protected header fields. `Mp3PcmFileEncoder` performs the same replacement during finalization. A failed partial metadata patch remains recoverable through its positional checkpoint.

`Mp3PcmReservoirEncoder` retains one frame until the next PCM frame is available. It moves as many complete leading main-data bytes as possible into the unused tail of that prior frame, bounded to 511 bytes for MPEG-1 and 255 bytes for MPEG-2 or MPEG-2.5. It then updates the current frame's `main_data_begin`, shifts its remaining physical payload, and recomputes a protected frame's side-information CRC. Pending storage starts deterministically and is scrubbed on reset, so unused tail bytes do not retain prior encoded audio. Its `valid` query covers the nested PCM encoder, pending frame bytes, receive and emission counts, cumulative borrowed-byte bounds, and finalization phase. Append and finish apply the same check before mutation. `Mp3PcmReservoirStreamEncoder` flushes the analysis delay through the same pending-frame path. Its `valid` query also binds stream counts, byte and padding cadence, metadata identity, and finalization to the nested reservoir. Its optional Info frame is encoded independently before reservoir priming, so later borrowed payload cannot overwrite metadata. `Mp3PcmReservoirFileEncoder` writes only finalized frames, patches final gapless metadata before synchronization, and restores both the emitted boundary and provisional first frame after a partial patch. Its `valid` query composes the stream contract with caller-storage capacity, exact committed-byte accounting, and finalization.

`mp3ReservoirRepackRequirements` measures the logical payload and physical main-data capacity of a complete untagged stream of independent frames. `repackMp3MainDataReservoir` then uses disjoint caller scratch to place those payloads across any number of compatible frame regions, bounded by a caller-selected history limit and the format's 511-byte or 255-byte backpointer field. It rewrites every `main_data_begin`, repairs protected-frame CRCs, and commits the destination only after the complete stream succeeds. Free-format, metadata-bearing, format-changing, and already packed streams are rejected. A zero history limit preserves the independently encoded bytes.

`Mp3FrameEncoder.encodeQuantizedFrameParts` separates a frame shell from its logical main data, allowing the payload to exceed that frame's physical body without publishing an invalid partial frame. `packMp3MainDataReservoir` accepts a sequence of those shells and concatenated logical payloads, then commits the packed stream through disjoint scratch. `Mp3ReservoirCreditTracker` derives each next history allowance from actual frame capacity and byte-rounded logical use. It rejects format changes, unreachable payloads, malformed retained credit, and history beyond the selected policy or format limit. `mp3ReservoirQuantizerBudget` caps physical plus retained history by the active Layer III side-information fields, and `Mp3EncoderQuantizer.processWithReservoirMasking` spends that limit while retaining the caller's psychoacoustic evidence. Ordinary quantization delegates with zero history for source-compatible behavior.

`encodeMp3PcmReservoirBatch` composes PCM analysis, temporal masking, credit tracking, logical staging, and transactional multi-frame packing for constant-rate streams. `encodeMp3VbrPcmReservoirBatch` evaluates every configured bitrate candidate against the same reachable history, retains the selected bitrate and quality evidence, and returns its histogram, misses, maximum noise-to-mask ratio, logical bit total, borrowed-byte total, largest backpointer, and final credit. Both require caller-owned destination, frame, packing, and logical-data storage. Frame and logical-data scratch must not overlap the PCM source because those regions change while input traversal is active. Destination and packing scratch may overlap the PCM source because they change only after traversal finishes. Failure may change scratch but preserves the destination. `Mp3PcmAdaptiveReservoirStreamEncoder` and `Mp3VbrPcmAdaptiveReservoirStreamEncoder` retain caller-owned frames while any physical main-data byte remains reachable through the configured history window. Append publishes every complete frame that future input can no longer change; finish releases the bounded tail. Each append stages pending frames and logical payloads separately, so capacity and alias failures preserve the live encoder and pending bytes. Fixed-rate validation derives the total encoded byte count from retained physical main-data bytes, the ordinary frame count and overhead, and the optional independent metadata frame. A mismatched public counter fails before finish publication. CBR and VBR output match their complete batch packing byte for byte, while VBR append also returns the selected bitrate and masking evidence. Their file encoders snapshot the unpublished window in separate caller storage before encoding. A partial write or failed final sync restores the stream state and pending bytes; `recover` truncates the file to the last committed audio-relative boundary before retry. `writeMp3PcmReservoirBatchFile` and `writeMp3VbrPcmReservoirBatchFile` encode the complete batch before file mutation, replace bytes from a checked audio offset, remove stale trailing data, and synchronize the exact result. A failed partial write restores the file to that audio boundary, preserving any prefix and making a full retry safe. The `WithInfo` and `WithXing` variants prepend truthful total-frame and byte counts; Xing output also includes a generated 100-entry seek table and optional quality. Their delay fields remain unspecified because those compatibility APIs do not flush the analysis delay or know the caller's audible sample count. `encodeMp3PcmReservoirGaplessBatch` and `encodeMp3VbrPcmReservoirGaplessBatch` reserve an independent metadata frame, advance analysis through it without exposing that frame as reservoir credit, flush the 1,057-sample analysis delay, and derive final delay and padding from the encoded extent and supplied PCM. Their metadata scratch must also remain separate from the PCM source because reservation happens before traversal. Their positional file variants retain the same prefix-preserving partial-write rollback as other complete-batch writers.

`Mp3EncoderPsychoacousticModel` reports energy, spectral-flatness tonality, and masking threshold for each active scale-factor band. `tonal_masking_reduction` tightens the same-band threshold for sparse tonal energy. `forward_masking_ratio` retains a bounded fraction of the preceding granule's band energy. `Mp3EncoderPsychoacousticTimeline` owns that per-channel history, handles long and short layout transitions by restarting unmatched bands, publishes a complete frame transactionally, and resets explicitly at discontinuities. Its `valid` query rejects malformed configuration, noncanonical absent history, invalid retained band evidence, and a right-channel history without the left-channel history that frame-order publication necessarily creates first. `Mp3EncoderPsychoacousticConfig.production` enables both policies, while the default keeps the earlier energy-mask thresholds for source compatibility. `Mp3FrameEncoder`, the block classifier, both retained analysis banks, and `Mp3EncoderAnalysis` expose matching validity queries. `Mp3PcmEncoder.valid` composes them and binds configuration, frame counters, and active-channel masking history before encoding. `Mp3PcmEncoder.initWithPsychoacoustics` selects either policy. VBR analyzes each input frame once and reuses the same masking evidence for every bitrate candidate, so candidate count cannot advance temporal history or change its thresholds.

Joint-stereo encoding accepts mid-side, intensity, or combined signaling. Intensity preparation evaluates the high-frequency scale-factor bands from the original left and right spectra, chooses the legal gain position with the lowest squared reconstruction error, stores one combined channel, and leaves lower bands independent or mid-side coded. Long, pure-short, mixed-short, MPEG-1, MPEG-2, and MPEG-2.5 layouts use their version-specific scale-factor compression and terminal-band rules. Malformed positions, nonzero intensity-side spectra, and plans attached to the wrong channel fail before quantization. The generated protected joint-stereo fixture carries gapless Info metadata and decodes to nonsilent stereo PCM through FFmpeg.

`Mp3MainDataReservoir`, `Mp3HybridSynthesis`, and `Mp3PolyphaseSynthesis` expose `valid` for retained byte bounds, finite overlap, finite synthesis history, and the polyphase ring head. `Mp3FrameDecoder.valid` composes those checks with the retained stream format and requires unused channels to remain canonical. Decode applies the complete validator before CRC, reservoir, or transform work, so malformed public state fails without mutation.

`Mp3GaplessPlan.valid` checks the identity between encoded, leading, trailing, and audible sample counts. `Mp3StreamDecoder.valid` composes that plan with a supported MP3 sample rate, channel count, nested frame-decoder state, consumed sample extent, and the retained-format phase. Decode and finish reject malformed retained state before frame or range processing. Reset preserves the plan and declared format while returning the nested decoder and sample cursor to their canonical initial state.

The Linux interoperability gate decodes independent FFmpeg, LAME, and Shine streams through the project and independent reference paths. Shine output without an optional Info frame matched 32,256 interleaved samples with `4.02e-7` peak error and `2.99e-7` normalized RMS error. A CRC-protected LAME stream matched 30,870 samples with every frame checksum validated, `3.73e-7` peak error, and `3.69e-7` normalized RMS error. A 320 kb/s LAME free-format stream matched LAME's decoder across 30,870 samples with `2.1026e-5` peak error and `8.0562e-5` normalized RMS error. FFmpeg rejects that free-format input and is not used as its PCM oracle. A separate probe inserts bounded inter-frame junk into an external FFmpeg stream and requires transactional recovery to reproduce the uninterrupted decoded PCM evidence. The low-rate matrix includes independent libmp3lame MPEG-2 and MPEG-2.5 joint-stereo input plus project-generated MPEG-2 and MPEG-2.5 intensity-stereo output. Project-generated CRC-protected MPEG-2 mono and MPEG-2.5 stereo streams extend checksum validation across every supported version. Every path requires complete project memory and positional decoding. FFmpeg comparison is mandatory when the Linux tools are available.

`Mp3VbrPcmEncoder` tests the configured bitrate-index range in ascending order and chooses the first quantization within `maximum_noise_to_mask_ratio`. If no successful candidate meets that limit, it emits the highest successful candidate with `quality_met` false and the measured ratio. `encodeAtBitrateIndex` forces one in-policy rate for metadata or application policy while retaining the shared padding cadence. Its `valid` query composes every nested encoder check and binds configuration, counters, bitrate histogram, padding count, byte count, masking policy, and active-channel history. `Mp3VbrPcmStreamEncoder` stores frame starts in caller-owned `u64` storage, flushes the analysis delay, and builds a 100-entry Xing table from final byte positions. Its `valid` query additionally checks caller-owned frame offsets, quality evidence, input-sample accounting, metadata state, and finalization. `startXingMetadata` advances analysis with one independent silent frame. `xingMetadataFrame` replaces it with final frame and byte counts, optional quality, table entries, the project encoder identifier, and compatible delay and padding fields. `Mp3VbrPcmFileEncoder` commits complete positional frames, patches Xing metadata before synchronization, truncates failed finalization output to the last committed boundary, and restores a provisional Xing frame for retry. Its `valid` query composes stream validity with frame-storage capacity, byte accounting, and finalization.

`Mp3VbrPcmReservoirEncoder` composes content-driven rate selection with the bounded one-frame main-data reservoir. Each append returns stable selection evidence separately from the delayed output frame. Pending storage starts deterministically and is scrubbed on reset. Its `valid` query checks the complete nested VBR encoder, pending-frame identity and integrity, receive and emission counts, version-aware cumulative borrowed-byte bounds, bitrate policy, and finalization phase. When a frame is pending, its encoded backpointer must fit within the cumulative borrowed total, and the remaining total must be reachable by the preceding frames. `Mp3VbrPcmReservoirStreamEncoder` retains caller-owned frame offsets, emits an independent Xing placeholder before reservoir priming, flushes the analysis delay through the same delayed path, and reports quality plus borrowed-byte totals. Its pending storage also starts deterministically, and its `valid` query binds that pending-frame phase and borrowed total to the complete VBR stream state. `Mp3VbrPcmReservoirFileEncoder` writes only finalized frames, derives its exact committed boundary by excluding the pending frame, restores a changed frame offset after a failed append, and supports provisional Xing restoration and retry after partial finalization. Its `valid` query adds caller-storage capacity, exact emitted-byte accounting, and file finalization to the nested stream contract.

`requiredMp3VbriTocBytes` and `buildMp3VbriToc` derive an exact caller-owned VBRI table from validated frame starts, a finished stream byte count, a frame grouping, a scale, and a 1–4 byte entry width. The builder rejects nonmonotonic offsets, inexact scaling, entry overflow, storage overlap, and capacity failures before changing the table. `encodeMp3VbriFrame` writes a silent first frame with checked version-1 VBRI counts and table fields. `finalizeMp3VbriStreamMetadata` scans a complete memory stream into caller-owned offset and table storage, requires a reserved first audio frame, stages its replacement, and leaves the stream unchanged on failure. Emission requires nonzero segments, complete declared-frame coverage, and cumulative table bytes within the declared stream size. It rejects protected frames because VBRI's fixed byte-36 location overlaps protected MPEG-1 stereo side information.

The MP3 interoperability gate also scans an independently encoded FFmpeg/LAME stream, derives an exact four-byte-per-frame VBRI table from its audio-relative frame positions, and replaces only the stream's first reserved metadata frame. The project decoder must accept the resulting external-audio stream and expose matching VBRI counts. FFmpeg must independently decode it to nonsilent PCM. This checks metadata composition with externally encoded audio; it is not evidence for VBRI metadata authored by an independent encoder.

`writeMp3Id3v2FilePrefix` validates and writes one complete ID3v2.2, v2.3, or v2.4 prefix. The `initAt` constructors on all four CBR, VBR, ordinary, and reservoir file encoders preserve that prefix and keep MP3 stream counts, VBR indexes, metadata patches, and recovery checkpoints relative to the first audio byte. `appendMp3Id3v1FileTail` replaces a stale or partial tail at the exact checked audio boundary, writes one complete 128-byte ID3v1 record, and synchronizes the result. Prefix and tail writes are retryable because each attempt restores its canonical boundary before publication. Invalid tags and offset overflow fail before changing the file.

`requiredMp3SeekPoints`, `buildMp3SeekIndex`, and `findMp3SeekPoint` build a caller-owned positional index at a selected frame stride. Index output may not overlap the encoded source. `Mp3FileReader` provides the same parser and free-format inference through positional file reads and caller-owned frame storage. It exposes the matching `valid` contract, including the completed-frame byte-progress bound. Iteration, recovery, and seeking reject malformed retained state before positional I/O. Its cursor and counters commit atomically after complete frame and metadata parsing. `nextTransactional` reads through disjoint caller scratch and publishes both reader state and destination bytes only after a complete frame succeeds. It rejects overlap and preserves the destination on malformed input, late truncation, and either buffer-capacity failure. Borrowed VBRI table bytes are rebound to the published destination rather than the scratch buffer. File index output may not overlap frame scratch, and the second construction scan bounds every write if a concurrently changed file contains more seek points than its sizing scan. `buildMp3FileSeekIndexTransactional` stages that second scan in caller-owned point scratch, then replaces the destination only after the count and complete file remain valid. Its file index helpers scan without loading the complete file. `seek` validates the selected header, frame-to-sample relationship, reachable byte offset, complete metadata, side information, and any protected CRC before changing reader state. File reads do not change the shared file cursor. `Mp3Stream.resynchronize` and `Mp3FileReader.resynchronize` scan forward by an explicit caller limit and apply the same complete candidate checks. They preserve frame and sample counters and leave all state unchanged if no recovery point exists. Deterministic positional tests mutate every byte of a retained second frame under three masks and truncate it at every boundary. Any rejected transactional frame leaves both complete reader state and destination storage unchanged. Complete decoder composition, CBR and VBR encoding, intensity stereo, one-frame encoder reuse, adaptive multi-frame CBR and VBR batch encoding, incremental adaptive CBR and VBR publication, recoverable incremental and atomic batch file output, exact gapless adaptive Info and Xing composition, and transactional transport repacking are available. The exact-gapless adaptive stream coordinators reserve metadata outside reservoir credit, flush the analysis delay through disjoint caller staging, restore the retained window on failure, and reproduce the matching batch stream byte for byte. Their positional-file wrappers preserve the committed boundary and reserved placeholder across append, delayed-tail, metadata-rewrite, and sync failures. Public sizing functions report the finish-staging bytes and final VBR offset count before initialization. A VBR writer that exhausts its offset slice rejects the current PCM frame without file mutation and can replace that slice transactionally before retrying. Retained offsets must begin at zero, increase strictly, remain below the committed byte count, and delimit exact frame lengths allowed by the configured bitrate range. CBR derives final Info metadata from retained counters. VBR derives its Xing seek table without loading the completed file. Deterministic generated interoperability fixtures cover protected MPEG-1 joint stereo with gapless metadata, VBRI metadata, MPEG-2 mono, MPEG-2 and MPEG-2.5 intensity stereo, protected MPEG-2 mono, and protected MPEG-2.5 stereo through both memory and positional project decoders. The external runner compares every generated PCM path with FFmpeg when it is installed. Additional independent encoders and decoders and audition remain separate work.

`Rf64FileWriter`, `Bw64FileWriter`, and `Wave64FileWriter` provide 64-bit file-backed containers with PCM16, PCM24, PCM32, and IEEE f32 encoding. RF64 and BW64 emit their distinct container signatures, mandatory `ds64` sizes, and classic RIFF sentinel values through one shared implementation. `makeBw64Header` provides the bounded header form, while `initBw64`, `initBw64WithMetadata`, and `initBw64WithRiffMetadata` provide incremental output. Wave64 emits the standard RIFF, WAVE, format, and data GUIDs with eight-byte chunk alignment. `Wave64Metadata` adds the registered BEXT and LIST/INFO GUID chunks defined by the [Sony Wave64 specification](https://mab.greyserv.net/f/sony_wave64.pdf). The writer does not invent GUIDs for iXML, aXML, or CHNA, which are not registered by that specification. The writers maintain 64-bit frame and byte counts, expose recovery after an interrupted header update, and validate a complete append before file mutation. Every recovery I/O failure leaves the writer in an explicit failed but recoverable state.

`AudioFileReader` opens caller-owned WAV, AIFF, uncompressed AIFC, RF64, BW64, or Wave64 files, validates their declared chunk boundaries and format arithmetic, and reads arbitrary complete frame ranges into interleaved `f32` or `f64` output. It supports PCM16, PCM24, and PCM32 in every container, plus IEEE f32 in the RIFF-derived containers. AIFC accepts the `NONE` compression type and validates its compression-name bounds. The reader exposes `valid` for its complete public channel, frame-width, frame-count, data-extent, and container byte-order state. Every PCM and metadata entry point applies that contract before division, modulo, slicing, or positional I/O. Ordinary reads may retain complete chunks decoded before a later positional-I/O failure. `readInterleavedTransactional` stages the requested range in disjoint caller scratch and commits only after the complete read succeeds. Reads use fixed staging storage and positional file I/O, so the reader does not allocate or change the shared file cursor. Positional chunk offsets and Wave64 eight-byte alignment use checked `u64` arithmetic. Deterministic file tests mutate every byte under three masks for all six supported containers and test every strict truncation prefix. Accepted variants remain valid and bounded, failed transactional reads preserve caller output, and every truncated container is rejected during initialization. `requiredMetadataChunkBytes` reports the exact destination size before `readMetadataChunk` retrieves a complete BWF, iXML, aXML, CHNA, or INFO chunk from WAV, RF64, or BW64. `readMetadataChunkTransactional` stages that chunk in disjoint caller scratch, including Wave64 canonicalization, and preserves the destination after every failure. The same APIs canonicalize registered Wave64 BEXT and LIST/INFO chunks into RIFF-shaped borrowed views, including validation of the eight-byte outer alignment. `requiredAdmMetadataBytes` preflights both aXML and CHNA destinations. `readAdmMetadata` rejects incomplete pairs, overlapping buffers, or either short destination before writing either buffer, then returns the validated typed pair. `readAdmMetadataTransactional` stages and validates both chunks in four mutually disjoint buffers before committing either destination.

`encodeInterleavedFlac` writes signed 8-, 16-, 24-, or 32-bit interleaved PCM to caller byte storage. It chooses constant, verbatim, or order 0 through 4 fixed-predictor subframes per channel and searches the standard Rice parameter range for the smallest residual representation. Every direct encoder validates the format before channel arithmetic and rejects overlap between its written destination prefix and source PCM or any borrowed Vorbis-comment descriptor, vendor, name, or value before mutation. Streaminfo records frame bounds, total samples, and the PCM MD5 digest. Every frame carries a checked header CRC-8 and frame CRC-16.

`decodeInterleavedFlac` validates metadata and complete frame boundaries before returning caller-owned interleaved `i32` samples. Before decoding, it relates the encoded audio extent to the frame-count interval implied by STREAMINFO block and frame-size bounds. Too-short input retains `TruncatedFlac`; an impossible oversized declared extent returns `InvalidFlacFrameSize` before output mutation. It decodes constant, verbatim, fixed-predictor, and LPC subframes, both Rice methods, escaped residual partitions, wasted bits, and left-side, side-right, or mid-side stereo. Invalid fixed-predictor orders return `InvalidFlacPredictorOrder` in both encoding and decoding. The ordinary direct decoders may retain samples written before a later frame or digest error. `decodeInterleavedFlacTransactional` stages the complete result in caller scratch and leaves the destination unchanged on every failure. Direct and file-backed decode APIs reject overlap among encoded input, decoded output, decoded-frame scratch, and wide side-channel scratch before parsing, positional reads, or output mutation. The bounded convenience functions `writeInterleavedFlacFile` and `readInterleavedFlacFile` use caller storage for the complete encoded file. Complete and range transactional read variants provide the same rollback contract, and wide-scratch variants cover 33-bit stereo side channels. These are offline file utilities, not audio-callback streaming primitives.

`FlacFileWriter` incrementally writes PCM blocks with caller-owned pending-sample and encoded-frame storage. `requiredFlacPendingSamples` and `requiredFlacFrameStorageBytes` size those buffers. The buffers and append source must remain disjoint. Every append preflights its worst-case encoded extent before retaining new pending samples, and each frame commit uses checked byte, sample, frame-number, and seek-table offsets. Its `valid` query means that the writer currently accepts more PCM, so a finalizing writer can remain recoverable without being append-valid. Recovery also verifies that committed sample and frame counts, encoded byte extent, and minimum and maximum frame sizes describe one reachable stream state. Finalization writes a short terminal block when needed, patches STREAMINFO totals, frame sizes, and the PCM MD5, and synchronizes the file. `initWithOperations` routes initialization, frame commits, recovery truncation, STREAMINFO patches, and final synchronization through the same injectable positional I/O contract as the PCM writers. A failed frame, final header write, or sync retains enough state to retry finalization after recovery. `initWithMetadata` composes validated Vorbis comments with a bounded reserved seek table. Committed frames fill points at the selected interval, while unused capacity remains as standard placeholders.

`FlacFileReader.requiredMetadataBytes` and `requiredFlacFileReaderMetadataBytes` scan positional metadata headers and report the exact caller storage needed for retained blocks. `FlacFileReader.init` retains Vorbis comments plus seek points in that buffer without depending on their file order. `FlacFileReader.initTransactional` stages those blocks in separate caller scratch, validates the complete metadata and every seek target, then copies the retained bytes and rebinds both borrowed views. Capacity, overlap, malformed metadata, truncation, and late seek-validation failures leave the destination unchanged. The reader exposes `valid` for its stream description, audio extent, comments, seek payload, and every active seek target. Its audio-extent check derives the possible encoded-frame-count interval from total PCM frames and block-size bounds, then requires the file bytes to fit any declared nonzero frame-size extrema. Seek validation applies the same bounds to the complete frames preceding each sample target and its audio-relative byte offset. A seek point shorter than the minimum block must reach the exact terminal sample. `commentIterator` and `seekTableIterator` return borrowed typed views over the storage and contain corrupted public reader, cursor, or payload state. Comment iteration also requires the public vendor slice and remaining count to match an exact boundary in the retained payload. Seek iteration revalidates ordering, positive frame lengths, and terminal placeholders before returning a point. Complete and range decoding validate the public stream layout, retained metadata, seek extents, and caller buffer separation before arithmetic or output mutation. Complete decoding reads one compressed frame at a time, validates every frame CRC and the whole-stream PCM MD5, and accepts optional caller-owned 33-bit side scratch. `decodeRange` uses the nearest preceding point with separate compressed-frame and decoded-frame scratch. `decodeTransactional` and `decodeRangeTransactional` stage their results in caller output scratch, so late positional-I/O, frame, checksum, and digest failures leave the destination unchanged. Deterministic positional tests mutate every encoded byte under three masks and test every truncation prefix while requiring failed initialization or decoding to preserve the destination.

`encodeInterleavedFlacWithComments` adds one checked FLAC Vorbis-comment block. `FlacCommentIterator` returns borrowed vendor, field-name, and UTF-8 value slices without allocation. Its `valid` query checks the complete payload, exact vendor provenance, and whether the retained cursor and remaining count form a reachable iteration boundary. Rejection and late field errors leave iteration state unchanged. Field names accept printable ASCII except `=`, and duplicate or malformed metadata blocks are rejected. `FlacMetadata` and `encodeInterleavedFlacWithMetadata` compose comments and a seek table in one checked file.

`encodeInterleavedFlacWithSeekTable` adds sorted seek points at a caller-selected encoded-frame interval. `FlacSeekTableIterator` validates strictly increasing sample numbers and byte offsets, uniqueness, positive frame lengths, terminal placeholders, and declared target bounds before returning borrowed points. Stream parsing additionally verifies that each target has a CRC-valid frame header whose coded frame or sample number and block length match the seek entry. Normal decoding and seek validation share that header parser. The iterator's `valid` query revalidates the full public payload and contains a malformed extent or cursor that is not aligned to a complete point. `decodeInterleavedFlacRange` uses the closest preceding point and caller-owned frame scratch to decode a requested interleaved range. Its transactional counterpart stages the requested output in separate caller scratch before committing any samples. `readInterleavedFlacFileRange` provides the ordinary range contract after loading a bounded file into caller storage. Range decoding validates each decoded frame CRC, but it cannot verify the whole-stream PCM MD5 unless the complete stream is decoded.

The simple decode functions reject a 32-bit stereo decorrelation frame whose side subframe needs 33 bits. `decodeInterleavedFlacWithWideScratch` and `decodeInterleavedFlacRangeWithWideScratch` accept one caller-owned `i64` sample per maximum frame and decode the full FLAC stereo range without allocation. Both transactional forms also have wide-scratch variants. Equivalent file-range support is available through `readInterleavedFlacFileRangeWithWideScratch`.

External Xiph parity remains separate work. File-backed append and recovery now share validated exact or aligned checkpoints while retaining format-specific header, sequence, pending-block, and seek-table commits.

`OggStreamWriter`, `OggPageIterator`, and `OggPacketIterator` implement bounded Ogg version 0 framing from [RFC 3533](https://www.rfc-editor.org/rfc/rfc3533.html). They cover lacing, zero-length terminators, packets continued across maximum-size pages, BOS/EOS flags, stream serials, page sequences, granule positions, and the Ogg CRC polynomial. The memory writer validates its retained byte count, lifecycle flags, and page-sequence reachability before append, exposes that state through `valid`, and returns an empty byte view for hostile state. Page reachability uses the format's minimum and maximum encoded page sizes and permits exact 32-bit sequence rollover. Both memory iterators also expose `valid`; packet validation includes its nested page lifecycle plus retained page, segment, body, and packet extents. The shared page lifecycle requires serial and expected-sequence presence to agree, forbids continuation before a stream begins, confines a later logical-stream index to chained readers, and permits the serial-free EOS checkpoint used to reload a chained BOS page after a capacity failure. Page parsing is transactional, so a rejected page does not advance continuation, sequence, EOS, or chained-stream state. Packet assembly also commits its page and segment cursors only after a complete packet is available, which permits retry with larger caller storage after a late capacity failure. `OggPacketIterator.nextTransactional` additionally stages the packet in disjoint caller scratch, preserving the bound destination and iterator on malformed input, insufficient scratch or output capacity, and overlap. Its returned bytes borrow the bound destination. Corrupted public cursors and packet-count rollover return errors without slice traps or partial advancement. `OggFileWriter` incrementally writes the same pages through caller-owned maximum-page storage. It applies the same retained page-state validation, validates complete packet framing before mutation, retries short positional writes, restores partial packets through the shared exact checkpoint, and exposes failed but recoverable state when rollback truncation fails. `finalize` requires an EOS packet and synchronizes through the retained operations backend. An injected sync failure leaves finalization retryable without rewriting the completed stream. `OggFilePageReader` and `OggFilePacketReader` provide the same validation through positional file reads with caller-owned page and packet storage. Both expose `valid`; packet validity accepts the current page and packet storage so it can verify retained bindings and active borrowed page slices. The file page reader rejects past-end cursors and inconsistent serial, sequence, continuation, or end state before positional reads. Its `nextTransactional` method stages one complete page in disjoint caller scratch, then commits the reader and destination together. Malformed input, truncation, insufficient output or scratch, and overlap preserve both, while returned lacing and body slices borrow the destination. The file packet reader validates its nested page lifecycle, paired storage bindings, retained page and reload cursors, packet capacity, and counters before optional dereferences or slice indexing. At each packet boundary it retains an allocation-free positional checkpoint. A late capacity failure clears the old storage bindings and reconstructs the page parser state to reload a multi-page packet or a packet that began midway through a chained BOS page. Retrying with larger storage preserves global and logical packet indexes plus seek-skip accounting. The `initChained` reader variants accept sequential logical streams, restart serial and page-sequence validation only after a complete EOS page, and attach a logical-stream index to each page and packet. Both page readers can scan past a caller-bounded run of inserted bytes. A candidate must pass complete page and CRC validation while preserving the expected serial, sequence, continuation, and chained-stream state. Failed scans leave the reader unchanged. The positional path uses caller storage large enough for one maximum-size page. Resynchronization does not conceal a missing or corrupt page because a sequence gap remains an error.

The memory writer rejects packet input that overlaps its destination before changing either. A memory packet reader's logical count cannot exceed its global count. Its bound output and transactional scratch must not overlap the encoded stream. A positional reader permits independent counter origins after seeking, requires pending skips to fit its remaining logical range, and may finish exactly at the saturated count. Any further packet reports overflow without committing reader state. `OggFilePacketReader.nextTransactional` assembles into retained page and packet scratch, then copies a complete packet into a disjoint destination and rebinds the returned byte slice. Malformed input, truncation, insufficient destination, and overlap preserve destination bytes. Insufficient packet scratch also preserves the destination while installing the same allocation-free retry checkpoint as ordinary iteration.

`VorbisPacketWriter` exposes `valid`, rejects a writable bit cursor beyond caller storage before mutation, and returns an empty byte view for hostile or count-only state. Count-only sizing remains allocation-free and does not expose a borrowed output view.

The memory and positional-file packet readers expose the same bounded recovery at a narrower boundary. A complete packet must have exhausted its page, so recovery cannot discard another available packet from the current page. Successful recovery preserves global and logical packet counters. Mid-page, partial-packet, reload, storage-binding, scan, and candidate failures preserve reader state.

`VorbisIdentification`, `VorbisCommentIterator`, and `VorbisHeaders` validate the three required header packets from the [Vorbis I specification](https://xiph.org/vorbis/doc/Vorbis_I_spec.html). The comment iterator exposes `valid` for its complete remaining field and framing extent. It reconstructs the parsed prefix to require an exact field boundary, matching remaining count, and exact vendor provenance. Failed iteration leaves its retained cursor, count, and borrowed view unchanged. `encodeVorbisIdentificationPacket` serializes checked channel, sample-rate, bitrate-hint, and legal block-size fields. `requiredVorbisCommentPacketBytes` and `encodeVorbisCommentPacket` serialize a UTF-8 vendor and printable-ASCII named UTF-8 fields into caller storage. The encoded prefix must not overlap the comment descriptor array, vendor, names, or values. `requiredVorbisSetupPacketBytes` and `encodeVorbisSetupPacket` serialize the complete retained setup model, using canonical unordered codebooks and exact Vorbis packed floats. Setup overlap validation covers codebooks, entries, Huffman nodes, multiplicands, floors, residues, mappings, and modes. All three encoders validate capacity and borrowed input before mutation. Variable-length encoders also reject input that overlaps their output. Their packets can be appended directly through either Ogg writer.

`parseVorbisSetup` reads least-significant-bit-first fields without allocation and validates ordered, unordered, and sparse Huffman codebooks, lookup tables, both floor formats, all three residue formats, channel mappings, modes, framing, and component references. Canonical codewords, exact-size Huffman decode trees, sparse entry markers, lookup multiplicands, codebook summaries, floor configurations, and modes use caller-owned storage. `VorbisPacketReader.valid` checks its retained bit cursor with overflow-safe packet sizing. Every scalar, vector, floor, and residue decoder rejects an invalid cursor before changing the cursor or caller output. `decodeScalar` follows one tree branch per packet bit and preserves its cursor on truncated input or invalid codewords. It also handles the single-entry erratum. `decodeVector` reconstructs type 1 lattice and type 2 explicit vectors with Vorbis float unpacking and sequence accumulation.

`VorbisPacketWriter` emits least-significant-bit-first fields, checked audio headers, canonical scalar or vector codewords, Floor 0 and Floor 1 packets, and residue types 0, 1, and 2. Floor serialization finds compatible subclass paths from caller-provided quantized values. Residue serialization validates classifications and vector entries in exact decoder order, including skipped channels, partial classwords, cascades, and type-2 interleaving. `requiredVorbisAudioPacketBytes` and `encodeVorbisAudioPacket` compose mode flags, per-channel floors, coupling-propagated residue skips, and every mapping submap into one transactional packet. They accept already-quantized encoding decisions. `measureVorbisAudioPacketFixedCost` runs the same header and floor writer in counting mode, returns the exact fixed bit count, and transactionally publishes per-channel skip flags after retained coupling propagation. This is the fixed cost consumed by `allocateVorbisResidueBitBudgets`. `quantizeVorbisVector` finds the nearest active entry in retained lookup type 1 or type 2 vector codebooks, uses f128 squared-error accumulation, reconstructs sequence codebooks identically to the decoder, and resolves ties to the lowest legal entry. `quantizeVorbisVectors` performs the same operation across a flat vector sequence with aggregate error reporting, checked output capacity and aliasing, and whole-destination transactionality.

`requiredVorbisResidueQuantizationScratch` sizes caller-owned partition, vector, and classification work areas. `quantizeVorbisResidue` searches active classbook entries for the lowest-distortion representable classification group, simulates all active cascade passes, quantizes the evolving residual through retained vector books, and emits the exact classification and entry order consumed by `VorbisPacketWriter.writeResidue`. It handles type 0 deinterleaving, type 1 sequential placement, type 2 channel interleaving, skipped channels, partial classwords, sparse books, and unrestricted retained classbook dimensions. Selection and final error use f128 accumulation, equal-error decisions choose the lowest legal entries, and complete capacity and alias validation precede output mutation.

`quantizeVorbisResidueAdaptive` evaluates each representable classword group against caller-supplied per-bin masking thresholds. A bounded Lagrangian search trades weighted reconstruction error against exact scalar-codeword length, then returns the best masked plan within the requested residue budget. When no legal plan fits, it returns the lowest-rate candidate with `budget_met` clear instead of hiding the shortfall. The result includes unweighted and mask-weighted squared error, audible excess power, exact residue bits, the selected multiplier, and the number of search iterations. Trial and retained classifications remain in separate caller scratch so capacity, setup, threshold, and alias failures preserve both destination arrays. `allocateVorbisResidueBitBudgets` removes the fixed header and floor cost from a pending packet target, then distributes the remainder across submaps by finite nonnegative weights. Largest-remainder rounding preserves the exact packet target, with deterministic low-index ties and equal allocation when every weight is zero.

`requiredVorbisResidueQuantizationEntries` derives the exact maximum entry capacity from the active classbook sequence, including a partial final classword. `requiredVorbisAudioResidueQuantizationStorage` applies that calculation to every submap selected by an audio packet's mapping. `quantizeVorbisAudioResiduesAdaptive` groups channels by their retained mux assignments, allocates the exact residue target by caller weights, reuses caller scratch sized for the largest submap, and quantizes each mapped residue in order. It publishes retained classification and entry prefixes, borrowed packet-writer encodings, and per-submap bit and distortion evidence only after every submap succeeds.

`fitVorbisFloorOne` maps a finite target spectrum onto the retained Floor 1 control geometry. It searches active masterbook paths and subclass scalar entries, evaluates values through the decoder's exact integer prediction and unwrap rules, resolves equal-error choices to the lowest legal entry, and preflights the result through the packet writer. Silent input produces an unused floor without requiring output storage. Non-silent fitting accepts f32 or f64 input, reports squared control-point error, preserves unused destination capacity, and rejects retained-setup or target aliases before mutation. `requiredVorbisAudioFloorOneStorage` sizes a multichannel packet plan from the selected mode and channel mux. `fitVorbisAudioFloorOne` enforces a Floor 1-only automatic-analysis contract, fits every channel into separate trial storage, synthesizes flattened per-channel curves, and publishes retained encodings that borrow only from caller-owned retained Y-value storage. No retained output changes unless every fit and synthesis succeeds. Silent channels publish unused floors and zero curves. `normalizeVorbisResidue` divides a spectrum by the synthesized floor curve transactionally. It supports exact in-place normalization, rejects partial aliases and non-positive floor values, and composes with `applyVorbisFloor` for bounded reconstruction. `normalizeVorbisNoiseThresholds` applies the same floor normalization to strictly positive masking bounds, including exact in-place use and underflow containment.

`prepareVorbisAudioResidue` composes multichannel Floor 1 fitting, curve synthesis, active-channel residue and threshold normalization, magnitude-angle coupling, safe masking-bound propagation, fixed packet-cost measurement, and coupling-propagated skip flags. An unused floor receives a zero normalized target and maximum finite pre-coupling tolerance. A coupling step tightens that tolerance against the active branch before residue quantization, while an uncoupled unused channel remains skipped. Exact trial and retained capacities come from `requiredVorbisAudioResiduePreparationStorage`. Retained floor encodings borrow only from retained Y-value storage, and no retained output changes unless the complete preparation succeeds.

`decodeFloorZero` and `decodeFloorOne` decode retained floor configuration without allocation. Packet truncation produces the Vorbis-defined unused-floor result and consumes the remaining packet bits. Other failures preserve the cursor and caller output. Floor 0 accepts the full 63-bit amplitude field and bounded LSP coefficient reconstruction. Floor 1 supports masterbook and subclass selection. `synthesizeVorbisFloorZero` computes the Bark-mapped LSP response, while `synthesizeVorbisFloorOne` performs wrapped amplitude prediction, integer line rendering, and inverse-dB substitution for `f32` or `f64` output. Floor 1 fitting and synthesis share the same raw-value unwrap primitive.

`VorbisPacketReader.decodeResidue` decodes residue types 0, 1, and 2 into caller-owned `f32` or `f64` channel vectors. It implements classification words, all eight cascade passes, skipped floor channels, type 0 interleaving, type 1 sequential placement, and type 2 interleaved-channel placement. `requiredVorbisResidueClassifications` reports the exact caller scratch requirement. Output channels and scratch must not overlap. Validation failures preserve the cursor and output, nontruncation packet failures clear output and preserve the cursor, and nominal end-of-packet returns the decoded prefix with `truncated` set.

Setup storage also retains mapping submaps, per-channel mux assignments, and ordered magnitude-angle coupling steps. `forwardCoupleVorbisChannels` applies those steps in setup order for encoding, and `inverseCoupleVorbisChannels` restores channels in reverse order for decoding. Both operate through caller-owned scratch. Shape, mapping, finite-value, arithmetic, and alias validation complete before channel output changes. `forwardCoupleVorbisNoiseThresholds` simulates the same forward sequence from uncoupled residue values while propagating per-channel bounds. Each step halves the tighter incoming bound and clamps it inside the coupled magnitude's sign margin when the angle is nonzero. This keeps inverse quantization error on one continuous piecewise-linear branch and within the original channel bounds. Separate value and threshold scratch makes the complete multistep update transactional.

`parseVorbisAudioPacketHeader` validates the audio packet type, selects a retained mode, and reads the two long-window transition flags. `synthesizeVorbisWindow` renders checked small, large, small-to-large, and large-to-small windows directly into caller output. `VorbisWindowPlan` precomputes every transition window for realtime use.

`VorbisForwardMdct` and `VorbisInverseMdct` use radix-2 FFT reductions with precomputed twiddles and rotations for any legal 64- through 8,192-sample block. Their complementary bitstream scaling matches the codec's lapped transform convention: an unwindowed forward transform of inverse output produces twice the original coefficients. Both directions have windowed forms, allocate no memory, perform no processing-time trigonometry, permit input/output overlap, reject non-finite values, and preserve output on failure. `applyVorbisFloor` multiplies a residue spectrum by its floor after validating the complete operation.

`analyzeVorbisPcmBlock` compares mean-square energy across half-short-block segments of one multichannel large-block candidate. The configurable energy ratio is scale-independent above a configurable RMS floor. The result reports peak, RMS, maximum ratio, and the selected transient boundary, then recommends a short block for detected attacks or decays and a large block for stationary material. f128 accumulation keeps finite f32 and f64 inputs bounded. `selectVorbisEncodingMode` deterministically chooses the lowest retained mode matching a mapping and block size. `planVorbisEncodingBlock` validates the identification and setup, then derives the exact previous and next long-window flags and encoded header width.

`VorbisPcmBlockClassifier` adds stream history to the single-block analysis. It compares the current block power with a smoothed prior reference, enters short mode on either an internal transient or a configurable cross-block energy jump, and requires a lower stable ratio before returning to long mode. A bounded short-block hold prevents rapid mode chatter around a boundary. Its `valid` query covers canonical uninitialized state, finite nonnegative initialized power, and the invariant that a positive short-block hold cannot coexist with active large-block mode. Classification rejects malformed retained state before analyzing PCM, and the state update commits only after configuration, PCM, and arithmetic validation. `reset` restores deterministic first-block behavior.

`VorbisPcmBlockLookahead` retains one analyzed decision so the following decision can supply its right-window flag. Its `valid` query includes the nested frame planner, and prime, push, and finish reject malformed retained state before transition. `push` emits the pending frame and retains the next choice. `finish` emits the final frame with a same-size terminal neighbor, and failures preserve both pending analysis and frame position. `VorbisPcmFramePlanner` carries the previous block choice and advances signed block centers by one quarter of the current size plus one quarter of the next size. Its `valid` query covers the canonical initial cursor, requires the 16-sample alignment shared by every legal transition, and bounds every active center by the minimum and maximum progress possible for its retained packet count. Each plan reports its packet index, header, signed source start, PCM advance, and next center. Invalid retained state, setup, packet-count exhaustion, and position overflow preserve the complete planner state. `extractVorbisPcmBlock` copies a planned multichannel source window and zero-pads leading or trailing positions outside the stream. It validates channel shape, finite source samples, position arithmetic, and aliases before changing any output.

`VorbisPcmPacketSequence` coordinates the classifier, lookahead, frame planner, bit reservoir, packet index, and encoder granule without advancing live packet state during planning. Its `valid` query covers nested configuration and state, pending-phase coherence, packet and revision indexes, frame center, granule bounds, and terminal state. An active sequence also requires the classifier's selected block mode to match the lookahead decision awaiting publication. Once audio packets exist, validation requires the published granule to trail the frame center by a reachable window advance: 32 through 4,096 samples while active, or at most 8,192 samples after final trimming. Priming, planning, and commit reject malformed live state before publishing a transition. `planNext` returns a caller-owned trial containing the next classification, frame, budget, granule, and complete staged state. Commit verifies the staged frame geometry, block flags, cursor transition, classification metrics, classifier relationship, lookahead phase, reservoir budget, and granule range. Terminal plans must retain the live classifier exactly and cannot place EOS beyond the frame's completed center. An optional adaptive-rate policy combines normalized activity, internal or cross-block transient strength, and crest factor into a bounded packet-target scale before publishing the staged reservoir budget. Nonterminal granules describe PCM completed before the current packet, so the first packet has granule zero. `planFinish` flushes the delayed frame once and accepts an exact EOS length no greater than the terminal packet's completed center. `appendMemory` preflights the state commit and Ogg append through copies, then publishes both together. `appendFile` relies on the file writer's positional rollback and advances the encoder only after a successful append. Stale, forged, zero-bit, overflowing, out-of-order, or impossible terminal plans preserve every live state machine. Direct `commit` is available when another destination has already accepted the packet.

`requiredVorbisPcmPacketEncodingStorage` combines the exact preparation and mapping-driven quantization capacities for a planned frame. `encodeVorbisPcmPacketTrial` accepts a retained frame analysis and a live sequence plan, prepares Floor 1 and coupled residue data in trial storage, quantizes every mapped submap, counts the final packet, and preflights the exact reservoir commit against copied sequence state. It encodes the packet and publishes retained borrowed preparation and quantization plans only after every step succeeds. The live sequence remains unchanged until the caller passes the returned packet and original plan to `appendMemory`, `appendFile`, or `commit`.

`encodeVorbisPcmPacket` adds the complete PCM front end to the same trial contract. It extracts the planned frame with boundary padding, runs the configured multichannel forward transform and psychoacoustic analysis, then delegates floor preparation, coupling, adaptive residue quantization, and packet encoding to `encodeVorbisPcmPacketTrial`. `VorbisPcmPacketOrchestrationScratch` separates analysis scratch and retained analysis workspace from the packet destination and retained encoding storage.

`VorbisPcmBlockTransform` owns precomputed windows plus short and long forward MDCT plans. It transforms every channel for a planned header into caller scratch, then commits all coefficient outputs together. Inputs may overlap outputs because no output changes until every channel succeeds. Output channels must remain separate, and used scratch cannot overlap input or output. Both block sizes, all four long-window transitions, f32, and f64 use the same API.

`VorbisPcmFrameAnalyzer` composes planned source extraction, boundary padding, transition-window selection, normalized forward MDCT, and multichannel psychoacoustic analysis. `requiredStorage` reports the exact scratch and retained capacities for the frame header. The analyzer publishes flattened spectra, channel analyses, Floor 1 targets, and masking thresholds only after every stage succeeds. Returned slices borrow from retained caller storage. Trial planes, retained planes, input slice descriptors, and input samples must not overlap.

`analyzeVorbisPsychoacoustics` maps a finite normalized spectrum into configurable Bark-spaced bands. Per-band arithmetic and geometric power means produce spectral flatness and tonality. Tonal and noise masking offsets feed an asymmetric spreading model over Bark distance, while a normalized absolute threshold bounds empty regions. Quality scales a checked maximum relaxation in decibels. The function returns peak, RMS, global flatness, tonality, active-band count, and relaxation while transactionally producing a spectral envelope for Floor 1 fitting plus a per-bin noise threshold. Silent spectra produce zero targets and an unused-floor-compatible result. Input may overlap one output because all spectral statistics complete before output mutation.

`VorbisQualityPreset` exposes q0 through q10 and maps each integer level to the encoder's normalized quality control in exact 0.1 steps. `applyTo` changes only the quality field of an existing psychoacoustic configuration. The names follow the [Xiph encoder quality scale](https://xiph.org/vorbis/doc/vorbisenc/overview.html), but do not promise a bitrate or bitstream match. Content, setup, channel geometry, and encoder tuning still determine the resulting rate.

The deterministic q0, q5, and q10 calibration requires distinct streams and bounded decoded error and signal-to-noise measurements. Its report parser accepts exactly one finite numeric value per required field and rejects missing, duplicated, malformed, NaN, infinite, or overflowing evidence.

`VorbisPcmQualityMeter` measures decoded f32 or f64 PCM against a finite reference without allocation. Streaming updates report reference and candidate RMS, RMS and peak error, normalized RMS error, optimal candidate gain, gain-aligned normalized RMS error, and signal-to-noise ratio. Retained-state validation requires accumulated squared error and peak error to agree on whether any mismatch exists. Exact matches retain equal reference, candidate, and cross energy plus the canonical zero peak index. A silent reference or candidate retains zero cross energy and an error energy equal to the nonsilent side. Shape and sample validation completes before a trial update commits, so invalid input, arithmetic overflow, and malformed retained state preserve the meter. A silent reference has no normalized measurement and returns an error. Exact matches report infinite signal-to-noise ratio. These waveform metrics calibrate regressions, but they do not replace perceptual comparison or audition.

The concealment calibration applies the same meter to a clean periodic continuation, silent packet replacement, and retained-signal replacement in both float precisions. Silent replacement retains measurable error, while unity-gain signal replacement exactly reconstructs this controlled continuation. The result demonstrates one known improvement case without generalizing waveform error into a perceptual quality claim.

`requiredVorbisAudioPsychoacousticStorage` reports exact retained analysis and flattened value-plane capacities for a multichannel spectrum bundle. `analyzeVorbisAudioPsychoacoustics` validates every channel shape and coefficient before analysis, uses separate caller-owned trial targets and thresholds, and commits the analyses, Floor 1 targets, and masking thresholds together only after every channel succeeds. Returned prefixes borrow from retained storage, unused suffixes remain unchanged, and no spectrum or slice descriptor may overlap trial or retained storage.

`evaluateVorbisRateDistortion` compares reconstructed coefficients against those thresholds. It reports the maximum noise-to-mask ratio, summed weighted squared error, power above the mask, and whether the complete block remains masked. A nonzero error against a zero threshold returns explicit infinite distortion.

`adaptVorbisPacketBitBudget` exposes the optional sequence policy as a pure decision function. Caller-selected quiet and full-activity RMS references, transient and crest saturation points, complexity weights, and minimum and maximum target scales remain explicit. The returned evidence reports every normalized component, the combined complexity, the applied scale, and the adjusted budget. The target is rounded deterministically and clamped to packet limits plus the exact reservoir interval that would permit a same-size commit. Invalid analysis, policy, retained balance, arithmetic, or an empty feasible interval returns an error without mutable state.

`VorbisQualityRateController` feeds committed packet evidence back into the next psychoacoustic quality value. A packet above its target or a residue plan that missed its budget lowers quality by one caller-selected step. The basic `observeCommit` path raises quality whenever the packet has the selected headroom. `observeSignal` instead consumes the encoder's complete per-submap distortion results: clean masked output holds even with unused rate, audible excess raises quality only when that headroom can support it, and audible excess without headroom holds. `observePcmPacketTrial` binds that policy directly to a retained encoder trial after checking its frame, fixed-plus-residue allocation, submap target total, packet identity, and committed bit count. Explicit minimum, maximum, initial, step, and headroom values keep product policy outside the codec. Reported actions describe an actual quality change, so pressure at either configured limit reports a hold. `applyTo` copies the current quality into a psychoacoustic configuration, and `reset` recovers the initial quality after a retained-value fault when the controller configuration remains valid.

Vorbis encoding treats its count, preflight, and publication passes as checked boundaries. A mismatch in comment sizing, setup sizing, packet bits, residue entry consumption, Floor 1 storage, or retained floor type returns an error. Invalid block exponents also return an error. These paths do not rely on production assertions or unreachable branches, so malformed caller state and an internal pass disagreement remain process-contained.

`VorbisBitReservoir` converts each frame's exact PCM advance into a rounded nominal packet budget at the configured bitrate. Credit from undersized packets and debt from oversized packets feed the next target over a configurable correction window. Minimum and maximum packet bounds remain explicit. Its `valid` query covers configuration, capacity, packet-index coherence, and every retained pending-budget field. Planning, commit, and cancellation share that validation. One budget may be pending at a time, successful commits advance packet state, cancellation discards only a valid pending budget, and capacity violations or corrupted pending state preserve the reservoir for a lower-distortion retry. Use `allocateVorbisResidueBitBudgets` to derive per-submap adaptive quantizer targets after measuring the fixed packet cost.

`VorbisOverlapAdd` retains one windowed block and returns the exact sample range between consecutive block centers. It handles every legal short/long transition, primes without emitting the first block, and contains invalid state, aliasing, non-finite samples, and overflow before changing output or retained history. Its previous and pending storage starts deterministically, and reset scrubs both buffers before clearing the retained extent. Its readiness and previous-block-size accessors fail closed when the retained extent or active history is malformed. `VorbisChannelOverlapAdd` validates matching retained history across every channel and prepares every channel before committing any channel, so a malformed channel cannot advance part of a multichannel stream.

`VorbisAudioPacketDecoder` composes floor decoding, nonzero propagation, submap residue bundles, inverse coupling, floor application, transition windows, and inverse MDCT. `requiredVorbisAudioPacketScratch` reports the exact spectrum, floor, coupling, time-domain, and classification capacities. Large classification storage remains caller-owned, and packet failures preserve all channel outputs.

`VorbisGranuleTracker` converts finished overlap ranges into signed PCM positions. Its `valid` query covers the signed decoded-sample limit, canonical empty state, the required known offset after end-of-stream, and a representable nonnegative current PCM endpoint whenever the offset is known. Trimming rejects malformed retained state without mutation. It handles inferred negative or positive starts, delayed first granules, short streams, and final-page tail trimming. `VorbisPcmStreamDecoder` combines packet decoding, atomic multichannel overlap, granule trimming, priming, reset, and EOS containment for one retained setup. Its `valid` query covers nested overlap and granule state, decoded and concealed packet counts, priming, terminal coherence, and the 32-to-4,096-sample overlap progress possible for every packet after the priming packet. Decode and concealment reject malformed live state before processing a packet. Returned samples occupy the prefix of each caller output channel. Strict decode continues to reject invalid packets. When a transport or product has independently established the missing block size, `concealMissingPacket` can explicitly insert one silent block through the same overlap and granule timeline. `concealMissingPacketUsingPreviousBlockSize` instead selects the configured small or large size from the retained preceding block. It returns `VorbisPreviousBlockSizeUnavailable` without mutation when no history exists. `concealMissingPacketUsingFollowingHeader` uses `inferVorbisMissingPacketLargeBlock` to read a following large packet's previous-window flag. The helper validates the following header and returns `VorbisFollowingPacketBlockSizeUnavailable` when a following small packet cannot disambiguate mixed block geometry. For that remaining case, `concealMissingPacketUsingFollowingGranule` compares the small and large overlap timelines against the exact granule immediately after a nonterminal following packet. It requires an established PCM position and rejects end trimming, missing evidence, inconsistency, and arithmetic overflow.

Signal replacement remains opt-in. `concealMissingPacketWithPreviousSignal` center-aligns the retained windowed block to an explicit missing size and applies caller-selected linear decay from `initial_gain` to `final_gain`. `concealMissingPacketUsingPreviousBlockSignal` also derives the size from the retained block. Gains must be finite, lie from zero through one, and must not increase across the replacement. Rejected settings preserve decoder, output, and scratch state. Centered crop or zero padding preserves sample timing across mixed block sizes. Each accepted replacement becomes the next retained block, so consecutive losses decay without a separate counter. The chained decoder exposes matching operations with checked global positions. Silence remains the default policy.

`VorbisChainedPcmStreamDecoder` owns the reset and transition contract across sequential logical streams with matching channel count, block geometry, and sample rate. Its `valid` query covers the nested stream, canonical not-started state, retained sample rate, checked global timeline, and the exact emitted count for an active stream or a bounded count after final trimming. Logical-stream transitions, decode, and concealment reject malformed live state before mutation. It rejects a new logical stream before EOS, reports the logical-stream index, and adds each emitted range to one checked unsigned PCM timeline. Header and setup parsing remain caller-owned because each logical stream carries independent codec headers.

`requiredVorbisSeekPoints` and `buildVorbisSeekIndex` scan an in-memory chained stream into caller-owned points. Their file-backed counterparts use caller-owned page storage and positional reads. `buildVorbisFileSeekIndexTransactional` stages the complete second scan in caller-owned point scratch, so truncation, malformed pages, capacity changes, or a changed point count cannot partially replace the destination. Its page buffer, destination, and point scratch must be pairwise disjoint. Each point records the page and packet identity for the target granule plus the preceding audio packet needed to prime overlap. `findVorbisSeekPoint` selects within one logical stream, and `OggFilePacketReader.seek` validates and repositions transactionally before discarding earlier packet completions on the start page. After resetting the PCM decoder, decode from the selected prime packet and pass each result through `VorbisPcmSeekCursor.select` until it returns the suffix at the requested signed PCM position. The index is not a substitute for parsing and retaining the three headers of each logical stream.

An end-to-end test writes identification, comment, setup, and audio packets into Ogg pages, parses them back, retains setup, builds matching memory and file seek indexes, repositions the file reader, and decodes the requested PCM suffix. Header integration tests generate all three packets through the public encoders, paginate them, and parse the result through `VorbisHeaders`. Setup round trips cover ordered, unordered, sparse, and deep codebooks, both lookup forms, 1–16-bit multiplicands, floor types 0 and 1, every residue and mapping field, channel coupling, submaps, modes, packed-float validation, capacity, and overlap preservation. A generated stereo audio packet crosses two submaps and one coupling step before decoding through the complete packet pipeline. Planned residue fixtures round trip all three layouts, classbook-constrained classification, skipped channels, and multi-pass reconstruction through the packet writer and decoder. Adaptive fixtures prove exact high-quality selection, lower-rate fallback, impossible-budget reporting, mask-weighted metrics, both float precisions, exact weighted submap allocation, equal-weight rounding, capacity preservation, invalid thresholds and configuration, and alias rejection. Mapping-driven fixtures group two independently mapped submaps, derive exact active-classword entry capacity, reuse bounded scratch, publish borrowed encodings and per-submap evidence atomically, compose with packet-writer cost measurement, and preserve retained state on late threshold, capacity, and alias failures. Floor fixtures fit both float precisions, round trip raw values through packet encoding and decoding, synthesize the retained curve, normalize signed residue, and reconstruct the original spectrum. Multichannel floor fixtures prove exact storage sizing, active and silent channel publication, retained borrowed ranges, fixed-cost skip composition, complete rollback, suffix preservation, Floor 0 rejection, capacity errors, and storage aliases. Mixed-silence preparation fixtures also prove fitted-floor reconstruction after normalization and coupling, safe threshold propagation, and transactional failure after floor fitting. PCM analysis fixtures distinguish stationary material from multichannel attacks, stabilize cross-block energy jumps through hysteresis and a bounded hold, schedule decisions through one-block lookahead, plan mixed short and long center sequences, zero-pad stream boundaries, and match direct windowed transforms across block transitions. Sequence fixtures prove non-mutating packet trials, stale and hostile-plan rejection, memory and file append rollback, exact terminal flush, and EOS granule publication for f32 and f64 analysis. Composed encoding fixtures bind a retained frame analysis to a live sequence revision, prepare and quantize through trial storage, preflight exact rate state, publish the final packet and retained borrowed plans together, and preserve packet, storage, and sequence state on capacity, alias, stale-plan, and reservoir failures. Psychoacoustic fixtures distinguish a sparse tone from a flat spectrum, prove monotonic quality relaxation, evaluate masked and audible reconstruction error, preserve aliased and failed outputs, and exercise packet credit, debt, clamping, cancellation, overflow, rate-only and signal-derived quality feedback, limit behavior, and hostile reservoir, controller, or submap evidence. Forward and inverse coupling fixtures cover every sign branch, magnitude ties, and dependent multistep mappings. Chained Ogg readers expose each new logical-stream boundary so the caller can parse its three headers and construct the matching typed decoder. The generated interoperability fixture carries used Floor 1 data, scalar classbook words, active lookup-type-2 vector residue, exact priming and output granules, and EOS through the public encoders. The repository gate uses FFmpeg when available. It decodes independent mono, stereo, 5.1, short, midpoint-seek, and chained external streams, compares exact sequential and positional f32 suffixes, and rejects checksum damage and truncation. The Linux gate also compares complete Xiph-decoded PCM for project-generated stereo and duplicated chains plus FFmpeg-encoded mono, stereo, 8 kHz stereo, 16 kHz mono, low-quality, 5.1, multi-page, and two-link chained streams. A Xiph-encoded 48 kHz stereo stream passes the project decoder, exact `oggdec` PCM comparison, and independent FFmpeg decoding. That exact comparison measured `1.5438e-5` peak error and `6.6227e-5` normalized RMS error across 33,600 interleaved samples. The staged Linux matrix also generates Xiph-authored 32 kHz mono at q0, requires its exact identification format, decodes it through the project and FFmpeg, and compares complete PCM with `oggdec`. The failure-injection runner requires all three paths. Live execution of this extension requires a Linux environment with Xiph and FFmpeg tools. The primary stereo comparison measured `1.5941e-5` peak error and `5.4986e-5` normalized RMS error. Chained reference output concatenates separately decoded logical inputs so both links are checked. On macOS the gate also uses AudioToolbox when `afinfo` can open Vorbis, requires a 48 kHz nonsilent PCM decode, and distinguishes an unavailable decoder from a later conversion failure. The pinned Xiph packet-loss gate removes complete packets outside the project and compares full decoded silence and retained-signal concealment output through exact terminal granule trimming. Its mono, stereo, and chained cases cover both block sizes, mixed neighboring geometries, and previous-block, following-header, and following-granule evidence. Additional implementation families and audition remain open.

`decodeMonoWav` reads bounded in-memory PCM16, IEEE f32, and IEEE f64 mono WAV fixtures. It is an offline test utility. It does not perform file access, allocate memory, or belong in an audio callback.

The repository fixture test generates its input and C++ reference renders, then compares Zig f32 and f64 output using fixed and randomized blocks:

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test-dsp-fixtures
```

The command records architecture, model, sample format, sample rate, backend, elapsed time per sample, and numerical metrics. It also enforces a 100 ns per sample regression ceiling. That ceiling detects major regressions while leaving room for translated and shared CI environments.

Use `zig build test-dsp-fixture-builds` to compile the fixture API for Linux aarch64, Linux x86-64, and Windows x86-64 without attempting to run cross-target binaries.

Retained Ogg packet pages must match the complete encoded page, checksum, metadata, and exact lacing and body slice provenance. A file packet reader applies the same proof to an active retained page, including its reader offset and caller-owned page-storage binding. An exhausted page retains its original range and lifecycle proof even when a later failed read or bounded resynchronization has reused the shared page buffer.

## Denormal handling

`DenormalScope` enables flush-to-zero behavior for the current thread on aarch64 and x86-64, then restores the exact floating-point control state it observed. On x86-64 it enables FTZ in MXCSR. On aarch64 it enables FZ in FPCR.

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

`FiniteImpulseResponseResampler(Sample, maximum_input_frames, maximum_output_frames)` converts one complete f32 or f64 impulse response outside the audio thread. It uses the same 32-tap, 256-phase Blackman-windowed sinc kernel as the streaming path, applies the sample-interval scale, and corrects the bounded result so its coefficient sum matches the source within destination precision. Equal-rate conversion is exact. Input is copied before calculation, so overlapping caller slices are safe, and every shape, rate, capacity, finite-input, and finite-result failure leaves the destination unchanged.

`StreamingResampler(f32)` and `StreamingResampler(f64)` use a 32-tap, 256-phase Blackman-windowed sinc filter. Each instance owns fixed inline coefficient and mirrored history storage. Configuration builds the coefficient table during preparation and selects the native scalar, NEON, or AVX2 convolution width. Output advances a retained continuous input phase. `setRateCorrectionPpm` changes the cached phase step from -2,000 through +2,000 ppm without resetting history or moving the current phase. `process`, rate correction, `reset`, and draining do not allocate or lock.

```zig
const plug = @import("zig-vst3-plugin");

var resampler = try plug.dsp.StreamingResampler(f32).init(.{
    .input_rate = 44_100.0,
    .output_rate = 48_000.0,
});

try resampler.setRateCorrectionPpm(125.0);
const result = try resampler.process(input, output);
```

`process` reports both consumed input and produced output. A caller may provide partial input or output slices and continue with the remaining data. `requiredInputSamples` reports the exact additional input needed to make a requested consecutive output span ready at the retained phase. `requiredInputSamplesAtCorrection` performs the same calculation for a proposed correction without changing the stream. These queries let a bounded FIFO consumer avoid both over-reading and a secondary pending-input buffer. `beginDrain` fixes the end of the stream and its current correction, and `drain` emits the bounded filter tail. `reset` clears history and phase while preserving the current correction. Reconfiguration starts a new nominal-rate stream with zero correction.

Rates must be finite and between 1 kHz and 2 MHz. Non-finite input samples are replaced with zero. The filter cutoff is reduced while downsampling to reject content above the destination Nyquist limit. Correction changes are transactional, and malformed cached step or phase state is rejected. Retained correction inconsistencies return `InvalidState` instead of entering an unreachable branch. `initBackend` and `configureBackend` force a vector width for deterministic parity tests. On the current NEON development machine, 44.1 to 48 kHz f32 conversion measured 6.9 ns per input sample, compared with 15.8 ns for the scalar path. The implementation is part of this repository and uses the repository license.

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

The caller owns model-rate scratch storage. Allocate it during preparation using the maximum host block size and `requiredModelCapacity`. The supported host-to-model ratio is bounded to 8:1 in either direction. The pipeline keeps at most ten model frames in fixed pending storage while reconciling arbitrary host block boundaries. Initialization, reset, successful reconfiguration, and pending-sample compaction clear every inactive pending slot.

The two resampling stages choose their delays so the round-trip latency is an exact integer number of host samples. `latencySamples` returns that value. A retained draining-state disagreement from either internal resampler is contained as `InvalidState`. Call `reset` after transport discontinuities, processing restarts, or a prepared mode change.

The deterministic tests cover:

- 44.1, 48, 88.2, and 96 kHz host rates with a 48 kHz model rate.
- Exact impulse-peak latency.
- Randomized host block boundaries.
- Passband amplitude and stopband attenuation.
- Reset, drain, invalid configuration, and insufficient scratch behavior.

The Fixed Rate Processor example applies a trivial gain at 48 kHz. It uses only the public framework API and safely passes through unsupported validator rates. On the current macOS development machine, the complete two-stage conversion measured 7.7 to 12.4 ns per host sample across the four common host rates.

## Dynamic latency

A processor that can change latency may declare this optional hook:

```zig
pub fn bindHostRequests(self: *Processor, requests: *plug.HostRequestSink) void {
    self.host_requests = requests;
}
```

Use `markLatencyChanged` to coalesce a pending latency notification. The same sink exposes `markIoChanged` for a prepared bus-topology change. Call `dispatchPending` only from a control, background, or UI thread. Debug and test builds reject dispatch from a real-time audit scope before making a host call. If both flags are pending, the framework sends one typed message and the controller makes one combined host restart request. A failed send restores both flags independently for retry.

The safe transition order is:

1. Prepare the new processing configuration without exposing it to the audio thread.
2. Publish the new value returned by `latencySamples`.
3. Mark and dispatch the latency change outside processing.
4. After successful dispatch, make the prepared mode eligible for adoption.
5. Adopt the new mode at the next audio block boundary and reset its history.

The raw VST3 shell sends a component-to-controller message. The reflected controller then asks the host to restart the component with `kLatencyChanged`. Repeated marks before dispatch produce one restart request. A failed dispatch remains pending for a later non-real-time retry.

For asynchronously loaded resources, expose bounded publication metadata through `ResourceRecovery` and call `adoptPendingThroughAtBlockBoundary` with the last successfully approved generation. The Model Shell demonstrates this ordering for a file-declared model rate, per-host SRC construction, and runtime replacement.

The host request sink belongs to the component. Do not retain it beyond processor teardown, invoke it after component destruction, or call `dispatchPending` from `process`.

MP3 VBRI parsing accepts both project-authored whole-stream counts and the external convention that excludes the leading metadata frame from byte and frame totals. A one-frame TOC coverage remainder is assigned to the final segment, and gapless stream plans remove a leading VBRI metadata frame from audible PCM. Xing parsing accepts InfoTag combinations through `0x7f`, skips both 20-byte reserved fields when present, and retains the encoder and delay fields used by Helix hmp3. Reserved fields without the InfoTag marker remain invalid so damaged metadata cannot become a resynchronization candidate.

## Reference implementation

The fixed-mode public-API example is split between `examples/fixed_rate_core.zig` and `examples/fixed_rate_plugin.zig`. The context-dependent resource example is split between `examples/model_shell_core.zig` and `examples/model_shell_plugin.zig`.

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-fixed-rate validate-fixed-rate
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-model-shell validate-model-shell
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build benchmark
```
