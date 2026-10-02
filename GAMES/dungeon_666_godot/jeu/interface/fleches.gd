extends Control
## Flèches au bord de l'écran vers ce qui est hors champ : les ennemis (rouge), le Gardien et
## l'objet à activer (or). Portage de `drawOffscreen` (src/render/hud.mjs). La position à l'écran
## vient de la vue Monde (`monde_vers_ecran`) ; sans elle, rien n'est dessiné. Un ennemi DISPARU
## (`hidden` : le Traqueur en embuscade) n'a pas de flèche : elle trahirait d'où il est parti. Un
## Gardien dissous garde la sienne (il reste dessiné, en filigrane).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const MARGE := 26.0 # px des bords de la zone utile
const TAILLE := 8.0
const TAILLE_FORTE := 11.0 # Gardien, élite, objet à activer

var _pointes: Array = [] # {pos, angle, couleur, taille}
var _haut := 0.0
var _marges := Vector4.ZERO
var _coin := Vector2.ZERO

## `haut` : bas de la bande haute du HUD ; `coin` : coin haut-gauche du groupe de boutons tactiles.
func actualiser(game: Dictionary, monde, haut: float, marges: Vector4, coin: Vector2) -> void:
	_pointes.clear()
	_haut = haut
	_marges = marges
	_coin = coin
	if monde != null and monde.has_method("monde_vers_ecran"):
		var pal: Dictionary = Couleurs.PAL
		for e in game.enemies:
			if D6Js.truthy(e.get("dead")) or (D6Js.truthy(e.get("hidden")) and not D6Js.truthy(e.get("boss"))):
				continue
			var fort := D6Js.truthy(e.get("boss")) or D6Js.truthy(e.get("eliteMod"))
			_pointer(monde.monde_vers_ecran(Vector2(e.x, e.y)), pal.bossTrim if D6Js.truthy(e.get("boss")) else Color(pal.danger, 0.85), TAILLE_FORTE if fort else TAILLE)
		var objet = game.room.get("interact")
		if objet is Dictionary and not D6Js.truthy(objet.get("used")):
			_pointer(monde.monde_vers_ecran(Vector2(objet.x, objet.y)), pal.gold, TAILLE_FORTE)
	queue_redraw()

func _pointer(ecran: Vector2, couleur: Color, taille: float) -> void:
	if ecran.x > 0.0 and ecran.x < size.x and ecran.y > _haut and ecran.y < size.y:
		return
	var y := clampf(ecran.y, _haut + 10.0, size.y - MARGE - _marges.w)
	var droite := _coin.x - 14.0 if y > _coin.y - MARGE else size.x - MARGE - _marges.z
	var x := clampf(ecran.x, MARGE + _marges.x, droite)
	_pointes.append({"pos": Vector2(x, y), "angle": (ecran - size / 2.0).angle(), "couleur": couleur, "taille": taille})

func _draw() -> void:
	for p in _pointes:
		var t: float = p.taille
		draw_set_transform(p.pos, p.angle)
		draw_colored_polygon(PackedVector2Array([Vector2(t, 0.0), Vector2(-t * 0.6, -t * 0.7), Vector2(-t * 0.6, t * 0.7)]), p.couleur)
	draw_set_transform(Vector2.ZERO)
