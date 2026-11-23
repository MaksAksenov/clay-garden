// Preview ghost: semi-transparent, gently pulsing.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.5);

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(color.rgb, vec3(1.0), fres * 0.5);
	ALPHA = color.a * (0.55 + 0.45 * fres) * (0.85 + 0.15 * sin(TIME * 5.0));
}
