# start_observer.ps1
# Lance le Forge Observer (lecture seule) en arriere-plan et ouvre la console web.
# Windows PowerShell 5.1. ASCII pur (pas d'accents) - PS 5.1 lit l'UTF-8 sans BOM comme
# de l'ANSI, donc ce fichier evite tout caractere hors ASCII.
#
# Usage:
#   .\start_observer.ps1
#   .\start_observer.ps1 -Port 8771 -Project breakout_v2 -TimeoutSeconds 30
#
# Comportement:
#   1. Resout l'interpreteur Python (venv d'abord, PATH ensuite).
#   2. Si le port repond deja a un Observer (api/health), ouvre juste le navigateur.
#      Si le port est occupe par autre chose, sort en erreur sans rien tuer.
#   3. Demarre live.py en arriere-plan, logs rediriges hors du depot.
#   4. Attend que /api/health reponde reellement (sondage, pas un sleep fixe).
#   5. Ouvre le navigateur sur la console.
#   6. En cas de timeout, affiche la fin du log et sort en erreur.

param(
    [int]$Port = 8771,
    [string]$Project = "breakout_v2",
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Chemins
# ---------------------------------------------------------------------------

$ScriptDir = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path
$LivePy = Join-Path $RepoRoot "scripts\observer\live.py"
$VenvPython = Join-Path $RepoRoot ".venv312\Scripts\python.exe"

$LogDir = Join-Path $env:LOCALAPPDATA "ForgeObserver"
$LogFile = Join-Path $LogDir "observer.log"
$LaunchCmd = Join-Path $LogDir ("_launch_{0}.cmd" -f $Port)
$Url = "http://127.0.0.1:$Port/"
$HealthUrl = "http://127.0.0.1:$Port/api/health"

# ---------------------------------------------------------------------------
# Fonctions
# ---------------------------------------------------------------------------

function Write-Info($msg) {
    Write-Host "[observer] $msg"
}

function Write-ErrorLine($msg) {
    Write-Host "[observer] ERREUR: $msg" -ForegroundColor Red
}

function Test-TcpPortOpen {
    param([string]$ComputerName, [int]$PortNumber, [int]$TimeoutMs = 500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $PortNumber, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if (-not $ok) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Test-ObserverHealth {
    param([string]$HealthEndpoint, [int]$TimeoutSec = 2)
    try {
        $resp = Invoke-WebRequest -Uri $HealthEndpoint -UseBasicParsing -TimeoutSec $TimeoutSec
        if ($resp.StatusCode -eq 200) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-PortOwnerProcess {
    param([int]$PortNumber)
    try {
        $conn = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($conn) {
            return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        }
    }
    catch {
        try {
            $lines = netstat -ano | Select-String (":{0}\s" -f $PortNumber) | Select-String "LISTENING"
            if ($lines) {
                $firstLine = $lines[0].ToString()
                $parts = $firstLine -split "\s+" | Where-Object { $_ -ne "" }
                $procId = $parts[$parts.Count - 1]
                return Get-Process -Id $procId -ErrorAction SilentlyContinue
            }
        }
        catch {
            return $null
        }
    }
    return $null
}

function Wait-EnterToClose {
    param([string]$Message)
    Write-ErrorLine $Message
    try {
        Read-Host "Appuyez sur Entree pour fermer cette fenetre"
    }
    catch {
        Start-Sleep -Seconds 5
    }
}

# ---------------------------------------------------------------------------
# Etape 1: resoudre l'interpreteur Python
# ---------------------------------------------------------------------------

$PythonExe = $null

if (Test-Path $VenvPython) {
    $PythonExe = $VenvPython
    Write-Info "Interpreteur: $PythonExe (venv312)"
}
else {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
        $PythonExe = $cmd.Source
        Write-Info "Interpreteur: $PythonExe (PATH)"
    }
}

if (-not $PythonExe) {
    Wait-EnterToClose "Aucun interpreteur Python trouve. Attendu: $VenvPython ou 'python' dans le PATH. Installez Python ou creez le venv312, puis reessayez."
    exit 1
}

if (-not (Test-Path $LivePy)) {
    Wait-EnterToClose "Fichier introuvable: $LivePy. Le depot est-il complet ?"
    exit 1
}

# ---------------------------------------------------------------------------
# Etape 2: le port est-il deja occupe par un Observer ?
# ---------------------------------------------------------------------------

$portOpen = Test-TcpPortOpen -ComputerName "127.0.0.1" -PortNumber $Port -TimeoutMs 500

if ($portOpen) {
    Write-Info "Port $Port deja occupe, verification de /api/health ..."
    $alreadyObserver = Test-ObserverHealth -HealthEndpoint $HealthUrl -TimeoutSec 3

    if ($alreadyObserver) {
        Write-Info "Un Observer repond deja sur ce port. Ouverture du navigateur sans relancer de serveur."
        Start-Process $Url
        exit 0
    }
    else {
        $owner = Get-PortOwnerProcess -PortNumber $Port
        if ($owner) {
            Write-ErrorLine ("Port $Port occupe par un autre processus: {0} (PID {1}). Aucune action prise. Choisissez un autre -Port ou liberez le port vous-meme." -f $owner.ProcessName, $owner.Id)
        }
        else {
            Write-ErrorLine "Port $Port occupe par un processus non identifiable. Aucune action prise."
        }
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Etape 3: demarrer le serveur en arriere-plan, logs hors depot
# ---------------------------------------------------------------------------

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "" -Encoding UTF8
Add-Content -Path $LogFile -Value "===== $stamp - start_observer.ps1 lance (port=$Port project=$Project) =====" -Encoding UTF8

# On passe par un petit fichier .cmd genere (hors depot, dans LogDir) plutot que par
# Start-Process -ArgumentList "/c", "<commande avec guillemets imbriques>" : ce dernier
# fait perdre le controle exact des guillemets (PowerShell puis cmd.exe requotent tous
# les deux), ce qui a ete observe planter cmd.exe silencieusement (exit code 1, aucune
# ligne de log). Le fichier .cmd fixe le texte de la commande une bonne fois pour toutes.
# -u (sortie non bufferisee) : sans ca, Python bufferise stdout/stderr par blocs des
# qu'ils sont rediriges vers un fichier, et le log reste vide tant que le process
# tourne (observe en test). Necessaire pour que le fichier de log serve au diagnostic
# pendant que le serveur est en vie, pas seulement apres coup.
$launchLines = @(
    "@echo off"
    "`"$PythonExe`" -X utf8 -u `"$LivePy`" --project `"$Project`" --port $Port >> `"$LogFile`" 2>&1"
)
Set-Content -Path $LaunchCmd -Value $launchLines -Encoding ASCII

Write-Info "Demarrage du serveur (arriere-plan, sans fenetre) ..."
$proc = Start-Process -FilePath $LaunchCmd -WindowStyle Hidden -PassThru

Write-Info "Processus lanceur PID $($proc.Id). Attente de /api/health (timeout ${TimeoutSeconds}s) ..."

# ---------------------------------------------------------------------------
# Etape 4: sonder /api/health jusqu'a reponse ou timeout
# ---------------------------------------------------------------------------

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$healthy = $false

while ((Get-Date) -lt $deadline) {
    if (Test-ObserverHealth -HealthEndpoint $HealthUrl -TimeoutSec 2) {
        $healthy = $true
        break
    }

    if ($proc.HasExited) {
        Write-ErrorLine "Le processus s'est arrete avant de repondre (code de sortie: $($proc.ExitCode))."
        break
    }

    Write-Host "." -NoNewline
    Start-Sleep -Milliseconds 500
}
Write-Host ""

# ---------------------------------------------------------------------------
# Etape 5 / 6: ouvrir le navigateur, ou afficher le log et sortir en erreur
# ---------------------------------------------------------------------------

if ($healthy) {
    Write-Info "Observer pret sur $Url"
    Start-Process $Url
    exit 0
}
else {
    Write-ErrorLine "Timeout: l'Observer n'a pas repondu sur $HealthUrl dans les ${TimeoutSeconds}s."
    Write-ErrorLine "Dernieres lignes de $LogFile :"
    if (Test-Path $LogFile) {
        Get-Content -Path $LogFile -Tail 30 | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-ErrorLine "(fichier de log absent)"
    }
    exit 1
}
