extends Node
## Banc du lot Monde : la scène Monde seule, branchée sur une Partie démarrée à un étage choisi.
##   D666_ETAGE (défaut 1), D666_GRAINE (défaut 7) : la partie jouée.
##   D666_VITRINE=1 : la partie est figée et le banc y POSE un échantillon de tout ce que le Monde
##     sait dessiner (zones, télégraphes, tirs, portes, objets) pour le juger d'un coup d'œil.
##     C'est un outil d'essai : seul le banc écrit dans l'état, jamais une vue.
## Ce nœud joue aussi le rôle de `app` (reglages, profil, vues), comme jeu/principal.gd.
##   <godot> --path . --script res://outils/capture.gd -- res://jeu/monde/banc.tscn sortie.png 420 pilote

const Partie = preload("res://jeu/partie.gd")
const Monde = preload("res://jeu/monde/monde.tscn")
const Vitrine = preload("res://jeu/monde/banc_vitrine.gd")

var partie: Node
var reglages := {"sound": false, "haptics": false, "shake": 1.0, "lab": {}}
var profil := {}
var vues := {}

func _ready() -> void:
	partie = Partie.new()
	partie.name = "Partie"
	add_child(partie)
	var monde: Node = Monde.instantiate()
	add_child(monde)
	vues["monde"] = monde
	monde.brancher(self, partie)
	partie.demarrer({"seed": _nombre("D666_GRAINE", 7.0), "startFloor": _nombre("D666_ETAGE", 1.0)})
	if OS.get_environment("D666_VITRINE") != "":
		Vitrine.poser(partie.game, OS.get_environment("D666_VITRINE"))
		partie.en_pause = true

func _nombre(variable: String, defaut: float) -> float:
	var texte := OS.get_environment(variable)
	return float(texte) if texte.is_valid_float() else defaut
