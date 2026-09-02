# Audit Forge — Kernel / Workflow / Mémoire / Branchements

- **Date** : 2026-07-24
- **Source** : mission Pierre « Audit et amélioration continue de la Forge » (Phase 1 — audit initial, lecture seule)
- **Méthode** : 4 explorations Sonnet parallèles (Kernel, Workflow, Mémoire, Branchements), chaque rapport
  contre-vérifié par l'orchestrateur Fable par observation directe (greps/lectures indépendants) avant intégration.
  Deux claims de sous-agents ont été **corrigés** par la contre-vérification (voir §3.6, §3.7) — la boucle
  anti-« agents qui se confirment mutuellement » a fonctionné.
- **Verdicts** : `software_verdict: OK` (outillage d'audit exécuté, 74 tests kernel relancés verts) ·
  `evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED`

---

## 1. État réel du Studio (par surface)

| Surface | Composant | État |
|---|---|---|
| Kernel | Porte contrat (`contract.py` + `prepare_dispatch` + hook `pretool_forge_guard`) | IMPLEMENTED + TESTED (74 tests verts relancés) |
| Kernel | Oracles déterministes non-LLM (`oracle.py`, `static_oracles.py` — 20 fonctions AST/regex) | IMPLEMENTED + TESTED |
| Kernel | Verdict signé HMAC (`verdict.py`) — claim figé `NO_CLAIM_ALLOWED`, red-team jamais juge | IMPLEMENTED + TESTED |
| Kernel | Re-vérification `verify_run.py` | IMPLEMENTED mais **PASSIVE** — jamais appelée par `driver.py`, invocation manuelle prescrite en prose (skill.md:206) |
| Kernel | Interdiction commit/push sous-agent | DOCUMENTED_ONLY — `settings.json` ne deny que les git destructifs |
| Kernel | HumanGate « Pierre décide » | DOCUMENTED_ONLY (procédural) — bon signal : `decision` du verdict ne vaut jamais MERGE |
| Workflow | Driver déterministe (`driver.py` + `run_real.py`) | IMPLEMENTED + TESTED mais **adoption 5/21 runs** (driver_smoke + famille shmup_slice) |
| Workflow | Orchestration prose (skill.md) | ACTIVE DE FAIT — 16/21 runs, y compris card_engine (20/07, postérieur au driver) |
| Workflow | Red-team indépendant Qwen (s11) | PARTIELLE — `verdict.json` shmup : `redteam_ran:false`, fallback claude-blind ; le verdict le déclare honnêtement |
| Workflow | Étapes s7/s8 | NOT_FOUND — jamais nommées nulle part (trou de numérotation, intention UNKNOWN) |
| Mémoire | Boucle `error_journal ↔ premortem` (driver.py:391-415) | IMPLEMENTED + CONNECTÉE — **seule boucle mémoire fermée automatiquement** |
| Mémoire | Boucle `dispatch_audit/telemetry ↔ hook_guard` | IMPLEMENTED + CONNECTÉE |
| Mémoire | KB briques consommées par les jeux | VIVANTE mais MARGINALE — 1 jeu sur ~18 importe réellement (kb_tactics, reuse_ratio 0.33) |
| Mémoire | `search.mjs` consulté avant build (s9 §2bis) | DOCUMENTED_ONLY — consigne prompt, capteur advisory, jamais gating |
| Mémoire | `PROJECT_BIBLE.md` / `propose_bible_entry` | MORTE — 0 fichier, 0 appel hors tests, s0 sans outil Read sur le chemin run_real.py |
| Mémoire | `forge_{ledger,project}_proposals.jsonl` (5+5 entrées) | PARTIELLE — lues par `pending_review.mjs` (T1 corrigé 23/07), mais la sortie n'a aucun consommateur aval |
| Mémoire | `pending_review_decisions.jsonl` (décisions Pierre 20/07) | ÉCRITE_JAMAIS_APPLIQUÉE — écrite à la main en session, aucun code ne l'applique (promotion ledger 100 % manuelle) |
| Mémoire | `knowledge_trace.mjs` (Resolver V1) | IMPLEMENTED + CONNECTÉE (bloquante dans verify_run R3) **mais statut déclaré PROPOSED** — code en prod sans ratification tracée |
| Mémoire | `studio_brain/` lu par du code vivant | DOCUMENTED_ONLY — seul parseur réel : autopilot.py (lane gelée) |
| Branchements | Capteurs visuels (visual_mechanical 26 fichiers, dominance 72 Ko) + contrat s10d | PASSIVE — s10d hors ORDER/PROFILES, aucun capteur relié au verdict signé |
| Branchements | `.claude/agents/*.md` (15 personas) ↔ pipeline Forge | MANQUANTE — roles.yaml ne mappe que des modèles ; personas utilisés par d'autres skills |
| Branchements | `studio_selfaudit.mjs` | IMPLEMENTED mais **NEUTRALISÉ** — lancé au pre-commit avec `|| true` + sortie jetée : ne peut ni bloquer ni être lu |
| Repo | 203 fichiers non commités (dont lab/forge_runs, forge_sensors, fixtures P1) + 8 worktrees | BLOCKED (risque) — preuves d'oracle en zone volatile, mode de panne déjà vécu (incident checkout 18/07) |

## 2. Carte des branchements (synthèse)

**CONNECTÉES (prouvées par call-site + trace disque)** :
`dispatch → driver → static_oracles → verdict(HMAC)` · `driver → studio_link.{record_error,record_fix,premortem,telemetry}` ·
`telemetry/dispatch_audit → hook_guard.check_spawn` · `s5-wiremap → wiremap.json → check_wiremap + mutation_proof` ·
`knowledge_trace.mjs → verify_run (R3, bloquant)` · `proposals.jsonl → pending_review.mjs (lecture)`.

**PARTIELLES** :
`skill.md prose → propose_ledger_entry` (à la main, rien ne force l'appel) · red-team Qwen (fallback claude-blind récurrent) ·
`s9-build-godot` (worktree : preuves rangées dans `knowledge_base/proofs/`, 2e convention non unifiée).

**DOCUMENTÉES UNIQUEMENT** :
`verify_run` post-verdict (prose) · interdiction commit sous-agent · consultation search.mjs · `PROJECT_BIBLE` → s0 ·
`s10d-oracle-visual` (contrat auto-déclaré « manuel »).

**MORTES** :
`propose_bible_entry` (jamais tirée, fichier inexistant) · capteurs visuels → décision · `studio_brain` → code vivant ·
sortie `pending_review` → promotion ledger.

**MANQUANTES** :
`.claude/agents/*.md` → contrats Forge · `verify_run` → driver · décisions Pierre enregistrées → effet mécanique.

## 3. Écarts critiques (croit posséder / possède / fonctionne)

1. **« Le driver remplace la prose »** (docstring driver.py) → réalité : 16/21 runs orchestrés à la main, dont card_engine postérieur au driver. Deux régimes coexistent sans doctrine.
2. **« Red-team indépendant »** → réalité : `redteam_ran:false` sur shmup_slice (LM Studio down → fallback claude-blind). Le verdict le dit honnêtement, mais l'indépendance promise n'existe pas en pratique.
3. **« Oracle visuel »** (26 visual_mechanical.json, capteur dominance, contrat s10d) → réalité : matière produite, zéro branchement au verdict. Le playtest Pierre du 18/07 (« mechanical OK, visually dead ») reste la seule détection réelle.
4. **« Périmètre Forge sous hook fail-closed »** → réalité : fail-closed *seulement si* le marqueur `FORGE_DISPATCH` est présent — et il est auto-apposé par l'orchestrateur, jamais injecté par `_render_prompt`. Un spawn sans marqueur passe (hook_guard.py:68-69). Faille assumée et documentée (ADR-002 §7), mais réelle.
5. **« Verdict signé re-vérifié »** → réalité : `verify_run` jamais appelé par le pipeline exécutable ; dépend de la discipline de l'orchestrateur.
6. **« Auto-audit ALIGNÉ ✅ »** → réalité : 7 chemins filesystem choisis à la main + 3 mtimes ; aucun call-graph ; **correction contre-audit** : il tourne bien au pre-commit mais en `|| true` sortie jetée — surveillance illusoire.
7. **« Décisions Pierre enregistrées »** → réalité : `pending_review_decisions.jsonl` écrit à la main le 20/07 (**correction contre-audit** : origine identifiée, pas UNKNOWN) ; aucun code ne les applique — une décision REJECT du 20/07 n'a mécaniquement rien rejeté.
8. **R9 solvabilité Godot = tautologie** (bloqueur déjà ouvert, hors périmètre de re-preuve ici) — rappelé pour la cohérence de la photographie.

## 4. Améliorations ROI (problème · preuve · solution · coût · impact)

| # | Amélioration | Preuve | Solution | Coût | Impact |
|---|---|---|---|---|---|
| R1 | **Câbler `verify_run` dans `driver.py._run_verdict`** | grep `verify_run` driver.py = vide | appel automatique post-écriture verdict.json, échec ⇒ verdict BLOCKED | ~10 lignes + test | Ferme l'écart §3.5 — la re-vérification devient structurelle |
| R2 | **Injecter `FORGE_DISPATCH:<etape>:<run_id>` dans `contract.py._render_prompt`** | marqueur absent du rendu (contract.py:151-170), auto-apposé à la main | la porte qui rend le prompt appose elle-même le marqueur | ~5 lignes + test | Réduit la brèche §3.4 (le chemin nominal devient auto-marqué) |
| R3 | **Dé-neutraliser le selfaudit au pre-commit** | pre-commit:25 `|| true` + sortie jetée | afficher les findings (advisory, non bloquant au début) + étendre `studio_expectations.json` avec les liaisons mortes du §2 | ~15 min | L'auto-audit détecte enfin ce que cet audit a trouvé à la main |
| R4 | **Appliquer les décisions Pierre** : petit `apply_decisions.mjs` qui lit `pending_review_decisions.jsonl` et marque les propositions traitées (statut dans les jsonl) | §3.7 | boucle décision→effet fermée, propose-only respecté (marquage, pas promotion auto) | ~1 h | Ferme le trou T1-bis identifié le 23/07 |
| R5 | **Doctrine driver vs prose** (décision, pas code) | 5/21 runs driver | trancher : tout run `full` passe par `run_real.py`, la prose reste pour profils dédiés | 0 code | Supprime le double régime §3.1 |
| R6 | **Boucle rapports agents + contre-audit (Phase 2 mission)** | aucune trace de rapports d'agent normalisés dans les runs | format YAML de la mission ajouté comme artefact d'étape (state.json/artifacts), contre-audit = étape advisory | ~½ journée | Donne au studio la matière d'auto-observation qui a manqué à cet audit |

## 5. Décisions humaines nécessaires (arbitrages Pierre)

1. **R5** — le driver devient-il le chemin canonique des runs `full` ?
2. **`knowledge_trace` (Resolver V1)** : ratifier (le code est déjà bloquant en prod) ou débrancher jusqu'à ratification ?
3. **Red-team indépendant** : exiger LM Studio up (gate dur) ou accepter le fallback claude-blind documenté comme régime normal ?
4. **Oracle visuel** : brancher s10d dans un profil dispatch, ou déclarer les capteurs advisory définitifs (et le dire dans les cartes) ?
5. **`propose_bible_entry` / PROJECT_BIBLE** : implémenter réellement ou supprimer le connecteur mort ?
6. **Phase 2 de la mission** (rapports agents + contre-audit) : go/no-go sur la proposition R6, et où la câbler (artefact driver vs champ contrat).
7. **Phase 3** (run Forge observé) : quel prochain run réel sert de terrain d'observation ?
8. **203 fichiers non commités** dont preuves Forge : commit de sauvegarde sur la branche courante ? (gel : aucun push sans go).

---
*Rapports bruts des 4 sous-agents non recopiés (doctrine contexte propre) ; chaque claim intégré ici a été contre-vérifié ou est cité avec sa preuve fichier:ligne d'origine.*
