# CONTRAT — P1 tranche mécanique-only (capteur qualité déterministe, advisory)

- **Date** : 2026-07-11
- **Statut** : **ACCEPTED → EXÉCUTÉ → CLOSED (expérience falsifiée)** — résultats : `P1_MECHANICAL_RESULTS.md` ; proposition suivante (doc seulement) : `P1_1_PROPOSAL.md`. Voir « Ajustements ratifiés » en fin de doc.
- **Nature** : capteur déterministe **advisory**, expérimental, **non-gating**. Ce n'est PAS un oracle de preuve, PAS un gate.
- **Objectif expérimental unique** : déterminer si des signaux mécaniques simples détectent des défauts de qualité RÉELS que les gates P0 ne voient pas — AVANT d'engager un P1 qualité complet.

## Invariants (garde-fous inscrits dans le contrat)

P0 reste gelé et inchangé. Ce capteur :
- **ne touche pas** `software_verdict`, `decision`, `is_clean_pass`, ni aucun reçu/verdict du pipeline de preuve ;
- **n'est pas câblé** dans `run-oracle.mjs` ni dans le driver (l'y câbler le rendrait gating — interdit) ;
- **ne produit aucun pass/fail**, aucun `returncode` de gate, aucun score global de qualité ;
- **aucun LLM** dans le chemin : le générateur d'inputs FTUE est scripté/seedé ; pas de juge multimodal, aucun jugement esthétique ou « plaisir humain » automatisé ;
- **aucune nouvelle couche mémoire/knowledge base** : sortie éphémère sous `lab/`, jamais promue en mémoire de référence.

Sortie **strictement advisory** — un signal à lire par un humain, jamais une décision machine.

## Exécution — hors-bande, réutilise l'outillage e2e existant

Le capteur tourne dans **son propre processus**, séparé de l'oracle. Il **réutilise le harnais e2e existant** (Playwright + `node_modules` belote-claude, pattern `e2e.mjs`, état `window.__game`, DOM `#overlay`/`#restart`) — **sans modifier** `e2e.mjs` ni `run-oracle.mjs`. Il ne fait que : lancer le jeu, piloter des inputs scriptés, capturer des screenshots, lire `window.__game`. Rien n'écrit dans le chemin de preuve.

## Entrées

1. Un jeu **déjà passant P0** (cibles : `breakout`, `menagerie_tactics`).
2. Le harnais e2e existant du jeu (réutilisé, non modifié).
3. Screenshots aux moments clés (chargement, 1re action, mi-partie, fin), via `page.screenshot` (déterministe).
4. Un générateur d'inputs **scripté à seed fixe** (varié par index, jamais LLM) + l'échantillonnage de `window.__game` après chaque input.

## Métriques déterministes (atomiques — jamais agrégées en une note)

### A. Lisibilité / rendu (screenshots + DOM)
| # | Métrique | Extraction | Drapeau |
|---|---|---|---|
| A1 | Contraste WCAG des éléments texte/UI DOM (`#overlay`, `#restart`…) | `getComputedStyle` couleur vs fond → ratio | < 4.5:1 |
| A2 | Taille des cibles interactives à résolution cible | bounding box px | < 24 px |
| A3 | Densité d'écran vide | fraction du frame = couleur de fond dominante | > 92 % |
| A4 | Nombre de couleurs distinctes / entropie | histogramme pixels | **signal brut, pas de seuil** (cohérence palette = P2, art bible) |
| A5 | Débordement viewport | élément hors cadre | présent |
| A6 | Réactivité visuelle | diff pixel avant/après un input censé agir | 0 changement |

### B. FTUE mécanique (générateur d'inputs scripté/seedé, non-LLM)
| # | Métrique | Mesure | Drapeau |
|---|---|---|---|
| B1 | Pas-avant-premier-delta d'état | inputs avant que `window.__game` change | > seuil |
| B2 | Pas-avant-première-récompense | inputs avant progrès score/objectif | > seuil ou jamais |
| B3 | Taux d'inputs morts | fraction d'inputs sans delta d'état | signal |
| B4 | Détection de stall | fenêtre d'inputs à 0 delta | présent |

> B mesure « un flux d'inputs naïf et mécanique fait-il des progrès rapidement ? » — proxy déterministe de l'onboarding. Un jeu qui exige une connaissance précise pour tout progrès y score mal. **Ce n'est pas** un bot « intelligent » (ce serait du LLM, interdit).

## Sorties (advisory, reproductibles)

- `lab/forge_sensors/<jeu>/visual_mechanical.json` — métriques brutes + drapeaux + seeds.
- `lab/forge_sensors/<jeu>/visual_mechanical_report.md` — lisible.
- **Rien d'autre.** Aucune écriture dans `verdict.json`, ledger, projets, mémoire.

## Preuves attendues

1. **Reproductibilité** : même jeu + même seed → rapport identique (hash stable).
2. **Couverture** : appliqué sur **≥2 jeux passant P0**.
3. **Traçabilité de chaque drapeau** : métrique + valeur mesurée + seuil + artefact (screenshot/trace) cité.
4. **Table d'orthogonalité** : « P0 = vert » vs « capteur signale » côte à côte, pour prouver que le signal est bien orthogonal aux gates P0.
5. **Comptabilité du bruit** : nombre total de drapeaux, dont vrais positifs (jugés par Pierre) → **taux de faux positifs rapporté explicitement**.

## Critère de succès de la tranche

- ≥1 drapeau = problème de qualité **réel** non détecté par P0, confirmé par ton inspection ;
- taux de faux positifs mesuré et présenté (un capteur bruyant est un échec même s'il trouve un vrai positif).

## Critères d'arrêt

- **Complétion** : rapports sur 2 jeux + ≥1 vrai positif + taux de faux positifs présenté → décision go/no-go P1-complet (à toi, séparément).
- **Kill / no-go** : si tous les drapeaux sont redondants avec P0 **ou** tous faux positifs → conclusion « base mécanique insuffisante », **ne pas** engager P1 complet.
- **Dépendance connue** : les métriques qui exigent un art bible pour être discriminantes (ex. A4 cohérence palette) restent en **signal brut**, jamais transformées en drapeau à ce stade.

## Ce que cette tranche N'EST PAS

Pas P1 complet. Pas un gate. Pas un score de qualité. Pas un juge de plaisir. Une **sonde d'exploration** pour décider, sur preuves, si une base mécanique mérite qu'on investisse P1 qualité.

## Rapport de charter (à la livraison de la tranche)

```
software_verdict: (inchangé — ce capteur n'en produit pas)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
advisory_only: true
```

---

## Ajustements ratifiés (Pierre, 2026-07-11)

### Point 1 — générateur FTUE : exploration seedée, jamais exhaustive
- Générateur **déterministe seedé**. La **seed est enregistrée** dans le rapport et la **séquence exacte d'inputs est rejouable** (rejeu bit-à-bit).
- **Aucun aléatoire non borné** (PRNG seedé, longueur fixe — jamais `Math.random`).
- Le rapport **distingue explicitement** `seeded_exploration` (le seul mode v0) de `systematic_coverage` (NON construit en v0 — trop proche d'un nouveau moteur de test ; P0 couvre déjà la jouabilité exhaustive).
- Raison : mesurer un **signal de comportement naïf**, pas re-prouver la jouabilité.

### Point 2 — seuils = hypothèses expérimentales, jamais des normes
- Les seuils initiaux sont des **hypothèses**. Chaque observation rapporte : **valeur mesurée · seuil utilisé · justification · résultat brut**.
- **Aucun `PASS`/`FAIL` de qualité.** Vocabulaire d'observation UNIQUE :
  - `signal_detected` — mesuré ET a franchi le seuil-hypothèse (à examiner par un humain) ;
  - `signal_absent` — mesuré, n'a pas franchi le seuil ;
  - `metric_unavailable` — non mesurable (honnête, ce n'est PAS un « pass »).
- Les seuils seront **réévalués après les 2 jeux** et la mesure du bruit.

### Contraintes supplémentaires (verrouillées)
- Aucun **score global**, aucune **agrégation automatique**, aucune conclusion **« bon/mauvais jeu »**.
- Chaque observation reste **traçable à son artefact brut** (screenshot/trace).

---

## Interface du capteur & format de rapport (v0)

### Emplacement
Code **hors** `scripts/forge/` (aucun code de production Forge touché) : `scripts/quality_sensor/` (tracké ; `tools/` est gitignored donc écarté). Cœur pur (sans navigateur) séparé de la collecte (Playwright), pour que le cœur soit testable en TDD déterministe.

### Interface — cœur pur (`scripts/quality_sensor/sensor.mjs`)
```
makeInputSequence(seed:int, length:int, alphabet:string[]) -> { seed, mode:"seeded_exploration", tokens:string[] }
   // déterministe : même (seed,length,alphabet) => mêmes tokens ; PRNG seedé (mulberry32), jamais Math.random ; rejouable.

evaluate(measured:number|null, threshold:{value,op:"<"|">"}) -> "signal_detected" | "signal_absent" | "metric_unavailable"
   // measured null/NaN => metric_unavailable ; sinon compare via op. JAMAIS de pass/fail.

observation({id, kind, measured, threshold, justification, raw, artifact}) -> Observation
   // enveloppe atomique traçable ; outcome dérivé par evaluate().

buildReport({game, run, observations}) -> Report
   // enveloppe advisory ; INTERDIT tout champ de score/verdict/pass/fail agrégé (invariant testé).
```

### Format de rapport (`lab/forge_sensors/<jeu>/visual_mechanical.json`)
```json
{
  "sensor": "visual_mechanical",
  "version": "0",
  "advisory": true,
  "game": "<nom>",
  "run": {
    "seed": 12345,
    "mode": "seeded_exploration",
    "input_sequence": ["ArrowLeft", "Space", "..."]
  },
  "observations": [
    {
      "id": "A1_contrast",
      "kind": "readability",
      "outcome": "signal_detected",
      "measured": 2.9,
      "threshold": { "value": 4.5, "op": "<", "status": "hypothesis" },
      "justification": "WCAG AA texte normal = 4.5:1",
      "raw": { "fg": "#888", "bg": "#777", "selector": "#overlay" },
      "artifact": "lab/forge_sensors/<jeu>/shots/overlay.png"
    }
  ]
}
```
Invariants du format : `advisory:true`, présence de `run.seed`+`run.input_sequence` (rejeu), chaque observation porte `measured`+`threshold`+`justification`+`raw`+`artifact`, **aucune** clé de score/verdict/agrégat au niveau racine. Un `visual_mechanical_report.md` lisible est dérivé du JSON (même contenu, jamais une conclusion).
