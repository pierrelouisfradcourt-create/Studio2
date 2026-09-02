# Lignee CAUSALITE — `next_reason` : TRANSPORT d'une cause, jamais une decision.
#
# Dette de preuve fermee ici. Deux contrats au moins exigent ce champ
# (s10a-oracle-code §64, s12-verdict §65 : « pourquoi le niveau superieur doit agir OU
# pourquoi la chaine causale est FERMEE ») ; avant cette lignee, 0 ligne de code le
# lisait — le dernier champ de la doctrine des quatre lignees causales sans destinataire.
# La lignee etait CABLEE (parseur + ecriture dans l'etat + lecture par l'escalade) mais
# AUCUN test ne couvrait son comportement neuf : les deux seuls fichiers citant ses
# symboles sont anterieurs et ne mentionnent jamais `next_reason`.
#
# Ces tests portent sur ce que le code PROMET dans ses docstrings — transporter et rendre
# visible, rien de plus — jamais sur une intention supposee.
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _oracle_config(tmp_path: Path, project: str = "proj") -> Path:
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", "import sys; sys.exit(0)"]}}),
        encoding="utf-8")
    return cfg


def _kwargs(tmp_path: Path, run_dir: Path) -> dict:
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )


class ReasonExecutor:
    """Exécuteur factice dont la sortie porte le bloc de lignée en FIN de rapport,
    comme le prescrit la règle de restitution des contrats."""

    def __init__(self, reason_line: str = "next_reason: oracle rouge sur core.render"):
        self.reason_line = reason_line

    def __call__(self, payload, decision, context):
        return {"ok": True,
                "output": f"artefact {payload.etape}\n\n## LIGNEE\n{self.reason_line}\n"}


# --- (1) extraction : le parseur lit ce que les contrats prescrivent ---------------

def test_extraction_forme_simple():
    out = "rapport\nnext_reason: le budget mutation n'est pas mesure\n"
    assert ForgeDriver._parse_next_reason(out) == "le budget mutation n'est pas mesure"


def test_extraction_tolere_la_decoration_markdown():
    """Le worker ecrit souvent en gras ou en bloc : la cause ne doit pas etre perdue
    pour une etoile (meme famille que l'incident `_extract_return_reason`)."""
    for forme in ("**next_reason**: cause reelle",
                  "> next_reason : cause reelle",
                  "- `next_reason`: cause reelle",
                  "#### NEXT_REASON: cause reelle"):
        assert ForgeDriver._parse_next_reason(forme) == "cause reelle", forme


def test_extraction_cle_seule_valeur_sur_la_ligne_suivante():
    out = "next_reason:\n\n    la chaine causale est FERMEE\n"
    assert ForgeDriver._parse_next_reason(out) == "la chaine causale est FERMEE"


# --- (4) l'absence reste distinguable d'une valeur valide -------------------------

def test_absence_rend_une_chaine_vide_jamais_une_valeur_fabriquee():
    assert ForgeDriver._parse_next_reason("") == ""
    assert ForgeDriver._parse_next_reason("rapport sans bloc de lignee") == ""


def test_decoration_seule_n_est_PAS_une_raison():
    """`**`, `---`, une cloture de bloc : aucun caractere alphanumerique => vide.
    Transporter cela comme une cause serait fabriquer une information."""
    for creux in ("next_reason: **", "next_reason: ---", "next_reason: ``"):
        assert ForgeDriver._parse_next_reason(creux) == "", creux


def test_valeur_bornee_a_400_caracteres():
    long = "x" * 900
    assert len(ForgeDriver._parse_next_reason(f"next_reason: {long}")) == 400


# --- (2) survie dans l'etat ET dans le recu d'etape --------------------------------

def test_next_reason_survit_dans_l_etat_et_dans_le_recu(tmp_path, offline):
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-1", profile="micro", executor=ReasonExecutor(),
                **_kwargs(tmp_path, run_dir)).run()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    entry = state["steps"]["s9-build"]
    assert entry["next_reason"] == "oracle rouge sur core.render"
    assert entry["detail"]["next_reason"] == "oracle rouge sur core.render", (
        "la cause doit vivre AUSSI dans le detail — c'est lui qui part au recu signe")


def test_sortie_sans_cause_n_ecrit_aucun_champ(tmp_path, offline):
    """L'absence n'est pas une valeur vide stockee : le champ n'existe pas du tout."""
    class Muet:
        def __call__(self, payload, decision, context):
            return {"ok": True, "output": f"artefact {payload.etape}"}

    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-2", profile="micro", executor=Muet(),
                **_kwargs(tmp_path, run_dir)).run()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    entry = state["steps"]["s9-build"]
    assert "next_reason" not in entry
    assert "next_reason" not in entry["detail"]


# --- (3) la cause atteint effectivement l'escalade ---------------------------------

def test_l_escalade_rend_la_cause_du_builder_durable(tmp_path, offline):
    """BRANCHEMENT 3 : `_maybe_escalate` LIT le next_reason du builder et le depose
    dans `humangate_notes` — il le MONTRE la ou quelqu'un decide, sans s'en servir
    pour decider. Deduplique : rejouer n'empile pas la meme note."""
    run_dir = tmp_path / "run"
    drv = ForgeDriver("proj", "proj-3", profile="micro", executor=ReasonExecutor(),
                      **_kwargs(tmp_path, run_dir))
    state = {"steps": {"s9-build": {"status": "OK",
                                    "next_reason": "budget mutation non mesure",
                                    "detail": {"output_excerpt": ""}},
                       "s10a-oracle-code": {"status": "FAIL", "detail": {}}}}
    drv._maybe_escalate(state)
    notes = state.get("humangate_notes", [])
    assert any("next_reason de s9-build: budget mutation non mesure" in n for n in notes), notes
    drv._maybe_escalate(state)
    assert sum("budget mutation non mesure" in n for n in notes) == 1, "note dedupliquee"


def test_escalade_sans_cause_ne_fabrique_aucune_note(tmp_path, offline):
    run_dir = tmp_path / "run"
    drv = ForgeDriver("proj", "proj-4", profile="micro", executor=ReasonExecutor(),
                      **_kwargs(tmp_path, run_dir))
    state = {"steps": {"s9-build": {"status": "OK", "detail": {"output_excerpt": ""}},
                       "s10a-oracle-code": {"status": "FAIL", "detail": {}}}}
    drv._maybe_escalate(state)
    assert not any("next_reason" in n for n in state.get("humangate_notes", []))
