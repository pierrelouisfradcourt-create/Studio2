# Dungeon 666 — charte du projet

`statut_artefact : PROPOSED` · `claim_verdict : NO_CLAIM_ALLOWED` · `evidence_verdict : MECHANICAL_VALIDATION_ONLY`

Demande de Pierre du 2026-10-01 : « GO prototype ». Ce document fixe ce que le prototype doit
prouver. Il ne ratifie rien. Le feel, l'équilibrage et le fun restent une **gate Pierre**.

## Le jeu en une phrase

Un action-roguelite mobile en vue de dessus. Le joueur descend les 666 étages de l'Enfer en
combats courts et nerveux : le combat de Hades, le butin de Diablo 1/2, les contrôles tactiles
de Brawl Stars. Un Gardien tous les six étages sert de checkpoint, pour qu'une mort ne coûte
jamais plus de quelques minutes.

## Piliers

| # | Pilier | Ce que ça veut dire concrètement |
|---|---|---|
| 1 | **Le dash d'abord** | Le dash donne de l'invulnérabilité, annule presque tout et est récompensé (esquive parfaite : jauge de Super + recharge). Bien dasher doit diviser les dégâts subis. |
| 2 | **Lisible avant d'être dur** | Aucun dégât de contact. Toute attaque ennemie est télégraphiée (≥ 0,4 s) et un nombre borné d'ennemis attaque à la fois. Une mort doit toujours avoir une cause visible. |
| 3 | **Chaque coup se sent** | Gel d'impact, recul, flash, particules, tremblement, son : un coup qui touche ne passe jamais inaperçu. |
| 4 | **Sessions courtes** | Une section de 6 étages dure environ 4 à 6 minutes et se termine sur un Gardien et un checkpoint. |
| 5 | **Le build raconte la descente** | Bénédictions des 7 péchés capitaux (perdues à la mort) et équipement façon Diablo (conservé). |

## Structure des 666 étages

- **Section** : 6 étages. Le 6ᵉ est un Gardien. Le battre ouvre un checkpoint : on reprend au
  1ᵉʳ étage de la section suivante.
- **Cercle** : 72 étages (12 sections). Il y a 9 Cercles de l'Enfer (Limbes, Luxure,
  Gourmandise, Avarice, Colère, Hérésie, Violence, Fraude, Trahison), soit 648 étages.
- **Finale** : 18 étages, « Le Trône ». Total : 648 + 18 = **666**. Il y a 111 Gardiens.

## Ce que le prototype doit prouver (périmètre)

| Priorité | Contenu | Statut |
|---|---|---|
| **Must** | Déplacement, combo 3 coups, dash (i-frames, charges, frappe de dash), compétence, gadget à charges, Super chargé par les dégâts | fait |
| **Must** | Contrôles tactiles (joystick flottant, attaque tap/glisser, boutons), clavier/souris, manette | fait |
| **Must** | 5 archétypes d'ennemis télégraphiés, élites à modificateurs, 1 Gardien à 2 phases | fait |
| **Must** | Juice : gel d'impact, recul, tremblement, particules, sons procéduraux | fait |
| Should | Salles enchaînées, portes à récompense, bénédictions, butin, marchand, autels, checkpoint | fait (version mince) |
| Could | Panneau de réglage du feel en jeu, pour itérer sans code | fait |
| Won't (proto) | Plusieurs héros, plusieurs biomes visuels distincts, méta-progression, sauvegarde cloud, monétisation, multijoueur | hors périmètre |

## Choix techniques

- **Web, canvas 2D, zéro dépendance.** C'est le chemin le plus court vers un test de feel *sur
  téléphone* : le jeu tourne dans n'importe quel navigateur mobile, depuis un fichier unique
  (`dist/dungeon_666.html`) ou depuis `node server.mjs` sur le Wi-Fi local. Un portage Godot
  reste possible si le feel est validé : la simulation est isolée, déterministe et sans DOM.
- **Simulation déterministe à 60 Hz**, séparée du rendu et des entrées. Elle est testable
  sous `node --test` et jouable par un bot.
- **Tous les nombres de tuning sont dans `src/sim/config.mjs`**. On peut aussi les régler en jeu
  (pause → Réglages du feel).

## Hors du rail et hors de la Forge, volontairement

Dungeon 666 est un projet lancé directement par Pierre. Il ne figure pas au rail de
`GAMES/RAIL_REGISTER.md`, n'est pas déclaré dans `forge/oracles.json` (surface protégée) et
n'a pas de `game_contract.yaml` (schéma fermé, réservé au pipeline Forge). Ses oracles se
lancent localement : `node run-oracle.mjs`.
