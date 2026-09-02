"""Profil full_godot_content (décision Pierre 2026-08-22, ORDRE corrigé Lot A
2026-08-23) : COMPOSITION, aucune station neuve — full_godot_narratif +
s2.5-artbible (Art Director) injectée entre s2.6-story-bible et s2.7-gm-worldscan
(audit docs/audit/2026-08-23-kitten-clicker-worldscan-artbible-gm-pipe.md : l'Art
Bible doit précéder le GM et hériter du World Scan + Story Bible, pas du Prisme).
Même forme que le lot full_godot_narratif : imite
test_profile_full_godot_narratif.py."""
from forge.dispatch import (
    DEDICATED_PROFILE_STEPS, ORDER, PROFILES, order_for_profile, step_timeout_for,
)


def test_le_profil_existe_et_compose_uniquement_des_etapes_existantes():
    steps = PROFILES["full_godot_content"]
    assert set(steps).issubset(set(ORDER) | set(DEDICATED_PROFILE_STEPS))


def test_le_profil_est_full_godot_narratif_plus_artbible_entre_s26_et_s27():
    attendu = list(PROFILES["full_godot_narratif"])
    k = attendu.index("s2.7-gm-worldscan")
    attendu.insert(k, "s2.5-artbible")
    # Lot F (2026-08-23) : boucle de complétion mutuelle -- s2.5-artbible-r2 et
    # s2.7-gm-worldscan-r2 (aliases round 2, même contrat que leur base -- cf.
    # forge.contract.base_step/step_round) s'insèrent juste après s2.7-gm-worldscan
    # et AVANT s1-prisme -- 2 rondes fixes, GO Pierre, jamais de 3e ronde.
    k2 = attendu.index("s2.7-gm-worldscan") + 1
    attendu[k2:k2] = ["s2.5-artbible-r2", "s2.7-gm-worldscan-r2"]
    assert list(PROFILES["full_godot_content"]) == attendu
    assert order_for_profile("full_godot_content") == attendu
    assert len(PROFILES["full_godot_content"]) == 19
    i = {e: idx for idx, e in enumerate(PROFILES["full_godot_content"])}
    assert i["s2.6-story-bible"] < i["s2.5-artbible"] < i["s2.7-gm-worldscan"] < i["s1-prisme"]
    assert i["s2.7-gm-worldscan"] < i["s2.5-artbible-r2"] < i["s2.7-gm-worldscan-r2"] < i["s1-prisme"]


def test_les_alias_round2_partagent_le_contrat_de_leur_base():
    from forge.contract import base_step, step_round, load_contract
    assert base_step("s2.5-artbible-r2") == "s2.5-artbible"
    assert base_step("s2.7-gm-worldscan-r2") == "s2.7-gm-worldscan"
    assert step_round("s2.5-artbible-r2") == 2
    assert step_round("s2.7-gm-worldscan-r2") == 2
    assert step_round("s2.5-artbible") == 1
    assert load_contract("s2.5-artbible-r2") == load_contract("s2.5-artbible")
    assert load_contract("s2.7-gm-worldscan-r2") == load_contract("s2.7-gm-worldscan")



def test_le_builder_garde_le_timeout_mesure():
    assert step_timeout_for("full_godot_content", "s9-build-godot-standard", 1.0) == 9000.0
    assert step_timeout_for("full_godot_content", "s3-decompo", 1.0) == 1.0


from forge import context_manifest, run_real

_AMONT_NARRATIF = ("artifacts/s2.6-story-bible.txt", "artifacts/s2.7-gm-worldscan.txt")
_AMONT_CONTENT = ("art_bible.md", "asset_requests.json")

# V4 GAME LOOP (2026-08-22, GO Pierre) : loop.json est injecté en FIN de tuple à
# ces 3 étapes (cf. docs/superpowers/plans/2026-08-22-kitten-clicker-v4-game-loop.md
# Task 2) — les 3 tests ci-dessous sont mis à jour en conséquence.
_LOOP_JSON = ("loop.json",)

# Lot B T2(b) (2026-08-23) : héritage inter-run (contrat d'artefacts GM <-> Artiste,
# sans station nouvelle, cf. plan Lot B) — injecté en FIN de tuple, absent au 1er run.
_HERITAGE_ARTBIBLE = ("heritage/art_bible.md", "heritage/art_response.json")
_HERITAGE_GM = ("heritage/art_response.json", "heritage/gm_worldscan.json")
_ECONOMY_JSON = ("economy.json",)

# Lot D (2026-08-23, GO Pierre, fuite 3 : le design n'etait lu par personne) —
# injecte en FIN de tuple, absent (design/ non peuple) => omis, comportement
# inchange. cf. forge/tests/test_lot_d_fuites_mesure.py pour la mesure
# dediee (run_dir tmp avec/sans ces fichiers).
# C.5 ratifie Pierre 2026-08-25 : la CARTE (design/content_requirements.md) est
# injectee aux DEUX piliers, rondes 1 et 2 — condition n°1 du contrat ("non injecte,
# C.5 subit le sort de C.3"). Cf. test_context_manifest.py pour la garde dediee.
_DESIGN_ARTBIBLE = ("design_intent.md", "design/gameplay_loop_content_contract.md",
                    "design/game_loop_blueprint.md", "design/content_requirements.md",
                    "design/progression_contract.md")
_DESIGN_GM = ("design_intent.md", "design/gameplay_loop_content_contract.md",
             "design/game_loop_blueprint.md", "design/content_requirements.md",
             "design/progression_contract.md", "design/calibration.md")
_DESIGN_BUILD = ("design/gameplay_loop_content_contract.md",)


def test_s25_artbible_recoit_charter_worldscan_story_bible():
    """Lot A 2026-08-23 : l'Art Bible hérite du World Scan et de la Story Bible
    (plus du Prisme). Lot B T2(b) : + héritage inter-run. Lot D : + sources design."""
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s2.5-artbible"] == (
            "charter.yaml", "artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt",
        ) + _HERITAGE_ARTBIBLE + _DESIGN_ARTBIBLE


def test_s27_gm_worldscan_recoit_story_bible_et_art_bible():
    """Lot A 2026-08-23 : le GM reçoit désormais la Story Bible et l'Art Bible
    (produite avant lui dans full_godot_content), plus le World Scan seul avant.
    Lot B T2(b) : + héritage inter-run (art_response.json, gm_worldscan.json).
    Lot D : + sources design."""
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s2.7-gm-worldscan"] == (
            "artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt",
        ) + _AMONT_CONTENT + _HERITAGE_GM + _DESIGN_GM


def test_s3_decompo_recoit_aussi_art_bible_et_asset_requests():
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s3-decompo"] == (
            "charter.yaml", "artifacts/s1-prisme.txt", "artifacts/s2-worldscan.txt",
        ) + _AMONT_NARRATIF + _AMONT_CONTENT + _LOOP_JSON


def test_s5_wiremap_recoit_story_bible_art_bible_et_asset_requests():
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s5-wiremap"] == (
            "charter.yaml", "artifacts/s3-decompo.txt", "blueprint.json",
            "artifacts/s2.6-story-bible.txt", "art_bible.md", "asset_requests.json",
        ) + _LOOP_JSON


def test_s9_build_godot_standard_recoit_blueprint_wiremap_art_bible_asset_requests():
    """Lot B T2(b) : + economy.json (projection déterministe, dérivée à s2.7).
    Lot D : + design/gameplay_loop_content_contract.md."""
    for table in (run_real._UPSTREAM_BY_STEP, context_manifest._UPSTREAM_BY_STEP):
        assert table["s9-build-godot-standard"] == (
            "blueprint.json", "wiremap.json", "art_bible.md", "asset_requests.json",
        ) + _LOOP_JSON + _ECONOMY_JSON + _DESIGN_BUILD


def test_les_deux_copies_de_la_table_amont_restent_identiques():
    assert run_real._UPSTREAM_BY_STEP == context_manifest._UPSTREAM_BY_STEP


def test_les_artefacts_amont_absents_sont_omis_sans_erreur_s9(tmp_path):
    # seul wiremap.json présent : art_bible.md/asset_requests.json omis, pas d'erreur.
    (tmp_path).mkdir(exist_ok=True)
    (tmp_path / "wiremap.json").write_text("{}", encoding="utf-8")
    section = run_real.upstream_artifacts_section("s9-build-godot-standard", tmp_path)
    assert "wiremap.json" in section
    assert "art_bible.md" not in section
    assert "asset_requests.json" not in section
