# `_V1_FIXTURES` — données d'entrée de tests, importées de V1

*Migrées le 2026-09-05 (GO Pierre). Source : `C:\TACTICAL_CHESS_STUDIO` (V1, lecture seule),
HEAD `58095ba9`. 565 fichiers, 7,2 Mo.*

## Ce que c'est, et surtout ce que ce n'est pas

Ces fichiers sont des **artefacts de runs et de jeux produits par V1**, conservés ici parce que
33 tests de la chaîne les lisent comme DONNÉES D'ENTRÉE (21 à la migration, +12 le 2026-09-05
sous GO Pierre, commit `80b6847`). Ce ne sont **pas** des preuves de V2, et
ils ne doivent jamais être comptés comme telles : aucun run V2 ne les a produits, aucun verdict V2
ne s'appuie dessus.

C'est la raison du dossier dédié. La migration `2769dc8` n'avait pas emporté ces runs ; les tests
qui les lisaient pointaient donc sur `EVIDENCE/runs/<projet>` et `GAMES/<jeu>`, où ils auraient été
mêlés aux preuves et aux jeux réels de V2.

## Pourquoi ils manquaient, et ce que ça coûtait

Les 21 tests concernés échouaient tous sur `FileNotFoundError` — **jamais sur une assertion de
comportement**. Le code de la chaîne n'était pas cassé : il n'était plus VÉRIFIÉ sur ces points.
La couverture perdue portait sur des règles réelles :

| fixture | ce qui redevient vérifié |
|---|---|
| `runs/kitten_clicker/tasks.json` | boucle joueur obligatoire (s9), sujet `player` (s1), assemblage obligatoire |
| `runs/kitten_clicker/_run9_20260823a/` | porte des sources GM du prisme |
| `runs/p1_alpha/` · `runs/p1_beta/` | locus R3, gel et théâtre, détection de structure normative ; micro-re-déclaration C2 (`test_micro_redeclaration`, ré-ancré `80b6847`) |
| `runs/p2_beta/artifacts/s0-contrat.txt` | sélection du VRAI charter quand la sortie s0 porte deux blocs |
| `runs/pong_r2_ref/rapport_redteam_code.md` | lecture d'un rapport red-team historique sans crash |
| `runs/pong_r2_ref/evidence/mutation_pong_r2.json` | périmètre du gate mutation par catégorie (U-2) : compteurs `system` / `system.adapter` séparés, score testable ≠ agrégat — instantané figé, sceau non re-vérifié (`test_mutation_scope_categories`, ré-ancré `80b6847`) |
| `GAMES/collect_runner_*` · `GAMES/survival_arena_*` | garde structurelle du harnais e2e |

`test_e2e_harness_acceptance` porte une sentinelle anti-vacuité écrite pour échouer si ces jeux
disparaissent, « au lieu de laisser la suite passer verte sans rien prouver ». Elle a fonctionné
comme prévu pendant toute la migration ; c'est son signal qui a été classé à tort en bruit de fond.

## Règles

- **Lecture seule.** Rien ici n'est régénérable : ces runs ne seront pas rejoués. Un test qui aurait
  besoin d'écrire copie d'abord vers son `tmp_path` (patron déjà utilisé par `test_r3_locus`).
- **Ne pas déplacer, ne pas renommer** : dix fichiers de test référencent ces chemins (mesuré
  2026-09-05, HEAD `80b6847` : `grep -l _V1_FIXTURES forge/tests/*.py`).
- **Non migré, décision HumanGate en attente** : `runs/pacman-v3/` (lu par
  `test_manifest_lesson_promotion`) et le monolithe `forge_error_journal.jsonl` (lu par
  `test_learning_memory` ×2 — qui, de plus, ne le verraient pas : `conftest.py` redirige le
  journal pour tout module). Aucune copie V1 ne se fait sans GO explicite.
- **Ne pas compter comme preuve V2.** Toute lecture d'inventaire des preuves doit exclure ce dossier.
- **Périmètre strict** : seul le nécessaire a été copié. `kitten_clicker` pèse 18 Mo dans V1, mais
  seuls `tasks.json` et `_run9_20260823a/` sont lus — le reste n'a pas été importé.

## Limite de l'isolement — découverte en migrant, pas anticipée

L'isolement ne vaut que là où **le TEST** résout le chemin. Deux briefs ont dû rester à
l'emplacement canonique `EVIDENCE/briefs/p1_alpha/` et `p1_beta/`, au milieu des briefs V2 :
ils sont lus par du **code de production** (`run_real._read_project_brief_text` ->
`project_brief_path(project)`), qui ne connaît que `EVIDENCE/briefs/<projet>`. Les déplacer aurait
demandé de tordre la production pour un test — refusé.

Compensation : chacun porte un `PROVENANCE_V1.md` qui dit son origine et qu'aucun run V2 ne
s'appuie dessus. Tout inventaire des projets réels du studio doit les exclure.
