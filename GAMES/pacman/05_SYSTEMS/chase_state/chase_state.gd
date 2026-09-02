# chase_state.gd — machine a etats de poursuite et son horloge (lignes chase.clock,
# chase.state_per_ghost, chase.frightened_window, chase.switch_reversal).
# Vocabulaire FERME de trois valeurs : jamais une combinaison de drapeaux.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

enum Mode { DISPERSION, POURSUITE, EFFRAYE }
const MODES_VALIDES: Array = [Mode.DISPERSION, Mode.POURSUITE, Mode.EFFRAYE]

# --- Sequence FINIE de segments (worldscan#ghost_states.mode_timing_levels_1_4) -------
# 20 s poursuite / 7 s dispersion / 20 / 7 / 20 / 5, puis poursuite permanente.
# Les durees viennent du bloc unique de parametres : aucun litteral de gameplay ici.
const SEGMENTS: Array = [
	[Mode.POURSUITE, P.SEGMENT_POURSUITE_TICKS],
	[Mode.DISPERSION, P.SEGMENT_DISPERSION_LONG_TICKS],
	[Mode.POURSUITE, P.SEGMENT_POURSUITE_TICKS],
	[Mode.DISPERSION, P.SEGMENT_DISPERSION_LONG_TICKS],
	[Mode.POURSUITE, P.SEGMENT_POURSUITE_TICKS],
	[Mode.DISPERSION, P.SEGMENT_DISPERSION_COURT_TICKS],
]
# Mode apres le sixieme seuil : poursuite PERMANENTE, aucun retour en dispersion.
const MODE_FINAL: int = Mode.POURSUITE

# Duree de la fenetre Effraye, en ticks.
const DUREE_EFFRAYE: int = P.DUREE_EFFRAYE_TICKS


# Les SIX seuils, CUMULES depuis les segments — jamais recopies a la main : une
# sequence et ses seuils ne peuvent pas diverger s'ils ont une seule source.
static func seuils() -> Array:
	var sortie: Array = []
	var borne: int = 0
	for seg in SEGMENTS:
		borne += seg[1]
		sortie.append(borne)
	return sortie


# Mode global a l'instant `horloge` (ligne chase.clock).
static func mode_global(horloge: int) -> int:
	var borne: int = 0
	for i in range(SEGMENTS.size()):
		borne += SEGMENTS[i][1]
		if horloge < borne:
			return SEGMENTS[i][0]
	return MODE_FINAL


# Vrai si `horloge` est EXACTEMENT un des six seuils : le tick de bascule.
static func est_seuil(horloge: int) -> bool:
	return seuils().has(horloge)


# Etat d'UN fantome : exactement une valeur du vocabulaire ferme.
static func etat_fantome(horloge: int, effraye: bool) -> int:
	if effraye:
		return Mode.EFFRAYE
	return mode_global(horloge)


# Arme la fenetre Effraye sur les quatre fantomes (consommation d'une super-pastille).
static func armer_effraye(s) -> void:
	s.effraye_restant = DUREE_EFFRAYE
	for i in range(s.effrayes.size()):
		s.effrayes[i] = true
	s.rang_capture = 0
	# L'etat EXPOSE suit immediatement l'armement : sans ce rafraichissement, le releve
	# du tick de consommation montrerait encore l'ancien mode.
	rafraichir_etats(s)


# Fait expirer la fenetre Effraye : l'etat prend TOUJOURS fin.
static func expirer(s) -> void:
	s.effraye_restant = 0
	for i in range(s.effrayes.size()):
		s.effrayes[i] = false
	rafraichir_etats(s)


# Avance l'horloge d'un tick et recalcule les etats exposes. Retourne vrai si ce tick
# est un tick de BASCULE (seuil franchi ou fin de fenetre Effraye) — c'est ce booleen
# qui declenche l'inversion de direction (ligne chase.switch_reversal).
static func avancer(s) -> bool:
	s.horloge += 1
	var bascule: bool = est_seuil(s.horloge)
	if s.effraye_restant > 0:
		s.effraye_restant -= 1
		if s.effraye_restant == 0:
			expirer(s)
			bascule = true
	rafraichir_etats(s)
	return bascule


# Attribue EXACTEMENT un etat par fantome dans l'ordre fixe des index.
static func rafraichir_etats(s) -> void:
	for i in range(s.etats_fantomes.size()):
		s.etats_fantomes[i] = etat_fantome(s.horloge, s.effrayes[i])


# Direction inverse — utilisee au tick de bascule.
static func inverser(d: Vector2i) -> Vector2i:
	return Vector2i(-d.x, -d.y)


# PHASE INITIALE de l'horloge (ligne chase.clock_reset_on_switch) : lors d'une bascule
# de NIVEAU, l'horloge des etats revient a sa premiere valeur, la fenetre Effraye est
# fermee et le rang de capture repart. La carte suivante n'herite JAMAIS de l'horloge de
# la precedente — propriete relevee par egalite stricte de part et d'autre de la bascule.
static func reinitialiser_horloge(s) -> void:
	s.horloge = 0
	s.effraye_restant = 0
	s.rang_capture = 0
	for i in range(s.effrayes.size()):
		s.effrayes[i] = false
	rafraichir_etats(s)
