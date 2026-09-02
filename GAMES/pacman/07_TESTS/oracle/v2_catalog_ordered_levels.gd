# v2_catalog_ordered_levels.gd — ligne catalog.ordered_levels, capacites F101/F102.
# L'ORDRE et le NOMBRE de cartes se lisent dans le catalogue et NULLE PART AILLEURS.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")


func run(h) -> void:
	var entrees: Array = ContentV2.entrees()
	h.gt(entrees.size(), 1, "catalog.ordered: au moins deux niveaux embarques")
	h.eq(ContentV2.nb_niveaux(), entrees.size(), "catalog.ordered: le compte vient du catalogue")

	# ORDRE DECLARE : l'index 0 est la carte nominale, l'index 1 la seconde.
	h.eq(ContentV2.dossier(0), "maze_classic", "catalog.ordered: premier niveau declare")
	h.eq(ContentV2.dossier(1), "maze_alt", "catalog.ordered: second niveau declare")
	h.eq(ContentV2.index_du_dossier("maze_alt"), 1, "catalog.ordered: resolution par nom de dossier")
	h.eq(ContentV2.index_du_dossier("carte_absente"), ContentV2.INDEX_ABSENT,
		"catalog.ordered: un dossier inconnu est refuse, jamais devine")

	# Chaque entree resout un descripteur REEL.
	var sans_descripteur: int = 0
	for i in range(ContentV2.nb_niveaux()):
		if ContentV2.descripteur(i).is_empty():
			sans_descripteur += 1
	h.eq(sans_descripteur, 0, "catalog.ordered: chaque entree resout un descripteur")

	# Hors bornes : une valeur VIDE, jamais une exception ni un index qui deborde.
	h.eq(ContentV2.entree(-1).is_empty(), true, "catalog.ordered: index negatif refuse")
	h.eq(ContentV2.entree(ContentV2.nb_niveaux()).is_empty(), true, "catalog.ordered: index au-dela refuse")
	h.eq(ContentV2.dossier(99), "", "catalog.ordered: dossier hors bornes vide")

	# La coquille lit le MEME compte : une seule source.
	h.eq(Shell.nb_niveaux(), ContentV2.nb_niveaux(), "catalog.ordered: la coquille lit le meme catalogue")
