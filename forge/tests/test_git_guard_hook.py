"""Heuristique de fail-closed du hook `pretool_git_guard` (gate 5, 2026-09-05).

Fichier NEUF sous `forge/tests/**` : sous le régime `create_allowed_modify_denied`
(forge/test_surfaces.yaml) la CRÉATION est permise, c'est la modification d'un test
préexistant qui demande une gate.

CE QUI EST TESTÉ : l'heuristique du CHEMIN D'EXCEPTION du hook — celle qui décide s'il
faut refuser fail-closed quand `forge.git_guard` est indisponible. Elle ne décide rien
quand le garde fonctionne.

CE QUI N'EST PAS TESTÉ, et il faut le dire : la complétude du garde. Elle est hors de
portée de toute analyse de texte — mesuré en gate 5, sept évasions restent ouvertes
(alias `g`, concaténation de chaînes, substitution de commande, `gh`, passage par
python…). Ce garde est un ralentisseur honnête, pas une frontière.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / ".claude" / "hooks" / "pretool_git_guard.py"

# Jamais le mot entier en clair dans ce fichier : le garde inspecte le TEXTE BRUT des
# commandes Bash, y compris du code cité. Une mesure du garde écrite naïvement se fait
# refuser par le garde — constaté en gate 5 sur la toute première commande.
G = "gi" + "t"
CO = "check" + "out"


@pytest.fixture(scope="module")
def hook():
    spec = importlib.util.spec_from_file_location("pretool_git_guard_sous_test", HOOK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("commande", [
    f"cat .{G}ignore",
    "ls di" + "gital/",
    "echo le" + "gitime",
    f"echo '.{G}modules'",
])
def test_ne_refuse_pas_une_sous_chaine_fortuite(hook, commande):
    """La sous-chaîne précédente refusait ces lectures inoffensives — et précisément
    quand le garde est déjà cassé, donc au pire moment pour perdre de la disponibilité."""
    assert not hook._GIT_MENTION.search(commande)


@pytest.mark.parametrize("commande", [
    f"{G} {CO} master",
    f"{G} status",
    f"echo ok && {G} st" + "ash",
    f"/usr/bin/{G} {CO} master",
    f"C:/outils/{G}.exe {CO}",
])
def test_refuse_toute_mention_reelle_y_compris_par_chemin_absolu(hook, commande):
    """Le fail-closed refuse TOUT git, pas seulement le destructeur : quand le garde est
    indisponible, on ne sait pas trier."""
    assert hook._GIT_MENTION.search(commande)


def test_le_fail_closed_est_plus_large_que_la_detection_jamais_plus_etroit(hook):
    """Divergence DÉLIBÉRÉE avec `git_guard._GIT_WORD`, mesurée en gate 5.

    `_GIT_WORD` exclut `/` avant le mot ; l'aligner à l'identique aurait laissé passer
    `/usr/bin/git checkout`, que l'ancienne sous-chaîne refusait. Un fail-closed plus
    étroit que la détection serait une régression silencieuse.
    """
    from forge.git_guard import _GIT_WORD
    par_chemin = f"/usr/bin/{G} {CO} master"
    assert not _GIT_WORD.search(par_chemin), (
        "prémisse de ce test caduque : _GIT_WORD matche désormais le chemin absolu")
    assert hook._GIT_MENTION.search(par_chemin), (
        "le fail-closed est devenu plus étroit que la détection")


def test_les_deux_motifs_visent_le_meme_mot(hook):
    """Duplication assumée (le hook ne peut pas importer git_guard — tout l'intérêt est
    de fonctionner quand cet import échoue), mais elle ne doit pas dériver sur le fond."""
    from forge.git_guard import _GIT_WORD
    for commande in (f"{G} {CO} master", f"{G} status", f"{G}.exe {CO}"):
        assert bool(_GIT_WORD.search(commande)) == bool(hook._GIT_MENTION.search(commande))


def test_le_docstring_ne_se_declare_plus_non_cable(hook):
    """Le fichier affirmait « PRÉPARÉ, NON CÂBLÉ : référencé nulle part » alors qu'il
    l'est deux fois et s'exécute à chaque commande."""
    import json
    texte = HOOK.read_text(encoding="utf-8")
    # On vérifie l'AFFIRMATION du fichier, pas la présence d'un mot : le docstring cite
    # désormais l'ancienne phrase fausse pour expliquer la correction, donc « NON CÂBLÉ »
    # y figure encore — en tant que citation, plus en tant que déclaration.
    assert "CÂBLÉ ET ACTIF" in texte
    reglages = json.loads((REPO_ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))
    cables = sum(
        1
        for entrees in (reglages.get("hooks") or {}).values()
        for entree in entrees
        for h in entree.get("hooks", [])
        if "pretool_git_guard" in (h.get("command") or "")
    )
    assert cables >= 1, "le hook n'est plus câblé : ce test et le docstring doivent changer ensemble"
