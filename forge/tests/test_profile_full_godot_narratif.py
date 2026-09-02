"""Profil full_godot_narratif (décision Pierre 2026-08-21, choix (b)) : composition
d'étapes EXISTANTES pour que s2.6 (Story Bible) et s2.7 (GM World Scan) soient
produites AVANT le Prisme et la décompo, et injectées dans leurs prompts."""
from forge.dispatch import (
    DEDICATED_PROFILE_STEPS, ORDER, PROFILES, order_for_profile, step_timeout_for,
)


def test_le_profil_existe_et_compose_uniquement_des_etapes_existantes():
    steps = PROFILES["full_godot_narratif"]
    assert set(steps).issubset(set(ORDER) | set(DEDICATED_PROFILE_STEPS))


def test_s26_et_s27_precedent_s1_et_s3():
    steps = list(PROFILES["full_godot_narratif"])
    i = {s: steps.index(s) for s in steps}
    assert i["s2-worldscan"] < i["s2.6-story-bible"] < i["s1-prisme"]
    assert i["s2-worldscan"] < i["s2.7-gm-worldscan"] < i["s1-prisme"]
    assert i["s1-prisme"] < i["s3-decompo"] < i["s5-wiremap"]
    assert i["s0-contrat"] == 0  # charter AVANT s2.6 : mesuré 0/8 -> 7/8 GROUNDED (dispatch.py)


def test_le_profil_est_full_godot_plus_les_deux_stations_amont():
    attendu = list(PROFILES["full_godot"])
    k = attendu.index("s1-prisme")
    attendu[k:k] = ["s2.6-story-bible", "s2.7-gm-worldscan"]
    assert list(PROFILES["full_godot_narratif"]) == attendu
    assert order_for_profile("full_godot_narratif") == attendu


def test_le_builder_garde_le_timeout_mesure_de_full_godot():
    assert step_timeout_for("full_godot_narratif", "s9-build-godot-standard", 1.0) == 5400.0
    assert step_timeout_for("full_godot_narratif", "s3-decompo", 1.0) == 1.0


from forge import context_manifest, run_real

_AMONT_NARRATIF = ("artifacts/s2.6-story-bible.txt", "artifacts/s2.7-gm-worldscan.txt")


def test_le_prisme_et_la_decompo_recoivent_story_bible_et_gm_worldscan():
    # Appartenance, pas égalité exacte : le lot 4 (full_godot_content, 2026-08-22) ajoute
    # l'art bible aux mêmes entrées — ce test garantit que s1 et s3 REÇOIVENT les deux
    # artefacts narratifs, pas que rien d'autre ne pourra jamais s'y ajouter.
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s1-prisme"][:1] == ("artifacts/s2-worldscan.txt",)
        assert set(_AMONT_NARRATIF) <= set(table["s1-prisme"])
        assert table["s3-decompo"][:3] == (
            "charter.yaml", "artifacts/s1-prisme.txt", "artifacts/s2-worldscan.txt",
        )
        assert set(_AMONT_NARRATIF) <= set(table["s3-decompo"])
    assert run_real._UPSTREAM_BY_STEP == context_manifest._UPSTREAM_BY_STEP


def test_les_artefacts_amont_absents_sont_omis_sans_erreur(tmp_path):
    # un run `full` (sans s2.6/s2.7) ne doit pas changer : section construite
    # uniquement depuis ce qui existe.
    (tmp_path / "artifacts").mkdir()
    (tmp_path / "artifacts" / "s2-worldscan.txt").write_text("WS", encoding="utf-8")
    section = run_real.upstream_artifacts_section("s1-prisme", tmp_path)
    assert "s2-worldscan.txt" in section
    assert "s2.6-story-bible.txt" not in section


def test_les_contrats_s1_et_s3_declarent_la_lecture_des_deux_artefacts():
    from pathlib import Path
    import yaml
    for nom in ("s1-prisme", "s3-decompo"):
        c = yaml.safe_load(Path(f"forge/contracts/{nom}.yaml").read_text(encoding="utf-8"))
        joined = " ".join(c["mandatory_read"])
        assert "story_bible.json" in joined and "gm_worldscan.json" in joined, nom
    s1 = Path("forge/contracts/s1-prisme.yaml").read_text(encoding="utf-8")
    for prefixe in ("worldscan:", "story_bible:", "gm_worldscan:"):
        assert prefixe in s1, f"le contrat s1 doit rendre `reference` adressable ({prefixe})"
