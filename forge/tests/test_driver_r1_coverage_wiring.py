"""Câblage driver des 2 volets de preuve de boucle (R1, contrat
`r1-preuves-boucle-mecaniques.yaml`, 2026-07-27) — `ForgeDriver._run_standard_oracle`
porte `check_observable_coverage`/`check_genre_coverage` dans
`detail["observable_coverage"]`/`detail["genre_coverage"]`, ADVISORY : ni l'un ni
l'autre ne participe au calcul du statut du pas `s10s-oracle-standard` (même patron
que `product_oracle` dans `_run_code_oracle`, s10a — cf. `test_driver_product_oracle.py`).

Ce fichier vérifie UNIQUEMENT le CÂBLAGE : que le driver (a) lit le reçu `product_oracle`
déjà posé par s10a (persisté dans l'état, jamais recalculé), (b) lit `01_DESIGN/genre_bible.json`
depuis `game_dir`, (c) porte les deux résultats dans le reçu de s10s, (d) ne les fait
JAMAIS gager le statut du pas. La couverture RED/GREEN des fonctions elles-mêmes vit
dans `test_standard_oracles_r1_coverage.py`.
"""
import json

import yaml

from forge.driver import ForgeDriver


def _standard_game(root, *, observable_proof="auto_session", genre_refs=None):
    """Squelette STANDARD minimal accepté par les six oracles historiques (au
    placement près, non regardé ici) + une ligne observable et une Genre Bible
    machine-lisible, à l'image de Pong."""
    (root / "00_CHARTER").mkdir(parents=True)
    (root / "00_CHARTER" / "game_contract.yaml").write_text(
        yaml.safe_dump({"schema_version": 1, "game_id": "g", "node": 1,
                        "runtimes": ["rules"], "budget": {"reuses": [], "adds": []},
                        "assets": {"plan": "cc0"}}), encoding="utf-8")
    (root / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    (root / "05_SYSTEMS" / "game_loop" / "loop.mjs").write_text("export const t=1;\n",
                                                                encoding="utf-8")
    (root / "09_WIREMAP").mkdir(parents=True)
    (root / "09_WIREMAP" / "wiremap.json").write_text(json.dumps({
        "schema_version": 2,
        "lines": [{
            "id": "core.boot", "category": "system", "provides": ["game.boot"],
            "requires": [], "owner": True, "state": "IMPLEMENTED",
            "address": "05_SYSTEMS/game_loop/",
            "observable_by_player": True,
            "observable_proof": observable_proof,
            "genre_refs": genre_refs or ["genre.g.some_rule"],
            "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}],
        }],
        "genre_refusals": [],
    }), encoding="utf-8")
    (root / "01_DESIGN").mkdir(parents=True)
    (root / "01_DESIGN" / "genre_bible.json").write_text(json.dumps({
        "genre_rules": [{"id": "genre.g.some_rule", "applies_to_wiremap_line": "core.boot"}],
    }), encoding="utf-8")
    return root


def _run_standard_step(tmp_path, game_dir, *, product_oracle_detail=None):
    d = ForgeDriver("g", "r1", run_dir=tmp_path / "run", profile="standard",
                    game_dir=game_dir, key_file=tmp_path / "k.key",
                    audit_path=tmp_path / "audit.jsonl")
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    # s10a s'exécute AVANT s10s dans l'ORDER du profil standard — son reçu (déjà
    # persisté) est ce que s10s doit lire, jamais recalculer.
    if product_oracle_detail is not None:
        state["steps"]["s10a-oracle-code"]["detail"] = {"product_oracle": product_oracle_detail}
    d._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


# --- câblage : les deux volets sont posés dans le reçu -------------------------------


def test_les_deux_volets_sont_portes_dans_le_recu(tmp_path):
    game = _standard_game(tmp_path / "game")
    entry = _run_standard_step(tmp_path, game, product_oracle_detail={
        "auto_session": {"passed": True, "checked": True},
    })
    assert "observable_coverage" in entry["detail"]
    assert "genre_coverage" in entry["detail"]
    assert entry["detail"]["observable_coverage"]["verdict"] == "OK"
    assert entry["detail"]["genre_coverage"]["verdict"] == "OK"


def test_genre_bible_absente_rend_genre_coverage_fail_motive_sans_crash(tmp_path):
    game = _standard_game(tmp_path / "game")
    (game / "01_DESIGN" / "genre_bible.json").unlink()
    entry = _run_standard_step(tmp_path, game, product_oracle_detail={
        "auto_session": {"passed": True, "checked": True},
    })
    assert entry["detail"]["genre_coverage"]["verdict"] == "FAIL"
    assert entry["detail"]["genre_coverage"]["passed"] is False


def test_product_oracle_absent_rend_observable_coverage_bloque_sans_crash(tmp_path):
    """s10a n'a pas encore tourné (ou n'a rien produit pour product_oracle) : le
    reçu combiné est vide, la ligne observable reste non couverte (BLOCKED), jamais
    une exception."""
    game = _standard_game(tmp_path / "game")
    entry = _run_standard_step(tmp_path, game, product_oracle_detail=None)
    cov = entry["detail"]["observable_coverage"]
    assert cov["verdict"] == "BLOCKED"
    assert cov["volets_absents"] == ["core.boot:auto_session"]


# --- POLITIQUE DE GATE : REVOQUEE pour `observable_coverage`, MAINTENUE pour `genre` ---
#
# REVOCATION (decision E variante A, GO Pierre 2026-08-18). Ce fichier assertait que NI
# `observable_coverage` NI `genre_coverage` ne font varier le statut du pas. C'est desormais
# FAUX pour le premier : une violation DEMONTREE de la couverture observable gate. La preuve
# differentielle vit dans `test_gate_coverage_violation.py` (4 experiences, colonne HEAD
# incluse) ; ici on conserve la moitie qui reste vraie.
#
# SQUELETTE BASCULE SUR `GAMES/snake`, et c'est le coeur du changement. Les tests precedents
# s'appuyaient sur `_standard_game`, dont la mesure du 2026-08-18 montre qu'il echoue sur
# `line_states` (core_omis), `placement` (adresse incoherente) et `budget` (28 briques hors
# budget faute d'instantane) : `s10s` y vaut FAIL DES DEUX COTES. Leur assertion
# `entry_ok["status"] == entry_red["status"]` etait donc satisfaite par un `FAIL == FAIL`
# INDEPENDANT de ce qu'elle pretendait mesurer — un faux vert, qui aurait survecu a la
# revocation sans rien prouver. `snake` est le seul squelette CONSTATE ou les six facettes
# CORE sont vertes ET le budget mesure ET passe.
#
# PRIX ASSUME : ces deux tests dependent desormais d'un jeu du depot. Ils SAUTENT, avec motif
# nomme, s'il est absent — un test qui depend d'un artefact absent mesure un poste, pas un
# depot. Les six tests de CABLAGE ci-dessus gardent `_standard_game` : ils n'ont besoin
# d'aucune facette verte, et les migrer aurait deplace le piege d'une couche.
import shutil
import tempfile
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SNAKE = REPO / "GAMES" / "snake"
RECU_PROOF5 = REPO / "EVIDENCE/runs/snake_proof5_20260818/state.json"

_SNAKE_DISPO = SNAKE.is_dir() and RECU_PROOF5.is_file()
_MOTIF_SAUT = ("squelette REEL indisponible (GAMES/snake ou son recu proof5 absent) — "
               "un test qui depend d'un artefact absent ne mesure pas le depot")


def _canaux_snake():
    d = json.loads(RECU_PROOF5.read_text(encoding="utf-8"))
    s10a = d["steps"]["s10a-oracle-code"]["detail"]
    return s10a.get("product_oracle") or {}, s10a.get("product_oracle_godot") or {}


def _copie_snake():
    t = Path(tempfile.mkdtemp()) / "snake"
    shutil.copytree(SNAKE, t,
                    ignore=shutil.ignore_patterns(".godot", "*.import", "04_ASSETS"))
    return t


def _s10s_snake(jeu, *, godot=None):
    web, godot_reel = _canaux_snake()
    t = Path(tempfile.mkdtemp())
    d = ForgeDriver("snake", "r", run_dir=t / "run", profile="standard", game_dir=jeu,
                    key_file=t / "k.key", audit_path=t / "a.jsonl")
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             # Instantane DIFFERENTIEL pris depuis le driver, jamais recopie d'un recu :
             # un `[]` signifierait « catalogue vide au depart » et ferait echouer le budget.
             "catalog_brick_ids_snapshot": d._catalog_brick_ids_snapshot()}
    state["steps"]["s10a-oracle-code"]["detail"] = {
        "product_oracle": web, "product_oracle_godot": godot or godot_reel}
    d._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


@pytest.mark.skipif(not _SNAKE_DISPO, reason=_MOTIF_SAUT)
def test_genre_coverage_rouge_ne_gate_TOUJOURS_pas_le_pas(tmp_path):
    """MOITIE CONSERVEE du gardien historique. La politique de `genre_coverage` n'a PAS ete
    revoquee : il reste ADVISORY. Sur un squelette DEMONSTRATIF (statut OK a l'etat sain),
    le degrader ne doit rien changer — ce que l'ancien squelette ne pouvait pas montrer."""
    jeu = _copie_snake()
    bible = jeu / "01_DESIGN" / "genre_bible.json"
    g = json.loads(bible.read_text(encoding="utf-8"))
    g["genre_rules"][0]["id"] = "genre.inexistante.jamais_citee"
    bible.write_text(json.dumps(g), encoding="utf-8")

    entry = _s10s_snake(jeu)
    assert entry["detail"]["genre_coverage"]["verdict"] == "FAIL"
    assert entry["detail"]["observable_coverage"]["violation"] is False, "isolement"
    assert entry["status"] == "OK", "genre_coverage ne gate pas — politique inchangee"


@pytest.mark.skipif(not _SNAKE_DISPO, reason=_MOTIF_SAUT)
def test_le_squelette_snake_est_DEMONSTRATIF(tmp_path):
    """PRECONDITION du test ci-dessus. Sans elle, un `status == OK` pourrait venir d'ailleurs
    — et sans elle, l'ancien gardien passait sur un `FAIL == FAIL` qui ne prouvait rien."""
    entry = _s10s_snake(_copie_snake())
    for k in ("contract_completeness", "line_states", "placement", "index", "collisions"):
        assert entry["detail"][k].get("passed") is True, k
    assert entry["detail"]["budget"].get("measured") is True
    assert entry["detail"]["budget"].get("passed") is True
    assert entry["status"] == "OK"
