shader_type canvas_item;
// Relief d'un grand titre : la lumière vient du haut. Le texte garde sa couleur en tête de lettre
// et prend `teinte_bas` vers le pied (un dégradé vertical, en pixels du Label). Une seule lecture
// de texture, aucun coût notable. Le liseré et l'ombre, déjà sombres, n'en sont presque pas changés.

uniform float haut = 0.0;
uniform float bas = 80.0;
uniform vec4 teinte_bas : source_color = vec4(1.0, 0.74, 0.52, 1.0);

varying float hauteur;

void vertex() {
	hauteur = VERTEX.y;
}

void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	c.rgb *= mix(vec3(1.0), teinte_bas.rgb, smoothstep(haut, bas, hauteur));
	COLOR = c;
}
