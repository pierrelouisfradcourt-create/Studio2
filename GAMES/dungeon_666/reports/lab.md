# Labo du feel — mesure comparée des variantes D5 / D8 / D9

Généré par `node tools/playtest.mjs --lab-report` le 2026-10-01T11:05:13.175Z. Graines 1 à 20 par variante et par joueur, objectif : battre la section 1 (Gardien à l'étage 18), limite 30 min de temps simulé, arrêt à la première mort. 260 parties jouées en 49.0 s.

**Ce rapport ne tranche pas D5, D8 ni D9.** Les bots mesurent des conséquences — dégâts reçus, rythme, durée des salles, temps passé figé. Ils ne mesurent pas le plaisir, la lisibilité ressentie, ni la sensation d'impact : ce sont des questions de pouce et d'œil humains. Les décisions restent ouvertes ; ces chiffres servent à repérer une variante qui casserait le jeu (dégâts reçus qui explosent, rythme effondré), pas à choisir la plus agréable.

Une seule variante change à la fois ; les deux autres axes restent à leur référence (Fin du dash · Global · Mobile). Entre parenthèses : l'écart à la référence, pour le même joueur. « min réelle » = minute d'images affichées (gel compris), seule base comparable entre gel global et gel local. « Temps figé » = part des images où le héros est figé par un gel d'impact.

## D5 · Frappe de dash

- **Fin du dash** — Attaquer dans le dernier 45 % du dash ou juste après.
- **Tout le dash** — Attaquer à n'importe quel moment du dash le coupe en frappe.
- **Après le dash** — Le dash va au bout ; une attaque juste après devient frappe.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fin du dash (réf.) | skilled | 100 % | 0 % | 2.7 | 8.5 | 0.38 | 15.3 | 43.0 | 51.0 | 7.76 | 31.4 | 7.2 % |
| Fin du dash (réf.) | dashFrappe | 55 % | 45 % | 13.6 | 50.6 | 1.73 | 14.3 | 30.4 | 80.1 | 30.71 | 30.9 | 9.8 % |
| Tout le dash | skilled | 100 % | 0 % | 2.7 (=) | 8.5 (=) | 0.38 (=) | 15.3 (=) | 43.0 (=) | 51.0 (=) | 7.76 (=) | 31.4 | 7.2 % |
| Tout le dash | dashFrappe | 30 % | 70 % | 18.4 (+36 %) | 74.2 (+47 %) | 2.56 (+49 %) | 13.4 (-6 %) | 27.0 (-11 %) | 81.4 (+2 %) | 30.21 (-2 %) | 30.5 | 9.7 % |
| Après le dash | skilled | 100 % | 0 % | 2.7 (=) | 8.5 (=) | 0.38 (=) | 15.3 (=) | 43.0 (=) | 51.0 (=) | 7.76 (=) | 31.4 | 7.2 % |
| Après le dash | dashFrappe | 95 % | 5 % | 7.4 (-45 %) | 25.8 (-49 %) | 1.13 (-34 %) | 14.0 (-2 %) | 32.4 (+7 %) | 75.9 (-5 %) | 28.57 (-7 %) | 31.0 | 9.0 % |

Lecture : Le bot skilled ne presse jamais l'attaque PENDANT un dash : pour lui les trois variantes doivent donner des chiffres identiques (c'est un contrôle, pas un résultat). La ligne « dash puis frappe » mesure le prix et le gain de chaque variante pour un joueur qui enchaîne vite : « Tout le dash » coupe la ruée plus tôt (esquive plus courte, frappe plus tôt), « Après le dash » garde toute l'esquive et frappe plus tard. Attention : l'habitude scriptée tape l'attaque au début de CHAQUE dash, y compris les dash d'esquive — c'est le pire cas pour une variante qui coupe la ruée ; un joueur humain choisit quand frapper, et peut apprendre à ne pas taper pendant une esquive.

## D8 · Gel d'impact

- **Global** — Toute la scène se fige à l'impact.
- **Local** — Seuls le héros et ses cibles se figent ; le reste continue.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Global (réf.) | skilled | 100 % | 0 % | 2.7 | 8.5 | 0.38 | 15.3 | 43.0 | 51.0 | 7.76 | 31.4 | 7.2 % |
| Global (réf.) | masher | 0 % | 100 % | 34.8 | 201.8 | 9.39 | 10.5 | — | 132.2 | 4.85 | 8.7 | 11.6 % |
| Local | skilled | 100 % | 0 % | 1.5 (-42 %) | 5.1 (-39 %) | 0.28 (-25 %) | 15.5 (+2 %) | 41.6 (-3 %) | 52.3 (+3 %) | 8.40 (+8 %) | 33.1 | 7.4 % |
| Local | masher | 0 % | 100 % | 42.6 (+22 %) | 253.9 (+26 %) | 11.80 (+26 %) | 9.6 (-8 %) | — | 141.3 (+7 %) | 6.04 (+25 %) | 9.2 | 12.8 % |

Lecture : En gel GLOBAL, le temps de la simulation s'arrête : les durées sont donc comparées en temps RÉEL (images affichées). En gel LOCAL, projectiles et autres ennemis continuent pendant que le héros est figé : la part de temps figé et les dégâts reçus disent ce que coûte ce gel, pas s'il est plus agréable.

## D9 · Mobilité du combo

- **Ancré** — 20 % de vitesse, annulations tardives.
- **Mobile** — 50 % de vitesse, annulations de référence.
- **Fluide** — 75 % de vitesse, annulations très tôt.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ancré | skilled | 95 % | 5 % | 2.8 (+7 %) | 8.8 (+4 %) | 0.39 (+2 %) | 15.9 (+5 %) | 41.5 (-4 %) | 50.5 (-1 %) | 7.51 (-3 %) | 31.1 | 7.1 % |
| Ancré | masher | 0 % | 100 % | 30.1 (-13 %) | 177.5 (-12 %) | 9.45 (+1 %) | 10.4 (-1 %) | — | 131.2 (-1 %) | 6.11 (+26 %) | 9.2 | 11.5 % |
| Mobile (réf.) | skilled | 100 % | 0 % | 2.7 | 8.5 | 0.38 | 15.3 | 43.0 | 51.0 | 7.76 | 31.4 | 7.2 % |
| Mobile (réf.) | masher | 0 % | 100 % | 34.8 | 201.8 | 9.39 | 10.5 | — | 132.2 | 4.85 | 8.7 | 11.6 % |
| Fluide | skilled | 100 % | 0 % | 2.5 (-7 %) | 8.4 (-1 %) | 0.42 (+12 %) | 15.6 (+3 %) | 34.6 (-20 %) | 54.3 (+7 %) | 7.35 (-5 %) | 29.3 | 7.5 % |
| Fluide | masher | 0 % | 100 % | 31.9 (-8 %) | 204.0 (+1 %) | 9.42 (=) | 9.3 (-11 %) | — | 146.5 (+11 %) | 4.45 (-8 %) | 9.0 | 11.6 % |

Lecture : Ancré : 20 % de vitesse en frappant et annulations tardives ; Fluide : 75 % et annulations très tôt. Les attaques par minute mesurent le rythme du combo, les dégâts reçus mesurent ce que la mobilité en frappant rapporte (ou coûte) à un joueur qui lit — et à un joueur qui martèle.

## Limites de la mesure

- Les bots ont un temps de réaction fixe (0,15 s) et lisent parfaitement les télégraphes : un écart de quelques pourcents entre variantes est en deçà du bruit de 20 graines.
- Le bot skilled n'exploite pas délibérément la frappe de dash : la ligne « dash puis frappe » est une habitude scriptée (un tap d'attaque au début de chaque dash), pas une stratégie optimisée.
- Aucun chiffre ici ne dit si un coup « pèse », si le gel local paraît plus net ou plus confus, ni si le combo fluide est plus grisant : il faut jouer (pause → Labo du feel, ou Ville → Labo du feel ; l'arène d'essai s'y prête).
