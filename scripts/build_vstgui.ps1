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

if ($Mode -eq "test") {
  cmake --build $BuildDir --config Release --target zig_vstgui_adapter_tests_run zig_vstgui_visual_tests_run --parallel
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
