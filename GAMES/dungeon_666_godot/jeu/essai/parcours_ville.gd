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

## Joueur avancé : classe changée et reprise, arme forgée et prise, objet équipé, objet recyclé,
## compétence débloquée et choisie, amélioration achetée, labo réglé.
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
	await _apprendre_une_competence(etape)
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

func _apprendre_une_competence(etape: String) -> void:
	for id in app.contenu.classes[app.profil.loadout.classId].skills:
		if app.profil.unlocked.skills.has(id) or D6Profile.unlock_cost(app.contenu, "skills", id) > app.profil.souls:
			continue
		await operer(etape, "unlock", ["skills", id])
		await operer(etape, "select_skill", [id])
		t.verifier("%s : la compétence débloquée (%s) est équipée" % [etape, id], app.profil.loadout.skillId == id)
		return
	print("  (note) %s : aucune compétence à débloquer" % etape)
