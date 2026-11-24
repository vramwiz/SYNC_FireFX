param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_FireFX\SYNC_FireFX.auf2',
    [string]$OutputPath,
    [switch]$Benchmark
)

# 本番AUF2の入出力を検査し、D3D11は画面を開かずに実行する。
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$plugin = (Resolve-Path -LiteralPath $PluginPath).Path
if (-not $OutputPath) { $OutputPath = Join-Path $project 'Win64\Verification' }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputPath).Path
$dcu = Join-Path $output 'DCU'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$lib = Join-Path $studio 'lib\Win64\release'
Push-Location $PSScriptRoot
try {
    & (Join-Path $studio 'bin\dcc64.exe') '--no-config' '-B' '-Q' '-TX.exe' '-$R+' '-$Q+' `
        '-NSSystem;Winapi;Vcl' "-U$lib;$lib\JA" "-E$output" "-NU$dcu" 'FireFX_RenderTests.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'FireFX test build failed.' }
    $testArgs = @($plugin, $output)
    if ($Benchmark) { $testArgs += '--benchmark' }
    & (Join-Path $output 'FireFX_RenderTests.exe') @testArgs
    if ($LASTEXITCODE -ne 0) { throw 'FireFX verification failed.' }
}
finally { Pop-Location }
