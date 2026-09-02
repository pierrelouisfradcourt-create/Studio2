# v4_p1_audio_playback_path.gd — CAUSE RACINE P1 : AUCUN SON.
#
# DEFAUT MESURE (playtest Pierre : « la musique j'ai rien »). L'audit a montre PLUS LARGE
# que le rapport joueur : rien ne sortait, bruitages compris.
#   * `audio.jouer()` et `audio.jouer_musique()` synthetisaient un tampon, l'inscrivaient
#     au journal, puis RENDAIENT ;
#   * aucun `AudioStreamPlayer` n'existait dans le jeu, aucun `push_frame` n'etait appele ;
#   * `fabriquer_flux()` n'etait invoque que par deux fichiers de preuve, jamais par le
#     runtime.
# La synthese etait complete, le CHEMIN DE LECTURE absent. La couverture mecanique
# mesurait meme le CONTRAIRE : `v3_p3_music_track` passait en lisant le JOURNAL. C'est le
# defaut « preuve sans executeur » dans sa forme la plus pure.
#
# CE QUE CETTE PREUVE MESURE — et rien de plus. Le harnais tourne en `--headless`, donc
# sur le pilote audio « Dummy » : AUCUN peripherique ne restitue quoi que ce soit. Cette
# preuve n'affirme donc PAS « le son est entendu ». Elle etablit que le CHEMIN EST CABLE
# ET ALIMENTE : un playback de plateforme existe reellement, il recoit des frames, le
# compte de frames poussees est > 0, et ce qui y entre SUIT le reglage de volume.
#
# CE QUI RESTE NON MESURABLE ICI, ET POURQUOI :
#   * la RESTITUTION sonore (qu'un haut-parleur emette le signal) exige un peripherique
#     audio reel — NOT_MEASURED motive, volet HumanGate, jamais converti en vert ;
#   * le tampon du playback NE SE VIDE PAS sous le pilote « Dummy » (mesure de ce poste
#     le 2026-08-06 : 11025 frames de capacite, `get_frames_available()` ne remonte
#     jamais). Aucune mesure de DEBIT SOUTENU n'est donc possible en headless. Chaque
#     mesure d'alimentation part par consequent d'un lecteur NEUF — c'est une contrainte
#     de plateforme nommee, pas un contournement : sous un vrai pilote, c'est le
#     peripherique qui draine le tampon.
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

const CHEMIN_RUNTIME := "res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd"


func _texte(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


# TAMPON NEUF avant chaque mesure d'alimentation. Voir la limitation nommee en tete :
# sous le pilote « Dummy », rien ne draine le tampon, donc deux mesures successives sur
# le meme lecteur se marcheraient dessus. Ce n'est pas un contournement de l'echec — le
# chemin reste le meme, seul le point de depart est remis a zero.
func _neuf(hote: Node):
	Audio.detacher_lecteur()
	Audio.reinitialiser()
	return Audio.brancher_lecteur(hote)


func run(h) -> void:
	# --- ETAT DE DEPART : sans lecteur branche, rien n'est pousse. C'EST LE DEFAUT
	# D'ORIGINE, et il est ici reproduit avant d'etre corrige. ---
	Audio.reinitialiser()
	h.eq(Audio.lecteur(), null, "v4.p1: aucun lecteur avant branchement")
	h.eq(Audio.lecture_active(), false, "v4.p1: le chemin de lecture est ferme au depart")
	var muet: Dictionary = Audio.jouer("son_collecte", 1)
	h.gt(int(muet["echantillons"]), 0, "v4.p1: la synthese, elle, a toujours fonctionne")
	h.eq(int(muet["frames"]), 0, "v4.p1: mais rien n'atteignait le lecteur — le defaut mesure")
	h.eq(Audio.frames_poussees(), 0, "v4.p1: 0 frame poussee, c'est l'etat d'avant V4")
	h.eq(Audio.brancher_lecteur(null), null, "v4.p1: sans parent, aucun lecteur — echec nomme")

	# --- LE CHEMIN EST OUVERT : flux -> AudioStreamPlayer reel -> playback -> frames. ---
	var arbre = Engine.get_main_loop()
	var hote := Node.new()
	arbre.root.add_child(hote)
	h.eq(hote.is_inside_tree(), true, "v4.p1: l'hote est dans un arbre vivant")

	Audio.reinitialiser()
	var lecteur = Audio.brancher_lecteur(hote)
	h.ok(lecteur != null, "v4.p1: un lecteur de plateforme est fabrique")
	h.eq(lecteur.is_inside_tree(), true, "v4.p1: il est reellement dans l'arbre de scene")
	h.eq(Audio.est_flux_de_plateforme(lecteur.stream), true, "v4.p1: il porte un flux genere")
	h.eq(lecteur.playing, true, "v4.p1: la lecture est DEMARREE, pas seulement preparee")
	h.eq(Audio.lecture_active(), true, "v4.p1: le chemin de lecture est ouvert")
	h.ok(lecteur.get_stream_playback() != null, "v4.p1: le moteur rend un playback reel")

	# --- IL EST ALIMENTE : un moment de jeu pousse des frames DANS ce playback. ---
	var joue: Dictionary = Audio.jouer("son_collecte", 2)
	h.gt(int(joue["frames"]), 0, "v4.p1: un bruitage pousse des frames dans le playback")
	h.eq(int(joue["frames"]), int(joue["echantillons"]),
		"v4.p1: tout ce qui est synthetise entre dans le tampon")
	h.gt(Audio.frames_poussees(), 0, "v4.p1: le compteur de frames poussees a bouge")
	h.gt(int(Audio.amplitude_poussee() * 1000.0), 0, "v4.p1: le signal pousse n'est pas plat")

	# LES SIX MOMENTS empruntent le chemin, pas seulement un. Chacun sur un tampon neuf :
	# les six totalisent ~1,36 s de signal pour 0,5 s de capacite.
	var sans_frame: int = 0
	for m in Bank.MOMENTS:
		_neuf(hote)
		if int(Audio.jouer(String(m), 3)["frames"]) <= 0:
			sans_frame += 1
	h.eq(sans_frame, 0, "v4.p1: chacun des six atteint reellement le lecteur")
	_neuf(hote)
	Audio.jouer_evenements(Bank.MOMENTS, 3)
	h.eq(Audio.moments_muets(), 0, "v4.p1: aucun des six moments ne reste muet")

	# LA PISTE MUSICALE aussi — c'est le point exact du rapport joueur.
	_neuf(hote)
	var note: Dictionary = Audio.jouer_musique(0.0)
	h.gt(int(note["frames"]), 0, "v4.p1: la piste musicale atteint le lecteur")
	# UNE note poussee PAR NOTE : re-interroger le meme instant ne la repousse pas.
	var repetee: Dictionary = Audio.jouer_musique(0.0)
	h.eq(int(repetee["frames"]), 0, "v4.p1: le meme rang n'est pas pousse deux fois")
	_neuf(hote)
	Audio.jouer_musique(0.0)
	var suivante: Dictionary = Audio.jouer_musique(Bank.PISTE_DUREE_NOTE_MS)
	h.gt(int(suivante["rang"]), int(note["rang"]), "v4.p1: le rang a bien change")
	h.gt(int(suivante["frames"]), 0, "v4.p1: la note suivante est poussee a son tour")

	# --- CE QUI ENTRE DANS LE TAMPON SUIT LE VOLUME. Le COMPTE de frames ne varie pas
	# avec le gain (un tampon a gain nul garde sa longueur) : c'est l'AMPLITUDE qui porte
	# le reglage, et c'est donc elle qui est mesuree. ---
	var plein: Dictionary = Reglages.avec_volume(Reglages.initial(), Reglages.Canal.EFFETS,
		Reglages.NIVEAU_MAX)
	var bas: Dictionary = Reglages.avec_volume(Reglages.initial(), Reglages.Canal.EFFETS, 1)
	_neuf(hote)
	Audio.jouer("son_victoire", 4, plein)
	var ampli_fort: float = Audio.amplitude_poussee()
	var frames_fort: int = Audio.frames_poussees()
	_neuf(hote)
	Audio.jouer("son_victoire", 5, bas)
	var ampli_faible: float = Audio.amplitude_poussee()
	h.gt(int(ampli_fort * 1000.0), int(ampli_faible * 1000.0),
		"v4.p1: ce qui entre dans le tampon suit le reglage de volume")
	h.eq(Audio.frames_poussees(), frames_fort,
		"v4.p1: le COMPTE, lui, ne varie pas — c'est l'amplitude qui porte le reglage")
	_neuf(hote)
	Audio.jouer("son_victoire", 6, Reglages.avec_muet(Reglages.initial(), true))
	h.eq(int(Audio.amplitude_poussee() * 1000.0), 0, "v4.p1: le coupe-son rend le silence")
	h.gt(Audio.frames_poussees(), 0, "v4.p1: et pourtant des frames sont bien poussees")

	# --- LE CHEMIN EST REFERMABLE : l'etat global ne survit pas a son installateur. ---
	Audio.detacher_lecteur()
	h.eq(Audio.lecteur(), null, "v4.p1: le lecteur est debranche")
	h.eq(Audio.lecture_active(), false, "v4.p1: le chemin est referme")
	Audio.reinitialiser()
	h.eq(int(Audio.jouer("son_mort", 7)["frames"]), 0, "v4.p1: sans lecteur, plus rien n'est pousse")
	arbre.root.remove_child(hote)
	hote.free()

	# --- LE RUNTIME LE BRANCHE REELLEMENT. Un chemin de lecture qu'aucun executeur
	# n'ouvre n'existe pas dans le jeu : c'etait EXACTEMENT le defaut. ---
	var source: String = _texte(CHEMIN_RUNTIME)
	h.gt(source.length(), 0, "v4.p1: la boucle du runtime est lisible")
	h.ok(source.find("Audio.brancher_lecteur(self)") >= 0,
		"v4.p1: la boucle du runtime branche le lecteur sur elle-meme")
	h.ok(source.find("Audio.jouer_musique(") >= 0, "v4.p1: elle joue la piste musicale")
	h.ok(source.find("Audio.jouer_evenements(") >= 0, "v4.p1: elle joue les moments de jeu")
