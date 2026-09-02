"""Câblage de la chaîne pour le profil `standard` (curriculum de jeux) — C1..C6.

Constat d'origine (run `pong-01`, 2026-07-23) : le run se terminait BLOCKED sans
`verdict.json`. Ni le jeu ni le forgeron n'étaient en cause — les briques existaient
toutes mais n'étaient pas RELIÉES. Ce fichier fige les six connexions, chacune sous la
forme « avant, ce fait était invisible ; maintenant il entre dans le reçu signé ».

Aucune de ces corrections ne verdit quoi que ce soit : le résultat attendu sur le
squelette réel de Pong reste un FAIL SIGNÉ (volets `placement`/`index` rouges).
NO_CLAIM_ALLOWED.
"""
import json
import sys

import pytest
import yaml

from forge.driver import ForgeDriver
from forge.oracle import REPO_ROOT, resolve_oracle
from forge.static_oracles import check_solvability_wired
from forge.verdict import build_aggregate_verdict, make_signed_receipt

KEY = None  # renseignée par la fixture `key`


@pytest.fixture
def key(tmp_path):
    return tmp_path / "forge_test.key"


def _receipt(oracle_id, run_id, status, detail, key_file, evidence_path=""):
    return make_signed_receipt(oracle_id, run_id, status, detail,
                               evidence_path=evidence_path, ts=1.0, key_file=key_file)


def _code_receipt(run_id, key_file, tmp_path, status="OK"):
    """Le reçu code exige un fichier d'évidence (exécution prouvable)."""
    ev = tmp_path / "oracle.log"
    ev.write_text("$ oracle\nok\n", encoding="utf-8")
    return _receipt("code", run_id, status, {}, key_file, evidence_path=str(ev))


# =======================================================================================
# C1 — le reçu `standard` entre dans le verdict SIGNÉ (verts comme rouges)
# =======================================================================================


def test_c1_le_recu_standard_rouge_rend_le_verdict_fail(tmp_path, key):
    """LE défaut : les six oracles du STANDARD ne pesaient sur AUCUN reçu signé — le
    profil ne prouvait rien de ce qu'il mesure."""
    code = _code_receipt("r1", key, tmp_path)
    skipped = _receipt("archi", "r1", "SKIPPED", {}, key)
    wire = _receipt("wiremap", "r1", "SKIPPED", {}, key)
    std = _receipt("standard", "r1", "FAIL", {
        "placement": {"passed": False}, "index": {"passed": False},
        "budget": {"passed": True}, "collisions": {"passed": True},
    }, key)
    agg = build_aggregate_verdict("jeu", "r1", code, skipped, wire, "aucun",
                                  redteam_ran=True, standard=std, key_file=key)
    assert agg.software_verdict == "FAIL"
    assert agg.decision == "BLOCKED"
    assert "standard" in agg.oracles
    # le flag CITE les volets rouges, il ne dit pas « violation » sans dire laquelle
    assert any("standard rouge: ['index', 'placement']" in f for f in agg.humangate_flags)


def test_c1_un_recu_standard_vert_ne_bloque_rien(tmp_path, key):
    code = _code_receipt("r1", key, tmp_path)
    ok = {"passed": True}
    std = _receipt("standard", "r1", "OK", {"placement": ok, "index": ok}, key)
    agg = build_aggregate_verdict(
        "jeu", "r1", code,
        _receipt("archi", "r1", "OK", {}, key), _receipt("wiremap", "r1", "OK", {}, key),
        "qwen2.5-14b-instruct", redteam_ran=True, standard=std, key_file=key)
    assert agg.software_verdict == "OK"
    assert agg.oracles["standard"]["status"] == "OK"


def test_c1_recu_standard_altere_rompt_la_provenance(tmp_path, key):
    """Le quatrième reçu est vérifié comme les trois autres — pas un champ décoratif."""
    code = _code_receipt("r1", key, tmp_path)
    std = _receipt("standard", "r1", "OK", {}, key)
    forge = type(std)(receipt=std.receipt, signature="00" * 32)
    agg = build_aggregate_verdict(
        "jeu", "r1", code,
        _receipt("archi", "r1", "OK", {}, key), _receipt("wiremap", "r1", "OK", {}, key),
        "aucun", redteam_ran=True, standard=forge, key_file=key)
    assert agg.provenance_ok is False
    assert agg.software_verdict == "BLOCKED"


def test_c1_signature_retrocompatible_sans_recu_standard(tmp_path, key):
    """RÉTRO-COMPATIBILITÉ : omis, `standard` ne change RIEN (profils full/patch/…)."""
    code = _code_receipt("r1", key, tmp_path)
    archi = _receipt("archi", "r1", "OK", {}, key)
    wire = _receipt("wiremap", "r1", "OK", {}, key)
    agg = build_aggregate_verdict("jeu", "r1", code, archi, wire, "aucun",
                                  redteam_ran=True, key_file=key)
    assert set(agg.oracles) == {"code", "archi", "wiremap"}
    assert agg.software_verdict == "OK"
    assert not any("standard" in f for f in agg.humangate_flags)


# =======================================================================================
# C3 — la garde solvabilité connaît LES DEUX topologies (aucune ne remplace l'autre)
# =======================================================================================


def _standard_solvability(root, body="const bot = { won: 1 > 0 };\n"):
    d = root / "07_TESTS" / "oracle"
    d.mkdir(parents=True, exist_ok=True)
    (d / "solvability.mjs").write_text(body, encoding="utf-8")


def test_c3_topologie_standard_preuve_trouvee_et_cablee(tmp_path):
    _standard_solvability(tmp_path)
    r = check_solvability_wired(
        tmp_path, standard_topology=True,
        runner_argv=["node", "--test", "07_TESTS/oracle/solvability.mjs"])
    assert r["passed"] is True
    assert r["topology"] == "standard"


def test_c3_topologie_standard_preuve_presente_mais_non_cablee_est_rouge(tmp_path):
    """Le fichier existe mais la commande d'oracle ne l'exécute pas : théâtre d'oracle."""
    _standard_solvability(tmp_path)
    r = check_solvability_wired(tmp_path, standard_topology=True,
                                runner_argv=["node", "--test", "07_TESTS/unit/x.test.mjs"])
    assert r["passed"] is False
    assert any("n'invoque pas" in x for x in r["raisons"])


def test_c3_argv_vide_nest_jamais_un_vert(tmp_path):
    """Oracle non résolu => câblage NON prouvé (hypothèse inconnue, jamais un vert)."""
    _standard_solvability(tmp_path)
    assert check_solvability_wired(tmp_path, standard_topology=True,
                                   runner_argv=[])["passed"] is False


def test_c3_topologie_standard_preuve_absente_est_rouge(tmp_path):
    r = check_solvability_wired(tmp_path, standard_topology=True,
                                runner_argv=["node", "07_TESTS/oracle/solvability.mjs"])
    assert r["passed"] is False
    assert any("07_TESTS/oracle/solvability.mjs absent" in x for x in r["raisons"])


def test_c3_topologie_legacy_inchangee(tmp_path):
    """Les jeux de l'ancienne topologie gardent EXACTEMENT le contrat de retour d'avant
    (forme du dict comprise : elle est assertée en égalité stricte ailleurs)."""
    (tmp_path / "solvability.mjs").write_text("const won = 1 > 0;\n", encoding="utf-8")
    (tmp_path / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\nspawn("node", ["solvability.mjs"]);\n',
        encoding="utf-8")
    assert check_solvability_wired(tmp_path) == {"passed": True, "raisons": [],
                                                 "checked": True}


# =======================================================================================
# C4 — `logic_files` dérivés de la VRAIE wiremap (deux formats, deux emplacements)
# =======================================================================================


def test_c4_wiremap_standard_schema_2_objets_path_category():
    """Format `schema_version: 2` : `lines[]` + `fichiers[]` d'OBJETS. Le code d'origine
    supposait `features[]` + chaînes nues => 0 fichier => BLOCKED, gate mutation jamais
    exécuté (un jeu à 20% de mutation serait passé en silence)."""
    wiremap = {
        "schema_version": 2,
        "lines": [
            {"id": "core.boot", "fichiers": [
                {"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"},
                {"path": "07_TESTS/oracle/solvability.mjs", "category": "test.solvability"},
            ]},
            {"id": "core.input", "fichiers": [
                {"path": "05_SYSTEMS/input/input.mjs", "category": "system"}]},
        ],
    }
    files = ForgeDriver._logic_files_from_wiremap_any(wiremap)
    assert files == ["05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/input/input.mjs"]
    # la PREUVE n'est pas du code mutable : muter sa propre solvabilité n'a aucun sens.
    # (l'heuristique de nom ne suffit pas : « 07_TESTS » ne contient pas « test » en
    # minuscules — c'est la CATÉGORIE de la table figée qui tranche)
    assert not any("solvability" in f for f in files)


def test_c4_wiremap_legacy_features_chaines_inchangee():
    wiremap = {"features": [{"fichiers": ["logic.mjs", "logic.test.mjs", "notes.md"]}]}
    assert ForgeDriver._logic_files_from_wiremap_any(wiremap) == ["logic.mjs"]


def test_c4_entrees_malformees_ne_crashent_pas():
    for bad in (None, [], {"lines": "pas une liste"}, {"lines": [None, 3]},
                {"lines": [{"fichiers": [None, 42, {"pas_de_path": 1}]}]}):
        assert ForgeDriver._logic_files_from_wiremap_any(bad) == []


# =======================================================================================
# C5 — `check_index` reçoit `repo_map` (le volet `dossiers_hors_structure` s'exécute)
# =======================================================================================


def _standard_game(root):
    """Squelette STANDARD minimal accepté par les six oracles (au placement près)."""
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
        "lines": [{"id": "core.boot", "category": "system", "provides": ["game.boot"],
                   "requires": [], "owner": True, "state": "IMPLEMENTED",
                   "address": "05_SYSTEMS/game_loop/",
                   "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs",
                                 "category": "system"}]}],
    }), encoding="utf-8")
    return root


def _run_standard_step(tmp_path, game_dir):
    d = ForgeDriver("g", "r1", run_dir=tmp_path / "run", profile="standard",
                    game_dir=game_dir, key_file=tmp_path / "k.key",
                    audit_path=tmp_path / "audit.jsonl")
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    d._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


def test_c5_dossier_hors_structure_est_desormais_vu_par_le_driver(tmp_path):
    """`src/` créé par un builder hors de la structure figée : le volet existait, était
    testé, mais n'avait JAMAIS tourné sur un jeu réel (repo_map non passé)."""
    game = _standard_game(tmp_path / "game")
    (game / "src").mkdir()
    (game / "src" / "rogue.mjs").write_text("export const r=1;\n", encoding="utf-8")
    entry = _run_standard_step(tmp_path, game)
    idx = entry["detail"]["index"]
    assert idx["dossiers_hors_structure"] == ["src"]
    assert idx["passed"] is False
    assert entry["status"] == "FAIL"


def test_c5_activation_pas_regression_sans_dossier_pirate(tmp_path):
    """Sans dossier hors structure, l'activation ne change AUCUN résultat (mesuré sur
    Pong : `dossiers_hors_structure = []`)."""
    game = _standard_game(tmp_path / "game")
    idx = _run_standard_step(tmp_path, game)["detail"]["index"]
    assert idx["dossiers_hors_structure"] == []


# =======================================================================================
# C2 — le volet e2e est un SKIPPED SIGNÉ en profil `standard` (décision Pierre 2026-07-23)
# =======================================================================================


def _oracle_cfg(tmp_path, project, cwd, exit_code=0):
    cfg = tmp_path / f"oracles_{project}.json"
    cfg.write_text(json.dumps({project: {
        "cwd": str(cwd),
        "command": [sys.executable, "-c",
                    f"import sys; sys.exit({exit_code})  # 07_TESTS/oracle/solvability.mjs"],
    }}), encoding="utf-8")
    return cfg


def _run_code_step(tmp_path, game_dir, profile, logic_files=None):
    d = ForgeDriver("g", "r1", run_dir=tmp_path / f"run_{profile}", profile=profile,
                    is_game=True, src_root=game_dir, game_dir=game_dir,
                    logic_files=logic_files,
                    oracle_config=_oracle_cfg(tmp_path, "g", game_dir),
                    key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
                    mutation_baseline_runner=lambda argv, cwd: True,
                    mutation_runner=lambda src, argv, *, cwd, **kw: {
                        "total": 2, "killed": 2, "survived": 0, "score": 1.0,
                        "survivors": []},
                    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    d._run_deterministic(state, "s10a-oracle-code")
    return state["steps"]["s10a-oracle-code"]


def test_c2_profil_standard_saute_le_volet_e2e_explicitement(tmp_path):
    """JAMAIS un faux OK, JAMAIS un silence : SKIPPED motivé, dans le reçu."""
    game = _standard_game(tmp_path / "game")
    _standard_solvability(game)
    entry = _run_code_step(tmp_path, game, "standard")
    e2e = entry["detail"]["e2e"]
    assert e2e["status"] == "SKIPPED"
    assert "décision Pierre 2026-07-23" in e2e["reason"]
    assert "passed" not in e2e, "un SKIPPED ne doit jamais se lire comme un vert"
    # le saut ne rougit pas le pas : c'est bien la SEULE conséquence attendue
    assert entry["status"] == "OK", entry["detail"]


def test_c2_les_autres_profils_gardent_la_garde_e2e(tmp_path):
    """full/increment/micro : rien ne change — un jeu sans harnais e2e reste rouge.
    (`logic_files` est fourni pour que le pas atteigne bien la décision du gate et ne
    s'arrête pas plus tôt sur un BLOCKED « fichiers logiques inconnus ».)"""
    game = _standard_game(tmp_path / "game")
    _standard_solvability(game)
    entry = _run_code_step(tmp_path, game, "micro",
                           logic_files=["05_SYSTEMS/game_loop/loop.mjs"])
    e2e = entry["detail"]["e2e"]
    assert e2e.get("status") != "SKIPPED"
    assert e2e["passed"] is False
    assert entry["status"] == "FAIL"


# =======================================================================================
# C6 — oracles.json : plus d'entrée fantôme, entrée `pong` présente et cohérente
# =======================================================================================


def test_c6_toute_entree_dont_le_jeu_est_present_cite_des_fichiers_reels():
    """Un oracle qui cite un fichier absent est un BLOCKED déguisé. Le contrôle ne porte
    QUE sur les jeux présents ici : `GAMES/` contient des dossiers NON SUIVIS par git
    (breakout, kb_tactics… existent dans la copie principale, pas dans un worktree) —
    juger l'absence d'un dossier non versionné dirait le worktree, pas l'oracle."""
    config = json.loads((REPO_ROOT / "forge" / "oracles.json")
                        .read_text(encoding="utf-8"))
    problemes = []
    for projet, entry in config.items():
        cwd = REPO_ROOT / entry["cwd"]
        if not cwd.is_dir():
            continue
        for arg in entry["command"][1:]:
            if arg.endswith(".mjs") and not (cwd / arg).exists() and not (REPO_ROOT / arg).exists():
                problemes.append(f"{projet}: {arg}")
    assert problemes == [], f"fichiers cités par un oracle mais absents: {problemes}"


def test_c6_pong_est_resoluble_et_cite_ses_deux_bras_de_preuve():
    """Sans entrée, resolve_oracle lève => gate._blocked => BLOCKED, evidence_path=''
    => provenance_ok=False. L'entrée doit citer les tests ET la solvabilité (c'est ce
    câblage que check_solvability_wired vérifie en topologie STANDARD)."""
    spec = resolve_oracle("pong")
    assert spec.cwd == (REPO_ROOT / "GAMES" / "pong").resolve()
    joined = " ".join(spec.command)
    assert "07_TESTS/oracle/solvability.mjs" in joined
    assert "07_TESTS/unit/" in joined
    for arg in spec.command[2:]:
        assert (spec.cwd / arg).exists(), f"{arg} cité par l'oracle mais absent du disque"
