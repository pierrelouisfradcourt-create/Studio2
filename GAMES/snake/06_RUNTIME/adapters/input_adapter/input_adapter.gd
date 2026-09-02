# input_adapter.gd — lignes core.input + input.adapter. Traduit une TOUCHE du moteur en
# action normalisee du vocabulaire ferme. AUCUN garde de gameplay ici : le refus du
# demi-tour vit dans core.direction_rules. Canal PUBLIC et unique (clavier ET bot).
# RefCounted : la traduction est pure et testable sans InputEvent vivant.
extends RefCounted

const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

# Vocabulaire ferme de commandes non directionnelles.
const CMD_PAUSE := "pause"
const CMD_RELANCE := "relance"
const CMD_SORTIE := "sortie"

# Traduit un keycode en action normalisee :
#   {"kind":"direction", "dir":Vector2i}  |  {"kind":"commande", "commande":String}
#   |  {"kind":"aucun"}
static func traduire_keycode(keycode: int) -> Dictionary:
	match keycode:
		KEY_UP, KEY_W:
			return {"kind": "direction", "dir": DR.HAUT}
		KEY_DOWN, KEY_S:
			return {"kind": "direction", "dir": DR.BAS}
		KEY_LEFT, KEY_A:
			return {"kind": "direction", "dir": DR.GAUCHE}
		KEY_RIGHT, KEY_D:
			return {"kind": "direction", "dir": DR.DROITE}
		KEY_P, KEY_SPACE:
			return {"kind": "commande", "commande": CMD_PAUSE}
		KEY_R:
			return {"kind": "commande", "commande": CMD_RELANCE}
		KEY_ESCAPE, KEY_Q:
			return {"kind": "commande", "commande": CMD_SORTIE}
		_:
			return {"kind": "aucun"}

# Extrait un keycode d'un InputEvent clavier presse (branche runtime). Renvoie -1 sinon.
static func keycode_de_event(event) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode
	return -1
