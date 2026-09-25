# Bastion — TCG tactique sur plateau

Un jeu de cartes à collectionner joué **sur une grille 7×8**, comme aux échecs ou à Gloomhaven :
les créatures se déplacent, les sorts frappent des zones, le terrain a des effets, et chaque carte
coûte du mana. Tour par tour, contre un bot. Jeu web sans dépendance (lignée V2 : moteur pur +
rendu canvas + oracles node/Playwright).

```
node server.mjs          # http://localhost:4515  (?seed=42 pour une autre partie)
node run-oracle.mjs      # tests unitaires · propriétés · solvabilité · e2e navigateur
```

## Le fantasme

Tu poses un Recruteur Gobelin : une petite vague. Tu avances ton Seigneur de Guerre au milieu :
tes gobelins tapent à 2. L'adversaire Boule-de-Feu le paquet — et brûle sa propre case pour
quatre tours. Tu réponds Portail : ton Ogre saute au contact de sa tour. Il te Gèle l'Ogre.
Tu lui rends son Épée du Titan, tu la poses sur le Dragon qui arrive en Vol par-dessus le mur.
BOUM. C'est ce genre de séquence que le jeu cherche : **des situations à créer, puis à retourner**.

## Règles

**Objectif** — détruire la tour ennemie (20 PV). Ta propre tour tire 2 dégâts, au début de ton
tour, sur l'ennemi adjacent le plus menaçant.

**Tour** — au début : +1 mana max (plafond 10), mana rechargé, +1 par Fontaine occupée, une carte
piochée (deck vide = fatigue croissante sur ta tour : la partie finit toujours). Puis, dans
l'ordre que tu veux : jouer des cartes, déplacer, attaquer, utiliser une capacité, rendre un
équipement. `E` ou le bouton pour finir.

**Déploiement** — à 2 cases de ta tour, **ou à 1 case d'un héros allié** : les commandants portent
ta ligne de front. Une unité invoquée n'agit qu'au tour suivant (sauf *Célérité*).

**Déplacement** — orthogonal, à hauteur de son MV. **Zone de contrôle** (pattern Wesnoth cité) :
entrer au contact d'un ennemi arrête le mouvement. **Vol** survole rochers, unités, marais et
zones de contrôle. Attaquer clôt l'activation.

**Combat** — portée en distance de Manhattan (1 = mêlée). Le défenseur **riposte** s'il survit et
si l'attaquant est à sa portée : un archer à portée 2 frappe un chevalier sans riposte. *Provocation*
force à cibler le Golem. **Plancher de dégâts** (brique KB `sys-damage-floor`) : un coup inflige au
moins 1, l'armure ne crée jamais d'impasse.

**Terrain** (3 cartes symétriques par rotation, tirées par la seed)

| terrain | effet |
|---|---|
| Forêt | +1 armure à l'unité qui s'y trouve |
| Rocher | infranchissable (sauf en Vol, sans s'y poser) |
| Marais | y entrer arrête le déplacement |
| Brasier | 2 dégâts en fin de tour à son occupant non volant |
| Fontaine | +1 mana au début de ton tour si tu l'occupes |

Le terrain **bouge** : Boule de Feu laisse un Brasier 4 tours, Mur de Pierre dresse un Rocher
6 tours.

## Les cartes (deck de 30, identique pour les deux camps, mélangé par seed)

**Créatures** — Gobelin 1 · Recruteur Gobelin 2 (amène 2 Gobelins) · Loup 2 · Loup Alpha 4
(amène 2 Loups) · Archer 3 (portée 2) · Chevalier 3 · Assassin 3 (Célérité) · Golem de Pierre 4
(Provocation, 2/7) · Élémentaire de Feu 3 (portée 2) · Ogre des Profondeurs 5 (5/7, lent) ·
Dragon 7 (5/5, Vol) · Prêtresse 3 (soigne les adjacents en fin de tour).

**Héros / commandants** — une aura qui se déplace avec eux, une capacité active (`A`), et ils
étendent la zone de déploiement.

| héros | coût | aura (rayon) | capacité |
|---|---|---|---|
| Seigneur de Guerre 3/6 | 5 | alliés +1 ATQ (2) | Cri de ralliement, 2 : alliés +1 déplacement |
| Archimage 2/4, portée 2 | 4 | sorts visant l'aura −1 mana (2) | Étincelle, 1 : 1 dégât à portée 2 |
| Nécromancienne 2/5, portée 2 | 5 | un allié mort laisse une Ombre 1/1 (2) | Drain, 2 : 2 dégâts, se soigne 2 |
| Paladin 2/7 | 5 | alliés adjacents −1 dégât subi (1) | Bénédiction, 2 : bouclier sur un allié |

**Sorts** — Boule de Feu 4 (3 dégâts en 3×3, **alliés et tours compris**, Brasier au centre) ·
Éclair 2 (3 dégâts) · Portail Dimensionnel 2 (téléporte un allié à 3 cases) · Bouclier Temporel 1
(annule les prochains dégâts) · Mur de Pierre 2 · Soin 2 (+4 PV) · Gel 2 (la cible saute son tour
et ne riposte pas).

**Équipements** — pas de vol : **ils reviennent dans ta main quand le porteur meurt**, et tu peux
en rendre un à la main pour 1 mana (`U`) avant qu'il ne crève. Épée du Titan 3 (+3 ATQ,
Piétinement : ignore les zones de contrôle) · Couronne du Tyran 2 (+1 ATQ, +1 MV) · Arc Long 2
(+1 portée) · Bottes Ailées 1 (Vol). Deux par unité au maximum.

## Commandes

Clic sur une unité → cases bleues (déplacement), cibles rouges (attaque). Clic sur une carte ou
touche `1`–`7` → cases vertes (déploiement) ou cibles orange (sort, équipement). `A` capacité du
héros sélectionné · `U` rendre son équipement · `Échap` annuler · `E` / `Entrée` fin de tour.

## Architecture

```
cards.mjs       catalogue — données pures (coûts, stats, mots-clés, auras, capacités)
maps.mjs        3 gabarits 7×8, symétriques par rotation, terrain permanent / temporaire
engine.mjs      règles — PUR, déterministe (mulberry32), apply(action) -> {ok|error}, legalActions()
ai.mjs          bot glouton déterministe, une action à la fois
controller.mjs  machine à états de sélection (clics -> actions), surbrillances
layout.mjs      géométrie canvas partagée (clic -> case / carte)
input.mjs       touches + clics -> intentions neutres
render.mjs      canvas 2D, ne modifie jamais l'état
main.mjs        orchestration, window.__game / __game_debug (PLAYABLE_CONTRACT), bot animé
server.mjs      statique, sert aussi la brique KB réutilisée
```

Réutilisation : `knowledge_base/systems/combat/damage_floor.mjs` (importée telle quelle) ;
patterns cités `pat-damage-floor`, `pat-zone-of-control`.

## Preuves

- `logic.test.mjs` — une règle, un test (~70), y compris contrôleur, entrées, rendu, orchestration.
- `properties.test.mjs` — invariants sur des milliers d'actions légales aléatoires, conservation
  des cartes, déterminisme, terminaison bot contre bot.
- `solvability.mjs` — le bot doit gagner 100 % contre un adversaire passif ; bot contre bot doit
  toujours désigner un vainqueur (mesure rapportée : avantage du trait).
- `e2e.mjs` — Chromium réel : touche, clics sur carte / case / unité / bouton, tour du bot,
  défaite forcée, `#overlay`, `#restart`, victoire. Captures dans `e2e-shots/`.

## Hors périmètre (volontairement)

Multijoueur, collection/deckbuilding, animations, sons. Le temps réel du brief initial (lanes
Clash-Royale) a été **remplacé par le tour par tour sur grille** demandé par le titre du brief ;
les idées du brief (commandants à aura, équipements qui circulent, vagues, portail, bouclier,
objectif de mana au centre) sont toutes là.
