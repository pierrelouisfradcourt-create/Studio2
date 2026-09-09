# Harmonisation `couvre` pour les rôles REJEU (REPEAT/ADVANTAGE) — plan (pas implémenté)

> **For agentic workers:** PLAN uniquement. Aucune ligne de `forge/**` n'est modifiée par
> ce fichier. GO Pierre 2026-09-08 : « prépare précisément le patch et les invariants,
> pas de modification immédiate ». Le GO chantier d'implémentation reste séparé.

*Date : 2026-09-08 · Source : investigation lecture-seule de l'anomalie `couvre` R12/R15
(3 runs indépendants : `chaton_clicker`, `chaton_clicker_canal_probe`,
`chaton_clicker_canal_probe_2` — ce dernier committé comme preuve canonique du chantier
canal-de-preuve, `f8204b0`) + décision Pierre 2026-09-08 (option a).*

## Diagnostic établi (rappel, ne se redémontre pas ici)

Contradiction entre deux contrats, reproduite à l'identique sur 3 runs :
- `forge/contracts/s3-decompo.yaml` (gardeFou) : REPEAT (H) et ADVANTAGE (J) « n'exigent
  AUCUNE feuille propre » — satisfaits par `replay`/`replay_ref` ciblant une exigence
  DÉJÀ couverte ailleurs.
- `forge/contracts/s5-wiremap.yaml` (`output_contract`) : « chaque ligne porte
  `couvre: [...]`, NON VIDE, citant l'id EXACT d'une capacité… DANS LES DEUX CAS »,
  sans exception pour les lignes REJEU.

Résultat mesuré : l'agent s5 invente une référence non conforme (`rejouerBoucle`,
`gainParCaresse` — des noms de méthode, jamais des ids `cap_*`) faute d'alternative.
`check_player_loop_coverage` (forge/static_oracles.py, chantier canal-de-preuve, CLOS)
rapporte alors « traçabilité rompue », honnêtement, mais ne peut jamais résoudre ces
deux lignes tant que le contrat ne prévoit pas de forme valide pour un `couvre` REJEU.

## Décision Pierre : option (a)

Ne pas créer de `cap_*` artificiels pour des rôles qui sont explicitement des rejeux
(refus de l'option b — polluerait le modèle conceptuel de FeatureMap). `s3-decompo.yaml`
reste **INCHANGÉ** dans ce chantier.

```
CAPACITÉ NORMALE                    REJEU
P02/P03/P04...                      P09 REPEAT / P11 ADVANTAGE
      ↓                                   ↓
   cap_xxx                          replay / replay_ref
      ↓                                   ↓
WireMap.couvre = cap_xxx            WireMap.couvre = référence au contrat rejoué
```

« Référence au contrat rejoué » se résout SANS nouveau champ ni nouvel id : `loop.json`
porte déjà `replay: [P02,P03,P04,P06]` (P09) et `replay_ref: P02` (P11) ; ces refs
pointent des rôles qui, par construction du gardeFou s3 (« déjà couverte ailleurs »),
ONT une ou plusieurs capacités réelles (`source_ref` égal à ce ref). **`couvre` d'une
ligne REJEU doit donc citer les id(s) `cap_*` réel(s) DE LA/DES CAPACITÉ(S) REJOUÉE(S)**
— jamais un id inventé, jamais un nom de méthode.

Exemple concret (chaton_clicker) : `P09` rejoue `[P02,P03,P04,P06]` → `R12.couvre` =
`["cap_caresser_entree", "cap_caresser_effet", "cap_recompense_bouton_producteur",
"cap_acheter_producteur_entree", "cap_acheter_producteur_effet"]` (les capacités réelles
dont `source_ref` ∈ {P02,P03,P04,P06}). `P11` rejoue `P02` → `R15.couvre` =
`["cap_caresser_entree", "cap_caresser_effet"]`.

## Ce qui doit changer, précisément

### 1. `forge/contracts/s5-wiremap.yaml` — `output_contract`

Ajouter une clause d'exception explicite, immédiatement après la règle « DANS LES DEUX
CAS… NON VIDE » actuelle (ne pas la retirer, l'exception s'ajoute) :

> Pour une ligne qui documente un rôle REJEU (REPEAT/ADVANTAGE de loop.json,
> `replay`/`replay_ref` non vide) : `couvre` cite l'id (ou les ids) `cap_*` RÉEL(S) de
> la/des exigence(s) que `replay`/`replay_ref` cible(nt) dans loop.json — jamais un id
> inventé, jamais un nom de méthode/fonction. N'invente AUCUNE capacité nouvelle pour
> le rôle REJEU lui-même (`s3-decompo.yaml` ne lui en fournit délibérément aucune).

Ce texte suffit seul : `output_contract` est injecté VERBATIM dans le prompt de
l'agent (`forge/contract.py:608`, section « CONTRAT DE SORTIE ») — pas besoin de
répéter la règle dans `forge/run_real.py::default_task_by_step`.

### 2. `forge/static_oracles.py::check_player_loop_coverage`

**Nécessaire même après le fix du contrat** — sans ce second geste, la fonction reste
aveugle : elle cherche aujourd'hui une capacité dont `source_ref == ref` du rôle
lui-même. Pour P09/P11, un tel `source_ref` n'existera JAMAIS (par construction de
l'option a) — le rôle resterait en « traçabilité rompue » même une fois `couvre` corrigé.

Ajout ciblé (fonction existante, additif) : quand `role in {"REPEAT", "ADVANTAGE"}`,
résoudre la couverture via `loop.json[ref].replay` (liste de refs) ou `.replay_ref`
(un ref) au lieu de chercher `source_ref == ref` :
1. Récupérer les refs rejoués (`replay` ou `[replay_ref]`).
2. Pour chaque ref rejoué, vérifier qu'il est LUI-MÊME couvert en `PLAYER_LOOP`/
   `META_LOOP` (même logique que pour un rôle normal).
3. Le rôle REJEU est `PASS` ssi TOUS les refs qu'il rejoue sont eux-mêmes `PASS`.
   Un rejeu qui vise un rôle NON PROUVÉ joueur ne peut pas hériter d'une preuve qui
   n'existe pas (ex. mesuré : `P09` rejoue `P04` qui, actuellement, ressort lui-même
   FAIL sur `chaton_clicker_canal_probe_2` faute de `PLAYER_LOOP` propre — un rejeu
   « propre » côté contrat resterait donc `FAIL`, à raison : il rejoue une preuve qui
   n'existe pas encore).
4. `couvre` invalide (un id qui ne résout à AUCUNE capacité réelle, ancien
   comportement toléré par accident) devient une raison de FORME distincte, nommée
   (`check_wiremap_canal` ou une garde sœur) — PROPOSÉ, pas encore localisé
   précisément dans quelle fonction (question ouverte ci-dessous).

### 3. `forge/contracts/s3-decompo.yaml`

**INCHANGÉ** — confirmé explicitement pour fermer l'option (b).

## Invariants à préserver (mêmes exigences que le chantier canal-de-preuve, reconduites)

1. Aucun rétro-verdissement : les 3 runs déjà signés (`chaton_clicker`,
   `chaton_clicker_canal_probe`, `chaton_clicker_canal_probe_2`) ne sont jamais
   retouchés ni re-jugés par ce chantier.
2. `s3-decompo.yaml` reste inchangé (option a confirmée, option b explicitement fermée).
3. Un `couvre` REJEU qui invente encore un id non résolu reste un défaut détecté,
   jamais une tolérance silencieuse — même doctrine « jamais un vert par défaut ».
4. Un rejeu qui cible un rôle lui-même non prouvé `PLAYER_LOOP` reste `FAIL` — le
   rejeu n'invente pas de preuve, il en hérite seulement d'une qui existe déjà.
5. `check_wiremap_contract.mjs` / `schema_version: 2` restent HORS de ce chantier —
   même exclusion que le chantier canal-de-preuve, pour ne pas fusionner trois
   migrations dans un seul GO.
6. La question de préférence de citation (Q2, distincte) n'est pas traitée ici.

## Oracle du chantier (proposé, pas exécuté)

Suit `forge/test_surfaces.yaml` (`create_allowed_modify_denied`) — tests NEUFS
uniquement, aucun test existant modifié :
1. Fixture reproduisant EXACTEMENT le cas mesuré (`P09` rejoue `[P02,P03,P04,P06]`,
   `couvre` invalide `['rejouerBoucle']`) → doit `FAIL`, raison nommée « couvre non
   résolu, pas un id de capacité ».
2. Même fixture avec `couvre` corrigé (ids réels des capacités rejouées, toutes
   elles-mêmes `PLAYER_LOOP`) → doit `PASS`.
3. Fixture où un rejeu cible un rôle NON couvert en `PLAYER_LOOP` → doit rester
   `FAIL`, raison nommée (hérite d'une preuve absente).
4. Rejouer les 3 runs existants (lecture seule, sans nouveau run réel) contre les
   fonctions patchées, pour confirmer que le diagnostic actuel (P09/P11 en échec) ne
   change QUE de raison affichée tant que `couvre` n'est pas manuellement corrigé
   dans leurs artefacts — ces 3 runs ne sont PAS réécrits (invariant 1).

## Question ouverte avant implémentation

Où loger la détection « `couvre` cite un id qui ne résout aucune capacité réelle » —
dans `check_player_loop_coverage` elle-même (actuellement elle ignore silencieusement
un `cid` non résolu, cf. `canals_by_cap.setdefault(cid, ...)` qui accepte n'importe
quelle chaîne comme clé) ou dans une garde de forme séparée (symétrique de
`check_wiremap_canal`) ? Pas tranché ici — à décider au moment du GO d'implémentation.

## Ce que ce plan ne fait PAS

- Ne touche aucun fichier de `forge/**`.
- Ne relance aucun run.
- Ne modifie `s3-decompo.yaml` en aucune façon.
- Ne traite ni la préférence de citation (Q2) ni `schema_version: 2`.

`claim_verdict: NO_CLAIM_ALLOWED` — plan, pas preuve d'implémentation.
