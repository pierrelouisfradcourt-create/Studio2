# Analyse M1-M7 — paire pilote L/D — CLÔTURE (Pierre, 2026-08-30)

Protocole : `docs/forge/RUN2_PILOTE_PROTOCOLE_V0.md` §5 (grille pré-enregistrée AVANT tout run).
Exécution : 4 revues à contexte propre (game-designer + systems-designer sur chaque charter masqué,
mêmes prompts, interdiction des run_dirs) · M2/M3 mécanique (L1 seul, D1 BLOCKED) · M7 jugement
Pierre en aveugle (paquet archivé ici même : `m7_blind/`, mapping descellé APRÈS jugement).
**Grille de MESURABILITÉ — aucun claim Libre vs Dirigé** (paire dégradée, n=1, aveugle imparfait).

## Grille finale (attribuée après descellement : X=p1_alpha=D1 · Y=p1_beta=L1)

| Métrique | D1 (p1_alpha) | L1 (p1_beta) |
|---|---|---|
| M1 trous design / preuve (game-designer) | 8 / 5 | 10 / 6 |
| M1' défauts numériques (systems, corrigés des artefacts de masquage) | 7½ (2 ambig · 2 manq · 2 incohér · 1½ claim) | 6 (4 ambig · 1 orpheline · 1 claim) |
| M4 claims sans instrument | ~6½ | 7 |
| M5 fogs présents / manquants | 3 / 6 | 4 / 5 |
| M6 boucles décisionnelles réelles / hors-scope défendables | 4 / 6 | 4 / 3 |
| M2 grandeurs inventées en aval | BLOCKED (pas de build) | 8 primaires — délégation EXPLICITE par design (≠ lives=20 silencieux du TD) |
| M3 fidélité charter→build | BLOCKED | 0/0/0 (table charter vide par design) + 1 divergence QUALITATIVE hors-mesure : « canvas » déclaré, rendu DOM réel |
| M7 (a) envie de jouer / (b) ratifiable tel quel | (a) ● | (b) ● |

## M7 — jugement Pierre (verbatim, rendu AVANT descellement)

> (a) Envie de jouer : X — « sa boucle est déjà concrète : ressource unique, clic, 4 tiers de
> générateurs, améliorations, arbitrage achat/épargne, déblocages progressifs et objectif
> terminal clair. »
> (b) Ratifiable tel quel : Y — « meilleur comme charter expérimental : il laisse réellement la
> structure être inventée par la chaîne tout en imposant les propriétés que l'expérience doit
> mesurer […] Il évite aussi explicitement la copie de Cookie Clicker. »

Caveats consignés avec la donnée : (i) auto-préférence structurelle — la concrétude préférée en
(a) EST la grammaire imposée que Pierre avait ratifiée ; (ii) asymétrie constitutive — la question
(a) posée sur des charters s0 défavorise par construction tout bras délégant (le charter L ne
contient pas encore de jeu). Le verdict scindé est cohérent : (a) juge LE JEU, (b) juge
L'INSTRUMENT — chaque bras gagne sur son terrain.

## Convergences inter-lentilles (signal de robustesse de la grille)

- L1 : « budget de ticks fixe » = grandeur ORPHELINE (citée par 3 critères, ni chiffrée ni
  déléguée) — pointée indépendamment par les deux revues.
- D1 : incalculabilité du test doré S9 (tick_rate + gain_clic + mapping coûts jamais reliés) —
  pointée indépendamment par les deux revues.

## Les 5 observations de protocole (résultat réel de l'analyse — nourrissent l'amendement V1)

1. **R3-lite : granularité** (finding pilote 1 — corrigé au sas R3/freeze, C1).
2. **Topologie des rondes** (finding 2 — corrigé, C2).
3. **R3 × bras normatif** (finding 3 — corrigé, C3).
4. **Matérialisation du charter = advisory** : s0-D1 a rendu son charter sans fence ```yaml →
   charter.yaml jamais écrit, chaîne poursuivie sans lui (reçu written:false non gatant).
5. **Instruments d'analyse à durcir** : (a) le masquage par mots-interdits a créé 2 faux défauts
   (valeurs légitimes cachées — ex. `gain_clic: 1` masqué à cause de son commentaire) ; (b) la
   question M7(a) doit porter sur les artefacts POST-conception (gm_worldscan/product_snapshot),
   pas sur les charters s0 ; (c) la revue attrape aussi les défauts de l'ENTRÉE imposée (3 défauts
   réels de la grammaire ratifiée : mapping coûts↔améliorations absent · tick_rate jamais fixé ·
   tension R-entier vs production 0.1/s sans règle d'arrondi) — la grille mesure sans égard pour
   l'auteur, y compris l'orchestrateur et Pierre.

## Ordre de marche ratifié (Pierre 2026-08-30)

1. Clôture de l'analyse (ce document). 2. Commit. 3. Amender le PROTOCOLE RUN 2 (pas le moteur
au-delà du nécessaire aux findings). 4. Sas de pré-enregistrement. 5. Seulement après : décider
si une paire 2 vaut le coût.

```
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
no_global_ready_verdict: true
```
