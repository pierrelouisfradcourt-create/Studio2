# SPÉCIFICATION DE LIBERTÉ DE CONCEPTION — SONDES FORGE — V0

Date : 2026-08-29 · Source : synthèse Fable (poste de commande) sur le run `tower_defense_sonde-20260829-build`
Statut : **RATIFIÉE Pierre 2026-08-30** (decision-log). Portée exacte de la ratification :
N1-N4 + N7-N9 applicables au Brief/RUN 1 ; **N5 et N6 restent fog / non mécanisées** —
la ratification ne les transforme PAS en exigences soudainement mesurées.
Base factuelle : `lab/forge_runs/tower_defense_sonde/design_findings_20260829.md` (observations ratifiées comme résultats d'expérience), `state.json` du run, `lab/reports/lessons.jsonl` (8 leçons candidates), contrat `scripts/forge/contracts/s0-contrat.yaml`.

Principe directeur, tiré du méta-enseignement du run :

> Quand on donne de la liberté au concepteur, il produit une structure raisonnable.
> Mais quand le même concepteur définit AUSSI les instruments qui doivent prouver la
> qualité de son système, ses angles morts deviennent des angles morts de la preuve.

Cette spec ne restreint donc PAS la liberté de conception (elle l'élargit et la protège).
Elle restreint la liberté de **s'auto-juger** et l'ambiguïté de **forme**.

Convention de vocabulaire : « obligation de preuve » = contrainte sur la vérifiabilité
(forme, traçabilité, instruments). « Choix de gameplay » = contenu du design (valeurs,
structures, économie). Cette spec n'impose AUCUN choix de gameplay.

---

## 1. Contraintes NON NÉGOCIABLES (avant s0)

Toutes sont des obligations de preuve ou de forme — aucune ne fixe un contenu de design.

**N1 — Socle d'observabilité technique.** La pratique standard des sondes reste imposée :
page HTML+JS unique, RNG seedé, logique `.mjs` testable hors navigateur, `window.__game`,
actions DOM-only, déterminisme par hash. Justification : sans ce socle, aucun oracle
non-LLM ne peut mesurer quoi que ce soit ; c'est le prérequis de toute preuve, pas un
choix de jeu.

**N2 — Provenance par champ, généralisée.** Le bloc `provenance_commande` du charter
tower_defense (SOURCE: Pierre / SOURCE: agent / SOURCE: pratique standard, plus la
liste explicite `non_impose_par_pierre`) devient obligatoire pour TOUT le charter, champ
par champ. Justification : c'est ce bloc qui a rendu l'expérience de liberté *lisible* —
on sait exactement ce que s0 a inventé. Sans lui, liberté et commande sont
indistinguables a posteriori (invariant provenance déjà à l'étude côté studio).

**N3 — État initial exhaustif.** Toute quantité dont dépend un critère de succès du
charter doit être **présente dans le charter** — la *valeur* reste au libre choix de s0,
mais son *existence* est vérifiable par oracle (règle du validateur sans producteur).
Justification directe : `lives` de départ absent du charter → S8/S9 invérifiables même en
théorie, et le builder a inventé `lives = 20` seul (défaut de production documenté).
Forme proposée : le charter liste son vecteur d'état initial complet et l'oracle
`check_charter` vérifie que chaque grandeur citée par un `criteres_succes` y figure.

**N4 — Formules à valeur unique.** Toute formule du charter doit être calculable en une
seule valeur (pas d'ambiguïté linéaire/composé type « +60 % par niveau »). Justification :
le charter exigeait des « valeurs exactes figées en test doré » qui étaient non
calculables en l'état — l'ambiguïté de forme a détruit sa propre obligation de preuve.

**N5 — Séparation concepteur / instrumenteur.** s0 propose librement ses critères de
preuve (S1-S20), mais ces critères ne sont **gelés qu'après une passe adversariale
indépendante** (red-team ou systems-designer à contexte séparé) dont la mission unique
est : « quels défauts du design proposé ces critères sont-ils structurellement incapables
de détecter ? ». La passe est advisory (elle ne réécrit pas le design) ; ses trous
identifiés deviennent soit des critères additionnels, soit des fogs explicites.
Justification : S10 (non-dominance) écrit par s0 ne testait qu'en mono-tour et ne pouvait
pas voir le duo dominant que son propre design rendait probable. C'était la piste
d'évolution déjà notée dans les findings ; cette spec la formalise.

**N6 — Fidélité charter → build, ou écart déclaré.** Toute valeur figée au charter est
soit reproduite à l'identique par le build, soit l'écart est **déclaré dans un artefact
structuré** (champ, pas commentaire) et remonte au verdict. Justification : le run a
livré Brute 220 PV au charter / 50 PV au code, V10 réduite de 36 à 5 ennemis, etc., sans
aucune trace de décision — la « balance librement conçue » n'a en fait jamais été
exécutée, ce qui invalide silencieusement l'expérience FOG-5 elle-même.

**N7 — Pas de PASS avec volets non exécutés.** Un volet SKIP/non mesuré = `NOT_MEASURED`
propagé, jamais absorbé dans un PASS global, et jamais un `executed: true` écrit en dur
(observé : `oracle-evidence.json` déclarait e2e exécuté alors que le log disait SKIP,
verdict global PASS avec e2e et mutation absents). Reprise directe des invariants
existants (`render_not_measured_was_policy_not_physics`, flags codés en dur détectés par
s10a).

**N8 — `fog_humangate` entre au schéma.** Le champ inventé par s0 (FOG-1..FOG-5) est
l'apport le plus précieux du run et n'existe dans aucun schéma. Il devient un champ
canonique du charter, validé par `check_charter` (liste non vide autorisée à contenir
« aucun fog » motivé). FOG-5 y garde son statut exact : une balance initiale qui échoue
est une DÉCOUVERTE à rapporter, jamais un bug à masquer par ajustement silencieux.

**N9 — Invariants studio inchangés.** NO_CLAIM_ALLOWED · verdict signé HMAC ·
HumanGate décide · le fun reste une évaluation humaine (FOG-4 permanent par
construction) · preuve de variance des métriques (ratifié 2026-07-21).

## 2. Contraintes LAISSÉES À S0 (liberté explicite)

Le charter de la sonde suivante ne doit imposer AUCUN des éléments suivants :

- Nombre et structure des maps, tours, ennemis, vagues, upgrades — et jusqu'à
  l'existence même de ces catégories si le genre s'y prête autrement.
- Forme de l'économie (nombre de sources de revenu, présence d'intérêts, etc.).
- **Valeurs** des conditions initiales (N3 impose leur existence, pas leur contenu).
- Toutes les valeurs de balance — FOG-5 intégral : une mauvaise balance initiale est un
  résultat d'expérience recevable.
- Structure des boucles de jeu et leur nombre (le run a montré que « boucle partie »
  pouvait être requalifiée en cadre de score : cette requalification honnête est une
  liberté, pas une faute).
- Le contenu du `hors_scope` motivé (« une deuxième map n'ajouterait aucune décision
  nouvelle » est exactement le type de raisonnement qu'on veut voir).
- Le choix des mécanismes de garde-fou internes au design (plafonds, planchers) — mais
  voir E5 : leur caractère opérant doit être explicité.

Les findings du run (Frost sans prédateur, parité anti-armure, plafond inopérant) ne
deviennent PAS des exigences de design de la prochaine sonde : ils sont des données
d'entrée de la passe adversariale N5, rien de plus. Imposer « chaque tour doit avoir un
prédateur » serait précisément l'ajustement silencieux que FOG-5 interdit.

## 3. Informations que s0 doit EXPLICITER (sans contrainte sur leur contenu)

- **E1 — Vecteur d'état initial complet** (cf. N3) : toute grandeur qui existe au tick 0.
- **E2 — Provenance de chaque bloc** (cf. N2).
- **E3 — Portée de chaque critère de preuve** : pour chaque critère, « ce qu'il mesure /
  ce qu'il ne mesure pas » (le format existe déjà dans les reçus s10 : `mesure` /
  `ne_mesure_pas`). C'est ce champ qui aurait rendu visible « S10 = mono-tour seulement ».
- **E4 — Hypothèses de dominance assumées** : si le design revendique N voies gagnantes
  concurrentes (type S11), s0 nomme les combinaisons qu'il croit équilibrées et celles
  qu'il n'a pas analysées. Déclarer une zone non analysée est recevable ; la taire ne
  l'est pas.
- **E5 — Caractère opérant des garde-fous** : pour chaque plafond/plancher/limite du
  design, s0 indique dans quel scénario il mord. Un garde-fou qui ne peut jamais mordre
  (le « plafond 30 » = exactement le maximum atteignable) peut rester dans le design,
  mais doit être déclaré décoratif.
- **E6 — Fogs HumanGate** (cf. N8), y compris le fog jetable-vs-graine (FOG-2) et le fog
  qualité ressentie (FOG-4).
- **E7 — Statut des bots de preuve** : pour chaque bot/stratégie servant une preuve de
  divergence, s0 déclare s'il est *construit pour diverger* ou *candidat naïf plausible*.
  Le run a montré que la divergence prouvée par 8 bots scriptés était construite, pas
  découverte — c'est acceptable si c'est dit.

## 4. Preuves que s0 doit PRÉVOIR (obligations de couverture, pas de résultat)

- **P1 — Solvabilité positive ET négative** exécutables dès le charter : les deux
  critères doivent être calculables avec les seules données du charter (conséquence
  mécanique de N3+N4). La *valeur* du seuil doré peut rester FOG-3 (fixée au premier run
  réel puis figée) — la procédure était bonne, elle est conservée.
- **P2 — Couverture preuve ↔ revendication** : tout claim structurel du charter (« deux
  voies gagnantes », « non-dominance ») doit avoir un instrument qui teste l'espace
  effectivement revendiqué, combinaisons comprises. Justification : c'est une obligation
  de cohérence interne (la preuve doit couvrir ce que le design affirme), pas un choix de
  gameplay — le trou S10-mono-tour est le contre-exemple canonique.
- **P3 — Test des instruments** : au moins une falsification par instrument de preuve
  (les « tests jumeaux » S17 existaient — le principe est reconduit et étendu aux
  instruments ajoutés par la passe N5). Un oracle doit pouvoir échouer
  (`forge.assertion_that_cannot_fail` est déjà en proposition KB).
- **P4 — Chaîne d'évidence complète ou honnête** : e2e, mutation, preuve visuelle,
  console — chacun exécuté ou marqué NOT_MEASURED (N7). Le harnais mutation doit pointer
  les vrais fichiers de test du projet (observé : `test_argv` visant `logic.test.mjs`
  inexistant → mutation `total: 0` présentée comme mesure).
- **P5 — Évidence exportée** : les preuves quittent le run dir vers
  `lab/forge_evidence/<RUN>/` (le run n'y a rien déposé — la preuve qui ne traverse pas
  la frontière qu'elle valide n'existe pas).
- **P6 — Variance des métriques** : toute métrique servant à classer/générer/calibrer
  prouve d'abord qu'elle porte une information variable (doctrine ratifiée 2026-07-21,
  reconduite telle quelle).
- **P7 — Traçabilité de la session de conception** : le prompt et le contexte de la
  session qui produit le charter sont conservés sous le run_id du run (observé : la
  conception réelle vivait sous un run_id sans répertoire ; seule la restitution verbatim
  est tracée). Sans cela, l'expérience de liberté n'est pas ré-analysable.

## 5. Décisions qui restent HUMANGATE (Pierre)

- Ratification du charter (STOP humain avant build) — inchangé.
- `reference_jeu` et tout design-intent sans source Pierre explicite (garde-fou s0
  existant, leçon AutoBattler) — inchangé.
- FOG-2 : sonde jetable vs graine de jeu.
- FOG-4 : qualité ressentie / fun — permanent par construction, jamais délégué à un
  oracle ni à un LLM.
- Verdict sur une découverte FOG-5 : quand la balance initiale échoue, c'est Pierre qui
  décide si on re-balance (nouveau cycle) ou si on archive la découverte — jamais un
  ajustement silencieux en cours de run.
- Gel des critères de preuve après la passe adversariale N5 : les ajouts proposés par la
  red-team sont advisory ; Pierre arbitre ce qui entre au charter.
- Promotion des leçons candidates en KB, merge/reject/freeze du run — inchangé.

## 6. Anti-patterns observés dans tower_defense_sonde

Constats factuels du run, chacun adressé par une clause ci-dessus :

1. **Juge et partie** : s0 seul auteur des critères qui jugent son design → l'angle mort
   Frost-sans-prédateur est devenu un angle mort de S10. (→ N5, E3, P2)
2. **Quantité fantôme** : `lives` de départ absent du charter, inventé par le builder →
   solvabilité invérifiable, FOG-6 jamais vu. (→ N3, P1)
3. **Drift silencieux charter → code** : Brute 220→50 PV, vagues 36→5 ennemis, sans
   trace de décision — l'expérience de balance conçue n'a jamais tourné. (→ N6)
4. **PASS cosmétique** : verdict global PASS avec e2e SKIP déclaré `executed: true` et
   mutation non mesurée ; flags `passed: true` écrits en dur dans le harnais. (→ N7, P4)
5. **Mutation à vide** : harnais mutation pointant des fichiers de test inexistants,
   `total: 0` présenté dans la chaîne de preuve. (→ P4)
6. **Formule ambiguë auto-invalidante** : « +60 % par niveau » rendait incalculables les
   tests dorés que le même charter exigeait. (→ N4)
7. **Garde-fou décoratif** : plafond de bonus fixé exactement au maximum atteignable —
   il ne mord jamais. (→ E5)
8. **Divergence construite présentée comme découverte** : bots scriptés pour diverger,
   homme de paille naïf. (→ E7)
9. **Étape amont vide non bloquante** : prisme s1 vide (0 règle observable, pas de
   `prisme.json` matérialisé) et le pipeline continue en re-sourçant ailleurs. (→ P4,
   et chantier prisme existant — hors périmètre de cette spec)
10. **Conception non tracée** : la session qui a réellement conçu le charter n'a laissé
    aucun répertoire de run ; seule la restitution verbatim existe. (→ P7)
11. **Run jamais clos** : `state.json` dit RUNNING, RUN_INDEX dit HALTED/BLOCKED —
    deux vérités concurrentes. (→ discipline de clôture, déjà couverte par
    `long_run_needs_external_supervisor`)

## 7. Protocole de mesure — la liberté produit-elle de meilleurs designs ?

Objectif : rendre falsifiable l'hypothèse « ne pas imposer le dimensionnement produit de
meilleures architectures de jeu ». Sans chiffres de gameplay : les métriques portent sur
la *structure* et la *preuve*, jamais sur les valeurs de balance.

**Design expérimental — paires appariées.** Pour un même genre-cible, deux sondes :
- Bras L (libre) : charter selon cette spec — dimensionnement entièrement laissé à s0.
- Bras D (dirigé) : charter où Pierre (ou une genre bible existante) fixe le
  dimensionnement, le reste identique (mêmes N1-N9, même passe N5, mêmes P1-P7).
Même profil de run, mêmes oracles, même budget d'étapes. Le genre change à chaque paire
(la paire tower-defense est déjà à moitié jouée côté L).

**Pré-enregistrement.** Les métriques d'issue et la grille de revue sont figées AVANT le
premier run de la paire (sinon on re-crée le juge-et-partie au niveau du protocole).

**Métriques d'issue** (toutes dénombrables ou jugées en aveugle, aucune valeur de
gameplay) :
- M1 — Trous structurels détectés par revue indépendante post-hoc (le format
  game-designer + systems-designer confrontés au charter, déjà exercé sur
  tower_defense_sonde, devient la revue standard), en séparant : trous de design vs
  trous de preuve.
- M2 — Quantités inventées en aval : nombre de grandeurs fixées par le builder sans
  source charter (le `lives = 20` compte pour 1).
- M3 — Fidélité charter → build : nombre de valeurs figées divergentes non déclarées.
- M4 — Couverture preuve ↔ revendication : nombre de claims structurels du charter sans
  instrument couvrant l'espace revendiqué (le S10-mono-tour compte pour 1).
- M5 — Qualité des fogs : nombre de fogs pertinents levés par s0 vs nombre de fogs
  manquants identifiés par la revue (FOG-6 manquant compte contre s0).
- M6 — Richesse décisionnelle structurelle : nombre de boucles décisionnelles réelles
  identifiées par la revue (pas par s0), et nombre de décisions hors_scope motivées
  jugées défendables.
- M7 — Jugement humain en aveugle : Pierre lit les deux charters de la paire sans savoir
  quel bras les a produits (blocs provenance masqués) et classe : lequel décrit le jeu
  auquel il aurait le plus envie de jouer, lequel il ratifierait tel quel. FOG-4 oblige :
  ce jugement est une donnée, pas un oracle.

**Critère de lecture.** L'hypothèse « la liberté produit de meilleurs designs » est
soutenue si, sur ≥2 paires, le bras L domine ou égale sur M6/M7 sans se dégrader sur
M1/M4 (les trous de preuve). Un bras L créativement supérieur mais structurellement
troué signifierait que la liberté doit rester conditionnée à la passe N5 — ce qui serait
en soi une conclusion exploitable. Deux paires sont un minimum de signal, pas une preuve
statistique : conclusion limitée, format `forge_experiment_cycle`.

**Garde-fou du protocole.** Les revues M1-M6 sont menées par des agents à contexte
propre n'ayant vu ni le run ni cette spec section 6 (sinon ils recomptent les
anti-patterns connus au lieu d'observer). L'orchestrateur confronte chaque rapport de
revue au charter réel avant de le compter.

---

software_verdict: OK — livrable produit (document, aucun code, aucun run modifié)
evidence_verdict: MECHANICAL_VALIDATION_ONLY — fondé sur l'exploration du run réel, non ré-exécuté
claim_verdict: NO_CLAIM_ALLOWED
