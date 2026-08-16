# Toolchain

## Zig

Pinned compiler version: 0.16.0

## VST3 SDK

- Repository: `https://github.com/steinbergmedia/vst3sdk.git`
- Tag: `v3.8.0_build_66`
- Commit: `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`
- Default checkout path: `.vst3-sdk/vst3sdk`
- Default build path: `.vst3-sdk/vst3sdk/build`

## Reference Projects

The following sources are verification-only dependencies. They are not linked
into ordinary `zig-vst3` consumers. Their preparation scripts pin archive
hashes and reject identity drift:

- libogg 1.3.5 and libvorbis 1.3.7 through
  `scripts/prepare_xiph_vorbis_reference.sh`
- Tremor commit `820fb3237ea81af44c9cc468c8b4e20128e3e5ad` through
  `scripts/prepare_tremor.sh`
- stb_vorbis 1.22 at commit
  `2c980bb59875b0d32144a71867fbdebb2f77cd20` through
  `scripts/prepare_stb_vorbis.sh`
- Helix hmp3 5.2.4 at commit
  `7f7dfc7680db3c05f8e4a8fbd9861cbb06427d92` through
  `scripts/prepare_helix_mp3_encoder.sh`
- libmysofa 1.3.5 at commit
  `6cc5b15a73e9bd97810d03767082edda7f315881` through
  `scripts/prepare_libmysofa_renderer.sh`
- libspatialaudio 0.4.1 through
  `scripts/prepare_libspatialaudio_renderer.sh`
- The Viking HRTF v2 and HUTUBS participant 1 datasets through
  `scripts/fetch_hrtf_sofa_fixture.sh` and
  `scripts/fetch_hutubs_hrtf_sofa_fixture.sh`
- The AndroidX Media VBRI asset at commit
  `3eb36d67bd90d6d962df26dfdf29701a45902b4a` through
  `scripts/fetch_androidx_vbri_fixture.sh`

## Framework Release

`zig-vst3-0.3.0` uses the Zig and VST3 SDK pins above plus the bundled ARA
SDK 2.3 headers. A pin change requires a new release candidate and the complete
framework candidate gate.
