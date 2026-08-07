shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_burley;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LOW-POLY CREATURE SHADER — makes a Meshy-generated model read as the arena's lamp lights it,
// not as the studio light Meshy baked into its own texture.
//
// THE PROBLEM (docs/ART_DIRECTION.md + docs/ART_BIBLE_LOWPOLY.md): the battlefield's whole
// identity is "a craftsman's yard after the day's work, lit by one warm working lamp," with the
// lamp's colour carrying each league's per-league identity. A generated model arrives with its
// OWN lighting already painted into the albedo (docs/LOWPOLY_MODEL_SPEC.md's texture prompt asked
// for "no baked shadows or highlights" and still got some — Meshy's refine pass always adds some
// occlusion/shading into the bake). Left alone, that baked shading (a) visually fights whatever
// the arena's real light does to the same surface, and (b) looks IDENTICAL under a Wood lamp and
// a Platinum one, flattening a ladder dimension ART_DIRECTION.md deliberately built.
//
// THIS SHADER, in three parts:
//   1. FACETED NORMALS — computed per-pixel from screen-space derivatives of view-space position,
//      not read from the mesh's authored normals. Meshy's refine step smooths normals across the
//      low-poly mesh, and a smooth-shaded 1,200-tri model reads as a *cheap* model rather than a
//      *stylised* one (docs/ART_BIBLE_LOWPOLY.md: "hard edges kept hard"). This guarantees hard
//      facets regardless of what the .glb shipped with.
//   2. FLATTEN + DESATURATE THE BAKE — crushes the baked albedo's own luminance variance toward a
//      flat per-pixel tone (keeping hue/material colour) and pulls saturation down, so there is
//      headroom left for the arena's real light to be the thing that actually shades the model.
//   3. TOON-RAMP DIRECT LIGHT, TINTED BY THE LAMP'S OWN COLOUR — direct light is quantised into a
//      small number of hard bands (matching the low-poly aesthetic — planes catching light, not a
//      smooth painterly gradient) and the band brightness is tinted toward the light's own colour,
//      so a Wood lamp and a Platinum lamp visibly differ on the SAME creature. `lamp_tint_strength`
//      is the knob: 0 = bands use light intensity only (neutral), 1 = full lamp hue tint.
//
// STATUS HOOK (docs/ART_BIBLE_GUILD_COLOURS.md / ART_BIBLE_LOWPOLY.md §3): status colour must be
// able to be "the brightest thing in frame" without the lamp fighting it. `status_tint` /
// `status_strength` drive an EMISSIVE overlay — emission is additive over the lit, banded body and
// is never dimmed by the toon ramp's shadow band or muted by a cold-lamp league, which is exactly
// the guarantee the status channel needs. `status_desaturate_body` optionally mutes the creature's
// own hue further while a status is active so the tint isn't competing with the material colour.
//
// ⚠️ NOT a PBR metalness workflow and no normal maps — `ART_BIBLE_LOWPOLY.md` is explicit that
// low-poly surfaces are flat/faceted with a single flat colour (or small palette texture) per
// material. METALLIC is hard-pinned to 0 and there is no normal-map uniform on purpose.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

group_uniforms surface;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
group_uniforms;

group_uniforms bake_flattening;
// How hard we crush the model's OWN baked shading toward a flat per-pixel tone before the arena's
// real light is added. 0.0 = trust Meshy's bake as-is (it will fight the lamp). 1.0 = fully flat
// albedo going into lighting (the lamp does 100% of the visible shading).
uniform float bake_flatten : hint_range(0.0, 1.0) = 0.55;
// Desaturates the baked albedo so the lamp's own hue reads through cleanly instead of competing
// with whatever colour variance Meshy's refine pass painted in.
uniform float desaturate : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

group_uniforms faceting;
// Compute per-pixel flat normals from screen-space derivatives of view-space position instead of
// trusting the mesh's authored (Meshy-smoothed) normals. Leave true except when A/B-testing
// against the raw mesh normals.
uniform bool use_flat_normals = true;
group_uniforms;

group_uniforms toon_ramp;
// Number of hard bands the direct-light response is quantised into. 3 gives a classic
// shadow/mid/lit low-poly read; push toward 2 for a starker silhouette-first look.
uniform float ramp_steps : hint_range(2.0, 6.0) = 3.0;
// Blends the hard toon bands back toward a smooth Lambert falloff. 0.0 = crisp stepped bands
// (the low-poly read); higher values soften the step edges. Kept low by default on purpose.
uniform float ramp_softness : hint_range(0.0, 1.0) = 0.0;
// How much of the light's own COLOUR (vs. its intensity alone) tints the lit bands. This is the
// per-league identity knob: at 1.0 the same creature visibly differs between a warm Wood lamp and
// a cool Tin one; at 0.0 the bands are neutral brightness only.
uniform float lamp_tint_strength : hint_range(0.0, 1.0) = 0.65;
// Floor on the darkest band so shadow-side geometry doesn't drop to pure black against the arena's
// deep-shadow backdrop — matches "deep shadow, cool sky bounce" rather than crushing to nothing.
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.22;
group_uniforms;

group_uniforms status_fx;
// Status-effect tint. Additive EMISSION, so it is never dimmed by the toon ramp's shadow band or
// muted under a cold-lamp league — the one guarantee the status channel needs: always the
// brightest thing in frame. Drive `status_strength` (and optionally pulse it) from GDScript per
// the unit's live status list; leave at 0 for a healthy, un-afflicted creature.
uniform vec4 status_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float status_strength : hint_range(0.0, 1.0) = 0.0;
uniform float status_emission_energy : hint_range(0.0, 6.0) = 2.2;
// Mutes the creature's own material colour further while a status is active, so the tint reads
// clearly instead of competing with the body's natural hue.
uniform float status_desaturate_body : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

varying vec3 v_view_pos;

void vertex() {
	// View-space position, used only to derive a per-pixel flat normal in fragment() — screen-space
	// derivatives of a smoothly-interpolated view-space position give a constant normal across each
	// triangle, i.e. true flat shading, independent of whatever normals the mesh shipped with.
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 desaturate_colour(vec3 c, float amount) {
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(luma), amount);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = tex.rgb * albedo_tint.rgb;

	// Flatten the model's OWN baked shading: pull each pixel's luminance toward a fixed mid value
	// while keeping its hue, so the highlights/occlusion Meshy painted in stop reading as "this
	// surface is already lit" and leave room for the toon ramp below to do the actual shading.
	float base_luma = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 hue = base_luma > 0.0001 ? base / max(base_luma, 0.0001) : base;
	vec3 flattened = hue * clamp(base_luma, 0.35, 0.85);
	base = mix(base, flattened, bake_flatten);
	base = desaturate_colour(base, desaturate);

	vec3 n = NORMAL;
	if (use_flat_normals) {
		vec3 dx = dFdx(v_view_pos);
		vec3 dy = dFdy(v_view_pos);
		vec3 flat_n = normalize(cross(dx, dy));
		// The cross-product's winding can hand back either face direction depending on triangle
		// winding order; keep it pointed toward the viewer so a facet never lights inside-out.
		if (dot(flat_n, VIEW) < 0.0) {
			flat_n = -flat_n;
		}
		n = flat_n;
	}
	NORMAL = n;

	ALBEDO = base;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	if (status_strength > 0.0) {
		ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.299, 0.587, 0.114))), status_desaturate_body * status_strength);
		EMISSION = status_tint.rgb * status_strength * status_emission_energy;
	}
}

void light() {
	// Quantise the diffuse response into hard bands (the low-poly "planes catching light" read)
	// rather than a smooth Lambert falloff.
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float steps = max(ramp_steps, 1.0);
	float denom = max(steps - 1.0, 1.0);
	float hard_band = clamp(floor(ndotl * steps) / denom, 0.0, 1.0);
	float banded = mix(hard_band, ndotl, ramp_softness);
	banded = mix(shadow_floor, 1.0, banded);

	// Tint the band brightness toward the LIGHT's own colour (not just its intensity), so the same
	// creature visibly differs between leagues purely from the lamp uniform in the scene — no
	// per-creature, per-league authoring needed.
	float light_intensity = dot(LIGHT_COLOR, vec3(0.3333));
	vec3 lamp_colour = mix(vec3(light_intensity), LIGHT_COLOR, lamp_tint_strength);

	DIFFUSE_LIGHT += ALBEDO * banded * lamp_colour * ATTENUATION;
}
