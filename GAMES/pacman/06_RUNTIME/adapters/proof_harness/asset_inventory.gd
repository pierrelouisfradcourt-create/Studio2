# asset_inventory.gd — inventaire des fichiers du jeu (ligne harness.asset_inventory).
# L'exigence hors_scope du charter (« zero asset importe ») devient un FAIT MESURE, pas
# une intention : on parcourt reellement res:// et l'on nomme ce qu'on trouve.
extends RefCounted

# Extensions d'assets IMPORTES, refusees par le charter (image, police, son).
const EXTENSIONS_INTERDITES: Array = [
	"png", "jpg", "jpeg", "bmp", "svg", "webp", "tga", "gif",
	"ttf", "otf", "woff", "woff2", "fnt",
	"wav", "ogg", "mp3", "flac",
	"import",
]
# Dossiers ignores : le cache du moteur n'est pas un livrable du jeu.
const DOSSIERS_IGNORES: Array = [".godot", ".import"]


# Liste RECURSIVE des fichiers du projet, triee — ordre deterministe, jamais l'ordre du
# systeme de fichiers.
static func fichiers(racine: String = "res://") -> Array:
	var sortie: Array = []
	_parcourir(racine, sortie)
	sortie.sort()
	return sortie


static func _parcourir(dossier: String, sortie: Array) -> void:
	var da := DirAccess.open(dossier)
	if da == null:
		return
	da.list_dir_begin()
	var nom := da.get_next()
	var sous_dossiers: Array = []
	while nom != "":
		if da.current_is_dir():
			if not DOSSIERS_IGNORES.has(nom):
				sous_dossiers.append(nom)
		else:
			sortie.append(dossier.path_join(nom))
		nom = da.get_next()
	da.list_dir_end()
	sous_dossiers.sort()
	for d in sous_dossiers:
		_parcourir(dossier.path_join(d), sortie)


# Fichiers d'asset importe trouves. Une liste VIDE est le constat recherche ; elle est
# rendue telle quelle pour que l'echec nomme les fichiers fautifs.
static func assets_importes(racine: String = "res://") -> Array:
	var fautifs: Array = []
	for f in fichiers(racine):
		var ext: String = f.get_extension().to_lower()
		if EXTENSIONS_INTERDITES.has(ext):
			fautifs.append(f)
	return fautifs


static func mesurer(racine: String = "res://") -> Dictionary:
	var liste: Array = fichiers(racine)
	var fautifs: Array = assets_importes(racine)
	return {"fichiers": liste.size(), "assets_importes": fautifs.size(), "fautifs": fautifs}
