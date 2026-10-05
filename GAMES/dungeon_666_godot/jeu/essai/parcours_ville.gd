extends RefCounted
## Les visites de la Ville du test de parcours (jeu/essai/test_parcours.gd) : chaque onglet est
## ouvert par la vue (`ville.ouvrir_onglet`), chaque opération passe par `app.operation_ville` ou
## `app.regler_labo`, les portes que prennent les boutons. Après chaque opération : l'onglet se
## redessine avec le profil changé (deux images), et le profil du disque d'essai est relu.

const Profil = preload("res://jeu/profil.gd")

const AXE_LABO := "hitstop"
const IMAGES_DE_DESSIN := 2

var t # le test (SceneTree) : verifier(), images(), verifier_disque()
var app: Node
## Opérations ACCEPTÉES, par nom (select_class, unlock, buy_upgrade… et « labo »).
var operations := {}

func _init(test, p_app: Node) -> void:
	t = test
	app = p_app

# ---------------------------------------------------------------- briques

## Ouvre l'onglet : sa page est montrée, seule.
func ouvrir(etape: String, id: String) -> void:
	var ville: Node = app.vues.ville
	ville.ouvrir_onglet(id)
	await t.images(IMAGES_DE_DESSIN)
	var seule: bool = ville.ONGLETS.all(func(autre: String) -> bool: return ville.page(autre).visible == (autre == id))
	t.verifier("%s, onglet %s : sa page est montrée, seule" % [etape, id], ville.visible and ville.onglet == id and seule)

## Une opération de la Ville, attendue acceptée ou refusée ; le disque suit ; l'onglet se redessine.
func operer(etape: String, nom: String, args: Array, acceptee: bool = true) -> Dictionary:
	var res: Dictionary = app.operation_ville(nom, args)
	var ok: bool = D6Js.truthy(res.get("ok"))
	t.verifier("%s : %s %s %s" % [etape, nom, args, "acceptée" if acceptee else "refusée"], ok == acceptee, res)
	if ok:
		operations[nom] = operations.get(nom, 0) + 1
	t.verifier_disque("%s, après %s" % [etape, nom])
	await t.images(IMAGES_DE_DESSIN)
	return res

## Règle l'axe du labo sur une autre variante que la sienne : retenue, écrite sur le disque d'essai.
func regler_le_labo(etape: String) -> void:
	await ouvrir(etape, "labo")
	var options: Array = D6Data.tables().lab.LAB_AXES[AXE_LABO].options.keys()
	var avant: String = app.reglages.lab[AXE_LABO]
	var autre: String = options[(options.find(avant) + 1) % options.size()]
	app.regler_labo(AXE_LABO, autre)
	await t.images(IMAGES_DE_DESSIN)
	var relu: Dictionary = Profil.charger_reglages()
	t.verifier("%s, labo : « %s » retenu et écrit (était « %s »)" % [etape, autre, avant], autre != avant and app.reglages.lab[AXE_LABO] == autre and relu.lab[AXE_LABO] == autre, relu.lab)
	operations["labo"] = operations.get("labo", 0) + 1

## Le bouton de l'onglet Portail qui porte la clé `cle` (« depart:19 », « gardien:cerbere »), ou null.
func bouton_du_portail(cle: String) -> Button:
	for b in app.vues.ville.page("portail").find_children("*", "Button", true, false):
		if String(b.get_meta("cle", "")) == cle and not b.is_queued_for_deletion():
			return b
	return null

## Ce que le Portail PROPOSE : une carte par checkpoint du profil et pas une de plus, « Descendre »
## sur le dernier ; un défi par Gardien rencontré, et pas un de plus.
func verifier_le_portail(etape: String, dernier: float) -> void:
	await ouvrir(etape, "portail")
	for etage in app.profil.checkpoints:
		var b := bouton_du_portail("depart:%s" % D6Js.num_str(etage))
		var texte := "Descendre" if etage == dernier else "Se téléporter"
		t.verifier("%s, portail : l'étage %s est proposé (« %s »)" % [etape, D6Js.num_str(etage), texte], b != null and b.text == texte and b.is_visible_in_tree() and not b.disabled, b.text if b != null else "absent")
	var departs: int = _boutons_du_portail("depart:").size()
	t.verifier("%s, portail : autant de départs que de checkpoints, le dernier est l'étage %s" % [etape, D6Js.num_str(dernier)], departs == app.profil.checkpoints.size() and D6Js.nz(app.profil.checkpoints.max(), 0.0) == dernier, [departs, app.profil.checkpoints])
	var rencontres: Array = app.contenu.boss.keys().filter(func(m: String) -> bool: return D6Js.nz(app.profil.guardians.get(m), 0.0) > 0.0)
	var defis: Array = _boutons_du_portail("gardien:").map(func(b: Button) -> String: return String(b.get_meta("cle")).trim_prefix("gardien:"))
	t.verifier("%s, portail : un défi par Gardien rencontré %s, et eux seuls" % [etape, rencontres], defis == rencontres, defis)

func _boutons_du_portail(prefixe: String) -> Array:
	return app.vues.ville.page("portail").find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return String(b.get_meta("cle", "")).begins_with(prefixe) and not b.is_queued_for_deletion() and b.is_visible_in_tree())

func _premier_du_coffre(filtre: Callable):
	for objet in app.profil.stash:
		if filtre.call(objet):
			return objet
	return null

func _type_arme(objet) -> String:
	return D6Js.nz(objet.get("weaponType"), D6Profile.DEFAULT_WEAPON) if objet is Dictionary else ""

# ---------------------------------------------------------------- les trois visites

## Joueur qui n'a jamais joué : tous les onglets s'ouvrent ; sans Âmes, un achat est REFUSÉ et ne
## change rien ; le labo se règle et se remet.
func visite_du_nouveau_joueur() -> void:
	var etape := "Ville du nouveau joueur"
	for id in app.vues.ville.ONGLETS:
		await ouvrir(etape, id)
	var classes: Array = app.contenu.classes.keys()
	var verrouillee: String = classes.filter(func(c: String) -> bool: return not app.profil.unlocked.classes.has(c))[0]
	await ouvrir(etape, "classe")
	var res: Dictionary = await operer(etape, "unlock", ["classes", verrouillee], false)
	t.verifier(etape + " : le refus dit pourquoi, rien n'est débloqué", String(res.get("reason", "")) != "" and not app.profil.unlocked.classes.has(verrouillee), res)
	await verifier_le_portail(etape, 1.0)
	t.verifier(etape + " : aucun Gardien à défier avant d'en avoir rencontré un", bouton_du_portail("gardien:%s" % app.contenu.guardians.rotation[0]) == null)
	var depart: String = app.reglages.lab[AXE_LABO]
	for i in D6Data.tables().lab.LAB_AXES[AXE_LABO].options.size(): # le tour des variantes
		await regler_le_labo(etape)
	t.verifier(etape + " : le labo est revenu à sa variante de départ", app.reglages.lab[AXE_LABO] == depart, app.reglages.lab)

## Retour d'une première descente : une amélioration si les Âmes le permettent, puis un objet du
## coffre équipé et l'ancien repris (équiper / ranger).
func visite_apres_la_descente() -> void:
	var etape := "Ville après la descente"
	for id in app.vues.ville.ONGLETS:
		await ouvrir(etape, id)
	await ouvrir(etape, "sanctuaire")
	await _acheter_une_amelioration(etape)
	await ouvrir(etape, "coffre")
	await _equiper_et_reprendre(etape)
	await _depenser_un_point(etape)

## Joueur avancé : classe changée et reprise, arme forgée et prise, objet équipé, objet recyclé,
## arbre de compétences (rangs, amélioration exclusive, compétence débloquée et placée, tout rendu),
## amélioration achetée, labo réglé.
func visite_du_joueur_avance() -> void:
	var etape := "Ville du joueur avancé"
	await ouvrir(etape, "portail")
	await ouvrir(etape, "classe")
	var depart: String = app.profil.loadout.classId
	for id in app.contenu.classes.keys() + [depart]:
		await choisir_la_classe(etape, id)
	await ouvrir(etape, "armurerie")
	await _forger_et_prendre(etape)
	await ouvrir(etape, "coffre")
	await _equiper_et_reprendre(etape)
	await _recycler(etape)
	await ouvrir(etape, "grimoire")
	await _arbre_du_joueur_avance(etape)
	await ouvrir(etape, "sanctuaire")
	await _acheter_une_amelioration(etape)
	await regler_le_labo(etape)

# ---------------------------------------------------------------- opérations

func choisir_la_classe(etape: String, id: String) -> void:
	await operer(etape, "select_class", [id])
	var armes: Array = app.contenu.classes[id].weapons
	t.verifier("%s : classe %s portée, avec une arme à elle" % [etape, id], app.profil.loadout.classId == id and armes.has(_type_arme(app.profil.equipment.get("arme"))), app.profil.equipment.get("arme"))

func _acheter_une_amelioration(etape: String) -> void:
	for id in app.contenu.town.upgrades:
		var niveau: float = D6Js.nz(app.profil.upgrades.get(id), 0.0)
		var prix = D6Profile.upgrade_cost(app.contenu, id, niveau)
		if prix == null or prix > app.profil.souls:
			continue
		var ames: float = app.profil.souls
		await operer(etape, "buy_upgrade", [id])
		t.verifier("%s : %s monte d'un niveau, les Âmes sont payées" % [etape, id], app.profil.upgrades.get(id) == niveau + 1.0 and app.profil.souls == ames - prix, app.profil.souls)
		return
	print("  (note) %s : aucune amélioration à la portée de %s Âmes" % [etape, D6Js.num_str(app.profil.souls)])

## Équipe une armure ou un talisman du coffre (l'objet porté y prend sa place), puis reprend l'ancien.
func _equiper_et_reprendre(etape: String) -> void:
	var objet = _premier_du_coffre(func(o: Dictionary) -> bool: return o.slot != "arme" and app.profil.equipment.get(o.slot) != null)
	if objet == null:
		print("  (note) %s : rien à équiper au coffre (%d objet(s))" % [etape, app.profil.stash.size()])
		return
	var ancien: Dictionary = app.profil.equipment[objet.slot]
	await operer(etape, "equip_from_stash", [objet.uid])
	var range_: bool = app.profil.stash.any(func(o: Dictionary) -> bool: return o.get("uid") == ancien.get("uid"))
	t.verifier("%s : l'objet du coffre est porté, l'ancien est rangé" % etape, app.profil.equipment[objet.slot].uid == objet.uid and range_)
	await operer(etape, "equip_from_stash", [ancien.uid])
	t.verifier("%s : l'ancien objet est repris" % etape, app.profil.equipment[objet.slot].uid == ancien.uid)

func _recycler(etape: String) -> void:
	var objet = _premier_du_coffre(func(o: Dictionary) -> bool: return o.slot == "talisman")
	if objet == null:
		return
	var ames: float = app.profil.souls
	var taille: int = app.profil.stash.size()
	await operer(etape, "salvage_from_stash", [objet.uid])
	t.verifier("%s : l'objet recyclé quitte le coffre et rend ses Âmes" % etape, app.profil.stash.size() == taille - 1 and app.profil.souls == ames + D6Profile.salvage_souls(app.contenu, objet))

## Forge le premier type d'arme de la classe encore verrouillé, puis prend l'exemplaire forgé.
func _forger_et_prendre(etape: String) -> void:
	for type in app.contenu.classes[app.profil.loadout.classId].weapons:
		if app.profil.unlocked.weapons.has(type) or D6Profile.unlock_cost(app.contenu, "weapons", type) > app.profil.souls:
			continue
		await operer(etape, "unlock", ["weapons", type])
		var forgee = _premier_du_coffre(func(o: Dictionary) -> bool: return o.slot == "arme" and _type_arme(o) == type)
		t.verifier("%s : l'arme forgée (%s) attend au coffre" % [etape, type], forgee != null)
		if forgee != null:
			await operer(etape, "equip_from_stash", [forgee.uid])
			t.verifier("%s : l'arme forgée est portée" % etape, _type_arme(app.profil.equipment.arme) == type)
		return
	print("  (note) %s : aucune arme à forger" % etape)

func _bouton_du_grimoire(cle: String, action: String) -> Button:
	for b in app.vues.ville.page("grimoire").find_children("*", "Button", true, false):
		if String(b.get_meta("cle", "")) == cle and String(b.get_meta("action", "")) == action:
			return b
	return null

func _noeud(classe: String, id: String) -> Dictionary:
	for etage in D6Profile.tree_view(app.profil, app.contenu, classe).tiers:
		for n in etage.nodes:
			if n.id == id:
				return n
	return {}

## Retour d'une première descente : la classe a gagné des niveaux (et le point du Gardien). Le
## joueur ouvre le Grimoire et dépense un point par le bouton « + » de sa compétence de départ.
func _depenser_un_point(etape: String) -> void:
	var ville: Node = app.vues.ville
	var classe: String = app.profil.loadout.classId
	var id: String = app.contenu.classes[classe].skills[0]
	var avant: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	t.verifier("%s : la descente a fait gagner des niveaux et des points (niveau %s, %s points)" % [etape, D6Js.num_str(avant.level), D6Js.num_str(avant.points)], avant.level > 1.0 and avant.points > 0.0)
	t.verifier("%s : l'onglet Grimoire porte le repère des points à dépenser" % etape, ville.bouton_onglet("grimoire").text == ville.REPERE_POINTS, ville.bouton_onglet("grimoire").text)
	await ouvrir(etape, "grimoire")
	var plus := _bouton_du_grimoire("arbre:%s" % id, "plus")
	t.verifier("%s : le bouton « + » de %s est offert" % [etape, id], plus != null and not plus.disabled)
	if plus == null or plus.disabled:
		return
	plus.pressed.emit()
	await t.images(IMAGES_DE_DESSIN + 1)
	t.verifier_disque("%s, après « + »" % etape)
	operations["tree_buy"] = operations.get("tree_buy", 0) + 1
	var apres: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	t.verifier("%s : un point dépensé, %s passe au rang 2" % [etape, id], apres.points == avant.points - 1.0 and _noeud(classe, id).rank == 2.0, [apres.points, _noeud(classe, id).rank])

## Joueur avancé (des points à dépenser) : un étage fermé refuse ; deux rangs de la compétence de
## départ, puis l'une de ses deux améliorations (l'autre est alors refusée) ; un passif ; l'étage
## suivant s'ouvre, une compétence y est débloquée et placée ; enfin tout est rendu contre de l'or.
func _arbre_du_joueur_avance(etape: String) -> void:
	var classe: String = app.profil.loadout.classId
	var c: Dictionary = app.contenu.classes[classe]
	var noeuds: Array = app.contenu.tree.classes[classe].nodes
	var depart: Dictionary = noeuds.filter(func(n: Dictionary) -> bool: return n.id == c.skills[0])[0]
	var passif: Dictionary = noeuds.filter(func(n: Dictionary) -> bool: return n.kind == "passive" and n.tier == 0.0)[0]
	await operer(etape, "tree_buy", [classe, c.skills[1]], false)
	await operer(etape, "tree_choose", [classe, depart.id, depart.choices[0].id], false)
	for i in int(app.contenu.tree.choiceRank) - 1:
		await operer(etape, "tree_buy", [classe, depart.id])
	await operer(etape, "tree_choose", [classe, depart.id, depart.choices[0].id])
	await operer(etape, "tree_choose", [classe, depart.id, depart.choices[1].id], false)
	for i in int(passif.maxRank):
		await operer(etape, "tree_buy", [classe, passif.id])
	await operer(etape, "tree_buy", [classe, c.skills[1]])
	await operer(etape, "select_slot", [2.0, c.skills[1]])
	t.verifier("%s : la compétence débloquée dans l'arbre (%s) est équipée, troisième emplacement" % [etape, c.skills[1]], app.profil.loadout.slots[2] == c.skills[1])
	var bourse: float = app.profil.gold
	var vue: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	await operer(etape, "tree_respec", [classe])
	var rendu: Dictionary = D6Profile.tree_view(app.profil, app.contenu, classe)
	t.verifier("%s : tout rendu contre %s or — points revenus, emplacement de %s vidé" % [etape, D6Js.num_str(vue.respecCost), c.skills[1]], app.profil.gold == bourse - vue.respecCost and rendu.spent == 0.0 and rendu.points == vue.points + vue.spent and app.profil.loadout.slots[2] == null, [app.profil.gold, rendu.points, app.profil.loadout.slots])
