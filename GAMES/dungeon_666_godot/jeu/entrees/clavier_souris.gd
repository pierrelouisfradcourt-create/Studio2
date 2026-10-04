extends RefCounted
## Le clavier et la souris. Portage de GAMES/dungeon_666/src/input/input.mjs (KEY_MOVE,
## KEY_ACTION, syncMouseButtons, et les sections « Clavier » et « Souris » de frame()).
## Les touches sont des touches PHYSIQUES (position sur le clavier), comme `ev.code` du web :
## ZQSD sur un AZERTY, WASD sur un QWERTY.

const SOURIS_INACTIVE_MS := 2500.0 # sans mouvement souris, on repasse en visée assistée
const VISEE_MIN := 8.0 # px : curseur trop près du héros = pas de visée
const DEPLACEMENTS := {
	KEY_W: [0.0, -1.0], KEY_UP: [0.0, -1.0], KEY_S: [0.0, 1.0], KEY_DOWN: [0.0, 1.0],
	KEY_A: [-1.0, 0.0], KEY_LEFT: [-1.0, 0.0], KEY_D: [1.0, 0.0], KEY_RIGHT: [1.0, 0.0],
}
const ACTIONS := {
	KEY_SPACE: "dash", KEY_SHIFT: "dash", KEY_K: "dash",
	KEY_J: "attack", KEY_L: "skill1", KEY_E: "skill2", KEY_F: "skill3",
}
const EMPLACEMENTS := ["skill1", "skill2", "skill3"]
const BOUTONS := {MOUSE_BUTTON_LEFT: "attack", MOUSE_BUTTON_RIGHT: "skill1"} # la commande de chaque bouton de souris
const TOUCHES_PAUSE := [KEY_ESCAPE, KEY_P]
const TOUCHE_ATTAQUE := KEY_J # maintenue : enchaîne le combo ; jauge pleine : lance l'ultime

var touches := {} # touche physique enfoncée -> true
var souris_x := 0.0
var souris_y := 0.0
var gauche := false
var droite := false
var dernier_mouvement_ms := -1e9
var dedans := false # la souris a déjà bougé dans la fenêtre

var _fronts: Dictionary # partagé avec la racine

func _init(fronts: Dictionary) -> void:
	_fronts = fronts

## La touche physique d'un événement (à défaut, sa touche logique : événements synthétiques).
static func code(ev: InputEventKey) -> Key:
	return ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode

static func est_pause(touche: Key) -> bool:
	return touche in TOUCHES_PAUSE

func touche_enfoncee(touche: Key) -> void:
	touches[touche] = true
	if ACTIONS.has(touche):
		_fronts[ACTIONS[touche]] = true

func touche_relachee(touche: Key) -> void:
	touches.erase(touche)

func bouton_enfonce(bouton: MouseButton, p: Vector2) -> void:
	_noter_position(p)
	if bouton == MOUSE_BUTTON_LEFT and not gauche:
		gauche = true
		_fronts.attack = true
	elif bouton == MOUSE_BUTTON_RIGHT and not droite:
		droite = true
		_fronts.skill1AimX = 0.0 # visée de l'emplacement 1 : celle de la souris, posée par completer_souris
		_fronts.skill1AimY = 0.0
		_fronts.skill1 = true

func bouton_relache(bouton: MouseButton) -> void:
	if bouton == MOUSE_BUTTON_LEFT:
		gauche = false
	elif bouton == MOUSE_BUTTON_RIGHT:
		droite = false

## Mouvement : le masque des boutons rattrape un relâcher qui nous aurait échappé (hors fenêtre).
func mouvement(p: Vector2, masque: int) -> void:
	_noter_position(p)
	if not (masque & MOUSE_BUTTON_MASK_LEFT):
		gauche = false
	if not (masque & MOUSE_BUTTON_MASK_RIGHT):
		droite = false

func _noter_position(p: Vector2) -> void:
	souris_x = p.x
	souris_y = p.y
	dernier_mouvement_ms = Time.get_ticks_msec()
	dedans = true

func tout_relacher() -> void:
	touches.clear()
	gauche = false
	droite = false

## Pour l'AFFICHAGE (retour « enfoncé » des boutons du HUD) : note dans `t` les commandes tenues.
func noter_tenues(t: Dictionary) -> void:
	for touche in touches:
		if ACTIONS.has(touche):
			t[ACTIONS[touche]] = true
	if gauche:
		t.attack = true
	if droite:
		t.skill1 = true

## Pour l'AFFICHAGE (ligne de visée) : la direction que la souris vise depuis le héros, unitaire ;
## ZERO quand la visée est assistée (souris inutilisée, ou curseur sur le héros).
func visee(tactile: bool, heros: Vector2) -> Vector2:
	var fraiche := not tactile and dedans and Time.get_ticks_msec() - dernier_mouvement_ms < SOURIS_INACTIVE_MS
	var d := Vector2(souris_x, souris_y) - heros
	return d.normalized() if (fraiche or gauche) and d.length() > VISEE_MIN else Vector2.ZERO

func completer_clavier(f: Dictionary) -> void:
	var kx := 0.0
	var ky := 0.0
	for touche in touches:
		if DEPLACEMENTS.has(touche):
			kx += DEPLACEMENTS[touche][0]
			ky += DEPLACEMENTS[touche][1]
	if kx != 0.0 or ky != 0.0:
		var l := sqrt(kx * kx + ky * ky)
		f.moveX = kx / l
		f.moveY = ky / l
	if touches.has(TOUCHE_ATTAQUE):
		f.attack = true

## Souris : visée manuelle vers le curseur tant qu'elle est utilisée. `heros` : sa position à l'écran.
func completer_souris(f: Dictionary, tactile: bool, heros: Vector2) -> void:
	var fraiche := not tactile and dedans and Time.get_ticks_msec() - dernier_mouvement_ms < SOURIS_INACTIVE_MS
	if gauche:
		f.attack = true
	if not (fraiche or gauche):
		return
	var dx := souris_x - heros.x
	var dy := souris_y - heros.y
	var l := sqrt(dx * dx + dy * dy)
	if l <= VISEE_MIN:
		return
	f.aimX = dx / l
	f.aimY = dy / l
	# Un emplacement pressé au clavier ou à la souris vise où pointe la souris.
	for e: String in EMPLACEMENTS:
		if f[e + "Pressed"] and not tactile and f[e + "AimX"] == 0.0 and f[e + "AimY"] == 0.0:
			f[e + "AimX"] = f.aimX
			f[e + "AimY"] = f.aimY
