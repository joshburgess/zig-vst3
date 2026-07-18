# Production File Importer Plan

Build a production audio-file importer on the public `@import("zig-vst3").vstgui` API. Drag and drop and the operating-system file picker must enter the same bounded import path. Imported audio produces a waveform preview without moving file I/O, decoding, allocation, or locks onto the audio thread.

## Contract

- Accept one audio file per import. The first production format is PCM WAV. AIFF remains filtered out until a decoder and fixtures exist.
- Copy paths at the GUI boundary. Reject empty, oversized, malformed, and unsupported paths before starting work.
- Run file I/O and decoding on one instance-owned worker. The worker has a fixed maximum input size and publishes at most 256 preview points.
- Keep progress, cancellation, retry, and terminal status explicit. Do not infer them from colors or animation.
- Treat editor close as a view lifecycle event, not an import cancellation. Controller teardown requests cancellation and joins the worker before releasing instance state.
- Keep imported data out of the audio processor until a future playback or convolution consumer defines an explicit real-time handoff.

## Milestone 1: Bounded Import Model

- [x] Add a toolkit-neutral fixed-capacity import model.
- [x] Cover drop and picker entry points through one state machine.
- [x] Cover copied paths, extension filtering, count and path limits, progress, cancellation acknowledgement, empty results, failure, retry, reset, and generation changes.
- [x] Export the model from `zig-vst3-plugin-core`.
- [x] Run Zig tests and raw ABI checks.
- [x] Commit the completed model.

Exit criteria:

- The model performs no allocation after construction.
- Caller-owned path storage can change after submission without affecting the job.
- Invalid transitions fail without corrupting the previous recoverable job.
- Cancellation is observable across threads through an atomic request flag.

Completion evidence:

- `gui_file_importer.Model(file_capacity, extension_capacity)` owns the filtered `gui_file_drop.DropZone`, copied paths, entry point, state, progress units, generation, and atomic cancellation request.
- Four focused tests cover caller-storage independence, case-insensitive extensions, drop and picker entry, count and path bounds, monotonic progress, cancellation acknowledgement, retry, failure, empty results, reset, and rejected transitions.
- The full local run completed 152 of 152 build steps and 3,572 of 3,572 tests. Raw ABI checks, native adapter tests, macOS accessibility tests, visual regression, and warm-render budgets passed.

## Milestone 2: Accessible Native Entry Points

- [ ] Extend the public `FileDrop` declaration with picker text and refresh behavior without exposing VSTGUI types.
- [ ] Make the native component keyboard focusable with a visible focus state.
- [ ] Open the operating-system file picker from pointer activation, Enter, Space, and the accessibility press action.
- [ ] Apply the same extension and count validation to picker and drop results.
- [ ] Restore focus to the importer after the picker closes.
- [ ] Cancel an open picker safely during editor teardown.

Exit criteria:

- Drop and picker dispatch the same public callback with copied paths.
- The accessibility node exposes a button-like import action, name, current status, and enabled state.
- The primary action says `Choose Audio File`. Drag and drop remains a secondary shortcut.
- Disabled importers reject pointer, keyboard, drop, picker, and accessibility activation.

## Milestone 3: Instance-Owned Import Worker

- [ ] Add optional controller instance state to the reflected controller without changing ordinary plugin composition.
- [ ] Implement a single bounded worker for PCM WAV validation and preview decoding.
- [ ] Enforce file-size, channel-count, sample-format, sample-count, and preview-point limits.
- [ ] Publish progress and waveform snapshots without exposing partially written data.
- [ ] Support cancellation, retry, editor reopen, and controller teardown.
- [ ] Keep every worker, path, status, and preview isolated per plugin instance.

Exit criteria:

- The worker owns all file I/O and decoding.
- Controller teardown cannot race a pending callback or worker write.
- The audio processor performs no file-import work and acquires no import locks.
- Malformed and truncated WAV files produce recoverable failures.

## Milestone 4: Production Importer UI

- [ ] Add the importer to the channel-strip editor using only `@import("zig-vst3").vstgui` declarations.
- [ ] Render idle, drag-hover, validating, importing, ready, empty, unsupported-file, capacity-limit, cancelled, and recoverable-error states.
- [ ] Render bounded progress and the imported waveform preview.
- [ ] Add Cancel and Retry actions only when they are available.
- [ ] Keep labels, status text, icons or shapes, focus, and contrast understandable without color.
- [ ] Make layout responsive at supported editor sizes and scales.

Exit criteria:

- The importer has one visually dominant action.
- Every state gives the user a next step or a clear terminal result.
- Keyboard order follows the visible reading order.
- Tooltips supplement visible labels and do not carry required instructions.

## Milestone 5: Coverage and API Decision

- [ ] Add unit tests for the model, WAV decoder, worker lifecycle, and instance isolation.
- [ ] Add native pointer, keyboard, picker, drop, cancellation, retry, accessibility, resize, scale, teardown, and callback-rejection tests.
- [ ] Add deterministic generated fixtures for valid, empty, oversized, malformed, truncated, and unsupported files.
- [ ] Add visual references for the importer state set and production editor.
- [ ] Add bounded warm-render and worker throughput measurements.
- [ ] Run Zig tests, raw ABI checks, native adapter tests, macOS accessibility tests, visual tests, Steinberg validators, and Linux and Windows cross-target bundle builds.
- [ ] Run serialized pluginval suites at strictness 5 and 10.
- [ ] Decide whether `FileDrop` is ready for promotion. Record any remaining experimental surface precisely.
- [ ] Commit the completed production integration and evidence.

Exit criteria:

- Both the gallery and channel strip consume the same public importer contract.
- Every locally executable validation gate passes.
- Pluginval stops at the first unexpected exit and preserves its artifacts.
- VoiceOver, Narrator, native Windows, X11, Wayland, and AT-SPI checks remain explicit external items when unavailable.

## External Checks

- [ ] Navigate the importer and picker with VoiceOver on macOS.
- [ ] Navigate the importer and picker with Narrator on Windows.
- [ ] Verify native picker, focus restoration, drop, and teardown in Windows, X11, and Wayland hosts.
- [ ] Verify AT-SPI names, roles, status changes, and actions on X11 and Wayland.
