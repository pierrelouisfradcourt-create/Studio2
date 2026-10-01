# Dungeon 666 — prototype jouable

Action-roguelite mobile : descendre les 666 étages de l'Enfer. Le combat s'inspire de Hades, le
butin de Diablo 1/2, les contrôles tactiles de Brawl Stars. Ce prototype sert d'abord à
**vérifier que le déplacement et le combat sont amusants**. Charte : [`00_CHARTER/CHARTER.md`](00_CHARTER/CHARTER.md).

`claim_verdict : NO_CLAIM_ALLOWED`. Les tests et les bots prouvent que le jeu **tourne** et
qu'il est **jouable**. Ils ne prouvent pas qu'il est **amusant** : ce verdict revient à Pierre,
manette ou téléphone en main.

## Jouer

| Où | Comment |
|---|---|
| **Téléphone, sans rien installer** | Ouvrir `dist/dungeon_666.html` (un seul fichier, ~300 Ko, fonctionne hors ligne). Le tenir en paysage. |
| **Téléphone sur le Wi-Fi local** | `node server.mjs` sur le PC, puis ouvrir l'adresse LAN affichée (`http://192.168.x.x:4666/`). |
| **Ordinateur** | `node server.mjs` puis <http://localhost:4666/>, ou double-clic sur `dist/dungeon_666.html`. |

Aucune dépendance : Node 18+ suffit pour le serveur et les tests. Playwright ne sert qu'aux tests navigateur.

### Contrôles

| Action | Tactile (paysage) | Clavier / souris | Manette |
|---|---|---|---|
| Se déplacer | pouce gauche n'importe où dans la moitié gauche (joystick flottant) | ZQSD / WASD / flèches | stick gauche |
| Attaquer (combo 3 coups) | gros bouton à droite ou n'importe où dans la moitié droite. **Tap** = visée auto, **glisser** = visée manuelle, **maintenir** = combo continu | clic gauche (vise la souris), J | X / RT |
| **Dash** (invulnérable) | gros bouton à gauche de l'attaque. Direction = joystick | Espace / Maj / K | A / LB |
| Lance infernale (compétence) | glisser puis relâcher pour viser, tap = auto. Revenir au centre annule | clic droit, L | B |
| Nova de cendres (gadget, 3 charges, rendues tous les 6 étages) | petit bouton en haut à droite du groupe | E | Y |
| Colère (Super, se charge en frappant) | bouton flamme quand il brille | F / R | RB |
| Pause, réglages | bouton ⏸ en haut à droite | Échap / P | Start |

**Ce qui fait le combat :**
- **Le dash d'abord.** Le dash annule la fin de n'importe quelle attaque et interrompt le gel d'impact. Une attaque en fin de dash coupe la ruée en **frappe de dash**. Enchaîner les coups demande de jouer une partie de leur récupération (30 % pour les coups 1-2, 60 % après le 3ᵉ) : le dash reste la sortie la plus rapide.
- **L'esquive parfaite paie.** Un coup évité grâce au dash remplit la jauge de Super et accélère la recharge du dash.
- **Rien ne fait mal sans prévenir.** Il n'y a aucun dégât de contact : chaque attaque ennemie est annoncée par une zone rouge qui se remplit.
- **L'environnement est une arme.** Un ennemi projeté contre un mur est sonné. Le Bélier qui rate sa charge contre un mur reste sonné longtemps : c'est le moment de punir.
- **Un ennemi sonné se relève en garde.** Pendant 1,5 s (petit écu au bout de sa barre de vie), un coup d'arme le blesse et le repousse mais ne le sonne plus. Compétences, gadgets, Supers et murs sonnent toujours. Sans cette règle, la Hache et le Maillet maintenus sur place sonnaient en boucle.

### Paramètres d'URL (playtest)

`?seed=123` partie rejouable · `?floor=18` aller directement au Gardien · `?god=1` invulnérable ·
`?autostart=1` sauter l'écran titre · `?tune=0` ignorer les réglages enregistrés.

Écran titre → **Arène d'essai** : des vagues sans fin, sans portes ni menus. C'est le bac à sable pour juger le déplacement et le combat en boucle (`?autostart=1&arena=1`).

En jeu : **pause → Réglages du feel**. Ce panneau règle en direct la vitesse, le dash, les dégâts, le gel d'impact, la visée auto, les télégraphes… Le bouton « Copier les réglages » produit le JSON à rapporter.

## Boucle V2 (demande de Pierre du 2026-10-01 : « GO prototype complet »)

**Ville → équipement/classe/armes/compétences → donjon → combats → bonus temporaires → Gardien → checkpoint/TP → nouvelle section.**

- **Ville de Dité** (écran titre → « Entrer dans Dité ») :
  - **Portail** : descendre depuis le dernier checkpoint ou se téléporter ; arène d'essai ; entraînement contre un Gardien déjà rencontré (`?lab=1` les montre tous).
  - **Classe**, **Armurerie**, **Coffre**, **Grimoire** et **Sanctuaire** : améliorations payées en Âmes.
  - **Labo du feel**.
- **Permanent** (profil, `src/sim/profile.mjs`) :
  - classe ;
  - armes (objets typés) ;
  - équipement et coffre (tout objet trouvé y est gardé) ;
  - compétences et gadgets ;
  - améliorations du Sanctuaire ;
  - Âmes ;
  - checkpoints.
- **Temporaire** (`game.run`) : bénédictions des 7 péchés (bonus, pouvoirs, améliorations, synergies).
- **Mort** : retour au **dernier checkpoint** (ou en Ville). Les bénédictions sont **remises à zéro**, tout le permanent est gardé, et Charon prélève une part de l'or. L'écran de mort montre ce qui est perdu et ce qui est gardé.
- **666 étages** : sections de **18** étages, avec un **Gardien** au 18ᵉ, soit 37 sections. Le Gardien ouvre un checkpoint et un point de téléportation. À la sortie, deux portes : « section suivante » (le build est conservé) ou portail vers la Ville. Les étages sont **composés** à partir d'un plan de section (`src/sim/sections.mjs`), de dispositions, du bestiaire et des thèmes des 9 Cercles + finale.
- **Classes** :
  - **Revenant** : Lame, Dagues ;
  - **Bourreau** : Hache, Maillet ;
  - **Chasseresse** : Arc, Arbalète. Elle tire à pas lents (moins vite qu'un diablotin) : pour fuir, il faut cesser de tirer ou dasher.

  Il y a 5 compétences, 5 gadgets, et un Super par classe (`src/sim/kits.mjs`). La mesure des 6 kits par les bots est dans [`reports/classes.md`](reports/classes.md).
- **Bestiaire** :
  - diablotin (mêlée rapide) ;
  - brute (mêlée lourde) ;
  - archer (distance) ;
  - bélier (chargeur) ;
  - **Pyromancienne** (zone : flaques persistantes) ;
  - **Nécromancien** (invocateur) ;
  - possédé (kamikaze) ;
  - 6 modificateurs d'élite.
- **Gardiens** : **Charon**, **Cerbère**, **Minos**, **Éphialte le Colosse**. Leurs patterns sont distincts, en rotation sur les 37 sections.
- **D5 / D8 / D9 restent ouvertes** : on les teste dans le **Labo du feel** (en Ville ou en pause).
  - frappe de dash : fin / tout le dash / après le dash ;
  - gel d'impact : global / **local** ;
  - mobilité du combo : ancré / mobile / fluide.

  La mesure par les bots est dans [`reports/lab.md`](reports/lab.md). Elle ne remplace pas le jugement en main.

## Reprise sous Godot

Décision de Pierre du 2026-10-01 : une version plus propre sous Godot. Le projet Godot vit dans
`GAMES/dungeon_666_godot/` ; ce prototype web reste la référence des règles.

La simulation (`src/sim/`) est isolée, déterministe à 60 Hz, sans DOM, et tous ses nombres sont dans des fichiers de données (`config.mjs`, `kits.mjs`, `foe_data.mjs`, `boss_data.mjs`, `town_data.mjs`). C'est la **spécification exécutable** à porter. Les tests `tests/*.test.mjs` décrivent les règles une par une ; ce sont les oracles à reproduire côté Godot. Le feel reste à valider en main **avant** le portage (charte).

## Code

```
src/
  core/      rng.mjs (mulberry32 seedé) · math.mjs (géométrie sans allocation)
             trig.mjs (sinus, cosinus… déterministes : la sim n'appelle jamais Math.sin & co)
  sim/       SIMULATION déterministe 60 Hz, sans DOM — game.mjs est le point d'entrée
             config.mjs (TOUS les nombres) · player · enemies · boss · combat · projectiles
             room · nav (pathfinding BFS) · run (étages, portes, choix, mort) · floors (666)
             loot · boons · stats · aim (visée assistée)
  input/     input.mjs — tactile multi-doigts, clavier/souris, manette → InputFrame
  render/    camera · render (monde) · hud · fx (particules, chocs) · palette
  audio/     sfx · synth · recipes — sons 100 % procéduraux (WebAudio)
  ui/        menus (DOM) · tuning (panneau de réglage du feel)
  main.mjs   boucle à pas fixe, câblage, persistance locale
tools/       bundle (→ dist/) · bots (politiques de jeu) · playtest (métriques) · shots · pw
             classes (mesure des 6 kits) · export_godot + traces + vecteurs/ (parité avec la version Godot)
```

Règle de dépendances : `sim` n'importe que `core`. `input` n'importe rien du jeu. `render`, `ui` et
`audio` lisent la sim sans jamais la modifier. Seul `main` câble l'ensemble. Une partie est
entièrement déterminée par sa graine et la suite de ses `InputFrame`.

## Oracles

```
node run-oracle.mjs        # tout : règles, propriétés, audio, bundle, solvabilité, classes, e2e, playtest
node --test tests/*.test.mjs   # 260 tests (dont tests/v2_*.test.mjs)
node solvability.mjs       # un bot bat la section 1 ; mesure la « valeur du dash »
node tools/classes.mjs     # les 6 kits joués par les bots → reports/classes.md (bloquant)
node e2e.mjs               # Chromium réel : doigts tactiles (CDP), clavier, souris, file://
node tools/playtest.mjs    # rapport de feel des bots → reports/playtest.md
node tools/shots.mjs       # le bot joue dans le navigateur : endurance + captures
node tools/bundle.mjs      # régénère dist/dungeon_666.html après toute modification de src/
```

Les tests vivent sous `tests/`, une surface protégée du studio (`forge/test_surfaces.yaml`) :
les créer est permis, les modifier après coup demande une gate Pierre. Ils lisent leurs valeurs
dans le tuning : régler le feel ne les casse pas, casser une règle oui.
