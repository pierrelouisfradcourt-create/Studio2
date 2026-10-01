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
| Nova de cendres (gadget, 3 charges par section) | petit bouton en haut à droite du groupe | E | Y |
| Colère (Super, se charge en frappant) | bouton flamme quand il brille | F / R | RB |
| Pause, réglages | bouton ⏸ en haut à droite | Échap / P | Start |

**Ce qui fait le combat :**
- **Le dash d'abord.** Le dash annule la fin de n'importe quelle attaque et interrompt le gel d'impact. Une attaque en fin de dash coupe la ruée en **frappe de dash**.
- **L'esquive parfaite paie.** Un coup évité grâce au dash remplit la jauge de Super et accélère la recharge du dash.
- **Rien ne fait mal sans prévenir.** Il n'y a aucun dégât de contact : chaque attaque ennemie est annoncée par une zone rouge qui se remplit.
- **L'environnement est une arme.** Un ennemi projeté contre un mur est sonné. Le Bélier qui rate sa charge contre un mur reste sonné longtemps : c'est le moment de punir.

### Paramètres d'URL (playtest)

`?seed=123` partie rejouable · `?floor=6` aller directement au Gardien · `?god=1` invulnérable ·
`?autostart=1` sauter l'écran titre · `?tune=0` ignorer les réglages enregistrés.

Écran titre → **Arène d'essai** : des vagues sans fin, sans portes ni menus. C'est le bac à sable pour juger le déplacement et le combat en boucle (`?autostart=1&arena=1`).

En jeu : **pause → Réglages du feel**. Ce panneau règle en direct la vitesse, le dash, les dégâts, le gel d'impact, la visée auto, les télégraphes… Le bouton « Copier les réglages » produit le JSON à rapporter.

## Structure des 666 étages

Section de 6 étages, le 6ᵉ est un **Gardien**. Le vaincre ouvre un **checkpoint** : à la mort,
on repart au début de la section suivante, avec son **équipement** mais sans ses **bénédictions**.
9 Cercles de 72 étages (Limbes → Trahison), puis la finale de 18 étages, « Le Trône ».
Après chaque salle, deux portes annoncent la récompense de la suivante : bénédiction (les 7
péchés capitaux), trésor, or, élite, soin. Le 5ᵉ étage propose un marchand ou un autel.

## Code

```
src/
  core/      rng.mjs (mulberry32 seedé) · math.mjs (géométrie sans allocation)
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
```

Règle de dépendances : `sim` n'importe que `core`. `input` n'importe rien du jeu. `render`, `ui` et
`audio` lisent la sim sans jamais la modifier. Seul `main` câble l'ensemble. Une partie est
entièrement déterminée par sa graine et la suite de ses `InputFrame`.

## Oracles

```
node run-oracle.mjs        # tout : règles, propriétés, audio, bundle, solvabilité, e2e, playtest
node --test tests/*.test.mjs
node solvability.mjs       # un bot bat la section 1 ; mesure la « valeur du dash »
node e2e.mjs               # Chromium réel : doigts tactiles (CDP), clavier, souris, file://
node tools/playtest.mjs    # rapport de feel des bots → reports/playtest.md
node tools/shots.mjs       # le bot joue dans le navigateur : endurance + captures
node tools/bundle.mjs      # régénère dist/dungeon_666.html après toute modification de src/
```

Les tests vivent sous `tests/`, une surface protégée du studio (`forge/test_surfaces.yaml`) :
les créer est permis, les modifier après coup demande une gate Pierre. Ils lisent leurs valeurs
dans le tuning : régler le feel ne les casse pas, casser une règle oui.
