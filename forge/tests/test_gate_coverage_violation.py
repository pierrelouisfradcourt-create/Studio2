# -*- coding: utf-8 -*-
"""DECISION E, VARIANTE A (GO Pierre 2026-08-18) — PREUVE DIFFERENTIELLE.

`observable_coverage.violation` entre dans le statut de `s10s` ; `measured` n'y entre PAS.
Une violation DEMONTREE gate ; une part NON MESURABLE ne gate pas et continue de remonter
par l'objection signee (`_observable_facts`, P0-3).

MATRICE PROUVEE ICI — quatre experiences, pas une :

    etat                                  HEAD    avec E
    couverture saine                      OK      OK
    observable_coverage en violation      OK      FAIL     <- causalite du gate
    genre_coverage en violation           OK      OK       <- la scission n'a pas deborde
    observable + genre en violation       OK      FAIL     <- genre ne masque pas observable

La colonne HEAD est ce qui transforme ce fichier en FALSIFICATION DIFFERENTIELLE plutot
qu'en constat d'un etat rouge : sur HEAD, une violation demontree ne change RIEN — c'est
exactement ce qu'assertait le gardien historique.

POURQUOI UN SQUELETTE REEL (`GAMES/snake`) ET NON SYNTHETIQUE. Une premiere redaction de ce
fichier montait un squelette minimal a la `_standard_game` : il echouait deja sur
`line_states`, `placement` et `budget`, donc `s10s` valait FAIL QUOI QU'IL ARRIVE. Trois
tests « passaient » pour la mauvaise raison et deux echouaient pour une raison etrangere —
le fichier ne mesurait pas ce qu'il pretendait. `snake` est le seul squelette CONSTATE ou
les six facettes CORE sont vertes ET le budget mesure ET passe (recu proof5, 2026-08-18).

DEUX DEPENDANCES DU HARNAIS, decouvertes par un preflight qui a d'abord ECHOUE :
  · les 10 lignes observables de snake tirent TOUTES leur preuve du canal GODOT
    (`product_oracle_godot`), aucune du canal WEB. Degrader `product_oracle` est INERTE ;
  · `check_genre_coverage` relie bible et wiremap par les `id` (`genre_rules[].id` cite par
    `genre_refs`), JAMAIS par `applies_to_wiremap_line`. Muter ce dernier champ est INERTE.
Les deux mutations initiales visaient le mauvais bout : les quatre cas rendaient OK avec des
mutations sans effet — un faux succes. Corrigees, l'isolement est mesure : muter le genre ne
contamine pas l'observable, et reciproquement.

`catalog_brick_ids_snapshot` VIENT DU DRIVER, jamais recopie d'un recu. C'est un instantane
DIFFERENTIEL pris au demarrage : un `[]` signifierait « catalogue vide au depart », donc
« tout a ete depose pendant le run », et le budget echouerait — mesure, et faux. Le recopier
d'un recu le ferait dater.
"""
from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

import pytest

from forge.driver import ForgeDriver

REPO = Path(__file__).resolve().parents[2]
SNAKE = REPO / "GAMES" / "snake"
RECU_PROOF5 = REPO / "EVIDENCE/runs/snake_proof5_20260818/state.json"

pytestmark = pytest.mark.skipif(
    not (SNAKE.is_dir() and RECU_PROOF5.is_file()),
    reason="squelette REEL indisponible (GAMES/snake ou son recu proof5 absent du depot) — "
           "un test qui depend d'un artefact absent ne mesure pas le depot, il mesure un poste")


def _canaux() -> tuple[dict, dict]:
    """Les DEUX canaux, repris TELS QUELS du run reel : on rejoue la vue que le run a
    produite, on ne la fabrique pas."""
    d = json.loads(RECU_PROOF5.read_text(encoding="utf-8"))
    s10a = d["steps"]["s10a-oracle-code"]["detail"]
    return s10a.get("product_oracle") or {}, s10a.get("product_oracle_godot") or {}


def _copie_snake() -> Path:
    """Copie TEMPORAIRE : le depot n'est jamais modifie, meme pour degrader une bible."""
    t = Path(tempfile.mkdtemp()) / "snake"
    shutil.copytree(SNAKE, t,
                    ignore=shutil.ignore_patterns(".godot", "*.import", "04_ASSETS"))
    return t


def _casser_observable(godot: dict) -> dict:
    """Degrade un volet REELLEMENT reference par une ligne observable (canal GODOT)."""
    g = json.loads(json.dumps(godot))
    assert "core_boot" in g, "le volet de reference a disparu du recu"
    g["core_boot"].update({"status": "FAIL", "passed": False, "checked": True})
    return g


def _casser_genre(jeu: Path) -> None:
    """Renomme un `id` de la bible : la regle cesse d'etre citee par un `genre_refs`."""
    p = jeu / "01_DESIGN" / "genre_bible.json"
    g = json.loads(p.read_text(encoding="utf-8"))
    g["genre_rules"][0]["id"] = "genre.inexistante.jamais_citee"
    p.write_text(json.dumps(g), encoding="utf-8")


def _s10s(jeu: Path, godot: dict) -> dict:
    web, _ = _canaux()
    t = Path(tempfile.mkdtemp())
    d = ForgeDriver("snake", "r", run_dir=t / "run", profile="standard", game_dir=jeu,
                    key_file=t / "k.key", audit_path=t / "a.jsonl")
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": d._catalog_brick_ids_snapshot()}
    state["steps"]["s10a-oracle-code"]["detail"] = {
        "product_oracle": web, "product_oracle_godot": godot}
    d._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


# --- le squelette lui-meme : sans lui, les trois autres ne prouvent rien ----------------


def test_le_squelette_est_DEMONSTRATIF(tmp_path):
    """PRECONDITION. Si `s10s` ne vaut pas OK a l'etat sain, toute variation observee
    ensuite pourrait venir d'une facette etrangere — c'est le piege qui a invalide la
    premiere redaction de ce fichier."""
    _, godot = _canaux()
    pas = _s10s(_copie_snake(), godot)
    det = pas["detail"]
    for k in ("contract_completeness", "line_states", "placement", "index", "collisions"):
        assert det[k].get("passed") is True, k
    assert det["budget"].get("measured") is True and det["budget"].get("passed") is True
    assert pas["status"] == "OK"


# --- la matrice ------------------------------------------------------------------------


def test_couverture_SAINE_laisse_le_pas_OK(tmp_path):
    _, godot = _canaux()
    pas = _s10s(_copie_snake(), godot)
    assert pas["detail"]["observable_coverage"]["violation"] is False
    assert pas["status"] == "OK"


def test_une_VIOLATION_observable_rend_le_pas_FAIL(tmp_path):
    """LE CAS QUI FALSIFIE. Sur HEAD ce pas vaut OK — c'est ce qu'assertait le gardien
    historique. Sous E il doit valoir FAIL : c'est la causalite du nouveau gate."""
    _, godot = _canaux()
    pas = _s10s(_copie_snake(), _casser_observable(godot))
    cov = pas["detail"]["observable_coverage"]
    assert cov["violation"] is True and cov["volets_en_echec"]
    assert pas["status"] == "FAIL"


def test_une_VIOLATION_genre_NE_gate_PAS(tmp_path):
    """La scission ne doit pas deborder : `genre_coverage` reste ADVISORY. Sans ce test, on
    aurait pu rendre bloquant un volet dont la politique n'a pas ete revoquee."""
    jeu = _copie_snake()
    _casser_genre(jeu)
    _, godot = _canaux()
    pas = _s10s(jeu, godot)
    assert pas["detail"]["genre_coverage"]["verdict"] == "FAIL"
    assert pas["detail"]["observable_coverage"]["violation"] is False, "isolement"
    assert pas["status"] == "OK"


def test_genre_en_violation_NE_MASQUE_PAS_une_violation_observable(tmp_path):
    """Les deux degrades ensemble : le FAIL doit venir de l'observable, et rien ne doit
    l'eteindre."""
    jeu = _copie_snake()
    _casser_genre(jeu)
    _, godot = _canaux()
    pas = _s10s(jeu, _casser_observable(godot))
    assert pas["detail"]["observable_coverage"]["violation"] is True
    assert pas["detail"]["genre_coverage"]["verdict"] == "FAIL"
    assert pas["status"] == "FAIL"
