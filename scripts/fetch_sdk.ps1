$ErrorActionPreference = "Stop"

$SdkRepo = if ($env:VST3_SDK_REPO) { $env:VST3_SDK_REPO } else { "https://github.com/steinbergmedia/vst3sdk.git" }
$SdkTag = if ($env:VST3_SDK_TAG) { $env:VST3_SDK_TAG } else { "v3.8.0_build_66" }
$SdkCommit = if ($env:VST3_SDK_COMMIT) { $env:VST3_SDK_COMMIT } else { "9fad9770f2ae8542ab1a548a68c1ad1ac690abe0" }
$SdkDir = if ($env:VST3_SDK_DIR) { $env:VST3_SDK_DIR } else { ".vst3-sdk/vst3sdk" }

if (Test-Path (Join-Path $SdkDir ".git")) {
    git -C $SdkDir fetch --tags $SdkRepo $SdkTag
    git -C $SdkDir checkout --force $SdkCommit
} else {
    $Parent = Split-Path -Parent $SdkDir
    if ($Parent) {
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    }
    git clone --branch $SdkTag --depth 1 $SdkRepo $SdkDir
}

$ActualCommit = (git -C $SdkDir rev-parse HEAD).Trim()
if ($ActualCommit -ne $SdkCommit) {
    Write-Error "VST3 SDK commit mismatch. Expected $SdkCommit, got $ActualCommit."
}

git -C $SdkDir submodule sync --recursive
git -C $SdkDir submodule update --init --depth 1

Write-Host "VST3 SDK ready at $SdkDir ($ActualCommit)"
