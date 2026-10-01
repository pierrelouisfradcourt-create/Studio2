extends SceneTree

## Rejoue un SCÉNARIO enregistré, sans aucune logique de décision : à l'image N, il appuie sur le bouton X.
## Aux points de contrôle, l'EMPREINTE de l'état du jeu (sha256 de son JSON) est comparée à l'enregistrement :
## la preuve que c'est LA MÊME PARTIE, image pour image.
##   godot --fixed-fps 60 --headless --path <jeu> --script res://addons/studio_kit/outils/rejouer.gd -- <scenario.json> [sortie]
## Sortie : 0 = partie identique à tous les points ; 1 = divergence (dite : première image, point, attendu/obtenu) ;
## 2 = scénario illisible. [sortie] : un dossier où écrire resultat.json (et, si le scénario le demande, des
## captures aux points de contrôle — sans --headless).
##
## Format (écrit par l'enregistreur du jeu) : {scene, fps, acceleration, image_acceleration, groupe_boutons,
## etat: {script, propriete}, actions: [{image, bouton, chemin?}], points: [{image, empreinte, …}], image_fin}.
## Le jeu doit démarrer SANS sa sauvegarde quand il est lancé par --script (sinon la partie dépend du joueur).
## `chemin` (le nœud exact appuyé) est rejoué tel quel, même caché : on rejoue CE QUI A ÉTÉ FAIT (mesuré le
## 27/09 : un robot appuie parfois sur des boutons que son propre appui précédent vient de cacher).
## Forme COMPACTE (une partie = des milliers d'appuis) : "boutons": [[nom, chemin], …] et
## "actions": [[image, rang dans boutons], …].
## APPELS (kit 0.9.1) : un robot qui joue en appelant les MÊMES fonctions que les boutons (ex. KF
## sonde_progression : `_on_acheter…`) s'enregistre aussi : "appels": [[méthode, [args]], …] et, dans
## "actions", [image, rang dans appels, "appel"]. L'appel est fait sur le nœud qui porte l'état (etat.script),
## dans l'ordre de la liste, mêlé aux appuis. Une méthode absente est comptée dans « boutons_absents ».

var _s: Dictionary = {}
var _f := 0
var _actions := {}
var _points := {}
var _sortie := ""
var _resultats: Array = []
var _divergence: Dictionary = {}
var _absents := {}
var _pret := false   # le scénario est chargé : sans lui, _process ne doit RIEN conclure (faux vert du 27/09)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var brut: Variant = JSON.parse_string(FileAccess.get_file_as_string(a[0])) if a.size() > 0 and FileAccess.file_exists(a[0]) else null
	if not (brut is Dictionary) or not (brut as Dictionary).has("actions"):
		printerr("scénario illisible : %s" % (a[0] if a.size() > 0 else "(aucun)"))
		quit(2)
		return
	_s = brut
	_sortie = a[1] if a.size() > 1 else ""
	var table: Array = _s.get("boutons", [])
	var appels: Array = _s.get("appels", [])
	for x in _s["actions"]:
		var compacte: bool = x is Array
		var act := {}
		if compacte and (x as Array).size() > 2 and String(x[2]) == "appel":
			var ap: Array = appels[int(x[1])]
			act = {"appel": String(ap[0]), "args": ap[1] if ap.size() > 1 else []}
		else:
			var b: Array = table[int(x[1])] if compacte else [x["bouton"], x.get("chemin", "")]
			act = {"bouton": String(b[0]), "chemin": String(b[1])}
		var k := int(x[0]) if compacte else int(x["image"])
		if not _actions.has(k):
			_actions[k] = []
		_actions[k].append(act)
	for p in _s.get("points", []):
		_points[int(p["image"])] = p
	root.add_child((load(String(_s["scene"])) as PackedScene).instantiate())
	_pret = true


func _process(_delta: float) -> bool:
	if not _pret:
		return true
	_f += 1
	if _f == int(_s.get("image_acceleration", 0)):
		Engine.time_scale = float(_s.get("acceleration", 1.0))
	for a in _actions.get(_f, []):
		_appuyer(a)
	if _points.has(_f):
		_controler(_points[_f])
	if _f >= int(_s.get("image_fin", 0)) or not _divergence.is_empty():
		_conclure()
		return true
	return false


func _appuyer(a: Dictionary) -> void:
	if a.has("appel"):
		var cible := StudioInspecteur.trouver(root, String((_s.get("etat", {}) as Dictionary).get("script", "")))
		if cible != null and cible.has_method(String(a["appel"])):
			cible.callv(String(a["appel"]), a["args"])
		else:
			_absents[String(a["appel"]) + "()"] = int(_absents.get(String(a["appel"]) + "()", 0)) + 1
		return
	var nom := String(a["bouton"])
	if a["chemin"] != "":
		var exact := root.get_node_or_null(NodePath(String(a["chemin"])))
		if exact is BaseButton:
			exact.emit_signal("pressed")
			return
	for n in get_nodes_in_group(String(_s.get("groupe_boutons", "affordance"))):
		if n is BaseButton and String(n.name) == nom:
			n.emit_signal("pressed")
			return
	_absents[nom] = int(_absents.get(nom, 0)) + 1   # le bouton n'existe pas (encore) à cette image


func _controler(p: Dictionary) -> void:
	var e := empreinte()
	var ok := e == String(p["empreinte"])
	_resultats.append({"image": _f, "identique": ok})
	if not ok:
		_divergence = {"image": _f, "attendu": p["empreinte"], "obtenu": e, "resume_attendu": p.get("resume", {}), "resume_obtenu": resume()}


func empreinte() -> String:
	return JSON.stringify(_etat()).sha256_text()


func resume() -> Dictionary:
	var e := _etat()
	var out := {}
	for k in (_s.get("resume_cles", []) as Array):
		out[k] = e.get(k)
	return out


func _etat() -> Dictionary:
	var conf: Dictionary = _s.get("etat", {})
	var n := StudioInspecteur.trouver(root, String(conf.get("script", "")))
	var e: Variant = n.get(String(conf.get("propriete", ""))) if n else null
	return e if e is Dictionary else {}


func _conclure() -> void:
	# IDENTIQUE exige d'avoir CONTRÔLÉ tous les points enregistrés (et au moins un) : sinon on ne sait rien
	var complet := _points.size() > 0 and _resultats.size() == _points.size()
	var identique := _divergence.is_empty() and complet
	var r := {"points_controles": _resultats.size(), "points_enregistres": _points.size(), "identique": identique, "images_jouees": _f,
		"divergence": _divergence, "boutons_absents": _absents}
	if _sortie != "":
		DirAccess.make_dir_recursive_absolute(_sortie)
		var f := FileAccess.open(_sortie.path_join("resultat.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(r, "  "))
		f.close()
	if identique:
		print("REJEU IDENTIQUE : %d points de contrôle sur %d, %d images" % [_resultats.size(), _points.size(), _f])
	elif _divergence.is_empty():
		print("REJEU INCOMPLET : %d points contrôlés sur %d enregistrés — rien n'est prouvé" % [_resultats.size(), _points.size()])
	else:
		print("REJEU DIVERGE à l'image %d (point %d/%d) : attendu %s, obtenu %s" % [_divergence["image"], _resultats.size(),
			_points.size(), str(_divergence["resume_attendu"]), str(_divergence["resume_obtenu"])])
	quit(0 if identique else 1)
