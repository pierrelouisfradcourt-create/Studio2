# v2_sound_bank_six_descriptors.test.gd — ligne sound_bank.six_descriptors, capacite F92.
# SIX DESCRIPTEURS DE SYNTHESE, compares DEUX A DEUX : chaque paire differe par au moins
# un parametre — le nombre de paires identiques vaut exactement 0.
extends RefCounted

const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	h.eq(Bank.MOMENTS.size(), 6, "sound_bank: six moments declares")
	h.eq(Bank.DESCRIPTEURS.size(), 6, "sound_bank: six descripteurs declares")
	h.eq(Bank.paires_identiques(), 0, "sound_bank: 0 paire de descripteurs identiques")

	# UN DESCRIPTEUR PAR MOMENT NOMME de game_events — aucun moment orphelin.
	var orphelins: int = 0
	for m in Events.MOMENTS:
		if not Bank.connu(m):
			orphelins += 1
	h.eq(orphelins, 0, "sound_bank: chaque moment nomme a son descripteur")

	# CHAQUE descripteur est COMPLET.
	var incomplets: int = 0
	for m in Bank.MOMENTS:
		if Bank.champs_manquants(Bank.descripteur(m)).size() > 0:
			incomplets += 1
	h.eq(incomplets, 0, "sound_bank: aucun descripteur incomplet")
	h.eq(Bank.CHAMPS.size(), 6, "sound_bank: six parametres de synthese declares")

	# DES DESCRIPTEURS, jamais des fichiers.
	var f := FileAccess.open("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains(".wav"), false, "sound_bank: aucune reference de fichier wav")
	h.eq(texte.contains(".ogg"), false, "sound_bank: aucune reference de fichier ogg")
	h.eq(texte.contains("04_ASSETS"), false, "sound_bank: aucun chemin d'asset")

	# LE COMPARATEUR detecte bien une difference — sans quoi 0 paire identique ne dirait rien.
	h.eq(Bank.differents(Bank.descripteur("son_mort"), Bank.descripteur("son_victoire")), true,
		"sound_bank: deux descripteurs differents sont reconnus")
	h.eq(Bank.differents(Bank.descripteur("son_mort"), Bank.descripteur("son_mort")), false,
		"sound_bank: un descripteur ne differe pas de lui-meme")
	h.eq(Bank.connu("son_absent"), false, "sound_bank: un moment inconnu est refuse")
	h.eq(Bank.descripteur("son_absent").is_empty(), true, "sound_bank: il ne rend aucun descripteur")
