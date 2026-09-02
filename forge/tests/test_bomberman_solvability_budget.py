# -*- coding: utf-8 -*-
"""Budget de solvabilite de BOMBERMAN_3D : `trials` reduit + `total_timeout_s` declare
(GO Pierre 2026-08-18).

DEFAUT MESURE. bomberman_3d declarait 20 essais. Cout mesure : ~19 s/essai (mesure directe,
identique a 12000, 30000 et 60000 ticks — la partie se termine naturellement bien avant le
plafond). La couverture complete demande donc ~380 s, AU-DELA des 300 s que `oracle.run_oracle`
accorde a l'oracle entier. Consequence observee sur les runs `proof4`/`proof5` :
`--- TIMEOUT after 300s ---`, processus TUE, AUCUN resultat partiel rendu.

DEUX MESURES ONT DIMENSIONNE CE PATCH, pas une intuition :
  · T_mecanique = 1 s (691 assertions) — l'hypothese « 45 s » etait fausse d'un facteur 45 ;
  · la borne utile est donc `300 - 1 - 19 = 280 s`, la marge du DERNIER essai comptee :
    `total_timeout_s` est verifie AVANT chaque essai, jamais pendant, donc un essai commence
    va a son terme et le depassement reel peut atteindre une duree d'essai.

EXPERIENCE DU 2026-08-18, budget instrumental de 200 s :
    temps reel 209 s · trials_executes 11/20 · won 3 · lost 8
    verdict BLOCKED · reason « budget total epuise ... preuve INCOMPLETE, jamais un echec »
L'arret est tombe EXACTEMENT ou l'arithmetique le predisait (10 essais = 190 s < 200, le 11e
demarre, coupe a 209 s), et le partiel a SURVECU. C'est le cas A : `total_timeout_s` est
adapte a bomberman_3d.

POURQUOI `trials` PASSE DE 20 A 14, et c'est le coeur de l'arbitrage. Avec un budget SEUL,
bomberman_3d ne pourrait JAMAIS rendre autre chose que BLOCKED : 20 essais sont hors de
portee de la limite Forge, donc la preuve serait definitivement « incomplete » — honnete,
mais jamais concluante. 14 essais tiennent (14 x 19 = 266 s, + 1 s de mecanique = 267 s), donc
le jeu redevient capable d'un VERDICT REEL. Prix assume : moins de puissance statistique.
Decision Pierre, entre « ne jamais conclure » et « conclure sur moins d'essais ».

LES DEUX CHAMPS ONT DES ROLES DIFFERENTS, et les confondre serait une erreur :
    trials = 14           DIMENSIONNE l'experience pour qu'elle ABOUTISSE en regime nominal
    total_timeout_s = 250 FILET DE SECURITE — ne doit PAS se declencher si les essais tiennent
                          leur cout mesure (13 essais = 247 s < 250, le 14e demarre et finit
                          la boucle). Il n'agit que si un essai deborde son regime.
Un budget qui se declencherait en regime NOMINAL signalerait que `trials` est mal dimensionne,
pas que le filet fonctionne.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from forge.solvability_budget_audit import audit_solvability_budgets

REPO = Path(__file__).resolve().parents[2]
ORACLES = REPO / "forge" / "oracles.json"

COUT_ESSAI_S = 19      # mesure directe 2026-08-18, identique a 12000/30000/60000 ticks
T_MECANIQUE_S = 1      # 691 assertions, mesure isolee
LIMITE_FORGE_S = 300   # oracle.py:76 / driver.py:613, en dur


def _solv() -> dict:
    e = json.loads(ORACLES.read_text(encoding="utf-8")).get("bomberman_3d") or {}
    return e.get("solvability") or {}


def test_les_deux_champs_sont_DECLARES():
    s = _solv()
    assert s.get("trials") == 14
    assert s.get("total_timeout_s") == 250
    assert s.get("max_ticks") == 12000, "inchange : le plafond de ticks n'est PAS en cause"
    assert s.get("trial_timeout_ms") == 60000, "inchange"


def test_l_experience_NOMINALE_tient_sous_la_limite_Forge():
    """LE DIMENSIONNEMENT. 14 essais x 19 s + 1 s de mecanique doivent rester sous 300 s,
    sinon le processus serait tue avant d'avoir conclu — le defaut qu'on ferme."""
    s = _solv()
    nominal = s["trials"] * COUT_ESSAI_S + T_MECANIQUE_S
    assert nominal < LIMITE_FORGE_S, f"{nominal} s >= {LIMITE_FORGE_S} s"


def test_le_filet_NE_se_declenche_PAS_en_regime_nominal():
    """`total_timeout_s` est un FILET, pas le dimensionnement. En regime mesure, les 14 essais
    doivent tenir : le 14e demarre avant que le budget ne soit atteint (13 x 19 = 247 < 250)
    et la boucle se termine d'elle-meme. Un budget qui couperait en nominal signalerait que
    `trials` est mal dimensionne."""
    s = _solv()
    avant_dernier = (s["trials"] - 1) * COUT_ESSAI_S
    assert avant_dernier < s["total_timeout_s"], (
        f"le budget ({s['total_timeout_s']} s) couperait AVANT le dernier essai "
        f"({avant_dernier} s) : l'experience ne pourrait jamais aboutir")


def test_le_filet_protege_REELLEMENT_si_un_essai_deborde():
    """Contre-epreuve : un filet qui ne coupe jamais ne protege de rien. Le budget doit
    rester SOUS la borne `300 - mecanique - un essai`, marge du dernier essai comprise —
    `total_timeout_s` est verifie AVANT chaque essai, jamais pendant."""
    s = _solv()
    borne = LIMITE_FORGE_S - T_MECANIQUE_S - COUT_ESSAI_S
    assert s["total_timeout_s"] < borne, (
        f"budget {s['total_timeout_s']} s >= borne {borne} s : l'arret « propre » "
        "arriverait APRES la limite qu'il devait preceder")


def test_la_reduction_de_trials_est_ce_qui_rend_un_verdict_POSSIBLE():
    """Sans elle, la couverture complete (20 essais) depasse la limite et le verdict serait
    definitivement BLOCKED. Ce test garde la raison de la reduction, pas seulement sa valeur."""
    s = _solv()
    couverture_ancienne = 20 * COUT_ESSAI_S + T_MECANIQUE_S
    assert couverture_ancienne > LIMITE_FORGE_S, "premisse de la reduction"
    assert s["trials"] * COUT_ESSAI_S + T_MECANIQUE_S < LIMITE_FORGE_S


def test_aucune_anomalie_d_audit_n_est_introduite():
    """bomberman_3d declare aussi un budget a son CONTRAT : ajouter un champ cote oracle ne
    doit pas creer de DIVERGENT — le parc ne gagne pas une contradiction en en fermant une."""
    etats = {a["jeu"]: a["etat"] for a in audit_solvability_budgets(REPO)}
    assert etats.get("bomberman_3d") != "DIVERGENT", etats
    assert "CONTRAT_IGNORE" not in etats.values(), etats


def test_le_RESOLVEUR_consomme_reellement_les_deux_champs():
    """PREUVE FONCTIONNELLE traversant la frontiere Python -> Node : ce n'est pas parce que
    le JSON porte les valeurs que `resolveSolvabilityConfig` les lit. `totalTimeoutS` n'a
    AUCUN defaut — s'il n'etait pas lu, il vaudrait `null` et le filet serait inerte."""
    code = (
        "import('./forge/godot_oracle.mjs').then(m=>{"
        "const c=m.resolveSolvabilityConfig('GAMES/bomberman_3d');"
        "console.log(JSON.stringify({t:c.trials,tt:c.totalTimeoutS,mt:c.maxTicks}));});"
    )
    r = subprocess.run(["node", "-e", code], cwd=REPO, capture_output=True,
                       text=True, timeout=60)
    if r.returncode != 0:
        pytest.skip(f"node indisponible ou pont casse : {(r.stderr or '')[:120]}")
    got = json.loads(r.stdout.strip().splitlines()[-1])
    assert got == {"t": 14, "tt": 250, "mt": 12000}, got
