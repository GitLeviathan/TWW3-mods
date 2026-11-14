param(
    [string]$GameRoot = 'D:\Steam\steamapps\common\Total War WARHAMMER III'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'Warhammer3.exe') -PathType Leaf)) {
    throw 'Warhammer3.exe not found. Run this launcher with -GameRoot pointing to the game folder.'
}

$nodeExe = (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $nodeExe) {
    $nodeExe = Get-AppxPackage -Name 'OpenAI.CodexPrimaryRuntime*' | ForEach-Object {
        Join-Path $_.InstallLocation 'dependencies\node\bin\node.exe'
    } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $nodeExe) { throw 'Node.js not found. Install Node.js 22 or newer and try again.' }

$codexExe = (Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $codexExe) {
    $codexBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $codexExe = Get-ChildItem -LiteralPath $codexBin -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $codexExe) { throw 'Codex CLI not found. Install it and sign in with codex login.' }

& $nodeExe (Join-Path $PSScriptRoot 'talkhammer-codex.mjs') (Join-Path $GameRoot 'talkhammer_data') $codexExe
exit $LASTEXITCODE
