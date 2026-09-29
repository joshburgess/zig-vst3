# Realtime Processing Inventory

This record maps every production example processor to its transitive work
bound. `scripts/check_realtime_source_inventory.sh` keeps the source appendix
identical to the direct callback audit. The lexical audit rejects forbidden
operations in callback bodies. This record supplies the semantic helper and
loop review that lexical matching cannot provide.

## Phase 2 Review Result

All 26 production processors have a recorded transitive processing chain,
shared-state contract, concrete work bound, and failure behavior. The checked
inventory and its negative fixtures reject missing source or contract entries.
Focused VST3 tests verify negotiated block limits and bounded hostile host
traversal. GitHub Actions run `31858188014` at `4466af3d` passed the complete
public gate, and no critical or high realtime finding remains open.

## Boundary Contract

Processing receives borrowed channel, parameter, event, and transport views.
The views remain valid only for the callback. Processing may mutate output
buffers and processor-owned fixed storage, but it may not retain host slices.

The adapters establish the outer bound:

- VST3 stores the successful `setupProcessing.maxSamplesPerBlock` value and
  rejects a later oversized block. Input parameter queue visits, parameter
  point visits, and event visits are each capped at 64, including invalid host
  entries. Output event storage is fixed at 64 entries.
- Audio Unit and LV2 expose only the configured block slices to the processor.
  Standalone and host-neutral runtimes likewise construct views from their
  configured maximum block. No processor may assume an unbounded backing
  buffer beyond the supplied view.
- Event and parameter segment iterators advance monotonically through fixed
  adapter storage. Their work is bounded by the stored entry count and frame
  count, not by an unchecked host-reported count.

Host-negotiated frame bounds are finite for one configured instance but are not
compile-time constants. Processors with larger internal requirements impose
their own fixed limits and use bypass, silence, or failure counters when those
limits are exceeded.

## Transitive Work Review

| Family | Sources | Transitive processing chain | Work bound and shared state |
| --- | --- | --- | --- |
| Scalar gain, bypass, and routing | Auxiliary Output Splitter variants, Bypass, Gain variants, Mode Gain, Mono Gain variants, Sidechain Ducker, Surround Gain, Voice Mix | Public process form to a local `processBlock` or direct channel loop to scalar parameter access | At most supplied frames times the fixed input and output topology. Parameter reads are independent atomics or callback-local views. No allocation, locks, host calls, or reclamation. |
| Events and synthesis | Event Echo, Event Monitor, Note Gate, Sine Synth | Process callback to fixed event iteration, parameter segmentation, and per-frame state update | At most 64 accepted VST3 input event or parameter attempts at the adapter, then at most supplied frames. Output event capacity is fixed. Note and voice state uses fixed arrays. |
| C kernel | C Kernel | Process callback to one fixed 4 by 4 native kernel invocation per `f32` frame; `f64` copies channels | At most supplied frames times four channels. The native function owns no dynamic state and performs no blocking operation. |
| Channel Strip and filters | Channel Strip, Parametric EQ, Resonant Filter | Parameter segmentation to fixed biquad and smoother chains, per-frame channel loops, and optional spectrum publication | At most supplied frames times two channels and a compile-time filter count. Smoothing is fixed at 64 steps. Spectrum work uses fixed storage and publishes immutable snapshots only while an editor is active. |
| Fixed Rate | Fixed Rate | Process callback to fixed-rate pipeline input conversion, model transform, and output conversion | Host frames are rejected or bypassed above 8,192. Scratch capacity is `8,192 * 8 + 2`. Conversion loops are bounded by those arrays; failure resets and copies the supplied block. |
| Model Shell | Model Shell | Parameter view to block-boundary prepared-model adoption, fixed-rate conversion, model sample processing, and snapshot publication | Host frames are rejected above 4,096. Model scratch is `4,096 * 8 + 2`; publication uses four immutable slots. Adoption never waits or reclaims. |
| Resource Swap | Resource Swap | Process callback to one fixed-slot exchange adoption followed by active processor work | The exchange has four slots. Adoption and retirement examine only fixed slot state; the active gain loop is bounded by channels and supplied frames. Preparation and reclamation stay on control or worker threads. |
| Sample Player | Sample Player | Parameter segmentation and event iteration to per-frame traversal of active fixed voices and immutable sample-store lease | At most supplied frames, adapter-capped events, and eight voices. Sample storage is capped at 262,144 frames. The callback only acquires and releases immutable fixed-slot state. |
| IR Loader | IR Loader | Parameter segmentation to one partitioned-convolver block operation, dry-delay update, and telemetry publication | IR storage is capped at 131,072 frames with 512-frame partitions. FFT and partition counts are fixed after preparation. The callback never imports, prepares, or reclaims an IR. |
| ARA playback | ARA Playback | Process callback to reader lease, cache or transform lookup, renderer, and copy from fixed scratch | At most four regions, two channels, 256 output frames, 256 source frames per region, and eight sinc taps. Oversized output is cleared. Reader and snapshot acquisition are bounded and nonblocking. |

The GUI analysis reached by Channel Strip and IR-related processors uses fixed
waveform or spectrum storage. Publication is a bounded atomic slot operation.
Editor refresh, file decoding, graph construction, and resource preparation are
control or worker work and are not reachable from the processing call chain.

## Failure Behavior

- An invalid or oversized VST3 block is rejected before host collection or
  processor invocation.
- Unsupported Fixed Rate blocks copy input to output. A conversion failure
  copies the block and resets fixed pipeline state.
- ARA blocks larger than fixed render scratch are cleared and counted.
- Missing channels, resources, readers, or transport data use the processor's
  documented silence, bypass, or no-op path without acquiring control locks.
- Fixed-capacity event, telemetry, and publication paths drop or count excess
  work. They do not allocate to preserve it.

## Checked Source Appendix

Every path below must also occur exactly once in
`examples/realtime_source_audit.zig` and in the discovered production processor
set.

<!-- realtime-sources:start -->
- `examples/ara_playback_plugin.zig`
- `examples/aux_output_splitter_audio_unit.zig`
- `examples/aux_output_splitter_core.zig`
- `examples/bypass_core.zig`
- `examples/c_kernel_core.zig`
- `examples/channel_strip_plugin.zig`
- `examples/event_echo_core.zig`
- `examples/event_monitor_core.zig`
- `examples/fixed_rate_core.zig`
- `examples/gain_core.zig`
- `examples/ir_loader_plugin.zig`
- `examples/mode_gain_core.zig`
- `examples/model_shell_core.zig`
- `examples/mono_gain_audio_unit.zig`
- `examples/mono_gain_core.zig`
- `examples/mono_gain_lv2_shared.zig`
- `examples/mono_gain_plugin.zig`
- `examples/note_gate_core.zig`
- `examples/parametric_eq_plugin.zig`
- `examples/resonant_filter_plugin.zig`
- `examples/resource_swap_core.zig`
- `examples/sample_player_plugin.zig`
- `examples/sidechain_ducker_core.zig`
- `examples/sine_synth_core.zig`
- `examples/surround_gain_core.zig`
- `examples/voice_mix_core.zig`
<!-- realtime-sources:end -->
