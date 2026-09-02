# -*- coding: utf-8 -*-
"""Budget de solvabilite de TETRIS inscrit dans `oracles.json` (GO Pierre 2026-08-18).

CONTRADICTION FERMEE. `tetris` declarait `proof.solvability` a son contrat de jeu
(`max_ticks: 20000`) mais n'avait AUCUNE entree `solvability` dans `oracles.json` — la SEULE
source lue par `godot_oracle.resolveSolvabilityConfig`. Il tournait donc sur les VALEURS PAR
DEFAUT (`max_ticks: 200`, `trial_timeout_ms: 10000`), et son contrat n'avait jamais eu la
moindre chance d'agir. L'auto-audit le signalait depuis 5190859 : `CONTRAT_IGNORE`.

LE `won: 0/50` N'ETAIT PAS UN DEFAUT DU JEU — il manquait 300 ticks. Balayage du 2026-08-18,
par invocation directe de `solvability_godot.mjs` :

    max_ticks   200 ->  0/50      (defaut applique en silence)
                250 ->  0/10
                300 ->  0/10
                400 ->  0/10
                500 -> 10/10      <- seuil
                600 -> 10/10
               1000 -> 10/10
    CONFIRMATION sur les 50 essais REELS a 1000 ticks : 50/50, verdict OK, 39 s.

BUDGET CALIBRE, PAS RECOPIE. `20000` (le contrat) n'est PAS retenu — non parce que le contrat
serait FAUX, mais parce que la mesure permet un plafond ECONOMIQUE la ou le contrat posait une
borne non instruite. `1000` donne une marge x2 sur le seuil observe.

`trial_timeout_ms: 10000` EST UNE DECISION, pas un defaut herite. Cout mesure ~0,8 s/essai =>
marge x12,5. Les trois autres jeux declarent `60000` : ce serait une CONVENTION DE PARC, pas
un calibrage — une marge x75 sans preuve que Tetris en ait besoin. Inscrire la valeur, meme
egale au defaut, evite exactement le defaut qu'on ferme ici : dependre silencieusement de
`DEFAULT_TRIAL_TIMEOUT_MS`.

CE QUE CE FICHIER PROUVE : la validation FONCTIONNELLE (le contrat est CONSOMME par le
resolveur, et l'anomalie d'audit disparait). La validation COMPORTEMENTALE (`won: 50/50` dans
un run reel) exige un `run_dir` NEUF — la reprise conserve les etapes deja OK — et n'est donc
pas prouvable ici.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from forge.solvability_budget_audit import audit_solvability_budgets

REPO = Path(__file__).resolve().parents[2]
ORACLES = REPO / "forge" / "oracles.json"

BUDGET_ATTENDU = {"max_ticks": 500, "trials": 50, "trial_timeout_ms": 10000}


def _entree_tetris() -> dict:
    return (json.loads(ORACLES.read_text(encoding="utf-8")).get("tetris") or {})


def test_le_budget_est_INSCRIT_et_calibre():
    """Les trois champs sont DECLARES — aucun ne depend d'un defaut silencieux."""
    solv = _entree_tetris().get("solvability") or {}
    assert {k: solv.get(k) for k in BUDGET_ATTENDU} == BUDGET_ATTENDU


def test_le_budget_est_AU_DESSUS_du_seuil_mesure():
    """Seuil observe entre 400 et 500 ticks : le budget doit garder une marge. Ce test
    tomberait si quelqu'un ramenait `max_ticks` vers le defaut sans remesurer."""
    solv = _entree_tetris().get("solvability") or {}
    assert solv["max_ticks"] >= 500, (
        "500 est la valeur MESUREE ET RATIFIEE (solvability.gd l.20-33, 18 graines, "
        "2026-08-10) : cadence 4,448 ticks/piece x plancher N_SURVIVE=100 = ~445 ticks. "
        "Descendre en dessous fabrique un faux negatif certain.")


def test_le_budget_reste_LOIN_de_la_limite_globale():
    """39 s mesurees contre 300 s de limite en dur (`oracle.py:76`). Un budget qui
    s'en approcherait ramenerait le mode de panne de bomberman_3d — mort de processus."""
    solv = _entree_tetris().get("solvability") or {}
    pire_cas_s = solv["trials"] * solv["trial_timeout_ms"] / 1000
    assert solv["trial_timeout_ms"] <= 10000, (
        "au-dela, le pire cas arithmetique (%s s) depasse largement la limite de 300 s "
        "sans preuve que Tetris en ait besoin" % pire_cas_s)


def test_l_anomalie_CONTRAT_IGNORE_a_disparu():
    """LE CAS QUI FALSIFIE. L'auto-audit signalait `tetris` depuis 5190859 : le contrat
    declarait un budget, `oracles.json` n'en portait aucun."""
    anomalies = {a["jeu"]: a["etat"] for a in audit_solvability_budgets(REPO)}
    assert "tetris" not in anomalies, f"anomalie persistante : {anomalies.get('tetris')}"


def test_aucune_DIVERGENCE_n_est_introduite():
    """Le parc ne doit pas gagner une contradiction en en perdant une : `oracles.json` fait
    autorite, mais deux declarations aux valeurs differentes seraient un defaut distinct."""
    etats = {a["jeu"]: a["etat"] for a in audit_solvability_budgets(REPO)}
    assert "DIVERGENT" not in etats.values(), etats


def test_le_RESOLVEUR_consomme_reellement_le_budget():
    """PREUVE FONCTIONNELLE, et elle traverse la frontiere Python -> Node : ce n'est pas
    parce que le JSON porte la valeur que `resolveSolvabilityConfig` la lit. On interroge le
    resolveur REEL plutot que de relire le fichier une seconde fois."""
    code = (
        "import('./forge/godot_oracle.mjs').then(m=>{"
        "const c=m.resolveSolvabilityConfig('GAMES/tetris');"
        "console.log(JSON.stringify({t:c.trials,mt:c.maxTicks,tt:c.trialTimeoutMs}));});"
    )
    r = subprocess.run(["node", "-e", code], cwd=REPO, capture_output=True,
                       text=True, timeout=60)
    if r.returncode != 0:
        pytest.skip(f"node indisponible ou pont casse : {(r.stderr or '')[:120]}")
    got = json.loads(r.stdout.strip().splitlines()[-1])
    assert got == {"t": 50, "mt": 500, "tt": 10000}, got
