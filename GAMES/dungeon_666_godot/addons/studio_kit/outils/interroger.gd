extends SceneTree

## Interroger l'état d'un jeu HORS DU JEU, avec sa couche sémantique (res://studio_inspecteur.json).
##   godot --headless --path <jeu> --script res://addons/studio_kit/outils/interroger.gd -- <source> <question> [id]
## <source> : un etat.json écrit par l'inspecteur (copie_etat), ou une SAUVEGARDE du jeu (lue par
##            charger_etat de la couche sémantique ; la sauvegarde n'est jamais écrite).
## Exemples de questions : inspect_game · inspect_line ligne_2 · find_blocked_entities · explain ligne_2
## Sortie : la réponse en JSON ; pour explain, aussi l'arbre des causes en texte.


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var conf: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://studio_inspecteur.json")) if FileAccess.file_exists("res://studio_inspecteur.json") else null
	var chemin := String((conf as Dictionary).get("semantique", {}).get("script", "")) if conf is Dictionary else ""
	if a.size() < 2 or chemin == "" or not ResourceLoader.exists(chemin):
		printerr("usage : interroger.gd -- <etat.json | sauvegarde> <question> [id]  (et une couche sémantique dans res://studio_inspecteur.json)")
		quit(2)
		return
	var sem: Script = load(chemin)
	var etat := _etat(a[0], sem)
	if etat.is_empty():
		printerr("état illisible : " + a[0])
		quit(2)
		return
	var r: Variant = sem.repondre(etat, a[1], a[2] if a.size() > 2 else "")
	print(JSON.stringify(r, "  "))
	if r is Dictionary and (r as Dictionary).has("texte"):
		print("\n" + String(r["texte"]))
	quit(0)


func _etat(source: String, sem: Script) -> Dictionary:
	var brut: Variant = JSON.parse_string(FileAccess.get_file_as_string(source)) if FileAccess.file_exists(source) else null
	if brut is Dictionary and (brut as Dictionary).has("lignes"):
		return brut
	return sem.charger_etat(source)
