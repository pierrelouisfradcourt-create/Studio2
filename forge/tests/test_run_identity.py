# -*- coding: utf-8 -*-
"""RUN_IDENTITY_V1 — le contrat des quatre dimensions d'un run (GO Pierre 2026-08-19).

UN SEUL CHAMP portait quatre sens. `project` servait a la fois de nom de jeu (`tetris`),
d'identifiant d'execution (`shmup_slice_patch2`), de portee (`driver_smoke`) et de nature
(`story_probe`). Le contrat separe ces sens en dimensions, chacune avec UNE semantique.

MESURE QUI FONDE CHAQUE DIMENSION — population reelle, 149 identifiants / 5179 enregistrements
de `EVIDENCE/bundles/*.jsonl`, 78 run_dirs, 28 projets observes :

  PROJECT_ID != RUN_ID   `shmup_slice_patch2` declare `is_game=True` sans etre dans `GAMES/` :
                         c'est un RUN SUR `shmup_slice`. Les deux vivaient dans un champ.
  RUN_ID requis          27 % des enregistrements SIGNES n'ont pas de `run_id`, et
                         `_belongs_to_project` rend False sur vide -> invisibles a TOUS les
                         rapports. Rupture de tracabilite, pas defaut de proprete.
  SCOPE                  le residu non classable contenait une nature entiere : les runs sur
                         l'USINE (`driver_smoke`, `p1-injection`, `charte2`, `amont-narratif`).
                         PRODUCT | FACTORY est le socle DEJA ratifie (deux registres de
                         capacites) — applique ici aux runs. Fige Pierre 2026-08-19.
  MODE                   `dryrun` etait sur le point d'entrer comme NATURE. C'est un MODE :
                         un run reel sans effet reste un run reel. `_is_dryrun` (audit) le
                         traite deja comme une annotation, jamais comme une categorie.
  NATURE                 laissee OUVERTE. L'hypothese `real|fixture|selftest|probe` couvrait
                         57 % des enregistrements et laissait 71 identifiants sur 149 hors
                         classement : FALSIFIEE. On ne fige pas ce qu'on n'a pas mesure.

REGLE CARDINALE (ratifiee Pierre 2026-08-19) :
    Une dimension inconnue reste EXPLICITEMENT inconnue. Elle n'est JAMAIS remplacee par une
    valeur inventee pour satisfaire un schema. Un champ rempli par defaut rend l'ignorance
    indetectable — c'est pire que l'ignorance.

`audit.py` porte deja la moitie de cette doctrine : « les champs de payload sont OPTIONNELS ...
vide = "non connu a ce point", jamais "aucun" ». Mais `run_id` N'EST PAS un champ de payload :
c'est un tiers du triplet de correlation `(etape, run_id, attempt)`. Le contrat nomme la
distinction que le producteur documentait sans l'imposer.
"""
from __future__ import annotations

import json
import pathlib

import pytest

from forge.run_identity import (
    MODES,
    NATURE_UNKNOWN,
    SCOPES,
    RunIdentityViolation,
    check_run_identity,
    validate_run_identity,
)


VALIDE = {"project_id": "tetris", "run_id": "tetris-20260817-090000",
          "scope": "PRODUCT", "mode": "live"}


# --- le vocabulaire fige, et LUI SEUL ------------------------------------------------------


def test_SCOPE_a_exactement_les_deux_valeurs_ratifiees():
    assert SCOPES == ("PRODUCT", "FACTORY")


def test_MODE_n_a_que_des_valeurs_ATTESTEES():
    """`dryrun` est mesure (445 enregistrements, predicat `_is_dryrun`) ; `live` en est le
    complement exact. Aucune troisieme valeur n'a ete observee, donc aucune n'est inventee."""
    assert MODES == ("live", "dryrun")


def test_NATURE_n_est_PAS_un_vocabulaire_ferme():
    """Le coeur de la regle cardinale. Figer NATURE aujourd'hui reproduirait l'erreur deja
    falsifiee : 71 identifiants sur 149 hors classement."""
    from forge import run_identity
    assert not hasattr(run_identity, "NATURES"), \
        "aucune enumeration de NATURE ne doit exister tant qu'elle n'est pas mesuree"
    assert NATURE_UNKNOWN == "UNKNOWN"


# --- les quatre dimensions sont REQUISES ---------------------------------------------------


def test_une_identite_complete_est_ACCEPTEE():
    out = validate_run_identity(VALIDE)
    assert out["project_id"] == "tetris"
    assert out["run_id"] == "tetris-20260817-090000"


@pytest.mark.parametrize("manquante", ["project_id", "run_id", "scope", "mode"])
def test_chaque_dimension_MANQUANTE_est_refusee(manquante):
    ident = {k: v for k, v in VALIDE.items() if k != manquante}
    with pytest.raises(RunIdentityViolation, match=manquante):
        validate_run_identity(ident)


@pytest.mark.parametrize("vide", ["", "   ", None])
def test_un_RUN_ID_vide_est_refuse(vide):
    """LA rupture mesuree : 1398 enregistrements signes sans identite, invisibles a tous les
    rapports parce que `_belongs_to_project` rend False sur vide. Le contrat la ferme au
    niveau ou l'identite se DECLARE."""
    with pytest.raises(RunIdentityViolation, match="run_id"):
        validate_run_identity({**VALIDE, "run_id": vide})


@pytest.mark.parametrize("vide", ["", "   ", None])
def test_un_PROJECT_ID_vide_est_refuse(vide):
    with pytest.raises(RunIdentityViolation, match="project_id"):
        validate_run_identity({**VALIDE, "project_id": vide})


# --- PROJECT_ID et RUN_ID : deux CHAMPS, pas une contrainte d'inegalite --------------------


def test_PROJECT_ID_et_RUN_ID_PEUVENT_etre_egaux():
    """Le defaut n'est PAS qu'ils se ressemblent, c'est qu'UN champ portait DEUX sens.

    Mesure : `driver_smoke_v6_20260808` a exactement cette valeur dans `state.json.project`
    ET comme base de son `run_id`. Interdire l'egalite rejetterait la realite observee et
    remplacerait une confusion de niveau par une contrainte arbitraire.
    """
    ident = validate_run_identity({**VALIDE, "project_id": "driver_smoke_v6_20260808",
                                   "run_id": "driver_smoke_v6_20260808",
                                   "scope": "FACTORY"})
    assert ident["project_id"] == ident["run_id"]


def test_le_cas_qui_a_REVELE_la_confusion_se_declare_maintenant_sans_ambiguite():
    """`shmup_slice_patch2` : un RUN sur le PROJET `shmup_slice`. C'est le cas qui a prouve
    que les deux sens vivaient dans un seul champ."""
    ident = validate_run_identity({"project_id": "shmup_slice",
                                   "run_id": "shmup_slice_patch2-20260718a",
                                   "scope": "PRODUCT", "mode": "live"})
    assert ident["project_id"] != ident["run_id"]


# --- les vocabulaires fermes REFUSENT ce qu'ils ne connaissent pas -------------------------


@pytest.mark.parametrize("mauvais", ["product", "Product", "GAME", "usine", ""])
def test_un_SCOPE_hors_vocabulaire_est_refuse(mauvais):
    with pytest.raises(RunIdentityViolation, match="scope"):
        validate_run_identity({**VALIDE, "scope": mauvais})


@pytest.mark.parametrize("mauvais", ["LIVE", "DRYRUN", "fixture", "reel", ""])
def test_un_MODE_hors_vocabulaire_est_refuse(mauvais):
    """`fixture` est refuse ICI : c'est une NATURE presumee, pas un mode. Sans ce refus, la
    dimension que l'on a justement laissee ouverte se remplirait par la porte de service."""
    with pytest.raises(RunIdentityViolation, match="mode"):
        validate_run_identity({**VALIDE, "mode": mauvais})


# --- NATURE : ouverte, mais jamais IMPLICITE ----------------------------------------------


def test_une_NATURE_ABSENTE_devient_UNKNOWN_EXPLICITE():
    assert validate_run_identity(VALIDE)["nature"] == NATURE_UNKNOWN


def test_une_NATURE_LIBRE_est_acceptee_TELLE_QUELLE():
    """Ouverte veut dire ouverte : le contrat n'arbitre pas entre `audit`, `asset`, `fixture`
    tant que la mesure ne les a pas separes."""
    for libre in ("fixture", "audit", "asset", "campagne", "sonde"):
        assert validate_run_identity({**VALIDE, "nature": libre})["nature"] == libre


@pytest.mark.parametrize("floue", ["", "   ", None])
def test_une_NATURE_VIDE_est_REFUSEE_et_non_convertie_en_UNKNOWN(floue):
    """La regle cardinale, dans son sens le plus strict. ABSENT = « je n'ai pas la dimension »
    et devient UNKNOWN. VIDE = « j'ai le champ mais je n'ai rien mis » : c'est une ignorance
    DEGUISEE en valeur. Les confondre reintroduirait exactement le trou que `run_id` a creuse
    — 27 % du flux, presents mais vides, donc silencieusement perdus.
    """
    with pytest.raises(RunIdentityViolation, match="nature"):
        validate_run_identity({**VALIDE, "nature": floue})


# --- lecture NON bloquante ----------------------------------------------------------------


def test_check_ne_LEVE_jamais_et_rend_les_causes():
    """`audit.append_spawn_event` est BEST-EFFORT ABSOLU par contrat : « ne leve JAMAIS ».
    Un futur cablage sur ce chemin a donc besoin d'une lecture qui RAPPORTE au lieu de casser
    — sinon le contrat d'identite casserait le contrat d'audit."""
    rapport = check_run_identity({"project_id": "", "scope": "usine"})
    assert rapport["conforme"] is False
    causes = " ".join(rapport["violations"])
    for attendu in ("project_id", "run_id", "scope", "mode"):
        assert attendu in causes
    assert check_run_identity(VALIDE)["conforme"] is True


def test_check_accepte_un_NON_MAPPING_sans_exploser():
    for objet in (None, "tetris", 42, []):
        assert check_run_identity(objet)["conforme"] is False


# --- le schema publie et le code disent la MEME chose --------------------------------------


def _schema():
    p = pathlib.Path(__file__).resolve().parents[1] / "run_identity.schema.json"
    return json.loads(p.read_text(encoding="utf-8"))


def test_le_schema_publie_existe_et_suit_la_convention_du_depot():
    s = _schema()
    assert s["$schema"] == "http://json-schema.org/draft-07/schema#"
    assert s["title"] == "RUN_IDENTITY_V1"


def test_le_schema_et_le_CODE_ne_peuvent_pas_DIVERGER():
    """Deux sources d'autorite qui derivent, c'est le mode de panne du studio. Ce test les
    attache l'une a l'autre : modifier l'une sans l'autre devient rouge."""
    s = _schema()
    assert set(s["required"]) == {"project_id", "run_id", "scope", "mode"}
    assert tuple(s["properties"]["scope"]["enum"]) == SCOPES
    assert tuple(s["properties"]["mode"]["enum"]) == MODES
    assert "enum" not in s["properties"]["nature"], \
        "NATURE reste ouverte dans le schema comme dans le code"


def test_le_schema_PORTE_la_regle_cardinale_en_toutes_lettres():
    """Un schema sans son pourquoi se fait « simplifier » par le prochain lecteur."""
    texte = json.dumps(_schema(), ensure_ascii=False)
    assert "UNKNOWN" in texte
    assert "inventee" in texte or "inventée" in texte
