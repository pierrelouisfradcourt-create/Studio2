extends RefCounted
## Briques de synthèse HORS LIGNE — aucune ressource audio : tout naît d'oscillateurs et d'un
## bruit blanc, calculés une fois dans des PackedFloat32Array puis rangés en 16 bits mono.
## Portage de GAMES/dungeon_666/src/audio/synth.mjs (WebAudio), mêmes enveloppes, mêmes filtres.
##
## Vocabulaire :
##   couche  : une source enveloppée décrite par des DONNÉES (voir recettes.gd) :
##     { src: "tone" | "noise", type (forme d'onde, ou filtre du bruit), freq, to (fréquence
##       d'arrivée ; 0 : fixe), glide (durée du glissando, s), q, env, gain, at (décalage, s),
##       filter {type, freq, to, q} (tons), detune (cents), drive (saturation douce),
##       vibrato {rate, cents}, tremolo {rate, depth} }
##   travail : le rendu d'une liste de couches, qui avance UNE couche à la fois (`avancer`) :
##     on peut l'étaler sur plusieurs images ou le dérouler d'un trait (`rendre`).
##
## Ce script ne connaît ni le jeu ni ses événements. Il est sans état : on peut l'appeler
## depuis un fil d'exécution.

const SILENCE := 0.0001 # plancher des rampes exponentielles (comme WebAudio : jamais 0)
const ATTAQUE_MIN := 0.001 # s : une attaque nulle claque
const RELACHE_MIN := 0.005 # s
const FREQ_MIN := 20.0 # Hz
const GARDE_NYQUIST := 0.45 # fraction de la fréquence d'échantillonnage tolérée
const DURETE_SATURATION := 3.0 # dureté de la saturation douce (0 = transparente)
const BLOC_FILTRE := 32 # échantillons entre deux recalculs d'un filtre qui glisse
const Q_DEFAUT := 1.0
const BRUIT_SECONDES := 2.0 # durée du bruit blanc partagé (lu en boucle, départ au hasard)
const BRUIT_PLAGE_DEPART := 0.5 # fraction du tampon où tirer le point de départ
const MARGE_FIN := 0.002 # s de silence gardées après la dernière enveloppe
const CRETE_CIBLE := 0.9 # crête d'un son rangé (le niveau réel est rendu à la lecture)
const SEUIL_ROGNAGE := 0.0004 # fraction de la crête sous laquelle la queue est coupée
const FONDU_FIN := 0.003 # s : la coupe de la queue ne claque pas
const PCM_MAX := 32767.0
const CENTS_PAR_OCTAVE := 1200.0

# ---------------------------------------------------------------- enveloppes

## Enveloppe percussive : attaque `a` puis extinction `r` (secondes).
static func perc(a: float, r: float) -> Dictionary:
	return {"a": a, "d": 0.0, "s": 1.0, "h": 0.0, "r": r}

## Enveloppe ADSR : attaque, déclin vers `s` (fraction du pic), tenue `h`, relâche `r`.
static func adsr(a: float, d: float, s: float, h: float, r: float) -> Dictionary:
	return {"a": a, "d": d, "s": s, "h": h, "r": r}

static func duree_enveloppe(env: Dictionary) -> float:
	return maxf(ATTAQUE_MIN, env.a) + env.d + env.h + maxf(RELACHE_MIN, env.r)

## Segments [échantillons, gain de départ, pas additif, facteur] : attaque linéaire, déclin
## exponentiel vers la tenue, tenue, extinction exponentielle vers SILENCE.
static func segments(env: Dictionary, crete: float, taux: int) -> Array:
	var haut := maxf(SILENCE * 2.0, crete)
	var tenue := maxf(SILENCE, haut * clampf(env.s, 0.0, 1.0))
	var na := maxi(1, int(maxf(ATTAQUE_MIN, env.a) * taux))
	var segs: Array = [[na, SILENCE, (haut - SILENCE) / na, 1.0]]
	var niveau := haut
	if env.d > 0.0:
		var nd := maxi(1, int(env.d * taux))
		segs.append([nd, haut, 0.0, pow(tenue / haut, 1.0 / nd)])
		niveau = tenue
	if env.h > 0.0:
		segs.append([int(env.h * taux), niveau, 0.0, 1.0])
	var nr := maxi(1, int(maxf(RELACHE_MIN, env.r) * taux))
	segs.append([nr, niveau, 0.0, pow(SILENCE / niveau, 1.0 / nr)])
	return segs

## Ajoute `src` enveloppé dans `dest` à partir de l'échantillon `depart` (enveloppe + mixage).
static func poser(dest: PackedFloat32Array, src: PackedFloat32Array, segs: Array, depart: int) -> void:
	var limite := mini(src.size(), dest.size() - depart)
	var i := 0
	for s in segs:
		var g: float = s[1]
		var plus: float = s[2]
		var fois: float = s[3]
		var fin := mini(i + int(s[0]), limite)
		while i < fin:
			dest[depart + i] += src[i] * g
			g = g * fois + plus
			i += 1

# ---------------------------------------------------------------- sources

## Glissando : la fréquence de chaque échantillon (en cycles par échantillon), de `f0` à `f1`
## en `glisse` secondes, exponentiel, puis tenue. `f1` <= 0 : hauteur fixe.
static func glissando(f0: float, f1: float, glisse: float, n: int, taux: int) -> PackedFloat32Array:
	var haut := taux * GARDE_NYQUIST
	var depart := clampf(f0, FREQ_MIN, haut)
	var arrivee := depart if f1 <= 0.0 else clampf(f1, FREQ_MIN, haut)
	var inc := PackedFloat32Array()
	inc.resize(n)
	inc.fill(arrivee / taux)
	if arrivee == depart:
		return inc
	var ng := maxi(1, int(maxf(ATTAQUE_MIN, glisse) * taux))
	var r := pow(arrivee / depart, 1.0 / ng)
	var w := depart / taux
	for i in mini(n, ng):
		inc[i] = w
		w *= r
	return inc

## Vibrato : module la hauteur de ± `cents` à `rate` Hz (sur place).
static func vibrer(inc: PackedFloat32Array, rate: float, cents: float, taux: int) -> void:
	var pas := TAU * rate / taux
	var k := cents / CENTS_PAR_OCTAVE
	for i in inc.size():
		inc[i] *= pow(2.0, k * sin(pas * i))

## Oscillateur : "sine" | "square" | "sawtooth" | "triangle", à la fréquence donnée par `inc`.
static func oscillateur(forme: String, inc: PackedFloat32Array) -> PackedFloat32Array:
	match forme:
		"square":
			return _carre(inc)
		"sawtooth":
			return _scie(inc)
		"triangle":
			return _triangle(inc)
	return _sinus(inc)

static func _sinus(inc: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(inc.size())
	var ph := 0.0
	for i in inc.size():
		out[i] = sin(ph)
		ph += inc[i] * TAU
		if ph >= TAU:
			ph -= TAU
	return out

static func _triangle(inc: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(inc.size())
	var ph := 0.0
	for i in inc.size():
		var v := 4.0 * ph
		if ph > 0.75:
			v -= 4.0
		elif ph > 0.25:
			v = 2.0 - v
		out[i] = v
		ph += inc[i]
		if ph >= 1.0:
			ph -= 1.0
	return out

## Correction de marche (polyBLEP) : adoucit le saut d'une onde à fronts raides, sinon les
## harmoniques repliées donnent un grain numérique que WebAudio n'a pas.
static func _marche(ph: float, dt: float) -> float:
	if ph < dt:
		var x := ph / dt
		return x + x - x * x - 1.0
	if ph > 1.0 - dt:
		var y := (ph - 1.0) / dt
		return y * y + y + y + 1.0
	return 0.0

static func _scie(inc: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(inc.size())
	var ph := 0.5 # la dent de scie de WebAudio part de zéro en montant
	for i in inc.size():
		var dt := inc[i]
		var v := 2.0 * ph - 1.0
		if ph < dt or ph > 1.0 - dt:
			v -= _marche(ph, dt)
		out[i] = v
		ph += dt
		if ph >= 1.0:
			ph -= 1.0
	return out

static func _carre(inc: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(inc.size())
	var ph := 0.0
	for i in inc.size():
		var dt := inc[i]
		var v := 1.0 if ph < 0.5 else -1.0
		v += _marche(ph, dt) - _marche(fposmod(ph + 0.5, 1.0), dt)
		out[i] = v
		ph += dt
		if ph >= 1.0:
			ph -= 1.0
	return out

## Bruit blanc mono dans [-1, 1], à générer UNE fois puis à partager entre les rendus.
static func bruit_blanc(taux: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(taux * BRUIT_SECONDES)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf() * 2.0 - 1.0
	return out

## `n` échantillons du bruit partagé, lus en boucle depuis un point de départ au hasard.
static func tranche_bruit(bruit: PackedFloat32Array, n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var depart := int(rng.randf() * bruit.size() * BRUIT_PLAGE_DEPART)
	var out := bruit.slice(depart, mini(bruit.size(), depart + n))
	while out.size() < n:
		out.append_array(bruit.slice(0, mini(bruit.size(), n - out.size())))
	return out

# ---------------------------------------------------------------- filtres

## Filtre du second ordre (biquad), mêmes formules que le BiquadFilterNode de WebAudio :
## "lowpass" / "highpass" (q en décibels de résonance) et "bandpass" (q = finesse).
## Rend [b0, b1, b2, a1, a2] normalisés.
static func coefficients(type: String, freq: float, q: float, taux: int) -> PackedFloat64Array:
	var w := TAU * clampf(freq, FREQ_MIN, taux * GARDE_NYQUIST) / taux
	var c := cos(w)
	var s := sin(w)
	var b := PackedFloat64Array([0.0, 0.0, 0.0])
	var alpha := s / (2.0 * pow(10.0, q / 20.0))
	match type:
		"highpass":
			b = PackedFloat64Array([(1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0])
		"bandpass":
			alpha = s / (2.0 * maxf(0.0001, q))
			b = PackedFloat64Array([alpha, 0.0, -alpha])
		_:
			b = PackedFloat64Array([(1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0])
	var a0 := 1.0 + alpha
	return PackedFloat64Array([b[0] / a0, b[1] / a0, b[2] / a0, -2.0 * c / a0, (1.0 - alpha) / a0])

## Filtre `x` sur place ; la fréquence de coupure glisse de `f0` à `f1` (0 : fixe) en `glisse` s.
static func filtrer(x: PackedFloat32Array, type: String, f0: float, f1: float, glisse: float, q: float, taux: int) -> void:
	var n := x.size()
	var haut := taux * GARDE_NYQUIST
	var depart := clampf(f0, FREQ_MIN, haut)
	var arrivee := depart if f1 <= 0.0 else clampf(f1, FREQ_MIN, haut)
	var ng := maxf(1.0, maxf(ATTAQUE_MIN, glisse) * taux)
	var fixe := arrivee == depart
	var z1 := 0.0
	var z2 := 0.0
	var i := 0
	while i < n:
		var f := depart if fixe else depart * pow(arrivee / depart, minf(1.0, i / ng))
		var k := coefficients(type, f, q, taux)
		var b0 := k[0]
		var b1 := k[1]
		var b2 := k[2]
		var a1 := k[3]
		var a2 := k[4]
		var fin := n if (fixe or i >= ng) else mini(n, i + BLOC_FILTRE)
		while i < fin:
			var v := x[i]
			var y := b0 * v + z1
			z1 = b1 * v - a1 * y + z2
			z2 = b2 * v - a2 * y
			x[i] = y
			i += 1

# ---------------------------------------------------------------- modulation, saturation, mixage

## Trémolo : le gain oscille entre 1 - 2·depth et 1 (sur place).
static func tremolo(x: PackedFloat32Array, rate: float, depth: float, taux: int) -> void:
	var d := clampf(depth, 0.0, 0.5)
	var pas := TAU * rate / taux
	for i in x.size():
		x[i] *= 1.0 - d + d * sin(pas * i)

## Saturation douce : pente 1 près de zéro, crêtes arrondies (grain, pas de gain caché).
static func saturer(x: PackedFloat32Array) -> void:
	for i in x.size():
		var v := x[i]
		x[i] = v / (1.0 + DURETE_SATURATION * absf(v))

## Ajoute `src` dans `dest` (mixage simple, même longueur ou plus court).
static func melanger(dest: PackedFloat32Array, src: PackedFloat32Array, gain: float = 1.0) -> void:
	for i in mini(dest.size(), src.size()):
		dest[i] += src[i] * gain

static func crete(x: PackedFloat32Array) -> float:
	var m := 0.0
	for v in x:
		if v > m:
			m = v
		elif -v > m:
			m = -v
	return m

## Coupe la queue inaudible (sous `SEUIL_ROGNAGE` de la crête) ; rend le signal raccourci.
static func rogner(x: PackedFloat32Array, pic: float) -> PackedFloat32Array:
	var seuil := pic * SEUIL_ROGNAGE
	var n := x.size()
	while n > 1 and absf(x[n - 1]) < seuil:
		n -= 1
	return x.slice(0, n)

## Normalise à `CRETE_CIBLE` et range en 16 bits mono, avec un court fondu de fin.
static func vers_pcm16(x: PackedFloat32Array, pic: float, taux: int) -> PackedByteArray:
	var n := x.size()
	var k := (CRETE_CIBLE / pic if pic > 0.0 else 1.0) * PCM_MAX
	var octets := PackedByteArray()
	octets.resize(n * 2)
	var nf := mini(n, int(FONDU_FIN * taux))
	for i in n - nf:
		octets.encode_s16(i * 2, int(roundf(x[i] * k)))
	for j in nf:
		var i := n - nf + j
		octets.encode_s16(i * 2, int(roundf(x[i] * k * (nf - j) / nf)))
	return octets

static func vers_flux(octets: PackedByteArray, taux: int) -> AudioStreamWAV:
	var flux := AudioStreamWAV.new()
	flux.format = AudioStreamWAV.FORMAT_16_BITS
	flux.mix_rate = taux
	flux.stereo = false
	flux.data = octets
	return flux

# ---------------------------------------------------------------- rendu d'une liste de couches

## Une couche, sans son enveloppe : la source (ton ou bruit), son filtre, son trémolo.
static func rendre_couche(c: Dictionary, n: int, taux: int, bruit: PackedFloat32Array, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var glisse: float = c.get("glide", n / float(taux))
	var x: PackedFloat32Array
	if c.src == "noise":
		x = tranche_bruit(bruit, n, rng)
		filtrer(x, c.get("type", "bandpass"), c.freq, c.get("to", 0.0), glisse, c.get("q", Q_DEFAUT), taux)
	else:
		var k := pow(2.0, c.get("detune", 0.0) / CENTS_PAR_OCTAVE)
		var inc := glissando(c.freq * k, c.get("to", 0.0) * k, glisse, n, taux)
		if c.has("vibrato"):
			vibrer(inc, c.vibrato.rate, c.vibrato.cents, taux)
		x = oscillateur(c.get("type", "sine"), inc)
		if c.has("filter"):
			var f: Dictionary = c.filter
			filtrer(x, f.type, f.freq, f.get("to", 0.0), glisse, f.get("q", Q_DEFAUT), taux)
	if c.has("tremolo"):
		tremolo(x, c.tremolo.rate, c.tremolo.depth, taux)
	return x

## Ouvre un travail : deux pistes vides (directe, et à saturer) à la longueur du son.
static func commencer(couches: Array, taux: int, bruit: PackedFloat32Array, graine: int) -> Dictionary:
	var duree := 0.0
	for c in couches:
		duree = maxf(duree, c.get("at", 0.0) + duree_enveloppe(c.env))
	var n := int((duree + MARGE_FIN) * taux)
	var directe := PackedFloat32Array()
	directe.resize(n)
	directe.fill(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	return {"couches": couches, "i": 0, "taux": taux, "bruit": bruit, "rng": rng, "directe": directe, "saturee": PackedFloat32Array()}

## Rend UNE couche du travail. Vrai quand toutes les couches sont posées.
static func avancer(t: Dictionary) -> bool:
	if t.i >= t.couches.size():
		return true
	var c: Dictionary = t.couches[t.i]
	t.i += 1
	var taux: int = t.taux
	var segs := segments(c.env, c.get("gain", 1.0), taux)
	var n := 0
	for s in segs:
		n += int(s[0])
	var x := rendre_couche(c, n, taux, t.bruit, t.rng)
	var piste: PackedFloat32Array = t.directe
	if c.get("drive", false):
		if t.saturee.is_empty():
			var vide := PackedFloat32Array()
			vide.resize(piste.size())
			vide.fill(0.0)
			t.saturee = vide
		piste = t.saturee
	poser(piste, x, segs, int(c.get("at", 0.0) * taux))
	return t.i >= t.couches.size()

## Ferme le travail : les couches `drive` passent ensemble par la saturation, puis tout se mêle.
static func terminer(t: Dictionary) -> PackedFloat32Array:
	var sortie: PackedFloat32Array = t.directe
	if not t.saturee.is_empty():
		saturer(t.saturee)
		melanger(sortie, t.saturee)
	return sortie

## Rendu d'un trait.
static func rendre(couches: Array, taux: int, bruit: PackedFloat32Array, graine: int) -> PackedFloat32Array:
	var t := commencer(couches, taux, bruit, graine)
	while not avancer(t):
		pass
	return terminer(t)
