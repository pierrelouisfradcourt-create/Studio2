extends SceneTree

## Outils « Game CAD » en ligne de commande, sur les données d'un jeu (jamais sur l'éditeur ouvert).
##   godot --headless --path <jeu> --script res://addons/studio_kit/outils/cad.gd -- <commande> …
##
##   inspecter <fichier.json> <plan.json>              décrit les entités du fichier (et leurs ancres)
##   relations <fichier.json> <plan.json>              chaque relation du monde : tient / cassée
##   verifier  <fichier.json> <plan.json>              fautes du plan (sortie 1 s'il y en a)
##   deplacer  <fichier.json> <plan.json> <id> <dx> <dy>
##             décale l'entité et toutes ses positions, réécrit le fichier, puis revérifie
##             (sortie 1 et fichier INCHANGÉ si le résultat est faux).

const USAGE := "usage : cad.gd -- inspecter|relations|verifier|deplacer <fichier.json> <plan.json> [id dx dy]"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		printerr(USAGE)
		quit(2)
		return
	var donnees: Variant = StudioJson.lire(a[1])
	var adaptateur: Variant = StudioJson.lire(a[2])
	if not (donnees is Dictionary and adaptateur is Dictionary):
		printerr("fichier ou plan illisible")
		quit(2)
		return
	match a[0]:
		"inspecter":
			print(StudioPlan.inspecter(StudioPlan.entites(donnees, adaptateur)))
			quit(0)
		"verifier":
			quit(_rapporter(donnees, adaptateur))
		"relations":
			quit(_relations(donnees, adaptateur))
		"deplacer":
			quit(_deplacer(a, donnees, adaptateur))
		_:
			printerr(USAGE)
			quit(2)


func _rapporter(donnees: Dictionary, adaptateur: Dictionary) -> int:
	var fautes := StudioPlan.verifier_plan(donnees, adaptateur, adaptateur.get("jetons_depart", []))
	for f in fautes:
		print("- " + f)
	print("=== PLAN : %d faute(s) ===" % fautes.size())
	return 0 if fautes.is_empty() else 1


func _relations(donnees: Dictionary, adaptateur: Dictionary) -> int:
	var cassees := 0
	var index := StudioRelations.indexer(donnees, adaptateur)
	for r in adaptateur.get("relations", []):
		var f := StudioRelations.verifier_une(r, index, donnees, adaptateur)
		cassees += 1 if not f.is_empty() else 0
		print("%s %s" % ["TIENT  " if f.is_empty() else "CASSÉE ", r.get("nom", r.get("type", "?"))])
		for x in f:
			print("         - " + x)
	print("=== RELATIONS : %d, dont %d cassée(s) ===" % [(adaptateur.get("relations", []) as Array).size(), cassees])
	return 0 if cassees == 0 else 1


func _deplacer(a: PackedStringArray, donnees: Dictionary, adaptateur: Dictionary) -> int:
	if a.size() < 6:
		printerr(USAGE)
		return 2
	var avant := StudioPlan.verifier_plan(donnees, adaptateur, adaptateur.get("jetons_depart", [])).size()
	if not StudioPlan.deplacer(donnees, adaptateur, a[3], Vector2(float(a[4]), float(a[5]))):
		printerr("entité introuvable : " + a[3])
		return 1
	var fautes := StudioPlan.verifier_plan(donnees, adaptateur, adaptateur.get("jetons_depart", []))
	if fautes.size() > avant:
		for f in fautes:
			print("- " + f)
		print("=== REFUSÉ : le déplacement ajoute des fautes, fichier inchangé ===")
		return 1
	StudioJson.ecrire(a[1], donnees)
	print("=== « %s » déplacée de (%s, %s) ; plan : %d faute(s) ===" % [a[3], a[4], a[5], fautes.size()])
	return 0
