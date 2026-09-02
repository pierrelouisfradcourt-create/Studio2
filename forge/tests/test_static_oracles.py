"""Oracles statiques déterministes (non-LLM) : ARCHI (s10b) + WIREMAP (s10c).

ARCHI : les imports réels du code ne violent aucune dépendance interdite du blueprint.
WIREMAP : chaque feature du tableau pointe une fonction qui existe vraiment (AST).
Aucun LLM. Reproductible.
"""
from forge.static_oracles import check_architecture, check_wiremap


def _write(root, rel, code):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(code, encoding="utf-8")


# --- ARCHI ---

def test_archi_detects_forbidden_dependency(tmp_path):
    _write(tmp_path, "ui/view.py", "import engine\n")
    _write(tmp_path, "engine/core.py", "x = 1\n")
    blueprint = {"modules": ["ui", "engine"], "deps_interdites": [["ui", "engine"]]}
    rep = check_architecture(blueprint, tmp_path)
    assert rep["passed"] is False
    assert ["ui", "engine"] in rep["deps_interdites_violées"]


def test_archi_passes_when_clean(tmp_path):
    _write(tmp_path, "ui/view.py", "import api\n")
    _write(tmp_path, "api/svc.py", "import engine\n")
    _write(tmp_path, "engine/core.py", "x = 1\n")
    blueprint = {"modules": ["ui", "api", "engine"], "deps_interdites": [["ui", "engine"]]}
    rep = check_architecture(blueprint, tmp_path)
    assert rep["passed"] is True
    assert rep["deps_interdites_violées"] == []


# --- WIREMAP ---

def test_wiremap_passes_when_function_exists(tmp_path):
    _write(tmp_path, "gameplay/moves.py", "def move_piece():\n    pass\n")
    wiremap = {"features": [
        {"feature": "déplacer", "fichiers": ["gameplay/moves.py"],
         "fonction": "move_piece", "preuve": "test_move", "statut": "fait"},
    ]}
    rep = check_wiremap(wiremap, tmp_path)
    assert rep["passed"] is True
    assert rep["features_manquantes"] == []
    assert rep["fonctions_renommées"] == []


def test_wiremap_flags_renamed_function(tmp_path):
    _write(tmp_path, "gameplay/moves.py", "def move_piece_v2():\n    pass\n")
    wiremap = {"features": [
        {"feature": "déplacer", "fichiers": ["gameplay/moves.py"],
         "fonction": "move_piece", "preuve": "test_move", "statut": "fait"},
    ]}
    rep = check_wiremap(wiremap, tmp_path)
    assert rep["passed"] is False
    assert "move_piece" in str(rep["fonctions_renommées"])


def test_wiremap_flags_missing_file_and_absent_proof(tmp_path):
    wiremap = {"features": [
        {"feature": "shop", "fichiers": ["shop/ui.py"], "fonction": "open_shop",
         "preuve": "", "statut": "fait"},
    ]}
    rep = check_wiremap(wiremap, tmp_path)
    assert rep["passed"] is False
    assert "shop/ui.py" in str(rep["obsoletes"])
    assert any("shop" in str(x) for x in rep["preuves_absentes"])


# --- ARCHI multi-langages (Rust / TypeScript) ---

def test_archi_detects_forbidden_dep_rust(tmp_path):
    _write(tmp_path, "ui/view.rs", "use engine::board;\nfn render() {}\n")
    _write(tmp_path, "engine/core.rs", "pub fn tick() {}\n")
    blueprint = {"modules": ["ui", "engine"], "deps_interdites": [["ui", "engine"]]}
    rep = check_architecture(blueprint, tmp_path)
    assert rep["passed"] is False
    assert ["ui", "engine"] in rep["deps_interdites_violées"]


def test_archi_detects_forbidden_dep_typescript(tmp_path):
    _write(tmp_path, "ui/view.ts", "import { Board } from '../engine/board';\n")
    _write(tmp_path, "engine/board.ts", "export const b = 1;\n")
    blueprint = {"modules": ["ui", "engine"], "deps_interdites": [["ui", "engine"]]}
    rep = check_architecture(blueprint, tmp_path)
    assert rep["passed"] is False
    assert ["ui", "engine"] in rep["deps_interdites_violées"]


# --- WIREMAP multi-langages (Rust / TypeScript / GDScript) ---

def test_wiremap_finds_rust_fn(tmp_path):
    _write(tmp_path, "chess/color.rs", "pub fn square_color(s: &str) -> String {\n    String::new()\n}\n")
    wiremap = {"features": [
        {"feature": "couleur", "fichiers": ["chess/color.rs"], "fonction": "square_color",
         "preuve": "test_color", "statut": "fait"},
    ]}
    assert check_wiremap(wiremap, tmp_path)["passed"] is True


def test_wiremap_finds_typescript_function(tmp_path):
    _write(tmp_path, "game/logic.ts", "export function movePiece(): void {}\n")
    wiremap = {"features": [
        {"feature": "deplacer", "fichiers": ["game/logic.ts"], "fonction": "movePiece",
         "preuve": "logic.test", "statut": "fait"},
    ]}
    assert check_wiremap(wiremap, tmp_path)["passed"] is True


def test_wiremap_finds_method_with_object_default_param(tmp_path):
    # Régression (bug trouvé in vivo sur GAMES/collect_runner) : une méthode avec un
    # paramètre par défaut objet (`input = {}`) ou déstructuré (`{x, y}`) DOIT être
    # trouvée — sinon faux positif « fonction renommée ».
    _write(tmp_path, "game/game.mjs",
           "export class G {\n"
           "  applyInput(input = {}) { return input; }\n"
           "  step(dtMs, input = {}) { return dtMs; }\n"
           "  draw(ctx, { x, y }) { return x + y; }\n"
           "}\n")
    wiremap = {"features": [
        {"feature": "R2 input", "fichiers": ["game/game.mjs"], "fonction": "applyInput", "preuve": "t"},
        {"feature": "R1 step", "fichiers": ["game/game.mjs"], "fonction": "step", "preuve": "t"},
        {"feature": "R draw", "fichiers": ["game/game.mjs"], "fonction": "draw", "preuve": "t"},
    ]}
    r = check_wiremap(wiremap, tmp_path)
    assert r["passed"] is True, r["fonctions_renommées"]


def test_wiremap_finds_gdscript_func(tmp_path):
    _write(tmp_path, "ui/hud.gd", "extends Control\n\nfunc update_hud() -> void:\n\tpass\n")
    wiremap = {"features": [
        {"feature": "hud", "fichiers": ["ui/hud.gd"], "fonction": "update_hud",
         "preuve": "hud_test", "statut": "fait"},
    ]}
    assert check_wiremap(wiremap, tmp_path)["passed"] is True


def test_wiremap_flags_renamed_across_langs(tmp_path):
    _write(tmp_path, "chess/color.rs", "pub fn square_colour() {}\n")  # ortho différente
    wiremap = {"features": [
        {"feature": "couleur", "fichiers": ["chess/color.rs"], "fonction": "square_color",
         "preuve": "t", "statut": "fait"},
    ]}
    rep = check_wiremap(wiremap, tmp_path)
    assert rep["passed"] is False
    assert "square_color" in str(rep["fonctions_renommées"])
