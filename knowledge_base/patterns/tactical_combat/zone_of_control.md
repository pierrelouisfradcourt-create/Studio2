# Pattern — Zone of Control (zone de contrôle)

- **brick_id** : `pat-zone-of-control`
- **kind** : pattern (advisory, cité — ZÉRO code repris)
- **source** : Battle for Wesnoth — déplacement et zones de contrôle
- **provenance_url** : https://wiki.wesnoth.org/ZoneOfControl
- **licence** : GPL-2.0-or-later (concept cité uniquement)
- **runtime** : agnostic — **advisory_only: true**

## Énoncé

Chaque unité **projette une zone de contrôle** sur les cases adjacentes. Une unité ennemie qui
**entre** dans une case sous zone de contrôle doit y **arrêter son déplacement** pour ce tour
(elle ne peut pas traverser librement la ligne adverse).

## Pourquoi (invariant de conception tactique)

Sans ZoC, le déplacement libre transforme une grille tactique en course : les unités contournent
l'adversaire sans coût. La ZoC crée un **positionnement signifiant** (tenir une ligne, bloquer un
passage) — c'est ce qui distingue un jeu tactique d'un jeu de déplacement pur.

## Invariants testables (à faire tenir chez tout système inspiré)

1. Une case adjacente à ≥1 unité ennemie est « contrôlée » pour le camp adverse.
2. Un déplacement qui pénètre une case contrôlée est tronqué à cette case (mouvement restant = 0).
3. Déterminisme : même configuration ⇒ même ensemble de cases contrôlées.

## Usage advisory

Cité pour justifier une contrainte de mouvement tactique. Version minimale possible : « s'arrêter
en entrant au contact d'un ennemi » (implémentable en réécriture propre sous licence permissive).
