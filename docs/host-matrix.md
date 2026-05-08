# Host Matrix

Tier 3 host smoke tests are release gates. Record only tests that were run in a real host with the built plugin artifact.

| Date | Host | Host Version | OS | CPU | Plugin Build | Bundle | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_gain.vst3` | Pending | No real-host smoke test has been recorded yet. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | b8bd61a | `zig_vst3_bypass.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, Bypass behavior confirmed; save/reload not recorded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | b8bd61a | `zig_vst3_mode_gain.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, Mode parameter changes behavior; save/reload not recorded. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 0dadeb0 | `zig_vst3_voice_mix.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, Voices parameter behavior confirmed; save/reload not recorded. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_note_gate.vst3` | Pending | No real-host smoke test has been recorded yet. |
| 2026-05-08 | REAPER | 7.72.0_0c2021fu | macOS 15.4 | arm64 | 907a279 | `zig_vst3_event_echo.vst3` | Partial Pass | Scanned in REAPER, inserted on a track, audio pass-through confirmed; event output and save/reload not recorded. |

## Minimum Smoke Test

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

## Recording Helper

After a real host run, generate a matrix row with:

```sh
sh scripts/host_smoke_row.sh "REAPER" "7.32" "zig_vst3_gain.vst3" "Pass" "Scanned, loaded, automated, saved, reloaded."
```

Paste the printed row into the table above and replace the matching pending row.
