"""Canaris des oracles statiques — des violations qui DOIVENT sortir ROUGE.

Chaque cas est un faux-négatif confirmé par red-team (exécuté). Le rôle de cette
suite : figer les corrections et transformer tout futur faux-négatif de la même
CLASSE (« l'oracle croit voir mais ne voit pas ») en régression détectée, au lieu
d'un trou silencieux découvert par un attaquant.
"""
import os
import tempfile

from forge.static_oracles import check_architecture, check_wiremap

_BP_UI_NOT_ENGINE = {"modules": ["ui", "engine"], "deps_interdites": [["ui", "engine"]]}


def _tree(files: dict) -> str:
    d = tempfile.mkdtemp()
    for rel, content in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(content)
    return d


# --- CRITICAL-2.1 : import Rust groupé ----------------------------------------

def test_canary_rust_grouped_use_is_caught():
    d = _tree({"ui/view.rs": "use crate::{engine, util};\nfn render(){}\n",
               "engine/board.rs": "pub fn make(){}\n"})
    r = check_architecture(_BP_UI_NOT_ENGINE, d)
    assert r["passed"] is False, "use crate::{engine} groupé doit être attrapé"
    assert ["ui", "engine"] in r["deps_interdites_violées"]


def test_canary_rust_nested_grouped_use_is_caught():
    d = _tree({"ui/view.rs": "use crate::{engine::board, util::log};\nfn render(){}\n",
               "engine/board.rs": "pub fn make(){}\n"})
    r = check_architecture(_BP_UI_NOT_ENGINE, d)
    assert r["passed"] is False
    assert ["ui", "engine"] in r["deps_interdites_violées"]


# --- CRITICAL-2.2 : import Python relatif -------------------------------------

def test_canary_python_relative_import_is_caught():
    d = _tree({"ui/panel.py": "from ..engine import Board\n",
               "engine/board.py": "class Board: pass\n"})
    r = check_architecture(_BP_UI_NOT_ENGINE, d)
    assert r["passed"] is False, "from ..engine doit être attrapé"
    assert ["ui", "engine"] in r["deps_interdites_violées"]


# --- CRITICAL-2.3 : feature WireMap sans fichier ------------------------------

def test_canary_wiremap_feature_without_files_fails():
    wm = {"features": [{"feature": "Neural eval", "fonction": "evaluate_nn",
                        "preuve": "trust me bro", "fichiers": []}]}
    r = check_wiremap(wm, _tree({}))
    assert r["passed"] is False, "une feature sans fichier ne peut pas être prouvée verte"
    assert "Neural eval" in r["features_manquantes"]


# --- RED-TEAM #2 : import dynamique TS (faux POSITIF d'archi) ------------------

def test_canary_ts_dynamic_import_is_caught():
    d = _tree({"ui/panel.ts": "export async function render(){ const e = await import('../engine/core'); return e.tick(); }\n",
               "engine/core.ts": "export function tick(){}\n"})
    r = check_architecture(_BP_UI_NOT_ENGINE, d)
    assert r["passed"] is False, "await import('../engine/...') doit être attrapé"
    assert ["ui", "engine"] in r["deps_interdites_violées"]


# --- RED-TEAM #2 : méthodes de classe (faux NÉGATIF wiremap = B4) --------------

def test_canary_ts_class_method_is_found():
    d = _tree({"game/game.mjs": "export class G {\n  step(dt, input) { return dt; }\n  collectCoin() { return 1; }\n}\n"})
    wm = {"features": [
        {"feature": "avance", "fonction": "step", "fichiers": ["game/game.mjs"], "preuve": "x"},
        {"feature": "collecte", "fonction": "collectCoin", "fichiers": ["game/game.mjs"], "preuve": "y"},
    ]}
    r = check_wiremap(wm, d)
    assert r["passed"] is True, "les méthodes de classe step/collectCoin doivent être trouvées"
    assert r["fonctions_renommées"] == []


# --- honnêteté du stub ownership ----------------------------------------------

def test_ownership_stub_is_marked_not_checked():
    d = _tree({"ui/view.py": "def render():\n    return 1\n"})
    r = check_architecture(_BP_UI_NOT_ENGINE, d)
    # Un stub ne doit pas avoir la même forme qu'un vrai résultat vide : il se déclare.
    assert r["debordements_ownership"]["checked"] is False
