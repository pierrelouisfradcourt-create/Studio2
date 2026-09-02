"""Oracle P5 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §07) : un
champ `reason` optionnel enregistre le WHY d'activation d'une étape sur la
ligne Context Manifest `kind: dispatch` — jusqu'ici, NI `activation` (compteur
de tentatives) NI `ts` (horloge) ne le portaient, et seule l'escalade (P3)
avait un motif, perdu au succès avant ce lot.

`prepare_dispatch(..., reason="")` par défaut (appel direct, tests, dry-run) ;
le DRIVER (seul appelant réel en production, `forge.driver`) passe toujours
`"ordre de profil"` explicitement à ses deux points d'appel — c'est CE
patron-là qui est vérifié ici, pas un défaut caché dans `prepare_dispatch`
lui-même. La porte (validation C1/C2, refus/accepte) est STRICTEMENT
inchangée — vérifié par non-régression sur le comportement déjà couvert par
`test_dispatch.py` (fichier existant, non modifié par ce lot).

Fichier NEUF (forge/tests/**, régime studio normal). NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json

import pytest

from forge.contract import ContractIncomplete
from forge.dispatch import prepare_dispatch
from forge.driver import ForgeDriver


def _manifest_reason(tmp_path, run_dir, etape, run_id):
    from forge import context_manifest as cm
    rec = json.loads(
        cm.manifest_path(run_dir, etape).read_text(encoding="utf-8").strip().splitlines()[-1]
    )
    return rec


# --- reason personnalisé / défaut sur un appel direct de la porte -----------------

def test_prepare_dispatch_reason_personnalise_atteint_le_manifeste(tmp_path):
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s4-archi", run_id="run-reason-1", audit_path=audit, run_dir=run_dir,
                     reason="motif custom de test")
    rec = _manifest_reason(tmp_path, run_dir, "s4-archi", "run-reason-1")
    assert rec["reason"] == "motif custom de test"


def test_prepare_dispatch_sans_reason_produit_une_chaine_vide_dans_le_manifeste(tmp_path):
    """Appel BRUT de la porte (comme tous les appels historiques) sans `reason` :
    le champ reste additif et présent, valant "" — jamais une valeur devinée."""
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s4-archi", run_id="run-reason-2", audit_path=audit, run_dir=run_dir)
    rec = _manifest_reason(tmp_path, run_dir, "s4-archi", "run-reason-2")
    assert rec["reason"] == ""


# --- le driver passe toujours "ordre de profil" (ses deux points d'appel) --------

def _oracle_config(tmp_path, project, exit_code=0):
    import sys
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


class StubExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def test_driver_passe_ordre_de_profil_sur_ses_deux_points_dappel(tmp_path, offline):
    """`_run_llm` (étape LLM, s9-build) ET `_run_deterministic` (étape non-LLM,
    s10a-oracle-code) doivent tous les deux porter une CAUSE STRUCTURÉE — les
    deux points d'appel de la porte, aucun oublié.

    ÉVOLUTION 2026-08-06 (gate Pierre) — Activation Lineage, doctrine
    `docs/forge/FORGE_CAUSAL_LINEAGE_V2.md` §2. Cette assertion portait le
    littéral `"ordre de profil"`. Le lot P5 l'avait choisi *faute de mieux* —
    sa propre docstring le dit : « aucune autre source de WHY dynamique dans ce
    lot ». La doctrine fournit désormais cette source, donc le littéral est
    REMPLACÉ, pas contredit.

    Ce que cette version protège EN PLUS de l'ancienne :
      - les deux points d'appel émettent toujours (invariant P5 conservé) ;
      - la cause est STRUCTURÉE, donc relisible par un consommateur ;
      - et surtout : quand aucune cause n'est mesurée — c'est le cas ici, le
        driver enchaîne mécaniquement l'ordre du profil — le champ vaut
        `NOT_TRANSMITTED` et JAMAIS une cause fabriquée. Une cause inventée est
        une violation de causalité, même famille qu'un `validated_by` fabriqué
        (incident du 2026-08-03). L'ancien littéral ne testait pas ce point.
    """
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
               run_dir=run_dir, oracle_config=_oracle_config(tmp_path, "proj"),
               key_file=tmp_path / "forge_test.key", audit_path=tmp_path / "audit.jsonl",
               telemetry_path=tmp_path / "telemetry.jsonl",
               builder_runs_path=tmp_path / "builder_runs.jsonl",
               journal_path=tmp_path / "journal.jsonl").run()

    llm_rec = _manifest_reason(tmp_path, run_dir, "s9-build", "proj-1")
    det_rec = _manifest_reason(tmp_path, run_dir, "s10a-oracle-code", "proj-1")

    for rec, etape in ((llm_rec, "s9-build"), (det_rec, "s10a-oracle-code")):
        cause = rec["reason"]
        # 1. les deux points d'appel émettent (invariant P5, conservé)
        assert cause, f"{etape}: aucune cause émise — un point d'appel oublié"
        # 2. la cause est structurée, donc consommable
        assert isinstance(cause, dict), f"{etape}: cause structurée attendue, reçu {type(cause)}"
        # 3. elle nomme l'action qu'elle active
        assert cause.get("action") == etape
        # 4. AUCUNE cause n'est mesurée ici (enchaînement mécanique du profil) :
        #    le driver doit le DÉCLARER, jamais fabriquer un problème ou un oracle.
        assert cause.get("status") == "NOT_TRANSMITTED", (
            f"{etape}: sans cause mesurée, le driver doit déclarer NOT_TRANSMITTED"
        )
        for invente in ("problem", "oracle", "root_cause"):
            assert invente not in cause, (
                f"{etape}: champ {invente!r} présent alors qu'aucune cause n'est mesurée "
                "— une cause fabriquée est une violation de causalité"
            )


# --- non-régression : la porte accepte/refuse exactement comme avant -------------

def test_reason_najoute_aucun_refus_ni_relaxation_de_la_porte(tmp_path):
    """Un `reason` fourni ne doit JAMAIS influencer C1/C2 : un profil qui
    exclut l'étape refuse toujours, avec ou sans reason (même exception)."""
    audit = tmp_path / "audit.jsonl"
    with pytest.raises(ContractIncomplete):
        prepare_dispatch("s0-contrat", run_id="run-reason-3", audit_path=audit,
                         profile="patch", reason="motif qui ne doit rien changer")


def test_unknown_step_still_raises_with_reason_supplied(tmp_path):
    with pytest.raises(FileNotFoundError):
        prepare_dispatch("s99-inexistant", run_id="x", audit_path=tmp_path / "a.jsonl",
                         reason="motif custom")
