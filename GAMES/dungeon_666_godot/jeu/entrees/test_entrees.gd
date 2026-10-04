extends SceneTree
## Test headless des entrées : de vrais événements poussés dans le viewport (Viewport.push_input :
## `_input`, puis les Control, puis `_unhandled_input`), et l'InputFrame rendu par `lire()`.
## Mêmes règles que l'e2e de la version web (GAMES/dungeon_666/e2e.mjs), sauf la disposition et
## les gestes du combat V3 (design/COMBAT_V3.md, « Affichage — ce qui est FAIT ») : rien ne part à
## l'appui sur l'attaque ; un appui bref = un coup, un glisser-relâcher = un coup visé, un pouce
## maintenu = attaque tenue. Les derniers essais rejouent ces gestes dans la VRAIE simulation.
##   godot --headless --path . --script res://jeu/entrees/test_entrees.gd   → sortie 0 = vert, 1 = rouge

const SCENE := "res://jeu/entrees/entrees.tscn"
const HEROS := Vector2(300.0, 200.0)

class AppFactice extends Node:
	var ecran := "jeu"
	var vues := {}

class PartieFactice extends Node:
	var game: Variant = {"mode": "play", "player": {"x": 300.0, "y": 200.0}}
	var en_pause := false

class MondeFactice extends Node:
	func monde_vers_ecran(p: Vector2) -> Vector2:
		return p

var e: Control
var app: AppFactice
var partie: PartieFactice
var pauses := 0
var _total := 0
var _echecs := 0

func _initialize() -> void:
	_derouler()

func _derouler() -> void:
	app = AppFactice.new()
	partie = PartieFactice.new()
	root.add_child(app)
	root.add_child(partie)
	var monde := MondeFactice.new()
	root.add_child(monde)
	app.vues["monde"] = monde
	e = (load(SCENE) as PackedScene).instantiate()
	root.add_child(e)
	e.brancher(app, partie)
	e.pause_demandee.connect(func() -> void: pauses += 1)
	await process_frame
	root.size = Vector2i(1280, 720) # la fenêtre headless naît en 64 × 64 : on lui donne celle du projet
	await process_frame
	print("viewport %s · fenêtre %s · échelle %s" % [root.get_visible_rect().size, root.size, e._doigts.echelle])
	for essai: Callable in [_forme, _arc, _joystick, _joystick_suiveur, _attaque_et_multi_doigts, _appui_bref, _glisser_relacher,
			_maintien, _attaque_annulee, _trois_doigts, _dash, _competence, _tap_flottant, _tolerance_du_pouce, _control_qui_consomme, _clavier, _souris, _souris_inactive,
			_manette, _manette_visee, _retours_du_bureau, _vider_et_pause, _perte_du_focus, _zone_sure]:
		_a_zero()
		essai.call()
	_a_zero()
	await _front_garde_une_image()
	_a_zero()
	await _hors_jeu()
	_a_zero()
	await _portrait()
	_a_zero()
	_gestes_dans_la_simulation()
	print("%d vérifications, %d échec(s) — %s" % [_total, _echecs, "ROUGE" if _echecs > 0 else "VERT"])
	quit(1 if _echecs > 0 else 0)

# ---------------------------------------------------------------- outils

func verifier(nom: String, ok: bool, detail: Variant = "") -> void:
	_total += 1
	if not ok:
		_echecs += 1
	print("%s  %s%s" % ["ok   " if ok else "ÉCHEC", nom, "" if ok and str(detail) == "" else "  [%s]" % str(detail)])

func _a_zero() -> void:
	e._tout_relacher()
	e._manette.appareil = -1
	e._clavier.dedans = false
	e._tactile_actif = false
	e.vider()
	pauses = 0

func doigt(index: int, p: Vector2, pose: bool, annule: bool = false) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = p
	ev.pressed = pose
	ev.canceled = annule
	root.push_input(ev, true)

func glisse(index: int, p: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = p
	root.push_input(ev, true)

func tap(index: int, p: Vector2) -> void:
	doigt(index, p, true)
	doigt(index, p, false)

func touche(code: Key, enfoncee: bool, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = enfoncee
	ev.echo = echo
	root.push_input(ev, true)

func clic(bouton: MouseButton, enfonce: bool, p: Vector2, masque: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = bouton
	ev.pressed = enfonce
	ev.position = p
	ev.global_position = p
	ev.button_mask = masque
	root.push_input(ev, true)

func souris(p: Vector2, masque: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = masque
	root.push_input(ev, true)

func pad_bouton(bouton: JoyButton, enfonce: bool, appareil: int = 0) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = appareil
	ev.button_index = bouton
	ev.pressed = enfonce
	root.push_input(ev, true)

func pad_axe(axe: JoyAxis, valeur: float, appareil: int = 0) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = appareil
	ev.axis = axe
	ev.axis_value = valeur
	root.push_input(ev, true)

func bouton(id: String) -> Dictionary:
	for b: Dictionary in e.interface_tactile().buttons:
		if b.id == id:
			return b
	return {}

func centre(id: String) -> Vector2:
	var b := bouton(id)
	return Vector2(b.x, b.y)

func k() -> float:
	return e._doigts.echelle

## Le pouce posé sur l'attaque y est depuis plus longtemps qu'un appui bref : au prochain pas,
## l'attaque est TENUE (même procédé que `dernier_mouvement_ms` pour la souris).
func vieillir_appui() -> void:
	e._doigts.boutons[0].pose_ms -= e._doigts.APPUI_BREF_MS + 50.0

## `n` pas lus : {coups: fronts d'attaque, tenue: pas où l'attaque est tenue, dernier: le dernier InputFrame}.
func lire_pas(n: int) -> Dictionary:
	var bilan := {"coups": 0, "tenue": 0, "dernier": {}}
	for i in n:
		var f: Dictionary = e.lire()
		bilan.coups += int(f.attackPressed)
		bilan.tenue += int(f.attack)
		bilan.dernier = f
	return bilan

## Un point de la zone du joystick (fractions de la zone et de la hauteur).
func gauche(fx: float, fy: float) -> Vector2:
	return Vector2(e._doigts.zone_x * fx, root.get_visible_rect().size.y * fy)

# ---------------------------------------------------------------- tactile

func _forme() -> void:
	var ui: Dictionary = e.interface_tactile()
	verifier("interface_tactile : clés visible, stick, buttons", ui.has_all(["visible", "stick", "buttons"]))
	verifier("interface_tactile : stick {active, baseX, baseY, knobX, knobY}", ui.stick.has_all(["active", "baseX", "baseY", "knobX", "knobY"]))
	var ids: Array = ui.buttons.map(func(b: Dictionary) -> String: return b.id)
	verifier("interface_tactile : 5 boutons attack, dash, skill1, skill2, skill3 (les trois emplacements)", ids == ["attack", "dash", "skill1", "skill2", "skill3"], ids)
	verifier("interface_tactile : bouton {id, x, y, r, pressed, dragging, dx, dy, held}", ui.buttons[0].has_all(["id", "x", "y", "r", "pressed", "dragging", "dx", "dy", "held"]))
	var taille := root.get_visible_rect().size
	var a := bouton("attack")
	verifier("disposition : attaque à 168 × 100 px CSS du coin bas-droit", is_equal_approx(a.x, taille.x - 168.0 * k()) and is_equal_approx(a.y, taille.y - 100.0 * k()), [a.x, a.y])
	verifier("disposition : rayon de l'attaque 52, du dash 38 (px CSS)", is_equal_approx(a.r, 52.0 * k()) and is_equal_approx(bouton("dash").r, 38.0 * k()))
	verifier("disposition : la zone joystick s'arrête à 48 % de la largeur au plus, avant la zone de toucher de chaque bouton", e._doigts.zone_x <= taille.x * 0.48 + 0.001 and ui.buttons.all(func(b: Dictionary) -> bool: return e._doigts.zone_x < b.x - b.r * 1.35))
	var f: Dictionary = e.lire()
	verifier("InputFrame : mêmes clés que D6Game.empty_input()", f.keys() == D6Game.empty_input().keys(), f.keys())
	verifier("InputFrame au repos : rien", f == D6Game.empty_input(), f)

## Combat V3 : gros bouton d'attaque, les trois emplacements en arc autour, le dash à part.
func _arc(taille: Vector2 = root.get_visible_rect().size) -> void:
	var a := bouton("attack")
	var dash := bouton("dash")
	var boutons: Array = e.interface_tactile().buttons
	var arc: Array = ["skill1", "skill2", "skill3"].map(func(id: String) -> Dictionary: return bouton(id))
	verifier("arc : l'attaque est le plus gros bouton", boutons.all(func(b: Dictionary) -> bool: return b.id == "attack" or b.r < a.r))
	verifier("arc : chaque emplacement est une cible d'au moins 56 px (diamètre, px CSS)", arc.all(func(b: Dictionary) -> bool: return 2.0 * b.r >= 56.0 * k() - 0.001), arc.map(func(b: Dictionary) -> float: return 2.0 * b.r / k()))
	var rayons: Array = arc.map(func(b: Dictionary) -> float: return Vector2(b.x - a.x, b.y - a.y).length())
	verifier("arc : les trois emplacements sont à la même distance de l'attaque", is_equal_approx(rayons[0], rayons[1]) and is_equal_approx(rayons[1], rayons[2]), rayons)
	verifier("arc : à gauche et au-dessus de l'attaque, dans l'ordre 1, 2, 3", arc.all(func(b: Dictionary) -> bool: return b.y < a.y) and arc[0].x < arc[1].x and arc[1].x < arc[2].x and arc[0].y > arc[1].y and arc[1].y > arc[2].y and arc[0].x < a.x - a.r)
	verifier("dash à part : de l'autre côté de l'attaque (à droite), hors de l'arc", dash.x > a.x + a.r and arc.all(func(b: Dictionary) -> bool: return b.x + b.r < dash.x - dash.r))
	var vide_mini := INF
	for i in boutons.size():
		for j in range(i + 1, boutons.size()):
			vide_mini = minf(vide_mini, Vector2(boutons[i].x - boutons[j].x, boutons[i].y - boutons[j].y).length() - boutons[i].r - boutons[j].r)
	verifier("aucun bouton n'en touche un autre : au moins 12 px CSS de vide entre deux", vide_mini >= 12.0 * k(), vide_mini / k())
	verifier("tous les boutons tiennent dans l'écran, anneau compris (9 px), à 8 px CSS du bord au moins", boutons.all(func(b: Dictionary) -> bool: return b.x - b.r - 9.0 > 0.0 and b.x + b.r + 9.0 <= taille.x - 8.0 * k() and b.y - b.r - 9.0 > 0.0 and b.y + b.r + 9.0 <= taille.y - 8.0 * k()))
	# Chaque centre de bouton rend ce bouton-là (les zones de toucher se recouvrent : le plus proche gagne).
	verifier("toucher le centre d'un bouton prend ce bouton", boutons.all(func(b: Dictionary) -> bool: return e._doigts.bouton_a(b.x, b.y).id == b.id))

func _joystick() -> void:
	# Pouce posé IMMOBILE au bord bas-gauche (là où il repose) : le héros ne doit pas bouger.
	var bord := Vector2(4.0, root.get_visible_rect().size.y - 4.0)
	doigt(11, bord, true)
	var f: Dictionary = e.lire()
	verifier("pouce immobile au bord : aucun déplacement fantôme", f.moveX == 0.0 and f.moveY == 0.0, [f.moveX, f.moveY])
	verifier("pouce au bord : le joystick est actif et son DESSIN est recalé loin du bord", e.interface_tactile().stick.active and e.interface_tactile().stick.baseX >= 58.0 * k())
	glisse(11, bord + Vector2(58.0 * 0.10 * k(), 0.0))
	f = e.lire()
	verifier("zone morte : 10 % de la course ne déplace pas", f.moveX == 0.0 and f.moveY == 0.0, f.moveX)
	doigt(11, bord, false)
	verifier("pouce levé : joystick inactif, tactile() vrai", not e.interface_tactile().stick.active and e.tactile())
	# Joystick flottant : pouce gauche, glissé vers la droite.
	var p := gauche(0.4, 0.6)
	doigt(1, p, true)
	glisse(1, p + Vector2(58.0 * 0.41 * k(), 0.0))
	f = e.lire()
	verifier("joystick à mi-course : déplacement analogique (0 < moveX < 1)", f.moveX > 0.3 and f.moveX < 0.7 and f.moveY == 0.0, f.moveX)
	glisse(1, p + Vector2(58.0 * 0.75 * k(), 0.0))
	f = e.lire()
	verifier("joystick à droite : moveX > 0, pleine vitesse dès 70 % de la course", f.moveX == 1.0 and f.moveY == 0.0, f.moveX)
	glisse(1, p + Vector2(0.0, -58.0 * k()))
	f = e.lire()
	verifier("joystick vers le haut : moveY = -1", f.moveY == -1.0 and absf(f.moveX) < 0.001, [f.moveX, f.moveY])
	doigt(1, p, false)
	f = e.lire()
	verifier("joystick relâché : plus de déplacement", f.moveX == 0.0 and f.moveY == 0.0)

func _joystick_suiveur() -> void:
	var p := gauche(0.3, 0.5)
	doigt(1, p, true)
	glisse(1, p + Vector2(58.0 * 3.0 * k(), 0.0))
	verifier("joystick suiveur : la base glisse derrière le pouce", is_equal_approx(e._doigts.manche.baseX, p.x + 58.0 * 2.0 * k()), e._doigts.manche.baseX)
	glisse(1, p + Vector2(58.0 * 1.0 * k(), 0.0))
	var f: Dictionary = e.lire()
	verifier("joystick suiveur : revenir en arrière inverse aussitôt la direction", f.moveX == -1.0, f.moveX)
	# Un second doigt dans la zone gauche ne vole pas le joystick.
	doigt(2, gauche(0.6, 0.2), true)
	verifier("joystick : un second doigt à gauche ne le vole pas", e._doigts.manche.doigt == 1)
	doigt(2, gauche(0.6, 0.2), false)
	verifier("joystick : lever l'autre doigt ne le lâche pas", e.interface_tactile().stick.active)

func _attaque_et_multi_doigts() -> void:
	# Multi-touch : on garde le déplacement ET on maintient l'attaque.
	var p := gauche(0.4, 0.6)
	doigt(1, p, true)
	glisse(1, p + Vector2(58.0 * k(), 0.0))
	doigt(2, centre("attack"), true)
	var f: Dictionary = e.lire()
	# Combat V3 : rien ne part à l'appui (le pouce peut encore glisser) ; le coup part quand on
	# sait que le pouce tape (relâcher) ou tient (appui bref dépassé).
	verifier("pouce posé sur l'attaque : rien ne part à l'appui, le joystick continue", f.moveX == 1.0 and not f.attack and not f.attackPressed and bouton("attack").pressed, f)
	vieillir_appui()
	f = e.lire()
	verifier("deux doigts : joystick + attaque tenue dans le même pas", f.moveX == 1.0 and f.attack and f.attackPressed and bouton("attack").held, f)
	verifier("attaque posée sans glisser : visée assistée (aim nul)", f.aimX == 0.0 and f.aimY == 0.0)
	var maintenue := true
	var fronts := 0
	for i in 5:
		f = e.lire()
		maintenue = maintenue and f.attack and f.moveX == 1.0
		fronts += int(f.attackPressed)
	verifier("attaque maintenue : attack vrai à chaque pas, attackPressed une seule fois", maintenue and fronts == 0, fronts)
	# Un troisième doigt tape le dash pendant que les deux autres tiennent.
	tap(3, centre("dash"))
	f = e.lire()
	verifier("trois doigts : joystick + attaque tenue + tap sur le dash", f.moveX == 1.0 and f.attack and f.dashPressed and not f.attackPressed, f)
	# Glisser le doigt de l'attaque : visée manuelle.
	glisse(2, centre("attack") + Vector2(0.0, -40.0 * k()))
	f = e.lire()
	# Combat V3 : glisser VISE sans tenir l'attaque (tenir l'attaque, jauge pleine, lance l'ultime).
	verifier("attaque glissée : visée manuelle vers le haut, l'attaque n'est plus tenue", not f.attack and not f.attackPressed and absf(f.aimX) < 0.001 and is_equal_approx(f.aimY, -1.0) and bouton("attack").dragging, [f.aimX, f.aimY])
	var tenue := false
	for i in 40: # bien plus long que le maintien de l'ultime (0,4 s = 24 pas)
		tenue = tenue or e.lire().attack
	verifier("attaque glissée longtemps : jamais d'attaque tenue (un glisser n'arme pas l'ultime)", not tenue)
	doigt(2, centre("attack"), false)
	f = e.lire()
	verifier("attaque tenue, puis glissée, puis relâchée : le coup visé part au relâcher, dans la direction visée", f.attackPressed and not f.attack and absf(f.aimX) < 0.001 and is_equal_approx(f.aimY, -1.0), [f.attackPressed, f.aimX, f.aimY])
	f = e.lire()
	verifier("attaque relâchée : attack faux, le joystick continue", not f.attack and not f.attackPressed and f.aimY == 0.0 and f.moveX == 1.0)
	doigt(1, p, false)

## Appui bref = exactement UN coup, visée assistée, jamais d'attaque tenue.
func _appui_bref() -> void:
	doigt(2, centre("attack"), true)
	var avant := lire_pas(3) # trois pas passent, le pouce est encore posé (appui bref : moins de 150 ms)
	doigt(2, centre("attack"), false)
	var apres := lire_pas(40)
	verifier("appui bref : rien avant le relâcher", avant.coups == 0 and avant.tenue == 0, avant)
	verifier("appui bref : exactement un coup, au relâcher", apres.coups == 1, apres.coups)
	verifier("appui bref : l'attaque n'est jamais tenue (il n'arme pas l'ultime)", apres.tenue == 0, apres.tenue)
	var f: Dictionary
	tap(2, centre("attack"))
	f = e.lire()
	verifier("appui bref : visée assistée (aim nul)", f.attackPressed and f.aimX == 0.0 and f.aimY == 0.0, [f.aimX, f.aimY])
	tap(2, centre("attack"))
	tap(2, centre("attack"))
	verifier("deux appuis brefs entre deux pas : un front (les fronts ne se comptent pas)", lire_pas(5).coups == 1)

## Glisser-relâcher = exactement UN coup, au relâcher, dans la direction visée ; l'attaque n'est
## jamais tenue, aussi long que soit le glisser : il ne peut pas lancer l'ultime.
func _glisser_relacher() -> void:
	var c := centre("attack")
	doigt(2, c, true)
	glisse(2, c + Vector2(-50.0 * k(), 0.0))
	vieillir_appui() # le pouce reste bien plus longtemps qu'un appui bref : il vise, il ne tient pas
	var pendant := lire_pas(60) # 1 s : plus de deux fois le maintien de l'ultime (0,4 s)
	verifier("glisser : aucun coup tant que le pouce vise", pendant.coups == 0, pendant.coups)
	verifier("glisser : l'attaque n'est jamais tenue (jamais d'ultime)", pendant.tenue == 0, pendant.tenue)
	verifier("glisser : la visée suit le pouce (à gauche)", is_equal_approx(pendant.dernier.aimX, -1.0) and absf(pendant.dernier.aimY) < 0.001 and bouton("attack").dragging, [pendant.dernier.aimX, pendant.dernier.aimY])
	glisse(2, c + Vector2(0.0, 50.0 * k()))
	doigt(2, c + Vector2(0.0, 50.0 * k()), false)
	var f: Dictionary = e.lire()
	verifier("glisser-relâcher : le coup part au relâcher, dans la DERNIÈRE direction visée (en bas)", f.attackPressed and not f.attack and absf(f.aimX) < 0.001 and is_equal_approx(f.aimY, 1.0), [f.attackPressed, f.aimX, f.aimY])
	var apres := lire_pas(40)
	verifier("glisser-relâcher : exactement un coup (aucun autre ensuite), attaque jamais tenue", apres.coups == 0 and apres.tenue == 0 and apres.dernier.aimX == 0.0 and apres.dernier.aimY == 0.0, apres)

## Pouce maintenu sans glisser = attaque tenue SANS INTERRUPTION (c'est ce qui arme l'ultime).
func _maintien() -> void:
	doigt(2, centre("attack"), true)
	vieillir_appui()
	var bilan := lire_pas(60)
	verifier("maintien : l'attaque est tenue à chaque pas, sans interruption", bilan.tenue == 60, bilan.tenue)
	verifier("maintien : un seul front (le premier coup), la suite est l'enchaînement de l'attaque tenue", bilan.coups == 1, bilan.coups)
	glisse(2, centre("attack") + Vector2(6.0 * k(), -4.0 * k())) # le pouce tremble : sous le seuil de visée (18 px)
	bilan = lire_pas(30)
	verifier("maintien : un pouce qui tremble (moins de 18 px) tient toujours l'attaque", bilan.tenue == 30 and bilan.coups == 0, bilan)
	doigt(2, centre("attack"), false)
	bilan = lire_pas(10)
	verifier("maintien relâché : plus d'attaque tenue, et pas de coup de plus", bilan.tenue == 0 and bilan.coups == 0, bilan)

## Comme pour un emplacement : viser puis revenir au centre du bouton ANNULE le coup.
func _attaque_annulee() -> void:
	var c := centre("attack")
	doigt(2, c, true)
	glisse(2, c + Vector2(60.0 * k(), 0.0))
	glisse(2, c + Vector2(5.0 * k(), 0.0))
	vieillir_appui()
	var pendant := lire_pas(30)
	verifier("attaque visée puis ramenée au centre : ni visée, ni attaque tenue", pendant.tenue == 0 and pendant.coups == 0 and pendant.dernier.aimX == 0.0 and not bouton("attack").dragging, pendant)
	doigt(2, c + Vector2(5.0 * k(), 0.0), false)
	verifier("attaque visée puis ramenée au centre : relâcher ne lance aucun coup", lire_pas(10).coups == 0)
	doigt(2, c, true)
	glisse(2, c + Vector2(60.0 * k(), 0.0))
	doigt(2, c, false, true)
	verifier("attaque visée, toucher annulé par le système : aucun coup", lire_pas(10).coups == 0)

## Trois doigts à la fois : le joystick, l'attaque tenue, et un emplacement visé puis lancé.
func _trois_doigts() -> void:
	var p := gauche(0.4, 0.6)
	doigt(1, p, true)
	glisse(1, p + Vector2(0.0, 58.0 * k()))
	doigt(2, centre("attack"), true)
	vieillir_appui()
	e.lire()
	var c := centre("skill2")
	doigt(3, c, true)
	glisse(3, c + Vector2(-60.0 * k(), 0.0))
	var f: Dictionary = e.lire()
	verifier("trois doigts : joystick + attaque tenue + emplacement 2 qui vise, rien n'est lâché", f.moveY == 1.0 and f.attack and not f.attackPressed and not f.skill2Pressed and bouton("skill2").dragging and bouton("attack").held and e.interface_tactile().stick.active, f)
	doigt(3, c + Vector2(-60.0 * k(), 0.0), false)
	f = e.lire()
	verifier("trois doigts : l'emplacement 2 part visé, dans le même pas que le déplacement et l'attaque tenue", f.moveY == 1.0 and f.attack and f.skill2Pressed and is_equal_approx(f.skill2AimX, -1.0) and not f.skill1Pressed and not f.skill3Pressed and not f.dashPressed, f)
	f = e.lire()
	verifier("trois doigts : le joystick et l'attaque tiennent toujours après le lancer", f.moveY == 1.0 and f.attack and not f.skill2Pressed and f.aimX == 0.0, f)
	doigt(2, centre("attack"), false)
	doigt(1, p, false)

func _dash() -> void:
	doigt(3, centre("dash"), true)
	verifier("bouton dash enfoncé : pressed dans la disposition", bouton("dash").pressed)
	var f1: Dictionary = e.lire()
	var f2: Dictionary = e.lire()
	doigt(3, centre("dash"), false)
	var f3: Dictionary = e.lire()
	verifier("bouton dash : un seul dashPressed, puis faux", f1.dashPressed and not f2.dashPressed and not f3.dashPressed, [f1.dashPressed, f2.dashPressed, f3.dashPressed])
	verifier("bouton dash : n'attaque pas", not f1.attack and not f1.attackPressed)
	tap(5, centre("skill2"))
	tap(6, centre("skill3"))
	f1 = e.lire()
	verifier("emplacements 2 et 3 : un tap chacun, un front chacun, visée assistée", f1.skill2Pressed and f1.skill3Pressed and not f1.skill1Pressed and not f1.dashPressed and f1.skill2AimX == 0.0 and f1.skill3AimY == 0.0)
	var c3 := centre("skill3")
	doigt(6, c3, true)
	glisse(6, c3 + Vector2(-60.0 * k(), 0.0))
	verifier("emplacement 3 glissé, pas encore relâché : rien ne part", not e.lire().skill3Pressed)
	doigt(6, c3, false)
	f1 = e.lire()
	verifier("emplacement 3 glissé puis relâché : skill3Pressed, visé à gauche, sans toucher aux autres", f1.skill3Pressed and is_equal_approx(f1.skill3AimX, -1.0) and not f1.skill1Pressed and f1.skill1AimX == 0.0, [f1.skill3AimX, f1.skill3AimY])
	doigt(3, centre("dash"), true)
	doigt(4, centre("dash"), true) # bouton déjà tenu : ce doigt ne redéclenche rien
	e.lire()
	doigt(3, centre("dash"), false)
	doigt(4, centre("dash"), false)
	verifier("dash tenu : un second doigt dessus ne redashe pas", not e.lire().dashPressed)

func _competence() -> void:
	var c := centre("skill1")
	doigt(4, c, true)
	glisse(4, c + Vector2(0.0, -60.0 * k()))
	var f: Dictionary = e.lire()
	verifier("compétence glissée, pas encore relâchée : rien ne part", not f.skill1Pressed and bouton("skill1").dragging)
	doigt(4, c + Vector2(0.0, -60.0 * k()), false)
	f = e.lire()
	verifier("compétence glissée puis relâchée : skillPressed, visée vers le haut", f.skill1Pressed and absf(f.skill1AimX) < 0.001 and is_equal_approx(f.skill1AimY, -1.0), [f.skill1AimX, f.skill1AimY])
	f = e.lire()
	verifier("compétence : le front et sa visée ne sont rendus qu'une fois", not f.skill1Pressed and f.skill1AimX == 0.0 and f.skill1AimY == 0.0)
	doigt(4, c, true)
	glisse(4, c + Vector2(60.0 * k(), 0.0))
	glisse(4, c + Vector2(5.0 * k(), 0.0))
	doigt(4, c + Vector2(5.0 * k(), 0.0), false)
	verifier("compétence glissée puis ramenée au centre : annulée", not e.lire().skill1Pressed)
	doigt(4, c, true)
	glisse(4, c + Vector2(60.0 * k(), 0.0))
	glisse(4, c + Vector2(15.0 * k(), 0.0)) # entre 12 et 18 px : la visée manuelle tient encore
	doigt(4, c, false)
	f = e.lire()
	verifier("compétence ramenée à 15 px (seuil d'annulation 12) : elle part encore", f.skill1Pressed and is_equal_approx(f.skill1AimX, 1.0), f.skill1AimX)
	tap(4, c)
	f = e.lire()
	verifier("compétence tapée : skillPressed en visée assistée (0, 0)", f.skill1Pressed and f.skill1AimX == 0.0 and f.skill1AimY == 0.0)
	doigt(4, c, true)
	glisse(4, c + Vector2(0.0, -60.0 * k()))
	doigt(4, c, false, true)
	verifier("compétence : toucher annulé par le système = rien ne part", not e.lire().skill1Pressed)

func _tap_flottant() -> void:
	# Zone d'attaque flottante : un tap dans la moitié droite, hors des boutons, attaque.
	var taille := root.get_visible_rect().size
	var p := Vector2(taille.x * 0.6, taille.y * 0.3)
	tap(8, p)
	var f: Dictionary = e.lire()
	# Combat V3 : comme sur le bouton, le coup d'un appui bref part au relâcher.
	verifier("tap hors bouton dans la moitié droite : attaque (un coup, au relâcher)", f.attackPressed and not f.attack and f.moveX == 0.0 and not e.lire().attackPressed, f)
	doigt(8, p, true)
	vieillir_appui()
	f = e.lire()
	verifier("pouce maintenu hors bouton dans la moitié droite : attaque tenue", f.attack and f.attackPressed and f.moveX == 0.0, f)
	glisse(8, p + Vector2(30.0 * k(), 0.0))
	f = e.lire()
	verifier("attaque flottante glissée : visée depuis le point de contact", is_equal_approx(f.aimX, 1.0) and absf(f.aimY) < 0.001, [f.aimX, f.aimY])
	doigt(9, Vector2(taille.x * 0.7, taille.y * 0.2), true)
	f = e.lire()
	verifier("attaque déjà prise par un doigt (qui vise) : un autre doigt à droite ne la redéclenche pas", bouton("attack").pressed and not f.attackPressed and is_equal_approx(f.aimX, 1.0))
	doigt(9, Vector2(taille.x * 0.7, taille.y * 0.2), false)
	doigt(8, p, false)
	verifier("tap flottant relâché : plus d'attaque", not e.lire().attack)

func _tolerance_du_pouce() -> void:
	var d := bouton("dash")
	tap(3, Vector2(d.x - d.r * 1.30, d.y)) # du côté libre : ailleurs, le bouton le plus proche gagne
	var f: Dictionary = e.lire()
	verifier("tolérance du pouce : à 1,30 rayon du centre, c'est encore le dash", f.dashPressed and not f.attackPressed, f)
	tap(3, Vector2(d.x - d.r * 1.45, d.y))
	f = e.lire()
	verifier("au-delà de 1,35 rayon : ce n'est plus le dash", not f.dashPressed, f)

func _control_qui_consomme() -> void:
	# Un bouton d'interface (pause du HUD, menu) posé sur la zone de droite : y toucher n'attaque pas.
	var taille := root.get_visible_rect().size
	var obstacle := Button.new()
	obstacle.position = Vector2(taille.x * 0.55, taille.y * 0.1)
	obstacle.size = Vector2(120.0, 80.0)
	root.add_child(obstacle)
	var p := obstacle.position + obstacle.size / 2.0
	tap(8, p)
	var f: Dictionary = e.lire()
	verifier("toucher un bouton d'interface : pas d'attaque", not f.attack and not f.attackPressed, f)
	clic(MOUSE_BUTTON_LEFT, true, p, MOUSE_BUTTON_MASK_LEFT)
	f = e.lire()
	clic(MOUSE_BUTTON_LEFT, false, p, 0)
	verifier("cliquer un bouton d'interface : pas d'attaque", not f.attack and not f.attackPressed, f)
	tap(8, p + Vector2(0.0, obstacle.size.y))
	verifier("juste à côté du bouton d'interface : attaque", e.lire().attackPressed)
	root.remove_child(obstacle)
	obstacle.free()

# ---------------------------------------------------------------- clavier, souris, manette

func _clavier() -> void:
	e._tactile_actif = true
	touche(KEY_D, true)
	var f: Dictionary = e.lire()
	verifier("clavier : D déplace vers la droite ; tactile() devient faux", f.moveX == 1.0 and f.moveY == 0.0 and not e.tactile(), f.moveX)
	touche(KEY_SPACE, true)
	touche(KEY_SPACE, true, true) # répétition automatique : ignorée
	f = e.lire()
	var f2: Dictionary = e.lire()
	verifier("clavier : Espace dashe une fois (la répétition de touche ne redashe pas)", f.dashPressed and not f2.dashPressed and f2.moveX == 1.0)
	touche(KEY_SPACE, false)
	touche(KEY_S, true)
	f = e.lire()
	verifier("clavier : D + S = diagonale de norme 1", is_equal_approx(f.moveX, sqrt(0.5)) and is_equal_approx(f.moveY, sqrt(0.5)), [f.moveX, f.moveY])
	touche(KEY_D, false)
	touche(KEY_S, false)
	f = e.lire()
	verifier("clavier : touches relâchées = arrêt", f.moveX == 0.0 and f.moveY == 0.0)
	touche(KEY_J, true)
	f = e.lire()
	f2 = e.lire()
	touche(KEY_J, false)
	verifier("clavier : J maintenu = attack à chaque pas, attackPressed une fois", f.attack and f.attackPressed and f2.attack and not f2.attackPressed and not e.lire().attack)
	for paire: Array in [[KEY_L, "skill1Pressed"], [KEY_E, "skill2Pressed"], [KEY_F, "skill3Pressed"], [KEY_SHIFT, "dashPressed"], [KEY_K, "dashPressed"]]:
		touche(paire[0], true)
		touche(paire[0], false)
		verifier("clavier : %s → %s" % [OS.get_keycode_string(paire[0]), paire[1]], e.lire()[paire[1]])

func _souris() -> void:
	e._tactile_actif = true
	var cible := HEROS + Vector2(200.0, 0.0)
	souris(cible)
	clic(MOUSE_BUTTON_LEFT, true, cible, MOUSE_BUTTON_MASK_LEFT)
	var f: Dictionary = e.lire()
	verifier("souris : clic gauche = attaque visée vers la souris ; tactile() devient faux", f.attack and f.attackPressed and is_equal_approx(f.aimX, 1.0) and absf(f.aimY) < 0.001 and not e.tactile(), [f.aimX, f.aimY])
	souris(HEROS + Vector2(0.0, 150.0), MOUSE_BUTTON_MASK_LEFT)
	f = e.lire()
	verifier("souris : clic gauche maintenu = attack à chaque pas, un seul front, la visée suit le curseur", f.attack and not f.attackPressed and is_equal_approx(f.aimY, 1.0), [f.aimX, f.aimY])
	# Clic droit PENDANT le clic gauche maintenu : la compétence part vers la souris.
	clic(MOUSE_BUTTON_RIGHT, true, HEROS + Vector2(0.0, 150.0), MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)
	f = e.lire()
	verifier("souris : clic droit = compétence visée vers la souris", f.skill1Pressed and is_equal_approx(f.skill1AimY, 1.0) and absf(f.skill1AimX) < 0.001 and f.attack, [f.skill1AimX, f.skill1AimY])
	# E et F (emplacements 2 et 3) visent aussi où pointe la souris.
	touche(KEY_E, true)
	touche(KEY_F, true)
	f = e.lire()
	touche(KEY_E, false)
	touche(KEY_F, false)
	verifier("clavier + souris : E et F = emplacements 2 et 3, visés vers la souris", f.skill2Pressed and f.skill3Pressed and is_equal_approx(f.skill2AimY, 1.0) and is_equal_approx(f.skill3AimY, 1.0) and not f.skill1Pressed, [f.skill2AimY, f.skill3AimY])
	clic(MOUSE_BUTTON_LEFT, false, cible, MOUSE_BUTTON_MASK_RIGHT)
	clic(MOUSE_BUTTON_RIGHT, false, cible, 0)
	f = e.lire()
	verifier("souris : boutons relâchés = plus d'attaque, rien ne reste collé", not f.attack and not f.skill1Pressed and not e._clavier.gauche and not e._clavier.droite)
	clic(MOUSE_BUTTON_LEFT, true, cible, MOUSE_BUTTON_MASK_LEFT)
	souris(cible + Vector2(5.0, 0.0), 0) # le relâcher a eu lieu hors de la fenêtre : le masque le dit
	e.lire()
	verifier("souris : un relâcher manqué est rattrapé au mouvement suivant", not e.lire().attack)
	_souris_fabriquee(cible)
	app.vues.erase("monde")
	var milieu := root.get_visible_rect().size / 2.0
	souris(milieu + Vector2(-100.0, 0.0))
	f = e.lire()
	app.vues["monde"] = root.get_child(2)
	verifier("souris sans vue Monde : la visée part du centre de l'écran", is_equal_approx(f.aimX, -1.0), f.aimX)

## Une souris fabriquée à partir d'un doigt n'est pas une souris.
func _souris_fabriquee(p: Vector2) -> void:
	e._tactile_actif = true
	var ev := InputEventMouseButton.new()
	ev.device = InputEvent.DEVICE_ID_EMULATION
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	root.push_input(ev, true)
	var f: Dictionary = e.lire()
	verifier("souris émulée depuis un doigt : ignorée (pas d'attaque, tactile() reste vrai)", not f.attack and not f.attackPressed and e.tactile(), f)
	e._tactile_actif = false

func _souris_inactive() -> void:
	souris(HEROS + Vector2(200.0, 0.0))
	var f: Dictionary = e.lire()
	verifier("souris qui vient de bouger : visée manuelle sans cliquer", is_equal_approx(f.aimX, 1.0) and not f.attack)
	e._clavier.dernier_mouvement_ms -= 2600.0
	f = e.lire()
	verifier("souris immobile depuis 2,5 s : retour à la visée assistée", f.aimX == 0.0 and f.aimY == 0.0, [f.aimX, f.aimY])
	clic(MOUSE_BUTTON_LEFT, true, HEROS + Vector2(0.0, -200.0), MOUSE_BUTTON_MASK_LEFT)
	e._clavier.dernier_mouvement_ms -= 2600.0
	f = e.lire()
	clic(MOUSE_BUTTON_LEFT, false, HEROS + Vector2(0.0, -200.0), 0)
	verifier("souris immobile mais clic gauche tenu : l'attaque reste visée vers le curseur", f.attack and is_equal_approx(f.aimY, -1.0), [f.aimX, f.aimY])
	souris(HEROS + Vector2(200.0, 0.0))
	doigt(1, gauche(0.5, 0.5), true)
	f = e.lire()
	doigt(1, gauche(0.5, 0.5), false)
	verifier("doigt posé après la souris : la souris ne vise plus", f.aimX == 0.0 and e.tactile())

func _manette() -> void:
	pad_axe(JOY_AXIS_LEFT_X, 0.8)
	pad_axe(JOY_AXIS_LEFT_Y, 0.1)
	var f: Dictionary = e.lire()
	verifier("manette : stick gauche = déplacement, zone morte 0,22 par axe", is_equal_approx(f.moveX, 0.8) and f.moveY == 0.0, [f.moveX, f.moveY])
	pad_axe(JOY_AXIS_LEFT_X, 0.0)
	pad_axe(JOY_AXIS_RIGHT_Y, -0.3)
	f = e.lire()
	verifier("manette : stick droit sous 0,35 = visée assistée", f.aimX == 0.0 and f.aimY == 0.0 and f.moveX == 0.0)
	pad_axe(JOY_AXIS_RIGHT_Y, -0.9)
	f = e.lire()
	verifier("manette : stick droit = visée", is_equal_approx(f.aimY, -0.9), f.aimY)
	pad_axe(JOY_AXIS_RIGHT_Y, 0.0)
	pad_bouton(JOY_BUTTON_A, true)
	pad_bouton(JOY_BUTTON_A, false) # appui bref, relâché avant le pas : le front reste
	f = e.lire()
	verifier("manette : A = un dashPressed, même relâché avant le pas, puis faux", f.dashPressed and not e.lire().dashPressed)
	pad_bouton(JOY_BUTTON_X, true)
	f = e.lire()
	var f2: Dictionary = e.lire()
	pad_bouton(JOY_BUTTON_X, false)
	verifier("manette : X maintenu = attack à chaque pas, attackPressed une fois", f.attack and f.attackPressed and f2.attack and not f2.attackPressed and not e.lire().attack)
	pad_axe(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	f = e.lire()
	pad_axe(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	verifier("manette : gâchette droite = attaque", f.attack and f.attackPressed and not e.lire().attack)
	for paire: Array in [[JOY_BUTTON_B, "skill1Pressed"], [JOY_BUTTON_Y, "skill2Pressed"], [JOY_BUTTON_RIGHT_SHOULDER, "skill3Pressed"], [JOY_BUTTON_LEFT_SHOULDER, "dashPressed"]]:
		pad_bouton(paire[0], true)
		pad_bouton(paire[0], false)
		verifier("manette : bouton %d → %s" % [paire[0], paire[1]], e.lire()[paire[1]])
	pad_bouton(JOY_BUTTON_START, true)
	pad_bouton(JOY_BUTTON_START, false)
	verifier("manette : Start émet pause_demandee", pauses == 1, pauses)
	pad_axe(JOY_AXIS_LEFT_X, 0.1, 1)
	pad_axe(JOY_AXIS_LEFT_X, 0.9)
	verifier("manette : le frémissement d'une autre manette ne prend pas la main", is_equal_approx(e.lire().moveX, 0.9))
	pad_axe(JOY_AXIS_LEFT_X, 0.0)

## Combat V3 : à la manette, un emplacement se vise au stick droit, comme l'attaque.
func _manette_visee() -> void:
	pad_axe(JOY_AXIS_RIGHT_X, -0.9)
	pad_bouton(JOY_BUTTON_B, true)
	pad_bouton(JOY_BUTTON_RIGHT_SHOULDER, true)
	var f: Dictionary = e.lire()
	pad_bouton(JOY_BUTTON_B, false)
	pad_bouton(JOY_BUTTON_RIGHT_SHOULDER, false)
	verifier("manette : un emplacement lancé vise où pointe le stick droit", f.skill1Pressed and f.skill3Pressed and is_equal_approx(f.skill1AimX, -0.9) and is_equal_approx(f.skill3AimX, -0.9) and f.skill2AimX == 0.0 and is_equal_approx(f.aimX, -0.9), [f.skill1AimX, f.skill3AimX])
	pad_axe(JOY_AXIS_RIGHT_X, 0.0)
	pad_bouton(JOY_BUTTON_Y, true)
	f = e.lire()
	pad_bouton(JOY_BUTTON_Y, false)
	verifier("manette : stick droit au repos, l'emplacement part en visée assistée", f.skill2Pressed and f.skill2AimX == 0.0 and f.skill2AimY == 0.0)

## Finitions V3 : pour l'AFFICHAGE, la vue dit quelle commande vient d'être enfoncée (signal),
## lesquelles sont tenues, et où vise le bureau (souris, stick droit). Rien de cela ne change `lire()`.
func _retours_du_bureau() -> void:
	var vus: Array = []
	var noter := func(id: String) -> void: vus.append(id)
	e.commande_enfoncee.connect(noter)
	touche(KEY_SPACE, true)
	verifier("retour : Espace enfoncé → commande_enfoncee(« dash »), et dash tenu", vus == ["dash"] and e.tenues() == {"dash": true}, [vus, e.tenues()])
	touche(KEY_SPACE, true, true)
	touche(KEY_SPACE, false)
	verifier("retour : la répétition de touche ne ré-enfonce pas ; relâchée, plus rien n'est tenu", vus == ["dash"] and e.tenues().is_empty(), [vus, e.tenues()])
	verifier("retour : souris inutilisée, la visée du bureau est assistée (ZERO)", e.visee_bureau() == Vector2.ZERO, e.visee_bureau())
	var bas := HEROS + Vector2(0.0, 150.0)
	clic(MOUSE_BUTTON_RIGHT, true, bas, MOUSE_BUTTON_MASK_RIGHT)
	verifier("retour : clic droit → skill1 enfoncé, tenu, visé vers la souris", vus == ["dash", "skill1"] and e.tenues() == {"skill1": true} and e.visee_bureau().is_equal_approx(Vector2.DOWN), [vus, e.tenues(), e.visee_bureau()])
	clic(MOUSE_BUTTON_RIGHT, false, bas, 0)
	pad_axe(JOY_AXIS_RIGHT_X, -0.9)
	pad_bouton(JOY_BUTTON_Y, true)
	verifier("retour : manette, Y → skill2 enfoncé, tenu ; le stick droit donne la visée", vus == ["dash", "skill1", "skill2"] and e.tenues() == {"skill2": true} and e.visee_bureau().is_equal_approx(Vector2.LEFT), [vus, e.tenues(), e.visee_bureau()])
	pad_axe(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	verifier("retour : gâchette droite tenue = attaque tenue", e.tenues() == {"skill2": true, "attack": true}, e.tenues())
	pad_axe(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	pad_bouton(JOY_BUTTON_Y, false)
	pad_axe(JOY_AXIS_RIGHT_X, 0.0)
	touche(KEY_E, true)
	doigt(1, gauche(0.5, 0.5), true)
	verifier("retour : au doigt, aucune commande « tenue » du bureau", e.tenues().is_empty(), e.tenues())
	doigt(1, gauche(0.5, 0.5), false)
	touche(KEY_E, false)
	e.commande_enfoncee.disconnect(noter)
	var f: Dictionary = e.lire()
	verifier("retour : les lectures d'affichage n'ont consommé aucun front", f.dashPressed and f.skill1Pressed and f.skill2Pressed, f)

# ---------------------------------------------------------------- fronts, pause, disposition

func _vider_et_pause() -> void:
	# Combat V3 : le pouce TIENT l'attaque (passé l'appui bref) avant que les fronts s'accumulent.
	doigt(2, centre("attack"), true)
	vieillir_appui()
	e.lire()
	tap(3, centre("dash"))
	touche(KEY_L, true)
	pad_bouton(JOY_BUTTON_Y, true)
	tap(6, centre("skill3"))
	tap(8, Vector2(root.get_visible_rect().size.x * 0.6, 40.0)) # second doigt à droite : l'attaque est déjà prise
	e.vider()
	var f: Dictionary = e.lire()
	verifier("vider() efface les fronts (doigt, clavier, manette)", not f.dashPressed and not f.skill1Pressed and not f.skill2Pressed and not f.skill3Pressed and not f.attackPressed, f)
	verifier("vider() ne lâche pas ce qui est tenu", f.attack)
	doigt(2, centre("attack"), false)
	touche(KEY_L, false)
	pad_bouton(JOY_BUTTON_Y, false)
	pauses = 0
	touche(KEY_ESCAPE, true)
	touche(KEY_ESCAPE, true, true)
	touche(KEY_ESCAPE, false)
	verifier("Échap émet pause_demandee, une seule fois", pauses == 1, pauses)
	touche(KEY_P, true)
	touche(KEY_P, false)
	verifier("P émet pause_demandee", pauses == 2, pauses)
	e.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	verifier("bouton retour d'Android : pause_demandee", pauses == 3 and not quit_on_go_back, pauses)
	verifier("Échap et P ne sont pas des commandes de jeu", e.lire() == D6Game.empty_input())

func _perte_du_focus() -> void:
	doigt(1, gauche(0.5, 0.5), true)
	glisse(1, gauche(0.5, 0.5) + Vector2(58.0 * k(), 0.0))
	doigt(2, centre("attack"), true)
	vieillir_appui()
	verifier("avant la perte du focus : le pouce tient l'attaque", e.lire().attack)
	touche(KEY_D, true)
	clic(MOUSE_BUTTON_LEFT, true, HEROS, MOUSE_BUTTON_MASK_LEFT)
	pad_bouton(JOY_BUTTON_X, true)
	e.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	e.vider()
	var f: Dictionary = e.lire()
	verifier("perte du focus : plus rien n'est tenu", not f.attack and f.moveX == 0.0 and not e.interface_tactile().stick.active and not bouton("attack").pressed, f)

func _zone_sure() -> void:
	var d: RefCounted = e._doigts
	var taille := Vector2(844.0, 390.0)
	d.disposer(taille, {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}, 1.0)
	var a := bouton("attack")
	var dash := bouton("dash")
	verifier("paysage 844 × 390 : les positions du combat V3 (attaque 676 × 290, dash 779,68 × 312,04)", is_equal_approx(a.x, 676.0) and is_equal_approx(a.y, 290.0) and absf(dash.x - 779.68) < 0.01 and absf(dash.y - 312.04) < 0.01, [a.x, a.y, dash.x, dash.y])
	_arc(taille) # petit téléphone : mêmes exigences (cibles, vides, tout dans l'écran)
	verifier("paysage 844 × 390 : zone joystick = 48 % de la largeur", is_equal_approx(d.zone_x, 844.0 * 0.48), d.zone_x)
	d.disposer(taille, {"top": 0.0, "right": 44.0, "bottom": 21.0, "left": 44.0}, 1.0)
	a = bouton("attack")
	verifier("zone sûre : les boutons s'écartent de l'encoche et de la barre de gestes", is_equal_approx(a.x, 676.0 - 44.0) and is_equal_approx(a.y, 290.0 - 21.0), [a.x, a.y])
	var boutons: Array = e.interface_tactile().buttons
	verifier("zone sûre : aucun bouton (anneau compris) ne mord sur l'encoche ni sur la barre de gestes", boutons.all(func(b: Dictionary) -> bool: return b.x + b.r + 9.0 <= 844.0 - 44.0 and b.y + b.r + 9.0 <= 390.0 - 21.0))
	doigt(1, Vector2(2.0, 388.0), true)
	var s: Dictionary = e.interface_tactile().stick
	doigt(1, Vector2(2.0, 388.0), false)
	verifier("zone sûre : le dessin du joystick sort de l'encoche gauche et de la barre du bas", is_equal_approx(s.baseX, 58.0 + 12.0 + 44.0) and is_equal_approx(s.baseY, 390.0 - 58.0 - 12.0 - 21.0), [s.baseX, s.baseY])
	e._disposer()

func _front_garde_une_image() -> void:
	tap(3, centre("dash"))
	tap(2, centre("attack"))
	tap(4, centre("skill1"))
	await process_frame
	await process_frame
	var f: Dictionary = e.lire()
	verifier("fronts lus deux images plus tard : aucun tap perdu", f.dashPressed and f.attackPressed and f.skill1Pressed, f)
	f = e.lire()
	verifier("fronts : jamais rendus deux fois", not f.dashPressed and not f.attackPressed and not f.skill1Pressed, f)

func _hors_jeu() -> void:
	for cas: String in ["ville", "pause", "menu", "sans partie"]:
		match cas:
			"ville": app.ecran = "ville"
			"pause": partie.en_pause = true
			"menu": partie.game.mode = "choice"
			"sans partie": partie.game = null
		tap(3, centre("dash"))
		await process_frame
		await process_frame
		app.ecran = "jeu"
		partie.en_pause = false
		partie.game = {"mode": "play", "player": {"x": HEROS.x, "y": HEROS.y}}
		verifier("hors du jeu (%s) : un tap ne part pas en dash à la reprise" % cas, not e.lire().dashPressed)
	# Le pouce reste posé sur le joystick pendant tout le menu (cas réel).
	var p := gauche(0.4, 0.6)
	doigt(1, p, true)
	glisse(1, p + Vector2(58.0 * k(), 0.0))
	partie.game.mode = "choice"
	await process_frame
	partie.game.mode = "play"
	verifier("pouce resté posé pendant un menu : le joystick répond toujours à la reprise", e.lire().moveX == 1.0)
	doigt(1, p, false)

func _portrait() -> void:
	root.size = Vector2i(390, 844)
	await process_frame
	var taille := root.get_visible_rect().size
	print("portrait : viewport %s · fenêtre %s · échelle %s" % [taille, root.size, k()])
	verifier("portrait : le viewport suit la fenêtre et la disposition est recalculée", taille.y > taille.x and is_equal_approx(bouton("attack").x, taille.x - 70.0 * k()), [taille, bouton("attack").x])
	var libres := true
	var boutons: Array = e.interface_tactile().buttons
	for i in boutons.size():
		for j in range(i + 1, boutons.size()):
			var ecart := Vector2(boutons[i].x - boutons[j].x, boutons[i].y - boutons[j].y).length()
			libres = libres and ecart > boutons[i].r + boutons[j].r
	verifier("portrait : aucun bouton n'en chevauche un autre, tous dans l'écran", libres and boutons.all(func(b: Dictionary) -> bool: return b.x - b.r > 0.0 and b.x + b.r < taille.x and b.y + b.r < taille.y))
	# Pouce gauche dans le coin bas-gauche du portrait (150, 720 → 150, 660 sur 390 × 844) : il marche, il ne dashe pas.
	var u := taille.x / 390.0
	doigt(3, Vector2(150.0, 720.0) * u, true)
	glisse(3, Vector2(150.0, 660.0) * u)
	var f: Dictionary = e.lire()
	doigt(3, Vector2(150.0, 660.0) * u, false)
	verifier("portrait : le pouce gauche pilote le joystick sans dash parasite", f.moveY == -1.0 and not f.dashPressed and not f.attack, f)
	tap(4, centre("dash"))
	verifier("portrait : le dash répond à sa place", e.lire().dashPressed)
	root.size = Vector2i(1280, 720)
	await process_frame

# ---------------------------------------------------------------- les gestes dans la VRAIE simulation

## Une vraie partie (sim/), sans ennemi, jouée par les InputFrame de la vue : ce que le geste
## DONNE en jeu. Profil neuf : compétence, gadget, emplacement 3 vide.
func _partie_reelle() -> Dictionary:
	var tuning: Dictionary = D6Data.create_tuning()
	var g: Dictionary = D6Game.create_game({"seed": 7.0, "startFloor": 1.0, "meta": D6Profile.new_profile(tuning)})
	g.godMode = true
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles]:
		liste.clear()
	g.room.waves = []
	g.events.clear()
	return g

## `n` pas de simulation joués par la vue ; rend le nombre d'événements de chaque type.
func jouer(g: Dictionary, n: int) -> Dictionary:
	var vus := {}
	for i in n:
		D6Game.step_game(g, e.lire())
		for ev in g.events:
			vus[ev.type] = vus.get(ev.type, 0) + 1
		g.events.clear()
	return vus

func _gestes_dans_la_simulation() -> void:
	var g := _partie_reelle()
	var tenir: float = g.tuning["super"].holdTime
	var longtemps := int(ceilf(tenir * 60.0)) * 3
	var c := centre("attack")
	verifier("simulation : profil neuf, l'emplacement 3 est vide", D6Loadout.slot_view(g, 2) == null and D6Loadout.slot_view(g, 0) != null)
	# 1. Appui bref, jauge pleine : un coup, pas d'ultime.
	g.player.superCharge = 1.0
	tap(2, c)
	var vus := jouer(g, longtemps)
	verifier("simulation : un appui bref donne exactement un coup, jamais l'ultime (jauge pleine)", vus.get("attackStart", 0) == 1 and vus.get("super", 0) == 0 and g.player.superCharge == 1.0, vus)
	# 2. Glisser-relâcher, jauge pleine : un coup, vers le haut, pas d'ultime.
	jouer(g, 60)
	doigt(2, c, true)
	glisse(2, c + Vector2(0.0, -60.0 * k()))
	vieillir_appui()
	vus = jouer(g, longtemps)
	verifier("simulation : pendant un glisser, aucun coup, aucun ultime, et l'armement ne monte pas", vus.get("attackStart", 0) == 0 and vus.get("super", 0) == 0 and g.player.superHold == 0.0, [vus, g.player.superHold])
	doigt(2, c + Vector2(0.0, -60.0 * k()), false)
	vus = jouer(g, 3)
	var vers_le_haut: bool = absf(angle_difference(g.player.facing, -PI / 2.0)) < 0.01
	vus.merge(jouer(g, longtemps))
	verifier("simulation : glisser-relâcher donne exactement un coup, vers le haut, jamais l'ultime", vus.get("attackStart", 0) == 1 and vus.get("super", 0) == 0 and vers_le_haut and g.player.superCharge == 1.0, [vus, g.player.facing])
	# 3. Emplacement vide : inerte.
	jouer(g, 60)
	var avant := JSON.stringify(g.player.slots)
	tap(6, centre("skill3"))
	var f: Dictionary = e.lire()
	D6Game.step_game(g, f)
	vus = jouer(g, 30)
	verifier("simulation : toucher l'emplacement vide ne fait rien (aucun événement, aucun état changé, pas d'attaque)", f.skill3Pressed and not f.attackPressed and ["castStart", "skill", "gadget", "gadgetCharge", "attackStart", "super", "dash"].all(func(t: String) -> bool: return not vus.has(t)) and JSON.stringify(g.player.slots) == avant and g.player.state == "free", [vus, g.player.state])
	# 4. Pouce maintenu, jauge pleine : l'ultime part, après le maintien.
	doigt(2, c, true)
	vieillir_appui()
	vus = jouer(g, int(ceilf(tenir * 60.0)) - 2)
	verifier("simulation : pouce maintenu jauge pleine, l'armement monte et l'ultime n'est pas encore parti", vus.get("super", 0) == 0 and g.player.superHold > 0.0, [vus, g.player.superHold])
	vus = jouer(g, 30)
	doigt(2, c, false)
	verifier("simulation : le maintien lance l'ultime, une fois", vus.get("super", 0) == 1 and g.player.superCharge < 1.0, vus)

