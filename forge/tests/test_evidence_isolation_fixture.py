# -*- coding: utf-8 -*-
"""La garde generique : AUCUN test de cette suite n'ecrit dans un artefact de preuve REEL.

GO Pierre 2026-08-19. Ferme le RESIDU mesure apres `2d418b3` : la suite complete ecrivait
encore +4524 octets dans `dispatch_audit.jsonl` et +8590 dans `repair_results.jsonl`.

POURQUOI UNE FIXTURE ET PAS UN PARAMETRE DE PLUS. Le residu ne venait pas d'appels de test
negligents : 9 modules pilotent `run_real` DE BOUT EN BOUT et passent par le site d'appel
INTERNE, dans l'executeur, qui n'a aucune destination a transmettre. Exposer `audit_path`
plus haut ne pouvait pas les atteindre. Et il ne FAUT PAS que ce site en ait une : en
production, ces ecritures DOIVENT atteindre le vrai fichier.

C'est donc un CONFINEMENT, pas une guerison. Le defaut structurel — une fonction de haut
niveau qui appelle un emetteur injectable sans exposer l'injection — reste ce qu'il est ;
seule sa consequence sur les artefacts durables disparait.

MOTIF DEJA RATIFIE, ce n'est pas une convention neuve : `_isolate_learning_curve_writes`
(conftest, 2026-07-26) fait exactement cela pour `knowledge_base/learning_curve.jsonl`,
avec la meme justification.

LE PIEGE, PROUVE PAR EXECUTION avant d'ecrire une ligne :

    patch forge.audit.DEFAULT_AUDIT SEUL       -> VRAI FICHIER, surcharge DEFAITE
    patch forge.dispatch.DEFAULT_AUDIT SEUL    -> tmp OK (si dispatch est charge)
    patch LES DEUX, meme valeur                -> tmp OK
    patch audit seul, dispatch NON charge      -> tmp OK

Patcher la constante dans le module qui la POSSEDE est precisement ce qui echoue :
`audit._resolve_audit_path` privilegie la surcharge `forge.dispatch` SI ELLE DIFFERE, et le
re-export la fait differer. Une fixture ecrite de la maniere evidente serait installee,
verte, et sans aucun effet. D'ou le test qui verrouille les DEUX constantes ensemble.
"""
from __future__ import annotations

import json

import forge.audit as A
import forge.dispatch as D
import forge.repair_dispatch as RD
import forge.studio_link as SL
from forge import run_real
from forge.asset_producer import asset_dispatch as AD

#: Les chemins REELS, reconstruits depuis `REPO_ROOT` — que la fixture ne patche pas. Les
#: relire ici plutot que de memoriser les constantes evite de comparer une valeur patchee
#: a elle-meme, ce qui rendrait tous les tests de ce fichier tautologiques.
_EVIDENCE = A._REPO_ROOT / "EVIDENCE" / "bundles"
AUDIT_REEL = _EVIDENCE / "dispatch_audit.jsonl"
REPAIR_REEL = _EVIDENCE / "repair_results.jsonl"
ASSET_REEL = _EVIDENCE / "asset_results.jsonl"


def _empreinte(p) -> tuple:
    return (p.exists(), p.stat().st_size if p.exists() else 0)


# --- la redirection est ACTIVE -------------------------------------------------------------


def test_la_destination_d_audit_EFFECTIVE_n_est_pas_le_fichier_reel():
    """On interroge le RESOLVEUR, pas les constantes : c'est lui qui decide reellement."""
    effectif = A._resolve_audit_path(None)
    assert effectif != AUDIT_REEL, "la fixture d'isolation n'est pas en vigueur"


def test_les_DEUX_constantes_d_audit_sont_patchees_ENSEMBLE():
    """LE test qui vaut ce lot. `forge.dispatch` RE-EXPORTE `DEFAULT_AUDIT`, et le
    resolveur privilegie cette surcharge SI ELLE DIFFERE. N'en patcher qu'une laisse les
    ecritures partir dans le vrai fichier — mesure a l'appui (voir docstring du module).
    Les garder EGALES est ce qui rend la redirection effective dans les deux branches.
    """
    assert A.DEFAULT_AUDIT == D.DEFAULT_AUDIT, \
        "les deux constantes ont diverge : la branche `forge.dispatch` reprend la main"
    assert A.DEFAULT_AUDIT != AUDIT_REEL


def test_les_destinations_de_RESULTATS_sont_redirigees_aussi():
    """`dispatch_audit.jsonl` n'etait pas le seul artefact touche : la mesure d'origine
    donnait +8590 octets sur `repair_results.jsonl`. Rediriger l'audit seul aurait laisse
    les deux tiers de la contamination en place."""
    assert RD.RESULTS_PATH != REPAIR_REEL
    assert AD.RESULTS_PATH != ASSET_REEL


# --- la redirection FONCTIONNE sur un appel qui n'injecte RIEN -----------------------------


def test_un_emetteur_appele_SANS_injection_n_atteint_PAS_la_production(tmp_path):
    """Le cas exact du residu : aucun `audit_path`, comme le site d'appel interne de
    `run_real`. `announce()` etant emis AVANT le sous-processus, la ligne part meme quand
    la reparation echoue — c'est ce chemin qui a produit 1048 orphelins."""
    avant = (_empreinte(AUDIT_REEL), _empreinte(REPAIR_REEL))

    run_real.run_repair_step("s2-worldscan", tmp_path)   # <- volontairement SANS injection

    assert (_empreinte(AUDIT_REEL), _empreinte(REPAIR_REEL)) == avant, \
        "un appel non injecte a atteint un artefact de preuve REEL"
    redirige = A._resolve_audit_path(None)
    assert redirige.exists(), "rediriger n'est pas jeter : la preuve doit exister ailleurs"
    ligne = json.loads(redirige.read_text(encoding="utf-8").splitlines()[0])
    assert ligne["capability_role"] == "repair_runtime"


# --- perimetre : ce que la fixture ne touche PAS -------------------------------------------


def test_la_TELEMETRIE_n_est_PAS_redirigee():
    """Verrou de PERIMETRE, pas oubli. `forge_telemetry.jsonl` a un defaut du meme genre
    (`studio_link.DEFAULT_TELEMETRY`), mais son delta MESURE sur la suite complete est
    ZERO : aucun test ne l'ecrit. L'ajouter « par symetrie » elargirait le lot sur une
    hypothese au lieu d'une mesure. Ce test rougira si quelqu'un le fait sans remesurer.
    """
    assert SL.DEFAULT_TELEMETRY == _EVIDENCE / "forge_telemetry.jsonl"


def test_le_module_de_FALSIFICATION_est_EXPLICITEMENT_exempte():
    """Sans exemption, `test_evidence_isolation.py` deviendrait NON FALSIFIABLE : il prouve
    qu'un appel INJECTE n'atteint pas la production, et la fixture ferait passer ce test
    meme si la transmission d'`audit_path` etait retiree. La garde masquerait exactement la
    regression qu'il existe pour detecter. L'exemption est donc une condition de validite,
    pas une commodite.
    """
    from pathlib import Path

    import conftest  # le conftest de CETTE suite, importable via son propre sys.path
    assert "test_evidence_isolation" in conftest.MODULES_OBSERVANT_LA_PREUVE_REELLE
    for nom in conftest.MODULES_OBSERVANT_LA_PREUVE_REELLE:
        assert (Path(__file__).parent / f"{nom}.py").is_file(), \
            f"exemption pour un module inexistant : {nom} (renomme ? supprime ?)"
