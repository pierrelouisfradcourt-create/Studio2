"""CV-4 (lot de dégel 1, 2026-07-30) — clause « SEARCH d'abord » portée au contrat
Godot (`s9-build-godot-standard.yaml`).

Défaut mesuré : la section `# --- 2bis. SEARCH d'abord ---` existe dans
`s9-build-standard.yaml` (contrat JS) et était ABSENTE de `s9-build-godot-standard.yaml`
(0 occurrence de "SEARCH" avant ce correctif). Le forgeron Godot n'était jamais consigné
tenu d'interroger `knowledge_base/search.mjs` avant d'écrire — seul le forgeron JS l'était.

Ce fichier vérifie UNIQUEMENT le TEXTE du contrat : présence de la clause, mention de
`knowledge_base/search.mjs`, obligation de rapporter (même vide), et que le contrat reste
chargeable par `forge.dispatch.load_contract` (le schéma des 17 champs n'est pas cassé
par l'ajout d'un commentaire de section)."""
from pathlib import Path

import yaml

from forge.dispatch import load_contract

_CONTRACTS_DIR = Path(__file__).resolve().parents[1] / "contracts"
_GODOT_CONTRACT = _CONTRACTS_DIR / "s9-build-godot-standard.yaml"
_JS_CONTRACT = _CONTRACTS_DIR / "s9-build-standard.yaml"


def test_clause_search_dabord_presente_dans_le_texte():
    text = _GODOT_CONTRACT.read_text(encoding="utf-8")
    assert "SEARCH d'abord" in text
    assert "knowledge_base/search.mjs" in text


def test_clause_exige_requete_obligatoire_meme_vide():
    text = _GODOT_CONTRACT.read_text(encoding="utf-8")
    assert "OBLIGATOIRE" in text
    assert "y compris vide" in text or "même vide" in text


def test_clause_interdit_modification_catalog():
    """Même garde-fou que le contrat JS : le forgeron ne modifie jamais catalog.json."""
    text = _GODOT_CONTRACT.read_text(encoding="utf-8")
    assert "catalog.json" in text
    assert "propose-only" in text


def test_clause_situee_entre_mandatory_read_et_mission():
    """Emplacement structurellement équivalent à la clause du contrat JS (entre la
    section 2 « Contexte projet » et la section 3 « Mission »)."""
    text = _GODOT_CONTRACT.read_text(encoding="utf-8")
    idx_search = text.index("2bis. SEARCH d'abord")
    idx_mandatory = text.index("mandatory_read:")
    idx_mission = text.index("# --- 3. Mission")
    assert idx_mandatory < idx_search < idx_mission


def test_contrat_reste_chargeable_apres_lajout():
    """L'ajout du commentaire de section ne casse pas le parsing YAML ni le schéma
    des 17 champs — `load_contract` doit toujours réussir."""
    contract = load_contract("s9-build-godot-standard")
    assert contract["role"]
    assert contract["objectif"]


def test_les_deux_contrats_portent_la_meme_exigence_de_fond():
    """Ne réinvente aucune exigence : la clause Godot et la clause JS demandent
    toutes deux (a) une recherche AVANT écriture, (b) via search.mjs, (c) rapportée
    même vide, (d) jamais d'écriture directe dans catalog.json."""
    godot_text = _GODOT_CONTRACT.read_text(encoding="utf-8")
    js_text = _JS_CONTRACT.read_text(encoding="utf-8")
    for fragment in ("search.mjs", "OBLIGATOIRE", "catalog.json"):
        assert fragment in godot_text
        assert fragment in js_text


def test_raw_yaml_parse_direct():
    """Chargement YAML brut (indépendant de load_contract) : le fichier reste un
    mapping valide, le champ mandatory_read une liste non vide."""
    data = yaml.safe_load(_GODOT_CONTRACT.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    assert isinstance(data["mandatory_read"], list) and data["mandatory_read"]
