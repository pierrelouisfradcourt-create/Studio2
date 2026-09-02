# v2_content_additive_third_map.gd — ligne content.additive_third_map, capacite F102.
# Le fournisseur resout une entree du catalogue SANS enumerer les cartes en dur : une
# entree de plus ne modifie pas ce fichier non plus. C'est la propriete qui fait tomber
# a 0 le nombre de fichiers de logique touches par l'ajout d'une troisieme carte.
extends RefCounted

const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")


func run(h) -> void:
	# AUCUNE CARTE citee en dur dans le fournisseur.
	var f := FileAccess.open("res://06_RUNTIME/adapters/content_provider/content_provider.gd", FileAccess.READ)
	h.ok(f != null, "content.additif: le fournisseur est lisible")
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("maze_classic"), false, "content.additif: la premiere carte n'est pas citee")
	h.eq(texte.contains("maze_alt"), false, "content.additif: la seconde carte n'est pas citee")
	h.eq(texte.contains("match "), false, "content.additif: aucun aiguillage par nom de carte")

	# La resolution passe par le CHAMP du catalogue, pas par une liste ecrite ici.
	h.eq(texte.contains("CLE_DOSSIER"), true, "content.additif: la resolution passe par le champ declare")
	h.eq(ContentV2.dossier(0), String(ContentV2.entree(0)["dossier"]), "content.additif: le dossier vient du catalogue")

	# La MEME fonction resout n'importe quelle entree : la resolution est GENERIQUE.
	var resolus: int = 0
	for i in range(ContentV2.nb_niveaux()):
		if not ContentV2.descripteur(i).is_empty():
			resolus += 1
	h.eq(resolus, ContentV2.nb_niveaux(), "content.additif: toutes les entrees se resolvent par la meme voie")

	# Une carte NON CATALOGUEE se resout aussi par son nom de dossier : ajouter une entree
	# suffirait, sans toucher a ce fichier.
	h.eq(ContentV2.descripteur_du_dossier("maze_alt").is_empty(), false,
		"content.additif: un dossier se resout par son nom seul")
	h.eq(ContentV2.descripteur_du_dossier("").is_empty(), true,
		"content.additif: un nom vide ne resout rien")
	h.eq(ContentV2.descripteur_du_dossier("carte_absente").is_empty(), true,
		"content.additif: un dossier inexistant ne resout rien, et ne leve pas")

	# LES SEULS EMPLACEMENTS touches par l'ajout d'une carte sont deux fichiers de donnee.
	h.eq(FileAccess.file_exists("res://03_WORLD/levels/maze_classic/level.json"), true,
		"content.additif: un descripteur par dossier de niveau")
	h.eq(FileAccess.file_exists("res://03_WORLD/rules/level_catalog/catalog.json"), true,
		"content.additif: un catalogue unique")
