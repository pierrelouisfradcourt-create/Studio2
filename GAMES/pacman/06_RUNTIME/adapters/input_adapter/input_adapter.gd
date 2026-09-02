# input_adapter.gd — CANAL D'ENTREE PUBLIC UNIQUE (lignes input.keyboard,
# input.restart_key, input.device_translation, core.input).
#
# V2 : traduit les evenements du peripherique en INTENTION du vocabulaire ferme, ou en
# « aucune », par LECTURE DE LA TABLE DE LIAISONS — et rien d'autre. Plus AUCUNE table
# de codes de touches n'est ecrite ici : la reconnaissance d'une touche, d'un bouton ou
# d'un contact n'existe que du cote 06_RUNTIME, ce qui donne au comptage statique sur
# 05_SYSTEMS son controle positif et le rend falsifiable dans les deux sens.
#
# Le bot de solvabilite et le replay passent par ce meme canal — jamais par une ecriture
# directe dans l'etat.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")

# Vocabulaire ferme des commandes (au-dela des quatre directions). Chacune est la
# LECTURE d'une intention du vocabulaire pur, jamais une seconde table de touches.
const CMD_RELANCE := "relance"
const CMD_SORTIE := "sortie"
const CMD_PAUSE := "pause"
const CMD_DASH := "dash"
const AUCUNE_ACTION := {"genre": "aucune"}

# Correspondance INTENTION -> commande, dans l'ordre declare.
const COMMANDES: Dictionary = {
	Intents.Intention.VALIDER: CMD_RELANCE,
	Intents.Intention.RETOUR: CMD_SORTIE,
	Intents.Intention.PAUSE: CMD_PAUSE,
	Intents.Intention.DASH: CMD_DASH,
}


# Direction portee par une intention de direction ; AUCUNE sinon. La traduction passe
# par le RANG dans l'ordre fixe de maze.DIRECTIONS : une source unique, jamais deux
# declarations de directions qui pourraient diverger.
static func direction_de_intention(intention: int) -> Vector2i:
	var rang: int = Intents.rang_direction(intention)
	if rang == Intents.RANG_ABSENT:
		return Maze.AUCUNE
	return Maze.DIRECTIONS[rang]


# Traduction d'une INTENTION en action du vocabulaire d'action. Point unique : les trois
# peripheriques y arrivent apres lecture de la meme table.
static func action_de_intention(intention: int) -> Dictionary:
	if Intents.est_direction(intention):
		return {"genre": "direction", "direction": direction_de_intention(intention)}
	if COMMANDES.has(intention):
		return {"genre": "commande", "commande": COMMANDES[intention]}
	return AUCUNE_ACTION


# Traduction d'un code de touche en action. Une touche non liee rend « aucune entree » :
# jamais une exception, jamais un effet de bord.
static func traduire(keycode: int) -> Dictionary:
	return action_de_intention(Bindings.intention_de_touche(keycode))


# Meme traduction pour un bouton de manette : MEME table, MEME vocabulaire, MEME sortie.
static func traduire_bouton(bouton: int) -> Dictionary:
	return action_de_intention(Bindings.intention_de_bouton(bouton))


# Meme traduction pour une zone tactile declaree.
static func traduire_zone(zone: String) -> Dictionary:
	return action_de_intention(Bindings.intention_de_zone(zone))


# INTENTION portee par un code de touche / un bouton / une zone — la sortie V2, commune
# aux trois peripheriques.
static func intention_de_touche(keycode: int) -> int:
	return Bindings.intention_de_touche(keycode)


static func intention_de_bouton(bouton: int) -> int:
	return Bindings.intention_de_bouton(bouton)


static func intention_de_zone(zone: String) -> int:
	return Bindings.intention_de_zone(zone)


# Code de touche d'un evenement du moteur ; -1 si l'evenement n'est pas un appui.
static func keycode_de_event(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode
	return -1


# Index de bouton d'un evenement de manette ; -1 si l'evenement n'est pas un appui.
static func bouton_de_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index
	return -1


# Direction NORMALISEE : toute valeur hors du vocabulaire ferme devient « aucune ». Le
# bot passe par cette porte comme le clavier — il n'existe pas de second canal.
static func normaliser_direction(direction: Vector2i) -> Vector2i:
	if Maze.DIRECTIONS.has(direction):
		return direction
	return Maze.AUCUNE


# Direction portee par un code de touche (AUCUNE si la touche n'est pas directionnelle).
static func direction_de_touche(keycode: int) -> Vector2i:
	var action: Dictionary = traduire(keycode)
	if action["genre"] == "direction":
		return action["direction"]
	return Maze.AUCUNE


static func direction_de_bouton(bouton: int) -> Vector2i:
	var action: Dictionary = traduire_bouton(bouton)
	if action["genre"] == "direction":
		return action["direction"]
	return Maze.AUCUNE


static func _est_commande(action: Dictionary, commande: String) -> bool:
	return action["genre"] == "commande" and action["commande"] == commande


# La touche demande-t-elle la relance depuis l'ecran de fin ?
static func est_relance(keycode: int) -> bool:
	return _est_commande(traduire(keycode), CMD_RELANCE)


# La touche demande-t-elle la sortie de l'application ?
static func est_sortie(keycode: int) -> bool:
	return _est_commande(traduire(keycode), CMD_SORTIE)


static func est_pause(keycode: int) -> bool:
	return _est_commande(traduire(keycode), CMD_PAUSE)


static func est_dash(keycode: int) -> bool:
	return _est_commande(traduire(keycode), CMD_DASH)
