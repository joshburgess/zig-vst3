# Host Matrix

Tier 3 host smoke tests are release gates. Record only tests that were run in a real host with the built plugin artifact.

| Date | Host | Host Version | OS | CPU | Plugin Build | Bundle | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_gain.vst3` | Pass | Scanned in REAPER, inserted on a track, Gain parameter behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_bypass.vst3` | Pass | Scanned in REAPER, inserted on a track, Bypass behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_mode_gain.vst3` | Pass | Scanned in REAPER, inserted on a track, Mode parameter behavior confirmed, saved, reloaded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_voice_mix.vst3` | Pass | Scanned in REAPER, inserted on a track, Voices parameter behavior confirmed, saved, reloaded. |
| Deferred | REAPER | Pending | Pending | Pending | Pending | `zig_vst3_note_gate.vst3` | Deferred | Needs an audio-plus-MIDI routing smoke test in a real host. Deferred because MIDI routing was not available during the first REAPER pass. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 3409b83 | `zig_vst3_event_echo.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, audio pass-through confirmed, saved, reloaded; event output not directly observed. |

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
6. Save and reload the session, then confirm parameter state and scan status are preserved.

## REAPER Notes

- `zig_vst3_gain.vst3`: insert on an audio track, play steady audio, then move Gain and listen for continuous level changes.
- `zig_vst3_note_gate.vst3`: create an audio track with the plugin, route audio into it, route MIDI notes into the same track, then confirm audio passes only while notes are held.
- `zig_vst3_event_echo.vst3`: this passes audio through and echoes VST3 events to the output event bus. It is not an audio delay effect.

## Recording Helper

After a real host run, generate a matrix row with:

```sh
sh scripts/host_smoke_row.sh "REAPER" "7.32" "zig_vst3_gain.vst3" "Pass" "Scanned, loaded, automated, saved, reloaded."
```

Paste the printed row into the table above and replace the matching pending row.
