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
const Factice = preload("res://jeu/ville/arbre_factice.gd")
const BancArbre = preload("res://jeu/ville/banc_arbre.gd")
const Consignes = preload("res://jeu/interface/consignes.gd")
## Les deux fenêtres où l'écran de l'arbre est éprouvé : le bureau, un petit téléphone en paysage.
const FORMATS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(844, 390)]

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
	await _reperes()
	await _arbre()
	await _medaillons()
	await _manette()
	await _mise_en_page()
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

## Le Grimoire, et ce que les règles rendent de l'arbre de la classe portée.
func _grimoire() -> Node:
	return ville.page("grimoire")

func _visible(c: Control) -> bool:
	return c != null and c.is_visible_in_tree()

func _vue() -> Dictionary:
	return D6Profile.tree_view(app.profil, app.contenu, app.profil.loadout.classId)

func _noeuds() -> Array:
	var tous: Array = []
	for etage in _vue().tiers:
		tous.append_array(etage.nodes)
	return tous

func _noeuds_de_sorte(sorte: String) -> Array:
	return _noeuds().filter(func(n: Dictionary) -> bool: return n.kind == sorte)

func _noeud(id: String) -> Dictionary:
	return _noeuds().filter(func(n: Dictionary) -> bool: return n.id == id)[0]

## Touche le nœud `id` de l'arbre comme un joueur : son médaillon est un bouton, le panneau le montre.
func _choisir(id: String) -> void:
	_appuyer(_grimoire().arbre().bouton(id))
	await _images()

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
	# Écran de l'arbre : le déplacement est le nœud en écusson de l'arbre ; on le touche, le panneau le décrit.
	await _choisir(_noeuds_de_sorte("move")[0].id)
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
	# Combat V3, écran de l'arbre : une compétence ne s'achète plus en Âmes ; verrouillée, c'est son
	# nœud qui la débloque (« Apprendre », grisé tant que son étage est fermé), et elle ne se place pas.
	await _choisir(competence)
	var deblocage := _bouton("arbre:%s" % competence, "plus")
	var prix_en_ames := _grimoire().find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.is_visible_in_tree() and l.text.contains("◆"))
	_ok(deblocage != null and deblocage.disabled and deblocage.text == "Apprendre" and not prix_en_ames, "%s, verrouillée : bouton grisé « Apprendre » dans l'arbre, sans prix en Âmes" % competence)
	_ok(not _visible(_bouton("placer:%s:0" % competence, "placer")), "…et aucun « Placer en » tant qu'elle n'est pas acquise")
	_ok(_bouton(cle, "debloquer") == null or _bouton(cle, "debloquer") == deblocage, "aucun bouton « Débloquer » en Âmes sur une compétence")
	# Une opération refusée par les règles (compétence non possédée) : la raison s'affiche, rien ne change.
	ville.page("grimoire").operation_demandee.emit("placer:%s:0" % competence, "select_slot", [0.0, competence])
	await _images()
	_ok(_instantane() == avant, "une opération refusée ne change pas le profil")
	_ok(_texte_visible("Indisponible"), "le refus affiche sa raison sur le panneau du nœud (« Indisponible »)")
	app.profil.souls = 50.0
	app.profil_change.emit()
	await _images()

## Combat V3, écran de l'arbre : l'ARBRE DE COMPÉTENCES au Grimoire. Niveau, expérience, points ;
## un médaillon par nœud, dont le panneau porte « Apprendre » / « Améliorer » (grisé avec sa raison) ;
## les deux améliorations exclusives au rang du choix, prises en DEUX appuis (confirmation) ;
## « Tout rendre » en deux appuis. Tout passe par les boutons (tree_buy, tree_choose, tree_respec).
func _arbre() -> void:
	print("[arbre]")
	await _ouvrir("grimoire")
	var classe: String = app.profil.loadout.classId
	var c: Dictionary = app.contenu.classes[classe]
	var depart: String = c.skills[0]
	var arbre: Control = _grimoire().arbre()
	var v: Dictionary = _vue()
	var pastille: Control = _grimoire().get_node("%PastillePoints")
	_ok(v.points > 0.0 and _texte_visible("Niveau %s / %s" % [D6Js.num_str(v.level), D6Js.num_str(v.maxLevel)]), "le niveau de la classe est écrit (%s)" % D6Js.num_str(v.level))
	_ok(pastille.is_visible_in_tree() and pastille.nombre == int(v.points) and _texte_commence("point"), "les points à dépenser sont écrits (%s)" % D6Js.num_str(v.points))
	_ok(ville.bouton_onglet("grimoire").text == ville.REPERE_POINTS, "l'onglet Grimoire porte le repère des points à dépenser")
	for etage in v.tiers:
		_ok(_texte_visible(String(etage.name).to_upper()), "l'étage « %s » est titré" % etage.name)
		for n in etage.nodes:
			await _choisir(n.id)
			var plus := _bouton("arbre:%s" % n.id, "plus")
			_ok(_visible(arbre.bouton(n.id)) and _visible(plus) and plus.disabled == (not n.canBuy), "%s : un médaillon, et son bouton d'achat %s" % [n.id, "offert" if n.canBuy else "grisé (%s)" % n.reason])
	await _choisir(c.skills[1])
	var ferme := _bouton("arbre:%s" % c.skills[1], "plus")
	_ok(ferme != null and ferme.disabled and _texte_commence("Étage %s fermé" % v.tiers[1].name), "étage fermé : achat grisé, le panneau dit pourquoi")
	await _choisir(depart)
	var premier: String = v.tiers[0].nodes.filter(func(n: Dictionary) -> bool: return n.id == depart)[0].choices[0].id
	_ok(_bouton("arbre:%s:%s" % [depart, premier], "choix:%s" % premier) == null, "avant le rang du choix, aucune amélioration ne se prend")
	# « Améliorer » jusqu'au rang du choix : le rang monte, les points descendent, les deux améliorations s'offrent.
	for i in int(v.choiceRank) - 1:
		_ok(_appuyer(_bouton("arbre:%s" % depart, "plus")), "« Améliorer » sur %s s'appuie" % depart)
		await _images()
	var apres: Dictionary = _vue()
	_ok(apres.points == v.points - (v.choiceRank - 1.0) and _texte_visible("Rang %s / %s" % [D6Js.num_str(v.choiceRank), D6Js.num_str(_noeud(depart).maxRank)]), "rang %s : écrit sur le panneau, un point par rang" % D6Js.num_str(v.choiceRank))
	await _choix_exclusif(classe, depart)
	await _tout_rendre(classe, v)

## Les deux améliorations exclusives : offertes au rang du choix ; un premier appui demande
## confirmation (rien n'est pris), le second prend ; l'autre est alors barrée.
func _choix_exclusif(classe: String, depart: String) -> void:
	var arbre: Control = _grimoire().arbre()
	var choix: Array = _noeud(depart).choices
	var cles: Array = choix.map(func(ch: Dictionary) -> String: return "arbre:%s:%s" % [depart, ch.id])
	var a := _bouton(cles[0], "choix:%s" % choix[0].id)
	var b := _bouton(cles[1], "choix:%s" % choix[1].id)
	_ok(a != null and b != null and not a.disabled and not b.disabled, "les deux améliorations exclusives sont offertes")
	_ok(arbre.etats_des_choix(depart) == ["offerte", "offerte"], "…et dessinées offertes sous le médaillon")
	var avant := _instantane()
	_ok(_appuyer(a), "« Choisir » %s s'appuie" % choix[0].name)
	await _images()
	a = _bouton(cles[0], "choix:%s" % choix[0].id)
	_ok(_instantane() == avant and a != null and a.text == "Confirmer" and _texte_visible("Ce choix est définitif, sauf à tout rendre."), "premier appui : rien n'est pris, le bouton devient « Confirmer » et dit que le choix est définitif")
	await _choisir(app.contenu.classes[classe].skills[1])
	await _choisir(depart)
	a = _bouton(cles[0], "choix:%s" % choix[0].id)
	_ok(_instantane() == avant and a != null and a.text == "Choisir", "regarder un autre nœud oublie la confirmation en attente")
	_appuyer(a)
	await _images()
	_ok(_appuyer(_bouton(cles[0], "choix:%s" % choix[0].id)), "« %s » se prend (second appui)" % choix[0].name)
	await _images()
	_ok(app.profil.tree[classe].choices.get(depart) == choix[0].id, "elle est au profil")
	_ok(_bouton(cles[0], "choix:%s" % choix[0].id) == null and _texte_commence("● %s" % choix[0].name), "prise : marquée, son bouton disparaît")
	b = _bouton(cles[1], "choix:%s" % choix[1].id)
	_ok(b == null and _texte_commence("✕ %s" % choix[1].name) and arbre.etats_des_choix(depart) == ["prise", "barree"], "l'autre est barrée, sans bouton : c'est l'une OU l'autre")
	var forcee: Dictionary = app.operation_ville("tree_choose", [classe, depart, choix[1].id])
	_ok(not D6Js.truthy(forcee.get("ok")) and app.profil.tree[classe].choices.get(depart) == choix[0].id, "…et, forcée, les règles la refusent (%s)" % forcee.get("reason"))
	await _images()

## Tout rendre : deux appuis, de l'or, tous les points.
func _tout_rendre(classe: String, v: Dictionary) -> void:
	var rendre: Button = ville.page("grimoire").get_node("%Rendre")
	var bourse: float = app.profil.gold
	var prix: float = D6Profile.tree_view(app.profil, app.contenu, classe).respecCost
	_ok(rendre.text == "Tout rendre (%s or)" % D6Js.num_str(prix) and not rendre.disabled, "« Tout rendre » dit son prix (%s or)" % D6Js.num_str(prix))
	_appuyer(rendre)
	await _images()
	_ok(app.profil.gold == bourse and rendre.text.begins_with("Confirmer"), "premier appui : rien n'est rendu, le bouton demande confirmation")
	_appuyer(rendre)
	await _images()
	var rendu: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	_ok(app.profil.gold == bourse - prix and rendu.points == v.points and rendu.spent == 0.0 and app.profil.tree[classe].choices.is_empty(), "second appui : %s or payés, tous les points reviennent" % D6Js.num_str(prix))
	_ok(rendre.disabled, "plus rien à rendre : le bouton est grisé")

## Combat V3 : le Grimoire place les actions dans les TROIS emplacements (opération select_slot).
## On choisit une compétence de l'arbre PUIS « Placer en N », ou un emplacement de l'arc puis la
## compétence ; rien n'est écrit au premier toucher.
func _emplacements() -> void:
	print("[emplacements]")
	await _ouvrir("grimoire")
	var avant: Array = app.profil.loadout.slots.duplicate()
	_ok(avant.size() == 3 and avant[0] != null and avant[1] != null, "le profil porte trois emplacements (%s)" % str(avant))
	var premiere: String = avant[0]
	var arc: Control = ville.page("grimoire").get_node("%Arc")
	_ok(_bouton("slots:0", "emplacement") == arc.bouton(0) and _bouton("slots:2", "emplacement") == arc.bouton(2), "les trois emplacements sont dessinés en arc, chacun est un bouton")
	await _choisir(premiere)
	_ok(_texte_visible("● EMPLACEMENT 1") or _texte_visible("● Emplacement 1"), "l'action placée dans l'emplacement 1 est marquée « ● Emplacement 1 »")
	# 1. Un emplacement d'abord : l'action qui y est déjà ne s'y replace pas.
	var instantane := _instantane()
	_ok(_appuyer(_bouton("slots:0", "emplacement")), "l'emplacement 1 se touche sur l'arc")
	await _images()
	_ok(_instantane() == instantane and arc.bouton(0).button_pressed, "toucher un emplacement ne change pas le profil : il attend une compétence")
	_ok(_visible(_bouton("slots:0", "vider")) and _texte_visible("Emplacement 1") and _texte_visible(_noeud(premiere).name), "le panneau montre l'emplacement : ce qu'il porte, et « Vider »")
	_grimoire().selectionner(premiere) # le focus passe sur son nœud, sans appui
	await _images()
	var deja := _bouton("placer:%s:0" % premiere, "placer")
	_ok(_visible(deja) and deja.disabled and deja.tooltip_text == "Déjà dans l'emplacement 1", "l'action placée dans l'emplacement 1 : son bouton « Placer en 1 » est grisé (« Déjà dans l'emplacement 1 »)")
	_ok(_appuyer(arc.bouton(0)), "retoucher l'emplacement 1 (sur l'arc) l'oublie")
	await _images()
	_ok(not arc.bouton(0).button_pressed and not _visible(_bouton("slots:0", "vider")) and _visible(_bouton("placer:%s:1" % premiere, "placer")), "plus rien n'est choisi : le panneau propose de nouveau « Placer en »")
	# 2. Une compétence d'abord, puis « Placer en 3 » : elle y va (échange).
	await _choisir(premiere)
	_ok(_instantane() == instantane and _visible(_bouton("placer:%s:2" % premiere, "placer")), "choisir une compétence ne change pas le profil : le panneau offre « Placer en 1 / 2 / 3 »")
	_ok(_appuyer(_bouton("placer:%s:2" % premiere, "placer")), "…et « Placer en 3 » s'appuie")
	await _images()
	_ok(app.profil.loadout.slots == [avant[2], avant[1], premiere], "compétence puis emplacement 3 : les emplacements 1 et 3 s'échangent (%s)" % str(app.profil.loadout.slots))
	_ok(_bouton("placer:%s:2" % premiere, "placer").disabled and _texte_visible("● Emplacement 3") and not arc.bouton(2).button_pressed, "le choix est fini : plus rien n'attend")
	_appuyer(arc.bouton(2))
	await _images()
	_ok(_appuyer(_bouton("slots:2", "vider")), "l'emplacement 3, rempli, a un bouton « Vider »")
	await _images()
	_ok(app.profil.loadout.slots[2] == null and _bouton("slots:2", "vider").disabled, "« Vider » : l'emplacement 3 est vide, et son bouton est grisé")
	# 3. L'inverse : l'emplacement 1 d'abord, puis la compétence.
	_ok(_appuyer(arc.bouton(0)), "l'emplacement 1 (vide) se touche sur l'arc")
	await _images()
	_ok(_appuyer(_grimoire().arbre().bouton(premiere)), "l'action, plus placée nulle part, se touche dans l'arbre")
	await _images()
	_ok(app.profil.loadout.slots[0] == premiere, "…elle y est")
	var relu: Dictionary = Profil.charger(app.contenu)
	_ok(relu.loadout.slots == app.profil.loadout.slots, "les emplacements sont relus du disque d'essai (%s)" % str(relu.loadout.slots))
	var jeu: Dictionary = app.operation_ville("select_slot", [1.0, avant[1]])
	_ok(jeu.get("ok") == true, "le second emplacement est remis")
	# 4. Un choix à moitié fait ne survit pas à un changement d'onglet.
	_appuyer(arc.bouton(1))
	await _images()
	await _ouvrir("classe")
	await _ouvrir("grimoire")
	_ok(not arc.bouton(1).button_pressed and not _visible(_bouton("slots:1", "vider")), "changer d'onglet oublie un choix à moitié fait")

# ---------------------------------------------------------------- écran de l'arbre (vérifications ajoutées)

## Repères des points à dépenser : la pastille de l'onglet Grimoire dit combien ; la consigne de
## l'accueil se montre en Ville (pas dans le Grimoire) tant qu'aucun point n'a été dépensé.
func _reperes() -> void:
	print("[repères des points]")
	await _ouvrir("classe")
	var points: float = D6Profile.tree_points(app.profil, app.contenu, app.profil.loadout.classId)
	var consigne: Control = ville.get_node("Racine/Marges/Cadre/Colonne/Consigne")
	_ok(points >= 2.0 and ville.pastille().is_visible_in_tree() and ville.pastille().nombre == int(points), "l'onglet Grimoire porte une pastille au nombre de points (%s)" % D6Js.num_str(points))
	_ok(consigne.is_visible_in_tree() and consigne.get_node("Texte").text == "Dépense tes points au Grimoire", "premier point disponible en Ville : la consigne « Dépense tes points au Grimoire »")
	_ok(Consignes.texte_en_ville("grimoire", 1.0) == "Dépense ton point au Grimoire", "…« ton point » quand il n'y en a qu'un")
	await _ouvrir("grimoire")
	_ok(not consigne.is_visible_in_tree(), "dans le Grimoire, la consigne se tait (l'arbre parle)")
	var depart: String = app.contenu.classes[app.profil.loadout.classId].skills[0]
	await _choisir(depart)
	_appuyer(_bouton("arbre:%s" % depart, "plus"))
	await _images()
	await _ouvrir("classe")
	_ok(not consigne.is_visible_in_tree() and app.reglages.accueil.acquis.has("grimoire") and Profil.charger_reglages().accueil.acquis.has("grimoire"), "un point dépensé : la consigne est acquise, retenue sur le disque d'essai, et ne revient pas")
	_ok(ville.pastille().nombre == int(points) - 1, "la pastille suit les points restants (%d)" % ville.pastille().nombre)
	app.regler("accueil", {"actif": false, "acquis": []})
	await _images()
	app.profil_change.emit()
	await _images()
	_ok(not consigne.is_visible_in_tree(), "consignes coupées (réglage de la pause) : elle ne se montre pas")
	app.regler("accueil", {"actif": true, "acquis": ["grimoire"]})
	app.operation_ville("tree_respec", [String(app.profil.loadout.classId)])
	app.profil.gold = 312.0
	app.profil_change.emit()
	await _images()

func _etat_attendu(n: Dictionary, ouvert: bool) -> String:
	if n.next == "":
		return "max"
	if n.canBuy:
		return "achetable"
	if not ouvert:
		return "ferme"
	return "acquis" if n.rank > 0.0 else "attente"

func _choix_attendus(n: Dictionary) -> Array:
	var une_prise: bool = n.choices.any(func(ch: Dictionary) -> bool: return ch.taken)
	return n.choices.map(func(ch: Dictionary) -> String: return "prise" if ch.taken else ("barree" if une_prise else ("offerte" if ch.canTake else "attente")))

## Chaque nœud de tree_view a son médaillon, pour les trois classes et cinq états de l'arbre ;
## l'état DESSINÉ (médaillon, améliorations) est celui que rendent les règles ; un bouton grisé
## dit la raison des règles ; un refus des règles s'affiche.
func _medaillons() -> void:
	print("[médaillons]")
	await _ouvrir("grimoire")
	var page := _grimoire()
	var arbre: Control = page.arbre()
	var vus := {"noeud": {}, "choix": {}}
	for classe: String in app.contenu.classes:
		for etat in ["vide", "points", "choix", "moitie", "plein"]:
			var p: Dictionary = ProfilEssai.riche(app.contenu)
			D6Profile.select_class(p, app.contenu, classe)
			BancArbre.garnir(p, app.contenu, etat)
			var v: Dictionary = D6Profile.tree_view(p, app.contenu, classe)
			page.vue_forcee = v
			app.profil_change.emit()
			await _images()
			var faux: Array = []
			var nombre := 0
			for etage in v.tiers:
				for n in etage.nodes:
					nombre += 1
					var attendu := _etat_attendu(n, etage.open)
					vus.noeud[attendu] = true
					for e in _choix_attendus(n):
						vus.choix[e] = true
					if not _visible(arbre.bouton(n.id)) or arbre.etat_de(n.id) != attendu or arbre.etats_des_choix(n.id) != _choix_attendus(n):
						faux.append(n.id)
			_ok(faux.is_empty() and arbre.ids().size() == nombre, "%s, arbre « %s » : %d nœuds, %d médaillons, chacun dans l'état rendu par les règles %s" % [classe, etat, nombre, arbre.ids().size(), faux])
	_ok(vus.noeud.size() == 5 and vus.choix.size() == 4, "les cinq états d'un médaillon %s et les quatre d'une amélioration %s ont tous été dessinés" % [vus.noeud.keys(), vus.choix.keys()])
	page.vue_forcee = {}
	app.profil_change.emit()
	await _images()
	var classe_portee: String = app.profil.loadout.classId
	for n in _noeuds().filter(func(x: Dictionary) -> bool: return not x.canBuy).slice(0, 3):
		await _choisir(n.id)
		_ok(_texte_visible(n.reason.left(1).to_upper() + n.reason.substr(1)), "%s, grisé : le panneau donne la raison des règles (« %s »)" % [n.id, n.reason])
	var ferme: Dictionary = _vue().tiers[1].nodes[0]
	var avant := _instantane()
	await _choisir(ferme.id)
	page.operation_demandee.emit("arbre:%s" % ferme.id, "tree_buy", [classe_portee, ferme.id])
	await _images()
	var refus: Label = page.get_node("%Refus")
	_ok(_instantane() == avant and refus.is_visible_in_tree() and refus.text.to_lower() == String(ferme.reason).to_lower(), "un achat refusé par les règles ne change rien et affiche leur raison (« %s »)" % refus.text)

func _touche(code: Key) -> void:
	for appui in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = appui
		root.push_input(ev)
		await process_frame

func _id_du_focus() -> String:
	var tenu := root.gui_get_focus_owner()
	return String(tenu.get_meta("cle", "")).trim_prefix("noeud:") if tenu != null and String(tenu.get_meta("action", "")) == "noeud" else ""

## Clavier et manette : le focus passe de nœud en nœud et les atteint tous ; Entrée sur un nœud
## mène au bouton du panneau, Entrée encore achète ; Échap revient au nœud sans quitter la Ville.
func _manette() -> void:
	print("[clavier, manette]")
	await _ouvrir("grimoire")
	var arbre: Control = _grimoire().arbre()
	var ids: Array = arbre.ids()
	var vus := {ids[0]: true}
	var file: Array = [ids[0]]
	while not file.is_empty():
		var b: Button = arbre.bouton(file.pop_back())
		for cote in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var voisin := b.get_node_or_null(b.get_focus_neighbor(cote)) if not b.get_focus_neighbor(cote).is_empty() else null
			var id := String(voisin.get_meta("cle", "")).trim_prefix("noeud:") if voisin != null and String(voisin.get_meta("action", "")) == "noeud" else ""
			if id != "" and not vus.has(id):
				vus[id] = true
				file.append(id)
	_ok(vus.size() == ids.size(), "de voisin en voisin, le focus atteint chaque nœud (%d sur %d)" % [vus.size(), ids.size()])
	var etages: Array = _vue().tiers
	arbre.bouton(etages[0].nodes[0].id).grab_focus()
	await _images()
	await _touche(KEY_RIGHT)
	_ok(_id_du_focus() == etages[0].nodes[1].id and _grimoire().selection() == etages[0].nodes[1].id and _texte_visible(etages[0].nodes[1].name), "flèche droite : le focus passe au nœud voisin, le panneau le montre (%s)" % _id_du_focus())
	await _touche(KEY_DOWN)
	_ok(etages[1].nodes.any(func(n: Dictionary) -> bool: return n.id == _id_du_focus()), "flèche bas : le focus descend à l'étage suivant (%s)" % _id_du_focus())
	await _touche(KEY_UP)
	await _touche(KEY_LEFT)
	var premier: Dictionary = etages[0].nodes[0]
	_ok(_id_du_focus() == premier.id and premier.canBuy, "haut puis gauche : retour au premier nœud (%s), où un point peut être dépensé" % _id_du_focus())
	await _touche(KEY_ENTER)
	var achat := _bouton("arbre:%s" % premier.id, "plus")
	_ok(root.gui_get_focus_owner() == achat, "Entrée sur le nœud : le focus passe au bouton « %s » du panneau" % achat.text)
	await _touche(KEY_ENTER)
	await _images()
	_ok(_noeud(premier.id).rank == premier.rank + 1.0, "Entrée sur le bouton : un rang de plus (%s)" % D6Js.num_str(_noeud(premier.id).rank))
	await _touche(KEY_ESCAPE)
	_ok(_id_du_focus() == premier.id and app.ecran == "ville", "Échap depuis le panneau : le focus revient au nœud, la Ville reste ouverte")
	app.operation_ville("tree_respec", [String(app.profil.loadout.classId)])
	app.profil.gold = 312.0
	app.profil_change.emit()
	await _images()

## Mise en page : les VRAIS arbres des trois classes, puis de 3 à 8 nœuds par étage (arbre factice), en 1280 × 720 et en 844 × 390, aucun
## médaillon n'en touche un autre et tout tient dans la largeur ; en 1280 × 720 tout l'arbre tient
## SANS défiler ; en 844 × 390 seul l'arbre défile, de haut en bas, et le panneau reste à l'écran.
func _mise_en_page() -> void:
	print("[mise en page]")
	await _ouvrir("grimoire")
	var page := _grimoire()
	var vue: Dictionary = _vue()
	var depart: Vector2i = root.size
	for format: Vector2i in FORMATS:
		root.size = format
		await _images(4)
		for classe: String in app.contenu.classes:
			var p: Dictionary = ProfilEssai.riche(app.contenu)
			D6Profile.select_class(p, app.contenu, classe)
			BancArbre.garnir(p, app.contenu, "plein")
			page.vue_forcee = D6Profile.tree_view(p, app.contenu, classe)
			app.profil_change.emit()
			await _images(4)
			_verifier_la_page(format, "l'arbre du jeu, %s" % classe)
		for n in range(3, 9):
			page.vue_forcee = Factice.gonfler(vue, n)
			app.profil_change.emit()
			await _images(4)
			_verifier_la_page(format, "%d nœuds par étage" % n)
	page.vue_forcee = {}
	root.size = depart
	app.profil_change.emit()
	await _images(4)

func _verifier_la_page(format: Vector2i, cas: String) -> void:
	var page := _grimoire()
	var arbre: Control = page.arbre()
	var defile: ScrollContainer = page.get_node("%Defile")
	var corps: ScrollContainer = page.get_parent().get_parent()
	var ecran: Rect2 = root.get_visible_rect().grow(0.5)
	var ids: Array = arbre.ids()
	var dedans := Rect2(Vector2.ZERO, arbre.size).grow(0.5)
	var se_touchent := 0
	var debordent := 0
	for i in ids.size():
		var boite: Rect2 = arbre.boite(ids[i])
		debordent += 0 if dedans.encloses(boite) and boite.size.y <= defile.size.y else 1
		for j in range(i + 1, ids.size()):
			se_touchent += 1 if boite.intersects(arbre.boite(ids[j])) else 0
	var nom := "%d × %d, %s" % [format.x, format.y, cas]
	var attendus := 0
	for etage in page.vue_forcee.tiers:
		attendus += etage.nodes.size()
	_ok(ids.size() == attendus and se_touchent == 0 and debordent == 0, "%s : %d médaillons, aucun n'en touche un autre, aucun ne déborde (se touchent %d, débordent %d)" % [nom, ids.size(), se_touchent, debordent])
	var panneau: Rect2 = page.get_node("%Cadre").get_global_rect()
	_ok(ecran.encloses(panneau) and ecran.encloses(defile.get_global_rect()) and not corps.get_v_scroll_bar().visible and defile.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "%s : le panneau de détail et l'arbre sont à l'écran ; la page ne défile pas, l'arbre jamais de côté" % nom)
	if format.y < 480:
		return
	var tous := ids.all(func(id: String) -> bool: return ecran.encloses(arbre.bouton(id).get_global_rect()))
	_ok(arbre.rangees() == page.vue_forcee.tiers.size() and not defile.get_v_scroll_bar().visible and tous, "%s : une rangée par étage, tout l'arbre tient sans défiler (%d rangées)" % [nom, arbre.rangees()])

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
