extends SceneTree
## Essai headless de la Ville de Dité, sur le VRAI programme principal (jeu/principal.gd).
##   <godot> --headless --path . --script res://jeu/ville/test_ville.gd      (sortie 0 = vert)
## Il APPUIE sur les boutons de la Ville (signal `pressed` d'un bouton trouvé dans l'écran, jamais
## un bouton grisé) et lit `app.profil`, `app.reglages`, `partie.game`. Il travaille dans son
## dossier d'essai : le vrai profil du joueur n'est ni lu ni écrit.
## Ce qu'il ne prouve pas : que l'écran se LIT (voir les captures du banc).

const DOSSIER := "user://essais_ville/test"
const VRAI_PROFIL := "user://profil.json"
const AMES := 200.0

const Principal = preload("res://jeu/principal.gd")
const Profil = preload("res://jeu/profil.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const PanneauLabo = preload("res://jeu/ville/panneau_labo.tscn")

var app: Node
var ville: Node
var _verifs := 0
var _rouges := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", DOSSIER) # AVANT d'instancier quoi que ce soit
	_derouler()

func _ok(vrai: bool, quoi: String) -> void:
	_verifs += 1
	if vrai:
		print("  ok    — ", quoi)
	else:
		_rouges += 1
		print("  ROUGE — ", quoi)

func _images(n: int = 3) -> void:
	for i in n:
		await process_frame

func _derouler() -> void:
	var vrai_avant := FileAccess.get_modified_time(VRAI_PROFIL)
	_preparer()
	app = Principal.new()
	root.add_child(app)
	await _images()
	_ok(Profil.chemin(Profil.FICHIER).begins_with(DOSSIER), "le profil d'essai vit dans %s" % DOSSIER)
	_ok(app.vues.has("ville"), "le programme principal a monté la Ville")
	if not app.vues.has("ville"):
		_finir(vrai_avant)
		return
	ville = app.vues.ville
	_ok(not ville.visible, "la Ville est cachée à l'écran titre")
	app.ouvrir_ville()
	await _images()
	_ok(ville.visible, "la Ville s'affiche quand app.ecran == « ville »")
	await _onglets()
	await _classe()
	await _deplacement()
	await _sanctuaire()
	await _sans_ames()
	await _emplacements()
	await _coffre()
	await _labo()
	await _doigt()
	await _portail()
	_finir(vrai_avant)

func _finir(vrai_avant: int) -> void:
	_ok(FileAccess.get_modified_time(VRAI_PROFIL) == vrai_avant, "le vrai profil du joueur n'a pas été touché")
	print("%d vérifications, %d rouges" % [_verifs, _rouges])
	print("RESULT: %s" % ("PASS" if _rouges == 0 else "FAIL"))
	quit(0 if _rouges == 0 else 1)

## Profil d'essai : avancé (coffre garni, checkpoints, Gardiens), mais UNE seule classe possédée.
func _preparer() -> void:
	ProfilEssai.effacer()
	var tuning: Dictionary = D6Data.create_tuning()
	var p: Dictionary = ProfilEssai.riche(tuning, AMES)
	p.unlocked.classes = [tuning.classes.keys()[0]]
	ProfilEssai.ecrire(p)

# ---------------------------------------------------------------- outils

## Le bouton d'action `action` de la carte `cle` dans l'onglet affiché (null s'il n'existe pas).
func _bouton(cle: String, action: String) -> Button:
	for b in ville.page(ville.onglet).find_children("*", "Button", true, false):
		if String(b.get_meta("cle", "")) == cle and String(b.get_meta("action", action)) == action:
			return b
	return null

## Appuie comme un joueur : un bouton absent ou grisé ne s'appuie pas.
func _appuyer(b: Button) -> bool:
	if b == null or b.disabled or not b.is_visible_in_tree():
		return false
	b.pressed.emit()
	return true

func _texte_visible(texte: String) -> bool:
	for l in ville.page(ville.onglet).find_children("*", "Label", true, false):
		if l.text == texte and l.is_visible_in_tree():
			return true
	return false

## Un texte visible de l'onglet commence par `debut`, sans égard aux majuscules.
func _texte_commence(debut: String) -> bool:
	for l in ville.page(ville.onglet).find_children("*", "Label", true, false):
		if l.text.to_lower().begins_with(debut.to_lower()) and l.is_visible_in_tree():
			return true
	return false

func _ouvrir(id: String) -> void:
	ville.ouvrir_onglet(id)
	await _images()

func _instantane() -> String:
	return JSON.stringify(app.profil)

# ---------------------------------------------------------------- essais

func _onglets() -> void:
	print("[onglets]")
	for id in ville.ONGLETS:
		_appuyer(ville.bouton_onglet(id))
		await _images(2)
		var seule := true
		for autre in ville.ONGLETS:
			seule = seule and ville.page(autre).visible == (autre == id)
		_ok(ville.onglet == id and seule, "onglet « %s » : sa page est la seule affichée" % id)

## Finitions V3 : l'onglet Classe et le Grimoire nomment le DÉPLACEMENT de la classe (dash, saut,
## roulade) et disent ce qu'il fait, avec le texte des données (data/classes.json, `moves`).
func _deplacement() -> void:
	print("[déplacement de classe]")
	await _ouvrir("classe")
	for id in app.contenu.classes:
		var geste: Dictionary = app.contenu.moves[app.contenu.classes[id].move]
		_ok(_texte_visible("Déplacement · %s : %s" % [geste.name, geste.text]), "onglet Classe, %s : « Déplacement · %s » et ce qu'il fait" % [id, geste.name])
	await _ouvrir("grimoire")
	var c: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	var le_sien: Dictionary = app.contenu.moves[c.move]
	_ok(_texte_commence("Déplacement · %s" % c.name) and _texte_visible(le_sien.name) and _texte_visible(le_sien.text), "Grimoire : le déplacement de la classe (« %s ») est nommé et décrit" % le_sien.name)

func _classe() -> void:
	print("[classe]")
	await _ouvrir("classe")
	var premiere: String = app.contenu.classes.keys()[0]
	var id: String = app.contenu.classes.keys()[1]
	var cle := "classes:%s" % id
	var prix: float = D6Profile.unlock_cost(app.contenu, "classes", id)
	_ok(app.profil.loadout.classId == premiere and not app.profil.unlocked.classes.has(id), "départ : %s équipé, %s verrouillé" % [premiere, id])
	_ok(_appuyer(_bouton(cle, "debloquer")), "avec %s Âmes, « Débloquer » (%s) s'appuie" % [D6Js.num_str(AMES), D6Js.num_str(prix)])
	_ok(app.profil.unlocked.classes.has(id) and app.profil.souls == AMES - prix, "débloquer la classe la possède et débite %s Âmes" % D6Js.num_str(prix))
	await _images()
	_ok(_appuyer(_bouton(cle, "choisir")), "la carte propose alors « Choisir »")
	_ok(app.profil.loadout.classId == id, "choisir la classe change app.profil.loadout.classId (%s)" % app.profil.loadout.classId)
	await _images()
	var equipe := _bouton(cle, "")
	_ok(equipe != null and equipe.disabled, "la classe choisie affiche « Équipé », grisé")
	_appuyer(_bouton("classes:%s" % premiere, "choisir"))
	await _images()
	_ok(app.profil.loadout.classId == premiere, "retour à la première classe")

func _sanctuaire() -> void:
	print("[sanctuaire]")
	await _ouvrir("sanctuaire")
	var id := "celerite"
	var niveau: float = D6Js.nz(app.profil.upgrades.get(id), 0.0)
	var prix: float = D6Profile.upgrade_cost(app.contenu, id, niveau)
	var avant: float = app.profil.souls
	_bouton("upgrades:%s" % id, "ameliorer").grab_focus()
	_ok(_appuyer(_bouton("upgrades:%s" % id, "ameliorer")), "« Améliorer » %s s'appuie (%s Âmes en poche, prix %s)" % [id, D6Js.num_str(avant), D6Js.num_str(prix)])
	_ok(app.profil.souls == avant - prix, "l'achat débite le bon prix (%s − %s = %s)" % [D6Js.num_str(avant), D6Js.num_str(prix), D6Js.num_str(app.profil.souls)])
	_ok(D6Js.nz(app.profil.upgrades.get(id), 0.0) == niveau + 1.0, "le niveau de l'amélioration monte d'un cran")
	await _images()
	var tenu := root.gui_get_focus_owner()
	_ok(tenu != null and String(tenu.get_meta("cle", "")) == "upgrades:%s" % id, "après le redessin, le focus (clavier, manette) revient sur la même carte")
	var suivant := InputEventAction.new()
	suivant.action = "ui_page_down"
	suivant.pressed = true
	root.push_input(suivant)
	await _images()
	_ok(ville.onglet == "labo" and root.gui_get_focus_owner() == ville.bouton_onglet("labo"), "Page suivante passe à l'onglet voisin et y porte le focus (onglet : %s)" % ville.onglet)

func _sans_ames() -> void:
	print("[sans Âmes]")
	await _ouvrir("sanctuaire")
	app.profil.souls = 0.0 # le test fabrique sa situation ; la Ville, elle, n'écrit jamais le profil
	app.profil_change.emit()
	await _images()
	var avant := _instantane()
	var achat := _bouton("upgrades:vitalite", "ameliorer")
	_ok(achat != null and achat.disabled, "sans Âmes, « Améliorer » est grisé")
	_ok(not _appuyer(achat) and _instantane() == avant, "…et le profil ne change pas")
	_ok(_texte_visible("Âmes insuffisantes"), "la carte dit pourquoi : « Âmes insuffisantes »")
	await _ouvrir("grimoire")
	var competence: String = app.contenu.classes[app.profil.loadout.classId].skills[1]
	var cle := "skills:%s" % competence
	var deblocage := _bouton(cle, "debloquer")
	_ok(deblocage != null and deblocage.disabled, "sans Âmes, « Débloquer » %s est grisé" % competence)
	# Une opération refusée par les règles (compétence non possédée) : la raison s'affiche, rien ne change.
	ville.page("grimoire").operation_demandee.emit(cle, "select_slot", [0.0, competence])
	await _images()
	_ok(_instantane() == avant, "une opération refusée ne change pas le profil")
	_ok(_texte_visible("Indisponible"), "le refus affiche sa raison sur la carte (« Indisponible »)")
	app.profil.souls = 50.0
	app.profil_change.emit()
	await _images()

## Combat V3 : le Grimoire place les actions dans les TROIS emplacements (opération select_slot).
## On touche une compétence PUIS un emplacement, ou l'inverse ; rien n'est écrit au premier toucher.
func _emplacements() -> void:
	print("[emplacements]")
	await _ouvrir("grimoire")
	var avant: Array = app.profil.loadout.slots.duplicate()
	_ok(avant.size() == 3 and avant[0] != null and avant[1] != null, "le profil porte trois emplacements (%s)" % str(avant))
	var premiere: String = avant[0]
	var cle := "%s:%s" % ["skills" if app.contenu.skills.has(premiere) else "gadgets", premiere]
	var arc: Control = ville.page("grimoire").get_node("%Arc")
	_ok(_bouton("slots:0", "emplacement") == arc.bouton(0) and _bouton("slots:2", "emplacement") == arc.bouton(2), "les trois emplacements sont dessinés en arc, chacun est un bouton")
	_ok(_texte_visible("● EMPLACEMENT 1") or _texte_visible("● Emplacement 1"), "l'action placée dans l'emplacement 1 est marquée « ● Emplacement 1 »")
	# 1. Un emplacement d'abord : l'action qui y est déjà ne s'y replace pas.
	var instantane := _instantane()
	_ok(_appuyer(_bouton("slots:0", "emplacement")), "l'emplacement 1 se touche sur l'arc")
	await _images()
	_ok(_instantane() == instantane and arc.bouton(0).button_pressed, "toucher un emplacement ne change pas le profil : il attend une compétence")
	var deja := _bouton(cle, "")
	_ok(deja != null and deja.disabled and deja.text == "Déjà dans l'emplacement 1", "l'action placée dans l'emplacement 1 : son bouton « Déjà dans l'emplacement 1 » est grisé")
	_ok(_appuyer(_bouton("slots:0", "ligne")), "retoucher l'emplacement 1 (dans la légende) l'oublie")
	await _images()
	_ok(not arc.bouton(0).button_pressed and _bouton(cle, "choisir") != null, "plus rien n'est choisi : la carte propose « Choisir »")
	# 2. Une compétence d'abord, puis l'emplacement 3 : elle y va (échange).
	_ok(_appuyer(_bouton(cle, "choisir")), "« Choisir » la compétence s'appuie")
	await _images()
	_ok(_instantane() == instantane and _bouton(cle, "choisir").text.begins_with("Choisie"), "choisir une compétence ne change pas le profil : elle attend un emplacement (« %s »)" % _bouton(cle, "choisir").text)
	_ok(_appuyer(_bouton("slots:2", "emplacement")), "…et l'emplacement 3 se touche")
	await _images()
	_ok(app.profil.loadout.slots == [avant[2], avant[1], premiere], "compétence puis emplacement 3 : les emplacements 1 et 3 s'échangent (%s)" % str(app.profil.loadout.slots))
	_ok(_bouton(cle, "choisir") != null and _bouton(cle, "choisir").text == "Choisir" and not arc.bouton(2).button_pressed, "le choix est fini : plus rien n'attend")
	_ok(_appuyer(_bouton("slots:2", "vider")), "l'emplacement 3, rempli, a un bouton « Vider »")
	await _images()
	_ok(app.profil.loadout.slots[2] == null and _bouton("slots:2", "vider").disabled, "« Vider » : l'emplacement 3 est vide, et son bouton est grisé")
	# 3. L'inverse : l'emplacement 1 d'abord, puis la compétence.
	_ok(_appuyer(_bouton("slots:0", "ligne")), "l'emplacement 1 (vide) se touche dans la légende")
	await _images()
	_ok(_appuyer(_bouton(cle, "placer")), "l'action, plus placée nulle part, propose « Placer dans l'emplacement 1 »")
	await _images()
	_ok(app.profil.loadout.slots[0] == premiere, "…elle y est")
	var relu: Dictionary = Profil.charger(app.contenu)
	_ok(relu.loadout.slots == app.profil.loadout.slots, "les emplacements sont relus du disque d'essai (%s)" % str(relu.loadout.slots))
	var jeu: Dictionary = app.operation_ville("select_slot", [1.0, avant[1]])
	_ok(jeu.get("ok") == true, "le second emplacement est remis")
	# 4. Un choix à moitié fait ne survit pas à un changement d'onglet.
	_appuyer(_bouton(cle, "choisir"))
	await _images()
	await _ouvrir("classe")
	await _ouvrir("grimoire")
	_ok(_bouton(cle, "choisir") != null and _bouton(cle, "choisir").text == "Choisir", "changer d'onglet oublie un choix à moitié fait")

func _objet_du_coffre(emplacement: String, rarete: String = ""):
	for objet in app.profil.stash:
		if objet.slot == emplacement and (rarete == "" or objet.rarity == rarete):
			return objet
	return null

func _au_coffre(uid) -> bool:
	return app.profil.stash.any(func(o): return o.get("uid") == uid)

func _coffre() -> void:
	print("[coffre]")
	await _ouvrir("coffre")
	var nouveau: Dictionary = _objet_du_coffre("armure")
	var porte: Dictionary = app.profil.equipment.armure
	var taille: int = app.profil.stash.size()
	_ok(_appuyer(_bouton("objet:%s" % nouveau.uid, "equiper")), "« Équiper » une armure du coffre s'appuie")
	_ok(app.profil.equipment.armure.uid == nouveau.uid and _au_coffre(porte.uid) and not _au_coffre(nouveau.uid) and app.profil.stash.size() == taille,
		"l'objet équipé échange sa place avec l'objet porté (%s ⇄ %s)" % [nouveau.name, porte.name])
	await _images()
	# Arme d'une autre classe : bouton grisé ; forcée, l'opération est refusée et dit pourquoi.
	var etrangere = null
	for objet in app.profil.stash:
		if objet.slot == "arme" and not app.contenu.classes[app.profil.loadout.classId].weapons.has(objet.weaponType):
			etrangere = objet
	var cle := "objet:%s" % etrangere.uid
	var avant := _instantane()
	var equiper := _bouton(cle, "equiper")
	_ok(equiper != null and equiper.disabled and equiper.text == "Autre classe", "une arme d'une autre classe (%s) ne s'équipe pas : bouton « Autre classe » grisé" % etrangere.name)
	ville.page("coffre").operation_demandee.emit(cle, "equip_from_stash", [etrangere.uid])
	await _images()
	_ok(_instantane() == avant and _texte_visible("Arme réservée à une autre classe"), "forcée, l'opération est refusée et la carte dit pourquoi")
	# Recyclage : deux appuis (demande, puis confirmation).
	var jete: Dictionary = _objet_du_coffre("talisman", "commun")
	var gain: float = D6Profile.salvage_souls(app.contenu, jete)
	var ames: float = app.profil.souls
	cle = "objet:%s:recycler" % jete.uid
	_appuyer(_bouton(cle, "recycler"))
	await _images()
	_ok(_au_coffre(jete.uid) and app.profil.souls == ames, "premier appui sur « Recycler » : rien n'est détruit, la carte demande confirmation")
	var confirmer := _bouton(cle, "recycler")
	_ok(confirmer != null and confirmer.text.begins_with("Confirmer"), "le bouton devient « %s »" % (confirmer.text if confirmer != null else "?"))
	_appuyer(confirmer)
	_ok(not _au_coffre(jete.uid) and app.profil.souls == ames + gain, "second appui : l'objet est recyclé, +%s Âmes (D6Profile.salvage_souls)" % D6Js.num_str(gain))
	await _images()

func _labo() -> void:
	print("[labo]")
	await _ouvrir("labo")
	var panneau: Node = ville.page("labo").panneau
	_ok(app.reglages.lab.hitstop == "global" and panneau.bouton("hitstop", "global").button_pressed, "départ : D8 sur « Global », bouton enfoncé")
	_ok(_appuyer(panneau.bouton("hitstop", "local")), "l'option D8 « Local » s'appuie")
	_ok(app.reglages.lab.hitstop == "local", "le panneau change app.reglages.lab.hitstop (%s)" % app.reglages.lab.hitstop)
	_ok(panneau.bouton("hitstop", "local").button_pressed and not panneau.bouton("hitstop", "global").button_pressed, "le choix courant se lit sur les boutons")
	# Le même panneau, instancié seul comme le fera l'écran de pause.
	var seul: Node = PanneauLabo.instantiate()
	root.add_child(seul)
	seul.brancher(app, app.partie)
	await _images()
	_ok(seul.bouton("hitstop", "local").button_pressed, "un panneau instancié à part montre le même choix")
	_appuyer(seul.bouton("comboMobility", "fluide"))
	_ok(app.reglages.lab.comboMobility == "fluide" and panneau.bouton("comboMobility", "fluide").button_pressed, "…et les deux panneaux se suivent (D9 « Fluide »)")
	seul.queue_free()
	app.regler_labo("hitstop", "global")
	app.regler_labo("comboMobility", "mobile")
	await _images()

func _toucher(position: Vector2, appui: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = position
	ev.pressed = appui
	root.push_input(ev, true)

## Le doigt, dans les DEUX réglages possibles du projet : souris émulée par le moteur, ou non
## (c'est alors jeu/ville/doigt.gd qui fait l'appui et le défilement).
func _doigt() -> void:
	print("[doigt]")
	await create_timer(0.5).timeout # l'armement de l'écran (0,35 s) est passé
	var reglage := Input.emulate_mouse_from_touch
	print("  réglage du projet : emulate_mouse_from_touch = ", reglage)
	# 1. Émulation par le moteur : un toucher venu de l'écran (Input) presse le bouton.
	Input.emulate_mouse_from_touch = true
	var cible: Vector2 = root.get_final_transform() * ville.bouton_onglet("classe").get_global_rect().get_center()
	for appui in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = cible
		ev.pressed = appui
		Input.parse_input_event(ev)
		await _images(2)
	_ok(ville.onglet == "classe", "souris émulée : toucher l'onglet « Classe » l'ouvre (onglet : %s)" % ville.onglet)
	# 2. Sans émulation : doigt.gd.
	Input.emulate_mouse_from_touch = false
	var centre: Vector2 = ville.bouton_onglet("coffre").get_global_rect().get_center()
	_toucher(centre, true)
	await _images(2)
	_toucher(centre, false)
	await _images()
	_ok(ville.onglet == "coffre", "sans émulation : toucher puis relâcher l'onglet « Coffre » l'ouvre (onglet : %s)" % ville.onglet)
	var liste: ScrollContainer = ville.page("coffre").get_parent().get_parent()
	var avant := _instantane()
	var depart: Vector2 = liste.get_global_rect().get_center()
	_toucher(depart, true)
	await _images(2)
	for i in 6:
		var glisse := InputEventScreenDrag.new()
		glisse.index = 0
		glisse.relative = Vector2(0.0, -20.0)
		glisse.position = depart + Vector2(0.0, -20.0 * (i + 1))
		root.push_input(glisse, true)
		await process_frame
	_toucher(depart + Vector2(0.0, -120.0), false)
	await _images()
	_ok(liste.scroll_vertical > 0, "sans émulation : glisser le doigt fait défiler le coffre (%d px)" % liste.scroll_vertical)
	_ok(_instantane() == avant and ville.onglet == "coffre", "…sans appuyer sur ce qui se trouvait sous le doigt")
	Input.emulate_mouse_from_touch = reglage

func _portail() -> void:
	print("[portail]")
	await _ouvrir("portail")
	var dernier: float = app.profil.checkpoints.max()
	_ok(_appuyer(_bouton("depart:%s" % D6Js.num_str(dernier), "partir")), "« Descendre » (étage %s) s'appuie" % D6Js.num_str(dernier))
	var jeu = app.partie.game
	_ok(app.ecran == "jeu" and jeu != null and jeu.run.floor == dernier and not D6Js.truthy(jeu.get("sandbox")), "une partie démarre à l'étage du dernier checkpoint (%s)" % D6Js.num_str(dernier))
	await _images()
	_ok(not ville.visible, "la Ville se cache pendant la descente")
	await _revenir()
	_appuyer(_bouton("depart:1", "partir"))
	_ok(app.partie.game != null and app.partie.game.run.floor == 1.0, "« Se téléporter » vers l'étage 1 démarre à l'étage 1")
	await _revenir()
	_appuyer(_bouton("arene", "arene"))
	_ok(app.partie.game != null and D6Js.truthy(app.partie.game.get("sandbox")), "« Arène d'essai » démarre une partie sans enjeu")
	await _revenir()
	var modele: String = app.profil.guardians.keys()[1]
	_appuyer(_bouton("gardien:%s" % modele, "gardien"))
	jeu = app.partie.game
	_ok(jeu != null and D6Js.truthy(jeu.get("practice")) and D6Floors.guardian_for(app.contenu, D6Floors.floor_info(app.contenu, jeu.run.floor).section) == modele,
		"« Défier » %s démarre un entraînement à l'étage de ce Gardien" % modele)
	await _revenir()
	var retour: Button = null
	for b in ville.find_children("Retour", "Button", true, false):
		retour = b
	_ok(_appuyer(retour) and app.ecran == "titre", "le bouton de retour ouvre l'écran titre")
	await _images()
	_ok(not ville.visible, "la Ville se cache à l'écran titre")

func _revenir() -> void:
	app.ouvrir_ville()
	await _images()
