class_name StudioAncrage
extends RefCounted

## ANCRAGE monde <-> écran — les briques communes à tous les jeux (kit 0.5, extraites de Kitten Factory).
##   ENTITÉ -> POSITION MONDE -> ANCRE / PRISE -> POSITION ÉCRAN (la règle) -> DESSIN (le nœud)
## Chaque jeu écrit sa couche d'ancrage (sa projection, ses prises, sa mise en scène) et s'appuie ici pour :
##   - le FORMAT d'une mesure : règle, dessin, écart, places admises, verdict ;
##   - le JUGEMENT : « à sa place » si le dessin tombe sur une place admise (à la tolérance près) ;
##   - l'IMAGE annotée : vert = la règle, rouge = le dessin, trait rouge si l'écart n'est pas expliqué.
## Un jeu la branche dans l'inspecteur par res://studio_inspecteur.json : "ancrage": {"script": …} (fonctions
## statiques mesurer(racine, etat) et ou_est(racine, etat, id)) ; questions « where_is <id> », « find_misplaced ».


## Une mesure. `places` : [{pourquoi, ecran: Vector2, jusqu_a?: Vector2}] — où le jeu a le droit de
## dessiner l'entité : un POINT, ou un SEGMENT de `ecran` à `jusqu_a` (un chat qui sautille au-dessus de sa
## place, une file d'attente). La première place est la règle elle-même. Invisible = toujours « à sa place ».
static func mesure(id: String, type: String, monde: Dictionary, places: Array, dessin: Vector2, visible: bool, tolerance_px: float) -> Dictionary:
	var regle: Vector2 = places[0]["ecran"] if not places.is_empty() else dessin
	var meilleure: Dictionary = {}
	var d_min := INF
	for p in places:
		var d := distance(dessin, p)
		if d < d_min:
			d_min = d
			meilleure = p
	var dans := not visible or d_min <= tolerance_px
	var ecart := dessin - regle
	return {"id": id, "type": type, "monde": monde, "regle_ecran": pt(regle), "dessin_ecran": pt(dessin),
		"ecart": pt(ecart), "ecart_px": snappedf(ecart.length(), 0.1), "visible": visible,
		"explique_par": {"place": String(meilleure.get("pourquoi", "")), "ecart_px": snappedf(d_min, 0.1)},
		"tolerance_px": tolerance_px, "dans_la_tolerance": dans,
		"verdict": ("à sa place : " + String(meilleure.get("pourquoi", ""))) if dans
			else "ÉCART : à %.0f px de toute place admise (la plus proche : %s)" % [d_min, meilleure.get("pourquoi", "")]}


## Distance d'un point à une place (point, ou segment ecran -> jusqu_a).
static func distance(point: Vector2, place: Dictionary) -> float:
	var a: Vector2 = place["ecran"]
	if not place.has("jusqu_a"):
		return point.distance_to(a)
	var b: Vector2 = place["jusqu_a"]
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Le bilan d'un ensemble de mesures (ce que l'inspecteur et le rapport montrent).
static func bilan(mesures: Array) -> Dictionary:
	var hors := mesures.filter(func(m: Dictionary) -> bool: return not bool(m["dans_la_tolerance"]))
	var par_type := {}
	for m in mesures:
		par_type[m["type"]] = int(par_type.get(m["type"], 0)) + 1
	return {"mesurees": mesures.size(), "par_type": par_type, "hors_tolerance": hors.size(),
		"fautes": hors.map(func(m: Dictionary) -> String: return "%s : %s" % [m["id"], m["verdict"]])}


## Image annotée. `vers_image` : du repère des mesures (écran du jeu) aux pixels de l'image.
static func annoter(image: Image, mesures: Array, vers_image: Transform2D = Transform2D.IDENTITY) -> Image:
	var img := image.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	for m in mesures:
		if not bool(m["visible"]):
			continue
		var r: Vector2 = vers_image * Vector2(m["regle_ecran"][0], m["regle_ecran"][1])
		var d: Vector2 = vers_image * Vector2(m["dessin_ecran"][0], m["dessin_ecran"][1])
		var faute := not bool(m["dans_la_tolerance"])
		if faute:
			_trait(img, r, d, Color(1, 0.2, 0.2))
		_croix(img, r, Color(0.1, 0.9, 0.3), 6 if faute else 4)
		_croix(img, d, Color(1, 0.2, 0.2) if faute else Color(1, 1, 1, 0.8), 3)
	return img


static func pt(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]


static func _croix(img: Image, p: Vector2, c: Color, t: int) -> void:
	for dx in range(-t, t + 1):
		_pixel(img, int(p.x) + dx, int(p.y), c)
		_pixel(img, int(p.x), int(p.y) + dx, c)


static func _trait(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(1.0, a.distance_to(b)))
	for s in n + 1:
		var p := a.lerp(b, float(s) / float(n))
		_pixel(img, int(p.x), int(p.y), c)


static func _pixel(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)
