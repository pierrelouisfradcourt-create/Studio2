extends Node
## Banc de la Ville : le VRAI programme principal (jeu/principal.gd, qui monte les vues
## présentes), ouvert sur la Ville, avec un profil d'essai. Pour se capturer :
##   D666_ONGLET=coffre D666_RICHE=1 <godot> --position -3000,-3000 --resolution 960x540 --path . \
##     --script res://outils/capture.gd -- res://jeu/ville/banc.tscn <sortie.png> 90
##   D666_ONGLET : portail | classe | armurerie | coffre | grimoire | sanctuaire | labo
##   D666_RICHE=1 : profil avancé (jeu/ville/profil_essai.gd) ; sinon un joueur qui n'a jamais joué.
##   D666_BAS=1 : la liste est défilée jusqu'en bas (pour voir la fin d'un onglet long).
##   D666_FOCUS=1 : le focus est posé sur le premier bouton actif de l'onglet (liseré de focus).
## Le banc écrit dans son propre dossier d'essai : jamais dans le vrai profil.

const Principal = preload("res://jeu/principal.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const ATTENTE_BAS := 20 # images avant de défiler (la mise en page doit être posée)

var app: Node
var partie: Node
var _images := 0

func _ready() -> void:
	var onglet := OS.get_environment("D666_ONGLET")
	if onglet == "":
		onglet = "portail"
	var riche := OS.get_environment("D666_RICHE") == "1"
	OS.set_environment("D666_DONNEES", "user://essais_ville/%s_%s" % ["riche" if riche else "neuf", onglet])
	ProfilEssai.effacer()
	if riche:
		ProfilEssai.ecrire(ProfilEssai.riche(D6Data.create_tuning()))
	app = Principal.new()
	app.name = "Principal"
	add_child(app)
	partie = app.partie
	app.ouvrir_ville()
	if app.vues.has("ville"):
		app.vues.ville.ouvrir_onglet(onglet)
	set_process(app.vues.has("ville"))

func _process(_delta: float) -> void:
	_images += 1
	if _images < ATTENTE_BAS:
		return
	set_process(false)
	var page: Control = app.vues.ville.page(app.vues.ville.onglet)
	if OS.get_environment("D666_BAS") == "1":
		var defilement: ScrollContainer = page.get_parent().get_parent()
		defilement.scroll_vertical = int(defilement.get_v_scroll_bar().max_value)
	if OS.get_environment("D666_FOCUS") == "1":
		for b in page.find_children("*", "Button", true, false):
			if not b.disabled:
				b.grab_focus()
				break
