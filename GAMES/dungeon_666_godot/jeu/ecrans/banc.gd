extends Node
## Banc des écrans : le vrai `principal.gd` (jeu/ecrans/banc_app.gd), une Partie, et la variable
## d'environnement D666_ECRAN qui amène à l'écran voulu :
##   titre · benediction · butin · marchand · evenement · coffre · fontaine · mort · mort_arene
##   victoire · pause · abandon · labo · feel
## D666_VUES : « toutes » monte aussi le monde, le HUD… (défaut : les écrans seuls, sur fond nu).
## D666_RICHE=1 : le profil d'essai est celui d'un joueur avancé (jeu/ville/profil_essai.gd), qui a
##   des points de compétence à dépenser (la pastille du bouton d'entrée en Ville, à l'écran titre).
##   D666_ECRAN=marchand <godot> --path . --script res://outils/capture.gd -- res://jeu/ecrans/banc.tscn <sortie.png> 120

const App = preload("res://jeu/ecrans/banc_app.gd")
const Scenes = preload("res://jeu/ecrans/banc_scenes.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const DONNEES := "user://essais_ecrans"
const GRAINE := 7.0
const OR_DU_MARCHAND := 60.0
const IMAGES_AVANT_PAUSE := 20
## Bouton de la pause à presser pour atteindre un écran qui s'ouvre depuis elle.
const DEPUIS_LA_PAUSE := {"labo": "%Labo", "feel": "%Feel", "abandon": "%Abandonner"}

var app: Node
var partie: Node
var _voulu := "titre"
var _images := 0
var _fait := false

func _ready() -> void:
	if OS.get_environment("D666_DONNEES") == "":
		OS.set_environment("D666_DONNEES", DONNEES)
	# Profil d'essai neuf à chaque lancement : une capture ne dépend pas de la précédente.
	if OS.get_environment("D666_DONNEES") == DONNEES:
		for fichier in ["profil.json", "profil.json.bak", "reglages_jeu.json", "reglages_jeu.json.bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DONNEES.path_join(fichier)))
	if OS.get_environment("D666_RICHE") == "1":
		ProfilEssai.ecrire(ProfilEssai.riche(D6Data.create_tuning()))
	if OS.get_environment("D666_ECRAN") != "":
		_voulu = OS.get_environment("D666_ECRAN")
	app = App.new()
	app.name = "Principal"
	if OS.get_environment("D666_VUES") == "toutes":
		app.vues_voulues = []
	add_child(app)
	partie = app.partie
	_demarrer()

func _demarrer() -> void:
	if _voulu == "titre":
		return
	if _voulu == "victoire":
		app.demarrer_descente(Scenes.ETAGE_FINAL, false, false, GRAINE)
	else:
		app.demarrer_descente(1.0, _voulu == "mort_arene", false, GRAINE)
	var g: Dictionary = partie.game
	if Scenes.PORTES.has(_voulu):
		Scenes.entrer(g, _voulu)
	match _voulu:
		"marchand":
			Scenes.donner_or(g, OR_DU_MARCHAND)
		"fontaine", "mort":
			Scenes.benir(g, 2)
			Scenes.donner_or(g, OR_DU_MARCHAND)
			# D666_XP : autant d'ennemis tués avant de mourir (l'écran de mort montre l'expérience, le niveau gagné).
			for i in int(OS.get_environment("D666_XP")):
				D6Combat.kill_enemy(g, D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, {"spawnT": 0.0}))

func _process(_delta: float) -> void:
	var g = partie.game
	if g == null or _fait:
		return
	_images += 1
	if Scenes.PORTES.has(_voulu) or _voulu == "victoire":
		Scenes.avancer_vers_le_menu(g)
		_fait = g.mode != "play"
	elif _voulu.begins_with("mort"):
		Scenes.tuer_le_heros(g)
		_fait = true
	elif _images >= IMAGES_AVANT_PAUSE:
		_fait = _ouvrir_la_pause()

## Met en pause, puis presse le bouton de la pause qui mène à l'écran voulu.
func _ouvrir_la_pause() -> bool:
	if not partie.en_pause:
		app.mettre_en_pause(true)
		return _voulu == "pause"
	var ecrans = app.vues.get("ecrans")
	if ecrans == null or ecrans.ecran_montre() != "pause":
		return false
	ecrans.ecran().get_node(DEPUIS_LA_PAUSE[_voulu]).pressed.emit()
	return true
