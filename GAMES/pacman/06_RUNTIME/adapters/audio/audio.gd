# audio.gd — SON ENTIEREMENT GENERE A L'EXECUTION (lignes audio.runtime_synthesis,
# audio.six_cues_fire, audio.positive_control, core.audio).
#
# Le son est FABRIQUE au moment ou il est joue, a partir d'un descripteur de synthese
# (forme d'onde, hauteur, duree, enveloppe), via AudioStreamGenerator : AUCUN echantillon
# n'est lu depuis un fichier. C'est la seule voie qui satisfait a la fois core.audio et
# l'invariant ZERO ASSET — l'inventaire du jeu porte exactement 0 fichier audio.
#
# SEULE couche a connaitre une API audio de la plateforme : AudioStream,
# AudioStreamGenerator, AudioStreamPlayer, AudioServer sont references ICI et nulle part
# dans 05_SYSTEMS. C'est ce qui donne au comptage statique son CONTROLE POSITIF — un
# projet sans audio du tout passerait le test a 0 sans rien prouver.
extends RefCounted

const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

# Noms des API audio de plateforme referencees ici : la liste sert au controle positif,
# elle ne remplace pas les references reelles ci-dessous.
const API_PLATEFORME: Array = [
	"AudioStream", "AudioStreamGenerator", "AudioStreamPlayer", "AudioServer",
]

const TAMPON_SECONDES: float = 0.5

# JOURNAL des declenchements : un moment, le tick ou il a ete declenche, le nombre
# d'echantillons REELLEMENT synthetises. Sans cette trace, « un son a ete joue » n'aurait
# aucun observateur en headless.
static var _journal: Array = []
# JOURNAL SEPARE de la piste musicale (V3) : `moments_joues` / `moments_muets` comptent
# les SIX moments de jeu ; une note de fond n'est pas un moment de jeu et n'a pas a
# entrer dans ce comptage, sous peine de le rendre illisible.
static var _journal_musique: Array = []


# --- CHEMIN DE LECTURE (V4, cause racine P1) --------------------------------------
# DEFAUT MESURE (playtest Pierre : « la musique j'ai rien ») — l'audit a montre plus
# large que le rapport : RIEN ne sortait, bruitages compris. `jouer()` et
# `jouer_musique()` synthetisaient un tampon, l'inscrivaient au journal, puis RENDAIENT.
# Aucun `AudioStreamPlayer` n'existait dans le jeu et `pousser()` n'etait appele que par
# des tests, avec `null`. La synthese etait complete, le CHEMIN DE LECTURE absent — cas
# d'ecole de « preuve sans executeur » : les tests lisaient le journal, donc passaient.
#
# Le lecteur branche est tenu ICI parce que c'est le seul endroit qui connaisse une API
# audio de plateforme. Le journal RESTE (il donne un observateur en headless), il ne
# suffit plus : ce qui est synthetise est desormais POUSSE dans un playback reel.
static var _lecteur: AudioStreamPlayer = null
# Frames REELLEMENT poussees dans le tampon du lecteur, et amplitude maximale de ce qui y
# est entre. Le compte prouve l'ALIMENTATION du chemin ; l'amplitude prouve que le
# reglage de volume l'atteint — un tampon a gain nul garde sa longueur.
static var _frames_poussees: int = 0
static var _amplitude_poussee: float = 0.0
# Rang de note DEJA pousse : la piste avance par note, pas par tick. Sans cela un tick de
# 150 ms pousserait une note de 180 ms a chaque fois et saturerait le tampon.
static var _rang_pousse: int = -1


static func reinitialiser() -> void:
	_journal = []
	_journal_musique = []
	_frames_poussees = 0
	_amplitude_poussee = 0.0
	_rang_pousse = -1


static func journal() -> Array:
	return _journal


static func journal_musique() -> Array:
	return _journal_musique


# Flux GENERE : un AudioStreamGenerator configure a la frequence declaree. Aucun fichier
# n'est charge — l'objet est construit, pas importe.
static func fabriquer_flux() -> AudioStreamGenerator:
	var flux := AudioStreamGenerator.new()
	flux.mix_rate = Bank.FREQUENCE_ECHANTILLONNAGE
	flux.buffer_length = TAMPON_SECONDES
	return flux


# Un flux fabrique est-il bien un AudioStream de la plateforme ?
static func est_flux_de_plateforme(flux) -> bool:
	return flux is AudioStream


# Enveloppe d'amplitude a l'instant t (en secondes) : attaque lineaire puis chute
# lineaire. Deterministe, sans aucune horloge de plateforme.
static func enveloppe(t: float, desc: Dictionary) -> float:
	var duree: float = float(desc["duree_ms"]) / 1000.0
	if t < 0.0 or t > duree:
		return 0.0
	var attaque: float = float(desc["attaque_ms"]) / 1000.0
	var chute: float = float(desc["chute_ms"]) / 1000.0
	if attaque > 0.0 and t < attaque:
		return t / attaque
	var reste: float = duree - t
	if chute > 0.0 and reste < chute:
		return reste / chute
	return 1.0


# Valeur de l'onde a la phase donnee (phase dans [0, 1[).
static func onde(forme: String, phase: float) -> float:
	if forme == Bank.ONDE_CARREE:
		return 1.0 if phase < 0.5 else -1.0
	if forme == Bank.ONDE_TRIANGLE:
		return 4.0 * absf(phase - 0.5) - 1.0
	if forme == Bank.ONDE_DENT_DE_SCIE:
		return 2.0 * phase - 1.0
	return sin(TAU * phase)


# ECHANTILLONS SYNTHETISES a l'execution pour un descripteur. C'est ici que le son est
# FABRIQUE : la suite rendue n'existe dans aucun fichier du depot.
# `gain` est le VOLUME GLOBAL du canal (V3, cause racine P6), distinct du `volume` du
# descripteur qui dose ce son-la. Les deux se MULTIPLIENT : un bruitage discret le reste
# quel que soit le reglage, et le reglage a un effet sur TOUS les sons a la fois.
static func echantillons(desc: Dictionary, gain: float = 1.0) -> PackedFloat32Array:
	var sortie := PackedFloat32Array()
	if desc.is_empty():
		return sortie
	var taux: float = Bank.FREQUENCE_ECHANTILLONNAGE
	var duree: float = float(desc["duree_ms"]) / 1000.0
	var n: int = int(taux * duree)
	var hauteur: float = float(desc["hauteur_hz"])
	var volume: float = float(desc["volume"]) * gain
	var forme: String = String(desc["onde"])
	sortie.resize(n)
	for i in range(n):
		var t: float = float(i) / taux
		var phase: float = fmod(t * hauteur, 1.0)
		sortie[i] = onde(forme, phase) * enveloppe(t, desc) * volume
	return sortie


# AMPLITUDE MAXIMALE d'un tampon : c'est cette grandeur, et non le nombre d'echantillons,
# qui rend le reglage de volume OBSERVABLE — un tampon a gain nul garde sa longueur.
static func amplitude_max(buffer: PackedFloat32Array) -> float:
	var m: float = 0.0
	for v in buffer:
		if absf(v) > m:
			m = absf(v)
	return m


# DECLENCHE le son d'un moment nomme : synthetise le flux et l'inscrit au journal, avec
# le TICK de son declenchement. Rend le constat, jamais un booleen nu.
# `reglages` est REMIS par l'appelant ; absent, le canal des effets vaut son defaut
# declare — le son du run V2 est alors reproduit a l'identique.
static func jouer(moment: String, tick: int, reglages: Dictionary = {}) -> Dictionary:
	var desc: Dictionary = Bank.descripteur(moment)
	if desc.is_empty():
		return {"joue": false, "moment": moment, "tick": tick, "echantillons": 0, "amplitude": 0.0}
	var gain: float = Reglages.gain_effectif(reglages, Reglages.Canal.EFFETS)
	var buffer: PackedFloat32Array = echantillons(desc, gain)
	var entree: Dictionary = {
		"joue": buffer.size() > 0,
		"moment": moment,
		"tick": tick,
		"echantillons": buffer.size(),
		"amplitude": amplitude_max(buffer),
		# V4 : ce qui a REELLEMENT atteint le lecteur de plateforme. Sans lecteur branche
		# la valeur vaut 0 et le dit — elle ne se confond jamais avec `echantillons`.
		"frames": pousser_buffer(_lecteur, buffer),
	}
	_journal.append(entree)
	return entree


# Branche la liste d'evenements sonores d'un tick : CHACUN sur SON PROPRE descripteur.
static func jouer_evenements(evenements: Array, tick: int, reglages: Dictionary = {}) -> Array:
	var sortie: Array = []
	for e in evenements:
		sortie.append(jouer(String(e), tick, reglages))
	return sortie


# --- PISTE MUSICALE (V3, cause racine P3) -----------------------------------------
# La musique emprunte le MEME moteur de synthese que les bruitages : meme enveloppe,
# meme table d'ondes, meme AudioStreamGenerator. Rien n'est double, rien n'est importe.

# Echantillons d'UNE note de la piste, au rang demande.
static func echantillons_note(rang: int, reglages: Dictionary = {}) -> PackedFloat32Array:
	var desc: Dictionary = Bank.descripteur_note(rang)
	if float(desc["hauteur_hz"]) == Bank.SILENCE_HZ:
		# Un silence de la piste est une note de duree pleine et d'amplitude nulle : la
		# boucle garde sa mesure. Un tampon vide la ferait accelerer.
		var n: int = int(Bank.FREQUENCE_ECHANTILLONNAGE * float(desc["duree_ms"]) / 1000.0)
		var muet := PackedFloat32Array()
		muet.resize(n)
		return muet
	return echantillons(desc, Reglages.gain_effectif(reglages, Reglages.Canal.MUSIQUE))


# DECLENCHE la note courante de la piste a partir du temps de lecture ecoule. Le rang
# est DERIVE du temps, jamais d'un compteur interne : deux lectures du meme instant
# rendent la meme note.
static func jouer_musique(ms: float, reglages: Dictionary = {}) -> Dictionary:
	var rang: int = Bank.rang_note(ms)
	var buffer: PackedFloat32Array = echantillons_note(rang, reglages)
	# UNE note poussee PAR NOTE, pas par appel : la piste avance au rythme qu'elle
	# declare, jamais a celui du cadenceur qui l'interroge.
	var frames: int = 0
	if rang != _rang_pousse:
		frames = pousser_buffer(_lecteur, buffer)
		_rang_pousse = rang
	var entree: Dictionary = {
		"rang": rang,
		"hauteur": Bank.hauteur_note(rang),
		"ms": ms,
		"echantillons": buffer.size(),
		"amplitude": amplitude_max(buffer),
		"frames": frames,
	}
	_journal_musique.append(entree)
	return entree


# Rangs de notes REELLEMENT joues, dans l'ordre du journal : c'est ce releve qui donne un
# OBSERVATEUR a la piste en headless, ou aucun haut-parleur ne temoigne.
static func rangs_joues() -> Array:
	var sortie: Array = []
	for e in _journal_musique:
		sortie.append(int(e["rang"]))
	return sortie


# Nombre de HAUTEURS DISTINCTES effectivement jouees : une piste qui n'en produirait
# qu'une ne serait pas une piste (regle de variance).
static func hauteurs_jouees() -> int:
	var vues: Array = []
	for e in _journal_musique:
		var f: float = float(e["hauteur"])
		if f == Bank.SILENCE_HZ:
			continue
		if not vues.has(f):
			vues.append(f)
	return vues.size()


# Moments effectivement declenches, sans doublon, dans l'ordre du journal.
static func moments_joues() -> Array:
	var sortie: Array = []
	for e in _journal:
		if not sortie.has(e["moment"]):
			sortie.append(e["moment"])
	return sortie


# Nombre des six moments restes MUETS. La valeur attendue vaut exactement 0.
static func moments_muets() -> int:
	var joues: Array = moments_joues()
	var n: int = 0
	for m in Bank.MOMENTS:
		if not joues.has(m):
			n += 1
	return n


# Lecteur de plateforme, construit UNIQUEMENT quand un parent de scene est fourni. En
# headless (aucun parent), la synthese a deja eu lieu : le son est genere, il n'est
# simplement pas rendu par un peripherique. L'echec eventuel est NOMME, jamais silencieux.
#
# V4 : le lecteur est RETENU (il devient le destinataire de jouer/jouer_musique) et la
# LECTURE EST DEMARREE. Le moteur refuse `play()` sur un noeud hors arbre ; la condition
# est donc verifiee au lieu d'etre supposee, et un refus laisse `lecture_active()` faux
# plutot que de faire croire a un son.
static func brancher_lecteur(parent: Node) -> AudioStreamPlayer:
	if parent == null:
		return null
	var lecteur := AudioStreamPlayer.new()
	lecteur.stream = fabriquer_flux()
	parent.add_child(lecteur)
	if lecteur.is_inside_tree():
		lecteur.play()
	_lecteur = lecteur
	return lecteur


static func lecteur() -> AudioStreamPlayer:
	return _lecteur


# Le chemin de lecture est-il REELLEMENT ouvert ? Trois conditions, toutes verifiees :
# un lecteur existe, il joue, et le moteur rend un playback ou pousser des frames.
static func lecture_active() -> bool:
	if _lecteur == null or not _lecteur.playing:
		return false
	return _lecteur.get_stream_playback() != null


static func frames_poussees() -> int:
	return _frames_poussees


static func amplitude_poussee() -> float:
	return _amplitude_poussee


# Debranche le lecteur : l'etat global ne survit pas a celui qui l'a installe.
static func detacher_lecteur() -> void:
	if _lecteur == null:
		return
	if not is_instance_valid(_lecteur):
		_lecteur = null
		return
	if _lecteur.playing:
		_lecteur.stop()
	var parent: Node = _lecteur.get_parent()
	if parent != null:
		parent.remove_child(_lecteur)
	_lecteur.free()
	_lecteur = null


# LE CHEMIN DE LECTURE LUI-MEME : les echantillons synthetises entrent dans le tampon du
# playback de plateforme. Rend le nombre de frames REELLEMENT poussees — jamais un
# booleen, qui ne distinguerait pas « pousse » de « pousse quelque chose ».
static func pousser_buffer(lecteur_cible: AudioStreamPlayer, buffer: PackedFloat32Array) -> int:
	if lecteur_cible == null or not lecteur_cible.playing:
		return 0
	var lecture = lecteur_cible.get_stream_playback()
	if lecture == null:
		return 0
	var pousses: int = 0
	for v in buffer:
		if lecture.get_frames_available() <= 0:
			break
		lecture.push_frame(Vector2(v, v))
		pousses += 1
		if absf(v) > _amplitude_poussee:
			_amplitude_poussee = absf(v)
	_frames_poussees += pousses
	return pousses


# Ecrit les echantillons synthetises d'un moment nomme dans le tampon du lecteur.
static func pousser(lecteur_cible: AudioStreamPlayer, moment: String) -> int:
	return pousser_buffer(lecteur_cible, echantillons(Bank.descripteur(moment)))


# Frequence de melange declaree par le serveur audio de la plateforme : reference
# explicite a AudioServer, part du controle positif.
static func frequence_serveur() -> float:
	return AudioServer.get_mix_rate()
