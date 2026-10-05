extends SceneTree
## Test headless de l'accueil du premier joueur (0 = vert) :
##   <godot> --headless --path . --script res://jeu/interface/test_accueil.gd
## Le vrai `principal.gd` (jeu/ecrans/banc_app.gd), le vrai HUD, les vrais écrans, la vraie
## simulation, avancée ici pas à pas (1/60 s) avec de vraies entrées de jeu. Chaque consigne :
## elle apparaît à sa condition, s'efface au geste, est retenue sur le disque d'essai et ne
## revient pas ; son libellé suit l'appareil ; rien en arène ni à l'entraînement ; le réglage de
## la pause la coupe et la fait revoir. Un essai ne touche jamais le vrai profil (D666_DONNEES).
## Comme tout banc, ce test a le droit de poser des situations dans `game` ; la vue, jamais.

const App = preload("res://jeu/ecrans/banc_app.gd")
const Profil = preload("res://jeu/profil.gd")
const Consignes = preload("res://jeu/interface/consignes.gd")
const Fondus = preload("res://jeu/essai/fondus.gd")
const DONNEES := "user://essais_accueil"
const GRAINE := 7.0
const DT := 1.0 / 60.0
const FONDU := 40 # pas : plus que le temps d'un fondu (0,25 s)
const ATTENTE := 400 # pas : borne d'une attente
const PEU := 5 # pas : le temps qu'un pas de simulation passe
const LOIN := 400.0

var app: Node
var hud: Node
var accueil: Node
var echecs := 0
var verifications := 0
var _entree: Dictionary = {}

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	_derouler.call_deferred()

func _derouler() -> void:
	await _nouvelle_app(true)
	_reglages_neufs()
	_descendre()
	_bouger()
	_attaquer_et_dasher()
	_rouge()
	_terrain()
	_competence_et_gadget()
	_super()
	_commandes_v3()
	_deplacement_de_classe()
	_retours_du_bureau()
	await _recompense_et_porte()
	await _mort()
	await _jamais_deux_fois()
	await _arene_et_entrainement()
	await _couper_et_revoir()
	await _progression()
	await _etat_des_neuves()
	print("test_accueil : %d vérifications, %d échec(s)" % [verifications, echecs])
	print("ACCUEIL : OK" if echecs == 0 else "ACCUEIL : ÉCHEC")
	await Fondus.laisser_finir(self)
	app.free()
	quit(1 if echecs > 0 else 0)

# ---------------------------------------------------------------- outils

func verifier(nom: String, ok: bool, detail = "") -> void:
	verifications += 1
	if not ok:
		echecs += 1
		print("ÉCHEC  ", nom, "  ", detail)

func _effacer() -> void:
	for fichier in ["profil.json", "profil.json.bak", "reglages_jeu.json", "reglages_jeu.json.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DONNEES.path_join(fichier)))

## Une application neuve (le disque d'essai est relu). Partie, HUD et bannière n'avancent plus
## seuls : c'est `_pas()` qui les fait avancer, d'un soixantième de seconde à la fois.
func _nouvelle_app(disque_vierge: bool) -> void:
	if app != null:
		await Fondus.laisser_finir(self)
		app.free()
	if disque_vierge:
		_effacer()
	app = App.new()
	app.vues_voulues = ["hud", "ecrans"]
	app.fausses_entrees = true
	root.add_child(app)
	hud = app.vues.hud
	accueil = hud.accueil
	app.partie.entrees = _lire
	for n in [app.partie, hud, hud.banniere]:
		n.set_process(false)
	await process_frame

func _game() -> Dictionary:
	return app.partie.game

## L'entrée du prochain pas ; les fronts (…Pressed) ne valent qu'un pas.
func _lire() -> Dictionary:
	var f: Dictionary = D6Game.empty_input()
	f.merge(_entree, true)
	for cle in _entree.keys():
		if cle.ends_with("Pressed"):
			_entree.erase(cle)
	return f

func _pas(n: int = 1) -> void:
	for i in n:
		app.partie._process(DT)
		hud.banniere._process(DT)
		hud._process(DT)

func _jusqu_a(condition: Callable, borne: int = ATTENTE) -> bool:
	for i in borne:
		if condition.call():
			return true
		_pas()
	return condition.call()

func _montree(id: String) -> bool:
	return _jusqu_a(func() -> bool: return accueil.montree() == id and accueil.modulate.a >= 1.0)

func _sur_disque() -> Array:
	return Profil.charger_reglages().accueil.acquis

func _appareil(nom: String) -> void:
	app.vues.entrees.est_tactile = nom == "tactile"
	if nom != "tactile":
		hud.montrer_peripherique(nom)
	_pas()

## Geste fait : la consigne est acquise, écrite sur le disque, et s'efface de l'écran.
func _acquise(id: String) -> void:
	verifier(id + " : acquise au geste", _jusqu_a(func() -> bool: return accueil.est_acquise(id), 120))
	verifier(id + " : retenue sur le disque", _sur_disque().has(id), _sur_disque())
	verifier(id + " : s'efface", _jusqu_a(func() -> bool: return accueil.montree() != id, FONDU), accueil.montree())

## La consigne `id` est à l'écran avec sa phrase, et son libellé suit l'appareil en main.
func _libelles(id: String, phrases: Dictionary, commande: String) -> void:
	for nom in ["clavier", "manette", "tactile", "clavier"]:
		_appareil(nom)
		var attendu: String = hud.libelles().get(commande, "")
		verifier("%s (%s) : phrase" % [id, nom], accueil.phrase() == phrases[nom], accueil.phrase())
		verifier("%s (%s) : libellé « %s »" % [id, nom, attendu], accueil.libelle() == attendu and (attendu != "") == (nom != "tactile" and commande != ""), accueil.libelle())
		if commande != "" and commande != "move":
			verifier("%s (%s) : le bouton de la commande bat, lui seul" % [id, nom], _designees(nom == "tactile") == [commande], _designees(nom == "tactile"))

## Les commandes désignées (anneau qui bat) dans la présentation en cours.
func _designees(au_doigt: bool) -> Array:
	var boutons: Array = hud.tactile.get_children() if au_doigt else hud.commandes_bureau
	return boutons.filter(func(b: Node) -> bool: return b._designee).map(func(b: Node) -> String: return b.id)

func _trois(phrase: String) -> Dictionary:
	return {"clavier": phrase, "manette": phrase, "tactile": phrase}

## Une salle où il ne se passe rien : plus d'ennemis, plus de vagues, le héros ne craint rien.
func _calmer() -> void:
	var g := _game()
	g.godMode = true
	g.enemies.clear()
	g.spawns.clear()
	g.projectiles.clear()
	g.hazards.clear()
	g.room.kind = "essai"

# ---------------------------------------------------------------- retours de progression (écran de l'arbre)

func _tuer(n: int) -> void:
	var g := _game()
	for i in n:
		D6Combat.kill_enemy(g, D6Enemies.create_enemy(g, "imp", g.player.x + LOIN, g.player.y, {"spawnT": 0.0}))

func _arbre_lu() -> Dictionary:
	var g := _game()
	return D6Profile.tree_view(g.meta, g.tuning, g.meta.loadout.classId)

## La barre d'expérience sous la vie suit l'état ; un niveau passé en pleine descente montre le
## bandeau de niveau (petit, sous la vie, hors du centre), fait briller la barre, puis s'efface seul.
func _progression() -> void:
	await _nouvelle_app(true)
	_reglages_neufs()
	app.demarrer_descente(1.0, false, false, GRAINE)
	_calmer()
	_pas(PEU)
	await process_frame # la mise en page du HUD se pose (les conteneurs se rangent à l'image suivante)
	await process_frame
	var v0 := _arbre_lu()
	verifier("xp : la barre est montrée sous la vie, à la part lue dans l'état", hud.experience.is_visible_in_tree() and is_equal_approx(hud.barre_xp.part(), v0.xp / v0.xpNext) and hud.niveau_classe.text == "NIV. %s" % D6Js.num_str(v0.level), [hud.barre_xp.part(), hud.niveau_classe.text])
	verifier("xp : elle tient sous la barre de vie, de sa largeur", hud.experience.get_global_rect().position.y >= hud.vie.get_global_rect().end.y and is_equal_approx(hud.experience.size.x, hud.vie.size.x), [hud.experience.get_global_rect(), hud.vie.get_global_rect()])
	verifier("niveau : aucun bandeau tant qu'aucun niveau n'est passé", hud.niveau.texte() == "" and not hud.niveau.visible)
	_tuer(3)
	_pas(PEU)
	var v1 := _arbre_lu()
	verifier("xp : la barre suit l'expérience gagnée", v1.xp > v0.xp and v1.level == v0.level and is_equal_approx(hud.barre_xp.part(), v1.xp / v1.xpNext), [v0.xp, v1.xp, hud.barre_xp.part()])
	verifier("niveau : toujours aucun bandeau", hud.niveau.texte() == "")
	var borne := 500
	while _arbre_lu().level == v1.level and borne > 0:
		_tuer(1)
		borne -= 1
	_pas(PEU)
	var v2 := _arbre_lu()
	var attendu := "NIVEAU %s · +1 point" % D6Js.num_str(v2.level)
	verifier("niveau : un niveau est passé, un point de plus", v2.level == v1.level + 1.0 and v2.points == v1.points + 1.0, [v2.level, v2.points])
	verifier("niveau : le bandeau dit « %s »" % attendu, hud.niveau.visible and hud.niveau.texte() == attendu, hud.niveau.texte())
	verifier("niveau : la barre brille et repart au niveau suivant", hud.barre_xp.brille() and is_equal_approx(hud.barre_xp.part(), v2.xp / v2.xpNext) and hud.niveau_classe.text == "NIV. %s" % D6Js.num_str(v2.level), [hud.barre_xp.part(), hud.niveau_classe.text])
	await process_frame
	_pas(FONDU) # le bandeau a fini d'apparaître
	var bandeau: Rect2 = hud.niveau.get_global_rect()
	verifier("niveau : sous la barre d'expérience, dans la bande du haut (jamais sur le combat), à côté du bloc de l'étage, hors de toute bannière", bandeau.position.y >= hud.experience.get_global_rect().end.y and bandeau.end.y <= hud.bande.get_global_rect().end.y and bandeau.end.x <= hud.centre.get_global_rect().position.x and not bandeau.intersects(hud.banniere.get_global_rect()), [bandeau, hud.centre.get_global_rect(), hud.bande.get_global_rect()])
	verifier("niveau : les losanges des bénédictions s'effacent le temps qu'il passe", hud.benedictions.modulate.a < 0.1, hud.benedictions.modulate.a)
	verifier("niveau : il ne prend aucun toucher", hud.niveau.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	verifier("niveau : il s'efface seul, les bénédictions reviennent", _jusqu_a(func() -> bool: return not hud.niveau.visible, 300) and hud.benedictions.modulate.a == 1.0, hud.benedictions.modulate.a)
	app.demarrer_descente(1.0, true, false, GRAINE)
	_pas(PEU)
	verifier("arène d'essai : ni barre d'expérience ni bandeau (rien n'y est gagné)", not hud.experience.visible and not hud.niveau.visible)

## Compétences neuves : ce qu'une action fait EN CE MOMENT se lit sur son bouton. L'état du bouton
## reprend D6Loadout.slot_state tel quel (charge qui monte, durée qui reste), sans rien calculer.
func _etat_des_neuves() -> void:
	await _nouvelle_app(true)
	_reglages_neufs()
	app.demarrer_descente(1.0, false, false, GRAINE)
	_calmer()
	var Etats: GDScript = load("res://jeu/interface/etat_commandes.gd")
	var g := _game()
	_pas(PEU)
	var repos: Dictionary = Etats.etat(g, "skill2")
	verifier("neuves : au repos, ni charge ni durée sur le bouton", repos.charge == 0.0 and repos.duree == 0.0 and not D6Loadout.slot_state(g, 1).active, repos)
	g.kit.slots[1] = "sillage" # le banc pose la situation : le Sillage dans l'emplacement 2
	g.player.slots[1].charges = 2.0
	_pas()
	_entree = {"skill2Pressed": true}
	_pas(PEU)
	var lu: Dictionary = D6Loadout.slot_state(g, 1)
	var e: Dictionary = Etats.etat(g, "skill2")
	verifier("neuves : le Sillage lancé, son effet dure (slot_state.active)", lu.active and lu.activeFrac > 0.0, lu)
	verifier("neuves : le bouton montre la part qui reste, celle des règles", e.duree == lu.activeFrac and e.charge == 0.0, [e, lu])
	_pas(30)
	var plus_tard: Dictionary = Etats.etat(g, "skill2")
	verifier("neuves : l'anneau de durée se vide avec le temps", plus_tard.duree < e.duree and plus_tard.duree == D6Loadout.slot_state(g, 1).activeFrac, [e.duree, plus_tard.duree])
	hud._process(DT)
	verifier("neuves : les autres boutons n'en montrent rien", Etats.etat(g, "skill1").duree == 0.0 and Etats.etat(g, "skill1").charge == 0.0)

# ---------------------------------------------------------------- les consignes, une à une

func _reglages_neufs() -> void:
	var a: Dictionary = app.reglages.accueil
	verifier("réglages neufs : consignes actives, aucune acquise", a.actif == true and a.acquis.is_empty(), a)
	verifier("la table : onze consignes, identifiants uniques", Consignes.TABLE.size() == 11 and Consignes.ids().size() == 11, Consignes.ids())

func _descendre() -> void:
	app.demarrer_descente(1.0, false, false, GRAINE)
	_calmer()
	_pas()
	verifier("entrée d'étage : la bannière parle, la consigne attend", hud.banniere.visible and accueil.montree() == "", accueil.montree())

func _bouger() -> void:
	verifier("bouger : apparaît dès que la bannière s'efface", _montree("bouger"), accueil.montree())
	_pas(180)
	verifier("bouger : reste tant que le joueur ne bouge pas", accueil.montree() == "bouger" and not accueil.est_acquise("bouger"))
	_libelles("bouger", {"clavier": "Déplace-toi", "manette": "Déplace-toi", "tactile": "Glisse le pouce gauche pour bouger"}, "move")
	verifier("bouger : la manette dit « Stick gauche »", hud.TOUCHES.manette.move == "Stick gauche")
	_entree = {"moveX": 1.0}
	_acquise("bouger")
	_entree = {}

func _attaquer_et_dasher() -> void:
	verifier("attaquer : apparaît ensuite", _montree("attaquer"), accueil.montree())
	_libelles("attaquer", _trois("Frappe les démons"), "attack")
	_entree = {"attackPressed": true}
	_acquise("attaquer")
	verifier("dash : apparaît ensuite", _montree("dash"), accueil.montree())
	_libelles("dash", _trois("Dashe à travers les attaques"), "dash")
	_entree = {"dashPressed": true}
	_acquise("dash")
	verifier("un dash hors de tout danger n'apprend pas « esquive le rouge »", not accueil.est_acquise("rouge"))
	_pas(FONDU)
	verifier("salle vide : plus rien à dire, aucune consigne", accueil.montree() == "" and not accueil.visible, accueil.montree())
	verifier("aucune commande ne bat", _designees(false).is_empty())

func _rouge() -> void:
	var g := _game()
	var zone: Dictionary = D6Combat.spawn_hazard(g, {"shape": "circle", "x": g.player.x + LOIN, "y": g.player.y, "r": 60.0, "delay": 60.0, "damage": 1.0, "kind": "essai"})
	verifier("rouge : apparaît à la première attaque télégraphiée", _montree("rouge"), accueil.montree())
	_libelles("rouge", _trois("Esquive le rouge : dashe"), "dash")
	g.player.dashCharges = 1.0
	_entree = {"dashPressed": true}
	_acquise("rouge")
	zone.done = true

## Terrain à franchir : la consigne paraît près d'une rivière, nomme le geste de la classe, et
## n'est acquise que lorsque le héros en a FRANCHI une (D6Player.crossing + D6Physics.low_at).
func _terrain() -> void:
	var g := _game()
	var p: Dictionary = g.player
	var c: Dictionary = Consignes.trouver("terrain")
	_pas(FONDU)
	verifier("terrain : rien dans une salle sans rivière ni obstacle bas", not Consignes.quand("terrain_proche", g) and accueil.montree() != "terrain", accueil.montree())
	p.x = g.room.w * 0.3
	p.y = g.room.h * 0.5
	var depart := Vector2(p.x, p.y)
	var riviere := {"x0": p.x + 50.0, "y0": p.y - 150.0, "x1": p.x + 110.0, "y1": p.y + 150.0, "kind": "river"}
	g.room.low = [riviere]
	verifier("terrain : apparaît près d'une rivière", _montree("terrain"), accueil.montree())
	_libelles("terrain", _trois("Franchis la rivière d'un dash"), "dash")
	riviere.kind = "barrier"
	verifier("terrain : un obstacle bas est nommé", Consignes.texte(c, "clavier", g) == "Franchis l'obstacle d'un dash", Consignes.texte(c, "clavier", g))
	riviere.kind = "river"
	g.player.dashCharges = 2.0
	_entree = {"moveY": 1.0, "dashPressed": true} # un dash LE LONG de la rivière ne franchit rien
	_pas(30)
	verifier("terrain : un dash qui ne franchit rien n'apprend rien", not accueil.est_acquise("terrain"))
	p.x = depart.x
	p.y = depart.y
	g.player.dashCharges = 2.0
	_entree = {"moveX": 1.0, "dashPressed": true}
	_acquise("terrain")
	verifier("terrain : le héros est de l'autre côté de la rivière", p.x > riviere.x1, [p.x, riviere.x1])
	_entree = {}
	g.room.low = []
	_pas(PEU)

func _competence_et_gadget() -> void:
	var g := _game()
	verifier("compétence : rien sans ennemi", not Consignes.quand("competence_prete", g))
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x - LOIN, g.player.y, {})
	e.spawnT = 0.0
	verifier("compétence : apparaît au combat", _montree("competence"), accueil.montree())
	_libelles("competence", {"clavier": "Lance une compétence", "manette": "Lance une compétence", "tactile": "Compétence : glisse pour viser, relâche"}, "skill1")
	_entree = {"skill1Pressed": true}
	_acquise("competence")
	verifier("gadget : apparaît ensuite", _montree("gadget"), accueil.montree())
	_libelles("gadget", _trois("Utilise une compétence à charges"), "skill2")
	_entree = {"skill2Pressed": true}
	_acquise("gadget")
	_calmer()

func _super() -> void:
	var g := _game()
	_pas(FONDU)
	verifier("Super : rien tant que la jauge n'est pas pleine", accueil.montree() == "", accueil.montree())
	g.player.superCharge = 1.0
	verifier("Super : apparaît quand la jauge est pleine", _montree("super"), accueil.montree())
	_libelles("super", _trois("Jauge pleine : garde le bouton d'attaque appuyé"), "attack")
	_entree = {"attack": true}
	_acquise("super")
	_jusqu_a(func() -> bool: return g.player.state == "free")

## Combat V3 : le HUD montre les trois emplacements (lus par D6Loadout.slot_view), ne plante pas
## sur un emplacement vide, et le bouton d'attaque porte la jauge d'ultime et son maintien.
func _commandes_v3() -> void:
	const Etats = preload("res://jeu/interface/etat_commandes.gd")
	var g := _game()
	var ids: Array = hud.commandes_bureau.map(func(c: Node) -> String: return c.id)
	verifier("HUD : attaque, dash et les trois emplacements", ids == ["attack", "dash", "skill1", "skill2", "skill3"], ids)
	verifier("HUD tactile : les mêmes cinq commandes", hud.tactile.get_children().map(func(c: Node) -> String: return c.id) == ["attack", "dash", "skill1", "skill2", "skill3"])
	_forme_puis_origine(Etats)
	verifier("profil neuf : compétence, gadget, emplacement vide", g.kit.slots[0] != null and g.kit.slots[1] != null and g.kit.slots[2] == null, g.kit.slots)
	var vide: Dictionary = Etats.etat(g, "skill3")
	verifier("emplacement vide : pas prêt, pas de pictogramme, et le HUD continue de tourner", vide.get("vide") == true and vide.pret == 0.0 and vide.icone == "", vide)
	var competence: Dictionary = Etats.etat(g, "skill1")
	var gadget: Dictionary = Etats.etat(g, "skill2")
	verifier("emplacement 1 : la compétence, son anneau de recharge", competence.get("recharge") == true and competence.icone == "skill", competence)
	verifier("emplacement 2 : le gadget, ses charges", gadget.get("max", 0.0) >= 1.0 and gadget.charges <= gadget.max and gadget.icone == "gadget", gadget)
	# L'ultime ne s'arme que si l'appui COMMENCE jauge pleine (règle de sim/player.gd) : on relâche
	# d'abord l'attaque restée tenue depuis l'essai du Super, puis on rappuie.
	_entree = {}
	_pas(2)
	g.player.superCharge = 1.0
	_entree = {"attack": true}
	_pas(12)
	var attaque: Dictionary = Etats.etat(g, "attack")
	verifier("bouton d'attaque : jauge d'ultime pleine, le maintien monte", attaque.jauge == 1.0 and attaque.eclat and attaque.maintien > 0.2 and attaque.maintien < 1.0, attaque)
	_entree = {}
	_pas(2)
	verifier("attaque relâchée : le maintien retombe à zéro, la jauge reste pleine", Etats.etat(g, "attack").maintien == 0.0 and g.player.superCharge == 1.0)
	g.player.superCharge = 0.0
	for appareil in ["tactile", "manette", "clavier"]:
		_appareil(appareil)
		_pas(3)
	verifier("les trois présentations se dessinent avec un emplacement vide", true)
	_jauge_et_visee_v3(Etats)

## Combat V3, étape 2 : l'essai de l'ultime (au-dessus) a lancé la FORME DU DAMNÉ du Revenant, qui
## dure. Pendant la forme, le HUD montre les trois ACTIONS DE FORME (pictogrammes connus, recharge,
## aucune n'est vide) et le bouton d'attaque porte la minuterie (jauge qui n'est plus pleine) ; puis
## la forme finit, et les vérifications d'origine jugent les emplacements d'ORIGINE, comme avant.
func _forme_puis_origine(Etats: GDScript) -> void:
	const Icones = preload("res://jeu/interface/icones.gd")
	var g := _game()
	var s: Dictionary = g.tuning["super"]
	verifier("l'essai de l'ultime a lancé la Forme du Damné, encore en cours", D6KitSupers.form_of(g) != null and s.kind == "forme", [s.kind, g.player.get("ult")])
	for i in 3:
		var action: Dictionary = s.actions[s.slots[i]]
		var e: Dictionary = Etats.etat(g, "skill%d" % (i + 1))
		verifier("forme : l'emplacement %d montre « %s » (pictogramme « %s », recharge)" % [i + 1, action.name, action.icon], e.get("recharge") == true and not e.has("vide") and e.icone == action.icon and Icones.connue(action.icon), e)
	var attaque: Dictionary = Etats.etat(g, "attack")
	verifier("forme : le bouton d'attaque porte la minuterie (jauge qui se vide, sans éclat)", attaque.jauge > 0.0 and attaque.jauge < 1.0 and not attaque.eclat and is_equal_approx(attaque.jauge, D6Player.ultimate_view(g).timeFrac), attaque)
	for appareil in ["tactile", "manette", "clavier"]:
		_appareil(appareil)
		_pas(3)
	_entree = {}
	_jusqu_a(func() -> bool: return not D6KitSupers.acting(g), int(s.formTime * 60.0) + 120)
	verifier("forme finie : les emplacements d'origine reviennent au HUD", D6KitSupers.form_of(g) == null and Etats.etat(g, "skill1").icone == "skill" and Etats.etat(g, "skill3").get("vide") == true, g.kit.slots)

## Le bouton de DÉPLACEMENT montre le geste de la classe : pictogramme, nom, charges et recharge
## lus par D6Player.move_view ; les consignes disent « Dashe », « Saute », « Roule ».
func _deplacement_de_classe() -> void:
	const Etats = preload("res://jeu/interface/etat_commandes.gd")
	const Icones = preload("res://jeu/interface/icones.gd")
	const Triangles = preload("res://jeu/theme/triangles.gd")
	const PHRASES := {
		"dash": ["Dashe à travers les attaques", "Esquive le rouge : dashe", "Franchis la rivière d'un dash"],
		"saut": ["Saute par-dessus les attaques", "Esquive le rouge : saute", "Franchis la rivière d'un saut"],
		"roulade": ["Roule à travers les attaques", "Esquive le rouge : roule", "Franchis la rivière d'une roulade"],
	}
	var g := _game()
	var classe: String = g.meta.loadout.classId
	var sorte = g.tuning.dash.get("kind")
	var pictos := {}
	for id in g.tuning.classes:
		var geste: Dictionary = g.tuning.moves[g.tuning.classes[id].move]
		g.meta.loadout.classId = id # le test pose la classe ; la vue, elle, ne fait que lire
		g.tuning.dash["kind"] = geste.kind
		var e: Dictionary = Etats.etat(g, "dash")
		var vue: Dictionary = D6Player.move_view(g)
		var lot := Triangles.new()
		Icones.ajouter(lot, e.icone, Vector2.ZERO, 22.0, Color.WHITE)
		pictos[e.icone] = true
		verifier("classe %s : le bouton porte le pictogramme « %s » de son déplacement, dessiné" % [id, geste.icon], e.icone == geste.icon and Icones.connue(e.icone) and not lot.vide(), e)
		verifier("classe %s : le bouton se nomme « %s »" % [id, geste.name], e.nom == geste.name and e.geste == geste.kind, e)
		verifier("classe %s : charges et recharge sont celles de move_view" % id, e.charges == vue.charges and e.max == vue.maxCharges and e.pret == (1.0 if vue.ready else vue.rechargeFrac), [e, vue])
		var phrases: Array = ["dash", "rouge", "terrain"].map(func(c: String) -> String: return Consignes.texte(Consignes.trouver(c), "clavier", g))
		verifier("classe %s : les consignes parlent de son geste" % id, phrases == PHRASES[geste.kind], phrases)
	verifier("trois classes, trois pictogrammes de déplacement différents", pictos.size() == 3, pictos.keys())
	g.meta.loadout.classId = classe
	if sorte == null:
		g.tuning.dash.erase("kind")
	else:
		g.tuning.dash["kind"] = sorte
	g.player.dashCharges = 0.0
	g.player.dashRecharge = 0.0
	var vide: Dictionary = Etats.etat(g, "dash")
	verifier("déplacement sans charge : pas prêt, la recharge se lit", vide.pret < 1.0 and vide.charges == 0.0 and vide.pret == D6Player.move_view(g).rechargeFrac, vide)
	g.player.dashCharges = D6Player.max_dash_charges(g)

## Clavier et manette : un bouton enfoncé se DESSINE enfoncé, un court instant au moins, et une
## compétence visée tenue montre sa ligne de visée (souris, stick droit), comme au doigt.
func _retours_du_bureau() -> void:
	var g := _game()
	_appareil("clavier")
	var boutons := {}
	for b in hud.commandes_bureau:
		boutons[b.id] = b
	for id in boutons:
		hud.enfoncer(id)
		_pas()
		var vide: bool = hud.Etats.etat(g, id).get("vide", false) # un emplacement vide ne réagit à rien
		verifier("bureau : « %s » enfoncé se dessine enfoncé" % id, boutons[id]._appuye != vide and hud.enfoncees().has(id), hud.enfoncees())
	_pas(12)
	verifier("bureau : le retour « enfoncé » est bref (retombé en 0,2 s)", hud.enfoncees().is_empty() and boutons.values().all(func(b: Node) -> bool: return not b._appuye), hud.enfoncees())
	hud.enfoncer("skill1")
	_pas()
	verifier("bureau, visée assistée : aucune ligne de visée", hud.reperes.visee().is_empty())
	app.vues.entrees.visee = Vector2.LEFT
	for id in ["dash", "attack"]: # ni le déplacement ni l'attaque ne tracent cette ligne
		_pas(12)
		hud.enfoncer(id)
		_pas()
		verifier("bureau : « %s » enfoncé ne montre pas de ligne de visée" % id, hud.reperes.visee().is_empty(), hud.reperes.visee())
	_pas(12)
	for id in ["skill1", "skill2", "skill3"]:
		_pas(12)
		hud.enfoncer(id)
		_pas()
		var e: Dictionary = hud.Etats.etat(g, id)
		var attendue: bool = e.get("visee", false) and not e.get("vide", false)
		var ligne: Dictionary = hud.reperes.visee()
		verifier("bureau : « %s » tenu montre sa ligne de visée depuis le héros si, et seulement si, son action se vise" % id, (ligne.get("dir") == Vector2.LEFT and ligne.get("de") == hud.racine.size / 2.0) if attendue else ligne.is_empty(), [e, ligne])
	_pas(12)
	verifier("bureau : touche relâchée, la ligne s'efface", hud.reperes.visee().is_empty())
	_appareil("tactile")
	hud.enfoncer("skill1")
	_pas()
	verifier("au doigt : le HUD ne trace pas la ligne du bureau (celle du pouce suffit)", hud.reperes.visee().is_empty())
	_pas(12)
	app.vues.entrees.visee = Vector2.ZERO
	_appareil("clavier")
	verifier("salle sans terrain bas : aucun point d'arrivée raccourci", not hud.reperes.arrivee().is_finite())
	g.player.superCharge = 0.0

## Combat V3, affichage : le bouton d'attaque EST la jauge (elle se lit dans le bouton), la ligne
## de visée part du héros quand le pouce glisse, et un emplacement vide ne réagit à rien.
func _jauge_et_visee_v3(Etats: GDScript) -> void:
	const Disposition = preload("res://jeu/interface/disposition.gd")
	var g := _game()
	for part: float in [0.0, 0.25, 0.5, 0.75]:
		g.player.superCharge = part
		var e: Dictionary = Etats.etat(g, "attack")
		verifier("jauge à %d %% : le bouton d'attaque la porte, sans éclat ni maintien" % int(part * 100.0), e.jauge == part and not e.eclat and e.maintien == 0.0, e)
	g.player.superCharge = 0.0
	verifier("l'emplacement 1 (une compétence) se vise ; le vide ne se vise pas", Etats.etat(g, "skill1").get("visee") == true and not Etats.etat(g, "skill3").has("visee"))
	_appareil("tactile")
	var heros := Vector2(480.0, 270.0)
	var ui: Dictionary = Disposition.calculer(hud.racine.size, Vector4.ZERO)
	var poses := {}
	for b in ui.buttons:
		b.pressed = true
		b.dragging = b.id != "dash"
		b.dx = -40.0
		b.dy = 0.0
		poses[b.id] = Vector2(b.x, b.y)
	hud.tactile.actualiser(g, {"stick": ui.stick, "buttons": ui.buttons.filter(func(b: Dictionary) -> bool: return b.id == "skill3")}, "", heros)
	var vide: Node = hud.tactile.get_node("Emplacement3")
	verifier("emplacement vide, pouce posé et glissé dessus : ni enfoncé, ni repère, ni ligne de visée", not vide._appuye and vide._visee == Vector2.ZERO and hud.tactile.visee().is_empty(), hud.tactile.visee())
	hud.tactile.actualiser(g, {"stick": ui.stick, "buttons": ui.buttons.filter(func(b: Dictionary) -> bool: return b.id == "skill1")}, "", heros)
	var ligne: Dictionary = hud.tactile.visee()
	verifier("emplacement 1 glissé : la ligne de visée part du héros, dans la direction du pouce", ligne.get("de") == heros and ligne.get("dir", Vector2.ZERO).is_equal_approx(Vector2.LEFT) and hud.tactile.get_node("Emplacement1")._appuye, ligne)
	hud.tactile.actualiser(g, {"stick": ui.stick, "buttons": ui.buttons.filter(func(b: Dictionary) -> bool: return b.id == "attack")}, "", heros)
	verifier("attaque glissée : la ligne de visée part du héros", hud.tactile.visee().get("de") == heros and hud.tactile.visee().dir.is_equal_approx(Vector2.LEFT))
	hud.tactile.actualiser(g, {"stick": ui.stick, "buttons": ui.buttons.filter(func(b: Dictionary) -> bool: return b.id == "dash")}, "", heros)
	verifier("dash appuyé : aucune ligne de visée", hud.tactile.visee().is_empty())
	hud.tactile.actualiser(g, ui, "", heros)
	for id in poses:
		var bouton: Control = hud.tactile._boutons[id]
		verifier("le bouton « %s » est dessiné là où la disposition le place" % id, (bouton.position + bouton.size / 2.0).is_equal_approx(poses[id]), [bouton.position + bouton.size / 2.0, poses[id]])
	_appareil("clavier")

func _recompense_et_porte() -> void:
	var g := _game()
	g.room.cleared = true
	D6Room.make_doors(g, [{"reward": "boon", "family": "colere"}, {"reward": "loot"}])
	for d in g.room.doors:
		d.open = false
	g.player.x = g.room.w / 2.0 - LOIN
	g.player.y = g.room.h / 2.0
	g.room.interact = {"kind": "boon", "x": g.room.w / 2.0, "y": g.room.h / 2.0, "r": 30.0, "used": false, "family": "colere"}
	verifier("récompense : apparaît devant le premier butin", _montree("recompense"), accueil.montree())
	_libelles("recompense", _trois("Marche sur la récompense pour la prendre"), "")
	g.player.x = g.room.interact.x
	verifier("récompense : marcher dessus ouvre le choix", _jusqu_a(func() -> bool: return g.mode == "choice", PEU), g.mode)
	_acquise("recompense")
	verifier("le choix se fait : la partie reprend", app.commande({"type": "choose", "index": 0.0}) and g.mode == "play", g.mode)
	verifier("porte : apparaît quand les portes s'ouvrent", _montree("porte"), accueil.montree())
	_libelles("porte", _trois("Franchis une porte : elle annonce ta récompense"), "")
	verifier("porte : l'indice permanent se tait pendant la consigne", not hud.indice.visible)
	var porte: Dictionary = g.room.doors[0]
	g.player.x = porte.x + porte.w / 2.0
	g.player.y = porte.y + porte.h / 2.0
	verifier("porte : la franchir mène à l'étage suivant", _jusqu_a(func() -> bool: return g.run.floor == 2.0, PEU), g.run.floor)
	_acquise("porte")
	_calmer()
	await process_frame

func _mort() -> void:
	var g := _game()
	_pas(FONDU)
	verifier("mort : rien tant que le héros n'est pas mort", accueil.montree() == "", accueil.montree())
	g.godMode = false
	g.player.iframes = 0.0
	D6Combat.damage_player(g, 1e6, {"kind": "imp", "id": -1.0, "x": g.player.x, "y": g.player.y})
	verifier("le héros meurt : écran de mort", _jusqu_a(func() -> bool: return g.mode == "dead"), g.mode)
	verifier("mort : rien pendant l'écran de mort", accueil.montree() == "")
	verifier("il repart du checkpoint", app.commande({"type": "respawn", "floor": 1.0}) and g.mode == "play", g.mode)
	_calmer()
	verifier("mort : apparaît au retour de la première mort", _montree("mort"), accueil.montree())
	_libelles("mort", _trois("Les bénédictions se regagnent.\nDépense tes Âmes en Ville."), "")
	_pas(int(Consignes.trouver("mort").patience / DT) + 5)
	_acquise("mort")
	await process_frame

# ---------------------------------------------------------------- une seule fois, par joueur

func _jamais_deux_fois() -> void:
	verifier("les onze consignes sont sur le disque", _sur_disque() == Consignes.ids(), _sur_disque())
	await _nouvelle_app(false)
	verifier("application relancée : les acquis sont relus", app.reglages.accueil.acquis == Consignes.ids(), app.reglages.accueil)
	app.demarrer_descente(1.0, false, false, GRAINE)
	_game().godMode = true
	var vues := {}
	for i in 900: # quinze secondes d'une vraie salle, ennemis et télégraphes compris
		_pas()
		vues[accueil.montree()] = true
	verifier("un joueur qui sait jouer ne revoit aucune consigne", vues.keys() == [""], vues.keys())

func _arene_et_entrainement() -> void:
	await _nouvelle_app(true)
	app.demarrer_descente(1.0, true)
	verifier("arène : c'est bien l'arène d'essai", D6Js.truthy(_game().get("sandbox")))
	verifier("arène : aucune consigne, rien d'acquis", _muet_et_sans_acquis())
	app.demarrer_entrainement(D6Floors.guardian_for(app.contenu, 1.0))
	verifier("entraînement : c'est bien l'entraînement", D6Js.truthy(_game().get("practice")))
	verifier("entraînement : aucune consigne, rien d'acquis", _muet_et_sans_acquis())

## Trois secondes de jeu avec tous les gestes : rien ne s'affiche, rien n'est retenu.
func _muet_et_sans_acquis() -> bool:
	_game().godMode = true
	var muet := true
	for i in 180:
		_entree = {"moveX": 1.0, "attackPressed": i == 20, "dashPressed": i == 60, "skill1Pressed": i == 100, "skill2Pressed": i == 140}
		_pas()
		muet = muet and accueil.montree() == "" and not accueil.visible
	_entree = {}
	return muet and _sur_disque().is_empty() and app.reglages.accueil.acquis.is_empty()

# ---------------------------------------------------------------- le réglage de la pause

func _bouton_de_pause(nom: String) -> Button:
	app.mettre_en_pause(true)
	for i in 4:
		await process_frame
	return app.vues.ecrans.ecran().get_node("%" + nom) if app.vues.ecrans.ecran_montre() == "pause" else null

func _reprendre() -> void:
	app.mettre_en_pause(false)
	await process_frame

func _couper_et_revoir() -> void:
	await _nouvelle_app(true)
	app.demarrer_descente(1.0, false, false, GRAINE)
	_calmer()
	verifier("réglage : la première consigne est là", _montree("bouger"), accueil.montree())
	var couper := await _bouton_de_pause("Consignes")
	verifier("pause : « Consignes : oui » et « Consignes : toutes à revoir »", couper != null and couper.text == "Consignes : oui" and couper.get_node("%RevoirConsignes").text == "Consignes : toutes à revoir")
	_pas(60)
	verifier("pause : la consigne ne bouge pas pendant la pause", accueil.montree() == "bouger")
	couper.pressed.emit()
	await process_frame
	verifier("couper : le réglage passe à non, sur le disque aussi", app.reglages.accueil.actif == false and Profil.charger_reglages().accueil.actif == false and couper.text == "Consignes : non", couper.text)
	await _reprendre()
	_entree = {"moveX": 1.0}
	_pas(120)
	_entree = {}
	verifier("coupées : plus aucune consigne, et rien n'est retenu", accueil.montree() == "" and _sur_disque().is_empty(), accueil.montree())
	couper = await _bouton_de_pause("Consignes")
	couper.pressed.emit()
	await _reprendre()
	verifier("remises : la consigne revient", app.reglages.accueil.actif and _montree("bouger"), accueil.montree())
	_entree = {"moveX": -1.0}
	_acquise("bouger")
	_entree = {}
	verifier("la suivante prend la place", _montree("attaquer"), accueil.montree())
	var revoir := await _bouton_de_pause("RevoirConsignes")
	verifier("pause : « Revoir les consignes » quand il y a un acquis", revoir != null and revoir.text == "Revoir les consignes", revoir.text if revoir != null else "")
	revoir.pressed.emit()
	await process_frame
	verifier("revoir : les acquis sont effacés, sur le disque aussi", app.reglages.accueil.acquis.is_empty() and _sur_disque().is_empty() and revoir.text == "Consignes : toutes à revoir", revoir.text)
	await _reprendre()
	verifier("revoir : la première consigne revient", _montree("bouger"), accueil.montree())
