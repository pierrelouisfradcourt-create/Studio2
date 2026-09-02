# FORGE ARCHITECT MANUAL — V1 (notice d'assemblage)

**Statut : PROPOSED** — rédigé le 2026-07-28 par la session Fable (troisième cerveau) à partir
du brief Pierre×GPT du 2026-07-28 et des règles d'usine ratifiées (schéma maître Détail K,
variance des métriques 2026-07-21, invariants qualité 2026-07-27). Ratification = Pierre.

**Pour qui** : tout agent qui conçoit ou assemble un jeu dans la Forge (« l'IA junior »).
Ce n'est pas un manuel technique : c'est la notice d'assemblage d'un architecte AAA.

## Consommateurs (règle de câblage — un document sans lecteur est un artefact passif)

| Consommateur | Comment il le lit | État du câblage |
|---|---|---|
| s2-worldscan (contrat) | `mandatory_read` — cadre du dossier d'observation (§2) | CÂBLÉ (2026-07-28) |
| Lentilles du Prisme (M-E) | `mandatory_read` — checklist §4 = leur schéma de sortie | À CÂBLER en M-E |
| s4-archi / s5-wiremap | `mandatory_read` — §3 et §5 | À CÂBLER (re-spéc s4, décision Pierre) |
| Pierre (HumanGate) | référence de review | humain |

Chaque règle ci-dessous se termine par **Vérifié par :** un check mécanique existant,
un check à créer (nommé), ou `HUMAN_ONLY`. Une règle sans vérificateur nommé n'entre pas.

---

## 0. La règle fondamentale

Un architecte AAA ne crée pas un jeu. Il **sélectionne, adapte et assemble** des systèmes
éprouvés. La création ex nihilo est l'exception justifiée, jamais le réflexe
(biais anti-création du studio : ne rien faire > supprimer > mémoire > corriger > améliorer > créer).

Chaîne de fabrication :

```
Référence AAA (observation) → World Scan → Genre Bible → Prisme (compression)
  → Architecture minimale → Wiremap → Production → Oracle → Apprentissage
```

La question de l'architecte n'est jamais « comment coder un inventaire ? » mais
« **quelle brique d'inventaire correspond à notre niveau d'ambition ?** ».

**Vérifié par :** `reuse_ratio.mjs` (part de briques importées vs créées) + champ
`REUSED_FROM` de la wiremap (§5).

## 1. La boîte de briques

Avant de construire, connaître ce qui existe. Quatre familles :

- **Core gameplay** : game loop, ECS/state machine, event bus, ability/combat,
  inventaire, quêtes, dialogue, save.
- **Métagame** : progression joueur, déblocages, récompenses, collection, craft,
  économie, achievements, boucle quotidienne.
- **Services** : API, base de données/persistance, cloud save, analytics, télémétrie, auth.
- **Production** : pipeline assets, pipeline niveaux, localisation, build, tests.

Sources de briques du studio, dans l'ordre de préférence :
1. `knowledge_base/` (briques cataloguées, kb-validate) ;
2. jeux verts existants (Pong gelé = témoin, ses briques sont candidates à l'import) ;
3. brique externe éprouvée (licence vérifiée) ;
4. création — seulement après les 5 questions du §6.

**Vérifié par :** `kb-validate` (validité des briques) · `check_worldscan.mjs`
(architecture_guess doit nommer les briques candidates AVANT production — condition Pierre).

## 2. Le World Scan : une caméra d'architecte, pas un scraper

Le World Scan produit un **dossier d'observation** (`GAME_REFERENCE/`), pas un tas de texte :

```
GAME_REFERENCE/
├── mechanics_analysis.md      # mécaniques observées, par jeu
├── progression_map.md         # ce qui débloque quoi, à quel rythme
├── economy_map.md             # ressources, sources, puits
├── ux_flow.md                 # écrans, HUD, transitions
├── architecture_guess.md      # systèmes probables + briques candidates à l'import
└── observation_manifest.json  # sources citées (URL + timestamp), boucles, rétention
```

Règles d'observation :
- **URLs citées + timestamps, jamais de collecte locale de médias** (ratifié Pierre
  2026-07-28) : on regarde, on cite, on analyse — on ne copie pas.
- Chaque jeu observé est décrit à 4 horizons : **boucle minute 1 · minute 10 ·
  heure 5 · endgame**.
- Trois questions obligatoires par jeu : pourquoi le joueur revient ? quelle récompense
  arrive ? quel système pousse le prochain clic ?
- Pas pour copier : pour comprendre l'assemblage (rétro-ingénierie de l'architecture).

**Vérifié par :** `check_worldscan.mjs` (complétude du dossier, sources citées,
interdiction des médias locaux — créé 2026-07-28).

## 3. Pratiques d'architecture (le cœur du métier, expliqué au junior)

1. **Sépare la logique pure de la présentation.** Les systèmes (règles, état,
   résolution) ne connaissent ni le rendu ni l'input. Leçon mesurée du studio :
   sur Pong, les systèmes purs tuaient 95 % des mutants, les adaptateurs de
   présentation 0 % — la logique pure est la seule chose que l'oracle protège bien.
   **Vérifié par :** repo_map (`system` vs `system.adapter`) + gate mutation par catégorie.
2. **Les dépendances vont dans un seul sens.** Systèmes → jamais vers l'UI ; adaptateurs →
   vers les systèmes. Un cycle de dépendance est un défaut d'architecture, pas un détail.
   **Vérifié par :** s10b (oracle archi) sur le blueprint.
3. **Tranche verticale d'abord.** Le premier livrable traverse tout (input → règle →
   état → rendu → sortie observable) sur UN cas ; on élargit ensuite. Jamais trois
   systèmes complets sans un fil jouable.
   **Vérifié par :** oracle produit (volet boot + partie auto) — le fil doit s'exécuter.
4. **`observable_by_player` est une contrainte de conception, pas une finition.**
   Chaque système déclare dès la wiremap ce que le joueur en voit. Un système
   invisible au joueur doit justifier son existence.
   **Vérifié par :** `check_observable_coverage`.
   **TYPE, ET C'EST UNE RÈGLE, PAS UN DÉTAIL** : `observable_by_player` est un
   BOOLÉEN (`true`/`false`) et `observable_proof` est le NOM COURT d'un volet du reçu
   d'oracle (`auto_session`, `exit_stop_wiring`…). Une phrase dans l'un ou l'autre est
   invisible à l'oracle : mesuré le 2026-07-28 sur la carte Snake, 44 lignes remplies
   en prose ont produit `{"couvertes": [], "passed": true}` — un vert obtenu parce
   qu'il n'y avait rien à vérifier. **Un champ que l'oracle lit comme un type ne
   contient jamais de justification** ; la justification va dans un champ de prose.
   Corollaire général : quand un oracle « ignore » une valeur au lieu de la refuser,
   il fabrique du vert. Le silence sur une valeur inattendue est un défaut d'oracle.
5. **Toute décision d'architecture est un champ structuré, jamais un commentaire**
   (ratifié 2026-07-23). Les choix notables → ADR court (contexte · options ·
   décision · conséquences) ou champ de wiremap.
   **Vérifié par :** HUMAN_ONLY (review) — les champs eux-mêmes par les validateurs de wiremap.
6. **Nomme les patterns que tu utilises** (state machine, event bus, command…) — un
   pattern nommé est comparable et réutilisable ; un pattern anonyme est du code à relire.
   **Vérifié par :** HUMAN_ONLY (Prisme, lentille architecte).
7. **Dimensionne au niveau d'ambition** (YAGNI) : pas d'API réseau pour un jeu local,
   pas de base de données pour trois clés de sauvegarde. La checklist TECHNIQUE du
   Prisme (§4) pose ces questions explicitement.
   **Vérifié par :** `check_prisme` (section TECHNIQUE renseignée).
8. **Une métrique doit prouver sa variance avant de servir** (ratifié 2026-07-21) :
   une mesure qui classe/génère/calibre doit montrer ≥2 valeurs distinctes non
   triviales sur échantillon, sinon elle est requalifiée honnêtement.
   **Vérifié par :** protocole de variance (échantillon + distribution au rapport).

## 4. Le Prisme : la design review qui évite le « techniquement cool mais vide »

Le Prisme est une **revue d'architecture obligatoire avant production**. Sa sortie n'est
pas un avis : c'est une liste structurée de décisions — **nécessaire / rejeté / pourquoi /
impact architecture** — exploitable par `check_prisme`.

Checklist de base (le schéma du fichier de sortie, pas du texte libre) :

- **GAME DESIGN** : le joueur sait quoi faire en 30 s ? boucle minute→session→retour
  demain ? progression visible ? le joueur comprend son amélioration ?
- **MÉTAGAME** : objectif long terme ? collection ? déblocages ? maîtrise ? raison de revenir ?
- **GAME FEEL** : actions satisfaisantes ? feedback visuel ? feedback sonore ?
  récompenses fréquentes ?
- **ARCHITECTURE** : systèmes séparés ? dépendances à sens unique ? une brique
  existante aurait-elle suffi ? le système produit est-il réutilisable ?
- **TECHNIQUE** : API nécessaire ou local suffit ? quelles données persistent, quel
  format, migration ? moteur/librairies choisis, licence, pérennité ?

Une case non applicable se répond `N/A + raison`, jamais par le silence.

**Vérifié par :** `check_prisme.mjs` (complétude structurée) + `merge_prisme.mjs`
(recombinaison mécanique des lentilles, GAP explicites, zéro LLM-arbitre).

## 5. La Wiremap : le plan de montage

Chaque bloc de la wiremap porte, en champs structurés :

```
ID: · ROLE: · INPUT: · OUTPUT: · DEPENDENCIES: · REUSED_FROM: · OBSERVABLE_BY_PLAYER:
```

- `REUSED_FROM` pointe une brique réelle (KB, jeu gelé, externe) ou vaut `NEW` —
  c'est l'instrument de la mesure d'accélération (reuse_ratio).
- Une ligne de wiremap est une **promesse exacte** : ce qui est promis est déposé,
  ce qui est déposé est mesuré sous le nom promis (règle d'usine n°4).

**Vérifié par :** validateurs wiremap + `check_observable_coverage` + `reuse_ratio.mjs`.

## 6. La règle IKEA : avant de créer une brique neuve

L'agent répond aux 5 questions, dans la sortie structurée (pas en commentaire) :

1. Existe-t-elle déjà ? (KB, jeux verts, externe)
2. Peut-on l'étendre ?
3. Peut-on la simplifier ?
4. Peut-elle devenir générique (réutilisable par le prochain jeu) ?
5. Quel coût futur crée-t-elle (maintenance, dépendance, licence) ?

Et la **règle de câblage** (ratifiée Pierre 2026-07-28), qui vaut pour le studio
lui-même : tout artefact créé (document, contrat, check, skill) doit avoir **au moins
un consommateur identifié** — agent, étape du pipeline, ou validation. Un écrivain sans
appelant / un lecteur sans données est le mode de panne n°1 du studio (6 occurrences
prouvées). **Vérifié par :** `studio_selfaudit.mjs` (connecteurs dormants) + review.

## 6 bis. Deux leçons du cycle Snake (ratifiées Pierre 2026-07-29)

Nées d'un cas mesuré : Snake a satisfait **toutes** ses preuves — 282 assertions, 63/64
mutants tués, bot solvable 50/50, 8 volets d'observabilité, `verify_run` AUTHENTIQUE — et
**ne démarrait pas**. `project.godot` pointait vers une scène qui n'existait pas ; le projet
ne contenait aucun `.tscn`.

### Leçon 1 — La preuve ne remplace jamais l'exécution produit

> Un projet peut satisfaire ses tests, ses contrats et ses oracles tout en étant impossible
> à lancer.

La validation doit inclure un **chemin d'entrée utilisateur réel** : point d'entrée déclaré
→ scène/runtime chargé → **rendu observable**. Les index prouvent la **cohérence des
déclarations**, jamais l'**exhaustivité des besoins**.

**Vérifié par :** un lancement réel borné (`--quit-after N`) dont la sortie est jointe, plus
un oracle de rendu exécuté en fenêtre GPU. Aucune suite de tests unitaires ne remplace ces
deux-là.

### Leçon 2 — Un contrat déclare les éléments structurels OBLIGATOIRES, pas seulement les fichiers existants

> Une carte qui ne déclare que les fichiers présents ne peut pas détecter un élément absent
> mais nécessaire.

Les **points d'entrée** (scène principale, bootstrap, entrypoint runtime) sont des
**invariants explicites du contrat**, et doivent être vérifiés **en absence comme en
présence**. C'est la différence entre « tout ce qui est déclaré existe » (vérifié
aujourd'hui) et « tout ce qui est nécessaire est déclaré » (qui ne l'était pas).

**Vérifié par :** rien, à ce jour — `check_index` ne peut pas voir manquer ce que personne
n'a déclaré. **Dette nommée**, à traiter par un invariant de contrat, pas par un cas
particulier.

---

## 7. Rappel des règles d'usine (non négociables, Détail K)

1. Une preuve sans lecteur branché n'existe pas dans la chaîne qualité.
2. Un état RUNNING doit être confirmé par une réalité externe.
3. Un test vérifie une propriété durable, pas une valeur historique.
4. Un nom de preuve est la promesse exacte de ce qui est mesuré.
5. Une garde de sécurité est indépendante de l'état courant.

Et la discipline de rapport, toujours : preuve d'exécution (pas d'existence) ·
`software_verdict` uniquement depuis des reçus d'oracle · `claim_verdict: NO_CLAIM_ALLOWED`.
