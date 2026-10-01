class_name StudioStyle
extends RefCounted

## Le STYLE d'un jeu en chiffres (kit 0.9.0, 2026-09-28). Pierre : « comme si c'était le même
## dessinateur sur tout un jeu ». Un dessinateur se reconnaît à son TRAIT (épaisseur, noir ou teinté),
## à son OMBRAGE (aplats ou dégradés) et à sa PALETTE : on les mesure sur chaque dessin, et la
## référence de style du jeu (style.json : registres, bandes de mesure, familles de noms) dit ce qui
## sort de la bande de son registre. Un écart est un SIGNAL à regarder, jamais un verdict, et rien
## ici ne modifie un dessin.
##
## Mesures (dessin ramené à 256 px de haut, pour comparer un chaton de 72 px et une maison de 240 px) :
##   trait_lum  luminance moyenne du contour (0 noir .. 1 blanc)
##   trait_sat  saturation du contour (0 = gris/noir, haut = trait teinté de la couleur de l'objet)
##   trait_ep   épaisseur du trait sombre, en % de la hauteur du dessin (médiane sur les bords)
##   degrade    part des pixels intérieurs dans une pente douce (0 = aplats, haut = dégradés)
##   sat        saturation moyenne de l'intérieur
## Portage fidèle de l'outil Python de Kitten Factory (_dev/atelier/mesure_style.py, PIL + scipy) :
## érosion en croix = distance « de Manhattan » au vide, flou gaussien sigma 1 (rayon 4, bords en
## miroir), gradient en différences centrées.

const HAUT := 256
const CLES := ["trait_lum", "trait_sat", "trait_ep", "degrade", "sat"]
const PLEIN_ALPHA := 200         # un pixel est « dessiné » au-delà (0..255)
const BORD := 3                  # le contour = les 3 px au bord du dessin
const INTERIEUR := 6             # l'intérieur = à plus de 6 px du bord
const SOMBRE := 0.35             # luminance du trait sombre
const PENTE := [0.004, 0.03]     # une pente « douce » (dégradé), ni aplat ni arête
const EP_MAX := 40


## Les mesures d'un dessin ; {} s'il est trop petit ou presque vide.
static func mesurer(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_height() < 8:
		return {}
	var im := source.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var w := maxi(8, roundi(im.get_width() * float(HAUT) / im.get_height()))
	im.resize(w, HAUT, Image.INTERPOLATE_LANCZOS)
	var d := im.get_data()
	var n := w * HAUT
	var plein := PackedByteArray()
	plein.resize(n)
	var lum := PackedFloat32Array()
	lum.resize(n)
	var sat := PackedFloat32Array()
	sat.resize(n)
	var nb := 0
	for i in n:
		var r := d[i * 4] / 255.0
		var g := d[i * 4 + 1] / 255.0
		var b := d[i * 4 + 2] / 255.0
		var mx := maxf(r, maxf(g, b))
		var mn := minf(r, minf(g, b))
		sat[i] = (mx - mn) / mx if mx > 0.0 else 0.0
		lum[i] = 0.3 * r + 0.59 * g + 0.11 * b
		if d[i * 4 + 3] > PLEIN_ALPHA:
			plein[i] = 1
			nb += 1
	if nb < 50:
		return {}
	var dist := distance_au_vide(plein, w, HAUT)
	var m := {}
	var s_lum := 0.0
	var s_sat := 0.0
	var n_bord := 0
	var s_int := 0.0
	var n_int := 0
	for i in n:
		if plein[i] == 0:
			continue
		if dist[i] <= BORD:
			s_lum += lum[i]
			s_sat += sat[i]
			n_bord += 1
		elif dist[i] > INTERIEUR:
			s_int += sat[i]
			n_int += 1
	m["trait_lum"] = snappedf(s_lum / maxf(1.0, n_bord), 0.001)
	m["trait_sat"] = snappedf(s_sat / maxf(1.0, n_bord), 0.001)
	m["trait_ep"] = snappedf(100.0 * _epaisseur(plein, lum, w) / HAUT, 0.01)
	m["degrade"] = snappedf(_degrade(lum, dist, w, HAUT) / maxf(1.0, n_int), 0.001)
	m["sat"] = snappedf(s_int / n_int, 0.001) if n_int > 0 else 0.0
	return m


## Distance de Manhattan de chaque pixel dessiné au premier pixel vide (hors de l'image = vide) :
## éroder k fois en croix garde exactement les pixels à distance > k.
static func distance_au_vide(plein: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	var inf := w + h
	for y in h:
		for x in w:
			var i := y * w + x
			if plein[i] == 0:
				dist[i] = 0
				continue
			var gauche := dist[i - 1] if x > 0 else 0
			var haut := dist[i - w] if y > 0 else 0
			dist[i] = mini(inf, mini(gauche, haut) + 1)
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if dist[i] == 0:
				continue
			var droite := dist[i + 1] if x < w - 1 else 0
			var bas := dist[i + w] if y < h - 1 else 0
			dist[i] = mini(dist[i], mini(droite, bas) + 1)
	return dist


## Épaisseur du trait sombre : une ligne sur 4, depuis chaque bord du dessin, les pixels sombres
## qui se suivent ; la médiane.
static func _epaisseur(plein: PackedByteArray, lum: PackedFloat32Array, w: int) -> float:
	var ep: Array[int] = []
	for y in range(0, HAUT, 4):
		var premier := -1
		var dernier := -1
		var compte := 0
		for x in w:
			if plein[y * w + x] == 1:
				compte += 1
				dernier = x
				if premier < 0:
					premier = x
		if compte < 10:
			continue
		for depart in [[premier, 1], [dernier, -1]]:
			var k := 0
			var x: int = depart[0]
			while x >= 0 and x < w and plein[y * w + x] == 1 and lum[y * w + x] < SOMBRE and k < EP_MAX:
				k += 1
				x += int(depart[1])
			ep.append(k)
	if ep.is_empty():
		return 0.0
	ep.sort()
	var mi := ep.size() / 2
	return float(ep[mi]) if ep.size() % 2 == 1 else (ep[mi - 1] + ep[mi]) * 0.5


## Nombre de pixels intérieurs dans une pente douce (flou gaussien sigma 1, puis gradient).
static func _degrade(lum: PackedFloat32Array, dist: PackedInt32Array, w: int, h: int) -> float:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for i in dist.size():
		if dist[i] > INTERIEUR:
			x0 = mini(x0, i % w)
			x1 = maxi(x1, i % w)
			y0 = mini(y0, i / w)
			y1 = maxi(y1, i / w)
	if x1 < 0:
		return 0.0
	var noyau := _noyau()
	# flou horizontal sur les lignes utiles, puis vertical autour de l'intérieur seulement
	var ya := maxi(0, y0 - 5)
	var yb := mini(h - 1, y1 + 5)
	var hz := PackedFloat32Array()
	hz.resize(w * h)
	for y in range(ya, yb + 1):
		for x in range(maxi(0, x0 - 2), mini(w - 1, x1 + 2) + 1):
			var s := 0.0
			for k in range(-4, 5):
				s += noyau[k + 4] * lum[y * w + _miroir(x + k, w)]
			hz[y * w + x] = s
	var flou := PackedFloat32Array()
	flou.resize(w * h)
	for y in range(maxi(0, y0 - 1), mini(h - 1, y1 + 1) + 1):
		for x in range(maxi(0, x0 - 1), mini(w - 1, x1 + 1) + 1):
			var s := 0.0
			for k in range(-4, 5):
				s += noyau[k + 4] * hz[_miroir(y + k, h) * w + x]
			flou[y * w + x] = s
	var doux := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * w + x
			if dist[i] <= INTERIEUR:
				continue
			var gx := (flou[i + 1] - flou[i - 1]) * 0.5
			var gy := (flou[i + w] - flou[i - w]) * 0.5
			var g := sqrt(gx * gx + gy * gy)
			if g > PENTE[0] and g < PENTE[1]:
				doux += 1
	return float(doux)


static func _noyau() -> PackedFloat32Array:
	var k := PackedFloat32Array()
	var s := 0.0
	for x in range(-4, 5):
		k.append(exp(-0.5 * x * x))
		s += k[k.size() - 1]
	for i in k.size():
		k[i] /= s
	return k


## Bords en miroir (scipy « reflect ») : -1 -> 0, -2 -> 1, n -> n-1.
static func _miroir(i: int, n: int) -> int:
	if i < 0:
		return -i - 1
	if i >= n:
		return 2 * n - i - 1
	return i


## La famille d'un nom (préfixes de style.json), ou "".
static func famille(nom: String, reference: Dictionary) -> String:
	var familles: Dictionary = reference.get("familles", {})
	for f in familles:
		for p in familles[f].get("prefixes", []):
			if nom.begins_with(String(p)):
				return String(f)
	return ""


## Ce qui sort de la bande du registre de la famille (style.json « registres.<r>.mesure ») ; une famille
## « sans_mesure » (lueurs, étincelles : ni trait ni dessin) n'est pas jugée ainsi.
static func hors_style(nom: String, m: Dictionary, png: bool, reference: Dictionary) -> Array[String]:
	var ecarts: Array[String] = []
	var f := famille(nom, reference)
	if f == "":
		ecarts.append("sans famille dans la référence de style")
		return ecarts
	var fam: Dictionary = reference["familles"][f]
	if bool(fam.get("sans_mesure", false)):
		return ecarts
	if not png:
		ecarts.append("ancien dessin plat (SVG)")
	var registre: Dictionary = reference.get("registres", {}).get(String(fam.get("registre", "")), {})
	var bandes: Dictionary = registre.get("mesure", {})
	for cle in bandes:
		if not m.has(cle):
			continue
		var bande: Array = bandes[cle]
		if float(m[cle]) < float(bande[0]) or float(m[cle]) > float(bande[1]):
			ecarts.append("%s %s hors [%s, %s]" % [cle, m[cle], bande[0], bande[1]])
	return ecarts
