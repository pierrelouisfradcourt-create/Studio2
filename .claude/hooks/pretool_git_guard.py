"""PreToolUse hook -- bloque `git checkout`/`git restore`/`git stash` (et
variantes) sans override humain explicite. Mission P2 (contrat
scripts/forge/contracts/p2-garde-git-mecanique.yaml).

**CÂBLÉ ET ACTIF** (corrigé le 2026-09-05, gate 5) : référencé DEUX FOIS dans
`.claude/settings.json`, sur les matchers `Bash` et `PowerShell` — il s'exécute donc
à chaque commande. Le docstring affirmait jusqu'ici « PRÉPARÉ, NON CÂBLÉ : ce fichier
n'est référencé nulle part », ce qui était faux : un fichier qui se décrit comme
inactif pendant qu'il garde le dépôt est pire qu'un fichier sans docstring.

Contrat Claude Code : lit l'événement PreToolUse en JSON sur stdin. Sort 0 pour
autoriser, 2 pour BLOQUER (le message stderr est remonté au modèle). Patron
repris de `.claude/hooks/pretool_forge_guard.py` : test de chaîne PUR AVANT
tout import fragile, pour que fail-closed s'applique même si l'import échoue,
mais UNIQUEMENT quand la commande mentionne "git" (voir forge.git_guard pour
la justification -- fail-closed total sur TOUT Bash/PowerShell serait un risque
de disponibilité disproportionné).
"""
import json
import re
import sys

# Noms d'outils couverts par ce garde. LIMITE ASSUMÉE : si un futur outil
# d'exécution de commande porte un autre nom (ex. un outil "Shell" ou
# "Execute" propre à un autre environnement), il N'EST PAS couvert tant qu'il
# n'est pas ajouté ici -- documenté dans la proposition.
GUARDED_TOOLS = ("Bash", "PowerShell")

# Heuristique du chemin d'exception UNIQUEMENT : « cette commande parle-t-elle de git ? ».
# Elle ne décide RIEN quand le garde fonctionne — c'est `forge.git_guard.evaluate_command`
# qui tranche. Elle décide seulement s'il faut refuser fail-closed quand le garde est
# indisponible.
#
# ÉTAIT une sous-chaîne `"git" in command.lower()`, corrigée le 2026-09-05 (gate 5) après
# mesure : elle refusait `cat .gitignore`, `ls digital/`, `echo legitime` — perte de
# disponibilité sur des lectures inoffensives, précisément quand le garde est déjà cassé.
#
# DÉLIBÉRÉMENT DIFFÉRENTE de `forge.git_guard._GIT_WORD`, et c'est mesuré : celle-ci exclut
# `\w`, `.` et `-` avant le mot, mais PAS `/`. Aligner à l'identique aurait laissé passer
# `/usr/bin/git checkout` et `C:/outils/git.exe`, que la sous-chaîne refusait. Un
# fail-closed doit être PLUS large que la détection, jamais plus étroit.
# Score mesuré sur 9 cas : sous-chaîne 5/9, `_GIT_WORD` à l'identique 7/9, celle-ci 9/9.
#
# DUPLICATION ASSUMÉE : ce module ne peut PAS importer `forge.git_guard` pour obtenir cette
# regex — tout l'intérêt est de fonctionner quand cet import échoue. `re` est stdlib, donc
# le test reste pur. `forge/tests/test_git_guard_hook.py` vérifie que les deux motifs
# restent cohérents.
_GIT_MENTION = re.compile(r"(?<![\w.-])git(?:\.exe)?(?=\s|$)", re.IGNORECASE)


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # entrée illisible : impossible de savoir s'il s'agit de git -> on n'entrave rien

    tool = data.get("tool_name") or data.get("tool") or ""
    if tool not in GUARDED_TOOLS:
        return 0

    ti = data.get("tool_input") or {}
    command = str(ti.get("command", ""))
    if not command:
        return 0

    looks_like_git = bool(_GIT_MENTION.search(command))

    try:
        from pathlib import Path
        repo_root = Path(__file__).resolve().parents[2]
        # V2 : le tronc est `<racine>/forge`, plus `<racine>/scripts/forge` (V1).
        sys.path.insert(0, str(repo_root))
        from forge.git_guard import evaluate_command

        blocked, reason = evaluate_command(command)
    except Exception as exc:
        if looks_like_git:
            print(f"[git-guard] garde indisponible ({exc}) -> refus fail-closed "
                  f"(la commande mentionne 'git').", file=sys.stderr)
            return 2
        return 0  # pas de "git" détecté : un bug du garde ne casse pas Bash/PowerShell en général

    if blocked:
        print(f"[git-guard] commande refusée : {reason}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
