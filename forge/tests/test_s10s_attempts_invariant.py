"""Invariant : aucun statut `s10s-oracle-standard` ne peut être posé sans passer par
l'incrément d'`attempts` de la boucle driver (`ForgeDriver._run_deterministic`,
driver.py l.637).

Contexte (mission s10s-branchement-driver, 2026-07-26 — docs/forge/MISSION_S10S_DRIVER_DRAFT.md) :
`EVIDENCE/runs/pong/state.json` (archive, LECTURE SEULE) montre
`s10s-oracle-standard: status=FAIL, attempts=0` avec un `detail` RÉEL (six volets
mesurés, deux rouges — budget/placement) mais SANS que le compteur d'attempts ait
jamais tourné.

Diagnostic (établi par lecture du code + git log, avant tout Edit de ce fichier) :
  - `state.json` du run archive porte `ts=1784832466` pour l'entrée s10s, soit
    2026-07-23 18:47:46 UTC (`python -c "import datetime;
    print(datetime.datetime.utcfromtimestamp(1784832466))"`).
  - `git log --oneline --all -S"_run_standard_oracle" -- forge/driver.py`
    ne retourne qu'UN SEUL commit : 74f3dd0 (2026-07-23 20:56:46 +0200) — c'est
    l'unique introduction du branchement `_run_deterministic` -> `_run_standard_oracle`
    (driver.py:674-675) dans l'historique versionné. Son message ("Sauvegarde l'outillage
    Forge non commité depuis le 2026-07-21") confirme que le code tournait déjà EN
    WORKTREE, non commité, avant cette date.
  - Le reçu archivé (18:47:46) précède donc de ~2h ce commit (20:56:46) : il a été
    produit par une version DE TRAVAIL (non versionnée, donc non rejouable telle
    quelle) du branchement s10s, PAS par le code qui existe aujourd'hui.
  - Dans le code ACTUEL (driver.py), `_run_standard_oracle` n'a qu'un seul appelant :
    `_run_deterministic` (driver.py:675), qui incrémente `entry["attempts"]`
    (driver.py:637) INCONDITIONNELLEMENT avant tout branchement, et `_finish_step`
    (driver.py:1107) ne touche jamais `attempts`. Le chemin hors-boucle qui a produit
    l'archive n'existe donc plus tel quel — mais rien ne l'empêchait STRUCTURELLEMENT
    de réapparaître (un futur appelant direct de `_run_standard_oracle`, par exemple).

Correction minimale (ce fichier + driver.py) : `_run_standard_oracle` refuse
maintenant explicitement de s'exécuter sur une entrée `attempts < 1` — l'invariant
« pas de statut s10s sans incrément d'attempts » devient un fait du code, pas une
observation sur l'unique appelant actuel.
"""
import pytest

from forge.driver import ForgeDriver


def _fresh_standard_entry():
    return {"status": "PENDING", "attempts": 0}


def _driver(tmp_path):
    return ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        game_dir=tmp_path / "game", key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
    )


def test_run_standard_oracle_refuses_a_zero_attempts_entry(tmp_path):
    """RED sur l'ancien code (aucune garde) : appeler `_run_standard_oracle`
    directement — hors `_run_deterministic`, donc SANS incrément d'attempts,
    exactement le chemin hors-boucle qui a produit `pong/state.json`
    FAIL/attempts:0 — doit lever bruyamment, jamais poser un statut en silence."""
    d = _driver(tmp_path)
    state = {"steps": {"s10s-oracle-standard": _fresh_standard_entry()},
             "catalog_brick_ids_snapshot": []}
    entry = state["steps"]["s10s-oracle-standard"]
    with pytest.raises(RuntimeError, match="attempts"):
        d._run_standard_oracle(state, entry)
    # la garde lève AVANT toute écriture : le statut hors-boucle interdit reste absent
    assert entry["status"] == "PENDING"
    assert "detail" not in entry


def test_run_deterministic_path_is_unaffected_attempts_ge_1(tmp_path):
    """Le chemin légitime (`run()` -> `_run_deterministic`) n'est pas cassé par la
    garde : l'incrément a lieu AVANT le dispatch vers `_run_standard_oracle`, donc
    l'entrée y arrive toujours avec attempts>=1 — la garde ne s'y déclenche jamais,
    et le statut final est bien posé (jamais PENDING)."""
    d = _driver(tmp_path)
    state = {"steps": {e: {"status": "PENDING", "attempts": 0} for e in d.order},
             "catalog_brick_ids_snapshot": []}
    d._run_deterministic(state, "s10s-oracle-standard")
    entry = state["steps"]["s10s-oracle-standard"]
    assert entry["attempts"] >= 1
    assert entry["status"] in ("OK", "FAIL", "BLOCKED")
