extends Node
## Banc des COMPÉTENCES NEUVES (combat V3, étape 4) : le vrai jeu (jeu/principal.tscn, toutes ses
## vues) dans un vrai combat joué par le bot habile, les trois compétences neuves de la classe dans
## ses trois emplacements. Sert à JUGER À L'ÉCRAN : le banc enregistre lui-même une image à chaque
## instant qui compte, repéré par les ÉVÉNEMENTS de la simulation (ou par l'arc qui se bande), puis
## se ferme. OUTIL D'ESSAI : seul ce banc écrit dans l'état, jamais le jeu — les PV sont rendus à
## chaque image pour que le combat dure (pas le mode invulnérable, qui empêcherait de parer et de
## bloquer) ; et, parce que le bot esquive trop bien pour se faire toucher pendant une garde, le banc
## porte lui-même UN coup d'essai au héros peu après chaque garde levée (Contre-taille, Garde de
## fer), depuis l'ennemi le plus proche devant lui : la parade et le blocage que l'on voit sont
## ceux des règles, le coup qui les déclenche est celui du banc.
##   D666_CLASSE = revenant (défaut) | bourreau | chasseresse
##   D666_CHOIX  = améliorations prises, « nœud:amélioration,… » (défaut : aucune, tout au rang 1) ;
##                 chaque compétence nommée est alors au rang du choix
##   D666_NOM    = préfixe des images (défaut : la classe)
##   D666_ETAGE  = étage de départ (défaut 7) ; D666_GRAINE = graine (défaut 11)
##   D666_SORTIE = dossier des images (défaut _dev/captures/lot_v3_competences)
##   <godot> --position -3000,-3000 --resolution 1600x900 --path . res://jeu/essai/competences.tscn
## SANS --headless (il faut un vrai rendu). Expose `partie`, comme les autres bancs.

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const Bots = preload("res://outils/bots/bots.gd")
const Arbre = preload("res://sim/tree.gd")
const DONNEES := "user://essais"
const KITS := {"revenant": ["sillage", "sceau", "riposte"], "bourreau": ["faille", "hachette", "garde"], "chasseresse": ["proie", "leurre", "trait"]}
const DUREE_MAX := 4200 # images : le banc se ferme de toute façon
const CHARGE_VUE := 0.75 # part de la charge du Trait à laquelle l'arc bandé est pris en image
const COUPS_D_ESSAI := {"parryStart": 10, "guardStart": 34} # images entre la garde levée et le coup d'essai du banc
const COUP_D_ESSAI := 14.0 # dégâts du coup d'essai
## Les instants à montrer, par classe : [événement attendu (« type » ou « type:genre »), images
## après lui, nom de l'image]. Ceux d'une amélioration ne viennent que si elle est prise.
const INSTANTS := {
	"revenant": [
		["gadget:sillage", 45, "sillage_1_braises"], ["gadget:sillage", 130, "sillage_2_trainee"], ["explode:sillage", 3, "sillage_3_detonation"],
		["marked:stigmate", 10, "stigmate_1_marque"], ["explode:stigmate", 3, "stigmate_2_explosion"], ["explode:stigmate", 20, "stigmate_3_apres"],
		["parryStart", 5, "contre_taille_1_garde"], ["parry", 3, "contre_taille_2_parade"],
	],
	"bourreau": [
		["fissure", 3, "faille_1_fissure"], ["fissure", 24, "faille_2_apres"], ["fissure", 70, "faille_3_reste"],
		["skill:hachette", 14, "hache_1_aller"], ["axeTurn", 8, "hache_2_retour"], ["kitPulse:hache", 3, "hache_3_tournoiement"],
		["guardStart", 20, "garde_1_levee"], ["guardBlock", 3, "garde_2_bloque"], ["explode:garde", 3, "garde_3_contrecoup"],
	],
	"chasseresse": [
		["marked:proie", 12, "proie_1_marque"], ["markJump", 4, "proie_2_curee"], ["kitPulse:proie", 4, "proie_2_battue"],
		["allySpawn:leurre", 45, "leurre_1_pose"], ["allyHurt", 4, "leurre_2_encaisse"], ["explode:leurre", 3, "leurre_3_piege"],
		["charge", 0, "trait_1_arc_bande"], ["traitShot", 3, "trait_2_tir"],
	],
}

var app: Node
var partie: Node

var _classe := "revenant"
var _nom := ""
var _images := 0
var _temps := 0.0
var _mem := {}
var _attente: Array = [] # [images restantes, nom]
var _coups: Array = [] # images restantes avant chaque coup d'essai
var _vus := {}
var _reste := 0
var _sortie := ""

func _ready() -> void:
	# Un essai ne touche jamais au vrai profil ni aux vrais réglages du joueur (jeu/profil.gd).
	if OS.get_environment(Profil.ENV_DOSSIER) == "":
		OS.set_environment(Profil.ENV_DOSSIER, DONNEES)
	_classe = _env("D666_CLASSE", "revenant")
	_nom = _env("D666_NOM", _classe)
	_sortie = _env("D666_SORTIE", ProjectSettings.globalize_path("res://_dev/captures/lot_v3_competences"))
	DirAccess.make_dir_recursive_absolute(_sortie)
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	app.profil = _profil(_classe, _env("D666_CHOIX", ""))
	app.demarrer_descente(float(_env("D666_ETAGE", "7")), false, false, float(_env("D666_GRAINE", "11")))
	partie.entrees = _lire_bot
	partie.evenements.connect(_sur_evenements)
	_reste = INSTANTS[_classe].size()

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

## Profil d'essai : tout débloqué, la classe demandée, ses trois compétences neuves ; chaque
## amélioration demandée est prise, sa compétence au rang du choix.
func _profil(classe: String, choix: String) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = t[k].keys()
	m.loadout = {"classId": classe, "slots": KITS[classe]}
	m.equipment.arme = D6Profile.starter_weapon(t, t.classes[classe].weapons[0])
	m = D6Profile.sanitize_profile(m, t)
	var st: Dictionary = Arbre.state(m, classe)
	st.level = t.tree.maxLevel
	for paire in choix.split(",", false):
		var id: String = paire.get_slice(":", 0)
		st.ranks[id] = t.tree.choiceRank - 1.0 # le rang 1 est offert (tout est débloqué)
		st.choices[id] = paire.get_slice(":", 1)
	return m

func _lire_bot() -> Dictionary:
	var g: Dictionary = partie.game
	if g.mode == "choice":
		Bots.resolve_choice(g, "skilled")
	g.player.hp = g.player.maxHp # le combat dure : PV rendus (parer et bloquer restent possibles)
	return Bots.play("skilled", g, _mem)

## Clés sous lesquelles un événement est attendu : son type, et « type:genre » (le champ qui dit
## de quelle compétence il s'agit).
static func _cles(ev: Dictionary) -> Array:
	var out: Array = [ev.type]
	for champ in ["kind", "gadget", "skill", "mark"]:
		if ev.get(champ) is String:
			out.append("%s:%s" % [ev.type, ev[champ]])
	return out

## Le premier événement de chaque sorte attendue arme la prise des images qui en dépendent.
func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		if COUPS_D_ESSAI.has(ev.type):
			_coups.append(COUPS_D_ESSAI[ev.type])
		for cle in _cles(ev):
			_armer(cle)

## Le coup d'essai du banc : porté au héros depuis l'ennemi vivant le plus proche DEVANT lui (à
## défaut, d'un point devant lui), par le seul chemin qui blesse le héros.
func _coup_d_essai(g: Dictionary) -> void:
	var h: Dictionary = g.player
	var face := Vector2.from_angle(h.facing)
	var d_ou := Vector2(h.x, h.y) + face * 44.0
	var plus_pres := INF
	for e in g.enemies:
		var vers := Vector2(e.x - h.x, e.y - h.y)
		if not e.dead and e.spawnT <= 0.0 and vers.dot(face) > 0.0 and vers.length() < minf(plus_pres, 160.0):
			plus_pres = vers.length()
			d_ou = Vector2(e.x, e.y)
	h.iframes = 0.0
	D6Combat.damage_player(g, COUP_D_ESSAI, {"kind": "imp", "id": D6State.new_id(g), "x": d_ou.x, "y": d_ou.y})

func _armer(cle: String) -> void:
	if _vus.has(cle):
		return
	_vus[cle] = true
	for instant in INSTANTS[_classe]:
		if instant[0] == cle:
			_attente.append([instant[1], instant[2]])

## Les « images » du banc sont des soixantièmes de seconde RÉELS (la fenêtre d'essai peut rendre
## bien plus vite que 60 images par seconde) : un instant « 6 images après » reste 0,1 s après.
func _process(delta: float) -> void:
	_temps += delta * 60.0
	var g = partie.game
	if g != null and g.mode == "choice":
		Bots.resolve_choice(g, "skilled") # un menu ouvert arrête la partie : le bot le résout
	if g != null and g.mode == "play":
		for i in D6Loadout.SLOTS:
			if D6Loadout.slot_state(g, i).chargeFrac >= CHARGE_VUE:
				_armer("charge")
	var pas := int(_temps) - _images
	_images += pas
	for i in range(_coups.size() - 1, -1, -1):
		_coups[i] -= pas
		if _coups[i] <= 0 and g != null and g.mode == "play":
			_coups.remove_at(i)
			_coup_d_essai(g)
	for a in _attente.duplicate():
		a[0] -= pas
		if a[0] <= 0:
			_attente.erase(a)
			_enregistrer(a[1])
	if _reste <= 0 or _images >= DUREE_MAX:
		print("fin du banc : image %d, %d instant(s) non vus ; événements vus : %s" % [_images, _reste, ", ".join(_vus.keys())])
		get_tree().quit()

func _enregistrer(nom: String) -> void:
	await RenderingServer.frame_post_draw
	var chemin := "%s/%s_%s.png" % [_sortie, _nom, nom]
	get_viewport().get_texture().get_image().save_png(chemin)
	print("image : ", chemin)
	_reste -= 1
