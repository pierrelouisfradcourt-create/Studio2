"""PreToolUse hook -- bloque `git checkout`/`git restore`/`git stash` (et
variantes) sans override humain explicite. Mission P2 (contrat
scripts/forge/contracts/p2-garde-git-mecanique.yaml).

**PRÉPARÉ, NON CÂBLÉ** : ce fichier n'est référencé nulle part dans
`.claude/settings.json` tant que le patch proposé dans
docs/forge/GARDE_GIT_MECANIQUE_PROPOSITION.md n'est pas appliqué par Pierre.
`git diff -- .claude/settings.json` doit rester VIDE tant que cette mission
n'est pas ratifiée.

Contrat Claude Code : lit l'événement PreToolUse en JSON sur stdin. Sort 0 pour
autoriser, 2 pour BLOQUER (le message stderr est remonté au modèle). Patron
repris de `.claude/hooks/pretool_forge_guard.py` : test de chaîne PUR AVANT
tout import fragile, pour que fail-closed s'applique même si l'import échoue,
mais UNIQUEMENT quand la commande mentionne "git" (voir forge.git_guard pour
la justification -- fail-closed total sur TOUT Bash/PowerShell serait un risque
de disponibilité disproportionné).
"""
import json
import sys

# Noms d'outils couverts par ce garde. LIMITE ASSUMÉE : si un futur outil
# d'exécution de commande porte un autre nom (ex. un outil "Shell" ou
# "Execute" propre à un autre environnement), il N'EST PAS couvert tant qu'il
# n'est pas ajouté ici -- documenté dans la proposition.
GUARDED_TOOLS = ("Bash", "PowerShell")


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

    looks_like_git = "git" in command.lower()

    try:
        from pathlib import Path
        repo_root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(repo_root / "scripts"))
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
