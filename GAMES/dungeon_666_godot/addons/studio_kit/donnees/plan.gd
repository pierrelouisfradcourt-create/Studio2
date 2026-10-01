class_name StudioPlan
extends RefCounted

## « Game CAD » : le monde d'un jeu vu comme un PLAN d'entités, indépendamment du jeu.
## Chaque jeu fournit un ADAPTATEUR (JSON) qui dit où trouver, dans SES données, l'identifiant,
## le rectangle, les points, les liens et les dépendances de chaque entité. Le kit sait alors :
##   - inspecter  : décrire le plan en clair (ce que Claude lit avant d'agir) ;
##   - vérifier   : hors cadre, chevauchements, liens cassés, dépendances impossibles ;
##   - déplacer   : bouger une entité ET tous ses points d'un même décalage (plus de coordonnées
##                  corrigées une à une dans le code).
##
## Adaptateur (clés) :
##   liste        : clé de la liste d'entités dans le fichier (ex. "zones")
##   id           : clé de l'identifiant (défaut "id")
##   type         : clé du type (optionnel)
##   rect         : clé du rectangle [x, y, l, h] (optionnel)
##   points       : clés de positions qui bougent AVEC l'entité ([x, y] ou [x, y, l, h], chemins a.b permis)
##   liens        : chemins de clés qui désignent d'autres entités (ex. "appelle.chat" n'en est pas une)
##   requiert     : clé de la liste des jetons requis ; produit : clé du jeton produit
##   solides      : types dont les rectangles ne doivent pas se chevaucher ([] = aucun contrôle)
##   suit         : clé qui nomme l'entité que celle-ci SUIT (l'enseigne suit la boutique) : déplacer
##                  la boutique déplace aussi tout ce qui la suit (optionnel)
##   cadre        : [x, y, l, h] de la zone jouable
##   ancres       : clé d'un dictionnaire {nom: [x, y]} de points NOMMÉS de l'entité (défaut « ancres ») :
##                  le quai d'une route, l'entrée d'une machine… Ils bougent avec l'entité.
##   relations    : ce que le monde doit respecter (voir relations.gd) — vérifiées par verifier_plan

const ID_DEFAUT := "id"


## Normalise les entités du fichier selon l'adaptateur -> Array de {id, type, rect, point, requiert, produit, liens}.
## `point` : la première position trouvée parmi adaptateur.points (utile aux entités sans rectangle : un arbre).
static func entites(donnees: Dictionary, adaptateur: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cle_id := String(adaptateur.get("id", ID_DEFAUT))
	for brut in donnees.get(String(adaptateur.get("liste", "")), []):
		if not (brut is Dictionary):
			continue
		var e: Dictionary = brut
		out.append({
			"id": String(e.get(cle_id, "?")),
			"type": String(lire_chemin(e, String(adaptateur.get("type", "")), "")),
			"rect": _rect(lire_chemin(e, String(adaptateur.get("rect", "")), null)),
			"point": _premier_point(e, adaptateur.get("points", [])),
			"ancres": _ancres(e, adaptateur),
			"requiert": _textes(lire_chemin(e, String(adaptateur.get("requiert", "")), [])),
			"produit": _textes(lire_chemin(e, String(adaptateur.get("produit", "")), [])),
			"liens": _liens(e, adaptateur.get("liens", [])),
		})
	return out


## Toutes les fautes du plan, RELATIONS comprises (vide = plan sain). À préférer à verifier().
static func verifier_plan(donnees: Dictionary, adaptateur: Dictionary, jetons_depart: Array = []) -> Array[String]:
	var fautes := verifier(entites(donnees, adaptateur), adaptateur, jetons_depart)
	fautes.append_array(StudioRelations.verifier(donnees, adaptateur))
	return fautes


## Fautes des entités seules (sans les relations, qui ont besoin des données brutes).
static func verifier(ents: Array[Dictionary], adaptateur: Dictionary, jetons_depart: Array = []) -> Array[String]:
	var fautes: Array[String] = []
	fautes.append_array(ids_uniques(ents))
	if adaptateur.has("cadre"):
		fautes.append_array(hors_cadre(ents, _rect(adaptateur["cadre"])))
	fautes.append_array(chevauchements(ents, adaptateur.get("solides", [])))
	fautes.append_array(liens_casses(ents))
	fautes.append_array(dependances(ents, jetons_depart))
	return fautes


static func ids_uniques(ents: Array[Dictionary]) -> Array[String]:
	var fautes: Array[String] = []
	var vus := {}
	for e in ents:
		if vus.has(e["id"]):
			fautes.append("id « %s » en double" % e["id"])
		vus[e["id"]] = true
	return fautes


static func hors_cadre(ents: Array[Dictionary], cadre: Rect2) -> Array[String]:
	var fautes: Array[String] = []
	for e in ents:
		if e["rect"] != null and not cadre.encloses(e["rect"]):
			fautes.append("« %s » déborde du cadre %s : %s" % [e["id"], str(cadre), str(e["rect"])])
		elif e["rect"] == null and e.get("point", null) != null and not cadre.has_point(e["point"]):
			fautes.append("« %s » hors du cadre %s : %s" % [e["id"], str(cadre), str(e["point"])])
	return fautes


## Chevauchements entre entités de types `solides` (liste vide = pas de contrôle).
static func chevauchements(ents: Array[Dictionary], solides: Array) -> Array[String]:
	var fautes: Array[String] = []
	if solides.is_empty():
		return fautes
	var s := ents.filter(func(e: Dictionary) -> bool: return e["rect"] != null and solides.has(e["type"]))
	for i in s.size():
		for j in range(i + 1, s.size()):
			var a: Rect2 = s[i]["rect"]
			var b: Rect2 = s[j]["rect"]
			if a.intersects(b):
				fautes.append("« %s » chevauche « %s » (%.0f px²)" % [s[i]["id"], s[j]["id"], a.intersection(b).get_area()])
	return fautes


static func liens_casses(ents: Array[Dictionary]) -> Array[String]:
	var fautes: Array[String] = []
	var ids := ents.map(func(e: Dictionary) -> String: return e["id"])
	for e in ents:
		for cible in e["liens"]:
			if not ids.has(cible):
				fautes.append("« %s » pointe vers « %s » qui n'existe pas" % [e["id"], cible])
	return fautes


## Simule le déblocage : une entité s'active quand tous ses jetons requis sont disponibles, puis
## produit les siens. Faute si un jeton n'est produit par personne, ou si une entité reste bloquée.
static func dependances(ents: Array[Dictionary], jetons_depart: Array = []) -> Array[String]:
	var fautes: Array[String] = []
	var produits := {}
	for e in ents:
		for j in e["produit"]:
			produits[j] = true
	for e in ents:
		for j in e["requiert"]:
			if not produits.has(j) and not jetons_depart.has(j):
				fautes.append("« %s » requiert « %s » que rien ne produit" % [e["id"], j])
	var dispo := {}
	for j in jetons_depart:
		dispo[j] = true
	var actives := {}
	var progres := true
	while progres:
		progres = false
		for e in ents:
			if actives.has(e["id"]) or not (e["requiert"] as Array).all(func(j: String) -> bool: return dispo.has(j)):
				continue
			actives[e["id"]] = true
			progres = true
			for j in e["produit"]:
				dispo[j] = true
	for e in ents:
		if not actives.has(e["id"]) and fautes.is_empty():
			fautes.append("« %s » ne peut jamais être débloquée (cycle ou jeton manquant)" % e["id"])
	return fautes


## Description en clair, une ligne par entité : ce que Claude lit avant de modifier un plan.
static func inspecter(ents: Array[Dictionary]) -> String:
	var lignes: PackedStringArray = []
	for e in ents:
		var r := "rect %s" % str(e["rect"])
		if e["rect"] == null:
			r = "sans position" if e.get("point", null) == null else "point %s" % str(e["point"])
		var dep := "" if (e["requiert"] as Array).is_empty() else " · requiert %s" % str(e["requiert"])
		var prod := "" if (e["produit"] as Array).is_empty() else " · produit %s" % str(e["produit"])
		var ty := "" if String(e["type"]) == "" else " [%s]" % e["type"]
		var anc := ""
		if not (e.get("ancres", {}) as Dictionary).is_empty():
			var noms: PackedStringArray = []
			for n in e["ancres"]:
				noms.append("%s %s" % [n, str(e["ancres"][n])])
			anc = " · ancres : " + ", ".join(noms)
		lignes.append("%s%s · %s%s%s%s" % [e["id"], ty, r, dep, prod, anc])
	return "\n".join(lignes)


## Décale l'entité `id` : son rect et toutes les positions listées dans adaptateur.points (un point,
## un rect ou une LISTE de points), puis, s'il y a une clé « suit », tout ce qui la suit.
## Modifie `donnees` en place ; retourne false si l'entité est introuvable.
static func deplacer(donnees: Dictionary, adaptateur: Dictionary, id: String, decalage: Vector2) -> bool:
	var liste: Array = donnees.get(String(adaptateur.get("liste", "")), [])
	var cle_id := String(adaptateur.get("id", ID_DEFAUT))
	var cle_suit := String(adaptateur.get("suit", ""))
	var a_bouger: Array = [id]
	var bouges := {}
	while not a_bouger.is_empty():
		var courant := String(a_bouger.pop_front())
		if bouges.has(courant):
			continue
		for brut in liste:
			if not (brut is Dictionary):
				continue
			var e: Dictionary = brut
			if String(e.get(cle_id, "")) == courant:
				_decaler_entite(e, adaptateur, decalage)
				bouges[courant] = true
			elif cle_suit != "" and String(lire_chemin(e, cle_suit, "")) == courant:
				a_bouger.append(String(e.get(cle_id, "")))
	return bouges.has(id)


static func _decaler_entite(e: Dictionary, adaptateur: Dictionary, decalage: Vector2) -> void:
	var chemins: Array = [String(adaptateur.get("rect", ""))]
	chemins.append_array(adaptateur.get("points", []))
	for c in chemins:
		_decaler(e, String(c), decalage)
	var ancres: Variant = lire_chemin(e, String(adaptateur.get("ancres", "ancres")), null)
	if ancres is Dictionary:
		for nom in ancres:
			if ancres[nom] is Array:
				_decaler_point(ancres[nom], decalage)


## Lecture d'un chemin « a.b.c » dans des Dictionary imbriqués.
static func lire_chemin(d: Dictionary, chemin: String, defaut: Variant) -> Variant:
	if chemin == "":
		return defaut
	var ici: Variant = d
	for morceau in chemin.split("."):
		if not (ici is Dictionary) or not (ici as Dictionary).has(morceau):
			return defaut
		ici = ici[morceau]
	return ici


static func _decaler(e: Dictionary, chemin: String, dv: Vector2) -> void:
	var v: Variant = lire_chemin(e, chemin, null)
	if not (v is Array) or (v as Array).is_empty():
		return
	if (v as Array)[0] is Array:  # une liste de points : chacun bouge
		for p in v:
			_decaler_point(p, dv)
		return
	_decaler_point(v, dv)


static func _decaler_point(a: Array, dv: Vector2) -> void:
	if a.size() < 2:
		return
	a[0] = _garder_entier(float(a[0]) + dv.x)
	a[1] = _garder_entier(float(a[1]) + dv.y)


static func _garder_entier(x: float) -> Variant:
	return int(x) if is_equal_approx(x, roundf(x)) else x


static func _rect(v: Variant) -> Variant:
	if v is Array and (v as Array).size() == 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return null


static func _ancres(e: Dictionary, adaptateur: Dictionary) -> Dictionary:
	var out := {}
	var brut: Variant = lire_chemin(e, String(adaptateur.get("ancres", "ancres")), null)
	if brut is Dictionary:
		for nom in brut:
			var v: Variant = brut[nom]
			if v is Array and (v as Array).size() >= 2:
				out[String(nom)] = Vector2(float(v[0]), float(v[1]))
	return out


static func _premier_point(e: Dictionary, chemins: Array) -> Variant:
	for c in chemins:
		var v: Variant = lire_chemin(e, String(c), null)
		if v is Array and (v as Array).size() >= 2 and (v[0] is float or v[0] is int):
			return Vector2(float(v[0]), float(v[1]))
	return null


static func _textes(v: Variant) -> Array:
	if v is String:
		return [] if (v as String) == "" else [v]
	if v is Array:
		return (v as Array).map(func(x: Variant) -> String: return str(x))
	return []


static func _liens(e: Dictionary, chemins: Array) -> Array:
	var out: Array = []
	for c in chemins:
		out.append_array(_textes(lire_chemin(e, String(c), [])))
	return out
