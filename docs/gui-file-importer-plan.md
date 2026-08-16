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

- [x] Extend the public `FileDrop` declaration with picker text without exposing VSTGUI types.
- [x] Make the native component keyboard focusable with a visible focus state.
- [x] Open the operating-system file picker from pointer activation, Enter, Space, and the accessibility press action.
- [x] Apply the same extension and count validation to picker and drop results.
- [x] Restore focus to the importer after the picker closes.
- [x] Cancel an open picker safely during editor teardown.
- [x] Commit the accessible picker fallback.

Exit criteria:

- Drop and picker dispatch the same public callback with copied paths.
- The accessibility node exposes a button-like import action, name, current status, and enabled state.
- The primary action says `Choose Audio File`. Drag and drop remains a secondary shortcut.
- Disabled importers reject pointer, keyboard, drop, picker, and accessibility activation.

Completion evidence:

- The public `FileDrop` declaration supplies picker labels and titles while the native adapter owns the VSTGUI file-selector implementation.
- Pointer activation, Enter, Space, and the accessibility press action use one picker action. Picker and drop paths share the same inspection, count limit, extension filter, copied-path callback, and rejection behavior.
- A per-invocation lifetime token cancels an open selector and rejects late callbacks after editor teardown. Successful selection restores keyboard focus to the importer.
- Native adapter tests cover pointer, keyboard, accessibility, shared callback delivery, and disabled-state rejection without opening an operating-system dialog during automation.
- The updated deterministic visual reference shows `Choose Audio File` as the primary action and drag and drop as the secondary shortcut. Warm rendering measured 35.1 microseconds for the file-drop scene against a 300 microsecond budget.
- The full local run completed 193 of 193 build steps and 3,572 of 3,572 tests. Raw ABI checks, all ten Steinberg validators, native adapter tests, macOS accessibility tests, visual regression, warm-render budgets, the Windows accessibility bridge cross-compile, and Linux and Windows bundles passed.
- Actual system picker behavior in REAPER and native Windows, X11, and Wayland hosts remains a manual external check.

## Milestone 3: Instance-Owned Import Worker

- [x] Add optional controller instance state to the reflected controller without changing ordinary plugin composition.
- [x] Implement a single bounded worker for PCM WAV validation and preview decoding.
- [x] Enforce file-size, channel-count, sample-format, sample-count, and preview-point limits.
- [x] Publish progress and waveform snapshots without exposing partially written data.
- [x] Support cancellation, retry, and controller teardown.
- [x] Verify that an active or completed import survives editor close and reopen.
- [x] Keep every worker, path, status, and preview isolated per plugin instance.
- [x] Commit the bounded worker foundation.

Exit criteria:

- The worker owns all file I/O and decoding.
- Controller teardown cannot race a pending callback or worker write.
- The audio processor performs no file-import work and acquires no import locks.
- Malformed and truncated WAV files produce recoverable failures.

Worker foundation evidence:

- `ReflectedEditController` now offers opt-in `ControllerState` initialization, access, per-instance storage, and teardown. Controllers without state retain the existing empty contract.
- `gui_audio_file_importer.Importer` owns one worker, one copied path, a 32 MiB input ceiling, an 8,388,608-frame ceiling, one or two channels, 16-bit, 24-bit, or 32-bit integer PCM, and at most 256 published waveform points.
- File I/O and decoding run only on the worker. The GUI-facing snapshot and preview copy are bounded. The audio processor has no importer reference, import lock, allocation, or file operation.
- Tests generate valid, malformed, truncated, unsupported-format, and multi-megabyte cancellation fixtures in temporary directories. They cover preview publication, retry, instance isolation, cancellation acknowledgement, teardown joining, and controller-state lifecycle.
- The complete local gate passed 193 of 193 build steps and 3,586 of 3,586 tests. Raw ABI checks, all ten Steinberg validators, native adapter tests, macOS accessibility tests, visual regression, warm-render budgets, the Windows accessibility bridge cross-compile, and all ten Linux and Windows cross-target bundles passed.
- The first full bundle attempt exhausted disk space and damaged one local Zig cache manifest. Removing only reproducible temporary and repository-local Zig caches restored a clean passing run.
- A channel-strip integration test starts an import, closes the first editor view, opens a second view on the same controller, and observes the completed 256-point preview. Controller teardown still cancels and joins pending work.

## Milestone 4: Production Importer UI

- [x] Add the importer to the channel-strip editor using only `@import("zig-vst3").vstgui` declarations.
- [x] Render idle, drag-hover, validating, importing, ready, empty, unsupported-file, capacity-limit, cancelled, and recoverable-error states.
- [x] Render bounded progress and the imported waveform preview.
- [x] Add Cancel and Retry actions only when they are available.
- [x] Keep labels, status text, icons or shapes, focus, and contrast understandable without color.
- [x] Make layout responsive at supported editor sizes and scales.

Exit criteria:

- The importer has one visually dominant action.
- Every state gives the user a next step or a clear terminal result.
- Keyboard order follows the visible reading order.
- Tooltips supplement visible labels and do not carry required instructions.

Completion evidence:

- The channel strip declares one WAV importer and one controller-sourced waveform through the public `vst3.vstgui` authoring surface. Ordinary composition does not import or edit adapter internals.
- Drop and picker callbacks preserve their entry point but enter the same validation and worker path. The native view polls only while work is active and stops its timer at every terminal state.
- The primary action is `Choose Audio File` while idle. It becomes Cancel during validation or import and Retry after cancellation or recoverable failure. Enter, Space, pointer activation, and the accessibility press action use the same current command.
- Ready state reports file metadata and renders the fixed 256-point imported waveform. Empty and all rejection states present explicit text and a next action without relying on color.
- Import state belongs to the controller, so closing and reopening an editor preserves active and completed work. Host state restoration intentionally starts a new controller in idle state instead of reopening a stale path or performing hidden file I/O.
- The importer participates in responsive channel-strip layout, host resizing, deterministic focus order, visible focus, and per-instance teardown.

## Milestone 5: Coverage and API Decision

- [x] Add unit tests for the model, WAV decoder, worker lifecycle, and instance isolation.
- [x] Add native pointer, keyboard, picker, drop, cancellation, retry, accessibility, resize, scale, teardown, and callback-rejection tests.
- [x] Add deterministic generated fixtures for valid, empty, oversized, malformed, truncated, and unsupported files.
- [x] Add visual references for the importer state set and production editor.
- [x] Add bounded warm-render and worker throughput measurements.
- [x] Run Zig tests, raw ABI checks, native adapter tests, macOS accessibility tests, visual tests, Steinberg validators, and Linux and Windows cross-target bundle builds.
- [x] Run serialized pluginval suites at strictness 5 and 10.
- [x] Decide whether `FileDrop` is ready for promotion. Record any remaining experimental surface precisely.
- [x] Commit the completed production integration and evidence.

Exit criteria:

- Both the gallery and channel strip consume the same public importer contract.
- Every locally executable validation gate passes.
- Pluginval stops at the first unexpected exit and preserves its artifacts.
- VoiceOver, Narrator, native Windows, X11, Wayland, and AT-SPI checks remain explicit external items when unavailable.

API decision:

- Promote `FileDrop`. The component gallery and channel strip use the same public declaration, bounded callback, picker fallback, keyboard behavior, accessibility semantics, focus restoration, and teardown contract.
- Keep `AudioFileImporter`, controller-owned import status and command hooks, and controller-sourced graph snapshots experimental. They currently have one authoring consumer and may need composition changes when a second production importer appears.

Current measurements:

- The production importing state rendered in 48.6 microseconds per warm frame during the final strictness 10 gate, against the 300 microsecond budget.
- The bounded worker decoded and reduced an 8 MiB generated PCM WAV fixture at 1,608.4 MiB/s during the final benchmark run.

Final validation evidence:

- `zig build validate-examples test raw-api-abi --summary all` completed 193 of 193 build steps and 3,587 of 3,587 tests. Raw ABI checks, native adapter tests, macOS accessibility bridge tests, visual regressions, warm-render budgets, and all ten Steinberg validators passed.
- `zig build benchmark --summary all` completed four of four steps. The imported waveform worker remained bounded and exceeded the recorded throughput baseline.
- Linux and Windows cross-target matrices each completed 32 of 32 build steps and produced all ten example bundles.
- Serialized pluginval strictness 5 and strictness 10 matrices each completed 44 of 44 build steps. All ten plugins passed. The channel strip passed editor creation, editor-while-processing, automation, state restoration, background-thread state, parameter thread safety, and parameter fuzzing.
- The automated macOS accessibility bridge passed. Manual VoiceOver use, the native macOS picker in a host, Narrator, native Windows, X11, Wayland, and AT-SPI remain external checks.

## External Checks

- [ ] Navigate the importer and picker with VoiceOver on macOS.
- [ ] Navigate the importer and picker with Narrator on Windows.
- [ ] Verify native picker, focus restoration, drop, and teardown in Windows, X11, and Wayland hosts.
- [ ] Verify AT-SPI names, roles, status changes, and actions on X11 and Wayland.
