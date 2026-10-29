# Lanzador de AssettoServer con cambio de mapa independiente de los presets.
# - Lee map_selection.json (lo escribe MapVotePlugin).
# - Parchea TRACK y CONFIG_TRACK en cfg\server_cfg.ini y en presets\*\server_cfg.ini,
#   de modo que el mapa elegido se mantiene al cambiar de preset de coches.
# - Reinicia el servidor cuando el plugin lo solicita.
# Ejecutalo desde la carpeta de AssettoServer:  powershell -ExecutionPolicy Bypass -File .\start_server.ps1

$ErrorActionPreference = 'Stop'
$root      = $PSScriptRoot
$exe       = Join-Path $root 'AssettoServer.exe'
$selection = Join-Path $root 'map_selection.json'
$flag      = Join-Path $root 'map_restart.flag'
$utf8      = New-Object System.Text.UTF8Encoding $false

function Set-IniValue([string]$text, [string]$key, [string]$value) {
    # Sustituye "KEY=..." sin tocar saltos de linea (respeta CRLF).
    return [regex]::Replace($text, "(?m)^$key=[^\r\n]*", "$key=$value")
}

function Apply-Selection {
    if (-not (Test-Path $selection)) { return }
    $sel = Get-Content $selection -Raw | ConvertFrom-Json
    $targets = @()
    $cfg = Join-Path $root 'cfg\server_cfg.ini'
    if (Test-Path $cfg) { $targets += $cfg }
    $presets = Join-Path $root 'presets'
    if (Test-Path $presets) {
        Get-ChildItem $presets -Directory | ForEach-Object {
            $p = Join-Path $_.FullName 'server_cfg.ini'
            if (Test-Path $p) { $targets += $p }
        }
    }
    foreach ($t in $targets) {
        $text = [System.IO.File]::ReadAllText($t)
        $text = Set-IniValue $text 'TRACK' $sel.track
        $text = Set-IniValue $text 'CONFIG_TRACK' $sel.layout
        [System.IO.File]::WriteAllText($t, $text, $utf8)
    }
    Write-Host "[launcher] Mapa aplicado: $($sel.track) / '$($sel.layout)' en $($targets.Count) ficheros"
    # Marcar la solicitud como atendida
    $sel.restartRequested = $false
    [System.IO.File]::WriteAllText($selection, ($sel | ConvertTo-Json), $utf8)
}

while ($true) {
    Apply-Selection
    if (Test-Path $flag) { Remove-Item $flag -Force }

    $p = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru -NoNewWindow
    $restart = $false
    while (-not $p.HasExited) {
        if (Test-Path $flag) {          # modo RestartMode: File
            Write-Host '[launcher] Reinicio solicitado (flag)'
            Stop-Process -Id $p.Id -Force
            $restart = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    $p.WaitForExit()

    if (-not $restart -and (Test-Path $selection)) {   # modo RestartMode: Exit
        $sel = Get-Content $selection -Raw | ConvertFrom-Json
        if ($sel.restartRequested -eq $true) { $restart = $true }
    }
    if (-not $restart) { Write-Host '[launcher] El servidor se ha detenido.'; break }
    Write-Host '[launcher] Reiniciando con el nuevo mapa...'
    Start-Sleep -Seconds 2
}
