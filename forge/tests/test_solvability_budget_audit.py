# SIGNAL DE CONTRADICTION contrat <-> oracles.json sur le budget de solvabilite
# (GO Pierre 2026-08-17). RAPPORTE, ne repare rien, ne gate rien.
#
# DEFAUT MESURE : le budget EFFECTIF de la solvabilite est lu par `godot_oracle.mjs` dans
# `forge/oracles.json`. Le bloc `proof.solvability` du contrat de jeu, lui, n'est lu
# que pour son champ `entry` (cablage, `check_solvability_wired`) : `trials`, `max_ticks` et
# `trial_timeout_ms` n'y ont AUCUN lecteur. Ce n'est donc pas « un declarant sans lecteur »
# mais une DECLARATION PARTIELLEMENT LUE — un champ consomme sur quatre, sans qu'aucun signal
# ne distingue les deux categories. Plus insidieux qu'une inertie totale : la presence d'un
# consommateur donne l'impression que tout le bloc compte.
#
# CAS REEL, mesure le 2026-08-17 sur les 6 jeux du depot : TETRIS declare
# `max_ticks: 20000, trial_timeout_ms: 60000` a son contrat et tourne a `200 / 10000` — les
# valeurs PAR DEFAUT — parce qu'il n'a aucune entree `solvability` dans `oracles.json`. Son
# contrat n'a jamais eu la moindre chance d'agir, et rien ne le disait.
#
# LE RISQUE N'EST PAS SEULEMENT TETRIS : trois jeux (snake, breakout_v2, bomberman_3d) sont
# COHERENTS parce que quelqu'un a maintenu DEUX fichiers a la main. Rien ne garantit qu'ils
# le restent, et rien ne le dirait.
#
# PAC-MAN N'EST PAS UNE ANOMALIE, et c'est une decision de cadrage : declarer en
# `oracles.json` SANS bloc au contrat est le regime normal d'un jeu sans descripteur `proof`.
# Le classer en anomalie creerait un faux positif PERMANENT. L'audit ne signale que la
# direction inverse — le contrat declare, l'oracle ignore.
from __future__ import annotations

import json
from pathlib import Path

from forge.solvability_budget_audit import audit_solvability_budgets

REPO = Path(__file__).resolve().parents[2]


def _jeu(root: Path, nom: str, contrat: dict | None) -> None:
    d = root / "GAMES" / nom / "00_CHARTER"
    d.mkdir(parents=True, exist_ok=True)
    if contrat is None:
        return
    lignes = ["proof:", "  solvability:"]
    for k, v in contrat.items():
        lignes.append(f"    {k}: {v}")
    (d / "game_contract.yaml").write_text("\n".join(lignes) + "\n", encoding="utf-8")


def _oracles(root: Path, mapping: dict) -> Path:
    p = root / "forge" / "oracles.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(mapping), encoding="utf-8")
    return p


def _etats(res: list[dict]) -> dict[str, str]:
    return {e["jeu"]: e["etat"] for e in res}


def test_contrat_IGNORE_est_signale(tmp_path):
    """LE CAS REEL (tetris) : le contrat declare un budget, `oracles.json` n'a pas d'entree
    -> les valeurs PAR DEFAUT s'appliquent, en silence."""
    _jeu(tmp_path, "t", {"trials": 50, "max_ticks": 20000, "trial_timeout_ms": 60000})
    _oracles(tmp_path, {"t": {}})
    res = audit_solvability_budgets(tmp_path)
    assert _etats(res) == {"t": "CONTRAT_IGNORE"}
    assert res[0]["contrat"]["max_ticks"] == 20000
    assert res[0]["oracles_json"] == {}


def test_valeurs_DIVERGENTES_sont_signalees_a_part(tmp_path):
    """Etat DISTINCT de `CONTRAT_IGNORE` : ici deux mainteneurs se contredisent, ce n'est pas
    un oubli d'entree. Meme gravite non presumee, mais jamais confondus."""
    _jeu(tmp_path, "t", {"trials": 50, "max_ticks": 20000})
    _oracles(tmp_path, {"t": {"solvability": {"trials": 50, "max_ticks": 999}}})
    res = audit_solvability_budgets(tmp_path)
    assert _etats(res) == {"t": "DIVERGENT"}
    assert res[0]["champs_divergents"] == ["max_ticks"]


def test_un_parc_COHERENT_ne_signale_RIEN(tmp_path):
    """Contre-epreuve : un signal qui se declenche toujours ne vaut rien."""
    b = {"trials": 50, "max_ticks": 5000, "trial_timeout_ms": 60000}
    _jeu(tmp_path, "a", b)
    _oracles(tmp_path, {"a": {"solvability": dict(b)}})
    assert audit_solvability_budgets(tmp_path) == []


def test_oracles_json_SEUL_n_est_PAS_une_anomalie(tmp_path):
    """Decision de cadrage : c'est le regime normal d'un jeu sans descripteur `proof`.
    Le signaler creerait un faux positif PERMANENT (cas pacman)."""
    _jeu(tmp_path, "p", None)
    _oracles(tmp_path, {"p": {"solvability": {"trials": 50, "max_ticks": 20000}}})
    assert audit_solvability_budgets(tmp_path) == []


def test_aucune_declaration_nulle_part_est_muet(tmp_path):
    """Cas pong : rien des deux cotes, rien a dire."""
    _jeu(tmp_path, "g", None)
    _oracles(tmp_path, {})
    assert audit_solvability_budgets(tmp_path) == []


def test_le_champ_entry_N_EST_PAS_un_budget(tmp_path):
    """`entry` est le SEUL champ du bloc qui ait un lecteur (`check_solvability_wired`).
    Il ne doit jamais compter comme une declaration de budget, sinon tout jeu cablé
    deviendrait un faux positif."""
    _jeu(tmp_path, "t", {"entry": "07_TESTS/oracle/solvability.gd"})
    _oracles(tmp_path, {"t": {}})
    assert audit_solvability_budgets(tmp_path) == []


def test_un_contrat_ILLISIBLE_ne_casse_PAS_l_audit(tmp_path):
    """Best-effort strict, meme discipline que `registryDivergences` : un fichier casse
    devient un etat NOMME, jamais une exception qui interrompt l'audit."""
    d = tmp_path / "GAMES" / "k" / "00_CHARTER"
    d.mkdir(parents=True)
    (d / "game_contract.yaml").write_text("proof: [ceci n'est pas: du yaml valide\n",
                                          encoding="utf-8")
    _oracles(tmp_path, {})
    res = audit_solvability_budgets(tmp_path)
    assert _etats(res) == {"k": "NON_EVALUABLE"}


def test_oracles_json_ABSENT_ne_casse_PAS_l_audit(tmp_path):
    _jeu(tmp_path, "t", {"max_ticks": 20000})
    res = audit_solvability_budgets(tmp_path)
    assert _etats(res) == {"t": "NON_EVALUABLE"}


def test_sur_le_depot_REEL_le_parc_est_SANS_anomalie():
    """Cas REEL, pas une fixture.

    HISTORIQUE, et le test a fait ce qu'il annoncait. Redige le 2026-08-17, il assertait
    `ignores == ["tetris"]` — le seul jeu du parc dont le contrat declarait un budget que
    `oracles.json` ignorait. Sa docstring prevenait : « si ce test devient rouge, c'est que
    le parc a change, pas que l'audit s'est casse ». Il est devenu rouge le 2026-08-18,
    exactement pour cette raison : le budget de tetris a ete INSCRIT (`max_ticks: 500`, la
    valeur mesuree et ratifiee du 2026-08-10) et le contrat de jeu ALIGNE sur elle.

    Il garde desormais l'etat ATTEINT plutot que l'anomalie d'alors : aucun contrat ignore,
    aucune divergence. Un nouveau jeu qui declarerait un budget sans entree dans
    `oracles.json` le ferait rougir — c'est le meme service, rendu depuis l'autre bord."""
    res = audit_solvability_budgets(REPO)
    assert [e["jeu"] for e in res if e["etat"] == "CONTRAT_IGNORE"] == [], res
    assert [e["jeu"] for e in res if e["etat"] == "DIVERGENT"] == [], res
