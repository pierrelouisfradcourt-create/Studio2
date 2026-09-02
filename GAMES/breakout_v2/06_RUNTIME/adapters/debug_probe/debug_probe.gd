# debug_probe.gd — ligne proof.debug_probe. Emission ligne-a-ligne du recu d'observation vers
# stdout, lisible par un lecteur reel HORS du moteur. Prefixe + JSON du dictionnaire
# d'observation. Les Vector2 sont serialises en [x, y] (JSON n'a pas de type vecteur). RefCounted.
extends RefCounted

const PREFIXE := "BREAKOUT_TRIAL"

# Convertit une observation (peut contenir des Vector2) en dictionnaire JSON-serialisable.
static func serialisable(observation: Dictionary) -> Dictionary:
	var out := {}
	for k in observation.keys():
		var v = observation[k]
		if v is Vector2:
			out[k] = [v.x, v.y]
		else:
			out[k] = v
	return out

# Ligne de recu : "BREAKOUT_TRIAL {json}".
static func formater(observation: Dictionary) -> String:
	return PREFIXE + " " + JSON.stringify(serialisable(observation))

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
