# -*- coding: utf-8 -*-
"""Le producteur Observer ECRIT bien ce que l'anonymiseur rend (GO Pierre 2026-08-20).

POURQUOI CE TEST EXISTE. `forge.anonymize_session_paths` a vecu des semaines avec ZERO
appelant : outil ecrit, teste, ratifie — et sans effet. « Une capacite declaree mais non
branchee n'est pas une capacite du systeme. » Ce fichier est la preuve que le branchement
existe, et il doit ROUGIR si quelqu'un le retire.

CE QU'IL NE FAIT PAS, et c'est deliberé. La premiere redaction envisagee lancait le
producteur puis assertait « 0 occurrence du compte dans la sortie ». MESURE : sur un
repertoire de transcripts vide, la sortie ne contient AUCUN chemin personnel — l'assertion
serait donc VERTE meme sans branchement. Un test vide qui se presente comme une preuve est
pire que pas de test.

CE QU'IL FAIT A LA PLACE : il remplace les deux fonctions par des ESPIONS qui rendent une
valeur SENTINELLE, lance le vrai `main()`, et exige de retrouver la sentinelle DANS LES
FICHIERS. Cela prouve deux choses distinctes que « la fonction a ete appelee » ne prouve
pas seule : le producteur l'appelle, ET il ecrit son RESULTAT plutot que l'original.
Independant des donnees du poste : aucun transcript reel n'est requis.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[2]
if str(RACINE) not in sys.path:
    sys.path.insert(0, str(RACINE))

from observer import cli  # noqa: E402

SENTINELLE_JSON = {"__SENTINELLE_DEEP__": True}
SENTINELLE_TEXTE = "__SENTINELLE_TEXT__"


@pytest.fixture()
def run_observer(tmp_path, monkeypatch):
    """Lance le VRAI producteur, avec les deux fonctions remplacees par des espions."""
    appels: list[str] = []

    def espion_deep(obj):
        appels.append("deep")
        return SENTINELLE_JSON

    def espion_text(txt):
        appels.append("text")
        return SENTINELLE_TEXTE

    monkeypatch.setattr(cli, "anonymize_deep", espion_deep)
    monkeypatch.setattr(cli, "anonymize_text", espion_text)

    transcripts = tmp_path / "transcripts"
    transcripts.mkdir()
    sortie = tmp_path / "out"
    code = cli.main(["--project", "sonde-cablage",
                     "--transcripts", str(transcripts),
                     "--out", str(sortie)])
    return code, sortie, appels


def test_le_producteur_APPELLE_les_deux_anonymiseurs(run_observer):
    code, _, appels = run_observer
    assert code == 0, "le producteur n'a pas abouti — le test ne prouve rien"
    assert "deep" in appels, "observer_run.json / events.jsonl n'passent PAS par anonymize_deep"
    assert "text" in appels, "RECONSTRUCTION.md ne passe PAS par anonymize_text"


def test_le_producteur_ECRIT_le_RESULTAT_de_l_anonymiseur(run_observer):
    """« Appelee » ne suffit pas : un appel dont le retour est jete laisserait la fuite."""
    _, sortie, _ = run_observer
    ecrit = json.loads((sortie / "observer_run.json").read_text(encoding="utf-8"))
    assert ecrit == SENTINELLE_JSON, "observer_run.json ne porte PAS ce que l'anonymiseur a rendu"
    assert (sortie / "RECONSTRUCTION.md").read_text(encoding="utf-8") == SENTINELLE_TEXTE


def test_le_module_de_production_expose_bien_les_deux_noms():
    """Si un refactor renomme ou retire l'import, les espions ci-dessus porteraient sur des
    attributs inexistants et `monkeypatch.setattr` echouerait — ce test rend la cause
    lisible au lieu d'un AttributeError dans une fixture."""
    for nom in ("anonymize_deep", "anonymize_text"):
        assert hasattr(cli, nom), f"observer.cli n'importe plus {nom}"
