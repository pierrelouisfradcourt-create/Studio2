# best_score_store.gd — ligne bestscore.persistence. SEULE I/O du produit : FileAccess
# sur un fichier user://. La logique pure n'y touche jamais. Degradation SILENCIEUSE cote
# joueur (record 0), journalisee cote debug. Un fichier illisible est traite comme absent
# (= strategie de migration). RefCounted : pas besoin d'un Node pour un acces fichier.
extends RefCounted

const CHEMIN_DEFAUT := "user://snake_best_score.save"

var chemin: String

func _init(chemin_fichier: String = CHEMIN_DEFAUT) -> void:
	chemin = chemin_fichier

# Charge le meilleur score. Les QUATRE cas limites (absent, vide, corrompu, illisible)
# renvoient 0 sans jamais lever d'exception au joueur.
func charger() -> int:
	if not FileAccess.file_exists(chemin):
		return 0  # fichier absent -> demarrage propre a 0
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		# Emplacement illisible : exception NOMMEE, absorbee ; record 0.
		push_warning("best_score illisible (%s) : demarrage a 0" % FileAccess.get_open_error())
		return 0
	var txt := f.get_as_text().strip_edges()
	f.close()
	if txt == "" or not txt.is_valid_int():
		# Vide ou corrompu : traite comme absent (record 0), pas de crash.
		push_warning("best_score vide/corrompu : demarrage a 0")
		return 0
	var v := int(txt)
	if v < 0:
		return 0
	return v

# Enregistre le meilleur score. Emplacement non inscriptible -> silencieux cote joueur.
func enregistrer(valeur: int) -> bool:
	var f := FileAccess.open(chemin, FileAccess.WRITE)
	if f == null:
		push_warning("best_score non inscriptible (%s) : ignore" % FileAccess.get_open_error())
		return false
	f.store_string(str(valeur))
	f.close()
	return true
