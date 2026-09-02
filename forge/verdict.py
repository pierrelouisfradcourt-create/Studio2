"""Signed forge verdict — the anti-over-claim epistemology brick.

Separates software / evidence / claim. ``claim_verdict`` is ALWAYS
``NO_CLAIM_ALLOWED``: the agent may never assert success. Only the deterministic
oracle speaks (``software_verdict``), and the verdict is HMAC-signed so it cannot
be forged after the fact.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KEY_FILE = REPO_ROOT / "forge" / ".forge_key"

CLAIM_VERDICT = "NO_CLAIM_ALLOWED"
EVIDENCE_VERDICT = "MECHANICAL_VALIDATION_ONLY"

# --- A2 (ratifié Pierre 2026-08-28) : régime de preuve d'EXÉCUTION des spawns ---
# INVARIANT : « une preuve doit provenir du mécanisme qui a réalisé l'action, sinon
# elle est explicitement AUTO_ATTESTED ». Sur le chemin headless (chemin B :
# `run_real._claude_call_raw` -> sous-processus, hors hook PreToolUse), les
# événements `spawn_authorized`/`spawn_executed` sont écrits par le DRIVER LUI-MÊME
# (`ForgeDriver._record_spawn_executed`) : aucun tiers n'observe le spawn. R2-OBS P4
# le dit déjà ligne à ligne (`spawn_links.jsonl`, `attestation: "self"`) ; l'agrégat
# SIGNÉ — le seul artefact que HumanGate lit — n'en disait rien et se présentait
# comme s'il avait été observé de l'extérieur.
# Vocabulaire FERMÉ (même patron que `scope`) : un régime non prévu est une erreur,
# jamais une chaîne libre glissée dans un corps signé.
ATTESTATION_SELF = "self"
EXECUTION_PROOF_ATTESTATIONS = (ATTESTATION_SELF,)
EXECUTION_PROOF_SELF_NOTE = (
    "auto-attesté (chemin B headless) : les événements spawn_authorized/"
    "spawn_executed de ce run ont été écrits par le driver qui exécute les spawns, "
    "aucun observateur tiers ne les a constatés"
)


@dataclass(frozen=True)
class Verdict:
    project: str
    software_verdict: str
    evidence_verdict: str
    claim_verdict: str
    returncode: int
    evidence_path: str


def build_verdict(project: str, passed: bool, returncode: int, evidence_path: Path,
                  timed_out: bool = False) -> Verdict:
    """Verdict d'un oracle — TROIS états, plus deux.

    `"OK" if passed else "FAIL"` répondait avec un booléen à deux états alors que
    `oracle.run_oracle` produit `passed=False` dans deux situations de nature OPPOSÉE :
    l'oracle a JUGÉ et condamné (FAIL légitime), ou il est MORT avant de juger — auquel cas
    rien n'est prouvé, et c'est `BLOCKED`. Quatrième question de la règle ratifiée
    2026-08-17 : « le processus a-t-il rendu un verdict valide ? ».

    Cas réel : bomberman_3d, run `proof3` (c19add3) — TIMEOUT à 300 s, alors que la seule
    mesure ABOUTIE était verte (691 assertions, 0 échec). Le processus est mort pendant la
    solvabilité, dont le budget déclaré (20 essais × 60 s) dépasse structurellement la
    limite. Un `FAIL` y désignait le produit pour une panne de l'instrument.

    `timed_out` est un PARAMÈTRE, jamais un champ de `Verdict` : `sign_verdict` signe
    `asdict(verdict)`, donc tout champ nouveau invaliderait les signatures DÉJÀ ÉMISES. Il
    n'influence que la VALEUR de `software_verdict`. Défaut `False` : un appelant qui
    l'ignore garde exactement l'ancien comportement.
    """
    return Verdict(
        project=project,
        software_verdict="BLOCKED" if timed_out else ("OK" if passed else "FAIL"),
        evidence_verdict=EVIDENCE_VERDICT,
        claim_verdict=CLAIM_VERDICT,
        returncode=returncode,
        evidence_path=canonical_evidence_path(evidence_path),
    )


def _read_key(key_file: Path) -> bytes | None:
    """Lit la clé si elle existe, sinon None. Ne génère JAMAIS (chemin de vérif)."""
    return key_file.read_bytes() if key_file.exists() else None


def _load_key_for_signing(key_file: Path) -> bytes:
    """Chemin de SIGNATURE : lit la clé, ou en génère une au premier usage."""
    existing = _read_key(key_file)
    if existing is not None:
        return existing
    key = os.urandom(32)
    key_file.parent.mkdir(parents=True, exist_ok=True)
    key_file.write_bytes(key)
    logger.info("generated new forge signing key at %s", key_file)
    return key


def _hmac_hex(key: bytes, mapping: dict) -> str:
    payload = json.dumps(mapping, sort_keys=True).encode("utf-8")
    return hmac.new(key, payload, hashlib.sha256).hexdigest()


def _sign_mapping(mapping: dict, key_file: Path | None = None) -> str:
    """HMAC-SHA256 déterministe sur un mapping (JSON trié). Base commune des signatures."""
    return _hmac_hex(_load_key_for_signing(key_file or DEFAULT_KEY_FILE), mapping)


def _verify_mapping(mapping: dict, signature: str, key_file: Path | None = None) -> bool:
    """Vérifie une signature. Clé ABSENTE => False (jamais de génération à la vérif).

    Générer une clé au moment de vérifier reviendrait à fabriquer de la confiance :
    supprimer .forge_key puis re-signer des verdicts forgés les rendrait valides.
    """
    key = _read_key(key_file or DEFAULT_KEY_FILE)
    if key is None:
        logger.warning("verify: clé de signature absente -> refus (aucune génération)")
        return False
    return hmac.compare_digest(_hmac_hex(key, mapping), signature)


def sign_verdict(verdict: Verdict, key_file: Path | None = None) -> str:
    return _sign_mapping(asdict(verdict), key_file)


def verify_verdict(verdict: Verdict, signature: str, key_file: Path | None = None) -> bool:
    return _verify_mapping(asdict(verdict), signature, key_file)


# --- Reçus d'oracle signés (provenance, étape 2) ------------------------------
# Chaque oracle déterministe émet un REÇU signé. L'agrégat VÉRIFIE ces reçus au
# lieu de croire des faits passés en argument : un OK sans reçu valide devient
# impossible sans la clé. Corrige la faille « le verdict signe une narration ».

# SKIPPED : l'oracle n'était pas applicable dans ce profil (ex. archi/wiremap sur
# un profil patch). Le reçu SKIPPED est SIGNÉ comme les autres — sauter est une
# décision assumée et auditable, jamais un trou silencieux.
RECEIPT_STATUSES = ("OK", "FAIL", "BLOCKED", "SKIPPED")


@dataclass(frozen=True)
class OracleReceipt:
    oracle_id: str           # "code" | "archi" | "wiremap"
    run_id: str              # lie le reçu à UN run précis (anti-rejeu inter-run)
    status: str              # OK | FAIL | BLOCKED
    evidence_sha256: str     # hash du contenu d'évidence (scelle le log/artefact jugé)
    detail: dict             # sortie brute de l'oracle (deps violées, features manquantes…)
    ts: float
    evidence_path: str = ""  # chemin du fichier d'évidence — RE-LU à la vérif pour
                             # confronter evidence_sha256 au contenu réel (scellé non décoratif)


@dataclass(frozen=True)
class SignedReceipt:
    receipt: OracleReceipt
    signature: str


def sign_receipt(receipt: OracleReceipt, key_file: Path | None = None) -> str:
    return _sign_mapping(asdict(receipt), key_file)


def verify_receipt(receipt: OracleReceipt, signature: str, key_file: Path | None = None) -> bool:
    return _verify_mapping(asdict(receipt), signature, key_file)


_SCELLABLE_CACHE: dict[str, bool] = {}
SEAL_SKIP_KEY = "evidence_seal"


def evidence_is_sealable(chemin: Path | str) -> bool:
    """Ce fichier peut-il porter un sceau que le DEPOT saura honorer ?

    CRITERE = `.gitignore`, pas une liste d'extensions. Doctrine ratifiee Pierre 2026-08-04
    (POLITIQUE OPTION C) : « un registre versionne qui cite un fichier ignore cree une
    reference que le depot ne peut pas honorer ». Mesure qui l'avait motivee : 57 references
    versionnees vers des fichiers ignores, et 13 x `evidence_missing` sur un clone frais.

    `.gitignore` ENCODE DEJA la distinction preuve/flux, y compris ses exceptions :
        EVIDENCE/runs/**/evidence/oracle_<jeu>.log   IGNORE        -> flux
        EVIDENCE/runs/**/evidence/mutation_*.json    versionnable  -> preuve
        knowledge_base/proofs/*.log                   versionnable  -> exception 2026-07-13
    Le jour ou la politique change, ce code suit sans etre touche. Une liste d'extensions,
    elle, aurait diverge en silence.

    GIT INJOIGNABLE -> True (on scelle), c'est-a-dire le comportement d'AVANT. Sous
    incertitude on ne modifie pas silencieusement un comportement etabli ; l'inverse
    supprimerait des sceaux sans que personne ne l'ait decide.
    """
    import subprocess   # import LOCAL, comme `_git_head` : git reste optionnel ici
    if not chemin:
        return False
    cle = str(chemin)
    if cle in _SCELLABLE_CACHE:
        return _SCELLABLE_CACHE[cle]
    try:
        code = subprocess.run(["git", "check-ignore", "-q", cle],
                              cwd=str(REPO_ROOT), capture_output=True).returncode
        scellable = code != 0          # 0 = ignore, 1 = versionnable, 128 = erreur
        if code not in (0, 1):
            scellable = True
    except OSError:
        scellable = True
    _SCELLABLE_CACHE[cle] = scellable
    return scellable


def make_signed_receipt(
    oracle_id: str, run_id: str, status: str, detail: dict,
    *, evidence_sha256: str = "", evidence_path: str = "", ts: float | None = None,
    key_file: Path | None = None,
) -> SignedReceipt:
    """Construit + signe un reçu d'oracle. Signé par le processus qui a EXÉCUTÉ
    l'oracle ; l'agrégat le re-vérifiera avant de prononcer un verdict.

    `evidence_path` permet à l'agrégat (et à `verify_run`) de RE-LIRE le fichier
    et de confronter `evidence_sha256` à son contenu réel — le scellé n'est plus
    décoratif. Si `evidence_path` est fourni sans `evidence_sha256`, on le calcule.

    RÉPARATION (post-mortem pacman 2026-08-07, lot A réparation 4) : `ts` défaut à
    `None`, jamais à un epoch fixe — un appelant qui omet `ts` obtient l'heure
    RÉELLE de signature (`time.time()`), jamais `0.0` (qui se relit comme 1970 et
    casse toute fenêtre temporelle calculée en aval, ex. Observer). Un appelant qui
    PASSE explicitement `ts=0.0` (aucun cas de production connu, seulement des
    fixtures) obtient toujours `0.0` — ce correctif ne touche que l'OMISSION,
    jamais une valeur explicite. Rétro-compat : un reçu déjà signé avec `ts=0.0`
    reste vérifiable tel quel (`verify_receipt` relit le `ts` stocké, ne le
    recalcule jamais).
    """
    if status not in RECEIPT_STATUSES:
        raise ValueError(f"status de reçu invalide: {status!r}")
    detail = dict(detail or {})
    if evidence_path and not evidence_sha256:
        # OPTION A (ratifiee Pierre 2026-08-20) : on ne scelle QUE ce que le depot peut
        # honorer. Sceller un flux d'exploitation ignore par git produisait une promesse
        # invalide des le clone — 37 recus dans ce cas.
        if evidence_is_sealable(evidence_path):
            # MEME autorite qu a la verification : si la creation resolvait contre le cwd et
            # la verification contre la racine, les deux ne parleraient pas du meme fichier.
            evidence_sha256 = sha256_evidence(evidence_path)
        else:
            # Le MOTIF est pose AVANT le check et VOYAGE avec le recu : un sceau vide sans
            # raison serait indiscernable d'un calcul rate. Motif ratifie 2026-08-17.
            detail[SEAL_SKIP_KEY] = {
                "sealed": False,
                "reason": "FLUX_D_EXPLOITATION_IGNORE_PAR_GIT",
                "evidence_path": str(evidence_path),
            }
    if ts is None:
        ts = time.time()
    receipt = OracleReceipt(
        oracle_id=oracle_id, run_id=run_id, status=status,
        evidence_sha256=evidence_sha256, detail=detail, ts=ts,
        evidence_path=canonical_evidence_path(evidence_path),
    )
    return SignedReceipt(receipt=receipt, signature=sign_receipt(receipt, key_file))


def status_from_passed(passed: bool) -> str:
    """Traduit le booléen d'un oracle statique en statut de reçu."""
    return "OK" if passed else "FAIL"


def resolve_evidence_path(chemin: Path | str) -> Path:
    """Resout un chemin d'evidence CONTRE LA RACINE DU DEPOT, jamais contre le `cwd`.

    DEFAUT MESURE le 2026-08-20 : `sha256_file(receipt.evidence_path)` resolvait un chemin
    RELATIF contre le repertoire courant. Meme recu, meme fichier, deux `cwd` :

        cwd = racine du depot  ->  RESOUT
        cwd = ailleurs         ->  VIDE  (donc « evidence alteree/absente »)

    La validite d'une preuve dependait donc de l'ENDROIT d'ou on la verifiait. Ce n'est pas
    une propriete acceptable pour une preuve.

    Les chemins ABSOLUS sont rendus tels quels : 63 des 90 recus existants en portent un, et
    ce lot ne doit en casser aucun. C'est le TEMPS 1 (lecture) ; rendre la forme STOCKEE
    canonique est le temps 2, avec son rayon d'impact propre.
    """
    p = Path(chemin)
    return p if p.is_absolute() else (REPO_ROOT / p)


def canonical_evidence_path(chemin: Path | str) -> str:
    """Forme CANONIQUE d'un chemin d'evidence : RELATIF a la racine du depot.

    Symetrique de `resolve_evidence_path`. Un chemin absolu sous la racine est ramene a sa
    forme relative POSIX ; un chemin HORS du depot est rendu tel quel — il n'a pas de forme
    relative qui ait un sens, et l'inventer masquerait le fait qu'il est ailleurs.

    POURQUOI STOCKER DU RELATIF. Un chemin absolu porte le nom de compte du poste (63 des 90
    recus mesures), n'a aucun sens sur une autre machine, et contredit la regle du depot
    (« chemins relatifs au repo root, jamais absolus »). Le sceau, lui, ne change pas : il
    porte les OCTETS du fichier, pas son chemin.

    ANCIENS RECUS INTACTS : ce lot ne reecrit AUCUN recu existant. Ils gardent leur forme
    absolue, et `resolve_evidence_path` (temps 1) continue de la lire. C'est precisement ce
    qui rend ce changement sur.
    """
    if not chemin:
        return ""
    p = Path(chemin)
    try:
        return p.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(chemin)


def sha256_evidence(chemin: Path | str) -> str:
    """Sceau d'une evidence DESIGNEE PAR UN RECU — resolution comprise.

    Une seule autorite pour « ou vit une evidence ». Les 3 sites de verification passent par
    ici ; en dupliquer la regle les ferait diverger, defaut deja rencontre plusieurs fois
    dans ce depot.
    """
    return sha256_file(resolve_evidence_path(chemin))


def sha256_file(path: Path | str) -> str:
    """Hash du CONTENU d'un fichier d'évidence (scelle le log). '' si illisible."""
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return ""


def current_git_head() -> str:
    """HEAD courant (best-effort, '' si hors git). Lien anti-rejeu grossier."""
    import subprocess
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(REPO_ROOT),
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def new_nonce() -> str:
    """Nonce unique par verdict (anti-rejeu)."""
    return os.urandom(16).hex()


# --- Verdict AGRÉGÉ (A3 + provenance) : reçus signés -> 1 verdict signé --------

# software_verdict de l'agrégat vient UNIQUEMENT des oracles déterministes VÉRIFIÉS.
# Le red-team est advisory : il lève des flags HumanGate, il ne juge JAMAIS le code.
DECISION_READY = "HUMANGATE_READY"   # oracles verts — prêt pour la revue de Pierre
DECISION_READY_OBJECTION = "HUMANGATE_READY_WITH_OBJECTION"  # oracles verts MAIS objection (red-team OU exception de triage mutation)
DECISION_BLOCKED = "BLOCKED"         # oracle rouge / provenance rompue — la chaîne s'arrête


def is_clean_pass(verdict: dict) -> bool:
    """Prédicat CANONIQUE d'un OK PROPRE — le seul autorisé pour décider une
    promotion. Vrai SSI software_verdict == OK ET decision == HUMANGATE_READY
    (ÉGALITÉ STRICTE) ET aucun humangate_flag.

    Ferme le footgun : ``HUMANGATE_READY`` est un PRÉFIXE de
    ``HUMANGATE_READY_WITH_OBJECTION`` — un ``startswith``/``in`` promouvrait un
    OK-avec-objection. Un consommateur ne doit JAMAIS dériver « propre » de
    software_verdict seul : un survivant mutation trié reste software_verdict=OK
    mais decision=WITH_OBJECTION. Ne décide PAS le merge (c'est Pierre) —
    empêche seulement de confondre OK-avec-réserve et OK-propre. NO_CLAIM_ALLOWED.

    Point d'entrée d'audit de consommation (à rejouer quand un consommateur est
    ajouté) : `grep -rn 'software_verdict.*==.*OK'` — chaque occurrence qui décide
    une promotion DOIT passer par ce prédicat, jamais par software_verdict seul.
    """
    if not isinstance(verdict, dict):
        return False
    return (
        verdict.get("software_verdict") == "OK"
        and verdict.get("decision") == DECISION_READY   # strict, jamais startswith/in
        and not verdict.get("humangate_flags")
        # P2 : un verdict de périmètre PARTIEL n'est JAMAIS un passage propre —
        # défaut "FULL" pour les verdicts historiques (champ absent = chaîne s12).
        and verdict.get("scope", "FULL") == "FULL"
    )


def _mutation_triage_exception(code_receipt) -> tuple[bool, list]:
    """Le reçu code embarque-t-il une preuve mutation avec EXCEPTION DE TRIAGE ?

    Doctrine P0.3 : un mutant survivant trié franchit le gate mutation mais reste
    une exception — jamais un OK propre. Cette info voyage dans le detail signé du
    reçu mutation (embarqué par le driver dans le reçu code) ; on la lit du reçu
    DÉJÀ VÉRIFIÉ (provenance intacte). Retourne (exception, triaged_survivors)."""
    if code_receipt is None:
        return (False, [])
    mut = (code_receipt.detail or {}).get("mutation")
    if not isinstance(mut, dict):
        return (False, [])
    mdetail = (mut.get("receipt") or {}).get("detail") or {}
    return (bool(mdetail.get("mutation_exception")), list(mdetail.get("triaged_survivors", [])))


def _red_facets(detail: dict) -> list[str]:
    """Noms des VOLETS rouges d'un reçu multi-volets (ex. les six oracles du STANDARD,
    dont le detail est {volet: {passed: bool, ...}}). Sert uniquement à rendre le flag
    HumanGate CITABLE (« standard rouge: ['placement', 'index'] ») au lieu d'un
    « violation » opaque. Ne juge rien : le statut vient du reçu signé, pas d'ici.
    [] si le detail n'a pas cette forme (archi/wiremap) -> le message générique reste."""
    if not isinstance(detail, dict):
        return []
    return sorted(
        k for k, v in detail.items()
        if isinstance(v, dict) and "passed" in v and not v.get("passed")
    )


@dataclass(frozen=True)
class AggregateVerdict:
    project: str
    run_id: str
    # INVARIANT : software_verdict n'est PAS un contrat de promotion. Un OK peut
    # porter une objection (decision=WITH_OBJECTION) ou des flags. Le SEUL prédicat
    # de passage propre est is_clean_pass() — ne jamais promouvoir sur ce champ seul.
    software_verdict: str            # OK | FAIL | BLOCKED — ORACLES VÉRIFIÉS SEULS
    evidence_verdict: str            # MECHANICAL_VALIDATION_ONLY
    claim_verdict: str               # NO_CLAIM_ALLOWED
    decision: str                    # HUMANGATE_READY | BLOCKED (jamais 'merge' — c'est Pierre)
    oracles: dict                    # {code, archi, wiremap[, standard]} -> reçus (dict) dont la provenance est vérifiée
    redteam_reviewer: str            # identité RÉELLE (A2) : qwen2.5-14b-instruct | claude-blind (fallback)
    redteam_ran: bool                # le reviewer INDÉPENDANT a-t-il réellement tourné ? (structuré, pas sniff de string)
    provenance_ok: bool = True       # tous les reçus vérifiés (signature + run_id concordant)
    git_head: str = ""               # anti-rejeu : état du code jugé
    nonce: str = ""                  # anti-rejeu : unicité par verdict
    ts: float = 0.0
    redteam_advisory: tuple = ()     # findings red-team (advisory — n'affectent pas software_verdict)
    humangate_flags: tuple = ()      # points à signaler à Pierre (fog)
    # P2 (2026-08-15) : périmètre de l'agrégat. FULL = chaîne s12 complète
    # (comportement historique, défaut — les verdicts antérieurs, sans ce champ,
    # restent vérifiables tels quels : le HMAC re-signe le mapping STOCKÉ).
    # PARTIAL = profil sans s12 (probes, oracle_only…) : le verdict ne couvre QUE
    # les oracles réellement exécutés ; jamais HUMANGATE_READY, jamais clean pass.
    scope: str = "FULL"
    # Lot 1 ADR-003 (P0-2, 2026-08-15) : la « game-ness » devient un fait DÉCLARÉ
    # et SIGNÉ par le producteur du verdict (le driver passe self.is_game), au lieu
    # d'être uniquement INFÉRÉE par verify_run depuis des clés FACULTATIVES du
    # detail du reçu code (e2e/mutation/solvability) — inférence qu'une recette de
    # verdict minimale ({"returncode": ...}) désarmait silencieusement : le jeu
    # passait AUTHENTIQUE sans preuve mutation, en se faisant classer « non-jeu ».
    # None = verdict historique / producteur qui ne déclare pas (rétro-compat :
    # verify_run garde l'inférence en filet). verify_run traite is_game=True sans
    # preuve mutation embarquée comme un REJET, plus jamais comme un non-jeu.
    is_game: bool | None = None
    # A2 (2026-08-28) : RÉGIME DE PREUVE de l'exécution des spawns de ce run.
    # `"self"` = auto-attesté (le mécanisme qui exécute écrit lui-même sa preuve,
    # cf. ATTESTATION_SELF) ; `None` = non déclaré (verdict historique, ou
    # producteur tiers qui ne se prononce pas — jamais un régime supposé).
    # N'entre dans AUCUN calcul : software_verdict, decision et humangate_flags
    # sont strictement inchangés. C'est un fait de PROVENANCE, signé avec le
    # verdict (donc infalsifiable après coup), lisible par HumanGate.
    execution_proof_attestation: str | None = None
    execution_proof_note: str = ""      # dérivé du régime, jamais saisi par l'appelant


def build_aggregate_verdict(
    project: str,
    run_id: str,
    code: SignedReceipt,
    archi: SignedReceipt,
    wiremap: SignedReceipt,
    redteam_reviewer: str,
    *,
    redteam_ran: bool,
    redteam_findings: Sequence[str] = (),
    redteam_blocked: bool = False,
    extra_advisory: Sequence[str] = (),
    standard: SignedReceipt | None = None,
    git_head: str = "",
    nonce: str = "",
    ts: float | None = None,
    key_file: Path | None = None,
    scope: str = "FULL",
    is_game: bool | None = None,
    execution_proof_attestation: str | None = None,
) -> AggregateVerdict:
    """Plie les REÇUS D'ORACLE SIGNÉS + le red-team en un verdict signable.

    RÉPARATION (post-mortem pacman 2026-08-07, lot A réparation 4) : `ts` défaut à
    `None` — un appelant qui l'omet obtient `time.time()` au moment de l'agrégation,
    jamais `0.0` (voir `make_signed_receipt` pour la même garantie côté reçu). Mesuré
    sur `EVIDENCE/runs/pacman/verdict.json` : `ts: 0.0` au sommet ET sur les trois
    reçus — un chemin d'écriture (hors `ForgeDriver`, jamais localisé avec certitude,
    cf. rapport) a construit ce verdict sans passer `ts`. Ce correctif ferme le trou
    à la source plutôt qu'au seul appelant connu (`ForgeDriver._run_verdict`, qui
    passait déjà `ts=time.time()` explicitement). Rétro-compat : `verify_aggregate`
    relit le `ts` stocké dans le JSON, ne le recalcule jamais — un verdict historique
    à `ts=0.0` reste vérifiable tel quel.

    Ne CROIT plus des faits passés en argument : chaque reçu est re-vérifié
    (signature HMAC + run_id concordant). Un reçu absent/altéré/discordant =>
    provenance rompue => software_verdict BLOCKED. Impossible de prononcer OK sans
    reçus valides prouvant que les oracles ont réellement tourné sur CE run.

    ``redteam_ran`` est un booléen STRUCTURÉ (dérivé de la RouteDecision réelle),
    pas un sniff de la chaîne reviewer : il alimente le flag d'honnêteté.
    Le red-team n'entre JAMAIS dans le calcul de ``software_verdict``.

    ``standard`` (curriculum de jeux, 2026-07-23) : reçu de ``s10s-oracle-standard``
    (les six oracles du STANDARD). OPTIONNEL et rétro-compatible — omis, l'agrégat se
    comporte exactement comme avant (profils antérieurs au STANDARD, appelants tiers).
    Fourni, il est traité EXACTEMENT comme archi/wiremap : provenance re-vérifiée,
    statut agrégé dans ``software_verdict``, rouge/sauté visible dans ``humangate_flags``.
    Un profil qui MESURE six oracles sans les faire entrer dans le verdict signé ne
    prouve rien de ce qu'il mesure — d'où ce quatrième reçu.

    ``extra_advisory`` (Tier 2.5 étape 3) : flags PRÉ-FORMATÉS d'un contrôle qualité
    additionnel qui DÉTECTE mais ne DÉCIDE jamais (ex. le panel Prisme, s1 : violations
    de forme remontées par check_prisme.mjs). Même statut que le red-team : n'entre
    JAMAIS dans ``software_verdict``, pousse ``decision`` vers WITH_OBJECTION s'il y a
    quelque chose à signaler, toujours visible dans ``humangate_flags`` — jamais tu.

    ``is_game`` (lot 1 ADR-003, P0-2) : déclaration STRUCTURÉE de la game-ness,
    signée avec le verdict (cf. AggregateVerdict.is_game). Ne change AUCUN calcul
    ici (software_verdict/decision inchangés) : c'est un fait de provenance que
    ``verify_run`` confronte au reçu code — un ``is_game=True`` sans preuve
    mutation embarquée y devient un rejet, plus jamais un « non-jeu » par défaut.

    ``execution_proof_attestation`` (A2, ratifié Pierre 2026-08-28) : régime de
    preuve de l'EXÉCUTION des spawns de ce run. Le driver headless passe
    ``ATTESTATION_SELF`` parce qu'il écrit LUI-MÊME ses `spawn_authorized`/
    `spawn_executed` (aucun observateur tiers) ; la note lisible est DÉRIVÉE ici,
    jamais fournie par l'appelant (une note libre serait une narration signée).
    Ne change AUCUN calcul — jamais bloquant, jamais silencieux. Omis => None,
    exactement l'ancien comportement (rétro-compat : `verify_run` re-signe le corps
    STOCKÉ, un verdict historique sans ces clés reste vérifiable tel quel).
    """
    if scope not in ("FULL", "PARTIAL"):
        raise ValueError(f"scope invalide: {scope!r} (attendu FULL ou PARTIAL)")
    if execution_proof_attestation is not None and (
            execution_proof_attestation not in EXECUTION_PROOF_ATTESTATIONS):
        raise ValueError(
            f"execution_proof_attestation invalide: {execution_proof_attestation!r} "
            f"(attendu None ou {', '.join(EXECUTION_PROOF_ATTESTATIONS)})")
    if ts is None:
        ts = time.time()
    flags: list[str] = []
    receipts = {"code": code, "archi": archi, "wiremap": wiremap}
    if standard is not None:
        receipts["standard"] = standard
    verified: dict = {}
    provenance_ok = True

    # 1) PROVENANCE d'abord : sans preuve d'exécution vérifiable, pas de verdict.
    for name, sr in receipts.items():
        if sr is None or not verify_receipt(sr.receipt, sr.signature, key_file):
            provenance_ok = False
            flags.append(f"provenance rompue: reçu {name} absent/non signé/altéré")
            continue
        if sr.receipt.run_id != run_id:
            provenance_ok = False
            flags.append(
                f"provenance rompue: run_id {name} discordant "
                f"({sr.receipt.run_id!r} != {run_id!r})"
            )
            continue
        if sr.receipt.status not in RECEIPT_STATUSES:
            provenance_ok = False
            flags.append(f"provenance rompue: statut {name} invalide {sr.receipt.status!r}")
            continue
        # Le reçu CODE représente une COMMANDE EXTERNE : sans fichier d'évidence, on
        # ne peut pas prouver qu'elle a tourné (ferme l'exploit « code OK fabriqué
        # sans oracle »). archi/wiremap sont des oracles-fonctions dont l'évidence
        # EST le detail signé — pas de fichier requis.
        if name == "code" and sr.receipt.status != "SKIPPED" and not sr.receipt.evidence_path:
            provenance_ok = False
            flags.append("provenance rompue: reçu code sans évidence (exécution non prouvable)")
            continue
        # Scellé d'évidence NON décoratif : si le reçu pointe un fichier d'évidence,
        # on RE-LIT son contenu et on confronte le hash signé au réel. Discordance
        # (log absent/altéré) => provenance rompue. Sauter (SKIPPED) n'a pas d'évidence.
        # `evidence_sha256` VIDE = rien n'a ete promis (flux non scellable, cf.
        # `evidence_is_sealable`). Confronter un sceau absent inventerait une rupture.
        if (sr.receipt.status != "SKIPPED" and sr.receipt.evidence_path
                and sr.receipt.evidence_sha256):
            actual = sha256_evidence(sr.receipt.evidence_path)
            if actual != sr.receipt.evidence_sha256:
                provenance_ok = False
                flags.append(
                    f"provenance rompue: évidence {name} altérée/absente "
                    f"({sr.receipt.evidence_path})"
                )
                continue
        verified[name] = sr.receipt

    # 2) software_verdict : statuts des reçus VÉRIFIÉS uniquement. SKIPPED ne compte
    #    pas, mais l'oracle CODE doit être OK (sinon rien de substantiel n'est prouvé).
    if not provenance_ok:
        software = "BLOCKED"     # aucune narration ne remplace un reçu signé
    elif scope == "PARTIAL":
        # P2 : un profil partiel est jugé sur les oracles qu'il a RÉELLEMENT
        # exécutés — SKIPPED (hors profil) ne compte pas, et « code sauté »
        # n'est pas une faute ici : c'est la définition même du périmètre.
        # Aucun oracle exécuté => BLOCKED honnête (rien de prouvé côté logiciel).
        actifs = [n for n in receipts if verified[n].status != "SKIPPED"]
        if not actifs:
            software = "BLOCKED"
            flags.append(
                "scope PARTIAL: aucun oracle exécuté dans ce périmètre — "
                "l'agrégat prouve la provenance des reçus, pas le logiciel")
        elif any(verified[n].status == "BLOCKED" for n in actifs):
            software = "BLOCKED"
        elif any(verified[n].status == "FAIL" for n in actifs):
            software = "FAIL"
        else:
            software = "OK"
    else:
        # Tous les reçus FOURNIS comptent (dont `standard` quand il est là) — pas une
        # liste en dur : ajouter un oracle sans l'agréger reviendrait à le mesurer pour rien.
        statuses = [verified[n].status for n in receipts]
        if "BLOCKED" in statuses:
            software = "BLOCKED"
        elif "FAIL" in statuses:
            software = "FAIL"
        elif verified["code"].status == "OK" and all(s in ("OK", "SKIPPED") for s in statuses):
            software = "OK"
        else:
            software = "BLOCKED"    # code sauté / rien de prouvé

    # Exception de triage mutation (doctrine P0.3) : un survivant trié franchit le
    # gate (software peut être OK) mais NE PEUT PAS produire un OK propre — HumanGate
    # obligatoire. Lue du reçu code vérifié (sinon provenance rompue => déjà BLOCKED).
    triage_exception, triaged = (_mutation_triage_exception(verified.get("code"))
                                 if provenance_ok else (False, []))

    # Le red-team ne change PAS software_verdict (pas de LLM-as-judge), mais s'il a
    # BLOQUÉ alors que les oracles sont verts, Pierre doit le VOIR dans la décision
    # (un jeu "prêt" dont le red-team dit que la mécanique cœur n'est pas prouvée).
    # Idem une exception de triage : oracles verts MAIS équivalence non prouvée.
    if software != "OK":
        decision = DECISION_BLOCKED
    elif redteam_blocked or triage_exception or extra_advisory or scope == "PARTIAL":
        # P2 : un PARTIAL ne peut JAMAIS produire HUMANGATE_READY — un périmètre
        # incomplet est structurellement une objection, pas un prêt-à-revue.
        decision = DECISION_READY_OBJECTION
    else:
        decision = DECISION_READY

    # 3) Flags HumanGate (fog) : rouges mécaniques + oracles sautés + advisory red-team.
    if provenance_ok:
        for name in [n for n in ("archi", "wiremap", "standard") if n in receipts]:
            st = verified[name].status
            if st == "SKIPPED":
                flags.append(f"{name} non vérifiée (oracle sauté dans ce profil)")
            elif st != "OK":
                d = verified[name].detail
                why = (d.get("deps_interdites_violées") or d.get("features_manquantes")
                       or d.get("preuves_absentes") or _red_facets(d) or "violation")
                flags.append(f"{name} rouge: {why}")
    if triage_exception:
        flags.append(
            f"mutation: {len(triaged)} survivant(s) trié(s) par le producteur "
            f"({', '.join(triaged)}) — équivalence NON vérifiée mécaniquement, "
            "ratification HumanGate obligatoire avant tout claim positif"
        )
    if redteam_blocked:
        flags.append(f"red-team BLOQUE ({redteam_reviewer}) — objection à examiner (advisory)")
    if not redteam_ran:
        # Honnêteté (structurée) : le reviewer indépendant n'a pas tourné.
        flags.append("red-team dégradé: reviewer indépendant n'a pas tourné (fallback)")
    flags.extend(extra_advisory)

    oracles = {name: asdict(sr.receipt) for name, sr in receipts.items() if sr is not None}
    return AggregateVerdict(
        project=project,
        run_id=run_id,
        software_verdict=software,
        evidence_verdict=EVIDENCE_VERDICT,
        claim_verdict=CLAIM_VERDICT,
        decision=decision,
        oracles=oracles,
        redteam_reviewer=redteam_reviewer,
        redteam_ran=bool(redteam_ran),
        provenance_ok=provenance_ok,
        git_head=git_head,
        nonce=nonce,
        ts=ts,
        redteam_advisory=tuple(redteam_findings),
        humangate_flags=tuple(flags),
        scope=scope,
        is_game=is_game,
        execution_proof_attestation=execution_proof_attestation,
        execution_proof_note=(
            EXECUTION_PROOF_SELF_NOTE
            if execution_proof_attestation == ATTESTATION_SELF else ""),
    )


def sign_aggregate(verdict: AggregateVerdict, key_file: Path | None = None) -> str:
    return _sign_mapping(asdict(verdict), key_file)


def verify_aggregate(verdict: AggregateVerdict, signature: str, key_file: Path | None = None) -> bool:
    return _verify_mapping(asdict(verdict), signature, key_file)


def signed_aggregate_record(verdict: AggregateVerdict, key_file: Path | None = None) -> dict:
    """L'agrégat + sa signature, prêt à écrire dans verdict.json (contrat s12)."""
    return {**asdict(verdict), "hmac": sign_aggregate(verdict, key_file)}
