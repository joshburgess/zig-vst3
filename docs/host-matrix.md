# Host Matrix

Tier 3 host smoke tests are release gates. Record only tests that were run in a real host with the built plugin artifact.

| Date | Host | Host Version | OS | CPU | Plugin Build | Bundle | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-07-17 | REAPER | 7.36/macOS-arm64 | macOS 15.4.1 | arm64 | 041ec5f | `zig_vst3_gain.vst3` | Partial Pass | Visible slider feedback, pointer dragging, arrow keys, Fn+Left/Right limits, exact text entry, Command-click reset, focus movement, host and editor resize, two isolated instances, pointer and keyboard automation recording/playback, save/reload, and editor recreation while stopped and running passed. Display-scale migration remains untested because a second display was unavailable. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_gain.vst3` | Pass | Scanned in REAPER, inserted on a track, Gain parameter behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_bypass.vst3` | Pass | Scanned in REAPER, inserted on a track, Bypass behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_mode_gain.vst3` | Pass | Scanned in REAPER, inserted on a track, Mode parameter behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_voice_mix.vst3` | Pass | Scanned in REAPER, inserted on a track, Voices parameter behavior confirmed, saved, reloaded. |
| Deferred | REAPER | Pending | Pending | Pending | Pending | `zig_vst3_note_gate.vst3` | Deferred | Needs an audio-plus-MIDI routing smoke test in a real host. Deferred because MIDI routing was not available during the first REAPER pass. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_event_echo.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, audio pass-through confirmed, saved, reloaded; event output not directly observed. |
| Deferred | REAPER | Pending | Pending | Pending | Pending | `zig_vst3_event_monitor.vst3` | Deferred | Needs an analyzer-style event inspection smoke test in a real host. |
| Deferred | REAPER | Pending | Pending | Pending | Pending | `zig_vst3_sine_synth.vst3` | Deferred | Needs an instrument-style MIDI input smoke test in a real host. |
| Deferred | REAPER | Pending | Pending | Pending | Pending | `zig_vst3_editor_smoke.vst3` | Deferred | Needs a real embedded editor smoke test. The view is protocol-only and has no visible toolkit UI. |

## Minimum Smoke Test

Run `zig build clean-bundles bundle-examples` before pointing a host at `zig-out/bundle/` so stale bundles from older builds do not show up in the plugin browser.

1. Build the bundle with `zig build bundle-<short-name>`.
2. Load the matching bundle from `zig-out/bundle/` in the host.
3. Confirm the plugin scans successfully.
4. Insert it on a stereo audio track.
5. Exercise the plugin-specific behavior:
   - `zig_vst3_gain.vst3`: move Gain and confirm audible level changes.
   - `zig_vst3_bypass.vst3`: toggle Bypass and confirm pass-through behavior.
   - `zig_vst3_mode_gain.vst3`: switch Mode and confirm the gain mode changes.
   - `zig_vst3_voice_mix.vst3`: change Voices and confirm stepped parameter automation.
   - `zig_vst3_note_gate.vst3`: send note input and confirm the gate opens and closes.
   - `zig_vst3_event_echo.vst3`: route event output and confirm input events are echoed. This is not an audio delay effect.
   - `zig_vst3_event_monitor.vst3`: route MIDI or other event input into the analyzer and confirm it scans and survives save/reload. Direct event-summary observation still needs a host harness.
   - `zig_vst3_sine_synth.vst3`: insert as a MIDI-driven instrument or output-only generator, send note input, move Level, and confirm generated audio follows note and level changes.
   - `zig_vst3_editor_smoke.vst3`: open and close the editor, resize the plugin window if the host allows it, save, and reload.
6. Save and reload the session, then confirm parameter state and scan status are preserved.

## REAPER Notes

- `zig_vst3_gain.vst3`: insert on an audio track, play steady audio, then move Gain and listen for continuous level changes.
- `zig_vst3_note_gate.vst3`: create an audio track with the plugin, route audio into it, route MIDI notes into the same track, then confirm audio passes only while notes are held.
- `zig_vst3_event_echo.vst3`: this passes audio through and echoes VST3 events to the output event bus. It is not an audio delay effect.
- `zig_vst3_event_monitor.vst3`: this is an input-only event analyzer. It has no audio output, so a basic REAPER pass should focus on scan/load/save/reload until a host-side event inspection harness exists.
- `zig_vst3_sine_synth.vst3`: create a track with MIDI input armed, insert the plugin, send notes, and confirm the Level parameter controls generated output.
- `zig_vst3_editor_smoke.vst3`: open the FX UI and close it while transport is stopped and running. It intentionally exposes a protocol-only editor, so a blank or host-generic container is acceptable as long as the host does not crash and save/reload survives.

## Visible GUI Platform Coverage

| Platform | Status | Remaining real-host work |
| --- | --- | --- |
| macOS | Partial Pass | Change display scale or move the editor between displays in REAPER or Cubase. |
| Windows | Pending | Run the gain bundle in a native Windows VST3 host, including DPI changes and two instances. |
| Linux X11 | Pending | Run the gain bundle in a native X11 VST3 host and verify host run-loop cleanup. |
| Linux Wayland | Pending | Run the gain bundle in a native Wayland VST3 host that implements the required Wayland interfaces. |

## Recording Helper

After a real host run, generate a matrix row with:

```sh
sh scripts/host_smoke_row.sh "REAPER" "7.32" "zig_vst3_gain.vst3" "Pass" "Scanned, loaded, automated, saved, reloaded."
```

Paste the printed row into the table above and replace the matching pending row.
