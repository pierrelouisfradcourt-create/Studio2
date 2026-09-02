"""Correctif A — `_FENCED_YAML` (run_real.py) doit reconnaître les fences
```yaml UNIQUEMENT en début de ligne, jamais une mention en prose.

Défaut mesuré (run kitten_clicker-20260821-1312, 2026-08-21) : la sortie réelle
de s0-contrat commence par une ligne de prose contenant « the **last valid
```yaml block** in my output », PUIS, ligne 3, la vraie fence ```yaml et le
charter jusqu'à la fence fermante ligne 53. L'ancienne regex
`r"```ya?ml\\s*(.*?)```"` (non ancrée, paresseuse) matchait depuis la mention
en prose jusqu'à la fence d'OUVERTURE du vrai bloc : `_materialize_yaml`
rendait `{"written": false, "reason": "... le bloc YAML n'est pas un mapping
(reçu str)"}` et `charter.yaml` n'était jamais écrit.

Avant le correctif, les tests (a) et (d) sont ROUGES."""
from __future__ import annotations

import pytest
import yaml

import forge.run_real as run_real


# --- (a) reproduction minimale du cas réel ------------------------------------------

_PROSE_AVANT = (
    "`Write`/`Bash` are disabled for this session — which confirms the ratified "
    "design exactly: the s0 agent has **Read only**, and the executor's "
    "`_materialize_yaml` (M4) is what writes `charter.yaml` to the run_dir from "
    "the **last valid ```yaml block** in my output, then attaches `check_charter`."
)

_CHARTER_MAPPING = {
    "objectif": "Produire un clicker de chatons",
    "hors_scope": ["Multijoueur"],
    "criteres_succes": ["La scène principale se lance sans erreur"],
    "actions_interdites": ["git commit ou git push"],
    "plateforme_cible": "Godot 4.6.3 (desktop)",
    "reference_jeu": "Cookie Clicker + Neko Atsume",
    "criteres_demo": ["Le compteur de ronrons augmente à chaque clic"],
}

_PROSE_APRES = (
    "Ci-dessus le bloc ```yaml``` (conforme au schéma check_charter) — c'est mon "
    "livrable."
)


def _sortie_reelle_reconstituee() -> str:
    bloc = yaml.safe_dump(_CHARTER_MAPPING, allow_unicode=True, sort_keys=False)
    return f"{_PROSE_AVANT}\n\n```yaml\n{bloc}```\n\n{_PROSE_APRES}\n"


def test_prose_mentionnant_yaml_avant_le_vrai_bloc_nempeche_pas_lecriture(tmp_path):
    texte = _sortie_reelle_reconstituee()
    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)
    assert res["written"] is True, res
    charter_path = tmp_path / "charter.yaml"
    assert charter_path.exists()
    data = yaml.safe_load(charter_path.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    assert data["reference_jeu"] == "Cookie Clicker + Neko Atsume"
    for champ in ("objectif", "hors_scope", "criteres_succes", "actions_interdites",
                  "plateforme_cible", "reference_jeu", "criteres_demo"):
        assert champ in data


# --- (b) deux blocs valides -> le DERNIER gagne --------------------------------------

def test_deux_blocs_valides_le_dernier_gagne(tmp_path):
    premier = yaml.safe_dump({"objectif": "PREMIER (ne doit pas gagner)"},
                             allow_unicode=True, sort_keys=False)
    second = yaml.safe_dump(_CHARTER_MAPPING, allow_unicode=True, sort_keys=False)
    texte = f"```yaml\n{premier}```\n\nprose entre les deux blocs\n\n```yaml\n{second}```\n"
    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)
    assert res["written"] is True, res
    data = yaml.safe_load((tmp_path / "charter.yaml").read_text(encoding="utf-8"))
    assert data["objectif"] != "PREMIER (ne doit pas gagner)"
    assert data["reference_jeu"] == "Cookie Clicker + Neko Atsume"


# --- (c) aucun bloc -> written False, raison explicite --------------------------------

def test_aucun_bloc_yaml_ecrit_rien_avec_raison(tmp_path):
    res = run_real._materialize_yaml("s0-contrat", "juste de la prose, aucune fence", tmp_path)
    assert res["written"] is False
    assert "aucun bloc" in res["reason"]
    assert not (tmp_path / "charter.yaml").exists()


# --- (d) le cas RÉEL, si l'artefact archivé existe -------------------------------------

def _chemins_artefact_reel():
    racine = run_real.REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker"
    return [
        racine / "_run1_20260821-1312" / "artifacts" / "s0-contrat.txt",
        racine / "artifacts" / "s0-contrat.txt",
    ]


def test_cas_reel_kitten_clicker_s0_contrat(tmp_path):
    """SAS MOTEUR (GO Pierre 2026-09-01, C-a) — assertion MISE À JOUR, signalée
    explicitement : cette fixture réelle unique-bloc, mesurée en re-vérifiant le
    test contre le corpus, contient déjà des items de liste non quotés portant un
    « : » (ex. « Portage mobile / tactile ou build web : la cible est... ») —
    YAML les parse comme des mappings à une clé, pas des chaînes, ce que
    `check_charter` rejette à bon droit (`hors_scope[2]/[4]/[5]`,
    `criteres_succes[2]/[4]` « absent ou vide »). Avant ce correctif, ce défaut
    de la fixture était INVISIBLE : `check_charter` tournait déjà (reçu
    `res["check"]`) mais restait ADVISORY — le fichier s'écrivait quand même
    (`written: True`), l'assertion de ce test ne regardait jamais le verdict du
    check. Le correctif C-a rend ce même défaut BLOQUANT (comportement voulu :
    un charter qui échoue check_charter ne doit plus jamais être matérialisé,
    unique bloc ou non) — ce test prouve désormais le refus, motifs inclus,
    plutôt que l'ancienne écriture silencieuse d'un charter déjà invalide."""
    chemin = next((p for p in _chemins_artefact_reel() if p.exists()), None)
    if chemin is None:
        pytest.skip("artefact réel s0-contrat.txt introuvable (aucun des deux chemins "
                    "connus) — non copié dans le dépôt, cf. consigne")
    texte = chemin.read_text(encoding="utf-8")
    res = run_real._materialize_yaml("s0-contrat", texte, tmp_path)
    assert res["ok"] is False, res
    assert res["written"] is False
    assert "non matérialisable" in res["reason"]
    assert "hors_scope" in res["reason"] or "criteres_succes" in res["reason"]
    assert not (tmp_path / "charter.yaml").exists()

    from forge.driver import _is_materialize_refusal_reason
    assert _is_materialize_refusal_reason(res["reason"]) is True
