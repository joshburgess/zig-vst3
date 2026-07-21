param(
  [ValidateSet("build", "test")]
  [string]$Mode = "build"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$SourceDir = Join-Path $Root "gui-adapters/vstgui"
$BuildDir = Join-Path $Root ".vst3-sdk/vstgui-adapter-build"

cmake -S $SourceDir -B $BuildDir `
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
