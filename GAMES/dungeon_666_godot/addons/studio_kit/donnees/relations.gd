class_name StudioRelations
extends RefCounted

## Les RELATIONS d'un plan : ce que le monde doit respecter, au-delà des positions.
## « Les distributeurs restent sur la place », « la ville est de l'autre côté de la route ».
## Déclarées dans l'adaptateur Game CAD (clé "relations"), vérifiées par StudioPlan.verifier_plan :
## un déplacement qui en casse une est refusé par cad.gd.
##
## Références (dans les données du plan) :
##   "id.chemin"        une valeur de l'entité id (chemins a.b permis) — ex. "route.demi", "magasin.distributeurs"
##   "id@ancre"         une ancre nommée de l'entité (clé "ancres") — ex. "route@quai"
##   "id.rect.umin"     bords d'un rect [u, v, du, dv] : umin, umax, vmin, vmax
##   "a+b", "a-b"       somme / différence de références ou de nombres — ex. "route.u+route.demi"
## Types :
##   dans  {points, zone, marge?}  chaque point dans la zone ; zone = "id.rect", [x, y, l, h]
##         ou {"bande": "u"|"v", "centre", "demi"}
##   plage {valeurs, entre: [min, max], axe?}  chaque nombre dans [min, max] ; avec « axe » (u|v), les
##         valeurs sont des points (ancre, liste) dont on prend la coordonnée — ex. le v du quai
##   cote  {points, axe: "u"|"v", apres | avant}  chaque point au-delà (>) ou en deçà (<) du seuil
## `points` : une référence (un point ou une liste de points) ou une sélection
##   {"filtre": {clé: valeur…}, "point": chemin} — ex. tous les décors de calque 2, par leur « pied ».


## Fautes (vide = toutes les relations tiennent). Chaque faute commence par le nom de la relation.
static func verifier(donnees: Dictionary, adaptateur: Dictionary) -> Array[String]:
	var fautes: Array[String] = []
	var index := indexer(donnees, adaptateur)
	for r in adaptateur.get("relations", []):
		fautes.append_array(verifier_une(r, index, donnees, adaptateur))
	return fautes


static func verifier_une(r: Dictionary, index: Dictionary, donnees: Dictionary, adaptateur: Dictionary) -> Array[String]:
	var nom := String(r.get("nom", r.get("type", "?")))
	match String(r.get("type", "")):
		"dans":
			return _dans(r, nom, index, donnees, adaptateur)
		"plage":
			return _plage(r, nom, index)
		"cote":
			return _cote(r, nom, index, donnees, adaptateur)
	return ["relation « %s » : type inconnu « %s »" % [nom, r.get("type", "")]] as Array[String]


static func _dans(r: Dictionary, nom: String, index: Dictionary, donnees: Dictionary, adaptateur: Dictionary) -> Array[String]:
	var fautes: Array[String] = []
	var zone: Variant = _zone(r.get("zone", ""), index)
	if zone == null:
		fautes.append("« %s » : zone introuvable %s" % [nom, str(r.get("zone", ""))])
		return fautes
	var z: Rect2 = (zone as Rect2).grow(float(r.get("marge", 0.0)))
	for p in _points(r.get("points", ""), index, donnees, adaptateur):
		if not _contient(z, p["pos"]):
			fautes.append("« %s » : %s %s hors de %s" % [nom, p["nom"], str(p["pos"]), str(r.get("zone", ""))])
	return fautes


static func _plage(r: Dictionary, nom: String, index: Dictionary) -> Array[String]:
	var fautes: Array[String] = []
	var bornes: Array = r.get("entre", [])
	var mini: Variant = nombre(bornes[0], index) if bornes.size() == 2 else null
	var maxi: Variant = nombre(bornes[1], index) if bornes.size() == 2 else null
	if mini == null or maxi == null:
		fautes.append("« %s » : bornes illisibles %s" % [nom, str(bornes)])
		return fautes
	var v: Variant = valeur(String(r.get("valeurs", "")), index)
	if r.has("axe"):
		var k := 0 if String(r["axe"]) == "u" else 1
		v = _en_liste(v).filter(func(p: Variant) -> bool: return _est_point(p)).map(func(p: Array) -> float: return float(p[k]))
	for x in (v if v is Array else [v]):
		if not (x is float or x is int) or float(x) < float(mini) or float(x) > float(maxi):
			fautes.append("« %s » : %s hors de [%s, %s]" % [nom, str(x), str(mini), str(maxi)])
	return fautes


static func _cote(r: Dictionary, nom: String, index: Dictionary, donnees: Dictionary, adaptateur: Dictionary) -> Array[String]:
	var fautes: Array[String] = []
	var apres := r.has("apres")
	var seuil: Variant = nombre(r.get("apres", r.get("avant", null)), index)
	if seuil == null:
		fautes.append("« %s » : seuil illisible" % nom)
		return fautes
	var axe := 0 if String(r.get("axe", "u")) == "u" else 1
	for p in _points(r.get("points", ""), index, donnees, adaptateur):
		var x: float = (p["pos"] as Vector2)[axe]
		if (apres and x <= float(seuil)) or (not apres and x >= float(seuil)):
			fautes.append("« %s » : %s à %s, doit être %s %s" % [nom, p["nom"], str(x), "au-delà de" if apres else "en deçà de", str(seuil)])
	return fautes


## Points désignés : [{nom, pos: Vector2}].
static func _points(ref: Variant, index: Dictionary, donnees: Dictionary, adaptateur: Dictionary) -> Array:
	var out: Array = []
	if ref is Dictionary:
		var filtre: Dictionary = ref.get("filtre", {})
		for e in donnees.get(String(adaptateur.get("liste", "")), []):
			if e is Dictionary and filtre.keys().all(func(k: Variant) -> bool: return e.get(k) == filtre[k]):
				var v: Variant = StudioPlan.lire_chemin(e, String(ref.get("point", "")), null)
				if _est_point(v):
					out.append({"nom": String(e.get(String(adaptateur.get("id", "id")), "?")), "pos": Vector2(float(v[0]), float(v[1]))})
		return out
	var v: Variant = valeur(String(ref), index)
	if v is Dictionary:  # un dictionnaire d'ancres : chacune est un point
		for n in v:
			if _est_point(v[n]):
				out.append({"nom": "%s@%s" % [String(ref).get_slice(".", 0), n], "pos": Vector2(float(v[n][0]), float(v[n][1]))})
		return out
	if _est_point(v):
		out.append({"nom": String(ref), "pos": Vector2(float(v[0]), float(v[1]))})
	elif v is Array:
		for i in (v as Array).size():
			if _est_point(v[i]):
				out.append({"nom": "%s[%d]" % [ref, i], "pos": Vector2(float(v[i][0]), float(v[i][1]))})
	return out


static func _zone(z: Variant, index: Dictionary) -> Variant:
	if z is Array and (z as Array).size() == 4:
		return Rect2(float(z[0]), float(z[1]), float(z[2]), float(z[3]))
	if z is Dictionary and (z as Dictionary).has("bande"):
		var c: Variant = nombre(z.get("centre", null), index)
		var d: Variant = nombre(z.get("demi", null), index)
		if c == null or d == null:
			return null
		var large := 1e9
		return Rect2(float(c) - float(d), -large, 2.0 * float(d), 2.0 * large) if String(z["bande"]) == "u" \
			else Rect2(-large, float(c) - float(d), 2.0 * large, 2.0 * float(d))
	var r: Variant = valeur(String(z), index)
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])) if r is Array and (r as Array).size() == 4 else null


## Nombre désigné : un nombre, une référence, ou une somme/différence (« a+b-c »).
static func nombre(ref: Variant, index: Dictionary) -> Variant:
	if ref is float or ref is int:
		return float(ref)
	if not (ref is String):
		return null
	var total := 0.0
	var termes := (ref as String).replace("-", "+-").split("+", false)
	for t in termes:
		var signe := -1.0 if t.begins_with("-") else 1.0
		var brut := t.trim_prefix("-").strip_edges()
		var v: Variant = float(brut) if brut.is_valid_float() else valeur(brut, index)
		if not (v is float or v is int):
			return null
		total += signe * float(v)
	return total


## Valeur d'une référence "id.chemin", "id@ancre" ou "id.rect.umin|umax|vmin|vmax".
static func valeur(ref: String, index: Dictionary) -> Variant:
	var id := ref.get_slice("@", 0).get_slice(".", 0)
	if not index.has(id):
		return null
	var e: Dictionary = index[id]
	if "@" in ref:
		return StudioPlan.lire_chemin(e, "ancres." + ref.get_slice("@", 1), null)
	var chemin := ref.substr(id.length() + 1)
	for bord in ["umin", "umax", "vmin", "vmax"]:
		if chemin.ends_with(".rect." + bord) or chemin == "rect." + bord:
			var r: Variant = e.get("rect", null)
			if not (r is Array):
				return null
			match bord:
				"umin": return float(r[0])
				"umax": return float(r[0]) + float(r[2])
				"vmin": return float(r[1])
				"vmax": return float(r[1]) + float(r[3])
	return StudioPlan.lire_chemin(e, chemin, null)


static func indexer(donnees: Dictionary, adaptateur: Dictionary) -> Dictionary:
	var out := {}
	var cle := String(adaptateur.get("id", "id"))
	for e in donnees.get(String(adaptateur.get("liste", "")), []):
		if e is Dictionary and (e as Dictionary).has(cle):
			out[String(e[cle])] = e
	return out


static func _en_liste(v: Variant) -> Array:
	if _est_point(v):
		return [v]
	if v is Dictionary:
		return (v as Dictionary).values()
	return v if v is Array else []


static func _est_point(v: Variant) -> bool:
	return v is Array and (v as Array).size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int)


## Bords inclus (Rect2.has_point exclut le bord droit/bas : un point posé SUR le bord de la place y est).
static func _contient(r: Rect2, p: Vector2) -> bool:
	return p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y
