# Validator Harness

The validator harness uses Steinberg's VST3 SDK validator from the pinned SDK checkout.

## Fetch the SDK

```sh
scripts/fetch_sdk.sh
```

On Windows:

```powershell
.\scripts\fetch_sdk.ps1
```

The scripts clone `v3.8.0_build_66` and fail if the checkout does not resolve to commit `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`.

## Run the validator

Build Steinberg's validator:

```sh
scripts/build_validator.sh
```

On Windows:

```powershell
.\scripts\build_validator.ps1
```

Then run it through the project wrapper:

```sh
scripts/validate.sh path/to/Plugin.vst3
```

Set `VST3_VALIDATOR` if the validator binary is outside the default SDK build directories:

```sh
VST3_VALIDATOR=/path/to/validator scripts/validate.sh path/to/Plugin.vst3
```

The wrapper checks the default SDK build output directories first. Use `VST3_VALIDATOR` when testing a validator binary built elsewhere.
