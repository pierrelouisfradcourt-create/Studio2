# V2 — GIT, BLENDER, GODOT : ce qui est requis, et par quoi

*2026-09-02 · suite des décisions Pierre. **V1 non modifié** (`58095ba9`, 4 fichiers de l'autre
session en écart, inchangés).*

---

## 1 · Git — **fait, et il ferme 6 échecs sur 6**

```
git init dans Desktop/Studio     0 commit — aucun historique V1 importé
```

### Puis une seconde cause, qu'il fallait traiter aussi
Trois des six tests continuaient d'échouer après l'init, et ils avaient raison :

> `evidence_seal` **utilise `.gitignore` comme CRITÈRE** — une preuve n'est scellée que si elle est
> versionnable. Le `.gitignore` de V2 comptait 4 lignes ; celui de V1, 219. Sans la règle `*.log`,
> un flux de bruit devenait « scellable », et le sceau ne voulait plus dire la même chose.

**`.gitignore` récupéré de V1 et restreint aux surfaces V2** — Rocky, lane STUDIO et `lab/` **non
repris** (les importer aurait réintroduit V1 par la bande). Les règles reprises portent leur raison :
`*.log` + l'exception `!knowledge_base/proofs/*.log`, `forge/*.config.json` (chemins de poste) avec
le gabarit `.example.json` versionné, `.godot/` et `*.uid`, les sorties de run régénérées.

```
6 tests Git         →  6 PASS
```

**Ce fichier n'est pas un confort de dépôt : c'est un mécanisme de preuve.** C'est écrit en tête du
`.gitignore` V2, pour que la prochaine main qui l'édite le sache.

## 2 · ⚠ Une dépendance que mon inventaire avait manquée : `docs/`

En vérifiant les 2 échecs restants de `commit_scope_guard`, la cause remonte plus loin qu'un
périmètre :

```
fichiers docs/*.md cités par les contrats et le code   : 59
   présents en V1                                      : 56
   présents en V2                                      :  0
dont cités en `mandatory_read` d'un contrat d'agent    :  9
```

> **`mandatory_read` est la « précondition dure » d'un contrat d'agent.** Neuf contrats désignent
> aujourd'hui des fichiers qui n'existent pas en V2 — **exactement le défaut de référence fantôme
> que j'ai signalé pour `.claude/settings.json`, mais dans les contrats.**

`docs/forge/` = 149 fichiers / 2,4 Mo en V1. **Je n'ai rien copié** : cette surface n'est pas dans
l'inventaire que tu as ratifié. Le critère mesuré existe si tu veux trancher vite : **56 fichiers
réellement cités**, dont 9 en `mandatory_read`.

## 3 · Blender / Godot — la matrice, mesurée

| capacité V2 | Blender | Godot | requis au démarrage ? |
|---|---|---|---|
| **Forge core** (contrats · dispatch · verdict · KB) | non | non | **non** |
| **oracles code / archi / wiremap** (s10a-c) | non | non | **non** |
| **Pong — volet navigateur** | non | non | **non** — *mesuré vert en V2 sans Godot configuré* |
| **gameplay / build d'un jeu** | non | **selon le jeu** | non — conditionnel |
| **volet visuel Godot** (`capture_godot.mjs`) | non | **oui** | non — **capacité conditionnelle** |
| **solvabilité / oracle produit Godot** (`solvability_godot`, `product_oracle_godot`) | non | **oui** | non — conditionnelle |
| **asset producer** (`asset_producer/`, `asset_geometry/oracle.py`) | **oui** | non | non — conditionnelle |

**Consommateurs mesurés :**
```
godot_bin  : godot_oracle.mjs · product_oracle_godot.py · mutation_proof.py · run_real.py · asset_dispatch.py
blender_bin: asset_geometry/oracle.py · asset_producer/asset_dispatch.py
```

### Ce que la matrice change pour les jeux migrés
```
8 des 9 jeux récupérés portent un project.godot   (seul `breakout` est purement web)
```
> **Godot n'est donc pas optionnel pour *jouer* la plupart des jeux repris** — mais il reste
> **conditionnel pour le Studio** : la Forge, ses oracles déterministes, la KB et le volet
> navigateur tournent sans lui. **La distinction tient : dépendance de capacité, jamais
> précondition globale.**

**Ni Blender ni Godot ne sont installés/configurés pour faire passer des tests.**
`godot.config.json` et `blender.config.json` portent des chemins de poste ; ils sont **ignorés par
`.gitignore` par construction** et restent à configurer localement, comme `.forge_key`.

## 4 · `EVIDENCE/bundles/asset_lessons` → `NOT_YET_PRODUCED`

Reclassé, comme tu l'as tranché. **Le dossier n'a pas été créé artificiellement** : un répertoire
vide fabriqué pour verdir une assertion mesurerait la fabrication, pas la production.

---

## État après ce lot

```
MIGRATION
  1–9                CLOSED
  A agent_policy     CLOSED / OUT_OF_SCOPE          0 appelant
  B workflow_lab     CLOSED / GUARD ONLY            interdit conservé
  C games/           CLOSED / 0 chemin actif        418 migrations, clé de schéma intacte

VALIDATION
  imports forge      PASS  50/50        .claude          PASS  0 fantôme
  chemins runtime    PASS               Observer         PASS  43
  KB                 PASS  50           Pong W-2 browser PASS
  contrats           PASS  28           lots de session  PASS  104 tests
  Git                PASS  6/6          .gitignore-preuve PASS

RESTANT
  docs/ (59 cités, 0 présents, 9 en mandatory_read)   ⚠ DÉCISION — hors inventaire ratifié
  reference_guard (2 tests)                            OUT_OF_SCOPE — capacité RETIRE ratifiée
  commit_scope_guard (2 tests)                         dépend de `docs/` + asset_lessons
  Blender / Godot                                      CAPACITÉS CONDITIONNELLES, non préconditions
  asset_lessons                                        NOT_YET_PRODUCED
  Pacman 00_CHARTER · 09_WIREMAP                       UNAVAILABLE @ 58095ba9
  Q2 / R8                                              UNTOUCHED
```

```
status_by_surface:
  git_v2:               TESTED   # init, 0 commit, 6/6 tests
  gitignore_preuve:     TESTED   # récupéré et restreint ; critère d'evidence_seal restauré
  docs_manquants:       TESTED   # 59 cités / 0 présents / 9 mandatory_read
  matrice_externes:     TESTED   # consommateurs mesurés, aucune précondition globale
  asset_lessons:        NOT_YET_PRODUCED
  suite_complete:       BLOCKED  # après décision `docs/`
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
