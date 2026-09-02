# harness_purity_counts.gd — COMPTAGES STATIQUES DE PURETE (lignes harness.no_color_in_logic,
# et volet machine des comptages d'API d'entree et d'API audio).
#
# Trois comptages, TOUS assortis de leur CONTROLE POSITIF : les memes references qui
# doivent valoir 0 dans 05_SYSTEMS doivent etre TROUVEES dans 06_RUNTIME, faute de quoi
# le comptage ne prouve rien (un projet sans entree, sans audio ou sans couleur du tout
# passerait les trois tests a 0 sans rien etablir).
#
# Le comptage porte sur le TEXTE des fichiers, comme le ferait un lecteur exterieur :
# c'est ce qui le rend falsifiable plutot que declaratif.
extends RefCounted

const Inventory = preload("res://06_RUNTIME/adapters/proof_harness/asset_inventory.gd")

const RACINE_LOGIQUE := "res://05_SYSTEMS"
const RACINE_RUNTIME := "res://06_RUNTIME"

# API d'ENTREE de la plateforme.
const MOTIFS_ENTREE: Array = [
	"Input.", "InputEvent", "InputMap", "KEY_", "JOY_", "InputEventScreenTouch",
]
# API AUDIO de la plateforme.
const MOTIFS_AUDIO: Array = [
	"AudioStream", "AudioStreamGenerator", "AudioStreamPlayer", "AudioServer",
]
# LITTERAL de couleur.
const MOTIFS_COULEUR: Array = ["Color("]

# Descripteur de palette declare : SEUL fichier autorise a porter un litteral de couleur.
const DESCRIPTEUR_PALETTE := "res://06_RUNTIME/adapters/palette/palette.gd"

# L'INSTRUMENT DE MESURE lui-meme : il porte les MOTIFS cherches sous forme de chaines,
# et se compterait donc lui-meme. L'exclure est une decision assumee et nommee, pas un
# silence : un instrument qui se mesure ne mesure plus rien.
const INSTRUMENT := "res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd"


static func _texte(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


# CODE SEUL : le commentaire est retire avant comptage. Une PROSE qui NOMME une API
# n'est pas une REFERENCE a cette API — compter les commentaires ferait rougir un
# fichier qui declare precisement qu'il n'utilise pas l'API en question. Meme convention
# que le gate de mutation, qui traite `#` comme un commentaire.
# Limite de mesure ASSUMEE : un `#` a l'interieur d'une chaine tronque aussi la ligne ;
# aucune ligne portant une API de plateforme n'est dans ce cas.
static func code_seul(texte: String) -> String:
	var sortie: Array = []
	for ligne in texte.split("\n"):
		var i: int = ligne.find("#")
		if i < 0:
			sortie.append(ligne)
		else:
			sortie.append(ligne.substr(0, i))
	return "\n".join(sortie)


# Fichiers .gd d'une racine, dans l'ordre trie (deterministe).
static func fichiers_gd(racine: String) -> Array:
	var sortie: Array = []
	for f in Inventory.fichiers(racine):
		if f.get_extension().to_lower() == "gd":
			sortie.append(f)
	return sortie


# Fichiers d'une racine portant AU MOINS UN des motifs. Rend la LISTE, pour que l'echec
# nomme les fichiers fautifs au lieu de rendre un nombre nu.
static func fichiers_portant(racine: String, motifs: Array, exclus: Array = []) -> Array:
	var sortie: Array = []
	for f in fichiers_gd(racine):
		if f == INSTRUMENT or exclus.has(f):
			continue
		var t: String = code_seul(_texte(f))
		for m in motifs:
			if t.find(m) >= 0:
				sortie.append(f)
				break
	return sortie


# --- COMPTAGE 1 : API d'entree ----------------------------------------------------
static func entree_dans_logique() -> Array:
	return fichiers_portant(RACINE_LOGIQUE, MOTIFS_ENTREE)


static func entree_dans_runtime() -> Array:
	return fichiers_portant(RACINE_RUNTIME, MOTIFS_ENTREE)


# --- COMPTAGE 2 : API audio -------------------------------------------------------
static func audio_dans_logique() -> Array:
	return fichiers_portant(RACINE_LOGIQUE, MOTIFS_AUDIO)


static func audio_dans_runtime() -> Array:
	return fichiers_portant(RACINE_RUNTIME, MOTIFS_AUDIO)


# --- COMPTAGE 3 : litteraux de couleur --------------------------------------------
static func couleur_dans_logique() -> Array:
	return fichiers_portant(RACINE_LOGIQUE, MOTIFS_COULEUR)


# Litteraux de couleur HORS du descripteur de palette declare, tout le runtime compris.
static func couleur_hors_palette() -> Array:
	return fichiers_portant(RACINE_RUNTIME, MOTIFS_COULEUR, [DESCRIPTEUR_PALETTE])


static func couleur_dans_palette() -> Array:
	var sortie: Array = []
	if code_seul(_texte(DESCRIPTEUR_PALETTE)).find(MOTIFS_COULEUR[0]) >= 0:
		sortie.append(DESCRIPTEUR_PALETTE)
	return sortie


# MESURE COMPLETE : les six nombres, cote logique et cote runtime.
static func mesurer() -> Dictionary:
	return {
		"fichiers_logique": fichiers_gd(RACINE_LOGIQUE).size(),
		"fichiers_runtime": fichiers_gd(RACINE_RUNTIME).size(),
		"entree_logique": entree_dans_logique().size(),
		"entree_runtime": entree_dans_runtime().size(),
		"audio_logique": audio_dans_logique().size(),
		"audio_runtime": audio_dans_runtime().size(),
		"couleur_logique": couleur_dans_logique().size(),
		"couleur_hors_palette": couleur_hors_palette().size(),
		"couleur_palette": couleur_dans_palette().size(),
	}
