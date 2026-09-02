"""Mission ciblée (2026-07-30, AUCUN appel LLM, AUCUN réseau, budget 0,00 $) —
ferme un trou de preuve distinct de `test_run_real_stream_json_volume.py`.

Ce que ce fichier NE prouve PAS (déjà couvert ailleurs) : le PARSING d'un flux
`stream-json` volumineux — `test_run_real_stream_json_volume.py` l'établit,
mais en monkeypatchant `subprocess.run` (cf. son `_fake_run_with_stdout`), ce
qui fait prendre à `_run_subprocess_tree` la branche « seam compat tests » de
son propre docstring et évite TOTALEMENT le chemin Popen réel.

Ce que ce fichier prouve : la CAPTURE elle-même, par le chemin de PRODUCTION —
`subprocess.run` non monkeypatché => `_run_subprocess_tree` prend la branche
Popen + `communicate()` + tree-kill (cf. son docstring, lignes 123-126 de
`run_real.py`). Le déclencheur : le basculement récent de `claude -p
--output-format json` vers `--output-format stream-json --verbose` change
d'ordre de grandeur le volume qui transite par les pipes stdout/stderr — et
le même docstring documente un incident RÉEL sur ce chemin précis (FIR-01,
P0) : « sans quoi communicate() deadlocke sur le petit-fils claude.exe ».
Le risque de pipe sur ce chemin n'est donc pas théorique.

Aucun `claude` invoqué : le sous-processus est un interpréteur Python LOCAL
trivial (`sys.executable -c <script>`) qui écrit plusieurs Mo sur stdout ET
stderr — assez pour dépasser tout tampon de pipe par défaut (~64 Ko sur
Windows) et forcer un drainage réellement concurrent, sans dépendre du
réseau ni d'un binaire tiers.

Volume retenu — justification : `test_run_real_stream_json_volume.py` a déjà
établi qu'une étape de build réelle (~190 000 tokens, ratio ~4 o/token) pèse
de l'ordre de ~760 Ko. Ce fichier vise délibérément PLUS HAUT sur ce chemin-ci
(~6 Mo stdout + ~2 Mo stderr, ~8 Mo combinés) : marge ~8-10x au-dessus de
l'estimation réaliste, pour stresser franchement le mécanisme de pipe
lui-même plutôt que de coller pile à l'estimation. Rejouable en routine :
écrire/lire quelques Mo en local prend une fraction de seconde, le test est
borné par un timeout explicite et une assertion de délai écoulé.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import subprocess
import sys
import time

import forge.run_real as run_real

# --- gabarit du flux généré par le processus enfant --------------------------------
# Tailles choisies pour dépasser tout tampon de pipe par défaut (chunk >> 64 Ko),
# afin qu'une capture NON concurrente (lecture séquentielle stdout PUIS stderr,
# plutôt que le drainage concurrent de `communicate()`) bloquerait le processus
# enfant en écriture — configuration classique de deadlock de pipes.
_CHUNK = 200_000  # octets par écriture — trois fois le tampon de pipe Windows typique
_OUT_REPS = 30    # 30 * 200_000 = 6_000_000 o de corps stdout
_MID_AT = 15      # marqueur milieu inséré à mi-parcours de la boucle stdout
_ERR_REPS = 10    # 10 * 200_000 = 2_000_000 o de corps stderr, ÉCRIT PENDANT la
                  # boucle stdout (pas après) — stderr non vide EN MÊME TEMPS qu'un
                  # gros stdout, le point 4 de la mission.

_HEAD = "HEAD_MARKER_STDOUT_BEGIN_"
_MID = "_MID_MARKER_STDOUT_MIDDLE_"
_TAIL = "_TAIL_MARKER_STDOUT_END"

_ERR_HEAD = "HEAD_MARKER_STDERR_BEGIN_"
_ERR_TAIL = "_TAIL_MARKER_STDERR_END"

# Script enfant : aucune dépendance externe, aucun fichier temporaire, ASCII pur
# (évite tout aléa d'encodage console Windows — la comparaison d'égalité stricte
# ci-dessous doit rester valide au caractère près).
_CHILD_SCRIPT = f"""
import sys
CHUNK = {_CHUNK}
OUT_REPS = {_OUT_REPS}
MID_AT = {_MID_AT}
ERR_REPS = {_ERR_REPS}
sys.stdout.write({_HEAD!r})
sys.stderr.write({_ERR_HEAD!r})
for i in range(OUT_REPS):
    sys.stdout.write("O" * CHUNK)
    if i == MID_AT:
        sys.stdout.write({_MID!r})
    if i < ERR_REPS:
        sys.stderr.write("E" * CHUNK)
        sys.stderr.flush()
    sys.stdout.flush()
sys.stdout.write({_TAIL!r})
sys.stderr.write({_ERR_TAIL!r})
sys.stdout.flush()
sys.stderr.flush()
"""


def _expected_stdout() -> str:
    parts = [_HEAD]
    for i in range(_OUT_REPS):
        parts.append("O" * _CHUNK)
        if i == _MID_AT:
            parts.append(_MID)
    parts.append(_TAIL)
    return "".join(parts)


def _expected_stderr() -> str:
    return _ERR_HEAD + ("E" * _CHUNK) * _ERR_REPS + _ERR_TAIL


# =====================================================================================
# Preuve d'identité du seam — condition PRÉALABLE à toute la mission : si
# `subprocess.run` était monkeypatché ici, `_run_subprocess_tree` prendrait la
# branche compat-tests et le test suivant ne prouverait RIEN sur le chemin Popen.
# =====================================================================================

def test_subprocess_run_est_bien_loriginale_non_monkeypatchee():
    """`_run_subprocess_tree` décide de sa branche par IDENTITÉ d'objet
    (`subprocess.run is not _REAL_SUBPROCESS_RUN`, run_real.py l.127) — donc la
    preuve que le chemin Popen est exercé PASSE PAR CETTE identité, pas par une
    supposition. Ce test échouerait bruyamment si un test voisin laissait fuiter
    un monkeypatch non annulé (ce que `monkeypatch` de pytest empêche déjà par
    construction, mais la garantie mérite d'être vérifiée, pas supposée)."""
    assert subprocess.run is run_real._REAL_SUBPROCESS_RUN
    assert run_real.subprocess.run is run_real._REAL_SUBPROCESS_RUN


# =====================================================================================
# Le test central : chemin Popen réel, gros stdout + gros stderr simultanés,
# intégrité octet pour octet, aucun deadlock, borné par un timeout explicite.
# =====================================================================================

def test_run_subprocess_tree_chemin_popen_reel_capture_gros_stdout_et_stderr_intacts(tmp_path):
    # Condition de la mission : AUCUN monkeypatch de subprocess.run dans ce test —
    # vérifié explicitement (pas supposé) avant l'appel, pour que l'assertion
    # d'identité et l'appel réel soient dans la MÊME fonction de test, sans
    # dépendre de l'ordre d'exécution avec le test précédent.
    assert subprocess.run is run_real._REAL_SUBPROCESS_RUN

    cmd = [sys.executable, "-c", _CHILD_SCRIPT]
    expected_stdout = _expected_stdout()
    expected_stderr = _expected_stderr()
    assert len(expected_stdout) >= 6_000_000, "sanity: volume stdout attendu"
    assert len(expected_stderr) >= 2_000_000, "sanity: volume stderr attendu"

    # Timeout explicite et généreux (30 s) pour un travail qui devrait se jouer
    # en une fraction de seconde — le TEST DE DEADLOCK est l'assertion de délai
    # écoulé ci-dessous, pas ce timeout (qui n'est qu'un filet dur).
    timeout_s = 30.0
    started = time.time()
    returncode, stdout, stderr, timed_out = run_real._run_subprocess_tree(
        cmd, cwd=str(tmp_path), input_text="PROMPT_TRIVIAL_NON_LU_PAR_LENFANT",
        timeout_s=timeout_s,
    )
    elapsed = time.time() - started

    # --- absence de deadlock : la main est rendue vite, largement sous le budget ---
    assert timed_out is False, "le chemin Popen a déclenché le tree-kill : deadlock ou lenteur anormale"
    assert elapsed < 15.0, f"rendu la main après {elapsed:.2f}s — trop proche d'un deadlock pour être sain"
    assert returncode == 0

    # --- intégrité : jamais par la seule longueur ---------------------------------
    assert len(stdout) == len(expected_stdout), (
        f"longueur stdout divergente : {len(stdout)} vs attendu {len(expected_stdout)}")
    assert stdout.startswith(_HEAD)
    assert stdout.endswith(_TAIL)
    assert _MID in stdout
    assert stdout == expected_stdout, "stdout NON identique octet pour octet à ce que l'enfant a émis"

    assert len(stderr) == len(expected_stderr), (
        f"longueur stderr divergente : {len(stderr)} vs attendu {len(expected_stderr)}")
    assert stderr.startswith(_ERR_HEAD)
    assert stderr.endswith(_ERR_TAIL)
    assert stderr == expected_stderr, "stderr NON identique octet pour octet à ce que l'enfant a émis"

    total_bytes = len(stdout.encode("utf-8")) + len(stderr.encode("utf-8"))
    assert total_bytes >= 8_000_000  # preuve chiffrée du volume réellement transité
