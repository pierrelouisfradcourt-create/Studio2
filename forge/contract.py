"""Dispatcher de contrat d'agent Forge — la porte d'entrée bornée.

Une planète (nœud agent) EST le contrat de travail d'un sous-agent. Un agent ne
se lance jamais sans contrat complet. Ce module fait DEUX choses, dans l'ordre :

  C1  valider le contrat (les 3 états rempli / déclaré-vide / absent). Un champ
      Critique non rempli => ``ContractIncomplete``, dispatch refusé.
  C2  fabriquer le prompt borné (role + objectif + frontières + garde-fou, modèle
      forcé, seuls les outils déclarés, RÈGLE DE RESTITUTION injectée).

Ce module ne lance AUCUN process ni sous-agent : il produit un payload ou refuse.
Le spawn réel appartient au skill /forge, qui DOIT passer par cette porte.

Schéma canonique : forge/contracts/SCHEMA.md.
"""
from __future__ import annotations

import json
import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

# forge/contract.py -> parents[2] == repo root
REPO_ROOT = Path(__file__).resolve().parents[1]
CONTRACTS_DIR = REPO_ROOT / "forge" / "contracts"

# =====================================================================================
# ALIAS D'ETAPE -- boucle de completion mutuelle Art <-> GM (Lot F, 2026-08-23,
# docs/superpowers/plans/2026-08-23-forge-lot-f-boucle-completion-mutuelle.md).
#
# `s2.5-artbible`/`s2.7-gm-worldscan` doivent pouvoir tourner une 2e fois (round 2)
# dans le MEME run, sur le MEME contrat (R1 et R2 PARTAGENT le contrat -- il n'existe
# aucun fichier `<etape>-r2.yaml`, et il n'en existera jamais). L'alias `<etape>-r<N>`
# (N >= 2 ; round 1 est la forme canonique SANS suffixe) est la cle qui distingue les
# deux activations dans `state.steps` (dict par id) et dans l'audit, tout en resolvant
# au MEME fichier de contrat.
# =====================================================================================
_ALIAS_ROUND_RE = re.compile(r"^(.+)-r([2-9]\d*)$")


def base_step(etape: str) -> str:
    """Etape de BASE d'un alias de round.

    ``base_step("s2.7-gm-worldscan-r2") == "s2.7-gm-worldscan"``
    ``base_step("s2.7-gm-worldscan") == "s2.7-gm-worldscan"`` (inchange -- pas d'alias)

    Reconnait uniquement le suffixe ``-r<N>`` avec N entier >= 2 (round 1 n'a jamais
    de suffixe ``-r1`` -- c'est la forme canonique). Toute autre chaine, y compris une
    etape deja canonique ou un id qui ne matche pas le motif, est retournee TELLE
    QUELLE -- aucune exception, aucune devinette.
    """
    m = _ALIAS_ROUND_RE.match(etape or "")
    return m.group(1) if m else etape


def step_round(etape: str) -> int:
    """Round porte par ``etape`` -- 1 par defaut (round 1 = forme canonique).

    ``step_round("s2.7-gm-worldscan-r2") == 2``
    ``step_round("s2.7-gm-worldscan") == 1``
    """
    m = _ALIAS_ROUND_RE.match(etape or "")
    return int(m.group(2)) if m else 1
# Mapping rôle-de-capacité -> runtime, Forge-scopé (ne touche pas le SSOT studio). ADR-002 gate 1.
FORGE_ROLES = CONTRACTS_DIR / "roles.yaml"

# Le registry LOCAL résout le modèle depuis un rôle (ADR-002 gate 1 : jamais de modèle en dur).
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
from control_plane.registry import (  # noqa: E402
    get_model_for_role, get_provider_for_role, probleme_catalogue)

# Sentinelle de « déclaré vide » : décision assumée, distincte d'un oubli.
SENTINEL_EMPTY = "aucun"

# Les 17 champs du schéma, par niveau (voir SCHEMA.md).
CRITICAL = (
    "role",
    "capability_role",
    "exigences_cognitives",
    "memoire",
    "mandatory_read",
    "objectif",
    "in_scope",
    "out_of_scope",
    "permissions",
    "gardeFou",
    "success_criteria",
    "tests_oracles",
    "final_report",
    "output_contract",
)
IMPORTANT = ("skill", "plugin")
RECOMMENDED = ("delegation_context",)

# Couche `verification` — amendement ratifié Pierre 2026-09-02 (décision P3).
#
# `consumption_evidence` déclare QUEL artefact produit par la capacité fait foi pour
# vérifier qu'un message qui lui a été opposé (amendement/objection/question) a bien
# été incorporé à sa PRODUCTION. Il n'entre dans AUCUNE des trois couches existantes :
#   - pas `prompt`      : l'agent n'a pas à le lire, il ne lui est jamais rendu ;
#   - pas `dispatch`    : il ne touche pas le payload (modèle/provider/outils) ;
#   - pas `documentation` : celle-ci se définit par « aucun consommateur d'exécution »,
#                           or ce champ a un consommateur machine, APRÈS production.
# D'où une 4e couche, du même ordre que l'amendement layer du 2026-08-02.
#
# OPTIONNEL, et c'est structurant : il ne figure ni dans CRITICAL, ni dans IMPORTANT,
# ni dans RECOMMENDED. Un contrat qui ne le porte pas reste chargeable et activable —
# sans quoi les 23 contrats existants deviendraient invalides d'un coup. Présent, il
# est type-vérifié (précédent `delegation_context` : une décision assumée n'a jamais
# le droit d'être malformée).
#
# ADVISORY (condition 2 du précédent ratifié 2026-07-26) : rien ici ne lit ni ne
# modifie un verdict, un gate ou `verify_run`. Le point de mesure d'adoption arrive
# le même jour que le champ (condition 1) : `consumption_evidence_status` et
# `consumption_evidence_adoption` ci-dessous — un champ déclaratif sans lecteur est
# exactement la faute que ce studio a déjà payée (corpus Codex, `reference_guard`).
VERIFICATION = ("consumption_evidence",)

# Couche par champ (SCHEMA.md, "Amendement layer — ratifié Pierre 2026-08-02") :
#   prompt        champ rendu comme section de texte par `_render_prompt`.
#   dispatch      champ consommé pour construire le payload (modèle/provider/outils),
#                 jamais rendu comme section de texte.
#   documentation champ de traçabilité humaine, aucun consommateur d'exécution.
# Un champ sans consommateur déclaré ne doit pas être présenté comme une capacité
# injectée (invariant Pierre, verbatim dans SCHEMA.md). `LAYER_PROMPT` est la liste
# EXACTE des champs que `_render_prompt` rend en section — `_verify_prompt_layer_
# rendered` en dépend pour figer l'invariant « tout champ prompt rempli est rendu ».
LAYER_PROMPT = (
    "role", "exigences_cognitives", "memoire", "mandatory_read", "objectif",
    "in_scope", "out_of_scope", "permissions", "gardeFou", "success_criteria",
    "tests_oracles", "output_contract", "final_report",
)
LAYER_DISPATCH = ("capability_role", "skill", "plugin")
LAYER_DOCUMENTATION = ("delegation_context",)
# 4e couche (P3, ratifiée Pierre 2026-09-02) : champ LU PAR LA VÉRIFICATION, après
# production. Tenu HORS de `LAYER_PROMPT` par construction — `_verify_prompt_layer_
# rendered` fige « tout champ prompt rempli est rendu », et ce champ ne doit jamais
# être rendu. L'invariant reste donc intact, sans exception ajoutée.
LAYER_VERIFICATION = ("consumption_evidence",)
# `parent_agent` (SCHEMA.md #16) n'est PAS un champ canonique de ce module : il n'a
# jamais figuré dans CRITICAL/IMPORTANT/RECOMMENDED et n'est validé/rendu nulle part
# ici — inchangé par cet amendement. Son repli existe uniquement côté Observer
# (`observer.system_agents._delegation_value_and_field`, lecture seule).

# Texte injecté verbatim dans chaque prompt : l'invariant anti-claim.
# Généralise aux 21 contrats (ratification Pierre 2026-07-26, primitive 1 du
# salvage Codex) une exigence jusque-là en prose dans un seul contrat
# (orchestrator.yaml : « ce que je n'ai PAS prouvé »). Mesure d'adoption en
# regard : forge.skipped_validation.skipped_validation_status (ADVISORY).
RESTITUTION_RULE = (
    "RÈGLE DE RESTITUTION — Chaque affirmation du final_report doit citer "
    "l'oracle/l'ancre non-LLM qui l'appuie. Appuyée par un oracle => "
    "software_verdict (OK/FAIL/BLOCKED) + evidence_verdict: "
    "MECHANICAL_VALIDATION_ONLY. Sans oracle disponible => claim_verdict: "
    "NO_CLAIM_ALLOWED et remonte un besoin HumanGate (fog), jamais un claim "
    "auto-certifié. Vocabulaire de verdict : OK / FAIL / BLOCKED uniquement. "
    "En dernier lieu, une section finale SKIPPED_VALIDATION, structurée et "
    "EXPLICITE : pour chaque validation que tu n'as PAS faite, liste l'item "
    "de validation (quoi), le périmètre concerné (où), le statut (ex. non "
    "fait / partiel / hors délai) et la raison (pourquoi). Rien sauté => "
    "écris `SKIPPED_VALIDATION: aucun` — une décision assumée, jamais un "
    "silence. Le silence sur cette section est traité comme un oubli, pas "
    "comme 'rien à signaler'. "
    # R1' (GO Pierre 2026-08-13) — lignée Return : le WHY DÉCOUVERT doit survivre au
    # worker sous forme structurée, sinon `promote_manifest_lessons` n'a aucun
    # producteur (mesuré : 4 reasons promotables sur 108 lignes de manifeste, tous
    # d'origine humaine). Règle anti-faux-WHY de la ratification : NOT_DISCOVERED est
    # une réponse HONNÊTE et attendue au premier essai sans anomalie — n'inventer un
    # DISCOVERED sous aucun prétexte. L'exécuteur (run_real) extrait ce marqueur vers
    # le Context Manifest ; un marqueur ABSENT est enregistré NOT_TRANSMITTED —
    # distinct de NOT_DISCOVERED : l'un mesure l'absence de découverte, l'autre le
    # non-respect du contrat de restitution.
    "TOUTE DERNIÈRE LIGNE DU RAPPORT, OBLIGATOIRE — lignée Return : une ligne "
    "unique `RETURN_REASON: {\"status\": \"NOT_DISCOVERED\"}` si tu n'as découvert "
    "AUCUN problème pendant ce travail. Si (et SEULEMENT si) tu as réellement "
    "découvert un problème — défaut rencontré, cause d'un échec, écart mesuré — "
    "écris à la place `RETURN_REASON: {\"status\": \"DISCOVERED\", \"problem\": "
    "\"<le problème, factuel>\", \"root_cause\": \"<la cause racine si connue, "
    "sinon omets ce champ>\"}`. JSON valide sur UNE seule ligne, aucun texte "
    "après. N'invente JAMAIS un problème pour remplir ce champ : un "
    "NOT_DISCOVERED honnête vaut mieux qu'un DISCOVERED de complaisance."
)


class ContractIncomplete(Exception):
    """Levée quand un contrat n'est pas activable (Critique manquant, etc.)."""


class RoleUnresolved(ContractIncomplete):
    """Le registry ne résout aucun runtime pour le capability_role déclaré.

    Sous-classe de ContractIncomplete : un rôle non résolu = contrat non activable.
    """


def field_state(value: object) -> str:
    """Retourne l'état d'un champ : ``filled`` / ``declared_empty`` / ``absent``.

    - ``filled`` : contenu réel.
    - ``declared_empty`` : la sentinelle ``aucun`` — une décision assumée.
    - ``absent`` : clé manquante ou valeur vide — un oubli.
    """
    if value is None:
        return "absent"
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return "absent"
        if stripped.lower() == SENTINEL_EMPTY:
            return "declared_empty"
        return "filled"
    if isinstance(value, (list, tuple)):
        if len(value) == 0:
            return "absent"
        if len(value) == 1 and isinstance(value[0], str) and value[0].strip().lower() == SENTINEL_EMPTY:
            return "declared_empty"
        return "filled"
    if isinstance(value, dict):
        return "filled" if value else "absent"
    return "filled"


def consumption_evidence_status(contract: dict) -> str:
    """État d'adoption de `consumption_evidence` pour UN contrat.

    Point de mesure livré le même jour que le champ (condition 1 du précédent ratifié
    2026-07-26 : « la primitive arrive avec son point de mesure »), et calqué sur
    `forge.skipped_validation.skipped_validation_status` : trois états, vocabulaire de
    `field_state`.

      filled          la capacité a désigné le ou les artefacts qui font foi
      declared_empty  la sentinelle `aucun` — décision assumée : rien à opposer ici
      absent          la capacité n'a pas déclaré quel artefact fait foi

    ADVISORY UNIQUEMENT : ne lève jamais, ne lit aucun verdict, ne bloque rien. Le
    passage en gate dur est une décision Pierre distincte et ultérieure, prise au vu
    des chiffres — pas ici.
    """
    if not isinstance(contract, dict):
        return "absent"
    return field_state(contract.get("consumption_evidence"))


def consumption_evidence_adoption(contracts_dir: Path | None = None) -> dict:
    """Adoption de `consumption_evidence` sur TOUS les contrats d'un répertoire.

    Retourne ``{"filled": n, "declared_empty": n, "absent": n, "total": n,
    "by_contract": {etape: état}}``. Best-effort strict : un YAML illisible est compté
    ``absent`` et n'interrompt jamais la mesure — mesurer ne doit pas pouvoir échouer.
    """
    directory = contracts_dir or CONTRACTS_DIR
    counts = {"filled": 0, "declared_empty": 0, "absent": 0}
    by_contract: dict[str, str] = {}
    for path in sorted(Path(directory).glob("*.yaml")):
        try:
            with open(path, encoding="utf-8") as fh:
                data = yaml.safe_load(fh)
        except Exception:
            data = None
        state = consumption_evidence_status(data if isinstance(data, dict) else {})
        by_contract[path.stem] = state
        counts[state] += 1
    return {**counts, "total": len(by_contract), "by_contract": by_contract}


def load_contract(etape: str, contracts_dir: Path | None = None) -> dict:
    """Charge le contrat YAML canonique d'une étape.

    Résout l'ALIAS de round (Lot F, `<etape>-r<N>` avec N>=2) vers le fichier de
    la BASE avant de construire le chemin — R1 et R2 d'une même étape de la boucle
    de complétion mutuelle partagent EXPRÈS le même contrat (cf. `base_step`). Le
    contrat retourné est donc celui de la base, jamais un fichier `-r2.yaml` qui
    n'existe pas et n'existera jamais.
    """
    path = (contracts_dir or CONTRACTS_DIR) / f"{base_step(etape)}.yaml"
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        raise ContractIncomplete(f"contrat {etape!r} n'est pas un mapping YAML")
    return data


def validate_contract(contract: dict) -> None:
    """C1 — refuse un contrat non activable. Ne retourne rien ; lève ou passe."""
    problems: list[str] = []
    for field in CRITICAL:
        state = field_state(contract.get(field))
        if state != "filled":
            problems.append(f"Critique {field!r} = {state} (exige 'filled')")
    for field in IMPORTANT:
        state = field_state(contract.get(field))
        if state == "absent":
            problems.append(f"{field!r} absent (doit être rempli ou 'aucun', jamais absent)")
    # RECOMMENDED (delegation_context) : levée d'obligation — SCHEMA.md "Amendement
    # layer" (ratifié Pierre 2026-08-02). Champ de couche `documentation`, aucun
    # consommateur d'exécution : son absence ne peut plus bloquer le dispatch. S'il
    # EST présent (rempli ou `aucun`), il reste type-vérifié : une décision assumée
    # n'a jamais le droit d'être malformée. Un contrat futur sans ce champ passe
    # désormais ; un contrat qui le porte avec un type invalide est toujours refusé.
    for field in RECOMMENDED:
        value = contract.get(field)
        if value is not None and not isinstance(value, (str, list, tuple)):
            problems.append(
                f"{field!r} présent mais de type invalide ({type(value).__name__}, "
                "attendu str/list)"
            )
    # VERIFICATION (couche 4, P3 ratifiée Pierre 2026-09-02) : OPTIONNEL — son absence
    # ne peut RIEN bloquer (23 contrats sur 23 ne le portent pas au jour de l'amendement).
    # Présent, il est type-vérifié, même discipline que RECOMMENDED.
    for field in VERIFICATION:
        value = contract.get(field)
        if value is not None and not isinstance(value, (str, list, tuple)):
            problems.append(
                f"{field!r} présent mais de type invalide ({type(value).__name__}, "
                "attendu str/list)"
            )
    if problems:
        raise ContractIncomplete("; ".join(problems))


@dataclass(frozen=True)
class DispatchPayload:
    """Le cadre borné remis au sous-agent. Aucun spawn — juste les données."""

    etape: str
    role: str
    model: str
    prompt: str
    allowed_tools: tuple[str, ...]
    mandatory_read: tuple[str, ...]
    # provider résolu par le registry (lmstudio / claude-local / forge). Défaut ""
    # => aucune régression sur les constructions existantes. Lu par l'aiguilleur
    # runtime (forge.runtime.route_step) pour honorer le contrat à l'exécution.
    provider: str = ""


# =====================================================================================
# RECONNEXION KB — les fiches de connaissance CITÉES par le contrat
#
# RECONNEXION KB RATIFIÉE PAR GO EXPLICITE DE PIERRE, 2026-08-13. Ne vaut pas
# autorisation générale de modifier forge/**.
#
# CE N'EST PAS UNE NOUVELLE CAPACITÉ — aucun module, dossier, schéma ni oracle neuf.
# Le canal existait déjà de bout en bout :
#     `memoire` (champ CRITIQUE, couche `prompt`, SCHEMA.md #3, « oriente : carte des
#     conventions ») -> `_render_prompt` -> `payload.prompt` -> `run_real.claude_executor`
# Ce qui manquait : un contrat peut CITER l'identité d'une fiche ratifiée sans que
# personne ne la résolve. `contracts/wm1-wiremap-tetris.yaml` en cite trois sous
# « Leçons validées du curriculum, à ne pas répéter » ; l'agent recevait la PARAPHRASE
# recopiée à la main dans le contrat, jamais le texte de référence.
#
# Défaut MESURÉ le 2026-08-13, pas supposé : sur `forge.forge_oracle_convention_
# undocumented`, la paraphrase du contrat affirme que la convention FORGE_ORACLE
# « est désormais déclarée dans forge/standard/SCHEMA.md », là où la fiche
# ratifiée dit qu'elle n'y est « jamais déclarée ». Les deux textes se contredisent.
# Une paraphrase figée dans un contrat ne peut pas être requalifiée par une
# ratification ultérieure — c'est la variante « côté lecture » de la règle du studio
# `forge.proof_text_must_be_derived`. Ici on n'EFFACE pas la paraphrase (le contrat
# reste rendu verbatim, cf. `_verify_prompt_layer_rendered`) : on SERT le texte de
# référence à côté, et la divergence devient visible pour l'agent au lieu d'être
# silencieusement tranchée en faveur du plus ancien des deux.
#
# PERTINENCE DÉCLARÉE, JAMAIS DEVINÉE. Une fiche n'est servie que si le contrat NOMME
# son identité dans son PROPRE champ `memoire`. Aucun score, aucun seuil, aucune
# similarité, aucune recherche lexicale (`knowledge_base/search.mjs` reste hors de ce
# chemin) : appariement de sous-chaîne EXACTE contre les identités RÉELLEMENT présentes
# dans le catalogue. Corollaire dur : un contrat qui ne cite rien ne reçoit RIEN de neuf
# — son prompt est inchangé octet pour octet. Zéro faux positif par construction, pas
# par réglage.
#
# SOURCE UNIQUE = `knowledge_base/catalog.json`, le magasin RATIFIÉ (une fiche n'y entre
# que par `kb_proposal --apply --ratifie-par <humain>`, ADR-002 propose-only). Une
# proposition encore sous `knowledge_base/proposals/` n'est PAS servie : seules son
# identité et son état « non ratifiée » sont signalés. Servir son CONTENU
# court-circuiterait le HumanGate — ce qui ferait de ce branchement exactement la
# faute qu'il répare.
#
# CE QUE CECI PROUVE / NE PROUVE PAS : l'EXPOSITION (le texte de la fiche est dans le
# prompt réellement rendu, mesurée et signée HMAC par `forge.context_manifest.
# append_execution_manifest`), JAMAIS la CONSOMMATION. Le lecteur de consommation
# existe déjà et est câblé (`knowledge_trace.mjs --verify`, appelé par
# `forge.verify_run`) ; lui donner un producteur est un lot SÉPARÉ, et une décision
# Pierre. MISE À JOUR (décision N-2, ratifiée Pierre 2026-09-02) : `verify_run` ne
# traite PLUS les problèmes de knowledge_trace comme bloquants — le contrôle est passé
# en ADVISORY, précisément pour que le branchement d'un producteur de traces ne
# transforme pas un gate marginal (1 run_dir sur 89) en blocage systémique. Séquence
# ratifiée : advisory -> émission -> mesure d'adoption -> décision Pierre sur le gate.
# =====================================================================================

KB_CATALOG = REPO_ROOT / "knowledge_base" / "catalog.json"
KB_PROPOSALS_DIR = REPO_ROOT / "knowledge_base" / "proposals"
KB_SECTION_TITLE = "FICHES DE CONNAISSANCE CITÉES (texte de référence, non paraphrasé)"


def _kb_catalog_index(catalog_path: Path | None = None) -> dict[str, dict] | None:
    """`{identité citable -> entrée de catalogue}`, lu dans le catalogue RATIFIÉ.

    Une même entrée est indexée sous TOUTES les identités sous lesquelles un contrat
    peut légitimement la citer : `brick_id` / `asset_id` / `role_id` (l'identité du
    catalogue) et `provenance_internal.lesson_id` (l'identité de la leçon d'origine,
    `forge.<slug>` — c'est CELLE que les contrats écrivent en pratique). C'est le
    catalogue lui-même qui déclare l'équivalence des deux, jamais une ressemblance de
    nom — même principe de jointure que `search_usage.tableCheminVersBrique`.

    Rend `None` quand le catalogue est ABSENT OU ILLISIBLE — distinct d'un `{}` (lu,
    mais sans entrée). La distinction n'est pas cosmétique : sans elle, un catalogue
    injoignable ferait dire « cette fiche n'est pas ratifiée » d'une fiche qui l'est.
    C'est exactement la faute que décrit `forge.oracle_fail_vs_not_measured_marker`
    (« non mesurable » ne se maquille ni en échec ni en succès) — défaut RÉEL trouvé
    par la falsification de ce branchement le 2026-08-13, pas une précaution théorique.
    """
    path = Path(catalog_path) if catalog_path else KB_CATALOG
    index: dict[str, dict] = {}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    for entry in doc.get("entries") or []:
        if not isinstance(entry, dict):
            continue
        for key in ("brick_id", "asset_id", "role_id"):
            ident = entry.get(key)
            if ident:
                index[str(ident)] = entry
        provenance = entry.get("provenance_internal")
        if isinstance(provenance, dict) and provenance.get("lesson_id"):
            index[str(provenance["lesson_id"])] = entry
    return index


def _kb_pending_ids(proposals_dir: Path | None = None) -> set[str]:
    """Identités des propositions NON ENCORE ratifiées, lues comme `kb_proposal.py` les
    écrit : le nom de fichier EST l'identité (`_proposal_path` => `<lesson_id>.yaml`).

    Volontairement AUCUN parsing du contenu : 4 des 36 fiches présentes le 2026-08-13
    ne sont pas du YAML valide (rédigées à la main, hors `--generate`). Une identité
    n'a pas à dépendre de la validité du corps du document — et rien de leur CONTENU
    n'est servi de toute façon.
    """
    directory = Path(proposals_dir) if proposals_dir else KB_PROPOSALS_DIR
    try:
        return {p.stem for p in directory.glob("*.yaml")}
    except OSError:
        return set()


def _cited_identities(texte: str, identities: set[str]) -> list[str]:
    """Identités RÉELLES citées dans `texte`, par sous-chaîne exacte.

    On n'essaie JAMAIS de deviner à quoi ressemble un identifiant (aucune regex de
    forme) : on part des identités qui existent vraiment et on demande si le texte les
    contient. Une identité strictement contenue dans une autre identité trouvée est
    écartée — sinon citer `pat-forge-x` servirait aussi une hypothétique `forge-x`.
    """
    found = [i for i in identities if i in texte]
    return sorted(i for i in found if not any(i != j and i in j for j in found))


def kb_fiches_citees(
    memoire: object,
    *,
    catalog_path: Path | None = None,
    proposals_dir: Path | None = None,
) -> dict:
    """Fiches de connaissance qu'un contrat CITE dans son champ `memoire`.

    Rend `{"servies": [...], "en_attente_de_ratification": [...]}` :
      - `servies` : fiche présente dans le catalogue ratifié — son énoncé de référence
        (`function`) est servi tel quel, jamais reformulé.
      - `en_attente_de_ratification` : identité citée qui existe sous
        `knowledge_base/proposals/` mais PAS dans le catalogue. Seule l'identité est
        rapportée ; le contenu reste derrière le HumanGate.
    Une identité citée qui n'existe ni dans l'un ni dans l'autre n'est pas rapportée :
    on ne sait pas si c'est une faute de frappe ou une connaissance qui vit ailleurs
    (mémoire studio, doctrine), et inventer ce diagnostic serait une devinette.

    Catalogue injoignable => les DEUX listes sont vides et rien n'est rendu : on ne
    peut alors ni servir un texte de référence, ni affirmer qu'une fiche attend sa
    ratification. Ne rien dire est le seul état honnête (cf. `_kb_catalog_index`).
    """
    if isinstance(memoire, (list, tuple)):
        texte = "\n".join(str(item) for item in memoire)
    else:
        texte = str(memoire or "")
    if not texte.strip():
        return {"servies": [], "en_attente_de_ratification": []}

    index = _kb_catalog_index(catalog_path)
    if index is None:  # non mesurable : ni servir, ni qualifier
        return {"servies": [], "en_attente_de_ratification": []}
    pending = _kb_pending_ids(proposals_dir)

    servies: list[dict] = []
    attente: list[str] = []
    vues: set[str] = set()
    for ident in _cited_identities(texte, set(index) | pending):
        entry = index.get(ident)
        if entry is None:
            attente.append(ident)
            continue
        canonique = str(
            entry.get("brick_id") or entry.get("asset_id") or entry.get("role_id") or ident
        )
        if canonique in vues:  # `forge.x` ET `pat-forge-x` cités : une seule fiche
            continue
        vues.add(canonique)
        servies.append({
            "cite": ident,
            "id": canonique,
            "tier": str(entry.get("tier") or "?"),
            "enonce": str(entry.get("function") or "").strip(),
        })
    return {"servies": servies, "en_attente_de_ratification": attente}


def _render_kb_section(fiches: dict) -> str | None:
    """CORPS de la section de prompt pour les fiches citées (le titre est ajouté par
    `_render_prompt`, comme pour toute autre section), ou None si le contrat n'en cite
    aucune — cas de 47 des 48 contrats : prompt strictement inchangé."""
    servies = fiches.get("servies") or []
    attente = fiches.get("en_attente_de_ratification") or []
    if not servies and not attente:
        return None
    lignes = [
        "Ton champ `memoire` ci-dessus NOMME ces fiches. Voici leur texte de RÉFÉRENCE,",
        "résolu mécaniquement depuis knowledge_base/catalog.json (magasin ratifié par",
        "HumanGate). Si ce texte contredit le résumé du contrat, c'est la FICHE qui fait",
        "foi et la divergence doit être signalée dans ton rapport — jamais tranchée en",
        "silence.",
        "",
    ]
    for fiche in servies:
        lignes.append(f"- `{fiche['id']}` (cité `{fiche['cite']}`, tier={fiche['tier']})")
        lignes.append(f"  {fiche['enonce']}")
    for ident in attente:
        lignes.append(
            f"- `{ident}` : fiche PROPOSÉE, non ratifiée — contenu volontairement NON servi "
            "(HumanGate Pierre en attente)."
        )
    return "\n".join(lignes)


def _render_prompt(contract: dict, etape: str = "", run_id: str = "",
                   attempt: int = 0) -> str:
    """Assemble le prompt borné à partir des champs du contrat.

    R2 (audit branchements 2026-07-24) : quand `etape` ET `run_id` sont connus
    (la porte réelle — `dispatch.prepare_dispatch` — les fournit toujours), le
    prompt PORTE systématiquement le marqueur
    ``FORGE_DISPATCH:<etape>:<run_id>:<attempt>`` attendu par
    `forge.hook_guard.MARKER` / `.claude/hooks/pretool_forge_guard.py`.
    AVANT ce correctif, ce marqueur était apposé À LA MAIN par l'orchestrateur
    (cf. `forge/run_real.py::claude_executor`, `context['dispatch_marker']`) —
    un oubli à ce niveau désarmait silencieusement le hook dur. Un appel direct
    sans run_id (tests C1/C2 unitaires, dry-run sans run réel) omet le marqueur :
    comportement strictement inchangé pour ces usages.

    `attempt` (lot 1 ADR-003, P0-1) : le marqueur porte le triplet complet, sinon
    l'unicité D4 du hook retombe sur le couple (etape, run_id) et REFUSE toute
    re-tentative dès la 2e ligne `spawn_prepared` (ambiguïté/replay) — le marqueur
    2 champs rendu ici masquait (première occurrence gagne, `MARKER.search`) le
    marqueur 3 champs correct que le driver appose plus loin dans le prompt.
    Même convention que `DispatchRecord.attempt` et `hook_guard.marker_key`
    (défaut 0) : la corrélation audit↔marqueur reste exacte.
    """
    sections = [("RÔLE", contract["role"])]
    # P1 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §05.2) : `exigences_
    # cognitives` et `memoire` sont CRITIQUES (contrat REFUSÉ si vides, cf. CRITICAL
    # ci-dessus) mais n'atteignaient jamais le prompt rendu — validés puis jetés.
    # Rendus ici, dans l'ORDRE de CRITICAL (juste après `role`, avant `objectif`).
    # Règle des 3 états : seul `filled` produit une section ; une valeur `aucun`
    # (declared_empty — décision assumée, pas un oubli, cf. `validate_contract`
    # qui l'accepte pour ces deux champs CRITIQUES seulement s'ils sont `filled`
    # en pratique, ce garde-fou couvre aussi un appel direct de `_render_prompt`
    # sur un contrat non validé) n'apparaît PAS comme section.
    if field_state(contract.get("exigences_cognitives")) == "filled":
        sections.append(("EXIGENCES COGNITIVES", contract["exigences_cognitives"]))
    if field_state(contract.get("memoire")) == "filled":
        sections.append(("MÉMOIRE DE TRAVAIL", contract["memoire"]))
        # RECONNEXION KB RATIFIÉE PAR GO EXPLICITE DE PIERRE, 2026-08-13. Ne vaut
        # pas autorisation générale de modifier forge/**.
        # Adossée à `memoire` (jamais rendue sans elle) : la citation vit dans ce
        # champ, la résolution le suit immédiatement. Best-effort strict, même
        # discipline que le pré-mortem côté driver — une KB illisible ne doit
        # JAMAIS transformer un dispatch valide en refus, elle ne sert rien.
        try:
            kb_section = _render_kb_section(kb_fiches_citees(contract["memoire"]))
        except Exception:  # noqa: BLE001 — lecture best-effort, jamais bloquante
            logger.warning("fiches KB citées non résolues (non bloquant)", exc_info=True)
            kb_section = None
        if kb_section:
            sections.append((KB_SECTION_TITLE, kb_section))
    sections += [
        ("OBJECTIF", contract["objectif"]),
        ("DANS LE PÉRIMÈTRE (in_scope)", contract["in_scope"]),
        ("HORS PÉRIMÈTRE (out_of_scope)", contract["out_of_scope"]),
        ("PERMISSIONS", contract["permissions"]),
        ("GARDE-FOU", contract["gardeFou"]),
        ("CRITÈRES DE RÉUSSITE", contract["success_criteria"]),
        ("ORACLES / TESTS", contract["tests_oracles"]),
        ("CONTRAT DE SORTIE", contract["output_contract"]),
        ("RAPPORT FINAL", contract["final_report"]),
    ]
    body = "\n\n".join(f"## {title}\n{value}" for title, value in sections)
    reads = "\n".join(f"- {r}" for r in contract["mandatory_read"])
    prompt = (
        f"{body}\n\n## À LIRE OBLIGATOIREMENT AVANT TOUTE ACTION\n{reads}\n\n"
        f"## {RESTITUTION_RULE}"
    )
    if etape and run_id:
        prompt += (f"\n\n## MARQUEUR DE DISPATCH (ne pas modifier)\n"
                   f"FORGE_DISPATCH:{etape}:{run_id}:{attempt}")
    return prompt


def _verify_prompt_layer_rendered(contract: dict, prompt: str) -> None:
    """Garde mécanique de la couche `prompt` (SCHEMA.md, amendement layer ratifié
    Pierre 2026-08-02) : tout champ de `LAYER_PROMPT` REMPLI doit apparaître comme
    texte dans le prompt déjà produit par `_render_prompt`. Fige un invariant qui
    existait par construction (chaque champ de `LAYER_PROMPT` a sa section codée
    en dur dans `_render_prompt`) mais qu'aucun test/garde ne vérifiait — protège
    contre une dérive future (un champ ajouté à `LAYER_PROMPT` sans sa section de
    rendu redeviendrait une capacité "validée" mais jamais injectée).

    Lecture seule : ne modifie ni le contrat, ni le prompt. N'ajoute aucune section.
    """
    missing: list[str] = []
    for field in LAYER_PROMPT:
        value = contract.get(field)
        if field_state(value) != "filled":
            continue
        if isinstance(value, (list, tuple)):
            if not all(str(item) in prompt for item in value):
                missing.append(field)
        elif str(value) not in prompt:
            missing.append(field)
    if missing:
        raise ContractIncomplete(
            "couche prompt (SCHEMA.md) déclarée mais jamais rendue par _render_prompt : "
            + ", ".join(missing)
        )


def _declared_tools(contract: dict) -> tuple[str, ...]:
    """Seuls les skill/plugin réellement remplis sont autorisés."""
    tools = []
    for field in IMPORTANT:
        if field_state(contract.get(field)) == "filled":
            tools.append(contract[field])
    return tuple(tools)


def resolve_runtime(contract: dict, caps_path: Path | None = None) -> str:
    """Résout le runtime depuis le capability_role via le registry LOCAL.

    Le contrat ne fixe jamais un modèle en dur (ADR-002 gate 1) : il déclare un
    rôle, le registry force le runtime. Rôle non résolu => RoleUnresolved (refus).
    """
    role = contract["capability_role"]
    chemin = caps_path or FORGE_ROLES
    model = get_model_for_role(role, caps_path=chemin)
    if not model:
        # La CAUSE, pas seulement le verdict (gate 2, 2026-09-05) : fichier absent,
        # YAML illisible, fichier vide et structure invalide rendaient tous le même
        # message accusant LE RÔLE — on relisait la liste des rôles, saine, au lieu de
        # soupçonner le fichier. Le diagnostic n'est calculé QUE sur ce chemin d'échec.
        cause = probleme_catalogue(chemin)
        detail = f" — catalogue inexploitable : {cause}" if cause else ""
        raise RoleUnresolved(
            f"capability_role {role!r} non résolu par le registry{detail}")
    return model


def build_dispatch_payload(
    contract: dict, etape: str = "", caps_path: Path | None = None, run_id: str = "",
    attempt: int = 0,
) -> DispatchPayload:
    """C1+C2 — refuse si le contrat est incomplet, sinon fabrique le payload borné.

    Le role (posture) est INJECTÉ dans le payload ; le modèle est FORCÉ par le
    registry local à partir du capability_role (jamais écrit en dur dans le contrat).

    R2 : `run_id`, quand fourni (toujours le cas via la porte réelle
    `dispatch.prepare_dispatch`), fait porter au prompt le marqueur
    ``FORGE_DISPATCH:<etape>:<run_id>:<attempt>`` attendu par le hook dur — plus
    besoin que l'orchestrateur l'appose à la main. Omis (défaut "") : comportement
    inchangé. `attempt` (lot 1 ADR-003, P0-1) : transmis par la porte pour que le
    marqueur porte le même triplet que la ligne d'audit signée (unicité D4 par
    tentative — les re-tentatives d'une même étape redeviennent spawnables).
    """
    validate_contract(contract)  # C1 : la porte bloque d'abord
    model = resolve_runtime(contract, caps_path=caps_path)  # registry force le runtime
    provider = get_provider_for_role(contract["capability_role"], caps_path=caps_path or FORGE_ROLES) or ""
    prompt = _render_prompt(contract, etape=etape, run_id=run_id, attempt=attempt)
    _verify_prompt_layer_rendered(contract, prompt)  # garde couche prompt (SCHEMA.md)
    payload = DispatchPayload(
        etape=etape,
        role=contract["role"],
        model=model,
        prompt=prompt,
        allowed_tools=_declared_tools(contract),
        mandatory_read=tuple(contract["mandatory_read"]),
        provider=provider,
    )
    logger.info("contrat %s activé : rôle=%s -> modèle=%s (provider=%s), %d outils",
                etape or "?", contract["capability_role"], payload.model, provider or "?",
                len(payload.allowed_tools))
    return payload
