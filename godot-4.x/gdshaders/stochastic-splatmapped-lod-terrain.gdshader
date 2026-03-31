shader_type spatial;

uniform sampler2D source_texture_mask  : source_color;
uniform sampler2D source_texture_black : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_texture_red   : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_texture_green : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_texture_blue  : source_color, filter_linear_mipmap, repeat_enable;

uniform float uv_black = 1.0;
uniform float uv_red  = 1.0;
uniform float uv_green = 1.0;
uniform float uv_blue  = 1.0;

// LOD System - Camera Near/Far Distances
uniform float close_dist = 26.0;
uniform float far_dist   = 120.0;

// LOD System - Texture Resolution Multipliers
uniform float res_high = 32.0;
uniform float res_med  = 16.0;
uniform float res_low  = 8.0;

// Stochastic Hex Tiling
/*
	Controls how much random rotation is applied to each virtual hex tile. 
	0.0 = No rotation (Use this if your texture has parallel lines, like bricks).
	1.0 = Full random rotation (Best for organic textures to destroy tiling patterns).
*/
uniform float rot_strength : hint_range(0.0, 1.0) = 0.5;

/*
	Restores the contrast that naturally gets lost when blending 3 texture samples.
	0.50 = No contrast adjustment (will look blurry).
	0.75 = Recommended by the author. Restores crispness without revealing the grid.
	0.99 = Max contrast (Warning: May make the hexagonal grid borders visible).
*/
uniform float contrast_adjust : hint_range(0.01, 0.99) = 0.75;


// Stochastic hex tile funcs:
void TriangleGrid(out float w1, out float w2, out float w3,
	out ivec2 vertex1, out ivec2 vertex2, out ivec2 vertex3,
	vec2 st) {

	// Scaling of the input
	st *= 2.0 * sqrt(3.0);

	/* 
		Skew input space into simplex triangle grid.
		Note: GLSL mat2 is column-major, so this is transposed from HLSL.
	*/
	mat2 gridToSkewedGrid = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054));
	vec2 skewedCoord = gridToSkewedGrid * st;

	ivec2 baseId = ivec2(floor(skewedCoord));
	vec3 temp = vec3(fract(skewedCoord), 0.0);
	temp.z = 1.0 - temp.x - temp.y;

	float s = step(0.0, -temp.z);
	float s2 = 2.0 * s - 1.0;

	w1 = -temp.z * s2;
	w2 = s - temp.y * s2;
	w3 = s - temp.x * s2;

	vertex1 = baseId + ivec2(int(s), int(s));
	vertex2 = baseId + ivec2(int(s), int(1.0 - s));
	vertex3 = baseId + ivec2(int(1.0 - s), int(s));
}

vec2 hash(vec2 p) {
	mat2 m = mat2(vec2(127.1, 269.5), vec2(311.7, 183.3));
	vec2 r = m * p;
	return fract(sin(r) * 43758.5453);
}

vec2 MakeCenST(ivec2 Vertex) {
	mat2 invSkewMat = mat2(vec2(1.0, 0.0), vec2(0.5, 1.0 / 1.15470054));
	return (invSkewMat * vec2(Vertex)) / (2.0 * sqrt(3.0));
}

mat2 LoadRot2x2(ivec2 idx, float rotStrength) {
	float angle = abs(float(idx.x * idx.y)) + abs(float(idx.x + idx.y)) + PI;

	// Remap to +/-pi.
	angle = mod(angle, 2.0 * PI);
	if(angle < 0.0) angle += 2.0 * PI;
	if(angle > PI) angle -= 2.0 * PI;

	angle *= rotStrength;

	float cs = cos(angle);
	float si = sin(angle);

	return mat2(vec2(cs, si), vec2(-si, cs));
}

vec3 Gain3(vec3 x, float r) {
	// Increase contrast when r > 0.5 and reduce contrast if less.
	float k = log(1.0 - r) / log(0.5);
	vec3 s = 2.0 * step(vec3(0.5), x);
	vec3 m = 2.0 * (1.0 - s);

	vec3 res = 0.5 * s + 0.25 * m * pow(max(vec3(0.0), s + x * m), vec3(k));
	return res / (res.x + res.y + res.z);
}

vec4 hex2colTex(sampler2D tex, vec2 st, float rotStrength, float r) {
	// Calculate derivatives for mipmapping *before* manipulating UVs
	vec2 dSTdx = dFdx(st);
	vec2 dSTdy = dFdy(st);

	// Get triangle info.
	float w1, w2, w3;
	ivec2 vertex1, vertex2, vertex3;
	TriangleGrid(w1, w2, w3, vertex1, vertex2, vertex3, st);

	mat2 rot1 = LoadRot2x2(vertex1, rotStrength);
	mat2 rot2 = LoadRot2x2(vertex2, rotStrength);
	mat2 rot3 = LoadRot2x2(vertex3, rotStrength);

	vec2 cen1 = MakeCenST(vertex1);
	vec2 cen2 = MakeCenST(vertex2);
	vec2 cen3 = MakeCenST(vertex3);

	vec2 st1 = (rot1 * (st - cen1)) + cen1 + hash(vec2(vertex1));
	vec2 st2 = (rot2 * (st - cen2)) + cen2 + hash(vec2(vertex2));
	vec2 st3 = (rot3 * (st - cen3)) + cen3 + hash(vec2(vertex3));

	// Fetch input textures using explicit derivatives to prevent seam artifacts
	vec4 c1 = textureGrad(tex, st1, rot1 * dSTdx, rot1 * dSTdy);
	vec4 c2 = textureGrad(tex, st2, rot2 * dSTdx, rot2 * dSTdy);
	vec4 c3 = textureGrad(tex, st3, rot3 * dSTdx, rot3 * dSTdy);

	// Use luminance as weight.
	vec3 Lw = vec3(0.299, 0.587, 0.114);
	vec3 Dw = vec3(dot(c1.rgb, Lw), dot(c2.rgb, Lw), dot(c3.rgb, Lw));

	float g_fallOffContrast = 0.6; // Hardcoded from Mikkelsen's defaults
	float g_exp = 7.0;             // Hardcoded from Mikkelsen's defaults

	Dw = mix(vec3(1.0), Dw, g_fallOffContrast);
	vec3 W = Dw * pow(vec3(w1, w2, w3), vec3(g_exp));
	W /= (W.x + W.y + W.z);

	// Apply contrast curve
	if(r != 0.5) {
		W = Gain3(W, r);
	}

	// Blend the 3 samples together using calculated weights
	return W.x * c1 + W.y * c2 + W.z * c3;
}


void fragment() {

	// world camera via INV_VIEW_MATRIX (distance variables)
	vec3 world_camera = (INV_VIEW_MATRIX  * vec4(vec3(0.0), 1.0)).xyz;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// texture_rgbmask UV is not scaled.
	vec3 texture_rgbmask= texture(source_texture_mask, UV).rgb; 

	// camera distance UV calculation
	// TODO: add a nice blend between the near and far planes!
	float uv_scale_far = smoothstep(far_dist, far_dist, distance(world_pos, world_camera));
	float uv_scale_near = smoothstep(close_dist, close_dist, distance(world_pos, world_camera));
	float uv_mixed = mix(res_high, mix(res_med, res_low, uv_scale_far), uv_scale_near);

	vec2 uv = world_pos.xz * 1.0;

	vec3 texture_black 	= hex2colTex(source_texture_black, UV * uv_black * uv_mixed, rot_strength, contrast_adjust).rgb;
	vec3 texture_red 	= hex2colTex(source_texture_red, UV * uv_red * uv_mixed, rot_strength, contrast_adjust).rgb;
	vec3 texture_green 	= hex2colTex(source_texture_green, UV * uv_green * uv_mixed, rot_strength, contrast_adjust).rgb;
	vec3 texture_blue 	= hex2colTex(source_texture_blue, UV * uv_blue * uv_mixed, rot_strength, contrast_adjust).rgb;

	float summed_texture_channels = (
		texture_rgbmask.r + 
		texture_rgbmask.g + 
		texture_rgbmask.b);

	vec3 mixed_terrain = clamp(
			(	texture_rgbmask.r * texture_red +
				texture_rgbmask.g * texture_green +
				texture_rgbmask.b * texture_blue) /
				summed_texture_channels,
				vec3(0.0), vec3(1.0) // Clamp min, max values.
			);

	ALBEDO = mix(mixed_terrain,texture_black,1.0 - summed_texture_channels);

} // Fragment end