extends Node
## Banc d'ASSEMBLAGE : le vrai jeu (jeu/principal.tscn, toutes ses vues), amené d'office à un
## écran choisi, pour le capturer avec outils/capture.gd.
##   D666_ECRAN = jeu (défaut) | titre | ville     D666_ETAGE, D666_GRAINE : la descente
## Expose `partie` (le pilote de capture.gd s'y branche).

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const DONNEES := "user://essais"

var app: Node
var partie: Node

func _ready() -> void:
	# Un essai ne touche jamais au vrai profil ni aux vrais réglages du joueur (jeu/profil.gd), même
	# lancé sans outils/capture.gd (scène ouverte seule, éditeur).
	if OS.get_environment(Profil.ENV_DOSSIER) == "":
		OS.set_environment(Profil.ENV_DOSSIER, DONNEES)
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	var ecran := OS.get_environment("D666_ECRAN")
	if ecran == "ville":
		app.ouvrir_ville()
	elif ecran != "titre":
		var etage := float(OS.get_environment("D666_ETAGE")) if OS.get_environment("D666_ETAGE") != "" else 1.0
		var graine := float(OS.get_environment("D666_GRAINE")) if OS.get_environment("D666_GRAINE") != "" else 7.0
		app.demarrer_descente(etage, false, false, graine)
