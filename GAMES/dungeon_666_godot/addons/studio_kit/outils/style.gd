extends SceneTree

## Contrôle du STYLE d'un jeu (kit 0.9.0, 2026-09-28) : chaque dessin que le jeu affiche, mesuré
## (StudioStyle) et rangé par famille de sa référence de style (style.json) ; ce qui sort de la bande
## de son registre est SIGNALÉ. Rien n'est jamais modifié : c'est une planche et une liste à regarder.
## Utilisé par le contrôle quotidien (verifier_tout.py --observer).
##   godot --position -3000,-3000 --path <jeu> --script res://addons/studio_kit/outils/style.gd -- <config.json>
## config : {"reference": "res://…/style.json", "dossier": "res://…/art/", "sortie": <dossier absolu>,
##           "exclure": [expressions régulières de noms à ne pas montrer (variantes de nuit, sols…)],
##           "code": [dossiers res:// dont les .gd citent les SVG affichés] (défaut : tout le jeu hors
##           addons, _dev, tests)}
## Un PNG est toujours affiché (il passe devant le SVG homonyme) ; un SVG sans PNG l'est si son nom est
## cité entre guillemets dans le code.
## Sorties : <sortie>/mesures.json, <sortie>/STYLE_planche.png (pas en --headless), et
## « STYLE : n dessins mesures, m a regarder ». Code 0 = mesuré (même avec des écarts) ; 2 = config.

const CASE := Vector2(92, 104)
const HAUT_CASE := 72.0
const LARGEUR := 1600
const ECHELLE_SVG := 4.0
const EXCLU_CODE := ["res://addons", "res://_dev", "res://tests", "res://.godot"]
const FOND := Color("#E9DCC6")
const ROUGE := Color("#B3261E")

var _conf: Dictionary = {}
var _vue: SubViewport
var _images := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var conf: Variant = JSON.parse_string(FileAccess.get_file_as_string(a[0])) if a.size() > 0 else null
	if not (conf is Dictionary) or not (conf as Dictionary).has("reference") or not (conf as Dictionary).has("sortie"):
		printerr("usage : style.gd -- <config.json> {reference, dossier, sortie, exclure, code}")
		quit(2)
		return
	_conf = conf
	var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(_conf["reference"])))
	if not (reference is Dictionary):
		printerr("référence de style illisible : %s" % _conf["reference"])
		quit(2)
		return
	var sortie := String(_conf["sortie"])
	DirAccess.make_dir_recursive_absolute(sortie)
	var dossier := String(_conf.get("dossier", "res://04_ASSETS/art/"))
	var resultats := {}
	var n_ecarts := 0
	for nom in _noms_affiches(dossier):
		var png := FileAccess.file_exists(dossier + nom + ".png")
		var img := _image(dossier, nom, png)
		var m := StudioStyle.mesurer(img)
		var r := {"famille": StudioStyle.famille(nom, reference), "png": png, "empreinte": _empreinte(dossier, nom, png)}
		r.merge(m)
		r["hors_style"] = StudioStyle.hors_style(nom, m, png, reference) if not m.is_empty() else []
		resultats[nom] = r
		if not (r["hors_style"] as Array).is_empty():
			n_ecarts += 1
			print("A REGARDER %s (%s) : %s" % [nom, r["famille"], " ; ".join(r["hors_style"])])
	var f := FileAccess.open(sortie.path_join("mesures.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(resultats, "  ", false))
	f.close()
	print("STYLE : %d dessins mesures, %d a regarder" % [resultats.size(), n_ecarts])
	if DisplayServer.get_name() == "headless":
		quit(0)
		return
	_planche(resultats, reference, dossier)


# Les dessins que le jeu AFFICHE, triés, moins les exclusions de la config.
func _noms_affiches(dossier: String) -> Array:
	var cite := _code()
	var tous := {}
	for fichier in DirAccess.get_files_at(dossier):
		var n := fichier.get_basename()
		if fichier.ends_with(".png"):
			tous[n] = true
		elif fichier.ends_with(".svg") and not FileAccess.file_exists(dossier + n + ".png") and ("\"%s\"" % n) in cite:
			tous[n] = true
	var exclure: Array[RegEx] = []
	for motif in _conf.get("exclure", []):
		var re := RegEx.new()
		if re.compile(String(motif)) == OK:
			exclure.append(re)
	var out: Array = tous.keys().filter(func(n: String) -> bool: return exclure.all(func(re: RegEx) -> bool: return re.search(n) == null))
	out.sort()
	return out


func _code() -> String:
	var texte := ""
	var dossiers: Array = _conf.get("code", [])
	if dossiers.is_empty():
		dossiers = ["res://"]
	for d in dossiers:
		texte += _lire_gd(String(d))
	return texte


func _lire_gd(dossier: String) -> String:
	if EXCLU_CODE.any(func(e: String) -> bool: return dossier.begins_with(e)):
		return ""
	var t := ""
	for f in DirAccess.get_files_at(dossier):
		if f.ends_with(".gd"):
			t += FileAccess.get_file_as_string(dossier.path_join(f))
	for d in DirAccess.get_directories_at(dossier):
		t += _lire_gd(dossier.path_join(d))
	return t


# Le dessin tel que le jeu le charge : le PNG importé (ou brut), sinon le SVG rastérisé.
func _image(dossier: String, nom: String, png: bool) -> Image:
	if png:
		var t: Texture2D = load(dossier + nom + ".png") if ResourceLoader.exists(dossier + nom + ".png") else null
		return t.get_image() if t != null else Image.load_from_file(dossier + nom + ".png")
	var img := Image.new()
	img.load_svg_from_string(FileAccess.get_file_as_string(dossier + nom + ".svg"), ECHELLE_SVG)
	return img


func _empreinte(dossier: String, nom: String, png: bool) -> String:
	return FileAccess.get_md5(dossier + nom + (".png" if png else ".svg"))


# La planche : une rangée par famille (ordre de la référence), le nom sous chaque dessin, en ROUGE
# s'il est à regarder (et « SVG » pour un ancien dessin plat).
func _planche(resultats: Dictionary, reference: Dictionary, dossier: String) -> void:
	_vue = SubViewport.new()
	_vue.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vue)
	var fond := ColorRect.new()
	fond.color = FOND
	_vue.add_child(fond)
	var familles: Array = reference.get("familles", {}).keys()
	familles.append("")
	var y := 8.0
	for fam in familles:
		var membres: Array = resultats.keys().filter(func(n: String) -> bool: return resultats[n]["famille"] == fam)
		if membres.is_empty():
			continue
		var registre := String(reference["familles"][fam].get("registre", "")) if fam != "" else "?"
		var n_hors := membres.filter(func(n: String) -> bool: return not (resultats[n]["hors_style"] as Array).is_empty()).size()
		_texte("%s  (registre %s)  %d dessins, %d a regarder" % [fam if fam != "" else "SANS FAMILLE", registre, membres.size(), n_hors], Vector2(8, y), 16, Color.BLACK)
		y += 24.0
		var x := 8.0
		for n in membres:
			if x + CASE.x > LARGEUR:
				x = 8.0
				y += CASE.y
			_poser(dossier, n, resultats[n], Vector2(x, y))
			x += CASE.x
		y += CASE.y + 6.0
	fond.size = Vector2(LARGEUR, y + 8)
	_vue.size = Vector2i(LARGEUR, int(y + 8))


func _poser(dossier: String, n: String, r: Dictionary, pos: Vector2) -> void:
	var img := _image(dossier, n, bool(r["png"]))
	if img == null or img.is_empty():
		return
	var k := HAUT_CASE / maxf(1.0, float(img.get_height()))
	var taille := Vector2(img.get_width(), img.get_height()) * k
	if taille.x > CASE.x - 8.0:
		taille *= (CASE.x - 8.0) / taille.x
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture = ImageTexture.create_from_image(img)
	t.position = pos + Vector2((CASE.x - taille.x) * 0.5, HAUT_CASE - taille.y)
	t.size = taille
	_vue.add_child(t)
	var hors := not (r["hors_style"] as Array).is_empty()
	_texte(n.substr(0, 14) + ("" if r["png"] else " SVG"), pos + Vector2(0, HAUT_CASE + 4), 9, ROUGE if hors else Color.BLACK)


func _texte(t: String, pos: Vector2, taille: int, couleur: Color) -> void:
	var la := Label.new()
	la.text = t
	la.position = pos
	la.add_theme_font_size_override("font_size", taille)
	la.add_theme_color_override("font_color", couleur)
	_vue.add_child(la)


func _process(_d: float) -> bool:
	if _vue == null:
		return false
	_images += 1
	if _images == 6:
		var chemin := String(_conf["sortie"]).path_join("STYLE_planche.png")
		_vue.get_texture().get_image().save_png(chemin)
		print("PLANCHE %s" % chemin)
		quit(0)
		return true
	return false
