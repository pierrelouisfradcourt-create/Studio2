extends Node
## Banc des trois ULTIMES de classe (combat V3, étape 2) : le vrai jeu (jeu/principal.tscn, toutes
## ses vues) dans un vrai combat joué par le bot habile, l'ultime de la classe lancé par le bot dès
## que la jauge — offerte pleine par le banc — le permet. Sert à JUGER À L'ÉCRAN : le banc enregistre
## lui-même une image à chaque instant qui compte (lancement, plein effet, fin), repéré par les
## ÉVÉNEMENTS de la simulation, puis se ferme. OUTIL D'ESSAI : seul ce banc écrit dans l'état
## (jauge pleine, héros increvable), jamais le jeu.
##   D666_CLASSE = revenant (défaut : Forme du Damné) | bourreau (Sentence capitale) | chasseresse (Meute des Limbes)
##   D666_ETAGE  = étage de départ (défaut 7) ; D666_GRAINE = graine (défaut 11)
##   D666_SORTIE = dossier des images (défaut _dev/captures/lot_v3_ultimes)
##   D666_JAUGE  = image du banc où la jauge est offerte (défaut 150 : le combat est engagé)
##   <godot> --position -3000,-3000 --resolution 1600x900 --path . res://jeu/essai/ultimes.tscn
## SANS --headless (il faut un vrai rendu). Expose `partie`, comme les autres bancs.

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const Bots = preload("res://outils/bots/bots.gd")
const DONNEES := "user://essais"
const KITS := {"revenant": ["lance", "nova", "chaine"], "bourreau": ["bond", "cri", "chaine"], "chasseresse": ["volee", "piege", "brasier"]}
const DUREE_MAX := 3600 # images : le banc se ferme de toute façon
## Les instants à montrer, par classe : [événement attendu, images après lui, nom de l'image].
const INSTANTS := {
	"revenant": [["formStart", 6, "1_transformation"], ["formStart", 80, "2_griffes"], ["formRush", 3, "3_ruee_spectrale"],
		["formHowl", 5, "4_hurlement"], ["formStart", 430, "5_mi_duree"], ["formBurst", 4, "6_embrasement"], ["formEnd", 40, "7_retour"]],
	"bourreau": [["super", 16, "1_lame_levee"], ["ultFreeze", 6, "2_temps_fige"], ["ultStrike", 3, "3_fracas"], ["ultStrike", 14, "4_executions"], ["superEnd", 20, "5_apres"]],
	"chasseresse": [["allySpawn", 8, "1_apparition"], ["allyBite", 4, "2_morsure"], ["allySpawn", 200, "3_plein_combat"],
		["allyHurt", 3, "4_ils_encaissent"], ["allySpawn", 640, "5_fin_de_duree"], ["allyGone", 6, "6_disparition"]],
}

var app: Node
var partie: Node

var _classe := "revenant"
var _images := 0
var _temps := 0.0
var _jauge := 150
var _mem := {}
var _attente: Array = [] # [images restantes, nom]
var _vus := {}
var _reste := 0
var _sortie := ""
## Coût du dessin (appels du canevas par image), hors ultime et pendant qu'il agit : [somme, images].
var _cout := {false: [0, 0], true: [0, 0]}

func _ready() -> void:
	# Un essai ne touche jamais au vrai profil ni aux vrais réglages du joueur (jeu/profil.gd).
	if OS.get_environment(Profil.ENV_DOSSIER) == "":
		OS.set_environment(Profil.ENV_DOSSIER, DONNEES)
	_classe = _env("D666_CLASSE", "revenant")
	_jauge = int(_env("D666_JAUGE", "150"))
	_sortie = _env("D666_SORTIE", ProjectSettings.globalize_path("res://_dev/captures/lot_v3_ultimes"))
	DirAccess.make_dir_recursive_absolute(_sortie)
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	app.profil = _profil(_classe)
	app.demarrer_descente(float(_env("D666_ETAGE", "7")), false, false, float(_env("D666_GRAINE", "11")))
	partie.game.godMode = true
	partie.entrees = _lire_bot
	partie.evenements.connect(_sur_evenements)
	_reste = INSTANTS[_classe].size()

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

## Profil d'essai : tout débloqué, la classe demandée, ses trois emplacements remplis.
func _profil(classe: String) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = t[k].keys()
	m.loadout = {"classId": classe, "slots": KITS[classe]}
	m.equipment.arme = D6Profile.starter_weapon(t, t.classes[classe].weapons[0])
	return D6Profile.sanitize_profile(m, t)

func _lire_bot() -> Dictionary:
	var g: Dictionary = partie.game
	if g.mode == "choice":
		Bots.resolve_choice(g, "skilled")
	# La jauge est offerte une fois le combat engagé : le bot décide lui-même de lancer l'ultime.
	if _images >= _jauge and g.telemetry.superUses == 0.0 and not D6KitSupers.acting(g):
		g.player.superCharge = 1.0
	return Bots.play("skilled", g, _mem)

## Le premier événement de chaque sorte attendue arme la prise des images qui en dépendent.
func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		if _vus.has(ev.type):
			continue
		_vus[ev.type] = true
		for instant in INSTANTS[_classe]:
			if instant[0] == ev.type:
				_attente.append([instant[1], instant[2]])

## Les « images » du banc sont des soixantièmes de seconde RÉELS (la fenêtre d'essai peut rendre
## bien plus vite que 60 images par seconde) : un instant « 6 images après » reste 0,1 s après.
func _process(delta: float) -> void:
	_temps += delta * 60.0
	_peser()
	if partie.game != null and partie.game.mode == "choice":
		Bots.resolve_choice(partie.game, "skilled") # un menu ouvert arrête la partie : le bot le résout
	var pas := int(_temps) - _images
	_images += pas
	for a in _attente.duplicate():
		a[0] -= pas
		if a[0] <= 0:
			_attente.erase(a)
			_enregistrer(a[1])
	if _reste <= 0 or _images >= DUREE_MAX:
		print("fin du banc : image %d, %d instant(s) non vus ; événements vus : %s" % [_images, _reste, ", ".join(_vus.keys())])
		print("coût (appels de dessin du canevas par image) : hors ultime %.1f (%d images) ; ultime en cours %.1f (%d images)" % [_cout[false][0] / maxf(1.0, _cout[false][1]), _cout[false][1], _cout[true][0] / maxf(1.0, _cout[true][1]), _cout[true][1]])
		get_tree().quit()

## Mesure du coût : les appels de dessin de l'image, rangés selon qu'un ultime agit ou non (en jeu).
func _peser() -> void:
	var g = partie.game
	if g == null or g.mode != "play" or _images < 60:
		return
	var appels := RenderingServer.viewport_get_render_info(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var cle: bool = D6KitSupers.acting(g)
	_cout[cle][0] += appels
	_cout[cle][1] += 1

func _enregistrer(nom: String) -> void:
	await RenderingServer.frame_post_draw
	var chemin := "%s/%s_%s.png" % [_sortie, _classe, nom]
	get_viewport().get_texture().get_image().save_png(chemin)
	print("image : ", chemin)
	_reste -= 1
