shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float opacity : hint_range(0.0, 1.0) = 0.25;
uniform float blur_amount : hint_range(0.0, 10.0) = 5.5;
uniform float overlay_layers : hint_range(1.0, 5.0, 1.0) = 3.0;

void fragment() {
    float stacked_opacity = 1.0 - pow(1.0 - clamp(opacity, 0.0, 1.0), overlay_layers);

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
                blurred += texture(screen_texture, SCREEN_UV + vec2(x, y) * pixel_size * blur_amount) * weight;
                total_weight += weight;
            }
        }
        blurred /= total_weight;
        // 模糊背景上叠加多层黑色遮罩，避免单层混合后画面仍然偏亮
        COLOR = mix(blurred, vec4(0.0, 0.0, 0.0, 1.0), stacked_opacity);
        COLOR.a = 1.0;
    } else {
        // 纯色遮罩，同样使用多层叠加后的等效透明度
        COLOR = vec4(0.0, 0.0, 0.0, stacked_opacity);
    }
}
