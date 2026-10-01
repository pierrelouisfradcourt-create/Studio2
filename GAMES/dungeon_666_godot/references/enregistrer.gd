extends SceneTree
## ENREGISTRE les parties de référence : joue le catalogue (references/catalogue.gd) avec les bots
## et la politique « hasard », et écrit pour chaque partie ses entrées et la signature de son état
## toutes les 30 images (references/parties/<nom>.ref, format : references/codec.gd).
##
##   <godot> --headless --path . --script res://references/enregistrer.gd [-- nom …] [--tranche i/n]
##   bash references/enregistrer.sh [nom …]          les mêmes, sur plusieurs processus
##
## CONSIGNE. Ces références ne disent pas « le jeu est juste » : elles disent « la simulation n'a
## pas changé SANS QU'ON LE VEUILLE ». Donc :
##   - references/verifier.gd rougit sans qu'une règle ait été changée exprès : c'est une
##     régression. On la corrige. On ne réenregistre PAS pour la faire taire.
##   - une règle (sim/) ou un nombre (data/) a été changé exprès : la garde rougit, c'est attendu.
##     On vérifie que le changement fait ce qu'on voulait (son test dans tests/regles/), on
##     réenregistre avec ce script, et on le DIT dans le message du commit (« références
##     réenregistrées : <la règle changée> »).
## Un réenregistrement sans changement redonne les mêmes fichiers, au bit près.
## Sortie 0 = tout écrit, 1 = au moins une erreur, 2 = arguments invalides.

const Partie = preload("res://references/partie.gd")
const Catalogue = preload("res://references/catalogue.gd")
const Codec = preload("res://references/codec.gd")

const MIN_CHECKS := 2 # un point au départ, un à la fin : en dessous, la partie n'a rien joué
const EXIT_USAGE := 2

## [detail] [nom …] [--tranche i/n] -> {names, slice, slices, detail}, avec `error` si invalide.
static func parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {"names": [], "slice": 0, "slices": 1, "detail": false}
	var i := 0
	while i < argv.size():
		if argv[i] == "--tranche" and i + 1 < argv.size():
			var parts := argv[i + 1].split("/")
			out.slice = int(parts[0])
			out.slices = int(parts[1]) if parts.size() > 1 else 0
			i += 1
		elif argv[i] == "detail" and out.names.is_empty():
			out.detail = true
		else:
			out.names.append(argv[i])
		i += 1
	if out.slices < 1 or out.slice < 0 or out.slice >= out.slices:
		out.error = "--tranche i/n attend 0 <= i < n"
	for n in out.names:
		if Catalogue.find(n) == null and not out.detail:
			out.error = "partie inconnue du catalogue : %s" % n
	return out

## Les specs demandées (toutes si aucun nom), réduites à la tranche.
static func selection(args: Dictionary) -> Array:
	var out: Array = []
	var all: Array = Catalogue.all()
	for i in all.size():
		if i % int(args.slices) == int(args.slice) and (args.names.is_empty() or args.names.has(all[i].name)):
			out.append(all[i])
	return out

func _initialize() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if args.has("error") or args.detail:
		print(args.get("error", "detail : voir references/verifier.gd"))
		quit(EXIT_USAGE)
		return
	var t0 := Time.get_ticks_msec()
	var bad := 0
	var frames := 0
	var bytes := 0
	var specs := selection(args)
	for spec in specs:
		var rec: Dictionary = Partie.record(spec)
		var checks: int = rec.steps.filter(func(s): return int(s[0]) == 2).size()
		var err: Error = Codec.write(rec) if checks >= MIN_CHECKS and rec.frames > 0 else ERR_INVALID_DATA
		if err != OK:
			bad += 1
			print("  ROUGE — %s : non écrite (%s ; %d images, %d points de contrôle)" % [spec.name, error_string(err), rec.frames, checks])
			continue
		var size := FileAccess.get_file_as_bytes(Codec.path_of(spec.name)).size()
		frames += rec.frames
		bytes += size
		print("  écrit — %s : %d images, %d points de contrôle, %d octets" % [spec.name, rec.frames, checks, size])
	if args.names.is_empty() and args.slice == 0:
		bad += _remove_orphans()
	print("%d parties enregistrées, %d images, %d octets, %d erreurs — %.1f s" % [specs.size() - bad, frames, bytes, bad, (Time.get_ticks_msec() - t0) / 1000.0])
	print("ENREGISTREMENT: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)

## Un enregistrement complet retire les fichiers des parties sorties du catalogue.
func _remove_orphans() -> int:
	var bad := 0
	var known: Array = Catalogue.names()
	for n in Codec.names_on_disk():
		if not known.has(n):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(Codec.path_of(n)))
			bad += 0 if err == OK else 1
			print("  retiré — %s : n'est plus au catalogue" % n)
	return bad
