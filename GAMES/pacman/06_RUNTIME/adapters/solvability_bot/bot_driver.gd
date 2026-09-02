# bot_driver.gd — pilotage du bot de solvabilite (ligne solvability.drive_public_input).
#
# Emet des directions sur le MEME canal d'entree public que le clavier : l'action est
# passee a game_loop.step(), exactement comme la demande d'un joueur. Le bot ne calcule
# AUCUN deplacement lui-meme, il ne force JAMAIS un champ de l'etat : il demande, le jeu
# decide.
#
# CORRECTION B1 (red-team s6) : BOUCLE FERMEE. `choisir_action` est appelee a CHAQUE
# tick sur l'etat COURANT — positions et etats des quatre fantomes compris. Une perte de
# vie (retour des entites au depart, collectibles deja manges conserves) est donc
# constatee au tick suivant sans aucune resynchronisation.
extends RefCounted

const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const InputChannel = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Planner = preload("res://06_RUNTIME/adapters/solvability_bot/route_planner.gd")


# L'action du tick : une direction du vocabulaire ferme, ou AUCUNE. Fonction PURE de
# l'etat observe — meme etat, meme action, toujours.
static func choisir_action(s) -> Vector2i:
	return InputChannel.normaliser_direction(Planner.prochain_pas(s))


# Joue une partie complete en boucle fermee depuis un etat de depart, dans un budget de
# ticks DECLARE. Rend l'etat final et le nombre de ticks reellement joues.
static func jouer(depart, budget: int) -> Dictionary:
	var s = depart
	var t: int = 0
	while t < budget and s.statut == State.Statut.EN_COURS:
		s = Loop.step(s, choisir_action(s))["etat"]
		t += 1
	return {"etat": s, "ticks": t}


# Meme boucle, depuis une graine : le point d'entree normal de l'oracle de solvabilite.
static func jouer_depuis_graine(carte, graine: int, budget: int, cadence: int = 0) -> Dictionary:
	return jouer(State.initial(carte, graine, cadence), budget)
