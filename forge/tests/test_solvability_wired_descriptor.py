"""Oracle du volet solvabilité en régime DESCRIPTEUR (contrat V1, `proof.solvability`).

Dernier rouge de Snake (mission Pierre 2026-07-29) : `check_solvability_wired`
supposait en dur `07_TESTS/oracle/solvability.mjs` (hypothèse web-only). Snake
prouve sa solvabilité en GDScript (`solvability.gd`, déclaré dans
`00_CHARTER/game_contract.yaml` sous `proof.solvability.entry`) — un faux rouge
alors que 50/50 parties sont gagnées (mesuré via `godot_oracle.mjs`). Ces tests
prouvent que, quand un descripteur `proof` est fourni, la garde LIT le
descripteur au lieu de deviner un chemin `.mjs`, et documente le critère de
câblage retenu (référence textuelle du basename de l'entrée dans le wrapper
localisé via `runner_argv`) ainsi que sa limite assumée. NO_CLAIM_ALLOWED.
"""
from forge.static_oracles import check_solvability_wired


def _write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _snake_like_repo(tmp_path):
    """Reconstitue la forme réelle mesurée : dépôt avec forge/godot_oracle.mjs
    (le wrapper cité dans oracles.json) et un jeu GAMES/<x>/ avec son entrée."""
    repo = tmp_path / "repo"
    game = repo / "GAMES" / "snake"
    (game).mkdir(parents=True)
    _write(repo / "forge" / "godot_oracle.mjs",
           "const SOLVABILITY_SCRIPT = 'res://solvability.gd';\n"
           "spawnSync(bin, [script, project, SOLVABILITY_SCRIPT]);\n")
    return repo, game


# --- vert : descripteur présent, entrée existante, câblage prouvé -------------------

def test_descripteur_entree_existante_et_cablee_acceptee(tmp_path):
    """`_resolve_wrapper_script` essaie d'abord le dépôt RÉEL (_REPO_ROOT), puis
    `root` (le jeu) en repli — on exerce ici le repli `root`, en pointant un
    wrapper qu'aucun dépôt réel ne porte sous ce nom (`wrapper.mjs`), pour ne pas
    dépendre du contenu réel de forge/godot_oracle.mjs dans ce test isolé."""
    repo, game = _snake_like_repo(tmp_path)
    _write(game / "solvability.gd", "func run():\n\treturn true\n")
    _write(game / "wrapper.mjs",
           "const SOLVABILITY_SCRIPT = 'res://solvability.gd';\n"
           "spawnSync(bin, [script, project, SOLVABILITY_SCRIPT]);\n")
    proof = {"entry": "solvability.gd", "max_ticks": 5000, "trials": 50}
    runner_argv = ("node", "wrapper.mjs", "GAMES/snake")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv, proof=proof)
    assert res["passed"] is True, res["raisons"]
    assert res["checked"] is True
    assert res["topology"] == "descripteur"
    assert res["raisons"] == []


# --- rouge : entrée absente du disque ------------------------------------------------

def test_descripteur_entree_absente_rejetee(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    proof = {"entry": "solvability.gd"}
    runner_argv = ("node", "wrapper.mjs", "GAMES/snake")
    _write(game / "wrapper.mjs",
           "const SOLVABILITY_SCRIPT = 'res://solvability.gd';\n")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv, proof=proof)
    assert res["passed"] is False
    assert res["checked"] is True
    assert any("absente sous" in r for r in res["raisons"])


# --- rouge : entrée présente mais vide/illisible -------------------------------------

def test_descripteur_entree_vide_rejetee(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    _write(game / "solvability.gd", "   \n")
    proof = {"entry": "solvability.gd"}
    runner_argv = ("node", "wrapper.mjs", "GAMES/snake")
    _write(game / "wrapper.mjs",
           "const SOLVABILITY_SCRIPT = 'res://solvability.gd';\n")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv, proof=proof)
    assert res["passed"] is False
    assert any("vide ou illisible" in r for r in res["raisons"])


# --- rouge : entrée existe, mais le câblage n'est PAS prouvé -------------------------

def test_descripteur_cablage_non_prouve_wrapper_ne_reference_pas_entree(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    _write(game / "solvability.gd", "func run():\n\treturn true\n")
    _write(game / "wrapper.mjs", "console.log('rien à voir ici');\n")
    proof = {"entry": "solvability.gd"}
    runner_argv = ("node", "wrapper.mjs", "GAMES/snake")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv, proof=proof)
    assert res["passed"] is False
    assert any("ne référence pas" in r for r in res["raisons"])


def test_descripteur_cablage_non_prouve_aucun_wrapper_localisable(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    _write(game / "solvability.gd", "func run():\n\treturn true\n")
    proof = {"entry": "solvability.gd"}
    # runner_argv ne pointe vers aucun fichier existant, ni côté dépôt ni côté jeu.
    runner_argv = ("node", "introuvable.mjs", "GAMES/snake")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv, proof=proof)
    assert res["passed"] is False
    assert any("aucun script wrapper localisable" in r for r in res["raisons"])


def test_descripteur_argv_vide_jamais_un_vert_par_defaut(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    _write(game / "solvability.gd", "func run():\n\treturn true\n")
    proof = {"entry": "solvability.gd"}
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=(), proof=proof)
    assert res["passed"] is False
    assert any("aucun script wrapper localisable" in r for r in res["raisons"])


# --- rouge : descripteur sans champ 'entry' exploitable ------------------------------

def test_descripteur_sans_entry_rejete(tmp_path):
    repo, game = _snake_like_repo(tmp_path)
    game.mkdir(parents=True, exist_ok=True)
    proof = {"max_ticks": 5000}  # pas d'entry
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=("node", "x.mjs"), proof=proof)
    assert res["passed"] is False
    assert any("sans champ 'entry' exploitable" in r for r in res["raisons"])


# --- non-régression : sans descripteur (proof=None), comportement historique --------

def test_sans_descripteur_chemin_standard_historique_inchange(tmp_path):
    """proof=None (défaut) : le chemin STANDARD historique (07_TESTS/oracle/
    solvability.mjs deviné, recherche de sous-chaîne dans runner_argv) doit rester
    EXACTEMENT ce qu'il était avant cette mission — même reçu, mêmes clés."""
    game = tmp_path / "game"
    (game / "07_TESTS" / "oracle").mkdir(parents=True)
    (game / "07_TESTS" / "oracle" / "solvability.mjs").write_text(
        "const bot = play();\nif (!bot.won) process.exit(1);\n", encoding="utf-8")
    runner_argv = ("node", "07_TESTS/oracle/solvability.mjs")
    res = check_solvability_wired(
        game, standard_topology=True, runner_argv=runner_argv)  # proof omis => None
    assert res == {"passed": True, "raisons": [], "checked": True, "topology": "standard"}


def test_sans_descripteur_chemin_legacy_historique_inchange(tmp_path):
    """proof=None (défaut), standard_topology=False (défaut) : forme du reçu LEGACY
    strictement inchangée (assertée en égalité stricte ailleurs, comme documenté)."""
    (tmp_path / "run-oracle.mjs").write_text(
        'spawn("node", ["solvability.mjs"]);\n', encoding="utf-8")
    (tmp_path / "solvability.mjs").write_text(
        "const bot = play();\nif (!bot.won) process.exit(1);\n", encoding="utf-8")
    res = check_solvability_wired(tmp_path)
    assert res == {"passed": True, "raisons": [], "checked": True}
