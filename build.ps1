# Equivalente en PowerShell de build.py (por si no tienes Python).
# Uso:  powershell -ExecutionPolicy Bypass -File .\build.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src  = Join-Path $root 'src'
$out  = Join-Path $root 'dist\acs_drift_menu.lua'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Lf([string]$p) { return ([System.IO.File]::ReadAllText($p) -replace "`r`n", "`n").TrimEnd("`n") }

$parts = New-Object System.Collections.Generic.List[string]
$parts.Add('-- ACS Drift by Water - script ONLINE para CSP')
$parts.Add("-- ARCHIVO GENERADO por build.ps1 ($(Get-Date -Format 'yyyy-MM-dd HH:mm')). No lo edites: edita src/.")
$parts.Add('-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]). Tecla M: abrir/cerrar.')
$parts.Add('')
$parts.Add('local __modules, __cache = {}, {}')
$parts.Add('local function import(name)')
$parts.Add('  local cached = __cache[name]')
$parts.Add('  if cached == nil then')
$parts.Add('    local loader = __modules[name]')
$parts.Add("    if not loader then error('modulo no encontrado: ' .. tostring(name)) end")
$parts.Add('    cached = loader()')
$parts.Add('    __cache[name] = cached == nil and true or cached')
$parts.Add('  end')
$parts.Add('  return cached')
$parts.Add('end')
$parts.Add('')

$files = Get-ChildItem $src -Recurse -Filter *.lua | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1) -replace '\\','/' -replace '\.lua$',''
    [pscustomobject]@{ Name = $rel; Path = $_.FullName }
} | Sort-Object Name

foreach ($f in $files) {
    if ($f.Name -eq 'main') { continue }
    $parts.Add("-- ===== modulo: $($f.Name) (src/$($f.Name).lua) =====")
    $parts.Add("__modules['$($f.Name)'] = function()")
    $parts.Add((Read-Lf $f.Path))
    $parts.Add('end')
    $parts.Add('')
}
$parts.Add('-- ===== punto de entrada (src/main.lua) =====')
$parts.Add("__modules['__main'] = function()")
$parts.Add((Read-Lf (Join-Path $src 'main.lua')))
$parts.Add('end')
$parts.Add("import('__main')")
$parts.Add('')

New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
[System.IO.File]::WriteAllText($out, ($parts -join "`n"), $utf8)
Write-Host "OK: $out ($($files.Count) modulos)"
