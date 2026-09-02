---
genre_tags: ["arcade", "casse-briques", "physique-continue", "reflexe-precision", "session-courte"]
mood_keywords: ["tendu", "satisfaisant", "rythme-croissant", "precision"]
status: PROPOSED
scope: breakout_v2
schema_version: 1
---

# GENRE BIBLE — Breakout_v2 (v1, PROPOSED)

Date : 2026-07-31 · Mission : matérialisation des artefacts de campagne Breakout V2
(mission orchestrateur, aucun `FORGE_DISPATCH:s0-contrat` n'a été ouvert pour ce document —
transcription/mise en forme, pas une rédaction sous contrat dispatché). Statut : **PROPOSED**,
troisième Genre Bible du studio après Pong et Snake. Aucune promotion vers `knowledge_base/**`
n'a été faite.

`claim_verdict: NO_CLAIM_ALLOWED` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY`.

**Patron répliqué** : `docs/forge/GENRE_BIBLE_SNAKE_V1_PROPOSED.md`, version condensée (accord
explicite de la mission : « gabarit plus court accepté »).

**AVERTISSEMENT DE PROVENANCE — LA DIFFÉRENCE MAJEURE AVEC PONG ET SNAKE** : Pong et Snake
avaient chacun un dossier `GAME_REFERENCE/` issu d'un World Scan HTTP-sourcé (URLs vérifiées,
codes HTTP mesurés) qui précédait et alimentait leur Genre Bible respective. **Aucun World
Scan sourcé n'a été conduit pour Breakout** à la date de ce document. Ce qui suit provient de
deux origines, distinguées règle par règle :
1. **[TRACE_INDIRECTE]** — le charter web `lab/forge_runs/breakout/charter.yaml` (2026-07-11),
   artefact du studio, pas une source de genre externe.
2. **[H]** — connaissance générale du genre casse-briques (Breakout/Arkanoid), non vérifiée par
   une URL consultée dans cette mission. Chaque règle marquée `[H]` est une **hypothèse à
   sourcer par un World Scan futur**, pas un fait établi.

Aucune règle de ce document ne porte de statut `OBSERVATION_DIRECTE` — c'est la conséquence
honnête de l'absence de World Scan, pas un oubli de rédaction.

---

## 1. IDENTITÉ DE GENRE

Breakout est un jeu d'arcade solo en temps réel, à physique continue et déterministe (hors
seed de disposition des briques), où le joueur déplace une raquette pour intercepter une balle
en mouvement permanent et détruire, brique par brique, un mur qui lui fait face. L'intérêt du
genre tient à la précision du contrôle indirect : le joueur n'agit jamais sur la balle
elle-même, seulement sur l'endroit où sa raquette la rencontre — l'angle de rebond devient le
véritable espace de décision. La partie se termine par la victoire (mur entièrement détruit) ou
la défaite (balle perdue à répétition jusqu'à épuisement des vies).

## 2. RATIONALE

Cette bible existe pour la même raison que les Genre Bibles Pong et Snake : donner aux étapes
suivantes de la Forge (Prisme, architecture, wiremap — cf.
`docs/forge/FORGE_ARCHITECT_MANUAL_V1.md` §2-§5) des règles de genre citables plutôt que des
choix inventés en cours de production. À la différence de ses deux prédécesseures, ce document
ne compresse PAS un World Scan déjà fait — il **esquisse la forme attendue** à partir de
connaissance générale et du charter web 2026-07-11, en marquant explicitement ce qui reste à
vérifier. Il sert de gabarit exploitable par `check_genre_coverage` dès qu'une wiremap
Breakout_v2 existera, mais son contenu n'est pas ratifiable tant qu'un World Scan sourcé ne l'a
pas confirmé, précisé ou contredit.

## 3. RÈGLES DE GENRE

```json
{
  "genre_rules": [
    {
      "id": "genre.breakout.continuous_ball_motion",
      "statement": "La balle est en mouvement continu permanent (vitesse constante ou quasi-constante) ; le joueur n'agit jamais directement sur la balle, seulement sur la raquette.",
      "applies_to": "core.physics",
      "confiance": "[H] connaissance générale du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.paddle_only_control",
      "statement": "La seule action du joueur est de déplacer la raquette horizontalement, bornée aux limites du terrain.",
      "applies_to": "core.input",
      "confiance": "[H] connaissance générale du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.impact_point_deflection",
      "statement": "L'angle de rebond de la balle sur la raquette dépend du point d'impact relatif (centre = rebond vertical, bords = déviation croissante) — mécanique distinctive du genre depuis Arkanoid.",
      "applies_to": "core.paddle_rebound",
      "confiance": "[TRACE_INDIRECTE + H] citée en germe dans lab/forge_runs/breakout/charter.yaml (2026-07-11) ; magnitude et convention non vérifiées par une source de genre externe consultée dans cette mission."
    },
    {
      "id": "genre.breakout.brick_destruction_on_contact",
      "statement": "Une brique touchée par la balle est détruite au contact (V1 : un seul coup par brique, pas de brique multi-hits) et la balle rebondit selon la face touchée.",
      "applies_to": "core.brick_collision",
      "confiance": "[H] connaissance générale du genre ; la restriction 'un seul coup' est un choix de périmètre V1 (voir hors_scope du charter), pas une observation de source."
    },
    {
      "id": "genre.breakout.wall_reflection",
      "statement": "La balle rebondit sur les murs latéraux et le plafond par inversion de la composante de vitesse perpendiculaire au mur touché.",
      "applies_to": "core.wall_collision",
      "confiance": "[H] convention physique généraliste du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.life_loss_on_drop",
      "statement": "Une vie est perdue quand la balle franchit la limite basse du terrain sans avoir été interceptée par la raquette ; une nouvelle balle est servie si des vies restent.",
      "applies_to": "core.life_loss",
      "confiance": "[H] connaissance générale du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.victory_condition_all_bricks",
      "statement": "La victoire est atteinte quand toutes les briques cassables du niveau sont détruites.",
      "applies_to": "core.end",
      "confiance": "[H] connaissance générale du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.defeat_condition_zero_lives",
      "statement": "La défaite est atteinte quand le nombre de vies restantes atteint zéro après une perte de balle.",
      "applies_to": "core.end",
      "confiance": "[H] connaissance générale du genre — non sourcée HTTP dans cette mission."
    },
    {
      "id": "genre.breakout.seeded_level_layout",
      "statement": "La disposition des briques d'un niveau est déterminée par une graine, reproductible à seed identique.",
      "applies_to": "core.level_generation",
      "confiance": "[TRACE_INDIRECTE] héritée de lab/forge_runs/breakout/charter.yaml (2026-07-11) et de l'exigence de déterminisme du studio (règle transverse, pas une observation de genre externe)."
    },
    {
      "id": "genre.breakout.session_short_focused",
      "statement": "Une partie individuelle (un niveau, une vie) dure typiquement de l'ordre de la minute.",
      "applies_to": "session.pacing",
      "confiance": "[H] la plus spéculative des 10 règles — aucune source, ni directe ni indirecte, ne chiffre cette durée. À vérifier ou retirer au premier World Scan."
    }
  ]
}
```

10 règles esquissées (dans la fourchette 8-12 demandée par le gabarit). **Aucune** ne porte la
confiance `OBSERVATION_DIRECTE` — c'est la conséquence assumée de l'absence de World Scan pour
Breakout, pas un défaut de cette rédaction.

## 4. CE QUE CE DOCUMENT NE PROUVE PAS

- **Aucune valeur chiffrée de genre** (durée de session, magnitude de l'angle de rebond,
  fréquence de rebond) n'est établie ici — les valeurs chiffrées du jeu vivent dans
  `lab/forge_runs/breakout_v2/charter.yaml` (`parametres_de_design`), toutes `A_EQUILIBRER`,
  jamais dérivées de cette bible.
- **La solidité du sourçage** : contrairement à Snake (10/14 sources HTTP 200 mesurées avant
  rédaction), zéro source externe n'a été testée pour ce document.
- **La couverture wiremap** : `games/breakout_v2/09_WIREMAP/wiremap.json` n'existe pas encore à
  la date de ce document — la correspondance `genre_rules[].id` → ligne de wiremap reste
  entièrement prospective, sur le même constat que Snake au moment de sa propre Genre Bible.

## 5. STATISTIQUE ADVISORY (séparée de tout pass/fail)

- Règles de genre : **10 / 10**, dont **0 / 10** en `OBSERVATION_DIRECTE` (aucun World Scan),
  **2 / 10** en `TRACE_INDIRECTE` (`impact_point_deflection` en partie, `seeded_level_layout`),
  **10 / 10** portant au moins un volet `[H]` non sourcé.
- Règle jugée la plus spéculative : `session_short_focused` (aucune trace, ni directe ni
  indirecte).
- Règles couvertes par une ligne de wiremap réelle : **0 / 10** — aucune wiremap Breakout_v2
  n'existe encore.

Cette statistique est **advisory** : elle ne bloque ni n'autorise rien mécaniquement — elle
sert à ce que Pierre voie d'un coup d'œil que cette bible est structurellement plus faible que
celles de Pong et Snake, faute de World Scan.

## Décision attendue (gate)

Ratifies-tu (a) la structure condensée de cette Genre Bible, (b) le statut `NON_RATIFIEE_
PROPOSITION` du fichier mécanique associé (`games/breakout_v2/01_DESIGN/genre_bible.json`)
tant qu'aucun World Scan sourcé n'a été conduit, (c) la nécessité d'un World Scan Breakout
avant toute consommation de cette bible par un builder (`genre_refs[]` de `check_genre_coverage`
exigeraient alors des règles réellement sourcées) ?
