"""Oracle des correctifs red-team de run_real.py (préparation 1er run full réel).

Couvre : F1 (outils builders bornés au contrat + deny-list git/PowerShell/zones
protégées sur TOUT appel claude -p) ; F2 (validation de schéma AVANT
matérialisation + check_architecture durci contre deps_interdites malformé) ;
F3 (durcissement console en tête de main) ; F4 (chaînage des artefacts amont
dans les prompts, troncature bornée) ; F5 (tasks-file fail-fast + valeurs vides
ignorées, défauts profile-aware, marqueur solvability dans verify_run, garde
run_dir périmé) ; R1-R4 (red-team de clôture : deny git par CLASSE + NotebookEdit,
isolation MCP --strict-mcp-config, deps_interdites obligatoire non vide,
wiremap fonction/fichiers non vides). Aucun appel réseau/claude réel.
NO_CLAIM_ALLOWED.
"""
import json
import re
from dataclasses import dataclass

import pytest

import forge.run_real as run_real
import forge.verify_run as verify_run
from forge.static_oracles import check_architecture


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
def capture_cmd(monkeypatch):
    """Remplace subprocess.run : trace la commande construite, aucun spawn réel."""
    cmds = []

    class FakeCompleted:
        returncode = 0
        stdout = json.dumps({"result": "ok", "usage": {}, "total_cost_usd": 0.0})
        stderr = ""

    def fake_run(cmd, **kwargs):
        cmds.append(list(cmd))
        return FakeCompleted()

    monkeypatch.setattr(run_real.subprocess, "run", fake_run)
    return cmds


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


# --- F1a : outils s9/s2.5 bornés au strict contrat --------------------------------

def test_s9_allowed_tools_bash_borne_node_jamais_bash_nu(tmp_path, capture_cmd):
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path,
                              tools=run_real._STEP_TOOLS["s9-build"])
    cmd = capture_cmd[-1]
    allowed = cmd[cmd.index("--allowedTools") + 1].split()
    assert "Bash(node:*)" in allowed
    assert "Bash" not in allowed  # jamais un Bash nu (héritage allow-list git)
    assert set(allowed) == {"Write", "Edit", "Read", "Bash(node:*)"}


def test_s2_5_artbible_outils_bornes():
    assert run_real._STEP_TOOLS["s2.5-artbible"] == ("Write", "Read", "Bash(node:*)")


# --- F1b : deny-list posée sur TOUT appel claude -p --------------------------------

def test_disallowed_contient_git_powershell_et_zones_protegees(tmp_path, capture_cmd):
    """R1 : le déni git est par CLASSE (préfixe 'git' entier, prefix-match du
    matcher : Bash(git:*) ≡ Bash(git *)) + NotebookEdit entier — un builder n'a
    aucun besoin de git ni de notebook, et acceptEdits auto-approuverait."""
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path,
                              tools=run_real._STEP_TOOLS["s9-build"])
    cmd = capture_cmd[-1]
    denied = cmd[cmd.index("--disallowedTools") + 1].split()
    for pattern in ("Bash(git:*)", "PowerShell(git:*)", "NotebookEdit",
                    "Write(forge/contracts/**)",
                    "Edit(forge/contracts/**)",
                    "Write(EVIDENCE/chains/**)", "Edit(EVIDENCE/chains/**)",
                    "Write(.claude/**)", "Edit(.claude/**)"):
        assert pattern in denied, f"pattern manquant dans la deny-list: {pattern}"

    # Zone `tests/` DU STUDIO : on vérifie la PROPRIÉTÉ (elle est protégée en écriture
    # ET en édition), pas la forme littérale du motif — figer la chaîne exacte a fait
    # échouer ce test lors de son ancrage à la racine le 2026-07-28 alors que la
    # protection était intacte (règle d'usine n°3 : un test vérifie une propriété
    # durable, pas une valeur historique). Formes acceptées : `tests/**` (historique)
    # ou `./tests/**` (ancrée racine, ratifiée Pierre 2026-07-28 — le motif nu bloquait
    # aussi `GAMES/<jeu>/tests/`, chemin exigé par godot_oracle.mjs).
    for verbe in ("Write", "Edit"):
        assert any(
            d.startswith(f"{verbe}(") and d.rstrip(")").endswith("tests/**") for d in denied
        ), f"la zone protegee tests/ n'est plus deniee en {verbe} : {denied}"


def test_deny_git_par_classe_aucune_regle_par_commande_orpheline():
    """R1 : plus AUCUNE règle git par commande (git add:*, git commit:*, …) — une
    liste une-par-une laissait passer checkout/branch/restore/apply/worktree…
    hérités de l'allow-list de .claude/settings.local.json."""
    assert "Bash(git:*)" in run_real._STEP_DISALLOWED
    assert "PowerShell(git:*)" in run_real._STEP_DISALLOWED
    for rule in run_real._STEP_DISALLOWED:
        assert not re.search(r"git \w", rule), (
            f"règle git par commande orpheline (déni par classe attendu) : {rule}")


def test_notebookedit_denie_en_entier():
    """R1 : NotebookEdit = outil ENTIER dans la deny-list (pas un motif de
    chemins) — acceptEdits l'auto-approuverait sinon sur des chemins protégés."""
    assert "NotebookEdit" in run_real._STEP_DISALLOWED


def test_disallowed_pose_meme_sans_outils_panel_compris(tmp_path, capture_cmd):
    """Le panel Prisme (make_panel_claude_call) passe par _claude_call_raw sans
    tools : la deny-list doit être posée là aussi (F1b : TOUTES les étapes)."""
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    cmd = capture_cmd[-1]
    assert "--disallowedTools" in cmd
    assert "--permission-mode" in cmd  # manual conservé pour le chemin sans tools


# --- R2 : isolation MCP sur TOUT appel claude -p ------------------------------------

def test_strict_mcp_config_pose_sur_tout_appel(tmp_path, capture_cmd):
    """R2 : --strict-mcp-config (vérifié dans `claude --help` local) SANS aucun
    --mcp-config = zéro serveur MCP — les builders n'héritent pas des serveurs
    MCP projet/utilisateur (studio-brain, computer-use, …)."""
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    cmd = capture_cmd[-1]
    assert "--strict-mcp-config" in cmd
    assert "--mcp-config" not in cmd  # aucun serveur de substitution fourni

    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path,
                              tools=run_real._STEP_TOOLS["s9-build"])
    assert "--strict-mcp-config" in capture_cmd[-1]  # chemin avec outils aussi


# --- F2a : validation de schéma AVANT écriture --------------------------------------

def test_blueprint_sans_modules_rejete_aucun_fichier_ecrit(tmp_path):
    res = run_real._materialize_artifact(
        "s4-archi", '```json\n{"note": "je suis un blueprint trivialement vert"}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "modules" in res["reason"]
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_blueprint_modules_vides_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s4-archi", '```json\n{"modules": [], "deps_interdites": []}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_blueprint_deps_malformees_rejete_aucun_fichier_ecrit(tmp_path):
    """La str 'ui->engine' (au lieu de la paire) faisait crash-looper le driver."""
    res = run_real._materialize_artifact(
        "s4-archi",
        '```json\n{"modules": ["ui"], "deps_interdites": ["ui->engine"]}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "deps_interdites" in res["reason"]
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_blueprint_ownership_non_dict_rejete(tmp_path):
    # deps_interdites non vide (R3) pour que le test exerce bien le check ownership.
    res = run_real._materialize_artifact(
        "s4-archi",
        '```json\n{"modules": ["ui"], "deps_interdites": [["ui", "engine"]], '
        '"ownership": "tout"}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "ownership" in res["reason"]


def test_blueprint_valide_avec_ownership_dict_ecrit(tmp_path):
    res = run_real._materialize_artifact(
        "s4-archi",
        '```json\n{"modules": ["ui"], "deps_interdites": [["ui", "engine"]], '
        '"ownership": {"ui/main.mjs": "s9"}}\n```',
        tmp_path / "run")
    assert res is None
    assert (tmp_path / "run" / "blueprint.json").exists()


def test_blueprint_deps_interdites_vides_rejete_avant_ecriture(tmp_path):
    """R3 : deps_interdites [] rend check_architecture vacuement vert (prouvé
    par sonde : zéro paire => zéro violation possible) — rejeté AVANT toute
    écriture, avec le message pédagogique fog HumanGate."""
    res = run_real._materialize_artifact(
        "s4-archi", '```json\n{"modules": ["ui"], "deps_interdites": []}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "deps_interdites" in res["reason"]
    assert "logique→rendu" in res["reason"]       # séparation minimale exigée
    assert "fog HumanGate" in res["reason"]        # pédagogie : fog, pas oracle vide
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_blueprint_deps_interdites_absentes_rejete_avant_ecriture(tmp_path):
    """R3 : deps_interdites est OBLIGATOIRE — un blueprint qui l'omet est rejeté
    au même titre qu'une liste vide (jamais un défaut silencieux [])."""
    res = run_real._materialize_artifact(
        "s4-archi", '```json\n{"modules": ["ui"]}\n```', tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "deps_interdites" in res["reason"]
    assert "OBLIGATOIRE" in res["reason"]
    assert not (tmp_path / "run" / "blueprint.json").exists()


def test_wiremap_sans_features_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s5-wiremap", '```json\n{"features": []}\n```', tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert not (tmp_path / "run" / "wiremap.json").exists()


def test_wiremap_feature_sans_champs_obligatoires_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s5-wiremap", '```json\n{"features": [{"feature": "R1"}]}\n```',
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "fichiers" in res["reason"]
    assert not (tmp_path / "run" / "wiremap.json").exists()


def _wiremap_fenced(**overrides):
    """Bloc fenced d'une wiremap à UNE feature valide, champs surchargés."""
    feat = {"feature": "R1 boot", "fonction": "boot",
            "fichiers": ["main.mjs"], "preuve": "test_boot"}
    feat.update(overrides)
    return "```json\n" + json.dumps({"features": [feat]}) + "\n```"


def test_wiremap_fonction_vide_rejetee_avant_ecriture(tmp_path):
    """R4 : fonction '' fait sauter la vérification d'existence de check_wiremap
    (static_oracles.py `if fonction:`) — wiremap creuse prouvée verte par sonde.
    Rejet AVANT écriture, pour '' comme pour les blancs."""
    for fonction in ("", "   "):
        res = run_real._materialize_artifact(
            "s5-wiremap", _wiremap_fenced(fonction=fonction), tmp_path / "run")
        assert res is not None and res["ok"] is False
        assert "fonction" in res["reason"]
        assert "NON VIDE" in res["reason"]
    assert not (tmp_path / "run" / "wiremap.json").exists()


def test_wiremap_fichiers_vides_rejetes_avant_ecriture(tmp_path):
    """R4 : fichiers [] OU [''] = feature qui ne pointe aucun fichier réel —
    invérifiable, rejetée avant écriture (jamais un artefact creux posé)."""
    for fichiers in ([], [""], ["main.mjs", " "]):
        res = run_real._materialize_artifact(
            "s5-wiremap", _wiremap_fenced(fichiers=fichiers), tmp_path / "run")
        assert res is not None and res["ok"] is False
        assert "fichiers" in res["reason"]
    assert not (tmp_path / "run" / "wiremap.json").exists()


# --- F2b : check_architecture ne lève plus sur deps malformé ------------------------

def test_check_architecture_deps_str_fail_honnete_sans_exception(tmp_path):
    rep = check_architecture(
        {"modules": ["ui"], "deps_interdites": ["ui->engine"]}, tmp_path)
    assert rep["passed"] is False
    assert "malform" in rep["raison"]


def test_check_architecture_deps_non_liste_fail_honnete(tmp_path):
    rep = check_architecture(
        {"modules": ["ui"], "deps_interdites": "ui->engine"}, tmp_path)
    assert rep["passed"] is False
    assert "malform" in rep["raison"]


def test_check_architecture_valide_inchange(tmp_path):
    (tmp_path / "main.py").write_text("import os\n", encoding="utf-8")
    rep = check_architecture(
        {"modules": ["main"], "deps_interdites": [["ui", "engine"]]}, tmp_path)
    assert rep["passed"] is True
    assert "raison" not in rep  # forme du résultat sain inchangée


# --- F4 : chaînage des artefacts amont ----------------------------------------------

def _run_dir_avec_amont(tmp_path):
    run_dir = tmp_path / "run"
    (run_dir / "artifacts").mkdir(parents=True)
    (run_dir / "artifacts" / "s3-decompo.txt").write_text(
        "DECOMPO R1 bouger R2 gagner", encoding="utf-8")
    # R3 : deps_interdites non vide — fixture alignée sur le schéma exigé.
    (run_dir / "blueprint.json").write_text(
        json.dumps({"modules": ["game"],
                    "deps_interdites": [["logique", "rendu"]]}), encoding="utf-8")
    (run_dir / "wiremap.json").write_text(
        json.dumps({"features": [{"feature": "R1 bouger", "fonction": "move",
                                  "fichiers": ["game.mjs"], "preuve": "t"}]}),
        encoding="utf-8")
    return run_dir


def test_s5_recoit_la_sortie_s3_et_le_blueprint(tmp_path, capture_calls):
    calls, _ = capture_calls
    run_dir = _run_dir_avec_amont(tmp_path)
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s5-wiremap"), None, _context(run_dir))
    prompt = calls[-1]["prompt"]
    assert "## ARTEFACTS AMONT (run_dir)" in prompt
    assert "DECOMPO R1 bouger R2 gagner" in prompt
    assert '"deps_interdites"' in prompt  # contenu blueprint.json injecté


def test_s9_recoit_blueprint_et_wiremap_avec_chemins_reels(tmp_path, capture_calls):
    calls, _ = capture_calls
    run_dir = _run_dir_avec_amont(tmp_path)
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build"), None, _context(run_dir))
    prompt = calls[-1]["prompt"]
    assert str(run_dir / "blueprint.json") in prompt   # CHEMIN réel run_dir
    assert str(run_dir / "wiremap.json") in prompt
    assert '"R1 bouger"' in prompt                     # contenu wiremap injecté
    assert "ownership" in prompt                        # rappel ownership (s9)


def test_troncature_effective_a_la_borne_declaree(tmp_path, capture_calls):
    calls, _ = capture_calls
    run_dir = _run_dir_avec_amont(tmp_path)
    gros = "X" * (run_real.UPSTREAM_MAX_CHARS + 5000)
    (run_dir / "artifacts" / "s3-decompo.txt").write_text(gros, encoding="utf-8")
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s4-archi"), None, _context(run_dir))
    prompt = calls[-1]["prompt"]
    assert "[tronqué]" in prompt
    assert "X" * run_real.UPSTREAM_MAX_CHARS in prompt
    assert "X" * (run_real.UPSTREAM_MAX_CHARS + 1) not in prompt


def test_etape_sans_amont_disponible_omet_la_section(tmp_path, capture_calls):
    """1re exécution : run_dir vide — la section est omise, jamais une erreur.

    L'étape porteuse est un DÉCOR : la section amont est construite depuis le
    contenu de run_dir, identiquement pour toutes les étapes. `s6-redteam-plan` est
    choisie parce qu'elle ne matérialise aucun artefact déterministe — avec
    `s3-decompo` (entrée dans _ARTIFACT_BY_STEP depuis le 2026-08-04), la sortie
    factice « artefact texte » échouerait à la matérialisation, ce qui ferait
    échouer ce test pour une raison qui n'a rien à voir avec ce qu'il vérifie.
    """
    calls, _ = capture_calls
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s6-redteam-plan"), None, _context(tmp_path / "vide"))
    assert res["ok"] is True
    assert "ARTEFACTS AMONT" not in calls[-1]["prompt"]


# --- F5a : tasks-file fail-fast sur clé inconnue, valeurs vides ignorées -------------

def test_tasks_file_cle_inconnue_fail_fast_avec_cles_valides(tmp_path):
    bad = tmp_path / "tasks.json"
    bad.write_text(json.dumps({"s9_build": "typo underscore"}), encoding="utf-8")
    with pytest.raises(ValueError) as exc:
        run_real.load_tasks_file(bad)
    assert "s9_build" in str(exc.value)
    assert "s9-build" in str(exc.value)        # la liste des clés valides est montrée
    assert "s2.5-artbible" in str(exc.value)   # étapes à profil dédié incluses


def test_tasks_file_valeur_vide_ignoree_ne_masque_pas_le_defaut(tmp_path):
    f = tmp_path / "tasks.json"
    f.write_text(json.dumps({"s9-build": "  ", "s11-redteam-code": "réel"}),
                 encoding="utf-8")
    tasks = run_real.load_tasks_file(f)
    assert tasks == {"s11-redteam-code": "réel"}
    merged = run_real.merge_task_overrides({"s9-build": "défaut"}, {}, tasks)
    assert merged["s9-build"] == "défaut"  # jamais effacé par un '' du fichier


# --- F5b : défauts de tâches PROFILE-AWARE -------------------------------------------

def test_defaut_s9_patch_correctif_different_du_greenfield():
    full = run_real.default_task_by_step("proj", "GAMES/proj", profile="full")
    patch = run_real.default_task_by_step("proj", "GAMES/proj", profile="patch")
    micro = run_real.default_task_by_step("proj", "GAMES/proj", profile="micro")
    assert "Implémente" in full["s9-build"]
    assert "Corrige" in patch["s9-build"]
    assert "ne réécris pas ce qui marche" in patch["s9-build"]
    assert patch["s9-build"] == micro["s9-build"]
    assert patch["s9-build"] != full["s9-build"]


def test_defaut_s9_interdit_le_commit_dans_tous_les_profils():
    """F1c : les « micro-commits » du contrat sont suspendus par l'exécuteur."""
    for profile in ("full", "patch", "micro"):
        s9 = run_real.default_task_by_step("proj", "GAMES/proj", profile=profile)["s9-build"]
        assert "AUCUN commit" in s9


# --- F5c : verify_run reconnaît le marqueur solvability ------------------------------

def test_verify_run_solvability_marque_le_verdict_comme_jeu():
    """Un reçu code portant SEULEMENT la garde solvabilité (posée par le driver
    pour tout jeu) est un verdict de JEU : sans preuve mutation embarquée, il est
    non ratifiable — avant F5c ce marqueur était ignoré (angle mort vs
    driver._effective_is_game)."""
    data = {"run_id": "r", "oracles": {"code": {
        "status": "OK",
        "detail": {"solvability": {"passed": True, "raisons": [], "checked": True}},
    }}}
    # V1 (séparation intégrité/verdict) : _check_mutation_proof rend désormais
    # {problems, status, checked} au lieu d'une liste nue — problems[0] devient
    # result["problems"][0]. Comportement inchangé : sans preuve embarquée, c'est
    # toujours un refus, quel que soit require_green (absence structurelle).
    result = verify_run._check_mutation_proof(data, None)
    assert result["problems"], "verdict de jeu (marqueur solvability) sans preuve mutation doit être rejeté"
    assert "preuve mutation" in result["problems"][0]
    assert result["checked"] is False


def test_verify_run_non_jeu_reste_exempte_de_mutation():
    data = {"run_id": "r", "oracles": {"code": {"status": "OK", "detail": {}}}}
    result = verify_run._check_mutation_proof(data, None)
    assert result["problems"] == []
    assert result["checked"] is False


# --- F5d : garde run_dir périmé ------------------------------------------------------

def test_gel_perime_sans_state_est_refuse(tmp_path):
    (tmp_path / "wiremap_frozen.json").write_text('{"features": ["R1"]}',
                                                  encoding="utf-8")
    reason = run_real.stale_run_dir_reason(tmp_path)
    assert reason is not None
    assert "wiremap_frozen.json" in reason
    assert "state.json" in reason


def test_reprise_legitime_et_run_dir_neuf_acceptes(tmp_path):
    assert run_real.stale_run_dir_reason(tmp_path) is None  # run_dir neuf
    (tmp_path / "wiremap_frozen.json").write_text("{}", encoding="utf-8")
    (tmp_path / "state.json").write_text("{}", encoding="utf-8")
    assert run_real.stale_run_dir_reason(tmp_path) is None  # reprise (state présent)


def test_main_fail_fast_sur_run_dir_perime_et_durcit_la_console(tmp_path, monkeypatch):
    """F5d câblé dans main (fail-fast AVANT le driver) + F3 (_harden_streams appelé
    en tête de main, réutilisé depuis verify_run)."""
    assert run_real._harden_streams is verify_run._harden_streams  # réutilisation F3
    hardened = []
    monkeypatch.setattr(run_real, "_harden_streams", lambda: hardened.append(True))
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    run_dir = tmp_path / "EVIDENCE" / "runs" / "proj"
    run_dir.mkdir(parents=True)
    (run_dir / "wiremap_frozen.json").write_text("{}", encoding="utf-8")
    with pytest.raises(SystemExit):
        run_real.main(["--project", "proj", "--run-id", "r", "--src-root", "src"])
    assert hardened == [True]
