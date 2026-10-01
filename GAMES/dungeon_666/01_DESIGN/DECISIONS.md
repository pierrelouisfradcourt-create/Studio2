# Dungeon 666 — décisions pour Pierre (état V2, 2026-10-01)

`statut_artefact : PROPOSED` · chaque ligne indique ce que fait le prototype aujourd'hui. Les
défauts sont **réversibles** : ce sont des valeurs de `src/sim/config.mjs`, ou de petites règles isolées.

| # | Décision | Ce que fait le prototype | Alternatives | Comment trancher |
|---|---|---|---|---|
| D1 | **Profil de feel** | « Nerveux » : course 300 u/s, accélération en 5 images, arrêt en 3. Dash de 170 u en 0,15 s, invulnérable 0,2 s, 2 charges rechargées en 0,9 s. | « Posé » : course 260, dash plus long (0,25 s), recharge 1,5 s, télégraphes ennemis ×1,25. | Pause → **Réglages du feel** : tout se règle en jouant. |
| D2 | **Visée** | Visée assistée par défaut (cible proche, avec ligne de vue, dans le sens du déplacement, cible « collante » 0,4 s). Glisser = visée manuelle. | Visée manuelle obligatoire (plus d'adresse, plus de friction au pouce). | Jouer deux salles en tapant, puis deux en glissant. |
| D3 | **Mort** | **TRANCHÉE par Pierre (V2)** : retour au dernier checkpoint ; bénédictions remises à zéro ; tout le permanent (classe, armes, équipement, compétences, déblocages, Âmes) gardé. Reste ouvert : la part d'or prélevée par Charon (50 %, Sanctuaire « Avidité » −15 %/niv.). | — | Jouer une mort après un Gardien. |
| D4 | **Structure des 666** | **TRANCHÉE par Pierre (V2)** : Gardien tous les 18 étages (37 sections), étages composés. Reste ouvert : nombre de modèles de Gardien (4 en rotation aujourd'hui), longueur réelle d'une section pour un humain (~11 min estimées par bot). | Gardiens spéciaux de fin de Cercle. | Après plusieurs sections jouées. |
| D5 | **Frappe de dash** | **TESTABLE** : Labo du feel → fin du dash (réf.) / tout le dash / après le dash. Mesure bots : `reports/lab.md`. | — | En main, Labo du feel. |
| D6 | **Moteur cible** | Prototype web (canvas 2D) : testable sur n'importe quel téléphone en un lien, simulation isolée et portable. | Port Godot 4 (export Android/iOS natif) une fois le feel validé. | Après le verdict de feel. |
| D7 | **Place dans le studio** | Hors du rail (`RAIL_REGISTER.md`) et hors de la Forge (`forge/oracles.json` est une surface protégée) : oracles locaux (`node run-oracle.mjs`). | L'inscrire au portefeuille, ou en faire un brief Forge (`EVIDENCE/briefs/dungeon_666/`). | Décision de portefeuille. |
| D8 | **Gel d'impact** | **TESTABLE** : Labo du feel → global (réf.) / local (seuls le héros et ses cibles se figent). Mesure bots : `reports/lab.md`. | — | Mêlée de 6 ennemis, en main. |
| D9 | **Mobilité pendant le combo** | **TESTABLE** : Labo du feel → ancré (20 %) / mobile (50 %, réf.) / fluide (75 %), avec annulations allongées ou abrégées. Mesure bots : `reports/lab.md`. | — | Arène d'essai, combo maintenu. |
| D10 | **Économie permanente** | Âmes : 1 par ennemi, 6 par élite, 60 + 15/section par Gardien ; classes 120, armes 40-60, compétences/gadgets 35-45 ; Sanctuaire 6 améliorations. | Coûts plus bas pour tester vite ; or comme seule monnaie. | Une soirée de jeu. |
| D11 | **Équilibrage des classes** | Bourreau (Hache/Maillet) : la relecture a relevé un étourdissement en boucle en maintenant l'attaque ; Chasseresse : le dash devient facultatif pour le bot. **Non corrigé** (correction interrompue à la clôture). | Garde/stagger des ennemis, recul de la Chasseresse. | En main, puis bots. |
| D12 | **Portage Godot** | Pierre (2026-10-01) : reprise sous Godot. La charte demandait un feel validé avant ; la sim web reste la spécification exécutable. | — | Pierre. |

## Ce qui est mesuré, et ce qui ne l'est pas

- **Mesuré (bots, `node solvability.mjs` et `node tools/playtest.mjs`)** :
  - la section 1 est battable ;
  - **ne jamais dasher fait prendre environ 4,5 fois plus de dégâts** (seuil de l'oracle : 2) ;
  - un joueur qui martèle sans lire les télégraphes meurt presque toujours ;
  - aucune partie bloquée sur 60 parties ;
  - la cadence du Super est d'environ 4 à 5 par section (bot habile).
- **Non mesurable par un bot** : le plaisir, le poids des coups, le confort du pouce, la lisibilité
  ressentie. C'est la **gate Pierre**. La grille G1 à G10 est dans [`GDD_PROTOTYPE.md`](GDD_PROTOTYPE.md).
