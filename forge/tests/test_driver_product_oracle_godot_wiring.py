"""Câblage driver du fournisseur GODOT (corrections Pierre ①②, mission 2026-07-29) —
`ForgeDriver._run_code_oracle` (s10a) active `product_oracle_godot_runner` SEULEMENT
si (a) le contrat de preuve le prévoit (`proof:` bien formé, lu via
`_mutation_regime_for_game`) ET (b) la capacité est constatée (oracles
`FORGE_ORACLE` réellement présents sur disque, `has_godot_capacity`) ;
`ForgeDriver._run_standard_oracle` (s10s) construit `observable_volets_effectifs`
(provenance `source: "web"|"godot"` par volet, jamais une fusion silencieuse) et le
passe à `check_observable_coverage` au lieu de `product_oracle` seul.

Ces tests injectent `product_oracle_godot_runner` (même patron que
`product_oracle_runner`, `mutation_runner`) — jamais un vrai binaire Godot ni un
vrai process. La couverture RED/GREEN du fournisseur lui-même vit dans
`test_product_oracle_godot.py`.
"""
import json
import sys

import yaml

from forge.driver import ForgeDriver
from forge.standard_oracles import _volet_status


def _oracle_cfg(tmp_path, project, cwd):
    """Même artifice que `test_driver_product_oracle.py::_oracle_cfg` : un oracle
    qui réussit réellement, pour que le statut du pas s10a ne soit pas BLOCKED pour
    une raison étrangère au fournisseur Godot testé ici."""
    cfg = tmp_path / f"oracles_{project}.json"
    cfg.write_text(json.dumps({project: {
        "cwd": str(cwd),
        "command": [sys.executable, "-c",
                    "import sys; sys.exit(0)  # 07_TESTS/oracle/solvability.mjs"],
    }}), encoding="utf-8")
    return cfg


def _standard_game_no_proof(root, *, observable_proof="auto_session"):
    """Jeu STANDARD SANS descripteur `proof:` (comme Pong aujourd'hui) — le chemin
    historique doit rester EXACTEMENT inchangé pour ce squelette."""
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
            "genre_refs": ["genre.g.some_rule"],
            "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}],
        }],
        "genre_refusals": [],
    }), encoding="utf-8")
    (root / "01_DESIGN").mkdir(parents=True)
    (root / "01_DESIGN" / "genre_bible.json").write_text(json.dumps({
        "genre_rules": [{"id": "genre.g.some_rule", "applies_to_wiremap_line": "core.boot"}],
    }), encoding="utf-8")
    return root


def _with_proof_descriptor(root):
    """Ajoute un descripteur `proof:` bien formé au contrat (condition (a))."""
    contract_path = root / "00_CHARTER" / "game_contract.yaml"
    contract = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
    contract["proof"] = {"mutation": {"command": ["echo", "noop"]}}
    contract_path.write_text(yaml.safe_dump(contract), encoding="utf-8")
    return root


def _with_godot_oracle_file(root, name="core_boot"):
    """Ajoute un fichier oracle `.gd` FORGE_ORACLE sous 07_TESTS/oracle/ (condition (b))."""
    oracle_dir = root / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True, exist_ok=True)
    (oracle_dir / f"{name}.gd").write_text(
        f'# Sortie : "FORGE_ORACLE {name} {{json}}"\nextends SceneTree\n', encoding="utf-8")
    return root


def _run_code_step(tmp_path, game_dir, *, product_oracle_godot_runner=None):
    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        is_game=True, src_root=game_dir, game_dir=game_dir,
        oracle_config=_oracle_cfg(tmp_path, "g", game_dir), key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=lambda game_dir: {
            "auto_session": {"passed": True, "checked": True}},
        product_oracle_godot_runner=product_oracle_godot_runner,
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    d._run_deterministic(state, "s10a-oracle-code")
    return state["steps"]["s10a-oracle-code"], state


def _run_standard_step_from_s10a(tmp_path, game_dir, d, s10a_state):
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    state["steps"]["s10a-oracle-code"] = s10a_state["steps"]["s10a-oracle-code"]
    d._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


# --- Correction ① : sélection pilotée par contrat ET capacité, pas runtime==godot ---


def test_ni_proof_ni_capacite_aucun_volet_godot_raison_tracee(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game")
    calls = []
    entry, _ = _run_code_step(
        tmp_path, game,
        product_oracle_godot_runner=lambda gd: calls.append(gd) or {"x": {"passed": True}})
    assert calls == []
    assert "product_oracle_godot" not in entry["detail"]
    act = entry["detail"]["product_oracle_godot_activation"]
    assert act["active"] is False
    assert act["proof_descriptor_present"] is False
    assert act["godot_capacity_present"] is False
    assert act["reason"]  # raison tracée, jamais un silence


def test_proof_sans_capacite_aucun_volet_godot_raison_tracee(tmp_path):
    """Condition (a) seule (contrat de preuve prévu) SANS (b) (aucun oracle .gd
    présent) : aucun volet Godot, raison nommée — jamais activé par le seul contrat."""
    game = _standard_game_no_proof(tmp_path / "game")
    _with_proof_descriptor(game)
    calls = []
    entry, _ = _run_code_step(
        tmp_path, game,
        product_oracle_godot_runner=lambda gd: calls.append(gd) or {"x": {"passed": True}})
    assert calls == []
    assert "product_oracle_godot" not in entry["detail"]
    act = entry["detail"]["product_oracle_godot_activation"]
    assert act["active"] is False
    assert act["proof_descriptor_present"] is True
    assert act["godot_capacity_present"] is False
    assert "oracle" in act["reason"].lower()


def test_capacite_sans_proof_aucun_volet_godot_raison_tracee(tmp_path):
    """Condition (b) seule (oracles .gd présents) SANS (a) (pas de descripteur
    `proof:`) : aucun volet Godot — la seule présence de fichiers ne suffit pas,
    jamais une heuristique sur le nom du jeu ou une extension."""
    game = _standard_game_no_proof(tmp_path / "game")
    _with_godot_oracle_file(game)
    calls = []
    entry, _ = _run_code_step(
        tmp_path, game,
        product_oracle_godot_runner=lambda gd: calls.append(gd) or {"x": {"passed": True}})
    assert calls == []
    assert "product_oracle_godot" not in entry["detail"]
    act = entry["detail"]["product_oracle_godot_activation"]
    assert act["active"] is False
    assert act["proof_descriptor_present"] is False
    assert act["godot_capacity_present"] is True


def test_proof_et_capacite_active_le_fournisseur_godot(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game")
    _with_proof_descriptor(game)
    _with_godot_oracle_file(game)
    calls = []

    def runner(game_dir):
        calls.append(game_dir)
        return {"core_boot": {"status": "OK", "passed": True, "checked": True}}

    entry, _ = _run_code_step(tmp_path, game, product_oracle_godot_runner=runner)
    assert calls == [game]
    assert entry["detail"]["product_oracle_godot"] == {
        "core_boot": {"status": "OK", "passed": True, "checked": True}}
    act = entry["detail"]["product_oracle_godot_activation"]
    assert act["active"] is True
    assert act["proof_descriptor_present"] is True
    assert act["godot_capacity_present"] is True


def test_exception_du_fournisseur_godot_nest_jamais_bloquante(tmp_path):
    """Le fournisseur Godot qui lève ne doit JAMAIS faire remonter d'exception au
    pas s10a — la présence d'un descripteur `proof:` reroute par ailleurs ce jeu
    vers le régime mutation "descripteur" (`_mutation_regime_for_game`, réutilisé
    tel quel par la correction ①, hors périmètre de cette mission de le modifier) ;
    seul le comportement du fournisseur Godot (`product_oracle_godot`, jamais
    d'exception qui remonte) est sous test ici, pas le statut global du régime
    mutation."""
    game = _standard_game_no_proof(tmp_path / "game")
    _with_proof_descriptor(game)
    _with_godot_oracle_file(game)

    def boom(game_dir):
        raise RuntimeError("panne fabriquée")

    entry, _ = _run_code_step(tmp_path, game, product_oracle_godot_runner=boom)
    assert entry["status"] in ("OK", "FAIL", "BLOCKED")  # jamais une exception qui remonte
    assert entry["detail"]["product_oracle_godot"]["measured"] is False


# --- Correction ② : provenance conservée, pas de fusion silencieuse ------------------


def test_jeu_sans_proof_garde_exactement_ancien_chemin(tmp_path):
    """PREUVE EXIGÉE PAR PIERRE : un jeu sans `proof:` garde EXACTEMENT l'ancien
    chemin — `observable_volets_effectifs` a les MÊMES clés et les MÊMES statuts
    que `product_oracle` seul, et le fournisseur Godot n'est JAMAIS appelé."""
    game = _standard_game_no_proof(tmp_path / "game")
    godot_calls = []
    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        is_game=True, src_root=game, game_dir=game,
        oracle_config=_oracle_cfg(tmp_path, "g", game), key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=lambda game_dir: {
            "auto_session": {"passed": True, "checked": True}},
        product_oracle_godot_runner=lambda gd: godot_calls.append(gd) or {"never": {}},
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    d._run_deterministic(state, "s10a-oracle-code")
    d._run_deterministic(state, "s10s-oracle-standard")

    assert godot_calls == [], "fournisseur Godot jamais appelé pour un jeu sans proof:"
    s10s_detail = state["steps"]["s10s-oracle-standard"]["detail"]
    assert "product_oracle_godot" not in s10s_detail

    effective = s10s_detail["observable_volets_effectifs"]
    web_only = {"auto_session": {"passed": True, "checked": True}}
    assert set(effective.keys()) == set(web_only.keys())
    for name, web_volet in web_only.items():
        assert _volet_status(effective[name]) == _volet_status(web_volet)
        assert effective[name]["source"] == "web"

    # même verdict de couverture que si on avait passé product_oracle seul
    # (comportement historique, non modifié pour ce chemin).
    assert s10s_detail["observable_coverage"]["verdict"] == "OK"
    assert s10s_detail["product_oracle"] == web_only


def test_provenance_presente_sur_chaque_volet_web_et_godot(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game", observable_proof="core_boot")
    _with_proof_descriptor(game)
    _with_godot_oracle_file(game, name="core_boot")

    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        is_game=True, src_root=game, game_dir=game,
        oracle_config=_oracle_cfg(tmp_path, "g", game), key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=lambda game_dir: {
            "auto_session": {"passed": True, "checked": True}},
        product_oracle_godot_runner=lambda gd: {
            "core_boot": {"status": "OK", "passed": True, "checked": True}},
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    d._run_deterministic(state, "s10a-oracle-code")
    d._run_deterministic(state, "s10s-oracle-standard")

    effective = state["steps"]["s10s-oracle-standard"]["detail"]["observable_volets_effectifs"]
    assert effective["auto_session"]["source"] == "web"
    assert effective["core_boot"]["source"] == "godot"
    # ligne observable core.boot -> preuve nommée core_boot -> volet godot vert -> couverte
    assert state["steps"]["s10s-oracle-standard"]["detail"]["observable_coverage"]["verdict"] == "OK"


def test_conflit_de_nom_resolu_vers_web_et_trace(tmp_path):
    """Un volet du même nom des DEUX côtés : WEB prioritaire, conflit TRACÉ (jamais
    absorbé en silence)."""
    game = _standard_game_no_proof(tmp_path / "game", observable_proof="auto_session")
    _with_proof_descriptor(game)
    _with_godot_oracle_file(game, name="auto_session")

    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        is_game=True, src_root=game, game_dir=game,
        oracle_config=_oracle_cfg(tmp_path, "g", game), key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=lambda game_dir: {
            "auto_session": {"passed": True, "checked": True}},
        product_oracle_godot_runner=lambda gd: {
            "auto_session": {"status": "FAIL", "passed": False, "checked": True}},
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order},
             "catalog_brick_ids_snapshot": []}
    d._run_deterministic(state, "s10a-oracle-code")
    d._run_deterministic(state, "s10s-oracle-standard")

    detail = state["steps"]["s10s-oracle-standard"]["detail"]
    effective = detail["observable_volets_effectifs"]
    assert effective["auto_session"]["source"] == "web"
    assert effective["auto_session"]["passed"] is True  # web gagne, pas le godot rouge
    assert detail["observable_volets_resolution"]["conflits_resolus_vers_web"] == ["auto_session"]


def test_source_est_inerte_pour_volet_status():
    """Le champ `source` ne doit JAMAIS influencer `_volet_status`
    (`standard_oracles.py`, NON modifié — il ne lit que status/checked/passed)."""
    with_source = {"status": "OK", "passed": True, "source": "godot"}
    without_source = {"status": "OK", "passed": True}
    assert _volet_status(with_source) == _volet_status(without_source) == "OK"

    with_source_fail = {"checked": True, "passed": False, "source": "web"}
    without_source_fail = {"checked": True, "passed": False}
    assert _volet_status(with_source_fail) == _volet_status(without_source_fail) == "FAIL"
