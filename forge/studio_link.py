"""Connecteurs studio de Forge — ADR-002 §3 (connecteurs 3/4/5/6).

Branche la boucle Forge sur les systèmes vivants du studio, en PROPOSE-ONLY :
tout est écrit sous ``EVIDENCE/bundles`` ou ``EVIDENCE/reports/forge_*`` — JAMAIS
dans les mémoires de référence (le ledger, la liste des projets). Une écriture
durable exige un HumanGate séparé (promotion via kaizen_loop / édition Pierre).

- Connecteur 3 : télémétrie coût/tokens par appel + agrégat par run.
- Connecteur 4 : proposition d'entrée ledger en lane AUDIT_REQUIRED.
- Connecteur 5 : proposition d'enregistrement projet.
- Connecteur 6 : journal d'erreurs + pré-mortem (lu par l'étape 0 au run suivant).
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path

from forge.verify_run import _harden_streams

logger = logging.getLogger(__name__)

# forge/studio_link.py -> parents[2] == repo root
REPO_ROOT = Path(__file__).resolve().parents[1]
FORGE_EVIDENCE = REPO_ROOT / "EVIDENCE" / "bundles"
FORGE_REPORTS = REPO_ROOT / "EVIDENCE" / "reports"
FORGE_RUNS = REPO_ROOT / "EVIDENCE" / "runs"

DEFAULT_TELEMETRY = FORGE_EVIDENCE / "forge_telemetry.jsonl"
# Journal MONOLITHE historique (pré-refactor par domaine). Conservé INTACT : il
# contient les vraies leçons (collect_runner/breakout/shmup, tous jeux HTML) + les
# leçons globales de méthode. On ne le RÉÉCRIT jamais — il sert de FALLBACK-LECTURE
# (voir `premortem`) pour ne rien perdre pendant la migration.
DEFAULT_ERROR_JOURNAL = FORGE_REPORTS / "forge_error_journal.jsonl"
# Refactor connecteur 6 : journaux PAR DOMAINE sous EVIDENCE/reports/error_journal/.
# Isole les leçons par nature de cible (un run rust ne lit pas les leçons html) pour
# éviter qu'un agent tire une leçon hors-sujet d'un monolithe indifférencié.
DOMAIN_JOURNAL_DIR = FORGE_REPORTS / "error_journal"
DEFAULT_LEDGER_PROPOSALS = FORGE_REPORTS / "forge_ledger_proposals.jsonl"
DEFAULT_PROJECT_PROPOSALS = FORGE_REPORTS / "forge_project_proposals.jsonl"
DEFAULT_BIBLE_PROPOSALS = FORGE_REPORTS / "forge_bible_proposals.jsonl"
# Le dépositaire (boucle bibliothèque, ratification Pierre 2026-07-23 : « réciprocité dure +
# construire le dépositaire ») : un jeu forgé PROPOSE un dépôt de brique ici ; Pierre PROMEUT
# manuellement dans knowledge_base/catalog.json (voir propose_brick ci-dessous).
# Connecteur 7 (mission repair-boucle-cassee 2026-08-03, FORGE_AUTONOMY_V1) : la
# flèche « manque ? -> world-scan ciblé du manquant -> pool de builders » (Coupe B,
# STUDIO_MASTER_SCHEMA.html) était un cul-de-sac pour la moitié « capacité inconnue »
# du registre `capabilities.yaml` — `check_collisions` (standard_oracles.py) calcule
# `identifiants_inconnus` mais AUCUN appelant ne les rendait consommables (grep vide
# avant ce correctif). `capabilities.yaml` grandit délibérément « d'un jeu à l'autre »
# (son propre en-tête) : un identifiant inconnu N'EST PAS une erreur de jeu à corriger,
# c'est une capacité candidate à AJOUTER au registre fermé — mais le registre est une
# mémoire de référence versionnée (même statut que catalog.json ou le ledger d'IMPs)
# et un `statement` (phrase humaine décrivant la capacité) ne peut pas être fabriqué
# mécaniquement sans inventer du sens. PROPOSE-ONLY, patron IDENTIQUE à propose_brick
# ci-dessus : dépose une proposition nommée, Pierre promeut dans capabilities.yaml.
DEFAULT_CAPABILITY_GAP_PROPOSALS = FORGE_REPORTS / "forge_capability_gap_proposals.jsonl"
# File USINE, jumelle de la precedente (decision Pierre 2026-08-10, option b). Une
# capacite de PREUVE (sonde, harnais, bot de solvabilite) ne doit pas remonter dans la
# file PRODUIT : Pierre y arbitre des capacites de JEU, et 8 identifiants d'usine
# mesures sur pacman s'y melangeraient a 67 identifiants de jeu.
DEFAULT_FACTORY_CAPABILITY_GAP_PROPOSALS = (
    FORGE_REPORTS / "forge_factory_capability_gap_proposals.jsonl"
)
DEFAULT_BRICK_PROPOSALS = FORGE_REPORTS / "forge_brick_proposals.jsonl"
# Tier 2.5 étape 2 : observabilité dédiée du pool de builders (Tier 2 #5) — sans ça,
# le pool reste une boîte noire. Un enregistrement par TENTATIVE s9-build (pas un
# agrégat par run) : c'est la granularité qui répond à « le pool sauve-t-il des
# tâches ? », « quels builders échouent toujours ? », « quelles stratégies marchent ? ».
DEFAULT_BUILDER_RUNS = FORGE_EVIDENCE / "forge_builder_runs.jsonl"


def _append(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _read(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


# --- Connecteur 3 : télémétrie -------------------------------------------------

# G1-G2 (vérité métrique minimale, ratifié Pierre — session_id · task_id ·
# modèle utilisé · tokens réels) : l'exécuteur réel (forge.run_real) MESURE ces
# valeurs dans le flux stream-json, mais la ligne télémétrie est écrite par le
# DRIVER (record_telemetry ci-dessous, appelé driver.py:692 succès / :938 halt),
# qui ne les connaît pas et dont le fichier est HORS PÉRIMÈTRE de ce chantier.
# Ce dépôt en mémoire de process fait le pont SANS toucher au driver : l'exécuteur
# dépose (stage_telemetry_extra), la PROCHAINE écriture télémétrie du même
# (run_id, etape) consomme (pop) — les deux appels ont lieu dans le même process,
# séquentiellement, immédiatement après le retour de l'exécuteur. ADDITIF pur :
# les clés existantes de la ligne (model/tokens DÉCLARÉS) restent intactes — la
# comparaison déclaré/mesuré est précisément le but ; une ligne sans dépôt
# (étape déterministe, runner non-claude, vieux appelant) est INCHANGÉE.
# P3 (2026-08-15) : + "tools_used" (Expérience C) — produit par parse_stream_metrics
# depuis 2026-08-12 puis PERDU (absent de ce tuple ET du littéral detail du driver) :
# une mesure d'usage réel d'outils sans persistance, quatrième occurrence du motif
# « mesuré → perdu » (après markdown_check/M3'a, yaml_check/M4', findings_note).
# Consommateur décisionnel : AUCUN à ce jour — PASSIVE DÉCLARÉ. Le consommateur
# prévu est le capteur M5 « outil UTILISÉ vs outil ACCORDÉ » (gate Pierre ouverte,
# 00_CURRENT_CONTEXT §gates) : ce champ en est la moitié « UTILISÉ », déjà mesurée.
TELEMETRY_MEASURED_FIELDS = ("session_id", "task_id", "model_used", "tokens_measured",
                             "tools_used")
_pending_telemetry_extra: dict[tuple[str, str], dict] = {}


def stage_telemetry_extra(run_id: str, etape: str, extra: dict) -> None:
    """Dépose les champs MESURÉS (TELEMETRY_MEASURED_FIELDS) pour la prochaine
    ligne télémétrie de (run_id, etape). Best-effort strict : seules les clés
    du contrat G1-G2 sont retenues (jamais un champ arbitraire injecté dans la
    ligne), une clé absente vaut None (échec de capture = champ à null, jamais
    une ligne cassée), et AUCUNE exception ne sort (capteur, jamais juge)."""
    try:
        _pending_telemetry_extra[(str(run_id), str(etape))] = {
            k: extra.get(k) for k in TELEMETRY_MEASURED_FIELDS
        }
    except Exception:
        logger.warning("stage_telemetry_extra: dépôt impossible pour (%s, %s) "
                       "(advisory, non bloquant)", run_id, etape, exc_info=True)


def record_telemetry(
    run_id: str,
    etape: str,
    model: str,
    tokens: int,
    duration_s: float,
    telemetry_path: Path | None = None,
    outcome: str = "OK",
    cost_usd: float = 0.0,
) -> None:
    """Trace le coût d'un appel (tokens/durée/modèle/coût/issue).

    MISSION_M1_TELEMETRIE_ECHEC.md (design imposé, §pts 1/2) : avant ce
    correctif, `record_telemetry` n'était appelé QUE sur le chemin succès
    (driver._run_llm après `entry["status"] = "OK"`) — un échec d'étape
    (`_halt_step`) ne laissait aucune trace. `outcome` et `cost_usd` rendent
    ce chemin d'échec observable SANS rien changer au format existant :

    - `outcome` ∈ {"OK", "HALT"} — "OK" par défaut, rétrocompatible avec TOUS
      les appels historiques (aucun n'existait sur le chemin d'échec avant ce
      correctif, donc aucun appelant réel ne dépendait d'une valeur différente).
    - `cost_usd` : coût réel de l'appel, 0.0 par défaut (rétrocompatible). Un
      0.0 explicite (ex. halte AVANT tout appel LLM) reste un ZÉRO MESURÉ —
      la ligne existe, ce n'est pas une absence de mesure (cf. la distinction
      déjà faite au niveau fichier par `ForgeDriver._cost_and_effort`).

    Champs ADDITIONNELS uniquement : les lecteurs existants de
    `forge_telemetry.jsonl` (dict.get sur des clés connues) ne voient rien
    casser ; une ligne ÉCRITE AVANT ce correctif n'a simplement pas ces deux
    clés (normalisées à la lecture, cf. `tokens_by_successful_step`).
    """
    record = {"run_id": run_id, "etape": etape, "model": model,
              "tokens": tokens, "duration_s": duration_s, "cost_usd": cost_usd,
              "outcome": outcome, "ts": time.time()}
    # G1-G2 : fusion des champs MESURÉS déposés par l'exécuteur (voir
    # stage_telemetry_extra ci-dessus). pop = consommé une seule fois, jamais
    # rejoué sur une tentative suivante ; setdefault = un champ existant de la
    # ligne (les DÉCLARÉS) n'est JAMAIS écrasé par le dépôt. Aucun dépôt =>
    # ligne strictement identique à avant ce chantier.
    extra = _pending_telemetry_extra.pop((str(run_id), str(etape)), None)
    if extra:
        for key, value in extra.items():
            record.setdefault(key, value)
    _append(telemetry_path or DEFAULT_TELEMETRY, record)


def run_cost(run_id: str, telemetry_path: Path | None = None) -> dict:
    """Agrège le coût d'un run : nb d'appels, tokens totaux, durée totale.

    INCHANGÉ par M1 (advisory strict — cf. design imposé §4, aucune métrique
    nouvelle au-delà de `tokens_by_successful_step`) : additionne TOUTES les
    lignes du run, succès et halt confondus — c'est précisément ce qui permet
    à `run_cost` de désormais compter aussi les tentatives échouées (avant ce
    correctif elles n'existaient simplement pas dans le fichier)."""
    rows = [r for r in _read(telemetry_path or DEFAULT_TELEMETRY) if r.get("run_id") == run_id]
    return {
        "run_id": run_id,
        "calls": len(rows),
        "total_tokens": sum(int(r.get("tokens", 0)) for r in rows),
        "total_duration_s": sum(float(r.get("duration_s", 0.0)) for r in rows),
    }


def tokens_by_successful_step(run_id: str, telemetry_path: Path | None = None) -> dict[str, int]:
    """Dérivée LECTURE SEULE (M1, design imposé §4 — la SEULE métrique nouvelle
    autorisée par cette mission) : tokens par étape RÉUSSIE, pour un run.

    Normalise les lignes HISTORIQUES sans `outcome` (toute la télémétrie
    antérieure à M1 ne portait que des succès, jamais écrite sur un halt) en
    "OK" — rétrocompat, aucune régression sur les analyses déjà en place.
    N'agrège JAMAIS une ligne `outcome == "HALT"` : ce n'est pas une nouvelle
    définition du coût, seulement la ventilation par étape de ce qui existait
    déjà implicitement avant M1 (le fichier ne contenait alors que des OK).
    """
    rows = [r for r in _read(telemetry_path or DEFAULT_TELEMETRY) if r.get("run_id") == run_id]
    out: dict[str, int] = {}
    for r in rows:
        if r.get("outcome", "OK") != "OK":
            continue
        etape = r.get("etape", "?")
        out[etape] = out.get(etape, 0) + int(r.get("tokens", 0))
    return out


# --- Tier 2.5 étape 2 : observabilité du pool de builders (extension connecteur 3) --

def record_builder_run(
    run_id: str,
    *,
    tier: str | None,
    builder_id: str,
    strategy: str,
    duration_s: float,
    oracle_result: str,
    retry_number: int,
    tokens: int,
    cost_usd: float,
    telemetry_path: Path | None = None,
) -> None:
    """Trace UNE tentative s9-build : tier/modèle/stratégie/résultat d'oracle/coût.

    `strategy` ∈ {"tier_attempt", "pool_retry"} — premier essai à ce tier, ou retry
    du pool (Tier 2 #5) au MÊME tier. `oracle_result` = statut réel de s10a-oracle-code
    pour CETTE tentative (OK/FAIL/BLOCKED/""). Best-effort, jamais bloquant.
    """
    _append(
        telemetry_path or DEFAULT_BUILDER_RUNS,
        {
            "task_id": run_id, "tier": tier, "builder_id": builder_id,
            "strategy": strategy, "duration_s": duration_s, "oracle_result": oracle_result,
            "retry_number": retry_number, "tokens_estimated": tokens,
            "cost_estimated": cost_usd, "ts": time.time(),
        },
    )


def pool_stats(run_id: str, telemetry_path: Path | None = None) -> dict:
    """Agrège les tentatives s9-build d'un run : ce que le pool a réellement fait.

    - `pool_saves` : nb de retries du pool (Tier 2 #5) qui ont fini par OK — une
      tâche que l'escalade de modèle (plus chère) n'a pas eu besoin de traiter.
    - `escalations_avoided_cost_usd` : coût des tentatives pool_retry réussies —
      un ordre de grandeur de ce qu'une escalade aurait coûté en plus si le pool
      n'existait pas (approximation : pas un contrefactuel exact).
    - `by_tier` : {tier: {"OK":n, "FAIL":n, "BLOCKED":n}} — QUEL TIER réussit, sur CE
      run. C'est l'agrégat FIABLE : le champ `tier` du journal est normalisé à
      l'écriture par `escalate.tier_of` (haiku/sonnet/opus).
    - `by_builder` : même comptage, mais clé sur `builder_id` BRUT — à ne pas utiliser
      pour conclure. Constat mesuré sur les données réelles du 2026-07-23 :
      `builder_id` vaut `model_override or s9_detail["model"]` (driver.py ~l.997),
      donc l'identifiant COMPLET du registry à la 1re tentative
      (`claude-haiku-4-5-20251001`) et le nom COURT après escalade (`sonnet`, `opus`)
      — un même tier apparaît sous deux clés. Champ conservé tel quel (c'est la donnée
      telle qu'elle a été écrite, on ne réécrit pas l'histoire), mais tout comptage
      « quel builder échoue toujours » doit passer par `by_tier`.
    """
    rows = [r for r in _read(telemetry_path or DEFAULT_BUILDER_RUNS) if r.get("task_id") == run_id]
    pool_rows = [r for r in rows if r.get("strategy") == "pool_retry"]
    pool_saves = sum(1 for r in pool_rows if r.get("oracle_result") == "OK")
    saved_cost = sum(float(r.get("cost_estimated", 0.0)) for r in pool_rows if r.get("oracle_result") == "OK")

    by_builder: dict[str, dict[str, int]] = {}
    by_tier: dict[str, dict[str, int]] = {}
    for r in rows:
        res = r.get("oracle_result") or "UNKNOWN"
        b = by_builder.setdefault(r.get("builder_id", "?"), {})
        b[res] = b.get(res, 0) + 1
        # `tier` est écrit normalisé ; une vieille ligne sans ce champ retombe sur
        # "inconnu" plutôt que de polluer un tier réel avec un identifiant brut.
        t = by_tier.setdefault(r.get("tier") or "inconnu", {})
        t[res] = t.get(res, 0) + 1

    return {
        "run_id": run_id,
        "attempts": len(rows),
        "pool_saves": pool_saves,
        "escalations_avoided_cost_usd": saved_cost,
        "by_tier": by_tier,
        "by_builder": by_builder,
    }


# --- Connecteur 6 : journal d'erreurs + pré-mortem -----------------------------

# Scope d'une leçon TRANSVERSALE (méthode), lue au pré-mortem de TOUT projet.
# Paie la dette #1 (silo par projet) : la leçon « oracle doit tester la solvabilité »
# apprise sur un jeu doit atteindre les suivants.
GLOBAL_SCOPE = "_global_"

# Domaines de journal connus (extensible : ajouter une entrée suffit). Chaque domaine
# a son propre fichier error_journal/<domaine>.jsonl. `GLOBAL_SCOPE` est un domaine à
# part entière : les leçons de MÉTHODE transversales y vivent et sont lues quel que
# soit le domaine demandé.
KNOWN_DOMAINS: list[str] = ["html", "python", "rust", "godot", "forge", "playtest", GLOBAL_SCOPE]

# Domaines pour lesquels on lit AUSSI le monolithe historique en fallback. Ses vraies
# entrées sont TOUTES des jeux HTML (collect_runner/breakout/shmup) : on ne les rejoue
# que pour un run html/forge, JAMAIS pour un run rust/godot (sinon on polluerait un run
# d'un autre domaine avec des leçons hors-sujet). Choix NON-DESTRUCTIF : fallback-lecture
# plutôt que migration ponctuelle du fichier (voir note de migration dans premortem).
LEGACY_FALLBACK_DOMAINS: frozenset[str] = frozenset({"html", "forge"})

# Domaine par défaut d'un run Forge quand aucun n'est précisé. `forge` = plomberie de
# la boucle elle-même (contrats, oracles, driver) — cohérent avec l'ancien défaut.
DEFAULT_DOMAIN = "forge"

# Domaine dédié aux retours de playtest Pierre (R2, FORGE_V2_CONSOLIDATION.md §4-A).
# Servi comme GLOBAL_SCOPE — TOUJOURS lu au pré-mortem, quel que soit le `domain`
# demandé par l'appelant (voir `premortem`) : un retour de playtest ne doit jamais
# dépendre du domaine (html/forge/rust/godot...) du run qui consulte, sinon il
# s'évapore silencieusement (constat P6 : 0 fichier de playtest, jamais consigné).
PLAYTEST_DOMAIN = "playtest"


def _domain_journal_path(domain: str) -> Path:
    """Chemin du journal d'un domaine sous error_journal/<domaine>.jsonl."""
    return DOMAIN_JOURNAL_DIR / f"{domain}.jsonl"


def record_error(
    run_id: str,
    etape: str,
    error: str,
    project: str,
    journal_path: Path | None = None,
    resolution: str | None = None,
    domain: str = DEFAULT_DOMAIN,
) -> None:
    """Journalise une erreur/finding red-team d'un run (best-effort, non bloquant).

    2 colonnes : l'échec (`error`) ET, si connue, sa réparation (`resolution` — la
    « 2e colonne » : COMMENT on a réparé). Une entrée avec `resolution` non vide est
    marquée ``status="fixed"`` ; sans, ``status="open"``. Ces deux champs sont
    RÉTROCOMPATIBLES : les entrées historiques du journal (sans `resolution`/`status`)
    restent lisibles telles quelles par `premortem`.

    Routage : `domain` route vers error_journal/<domain>.jsonl (isolation par nature de
    cible). Un `journal_path` EXPLICITE PRIME toujours sur le routage par domaine — c'est
    la garantie de rétrocompat : les appels existants qui passent `journal_path=` écrivent
    exactement où avant, `domain` est simplement ignoré dans ce cas.
    """
    target = journal_path or _domain_journal_path(domain)
    _append(
        target,
        # `date` = date LISIBLE ISO (recherche/tri/purge humaine, ex. « voir les fixes
        # d'il y a un an ») ; `ts` = timestamp machine conservé pour l'ordre exact.
        {"run_id": run_id, "etape": etape, "project": project, "error": error,
         "resolution": resolution, "status": "fixed" if resolution else "open",
         "date": datetime.now().isoformat(timespec="seconds"), "ts": time.time()},
    )


def record_fix(
    run_id: str,
    etape: str,
    error: str,
    resolution: str,
    project: str,
    journal_path: Path | None = None,
    domain: str = DEFAULT_DOMAIN,
) -> None:
    """Consigne en UNE entrée l'erreur ET sa réparation — la « 2e colonne ».

    À utiliser quand un échec d'étape a été RÉPARÉ dans le run : le journal apprend
    ainsi la RÉPARATION (pas seulement l'échec), et le pré-mortem du run suivant peut
    surfacer « voici comment on a corrigé ce problème la dernière fois ». Équivaut à
    `record_error(..., resolution=resolution)` : `status="fixed"`, `resolution` renseigné.
    `domain` route comme dans `record_error` ; `journal_path` explicite prime.
    """
    record_error(run_id, etape, error, project, journal_path=journal_path,
                 resolution=resolution, domain=domain)


def record_playtest(
    project: str,
    constat: str,
    regle_observable: str,
    run_id: str = "playtest",
    journal_path: Path | None = None,
) -> None:
    """Capture un playtest Pierre (R2, FORGE_V2_CONSOLIDATION.md §4-A) : `constat`
    (ce qui a été observé en jeu) -> `regle_observable` (la contrainte que le run
    SUIVANT doit respecter). Avant R2, un retour de playtest était une conversation
    qui s'évaporait (0 fichier — constat P6). Ce helper route CE type de
    connaissance vers le canal DÉJÀ prouvé (error_journal + pré-mortem, card_engine)
    plutôt que d'inventer un nouveau mécanisme : réutilise `record_error` (même
    signature, mêmes garanties best-effort), domaine dédié `PLAYTEST_DOMAIN`.

    `regle_observable` est passée comme `resolution` de `record_error` : la 2e
    colonne du journal (affichée « → ✅ RÉPARÉ: <règle> » par `_format_entry`) porte
    ainsi la contrainte actionnable, pas seulement le constat — exactement le
    mécanisme déjà prouvé pour une réparation d'erreur, réutilisé tel quel pour un
    playtest (même esprit que `record_fix`).
    """
    record_error(
        run_id, "playtest", constat, project,
        journal_path=journal_path, resolution=regle_observable, domain=PLAYTEST_DOMAIN,
    )


def record_global_lesson(etape: str, lesson: str, journal_path: Path | None = None) -> None:
    """Consigne une leçon de MÉTHODE transversale (lue au pré-mortem de tout projet).

    Écrit dans le domaine `_global_` (error_journal/_global_.jsonl) : ces leçons sont
    relues quel que soit le domaine demandé au pré-mortem. `journal_path` explicite prime.
    """
    record_error("_method_", etape, lesson, GLOBAL_SCOPE,
                 journal_path=journal_path, domain=GLOBAL_SCOPE)


def _format_entry(row: dict, prefix: str = "") -> str:
    """Ligne de pré-mortem pour une entrée de journal, réparation incluse si connue.

    Tolère les vieilles entrées SANS clé `resolution`/`status` (accès via .get). Une
    résolution non vide ajoute « → ✅ RÉPARÉ: <resolution> » (la 2e colonne).
    """
    base = f"{prefix}[{row.get('etape')}] {row.get('error')}"
    resolution = row.get("resolution")
    if resolution:
        return f"{base} → ✅ RÉPARÉ: {resolution}"
    return base


def premortem(
    project: str,
    domain: str | None = None,
    journal_path: Path | None = None,
    limit: int = 5,
) -> list[str]:
    """Erreurs du projet + leçons GLOBALES de méthode — lu à l'étape 0 (« PILOU »).

    Les leçons globales (préfixées ⚑) circulent vers TOUS les projets, ce qui ferme
    le silo par projet : un enseignement appris ailleurs n'est plus perdu ici. Quand
    une entrée porte une réparation (`resolution`), le pré-mortem la fait apparaître
    (« → ✅ RÉPARÉ: … ») pour que le run suivant apprenne la RÉPARATION, pas juste
    l'échec. Les vieilles entrées sans `resolution`/`status` restent surfacées inchangées.

    Deux modes :
    - `journal_path` fourni → mode RÉTROCOMPAT : lit ce SEUL fichier (projet + global
      dedans), comportement identique à l'ancien pré-mortem. `domain` est ignoré.
    - `journal_path=None` → mode DOMAINE : lit TOUJOURS le journal `_global_` (leçons
      transversales) PLUS, si `domain` est fourni, le journal de ce domaine (entrées du
      `project`). Pour un domaine à fallback (html/forge) ET pour les leçons globales, on
      relit AUSSI le monolithe historique (NON-DESTRUCTIF) afin de ne perdre aucune leçon
      déjà accumulée. Un run rust/godot ne voit jamais les vieilles leçons html du monolithe.

    Note de migration (choix assumé) : FALLBACK-LECTURE, pas migration ponctuelle. Le
    monolithe `forge_error_journal.jsonl` reste intact et lisible ; on ne le réécrit ni ne
    le déplace. Avantage : zéro risque de perte/corruption de données réelles, réversible.
    Coût : une lecture de plus pour les domaines html/forge — négligeable.
    """
    if journal_path is not None:
        rows = _read(journal_path)
        proj = [r for r in rows if r.get("project") == project]
        glob = [r for r in rows if r.get("project") == GLOBAL_SCOPE]
        out = [_format_entry(r, prefix="⚑ ") for r in glob[-limit:]]
        out += [_format_entry(r) for r in proj[-limit:]]
        return out

    # Mode domaine : leçons globales (journal dédié + fallback monolithe global).
    glob = list(_read(_domain_journal_path(GLOBAL_SCOPE)))
    glob += [r for r in _read(DEFAULT_ERROR_JOURNAL) if r.get("project") == GLOBAL_SCOPE]

    proj: list[dict] = []
    if domain is not None:
        proj += [r for r in _read(_domain_journal_path(domain)) if r.get("project") == project]
        if domain in LEGACY_FALLBACK_DOMAINS:
            proj += [r for r in _read(DEFAULT_ERROR_JOURNAL) if r.get("project") == project]

    # R2 : le domaine `playtest` est TOUJOURS servi (même traitement que
    # GLOBAL_SCOPE) — le driver n'appelle premortem qu'avec UN SEUL domaine à la
    # fois (ForgeDriver._domain -> "html" ou "forge"), donc sans cet ajout un
    # retour de playtest resterait filtré hors de la vue du run suivant et
    # s'évaporerait quand même. Pas de double-lecture si `playtest` est déjà le
    # domaine explicitement demandé.
    if domain != PLAYTEST_DOMAIN:
        proj += [r for r in _read(_domain_journal_path(PLAYTEST_DOMAIN)) if r.get("project") == project]

    out = [_format_entry(r, prefix="⚑ ") for r in glob[-limit:]]
    out += [_format_entry(r) for r in proj[-limit:]]
    return out


# --- Index des journaux par domaine (déterministe, non-LLM) --------------------

INDEX_FILENAME = "INDEX.generated.md"


def _count_entries(path: Path) -> int:
    """Nombre de lignes JSON non vides d'un journal (0 si absent)."""
    return len(_read(path))


def list_journals(reports_dir: Path | None = None) -> list[dict]:
    """Index léger des journaux par domaine : un dict par domaine, trié par nom.

    Recense les `KNOWN_DOMAINS` PLUS tout autre `error_journal/*.jsonl` déjà présent
    (domaines ajoutés sans toucher au code). `reports_dir` = racine des rapports (défaut
    `EVIDENCE/reports`) ; le sous-dossier `error_journal/` en est déduit — pratique pour isoler
    dans un tmp_path de test. Chaque entrée : {domaine, chemin(str), entries(int), existe(bool)}.
    """
    root = reports_dir or FORGE_REPORTS
    jdir = root / "error_journal"

    domaines = set(KNOWN_DOMAINS)
    if jdir.exists():
        domaines.update(p.stem for p in jdir.glob("*.jsonl"))

    out: list[dict] = []
    for domaine in sorted(domaines):
        path = jdir / f"{domaine}.jsonl"
        out.append({
            "domaine": domaine,
            "chemin": str(path),
            "entries": _count_entries(path),
            "existe": path.exists(),
        })
    return out


def generate_journal_index(reports_dir: Path | None = None) -> str:
    """Rend l'index des journaux en Markdown DÉTERMINISTE (aucun horodatage).

    Sortie stable à contenu constant : ré-générable au pré-commit sans diff parasite.
    Le monolithe historique est signalé en note (lu en fallback, jamais réécrit).
    """
    lignes = ["# Journaux d'erreurs Forge par domaine", ""]
    lignes.append("| domaine | entries | existe | chemin |")
    lignes.append("|---|---:|:---:|---|")
    for j in list_journals(reports_dir):
        existe = "oui" if j["existe"] else "non"
        lignes.append(f"| {j['domaine']} | {j['entries']} | {existe} | {j['chemin']} |")
    lignes.append("")
    lignes.append("> Note : `forge_error_journal.jsonl` (monolithe historique) est lu en "
                  "fallback pour les domaines html/forge et jamais réécrit (migration "
                  "non-destructive).")
    lignes.append("")
    return "\n".join(lignes)


def write_journal_index(reports_dir: Path | None = None) -> Path:
    """Écrit l'index Markdown dans error_journal/INDEX.generated.md. Renvoie le chemin."""
    root = reports_dir or FORGE_REPORTS
    jdir = root / "error_journal"
    jdir.mkdir(parents=True, exist_ok=True)
    path = jdir / INDEX_FILENAME
    path.write_text(generate_journal_index(reports_dir), encoding="utf-8")
    return path


# --- Project Bible : mémoire de DÉCISION par projet (persistante entre runs) ----

# Où vit la bible d'un projet : à côté de son state.json, dans le run_dir stable par
# projet. C'est une mémoire de RÉFÉRENCE — un agent ne l'écrit jamais (il PROPOSE via
# propose_bible_entry ; Pierre ratifie). Le lecteur ci-dessous est branché en s0
# (mandatory_read) : la vision cesse d'être reconstruite à zéro à chaque run.

BIBLE_FILENAME = "PROJECT_BIBLE.md"


def project_bible(project: str, runs_root: Path | None = None) -> str:
    """Texte de la Project Bible d'un projet, ou "" si aucune (jamais une exception).

    Lu par l'étape 0 (s0-contrat) pour injecter vision/piliers/décisions validées et
    ABANDONNÉES (+ raisons) du projet dans le cadrage du run suivant. Absent = "" :
    un projet neuf n'a pas encore de bible, ce n'est pas une erreur.
    """
    path = (runs_root or FORGE_RUNS) / project / BIBLE_FILENAME
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def propose_bible_entry(
    project: str,
    kind: str,
    decision: str,
    rationale: str,
    proposals_path: Path | None = None,
) -> dict:
    """Propose une entrée de Project Bible issue d'un run. PROPOSE-ONLY.

    N'écrit JAMAIS la bible de référence : dépose une proposition que Pierre promeut
    (HumanGate) dans `EVIDENCE/runs/<projet>/PROJECT_BIBLE.md`. `kind` ∈
    {"validated","abandoned"} — une décision actée, ou une voie écartée + sa raison
    (la mémoire la plus précieuse : empêche un run futur de re-proposer un cul-de-sac).
    """
    if kind not in ("validated", "abandoned"):
        raise ValueError(f"kind doit valoir 'validated' ou 'abandoned', reçu {kind!r}")
    record = {
        "project": project,
        "kind": kind,
        "decision": decision,
        "rationale": rationale,
        "status": "PROPOSED",
        "ts": time.time(),
    }
    _append(proposals_path or DEFAULT_BIBLE_PROPOSALS, record)
    logger.info("proposition Project Bible déposée (%s) pour %s", kind, project)
    return record


# --- Le dépositaire : proposition de brique (PROPOSE-ONLY, jamais d'auto-write) -

# Défaut d'origine (audit 2026-07-23) : un jeu forgé n'a AUCUN moyen de déposer une brique
# dans la bibliothèque — `propose_bible_entry`/`propose_ledger_entry`/`propose_project_record`
# existent, `propose_brick` non. Le contrat du forgeron interdit d'écrire `catalog.json`
# directement (propose-only) et personne d'autre n'a le devoir de déposer : la flèche
# « un jeu dépose une brique » n'existait dans aucun code. Ratification Pierre 2026-07-23
# (« réciprocité dure + construire le dépositaire ») : PROPOSE en JSONL, Pierre PROMEUT à la
# main dans catalog.json. Patron repris à l'identique de `propose_bible_entry` ci-dessus —
# aucun mécanisme neuf.

def propose_brick(
    run_id: str,
    project: str,
    brick_id: str,
    kind: str,
    function: str,
    path: str,
    proposals_path: Path | None = None,
) -> dict:
    """Propose un dépôt de brique issue d'un run. PROPOSE-ONLY.

    N'écrit JAMAIS `knowledge_base/catalog.json` : dépose une proposition que Pierre
    promeut (HumanGate) dans le catalogue. Champs minimaux pour qu'un humain puisse
    évaluer et promouvoir honnêtement — PAS tout le schéma BRICK_SPEC (kb-validate.mjs) :
    `dependencies`/`parameters`/`genre_compatible`/`invariants`/`tests`/`sha256`/`affordances`/
    `tier` restent à la charge de Pierre au moment de la promotion, une fois le code relu.

    - `brick_id` : identifiant candidat (Pierre peut le renommer en promouvant).
    - `kind` : ∈ {"system","pattern","template"} (BRICK_SPEC::kind).
    - `function` : description courte d'une phrase — ce que la brique fait.
    - `path` : chemin RÉEL du code produit par le run (relatif au repo), la preuve que la
      brique existe déjà sur disque, pas une intention.
    """
    record = {
        "type": "brick",
        "brick_id": brick_id,
        "run_id": run_id,
        "project": project,
        "kind": kind,
        "function": function,
        "path": path,
        "status": "PROPOSED",
        "ts": time.time(),
    }
    _append(proposals_path or DEFAULT_BRICK_PROPOSALS, record)
    logger.info("proposition de brique déposée (%s) pour %s", brick_id, project)
    return record


# --- Connecteur 7 : proposition d'extension du registre de capacités -----------
# (PROPOSE-ONLY, jamais d'auto-write de capabilities.yaml — cf. commentaire de
# DEFAULT_CAPABILITY_GAP_PROPOSALS ci-dessus)

def propose_capability_gap(
    run_id: str,
    project: str,
    capability_id: str,
    source_line_id: str,
    proposals_path: Path | None = None,
    factory_namespaces: tuple[str, ...] | list[str] | None = None,
    factory_proposals_path: Path | None = None,
) -> dict:
    """Propose l'ajout d'une capacité au registre fermé `capabilities.yaml`. PROPOSE-ONLY.

    ROUTAGE PRODUIT / USINE (décision Pierre 2026-08-10, option b). Un identifiant
    dont l'espace de noms figure dans `factory_namespaces` part dans la file USINE
    (`forge_factory_capability_gap_proposals.jsonl`), jamais dans la file PRODUIT :
    Pierre arbitre des capacités de JEU dans celle-ci, et mélanger les deux la rend
    illisible (mesuré sur pacman : 8 identifiants d'usine pour 67 de jeu).

    Les préfixes ne sont PAS codés en dur ici : ils viennent du champ structuré
    `namespaces` de `factory_capabilities.yaml` (règle « aucune décision dans un
    commentaire », ratifiée 2026-07-23). `factory_namespaces` absent => aucun
    routage, tout part en produit — comportement d'avant, strictement.

    LIMITE ASSUMÉE : le routage se fait sur le NOM. Une préoccupation d'usine mal
    nommée (`game.debug_state` de Tetris, avant son renommage) part en produit. Le
    tri final reste humain, à la promotion — ce mécanisme réduit le bruit, il ne
    remplace pas l'arbitrage.

    Le `record` déposé est IDENTIQUE dans les deux files (même schéma, même `type`) :
    seule la destination change. Un lecteur n'a donc rien de spécial à apprendre.

    N'écrit JAMAIS `forge/standard/capabilities.yaml` : dépose une proposition
    que Pierre promeut (HumanGate) — un `statement` (phrase humaine décrivant ce que la
    capacité FAIT) ne peut pas être inventé mécaniquement, exactement la même limite
    honnête que `kb_proposal._lesson_to_pattern_entry` pose sur `provenance_url`.

    - `capability_id` : l'identifiant absent du registre (ex. "game.gravity"),
      extrait de `identifiants_inconnus[i]` (format "<line_id>:<capability_id>",
      cf. `check_collisions`).
    - `source_line_id` : la ligne de wiremap qui a déclaré cet identifiant (le
      "<line_id>" du même couple) — trace la provenance réelle, jamais fabriquée.

    Idempotent par construction du lecteur (pending_review.mjs agrège par
    `capability_id` + `ts` comme les autres files) : rejouer un run qui referait
    surface le même manque redépose une ligne, jamais une perte silencieuse — la
    dernière proposition PROPOSED pour un `capability_id` donné est celle qui compte.
    """
    record = {
        "type": "capability_gap",
        "capability_id": capability_id,
        "source_line_id": source_line_id,
        "run_id": run_id,
        "project": project,
        "status": "PROPOSED",
        "ts": time.time(),
        "note": (
            f"identifiant '{capability_id}' absent de forge/standard/"
            f"capabilities.yaml, déclaré par la ligne wiremap '{source_line_id}' "
            f"(check_collisions, run {run_id}) — registre conçu pour grandir "
            "d'un jeu à l'autre (en-tête capabilities.yaml) ; statement à "
            "rédiger par Pierre au moment de la promotion."
        ),
    }
    prefixes = tuple(
        p for p in (factory_namespaces or ()) if isinstance(p, str) and p.strip()
    )
    is_factory = bool(prefixes) and capability_id.startswith(prefixes)
    if is_factory:
        target = factory_proposals_path or DEFAULT_FACTORY_CAPABILITY_GAP_PROPOSALS
    else:
        target = proposals_path or DEFAULT_CAPABILITY_GAP_PROPOSALS
    _append(target, record)
    logger.info(
        "proposition d'extension de capacité déposée (%s, file %s) pour %s",
        capability_id, "USINE" if is_factory else "PRODUIT", project,
    )
    return record


# --- Connecteur 4 : proposition ledger (AUDIT_REQUIRED, jamais d'auto-write) ----

def propose_ledger_entry(
    run_id: str,
    project: str,
    verdict: dict,
    proposals_path: Path | None = None,
) -> dict:
    """Propose une entrée ledger issue d'un run Forge. PROPOSE-ONLY, lane AUDIT_REQUIRED.

    N'écrit JAMAIS le ledger : dépose une proposition que Pierre promeut via HumanGate.
    """
    # Signal de promotion CANONIQUE : software_verdict seul ne distingue pas un OK
    # propre d'un OK-avec-objection (survivant trié = software OK mais decision
    # WITH_OBJECTION). La proposition transporte `clean_pass` pour qu'un promoteur
    # futur ne clé JAMAIS sur software_verdict seul. Import local : évite tout cycle.
    from forge.verdict import is_clean_pass
    record = {
        "run_id": run_id,
        "project": project,
        "lane": "AUDIT_REQUIRED",
        "status": "PROPOSED",
        "software_verdict": verdict.get("software_verdict"),
        "decision": verdict.get("decision"),
        "clean_pass": is_clean_pass(verdict),
        "evidence_verdict": verdict.get("evidence_verdict"),
        "claim_verdict": verdict.get("claim_verdict", "NO_CLAIM_ALLOWED"),
        "ts": time.time(),
    }
    _append(proposals_path or DEFAULT_LEDGER_PROPOSALS, record)
    logger.info("proposition ledger déposée (AUDIT_REQUIRED) pour run %s", run_id)
    return record


# --- Connecteur 5 : proposition projet (jamais d'auto-write de la liste) --------

def propose_project_record(
    project: str,
    stage: str,
    folder: str,
    proposals_path: Path | None = None,
) -> dict:
    """Propose l'enregistrement/MAJ d'un projet forgé. PROPOSE-ONLY.

    N'écrit JAMAIS la liste des projets de référence : dépose une proposition.
    """
    record = {"project": project, "stage": stage, "folder": folder,
              "status": "PROPOSED", "ts": time.time()}
    _append(proposals_path or DEFAULT_PROJECT_PROPOSALS, record)
    return record


# --- CLI : index des journaux + entrées d'écriture humaine ---------------------
#
# `record_playtest` / `record_global_lesson` / `propose_bible_entry` ont un
# consommateur prouvé (error_journal relu par `premortem`, injecté au prompt de
# l'étape suivante — ou `pending_review.mjs` pour la bible) mais AUCUN appelant :
# consigner un playtest ou une leçon de méthode est un acte HUMAIN, il ne peut pas
# être fabriqué par du code. Ces sous-commandes sont l'appelant : un terminal, pas
# de la prose perdue dans un document.
#
# `--write` (comportement PRÉ-EXISTANT) reste inchangé : sans sous-commande, le
# CLI affiche ou écrit l'index des journaux, exactement comme avant ce chantier.


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="CLI Forge studio_link : index des journaux + écritures humaines.")
    parser.add_argument("--write", action="store_true",
                        help="écrit error_journal/INDEX.generated.md (sinon affiche seulement)")
    sub = parser.add_subparsers(dest="cmd")

    p_playtest = sub.add_parser(
        "playtest", help="consigne un playtest Pierre (record_playtest -> error_journal, domaine playtest)")
    p_playtest.add_argument("--project", required=True, help="projet forgé concerné")
    p_playtest.add_argument("--constat", required=True, help="ce qui a été observé en jeu")
    p_playtest.add_argument("--regle-observable", required=True, dest="regle_observable",
                            help="la contrainte que le run SUIVANT doit respecter")
    p_playtest.add_argument("--run-id", default="playtest", help="défaut: 'playtest'")
    p_playtest.add_argument("--journal-path", type=Path, default=None,
                            help="défaut: error_journal/playtest.jsonl")

    p_lesson = sub.add_parser(
        "lesson", help="consigne une leçon GLOBALE de méthode (record_global_lesson -> error_journal, domaine _global_)")
    p_lesson.add_argument("--etape", required=True, help="étape du pipeline concernée (ex. s9-build)")
    p_lesson.add_argument("--lesson", required=True, help="la leçon de méthode, transversale à tout projet")
    p_lesson.add_argument("--journal-path", type=Path, default=None,
                          help="défaut: error_journal/_global_.jsonl")

    p_bible = sub.add_parser(
        "bible", help="propose une entrée de Project Bible (propose_bible_entry -> forge_bible_proposals.jsonl, PROPOSE-ONLY)")
    p_bible.add_argument("--project", required=True, help="projet forgé concerné")
    p_bible.add_argument("--kind", required=True, choices=("validated", "abandoned"),
                         help="décision actée, ou voie écartée + sa raison")
    p_bible.add_argument("--decision", required=True, help="la décision elle-même")
    p_bible.add_argument("--rationale", required=True, help="pourquoi (la mémoire la plus précieuse pour 'abandoned')")
    p_bible.add_argument("--proposals-path", type=Path, default=None,
                         help="défaut: EVIDENCE/reports/forge_bible_proposals.jsonl")

    p_brick = sub.add_parser(
        "brick", help="propose un dépôt de brique (propose_brick -> forge_brick_proposals.jsonl, PROPOSE-ONLY)")
    p_brick.add_argument("--project", required=True, help="projet forgé concerné")
    p_brick.add_argument("--run-id", required=True, help="run qui a produit la brique")
    p_brick.add_argument("--brick-id", required=True, dest="brick_id", help="identifiant candidat de la brique")
    p_brick.add_argument("--kind", required=True, choices=("system", "pattern", "template"),
                         help="BRICK_SPEC::kind (kb-validate.mjs)")
    p_brick.add_argument("--function", required=True, help="description courte : ce que la brique fait")
    p_brick.add_argument("--path", required=True, help="chemin RÉEL du code produit par le run (relatif au repo)")
    p_brick.add_argument("--proposals-path", type=Path, default=None,
                         help="défaut: EVIDENCE/reports/forge_brick_proposals.jsonl")

    p_capgap = sub.add_parser(
        "capability-gap",
        help="propose l'ajout d'une capacité au registre (propose_capability_gap -> "
             "forge_capability_gap_proposals.jsonl, PROPOSE-ONLY)")
    p_capgap.add_argument("--project", required=True, help="projet forgé concerné")
    p_capgap.add_argument("--run-id", required=True, help="run qui a détecté le manque")
    p_capgap.add_argument("--capability-id", required=True, dest="capability_id",
                          help="identifiant absent du registre (ex. game.gravity)")
    p_capgap.add_argument("--source-line-id", required=True, dest="source_line_id",
                          help="ligne de wiremap qui a déclaré cet identifiant")
    p_capgap.add_argument("--proposals-path", type=Path, default=None,
                          help="défaut: EVIDENCE/reports/forge_capability_gap_proposals.jsonl")

    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI : index des journaux (``--write``) + sous-commandes ``playtest`` /
    ``lesson`` / ``bible`` pour les écritures qui n'ont pas d'appelant automatisable.

    Robustesse : `_harden_streams()` est appelée EN PREMIER (console Windows cp1252 —
    un `constat`/`rationale` accentué non représentable levait `UnicodeEncodeError`
    et faussait le code de sortie, incident réel de ce dépôt). Des arguments
    manquants ou invalides ne produisent JAMAIS de trace Python nue ni d'écriture
    partielle : argparse imprime un usage clair sur stderr et sort en code != 0
    *avant* tout appel à une fonction d'écriture (validation puis écriture, jamais
    l'inverse) ; une erreur de validation métier (`kind` invalide en dehors
    d'argparse, ex. appel direct de la fonction) est aussi convertie en code 2,
    jamais une trace Python.
    """
    _harden_streams()
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        # argparse a déjà imprimé un usage clair sur stderr ; on ne fait que
        # convertir son SystemExit en valeur de retour entière (contrat de `main`:
        # toujours un int, jamais une exception qui remonte à l'appelant Python).
        return exc.code if isinstance(exc.code, int) else 2

    if args.cmd == "playtest":
        path = args.journal_path or _domain_journal_path(PLAYTEST_DOMAIN)
        record_playtest(args.project, args.constat, args.regle_observable,
                        run_id=args.run_id, journal_path=args.journal_path)
        print(f"playtest consigné -> {path}")
        return 0

    if args.cmd == "lesson":
        path = args.journal_path or _domain_journal_path(GLOBAL_SCOPE)
        record_global_lesson(args.etape, args.lesson, journal_path=args.journal_path)
        print(f"leçon globale consignée -> {path}")
        return 0

    if args.cmd == "bible":
        path = args.proposals_path or DEFAULT_BIBLE_PROPOSALS
        try:
            propose_bible_entry(args.project, args.kind, args.decision, args.rationale,
                                proposals_path=args.proposals_path)
        except ValueError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(f"proposition Project Bible déposée -> {path}")
        return 0

    if args.cmd == "brick":
        path = args.proposals_path or DEFAULT_BRICK_PROPOSALS
        propose_brick(args.run_id, args.project, args.brick_id, args.kind, args.function, args.path,
                      proposals_path=args.proposals_path)
        print(f"proposition de brique déposée -> {path}")
        return 0

    if args.cmd == "capability-gap":
        path = args.proposals_path or DEFAULT_CAPABILITY_GAP_PROPOSALS
        propose_capability_gap(args.run_id, args.project, args.capability_id, args.source_line_id,
                               proposals_path=args.proposals_path)
        print(f"proposition d'extension de capacité déposée -> {path}")
        return 0

    # Comportement PRÉ-EXISTANT, strictement inchangé (aucune sous-commande donnée).
    if args.write:
        path = write_journal_index()
        logger.info("index des journaux écrit : %s", path)
        print(str(path))
    else:
        print(generate_journal_index())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
