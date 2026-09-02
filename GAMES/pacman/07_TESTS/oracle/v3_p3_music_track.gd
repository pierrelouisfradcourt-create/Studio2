# v3_p3_music_track.gd — CAUSE RACINE P3.
#
# DEFAUT MESURE (playtest Pierre) : le jeu n'avait pas de MUSIQUE. Ce n'etait PAS « audio
# absent » — six bruitages existent, sont synthetises et sont prouves. Ce qui manquait
# est une PISTE : une suite de notes qui tourne en fond.
#
# INVARIANT : aucun fichier son (charter_v2.hors_scope[10]). La piste est donc
# SYNTHETISEE par le meme AudioStreamGenerator et le meme moteur d'enveloppe que les
# bruitages — reutilise, jamais double.
#
# Regle de variance (ratifiee Pierre 2026-07-21) : une piste dont toutes les notes
# seraient identiques serait un bourdon. Le nombre de hauteurs distinctes est MESURE.
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const InventoryV2 = preload("res://06_RUNTIME/adapters/proof_harness/harness_asset_inventory_v2.gd")


func run(h) -> void:
	Audio.reinitialiser()

	# --- LA PISTE EXISTE, ET ELLE VARIE. ---
	h.gt(Bank.nb_notes(), 7, "v3.p3: la piste porte une vraie suite de notes")
	h.gt(Bank.hauteurs_distinctes(), 2, "v3.p3: au moins trois hauteurs distinctes")
	h.gt(int(Bank.duree_piste_ms()), 0, "v3.p3: la piste a une duree declaree")

	# ELLE BOUCLE : le rang revient a son point de depart au bout d'une duree de piste.
	h.eq(Bank.rang_note(0.0), 0, "v3.p3: la lecture commence a la premiere note")
	h.eq(Bank.rang_note(Bank.duree_piste_ms()), 0, "v3.p3: la piste boucle sur elle-meme")
	h.eq(Bank.rang_note(Bank.PISTE_DUREE_NOTE_MS), 1, "v3.p3: une note dure ce qui est declare")
	h.eq(Bank.rang_note(-Bank.PISTE_DUREE_NOTE_MS), Bank.nb_notes() - 1,
		"v3.p3: un temps negatif est ramene dans la boucle")
	h.eq(Bank.hauteur_note(Bank.nb_notes()), Bank.hauteur_note(0),
		"v3.p3: le rang boucle aussi sur les hauteurs")

	# LA PISTE N'EST PAS UN BRUITAGE DEGUISE : elle vit hors des six moments, dont le
	# comptage sert de controle croise a l'inventaire.
	h.eq(InventoryV2.mesurer()["descripteurs_de_synthese"], 6,
		"v3.p3: les six moments de jeu restent six")
	h.eq(Bank.connu(Bank.MOMENT_MUSIQUE), false, "v3.p3: la musique n'est pas un septieme moment")

	# --- ELLE EST SYNTHETISEE, PAS CHARGEE. ---
	var buffer: PackedFloat32Array = Audio.echantillons_note(0)
	h.gt(buffer.size(), 0, "v3.p3: la note est fabriquee a l'execution")
	h.gt(int(Audio.amplitude_max(buffer) * 1000.0), 0, "v3.p3: la note n'est pas silencieuse")
	var deborde: int = 0
	for v in buffer:
		if absf(v) > 1.0:
			deborde += 1
	h.eq(deborde, 0, "v3.p3: le signal reste borne")

	# UN SILENCE DE LA PISTE garde sa mesure : un tampon vide ferait accelerer la boucle.
	var rang_silence: int = Bank.NOTES.find(Bank.SILENCE_HZ)
	h.gt(rang_silence, -1, "v3.p3: la piste declare au moins un silence")
	var muet: PackedFloat32Array = Audio.echantillons_note(rang_silence)
	h.eq(muet.size(), buffer.size(), "v3.p3: un silence dure autant qu'une note")
	h.eq(int(Audio.amplitude_max(muet) * 1000.0), 0, "v3.p3: un silence est bien silencieux")

	# --- ELLE SE JOUE, ET LE JOURNAL EN TEMOIGNE (headless : aucun haut-parleur). ---
	Audio.reinitialiser()
	h.eq(Audio.journal_musique().size(), 0, "v3.p3: le journal musical part vide")
	var ms: float = 0.0
	while ms < Bank.duree_piste_ms():
		Audio.jouer_musique(ms)
		ms += Bank.PISTE_DUREE_NOTE_MS
	h.eq(Audio.journal_musique().size(), Bank.nb_notes(), "v3.p3: toute la piste a ete jouee")
	h.eq(Audio.rangs_joues()[0], 0, "v3.p3: la lecture a commence au debut")
	h.eq(Audio.hauteurs_jouees(), Bank.hauteurs_distinctes(),
		"v3.p3: toutes les hauteurs declarees ont ete jouees")

	# LE JOURNAL DES BRUITAGES reste separe : la musique ne pollue pas le comptage des six.
	h.eq(Audio.journal().size(), 0, "v3.p3: la piste n'entre pas au journal des bruitages")
	h.eq(Audio.moments_muets(), 6, "v3.p3: aucun moment de jeu n'a ete declenche par la piste")

	# --- LE VOLUME MUSIQUE LA GOUVERNE (jonction avec P6). ---
	var fort: PackedFloat32Array = Audio.echantillons_note(0, Reglages.avec_volume(
		{}, Reglages.Canal.MUSIQUE, Reglages.NIVEAU_MAX))
	var faible: PackedFloat32Array = Audio.echantillons_note(0, Reglages.avec_volume(
		{}, Reglages.Canal.MUSIQUE, Reglages.NIVEAU_MIN))
	h.gt(int(Audio.amplitude_max(fort) * 1000.0), int(Audio.amplitude_max(faible) * 1000.0),
		"v3.p3: le volume musique change l'amplitude de la piste")
	h.eq(fort.size(), faible.size(), "v3.p3: le volume ne change pas la duree")
	Audio.reinitialiser()
