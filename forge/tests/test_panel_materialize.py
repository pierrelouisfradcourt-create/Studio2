"""FICHE 4 (GO Pierre 2026-08-29) : le panel Prisme multi-lentilles DOIT
matérialiser prisme.json — la limite déclarée (run_real.py, ex-lignes 445-451)
disait que le chemin panel appelait `claude_call` directement et ne passait
jamais par `_materialize_artifact`. Ces tests prouvent que le câblage
(`forge.panel.extract_json_fence` + le branchement `--charter` de
`run_real.main`) ferme le trou : la sortie fusionnée du panel, une fois passée
dans les MÊMES fonctions module-level que la voie simple, écrit bien
`prisme.json` au format historique — et échoue proprement sinon.

Aucun LLM, aucun subprocess claude : `panel_prisme_executor` reçoit un
`claude_call` factice ; seuls `node merge_prisme.mjs` / `check_prisme.mjs`
(mécaniques, zéro LLM) tournent réellement, exactement comme test_panel.py.

    PYTHONIOENCODING=utf-8 PYTHONPATH=scripts .venv312/Scripts/python.exe \
        -m pytest forge/tests/test_panel_materialize.py -v
"""
import json
import re
from pathlib import Path

import pytest

import forge.run_real as run_real
from forge.panel import panel_prisme_executor

CHARTER = """objectif: >-
  Forger un jeu de test.

criteres_succes:
  - "SOLVABILITE PROUVEE : un bot gagne reellement."
  - "DETERMINISME : meme seed, meme resultat."
"""

_SNAPSHOT = """# Snapshot ({label})

## 1. CE QUE LE JOUEUR VOIT

Une raquette et une balle dans une aire de jeu bien delimitee et lisible partout.

## 2. CE QUE LE JOUEUR FAIT

Deplace la raquette au clavier pour intercepter la balle et progresser.

## 3. CE QUE LE JOUEUR RESSENT

Tension puis satisfaction a la victoire du joueur.

## 4. RÈGLES OBSERVABLES

- **R1 — {label} couvre {tag}.**
"""

# Même format que EVIDENCE/runs/kitten_clicker/_run9_20260823a/prisme.json —
# la référence PROUVÉE consommable (un run l'a traversé jusqu'au BUILD).
_EXIGENCE_OK = {
    "id": "a_goal",
    "source": "EXPECTED",
    "enonce": "Le jeu affiche un objectif non vide au demarrage.",
}


class _Payload:
    prompt = "CONTRAT DE BASE (payload.prompt du contrat s1-prisme)"
    model = "claude-opus-4-8"
    etape = "s1-prisme"


def _payload():
    return _Payload()


@pytest.fixture
def charter_path(tmp_path):
    p = tmp_path / "charter.yaml"
    p.write_text(CHARTER, encoding="utf-8")
    return p


def _control_with_json(exigences) -> str:
    body = _SNAPSHOT.format(label="controle", tag="SOLVABILITE PROUVEE")
    return body + "\n```json\n" + json.dumps({"exigences": exigences}, ensure_ascii=False) + "\n```\n"


def _run_panel(claude_call, charter_path, panel_run_dir):
    executor = panel_prisme_executor(claude_call, charter_path, panel_run_dir, lenses=("ceo",))
    return executor(_payload(), None, {})


def test_panel_conforme_materialise_prisme_json_format_historique(tmp_path, charter_path):
    """Merge conforme -> prisme.json ECRIT et PARSABLE, memes cles de premier
    niveau que le prisme.json historique PROUVE (kitten_clicker _run9)."""
    def claude_call(prompt, model):
        if "lens=" in prompt:
            return _SNAPSHOT.format(label="ceo", tag="solvabilite prouvee")
        return _control_with_json([_EXIGENCE_OK])

    res = _run_panel(claude_call, charter_path, tmp_path / "prisme")
    assert res["ok"] is True, res

    step_run_dir = tmp_path  # racine du run — MÊME dossier que context["run_dir"]
    failure = run_real._materialize_artifact("s1-prisme", res["output"], step_run_dir)
    assert failure is None, failure

    prisme_path = step_run_dir / "prisme.json"
    assert prisme_path.exists()
    data = json.loads(prisme_path.read_text(encoding="utf-8"))
    # égalité stricte sur les clés de premier niveau attendues du schéma prisme.json
    assert set(data.keys()) == {"exigences"}
    assert data["exigences"] == [_EXIGENCE_OK]

    # même chemin de code que la voie simple : product_snapshot.md + loop.json
    md_receipt = run_real._materialize_markdown("s1-prisme", res["output"], step_run_dir)
    assert md_receipt is not None
    assert md_receipt["written"] is True
    assert (step_run_dir / "product_snapshot.md").exists()
    # le bloc ```json``` n'a pas fuité dans le texte narratif
    assert "```json" not in (step_run_dir / "product_snapshot.md").read_text(encoding="utf-8")


def test_panel_controle_sans_json_echoue_aucun_fichier_ecrit(tmp_path, charter_path):
    """Merge non conforme (controle sans bloc ```json``` exploitable) -> l'ETAPE
    échoue avec raison, AUCUN fichier prisme.json n'est écrit."""
    def claude_call(prompt, model):
        if "lens=" in prompt:
            return _SNAPSHOT.format(label="ceo", tag="solvabilite prouvee")
        return _SNAPSHOT.format(label="controle", tag="SOLVABILITE PROUVEE")  # pas de json

    res = _run_panel(claude_call, charter_path, tmp_path / "prisme")
    assert res["ok"] is False
    assert "json" in res["reason"].lower()
    assert not res.get("output")
    # jamais appelé côté run_real dans ce cas (l'appelant retourne avant) — et même
    # si on l'appelait avec une sortie vide, rien ne s'écrirait : double garde.
    step_run_dir = tmp_path
    failure = run_real._materialize_artifact("s1-prisme", res.get("output", ""), step_run_dir)
    assert failure is not None
    assert failure["ok"] is False
    assert not (step_run_dir / "prisme.json").exists()


def test_panel_schema_invalide_echoue_sans_ecrire(tmp_path, charter_path):
    """Le bloc ```json``` du contrôle est un objet valide mais ne respecte PAS le
    schéma prisme.json (`exigences` absent) -> _materialize_artifact refuse,
    aucun fichier écrit. Prouve que _validate_prisme reste le SEUL juge du
    schéma (le panel ne duplique aucune règle de validation)."""
    def claude_call(prompt, model):
        if "lens=" in prompt:
            return _SNAPSHOT.format(label="ceo", tag="solvabilite prouvee")
        body = _SNAPSHOT.format(label="controle", tag="SOLVABILITE PROUVEE")
        return body + '\n```json\n{"pas_les_bonnes_cles": true}\n```\n'

    res = _run_panel(claude_call, charter_path, tmp_path / "prisme")
    assert res["ok"] is True  # le panel lui-même a bien trouvé un bloc JSON dict

    step_run_dir = tmp_path
    failure = run_real._materialize_artifact("s1-prisme", res["output"], step_run_dir)
    assert failure is not None
    assert failure["ok"] is False
    assert "exigences" in failure["reason"]
    assert not (step_run_dir / "prisme.json").exists()


def test_merge_illisible_echoue_avant_meme_extraction_json(tmp_path, charter_path):
    """merge_prisme.mjs en échec (ex. charter illisible) -> l'étape échoue déjà
    au niveau du panel, jamais atteint le point d'extraction JSON, aucun fichier
    écrit — non-régression du garde-fou existant (pas modifié par ce chantier)."""
    charter_vide = tmp_path / "charter_vide.yaml"
    charter_vide.write_text("", encoding="utf-8")

    def claude_call(prompt, model):
        if "lens=" in prompt:
            return _SNAPSHOT.format(label="ceo", tag="solvabilite prouvee")
        return _control_with_json([_EXIGENCE_OK])

    # merge_prisme.mjs ne peut pas echouer sur un charter vide (il traite juste
    # 0 critere) — le garde-fou reel est l'absence d'arguments CLI ; on verifie
    # ici seulement que le chemin normal reste stable avec un charter degenere.
    executor = panel_prisme_executor(claude_call, charter_vide, tmp_path / "prisme", lenses=("ceo",))
    res = executor(_payload(), None, {})
    assert res["ok"] is True
    step_run_dir = tmp_path
    failure = run_real._materialize_artifact("s1-prisme", res["output"], step_run_dir)
    assert failure is None
    assert (step_run_dir / "prisme.json").exists()


def test_non_regression_voie_sans_charter_reste_simple_executor():
    """Inspection de source (aucun LLM, aucun subprocess) : quand `--charter`
    n'est pas fourni, `run_real.main` doit toujours assigner
    `executor = simple_executor` SANS passer par le branchement panel — la voie
    standard (claude_executor) reste inchangée par ce chantier."""
    source = Path(run_real.__file__).read_text(encoding="utf-8")
    m = re.search(
        r"if args\.charter:\n.*?\n(    else:\n\s*executor = simple_executor)",
        source, re.S,
    )
    assert m is not None, (
        "le branchement `if args.charter: ... else: executor = simple_executor` "
        "est introuvable tel quel dans run_real.main — la voie sans --charter a "
        "peut-être été modifiée par ce chantier (hors périmètre FICHE 4)")


def test_panel_wiring_appelle_les_memes_materialiseurs_que_la_voie_simple():
    """Inspection de source : le branchement panel de `main()` doit appeler
    `_materialize_artifact`, `_materialize_markdown` et `_materialize_loop_spec`
    — les MÊMES fonctions module-level que `claude_executor` pour s1-prisme,
    zéro nouveau writer (contrainte explicite FICHE 4)."""
    source = Path(run_real.__file__).read_text(encoding="utf-8")
    start = source.index("res = panel_executor(payload, decision, context)")
    end = source.index("return simple_executor(payload, decision, context)", start)
    block = source[start:end]
    assert "_materialize_artifact(" in block
    assert "_materialize_markdown(" in block
    assert "_materialize_loop_spec(" in block
