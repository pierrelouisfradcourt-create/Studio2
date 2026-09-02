# input_adapter.gd — ligne core.input. Traduit une TOUCHE du moteur en action normalisee du
# vocabulaire ferme (le MEME que le bot : canal public unique). Aucun garde de gameplay ici.
# RefCounted : la traduction est pure et testable sans InputEvent vivant.
extends RefCounted

const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

# Vocabulaire ferme de commandes non directionnelles (pas de pause en Breakout V1).
const CMD_RELANCE := "relance"
const CMD_SORTIE := "sortie"

# Traduit un keycode en action normalisee :
#   {"kind":"direction", "dir":int}  |  {"kind":"commande", "commande":String}  |  {"kind":"aucun"}
# dir vaut l'action du vocabulaire ferme de input_rules (GAUCHE=-1, DROITE=+1).
static func traduire_keycode(keycode: int) -> Dictionary:
	match keycode:
		KEY_LEFT, KEY_A:
			return {"kind": "direction", "dir": InputRules.GAUCHE}
		KEY_RIGHT, KEY_D:
			return {"kind": "direction", "dir": InputRules.DROITE}
		KEY_R:
			return {"kind": "commande", "commande": CMD_RELANCE}
		KEY_ESCAPE, KEY_Q:
			return {"kind": "commande", "commande": CMD_SORTIE}
		_:
			return {"kind": "aucun"}

# Extrait un keycode d'un InputEvent clavier presse (branche runtime). -1 sinon.
static func keycode_de_event(event) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode
	return -1
