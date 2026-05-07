# Host Matrix

Tier 3 host smoke tests are release gates. Record only tests that were run in a real host with the built plugin artifact.

| Date | Host | Host Version | OS | CPU | Plugin Build | Bundle | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pending | Pending | Pending | Pending | Pending | Pending | `zig_vst3_gain.vst3` | Pending | No real-host smoke test has been recorded yet. |

## Minimum Smoke Test

1. Build the gain bundle with `zig build bundle-gain`.
2. Load `zig-out/bundle/zig_vst3_gain.vst3` in the host.
3. Confirm the plugin scans successfully.
4. Insert it on a stereo audio track.
5. Move the Gain parameter and confirm audible level changes.
6. Save and reload the session, then confirm the Gain value is restored.
