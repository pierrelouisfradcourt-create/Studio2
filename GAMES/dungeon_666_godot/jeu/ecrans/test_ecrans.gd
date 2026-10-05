extends SceneTree
## Test headless des écrans (0 = vert) :
##   <godot> --headless --path . --script res://jeu/ecrans/test_ecrans.gd
## Le vrai `principal.gd` (banc_app.gd), la vraie simulation, de vrais clics, touchers et touches.
## Pour chaque sorte de menu : chaque bouton actif envoie une commande que la simulation ACCEPTE
## et le menu se ferme ; chaque bouton grisé correspond à une commande qu'elle REFUSE ; un appui
## dans l'instant qui suit l'ouverture ne choisit rien. Mort, victoire, pause, labo, réglages.

const App = preload("res://jeu/ecrans/banc_app.gd")
const Scenes = preload("res://jeu/ecrans/banc_scenes.gd")
const LaboRepli = preload("res://jeu/ecrans/labo_repli.tscn")
const Fondus = preload("res://jeu/essai/fondus.gd")
const DONNEES := "user://essais_ecrans_test"
const GRAINE := 7.0
const IMAGES_MAX := 900
const SORTES := ["benediction", "butin", "butin_autre_classe", "marchand", "marchand_riche", "evenement", "evenement_sans_or", "coffre", "fontaine", "fontaine_benie"]

var app: Node
var ecrans: Node
var echecs := 0
var verifications := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	_derouler.call_deferred()

func _derouler() -> void:
	await _nouvelle_app(false)
	await _titre()
	for sorte in SORTES:
		await _tous_les_boutons(sorte)
	await _anti_martelage()
	await _mort()
	await _mort_et_experience()
	await _titre_et_points()
	await _mort_et_gain()
	await _victoire()
	await _pause()
	await _labo_et_feel()
	await _abandon()
	await _avec_entrees()
	await _labo_de_repli()
	print("test_ecrans : %d vérifications, %d échec(s)" % [verifications, echecs])
	await Fondus.laisser_finir(self)
	quit(1 if echecs > 0 else 0)

# ---------------------------------------------------------------- outils

func verifier(nom: String, ok: bool, detail = "") -> void:
	verifications += 1
	if not ok:
		echecs += 1
		print("ÉCHEC  ", nom, "  ", detail)

func _nouvelle_app(fausses_entrees: bool) -> void:
	if app != null:
		await Fondus.laisser_finir(self)
		app.free()
	for fichier in ["profil.json", "profil.json.bak", "reglages_jeu.json", "reglages_jeu.json.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DONNEES.path_join(fichier)))
	app = App.new()
	app.vues_voulues = ["ecrans"]
	app.fausses_entrees = fausses_entrees
	root.add_child(app)
	ecrans = app.vues.ecrans
	await process_frame

func _attendre(condition: Callable) -> bool:
	for i in IMAGES_MAX:
		if condition.call():
			return true
		await process_frame
	return condition.call()

func _attendre_ms(ms: float) -> void:
	var fin := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < fin:
		await process_frame

## L'écran est posé (mise en page faite) et armé.
func _attendre_pret() -> void:
	await _attendre(func() -> bool: return ecrans.pret())
	await process_frame
	await process_frame
	await process_frame

func _centre(c: Control) -> Vector2:
	return c.get_global_transform() * (c.size / 2.0)

## Amène le contrôle dans la fenêtre du panneau s'il est plus bas (panneau qui défile).
func _montrer(c: Control) -> void:
	var p: Node = c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		p.ensure_control_visible(c)
		await process_frame

func _cliquer(c: Control) -> void:
	await _montrer(c)
	for enfonce in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = enfonce
		ev.position = _centre(c)
		ev.global_position = ev.position
		root.push_input(ev, true)
		await process_frame

func _toucher(c: Control, doigt: int) -> void:
	for enfonce in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = doigt
		ev.pressed = enfonce
		ev.position = _centre(c)
		root.push_input(ev, true)
		await process_frame

func _touche(code: Key) -> void:
	for enfonce in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = enfonce
		root.push_input(ev, true)
		await process_frame

func _boutons() -> Array:
	return ecrans.ecran().find_children("*", "BaseButton", true, false).filter(func(b: BaseButton) -> bool: return b.is_visible_in_tree())

func _game() -> Dictionary:
	return app.partie.game

# ---------------------------------------------------------------- mises en scène

## Descente neuve amenée devant le menu `sorte` (les variantes préparent un cas grisé).
func _ouvrir_menu(sorte: String) -> bool:
	app.demarrer_descente(1.0, false, false, GRAINE)
	var g := _game()
	var base := sorte.get_slice("_", 0)
	Scenes.entrer(g, base)
	match sorte:
		"butin_autre_classe":
			Scenes.vider_salle(g)
			await _attendre(func() -> bool: return g.room.get("interact") is Dictionary)
			g.room.interact.item.slot = "arme"
			g.room.interact.item.weaponType = "arme_inconnue"
		"marchand": Scenes.donner_or(g, 60.0)
		"marchand_riche": Scenes.donner_or(g, 5000.0)
		"evenement", "evenement_sans_or":
			g.room.interact.event = "mammon"
			Scenes.donner_or(g, 100.0 if sorte == "evenement" else 0.0)
		"fontaine_benie": Scenes.benir(g, 2)
	app.journal.clear()
	var ouvert := await _attendre(func() -> bool:
		Scenes.avancer_vers_le_menu(g)
		return g.mode == "choice" and ecrans.ecran_montre() == "choix")
	if ouvert:
		await _attendre_pret()
	return ouvert

# ---------------------------------------------------------------- titre

func _titre() -> void:
	verifier("titre : écran montré au lancement", ecrans.ecran_montre() == "titre", ecrans.ecran_montre())
	await _attendre_pret()
	var b := _boutons()
	verifier("titre : trois boutons", b.size() == 3, b.size())
	verifier("titre : le premier bouton a le focus", root.gui_get_focus_owner() == b[0])
	for bouton in b:
		verifier("titre : cible ≥ 44 px (%s)" % bouton.text, bouton.size.y >= 44.0, bouton.size)
	await _cliquer(b[2])
	verifier("titre : « Arène d'essai » démarre l'arène", app.ecran == "jeu" and _game().sandbox)
	app.ouvrir_titre()
	await process_frame
	await _attendre_pret()
	await _cliquer(_boutons()[0])
	verifier("titre : « Entrer dans Dité » ouvre la Ville", app.ecran == "ville" and ecrans.ecran_montre() == "", app.ecran)

# ---------------------------------------------------------------- menus de choix

## Presse tour à tour CHAQUE bouton du menu (menu rouvert à neuf à chaque fois).
func _tous_les_boutons(sorte: String) -> void:
	if not await _ouvrir_menu(sorte):
		verifier(sorte + " : le menu s'ouvre", false, _game().mode)
		return
	var n := _boutons().size()
	verifier(sorte + " : des boutons", n >= 2, n)
	for i in n:
		if i > 0 and not await _ouvrir_menu(sorte):
			verifier(sorte + " : le menu se rouvre", false)
			return
		await _presser(sorte, i)

func _presser(sorte: String, i: int) -> void:
	var b: BaseButton = _boutons()[i]
	var nom := "%s, bouton %d" % [sorte, i]
	verifier(nom + " : cible ≥ 44 px", b.size.y >= 44.0 and b.size.x >= 44.0, b.size)
	if b.disabled:
		b.pressed.emit() # un clic n'y ferait rien : on force, pour voir ce qu'en dirait la simulation
		var refus: bool = app.journal.size() == 1 and not app.journal[0].ok
		verifier(nom + " (grisé) : la simulation aurait refusé", refus and _game().mode == "choice", app.journal)
		return
	await _cliquer(b)
	if app.journal.size() != 1:
		verifier(nom + " : une commande envoyée", false, [app.journal, _centre(b), root.get_visible_rect(), ecrans.pret()])
		return
	var envoi: Dictionary = app.journal[0]
	verifier(nom + " : commande acceptée " + str(envoi.cmd), envoi.ok)
	var achat: bool = sorte.begins_with("marchand") and envoi.cmd.type == "choose"
	if achat:
		var offre: Dictionary = _game().choice.offers[int(envoi.cmd.index)]
		verifier(nom + " : l'offre achetée est vendue, le marchand reste ouvert", D6Js.truthy(offre.sold) and ecrans.ecran_montre() == "choix")
		verifier(nom + " : marchand rafraîchi sans délai", ecrans.pret())
	else:
		verifier(nom + " : le menu se ferme", envoi.mode == "play", envoi.mode)

## Un menu tout juste ouvert n'accepte aucun choix : clic, second doigt, touche du dash.
func _anti_martelage() -> void:
	app.demarrer_descente(1.0, false, false, GRAINE)
	var g := _game()
	Scenes.entrer(g, "benediction")
	app.journal.clear()
	await _attendre(func() -> bool:
		Scenes.avancer_vers_le_menu(g)
		return ecrans.ecran_montre() == "choix")
	verifier("armement : le menu ouvert n'est pas encore prêt", not ecrans.pret())
	await process_frame
	await process_frame
	var carte: BaseButton = _boutons()[0]
	verifier("armement : la première carte a le focus", root.gui_get_focus_owner() == carte)
	await _cliquer(carte)
	await _toucher(carte, 1)
	await _touche(KEY_SPACE)
	await _touche(KEY_ENTER)
	verifier("armement : clic, toucher et touches réflexes ne choisissent rien", g.mode == "choice" and g.run.boons.is_empty() and app.journal.is_empty(), app.journal)
	# Martelage à 4 Hz : chaque appui relance l'armement, rien n'est jamais choisi.
	for i in 6:
		await _attendre_ms(250.0)
		await _cliquer(carte)
	verifier("armement : un martelage à 4 Hz ne choisit rien", g.mode == "choice" and app.journal.is_empty(), app.journal)
	await _attendre_pret()
	await _touche(KEY_ENTER)
	verifier("armement : une fois prêt, Entrée choisit la carte qui a le focus", g.mode == "play" and g.run.boons.size() == 1, g.mode)
	verifier("armement : menu fermé, plus aucun écran", ecrans.ecran_montre() == "")

# ---------------------------------------------------------------- mort, victoire

func _mourir(arene: bool) -> void:
	app.demarrer_descente(1.0, arene, false, GRAINE)
	Scenes.benir(_game(), 2)
	Scenes.donner_or(_game(), 60.0)
	Scenes.tuer_le_heros(_game())
	app.journal.clear()
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "mort")

func _mort() -> void:
	await _mourir(false)
	verifier("mort : écran montré", _game().mode == "dead" and ecrans.ecran_montre() == "mort")
	await process_frame
	await process_frame
	await _cliquer(_boutons()[0])
	verifier("mort : un clic réflexe ne relance rien", _game().mode == "dead" and app.journal.is_empty())
	await _attendre_pret()
	var recap: Dictionary = _game().run.deathRecap
	var texte: String = _boutons()[0].text
	verifier("mort : le bouton nomme le checkpoint", texte.ends_with("étage " + D6Js.num_str(recap.checkpoint)), texte)
	await _cliquer(_boutons()[0])
	verifier("mort : « Repartir » ramène en jeu", _game().mode == "play" and app.journal[0].ok and ecrans.ecran_montre() == "", _game().mode)
	verifier("mort : le temporaire est reparti de zéro", _game().run.boons.is_empty())
	await _mourir(false)
	await _attendre_pret()
	await _cliquer(_boutons()[1])
	verifier("mort : « Retour à la Ville » ouvre la Ville", app.ecran == "ville" and app.partie.game == null and ecrans.ecran_montre() == "", app.ecran)
	await _mourir(true)
	await _attendre_pret()
	verifier("mort en arène : pas de récapitulatif, « Recommencer l'arène »", _boutons().size() == 2 and _boutons()[0].text == "Recommencer l'arène", _boutons()[0].text)
	await _cliquer(_boutons()[0])
	verifier("mort en arène : on recommence l'arène", _game().mode == "play" and _game().sandbox)

## Arbre de compétences : l'écran de mort dit l'expérience de classe gagnée et le niveau passé.
func _mort_et_experience() -> void:
	app.demarrer_descente(1.0, false, false, GRAINE)
	var g := _game()
	var a_tuer := int(g.tuning.tree.curve.base / g.tuning.tree.xp.kill) # de quoi passer le niveau 1
	for i in a_tuer:
		D6Combat.kill_enemy(g, D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, {"spawnT": 0.0}))
	Scenes.tuer_le_heros(g)
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "mort")
	var bilan: Dictionary = g.run.deathRecap.tree
	var textes: Array = ecrans.ecran().find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.is_visible_in_tree()).map(func(l: Label) -> String: return l.text)
	verifier("mort : le bilan compte l'expérience et le niveau gagnés", bilan.xpEarned >= g.tuning.tree.curve.base and bilan.levelsGained == 1.0 and bilan.level == 2.0, bilan)
	verifier("mort : l'expérience de classe gagnée est écrite", textes.has("Expérience de classe : +%s." % D6Js.num_str(bilan.xpEarned)), textes)
	verifier("mort : « Niveau 2 ! +1 point à dépenser au Grimoire. »", textes.has("Niveau 2 ! +1 point à dépenser au Grimoire."), textes)
	# Écran de l'arbre : la barre d'expérience ; un niveau passé, tout l'acquis du niveau en cours est du gain.
	var barre: Control = ecrans.ecran().get_node("%BarreXp")
	var vue: Dictionary = D6Profile.tree_view(g.meta, g.tuning, bilan.classId)
	verifier("mort : la barre d'expérience montre le niveau en cours, tout en gain après un niveau passé", barre.is_visible_in_tree() and is_equal_approx(barre.part(), vue.xp / vue.xpNext) and barre.depuis() == 0.0, [barre.part(), barre.depuis()])
	await _attendre_pret()
	await _cliquer(_boutons()[1])
	verifier("mort : de retour en Ville, le niveau gagné reste au profil de la partie", app.ecran == "ville" and g.meta.tree.revenant.level == 2.0, g.meta.tree)

## Écran de l'arbre : la barre d'expérience de l'écran de mort. Sans niveau passé, la part gagnée
## dans la descente se détache de ce qui était acquis avant ; aucun « Niveau N ! ». En arène, rien.
func _mort_et_gain() -> void:
	app.demarrer_descente(1.0, false, false, GRAINE)
	var g := _game()
	var classe: String = g.meta.loadout.classId
	var avant: Dictionary = D6Profile.tree_view(g.meta, g.tuning, classe)
	for i in 5:
		D6Combat.kill_enemy(g, D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, {"spawnT": 0.0}))
	for i in 7:
		D6Combat.kill_enemy(g, D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, {"spawnT": 0.0}))
	Scenes.tuer_le_heros(g)
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "mort")
	var bilan: Dictionary = g.run.deathRecap.tree
	var v: Dictionary = D6Profile.tree_view(g.meta, g.tuning, classe)
	var barre: Control = ecrans.ecran().get_node("%BarreXp")
	var niveau: Label = ecrans.ecran().get_node("%NiveauGagne")
	var ligne: Label = ecrans.ecran().get_node("%NiveauClasse")
	verifier("mort, sans niveau passé : le bilan compte l'expérience, aucun niveau", bilan.xpEarned > 0.0 and bilan.levelsGained == 0.0 and v.level == avant.level, bilan)
	verifier("mort : la barre est à la part acquise du niveau en cours", barre.is_visible_in_tree() and is_equal_approx(barre.part(), v.xp / v.xpNext), [barre.part(), v.xp, v.xpNext])
	verifier("mort : le gain de la descente part de ce qui était acquis avant", is_equal_approx(barre.depuis(), avant.xp / avant.xpNext) and barre.depuis() < barre.part(), [barre.depuis(), avant.xp])
	verifier("mort : « classe · niveau N · acquis / à atteindre »", ligne.is_visible_in_tree() and ligne.text == "%s · niveau %s · %s / %s" % [g.tuning.classes[classe].name, D6Js.num_str(v.level), D6Js.num_str(v.xp), D6Js.num_str(v.xpNext)], ligne.text)
	verifier("mort, sans niveau passé : pas de « Niveau N ! »", not niveau.is_visible_in_tree(), niveau.text)
	await _attendre_pret()
	await _cliquer(_boutons()[1])
	app.demarrer_descente(1.0, true, false, GRAINE)
	Scenes.tuer_le_heros(_game())
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "mort")
	verifier("mort en arène : aucune progression montrée (rien n'y est gagné)", not ecrans.ecran().get_node("%Progression").is_visible_in_tree())
	app.ouvrir_titre()
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "titre")

## Écran de l'arbre : le bouton d'entrée en Ville porte une pastille quand des points de compétence attendent.
func _titre_et_points() -> void:
	app.ouvrir_titre()
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "titre")
	var points: float = D6Profile.tree_points(app.profil, app.contenu, app.profil.loadout.classId)
	var pastille: Control = ecrans.ecran().pastille()
	verifier("titre : des points attendent (niveau gagné plus haut)", points > 0.0, points)
	verifier("titre : « Entrer dans Dité » porte une pastille au nombre de points", pastille != null and pastille.is_visible_in_tree() and pastille.nombre == int(points) and pastille.get_parent() == _boutons()[0], pastille.nombre if pastille != null else -1)
	var depense: Dictionary = app.operation_ville("tree_buy", [String(app.profil.loadout.classId), String(app.contenu.classes[app.profil.loadout.classId].skills[0])])
	app.ouvrir_ville()
	await process_frame
	await process_frame
	app.ouvrir_titre()
	await _attendre(func() -> bool: return ecrans.ecran_montre() == "titre")
	await process_frame
	verifier("titre : le point dépensé, la pastille s'en va", D6Js.truthy(depense.get("ok")) and points == 1.0 and not ecrans.ecran().pastille().is_visible_in_tree(), [depense, points])

func _victoire() -> void:
	app.demarrer_descente(Scenes.ETAGE_FINAL, false, false, GRAINE)
	var g := _game()
	app.journal.clear()
	var vu := await _attendre(func() -> bool:
		Scenes.avancer_vers_le_menu(g)
		return ecrans.ecran_montre() == "victoire")
	verifier("victoire : écran montré", vu and g.mode == "victory", g.mode)
	await _attendre_pret()
	await _cliquer(_boutons()[0])
	verifier("victoire : « Retour à la Ville » ouvre la Ville", app.ecran == "ville" and app.journal.size() == 1 and app.journal[0].ok, app.ecran)

# ---------------------------------------------------------------- pause, labo, réglages

func _mettre_en_pause() -> void:
	app.demarrer_descente(1.0, false, false, GRAINE)
	await process_frame
	await _touche(KEY_ESCAPE)
	await _attendre_pret()

func _pause() -> void:
	await _mettre_en_pause()
	verifier("pause : Échap ouvre la pause", app.partie.en_pause and ecrans.ecran_montre() == "pause", ecrans.ecran_montre())
	var tick: float = _game().tick
	var p: Control = ecrans.ecran()
	verifier("pause : « Reprendre » a le focus", root.gui_get_focus_owner() == p.get_node("%Reprendre"))
	await _cliquer(p.get_node("%Son"))
	verifier("pause : le son se coupe, le libellé suit", app.reglages.sound == false and p.get_node("%Son").text == "Son : non", p.get_node("%Son").text)
	await _cliquer(p.get_node("%Vibrations"))
	verifier("pause : les vibrations se coupent", app.reglages.haptics == false)
	await _cliquer(p.get_node("%Tremblement"))
	verifier("pause : le tremblement passe à 50 %", is_equal_approx(app.reglages.shake, 0.5) and p.get_node("%Tremblement").text == "Tremblement : 50 %", p.get_node("%Tremblement").text)
	verifier("pause : la partie n'avance pas", _game().tick == tick)
	await _touche(KEY_ESCAPE)
	verifier("pause : Échap la referme", not app.partie.en_pause and ecrans.ecran_montre() == "")
	app.mettre_en_pause(true) # le bouton du HUD
	await process_frame
	verifier("pause : ouverte par app.mettre_en_pause (bouton du HUD)", ecrans.ecran_montre() == "pause")
	await _cliquer(ecrans.ecran().get_node("%Reprendre"))
	verifier("pause : « Reprendre » relance le jeu", not app.partie.en_pause and ecrans.ecran_montre() == "")

func _labo_et_feel() -> void:
	await _mettre_en_pause()
	await _cliquer(ecrans.ecran().get_node("%Labo"))
	verifier("labo : ouvert depuis la pause", ecrans.ecran_montre() == "labo" and app.partie.en_pause, ecrans.ecran_montre())
	await _attendre_pret()
	verifier("labo : au moins une option par variante", _boutons().size() >= 8, _boutons().size())
	await _touche(KEY_ESCAPE)
	verifier("labo : Échap revient à la pause", ecrans.ecran_montre() == "pause" and app.partie.en_pause, ecrans.ecran_montre())
	await _cliquer(ecrans.ecran().get_node("%Feel"))
	verifier("feel : ouvert depuis la pause", ecrans.ecran_montre() == "feel", ecrans.ecran_montre())
	await _attendre_pret()
	var f: Control = ecrans.ecran()
	var lignes: Array = f.get_node("%Liste").get_children()
	verifier("feel : dix-sept réglettes", lignes.size() == 17, lignes.size())
	var tuning: Dictionary = _game().tuning
	var vitesse: float = tuning.player.speed
	lignes[0].curseur().value = vitesse + 40.0
	verifier("feel : la réglette écrit dans le tuning de la partie", tuning.player.speed == vitesse + 40.0, tuning.player.speed)
	lignes[10].curseur().value = 0.1
	verifier("feel : le gel des coups 1-2 règle les deux coups", tuning.combo[0].hitstop == 0.1 and tuning.combo[1].hitstop == 0.1)
	await _cliquer(f.get_node("%Copier"))
	verifier("feel : « Copier » annonce la copie des écarts", f.get_node("%Copier").text == "Copié" and f.etat.ecarts.size() == 2, f.etat.texte_ecarts())
	app.demarrer_descente(1.0, false, false, GRAINE)
	verifier("feel : les écarts suivent dans la partie suivante", _game().tuning.player.speed == vitesse + 40.0, _game().tuning.player.speed)
	await _mettre_en_pause()
	await _cliquer(ecrans.ecran().get_node("%Feel"))
	await _attendre_pret()
	await _cliquer(ecrans.ecran().get_node("%Reinitialiser"))
	verifier("feel : « Réinitialiser » rend les valeurs de départ", _game().tuning.player.speed == vitesse and ecrans.ecran().etat.ecarts.is_empty(), _game().tuning.player.speed)
	await _cliquer(ecrans.ecran().get_node("%Fermer"))
	verifier("feel : « Fermer » revient à la pause", ecrans.ecran_montre() == "pause")

func _abandon() -> void:
	await _mettre_en_pause()
	var p: Control = ecrans.ecran()
	await _cliquer(p.get_node("%Abandonner"))
	verifier("abandon : une confirmation, la partie est toujours là", p.get_node("%Confirmation").visible and app.ecran == "jeu" and app.partie.game != null)
	await _cliquer(p.get_node("%Rester"))
	verifier("abandon : « Continuer » revient au menu de pause", p.get_node("%Menu").visible and app.partie.en_pause)
	await _cliquer(p.get_node("%Abandonner"))
	await _cliquer(p.get_node("%Confirmer"))
	verifier("abandon : confirmé, retour en Ville", app.ecran == "ville" and app.partie.game == null and ecrans.ecran_montre() == "", app.ecran)

# ---------------------------------------------------------------- avec la vue Entrees

func _avec_entrees() -> void:
	await _nouvelle_app(true)
	var entrees: Node = app.vues.entrees
	entrees.est_tactile = true
	app.demarrer_descente(1.0, false, false, GRAINE)
	await process_frame
	var vidages: int = entrees.vidages
	entrees.pause_demandee.emit()
	await _attendre_pret()
	verifier("entrées : pause_demandee ouvre la pause", ecrans.ecran_montre() == "pause" and app.partie.en_pause)
	verifier("entrées : vider() à l'ouverture", entrees.vidages == vidages + 1, entrees.vidages)
	verifier("entrées : au doigt, aucun focus posé d'office", root.gui_get_focus_owner() == null)
	await _toucher(ecrans.ecran().get_node("%Son"), 1)
	verifier("entrées : un second doigt active un bouton", app.reglages.sound == false)
	await _toucher(ecrans.ecran().get_node("%Son"), 0)
	verifier("entrées : le premier doigt est laissé à la souris émulée", app.reglages.sound == false)
	await _touche(KEY_ESCAPE)
	verifier("entrées : Échap est laissé à la vue Entrees", ecrans.ecran_montre() == "pause")
	entrees.pause_demandee.emit()
	await process_frame
	verifier("entrées : pause_demandee referme la pause", ecrans.ecran_montre() == "" and not app.partie.en_pause)
	verifier("entrées : vider() à la fermeture", entrees.vidages == vidages + 2, entrees.vidages)

func _labo_de_repli() -> void:
	var panneau := LaboRepli.instantiate()
	root.add_child(panneau)
	var choix: Array = []
	panneau.choisi.connect(func(axe: String, variante: String) -> void: choix.append([axe, variante]))
	panneau.brancher(app, app.partie)
	var boutons: Array = panneau.find_children("*", "Button", true, false)
	verifier("labo de repli : huit variantes sur trois axes", boutons.size() == 8, boutons.size())
	boutons[1].pressed.emit()
	verifier("labo de repli : une variante pressée est demandée", choix == [["dashStrike", "toutDash"]], choix)
	app.regler_labo("dashStrike", "toutDash")
	verifier("labo de repli : la variante retenue porte le bouton principal", boutons[1].theme_type_variation == &"BoutonPetitPrincipal")
	panneau.free()
