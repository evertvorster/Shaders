// baseline.gdshader — a do-nothing sky-sphere shader: measures the HOST's per-frame cost on a
// given GPU, so a layer's own cost is (measured - this). Not part of the layer set.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never, depth_test_disabled;
void fragment() { ALBEDO = vec3(0.0, 0.0, 0.01); }
