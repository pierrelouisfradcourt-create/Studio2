# Lot B — s2.7 devient GAME MASTER : traducteur du monde découvert en jeu mesurable, + contrat GM ↔ Artiste

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD strict, fixtures RÉELLES (run 9 archivé
> `lab/forge_runs/kitten_clicker/_run9_20260823a/` ; Art Bible = `art_bible.md` du run 9, qui n'a PAS encore les 8 sections du Lot A —
> fixture synthétique pour ces cas). Jamais de commit par un sous-agent ; un commit de clôture (gate Pierre).
> **Aucune station nouvelle, aucun profil nouveau, aucun oracle LLM, aucun gameplay Kitten Clicker (Lot C).** Mesure joueur inchangée
> (`loop.json`, sondes, gates).

*Date : 2026-08-23 · Source : cadrage Pierre « Lot B » (3 niveaux de métriques, 6 boucles, 9 sorties obligatoires, contrat de retour
GM ↔ Artiste sans station nouvelle), après Lot A `497c54b` et audits `docs/audit/2026-08-23-kitten-clicker-*.md`.*

**Goal :** qu'AVANT le Builder, un artefact déterministe dise pour chaque élément important : WHY → règle → métrique → preuve →
représentation visuelle → consommation Builder ; et que l'aval (Prisme, Grey Blocks, Builder) PROUVE qu'il l'a consommé.

## Réalité de la chaîne (après Lot A) et ce que « retour GM ↔ Artiste » veut dire ici
```text
s2 World Scan → s2.6 Story Bible → s2.5 Art Bible (Art Director) → s2.7 GAME MASTER → s1 Prisme → s3 Grey Blocks → s5 WireMap → s9 Builder
```
L'Art Director passe AVANT le GM : il ne peut pas répondre au GM dans le même run. Sans station nouvelle, le retour est un **contrat
d'artefacts** : le GM émet `artist_requirements[]` (id, état, besoin joueur, exigence visuelle, grey block) ; le Builder — qui réalise
aujourd'hui les assets (`04_ASSETS`, SVG) — dépose `04_ASSETS/art_response.json` : une entrée par requirement (asset réalisé, nœud/groupe,
états représentés, affordance), vérifiée déterministiquement (complétude 1:1, fichiers existants, états couverts). Au run suivant, l'Art
Director reçoit l'`art_response` précédente (héritage) — c'est le « à terme » bidirectionnel, sans station.

## Verrous GO Pierre 2026-08-23
- **Modèle s2.7 → Opus** (champ modèle du contrat ; pas de station). **Gates dès le run 10** pour `art_response` 1:1 et « aucune
  constante économique en dur » (pas d'advisory : le run 9 a prouvé que l'advisory n'est jamais lu par le builder).
- **Retour Artiste ↔ GM = contrat d'artefacts INTER-RUN** : `art_response` ne meurt pas dans le Builder. Mécanisme sans système
  nouveau : dossier `lab/forge_runs/<projet>/heritage/` (persistant entre runs, comme `tasks.json`/`design_intent.md`) ; le driver y
  copie en fin de run (DONE ou HALTED après s9) `art_bible.md`, `gm_worldscan.json`, `<build>/04_ASSETS/art_response.json` (+
  sha, run_id) ; `_UPSTREAM_BY_STEP` : s2.5 ← `heritage/art_bible.md`, `heritage/art_response.json` ; s2.7 ← `heritage/art_response.json`,
  `heritage/gm_worldscan.json` (fichiers absents = omis, comportement inchangé au 1er run). Le manifeste de dispatch prouve le chargement.
- **Boucles TESTABLES** : chaque boucle comporte au minimum les étapes action joueur → feedback → récompense → progression → prochaine
  décision, et chaque étape porte `metric_ref` (id de `progression_metrics`) et `proof_ref` (id de `proof_model`) — une étape sans
  métrique ni preuve = refus du bloc `game_master`.
- Aucun nouveau système d'orchestration : artefacts existants + validateurs de matérialisation + contrats + sondes existantes.

## Sorties obligatoires du GM (`gm_worldscan.json` → renommage NON : on garde le fichier, on AJOUTE un bloc `game_master`)
`gm_worldscan.json` conserve son scan de genre (`dimensions`, `games_observed`, `sources_consumed` du Lot A) et gagne **`game_master`** :
```text
game_master:
  world_interpretation   : ce que le monde découvert (World Scan + Story + Art) impose au jeu (≥ 3 faits cités par adresse)
  loops:
    core_loop            : action → réponse → récompense → décision → répétition
    progression_loop     : action → ressource → achat → capacité → nouveau palier
    player_loop          : objectif → action → feedback → compréhension → prochain objectif
    content_loop         : déblocage → nouveau contenu → exploration → collection
    meta_loop            : fin de niveau → prestige/reset → bonus permanent → nouvelle possibilité
    economy_loop         : sources → stock → sinks → rendement → nouveau pouvoir d'achat
    (chaque boucle = liste ordonnée d'étapes {id, kind ∈ action|feedback|reward|progression|decision|other, actor PLAYER|SYSTEM, affordance?, hud?, why, metric_ref, proof_ref})
  economy_model          : ressources {id, unité, sources[], sinks[], stock_initial}, formules nommées (coût(n), gain(n)) en
                           texte + paramètres numériques
  progression_metrics[]  : {id, kind ∈ invariant | target | observation, value | range:{min,max}, unit, why, proof_ref}
                           invariant = CONTRAIGNANT (coût, seuil, bonus, condition de déblocage) · target = contraignant + tolérance
                           (durée cible d'un palier) · observation = mesurée, non bloquante (durée réelle, nombre de clics)
  proof_model[]          : {id, measures: metric_id | loop_step_id, how ∈ player_loop | decision | registry | hud | humangate,
                           expected: texte observable}
  grey_blocks[]          : {id, type ∈ LOCATION|ACTOR|ITEM|RULE|UI|RESOURCE, role ∈ PROGRESSION_GATE|AFFORDANCE|FEEDBACK|REWARD|
                           CONTENT|META, state ∈ LOCKED|AVAILABLE|OWNED|PLACED|CONSUMED, requires[] (metric_id / grey_block_id),
                           player_meaning, builder_contract: texte, proof_ref}
  artist_requirements[]  : {id, grey_block: id, states_to_show[], visible_reason: bool, visible_requirement: texte, preview: bool,
                           affordance_visual: texte, readability: texte}
```
Vocabulaire fermé, adressable : `gm_worldscan:game_master.<bloc>[.<id>]` (le schéma d'adresse de s1 admet déjà `gm_worldscan:`).

## Consommation prouvée (aucun oracle nouveau : validateurs de matérialisation + contrats + checks existants)
- **Prisme (s1)** : toute exigence `acteur: PLAYER` ou de `loop_role ≠ NONE` cite une adresse `gm_worldscan:game_master.loops.*` ou
  `…grey_blocks.<id>` ; `validateExigence` (additif) signale les exigences de boucle sans source GM ; `check_prisme` compte
  `exigences_sourcees_gm`. Baseline run 9 (sans `game_master`) → 0/13, mesuré.
- **Grey Blocks (s3)** : chaque `grey_blocks[].id` du GM apparaît comme feuille (ou `source_ref`) de la featuremap → `check_decompo`
  finding `grey_block_non_decompose` (stats `grey_blocks_couverts`).
- **Builder (s9)** : (a) `03_WORLD/economy.json` = projection DÉTERMINISTE de `economy_model` + `progression_metrics[kind=invariant]`
  (écrite par l'exécuteur dans le run_dir comme `loop.json`, copiée sha-égale par le builder ; test statique : aucune constante
  numérique de coût/seuil/bonus dans `05_SYSTEMS` hors lecture du registre — liste de tokens, même patron que `check_loop_bypass`) ;
  (b) `04_ASSETS/art_response.json` 1:1 avec `artist_requirements` (validateur déterministe `check_art_response`).
- **Cibles (targets)** : `proof_model` + `progression_metrics[kind=target]` → mesurées par la sonde existante quand `how = player_loop`
  (durée = `frames` du step rapporté dans `data.steps[].frames` — ajout minimal à la sonde : compter les frames par step) ; écart
  hors tolérance = FAIL du step ; `observation` = rapportée seulement.

---

### T1 — Schéma + validateur du bloc `game_master` (code)
**Files :** `scripts/forge/run_real.py` (`_validate_gm_worldscan` étendu), nouveau `scripts/forge/game_master_schema.mjs` (vocabulaire
fermé, validateur Node exportable, CLI) + test, `scripts/forge/tests/test_gm_game_master_block.py`.
- `game_master` obligatoire (après Lot B) : 9 blocs présents ; 6 boucles non vides ; `progression_metrics` ≥ 1 invariant + ≥ 1 target ;
  `proof_model` couvre chaque métrique `invariant|target` ; `grey_blocks` ≥ 1 avec `requires` résolus (ids existants) ;
  `artist_requirements` ≥ 1 par grey block de type LOCATION|ACTOR|ITEM|UI ; `why` non vide partout. Refus nommé par bloc.
- Baseline : `gm_worldscan.json` du run 9 → refusé « game_master absent ».

### T2 — Contrat s2.7 = Game Master (texte) + `_materialize` de `economy.json`
**Files :** `scripts/forge/contracts/s2.7-gm-worldscan.yaml` (objectif, in_scope, out_of_scope RÉÉCRITS : concevoir CE jeu à partir
des 3 sources ; garder le scan de genre comme section 1), `scripts/forge/run_real.py` (`_materialize_economy` : `run_dir/economy.json`
dérivé, reçu `economy_check`), `_UPSTREAM_BY_STEP` ×2 : s9 ← `economy.json` ; s1 ← inchangé (reçoit déjà s2.7).
- Le GM écrit les 3 niveaux de métriques ; exemple contractuel obligatoire (format Pierre : unlock garden / requires / player_need /
  visual_requirement / grey_block).

### T3 — Consommation aval : Prisme, Grey Blocks, Builder, Artiste (code + contrats)
**Files :** `upstream_schema.mjs` (+test), `check_prisme_manifest.mjs` ou équivalent (stats), `check_decompo.mjs` (+test), nouveau
`check_art_response.mjs` (+test) et `product_oracle_godot.check_economy_bypass` (tokens), contrats `s1-prisme.yaml`, `s3-decompo.yaml`,
`s9-build-godot-standard.yaml` (règles (14) economy.json sha-égal + (15) art_response 1:1), `driver.py` (appel de
`check_art_response` + `check_economy_bypass` dans le bloc produit, advisory au premier run, gate ensuite — décision Pierre).
- Baselines sur le build run 9 : `art_response.json` absent → FAIL nommé ; constantes en dur (`pricing.gd:9-12`, `prestige.gd:9`) →
  violations listées.

### T4 — Sonde : frames par step + tolérance des targets (code minimal)
**Files :** `player_loop.gd`, `test_player_loop_probe.py`, `loop_spec.mjs` (step porte `target_frames:{min,max}` dérivé de
`progression_metrics[kind=target]` quand `proof_ref` pointe ce step).
- `data.steps[].frames` ; FAIL si hors `[min,max]` quand présent. Baseline : sans target → inchangé.

### T5 — Confrontation Fable + commit. Pas de run (Lot E).
Node complet (0 fail), pytest Forge ciblé, dry-run 17/16, `diff --check`. Preuve par fixtures ; 1ʳᵉ traversée réelle = run 10 après C/D.

## Hors périmètre
Calibration Kitten Clicker (C) · fuites de mesure J/tri/design_intent (D) · run 10 (E) · station Artiste de retour (à terme) ·
gates historiques · `check_wiremap_contract`.

## Risques nommés
- Le GM (haiku aujourd'hui, `s2.7` modèle `claude-haiku-4-5`) : un bloc `game_master` à 9 sorties contraintes dépasse probablement
  haiku → **modèle du contrat s2.7 à passer à Opus** (décision de contrat, pas de station ; coût ≈ +3-5 $/run).
- Double vérité économique si le builder garde des constantes : le check de tokens est la seule garde ; la mutation ne le voit pas.
- Le Prisme devient dépendant du GM : si `game_master` est refusé, s2.7 échoue (pool retry), s1 ne tourne pas — voulu.
