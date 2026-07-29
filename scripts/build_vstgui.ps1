param(
  [ValidateSet("build", "test")]
  [string]$Mode = "build"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$SourceDir = Join-Path $Root "gui-adapters/vstgui"
$BuildDir = Join-Path $Root ".vst3-sdk/vstgui-adapter-build"
$VisualTestArgs = $env:VSTGUI_VISUAL_TEST_ARGS
if ($null -eq $VisualTestArgs) { $VisualTestArgs = "" }
$RunVisualTests = $env:VSTGUI_RUN_VISUAL_TESTS
if ($null -eq $RunVisualTests) { $RunVisualTests = "ON" }

function Get-ZigLibcDirectories {
  if ([string]::IsNullOrWhiteSpace($env:ZIG_LIBC_FILE)) {
    $Lines = & zig libc
    if ($LASTEXITCODE -ne 0) {
      throw "Could not query Zig's native libc configuration"
    }
  } else {
    $Lines = Get-Content -LiteralPath $env:ZIG_LIBC_FILE
  }

  $Directories = @{}
  foreach ($Line in $Lines) {
    if ($Line -match "^([^=]+)=(.*)$") {
      $Directories[$Matches[1]] = $Matches[2]
    }
  }
  foreach ($Name in @("msvc_lib_dir", "crt_dir")) {
    if ([string]::IsNullOrWhiteSpace($Directories[$Name])) {
      throw "Zig's libc configuration does not define $Name"
    }
  }
  return $Directories
}

function Copy-MsvcRuntimeLibraries {
  param([string]$Destination)

  $Directories = Get-ZigLibcDirectories
  $Libraries = @(
    @{ Source = Join-Path $Directories["msvc_lib_dir"] "msvcprt.lib"; Name = "msvcprt.lib" },
    @{ Source = Join-Path $Directories["msvc_lib_dir"] "vcruntime.lib"; Name = "vcruntime.lib" },
    @{ Source = Join-Path $Directories["crt_dir"] "ucrt.lib"; Name = "ucrt.lib" }
  )
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($Library in $Libraries) {
    if (-not (Test-Path -LiteralPath $Library.Source -PathType Leaf)) {
      throw "Required MSVC runtime library not found: $($Library.Source)"
    }
    Copy-Item -LiteralPath $Library.Source `
      -Destination (Join-Path $Destination $Library.Name) `
      -Force
  }
}

cmake -S $SourceDir -B $BuildDir `
  "-DZIG_VSTGUI_VISUAL_TEST_ARGS=$VisualTestArgs" `
  "-DZIG_VSTGUI_RUN_VISUAL_TESTS=$RunVisualTests" `
  -DVSTGUI_STANDALONE=OFF `
  -DVSTGUI_STANDALONE_EXAMPLES=OFF `
  -DVSTGUI_TOOLS=OFF `
  -DVSTGUI_DISABLE_UNITTESTS=ON `
  -DVSTGUI_UISCRIPTING=OFF `
  -DVSTGUI_ENABLE_OPENGL_SUPPORT=OFF `
  -DVSTGUI_ENABLE_XMLPARSER=OFF
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $BuildDir --config Release --target zig_vstgui_adapter --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-MsvcRuntimeLibraries -Destination (Join-Path $BuildDir "Release/libs")

if ($Mode -eq "test") {
  cmake --build $BuildDir --config Release --target zig_vstgui_adapter_tests_run zig_vstgui_visual_tests_run --parallel
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
