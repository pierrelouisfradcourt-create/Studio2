# ATLAS DES AGENTS DU STUDIO — fiches contrat, mémoire, repo (départ → cible)

- **Date** : 2026-07-12 · **Statut** : PROPOSED (Pierre décide) · `claim_verdict: NO_CLAIM_ALLOWED`.
- **But** : associer à CHAQUE agent sa fiche complète (les 8 points + capacités), dire **qui crée
  quelle mémoire dans quel fichier**, et poser l'**architecture repo de départ et de cible**. Zéro
  freestyle : la fiche = le **contrat d'agent canonique de la Forge** (`scripts/forge/contracts/SCHEMA.md`).
- **Compagnon** : [`STUDIO_ARCHITECTURE.md`](STUDIO_ARCHITECTURE.md) (la vision + le couplage org-chart).

> **⚠ MISE À JOUR 2026-07-15 (auto-audit `scripts/forge/studio_selfaudit.mjs`).** Cet instantané
> date du 12-07. **6 éléments** qu'il décrit comme « cible / MANQUANT / à construire » **existent
> désormais** (construits 12→13-07, vérifiés on-disk) : `knowledge_base/search.mjs` ·
> `knowledge_base/role_sim.mjs` · `scripts/forge/reuse_ratio.mjs` · `scripts/forge/pool.py` ·
> `scripts/forge/contracts/s2.5-artbible.yaml` · `knowledge_base/roles/pursuer-mobile.yaml`. Les
> fiches §2.2/§2.3 (🔴 MANQUANT) ci-dessous sont **périmées** — corrigées inline. Dérive surveillée :
> `node scripts/forge/studio_selfaudit.mjs` (exit 0 = cartes à jour). **État factuel toujours frais**
> (auto-généré) : [`STUDIO_STATUS.generated.md`](STUDIO_STATUS.generated.md).

---

## 0. Le schéma de fiche (les 8 points Critiques + capacités + traçabilité)

Une **planète llm-lego = le contrat de travail d'un sous-agent** (`SCHEMA.md:14`). 16 champs / 10
catégories. **Règle des 3 états** (anti-freestyle mécanique) : un champ Critique **vide ou absent
⇒ agent NON activable** ; un champ optionnel peut valoir `aucun` mais **jamais être absent**.

| # | Point (catégorie) | Champ(s) | Niveau |
|---|---|---|---|
| 1 | Identité / posture | `role` (persona) · `capability_role` (clé registry → modèle) · `exigences_cognitives` | Critique |
| 2 | Contexte / **mémoire** | `memoire` (advisory) · `mandatory_read` (précondition dure) | Critique |
| 3 | Mission | `objectif` | Critique |
| 4 | Frontières | `in_scope` · `out_of_scope` | Critique |
| 5 | Autorisation | `permissions` (read/write/run/create/delete + dossiers) | Critique |
| 6 | **Garde-fou** | `gardeFou` (comportemental, ≠ out_of_scope périmètre) | Critique |
| 7 | Validation | `success_criteria` · `tests_oracles` · `final_report` | Critique |
| 8 | Restitution | `output_contract` | Critique |
| 9 | **Capacités** | `skill` · `plugin` (`aucun` permis, jamais absent) | Important |
| 10 | Traçabilité | `parent_agent` / `delegation_context` | Recommandé |

Résolution du modèle : **jamais en dur** — le contrat déclare `capability_role`, le **registry
`roles.yaml`** résout le runtime (ADR-002 gate 1). **Règle de restitution** : tout `final_report`
cite l'oracle qui appuie chaque affirmation ; sans oracle → pas de claim, remontée HumanGate (fog).

---

## 1. ATLAS DÉPART — les agents qui EXISTENT (prouvés/câblés)

Format compact : chaque fiche = les 8 points. `capability_role`→modèle résolu par `roles.yaml`.

### 1.0 — Orchestrateur · `orchestrator` → **Fable 5** (claude-local, high)
- **objectif** : démarre et pilote /forge (choix de profil, aiguillage A2, décision d'escalade). N'écrit aucun code, n'est pas un tier de build.
- **mémoire** : lit le skill `forge/skill.md` + l'état du run ; **mandatory_read** : `dispatch --dry-run` avant de lancer.
- **frontières** : orchestration seule / ne code aucune étape, ne juge jamais (HumanGate = Pierre).
- **permissions** : spawn via `prepare_dispatch` uniquement ; `run` dispatch/driver.
- **garde-fou** : aucun spawn Forge sans dispatch validé (marqueur `FORGE_DISPATCH`, hook guard).
- **validation** : n/a (ne produit pas d'artefact jugé) ; **restitution** : présente le verdict signé à Pierre.
- **skill** : `forge` (superpowers) · **plugin** : `aucun`.

### 1.1 — s0 Contrat · `contract_author` → **Opus 4.8**
- **objectif** : `charter.yaml` {objectif, hors_scope[], criteres_succes[], actions_interdites[]}.
- **mémoire** : prompt + **pré-mortem PILOU** (`premortem(project)`) injecté ; **mandatory_read** : `SCHEMA.md`.
- **frontières** : cadrer / ne conçoit rien. **garde-fou** : criteres_succes objectifs, actions_interdites explicites.
- **validation** : le charter borne tout le run · **restitution** : `charter.yaml`. **skill/plugin** : `aucun`.

### 1.2 — s1 Prisme · `prisme` → **Opus 4.8**
- **objectif** : `product_snapshot.md` {ce que le joueur voit / fait / ressent, regles_observables[]}.
- **mémoire** : charter (s0) ; **frontières** : photo du produit fini / pas d'archi ni de code.
- **garde-fou** : décrit le perçu, pas l'implémentation · **restitution** : `product_snapshot.md`. **skill/plugin** : `aucun`.

### 1.3 — s2 World Scan · `worldscan` → **Haiku 4.5** (+ skill `world-scan`)  ⟵ RECHERCHE WEB
- **objectif** : `knowledge_packet.json` {patterns[{claim ≤600c, source_url, source_title, relevance}], advisory:true}.
- **mémoire** : product_snapshot ; **mandatory_read** : contexte IMP (read-only) si lancé via `/world-scan`.
- **permissions** : `run: WebSearch/WebFetch` ; **write** : `llm-lego/knowledge/<IMP>.json` UNIQUEMENT (dossier gitignored, non gouverné).
- **garde-fou** : chaque affirmation CITÉE et sourcée (lire la source avant de citer) ; **JAMAIS injecté** aux prompts council ; advisory-only.
- **validation** : `knowledge-validate.mjs` (advisory_only=true, patterns non vide, source_url http(s), claim ≤600c) · **restitution** : packet `world-scan/v0`. **skill** : `world-scan` · **plugin** : `aucun`.

### 1.4 — s3 Décompo · `decompose` → **Opus 4.8**
- **objectif** : `featuremap` (arbre Système→Feature→capacité, chaque feuille {capacité, preuve_attendue}).
- **mémoire** : prisme (+ world-scan advisory) ; **garde-fou** : chaque feuille porte sa preuve attendue · **restitution** : `featuremap`. **skill/plugin** : `aucun`.

### 1.5 — s4 Archi · `architect` → **Opus 4.8** (+ skill `architecture-review`)
- **objectif** : `blueprint.yaml` {modules[], deps_autorisees[], deps_interdites[], ownership{}, invariants_archi[]}.
- **mémoire** : featuremap ; **garde-fou** : deps interdites + ownership = frontière dure du builder.
- **validation** : `check_architecture` (s10b) vérifie les deps réelles vs interdites · **restitution** : `blueprint.yaml`. **skill** : `architecture-review` · **plugin** : `aucun`.

### 1.6 — s5 WireMap · `wiremap` → **Opus 4.8**
- **objectif** : `wiremap` {section=module, features[{feature, fichiers[], fonction, version, preuve, statut}]}.
- **mémoire** : blueprint + featuremap ; **garde-fou** : isomorphe au blueprint ; **le jeu de règles est GELÉ** post-s5 (`wiremap_frozen.json`, jamais réécrit).
- **validation** : `check_wiremap` (s10c) + `check_feature_set_frozen` · **restitution** : `wiremap`. **skill/plugin** : `aucun`.

### 1.7 — s6 Red-team Plan · `redteam_reviewer` → **Qwen 2.5 14B** (lmstudio ; fallback claude-blind)  ⟵ REVIEWER INDÉPENDANT
- **objectif** : `rapport_redteam_plan.md` {angle, faille, correction_proposée} + verdict GO-si-corrigé.
- **mémoire** : blueprint + wiremap ; **frontières** : critique le PLAN / ne code pas.
- **garde-fou** : reviewer INDÉPENDANT (contexte propre) ; si LM Studio :1234 down → fallback **claude-blind tracé** (identité réelle jamais étiquetée Qwen).
- **validation** : advisory (lève des humangate_flags, ne juge pas le code) · **restitution** : rapport. **skill/plugin** : `aucun`.

### 1.8 — s9 Builder · `builder` → **Haiku 4.5** (escaladable haiku→sonnet→opus)
- **objectif** : diff (micro-commits) borné à l'ownership + WireMap à jour. JEU : `solvability.mjs` + `e2e.mjs` câblés dans `run-oracle.mjs`.
- **mémoire** : blueprint (ownership) + wiremap ; **mandatory_read** : `SCHEMA.md`, blueprint, wiremap.
- **frontières** : écrit UNIQUEMENT dans son ownership / ne touche jamais `tests/**`, ne modifie pas l'archi.
- **permissions** : write = fichiers d'ownership + WireMap ; **INTERDIT tests/**. **garde-fou** : respecte ownership + deps interdites, micro-commits.
- **validation** : oracle code vert + (JEU) solvabilité + e2e + gate mutation · **restitution** : `output_contract` diff + WireMap. **skill/plugin** : `aucun`.

### 1.9 — s11 Red-team Code · `redteam_code` → **Opus 4.8** (contexte vierge/aveuglé)
- **objectif** : `rapport_redteam_code.md` {angle, faille, sévérité, reproduction} sur le diff SANS justifs.
- **mémoire** : le diff seul (aucun contexte d'auteur) ; **garde-fou** : advisory, cherche à réfuter · **restitution** : rapport. **skill/plugin** : `aucun`.

### 1.10 — Oracles déterministes s10a/b/c + s12 · `deterministic` → **non-LLM** (provider forge)
- **objectif** : preuves signées — s10a code (`forge_gate`→`oracles.json`→evidence log) · s10b archi (`check_architecture`) · s10c wiremap (`check_wiremap`+gel) · s12 verdict agrégé signé HMAC (`build_aggregate_verdict`, `is_clean_pass`).
- **mémoire** : les artefacts du run ; **permissions** : `run` les commandes d'`oracles.json` (timeout 300s) ; **write** : `lab/forge_evidence/`, `lab/forge_runs/<projet>/verdict.json`.
- **garde-fou** : ZÉRO LLM ; provenance re-vérifiée (reçu absent/altéré → BLOCKED) ; `software_verdict` vient UNIQUEMENT des reçus vérifiés ; red-team = advisory.
- **validation** : `verify_run` (HMAC + évidence relue + preuve mutation) = exit 0 authentique / 2 falsifié · **restitution** : `verdict.json` signé. **skill/plugin** : `aucun`.
- **Volets JEU inclus dans s10a** : e2e structurel (`check_e2e_harness`), solvabilité (bot gagne), property-based, **gate mutation** (`mutation_proof` : baseline verte obligatoire + reçu signé + triage = exception tracée jamais OK propre).

### 1.11 — s10d Capteur visuel · `deterministic` → **non-LLM** — ⚠ ANNEXE ADVISORY
- **objectif** : `visual_mechanical.json` (familles A1/A2/A3/A5, seuils v0) via `quality_sensor/collect.mjs`.
- **garde-fou** : **hors chaîne de promotion** — absent de `dispatch.ORDER`, non câblé au driver, `is_clean_pass` ne le lit pas ; un échec s10d ne bloque/dégrade RIEN. **skill/plugin** : `aucun`.

### 1.S — Services & infra (pas des agents LLM, mais des pièces du système)
- **Connecteurs studio** (`studio_link`, **propose-only**) : #3 Télémétrie (`forge_telemetry.jsonl`) · #4 Kaizen-propose (`forge_ledger_proposals.jsonl`, lane AUDIT_REQUIRED PROPOSED, porte `clean_pass`) · #5 Mémoire projet (`forge_project_proposals.jsonl`) · #6 Journal d'erreurs + **pré-mortem PILOU** (`forge_error_journal.jsonl`, leçons `_global_` vers tous les projets).
- **Driver** (`driver.py`) : machine à états déterministe, reprise après kill (`state.json` atomique), game-ness non-downgradable, escalade en code. **Hook guard** (`hook_guard.py`) : fail-CLOSED en périmètre Forge, **ACTIF depuis 2026-07-10** — câblé dans `.claude/settings.json` (`PreToolUse`/`Task` → `.claude/hooks/pretool_forge_guard.py`), vérifie la signature HMAC de l'audit avant tout spawn marqué `FORGE_DISPATCH:*` (cf. ADR-002 §7).

---

## 2. ATLAS CIBLE — les agents/services à AJOUTER (pour la bibliothèque + l'org chart complet)

### 2.1 — 🔴 KNOWLEDGE ENGINE (service non-LLM) — **existe en embryon**
- **objectif** : admettre + classer les pièces (`representation`/`logic`/`role`) ; index typé + relations + tiers.
- **écrit dans** : `knowledge_base/catalog.json` (le producteur design écrit en tier `candidate`, propose-only).
- **garde-fou** : validateur `kb-validate.mjs` (déterministe, red-teamé) ; `candidate→validated` EXIGE `proof_of_use` d'un jeu gaté vert ; contrôle anti-triche.
- **validation** : `node kb-validate.mjs` exit 0. **skill/plugin** : `aucun`. **État** : catalogue+validateur FAITS ; manque ROLE + relations.

### 2.2 — ✅ SEARCH ENGINE (service non-LLM) — **CONSTRUIT 2026-07-13** (`knowledge_base/search.mjs` + `search.test.mjs`)
- **objectif** : `search.mjs` — filtre déterministe sur l'index (intention → pièces compatibles ; ROLE se lie à REPRESENTATION ssi `affordances ⊇ requires`).
- **permissions** : read `catalog.json` ; **write** : rien (retourne des matches). **garde-fou** : déterministe ; embedding = couche advisory ultérieure, jamais porte d'admission. **skill/plugin** : `aucun`.

### 2.3 — ✅ ROLE-SIM Oracle (service non-LLM) — **CONSTRUIT 2026-07-13** (`knowledge_base/role_sim.mjs`, étend la solvabilité)
- **objectif** : valider un ROLE par SIMULATION — un bot combat le rôle, mesure la **bande de difficulté** (pas juste la victoire).
- **validation** : preuve = `proof_of_use` du ROLE ; **restitution** : reçu signé (comme mutation). **skill/plugin** : `aucun`.

### 2.4 — 🔴 s9 Builder MODIFIÉ — **consulte SEARCH d'abord**
- **objectif (cible)** : interroge SEARCH → importe l'existant → n'écrit que le delta ; `reuse-ratio.mjs` mesuré.
- **garde-fou** : import réel (pas de copie) ; le delta reste borné à l'ownership. Reste sous les mêmes oracles.

### 2.5 — 🔷 ART DIRECTOR + ASSETS (nouveaux contrats, imports CCGS)
- **s2.5-artbible** · `art_director` → **Opus** : `art_bible.md` {style lock, palette, mood, silhouette}. **garde-fou** : ne touche pas les règles (gel s5).
- **s8-assets** · `asset_dresser` → **Haiku** : cherche dans REPRESENTATION via SEARCH, pose les assets sur la géométrie (héritage : la peau suit l'ancre logique). **garde-fou** : **ne modifie JAMAIS les règles/la logique** (agent aveugle « habilleur »).
- **Import** : rôles `art-director`/`technical-artist`/`sound-designer`/`audio-director`/`narrative-director` de `Donchitos/Claude-Code-Game-Studios` (**MIT**) → **convertis en contrats `.yaml`** (16 champs) pour passer `prepare_dispatch`. On prend leur **largeur de rôles** ; **rien** de leur validation (hooks bash + « user decides ») — la nôtre (oracles signés) est supérieure.

---

## 3. PROPRIÉTÉ MÉMOIRE — qui crée quoi, dans quel fichier

| Mémoire / fichier | Qui écrit | Nature | Règle |
|---|---|---|---|
| `memory/` (+ `MEMORY.md`) | **mécanisme auto-mémoire** (Claude Code) | faits durables | jamais un agent Forge ; jamais dupliqué à la main |
| `studio_brain/00_CURRENT_CONTEXT.md` | Claude Code / Pierre | handoff inter-sessions | < 100 lignes, archive dans `journal/` |
| `studio_brain/{doctrine,decisions,...}` | Pierre (ratifié) | doctrine/vision (tier-2) | décisions = ce que Pierre a ratifié |
| `lab/chains/IMPROVEMENT_LEDGER.yaml` | via `kaizen_loop.py` ; Forge **propose** (`propose_ledger_entry`) | ledger canonique | écriture durable = **HumanGate** ; `settings.json` Write(lab/chains/**) en *ask* |
| `knowledge_base/catalog.json` | agents design (tier `candidate`, propose) ; **validateur** admet | index bibliothèque | `validated` = preuve d'un jeu gaté vert |
| `llm-lego/knowledge/<IMP>.json` | **world-scan** (s2 / `/world-scan`) | knowledge packet web | **gitignored, non gouverné**, advisory-only |
| `lab/forge_runs/<projet>/{state.json,verdict.json,artifacts/}` | **driver** + oracles | état + verdict signé | atomique, reprise après kill |
| `lab/forge_evidence/*.log,*.jsonl` | oracles + connecteur télémétrie | preuves + tokens/durée | evidence relue par `verify_run` |
| `lab/reports/forge_*.jsonl` | connecteurs 4/5/6 (propose-only) | propositions + journal PILOU | jamais de mémoire de référence sans HumanGate |
| `lab/forge_sensors/<jeu>/visual_mechanical.json` | s10d capteur | advisory visuel | hors promotion |

**Invariant** : un agent Forge n'écrit JAMAIS seul dans une mémoire de référence (ledger, projets,
`memory/`). Il **propose** (connecteurs propose-only) ; Pierre ratifie (HumanGate).

---

## 4. ARCHITECTURE REPO — départ → cible

### Départ (réel aujourd'hui)
```
scripts/forge/
  contracts/{s0..s12}.yaml · s10d-oracle-visual.yaml · roles.yaml · SCHEMA.md · PLAYABLE_CONTRACT.md
  dispatch.py · driver.py · runtime.py · gate.py · oracle.py · verdict.py
  mutation.py · mutation_proof.py · static_oracles.py · verify_run.py · studio_link.py · escalate.py · hook_guard.py · contract.py
  oracles.json · templates/solvability.template.mjs
.claude/skills/{forge,world-scan,...}/skill.md
knowledge_base/                      # catalog.json + kb-validate.mjs + assets/systems/patterns/proofs (bibliothèque, admission seule)
games/<jeu>/                         # jeux forgés (run-oracle.mjs 4 volets)
llm-lego/knowledge/                  # packets world-scan (gitignored)
lab/{forge_runs,forge_evidence,forge_sensors,reports}/
```

### Cible (ajouts — 🔴 à construire · 🔷 à importer MIT)
```
knowledge_base/
  catalog.json                       # + types 'role' et 'representation/logic' enrichis (affordances, requires, relations)
  search.mjs 🔴                       # SEARCH ENGINE déterministe (+ search.test.mjs)
  roles/                             # 🔴 contrats ROLE gameplay (requires + proof)
scripts/forge/contracts/
  s2.5-artbible.yaml 🔷 · s8-assets.yaml 🔷   # branche ART (imports CCGS convertis)
  s-role-sim.yaml 🔴                  # oracle simulation ROLE (bande de difficulté)
scripts/forge/
  reuse-ratio.mjs 🔴                  # mesure la réutilisation d'un jeu (s9 cible)
  agents_ccgs/ 🔷                     # 49 rôles Claude-Code-Game-Studios convertis en contrats
```
Le **s9-build** cible interroge `search.mjs` avant d'écrire (importe l'existant, n'invente que le
delta). Le reste de la colonne (Assembler/Oracle/Verdict/HumanGate) **ne change pas** : elle est
déjà prouvée.

```
software_verdict: (aucun — doc d'architecture)
evidence_verdict: MECHANICAL_VALIDATION_ONLY (fiches remplies depuis les .yaml/scripts réels + cartographie vérifiée)
claim_verdict: NO_CLAIM_ALLOWED
```
