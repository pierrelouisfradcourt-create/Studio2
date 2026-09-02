# game_state.gd — ORIGINE UNIQUE d'un etat de partie (lignes state.initial_from_seed,
# state.carries_map, state.exposes_level_number).
#
# V2 : l'etat initial est construit A PARTIR D'UNE CARTE PASSEE EN ENTREE, et l'etat
# PORTE desormais sa carte courante. Aucune fonction de la logique ne va chercher une
# carte globale — troisieme des quatre causes mesurees de la baseline V1.
#
# RefCounted, aucune I/O, aucune horloge de plateforme, aucun alea non seede, aucune API
# de rendu. Tous les champs de la partie vivent ici — y compris l'etat du generateur.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Rng = preload("res://05_SYSTEMS/rng/rng.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
# V6 : l'arete game_state -> end_conditions a DISPARU. Elle ne servait qu'a lire la
# constante `VIES_INITIALES`, qui n'existe plus : le nombre de vies de depart depend du
# mode, et la correspondance vit dans settings. Un preload sans lecteur est du code mort.
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

const CHEMIN := "res://05_SYSTEMS/game_state/game_state.gd"

# Vocabulaire FERME des trois statuts terminaux, exclusifs et exhaustifs.
enum Statut { EN_COURS, GAGNE, PERDU }
const STATUTS_VALIDES: Array = [Statut.EN_COURS, Statut.GAGNE, Statut.PERDU]

# Premier niveau du catalogue, en numerotation lisible par une personne.
const PREMIER_NIVEAU: int = 1

# --- Champs de l'etat de partie ---
var carte                          # la CARTE COURANTE, portee par l'etat
var niveau: int = PREMIER_NIVEAU   # numero de niveau courant (1 = premier)
var cadence_fantome: int = 0       # parametre de progression du niveau, RECU
var mode: int = Reglages.Mode.NORMAL
var dash_actif: bool = Reglages.DASH_ACTIF_PAR_DEFAUT
var dash_recharge: int = 0
var pac: Vector2i
var pac_dir: Vector2i
var pac_attente: Vector2i
var fantomes: Array = []          # Array[Vector2i], index nominatifs 0..3
var dirs_fantomes: Array = []     # Array[Vector2i]
var dehors: Array = []            # Array[bool] : le fantome est hors de la maison
var sorties_maison: Array = []    # Array[int] : tick de sortie declare
var effrayes: Array = []          # Array[bool] : ce fantome est en etat Effraye
var etats_fantomes: Array = []    # Array[int] : EXACTEMENT un mode par fantome
var pastilles: PackedByteArray = PackedByteArray()
var consommees: int = 0
var total_pose: int = 0
var score: int = 0
var vies: int = 0
var ticks: int = 0
var horloge: int = 0
var effraye_restant: int = 0
var rang_capture: int = 0
var rng_etat: int = 0
var statut: int = Statut.EN_COURS


# Construction initiale COMPLETE et reproductible a partir d'une CARTE et d'une graine.
# `cadence` est le parametre de progression du niveau : il ARRIVE, il n'est jamais lu
# dans une table indexee par niveau. Une valeur non superieure a 1 laisse ghost_movement
# retomber sur le repli declare dans le bloc de parametres.
static func initial(carte_courante, graine: int, cadence: int = 0, reglages: Dictionary = {}) -> Object:
	var s = load(CHEMIN).new()
	var r: Dictionary = Reglages.normaliser(reglages)
	s.carte = carte_courante
	s.niveau = PREMIER_NIVEAU
	s.cadence_fantome = cadence
	s.mode = r["mode"]
	s.dash_actif = r["dash_actif"]
	s.dash_recharge = 0
	s.pac = carte_courante.DEPART_PACMAN
	s.pac_dir = carte_courante.DEPART_DIRECTION
	s.pac_attente = Maze.AUCUNE
	var maison: Dictionary = House.etat_initial(carte_courante)
	s.fantomes = maison["positions"].duplicate()
	s.dehors = maison["dehors"].duplicate()
	s.sorties_maison = maison["sorties"].duplicate()
	s.dirs_fantomes = []
	s.effrayes = []
	s.etats_fantomes = []
	for i in range(s.fantomes.size()):
		s.dirs_fantomes.append(Maze.GAUCHE)
		s.effrayes.append(false)
		s.etats_fantomes.append(Chase.Mode.DISPERSION)
	s.pastilles = Pellets.poser(carte_courante)
	s.total_pose = Pellets.total_pose(s.pastilles)
	s.consommees = 0
	s.score = 0
	# V6 : LE MODE GOUVERNE LES VIES. C'est ici, et nulle part ailleurs, que la regle
	# s'applique — a la NAISSANCE de la partie, quand le mode choisi est connu.
	s.vies = Reglages.vies_initiales(r["mode"])
	s.ticks = 0
	s.horloge = 0
	s.effraye_restant = 0
	s.rang_capture = 0
	s.rng_etat = Rng.graine(graine)
	s.statut = Statut.EN_COURS
	Chase.rafraichir_etats(s)
	return s


# GRAINE DECLAREE du niveau `niveau` d'une partie de graine `graine_partie`. Expose la
# derivation de rng au seul module qui detient l'etat : level_progression n'a ainsi
# aucune arete directe vers rng, et la valeur reste reproductible.
static func graine_du_niveau(graine_partie: int, niveau: int) -> int:
	return Rng.graine_de_niveau(graine_partie, niveau)


# Copie profonde independante : le tick et les preuves ne mutent jamais leur entree.
# La carte est PARTAGEE et non dupliquee : c'est une donnee inerte, jamais mutee.
func clone() -> Object:
	var c = load(CHEMIN).new()
	c.carte = carte
	c.niveau = niveau
	c.cadence_fantome = cadence_fantome
	c.mode = mode
	c.dash_actif = dash_actif
	c.dash_recharge = dash_recharge
	c.pac = pac
	c.pac_dir = pac_dir
	c.pac_attente = pac_attente
	c.fantomes = fantomes.duplicate()
	c.dirs_fantomes = dirs_fantomes.duplicate()
	c.dehors = dehors.duplicate()
	c.sorties_maison = sorties_maison.duplicate()
	c.effrayes = effrayes.duplicate()
	c.etats_fantomes = etats_fantomes.duplicate()
	c.pastilles = pastilles.duplicate()
	c.consommees = consommees
	c.total_pose = total_pose
	c.score = score
	c.vies = vies
	c.ticks = ticks
	c.horloge = horloge
	c.effraye_restant = effraye_restant
	c.rang_capture = rang_capture
	c.rng_etat = rng_etat
	c.statut = statut
	return c


# Egalite profonde CHAMP PAR CHAMP — la base des comparaisons de replay. La carte est
# comparee par son identifiant declare : deux etats sur deux cartes differentes ne sont
# jamais egaux.
func egal_profond(autre: Object) -> bool:
	if carte == null or autre.carte == null:
		return false
	return (carte.meme_carte(autre.carte)
		and niveau == autre.niveau
		and cadence_fantome == autre.cadence_fantome
		and mode == autre.mode
		and dash_actif == autre.dash_actif
		and dash_recharge == autre.dash_recharge
		and pac == autre.pac
		and pac_dir == autre.pac_dir
		and pac_attente == autre.pac_attente
		and fantomes == autre.fantomes
		and dirs_fantomes == autre.dirs_fantomes
		and dehors == autre.dehors
		and sorties_maison == autre.sorties_maison
		and effrayes == autre.effrayes
		and etats_fantomes == autre.etats_fantomes
		and pastilles == autre.pastilles
		and consommees == autre.consommees
		and total_pose == autre.total_pose
		and score == autre.score
		and vies == autre.vies
		and ticks == autre.ticks
		and horloge == autre.horloge
		and effraye_restant == autre.effraye_restant
		and rang_capture == autre.rang_capture
		and rng_etat == autre.rng_etat
		and statut == autre.statut)


# Validation STRUCTURELLE (ligne core.error_handling). Aucune I/O, aucune exception :
# un etat hors domaine se CONSTATE, il ne leve pas.
func est_valide() -> bool:
	if carte == null:
		return false
	if not (statut in STATUTS_VALIDES):
		return false
	if not Reglages.valide(mode):
		return false
	if niveau < PREMIER_NIVEAU:
		return false
	if not carte.praticable(pac):
		return false
	for i in range(fantomes.size()):
		if dehors[i] and not carte.praticable(fantomes[i]):
			return false
		if not (etats_fantomes[i] in Chase.MODES_VALIDES):
			return false
	if consommees + Pellets.total_pose(pastilles) != total_pose:
		return false
	# V6 : la borne haute est la PLUS GRANDE valeur qu'un mode puisse accorder, pas celle
	# du mode courant. Raison mesuree, pas theorique : le mode d'une partie EN COURS peut
	# changer (session.appliquer_reglages, ecran d'options ouvert depuis la pause) sans que
	# le compteur deja entame soit rejuste — le rejuster donnerait ou retirerait des vies au
	# milieu d'une partie. Le domaine reste donc un ENCADREMENT structurel ; la regle du
	# mode s'exerce a la naissance de la partie, ou elle est EXACTE.
	if vies < 0 or vies > Reglages.vies_maximales():
		return false
	return true
