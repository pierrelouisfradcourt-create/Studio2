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
	_competence_et_gadget()
	_super()
	_commandes_v3()
	await _recompense_et_porte()
	await _mort()
	await _jamais_deux_fois()
	await _arene_et_entrainement()
	await _couper_et_revoir()
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

# ---------------------------------------------------------------- les consignes, une à une

func _reglages_neufs() -> void:
	var a: Dictionary = app.reglages.accueil
	verifier("réglages neufs : consignes actives, aucune acquise", a.actif == true and a.acquis.is_empty(), a)
	verifier("la table : dix consignes, identifiants uniques", Consignes.TABLE.size() == 10 and Consignes.ids().size() == 10, Consignes.ids())

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
	_libelles("dash", _trois("Traverse les attaques d'un dash"), "dash")
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
	_libelles("rouge", _trois("Esquive le rouge"), "dash")
	g.player.dashCharges = 1.0
	_entree = {"dashPressed": true}
	_acquise("rouge")
	zone.done = true

func _competence_et_gadget() -> void:
	var g := _game()
	verifier("compétence : rien sans ennemi", not Consignes.quand("competence_prete", g))
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x - LOIN, g.player.y, {})
	e.spawnT = 0.0
	verifier("compétence : apparaît au combat", _montree("competence"), accueil.montree())
	_libelles("competence", {"clavier": "Lance ta compétence", "manette": "Lance ta compétence", "tactile": "Compétence : glisse pour viser, relâche"}, "skill1")
	_entree = {"skill1Pressed": true}
	_acquise("competence")
	verifier("gadget : apparaît ensuite", _montree("gadget"), accueil.montree())
	_libelles("gadget", _trois("Utilise ton gadget"), "skill2")
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
	verifier("HUD tactile : les mêmes cinq commandes", hud.tactile.get_children().map(func(c: Node) -> String: return c.id) == ["attack", "dash", "skill1", "skill3", "skill2"])
	verifier("profil neuf : compétence, gadget, emplacement vide", g.kit.slots[0] != null and g.kit.slots[1] != null and g.kit.slots[2] == null, g.kit.slots)
	var vide: Dictionary = Etats.etat(g, "skill3")
	verifier("emplacement vide : pas prêt, pas de pictogramme, et le HUD continue de tourner", vide.get("vide") == true and vide.pret == 0.0 and vide.icone == "", vide)
	var competence: Dictionary = Etats.etat(g, "skill1")
	var gadget: Dictionary = Etats.etat(g, "skill2")
	verifier("emplacement 1 : la compétence, son anneau de recharge", competence.get("recharge") == true and competence.icone == "skill", competence)
	verifier("emplacement 2 : le gadget, ses charges", gadget.get("max", 0.0) >= 1.0 and gadget.charges <= gadget.max and gadget.icone == "gadget", gadget)
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
	verifier("les dix consignes sont sur le disque", _sur_disque() == Consignes.ids(), _sur_disque())
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
