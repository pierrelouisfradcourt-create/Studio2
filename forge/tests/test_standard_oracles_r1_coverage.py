"""Les 2 volets de preuve de boucle (R1, contrat `r1-preuves-boucle-mecaniques.yaml`,
2026-07-27) : `check_observable_coverage` et `check_genre_coverage`
(`forge/standard_oracles.py`).

Le livrable, ce sont les échecs : chaque volet est montré ROUGE sur au moins 2 cas
fabriqués DISTINCTS, puis VERT sur un cas conforme façonné à l'image de Pong (mêmes
identifiants de ligne, même forme de reçu que `product_oracle.run_product_oracle`).
Vocabulaire du patron Art Bible (`check_artbible.mjs`) : `FAIL` = malformé ·
`BLOCKED` = bien formé mais non couvert · `OK` = conforme et couvert.

Ces deux volets sont ADVISORY et branchés dans le reçu de `s10s-oracle-standard` —
le câblage driver est testé séparément (`test_driver_r1_coverage_wiring.py`). Ici,
les fonctions sont testées ISOLÉMENT (mêmes principes que `test_standard_oracles.py`) :
aucune exception sur entrée malformée, `passed`/`verdict` cohérents.
"""
from forge.standard_oracles import check_genre_coverage, check_observable_coverage


# =======================================================================================
# check_observable_coverage
# =======================================================================================


def _observable_line(**overrides) -> dict:
    base = {
        "id": "core.end_condition",
        "observable_by_player": True,
        "observable_proof": "auto_session",
    }
    base.update(overrides)
    return base


def _oracle_receipt(**overrides) -> dict:
    base = {
        "browser_import_safety": {"passed": True, "checked": True},
        "auto_session": {"passed": True, "checked": True, "finished": True},
        "visual_capture": {"status": "OK", "passed": True},
    }
    base.update(overrides)
    return base


# --- robustesse : jamais d'exception, jamais un vert par défaut sur entrée malformée ---


def test_observable_coverage_wiremap_non_dict_fail():
    rep = check_observable_coverage([], {})
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"


def test_observable_coverage_receipt_non_dict_traite_comme_vide():
    """Un reçu du mauvais type est traité comme vide (aucun volet disponible), jamais
    une exception : une ligne observable devient alors non couverte (BLOCKED), pas un
    crash — même discipline que les 6 autres oracles du module."""
    wiremap = {"lines": [_observable_line()]}
    rep = check_observable_coverage(wiremap, "pas un dict")
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert "core.end_condition:auto_session" in rep["volets_absents"]


def test_observable_coverage_aucune_ligne_observable_ok_par_vacuite():
    wiremap = {"lines": [{"id": "core.boot", "observable_by_player": False}]}
    rep = check_observable_coverage(wiremap, {})
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"


# --- RED #1 : ligne observable SANS observable_proof --------------------------------


def test_observable_coverage_red_ligne_sans_preuve_nommee():
    wiremap = {"lines": [_observable_line(observable_proof=None)]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert rep["lignes_sans_preuve"] == ["core.end_condition"]


def test_observable_coverage_red_observable_proof_chaine_vide():
    wiremap = {"lines": [_observable_line(observable_proof="   ")]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["verdict"] == "BLOCKED"
    assert rep["lignes_sans_preuve"] == ["core.end_condition"]


# --- RED #2 : volet nommé ABSENT du reçu ---------------------------------------------


def test_observable_coverage_red_volet_absent_du_recu():
    wiremap = {"lines": [_observable_line(observable_proof="volet_qui_nexiste_pas")]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert rep["volets_absents"] == ["core.end_condition:volet_qui_nexiste_pas"]


# --- RED #3 : volet nommé mais NOT_MEASURED ------------------------------------------


def test_observable_coverage_red_volet_not_measured_forme_status():
    wiremap = {"lines": [_observable_line(observable_proof="visual_capture")]}
    receipt = _oracle_receipt(visual_capture={"status": "NOT_MEASURED", "passed": False,
                                              "reason": "godot indisponible"})
    rep = check_observable_coverage(wiremap, receipt)
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert rep["volets_non_mesures"] == ["core.end_condition:visual_capture"]


def test_observable_coverage_red_volet_not_measured_forme_checked():
    wiremap = {"lines": [_observable_line(observable_proof="browser_import_safety")]}
    receipt = _oracle_receipt(browser_import_safety={"passed": False, "checked": False,
                                                      "reason": "entrée absente"})
    rep = check_observable_coverage(wiremap, receipt)
    assert rep["verdict"] == "BLOCKED"
    assert rep["volets_non_mesures"] == ["core.end_condition:browser_import_safety"]


# --- volet mesuré mais en ÉCHEC : non couvert (BLOCKED), pas une exception -----------


def test_observable_coverage_volet_mesure_en_echec_reste_bloque():
    wiremap = {"lines": [_observable_line(observable_proof="auto_session")]}
    receipt = _oracle_receipt(auto_session={"passed": False, "checked": True,
                                            "finished": False, "score_evolves": False})
    rep = check_observable_coverage(wiremap, receipt)
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert rep["volets_en_echec"] == ["core.end_condition:auto_session"]


# --- GARDE DE TYPE (ratifiée Pierre 2026-07-28, faux vert mesuré sur Snake) -----------


def test_observable_coverage_booleen_true_legal():
    wiremap = {"lines": [_observable_line()]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["observable_malformes"] == []


def test_observable_coverage_booleen_false_legal():
    wiremap = {"lines": [{"id": "core.boot", "observable_by_player": False}]}
    rep = check_observable_coverage(wiremap, {})
    assert rep["passed"] is True
    assert rep["observable_malformes"] == []


def test_observable_coverage_champ_absent_legal():
    wiremap = {"lines": [{"id": "core.boot"}]}
    rep = check_observable_coverage(wiremap, {})
    assert rep["passed"] is True
    assert rep["observable_malformes"] == []


def test_observable_coverage_red_observable_by_player_chaine_est_malforme():
    """Une phrase de justification à la place du booléen attendu : le point de la
    garde 2026-07-28 — avant elle, cette ligne était silencieusement traitée comme
    `!= True` (donc ignorée, jamais couverte ni signalée)."""
    wiremap = {"lines": [{
        "id": "params.bloc_unique",
        "observable_by_player": "Indirectement mais reellement : ces constantes...",
        "observable_proof": "Modifier la constante et relancer.",
    }]}
    rep = check_observable_coverage(wiremap, {})
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"
    assert rep["observable_malformes"] == [{
        "id": "params.bloc_unique", "champ": "observable_by_player", "type_recu": "str",
    }]


def test_observable_coverage_red_observable_proof_phrase_alors_que_observable():
    """Ligne réellement observable (`True`) mais `observable_proof` porte une phrase
    de méthode au lieu d'un nom de volet -> malformé, pas juste "sans preuve"."""
    wiremap = {"lines": [_observable_line(
        observable_proof="Bot qui atteint la cible : l'ecran affiche gagnee",
    )]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"
    assert rep["observable_malformes"] == [{
        "id": "core.end_condition", "champ": "observable_proof",
        "type_recu": "str_avec_espaces",
    }]


def test_observable_coverage_carte_malformee_denonce_toutes_les_lignes():
    """Preuve n°2 du contrat (critère (d)) : une carte dont les lignes portent une
    PHRASE dans `observable_by_player` doit être dénoncée LIGNE PAR LIGNE — jamais
    laissée passer par vacuité (le défaut d'origine : `is not True` faisait sauter
    la ligne en silence, `couvertes: []` et `passed: true`).

    FIXTURE DÉDIÉE (gate Pierre 2026-07-29) : ce test lisait auparavant la VRAIE
    wiremap de `GAMES/snake` et figeait son état du moment (44 lignes malformées).
    Corriger les données du jeu — ce qui était l'objectif — le rendait faux : il
    testait l'état d'un JEU au lieu de la propriété d'un INSTRUMENT (règle d'usine
    n°3 : un test vérifie une propriété durable, pas une valeur historique).
    La fixture ci-dessous ne dépend d'aucun jeu et ne peut plus périmer.
    """
    lignes = [
        {"id": f"ligne.{i}",
         "observable_by_player": f"Le joueur voit la chose {i} — justification en prose.",
         "observable_proof": "Une phrase de methode, pas un nom de volet."}
        for i in range(5)
    ]
    # Une ligne CORRECTE au milieu : la garde doit discriminer, pas tout rougir.
    lignes.append({"id": "ligne.correcte", "observable_by_player": True,
                   "observable_proof": "auto_session"})
    rep = check_observable_coverage(
        {"lines": lignes}, {"auto_session": {"checked": True, "passed": True}}
    )
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"
    # TOUTES les malformées sont nommées, aucune n'est sautée en silence.
    assert len(rep["observable_malformes"]) == 5
    assert {e["id"] for e in rep["observable_malformes"]} == {f"ligne.{i}" for i in range(5)}
    for entry in rep["observable_malformes"]:
        assert entry["champ"] == "observable_by_player"
        assert entry["type_recu"] == "str"
    # La ligne bien formée reste couverte : la garde discrimine la FORME, pas le jeu.
    assert any("ligne.correcte" in str(c) for c in rep["couvertes"])


def test_observable_coverage_wiremap_pong_reel_reste_vert():
    """Non-régression : la VRAIE wiremap Pong (forme correcte, booléens + noms de
    volet) doit rester OK avec un reçu où les 6 volets nommés sont verts."""
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    wiremap = json.loads(
        (root / "GAMES/pong/09_WIREMAP/wiremap.json").read_text(encoding="utf-8")
    )
    receipt = {
        "auto_session": {"passed": True, "checked": True},
        "restart_offer_wiring": {"passed": True, "checked": True},
        "exit_stop_wiring": {"passed": True, "checked": True},
        "solo_ai_session": {"passed": True, "checked": True},
        "playable_speed_band_test": {"passed": True, "checked": True},
    }
    rep = check_observable_coverage(wiremap, receipt)
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"
    assert rep["observable_malformes"] == []


# --- GREEN : conforme et couvert, façonné à l'image de Pong (mêmes ids/volets) -------


def test_observable_coverage_green_pong_shape_ok():
    wiremap = {"lines": [
        _observable_line(id="core.end_condition", observable_proof="auto_session"),
        _observable_line(id="play.score", observable_proof="auto_session"),
        _observable_line(id="core.exit", observable_proof="browser_import_safety"),
        {"id": "core.boot", "observable_by_player": False},  # ligne non observable, ignorée
    ]}
    rep = check_observable_coverage(wiremap, _oracle_receipt())
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"
    assert rep["couvertes"] == [
        "core.end_condition:auto_session",
        "play.score:auto_session",
        "core.exit:browser_import_safety",
    ]
    assert rep["lignes_sans_preuve"] == []
    assert rep["volets_absents"] == []
    assert rep["volets_non_mesures"] == []
    assert rep["volets_en_echec"] == []


# =======================================================================================
# check_genre_coverage
# =======================================================================================


def _genre_bible(**overrides) -> dict:
    base = {"genre_rules": [
        {"id": "genre.pong.two_paddles_vertical", "applies_to_wiremap_line": "play.paddle"},
        {"id": "genre.pong.playable_speed_range", "applies_to_wiremap_line": "play.playable_speed"},
    ]}
    base.update(overrides)
    return base


# --- robustesse -----------------------------------------------------------------------


def test_genre_coverage_wiremap_non_dict_fail():
    rep = check_genre_coverage([], _genre_bible())
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"


def test_genre_coverage_genre_bible_non_dict_fail():
    rep = check_genre_coverage({"lines": []}, "pas un dict")
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"


def test_genre_coverage_genre_rules_pas_une_liste_fail():
    rep = check_genre_coverage({"lines": []}, {"genre_rules": "pas une liste"})
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"


def test_genre_coverage_genre_rules_vide_ok_par_vacuite():
    rep = check_genre_coverage({"lines": []}, {"genre_rules": []})
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"


# --- RED #1 : règle applicable NI citée NI refusée ------------------------------------


def test_genre_coverage_red_regle_ni_citee_ni_refusee():
    wiremap = {"lines": [{"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]}]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["passed"] is False
    assert rep["verdict"] == "BLOCKED"
    assert rep["regles_non_couvertes"] == ["genre.pong.playable_speed_range"]


def test_genre_coverage_red_aucune_ligne_aucune_citation():
    wiremap = {"lines": [{"id": "core.boot"}]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["verdict"] == "BLOCKED"
    assert set(rep["regles_non_couvertes"]) == {
        "genre.pong.two_paddles_vertical", "genre.pong.playable_speed_range",
    }


# --- RED #2 : citation qui ne RÉSOUT PAS (id inexistant) -> FAIL, priorité sur BLOCKED -


def test_genre_coverage_red_citation_id_inexistant_fail():
    wiremap = {"lines": [
        {"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]},
        {"id": "play.playable_speed", "genre_refs": ["genre.pong.id_qui_nexiste_pas"]},
    ]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["passed"] is False
    assert rep["verdict"] == "FAIL"
    assert rep["citations_non_resolues"] == ["play.playable_speed:genre.pong.id_qui_nexiste_pas"]


def test_genre_coverage_citation_fail_prioritaire_sur_blocked():
    """Même si une AUTRE règle est aussi non couverte, une citation cassée rend FAIL,
    pas BLOCKED — une preuve d'échec l'emporte sur une absence de preuve (même
    arbitrage que `_run_standard_oracle` pour budget/autres volets)."""
    wiremap = {"lines": [
        {"id": "play.playable_speed", "genre_refs": ["genre.pong.id_fantome"]},
    ]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["verdict"] == "FAIL"


# --- refus explicite : couvre une règle SANS citation, si la raison est non vide ------


def test_genre_coverage_refus_explicite_avec_raison_couvre_la_regle():
    wiremap = {
        "lines": [{"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]}],
        "genre_refusals": [
            {"rule_id": "genre.pong.playable_speed_range",
             "reason": "hors périmètre de ce nœud du curriculum, décision Pierre 2026-07-27"},
        ],
    }
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"
    assert rep["refusees"] == ["genre.pong.playable_speed_range"]


def test_genre_coverage_refus_sans_raison_ne_couvre_pas():
    wiremap = {
        "lines": [{"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]}],
        "genre_refusals": [{"rule_id": "genre.pong.playable_speed_range", "reason": ""}],
    }
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["verdict"] == "BLOCKED"
    assert rep["regles_non_couvertes"] == ["genre.pong.playable_speed_range"]


# --- GREEN : conforme et couvert, façonné à l'image de Pong (mêmes ids réels) ---------


def test_genre_coverage_green_pong_shape_ok():
    wiremap = {"lines": [
        {"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]},
        {"id": "play.playable_speed", "genre_refs": ["genre.pong.playable_speed_range"]},
    ]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["passed"] is True
    assert rep["verdict"] == "OK"
    assert rep["regles_non_couvertes"] == []
    assert rep["citations_non_resolues"] == []
    assert set(rep["citees"]) == {
        "play.paddle:genre.pong.two_paddles_vertical",
        "play.playable_speed:genre.pong.playable_speed_range",
    }


# --- ratio de résolution (taux_resolution, mission N2-0 2026-07-28) -------------------


def test_genre_coverage_taux_resolution_aucune_citation_none():
    """0 citation revendiquée -> None, jamais un 1.0 gratuit sur l'absence de données
    (règle de variance des métriques, ratifiée Pierre 2026-07-21)."""
    wiremap = {"lines": [{"id": "core.boot"}]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["citations_revendiquees"] == 0
    assert rep["citations_resolues"] == 0
    assert rep["taux_resolution"] is None


def test_genre_coverage_taux_resolution_toutes_resolues_1_0():
    wiremap = {"lines": [
        {"id": "play.paddle", "genre_refs": ["genre.pong.two_paddles_vertical"]},
        {"id": "play.playable_speed", "genre_refs": ["genre.pong.playable_speed_range"]},
    ]}
    rep = check_genre_coverage(wiremap, _genre_bible())
    assert rep["citations_revendiquees"] == 2
    assert rep["citations_resolues"] == 2
    assert rep["taux_resolution"] == 1.0


def test_genre_coverage_taux_resolution_partiel_0_75():
    genre_bible = _genre_bible(genre_rules=[
        {"id": "g.a"}, {"id": "g.b"}, {"id": "g.c"}, {"id": "g.d"},
    ])
    wiremap = {"lines": [
        {"id": "l1", "genre_refs": ["g.a", "g.b", "g.c"]},
        {"id": "l2", "genre_refs": ["g.fantome"]},
    ]}
    rep = check_genre_coverage(wiremap, genre_bible)
    assert rep["citations_revendiquees"] == 4
    assert rep["citations_resolues"] == 3
    assert rep["taux_resolution"] == 0.75


# --- preuve n°1 de la boucle (critère (c) du contrat) : lu sur les VRAIS artefacts ----


def test_genre_coverage_preuve_n1_sur_les_vrais_artefacts_pong():
    """Charge le VRAI wiremap.json et la VRAIE genre_bible.json de Pong (pas des
    fixtures) : au moins une citation RÉSOUT — la preuve que la Genre Bible a été lue
    avant/pendant la conception plutôt que d'être une bible que personne ne cite."""
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    wiremap = json.loads((root / "GAMES/pong/09_WIREMAP/wiremap.json").read_text(encoding="utf-8"))
    genre_bible = json.loads((root / "GAMES/pong/01_DESIGN/genre_bible.json").read_text(encoding="utf-8"))

    rep = check_genre_coverage(wiremap, genre_bible)
    assert rep["verdict"] == "OK", rep
    assert len(rep["citees"]) >= 1
    assert rep["citations_non_resolues"] == []
