# params.gd — BLOC UNIQUE de constantes nommees de gameplay (ligne params.bloc_unique).
# C'est ICI, et NULLE PART AILLEURS, que vit un litteral numerique de gameplay.
# Feuille du graphe : ne depend de rien. RefCounted (logique pure, aucune API moteur).
#
# Les 8 parametres viennent de charter.parametres_de_design (statut A_EQUILIBRER pour
# 7 d'entre eux, grille RATIFIEE). Repris tels quels, jamais reinventes.
extends RefCounted

# Dimension de la grille carree (cases). RATIFIE_PIERRE (D2).
const TAILLE_GRILLE: int = 20

# Periode initiale d'un tick, en millisecondes. A_EQUILIBRER.
const VITESSE_INITIALE_MS: float = 200.0

# Un palier d'acceleration est franchi tous les N fruits manges. A_EQUILIBRER.
const ACCELERATION_PALIER: int = 5

# Facteur multiplicatif de periode a chaque palier (pas -8 % => x0,92). A_EQUILIBRER.
const ACCELERATION_PAS: float = 0.92

# Plancher de periode : la cadence ne descend jamais sous ce seuil (ms). A_EQUILIBRER.
const PERIODE_PLANCHER_MS: float = 80.0

# Longueur du serpent au demarrage (segments). A_EQUILIBRER.
const LONGUEUR_INITIALE: int = 3

# Longueur a atteindre pour gagner. 25 = 3 initiale + 22 nourritures. A_EQUILIBRER.
const CIBLE_VICTOIRE: int = 25

# Points gagnes par nourriture consommee. A_EQUILIBRER.
const POINTS_PAR_NOURRITURE: int = 1
