class_name StudioValidation
extends RefCounted

## Contrôle de TOUTES les données d'un jeu, piloté par un seul fichier de configuration
## (res://data/validation.json) — aucun code à écrire par jeu :
## {
##   "catalogues": { "chats": {"fichier": "res://data/chats.json", "liste": "chats", "champ": "id"} },
##   "controles": [
##     { "dossier": "res://data/niveaux/", "schema": "res://data/schemas/niveau.json",
##       "plan": "res://data/plan.json" }
##   ]
## }
## Un contrôle vise un "fichier" ou tous les .json d'un "dossier". "plan" (optionnel) ajoute les
## vérifications spatiales et de dépendances de StudioPlan.

const CONFIG_DEFAUT := "res://data/validation.json"


## Retourne {chemin_fichier: Array[String] de fautes} ; la clé "_config" porte les fautes de config.
static func tout(config_chemin: String = CONFIG_DEFAUT) -> Dictionary:
	var rapport := {}
	var config: Variant = StudioJson.lire(config_chemin)
	if not (config is Dictionary):
		rapport["_config"] = ["configuration illisible : %s" % config_chemin]
		return rapport
	var catalogues := charger_catalogues((config as Dictionary).get("catalogues", {}))
	for controle in (config as Dictionary).get("controles", []):
		for chemin in _fichiers(controle):
			rapport[chemin] = controler(chemin, controle, catalogues)
	return rapport


static func controler(chemin: String, controle: Dictionary, catalogues: Dictionary) -> Array[String]:
	var fautes: Array[String] = []
	var donnees: Variant = StudioJson.lire(chemin)
	if donnees == null:
		fautes.append("illisible")
		return fautes
	if controle.has("schema"):
		var schema := StudioSchema.charger(String(controle["schema"]))
		if schema.is_empty():
			fautes.append("schéma introuvable : %s" % controle["schema"])
		else:
			fautes.append_array(StudioSchema.valider(donnees, schema, catalogues))
	if controle.has("plan") and donnees is Dictionary:
		var adaptateur: Variant = StudioJson.lire(String(controle["plan"]))
		if adaptateur is Dictionary:
			fautes.append_array(StudioPlan.verifier_plan(donnees, adaptateur, (adaptateur as Dictionary).get("jetons_depart", [])))
	return fautes


## {nom: Array des valeurs} à partir de {nom: {fichier, liste, champ}}.
static func charger_catalogues(defs: Dictionary) -> Dictionary:
	var out := {}
	for nom in defs:
		var d: Dictionary = defs[nom]
		var brut: Variant = StudioJson.lire(String(d.get("fichier", "")))
		var valeurs: Array = []
		if brut is Dictionary:
			for e in (brut as Dictionary).get(String(d.get("liste", "")), []):
				if e is Dictionary and (e as Dictionary).has(String(d.get("champ", "id"))):
					valeurs.append(e[String(d.get("champ", "id"))])
		out[nom] = valeurs
	return out


## Nombre total de fautes d'un rapport.
static func compter(rapport: Dictionary) -> int:
	var n := 0
	for k in rapport:
		n += (rapport[k] as Array).size()
	return n


static func _fichiers(controle: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if controle.has("fichier"):
		out.append(String(controle["fichier"]))
	if controle.has("dossier"):
		var dossier := String(controle["dossier"])
		for nom in DirAccess.get_files_at(dossier):
			if nom.ends_with(".json"):
				out.append(dossier.path_join(nom))
	return out
