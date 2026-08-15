# Quality Review Inventory

`scripts/check_quality_inventory.sh` classifies every tracked source file. It
fails when a new source file has no review unit. Run it after changing source
layout or inventory rules.

The checked inventory contains 823 source files and 471,806 source lines.
These totals include tests, tools, scripts, imported headers, and embedded data.
They are workload measures, not implementation-size claims.

## Risk Model

Each review unit has four scores from 1 (low) through 5 (high): consequence
(`C`), exposure (`E`), complexity (`X`), and present test strength (`T`). The
risk score is `C + E + X + (6 - T)`.

| Score | Rank | Required treatment |
| --- | --- | --- |
| 16–20 | High | Review first; focused adversarial evidence required |
| 12–15 | Elevated | Dedicated review and subsystem gate required |
| 8–11 | Moderate | Review after higher-risk dependencies |
| 4–7 | Low | Structural review and repository gate |

The score orders work. It does not lower the severity of a concrete finding.

Except for material listed under Source Origin, the line counts are the current
estimate of repository-maintained handwritten source and tests. Test blocks are
often colocated with production declarations, so separating them by file would
misstate review effort.

## Review Units

| Unit | Scope | Files | Lines | C/E/X/T | Rank | Principal exposure | Required verification |
| --- | --- | ---: | ---: | --- | --- | --- | --- |
| Q00 | Build graph, CI, release and validation scripts | 126 | 17,757 | 4/4/5/4 | Elevated | Release contents, tool execution, cross-target gates | Script fixtures, package smoke, clean-tree release graph |
| Q01 | Raw VST3 ABI mirrors and COM helpers | 114 | 28,988 | 5/5/4/5 | Elevated | Public ABI, pointers, reference counts, host callbacks | SDK layout parity, callback lifecycle, validators, sanitizers |
| Q02 | ARA model, controller, analysis, cache, and official headers | 15 | 27,714 | 5/4/5/3 | High | Host callbacks, readers, atomics, persistence, untrusted host data | Header parity, lifecycle stress, allocator failure, TSan, state corruption |
| Q03 | Raw VSTGUI and Wayland bridges | 7 | 6,152 | 5/4/4/3 | Elevated | COM identities, native handles, callback teardown | ABI checks, ASan/UBSan/TSan, attach-detach and reentrancy stress |
| Q04 | Raw-to-framework VST3 processor and controller adapters | 3 | 11,883 | 5/5/5/4 | High | Realtime host entry, dual state stores, resource publication | Lifecycle model, failure silence, host mutation, sanitizer stress |
| Q05 | Raw-package example plugin declarations | 18 | 758 | 2/2/2/4 | Moderate | Factory examples and public construction patterns | Compile, validator, package examples |
| Q06 | Framework declaration, lifecycle, topology, and runtime core | 16 | 9,592 | 5/5/5/4 | High | Public compatibility, ownership, realtime processing | API manifest, state-machine tests, allocator failure, bounded-work audit |
| Q07 | Parameters, state, units, and resources | 23 | 13,905 | 5/5/4/4 | Elevated | Persistence, background work, publication, public API | Migration corpus, transactionality, allocator failure, TSan |
| Q08 | Process context, events, changes, segmentation, and ordering | 5 | 9,114 | 5/5/5/4 | High | Host-controlled counts and pointers on realtime path | Boundary generation, malformed host data, partition invariance |
| Q09 | MIDI 1, MIDI 2, MIDI-CI, MPE, files, streams, and sessions | 33 | 20,657 | 4/5/5/3 | High | Untrusted byte streams, bounded queues, session state | Fuzzing, truncation, progress, capacity, deterministic state models |
| Q10 | Ogg and Vorbis | 1 | 31,085 | 5/5/5/4 | High | Untrusted packets, checked arithmetic, codec state, seeking | Fuzzing, truncation, sanitizer runs, independent decoders |
| Q11 | MP3 | 3 | 30,826 | 5/5/5/4 | High | Untrusted frames, bit reservoirs, Huffman data, synthesis | Fuzzing, corruption, sanitizer runs, independent decoders |
| Q12 | FLAC, audio containers, metadata, and file I/O | 15 | 23,821 | 5/5/5/4 | High | Untrusted files, XML, arithmetic, transactional output | Fuzzing, short I/O, failure injection, independent tools |
| Q13 | ADM parsing and rendering | 15 | 33,905 | 5/4/5/4 | High | XML, timed metadata, matrix construction, exclusion rules | Fuzzing, numerical oracles, bounded inputs, partition invariance |
| Q14 | HRTF, HOA, and spatial matrices | 7 | 14,901 | 5/4/5/4 | High | Measured datasets, conditioning, realtime publication | Dataset corruption, numerical parity, TSan, partition invariance |
| Q15 | DSP primitives, convolution, filters, effects, resampling, and numerics | 62 | 33,533 | 5/4/5/4 | High | Numerical stability, bounds, realtime execution and publication | Independent vectors, property tests, finite containment, TSan, benchmarks |
| Q16 | Toolkit-neutral GUI state and models | 16 | 9,006 | 4/4/4/4 | Elevated | Callback lifetime, user input, resource transfer | State models, malformed input, lifecycle and concurrency stress |
| Q17 | LV2 and Audio Unit adapters | 6 | 22,415 | 5/5/5/4 | High | C ABI, host pointers, realtime entry, state and worker callbacks | ABI fixtures, dynamic hosts, sanitizers, metadata lint, failure silence |
| Q18 | Standalone runtime and native audio, MIDI, and window backends | 60 | 37,463 | 5/5/5/3 | High | OS callbacks, devices, threads, handles, recovery | TSan, callback drain, fault injection, cross-target and physical checks |
| Q19 | VSTGUI C++ adapter and native platform code | 67 | 32,691 | 5/4/5/4 | High | C++ ownership, native UI callbacks, C ABI bridge | ASan/UBSan/TSan, soak, visual fixtures, attach-detach stress |
| Q20 | Product and API examples | 54 | 14,920 | 3/4/4/4 | Moderate | Consumer patterns, retained callbacks, package surface | Installed builds, validators, public-example policy checks |
| Q21 | Test hosts, reference adapters, and downstream fixtures | 101 | 29,765 | 3/3/4/4 | Moderate | Oracle correctness and false confidence | Mutation review, independent provenance, fixture self-tests |
| Q22 | ABI, fixture, codec, and parity tools | 56 | 10,955 | 3/3/4/4 | Moderate | Generated evidence and oracle correctness | Reproducibility, independent comparison, negative controls |

## Lexical Concentrations

The checker reports lines containing indicators for allocation, raw pointers,
atomics, callbacks, parsing, and public declarations. These counts prioritize
manual review. They include false positives and cannot establish absence.

| Unit | Allocation | Pointer | Atomic | Callback | Parser | Public |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Q00 | 1 | 9 | 3 | 82 | 397 | 1 |
| Q01 | 128 | 2,162 | 93 | 1,126 | 92 | 2,429 |
| Q02 | 7 | 437 | 38 | 190 | 174 | 316 |
| Q03 | 39 | 272 | 8 | 194 | 32 | 280 |
| Q04 | 72 | 370 | 4 | 128 | 138 | 507 |
| Q05 | 0 | 2 | 0 | 0 | 0 | 114 |
| Q06 | 23 | 15 | 0 | 14 | 167 | 1,313 |
| Q07 | 107 | 7 | 40 | 13 | 327 | 1,474 |
| Q08 | 1 | 0 | 0 | 0 | 3 | 1,218 |
| Q09 | 53 | 0 | 0 | 0 | 673 | 846 |
| Q10 | 0 | 6 | 0 | 0 | 524 | 362 |
| Q11 | 0 | 8 | 0 | 0 | 667 | 416 |
| Q12 | 0 | 26 | 0 | 0 | 668 | 370 |
| Q13 | 90 | 0 | 0 | 0 | 396 | 328 |
| Q14 | 132 | 13 | 18 | 14 | 71 | 223 |
| Q15 | 2 | 12 | 32 | 0 | 65 | 1,885 |
| Q16 | 2 | 67 | 22 | 17 | 191 | 409 |
| Q17 | 74 | 439 | 4 | 234 | 139 | 896 |
| Q18 | 270 | 539 | 300 | 889 | 65 | 615 |
| Q19 | 185 | 0 | 67 | 749 | 68 | 0 |
| Q20 | 116 | 252 | 17 | 41 | 255 | 836 |
| Q21 | 63 | 211 | 11 | 136 | 452 | 268 |
| Q22 | 94 | 37 | 3 | 27 | 224 | 61 |

## Boundaries

The executable classifier is authoritative for file membership. The grouping
below describes the intended dependency and review boundaries.

- Q01 owns raw VST3 declarations and helpers. Q04 is the framework adapter over
  that boundary. Q06 must not acquire raw host behavior that belongs in Q04.
- Q06 owns format-neutral lifecycle and processing. Q14 and Q15 translate host
  or device contracts into Q06 without moving platform policy into the core.
- Q07 owns persistence and background resource publication. Q13 may initiate
  work but must not become the owner of processor resources.
- Q08 owns format-neutral process values. Q09 owns MIDI protocol state layered
  over those values.
- Q10–Q12 accept files and byte streams. Q13 and Q14 accept spatial metadata and
  measured datasets. Q15 supplies numerical primitives without file or host
  ownership.
- Q03 and Q19 form the Zig and C++ halves of the VSTGUI boundary. Native object
  ownership must have one side with an explicit destruction obligation.

## Dependency Direction

| Unit | Intended project dependencies |
| --- | --- |
| Q00 | May build and verify every unit; no runtime code depends on Q00 |
| Q01 | Standard library and pinned VST3 declarations |
| Q02 | Q01 for ARA/VST3 integration; official ARA headers as specification input |
| Q03 | Q01 and the external VSTGUI contract |
| Q04 | Q01–Q03, Q06–Q08, Q16 |
| Q05 | Q01 |
| Q06 | Q07 and Q08; format-neutral core must not depend on Q17–Q19 |
| Q07 | Standard library; resource publication may use Q15 primitives |
| Q08 | Q07 parameter and event value contracts |
| Q09 | Q08 process event values |
| Q10 | Q12 file I/O and Q15 FFT or numerical primitives |
| Q11 | Q12 file I/O and embedded MP3 tables |
| Q12 | Q15 numerical primitives where required by a format |
| Q13 | Q15 numerical and matrix primitives |
| Q14 | Q12 dataset I/O and Q15 numerical primitives |
| Q15 | Q08 transport values and the standard library; no file-format, GUI, or host adapter dependencies |
| Q16 | Q06, Q07, and Q15 model or telemetry values |
| Q17 | Q01 and Q06–Q09; optional Q16 and Q19 UI integration |
| Q18 | Q06–Q09 plus operating-system APIs loaded or linked by each backend |
| Q19 | Q03, Q16, and external VSTGUI platform APIs |
| Q20 | Public modules from Q01–Q19 as consumer examples require |
| Q21 | Units under test and independent test-only libraries |
| Q22 | Units inspected or exercised by each tool and independent reference libraries |

Phase 4 must verify these directions from resolved imports. The Phase 0 check
establishes intended boundaries and ensures that every source change has an
assigned reviewer and later-phase gate.

## Source Origin

| Material | Origin | Regeneration or verification status |
| --- | --- | --- |
| `vendor/ARA_API/*` | Bundled official ARA 2.3 headers and notices, 4,311 lines including non-source text | Pinned input to Zig translation and ABI checks; no local regeneration |
| `zig-vst3/src/pluginterfaces/**` | Repository-maintained Zig mirrors of pinned VST3 SDK declarations | Checked against SDK C++ layouts by the raw ABI matrix |
| `zig-vst3-plugin/src/dsp/mp3_huffman_tables.zig` | [ISO/IEC 11172-3:1993](https://www.iso.org/standard/22412.html), Annex B, Table 3-B.7 | Reconstruction enumerates tables by number and cells by `x * side + y`, retaining each published codeword length and unsigned bits. The semantic serialization has SHA-256 `9fdeb0ca3c74ac54a8ee9154544e8dced73aef97837de1311572e75866de76ec`, enforced by the MP3 tests. |
| `zig-vst3-plugin/src/dsp/mp3_synthesis_window.zig` | [ISO/IEC 11172-3:1993](https://www.iso.org/standard/22412.html), Annex B, Table 3-B.3 | Reconstruction reads the 512 `D[i]` values in index order, multiplies each published coefficient by 65,536, and rounds to the nearest integer. The big-endian `i32` serialization has SHA-256 `e8d6792457f2a517d0e36a87d29f83610aa00d6cca6281f0b31802faa4b2ccf3`, enforced by the MP3 tests. |
| `gui-adapters/vstgui/testdata/*` | Checked-in visual reference images, 51 files | Visual tests compare renderer output with these references; acceptance provenance requires Q16 review |
| MP3 conformance fixtures | CC0 minimp3 vectors at commit `ea99364f61c14656440e8d77e9c233ccf3124633` | The checked-in README records upstream paths and decoded SHA-256 values |
| Downloaded codec references | Xiph libogg 1.3.5, libvorbis 1.3.7, Tremor commit `820fb323`, stb_vorbis commit `2c980bb5`, and Helix MP3 commit `7f7dfc76` | Preparation scripts pin archive hashes; fixture runners exercise download, identity, hash-failure, and interruption handling |
| Downloaded spatial references | libspatialaudio 0.4.1, libmysofa commit `6cc5b15a`, Viking HRTF v2, and HUTUBS participant 1 | Preparation scripts pin versions or commits and SHA-256 values; fixture runners exercise source preparation |
| AndroidX VBRI fixture | AndroidX Media test asset at commit `3eb36d67`, Apache 2.0 | Fetch script pins the source URL and SHA-256 value |
| `tools/pack_ara_bindings.zig` | Repository tool that packages translated ARA declarations | Exercised by ARA ABI, installed-package, and published-release gates |
| LV2 metadata outputs | Generated at build or bundle time from plugin declarations | Generator tools and bundle lint provide reproducibility checks |

The two MP3 tables are tracked as finding Q-CODEC-001 until their provenance and
verification are sufficient to detect accidental edits.

## Cross-Cutting Exposure

| Exposure | Review units |
| --- | --- |
| Public compatibility | Q01, Q06–Q09, Q15, Q20 |
| Raw pointers or FFI | Q01–Q04, Q17–Q19, Q21, Q22 |
| Allocator ownership | Q02–Q04, Q06–Q19 |
| Host or OS callbacks | Q01–Q04, Q06, Q16–Q19 |
| Realtime execution | Q04, Q06–Q09, Q13–Q19 |
| Cross-thread publication | Q02–Q04, Q06, Q07, Q14, Q16–Q19 |
| Untrusted byte input | Q02, Q07, Q09–Q14, Q17, Q18 |
| Persistent state | Q02, Q06, Q07, Q09, Q16–Q18 |

This matrix identifies where later phases must look. It does not assert that
every file in a listed unit has every exposure.

## Ownership and Entry Points

| Unit | Owned resources and allocation | Callback, thread, and realtime boundary | Input or persisted state |
| --- | --- | --- | --- |
| Q00 | Build artifacts, temporary directories, downloaded tool sources, and child processes | CI and developer shell execution | Package manifests, environment, command output, archives |
| Q01 | Page-allocated COM objects, reference-counted interfaces, strings, and stream adapters | Host COM callbacks, factory entry points, and audio process data | SDK records, streams, presets, host-owned buffers |
| Q02 | Controller pool slots, host readers, cache pages, analysis records, and archive buffers | ARA host callbacks, non-realtime readers, atomic cache publication, realtime render reads | Host model graph, audio samples, content readers, controller archives |
| Q03 | Ref-counted views, run-loop registrations, native-object borrows, and telemetry sources | VSTGUI, Wayland, timer, descriptor, and view callbacks | Host interfaces, native handles, GUI messages |
| Q04 | Page-allocated controller and processor objects, plugin runtime allocations, retained handlers, peers, and telemetry sources | VST3 lifecycle, state, UI, and realtime process callbacks | Host process data, parameter queues, events, streams, component and editor state |
| Q05 | No long-lived resource beyond the factory products supplied by Q01 | Example factory and process entry points | Example parameters and host process data |
| Q06 | Plugin instance allocation, reflected parameter storage, topology snapshots, host-request state, and lifecycle resources | Format-neutral lifecycle and realtime processing | Plugin declarations, process contexts, parameter and component state |
| Q07 | State buffers, resource jobs, paths, reference generations, and publication exchanges | Worker completion and cross-thread resource publication | Versioned state, migrations, paths, resource payloads |
| Q08 | Caller-owned bounded views over audio, events, changes, transport, and output writers | Realtime process entry; no owned host buffers | Host-controlled counts, offsets, pointers, and transport values |
| Q09 | Fixed-capacity queues and sessions plus bounded property and file storage | Device producers, audio-thread consumers, and session state machines | MIDI byte streams, MIDI files, UMP packets, MIDI-CI JSON and properties |
| Q10 | Caller-owned indexes, packet and PCM buffers, and explicit file reader or writer state | No host callback; streaming decode or encode may run in product workers | Ogg pages, Vorbis packets, seek indexes, encoded and decoded files |
| Q11 | Caller-owned frame, reservoir, Huffman, synthesis, and PCM storage | No host callback; streaming decode or encode may run in product workers | MP3 frames, tags, seek metadata, encoded and decoded files |
| Q12 | File handles or adapters and caller-owned audio or metadata buffers | File reader and writer operations outside realtime processing | FLAC, AIFF, WAV, RF64, Wave64, ID3, iXML, and metadata chunks |
| Q13 | Parsed ADM records, render plans, matrices, delay state, and caller-bounded timelines | Render operations may be realtime after non-realtime construction | ADM XML and metadata, layouts, timed object and matrix records |
| Q14 | HRTF databases, SOFA loader storage, convolution histories, and immutable published generations | Non-realtime load and atomic publication to realtime render readers | SOFA datasets, layouts, motion schedules, HOA matrices |
| Q15 | Predominantly caller-owned fixed storage; the shared partitioned convolver owns bounded queues and publishes immutable processor state | Realtime DSP calls and control-to-audio publication | Coefficients, impulse responses, sample buffers, configuration, numerical vectors |
| Q16 | Editor models, imported-resource snapshots, telemetry generations, and bounded GUI state | UI callbacks and control-to-UI or audio-to-UI publication | User gestures, text, files, presets, graphs, viewport state |
| Q17 | Host component instances, retained features, worker payloads, state buffers, and Audio Unit cache storage | LV2 and Audio Unit lifecycle, worker, property, UI, and realtime render callbacks | Atom sequences, properties, options, streams, class-info state |
| Q18 | Device and window handles, callback contexts, queues, catalogs, recovery state, and platform allocations | Native audio, MIDI, window, monitor, and recovery callbacks across control and realtime threads | Device descriptors, packets, timestamps, selections, OS events |
| Q19 | C++ views, controllers, platform objects, accessibility nodes, drawing resources, and bridge allocations | Native UI, accessibility, timer, file selector, and C bridge callbacks | Host parent handles, user input, files, themes, visual state |
| Q20 | Product-specific workers, engines, importers, caches, and editor resources | Example host entry points, workers, editors, and realtime processing | Example component state, files, parameters, MIDI, telemetry |
| Q21 | Test-owned hosts, fixtures, temporary storage, and independent decoder or renderer adapters | Synthetic callbacks and stress threads | Malformed fixtures, reference vectors, downstream packages |
| Q22 | Tool-owned allocators, processes, generated fixtures, and comparison buffers | Command-line entry points only | SDK layouts, codec streams, datasets, generated metadata |
