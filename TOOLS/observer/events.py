"""Schema d'evenements normalises de Forge Observer V0.

Observer est une couche STRICTEMENT LECTURE SEULE. Ce module ne definit que des
structures de donnees et des fonctions pures : il n'ouvre aucun fichier, n'ecrit
nulle part, et ne connait pas la Forge.

Principe directeur — un evenement porte TROIS metadonnees de confiance, jamais
une seule valeur nue :

  * `proof`  : la NATURE de la preuve (signee / mecanique / auto-declaree / inferee).
               Un agent qui ecrit "j'ai touche 0 fichier" dans sa prose et un
               reçu HMAC ne sont pas la meme categorie de verite.
  * `link`   : COMMENT l'evenement a ete rattache a un run_id. Un champ `run_id`
               present dans l'objet et une deduction "ce fichier entier appartient
               a ce run" ne se valent pas.
  * `source` : d'ou vient exactement la donnee (fichier, ligne, format), pour que
               toute affirmation d'Observer soit re-verifiable a la main.

Sans ces trois axes, Observer reproduirait le theatre d'oracle au lieu de le
reveler.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

SCHEMA_VERSION = "observer.event.v0"

# --------------------------------------------------------------------------- #
# Niveaux de preuve
# --------------------------------------------------------------------------- #

PROOF_SIGNED = "SIGNED"                # HMAC PRESENT ET VERIFIE CRYPTOGRAPHIQUEMENT
                                        # (P4 INV-2, 2026-08-07) : Observer a relu la cle
                                        # scripts/forge/.forge_key et confronte le HMAC au
                                        # corps de l'enregistrement — pas seulement constate
                                        # la presence du champ. Voir observer.signature.
PROOF_SIGNED_UNVERIFIABLE = "SIGNED_UNVERIFIABLE"  # hmac present, cle de signature absente
                                        # ou illisible depuis ce contexte -> Observer ne PEUT
                                        # PAS trancher. Distinct de SIGNED : ne compte jamais
                                        # comme preuve dure.
PROOF_SIGNED_INVALID = "SIGNED_INVALID"  # hmac present, cle lisible, signature qui NE
                                        # correspond PAS au corps -> falsification probable
                                        # ou corruption. Produit toujours un drift.detected
                                        # severite haute cote adaptateur.
PROOF_MECHANICAL = "MECHANICAL"        # produite par du code, non falsifiable par l'agent
PROOF_SELF_DECLARED = "SELF_DECLARED"  # prose ecrite par l'agent sur son propre travail
PROOF_INFERRED = "INFERRED"            # deduit par Observer, pas lu tel quel

PROOF_LEVELS = (
    PROOF_SIGNED,
    PROOF_SIGNED_UNVERIFIABLE,
    PROOF_SIGNED_INVALID,
    PROOF_MECHANICAL,
    PROOF_SELF_DECLARED,
    PROOF_INFERRED,
)

# --------------------------------------------------------------------------- #
# Niveaux de rattachement a un run
# --------------------------------------------------------------------------- #

LINK_DIRECT = "DIRECT"              # champ run_id present dans l'objet lui-meme
LINK_FILENAME = "BY_FILENAME"       # run_id lisible dans le nom du fichier
LINK_PATH = "BY_PATH"               # deduit du dossier de run qui contient le fichier
LINK_FILE_SCOPE = "BY_FILE_SCOPE"   # marqueur en tete de fichier, etendu a tout le fichier
LINK_TIME_WINDOW = "BY_TIME_WINDOW"  # rattache par proximite temporelle seule
LINK_NONE = "UNLINKED"

LINK_LEVELS = (
    LINK_DIRECT,
    LINK_FILENAME,
    LINK_PATH,
    LINK_FILE_SCOPE,
    LINK_TIME_WINDOW,
    LINK_NONE,
)

# --------------------------------------------------------------------------- #
# Taxonomie des evenements
# --------------------------------------------------------------------------- #

KINDS: frozenset[str] = frozenset(
    {
        # cycle de vie du run
        "run.declared",
        "run.status",
        "step.status",
        "run.charter",
        "run.task_prompt",
        # dispatch d'agent
        "dispatch.prepared",
        "dispatch.executed",
        "dispatch.context_manifest",
        "dispatch.reasoning",
        "dispatch.tools",
        # activite reelle de l'agent (transcripts)
        "agent.session",
        "agent.message",
        "tool.call",
        "tool.result",
        "file.read",
        "file.write",
        "file.edit",
        "shell.exec",
        "llm.usage",
        # cout / effort
        "telemetry.step",
        "builder.attempt",
        # preuves
        "oracle.result",
        "mutation.result",
        "solvability.result",
        # reparation ciblee (runtime `repair_runtime`, roles.yaml). Source :
        # lab/forge_evidence/repair_results.jsonl, ecrite par forge.repair_dispatch.
        "repair.result",
        "test.result",
        "guard.reference",
        "capture.visual",
        "verdict.signed",
        # deviations
        "failure.event",
        "drift.detected",
        # declaratif
        "artifact.self_declared",
        "wiremap.line",
        # depot
        "git.commit",
        # presence generique — fichier du run_dir qu'aucun collecteur specifique
        # n'a reclame (P2 routage, 2026-08-08). Ne remplace jamais un evenement
        # deja produit par un collecteur specifique : n'existe QUE pour les
        # fichiers restes orphelins apres le passage de tous les autres.
        "run.artifact_present",
    }
)

# Vocabulaires concurrents rencontres pour la notion de "tentative".
# Les quatre coexistent dans les sources : aucun champ commun n'existe.
ATTEMPT_FIELDS = ("attempt", "activation", "retry_number", "attempts")

_ISO_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"
)


# --------------------------------------------------------------------------- #
# Normalisation du temps
# --------------------------------------------------------------------------- #


def normalize_ts(value: Any) -> tuple[Optional[float], Optional[str], str]:
    """Normalise un horodatage heterogene vers un epoch flottant UTC.

    Les sources melangent trois formats, parfois dans le meme objet :
      * epoch flottant           -> 1785489109.66057
      * ISO8601 zoule            -> "2026-07-31T06:24:35.596Z"
      * ISO8601 sans fuseau      -> "2026-07-31T08:57:06"
      * log texte du driver      -> "2026-07-31 11:11:49,660"

    Retourne (epoch_utc, valeur_brute, format_detecte). L'epoch vaut None si la
    valeur est inexploitable — Observer ne fabrique jamais un temps absent.

    Les horodatages sans fuseau sont interpretes en UTC faute d'information ;
    le format retourne le signale (`iso_naive`) pour que l'incertitude reste
    visible en aval.
    """
    if value is None:
        return None, None, "absent"

    if isinstance(value, bool):  # bool est un int en Python : piege explicite
        return None, str(value), "invalide"

    if isinstance(value, (int, float)):
        return float(value), repr(value), "epoch"

    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None, value, "absent"

        # log driver : "2026-07-31 11:11:49,660"
        if "," in raw and _ISO_RE.match(raw.replace(",", ".")):
            raw_dot = raw.replace(",", ".")
            parsed = _parse_iso(raw_dot)
            if parsed is not None:
                epoch, naive = parsed
                return epoch, value, "log_naive" if naive else "log"

        if _ISO_RE.match(raw):
            parsed = _parse_iso(raw)
            if parsed is not None:
                epoch, naive = parsed
                return epoch, value, "iso_naive" if naive else "iso"

        # epoch stocke en chaine
        try:
            return float(raw), value, "epoch_str"
        except ValueError:
            return None, value, "invalide"

    return None, str(value), "invalide"


def _parse_iso(raw: str) -> Optional[tuple[float, bool]]:
    """Parse une chaine ISO8601. Retourne (epoch_utc, etait_naif) ou None."""
    candidate = raw.replace("Z", "+00:00").replace(" ", "T", 1)
    try:
        dt = datetime.fromisoformat(candidate)
    except ValueError:
        return None
    naive = dt.tzinfo is None
    if naive:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp(), naive


def iso(epoch: Optional[float]) -> Optional[str]:
    """Rend un epoch lisible en ISO8601 UTC, ou None si le temps est absent."""
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat()


# --------------------------------------------------------------------------- #
# Acteur
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Actor:
    """Qui a agi. Tous les champs sont optionnels : une source peut n'en porter
    aucun, et Observer ne comble pas les blancs."""

    kind: str = "unknown"  # llm_agent | non_llm | driver | human | unknown
    model: Optional[str] = None
    provider: Optional[str] = None
    capability_role: Optional[str] = None
    session_id: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v is not None}


# --------------------------------------------------------------------------- #
# Source
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Source:
    """D'ou vient la donnee, avec assez de precision pour la relire a la main."""

    path: str                      # chemin relatif au repo si possible
    fmt: str                       # json | jsonl | yaml | log | txt | png | git
    line: Optional[int] = None     # 1-indexe pour les .jsonl
    field: Optional[str] = None    # champ precis quand l'objet est gros

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v is not None}


# --------------------------------------------------------------------------- #
# Evenement
# --------------------------------------------------------------------------- #


@dataclass
class Event:
    """Un fait observe, date, attribue, et qualifie par sa nature de preuve."""

    kind: str
    source: Source
    proof: str
    link: str = LINK_NONE
    ts: Optional[float] = None
    ts_raw: Optional[str] = None
    ts_format: str = "absent"
    run_id: Optional[str] = None
    project: Optional[str] = None
    etape: Optional[str] = None
    attempt: Optional[int] = None
    attempt_field: Optional[str] = None
    actor: Actor = field(default_factory=Actor)
    payload: dict[str, Any] = field(default_factory=dict)
    note: Optional[str] = None
    event_id: str = ""

    def __post_init__(self) -> None:
        if self.kind not in KINDS:
            raise ValueError(f"kind inconnu: {self.kind!r}")
        if self.proof not in PROOF_LEVELS:
            raise ValueError(f"proof inconnu: {self.proof!r}")
        if self.link not in LINK_LEVELS:
            raise ValueError(f"link inconnu: {self.link!r}")
        if not self.event_id:
            self.event_id = self._compute_id()

    def _compute_id(self) -> str:
        """Identifiant deterministe : deux executions d'Observer sur les memes
        traces produisent les memes identifiants (rejouabilite)."""
        material = json.dumps(
            {
                "kind": self.kind,
                "source": self.source.to_dict(),
                "ts_raw": self.ts_raw,
                "run_id": self.run_id,
                "etape": self.etape,
                "attempt": self.attempt,
                "payload": self.payload,
            },
            sort_keys=True,
            ensure_ascii=False,
            default=str,
        )
        return hashlib.sha1(material.encode("utf-8")).hexdigest()[:16]

    def to_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {
            "event_id": self.event_id,
            "kind": self.kind,
            "ts": self.ts,
            "ts_iso": iso(self.ts),
            "ts_raw": self.ts_raw,
            "ts_format": self.ts_format,
            "run_id": self.run_id,
            "project": self.project,
            "etape": self.etape,
            "attempt": self.attempt,
            "attempt_field": self.attempt_field,
            "proof": self.proof,
            "link": self.link,
            "actor": self.actor.to_dict(),
            "source": self.source.to_dict(),
            "payload": self.payload,
        }
        if self.note:
            out["note"] = self.note
        return {k: v for k, v in out.items() if v is not None and v != {}}


def extract_attempt(obj: dict[str, Any]) -> tuple[Optional[int], Optional[str]]:
    """Resout la notion de tentative a travers ses quatre vocabulaires.

    `attempt` (dispatch_audit), `activation` (manifests), `retry_number`
    (builder_runs) et `attempts` (state.steps) designent des choses proches mais
    ne sont PAS interchangeables : aucun champ commun n'existe dans les sources.
    Observer retient la premiere valeur trouvee ET le nom du champ qui l'a
    fournie, pour qu'aucune comparaison ne se fasse entre deux vocabulaires sans
    que ce soit visible.
    """
    for name in ATTEMPT_FIELDS:
        if name in obj and isinstance(obj[name], int) and not isinstance(obj[name], bool):
            return obj[name], name
    return None, None
