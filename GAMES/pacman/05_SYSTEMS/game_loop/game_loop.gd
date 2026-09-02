# game_loop.gd — composition d'UN tick dans un ordre FIGE et DECLARE
# (lignes loop.tick, loop.events, core.main_loop, loop.tick_order_with_dash,
# loop.emits_sound_events).
#
# Ne mute JAMAIS l'etat d'entree : il produit un NOUVEL etat (clone puis mutation).
# N'est appele que lorsque l'etat d'application AUTORISE le tick — la pause gele donc
# par ABSENCE D'APPEL, et non par un drapeau lu ici : la COMPOSITION du tick est
# inchangee par rapport au run V1, ce qui laisse valides les preuves V1 du tick.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Score = preload("res://05_SYSTEMS/score/score.gd")
const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")

const AUCUNE := Maze.AUCUNE

# ORDRE FIGE du tick — declare ici, et nulle part ailleurs. Le budget de dash s'insere
# entre l'horloge et le deplacement du joueur : il PRODUIT un nombre de cases, il ne
# deplace pas.
const ORDRE: Array = [
	"entree", "horloge", "budget_dash", "pac", "fantomes", "consommation", "contacts", "statut",
]

# Vocabulaire ferme des evenements du tick (ligne loop.events) : c'est la SEULE prise a
# laquelle un adaptateur de retour peut se brancher.
const EV_PASTILLE := "pastille"
const EV_SUPER := "super"
const EV_BASCULE := "bascule"
const EV_CAPTURE := "capture"
const EV_VIE_PERDUE := "vie_perdue"
const EV_FIN := "fin"


# Un tick. `action` est une direction du vocabulaire ferme, ou AUCUNE ; `dash_demande`
# porte l'intention DEDIEE de dash, distincte des quatre directions.
# Retourne {"etat", "evenements", "evenements_sonores"}.
static func step(entree, action: Vector2i, dash_demande: bool = false, ouverture_menu: bool = false) -> Dictionary:
	var avant = entree
	var s = entree.clone()
	var evenements: Array = []

	if Status.est_terminal(s.statut):
		return {
			"etat": s,
			"evenements": evenements,
			"evenements_sonores": Events.evenements_sonores(avant, s, ouverture_menu),
		}

	# 1. ENTREE — la demande de direction entre par ce seul point.
	Player.demander(s, action)

	# 2. HORLOGE — la bascule d'etat inverse la direction des fantomes hors maison.
	s.ticks += 1
	if Chase.avancer(s):
		Ghosts.inverser_tous(s)
		evenements.append(EV_BASCULE)

	# 3. BUDGET DE DASH — un NOMBRE DE CASES, jamais un deplacement.
	var budget: int = Dash.appliquer(s, dash_demande)

	# Positions AVANT deplacement : necessaires a la detection du croisement.
	var pac_avant: Vector2i = s.pac
	var fantomes_avant: Array = s.fantomes.duplicate()

	# 4. DEPLACEMENT DE PAC-MAN, dans la limite du budget.
	Player.pas(s, budget)

	# 5. DEPLACEMENT DES FANTOMES (sortie de maison, puis pas).
	House.mettre_a_jour(s)
	Ghosts.pas(s)

	# 6. CONSOMMATION du collectible de la case occupee.
	var r: Dictionary = Pellets.consommer(s.carte, s.pastilles, s.pac, s.consommees)
	s.pastilles = r["grille"]
	s.consommees = r["consommees"]
	if r["contenu"] != Pellets.Contenu.VIDE:
		var est_super: bool = r["contenu"] == Pellets.Contenu.SUPER
		Score.ajouter(s, Score.valeur_collectible(est_super))
		if est_super:
			Chase.armer_effraye(s)
			Ghosts.inverser_tous(s)
			evenements.append(EV_SUPER)
		else:
			evenements.append(EV_PASTILLE)

	# 7. CONTACTS, sur les positions AVANT et APRES.
	var touches: Array = Contacts.detecter(pac_avant, s.pac, fantomes_avant, s.fantomes, s.dehors)
	var issue: Dictionary = Contacts.resoudre(s, touches)
	for _c in issue["captures"]:
		evenements.append(EV_CAPTURE)
	if issue["hostile"]:
		End.perdre_une_vie(s)
		evenements.append(EV_VIE_PERDUE)

	# 8. STATUT — aucun chemin de sortie ne laisse la partie sans statut terminal.
	Status.appliquer(s)
	if Status.est_terminal(s.statut):
		evenements.append(EV_FIN)

	# TRANSPORT des evenements sonores dans la sortie du tick : la production des six
	# moments nommes appartient a game_events, cette ligne n'en revendique que le
	# transport — c'est la PRISE unique de la couche de presentation.
	return {
		"etat": s,
		"evenements": evenements,
		"evenements_sonores": Events.evenements_sonores(avant, s, ouverture_menu),
	}


# Meme tick, pilote par des INTENTIONS du vocabulaire ferme : c'est la porte que le
# clavier, la manette, le tactile et le bot empruntent indifferemment. La traduction
# rang d'intention -> direction passe par l'ordre fixe de maze.DIRECTIONS, source unique.
static func step_intentions(entree, intentions: Array, ouverture_menu: bool = false) -> Dictionary:
	var direction: Vector2i = AUCUNE
	var dash_demande: bool = false
	for i in intentions:
		if Intents.est_direction(i):
			direction = Maze.DIRECTIONS[Intents.rang_direction(i)]
		elif i == Intents.Intention.DASH:
			dash_demande = true
	return step(entree, direction, dash_demande, ouverture_menu)
