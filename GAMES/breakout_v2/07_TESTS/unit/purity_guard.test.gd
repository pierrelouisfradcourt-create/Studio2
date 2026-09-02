# purity_guard.test.gd — ligne proof.purity_guard. Garde STATIQUE : la logique pure
# (05_SYSTEMS) n'herite d'aucun Node, n'appelle AUCUNE API de moteur, et n'importe ni scene
# ni script de presentation/runtime (sens unique du graphe). Scan deterministe du source.
#
# PORTEE HONNETE (rapport) : ce scan couvre les motifs distinctifs listes ci-dessous sur les
# fichiers de 05_SYSTEMS. L'analyse EXHAUSTIVE (tous appels d'API moteur) reste l'oracle
# d'architecture Python du standard (forge.static_oracles). Ici : garde headless, non-LLM.
extends RefCounted

# Motifs d'API moteur / de rendu INTERDITS dans la logique pure (recherche sur code nettoye).
const INTERDITS := [
	"get_node(", "move_and_collide", "_process(", "_physics_process(", "_draw(",
	"InputEvent", "Viewport", "CanvasItem", "OS.", "Time.", "randi(", "randf(",
	"randomize(", "queue_redraw",
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
	var fichiers: Array = []
	_lister_gd("res://05_SYSTEMS", fichiers)
	h.ok(fichiers.size() >= 15, "au moins 15 fichiers de logique pure scannes")

	var viol_api := 0
	var sans_refcounted := 0
	var import_presentation := 0
	for chemin in fichiers:
		var f := FileAccess.open(chemin, FileAccess.READ)
		if f == null:
			h.ok(false, "illisible: " + chemin)
			continue
		var brut := f.get_as_text()
		f.close()
		var code := _nettoyer(brut)

		# (a) API moteur interdite dans le code (hors commentaires/chaines).
		for motif in INTERDITS:
			if motif in code:
				viol_api += 1
				h.ok(false, "%s contient l'API moteur interdite '%s'" % [chemin, motif])

		# (b) herite de RefCounted, jamais d'un Node (verifie sur le brut : ligne extends).
		if not ("extends RefCounted" in brut):
			sans_refcounted += 1
			h.ok(false, "%s n'herite pas de RefCounted" % chemin)
		if "extends Node" in code:
			sans_refcounted += 1
			h.ok(false, "%s herite d'un Node (interdit en logique pure)" % chemin)

		# (c) sens unique : la logique pure n'importe ni runtime/presentation ni scene.
		if ("06_RUNTIME" in brut) or (".tscn" in brut):
			import_presentation += 1
			h.ok(false, "%s importe une scene ou un adaptateur (sens du graphe viole)" % chemin)

	h.eq(viol_api, 0, "0 appel d'API moteur dans la logique pure")
	h.eq(sans_refcounted, 0, "toute la logique pure herite de RefCounted (aucun Node)")
	h.eq(import_presentation, 0, "0 import de presentation/scene depuis la logique pure")
