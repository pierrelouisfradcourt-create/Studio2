# Dungeon 666 — décisions ouvertes pour Pierre

`statut_artefact : PROPOSED` · chaque ligne indique ce que fait le prototype aujourd'hui. Les
défauts sont **réversibles** : ce sont des valeurs de `src/sim/config.mjs`, ou de petites règles isolées.

| # | Décision | Ce que fait le prototype | Alternatives | Comment trancher |
|---|---|---|---|---|
| D1 | **Profil de feel** | « Nerveux » : course 300 u/s, accélération en 5 images, arrêt en 3. Dash de 170 u en 0,15 s, invulnérable 0,2 s, 2 charges rechargées en 0,9 s. | « Posé » : course 260, dash plus long (0,25 s), recharge 1,5 s, télégraphes ennemis ×1,25. | Pause → **Réglages du feel** : tout se règle en jouant. |
| D2 | **Visée** | Visée assistée par défaut (cible proche, avec ligne de vue, dans le sens du déplacement, cible « collante » 0,4 s). Glisser = visée manuelle. | Visée manuelle obligatoire (plus d'adresse, plus de friction au pouce). | Jouer deux salles en tapant, puis deux en glissant. |
| D3 | **Mort** | On reprend au checkpoint choisi avec le **build figé quand on a battu son Gardien** (bénédictions + or, l'or plafonné à celui qu'on avait en mourant). L'équipement n'est jamais perdu. On ne perd que la section en cours. Mort au Gardien : « Réessayer le Gardien » relance le combat avec le build d'entrée dans sa salle. | (a) Perdre toutes les bénédictions à chaque mort (plus Hades, plus punitif). (b) Tout garder, ne perdre que la position. | Mourir deux fois au Gardien et juger l'envie de relancer. |
| D4 | **Structure des 666** | Sections de 6 (Gardien au 6ᵉ = checkpoint), 9 Cercles de 72, finale de 18. Un seul modèle de Gardien dans le prototype. | Un « Seigneur » plus coriace tous les 18 étages et à la fin de chaque Cercle (22 scripts de boss en tout, recommandation des concepteurs). | Après validation du feel. |
| D5 | **Frappe de dash** | Une attaque en fin de dash (dernier 45 %) coupe la ruée et frappe tout de suite (×1,8 dégâts, élan). | Frappe seulement après la fin complète du dash. | Ressenti : « je frappe quand je veux » ou « ça me coupe mon esquive ». |
| D6 | **Moteur cible** | Prototype web (canvas 2D) : testable sur n'importe quel téléphone en un lien, simulation isolée et portable. | Port Godot 4 (export Android/iOS natif) une fois le feel validé. | Après le verdict de feel. |
| D7 | **Place dans le studio** | Hors du rail (`RAIL_REGISTER.md`) et hors de la Forge (`forge/oracles.json` est une surface protégée) : oracles locaux (`node run-oracle.mjs`). | L'inscrire au portefeuille, ou en faire un brief Forge (`EVIDENCE/briefs/dungeon_666/`). | Décision de portefeuille. |
| D8 | **Gel d'impact** | Gel global (coups 0,04 s, 3ᵉ coup 0,085 s), plafonné par une réserve de 0,22 s qui se recharge. Le dash l'interrompt. | Gel local (attaquant + cible seulement), recommandé par le spécialiste juice : plus fluide en mêlée, plus complexe. | Mêlée de 6 ennemis : est-ce que ça « colle » ? |
| D9 | **Mobilité pendant le combo** | On garde 40 % de la vitesse en attaquant (`player.attackMoveMult`). Le coup suivant part après 30 % de la récupération (60 % après le 3ᵉ coup, `comboCancelFrom`). | 50 % de vitesse et des annulations plus tôt : plus mobile, mais l'oracle mesure alors un dash qui ne vaut plus que ×1,6–1,7 (seuil ×2). À 20 % (valeur initiale), le héros était plus lent qu'un diablotin. | Arène d'essai, combo maintenu : le dash reste-t-il le réflexe ? |

## Ce qui est mesuré, et ce qui ne l'est pas

- **Mesuré (bots, `node solvability.mjs` et `node tools/playtest.mjs`)** :
  - la section 1 est battable ;
  - **ne jamais dasher fait prendre environ 2,4 fois plus de dégâts** (seuil de l'oracle : 2) ;
  - un joueur qui martèle sans lire les télégraphes meurt presque toujours ;
  - aucune partie bloquée sur 60 parties ;
  - la cadence du Super est d'environ 4 à 5 par section (bot habile).
- **Non mesurable par un bot** : le plaisir, le poids des coups, le confort du pouce, la lisibilité
  ressentie. C'est la **gate Pierre**. La grille G1 à G10 est dans [`GDD_PROTOTYPE.md`](GDD_PROTOTYPE.md).
