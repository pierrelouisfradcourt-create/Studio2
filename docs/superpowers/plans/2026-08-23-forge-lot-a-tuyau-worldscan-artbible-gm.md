# Lot A — TUYAU : World Scan → Story Bible → Art Bible → GM, avec preuve de chargement ET de consommation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD strict, fixtures RÉELLES (run 9 archivé
> `lab/forge_runs/kitten_clicker/_run9_20260823a/`). Jamais de commit par un sous-agent ; un commit de clôture (gate Pierre).
> **Aucun gameplay Kitten Clicker, aucune station nouvelle, aucun oracle LLM.** Lot B (GM = Game Master), C (calibration),
> D (fuites de mesure), E (run 10) viennent APRÈS et ne sont pas ouverts ici.

*Date : 2026-08-23 · Source : GO Pierre « Lot A — Tuyau » après les audits `docs/audit/2026-08-23-kitten-clicker-*.md`.*

**Goal :** que le GM (s2.7) reçoive World Scan + Story Bible + Art Bible, que l'Art Bible (s2.5) soit produite AVANT lui et
héritée du World Scan + Story Bible (plus du Prisme), et qu'un run prouve mécaniquement (1) les sources chargées et (2) ce que
le GM en a consommé.

**Mesuré aujourd'hui (run 9)** : ordre `s2 → s2.6 → s2.7 → s1 → s2.5` ; `_UPSTREAM_BY_STEP["s2.7-gm-worldscan"] =
("artifacts/s2-worldscan.txt",)` ; s2.5 sans injection amont (ancre = `product_snapshot.md` du Prisme) ; le manifeste de dispatch
enregistre déjà `sources[]` `{path, role: upstream, sha256, exists}` → la preuve de CHARGEMENT existe par construction dès que
l'injection est câblée ; aucune preuve de CONSOMMATION n'existe.

## Cible
```text
s0 → s2 World Scan → s2.6 Story Bible → s2.5 Art Bible → s2.7 GM → s1 Prisme → s3 → s4 → s5 → s6 → s9 → s10* → s11 → s12
injections : s2.5 ← (charter.yaml, s2-worldscan.txt, s2.6-story-bible.txt)
             s2.7 ← (s2-worldscan.txt, s2.6-story-bible.txt, art_bible.md, asset_requests.json)
preuve 1 (chargement)   : manifeste de dispatch s2.7 : sources role=upstream exists=true pour les 4 fichiers (déjà écrit par
                          context_manifest ; test sur fixture)
preuve 2 (consommation) : gm_worldscan.json porte `sources_consumed: {worldscan: [adresses], story_bible: [adresses],
                          art_bible: [sections]}` ; chaque adresse RÉSOUT dans l'artefact correspondant ; ≥ 1 par source ;
                          validé à la matérialisation (`_validate_gm_worldscan`, même régime que `advisory` : non
                          matérialisable = étape non OK). Déterministe, sans LLM.
```

### T1 — Ordre et injections (code)
**Files :** `scripts/forge/dispatch.py` (profils `full_godot_content` ET `full_godot_narratif` : s2.5 entre s2.6 et s2.7 —
narratif n'a pas s2.5 aujourd'hui ; ne l'ajoute QUE si le profil le contient déjà, sinon ne touche pas narratif),
`scripts/forge/run_real.py` `_UPSTREAM_BY_STEP`, `scripts/forge/context_manifest.py` (copie identique — test d'égalité existant),
tests `test_profile_full_godot_content.py`, `test_loop_json_upstream.py`, `test_context_manifest*.py` (+ nouveau
`test_lot_a_tuyau_artbible_gm.py`).
- `s2.5-artbible` gagne une entrée `("charter.yaml", "artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt")`.
- `s2.7-gm-worldscan` devient `("artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt", "art_bible.md",
  "asset_requests.json")`.
- s1/s3/s9 inchangés (l'art bible y arrive déjà pour s3/s9).
- Tests : ordre du profil ; égalité des deux tables ; sur fixture run 9 (`art_bible.md`, `asset_requests.json`, artefacts) la
  section amont construite pour s2.7 contient les 4 fichiers ; dry-run 17 étapes (même nombre, ordre changé).

### T2 — Contrats s2.5 et s2.7 (texte) + preuve de consommation (code)
**Files :** `scripts/forge/contracts/s2.5-artbible.yaml`, `scripts/forge/contracts/s2.7-gm-worldscan.yaml`,
`scripts/forge/run_real.py` (`_validate_gm_worldscan`), `scripts/forge/static_oracles.py` si `check_gm_worldscan` doit accepter la
clé, tests `test_materialize_artifact_schema_aware.py` / nouveau test.
- s2.5 : `mandatory_read` perd `product_snapshot.md` (qui n'existe plus à ce moment) et gagne les trois entrées injectées ; son
  objectif dit : HÉRITÉ du World Scan (conventions visuelles/sonores, attentes joueur, boucles observées — `retention_answer`) et
  de la Story Bible (monde, personnages, lieux, objets) ; DÉCIDÉ par l'artiste (style, règles d'assets, silhouettes, règles
  d'affordance, lisibilité, états des personnages, variantes, contraintes connues). Sections de `art_bible.md` nommées et stables :
  `## heritage_worldscan`, `## heritage_story_bible`, `## visual_language`, `## affordance_rules`, `## character_states`,
  `## ui_readability`, `## world_constraints`, `## asset_rules` (ancres pour `sources_consumed.art_bible`).
- s2.7 : `mandatory_read` nomme les 4 sources injectées ; **sortie** : le bloc JSON gagne `sources_consumed` (forme ci-dessus) —
  adresses `worldscan:games[i].<clé>` / `story_bible:<section>[.<clé>]` / `art_bible:<section>` ; règle : ne lister que ce qui a
  RÉELLEMENT servi (une adresse citée sans usage est une fausse preuve — red-team advisory). Le reste du contrat s2.7 (scan de
  genre, `out_of_scope` « concevoir le jeu ») est INCHANGÉ — le rôle Game Master = Lot B.
- `_validate_gm_worldscan` : `sources_consumed` obligatoire, dict à 3 clés, chaque liste non vide, chaque adresse résout dans
  l'artefact (worldscan.json / story_bible.json du run_dir ; `art_bible.md` : un `## <section>` existant) ; message d'erreur
  nommant l'adresse fautive. Fixture : `gm_worldscan.json` du run 9 → refusé « sources_consumed absent » ; fixture synthétique
  valide → accepté ; adresse inexistante → refusée.

### T3 — Confrontation Fable + commit + run de tuyau
- Node + pytest ciblés, dry-run des 2 profils, `git diff --check`.
- **Run de preuve du tuyau** (Lot A, E n'est pas ouvert) : profil `full_godot_content` **limité** ? Non : pas de profil nouveau.
  Lancer `kitten_clicker-20260823c` et l'**arrêter après s2.7** n'est pas propre (BLOCKED). Alternative retenue : laisser le run
  entier (≈ 60 $) ? NON — Pierre n'a pas demandé le run 10 (Lot E). Décision : la preuve du tuyau se fait **par tests sur fixture**
  (manifeste + validateur) ; le premier run réel du tuyau sera le run 10 après B/C/D. À confirmer par Pierre.

## Hors périmètre
Rôle Game Master de s2.7 (Lot B) · calibration Kitten Clicker (Lot C) · `replay_ref`, tri alphabétique, `design_intent` (Lot D) ·
run 10 (Lot E) · gates historiques · `check_wiremap_contract`.
