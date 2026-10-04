extends RefCounted
## La manette. Portage de readPad() de GAMES/dungeon_666/src/input/input.mjs : mêmes zones
## mortes, même disposition (A / LB dash, X / RT attaque, Start pause) ; combat V3 : B, Y et RB
## sont les emplacements 1, 2 et 3, et l'ultime part en gardant X ou RT enfoncé, jauge pleine. Le web SONDE la manette à chaque pas ; ici on écoute ses événements, et les
## fronts s'accumulent comme ceux des doigts : un appui bref entre deux pas n'est jamais perdu.

const ZONE_MORTE := 0.22 # stick gauche, par axe
const VISEE_MIN := 0.35 # norme du stick droit en deçà de laquelle la visée reste assistée
const SEUIL_GACHETTE := 0.5 # la gâchette droite compte comme un bouton au-delà
const BOUTON_PAUSE := JOY_BUTTON_START
const BOUTON_ATTAQUE := JOY_BUTTON_X
const ACTIONS := {
	JOY_BUTTON_A: "dash", JOY_BUTTON_LEFT_SHOULDER: "dash", JOY_BUTTON_B: "skill1",
	JOY_BUTTON_X: "attack", JOY_BUTTON_Y: "skill2", JOY_BUTTON_RIGHT_SHOULDER: "skill3",
}
const AUCUNE := -1

## La manette écoutée : celle du dernier appui franc (bouton, ou axe sorti de sa zone morte).
var appareil := AUCUNE
var axes := {} # JoyAxis -> valeur
var tenus := {} # JoyButton enfoncé -> true
var fronts := {} # action -> true, jusqu'au prochain pas

func bouton(appareil_ev: int, index: JoyButton, enfonce: bool) -> void:
	if not _ecouter(appareil_ev, enfonce):
		return
	if not enfonce:
		tenus.erase(index)
		return
	if not tenus.has(index) and ACTIONS.has(index):
		fronts[ACTIONS[index]] = true
	tenus[index] = true

func axe(appareil_ev: int, index: JoyAxis, valeur: float) -> void:
	if not _ecouter(appareil_ev, absf(valeur) > ZONE_MORTE):
		return
	var avant: float = axes.get(index, 0.0)
	axes[index] = valeur
	if index == JOY_AXIS_TRIGGER_RIGHT and valeur > SEUIL_GACHETTE and avant <= SEUIL_GACHETTE:
		fronts.attack = true

## Vrai si l'événement vient de la manette écoutée ; un appui franc d'une autre la remplace.
func _ecouter(appareil_ev: int, franc: bool) -> bool:
	if appareil_ev == appareil:
		return true
	if not franc:
		return false
	appareil = appareil_ev
	tout_relacher()
	return true

func debranchee(appareil_ev: int) -> void:
	if appareil_ev == appareil:
		appareil = AUCUNE
		tout_relacher()

func tout_relacher() -> void:
	axes.clear()
	tenus.clear()

func vider() -> void:
	fronts.clear()

func completer(f: Dictionary) -> void:
	if appareil == AUCUNE:
		return
	var lx := _axe_gauche(JOY_AXIS_LEFT_X)
	var ly := _axe_gauche(JOY_AXIS_LEFT_Y)
	if lx != 0.0 or ly != 0.0:
		f.moveX = lx
		f.moveY = ly
	var rx: float = axes.get(JOY_AXIS_RIGHT_X, 0.0)
	var ry: float = axes.get(JOY_AXIS_RIGHT_Y, 0.0)
	if sqrt(rx * rx + ry * ry) > VISEE_MIN:
		f.aimX = rx
		f.aimY = ry
	if tenus.has(BOUTON_ATTAQUE) or axes.get(JOY_AXIS_TRIGGER_RIGHT, 0.0) > SEUIL_GACHETTE:
		f.attack = true
	for action: String in fronts:
		f[action + "Pressed"] = true

func _axe_gauche(index: JoyAxis) -> float:
	var v: float = axes.get(index, 0.0)
	return v if absf(v) > ZONE_MORTE else 0.0
