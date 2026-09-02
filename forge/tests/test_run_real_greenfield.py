"""Oracle de run_real.py — capacités greenfield (P1), SANS appel réseau/claude réel.

Couvre : (a) outils s9-build alignés au contrat ratifié ; (b) matérialisation
déterministe blueprint.json/wiremap.json par l'EXÉCUTEUR (extraction JSON fenced,
fail-fast honnête sur parse impossible) ; (c) model_override honoré (escalade
non no-op) ; (d) timeout paramétrable propagé ; (e/f) parsing CLI + merge des
tâches (défauts <- CLI <- tasks-file) ; (g) injection du pré-mortem dans le
prompt. Tous les appels `claude -p` sont monkeypatchés. NO_CLAIM_ALLOWED.
"""
import json
from dataclasses import dataclass

import pytest

import forge.run_real as run_real
from forge.dispatch import DETERMINISTIC, PROFILES
from forge.pool import DEFAULT_POOL_SIZE


@dataclass
class FakePayload:
    """Double minimal de DispatchPayload (seuls etape/model/prompt sont lus)."""
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, **extra):
    ctx = {
        "run_id": "run-1",
        "project": "proj",
        "run_dir": str(run_dir),
        "model_override": None,
        "dispatch_marker": "FORGE_DISPATCH:x:run-1",
        "attempt": 1,
        "premortem": [],
    }
    ctx.update(extra)
    return ctx


@pytest.fixture
def capture_calls(monkeypatch):
    """Remplace _claude_call_raw : trace (prompt, model, kwargs), sortie pilotable."""
    calls = []
    outputs = {"default": "artefact texte"}

    def fake(prompt, model, **kwargs):
        calls.append({"prompt": prompt, "model": model, **kwargs})
        return {"ok": True, "output": outputs["default"],
                "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    return calls, outputs


# --- (a) outils s9-build alignés au contrat ratifié ------------------------------

def test_s9_build_a_les_outils_du_contrat_ratifie():
    """s9-build.yaml §5 (l.55-58) : create fichiers ownership (Write) + run oracle
    — Edit/Read seuls rendaient le greenfield impossible (rien à éditer). F1a
    (red-team 2026-07-14) : Bash borné au strict contrat (« run: l'oracle code »,
    node) — Bash NU héritait de l'allow-list git de .claude/settings.local.json."""
    assert run_real._STEP_TOOLS["s9-build"] == ("Write", "Edit", "Read", "Bash(node:*)")


# --- (b) extraction JSON déterministe ---------------------------------------------

def test_extraction_dernier_bloc_json_valide():
    text = ('bla\n```json\n{"modules": ["vieux"]}\n```\nmilieu\n'
            '```json\n{"modules": ["recent"], "deps_interdites": []}\n```\nfin')
    data, why = run_real.extract_json_payload(text)
    assert why == ""
    assert data == {"modules": ["recent"], "deps_interdites": []}


def test_extraction_saute_un_dernier_bloc_invalide():
    """Le DERNIER bloc VALIDE gagne : un bloc final corrompu ne masque pas le bon."""
    text = ('```json\n{"modules": ["bon"]}\n```\n```json\n{pas du json}\n```')
    data, why = run_real.extract_json_payload(text)
    assert data == {"modules": ["bon"]}


def test_extraction_sortie_entiere_si_aucune_fence():
    data, why = run_real.extract_json_payload('  {"features": []}  ')
    assert data == {"features": []}


def test_extraction_echec_honnete_sur_texte_libre():
    data, why = run_real.extract_json_payload("aucun JSON ici")
    assert data is None
    assert why  # raison non vide (fail-fast documenté)


def test_extraction_refuse_un_json_non_objet():
    data, why = run_real.extract_json_payload("[1, 2, 3]")
    assert data is None
    assert "dict" in why


# --- (b) matérialisation des artefacts s4/s5 par l'exécuteur ----------------------

def test_s4_materialise_blueprint_json(tmp_path, capture_calls):
    calls, outputs = capture_calls
    outputs["default"] = ('Architecture...\n```json\n'
                          '{"modules": ["game"], "deps_interdites": [["ui", "engine"]]}\n```')
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s4-archi"), None, _context(tmp_path / "run"))
    assert res["ok"] is True
    blueprint = json.loads((tmp_path / "run" / "blueprint.json").read_text(encoding="utf-8"))
    assert blueprint == {"modules": ["game"], "deps_interdites": [["ui", "engine"]]}


def test_s5_materialise_wiremap_json(tmp_path, capture_calls):
    calls, outputs = capture_calls
    wiremap = {"features": [{"feature": "R1 boot", "fonction": "boot",
                             "fichiers": ["main.mjs"], "preuve": "test_boot"}]}
    outputs["default"] = f"WireMap...\n```json\n{json.dumps(wiremap)}\n```"
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s5-wiremap"), None, _context(tmp_path / "run"))
    assert res["ok"] is True
    on_disk = json.loads((tmp_path / "run" / "wiremap.json").read_text(encoding="utf-8"))
    assert on_disk == wiremap


def test_s4_sans_json_echoue_sans_ecrire_de_fichier(tmp_path, capture_calls):
    calls, outputs = capture_calls
    outputs["default"] = "je décris l'architecture mais sans bloc JSON"
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s4-archi"), None, _context(tmp_path / "run"))
    assert res["ok"] is False
    assert "blueprint.json" in res["reason"]
    # fail-fast : JAMAIS un fichier corrompu ou vide posé sur le disque.
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_les_autres_etapes_ne_materialisent_rien(tmp_path, capture_calls):
    calls, outputs = capture_calls
    outputs["default"] = '```json\n{"modules": []}\n```'
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s9-build"), None, _context(tmp_path / "run"))
    assert res["ok"] is True
    assert not (tmp_path / "run" / "blueprint.json").exists()
    assert not (tmp_path / "run" / "wiremap.json").exists()


# --- (c) model_override honoré ----------------------------------------------------

def test_model_override_prime_sur_le_modele_du_payload(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build", model="haiku"), None,
       _context(tmp_path / "run", model_override="opus"))
    assert calls[-1]["model"] == "opus"


def test_sans_override_le_modele_du_payload_est_utilise(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build", model="haiku"), None, _context(tmp_path / "run"))
    assert calls[-1]["model"] == "haiku"


# --- (d) timeout paramétrable propagé ----------------------------------------------

def test_step_timeout_propage_a_l_appel_reel(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={}, step_timeout=42.0)
    ex(FakePayload("s9-build"), None, _context(tmp_path / "run"))
    assert calls[-1]["timeout_s"] == 42.0


def test_timeout_par_defaut_1800s():
    assert run_real.DEFAULT_STEP_TIMEOUT_S == 1800.0


# --- timeout par profil (leçon forge.timeout_greenfield_by_profile) -----------------
# Propriété vérifiée : le couple MESURÉ reçoit sa valeur mesurée, les couples NON
# mesurés gardent le défaut, et l'intention explicite de l'opérateur gagne toujours.
# On n'assert PAS le contenu complet de la table : y ajouter une mesure future ne
# doit pas casser ce test (un test qui fige un état devient un faux signal).

def test_timeout_greenfield_godot_porte_a_5400s(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={},
                                  profile="standard_godot")
    ex(FakePayload("s9-build-godot-standard"), None, _context(tmp_path / "run"))
    assert calls[-1]["timeout_s"] == 5400.0


def test_timeout_couple_non_mesure_garde_le_defaut(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={},
                                  profile="standard_godot")
    ex(FakePayload("s12-verdict"), None, _context(tmp_path / "run"))
    assert calls[-1]["timeout_s"] == run_real.DEFAULT_STEP_TIMEOUT_S


def test_intention_explicite_de_l_operateur_gagne_sur_la_table(tmp_path, capture_calls):
    """Un opérateur qui borne délibérément le coût n'est jamais contredit."""
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={},
                                  step_timeout=600.0, profile="standard_godot")
    ex(FakePayload("s9-build-godot-standard"), None, _context(tmp_path / "run"))
    assert calls[-1]["timeout_s"] == 600.0


# --- (g) pré-mortem injecté dans le prompt -----------------------------------------

def test_premortem_injecte_sous_le_titre_attendu(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build"), None,
       _context(tmp_path / "run", premortem=["[s9] oracle jamais câblé"]))
    prompt = calls[-1]["prompt"]
    assert "## PRÉ-MORTEM (erreurs des runs passés)" in prompt
    assert "[s9] oracle jamais câblé" in prompt


def test_premortem_vide_n_ajoute_pas_de_section(tmp_path, capture_calls):
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build"), None, _context(tmp_path / "run", premortem=[]))
    assert "PRÉ-MORTEM" not in calls[-1]["prompt"]


# --- (f) tâches par défaut + merge tasks-file ---------------------------------------

def test_toutes_les_etapes_llm_du_profil_full_ont_une_tache_non_vide():
    tasks = run_real.default_task_by_step("shootemup", "GAMES/shootemup")
    for etape in PROFILES["full"]:
        if etape not in DETERMINISTIC:
            assert tasks.get(etape, "").strip(), f"tâche vide pour {etape}"


def test_defauts_s4_s5_exigent_le_format_des_oracles_statiques():
    """Les tâches par défaut doivent demander le bloc fenced au format exact lu par
    check_architecture (modules/deps_interdites) et check_wiremap (features...)."""
    tasks = run_real.default_task_by_step("proj", "GAMES/proj")
    assert "```json" in tasks["s4-archi"]
    assert '"modules"' in tasks["s4-archi"] and '"deps_interdites"' in tasks["s4-archi"]
    assert "```json" in tasks["s5-wiremap"]
    for key in ('"features"', '"feature"', '"fonction"', '"fichiers"', '"preuve"'):
        assert key in tasks["s5-wiremap"]


def test_defaut_s4_exige_deps_interdites_non_vides():
    """R3 : la tâche par défaut de s4 exige EXPLICITEMENT deps_interdites non
    vide, au minimum les séparations logique→rendu et logique→input — sinon
    l'agent livre un [] rejeté par l'exécuteur au premier tour."""
    s4 = run_real.default_task_by_step("proj", "GAMES/proj")["s4-archi"]
    assert "OBLIGATOIRE" in s4 and "NON VIDE" in s4
    assert "logique→rendu" in s4 and "logique→input" in s4


def test_defaut_s5_exige_fonction_et_fichiers_non_vides():
    """R4 : la tâche par défaut de s5 exige EXPLICITEMENT fonction/fichiers non
    vides pour chaque feature (une fonction vide faisait sauter la vérification
    d'existence de check_wiremap — wiremap creuse prouvée verte par sonde)."""
    s5 = run_real.default_task_by_step("proj", "GAMES/proj")["s5-wiremap"]
    assert "fonction" in s5 and "fichiers" in s5
    assert "NON VIDE" in s5


def test_merge_defauts_cli_puis_tasks_file():
    defaults = {"s9-build": "défaut s9", "s4-archi": "défaut s4", "s0-contrat": "défaut s0"}
    cli = {"s9-build": "cli s9", "s4-archi": ""}      # vide = ne PAS effacer le défaut
    file_tasks = {"s9-build": "fichier s9"}           # par-dessus tout (item f)
    merged = run_real.merge_task_overrides(defaults, cli, file_tasks)
    assert merged["s9-build"] == "fichier s9"
    assert merged["s4-archi"] == "défaut s4"
    assert merged["s0-contrat"] == "défaut s0"


def test_tasks_file_charge_et_valide(tmp_path):
    good = tmp_path / "tasks.json"
    good.write_text(json.dumps({"s9-build": "ma tâche"}), encoding="utf-8")
    assert run_real.load_tasks_file(good) == {"s9-build": "ma tâche"}

    bad = tmp_path / "bad.json"
    bad.write_text('["pas", "un", "dict"]', encoding="utf-8")
    with pytest.raises(ValueError):
        run_real.load_tasks_file(bad)
    with pytest.raises(ValueError):
        run_real.load_tasks_file(tmp_path / "absent.json")


# --- (d/e) parsing CLI --------------------------------------------------------------

def _parse(*extra):
    base = ["--project", "p", "--run-id", "r", "--src-root", "GAMES/p"]
    return run_real.build_parser().parse_args(base + list(extra))


def test_cli_defauts():
    args = _parse()
    assert args.step_timeout == 1800.0
    assert args.pool_size == DEFAULT_POOL_SIZE
    assert args.is_game is False
    assert args.logic_files == ""
    assert args.mutation_test_argv == ""
    assert args.oracle_config == ""
    assert args.tasks_file == ""


def test_cli_flags_jeu_et_timeout():
    args = _parse("--is-game", "--step-timeout", "3600",
                  "--logic-files", "game.mjs, engine.mjs",
                  "--mutation-test-argv", "node,run-oracle.mjs",
                  "--oracle-config", "forge/oracles.json",
                  "--pool-size", "3", "--tasks-file", "tasks.json")
    assert args.is_game is True
    assert args.step_timeout == 3600.0
    assert run_real._split_csv(args.logic_files) == ["game.mjs", "engine.mjs"]
    assert run_real._split_csv(args.mutation_test_argv) == ["node", "run-oracle.mjs"]
    assert args.oracle_config == "forge/oracles.json"
    assert args.pool_size == 3
    assert args.tasks_file == "tasks.json"


def test_split_csv_vide_donne_liste_vide():
    assert run_real._split_csv("") == []
    assert run_real._split_csv(" , ,") == []


# --- intégration offline : la chaîne full greenfield va au VERT ----------------------
# (preuve que les artefacts matérialisés par l'exécuteur nourrissent réellement
# s10b/s10c et le gel de règles du driver — même harnais que test_driver.py)

import sys

from forge.driver import ForgeDriver


@pytest.fixture
def offline(monkeypatch):
    """Offline strict : aucune sonde LM Studio (même garde que test_driver.py)."""
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def test_full_greenfield_offline_verdict_ok(tmp_path, offline, monkeypatch):
    src = tmp_path / "src"
    src.mkdir()
    (src / "main.py").write_text("def boot():\n    pass\n", encoding="utf-8")

    # R3 : deps_interdites OBLIGATOIRE et NON VIDE (un blueprint sans paire est
    # rejeté par l'exécuteur avant écriture) — paire inerte pour ce src minimal.
    blueprint = {"modules": ["main"], "deps_interdites": [["logique", "rendu"]]}
    wiremap = {"features": [{"feature": "R1 boot", "fonction": "boot",
                             "fichiers": ["main.py"], "preuve": "test_boot"}]}
    # s2-worldscan (réparation 2026-08-03, invariant « un agent de connaissance ne
    # doit jamais posséder l'état qu'il décrit ») : plus de droit d'écriture, un
    # bloc ```json``` terminal est désormais matérialisé par l'exécuteur en
    # worldscan.json (_ARTIFACT_BY_STEP) — le mock doit le rendre comme s4/s5.
    worldscan = {
        "games": [
            {"game": "Jeu A", "sources": [{"url": "https://example.test/a", "type": "wiki"}] * 3,
             "loops": {"minute_1": "x", "minute_10": "x", "hour_5": "x", "endgame": "x"},
             "objectives": [{"mode": "solo", "has_win_state": True, "victory_condition": "gagner",
                              "has_defeat_state": True, "defeat_condition": "perdre",
                              "player_goal": "avancer"}],
             "retention_answer": "rejouabilite"},
            {"game": "Jeu B", "sources": [{"url": "https://example.test/b", "type": "wiki"}] * 3,
             "loops": {"minute_1": "x", "minute_10": "x", "hour_5": "x", "endgame": "x"},
             "objectives": [{"mode": "solo", "has_win_state": True, "victory_condition": "gagner",
                              "has_defeat_state": True, "defeat_condition": "perdre",
                              "player_goal": "avancer"}],
             "retention_answer": "rejouabilite"},
        ],
        "advisory": True,
    }

    # s1-prisme / s3-decompo (2026-08-04, couche d'évaluation) : mêmes entrées dans
    # _ARTIFACT_BY_STEP que s2/s4/s5 — sans artefact structuré, aucun oracle ne peut
    # juger ces deux étapes et aucune substitution de worker n'est décidable sur
    # preuve. Le mock doit donc les rendre comme s4/s5, exactement comme s2-worldscan
    # a dû l'être le 2026-08-03.
    prisme = {
        "game_id": "proj",
        "exigences": [{
            "id": "ex.boot",
            "source": "EXPECTED",
            "source_role": "back",
            "reference": "https://example.test/a",
            "observation": "Le jeu demarre.",
            "enonce": "Le boot initialise l etat sans erreur.",
            "expected_proof": {"kind": "oracle", "statement": "boot() retourne sans lever."},
            "destination": "s3-decompo",
        }],
    }
    featuremap = {
        "game_id": "proj",
        "systemes": [{"id": "main", "features": [{"id": "feat.boot", "capacites": [{
            "id": "cap.boot",
            "capacite": "Initialiser l etat au demarrage.",
            "source_ref": "ex.boot",
            "expected_proof": {"kind": "oracle", "statement": "boot() retourne sans lever."},
        }]}]}],
    }

    # Sas moteur (GO Pierre 2026-09-01, C-a) : _materialize_yaml GATE désormais
    # s0-contrat sur un charter non matérialisable — avant ce correctif, l'absence
    # de bloc ```yaml``` à s0-contrat restait ADVISORY (yaml_check informatif) et
    # ce test n'avait pas besoin d'un charter dans son mock. Charter complet (7
    # champs R7) ajouté ici pour que s0-contrat matérialise et passe check_charter,
    # comme les autres étapes structurées de ce mock (s1/s2/s4/s5).
    charter_yaml = (
        "objectif: Livrer un jeu minimal jouable.\n"
        "hors_scope:\n  - multijoueur\n"
        "criteres_succes:\n  - boot() ne leve jamais\n"
        "actions_interdites:\n  - toucher tests/\n"
        "plateforme_cible: web/HTML5\n"
        "reference_jeu: jeu de test (choisi pour ce mock)\n"
        "criteres_demo:\n  - le jeu demarre sans erreur\n"
    )

    def fake(prompt, model, **kwargs):
        # La sortie dépend de l'étape, identifiée par le dispatch_marker du prompt.
        if "FORGE_DISPATCH:s0-contrat:" in prompt:
            out = f"charter\n```yaml\n{charter_yaml}```"
        elif "FORGE_DISPATCH:s4-archi:" in prompt:
            out = f"archi\n```json\n{json.dumps(blueprint)}\n```"
        elif "FORGE_DISPATCH:s5-wiremap:" in prompt:
            out = f"wiremap\n```json\n{json.dumps(wiremap)}\n```"
        elif "FORGE_DISPATCH:s2-worldscan:" in prompt:
            out = f"worldscan\n```json\n{json.dumps(worldscan)}\n```"
        elif "FORGE_DISPATCH:s1-prisme:" in prompt:
            out = f"prisme\n```json\n{json.dumps(prisme)}\n```"
        elif "FORGE_DISPATCH:s3-decompo:" in prompt:
            out = f"decompo\n```json\n{json.dumps(featuremap)}\n```"
        else:
            out = "artefact texte"
        return {"ok": True, "output": out, "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)

    oracle_cfg = tmp_path / "oracles.json"
    oracle_cfg.write_text(json.dumps({"proj": {
        "cwd": str(tmp_path),
        "command": [sys.executable, "-c", "import sys; sys.exit(0)"],
    }}), encoding="utf-8")

    run_dir = tmp_path / "run"
    executor = run_real.claude_executor(
        add_dir=src,
        task_by_step=run_real.default_task_by_step("proj", "src"),
    )
    report = ForgeDriver(
        "proj", "proj-1", profile="full", executor=executor, src_root=src,
        run_dir=run_dir, oracle_config=oracle_cfg,
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    ).run()

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"
    # les artefacts matérialisés par l'exécuteur ont bien nourri les oracles
    assert (run_dir / "blueprint.json").exists()
    assert (run_dir / "wiremap.json").exists()
    assert (run_dir / "prisme.json").exists()
    assert (run_dir / "featuremap.json").exists()
    # et le driver a figé le jeu de règles depuis la wiremap matérialisée (s5)
    frozen = json.loads((run_dir / "wiremap_frozen.json").read_text(encoding="utf-8"))
    assert frozen["features"] == ["R1 boot"]
