# Canal de preuve pour les rôles de boucle — plan (pas encore implémenté)

> **For agentic workers:** ce document est un PLAN, écrit hors de `forge/` (surface protégée).
> Aucune ligne de `forge/**` n'est modifiée par ce fichier. Toute mise en œuvre demande un GO
> distinct ; `forge/test_surfaces.yaml` reste le régime `create_allowed_modify_denied`.

*Date : 2026-09-07 (révision 2, même jour) · Source : audit lecture-seule de
`chaton-clicker-20260906` (verdict OK AUTHENTIQUE, HUMANGATE_READY) + cadrage Pierre du même
jour, message verbatim repris ci-dessous section « Modèle cible » + retour Pierre (révision 2) :
« plan accepté comme plan de travail. Aucun code lancé. » Les diagnostics 3 et 4 ci-dessous ont
été confirmés explicitement par Pierre comme les deux corrections importantes du diagnostic
(pas seulement l'absence de `canal` : l'oracle de citation est structurellement orienté Godot,
et la résolution affordance→effet existante est une capacité non branchée sur la lignée V2, pas
un mécanisme absent).

**Statut du GO : « GO chantier canal-de-preuve » a autorisé la PRODUCTION de ce plan, pas
l'écriture dans `forge/**`.** Pierre réserve explicitement cette même formule pour le GO
d'implémentation, distinct de celui qui a produit ce document — ne pas confondre les deux
usages du même intitulé dans la suite de cette conversation.

## Diagnostic (mesuré, pas supposé)

L'audit du run `chaton-clicker-20260906` a trouvé, en lisant directement les artefacts (aucune
exécution) :

1. **`loop.json` (P01-P11) et `loop_spec.mjs::checkLoopSpec` valident une FORME, jamais une
   exécution.** `checkLoopSpec` vérifie que `loop.json` est bien typé (rôles connus, `policies`
   ≥ 2 pour DECISION, options qui référencent une affordance réelle) — il ne fait jamais tourner
   le jeu. `loop_check: OK` dans `state.json` ne prouve donc rien à l'exécution.
2. **Le WireMap déclare honnêtement son canal de preuve dans le champ libre `preuve`, mais rien
   ne l'exploite.** Sur `chaton_clicker`, `R2/R6/R13` (entrées joueur) citent `solvability.mjs`
   (un vrai bot qui clique dans un vrai DOM) ; `R3/R7/R9/R11/R12/R14/R15` (effets économiques)
   citent `logic.test.mjs::<méthode>` — un appel DIRECT à la méthode interne, jamais un clic.
   **Trois rôles de boucle — R9 (`P05` DECISION), R11 (`P08`, second NEXT_GOAL), R12 (`P09`
   REPEAT) — n'ont AUCUNE preuve joueur, seulement `logic.test.mjs`.** Le bouton concerné
   (« Producteur 2 ») est visible et cliquable à l'écran (vérifié en playtest manuel), mais
   aucun oracle exécutable ne le clique jamais.
3. **`forge.static_oracles.check_wiremap` (l'oracle Python réellement invoqué à s10c pour un
   jeu web) ne peut PAS vérifier le contenu du champ `preuve`.** Son seul extracteur de
   citation, `_PREUVE_GD = re.compile(r"[\w./-]+\.gd\b")` (`forge/static_oracles.py:291`), ne
   matche QUE des chemins `.gd` (Godot). Pour un jeu web (`.mjs`), `_PREUVE_GD.findall(preuve)`
   rend systématiquement `[]` : la boucle de vérification de citation ne s'exécute jamais, et
   `preuve` reste un texte libre non vérifié pour toute la lignée web — la seule lignée que V2
   exerce aujourd'hui (mesuré `00_CURRENT_CONTEXT.md` : 3/3 jeux produits sont web).
4. **`forge/check_wiremap_contract.mjs` porte déjà une machinerie de résolution
   affordance→effet** (`provides: affordance:<x>` / `requires` / `couvre` d'une feuille EFFET,
   profondeur ≤ 3, V4 GAME LOOP 2026-08-22) — mais elle n'agit que sur le schéma
   `schema_version: 2` à `lines[]`. **Mesuré sur les 3 wiremaps web existants
   (`chaton_clicker`, `v2_breakout_slice_r1`, `runm_breakout`) : tous en `features[]` v1, aucun
   en `schema_version: 2`.** Cette machinerie n'a donc jamais tourné sur un jeu réellement
   produit par V2 — construite, jamais câblée (classe C du protocole d'escalade).
5. **La traçabilité P0x → capacité → ligne WireMap existe déjà, complète, sans nouveau champ.**
   `featuremap.json` porte `source_ref: "P05"` etc. sur chaque capacité feuille
   (`EVIDENCE/runs/chaton_clicker/featuremap.json`), et chaque ligne WireMap cite cette capacité
   dans `couvre`. Le join `loop.json[role].ref` → `featuremap[capacité].source_ref` →
   `wiremap[ligne].couvre` est mécaniquement calculable dès aujourd'hui.

**Conclusion du diagnostic** : le système de preuve actuel ne distingue jamais *« la logique
sait le faire »* de *« le joueur peut le faire »* — ni au niveau du schéma (`preuve` = texte
libre), ni au niveau de l'oracle qui le lirait (`_PREUVE_GD` aveugle au web), ni au niveau de la
machinerie censée le faire (`check_wiremap_contract.mjs`, jamais exercée en v1). C'est un défaut
du PROTOCOLE, indépendant de la qualité de `chaton_clicker`.

## Modèle cible (Pierre, 2026-09-07, verbatim résumé)

> Le contrat de loop décrit des choses que le système de preuve ne sait pas actuellement
> distinguer entre « la logique sait le faire » et « le joueur peut réellement le faire ».

Quatre canaux, une règle :

| canal | ce qu'il prouve | exemples mesurés sur `chaton_clicker` |
|---|---|---|
| `WHITE_BOX` | la logique économique est correcte, hors navigateur | `logic.test.mjs::comparerPolitiques`, `::rejouerBoucle`, `::objectifCourant` |
| `PLAYER_INPUT` | une affordance DOM réelle est cliquée par un canal qui n'a que les entrées d'un joueur | `solvability.mjs` clique `caresser_chaton` / `acheter_producteur_0` / `renouveau_portee` |
| `PLAYER_LOOP` | un rôle de `loop.json` (`PLAYER_ACTION`…`ADVANTAGE`) est exercé de bout en bout par `PLAYER_INPUT`, ET son `observe` est lu dans le DOM/l'état exposé par contrat | `e2e.mjs` P01/P02/P03/P06/P07 ; `solvability.mjs` P02/P06/P10 |
| `META_LOOP` | un état porté à travers un reset (prestige) a une conséquence observable dans un traversal SUIVANT, via `PLAYER_INPUT` à nouveau | **absent aujourd'hui** — `e2e.mjs`/`solvability.mjs` s'arrêtent au premier `prestige > 0`, aucun ne rejoue après |

**Règle dure** (reprise telle quelle) : *une arête de boucle possède un canal de preuve
obligatoire ; un rôle marqué `PLAYER_LOOP` ou `META_LOOP` dans `loop.json` ne peut JAMAIS être
satisfait par un `couvre` dont TOUTES les lignes sont `WHITE_BOX` seul.* `WHITE_BOX` reste une
preuve légitime et suffisante pour les rôles qui ne sont pas des arêtes de boucle joueur
(justesse de formule, propriétés internes) — elle n'est jamais retirée, seulement **non comptée**
pour `PLAYER_CAN_TRAVERSE_LOOP`.

### Les 3 gameplay runs pour la méta (repris tel quel, sans alourdir le protocole)

```
META
 ├─ GAMEPLAY RUN 1 → le joueur joue
 ├─ GAMEPLAY RUN 2 → le joueur rejoue avec l'état méta (post-reset)
 └─ GAMEPLAY RUN 3 → le joueur rejoue encore ; l'état enrichi a une conséquence observable
          ↓
     méta-progression prouvée
```
Pas de simulation à grande échelle : 3 traversals bornés suffisent à distinguer « le reset
existe » de « le reset a un effet qu'un joueur peut constater en rejouant ». C'est précisément
ce que `P11` (`R15 avantage_permanent_prestige`) manque aujourd'hui : `gainApresRenouveau >
gainAvantRenouveau` est lu comme un CHAMP interne (`window.__game.gainParCaresse`, autorisé par
`PLAYABLE_CONTRACT.md` pour l'observation) après UN SEUL renouveau, jamais démontré par un second
run de clics réels qui produirait effectivement plus vite.

## Renforcement (Pierre, révision 2) — le canal est un CONTRAT de preuve, pas une étiquette

Réserve explicite sur la version 1 de ce plan : ne pas faire de `canal` un simple label déclaratif
qui remplacerait `preuve: "solvability.mjs…"` par `canal: PLAYER_LOOP` sans renforcer la preuve
elle-même — l'agent qui rédige la WireMap à s5 apprendrait vite à écrire l'étiquette qui fait
passer l'oracle, exactement le mode de dégradation qui a produit l'oracle `_PREUVE_GD` actuel
(un champ texte que plus personne ne vérifie). La validation de `canal` doit donc suivre TOUTE la
chaîne, pas seulement constater la présence d'une valeur d'enum :

```
PLAYER_LOOP déclaré
        ↓
canal PLAYER_LOOP
        ↓
preuve identifiable      (la citation résout à un fichier + un test/oracle NOMMÉ qui existe)
        ↓
preuve exécutable        (ce test/oracle a un reçu d'exécution réel — pas une lecture statique)
        ↓
entrée joueur réelle     (le reçu montre un clic/une touche sur l'affordance déclarée, pas un
                           appel direct à la méthode économique)
        ↓
observation contractuelle (l'effet est lu via le canal DOM/`window.__game` autorisé par
                           PLAYABLE_CONTRACT.md, jamais via `window.__game_debug` ou un import
                           direct du module logique)
        ↓
rôle effectivement couvert
```

Et pour `META_LOOP` (version affinée, remplace le schéma « 3 runs » ci-dessus dans l'ordre
d'enchaînement, sans changer le nombre de traversals) :

```
PLAYER_INPUT
    ↓
GAMEPLAY #1
    ↓
RESET / META
    ↓
GAMEPLAY #2
    ↓
GAMEPLAY #3
    ↓
conséquence observable
```

**Conséquence directe pour l'étape 3 « Où instrumenter » ci-dessous** : le validateur qui lira le
champ `canal` ne peut pas se contenter d'un `check_wiremap` élargi qui vérifie « le fichier cité
existe, la fonction cité existe ». Il doit pouvoir répondre à « ce canal est-il rattaché à une
preuve qui a RÉELLEMENT tourné » — ce qui implique de croiser la ligne WireMap avec un artefact
d'exécution (reçu `s10a-oracle-code`, log `e2e`, reçu `solvability`), pas seulement avec le code
source. **Comment faire ce croisement mécaniquement reste une question d'implémentation ouverte,
non tranchée ici** — proposition de départ : le reçu `s10a` (`evidence_path`) porte déjà les
actions réellement jouées par `solvability.mjs` (`FORGE_ORACLE solvability {...}` avec un journal
d'actions) et le log `e2e.mjs` porte un journal de lignes nommées (`P06 entrée : clic réel sur
acheter_producteur_0`) — un premier niveau, moins ambitieux qu'un vrai lien structurel, serait de
vérifier que la RÉFÉRENCE citée en `preuve` (ex. `P06`) apparaît dans CE journal d'exécution réel,
pas seulement dans le code source déclaré.

## Trois exigences à préserver dans le plan d'implémentation (Pierre, révision 2)

Retenues explicitement comme conditions du futur GO d'implémentation, à ne jamais relâcher en
cours de chantier :

1. **Aucun rétro-verdissement des anciens runs.** `chaton_clicker`, `v2_breakout_slice_r1`,
   `runm_breakout` gardent leur verdict signé tel quel ; la nouvelle règle ne réécrit ni ne
   ré-signe rien rétroactivement (cf. section Migration ci-dessous, `NOT_MEASURED` jamais `FAIL`
   sur l'historique).
2. **`WHITE_BOX` ne satisfait JAMAIS `PLAYER_LOOP`/`META_LOOP`**, quel que soit le nombre de
   lignes `WHITE_BOX` empilées sur la même capacité — pas de compensation par volume.
3. **`canal: PLAYER_LOOP` seul ne suffit pas.** Il doit être rattaché à une preuve identifiable
   ET exécutable (chaîne complète ci-dessus) — un enum juste posé à côté d'un `preuve` inchangé
   ne fait pas passer la ligne.

`check_wiremap_contract.mjs` / `schema_version: 2` reste HORS du premier patch (accord explicite
Pierre) : mélanger ce chantier avec une migration de schéma WireMap créerait deux chantiers dans
un seul GO, contraire à la doctrine « un GO par geste ».

## Où instrumenter (localisation précise, aucune ligne écrite ici)

Tout ce qui suit touche `forge/**` — surface protégée — et demande un GO d'implémentation
séparé, puis un ré-ancrage de l'empreinte de référence APRÈS ratification (jamais avant).

1. **Schéma WireMap** (`forge/static_oracles.py::check_wiremap`, appelé à `s10c-oracle-wiremap`) :
   ajouter un champ **structuré** par ligne, `canal: WHITE_BOX | PLAYER_INPUT | PLAYER_LOOP |
   META_LOOP` (liste si une ligne cumule plusieurs preuves de canaux différents — cas de
   `chaton_clicker` R2 qui a PLAYER_INPUT via `solvability.mjs` ET WHITE_BOX via `logic.test.mjs`
   pour l'effet). Enum fermée, comme `_CHARTER_STRING_FIELDS`/`_BRIEF_LIST_FIELDS` existants —
   même doctrine de validation (FAIL honnête, jamais d'exception).
2. **Remplacer/compléter `_PREUVE_GD`** : l'extracteur actuel est scopé `.gd` par accident
   d'héritage Godot. Il doit devenir langage-agnostique (`.gd`, `.mjs`, `.py`, au minimum) OU
   être remplacé par une vérification structurelle du nouveau champ `canal` plutôt que du texte
   libre `preuve` (le texte libre resterait à but humain/traçabilité, pas à but de validation).
3. **Le join rôle → canal** (nouvelle fonction, `forge/static_oracles.py` ou module dédié) :
   pour chaque capacité dont `source_ref` pointe un `loop.json[i].ref` de rôle ∈
   `{PLAYER_ACTION, GAME_RESPONSE, REWARD, DECISION, UNLOCK, NEXT_GOAL, REPEAT, META_LOOP,
   ADVANTAGE}` (liste `ROLE_ORDER` déjà définie dans `forge/loop_spec.mjs`, à réutiliser — pas
   à redéfinir une seconde fois), au moins une ligne WireMap qui la `couvre` doit porter un
   canal `PLAYER_LOOP` (ou `META_LOOP` pour le rôle `META_LOOP` spécifiquement). Une capacité
   couverte par des lignes `WHITE_BOX` uniquement = `passed: False`, raison nommée
   (`"R9 (P05, rôle DECISION) : couverte uniquement en WHITE_BOX, PLAYER_LOOP requis"`).
   **Ce join valide la présence de l'étiquette, PAS toute la chaîne** (cf. section
   « le canal est un contrat de preuve » ci-dessus) — il est nécessaire mais pas suffisant.
3bis. **La vérification « preuve identifiable + exécutable »** (distincte du join 3, sur la
   MÊME ligne) : croiser la référence citée (`preuve` ou une future sous-clé structurée, ex.
   `preuve_ref: "P06"`) avec un artefact d'exécution réel du run — reçu `s10a-oracle-code`
   (`evidence_path`, journal `solvability` avec ses actions jouées) ou log `e2e.mjs` (lignes
   nommées `P0x : …`). Une ligne `canal: PLAYER_LOOP` dont la référence n'apparaît dans AUCUN
   journal d'exécution réel doit rester `NOT_MEASURED`/`FAIL`, jamais `PASS` sur la seule foi de
   l'enum. **Le mécanisme exact de ce croisement (format du reçu, granularité de la référence)
   n'est pas tranché ici — c'est la question ouverte principale du futur GO d'implémentation.**
4. **`s5-wiremap` (tâche par défaut, `forge/run_real.py::default_task_by_step`)** : le prompt de
   l'agent doit désormais EXIGER le champ `canal` par ligne, avec sa définition — sans quoi
   l'agent continuera à produire des `preuve` en texte libre sans le savoir. Même doctrine que
   l'ajout du champ `couvre` lui-même (2026-08-04, cf. en-tête `check_wiremap_contract.mjs`).
5. **`s12-verdict`** (`forge/verdict.py::build_aggregate_verdict`) : un rôle PLAYER_LOOP/META_LOOP
   non couvert alimente un `humangate_flags` NOMMÉ (`"joueur non prouvé sur: R9(P05,DECISION),
   R11(P08,NEXT_GOAL#2), R12(P09,REPEAT)"`), distinct des flags génériques actuels (« red-team
   dégradé », « standard non vérifiée ») qui ne portent aucune information sur CE défaut précis.
6. **`check_wiremap_contract.mjs`** (V4 GAME LOOP, `schema_version: 2`) : à netttoyer plus tard —
   soit migrer les jeux web vers ce schéma pour réutiliser sa résolution `provides`/`requires`
   (le canal `PLAYER_LOOP` pourrait alors se DÉRIVER de la chaîne affordance→effet plutôt que
   d'être déclaré à la main), soit documenter explicitement qu'il reste réservé à une future
   lignée et n'est pas le mécanisme visé par ce chantier. Question ouverte, pas tranchée ici.

## Migration — ne jamais fabriquer un vert rétroactif

Les runs déjà signés (`chaton_clicker`, `v2_breakout_slice_r1`, `runm_breakout`, …) n'ont pas de
champ `canal`. Une bascule dure casserait leur re-vérification (`verify_run`) sans aucune valeur
ajoutée — leur verdict reste ce qu'il est, signé sous l'ancien contrat. Proposition (N7 : jamais
de PASS sur un volet non mesuré) :
- `canal` absent sur une capacité `PLAYER_LOOP`/`META_LOOP` → **`NOT_MEASURED`**, jamais `FAIL`
  ni `PASS`, jusqu'à une date de bascule ratifiée par Pierre.
- Après bascule : absent = FAIL (le comportement dur décrit ci-dessus).
- Le verdict déjà signé de `chaton_clicker` n'est PAS retouché. Une note HumanGate peut être
  ajoutée en marge (proposée, jamais imposée) : « sous la taxonomie canal, R9/R11/R12 liraient
  aujourd'hui `NOT_MEASURED` en `PLAYER_LOOP` ».

## Oracle du chantier lui-même

Ce chantier modifie la Forge, pas un jeu : il suit `forge/test_surfaces.yaml`
(`create_allowed_modify_denied` — créer des tests neufs est permis, modifier un test préexistant
demande une gate Pierre explicite), pas un run `forge.run_real`. Geste proposé :
1. fixture de régression : une WireMap minimale reproduisant le cas `chaton_clicker`
   (une capacité `source_ref` sur un rôle `DECISION`, couverte uniquement par une ligne
   `canal: WHITE_BOX`) — doit `FAIL` une fois la règle codée ; test NEUF, autorisé sans gate.
2. fixture positive : la même capacité couverte en plus par une ligne `canal: PLAYER_LOOP` —
   doit `PASS`.
3. Aucun test existant de `forge/tests/**` n'est modifié pour faire passer ces deux cas ; s'il
   fallait en toucher un, gate Pierre nommée avant.

## Ce que ce plan ne fait PAS

- Ne touche aucun fichier de `forge/**`.
- Ne relance aucune campagne, ne modifie pas `GAMES/chaton_clicker/`.
- Ne décide pas seul de la bascule dure/molle — proposée, pas tranchée.
- Ne referme pas la question `check_wiremap_contract.mjs` vs schéma v1 — signalée, pas résolue.

`claim_verdict: NO_CLAIM_ALLOWED` — ce document est un plan, pas une preuve d'implémentation.

## Statut

Plan accepté par Pierre comme plan de travail (2026-09-07, révision 2) — « aucun code lancé ».
L'implémentation dans `forge/**` attend un GO distinct et nommé : « GO chantier canal-de-preuve »
(réservé à cet usage précis, ne pas confondre avec le GO qui a produit ce document). Ce fichier
peut être committé indépendamment de ce GO — commit à faire seulement sur GO explicite séparé.
