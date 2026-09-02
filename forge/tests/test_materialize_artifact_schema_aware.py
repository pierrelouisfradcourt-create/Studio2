"""Oracle TDD — `select_artifact_payload` / `_materialize_artifact` savent choisir,
parmi PLUSIEURS blocs ```json``` fenced, celui qui passe le validateur de l'étape.

Défaut mesuré (run kitten_clicker-20260821b, 2026-08-21) : `extract_json_payload`
retourne inconditionnellement le DERNIER bloc dict. La sortie réelle de
s2-worldscan (fixture `EVIDENCE/runs/kitten_clicker/artifacts/s2-worldscan.failed.txt`)
contient DEUX blocs ```json``` : un worldscan VALIDE (4 jeux) suivi d'un second bloc,
le RETURN_REASON fenced au lieu d'inline, qui vole la place de l'artefact. Le
validateur worldscan juge alors ce second bloc et rend un message trompeur
(« games doit être une liste non vide ») alors que la clé est ABSENTE, pas vide.

NO_CLAIM_ALLOWED — capteur déterministe, aucun appel réseau/LLM.
"""
from pathlib import Path

import pytest

import forge.run_real as run_real

REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker"
# Sortie RÉELLE du run 2 : d'abord le run courant, sinon l'archive du run 2
# (même convention que la fixture charter du run 1, `_run1_20260821-1312/`).
_FIXTURE = next(
    (p for p in (
        # Archive d'abord : le run_dir vivant porte le failed.txt du RUN COURANT
        # (contenu différent à chaque run) — la fixture du défaut mesuré est l'archive.
        _RUN_DIR / "_run2_20260821b" / "artifacts" / "s2-worldscan.failed.txt",
    ) if p.exists()),
    _RUN_DIR / "_run2_20260821b" / "artifacts" / "s2-worldscan.failed.txt",
)


def _valid_worldscan_block() -> str:
    return (
        '```json\n'
        '{"games": [{"name": "g1", "objectives": ["survive"]}], '
        '"advisory": true, "candidate_bricks": []}\n'
        '```'
    )


def _invalid_return_reason_block() -> str:
    # Forme observée en vivo : RETURN_REASON fenced en ```json``` au lieu d'inline.
    return '```json\n{"status": "NOT_DISCOVERED"}\n```'


def _valid_worldscan_block_variant() -> str:
    return (
        '```json\n'
        '{"games": [{"name": "g2", "objectives": ["win"]}], '
        '"advisory": true, "candidate_bricks": ["b1"]}\n'
        '```'
    )


class TestSelectArtifactPayload:
    def test_a_dernier_bloc_invalide_avant_dernier_valide_retient_avant_dernier(self):
        """(a) deux blocs dict, le dernier NE valide PAS, l'avant-dernier valide
        -> l'avant-dernier doit être retenu."""
        text = (
            "Voici mon analyse.\n\n"
            + _valid_worldscan_block()
            + "\n\nRETURN_REASON en fenced (hors contrat, observé en vivo) :\n"
            + _invalid_return_reason_block()
        )
        data, why = run_real.select_artifact_payload("s2-worldscan", text)
        assert why == ""
        assert data is not None
        assert data["games"] == [{"name": "g1", "objectives": ["survive"]}]

    def test_b_deux_blocs_valides_retient_le_dernier(self):
        """(b) deux blocs dict tous les deux valides -> le DERNIER doit être
        retenu (comportement inchangé dans ce cas — même règle qu'avant)."""
        text = (
            _valid_worldscan_block()
            + "\n\n"
            + _valid_worldscan_block_variant()
        )
        data, why = run_real.select_artifact_payload("s2-worldscan", text)
        assert why == ""
        assert data is not None
        assert data["games"] == [{"name": "g2", "objectives": ["win"]}]

    def test_c_aucun_bloc_ne_valide_echoue_avec_raison_du_validateur(self):
        """(c) aucun bloc dict ne valide -> échec, raison venant du validateur
        (pas un message générique d'extract_json_payload)."""
        text = (
            _invalid_return_reason_block()
            + "\n\n"
            + '```json\n{"status": "NOT_TRANSMITTED"}\n```'
        )
        data, why = run_real.select_artifact_payload("s2-worldscan", text)
        assert data is None
        assert "games" in why  # raison du validateur worldscan, pas générique

    def test_d_fixture_reelle_run_kitten_clicker(self, tmp_path):
        """(d) FIXTURE RÉELLE : la sortie réelle de s2-worldscan (2 blocs fenced,
        le second vole la place avant ce correctif) doit désormais matérialiser
        worldscan.json avec ses 4 jeux."""
        if not _FIXTURE.exists():
            pytest.skip(f"fixture absente sur ce poste : {_FIXTURE}")
        texte = _FIXTURE.read_text(encoding="utf-8")
        failure = run_real._materialize_artifact("s2-worldscan", texte, tmp_path)
        assert failure is None, f"matérialisation refusée : {failure}"
        artefact_path = tmp_path / "worldscan.json"
        assert artefact_path.exists()
        import json
        data = json.loads(artefact_path.read_text(encoding="utf-8"))
        assert isinstance(data["games"], list)
        assert len(data["games"]) == 4

    def test_e_message_distingue_games_absente_vs_games_vide(self):
        """(e) le message d'erreur du validateur worldscan diffère bien entre
        'games absente' et 'games vide'."""
        absente = run_real._validate_worldscan({"advisory": True})
        vide = run_real._validate_worldscan({"games": [], "advisory": True})
        assert absente != vide
        assert "ABSENTE" in absente
        assert "ABSENTE" not in vide
        assert "NON VIDE" in vide

    def test_etape_sans_validateur_delegue_a_extract_json_payload(self):
        """Étape hors `_ARTIFACT_BY_STEP` (pas d'artefact JSON déterministe) :
        comportement inchangé, délégation directe à extract_json_payload."""
        text = '```json\n{"a": 1}\n```\n\n```json\n{"b": 2}\n```'
        data, why = run_real.select_artifact_payload("s99-inconnue", text)
        expected_data, expected_why = run_real.extract_json_payload(text)
        assert (data, why) == (expected_data, expected_why)
