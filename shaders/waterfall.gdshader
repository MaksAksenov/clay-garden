// Waterfall (stage 15): the pond's glossy "jelly" clay running down an open side — the same colors and gloss as
// water.gdshader, opaque (no sorting, no dithering). Soft, slow highlights drift down in world height, so pieces of any
// length share one pattern and never stretch.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.36, 0.72, 0.87, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lane = sin((wpos.x + wpos.z) * 6.0) * 0.5 + 0.5;
	float flow = fract(wpos.y * 0.8 + TIME * 0.28 + lane * 0.45);
	float band = smoothstep(0.3, 0.5, flow) * (1.0 - smoothstep(0.5, 0.7, flow));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(water_color.rgb, foam_color.rgb, band * 0.18 + fres * 0.2);
	ROUGHNESS = 0.16;
	SPECULAR = 0.6;
	RIM = 0.3;
	RIM_TINT = 0.3;
}
