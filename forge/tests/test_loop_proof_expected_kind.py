"""Chantier S5 expected_proof.kind (GO Pierre 2026-09-08), plan
docs/superpowers/plans/2026-09-08-s5-expected-proof-kind.md.

Diagnostic (audit Q2 lecture seule, chaton_clicker_canal_probe_2, f8204b0) : `R3`
cite `logic.test.mjs::caresser` en `WHITE_BOX` alors que `cap_caresser_effet` porte
déjà `expected_proof.kind: bot_action` dans featuremap.json — une preuve joueur
décidée dès s3, transmise verbatim à s5, jamais consultée par le contrat s5.

Fixtures reprises du cas réel exact (`cap_caresser_effet`, kind `bot_action`), plus
les kinds `visual`/`file_write`. Vérifie explicitement que cette dimension est
INDÉPENDANTE de loop.json/des rôles de boucle (contrairement à `roles_manquants`) et
distincte de `couvre_non_resolu` (une ligne bien formée peut quand même violer
`kind_non_honore`).
"""
from forge.static_oracles import check_player_loop_coverage

FEATUREMAP_BOT_ACTION = {
    "systemes": [{"features": [{"capacites": [
        {"id": "cap_caresser_entree", "source_ref": "P02",
         "expected_proof": {"kind": "bot_action", "statement": "..."}},
        {"id": "cap_caresser_effet", "source_ref": "P02",
         "expected_proof": {"kind": "bot_action", "statement": "..."}},
    ]}]}]
}


def _wiremap(features):
    return {"features": features}


# --- reproduction exacte du cas réel chaton_clicker ----------------------------

def test_reproduit_le_cas_reel_r3_white_box_sur_kind_bot_action():
    """Cas EXACT mesuré : R3 cite logic.test.mjs::caresser en WHITE_BOX pour une
    capacité dont le kind exige une preuve joueur. Doit ressortir en FAIL nommé."""
    wiremap = _wiremap([
        {"feature": "R2", "couvre": ["cap_caresser_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R3", "couvre": ["cap_caresser_effet"], "canal": "WHITE_BOX",
         "preuve": "logic.test.mjs::caresser"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_BOT_ACTION, {"steps": []})
    assert rep["status"] == "FAIL"
    assert any("cap_caresser_effet" in r and "bot_action" in r for r in rep["kind_non_honore"])


def test_canal_player_loop_ajoute_en_plus_du_test_unitaire_passe():
    """Correctif attendu : canal porte les DEUX valeurs — le test unitaire reste
    une preuve légitime EN PLUS, jamais seul."""
    wiremap = _wiremap([
        {"feature": "R2", "couvre": ["cap_caresser_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R3", "couvre": ["cap_caresser_effet"],
         "canal": ["PLAYER_LOOP", "WHITE_BOX"], "preuve_ref": "P02"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_BOT_ACTION, {"steps": []})
    assert rep["status"] == "PASS"
    assert rep["kind_non_honore"] == []


def test_canal_player_loop_seul_sans_white_box_suffit_aussi():
    wiremap = _wiremap([
        {"feature": "R2", "couvre": ["cap_caresser_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R3", "couvre": ["cap_caresser_effet"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_BOT_ACTION, {"steps": []})
    assert rep["status"] == "PASS"


# --- indépendance vis-à-vis de loop.json/des rôles de boucle -------------------

def test_kind_non_honore_independant_de_loop_json_role():
    """La vérification s'applique même quand loop.json est vide (aucun rôle
    déclaré) — le kind est la source de vérité, pas le rôle."""
    wiremap = _wiremap([
        {"feature": "R3", "couvre": ["cap_caresser_effet"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_BOT_ACTION, {"steps": []})
    assert rep["status"] == "FAIL"
    assert any("cap_caresser_effet" in r for r in rep["kind_non_honore"])


# --- kinds visual / file_write, mêmes règles que bot_action --------------------

def test_kind_visual_exige_aussi_player_loop():
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_objectif_change", "expected_proof": {"kind": "visual"}},
    ]}]}]}
    wiremap = _wiremap([{"feature": "R7", "couvre": ["cap_objectif_change"], "canal": "WHITE_BOX"}])
    rep = check_player_loop_coverage(wiremap, featuremap, {"steps": []})
    assert rep["status"] == "FAIL"
    assert any("visual" in r for r in rep["kind_non_honore"])


def test_kind_file_write_exige_aussi_player_loop():
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_registre", "expected_proof": {"kind": "file_write"}},
    ]}]}]}
    wiremap = _wiremap([{"feature": "R20", "couvre": ["cap_registre"], "canal": "WHITE_BOX"}])
    rep = check_player_loop_coverage(wiremap, featuremap, {"steps": []})
    assert rep["status"] == "FAIL"


# --- fail-safe : un kind inconnu/absent ne déclenche jamais rien --------------

def test_kind_inconnu_ne_declenche_aucune_exigence():
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_x", "expected_proof": {"kind": "gpu_window"}},
    ]}]}]}
    wiremap = _wiremap([{"feature": "R1", "couvre": ["cap_x"], "canal": "WHITE_BOX"}])
    rep = check_player_loop_coverage(wiremap, featuremap, {"steps": []})
    assert rep["kind_non_honore"] == []


def test_capacite_sans_expected_proof_ne_declenche_aucune_exigence():
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_sans_proof"},
    ]}]}]}
    wiremap = _wiremap([{"feature": "R1", "couvre": ["cap_sans_proof"], "canal": "WHITE_BOX"}])
    rep = check_player_loop_coverage(wiremap, featuremap, {"steps": []})
    assert rep["kind_non_honore"] == []


# --- distinct de couvre_non_resolu : une ligne bien formée peut violer kind ----

def test_kind_non_honore_distinct_de_couvre_non_resolu():
    """couvre pointe une capacité RÉELLE (pas de couvre_non_resolu) mais le canal
    ne l'honore pas (kind_non_honore SEUL doit se déclencher)."""
    wiremap = _wiremap([
        {"feature": "R3", "couvre": ["cap_caresser_effet"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_BOT_ACTION, {"steps": []})
    assert rep["couvre_non_resolu"] == []
    assert rep["kind_non_honore"] != []
