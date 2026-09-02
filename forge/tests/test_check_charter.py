"""Oracle CHARTER (R7, FORGE_V2_CONSOLIDATION.md §4-A) — check_charter.

Le contrat s0-contrat exige en prose que charter.yaml porte 4 champs originaux
(objectif, hors_scope[], criteres_succes[], actions_interdites[]) PLUS 3 champs de
design-intent (plateforme_cible, reference_jeu, criteres_demo[]) sans « à définir »
résiduel. check_charter le vérifie MÉCANIQUEMENT — {passed, raisons[]}, jamais
d'exception sur entrée malformée. NO_CLAIM_ALLOWED.
"""
from forge.static_oracles import check_charter


def _charter_complet(**overrides) -> dict:
    base = {
        "objectif": "Livrer un shmup 2D vertical jouable au clavier.",
        "hors_scope": ["multijoueur", "monétisation"],
        "criteres_succes": ["3 vagues d'ennemis", "1 boss final"],
        "actions_interdites": ["toucher tests/", "toucher src/"],
        "plateforme_cible": "web/HTML5",
        "reference_jeu": "Galaga (choisi par Pierre, session du 2026-07-14)",
        "criteres_demo": ["une flèche visible qui vole à l'écran", "un boss visible qui explose"],
    }
    base.update(overrides)
    return base


# --- vert : charter complet ---------------------------------------------------------

def test_charter_complet_pass():
    rep = check_charter(_charter_complet())
    assert rep["passed"] is True
    assert rep["raisons"] == []


# --- rouge : champ requis manquant ---------------------------------------------------

def test_champ_scalaire_manquant_fail():
    charter = _charter_complet()
    del charter["objectif"]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert any("objectif" in r for r in rep["raisons"])


def test_champ_scalaire_vide_fail():
    rep = check_charter(_charter_complet(plateforme_cible="   "))
    assert rep["passed"] is False
    assert any("plateforme_cible" in r for r in rep["raisons"])


def test_champ_liste_manquant_fail():
    charter = _charter_complet()
    del charter["hors_scope"]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert any("hors_scope" in r for r in rep["raisons"])


def test_champ_liste_vide_fail():
    rep = check_charter(_charter_complet(criteres_succes=[]))
    assert rep["passed"] is False
    assert any("criteres_succes" in r for r in rep["raisons"])


def test_item_de_liste_vide_fail():
    rep = check_charter(_charter_complet(actions_interdites=["toucher tests/", "  "]))
    assert rep["passed"] is False
    assert any("actions_interdites[1]" in r for r in rep["raisons"])


# --- rouge : « à définir » (accents/casse variés) ------------------------------------

def test_a_definir_scalaire_fail():
    rep = check_charter(_charter_complet(objectif="à définir"))
    assert rep["passed"] is False
    assert any("objectif" in r and "à définir" in r for r in rep["raisons"])


def test_a_definir_casse_et_accents_varies_fail():
    variantes = ["À DÉFINIR", "a definir", "A Definir", "à Definir", "À définir"]
    for variante in variantes:
        rep = check_charter(_charter_complet(reference_jeu=variante))
        assert rep["passed"] is False, f"variante non détectée : {variante!r}"
        assert any("reference_jeu" in r for r in rep["raisons"])


def test_a_definir_dans_item_de_liste_fail():
    rep = check_charter(_charter_complet(criteres_demo=["une flèche visible", "à Définir"]))
    assert rep["passed"] is False
    assert any("criteres_demo[1]" in r for r in rep["raisons"])


def test_a_definir_ne_flag_pas_un_faux_positif():
    # 'defini' seul (sans 'a ') ne doit pas déclencher le motif « à définir ».
    rep = check_charter(_charter_complet(objectif="Un objectif bien défini et concret."))
    assert rep["passed"] is True


# --- rouge : design-intent (R7) absent -----------------------------------------------

def test_design_intent_plateforme_cible_absente_fail():
    charter = _charter_complet()
    del charter["plateforme_cible"]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert any("plateforme_cible" in r for r in rep["raisons"])


def test_design_intent_reference_jeu_absente_fail():
    charter = _charter_complet()
    del charter["reference_jeu"]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert any("reference_jeu" in r for r in rep["raisons"])


def test_design_intent_criteres_demo_absents_fail():
    charter = _charter_complet()
    del charter["criteres_demo"]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert any("criteres_demo" in r for r in rep["raisons"])


def test_design_intent_tous_absents_toutes_les_raisons_listees():
    charter = _charter_complet()
    for champ in ("plateforme_cible", "reference_jeu", "criteres_demo"):
        del charter[champ]
    rep = check_charter(charter)
    assert rep["passed"] is False
    assert len(rep["raisons"]) == 3
    for champ in ("plateforme_cible", "reference_jeu", "criteres_demo"):
        assert any(champ in r for r in rep["raisons"])


# --- entrée malformée : FAIL honnête, jamais une exception --------------------------

def test_charter_non_dict_fail_honnete():
    rep = check_charter(["pas un charter"])
    assert rep["passed"] is False
    assert rep["raisons"]


def test_charter_none_fail_honnete():
    rep = check_charter(None)
    assert rep["passed"] is False


def test_champ_liste_avec_type_inattendu_fail_honnete():
    rep = check_charter(_charter_complet(hors_scope="pas une liste"))
    assert rep["passed"] is False
    assert any("hors_scope" in r for r in rep["raisons"])


def test_champ_scalaire_avec_type_inattendu_fail_honnete():
    rep = check_charter(_charter_complet(objectif=["pas une chaine"]))
    assert rep["passed"] is False
    assert any("objectif" in r for r in rep["raisons"])
