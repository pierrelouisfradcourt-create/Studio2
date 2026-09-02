# install_shortcut.ps1
# Cree (ou supprime) un raccourci Bureau "Forge Observer" qui lance start_observer.ps1
# en une seule fois, sans fenetre console visible.
# Windows PowerShell 5.1. ASCII pur (voir start_observer.ps1 pour l'explication).
#
# Usage:
#   .\install_shortcut.ps1              -> cree le raccourci
#   .\install_shortcut.ps1 -Uninstall   -> supprime le raccourci

param(
    [switch]$Uninstall
)

function Write-Info($msg) {
    Write-Host "[observer] $msg"
}

function Write-ErrorLine($msg) {
    Write-Host "[observer] ERREUR: $msg" -ForegroundColor Red
}

$ScriptDir = $PSScriptRoot
$StartScript = Join-Path $ScriptDir "start_observer.ps1"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopDir "Forge Observer.lnk"

if ($Uninstall) {
    if (Test-Path $ShortcutPath) {
        Remove-Item -Path $ShortcutPath -Force
        Write-Info "Raccourci supprime: $ShortcutPath"
        exit 0
    }
    else {
        Write-Info "Aucun raccourci a supprimer (introuvable): $ShortcutPath"
        exit 0
    }
}

if (-not (Test-Path $StartScript)) {
    Write-ErrorLine "Introuvable: $StartScript. Le raccourci ne serait pas fonctionnel, arret."
    exit 1
}

$powershellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $powershellExe)) {
    # repli sur ce qui est deja resolu dans le PATH
    $powershellExe = "powershell.exe"
}

# Icone: on reutilise une icone systeme existante (shell32.dll) plutot que
# d'inventer un .ico qui n'existe pas sur le disque.
$iconDll = Join-Path $env:WINDIR "System32\shell32.dll"
$iconIndex = 13  # icone "reseau / moniteur" du jeu d'icones shell32 standard

try {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $powershellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartScript`""
    $shortcut.WorkingDirectory = $ScriptDir
    $shortcut.Description = "Lance Forge Observer (console lecture seule, port 8771)"
    if (Test-Path $iconDll) {
        $shortcut.IconLocation = "$iconDll,$iconIndex"
    }
    $shortcut.Save()
}
catch {
    Write-ErrorLine "Echec de la creation du raccourci: $($_.Exception.Message)"
    exit 1
}

if (Test-Path $ShortcutPath) {
    Write-Info "Raccourci cree: $ShortcutPath"
    exit 0
}
else {
    Write-ErrorLine "Le raccourci n'a pas ete trouve apres creation: $ShortcutPath"
    exit 1
}
