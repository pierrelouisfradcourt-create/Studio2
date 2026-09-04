"""Dispatch gouverné de la chaîne Forge — la porte unique.

`prepare_dispatch(etape)` charge le contrat de l'étape, le valide (refuse si
incomplet), fabrique le payload borné et APPEND un enregistrement d'audit. Il ne
spawn AUCUN agent : l'orchestrateur (le skill /forge) réalise le spawn réel avec
le payload retourné. Le contrat reste la porte de contrôle, chaque dispatch est
auditable (connecteur 2 léger + auditabilité connecteur 3).

Enforcement doctrinal (ADR-002 gate 2) : aucun sous-agent Forge ne doit être
lancé sans passer par cette fonction. Le durcissement « hook » est ultérieur.
"""
from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from forge.contract import (
    REPO_ROOT,
    ContractIncomplete,
    DispatchPayload,
    build_dispatch_payload,
    load_contract,
)

# La couche « fichier d'audit » (événements, enregistrement signé, écriture, lecture)
# vit dans `forge.audit`, module STDLIB-ONLY. Raison : le garde de spawn
# (`forge.hook_guard`) est fail-CLOSED en périmètre Forge — s'il ne peut pas s'importer,
# il refuse TOUT spawn Forge. Il ne doit donc pas traverser ce module-ci, qui dépend de
# `forge.contract` -> `yaml` (absent hors venv, c.-à-d. dans les worktrees).
# Les noms ci-dessous sont RÉ-EXPORTÉS : `from forge.dispatch import DEFAULT_AUDIT /
# EVENT_* / verify_audit_line / append_spawn_event / spawn_proof / ...` reste valide
# (driver.py et les tests existants en dépendent), avec exactement le même objet.
from forge.audit import (  # noqa: F401 — ré-exports d'API historique, usage indirect
    DEFAULT_AUDIT,
    EVENT_AUTHORIZED,
    EVENT_EXECUTED,
    EVENT_PREPARED,
    SPAWN_EVENTS,
    DispatchRecord,
    _append_audit,
    _iter_audit_records,
    append_spawn_event,
    sign_audit_record,
    spawn_proof,
    verify_audit_line,
)

logger = logging.getLogger(__name__)

# Ordre logique de la chaîne (les 13 étapes-agents qui ont un contrat).
#
# ⚠ L'ORDRE NE SUIT PLUS LA NUMÉROTATION : s2-worldscan s'exécute AVANT s1-prisme
# (FORGE_PRISME_V2, ratifié Pierre 2026-08-03). Les NOMS d'étape sont conservés
# volontairement : ils apparaissent dans les contrats, les tâches par défaut, les
# state.json archivés et les traces Observer — les renommer rendrait tout
# l'historique des runs illisible. Un nom qui ne reflète plus sa position est un
# désagrément ; un historique qu'on ne peut plus relire est une perte.
#
# POURQUOI l'inversion (cause racine mesurée le 2026-08-03) : le Prisme tournait
# en position 2/14, AVANT toute connaissance externe, avec pour seul
# `mandatory_read` le charter — donc structurellement aveugle. Mesure : 0
# occurrence de menu/pause/audio/onboarding dans son artefact sur le run témoin
# Tetris. Son silence n'était pas une faute d'agent, c'était une conséquence de sa
# position. Le Prisme ne peut transformer la connaissance externe en exigences
# internes que s'il la reçoit d'abord.
ORDER = [
    "s0-contrat",
    "s2-worldscan",
    "s1-prisme",
    "s3-decompo",
    "s4-archi",
    "s5-wiremap",
    "s6-redteam-plan",
    "s9-build",
    "s10a-oracle-code",
    "s10b-oracle-archi",
    "s10c-oracle-wiremap",
    "s11-redteam-code",
    "s12-verdict",
]

# Étapes déterministes (non-LLM) : exécutées par oracle, pas par un agent LLM.
# Invariant couvert par un test existant (test_dispatch.test_order_covers_the_agent_steps) :
# DETERMINISTIC ⊆ ORDER. Reste vrai ICI — les 4 étapes ci-dessous sont toutes des membres
# canoniques de "full". Une étape déterministe qui vit HORS ORDER (profil dédié) va dans
# DEDICATED_DETERMINISTIC_STEPS ci-dessous, PAS ici : mélanger casserait à la fois cet
# invariant et `plan_chain(profile="full")` (qui n'a que les étapes de ORDER).
DETERMINISTIC = ("s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap", "s12-verdict")

# Étapes déterministes qui vivent HORS de ORDER, jumelles de DEDICATED_PROFILE_STEPS mais
# pour la catégorie « oracle non-LLM » plutôt que « agent LLM ». s10s-oracle-standard (les
# six oracles du STANDARD, forge/standard_oracles.py) n'est dispatchable que via le
# profil dédié `standard` (cf. DEDICATED_PROFILE_STEPS et PROFILES["standard"] plus bas) —
# jamais dans `full`. Séparée de DETERMINISTIC pour ne PAS casser l'invariant DETERMINISTIC
# ⊆ ORDER ci-dessus (contrat déjà vérifié par un test existant, non modifiable). Utiliser
# `is_deterministic_step(etape)` pour tester l'UNE ou l'AUTRE catégorie.
DEDICATED_DETERMINISTIC_STEPS = ("s10s-oracle-standard",)


def is_deterministic_step(etape: str) -> bool:
    """Vrai si `etape` est un oracle non-LLM — canonique (DETERMINISTIC, dans ORDER)
    OU dédié (DEDICATED_DETERMINISTIC_STEPS, hors ORDER, profil dédié uniquement)."""
    return etape in DETERMINISTIC or etape in DEDICATED_DETERMINISTIC_STEPS

# Étapes délibérément HORS de ORDER (la chaîne canonique greenfield "full") mais
# réellement contractualisées, prouvées en vivo, et dispatchables via un profil
# DÉDIÉ — jamais silencieusement incluses dans "full". Une étape n'entre ici
# qu'après une preuve en vivo distincte (cf. FORGE_STATE_SNAPSHOT/notes du contrat) ;
# rester hors de ORDER est une décision de portée, pas un oubli. `s2.5-artbible`
# (Tier 3 #7, Art Director) : 6 runs réels (2 non-adversariaux + 4 adversariaux) +
# gate 4 Qwen + fix v0.1 + preuve v0.1 finale, cf. docs/forge/S2_5_ARTBIBLE_*.md.
# `s9-build-standard` / `s10s-oracle-standard` (curriculum de jeux, 2026-07-22) : la
# variante STANDARD contrat/repo/wiremap du build et de son oracle — dispatchable
# UNIQUEMENT via le profil dédié `standard`, jamais mêlée à "full" (le squelette gelé
# est un mode opératoire distinct du greenfield Prisme->WireMap classique).
# `s9-build-godot-standard` (curriculum de jeux, cible Godot ratifiée Pierre 2026-07-28) :
# jumeau Godot de s9-build-standard — dispatchable UNIQUEMENT via le profil dédié
# `standard_godot`, jamais mêlée à "full". `s9-build-godot` (étape 0, brique M01, contrat
# historique du 2026-07-21) reste HORS de tout profil : il n'appartient ni à ORDER, ni à
# DEDICATED_PROFILE_STEPS — c'est une trace figée, pas un builder de curriculum.
DEDICATED_PROFILE_STEPS = (
    "s2.5-artbible",
    "s9-build-standard",
    "s10s-oracle-standard",
    "s9-build-godot-standard",
    # §7.2 · s2.7-gm-worldscan (GO Pierre 2026-08-14) — World Scan du GAME MASTER :
    # mesure comparative du GENRE, distincte du World Scan artistique (s2-worldscan,
    # « quel monde ? »). Produit les 8 dimensions de calibration que le schéma de s2
    # ne structure PAS (combat, progression, economy, rng, rarity, bonus, metagame,
    # construction) ; les 3 autres — modes, solvabilité, boucles — vivent déjà dans
    # worldscan.json et ne sont jamais redites. Cf. FORGE_PIPELINE_TARGET_V1.md §1.1.
    # HORS de ORDER, comme les quatre ci-dessus : jamais mêlée silencieusement à
    # `full`, dispatchable uniquement par son profil dédié.
    "s2.7-gm-worldscan",
    # §7.2 · s2.6-story-bible (GO Pierre 2026-08-14, strictement cette station) —
    # Story Bible de l'AGENT ARTISTIQUE, ancree dans worldscan.json + charter, role
    # art_director. La regle qui la definit : elle n'INVENTE pas — chaque element cite
    # sa source, une section non ancrable se declare NOT_GROUNDED motivee. Hors ORDER
    # comme les cinq ci-dessus.
    "s2.6-story-bible",
    # Lot F (2026-08-23, boucle de complétion mutuelle Art <-> GM) — alias round 2 de
    # s2.5-artbible/s2.7-gm-worldscan (`<etape>-r2`, cf. forge.contract.base_step/
    # step_round). Membres RÉELS de PROFILES["full_godot_content"] (dispatch.py) : ils
    # doivent apparaître ici pour satisfaire le même invariant que les six entrées
    # ci-dessus — `test_profiles_are_subsets_of_order_or_explicitly_dedicated`
    # (test_dispatch.py) exige que TOUT id référencé par un profil soit dans ORDER OU
    # DEDICATED_PROFILE_STEPS, jamais un id « mystère ». Conséquence directe : ces deux
    # alias deviennent aussi des clés valides de `_VALID_TASK_STEPS`
    # (`run_real._VALID_TASK_STEPS = frozenset(ORDER) | frozenset(DEDICATED_PROFILE_
    # STEPS)`), ce qui débloque `EVIDENCE/runs/kitten_clicker/tasks.json` (non touché
    # par ce lot, mais qui cite déjà ces deux ids) sans y toucher. Jamais mêlés
    # silencieusement à `full` (comme les six entrées ci-dessus) — dispatchables
    # uniquement via leur base + le profil `full_godot_content`.
    "s2.5-artbible-r2",
    "s2.7-gm-worldscan-r2",
)


# Profils de chaîne — sous-ensembles de ORDER (ou de DEDICATED_PROFILE_STEPS ci-dessus)
# pour des usages plus courts que le greenfield complet. `patch` = un fix sur un projet
# existant (build -> oracle code -> red-team code -> verdict) : les oracles archi/
# wiremap n'y sont pas applicables et seront émis SKIPPED (reçu signé) au verdict.
# `review` = red-team d'un plan seul. `artbible` = Art Director seul (Tier 3 #7) : un
# profil dédié, PAS ajouté à `full` — décision explicite de portée (Pierre,
# 2026-07-14), suppose product_snapshot.md déjà produit (même convention que `review`
# qui suppose blueprint/wiremap déjà produits).
PROFILES = {
    "full": tuple(ORDER),
    "patch": ("s9-build", "s10a-oracle-code", "s11-redteam-code", "s12-verdict"),
    "review": ("s6-redteam-plan",),
    # micro : une tâche triviale (fonction pure, one-liner). Proportionnalité : pas
    # de red-team ni de design — build -> oracle code -> verdict. Évite la cérémonie
    # 13 étapes sur 78 lignes (finding red-team chesscolor). archi/wiremap = SKIPPED.
    "micro": ("s9-build", "s10a-oracle-code", "s12-verdict"),
    # proof_only : REMESURER SANS RECONSTRUIRE (GO Pierre 2026-08-17). Rafraichir un reçu
    # de preuve produit exigeait jusqu'ici `standard`/`standard_godot`/`full_godot`, tous
    # porteurs d'un BUILDER et d'une RED-TEAM : on reconstruisait le jeu — et on reecrivait
    # `GAMES/**` — pour remplacer un certificat. Ce profil decoupe les deux SEULES etapes
    # deterministes non-LLM de la chaine de preuve. Il n'invente aucune etape : c'est un
    # sous-ensemble strict de `standard`.
    #
    # LE COUPLE EST INDIVISIBLE. `s10s` ne PRODUIT pas le reçu produit, il le LIT dans le
    # detail de `s10a`. Le profil `oracle_only` (s10s seule) recalculerait donc
    # `observable_coverage` sur un reçu PERIME — un fichier date d'aujourd'hui derive de
    # mesures de juillet, exactement la fausse continuite ecartee par Pierre.
    #
    # PAS DE `s12-verdict` : ce profil REMESURE, il ne juge pas. Un `software_verdict` vient
    # UNIQUEMENT de reçus d'oracle verifies (CLAUDE.md:81) ; ce que produit `proof_only` est
    # une mesure contemporaine coherente, pas une preuve signee. Meme forme que `review`,
    # `artbible`, `gm_worldscan` : une tranche isolee sans verdict.
    #
    # TOPOLOGIE : `proof_only` est AUSSI inscrit dans `driver._STANDARD_TOPOLOGY_PROFILES`.
    # Sans cela il tomberait en branche LEGACY, dont l'effet est mesure (run snake-s9p,
    # 2026-07-28) : trois rouges d'INSTRUMENTATION — sur un profil fait pour en supprimer.
    "proof_only": ("s10a-oracle-code", "s10s-oracle-standard"),
    "artbible": ("s2.5-artbible",),
    # gm_worldscan : s2.7 SEULE, même forme que `artbible` (s2.5 seule) et `review`
    # (s6 seule) — une tranche isolée, pas de verdict signé (s12 n'y est pas : une
    # mesure de genre n'est ni un build ni une preuve de produit).
    #
    # CONSOMMATION AVAL : PASSIVE, déclarée et non masquée (GO Pierre 2026-08-14).
    # `gm_worldscan.json` est produit et validé par son oracle, mais AUCUNE étape ne
    # le lit — les stations aval (matrices de design, Grey Block) n'existent pas
    # encore. Aucun faux consommateur n'a été créé pour fermer la boucle
    # artificiellement : ce serait exactement le motif « producteur sans
    # consommateur » que §7.2 doit corriger, pas reproduire. Le câblage aval se fera
    # avec la première station consommatrice réelle.
    "gm_worldscan": ("s2.7-gm-worldscan",),
    # story_bible : s2.6 SEULE, meme forme que gm_worldscan/artbible/review. Pas de
    # verdict signe. CONSOMMATION AVAL : PASSIVE attendue — le consommateur
    # architectural (le GM) n'existe pas encore ; aucun faux consommateur.
    "story_bible": ("s2.6-story-bible",),
    # amont_narratif (GO Pierre 2026-08-14) — profil de COMPOSITION, seule mutation du
    # lot : aucun contrat, aucun oracle, aucune station neuve.
    #
    # POURQUOI : `s2.7` et `s2.6` étaient tous deux TESTED, mais leur surface
    # « injection amont avec fichiers PRÉSENTS » restait NOT_MEASURED — les deux runs
    # de preuve tournaient sur sondes neuves, sans worldscan ni charter. On avait donc
    # prouvé deux fois que les stations se comportent bien SANS entrées, et zéro fois
    # qu'elles savent en exploiter. Et le trou ne se referme pas seul : les profils
    # sont mono-station, et relancer un second profil sur le même projet ne produit
    # rien — `run()` court-circuite sur `run_status == DONE` (driver.py) et rend un
    # rapport idempotent. Il fallait donc une CHAÎNE, pas une reprise.
    #
    # Ce que ce profil doit démontrer, et qui n'est PAS « les deux étapes finissent
    # OK » : que l'information produite par s2-worldscan a réellement traversé la
    # frontière et MODIFIÉ la sortie de s2.6 — sections GROUNDED, `source`/`ref`
    # réels, `inferred` distingué. Une Story Bible encore vide malgré un worldscan
    # présent signerait une rupture de transmission, et ce serait le résultat.
    "amont_narratif": ("s2-worldscan", "s2.6-story-bible"),
    # amont_narratif_charte (GO Pierre 2026-08-14) — extension AMONT d'un cran, seule
    # mutation du lot. Le run amont_narratif a mesuré 2/8 GROUNDED et ses 6 refus
    # nommaient tous la même cause : le World Scan fonde des RÈGLES DE GENRE, pas un
    # monde de projet — « aucune faction DE CE PROJET n'est ancrée », « les seuls
    # protagonistes des entrées sont ceux des jeux observés ». Ce qui fonde un monde,
    # c'est l'INTENTION DE PROJET, portée par le charter.
    #
    # Prérequis leve par M4 (91f3a12) : avant lui, charter.yaml n'avait aucun
    # producteur — s0 aurait tourné, produit du YAML dans son texte, et rien sur le
    # disque ; s2.6 aurait reçu charter:false une troisième fois et l'expérience aurait
    # perdu sa variable.
    #
    # Expérience contrôlée, une variable structurelle ajoutée — MESURÉE :
    #   charter absent      ->  0/8 GROUNDED,  0 élément (story-probe-20260814)
    #   worldscan seul      ->  2/8 GROUNDED,  4 éléments (amont-narratif-20260814)
    #   charter + worldscan ->  7/8 GROUNDED, 26 éléments (charte2-20260814)
    # Marqueur décisif : 24 des 26 éléments citent `source: charter` — la seconde
    # source n'est pas seulement transmise, elle est EXPLOITÉE. Seul refus résiduel :
    # `chronology`, et il est juste — aucune temporalité n'était portée par l'entrée.
    "amont_narratif_charte": ("s0-contrat", "s2-worldscan", "s2.6-story-bible"),
    # oracle_only : s10s SEUL, sur un jeu DEJA CONSTRUIT (ratifie Pierre 2026-08-10).
    #
    # Cause mesuree : pacman V5 est VALIDATED mais n'est jamais passe par le driver
    # (aucun state.json dans ses 6 repertoires de run) — donc ses 53 identifiants de
    # capacite absents du registre n'ont JAMAIS ete proposes, la ou tetris en a propose
    # 42. Le producteur (`driver.py::_propose_capability_gaps`, l.2198) est correctement
    # cable ; c'est le JEU DE REFERENCE qui l'a contourne. Sans ce profil, capitaliser
    # le vocabulaire d'un jeu validé imposait de lui repasser un profil commencant par
    # `s9-build-*` — c'est-a-dire de RECONSTRUIRE par-dessus la seule reference validee
    # du studio pour la mesurer. Un jeu valide doit pouvoir devenir une source de
    # connaissance sans etre reconstruit.
    #
    # PORTEE STRICTEMENT LIMITEE (condition de la ratification) : une seule etape, aucun
    # build, aucune variante de pipeline. s10s ne fait que LIRE GAMES/<projet>/ et deposer
    # ses propositions (best-effort, cf. _propose_capability_gaps/_propose_bible_entries).
    # Meme forme que `review` (s6 seul) et `artbible` (s2.5 seul) : une tranche isolee.
    # PAS de verdict signe — s12 n'y est pas : une mesure de capitalisation n'est ni une
    # baseline ni un temoin, exactement la reserve deja posee sur `amont_only`.
    "oracle_only": ("s10s-oracle-standard",),
    # increment : un incrément sur un projet existant dont le corpus de design (bibles)
    # est déjà la source de vérité — saute s0/s1/s2 (charter/prisme/world scan, déjà
    # couverts) mais REFAIT archi/wiremap contrairement à `patch`, parce qu'un moteur
    # multi-incréments a justement le plus besoin de deps_interdites et de wiremap à
    # jour à chaque incrément (cf. FORGE_PLAN_PROPOSAL.md §5 R1, ratifié Pierre 2026-07-19).
    "increment": (
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # standard : curriculum de jeux (Pong -> ...) sur squelette gelé (forge/standard/).
    # Remplace s9-build par son jumeau STANDARD (s9-build-standard, hors ORDER par décision
    # explicite — cf. DEDICATED_PROFILE_STEPS) ; GARDE s10a-oracle-code (le gate mutation/
    # e2e/solvabilité générique reste applicable) et AJOUTE s10s-oracle-standard (les six
    # oracles du squelette, jumeau déterministe de s9-build-standard, également hors ORDER) ;
    # garde s11-redteam-code (advisory) et s12-verdict (agrégation signée) de la chaîne
    # canonique. Pas d'archi/wiremap génériques (s10b/s10c) : c'est s10s qui en tient lieu
    # pour cette variante — décision de portée, ratifiée Pierre 2026-07-22, PAS dans "full".
    "standard": (
        "s9-build-standard",
        "s10a-oracle-code",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # standard_godot : jumeau Godot de `standard` (cible Godot ratifiée Pierre 2026-07-28).
    # CE QUI CHANGE vs `standard` : s9-build-standard (web/JS) est remplacé par son jumeau
    # s9-build-godot-standard (GDScript, projet Godot, oracle headless) — hors ORDER par la
    # même décision de portée (cf. DEDICATED_PROFILE_STEPS). CE QUI NE CHANGE PAS : s10a-
    # oracle-code reste applicable (gate mutation/e2e/solvabilité générique, ici sur du
    # GDScript) ; s10s-oracle-standard porte toujours les six oracles du squelette gelé
    # (line_states, placement, collisions, index, contract_completeness, budget), agnostiques
    # du runtime du builder ; s11-redteam-code reste advisory ; s12-verdict reste
    # l'agrégation signée. Pas d'archi/wiremap génériques (s10b/s10c), exactement comme
    # `standard` — c'est s10s qui en tient lieu. `s9-build-godot` (étape 0, brique M01)
    # n'appartient à AUCUN profil, ni celui-ci ni "full" : trace historique intacte.
    "standard_godot": (
        "s9-build-godot-standard",
        "s10a-oracle-code",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # full_godot : la chaîne CANONIQUE COMPLÈTE avec livrable Godot (mission Pierre
    # 2026-08-03, run de référence Tetris). Comble le trou mesuré ce jour-là : aucun
    # profil ne permettait « World Scan -> Genre Bible -> Charter -> Wiremap -> Archi ->
    # Production Godot -> Oracles -> Red Team -> Verdict ». `full` a bien la conception
    # amont (s0..s6) et le gel du jeu de règles, mais son s9-build produit du web/JS ;
    # `standard_godot` livre bien du Godot mais saute s0..s6, donc n'émet AUCUN événement
    # de gel (driver.py::_freeze_rules ne suit que s5-wiremap) — cause structurelle des
    # 2 humangate_flags acceptés sur breakout_v2 (« archi non vérifiée », « wiremap non
    # vérifiée ») et de son `humangate_notes: gel des règles absent`.
    #
    # COMPOSITION = amont canonique de `full` (s0..s6, tous membres de ORDER)
    #             + build Godot de `standard_godot` (s9-build-godot-standard, dédié)
    #             + LES DEUX familles d'oracles :
    #                 * s10a-oracle-code    (mutation / e2e / solvabilité, générique)
    #                 * s10b/s10c            (archi + wiremap génériques ; s10c est ce qui
    #                                         RELIT wiremap_frozen.json et rend le gel
    #                                         opposable — c'est le point de la manœuvre)
    #                 * s10s-oracle-standard (les six oracles du squelette gelé, dédié :
    #                                         line_states, placement, collisions, index,
    #                                         contract_completeness, budget/loi d'empilement)
    #             + s11-redteam-code (advisory) + s12-verdict (agrégation signée).
    #
    # Ce profil est le SEUL à cumuler s10s ET s10b/s10c. Ce n'est pas une redondance :
    # s10s vérifie la conformité au squelette (« as-tu rempli la carte, et as-tu le droit
    # de déposer ça en bibliothèque ? »), s10b/s10c vérifient l'isomorphisme carte<->code
    # et l'intégrité du jeu de règles gelé (« la carte décrit-elle le code réel, et les
    # règles sont-elles restées les mêmes ? »). Portées disjointes, contrats distincts.
    #
    # Mélange ORDER + DEDICATED_PROFILE_STEPS : déjà le régime de `standard`/`standard_godot`,
    # pas une nouveauté introduite ici.
    # amont_only : les DEUX étapes de conception amont, rien d'autre. Sert à
    # mesurer l'effet de l'inversion World Scan -> Prisme (FORGE_PRISME_V2) sans
    # repayer une chaîne complète. Même esprit que `review` (s6 seul) et
    # `artbible` (s2.5 seul) : une tranche isolée, PAS de verdict signé — donc
    # jamais une baseline, jamais un témoin.
    "amont_only": (
        "s2-worldscan",
        "s1-prisme",
    ),
    "full_godot": (
        "s0-contrat",
        "s2-worldscan",
        "s1-prisme",
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build-godot-standard",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # full_godot_narratif (décision Pierre 2026-08-21, choix (b)) — COMPOSITION, aucune
    # station neuve : `full_godot` + les deux stations amont dédiées s2.6 (Story Bible)
    # et s2.7 (GM World Scan), placées APRÈS s0+s2 (mesuré : charter+worldscan ->
    # 7/8 GROUNDED, cf. amont_narratif_charte) et AVANT s1-prisme, qui est « le
    # mécanisme qui transforme la connaissance externe en exigences ». Consommation :
    # `_UPSTREAM_BY_STEP` (run_real/context_manifest) injecte les deux artefacts dans
    # s1 ET s3 ; la traversée jusqu'au build est MESURÉE par check_amont_traversal.mjs
    # (advisory, attaché au reçu s10c) — jamais supposée.
    "full_godot_narratif": (
        "s0-contrat",
        "s2-worldscan",
        "s2.6-story-bible",
        "s2.7-gm-worldscan",
        "s1-prisme",
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build-godot-standard",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # full_godot_content (décision Pierre 2026-08-22, ORDRE corrigé Lot A 2026-08-23) —
    # COMPOSITION, aucune station neuve : `full_godot_narratif` + s2.5-artbible
    # (Art Director), désormais placée ENTRE s2.6-story-bible et s2.7-gm-worldscan
    # (audit docs/audit/2026-08-23-kitten-clicker-worldscan-artbible-gm-pipe.md : l'Art
    # Bible doit précéder le GM et hériter du World Scan + Story Bible, pas du Prisme —
    # `product_snapshot.md` (s1) est RETIRÉ de son `mandatory_read`). Art bible injectée
    # en aval (s3/s5/s9) via `_UPSTREAM_BY_STEP` (run_real/context_manifest), inchangé.
    # LOT F -- BOUCLE DE COMPLETION MUTUELLE (2026-08-23, GO Pierre 2 rondes fixes,
    # docs/superpowers/plans/2026-08-23-forge-lot-f-boucle-completion-mutuelle.md) :
    # s2.5-artbible et s2.7-gm-worldscan tournent une 2e fois (round 2, alias
    # `<etape>-r2` -- cf. forge.contract.base_step/step_round, MEME contrat que la
    # base) juste apres leur 1re passe, AVANT s1-prisme. Round 1 = "voila ce que je
    # vois" + questions vers l'autre pilier (design_questions.json, T2) ; round 2 =
    # reponses + completion. Topologie a 2 rondes FIXES -- jamais de 3e ronde
    # automatique (hors perimetre de ce lot). Timeout : aucune entree dediee dans
    # PROFILE_STEP_TIMEOUTS_S ci-dessous pour les 2 alias -- leur base (s2.5-artbible/
    # s2.7-gm-worldscan) n'en a pas non plus (jamais mesuree), donc "meme timeout que
    # la base" == meme absence d'entree, retombant sur DEFAULT_STEP_TIMEOUT_S.
    "full_godot_content": (
        "s0-contrat",
        "s2-worldscan",
        "s2.6-story-bible",
        "s2.5-artbible",
        "s2.7-gm-worldscan",
        "s2.5-artbible-r2",
        "s2.7-gm-worldscan-r2",
        "s1-prisme",
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build-godot-standard",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ),
    # full_content (GO Pierre 2026-08-29, consolidation post-audit cartographie) —
    # COMPOSITION, aucune station neuve : la chaîne de CONCEPTION de full_godot_content
    # (story → art → gm → boucle r2/design_questions → design_freeze, briques génériques
    # mesurées comme telles par l'audit du 2026-08-29) + le build WEB de `full`
    # (s9-build + s10a/b/c), SANS les consommateurs Godot (ni s9-build-godot-standard,
    # ni s10s-oracle-standard, ni product_oracle_godot/sondes GPU — niveau 3 « ne pas
    # rapatrier comme vérité »). La gate design_freeze s'arme d'elle-même (présence de
    # s2.7 dans l'ordre, cf. driver._design_loop_active). Timeout : AUCUNE entrée dans
    # PROFILE_STEP_TIMEOUTS_S — aucun couple (full_content, étape) n'a jamais été
    # mesuré, et la doctrine de la table (« une entrée = une mesure ») interdit d'en
    # inventer ; le lanceur passe --step-timeout explicitement (RUN 1).
    "full_content": (
        "s0-contrat",
        "s2-worldscan",
        "s2.6-story-bible",
        "s2.5-artbible",
        "s2.7-gm-worldscan",
        "s2.5-artbible-r2",
        "s2.7-gm-worldscan-r2",
        "s1-prisme",
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s11-redteam-code",
        "s12-verdict",
    ),
}


# Paramètres d'exécution attachés à un couple (profil, étape) — la structure
# profil->paramètres qui n'existait pas : `PROFILES` ci-dessus ne porte que des
# SÉQUENCES d'étapes, aucun réglage.
#
# Posée en réponse à la leçon `forge.timeout_greenfield_by_profile` (validée
# 2026-08-02, run `breakout_v2-run1-20260731-082705`) : « un step-timeout de
# dispatch (défaut 1800 s) est insuffisant pour un s9 greenfield Godot construit
# depuis zéro sur un squelette de wiremap de taille standard (~50 lignes) ; 5400 s
# a suffi pour un build complet réel (~40 min). Le défaut actuel est calibré pour
# du correctif, pas pour un greenfield. »
#
# Table EXPLICITE et étroite, jamais une formule : `evidence_count: 1`, UN SEUL
# point de mesure. On n'extrapole donc PAS au greenfield web (`s9-build-standard`)
# ni au greenfield générique (`s9-build` du profil `full`) — ces couples n'ont pas
# été mesurés, et un chiffre inventé serait exactement la « promesse trop forte »
# que ce studio refuse. Ajouter une entrée ici = une mesure, pas une intuition.
PROFILE_STEP_TIMEOUTS_S: dict[tuple[str, str], float] = {
    ("standard_godot", "s9-build-godot-standard"): 5400.0,
    # full_godot : MÊME étape, MÊME contrat, MÊME builder greenfield Godot que la ligne
    # au-dessus — seule la chaîne amont change, et elle ne change pas ce que s9 a à faire.
    # Ce n'est donc PAS l'extrapolation que le commentaire ci-dessus interdit (celle-là
    # viserait un AUTRE builder : s9-build-standard web, ou s9-build générique, jamais
    # mesurés). Le point de mesure reste le même et unique : run
    # `breakout_v2-run1-20260731-082705`. Si un jour s9-build-godot-standard est mesuré
    # sous full_godot, cette valeur doit être remplacée par la mesure réelle, pas confirmée
    # par l'absence d'incident.
    ("full_godot", "s9-build-godot-standard"): 5400.0,
    # full_godot_narratif : MÊME builder, MÊME point de mesure (breakout_v2-run1).
    ("full_godot_narratif", "s9-build-godot-standard"): 5400.0,
    # full_godot_content : MÊME builder, MÊME point de mesure (breakout_v2-run1) —
    # décision Pierre 2026-08-22, composition, aucune station neuve.
    ("full_godot_content", "s9-build-godot-standard"): 9000.0,  # Lot F/G 2026-08-24 : design injecté + 10 maillons + art_response — 90 min mesurées insuffisantes (timeout à 57 fichiers au run 10d)
}


def step_timeout_for(profile: str, etape: str, default_s: float) -> float:
    """Timeout d'UNE étape pour ce profil, en secondes.

    Rend `default_s` si le couple (profil, étape) n'a pas été mesuré — c'est le
    cas de la très grande majorité, et c'est voulu : l'absence de mesure se nomme,
    elle ne se comble pas par extrapolation.
    """
    return PROFILE_STEP_TIMEOUTS_S.get((profile, etape), default_s)


def order_for_profile(profile: str = "full") -> list[str]:
    """Étapes d'un profil, dans l'ordre. Profil inconnu => ValueError (fail-fast)."""
    try:
        return list(PROFILES[profile])
    except KeyError:
        raise ValueError(f"profil inconnu {profile!r} (attendu: {', '.join(PROFILES)})")


def profile_allowed_for_contract(etape: str, profile: str) -> bool:
    """Vrai ssi `etape` appartient au `profile` — appartenance profil->étapes (D1).

    Source de vérité UNIQUE : `order_for_profile` (les PROFILES déjà testés). Pas de
    2e source divergente (pas de champ `allowed_profiles` dans les contrats YAML).
    Profil inconnu => ValueError propagé (fail-fast, comme `order_for_profile`).
    """
    return etape in order_for_profile(profile)


def prepare_dispatch(
    etape: str,
    run_id: str,
    caps_path: Path | None = None,
    audit_path: Path | None = None,
    run_dir: Path | None = None,
    *,
    profile: str | None = None,
    attempt: int = 0,
    allow_unprofiled: bool = False,
    model_executed: str | None = None,
    reason: 'str | dict' = "",
    contracts_dir: Path | None = None,
    sources_override: list | None = None,
) -> DispatchPayload:
    """Valide le contrat de l'étape, fabrique le payload borné, trace l'audit.

    Ne spawn rien : retourne le payload que l'orchestrateur donnera au sous-agent.

    ``run_dir`` (Context Manifest, docs/forge/CONTEXT_LOOP_V1_1_FRESHNESS.md §7) :
    optionnel — dérivé depuis ``run_id`` via ``context_manifest.default_run_dir``
    si non fourni. N'affecte QUE l'emplacement de la mesure advisory ; le dispatch
    lui-même n'en dépend pas.

    ``model_executed`` (0.5.d) : optionnel — le modèle RÉELLEMENT exécutant cette
    tentative quand il diffère du modèle résolu par le contrat (ex. l'override
    d'escalade côté driver). N'affecte QUE le champ additif ``model_executed`` de
    la ligne Context Manifest ``kind: dispatch`` (voir
    ``context_manifest.build_dispatch_manifest_record``) — jamais le ``model`` du
    contrat, jamais la ligne d'audit (`DispatchRecord`), jamais le dispatch lui-même.

    ``reason`` (P5, lot dégel 2) : optionnel, "" par défaut — pourquoi CETTE étape
    démarre maintenant (WHY d'activation, cf. docs/forge/FORGE_CONTEXT_COMPACT_V1.md
    §03 RC5 : jusqu'ici, seule l'escalade construisait un WHY). N'affecte QUE le
    champ additif ``reason`` de la ligne Context Manifest ``kind: dispatch`` — jamais
    la ligne d'audit signée, jamais la validation C1/C2, jamais le hook. Le driver
    (seul appelant réel en production, `forge.driver`) passe systématiquement
    ``"ordre de profil"`` à ses deux points d'appel (aucune autre source de WHY
    dynamique dans ce lot) ; un appel direct de la porte sans ``reason`` (tests,
    dry-run) produit une ligne "" — jamais une valeur devinée.

    Appartenance profil (D1) : si `profile` est fourni ET que `etape` n'en fait pas
    partie ET que `allow_unprofiled` est faux => `ContractIncomplete` (contrat non
    dispatchable dans ce profil). `allow_unprofiled=True` autorise la dérogation et
    l'inscrit (`unprofiled: true`) dans le corps SIGNÉ de la ligne d'audit. `profile=None`
    => aucun contrôle (comportement historique strictement inchangé, rétro-compat totale).
    `attempt` corrèle la ligne au triplet du marqueur de spawn (unicité D4).
    """
    # `contracts_dir` (Lot 2 V2, 2026-09-03 — Q7 de FORGE_TARGET_MODEL §12) : optionnel, None =
    # forge/contracts/ (comportement historique inchangé). Un contrat COMPOSÉ hors de ce dossier
    # passe la MÊME porte : validation C1, payload borné, ligne d'audit signée, marqueur — le
    # fichier sur disque est un détail d'implémentation, l'invariant est le dispatch enregistré.
    contract = load_contract(etape, contracts_dir)
    # R2 (audit branchements 2026-07-24) : run_id transite jusqu'à _render_prompt
    # pour que le prompt porte SYSTÉMATIQUEMENT son marqueur FORGE_DISPATCH — la
    # porte n'a plus besoin que l'orchestrateur l'appose à la main. `attempt`
    # transite aussi (lot 1 ADR-003, P0-1) : marqueur et ligne d'audit signée
    # portent le MÊME triplet (etape, run_id, attempt), sinon le hook D4 refuse
    # toute re-tentative (le marqueur 2 champs matchait toutes les tentatives).
    payload = build_dispatch_payload(contract, etape=etape, caps_path=caps_path,
                                     run_id=run_id, attempt=attempt)
    unprofiled = False
    if profile is not None and not profile_allowed_for_contract(etape, profile):
        if not allow_unprofiled:
            raise ContractIncomplete(
                f"étape {etape!r} hors du profil {profile!r} "
                f"(non membre de order_for_profile({profile!r})) — dispatch refusé ; "
                f"utilise allow_unprofiled=True pour un run hors-profil assumé"
            )
        unprofiled = True
    _append_audit(
        DispatchRecord(
            run_id=run_id,
            etape=etape,
            capability_role=contract["capability_role"],
            model=payload.model,
            provider=payload.provider,
            allowed_tools=payload.allowed_tools,
            ts=time.time(),
            event="spawn_prepared",
            attempt=attempt,
            unprofiled=unprofiled,
        ),
        audit_path,
    )
    logger.info("dispatch préparé : run=%s étape=%s modèle=%s", run_id, etape, payload.model)

    # Context Manifest (kind "dispatch") : MESURE advisory, jamais bloquante.
    # Une exception ici (I/O, résolution de source, table absente...) ne doit
    # JAMAIS faire échouer un dispatch déjà validé — best-effort strict.
    try:
        from forge import context_manifest
        effective_run_dir = run_dir if run_dir is not None else context_manifest.default_run_dir(run_id)
        context_manifest.append_dispatch_manifest(
            etape, run_id, payload, contract, run_dir=effective_run_dir,
            caps_path=caps_path, model_executed=model_executed, reason=reason,
            # Lot 5 (L8) : sources de contexte connues de l'appelant (sections du Blueprint)
            sources_override=sources_override,
        )
    except Exception:
        logger.warning(
            "context manifest (dispatch) non écrit pour run=%s étape=%s (advisory, non bloquant)",
            run_id, etape, exc_info=True,
        )

    # Tool Observability (étape 4, charter V2 — docs/fvl/FVL_PHASE_0_5_CHARTER.md
    # §4) : mesure ADDITIVE des maillons 1 (déclaration typée skill/plugin) et 2
    # (chargement réel via forge.run_real._STEP_TOOLS), dans SON PROPRE fichier
    # (jamais context_manifest, jamais audit.py, jamais payload.allowed_tools).
    # Même garantie best-effort que ci-dessus : observer, jamais gêner un
    # dispatch déjà validé. Bloc SÉPARÉ du précédent (pas de dépendance à sa
    # réussite) : re-dérive son propre `effective_run_dir` au besoin, pour que
    # cette trace-ci existe même si le Context Manifest a échoué juste avant.
    try:
        from forge import context_manifest as _cm
        from forge import tool_observability as _tool_obs
        tool_obs_run_dir = run_dir if run_dir is not None else _cm.default_run_dir(run_id)
        _tool_obs.append_tool_observability_record(
            etape, run_id, contract, run_dir=tool_obs_run_dir,
        )
    except Exception:
        logger.warning(
            "tool observability non écrite pour run=%s étape=%s (advisory, non bloquant)",
            run_id, etape, exc_info=True,
        )

    # Reasoning Observability (étape 5, charter V2 — docs/fvl/FVL_PHASE_0_5_CHARTER.md
    # §4, ligne « 5. RAISONNEMENT ») : mesure ADDITIVE du maillon 1 SEUL (déclaré —
    # `reasoning` du modèle résolu pour le `capability_role` de cette étape), dans
    # SON PROPRE fichier (jamais context_manifest, jamais audit.py, jamais
    # payload.allowed_tools/model). Les maillons 2/3/4 sont des mesures repo-wide ou
    # nécessitant un appel réel : ils vivent dans leurs propres CLI/fixtures
    # (forge.reasoning_observability scan-readers / tests), pas dans ce bloc par-run.
    # Même garantie best-effort que les deux blocs ci-dessus : observer, jamais gêner
    # un dispatch déjà validé.
    try:
        from forge import context_manifest as _cm2
        from forge import reasoning_observability as _reasoning_obs
        reasoning_run_dir = run_dir if run_dir is not None else _cm2.default_run_dir(run_id)
        _reasoning_obs.append_reasoning_observability_record(
            etape, run_id, contract, run_dir=reasoning_run_dir,
        )
    except Exception:
        logger.warning(
            "reasoning observability non écrite pour run=%s étape=%s (advisory, non bloquant)",
            run_id, etape, exc_info=True,
        )

    return payload


def plan_chain(
    run_id: str = "dryrun",
    caps_path: Path | None = None,
    audit_path: Path | None = None,
    profile: str = "full",
) -> list[DispatchPayload]:
    """Dry-run : prépare le dispatch des étapes du profil, sans spawn. Preuve de câblage."""
    return [prepare_dispatch(e, run_id, caps_path=caps_path, audit_path=audit_path)
            for e in order_for_profile(profile)]


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Dispatch gouverné de la chaîne Forge.")
    parser.add_argument("--dry-run", action="store_true", help="planifie la chaîne sans spawn")
    parser.add_argument("--profile", default="full", choices=sorted(PROFILES),
                        help="profil de chaîne (full / patch / review / micro / artbible)")
    parser.add_argument("--spawn-proof", metavar="RUN_ID",
                        help="preuve d'action d'un run : préparés / autorisés / exécutés")
    parser.add_argument("--audit", metavar="PATH", default=None,
                        help=f"fichier d'audit à lire (défaut: {DEFAULT_AUDIT})")
    args = parser.parse_args()
    if args.spawn_proof:
        proof = spawn_proof(args.spawn_proof,
                            audit_path=Path(args.audit) if args.audit else None)
        print(json.dumps(proof, ensure_ascii=False, indent=2))
    elif args.dry_run:
        audit = REPO_ROOT / "EVIDENCE" / "bundles" / "dispatch_dryrun.jsonl"
        plan = plan_chain(run_id="dryrun", audit_path=audit, profile=args.profile)
        print(f"Chaîne Forge [{args.profile}] — {len(plan)} étapes planifiées (aucun spawn) :")
        for p in plan:
            kind = "déterministe" if is_deterministic_step(p.etape) else "LLM"
            print(f"  {p.etape:22} [{kind:12}] -> {p.model}")
        print(f"Audit : {audit}")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
