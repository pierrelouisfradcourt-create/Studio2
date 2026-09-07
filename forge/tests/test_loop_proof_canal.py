"""Chantier canal-de-preuve (GO Pierre 2026-09-07) — WHITE_BOX/PLAYER_INPUT/
PLAYER_LOOP/META_LOOP, plan docs/superpowers/plans/2026-09-07-canal-de-preuve-loop.md.

Trois fonctions ADDITIVES de forge.static_oracles, aucune ne touche check_wiremap
existant. Invariants couverts ici, un test par invariant nommé dans le plan :
  1. aucun rétro-verdissement des runs sans champ `canal` -> NOT_MEASURED ;
  2. WHITE_BOX (seul ou empilé) ne satisfait jamais PLAYER_LOOP/META_LOOP ;
  3. `canal: PLAYER_LOOP` sans `preuve_ref` observé dans un journal d'exécution
     réel ne suffit pas — la chaîne complète est exigée.

Fixture positive reprise du cas réel `chaton_clicker` (R9 arbitrage_actif_vs_passif,
rôle DECISION, ref P05) : WHITE_BOX seul aujourd'hui (mesuré, cf. audit
2026-09-07) devient PASS une fois une ligne PLAYER_LOOP+preuve_ref ajoutée et
observée dans le journal.
"""
from forge.static_oracles import (
    check_player_loop_coverage,
    check_player_loop_proof,
    check_wiremap_canal,
)

LOOP_JSON_DECISION = {
    "steps": [
        {"role": "PLAYER_GOAL", "ref": "P01"},
        {"role": "DECISION", "ref": "P05"},
    ]
}

FEATUREMAP_DECISION = {
    "systemes": [
        {"features": [{"capacites": [
            {"id": "cap_afficher_objectif_courant", "source_ref": "P01"},
            {"id": "cap_arbitrage_actif_vs_passif", "source_ref": "P05"},
        ]}]}
    ]
}


def _wiremap(features):
    return {"features": features}


# --- invariant 1 : pas de rétro-verdissement -----------------------------------

def test_absence_totale_de_canal_rend_not_measured_jamais_fail_ni_pass():
    """Run antérieur au chantier (chaton_clicker-20260906 mesuré : 0 champ canal
    sur ses 15 lignes) — ni FAIL ni PASS, un statut à part."""
    wiremap = _wiremap([
        {"feature": "R9 arbitrage_actif_vs_passif", "couvre": ["cap_arbitrage_actif_vs_passif"],
         "preuve": "logic.test.mjs::comparerPolitiques"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_DECISION, LOOP_JSON_DECISION)
    assert rep["status"] == "NOT_MEASURED"
    assert rep["passed"] is None
    assert rep["roles_manquants"] == []


# --- invariant 2 : WHITE_BOX ne satisfait jamais PLAYER_LOOP/META_LOOP ---------

def test_white_box_seul_sur_decision_reste_manquant():
    """Cas réel chaton_clicker R9 : couvert par logic.test.mjs (WHITE_BOX) et rien
    d'autre. Dès qu'UNE AUTRE ligne du wiremap porte 'canal' (ici une ligne sœur,
    peu importe laquelle), le statut NOT_MEASURED cesse et P05/DECISION doit
    ressortir manquant."""
    wiremap = _wiremap([
        {"feature": "R1 objectif_courant_affiche", "couvre": ["cap_afficher_objectif_courant"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P01"},
        {"feature": "R9 arbitrage_actif_vs_passif", "couvre": ["cap_arbitrage_actif_vs_passif"],
         "canal": "WHITE_BOX", "preuve": "logic.test.mjs::comparerPolitiques"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_DECISION, LOOP_JSON_DECISION)
    assert rep["status"] == "FAIL"
    assert "P05" in rep["roles_manquants"]
    assert any("WHITE_BOX" in r for r in rep["raisons"])


def test_empiler_plusieurs_lignes_white_box_ne_compense_jamais():
    """Pas de compensation par volume : 3 lignes WHITE_BOX sur la même capacité
    valent aussi peu qu'une seule."""
    wiremap = _wiremap([
        {"feature": "R1", "couvre": ["cap_afficher_objectif_courant"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P01"},
        {"feature": "R9a", "couvre": ["cap_arbitrage_actif_vs_passif"], "canal": "WHITE_BOX"},
        {"feature": "R9b", "couvre": ["cap_arbitrage_actif_vs_passif"], "canal": "WHITE_BOX"},
        {"feature": "R9c", "couvre": ["cap_arbitrage_actif_vs_passif"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_DECISION, LOOP_JSON_DECISION)
    assert rep["status"] == "FAIL"
    assert "P05" in rep["roles_manquants"]


def test_player_loop_present_couvre_le_role():
    wiremap = _wiremap([
        {"feature": "R1", "couvre": ["cap_afficher_objectif_courant"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P01"},
        {"feature": "R9", "couvre": ["cap_arbitrage_actif_vs_passif"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P05"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_DECISION, LOOP_JSON_DECISION)
    assert rep["status"] == "PASS"
    assert rep["roles_manquants"] == []


def test_meta_loop_role_exige_specifiquement_le_canal_meta_loop():
    """PLAYER_LOOP seul ne suffit pas pour un rôle META_LOOP — canal META_LOOP requis."""
    loop_json = {"steps": [{"role": "META_LOOP", "ref": "P10"}]}
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_renouveau", "source_ref": "P10"}]}]}]}
    wiremap_insuffisant = _wiremap([
        {"feature": "R13", "couvre": ["cap_renouveau"], "canal": "PLAYER_LOOP", "preuve_ref": "P10"},
    ])
    rep = check_player_loop_coverage(wiremap_insuffisant, featuremap, loop_json)
    assert rep["status"] == "FAIL"

    wiremap_ok = _wiremap([
        {"feature": "R13", "couvre": ["cap_renouveau"], "canal": "META_LOOP", "preuve_ref": "P10"},
    ])
    rep_ok = check_player_loop_coverage(wiremap_ok, featuremap, loop_json)
    assert rep_ok["status"] == "PASS"


def test_role_a_deux_occurrences_exige_deux_preuves_distinctes():
    """NEXT_GOAL apparaît 2x dans loop.json (P07 chaton_clicker, P08) — prouver
    l'un ne prouve pas l'autre."""
    loop_json = {"steps": [
        {"role": "NEXT_GOAL", "ref": "P07"},
        {"role": "NEXT_GOAL", "ref": "P08"},
    ]}
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_g1", "source_ref": "P07"},
        {"id": "cap_g2", "source_ref": "P08"},
    ]}]}]}
    wiremap = _wiremap([
        {"feature": "R10", "couvre": ["cap_g1"], "canal": "PLAYER_LOOP", "preuve_ref": "P07"},
        {"feature": "R11", "couvre": ["cap_g2"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, featuremap, loop_json)
    assert rep["status"] == "FAIL"
    assert rep["roles_manquants"] == ["P08"]


# --- invariant 3 : canal seul ne suffit pas sans preuve exécutable -------------

def test_canal_player_loop_sans_preuve_ref_echoue():
    wiremap = _wiremap([
        {"feature": "R9", "couvre": ["cap_arbitrage_actif_vs_passif"], "canal": "PLAYER_LOOP"},
    ])
    rep = check_player_loop_proof(wiremap, oracle_log_text="peu importe le contenu")
    assert rep["passed"] is False
    assert any("preuve_ref" in r for r in rep["raisons"])


def test_preuve_ref_jamais_observee_dans_le_journal_echoue():
    """Le cas exact que l'invariant 3 vise à bloquer : un agent pose canal +
    preuve_ref sans que rien n'ait réellement tourné en ce sens."""
    wiremap = _wiremap([
        {"feature": "R9", "couvre": ["cap_arbitrage_actif_vs_passif"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P05"},
    ])
    rep = check_player_loop_proof(wiremap, oracle_log_text="P01 : objectif affiché\nP06 entrée : clic réel")
    assert rep["passed"] is False
    assert any("P05" in r for r in rep["raisons"])


def test_preuve_ref_observee_dans_le_journal_reel_passe():
    """Journal réel mesuré sur chaton_clicker-20260906 (e2e.mjs) — la ligne
    'P06 entrée : clic réel sur acheter_producteur_0' authentifie le ref P06."""
    wiremap = _wiremap([
        {"feature": "R6", "couvre": ["cap_acheter_producteur_entree"],
         "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
    ])
    journal = "P06 entrée : clic réel sur acheter_producteur_0\nP06 effet : panier_chatons visible après achat"
    rep = check_player_loop_proof(wiremap, oracle_log_text=journal)
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_journal_absent_echoue_jamais_un_vert_par_defaut():
    wiremap = _wiremap([
        {"feature": "R6", "couvre": ["cap_x"], "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
    ])
    rep = check_player_loop_proof(wiremap, oracle_log_text="")
    assert rep["passed"] is False


# --- check_wiremap_canal : forme de l'enum -------------------------------------

def test_canal_hors_enum_est_rejete():
    wiremap = _wiremap([
        {"feature": "R1", "canal": "PRESQUE_JOUEUR"},
    ])
    rep = check_wiremap_canal(wiremap)
    assert rep["passed"] is False
    assert any("PRESQUE_JOUEUR" in r for r in rep["raisons"])


def test_canal_absent_ne_declenche_aucune_raison():
    wiremap = _wiremap([{"feature": "R1", "fonction": "f", "fichiers": ["a.mjs"]}])
    rep = check_wiremap_canal(wiremap)
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_canal_valide_passe():
    wiremap = _wiremap([{"feature": "R1", "canal": "PLAYER_LOOP"}])
    rep = check_wiremap_canal(wiremap)
    assert rep["passed"] is True
