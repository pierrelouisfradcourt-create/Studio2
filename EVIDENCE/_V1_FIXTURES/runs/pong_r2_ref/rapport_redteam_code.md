# rapport_redteam_code — pong (s11-redteam-code / pong_r2)

FORGE_DISPATCH:s11-redteam-code:pong_r2

Posture : auditeur CODE **aveuglé** — je n'ai pas lu les justifications du builder ;
j'ai lu uniquement le code produit (`games/pong/**`), le contrat de jeu, le wiremap,
la triage de mutation et les tests/oracles. **Lecture seule** (permission `run: aucun`) :
je n'ai exécuté aucun test ni oracle. Chaque faille est livrée avec une **reproduction
déterministe exécutable par un oracle non-LLM en aval** ; je ne certifie pas moi-même le
résultat d'exécution (voir verdicts + SKIPPED_VALIDATION).

Deux natures d'appui sont distinguées explicitement :
- **[ancre-statique]** = fait vérifiable en *lisant* le fichier cité (numéro de ligne) —
  aucune exécution requise.
- **[repro-aval]** = affirmation de *comportement* dérivée par trace arithmétique ;
  doit être confirmée par exécution d'un oracle non-LLM. Non auto-certifiée.

---

## Failles

### F1 — [correctness / fake-proof] Mis-scoring à grande vitesse : la raquette DROITE offre un point à l'adversaire, et le test le masque — **HIGH**

- **angle** : collision balayée + scoring, sur la plage de vitesses que le test prétend couvrir.
- **faille** : dans `stepBall` (loop.mjs L67-83), quand la balle franchit le plan `P2_X` avec
  une grande `vx`, le renvoi calcule `nx = P2_X - BALL_R - (nx + BALL_R - P2_X)` (L71). Pour
  `x=190, vx=speed` cela donne `nx = 194 - speed`. Dès que `speed > 192`, `nx - BALL_R < 0`,
  donc le bloc scoring (L79) déclenche `scored = 'p2'` : **un renvoi réussi de la raquette
  droite est compté comme un point encaissé** (sortie à gauche). La balle a de plus « tunnelé »
  au-delà du terrain (position renvoyée `x = 194 - speed`, ex. `-706` à speed 900) avant d'être
  masquée par le recentrage du service.
  Le test censé le prouver (`loop.test.mjs` L80-89, « NO-TUNNEL a toute vitesse », vitesses
  incluant **300 et 900**) **passe quand même** parce que ses trois assertions sont satisfaites
  par le chemin scoring/recentrage, pas par la physique anti-tunnel :
  - `ns.ball.vx < 0` ✔ mais parce que le service recentré repart à `-3`, pas parce que la balle
    a été « renvoyée » ;
  - `ns.ball.x <= P2_X` ✔ mais parce que le point a **recentré** la balle à `x=100`, pas parce
    qu'elle est restée sur le terrain ;
  - `ns.score.p1 === 0` ✔ — mais le point fantôme va à **p2**, jamais vérifié.
- **sévérité** : HIGH. Le wiremap (`09_WIREMAP/wiremap.json`, ligne `play.ball.preuve`) affirme
  verbatim « vitesses 10..900 : jamais traversant, **aucun point marqué** » — affirmation
  **falsifiable et fausse** à speed 300/900. C'est une preuve de vert, pas une preuve de
  correction.
- **reproduction** [repro-aval] — oracle non-LLM :
  ```js
  import { boot, step } from 'games/pong/05_SYSTEMS/game_loop/loop.mjs';
  import { translate } from 'games/pong/05_SYSTEMS/input/input.mjs';
  const PADDLE_H = 24, P2_X = 194;
  let s = boot(1);
  s = { ...s, p2: { y: 60 - PADDLE_H/2 }, ball: { x: P2_X - 4, y: 60, vx: 300, vy: 0 } };
  const ns = step(s, translate({})).state;
  // ATTENDU par le red-team : ns.score.p2 === 1  (point fantôme au mauvais camp)
  // et le test loop.test.mjs "NO-TUNNEL" NE le détecte pas.
  ```
  Oracle de décision : `ns.score.p2 === 0` doit être vrai pour un renvoi ; s'il vaut `1` → FAIL réel.

### F2 — [test-coverage / assertion incomplète] L'oracle no-tunnel n'assère pas ce que son message promet — **MEDIUM**

- **angle** : qualité de l'oracle qui garde `play.ball`.
- **faille** : `loop.test.mjs` L87 — `assert.equal(ns.score.p1, 0, "...aucun point ne doit etre
  marque")`. Le message dit « aucun point » mais l'assertion ne couvre **que p1**. Combinée à
  l'assertion `ns.ball.x <= P2_X` (L86) qui est satisfaite par le **recentrage** post-score,
  deux des trois assertions du test sont validées par le chemin de scoring qu'elles prétendent
  exclure. C'est le mécanisme exact qui laisse F1 passer en CI. (Cousin du « `>=` tautologique »
  du pré-mortem : une assertion trop faible masque une mécanique fausse.)
- **sévérité** : MEDIUM (défaut de l'oracle, pas du moteur — mais c'est lui qui a laissé passer F1).
- **reproduction** [ancre-statique] : lire `07_TESTS/unit/loop.test.mjs` L80-89 — aucune
  assertion `ns.score.p2 === 0` ni sur la position **pré-recentrage**. Correctif d'oracle
  attendu : asserter `ns.score.p1 === 0 && ns.score.p2 === 0` **et** vérifier la position de la
  balle avant l'application du score.

### F3 — [correctness / robustesse] Le rebond vertical n'est pas robuste : la balle peut sortir du terrain et produire un état invalide — **MEDIUM**

- **angle** : réflexion bords haut/bas à grande `vy`.
- **faille** : `stepBall` L45-53 réfléchit d'un seul côté : `ny = 2*BALL_R - ny` (haut) /
  `ny = 2*(FIELD_H-BALL_R) - ny` (bas). Si `|vy|` dépasse la hauteur du terrain en un tick, la
  réflexion **dépasse le mur opposé** et `step` renvoie un état où `ball.y > FIELD_H` — que
  `isValidState` rejette (state.mjs L74). Le loop ne valide jamais sa propre sortie. La garantie
  « no-tunnel à toute vitesse » du contrat n'a en réalité couvert que les raquettes
  (horizontal) ; l'axe vertical n'est borné à aucune vitesse.
- **sévérité** : MEDIUM. Latent tant que `vy` reste `±2` (jeu réel), mais contredit la promesse
  « à toute vitesse » et laisse le moteur produire un état hors-domaine sans le signaler.
- **reproduction** [repro-aval] :
  ```js
  import { boot, step } from 'games/pong/05_SYSTEMS/game_loop/loop.mjs';
  import { translate } from 'games/pong/05_SYSTEMS/input/input.mjs';
  import { isValidState } from 'games/pong/05_SYSTEMS/game_state/state.mjs';
  const ns = step({ ...boot(1), ball: { x:100, y:60, vx:0, vy:-900 } }, translate({})).state;
  // ATTENDU : ns.ball.y === 844  ET  isValidState(ns) === false
  ```
  Oracle de décision : après tout `step`, `isValidState(state) === true`. Ici il vaut `false`.

### F4 — [correctness / imprécision] Interpolation de collision faussée quand un rebond mural et un franchissement de raquette partagent le même tick — **LOW**

- **angle** : ordre des effets dans `stepBall`.
- **faille** : le `yHit` de franchissement (L59, L69) est interpolé avec `ny` **déjà réfléchi**
  par le rebond haut/bas du même tick (L45-53), pas avec la trajectoire géométrique réelle.
  Quand un rebond mural et un franchissement du plan raquette coïncident dans un tick, le point
  d'impact vertical testé par `hitsPaddle` est distordu → un hit/miss peut être décidé sur un
  `y` faux.
- **sévérité** : LOW. Aux vitesses constantes du jeu (`vx=±3, vy=±2`) les coïncidences sont rares
  et le décalage est souvent auto-corrigé par le rebond lui-même ; je **n'ai pas** construit de
  cas produisant un hit/miss *inversé* à vitesse de jeu réelle. Je remonte donc l'imprécision
  **sans claim de mauvais résultat**.
- **reproduction** [ancre-statique] : structure `stepBall` loop.mjs L45-64 — `ny` est muté
  L46/L50 **avant** d'être réutilisé L59 dans `yHit`. Besoin HumanGate : borner si un état de
  jeu réel (vitesses nominales, coin haut/bas près d'une raquette) peut faire basculer un
  hit/miss ; sinon requalifier en imprécision documentée.

### F5 — [dead-zone / mutation] Calcul mort dans le service : la direction de re-service ne dépend jamais du seed/parité, contrairement à la doc — **LOW**

- **angle** : re-service après un point.
- **faille** : `step` L114-115 — `vx: towardLoser >= 0 ? Math.abs(serveVx(state.seed,
  pointsPlayed)) : -Math.abs(serveVx(state.seed, pointsPlayed))`. `serveVx` renvoie toujours
  `±BALL_VX` ; `Math.abs(...)` en fait la **constante 3**. La direction de re-service dépend donc
  **uniquement** de `towardLoser`, jamais du seed ni de la parité — ce qui contredit l'intention
  documentée dans state.mjs L28-33 (« direction de service déterministe : dépend du seed et du
  nombre de points »). Tout l'appel `serveVx(state.seed, pointsPlayed)` à L114 est **inerte**.
  La triage (`mutation_triage.json`, mutant L114 `ge->gt`) est *correcte* de dire que le mutant
  est équivalent — mais cette équivalence existe **parce que** le calcul autour est mort, et
  aucun test n'exerce la direction de re-service vs seed.
- **sévérité** : LOW (aucun mauvais comportement de jeu ; c'est du code mort + doc trompeuse +
  angle mort de mutation).
- **reproduction** [repro-aval, style mutation] : remplacer `serveVx(state.seed, pointsPlayed)`
  par le littéral `1` aux deux occurrences L114-115 ⇒ **tous les tests restent verts**. Un test
  survivant à cette mutation prouve la zone morte.

### F6 — [preuve non falsifiable] La preuve de `core.exit` est tautologique — **LOW**

- **angle** : critère `game.exit` (« processus terminé, code 0, aucune ressource laissée active »).
- **faille** : `exit.mjs` L14-17 appelle `process.exit(0)` **inconditionnellement** ; le code de
  sortie 0 est vrai *par construction*, il ne prouve rien. Le volet « aucune ressource laissée
  active » n'est vérifié par aucun oracle — il est seulement *affirmé en commentaire* (L3-5).
  Preuve non falsifiable.
- **sévérité** : LOW. Le critère est trivialement satisfaisable ; il ne peut pas échouer, donc ne
  teste rien.
- **reproduction** [ancre-statique] : `exit.mjs` L14 — `process.exit(0)` sans condition. Oracle
  qui « passe toujours » = pas un oracle. Besoin HumanGate : décider si le critère exit doit
  rester au catalogue ou être requalifié.

---

## Contre-vérification d'équité (ce qui N'EST PAS une faille)

Red-team indépendant ≠ tout noircir. Points examinés et jugés **honnêtes** :

- **mutation_triage.json L19/L20 (`or->and` sur input.mjs)** : justification *correcte*.
  `UP === 'up'` (input.mjs L9) donc `raw[UP]` est exactement `raw.up` ; `X || X === X && X === X`.
  Mutants réellement équivalents. [ancre-statique : input.mjs L9-10, L19-20]. (À noter au passage :
  `raw.up === true || raw[UP] === true` est du code redondant — `raw.up === true` dupliqué — mais
  la triage l'assume ouvertement, ce n'est pas une preuve factice.)
- **Volet Godot du critère pixel** : le wiremap déclare honnêtement `core.render` Godot
  **non re-exécutable** sur ce poste (GODOT_BIN absent) et le marque **fog HumanGate** au lieu de
  re-certifier depuis les PNG existants (« preuve d'existence, pas de re-exécution »). Conforme au
  pré-mortem « preuve d'exécution ≠ preuve d'existence ». Pas une déception — c'est le
  comportement attendu.
- **Oracle pixel navigateur** (`capture_browser.mjs`) : rend *deux états réellement différents*
  (boot vs 45 ticks) via le même `drawState`, compare les buffers, exclut le monochrome. Oracle
  faible (un déplacement d'1 pixel suffirait) mais **non factice** : il exerce vraiment le code de
  dessin.

---

## Rapport final (verdicts séparés)

- **software_verdict : BLOCKED**
  Motif : permission `run: aucun` — je n'ai exécuté aucun oracle. Les failles comportementales
  F1/F3/F5 sont dérivées par trace arithmétique et livrées avec des **reproductions
  déterministes exécutables en aval** ; elles ne sont pas auto-certifiées par exécution. Les
  failles F2/F4/F6 reposent sur des **ancres statiques** (lignes de code lisibles) et sont, elles,
  factuelles sans exécution.
- **evidence_verdict : MECHANICAL_VALIDATION_ONLY** — restreint aux ancres statiques (F2, F4, F6,
  contre-vérification) : faits établis par lecture directe des fichiers cités. Les volets
  comportementaux (F1, F3, F5) ne bénéficient PAS de cet appui tant qu'un oracle aval ne les a pas
  exécutés.
- **claim_verdict : NO_CLAIM_ALLOWED** — aucune affirmation de comportement n'est auto-certifiée.

### fog → HumanGate (Pierre)
1. **F1** doit être exécutée par l'oracle aval (`node` sur la repro fournie). Si `ns.score.p2 === 1`,
   c'est un FAIL de moteur réel *et* une preuve de wiremap fausse (`play.ball.preuve` : « aucun
   point marqué ») → décision merge/reject/freeze à Pierre.
2. **F3** : exécuter la repro `isValidState` ; décider si le moteur doit clamper/valider sa sortie
   ou si la garantie « à toute vitesse » doit être requalifiée en « aux vitesses nominales ».
3. **F4** : borne à établir — un état de jeu réel peut-il inverser un hit/miss ? Sinon requalifier.
4. **F6** : le critère `core.exit` reste-t-il au catalogue (non falsifiable) ?

---

## SKIPPED_VALIDATION

| # | item de validation (quoi) | périmètre (où) | statut | raison (pourquoi) |
|---|---|---|---|---|
| 1 | Exécution des tests unitaires `node --test 07_TESTS/unit/*.mjs` | games/pong/07_TESTS/unit | non fait | permission `run: aucun` — red-team lecture seule ; l'exécution appartient à l'oracle aval (s10a). |
| 2 | Exécution de l'oracle de solvabilité `node 07_TESTS/oracle/solvability.mjs` | games/pong/07_TESTS/oracle | non fait | idem `run: aucun`. Analyse statique du harnais faite (tracker vs fleer ⇒ p1 gagne 3-0) mais **non exécutée**. |
| 3 | Confirmation par exécution des repros F1, F3, F5 | games/pong/05_SYSTEMS | non fait | `run: aucun` ; repros dérivées par trace arithmétique, à exécuter en aval (fog HumanGate 1-2). |
| 4 | Construction d'un cas F4 produisant un hit/miss inversé à vitesse de jeu réelle | games/pong/05_SYSTEMS/game_loop/loop.mjs | partiel | tenté par trace ; la coïncidence rebond+franchissement s'auto-corrige aux vitesses nominales — pas de contre-exemple propre trouvé. Remonté sans claim. |
| 5 | Re-exécution du gate mutation (mutmut/équivalent) pour valider les compteurs 14/15, 15/17, 29/29 du wiremap | games/pong | non fait | `run: aucun` ; les compteurs de mutation ne sont pas re-vérifiés. F5 signale un angle mort de mutation (serveVx inerte) non reflété dans le compteur. |
| 6 | Validation du volet Godot du critère pixel | games/pong/06_RUNTIME/adapters/presentation/godot | hors délai / poste | GODOT_BIN absent (déjà fog du run) — non re-exécutable ici. |
| 7 | Vérification que `bounce.wav` est un WAV lisible (pas seulement `bytes > 0`) et provenance CC0 réelle | games/pong/04_ASSETS/audio | non fait | `run: aucun` + provenance non vérifiable par lecture ; relève du jugement Pierre. |
