# RUN M ter — RÉSULTAT

*2026-09-03 · troisième run réel du Studio V2, après la correction d'encodage.
**V1 non modifié** : `58095ba9`, écarts identiques au snapshot d'ouverture, 0 fichier ajouté.
Affirmations **re-vérifiées et reproduites** par mes soins — y compris contre le rapport de Fable.*

```
RUN M      6 étapes · HALT s6            · aucun jeu
M bis      9 étapes · HALT s10a          · un jeu jouable
M ter      s0→s6 OK · boucle s9↔s10a     · TUÉ à 60 min par l'instrument, pas par la chaîne
7,46 $ mesurés (att. 3 de s9 non comptée, tuée en vol)
```

---

## 1 · Ce que M ter a tranché

**La correction d'encodage tient** — `s10a-oracle-code` a produit **deux reçus** sur deux
exécutions, journal lisible (cadres et `✓` intacts), `evidence_sha256` scellé.

**Le gate mutation fait son travail, et c'est la première fois qu'on le voit en V2 :**
```
att. 1   baseline ROUGE sur code non muté — la suite de tests n'existait pas   -> REFUSÉ
att. 2   17 mutants tués sur 70 · 53 survivants · 0 triés                      -> REFUSÉ
         escalade #1 : haiku -> sonnet, appliquée via context.model_override
```
Une suite qui laisse survivre 53 mutants sur 70 ne prouve pas ce qu'elle prétend. **Le gate l'a
dit deux fois et a fait monter le builder d'un cran.** L'escalade n'avait jamais été observée en V2.

## 2 · Sur mon lot D — je corrige Fable, et la correction me concerne

Fable écrit « **D-1 EXERCÉ** ». **C'est inexact, et le détail compte.**

```
STATUS  ESCALADE
ARRET   « aucun finding reparable localement »     <- chemin PRÉEXISTANT
PROBLEMS_BEFORE/AFTER   9 -> 0                      <- vue TRONQUÉE
```
Si ma garde D-1 avait tiré, l'arrêt dirait *« aucun progres mesure (19 → 19 problemes) »*. Il dit
autre chose. **D-1 n'a pas tiré** — la troncature de `repair_step.mjs:237`
(`return { ok, problems }`) ampute les trois autres listes **avant** que `repair_loop` ne les voie.
Ma correction porte sur le lecteur ; le tuyau reste bouché.

**Ce qui a réellement détecté le déplacement, c'est D-2 :**
```
join_check                    EMPTY_FORM   0/10 · 0 fantôme  · forme false
join_check_apres_reparation   VOID         0/10 · 9 FANTÔMES · forme TRUE
ecart_avec_avant : « EMPTY_FORM (agent) -> VOID (après réparation) — la boucle a modifié la jointure »
```

> **Le scénario de RUN M s'est reproduit à l'identique — et cette fois la chaîne l'a nommé
> elle-même, dans un reçu, à la seconde où il s'est produit.** Il nous avait fallu une enquête.
> **La défense en couches a fonctionné : D-2 a rendu visible ce que D-1 a laissé passer.**

**Et le défaut n'est pas empêché** : `wiremap.json` porte sur disque 9 `couvre` fantômes
(`movePaddle`, `checkWin`, `E9`…), 0 rollback, l'étape est **OK**. Détecté, nommé, non bloqué.

## 3 · Le jeu se gagne **sans joueur** — et l'oracle le valide

```
solvability.mjs   « Bot : 456 steps, state=won »   ✓ BOT A GAGNÉ — RESULT: PASS
partie SANS aucune entrée : state='won' en 7,7 s = 456 frames · raquette immobile [360,360]
                            balle piégée dans la zone des briques, ne redescend jamais
```

> **456 steps du bot = 456 frames sans joueur. La solvabilité mesurée ne porte AUCUNE variance
> entre jouer et ne pas jouer.**

C'est la **règle de variance ratifiée le 2026-07-21**, mot pour mot : *une métrique à variance
nulle valide le moteur mais ne mesure pas ce que son nom promet* — même motif que
`ticks == plus-court-chemin` sur grid-navigator. **Ce n'est pas un défaut de la chaîne : c'est un
défaut de l'oracle que la chaîne a produit.** Elle a fabriqué un juge qui ne peut pas condamner.

Le clavier, lui, fonctionne réellement (frappe Playwright : raquette 360 → 595 px en 800 ms).

## 4 · Pourquoi le run s'est arrêté — erreur d'instrument, pas de chaîne

Le lanceur de Fable a été **tué à 60 min 12 s** (durée de vie du lanceur de session). La chaîne
était vivante et dans une boucle **légitime** `s9 ↔ s10a` — att. 3 à 25 min sur 30, en train
d'écrire `mutation_triage.json` 49 secondes avant le kill.

Fable le déclare lui-même et cite la leçon qu'il n'a pas appliquée : *« run long ≠ vie de l'agent
parent — superviseur externe requis »*. **Je la partage** : je lui avais demandé de surveiller,
sans exiger un lancement détaché.

**Reprise possible** : `state.json` est un « redémarrage légitime » selon le driver — s9 reprendrait
à att. 4, `model_override=sonnet` conservé, les étapes acquises intactes.

## 5 · Deux défauts nouveaux, mesurés

| # | | nature |
|---|---|---|
| **A** | **La convention `logic.test.mjs` / `properties.test.mjs` n'est écrite nulle part.** Le gate mutation l'exige (`DEFAULT_TEST_ARGV`) ; ni le prompt s9 (17 408 car.) ni le contrat ne la nomment. En V1 elle venait d'un **argument de lancement jamais archivé** (`git log -S` vide). Coût : une tentative de builder entière — 259 s, 0,67 $ — pour l'apprendre par l'oracle | convention non documentée |
| **B** | **Fuite de leçons inter-projets** : le prompt s9 att. 2 injecte `manifest-2b3083e411db2072` — « échec de la tentative 5 à s9-build », `project: None`. `premortem_lessons` n'a **aucun filtre projet** (`apply_injection_policy` filtre par génération et statut seulement) | contamination de contexte |

---

## Ce qui reste non tranché — et par ma faute, pas celle de la chaîne

```
s10b · s10c · s11 · s12      PENDING ou non atteintes
verdict.json signé            JAMAIS PRODUIT
clé V2 (forge/.forge_key)     JAMAIS UTILISÉE
verify_run -> AUTHENTIQUE     NON MESURÉ
```
**Trois runs, et le Studio V2 n'a toujours pas signé un verdict.** Ce n'est pas la chaîne qui l'en
empêche : c'est la manière dont je l'ai lancée.

```
status_by_surface:
  encodage_corrige_tient:  TESTED   # 2 reçus s10a, journal lisible
  gate_mutation_actif:     TESTED   # baseline rouge refusée, 17/70 refusé, escalade appliquée
  D2_fonctionne:           TESTED   # écart EMPTY_FORM -> VOID nommé automatiquement
  D1_toujours_contourne:   TESTED   # arrêt « aucun finding reparable », pas « aucun progres mesure »
  jeu_gagne_sans_joueur:   TESTED   # 456 frames = partie sans entrée, variance nulle
  clavier_fonctionne:      TESTED   # 360 -> 595 px
  convention_non_ecrite:   TESTED   # absente du prompt et du contrat
  fuite_lecons:            TESTED   # project: None injecté
  verdict_signe:           NOT_FOUND
  arret:                   INSTRUMENT  # kill du lanceur à 60 min, chaîne vivante
  v1_intact:               TESTED   # 58095ba9
```
`software_verdict: BLOCKED` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
