"""Oracles déterministes du STANDARD Forge (`forge/standard/`).

Six oracles, un par facette du standard décrit dans `standard/SCHEMA.md` :

1. ``check_contract_completeness`` — schéma FERMÉ de `game_contract` / `system_contract`
   (miroir de `checkSpec` dans `knowledge_base/kb-validate.mjs` : champ manquant = violation,
   champ inconnu = violation).
2. ``check_budget`` — la loi d'empilement (`len(adds) <= 1`), les `reuses` au tier `validated`,
   toute brique déposée dans le budget.
3. ``check_line_states`` — les 6 états d'une ligne de wiremap v2 et leurs contraintes
   (NOT_APPLICABLE/DEFERRED/UNKNOWN/REQUIRED/EXPECTED), l'exigence de champ `system_parent`,
   + omission silencieuse d'une exigence CORE. Distingue deux moments (`frozen`) : au gel
   (UNKNOWN et IMPLEMENTED interdits) vs après build (REQUIRED interdit). Depuis l'étage 1
   `lifecycle` (ratifié Pierre 2026-08-02, SCHEMA.md §3) : vérifie aussi le bloc OPTIONNEL
   `lifecycle` d'une ligne quand il est présent (schéma fermé, evidence exigée sur
   implemented/tested) — une ligne sans `lifecycle` reste jugée exactement comme avant.
4. ``check_placement`` — l'adresse d'une ligne est cohérente avec sa catégorie via `repo_map.yaml`,
   dérivée de `category` + `system_parent` (jamais de l'id de la ligne) ; `system_parent` doit
   désigner une entrée de `wiremap["systems"]`. En `schema_version: 2`, chaque entrée de
   `fichiers[]` DOIT elle-même déclarer `{path, category}` (jamais déduit du nom de fichier) —
   c'est le trou fermé par cette révision : une wiremap peut avoir une `address` de ligne
   correcte tout en posant ses fichiers réels ailleurs.
5. ``check_index`` — index bidirectionnel carte↔disque (fichiers ET dossiers), dossiers de
   gouvernance exclus, mode avant/après build (`built`), et — si `repo_map` est fourni —
   tout dossier de premier niveau hors des `roots` figées (`dossiers_hors_structure`). Lit
   `fichiers[]` sous ses deux formes (chaîne nue OU `{path, category}`) sans jamais juger
   `category` — cette règle appartient uniquement à `check_placement`.
6. ``check_collisions`` — le registre de capacités : identifiants inconnus, collisions
   `single_owner`, trous, doubles propriétaires, ordre d'écriture implicite.

Deux volets supplémentaires (R1, `contracts/r1-preuves-boucle-mecaniques.yaml`,
2026-07-27), branchés ADVISORY dans le reçu de `s10s-oracle-standard`
(`driver.py::_run_standard_oracle` — jamais dans le calcul du statut du pas) :

7. ``check_observable_coverage`` — toute ligne `observable_by_player: true` doit
   nommer, via `observable_proof`, un volet d'oracle produit qui EXISTE dans le reçu
   fourni et n'est ni `NOT_MEASURED` ni en échec. Patron Art Bible
   (`check_artbible.mjs`) : `FAIL` = malformé · `BLOCKED` = bien formé mais non
   couvert · `OK` = conforme et couvert.
8. ``check_genre_coverage`` — chaque règle de la Genre Bible (`genre_rules[].id`)
   doit être citée par une ligne de wiremap (`genre_refs`, résolvant vers un `id`
   réel) ou refusée explicitement (`wiremap["genre_refusals"]`, raison non vide).
   Une citation qui ne résout pas -> `FAIL` ; une règle ni citée ni refusée ->
   `BLOCKED`.

Non-LLM, déterministes, reproductibles. Comme `static_oracles.py` : un oracle ne lève JAMAIS
sur une entrée malformée — il retourne un ``passed: False`` avec une raison explicite (cf.
`check_architecture`, commentaire F2b sur le crash-loop réel évité par cette discipline).

Ces oracles PROUVENT (PASS/FAIL) ; ils ne jugent jamais (aucun LLM). Les six premiers
oracles restent autonomes : rien de leur comportement n'a changé, aucun branchement
driver n'a été ajouté pour eux dans cette révision. Les deux nouveaux (7-8) SONT
branchés (ADVISORY) — cf. `driver.py::_run_standard_oracle`.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from .static_oracles import _is_test_file, _source_files  # réutilisés, pas dupliqués (SOURCE_EXTS y est déjà consommé)

# --------------------------------------------------------------------------------------
# Validateurs de type élémentaires (mêmes principes que ASSET_SPEC/BRICK_SPEC dans
# knowledge_base/kb-validate.mjs : chaque champ a un prédicat, un schéma fermé rejette
# tout champ absent d'un côté et tout champ inconnu de l'autre).
# --------------------------------------------------------------------------------------


def _is_str(v: Any) -> bool:
    return isinstance(v, str)


def _is_nonempty_str(v: Any) -> bool:
    return isinstance(v, str) and v.strip() != ""


def _is_int(v: Any) -> bool:
    # bool est une sous-classe d'int en Python — on l'exclut explicitement.
    return isinstance(v, int) and not isinstance(v, bool)


def _is_bool(v: Any) -> bool:
    return isinstance(v, bool)


def _is_str_list(v: Any) -> bool:
    return isinstance(v, list) and all(isinstance(x, str) for x in v)


def _is_dict(v: Any) -> bool:
    return isinstance(v, dict)


def _is_assets_plan(v: Any) -> bool:
    return v in ("cc0", "generated")


# spec[field] = (validateur, obligatoire)
_FieldSpec = dict[str, tuple[Callable[[Any], bool], bool]]

_GAME_CONTRACT_SPEC: _FieldSpec = {
    "schema_version": (_is_int, True),
    "game_id": (_is_nonempty_str, True),
    "node": (_is_int, True),
    "runtimes": (_is_str_list, True),
    "budget": (_is_dict, True),
    "assets": (_is_dict, True),
    # `proof` — descripteur de preuve de mutation multi-runtime, OPTIONNEL.
    # Gate Pierre 2026-07-28 (option (a)) : le contrat FIGÉ
    # docs/forge/CONTRAT_PREUVE_MUTATION_V1.md §1 place le descripteur DANS ce fichier
    # (« la vérité du jeu reste dans le jeu »), or le schéma fermé le rejetait comme
    # champ inconnu — contradiction découverte en écrivant le premier descripteur réel
    # (Snake), invisible tant qu'aucun jeu n'en portait.
    # OPTIONNEL par construction : un jeu sans descripteur reste valide et suit le
    # régime historique (contrat §6 — c'est le cas de Pong, témoin gelé, et de tout le
    # parc). Le schéma reste FERMÉ : seul ce champ est ajouté, aucune autre règle touchée.
    "proof": (_is_dict, False),
}
_BUDGET_SPEC: _FieldSpec = {
    "reuses": (_is_str_list, True),
    "adds": (_is_str_list, True),
}
_ASSETS_SPEC: _FieldSpec = {
    "plan": (_is_assets_plan, True),
}
_SYSTEM_CONTRACT_SPEC: _FieldSpec = {
    "schema_version": (_is_int, True),
    "id": (_is_nonempty_str, True),
    "category": (_is_nonempty_str, True),
    "provides": (_is_str_list, True),
    "requires": (_is_str_list, True),
    "owner": (_is_bool, True),
    "dependencies": (_is_str_list, True),
    "tests": (_is_str_list, True),
}

_SUPPORTED_KINDS = ("game", "system")


def _closed_schema_violations(obj: dict, spec: _FieldSpec, label: str) -> list[str]:
    """Schéma FERMÉ : champ obligatoire manquant OU mal typé -> violation ; champ
    absent du spec -> violation. Miroir Python de `checkSpec` (kb-validate.mjs)."""
    violations: list[str] = []
    for field, (validator, required) in spec.items():
        if field not in obj:
            if required:
                violations.append(f"{label}: champ obligatoire manquant '{field}'")
            continue
        if not validator(obj[field]):
            violations.append(f"{label}: champ mal typé '{field}' (reçu {obj[field]!r})")
    for key in obj.keys():
        if key not in spec:
            violations.append(f"{label}: champ inconnu (schéma fermé) '{key}'")
    return violations


def check_contract_completeness(contract: dict, kind: str) -> dict:
    """Schéma FERMÉ d'un `game_contract` ou `system_contract` (`standard/SCHEMA.md` §1-2).

    `kind` ∈ {"game", "system"}. Toute autre valeur (y compris "entity"/"level" — non
    écrits par le standard v1) est une VIOLATION EXPLICITE, jamais un crash.

    Retourne {passed, violations[]}. Jamais d'exception sur entrée malformée : un
    `contract` qui n'est pas un mapping produit une violation lisible, pas une TypeError.
    """
    if not isinstance(contract, dict):
        return {
            "passed": False,
            "violations": [f"contract n'est pas un mapping (reçu {type(contract).__name__})"],
        }

    if kind not in _SUPPORTED_KINDS:
        return {
            "passed": False,
            "violations": [
                f"kind non supporté: {kind!r} (formats écrits par le standard v1: "
                f"{', '.join(_SUPPORTED_KINDS)} — entity/level non encore écrits, "
                "cf. standard/SCHEMA.md §0)"
            ],
        }

    if kind == "game":
        label = "game_contract"
        violations = _closed_schema_violations(contract, _GAME_CONTRACT_SPEC, label)
        budget = contract.get("budget")
        if isinstance(budget, dict):
            violations += _closed_schema_violations(budget, _BUDGET_SPEC, f"{label}.budget")
        assets = contract.get("assets")
        if isinstance(assets, dict):
            violations += _closed_schema_violations(assets, _ASSETS_SPEC, f"{label}.assets")
    else:
        label = "system_contract"
        violations = _closed_schema_violations(contract, _SYSTEM_CONTRACT_SPEC, label)

    return {"passed": not violations, "violations": violations}


# --------------------------------------------------------------------------------------
# 2. check_budget — SCHEMA.md §1 : loi d'empilement + reuses au tier validated + brique
#    déposée forcément dans reuses ∪ adds.
# --------------------------------------------------------------------------------------


def check_budget(game_contract: dict, deposited_bricks: list[str], library_index: dict) -> dict:
    """Vérifie le budget d'un `game_contract` contre la bibliothèque et le dépôt réel.

    - `len(adds) <= 1` (loi d'empilement, §7 du standard).
    - tout `reuses[i]` existe dans `library_index` ET y est au tier `validated`.
    - toute brique de `deposited_bricks` appartient à `reuses ∪ adds` (sinon hors budget).
    - RÉCIPROQUE : toute brique promise dans `adds` mais JAMAIS déposée (absente de
      `deposited_bricks`) -> violation `promis_non_depose`. Sans ce contrôle, le volet
      `hors_budget` n'a qu'une seule direction et une promesse `adds` jamais tenue passe
      au vert par construction (tautologie mesurée sur `EVIDENCE/runs/pong_verif` : un
      `s10s` OK avec `game_loop` déclarée mais aucun dépositaire). La direction
      `hors_budget` seule a une variance nulle tant qu'aucun dépôt n'existe.
    - `adds ∩ reuses` non vide -> violation (chevauchement incohérent).

    Retourne {passed, empilement_violee, reuses_invalides[], hors_budget[],
    promis_non_depose[], chevauchement[]}.
    Jamais d'exception : toute entrée du mauvais type est traitée comme vide/absente.
    """
    if not isinstance(game_contract, dict):
        return {
            "passed": False,
            "raison": f"game_contract n'est pas un mapping (reçu {type(game_contract).__name__})",
            "empilement_violee": False,
            "reuses_invalides": [],
            "hors_budget": [],
            "promis_non_depose": [],
            "chevauchement": [],
        }

    budget = game_contract.get("budget")
    if not isinstance(budget, dict):
        return {
            "passed": False,
            "raison": "game_contract.budget absent ou n'est pas un mapping",
            "empilement_violee": False,
            "reuses_invalides": [],
            "hors_budget": [],
            "promis_non_depose": [],
            "chevauchement": [],
        }

    reuses_raw = budget.get("reuses")
    adds_raw = budget.get("adds")
    reuses = [r for r in reuses_raw if isinstance(r, str)] if isinstance(reuses_raw, list) else []
    adds = [a for a in adds_raw if isinstance(a, str)] if isinstance(adds_raw, list) else []
    deposited = (
        [b for b in deposited_bricks if isinstance(b, str)]
        if isinstance(deposited_bricks, list)
        else []
    )
    lib = library_index if isinstance(library_index, dict) else {}

    empilement_violee = len(adds) > 1

    reuses_invalides: list[str] = []
    for r in reuses:
        entry = lib.get(r)
        if not isinstance(entry, dict) or entry.get("tier") != "validated":
            reuses_invalides.append(r)

    budget_set = set(reuses) | set(adds)
    deposited_set = set(deposited)
    hors_budget = sorted({b for b in deposited if b not in budget_set})
    # RÉCIPROQUE de `hors_budget` : une brique promise dans `adds` mais jamais déposée.
    # Ferme la tautologie (une promesse `adds` non tenue passait au vert faute de contrôle
    # dans ce sens). N'inspecte QUE `adds` : un `reuses` désigne une brique préexistante
    # de la bibliothèque (validée par `reuses_invalides`), pas quelque chose que ce run
    # doit déposer.
    promis_non_depose = sorted({a for a in adds if a not in deposited_set})
    chevauchement = sorted(set(reuses) & set(adds))

    passed = not (
        empilement_violee
        or reuses_invalides
        or hors_budget
        or promis_non_depose
        or chevauchement
    )
    return {
        "passed": passed,
        "empilement_violee": empilement_violee,
        "reuses_invalides": reuses_invalides,
        "hors_budget": hors_budget,
        "promis_non_depose": promis_non_depose,
        "chevauchement": chevauchement,
    }


# --------------------------------------------------------------------------------------
# 3. check_line_states — SCHEMA.md §3 : les 6 états d'une ligne de wiremap v2.
# --------------------------------------------------------------------------------------

_ALLOWED_STATES = {"REQUIRED", "IMPLEMENTED", "NOT_APPLICABLE", "DEFERRED", "BLOCKED", "UNKNOWN"}

# Deux moments, deux vérifications (SCHEMA.md §3, "Deux moments, deux vérifications") :
#   - "draft"  : squelette pas encore gelé, rien n'est encore exigé (comportement historique
#                de l'ancien `frozen=False`) — conservé pour ne fermer aucune porte amont.
#   - "frozen" : au gel (avant build) — `UNKNOWN` interdit (rien ne doit rester indécis) ET
#                `IMPLEMENTED` interdit (rien n'est encore fait). C'était l'ancien `frozen=True`,
#                étendu avec la nouvelle interdiction sur IMPLEMENTED.
#   - "built"  : après build — `REQUIRED` interdit (tout ce qui était à faire doit être devenu
#                IMPLEMENTED ou BLOCKED). Moment nouveau, absent de l'ancien booléen.
_MOMENT_DRAFT = "draft"
_MOMENT_FROZEN = "frozen"
_MOMENT_BUILT = "built"
_KNOWN_MOMENTS = {_MOMENT_DRAFT, _MOMENT_FROZEN, _MOMENT_BUILT}


def _normalize_moment(frozen) -> str:
    """Rétro-compatibilité de signature (SCHEMA.md §3) : `frozen` accepte soit l'ancien
    booléen (`True` -> "frozen" au gel, `False` -> "draft" en brouillon), soit la nouvelle
    chaîne de moment ("draft"|"frozen"|"built"). Une chaîne inconnue retombe sur "frozen"
    (le plus strict), jamais un crash — même discipline que le reste du module."""
    if isinstance(frozen, str):
        return frozen if frozen in _KNOWN_MOMENTS else _MOMENT_FROZEN
    return _MOMENT_FROZEN if frozen else _MOMENT_DRAFT


# --- `lifecycle` — étage 1 ratifié Pierre 2026-08-02 (SCHEMA.md §3, section datée) ---
# Bloc OPTIONNEL par ligne : une ligne SANS `lifecycle` (ou `lifecycle: null`) reste
# valide telle quelle — zéro régression sur les cartes existantes (« Ne pas casser
# l'existant. »). PERSONNE n'écrit encore ce bloc (étage 2 — stampage par l'oracle —
# NON ratifié, conditionné P1-G4) : le schéma l'accepte, ce validateur le vérifie.
# Invariants verbatim : « implemented sans evidence = invalide » · « Le stampage reste
# oracle uniquement » (`verified_by` = jamais un agent LLM, un reçu <oracle_id|run_id>) ·
# « L'overlay Observer reste obligatoire comme contre-pouvoir ».
_LIFECYCLE_STATES = {"required", "implemented", "tested"}
_LIFECYCLE_KEYS = {"state", "evidence", "last_verified", "verified_by"}
_LIFECYCLE_EVIDENCE_KINDS = {"file_write", "oracle", "mutation", "visual"}
_LIFECYCLE_EVIDENCE_KEYS = {"kind", "ref", "sha256"}
_LIFECYCLE_TESTED_KINDS = {"oracle", "mutation"}
# États dont la revendication exige un reçu complet (evidence + last_verified + verified_by).
_LIFECYCLE_VERIFIED_STATES = {"implemented", "tested"}


def _is_iso8601(v: Any) -> bool:
    """ISO8601 parsable (datetime.fromisoformat, suffixe 'Z' accepté). Jamais d'exception."""
    if not isinstance(v, str) or not v.strip():
        return False
    s = v.strip()
    if s.endswith(("Z", "z")):
        s = s[:-1] + "+00:00"
    try:
        datetime.fromisoformat(s)
    except ValueError:
        return False
    return True


def _lifecycle_violations(lifecycle: Any, lid: str) -> list[str]:
    """Violations du bloc `lifecycle` d'UNE ligne (SCHEMA.md §3, étage 1 2026-08-02).

    Schéma FERMÉ (régime du studio) : clé inconnue = violation, dans le bloc comme dans
    chaque entrée d'`evidence`. Retourne des chaînes `"<line_id>: raison"`, liste vide si
    le bloc est conforme. Jamais d'exception sur entrée malformée."""
    if not isinstance(lifecycle, dict):
        return [f"{lid}: lifecycle n'est pas un mapping (reçu {type(lifecycle).__name__})"]

    v: list[str] = []
    for key in lifecycle.keys():
        if key not in _LIFECYCLE_KEYS:
            v.append(f"{lid}: clé inconnue dans lifecycle (schéma fermé) '{key}'")

    state = lifecycle.get("state")
    if state not in _LIFECYCLE_STATES:
        v.append(f"{lid}: lifecycle.state hors enum fermé (reçu {state!r})")

    # evidence[] : liste d'objets {kind, ref, sha256?}. On compte les entrées BIEN FORMÉES
    # (une entrée malformée est une violation, jamais un reçu).
    evidence = lifecycle.get("evidence")
    valid_entries: list[dict] = []
    if evidence is not None:
        if not isinstance(evidence, list):
            v.append(f"{lid}: lifecycle.evidence n'est pas une liste "
                     f"(reçu {type(evidence).__name__})")
        else:
            for i, entry in enumerate(evidence):
                if not isinstance(entry, dict):
                    v.append(f"{lid}: lifecycle.evidence[{i}] n'est pas un mapping")
                    continue
                entry_ok = True
                for key in entry.keys():
                    if key not in _LIFECYCLE_EVIDENCE_KEYS:
                        v.append(f"{lid}: clé inconnue dans lifecycle.evidence[{i}] "
                                 f"(schéma fermé) '{key}'")
                        entry_ok = False
                if entry.get("kind") not in _LIFECYCLE_EVIDENCE_KINDS:
                    v.append(f"{lid}: lifecycle.evidence[{i}].kind hors enum "
                             f"(reçu {entry.get('kind')!r})")
                    entry_ok = False
                if not _is_nonempty_str(entry.get("ref")):
                    v.append(f"{lid}: lifecycle.evidence[{i}].ref vide ou absent")
                    entry_ok = False
                if "sha256" in entry and not _is_nonempty_str(entry.get("sha256")):
                    v.append(f"{lid}: lifecycle.evidence[{i}].sha256 présent mais vide/mal typé")
                    entry_ok = False
                if entry_ok:
                    valid_entries.append(entry)

    claimed = state in _LIFECYCLE_VERIFIED_STATES
    if claimed and not valid_entries:
        # Invariant verbatim : « implemented sans evidence = invalide » (idem tested).
        v.append(f"{lid}: lifecycle.state={state} sans evidence non-vide — invalide")
    if state == "tested" and valid_entries and not any(
        e.get("kind") in _LIFECYCLE_TESTED_KINDS for e in valid_entries
    ):
        v.append(f"{lid}: lifecycle.state=tested sans reçu evidence.kind ∈ "
                 "{oracle, mutation}")

    # last_verified / verified_by : OBLIGATOIRES quand l'état revendique une vérification
    # (implemented/tested) ; en `required`, optionnels mais JAMAIS acceptés invalides.
    last_verified = lifecycle.get("last_verified")
    if claimed or last_verified is not None:
        if not _is_iso8601(last_verified):
            v.append(f"{lid}: lifecycle.last_verified non parsable ISO8601 "
                     f"(reçu {last_verified!r})")
    verified_by = lifecycle.get("verified_by")
    if claimed or verified_by is not None:
        if not _is_nonempty_str(verified_by):
            # « Le stampage reste oracle uniquement » : verified_by est un reçu
            # <oracle_id|run_id>, jamais un agent LLM — et jamais vide.
            v.append(f"{lid}: lifecycle.verified_by vide ou absent (reçu attendu : "
                     f"<oracle_id|run_id>)")
    return v


def check_line_states(wiremap: dict, core_requirements: dict, frozen: bool | str = True) -> dict:
    """Vérifie les contraintes des 6 états d'une ligne de wiremap v2 (`standard/SCHEMA.md` §3).

    - `state` doit appartenir à {REQUIRED, IMPLEMENTED, NOT_APPLICABLE, DEFERRED, BLOCKED, UNKNOWN}.
    - `NOT_APPLICABLE` sur une ligne `source == "CORE"` : interdit structurellement.
    - `NOT_APPLICABLE` sans `reason` non vide : violation.
    - `DEFERRED` sans `until` ET `decider` : violation.
    - Deux moments (`frozen`, cf. `_normalize_moment`) :
        - au gel ("frozen"/`True`) : `UNKNOWN` interdit ET `IMPLEMENTED` interdit.
        - après build ("built") : `REQUIRED` interdit.
        - brouillon ("draft"/`False`) : aucune des deux contraintes ci-dessus.
    - toute exigence de `core_requirements` absente de la wiremap (par `id`) : omission
      silencieuse, violation.
    - ligne `EXPECTED` sans `reference` non vide : violation.
    - ligne `EXPECTED`/`ADDITIONS` sans `source_role` : violation.
    - chaque ligne doit porter un `system_parent` non vide (SCHEMA.md §3, `system_parent`) :
      absence ou chaîne vide -> violation. C'est l'exigence de champ ; sa VALIDITÉ (désigne-t-il
      un système réel) est vérifiée par `check_placement`, pas ici.
    - bloc `lifecycle` OPTIONNEL (étage 1 ratifié Pierre 2026-08-02, SCHEMA.md §3) :
      une ligne SANS `lifecycle` (ou `lifecycle: null`) n'est soumise à AUCUNE règle
      nouvelle — zéro régression. Une ligne AVEC `lifecycle` est vérifiée par
      `_lifecycle_violations` (schéma fermé, enum d'états, evidence exigée sur
      implemented/tested, reçu oracle/mutation exigé sur tested, last_verified ISO8601,
      verified_by non vide) -> bucket `lifecycle_invalide[]`.
    - `reused_from` ADVISORY (R2, 2026-08-03, leçon `forge.wiremap_concept_reuse_requalification`) :
      une ligne dont `reused_from.type == "CONCEPT"` ET dont `reused_from.source` pointe un
      AUTRE jeu (`GAMES/<autre-id>/...`) que `wiremap.game_id` DOIT porter une requalification
      explicite non vide dans un champ EXISTANT (`reused_from_note`, à défaut `reason`).
      Absence -> bucket `reused_concept_non_requalifie[]`. Ce bucket est REMONTÉ mais ne fait
      PAS basculer `passed` (même prudence que `lifecycle` étage 1 : on mesure avant de durcir ;
      la wiremap réelle breakout_v2 a 52 lignes CONCEPT, une règle stricte la ferait échouer
      d'un coup sur une campagne déjà archivée).

    Retourne un dict `{passed, etats_invalides[], not_applicable_sur_core[],
    not_applicable_sans_raison[], deferred_incomplet[], unknown_au_gel[], implemented_au_gel[],
    required_apres_build[], core_omis[], expected_sans_reference[], source_manquante[],
    system_parent_manquant[], lifecycle_invalide[], reused_concept_non_requalifie[]}`.
    Jamais d'exception.
    """
    empty = {
        "etats_invalides": [],
        "not_applicable_sur_core": [],
        "not_applicable_sans_raison": [],
        "deferred_incomplet": [],
        "unknown_au_gel": [],
        "implemented_au_gel": [],
        "required_apres_build": [],
        "core_omis": [],
        "expected_sans_reference": [],
        "source_manquante": [],
        "system_parent_manquant": [],
        "lifecycle_invalide": [],
        "reused_concept_non_requalifie": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }

    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []
    moment = _normalize_moment(frozen)
    game_id = wiremap.get("game_id") if isinstance(wiremap.get("game_id"), str) else None

    # P5 (2026-08-15) — garde de NON-VACUITÉ (code review : une wiremap
    # `lines: []` passait ce volet et 4 autres par vacuité — zéro contrainte
    # vérifiée, PASS affiché ; seuls `core_omis` — si core_requirements fourni —
    # et le scan disque de check_index compensaient). Une carte vide n'est pas
    # une carte conforme : FAIL, SAUF waiver EXPLICITE `no_lines_waiver` au
    # sommet de la wiremap — même convention de traçabilité que DEFERRED :
    # `reason` ET `decider` non vides. Le waiver n'excuse QUE la vacuité : les
    # exigences `core_requirements` omises restent des violations (`core_omis`),
    # et le waiver est TOUJOURS remonté dans le rapport, jamais silencieux.
    # PÉRIMÈTRE DÉCLARÉ (gate ouverte) : la garde couvre `lines` ABSENT ou LISTE
    # VIDE. Le cas `lines` d'un MAUVAIS TYPE conserve son comportement historique
    # (passed True, « aucune ligne exploitable ») figé par
    # test_line_states_lines_not_a_list_no_crash — le durcir exige un arbitrage
    # Pierre sur ce test ; résidu de vacuité DÉCLARÉ, pas silencieux.
    no_lines_waiver = None
    if lines_raw is None or lines_raw == []:
        waiver = wiremap.get("no_lines_waiver")
        if (isinstance(waiver, dict)
                and str(waiver.get("reason") or "").strip()
                and str(waiver.get("decider") or "").strip()):
            no_lines_waiver = waiver
        else:
            return {
                "passed": False,
                "raison": ("wiremap sans ligne (`lines` vide ou absent) : vacuité "
                           "— rien n'est vérifié, un PASS serait fabriqué. Fournir "
                           "des lignes, ou un `no_lines_waiver` {reason, decider} "
                           "explicite au sommet de la wiremap"),
                **empty,
            }

    etats_invalides: list[str] = []
    not_applicable_sur_core: list[str] = []
    not_applicable_sans_raison: list[str] = []
    deferred_incomplet: list[str] = []
    unknown_au_gel: list[str] = []
    implemented_au_gel: list[str] = []
    required_apres_build: list[str] = []
    expected_sans_reference: list[str] = []
    source_manquante: list[str] = []
    system_parent_manquant: list[str] = []
    lifecycle_invalide: list[str] = []
    reused_concept_non_requalifie: list[str] = []
    seen_ids: list[str] = []

    for line in lines:
        if not isinstance(line, dict):
            etats_invalides.append("<ligne non-mapping>")
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"
        seen_ids.append(lid)
        state = line.get("state")
        source = line.get("source")

        if state not in _ALLOWED_STATES:
            etats_invalides.append(f"{lid}:{state!r}")
        else:
            if state == "NOT_APPLICABLE":
                if source == "CORE":
                    not_applicable_sur_core.append(lid)
                reason = line.get("reason")
                if not (isinstance(reason, str) and reason.strip()):
                    not_applicable_sans_raison.append(lid)
            if state == "DEFERRED":
                until = line.get("until")
                decider = line.get("decider")
                if not (isinstance(until, str) and until.strip()) or not (
                    isinstance(decider, str) and decider.strip()
                ):
                    deferred_incomplet.append(lid)
            if state == "UNKNOWN" and moment == _MOMENT_FROZEN:
                unknown_au_gel.append(lid)
            if state == "IMPLEMENTED" and moment == _MOMENT_FROZEN:
                implemented_au_gel.append(lid)
            if state == "REQUIRED" and moment == _MOMENT_BUILT:
                required_apres_build.append(lid)

        if source == "EXPECTED":
            reference = line.get("reference")
            if not (isinstance(reference, str) and reference.strip()):
                expected_sans_reference.append(lid)
        if source in ("EXPECTED", "ADDITIONS"):
            source_role = line.get("source_role")
            if not (isinstance(source_role, str) and source_role.strip()):
                source_manquante.append(lid)

        system_parent = line.get("system_parent")
        if not (isinstance(system_parent, str) and system_parent.strip()):
            system_parent_manquant.append(lid)

        # `lifecycle` — étage 1 (2026-08-02) : absent ou null = ligne valide telle quelle
        # (zéro régression, « Ne pas casser l'existant. ») ; présent = vérifié, fermé.
        lifecycle = line.get("lifecycle")
        if lifecycle is not None:
            lifecycle_invalide.extend(_lifecycle_violations(lifecycle, lid))

        # `reused_from` — R2 (2026-08-03), leçon forge.wiremap_concept_reuse_requalification :
        # ADVISORY only (voir docstring), n'entre pas dans `passed`.
        reused_from = line.get("reused_from")
        if isinstance(reused_from, dict) and reused_from.get("type") == "CONCEPT":
            rf_source = reused_from.get("source")
            other_project = False
            if isinstance(rf_source, str) and isinstance(game_id, str) and game_id:
                parts = rf_source.split("/")
                if len(parts) >= 2 and parts[0] == "games" and parts[1] != game_id:
                    other_project = True
            if other_project:
                note = line.get("reused_from_note")
                reason = line.get("reason")
                requalifie = (isinstance(note, str) and note.strip()) or (
                    isinstance(reason, str) and reason.strip()
                )
                if not requalifie:
                    reused_concept_non_requalifie.append(
                        f"{lid}: reused_from.type=CONCEPT source={rf_source!r} sans "
                        "requalification (reused_from_note/reason vide) "
                        "[forge.wiremap_concept_reuse_requalification]"
                    )

    core_omis: list[str] = []
    if isinstance(core_requirements, dict):
        reqs = core_requirements.get("requirements")
        if isinstance(reqs, list):
            for req in reqs:
                if isinstance(req, dict) and isinstance(req.get("id"), str):
                    rid = req["id"]
                    if rid not in seen_ids:
                        core_omis.append(rid)

    passed = not (
        etats_invalides
        or not_applicable_sur_core
        or not_applicable_sans_raison
        or deferred_incomplet
        or unknown_au_gel
        or implemented_au_gel
        or required_apres_build
        or core_omis
        or expected_sans_reference
        or source_manquante
        or system_parent_manquant
        or lifecycle_invalide
    )
    result_extra = {}
    if no_lines_waiver is not None:
        # traçabilité P5 : le waiver accepté apparaît dans le reçu signé du volet.
        result_extra["no_lines_waiver"] = no_lines_waiver
    return {
        "passed": passed,
        **result_extra,
        "etats_invalides": etats_invalides,
        "not_applicable_sur_core": not_applicable_sur_core,
        "not_applicable_sans_raison": not_applicable_sans_raison,
        "deferred_incomplet": deferred_incomplet,
        "unknown_au_gel": unknown_au_gel,
        "implemented_au_gel": implemented_au_gel,
        "required_apres_build": required_apres_build,
        "core_omis": core_omis,
        "expected_sans_reference": expected_sans_reference,
        "source_manquante": source_manquante,
        "system_parent_manquant": system_parent_manquant,
        "lifecycle_invalide": lifecycle_invalide,
        "reused_concept_non_requalifie": reused_concept_non_requalifie,
    }


# --------------------------------------------------------------------------------------
# 4. check_placement — SCHEMA.md §4.3 + repo_map.yaml : adresse cohérente avec la
#    catégorie, catégorie absente de la table = violation (jamais un placement par défaut).
# --------------------------------------------------------------------------------------


def _is_named_artifact_template(template: object) -> bool:
    """Gabarit d'ARTEFACT NOMMÉ au sens `REPO_MAP_TEMPLATE_IDENTITY_V1` (ratifié
    Pierre 2026-07-23) : « Un gabarit qui revendique un artefact concret doit porter
    un identifiant stable permettant une correspondance univoque. Les motifs
    génériques sont réservés aux catégories, pas aux preuves d'existence. »

    La FORME est déclarée par la table, jamais codée en dur ici (aucune liste
    `test.*`/`asset.*` dans le code) : un gabarit qui ne se termine PAS par `/` et
    qui porte `{id}` désigne un fichier nommé ; tout le reste est un dossier
    (motif générique de catégorie). L'obligation de porter `{id}` sur les catégories
    `test.*`/`asset.*` (le `scope` de la décision) est un invariant de la TABLE,
    vérifié mécaniquement côté tests."""
    if not isinstance(template, str):
        return False
    t = template.strip().replace("\\", "/")
    return bool(t) and not t.endswith("/") and "{id}" in t


def _named_artifact_dir(template: str) -> str:
    """Dossier d'un gabarit d'artefact nommé (segment `{id}` terminal retiré).

    Sert à garder INCHANGÉ le comportement des `address` de ligne : une adresse
    reste jugée sur le dossier de la catégorie, jamais sur un nom de fichier."""
    t = template.strip().replace("\\", "/")
    head = t.rsplit("/", 1)[0] if "/" in t else ""
    return (head + "/") if head else ""


def _template_expected_prefix(template: str, deriv_id: str) -> str:
    """Gabarit `mapping[category]` -> préfixe de chemin attendu, `{id}` substitué.

    Fonction unique pour les DEUX usages du gabarit (adresse de ligne §4.3 ET
    placement de fichier §1 déclaré) — ne jamais dupliquer cette substitution.

    Un gabarit d'ARTEFACT NOMMÉ (`07_TESTS/oracle/{id}`) n'a pas de préfixe au sens
    d'un dossier de ligne : on retombe sur son dossier (`07_TESTS/oracle/`), ce qui
    laisse le jugement des `address` STRICTEMENT identique à avant la décision
    `REPO_MAP_TEMPLATE_IDENTITY_V1` — une ligne n'est pas un fichier."""
    if _is_named_artifact_template(template):
        return _named_artifact_dir(template)
    return template.replace("{id}", deriv_id).replace("\\", "/").rstrip("/") + "/"


def _named_artifact_expected_path(template: str, artifact_id: str) -> str:
    """Chemin EXACT attendu pour un artefact nommé d'identifiant `artifact_id`."""
    return template.strip().replace("\\", "/").replace("{id}", artifact_id)


def _check_declared_fichiers(
    fichiers: list, lid: str, deriv_id: str, mapping: dict
) -> tuple[list[str], list[str], list[str], list[tuple[str, str, str, str]]]:
    """Valide les entrées `fichiers[]` d'une ligne de wiremap `schema_version: 2`
    (`standard/SCHEMA.md` §3 — format déclaré, jamais déduit du nom de fichier).

    - une entrée qui n'est pas un mapping `{path, category}` (chaîne nue = ancien
      format, ou tout autre type) -> `categorie_fichier_non_declaree` : c'est le trou
      que cette fonction ferme, jamais accepté en silence.
    - `path` absent/vide ou `category` absent/vide sur une entrée-mapping -> même
      liste (`categorie_fichier_non_declaree`) : la déclaration est incomplète.
    - `category` non nulle mais absente de `repo_map["mapping"]` -> `categorie_fichier_non_mappee`
      (jamais de placement par défaut, même discipline que `categorie_non_mappee`).
    - `path` incohérent avec le gabarit `mapping[category]` (même fonction que pour
      l'adresse d'une ligne, `_template_expected_prefix`) -> `fichier_adresse_incoherente`.
    - si le gabarit est un gabarit d'ARTEFACT NOMMÉ (`REPO_MAP_TEMPLATE_IDENTITY_V1`),
      l'identifiant est le NOM DU FICHIER et le chemin doit valoir EXACTEMENT le gabarit
      substitué (l'artefact vit directement dans le dossier de sa catégorie) ; la
      revendication est en outre COLLECTÉE pour que `check_placement` puisse juger
      l'unicité de la liaison identité<->cible (ce que la table ne permettait pas de
      voir tant que les gabarits `test.*`/`asset.*` étaient des motifs génériques).

    Retourne (categorie_fichier_non_declaree, categorie_fichier_non_mappee,
    fichier_adresse_incoherente, revendications) où `revendications` est la liste des
    (category, artifact_id, path, line_id) portant sur un artefact nommé — une
    revendication est enregistrée MÊME si son chemin est incohérent : un fichier mal
    placé reste revendiqué, et c'est ce qui rend l'ambiguïté d'identité visible.
    Jamais d'exception sur entrée malformée.
    """
    non_declaree: list[str] = []
    non_mappee: list[str] = []
    incoherente: list[str] = []
    revendications: list[tuple[str, str, str, str]] = []

    for entry in fichiers:
        if not isinstance(entry, dict):
            descriptor = entry if isinstance(entry, str) else repr(entry)
            non_declaree.append(f"{lid}:{descriptor}")
            continue

        fpath = entry.get("path")
        if not (isinstance(fpath, str) and fpath.strip()):
            non_declaree.append(f"{lid}:<path vide ou absent>")
            continue

        fcategory = entry.get("category")
        if not (isinstance(fcategory, str) and fcategory.strip()):
            non_declaree.append(f"{lid}:{fpath}")
            continue

        ftemplate = mapping.get(fcategory)
        if not isinstance(ftemplate, str):
            non_mappee.append(f"{lid}:{fpath}:{fcategory}")
            continue

        norm_path = fpath.strip().replace("\\", "/")

        if _is_named_artifact_template(ftemplate):
            artifact_id = norm_path.rsplit("/", 1)[-1]
            if not artifact_id:
                # chemin qui se termine par « / » : un dossier n'est pas un artefact nommé.
                incoherente.append(
                    f"{lid}:{fpath} (artefact nommé attendu, dossier reçu, category={fcategory})"
                )
                continue
            expected_path = _named_artifact_expected_path(ftemplate, artifact_id)
            if norm_path != expected_path:
                incoherente.append(
                    f"{lid}:{fpath} (artefact nommé attendu exactement à "
                    f"'{expected_path}', category={fcategory})"
                )
            revendications.append((fcategory, artifact_id, norm_path, lid))
            continue

        expected = _template_expected_prefix(ftemplate, deriv_id)
        if not norm_path.startswith(expected):
            incoherente.append(f"{lid}:{fpath} (attendu sous '{expected}', category={fcategory})")

    return non_declaree, non_mappee, incoherente, revendications


def check_placement(wiremap: dict, repo_map: dict) -> dict:
    """Vérifie que chaque ligne a une adresse non vide et cohérente avec sa catégorie.

    - `address` non vide requis sur chaque ligne.
    - catégorie absente de `repo_map["mapping"]` -> violation explicite (jamais de
      placement par défaut, cf. `repo_map.yaml` en-tête).
    - `address` incohérente avec le gabarit `mapping[category]` -> violation. Le gabarit
      est rempli avec `system_parent` (SCHEMA.md §3, "plusieurs lignes vivent légitimement
      dans le même système") si la ligne en porte un valide, JAMAIS avec l'identifiant de
      la ligne dans ce cas — c'est ce qui permet à `core.game_state`, `core.end_condition`
      et `core.restart` de partager une adresse. Une ligne sans `system_parent` (wiremaps
      antérieures à cette section) retombe sur l'ancien comportement (`{id}` = identifiant
      de la ligne), pour rester rétro-compatible.
    - `system_parent` qui ne désigne aucune entrée de `wiremap["systems"]` (passe 1,
      SCHEMA.md §3) -> violation `system_parent_inconnu` : un meuble ne peut pas exister
      dans une pièce que le plan n'a jamais posée. L'exigence de simple PRÉSENCE du champ
      est du ressort de `check_line_states` (séparation des responsabilités) ; ici on ne
      juge que sa VALIDITÉ quand il est fourni.
    - la `category` de CHAQUE entrée de `wiremap["systems"]` (passe 1) doit elle-même
      exister dans `repo_map["mapping"]` -> sinon `systeme_categorie_non_mappee`. Un
      système gelé sur une catégorie que la table ne connaît pas ne pourra jamais être
      matérialisé (même discipline que `categorie_non_mappee`, appliquée à la passe 1).
    - **SSI `wiremap["schema_version"] == 2`** : chaque entrée de `fichiers[]` d'une
      ligne doit être un objet `{path, category}` — jamais déduit du nom de fichier
      (§1 du standard). Une entrée restée une chaîne nue (ancien format), une catégorie
      inconnue de la table, ou un `path` incohérent avec le gabarit de sa catégorie sont
      des violations distinctes (`categorie_fichier_non_declaree`,
      `categorie_fichier_non_mappee`, `fichier_adresse_incoherente`). Les wiremaps
      `schema_version` absente ou `1` ne subissent AUCUN changement de comportement —
      ce sont des preuves de runs passés (rétro-compatibilité stricte).

    - **`REPO_MAP_TEMPLATE_IDENTITY_V1`** (ratifié Pierre 2026-07-23), sur les seuls
      gabarits d'ARTEFACT NOMMÉ de la table (`test.*`/`asset.*` : `.../{id}` sans `/`
      final) : `duplicate_claims` est un `FAIL` dans les deux sens —
      `same_target_multiple_ids` -> `revendications_multiples` (un même fichier
      revendiqué par plusieurs identités : c'est la contrainte qui manquait, un
      artefact nommé a UN déposant) et `same_id_multiple_targets` ->
      `identite_ambigue` (un même identifiant désignant plusieurs fichiers distincts :
      plus de correspondance univoque). Aucune rustine « première correspondance » :
      les deux volets ÉNUMÈRENT le conflit au lieu d'en choisir un arbitrairement.

    Retourne {passed, adresse_manquante[], categorie_manquante[], categorie_non_mappee[],
    adresse_incoherente[], system_parent_inconnu[], systeme_categorie_non_mappee[],
    categorie_fichier_non_declaree[], categorie_fichier_non_mappee[],
    fichier_adresse_incoherente[], revendications_multiples[], identite_ambigue[]}.
    Jamais d'exception sur entrée malformée.
    """
    empty = {
        "adresse_manquante": [],
        "categorie_manquante": [],
        "categorie_non_mappee": [],
        "adresse_incoherente": [],
        "system_parent_inconnu": [],
        "systeme_categorie_non_mappee": [],
        "categorie_fichier_non_declaree": [],
        "categorie_fichier_non_mappee": [],
        "fichier_adresse_incoherente": [],
        "revendications_multiples": [],
        "identite_ambigue": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }

    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []

    systems_raw = wiremap.get("systems")
    systems = systems_raw if isinstance(systems_raw, list) else []
    system_ids = {
        s["id"] for s in systems if isinstance(s, dict) and isinstance(s.get("id"), str)
    }

    mapping: dict = {}
    if isinstance(repo_map, dict) and isinstance(repo_map.get("mapping"), dict):
        mapping = repo_map["mapping"]

    # Déclencheur de la normalisation §1 : SEULE `schema_version: 2` active la
    # validation des fichiers déclarés — rétro-compatibilité stricte des wiremaps
    # antérieures (SCHEMA.md §3, "Ne pas confondre... rétro-compatibilité").
    schema_v2 = wiremap.get("schema_version") == 2

    adresse_manquante: list[str] = []
    categorie_manquante: list[str] = []
    categorie_non_mappee: list[str] = []
    adresse_incoherente: list[str] = []
    system_parent_inconnu: list[str] = []
    systeme_categorie_non_mappee: list[str] = []
    categorie_fichier_non_declaree: list[str] = []
    categorie_fichier_non_mappee: list[str] = []
    fichier_adresse_incoherente: list[str] = []
    # Revendications d'artefacts NOMMÉS, toutes lignes confondues (REPO_MAP_TEMPLATE_
    # IDENTITY_V1) : (category, artifact_id, path, line_id). L'unicité de la liaison
    # ne peut se juger qu'ICI — une ligne seule ne voit pas ce que les autres revendiquent.
    revendications: list[tuple[str, str, str, str]] = []

    for system in systems:
        if not isinstance(system, dict):
            continue
        sid = system.get("id") if isinstance(system.get("id"), str) else "<systeme-sans-id>"
        scat = system.get("category")
        if not (isinstance(scat, str) and scat.strip()) or scat not in mapping:
            systeme_categorie_non_mappee.append(f"{sid}:{scat!r}")

    for line in lines:
        if not isinstance(line, dict):
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"

        if schema_v2:
            fichiers_raw = line.get("fichiers")
            if isinstance(fichiers_raw, list) and fichiers_raw:
                system_parent_f = line.get("system_parent")
                has_system_parent_f = (
                    isinstance(system_parent_f, str) and system_parent_f.strip() != ""
                )
                deriv_id_f = system_parent_f if has_system_parent_f else lid
                nd, nm, inc, rev = _check_declared_fichiers(
                    fichiers_raw, lid, deriv_id_f, mapping
                )
                categorie_fichier_non_declaree += nd
                categorie_fichier_non_mappee += nm
                fichier_adresse_incoherente += inc
                revendications += rev

        address = line.get("address")
        if not (isinstance(address, str) and address.strip()):
            adresse_manquante.append(lid)
            continue

        category = line.get("category")
        if not (isinstance(category, str) and category.strip()):
            categorie_manquante.append(lid)
            continue

        system_parent = line.get("system_parent")
        has_system_parent = isinstance(system_parent, str) and system_parent.strip() != ""
        if has_system_parent and system_parent not in system_ids:
            system_parent_inconnu.append(f"{lid}:{system_parent}")
            # system_parent fourni mais invalide -> on n'en dérive pas d'adresse
            # (elle serait de toute façon calculée à partir d'un système fantôme).
            continue

        template = mapping.get(category)
        if not isinstance(template, str):
            categorie_non_mappee.append(f"{lid}:{category}")
            continue

        # L'adresse se dérive de `category` + `system_parent` (jamais de l'id de la ligne)
        # dès qu'un `system_parent` valide est présent ; sinon repli sur l'ancien schéma.
        deriv_id = system_parent if has_system_parent else lid
        expected = _template_expected_prefix(template, deriv_id)
        norm_addr = address.strip().replace("\\", "/").rstrip("/") + "/"
        if not norm_addr.startswith(expected):
            adresse_incoherente.append(f"{lid}: attendu '{expected}', reçu '{address}'")

    # --- REPO_MAP_TEMPLATE_IDENTITY_V1 : unicité de la liaison identité <-> cible ---
    # `same_target_multiple_ids` : une cible revendiquée par plusieurs identités
    # distinctes (identité = ligne déposante + catégorie de l'artefact).
    par_cible: dict[str, set[tuple[str, str]]] = {}
    # `same_id_multiple_targets` : un identifiant (catégorie + nom d'artefact) qui
    # désigne plusieurs fichiers distincts.
    par_identite: dict[tuple[str, str], set[str]] = {}
    for fcat, aid, fpath, line_id in revendications:
        par_cible.setdefault(fpath, set()).add((line_id, fcat))
        par_identite.setdefault((fcat, aid), set()).add(fpath)

    revendications_multiples: list[str] = []
    for fpath in sorted(par_cible):
        identites = sorted(par_cible[fpath])
        if len(identites) > 1:
            detail_ids = ", ".join(f"{lid}/{cat}" for lid, cat in identites)
            revendications_multiples.append(
                f"{fpath} : revendiqué par {len(identites)} identités distinctes ({detail_ids})"
            )

    identite_ambigue: list[str] = []
    for fcat, aid in sorted(par_identite):
        cibles = sorted(par_identite[(fcat, aid)])
        if len(cibles) > 1:
            identite_ambigue.append(
                f"{fcat}:{aid} : {len(cibles)} cibles distinctes ({', '.join(cibles)})"
            )

    passed = not (
        adresse_manquante
        or categorie_manquante
        or categorie_non_mappee
        or adresse_incoherente
        or system_parent_inconnu
        or systeme_categorie_non_mappee
        or categorie_fichier_non_declaree
        or categorie_fichier_non_mappee
        or fichier_adresse_incoherente
        or revendications_multiples
        or identite_ambigue
    )
    return {
        "passed": passed,
        "adresse_manquante": adresse_manquante,
        "categorie_manquante": categorie_manquante,
        "categorie_non_mappee": categorie_non_mappee,
        "adresse_incoherente": adresse_incoherente,
        "system_parent_inconnu": system_parent_inconnu,
        "systeme_categorie_non_mappee": systeme_categorie_non_mappee,
        "categorie_fichier_non_declaree": categorie_fichier_non_declaree,
        "categorie_fichier_non_mappee": categorie_fichier_non_mappee,
        "fichier_adresse_incoherente": fichier_adresse_incoherente,
        "revendications_multiples": revendications_multiples,
        "identite_ambigue": identite_ambigue,
    }


# --------------------------------------------------------------------------------------
# 5. check_index — SCHEMA.md §4.4 : indexation dans les deux sens, carte<->disque.
#    C'est la moitié qui manque à check_wiremap (static_oracles.py) aujourd'hui :
#    check_wiremap ne teste QUE carte -> disque. Ici on teste aussi disque -> carte.
# --------------------------------------------------------------------------------------


# Dossiers de gouvernance (racines de `repo_map.yaml`) : contenu de PILOTAGE du run
# (charte, design, télémétrie, carte, artefacts Forge), pas contenu de JEU — ils n'ont
# pas vocation à être référencés par une `address` de ligne. Les exclure du contrôle
# d'orphelins évite le faux positif "00_CHARTER/09_WIREMAP orphelins" (correction
# standard 2026-07-22, cf. rapport de sondage des 6 oracles sur le squelette Pong).
_GOVERNANCE_DIRS = ("00_CHARTER", "01_DESIGN", "08_TELEMETRY", "09_WIREMAP", "10_FORGE")


def _is_governance_path(rel: str) -> bool:
    top = rel.split("/", 1)[0]
    return top in _GOVERNANCE_DIRS


def _is_artefact_outil(rel: str) -> bool:
    """Artefact REGENERE PAR L'OUTILLAGE, jamais produit ni déclaré par le jeu.

    Cause mesurée (run snake-descripteur-20260729, gate Pierre 2026-07-28) : les 64
    lancements Godot du gate mutation recréent `GAMES/snake/.godot/` (cache d'import +
    shader cache, 124 dossiers). `check_index` scannant le DISQUE, il les comptait en
    `dossiers_orphelins`/`dossiers_hors_structure` — un rouge produit par l'acte de
    mesurer, pas par le jeu. Le `.gitignore` masque ce cache pour git, jamais pour un
    scan disque.

    Critère : tout segment de chemin commençant par un point (convention universelle des
    dossiers d'outillage : `.godot`, `.import`, `.venv`, `.pytest_cache`…). Un jeu ne
    déclare JAMAIS d'adresse cachée — `repo_map.yaml` n'en contient aucune — donc cette
    exemption ne peut pas blanchir un fichier légitimement attendu.

    PORTÉE : n'affecte QUE le contrôle d'orphelins/hors-structure. Le sens carte→disque
    (un fichier déclaré doit exister) est INCHANGÉ : un `.gd` manquant reste une violation.
    Non-régression Pong vérifiée : son arbre ne contient aucun segment caché, son résultat
    est identique avant/après.
    """
    return any(seg.startswith(".") for seg in rel.split("/") if seg)


def check_index(
    wiremap: dict, src_root: Path, built: bool = True, repo_map: dict | None = None
) -> dict:
    """Index BIDIRECTIONNEL entre la wiremap et le disque.

    - carte -> disque : tout `fichiers[]`/`address` déclaré par une ligne existe — SSI
      `built` est True. **Avant build** (`built=False`), un fichier/dossier déclaré qui
      n'existe pas encore n'est PAS une violation : rien n'est construit, c'est attendu
      (SCHEMA.md §3, doctrine "deux moments, deux vérifications"). Une entrée de
      `fichiers[]` est acceptée sous DEUX formes, sans changement de comportement pour
      l'une ou l'autre : chaîne nue (chemin direct, wiremaps antérieures à
      `schema_version: 2`) ou objet `{path, category}` (schema_version 2, le chemin est
      `path`). Dans les deux cas seul le CHEMIN est indexé ici — juger `category`
      appartient exclusivement à `check_placement` (jamais deux implémentations de la
      même règle, cf. `FORGE_SYSTEM_CONTRACT.yaml`).
    - disque -> carte : tout fichier de logique (extensions `SOURCE_EXTS`, hors fichiers
      de test — réutilise `_is_test_file`/`_source_files` de `static_oracles.py`) présent
      sous `src_root` est cité par au moins une ligne ; sinon `orphelins` (du code que
      personne n'a demandé). Les dossiers de gouvernance (`_GOVERNANCE_DIRS` : charte,
      design, télémétrie, wiremap, artefacts Forge) ne sont PAS du contenu de jeu et sont
      exclus de ce contrôle, dans les deux sens (fichiers et dossiers).
    - un dossier référencé (`address`) qui n'existe pas -> violation SSI `built`.
    - un dossier qui existe (contient au moins un fichier), n'est référencé NI par une
      `address` NI par un fichier cité dans `fichiers[]` ET n'est pas un dossier de
      gouvernance -> violation (`dossiers_orphelins`, dossier vide de façade). Un dossier
      compte comme référencé s'il est égal à, ancêtre de, ou contient un fichier cité
      (décision Pierre 2026-07-23, `CHECK_INDEX_SYMMETRY_V1`) : `fichiers[]` prouvait déjà
      le référencement des FICHIERS (`cited_files`) mais, pour les DOSSIERS, seul
      `cited_addresses` était consulté — deux règles de preuve dans un même oracle. Sans
      cette symétrie, des dossiers réels contenant des fichiers cités (ex. `07_TESTS/unit`)
      étaient de faux orphelins. Un dossier de premier niveau hors structure reste attrapé
      par `dossiers_hors_structure` (ci-dessous), pas par ce volet.
    - **SSI `repo_map` est fourni** : tout dossier de PREMIER NIVEAU sous `src_root` qui
      n'appartient pas à `repo_map["roots"]` -> violation (`dossiers_hors_structure`).
      Attrape un builder qui crée `src/`, `lib/`, etc. hors de la structure figée. Ne
      descend jamais au-delà du premier niveau (les sous-dossiers d'une racine connue
      — ex. `05_SYSTEMS/game_loop/` — ne sont jamais concernés). `repo_map` est
      optionnel et absent par défaut : omis, ce contrôle ne s'exécute pas (aucun
      changement de comportement pour les appelants existants).

    Retourne {passed, fichiers_manquants[], dossiers_manquants[], orphelins[],
    dossiers_orphelins[], dossiers_hors_structure[]}. Jamais d'exception sur entrée
    malformée ou `src_root` absent.
    """
    empty = {
        "fichiers_manquants": [],
        "dossiers_manquants": [],
        "orphelins": [],
        "dossiers_orphelins": [],
        "dossiers_hors_structure": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }

    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []
    root = Path(src_root)

    cited_files: set[str] = set()
    cited_addresses: list[str] = []
    fichiers_manquants: list[str] = []
    dossiers_manquants: list[str] = []

    for line in lines:
        if not isinstance(line, dict):
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"

        fichiers = line.get("fichiers")
        if isinstance(fichiers, list):
            for f in fichiers:
                # Deux formes acceptées (SCHEMA.md §3) : chaîne nue (wiremaps
                # antérieures à `schema_version: 2`, comportement INCHANGÉ) ou objet
                # `{path, category}` (schema_version 2). Ici on n'indexe QUE le chemin
                # — juger `category` appartient à `check_placement` (FORGE_SYSTEM_CONTRACT.yaml :
                # une seule implémentation par règle, jamais dupliquée entre oracles).
                if isinstance(f, str):
                    fpath = f
                elif isinstance(f, dict):
                    fpath = f.get("path")
                else:
                    continue
                if not (isinstance(fpath, str) and fpath.strip()):
                    continue
                norm = fpath.replace("\\", "/")
                cited_files.add(norm)
                if built and not (root / fpath).exists():
                    fichiers_manquants.append(f"{lid}:{fpath}")

        address = line.get("address")
        if isinstance(address, str) and address.strip():
            norm_addr = address.strip().replace("\\", "/").rstrip("/")
            cited_addresses.append(norm_addr)
            if built and not (root / norm_addr).is_dir():
                dossiers_manquants.append(f"{lid}:{address}")

    orphelins: list[str] = []
    dossiers_orphelins: list[str] = []

    if root.exists() and root.is_dir():
        for path in _source_files(root):
            if _is_test_file(path):
                continue
            rel = path.relative_to(root).as_posix()
            if _is_governance_path(rel) or _is_artefact_outil(rel):
                continue
            if rel not in cited_files:
                orphelins.append(rel)

        for d in sorted(p for p in root.rglob("*") if p.is_dir()):
            rel = d.relative_to(root).as_posix()
            if _is_governance_path(rel) or _is_artefact_outil(rel):
                continue
            files_in_dir = [p for p in d.rglob("*") if p.is_file()]
            if not files_in_dir:
                continue  # dossier structurel vide : pas la préoccupation visée ici
            # Exemption dossier 100%-tests (décision Pierre 2026-07-23) : symétrique EXACT
            # de l'exclusion `_is_test_file` déjà appliquée aux FICHIERS ci-dessus. Un
            # dossier ne contenant QUE des fichiers de test (`*.test.mjs`…, même heuristique
            # `_is_test_file`) n'a pas à être référencé par une `address` ni par `fichiers[]`
            # — les tests sont légitimement déclarés ailleurs (`system_contract.tests`),
            # jamais dans la wiremap. Un dossier avec ne serait-ce qu'un fichier NON-test
            # reste soumis à la règle (l'exemption ne blanchit pas un dossier mixte).
            if all(_is_test_file(p) for p in files_in_dir):
                continue
            # référencé si égal à une adresse citée, descendant d'une adresse citée
            # (ex. sous-dossier d'un système), OU ANCÊTRE d'une adresse citée (ex.
            # "05_SYSTEMS/" est un parent structurel nécessaire de "05_SYSTEMS/game_loop/"
            # cité — ce n'est pas un dossier de façade, juste un dossier-racine).
            referenced = any(
                rel == addr or rel.startswith(addr + "/") or addr.startswith(rel + "/")
                for addr in cited_addresses
            )
            # CHECK_INDEX_SYMMETRY_V1 (décision Pierre 2026-07-23) : `fichiers[]` prouve
            # AUSSI le référencement d'un dossier. Un dossier est référencé s'il contient
            # (est égal à, ou ancêtre de) un fichier cité — même règle de preuve que pour
            # les fichiers, appliquée aux dossiers. Ne rend PAS l'oracle aveugle : un
            # dossier de premier niveau hors structure sans aucun fichier cité reste
            # orphelin ici (et attrapé par `dossiers_hors_structure`).
            if not referenced:
                referenced = any(
                    cf == rel or cf.startswith(rel + "/") for cf in cited_files
                )
            if not referenced:
                dossiers_orphelins.append(rel)

    # Dossier de premier niveau hors structure (`repo_map["roots"]`) : SSI repo_map est
    # un dict exploitable — sinon liste vide, comportement inchangé (rétro-compatibilité
    # de signature pour tout appelant existant qui ne passe pas ce paramètre).
    #
    # RÈGLE GÉNÉRALE (correction 2026-07-28, snake) : un dossier de premier niveau est
    # AUSSI légal quand il préfixe un gabarit du `mapping` de repo_map, même hors des
    # `roots` — ex. `godot.project_tests: "tests/{id}"` autorise "tests" par
    # construction (check_placement l'accepte déjà via ce même gabarit ; check_index le
    # rejetait faute de le lire, deux oracles du même standard en contradiction sur un
    # dossier autorisé). Dérivé du premier segment de chemin de chaque gabarit qui n'est
    # PAS lui-même `{id}` (un gabarit-artefact-racine comme `godot.project_root: "{id}"`
    # ne déclare aucun dossier — l'identifiant EST le nom du fichier, à la racine) :
    # aucune liste de catégories codée en dur, toute future catégorie hors-roots marche
    # sans toucher ce code.
    dossiers_hors_structure: list[str] = []
    if isinstance(repo_map, dict) and root.exists() and root.is_dir():
        roots_map = repo_map.get("roots")
        allowed_top: set[str] = set()
        if isinstance(roots_map, dict):
            for v in roots_map.values():
                if isinstance(v, str) and v.strip():
                    allowed_top.add(v.strip().replace("\\", "/").rstrip("/"))
        mapping = repo_map.get("mapping")
        if isinstance(mapping, dict):
            for tmpl in mapping.values():
                if not (isinstance(tmpl, str) and tmpl.strip()):
                    continue
                first_segment = tmpl.strip().replace("\\", "/").split("/", 1)[0]
                if first_segment and "{" not in first_segment:
                    allowed_top.add(first_segment)
        for child in sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name):
            # Même exemption que pour les orphelins : un dossier d'outillage régénéré
            # par la MESURE (`.godot` recréé par chaque lancement Godot du gate mutation)
            # n'est pas une dérive de structure du jeu. Cf. `_is_artefact_outil`.
            if _is_artefact_outil(child.name):
                continue
            if child.name not in allowed_top:
                dossiers_hors_structure.append(child.name)

    passed = not (
        fichiers_manquants
        or dossiers_manquants
        or orphelins
        or dossiers_orphelins
        or dossiers_hors_structure
    )
    return {
        "passed": passed,
        "fichiers_manquants": fichiers_manquants,
        "dossiers_manquants": dossiers_manquants,
        "orphelins": orphelins,
        "dossiers_orphelins": dossiers_orphelins,
        "dossiers_hors_structure": dossiers_hors_structure,
    }


# --------------------------------------------------------------------------------------
# 6. check_collisions — SCHEMA.md §4.5 + capabilities.yaml : audit du registre de
#    capacités, arithmétique (pas de juge LLM sur la similarité sémantique).
# --------------------------------------------------------------------------------------


def check_collisions(
    wiremap: dict, capabilities: dict, factory_capabilities: dict | None = None
) -> dict:
    """Vérifie les registres de capacités contre la wiremap.

    DEUX REGISTRES, UN SEUL VOCABULAIRE (ratifié Pierre 2026-08-10) :
    `capabilities.yaml` porte les capacités du JEU, `factory_capabilities.yaml` les
    préoccupations d'USINE (sondes, harnais de preuve, bot de solvabilité). La
    séparation est de GOUVERNANCE, jamais de sévérité : les règles structurelles
    ci-dessous s'appliquent à l'union des deux, et un identifiant absent des deux
    reste `identifiants_inconnus`. `factory_capabilities` est optionnel — un appelant
    qui ne le passe pas retrouve exactement le comportement d'avant (rétro-compatible).

    Un même id présent dans les deux registres est un défaut de gouvernance (on ne
    saurait plus qui le ratifie) : signalé en `identifiants_ambigus`, jamais résolu
    silencieusement par une priorité arbitraire.

    - tout identifiant de `provides`/`requires` doit exister dans l'un des registres
      (pas de nom libre) -> sinon `identifiants_inconnus`.
    - deux lignes avec le même `provides` sur une capacité `single_owner: true` -> collision.
    - un `requires` sans aucun fournisseur -> trou.
    - deux lignes `owner: true` sur la même capacité -> double propriétaire.
    - plusieurs lignes fournissant (écrivant) la même capacité sans qu'AUCUNE d'entre
      elles ne déclare `write_order` -> ordre implicite (incident réel : compteur global
      cassant le déterminisme du replay).

    Retourne {passed, identifiants_inconnus[], collisions[], trous[], doubles_proprietaires[],
    ordre_implicite[]}. Jamais d'exception sur entrée malformée.
    """
    empty = {
        "identifiants_inconnus": [],
        "identifiants_ambigus": [],
        "capacites_usine_utilisees": [],
        "collisions": [],
        "trous": [],
        "doubles_proprietaires": [],
        "ordre_implicite": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }

    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []

    def _collect(reg: object, key: str) -> dict[str, dict]:
        """Entrées `{id: def}` d'un registre. Entrée malformée = registre vide, jamais
        une exception (même discipline que le reste du module)."""
        out: dict[str, dict] = {}
        if isinstance(reg, dict) and isinstance(reg.get(key), list):
            for c in reg[key]:
                if isinstance(c, dict) and isinstance(c.get("id"), str):
                    out[c["id"]] = c
        return out

    game_defs = _collect(capabilities, "capabilities")
    factory_defs = _collect(factory_capabilities, "factory_capabilities")

    # Un id déclaré des deux côtés : personne ne sait plus qui le ratifie. Signalé,
    # jamais arbitré en silence — il reste connu (donc pas « inconnu »), mais le pas
    # échoue tant que la gouvernance n'est pas tranchée.
    identifiants_ambigus = sorted(set(game_defs) & set(factory_defs))

    cap_defs: dict[str, dict] = {**factory_defs, **game_defs}
    cap_ids = set(cap_defs.keys())
    factory_ids = set(factory_defs)
    single_owner_ids = {cid for cid, c in cap_defs.items() if c.get("single_owner") is True}

    identifiants_inconnus: list[str] = []
    providers: dict[str, list[str]] = {}
    owners: dict[str, list[str]] = {}
    requirers: dict[str, list[str]] = {}
    write_orders: dict[str, list[bool]] = {}

    for line in lines:
        if not isinstance(line, dict):
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"

        provides = line.get("provides")
        provides = [p for p in provides if isinstance(p, str)] if isinstance(provides, list) else []
        requires = line.get("requires")
        requires = [r for r in requires if isinstance(r, str)] if isinstance(requires, list) else []
        owner_flag = line.get("owner") is True
        write_order = line.get("write_order")
        has_write_order = write_order is not None and str(write_order).strip() != ""

        for cap in provides:
            if cap not in cap_ids:
                identifiants_inconnus.append(f"{lid}:{cap}")
                continue
            providers.setdefault(cap, []).append(lid)
            write_orders.setdefault(cap, []).append(has_write_order)
            if owner_flag:
                owners.setdefault(cap, []).append(lid)

        for cap in requires:
            if cap not in cap_ids:
                identifiants_inconnus.append(f"{lid}:{cap}")
                continue
            requirers.setdefault(cap, []).append(lid)

    collisions = sorted(
        cap for cap, provs in providers.items() if cap in single_owner_ids and len(provs) > 1
    )
    trous = sorted(cap for cap in requirers if cap not in providers)
    doubles_proprietaires = sorted(cap for cap, own in owners.items() if len(own) > 1)
    ordre_implicite = sorted(
        cap
        for cap, provs in providers.items()
        if len(provs) > 1 and not all(write_orders.get(cap, []))
    )

    # Visibilité : quelles capacités d'USINE ce jeu emploie réellement. Informatif —
    # n'entre PAS dans `passed` (une sonde déclarée n'est pas un défaut, c'est le point).
    capacites_usine_utilisees = sorted(
        (set(providers) | set(requirers)) & factory_ids
    )

    passed = not (
        identifiants_inconnus
        or identifiants_ambigus
        or collisions
        or trous
        or doubles_proprietaires
        or ordre_implicite
    )
    return {
        "passed": passed,
        "identifiants_inconnus": sorted(set(identifiants_inconnus)),
        "identifiants_ambigus": identifiants_ambigus,
        "capacites_usine_utilisees": capacites_usine_utilisees,
        "collisions": collisions,
        "trous": trous,
        "doubles_proprietaires": doubles_proprietaires,
        "ordre_implicite": ordre_implicite,
    }


# --------------------------------------------------------------------------------------
# 7. check_observable_coverage — R1 (contrat r1-preuves-boucle-mecaniques.yaml,
#    2026-07-27) : toute ligne `observable_by_player: true` doit NOMMER, via un nouveau
#    champ `observable_proof`, le volet d'oracle produit qui la prouve. Ce volet doit
#    EXISTER dans le reçu fourni par l'appelant ET son résultat ne doit être ni
#    NOT_MEASURED ni en échec — sinon la ligne reste NON COUVERTE.
#
#    Vocabulaire REPRIS du patron Art Bible (`check_artbible.mjs`, seul patron de
#    couverture éprouvé du studio) : `FAIL` = entrée malformée (wiremap/reçu du
#    mauvais type) · `BLOCKED` = bien formé mais au moins une ligne observable non
#    couverte · `OK` = conforme et intégralement couvert. Ne juge JAMAIS le fond de la
#    preuve (ce serait un jugement sémantique, hors de portée d'un oracle déterministe) —
#    seulement sa PRÉSENCE, son EXISTENCE dans le reçu, et son statut mesuré.
#
#    ADVISORY (garde-fou 6 du contrat) : ce volet est porté dans le reçu de
#    `s10s-oracle-standard` (driver.py::_run_standard_oracle) mais ne gate JAMAIS le
#    statut du pas — sa promotion en gate dur est une décision Pierre distincte.
# --------------------------------------------------------------------------------------


def _volet_status(volet: dict) -> str:
    """Statut homogène `OK`|`FAIL`|`NOT_MEASURED` d'un volet de reçu produit, quelle que
    soit sa forme concrète — `product_oracle.py` expose deux formes différentes :
    `visual_capture` porte un `status` explicite ∈ {OK, FAIL, NOT_MEASURED} ;
    `browser_import_safety`/`auto_session` portent `checked` (mesuré ou non) + `passed`.
    Une entrée qui n'est pas un mapping, ou qui ne porte aucun de ces indices connus,
    retourne `NOT_MEASURED` — absence d'information, jamais un vert par défaut (même
    discipline que `NOT_MEASURED != OK`, invariant global ratifié Pierre)."""
    if not isinstance(volet, dict):
        return "NOT_MEASURED"
    if "status" in volet:
        if volet.get("status") == "NOT_MEASURED":
            return "NOT_MEASURED"
        return "OK" if volet.get("status") == "OK" and volet.get("passed") is True else "FAIL"
    if "checked" in volet:
        if volet.get("checked") is not True:
            return "NOT_MEASURED"
        return "OK" if volet.get("passed") is True else "FAIL"
    if "passed" in volet:
        return "OK" if volet.get("passed") is True else "FAIL"
    return "NOT_MEASURED"


def check_observable_coverage(wiremap: dict, oracle_receipt: dict) -> dict:
    """Vérifie que chaque ligne `observable_by_player: true` de `wiremap` nomme, via
    `observable_proof`, un volet réellement présent et mesuré-vert dans `oracle_receipt`
    (un mapping plat `{nom_volet: résultat}` — typiquement les volets de
    `product_oracle.run_product_oracle`, portés au reçu de s10a).

    GARDE DE TYPE (ratifiée Pierre 2026-07-28, faux vert mesuré sur Snake) —
    `observable_by_player` n'a que 3 valeurs LÉGALES : le booléen `True`, le booléen
    `False`, ou l'absence du champ (`None`). Toute autre valeur (chaîne, nombre,
    dict, liste...) est une ligne MALFORMÉE, nommée dans `observable_malformes` —
    jamais un simple `continue` silencieux : avant cette garde, une phrase de
    justification à la place du booléen attendu se comportait comme `!= True`, donc
    ignorée comme "non observable", et un wiremap intégralement malformé (44/44
    lignes) rendait l'oracle vert par vacuité (rien à vérifier). De même, quand la
    ligne EST observable (`True`), `observable_proof` doit être une chaîne non vide
    qui NOMME un volet (identifiant court, sans espace) — pas une phrase de méthode.
    Critère mécanique retenu : présence d'un caractère d'espace. Tous les noms de
    volet réels du studio sont en snake_case sans espace (`auto_session`,
    `restart_offer_wiring`...) ; une phrase française porte presque toujours un
    espace. Limite documentée : un futur nom de volet légitime à espaces serait à
    tort rejeté ici — aucun volet actuel n'en a besoin, donc le critère tient tant
    que cette convention de nommage est respectée.

    Trois façons pour une ligne observable bien typée de rester NON COUVERTE :
    - `observable_proof` absent, vide, ou pas une chaîne -> ligne sans preuve nommée.
    - `observable_proof` nommé mais absent de `oracle_receipt` (ou pas un mapping) ->
      volet inconnu du reçu.
    - volet présent mais `NOT_MEASURED` (`_volet_status`) -> non mesuré.
    - volet présent, mesuré, mais en échec (`_volet_status` == "FAIL") -> preuve rouge.

    Retourne {passed, verdict, observable_malformes[], lignes_sans_preuve[],
    volets_absents[], volets_non_mesures[], volets_en_echec[], couvertes[]}. Jamais
    d'exception sur entrée malformée (même discipline que les 6 autres oracles de ce
    module) : `wiremap` qui n'est pas un mapping -> `FAIL` motivé ; `oracle_receipt`
    qui n'est pas un mapping est traité comme vide (aucun volet disponible), jamais
    une exception — un reçu absent est un fait mesurable (BLOCKED), pas une erreur
    de ce contrôle. Un `observable_malformes` non vide rend le verdict `FAIL` (une
    carte mal typée est un défaut de contenu, priorité sur un simple `BLOCKED` de
    couverture manquante — même arbitrage que `citations_non_resolues` dans
    `check_genre_coverage`)."""
    empty = {
        "observable_malformes": [],
        "lignes_sans_preuve": [],
        "volets_absents": [],
        "volets_non_mesures": [],
        "volets_en_echec": [],
        "couvertes": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "verdict": "FAIL",
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }

    receipt = oracle_receipt if isinstance(oracle_receipt, dict) else {}
    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []

    observable_malformes: list[dict] = []
    lignes_sans_preuve: list[str] = []
    volets_absents: list[str] = []
    volets_non_mesures: list[str] = []
    volets_en_echec: list[str] = []
    couvertes: list[str] = []

    for line in lines:
        if not isinstance(line, dict):
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"
        obs = line.get("observable_by_player")

        # Garde de type : True, False, absent (None) sont légaux ; tout le reste
        # (str, int, dict, liste...) est rapporté, jamais sauté en silence.
        if obs is not None and obs is not True and obs is not False:
            observable_malformes.append({
                "id": lid,
                "champ": "observable_by_player",
                "type_recu": type(obs).__name__,
            })
            continue

        if obs is not True:
            continue

        proof_name = line.get("observable_proof")
        if not (isinstance(proof_name, str) and proof_name.strip()):
            lignes_sans_preuve.append(lid)
            continue
        proof_name = proof_name.strip()

        if any(ch.isspace() for ch in proof_name):
            observable_malformes.append({
                "id": lid,
                "champ": "observable_proof",
                "type_recu": "str_avec_espaces",
            })
            continue

        volet = receipt.get(proof_name)
        if not isinstance(volet, dict):
            volets_absents.append(f"{lid}:{proof_name}")
            continue
        status = _volet_status(volet)
        if status == "NOT_MEASURED":
            volets_non_mesures.append(f"{lid}:{proof_name}")
        elif status == "FAIL":
            volets_en_echec.append(f"{lid}:{proof_name}")
        else:
            couvertes.append(f"{lid}:{proof_name}")

    malforme = bool(observable_malformes)
    non_couvert = bool(
        lignes_sans_preuve or volets_absents or volets_non_mesures or volets_en_echec
    )
    if malforme:
        verdict = "FAIL"
    elif non_couvert:
        verdict = "BLOCKED"
    else:
        verdict = "OK"
    # TROIS ETATS DISTINCTS (2026-08-17). Le `non_couvert` ci-dessus reunit par un OU quatre
    # categories que cette fonction a pourtant pris soin de SEPARER : un volet honnetement NON
    # MESURE produisait le meme `passed: False` qu'un volet EN ECHEC, et tout consommateur qui
    # ne lit que `passed` heritait de la confusion. Cas reel : `tetris` (recu c19add3) est
    # BLOCKED avec les TROIS listes d'echec VIDES — seul `core.render` est non mesure, via le
    # marqueur `requires_gpu_window` qu'il porte LUI-MEME.
    #
    # PATRON REPRIS de la facette `budget` (`driver.py`, meme fonction de gate) : elle distingue
    # deja `measured` de `passed`, avec la regle « un volet demontre en violation rend le pas
    # FAIL MEME si une autre part n'a pas pu etre mesuree ; BLOCKED seulement si rien n'est
    # demontre ET qu'une part est non mesurable ». Rien d'invente ici, le patron est etendu.
    #
    # `passed` et `verdict` sont INCHANGES : ce lot AJOUTE de quoi decider, il ne redefinit
    # rien. Cabler ces champs dans `_CORE_FACETS` est une decision DISTINCTE (E), non prise ici.
    violation = bool(malforme or lignes_sans_preuve or volets_absents or volets_en_echec)
    return {
        "passed": verdict == "OK",
        # Une part de la couverture a-t-elle ete IMPOSSIBLE a mesurer ? (preuve impossible)
        "measured": not bool(volets_non_mesures),
        # Un defaut a-t-il ete DEMONTRE ? (preuve negative) — jamais confondu avec le precedent.
        "violation": violation,
        "verdict": verdict,
        "observable_malformes": observable_malformes,
        "lignes_sans_preuve": lignes_sans_preuve,
        "volets_absents": volets_absents,
        "volets_non_mesures": volets_non_mesures,
        "volets_en_echec": volets_en_echec,
        "couvertes": couvertes,
    }


# --------------------------------------------------------------------------------------
# 8. check_genre_coverage — R1 : chaque règle de la Genre Bible (`genre_rules[].id`)
#    doit être soit CITÉE par au moins une ligne de wiremap (champ `genre_refs`, la
#    citation devant RÉSOUDRE vers un `id` réellement présent dans `genre_rules`), soit
#    REFUSÉE explicitement (`wiremap["genre_refusals"]`, entrée {rule_id, reason} avec
#    une raison non vide). Même vocabulaire que `check_observable_coverage`.
# --------------------------------------------------------------------------------------


def check_genre_coverage(wiremap: dict, genre_bible: dict) -> dict:
    """Vérifie la couverture règle-de-genre <-> ligne-de-wiremap (patron Art Bible,
    `check_artbible.mjs::checkCoverage`, transposé à la Genre Bible).

    - `genre_bible["genre_rules"]` doit être une liste ; sinon `FAIL` (bible
      illisible pour ce contrôle). Une liste vide est un cas trivial valide : aucune
      règle à couvrir, `OK` par vacuité.
    - chaque règle (entrée `{id: str, ...}`) est couverte si son `id` apparaît dans
      `genre_refs` d'au moins une ligne du wiremap (`citée`) OU dans
      `wiremap["genre_refusals"]` avec une `reason` non vide (`refusée`).
    - une règle applicable ni citée ni refusée -> `regles_non_couvertes` -> `BLOCKED`
      (bien formé, couverture manquante).
    - une citation (`genre_refs`) qui ne RÉSOUT vers AUCUN `id` de `genre_rules` ->
      `citations_non_resolues` -> `FAIL` (une citation cassée est une erreur de
      contenu, pas une simple absence de preuve — priorité sur `BLOCKED`, même
      arbitrage que `_run_standard_oracle` : une preuve d'échec l'emporte sur une
      absence de preuve).

    Retourne {passed, verdict, regles_non_couvertes[], citations_non_resolues[],
    citees[], refusees[]}. Jamais d'exception sur entrée malformée."""
    empty = {
        "regles_non_couvertes": [],
        "citations_non_resolues": [],
        "citees": [],
        "refusees": [],
    }
    if not isinstance(wiremap, dict):
        return {
            "passed": False,
            "verdict": "FAIL",
            "raison": f"wiremap n'est pas un mapping (reçu {type(wiremap).__name__})",
            **empty,
        }
    if not isinstance(genre_bible, dict):
        return {
            "passed": False,
            "verdict": "FAIL",
            "raison": f"genre_bible n'est pas un mapping (reçu {type(genre_bible).__name__})",
            **empty,
        }

    rules_raw = genre_bible.get("genre_rules")
    if not isinstance(rules_raw, list):
        return {
            "passed": False,
            "verdict": "FAIL",
            "raison": "genre_bible.genre_rules absent ou n'est pas une liste",
            **empty,
        }
    rule_ids = {
        r["id"] for r in rules_raw
        if isinstance(r, dict) and isinstance(r.get("id"), str) and r["id"].strip()
    }

    lines_raw = wiremap.get("lines")
    lines = lines_raw if isinstance(lines_raw, list) else []

    citees: list[str] = []
    citations_non_resolues: list[str] = []
    cited_ids: set[str] = set()
    for line in lines:
        if not isinstance(line, dict):
            continue
        lid = line.get("id") if isinstance(line.get("id"), str) else "<sans-id>"
        refs_raw = line.get("genre_refs")
        refs = refs_raw if isinstance(refs_raw, list) else []
        for ref in refs:
            if not (isinstance(ref, str) and ref.strip()):
                continue
            if ref in rule_ids:
                citees.append(f"{lid}:{ref}")
                cited_ids.add(ref)
            else:
                citations_non_resolues.append(f"{lid}:{ref}")

    refusals_raw = wiremap.get("genre_refusals")
    refusals = refusals_raw if isinstance(refusals_raw, list) else []
    refused_ids: set[str] = set()
    for r in refusals:
        if not isinstance(r, dict):
            continue
        rid = r.get("rule_id")
        reason = r.get("reason")
        if (
            isinstance(rid, str) and rid.strip()
            and isinstance(reason, str) and reason.strip()
        ):
            refused_ids.add(rid)

    regles_non_couvertes = sorted(
        rid for rid in rule_ids if rid not in cited_ids and rid not in refused_ids
    )

    if citations_non_resolues:
        verdict = "FAIL"
    elif regles_non_couvertes:
        verdict = "BLOCKED"
    else:
        verdict = "OK"

    citations_revendiquees = len(citees) + len(citations_non_resolues)
    citations_resolues = len(citees)
    taux_resolution = (
        round(citations_resolues / citations_revendiquees, 4)
        if citations_revendiquees > 0
        else None
    )

    return {
        "passed": verdict == "OK",
        "verdict": verdict,
        "regles_non_couvertes": regles_non_couvertes,
        "citations_non_resolues": sorted(citations_non_resolues),
        "citees": sorted(citees),
        "refusees": sorted(refused_ids),
        "citations_revendiquees": citations_revendiquees,
        "citations_resolues": citations_resolues,
        "taux_resolution": taux_resolution,
    }


def check_gpu_window_directive(oracle_dir: Path | str) -> dict:
    """Oracle 9 (lot 1 ADR-003, P0-4) — la directive de mode GPU est un CHAMP
    VÉRIFIÉ, plus jamais une prose de commentaire.

    Contexte mesuré (breakout_v2, 2026-08-15) : le routage d'exécution des volets
    pixel repose sur la DIRECTIVE STATIQUE ``forge:run_mode = gpu_window``
    (`product_oracle_godot._gpu_window_declared`, seule autorité de routage) ;
    or les `.gd` de breakout_v2 déclaraient l'exigence GPU en PROSE seule
    (« Fenetre GPU reelle exigee (charter) », core_render_frame.gd:4) — le volet
    partait en `--headless` et rendait un ROUGE FABRIQUÉ (« --headless rend une
    texture nulle »). Cas d'école « aucune décision dans un commentaire »
    (ratifié Pierre 2026-07-23) : toute donnée qui influence un comportement doit
    avoir un champ structuré validé.

    Règle : un `.gd` du répertoire d'oracles dont un COMMENTAIRE évoque
    l'exigence de fenêtre GPU (« fenêtre GPU », « rendering-driver »,
    « gpu window/gpu_window ») sans porter la directive structurée est EN DÉFAUT.

    RAFFINEMENT 2026-08-16 (GO Pierre) — TROIS états, plus deux. Un oracle doit
    discriminer FAIL, PASS et NOT_MEASURED quand ces états ont une signification
    opérationnelle différente :

        preuve GPU requise
            -> directive `forge:run_mode = gpu_window`   => routé en fenêtre : OK
            -> marqueur `requires_gpu_window` (payload)  => NOT_MEASURED motivé : OK
            -> ni l'un ni l'autre, prose seule           => DÉFAUT (BLOCKED)

    La version d'origine confondait les deux derniers : elle attrapait « exigence non
    satisfaite » ET « preuve volontairement non mesurée, avec raison structurée ».
    Défaut MESURÉ le 2026-08-16 : `GAMES/tetris/07_TESTS/oracle/core_render.gd` —
    SEUL volet du dépôt à porter le marqueur, avec une justification exemplaire — était
    signalé en défaut. Faux positif de l'oracle, pas défaut du produit. Motif
    `forge.oracle_fail_vs_not_measured_marker` : « non mesurable » ne se maquille ni en
    échec ni en succès. AUCUNE clé n'est inventée ici : `_GPU_WINDOW_MARKER_KEY` est
    déjà la clé par laquelle le collecteur rend NOT_MEASURED.
    Verdict ``BLOCKED``, jamais ``FAIL`` : c'est l'INSTRUMENT (la déclaration)
    qu'il faut réparer, pas le jeu — les confondre enverrait le builder réparer
    la mauvaise chose (doctrine FAIL vs BLOCKED du driver).

    Ne lève jamais : répertoire absent => OK (rien à vérifier, on ne fabrique pas
    une exigence) ; fichier illisible => listé `illisibles`, jamais un défaut.
    """
    import re as _re

    # SOURCE UNIQUE de la directive : la regex du routeur lui-même — si le format
    # évolue là-bas, ce contrôle suit, jamais une seconde vérité locale.
    from forge.product_oracle_godot import (
        _GPU_WINDOW_DIRECTIVE, _GPU_WINDOW_MARKER_KEY, _ORACLE_MARKER)

    prose_hint = _re.compile(
        r"fen[eê]tre\s+gpu|rendering[-_\s]driver|gpu[\s_]window", _re.IGNORECASE)
    # RENONCEMENT STRUCTURÉ (2026-08-16) : `requires_gpu_window` est la clé de marqueur
    # PAR LAQUELLE UN VOLET DÉCLARE LUI-MÊME n'avoir pas pu être mesuré — le collecteur
    # rend alors NOT_MEASURED motivé (product_oracle_godot._GPU_WINDOW_MARKER_KEY).
    # Cherchée dans la SOURCE, comme la directive : le volet l'écrit dans le payload
    # qu'il émet, donc la chaîne est présente dans son texte. Même autorité que le
    # routeur, aucune clé inventée ici.
    renoncement = _re.compile(_re.escape(_GPU_WINDOW_MARKER_KEY), _re.IGNORECASE)

    base = Path(oracle_dir)
    result: dict[str, Any] = {
        "passed": True, "verdict": "OK", "fichiers_examines": 0,
        "fichiers_avec_directive": 0, "fichiers_not_measured": [],
        "sous_modules_ignores": [],
        "fichiers_en_defaut": [], "illisibles": [], "raisons": [],
    }
    if not base.is_dir():
        result["raisons"].append(f"répertoire d'oracles absent ({base}) — rien à vérifier")
        return result

    for path in sorted(base.glob("*.gd")):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            result["illisibles"].append(path.name)
            continue
        # PÉRIMÈTRE (2026-08-16) : SEULS les fichiers que le collecteur LANCE. Sa
        # condition de découverte est la présence du marqueur `FORGE_ORACLE`
        # (product_oracle_godot.discover_oracle_files) ; un `.gd` sans ce marqueur est un
        # SOUS-MODULE (`extends RefCounted`, aucun payload émis), jamais routé — lui
        # imposer une directive de routage n'a aucune réalité d'exécution.
        # Défaut MESURÉ le 2026-08-16 : pacman portait 6 « défauts » sur 104 fichiers dont
        # ZÉRO n'est un volet réel, et 4 des 7 directives posées en e02b010 sont inertes
        # pour la même raison. Même autorité que le routeur, encore : on ne réimplémente
        # pas la règle de découverte, on l'importe.
        if _ORACLE_MARKER not in text:
            result["sous_modules_ignores"].append(path.name)
            continue
        result["fichiers_examines"] += 1
        if _GPU_WINDOW_DIRECTIVE.search(text):
            result["fichiers_avec_directive"] += 1
            continue
        if renoncement.search(text):
            # Le volet DÉCLARE, en champ structuré, qu'il ne mesure pas la preuve pixel.
            # Ce n'est ni un défaut ni une réussite : c'est NOT_MEASURED motivé, un état
            # opérationnel DISTINCT des deux autres. Le confondre avec une exigence non
            # satisfaite recalerait le volet le plus rigoureux du dépôt
            # (GAMES/tetris/07_TESTS/oracle/core_render.gd, seul émetteur mesuré le
            # 2026-08-16) et pousserait à lui poser une directive qui CASSERAIT son
            # contrat — cf. pacman/v2_core_render, dont une assertion exige
            # explicitement « aucune capture mesurée sans fenêtre GPU ».
            result["fichiers_not_measured"].append(path.name)
            continue
        commentaires = "\n".join(
            line for line in text.splitlines() if line.lstrip().startswith("#"))
        if prose_hint.search(commentaires):
            result["fichiers_en_defaut"].append(path.name)

    if result["fichiers_en_defaut"]:
        result["passed"] = False
        result["verdict"] = "BLOCKED"
        result["raisons"].append(
            "exigence GPU déclarée en prose de commentaire sans directive "
            "structurée 'forge:run_mode = gpu_window' — le volet serait routé "
            "--headless et rendrait un rouge fabriqué : "
            + ", ".join(result["fichiers_en_defaut"])
        )
    return result
