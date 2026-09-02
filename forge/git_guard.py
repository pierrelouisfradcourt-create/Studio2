"""Garde MÉCANIQUE anti-git-destructif (mission P2, contrat
forge/contracts/p2-garde-git-mecanique.yaml).

**PRÉPARÉ, NON ACTIVÉ.** Ce module n'est câblé nulle part dans
`.claude/settings.json` : le patch proposé vit dans
docs/forge/GARDE_GIT_MECANIQUE_PROPOSITION.md, non appliqué (Pierre décide).

Objectif ratifié (retour niveau 1 Pierre, 2026-07-27, point 4) : rendre
MÉCANIQUEMENT impossible pour un agent d'exécuter `git checkout`, `git restore`,
`git stash` (et leurs variantes) sur ce dépôt, sans jamais bloquer les usages en
LECTURE (`git status`/`diff`/`log`/`show`), avec un override humain explicite,
tracé, jamais silencieux.

TROIS OCCURRENCES RÉELLES ayant motivé ce garde (EVIDENCE/runs/RUN_INDEX.md) :
  V4    (2026-07-26) — revert temporaire de hunks de `driver.py` pour prouver
         un RED, sur un fichier portant 3 autres chantiers non commités.
  N1-1  (2026-07-27) — `git stash push`/`pop` sur `run_real.py`.
  N1-3  (2026-07-27) — `git checkout -- knowledge_base/learning_curve.jsonl`,
         puis une « réparation » qui a en fait RESTAURÉ une pollution de test
         (diagnostic erroné de l'agent).
La 3e a eu lieu MALGRÉ une interdiction déjà écrite en prose dans le contrat de
la mission N1-3 : la règle écrite ne suffit plus, d'où ce garde mécanique.

STDLIB UNIQUEMENT (comme forge.hook_guard) : ce module est appelé depuis un
hook PreToolUse fail-closed. Une dépendance tierce absente du PATH d'un futur
worktree transformerait une simple ImportError en refus universel de TOUTE
commande Bash/PowerShell mentionnant "git" -- risque de disponibilité
disproportionné par rapport au gain de sécurité.

CE QUE CE GARDE NE COUVRE PAS (honnêteté exigée par le garde-fou 3 du contrat) :
  - les ALIAS git définis par l'utilisateur (`git co` pour `checkout`, etc.) --
    seule la forme canonique (`checkout`/`restore`/`stash`) est reconnue ;
  - les WRAPPERS qui invoquent git indirectement : script .sh/.ps1 qui appelle
    git en interne, `subprocess.run(["git","checkout",...])` en Python,
    `Invoke-Expression` PowerShell construite dynamiquement, etc. -- seule la
    chaîne TEXTUELLE passée en tool_input.command est analysée, jamais la
    commande réellement exécutée par le shell ;
  - la concaténation/obfuscation de la commande via des variables shell
    (`X=checkout; git $X`) ;
  - un binaire `git` renommé ou un PATH détourné ;
  - toute syntaxe PowerShell exotique où la sous-commande n'est pas séparée du
    reste par un espace ASCII simple (ex. néologismes de quoting imbriqué).
Ce garde est un filtre TEXTUEL best-effort, pas un sandbox d'exécution.
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path

# --- Politique -----------------------------------------------------------

# Sous-commandes qui modifient l'arbre de travail / l'index / le stash --
# exactement les 3 familles des incidents réels ci-dessus.
BLOCKED_SUBCOMMANDS = frozenset({"checkout", "restore", "stash"})

# Liste BLANCHE explicite (garde-fou 2 du contrat) : jamais bloquées, quelles
# que soient les options qui précèdent. On raisonne en AUTORISATION plutôt
# qu'en interdiction pour celles-ci (exigences_cognitives du contrat).
READ_ONLY_SUBCOMMANDS = frozenset({"status", "diff", "log", "show"})

# Options globales `git <option> <valeur> <sous-commande>` qui consomment un
# argument SÉPARÉ -- à sauter avec leur valeur avant de chercher la
# sous-commande (cf. `git help` section "OPTIONS"). Couvre `git -C <dir> checkout`.
_GLOBAL_OPTS_WITH_ARG = frozenset({
    "-C", "-c", "--git-dir", "--work-tree", "--namespace",
    "--super-prefix", "--exec-path",
})
# Formes `--option=valeur` : un seul token, rien à sauter en plus.
_GLOBAL_OPTS_EQUALS_PREFIXES = (
    "--git-dir=", "--work-tree=", "--namespace=",
    "--exec-path=", "--super-prefix=",
)

_TOP_LEVEL_SEPARATORS = re.compile(r"&&|\|\||[;|]")
# "git" en mot entier (pas "digital", pas "legit"), suivi d'un espace ou de fin
# de segment -- volontairement insensible à un éventuel ".exe" (invocations
# Windows explicites).
_GIT_WORD = re.compile(r"(?<![\w./-])git(?:\.exe)?(?=\s|$)")

OVERRIDE_SENTINEL_DEFAULT = Path(".claude/HUMAN_GIT_OVERRIDE.json")
# Fenêtre volontairement courte : un override est un geste ponctuel pour UNE
# commande, pas un interrupteur qu'on laisse ouvert toute une session.
OVERRIDE_MAX_AGE_SECONDS = 600  # 10 minutes


def _segments(command: str) -> list[str]:
    """Découpe (best-effort) une commande composée sur &&, ||, ;, | de haut
    niveau. PAS un parseur shell complet (limite documentée en tête de module) :
    suffisant pour repérer chaque invocation `git` distincte dans une commande
    chaînée -- ce qu'aucun des 3 incidents réels n'utilisait de toute façon,
    mais que le garde-fou 3 du contrat exige de couvrir par prudence.
    """
    return [s for s in _TOP_LEVEL_SEPARATORS.split(command) if s.strip()]


def _subcommand_of(segment: str) -> str | None:
    """Sous-commande git du segment, ou None si ce segment n'invoque pas git
    (ou invoque `git` sans sous-commande, ex. `git --version`)."""
    match = _GIT_WORD.search(segment)
    if not match:
        return None
    tokens = segment[match.end():].split()
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in _GLOBAL_OPTS_WITH_ARG:
            i += 2  # option + sa valeur séparée (ex. `-C EVIDENCE/runs/pong`)
            continue
        if tok.startswith(_GLOBAL_OPTS_EQUALS_PREFIXES):
            i += 1
            continue
        if tok.startswith("-"):
            i += 1  # option globale (connue ou non) sans argument séparé
            continue
        return tok  # premier token qui n'est pas une option => sous-commande
    return None  # `git` seul, ou uniquement des options globales


def find_blocked_invocations(command: str) -> list[tuple[str, str]]:
    """Liste des (segment, sous-commande) du texte de commande qui matchent
    une sous-commande bloquée (`checkout`/`restore`/`stash`). Liste vide si
    aucune invocation destructrice n'est trouvée."""
    hits: list[tuple[str, str]] = []
    for seg in _segments(command):
        sub = _subcommand_of(seg)
        if sub in BLOCKED_SUBCOMMANDS:
            hits.append((seg.strip(), sub))
    return hits


def _read_override(sentinel_path: Path, now: float | None = None,
                    max_age: int = OVERRIDE_MAX_AGE_SECONDS) -> tuple[bool, str]:
    """Override humain : présence + fraîcheur + motif d'un sentinelle horodaté.

    **LIMITE ASSUMÉE ET DOCUMENTÉE (le point central du garde-fou 4)** : cette
    fonction vérifie la PRÉSENCE, la FRAÎCHEUR et la FORME d'un fichier -- elle
    ne peut PAS vérifier QUI l'a écrit. La garantie d'origine humaine dépend
    ENTIÈREMENT d'une règle *externe* à ce module : que `.claude/settings.json`
    refuse (deny) toute écriture d'agent sur `OVERRIDE_SENTINEL_DEFAULT`. Cette
    règle est PROPOSÉE dans docs/forge/GARDE_GIT_MECANIQUE_PROPOSITION.md, pas
    appliquée par cette mission (hors périmètre : `.claude/settings.json`
    interdit d'écriture ici). Sans ce deny, un agent autorisé à écrire dans
    `.claude/**` pourrait produire ce fichier lui-même -- exactement le défaut
    qu'un override doit éliminer selon le contrat ("un override qu'un agent
    peut se donner tout seul ne vaut rien").
    """
    if not sentinel_path.exists():
        return False, "aucun override (sentinelle absent)"
    try:
        raw = sentinel_path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except Exception as exc:  # noqa: BLE001 — override illisible = pas d'override
        return False, f"override illisible ({exc}) -> ignoré, refus"
    if not isinstance(data, dict):
        return False, "override mal formé (racine non-objet) -> ignoré, refus"
    ts = data.get("timestamp_epoch")
    reason = data.get("reason", "")
    if not isinstance(ts, (int, float)) or not reason:
        return False, "override mal formé (timestamp_epoch/reason requis) -> refus"
    age = (now if now is not None else time.time()) - ts
    if age < 0 or age > max_age:
        return False, f"override expiré ou horodatage invalide (age={age:.0f}s) -> refus"
    return True, f"override humain accepté (reason={reason!r}, age={age:.0f}s)"


def evaluate_command(command: str, sentinel_path: Path | None = None,
                      now: float | None = None) -> tuple[bool, str]:
    """Décision du garde : ``(bloqué, motif)``. ``True`` = BLOQUER l'exécution.

    Fail-CLOSED SUR SA SURFACE (garde-fou 2 du contrat) : dès que la commande
    mentionne textuellement "git", toute exception pendant l'analyse est
    traitée comme un blocage, jamais comme un laissez-passer silencieux. Une
    commande qui ne mentionne PAS "git" n'est jamais analysée plus loin -- ce
    garde ne gêne aucun autre usage de Bash/PowerShell (fail-OPEN hors de sa
    surface, même patron que `forge.hook_guard.hook_decision`).
    """
    if "git" not in command.lower():
        return False, "aucune invocation git détectée"

    try:
        hits = find_blocked_invocations(command)
    except Exception as exc:  # noqa: BLE001 — incertitude sur du git = refus
        return True, f"analyse impossible ({exc}) -> refus fail-closed"

    if not hits:
        return False, "invocation(s) git détectée(s), aucune sous-commande bloquée"

    joined = ", ".join(f"`{seg}` ({sub})" for seg, sub in hits)
    allowed, reason = _read_override(sentinel_path or OVERRIDE_SENTINEL_DEFAULT, now=now)
    if allowed:
        return False, f"bloqué normalement ({joined}) mais {reason}"
    return True, f"commande destructrice refusée : {joined} -- {reason}"
