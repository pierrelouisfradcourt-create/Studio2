# harness_asset_inventory_v2.gd — INVENTAIRE APRES L'AJOUT DU SON
# (ligne harness.zero_audio_asset_inventory).
#
# L'invariant ZERO ASSET du run V1 est conserve et ETENDU au son : le nombre de fichiers
# d'extension audio (.wav, .ogg, .mp3, .m4a, .flac) sous games/pacman/ vaut exactement 0.
# C'est CE COMPTAGE qui rend la clause « audio entierement genere » falsifiable — sans
# lui, « genere » ne serait qu'une intention de conception.
extends RefCounted

const Inventory = preload("res://06_RUNTIME/adapters/proof_harness/asset_inventory.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")

# Extensions AUDIO, nommees separement des autres assets : c'est le volet que V2 ajoute.
const EXTENSIONS_AUDIO: Array = ["wav", "ogg", "mp3", "m4a", "flac"]


static func fichiers_audio(racine: String = "res://") -> Array:
	var fautifs: Array = []
	for f in Inventory.fichiers(racine):
		if EXTENSIONS_AUDIO.has(f.get_extension().to_lower()):
			fautifs.append(f)
	return fautifs


# Le dossier d'assets importes reste-t-il ABSENT ou VIDE ? Un descripteur de synthese
# n'est pas un asset : il vit en 06_RUNTIME, pas en 04_ASSETS.
static func fichiers_sous_assets() -> Array:
	var sortie: Array = []
	for f in Inventory.fichiers("res://"):
		if f.begins_with("res://04_ASSETS"):
			sortie.append(f)
	return sortie


static func mesurer(racine: String = "res://") -> Dictionary:
	var tous: Array = Inventory.fichiers(racine)
	var audio: Array = fichiers_audio(racine)
	return {
		"fichiers": tous.size(),
		"fichiers_audio": audio.size(),
		"fautifs": audio,
		"fichiers_04_assets": fichiers_sous_assets().size(),
		# CONTRE-EPREUVE : le son EXISTE malgre 0 fichier audio — six descripteurs de
		# synthese sont declares. Un son present sans asset est la SEULE lecture
		# acceptable des deux mesures ensemble.
		"descripteurs_de_synthese": Bank.MOMENTS.size(),
	}
