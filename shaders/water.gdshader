// Water: glossy "jelly" clay that sways softly.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.36, 0.72, 0.87, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);

varying vec3 wpos;

// Integer lattice hash: each axis is folded in through the lowbias32 finalizer
// (Chris Wellons, hash-prospector, public domain). p is always a lattice point (floor + 0/1).
uint mix32(uint h) {
	h ^= h >> 16u;
	h *= 0x7feb352du;
	h ^= h >> 15u;
	h *= 0x846ca68bu;
	h ^= h >> 16u;
	return h;
}

float hash13(vec3 p) {
	uvec3 q = uvec3(ivec3(round(p)));
	return float(mix32(q.x + mix32(q.y + mix32(q.z + 0x9e3779b9u)))) * (1.0 / 4294967295.0);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (VERTEX.y > 0.04) {
		VERTEX.y += sin(TIME * 1.7 + w.x * 2.1 + w.z * 1.3) * 0.014;
	}
	wpos = w;
}

void fragment() {
	vec2 q = wpos.xz;
	float h = vnoise(vec3(q * 3.0, TIME * 0.35)) * 0.6 + vnoise(vec3(q * 6.5 + 4.0, TIME * 0.6)) * 0.4;
	float hh = h * 0.02;
	// bump mapping (as in clay.gdshader): the surface-gradient formula from M. S. Mikkelsen,
	// "Bump Mapping Unparametrized Surfaces on the GPU" (2010) — screen-space derivatives of the position and the height
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(hh);
	float dhdy = dFdy(hh);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float foam = smoothstep(0.66, 0.82, h);
	ALBEDO = mix(water_color.rgb, foam_color.rgb, foam * 0.35 + fres * 0.2);
	ROUGHNESS = 0.16;
	SPECULAR = 0.6;
	RIM = 0.3;
	RIM_TINT = 0.3;
}
