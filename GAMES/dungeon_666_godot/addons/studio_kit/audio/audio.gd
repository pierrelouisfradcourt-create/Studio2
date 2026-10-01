class_name StudioAudio
extends Node

## Son commun : musique avec fondu enchaîné, bruitages en polyphonie limitée, anti-rafale.
## Hérité de l'audio_adapter de Kitten Factory, rendu générique : aucun nom de son en dur,
## les volumes passent par les BUS (réglés par StudioReglages), plus par chaque lecteur.
##
## Aucune logique de jeu : il joue ce qu'on lui demande.

const VOIX_EFFETS := 6
const FONDU_DEFAUT := 0.8
const VOLUME_MUET_DB := -80.0
const ENTETE_WAV := 44

var dossier: String = ""
var _flux: Dictionary = {}
var _musiques: Array[AudioStreamPlayer] = []
var _musique_active := 0
var _voix: Array[AudioStreamPlayer] = []
var _tour := 0
var _dernier: Dictionary = {}


func _init(dossier_sons: String = "") -> void:
	dossier = dossier_sons


func _ready() -> void:
	StudioReglages.assurer_bus()
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = StudioReglages.BUS_MUSIQUE
		add_child(m)
		_musiques.append(m)
	for i in VOIX_EFFETS:
		var p := AudioStreamPlayer.new()
		p.bus = StudioReglages.BUS_EFFETS
		add_child(p)
		_voix.append(p)


## Charge `nom` (sans extension) depuis `dossier` : .ogg/.wav importés, sinon lecture brute du WAV.
func flux(nom: String) -> AudioStream:
	if _flux.has(nom):
		return _flux[nom]
	var s: AudioStream = null
	for ext in [".ogg", ".wav", ".mp3"]:
		var chemin := dossier.path_join(nom + ext)
		if ResourceLoader.exists(chemin):
			s = load(chemin)
			break
		if ext == ".wav" and FileAccess.file_exists(chemin):
			s = StudioAudio.lire_wav(FileAccess.get_file_as_bytes(chemin))
			break
	_flux[nom] = s
	return s


## Musique en boucle ; si une autre joue, fondu enchaîné.
func musique(nom: String, fondu: float = FONDU_DEFAUT) -> void:
	var s := flux(nom)
	if s == null:
		return
	_boucler(s)
	var ancienne := _musiques[_musique_active]
	_musique_active = 1 - _musique_active
	var nouvelle := _musiques[_musique_active]
	nouvelle.stream = s
	nouvelle.volume_db = VOLUME_MUET_DB
	nouvelle.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(nouvelle, "volume_db", 0.0, fondu)
	if ancienne.playing:
		t.tween_property(ancienne, "volume_db", VOLUME_MUET_DB, fondu)
		t.chain().tween_callback(ancienne.stop)


func musique_joue() -> bool:
	return not _musiques.is_empty() and _musiques[_musique_active].playing


func arreter_musique(fondu: float = FONDU_DEFAUT) -> void:
	var m := _musiques[_musique_active]
	if not m.playing:
		return
	var t := create_tween()
	t.tween_property(m, "volume_db", VOLUME_MUET_DB, fondu)
	t.tween_callback(m.stop)


## Bruitage court. `anti_rafale` (s) : ne rejoue pas le même son plus vite que ça.
## Bus Effets muet : rien n'est joué (pas de travail inutile ; c'était aussi le comportement de
## l'audio_adapter de Kitten Factory avant le kit).
func jouer(nom: String, anti_rafale: float = 0.0) -> bool:
	var bus := AudioServer.get_bus_index(StudioReglages.BUS_EFFETS)
	if bus != -1 and AudioServer.is_bus_mute(bus):
		return false
	var s := flux(nom)
	if s == null:
		return false
	var t := Time.get_ticks_msec() / 1000.0
	if anti_rafale > 0.0 and t - float(_dernier.get(nom, -INF)) < anti_rafale:
		return false
	_dernier[nom] = t
	var p := _voix[_tour % _voix.size()]
	_tour += 1
	p.stream = s
	p.play()
	return true


func _boucler(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = w.data.size() / (4 if w.stereo else 2)
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true


## Lecteur WAV PCM 16 bits (mono ou stéréo) -> AudioStreamWAV. null si ce n'est pas un WAV lisible.
static func lire_wav(octets: PackedByteArray) -> AudioStreamWAV:
	if octets.size() < ENTETE_WAV or octets.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var canaux := 1
	var taux := 22050
	var data := PackedByteArray()
	while pos + 8 <= octets.size():
		var id := octets.slice(pos, pos + 4).get_string_from_ascii()
		var taille := octets.decode_u32(pos + 4)
		if id == "fmt ":
			canaux = octets.decode_u16(pos + 10)
			taux = int(octets.decode_u32(pos + 12))
		elif id == "data":
			data = octets.slice(pos + 8, pos + 8 + taille)
			break
		pos += 8 + taille + (taille % 2)
	if data.is_empty():
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = taux
	w.stereo = canaux == 2
	w.data = data
	return w
