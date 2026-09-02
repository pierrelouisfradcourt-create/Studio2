# Context Loop V1.1 — Freshness Layer (addendum à CONTEXT_LOOP_V1_PROPOSAL.md)

- **Statut** : PROPOSED (architecture) · arbitrage GO/ATTENTE **fourni par Pierre dans la mission du 2026-07-25** et consolidé ici
- **Auteur** : Fable (Architecte du contexte agentique) · **Base factuelle** : audit CONTEXT_BUDGET (lecture seule, ce jour) + audits 24-25/07
- **Règle** : aucun code, aucune modification runtime — architecture et décision uniquement.

## 1. CONTEXT_BUDGET_STATUS (Phase 1.1 — faits, contre-vérifiés)

| Élément | Statut | Preuve |
|---|---|---|
| Modèle utilisé par étape | IMPLEMENTED | roles.yaml → resolve_runtime → DispatchRecord.model + state.json detail.model (driver.py:329) |
| Fenêtre max par modèle | NOT_FOUND | grep `context_window` vide sur tout scripts/forge/ — aucune table nulle part |
| Tokens injectés au bootstrap (pré-envoi) | NOT_FOUND | aucun len(prompt)/estimation avant subprocess (run_real.py:504-527) |
| Tokens mesurés post-appel | PARTIAL | run_real.py:301-302 : `input_tokens + output_tokens` **sommés en un entier** — ventilation et cache perdus ; persisté state.json + telemetry |
| Taille artefacts injectés | PARTIAL | 15 000 car/artefact (UPSTREAM_MAX_CHARS, testé) ; pré-mortem borné en nombre (5+5) mais pas en taille ; **prompt total sans plafond** (s6 : jusqu'à 3×15k + contrat + pré-mortem) |
| Historique conversation | NOT_FOUND (par conception) | `claude -p` one-shot, pas de `-c/--continue` ; retry/escalade = prompt reconstruit de zéro, carry-over uniquement via pré-mortem texte |
| Marge avant saturation | NOT_FOUND | rien ne combine fenêtre max (inexistante) et injecté (mesuré après coup) |

Anomalie relevée au passage : driver.py:345 passe `reviewer` (runner effectif, ex. « claude-sonnet-5 (escalade 1) ») au champ
`model` de la télémétrie — exact en pratique, mais champ mal nommé ; à ranger avec la règle « intention ≠ exécution » (deux
usages, deux champs) lors d'un futur patch.

## 2. CONTEXT FRESHNESS — la distinction (Phase 1.2)

**Découverte structurante** : le chemin driver étant one-shot à contexte vierge, la « fraîcheur cognitive » intra-session
(fenêtre qui sature en cours de conversation) **n'existe pas sur ce chemin**. Elle se réduit à deux choses réelles :

- **Source Freshness** — les sources injectées sont-elles encore représentatives du projet ? (c'est la dérive wiremap
  14/07→18/07 constatée). Signaux DISPONIBLES aujourd'hui, tous applicatifs (aucun mtime consulté par le code) :
  `steps.<etape>.ts` (state.json) · `created_ts/updated_ts` du run · `ts` dispatch_audit/telemetry ·
  `ts+date` error_journal · `ts` + `git_head` du verdict signé · demain : sha256 du Context Manifest (V1 étape 1).
- **Budget Freshness** (remplace « fraîcheur cognitive » côté one-shot) — le prompt assemblé tient-il dans la fenêtre du
  modèle résolu, avec quelle marge ? Aujourd'hui : INCALCULABLE (pas de table de fenêtres, pas de mesure pré-envoi,
  prompt total non plafonné). Risque réel : un prompt qui déborde est tronqué/refusé côté API sans que la Forge le sache.

La « fenêtre cognitive encore valide » ne redeviendra une dimension propre que si un futur chemin multi-tour apparaît
(sessions continues) — à ce moment-là seulement, l'âge de la fenêtre et sa saturation deviennent des signaux distincts.

## 3. Score advisory de fraîcheur (proposition, jamais bloquant en V1.1)

Calculé par `context_check.mjs` (artefact séparé — voir §4), 100 % déterministe, entrées observables :

| Score | Condition (première qui matche, de haut en bas) |
|---|---|
| `REQUIRES_REFRESH` | ≥1 source **consommée par l'étape** (table CONTEXT_CONSUMERS) a changé de sha256 depuis le manifest de la dernière activation |
| `STALE_CRITICAL` | ≥1 source critique du projet (wiremap, contrat de l'étape, Game Bible, invariants) a changé — même si l'étape ne la consomme pas directement ; OU nouvelles décisions Pierre non reflétées (`ts` pending_review_decisions > dernière activation) |
| `STALE_WARNING` | commits touchant le projet depuis la dernière activation ; OU nouvelles entrées pré-mortem ; OU âge > seuil (défaut proposé : 72 h — la pause shmup_slice de 4 jours aurait sonné) |
| `FRESH` | rien de ce qui précède |

Plus un volet budget dans le même rapport : `CONTEXT_BUDGET: OK | UNKNOWN_WINDOW | OVERFLOW_RISK` —
estimation chars/4 (assumée ±20 %, honnêtement étiquetée « estimation ») contre une table statique
`MODEL_WINDOWS` à créer (3 modèles Claude + Qwen : 5 lignes). `UNKNOWN_WINDOW` si le modèle n'y est pas — jamais inventé.

## 4. Où s'intègre la couche (Phase 1.3 — schéma complété)

```
Bootstrap → Context Manifest (prepare_dispatch : photo + hashes + prompt_sha256 + budget estimé)
          → Projet évolue
          → Context Diff        (context_check.mjs — artefact séparé, advisory)
          → Freshness Check     (même CLI, score §3)
          → Impact Analysis     (V1.1 : ALERTE simple « source X changée » ; graphe auto = ATTENTE)
          → Refresh             (V1.1 : RECOMMANDATION humaine dans le rapport ; auto = ATTENTE)
```

Décision d'intégration : **prepare_dispatch** écrit la photo (seul point complet) · **artefact séparé** calcule
diff+freshness (pas le driver — rien ne change dans l'exécution en V1.1) · **verify_run** re-vérifie la signature du
manifest comme une évidence de plus (extension naturelle de R1). Le driver n'est PAS touché tant que le refresh est en ATTENTE.

## 5. Arbitrage consolidé (fourni par Pierre, mission 2026-07-25)

**GO (fondations avant run réel)** : ① Context Manifest — photo prouvable du contexte initial, sans quoi aucune erreur
n'est explicable après coup ; ② prompt_sha256 — « voici exactement ce qui lui a été fourni » (pas ce qu'il a compris) ;
③ Integrity Check advisory — mesurer les vrais problèmes avant de créer des gates.

**ATTENTE (après observation)** : ① Refresh automatique — d'abord comprendre quels changements méritent un refresh
(V1 = recommandation humaine), sinon explosion tokens et agents interrompus ; ② Transcript obligatoire — la couche la
plus coûteuse (fourni vs lu vs utilisé), après stabilisation du manifest ; ③ Impact automatique — ne pas automatiser
une mauvaise compréhension du graphe : d'abord « wiremap changée = alerte », le mapping s9/s10/s11 auto viendra quand
la carte des consommateurs aura été validée par l'observation.

## 6. Risques d'implémentation prématurée (ce que l'ATTENTE évite)

- Refresh auto sans données : sur-refresh systématique (chaque commit toucherait quelque chose), coût tokens,
  interruptions — l'inverse de « le bon contexte au bon moment ».
- Impact auto sur graphe non validé : faux sentiment de couverture (« s9 non listé ⇒ non impacté » alors que la table
  est incomplète) — le mode de panne « déclaré ≠ exécuté » réintroduit au cœur du système censé le combattre.
- Transcript précoce : stockage lourd + dépendance au format CLI avant d'avoir prouvé que le manifest (couche
  « fourni ») répond déjà à 80 % des questions d'audit.
- Gate dur immédiat : bloquer des runs sur des seuils jamais calibrés (le 72 h du §3 est un défaut à observer, pas une vérité).

## 7. Proposition minimale avant run réel (périmètre GO exact)

1. Manifest signé à `prepare_dispatch` (sources + sha256 + prompt_sha256 + git_head + budget estimé + figement pré-mortem).
2. Table statique `MODEL_WINDOWS` (5 lignes) + estimation chars/4 dans le manifest — donne enfin une marge, étiquetée estimation.
3. `context_check.mjs` : diff vs dernier manifest + score §3 + volet budget + recommandations de refresh (texte, humain).
4. `verify_run` étend sa vérification au manifest (signature + cohérence).
Rien d'autre. Le driver, les prompts et le comportement agent restent inchangés.
