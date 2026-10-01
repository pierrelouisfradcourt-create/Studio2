extends RefCounted
## Recettes sonores de Dungeon 666 — la « fiche de sound design ».
## Portage de GAMES/dungeon_666/src/audio/recipes.mjs : mêmes couches, mêmes fréquences (Hz),
## mêmes durées (s), mêmes gains relatifs. Le niveau de mixage par son est dans routage.gd.
##
## Différence de fond avec le web : là-bas une recette est JOUÉE en direct, avec la hauteur et
## les couches choisies d'après l'événement. Ici chaque recette est RENDUE une fois (synthese.gd)
## et rejouée ; ce qui variait en continu (hauteur, force) est réglé à la lecture, et ce qui
## variait par choix de couches devient une recette par variante (`coup_0`, `coup_2`,
## `equipement_3`…). Un son composé de parties de hauteurs indépendantes (le corps d'un impact et
## son éclat de critique) reste en recettes séparées, superposées à la lecture.
##
## Rien ici ne lit la simulation.

const S = preload("res://jeu/son/synthese.gd")

const TAUX := 44100 # Hz
const FIXE := 0.0 # fréquence d'arrivée d'une couche à hauteur fixe
const GRAINE_BRUIT := 666
const DEMI_TONS_PAR_OCTAVE := 12.0

# Notes de référence (Hz).
const NOTE := {
	"G2": 98.0, "C3": 130.81, "E3": 164.81, "G3": 196.0, "C4": 261.63, "A4": 440.0,
	"C5": 523.25, "E5": 659.26, "G5": 783.99, "B5": 987.77, "C6": 1046.5, "E6": 1318.51, "A6": 1760.0,
}
const MAJEUR := [0.0, 4.0, 7.0, 12.0]
const ACCORD_MAJEUR := [0.0, 4.0, 7.0]
const QUINTE := [0.0, 7.0]
const ACCORD_MINEUR := [0.0, 3.0, 7.0]
const PARTIELS_CLOCHE := [[1.0, 1.0], [2.0, 0.5], [2.4, 0.3], [3.0, 0.2], [4.2, 0.12]]
const PARTIELS_METAL := [[1.0, 1.0], [2.32, 0.45], [4.25, 0.25]]

const ECLAIRS := 3 # variantes d'éclair (crépitements tirés au hasard, une fois)
const ETINCELLES_ECLAIR := 5
const FENETRE_ETINCELLES := 0.08 # s
const GAIN_ETINCELLES := [0.25, 0.55]
const RARETES_BENEDICTION := {
	"commun": {"decalage": 0.0, "intervalles": [0.0, 4.0, 7.0, 12.0]},
	"rare": {"decalage": 2.0, "intervalles": [0.0, 4.0, 7.0, 12.0, 16.0]},
	"epique": {"decalage": 5.0, "intervalles": [0.0, 4.0, 7.0, 12.0, 14.0, 16.0, 19.0, 24.0]},
}
const ETINCELLES_EQUIPEMENT := 3 # 0 (commun) à 3 (légendaire)

static var _table: Dictionary = {}

# ---------------------------------------------------------------- outillage des tables

static func perc(a: float, r: float) -> Dictionary:
	return S.perc(a, r)

static func adsr(a: float, d: float, s: float, h: float, r: float) -> Dictionary:
	return S.adsr(a, d, s, h, r)

## Couche tonale (forme d'onde `forme`, glissando freq -> vers ; vers = FIXE : hauteur fixe).
static func ton(forme: String, freq: float, vers: float, env: Dictionary, gain: float, plus: Dictionary = {}) -> Dictionary:
	var c := {"src": "tone", "type": forme, "freq": freq, "to": vers, "env": env, "gain": gain}
	c.merge(plus, true)
	return c

## Couche de bruit filtré (`filtre` : lowpass | highpass | bandpass).
static func souffle(filtre: String, freq: float, vers: float, q: float, env: Dictionary, gain: float, plus: Dictionary = {}) -> Dictionary:
	var c := {"src": "noise", "type": filtre, "freq": freq, "to": vers, "q": q, "env": env, "gain": gain}
	c.merge(plus, true)
	return c

static func demi_tons(f: float, n: float) -> float:
	return f * pow(2.0, n / DEMI_TONS_PAR_OCTAVE)

## Accord arpégé : une couche par intervalle (demi-tons au-dessus de la fondamentale), décalées
## de `pas`. Comme sur le web, un `at` donné dans `plus` l'emporte : les notes partent ensemble.
static func accord(forme: String, fondamentale: float, intervalles: Array, pas: float, env: Dictionary, gain: float, plus: Dictionary = {}) -> Array:
	var out: Array = []
	for i in intervalles.size():
		var c := ton(forme, demi_tons(fondamentale, intervalles[i]), FIXE, env, gain, {"at": i * pas})
		c.merge(plus, true)
		out.append(c)
	return out

## Cloche : partiels inharmoniques d'une même fondamentale, extinctions décroissantes.
static func cloche(fondamentale: float, partiels: Array, at: float, relache: float, gain: float) -> Array:
	var out: Array = []
	for p in partiels:
		out.append(ton("sine", fondamentale * p[0], FIXE, perc(0.002, relache / sqrt(p[0])), gain * p[1], {"at": at}))
	return out

## Copie des couches à une autre hauteur et à un autre gain (une recette composée).
static func accorder(couches: Array, hauteur: float, gain: float = 1.0) -> Array:
	var out: Array = []
	for c in couches:
		var d: Dictionary = c.duplicate()
		d.freq = c.freq * hauteur
		d.to = c.to * hauteur
		d.gain = c.gain * gain
		out.append(d)
	return out

# ---------------------------------------------------------------- la table

## Nom de recette -> liste de couches. Construite une fois (sur le fil principal), dans l'ordre
## où les sons sont rendus : les plus fréquents d'abord, les longs à la fin.
static func table() -> Dictionary:
	if _table.is_empty():
		var t := {}
		_interface(t)
		_coups(t)
		_impacts(t)
		_mouvement(t)
		_heros_touche(t)
		_butin(t)
		_cris_sbires(t)
		_dangers(t)
		_competences(t)
		_gadgets(t)
		_supers(t)
		_cris_gardiens(t)
		_benedictions_equipement(t)
		_salles(t)
		_fins(t)
		_table = t
	return _table

static func noms() -> Array:
	return table().keys()

static func _interface(t: Dictionary) -> void:
	# Clic de menu (absent du web, où la Ville est en HTML) : petit « toc » clair.
	t["clic"] = [
		ton("sine", 1400.0, 900.0, perc(0.001, 0.035), 0.4),
		souffle("highpass", 4000.0, FIXE, 0.7, perc(0.001, 0.012), 0.25),
	]
	t["choix"] = accord("triangle", NOTE.G5, QUINTE, 0.04, perc(0.005, 0.4), 0.08)
	t["dash_pret"] = [ton("sine", 2200.0, FIXE, perc(0.001, 0.03), 0.5)]

# ---------------------------------------------------------------- combat du héros

static func _coups(t: Dictionary) -> void:
	# Index de combo 0 et 1 : coups vifs en miroir ; 2 : coup final ample et grave.
	t["coup_0"] = [souffle("bandpass", 900.0, 2600.0, 1.2, perc(0.012, 0.11), 0.55)]
	t["coup_1"] = [souffle("bandpass", 1150.0, 3000.0, 1.2, perc(0.012, 0.1), 0.55)]
	t["coup_2"] = [
		souffle("bandpass", 480.0, 2000.0, 0.9, perc(0.02, 0.2), 0.8),
		ton("sine", 150.0, 60.0, perc(0.005, 0.14), 0.45),
	]
	# Frappe de dash : souffle plus long + lame qui chante.
	t["coup_frappe"] = [
		souffle("bandpass", 700.0, 3400.0, 1.6, perc(0.015, 0.16), 0.75),
		ton("triangle", 1500.0, 900.0, perc(0.004, 0.18), 0.12),
	]
	# Arc : corde pincée + souffle bref ; arbalète (et trait lourd) : déclic sec et plus grave.
	t["tir_arc"] = [
		ton("triangle", 520.0, 190.0, perc(0.002, 0.09), 0.35),
		souffle("bandpass", 2400.0, 5200.0, 2.0, perc(0.004, 0.07), 0.45),
	]
	t["tir_lourd"] = [
		ton("square", 210.0, 90.0, perc(0.002, 0.07), 0.3, {"filter": {"type": "lowpass", "freq": 1600.0}}),
		souffle("bandpass", 1500.0, 4200.0, 1.6, perc(0.003, 0.1), 0.6),
		souffle("highpass", 4000.0, FIXE, 0.7, perc(0.001, 0.02), 0.35),
	]

static func _impacts(t: Dictionary) -> void:
	# Impact : coup sourd + clic. Le coup lourd AJOUTE un corps grave.
	var corps := [
		ton("sine", 165.0, 55.0, perc(0.002, 0.11), 0.9),
		souffle("highpass", 3500.0, FIXE, 0.7, perc(0.001, 0.02), 0.45),
		souffle("bandpass", 900.0, 400.0, 1.2, perc(0.002, 0.05), 0.35),
	]
	t["impact"] = corps
	t["impact_lourd"] = corps + [
		ton("sine", 95.0, 38.0, perc(0.003, 0.2), 0.8),
		souffle("lowpass", 600.0, 150.0, 0.8, perc(0.003, 0.12), 0.5),
	]
	# Critique : partiels aigus cristallins, hauteur indépendante de la force du coup.
	t["critique"] = [
		ton("sine", 2637.0, FIXE, perc(0.001, 0.22), 0.2),
		ton("sine", 3951.0, FIXE, perc(0.001, 0.15), 0.12),
		ton("triangle", 5274.0, FIXE, perc(0.001, 0.08), 0.06),
	]
	t["brulure"] = [souffle("highpass", 2500.0, 4000.0, 0.7, perc(0.002, 0.04), 0.4)]
	t["mort"] = [
		souffle("bandpass", 2200.0, FIXE, 1.4, perc(0.001, 0.06), 1.4),
		ton("square", 260.0, 70.0, perc(0.002, 0.09), 0.45, {"filter": {"type": "lowpass", "freq": 1500.0}}),
		souffle("lowpass", 900.0, 200.0, 0.8, perc(0.003, 0.18), 1.0),
	]
	t["mort_elite"] = [
		ton("sine", 80.0, 40.0, perc(0.005, 0.35), 0.7),
		souffle("bandpass", 1200.0, 300.0, 1.0, perc(0.005, 0.3), 0.35),
	]
	t["parade"] = cloche(1480.0, PARTIELS_METAL, 0.0, 0.3, 0.25) + [
		souffle("highpass", 5000.0, FIXE, 0.7, perc(0.001, 0.015), 0.25),
	]
	for i in ECLAIRS:
		t["eclair_%d" % i] = _eclair(i)

## Éclair en chaîne : bourdonnement + crépitements à instants tirés une fois pour toutes.
static func _eclair(variante: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6660 + variante
	var couches := [
		ton("sawtooth", 90.0, FIXE, perc(0.002, 0.09), 0.15, {"filter": {"type": "bandpass", "freq": 2500.0, "q": 2.0}}),
		ton("square", 1800.0, 600.0, perc(0.001, 0.05), 0.05),
	]
	for i in ETINCELLES_ECLAIR:
		var at := rng.randf() * FENETRE_ETINCELLES
		var gain := lerpf(GAIN_ETINCELLES[0], GAIN_ETINCELLES[1], rng.randf())
		couches.append(souffle("highpass", 3000.0, FIXE, 0.7, perc(0.0005, 0.012), gain, {"at": at}))
	return couches

static func _mouvement(t: Dictionary) -> void:
	t["dash"] = [
		souffle("bandpass", 350.0, 2600.0, 0.9, adsr(0.03, 0.05, 0.6, 0.04, 0.09), 0.65),
		ton("sine", 180.0, 420.0, perc(0.02, 0.12), 0.12),
	]
	# Esquive « parfaite » : arpège très aigu + poussière d'étoiles.
	t["esquive"] = [
		ton("sine", NOTE.A6, FIXE, perc(0.002, 0.12), 0.22),
		ton("sine", demi_tons(NOTE.A6, 5.0), FIXE, perc(0.002, 0.12), 0.2, {"at": 0.03}),
		ton("sine", demi_tons(NOTE.A6, 10.0), FIXE, perc(0.002, 0.18), 0.18, {"at": 0.06}),
		souffle("highpass", 7000.0, FIXE, 0.7, perc(0.005, 0.12), 0.12),
	]

# ---------------------------------------------------------------- héros touché

static func _heros_touche(t: Dictionary) -> void:
	t["blessure"] = [
		ton("sine", 120.0, 55.0, perc(0.003, 0.25), 0.9),
		ton("sawtooth", 200.0, 90.0, perc(0.003, 0.18), 0.35, {"drive": true, "filter": {"type": "lowpass", "freq": 1400.0}}),
		souffle("lowpass", 1000.0, FIXE, 0.8, perc(0.001, 0.08), 0.5),
	]

# ---------------------------------------------------------------- butin

static func _butin(t: Dictionary) -> void:
	# Pièce : deux notes aiguës (mi puis la).
	var piece := [
		ton("triangle", NOTE.E6, FIXE, perc(0.002, 0.07), 0.25),
		ton("square", NOTE.E6, FIXE, perc(0.002, 0.05), 0.04),
		ton("triangle", NOTE.A6, FIXE, perc(0.002, 0.18), 0.25, {"at": 0.06}),
		ton("square", NOTE.A6, FIXE, perc(0.002, 0.1), 0.04, {"at": 0.06}),
	]
	t["piece"] = piece
	t["piece_achat"] = piece + [ton("triangle", NOTE.B5, FIXE, perc(0.002, 0.25), 0.2, {"at": 0.12})]
	t["soin"] = accord("sine", NOTE.C5, ACCORD_MAJEUR, 0.06, adsr(0.03, 0.05, 0.6, 0.05, 0.25), 0.14, {"vibrato": {"rate": 6.0, "cents": 8.0}}) + [
		souffle("highpass", 6000.0, FIXE, 0.7, adsr(0.05, 0.1, 0.5, 0.1, 0.2), 0.05),
	]

# ---------------------------------------------------------------- ennemis et dangers

## Télégraphes : petits cris discrets, un timbre par type d'ennemi.
static func _cris_sbires(t: Dictionary) -> void:
	t["cri_defaut"] = [ton("square", 500.0, 700.0, perc(0.005, 0.06), 0.1, {"filter": {"type": "lowpass", "freq": 1500.0}})]
	t["cri_imp"] = [ton("square", 650.0, 1050.0, perc(0.005, 0.08), 0.45, {"filter": {"type": "lowpass", "freq": 2000.0}})]
	t["cri_archer"] = [
		ton("triangle", 330.0, 620.0, perc(0.004, 0.12), 0.6),
		souffle("bandpass", 1800.0, FIXE, 3.0, perc(0.002, 0.04), 0.3),
	]
	t["cri_brute"] = [
		ton("sawtooth", 95.0, 70.0, adsr(0.04, 0.1, 0.6, 0.1, 0.15), 0.4, {"drive": true, "filter": {"type": "lowpass", "freq": 450.0}}),
		souffle("lowpass", 350.0, FIXE, 0.8, perc(0.05, 0.25), 0.3),
	]
	t["cri_charger"] = [
		souffle("bandpass", 600.0, 300.0, 2.0, perc(0.02, 0.2), 0.7),
		ton("sawtooth", 150.0, 110.0, perc(0.02, 0.18), 0.3, {"filter": {"type": "lowpass", "freq": 700.0}}),
	]
	# Pyromancienne : les cercles de feu apparaissent — souffle qui s'embrase (grave -> aigu).
	t["cri_pyromancer"] = [
		souffle("bandpass", 500.0, 1800.0, 1.4, adsr(0.03, 0.08, 0.6, 0.08, 0.2), 0.55),
		ton("sawtooth", 120.0, 190.0, perc(0.03, 0.22), 0.18, {"filter": {"type": "lowpass", "freq": 900.0}}),
	]
	# Nécromancien : la canalisation commence — psalmodie qui descend, voix creuse.
	t["cri_necromancer"] = [
		ton("triangle", 330.0, 220.0, adsr(0.08, 0.15, 0.6, 0.25, 0.3), 0.28, {"glide": 0.6}),
		ton("sine", 165.0, 110.0, adsr(0.08, 0.15, 0.6, 0.25, 0.3), 0.22, {"glide": 0.6}),
	]
	# Porte-pavois : le coup de pavois part — choc sourd du bois ferré + tintement de bronze.
	t["cri_pavois"] = [
		ton("square", 140.0, 85.0, perc(0.004, 0.16), 0.4, {"filter": {"type": "lowpass", "freq": 600.0}}),
		souffle("bandpass", 2400.0, FIXE, 4.0, perc(0.002, 0.07), 0.35),
	]
	# Traqueur : il resurgit dans le dos — souffle qui monte, sifflement de lame (aigu, bref : on se retourne).
	t["cri_stalker"] = [
		souffle("bandpass", 900.0, 3200.0, 2.5, perc(0.01, 0.16), 0.5),
		ton("sine", 880.0, 1500.0, perc(0.005, 0.1), 0.14),
	]
	# Élite invocateur : même famille que le nécromancien, plus aigu (un champion, pas un mage).
	t["cri_summon"] = [
		ton("triangle", 440.0, 300.0, adsr(0.06, 0.12, 0.6, 0.2, 0.25), 0.24, {"glide": 0.5}),
		ton("sine", 220.0, 150.0, adsr(0.06, 0.12, 0.6, 0.2, 0.25), 0.18, {"glide": 0.5}),
	]

static func _dangers(t: Dictionary) -> void:
	# Explosion / zone qui frappe : boum basse fréquence + craquement.
	t["explosion"] = [
		ton("sine", 95.0, 32.0, perc(0.004, 0.45), 1.0),
		souffle("lowpass", 1100.0, 120.0, 0.7, perc(0.003, 0.4), 0.7),
		souffle("bandpass", 2500.0, FIXE, 1.0, perc(0.001, 0.03), 0.3),
	]
	t["explosion_feu"] = [souffle("highpass", 1800.0, 3500.0, 0.7, adsr(0.01, 0.05, 0.4, 0.1, 0.25), 0.25)]
	t["annulation"] = [
		souffle("highpass", 2000.0, 800.0, 0.7, perc(0.005, 0.15), 0.2),
		ton("sine", 600.0, 300.0, perc(0.005, 0.12), 0.05),
	]
	# Projeté contre un mur / bélier qui s'écrase : choc lourd.
	t["choc"] = [
		ton("sine", 75.0, 32.0, perc(0.003, 0.3), 1.0),
		souffle("lowpass", 600.0, 150.0, 0.8, perc(0.002, 0.18), 0.7),
		souffle("bandpass", 1800.0, FIXE, 1.0, perc(0.001, 0.025), 0.35),
	]
	t["apparition"] = [
		ton("sine", 330.0, 520.0, adsr(0.08, 0.05, 0.6, 0.05, 0.15), 0.5),
		souffle("bandpass", 1200.0, FIXE, 4.0, adsr(0.08, 0.05, 0.6, 0.05, 0.15), 0.4),
	]
	t["invocation"] = [
		ton("sawtooth", 140.0, 100.0, adsr(0.05, 0.1, 0.6, 0.15, 0.25), 0.3, {"drive": true, "filter": {"type": "lowpass", "freq": 800.0}}),
		souffle("bandpass", 800.0, 300.0, 1.0, perc(0.03, 0.35), 0.3),
	]

# ---------------------------------------------------------------- kits (classes, armes, aptitudes)

static func _competences(t: Dictionary) -> void:
	# Lance infernale : sifflement montant + air + poussée de flamme.
	t["competence"] = [
		ton("sine", 900.0, 2400.0, adsr(0.01, 0.05, 0.7, 0.06, 0.12), 0.22, {"glide": 0.18, "vibrato": {"rate": 18.0, "cents": 25.0}}),
		ton("sine", 1800.0, 4800.0, perc(0.01, 0.15), 0.05, {"glide": 0.18}),
		souffle("bandpass", 2500.0, 6000.0, 2.0, perc(0.01, 0.2), 0.35),
		souffle("lowpass", 600.0, FIXE, 0.8, perc(0.005, 0.12), 0.3),
	]
	# Chaîne d'Enfer : cliquetis de maillons qui file.
	t["competence_chain"] = [souffle("bandpass", 3200.0, 1800.0, 3.0, perc(0.003, 0.18), 0.5)] + cloche(880.0, PARTIELS_METAL, 0.0, 0.18, 0.12) + [
		ton("square", 300.0, 520.0, perc(0.004, 0.12), 0.08, {"filter": {"type": "lowpass", "freq": 2200.0}}),
	]
	# Bond : élan grave qui monte.
	t["competence_bond"] = [
		souffle("bandpass", 300.0, 1400.0, 0.8, adsr(0.02, 0.05, 0.6, 0.08, 0.2), 0.7),
		ton("sine", 120.0, 260.0, perc(0.01, 0.2), 0.25),
	]
	# Brasier d'âmes : pot qui siffle en l'air.
	t["competence_brasier"] = [
		ton("sine", 700.0, 1500.0, adsr(0.01, 0.05, 0.6, 0.05, 0.2), 0.15, {"glide": 0.3}),
		souffle("bandpass", 1200.0, 2600.0, 1.4, perc(0.01, 0.2), 0.35),
	]
	# Volée d'épines : rafale de souffles aigus.
	t["competence_volee"] = [
		souffle("bandpass", 2600.0, 5800.0, 2.0, perc(0.004, 0.08), 0.45),
		souffle("bandpass", 2200.0, 5000.0, 2.0, perc(0.004, 0.08), 0.35, {"at": 0.025}),
		souffle("bandpass", 3000.0, 6200.0, 2.0, perc(0.004, 0.08), 0.3, {"at": 0.05}),
	]

static func _gadgets(t: Dictionary) -> void:
	# Nova de cendres : onde grave + souffle qui retombe. (Rejouée plus aiguë : nova de dash.)
	t["gadget"] = [
		ton("sine", 85.0, 42.0, perc(0.005, 0.5), 1.0),
		souffle("bandpass", 1600.0, 250.0, 0.8, adsr(0.02, 0.1, 0.5, 0.1, 0.3), 0.6),
		ton("triangle", 170.0, 85.0, perc(0.005, 0.25), 0.25),
	]
	# Bombe : lancer (souffle) — l'explosion vient avec `explode`.
	t["gadget_bombe"] = [
		souffle("bandpass", 600.0, 1800.0, 1.0, perc(0.01, 0.16), 0.5),
		ton("sine", 220.0, 140.0, perc(0.005, 0.12), 0.15),
	]
	# Piège : déclic métallique d'armement.
	t["gadget_piege"] = cloche(1240.0, PARTIELS_METAL, 0.0, 0.16, 0.2) + [
		souffle("highpass", 4500.0, FIXE, 0.7, perc(0.001, 0.02), 0.3),
	]
	# Cri du bourreau : rugissement grave, saturé.
	t["gadget_cri"] = [
		ton("sawtooth", 110.0, 70.0, adsr(0.02, 0.1, 0.7, 0.15, 0.35), 0.3, {"drive": true, "filter": {"type": "lowpass", "freq": 900.0, "to": 300.0}}),
		souffle("bandpass", 500.0, 250.0, 0.9, adsr(0.02, 0.1, 0.6, 0.15, 0.3), 0.5),
	]
	# Totem de givre : carillon cristallin.
	t["gadget_totem"] = cloche(NOTE.E6, PARTIELS_CLOCHE, 0.0, 0.5, 0.12) + [
		ton("sine", NOTE.B5, FIXE, perc(0.005, 0.4), 0.08, {"at": 0.05}),
	]

static func _supers(t: Dictionary) -> void:
	t["super_coup"] = [souffle("bandpass", 900.0, 1600.0, 1.5, perc(0.01, 0.07), 0.5)]
	# Exécution de la Sentence : choc lourd. Trait de la Nuée : pincement bref.
	t["super_coup_sentence"] = [
		ton("sine", 85.0, 35.0, perc(0.003, 0.35), 0.9),
		souffle("lowpass", 1200.0, 200.0, 0.8, perc(0.003, 0.25), 0.6),
	]
	t["super_coup_nuee"] = [
		ton("triangle", 900.0, 400.0, perc(0.002, 0.05), 0.2),
		souffle("bandpass", 3500.0, FIXE, 2.0, perc(0.002, 0.04), 0.25),
	]
	t["super_fin"] = [
		souffle("bandpass", 1600.0, 400.0, 1.0, perc(0.01, 0.25), 0.3),
		ton("sine", 220.0, 110.0, perc(0.01, 0.2), 0.1),
	]
	t["super_pret"] = accord("triangle", NOTE.A4, MAJEUR, 0.025, perc(0.005, 0.35), 0.16) + [
		ton("sine", demi_tons(NOTE.A6, 12.0), FIXE, perc(0.002, 0.2), 0.05, {"at": 0.08}),
	]
	# Super « Colère » : impact immédiat (aucune latence) puis montée puissante.
	var montee := adsr(0.05, 0.2, 0.8, 0.25, 0.4)
	t["super"] = [
		ton("sine", 90.0, 40.0, perc(0.003, 0.4), 0.9),
		souffle("lowpass", 900.0, FIXE, 0.8, perc(0.003, 0.35), 0.6),
		ton("sawtooth", 110.0, 440.0, montee, 0.22, {"glide": 0.55, "drive": true, "filter": {"type": "lowpass", "freq": 300.0, "to": 3200.0}}),
		ton("sawtooth", 165.0, 660.0, montee, 0.14, {"glide": 0.55, "detune": 8.0, "filter": {"type": "lowpass", "freq": 300.0, "to": 3200.0}}),
		ton("sine", 55.0, FIXE, adsr(0.3, 0.2, 0.8, 0.2, 0.5), 0.6),
		souffle("highpass", 400.0, 4000.0, 0.7, adsr(0.3, 0.05, 0.6, 0.1, 0.3), 0.25),
	]
	# Sentence : coup de gong grave, puis la lame qui se lève.
	t["super_sentence"] = cloche(NOTE.G2, PARTIELS_CLOCHE, 0.0, 1.4, 0.5) + [
		ton("sawtooth", 70.0, 140.0, adsr(0.05, 0.2, 0.7, 0.3, 0.5), 0.2, {"drive": true, "filter": {"type": "lowpass", "freq": 400.0, "to": 1800.0}}),
	]
	# Nuée : montée scintillante.
	t["super_nuee"] = accord("triangle", NOTE.E5, MAJEUR, 0.03, perc(0.005, 0.4), 0.1) + [
		souffle("highpass", 3000.0, 7000.0, 0.7, adsr(0.1, 0.1, 0.6, 0.2, 0.4), 0.2),
	]

## Cris d'attaque des Gardiens (champ `enemy` de enemyAttack) : un timbre par modèle.
static func _cris_gardiens(t: Dictionary) -> void:
	t["cri_boss"] = [
		ton("sawtooth", 75.0, 58.0, adsr(0.05, 0.1, 0.7, 0.15, 0.25), 0.5, {"drive": true, "filter": {"type": "lowpass", "freq": 520.0}}),
		souffle("lowpass", 400.0, FIXE, 0.8, perc(0.05, 0.4), 0.35),
	]
	t["cri_bossRing"] = [
		ton("sine", 280.0, 900.0, adsr(0.08, 0.1, 0.8, 0.1, 0.15), 0.15, {"glide": 0.35}),
		ton("triangle", 560.0, 1800.0, adsr(0.08, 0.1, 0.8, 0.1, 0.15), 0.06, {"glide": 0.35}),
	]
	# Cerbère : aboiement rauque (bruit grave + carré qui chute).
	t["cri_cerbere"] = [
		souffle("bandpass", 700.0, 260.0, 2.5, perc(0.01, 0.22), 0.7),
		ton("square", 210.0, 120.0, perc(0.01, 0.2), 0.3, {"filter": {"type": "lowpass", "freq": 900.0}}),
	]
	# Minos : coup de marteau du Juge, cloche sombre.
	t["cri_minos"] = cloche(NOTE.G2, PARTIELS_CLOCHE, 0.0, 0.6, 0.35) + [
		souffle("bandpass", 1500.0, FIXE, 2.0, perc(0.001, 0.04), 0.2),
	]
	# Colosse : grondement d'effort, très grave, saturé.
	t["cri_colosse"] = [
		ton("sawtooth", 55.0, 42.0, adsr(0.06, 0.12, 0.7, 0.2, 0.3), 0.55, {"drive": true, "filter": {"type": "lowpass", "freq": 380.0}}),
		souffle("lowpass", 300.0, FIXE, 0.8, perc(0.06, 0.45), 0.4),
	]
	var cri := adsr(0.08, 0.15, 0.8, 0.5, 0.45)
	t["rugissement"] = [
		ton("sawtooth", 85.0, 62.0, cri, 0.45, {"glide": 1.0, "drive": true, "tremolo": {"rate": 28.0, "depth": 0.3}, "filter": {"type": "lowpass", "freq": 700.0, "to": 400.0}}),
		ton("sawtooth", 86.5, 63.0, cri, 0.35, {"glide": 1.0, "filter": {"type": "lowpass", "freq": 700.0, "to": 400.0}}),
		souffle("lowpass", 500.0, FIXE, 0.8, adsr(0.1, 0.2, 0.7, 0.4, 0.5), 0.5),
		ton("sine", 45.0, FIXE, perc(0.01, 1.2), 0.8),
	]
	t["mort_gardien"] = [
		ton("sine", 60.0, 25.0, perc(0.01, 1.4), 1.0),
		souffle("lowpass", 1200.0, 80.0, 0.7, perc(0.01, 1.6), 0.8),
		ton("sawtooth", 110.0, 40.0, perc(0.02, 1.2), 0.25, {"drive": true, "filter": {"type": "lowpass", "freq": 700.0, "to": 200.0}}),
	]

# ---------------------------------------------------------------- progression

## Bénédiction : accord majeur lumineux ; la rareté monte la tonalité et enrichit l'accord.
static func _benediction(rarete: String) -> Array:
	var r: Dictionary = RARETES_BENEDICTION[rarete]
	return accord("triangle", demi_tons(NOTE.C5, r.decalage), r.intervalles, 0.02, adsr(0.01, 0.15, 0.5, 0.2, 0.6), 0.13) + [
		ton("sine", demi_tons(NOTE.C6, 12.0), FIXE, perc(0.002, 0.4), 0.05, {"at": 0.1}),
		ton("sine", demi_tons(NOTE.C6, 19.0), FIXE, perc(0.002, 0.4), 0.04, {"at": 0.14}),
	]

static func _benedictions_equipement(t: Dictionary) -> void:
	for rarete in RARETES_BENEDICTION:
		t["benediction_" + rarete] = _benediction(rarete)
	# Équipement : cliquetis métallique + cuir ; étincelles selon la rareté de l'objet.
	var base := [
		souffle("bandpass", 2800.0, FIXE, 3.0, perc(0.001, 0.06), 1.0),
		ton("square", 320.0, 260.0, perc(0.002, 0.08), 0.3, {"filter": {"type": "lowpass", "freq": 1800.0}}),
		ton("triangle", 960.0, FIXE, perc(0.002, 0.2), 0.25),
		souffle("lowpass", 500.0, FIXE, 0.8, perc(0.01, 0.1), 0.6),
	]
	var notes := [NOTE.E6, NOTE.A6, demi_tons(NOTE.A6, 4.0)]
	for n in ETINCELLES_EQUIPEMENT + 1:
		var couches := base.duplicate()
		for i in n:
			couches.append(ton("sine", notes[i], FIXE, perc(0.002, 0.3), 0.15, {"at": 0.08 + i * 0.05}))
		t["equipement_%d" % n] = couches

## Salle nettoyée : cloche grave + accord ; Gardien : une quarte plus bas et plus long.
static func _salle(fondamentale: float, relache: float, gain: float) -> Array:
	var chant := accord("triangle", NOTE.C4, ACCORD_MAJEUR, 0.04, adsr(0.02, 0.2, 0.5, 0.2, 0.6), 0.1, {"at": 0.08})
	return cloche(fondamentale, PARTIELS_CLOCHE, 0.0, relache, gain) + accorder(chant, fondamentale / NOTE.C3)

static func _salles(t: Dictionary) -> void:
	t["portes"] = [
		souffle("lowpass", 250.0, 700.0, 1.0, adsr(0.08, 0.1, 0.7, 0.25, 0.25), 0.5),
		ton("sine", 55.0, 50.0, adsr(0.05, 0.1, 0.8, 0.3, 0.3), 0.4),
		souffle("bandpass", 400.0, FIXE, 1.0, perc(0.003, 0.1), 0.4, {"at": 0.6}),
	]
	var entree := [
		souffle("bandpass", 2000.0, 250.0, 0.7, adsr(0.05, 0.1, 0.6, 0.15, 0.3), 0.4),
		ton("sine", NOTE.G3, NOTE.G3 / 2.0, adsr(0.02, 0.1, 0.6, 0.2, 0.5), 0.25),
	]
	t["etage"] = entree
	# Étage de Gardien : bourdon grave qui bat (deux dents de scie désaccordées).
	var bourdon := adsr(0.3, 0.2, 0.7, 0.6, 0.8)
	t["etage_gardien"] = entree + [
		ton("sawtooth", 55.0, FIXE, bourdon, 0.18, {"filter": {"type": "lowpass", "freq": 300.0}}),
		ton("sawtooth", 58.3, FIXE, bourdon, 0.18, {"filter": {"type": "lowpass", "freq": 300.0}}),
	]
	t["salle_nettoyee"] = _salle(NOTE.C3, 1.6, 0.5)
	t["salle_gardien"] = _salle(NOTE.G2, 2.6, 0.6)
	var carillon: Array = []
	var notes := [NOTE.E5, NOTE.B5, demi_tons(NOTE.E5, 12.0)]
	for i in notes.size():
		carillon += cloche(notes[i], PARTIELS_METAL, i * 0.12, 1.4, 0.18)
	t["checkpoint"] = carillon + [ton("sine", NOTE.E3, FIXE, adsr(0.1, 0.3, 0.6, 0.5, 1.0), 0.2)]

static func _fins(t: Dictionary) -> void:
	t["mort_heros"] = [
		ton("sawtooth", 220.0, 38.0, adsr(0.01, 0.2, 0.7, 0.4, 0.9), 0.35, {"glide": 1.4, "drive": true, "filter": {"type": "lowpass", "freq": 2200.0, "to": 180.0}}),
		ton("sine", 70.0, 28.0, perc(0.005, 1.3), 0.9),
		souffle("lowpass", 1500.0, 100.0, 0.7, perc(0.01, 1.2), 0.5),
		ton("triangle", 440.0, 110.0, perc(0.02, 0.9), 0.12, {"at": 0.15}),
	]
	t["fin_de_partie"] = cloche(NOTE.G2, PARTIELS_CLOCHE, 0.0, 2.5, 0.6) + accord("triangle", NOTE.G3, ACCORD_MINEUR, 0.08, adsr(0.3, 0.3, 0.6, 0.6, 1.5), 0.06)
	# Victoire : la cloche du Gardien vaincu + la bénédiction la plus riche.
	t["victoire"] = _salle(NOTE.G2, 2.6, 0.6) + _benediction("epique")

# ---------------------------------------------------------------- rendu

## Le bruit blanc partagé par tous les rendus d'une même passe.
static func bruit() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GRAINE_BRUIT
	return S.bruit_blanc(TAUX, rng)

## Ouvre le rendu d'une recette (à faire avancer couche par couche : `avancer`, puis `conclure`).
static func commencer(nom: String, tampon_bruit: PackedFloat32Array) -> Dictionary:
	var travail := S.commencer(table()[nom], TAUX, tampon_bruit, hash(nom))
	travail["nom"] = nom
	return travail

static func avancer(travail: Dictionary) -> bool:
	return S.avancer(travail)

## Ferme le rendu : { flux (AudioStreamWAV 16 bits mono), niveau (gain à rendre à la lecture :
## le son est rangé normalisé), duree (s), crete_brute, octets }.
static func conclure(travail: Dictionary) -> Dictionary:
	var signal_brut := S.terminer(travail)
	var pic := S.crete(signal_brut)
	var coupe := S.rogner(signal_brut, pic)
	var octets := S.vers_pcm16(coupe, pic, TAUX)
	return {
		"flux": S.vers_flux(octets, TAUX),
		"niveau": pic / S.CRETE_CIBLE,
		"duree": coupe.size() / float(TAUX),
		"crete_brute": pic,
		"octets": octets.size(),
	}

## Rendu d'un trait.
static func rendre(nom: String, tampon_bruit: PackedFloat32Array) -> Dictionary:
	var travail := commencer(nom, tampon_bruit)
	while not avancer(travail):
		pass
	return conclure(travail)
