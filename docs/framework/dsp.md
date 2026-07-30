# DSP Utilities

`zig-vst3-plugin.dsp` provides bounded processing utilities that can run inside a plugin audio callback. The current public surface includes scoped denormal control, FFT and FIR processing, oscillators, fractional delay, dry/wet mixing, panning, waveshaping, modulation effects, dynamics and envelope tracking, algorithmic reverb, partitioned convolution, biquad and topology-preserving filters, crossover splitting, gain and bias, logarithmic ramping, lookup tables, processor composition and duplication, streaming sample-rate conversion, and a two-stage fixed-rate processing pipeline.

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

`ButterworthDesigner(Sample)` designs low-pass and high-pass cascades from order 1 through order 16. `lowPassOrder` and `highPassOrder` return a `ButterworthCascade` with the active section count and requested order. Odd orders begin with a first-order section. The slice-based `lowPass` and `highPass` functions remain available for even orders, with each output element representing one second-order section.

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

`PolyphaseAllpassDesigner(Sample).halfBandLowPass` designs a bounded half-band IIR as two parallel cascades of second-order all-pass sections. The request specifies normalized transition width and stopband attenuation. The returned design exposes direct and delayed path coefficients, low-pass and complementary high-pass magnitude evaluation, section counts, and the derived odd order.

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

`MixedOversampler(Sample, maximum_frames, maximum_stages)` accepts a bounded runtime list containing equiripple FIR, polyphase IIR, and dummy stages. Real stages double the rate while dummy stages preserve both the samples and factor. FIR and IIR stages accept independent upsampling and downsampling transition widths and stopband attenuations. FIR tap count is selected automatically, the completed equiripple response is normalized to exact DC gain, and a dense response check must satisfy both directional specifications before the configuration is published. `MixedMultichannelOversampler` applies the same list to independent channel histories and commits caller output only after every channel succeeds.

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

Only one dry block may be pending. Frame mismatches, non-finite samples, and reconfiguration while a block is pending are rejected without releasing that block. Use one mixer per independently compensated channel.

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

The reusable `ModulationRateSmoother`, `LinearSmoothedValue`, and positive-domain `MultiplicativeSmoothedValue` preserve exact sample counts across arbitrary blocks. The multiplicative form follows equal ratios, which suits frequency, gain, and ratio controls, rejects zero and negative bounds, and lands on the exact target without accumulated endpoint drift. `configureSmooth` ramps delay center, modulation depth, sweep bounds, feedback, wet mix, and LFO rate across chorus, flanger, vibrato, modulated delay, and phaser. Dynamics-style channel linking remains separate.

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

`LookupTable(Sample, point_count)` samples a function over a checked finite range. Scalar and block processing clamp inputs to that range and linearly interpolate adjacent points.

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

`AudioBlock(Sample, maximum_channels)` and `ConstAudioBlock(Sample, maximum_channels)` are allocation-free views over caller-owned planar channel slices. Construction checks the channel bound and equal frame counts. Sub-block and channel-subset views retain aliasing with the original storage. Mutable blocks support checked copy, addition, subtraction, scaled addition, multiplication by a scalar, and replacement with the pointwise sum or product of two blocks. Const views report minimum, maximum, peak magnitude, and sum of squares.

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

`Vector(Sample, dimensions)` owns finite fixed-size storage with checked arithmetic, dot product, overflow-stable magnitude, and normalization. `Matrix(Sample, rows, columns)` provides checked addition and scaling, transpose, identity construction for square matrices, dimension-safe matrix and vector multiplication, and partial-pivot solving for square linear systems. `DynamicMatrix(Sample)` provides allocator-owned row-major storage for runtime dimensions. It validates checked element counts and finite values, exposes checked indexing and rows, and returns separately owned results for cloning, identity construction, addition, subtraction, scaling, transpose, and rectangular multiplication. These allocating operations belong outside the realtime path.

Square fixed matrices can produce a reusable `LuDecomposition` that solves vectors or multiple right-hand sides and computes a determinant or inverse without repeating factorization. Matrices with at least as many rows as columns can produce a Householder `QrDecomposition`. It exposes the orthogonal and upper factors and solves full-rank least-squares systems without forming normal equations. Every fixed matrix can produce a compact one-sided Jacobi `SvdDecomposition` with `min(rows, columns)` factors. It retains sorted singular values, numerical rank, convergence state, and compact left and right factors, and provides reconstruction, condition-number reporting, pseudoinverse construction, and minimum-norm overdetermined, rank-deficient, or underdetermined least-squares solutions through the retained numerical rank. Invalid tolerances, sweep exhaustion, and corrupted retained state return errors. Dynamic decompositions remain separate work.

`Polynomial(Sample, capacity)` stores coefficients from the constant term upward and provides bounded evaluation, derivative, integral, addition, subtraction, multiplication, composition, quotient and remainder division, interpolation, least-squares fitting, standard orthogonal-family construction, and allocation-free complex root solving. `coefficient_capacity` and `maximum_degree` expose the selected type bounds. `legendre`, `chebyshevFirstKind`, and `chebyshevSecondKind` construct their degree-bounded families through checked three-term recurrences. `hermitePhysicists` and `hermiteProbabilists` name both common Hermite normalizations explicitly. `laguerre` selects the ordinary family, while `generalizedLaguerre` accepts a finite alpha greater than -1. `jacobi` accepts finite alpha and beta values greater than -1 and includes Legendre when both are zero. Every family rejects capacity overflow and non-finite recurrence results. Interpolation converts a checked distinct point set through divided differences. `fitLeastSquares` builds a fixed Vandermonde design and uses QR for full-rank fits. `fitLeastSquaresMinimumNorm` uses SVD when repeated or linearly dependent sample locations require a rank-aware minimum-norm coefficient vector.

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

`jacobiElliptic` computes checked real `sn`, `cn`, `dn`, and the principal amplitude. `jacobiEllipticFunction` selects any of the twelve standard functions through `JacobiFunction`: the three primary functions plus `ns`, `nc`, `nd`, `sc`, `sd`, `cs`, `cd`, `ds`, and `dc`. Reciprocal and quotient evaluation reports `error.JacobiPole` when its denominator is numerically indistinguishable from zero. Parameter-based paths start the arithmetic-geometric mean from `sqrt(1 - m)` instead of reconstructing a modulus, so the largest representable parameter below one retains its finite quarter period. Bounded modulo reduction contains maximum finite arguments without an overflowing period multiply. `inverseJacobiSn`, `inverseJacobiCn`, and `inverseJacobiDn` cover their principal real branches on `[-K, K]`, `[0, 2K]`, and `[0, K]`. Dense round trips include parameters through `0.99`, both precisions at the closest representable value below one, forced endpoints, degenerate parameter-zero behavior, and the narrower parameter-one domains.

`complexJacobiElliptic` accepts `std.math.complex.Complex(f32)` or `Complex(f64)` and a real parameter `m` from zero through one. It returns checked complex `sn`, `cn`, and `dn`. `complexJacobiEllipticFunction` evaluates the same twelve-function selector for complex arguments according to the [DLMF quotient definitions](https://dlmf.nist.gov/22.2). `complexJacobiCd` remains as the direct `cn / dn` convenience entry point, and `inverseComplexJacobiSn` returns the principal complex argument. Endpoint formulas use complex sine or hyperbolic functions. Generic forward evaluation combines the real AGM solutions through [Jacobi's imaginary transformation](https://dlmf.nist.gov/22.6) and [addition theorem](https://dlmf.nist.gov/22.8), while the inverse uses a convergent descending-modulus transform. Non-finite arguments, non-finite results, and numerically unresolved pole or branch neighborhoods return errors.

This module uses raw arguments and the parameter `m = k * k`. For references expressed in quarter-period units with modulus `k`, multiply forward units by `K(k)` or divide the returned inverse by `K(k)`.

## Envelopes, Gain, And Ramping

`BallisticsFilter(Sample)` tracks peak or RMS magnitude with independent attack and release times. Zero-millisecond times follow the detector immediately.

```zig
var envelope = try plug.dsp.BallisticsFilter(f32).init(.{
    .sample_rate = sample_rate,
    .attack_ms = 5.0,
    .release_ms = 100.0,
    .mode = .rms,
});
const level = envelope.processSample(input);
```

`Gain(Sample)` applies nonnegative linear gain with an optional sample-counted linear ramp. `setDecibels` accepts values from -160 dB through 36 dB. `Bias(Sample)` adds a checked finite offset.

`LogRampedValue(Sample)` interpolates strictly positive values geometrically. `setTarget` defines the exact ramp length. `next` advances one sample, while `skip` advances a bounded group without looping.

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

`RealtimeSnapshotPublisher(State)` provides fixed-storage mutable-state publication for one non-realtime writer and one realtime reader. Three inline slots and reader pinning prevent the writer from changing the slot being copied. `tryRead` performs one bounded nonblocking attempt, so the audio thread can retain its previous snapshot when publication races a block boundary. State containing pointers still requires the pointed-to storage to outlive every published snapshot.

`RealtimeReferencePublisher(State, slot_count)` provides retained immutable generations for one non-realtime writer and multiple realtime readers. It owns three through 64 inline slots. `tryAcquire` performs one bounded atomic attempt and returns a handle that pins its generation until `release`. `retain` makes another independently released handle. `beginPublish` reserves a non-active unreferenced slot and returns a control-thread writer whose `value` pointer can be filled in place. `beginUpdate` reserves a slot, pins the active generation, copies it into the reservation, and returns the same writer for partial mutation. It makes at most `slot_count` bounded acquisition attempts and releases the reservation if the snapshot cannot be acquired. `commit` atomically publishes the complete generation, while `cancel` releases the reservation without changing the active generation. The convenience `publish` path uses the same reservation internally. Publication fails with `RealtimeReferenceUnavailable` instead of waiting when every reusable slot is pinned. Generation allocation skips zero and every generation still represented by an inline slot, including across `u64` rollover. A stale copied handle therefore cannot become valid again when its former slot is reused. State containing pointers still requires the pointed-to storage to remain valid for every retained generation.

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

`Compressor(f32)` and `Compressor(f64)` apply a peak-envelope compressor with configurable threshold, ratio, attack, release, and makeup gain. Configuration is validated before publication, including the derived attack and release coefficients. Finite but unrepresentable sample-rate and duration products are rejected rather than constructing an envelope that cannot advance. Non-finite samples become silence, and malformed public state causes a safe unity-gain reset.

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

`LookaheadLimiter(Sample, maximum_lookahead_samples)` delays the signal by an exact, configured number of samples and derives gain from the complete lookahead window. `LookaheadCompressor(Sample, maximum_lookahead_samples)` applies the complete threshold, ratio, attack, release, and makeup curve to an exactly delayed signal while its detector observes future samples. Storage is inline and bounded. `latencySamples` reports the delay that the plugin must publish to its host.

`InterSampleLimiter(Sample, maximum_frames, factor)` performs fixed-capacity oversampling, high-rate peak limiting with a configurable reconstruction guard, and a final sample-peak safety stage. The oversampling factor is a compile-time 2x, 4x, 8x, or 16x choice. `process` is transactional when a block exceeds its declared capacity.

`TwoBandCompressor(Sample)` splits the signal through a fourth-order Linkwitz-Riley crossover and applies independently configured compressors to the low and high bands. `MultibandCompressor(Sample, band_count)` expands the same contract to two through eight compile-time bands. Its ordered crossover tree applies the later Linkwitz-Riley all-pass responses to earlier bands, preserving unity recombination magnitude while retaining independent compressor state and gain-reduction reporting for every band. `LinkedMultibandCompressor(Sample, band_count, channel_count)` retains independent crossover history for as many as 16 channels while using one peak detector and identical gain for every channel in each band. This preserves stereo and surround image relationships without leaking audio between channels. Configuration changes validate and prepare the complete crossover, phase-compensation, and compressor graph before replacing active state.

The ReleaseFast benchmark covers representative setup and processing costs for the advanced filter designers, lookahead and 4x inter-sample limiting, four-band compression, and realtime snapshot publication with and without a concurrent reader. These budgets are regression limits, not claims about every target. Fixed external or independent vectors cover lookahead gain behavior, sinc-reconstructed inter-sample containment, and three-band Linkwitz-Riley recombination.

The base compressor's `gainReductionDb` returns its current non-positive gain reduction. It has no knee or sidechain filter. Lookahead and shared-detector channel-linking policies are provided by the dedicated wrappers above.

`NoiseGate(Sample)` uses the same checked peak-envelope model as a downward expander below its threshold. `Limiter(Sample)` applies instantaneous gain reduction and a configurable release to keep individual samples at or below its threshold. Their configurations also reject derived coefficients that round to a non-advancing value. This derived check retains supported multi-megahertz high-rate limiting, including the maximum 192 kHz by 16x inter-sample path. The basic limiter has no lookahead, oversampling, inter-sample peak detection, or channel-linking policy.

## Partitioned Convolution

`PartitionedConvolver(maximum_frames, partition_size)` is the same fixed-capacity convolution engine used by the IR Loader. It stages mono or stereo `f32` impulse responses outside processing, precomputes their spectra, and lets the audio callback adopt only a complete generation. `ConvolutionOptions` selects partitioned or zero-latency processing and independent-stereo or mono routing. Zero-latency mode processes the first partition directly and keeps the remaining impulse response in the FFT tail. Mono routing averages the input channels, uses the first impulse-response channel, and writes the same result to both outputs.

The partition size must be a power of two of at least eight samples. `latencySamples` reports that size in partitioned mode and zero in zero-latency mode. Each instance owns three impulse-response slots, the direct-head history, and all transform history inline, so memory use grows with both template arguments. Import, resampling, `commit`, and option changes belong outside the audio callback. `adoptPending`, `processFrame`, and `resetProcessing` are the processing-side operations.

`ConvolutionPreparationQueue(maximum_frames, queue_capacity)` owns a bounded SPSC queue of complete mono or stereo impulse-response jobs. One producer submits validated generations while one consumer prepares them through `PartitionedConvolver`. A busy convolver leaves the front job ready for retry. The consumer can explicitly discard a job that cannot become current. The queue does not create or own a thread; the product chooses its worker or message-loop policy.

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

Both paths validate the complete specification, sample shape, finite input, size arithmetic, and destination capacity before changing encoded data. A failed append preserves the previous valid file and counters. PCM output clamps to the normalized range.

`PcmDither` provides deterministic, allocation-free signed PCM quantization from 2 through 32 bits across as many as 64 channels. Modes include direct rounding, TPDF dither at one quantization step in each direction, and first-order noise-shaped TPDF with a checked feedback coefficient. Each channel has an independent seeded sequence and error history. `reset` reproduces the original sequence exactly. Caller-buffer WAV and AIFF support 16-, 24-, and 32-bit dithered output. `WavFileWriter`, `AiffFileWriter`, `Rf64FileWriter`, and `Wave64FileWriter` expose `appendDithered` for their integer PCM encodings. One internal codec supplies signed PCM16, PCM24, PCM32, and IEEE f32 byte conversion, normalized decoding, bit and byte widths, little- and big-endian handling, and fixed 4 KiB positional-write staging to every PCM container and the bounded reader. A shared checked checkpoint restores either an exact committed length or an aligned payload boundary with canonical zero padding. It rejects inconsistent committed state before file mutation. Dithered staging preserves interleaved channel phase across chunk boundaries. Format, channel, bit-depth, finite-sample, and capacity checks finish before dither state advances. A failed audio write restores the last committed file length, prior padding, and caller dither state when truncation succeeds. If truncation also fails, the writer remains recoverable but rejects further appends until `recover` succeeds.

`WavFileWriter` writes the same classic RIFF formats directly to a caller-owned `std.Io.File`. It truncates and initializes the file, streams samples through fixed staging storage, keeps the header current after each successful append, and provides `finalize` for header recovery, exact truncation, and durable sync. The caller retains responsibility for closing the file. All four PCM container writers also expose `initWithOperations`. `FileWriterOperations` supplies positional-write and length callbacks for deterministic fault injection or another file implementation. Positional callbacks report the bytes written; the framework retries short writes and rejects zero progress or counts larger than the supplied slice. `FileWriterCheckpoint` exposes the validated exact or aligned committed-boundary primitive used by the file-backed writers. Header, padding, audio, dithered staging, rollback, and recovery use the same operations after initialization. Focused failure coverage includes partial audio writes over an existing pad byte, truncation failure, header failure after committed audio, short writes, recovery, and dither rollback.

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

`AudioMetadataEntry` represents a borrowed FourCC and byte string. `encodeRiffInfoMetadata` and `encodeAiffTextMetadata` write complete metadata chunks into caller storage, while their iterators validate and expose both known and unknown FourCC entries without allocation. `WavFileWriter`, `AiffFileWriter`, and `Rf64FileWriter` accept these tags through `initWithMetadata`. Metadata values need to remain valid only for that initialization call.

`BroadcastExtension` implements the complete 602-byte Broadcast Audio Extension defined by [EBU Tech 3285](https://tech.ebu.ch/publications/tech3285). Its version-aware contract covers fixed ASCII fields, typed calendar date and time, the 64-bit sample time reference, 64-byte UMID, version-2 loudness values and unused-value sentinels, zeroed reserved storage, and CR/LF-terminated coding history. `BroadcastMetadataView` validates a complete borrowed `bext` chunk without allocation. Invalid loudness values from external files are ignored as required by the specification, while invalid structure, reserved bytes, text padding, dates, times, versions, and chunk padding are rejected.

`RiffXmlKind`, `encodeRiffXmlMetadata`, and `RiffXmlView` frame borrowed UTF-8 iXML and aXML documents. They validate UTF-8, NUL exclusion, the XML envelope, RIFF sizes, and word padding. `IxmlMetadata` adds allocation-free encoding and caller-storage parsing for production-recorder fields, take flags, file identity, notes, speed and timecode-rate data, sync points, file-set identity, track lists, derivation history, loudness, portable BEXT data, location data, and user data. Ratios retain exact integer numerators and denominators. Sample rates, bit depth, split timestamps, drop-frame flags, relative and absolute sample positions, event durations, file-set grouping, and file-set start times are typed. `IxmlLoudness` carries the five EBU R 128 values in either the native `LOUDNESS` object or the redundant BEXT form. `IxmlLocation` validates finite latitude and longitude ranges plus finite altitude. `IxmlUser` supports legacy human-readable text or the standardized iXML 2.0 AFSI production, mixer, and recorder fields, but rejects an ambiguous mixture during encoding. Every field is optional. Parsing accepts arbitrary field order, XML declarations, numeric and named entities, and structurally nested unknown extension subtrees, which it ignores. It rejects duplicate known fields, mismatched tags, zero-denominator ratios, non-finite values, invalid GPS coordinates, invalid Unicode, inconsistent list counts, insufficient storage, and input/output overlap before mutation. CDATA, DTD, and untyped vendor extension values remain outside the typed view. When an iXML BEXT object and an official Wave `bext` chunk coexist, the caller must keep their redundant values equal.

`AdmIdentifier` parses every core ID family defined by ITU-R BS.2076-3: programme, content, object, pack, channel, stream, track format, track UID, alternative value set, and block format. It accepts hexadecimal case differences, provides case-insensitive identity, exposes format type labels and definition indexes, and distinguishes externally supplied common definitions from custom definitions that require local metadata. `AdmChannelAllocation` and `AdmChannelAllocationView` encode and parse the fixed-layout `chna` chunk defined by ITU-R BS.2088-2. They validate track indexes, exact UID and reference shapes, direct audio-channel references, optional pack references, duplicate UIDs, complete track coverage, zeroed reserved entries, and the padding byte without allocation. Reserved entry capacity supports later metadata growth. WAV, RF64, and BW64 writers reject a `chna` track count that disagrees with the audio channel count before mutating the file.

`AdmXmlDocument` adds an allocation-free typed graph over a bounded XML scanner. It recognizes all core declaration families inside one `audioFormatExtended` subtree and exposes declaration and reference iterators. Validation rejects duplicate IDs, wrong reference kinds, unresolved custom definitions, invalid owners, self-references, incompatible type labels, broken stream/track reciprocity, invalid identifier continuity, and excess or mutually exclusive references. Common format definitions may resolve outside the document. The XML scanner resolves scoped default and prefixed namespace declarations, validates namespace URI references through 2,048 decoded bytes and reserved bindings, compares entity-normalized namespace names, and rejects undeclared prefixes or duplicate expanded attributes. Ordinary escaped text and CDATA sections share one bounded typed-text path. CDATA remains literal while entity references in ordinary text decode normally, including when the two forms are adjacent. DTD declarations remain explicitly unsupported. The typed graph matches elements against the expanded namespace of `audioFormatExtended`. It omits complete foreign-vocabulary subtrees, so nested elements cannot impersonate metadata fields. Attributes are matched by exact qualified name, so a foreign namespace cannot satisfy a required unqualified field.

`AdmXmlExtensionIterator` returns each outermost foreign-vocabulary subtree inside `audioFormatExtended` without allocation. Each item exposes its decoded namespace URI, qualified and local names, root attributes, exact source bytes and offset, immediate typed parent, and nearest declaration owner. Nested markup, comments, processing instructions, entity spelling, and typed-looking descendants remain byte-for-byte intact. `AdmXmlExtensionAttributeIterator` returns foreign-prefixed attributes attached to typed elements with their decoded namespace URI, exact source spelling, encoded value, typed element, and declaration owner. Callers can decode an attribute value into their own buffer. Extension namespace aliases are compared by decoded URI identity.

`AdmXmlUntypedElementIterator` separately returns each outermost subtree whose namespace matches `audioFormatExtended` but whose local name is outside the supported typed vocabulary. It preserves the same exact source and ownership information as a foreign extension. `AdmXmlUntypedAttributeIterator` returns prefixed attributes bound to the metadata namespace on typed elements. XML default namespaces do not apply to unprefixed attributes, so those remain under each typed validator's element-specific attribute rules. `untyped_element_count` and `untyped_attribute_count` allow a caller to inspect compatibility before consuming typed views. `validateTypedVocabulary` provides an opt-in strict policy without changing the existing profile-specific validation errors.

`AdmXmlProfileIterator` exposes each profile's required name, version, level, and document-reference text. It accepts multiple profiles in one direct `profileList`, but rejects multiple lists, empty lists, missing or empty values, nested profile content, and misplaced lists or profiles. It validates the generic BS.2076-3 profile declaration contract.

The BS.2168 emission validators apply the declared level's element and direct sub-element limits, identifier rules, content reachability, and two-level object ownership. Object-source validation requires leaf objects to select one permitted local Objects or common DirectSpeakers pack and branching objects to omit pack and track references. A nested object must select a local Objects pack. Every local Objects pack, local channel, and track UID must participate in the required graph. Track UIDs cover each channel in the selected pack exactly once, refer back to that pack, and cannot select the silent UID. The common pack registry covers the polar and Cartesian layouts permitted by the profile and applies the level-specific 12- or 24-channel limit.

`validateEmissionProfileMatrices` validates downmix side information after object-source validation. Each local Matrix pack has one distinct common DirectSpeakers input and output layout, one through 24 local Matrix channels, and a unique input/output pair. The input layout must be used by an object, while Matrix packs and channels cannot serve as object or track sources. Output layouts exclude the common configurations without an LFE channel. Each Matrix channel has one block and a unique output channel from the selected output layout. Coefficients identify distinct channels from the input layout, accept only constant gain and gain-unit attributes, and remain within `-inf` through 20 dB or zero through 10 linear. The profile path requires the current output-reference name and rejects extra Matrix pack, channel, block, matrix, and coefficient structure.

`validateEmissionProfileComplementaryObjects` validates mutually exclusive top-level object groups. A group member belongs to one group, cannot own another group, and uses the same source pack type as the root. Each programme includes every member, exactly one member, or none. Derived level limits count one independent group per complementary set and use the maximum direct or nested track count among its alternatives. Non-complementary top-level objects contribute their complete direct or nested track counts.

`validateEmissionProfileObjectParameters` validates the profile subset for object interaction controls. Every object has a bounded name and explicit `interact` flag. Interaction metadata is limited to gain and azimuth or Cartesian-X ranges with the required minimum and maximum bounds. Object and alternative-value-set gains cannot exceed 21 dB or their interaction range. Position offsets cannot exceed the profile or interaction range and require a local Objects source whose blocks stay at the neutral position. Alternative interaction metadata retains the parent ranges while allowing different gain and position interaction flags. Nested objects cannot carry these controls.

`validateEmissionProfileComplementaryParameters` requires every member of a complementary group to use identical interaction flags and metadata, gain, and position offsets. Programme alternative-value-set references must belong to included top-level objects and select at most one set per object. A programme that includes an entire complementary group either references no alternative sets for that group or one semantically identical set for every member. Fixed single-member selections may reference that member's set independently.

`validateEmissionProfileProgrammeContentMetadata` validates the profile's programme and content metadata after the complementary-parameter checks. Programme and content names contain one through 64 Unicode scalar values. Required language attributes and label languages must be registered ISO 639-2 codes, including bibliographic and terminology aliases and the reserved private-use range. Labels carry no extra attributes and use each language at most once per owner. Every programme and content has exactly one attribute-free loudness block containing one or both finite integrated and dialogue loudness values. Every content has exactly one dialogue element whose required kind attribute and enumerated range match its non-dialogue, dialogue, or mixed value. Direct children and attributes outside the profile subset are rejected.

`validateEmissionProfileFormatMetadata` validates every local Matrix or Objects pack and channel declaration plus every track UID. Packs and channels require bounded names, matching type labels and definitions, and only the profile attributes. Objects packs select exactly one Objects channel. Matrix packs select one through 24 Matrix channels plus exactly one input and output pack. Matrix channels contain one Matrix block, while Objects channels contain at least one Objects block. Track UIDs accept only optional positive sample-rate and bit-depth attributes and exactly one permitted pack and channel reference. Reference elements cannot carry attributes, and format or track children outside the profile subset are rejected.

`validateEmissionProfileObjectBlocks` validates file-based Objects blocks. Every block requires relative start time and duration, consecutive blocks must be continuous, and nonzero durations must be at least 5 ms. A document uses one coordinate system throughout. Each block supplies all three coordinates and accepts only position, coordinate-system, divergence, gain, and jump parameters. Divergence requires the matching range, gain cannot exceed 10 dB, and jump interpolation is forbidden. Serial frames require the separate serial validation path.

`validateEmissionProfilePcmEssence` accepts the physical PCM sample rate, bit depth, channel count, and frame count. It requires one track UID per physical channel, compares every present track sample-rate and bit-depth attribute with the supplied properties, starts every local Objects block sequence at zero, and ends it exactly at the file duration using rational time arithmetic. `RiffMetadata.validateEmissionProfileAdm` also requires a one-to-one channel-allocation entry for every physical track. `AudioFileAdmMetadata.validateEmissionProfilePcmEssence` applies the equivalent check to parsed CHNA storage, while `AudioFileReader.readEmissionProfileAdmMetadata` derives the essence descriptor from an integer-PCM file and rejects floating-point essence.

`validateEmissionProfileSerialFrameEnvelope` starts the S-ADM path without claiming complete serial interoperability. It requires one `frame` root at BS.2125-1, one `frameHeader`, one `audioFormatExtended`, one empty `frameFormat`, at least one transport-track container, and one header profile list. Frame-format IDs use the eight-digit hexadecimal counter shape. Start and duration use exact ADM time syntax, duration is at least 5 ms, type is `header` or `full`, and the time reference is local. `validateEmissionProfileSerialTransportTracks` validates unique four-digit hexadecimal transport IDs, bounded names, equal positive track and ID counts, unique positive physical track IDs within each transport, PCM format declarations, exact one-reference track structure, and one-to-one coverage of every ADM track UID across all transport containers. `validateEmissionProfileSerialHeaderProfiles` requires a well-formed, duplicate-free header profile list with at least one emission-profile declaration and an identical declaration in the embedded ADM profile list. Other header profiles remain permitted. `validateEmissionProfileSerialObjectBlocks` retains typed local start, local duration, and initialization state. Timed Objects blocks use only local timing, start at zero, remain exactly continuous, use zero or at least 5 ms durations, increment their within-frame identifiers, and cover the frame duration exactly. An optional initialization block comes first, uses identifier counter zero, carries no timing, and does not constrain the first timed counter. `validateEmissionProfileSerialFlowFrame` accepts caller-owned `EmissionSerialFlowState` for an original flow. The first frame counter is one, later counters increment exactly, only the first frame may use the `header` type, and each start equals the preceding start plus duration across decimal and sample-fraction representations. Optional flow identifiers use the UUID text shape and must remain equal whenever present. Failed validation leaves the state unchanged, and `reset` starts a new flow. Modified flows that intentionally no longer preserve original counter semantics remain outside this strict opt-in path.

`AdmStaticMatrixMixer` binds one typed Matrix block to a caller-supplied, duplicate-free channel identifier order and retains fixed input indexes and gains. Linear and dB coefficients render in f32 or f64 without allocation. Plan construction rejects missing inputs, duplicate terms, non-Matrix blocks, variable values, phase, and delay. `AdmMatrixCoefficientMixer(Sample, maximum_delay_samples)` adds stateful nonnegative constant delay. It converts milliseconds at initialization using nearest-sample rounding with half-sample ties toward zero, rejects requests beyond the caller-selected capacity, and preserves its histories across arbitrary processing partitions. `reset` clears every delay path. Both mixers validate every buffer length and reject overlapping input and output storage before mutation. Non-finite coefficient input is treated as silence.

`AdmVariableMatrixCoefficientMixer(Sample, maximum_delay_samples, maximum_variables, maximum_points, maximum_phase_taps)` is the opt-in product-policy layer for variable values and phase. Caller-defined `AdmMatrixVariableTimeline` values bind metadata names to linear gain, phase in degrees, or delay in milliseconds. Each bounded lane starts at sample zero, uses strictly increasing absolute `u64` sample positions, and selects held or linear interpolation. Variable delay endpoints use the constant-delay nearest-sample rule, then interpolate fractionally between those endpoints to avoid integer-delay jumps. Processing is sequential, allocation-free, and invariant to host partitioning. `resetAt` clears signal history and selects an exact absolute restart position without converting the sample index to floating point.

Phase processing uses a caller-supplied odd-length antisymmetric quadrature FIR. The mixer aligns the real path to the FIR group delay, evaluates `real * cos(angle) + quadrature * sin(angle)`, applies the same latency to every term, and reports it through `latencySamples`. The caller therefore owns the useful phase bandwidth, ripple, tap count, and resulting latency. The existing odd-symmetry equiripple designer can prepare the FIR outside the realtime path. Products that do not use phase can select zero phase-tap capacity and incur no added latency. Initialization rejects missing, duplicate, mistyped, unused, non-finite, over-capacity, or malformed control lanes and phase filters before publishing state. Processing rejects discontinuous sample ranges, invalid retained state, shape errors, range overflow, and aliases before changing output or history.

`AdmHoaMatrixDecoder(Sample, maximum_inputs, maximum_outputs)` accepts an ordered slice of typed HOA blocks and an output-major coefficient matrix already defined for the declared channel normalization. Initialization requires unique valid order-degree pairs, orders through 50, one normalization, one NFC reference distance, and one screen-reference value. N3D and SN3D are accepted through the supported order. FuMa is limited through order three. Equation-defined component bases are rejected because the metadata does not define a portable formula language. Static block gains are composed into the retained matrix. Processing replaces every output bus without allocation and validates all shapes and aliases before mutation.

`AdmHoaLoudspeakerMatrix(Sample, maximum_inputs, maximum_outputs)` generates that matrix outside the realtime path. It evaluates the real spherical-harmonic basis defined by [ITU-R BS.2076-3](https://www.itu.int/rec/R-REC-BS.2076-3-202502-I/en) at each non-LFE loudspeaker direction, then computes the minimum-norm mode-matching pseudoinverse with the bounded SVD. The basis uses azimuth from `-180` through `180` degrees, elevation from `-90` through `90` degrees, sine terms for negative degree, the zonal term for degree zero, cosine terms for positive degree, and no Condon-Shortley phase. N3D and SN3D are supported through order 50. The specified FuMa weights are supported through order three.

Generation requires at least as many distinct non-LFE directions as components and rejects a numerically rank-deficient layout. The result reports rank and condition number, keeps LFE rows exactly zero, retains the exact ordered component identity, and refuses to initialize a decoder with a different block set. Basic weights preserve the mode-matching solution. Optional max-rE weights apply the per-order Legendre approximation documented in the [AES AllRAD2 paper](https://www.aes.org/e-lib/download.cfm/19460.pdf?ID=19460). The generated matrix is angular and far-field. It retains the common NFC reference distance for downstream policy but does not create radial filters. Screen-referenced and equation-defined HOA need separate rendering policies and are rejected.

`AdmBinauralStereoMixer(Sample)` handles one static block per ear for content already encoded as left-ear and right-ear signals. It accepts the current and legacy ADM channel names, requires exactly one channel per ear, maps either input ordering to stereo output, and composes linear or dB block gain. Block processing replaces both outputs without allocation, treats non-finite input as silence, and rejects every input-output or output-output overlap before mutation.

`AdmBinauralStereoGainTimeline(Sample, maximum_blocks_per_ear)` handles explicit block timing for the same direct-ear content. Initialization accepts one ordered block sequence per input channel, maps those channels to ears, and retains exact rational start, interpolation-end, and end positions. An ordinary adjacent block ramps from the previous gain over its full duration. A jump block switches immediately unless it supplies a nonzero interpolation length. Gaps render silence and prevent cross-gap interpolation. `process` replaces an arbitrary absolute sample range without allocation, and its result is independent of host-buffer partitioning.

`HrtfDatabase(maximum_measurements, maximum_frames)` copies a measured stereo impulse-response set and its optional fractional per-ear delays into fixed storage. Directions use head-relative azimuth from -180 through 180 degrees and elevation from -90 through 90 degrees. Initialization rejects non-finite samples, empty responses, malformed shapes, invalid delays or directions, and duplicate physical directions, including wrapped azimuth and pole aliases. `interpolate` prepares an interleaved stereo filter through exact nearest selection, normalized inverse squared chord-distance weighting over the three nearest measurements, delay-aligned interpolation, or optional log-magnitude and circular-phase spectral interpolation. Exact measured directions retain the measured response and delay.

`HrtfRenderer(maximum_frames, partition_size)` stages an interpolated response through the immutable convolution publication path. Preparation and sample-rate conversion are non-realtime operations. `adoptPending` is the bounded audio-thread publication point, and `processSample` sends one finite mono source through the independent measured left and right filters without allocation. Partitioned and zero-latency modes, generation ordering, reset, non-finite input containment, active-generation reporting, and explicit latency are available. The product owns the worker or message-loop execution that prepares and publishes a new static filter.

`HrtfMotionRenderer(maximum_frames, maximum_points, maximum_crossfade_samples)` precomputes a bounded sequence of source and head poses outside the audio thread. Positions use a right-handed coordinate system with positive X forward, positive Y left, and positive Z up. Head yaw, pitch, and roll transform world-space source positions into head-relative directions. Strictly increasing absolute sample positions select filters, and smooth fixed-duration crossfades avoid filter-switch discontinuities. Processing performs no allocation, locks, transforms, or filter preparation. Schedule validation and filter preparation are transactional.

`HrtfSofaLoader(maximum_measurements, maximum_frames)` reads SimpleFreeFieldHRIR 1.0, 1.1, and 1.2 files through an optional runtime-loaded netCDF library. It validates the convention, free-field FIR data, stereo receiver count and ordering, coordinate encoding and units, sampling-rate consistency, impulse and delay dimensions, numeric values, and product capacities before returning the fixed database. Spherical and Cartesian source positions are supported for the convention's default listener origin, forward vector, and up vector. A file with measurement-varying listener geometry is rejected explicitly until that transform is part of the decoded model. The ordinary framework has no link-time netCDF dependency. `hrtf_sofa.databaseFromDecoded` provides the same checked conversion boundary for another file service or an already decoded dataset. Product-specific dataset selection, live tracking transport, room response composition, and headphone audition remain outside this layer.

`AdmDirectSpeakerRouter` handles one unambiguous exact label, while `AdmDirectSpeakerPositionRouter` adds common-layout gain mapping, bounded polar or Cartesian selection, screen-edge transforms, LFE routing, discard behavior, and explicit point-panner fallback. Supply `AdmDirectSpeakerCommonPackMapping` with the source pack identifier and output layout name to enable common-layout rules. A rule applies only to a block with exactly one normalized speaker label and only when every destination label exists. The first complete ordered rule wins before ordinary label, bound, LFE, or panner fallback. Multi-output routes use `mix` or a fallback mixer because `processSample` cannot represent them. `AdmPolarPointSourcePanner` renders nominal speaker regions through measured reproduction positions, including virtual layer and pole downmixes and the dedicated stereo path. `AdmCartesianPointSourcePanner` applies the bounded allocentric point-source algorithm over caller-owned room positions. Both panners exclude LFE outputs and preflight block aliases.

`AdmPolarExtentPanner` retains the 1,652 spreading directions and a copy of its point panner. Its precomputed per-direction gains live in caller-owned storage whose length is returned by `requiredGainStorage`; that storage must remain alive and unchanged while the extent panner is used. Initialization preflights every direction before filling the table. Gain calculation covers width, height, distance, and depth without allocation and rejects an output slice that overlaps the retained table. `AdmObjectPolarExtentGainPlan.initPolarExtent` applies screen transforms, polar channel lock, divergence, block gain, and direct/diffuse splitting before retaining the final gain vectors.

`AdmCartesianExtentPanner` copies a validated allocentric point panner and evaluates the separable virtual-source grid without retained gain storage. Layouts with three or more height planes use 40 samples on every axis. Other layouts use 20 samples over the nonnegative height range. Gain calculation applies extent scaling, layout-dimensional weighting, inside and boundary accumulation, boundary fading, point-to-extent crossfade, normalization, and LFE suppression. `AdmObjectCartesianExtentGainPlan.initCartesianExtent` applies the common Objects transforms and gain stages. `AdmObjectPointGainPlan.init` remains the smaller zero-extent path for polar or Cartesian point panners.

Objects blocks retain up to 32 typed polar or Cartesian exclusion zones. Polar rendering selects speakers from nominal positions, groups destination speakers by layer, front/back change, unit-vector distance, and front/back distance, and redistributes excluded gain power through the first available priority group. Cartesian rendering applies the additional allocentric row repair, cancels an exclusion that would remove every speaker, excludes removed speakers from channel lock, and runs point or extent panning on a reduced layout before mapping gains back to the complete output order. LFE outputs remain silent in both paths.

`AdmObjectGainTimeline(Sample, maximum_blocks)` precomputes one direct and diffuse gain target per explicitly timed Objects block. Use `init` for point rendering, `initPolarExtent` for polar extent, or `initCartesianExtent` for Cartesian extent. Exact rational time remains intact through sample-boundary selection and interpolation phase calculation. An ordinary adjacent block ramps from the preceding target across its full duration. A jump block switches immediately unless it supplies a nonzero interpolation length, in which case the ramp occupies that initial interval and the target remains fixed afterward. The first block and every block after a gap remain fixed for their full span. A zero-duration block renders no samples but supplies the source target for an adjacent successor.

Timeline construction is a non-realtime operation because it calculates every spatial target. `mix` accepts an absolute first-sample index and arbitrary input partition, performs no allocation, adds into separate direct and diffuse output buses, and preflights all shapes and aliases before mutation. The caller chooses the maximum metadata-block count at compile time. A single block without explicit timing continues to use its static gain plan.

`AdmObjectDiffuseProcessor(Sample, maximum_outputs)` completes the Objects direct and diffuse bus path. Initialization is non-realtime. It designs one deterministic 512-sample random-phase all-pass FIR per canonical output label using that label's rank in the sorted layout. Layout reordering therefore preserves each channel's filter. `process` decorrelates each diffuse bus with f64 accumulation, delays the corresponding direct bus by 255 samples, and replaces the final output buses. It accepts arbitrary partitions, allocates no memory, treats non-finite input as silence, and preflights state, shapes, and aliases before mutation. `latencySamples` reports the direct-path match that the enclosing renderer must include in its latency contract. `reset` clears both paths. The caller chooses the maximum output count at compile time, which bounds all coefficients and history. The local ReleaseFast benchmark covers fully active 12-channel f32 and f64 layouts at 16, 64, and 512 frames.

`validateEmissionProfileComplementaryLabels` validates complementary-group labels on the group leader. Labels contain one through 64 Unicode scalar values, require a unique registered ISO 639-2 language per leader, and accept no other attributes. Object reference elements accept no attributes. `validateEmissionProfileConsistentLabelLanguages` is a separate opt-in check for the recommendation that every programme, content, and complementary-group leader expose the same label-language set. `validateEmissionProfileRecommendedProgrammeLanguages` is another opt-in check. A programme that includes every member of a complementary group whose contents use multiple languages declares `und` as its programme language. `validateEmissionProfileRecommendedDialogueLoudness` separately requires dialogue loudness on each dialogue or mixed content and on every programme that references such content. None of these recommendations is part of the conformance chain.

`AdmXmlTagIterator` exposes bounded tag groups as typed tag or target items. Tags retain decoded text and an optional class. Targets are limited to programme, content, or object identifiers and participate in the same local custom-reference validation as the main graph. Each direct group must contain at least one tag and one target.

`AdmTimeValue` preserves ADM decimal and fractional-sample time forms as an integer whole part plus an exact rational fraction. It accepts clock-form decimal time, clock-form sample fractions, and short sample counts. Decimal fractions require at least five digits. Long sample fractions require matching numerator and denominator digit counts and a numerator below the rate. Exact comparison and sum equality work across unlike denominators, while `toSeconds` provides an explicit floating-point conversion.

`AdmXmlBlockIterator` exposes block IDs, parent channel IDs and names, exact `rtime` and `duration`, gain, importance, jump position and optional interpolation length, head locking, and headphone virtualization. One static block may omit timing and receives the BS.2076-3 defaults. Every block in a multi-block channel must provide both timing attributes. Validation also enforces direct channel ownership, matching channel and block identifiers, block indexes starting at one in document order, finite nonnegative common linear gain, finite dB gain, importance from zero through ten, unique common parameters, flag syntax, and interpolation no longer than a bounded block duration.

Type-specific block models cover DirectSpeakers polar or Cartesian positions, bounds, speaker labels, and screen-edge locks; Objects positions, dimensions, diffuse amount, divergence, channel locking, screen references, and bounded polar or Cartesian exclusion zones; HOA equation, order, degree, normalization, and NFC reference distance; and Binaural current or legacy ear channel names. Matrix blocks expose bounded coefficients with typed input channel identifiers and constant or variable gain, phase, and delay. The generic ADM model permits negative Matrix coefficient gains and accepts the current `outputChannelFormatIDRef` name or legacy `outputChannelIDRef` name, with one output reference per block. The emission-profile validator applies its narrower gain, attribute, and reference-name rules. Custom coefficient references must resolve locally.

`AdmXmlDocument.validateChannelAllocation` cross-checks physical track UID references and custom track, channel, and pack definitions against CHNA. `RiffMetadata.validateAdm` validates an in-memory aXML and CHNA pair. `AudioFileReader.readAdmMetadata` retrieves both chunks into separate caller buffers and returns a validated typed document and channel-allocation view. It returns no ADM metadata when neither chunk exists and rejects incomplete pairs, overlapping buffers, malformed XML, invalid graph structure, and inconsistent mappings.

`RiffMetadata` composes Broadcast Wave, iXML, aXML, CHNA, and INFO data in interoperable order. `WavFileWriter.initWithRiffMetadata` places this package before the format chunk, as required for BWF. `Rf64FileWriter.initWithRiffMetadata` and `Bw64FileWriter.initBw64WithRiffMetadata` place it after the mandatory `ds64` chunk and before the format chunk. External loudness measurement accuracy, the remaining dynamic rendering layers, and independent tool exchange remain separate work.

`encodeId3` and `Id3View` implement complete allocation-free ID3v2.4 tag framing independently of an audio container. The codec validates syncsafe tag and frame sizes, frame identifiers and flags, optional extended-header update, CRC, and restriction fields, zero padding, matching footers, and whole-tag unsynchronisation consistency. Iteration retains unknown frame identifiers and encoded bodies. Decoding into caller storage reverses per-frame unsynchronisation before exposing grouping identity, encryption method, data-length indication, compression state, and the remaining payload. UTF-8 text payload helpers and `Id3DecodedFrame.text` cover the four standard ID3 text encodings, including UTF-8 validation, UTF-16 byte-order marks, and surrogate pairs.

`encodeId3V23` and `Id3V23View` provide a separate [ID3v2.3](https://id3.org/id3v2.3.0) contract. Frame sizes are ordinary big-endian 32-bit integers. The status flags, format flags, and compression-size, encryption-method, and grouping-identity prefixes use v2.3 bit positions and ordering. Optional extended headers retain declared padding and CRC-32 values. Requested tag-wide unsynchronisation is emitted only when a false sync or terminal `0xff` requires transformation, and parsing reverses the complete encoded body into caller storage before interpreting headers. Unknown frames remain iterable. Text helpers accept Latin-1 or BOM-qualified UTF-16, the two encodings defined by v2.3.

`encodeId3V1` and `Id3V1View` cover exact 128-byte [ID3v1.0 and ID3v1.1](https://id3.org/ID3v1) tail records. The encoder validates field capacities, embedded NUL bytes, four-digit years, and nonzero v1.1 track numbers before replacing caller storage. The view distinguishes v1.1 only when the 29th comment byte is zero and the following track byte is nonzero. It retains arbitrary genre identifiers, including the conventional unknown value 255.

Compression and encryption algorithms remain external policies: the generic v2 frame layers carry their flags and auxiliary fields without claiming to interpret transformed payloads. Source and destination overlap is rejected before mutation.

`Mp3Header`, `Mp3Frame`, and `Mp3Stream` provide bounded MPEG-1, MPEG-2, and MPEG-2.5 Layer III framing. Header parsing validates the sync, version, Layer III selector, bitrate index, sample-rate index, channel mode, CRC-protection bit, and padding bit. It computes the standard 1,152- or 576-sample frame duration and checked frame byte length. Free-format headers retain an unresolved zero bitrate and frame length until the stream infers an unpadded base length. Inference scans at most 16 KiB, accounts for each frame's padding bit, and confirms a candidate through the following expected frame boundary so one payload sync cannot establish the size. A standalone free-format frame is rejected as ambiguous.

Stream parsing requires a stable version, sample rate, channel count, and free-format mode, skips one bounded leading ID3v2.2, v2.3, or v2.4 tag and one trailing ID3v1 record, and rejects truncated frames or trailing data. ID3 extent checks use ordered subtraction rather than potentially overflowing end-offset addition. Cursor, first-header, free-format base length, frame-count, and sample-count changes commit together only after all derived values validate. Public retained boundaries are checked before slicing. The tables and ordinary bitrate frame formulas follow FFmpeg's maintained [MPEG Audio header decoder](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/mpegaudiodecheader.c).

The first frame retains bounded Xing or Info fields, the 100-byte seek table, optional quality, recognized LAME, Lavf, or Lavc encoder delay and padding, and version-1 VBRI fields and table bytes. Xing side-information offsets account for optional CRC words. VBRI placement follows FFmpeg's maintained [MP3 demuxer](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mp3dec.c). `Mp3Summary` reports the scanned encoded frame count, sample count, byte range, sample rate, channel count, and duration. `Mp3GaplessPlan` validates paired delay and padding fields and derives the exact audible range.

`Mp3PcmStreamEncoder` accepts complete PCM frames, flushes the fixed analysis delay, and reports encoded, input, delay, padding, frame, and byte counts. Call `startGaplessMetadata` before the first PCM append to reserve a silent CBR Info frame. After `finish`, call `gaplessMetadataFrame` with the original frame-sized destination to replace the provisional counts. The reserved frame advances the encoder analysis state, and its duration is included in the reported delay. `Mp3PcmFileEncoder` performs the same replacement during finalization. A failed partial metadata patch remains recoverable through its positional checkpoint.

`Mp3PcmReservoirEncoder` retains one frame until the next PCM frame is available. It moves as many complete leading main-data bytes as possible into the unused tail of that prior frame, bounded to 511 bytes for MPEG-1 and 255 bytes for MPEG-2 or MPEG-2.5. It then updates the current frame's `main_data_begin`, shifts its remaining physical payload, and recomputes a protected frame's side-information CRC. `Mp3PcmReservoirStreamEncoder` flushes the analysis delay through the same pending-frame path. Its optional Info frame is encoded independently before reservoir priming, so later borrowed payload cannot overwrite metadata. `Mp3PcmReservoirFileEncoder` writes only finalized frames, patches final gapless metadata before synchronization, and restores both the emitted boundary and provisional first frame after a partial patch.

`Mp3VbrPcmEncoder` tests the configured bitrate-index range in ascending order and chooses the first quantization within `maximum_noise_to_mask_ratio`. If no successful candidate meets that limit, it emits the highest successful candidate with `quality_met` false and the measured ratio. `encodeAtBitrateIndex` forces one in-policy rate for metadata or application policy while retaining the shared padding cadence. `Mp3VbrPcmStreamEncoder` stores frame starts in caller-owned `u64` storage, flushes the analysis delay, and builds a 100-entry Xing table from final byte positions. `startXingMetadata` advances analysis with one independent silent frame. `xingMetadataFrame` replaces it with final frame and byte counts, optional quality, table entries, and LAME delay and padding. `Mp3VbrPcmFileEncoder` commits complete positional frames, patches Xing metadata before synchronization, truncates failed finalization output to the last committed boundary, and restores a provisional Xing frame for retry.

`requiredMp3SeekPoints`, `buildMp3SeekIndex`, and `findMp3SeekPoint` build a caller-owned positional index at a selected frame stride. Index output may not overlap the encoded source. `Mp3FileReader` provides the same parser and free-format inference through positional file reads and caller-owned frame storage. Its cursor and counters commit atomically after complete frame and metadata parsing. File index output may not overlap frame scratch, and the second construction scan bounds every write if a concurrently changed file contains more seek points than its sizing scan. Its file index helpers scan without loading the complete file, and `seek` validates the selected header and frame-to-sample relationship before changing reader state. File reads do not change the shared file cursor. Complete decoder composition, CBR and VBR encoding, and bounded one-frame reservoir reuse are available. Junk resynchronisation, adaptive multi-frame reservoir policy, VBR-reservoir composition, and broader external encoder interoperability remain separate work.

`Rf64FileWriter`, `Bw64FileWriter`, and `Wave64FileWriter` provide 64-bit file-backed containers with PCM16, PCM24, PCM32, and IEEE f32 encoding. RF64 and BW64 emit their distinct container signatures, mandatory `ds64` sizes, and classic RIFF sentinel values through one shared implementation. `makeBw64Header` provides the bounded header form, while `initBw64`, `initBw64WithMetadata`, and `initBw64WithRiffMetadata` provide incremental output. Wave64 emits the standard RIFF, WAVE, format, and data GUIDs with eight-byte chunk alignment. `Wave64Metadata` adds the registered BEXT and LIST/INFO GUID chunks defined by the [Sony Wave64 specification](https://mab.greyserv.net/f/sony_wave64.pdf). The writer does not invent GUIDs for iXML, aXML, or CHNA, which are not registered by that specification. The writers maintain 64-bit frame and byte counts, expose recovery after an interrupted header update, and validate a complete append before file mutation. Every recovery I/O failure leaves the writer in an explicit failed but recoverable state.

`AudioFileReader` opens caller-owned WAV, AIFF, uncompressed AIFC, RF64, BW64, or Wave64 files, validates their declared chunk boundaries and format arithmetic, and reads arbitrary complete frame ranges into interleaved `f32` or `f64` output. It supports PCM16, PCM24, and PCM32 in every container, plus IEEE f32 in the RIFF-derived containers. AIFC accepts the `NONE` compression type and validates its compression-name bounds. Every range read validates the complete public channel, frame-width, frame-count, and data-extent state before division, modulo, positional I/O, or output mutation. Reads use fixed staging storage and positional file I/O, so the reader does not allocate or change the shared file cursor. Positional chunk offsets and Wave64 eight-byte alignment use checked `u64` arithmetic. `requiredMetadataChunkBytes` reports the exact destination size before `readMetadataChunk` retrieves a complete BWF, iXML, aXML, CHNA, or INFO chunk from WAV, RF64, or BW64. The same APIs canonicalize registered Wave64 BEXT and LIST/INFO chunks into RIFF-shaped borrowed views, including validation of the eight-byte outer alignment. `requiredAdmMetadataBytes` preflights both aXML and CHNA destinations. `readAdmMetadata` rejects incomplete pairs, overlapping buffers, or either short destination before writing either buffer, then returns the validated typed pair.

`encodeInterleavedFlac` writes signed 8-, 16-, 24-, or 32-bit interleaved PCM to caller byte storage. It chooses constant, verbatim, or order 0 through 4 fixed-predictor subframes per channel and searches the standard Rice parameter range for the smallest residual representation. Every direct encoder validates the format before channel arithmetic and rejects overlap between its written destination prefix and source PCM or any borrowed Vorbis-comment descriptor, vendor, name, or value before mutation. Streaminfo records frame bounds, total samples, and the PCM MD5 digest. Every frame carries a checked header CRC-8 and frame CRC-16.

`decodeInterleavedFlac` validates metadata and complete frame boundaries before returning caller-owned interleaved `i32` samples. It decodes constant, verbatim, fixed-predictor, and LPC subframes, both Rice methods, escaped residual partitions, wasted bits, and left-side, side-right, or mid-side stereo. Direct and file-backed decode APIs reject overlap among encoded input, decoded output, decoded-frame scratch, and wide side-channel scratch before parsing, positional reads, or output mutation. The bounded convenience functions `writeInterleavedFlacFile` and `readInterleavedFlacFile` use caller storage for the complete encoded file. They are offline file utilities, not audio-callback streaming primitives.

`FlacFileWriter` incrementally writes PCM blocks with caller-owned pending-sample and encoded-frame storage. `requiredFlacPendingSamples` and `requiredFlacFrameStorageBytes` size those buffers. The buffers and append source must remain disjoint. Every append preflights its worst-case encoded extent before retaining new pending samples, and each frame commit uses checked byte, sample, frame-number, and seek-table offsets. Finalization writes a short terminal block when needed, patches STREAMINFO totals, frame sizes, and the PCM MD5, and synchronizes the file. `initWithOperations` routes initialization, frame commits, recovery truncation, and STREAMINFO patches through the same injectable positional I/O contract as the PCM writers. A failed frame or final header write retains enough state to truncate to the shared exact checkpoint and retry through `recover`. `initWithMetadata` composes validated Vorbis comments with a bounded reserved seek table. Committed frames fill points at the selected interval, while unused capacity remains as standard placeholders.

`FlacFileReader.requiredMetadataBytes` and `requiredFlacFileReaderMetadataBytes` scan positional metadata headers and report the exact caller storage needed for retained blocks. `FlacFileReader.init` retains Vorbis comments plus seek points in that buffer without depending on their file order. `commentIterator` and `seekTableIterator` return borrowed typed views over the storage and contain corrupted public cursor or payload state. Complete and range decoding validate the public stream layout, retained metadata, seek extents, and caller buffer separation before arithmetic or output mutation. Complete decoding reads one compressed frame at a time, validates every frame CRC and the whole-stream PCM MD5, and accepts optional caller-owned 33-bit side scratch. `decodeRange` uses the nearest preceding seek point with separate compressed-frame and decoded-frame scratch.

`encodeInterleavedFlacWithComments` adds one checked FLAC Vorbis-comment block. `FlacCommentIterator` returns borrowed vendor, field-name, and UTF-8 value slices without allocation. Field names accept printable ASCII except `=`, and duplicate or malformed metadata blocks are rejected. `FlacMetadata` and `encodeInterleavedFlacWithMetadata` compose comments and a seek table in one checked file.

`encodeInterleavedFlacWithSeekTable` adds sorted seek points at a caller-selected encoded-frame interval. `FlacSeekTableIterator` validates ordering, uniqueness, placeholders, sample bounds, target block sizes, byte offsets, and target sync codes before returning borrowed points. `decodeInterleavedFlacRange` uses the closest preceding point and caller-owned frame scratch to decode a requested interleaved range. `readInterleavedFlacFileRange` provides the same range contract after loading a bounded file into caller storage. Range decoding validates each decoded frame CRC, but it cannot verify the whole-stream PCM MD5 unless the complete stream is decoded.

The simple decode functions reject a 32-bit stereo decorrelation frame whose side subframe needs 33 bits. `decodeInterleavedFlacWithWideScratch` and `decodeInterleavedFlacRangeWithWideScratch` accept one caller-owned `i64` sample per maximum frame and decode the full FLAC stereo range without allocation. Equivalent file-range support is available through `readInterleavedFlacFileRangeWithWideScratch`.

External Xiph parity remains separate work. File-backed append and recovery now share validated exact or aligned checkpoints while retaining format-specific header, sequence, pending-block, and seek-table commits.

`OggStreamWriter`, `OggPageIterator`, and `OggPacketIterator` implement bounded Ogg version 0 framing from [RFC 3533](https://www.rfc-editor.org/rfc/rfc3533.html). They cover lacing, zero-length terminators, packets continued across maximum-size pages, BOS/EOS flags, stream serials, page sequences, granule positions, and the Ogg CRC polynomial. Page parsing is transactional, so a rejected page does not advance continuation, sequence, EOS, or chained-stream state. Packet assembly also commits its page and segment cursors only after a complete packet is available, which permits retry with larger caller storage after a late capacity failure. Corrupted public cursors and packet-count rollover return errors without slice traps or partial advancement. `OggFileWriter` incrementally writes the same pages through caller-owned maximum-page storage. It validates complete packet framing before mutation, retries short positional writes, restores partial packets through the shared exact checkpoint, and exposes failed but recoverable state when rollback truncation fails. `finalize` requires an EOS packet and synchronizes the file. `OggFilePageReader` and `OggFilePacketReader` provide the same validation through positional file reads with caller-owned page and packet storage. The file page reader rejects past-end cursors and validates the remaining `u64` extent before adding header or body offsets. The file packet reader validates its paired storage bindings, retained page and reload cursors, packet capacity, and counters before optional dereferences or slice indexing. At each packet boundary it retains an allocation-free positional checkpoint. A late capacity failure clears the old storage bindings and reconstructs enough parser state to reload a multi-page packet or a packet that began midway through a chained BOS page. Retrying with larger storage preserves global and logical packet indexes plus seek-skip accounting. The `initChained` reader variants accept sequential logical streams, restart serial and page-sequence validation only after a complete EOS page, and attach a logical-stream index to each page and packet.

`VorbisIdentification`, `VorbisCommentIterator`, and `VorbisHeaders` validate the three required header packets from the [Vorbis I specification](https://xiph.org/vorbis/doc/Vorbis_I_spec.html). `encodeVorbisIdentificationPacket` serializes checked channel, sample-rate, bitrate-hint, and legal block-size fields. `requiredVorbisCommentPacketBytes` and `encodeVorbisCommentPacket` serialize a UTF-8 vendor and printable-ASCII named UTF-8 fields into caller storage. `requiredVorbisSetupPacketBytes` and `encodeVorbisSetupPacket` serialize the complete retained setup model, using canonical unordered codebooks and exact Vorbis packed floats. All three encoders validate capacity and borrowed input before mutation. Variable-length encoders also reject input that overlaps their output. Their packets can be appended directly through either Ogg writer.

`parseVorbisSetup` reads least-significant-bit-first fields without allocation and validates ordered, unordered, and sparse Huffman codebooks, lookup tables, both floor formats, all three residue formats, channel mappings, modes, framing, and component references. Canonical codewords, exact-size Huffman decode trees, sparse entry markers, lookup multiplicands, codebook summaries, floor configurations, and modes use caller-owned storage. `VorbisPacketReader.decodeScalar` follows one tree branch per packet bit and preserves its cursor on truncated input, invalid codewords, or hostile retained state. It also handles the single-entry erratum. `decodeVector` reconstructs type 1 lattice and type 2 explicit vectors with Vorbis float unpacking and sequence accumulation.

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

`VorbisForwardMdct` and `VorbisInverseMdct` use radix-2 FFT reductions with precomputed twiddles and rotations for any legal 64- through 8,192-sample block. The forward transform uses Xiph's normalized Vorbis convention, so forwarding an inverse-transformed spectrum restores the original coefficients within floating-point tolerance. Both directions have windowed forms, allocate no memory, perform no processing-time trigonometry, permit input/output overlap, reject non-finite values, and preserve output on failure. `applyVorbisFloor` multiplies a residue spectrum by its floor after validating the complete operation.

`analyzeVorbisPcmBlock` compares mean-square energy across half-short-block segments of one multichannel large-block candidate. The configurable energy ratio is scale-independent above a configurable RMS floor. The result reports peak, RMS, maximum ratio, and the selected transient boundary, then recommends a short block for detected attacks or decays and a large block for stationary material. f128 accumulation keeps finite f32 and f64 inputs bounded. `selectVorbisEncodingMode` deterministically chooses the lowest retained mode matching a mapping and block size. `planVorbisEncodingBlock` validates the identification and setup, then derives the exact previous and next long-window flags and encoded header width.

`VorbisPcmBlockClassifier` adds stream history to the single-block analysis. It compares the current block power with a smoothed prior reference, enters short mode on either an internal transient or a configurable cross-block energy jump, and requires a lower stable ratio before returning to long mode. A bounded short-block hold prevents rapid mode chatter around a boundary. The state update commits only after configuration, PCM, arithmetic, and retained-state validation. `reset` restores deterministic first-block behavior.

`VorbisPcmBlockLookahead` retains one analyzed decision so the following decision can supply its right-window flag. `push` emits the pending frame and retains the next choice. `finish` emits the final frame with a same-size terminal neighbor, and failures preserve both pending analysis and frame position. `VorbisPcmFramePlanner` carries the previous block choice and advances signed block centers by one quarter of the current size plus one quarter of the next size. Each plan reports its packet index, header, signed source start, PCM advance, and next center. Invalid setup, packet-count exhaustion, and position overflow preserve the complete planner state. `extractVorbisPcmBlock` copies a planned multichannel source window and zero-pads leading or trailing positions outside the stream. It validates channel shape, finite source samples, position arithmetic, and aliases before changing any output.

`VorbisPcmPacketSequence` coordinates the classifier, lookahead, frame planner, bit reservoir, packet index, and encoder granule without advancing live packet state during planning. `planNext` returns a caller-owned trial containing the next classification, frame, budget, granule, and complete staged state. Nonterminal granules describe PCM completed before the current packet, so the first packet has granule zero. `planFinish` flushes the delayed frame once and accepts an exact EOS length no greater than the terminal packet's completed center. `appendMemory` preflights the state commit and Ogg append through copies, then publishes both together. `appendFile` relies on the file writer's positional rollback and advances the encoder only after a successful append. Stale, forged, zero-bit, overflowing, out-of-order, or impossible terminal plans preserve every live state machine. Direct `commit` is available when another destination has already accepted the packet.

`requiredVorbisPcmPacketEncodingStorage` combines the exact preparation and mapping-driven quantization capacities for a planned frame. `encodeVorbisPcmPacketTrial` accepts a retained frame analysis and a live sequence plan, prepares Floor 1 and coupled residue data in trial storage, quantizes every mapped submap, counts the final packet, and preflights the exact reservoir commit against copied sequence state. It encodes the packet and publishes retained borrowed preparation and quantization plans only after every step succeeds. The live sequence remains unchanged until the caller passes the returned packet and original plan to `appendMemory`, `appendFile`, or `commit`.

`encodeVorbisPcmPacket` adds the complete PCM front end to the same trial contract. It extracts the planned frame with boundary padding, runs the configured multichannel forward transform and psychoacoustic analysis, then delegates floor preparation, coupling, adaptive residue quantization, and packet encoding to `encodeVorbisPcmPacketTrial`. `VorbisPcmPacketOrchestrationScratch` separates analysis scratch and retained analysis workspace from the packet destination and retained encoding storage.

`VorbisPcmBlockTransform` owns precomputed windows plus short and long forward MDCT plans. It transforms every channel for a planned header into caller scratch, then commits all coefficient outputs together. Inputs may overlap outputs because no output changes until every channel succeeds. Output channels must remain separate, and used scratch cannot overlap input or output. Both block sizes, all four long-window transitions, f32, and f64 use the same API.

`VorbisPcmFrameAnalyzer` composes planned source extraction, boundary padding, transition-window selection, normalized forward MDCT, and multichannel psychoacoustic analysis. `requiredStorage` reports the exact scratch and retained capacities for the frame header. The analyzer publishes flattened spectra, channel analyses, Floor 1 targets, and masking thresholds only after every stage succeeds. Returned slices borrow from retained caller storage. Trial planes, retained planes, input slice descriptors, and input samples must not overlap.

`analyzeVorbisPsychoacoustics` maps a finite normalized spectrum into configurable Bark-spaced bands. Per-band arithmetic and geometric power means produce spectral flatness and tonality. Tonal and noise masking offsets feed an asymmetric spreading model over Bark distance, while a normalized absolute threshold bounds empty regions. Quality scales a checked maximum relaxation in decibels. The function returns peak, RMS, global flatness, tonality, active-band count, and relaxation while transactionally producing a spectral envelope for Floor 1 fitting plus a per-bin noise threshold. Silent spectra produce zero targets and an unused-floor-compatible result. Input may overlap one output because all spectral statistics complete before output mutation.

`requiredVorbisAudioPsychoacousticStorage` reports exact retained analysis and flattened value-plane capacities for a multichannel spectrum bundle. `analyzeVorbisAudioPsychoacoustics` validates every channel shape and coefficient before analysis, uses separate caller-owned trial targets and thresholds, and commits the analyses, Floor 1 targets, and masking thresholds together only after every channel succeeds. Returned prefixes borrow from retained storage, unused suffixes remain unchanged, and no spectrum or slice descriptor may overlap trial or retained storage.

`evaluateVorbisRateDistortion` compares reconstructed coefficients against those thresholds. It reports the maximum noise-to-mask ratio, summed weighted squared error, power above the mask, and whether the complete block remains masked. A nonzero error against a zero threshold returns explicit infinite distortion.

`VorbisBitReservoir` converts each frame's exact PCM advance into a rounded nominal packet budget at the configured bitrate. Credit from undersized packets and debt from oversized packets feed the next target over a configurable correction window. Minimum and maximum packet bounds remain explicit. One budget may be pending at a time, successful commits advance packet state, cancellation discards only the pending budget, and capacity violations or corrupted pending state preserve the reservoir for a lower-distortion retry. Use `allocateVorbisResidueBitBudgets` to derive per-submap adaptive quantizer targets after measuring the fixed packet cost.

`VorbisOverlapAdd` retains one windowed block and returns the exact sample range between consecutive block centers. It handles every legal short/long transition, primes without emitting the first block, and contains invalid state, aliasing, non-finite samples, and overflow before changing output or retained history. `VorbisChannelOverlapAdd` prepares every channel before committing any channel, so a malformed channel cannot advance part of a multichannel stream.

`VorbisAudioPacketDecoder` composes floor decoding, nonzero propagation, submap residue bundles, inverse coupling, floor application, transition windows, and inverse MDCT. `requiredVorbisAudioPacketScratch` reports the exact spectrum, floor, coupling, time-domain, and classification capacities. Large classification storage remains caller-owned, and packet failures preserve all channel outputs.

`VorbisGranuleTracker` converts finished overlap ranges into signed PCM positions. It handles inferred negative or positive starts, delayed first granules, short streams, and final-page tail trimming. `VorbisPcmStreamDecoder` combines packet decoding, atomic multichannel overlap, granule trimming, priming, reset, and EOS containment for one retained setup. Returned samples occupy the prefix of each caller output channel.

`requiredVorbisSeekPoints` and `buildVorbisSeekIndex` scan an in-memory chained stream into caller-owned points. Their file-backed counterparts use caller-owned page storage and positional reads. Each point records the page and packet identity for the target granule plus the preceding audio packet needed to prime overlap. `findVorbisSeekPoint` selects within one logical stream, and `OggFilePacketReader.seek` validates and repositions transactionally before discarding earlier packet completions on the start page. After resetting the PCM decoder, decode from the selected prime packet and pass each result through `VorbisPcmSeekCursor.select` until it returns the suffix at the requested signed PCM position. The index is not a substitute for parsing and retaining the three headers of each logical stream.

An end-to-end test writes identification, comment, setup, and audio packets into Ogg pages, parses them back, retains setup, builds matching memory and file seek indexes, repositions the file reader, and decodes the requested PCM suffix. Header integration tests generate all three packets through the public encoders, paginate them, and parse the result through `VorbisHeaders`. Setup round trips cover ordered, unordered, sparse, and deep codebooks, both lookup forms, 1–16-bit multiplicands, floor types 0 and 1, every residue and mapping field, channel coupling, submaps, modes, packed-float validation, capacity, and overlap preservation. A generated stereo audio packet crosses two submaps and one coupling step before decoding through the complete packet pipeline. Planned residue fixtures round trip all three layouts, classbook-constrained classification, skipped channels, and multi-pass reconstruction through the packet writer and decoder. Adaptive fixtures prove exact high-quality selection, lower-rate fallback, impossible-budget reporting, mask-weighted metrics, both float precisions, exact weighted submap allocation, equal-weight rounding, capacity preservation, invalid thresholds and configuration, and alias rejection. Mapping-driven fixtures group two independently mapped submaps, derive exact active-classword entry capacity, reuse bounded scratch, publish borrowed encodings and per-submap evidence atomically, compose with packet-writer cost measurement, and preserve retained state on late threshold, capacity, and alias failures. Floor fixtures fit both float precisions, round trip raw values through packet encoding and decoding, synthesize the retained curve, normalize signed residue, and reconstruct the original spectrum. Multichannel floor fixtures prove exact storage sizing, active and silent channel publication, retained borrowed ranges, fixed-cost skip composition, complete rollback, suffix preservation, Floor 0 rejection, capacity errors, and storage aliases. Mixed-silence preparation fixtures also prove fitted-floor reconstruction after normalization and coupling, safe threshold propagation, and transactional failure after floor fitting. PCM analysis fixtures distinguish stationary material from multichannel attacks, stabilize cross-block energy jumps through hysteresis and a bounded hold, schedule decisions through one-block lookahead, plan mixed short and long center sequences, zero-pad stream boundaries, and match direct windowed transforms across block transitions. Sequence fixtures prove non-mutating packet trials, stale and hostile-plan rejection, memory and file append rollback, exact terminal flush, and EOS granule publication for f32 and f64 analysis. Composed encoding fixtures bind a retained frame analysis to a live sequence revision, prepare and quantize through trial storage, preflight exact rate state, publish the final packet and retained borrowed plans together, and preserve packet, storage, and sequence state on capacity, alias, stale-plan, and reservoir failures. Psychoacoustic fixtures distinguish a sparse tone from a flat spectrum, prove monotonic quality relaxation, evaluate masked and audible reconstruction error, preserve aliased and failed outputs, and exercise packet credit, debt, clamping, cancellation, overflow, and hostile reservoir state. Forward and inverse coupling fixtures cover every sign branch, magnitude ties, and dependent multistep mappings. Chained Ogg readers expose each new logical-stream boundary so the caller can parse its three headers and construct the matching typed decoder. The generated interoperability fixture carries used Floor 1 data, scalar classbook words, active lookup-type-2 vector residue, exact priming and output granules, and EOS through the public encoders. The repository gate uses FFmpeg when available. On macOS it also uses AudioToolbox when `afinfo` can open Vorbis, requires a 48 kHz nonsilent PCM decode, and distinguishes an unavailable decoder from a later conversion failure. Broader Xiph packet parity, additional third-party decoders, and external-encoder input coverage remain open.

`decodeMonoWav` reads bounded in-memory PCM16, IEEE f32, and IEEE f64 mono WAV fixtures. It is an offline test utility. It does not perform file access, allocate memory, or belong in an audio callback.

The repository fixture test generates its input and C++ reference renders, then compares Zig f32 and f64 output using fixed and randomized blocks:

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test-dsp-fixtures
```

The command records architecture, model, sample format, sample rate, backend, elapsed time per sample, and numerical metrics. It also enforces a 100 ns per sample regression ceiling. That ceiling detects major regressions while leaving room for translated and shared CI environments.

Use `zig build test-dsp-fixture-builds` to compile the fixture API for Linux aarch64, Linux x86-64, and Windows x86-64 without attempting to run cross-target binaries.

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

Rates must be finite and between 1 kHz and 2 MHz. Non-finite input samples are replaced with zero. The filter cutoff is reduced while downsampling to reject content above the destination Nyquist limit. Correction changes are transactional, and malformed cached step or phase state is rejected. `initBackend` and `configureBackend` force a vector width for deterministic parity tests. On the current NEON development machine, 44.1 to 48 kHz f32 conversion measured 6.9 ns per input sample, compared with 15.8 ns for the scalar path. The implementation is part of this repository and uses the repository license.

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

## Reference implementation

The fixed-mode public-API example is split between `examples/fixed_rate_core.zig` and `examples/fixed_rate_plugin.zig`. The context-dependent resource example is split between `examples/model_shell_core.zig` and `examples/model_shell_plugin.zig`.

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-fixed-rate validate-fixed-rate
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-model-shell validate-model-shell
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build benchmark
```
