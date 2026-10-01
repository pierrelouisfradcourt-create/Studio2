# Labo du feel — mesure comparée des variantes D5 / D8 / D9

Généré par `node tools/playtest.mjs --lab-report` le 2026-10-01T19:21:23.856Z. Graines 1 à 20 par variante et par joueur, objectif : battre la section 1 (Gardien à l'étage 18), limite 30 min de temps simulé, arrêt à la première mort. 260 parties jouées en 21.8 s.

**Ce rapport ne tranche pas D5, D8 ni D9.** Les bots mesurent des conséquences — dégâts reçus, rythme, durée des salles, temps passé figé. Ils ne mesurent pas le plaisir, la lisibilité ressentie, ni la sensation d'impact : ce sont des questions de pouce et d'œil humains. Les décisions restent ouvertes ; ces chiffres servent à repérer une variante qui casserait le jeu (dégâts reçus qui explosent, rythme effondré), pas à choisir la plus agréable.

Une seule variante change à la fois ; les deux autres axes restent à leur référence (Fin du dash · Global · Mobile). Entre parenthèses : l'écart à la référence, pour le même joueur. « min réelle » = minute d'images affichées (gel compris), seule base comparable entre gel global et gel local. « Temps figé » = part des images où le héros est figé par un gel d'impact.

## D5 · Frappe de dash

- **Fin du dash** — Attaquer dans le dernier 45 % du dash ou juste après.
- **Tout le dash** — Attaquer à n'importe quel moment du dash le coupe en frappe.
- **Après le dash** — Le dash va au bout ; une attaque juste après devient frappe.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fin du dash (réf.) | skilled | 95 % | 5 % | 3.3 | 10.7 | 0.53 | 15.5 | 44.7 | 59.6 | 9.22 | 30.2 | 7.6 % |
| Fin du dash (réf.) | dashFrappe | 65 % | 35 % | 13.7 | 54.7 | 2.01 | 13.7 | 29.6 | 82.0 | 27.52 | 27.7 | 9.4 % |
| Tout le dash | skilled | 95 % | 5 % | 3.3 (=) | 10.7 (=) | 0.53 (=) | 15.5 (=) | 44.7 (=) | 59.6 (=) | 9.22 (=) | 30.2 | 7.6 % |
| Tout le dash | dashFrappe | 20 % | 80 % | 17.3 (+26 %) | 75.8 (+38 %) | 2.79 (+39 %) | 12.7 (-7 %) | 31.3 (+6 %) | 85.2 (+4 %) | 27.06 (-2 %) | 27.0 | 9.5 % |
| Après le dash | skilled | 95 % | 5 % | 3.3 (=) | 10.7 (=) | 0.53 (=) | 15.5 (=) | 44.7 (=) | 59.6 (=) | 9.22 (=) | 30.2 | 7.6 % |
| Après le dash | dashFrappe | 95 % | 5 % | 7.1 (-48 %) | 26.6 (-51 %) | 1.30 (-35 %) | 14.1 (+3 %) | 30.9 (+4 %) | 80.3 (-2 %) | 26.57 (-3 %) | 28.8 | 9.1 % |

Lecture : Le bot skilled ne presse jamais l'attaque PENDANT un dash : pour lui les trois variantes doivent donner des chiffres identiques (c'est un contrôle, pas un résultat). La ligne « dash puis frappe » mesure le prix et le gain de chaque variante pour un joueur qui enchaîne vite : « Tout le dash » coupe la ruée plus tôt (esquive plus courte, frappe plus tôt), « Après le dash » garde toute l'esquive et frappe plus tard. Attention : l'habitude scriptée tape l'attaque au début de CHAQUE dash, y compris les dash d'esquive — c'est le pire cas pour une variante qui coupe la ruée ; un joueur humain choisit quand frapper, et peut apprendre à ne pas taper pendant une esquive.

## D8 · Gel d'impact

- **Global** — Toute la scène se fige à l'impact.
- **Local** — Seuls le héros et ses cibles se figent ; le reste continue.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Global (réf.) | skilled | 95 % | 5 % | 3.3 | 10.7 | 0.53 | 15.5 | 44.7 | 59.6 | 9.22 | 30.2 | 7.6 % |
| Global (réf.) | masher | 0 % | 100 % | 28.0 | 173.5 | 9.28 | 9.6 | — | 129.4 | 4.68 | 9.0 | 11.3 % |
| Local | skilled | 100 % | 0 % | 3.1 (-6 %) | 10.5 (-2 %) | 0.48 (-11 %) | 14.7 (-5 %) | 46.8 (+5 %) | 60.6 (+2 %) | 9.31 (+1 %) | 29.6 | 7.7 % |
| Local | masher | 0 % | 100 % | 28.2 (+1 %) | 188.3 (+9 %) | 10.16 (+9 %) | 8.7 (-9 %) | — | 137.0 (+6 %) | 5.13 (+10 %) | 9.2 | 12.4 % |

Lecture : En gel GLOBAL, le temps de la simulation s'arrête : les durées sont donc comparées en temps RÉEL (images affichées). En gel LOCAL, projectiles et autres ennemis continuent pendant que le héros est figé : la part de temps figé et les dégâts reçus disent ce que coûte ce gel, pas s'il est plus agréable.

## D9 · Mobilité du combo

- **Ancré** — 20 % de vitesse, annulations tardives.
- **Mobile** — 50 % de vitesse, annulations de référence.
- **Fluide** — 75 % de vitesse, annulations très tôt.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ancré | skilled | 100 % | 0 % | 2.4 (-29 %) | 7.5 (-30 %) | 0.40 (-24 %) | 15.5 (=) | 45.8 (+2 %) | 60.2 (+1 %) | 9.46 (+3 %) | 30.1 | 7.5 % |
| Ancré | masher | 0 % | 100 % | 24.2 (-14 %) | 149.8 (-14 %) | 8.33 (-10 %) | 9.1 (-5 %) | — | 128.4 (-1 %) | 5.61 (+20 %) | 9.1 | 11.1 % |
| Mobile (réf.) | skilled | 95 % | 5 % | 3.3 | 10.7 | 0.53 | 15.5 | 44.7 | 59.6 | 9.22 | 30.2 | 7.6 % |
| Mobile (réf.) | masher | 0 % | 100 % | 28.0 | 173.5 | 9.28 | 9.6 | — | 129.4 | 4.68 | 9.0 | 11.3 % |
| Fluide | skilled | 100 % | 0 % | 2.3 (-31 %) | 7.6 (-29 %) | 0.38 (-29 %) | 15.4 (=) | 40.4 (-10 %) | 60.7 (+2 %) | 8.67 (-6 %) | 29.4 | 7.8 % |
| Fluide | masher | 0 % | 100 % | 27.3 (-3 %) | 184.4 (+6 %) | 8.83 (-5 %) | 8.7 (-10 %) | — | 142.6 (+10 %) | 4.85 (+3 %) | 9.1 | 11.3 % |

Lecture : Ancré : 20 % de vitesse en frappant et annulations tardives ; Fluide : 75 % et annulations très tôt. Les attaques par minute mesurent le rythme du combo, les dégâts reçus mesurent ce que la mobilité en frappant rapporte (ou coûte) à un joueur qui lit — et à un joueur qui martèle.

## Limites de la mesure

- Les bots ont un temps de réaction fixe (0,15 s) et lisent parfaitement les télégraphes : un écart de quelques pourcents entre variantes est en deçà du bruit de 20 graines.
- Le bot skilled n'exploite pas délibérément la frappe de dash : la ligne « dash puis frappe » est une habitude scriptée (un tap d'attaque au début de chaque dash), pas une stratégie optimisée.
- Aucun chiffre ici ne dit si un coup « pèse », si le gel local paraît plus net ou plus confus, ni si le combo fluide est plus grisant : il faut jouer (pause → Labo du feel, ou Ville → Labo du feel ; l'arène d'essai s'y prête).
