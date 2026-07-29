# Real Host Coverage

This page tracks the remaining work that cannot be proven by ABI fixtures alone.

The [open-work tracker](open-work.md) is the consolidated index for automated checks, cleanup debt, feature work, and manual confirmation. This page retains the detailed host procedures.

## Automated Host-Like Gates

Run these before recording new host rows:

```sh
zig build validate-examples
zig build pluginval-examples
zig build pluginval-strict-examples
```

`pluginval-strict-examples` runs pluginval at strictness level 10. It exercises non-releasing processing, state restoration, background thread state, parameter thread safety, and parameter fuzzing across all native examples. It does not replace real DAW testing or Steinberg's validator.

## GUI And Editor Coverage

Current state:

- Raw GUI interfaces and helpers are ABI-tested and unit-tested.
- The production Gain, Channel Strip, IR Loader, Parametric EQ, Resonant Filter, and Sample Player examples expose visible VSTGUI editors in native builds and protocol-only fallbacks in cross-target builds.
- `editor-smoke` remains toolkit-free and covers the editor protocol on all four platform identifiers.
- The Steinberg validator and pluginval pass editor-open, open-while-processing, automation, and editor-automation tests on macOS.
- REAPER rows cover Gain, Parametric EQ, and Resonant Filter. The Sample Player bundle and deterministic generated-audio smoke script are installed, but its interactive walkthrough remains pending. No host result is inferred from plugin installation, validator output, or pluginval.

Useful next slices:

- Record real embedded editor rows in at least one host per platform:
  - macOS: REAPER or another AU/VST3 host using `NSView`.
  - Windows: a VST3 host using `HWND`.
  - Linux X11: a host using `X11EmbedWindowID`.
  - Linux Wayland: a host using `WaylandSurfaceID` and `IWaylandFrame`.

The editor smoke example is protocol-focused. The visible editors use the separate VSTGUI integration.
See [the plugin GUI plan](gui-plan.md) for the implementation sequence and platform exit criteria.

## LV2 Host Coverage

Current state:

- The core and UI ABI declarations have independent C layout checks.
- Dynamically loaded fixtures exercise core processing, state, Worker calls, UI parent attachment, control-port updates, host writes, optional touch, idle, show, hide, resize, malformed host inputs, and teardown.
- The native Mono Gain bundle links the production VSTGUI parameter backend, publishes the platform widget only after successful attachment, and declares the native UI class and parent feature in generated Turtle.
- The UI fixture cross-builds for Linux aarch64, Linux x86-64, and Windows x86-64 GNU.
- Generated Turtle can associate a plugin with a separate UI resource, class, and binary.
- The complete generated bundle passes the LV2 1.18.10 RDF schema validator and warning-fatal `lv2lint` 0.16.2 in direct-distribution mode. The validator loads and verifies both native descriptors.
- Automated smoke coverage proves native widget publication and descriptor loading without a physical host. External host scheduling and external Turtle discovery remain unproven.

Useful next slices:

- Load the linked VSTGUI UI on each supported platform and test it in at least two LV2 hosts.
- Confirm native parent and child ownership, automation in both directions, gesture touch notifications, idle cadence, both resize directions, show and hide, two instances, close, reopen, session reload, and teardown.
- Exercise Worker delivery on a real asynchronous host worker thread and confirm responses arrive on a later `run`.

## Advanced Host-Integration Coverage

Current state:

- Data exchange, physical UI mapping, channel context, automation state, compatibility metadata, wrappers, and test-provider APIs have raw declarations, ABI fixtures, and helper tests.
- The gain example has a combined host-context regression test for channel context, automation state, and data exchange. It verifies initialization, callback delegation, block lock/free, queue close, and termination releases when one host exposes all three interfaces.
- Data-exchange helpers reject invalid successful queue and block outputs, so plugin code does not consume an invalid queue ID or empty block after a delegated host callback reports success.
- Data-exchange receiver callbacks are covered through a real component query path, including queue-open dispatch selection, queue-close notification, and block-delivery delegation.
- Reflected controllers can expose static physical UI maps. The gain controller advertises a pressure-to-expression map that Steinberg's validator can query.
- Compatibility JSON can be exposed as a factory class. The factory regression creates an `IPluginCompatibility` class through `IPluginFactory3` and streams the JSON payload through `IBStream`.
- Test plug providers retain returned component and controller interfaces as required by the SDK. The regression uses real gain component/controller objects and balances the retained references through `releasePlugIn`.
- Wrapper MPE support helpers use the SDK default input settings and keep the previous accepted settings when delegated wrapper calls fail.
- Most of them do not have real host rows.

Useful next slices:

- Confirm the sidechain ducker and both auxiliary outputs of the splitter in a host that exposes explicit VST3 bus routing.
- Add a host-smoke row for channel context and automation state using a host that sends those callbacks to the component.
- Add a data-exchange probe once a host or harness that supports `IDataExchangeHandler` is available.
- Record a physical UI mapping host row with a controller/host pair that observes the gain controller's pressure-to-expression map.
- Keep wrapper metadata and compatibility JSON coverage fixture-based until a real wrapper workflow exists.

Record successful host runs in [host-matrix.md](host-matrix.md). Do not mark a protocol host-proven from unit tests or pluginval alone.
