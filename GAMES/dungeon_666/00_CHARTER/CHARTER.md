# Dungeon 666 — charte du projet

`statut_artefact : PROPOSED` · `claim_verdict : NO_CLAIM_ALLOWED` · `evidence_verdict : MECHANICAL_VALIDATION_ONLY`

Historique des demandes de Pierre :
- 2026-10-01, « GO prototype » : faire tourner le jeu et vérifier que déplacement et combat sont amusants.
- 2026-10-01, « GO prototype complet » (V2) : représenter la boucle complète
  **Ville → équipement/classe/armes/compétences → donjon → combats → bonus temporaires → Gardien → checkpoint/TP → nouvelle section**.

Ce document fixe ce que le prototype doit prouver. Il ne ratifie rien. Le feel, l'équilibrage et le fun
restent une **gate Pierre**. Pas de passage à Godot tant que le feel du combat n'est pas validé.

## Le jeu en une phrase

Un action-roguelite mobile en vue de dessus. Le joueur part de la Ville, prépare sa classe et son
équipement, puis descend les 666 étages de l'Enfer en combats courts et nerveux. Le combat vient de
Hades, le butin de Diablo 1/2, les contrôles tactiles de Brawl Stars. Un Gardien tous les 18 étages
ouvre un checkpoint et un point de téléportation.

## Piliers

| # | Pilier | Ce que ça veut dire concrètement |
|---|---|---|
| 1 | **Le dash d'abord** | Le dash donne de l'invulnérabilité, annule presque tout et est récompensé (esquive parfaite : jauge de Super + recharge). Bien dasher doit diviser les dégâts subis. |
| 2 | **Lisible avant d'être dur** | Aucun dégât de contact. Toute attaque ennemie est télégraphiée, et un nombre borné d'ennemis attaque à la fois. Le rouge signifie « ça fait mal ». Une mort doit toujours avoir une cause visible. |
| 3 | **Chaque coup se sent** | Gel d'impact, recul, flash, particules, tremblement, son : un coup qui touche ne passe jamais inaperçu. |
| 4 | **Le permanent et le temporaire se lisent** | Permanent (Ville) : classe, armes, équipement, compétences, déblocages. Temporaire (run) : bénédictions, pouvoirs, synergies. La mort remet le temporaire à zéro, et l'écran de mort le montre. |
| 5 | **Une mort ne coûte jamais toute la descente** | On repart du dernier checkpoint, avec toute sa progression permanente. |

## Structure des 666 étages (V2)

- **Section** : 18 étages. Le 18ᵉ est un **Gardien**. Le battre ouvre un checkpoint et un point de
  téléportation (l'étage suivant). La sortie propose deux portes : continuer, ou rentrer en Ville par le portail.
- **Cercle** : 72 étages (4 sections). Il y a 9 Cercles de l'Enfer, soit 648 étages.
- **Finale** : 18 étages, « L'Abîme » (1 section). Total : 648 + 18 = **666**, soit **37 sections et 37 Gardiens**.
- **Aucun étage n'est écrit à la main.** Chaque étage est composé à la volée : plan de section
  (type d'étage, portes, vagues), dispositions de salle, bestiaire et élites, Gardien de la section
  (rotation de plusieurs modèles).

## Ce que le prototype doit prouver (périmètre V2, ordre de priorité de Pierre)

| Priorité | Contenu | Où |
|---|---|---|
| 1 | Feel du déplacement et du combat : combo, dash, frappe de dash, compétences, gadgets, mobilité pendant le combo, gel d'impact, visée manuelle | `src/sim/player.mjs`, `combat.mjs` |
| 1 | D5 / D8 / D9 **testables, pas tranchées** : labo du feel en Ville et en pause | `src/sim/lab.mjs` |
| 2 | Boucle Ville → donjon → Gardien → checkpoint/TP → nouvelle section ; mort → dernier checkpoint | `src/sim/run.mjs`, `src/ui/town.mjs` |
| 3 | Classes, armes, compétences, gadgets, Supers | `src/sim/kits.mjs` |
| 4 | Archétypes d'ennemis (mêlée rapide et lourde, distance, chargeur, zone, invocateur, élites) et plusieurs Gardiens aux patterns distincts | `src/sim/foe_*.mjs`, `boss_*.mjs` |
| 5 | Progression permanente (profil, Sanctuaire, déblocages) et bonus temporaires (bénédictions) | `src/sim/profile.mjs`, `boons.mjs` |
| 6 | Système des 666 étages (sections de 18, composition) | `src/sim/floors.mjs`, `sections.mjs`, `room.mjs` |
| Hors périmètre | Monétisation, multijoueur, sauvegarde cloud, portage Godot | — |

## Choix techniques

- **Web, canvas 2D, zéro dépendance.** C'est le chemin le plus court vers un test de feel *sur
  téléphone* : le jeu tourne dans n'importe quel navigateur mobile, depuis un fichier unique
  (`dist/dungeon_666.html`) ou depuis `node server.mjs` sur le Wi-Fi local. Un portage Godot
  reste possible une fois le feel validé : la simulation est isolée, déterministe et sans DOM.
- **Simulation déterministe à 60 Hz**, séparée du rendu et des entrées. Elle est testable
  sous `node --test` et jouable par un bot.
- **Tous les nombres sont dans des fichiers de données** (`src/sim/config.mjs` et les registres
  `kits.mjs`, `foe_data.mjs`, `boss_data.mjs`, `town_data.mjs`). On peut aussi les régler en jeu
  (pause → Réglages du feel).

## Hors du rail et hors de la Forge, volontairement

Dungeon 666 est un projet lancé directement par Pierre. Il ne figure pas au rail de
`GAMES/RAIL_REGISTER.md`, n'est pas déclaré dans `forge/oracles.json` (surface protégée) et
n'a pas de `game_contract.yaml` (schéma fermé, réservé au pipeline Forge). Ses oracles se
lancent localement : `node run-oracle.mjs`.
