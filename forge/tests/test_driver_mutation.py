"""Oracle du chemin critique mutation dans le driver (P0.2) — trous I1/I2 fermés.

I1 : un vert s10a de JEU est IMPOSSIBLE sans preuve mutation exécutée dans le run.
I2 : une preuve périmée (code/tests/triage modifiés après coup) est invalidée au
verdict — y compris à travers une reprise (state.json). NO_CLAIM_ALLOWED.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _oracle_config(tmp_path, project, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


def _game_dir(tmp_path):
    """Mini-jeu satisfaisant la garde e2e structurelle (check_e2e_harness)."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const speed = 3;\nexport const win = 1 >= 0;\n",
                                 encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n',
        encoding="utf-8",
    )
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n',
        encoding="utf-8",
    )
    # fichiers de tests nommés par DEFAULT_TEST_ARGV : la suite doit être scellable
    (g / "logic.test.mjs").write_text("// suite logique\n", encoding="utf-8")
    (g / "properties.test.mjs").write_text("// suite propriétés\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


def _one_survivor(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 3, "survived": 1, "score": 0.75,
            "survivors": [{"name": "ge->gt", "line": 2}]}


class StubExecutor:
    def __init__(self, raise_on=()):
        self.calls = []
        self.raise_on = set(raise_on)

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        if payload.etape in self.raise_on:
            raise RuntimeError(f"interruption simulée à {payload.etape}")
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "jeu", exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,  # baseline verte stubée
    )


def _verdict(run_dir):
    return json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))


# --- cas normal : jeu vert AVEC preuve mutation -----------------------------------

def test_jeu_vert_avec_preuve_mutation_valide(tmp_path, offline):
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"

    # le reçu mutation signé est embarqué dans le reçu code du verdict signé
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "OK"
    mutation = code["detail"]["mutation"]
    assert mutation["receipt"]["status"] == "OK"
    assert mutation["receipt"]["detail"]["code_sha256"]["logic.mjs"]
    assert mutation["signature"]


# --- I1 : jamais un vert sans preuve ----------------------------------------------

def test_jeu_sans_fichiers_logiques_connus_blocked(tmp_path, offline):
    """Ni logic_files ni wiremap.json => preuve mutation impossible => BLOCKED."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "BLOCKED"
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s10a-oracle-code"]["status"] == "BLOCKED"
    assert "mutation" in state["steps"]["s10a-oracle-code"]["detail"]["reason"]


def test_contournement_state_forge_sans_mutation_blocked(tmp_path, offline):
    """Tentative de contournement : un state.json où s10a est OK SANS preuve
    mutation (édité à la main) ne peut pas produire un verdict OK."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    kw = _kwargs(tmp_path, run_dir)
    drv_kwargs = dict(profile="micro", is_game=True, src_root=g,
                      logic_files=["logic.mjs"], mutation_runner=_all_killed, **kw)
    report = ForgeDriver("jeu", "jeu-1", executor=StubExecutor(), **drv_kwargs).run()
    assert report["software_verdict"] == "OK"  # préalable : run légitime vert

    # falsification : retirer la preuve mutation, rejouer uniquement le verdict
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    del state["steps"]["s10a-oracle-code"]["detail"]["mutation"]
    state["steps"]["s12-verdict"] = {"status": "PENDING", "attempts": 0}
    state["run_status"] = "RUNNING"
    (run_dir / "state.json").write_text(json.dumps(state), encoding="utf-8")
    (run_dir / "verdict.json").unlink()

    report2 = ForgeDriver("jeu", "jeu-1", executor=StubExecutor(), **drv_kwargs).run()
    assert report2["software_verdict"] == "BLOCKED"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "BLOCKED"


# --- I2 : preuve périmée invalidée au verdict (à travers une reprise) --------------

def _interrupted_then(tmp_path, run_dir, g, tamper):
    """Run patch interrompu APRÈS s10a (preuve posée), altération, puis reprise."""
    kw = _kwargs(tmp_path, run_dir)
    drv_kwargs = dict(profile="patch", is_game=True, src_root=g,
                      logic_files=["logic.mjs"], mutation_runner=_all_killed, **kw)
    with pytest.raises(RuntimeError):
        ForgeDriver("jeu", "jeu-1", executor=StubExecutor(raise_on={"s11-redteam-code"}),
                    **drv_kwargs).run()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s10a-oracle-code"]["status"] == "OK"  # preuve posée avant kill
    tamper()
    return ForgeDriver("jeu", "jeu-1", executor=StubExecutor(), **drv_kwargs).run()


def test_hash_code_divergent_au_verdict_blocked(tmp_path, offline):
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = _interrupted_then(
        tmp_path, run_dir, g,
        lambda: (g / "logic.mjs").write_text("export const speed = 99;\n",
                                             encoding="utf-8"))
    assert report["software_verdict"] == "BLOCKED"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "BLOCKED"
    assert any("divergent" in r for r in code["detail"]["mutation_verification"]["raisons"])


def test_triage_ajoute_apres_preuve_blocked(tmp_path, offline):
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = _interrupted_then(
        tmp_path, run_dir, g,
        lambda: (g / "mutation_triage.json").write_text(
            json.dumps([{"name": "ge->gt", "line": 2, "justification": "après coup"}]),
            encoding="utf-8"))
    assert report["software_verdict"] == "BLOCKED"
    code = _verdict(run_dir)["oracles"]["code"]
    assert any("triage" in r for r in code["detail"]["mutation_verification"]["raisons"])


# --- durcissements post-revue adversariale (2026-07-11) ----------------------------

def test_reprise_sans_flag_is_game_ne_desarme_pas_les_gates(tmp_path, offline):
    """BYPASS CONFIRMÉ (revue adversariale, reproduit) : reprendre un run de JEU
    sans repasser is_game=True retombait sur le défaut False et sautait la
    re-vérification s12. is_game est une propriété du RUN : le state la porte."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    kw = _kwargs(tmp_path, run_dir)
    with pytest.raises(RuntimeError):
        ForgeDriver("jeu", "jeu-1", profile="patch", is_game=True, src_root=g,
                    logic_files=["logic.mjs"], mutation_runner=_all_killed,
                    executor=StubExecutor(raise_on={"s11-redteam-code"}), **kw).run()
    (g / "logic.mjs").write_text("export const speed = 99;\n", encoding="utf-8")

    # reprise SANS is_game (l'oubli réaliste) : les gates jeu doivent tenir
    report = ForgeDriver("jeu", "jeu-1", profile="patch", src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         executor=StubExecutor(), **kw).run()
    assert report["software_verdict"] == "BLOCKED"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "BLOCKED"
    assert any("divergent" in r for r in code["detail"]["mutation_verification"]["raisons"])


def test_harnais_e2e_altere_apres_preuve_blocked(tmp_path, offline):
    """Échanger e2e.mjs entre la preuve (s10a) et le verdict (s12) = preuve périmée."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = _interrupted_then(
        tmp_path, run_dir, g,
        lambda: (g / "e2e.mjs").write_text("// coquille substituée\n", encoding="utf-8"))
    assert report["software_verdict"] == "BLOCKED"


def test_commande_de_test_indirecte_blocked_des_s10a(tmp_path, offline):
    """`npm test` (aucun fichier de test scellable) => auto-contrôle s10a => BLOCKED
    immédiat avec raisons, jamais un OK qui attendrait s12 pour tomber."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         mutation_test_argv=["npm", "test"],
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    s10a = state["steps"]["s10a-oracle-code"]
    assert s10a["status"] == "BLOCKED"
    assert "mutation_verification" in s10a["detail"]


# --- P0.3 : plus aucun chemin vers OK sans preuve valide ---------------------------

def test_jeu_non_declare_auto_detecte_par_le_harnais(tmp_path, offline):
    """Omettre is_game sur un dossier portant run-oracle.mjs/e2e.mjs ne désarme
    PAS les gates : un dossier qui porte un harnais de jeu EST un jeu."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro",  # is_game OMIS
                         executor=StubExecutor(), src_root=g,
                         **_kwargs(tmp_path, run_dir)).run()
    # sans fichiers logiques connus, un jeu auto-détecté doit être BLOCKED,
    # jamais traité comme un non-jeu vert
    assert report["software_verdict"] == "BLOCKED"
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["is_game"] is True
    assert state["steps"]["s10a-oracle-code"]["status"] == "BLOCKED"


def test_baseline_rouge_fail_des_s10a(tmp_path, offline):
    """Suite rouge sur code non muté => preuve mutation invalide => FAIL à s10a
    (l'escalade peut réparer la suite), jamais un OK."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    kw = _kwargs(tmp_path, run_dir)
    kw["mutation_baseline_runner"] = lambda argv, cwd: False
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **kw).run()
    assert report["software_verdict"] == "FAIL"
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    mutation = state["steps"]["s10a-oracle-code"]["detail"]["mutation"]
    assert mutation["receipt"]["detail"]["baseline_ok"] is False


# --- P0.3 sweep final : bypass reproduits par la revue adversariale ----------------

def test_flip_is_game_false_dans_state_ne_desarme_pas_la_preuve(tmp_path, offline):
    """BYPASS CONFIRMÉ (revue P0.3, reproduit). Éditer le state.json NON signé
    (is_game=false, retrait de detail.mutation/e2e) + src_root=None à la reprise
    ne doit PAS produire un verdict OK : la game-ness est re-dérivée de signaux
    objectifs on-disk (fichier d'évidence mutation), non-downgradable."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    kw = _kwargs(tmp_path, run_dir)
    rep = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True, src_root=g,
                      logic_files=["logic.mjs"], mutation_runner=_all_killed,
                      executor=StubExecutor(), **kw).run()
    assert rep["software_verdict"] == "OK"  # run légitime vert

    # falsification du state (non signé) + code désormais périmé
    (g / "logic.mjs").write_text("export const win = false;\n", encoding="utf-8")
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    state["is_game"] = False
    det = state["steps"]["s10a-oracle-code"]["detail"]
    det.pop("mutation", None)
    det.pop("e2e", None)
    state["steps"]["s12-verdict"] = {"status": "PENDING", "attempts": 0}
    state["run_status"] = "RUNNING"
    (run_dir / "state.json").write_text(json.dumps(state), encoding="utf-8")
    (run_dir / "verdict.json").unlink()

    # reprise SANS is_game et src_root=None (l'attaque exacte)
    rep2 = ForgeDriver("jeu", "jeu-1", profile="micro",  # is_game OMIS
                       executor=StubExecutor(), src_root=None,
                       logic_files=["logic.mjs"], mutation_runner=_all_killed,
                       **kw).run()
    assert rep2["software_verdict"] == "BLOCKED"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "BLOCKED"
    # ET le /gate doit AUSSI rejeter (pas seulement le driver) : le verdict reste
    # détecté comme jeu via la trace mutation_verification -> overall False.
    from forge.verify_run import verify_run
    res = verify_run(run_dir / "verdict.json", key_file=tmp_path / "forge_test.key")
    assert res["overall"] is False


# --- parité skill.md : mutation rouge alimente l'escalade, jamais masquée ----------

def test_finding3_triage_mensonger_ne_donne_pas_un_ok_propre(tmp_path, offline):
    """Le chemin finding-3 exact, via le driver NON modifié : un survivant réel
    'trié' par une justification écrite par le producteur ne produit plus un OK
    propre — software OK mais decision WITH_OBJECTION (HumanGate obligatoire)."""
    from forge.verdict import DECISION_READY, DECISION_READY_OBJECTION
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    (g / "mutation_triage.json").write_text(
        json.dumps([{"name": "ge->gt", "line": 2, "justification": "affirmé équivalent"}]),
        encoding="utf-8")
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, logic_files=["logic.mjs"],
                         mutation_runner=_one_survivor,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    record = _verdict(run_dir)
    assert record["decision"] == DECISION_READY_OBJECTION
    assert record["decision"] != DECISION_READY          # jamais un OK propre
    assert any("survivant" in f for f in record["humangate_flags"])


def test_survivant_non_justifie_fail_et_escalade_bornee(tmp_path, offline):
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    ex = StubExecutor()
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=ex, src_root=g, logic_files=["logic.mjs"],
                         mutation_runner=_one_survivor,
                         **_kwargs(tmp_path, run_dir)).run()
    s9_calls = [c for c in ex.calls if c[0] == "s9-build"]
    # pool_size=2 (Tier 2 #5) : 2 essais par tier avant chaque escalade bornée.
    assert [c[1] for c in s9_calls] == [None, None, "sonnet", "sonnet", "opus", "opus"]
    assert report["software_verdict"] == "FAIL"                  # rouge signé
    assert report["decision"] == "BLOCKED"
