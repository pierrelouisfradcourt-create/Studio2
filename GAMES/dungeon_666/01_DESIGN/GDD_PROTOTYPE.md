<!--
  Spécification unifiée produite par le panel de conception de la session (6 rapports :
  GDD, chiffres, contrôles mobiles, juice, références, conventions), arbitrée par un agent
  « directeur de conception ». Elle est versée ici telle quelle, en PROPOSED. L'écart avec le
  code est tenu dans le tableau ci-dessous, et non en corrigeant la spec en silence.
-->

# État d'implémentation au 2026-10-01 (à lire avant la spec)

| Domaine | Implémenté | Écart assumé par rapport à la spec |
|---|---|---|
| Contrôles | Joystick flottant, attaque tap/glisser/maintien + zone d'attaque flottante, dash, Lance (glisser-relâcher, annulation au centre), gadget, Super, clavier/souris, manette, plein écran Android, déblocage audio iOS | Pas de presets de disposition A/B/C, pas d'option gaucher |
| Héros | Combo 3 coups (enchaînement après 30 % / 30 % / 60 % de la récupération, vitesse ×0,5 en attaquant), frappe de dash (y compris en coupant la fin du dash), esquive parfaite (+6 % Super, recharge −0,5 s, une fois par projectile et par dash), Lance (perce 3), Nova (3 charges/section, +1 par élite tué), Super | Super = **tourbillon** de 1,4 s (alternative de la spec) au lieu du slam + Fureur. Gel d'impact **global** plafonné par une réserve, au lieu d'un gel local |
| Ennemis | Diablotin, Archer, Brute, Bélier, Possédé ; élites Rapide/Blindé/Ardent ; jetons d'attaque (mêlée 2, tir 2) ; pathfinding BFS | Pas de poise ni de stagger par seuil ; pas de « zone d'équité » de spawn au-delà de la distance minimale |
| Boss | Charon, le Passeur : 3 phases, transitions invulnérables avec renforts et orbe de soin, slam ×3, anneaux à brèche (alerte maintenue entre les vagues), charge (double en phase 3), invocations (alerte violette, inoffensive) | Patterns différents de la spec (Coup de Rame, Lanternes, Traversée) ; pas d'icône du prochain pattern |
| 666 étages | Sections de 6, Cercles de 72, finale de 18, scaling L·B·C/L·D jusqu'à 666, checkpoints avec instantané du build (or à la reprise = min(instantané, or actuel)), « Réessayer le Gardien » depuis l'entrée de sa salle | Un seul modèle de Gardien, pas de « Seigneurs » tous les 18 étages |
| Progression | 7 péchés (21 bénédictions + 4 duos), butin 4 raretés (commun sans affixe), arme = dégâts de base W, armure = PV, légendaires à pouvoir, marchand, 4 autels | Pas de pitié de rareté, pas de reroll, pas de coffre « 1 parmi 3 » |
| Juice | Gel (plafonné à 0,075 s sur le Gardien), recul caméra directionnel, tremblement trauma² (≈ 9-36 Hz), zoom, flash, squash & stretch, particules SoA, pose de mort, ralentis, sons procéduraux, vibrations Android | Interpolation de rendu entre deux pas de sim (écrans 90-144 Hz) ; gel global et non local (D8) |

---

# Dungeon 666 : spécification unifiée du prototype « feel » (v1.0)

| Champ | Valeur |
|---|---|
| Statut | **PROPOSED**. Directeur de conception, 2026-10-01. Document de référence d'implémentation. Emplacement prévu : `GAMES/dungeon_666/01_DESIGN/GDD.md` (§10). |
| Fun, feel, équilibrage | **NO_CLAIM**. Les valeurs sont des points de départ que l'on règle en config sans toucher au code. Le verdict revient à Pierre (§9.3). |
| Sources arbitrées | Rapports GDD, NUMBERS, MOBILE, JUICE, REFS et CONVENTIONS. S'y ajoute l'état réel du dossier `GAMES/dungeon_666/`, qui existe déjà avec du code et des tests. Les tests existants sont des surfaces protégées : cette spécification est **compatible avec toutes leurs assertions** (liste au §10.4). |
| Temps | Simulation à pas fixe 60 Hz. **1 f = 1 tick = 16,67 ms.** La config stocke des secondes via `f(n) = n/60`, parce que les tests existants lisent `tuning.dash.duration` en secondes. La sim reconvertit en entiers avec `Math.round(s × 60)`. |
| Espace | **1 u = 1 px de référence.** La caméra montre 960×540 u en paysage (petit côté 540 u) et 540×960 u en portrait. Angles en degrés dans la config. |
| Notation | **W** = dégâts de base de l'arme portée (10 au départ). Une **clé** est un chemin dans `DEFAULT_TUNING` (`src/sim/config.mjs`). « Arbitrage » signale qu'il y avait désaccord entre rapports. |

---

## 1. Vision et piliers

**Vision.** Un damné, « le Revenant », refuse sa sentence et descend 666 étages vers l'Enfer en dansant entre les coups. Il lit le télégraphe, le traverse d'un dash et punit. Chaque section se termine par un boss qui devient un point de reprise.

**Mécanique centrale.** Lire le télégraphe → dasher dedans (i-frames) → punir (frappe de dash puis combo) → la jauge du Super monte → le build s'affine.

| # | Pilier | Ce que ça veut dire concrètement | Règle d'arbitrage |
|---|---|---|---|
| P1 | **Le dash est roi** | 0 f de verrouillage. Il annule presque tout et traverse les ennemis. L'esquive parfaite est récompensée. L'attaque après un dash est la meilleure attaque. | Entre puissance du dash et puissance de l'attaque statique, on renforce le dash. |
| P2 | **Lisibilité brutale** | Toute menace est télégraphiée au sol pendant au moins 24 f. Aucun dégât de contact. Aucun ennemi hors cadre n'attaque. Au plus 10 ennemis et 40 projectiles ennemis. | On retire de la complexité avant de retirer de la lisibilité. |
| P3 | **Chaque coup pèse** | Chaque impact déclenche gel, tremblement, flash, particules et son synthétisé. Le finisseur pèse plus lourd. | Un coup moins fort mais « gras » vaut mieux qu'un coup fort et plat. |
| P4 | **Un build en une section** | 3 à 4 choix en environ 5 min font apparaître une identité de build. | Peu de choix, chacun visible en jeu. |
| P5 | **Session courte** | Une section dure 4 à 6 min. La mort fait perdre au plus une section. | Pas d'énergie, pas de minuterie. |

| Échelle | Durée | Boucle |
|---|---|---|
| Seconde | 0,3 à 2 s | télégraphe → dash ou pas → frappe |
| Vague | 8 à 15 s | apparition → priorisation → nettoyage |
| Salle | 25 à 45 s | 3 vagues → récompense → choix de porte |
| Section | environ 4,7 min | 4 combats + antichambre + boss → Foyer (checkpoint) |
| Méta | plusieurs sessions | reprise au Foyer, équipement conservé |

---

## 2. Contrôles

### 2.1 Principe
- Le module input produit **un `InputFrame` immuable par tick** et la sim ne voit que ça. Le bot produit les mêmes frames et le replay les rejoue. Latence ajoutée : au plus 1 tick.
- Champs de l'`InputFrame` (noms existants conservés) : `moveX, moveY` (vecteur dans [-1,1]), `attack` (maintenu), `attackPressed` (front), `aimX, aimY` (visée manuelle de l'attaque, (0,0) = auto), `dashPressed`, `dashDirX, dashDirY` (optionnel, (0,0) = stick puis orientation), `skillPressed`, `skillAimX, skillAimY` ((0,0) = auto), `gadgetPressed`, `superPressed`.
- Commandes hors tick, journalisées avec le replay : `choose`, `respawn`, `buy`, `reroll`, `teleport`, `setView{orientation}`.

### 2.2 Tactile paysage

**Unité de layout.** `S` = petit côté du rectangle sûr, en px CSS. C'est la fenêtre moins `env(safe-area-inset-*)`.

| Contrôle | Rayon visuel (clé `input.layout.*`) | à S=293 | à S=360 | à S=412 |
|---|---|---|---|---|
| Socle du stick | `clamp(48, 0.16·S, 72)` | 48 | 58 | 66 |
| Bouton du stick | 0,42 × socle | 20 | 24 | 28 |
| Attaque | `clamp(36, 0.12·S, 52)` | 36 | 43 | 49 |
| Course de visée (drag max) | `clamp(56, 0.18·S, 80)` | 56 | 65 | 74 |
| Dash | `clamp(30, 0.095·S, 42)` | 30 | 34 | 39 |
| Compétence | `clamp(26, 0.085·S, 38)` | 26 | 31 | 35 |
| Super | `clamp(26, 0.085·S, 38)` | 26 | 31 | 35 |
| Gadget | `clamp(22, 0.07·S, 32)` | 22 | 25 | 29 |
| Pause (en haut à droite) | 22 fixe | 22 | 22 | 22 |

Règles de taille et d'espacement :
- Marge de touche +12 px autour de chaque bouton. Si deux zones de touche se recouvrent, le centre le plus proche l'emporte.
- Espace visuel entre boutons ≥ 14 px.
- Distance au bord sûr ≥ 16 px.
- Rien dans la bande HUD du haut, de hauteur `max(48, 0.15·H)`.

**Position des boutons.**
- Attaque : `x = droite_sûre − min(0.32·S, 140)`, `y = bas_sûr − min(0.27·S, 120)`.
- Les autres boutons sont sur un arc autour de l'attaque, à la distance `ρ = R_attaque + r_bouton + 14`. Les angles sont comptés avec 0° à droite et 90° en haut.
- `computeLayout` essaie les presets **A, puis B, puis C**. Il garde le premier qui respecte toutes les contraintes. Si aucun ne passe, il réduit les boutons d'action ×0,9 et recommence.
- Ces presets ont été vérifiés par recherche exhaustive sur les 9 fenêtres de référence. **Arbitrage :** le rapport MOBILE ne plaçait pas le Super. Aucun jeu d'angles unique ne tient sur toutes les fenêtres, d'où les trois presets.

| Preset | Dash | Compétence | Super | Gadget | Valide sur |
|---|---|---|---|---|---|
| A (défaut) | 204° | 146° | 90° | 40° | 734×343, 780×360, 863×360, 915×412, 1040×480, 1024×768 |
| B | 204° | 150° | 92° | 42° | 802×293, 852×393 (insets 59/59/21) |
| C | 208° | 140° | 88° | 38° | 568×320 |

Exemples de centres (x, y, rayon), mesurés :

| Fenêtre | Attaque | Dash | Compétence | Super | Gadget |
|---|---|---|---|---|---|
| 780×360 (A) | 665,263,r43 | 581,300,r34 | 592,214,r31 | 665,175,r31 | 728,210,r25 |
| 802×293 (B) | 708,214,r36 | 635,246,r30 | 642,176,r26 | 706,138,r26 | 762,166,r22 |
| 568×320 (C) | 466,234,r38 | 392,272,r30 | 405,182,r27 | 468,154,r27 | 525,188,r22 |

**Zones.**
- Zone de déplacement : `x < 50 %` de la largeur sûre, sous la bande HUD.
- Zone d'actions : `x ≥ 50 %`. Un toucher qui ne tombe sur aucun bouton devient une **attaque à origine flottante**.
- Ordre du hit-test : pause > dash > Super > gadget > compétence > attaque > zones.
- Aucun contrôle flottant dans les 20 px contre le bord physique, pour laisser passer les gestes système.

**Stick de déplacement (`input.move.*`).**
- Flottant : le socle apparaît au point de contact, recalé pour rester à ≥ R+4 px des bords de la zone. Si le doigt dépasse R, le socle glisse pour le suivre.
- Ancre fantôme à α 0,2 en `(gauche + min(0.30·S, 130), bas − min(0.30·S, 130))`.
- Zone morte radiale 0,12·R. **Vitesse pleine dès la sortie de la zone morte** (`analog: false`). Pas de crantage.
- Au relâchement : entrée à zéro immédiatement ; retour visuel à l'ancre en 150 ms.
- Option « fixe » : activation dans 1,6·R autour de l'ancre.
- Option gaucher `mirror` : inverse les deux côtés.

**Comportement par bouton.**

| Bouton | Déclenchement | Détails |
|---|---|---|
| Attaque | **À l'appui**, immédiat. Maintenir = enchaînement continu. | La direction est calculée à l'appui, mise à jour à chaque tick de startup, puis verrouillée à la 1re frame active. Un drag ≥ `0.25 × course` depuis le point de contact passe en visée manuelle (bande au sol blanche α 0,35). Revenir dans la zone morte repasse en auto. **Arbitrage :** les 3 ticks d'intention du rapport MOBILE sont supprimés ; le startup (5 f) sert de fenêtre d'intention sans latence. |
| Dash | **À l'appui**, front mémorisé. | Direction = stick hors zone morte, sinon orientation. Pas de swipe. |
| Compétence | Appui = visée ; **relâché = lancer**. | Tap (jamais passé en manuel) = lancer rapide auto. Drag ≥ 0,25·course = manuel, ligne de 520 u. Retour < 0,20·course = annulation (gris, croix), avec hystérésis de sortie à 0,25. Annulation = pas de recharge consommée. Un appui pendant la recharge n'est accepté que s'il reste ≤ 9 f, sinon retour « refusé ». |
| Super | **À l'appui**. | Non directionnel (slam centré sur le héros). Anneau de charge, pulse quand il est prêt. |
| Gadget | **À l'appui**. | Non directionnel (nova). Les charges sont affichées en pastilles. |

**Retours visuels des boutons.**
- Pastilles de charge : arcs à r+6 px, épaisseur 4 px, sur 120° en haut du bouton, 8° d'écart.
- Recharge : secteur noir α 0,55 qui balaie dans le sens horaire. Un chiffre `ceil` en secondes s'affiche si ≥ 1 s.
- Prêt : échelle 1 → 1,12 → 1 en 180 ms, plus un « ding ».
- Refusé : tremblement ±3 px pendant 120 ms, plus un « thunk ».
- Opacité : 0,35 au repos, 0,75 en action.

### 2.3 Tactile portrait (toléré)

Sur téléphone étroit, un arc ne tient pas (vérifié). On utilise donc une **grille de 2 rangées** alignée à droite, avec un espacement de 14 et une marge de 16 :
- Rangée 1 : `[dash][attaque]`. Le bas de l'attaque est à `bas − 16 − 8`.
- Rangée 2 : `[compétence][super][gadget]`. Le gadget est au-dessus de l'attaque, et la rangée est à 14 px au-dessus de la rangée 1.

Exemples mesurés :
- 360×640 : attaque 301,573 · dash 209,582 · compétence 174,481 · super 249,481 · gadget 319,481. Le groupe occupe `x ≥ 40 % W` et `y ≥ 70 % H`.
- 393×659 : attaque 330,588 · dash 231,598 · compétence 194,489 · super 275,489 · gadget 349,489.

Règles portrait :
- Zone de déplacement : `x < 40 % W` et `y > 50 % H`.
- Caméra : le héros est affiché à 38 % du haut.
- Un conseil « tournez l'appareil » s'affiche et peut être fermé.

### 2.4 Routage multi-touch (module input, aucune logique de jeu)
- Pointer Events. **Un `pointerId` possède au plus un contrôle**, et cette possession est figée jusqu'au relâchement (`setPointerCapture`). Au plus 4 pointeurs.
- `pointercancel`, `lostpointercapture`, `blur`, `visibilitychange`, `pagehide`, `resize`, `orientationchange` et `fullscreenchange` : tout relâcher, la compétence étant annulée.
- Canvas :
  - `touch-action: none`, `user-select: none`, `-webkit-touch-callout: none` ;
  - `preventDefault` sur `touchstart` et `touchmove` avec `{passive: false}` ;
  - `gesturestart` et `contextmenu` bloqués, ainsi que Ctrl+molette.
- Les boutons DOM des menus écoutent **`pointerup`**, jamais `click`.
- Backing store = taille CSS × `min(devicePixelRatio, dprCap)`. Le `getBoundingClientRect` est mis en cache et recalculé au resize.
- Détection du tactile : `matchMedia('(pointer: coarse)')` ou le 1er `pointerType`. Ne jamais se fier à `maxTouchPoints`.

### 2.5 Clavier et souris (`KeyboardEvent.code`, compatible AZERTY)

| Action | Touches |
|---|---|
| Déplacement | WASD (= ZQSD en AZERTY) et flèches, normalisés |
| Visée | Curseur souris (réticule dessiné, `cursor: none`) |
| Attaque | Clic gauche maintenu, vers le curseur. **J** = tap auto-visé. |
| Dash | **Espace**, Shift gauche ou K. Direction = touches, sinon vers le curseur. |
| Compétence | Clic droit : appui = visée vers le curseur, relâché = lancer, Échap pendant le maintien = annuler. **L** = lancer rapide auto. |
| Gadget | E |
| Super | R ou F |
| Valider | Entrée |
| Pause | Échap ou P |
| Plein écran | O |
| Debug | F1 couche d'entrée et hitboxes · F2 ralenti ×0,25 · F3 overlay de perf · F4 avance d'un tick (en pause) · F9 panneau de tuning |

Règles : ignorer `e.repeat`, `preventDefault` sur Espace, flèches et Tab, tout vider sur `blur`.

### 2.6 Manette (mapping « standard », lecture une fois par tick ; Should)

| Action | Bouton |
|---|---|
| Déplacement | Stick gauche, zone morte radiale 0,18, vitesse pleine à ≥ 0,85 |
| Visée | Stick droit : manuelle si > 0,35, sinon auto |
| Attaque | RT (b7, enclenche > 0,30, relâche < 0,20) ou X (b2) |
| Dash | A (b0) |
| Compétence | RB (b5) : maintien + stick droit = visée, relâché = lancer, B (b1) = annuler |
| Gadget | LB (b4) |
| Super | Y (b3) ou LT (b6) |
| Interagir | B (b1) hors visée |
| Pause | Start (b9) |

Tant que la manette n'a pas été « vue », afficher « appuyez sur un bouton ». Les contrôles virtuels apparaissent au 1er pointeur tactile et disparaissent à la 1re entrée clavier, souris ou manette.

### 2.7 Auto-visée (fonction pure `aim.mjs`, appelée par la sim et lue par le rendu)

1. **Candidats** : ennemis vivants et matérialisés, **avec ligne de vue** (les piliers bloquent), à une distance ≤ `aim.meleeRange = 160 u` pour l'attaque ou ≤ `aim.skillRange = 520 u` pour la Lance.
2. **Référence** : direction du stick si le joueur se déplace.
   - Si le joueur bouge, seuls les candidats dans **±90°** de la référence sont retenus (Lance : ±40°).
   - Si le joueur est immobile, aucun filtre d'angle.
3. **Score** (le plus bas gagne) : `d + W_ang·(1 − cos Δθ) − bonus`.
   - `W_ang = 80 u` en mouvement, **0 à l'arrêt** (on vise alors le plus proche, comme Brawl Stars).
   - Bonus : cible collante −40 u (24 f, gardée tant qu'elle reste à portée +10 %) ; ennemi en télégraphe −30 u ; élite −20 u.
4. **Aucune cible** : le coup part vers le stick, sinon vers l'orientation. C'est un coup dans le vide, comme dans Hades.
5. **Visée manuelle** : aimantation `aim.magnetDeg = 8°` vers une cible valide à portée.
6. **Lunge** : il s'arrête à `r_héros + r_ennemi + 4` u, sans traverser.
7. **Réticule** : un anneau sur la cible auto courante (rayon cible + 7 u, pulsation 4 Hz), toujours visible en combat. Il est jaune sur un élite.

**Arbitrage :** la formule cosinus et la ligne de vue viennent de MOBILE, les portées sont recalculées pour la mêlée réelle (portée 80 + lunge 24 + marge).

### 2.8 Tampon, priorités, matrice d'annulation

- Tampon universel `input.bufferTicks = 8 f` (133 ms). **Arbitrage :** valeur médiane entre 6 et 12, compatible avec le test « attaque pressée pendant un dash ».
- Pendant un gel d'impact, le tampon ne décrémente pas.
- Priorité si plusieurs entrées arrivent au même tick : **Dash > Super > Gadget > Compétence > Attaque**.

Légende : OUI = immédiat · OUI@tN = à partir du tick N de la phase · BUF = tamponné, exécuté dès que possible · NON = refusé (le tampon s'applique quand même).

| État courant | Dash | Attaque | Lance | Nova | Super |
|---|---|---|---|---|---|
| Libre / course | OUI | OUI | OUI | OUI | OUI |
| Attaque, startup | **OUI** (coup perdu) | BUF | BUF | OUI | OUI |
| Attaque, actif | **OUI** | BUF | BUF | OUI | OUI |
| Récupération avant chaîne | **OUI** | BUF | OUI | OUI | OUI |
| Récupération après chaîne | **OUI** | OUI (enchaîne) | OUI | OUI | OUI |
| Dash, t0–t5 | NON | BUF (devient Estoc à t6) | BUF | BUF | BUF |
| Dash, t6–t8 | **OUI** (chain-dash) | **OUI = Estoc** (coupe le dash) | OUI | OUI | OUI |
| Fenêtre Estoc (10 f après la fin du dash) | OUI | **Estoc** | OUI | OUI | OUI |
| Lance, startup (6 f) | OUI (annule, **pas de recharge**) | BUF | NON | OUI | BUF |
| Lance, récupération | OUI | OUI@t4 | NON | OUI | OUI |
| Nova, récupération (10 f) | OUI | OUI@t4 | OUI@t4 | NON | OUI |
| Super, startup (12 f, invulnérable) | NON | NON | NON | NON | NON |
| Super, récupération (12 f) | OUI@t0 | OUI@t4 | OUI@t4 | OUI@t4 | NON |
| Gel d'impact global | **OUI, annule le gel** | BUF | BUF | **OUI, annule le gel** | BUF |
| Recul subi | aucun verrou (le recul n'interrompt jamais) | | | | |

### 2.9 Premier geste, plein écran, audio, haptique

**Écran titre « TOUCHER POUR JOUER ».** Il est déclenché par `pointerup` (tactile) ou `keydown`/`mousedown`, et exécute dans l'ordre :
1. `audioCtx.resume()` et un buffer silencieux, **de façon synchrone**, avant tout `await` ;
2. `navigator.audioSession.type = 'playback'` si l'API existe ;
3. `requestFullscreen({navigationUI: 'hide'})` dans un try ;
4. `screen.orientation.lock('landscape')` dans un try, rejet ignoré.

Comportement ensuite :
- Sortie de plein écran : pause et bouton « Reprendre plein écran ».
- iOS : bouton muet en jeu et conseil « Ajouter à l'écran d'accueil ».

**Haptique** (Android, réglage activé par défaut, 1 appel au plus toutes les 90 ms) :

| Événement | Vibration |
|---|---|
| Dégât subi | 30 ms |
| Critique | 12 ms |
| Esquive parfaite | 15 ms |
| Kill d'élite | 20 ms |
| Kill de boss | [40, 30, 80] |

Jamais sur chaque coup ni sur chaque dash.

---

## 3. Kit du héros (un seul héros : le Revenant)

### 3.1 Stats de base (`player.*`)

| Clé | Valeur | Note |
|---|---|---|
| `maxHp` | 100 = `innateHp` 45 + armure de départ 55 | pas de régénération passive |
| `radius` (collision murs et piliers) / `visualRadius` / `hurtRadius` | 14 / 16 / **11 u** | hurtbox généreuse |
| `weaponBase` W | 10 (épée commune, ilvl 1) | |
| `critChance` / `critMult` | 5 % / ×1,75 | 1 tirage RNG `combat` par touche, toujours |
| `hurtIframes` | **30 f** (0,5 s), clignotement à 15 Hz | **Arbitrage :** entre 18 (GDD) et 36 (JUICE) : évite les doubles coups sans rendre l'encaissement viable. |
| Recul subi | 24 u sur 6 f, additif au mouvement, **n'interrompt aucune action** | aucun étourdissement du héros, jamais |
| Gel global quand le héros est touché | 5 f (événement majeur) | |
| Coups simultanés | au même tick, seul le plus fort s'applique | |
| Mort | PV ≤ 0 → état `dead` (chute 60 f, sim figée pour les ennemis) → mode `dead` (panneau « Jugement ») | |

### 3.2 Mouvement (`player.*`, profil « nerveux »)

| Clé | Valeur |
|---|---|
| `speed` | **300 u/s** (5 u/f). Traverse l'écran en 3,2 s. |
| `accelTime` | 5 f (83 ms), soit 3600 u/s² |
| `decelTime` | 3 f (50 ms), soit 6000 u/s² |
| `turnAccelMult` | ×1,5 si `v·v_voulu < 0` (demi-tour en environ 7 f) |
| Intégration | `v ← v + clampLen(v_voulu − v, a·dt)` |
| `moveMult` pendant les actions | voir §3.4. Lance : 0,4. Super : 0. |
| Collisions | cercle contre cercles et AABB, glissement tangent. Séparation héros/ennemis par masse inverse (héros 1, imp 0,5, archer 0,5, possédé 0,5, bélier 1, brute 2, boss immobile). |

**Arbitrage :** valeurs du profil A de NUMBERS, qui sont aussi celles du code actuel. Elles sont plus nerveuses que celles du GDD (280 u/s, 4 f), sans glissade.

### 3.3 Dash « Pas Fantôme » (`dash.*`)

| Clé | Valeur | Justification |
|---|---|---|
| `distance` | **165 u** | moyenne des rapports (150 à 170), environ 31 % de la hauteur de l'écran |
| `duration` | **9 f** (150 ms) | MOBILE, REFS et code actuel |
| `curve` (fraction par tick) | `[0.20, 0.18, 0.15, 0.12, 0.10, 0.08, 0.07, 0.06, 0.04]` (somme 1) | départ explosif |
| `iframes` | **10 f à partir du tick 0** (de t0 à t9, soit toute la durée + 1 f) | Arbitrage : couvre le dash plus 1 f de latence tactile. On ne perd pas les i-frames en attaquant (contrairement à Hades) ; l'Estoc démarre de toute façon à t6. |
| `charges` | **2** | Arbitrage : 3 charges plus le remboursement rendraient le jeu trivial (piège n°1 de REFS). La 3e charge vient du légendaire Ailes de Méphisto. |
| `recharge` | **54 f** (0,9 s) par charge, séquentiel ; le minuteur ne se met jamais en pause | |
| `chainFromTick` | t6 : un nouveau dash est possible dès le 7e tick (avec une charge) | compatible avec le test des charges |
| `exitSpeedFrac` | 0,5 × vMax dans la direction du dash | sortie fluide |
| `lockTicks` | 0 | |
| Direction | `dashDir` si fourni, sinon stick hors zone morte, sinon orientation. Jamais un vecteur nul. | |
| Collisions | traverse les ennemis. Murs et piliers : collision balayée et glissement. Le dash se termine si 2 ticks de suite avancent de moins de 25 % du nominal. | |
| `cancelsHitstop` | oui | test existant |
| Interdit | pendant le startup du Super | |

**Esquive parfaite** (`dash.perfectDodge*`).
- Déclencheur : un coup ennemi (hazard actif ou projectile) aurait touché la hurtbox pendant les i-frames **du dash**.
- Récompense : +6 % de jauge de Super et −30 f sur la recharge en cours.
- Une seule fois par `attackId`.
- Effets visuels et sonores : recharge interne de 30 f, onde cyan, carillon à 880 Hz, ralenti de présentation (§8.4).
- Un projectile n'est pas consommé quand il traverse les i-frames.
- **Arbitrage :** pas de « +1 charge » comme dans le GDD, trop fort avec la traversée.

**Estoc de dash** (frappe de dash, profil `dashStrike`).
- Une attaque saisie pendant le dash est tamponnée. Elle part à **t6** en coupant le reste du trajet, ou jusqu'à **10 f** après la fin du dash (`dash.strikeWindow`).
- Le dash **remet le combo à zéro**. L'Estoc compte comme le coup 1 : l'attaque suivante est H2.

### 3.4 Attaque principale « Lame de Cendre » : combo de 3 coups (`combo[]`, `dashStrike`)

| | H1 Entaille | H2 Contre-taille | H3 Tourbillon (finisseur) | Estoc de dash |
|---|---|---|---|---|
| Startup / actif / récupération (f) | 5 / 3 / 9 | 5 / 3 / 9 | 8 / 4 / 18 | 4 / 4 / 10 |
| Chaîne possible dès le tick de récupération | 3 (vers H2) | 3 (vers H3) | 10 (vers H1) | 3 (vers H2) |
| Dégâts | 1,0 W = **10** | 1,2 W = **12** | 2,2 W = **22** | 1,6 W = **16** |
| Portée (depuis le centre) / arc | 80 u / 120° | 80 u / 130° (miroir) | 96 u / 200° | 104 u / 80° |
| Lunge (3 dernières frames du startup) | 24 u | 24 u | 32 u | 40 u |
| Recul infligé (v0, frottement 12/s) | 300 u/s (environ 25 u) | 300 (25 u) | 720 (60 u) | 480 (40 u) |
| Puissance de stagger | 1 | 1 | 3 | 2 |
| Gel d'impact global | 3 f | 3 f | 6 f | 4 f |
| `moveMult` startup / actif / récupération | 0,5 / 0,2 / 0,6 | 0,5 / 0,2 / 0,6 | 0,3 / 0,1 / 0,4 | 0,3 / 0,2 / 0,5 |

Règles :
- Toucher un ennemi demande `dist ≤ portée + r_ennemi` et `|angle| ≤ arc/2 + atan(r_ennemi/dist)`.
- **1 touche par ennemi et par coup** (`hitId`). Tous les ennemis dans l'arc sont touchés (cleave).
- Maintenir le bouton enchaîne en continu. Le combo revient à H1 si aucune attaque n'est entrée dans les **12 f** après la fin de la récupération (`comboResetTime`).
- Vitesse d'attaque : startup et récupération sont divisés par `(1 + attackSpeed)`, arrondis avec un minimum de 1 f. L'actif est inchangé.

**Timeline en chaînage parfait.** Les impacts tombent aux frames 5, 16 et 30, et le cycle dure 44 f, soit 60 DPS théoriques. Avec les gels (12 f), l'horloge réelle donne impacts à f5, f19 et f36, un cycle de 56 f, soit **47 DPS** réels sur une cible.

**TTK calculés à l'étage 1** (premier appui jusqu'à la mort, gels inclus) :

| Imp (22 PV) | Archer (20) | Possédé (10) | Bélier (52) | Brute (90) | Brute élite (270) |
|---|---|---|---|---|---|
| 2 coups, 0,32 s | 2 coups, 0,32 s | 1 coup, 0,08 s | 4 coups, 1,02 s | 7 coups, 1,95 s | 19 coups, 5,7 s |

### 3.5 Compétence « Lance infernale » (`skill.*`)

| Clé | Valeur |
|---|---|
| Point d'engagement | Le cast de la sim commence à `skillPressed`. En tactile, c'est le relâché. |
| `castTime` (startup) / `recovery` | 6 f / 8 f. Le projectile part à la fin du startup. Un dash pendant le startup annule le lancer sans consommer la recharge. |
| `cooldown` | **240 f (4,0 s)**, compté à partir du départ du projectile |
| Projectile `speed` / `range` / `radius` | 900 u/s / 520 u / 12 u |
| `damage` | **3,0 W = 30**. Perce **3 cibles**, ×0,8 par cible suivante : 30 / 24 / 19. |
| Recul / stagger / gel | 240 u/s (environ 20 u) / puissance 2 / 3 f, sur la 1re cible seulement |
| Bloquée par | murs et piliers |
| `moveMult` | 0,4 |

**Arbitrage :** 30 dégâts (NUMBERS, code actuel) contre 16 (GDD). Un tir doit tuer un archer ou un imp de l'étage 1 pour avoir un vrai rôle contre les tireurs. Perce limitée à 3 (au lieu de 99) pour garder la mêlée centrale.

### 3.6 Gadget à charges « Nova de Cendres » (`gadget.*`)

| Clé | Valeur |
|---|---|
| Charges | max **3**. Remplies au début de chaque section et à chaque reprise au Foyer. **+1 par salle de combat nettoyée et +1 par élite tué**, plafond 3. |
| `minInterval` | 90 f (1,5 s) entre deux usages |
| Startup / récupération | **0 f** (la nova part au tick de l'appui ; bouton panique, test existant) / 10 f |
| `iframes` | 15 f à partir de l'appui |
| `radius` / `damage` | 150 u / 2,0 W = 20 |
| Recul | 900 u/s radial (environ 75 u) |
| `stun` | légers (imp, archer, possédé) **54 f** ; lourds (bélier, brute, élites) **30 f** ; boss : 0 (dégâts seuls, recul ×0) |
| Effets annexes | **détruit les projectiles ennemis dans 190 u** ; tout ennemi étourdi voit son télégraphe annulé |
| Gel / trauma | 5 f / +0,35 |

**Arbitrage :** nova instantanée (GDD, code actuel) plutôt que bombe lancée (NUMBERS). Le gadget sert de bouton panique façon Brawl Stars. Le gain +1 par salle évite que le joueur thésaurise.

### 3.7 Super « Jugement de Cendre » (`super.*`)

| Clé | Valeur |
|---|---|
| Jauge (`player.superCharge` ∈ [0,1]) | Pleine après **500 × hp_mult(étage)** dégâts effectifs (overkill exclu, dégâts du Super exclus). +6 % par esquive parfaite, +10 % par kill d'élite. Aucun gain pendant le cast. La jauge est conservée entre étages. |
| Startup | **12 f**, invulnérable, non annulable, aura qui monte, vitesse 0 |
| Slam (au tick 12) | rayon 220 u ; 6,0 W = **60** dégâts ; recul 840 u/s (environ 70 u) ; étourdissement 60 f (hors boss) ; puissance 5 ; détruit les projectiles ennemis dans 220 u ; gel 8 f ; trauma +0,5 ; flash blanc d'écran α 0,2 pendant 4 f |
| Récupération | 12 f. Dash dès t0, le reste dès t4. **Invulnérable du tick 0 au tick 24.** |
| Buff « Fureur » | **300 f** (5 s) : startup et récupération d'attaque ×0,8 (+25 % de vitesse d'attaque), déplacement +10 %, recharge du dash ×0,67 |
| Cadence visée | environ 1 Super par salle de combat, et 2 à 3 par boss |

**Arbitrage :** slam + Fureur, sur lesquels GDD et NUMBERS convergent : un moment lisible et unique, prolongé par un buff qui se sent. Le tourbillon actuel du code (« Colère », 1,4 s) devient l'alternative `super.mode = 'whirlwind'` (Could, utile pour un A/B). Jauge à 500 au lieu des 2000 dégâts du GDD : un test de feel doit faire vivre le Super souvent.

### 3.8 Formules de dégâts
- **Héros vers ennemi** : `max(1, round(W × multCoup × (1 + ΣA) × ΠM × crit × vuln × (1 − DR_cible)))`.
  - ΣA = somme additive des bonus en % (affixes et bénédictions simples), plafonnée à +150 %.
  - ΠM = multiplicateurs des duos.
  - crit = 1,75 + bonus.
  - vuln = la plus forte vulnérabilité active : brute en récupération ×1,25, étourdi ×1,5, fenêtre de Charon ×1,4, Charme ×1,3.
  - DR_cible : élite Blindé 0,4.
- **Ennemi vers héros** : `max(1, round(base × dmg_mult(étage) × multÉlite × multMod × (1 − DR_héros)))`, avec DR_héros plafonnée à 50 %.

---

## 4. Ennemis du prototype

### 4.1 Règles globales (`combat.*`, `enemies.*`)

1. **Aucun dégât de contact.** Tout dégât passe par une attaque télégraphiée **d'au moins 24 f** (`telegraph.minTicks`). Aucun scaling et aucun modificateur ne raccourcit un télégraphe.
2. **Zone d'équité.** Un ennemi ne peut **démarrer** un télégraphe que si son centre est dans le rectangle d'équité centré sur le héros.

   | Orientation | Demi-largeur | Haut | Bas |
   |---|---|---|---|
   | Paysage | 424 u | 214 u | 214 u |
   | Portrait | 214 u | 300 u | 230 u |

   L'orientation entre dans la sim par la commande `setView`, ce qui garde le déterminisme. La caméra le garantit visible : look-ahead ≤ 40 u, clamp à la salle (§8.5). Les tireurs exigent aussi la ligne de vue. **Arbitrage :** règle « hors cadre » du GDD rendue déterministe.
3. **Jetons** :
   - au plus **2** attaquants de mêlée en télégraphe ou en actif (imp, brute, possédé) ;
   - au plus **2** archers en visée ;
   - au plus **1** charge de bélier à la fois ;
   - au plus **40** projectiles ennemis (le boss compris).

   Sans jeton, un ennemi orbite à 100 ± 20 u à 0,7 × sa vitesse, et change de sens toutes les 90 ± 30 f.
4. **Stagger** : la puissance du coup doit dépasser la poise.
   - Poise : imp, archer et possédé 0 ; bélier 1 (2 en télégraphe ou en charge) ; brute 1 (3 en télégraphe) ; élite +1 ; boss ∞.
   - Hitstun par puissance : 1 → 10 f, 2 → 14 f, 3 → 20 f. La Nova et le Super imposent leurs propres étourdissements.
   - Un stagger interrompt le télégraphe, qui **repart en entier** ensuite.
   - Anti-enfermement : 3 staggers en 120 f donnent 60 f d'immunité.
5. **La mort annule les hazards en attente** (test existant). Seule exception : l'explosion posthume de l'élite Ardent.
6. **Apparition** :
   - cercle d'invocation **45 f** pendant lequel l'ennemi est intangible et non ciblable ;
   - puis 18 f de grâce (il peut bouger et être touché, mais pas télégraphier) ;
   - jamais à moins de 240 u du héros (320 u pour un archer), ni à moins de 60 u d'un mur ou d'un pilier.
7. **Recul** : `v ← v·exp(−12·dt)`, arrêt sous 5 u/s. Multiplicateur de masse : imp 1,4 · possédé 1,4 · archer 1,2 · bélier 0,7 · brute 0,5 · élite ×0,6 · boss 0.
8. **Wall slam** : si la vitesse de recul est ≥ **360 u/s** au contact d'un mur ou d'un pilier : dégâts 0,8 W, étourdissement 27 f, gel 3 f, trauma +0,15, 8 débris.
9. **Pas de pathfinding** : steering et glissement. Séparation entre ennemis de force 0,6.
10. **Soin à la mort** : un ennemi normal lâche une orbe de soin (+10 PV) avec 6 % de chances.

### 4.2 Archétypes (valeurs à l'étage 1 ; identifiants du code conservés)

| ID (nom) | Rôle, compétence testée | PV | Rayon | Vitesse | Dégâts | Télégraphe | Actif | Récupération | Cooldown | Coût | Or |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `imp` (Diablotin) | essaim de mêlée : gérer la foule, finisseur | 22 | 13 | 150 | 8 | **24 f**, cône 90° de rayon 70, direction verrouillée à f16 | 4 f (+20 u de lunge) | 30 f | 60 f | 1 | 1 |
| `archer` (Archer squelette) | tireur qui garde ses distances : se repositionner, couvert | 20 | 13 | 120 (fuite 140, strafe 70) | 9 | **30 f**, ligne de visée, verrouillée à f22 | flèche 380 u/s, r 9, durée 96 f | 18 f | 100 f | 2 | 2 |
| `charger` (Bélier) | charge en ligne : timing du dash, exploiter le décor | 52 | 18 | 110 (charge 720) | 16, recul 40 u | **42 f**, rectangle de largeur 44, verrouillé à f30 | charge ≤ 30 f (360 u) | 36 f si raté ; **mur : étourdi 72 f, ×1,5** | 120 f | 3 | 3 |
| `brute` (Brute) | zone lourde : punir, flanquer | 90 | 24 | 90 | 18, recul 60 u | **40 f**, cercle r 100 centré 50 u devant, verrouillé à f28 | 3 f | **54 f, « vulnérable » ×1,25** | 90 f | 4 | 4 |
| `exploder` (Possédé) | kamikaze : prioriser, frapper à distance | 10 | 12 | 210 | 16 (24 aux ennemis) | **36 f**, cercle r 90 centré sur lui, immobile | explosion, puis il meurt | — | — | 1 | 1 |

### 4.3 IA chiffrée

| ID | Comportement |
|---|---|
| imp | Poursuite. Au contact (centre à ≤ 60 u) avec un jeton et un cooldown prêt : télégraphe. Sinon orbite. |
| archer | Bande de distance 220 à 320 u, **et** dans la zone d'équité réduite de 20 u (il privilégie les décalages horizontaux en paysage). Sous 180 u : fuite à 140 u/s. Dans la bande : strafe à 70 u/s, inversion toutes les 90 ± 30 f. Il vise la position actuelle du héros, sans anticipation. Ligne magenta α 0,5 de 240 u, pleine au verrouillage. Il lui faut un jeton de tir et la ligne de vue. |
| charger | Tourne à environ 260 u. Charge si la distance est dans [140, 360] u, avec ligne de vue et jeton. Charge sans dégâts amis. Contre un mur ou un pilier : étourdi 72 f et vulnérable ×1,5 (événement `chargerWall`). Hyper-armure (poise 2) pendant le télégraphe et la charge. |
| brute | S'engage à ≤ 110 u. Pendant les 54 f de récupération, corps assombri et icône de fissure : fenêtre de punition. |
| exploder | Fonce. À ≤ 70 u (avec un jeton de mêlée) il s'arrête, gonfle et télégraphie. Il explose : 16 au héros, 24 aux ennemis dans 90 u, recul radial de 300 u/s. Tué avant la fin : rien n'explose. |

### 4.4 Élites (champions façon Diablo, `elite.*`)

| Clé | Valeur |
|---|---|
| Pool | `archer`, `charger`, `brute` (ni imp ni possédé) |
| Multiplicateurs | PV ×**3,0** · dégâts ×1,25 · taille ×1,25 · cooldowns ×0,85 · recul subi ×0,6 · poise +1 · or ×5 |
| Télégraphes | inchangés (règle 1) |
| Nombre de modificateurs | 1 aux Cercles 1–3 ; 2 aux Cercles 4–6 ; 3 aux Cercles 7–9 et dans l'Abîme |
| Visuel | contour et aura or #FFB627 pulsant à 2 Hz, icône couronne, nom « Archétype + épithète du modificateur » (ex. « Brute ardente »), icône du modificateur |
| Récompenses | 1 objet Magique ou mieux, orbe +20 PV, +10 % de Super, +1 charge de Nova, or ×5 |
| Salle d'élite | 2 vagues : élite + 40 % du budget restant, puis les 60 % restants |

| Modificateur | Effet | Contre-jeu | Statut |
|---|---|---|---|
| Rapide (éclair, #FFE14D) | déplacement ×1,35 ; récupération et cooldown ×0,75 ; **télégraphe inchangé** (corrige `windupMult` du code actuel) | dasher plus souvent | Must |
| Blindé (bouclier, #8FA8FF) | dégâts subis ×0,6 ; recul ×0,25 ; poise +1 | Super, finisseurs | Must |
| Ardent (flamme, #FF8C1A) | à sa mort : télégraphe 42 f, cercle r 110, 18 dégâts | s'écarter après le kill | Must |
| Vampirique · Téléporteur · Multitir (archer ×3, ±15°) | voir le rapport GDD | | Should |

### 4.5 Boss de section : **Charon, le Passeur** (tier Gardien G01, `boss.charon.*`)

| Clé | Valeur |
|---|---|
| PV | `1450 × hp_mult(étage)`, soit **1997 à l'étage 6** et 2738 à l'étage 12 |
| Rayon / vitesse | 36 u / 120 u/s (×1,15 en P3) |
| Poise / recul | ∞ / immunisé |
| Gel quand il est touché | ×0,5, plafond 3 f |
| Nova sur le boss | dégâts seulement |
| Arène | standard (§6.1), 2 piliers-lanternes r 40 à (centre ±300, centre) |
| Intro | 90 f sans attaque (carton de nom, zoom) |
| Phases | P1 100 → 66 %, P2 66 → 33 %, P3 33 → 0 % |
| Transition de phase | 90 f invulnérable, projectiles effacés, rugissement (trauma 0,8), 1 orbe +15 PV lâchée, renforts : P2 = 4 imps ; P3 = 2 archers + 2 possédés |
| Pause entre patterns | P1 60 f · P2 48 f · P3 36 f |
| Sélection | P1 A 50 / B 50 · P2 A 30 / B 35 / C 35 · P3 A 25 / B 30 / C 45. **Jamais deux fois de suite le même.** Icône du prochain pattern au-dessus de la tête. |
| Mort | gel 12 f, ralenti ×0,25 pendant 1 s, trauma 1,0, flash. Coffre (Rare 75 % / Légendaire 25 %), orbe de bénédiction (offre post-boss), or 120 × L(étage), brasier du **Foyer** |

| Pattern | Télégraphe | Détail | Dégâts (base étage 1, × dmg_mult) | Récupération | Variantes |
|---|---|---|---|---|---|
| **A. Coup de Rame** | 40 f, cône 140° de rayon 230, verrouillé à f28 | Marche jusqu'à 160 u (au plus 90 f de marche). Actif 6 f. Recul 60 u. | 18 (23 à l'étage 6) | 48 f, **vulnérable ×1,4** | P2 : second balayage re-visé, télégraphe 30 f, dégâts ×0,8. P3 : A enchaîné directement avec C. |
| **B. Lanternes d'âmes** | 36 f (lanterne qui se charge, son montant) | Anneaux de 12 balles (14 positions, trou de 2 positions ≈ 51°), 220 u/s, r 10, durée 132 f, un anneau toutes les 45 f | 8 par balle (10 à l'étage 6) | 36 f | P1 : 2 anneaux. P2 : 3, trou décalé de +30° par anneau. P3 : 4 + tir visé triple (±12°, 300 u/s, télégraphe 24 f). |
| **C. Traversée de la Barque** | 42 f, ligne de largeur 72 jusqu'au mur (600 u max), verrouillée à f30 | Charge à 780 u/s. **Contre un mur ou un pilier : étourdi 90 f, vulnérable ×1,5.** Recul 80 u. | 20 (26 à l'étage 6) | 40 f | Apparaît en P2. P3 : double charge (2e télégraphe de 30 f après 24 f de pause). |

Chaque pattern teste une compétence : A = punir, B = traverser au dash ou trouver le trou, C = esquiver puis exploiter les piliers, renforts = prioriser.
- **Should** : Charon « enragé » à l'étage 12, avec C disponible dès P1 (P1 A 40 / B 30 / C 30).
- **Arbitrage :** Charon (GDD) plutôt que Cerbère (NUMBERS) ou le Gardien actuel : il colle au thème du Passeur à l'entrée des Limbes. PV calés sur 60 à 90 s de combat, avec un DPS effectif d'environ 30 à 40.

### 4.6 Ordre d'introduction dans la section 1

| Étage | Nouveau | Leçon |
|---|---|---|
| 1 | imp | bouger, combo, premier dash sur un télégraphe |
| 2 | + archer | se repositionner, Lance |
| 3 | + bélier, + possédé | esquive au bon moment, prioriser |
| 4 | + brute (élites possibles dès l'étage 3) | flanquer, punir |
| 5 | antichambre (sans combat) | préparer le boss |
| 6 | Charon | synthèse |

Un archétype introduit à son étage est garanti au moins une fois dans la vague 1.

---

## 5. Structure des 666 étages

### 5.1 Décision : sections de 6 étages, 111 boss, 9 Cercles + Abîme

**Arbitrage :** c'est l'option A du GDD, qui correspond aussi au squelette de l'option 4 de NUMBERS et au code et aux tests existants. Elle est retenue contre la section de 18 étages de REFS. C'est la seule à tenir 4 à 6 min par section et à limiter la perte à une mort à une section.

Formules (`floors.*`, module `floors.mjs`) :
- `section = ceil(f/6)` (1 à 111) ; `indexInSection = f − 6·(section−1)` (1 à 6) ; boss ssi `indexInSection = 6`.
- `circle = ceil(f/72)` pour f ≤ 648 ; sinon 10, la Finale « L'Abîme » (étages 649 à 666, 3 sections).
- `checkpointAfterBoss(b) = b + 1`. Foyers = [1, 7, 13, …, 661].

### 5.2 Les trois tiers de boss (111 combats)

| Tier | Étages | Nombre | Format |
|---|---|---|---|
| Gardien | multiples de 6, hors 72k et hors 654, 660, 666 | 99 | 2 à 3 patterns, 60 à 90 s. Production : modèles + modificateurs. |
| Seigneur de Cercle | 72, 144, …, 648 | 9 | 3 patterns, 3 phases, faits main |
| Lieutenant | 654 (Béhémoth), 660 (Léviathan) | 2 | faits main |
| Final | 666 (Lucifer) | 1 | 4 patterns, 3 phases |

Le prototype n'implémente que Charon. Aux autres étages-boss, Charon est réutilisé avec le scaling (Won't : contenu des 110 autres).

### 5.3 Cercles (biomes)

| # | Cercle | Étages | Teinte du sol (luminance ≤ 20 %) | Péché mis en avant (+50 % de poids d'offre) | Seigneur |
|---|---|---|---|---|---|
| 1 | Limbes | 1–72 | #1A1A22 (brume gris-bleu) | neutre | Minos (72) |
| 2 | Luxure | 73–144 | #22141E | Luxure | Cerbère (144) |
| 3 | Gourmandise | 145–216 | #1A1E12 | Gourmandise | Plutus (216) |
| 4 | Avarice | 217–288 | #221C10 | Avarice | Phlégyas (288) |
| 5 | Colère | 289–360 | #220E0E | Colère | Les Érinyes (360) |
| 6 | Hérésie | 361–432 | #1E1210 | Paresse | Le Minotaure (432) |
| 7 | Violence | 433–504 | #240C0C | Orgueil | Géryon (504) |
| 8 | Fraude | 505–576 | #141A22 | Envie | Antée (576) |
| 9 | Trahison | 577–648 | #121A22 (glace) | mélange | Judas (648) |
| F | L'Abîme | 649–666 | #0E0A0E | mélange | Béhémoth (654), Léviathan (660), **Lucifer (666)** |

Le prototype ne rend que les Limbes. Les teintes servent dès qu'on démarre à un autre étage (Should, coût quasi nul). Le compteur « Étage N/666 · Cercle » reste toujours affiché.

### 5.4 Foyers, téléportation et mort

| Élément | Règle |
|---|---|
| Foyer | Il apparaît après la mort d'un boss, sous forme de brasier dans l'arène. Il ajoute `b+1` à `meta.checkpoints`, soigne entièrement, remplit la Nova et ouvre un panneau : « Descendre » (étage b+1), et « Téléporter » vers tout Foyer débloqué (Should). Le Foyer 0 (étage 1) existe d'office. |
| Mort | Chute 60 f, puis mode `dead`. Panneau « Jugement » avec la liste des Foyers débloqués (le plus profond par défaut) ; `#restart` relance au plus profond. |
| Ce qui se perd | **Les bénédictions, et 50 % de l'or porté** (`economy.deathGoldKeep = 0.5`). Jauge de Super remise à 0. |
| Ce qui se garde | **L'équipement**, les Foyers débloqués et le meilleur étage. PV au maximum et Nova pleine à la reprise. |
| Rattrapage (Should) | En reprenant à la section s ≥ 2 : `min(3, s−1)` offres de bénédiction Rare+ avant la 1re salle. |
| Grâce (Should) | Dès la 3e mort consécutive dans la même section : −10 % de dégâts ennemis par mort supplémentaire, plafond −30 %, remis à zéro au boss. |
| Sauvegarde (Should) | `localStorage` `dungeon666.meta.v1` (Foyers, meilleur étage, équipement), écrit à chaque Foyer et à chaque entrée d'étage. Chaque accès est dans un try/catch. |

**Arbitrage :** équipement gardé et bénédictions perdues (REFS R15). Cette règle est déjà figée par le test protégé « mort ». La perte est nette sans être punitive : le loot Diablo persiste, le build Hades se reconstruit.

### 5.5 Scaling (NUMBERS, adopté tel quel ; `floors.*`)

```
L(f)  = 1 + 0.05·(f−1)                  // niveau d'objet
B(f)  = 1 + 2·(1 − e^(−(f−1)/100))       // saturation du build, asymptote 3
C(f)  = 1 + 0.5·(f−1)/665                // dérive de difficulté, +50 % à l'étage 666
S(f)  = 1 − e^(−(f−1)/150) ;  D(f) = 1 + 0.6·S(f)
hp_mult(f)  = L·B·C     dmg_mult(f) = L·D     speed_mult(f) = 1 + 0.10·S(f)
budget_mult(f) = D(f)   gold/price_mult = L(f)
PV et dégâts = max(1, round(base × mult)) ; télégraphes constants
```

| Étage | 1 | 4 | 6 | 7 | 12 | 30 | 72 | 333 | 666 |
|---|---|---|---|---|---|---|---|---|---|
| hp_mult | 1,000 | 1,221 | 1,377 | 1,458 | 1,888 | 3,764 | 9,666 | 64,39 | 153,99 |
| dmg_mult | 1,000 | 1,164 | 1,275 | 1,331 | 1,616 | 2,708 | 5,579 | 27,01 | 54,56 |
| speed_mult | 1,000 | 1,002 | 1,003 | 1,004 | 1,007 | 1,018 | 1,038 | 1,089 | 1,099 |

PV / dégâts concrets par étage :

| Étage | imp | archer | possédé | bélier | brute | Charon |
|---|---|---|---|---|---|---|
| 1 | 22/8 | 20/9 | 10/16 | 52/16 | 90/18 | 1450 |
| 6 | 30/10 | 28/11 | 14/20 | 72/20 | 124/23 | 1997 |
| 12 | 42/13 | 38/15 | 19/26 | 98/26 | 170/29 | 2738 |

- Super requis : 500 à l'étage 1, 689 à l'étage 6, 944 à l'étage 12.
- Risque : le scaling n'est calibré que jusqu'à l'étage 12. Au-delà, ce sont des hypothèses à valider par bot aux étages 30 et 72.

### 5.6 Durées

| Poste | Durée |
|---|---|
| Combat F1 / F2 / F3 / F4 | 30 / 35 / 40 / 45 s |
| Antichambre F5 | 20 s |
| Boss | 75 s |
| Transitions (6 × 3 s) | 18 s |
| Panneaux de choix (4 × 5 s) | 20 s |
| **Section** | **≈ 283 s (4,7 min)** |
| Descente complète | ≈ 8,7 h hors morts |

Cible : médiane de section 4 à 6 min. Si elle dépasse 6 min, baisser `room.budgetBase` de 15 %.

---

## 6. Flux de salle

### 6.1 Arène (`room.*`)
- Taille totale 1328×848 u avec `wallPad` 24, soit un intérieur de **1280×800 u**.
- Le héros entre par le sud, en (cx, bas − 80), orienté vers le nord. Les portes sont sur le mur nord.
- Dispositions (`room.layouts`, tirées dès l'étage 2, l'étage 1 est toujours `vide`) :

| Disposition | Poids | Contenu |
|---|---|---|
| `vide` | 25 | aucun obstacle |
| `deux_piliers` | 30 | piliers r 40 en (cx ± 280, cy) |
| `quatre_piliers` | 25 | piliers r 36 en (cx ± 300, cy ± 170) |
| `mur_central` | 20 | rectangle 360×36 centré, passages de chaque côté |

- Les piliers bloquent les déplacements, les projectiles des deux camps et la ligne de vue.
- La récompense apparaît au centre si l'endroit est libre, sinon au point libre le plus proche (spirale). Le test (f) vérifie qu'elle est atteignable.

### 6.2 Chronologie d'une salle de combat

| Tick | Événement |
|---|---|
| 0 | Entrée, portes verrouillées (runes) |
| 0–36 | Respiration |
| 36 | Vague 1 : cercles d'invocation (45 f), échelonnés de 0 à 12 f |
| 81+ | Matérialisation, puis 18 f de grâce |
| Vague N+1 | dès qu'il reste ≤ 2 vivants (invocations comprises), ou **720 f** après la vague N |
| Dernier kill | gel 8 f + ralenti de présentation, puis 30 f |
| Nettoyée | récompense posée, portes **allumées** avec l'icône de la salle suivante et **fermées tant que la récompense n'est pas prise** (test). Prise → `doorsOpen`. |
| Porte | toucher une porte ouverte : fondu de 150 ms, étage suivant |

### 6.3 Budget, vagues, apparitions (`room.*`, `wave.*`)
- `budget = round((budgetBase 20 + budgetPerIndex 4 × (indexInSection − 1)) × D(f))`, soit **20 / 24 / 28 / 32** aux étages 1 à 4.
- Coûts : imp 1, possédé 1, archer 2, bélier 3, brute 4, élite 8.
- 3 vagues réparties 30 / 35 / 35 %. `maxAlive = 10`. Le pool de chaque étage est celui du §4.6, avec un tirage pondéré par coût sur le RNG `gen`.
- Salle d'élite : budget ×0,6, plus l'élite.

| Étage | Budget | Exemple (vagues 1 / 2 / 3) | PV environ |
|---|---|---|---|
| 1 | 20 | 6 imps / 7 imps / 7 imps | 440 |
| 2 | 24 | 4 imps + 1 archer / 3 imps + 2 archers / 4 imps + 2 archers | 460 |
| 3 | 28 | 1 bélier + 4 imps + 1 possédé / 1 bélier + 1 archer + 3 imps + 1 possédé / 2 archers + 4 imps + 2 possédés | 600 |
| 4 | 32 | 1 brute + 4 imps + 1 archer / 1 bélier + 1 archer + 4 imps + 1 possédé / 1 brute + 1 bélier + 1 archer + 1 imp | 740 |

### 6.4 Plan d'une section

| Étage | Type | Récompense ou portes |
|---|---|---|
| F1 | combat | **Bénédiction garantie** (famille tirée). Pas de portes spéciales. |
| F2 | combat (récompense = porte choisie) | portes tirées, **élite interdit** |
| F3, F4 | combat ou élite | portes tirées |
| F4 → F5 | — | portes **fixes : Marchand ou Autel** (test) |
| F5 | antichambre, sans combat | porte du boss **visible et ouverte dès l'entrée** (test) |
| F6 | boss | coffre + bénédiction post-boss + Foyer |

### 6.5 Portes et récompenses (modèle Hades ; `doors.*`)
- 2 portes (80 %) ou 3 (20 %). Les récompenses d'un même jeu de portes sont toujours **distinctes**.
- Chaque porte affiche l'icône de la récompense et, pour une bénédiction, un anneau de la couleur de la famille.

| Récompense de porte (F2–F4) | Poids | Contenu |
|---|---|---|
| Bénédiction (losange, anneau de famille) | 38 | offre de 3 cartes de la famille annoncée |
| Trésor (coffre) | 22 | 1 objet (tableau des drops au §7.3) + 20 or |
| Or (pièce) | 14 | `(50 + 5·indexInSection) × L(f)` |
| Élite (crâne cornu) | 14 | salle d'élite ; récompense = objet Magique ou mieux (au §7.3) |
| Soin (cœur) | 12 | +30 % des PV max |

Contraintes :
- Au plus 1 élite par section aux sections 1 à 3, 2 ensuite.
- **Pitié** : si aucune bénédiction n'a été prise depuis F1 au moment de générer les portes de F3 ou de F4, une porte « Bénédiction » est forcée.
- Famille annoncée : tirage uniforme parmi les familles actives, ×1,5 pour les familles déjà possédées, ×1,5 pour la famille d'emphase du Cercle.

### 6.6 Types de salles dans une section (prototype)

| | F1 | F2 | F3 | F4 | F5 | F6 |
|---|---|---|---|---|---|---|
| Combat | 100 % | 100 % | environ 84 % | environ 84 % | — | — |
| Élite | — | 0 | environ 16 % (au plus 1 par section) | environ 16 % | — | — |
| Marchand / Autel | — | — | — | — | au choix du joueur (50/50 si bot aléatoire) | — |
| Boss | — | — | — | — | — | 100 % |

Le pourcentage d'élite est la probabilité qu'au moins une porte d'élite soit proposée avec 2 ou 3 portes, multipliée par environ 0,6 de choix joueur. Bénédictions attendues : 1 (F1) + environ 1,3 (portes) + 1 (boss) + 0 à 1 (marchand ou autel), soit **3 à 4 par section** (P4).

---

## 7. Progression du prototype

### 7.1 Couches

| Couche | Durée de vie | Statut prototype |
|---|---|---|
| Bénédictions (Hades) | jusqu'à la mort | Must : 3 familles, 12 bénédictions + 1 duo. Should : Avarice (4) + 2 duos. |
| Équipement (Diablo) | **persistant** | Must : 3 emplacements, 4 raretés, 15 affixes, 3 légendaires. Should : 3 légendaires de plus. |
| Or | 50 % perdu à la mort | Must |
| Âmes, hub méta | — | Won't |

### 7.2 Bénédictions : les 7 péchés comme familles

- **Familles actives** (`boons.enabledFamilies`) : Colère, Luxure, Gourmandise (Must), Avarice (Should). Orgueil, Envie et Paresse restent dans les données mais sont désactivées. **Arbitrage :** il faut moins de familles pour qu'un build apparaisse en 4 salles (GDD : 2 + 1 ; code : 7).
- **Raretés** :

  | Rareté | Multiplicateur | Poids normal | Poids après boss |
  |---|---|---|---|
  | Commun | ×1,0 | 70 | 0 |
  | Rare | ×1,4 | 25 | 70 |
  | Épique | ×1,8 | 5 | 30 |

  Valeurs arrondies à 0,1. **Arbitrage :** milieu des fourchettes Hades.
- **Emplacements exclusifs** : `attack`, `dash`, `skill`, `gadget`, `super`, 1 bénédiction chacun. Une nouvelle remplace l'ancienne, avec la mention « remplace X ». Les `passive` s'empilent, 4 au plus.
- **Offre** : 3 cartes de la famille de la porte, sans doublon. Une bénédiction déjà possédée peut revenir en « Amélioration » (rareté +1, exclue si déjà Épique). Un duo éligible remplace la 3e carte avec 60 % de chances. Relance : Could.
- **Cumul** : les bénédictions simples sont additives (ΣA), les duos multiplicatifs (ΠM).

| ID | Famille (couleur UI) | Emplacement | Effet (Commun) | Rare / Épique |
|---|---|---|---|---|
| `lame_ardente` | Colère #D93A3A | attack | les coups enflamment : 6 dégâts/s pendant 180 f (1 tick par 30 f) | 8,4 / 10,8 |
| `elan_de_haine` | Colère | dash | Estoc +40 % de dégâts et +1 puissance de stagger | +56 % / +72 % |
| `cendre_rouge` | Colère | super | slam +35 % de dégâts, Fureur +120 f | +49 % / +63 % |
| `furie` | Colère | passive (`damageMult`) | +12 % de dégâts | 16,8 / 21,6 % |
| `baiser_fugace` | Luxure #E04A86 | attack | +12 % de vitesse d'attaque | 16,8 / 21,6 % |
| `pas_de_velours` | Luxure | dash | recharge du dash −20 % | −28 / −36 % |
| `charme` | Luxure | skill | la Lance rend vulnérable : +30 % de dégâts subis pendant 240 f | 42 / 54 % |
| `desir` | Luxure | passive | après une esquive parfaite : +25 % de dégâts pendant 180 f | 35 / 45 % |
| `sang_devore` | Gourmandise #8BBE3A | attack (`lifesteal`) | vol de vie 3 % (au plus 3 % des PV max par coup) | 4,2 / 5,4 % |
| `ruee_vorace` | Gourmandise | dash | un kill dans les 60 f après un dash soigne 3 PV | 4,2 / 5,4 |
| `banquet` | Gourmandise | super | le Super soigne 8 PV + 2 par ennemi touché (bonus plafonné à +10) | 11,2 / 14,4 de base |
| `voracite` | Gourmandise | passive (`maxHpBonus`) | +20 PV max (soin immédiat équivalent) | 28 / 36 |
| `main_avide` | Avarice #E0A82E (Should) | attack | +8 pts de critique sur l'attaque ; chaque critique rapporte 1 or | 11,2 / 14,4 |
| `pillage` | Avarice | gadget | Nova +25 % de rayon ; chaque ennemi tué par elle a 25 % de chances de rendre 1 charge (au plus 1 par 180 f) | rayon +35 / +45 % |
| `fortune` | Avarice | passive (`critChance`) | +6 pts de critique | 8,4 / 10,8 |
| `dime` | Avarice | passive (`goldFindMult`) | +35 % d'or | 49 / 63 % |

| Duo | Condition | Effet (fixe) | Statut |
|---|---|---|---|
| `fievre_dansante` | 1 Colère + 1 Luxure | après une esquive parfaite, le prochain Estoc fait ×2 et son arc passe à 360° | **Must** (signature du build « Danseur ») |
| `boucherie` | Colère + Gourmandise | un kill au finisseur H3 explose (r 90, 1,0 W) et soigne 2 PV | Should |
| `festin_dor` | Avarice + Gourmandise | chaque kill soigne 3 PV et rapporte 2 or | Should |

Builds cibles pour les tests de diversité :
- **Danseur** : `desir` + `elan_de_haine` + `pas_de_velours` (+ duo) ;
- **Brute** : `furie` + `cendre_rouge` + `lame_ardente` ;
- **Glouton** : `voracite` + `sang_devore` + `banquet`.

Les effets en arène des bénédictions utilisent la **palette joueur** (blanc, cyan, or pâle). La couleur de famille sert à l'interface (cartes, portes, anneaux à 30 % au plus), jamais à un effet saturé rouge ou magenta.

### 7.3 Loot façon Diablo (`loot.*`)

**Raretés.** Le nombre d'affixes est fixe par rareté (test existant).

| Rareté | Couleur | Affixes | Pouvoir | Multiplicateur de base | Qualité du tirage `q` | Recyclage |
|---|---|---|---|---|---|---|
| Commun | #D8D4CC | 0 | non | ×1,00 | — | 5 or |
| Magique | #6F8CFF (◇) | 2 | non | ×1,08 | u | 20 |
| Rare | #FFE14D (◆) | 3 | non | ×1,16 | max(u1,u2) | 40 |
| Légendaire | #FF8C1A (★) | 3 | **1** | ×1,25 | max(u1,u2,u3) | 100 |

Les valeurs de recyclage sont multipliées par L(ilvl).

**Emplacements.**
- Poids de tirage : arme 35, armure 30, talisman 35.
- Arme : `W = 10 × L(ilvl) × multRareté`.
- Armure : `PV de base = 55 × L(ilvl) × multRareté`.
- Talisman : pas de base, jamais Commun.
- `ilvl` = étage (+1 sur un élite, +2 sur un boss).

**Affixes** (aucun doublon sur un objet). `valeur = min + (max − min)·q` ; les valeurs plates sont multipliées par L(ilvl).

| Emplacement | Stat (`id`) | Plage | Plafond cumulé |
|---|---|---|---|
| Arme | `damageMult` | +6 à 12 % | ΣA ≤ +150 % |
| Arme | `attackSpeedMult` | +5 à 10 % | +60 % |
| Arme | `critChance` | +3 à 6 pts | 60 % |
| Arme | `critMult` | +15 à 35 pts | ×3,0 |
| Arme | `dashStrikeMult` | +10 à 20 % | — |
| Arme | `lifesteal` | +1 à 3 % | 10 % (au plus 3 % des PV max par coup) |
| Armure | `maxHpBonus` | +10 à 24 (plat) | — |
| Armure | `armor` (réduction) | +3 à 7 % | 50 % |
| Armure | `moveSpeedMult` | +3 à 7 % | +25 % au total |
| Armure | `healOnKill` | +1 à 2 (plat) | — |
| Armure | `dashRechargeMult` | −6 à −12 % | −40 % |
| Talisman | `skillCooldownMult` | −8 à −15 % | −40 % |
| Talisman | `superChargeMult` | +10 à 25 % | — |
| Talisman | `goldFindMult` | +15 à 35 % | — |
| Talisman | `critChance` | +2 à 5 pts | 60 % |
| Talisman | `damageMult` | +4 à 8 % | ΣA ≤ +150 % |

**Pouvoirs légendaires.**

| Pouvoir | Emplacement | Effet | Statut |
|---|---|---|---|
| Ailes de Méphisto | talisman | +1 charge de dash (3), recharge du dash +15 % | Must |
| Fendoir du Damné | arme | H3 libère une onde de 160 u vers l'avant, 1,0 W | Must |
| Linceul de Cendre | armure | une esquive parfaite déclenche une explosion r 110, 2,0 W | Must |
| Œil de Mammon | talisman | +1 charge de Nova max ; 8 % de chances sur kill de rendre une charge | Should |
| Cœur de Braise | armure | le dash laisse une traînée de feu de 60 f, 0,8 W par 30 f | Should |
| Lame d'Azazel | arme | 25 % de chances d'éclair en chaîne, 1,2 W, 2 rebonds sur 200 u | Should |

**Drops** (RNG `loot`).

| Source | Chance | C / M / R / L |
|---|---|---|
| Ennemi normal | 2 % | 60 / 32 / 7 / 1 |
| Élite | 100 % | 0 / 50 / 40 / 10 |
| Coffre de porte Trésor | 100 % | 10 / 50 / 32 / 8 |
| Boss | 100 % | 0 / 0 / 75 / 25 |
| Stock du marchand | — | 0 / 60 / 35 / 5 |

- **Pitié** : après 10 drops qualifiants (élite, trésor, boss) sans légendaire, le suivant en est un.
- **Ramassage** : au contact, un panneau s'ouvre (la sim se met en pause, mode `choice`) avec « Équiper » ou « Recycler (+N or) » et les écarts de stats en vert ou rouge. Un Commun moins bon que l'objet porté est recyclé automatiquement (option activée par défaut).

### 7.4 Or et marchand (`economy.*`)

| Source d'or (× L(f)) | Valeur |
|---|---|
| imp, possédé / archer / bélier / brute | 1 / 2 / 3 / 4 |
| Élite | ×5 de sa base |
| Bonus de salle nettoyée | 8 |
| Porte Or | 50 + 5·indexInSection |
| Coffre Trésor | +20 |
| Boss | 120 |
| **Estimation par section** | **environ 300 or** |

| Stock du marchand (F5) | Prix (× L(f), arrondi) |
|---|---|
| 1 bénédiction (famille active tirée) | Commun 70 · Rare 120 · Épique 180 |
| 1 objet | Magique 80 · Rare 160 · Légendaire 400 |
| Fiole de sang (+35 % des PV max) | 40 |
| Charge de Nova (+1, plafonnée) | 50 |
| Relance du stock | 25, puis +25 par relance dans la visite |

Objectif : 2 achats par visite. Achat atomique, or toujours ≥ 0.

### 7.5 Événements (Autel, F5)

| ID | Choix A | Choix B |
|---|---|---|
| `autel_sang` | payer 25 % des PV max (nécessite ≥ 30 %) pour une offre de bénédiction Rare+ | partir |
| `fontaine` | +40 % des PV | +1 charge de Nova |
| `coffre_maudit` | objet Rare garanti, −20 PV | le laisser |
| `mammon` | 40 or pour une bénédiction d'Avarice (remplacé par la fontaine si Avarice est désactivée) | prier : +25 or |
| `sanctuaire_frenesie` (Should) | +20 % de vitesse d'attaque et +10 % de déplacement jusqu'à la fin du boss | — |

### 7.6 Soins

| Source | Soin |
|---|---|
| Orbe sur kill normal (6 %) | +10 |
| Orbe d'élite | +20 |
| Orbe de transition de phase du boss | +15 |
| Porte Soin | +30 % des PV max |
| Fontaine | +40 % |
| Fiole | +35 % |
| Foyer | 100 % |

Les PV ne dépassent jamais le maximum.

---

## 8. Juice et lisibilité

### 8.1 Frontière sim / présentation
- **Gel d'impact = gel global de la SIM** (`game.hitstop`) : le temps de jeu ne s'écoule pas. Dash et Nova le coupent. **Arbitrage :** modèle GDD et code actuel, figé par les tests. Il est déterministe, le bot le voit, et les projectiles gèlent aussi (aucune touche injuste pendant un gel).
- **Ralenti = horloge de présentation** : l'accumulateur reçoit `realDt × timeScale`. La suite de ticks reste identique pour le bot et le replay.
- Shake, kick, zoom, flash, squash, particules, nombres et sons sont **dérivés des événements** de la sim, jamais de son état interne.
- L'aléa des effets passe par un `fxRng` hors sim, exclu du hash.

### 8.2 Gel d'impact (`hitstop.*`, en f)

| Événement | Gel | Événement | Gel |
|---|---|---|---|
| H1 / H2 touche | 3 | Kill normal | +2 |
| Estoc | 4 | Wall slam | 3 |
| H3 | 6 | Critique | +2 |
| Lance (1re cible) | 3 | Cibles multiples | +1 par cible supplémentaire, plafond 8 |
| Nova | 5 | Coup sur un boss | ×0,5, plafond 3 |
| Slam du Super | 8 | Début de dash | 0 |

Événements **majeurs** : héros touché 5 · kill d'élite 6 · dernier ennemi de la salle 8 · changement de phase du boss 10 · kill du boss 12.
- Pas d'addition : `gel = max(restant, nouveau)`.
- **Budget** : au plus 12 f gelés par fenêtre glissante de 60 pas pour les gels normaux. Au-delà, le gel demandé est tronqué. Les événements majeurs passent outre mais comptent dans la fenêtre.
- Le recul est différé au dégel.
- Pendant le gel, la cible tremble le long de l'axe du coup (signe inversé à chaque tick, amplitude 2 u qui décroît jusqu'à 0, ×1,3 sur un critique). C'est un décalage de rendu seulement.

### 8.3 Tremblement, kick, zoom, flash, squash

**Trauma** (Eiserloh) :
- `trauma += add` (borné à [0,1]) ; décroissance linéaire **1,8/s** en temps réel.
- `s = trauma² × shakeScale` ; décalage max **20 u**, rotation max 2,5°, bruit lissé à 22 Hz.
- Les sources joueur sont plafonnées à 0,55.

| Événement | Trauma ajouté |
|---|---|
| Kill normal | +0,10 |
| Estoc | +0,10 |
| H3 | +0,15 |
| Wall slam | +0,15 |
| Nova | +0,35 |
| Explosion (au contact) | +0,5 × (1 − d/r) |
| Super | +0,5 |
| Kill d'élite | +0,5 |
| **Héros touché** | **+0,6** |
| Slam ou charge du boss (près) | +0,7 |
| Changement de phase | +0,8 |
| Kill du boss | 1,0 |

**Kick** directionnel (u) :

| Coup dans le vide | H1 / H2 | Estoc | H3 | Lance (opposé à la visée) | Super | Héros touché |
|---|---|---|---|---|---|---|
| 2 | 4 | 5 | 6 | 3 | 9 | 10 |

Somme plafonnée à 16 u, retour exponentiel λ = 16/s.

**Zoom punch** : H3 1,02 pendant 120 ms ; kill d'élite 1,04 pendant 200 ms ; kill du boss 1,12 tenu pendant le ralenti.

**Flash** :
- Ennemi : 2 f blanc pur (sprite pré-rendu), puis 2 f blanc à 50 %.
- Boss : 50 % seulement, au plus 1 flash par 4 f.
- Héros : 3 f rouge #FF2A2A, puis clignotement 1 / 0,35 à 15 Hz pendant les i-frames.
- Écran : Super, blanc α 0,2 pendant 4 f ; kill du boss, α 0,35 pendant 80 ms. Les deux sont désactivés si `prefers-reduced-motion`, qui met aussi `shakeScale` à 0,5. Les réglages proposés pour `shakeScale` sont {0 ; 0,5 ; 1}.

**Squash & stretch** (rendu seul, aire conservée) :

| Moment | Étirement (axe / perpendiculaire) | Tenue et retour |
|---|---|---|
| Départ du dash | 1,35 / 0,74 | 3 f, retour λ = 25/s |
| Fin du dash | 0,82 / 1,22 | 4 f |
| Coup lancé | 1,18 / 0,85 | 3 f |
| Préparation du héros | 0,90 / 1,11 | pendant le startup |
| Ennemi touché | 0,78 / 1,28 | ressort ω = 35, ζ = 0,45 |
| Ennemi en télégraphe | gonflement 1,0 ↔ 1,12 à 8 Hz, corps orange #FF8A3D pendant 2 f au début | toute la préparation |
| Apparition | 0 → 1,15 → 1 | 250 ms, easeOutBack |

Le loot suit une parabole de 36 u avec un rebond. Aimant à or : rayon 112 u, vitesse max 800 u/s.

### 8.4 Ralenti (horloge de présentation, `slowmo.*`)

| Déclencheur | `timeScale` | Tenue | Retour |
|---|---|---|---|
| Dernier ennemi de la salle | 0,35 | 350 ms | 150 ms |
| Kill du boss | 0,25 | 1000 ms | 400 ms |
| Mort du héros | 0,30 | 800 ms | fondu |
| Esquive parfaite | 0,5 | 250 ms | 100 ms |

- Pas de nouveau ralenti avant 3 s, sauf pour le boss.
- Pendant un ralenti : passe-bas du bus SFX à 2,5 kHz, musique à −6 dB.

### 8.5 Caméra (`view.*`)
- Suivi : `cam += (cible − cam)·(1 − e^(−9·dt))`.
- Look-ahead **plafonné à 40 u** (contrainte de la zone d'équité) : déplacement `moveDir × 40 × |v|/vMax` ; visée manuelle `aimDir × 40` ; souris `0,15 × (souris − héros)`. Lissage λ = 4/s, figé pendant un dash.
- Vue de base : petit côté 540 u. Le héros est centré en paysage et à 38 % du haut en portrait.
- Zoom « foule » ×0,92 si au moins 7 ennemis sont à moins de 420 u (λ = 2/s). Dézoomer est toujours équitable.
- Boss : zoom ×0,9 et biais `0,3 × (boss − héros)` plafonné à 60 u. Intro : zoom ×1,1 pendant 60 f.
- Confinement à la salle élargie de 34 u ; si la salle est plus petite que la vue sur un axe, centrage sur cet axe.
- Ordre de calcul : cible → lissage → confinement → kick → shake.
- Changement de salle : caméra placée directement, fondu de 150 ms. Rendu interpolé `lerp(prev, cur, acc/tick)`.

### 8.6 Particules (pool SoA alloué au démarrage, aucune allocation dans la boucle)

| Qualité q | Particules | Fantômes | Nombres | Décals par salle | Ambiance | Additif | Émission | `dprCap` | `renderScale` |
|---|---|---|---|---|---|---|---|---|---|
| 3 desktop | 1200 | 6 | 40 | 128 | 50 | oui | 1,0 | 2,0 | 1,0 |
| **2 mobile (défaut)** | **450** | 5 | 32 | 64 | 25 | oui | 1,0 | 2,0 | 1,0 |
| 1 | 250 | 4 | 24 | 48 | 10 | oui | 0,7 | 1,5 | 1,0 |
| 0 | 120 | 3 | 16 | 32 | 0 | non | 0,45 | 1,0 | 0,85 |

**Niveau de départ** : `pointer: fine` → q3 ; mobile → q2 ; `hardwareConcurrency ≤ 4` ou `deviceMemory ≤ 3` → q1.

**Adaptation automatique** :
- Baisse : sur une fenêtre de 2 s, travail moyen > 10 ms ou p90 de l'intervalle rAF > 20 ms. Recharge 3 s.
- Hausse : travail < 5 ms et p90 < 17,5 ms pendant 10 s. Une hausse annulée en moins de 10 s bloque les hausses pour la session.
- Délestage, dans l'ordre : ambiance → poussière → sang ×0,5 → étincelles ×0,6.
- **Jamais dégradés** : télégraphes, projectiles ennemis, flash, gel, audio.

| Type | Nombre | Vie | Vitesse (u/s) | Taille (u) | Couleur |
|---|---|---|---|---|---|
| Étincelle d'impact | 6 (H3 10, critique 14) | 6–13 f | 360–720, cône ±35° | trait v×0,025 s, épaisseur 2 | #FFFFFF → #FFE6A0, additif |
| Anneau d'impact | 1 | 7 f | — | r 7 → 32, trait 4 → 0 | #FFFFFF |
| Ichor | coup 3 / kill 10 | 21–36 f | 135–315 | 3–5 ; 30 % deviennent des décals | #8E0F1F → #4A0710 |
| Cendres (archer) | coup 4 / kill 14 | 36–60 f | 45–180, montée 68 u/s² | 2–4,5 | #9A8F88 → #3A3433 |
| Éclatement de mort | flash r 45 (5 f) + 12–18 éclats | 18–30 f | 225–495 | 4 | couleur de l'ennemi + blanc |
| Traînée de dash | 1 fantôme tous les 2 f + 6 poussières au départ | 11 f / 18 f | 0 / 90–180 | sprite | #3DF2E0 α 0,5 → 0, additif |
| Onde de Nova | anneau + 24 | 8 f | 0 → 150 u | trait 10 → 0 | #B8FBFF |
| Slam du Super | anneau + 60 + poussière | 10 f | 0 → 220 u | — | #FFFFFF / #B8FBFF |
| Cercle d'invocation | 1 + 8 braises | 45 f | braises 90 vers le haut | r 40, rotation 90°/s | #FF3B1F → #FFB627 à l'apparition |
| Poussière de pas | 1 toutes les 10 f si v > 60 % | 21 f | 22–45 | 5 → 11 | #6B5A55 α 0,25 |
| Éclat de loot (Rare+) | 1 toutes les 15 f | 36 f | montée 45 | 3 | couleur de rareté |
| Brume ambiante (Limbes) | continue | 3–6 s | montée 18–40 | 1,5–3 | #8A93A8 α 0,2–0,4 |
| Débris de mur | 8 | 24 f | 180–360 | 4 | #5A4A44 |

Dessin regroupé par mode de mélange, puis par couleur : un seul `beginPath` et un seul `fill` par couleur, alpha ramené à 4 niveaux. Les glows sont des sprites radiaux pré-rendus de 64 px.

### 8.7 Nombres, indicateurs, HUD

**Nombres de dégâts.** Atlas pré-rendu, jamais de `fillText` par frame.

| Type | Couleur | Taille (u) | Vie | Pop |
|---|---|---|---|---|
| Normal | blanc, contour noir | 18 | 33 f | 1,4 → 1 en 80 ms |
| Critique | #FFC93D « ! » | 28 | 48 f | 2,0 → 1 en 120 ms |
| Reçu | #FF4A4A | 20 | 42 f | — |
| Brûlure (DoT) | #FFA05A α 0,8 | 14 | agrégé par 30 f | — |
| Soin / or | #6CFF8E « + » / #FFD23F « +N » | 17 / 14 | — | — |

- Montée 112 u/s, frottement 4/s, décalage horizontal ±11 u (`fxRng`).
- Plusieurs coups sur la même cible en moins de 250 ms ne forment qu'une étiquette dont la somme se met à jour, avec un re-pop 1,25 → 1.

**Indicateurs hors écran.**
- Triangle à 24 px + inset sûr du bord, contour noir de 2 px : ennemi 14 px #FF3B3B, élite 18 px #FFB627, boss 22 px + crâne.
- Alpha 1 jusqu'à 180 u hors cadre, puis jusqu'à 0,4 à 720 u.
- Pulsation 1 → 1,3 à 6 Hz si l'ennemi télégraphe.
- Fusion des indicateurs à moins de 12° d'écart (« ×N »), au plus 8.
- Un ennemi caché sous un pouce (rectangle des boutons + 24 px, ou disque du stick) reçoit un marqueur dessiné au-dessus.

**HUD.**
- Bande haute : barre de PV cyan avec segment blanc de PV perdus (reste 350 ms puis se vide en 300 ms) ; « Étage N/666 · Limbes » au centre ; or et pause à droite.
- Barre du boss en haut au centre, avec le nom et des traits à 66 % et 33 %.
- Pastilles de dash sous l'anneau au sol du héros et autour du bouton.
- Sous 25 % de PV : vignette pulsée à 1 Hz (α 0,15 à 0,30) et battement de cœur.
- Barres de PV ennemies visibles après le 1er dégât, cachées 3 s plus tard.

### 8.8 Palette (hex, par rôle)

| Rôle | Couleur | Règle |
|---|---|---|
| Vide / sol | #0B0607 / #1C1012 → #2E1A1A (teinte de Cercle au §5.3) | saturation ≤ 40 %, aucune teinte de gameplay dans le décor |
| Murs / piliers | dessus #3A2626, face #120A0B / #2A1C1C, liseré #5A3A34 | |
| **Héros** | **#3DF2E0** + liseré blanc 2 u + anneau au sol α 0,35 (r 27 u) | seule teinte froide saturée (contraste 13,2:1) |
| Attaques et Lance du héros | #B8FBFF, formes **allongées** | |
| Corps ennemis | imp #B5474E · archer #C9A894 · bélier #8C5A3C · brute #7A4A52 · possédé #8E6A86 (cœur blanc pulsé) ; contour #0A0506 3 u ; liseré #FFD9C2 α 0,5 ; yeux et armes #FFB15C | contour et liseré obligatoires |
| Charon | robe #2B2F3A, crâne #C9C2B0, flammes des lanternes #9A7CFF | |
| Élite | aura et contour #FFB627 à 2 Hz, couronne ; icônes de modificateur #FFE14D / #8FA8FF / #FF8C1A | |
| **Télégraphes** | **#FF4A1C** : bord plein 3 u + remplissage α 0,15 + forme intérieure qui grandit (α 0,40, linéaire) ; bord blanc 1 f à 100 % ; effacement en 6 f. La forme est exactement celle de la hitbox. | contraste 5,5:1 |
| Visée d'un tireur | ligne #FF3DB8 α 0,5, puis 0,9 au verrouillage | |
| **Projectiles ennemis** | anneau **#FF3DB8** + **cœur blanc** + contour sombre 2 u, **ronds**, r ≥ 8 ; jamais additifs, toujours au-dessus des particules | |
| Danger persistant | hachures #FF4A1C α 0,35 | distinct d'un télégraphe |
| Pickups | or #FFD23F · soin #6CFF8E · bénédiction #C77DFF | |
| Loot | #D8D4CC / #6F8CFF / #FFE14D / #FF8C1A, faisceau vertical de 70 u (Rare) ou 135 u (Légendaire) + icône | |
| Boutons | attaque #EDE6DA · dash #3DF2E0 · compétence #B8FBFF · Super #FFC93D · gadget #6CFF8E | |

**Daltonisme** : une information n'est jamais codée par la seule teinte. Rond contre allongé, bord contre hachures, couronne pour l'élite, icône et hauteur de faisceau pour la rareté.

**Ordre de dessin** : sol (avec décals) → télégraphes et dangers → ombres → loot → ennemis triés par y → héros → arcs et Lance → particules (normales puis additives) → **projectiles ennemis** → barres et nombres → espace écran (vignette, indicateurs, HUD, contrôles, overlay de perf).

### 8.9 Sons WebAudio (100 % synthétisés)

**Infrastructure.**
- Un seul `AudioContext`, débloqué au 1er geste.
- Graphe : voix → bus `sfx`/`ui`/`music` → master → compresseur (−16 dB, knee 10, ratio 6, attaque 2 ms, release 150 ms).
- 3 variantes pré-rendues par recette via `OfflineAudioContext` ; à l'exécution, `BufferSource` avec `playbackRate = 2^(cents/1200)`.
- Le télégraphe et le battement de cœur restent en synthèse directe.
- Enveloppes `0.0001 → pic → exponentialRamp(0.0001)`.
- 20 voix sur mobile, 32 sur desktop.
- Un même son relancé en moins de 30 ms n'est pas rejoué ; la voix en cours gagne +1,5 dB (max +4).
- Priorités : dégât reçu > boss > télégraphe > kill > coup > loot > dash > or > coup dans le vide.
- `suspend()` quand la page est cachée. Volume par défaut 0,6.

| Événement de sim | Recette | Niveau |
|---|---|---|
| `hit` (H1 / H2) | bruit passe-bande 1800 Hz (70 ms) + sinus 170 → 55 Hz (110 ms) + carré 1100 → 350 Hz (25 ms) ; ±150 cents, **+100 cents par rang dans le combo** | −6 dB |
| `hit` (H3, critique) | sinus 140 → 45 Hz (160 ms) + bruit passe-bas 1,2 kHz ; critique : triangle 1320 Hz (« ting ») | −4 dB |
| `swing` (dans le vide) | bruit passe-bande balayé 500 → 2600 Hz (110 ms) | −16 dB |
| `dash` | bruit passe-haut 300 + passe-bas 1 → 6 kHz (120 ms) + sinus 260 → 520 Hz (70 ms) | −10 dB |
| `dash` refusé / `cancel` | carré 110 Hz, 35 ms, « tok » | −12 dB |
| `dodge` (esquive parfaite) | carillon sinus 880 Hz + 1320 Hz, 300 ms | −6 dB |
| `kill` | sinus 130 → 38 Hz (170 ms) + bruit passe-bas 900 Hz + « pop » triangle 620 → 930 Hz | −4 dB |
| `kill` d'élite | + sub 60 → 28 Hz avec WaveShaper k = 15 | −2 dB |
| `playerHurt` | carré 190 → 85 Hz, WaveShaper k = 25, passe-bas 1,6 kHz + bruit passe-bande 450 Hz ; les autres bus baissent de 6 dB pendant 150 ms | 0 dB |
| `enemyAttack` / `hazard` (télégraphe) | dent de scie 280 → 560 Hz sur toute la durée, passe-bas 1,4 kHz Q 4, gain 0,02 → 0,12, coupure nette à l'impact ; panoramique selon dx/450 u | −14 dB |
| `skill` (Lance) | bruit balayé montant + sinus 400 → 900 Hz (90 ms) | −8 dB |
| `gadget` (Nova) | sinus 90 → 40 Hz + bruit passe-bas 2 kHz, 250 ms | −3 dB |
| `super` / `superSlam` | montée sub 40 → 80 Hz sur 200 ms / sinus 85 → 30 Hz (320 ms) + bruit passe-bas 600 Hz | −1 dB |
| `gold` | carré 988 Hz (45 ms) puis 1319 Hz ; **+1 demi-ton par pièce enchaînée en moins de 450 ms** (max +12) | −12 dB |
| Loot Rare / Légendaire | arpège C6–E6–G6 / cloche 196 Hz (partiels ×2,76 et ×5,40) + sub 49 Hz | −8 / −3 dB |
| `bossPhase` (rugissement) | 2 dents de scie à 72 et 75,5 Hz + bruit passe-bas 450 Hz, WaveShaper k = 40, hauteur ×1,25 → ×0,85 sur 1,3 s | −2 dB |
| Mort du boss | slam + cloche −5 demi-tons + réverbération synthétique de 1,8 s | 0 dB |
| Battement de cœur (PV < 25 %) | sinus 55 Hz, double impulsion toutes les 0,8 s | −10 dB |
| Interface | sinus 1250 Hz, 18 ms | −18 dB |

### 8.10 Rendu et performance

**Boucle.**
- `rAF` → `realDt = min(Δ, 100 ms)` → accumulateur (× `timeScale`).
- **Au plus 4 pas de sim par frame**. Si la limite est atteinte, l'accumulateur est remis à zéro.
- Interpolation, puis effets, puis dispatch audio, puis rendu.
- Pause sur `visibilitychange`, sans rattrapage.

**Contexte et résolution.**
- `getContext('2d', {alpha: false, desynchronized: true})`.
- Backing store ≤ 2,0 MP sur mobile. Redimensionnement avec debounce de 150 ms.

**Interdits dans la boucle** : `shadowBlur`, `ctx.filter`, `create*Gradient` (dégradés autorisés seulement au pré-rendu), `getImageData`, `fillText`, `clip` par entité, allocations (`{}`, `[]`, closures, `forEach`, `map`).

**Pré-rendus.**
- Sprites par entité, en variantes `normal`, `white`, `elite`, `ghost`.
- Sol complet par salle, sang et brûlures peints directement dedans ; tuiles de 1024² au-delà de 4096 px.
- `setTransform` par sprite, culling à 45 u.

**Budgets par frame.**
- Au plus 400 `drawImage` et 30 `fill`/`stroke`.
- Sim ≤ 1 ms par tick ; effets ≤ 1 ms ; rendu ≤ 6 ms ; audio ≤ 0,3 ms.
- Scénario de stress : 30 ennemis, 120 projectiles, 450 particules.

**Mesure** : overlay F3 (ou tap à 3 doigts) affichant fps, p95 de l'intervalle, `workMs`, frames longues et q. Exposé à Playwright via `window.__perf`.

---

## 9. Périmètre MoSCoW et critères de réussite

### 9.1 MoSCoW

| Priorité | Contenu |
|---|---|
| **Must** | Sim déterministe 60 Hz, RNG à flux, tuning en données, hash d'état. Input tactile multi-doigts (presets A/B/C, grille portrait) et clavier/souris. Kit complet : mouvement, combo 3 coups, dash (2 charges, i-frames, esquive parfaite, Estoc, chain), Lance, Nova, Super slam + Fureur, matrice d'annulation, tampon, auto-visée avec ligne de vue. Juice P0 : gel, flash, recul, sons, caméra, paquet « héros touché », traînée de dash, télégraphes, étincelles et éclatements, trauma, nombres. 5 archétypes, élites (3 modificateurs), Charon (3 patterns, 3 phases, renforts). Zone d'équité, jetons, 4 dispositions. Section 1 enchaînable : portes à récompense, antichambre marchand/autel, Foyer, mort et reprise. Bénédictions : 3 familles (12) + Fièvre Dansante. Loot : 3 emplacements, 4 raretés, 16 affixes, 3 légendaires. Or, marchand, 4 événements. **Bac à sable** (`?sandbox=1`) : apparition de n'importe quel archétype, élite ou boss, mode dieu, hitboxes, ralenti, avance image par image, `?floor=N`. Panneau de tuning en direct (F9). Harnais bot et télémétrie, tests node, e2e Playwright, solvabilité, bundle mono-fichier `dist/`. |
| **Should** | Avarice (4) + duos Boucherie et Festin d'or. Section 2 et Charon enragé. Téléportation entre Foyers. Manette. Profil de feel « posé » en bascule (accélération 9 f, dash 150 u sur 12 f avec 9 f d'i-frames, startups +2 f, télégraphes ×1,25, ennemis ×0,85). Modificateurs Vampirique, Téléporteur, Multitir. Haptique. Grâce, rattrapage, sauvegarde `localStorage`. Option gaucher, taille des boutons (80 à 130 %). Marqueurs d'occlusion par les pouces. Légendaires 4 à 6. Bots `idle` et `dashOnly`. Teintes de Cercle. |
| **Could** | Super en tourbillon (A/B). Relance d'offre. Mimic. Musique synthétisée en boucle. Palette daltonienne. Rumble manette. Pom (+1 niveau). |
| **Won't** | Contenu des 666 étages au-delà des formules, 110 autres boss, 9 biomes visuels, méta et hub, autres héros, 7 familles complètes, inventaire à 8 emplacements, artisanat, narration, langues autres que le français, multijoueur, monétisation, cloud. |

### 9.2 Métriques mesurables par bot

- Profils : `skilled`, `noDash`, `masher` (existants) ; `idle` et `dashOnly` (Should).
- Méthode : 100 graines par profil, `tools/playtest.mjs`. Sortie JSON, une ligne `FEEL_METRICS {json}`. Les seuils sont des données dans `tools/feel_targets.mjs`.
- Ces métriques **servent au réglage, elles ne sont pas bloquantes**. Les seuls oracles bloquants sont au §10.5.

| ID | Métrique (télémétrie) | Seuil |
|---|---|---|
| M1 | Dégâts subis `skilled / noDash`, mêmes graines | ≤ 0,60 aux étages 1–4 ; ≤ 0,50 au boss |
| M2 | Victoire sur Charon (graines qui l'atteignent) | `skilled` ≥ 80 % ; `noDash` ≤ 30 % ; `idle` 0 % |
| M3 | Esquives parfaites / dashes | `skilled` ≥ 40 % |
| M4 | Dashes par minute de combat | `skilled` 15 à 45 |
| M5 | TTK mesuré sur mannequin, étage 1 | à ±15 % du tableau du §3.4 |
| M6 | Durées | salle : médiane 25–45 s, p90 ≤ 70 s ; boss : médiane 50–100 s ; section : médiane 4–6 min |
| M7 | Dégâts subis par salle (`skilled`) | médiane 10–30, p90 ≤ 55 |
| M8 | Supers lancés par salle de combat | 0,6 à 1,5 ; utilisé dans les 12 s après « prêt » dans ≥ 70 % des cas |
| M9 | Lisibilité | **0** dégât sans télégraphe ≥ 24 f ; **0** dégât d'un ennemi qui démarrait hors de la zone d'équité ; **0** dégât de contact |
| M10 | Perf (node) | p95 d'un tick ≤ 1 ms (10 ennemis + 40 projectiles) ; ≤ 2 ms en stress |
| M11 | Déterminisme | 100 % : même graine + mêmes entrées = même `stateHash` aux ticks 600 et 3600 |
| M12 | Taux de gel | ≤ 20 % des pas sur toute fenêtre de 60, hors événements majeurs |
| M13 | Latence | toute action prend effet au tick qui suit l'entrée |
| M14 | Sanité | `idle` meurt avant la fin de F2 dans ≥ 90 % des graines ; `masher` meurt avant le boss dans ≥ 50 % |
| M15 | Jetons | jamais plus de 2 mêlées en attaque ; jamais plus de 40 projectiles ennemis ; jamais plus de 10 ennemis vivants |

### 9.3 Gate Pierre (fun, feel, UX, audio)

Protocole : 3 sessions d'environ 10 min (bac à sable, section 1 au clavier, section 1 au tactile sur un vrai téléphone). Notes de 1 à 5.

| # | Question | Seuil |
|---|---|---|
| G1 | Le déplacement est nerveux dès la première seconde | ≥ 4 |
| G2 | Le dash est satisfaisant et donne envie d'être rejoué | ≥ 4 |
| G3 | Chaque coup a du poids | ≥ 4 |
| G4 | Je comprends pourquoi j'ai pris chaque dégât | ≥ 4 |
| G5 | Je veux relancer après une mort | ≥ 4 |
| G6 | Le tactile se joue au pouce sans gêne | ≥ 4 |
| G7 | L'audio renforce l'impact | ≥ 3 |
| G8 | Le Super et la Nova sont des moments de puissance clairs | ≥ 4 |
| G9 | Les 5 ennemis demandent des réactions différentes | ≥ 4 |
| G10 | Les 3 phases du boss sont distinctes et lisibles | ≥ 4 |

Passage : médiane ≥ 4 sur G1–G6 et G8–G10, G7 ≥ 3, aucune note ≤ 2.

### 9.4 Décisions demandées à Pierre
1. **D1** Structure en sections de 6, 111 boss sur 3 tiers, 9 Cercles + Abîme.
2. **D2** Règle de mort : bénédictions perdues, équipement gardé, 50 % de l'or (elle est déjà figée par les tests ; le snapshot du GDD reste l'alternative).
3. **D3** Écart de stack : web canvas au lieu du gabarit Godot.
4. **D4** Super en slam + Fureur (tourbillon en alternative).
5. **D5** Les 7 péchés comme familles (prototype : 3 + Avarice).
6. **D6** Zone d'équité (les tireurs se repositionnent).
7. **D7** Gel global de la sim.
8. **D8** Cible de durée de section 4 à 6 min.

---

## 10. Conventions du dépôt

### 10.1 État constaté (lecture seule, 2026-10-01)
- `GAMES/dungeon_666/` **existe**. Il n'est pas suivi par git, et une passe parallèle y écrit encore.
- Contenu : `src/{core,sim,input,render,audio,ui}`, `src/main.mjs`, `index.html`, `server.mjs` (port 4666), `package.json` (`"test": "node --test tests/"`), `tools/{bots,bundle,e2e,playtest,pw}.mjs`, `dist/`.
- Tests présents : `tests/logic.test.mjs`, `tests/properties.test.mjs`, `tests/audio.test.mjs`.
- `00_CHARTER/` et `01_DESIGN/` sont vides.
- `package.json` appelle un `run-oracle.mjs` qui n'existe pas.

### 10.2 Architecture et dépendances
- Couches : `core` (rng, math : purs) ← `sim` (règles, n'importe que `core`) ; `input` (DOM → `InputFrame`, n'importe ni `sim` ni `render`) ; `render` et `audio` (consomment l'état en lecture seule et la file `game.events`, peuvent importer des constantes de `sim`) ; `ui` (menus, panneau de tuning : lit l'état, envoie des commandes via `applyCommand`) ; `main.mjs` (seul assembleur).
- Si un `architecture_contract` est déclaré : `src_root = GAMES/dungeon_666/src`, sinon tout tombe dans le module `src`.
- Interdits dans `sim` et `core` : `Math.random`, `Date.now`, `performance.now`, le DOM, `node:crypto` (qui casse le navigateur). Le hash est un 32 bits maison.
- **Flux RNG** seedés par `hash(seedDePartie, flux, étage)` : `gen` (salles, portes, apparitions), `combat` (critiques, choix d'IA), `loot` (objets, offres, boutique). `fxRng` est hors sim.
- **Ordre d'un tick** :
  1. entrées → tampons ;
  2. machine d'états du héros et mouvement ;
  3. IA et jetons ;
  4. projectiles et hazards ;
  5. touches héros → ennemis, puis ennemis → héros avec les i-frames calculées en 2 (priorité au joueur) ;
  6. dégâts appliqués en lot, dans l'ordre des `hitId` ;
  7. morts, drops, jauge ;
  8. gel, apparitions, nettoyage.
- **Événements de sim** (vocabulaire existant, à conserver) : `hit, kill, swing, attackStart, dash, dashEnd, dashReady, dodge, playerHurt, playerDeath, heal, gold, pickup, equip, boonGain, superReady, super, gadget, gadgetCharge, skill, castStart, enemyAttack, hazard, hazardFire, hazardCancel, explode, chargerWall, wallSlam, deflect, chain, spawnWarn, spawn, wave, roomClear, doorsOpen, floorEnter, checkpoint, respawn, bossPhase, bossSummon, victory, gameOver, choiceOpen, choiceClose, buy, cancel, projectileEnd, dashNova`.
  - À ajouter pour le slam : `superSlam`, `furyStart`, `furyEnd`. Ils remplacent `superTick`, gardé seulement pour le mode tourbillon.
  - Chaque nouvel événement doit être routé vers un son ou déclaré silencieux (test audio existant).

### 10.3 Paramètres d'URL et hooks
- URL : `?seed=`, `?floor=`, `?sandbox=1`, `?profile=pose`, `?debug=1`, `?manualClock=1` (horloge manuelle pour l'e2e).
- `window.__game` : `{ mode, tick, level (étage), over, score (meilleur étage), player:{x, y, hp, maxHp, state, dashCharges, superCharge, gadgetCharges}, enemies, hash, telemetry }`.
- `window.__game_debug` : `{ hit(d), forceLose(), forceWin() (tue Charon → VICTOIRE), step(n), reset(seed), snapshot(), setFloor(n), spawn(kind, elite), godMode(b) }`.
- DOM : `#gameCanvas`, `#objectif` (texte HUD lisible par un bot, par exemple « Étage 3/666 · Limbes — Nettoyez la salle »), `#overlay` (classe `hidden`), `#overlayText` (`VICTOIRE` / `JUGEMENT`), `#restart` (écoute `pointerup`).

### 10.4 Tests : surfaces protégées
- `GAMES/dungeon_666/tests/**` est **protégé** (`forge/test_surfaces.yaml`, régime `create_allowed_modify_denied`). Une fois la passe en cours terminée, les trois fichiers existants **ne seront plus modifiés sans gate Pierre**. On ne les déplace pas non plus.
- Les nouveaux tests sont créés dans **de nouveaux fichiers** : `tests/layout.test.mjs` (T8 : les 9 fenêtres paysage + 5 portrait), `tests/aim.test.mjs`, `tests/scaling.test.mjs` (SCL-01 à ±0,5 %), `tests/cancel_matrix.test.mjs` (une assertion par cellule du §2.8), `tests/telegraph.test.mjs` (M9).
- Règle : un test lit le tuning et ne recopie jamais une valeur. On ne rend jamais un test vert en réécrivant l'oracle.
- **Compatibilité vérifiée** de cette spécification avec les assertions existantes :
  - charges qui se rechargent une par une (chain-dash à t6 ≤ seuil du test) ;
  - Nova à 0 f de startup (le test vérifie la charge, l'étourdissement et les projectiles après 1 seul pas) ;
  - Super invulnérable dès l'appui ;
  - Lance qui perce au moins 2 cibles ;
  - gel global de la sim que le dash annule ;
  - Estoc tamponné pendant le dash ;
  - mort : bénédictions à 0, équipement gardé, `floor(or × deathGoldKeep)` ;
  - 111 boss, `circle(648) = 9`, `inFinale(649)` ;
  - portes F4 = {shop, event}, F5 = [boss] ;
  - rareté → nombre d'affixes fixe ;
  - ids `imp` et `brute` ;
  - au moins 2 bénédictions `attack` et au moins 2 `passive` avec `stat`.

### 10.5 Harnais oracle (gardes mécaniques de `forge/`)
Fichiers **à la racine du jeu**, à créer :
- **`run-oracle.mjs`** : tableau `STEPS [{label, argv, gating}]`, chaque étape lancée en `spawn` avec cwd = dossier du jeu, code de sortie 1 si un volet bloquant échoue. Volets :
  1. `node --test tests/` (bloquant) ;
  2. `solvability.mjs` (bloquant) ;
  3. `e2e.mjs` (bloquant) ;
  4. `tools/playtest.mjs` (métriques M, non bloquant) ;
  5. `node ../../forge/reuse_ratio.mjs dungeon_666` (non bloquant).
- **`e2e.mjs`** : Playwright + **chromium**, profil `Pixel 7 landscape`. Il doit contenir de vraies entrées : `keyboard.down`, `page.touchscreen.tap(...)` et `page.click('#restart')`. Les touches CDP seules ne passent pas la garde. Au moins 3 références à `__game`, `__game_debug`, `#overlay` ou `#restart`.
  - Scénario : hooks présents → `#objectif` non vide → les ticks avancent → déplacement réel au clavier → dash au tactile → `__game_debug.hit()` donne `JUGEMENT` → `#restart` → `forceWin()` donne `VICTOIRE`.
  - Captures dans `e2e-shots/`. Sortie `RESULT: PASS|FAIL`.
  - Playwright est résolu via `PLAYWRIGHT_NODE_MODULES=/opt/node22/lib/node_modules`. Si rien n'est trouvé : `FAIL`, jamais un vert par défaut.
- **`solvability.mjs`** : le bot `skilled` joue via les `InputFrame` uniquement. **PASS si au moins 5 graines sur 10 atteignent l'étage 7** (Charon battu) en ≤ 12 min de sim. Sortie `FORGE_ORACLE solvability {json}` puis `SOLVABILITY: PASS|FAIL`.
- **`server.mjs`** :
  - exporte `{startServer, routeFor, typeFor}` et ne démarre que s'il est exécuté directement ;
  - GET uniquement ; sert `src/**` et `dist/**` (extensions `mjs|js|css|html`) ; `Cache-Control: no-store` ;
  - écrit **`interface jouable`** sur stdout quand il est prêt ;
  - ports `DUNGEON_666_PORT` = 4666, `DUNGEON_666_E2E_PORT` = 4667, `DUNGEON_666_SOLV_PORT` = 4668, `DUNGEON_666_HOST` (0.0.0.0 pour un téléphone, ou `adb reverse` + `localhost` pour une origine sécurisée).
- `package.json` : scripts `test`, `oracle`, `e2e` (→ `node e2e.mjs`), `solvability`, `playtest`, `bundle`, `dev`.
- Documentation (en français) :
  - `01_DESIGN/GDD.md` : ce document, avec en-tête `statut_artefact : PROPOSED · claim_verdict : NO_CLAIM_ALLOWED` ;
  - `01_DESIGN/TUNING.md` ;
  - `00_CHARTER/CHARTER_PROPOSED.md`.

  Ne pas créer de `game_contract.yaml` : son schéma est fermé, il demande un `node` de curriculum, et cette décision revient à Pierre.

### 10.6 Ce qu'il ne faut **PAS** toucher
- Les autres jeux `GAMES/*` (dont `GAMES/pong/**`, gelé), `GAMES/RAIL_REGISTER.md` et `GAMES/PLAN_STATUS.md` (aucune déclaration n'est requise).
- `forge/**`, **`forge/oracles.json` compris**. Si une config d'oracle est nécessaire, utiliser `EVIDENCE/briefs/dungeon_666/oracles.json` avec `run_real --oracle-config`.
- `control_plane/registry.py`.
- `.claude/**` (hooks, `settings.json`, `HUMAN_GIT_OVERRIDE.json`, qui est en écriture refusée et réservé à Pierre).
- `knowledge_base/catalog.json`.
- **Le `.gitignore` racine** (mécanisme de preuve). Ne pas ajouter de `.gitignore` local sans gate.
- `dist/` ne s'ajoute à git que comme preuve jouable livrée.
- Recherche KB : `node knowledge_base/search.mjs --log-path <scratchpad>`, pour ne pas écrire dans `search_log.jsonl`.
- Ne pas importer de modules d'un autre jeu. Les imports `knowledge_base/...` renvoient 404 dans le navigateur : il faut bundler ou réécrire.
- Commits : uniquement sur demande, avec les lignes d'attribution de la session.

### 10.7 Écarts à appliquer au code actuel (config d'abord, code ensuite)

| Zone | Actuel → cible |
|---|---|
| Dash | `distance` 170 → 165 ; `iframes` 0,2 s → `f(10)` ; ajouter `curve`, `chainFromTick` 6 et `strikeWindow` `f(10)` (au lieu de 0,25 s) ; esquive parfaite : remboursement de 0,5 s → `f(30)` |
| Combo et Estoc | données frame par frame du §3.4. `comboResetTime` 0,32 s → `f(12)` ; `autoAim.range` 300 → 160 (mêlée) / 520 (Lance) ; ligne de vue obligatoire |
| Lance | perce 99 → 3 avec ×0,8 ; `castTime` `f(6)` |
| Nova | dégâts 12 → 20 (2 W) ; recul 700 → 900 ; étourdissement par classe (54 / 30 / 0 f) ; rayon de destruction des projectiles 190 ; +1 charge par salle |
| Super | tourbillon → **slam + Fureur** (`super.mode`, le tourbillon reste en alternative) ; `chargeDamage` 450 → 500 × hp_mult |
| Ennemis | imp 28 → 22 PV, télégraphe 24 f ; archer 30 f ; bélier 42 → 52 PV, charge 760 → 720 ; brute télégraphe 51 → 40 f, cercle r 120 → 100, récupération vulnérable 54 f ; possédé 12 → 10 PV, vitesse 225 → 210 ; frottement du recul 9 → 12 ; ajouter poise et anti-enfermement, zone d'équité, jeton de charge |
| Élites | `hpMult` 2,6 → 3,0 ; **supprimer `rapide.windupMult`** (les télégraphes ne sont jamais raccourcis) |
| Boss | `gardien` → `charon` (3 patterns, 3 phases à 66 et 33 %, renforts, fenêtres de vulnérabilité, PV `1450 × hp_mult`) |
| Étages | croissance linéaire (`hpGrowth`, `dmgGrowth`) → formules L/B/C/D du §5.5 ; `finaleName` « Le Trône » → « L'Abîme » |
| Salle | 1400×880 → intérieur 1280×800 ; `spawnWarn` 0,8 s → `f(45)` + grâce `f(18)` ; budget du §6.3 ; `maxAlive` 10 |
| Portes | poids du §6.5 ; pitié de bénédiction ; élite interdit en F2 |
| Bénédictions | raretés ×1,5 / ×2 → ×1,4 / ×1,8 ; `enabledFamilies` ; liste du §7.2 (les ids existants sont réutilisés quand l'effet correspond) |
| Loot | commun 1 → **0** affixe ; couleurs du §8.8 ; table des drops et pitié du §7.3 |
| Économie | `shopHealPrice` 30 → 40 ; prix × L(f) ; `deathGoldKeep` 0,5 inchangé |
| Contrôles | placer le **bouton Super** (presets A/B/C, grille portrait) ; supprimer `ATTACK_INTENT_TICKS` |

Fichiers de référence lus pour cette spécification :
- `/home/user/Studio2/GAMES/dungeon_666/src/sim/config.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/src/sim/boons.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/src/sim/loot.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/src/sim/floors.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/src/sim/run.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/tests/logic.test.mjs`
- `/home/user/Studio2/GAMES/dungeon_666/tests/properties.test.mjs`

Scripts de vérification de la disposition et des calculs : `/tmp/claude-0/-home-user-Studio2/ed1ee3dd-fb65-5677-bb48-3018ccfebe54/scratchpad/spec/` (`layout_search.mjs`, `cover.mjs`, `show.mjs`, `p2.mjs`, `calc.mjs`).