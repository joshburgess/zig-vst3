# Source Cohesion Ledger

This ledger covers tracked handwritten implementation sources with at least
2,000 physical lines. It excludes dedicated test files, test fixtures, tools,
and vendored sources. The gate counts complete top-level Zig `test` declaration
spans as test lines. Every other line is a production line, including imports,
types, build declarations, and supporting prose.

`KEEP` means the file has one contract whose private invariants would become
harder to review if separated. `SPLIT` identifies a concrete narrower boundary
that must be extracted before Q-ARCH-001 closes. Size alone never requires a
split.

## Decisions

| Source | Production / test lines | Role and state contract | Decision |
| --- | ---: | --- | --- |
| `build.zig` | 7,530 / 0 | Owns the repository build graph. Its steps share resolved targets, package modules, feature options, and named aggregate gates. | KEEP. Splitting would require a broad mutable build context without creating an independently meaningful package contract. |
| `gui-adapters/vstgui/zig_vstgui_accessibility_bridge.cpp` | 2,840 / 0 | Owns the native accessibility peer bridge and the lifetime transfer between VSTGUI objects and platform accessibility objects. | KEEP. The translation unit already matches one foreign-lifetime boundary. |
| `gui-adapters/vstgui/zig_vstgui_editor.cpp` | 2,417 / 0 | Owns native editor creation, attachment, resize, and teardown behind the Zig VSTGUI ABI. | KEEP. Its state is one editor lifecycle and is separate from graph and accessibility implementations. |
| `gui-adapters/vstgui/zig_vstgui_graphs.cpp` | 2,053 / 0 | Owns graph widgets, retained plot data, and graph-specific draw and input callbacks. | KEEP. Graph state and invalidation form one adapter contract. |
| `zig-vst3-plugin/src/audio_unit_v2.zig` | 2,349 / 2,290 | Owns the component instance, processor state, host callbacks, and render lifecycle. Raw ABI vocabulary lives in `audio_unit_v2/abi.zig`. | KEEP. The remaining production state belongs to one component lifecycle; every prior public ABI name is an exact alias. |
| `zig-vst3-plugin/src/dsp/adm_render/object.zig` | 2,079 / 3,982 | Owns bounded object gain planning, divergence, exclusion, screen transforms, channel lock, and sample-accurate gain timelines. Shared geometry, panning, matrix rendering, and direct-speaker routing live in sibling modules behind the exact `dsp/adm_render.zig` facade. | KEEP. The remaining production state and helpers preserve one object-rendering contract; the file exceeds the threshold because its colocated behavioral tests are larger than its implementation. |
| `zig-vst3-plugin/src/dsp/adm_xml/core.zig` | 10,470 / 4,786 | Temporarily owns bounded ADM metadata traversal, model construction, emission-profile checks, and graph validation behind the exact `dsp/adm_xml.zig` facade. | SPLIT. Separate ADM-specific token and attribute traversal from the retained model and graph validator without exposing parser scratch state. |
| `zig-vst3-plugin/src/dsp/audio_file_reader.zig` | 1,577 / 1,247 | Selects bounded WAV, RF64, BW64, Wave64, AIFF, and AIFC readers and presents one positional PCM and metadata interface. | KEEP. The file is the format-dispatch boundary; format implementations already live in narrower modules. |
| `zig-vst3-plugin/src/dsp/flac.zig` | 4,747 / 2,547 | Owns FLAC metadata, frame encoding and decoding, positional I/O, and caller-provided work storage. | KEEP. Frame and metadata state share one bitstream contract, while large static tables already live outside the file. |
| `zig-vst3-plugin/src/dsp/hrtf.zig` | 2,698 / 2,772 | Owns HRTF database interpolation, room-path planning, renderer state, and convolver preparation. Spatial types and conversions live in `hrtf/spatial.zig`; tracker clocks and bounded motion transport live in `hrtf/motion.zig`. | KEEP. The remaining state belongs to one spatial renderer contract, and every moved public name is an exact alias. |
| `zig-vst3-plugin/src/dsp/hrtf_sofa.zig` | 1,335 / 906 | Converts a bounded SOFA/NetCDF dataset into caller-owned HRTF database storage with failure-atomic publication. | KEEP. External parsing and database conversion are one setup-time ownership boundary. |
| `zig-vst3-plugin/src/dsp/id3.zig` | 1,566 / 658 | Parses and encodes bounded ID3v2.3 and ID3v2.4 tags while retaining exact iterator source and cursor state. | KEEP. Both versions share frame encoding, text decoding, and retained-state validation. |
| `zig-vst3-plugin/src/dsp/ixml.zig` | 2,889 / 565 | Materializes bounded iXML metadata and exposes typed views over tracks, sync points, history, location, and BEXT fields. | KEEP. The typed model is the parser result and shares its storage and limit invariants. |
| `zig-vst3-plugin/src/dsp/kernel_dispatch.zig` | 1,527 / 787 | Detects CPU features and binds scalar or SIMD kernels into immutable dispatcher values. | KEEP. Backend selection and function tables form one dispatch contract. |
| `zig-vst3-plugin/src/dsp/matrix.zig` | 1,436 / 1,986 | Provides fixed-size vectors and matrices plus fixed-storage LU, QR, and SVD decompositions. | KEEP. Dimensions and workspace sizes are compile-time invariants shared by the fixed family. |
| `zig-vst3-plugin/src/dsp/matrix/dynamic.zig` | 2,076 / 0 | Owns runtime-shaped matrix allocation and reusable LU, QR, and SVD workspaces through the caller allocator. | KEEP. Public matrix convenience methods return the factorization types and each factorization accepts the matrix type, so their exact identities form one mutually dependent contract. |
| `zig-vst3-plugin/src/dsp/mp3.zig` | 16,584 / 12,720 | Owns MPEG Layer III headers, side information, bit reservoir, Huffman coding, encoding, decoding, seeking, and positional I/O. | SPLIT. Separate shared bitstream syntax from encoder and decoder state while preserving the current public module as a facade. |
| `zig-vst3-plugin/src/dsp/ogg.zig` | 20,969 / 10,120 | Owns Ogg pages, packets, streams, files, and the complete Vorbis header, encode, decode, seek, rate-control, and concealment stack. | SPLIT. Separate the Ogg container from the Vorbis codec and retain all current `dsp.ogg` names as exact aliases. |
| `zig-vst3-plugin/src/dsp/special_functions.zig` | 1,062 / 1,235 | Implements the elliptic, Jacobi, and Bessel functions used by DSP design code with shared domain and convergence handling. | KEEP. These functions share numerical primitives and one error policy; the file is test-heavy rather than production-heavy. |
| `zig-vst3-plugin/src/lv2.zig` | 5,523 / 4,608 | Owns plugin instance, feature negotiation, worker, state, programs, dynamic ports, and bounded host-owned path lifecycles. C layouts and callbacks live in `lv2/abi.zig`; URI constants live in `lv2/uris.zig`. | KEEP. The remaining values belong to one plugin instance, and all moved public names retain exact type and value identity. |
| `zig-vst3-plugin/src/lv2_metadata.zig` | 1,436 / 1,178 | Generates bounded Turtle metadata from one validated plugin and UI metadata model. | KEEP. Escaping, URI emission, port emission, and preset output share one transactional writer. |
| `zig-vst3-plugin/src/lv2_ui.zig` | 1,723 / 2,080 | Owns LV2 UI feature negotiation, host subscription and resize callbacks, backend lifecycle, and idle publication. | KEEP. The runtime state is one UI instance, and more than half the file is colocated lifecycle testing. |
| `zig-vst3-plugin/src/parameters/access.zig` | 1,704 / 1,024 | Derives typed parameter values, read-only views, and editors from one compile-time parameter schema. | KEEP. All three views depend on the same descriptor reflection and range conversion invariants. |
| `zig-vst3-plugin/src/plugin/instance.zig` | 2,659 / 0 | Generates one plugin runtime that owns preparation, processing, state, resources, and teardown according to the plugin specification. | KEEP. The generic type is the lifecycle boundary; its supporting state is already factored into sibling modules. |
| `zig-vst3-plugin/src/plugin/standalone.zig` | 1,953 / 3,063 | Owns callback adaptation, channel routing, MIDI and UMP scheduling, device lifecycle, and the standalone host shell. Capture FIFO, drift control, and disparate-clock transport live in `plugin/standalone/capture.zig`. | KEEP. The remaining production code coordinates one host lifecycle; every moved public name is an exact alias. |
| `zig-vst3-plugin/src/process/context.zig` | 2,058 / 1,610 | Defines one bounded process block view over transport, audio buses, parameters, events, data exchange, and host requests. | KEEP. These borrowed views share the lifetime of one host process call and expose no independent ownership. |
| `zig-vst3-plugin/src/process/events.zig` | 1,557 / 1,529 | Defines bounded event values, validation, ordering, iteration, and note tracking for a process block. | KEEP. Validation and iteration preserve the same event representation and block-lifetime contract. |
| `zig-vst3/src/ara_document_controller.zig` | 4,090 / 1,908 | Owns the bounded ARA document model, archive store and restore, audio-reader leases, host notifications, and model-update sequencing. | KEEP. These operations mutate one controller model and share its generation, capacity, and host-lifetime invariants. |
| `zig-vst3/src/ara_source_cache.zig` | 1,568 / 635 | Owns fixed or paged source audio populated on control threads and published as immutable generations to realtime readers. | KEEP. Fill, directory publication, lookup, and teardown form one cache ownership contract. |
| `zig-vst3/src/ara_tuning_analysis.zig` | 4,584 / 3,032 | Runs bounded tuning, tempo, meter, key, chord, and note analysis and serializes retained analysis results. | SPLIT. Extract each detector behind shared bounded observation and archive types. |
| `zig-vst3/src/zig_vst3_plugin_bridge.zig` | 2,439 / 2,836 | Converts VST3 process, parameter, event, bus, and state interfaces into the framework's bounded process model. | KEEP. The conversions share one host-call lifetime and negotiated bus and capacity state. |
| `zig-vst3/src/zig_vst3_plugin_effect.zig` | 3,322 / 2,773 | Builds reflected edit controllers and effect component pairs over shared parameter, host-request, state, and view lifecycles. | SPLIT. Separate controller construction from processor and component construction while retaining the public facade. |

## Checked Records

Each record stores `total | production | test | decision`. The repository gate
rejects missing or stale sources, changed metrics, duplicate paths, and unknown
decisions.

<!-- cohesion-files:start -->
- `build.zig` | 7530 | 7530 | 0 | KEEP
- `gui-adapters/vstgui/zig_vstgui_accessibility_bridge.cpp` | 2840 | 2840 | 0 | KEEP
- `gui-adapters/vstgui/zig_vstgui_editor.cpp` | 2417 | 2417 | 0 | KEEP
- `gui-adapters/vstgui/zig_vstgui_graphs.cpp` | 2053 | 2053 | 0 | KEEP
- `zig-vst3-plugin/src/audio_unit_v2.zig` | 4639 | 2349 | 2290 | KEEP
- `zig-vst3-plugin/src/dsp/adm_render/object.zig` | 6061 | 2079 | 3982 | KEEP
- `zig-vst3-plugin/src/dsp/adm_xml/core.zig` | 15256 | 10470 | 4786 | SPLIT
- `zig-vst3-plugin/src/dsp/audio_file_reader.zig` | 2824 | 1577 | 1247 | KEEP
- `zig-vst3-plugin/src/dsp/flac.zig` | 7294 | 4747 | 2547 | KEEP
- `zig-vst3-plugin/src/dsp/hrtf.zig` | 5470 | 2698 | 2772 | KEEP
- `zig-vst3-plugin/src/dsp/hrtf_sofa.zig` | 2241 | 1335 | 906 | KEEP
- `zig-vst3-plugin/src/dsp/id3.zig` | 2224 | 1566 | 658 | KEEP
- `zig-vst3-plugin/src/dsp/ixml.zig` | 3454 | 2889 | 565 | KEEP
- `zig-vst3-plugin/src/dsp/kernel_dispatch.zig` | 2314 | 1527 | 787 | KEEP
- `zig-vst3-plugin/src/dsp/matrix.zig` | 3422 | 1436 | 1986 | KEEP
- `zig-vst3-plugin/src/dsp/matrix/dynamic.zig` | 2076 | 2076 | 0 | KEEP
- `zig-vst3-plugin/src/dsp/mp3.zig` | 29304 | 16584 | 12720 | SPLIT
- `zig-vst3-plugin/src/dsp/ogg.zig` | 31089 | 20969 | 10120 | SPLIT
- `zig-vst3-plugin/src/dsp/special_functions.zig` | 2297 | 1062 | 1235 | KEEP
- `zig-vst3-plugin/src/lv2.zig` | 10131 | 5523 | 4608 | KEEP
- `zig-vst3-plugin/src/lv2_metadata.zig` | 2614 | 1436 | 1178 | KEEP
- `zig-vst3-plugin/src/lv2_ui.zig` | 3803 | 1723 | 2080 | KEEP
- `zig-vst3-plugin/src/parameters/access.zig` | 2728 | 1704 | 1024 | KEEP
- `zig-vst3-plugin/src/plugin/instance.zig` | 2659 | 2659 | 0 | KEEP
- `zig-vst3-plugin/src/plugin/standalone.zig` | 5016 | 1953 | 3063 | KEEP
- `zig-vst3-plugin/src/process/context.zig` | 3668 | 2058 | 1610 | KEEP
- `zig-vst3-plugin/src/process/events.zig` | 3086 | 1557 | 1529 | KEEP
- `zig-vst3/src/ara_document_controller.zig` | 5998 | 4090 | 1908 | KEEP
- `zig-vst3/src/ara_source_cache.zig` | 2203 | 1568 | 635 | KEEP
- `zig-vst3/src/ara_tuning_analysis.zig` | 7616 | 4584 | 3032 | SPLIT
- `zig-vst3/src/zig_vst3_plugin_bridge.zig` | 5275 | 2439 | 2836 | KEEP
- `zig-vst3/src/zig_vst3_plugin_effect.zig` | 6095 | 3322 | 2773 | SPLIT
<!-- cohesion-files:end -->
