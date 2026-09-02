# Protocole V1 — Knowledge Resolver (expérience falsifiable)

- **Statut : PROPOSED — en attente gate Pierre avant toute construction.**
- Date : 2026-07-20 · Auteur : orchestrateur Fable · Gabarit : cycle d'expérience maison (cf. P1_1_PROTOCOL.md — métrique posée avant, sonde-contrôle, conclusion limitée, jamais de tuning post-hoc).
- Amont : `docs/audit/DECISION_LAYER_AUDIT_2026-07-19.md` (trou T1 contre-vérifié) + dialogue d'architecture Fable×Pierre du 2026-07-20.

## 1. Cadre ratifié (Pierre, 2026-07-20 — verbatim d'intention)

- **Rasoir à 4 conditions** pour toute auto-promotion : produit **déterministe** + **recomputable** depuis ses entrées + **append-only / non destructif** + **non liant** (pas de la doctrine).
- **Score = tri advisory** sur features déterministes (comptages, dates, reproductions, citations) — **jamais juge** de promotion. Aucun seuil ne promeut.
- Modes de promotion : `automatic` · `oracle` · `human` — **`consensus` supprimé**. **HumanGate = le nom de l'acte humain** ; Promotion Policy = la règle de routage.
- **Ordre incrémental imposé** : (1) Resolver V1 — lecture, trace, pending queue, **zéro écriture** → (2) validation de la valeur sur plusieurs runs → (3) Promotion Policies → (4) automatisation de leur application → (5) Policy Compiler **seulement si la maintenance le justifie**.
- **Règle anti-couches** : aucun nouveau composant s'il ne remplace pas explicitement plusieurs composants existants. Priorité : consolidation et preuve.

## 2. Hypothèse (falsifiable)

**H1** — Unifier et rendre visibles les trois canaux de lecture EXISTANTS (pré-mortem · search-first `knowledge_base/` · `mandatory_read`/knowledge packets) via une trace par run, et donner enfin un **lecteur** aux files de propositions dormantes, produit : (a) une réutilisation de connaissance démontrable par run, (b) le traitement effectif des propositions (aujourd'hui : 0 % lues), (c) pour un coût marginal ≤ 10 min/run — **sans aucune écriture dans la vérité permanente**.

Si H1 est fausse, on s'arrête à la V1 et on n'aura perdu que quelques jours — c'est le but du protocole.

## 3. Composants V1 (trois pièces, consolidation pure)

Conformité règle anti-couches : la V1 ne crée aucun magasin ; elle **unifie** 3 lecteurs qui s'ignorent (contrat de trace) et **fusionne en une vue** 3 files sans lecteur (`forge_ledger_proposals.jsonl`, `forge_project_proposals.jsonl`, `error_proposals.jsonl`).

1. **`knowledge_trace.json`** — déposé dans `lab/forge_runs/<run>/` par l'orchestrateur au moment du run : liste des items réellement servis `{source ∈ {premortem, knowledge_base, mandatory_read/packet}, id/chemin, provenance ∈ {VERIFIED, HUMAN_RATIFIED, ADVISORY, DERIVED, DOCTRINE}, date-de-validité, raison-du-service}`. C'est du **lineage de lecture**, pas un nouveau savoir.
2. **`pending_review`** — outil **read-only** qui agrège les 3 files, calcule les features déterministes brutes (nb de dépôts, âge, run source, reproduction oui/non), trie, **plafonne à 5** l'affichage (compte total toujours affiché — pas de volume caché) et présente pour décision Pierre : Accept / Reject / Postpone. **L'outil n'écrit rien** ; les décisions sont consignées par l'orchestrateur dans l'enregistrement de gate de la session (mécanisme existant).
3. **Rien d'autre.** Explicitement hors V1 : scoring pondéré, distillation, index au-delà des 3 sources codées en dur, détection sémantique de contradiction, tout vectoriel, tout daemon, toute écriture par l'outillage.

## 4. Métriques (posées AVANT — succès = les quatre)

| # | Métrique | Cible | Baseline documentée |
|---|---|---|---|
| M1 | `knowledge_trace.json` présent et référencé par le rapport de run | 3/3 prochains runs Forge | 0 trace n'existe aujourd'hui |
| M2 | ≥ 1 item servi par run ayant **changé une action de façon démontrable** (réf citée dans le rapport — ex. pré-mortem évitant une erreur connue, brique KB réutilisée) | ≥ 1 par run, 3/3 | canal prouvé une fois (premortem i2) mais jamais tracé |
| M3 | File de propositions traitée | 100 % des items présentés décidés (A/R/P) en ≤ 1 session, revue ≤ 5 min | 8+ dépôts, 0 % lus depuis des semaines |
| M4 | Coût orchestrateur | ≤ 10 min par run | — |

## 5. Sondes de falsification

- **Anti-théâtre (la plus importante)** : chaque item de la trace doit être **recoupable** avec un artefact du run (extrait de prompt de contrat, pré-mortem injecté, brique importée). Un item tracé mais introuvable dans les artefacts = FAUX POSITIF de trace → M1 invalide. Vérification par agent indépendant.
- **Contrôle négatif** : la baseline historique (runs i1/i2 : aucune trace, files jamais lues) sert de témoin — pas de sonde-contrôle dédiée à fabriquer.
- **Anti-postpone** : un item Postpone reçoit une date ; à échéance il revient en tête de file. Une file qui grossit en silence = échec de M3.

## 6. Substrat expérimental — non-mélange avec les jeux

La V1 s'attache aux runs Forge **qui auraient lieu de toute façon** (prochain incrément auto_battler quand Pierre le décidera, ou tout run patch/micro). Elle **ne force aucun run de jeu** et n'ajoute aucune décision produit — conformité à la directive « ne pas mélanger jeux et refonte studio ». Si aucun run naturel ne survient, un run sonde sur fixture (tradition P1.1) est admissible en dernier recours, décision Pierre.

## 7. Répartition et estimation

- **Sonnet** : construit les 2 outils read-only (petits, testés — comportements évidents : fichier absent, JSONL corrompu, file vide, encodage UTF-8/CRLF) + leurs tests. Estimation : 1-2 sessions.
- **Opus** : uniquement si un arbitrage de schéma surgit (format de trace, taxonomie).
- **Fable** : revue des livrables, contre-vérification anti-théâtre, tenue des métriques, préparation de la conclusion pour gate.
- **Pierre** : gate de ce protocole · décisions A/R/P en session · gate de conclusion.

## 8. Conclusion (limitée, à l'avance)

- **SUCCESS** (M1-M4 atteints) → autorise l'étape 3 de l'ordre ratifié (table des Promotion Policies, préparée alors pour gate). Ne prouve PAS que le résolveur doit devenir le cœur du studio — seulement que la boucle fermée a de la valeur mesurable.
- **FAIL / partiel** → conclusion limitée écrite, pas de tuning post-hoc ; on corrige le protocole (gate) ou on s'arrête.
- Dans tous les cas : aucune écriture durable n'aura eu lieu hors gates.

## 9. Risques

- Théâtre de trace (mitigé §5) · coût orchestrateur sous-estimé (M4 le mesure) · plafond de file masquant le volume (compte total affiché) · tentation d'étendre la V1 en cours de route (interdit par ce protocole — toute extension = nouvelle gate).

---
software_verdict : s'appliquera aux outils V1 une fois construits et testés, pas à ce document.
evidence_verdict : MECHANICAL_VALIDATION_ONLY
claim_verdict : NO_CLAIM_ALLOWED
