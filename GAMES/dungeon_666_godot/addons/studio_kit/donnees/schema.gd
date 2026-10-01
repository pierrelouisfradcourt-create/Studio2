class_name StudioSchema
extends RefCounted

## Validation des DONNÉES de jeu (niveaux, catalogues, économie) contre un schéma.
## C'est un oracle non-LLM : une donnée fausse est rejetée mécaniquement, avec son chemin exact
## (« zones[2].rect : largeur <= 0 »), avant d'arriver dans le jeu.
##
## Un schéma est un Dictionary (écrit en JSON dans le jeu) :
##   type     : objet | liste | texte | entier | nombre | booleen | rect | point | couleur | quelconque
##   requis   : [champs obligatoires]          (objet)
##   champs   : {nom: schéma}                  (objet)
##   fermé    : true => champ inconnu = faute  (objet ; défaut false, les données évoluent)
##   elements : schéma de chaque élément       (liste)
##   unique   : champ qui doit être unique entre éléments (liste)
##   contient : {"champ": "id", "valeurs": [...]} — entrées OBLIGATOIRES de la liste (celles que le code lit)
##   selon    : {"champ": "id", "cas": {valeur: schéma}} — l'élément de la liste dont le champ vaut
##              `valeur` est AUSSI validé par ce schéma (règles propres à une entrée : ses nombres) (liste)
##   chaque   : schéma de CHAQUE valeur d'un objet à clés libres (ex. une famille de prix par nom) (objet)
##   min, max : bornes (nombre) ou tailles (liste, texte)
##   valeurs  : [valeurs permises]
##   ref      : nom d'un catalogue ; la valeur (ou chaque valeur d'une liste de textes) doit y être

const TYPES := ["objet", "liste", "texte", "entier", "nombre", "booleen", "rect", "point", "couleur", "quelconque"]


## Retourne la liste des fautes (vide = valide). `catalogues` : {nom: Array des valeurs connues}.
static func valider(valeur: Variant, schema: Dictionary, catalogues: Dictionary = {}, chemin: String = "$") -> Array[String]:
	var fautes: Array[String] = []
	var type := String(schema.get("type", "quelconque"))
	if not TYPES.has(type):
		fautes.append("%s : type de schéma inconnu « %s »" % [chemin, type])
		return fautes
	if not _type_ok(valeur, type):
		fautes.append("%s : %s attendu, reçu %s" % [chemin, type, _nom_type(valeur)])
		return fautes
	fautes.append_array(_bornes(valeur, schema, chemin))
	fautes.append_array(_valeurs_et_refs(valeur, schema, catalogues, chemin))
	match type:
		"objet":
			fautes.append_array(_objet(valeur, schema, catalogues, chemin))
		"liste":
			fautes.append_array(_liste(valeur, schema, catalogues, chemin))
		"rect":
			if float(valeur[2]) <= 0.0 or float(valeur[3]) <= 0.0:
				fautes.append("%s : largeur et hauteur doivent être > 0" % chemin)
	return fautes


static func _type_ok(v: Variant, type: String) -> bool:
	match type:
		"objet":
			return v is Dictionary
		"liste":
			return v is Array
		"texte":
			return v is String
		"entier":
			return (v is int) or (v is float and is_equal_approx(v, roundf(v)))
		"nombre":
			return v is int or v is float
		"booleen":
			return v is bool
		"rect":
			return _nombres(v, 4)
		"point":
			return _nombres(v, 2)
		"couleur":
			return v is String and Color.html_is_valid(v)
	return true


static func _nombres(v: Variant, n: int) -> bool:
	if not (v is Array) or (v as Array).size() != n:
		return false
	for x in v:
		if not (x is int or x is float):
			return false
	return true


static func _bornes(v: Variant, schema: Dictionary, chemin: String) -> Array[String]:
	var fautes: Array[String] = []
	var mesure: float
	if v is int or v is float:
		mesure = float(v)
	elif v is Array or v is String:
		mesure = float(v.size() if v is Array else (v as String).length())
	else:
		return fautes
	if schema.has("min") and mesure < float(schema["min"]):
		fautes.append("%s : %s < minimum %s" % [chemin, str(mesure), str(schema["min"])])
	if schema.has("max") and mesure > float(schema["max"]):
		fautes.append("%s : %s > maximum %s" % [chemin, str(mesure), str(schema["max"])])
	return fautes


static func _valeurs_et_refs(v: Variant, schema: Dictionary, catalogues: Dictionary, chemin: String) -> Array[String]:
	var fautes: Array[String] = []
	if schema.has("valeurs") and not (schema["valeurs"] as Array).has(v):
		fautes.append("%s : « %s » hors des valeurs permises %s" % [chemin, str(v), str(schema["valeurs"])])
	if not schema.has("ref"):
		return fautes
	var nom := String(schema["ref"])
	if not catalogues.has(nom):
		fautes.append("%s : catalogue « %s » non fourni" % [chemin, nom])
		return fautes
	var connus: Array = catalogues[nom]
	var a_verifier: Array = v if v is Array else [v]
	for x in a_verifier:
		if not connus.has(x):
			fautes.append("%s : « %s » n'existe pas dans %s" % [chemin, str(x), nom])
	return fautes


static func _objet(d: Dictionary, schema: Dictionary, catalogues: Dictionary, chemin: String) -> Array[String]:
	var fautes: Array[String] = []
	var champs: Dictionary = schema.get("champs", {})
	for cle in schema.get("requis", []):
		if not d.has(cle):
			fautes.append("%s : champ requis « %s » absent" % [chemin, cle])
	for cle in d:
		if schema.has("chaque"):
			fautes.append_array(valider(d[cle], schema["chaque"], catalogues, "%s.%s" % [chemin, cle]))
		if champs.has(cle):
			fautes.append_array(valider(d[cle], champs[cle], catalogues, "%s.%s" % [chemin, cle]))
		elif bool(schema.get("fermé", false)):
			fautes.append("%s : champ inconnu « %s »" % [chemin, cle])
	return fautes


static func _liste(a: Array, schema: Dictionary, catalogues: Dictionary, chemin: String) -> Array[String]:
	var fautes: Array[String] = []
	var vus := {}
	var unique := String(schema.get("unique", ""))
	var selon: Dictionary = schema.get("selon", {})
	fautes.append_array(_contient(a, schema.get("contient", {}), chemin))
	for i in a.size():
		var ici := "%s[%d]" % [chemin, i]
		if schema.has("elements"):
			fautes.append_array(valider(a[i], schema["elements"], catalogues, ici))
		if unique != "" and a[i] is Dictionary and (a[i] as Dictionary).has(unique):
			var cle: Variant = a[i][unique]
			if vus.has(cle):
				fautes.append("%s : %s « %s » déjà utilisé en [%d]" % [ici, unique, str(cle), vus[cle]])
			vus[cle] = i
		if not selon.is_empty() and a[i] is Dictionary:
			var cas: Dictionary = selon.get("cas", {})
			var v: Variant = (a[i] as Dictionary).get(String(selon.get("champ", "id")))
			if v != null and cas.has(v):
				fautes.append_array(valider(a[i], cas[v], catalogues, "%s(%s)" % [ici, str(v)]))
	return fautes


static func _contient(a: Array, regle: Dictionary, chemin: String) -> Array[String]:
	var fautes: Array[String] = []
	if regle.is_empty():
		return fautes
	var champ := String(regle.get("champ", "id"))
	var presents := {}
	for e in a:
		if e is Dictionary and (e as Dictionary).has(champ):
			presents[e[champ]] = true
	for v in regle.get("valeurs", []):
		if not presents.has(v):
			fautes.append("%s : entrée obligatoire %s « %s » absente" % [chemin, champ, str(v)])
	return fautes


static func _nom_type(v: Variant) -> String:
	return type_string(typeof(v))


## Charge un schéma JSON (res://…). Retourne {} si absent ou illisible.
static func charger(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		return {}
	var brut: Variant = JSON.parse_string(FileAccess.get_file_as_string(chemin))
	return brut if brut is Dictionary else {}
