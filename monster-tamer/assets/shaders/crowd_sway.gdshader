// CROWD SWAY + CHEER — the per-instance life of the MultiMesh crowd (scripts/ui/spectators.gd).
//
// The rigged crowd cost 4.6x the frame budget (docs/WATCH_AUDIT.md round 13 A/B: fill 1.0 ->
// 31fps / 2,986 draw calls / 30,111 nodes). The batched crowd renders one draw call per pack
// surface, and ALL motion lives here, driven by per-instance data — no per-spectator nodes,
// no AnimationPlayers, no timers.
//
// Per-instance channels (set by spectators.gd):
//   COLOR            = tint (MultiMesh use_colors) — replaces the per-instance material
//                      duplication the rigged path paid for
//   INSTANCE_CUSTOM  = (sway_phase 0..1, cheer_start_s, cheer_dur_s, cheer_amp_LOCAL)
//
// ⚠️ THE MESH IS IN ARMATURE-LOCAL UNITS: the Quaternius packs carry a x100 scale on
// HumanArmature (measured 2026-08-13), so the baked verts are ~0.04 units tall and local +Z is
// world UP. Every displacement below is in that tiny local space — cheer amplitude arrives
// already converted (world * 0.01) from GDScript. Do not "fix" the small constants.
//
// u_now is a shared clock uniform pushed by spectators.gd every frame rather than TIME, because
// GDScript must write cheer_start in the SAME clock it cannot read TIME from.
shader_type spatial;

uniform vec4 albedo_mul : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform float u_now = 0.0;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	// Idle sway: two incommensurate sines so the house never synchronises. Lean pivots at the
	// feet (scaled by height along local +Z).
	float lean = sin(u_now * 1.6 + phase) * 0.012 + sin(u_now * 0.7 + phase * 1.9) * 0.008;
	VERTEX.x += lean * VERTEX.z;
	// Cheer: a two-beat hop, decaying, over cheer_dur seconds from cheer_start. An unset
	// instance has dur 0 so the branch never takes.
	float t = u_now - INSTANCE_CUSTOM.y;
	if (t >= 0.0 && t < INSTANCE_CUSTOM.z) {
		float p = t / INSTANCE_CUSTOM.z;
		float hop = abs(sin(p * 6.2831853)) * (1.0 - 0.35 * p);
		VERTEX.z += hop * INSTANCE_CUSTOM.w;
		// a cheering body also throws its shoulders back a touch
		VERTEX.x += hop * INSTANCE_CUSTOM.w * 0.3 * sin(phase);
	}
}

void fragment() {
	// COLOR = instance tint (x vertex colour). Pack materials are flat albedo colours; the
	// texture is hint_default_white so untextured packs pass through unchanged.
	vec4 c = albedo_mul * COLOR * texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
