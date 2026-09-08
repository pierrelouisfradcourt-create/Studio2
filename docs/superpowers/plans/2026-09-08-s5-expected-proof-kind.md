# S5 : préférence de preuve `PLAYER_*` quand `expected_proof.kind` l'exige — plan (pas implémenté)

> **For agentic workers:** PLAN uniquement. Aucune ligne de `forge/**` n'est modifiée par
> ce fichier. GO Pierre 2026-09-08 : « écrire le plan », pas d'implémentation. Le GO
> d'implémentation reste séparé, comme pour les deux chantiers précédents (canal-de-
> preuve, couvre-REJEU).

*Date : 2026-09-08 · Source : audit lecture-seule de Q2 (« pourquoi `R3` reste
`WHITE_BOX` alors qu'une preuve joueur existe »), sur `chaton_clicker_canal_probe_2`
(preuve canonique `f8204b0`).*

## Diagnostic établi (audit lecture-seule, ne se redémontre pas ici)

`R3` (« caresser incrémente les ronrons », l'EFFET de `P02`) est étiqueté `WHITE_BOX`
et cite `logic.test.mjs::caresser`, alors qu'`e2e.mjs`/`solvability.mjs` démontrent le
même fait par un vrai clic. **L'information n'était PAS manquante** :

- `featuremap.json` porte, pour `cap_caresser_effet` : `expected_proof: {kind:
  "bot_action", statement: "...le bot mesure dans le DOM que le compteur ronrons a
  augmenté."}` — décidé et mécaniquement vérifié dès s3 (`forge/check_decompo.mjs`,
  contrôle `boucle_sans_effet`, `EFFECT_KINDS`/règle V4 boucle joueur).
- `artifacts/s3-decompo.txt` (texte brut de s3) **explicite** cette exigence : *« les
  DEUX feuilles doivent donc être `bot_action` ET citer le point d'entrée »* — et ce
  texte est injecté VERBATIM dans le prompt de s5 (`_UPSTREAM_BY_STEP["s5-wiremap"]`,
  [forge/run_real.py:3047](../../../forge/run_real.py)).

**Cause exacte, confirmée par recherche directe** : `forge/contracts/s5-wiremap.yaml`
ne mentionne JAMAIS `expected_proof`, `kind`, ni `bot_action` (zéro occurrence). Rien
n'instruit l'agent à faire correspondre le `canal`/`preuve` d'une ligne au
`expected_proof.kind` que s3 a déjà fixé pour la capacité qu'elle `couvre`. Ce n'est
pas un problème d'architecture de preuve (l'information circule) ni d'artefacts
indisponibles (le texte est là) — c'est une **absence de règle contractuelle**, même
famille de défaut que le chantier couvre-REJEU (contrat s5 incomplet vis-à-vis d'une
décision déjà prise en amont).

## Modèle cible

Vocabulaire déjà existant et mécaniquement enforcé à s3 (`forge/check_decompo.mjs:61`,
`EFFECT_KINDS = ['file_write', 'visual']`, plus `bot_action` pour les capacités
d'ENTRÉE et, depuis la règle V4 boucle joueur, pour certaines capacités d'EFFET aussi)
— trois `kind` connus comme PLAYER-FACING : `bot_action`, `visual`, `file_write` (ce
dernier au sens d'un écrit produit et lisible, pas d'un test unitaire).

Règle proposée : **quand la capacité qu'une ligne WireMap `couvre` porte un
`expected_proof.kind` ∈ {`bot_action`, `visual`, `file_write`}, le `canal` de cette
ligne DOIT être `PLAYER_LOOP`/`PLAYER_INPUT`/`META_LOOP` — jamais `WHITE_BOX` seul,
même si un test unitaire existe ET vérifie honnêtement le même fait.** Un test
unitaire reste une preuve légitime en PLUS (`canal: [PLAYER_LOOP, WHITE_BOX]`, liste
déjà supportée par le schéma `canal` du chantier canal-de-preuve), jamais en
remplacement lorsqu'un `kind` joueur est exigé en amont.

```
featuremap.json : cap_x.expected_proof.kind = bot_action|visual|file_write
        ↓ (déjà transmis, artifacts/s3-decompo.txt injecté à s5)
s5-wiremap.yaml : DOIT exiger canal PLAYER_* pour toute ligne couvrant cap_x
        ↓
WireMap.couvre = cap_x, canal = PLAYER_LOOP (jamais WHITE_BOX seul)
        ↓
check_player_loop_coverage (forge/static_oracles.py) : vérifie mécaniquement
la correspondance kind → canal, pas seulement rôle → canal (portée actuelle)
```

## Ce qui doit changer, précisément

### 1. `forge/contracts/s5-wiremap.yaml` — `output_contract`

Ajouter une clause, à côté (jamais en remplacement) de la clause REJEU déjà posée
(chantier couvre-REJEU, commit `b6678b2`) :

> Pour toute ligne dont `couvre` cite une capacité dont `expected_proof.kind` (dans
> featuremap.json / `artifacts/s3-decompo.txt`) vaut `bot_action`, `visual` ou
> `file_write` : `canal` DOIT inclure `PLAYER_LOOP` (ou `META_LOOP` si le rôle est
> META_LOOP), même si un test unitaire (`WHITE_BOX`) existe aussi pour le même fait
> — `WHITE_BOX` seul ne suffit jamais à honorer un `kind` déjà décidé côté joueur.
> `canal` peut porter les deux valeurs (`["PLAYER_LOOP", "WHITE_BOX"]`) si les deux
> preuves existent réellement.

### 2. `forge/static_oracles.py::check_player_loop_coverage`

**Second geste nécessaire**, même schéma que pour REJEU : sans lui, la règle du
contrat reste une déclaration d'intention non vérifiée. Extension additive :

1. Lire `expected_proof.kind` par capacité depuis `featuremap.json` (nouvelle petite
   fonction privée, symétrique de `_capacity_source_ref_by_id` — ex.
   `_capacity_expected_kind_by_id`).
2. Pour chaque ligne WireMap dont `couvre` cite une capacité dont le kind ∈
   `{"bot_action", "visual", "file_write"}` : vérifier que le `canal` de CETTE ligne
   (ou d'une AUTRE ligne couvrant la MÊME capacité — même logique d'agrégation que
   `canals_by_cap`) inclut `PLAYER_LOOP`/`META_LOOP`. Sinon, raison nommée dans une
   nouvelle clé de retour (proposée : `kind_non_honore`), distincte de
   `roles_manquants` (rôle de boucle) et de `couvre_non_resolu` (forme) — TROIS
   dimensions de défaut désormais séparées, jamais confondues.
3. Portée : cette vérification est INDÉPENDANTE de `loop.json`/des rôles de boucle —
   elle s'applique à TOUTE capacité, qu'elle soit ou non source_ref d'un rôle
   PLAYER_LOOP_ROLES. Une capacité `bot_action` hors boucle joueur nommée reste
   soumise à la même exigence (le `kind` est la source de vérité, pas le rôle).

### 3. `forge/contracts/s3-decompo.yaml`

**Non touché** — la production de `expected_proof.kind` y est déjà correcte et
mécaniquement vérifiée (`check_decompo.mjs`). Ce chantier ne change rien en amont de
s5.

## Invariants à préserver (reconduits des deux chantiers précédents)

1. Aucun rétro-verdissement des runs déjà signés (`chaton_clicker`, les deux probes,
   `chaton_clicker_canal_probe_2`) — absence du contrôle `kind_non_honore` dans un
   ancien reçu n'est jamais un `FAIL` rétroactif : cette clé, absente d'un ancien
   run, doit être lisible comme non mesurée sur cet ancien reçu (même doctrine
   `NOT_MEASURED` que le chantier canal-de-preuve).
2. `s3-decompo.yaml` reste inchangé.
3. `WHITE_BOX` seul ne satisfait jamais une exigence de `kind` joueur — un test
   unitaire correct ne remplace pas une preuve DOM quand featuremap l'exige.
4. `check_wiremap_contract.mjs`/`schema_version: 2` restent HORS de ce chantier.
5. `run_real.py` : pas de changement nécessaire identifié à ce stade — le texte de
   tâche de s5 n'a pas besoin d'être réécrit, `output_contract` (injecté verbatim,
   `forge/contract.py:608`) porte la règle. À confirmer au moment de
   l'implémentation si le texte de tâche a besoin d'un rappel, comme cela avait été
   nécessaire pour la clarification PLAYER_LOOP vs PLAYER_INPUT (commit `6981122`).

## Oracle du chantier (proposé, pas exécuté)

`forge/test_surfaces.yaml` (`create_allowed_modify_denied`) — tests NEUFS
uniquement :
1. Fixture reproduisant EXACTEMENT le cas mesuré (`cap_caresser_effet` en
   `expected_proof.kind: bot_action`, WireMap ligne `canal: WHITE_BOX` seul) → doit
   `FAIL` (`kind_non_honore`), raison nommée.
2. Même fixture avec `canal: ["PLAYER_LOOP", "WHITE_BOX"]` → `PASS`.
3. Fixture où `expected_proof.kind` n'est PAS dans l'ensemble joueur (ex. absent, ou
   une valeur non reconnue) → aucune exigence, comportement inchangé (fail-safe : ne
   jamais deviner un kind non déclaré).
4. Rejouer `chaton_clicker_canal_probe_2` (lecture seule, sans nouveau run réel)
   contre la fonction patchée, pour mesurer combien de lignes existantes tombent
   sous `kind_non_honore` — sans réécrire ce run (invariant 1).

## Question ouverte avant implémentation

L'ensemble exact des `kind` à traiter comme « joueur » — `{bot_action, visual,
file_write}` — est dérivé de `check_decompo.mjs` (lignée web/générique actuelle).
D'autres lignées (Godot) ou contrats futurs pourraient introduire d'autres valeurs de
`kind` (ex. `oracle`, `gpu_window`, vus dans des contrats plus anciens type
kitten_clicker V1). Faut-il une liste fermée maintenue à la main dans
`static_oracles.py` (risque de dérive si `check_decompo.mjs` évolue sans que ce
module soit mis à jour), ou une lecture dynamique d'un vocabulaire partagé ? Pas
tranché ici — signalé pour la décision d'implémentation.

## Ce que ce plan ne fait PAS

- Ne touche aucun fichier de `forge/**`.
- Ne relance aucun run.
- Ne modifie `forge/contracts/s3-decompo.yaml` en aucune façon.
- Ne referme pas la question du vocabulaire `kind` multi-lignées (signalée, pas
  résolue).
- Ne traite ni `schema_version: 2` ni le probe 1 en attente.

`claim_verdict: NO_CLAIM_ALLOWED` — plan, pas preuve d'implémentation.
