"""Chantier couvre-REJEU (GO Pierre 2026-09-08), plan
docs/superpowers/plans/2026-09-08-couvre-rejeu-s3-s5-harmonisation.md.

Diagnostic : `s3-decompo.yaml` exempte REPEAT/ADVANTAGE de toute capacité propre
(« n'exigent AUCUNE feuille propre ») ; `check_player_loop_coverage` cherchait
pourtant une capacité `source_ref == ref` pour CES rôles aussi, qui n'existe
JAMAIS par construction — d'où « traçabilité rompue » systématique, mesuré à
l'identique sur 3 runs indépendants (chaton_clicker, chaton_clicker_canal_probe,
chaton_clicker_canal_probe_2 — ce dernier committé f8204b0).

Décision Pierre (option a) : `s3-decompo.yaml` reste INCHANGÉ ; la couverture
d'un rôle REJEU s'hérite de celle des refs que `replay`/`replay_ref` cible.
Fixtures reprises du cas réel `chaton_clicker` (P09 rejoue [P02,P03,P04,P06],
P11 rejoue P02) et de l'anomalie mesurée (`couvre: ['rejouerBoucle']`,
`['gainParCaresse']`).
"""
from forge.static_oracles import check_player_loop_coverage

LOOP_JSON_REJEU = {
    "steps": [
        {"role": "PLAYER_ACTION", "ref": "P02"},
        {"role": "GAME_RESPONSE", "ref": "P03"},
        {"role": "REWARD", "ref": "P04"},
        {"role": "UNLOCK", "ref": "P06"},
        {"role": "REPEAT", "ref": "P09", "replay": ["P02", "P03", "P04", "P06"]},
        {"role": "ADVANTAGE", "ref": "P11", "replay_ref": "P02"},
    ]
}

FEATUREMAP_REJEU = {
    "systemes": [{"features": [{"capacites": [
        {"id": "cap_caresser_entree", "source_ref": "P02"},
        {"id": "cap_caresser_effet", "source_ref": "P02"},
        {"id": "cap_reponse_caresse", "source_ref": "P03"},
        {"id": "cap_bouton_producteur_actif", "source_ref": "P04"},
        {"id": "cap_acheter_producteur_entree", "source_ref": "P06"},
        {"id": "cap_acheter_producteur_effet", "source_ref": "P06"},
    ]}]}
]}
FEATUREMAP_REJEU = {"systemes": FEATUREMAP_REJEU["systemes"]}


def _wiremap(features):
    return {"features": features}


def _lignes_normales_toutes_player_loop():
    """P02/P03/P04/P06 tous couverts PLAYER_LOOP — état où le rejeu DEVRAIT pouvoir
    hériter d'une preuve réelle."""
    return [
        {"feature": "R2", "couvre": ["cap_caresser_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R3", "couvre": ["cap_caresser_effet"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R4", "couvre": ["cap_reponse_caresse"], "canal": "PLAYER_LOOP", "preuve_ref": "P03"},
        {"feature": "R5", "couvre": ["cap_bouton_producteur_actif"], "canal": "PLAYER_LOOP", "preuve_ref": "P04"},
        {"feature": "R6", "couvre": ["cap_acheter_producteur_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
        {"feature": "R7", "couvre": ["cap_acheter_producteur_effet"], "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
    ]


# --- invariant : reproduire, puis résoudre le cas réel chaton_clicker ---------

def test_reproduit_le_cas_reel_mesure_couvre_nom_de_methode():
    """Cas EXACT des 3 runs (chaton_clicker, probe 1, probe 2) : R12 couvre
    'rejouerBoucle' (nom de méthode), R15 couvre 'gainParCaresse' — aucun des
    deux ne résout à une capacité réelle. Deux constats DISTINCTS, jamais
    confondus : (1) P09/P11 HÉRITENT correctement PASS (P02/P03/P04/P06 sont
    tous PLAYER_LOOP ici — le rejeu lui-même est réel, l'héritage ne dépend PAS
    de la ligne R12/R15) ; (2) la ligne R12/R15 qui PRÉTEND documenter ce rejeu
    est malformée et DOIT ressortir via couvre_non_resolu — le statut global
    reste FAIL à cause de CETTE malformation, pas d'un rôle manquant."""
    wiremap = _wiremap(_lignes_normales_toutes_player_loop() + [
        {"feature": "R12 Rejeu de la boucle", "couvre": ["rejouerBoucle"], "canal": "WHITE_BOX"},
        {"feature": "R15 Avantage permanent", "couvre": ["gainParCaresse"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_REJEU, LOOP_JSON_REJEU)
    assert rep["status"] == "FAIL"
    assert "P09" not in rep["roles_manquants"]  # hérité PASS, réellement rejoué
    assert "P11" not in rep["roles_manquants"]
    assert any("rejouerBoucle" in r for r in rep["couvre_non_resolu"])
    assert any("gainParCaresse" in r for r in rep["couvre_non_resolu"])


def test_couvre_corrige_avec_ids_reels_des_refs_rejouees_passe():
    """Correctif attendu (s5-wiremap.yaml, exception REJEU) : couvre cite les IDS
    RÉELS des capacités rejouées, jamais un id inventé. P09/P11 doivent alors
    hériter PASS puisque P02/P03/P04/P06 sont tous PLAYER_LOOP."""
    wiremap = _wiremap(_lignes_normales_toutes_player_loop() + [
        {"feature": "R12 Rejeu de la boucle",
         "couvre": ["cap_caresser_entree", "cap_caresser_effet",
                    "cap_bouton_producteur_actif", "cap_acheter_producteur_entree",
                    "cap_acheter_producteur_effet"],
         "canal": "WHITE_BOX"},
        {"feature": "R15 Avantage permanent",
         "couvre": ["cap_caresser_entree", "cap_caresser_effet"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_REJEU, LOOP_JSON_REJEU)
    assert rep["status"] == "PASS"
    assert rep["roles_manquants"] == []
    assert rep["couvre_non_resolu"] == []


def test_rejeu_qui_cible_un_role_non_couvert_reste_fail():
    """Un rejeu n'hérite pas d'une preuve qui n'existe pas : si P04 n'est PAS
    PLAYER_LOOP, P09 (qui le rejoue) reste manquant, même avec un couvre bien
    formé citant des ids réels."""
    lignes = _lignes_normales_toutes_player_loop()
    lignes[3] = {"feature": "R5", "couvre": ["cap_bouton_producteur_actif"], "canal": "WHITE_BOX"}  # P04 dégradé
    wiremap = _wiremap(lignes + [
        {"feature": "R12 Rejeu de la boucle",
         "couvre": ["cap_caresser_entree", "cap_caresser_effet",
                    "cap_bouton_producteur_actif", "cap_acheter_producteur_entree",
                    "cap_acheter_producteur_effet"],
         "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_REJEU, LOOP_JSON_REJEU)
    assert rep["status"] == "FAIL"
    assert "P09" in rep["roles_manquants"]
    assert any("P04" in r and "P09" in r for r in rep["raisons"])


def test_rejeu_sans_replay_ni_replay_ref_est_signale():
    loop_json = {"steps": [{"role": "REPEAT", "ref": "P09"}]}
    wiremap = _wiremap([{"feature": "R12", "couvre": ["cap_x"], "canal": "WHITE_BOX"}])
    rep = check_player_loop_coverage(wiremap, {}, loop_json)
    assert rep["status"] == "FAIL"
    assert "P09" in rep["roles_manquants"]
    assert any("sans cible" in r for r in rep["raisons"])


def test_advantage_replay_ref_simple_fonctionne_comme_replay_liste():
    """ADVANTAGE (replay_ref, un seul ref) suit la même logique d'héritage que
    REPEAT (replay, liste)."""
    loop_json = {"steps": [
        {"role": "PLAYER_ACTION", "ref": "P02"},
        {"role": "ADVANTAGE", "ref": "P11", "replay_ref": "P02"},
    ]}
    featuremap = {"systemes": [{"features": [{"capacites": [
        {"id": "cap_p2", "source_ref": "P02"}]}]}]}
    wiremap_ok = _wiremap([
        {"feature": "R2", "couvre": ["cap_p2"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
        {"feature": "R15", "couvre": ["cap_p2"], "canal": "WHITE_BOX"},
    ])
    assert check_player_loop_coverage(wiremap_ok, featuremap, loop_json)["status"] == "PASS"

    wiremap_fail = _wiremap([
        {"feature": "R2", "couvre": ["cap_p2"], "canal": "WHITE_BOX"},
        {"feature": "R15", "couvre": ["cap_p2"], "canal": "WHITE_BOX"},
    ])
    rep = check_player_loop_coverage(wiremap_fail, featuremap, loop_json)
    assert rep["status"] == "FAIL"
    assert "P11" in rep["roles_manquants"]


# --- couvre_non_resolu : détection générale, pas seulement pour les rejeux ----

def test_couvre_non_resolu_sur_ligne_normale_aussi_detecte():
    """La détection n'est pas limitée aux rôles REJEU : toute ligne dont `couvre`
    ne résout à rien de réel est signalée, qu'elle documente un rôle normal ou
    non couvert par loop.json du tout."""
    wiremap = _wiremap([
        {"feature": "R99 orpheline", "couvre": ["nom_de_variable_invente"], "canal": "WHITE_BOX"},
        {"feature": "R2", "couvre": ["cap_caresser_entree"], "canal": "PLAYER_LOOP", "preuve_ref": "P02"},
    ])
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_REJEU, LOOP_JSON_REJEU)
    assert any("nom_de_variable_invente" in r for r in rep["couvre_non_resolu"])


def test_couvre_bien_forme_ne_declenche_aucune_fausse_alerte():
    wiremap = _wiremap(_lignes_normales_toutes_player_loop())
    rep = check_player_loop_coverage(wiremap, FEATUREMAP_REJEU, LOOP_JSON_REJEU)
    assert rep["couvre_non_resolu"] == []
