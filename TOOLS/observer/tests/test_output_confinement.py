# -*- coding: utf-8 -*-
"""T10 — le chemin d'ECRITURE de l'Observer est confine (GO Pierre 2026-08-19).

DEFAUT MESURE. `cli.py` promet dans sa docstring :

    « Observer lit les traces existantes, reconstruit le run et ecrit SON PROPRE
      rapport sous `EVIDENCE/reports/observer/<projet>/`. Il n'ecrit jamais ailleurs. »

Le code contredit cette promesse. `cli.py:247` fait :

    out_dir = args.out or (args.repo / "EVIDENCE" / "reports" / "observer" / args.project)
    out_dir.mkdir(parents=True, exist_ok=True)

`args.project` est concatene SANS normalisation ni contrainte. Mesure :

    --project ../../evade  ->  EVIDENCE/reports/observer/../../evade   (HORS du repertoire promis)

ASYMETRIE A L'ORIGINE DU DEFAUT. L'Observer possede DEJA une garde de confinement, mais
seulement pour ce qu'il LIT : `ObserverContext._check` (sources.py:222) resout le chemin et
exige `relative_to(root)`, sinon `BlindnessViolation`. Le cote ECRITURE n'a jamais eu son
equivalent. Ce lot lui donne la garde que la lecture possede depuis toujours.

ATTEIGNABLE DEPUIS LA FORGE : `driver.py:611` lance `cli.py --project <projet>` avec le projet
du run. Ce n'est pas un defaut theorique d'usage manuel.

PERIMETRE STRICT — ce que ce lot ne fait PAS :
  · il ne confine PAS `--out`. Une destination donnee EXPLICITEMENT est une declaration de
    l'operateur, pas une surprise ; `selftest.py:14` s'en sert delibrement hors depot.
  · il ne FERME PAS F1. Les noms non-projets sont des noms de repertoire ordinaires : ils
    passent ce controle et DOIVENT continuer a le passer. Les distinguer d'une sonde legitime
    (`story_probe`, `gmws_probe`) demande la semantique de `--project`, qui est BLOCKED (T4).
    Deux tests ci-dessous verrouillent cette frontiere pour qu'aucune lecture future ne croie
    T10 plus large qu'il n'est.

CORRIGE LE 2026-08-19 — ce fichier affirmait « six repertoires fantomes (`jeu`, `nr`, `p`,
`proj`, `rouge`, `vert`) », et donnait `probe2` pour une sonde legitime. MESURE :

    discriminant       adapters.forge_run.events == 0     (aucune liste blanche)
    isole              7 entrees sur 28 ; les 21 autres ont toutes >= 3

    jeu nr p rouge vert   forge_run=0, pas de run_dir  -> parasites, CINQ
    probe2                forge_run=0, pas de run_dir  -> parasite, jamais repere
    repair_runtime_v1     forge_run=0, run_dir PRESENT -> cas limite (pas de state.json)
    proj                  1328 evenements REELS        -> espace de noms de FIXTURES

`run_id = "proj-1"` est le 2e identifiant le plus frequent de tout le flux de preuve (1320
enregistrements dans `lab/forge_evidence/*.jsonl`). `_belongs_to_project` l'a correctement
rattache par prefixe : l'Observer a fait son travail, c'est le FLUX qui melange fixtures et
runs reels. L'erreur d'origine jugeait sur la FORME DU NOM — exactement le raisonnement que
ce fichier pretend interdire.

La liste parametree ci-dessous est INCHANGEE : `proj` passe le controle de confinement et doit
continuer a le passer, au meme titre que les cinq parasites. Seule sa JUSTIFICATION etait
fausse. Y ajouter `probe2` serait un changement de comportement, distinct de cette correction.
"""
from __future__ import annotations

import pytest

from observer.sources import OutputScopeViolation, resolve_output_dir


def _racine(tmp_path):
    """Un faux depot. `resolve_output_dir` ne doit RIEN creer : il calcule et juge."""
    return tmp_path / "repo"


# --- la promesse de la docstring, tenue ---------------------------------------------------


def test_le_chemin_nominal_est_SOUS_le_repertoire_promis(tmp_path):
    repo = _racine(tmp_path)
    out = resolve_output_dir(repo, "tetris")
    assert out == (repo / "EVIDENCE" / "reports" / "observer" / "tetris").resolve()


def test_AUCUN_repertoire_n_est_CREE_par_la_resolution(tmp_path):
    """Resoudre n'est pas ecrire. Un nom refuse ne doit laisser AUCUNE trace, et un nom
    accepte ne doit pas devancer la decision de l'appelant."""
    repo = _racine(tmp_path)
    resolve_output_dir(repo, "tetris")
    assert not (repo / "EVIDENCE").exists()


# --- les echappements, refuses ------------------------------------------------------------


@pytest.mark.parametrize("nom", [
    "../../evade",
    "..\\..\\evade",
    "..",
    "tetris/../../../evade",
    "./../evade",
])
def test_un_nom_qui_SORT_du_repertoire_est_REFUSE(tmp_path, nom):
    with pytest.raises(OutputScopeViolation):
        resolve_output_dir(_racine(tmp_path), nom)


def test_un_chemin_ABSOLU_est_REFUSE(tmp_path):
    """Sans cela, `--project C:/ailleurs` ecraserait la base entiere du chemin : en
    concatenation Path, un absolu a droite ANNULE tout ce qui precede."""
    with pytest.raises(OutputScopeViolation):
        resolve_output_dir(_racine(tmp_path), str(tmp_path / "ailleurs"))


@pytest.mark.parametrize("nom", ["", "."])
def test_un_nom_qui_DESIGNE_LA_RACINE_est_REFUSE(tmp_path, nom):
    """Ils resolvent vers le repertoire d'observation LUI-MEME. L'Observer ecrirait alors
    son rapport a la racine commune de tous les projets, en collision avec chacun."""
    with pytest.raises(OutputScopeViolation):
        resolve_output_dir(_racine(tmp_path), nom)


def test_un_nom_fait_UNIQUEMENT_DE_BLANCS_est_REFUSE(tmp_path):
    """Cas SEPARE, et pour une raison mesuree — pas par symetrie de facade.

    On attendait que `"   "` se replie sur la racine comme `""` et `"."`. Sous Windows,
    NON : `resolve()` le conserve, le chemin reste parfaitement CONFINE, et l'Observer
    creerait un repertoire nomme par trois espaces — invisible a la lecture, impraticable
    en ligne de commande. Ce n'est donc pas un defaut de confinement mais un nom degenere.
    Le regrouper avec les deux precedents aurait fait passer une justification fausse.
    """
    with pytest.raises(OutputScopeViolation, match="blancs"):
        resolve_output_dir(_racine(tmp_path), "   ")


def test_le_message_de_refus_NOMME_le_chemin_et_la_racine(tmp_path):
    """Un refus muet obligerait a relire le code pour savoir ce qui a ete refuse et
    contre quoi. La regle studio « aucune decision dans un commentaire » vaut aussi pour
    les diagnostics."""
    with pytest.raises(OutputScopeViolation) as exc:
        resolve_output_dir(_racine(tmp_path), "../../evade")
    msg = str(exc.value)
    assert "evade" in msg
    assert "observer" in msg


# --- la frontiere avec T4/F1, verrouillee -------------------------------------------------


@pytest.mark.parametrize("non_projet", ["jeu", "nr", "p", "proj", "rouge", "vert"])
def test_les_NOMS_NON_PROJETS_passent_encore_ce_controle(tmp_path, non_projet):
    """T10 ne ferme PAS F1, et ce test existe pour l'empecher de le PRETENDRE.

    Ces six noms ne designent aucun projet, mais ils ne sont PAS de meme nature — cinq sont
    des fragments d'arguments CLI, `proj` est un espace de noms de fixtures portant 1328
    evenements REELS (voir la docstring du module). C'est precisement ce qui fait la valeur
    du test : le confinement ne peut pas, et ne doit pas, les distinguer. Tous sont des noms
    de repertoire parfaitement confines.

    Les refuser ici demanderait une liste blanche — mesure : les deux sources candidates
    rejettent 21 des 28 projets reels, dont l'auto-test de l'Observer. C'est BLOCKED (T4), et
    ce lot ne doit pas le contourner par un durcissement opportuniste.
    """
    resolve_output_dir(_racine(tmp_path), non_projet)  # ne leve pas


@pytest.mark.parametrize("legitime", ["_selftest", "driver_smoke_v6_20260808", "pacman-v6",
                                      "p1_worldscan_injection", "bomberman_3d"])
def test_AUCUNE_liste_blanche_n_est_introduite(tmp_path, legitime):
    """Les 28 projets reellement observes couvrent quatre natures differentes : jeu,
    campagne, sonde, auto-test. Un controle de confinement ne doit connaitre AUCUNE
    d'entre elles."""
    resolve_output_dir(_racine(tmp_path), legitime)  # ne leve pas


# --- la garde est REELLEMENT APPELEE par la CLI -------------------------------------------
#
# Sans cette section, `resolve_output_dir` serait un producteur sans consommateur : teste,
# vert, et sans effet sur le defaut. La preuve doit traverser la frontiere qu'elle valide —
# ici `sources.py` -> `cli.py` -> processus.


def test_la_CLI_REFUSE_un_nom_qui_echappe_et_rend_un_code_NON_NUL(tmp_path, capsys):
    from observer import cli
    code = cli.main(["--project", "../../evade", "--repo", str(_racine(tmp_path))])
    assert code == 2, "un refus muet avec code 0 laisserait l'appelant croire au succes"


def test_la_CLI_REFUSE_AVANT_de_reconstruire(tmp_path):
    """Le controle vivait implicitement au `mkdir`, en FIN de main : un nom invalide faisait
    l'integralite de la reconstruction avant d'ecrire au mauvais endroit. Ici le depot passe
    est VIDE — si la CLI atteignait la reconstruction, elle echouerait autrement qu'en 2."""
    from observer import cli
    repo = _racine(tmp_path)
    repo.mkdir(parents=True)
    assert cli.main(["--project", "..", "--repo", str(repo)]) == 2
    assert not (repo / "EVIDENCE").exists(), "aucune ecriture ne doit avoir eu lieu"


def test_driver_py_est_l_appelant_reel_de_cette_surface():
    """`driver.py:611` lance `cli.py --project <projet>` avec le projet du run : le defaut
    etait atteignable depuis la chaine Forge, pas seulement en usage manuel. Ce test fige
    la raison pour laquelle ce lot n'est pas cosmetique."""
    from pathlib import Path as _P
    src = _P(__file__).resolve().parents[3] / "forge" / "driver.py"  # V2 : TOOLS/observer/tests -> Studio/forge/driver.py
    texte = src.read_text(encoding="utf-8")
    assert 'TOOLS/observer/cli.py", "--project"' in texte


# --- symetrie avec la garde de lecture ----------------------------------------------------


def test_la_garde_d_ECRITURE_vit_AVEC_la_garde_de_LECTURE(tmp_path):
    """Les deux confinements sont le meme invariant applique aux deux sens. Les separer
    de module ferait diverger leur maintenance : `sources.py` est l'endroit ou l'Observer
    declare ses racines."""
    from observer import sources
    assert issubclass(sources.OutputScopeViolation, RuntimeError)
    assert hasattr(sources, "BlindnessViolation")
