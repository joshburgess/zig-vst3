# Numerical and Performance Review

This ledger is the checked Phase 5 scope for Q13, Q14, and Q15. The inventory
script requires one record for every source assigned to those review units and
rejects missing, stale, duplicate, malformed, or misassigned records.

States have narrow meanings:

- `EVIDENCE`: existing independent vectors, defining-transform comparisons,
  higher-precision references, or strong mathematical identities are present.
- `REVIEW`: numerical behavior or performance still needs Phase 5 inspection.
- `EXCLUDED`: the source is a facade, test harness, transport, parser, or value
  declaration without an algorithmic numerical contract. The final field
  records the exclusion reason.

An `EVIDENCE` record is an inventory disposition, not automatic Phase 5
closure. The evidence family must still be checked for stated tolerances,
finite containment, latency, channel and layout behavior, transactionality,
and representative performance where those concerns apply.

## Evidence Families

| ID | Scope | Present evidence |
| --- | --- | --- |
| N-ADM | ADM panning, extent, matrix, diffuse, binaural, and HOA rendering | Independent C++ reference renderer, libspatialaudio HOA parity, higher-precision diffuse comparison, geometric identities, partition invariance, latency and transactional tests |
| N-HRTF | HRTF loading, interpolation, convolution, and spatial matrices | libmysofa and libspatialaudio parity, NetCDF comparisons, public datasets, matrix reconstruction identities, partition invariance, and sanitizer stress |
| N-FILTER | IIR and FIR design plus special functions | SciPy 1.17 vectors, independent ODE vectors, response identities, reconstruction, convergence, maximum-size finite containment, and transactional failures |
| N-TRANSFORM | FFT, convolution, resampling, oversampling, and limiters | Defining transforms, direct convolution, backend parity, sinc reconstruction, response and recombination identities, partition invariance, latency, and transactional failures |
| N-DYNAMICS | Dynamics and multiband processing | Independent scalar vectors, static-curve and recombination identities, peak containment, partition invariance, latency, and transactional failures |
| N-EFFECT | Modulation, nonlinear shaping, and algorithmic reverb | Static-delay and feedback vectors, all-pass and symmetry identities, partition invariance, tempo and parameter smoothing, stereo decorrelation, finite containment, and transactional aliases |
| N-PRIMITIVE | Scalar, SIMD, phase, smoothing, and buffer primitives | Scalar-oracle parity, algebraic identities, alias matrices, finite containment, overflow rejection, and transactional destinations |
| N-PENDING | Algorithmic source requiring Phase 5 review | Evidence and contract disposition have not yet been accepted |

## Checked Source Inventory

The records are tab-separated so the checker can compare exact paths without
interpreting prose or Markdown tables.

<!-- numerical-files:start -->
Q13	zig-vst3-plugin/src/dsp/adm.zig	EXCLUDED	ADM identifier and CHNA container serialization
Q13	zig-vst3-plugin/src/dsp/adm_binaural.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_cartesian_extent.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_diffuse.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_direct_speaker_mapping.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_hoa_decoder.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_hoa_dual_band.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_hoa_matrix.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_hoa_radial.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_polar_extent.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_polar_panner.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_render.zig	EXCLUDED	public compatibility facade
Q13	zig-vst3-plugin/src/dsp/adm_render/common.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_render/direct_speaker.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_render/matrix.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_render/object.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_render/panner.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_sample_time.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_time.zig	EVIDENCE	N-ADM
Q13	zig-vst3-plugin/src/dsp/adm_xml.zig	EXCLUDED	parser facade
Q13	zig-vst3-plugin/src/dsp/adm_xml/block.zig	EXCLUDED	XML block parser and validation
Q13	zig-vst3-plugin/src/dsp/adm_xml/common.zig	EXCLUDED	XML vocabulary
Q13	zig-vst3-plugin/src/dsp/adm_xml/core.zig	EXCLUDED	bounded XML document and graph model
Q13	zig-vst3-plugin/src/dsp/adm_xml/emission.zig	EXCLUDED	XML emission-profile reader
Q13	zig-vst3-plugin/src/dsp/adm_xml/metadata.zig	EXCLUDED	XML metadata traversal
Q13	zig-vst3-plugin/src/dsp/adm_xml/model.zig	EXCLUDED	passive metadata values
Q13	zig-vst3-plugin/src/dsp/adm_xml/standard.zig	EXCLUDED	XML declaration and reference traversal
Q14	zig-vst3-plugin/src/dsp/hrtf.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/dsp/hrtf/motion.zig	EXCLUDED	clock calibration and bounded transport
Q14	zig-vst3-plugin/src/dsp/hrtf/spatial.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/dsp/hrtf_sofa.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/dsp/hrtf_stream.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/dsp/matrix.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/dsp/matrix/dynamic.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/hoa_tests.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/hrtf_tests.zig	EVIDENCE	N-HRTF
Q14	zig-vst3-plugin/src/hrtf_thread_sanitizer.zig	EXCLUDED	concurrency test root
Q15	zig-vst3-plugin/src/dsp.zig	EXCLUDED	public module facade
Q15	zig-vst3-plugin/src/dsp/audio_block.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/ballistics.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/biquad.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/buffer_regions.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/butterworth_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chebyshev2_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chebyshev_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chorus.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/convolution.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/delay.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/denormals.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/dry_wet.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/dynamics.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/elliptic_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/equiripple_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/fast_math.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/fft.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/fir.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/fir_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/first_order_tpt.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/fixed_rate.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/fixture_runner.zig	EXCLUDED	independent-fixture process runner
Q15	zig-vst3-plugin/src/dsp/flanger.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/gain_bias.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/inter_sample_limiter.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/kernel_dispatch.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/ladder.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/linkwitz_riley.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/log_ramp.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/lookup_table.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/mixed_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/modulated_delay.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/modulation_rate.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/multiband_dynamics.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/multichannel_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/multichannel_polyphase_iir_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/oscillator.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/panner.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/pcm_dither.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/phase.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/phaser.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/polynomial.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/polyphase_fir.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/polyphase_iir.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/polyphase_iir_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/process_context.zig	EXCLUDED	format-neutral processing value view
Q15	zig-vst3-plugin/src/dsp/processor_chain.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/processor_duplicator.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/realtime_snapshot.zig	EXCLUDED	fixed-storage concurrency primitive
Q15	zig-vst3-plugin/src/dsp/resampler.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/reverb.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/shared_processor_duplicator.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/simd_register.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/smoothed_value.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/special_functions.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/state_variable.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/stereo_modulation.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/vibrato.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/wave64_metadata.zig	EXCLUDED	passive metadata values
Q15	zig-vst3-plugin/src/dsp/waveshaper.zig	EVIDENCE	N-EFFECT
Q15	zig-vst3-plugin/src/dsp/window.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/gui_ir_convolution.zig	EXCLUDED	public compatibility alias
<!-- numerical-files:end -->

## Benchmark Families

`tools/benchmark.zig` is the executable timing and memory ledger. Its `Budget`
record is the source of truth for every ceiling. The following table records
the representative workloads that close the four Phase 5 performance classes.

| Class | Workload | Regression threshold |
| --- | --- | --- |
| Setup | 8 MiB mono PCM WAV import; 262,144-frame sample decode and preview construction | At least 50 MiB/s; at most 500 ms |
| Setup | 131,072-frame mono IR, 512-sample partitions | At most 500 ms preparation and 1 ms pending adoption |
| Setup | Order-six Chebyshev II and elliptic filters; complex and inverse complex Jacobi; 63-tap, two-band least-squares and equiripple FIR; two-stage 4x mixed oversampler | At most 1 ms, 5 ms, 10 us, 10 us, 100 ms, 200 ms, and 500 ms per design, respectively |
| Realtime | 512-frame framework block; scalar and native 44.1-to-48 kHz resampling; fixed 48 kHz model at 44.1, 48, 88.2, and 96 kHz host rates | At most 50 us/block, 500 ns/input sample, and 2 us/sample |
| Realtime | 4x mixed oversampling; lookahead and 4x inter-sample limiters; four-band compressor | At most 5 us, 2 us, 5 us, and 5 us per sample |
| Realtime | Twelve-output ADM diffuse rendering in f32 and f64 at 16, 64, and 512 frames; 131,072-frame IR convolution with 512-sample partitions | At most 5 us/output sample and 20 us/sample |
| Realtime | Snapshot publish, read, partial reference update, and publish attempt with one concurrent reader across 20,000 operations | At most 1 us, 1 us, 2 us, and 2 us per attempt |
| Realtime | Forward and inverse Vorbis MDCT at 64, 256, and 2,048 samples; scalar and detected buffer kernels at 8, 32, 128, and 512 samples | At most 500 ns/sample and 100 ns/sample |
| Memory | 262,144-frame decoded importer and eight-voice player | At most 3 MiB and 7 MiB fixed storage |
| Memory | 131,072-frame IR convolver with 512-sample partitions, decoded importer, and editor | At most 20 MiB, 2 MiB, and 4 MiB fixed storage |
| Hostile scaling | MIDI file parse and traversal at 1,000, 2,000, and 4,000 events; UMP traversal at 1,024, 2,048, and 4,096 packets | At most 2 us/item and 1.75x per-item growth between adjacent sizes |
| Hostile scaling | ADM XML at 128, 256, and 512 declaration-reference pairs | At most 1 ms/pair and 1.6x per-pair growth between adjacent sizes |
| Hostile scaling | Vorbis, FLAC, ID3v2.3, ID3v2.4, RIFF INFO, and AIFF text traversal at 256, 512, and 1,024 entries | At most 5 us/entry and 2x per-entry growth from the 256-entry baseline |

The main benchmark also enforces state and resource exchange, GUI snapshot,
sample publication and playback, dense Zig and C kernels, denormal-tail, and
resource-identity budgets. `verification.md` records the measured results and
the separate parser-scaling commands.

## Current Disposition

The checked ledger is complete at 83 `EVIDENCE`, zero `REVIEW`, and 18
`EXCLUDED` records. The inventory gate prevents later source additions or unit
moves from silently escaping Phase 5. A source remains `EVIDENCE` only while
its numerical and performance contracts and named evidence family stay
accurate.

## Accepted Review Units

### ADM and HRTF Shared Values

The first review accepts exact ADM time and sample-position arithmetic, common
speaker mapping, renderer geometry helpers, and HRTF spatial conversion. ADM
time parsing bounds every decimal and sample representation to checked integer
storage. Addition, comparison, ceiling conversion, and interpolation preserve
exact rational values through `u1024`; floating-point conversion occurs only
for the final clamped phase. Tests cover unlike denominators, values beyond
the exact f64 integer range, malformed denominators, parse overflow, sequence
transactionality, and partitioned renderer equivalence.

Common speaker mappings use the standard layout rule vectors and reject
malformed retained gain views. Renderer geometry is exercised by independent
polar and Cartesian gain vectors, screen-layout reference positions, power
preservation, tie behavior, finite containment, buffer alias rejection, and
transactional output. HRTF position conversion uses an explicit right-handed
world-to-head rotation. Room-plan vectors independently recompute distance,
reflection gain, delay, and rotated azimuth with absolute tolerances of
`1e-12` for direction and gain and `1e-9` samples for delay. The HRTF matrix,
dataset, partition, and cross-target evidence remains in N-HRTF.

`adm.zig` is excluded from the numerical phase because it owns identifiers and
exact CHNA byte serialization, not rendering arithmetic. Its normative stereo
bytes, malformed-state, overlap, reserved-entry, parser, and positional-write
tests remain parser and persistence evidence.

### Audio Block Arithmetic and Aliasing

Audio-block construction and mutation now make the planar storage contract
explicit. Mutable channels are disjoint. Copy, scaled addition, subtraction,
sum replacement, and product replacement preflight every destination-source
pair. Exact corresponding in-place sources are valid, while shifted and
cross-channel aliases fail before output changes. Checked span arithmetic
treats a hostile address calculation as overlap. Existing finite-input and
overflow preflights preserve transactional arithmetic, and aggregate values
retain direct scalar expectations.
