# audio.gd — ADAPTATEUR AUDIO (category system.adapter, allowed_deps []).
#
# SON ENTIEREMENT GENERE A L'EXECUTION, patron de synthese repris de
# games/pacman/06_RUNTIME/adapters/audio/audio.gd (AudioStreamGenerator + enveloppe + table
# d'ondes + journal des declenchements). DEVIATION ASSUMEE ET DECLAREE : la carte gelee donne
# a `audio` `allowed_deps: []` et ne declare QUE ce fichier ; une copie octet-fidele de
# l'audio pacman est IMPOSSIBLE ici car elle preload `sound_bank.gd` et `settings.gd` a des
# adresses que la carte kitten_clicker ne declare pas — ce qui violerait a la fois
# `allowed_deps: []` et « la carte fait loi ». Les descripteurs et le gain sont donc INLINE :
# le PATRON est reutilise, pas les octets (la carte gelee ne porte aucun `copy_sha256` a
# egaler). Un declenchement par evenement de jeu, avec un id de son DISTINCT, journalise.
extends Node

const FREQUENCE_ECHANTILLONNAGE: float = 22050.0
const TAMPON_SECONDES: float = 0.5

# Quatre evenements de jeu -> quatre descripteurs de son DISTINCTS (hauteur/onde propres).
const CUE_CLICK: String = "click"
const CUE_PURCHASE: String = "purchase"
const CUE_UNLOCK: String = "unlock"
const CUE_PRESTIGE: String = "prestige"

const DESCRIPTEURS: Dictionary = {
	"click":    {"hauteur_hz": 880.0, "duree_ms": 90,  "onde": "carree",   "volume": 0.4},
	"purchase": {"hauteur_hz": 523.0, "duree_ms": 160, "onde": "triangle", "volume": 0.5},
	"unlock":   {"hauteur_hz": 659.0, "duree_ms": 260, "onde": "sinus",    "volume": 0.6},
	"prestige": {"hauteur_hz": 392.0, "duree_ms": 380, "onde": "dent",     "volume": 0.7},
}

# JOURNAL statique des declenchements (id de son, tick, echantillons synthetises). Sans lui,
# « un son a ete joue » n'aurait aucun observateur en headless. NON economique : c'est une
# feuille de side-effect, reinitialisee par son oracle (jamais un etat de gameplay).
static var _journal: Array = []

var _lecteur: AudioStreamPlayer = null


static func reinitialiser() -> void:
	_journal = []


static func journal() -> Array:
	return _journal


# Ids de son DISTINCTS reellement declenches, dans l'ordre, sans doublon.
static func cues_distincts() -> Array:
	var out: Array = []
	for e in _journal:
		if not out.has(String(e["cue"])):
			out.append(String(e["cue"]))
	return out


func _ready() -> void:
	var flux := AudioStreamGenerator.new()
	flux.mix_rate = FREQUENCE_ECHANTILLONNAGE
	flux.buffer_length = TAMPON_SECONDES
	_lecteur = AudioStreamPlayer.new()
	_lecteur.stream = flux
	add_child(_lecteur)
	if _lecteur.is_inside_tree():
		_lecteur.play()


static func onde(forme: String, phase: float) -> float:
	if forme == "carree":
		return 1.0 if phase < 0.5 else -1.0
	if forme == "triangle":
		return 4.0 * absf(phase - 0.5) - 1.0
	if forme == "dent":
		return 2.0 * phase - 1.0
	return sin(TAU * phase)


static func enveloppe(t: float, duree: float) -> float:
	if t < 0.0 or t > duree:
		return 0.0
	var bord: float = 0.02
	if t < bord:
		return t / bord
	var reste: float = duree - t
	if reste < bord:
		return reste / bord
	return 1.0


# Echantillons SYNTHETISES a l'execution pour un descripteur — la suite rendue n'existe
# dans aucun fichier du depot (invariant ZERO ASSET audio).
static func echantillons(desc: Dictionary) -> PackedFloat32Array:
	var sortie := PackedFloat32Array()
	if desc.is_empty():
		return sortie
	var duree: float = float(desc["duree_ms"]) / 1000.0
	var n: int = int(FREQUENCE_ECHANTILLONNAGE * duree)
	var hauteur: float = float(desc["hauteur_hz"])
	var volume: float = float(desc["volume"])
	var forme: String = String(desc["onde"])
	sortie.resize(n)
	for i in range(n):
		var t: float = float(i) / FREQUENCE_ECHANTILLONNAGE
		var phase: float = fmod(t * hauteur, 1.0)
		sortie[i] = onde(forme, phase) * enveloppe(t, duree) * volume
	return sortie


# DECLENCHE le son d'un evenement nomme : synthetise, pousse dans le lecteur si branche, et
# INSCRIT au journal avec le tick. Rend le constat, jamais un booleen nu.
func play_cue(cue: String, tick: int) -> Dictionary:
	var desc: Dictionary = DESCRIPTEURS.get(cue, {})
	var buffer: PackedFloat32Array = echantillons(desc)
	var frames: int = _pousser(buffer)
	var entree: Dictionary = {
		"cue": cue, "tick": tick, "echantillons": buffer.size(), "frames": frames,
	}
	_journal.append(entree)
	return entree


func _pousser(buffer: PackedFloat32Array) -> int:
	if _lecteur == null or not _lecteur.playing:
		return 0
	var lecture = _lecteur.get_stream_playback()
	if lecture == null:
		return 0
	var pousses: int = 0
	for v in buffer:
		if lecture.get_frames_available() <= 0:
			break
		lecture.push_frame(Vector2(v, v))
		pousses += 1
	return pousses
