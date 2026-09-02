# PROVENANCE — Studio V2

Repo source : `C:\TACTICAL_CHESS_STUDIO` · branche `master` · HEAD `d6c2510c1f83633a869f0ab1c439e6a2afc8cc4d` · 2026-09-01
Copie **bit-à-bit** (`cp -p`). Vérification : **636 fichiers copiés comparés par `cmp`, 0 différence.**
(La vérification initiale portait sur 637 : `MASTER_SCHEMA.html` en faisait partie tant qu'il
était une copie. Il est depuis une construction neuve — voir plus bas.)

| destination V2 | source | fichiers | exclusions |
|---|---|---:|---|
| `MASTER_SCHEMA.html` | **NON COPIE — construction neuve** | 1 | voir `derived_from` ci-dessous |
| `FORGE/forge/` | `scripts/forge/` | 463 | `contracts/archive/` (36 contrats one-shot) |
| `FORGE/control_plane/` | `control_plane/` | 2 | — |
| `FORGE/openclaw/` | `openclaw/{capabilities,providers}.yaml` | 2 | le reste d'`openclaw/` |
| `knowledge_base/` | `knowledge_base/` | 129 | `catalog.broken.json` |
| `TOOLS/observer/` | `scripts/observer/` | 40 | — |
| `.claude/` | `.claude/{settings.json,hooks,skills/forge,agents,rules}` | 28 | 9 hooks de session/git |

Produits par la mission (pas des copies) : `RECONSTRUCTION_AUDIT.md`, `PROVENANCE.md`, `GAMES/PLAN_STATUS.md`, `TOOLS/README.md`.

## `MASTER_SCHEMA.html` — derive, pas copie

Le Master Schema V2 n'a **pas** de `copied_from` / `sha256` : ce n'est pas une copie.
L'ancien document est **matiere premiere**, pas source d'autorite.

```
derived_from:
  - ancien MASTER_SCHEMA (docs/forge/STUDIO_MASTER_SCHEMA.html, rev. 2026-08-28)
  - Forge reellement retenue      FORGE/                     467 fichiers
  - KB reellement retenue         knowledge_base/            129 fichiers
  - outils reellement consommes   TOOLS/ + .claude/           69 fichiers
  - rail des jeux verifie         GAMES/RAIL_REGISTER.md      25 noeuds
  - preuves disponibles           verdicts signes, imports executes, greps de consommateurs
mesure_a : repo source @ d6c2510c, 2026-09-01
statut   : SOURCE CANONIQUE. L'ancien schema redevient materiau historique, sans autorite,
           et reste dans le repo source (non copie ici, aucune archive dans le V2).
methode  : chaque section de l'ancien document adjugee KEEP / MODIFY / REMOVE / ADD,
           avec preuve — table complete au §11 du document.
volume   : 125 510 o -> 28 492 o (4,4x plus petit).
```
