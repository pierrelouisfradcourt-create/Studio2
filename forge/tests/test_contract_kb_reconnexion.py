# Reconnexion KB (ratifiée Pierre 2026-08-13) — les fiches CITÉES par le champ
# `memoire` d'un contrat sont résolues mécaniquement depuis le catalogue ratifié et
# servies dans le prompt.
#
# Dette de preuve fermée ici : le code était CÂBLÉ (`_render_prompt` appelle
# `_render_kb_section(kb_fiches_citees(...))`) et 80/80 tests de non-régression des
# consommateurs passaient — mais AUCUN test ne couvrait le comportement neuf. Ces
# tests portent sur ce que les docstrings promettent, jamais sur une intention
# supposée. Le cas le plus important est le catalogue injoignable : c'est un défaut
# RÉEL trouvé par falsification le 2026-08-13, pas une précaution théorique.
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.contract import _cited_identities, _render_kb_section, kb_fiches_citees


def _catalog(tmp_path: Path, entries: list[dict]) -> Path:
    p = tmp_path / "catalog.json"
    p.write_text(json.dumps({"catalog_version": 1, "entries": entries},
                            ensure_ascii=False), encoding="utf-8")
    return p


_FICHE = {
    "brick_id": "pat-forge-oracle-vacuite",
    "tier": "2",
    "function": "Un oracle vert sur une liste vide ne mesure rien.",
    "provenance_internal": {"lesson_id": "forge.oracle_vacuite"},
}


def test_fiche_citee_est_servie_avec_son_enonce_de_reference(tmp_path):
    cat = _catalog(tmp_path, [_FICHE])
    out = kb_fiches_citees("Voir pat-forge-oracle-vacuite avant de conclure.",
                           catalog_path=cat, proposals_dir=tmp_path / "vide")
    assert out["en_attente_de_ratification"] == []
    assert len(out["servies"]) == 1
    servie = out["servies"][0]
    assert servie["id"] == "pat-forge-oracle-vacuite"
    assert servie["tier"] == "2"
    # énoncé SERVI TEL QUEL, jamais reformulé (contrat de la docstring)
    assert servie["enonce"] == _FICHE["function"]


def test_citation_par_lesson_id_resout_la_meme_fiche(tmp_path):
    # Le catalogue déclare lui-même l'équivalence brick_id <-> lesson_id ; c'est
    # `forge.<slug>` que les contrats écrivent en pratique.
    cat = _catalog(tmp_path, [_FICHE])
    out = kb_fiches_citees("leçon forge.oracle_vacuite", catalog_path=cat,
                           proposals_dir=tmp_path / "vide")
    assert [s["id"] for s in out["servies"]] == ["pat-forge-oracle-vacuite"]


def test_deux_identites_de_la_meme_fiche_ne_la_servent_qu_une_fois(tmp_path):
    cat = _catalog(tmp_path, [_FICHE])
    out = kb_fiches_citees("pat-forge-oracle-vacuite ET forge.oracle_vacuite",
                           catalog_path=cat, proposals_dir=tmp_path / "vide")
    assert len(out["servies"]) == 1, "une fiche citée deux fois reste UNE fiche"


def test_fiche_seulement_proposee_est_en_attente_sans_servir_son_contenu(tmp_path):
    cat = _catalog(tmp_path, [_FICHE])
    prop = tmp_path / "proposals"
    prop.mkdir()
    (prop / "forge.pas_encore_ratifiee.yaml").write_text("name: x", encoding="utf-8")
    out = kb_fiches_citees("cf. forge.pas_encore_ratifiee", catalog_path=cat,
                           proposals_dir=prop)
    assert out["servies"] == []
    assert out["en_attente_de_ratification"] == ["forge.pas_encore_ratifiee"]


def test_identite_proposee_illisible_reste_une_identite(tmp_path):
    # AUCUN parsing du contenu : le nom de fichier EST l'identité (4 fiches réelles
    # n'étaient pas du YAML valide le 2026-08-13).
    cat = _catalog(tmp_path, [])
    prop = tmp_path / "proposals"
    prop.mkdir()
    (prop / "forge.corrompue.yaml").write_text("{{ pas du yaml", encoding="utf-8")
    out = kb_fiches_citees("forge.corrompue", catalog_path=cat, proposals_dir=prop)
    assert out["en_attente_de_ratification"] == ["forge.corrompue"]


def test_identite_inconnue_n_est_pas_rapportee(tmp_path):
    # Ni servie, ni « en attente » : on ne sait pas si c'est une faute de frappe ou
    # une connaissance qui vit ailleurs — inventer ce diagnostic serait une devinette.
    cat = _catalog(tmp_path, [_FICHE])
    out = kb_fiches_citees("cf. forge.nexiste_nulle_part", catalog_path=cat,
                           proposals_dir=tmp_path / "vide")
    assert out == {"servies": [], "en_attente_de_ratification": []}


def test_catalogue_injoignable_ne_dit_RIEN(tmp_path):
    # LE cas fondateur (falsification 2026-08-13) : « non mesurable » ne se maquille
    # ni en échec ni en succès. Un catalogue absent ne doit JAMAIS faire dire d'une
    # fiche ratifiée qu'elle attend sa ratification.
    prop = tmp_path / "proposals"
    prop.mkdir()
    (prop / "forge.oracle_vacuite.yaml").write_text("name: x", encoding="utf-8")
    out = kb_fiches_citees("pat-forge-oracle-vacuite et forge.oracle_vacuite",
                           catalog_path=tmp_path / "absent.json", proposals_dir=prop)
    assert out == {"servies": [], "en_attente_de_ratification": []}


def test_catalogue_illisible_traite_comme_injoignable(tmp_path):
    bad = tmp_path / "catalog.json"
    bad.write_text("{ pas du json", encoding="utf-8")
    out = kb_fiches_citees("pat-forge-oracle-vacuite", catalog_path=bad,
                           proposals_dir=tmp_path / "vide")
    assert out == {"servies": [], "en_attente_de_ratification": []}


def test_catalogue_vide_est_distinct_d_un_catalogue_absent(tmp_path):
    # Lu mais sans entrée : une identité proposée peut alors être qualifiée.
    cat = _catalog(tmp_path, [])
    prop = tmp_path / "proposals"
    prop.mkdir()
    (prop / "forge.en_attente.yaml").write_text("name: x", encoding="utf-8")
    out = kb_fiches_citees("forge.en_attente", catalog_path=cat, proposals_dir=prop)
    assert out["en_attente_de_ratification"] == ["forge.en_attente"]


def test_memoire_vide_ou_liste(tmp_path):
    cat = _catalog(tmp_path, [_FICHE])
    vide = tmp_path / "vide"
    assert kb_fiches_citees("", catalog_path=cat, proposals_dir=vide)["servies"] == []
    assert kb_fiches_citees(None, catalog_path=cat, proposals_dir=vide)["servies"] == []
    out = kb_fiches_citees(["ligne neutre", "cf. pat-forge-oracle-vacuite"],
                           catalog_path=cat, proposals_dir=vide)
    assert len(out["servies"]) == 1, "une `memoire` en liste est jointe, pas ignorée"


def test_identite_incluse_dans_une_autre_est_ecartee():
    # Citer `pat-forge-x` ne doit pas servir aussi une hypothétique `forge-x`.
    assert _cited_identities("cf. pat-forge-x", {"pat-forge-x", "forge-x"}) == ["pat-forge-x"]


def test_aucune_fiche_citee_laisse_le_prompt_strictement_inchange():
    # Cas de 47 des 48 contrats : la section n'existe pas du tout.
    assert _render_kb_section({"servies": [], "en_attente_de_ratification": []}) is None


def test_section_rendue_porte_l_enonce_servi_et_l_identite_en_attente():
    corps = _render_kb_section({
        "servies": [{"cite": "forge.x", "id": "pat-forge-x", "tier": "2",
                     "enonce": "ENONCE DE REFERENCE"}],
        "en_attente_de_ratification": ["forge.en_attente"],
    })
    assert corps is not None
    assert "ENONCE DE REFERENCE" in corps
    assert "pat-forge-x" in corps
    assert "forge.en_attente" in corps
