"""WireMap v2 ({schema_version: 2, systems[], lines[]}) acceptée par
`run_real._validate_wiremap` et par `static_oracles.check_wiremap`.

Défaut mesuré (run kitten_clicker-20260821d, 2026-08-22) : l'agent s5 a rendu
une WireMap v2 conforme au contrat `forge/contracts/s5-wiremap.yaml`
(« ou le schéma v2 {systems[], lines[]} (standard/SCHEMA.md §3) ») et déjà
lue par `frozen_features_from_wiremap` / `driver._mutation_scope_from_wiremap_any`,
mais `run_real._validate_wiremap` exigeait `features[]` non vide -> HALT sur toute
v2. Second défaut LATENT : `check_wiremap` itère `wiremap.get("features", [])`
-> sur une v2 il ne voit rien et rend `passed=True` PAR VACUITÉ (faux vert).

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_wiremap_v2_accepted.py -v
"""
import json
import re
from pathlib import Path

import pytest

import forge.run_real as run_real
import forge.static_oracles as static_oracles

FIXTURE_CANDIDATES = [
    Path("EVIDENCE/runs/kitten_clicker/_run4_20260821d/artifacts/s5-wiremap.failed.txt"),
    Path("EVIDENCE/runs/kitten_clicker/artifacts/s5-wiremap.failed.txt"),
]


def _fixture_path() -> Path | None:
    for p in FIXTURE_CANDIDATES:
        if p.exists():
            return p
    return None


def _fixture_wiremap() -> dict | None:
    path = _fixture_path()
    if path is None:
        return None
    text = path.read_text(encoding="utf-8")
    blocks = re.findall(r"```json(.*?)```", text, re.S)
    assert blocks, f"aucun bloc ```json``` dans {path}"
    return json.loads(blocks[-1])


def _ligne_ok(**overrides) -> dict:
    base = {
        "id": "core.boot",
        "fichiers": [{"path": "06_RUNTIME/adapters/runtime_loop/boot.gd", "category": "system.adapter"}],
        "couvre": ["R2"],
        "fonction": "",
        "preuve": "",
    }
    base.update(overrides)
    return base


def _wiremap_v2(**overrides) -> dict:
    base = {
        "schema_version": 2,
        "game_id": "kitten_clicker",
        "systems": [{"id": "runtime_loop", "category": "system", "allowed_deps": []}],
        "lines": [_ligne_ok()],
    }
    base.update(overrides)
    return base


# --- (a) v2 minimale valide -------------------------------------------------

def test_validate_wiremap_v2_minimal_ok():
    reason = run_real._validate_wiremap(_wiremap_v2())
    assert reason == ""


# --- (b) v2 invalide : 4 messages distincts ---------------------------------

def test_validate_wiremap_v2_sans_lines():
    reason = run_real._validate_wiremap(_wiremap_v2(lines=[]))
    assert "lines" in reason
    assert "NON VIDE" in reason


def test_validate_wiremap_v2_ligne_sans_id():
    ligne = _ligne_ok()
    del ligne["id"]
    reason = run_real._validate_wiremap(_wiremap_v2(lines=[ligne]))
    assert "lines[0]" in reason
    assert "id" in reason


def test_validate_wiremap_v2_ligne_sans_fichiers():
    reason = run_real._validate_wiremap(_wiremap_v2(lines=[_ligne_ok(fichiers=[])]))
    assert "lines[0]" in reason
    assert "fichiers" in reason


def test_validate_wiremap_v2_ligne_couvre_vide():
    reason = run_real._validate_wiremap(_wiremap_v2(lines=[_ligne_ok(couvre=[])]))
    assert "lines[0]" in reason
    assert "couvre" in reason


def test_validate_wiremap_v2_quatre_messages_distincts():
    reasons = {
        "sans_lines": run_real._validate_wiremap(_wiremap_v2(lines=[])),
        "sans_id": run_real._validate_wiremap(
            _wiremap_v2(lines=[{k: v for k, v in _ligne_ok().items() if k != "id"}])),
        "sans_fichiers": run_real._validate_wiremap(_wiremap_v2(lines=[_ligne_ok(fichiers=[])])),
        "couvre_vide": run_real._validate_wiremap(_wiremap_v2(lines=[_ligne_ok(couvre=[])])),
    }
    assert len(set(reasons.values())) == 4, reasons


# --- (c) v1 inchangé -------------------------------------------------------

_V1_FEAT_OK = {
    "feature": "core.clic",
    "fichiers": ["06_RUNTIME/boot.gd"],
    "fonction": "on_click",
}


def test_validate_wiremap_v1_valide_inchange():
    reason = run_real._validate_wiremap({"features": [_V1_FEAT_OK]})
    assert reason == ""


def test_validate_wiremap_v1_invalide_inchange():
    reason = run_real._validate_wiremap({"features": []})
    assert reason == "'features' doit être une liste NON VIDE"


# --- (d) fixture réelle -------------------------------------------------------
#
# ÉCART DÉCOUVERT (documenté dans le rapport, pas contourné en silence) :
# lines[8] de cette fixture réelle (id="core.audio", owner=false,
# requires=["audio.event_cues"]) porte `fichiers: []` — délibérément, le
# commentaire du builder dans `fonction` dit ne pas re-déclarer un fichier
# déjà porté par la ligne `audio.event_cues` pour ne pas "revendiquer deux
# fois le même volet". SCHEMA.md §3 ne documente AUCUNE exemption "owner:
# false => fichiers vide toléré" ; la mission demande `fichiers` NON VIDE
# SANS condition. Assouplir la règle pour ce cas précis serait inventer une
# clause absente du standard (interdit : "jamais inventer une appartenance
# avant de mesurer sa population" — memory/dont_clean_before_the_cause.md).
# Donc : la fixture entière (51 lignes) N'EST PAS acceptée telle quelle par
# _validate_wiremap — elle est rejetée sur CETTE ligne précise, un second
# défaut réel révélé par ce correctif (masqué avant lui par le rejet plus
# grossier "'features' doit être une liste NON VIDE" qui ne descendait
# jamais au niveau ligne). Testé ici tel quel, sans contournement.

def test_fixture_v2_ligne_owner_false_sans_fichiers_rejetee():
    """Défaut secondaire révélé par ce correctif : lines[8] (core.audio,
    owner=false) a fichiers=[] — invérifiable, rejeté par lines[8].fichiers,
    pas par le message générique 'features' d'avant ce correctif."""
    data = _fixture_wiremap()
    if data is None:
        pytest.skip("fixture s5-wiremap.failed.txt absente")
    reason = run_real._validate_wiremap(data)
    assert reason != ""
    assert "lines[8]" in reason
    assert "fichiers" in reason


def test_fixture_v2_sans_la_ligne_deficiente_valide_et_materialise(tmp_path):
    """Preuve que le correctif accepte bien la v2 réelle une fois le SEUL
    défaut réel (lines[8].fichiers vide) neutralisé — isole la garde v2 du
    défaut préexistant du builder plutôt que de le masquer."""
    data = _fixture_wiremap()
    if data is None:
        pytest.skip("fixture s5-wiremap.failed.txt absente")
    data = dict(data)
    data["lines"] = [l for i, l in enumerate(data["lines"]) if i != 8]
    reason = run_real._validate_wiremap(data)
    assert reason == ""

    output = "```json\n" + json.dumps(data, ensure_ascii=False) + "\n```"
    failure = run_real._materialize_artifact("s5-wiremap", output, tmp_path)
    assert failure is None, failure
    assert (tmp_path / "wiremap.json").exists()


# --- (e) check_wiremap v2 ----------------------------------------------------

def test_check_wiremap_v2_passe(tmp_path):
    (tmp_path / "boot.gd").write_text("func on_boot():\n\tpass\n", encoding="utf-8")
    wiremap = _wiremap_v2(lines=[_ligne_ok(
        fichiers=[{"path": "boot.gd", "category": "system.adapter"}],
        fonction="on_boot",
        preuve="preuve non vide",
    )])
    res = static_oracles.check_wiremap(wiremap, tmp_path)
    assert res["passed"] is True, res


def test_check_wiremap_v2_fichier_absent(tmp_path):
    wiremap = _wiremap_v2(lines=[_ligne_ok(
        fichiers=[{"path": "absent.gd", "category": "system.adapter"}],
        fonction="on_boot",
        preuve="preuve non vide",
    )])
    res = static_oracles.check_wiremap(wiremap, tmp_path)
    assert res["passed"] is False
    assert res["features_manquantes"]


def test_check_wiremap_v2_lines_vide_pas_de_vert_par_vacuite(tmp_path):
    wiremap = _wiremap_v2(lines=[])
    res = static_oracles.check_wiremap(wiremap, tmp_path)
    assert res["passed"] is False
    assert res["features_manquantes"] == ["<aucune ligne>"]


# --- (f) frozen_features_from_wiremap sur la fixture -------------------------

def test_frozen_features_from_wiremap_fixture_51_ids():
    data = _fixture_wiremap()
    if data is None:
        pytest.skip("fixture s5-wiremap.failed.txt absente")
    ids = static_oracles.frozen_features_from_wiremap(data)
    assert len(ids) == 51
    assert all(ids)
