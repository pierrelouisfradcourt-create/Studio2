# MODÈLE CIBLE — v0.1 (matrice)

*2026-09-01 · DOCUMENTED_ONLY · aucun code, aucun déplacement, aucune suppression.
Dépôt source `feeb29cb`, non touché. **On copie, jamais on ne déplace.***

## La matrice

| Objet cible | Question à laquelle il répond | Producteur | Consommateurs | Ancien composant réutilisable | Manque | Comm. dynamique ? |
|---|---|---|---|---|---|---|
| **GAME_BLUEPRINT** | Quel jeu voulons-nous fabriquer ? | Fable + design | tous | Brief `FORGE_PROJECT_INPUT_V0` | adaptation → objet **vivant** | **OUI** — tous amendent, chacun sa section |
| **Research** | Que veulent, que fuient les joueurs ? | Research | Fable, design | `s2-worldscan` (`run: WebSearch, WebFetch`) | axe *abandons/flops* · capitalisation KB | non — produit, puis consulté |
| **World Scan** | Que se passe-t-il dans ce marché ? | World Scan | Fable | `s2-worldscan`, `s2.7` (profils mono-étape) | déclenchement à la demande | non |
| **Prisme** | Comment les références fonctionnent ? Qu'oublions-nous ? | Prisme | design, Feature Map | `s1-prisme`, `prisme.json` | rien | non |
| **Gameplay** | Quelle boucle, quelles actions, quel échec ? | Gameplay | tous | `s0-contrat` → charter | devient section, pas artefact | **OUI** ↔ UX, Systems, Tech |
| **Systems / Economy** | Quels nombres produisent cette sensation ? | System Design | Build, QA | `loop_spec.mjs`, `game_master_schema.mjs` (**projections PURES**, verrou anti-LLM) | chaînon `metrics → paramètres` | **OUI** ↔ Gameplay, UX |
| **UX** | Le joueur comprend-il ce qu'il voit et peut faire ? | UX | design, Architect, QA | **aucun** (`\bUX\b` : 2 contrats, et seulement *chez les concurrents*) | **tout — à construire** | **OUI** ↔ Gameplay, Art |
| **Art direction** | À quoi ça ressemble, pourquoi ? | Art | Build, QA visuelle | `s2.5-artbible` + `redteam-artdirector` | rien | **OUI** ↔ Tech, UX |
| **FEATURE_MAP** | Qu'est-ce qui doit exister ? | Design (fonction, plus étape) | Architect, Build, QA | `s3-decompo` → `featuremap.json` | fusion : devient section ; son invariant devient invariant du Blueprint | **OUI** ↔ Architect |
| **GAME_FLOW** | Comment le joueur et les systèmes traversent le jeu ? | Design / System | **Architect**, QA | *voir la note ci-dessous* | **définir sa forme avant tout** | **OUI** ↔ Architect |
| **ARCHITECTURE_CONTRACT** *(ex-`blueprint.json`)* | Comment le construire ? | Architect | Build, Wiremap | `s4-archi` (`modules · deps_interdites · ownership`) | déplacer : après Feature Map + Flow · **droit de remonter** | **OUI** ↔ Gameplay, Art, Build |
| **WIREMAP** | Où cela existe-t-il réellement ? | Architect / Build | QA, Evidence | `s5-wiremap` (`fonction · fichiers · preuve · statut`) | adaptation | oui ↔ Build |
| **BUILD** | Fabriquer le vrai jeu | Build Orchestrator + workers | QA | `s9-build` ×4 + squelette `forge/standard/` | porte de suffisance en entrée | oui ↔ Architect |
| **QA** | Est-ce conforme ? | QA | Fable, Human | ≈5 800 l. d'oracles non-LLM (27 tests) | **volet design** (métriques) | oui → objections |
| **Red Team** | Qu'est-ce qui ne tient pas ? | Red Team | Fable | `s6`, `s11` — advisory | indépendance (1 profil sur 19) | oui → objections |
| **EVIDENCE** | Qu'est-ce qui est prouvé ? | Forge | verdict, Fable, Human | `verdict` HMAC + `verify_run` | **jointure `expected ↔ actual`** | non — append-only |
| **METRICS** | Le jeu atteint-il ses cibles ? | Pierre pose · QA mesure | design, Fable | règle de variance ratifiée | **la boucle entière** | oui → rework |
| **HUMAN_GATE** | Le jeu vaut-il quelque chose ? | **Pierre** | Fable | `gate.py` (*the FORCER brick*) | destination `decision-log` | — |

---

## La note qui compte : `GAME_FLOW` n'est pas un 4ᵉ objet

Tu as raison de refuser un artefact isolé de plus. La question n'est pas *« faut-il un GAME_FLOW ? »*
mais **« que le Director doit-il transmettre à l'Architecte ? »**. Mesuré — ce que `s4-archi`
reçoit **aujourd'hui** :

```
mandatory_read:
  - featuremap produit par l'étape 3              ← le QUOI
  - charter.yaml — INTENT LINEAGE : intention humaine, invariants, hors_scope, provenance
  - repo_map.yaml — TABLE FIGÉE des racines       ← les contraintes
  - knowledge_packet.json — patterns externes, ADVISORY jamais prescriptif
  - blueprint.yaml existant si le repo est déjà structuré
in_scope : modules · graphe de dépendances · ownership · invariants
```

**L'Architecte reçoit donc déjà le QUOI, l'INTENTION et les CONTRAINTES.** Ce qui manque à cette
transmission, c'est exactement ce que tu décris : **les interactions dynamiques que l'architecture
devra supporter** (`WAVE START → SPAWN → MOVE → DETECT → ATTACK → DAMAGE → DEATH → REWARD →
DÉCISION JOUEUR → UPGRADE → NEXT WAVE`).

Donc trois formes possibles, **non tranchées** :

| # | forme | conséquence |
|---|---|---|
| **F1** | une **section du Blueprint** — `game_flow`, lue par l'Architecte via `mandatory_read` | aucun nouvel artefact ; un champ de plus dans un objet qui existe |
| **F2** | un **enrichissement de `featuremap`** — les features portent leurs relations | pas de nouvel objet, mais alourdit un artefact déjà chargé (26 feuilles typiques) |
| **F3** | un **artefact distinct** | 4ᵉ objet, risque de chevauchement — **ce que tu veux éviter** |

**Je penche pour F1**, pour une raison mesurée : `loop.json` existe déjà et décrit une boucle, mais
c'est une **projection déterministe de `prisme.json`** sous verrou anti-écriture LLM — donc un
*dérivé*, pas un *flux conçu*. Une section `game_flow` du Blueprint serait le premier endroit où le
flux est **décidé** plutôt que dérivé. Mais c'est ta décision.

---

## Ce qui est verrouillé par cette v0.1

1. **`GAME_BLUEPRINT`** = objet central de conception · **`ARCHITECTURE_CONTRACT`** = l'actuel
   `blueprint.json`. Deux objets, deux noms. *(Renommage enregistré, non exécuté.)*
2. **`FEATURE_MAP` ≠ `WIREMAP`** — mesuré : 26 ids vs 25, **intersection 0**. On garde les deux.
3. **Research est une obligation d'entrée. World Scan et Prisme sont des outils** que le Director
   mobilise pour approfondir. Jamais zéro recherche, jamais une étude obligatoire.
4. **Les flèches sont des relations de travail, pas des portes de passage.**

## Ce qui reste ouvert

| # | question |
|---|---|
| Q1 | Forme de `GAME_FLOW` : **F1**, F2 ou F3 ? |
| Q2 | Verrou *« World Scan hors périmètre »* + R8 BLOQUÉ (2026-08-29) — Research systématique le contredit. **Non levé.** |
| Q3 | Qui prouve la **variance** d'une `design_metric` avant qu'elle devienne une cible ? |
| Q4 | La **notification** entre capacités : mécanisme runtime, ou discipline du Director ? |
| Q5 | Rail = catalogue de compétences (résolu) — mais qui décide du **prochain jeu** ? |

---

**Colonne « comm. dynamique » — lecture** : 11 objets sur 18 en exigent une. C'est là qu'est le
gain réel, pas dans le nombre d'étapes. Le manque unique et transversal reste la **notification** :
aujourd'hui un amendement ne prévient personne, donc un désaccord ne peut s'exprimer qu'en aval.

`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
