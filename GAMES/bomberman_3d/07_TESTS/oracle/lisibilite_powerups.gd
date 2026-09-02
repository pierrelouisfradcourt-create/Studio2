# lisibilite_powerups.gd — oracle PIXEL de la lisibilite des power-ups et du danger.
#
# forge:run_mode = gpu_window
#
# CE QUE CE VOLET ETABLIT, et qu'aucun test mecanique ne peut etablir : que la
# discernabilite declaree dans la palette SE VOIT REELLEMENT A L'ECRAN. Une table de
# couleurs distinctes peut donner trois pastilles indiscernables si elles sont minuscules,
# masquees ou hors champ.
#
# Chaine prouvee, dans cet ordre :
#   bonus VISIBLE      -> la region projetee d'une case portant un power-up DIFFERE de la
#                         meme case vide (l'objet se voit)
#   type IDENTIFIABLE  -> les regions des trois types different DEUX A DEUX (on distingue
#                         lequel c'est, pas seulement qu'il y en a un)
#   danger LISIBLE     -> une case menacee par une bombe armee differe de la meme case sans
#                         bombe, AVANT toute explosion
#
# Les maillons `ramassage -> effet reel -> feedback` sont couverts mecaniquement ailleurs
# (test_loop_and_rules pour l'effet, test_lisibilite pour le libelle) : ils ne sont pas
# observables en pixel sans piloter une partie, et je ne les revendique pas ici.
#
# Sortie : "FORGE_ORACLE lisibilite_powerups {json}".
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const View = preload("res://06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")

const FRAMES := 8
const DEMI := 14

# Cases d'essai, alignees et libres sur la carte 0.
var _cases: Array = [Vector2i(5, 5), Vector2i(7, 5), Vector2i(9, 5)]
var _case_bombe := Vector2i(5, 9)

var _vue
var _base
var _images: Array = []
var _etats: Array = []
var _i := 0
var _f := 0


func _etat_avec(powerup_par_case: Dictionary, bombe: bool):
	var desc: Dictionary = Content.descripteur(0)
	var s = State.initial(Validator.carte_validee(desc), desc, 1, 4)
	# Terrain degage autour des cases d'essai : on mesure la lisibilite de l'OBJET, pas
	# celle d'un bloc qui se trouverait derriere.
	for c in _cases:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				s.arene.detruire(c + Vector2i(dx, dy))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			s.arene.detruire(_case_bombe + Vector2i(dx, dy))
	for c in powerup_par_case.keys():
		s.powerups[c] = powerup_par_case[c]
	if bombe:
		s.bombes.append({"proprietaire": 1, "cellule": _case_bombe, "meche": 90, "rayon": 2})
	return s


func _initialize() -> void:
	# Etat 0 = reference vide. Etats 1..3 = un seul power-up, toujours SUR LA MEME CASE
	# (comparer deux cases differentes ne prouverait rien : elles different deja).
	_etats.append(_etat_avec({}, false))
	for id in P.POWERUP_IDS:
		_etats.append(_etat_avec({_cases[0]: String(id)}, false))
	_etats.append(_etat_avec({}, true))
	_vue = View.new()
	get_root().add_child(_vue)
	_vue.batir(_etats[0], String(Content.descripteur(0).get("theme", "")))


func _region_diff(a: Image, b: Image, centre: Vector2, demi: int) -> int:
	if a == null or b == null or centre.x < 0.0:
		return -1
	var n := 0
	var x0: int = int(max(0, int(centre.x) - demi))
	var y0: int = int(max(0, int(centre.y) - demi))
	var x1: int = int(min(a.get_width() - 1, int(centre.x) + demi))
	var y1: int = int(min(a.get_height() - 1, int(centre.y) + demi))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func _process(_delta: float) -> bool:
	_f += 1
	if _f < FRAMES:
		return false
	_f = 0
	_images.append(get_root().get_texture().get_image())
	_i += 1
	if _i < _etats.size():
		_vue.rafraichir(_etats[_i])
		return false

	var fails: Array = []
	var p0: Vector2 = _vue.projeter(_cases[0])
	var pb: Vector2 = _vue.projeter(_case_bombe)
	var mesures: Dictionary = {}

	if p0.x < 0.0 or pb.x < 0.0:
		fails.append("cases d'essai non projetables (camera ?)")
	else:
		# (1) VISIBLE : chaque power-up modifie la case par rapport a la reference vide.
		for k in range(P.POWERUP_IDS.size()):
			var d: int = _region_diff(_images[0], _images[1 + k], p0, DEMI)
			mesures["visible_" + String(P.POWERUP_IDS[k])] = d
			if d <= 0:
				fails.append("%s INVISIBLE (0 pixel change sur sa case)" % String(P.POWERUP_IDS[k]))

		# (2) IDENTIFIABLE : les trois types different DEUX A DEUX sur la meme case.
		for a in range(P.POWERUP_IDS.size()):
			for b in range(a + 1, P.POWERUP_IDS.size()):
				var d2: int = _region_diff(_images[1 + a], _images[1 + b], p0, DEMI)
				var cle: String = "%s_vs_%s" % [String(P.POWERUP_IDS[a]), String(P.POWERUP_IDS[b])]
				mesures[cle] = d2
				if d2 <= 0:
					fails.append("%s INDISCERNABLES a l'ecran" % cle)

		# (3) DANGER : une bombe armee marque sa zone AVANT d'exploser.
		var d3: int = _region_diff(_images[0], _images[_images.size() - 1], pb, DEMI)
		mesures["danger_annonce"] = d3
		if d3 <= 0:
			fails.append("zone de danger NON ANNONCEE avant explosion")

	print("FORGE_ORACLE lisibilite_powerups " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails, "mesures": mesures,
		"viewport": [_images[0].get_width(), _images[0].get_height()],
	}))
	quit(0 if fails.is_empty() else 1)
	return true
