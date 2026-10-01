extends SceneTree
## Sonde d'OBSERVATION pour le contrôle du matin du kit (SANDBOX/studio_kit/jeux.json) : le vrai
## jeu, amené tour à tour à ses écrans clés, photographiés dans $CAPTURE_OUT.
##   <godot> --fixed-fps 60 --position -3000,-3000 --resolution 1280x720 --path . --script res://outils/observation.gd
## SANS --headless (il faut un vrai rendu). Les descentes sont jouées par un pilote simple et une
## graine fixe : d'un jour à l'autre, la même partie. Une photo ne dit rien du plaisir de jeu.

const Principal = preload("res://jeu/principal.tscn")
## Les étapes, dans l'ordre : {photo, images à attendre avant la photo, action sur l'application}.
const ETAPES := [
	{"photo": "titre", "images": 90, "action": "titre"},
	{"photo": "ville", "images": 90, "action": "ville"},
	{"photo": "combat_cercle_1", "images": 300, "action": "descente", "etage": 1.0},
	{"photo": "combat_cercle_2", "images": 300, "action": "descente", "etage": 7.0},
	{"photo": "combat_cercle_3", "images": 300, "action": "descente", "etage": 13.0},
]
const GRAINE := 7.0
const DOSSIER_ESSAI := "user://essais_observation"
const PORTEE_FRAPPE := 70.0

var _app: Node
var _sortie := ""
var _etape := -1
var _attente := 0
var _prises := 0

func _initialize() -> void:
	_sortie = OS.get_environment("CAPTURE_OUT")
	if _sortie == "":
		print("OBSERVATION: FAIL — CAPTURE_OUT absent")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_sortie)
	# Une observation ne touche jamais au vrai profil du joueur (jeu/profil.gd).
	# Elle repart d'un profil NEUF : le dossier d'essai est vidé (la même photo d'un jour à l'autre).
	if OS.get_environment("D666_DONNEES") == "":
		OS.set_environment("D666_DONNEES", DOSSIER_ESSAI)
		for f in DirAccess.get_files_at(DOSSIER_ESSAI):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DOSSIER_ESSAI.path_join(f)))
	_app = Principal.instantiate()
	root.add_child(_app)
	process_frame.connect(_image)

func _suivante() -> void:
	_etape += 1
	if _etape >= ETAPES.size():
		print("OBSERVATION: %s — %d photo(s) sur %d" % ["PASS" if _prises == ETAPES.size() else "FAIL", _prises, ETAPES.size()])
		quit(0 if _prises == ETAPES.size() else 1)
		return
	var e: Dictionary = ETAPES[_etape]
	_attente = e.images
	match e.action:
		"titre":
			_app.ouvrir_titre()
		"ville":
			_app.ouvrir_ville()
		"descente":
			_app.demarrer_descente(e.etage, false, false, GRAINE)
			_app.partie.entrees = _piloter

func _image() -> void:
	if _etape < 0: # première image : l'application est prête (son _ready a tourné)
		_suivante()
		return
	_attente -= 1
	if _attente > 0:
		return
	var e: Dictionary = ETAPES[_etape]
	var image := root.get_texture().get_image()
	if image.save_png(_sortie.path_join(e.photo + ".png")) == OK:
		_prises += 1
	if e.action == "descente":
		var g = _app.partie.game
		print("OBSERVATION %s : étage %d, vie %d, ennemis %d" % [e.photo, int(g.run.floor), int(g.player.hp), g.enemies.size()])
		_app.partie.entrees = Callable()
	_suivante()

## Pilote simple : va vers l'ennemi vivant le plus proche et frappe.
func _piloter() -> Dictionary:
	var g = _app.partie.game
	var input: Dictionary = D6Game.empty_input()
	var cible = null
	var d_min := INF
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or e.spawnT > 0.0:
			continue
		var d: float = D6Geo.dist2(g.player.x, g.player.y, e.x, e.y)
		if d < d_min:
			d_min = d
			cible = e
	if cible == null:
		return input
	var v := Vector2(cible.x - g.player.x, cible.y - g.player.y)
	if v.length() > PORTEE_FRAPPE:
		v = v.normalized()
		input.moveX = v.x
		input.moveY = v.y
	input.attack = true
	return input
