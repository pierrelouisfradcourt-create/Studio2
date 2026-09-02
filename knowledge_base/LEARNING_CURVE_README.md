# knowledge_base/learning_curve.jsonl — la courbe d'apprentissage du studio

> **Pourquoi ce fichier vit ici et pas dans `lab/forge_evidence/`** — le plan le logeait
> initialement là-bas. C'était une erreur d'emplacement : `lab/forge_evidence/` est ignoré
> en bloc par `.gitignore`, parce qu'il contient les preuves **d'un run**, délibérément
> jetables. La courbe d'apprentissage est exactement l'inverse : elle est **cumulative**,
> elle survit aux runs, et elle est le livrable réel du curriculum. Elle appartient donc
> à la connaissance durable du studio, qui est versionnée.

## learning_curve.jsonl

Une ligne JSON par **sujet** forgé, ajoutée par `scripts/forge/learning_metrics.mjs`
(`recordLearning`). Chaque ligne identifie son sujet et porte trois métriques.

### Le sujet : `subject: {type, id}` (LEARNING_SUBJECT_MODEL_V1, ratifié Pierre 2026-07-26)

`brick_id` (seule unité au lancement de l'instrumentation) est devenu un **sujet typé** :
`subject: {type, id}` avec `type` ∈ `{brick, game}` — une énumération contrainte, jamais un
champ libre. Raison : la courbe était indexée par brique (`knowledge_base/systems/`, issues
du pipeline d'ingestion KB) alors que **tous les runs Forge produisent un jeu**, pas une
brique — le backfill sur les 7 runs archivés produisait 0 ligne. Un jeu n'est pas une brique
(une brique est une capacité réutilisable, un jeu est un produit assemblé) : ce module ne
crée ni ne promeut jamais d'entrée dans `knowledge_base/catalog.json`.

**Rétro-compatibilité** : par **normalisation à la lecture**, jamais en réécrivant une ligne
existante. La ligne historique (`sys-grid-nav-m01`, ci-dessous) ne porte que `brick_id` —
elle n'est jamais convertie sur disque. Tout lecteur doit passer par
`normalizeSubject(record)` (`scripts/forge/learning_metrics.mjs`), qui normalise `{brick_id}`
en `{type:'brick', id:brick_id}` et valide `{subject:{type,id}}` tel quel. Même patron déjà
établi dans ce dépôt : `hook_guard.marker_key` (marqueur historique 2-champs -> triplet) et
`studio_link.premortem` (entrées de journal sans `resolution`/`status`).

- `reuse_ratio` — mesuré par `scripts/forge/reuse_ratio.mjs` (combien de la logique du
  jeu vient de `knowledge_base/` plutôt que d'être écrite de zéro).
- `oracle_iterations` — nombre de passes d'oracle nécessaires avant le vert (rouge → correction
  → rouge → correction → ... → vert). Compte les passes réellement exécutées, pas une estimation.
- `joust_delta` — écart mesuré face à une implémentation dérivée de l'état de l'art dans une
  joute (`/joust`), ou `null` si aucune comparaison n'a eu lieu. Quand `joust_delta` est `null`,
  la ligne porte `no_comparison: true` : c'est un fait à consigner, pas une erreur à masquer.

### Limite obligatoire (spec §10) — à lire avant toute lecture de ce fichier

**Sur une seule mécanique, ces trois nombres n'ont aucune valeur statistique.** Ils
établissent une ligne de base et prouvent que l'instrumentation enregistre réellement —
rien de plus. Une série d'un seul point ne permet de déduire ni tendance, ni progrès,
ni régression. **Aucune conclusion sur l'apprentissage de la Forge n'est tirée à l'étape 0**,
et aucune ne doit être écrite tant que la courbe ne comporte pas plusieurs briques
indépendantes forgées dans des conditions comparables.

La première ligne (`sys-grid-nav-m01`) est cette ligne de base : elle prouve que
`buildRecord`/`recordLearning` fonctionnent et que la mesure a été prise honnêtement
(voir `.superpowers/sdd/task-12-report.md` pour le détail de son calcul), pas que la
Forge « apprend ».

## Statut — 2026-07-30 (CV-15, audit lot KB)

**journal-only.** La chaîne d'écriture est complète et câblée : le driver Forge appelle
`scripts/forge/learning_hook.py`, qui appelle `scripts/forge/learning_metrics.mjs`
(`recordLearning`) — 9 lignes réelles dans `knowledge_base/learning_curve.jsonl` à cette
date. **Aucun lecteur décisionnel n'existe.** Les seuls lecteurs actuels sont le backfill
(reconstruction rétroactive des lignes historiques) et les tests unitaires du module —
personne ne lit ce fichier pour décider quoi que ce soit dans une session Forge ou un
rapport de campagne.

Ce statut est **le choix par défaut en attente de la décision D-i de Pierre**, pas une
conclusion : soit un lecteur de rapport de campagne est créé plus tard (agrégation
multi-sujets, tendances, comparaison de runs), soit ce statut journal-only devient
définitif et le fichier reste une trace cumulative sans consommateur — les deux issues
sont acceptables, aucune n'est présumée ici.

**Risque de confusion à ne pas commettre** : `knowledge_base/learning_curve.jsonl` et
`lab/reports/lessons.jsonl` sont deux fichiers **distincts**, à ne jamais fusionner ni
confondre dans un audit ou une proposition de câblage :
- `knowledge_base/learning_curve.jsonl` — **événements de courbe** : trois métriques
  numériques par sujet forgé (`reuse_ratio`, `oracle_iterations`, `joust_delta`), pas de
  jugement, pas de statut de maturité.
- `lab/reports/lessons.jsonl` — **leçons à statut** : un tout autre schéma, orienté
  narration/décision (une leçon a un statut, pas un sujet typé `{type, id}`).

Un lecteur qui voudrait produire un "rapport de campagne" devra choisir explicitement
sa ou ses sources — le mélanger silencieusement avec `lessons.jsonl` produirait un
rapport qui prétend mesurer une chose (progrès mesuré) en s'appuyant en partie sur une
autre (jugement narratif).
