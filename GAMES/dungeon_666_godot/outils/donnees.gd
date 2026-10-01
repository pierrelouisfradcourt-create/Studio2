extends SceneTree
## Les fichiers de données (data/*.json, liste : D6Data.FILES) s'écrivent-ils sans rien perdre ?
##   <godot> --headless --path . --script res://outils/donnees.gd                 contrôle (ne change rien)
##   <godot> --headless --path . --script res://outils/donnees.gd -- reecrire     remet chaque fichier en forme
##   <godot> --headless --path . --script res://outils/donnees.gd -- comparer <dossier>
##
## Contrôle : chaque fichier est lu, réécrit en mémoire par StudioJson (le style du studio : ce qui
## tient sur une ligne y reste, entiers sans « .0 »), relu. ROUGE si une valeur ne revient pas AU BIT
## PRÈS (un nombre que l'écriture arrondirait : plus de 15 chiffres, ou un minuscule pris pour un
## entier) ou si l'ordre des clés change — l'ordre fait partie des règles, des boucles le parcourent.
## Un fichier seulement mal mis en forme (édité à la main) est signalé, sans rouge : `-- reecrire`.
##
## comparer : les données en mémoire (D6Data) sont-elles, au bit près et dans le même ordre, celles
## d'un ancien export de la version web (<dossier>/tuning.json et tables.json, forme « ~hex ») ?
## A servi une fois, le 2026-10-01, à prouver que le passage au JSON ordinaire n'a rien changé.
##
## Sortie 0 = vert, 1 = rouge.

const NOTE_PREFIX := "_"

static func bits(x: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	return b.hex_encode()

## "" si `a` et `b` sont identiques — mêmes types, mêmes clés dans le même ordre, nombres au bit
## près — sinon le chemin et les deux valeurs du premier écart.
static func same(a, b, path: String = "$") -> String:
	if typeof(a) != typeof(b):
		return "%s : %s au lieu de %s" % [path, type_string(typeof(b)), type_string(typeof(a))]
	if a is float:
		return "" if bits(a) == bits(b) else "%s : %s (%s) au lieu de %s (%s)" % [path, str(b), bits(b), str(a), bits(a)]
	if a is Array:
		if a.size() != b.size():
			return "%s : %d éléments au lieu de %d" % [path, b.size(), a.size()]
		for i in a.size():
			var d := same(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if a is Dictionary:
		if a.keys() != b.keys():
			return "%s : clés %s au lieu de %s" % [path, str(b.keys()), str(a.keys())]
		for k in a:
			var d := same(a[k], b[k], "%s.%s" % [path, k])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s : %s au lieu de %s" % [path, str(b), str(a)]

## Compte les nombres d'une donnée : [tous, non entiers].
static func count_numbers(v, acc: Array = [0, 0]) -> Array:
	if v is float or v is int:
		acc[0] += 1
		if float(v) != floorf(float(v)):
			acc[1] += 1
	elif v is Array:
		for x in v:
			count_numbers(x, acc)
	elif v is Dictionary:
		for k in v:
			count_numbers(v[k], acc)
	return acc

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "comparer":
		quit(_compare(args[1]))
		return
	quit(_check(args.size() >= 1 and args[0] == "reecrire"))

func _check(rewrite: bool) -> int:
	var red := 0
	var numbers := [0, 0]
	for name in D6Data.FILES:
		var path: String = D6Data.DATA_DIR + name + ".json"
		var text := FileAccess.get_file_as_string(path).replace("\r", "")
		var value = JSON.parse_string(text)
		if not (value is Dictionary):
			red += 1
			print("  ROUGE — %s : illisible" % path)
			continue
		count_numbers(value, numbers)
		var written: String = StudioJson.formater(value) + "\n"
		var diff := same(value, JSON.parse_string(written))
		if diff != "":
			red += 1
			print("  ROUGE — %s : l'écriture ne rend pas la valeur lue — %s" % [path, diff])
		elif written == text:
			print("  ok   — %s" % path)
		elif rewrite:
			var err := StudioJson.ecrire(path, value)
			red += 0 if err == OK else 1
			print("  %s — %s : remis en forme" % ["ok  " if err == OK else "ROUGE", path])
		else:
			print("  ok   — %s (mise en forme à refaire : outils/donnees.gd -- reecrire)" % path)
	print("%d fichiers, %d nombres dont %d non entiers, %d rouges" % [D6Data.FILES.size(), numbers[0], numbers[1], red])
	print("DONNEES_ECRITURE: %s" % ("PASS" if red == 0 else "FAIL"))
	return 0 if red == 0 else 1

func _compare(dir: String) -> int:
	var red := 0
	for pair in [["tuning.json", D6Data.default_tuning()], ["tables.json", D6Data.tables()]]:
		var old = D6Js.read_exact(dir.path_join(pair[0]))
		if not (old is Dictionary):
			red += 1
			print("  ROUGE — %s illisible" % dir.path_join(pair[0]))
			continue
		var diffs := _all_diffs(old, pair[1], "$", [])
		var n := count_numbers(old)
		print("  %s — %s : %d nombres (%d non entiers), %d écarts" % ["ok  " if diffs.is_empty() else "ROUGE", pair[0], n[0], n[1], diffs.size()])
		for d in diffs:
			print("        ", d)
		red += diffs.size()
	print("COMPARAISON: %s" % ("PASS" if red == 0 else "FAIL"))
	return 0 if red == 0 else 1

## Tous les écarts (et non le premier seulement) entre l'ancienne donnée et la nouvelle.
static func _all_diffs(a, b, path: String, out: Array) -> Array:
	if a is Dictionary and b is Dictionary and a.keys() == b.keys():
		for k in a:
			_all_diffs(a[k], b[k], "%s.%s" % [path, k], out)
	elif a is Array and b is Array and a.size() == b.size():
		for i in a.size():
			_all_diffs(a[i], b[i], "%s[%d]" % [path, i], out)
	else:
		var d := same(a, b, path)
		if d != "":
			out.append(d)
	return out
