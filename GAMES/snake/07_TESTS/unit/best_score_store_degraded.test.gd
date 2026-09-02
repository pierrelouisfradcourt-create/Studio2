# best_score_store_degraded.test.gd — ligne bestscore.persistence. Aller-retour egal ;
# et pour CHACUN des 4 cas (absent, vide, corrompu, [illisible simule par chemin invalide]),
# le chargement renvoie STRICTEMENT 0, sans exception remontee au joueur.
extends RefCounted

const Store = preload("res://06_RUNTIME/adapters/best_score_store/best_score_store.gd")

func run(h) -> void:
	var chemin := "user://snake_best_score_test.save"
	# Nettoyage prealable.
	if FileAccess.file_exists(chemin):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	var store = Store.new(chemin)

	# Cas 1 : fichier ABSENT -> 0.
	if FileAccess.file_exists(chemin):
		var f0 := FileAccess.open(chemin, FileAccess.WRITE)
		f0.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	h.eq(store.charger(), 0, "fichier absent -> 0")

	# Aller-retour : enregistrer 42 puis relire = 42.
	h.eq(store.enregistrer(42), true, "enregistrement reussi")
	h.eq(store.charger(), 42, "relecture stricte = valeur enregistree")

	# Cas 2 : fichier VIDE -> 0.
	var fv := FileAccess.open(chemin, FileAccess.WRITE)
	fv.store_string("")
	fv.close()
	h.eq(store.charger(), 0, "fichier vide -> 0")

	# Cas 3 : fichier CORROMPU (non entier) -> 0, sans crash.
	var fc := FileAccess.open(chemin, FileAccess.WRITE)
	fc.store_string("<<pas un entier>>")
	fc.close()
	h.eq(store.charger(), 0, "fichier corrompu -> 0")

	# Cas 4 : emplacement non inscriptible (chemin invalide) -> enregistrer echoue
	# proprement (false), aucune exception ; le chargement y reste 0.
	var store_ko = Store.new("user://sous_dossier_inexistant/rec.save")
	h.eq(store_ko.enregistrer(99), false, "emplacement non inscriptible -> false (pas de crash)")
	h.eq(store_ko.charger(), 0, "emplacement illisible -> 0")

	# Nettoyage final.
	if FileAccess.file_exists(chemin):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
