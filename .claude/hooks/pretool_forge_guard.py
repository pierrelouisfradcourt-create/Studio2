"""PreToolUse hook — deux couches de refus indépendantes sur les spawns d'agents.

Contrat Claude Code : lit l'événement PreToolUse en JSON sur stdin. Sort 0 pour
autoriser, 2 pour BLOQUER (le message stderr est remonté au modèle).

===============================================================================
COUCHE 1 (historique, INCHANGÉE, PRIORITAIRE) — garde de contrat Forge
===============================================================================
Politique (voir forge.hook_guard.hook_decision) :
- HORS périmètre Forge (autre outil, ou aucun marqueur FORGE_DISPATCH) => fail-OPEN :
  le hook ne gêne jamais les usages non-Forge de l'outil Agent.
- SUR le périmètre Forge (marqueur présent) => fail-CLOSED : toute impossibilité de
  vérifier (garde qui lève, import cassé, audit illisible) => refus (2). L'ancien
  fail-open aveugle laissait passer un spawn Forge non gardé sur le moindre bug.

===============================================================================
COUCHE 2 (nouvelle) — héritage d'autorité de délégation
===============================================================================
Règle appliquée :

    effective_authority(agent) = capabilities(type) ∩ permissions(control-plane)
    délégation valide ⟺ effective_authority(enfant) ⊆ effective_authority(parent)

Applicable UNIQUEMENT à `tool_name ∈ {Task, Agent}`. Un enfant ne peut JAMAIS
obtenir une autorité supérieure à celle de son parent. Fail-closed intégral :
parent introuvable, autorité parent UNKNOWN, autorité enfant UNKNOWN, lignée
ambiguë, transcript absent/illisible, sidecar corrompu => DENY. UNKNOWN n'est
JAMAIS converti en ALLOW.

-------------------------------------------------------------------------------
Résolution du parent — ce qui est MESURÉ, pas supposé (2026-08-09)
-------------------------------------------------------------------------------
Format réel du payload PreToolUse :
    {session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
     hook_event_name, tool_name, tool_input, tool_use_id}
=> il ne contient AUCUN identifiant d'agent de l'appelant.

Format réel des sidecars (mesuré sur 476 agents du projet) :
    <session_dir>/subagents/agent-<id>.meta.json
    {"agentType": str, "description": str, "toolUseId": str,
     "parentAgentId": str (présent dès spawnDepth >= 2), "spawnDepth": int,
     "model": str (optionnel)}
    `parentAgentId` EST présent — contrairement à l'hypothèse de départ du charter
    (« {agentType, description, toolUseId, spawnDepth, model} »). Preuve :
    226b4ded-.../subagents/agent-aa2c149e72c426f20.meta.json porte
    "parentAgentId":"a8fc257f85f4ca9bd","spawnDepth":2.

`tool_use_id` du payload identifie l'ENFANT À NAÎTRE, pas le parent : c'est
exactement la valeur qui sera écrite dans le `toolUseId` du sidecar de l'enfant.
Preuve mesurée : toolu_01Vvx4D3qmLim7S28D1nNvb5 (toolUseId de
agent-aa2c149e72c426f20) n'apparaît que dans agent-a8fc257f85f4ca9bd.jsonl,
c.-à-d. dans le transcript de son PARENT, et dans aucun autre fichier de la
session. `tool_use_id` seul ne peut donc PAS résoudre le parent.

Conséquence : l'identité du parent est portée par `transcript_path`, qui EST le
transcript de l'appelant — résolution UNITAIRE, O(1), session courante
uniquement, aucun index global (l'index global mesuré coûtait 1460 ms) :
  * `<...>/<uuid>.jsonl`                       -> appelant = session principale
  * `<...>/subagents/agent-<id>.jsonl`         -> appelant = sous-agent <id>,
                                                  type lu dans le sidecar frère
  * toute autre forme                          -> UNRECOGNIZED => DENY
`tool_use_id` sert de corroboration ADVISORY (présence dans le transcript de
l'appelant) : jamais utilisé pour refuser (le transcript peut ne pas être encore
vidé sur disque au moment du hook) et jamais pour autoriser.

L'intégrité de la lignée est vérifiée en remontant `parentAgentId` (borne
MAX_CHAIN = 16, profondeurs réelles observées : {1:465, 2:10, 3:1}) :
profondeur non entière, profondeur qui ne décroît pas de 1, parent déclaré à la
profondeur 1, parent manquant à une profondeur > 1, ou cycle => AMBIGUOUS => DENY.

-------------------------------------------------------------------------------
Modèle d'autorité
-------------------------------------------------------------------------------
capabilities(type) :
  * agent CUSTOM  -> `.claude/agents/<type>.md`, frontmatter `disallowedTools`
    (mesuré : 15 des 17 fichiers déclarent `disallowedTools:` ; AUCUN ne déclare
    `tools:`). Un fichier sans `description` n'est PAS enregistré par le harnais
    (economy-designer.md, ui-programmer.md sont sur disque mais absents de la
    liste de types du runtime) => UNKNOWN => DENY. `disallowedTools` absent =>
    UNKNOWN => DENY (jamais « aucune restriction » par défaut).
  * type INTÉGRÉ -> `.claude/hooks/agent_authority_allowlist_v0.json`, allowlist
    conservative et versionnée. Type absent => UNKNOWN => DENY.

permissions(control-plane) : règles `permissions.deny` de `.claude/settings.json`
(+ `.claude/settings.local.json` s'il en déclare). Seule une règle SANS argument
(`WebSearch`) ou à argument universel (`Write(*)`, `Write(**)`) retire l'outil de
l'autorité effective ; une règle à portée de chemin (`Write(.claude/settings.json)`)
restreint sans supprimer la capacité et n'est donc PAS soustraite ici.
Mesure 2026-08-09 : aucune permission SCOPÉE PAR AGENT n'existe dans ce dépôt
(ni settings.json, ni settings.local.json, ni frontmatter) — surface déclarée
NOT_FOUND, pas simulée.

L'autorité est représentée sans énumérer l'univers des outils : soit « TOUS sauf
D » (co-finie), soit un ensemble fini explicite. L'inclusion est exacte dans les
quatre combinaisons (cf. Authority.is_subset_of).

-------------------------------------------------------------------------------
Témoin d'activation (borné, documenté, réversible)
-------------------------------------------------------------------------------
Variable d'environnement `TCS_AUTHORITY_INHERITANCE`, sinon fichier témoin
`.claude/hooks/authority_witness.json` ({"mode": "..."}), sinon défaut `off`.
  off      : la couche 2 n'est pas évaluée du tout (état par défaut, réversible
             par simple suppression du témoin).
  observe  : la couche 2 est évaluée et sa décision est écrite sur stderr, mais
             elle ne change JAMAIS le code de sortie.
  enforce  : DENY => sortie 2.
Le témoin n'active QUE la couche 2. Il ne peut ni transformer un UNKNOWN en
ALLOW (en `off`/`observe` la couche n'ajoute simplement aucun refus — elle
n'autorise rien qui ne l'était déjà), ni contourner la couche 1, ni contourner
les permissions du control-plane, qui sont appliquées par le harnais lui-même.
La couche 1 s'exécute d'abord et son refus est définitif.

-------------------------------------------------------------------------------
Limite explicite : `Python -> claude_executor` = NOT_OBSERVABLE
-------------------------------------------------------------------------------
Les spawns effectués par du code Python appelant `claude_executor` ne passent PAS
par PreToolUse : aucun événement de hook n'est émis pour eux. Ce chemin n'est
donc NI couvert NI couvrable par ce fichier. Il est déclaré NOT_OBSERVABLE — ce
qui n'est pas la même chose que ALLOW, ni que DENY, ni que « vérifié ».

claim_verdict: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

MARKER_TOKEN = "FORGE_DISPATCH"
SPAWN_TOOLS = ("Task", "Agent")

WITNESS_ENV = "TCS_AUTHORITY_INHERITANCE"
WITNESS_MODES = ("off", "observe", "enforce")
DEFAULT_MODE = "off"

MAX_CHAIN = 16
_ACCEPTED_VERIFICATION = ("OBSERVED_RUNTIME_LISTING",)

_AGENT_TRANSCRIPT_RE = re.compile(r"^agent-([0-9A-Za-z_-]+)\.jsonl$")
_MAIN_TRANSCRIPT_RE = re.compile(r"^[0-9a-fA-F-]{8,}\.jsonl$")
_TYPE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_DENY_RULE_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*(?:\((.*)\))?\s*$", re.DOTALL)
_UNIVERSAL_ARGS = {"", "*", "**", "**/*", ":*", "*:*"}


# =============================================================================
# Erreurs — chacune porte une CATÉGORIE distincte, jamais fondue en « erreur »
# =============================================================================
class AuthorityConfigError(RuntimeError):
    """Cible de configuration invalide (chemin injecté inexistant, allowlist
    illisible). Erreur EXPLICITE : jamais de redirection silencieuse vers un
    autre fichier."""


class LineageError(RuntimeError):
    """kind ∈ {NOT_FOUND, CORRUPT, AMBIGUOUS, UNRECOGNIZED}."""

    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind


class AuthorityUnknown(RuntimeError):
    """L'autorité effective d'un type n'est pas calculable => DENY."""


# =============================================================================
# Autorité
# =============================================================================
class Authority:
    """Ensemble d'outils autorisés, SANS énumérer l'univers.

    allow_all=True  -> « tous les outils SAUF `tools` »  (co-fini)
    allow_all=False -> « exactement `tools` »            (fini)

    CLASSE SIMPLE, PAS une `@dataclass` — volontaire et verrouillé par
    test_le_hook_reste_chargeable_hors_sys_modules. `@dataclass` résout ses
    annotations via `sys.modules[cls.__module__]` : ce fichier est chargé par
    `importlib.util.module_from_spec` SANS enregistrement dans `sys.modules`
    (patron utilisé par scripts/forge/tests/test_spawn_authority_repair.py), et
    la première dataclass y lève `AttributeError: 'NoneType' object has no
    attribute '__dict__'` — c.-à-d. un hook qui ne se charge plus du tout.
    """

    __slots__ = ("allow_all", "tools")

    def __init__(self, allow_all: bool, tools) -> None:
        self.allow_all = bool(allow_all)
        self.tools = frozenset(tools)

    def __eq__(self, other) -> bool:
        return (isinstance(other, Authority) and self.allow_all == other.allow_all
                and self.tools == other.tools)

    def __hash__(self) -> int:
        return hash((self.allow_all, self.tools))

    def __repr__(self) -> str:
        return f"Authority({self.describe()})"

    @staticmethod
    def all_except(denied: Iterable[str]) -> "Authority":
        return Authority(True, frozenset(denied))

    @staticmethod
    def only(allowed: Iterable[str]) -> "Authority":
        return Authority(False, frozenset(allowed))

    def intersect(self, other: "Authority") -> "Authority":
        if self.allow_all and other.allow_all:
            return Authority(True, self.tools | other.tools)
        if self.allow_all:  # other est fini
            return Authority(False, other.tools - self.tools)
        if other.allow_all:
            return Authority(False, self.tools - other.tools)
        return Authority(False, self.tools & other.tools)

    def is_subset_of(self, other: "Authority") -> bool:
        if self.allow_all and other.allow_all:
            # TOUS\Dc ⊆ TOUS\Dp ⟺ Dp ⊆ Dc
            return other.tools <= self.tools
        if self.allow_all and not other.allow_all:
            # co-fini ⊄ fini (conservateur, et exact tant que l'univers est infini/ouvert)
            return False
        if not self.allow_all and other.allow_all:
            return not (self.tools & other.tools)
        return self.tools <= other.tools

    def describe(self) -> str:
        if self.allow_all:
            return "ALL_TOOLS" if not self.tools else "ALL_TOOLS - {%s}" % ", ".join(sorted(self.tools))
        return "{%s}" % ", ".join(sorted(self.tools))


# =============================================================================
# Configuration (injectable — aucune valeur par défaut cachée)
# =============================================================================
class AuthorityConfig:
    """Classe simple (pas `@dataclass`) — même raison que `Authority`."""

    __slots__ = ("agents_dir", "allowlist_path", "settings_paths")

    def __init__(self, agents_dir: Path, allowlist_path: Path, settings_paths) -> None:
        self.agents_dir = Path(agents_dir)
        self.allowlist_path = Path(allowlist_path)
        self.settings_paths = tuple(Path(p) for p in settings_paths)

    def __repr__(self) -> str:
        return (f"AuthorityConfig(agents_dir={self.agents_dir!s}, "
                f"allowlist_path={self.allowlist_path!s}, "
                f"settings_paths={[str(p) for p in self.settings_paths]})")

    @staticmethod
    def from_repo_root(repo_root: Path) -> "AuthorityConfig":
        claude = Path(repo_root) / ".claude"
        return AuthorityConfig(
            agents_dir=claude / "agents",
            allowlist_path=claude / "hooks" / "agent_authority_allowlist_v0.json",
            settings_paths=(claude / "settings.json", claude / "settings.local.json"),
        )

    def validate(self) -> None:
        """Une mauvaise cible doit produire une ERREUR EXPLICITE, jamais un repli."""
        if not self.agents_dir.is_dir():
            raise AuthorityConfigError(f"agents_dir introuvable : {self.agents_dir}")
        if not self.allowlist_path.is_file():
            raise AuthorityConfigError(f"allowlist builtin introuvable : {self.allowlist_path}")
        for p in self.settings_paths:
            if p.exists() and not p.is_file():
                raise AuthorityConfigError(f"settings n'est pas un fichier : {p}")

    def load_allowlist(self) -> dict:
        try:
            data = json.loads(self.allowlist_path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise AuthorityConfigError(f"allowlist illisible ({self.allowlist_path}) : {exc}") from exc
        types = data.get("types")
        if not isinstance(types, dict):
            raise AuthorityConfigError(f"allowlist sans table `types` : {self.allowlist_path}")
        return types


def global_tool_denies(cfg: AuthorityConfig) -> frozenset:
    """Outils retirés à TOUT LE MONDE par le control-plane.

    Seule une règle sans argument ou à argument universel supprime la capacité.
    `Write(.claude/settings.json)` restreint une portée : la capacité `Write`
    existe encore, elle n'est donc pas soustraite ici.
    """
    denied: set = set()
    for path in cfg.settings_paths:
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise AuthorityConfigError(f"settings illisible ({path}) : {exc}") from exc
        rules = ((data.get("permissions") or {}).get("deny") or [])
        if not isinstance(rules, list):
            raise AuthorityConfigError(f"permissions.deny non listé dans {path}")
        for rule in rules:
            if not isinstance(rule, str):
                continue
            m = _DENY_RULE_RE.match(rule)
            if not m:
                continue
            tool, arg = m.group(1), m.group(2)
            if arg is None or arg.strip() in _UNIVERSAL_ARGS:
                denied.add(tool)
    return frozenset(denied)


# --- capacités d'un type ------------------------------------------------------
def _parse_frontmatter(text: str) -> dict:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    out: dict = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line or line.startswith((" ", "\t")):
            continue
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def _split_tool_list(raw: str) -> list:
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    return [t.strip().strip("'\"") for t in raw.split(",") if t.strip().strip("'\"")]


def capabilities_for_type(agent_type: str, cfg: AuthorityConfig, allowlist: dict) -> Authority:
    """capabilities(type). Lève AuthorityUnknown si non établissable."""
    if not isinstance(agent_type, str) or not _TYPE_NAME_RE.match(agent_type):
        raise AuthorityUnknown(f"type d'agent invalide ou absent : {agent_type!r}")

    md = cfg.agents_dir / f"{agent_type}.md"
    if md.is_file():
        try:
            fm = _parse_frontmatter(md.read_text(encoding="utf-8"))
        except OSError as exc:
            raise AuthorityUnknown(f"agent custom illisible ({md}) : {exc}") from exc
        if fm.get("name", "").strip().strip("'\"") != agent_type:
            raise AuthorityUnknown(f"frontmatter `name` != nom de fichier pour {agent_type}")
        if not fm.get("description"):
            # Mesuré : un .md sans `description` n'est pas enregistré par le harnais.
            raise AuthorityUnknown(
                f"agent custom {agent_type} sans `description` : créé mais NON enregistré")
        if "disallowedTools" not in fm:
            raise AuthorityUnknown(
                f"agent custom {agent_type} sans `disallowedTools` : capacité non déclarée")
        return Authority.all_except(_split_tool_list(fm["disallowedTools"]))

    entry = allowlist.get(agent_type)
    if not isinstance(entry, dict):
        raise AuthorityUnknown(f"type intégré inconnu de l'allowlist : {agent_type}")
    if entry.get("verification_status") not in _ACCEPTED_VERIFICATION:
        raise AuthorityUnknown(
            f"type {agent_type} : verification_status={entry.get('verification_status')!r} "
            "non recevable pour autoriser")
    caps = entry.get("known_capabilities")
    restrictions = entry.get("known_restrictions") or []
    if not isinstance(restrictions, list):
        raise AuthorityUnknown(f"type {agent_type} : known_restrictions mal formé")
    if caps == "ALL":
        return Authority.all_except(restrictions)
    if isinstance(caps, list):
        return Authority.only(set(caps) - set(restrictions))
    raise AuthorityUnknown(f"type {agent_type} : known_capabilities non établi ({caps!r})")


def effective_authority(agent_type: str, cfg: AuthorityConfig, allowlist: dict,
                        denies: frozenset) -> Authority:
    """effective_authority = capabilities(type) ∩ permissions(control-plane)."""
    return capabilities_for_type(agent_type, cfg, allowlist).intersect(Authority.all_except(denies))


# =============================================================================
# Lignée — résolution UNITAIRE de l'appelant (aucun index, aucun scan global)
# =============================================================================
class Caller:
    """Classe simple (pas `@dataclass`) — même raison que `Authority`."""

    __slots__ = ("kind", "agent_id", "chain", "transcript")

    def __init__(self, kind: str, agent_id: str, chain, transcript: Path) -> None:
        self.kind = kind              # "main_session" | "subagent"
        self.agent_id = agent_id      # "" pour la session principale
        self.chain = tuple(chain)     # (type appelant, ..., type ancêtre profondeur 1)
        self.transcript = transcript

    def __repr__(self) -> str:
        return f"Caller({self.kind}, {self.agent_id!r}, {list(self.chain)})"


def _load_meta(subagents_dir: Path, agent_id: str) -> dict:
    meta = subagents_dir / f"agent-{agent_id}.meta.json"
    if not meta.is_file():
        raise LineageError("NOT_FOUND", f"sidecar parent introuvable : {meta}")
    try:
        raw = meta.read_text(encoding="utf-8")
    except OSError as exc:
        raise LineageError("CORRUPT", f"sidecar illisible ({meta}) : {exc}") from exc
    try:
        data = json.loads(raw)
    except Exception as exc:  # noqa: BLE001
        raise LineageError("CORRUPT", f"sidecar JSON invalide ({meta}) : {exc}") from exc
    if not isinstance(data, dict):
        raise LineageError("CORRUPT", f"sidecar non-objet ({meta})")
    return data


def resolve_caller(transcript_path: Any) -> Caller:
    """Identifie l'appelant à partir de son PROPRE transcript. O(1) fichiers."""
    if not isinstance(transcript_path, str) or not transcript_path.strip():
        raise LineageError("NOT_FOUND", "transcript_path absent du payload PreToolUse")
    tp = Path(transcript_path)
    if not tp.is_file():
        raise LineageError("NOT_FOUND", f"transcript introuvable : {tp}")
    try:
        with tp.open("rb"):
            pass
    except OSError as exc:
        raise LineageError("CORRUPT", f"transcript illisible : {tp} ({exc})") from exc

    name = tp.name
    m = _AGENT_TRANSCRIPT_RE.match(name)
    if m:
        agent_id = m.group(1)
        subagents_dir = tp.parent
        chain: list = []
        seen: set = set()
        current = agent_id
        expected_depth = None
        while True:
            if current in seen:
                raise LineageError("AMBIGUOUS", f"cycle de lignée sur agent-{current}")
            seen.add(current)
            meta = _load_meta(subagents_dir, current)
            atype = meta.get("agentType")
            if not isinstance(atype, str) or not atype.strip():
                raise LineageError("CORRUPT", f"agentType absent du sidecar agent-{current}")
            depth = meta.get("spawnDepth")
            if not isinstance(depth, int) or isinstance(depth, bool) or depth < 1:
                raise LineageError("AMBIGUOUS", f"spawnDepth non entier sur agent-{current}")
            if expected_depth is not None and depth != expected_depth:
                raise LineageError(
                    "AMBIGUOUS",
                    f"profondeur incohérente sur agent-{current} : {depth} != {expected_depth}")
            chain.append(atype.strip())
            if len(chain) > MAX_CHAIN:
                raise LineageError("AMBIGUOUS", f"lignée plus profonde que MAX_CHAIN={MAX_CHAIN}")
            parent_id = meta.get("parentAgentId")
            if depth == 1:
                if parent_id:
                    raise LineageError(
                        "AMBIGUOUS",
                        f"agent-{current} déclare un parent alors que spawnDepth==1")
                break
            if not isinstance(parent_id, str) or not parent_id.strip():
                raise LineageError(
                    "AMBIGUOUS", f"agent-{current} à la profondeur {depth} sans parentAgentId")
            current = parent_id.strip()
            expected_depth = depth - 1
        return Caller("subagent", agent_id, tuple(chain), tp)

    if _MAIN_TRANSCRIPT_RE.match(name) and tp.parent.name != "subagents":
        return Caller("main_session", "", (), tp)

    raise LineageError("UNRECOGNIZED", f"forme de transcript non reconnue : {name}")


def corroborate_tool_use_id(caller: Caller, tool_use_id: Any) -> str:
    """ADVISORY. Le transcript de l'appelant peut ne pas être encore vidé sur
    disque : l'absence ne prouve rien et ne refuse jamais. Retourne
    PRESENT / ABSENT / UNKNOWN."""
    if not isinstance(tool_use_id, str) or not tool_use_id:
        return "UNKNOWN"
    try:
        blob = caller.transcript.read_bytes()
    except OSError:
        return "UNKNOWN"
    return "PRESENT" if tool_use_id.encode("utf-8") in blob else "ABSENT"


# =============================================================================
# Décision
# =============================================================================
def evaluate_inheritance(payload: dict, cfg: AuthorityConfig) -> dict:
    """Retourne un enregistrement de décision complet (input, parent résolu,
    types, autorités, décision, raison). Ne lève jamais : toute impossibilité
    est convertie en DENY explicitement catégorisé."""
    tool = payload.get("tool_name") or payload.get("tool") or ""
    ti = payload.get("tool_input") or {}
    child_type = ti.get("subagent_type")
    record = {
        "layer": "authority_inheritance",
        "tool_name": tool,
        "tool_use_id": payload.get("tool_use_id"),
        "transcript_path": payload.get("transcript_path"),
        "child_type": child_type,
        "parent_kind": None,
        "parent_agent_id": None,
        "parent_chain": None,
        "parent_type": None,
        "parent_authority": "UNKNOWN",
        "child_authority": "UNKNOWN",
        "global_denies": None,
        "tool_use_id_corroboration": "UNKNOWN",
        "decision": "DENY",
        "reason_kind": "UNKNOWN",
        "reason": "",
    }
    if tool not in SPAWN_TOOLS:
        record.update(decision="NOT_APPLICABLE", reason_kind="OUT_OF_SCOPE",
                      reason=f"outil {tool!r} hors périmètre (Task/Agent uniquement)")
        return record

    try:
        cfg.validate()
        allowlist = cfg.load_allowlist()
        denies = global_tool_denies(cfg)
    except AuthorityConfigError as exc:
        record.update(reason_kind="CONFIG_ERROR", reason=str(exc))
        return record
    record["global_denies"] = sorted(denies)

    try:
        caller = resolve_caller(payload.get("transcript_path"))
    except LineageError as exc:
        record.update(reason_kind=f"PARENT_{exc.kind}", reason=str(exc))
        return record
    record["parent_kind"] = caller.kind
    record["parent_agent_id"] = caller.agent_id or None
    record["parent_chain"] = list(caller.chain)
    record["parent_type"] = caller.chain[0] if caller.chain else "__main_session__"
    record["tool_use_id_corroboration"] = corroborate_tool_use_id(caller, payload.get("tool_use_id"))

    # Autorité du parent = intersection sur toute la lignée (un agent ne peut pas
    # valoir plus que n'importe lequel de ses ancêtres). La session principale est
    # la racine : ALL ∩ control-plane.
    try:
        parent_auth = Authority.all_except(denies)
        for atype in caller.chain:
            parent_auth = parent_auth.intersect(
                effective_authority(atype, cfg, allowlist, denies))
    except AuthorityUnknown as exc:
        record.update(reason_kind="PARENT_AUTHORITY_UNKNOWN", reason=str(exc))
        return record
    record["parent_authority"] = parent_auth.describe()

    if child_type is None:
        record.update(reason_kind="CHILD_TYPE_MISSING",
                      reason="`subagent_type` absent du tool_input : autorité enfant UNKNOWN "
                             "(aucun défaut silencieux)")
        return record
    try:
        child_auth = effective_authority(child_type, cfg, allowlist, denies)
    except AuthorityUnknown as exc:
        record.update(reason_kind="CHILD_AUTHORITY_UNKNOWN", reason=str(exc))
        return record
    record["child_authority"] = child_auth.describe()

    if child_auth.is_subset_of(parent_auth):
        record.update(decision="ALLOW", reason_kind="SUBSET",
                      reason=f"effective_authority({child_type}) SUBSET_OF "
                             f"effective_authority({record['parent_type']})")
    else:
        record.update(decision="DENY", reason_kind="AUTHORITY_ESCALATION",
                      reason=f"effective_authority({child_type}) NOT_SUBSET_OF "
                             f"effective_authority({record['parent_type']}) : un enfant ne peut "
                             "pas obtenir une autorité supérieure à son parent")
    return record


# =============================================================================
# Témoin d'activation
# =============================================================================
def witness_mode(repo_root: Path, env: dict | None = None) -> str:
    env = os.environ if env is None else env
    raw = (env.get(WITNESS_ENV) or "").strip().lower()
    if raw in WITNESS_MODES:
        return raw
    if raw:
        return DEFAULT_MODE  # valeur inconnue => on n'active rien
    witness = Path(repo_root) / ".claude" / "hooks" / "authority_witness.json"
    if witness.is_file():
        try:
            mode = (json.loads(witness.read_text(encoding="utf-8")).get("mode") or "").strip().lower()
        except Exception:  # noqa: BLE001 — témoin illisible => non activé
            return DEFAULT_MODE
        if mode in WITNESS_MODES:
            return mode
    return DEFAULT_MODE


def _format(record: dict) -> str:
    return (
        "[authority-gate] {decision} ({reason_kind}) -- parent={parent_type} "
        "[{parent_kind}/{parent_agent_id}] authority={parent_authority} | "
        "child={child_type} authority={child_authority} | tool_use_id={tool_use_id} "
        "(corroboration={tool_use_id_corroboration}) | {reason}"
    ).format(**record)


# =============================================================================
# Entrée du hook
# =============================================================================
def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # pas d'entrée exploitable -> impossible de savoir si Forge -> on n'entrave rien

    tool = data.get("tool_name") or data.get("tool") or ""
    ti = data.get("tool_input") or {}
    prompt = " ".join(str(ti.get(k, "")) for k in ("prompt", "description"))

    # Périmètre Forge détecté par pur test de chaîne, AVANT tout import fragile :
    # si le garde ne se charge même pas, on doit quand même fail-closed sur Forge.
    forge_scope = tool in SPAWN_TOOLS and MARKER_TOKEN in prompt
    repo_root = Path(__file__).resolve().parents[2]

    # --- COUCHE 1 : garde de contrat Forge (prioritaire, inchangée) -----------
    try:
        sys.path.insert(0, str(repo_root / "scripts"))
        from forge.hook_guard import hook_decision, record_authorization

        code, reason = hook_decision(tool, prompt)
    except Exception as exc:
        if forge_scope:
            print(f"[forge-gate] garde indisponible ({exc}) -> refus fail-closed (périmètre Forge).",
                  file=sys.stderr)
            return 2
        return 0  # hors périmètre : un bug du garde ne casse pas la session

    if code == 2:
        print(f"[forge-gate] spawn refusé : {reason}. "
              f"Passe par forge.dispatch.prepare_dispatch (contrat validé) avant de spawner.",
              file=sys.stderr)
        return code

    # --- COUCHE 2 : héritage d'autorité (derrière témoin) ---------------------
    mode = witness_mode(repo_root)
    if mode != "off" and tool in SPAWN_TOOLS:
        record = evaluate_inheritance(data, AuthorityConfig.from_repo_root(repo_root))
        if record["decision"] == "DENY":
            print(_format(record), file=sys.stderr)
            if mode == "enforce":
                # Refus AVANT toute trace d'autorisation : l'audit ne doit jamais
                # enregistrer comme autorisé un spawn que le hook refuse.
                return 2
        elif mode == "observe":
            print(_format(record), file=sys.stderr)

    if forge_scope:
        # RÉPARATION (post-mortem pacman 2026-08-07, lot A réparation 3) : le hook
        # AUTORISE ce spawn (code == 0, marqueur FORGE_DISPATCH présent) -> trace
        # `spawn_authorized` AVANT de rendre la main. `record_authorization` était
        # implémentée et testée (forge.hook_guard) mais jamais appelée ici — c'est
        # le seul appelant légitime documenté dans sa propre docstring, d'où
        # `spawn_authorized` mesuré à 0/1418. Best-effort strict (jamais lever) :
        # une trace non écrite dégrade la preuve, elle ne doit JAMAIS transformer
        # un spawn déjà autorisé en refus — le hook a déjà rendu sa décision au
        # moment où cet appel a lieu, il ne peut plus la changer.
        try:
            record_authorization(prompt)
        except Exception:  # noqa: BLE001 — best-effort, jamais bloquant
            pass
    return code


if __name__ == "__main__":
    sys.exit(main())
