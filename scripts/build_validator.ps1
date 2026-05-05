$ErrorActionPreference = "Stop"

$SdkDir = if ($env:VST3_SDK_DIR) { $env:VST3_SDK_DIR } else { ".vst3-sdk/vst3sdk" }
$BuildDir = if ($env:VST3_SDK_BUILD_DIR) { $env:VST3_SDK_BUILD_DIR } else { Join-Path $SdkDir "build" }
$Config = if ($env:VST3_SDK_CONFIG) { $env:VST3_SDK_CONFIG } else { "Release" }

if (!(Test-Path (Join-Path $SdkDir ".git"))) {
    Write-Error "SDK checkout not found at $SdkDir. Run .\scripts\fetch_sdk.ps1 first."
}

cmake -S $SdkDir -B $BuildDir `
    -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF `
    -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF `
    -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON

cmake --build $BuildDir --config $Config --target validator
