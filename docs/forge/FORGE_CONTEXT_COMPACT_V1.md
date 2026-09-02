# FORGE_CONTEXT_COMPACT_V1

Contexte opératoire compact. Source de briefing pour tout agent reprenant le travail.
Rev. 2026-07-31 · remplace la lecture de l'historique narratif · tout est **vérifié contre le dépôt** (index des preuves en 08).
`claim_verdict: NO_CLAIM_ALLOWED`

## 00_PURPOSE

La Forge est une chaîne de production de jeux assistée par IA dont la raison d'être est de **préserver la boucle** :
`Humain → intention → agent → action → retour → humain`.
La menace n'est pas une IA hostile, c'est la **rupture de boucle** : l'humain perd le contact avec le réel, l'agent optimise un objectif incomplet. Une machine puissante sans retour humain devient aveugle.
L'IA augmente un pilote humain qui garde : intention · jugement · direction · compréhension du réel.
**Mission active : réparer l'écart Déclaration → Validation → Exécution → Preuve.**
Principe directeur : **« Si ce n'est pas branché, ce n'est pas un système. »** Un fichier jamais lu = documentation. Une mémoire jamais injectée = artefact. Un validateur jamais appelé = décoration. Un contrat jamais consommé = déclaration.
Objectif : **pas une Forge plus grosse — une Forge qui dit vrai sur elle-même.**

## 01_INVARIANTS (ratifiés, non négociables)

1. `software_verdict` = reçus d'oracle vérifiés UNIQUEMENT · red-team advisory · HumanGate (Pierre) décide · `NO_CLAIM_ALLOWED` partout.
2. Aucun sous-agent sans contrat validé (porte `prepare_dispatch` + hook fail-closed).
3. Oracles déterministes non-LLM · verdict HMAC re-vérifié (`forge.verify_run`).
4. **Producteur avant validateur** : un champ vérifié que rien ne produit → construire le producteur, jamais durcir la validation.
5. Diversité cognitive > profondeur partout · matrice rôle→modèle modifiable uniquement après mesure sur tâche réelle (jamais benchmark).
6. Preuve de variance : toute métrique qui classe/génère/calibre prouve ≥2 valeurs distinctes avant usage.
7. La preuve ne remplace jamais l'exécution produit · points d'entrée vérifiés en ABSENCE comme en présence.
8. Mémoire 4 couches Run→FailureEvent→Lesson→Doctrine · écriture jamais ascendante (2→3 = curation humaine/CLI, choix de conception).
9. Aucune décision dans un commentaire — champ structuré consommé, sinon rien.
10. Budgets de mission bornés en coût ET en appels · constante ambiante (~32,8k tk/appel) défalquée à la lecture des coûts.
11. Anti-accrétion documentaire : toute nouveauté modifie une vue ou n'entre pas · historique hors canon · un correctif ne survit pas à son application · flèches toujours qualifiées [M]/[D]/[X]/[B].
12. Périmètre gelé `scripts/forge/**` etc. : modification par LOT borné autorisé par Pierre, preuve avant intégration, re-gel + baseline après commit.

## 02_REALITY_MAP (état mesuré, 2026-07-31)

**Chaîne ALLER — solide [M]** : porte+hook · driver FIFO (`order_for_profile`, aucun agent ne choisit l'étape suivante) · profil réel `standard_godot` = 5 étapes (s9-godot → s10a → s10s → s11 → s12), 16/24 runs · oracles s10a/s10s les plus exécutés · verdict signé · garde de référence à chaque run · suite **1321 passed / 1 skipped**.
**Contexte agent** : le contrat gouverne **~8 %** du contexte reçu (~2,6-3k tk) ; **~92 % ambiant non déclaré** (32 775 tk : hook SessionStart + CLAUDE.md + .claude/rules + settings.local, via `cwd=REPO_ROOT`). Pré-mortem en **position 16/18** (commande avant mémoire ; session Claude Code = inverse). `context_budget: OK` mesure les 8 % seuls.
**Permissions** : contrat YAML = plafond d'intention ; plancher réel = `_STEP_TOOLS` (Python en dur) — 5 étapes ont des outils, 7 ont zéro par défaut ; s11 n'a que `Read` (son rapport = stdout persisté par le driver). Ligne d'audit signée porte `allowed_tools=()` = **sous-déclaration**. 3 verrous deny absolus seulement (settings.json, reference_protected.yaml, HUMAN_GIT_OVERRIDE) ; tout le reste **détecté jamais empêché** (CLAUDE.md mécaniquement modifiable).
**Rôles** : `run_orchestrator` réel (6 dispatches, uniquement Pong) — runs Snake lancés directement via `run_real.py`. Pas de « directeur ». `architect` hors du profil réel. Workers non unifiés (`builder` haiku / `game_forger` opus — c'est game_forger qui tourne). Opus porte 7-9 casquettes. `reasoning` attaché au modèle, pas au rôle (verrou R1).
**Mémoire cognitive** : journaux par DOMAINE (`error_journal/{forge,html,playtest}.jsonl`, 65 entrées, 22 résolues `fixed`). Jamais par rôle. `CAUSE_MUTATION_TARGET` (cause→rôle) existe avec **zéro appelant**. Un jeu lit le domaine `html` (`_domain()` d'avant Godot) → les 4 leçons playtest résolues (dont « bande de vitesse jouable », utile Breakout) **illisibles par un builder**. `lessons.jsonl` absent du disque ; pré-mortem dégradé à 3 leçons legacy ; **producteur failure_event DÉCLENCHÉ EN PROD** (campagne Breakout run 1 : `lab/reports/failure_events.jsonl` créé, `fail-59097e0c915c4646`, timeout s9 — leçon vide par doctrine, propositions L1-L5 au dossier de gate).
**WHY/WHEN** : NOT_FOUND. `activation` = compteur de tentatives ; `ts` = horloge. Seul WHY construit = escalade (`escalate.py`) — persisté si REFUSÉE (`humangate_notes`), **perdu si réussie** (logger sans FileHandler).
**KB** : catalogue 34 entrées, 0 `provides` · fouille 5/5 `matchCount:0` (catalogue vide du sujet — briques card_engine jamais promues : 10 décisions ratifiées en attente de `apply_decisions --apply`, geste Pierre, dry-run vérifié 0 conflit) · réutilisation Snake majoritairement hors index (25/44 lignes de Pong direct ; 3 artefacts KB dont 2 non catalogués) · `propose_brick` : 10 sites d'appel, fichier de propositions jamais matérialisé.
**Prisme** : `panel.py` câblé (via `--charter`), mono-modèle, lentilles sans droit d'écriture (méta-rapports) · 3 contrats de lentille non dispatchables · 1re mesure : Jaccard 0,909 archidepot~gameplayprog, ininterprétable sans plancher Intra (jamais mesuré).
**s10d oracle visuel** : structurellement non dispatchable (absent des 3 registres) — le capteur du défaut « Snake ne démarre pas ».
**Mutation régime descripteur V1** : évaluation de FORME seule, aucun exécuteur.
**Représentation** : 4 vues HTML, légende 6 statuts, flèches qualifiées, changelog sorti du canon (HISTORY.md). VUE 3 runtime, VUE 4 pilotage.

## 03_ROOT_CAUSES

**RC1 — Les décisions vivent dans le lieu qui n'exécute pas** (permissions YAML vs plancher Python ; doctrine roles.yaml vs prose skill.md ; curriculum ×2 ; budget vs wiremap). La règle de câblage existe pour les artefacts, jamais étendue aux déclarations.
**RC2 — « Fini » n'incluait pas « inséré dans la boucle »** : la chaîne retour a été construite modules-d'abord sans consommateur forcé → producteurs-sans-consommateurs en série. (Règle corrigée depuis : l'insertion dans un profil fait partie de la définition de fini.)
**RC3 — Le contexte a deux propriétaires, aucun arbitre** (contrat 8 % / harnais 92 %).
**RC4 — « L'agent » n'existe pas comme objet** : modèle×raisonnement×mémoire×outils×contexte×mission×moment éparpillés sur 6 supports ; aucune clé commune = le rôle.
**RC5 — Le WHY n'a jamais été un champ parce que le séquencement est figé** ; la seule décision dynamique (escalade) a montré le besoin, et son motif fuit.

## 04_BROKEN_LOOPS

| boucle | état | rupture |
|---|---|---|
| Jeux→KB | [X] | propositions jamais matérialisées ; promotion 100 % manuelle ; 10 décisions non appliquées (`--apply` = geste Pierre) |
| Erreur→Lesson | [B] | fichiers absents ; producteur branché jamais déclenché ; curation 2→3 humaine par doctrine |
| Lesson→KB | [X] | zéro référence knowledge_base dans learning_memory |
| Mémoire→agent jeu | **[M] depuis P2** | un run jeu lit AUSSI `playtest.jsonl` (leçon « bande de vitesse » atteint le builder) ; écriture inchangée |
| Mémoire→raisonnement | [M] mal placé | position 16/18 — réordonner = expérience future, pas un correctif |
| WHY→trace | **[M] depuis P3+P5** | `reason` au manifeste dispatch (défaut « ordre de profil ») ; motif d'escalade persisté succès ET refus ; `run.log` par run |

## 05_CONTRADICTIONS

1. ~~Contrat vs exécuteur~~ **ANNOTÉE (P6)** : les 3 divergences sont désormais déclarées DANS les contrats (« plafond d'intention, pas plancher d'exécution ») + `tools_effective` signé au manifeste (P4). Résolution de fond (table dérivée du contrat) = chantier futur.
2. ~~Champs jetés~~ **CLOSE (P1)** : `exigences_cognitives` + `memoire` rendus dans le prompt (sections dédiées, règle 3 états).
3. Deux curriculums disjoints, aucun ratifié (Détail H vs CURRICULUM_JEUX_v1) — **OUVERTE, arbitrage Pierre**.
4. Budget mécanique (`reuses:[]`) vs réutilisation réelle (25/44 de Pong) — **OUVERTE**.
5. ~~skill.md vs roles.yaml~~ **CLOSE (P6)** : skill.md distingue `orchestrator`/`run_orchestrator`.
6. ~~« Cible vierge » vs « Breakout »~~ **CLOSE (mandat Pierre « BOUCLE COMPLÈTE BREAKOUT » + GATES VALIDÉES 2026-07-31)** : Breakout V2 JOUÉE comme campagne Forge complète (3 runs, verdict signé OK/HUMANGATE_READY — `docs/forge/BREAKOUT_V2_CAMPAIGN_REPORT_2026-07-31.md`).
7. ~~`context_budget` trompeur~~ **CLOSE (P7)** : `prompt_budget` + `ambient_context_note` ; ancien nom en lecture legacy seule.

## 06_DECISIONS (humaines, en vigueur)

Ratifiées : routage 5 familles (Opus archi · Sonnet conception · Qwen contradiction/code · Gemini recherche+fallback Sonnet tracé · Haiku simple) · critère Prisme = Inter>Intra · producteur-avant-validateur · Breakout = expérience externe hors campagne / prochaine campagne Forge V2 (tension vierge/Breakout à trancher) · E7 découplé · anti-accrétion · lots de dégel avec preuve · **mandat d'exécution courant : lot dégel 2 (P1→P7), délégation, intervention humaine seulement si choix produit / invariant / nouvelle couche / preuve impossible**.
Exécutées sous mandat de clôture 2026-07-31 : `--apply` FAIT (10 décisions, card_engine ACCEPTED) · commits des lots + gates + re-baseline FAITS (`319e9a2`→`2b38702`, verify CLEAN) · campagne Breakout jouée.
En attente Pierre : **gate de campagne Breakout** (F-A/F17, playtest ressenti, leçons L1-L5, 2 dégels ciblés — rapport §8) · ratification CV-9 · curriculum faisant foi · D-b/e/f/g/i/j.

## 07_EXECUTION_PLAN — LOT DÉGEL 2 (**LIVRÉ 2026-07-31 — suite 1350 passed / 1 skipped, node 35/35, re-vérifiée par l'orchestrateur**)

État : P1✅ P2✅ P3✅ P4✅ P5✅ P6✅ P7✅ (alias transitoire retiré, lecture legacy testée côté context_check). Reste du lot : mise à jour des vues canoniques (en cours) · commit + re-baseline = gate Pierre. Le tableau ci-dessous est conservé comme référence des critères de preuve.

| # | action | composant | preuve de réussite |
|---|---|---|---|
| P1 | Rendre `exigences_cognitives`+`memoire` dans le prompt | `contract._render_prompt` | le texte `memoire` du contrat s9 atteint le prompt final réel ; suite verte |
| P2 | Pré-mortem d'un run jeu lit AUSSI `playtest.jsonl` | `driver._premortem` (additif) | un driver `is_game` reçoit la leçon « bande de vitesse » |
| P3 | WHY d'escalade persisté au SUCCÈS + logs fichiers (run_dir) | `driver._maybe_escalate`, logging | escalade simulée réussie → motif dans state.json ; run.log existe |
| P4 | Manifeste porte les outils EFFECTIFS (additif, jamais audit.py) | `context_manifest` + appelant | ligne réelle porte le tuple `_STEP_TOOLS` effectif |
| P5 | Champ `reason` optionnel d'activation (défaut « ordre de profil ») | `dispatch.prepare_dispatch` → manifeste | ligne dispatch avec reason ; gate inchangée |
| P6 | Documenter les écarts résolus : skill.md cite run_orchestrator · 3 divergences annotées dans les contrats | skill.md, 3 contrats | grep ; les contrats disent ce que l'exécuteur fait |
| P7 | `context_budget` → `prompt_budget` + champ informatif `ambient_constant` | `context_manifest` | manifeste suivant porte le nouveau nom |

Interdits du lot : refonte · nouvelle couche · audit.py · verdict.py · valeurs de roles.yaml · réordonnancement du prompt (expérience future, pas correctif) · mémoire par rôle (attend une donnée réelle).
Fin du lot : P1-P5 implémentés · tests verts (baseline re-mesurée avant/après) · preuves listées · re-gel : garde DRIFT = exactement les fichiers du lot · **mise à jour du master schema en dernier (modifie les vues, jamais un bloc changelog)**.

## 08_EVIDENCE_INDEX

Audits : `docs/forge/MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md` · `ECARTS_ET_PLAN_REPRESENTATION_V2.md` · `PLAN_CONVERGENCE_FORGE_V1.md` (CV-0…CV-19, classes A→G) · `INFERENCE_ORCHESTRATOR_V2_PROPOSAL.md` (routage, E4/E7, sonde-contrôle Intra/Inter) · `RAPPORT_EXECUTION_CONVERGENCE_2026-07-30.md` (lot dégel 1 : CV-3/4/8/9/14/15/16/19 livrés, 1321 tests).
Campagne : `BREAKOUT_V2_CHARTER_PROPOSED.md` · `BREAKOUT_V2_PROOF_PROTOCOL.md` · `BREAKOUT_V2_CAMPAIGN_PREP.md`.
Vues : `STUDIO_MASTER_SCHEMA.html` (+`_HISTORY.md`) · `FORGE_V2_COGNITIVE_RUNTIME.html` · `FORGE_V2_PILOTAGE.html`.
Code pivot : `dispatch.py` (PROFILES:123) · `driver.py` (_premortem:777, _halt_step→failure_event:840, escalade:2057) · `run_real.py` (_STEP_TOOLS:163, _claude_call_raw:355, cwd:410) · `contract.py` (CRITICAL:42, _render_prompt:162) · `context_manifest.py` · `escalate.py` · `learning_memory.py` (chemins:63-64, CAUSE_MUTATION_TARGET:95) · `studio_link.py` (domaines:243, record_error:269).
Handoff : `studio_brain/00_CURRENT_CONTEXT.md`.
