# score_store.gd — PERSISTANCE du meilleur score. Seul module qui touche au disque.
#
# reused_from = CONCEPT (games/snake/06_RUNTIME/adapters/best_score_store) : la valeur vit
# dans `user://`, jamais dans le depot — un meilleur score est une donnee de JOUEUR, pas un
# artefact de build.
#
# MODE DEGRADE ASSUME : disque indisponible, fichier illisible, contenu non entier => 0.
# Jamais une exception, jamais un score invente. Perdre un record est benin ; planter au
# demarrage ne l'est pas.
extends RefCounted

const CHEMIN := "user://meilleur_score.txt"


static func lire() -> int:
	if not FileAccess.file_exists(CHEMIN):
		return 0
	var f := FileAccess.open(CHEMIN, FileAccess.READ)
	if f == null:
		return 0
	var t := f.get_as_text().strip_edges()
	f.close()
	return int(t) if t.is_valid_int() else 0


# Rend true si l'ecriture a REELLEMENT eu lieu. Un appel qui echoue le dit.
static func ecrire(valeur: int) -> bool:
	if valeur < 0:
		return false
	var f := FileAccess.open(CHEMIN, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(str(valeur))
	f.close()
	return true
