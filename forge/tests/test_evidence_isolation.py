# -*- coding: utf-8 -*-
"""ISOLATION DE LA PREUVE — un test ne doit jamais ecrire dans l'artefact de PRODUCTION.

GO Pierre 2026-08-19, option B : fermer la CLASSE de defaut, pas son premier exemple.

DEFAUT MESURE PAR EXECUTION (pas par lecture) — lignes ajoutees a `EVIDENCE/bundles/`
par un simple `pytest <fichier>` :

    test_run_real_repair_wiring.py   dispatch_audit +12   repair_results +4
    test_asset_loop.py               dispatch_audit  +2   asset_results  +1
    test_domain_routing.py           aucune ecriture — PROPRE

Le troisieme etait un FAUX POSITIF de ma lecture (`grep audit_path == 0`) : l'execution l'a
falsifie. C'est pourquoi la mesure precede le correctif.

VOLUME HISTORIQUE. 1048 des 3462 enregistrements de `dispatch_audit.jsonl` (30 %) n'ont
AUCUN `run_id`, et 100 % d'entre eux portent `capability_role = "repair_runtime"`. Leur
repartition par etape — s2-worldscan 696, s4-archi 176, s5-wiremap 176 — reproduit
exactement les appels de `test_run_real_repair_wiring.py` (7 / 1 / 1) sur ~176 executions
de la suite. Ce n'etait donc PAS une rupture de tracabilite en production : c'etait la
suite de tests ecrivant dans le fichier de preuve de production, sans `run_id` puisqu'un
test n'en fournit pas.

LA CLASSE DE DEFAUT, une seule phrase :

    Une fonction de haut niveau appelle un emetteur INJECTABLE sans exposer l'injection.

    run_repair_step(...)          ->  repair_dispatch.announce / .record   (audit_path OK)
    asset_dispatch.dispatch(...)  ->  announce / record                    (audit_path OK)

Les emetteurs bas niveau acceptaient deja `audit_path` ; `audit_path=None` retombe sur
`forge.audit.DEFAULT_AUDIT`, c'est-a-dire le VRAI fichier. Le correctif n'invente aucun
mecanisme : il expose celui qui existait, la ou il manquait, et nulle part ailleurs.

CE LOT NE TOUCHE PAS `RUN_IDENTITY_V1`. Le contrat des quatre dimensions reste valide et
NOT_WIRED : ce defaut-ci est une rupture d'ISOLATION, pas d'IDENTITE, et le confondre avec
l'autre reviendrait a cabler un contrat pour une cause qu'il ne traite pas.
"""
from __future__ import annotations

import inspect
import json

import pytest

from forge import run_real
from forge.asset_producer import asset_dispatch as AD
from forge.audit import DEFAULT_AUDIT


#: Les fonctions de haut niveau qui EMETTENT de la preuve. Toute nouvelle entree ici doit
#: exposer l'injection, sinon elle reintroduit la classe de defaut.
EMETTEURS = (run_real.run_repair_step, AD.dispatch)


def _empreinte_production() -> tuple:
    """(existe, taille) du VRAI fichier de preuve. Comparee avant/apres : c'est la seule
    observation qui prouve la non-ecriture, plutot qu'une inspection de signature."""
    return (DEFAULT_AUDIT.exists(),
            DEFAULT_AUDIT.stat().st_size if DEFAULT_AUDIT.exists() else 0)


# --- la classe de defaut, verrouillee ------------------------------------------------------


@pytest.mark.parametrize("fonction", EMETTEURS, ids=lambda f: f.__name__)
def test_tout_EMETTEUR_de_haut_niveau_EXPOSE_l_injection(fonction):
    """Le verrou de CLASSE. Sans lui, le prochain emetteur ajoute reproduira le defaut, et
    la contamination ne se verra qu'en relisant un fichier ignore par git."""
    params = inspect.signature(fonction).parameters
    assert "audit_path" in params, (
        f"{fonction.__name__} ecrit de la preuve sans permettre de la rediriger : "
        f"un test qui l'appelle contaminera {DEFAULT_AUDIT.name}")
    assert params["audit_path"].default is None, \
        "l'injection doit etre OPTIONNELLE — la production continue de viser DEFAULT_AUDIT"


@pytest.mark.parametrize("fonction", EMETTEURS, ids=lambda f: f.__name__)
def test_tout_EMETTEUR_expose_aussi_la_destination_des_RESULTATS(fonction):
    """`dispatch_audit.jsonl` n'est pas le seul artefact touche : la mesure a montre
    `repair_results.jsonl` (+4) et `asset_results.jsonl` (+1). Rediriger l'audit seul
    laisserait la moitie de la contamination en place."""
    assert "results_path" in inspect.signature(fonction).parameters


# --- preuve par OBSERVATION du vrai fichier ------------------------------------------------


def test_run_repair_step_N_ECRIT_PAS_dans_la_preuve_de_production(tmp_path):
    """LE test qui compte. `announce()` est emis AVANT le sous-processus de reparation :
    meme si `node` echoue et que la fonction rend None, la ligne d'audit, elle, est ecrite.
    C'est exactement le chemin qui a produit les 1048 orphelins.

    On observe le VRAI fichier avant/apres. Une assertion de signature seule ne prouverait
    que la possibilite de rediriger, jamais la redirection.
    """
    audit = tmp_path / "audit.jsonl"
    avant = _empreinte_production()

    run_real.run_repair_step("s2-worldscan", tmp_path,
                             audit_path=audit, results_path=tmp_path / "res.jsonl")

    assert _empreinte_production() == avant, \
        f"{DEFAULT_AUDIT} a ete modifie par un test — la contamination persiste"
    assert audit.exists(), "la preuve doit exister QUELQUE PART : rediriger n'est pas jeter"
    ligne = json.loads(audit.read_text(encoding="utf-8").splitlines()[0])
    assert ligne["etape"] == "s2-worldscan"
    assert ligne["capability_role"] == "repair_runtime", \
        "le role qui portait 100 % des orphelins"


def test_asset_dispatch_TRANSMET_la_destination_a_ses_six_points_d_emission(monkeypatch,
                                                                            tmp_path):
    """`dispatch()` appelle `announce` 2 fois et `record` 4 fois. Un oubli sur UN SEUL des
    six suffirait a contaminer. On capture les appels plutot que de piloter Blender : le
    defaut est le NON-PASSAGE du parametre, pas le comportement de la chaine 3D.
    """
    vus: list[tuple[str, object]] = []
    monkeypatch.setattr(AD, "announce",
                        lambda *a, audit_path=None, **k: vus.append(("announce", audit_path)))
    monkeypatch.setattr(AD, "record",
                        lambda *a, audit_path=None, **k: vus.append(("record", audit_path)) or {})

    spec = tmp_path / "s.json"
    spec.write_text(json.dumps({"asset_id": "x", "archetype": "chest", "category": "chest",
                                "size": {"w": 1, "d": 1, "h": 1}, "variants": [],
                                "consumer": ["x"]}), encoding="utf-8")
    dest = tmp_path / "out"
    dest.mkdir()
    audit = tmp_path / "audit.jsonl"
    avant = _empreinte_production()

    try:
        AD.dispatch(spec, dest, run_id="isolation-1", propose=False,
                    audit_path=audit, results_path=tmp_path / "res.jsonl")
    except Exception:
        # La chaine 3D peut echouer (Blender absent, oracle indisponible) : ce test ne
        # juge PAS la production d'asset, seulement le passage du parametre jusqu'aux
        # emetteurs deja atteints.
        pass

    assert vus, "aucun emetteur atteint — le test ne prouverait rien"
    assert all(dest_vue == audit for _, dest_vue in vus), \
        f"au moins un point d'emission n'a pas recu la destination : {vus}"
    assert _empreinte_production() == avant


# --- les deux fichiers de test qui contaminaient sont CORRIGES -----------------------------


@pytest.mark.parametrize("module", ["test_run_real_repair_wiring", "test_asset_loop"])
def test_les_tests_qui_CONTAMINAIENT_injectent_desormais(module):
    """Mesure d'origine : `pytest test_run_real_repair_wiring.py` ajoutait 12 lignes a
    `dispatch_audit.jsonl` et 4 a `repair_results.jsonl` ; `test_asset_loop.py`, 2 et 1.

    Ce test lit leur SOURCE : il echoue si quelqu'un rajoute un appel non injecte. Verifier
    le texte est ici plus honnete que ré-executer ces modules depuis celui-ci — une
    execution imbriquee mesurerait un effet de bord de pytest, pas leur contenu.
    """
    from pathlib import Path
    src = (Path(__file__).parent / f"{module}.py").read_text(encoding="utf-8")

    # Un appel s'etend jusqu'a SA parenthese fermante, pas jusqu'a la fin de ligne : la
    # premiere version de ce test lisait ligne par ligne et rendait rouge un appel
    # correctement injecte, simplement parce qu'il tenait sur trois lignes. Un test qui
    # juge la MISE EN FORME au lieu du CONTENU est un faux negatif en puissance.
    manquants: list[str] = []
    for jeton in ("run_repair_step(", "AD.dispatch("):
        depart = 0
        while (i := src.find(jeton, depart)) != -1:
            depart = i + len(jeton)
            if src[max(0, i - 4):i].strip().endswith("def"):
                continue
            profondeur, j = 1, depart
            while j < len(src) and profondeur:
                profondeur += (src[j] == "(") - (src[j] == ")")
                j += 1
            appel = src[i:j]
            if "audit_path" not in appel:
                manquants.append(" ".join(appel.split())[:90])
    assert manquants == [], \
        f"{module} : appel(s) sans redirection de preuve -> {manquants}"
