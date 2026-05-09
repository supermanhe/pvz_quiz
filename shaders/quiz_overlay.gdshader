shader_type canvas_item;

uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float blur_amount : hint_range(0.0, 10.0) = 0.0;

void fragment() {
    if (blur_amount > 0.1) {
        // 高斯模糊采样
        vec2 pixel_size = SCREEN_PIXEL_SIZE;
        vec4 blurred = vec4(0.0);
        float total_weight = 0.0;
        float sigma = blur_amount;
        float two_sigma_sq = 2.0 * sigma * sigma;

        for (float x = -3.0; x <= 3.0; x += 1.0) {
            for (float y = -3.0; y <= 3.0; y += 1.0) {
                float weight = exp(-(x * x + y * y) / two_sigma_sq);
                blurred += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(x, y) * pixel_size * blur_amount) * weight;
                total_weight += weight;
            }
        }
        blurred /= total_weight;
        // 模糊背景上叠加黑色遮罩，opacity 控制黑色占比
        COLOR = mix(blurred, vec4(0.0, 0.0, 0.0, 1.0), opacity);
        COLOR.a = 1.0;
    } else {
        // 纯色遮罩
        COLOR = vec4(0.0, 0.0, 0.0, opacity);
    }
}
