# -*- coding: utf-8 -*-
"""Trois etats DISTINCTS dans le recu de couverture observable (GO Pierre 2026-08-17).

DEFAUT MESURE, et il est plus etroit que le cadrage initial ne le supposait. L'aplatissement
n'a PAS lieu dans `_CORE_FACETS` : il a lieu UNE ETAPE PLUS TOT, dans cette fonction meme --

    non_couvert = lignes_sans_preuve or volets_absents or volets_non_mesures or volets_en_echec
    verdict = "FAIL" if malforme else ("BLOCKED" if non_couvert else "OK")
    passed  = verdict == "OK"

Un `OU` reunit QUATRE categories que l'oracle a pourtant pris soin de separer. Un volet
HONNETEMENT NON MESURE produit donc le meme `passed: False` qu'un volet EN ECHEC, et tout
consommateur qui ne lit que `passed` herite de la confusion.

CAS REEL : `tetris`, run `proof3` (commit c19add3). Sa couverture est BLOCKED avec les TROIS
listes d'echec VIDES -- seul `volets_non_mesures` porte `core.render:core_render`, le volet qui
declare LUI-MEME, par le marqueur `requires_gpu_window`, ne pas pouvoir mesurer la preuve
pixel. Le volet le plus rigoureux du parc. Promouvoir `observable_coverage` en facette dure
(decision E) en ferait un ECHEC PRODUIT.

LE PATRON EXISTE DEJA, A QUATRE LIGNES DU PROBLEME. La facette `budget` de `driver.py` traite
exactement ce cas : `budget_measured` distingue « non mesure » de « mesure et rouge », et son
commentaire enonce la regle -- « un volet demontre en violation rend le pas FAIL, MEME si le
budget n'a pas pu etre mesure ; BLOCKED seulement si non mesurable ET qu'aucun autre volet n'a
echoue ». Ce lot etend ce patron, il n'en invente pas.

CE LOT NE TOUCHE PAS AU GATE. `passed` et `verdict` sont INCHANGES -- aucun consommateur n'est
affecte. Il expose seulement de quoi decider : `measured` et `violation`. Cabler cela dans
`_CORE_FACETS` EST la decision E, prise separement et pas ici.
"""
from __future__ import annotations

import json
from pathlib import Path

from forge.standard_oracles import check_observable_coverage

REPO = Path(__file__).resolve().parents[2]


def _wiremap(*lignes: str) -> dict:
    # Forme REELLE, verifiee contre le parseur : la cle est `lines` (pas `lignes`) et le nom
    # du volet vit dans `observable_proof` (pas dans un sous-objet `preuve`). Premiere
    # redaction de cette fixture : les deux etaient faux -> aucune ligne observable produite,
    # donc `passed: True` partout et des tests qui mesuraient le vide.
    return {"lines": [{"id": l, "observable_by_player": True,
                       "observable_proof": l.replace(".", "_")} for l in lignes]}


def _recu(**volets) -> dict:
    return {k: v for k, v in volets.items()}


# --- les deux champs neufs -------------------------------------------------------------


def test_tout_couvert_est_MESURE_et_sans_violation():
    wm = _wiremap("core.a")
    r = check_observable_coverage(wm, _recu(core_a={"status": "OK", "passed": True}))
    assert r["passed"] is True
    assert r["measured"] is True
    assert r["violation"] is False


def test_un_volet_EN_ECHEC_est_MESURE_et_en_violation():
    """« mesure et rouge » : on SAIT que c'est faux. Doit rester bloquant sous E."""
    wm = _wiremap("core.a")
    r = check_observable_coverage(wm, _recu(core_a={"status": "FAIL", "passed": False}))
    assert r["measured"] is True, "un echec est une MESURE, pas une absence de mesure"
    assert r["violation"] is True
    assert r["volets_en_echec"] == ["core.a:core_a"]


def test_un_volet_NON_MESURE_n_est_PAS_une_violation():
    """LE CAS QUI FALSIFIE, et le cas tetris. Un volet qui declare ne pas pouvoir mesurer
    n'affirme RIEN sur le produit -- il ne doit jamais devenir un echec par agregation."""
    wm = _wiremap("core.render")
    r = check_observable_coverage(wm, _recu(core_render={"status": "NOT_MEASURED",
                                                        "passed": False}))
    assert r["measured"] is False
    assert r["violation"] is False, "preuve impossible != preuve negative"
    assert r["volets_non_mesures"] == ["core.render:core_render"]
    assert r["verdict"] == "BLOCKED"


def test_une_VIOLATION_survit_a_un_volet_non_mesure_a_cote():
    """Regle du patron `budget`, mot pour mot : un volet demontre en violation rend le pas
    FAIL MEME si un autre n'a pas pu etre mesure. Sinon un seul volet non mesurable
    suffirait a masquer un vrai rouge."""
    wm = _wiremap("core.a", "core.render")
    r = check_observable_coverage(wm, _recu(
        core_a={"status": "FAIL", "passed": False},
        core_render={"status": "NOT_MEASURED", "passed": False}))
    assert r["violation"] is True, "un rouge reel ne doit JAMAIS etre masque"
    assert r["measured"] is False, "et l'on dit AUSSI qu'une part n'a pas pu etre mesuree"


def test_un_volet_ABSENT_est_une_VIOLATION_de_declaration():
    """La wiremap declare une preuve qui n'existe pas : c'est un defaut DEMONTRABLE, pas une
    impossibilite de mesure."""
    wm = _wiremap("core.a")
    r = check_observable_coverage(wm, _recu())
    assert r["violation"] is True
    assert r["volets_absents"] == ["core.a:core_a"]


def test_observable_malforme_reste_FAIL_et_non_BLOCKED():
    """VIGILANCE : une ligne mal formee est un defaut de DECLARATION, pas une preuve absente.
    Cette distinction etait deja juste avant ce lot ; elle ne doit pas etre emportee."""
    wm = {"lines": [{"id": "core.a", "observable_by_player": "oui-mais-pas-un-bool"}]}
    r = check_observable_coverage(wm, _recu())
    assert r["verdict"] == "FAIL"
    assert r["violation"] is True


# --- ce que le lot NE change PAS --------------------------------------------------------


def test_passed_et_verdict_sont_INCHANGES():
    """Aucun consommateur n'est affecte : `passed` reste `verdict == OK`, et les 4 listes
    gardent leur contenu. Le lot AJOUTE, il ne redefinit pas."""
    wm = _wiremap("core.render")
    r = check_observable_coverage(wm, _recu(core_render={"status": "NOT_MEASURED",
                                                         "passed": False}))
    assert r["passed"] is False and r["verdict"] == "BLOCKED"
    assert set(r) >= {"passed", "verdict", "observable_malformes", "lignes_sans_preuve",
                      "volets_absents", "volets_non_mesures", "volets_en_echec", "couvertes"}


# --- le cas reel -----------------------------------------------------------------------


def test_sur_le_RECU_REEL_de_tetris_la_distinction_change_le_verdict_de_E():
    """Cas REEL, pas une fixture : le recu commite de tetris (c19add3). C'est LUI qui rend la
    decision E prematuree -- BLOCKED sans aucune violation demontree."""
    p = REPO / "EVIDENCE/runs/tetris_proof3_20260817/state.json"
    if not p.is_file():
        import pytest
        pytest.skip("run tetris_proof3 absent du depot")
    cov = (json.loads(p.read_text(encoding="utf-8"))["steps"]["s10s-oracle-standard"]
           .get("detail") or {}).get("observable_coverage") or {}
    assert cov["verdict"] == "BLOCKED" and cov["passed"] is False
    assert cov["volets_non_mesures"] == ["core.render:core_render"]
    assert cov["volets_en_echec"] == [] and cov["volets_absents"] == []
    assert cov["lignes_sans_preuve"] == []
