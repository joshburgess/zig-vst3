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
Q15	zig-vst3-plugin/src/dsp/ballistics.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/biquad.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/buffer_regions.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/butterworth_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chebyshev2_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chebyshev_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/chorus.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/convolution.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/delay.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/denormals.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/dry_wet.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/dynamics.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/elliptic_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/equiripple_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/fast_math.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/fft.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/fir.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/fir_design.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/first_order_tpt.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/fixed_rate.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/fixture_runner.zig	EXCLUDED	independent-fixture process runner
Q15	zig-vst3-plugin/src/dsp/flanger.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/gain_bias.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/inter_sample_limiter.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/kernel_dispatch.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/ladder.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/linkwitz_riley.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/log_ramp.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/lookup_table.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/mixed_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/modulated_delay.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/modulation_rate.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/multiband_dynamics.zig	EVIDENCE	N-DYNAMICS
Q15	zig-vst3-plugin/src/dsp/multichannel_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/multichannel_polyphase_iir_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/oscillator.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/panner.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/pcm_dither.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/phase.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/phaser.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/polynomial.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/polyphase_fir.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/polyphase_iir.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/polyphase_iir_oversampling.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/process_context.zig	EXCLUDED	format-neutral processing value view
Q15	zig-vst3-plugin/src/dsp/processor_chain.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/processor_duplicator.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/realtime_snapshot.zig	EXCLUDED	fixed-storage concurrency primitive
Q15	zig-vst3-plugin/src/dsp/resampler.zig	EVIDENCE	N-TRANSFORM
Q15	zig-vst3-plugin/src/dsp/reverb.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/shared_processor_duplicator.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/simd_register.zig	EVIDENCE	N-PRIMITIVE
Q15	zig-vst3-plugin/src/dsp/smoothed_value.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/special_functions.zig	EVIDENCE	N-FILTER
Q15	zig-vst3-plugin/src/dsp/state_variable.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/stereo_modulation.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/vibrato.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/wave64_metadata.zig	EXCLUDED	passive metadata values
Q15	zig-vst3-plugin/src/dsp/waveshaper.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/dsp/window.zig	REVIEW	N-PENDING
Q15	zig-vst3-plugin/src/gui_ir_convolution.zig	EXCLUDED	public compatibility alias
<!-- numerical-files:end -->

## Benchmark Families

`tools/benchmark.zig` records fixed regression budgets for framework blocks,
state and resource exchange, GUI snapshots, import and preparation work,
resampling, advanced filter design, oversampling, dynamics, ADM diffuse
rendering, snapshot publication, Vorbis transforms, dispatched kernels, and C
kernel comparisons. Parser scaling benchmarks remain recorded in
`verification.md`. Phase 5 must review input shapes and thresholds before this
section can close.

## Current Disposition

The first ledger pass intentionally leaves `REVIEW` records open. It establishes
complete scope and prevents later source additions or unit moves from silently
escaping Phase 5. A source moves to `EVIDENCE` only after its numerical and
performance contracts have been inspected and its evidence family is accurate.

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
