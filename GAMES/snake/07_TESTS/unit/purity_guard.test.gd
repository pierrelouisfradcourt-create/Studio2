# purity_guard.test.gd — ligne arch.dependency_direction. Pour CHAQUE script de
# 05_SYSTEMS/ : il herite de RefCounted et ne reference AUCUNE API de moteur interdite ;
# aucun import de 05_SYSTEMS/ vers 06_RUNTIME/. Verification EXECUTEE dans le moteur,
# doublant la verification statique cote Python. Compte de violations = EXACTEMENT 0.
extends RefCounted

const API_INTERDITES := [
	"get_node(", "Input.", "InputEvent", "Viewport", "CanvasItem",
	"_draw(", "_process(", "_physics_process(", "Timer", "OS.", "Time.",
	"randi(", "randf(",
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

# Retire tout ce qui suit un '#' (commentaire) sur chaque ligne.
func _sans_commentaires(texte: String) -> String:
	var out := ""
	for ligne in texte.split("\n"):
		var i := ligne.find("#")
		if i >= 0:
			out += ligne.substr(0, i) + "\n"
		else:
			out += ligne + "\n"
	return out

func run(h) -> void:
	var fichiers: Array = []
	_lister_gd("res://05_SYSTEMS", fichiers)
	h.ok(fichiers.size() >= 10, "au moins 10 scripts purs trouves dans 05_SYSTEMS")

	var violations := 0
	for chemin in fichiers:
		var f := FileAccess.open(chemin, FileAccess.READ)
		if f == null:
			violations += 1
			h.ok(false, "lecture impossible : " + chemin)
			continue
		var brut := f.get_as_text()
		f.close()
		var code := _sans_commentaires(brut)

		# (1) Premiere directive `extends` = RefCounted.
		var extends_ok := false
		for ligne in code.split("\n"):
			var l := ligne.strip_edges()
			if l.begins_with("extends "):
				extends_ok = (l == "extends RefCounted")
				break
		if not extends_ok:
			violations += 1
		h.ok(extends_ok, "extends RefCounted : " + chemin)

		# (2) Aucune API de moteur interdite.
		for api in API_INTERDITES:
			if api in code:
				violations += 1
				h.ok(false, "%s reference l'API interdite %s" % [chemin, api])

		# (3) Aucun import de 05_SYSTEMS/ vers 06_RUNTIME/.
		if "06_RUNTIME" in code:
			violations += 1
			h.ok(false, chemin + " importe depuis 06_RUNTIME (dependance inversee)")

	h.eq(violations, 0, "0 violation de purete sur 05_SYSTEMS")
