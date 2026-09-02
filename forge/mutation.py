"""Mutation testing — le MÉTA-oracle : « tes tests attrapent-ils vraiment un bug ? ».

La couverture ne dit rien (« on peut supprimer toutes les assertions et garder 100% »).
Le mutation testing introduit une faute syntaxique (`>=`→`>`, `&&`→`||`, `true`→`false`…)
dans le CODE et vérifie qu'un test ÉCHOUE. Un mutant SURVIVANT = un bug que la suite
ne détecte pas — exactement le trou du test tautologique `>=` (survival_arena).

Générique : `generate_mutants(text)` est pur et testable ; `run_mutation_test` exécute
la vraie commande de test par mutant et rend un score kill/total. Aucune dépendance
externe (pas de Stryker/mutmut) — homegrown, v0.

Limite honnête v0 : les mutations dans un commentaire/chaîne peuvent gonfler les
survivants (on saute les lignes de commentaire pur, pas les chaînes). Score à lire
comme un signal, pas une vérité absolue.
"""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

# Règles de mutation : (token, remplacement, nom). Tokens multi-caractères sans
# chevauchement ambigu (on ne mute pas `>` seul pour ne pas casser `>=`/`=>`).
RULES: tuple[tuple[str, str, str], ...] = (
    (">=", ">", "ge->gt"),
    ("<=", "<", "le->lt"),
    ("===", "!==", "eq->neq"),
    ("!==", "===", "neq->eq"),
    ("&&", "||", "and->or"),
    ("||", "&&", "or->and"),
    ("+=", "-=", "pluseq->minuseq"),
    ("-=", "+=", "minuseq->pluseq"),
)
# Règles à frontière de mot. Regroupe les booléens (tous langages) et les opérateurs
# logiques GDScript/Python (`and`/`or`), qui n'ont pas d'équivalent dans RULES —
# RULES ne couvre que `&&`/`||` (JS/Rust). Sans ces entrées, muter un `.gd` ne
# produisait presque aucun mutant : gate mutation édenté (plan étape 0, tâche 4).
# Frontière \b obligatoire : sinon `operand`, `random`, `sword` génèrent des mutants
# syntaxiquement absurdes en masse.
_WORD_RULES = (
    (r"\btrue\b", "false", "true->false"),
    (r"\bfalse\b", "true", "false->true"),
    (r"\band\b", "or", "and->or"),
    (r"\bor\b", "and", "or->and"),
)

# Égalité non stricte (GDScript/Python). Ces règles sont appliquées APRÈS celles de
# RULES et jamais à l'intérieur d'un `===`/`!==` : muter le `==` d'un `===` JS
# produirait `=!=`, une faute de syntaxe (mutant inkillable et trompeur).
_EQ_RULES = (
    (re.compile(r"(?<![=!<>])==(?!=)"), "!=", "eqeq->neq"),
    (re.compile(r"(?<![=!<>])!=(?!=)"), "==", "neq->eqeq"),
)


@dataclass(frozen=True)
class Mutant:
    name: str
    line: int
    mutant_text: str


# Marqueur de mutant ÉQUIVALENT : une ligne portant ce commentaire n'est pas mutée.
# À réserver aux cas PROUVÉS équivalents (mutation inerte, inkillable par définition —
# ex. `x >>>= 0` redondant : les opérateurs bitwise JS re-convertissent en 32 bits).
SKIP_MARKER = "mutation:skip"

# Préfixes de commentaire pur par défaut (JS/Rust/C-like). NE PAS y ajouter `#`
# globalement : en JS moderne `#` introduit un champ privé de classe
# (`#alive = true;`), pas un commentaire — le confondre supprimerait
# silencieusement un mutant légitime. Le `#` GDScript/Python est ajouté au cas
# par cas via `comment_prefixes_for`, dérivé de l'extension du fichier source.
DEFAULT_COMMENT_PREFIXES: tuple[str, ...] = ("//", "*", "/*")

# Extensions dont le marqueur de commentaire pur est `#` (GDScript, Python).
_HASH_COMMENT_EXTENSIONS = (".gd", ".py")


def comment_prefixes_for(source_path: Path | str) -> tuple[str, ...]:
    """Préfixes de commentaire pur à utiliser pour ce fichier source.

    `.gd`/`.py` ajoutent `#` (sans quoi chaque commentaire GDScript contenant
    `and`/`or`/`true`/`false`/`==`/`!=` produit un survivant inkillable par
    construction — cf. mesure empirique du défaut). Tout le reste garde le
    défaut inchangé (`//`, `*`, `/*`).
    """
    suffix = Path(source_path).suffix.lower()
    if suffix in _HASH_COMMENT_EXTENSIONS:
        return DEFAULT_COMMENT_PREFIXES + ("#",)
    return DEFAULT_COMMENT_PREFIXES


def _skip_occurrence(text: str, idx: int,
                     comment_prefixes: tuple[str, ...] = DEFAULT_COMMENT_PREFIXES) -> bool:
    """Ligne de commentaire pur OU portant le marqueur d'équivalence => on ne mute pas."""
    start = text.rfind("\n", 0, idx) + 1
    end = text.find("\n", idx)
    line = text[start:(end if end != -1 else len(text))]
    stripped = line.lstrip()
    if any(stripped.startswith(prefix) for prefix in comment_prefixes):
        return True
    return SKIP_MARKER in line


def generate_mutants(text: str,
                     comment_prefixes: tuple[str, ...] = DEFAULT_COMMENT_PREFIXES) -> list[Mutant]:
    """Un mutant par occurrence mutable (hors ligne de commentaire pur)."""
    mutants: list[Mutant] = []
    for token, repl, name in RULES:
        start = 0
        while True:
            i = text.find(token, start)
            if i == -1:
                break
            start = i + len(token)
            if _skip_occurrence(text, i, comment_prefixes):
                continue
            mutant = text[:i] + repl + text[i + len(token):]
            mutants.append(Mutant(name, text.count("\n", 0, i) + 1, mutant))
    for pattern, repl, name in _WORD_RULES:
        for m in re.finditer(pattern, text):
            if _skip_occurrence(text, m.start(), comment_prefixes):
                continue
            mutant = text[:m.start()] + repl + text[m.end():]
            mutants.append(Mutant(name, text.count("\n", 0, m.start()) + 1, mutant))
    for pattern, repl, name in _EQ_RULES:
        for m in pattern.finditer(text):
            if _skip_occurrence(text, m.start(), comment_prefixes):
                continue
            mutant = text[:m.start()] + repl + text[m.end():]
            mutants.append(Mutant(name, text.count("\n", 0, m.start()) + 1, mutant))
    return mutants


def run_mutation_test(source_path: Path | str, test_argv: list[str], *, cwd: Path | str,
                      timeout: int = 60, limit: int | None = None) -> dict:
    """Pour chaque mutant : l'écrit, lance test_argv, RESTAURE l'original. Killed si test échoue.

    Retourne {total, killed, survived, score, survivors:[{name,line}]}.
    """
    import shutil
    source_path = Path(source_path)
    cwd = str(Path(cwd).resolve())   # cwd ABSOLU (Windows : un cwd relatif casse CreateProcess)
    # BACKUP SUR DISQUE : survit à un kill dur (SIGTERM/timeout où le `finally` ne
    # tourne pas). Si un backup traîne d'un run précédent tué => on RESTAURE d'abord
    # (auto-réparation), pour ne jamais laisser un fichier muté en place.
    bak = source_path.with_suffix(source_path.suffix + ".mutbak")
    if bak.exists():
        source_path.write_bytes(bak.read_bytes())
    # Octets exacts pour la restauration (évite toute traduction \n<->\r\n Windows).
    original_bytes = source_path.read_bytes()
    bak.write_bytes(original_bytes)
    mutants = generate_mutants(original_bytes.decode("utf-8"), comment_prefixes_for(source_path))
    if limit is not None:
        mutants = mutants[:limit]
    # Résout l'exe (Windows : `node` -> node.exe via PATHEXT, que CreateProcess ne fait pas).
    exe = shutil.which(test_argv[0]) or test_argv[0]
    argv = [exe, *test_argv[1:]]
    killed = 0
    survivors: list[dict] = []
    try:
        for mut in mutants:
            source_path.write_bytes(mut.mutant_text.encode("utf-8"))
            try:
                proc = subprocess.run(argv, cwd=str(cwd), capture_output=True,
                                      text=True, timeout=timeout)
                test_failed = proc.returncode != 0
            except subprocess.TimeoutExpired:
                test_failed = True   # un mutant qui fait boucler = détecté (killed)
            if test_failed:
                killed += 1
            else:
                survivors.append({"name": mut.name, "line": mut.line})
    finally:
        source_path.write_bytes(original_bytes)   # TOUJOURS restaurer (octets exacts)
        bak.unlink(missing_ok=True)                # nettoie le backup en fin normale
    total = len(mutants)
    return {
        "total": total, "killed": killed, "survived": len(survivors),
        "score": round(killed / total, 3) if total else 1.0,
        "survivors": survivors,
    }


def main(argv: list[str] | None = None) -> int:
    import argparse
    import sys
    argv = list(argv) if argv is not None else sys.argv[1:]
    # Découpe manuelle sur `--` (argparse REMAINDER gère mal le marqueur) : tout ce
    # qui suit `--` est la commande de test, verbatim.
    if "--" in argv:
        i = argv.index("--")
        head, test_argv = argv[:i], argv[i + 1:]
    else:
        head, test_argv = argv, []
    parser = argparse.ArgumentParser(description="Mutation testing homegrown (Forge).")
    parser.add_argument("source", help="fichier source à muter")
    parser.add_argument("--cwd", default=".", help="dossier d'exécution des tests")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args(head)
    if not test_argv:
        print("usage: python -m forge.mutation <source> --cwd <dir> -- <cmd de test>", file=sys.stderr)
        return 2
    res = run_mutation_test(args.source, test_argv, cwd=args.cwd, limit=args.limit)
    for stream in (sys.stdout, sys.stderr):        # console Windows cp1252 -> UTF-8 si possible
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    print(f"mutants: {res['total']}  tues: {res['killed']}  survivants: {res['survived']}  "
          f"score: {res['score']*100:.0f}%")
    for s in res["survivors"]:
        print(f"   [SURVIVANT] {s['name']} (ligne {s['line']}) -- un test devrait attraper ce bug")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
