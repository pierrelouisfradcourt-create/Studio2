extends SceneTree
## Planche de sons : écrit chaque recette rendue en .wav dans un dossier, pour l'ÉCOUTE par le
## propriétaire (personne n'a entendu ces sons : la machine ne vérifie que leur santé).
##   <godot> --headless --path . --script res://jeu/son/exporter_planche.gd -- <dossier>
## Écrit aussi `sommaire.txt` : nom, durée, crête, niveau de mixage, événements déclencheurs.
## Le dossier doit être HORS du projet : aucun fichier audio n'y entre.

const Recettes = preload("res://jeu/son/recettes.gd")
const Routage = preload("res://jeu/son/routage.gd")
const Synthese = preload("res://jeu/son/synthese.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage : exporter_planche.gd -- <dossier hors du projet>")
		quit(2)
		return
	var dossier: String = args[0]
	if ProjectSettings.globalize_path(dossier).begins_with(ProjectSettings.globalize_path("res://")):
		print("refus : le dossier est dans le projet (aucun fichier audio dans le projet)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(dossier)
	var erreurs := _exporter(dossier)
	print("RESULT: %s" % ("PASS" if erreurs == 0 else "FAIL"))
	quit(0 if erreurs == 0 else 1)

func _exporter(dossier: String) -> int:
	var declencheurs := _declencheurs()
	var bruit := Recettes.bruit()
	var lignes: Array = [
		"Dungeon 666 (Godot) — planche de sons, %d recettes, %d Hz 16 bits mono" % [Recettes.noms().size(), Recettes.TAUX],
		"Chaque fichier est normalisé à une crête de %.2f pour l'écoute ; en jeu il est rejoué au" % Synthese.CRETE_CIBLE,
		"niveau « crête brute » × le niveau de mixage du son, et sa hauteur varie de ±5 %.",
		"",
		"%-22s %8s %12s  %s" % ["recette", "durée s", "crête brute", "son (niveau de mixage) <- événements"],
	]
	var erreurs := 0
	var depart := Time.get_ticks_usec()
	var total := 0.0
	var octets := 0
	for nom in Recettes.noms():
		var r := Recettes.rendre(nom, bruit)
		var flux: AudioStreamWAV = r.flux
		if flux.save_to_wav(dossier.path_join(nom + ".wav")) != OK:
			erreurs += 1
			print("ROUGE — écriture impossible : ", nom)
		total += r.duree
		octets += r.octets
		lignes.append("%-22s %8.3f %12.3f  %s" % [nom, r.duree, r.crete_brute, declencheurs.get(nom, "(aucun)")])
	var ms := (Time.get_ticks_usec() - depart) / 1000.0
	lignes.append("")
	lignes.append("total : %.1f s de son, %.2f Mo en mémoire, rendu et écriture en %.0f ms" % [total, octets / 1048576.0, ms])
	var sommaire := FileAccess.open(dossier.path_join("sommaire.txt"), FileAccess.WRITE)
	if sommaire == null:
		print("ROUGE — sommaire.txt impossible à écrire")
		return erreurs + 1
	sommaire.store_string("\n".join(lignes) + "\n")
	sommaire.close()
	print("%d sons écrits dans %s (%.1f s de son, %.0f ms)" % [Recettes.noms().size() - erreurs, dossier, total, ms])
	return erreurs

## Recette -> « son (niveau) <- événements » pour chaque son qui peut la demander.
func _declencheurs() -> Dictionary:
	var out := {}
	for cle in Routage.SONS:
		var texte := "%s (%.2f) <- %s" % [cle, Routage.SONS[cle].gain, ", ".join(Routage.evenements_de(cle))]
		for nom in Routage.recettes_de(cle):
			out[nom] = texte if not out.has(nom) else out[nom] + " ; " + texte
	for nom in Routage.RECETTES_ECRANS:
		out[nom] = "écrans : son.jouer(\"%s\")" % nom
	return out
