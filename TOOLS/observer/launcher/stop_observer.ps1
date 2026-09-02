# stop_observer.ps1
# Arrete le(s) processus Python qui font tourner scripts\observer\live.py.
# Windows PowerShell 5.1. ASCII pur (voir start_observer.ps1 pour l'explication).
#
# Usage:
#   .\stop_observer.ps1            -> arrete toute instance de observer\live.py
#   .\stop_observer.ps1 -Port 8771 -> arrete uniquement l'instance lancee avec ce port
#
# Ne touche JAMAIS un processus Python dont la ligne de commande ne contient pas
# "observer\live.py" ou "observer/live.py". Cette machine sert a d'autres taches
# Python en parallele.

param(
    [int]$Port = 0
)

function Write-Info($msg) {
    Write-Host "[observer] $msg"
}

function Write-ErrorLine($msg) {
    Write-Host "[observer] ERREUR: $msg" -ForegroundColor Red
}

$targets = @()

try {
    $candidates = Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" -ErrorAction Stop
}
catch {
    Write-ErrorLine "Impossible d'interroger la liste des processus (Get-CimInstance a echoue) : $($_.Exception.Message)"
    exit 1
}

foreach ($p in $candidates) {
    $cmdLine = $p.CommandLine
    if (-not $cmdLine) {
        continue
    }
    if ($cmdLine -notmatch "observer[\\/]live\.py") {
        continue
    }
    if ($Port -gt 0) {
        # n'accepte que la ligne de commande qui reference explicitement ce port
        $portPattern = "--port[= ]{0}\b" -f $Port
        if ($cmdLine -notmatch $portPattern) {
            continue
        }
    }
    $targets += $p
}

if ($targets.Count -eq 0) {
    if ($Port -gt 0) {
        Write-Info "Aucun processus observer\live.py trouve pour le port $Port. Rien a faire."
    }
    else {
        Write-Info "Aucun processus observer\live.py en cours. Rien a faire."
    }
    exit 0
}

foreach ($p in $targets) {
    $procId = $p.ProcessId
    try {
        Stop-Process -Id $procId -Force -ErrorAction Stop
        Write-Info "Processus arrete: PID $procId (`"$($p.CommandLine)`")"
    }
    catch {
        Write-ErrorLine "Echec de l'arret du PID $procId : $($_.Exception.Message)"
    }
}

exit 0
