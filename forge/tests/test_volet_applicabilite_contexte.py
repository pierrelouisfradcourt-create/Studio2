# APPLICABILITE DES VOLETS AU CONTEXTE D'EXECUTION (GO Pierre 2026-08-17).
#
# REGLE RATIFIEE : avant d'interpreter un verdict, verifier que le contexte d'execution
# possede les PRODUCTEURS necessaires pour produire la preuve demandee. Un oracle qui juge
# au-dela de ce que son contexte peut produire ne mesure pas le produit — il mesure le
# contexte, et rend un rouge FABRIQUE.
#
# DEFAUT MESURE le 2026-08-17, sur les 4 jeux Godot du depot, y compris ceux dont s10a est OK :
#   `reuse_ratio_wired`  -> « run-oracle.mjs absent »  (absent des QUATRE jeux)
#   `search_consulted`   -> « aucune recherche journalisee » (contrat s9-build §2bis)
# Rouges STRUCTURELS, permanents, advisory — donc jamais bloquants, mais polluant
# l'instruction des vrais rouges. Ils ne sont PAS neufs : ils etaient invisibles tant
# qu'aucun recu n'existait (« observation nouvellement visible != evenement nouvellement
# produit »).
#
# MECANISME EXISTANT, APPLICATION INCOMPLETE — rien n'est invente ici. `driver.py:1697`
# traite deja `e2e` exactement ainsi : {status: SKIPPED, checked: False, reason} conditionne
# au profil, avec le commentaire « SKIPPED motive, JAMAIS un faux OK, JAMAIS un silence ».
# Et ce meme commentaire dit que `check_e2e_harness` fut saute parce qu'il « exige un
# run-oracle.mjs [...] topologie que le STANDARD n'utilise pas » : MEME FICHIER, MEME CAUSE
# que `reuse_ratio_wired`. Deux oracles dependaient du meme artefact ; un seul a ete traite
# en juillet. Ce lot applique la decision au second.
#
# DEUX CONDITIONS DISTINCTES, a ne pas confondre :
#   reuse_ratio_wired -> TOPOLOGIE (`_standard_topology()`), meme condition que e2e
#   search_consulted  -> PRESENCE D'UN BUILDER dans `self.order`, derivee du WORKFLOW REEL
#                        et jamais d'une liste de profils en dur (le studio a deja paye ce
#                        piege avec `_STANDARD_TOPOLOGY_PROFILES` et `standard_godot`).
#
# FORME DU SKIPPED : celle d'`e2e`, SANS clef `passed`. Verifie avant d'ecrire : AUCUN
# consommateur ne lit `passed` sur ces deux volets hors de leurs tests unitaires propres
# (`driver.py` ne fait que les ECRIRE ; `_volet_status` concerne les volets du recu PRODUIT).
# Un `passed: True` serait un faux vert, un `passed: False` un faux rouge : l'absence de
# booleen est la seule forme honnete quand aucun jugement n'a ete rendu.
from __future__ import annotations

from pathlib import Path

import pytest

from forge.dispatch import PROFILES
from forge.driver import ForgeDriver

BUILDERS = ("s9-build", "s9-build-standard", "s9-build-godot-standard")


REPO = Path(__file__).resolve().parents[2]


def _driver(tmp_path: Path, profile: str) -> ForgeDriver:
    # `src_root` est FOURNI : le CLI l'exige (`--src-root`, required=True) et un run reel
    # en a donc toujours un. L'omettre rendait la fixture infidele — `check_reuse_ratio_wired`
    # recevait None et levait, ce qui masquait le comportement teste.
    return ForgeDriver(project="p", run_id="r", run_dir=tmp_path, profile=profile,
                       executor=lambda *a, **k: {}, src_root=tmp_path)


# --- la condition « le contexte a-t-il le producteur ? » -----------------------------


def test_proof_only_n_a_AUCUN_builder(tmp_path):
    """LE CAS QUI FALSIFIE : `search_consulted` mesure une obligation de BUILDER, et
    `proof_only` n'en contient aucun. L'oracle ne peut rendre que rouge, par construction."""
    assert _driver(tmp_path, "proof_only")._profile_has_builder() is False


def test_les_profils_QUI_construisent_gardent_le_controle(tmp_path):
    """Contre-epreuve indispensable : on ne blanchit PAS un contexte ou le volet EST
    applicable. Partout ou un builder tourne, l'obligation §2bis reste jugee."""
    for p in ("standard", "standard_godot", "full", "full_godot", "patch", "micro",
              "increment"):
        assert _driver(tmp_path, p)._profile_has_builder() is True, p


def test_les_profils_SANS_builder_sont_tous_reconnus(tmp_path):
    for p in ("proof_only", "oracle_only", "review", "artbible", "amont_only"):
        assert _driver(tmp_path, p)._profile_has_builder() is False, p


def test_la_condition_est_DERIVEE_de_l_ordre_reel_pas_d_une_liste_en_dur(tmp_path):
    """Invariant d'architecture : la reponse doit se deduire de `self.order`. Un profil
    inconnu de toute liste figee doit etre classe correctement par la SEULE lecture de ses
    etapes — c'est ce qui a manque a `_STANDARD_TOPOLOGY_PROFILES` face a `standard_godot`."""
    for nom, etapes in PROFILES.items():
        attendu = any(e in BUILDERS for e in etapes)
        assert _driver(tmp_path, nom)._profile_has_builder() is attendu, nom


# --- la forme du SKIPPED --------------------------------------------------------------


def _volets_s10a(tmp_path: Path, profile: str) -> dict:
    """Les deux volets tels que s10a les poserait pour ce profil."""
    d = _driver(tmp_path, profile)
    return {
        "reuse_ratio_wired": d._volet_reuse_ratio_wired(),
        "search_consulted": d._volet_search_consulted(),
    }


def test_skipped_porte_un_MOTIF_et_jamais_un_faux_vert(tmp_path):
    """Meme forme qu'`e2e` : `status` SKIPPED, `checked` False, motif NON VIDE, et AUCUNE
    clef `passed` — l'absence de booleen est la seule forme honnete sans jugement rendu."""
    for nom, v in _volets_s10a(tmp_path, "proof_only").items():
        assert v["status"] == "SKIPPED", nom
        assert v["checked"] is False, nom
        assert v.get("reason"), f"{nom} : un SKIPPED sans motif est un silence"
        assert "passed" not in v, f"{nom} : ni faux vert ni faux rouge"


def test_le_motif_NOMME_le_producteur_manquant(tmp_path):
    """Un motif doit dire CE QUI manque, pas seulement qu'on a saute."""
    v = _volets_s10a(tmp_path, "proof_only")
    assert "run-oracle.mjs" in v["reuse_ratio_wired"]["reason"]
    assert "build" in v["search_consulted"]["reason"]


def test_un_contexte_APPLICABLE_est_toujours_JUGE(tmp_path):
    """LE GARDE-FOU CONTRE LE BLANCHIMENT. Sur un profil qui construit et n'est pas en
    topologie standard, les deux volets rendent un VERDICT (clef `passed`), jamais SKIPPED.
    Sans ce test, on aurait remplace un rouge structurel par un SILENCE structurel."""
    v = _volets_s10a(tmp_path, "full")
    for nom, r in v.items():
        assert r.get("status") != "SKIPPED", nom
        assert "passed" in r, f"{nom} : le jugement doit etre rendu quand il a un sens"


def test_reuse_ratio_est_saute_par_TOPOLOGIE_meme_avec_un_builder(tmp_path):
    """Les deux conditions sont INDEPENDANTES : `standard` a un builder — donc
    `search_consulted` est juge — mais sa topologie n'utilise pas `run-oracle.mjs`, donc
    `reuse_ratio_wired` est saute. Confondre les deux conditions casserait ce cas."""
    d = _driver(tmp_path, "standard")
    assert d._standard_topology() is True and d._profile_has_builder() is True
    assert d._volet_reuse_ratio_wired()["status"] == "SKIPPED"
    assert "passed" in d._volet_search_consulted()


def test_les_volets_restent_ADVISORY_car_JAMAIS_RELUS(tmp_path):
    """Ce lot ne change AUCUN verdict : il corrige la veracite des recus, rien d'autre.

    L'invariant est mesurable SANS ambiguite : ces deux cles sont ECRITES dans `detail` et
    jamais RELUES. Une valeur qu'aucune expression ne lit ne peut gater quoi que ce soit —
    c'est plus fort que constater l'absence du mot `oracle_ok` a proximite.
    (Premiere redaction de ce test : un grep de `oracle_ok` dans une fenetre de 2000
    caracteres. Il trouvait le mot DANS LE COMMENTAIRE qui affirme « ne gate JAMAIS
    oracle_ok » — une assertion incapable de distinguer une affirmation de sa negation ne
    mesure rien. Corrige ici plutot que contourne.)"""
    src = (REPO / "forge/driver.py").read_text(encoding="utf-8", errors="replace")
    for cle in ('detail["reuse_ratio_wired"]', 'detail["search_consulted"]'):
        assert src.count(cle) == 1, (
            f"{cle} apparait {src.count(cle)} fois : une seule ECRITURE est attendue, "
            "toute occurrence supplementaire serait une LECTURE — donc un gate potentiel")
