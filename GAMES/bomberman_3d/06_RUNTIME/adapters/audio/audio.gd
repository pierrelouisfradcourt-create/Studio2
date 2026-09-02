# audio.gd — SON ENTIEREMENT GENERE A L'EXECUTION. Satisfait `core.audio` sans introduire
# le moindre fichier audio dans le depot.
#
# reused_from = CONCEPT (games/pacman/06_RUNTIME/adapters/audio/audio.gd) : synthese par
# AudioStreamGenerator a partir d'un descripteur, plus un JOURNAL des declenchements —
# sans ce journal, « un son a ete joue » n'aurait aucun observateur en headless, et
# l'exigence serait invérifiable donc invérifiée.
#
# SEULE couche a connaitre une API audio de la plateforme. Aucun fichier de 05_SYSTEMS n'en
# reference une : c'est ce qui donne au comptage statique son CONTROLE POSITIF — un projet
# SANS audio du tout passerait un test « 0 API audio dans la logique » sans rien prouver.
extends Node

const Cues = preload("res://05_SYSTEMS/sound_cues/sound_cues.gd")

# Noms des API audio de plateforme referencees ici. Sert au controle positif ; ne remplace
# pas les references reelles ci-dessous.
const API_PLATEFORME: Array = ["AudioStreamGenerator", "AudioStreamPlayer", "AudioServer"]

const FREQUENCE: int = 22050
const TAMPON_S: float = 0.5

# JOURNAL des declenchements : {cue, tick, echantillons}. C'est l'artefact observable.
static var journal: Array = []

# JOURNAL SEPARE de la musique. Separe a dessein : un effet et une piste ne se prouvent
# pas de la meme facon, et les melanger masquerait qu'une des deux est muette.
#
# DEFAUT DU PARC EVITE PAR CONSTRUCTION : `games/pacman/.../audio.gd` documente un defaut
# mesure au playtest (« la musique j'ai rien ») — la fonction synthetisait un tampon,
# l'inscrivait au journal, puis RENDAIT sans jamais pousser les trames. Le journal disait
# donc qu'une musique jouait alors qu'aucun echantillon ne sortait. Ici la seule grandeur
# qui compte est `echantillons`, ce qui est REELLEMENT pousse ; le compte d'entrees de
# journal ne prouve rien et l'oracle ne le regarde pas.
static var journal_musique: Array = []

# MOTIF de la piste : degres d'une gamme mineure, en demi-tons depuis la tonique.
# Une piste n'est pas un effet : elle boucle, elle est BASSE en gain, et elle ne doit
# jamais couvrir un signal de danger.
const MOTIF: Array = [0, 3, 7, 10, 7, 3]
const MUSIQUE_TONIQUE_HZ: float = 146.83   # re2
const MUSIQUE_NOTE_MS: int = 260
const MUSIQUE_GAIN: float = 0.12

var _joueur: AudioStreamPlayer = null
var _muet: bool = false

# VOLUMES, en facteur [0,1]. Portee SESSION : `app_state` les detient en pourcentage et les
# pousse ici. Aucun nouveau systeme audio — ils multiplient le gain deja declare par
# `sound_cues`, au seul endroit ou l'amplitude est calculee.
var volume_musique: float = 1.0
var volume_effets: float = 1.0


# AMPLITUDE REELLEMENT APPLIQUEE. Une seule source de verite pour la synthese ET pour la
# preuve : sans elle, un test pourrait verifier le reglage sans que la synthese le lise, et
# « le volume est branche » resterait une affirmation. Le journal l'enregistre.
func amplitude_effet(cue: String) -> float:
	var d: Dictionary = Cues.descripteur(cue)
	if d.is_empty():
		return 0.0
	return float(d["gain"]) * volume_effets


func amplitude_musique() -> float:
	return MUSIQUE_GAIN * volume_musique


func _ready() -> void:
	_joueur = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(FREQUENCE)
	gen.buffer_length = TAMPON_S
	_joueur.stream = gen
	add_child(_joueur)
	_joueur.play()


# Mode MUET : la synthese n'est pas tentee, mais le journal continue d'enregistrer. Sert
# aux executions headless, ou aucun peripherique audio n'existe — l'exigence reste
# observable sans pretendre qu'un son est sorti d'un haut-parleur.
func muet(v: bool) -> void:
	_muet = v


static func reinitialiser_journal() -> void:
	journal = []
	journal_musique = []


# Hauteur d'une note du motif, en hertz. PURE : temperament egal, 12 demi-tons par octave.
static func hauteur_note(index: int) -> float:
	var demi: int = int(MOTIF[index % MOTIF.size()])
	return MUSIQUE_TONIQUE_HZ * pow(2.0, float(demi) / 12.0)


# Echantillon d'une onde, a une phase donnee. PUR et sans etat : c'est cette fonction que
# l'on peut verifier hors moteur.
static func echantillon(onde: int, phase: float, graine: int) -> float:
	match onde:
		Cues.ONDE_CARREE:
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		Cues.ONDE_TRIANGLE:
			var f: float = fmod(phase, 1.0)
			return 4.0 * abs(f - 0.5) - 1.0
		Cues.ONDE_BRUIT:
			# Bruit DETERMINISTE par graine : deux executions produisent le meme son, ce qui
			# garde le rejeu comparable. Un `randf()` casserait cette propriete.
			var g: int = (graine * 1103515245 + 12345) % 2147483648
			return float(g % 2000) / 1000.0 - 1.0
		_:
			return 0.0


# Declenche un moment sonore. Rend le nombre d'echantillons REELLEMENT synthetises — 0 en
# mode muet ou si le moment n'existe pas. Le journal, lui, enregistre toujours la demande.
func jouer(cue: String, tick: int) -> int:
	var d: Dictionary = Cues.descripteur(cue)
	if d.is_empty():
		return 0
	var vises: int = Cues.echantillons(cue, FREQUENCE)
	var produits: int = 0
	var gain: float = amplitude_effet(cue)
	if not _muet and _joueur != null:
		var pb = _joueur.get_stream_playback()
		if pb != null:
			var libres: int = pb.get_frames_available()
			var n: int = min(vises, libres)
			var pas: float = float(d["hz"]) / float(FREQUENCE)
			for i in range(n):
				var t: float = float(i) / float(max(1, vises))
				var env: float = pow(1.0 - t, 1.0 + float(d["chute"]) * 3.0)
				var v: float = echantillon(int(d["onde"]), float(i) * pas, i) * gain * env
				pb.push_frame(Vector2(v, v))
			produits = n
	journal.append({"cue": cue, "tick": tick, "echantillons": produits, "vises": vises,
		"amplitude": gain})
	return produits


# Joue UNE note de la piste musicale. Rend le nombre d'echantillons REELLEMENT pousses —
# c'est cette valeur, et elle seule, qui prouve que la musique sort.
func jouer_musique(index: int, tick: int) -> int:
	var vises: int = int(float(MUSIQUE_NOTE_MS) * float(FREQUENCE) / 1000.0)
	var produits: int = 0
	var gain_m: float = amplitude_musique()
	if not _muet and _joueur != null:
		var pb = _joueur.get_stream_playback()
		if pb != null:
			var hz: float = hauteur_note(index)
			var n: int = min(vises, pb.get_frames_available())
			var pas: float = hz / float(FREQUENCE)
			for i in range(n):
				var t2: float = float(i) / float(max(1, vises))
				# Enveloppe douce aux deux bouts : une note de piste ne claque pas.
				var env: float = min(1.0, t2 * 8.0) * min(1.0, (1.0 - t2) * 4.0)
				var v: float = echantillon(Cues.ONDE_TRIANGLE, float(i) * pas, i) * gain_m * env
				pb.push_frame(Vector2(v, v))
			produits = n
	journal_musique.append({"index": index, "tick": tick, "echantillons": produits,
		"vises": vises, "amplitude": gain_m})
	return produits


# Consomme les evenements d'un tick et declenche les sons correspondants.
# Rend le nombre de moments declenches.
func consommer(events: Array, tick: int) -> int:
	var n: int = 0
	for e in events:
		var cue: String = Cues.cue_pour_evenement(String(e["kind"]))
		if cue == "":
			continue
		jouer(cue, tick)
		n += 1
	return n
