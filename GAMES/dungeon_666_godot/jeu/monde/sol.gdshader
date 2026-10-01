shader_type canvas_item;
// Le sol d'une salle, peint en un seul rectangle : dalles (deux tons, grain, joints usés,
// biseau), craquelures sèches, fissures de lave qui pulsent, ombre au pied des murs, et la
// lanterne du héros (le sol s'éclaire autour de lui : on le trouve d'un coup d'œil).
// Quatre lectures de texture par pixel, aucune boucle : pensé pour un téléphone.
// Les réglages viennent de jeu/monde/ambiance.gd, posés par jeu/monde/sol.gd.

uniform sampler2D bruit : repeat_enable, filter_linear_mipmap;
uniform sampler2D craquelure : repeat_enable, filter_linear_mipmap;
uniform vec3 pierre_a = vec3(0.2, 0.14, 0.16);
uniform vec3 pierre_b = vec3(0.13, 0.09, 0.11);
uniform vec3 joint = vec3(0.05, 0.03, 0.04);
uniform vec3 teinte = vec3(1.0, 0.35, 0.12);
uniform vec2 dalle = vec2(88.0, 88.0);
uniform float decale = 0.0;
uniform float tourne = 0.0;
uniform float lave = 0.4;
uniform float seches = 0.5;
uniform float souffle = 1.0;
uniform vec2 salle = vec2(1400.0, 880.0);
uniform float marge = 24.0;
uniform vec2 graine = vec2(0.0);
uniform float temps = 0.0;
uniform vec2 heros = vec2(-9999.0);

const float LANTERNE = 190.0; // u : portée de la lueur du héros
const vec3 CLAIR = vec3(1.0, 0.86, 0.78);

varying vec2 lieu;

void vertex() {
	lieu = VERTEX;
}

float hasard(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

// Une dalle : ton, grain, biseau (lumière en haut à gauche), joint mangé par l'usure.
vec3 dallage(vec2 p, float grain, float tache) {
	float ca = cos(tourne);
	float sa = sin(tourne);
	vec2 q = vec2(ca * p.x + sa * p.y, ca * p.y - sa * p.x) / dalle;
	q.x += decale * floor(q.y);
	vec2 f = fract(q);
	float ton = hasard(floor(q) + floor(graine * 97.0));
	vec3 c = mix(pierre_b, pierre_a, clamp(ton * 0.75 + tache * 0.5 - 0.1, 0.0, 1.0));
	c *= 0.5 + 0.62 * grain;
	vec2 haut = f * dalle;
	vec2 bas = (1.0 - f) * dalle;
	float clair = (1.0 - smoothstep(1.5, 6.0, haut.x)) + (1.0 - smoothstep(1.5, 6.0, haut.y));
	float sombre = (1.0 - smoothstep(1.5, 8.0, bas.x)) + (1.0 - smoothstep(1.5, 8.0, bas.y));
	c += CLAIR * 0.045 * min(clair, 1.0);
	c *= 1.0 - 0.3 * min(sombre, 1.0);
	float bord = min(min(haut.x, haut.y), min(bas.x, bas.y));
	float plein = smoothstep(0.8, 2.6, bord + (grain - 0.5) * 3.5);
	return mix(joint, c, plein);
}

void fragment() {
	vec2 p = lieu;
	float grain = texture(bruit, p / 170.0 + graine).r;
	float tache = texture(bruit, p / 640.0 + graine.yx * 1.7).r;
	vec3 c = dallage(p, grain, tache);

	// Fissures : la lave court là où la grande tache est forte, les craquelures sèches ailleurs.
	float seuil = mix(0.8, 0.52, lave);
	float zone = smoothstep(seuil - 0.07, seuil + 0.07, tache + (grain - 0.5) * 0.12);
	float veine = texture(craquelure, p / 940.0 + graine).r;
	float coeur = 1.0 - smoothstep(0.004, 0.03, veine);
	float halo = 1.0 - smoothstep(0.0, 0.2, veine);
	float eteinte = texture(craquelure, p / 700.0 - graine.yx + vec2(0.37, 0.61)).r;
	float friche = mix(0.78, 0.5, seches);
	float trait = (1.0 - smoothstep(0.004, 0.026, eteinte)) * smoothstep(friche - 0.08, friche + 0.08, 1.0 - tache);
	c *= 1.0 - 0.6 * trait * (1.0 - zone);
	c *= 1.0 - 0.3 * halo * zone;

	// Ombre au pied des murs (plus profonde sous le mur du fond), salle plus claire au centre.
	vec2 pres = min(p - vec2(marge), salle - vec2(marge) - p);
	float ombre = mix(0.42, 1.0, smoothstep(0.0, 96.0, p.y - marge)) * mix(0.62, 1.0, smoothstep(0.0, 52.0, min(pres.x, salle.y - marge - p.y)));
	vec2 au_centre = (p - salle * 0.5) / (salle * 0.62);
	float clarte = 1.0 - 0.3 * smoothstep(0.25, 1.0, dot(au_centre, au_centre));
	c *= ombre * clarte * 0.88;
	c += teinte * 0.05 * tache * tache * ombre;

	// Lanterne du héros : le sol s'éclaire autour de lui, d'une lumière un peu froide.
	vec2 vers = p - heros;
	float lanterne = exp(-dot(vers, vers) / (LANTERNE * LANTERNE));
	c *= 1.0 + 0.75 * lanterne;
	c += vec3(0.1, 0.2, 0.26) * 0.09 * lanterne;

	// La lave, par-dessus : cœur clair, halo à la teinte du Cercle, pulsation lente et déphasée.
	float pouls = 0.7 + 0.3 * sin(temps * 1.7 * souffle + tache * 15.0 + grain * 3.0);
	vec3 braise = mix(teinte, vec3(1.0, 0.94, 0.82), coeur * 0.6);
	c += braise * (coeur * 0.9 + halo * halo * 0.34) * zone * pouls * mix(0.6, 1.0, ombre);

	COLOR = vec4(c, 1.0);
}
