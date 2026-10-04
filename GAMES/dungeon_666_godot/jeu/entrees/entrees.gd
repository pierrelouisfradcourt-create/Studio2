extends Control
## Les entrées : tactile multi-doigts, clavier / souris, manette → un InputFrame par pas de
## simulation (voir GAMES/dungeon_666/src/sim/player.mjs). Portage de src/input/input.mjs.
##
## COMBAT V3 : trois emplacements d'action (skill1, skill2, skill3), chacun avec sa visée ; plus
## de bouton Super — l'ultime part quand l'ATTAQUE reste tenue, jauge pleine (règle : sim/player.gd).
## Clavier : clic droit = emplacement 1, E = 2, F = 3 ; clic gauche (ou J) tenu = attaque.
## Manette : B, Y, RB, visés au stick droit. Tactile (jeu/entrees/tactile.gd) : gros bouton
## d'attaque, les trois emplacements en arc autour, le dash à part. Un emplacement part au
## relâcher (tap = visée assistée, glisser = viser, retour au centre = annuler). Sur l'attaque :
## appui bref = un coup au relâcher ; GLISSER vise sans tenir l'attaque et le coup part au
## relâcher (un glisser-relâcher n'arme jamais l'ultime) ; pouce MAINTENU sans glisser = attaque
## tenue.
##
## Les fronts (…Pressed) s'accumulent jusqu'à être consommés par le prochain pas : aucun tap
## perdu, même si l'affichage va plus vite que la simulation ou pendant un gel d'impact.
## Cette vue ne dessine rien et ne connaît de la partie que son mode et la position du héros.
##
## Qui écoute quoi : un APPUI (doigt, clic, touche) n'est pris que s'il n'a été consommé par
## aucun Control (`_unhandled_input`) : toucher le bouton pause ou un menu ne fait pas attaquer.
## Un RELÂCHER ou un GLISSER est toujours entendu (`_input`) : rien ne reste « collé » quand un
## menu s'ouvre sous un doigt posé.

signal pause_demandee ## Échap, P, Start, bouton retour d'Android
## Une touche, un bouton de souris ou de manette vient d'enfoncer la commande `id` (attack, dash,
## skill1..skill3). Pour l'AFFICHAGE seulement (le HUD enfonce son bouton) : le jeu, lui, lit `lire()`.
signal commande_enfoncee(id: String)

const Tactile = preload("res://jeu/entrees/tactile.gd")
const ClavierSouris = preload("res://jeu/entrees/clavier_souris.gd")
const Manette = preload("res://jeu/entrees/manette.gd")

const ACTIONS := ["attack", "dash", "skill1", "skill2", "skill3"]
const EMPLACEMENTS := ["skill1", "skill2", "skill3"]
const DENSITE_ANDROID := 160.0 # points par pouce d'un « px CSS » sur Android
const ECHELLE_MIN := 0.5
const ECHELLE_MAX := 3.0
const BOUTONS_SOURIS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]

var _app: Node
var _partie: Node
var _tactile_actif := false
## Fronts accumulés depuis le dernier pas (doigts, clavier, souris), visée de chaque emplacement,
## et visée du coup parti au relâcher d'un glisser sur le bouton d'attaque (aimX, aimY).
var _fronts := {
	"attack": false, "dash": false, "skill1": false, "skill2": false, "skill3": false, "aimX": 0.0, "aimY": 0.0,
	"skill1AimX": 0.0, "skill1AimY": 0.0, "skill2AimX": 0.0, "skill2AimY": 0.0, "skill3AimX": 0.0, "skill3AimY": 0.0,
}
var _doigts := Tactile.new(_fronts)
var _clavier := ClavierSouris.new(_fronts)
var _manette := Manette.new()

func brancher(app: Node, partie: Node) -> void:
	_app = app
	_partie = partie

func _ready() -> void:
	_tactile_actif = DisplayServer.is_touchscreen_available()
	# Le bouton retour d'Android demande la pause au lieu de quitter le jeu.
	get_tree().quit_on_go_back = false
	get_viewport().size_changed.connect(_disposer)
	Input.joy_connection_changed.connect(_sur_manette_branchee)
	_disposer()

# ---------------------------------------------------------------- ce que la vue expose

## L'InputFrame du pas. Les fronts accumulés sont rendus une fois, puis effacés.
func lire() -> Dictionary:
	var f: Dictionary = D6Game.empty_input()
	for action: String in ACTIONS:
		f[action + "Pressed"] = _fronts[action]
	for e: String in EMPLACEMENTS:
		f[e + "AimX"] = _fronts[e + "AimX"]
		f[e + "AimY"] = _fronts[e + "AimY"]
	_clavier.completer_clavier(f)
	_doigts.completer(f)
	_clavier.completer_souris(f, _tactile_actif, _heros_a_l_ecran())
	_manette.completer(f)
	# Coup parti au relâcher d'un glisser : il part dans la direction glissée.
	if _fronts.attack and (_fronts.aimX != 0.0 or _fronts.aimY != 0.0):
		f.aimX = _fronts.aimX
		f.aimY = _fronts.aimY
	vider()
	return f

## Oublie les fronts accumulés (ouverture et fermeture d'un menu). Ce qui est TENU reste tenu.
func vider() -> void:
	for action: String in ACTIONS:
		_fronts[action] = false
	for e: String in EMPLACEMENTS:
		_fronts[e + "AimX"] = 0.0
		_fronts[e + "AimY"] = 0.0
	_fronts.aimX = 0.0
	_fronts.aimY = 0.0
	_manette.vider()

## Vrai si le joueur utilise l'écran tactile (dernier périphérique utilisé).
func tactile() -> bool:
	return _tactile_actif

## La disposition des commandes tactiles pour le HUD, en unités du viewport :
## {visible, stick: {active, baseX, baseY, knobX, knobY, r}, buttons: [{id, x, y, r, pressed, dragging, dx, dy, held}]}.
func interface_tactile() -> Dictionary:
	return _doigts.interface(_tactile_actif)

## Les commandes TENUES au clavier, à la souris ou à la manette, {id: true} : pour l'affichage.
func tenues() -> Dictionary:
	var t := {}
	if not _tactile_actif:
		_clavier.noter_tenues(t)
		_manette.noter_tenues(t)
	return t

## La direction visée au bureau (stick droit, sinon souris), unitaire ; ZERO en visée assistée.
## Pour l'affichage de la ligne de visée : la même direction que celle posée dans `lire()`.
func visee_bureau() -> Vector2:
	var stick := _manette.visee()
	return stick if stick != Vector2.ZERO else _clavier.visee(_tactile_actif, _heros_a_l_ecran())

# ---------------------------------------------------------------- événements

func _input(ev: InputEvent) -> void:
	if _souris_emulee(ev):
		return
	if ev is InputEventScreenTouch:
		_tactile_actif = true # un tap sur un menu compte aussi : les commandes sont là au premier pas
		if not ev.pressed:
			_doigts.relacher(ev.index, ev.canceled)
	elif ev is InputEventScreenDrag:
		_doigts.glisser(ev.index, ev.position)
	elif ev is InputEventMouseMotion:
		_clavier.mouvement(ev.position, ev.button_mask)
	elif ev is InputEventMouseButton:
		if not ev.pressed:
			_clavier.bouton_relache(ev.button_index)
		elif ev.button_index in BOUTONS_SOURIS:
			_tactile_actif = false
	elif ev is InputEventKey:
		_sur_touche(ev)
	elif ev is InputEventJoypadButton:
		_manette.bouton(ev.device, ev.button_index, ev.pressed)
		if ev.pressed and Manette.ACTIONS.has(ev.button_index):
			commande_enfoncee.emit(Manette.ACTIONS[ev.button_index])
		if ev.pressed and ev.button_index == Manette.BOUTON_PAUSE:
			pause_demandee.emit()
	elif ev is InputEventJoypadMotion:
		_manette.axe(ev.device, ev.axis, ev.axis_value)

func _sur_touche(ev: InputEventKey) -> void:
	var touche := ClavierSouris.code(ev)
	if not ev.pressed:
		_clavier.touche_relachee(touche)
	elif not ev.echo and ClavierSouris.est_pause(touche):
		pause_demandee.emit()

func _unhandled_input(ev: InputEvent) -> void:
	if _souris_emulee(ev):
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_doigts.appuyer(ev.index, ev.position)
	elif ev is InputEventMouseButton:
		if ev.pressed:
			_clavier.bouton_enfonce(ev.button_index, ev.position)
			if ClavierSouris.BOUTONS.has(ev.button_index):
				commande_enfoncee.emit(ClavierSouris.BOUTONS[ev.button_index])
	elif ev is InputEventKey:
		var touche := ClavierSouris.code(ev)
		if ev.pressed and not ev.echo and not ClavierSouris.est_pause(touche):
			_tactile_actif = false
			_clavier.touche_enfoncee(touche)
			if ClavierSouris.ACTIONS.has(touche):
				commande_enfoncee.emit(ClavierSouris.ACTIONS[touche])

## Le doigt et la souris sont deux périphériques distincts : une souris fabriquée à partir d'un
## doigt (si le projet active un jour `emulate_mouse_from_touch` pour ses boutons) est ignorée.
func _souris_emulee(ev: InputEvent) -> bool:
	return ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION

func _notification(quoi: int) -> void:
	match quoi:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			pause_demandee.emit()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_tout_relacher()

## Hors du jeu (titre, Ville, menu, pause), les fronts ne s'accumulent pas : un tap donné dans
## un menu ne part pas en dash à la reprise.
func _process(_delta: float) -> void:
	if not _en_jeu():
		vider()

func _en_jeu() -> bool:
	if _partie == null:
		return true
	if _partie.game == null or _partie.en_pause or _partie.game.mode != "play":
		return false
	return _app == null or _app.ecran == "jeu"

func _tout_relacher() -> void:
	_doigts.tout_relacher()
	_clavier.tout_relacher()
	_manette.tout_relacher()

func _sur_manette_branchee(appareil: int, branchee: bool) -> void:
	if not branchee:
		_manette.debranchee(appareil)

# ---------------------------------------------------------------- disposition

func _disposer() -> void:
	_doigts.disposer(get_viewport_rect().size, _marges_sures(), _echelle_css())

## Unités du viewport par pixel de la fenêtre (l'étirement `canvas_items`).
func _unites_par_pixel() -> float:
	var fenetre := get_window().size
	if fenetre.x <= 0:
		return 1.0
	return get_viewport_rect().size.x / float(fenetre.x)

## Unités du viewport par « px CSS » : les longueurs de la version web gardent leur taille
## physique sous le pouce, quelle que soit la définition de l'écran.
func _echelle_css() -> float:
	var densite := DisplayServer.screen_get_scale()
	if OS.has_feature("android"):
		densite = DisplayServer.screen_get_dpi() / DENSITE_ANDROID
	return clampf(_unites_par_pixel() * maxf(1.0, densite), ECHELLE_MIN, ECHELLE_MAX)

## Marges de la zone sûre (encoche, barre de gestes), en unités du viewport. Hors téléphone,
## la « zone sûre » décrit le bureau, pas la fenêtre : aucune marge.
func _marges_sures() -> Dictionary:
	var marges := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
	if not OS.has_feature("mobile"):
		return marges
	var sure := DisplayServer.get_display_safe_area()
	var fenetre := get_window().size
	var k := _unites_par_pixel()
	marges.left = maxf(0.0, sure.position.x) * k
	marges.top = maxf(0.0, sure.position.y) * k
	marges.right = maxf(0.0, fenetre.x - sure.end.x) * k
	marges.bottom = maxf(0.0, fenetre.y - sure.end.y) * k
	return marges

## Position du héros à l'écran, pour viser à la souris ; le centre de l'écran sans vue Monde.
func _heros_a_l_ecran() -> Vector2:
	var centre := get_viewport_rect().size / 2.0
	if _app == null or _partie == null or _partie.game == null:
		return centre
	var monde: Variant = _app.vues.get("monde")
	if monde == null or not monde.has_method("monde_vers_ecran"):
		return centre
	var heros: Dictionary = _partie.game.player
	return monde.monde_vers_ecran(Vector2(heros.x, heros.y))
