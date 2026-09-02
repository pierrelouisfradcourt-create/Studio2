# params.gd — BLOC UNIQUE de constantes nommees de gameplay (ligne params.bloc_unique).
# C'est ICI, et NULLE PART AILLEURS, que vit un litteral numerique de gameplay.
# Feuille du graphe : ne depend de rien. RefCounted (logique pure, aucune API moteur).
#
# Les 10 parametres viennent de charter.parametres_de_design (tous statut A_EQUILIBRER,
# provenance PROPOSITION_REDACTEUR). Repris tels quels, JAMAIS re-tranches ici. Les
# constantes de GEOMETRIE derivees/annexes (dimensions de brique, rayon de balle, hauteur
# et position de raquette, offsets de niveau) vivent AUSSI dans ce bloc unique : la regle
# du charter est « un seul bloc de constantes nommees, aucun litteral disperse » — elle
# n'interdit pas d'autres constantes nommees, elle interdit les litteraux ailleurs.
extends RefCounted

# ============================================================================
# LES 10 PARAMETRES DU CHARTER (charter.parametres_de_design, tous A_EQUILIBRER)
# ============================================================================

# (1) terrain : "640 x 480 unites logiques". A_EQUILIBRER.
const TERRAIN_LARGEUR: float = 640.0
const TERRAIN_HAUTEUR: float = 480.0

# (2) raquette_largeur : "80 unites (1/8 de la largeur du terrain)". A_EQUILIBRER.
const RAQUETTE_LARGEUR: float = 80.0

# (3) raquette_vitesse_max : "600 unites/seconde". A_EQUILIBRER.
const RAQUETTE_VITESSE_MAX: float = 600.0

# (4) balle_vitesse_initiale : "300 unites/seconde, constante sur toute la partie". A_EQUILIBRER.
const BALLE_VITESSE_INITIALE: float = 300.0

# (5) tick_dt_fixed_ms : "16 ms (~62,5 Hz), pas de temps FIXE de la simulation pure". A_EQUILIBRER.
const TICK_DT_FIXED_MS: float = 16.0

# (6) angle_rebond_max_deg : "60 degres de deviation maximale par rapport a la verticale". A_EQUILIBRER.
const ANGLE_REBOND_MAX_DEG: float = 60.0

# (7) grille_briques : "6 rangees x 10 colonnes = 60 briques cassables". A_EQUILIBRER.
const GRILLE_RANGEES: int = 6
const GRILLE_COLONNES: int = 10

# (8) vies_initiales : "3 vies". A_EQUILIBRER.
const VIES_INITIALES: int = 3

# (9) seed_reference : charter = "breakout-ref-01 (chaine de seed de travail, a fixer au s4)".
# Le PRNG de generation et l'oracle de solvabilite exigent un ENTIER : valeur de travail 1,
# statut A_EQUILIBRER (fog F11 : seed non fixee). Le NOM est cite par les preuves, jamais la valeur.
const SEED_REFERENCE: int = 1

# (10) points_par_brique : "10 points par brique cassee" (GATE 1, fog F3). A_EQUILIBRER.
const POINTS_PAR_BRIQUE: int = 10

# ============================================================================
# CONSTANTES DE GEOMETRIE (nommees, dans le meme bloc unique — pas de litteral disperse)
# ============================================================================

# Dimensions d'une brique. La largeur PAVE le terrain sur GRILLE_COLONNES colonnes.
const BRIQUE_LARGEUR: float = TERRAIN_LARGEUR / GRILLE_COLONNES   # 640/10 = 64
const BRIQUE_HAUTEUR: float = 20.0

# Rayon de la balle (physique continue : la balle est un disque).
const BALLE_RAYON: float = 6.0

# Raquette : hauteur (epaisseur) et marge au-dessus du bas du terrain.
const RAQUETTE_HAUTEUR: float = 12.0
const RAQUETTE_MARGE_BAS: float = 30.0

# Generation de niveau : offset vertical seede du bloc de briques (fog : disposition seedee
# a compte constant ROWS*COLS ; deux seeds -> deux offsets -> deux dispositions distinctes).
const BRIQUE_ZONE_Y_BASE: float = 40.0
const LEVEL_OFFSET_STEP: float = 12.0
const LEVEL_NB_OFFSETS: int = 7

# ============================================================================
# CADENCE RUNTIME (borne de l'adaptateur de boucle — PAS un des 10 parametres de gameplay)
# ============================================================================

# Plafond de ticks de simulation appliques dans UNE trame du moteur par l'accumulateur a pas
# fixe du cadenceur runtime (runtime_loop.gd::avancer). Le rattrapage est BORNE a cette valeur
# pour ne jamais spiraler apres une trame tres longue (pause, point d'arret) : au-dela, le
# surplus de temps est jete. Ce n'est PAS un parametre de gameplay (il ne change ni la physique
# ni les regles, seulement la robustesse du cadenceur) ; il vit ici pour honorer « un seul bloc
# de constantes nommees, aucun litteral disperse » (charter).
const MAX_TICKS_PAR_FRAME: int = 5

# ---- Grandeurs derivees exposees en fonctions (evite tout risque d'expression const non
# supportee, et garantit que test et implementation partagent EXACTEMENT l'expression) ----

# Demi-largeur de la raquette (bornage + point d'impact relatif).
static func raquette_demi_largeur() -> float:
	return RAQUETTE_LARGEUR / 2.0

# Ligne (haut) de la raquette, en y.
static func raquette_y() -> float:
	return TERRAIN_HAUTEUR - RAQUETTE_MARGE_BAS

# Pas de temps fixe de la simulation, en SECONDES (derive de TICK_DT_FIXED_MS). Un seul
# porteur : jamais un litteral de duree ailleurs.
static func dt_s() -> float:
	return TICK_DT_FIXED_MS / 1000.0

# Angle de rebond maximal en RADIANS (derive de ANGLE_REBOND_MAX_DEG). Expression partagee
# par la deflexion et son test -> egalite flottante stricte exacte (charter, politique F2).
static func angle_rebond_max_rad() -> float:
	return ANGLE_REBOND_MAX_DEG * PI / 180.0

# Nombre total de briques a la generation : EXACTEMENT rangees * colonnes.
static func total_briques() -> int:
	return GRILLE_RANGEES * GRILLE_COLONNES
