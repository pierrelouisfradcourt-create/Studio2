# Context Loop V2 — Context Continuity / Core Memory (architecture CONSOLIDÉE)

- **Statut** : CONSOLIDÉ — décisions **D1-D5 ratifiées Pierre 2026-07-25** (retour architecture) ;
  l'implémentation de chaque brique garde son gate propre. §0 intègre les corrections de Pierre.
- **Date** : 2026-07-25 (v2 consolidée le même jour) · **Auteur** : Fable (Architecte du contexte agentique)

---

## 0. Corrections ratifiées Pierre (priment sur le reste du document)

### 0.1 Trois mémoires distinctes — séparation des USAGES, pas seulement compression
Le piège nommé : « résoudre la perte de contexte en ajoutant toujours plus de contexte. » Le modèle final :

```
MÉMOIRE COURTE — CONTINUATION        : checkpoint · prompt de reprise · delta contexte · prochaine action
MÉMOIRE LONGUE — CONNAISSANCE PROJET : PROJECT_BIBLE · Core Memory · Wiremap · décisions ratifiées · invariants
MÉMOIRE FORENSIC — ENQUÊTE           : conversations complètes · traces agent · essais · hypothèses abandonnées
```

**Le checkpoint sert à avancer. La mémoire projet sert à comprendre le système. La conversation complète
sert à enquêter sur les dérives.** La fenêtre complète ne disparaît pas — mais elle n'est JAMAIS le contexte
normal transmis à l'agent suivant. Accès forensic uniquement si : bug incompréhensible · contradiction ·
régression · boucle agentique · besoin d'audit. Chemin d'enquête : Bug → Wiremap → Feature → Agents
intervenus → Checkpoint → Conversation archive.

### 0.2 D1 ratifié — avec séparation stricte (la Bible ne devient jamais un chat géant)
```
PROJECT_BIBLE : vérités validées · architecture stable · décisions ratifiées · invariants
CORE_MEMORY   : checkpoints promus · leçons apprises · erreurs récurrentes · patterns validés
ARCHIVE       : conversations · traces · essais · hypothèses rejetées
```

### 0.3 Pyramide de contexte — principe de design
Le contexte DIMINUE avec la spécialisation : Niveau 0 projet complet → 1 architecture → 2 module →
3 feature → 4 fichier/fonction. La qualité ne vient pas d'un contexte maximal mais d'un contexte
correctement orienté. À appliquer à chaque contrat : un builder de feature (niveau 3) ne reçoit pas le
niveau 0.

### 0.4 Concept directeur ratifié
Objectif ≠ agent à mémoire infinie. Objectif = **continuité de travail vérifiable à travers plusieurs
activations**. Un agent est une activation temporaire d'un rôle dans une organisation : les agents
exécutent · les checkpoints transmettent · la Wiremap structure · la Core Memory capitalise · l'archive
explique les erreurs.

### 0.5 D5 — ordre ratifié (remplace le §4 initial)
0. Run observé (calibration réelle) · 1. Wiremap Navigation (**GO maintenant** — D2 : observation pure,
la Wiremap devient le système de coordonnées de la mémoire) · 2. Context Handoff / Checkpoint (continuité
opérationnelle, D4 GO sur le schéma 9 champs) · 3. Stream-json **sonde uniquement** (D3 : mesurer
fourni→lu→utilisé→influent AVANT d'en faire une contrainte) · 4. Core Memory / PROJECT_BIBLE (promotion
basée sur les observations) · 5. Refresh automatique (après calibration) · 6. Impact graph complet (dernier).

### 0.6 Relation fondamentale : Contexte × Mémoire × Tokens × Qualité
*(principe fondateur, texte Pierre 2026-07-25 — c'est lui qui unifie toutes les briques ; complète la
pyramide du §0.3)*

Le principe fondateur de Context Loop est le suivant :

> **La qualité d'un agent n'augmente pas avec la quantité de contexte, mais avec la pertinence du
> contexte reçu.**

Quatre notions doivent rester distinctes :

```text
Mémoire             = Tout ce que l'organisation sait.
Contexte            = La partie de cette mémoire injectée pour une activation.
Fenêtre de contexte = La limite technique du modèle (budget tokens).
Qualité             = La capacité du modèle à rester focalisé sur son objectif.
```

Ces quatre notions ne doivent jamais être confondues. La mémoire peut croître pendant toute la vie du
projet. Le contexte, lui, doit rester minimal. Autrement dit :

```text
Mémoire ↑ → Sélection → Contexte pertinent → Raisonnement de qualité
```

et non :

```text
Mémoire ↑ → Contexte ↑ → Qualité ↑        (FAUX en pratique)
```

Au-delà d'un certain volume, le modèle passe davantage de temps à filtrer le contexte qu'à résoudre le
problème. On obtient alors deux pathologies opposées :

```text
Contexte insuffisant → dérive · oubli · réinvention
Contexte excessif    → dispersion · perte de focalisation · coût tokens
```

Le rôle de Context Loop est précisément d'éviter ces deux extrêmes.

**Conséquence architecturale.** La mémoire complète du projet ne doit jamais être injectée directement.
Elle doit être transformée progressivement :

```text
Archive → Core Memory → PROJECT_BIBLE → Wiremap → Zone concernée → Prompt de reprise
```

Chaque étape réduit le volume d'information tout en augmentant sa pertinence.

**Conséquence sur la pyramide agentique.** Plus un agent est spécialisé, plus son contexte doit être réduit :

```text
Directeur   vision globale
Architecte  sous-système
Builder     feature
Codeur      fichiers
Correcteur  fonction
```

La quantité de contexte est donc **dégressive** dans la pyramide. Ce n'est pas une optimisation
économique. C'est une **optimisation de qualité du raisonnement**.

Sans ce paragraphe, on voit une série de mécanismes. Avec lui, on comprend qu'ils poursuivent tous le
même objectif : **transformer une mémoire potentiellement immense en un contexte minimal, ciblé et
vérifiable pour chaque activation.**

---
- **Socle factuel** : audits 24-25/07 (branchements, agent context, budget) + implémentation GO livrée
  (manifest signé 2 kinds, model_windows, context_check advisory, verify_run étendu — 516+34 tests).
- **Principe directeur** : un agent = activation temporaire d'un rôle dans un projet vivant. Le projet
  conserve le pourquoi, le contexte disponible, qui a travaillé où, et comment reprendre sans perte.
- **Anti-couches** : chaque brique ci-dessous se raccorde à un artefact EXISTANT (manifest, wiremap,
  state.json, error_journal, knowledge_trace, dispatch_audit, telemetry, PROJECT_BIBLE). Aucune plateforme.

---

## 1. Audit de compatibilité avec l'existant

| Capacité | État réel (prouvé) | Raccord V2 |
|---|---|---|
| Preuve du fourni | IMPLEMENTED — manifest 2 kinds signés + prompt_sha256 | socle de tout |
| Fraîcheur / dérive | IMPLEMENTED — context_check (score, budget, reco texte) | déclencheur du refresh (A) |
| Preuve du « lu » | NOT_FOUND — `--output-format json` sans transcript | brique B |
| Preuve de l'« utilisé » | IMPLEMENTED (partiel) — knowledge_trace (citations recoupées) | complété par B |
| « Influent » | PROPOSED — champ du futur rapport d'agent (chantier R6, 24/07 §4) | brique 4 (checkpoint) |
| Carte feature→code | IMPLEMENTED — wiremap {feature, fichiers[], fonction, preuve} vérifiée par check_wiremap | brique 6 |
| Qui a travaillé où | PARTIAL — state.json (etape/model/ts), dispatch_audit (role/model, HMAC), telemetry ; granularité = run+etape, jamais fichier-par-agent | brique 6 (honnête sur la granularité) |
| Mémoire projet durable | NOT_FOUND — PROJECT_BIBLE mort-vivant (arbitrage « implémenter ou supprimer » EN ATTENTE, audit 24/07 §5) | brique 5/Core Memory — voir décision D1 |
| Reprise entre activations | PARTIAL — retry/escalade = prompt frais + pré-mortem (seul carry-over) | briques 4-5 généralisent ce canal |
| Saturation fenêtre | RÉELLE — 465 270 tokens observés sur UNE passe s9 (telemetry card_engine) ; aucune métrique live disponible en `claude -p` headless | contrainte structurante des briques 4-5 |

## 2. Architecture proposée — les 6 briques

### Brique 1-2 (livrées) — Manifest + Freshness
Inchangées. V2 n'y ajoute rien.

### Brique A/3 — Context Refresh (delta ciblé)
- **Déclencheur** : uniquement à la re-activation d'une étape (`activation ≥ 2` dans le manifest — retry,
  escalade, reprise après pause) ET score `REQUIRES_REFRESH`/`STALE_CRITICAL` du context_check. Jamais en
  cours de session, jamais sur `FRESH`/`STALE_WARNING` (anti sur-refresh).
- **Signaux** : ceux du context_check existant (sha256, commits_since, décisions, pré-mortem, budget) —
  aucun nouveau capteur.
- **Format** : bloc `## CE QUI A CHANGÉ DEPUIS TA DERNIÈRE ACTIVATION (<ts N-1> → <ts N>)` assemblé par
  le même code que les artefacts amont (run_real), **borné** (proposition : 4 000 chars), une ligne par
  source dérivée (quoi + nature du changement + « relis-le »), jamais le contenu complet — l'agent relit
  lui-même s'il a Read. Refresh complet **interdit par défaut** (conforme arbitrage).
- **Risques** : sur-refresh (mitigé : activation≥2 + score seuil + borne) ; delta trompeur si la table des
  consommateurs est fausse (mitigé : V1 = sources du manifest uniquement, pas d'inférence de graphe).

### Brique B — Preuve du « lu » (reads index, pas transcript brut)
- **Chaîne complète** : fourni (manifest, fait) → **lu** (nouveau) → utilisé (knowledge_trace, fait) →
  influent (checkpoint brique 4).
- **Architecture** : `claude -p --output-format stream-json` dans run_real ; on ne stocke PAS le transcript
  brut — un parseur extrait les événements tool_use (Read/Grep/Glob : chemin + ts) vers
  `context/<etape>.reads.jsonl` + sha256 du transcript complet (le brut est jetable ou archivable à part).
  Coût stockage : quelques Ko/étape (index) vs Mo (brut). Coût tokens : nul (même session, autre format de
  sortie). Dépendance : stabilité du format CLI — à sonder sur un run avant généralisation.
- **Valeur audit** : verify_run peut alors recouper knowledge_trace (« cité ») contre reads (« ouvert ») —
  le théâtre de citation devient détectable mécaniquement.
- **Quand** : opt-in par run (arbitrage ATTENTE respecté), activé d'office sur les runs observés.

### Brique C — Impact automatique
- **Chaîne** : source modifiée → consommateurs (table CONTEXT_CONSUMERS **validée par l'observation**,
  dérivée de _UPSTREAM_BY_STEP + mandatory_read) → modules/fichiers (wiremap) → étapes/runs (manifests +
  state.json) → décisions (pending_review_decisions par projet).
- **V2 conserve l'arbitrage** : d'abord « source X changée = alerte » (déjà livré dans context_check) ;
  le mapping automatique vers les étapes n'est activé qu'après validation de la table par les runs observés.
  Ne pas automatiser une mauvaise compréhension du graphe.

### Brique 4 — Context Handoff (Agent A → A2)
- **Contrainte structurante** : en `claude -p` headless, AUCUNE métrique de fenêtre en cours de session —
  un « seuil 75-90 % » live est inobservable. Le handoff ne peut donc pas être déclenché DE L'INTÉRIEUR ;
  il est déclenché PAR LE DRIVER, aux frontières d'activation (retry, escalade, reprise) — points qui
  existent déjà (`_maybe_escalate`).
- **Mécanisme** : le contrat (s9 d'abord) exige un bloc final `CHECKPOINT` machine-parsable dans la sortie
  de CHAQUE tentative — champs obligatoires : objectif courant · avancement · décisions prises · hypothèses
  actives · hypothèses rejetées · fichiers concernés · tests réalisés · prochaine action · risques. Le
  driver l'extrait vers `context/<etape>.checkpoint.json` (signé HMAC comme le manifest).
- **Checkpoint ≠ résumé** : un résumé compresse la narration ; un checkpoint est un **état structuré
  falsifiable**. Validation mécanique (style static_oracles, anti-théâtre) : champs non vides · chaque
  fichier cité existe · chaque test cité existe et son statut déclaré correspond au dernier oracle ·
  la « prochaine action » référence une zone in_scope. Checkpoint invalide ⇒ traité comme absent (A2
  repart du pré-mortem seul, comme aujourd'hui) — jamais un faux état de confiance.
- **Moment optimal** : à CHAQUE fin de tentative (coût marginal : quelques centaines de tokens de sortie),
  pas seulement en cas d'échec — un checkpoint de succès sert aussi la reprise du run et la brique 6.
- **Seuils préventifs** (sans métrique live) : la télémétrie historique par étape (tokens observés) permet
  au driver de savoir qu'une étape sature typiquement → scope réduit ou handoff préventif — calibrage
  APRÈS les runs observés.

### Brique 5 — Héritage contrôlé / Core Memory
- **Principe : « trop de contexte tue le contexte. »** Interdit : transmettre la conversation complète.
  Le contexte successeur d'A2 = contrat (identique) + checkpoint validé + delta wiremap (brique A) +
  pré-mortem (existant) + pointeurs sources (manifest) — c'est TOUT.
- **Règles de compression** : obligatoire = les 9 champs du checkpoint, verbatim ; supprimable = sorties
  d'outils, narration, essais intermédiaires (tout ce qui n'est pas dans le schéma) ; le « pourquoi » des
  décisions tient en une ligne par décision dans le checkpoint.
- **Validation de fidélité** : mécanique (ci-dessus) + première tâche imposée d'A2 : **vérifier le
  checkpoint contre le réel** (fichiers/tests annoncés) avant de continuer — la doctrine « rapporté ≠
  démontré » appliquée entre agents.
- **Core Memory** = fédération de l'EXISTANT, pas un nouveau magasin : error_journal (échecs, vivant) ·
  décisions ratifiées (pending_review_decisions + apply_decisions) · checkpoints promus · KB (briques).
  Le fichier canonique par projet est **PROJECT_BIBLE.md ressuscité** : alimenté par promotion HUMAINE de
  checkpoints/décisions (propose-only, comme le ledger), injecté en CONTENU à s0 (ferme E1 pour s0).
  → tranche l'arbitrage en attente « implémenter ou supprimer » : voir décision D1.

### Brique 6 — Navigation Wiremap des directeurs
- **Requête cible** : « Fireball perd 10 % contre Warrior » → feature (wiremap) → fichiers/fonction
  (wiremap, déjà vérifiés par oracle) → runs/étapes ayant touché ces fichiers (manifests.sources +
  checkpoints.fichiers + state.json) → modèle/rôle par étape (dispatch_audit signé) → décisions du projet
  (pending_review_decisions) → tests (champ `preuve` de la wiremap) → rapports d'agents (artifacts/*.txt,
  auto-déclarés — dit comme tel).
- **Outil** : `wiremap_nav.mjs`, CLI 100 % lecture (famille context_check), requête avant : feature → chaîne ;
  requête inverse : fichier → features → runs → décisions. Zéro écriture, zéro risque runtime.
- **Limite honnête de granularité** : l'attribution est au niveau run+étape+modèle, PAS fichier-par-agent
  ligne-à-ligne (les agents ne commitent pas ; git blame remonte aux commits de Pierre). La brique 4
  (checkpoints avec `fichiers concernés`) affine progressivement cette granularité. Les « conversations
  associées » n'existent que via artifacts/*.txt tant que la brique B n'est pas active.

## 3. Dépendances entre briques

```
[1-2 Manifest+Freshness : LIVRÉES]
        │
        ├─► Run observé (chemin ratifié) ──► calibre : seuils A · consommateurs C · saturation 4
        │
        ├─► Brique 6 (nav, lecture seule)  — dépend de : manifests (faits) ; enrichie par 4 (checkpoints) et B (reads)
        ├─► Brique B (reads index, opt-in) — dépend de : sonde format stream-json
        ├─► Brique 4 (checkpoint)          — dépend de : schéma + validateur ; câblage retry = gate Pierre
        ├─► Brique 5 (héritage/Core Memory)— dépend de : 4 + décision D1 (PROJECT_BIBLE)
        ├─► Brique A (refresh delta)       — dépend de : données des runs observés (calibrage)
        └─► Brique C (impact auto)         — dépend de : table consommateurs VALIDÉE (le plus tard)
```

## 4. Ordre d'implémentation recommandé

1. **Run Forge observé** (déjà ratifié — produit les données de calibrage de tout le reste).
2. **Brique 6 — wiremap_nav.mjs** : lecture seule, zéro risque, ROI directeur immédiat, exploitable dès
   les manifests du run observé.
3. **Brique B-lite** : sonde stream-json sur UN run + reads index (opt-in).
4. **Brique 4** : schéma checkpoint + validateur anti-théâtre (outillage pur), puis câblage dans le chemin
   retry/escalade (modifie le driver ⇒ gate Pierre distinct).
5. **Brique 5** : héritage contrôlé + résurrection PROJECT_BIBLE (après D1).
6. **Brique A** : refresh delta automatique (seuils calibrés sur les runs observés).
7. **Brique C** : impact automatique (en dernier, graphe validé).

## 5. Risques

- **Théâtre de checkpoint** (l'agent embellit son avancement) — mitigé : validation mécanique + A2
  vérifie-d'abord ; jamais de checkpoint invalide « réparé » silencieusement.
- **Résumé déguisé en checkpoint** — mitigé : schéma à champs falsifiables, pas de texte libre global.
- **Boucles de refresh / interruptions** — mitigé : déclencheur aux frontières d'activation uniquement + bornes.
- **Fausse confiance du graphe d'impact** (« non listé = non impacté ») — mitigé : C en dernier, alerte simple d'abord.
- **Dérive de coût** (stream-json, checkpoints partout) — mitigé : opt-in, index plutôt que brut, mesure sur runs observés.
- **Contradiction d'arbitrage** : la brique 5 ressuscite PROJECT_BIBLE alors que « supprimer » restait une
  option ouverte — c'est une DÉCISION (D1), pas un fait accompli.

## 6. Ce qui doit rester humain

Promotion checkpoint/décision → PROJECT_BIBLE (propose-only) · ratification des seuils (refresh, saturation) ·
tout gate merge/reject/freeze · correction sémantique de la wiremap · activation de chaque brique (gates séparés).

## 7. Ce qui peut être automatisé

Manifest/diff/score (fait) · extraction+validation mécanique des checkpoints · assemblage du bloc delta ·
reads index · requêtes wiremap_nav · recoupement cité↔ouvert dans verify_run.

## 8. Décisions Pierre (gates de cette architecture)

- **D1** : PROJECT_BIBLE devient le Core Memory par projet (résurrection, propose-only, injection contenu à s0)
  — ou suppression définitive du connecteur ? (tranche l'arbitrage ouvert du 24/07)
- **D2** : go brique 6 (wiremap_nav, lecture seule) dès maintenant ou après le run observé ?
- **D3** : sonde stream-json (brique B-lite) incluse dans le run observé ?
- **D4** : schéma checkpoint (9 champs) — valider le schéma avant tout outillage.
- **D5** : confirmer l'ordre §4.

## Statut par surface

```
software_verdict: OK            (architecture ancrée sur artefacts existants prouvés ; aucun code produit)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```
*Aucun verdict global « prêt » (consigne mission).*
