"""SAS MOTEUR (GO Pierre 2026-09-01) — C-a/C-b : `_materialize_yaml` GATE
désormais l'étape s0-contrat sur un charter non matérialisable, et sélectionne
le bloc ```yaml``` de façon DÉTERMINISTE ET FAIL-CLOSED (plus « dernier bloc
valide »).

Finding n°7 (paire 2) : la sortie s0 de p2_beta contenait DEUX blocs ```yaml```
(le vrai charter, PUIS le bloc RETURN LINEAGE) ; l'ancienne règle « dernier
bloc valide » matérialisait le RETURN LINEAGE comme charter.yaml, et
check_charter FAIL restait ADVISORY (res["yaml_check"]) — la chaîne continuait
18/18 sur le mauvais objet. Fixture réelle :
EVIDENCE/runs/p2_beta/artifacts/s0-contrat.txt (LECTURE SEULE, copiée en
tmp_path).

Nouvelle règle (C-b) : parmi les blocs ```yaml``` qui parsent en mapping,
sélectionner ceux dont check_charter.passed == True.
  - EXACTEMENT UN -> c'est le charter, matérialisé (comportement RETROCOMPATIBLE
    avec un unique bloc valide historique).
  - ZÉRO -> refus de matérialisation (raisons check_charter jointes).
  - PLUSIEURS -> refus « ambiguïté ».

Nouvelle règle (C-a) : un refus de matérialisation N'EST PLUS advisory — il
retourne {"ok": False, "reason": ...}, même contrat que
`_materialize_artifact`/`_materialize_design_questions`, GATE l'étape et arme
le re-spawn du driver (`driver._is_materialize_refusal_reason`).
"""
from __future__ import annotations

import yaml

import forge.run_real as run_real


# --- fixture réelle p2_beta (finding n°7) -------------------------------------------

def _fixture_p2_beta_path():
    return (run_real.REPO_ROOT / "EVIDENCE" / "runs" / "p2_beta"
            / "artifacts" / "s0-contrat.txt")


def test_p2_beta_deux_blocs_le_vrai_charter_est_selectionne(tmp_path):
    """LE test central du chantier : la sortie RÉELLE de p2_beta (2 blocs yaml,
    charter valide en premier, RETURN LINEAGE en second) doit désormais
    matérialiser le VRAI charter (bloc 1), check PASS, étape verte — jamais le
    RETURN LINEAGE."""
    chemin = _fixture_p2_beta_path()
    assert chemin.is_file(), f"fixture réelle introuvable (ne pas déplacer) : {chemin}"
    texte = chemin.read_text(encoding="utf-8")

    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)

    assert res.get("ok") is not False, res
    assert res["written"] is True, res
    assert res["check"]["verdict"] == "PASS", res
    charter_path = tmp_path / "charter.yaml"
    assert charter_path.exists()
    data = yaml.safe_load(charter_path.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    # C'est bien le CHARTER (projet p2_beta) qui a gagné, jamais le RETURN LINEAGE
    # (qui porte why_task_existed/result/proof/learning/next_reason, aucun champ
    # R7 du charter).
    assert data.get("projet") == "p2_beta"
    assert "why_task_existed" not in data
    assert "next_reason" not in data
    for champ in ("objectif", "hors_scope", "criteres_succes", "actions_interdites",
                  "plateforme_cible", "reference_jeu", "criteres_demo"):
        assert champ in data, f"champ R7 manquant : {champ}"


# --- unique bloc, charter FAIL -> refus + motifs + re-spawn armé -------------------

_CHARTER_INCOMPLET = {
    "objectif": "Livrer un jeu",
    # champs R7 manquants : hors_scope, criteres_succes, actions_interdites,
    # plateforme_cible, reference_jeu, criteres_demo
}


def test_unique_bloc_charter_fail_refus_avec_motifs(tmp_path):
    bloc = yaml.safe_dump(_CHARTER_INCOMPLET, allow_unicode=True, sort_keys=False)
    texte = f"Voici le charter.\n\n```yaml\n{bloc}```\n"

    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)

    assert res["ok"] is False, res
    assert res["written"] is False
    assert "non matérialisable" in res["reason"]
    assert "check_charter" in res["reason"] or "FAIL" in res["reason"]
    assert not (tmp_path / "charter.yaml").exists()

    # `_is_materialize_refusal_reason` (driver.py) doit reconnaître ce motif —
    # c'est ce qui arme le re-spawn (C-a).
    from forge.driver import _is_materialize_refusal_reason
    assert _is_materialize_refusal_reason(res["reason"]) is True


# --- deux blocs charter-valides synthétiques -> refus ambiguïté -------------------

_CHARTER_VALIDE_A = {
    "objectif": "Objectif A",
    "hors_scope": ["x"],
    "criteres_succes": ["y"],
    "actions_interdites": ["z"],
    "plateforme_cible": "web",
    "reference_jeu": "Jeu A",
    "criteres_demo": ["demo A"],
}

_CHARTER_VALIDE_B = {
    "objectif": "Objectif B",
    "hors_scope": ["x"],
    "criteres_succes": ["y"],
    "actions_interdites": ["z"],
    "plateforme_cible": "web",
    "reference_jeu": "Jeu B",
    "criteres_demo": ["demo B"],
}


def test_deux_blocs_charter_valides_refus_ambiguite(tmp_path):
    bloc_a = yaml.safe_dump(_CHARTER_VALIDE_A, allow_unicode=True, sort_keys=False)
    bloc_b = yaml.safe_dump(_CHARTER_VALIDE_B, allow_unicode=True, sort_keys=False)
    texte = f"```yaml\n{bloc_a}```\n\nprose\n\n```yaml\n{bloc_b}```\n"

    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)

    assert res["ok"] is False, res
    assert res["written"] is False
    assert "ambiguïté" in res["reason"], res["reason"]
    assert "2" in res["reason"]
    assert not (tmp_path / "charter.yaml").exists()

    from forge.driver import _is_materialize_refusal_reason
    assert _is_materialize_refusal_reason(res["reason"]) is True


# --- un seul bloc valide (cas historique chain_probe/p2_alpha) -> inchangé --------

def test_un_seul_bloc_valide_comportement_inchange(tmp_path):
    bloc = yaml.safe_dump(_CHARTER_VALIDE_A, allow_unicode=True, sort_keys=False)
    texte = f"```yaml\n{bloc}```\n"

    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)

    assert res.get("ok") is not False, res
    assert res["written"] is True, res
    assert res["check"]["verdict"] == "PASS"
    data = yaml.safe_load((tmp_path / "charter.yaml").read_text(encoding="utf-8"))
    assert data["reference_jeu"] == "Jeu A"


# --- zéro bloc -> refus (comportement existant conservé) --------------------------

def test_zero_bloc_refus_comportement_existant(tmp_path):
    res = run_real._materialize_yaml("s0-contrat", "juste de la prose, aucune fence", tmp_path)

    assert res["ok"] is False, res
    assert res["written"] is False
    assert "aucun bloc" in res["reason"]
    assert not (tmp_path / "charter.yaml").exists()


# --- le call-site (executor) GATE désormais sur un refus ---------------------------

def test_call_site_gate_run_real_module_expose_les_deux_branches():
    """Vérification statique légère : le module expose bien les deux clés utilisées
    par le call-site (`_materialize_yaml`/`_YAML_BY_STEP`) — ancre la couture sans
    dépendre d'un run LLM complet (déjà couvert par les tests d'intégration
    existants, test_run_real_*), hors périmètre du sas."""
    assert "s0-contrat" in run_real._YAML_BY_STEP
    assert run_real._YAML_BY_STEP["s0-contrat"] == "charter.yaml"
