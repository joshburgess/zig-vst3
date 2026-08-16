param(
    [string]$SdkDirectory = (
        Join-Path $PSScriptRoot '..\.windows-midi-sdk'
    )
)

$ErrorActionPreference = 'Stop'

$version = '1.0.17-rc.4.25'
$packageName = "Microsoft.Windows.Devices.Midi2.$version.nupkg"
$packageUrl = "https://github.com/microsoft/MIDI/releases/download/rc-4/$packageName"
$expectedHash = 'D0A420E724154AAF707CBCEEFDE0E355B0B6D9DCD37160F767BFAC6A9C9A86E6'
$packagePath = Join-Path $sdkDirectory $packageName
$metadataPath = Join-Path $sdkDirectory 'ref\native\Microsoft.Windows.Devices.Midi2.winmd'
$generatedDirectory = Join-Path $sdkDirectory 'generated'
$generatedHeader = Join-Path $generatedDirectory 'winrt\Microsoft.Windows.Devices.Midi2.h'
$kitRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'

New-Item -ItemType Directory -Force -Path $sdkDirectory | Out-Null

if (-not (Test-Path $packagePath)) {
    Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath
}

$actualHash = (Get-FileHash -Algorithm SHA256 $packagePath).Hash
if ($actualHash -ne $expectedHash) {
    throw "Windows MIDI SDK hash mismatch. Expected $expectedHash, found $actualHash"
}

if (-not (Test-Path $metadataPath)) {
    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $packagePath,
        $sdkDirectory,
        $true
    )
}

$cppwinrtCandidates =
    Get-ChildItem -Path $kitRoot -Filter cppwinrt.exe -Recurse
$cppwinrt = $cppwinrtCandidates |
    Where-Object FullName -Match '\\x64\\cppwinrt\.exe$' |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $cppwinrt) {
    $cppwinrt = $cppwinrtCandidates |
        Sort-Object FullName -Descending |
        Select-Object -First 1
}
if ($null -eq $cppwinrt) {
    throw "cppwinrt.exe was not found under $kitRoot"
}

if (-not (Test-Path $generatedHeader)) {
    New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
    & $cppwinrt.FullName `
        -input $metadataPath `
        -reference sdk `
        -output $generatedDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "cppwinrt.exe failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path $generatedHeader)) {
        throw "cppwinrt.exe did not generate $generatedHeader"
    }
}

$windowsSdkVersion = $cppwinrt.Directory.Parent.Name
$windowsCppWinRtInclude = Join-Path (
    Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
) "$windowsSdkVersion\cppwinrt"
if (-not (Test-Path (Join-Path $windowsCppWinRtInclude 'winrt\base.h'))) {
    throw "C++/WinRT headers were not found under $windowsCppWinRtInclude"
}
$windowsSdkWinRtInclude = Join-Path (
    Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
) "$windowsSdkVersion\winrt"
if (-not (Test-Path (Join-Path $windowsSdkWinRtInclude 'roapi.h'))) {
    throw "Windows SDK WinRT headers were not found under $windowsSdkWinRtInclude"
}

$msvcInclude = $null
if ($env:VCToolsInstallDir) {
    $candidate = Join-Path $env:VCToolsInstallDir 'include'
    if (Test-Path (Join-Path $candidate 'vector')) {
        $msvcInclude = $candidate
    }
}
if ($null -eq $msvcInclude) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} (
        'Microsoft Visual Studio\Installer\vswhere.exe'
    )
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe was not found at $vswhere"
    }
    $visualStudioRoot = & $vswhere `
        -latest `
        -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $visualStudioRoot) {
        throw "Visual Studio C++ tools were not found"
    }
    $msvcInclude = Get-ChildItem (
        Join-Path $visualStudioRoot 'VC\Tools\MSVC'
    ) -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'include' } |
        Where-Object { Test-Path (Join-Path $_ 'vector') } |
        Select-Object -First 1
}
if ($null -eq $msvcInclude) {
    throw "MSVC C++ standard-library headers were not found"
}

$env:ZIG_WINDOWS_CPPWINRT_INCLUDE = $windowsCppWinRtInclude
$env:ZIG_WINDOWS_MSVC_INCLUDE = $msvcInclude
$env:ZIG_WINDOWS_SDK_WINRT_INCLUDE = $windowsSdkWinRtInclude
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    (Join-Path $sdkDirectory 'cppwinrt-include-path.txt'),
    "$windowsCppWinRtInclude`n",
    $utf8NoBom
)
[IO.File]::WriteAllText(
    (Join-Path $sdkDirectory 'msvc-include-path.txt'),
    "$msvcInclude`n",
    $utf8NoBom
)
[IO.File]::WriteAllText(
    (Join-Path $sdkDirectory 'windows-sdk-winrt-include-path.txt'),
    "$windowsSdkWinRtInclude`n",
    $utf8NoBom
)
if ($env:GITHUB_ENV) {
    "ZIG_WINDOWS_CPPWINRT_INCLUDE=$windowsCppWinRtInclude" |
        Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    "ZIG_WINDOWS_MSVC_INCLUDE=$msvcInclude" |
        Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    "ZIG_WINDOWS_SDK_WINRT_INCLUDE=$windowsSdkWinRtInclude" |
        Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}

Write-Host "Windows MIDI SDK $version ready at $sdkDirectory"
Write-Host "C++/WinRT includes: $windowsCppWinRtInclude"
Write-Host "MSVC includes: $msvcInclude"
Write-Host "Windows SDK WinRT includes: $windowsSdkWinRtInclude"
