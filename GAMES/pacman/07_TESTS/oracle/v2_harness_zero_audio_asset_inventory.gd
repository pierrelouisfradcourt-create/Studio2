# v2_harness_zero_audio_asset_inventory.gd — ligne harness.zero_audio_asset_inventory, F91.
# Inventaire des fichiers du jeu APRES l'ajout du son : le nombre de fichiers d'extension
# audio vaut exactement 0. C'est ce comptage qui rend la clause « audio entierement
# genere » falsifiable.
extends RefCounted

const InventoryV2 = preload("res://06_RUNTIME/adapters/proof_harness/harness_asset_inventory_v2.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")


func run(h) -> void:
	var m: Dictionary = InventoryV2.mesurer()
	h.gt(m["fichiers"], 0, "harness.audio_assets: l'inventaire a reellement parcouru le projet")
	h.eq(m["fichiers_audio"], 0, "harness.audio_assets: 0 fichier audio dans le jeu")
	h.eq(m["fautifs"].size(), 0, "harness.audio_assets: aucun fichier fautif a nommer")
	h.eq(m["fichiers_04_assets"], 0, "harness.audio_assets: aucun fichier sous 04_ASSETS")
	h.eq(InventoryV2.EXTENSIONS_AUDIO.size(), 5, "harness.audio_assets: cinq extensions surveillees")

	# CONTROLE CROISE OBLIGATOIRE : le son EXISTE malgre 0 fichier audio.
	h.eq(m["descripteurs_de_synthese"], 6, "harness.audio_assets: six descripteurs de synthese declares")
	Audio.reinitialiser()
	var joue: Dictionary = Audio.jouer(Bank.MOMENTS[0], 1)
	h.eq(joue["joue"], true, "harness.audio_assets: un son est bien produit")
	h.gt(int(joue["echantillons"]), 0, "harness.audio_assets: des echantillons sont synthetises")
	Audio.reinitialiser()

	# LE DETECTEUR FONCTIONNE : il reconnait bien une extension audio.
	var faux: Array = InventoryV2.fichiers_audio("res://03_WORLD")
	h.eq(faux.size(), 0, "harness.audio_assets: aucun fichier audio dans le contenu non plus")
	h.eq(InventoryV2.EXTENSIONS_AUDIO.has("wav"), true, "harness.audio_assets: le wav est surveille")
	h.eq(InventoryV2.EXTENSIONS_AUDIO.has("m4a"), true, "harness.audio_assets: le m4a aussi")
