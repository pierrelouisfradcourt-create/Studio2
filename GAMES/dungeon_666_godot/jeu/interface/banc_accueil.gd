extends Node
## Banc de l'ACCUEIL du premier joueur : le VRAI jeu (jeu/principal.gd, toutes ses vues), amené
## devant UNE consigne, pour la capturer en situation avec outils/capture.gd :
##   D666_CONSIGNE=rouge D666_APPAREIL=tactile <godot> --position -3000,-3000 --resolution 1280x720 \
##     --path . --script res://outils/capture.gd -- res://jeu/interface/banc_accueil.tscn <sortie.png> 240
##   D666_CONSIGNE : bouger | attaquer | dash | rouge | competence | gadget | super | recompense |
##                   porte | mort (une consigne de jeu/interface/consignes.gd) ;
##                   pause (l'écran de pause et ses deux réglages) ;
##                   armurerie | grimoire | classe (l'onglet de la Ville, pour les textes accordés)
##   D666_APPAREIL : clavier (défaut) | manette | tactile
##   D666_CLASSE   : revenant (défaut) | bourreau | chasseresse
##   D666_BAS=1    : l'onglet de la Ville est défilé jusqu'en bas
## Le banc écrit dans son propre dossier d'essai, jamais dans le vrai profil. Comme tout banc, il
## est le seul ici à poser des situations dans `game` ; la vue Accueil, elle, ne fait que lire.

const Principal = preload("res://jeu/principal.gd")
const Profil = preload("res://jeu/profil.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const Consignes = preload("res://jeu/interface/consignes.gd")
const DONNEES := "user://essais_accueil_banc"
const GRAINE := 7.0
const ONGLETS := ["armurerie", "grimoire", "classe"]
const POSE := 3 # images avant de poser la situation (les vues sont branchées)
const BAS := 20 # images avant de défiler un onglet de la Ville jusqu'en bas (D666_BAS=1)

var app: Node
var partie: Node
var _voulue := ""
var _images := 0

func _ready() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	_voulue = _env("D666_CONSIGNE", "bouger")
	ProfilEssai.effacer()
	var tuning: Dictionary = D6Data.create_tuning()
	var profil: Dictionary = ProfilEssai.riche(tuning)
	D6Profile.select_class(profil, tuning, _env("D666_CLASSE", "revenant"))
	ProfilEssai.ecrire(profil)
	# Le joueur d'essai a tout appris, sauf la consigne voulue ; son et vibrations coupés.
	var reglages: Dictionary = Profil.REGLAGES_DEFAUT.duplicate(true)
	reglages.sound = false
	reglages.haptics = false
	reglages.accueil.acquis = Consignes.ids().filter(func(id: String) -> bool: return id != _voulue)
	Profil.enregistrer_reglages(reglages)
	app = Principal.new()
	app.name = "Principal"
	add_child(app)
	partie = app.partie
	if _voulue in ONGLETS:
		app.ouvrir_ville()
		app.vues.ville.ouvrir_onglet(_voulue)
	else:
		app.demarrer_descente(1.0, false, false, GRAINE)

func _env(nom: String, defaut: String = "") -> String:
	var v := OS.get_environment(nom)
	return v if v != "" else defaut

func _process(_delta: float) -> void:
	_images += 1
	if _images == BAS and _voulue in ONGLETS and _env("D666_BAS") == "1":
		var defilement: ScrollContainer = app.vues.ville.page(_voulue).get_parent().get_parent()
		defilement.scroll_vertical = int(defilement.get_v_scroll_bar().max_value)
	if _images != POSE or partie.game == null:
		return
	_poser_appareil(_env("D666_APPAREIL", "clavier"))
	_poser(partie.game)

func _poser_appareil(nom: String) -> void:
	if nom == "tactile":
		app.vues.entrees._tactile_actif = true
	elif nom == "manette":
		app.vues.hud.montrer_peripherique("manette")

func _poser(g: Dictionary) -> void:
	g.godMode = true
	match _voulue:
		"rouge":
			D6Combat.spawn_hazard(g, {"shape": "circle", "x": g.player.x + 150.0, "y": g.player.y - 30.0, "r": 95.0, "delay": 6.0, "damage": 1.0, "kind": "essai"})
		"super":
			g.player.superCharge = 1.0
		"mort":
			g.telemetry.deaths = 1.0
		"recompense":
			_salle_nettoyee(g, false)
		"porte":
			_salle_nettoyee(g, true)
		"pause":
			app.mettre_en_pause(true)

## Salle vaincue : la récompense au milieu (portes closes), ou déjà prise (portes ouvertes).
func _salle_nettoyee(g: Dictionary, prise: bool) -> void:
	g.enemies.clear()
	g.spawns.clear()
	g.room.cleared = true
	D6Room.make_doors(g, [{"reward": "boon", "family": "colere"}, {"reward": "loot"}])
	for d in g.room.doors:
		d.open = prise
	g.room.interact = {"kind": "boon", "x": g.room.w / 2.0, "y": 300.0, "r": g.tuning.room.rewardRadius, "used": prise, "family": "luxure"}
	g.player.x = g.room.w / 2.0 + 120.0
	g.player.y = 250.0 if prise else 430.0 # portes ouvertes : le héros est monté, on les voit
