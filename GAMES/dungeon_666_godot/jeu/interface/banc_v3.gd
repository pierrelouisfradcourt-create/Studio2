extends Node
## Banc des COMMANDES du combat V3 : le VRAI jeu (jeu/principal.gd, toutes ses vues, la vraie vue
## Entrees), figé dans un état choisi, pour capturer chaque état des boutons avec outils/capture.gd :
##   D666_APPAREIL=tactile D666_JAUGE=0.5 <godot> --position -3000,-3000 --resolution 1600x720 \
##     --path . --script res://outils/capture.gd -- res://jeu/interface/banc_v3.tscn <sortie.png> 150
##   D666_APPAREIL : tactile (défaut) | clavier | manette
##   D666_CLASSE   : revenant (défaut) | bourreau | chasseresse
##   D666_JAUGE    : jauge d'ultime, 0..1 (défaut 0)
##   D666_MAINTIEN : avancement du maintien qui lance l'ultime, 0..1 (jauge pleine)
##   D666_RECHARGE : part de recharge RESTANTE de l'emplacement 1, 0..1 (0 = prêt)
##   D666_CHARGES  : charges restantes du premier emplacement à charges
##   D666_VIDE=1   : l'emplacement 3 est vide (sinon les trois sont remplis)
##   D666_GESTE    : attaque (le pouce glisse sur l'attaque) | competence1..3 (il glisse sur
##                   l'emplacement) | tenir (il tient l'attaque)
##   D666_MANCHE=0 : au doigt, le pouce gauche ne tient pas le joystick
##   D666_DENSITE  : densité d'écran simulée (défaut 1 : celle du bureau). Un téléphone de
##                   1600 × 720 points a une densité proche de 1,7 : ses boutons gardent leur
##                   taille sous le pouce, donc sont plus gros en points qu'à densité 1.
## La partie tourne un instant (les démons apparaissent), puis la simulation est ARRÊTÉE : l'état
## posé ne bouge plus. Le banc écrit dans son propre dossier d'essai, jamais dans le vrai profil.
## Comme tout banc, il est le seul ici à poser des situations dans `game` ; les vues ne font que lire.

const Principal = preload("res://jeu/principal.gd")
const Profil = preload("res://jeu/profil.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const Consignes = preload("res://jeu/interface/consignes.gd")
const DONNEES := "user://essais_v3_affichage/banc"
const GRAINE := 7.0
const POSE := 45 # images de jeu avant de figer (les démons sont apparus)
const GLISSE := Vector2(-52.0, -34.0) # px CSS : où le pouce a glissé depuis le centre du bouton
const POUCE_GAUCHE := Vector2(0.16, 0.68) # où le pouce gauche tient le joystick (parts de l'écran)
const GESTES := {"attaque": "attack", "tenir": "attack", "competence1": "skill1", "competence2": "skill2", "competence3": "skill3"}

var app: Node
var partie: Node
var _images := 0

func _ready() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	ProfilEssai.effacer()
	var tuning: Dictionary = D6Data.create_tuning()
	ProfilEssai.ecrire(_profil(tuning))
	# Le joueur d'essai a tout appris (aucune consigne) ; son et vibrations coupés.
	var reglages: Dictionary = Profil.REGLAGES_DEFAUT.duplicate(true)
	reglages.sound = false
	reglages.haptics = false
	reglages.accueil.acquis = Consignes.ids()
	Profil.enregistrer_reglages(reglages)
	app = Principal.new()
	app.name = "Principal"
	add_child(app)
	partie = app.partie
	app.demarrer_descente(1.0, false, false, GRAINE)
	partie.game.godMode = true

func _env(nom: String, defaut: String = "") -> String:
	var v := OS.get_environment(nom)
	return v if v != "" else defaut

## Profil d'essai : la classe voulue, toutes ses actions possédées, trois emplacements remplis
## (une compétence, une action à charges, une autre compétence) ou le troisième vide.
func _profil(tuning: Dictionary) -> Dictionary:
	var p: Dictionary = ProfilEssai.riche(tuning)
	var id := _env("D666_CLASSE", "revenant")
	var c: Dictionary = tuning.classes[id]
	D6Profile.select_class(p, tuning, id)
	p.souls = ProfilEssai.AMES_LARGES
	for genre in ["skills", "gadgets"]:
		for action in c[genre]:
			D6Profile.unlock(p, tuning, genre, action)
	var voulus: Array = [c.skills[0], c.gadgets[0], null if _env("D666_VIDE") == "1" else c.skills[1]]
	for i in voulus.size():
		D6Profile.select_slot(p, tuning, float(i), null)
	for i in voulus.size():
		D6Profile.select_slot(p, tuning, float(i), voulus[i])
	return p

func _process(_delta: float) -> void:
	_images += 1
	if _images != POSE or partie.game == null:
		return
	partie.set_process(false) # la simulation s'arrête : l'état posé reste
	_poser_appareil(_env("D666_APPAREIL", "tactile"))
	_poser_etat(partie.game)
	_poser_geste.call_deferred(_env("D666_GESTE"))

func _poser_appareil(nom: String) -> void:
	if nom == "tactile":
		var entrees: Control = app.vues.entrees
		entrees._tactile_actif = true
		var densite := float(_env("D666_DENSITE", "1"))
		entrees._doigts.disposer(entrees.get_viewport_rect().size, entrees._marges_sures(), entrees._unites_par_pixel() * densite)
	elif nom == "manette":
		app.vues.hud.montrer_peripherique("manette")

func _poser_etat(g: Dictionary) -> void:
	var p: Dictionary = g.player
	p.superCharge = clampf(float(_env("D666_JAUGE", "0")), 0.0, 1.0)
	p.superHold = float(_env("D666_MAINTIEN", "0")) * g.tuning["super"].holdTime
	var recharge := float(_env("D666_RECHARGE", "0"))
	for i in D6Loadout.SLOTS:
		var vue = D6Loadout.slot_view(g, i)
		if vue == null:
			continue
		if vue.charges == null and i == 0 and recharge > 0.0:
			p.slots[i].cd = recharge * D6Loadout.slot_def(g, i).cooldown * p.stats.skillCooldownMult
		elif vue.charges != null and _env("D666_CHARGES") != "":
			p.slots[i].charges = float(_env("D666_CHARGES"))

## Le geste est fait par de VRAIS événements de doigt, reçus par la vraie vue Entrees. Au doigt,
## le pouce gauche tient toujours le joystick (D666_MANCHE=0 pour l'ôter).
func _poser_geste(geste: String) -> void:
	if not app.vues.entrees.tactile():
		return
	var taille := get_viewport().get_visible_rect().size
	var k: float = app.vues.entrees._doigts.echelle
	if _env("D666_MANCHE", "1") == "1":
		var base := taille * POUCE_GAUCHE
		_doigt(1, base, true)
		_glisser(1, base + Vector2(34.0, -20.0) * k)
	var id: String = GESTES.get(geste, "")
	for b in app.vues.entrees.interface_tactile().buttons:
		if b.id != id:
			continue
		_doigt(2, Vector2(b.x, b.y), true)
		if geste != "tenir":
			_glisser(2, Vector2(b.x, b.y) + GLISSE * k)

func _doigt(index: int, p: Vector2, pose: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = p
	ev.pressed = pose
	get_viewport().push_input(ev, true)

func _glisser(index: int, p: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = p
	get_viewport().push_input(ev, true)
