"""Chantier RAISONNEMENT (mission d'outillage 2026-07-30, dernière boucle avant
le gel du tronc — docs/fvl/FVL_PHASE_0_5_CHARTER.md §4, ligne « 5. RAISONNEMENT :
d'abord tracer le paramètre, ensuite rendre le mécanisme effectif »).

Le socle d'observation (`forge.reasoning_observability`) avait déjà PROUVÉ :
  (a) que `claude -p` documente `--effort <level>` (claude --help, fixture réelle) ;
  (b) que `forge.run_real._claude_call_raw` ne le construisait PAS encore — cf. son
      propre docstring, « aucun --effort n'est ajouté... fichier non modifié » —
      et son test `test_cablage_b_PRODUCTION_cmd_reelle_de_claude_call_raw`
      (modèles bruts 'sonnet'/'haiku', qui ne correspondent à AUCUN id complet de
      roles.yaml — donc restent ABSENTS même après ce câblage, cf. plus bas).

Ce fichier prouve que le mécanisme est maintenant RÉELLEMENT effectif — même seam
`capture_cmd` que `tests/test_run_real_hardening.py` (monkeypatch de
`subprocess.run`, aucun spawn réel, aucun coût) — SANS qu'aucune valeur de
`roles.yaml` n'ait changé : ce qui était déjà déclaré (`claude-opus-4-8` ->
`reasoning: high`, `qwen2.5-14b-instruct` -> `reasoning: false`) est simplement
devenu transmis. Mesure de PRODUCTION (roles.yaml réel), même philosophie que
`test_PRODUCTION_roles_yaml_reel` de `test_reasoning_observability.py` : ce test
casse si roles.yaml change de forme — c'est voulu.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json

import pytest

import forge.run_real as run_real


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


# --- résolution pure (aucun subprocess) --------------------------------------

def test_effort_resout_high_pour_un_modele_reellement_declare_high():
    """PRODUCTION (roles.yaml réel) : claude-opus-4-8 déclare reasoning: high —
    la résolution doit rendre 'high', jamais deviné ni recalculé autrement."""
    assert run_real._effort_flag_for_model("claude-opus-4-8") == "high"


def test_effort_resout_low_pour_le_builder_haiku_reel():
    assert run_real._effort_flag_for_model("claude-haiku-4-5-20251001") == "low"


def test_effort_absent_pour_un_role_not_applicable():
    """qwen2.5-14b-instruct déclare reasoning: false (not_applicable) — AUCUN
    flag. Défense en profondeur : _claude_call_raw n'est jamais invoqué pour ce
    provider en production (decision.runner in {claude, claude-blind}
    seulement), mais la fonction de résolution elle-même doit refuser aussi,
    pas seulement compter sur ses appelants."""
    assert run_real._effort_flag_for_model("qwen2.5-14b-instruct") is None
    assert run_real._effort_flag_for_model("non-llm") is None  # déterministe


def test_effort_absent_pour_un_modele_non_resolu_NEGATIF():
    """Test NÉGATIF : un nom qui ne correspond à AUCUN id de roles.yaml (alias
    de palier nu post-escalade type 'opus'/'sonnet', ou les modèles de test
    'haiku' déjà utilisés par test_run_real_hardening.py) ne doit JAMAIS
    deviner une valeur — None, pas une exception, pas un défaut inventé."""
    assert run_real._effort_flag_for_model("opus") is None
    assert run_real._effort_flag_for_model("sonnet") is None
    assert run_real._effort_flag_for_model("haiku") is None
    assert run_real._effort_flag_for_model("n-existe-pas") is None


# --- câblage réel dans la commande construite (seam capture_cmd) -------------

def test_effort_present_dans_cmd_pour_un_modele_cli_compatible(tmp_path, capture_cmd):
    """LE test du chantier : --effort apparaît dans la commande RÉELLEMENT
    construite par _claude_call_raw pour un modèle CLI-compatible réel — ce
    test ÉCHOUERAIT si le câblage était retiré (preuve négative explicite du
    branchement, comme exigé par la mission)."""
    run_real._claude_call_raw("p", "claude-opus-4-8", add_dir=tmp_path, tools=())
    cmd = capture_cmd[-1]
    assert "--effort" in cmd
    assert cmd[cmd.index("--effort") + 1] == "high"


def test_effort_absent_dans_cmd_pour_provider_non_cli(tmp_path, capture_cmd):
    """Preuve exigée #3 (« ABSENT pour les providers non-CLI ») : un appel
    construit avec le nom réel du modèle Qwen — hypothétique, _claude_call_raw
    n'est jamais invoqué pour ce provider en production — ne porte AUCUN
    --effort, même en défense en profondeur."""
    run_real._claude_call_raw("p", "qwen2.5-14b-instruct", add_dir=tmp_path, tools=())
    cmd = capture_cmd[-1]
    assert "--effort" not in cmd


def test_effort_absent_dans_cmd_pour_modele_non_resolu_comportement_inchange(tmp_path, capture_cmd):
    """Non-régression : un nom de modèle qui ne résout à rien (alias de palier
    nu 'haiku', identique aux fixtures déjà utilisées par
    test_run_real_hardening.py et test_reasoning_observability.py) ne reçoit
    AUCUN --effort — comportement STRICTEMENT IDENTIQUE à avant ce chantier
    pour ces cas précis (c'est ce qui garde ces deux fichiers de tests verts
    sans y toucher)."""
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path,
                              tools=run_real._STEP_TOOLS["s9-build"])
    cmd = capture_cmd[-1]
    assert "--effort" not in cmd


def test_effort_ne_perturbe_pas_le_reste_de_la_commande(tmp_path, capture_cmd):
    """Forme de la commande : --effort apparaît une seule fois, la commande
    reste PAR AILLEURS identique (--strict-mcp-config, --disallowedTools,
    --allowedTools toujours présents et bien formés) — aucune régression des
    correctifs red-team antérieurs (F1/F1b/R1/R2)."""
    run_real._claude_call_raw("p", "claude-opus-4-8", add_dir=tmp_path,
                              tools=run_real._STEP_TOOLS["s9-build"])
    cmd = capture_cmd[-1]
    assert cmd.count("--effort") == 1
    assert "--strict-mcp-config" in cmd
    assert "--disallowedTools" in cmd
    allowed = cmd[cmd.index("--allowedTools") + 1].split()
    assert set(allowed) == {"Write", "Edit", "Read", "Bash(node:*)"}
