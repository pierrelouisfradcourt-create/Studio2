# params_isolation.test.gd — ligne params.bloc_unique. params.gd declare bien les constantes
# nommees ; les valeurs de gameplay DISTINCTIVES n'apparaissent comme litteraux dans AUCUN
# script de 05_SYSTEMS/ ou 06_RUNTIME/ hors params.gd (commentaires et chaines retires).
#
# PORTEE HONNETE (rapport) : couvre les valeurs distinctives (600.0, 300.0, 480.0), non les
# petits entiers ambigus. La verification EXHAUSTIVE est l'oracle Python forge.static_oracles
# (s10s), qui possede un vrai analyseur.
extends RefCounted

const VALEURS_GAMEPLAY := ["600.0", "300.0", "480.0"]
const CONSTANTES_ATTENDUES := [
	"TERRAIN_LARGEUR", "TERRAIN_HAUTEUR", "RAQUETTE_LARGEUR", "RAQUETTE_VITESSE_MAX",
	"BALLE_VITESSE_INITIALE", "TICK_DT_FIXED_MS", "ANGLE_REBOND_MAX_DEG", "GRILLE_RANGEES",
	"GRILLE_COLONNES", "VIES_INITIALES", "SEED_REFERENCE", "POINTS_PAR_BRIQUE",
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

# Retire commentaires (#...) et contenu des chaines "..." (chemins de preload compris).
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
	var pf := FileAccess.open("res://05_SYSTEMS/params/params.gd", FileAccess.READ)
	h.ok(pf != null, "params.gd lisible")
	var ptxt := pf.get_as_text() if pf != null else ""
	if pf != null:
		pf.close()
	for c in CONSTANTES_ATTENDUES:
		h.ok(("const " + c) in ptxt, "params.gd declare la constante " + c)

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
