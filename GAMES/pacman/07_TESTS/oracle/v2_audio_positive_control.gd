# v2_audio_positive_control.gd — ligne audio.positive_control, capacite F89.
# SEULE couche a connaitre une API audio de la plateforme. C'est ce qui donne au
# comptage statique son CONTROLE POSITIF : les memes references qui doivent valoir 0
# dans 05_SYSTEMS doivent etre TROUVEES ici, faute de quoi le comptage ne prouve rien
# (un projet sans audio du tout passerait le test a 0).
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	# LE COMPTAGE, dans les deux sens.
	h.eq(Purity.audio_dans_logique().size(), 0, "audio.controle: 0 fichier de logique reference l'audio")
	var runtime: Array = Purity.audio_dans_runtime()
	h.gt(runtime.size(), 0, "audio.controle: les memes references SONT trouvees dans le runtime")

	# ET c'est bien l'adaptateur audio qui les porte.
	var porte_par_audio: bool = false
	for f in runtime:
		if f == "res://06_RUNTIME/adapters/audio/audio.gd":
			porte_par_audio = true
	h.eq(porte_par_audio, true, "audio.controle: l'adaptateur audio porte les references")

	# LES QUATRE API declarees sont reellement citees dans le fichier.
	var f2 := FileAccess.open("res://06_RUNTIME/adapters/audio/audio.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f2.get_as_text() if f2 != null else "")
	var manquantes: int = 0
	for api in Audio.API_PLATEFORME:
		if not texte.contains(String(api)):
			manquantes += 1
	h.eq(manquantes, 0, "audio.controle: les quatre API declarees sont reellement referencees")
	h.eq(Audio.API_PLATEFORME.size(), 4, "audio.controle: quatre API declarees")

	# LE SERVEUR AUDIO de la plateforme repond : la reference n'est pas decorative.
	h.gt(Audio.frequence_serveur(), 0.0, "audio.controle: le serveur audio de la plateforme repond")
	h.eq(Audio.est_flux_de_plateforme(Audio.fabriquer_flux()), true,
		"audio.controle: le flux fabrique est bien un flux de plateforme")
	h.eq(Audio.brancher_lecteur(null) == null, true,
		"audio.controle: sans scene, aucun lecteur n'est fabrique — l'echec est nomme")
	h.eq(Audio.pousser(null, "son_mort"), 0, "audio.controle: sans lecteur, rien n'est pousse")
