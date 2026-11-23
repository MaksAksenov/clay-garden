// Clay: soft diffuse, a light sheen, lumps and finger dents
// (bump mapping from screen-space derivatives — no textures).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float bump_strength = 2.3;
uniform float tint_amount = 0.08;
uniform float world_offset = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying vec3 obj_pos;

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
	obj_pos = VERTEX + NODE_POSITION_WORLD * 1.731 * world_offset;
}

void fragment() {
	vec3 p = obj_pos;
	float h = vnoise(p * 6.0) * 0.65 + vnoise(p * 13.0 + 7.1) * 0.35;
	// rare soft dents, as if from a finger
	float dents = smoothstep(0.6, 0.9, vnoise(p * 2.6 + 3.3));
	h -= dents * 0.9;
	float hh = h * 0.006 * bump_strength;

	// bump mapping: the surface-gradient formula from M. S. Mikkelsen,
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

	float tint = (vnoise(p * 1.4 + 11.0) - 0.5) * 2.0 * tint_amount;
	ALBEDO = albedo.rgb * (1.0 + tint) * (1.0 - dents * 0.07);
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	RIM = 0.22;
	RIM_TINT = 0.6;
	EMISSION = emission_color.rgb * emission_energy;
}
