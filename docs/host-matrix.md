# Host Matrix

Tier 3 host smoke tests are release gates. Record only tests that were run in a real host with the built plugin artifact.

| Date | Host | Host Version | OS | CPU | Plugin Build | Bundle | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_gain.vst3` | Pending | No real-host smoke test has been recorded yet. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_bypass.vst3` | Pending | No real-host smoke test has been recorded yet. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_mode_gain.vst3` | Pending | No real-host smoke test has been recorded yet. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_voice_mix.vst3` | Pending | No real-host smoke test has been recorded yet. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_note_gate.vst3` | Pending | No real-host smoke test has been recorded yet. |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_event_echo.vst3` | Pending | No real-host smoke test has been recorded yet. |

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
   - `zig_vst3_event_echo.vst3`: route event output and confirm input events are echoed.
6. Save and reload the session, then confirm parameter state and scan status are preserved.
