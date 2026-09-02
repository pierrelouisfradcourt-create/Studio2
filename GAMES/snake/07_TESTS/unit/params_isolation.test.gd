# params_isolation.test.gd — ligne params.bloc_unique. Les valeurs de gameplay
# DISTINCTIVES (periode initiale 200, pas 0.92, plancher 80, cible 25) n'apparaissent
# comme litteraux dans AUCUN script de 05_SYSTEMS/ ou 06_RUNTIME/ hors params.gd, une
# fois commentaires et chaines retires. params.gd declare bien les 8 constantes nommees.
#
# PORTEE HONNETE (remontee au rapport) : ce test couvre les valeurs distinctives, non
# les petits entiers ambigus (3, 5, 20) qui apparaissent legitimement comme indices ou
# bornes. La verification EXHAUSTIVE des litteraux de gameplay est celle de l'oracle
# Python forge.static_oracles (etape s10s), qui possede un vrai analyseur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const VALEURS_GAMEPLAY := ["200", "0.92", "80", "25"]
const CONSTANTES_ATTENDUES := [
	"TAILLE_GRILLE", "VITESSE_INITIALE_MS", "ACCELERATION_PALIER", "ACCELERATION_PAS",
	"PERIODE_PLANCHER_MS", "LONGUEUR_INITIALE", "CIBLE_VICTOIRE", "POINTS_PAR_NOURRITURE",
]

func _lister_gd(racine: String, sortie: Array) -> void:
	var da := DirAccess.open(racine)
	if da == null:
		return
	da.list_dir_begin()
	var nom := da.get_next()
	while nom != "":
		if nom == "." or nom == "..":
			nom = da.get_next()
			continue
		var chemin := racine + "/" + nom
		if da.current_is_dir():
			_lister_gd(chemin, sortie)
		elif nom.ends_with(".gd"):
			sortie.append(chemin)
		nom = da.get_next()
	da.list_dir_end()

# Retire commentaires (#...) et contenu des chaines "..." (pour ne pas matcher les
# chemins de preload). Approche simple ligne a ligne.
func _nettoyer(texte: String) -> String:
	var out := ""
	for ligne in texte.split("\n"):
		var i := ligne.find("#")
		var l := ligne if i < 0 else ligne.substr(0, i)
		var propre := ""
		var dans_chaine := false
		for c in l:
			if c == "\"":
				dans_chaine = not dans_chaine
				continue
			if not dans_chaine:
				propre += c
		out += propre + "\n"
	return out

func run(h) -> void:
	# params.gd declare les 8 constantes nommees.
	var pf := FileAccess.open("res://05_SYSTEMS/params/params.gd", FileAccess.READ)
	h.ok(pf != null, "params.gd lisible")
	var ptxt := pf.get_as_text() if pf != null else ""
	if pf != null:
		pf.close()
	for c in CONSTANTES_ATTENDUES:
		h.ok(("const " + c) in ptxt, "params.gd declare la constante " + c)

	# Scan des autres scripts.
	var fichiers: Array = []
	_lister_gd("res://05_SYSTEMS", fichiers)
	_lister_gd("res://06_RUNTIME", fichiers)
	var fuites := 0
	for chemin in fichiers:
		if chemin.ends_with("05_SYSTEMS/params/params.gd"):
			continue
		var f := FileAccess.open(chemin, FileAccess.READ)
		if f == null:
			continue
		var code := _nettoyer(f.get_as_text())
		f.close()
		for v in VALEURS_GAMEPLAY:
			if v in code:
				fuites += 1
				h.ok(false, "%s contient le litteral de gameplay %s hors params.gd" % [chemin, v])
	h.eq(fuites, 0, "0 valeur de gameplay distinctive hors de params.gd")
