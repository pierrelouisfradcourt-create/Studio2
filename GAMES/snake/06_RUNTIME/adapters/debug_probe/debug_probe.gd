# debug_probe.gd — ligne debug.receipt_line. Emission ligne-a-ligne du recu d'observation
# vers stdout, lisible par un lecteur reel HORS du moteur. Prefixe + JSON du dictionnaire
# d'observation. RefCounted. Les Vector2i sont serialises en [x, y] (JSON n'a pas de type
# vecteur). Type OUTIL_FORGE cote .mjs source ; ici c'est le .gd emetteur qui est ecrit.
extends RefCounted

const PREFIXE := "SNAKE_TRIAL"

# Convertit une observation (peut contenir des Vector2i) en dictionnaire JSON-serialisable.
static func serialisable(observation: Dictionary) -> Dictionary:
	var out := {}
	for k in observation.keys():
		var v = observation[k]
		if v is Vector2i:
			out[k] = [v.x, v.y]
		else:
			out[k] = v
	return out

# Ligne de recu : "SNAKE_TRIAL {json}".
static func formater(observation: Dictionary) -> String:
	return PREFIXE + " " + JSON.stringify(serialisable(observation))

# Emet la ligne sur stdout (lecteur reel).
static func emettre(observation: Dictionary) -> void:
	print(formater(observation))

# Parse une ligne de recu (cote oracle). Renvoie le Dictionary, ou null si mal forme.
static func parser(ligne: String):
	var tete := PREFIXE + " "
	if not ligne.begins_with(tete):
		return null
	var json_txt := ligne.substr(tete.length())
	var j := JSON.new()
	if j.parse(json_txt) != OK:
		return null
	return j.data
