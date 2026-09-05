"""Comportement du registry face à un catalogue abîmé (gate 2, 2026-09-05).

Fichier NEUF sous `forge/tests/**` : la CRÉATION est permise par le régime
`create_allowed_modify_denied` (forge/test_surfaces.yaml).

CE QUI MANQUAIT : les 13 tests existants du registre vérifient le catalogue RÉEL et son
intégrité. Aucun ne couvrait le fichier absent, illisible ou mal structuré — c'est-à-dire
tout ce qui arrive quand quelque chose casse.

CE QUE CES TESTS PROUVENT : la cause est NOMMÉE, et six formes d'anomalie rendent six
messages distincts au lieu d'un seul accusant le rôle.

CE QU'ILS NE PROUVENT PAS, dit plutôt que sous-entendu : que le catalogue corrompu soit
détecté PARTOUT. Trois appelants — `capability._provider_for`, `asset_producer.asset_dispatch`,
`repair_dispatch` — écrivent `or ""` DANS un `except Exception` : chez eux un catalogue
cassé reste indistinguable d'un rôle absent, et alimente une fiche de preuve avec un
`provider` vide. Rendre la lecture levante ne refermerait pas ce chemin ; c'est une gate
à part, non ouverte.
"""
from __future__ import annotations

import logging
from pathlib import Path

import pytest

from control_plane import registry
from forge import contract as fc
from forge.contract import RoleUnresolved

# (nom, contenu ; None = fichier jamais créé)
ABIMES = {
    "absent": None,
    "yaml_illisible": "models: [\n  - id: x\n",      # crochet jamais fermé
    "vide": "",
    "liste_au_lieu_de_dict": "- a\n- b\n",
    "models_non_liste": "models: 42\n",
}
SAIN = "models:\n  - id: anthropic/opus\n    roles: [orchestrator]\n    provider: claude-local\n"


def _catalogue(tmp_path: Path, contenu: str | None, nom: str = "roles.yaml") -> Path:
    p = tmp_path / nom
    if contenu is not None:
        p.write_text(contenu, encoding="utf-8")
    return p


# --- lecture tolérante, jamais levante ------------------------------------------------

@pytest.mark.parametrize("nom", ["absent", "yaml_illisible", "vide", "liste_au_lieu_de_dict"])
def test_load_yaml_rend_un_dict_vide_et_ne_leve_jamais(tmp_path, nom):
    """Contrat volontairement TOLÉRANT : le refus a lieu en aval, jamais ici.

    `models_non_liste` est EXCLU de ce cas, et la distinction compte : `models: 42` EST un
    dictionnaire valide — `_load_yaml` a raison de le rendre tel quel. C'est `_models` qui
    garde le type de la clé, une couche plus bas. Confondre les deux ferait porter à la
    lecture une responsabilité qui n'est pas la sienne."""
    assert registry._load_yaml(_catalogue(tmp_path, ABIMES[nom])) == {}


def test_load_yaml_rend_le_dict_tel_quel_quand_models_est_mal_type(tmp_path):
    """Le typage de `models` n'est PAS l'affaire de la lecture : elle rend le document,
    `_models` filtre. Ce test fige cette frontière."""
    p = _catalogue(tmp_path, ABIMES["models_non_liste"])
    assert registry._load_yaml(p) == {"models": 42}
    assert registry._models(p) == []


@pytest.mark.parametrize("nom", sorted(ABIMES))
def test_les_trois_lecteurs_ne_crashent_plus(tmp_path, nom):
    """AVANT : une LISTE donnait `AttributeError`, `models: 42` un `TypeError` — l'erreur
    de parsing était avalée pendant que l'erreur de structure passait brute."""
    p = _catalogue(tmp_path, ABIMES[nom])
    assert registry.get_model_for_role("orchestrator", p) is None
    assert registry.get_provider_for_role("orchestrator", p) is None
    assert registry.get_reasoning_for_model("opus", p) is None


# --- la cause est nommée --------------------------------------------------------------

@pytest.mark.parametrize("nom, attendu", [
    ("absent", registry.CATALOGUE_ABSENT),
    ("yaml_illisible", registry.CATALOGUE_ILLISIBLE),
    ("vide", registry.CATALOGUE_VIDE),
    ("liste_au_lieu_de_dict", registry.CATALOGUE_STRUCTURE),
    ("models_non_liste", registry.CATALOGUE_MODELS),
])
def test_probleme_catalogue_nomme_chaque_cause(tmp_path, nom, attendu):
    cause = registry.probleme_catalogue(_catalogue(tmp_path, ABIMES[nom]))
    assert cause is not None and attendu in cause


def test_un_catalogue_sain_n_a_aucun_probleme(tmp_path):
    assert registry.probleme_catalogue(_catalogue(tmp_path, SAIN)) is None


def test_un_fichier_sain_dont_le_role_manque_n_est_pas_un_probleme_de_catalogue(tmp_path):
    """Distinction qui compte : ici le fichier va bien, c'est le RÔLE qui manque. Le
    message d'origine est alors juste, et ne doit pas être pollué par une fausse cause."""
    p = _catalogue(tmp_path, "autre_cle: 1\n")
    assert registry.probleme_catalogue(p) is None
    with pytest.raises(RoleUnresolved) as err:
        fc.resolve_runtime({"capability_role": "orchestrator"}, caps_path=p)
    assert "catalogue inexploitable" not in str(err.value)


# --- propagation jusqu'au refus -------------------------------------------------------

@pytest.mark.parametrize("nom", sorted(ABIMES))
def test_resolve_runtime_refuse_EN_NOMMANT_la_cause(tmp_path, nom):
    """AVANT : trois causes distinctes rendaient le MÊME message, qui accusait le rôle —
    on relisait la liste des rôles, saine, au lieu de soupçonner le fichier."""
    with pytest.raises(RoleUnresolved) as err:
        fc.resolve_runtime({"capability_role": "orchestrator"},
                           caps_path=_catalogue(tmp_path, ABIMES[nom]))
    assert "catalogue inexploitable" in str(err.value)


def test_six_anomalies_rendent_six_messages_distincts(tmp_path):
    """La propriété qui compte : un message par cause, sinon le diagnostic ne sert à rien."""
    messages = set()
    for nom, contenu in list(ABIMES.items()) + [("role_absent", "autre_cle: 1\n")]:
        p = _catalogue(tmp_path, contenu, nom=f"{nom}.yaml")
        try:
            fc.resolve_runtime({"capability_role": "orchestrator"}, caps_path=p)
        except RoleUnresolved as exc:
            messages.add(str(exc).replace(str(tmp_path), "<tmp>"))
    assert len(messages) == 6, f"messages non distincts : {messages}"


def test_un_catalogue_sain_resout_toujours(tmp_path):
    """Non-régression : la tolérance ne doit rien casser sur le chemin nominal."""
    p = _catalogue(tmp_path, SAIN)
    assert fc.resolve_runtime({"capability_role": "orchestrator"}, caps_path=p) == "opus"
    assert registry.get_provider_for_role("orchestrator", p) == "claude-local"


def test_l_anomalie_est_tracee_et_pas_seulement_avalee(tmp_path, caplog):
    """Une lecture tolérante qui ne dit rien serait un vert silencieux."""
    with caplog.at_level(logging.WARNING, logger="control_plane.registry"):
        registry.get_model_for_role("orchestrator", _catalogue(tmp_path, "models: 42\n"))
    assert "models" in caplog.text
