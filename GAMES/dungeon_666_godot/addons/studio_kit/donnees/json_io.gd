class_name StudioJson
extends RefCounted

## Lecture / écriture des fichiers de données JSON du studio.
## Écrit dans le style des fichiers faits main (Qui va où) : ce qui tient sur une ligne reste sur
## une ligne, le reste est indenté de 2. Les entiers restent des entiers (JSON de Godot relit tout
## en flottants : 690 deviendrait 690.0). Résultat : un déplacement d'entité = un diff de quelques lignes.

const INDENT := "  "
const LARGEUR := 100


static func lire(chemin: String) -> Variant:
	if not FileAccess.file_exists(chemin):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(chemin)) != OK:
		push_error("JSON invalide %s ligne %d : %s" % [chemin, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func ecrire(chemin: String, valeur: Variant) -> Error:
	var f := FileAccess.open(chemin, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(formater(valeur) + "\n")
	f.close()
	return OK


static func formater(v: Variant, niveau: int = 0) -> String:
	var enligne := _en_ligne(v)
	if not (v is Dictionary or v is Array) or INDENT.length() * niveau + enligne.length() <= LARGEUR:
		return enligne
	var retrait := INDENT.repeat(niveau + 1)
	var morceaux: PackedStringArray = []
	if v is Dictionary:
		for cle in v:
			morceaux.append("%s%s: %s" % [retrait, JSON.stringify(str(cle)), formater(v[cle], niveau + 1)])
		return "{\n%s\n%s}" % [",\n".join(morceaux), INDENT.repeat(niveau)]
	for x in v:
		morceaux.append(retrait + formater(x, niveau + 1))
	return "[\n%s\n%s]" % [",\n".join(morceaux), INDENT.repeat(niveau)]


static func _en_ligne(v: Variant) -> String:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
		return str(int(v))
	if v is Dictionary:
		var parts: PackedStringArray = []
		for cle in v:
			parts.append("%s: %s" % [JSON.stringify(str(cle)), _en_ligne(v[cle])])
		return "{}" if parts.is_empty() else "{ %s }" % ", ".join(parts)
	if v is Array:
		var parts: PackedStringArray = []
		for x in v:
			parts.append(_en_ligne(x))
		return "[%s]" % ", ".join(parts)
	return JSON.stringify(v)
