# Game Knowledge Base — règles d'admission

Mémoire de production du studio : **ingestion, classification, orchestration** de composants open
source existants, consommés par le Forge pour ASSEMBLER des jeux. C'est de la **donnée + du code**,
PAS un 4e référent mémoire (ne concurrence ni `memory/`, ni `studio_brain/`, ni `MEMORY.md`).

Contrat complet : [`docs/forge/KB_INGESTION_CONTRACT.md`](../docs/forge/KB_INGESTION_CONTRACT.md).
Cadre runtime : [`docs/forge/STUDIO_RUNTIME_ARBITRATION.md`](../docs/forge/STUDIO_RUNTIME_ARBITRATION.md).

## Le validateur est la porte

```bash
node knowledge_base/kb-validate.mjs knowledge_base/catalog.json   # exit 0 = conforme
node --test knowledge_base/kb-validate.test.mjs                   # 29 tests des regles R1..R12
```

Aucune entrée n'existe « parce qu'on l'a écrite » : elle existe **si le validateur l'accepte**.
Le validateur est déterministe, non-LLM, sans réseau.

## Deux contraintes non négociables (P0/P1, ne pas redécouvrir)

1. **Runtime honnête.** Seul HTML/JS/canvas/Playwright est prouvé. On ingère+consomme le 2D
   compatible HTML. Le **3D + addons Godot** sont **catalogués en métadonnées, jamais téléchargés
   ni consommés** (`ingested:false`, `runtime:godot`, `path:null`) tant qu'un validateur Godot
   n'existe pas et n'est pas prouvé. Règle R6.
2. **Licences.** CC0/MIT/CC-BY → ingestion OK. GPL → **patterns/concepts cités UNIQUEMENT, jamais
   de code** (le GPL contamine un jeu distribué). Un `system` en CODE vient d'une source permissive
   ou d'une **réécriture propre** inspirée d'un pattern cité. Règles R4/R5/R11.

## Tiers

| Tier | Signification | Exigence |
|---|---|---|
| `candidate` | admis (schéma+licence+provenance conformes), non prouvé en jeu | défaut |
| `validated` | prouvé en jeu | `proof_of_use` = chemin d'un run-oracle **vert** d'un jeu qui l'importe/l'affiche réellement (bricks) ; `usage_examples` non vide (assets). Sans preuve → REJET |

Les **patterns** restent `advisory` à vie (cités, jamais injectés comme code — régime world-scan).

## Politique de téléchargement

**Tout octet réseau nouveau = gate Pierre explicite** (pack, URL, licence, taille). Pas d'ingestion
de masse. Le noyau actuel a été ingéré **par copie locale** d'assets CC0 déjà présents dans le repo
(`games/leviathan/public/assets/`, provenance `games/leviathan/CREDITS.md`) — zéro octet réseau.

## Contenu actuel (noyau minimal — `catalog.json`)

- **Assets 2D ingérés (3)** : sprites Kenney « Top-down Shooter » CC0 (2 personnages, 1 créature).
- **Assets 3D manifest-only (3)** : Quaternius, KayKit, Poly Haven — CC0, **non téléchargés**.
- **Patterns cités (3, GPL-safe advisory)** : `pat-damage-floor` (Wesnoth), `pat-full-reachability`
  (SPD), `pat-zone-of-control` (Wesnoth).
- **Systèmes MIT (2, tier candidate)** : `sys-damage-floor`, `sys-reachability` — réécritures
  propres inspirées des patterns, purs, testés (property-tests d'invariants).

## Structure

```
catalog.json          index pivot unique (données)
kb-validate.mjs        validateur non-LLM (R1..R12) + kb-validate.test.mjs
assets/                2D ingéré ; 3D = manifest-only (jamais de fichier sur disque)
systems/               CODE permissif / réécriture propre uniquement
patterns/              fiches .md citées, GPL-safe, advisory
templates/             squelettes d'assemblage (spec, pas un moteur)
proofs/                évidences de gate vert référencées par proof_of_use
```
