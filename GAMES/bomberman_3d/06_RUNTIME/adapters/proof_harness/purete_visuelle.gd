# purete_visuelle.gd — MESURE de l'unicite du descripteur de palette.
#
# reused_from = CONCEPT (games/pacman/06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd
# + son volet v2_shell_palette_only_colors.gd) : « le comptage des litteraux de couleur
# situes hors du descripteur vaut exactement 0 ».
#
# POURQUOI CE FICHIER EXISTE : `palette.gd` AFFIRMAIT deja cette propriete en commentaire.
# Rien ne la verifiait. Une regle qui vit dans la prose echappe aux lecteurs et a toute
# verification mecanique — c'est le mode de panne que le standard nomme explicitement. Ici
# on la rend comptable.
extends RefCounted

const DESCRIPTEUR := "res://06_RUNTIME/adapters/palette/palette.gd"
const RACINE_LOGIQUE := "res://05_SYSTEMS"
const RACINE_RUNTIME := "res://06_RUNTIME"
const MOTIF := "Color("
# EXCLUSION NOMMEE : une sonde qui declare ce qu elle cherche porte forcement le motif
# qu elle cherche. L exclure est un fait, pas une complaisance — et l exclusion est
# LIMITEE a ce seul fichier, jamais a un repertoire.
const SONDE := "res://06_RUNTIME/adapters/proof_harness/purete_visuelle.gd"


# Retire les COMMENTAIRES avant de compter : un fichier qui PARLE d'une couleur n'en porte
# pas une. Sans ce filtre, la mesure compterait sa propre documentation.
static func code_seul(texte: String) -> String:
	var sortie: Array = []
	for ligne in texte.split("\n"):
		var i: int = ligne.find("#")
		sortie.append(ligne if i < 0 else ligne.substr(0, i))
	return "\n".join(sortie)


static func _fichiers_gd(racine: String, acc: Array) -> Array:
	var da := DirAccess.open(racine)
	if da == null:
		return acc
	da.list_dir_begin()
	var nom := da.get_next()
	while nom != "":
		var chemin: String = racine + "/" + nom
		if da.current_is_dir():
			_fichiers_gd(chemin, acc)
		elif nom.ends_with(".gd"):
			acc.append(chemin)
		nom = da.get_next()
	da.list_dir_end()
	acc.sort()
	return acc


static func _porte_couleur(chemin: String) -> bool:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return false
	var t: String = code_seul(f.get_as_text())
	f.close()
	return t.find(MOTIF) >= 0


# Fichiers portant un litteral de couleur HORS du descripteur, dans tout le runtime.
static func couleur_hors_palette() -> Array:
	var sortie: Array = []
	for chemin in _fichiers_gd(RACINE_RUNTIME, []):
		if chemin == DESCRIPTEUR or chemin == SONDE:
			continue
		if _porte_couleur(chemin):
			sortie.append(chemin)
	return sortie


# CONTROLE POSITIF : le descripteur, lui, DOIT en porter. Sans ce controle, une mesure a
# zero pourrait signifier « la sonde ne trouve rien nulle part ».
static func couleur_dans_palette() -> bool:
	return _porte_couleur(DESCRIPTEUR)


# Fichiers de LOGIQUE portant une couleur : les regles n'ont aucune raison d'en connaitre.
static func couleur_dans_logique() -> Array:
	var sortie: Array = []
	for chemin in _fichiers_gd(RACINE_LOGIQUE, []):
		if _porte_couleur(chemin):
			sortie.append(chemin)
	return sortie
