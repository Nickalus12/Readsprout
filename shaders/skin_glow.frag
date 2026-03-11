#include <flutter/runtime_effect.glsl>

// Uniforms set from Dart via FragmentShader.setFloat()
uniform vec2 uSize;    // width, height of the paint area
uniform float uTime;   // elapsed seconds (subtle breathing pulse)

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;

    // ── Subsurface Scattering (SSS) Approximation ──
    //
    // Real skin transmits light beneath the surface. Red wavelengths
    // travel furthest through tissue, giving skin a warm undertone
    // especially at thinner areas (nose, ears, cheeks). We simulate
    // this with a warm radial glow centered on the face.

    vec2 faceCenter = vec2(0.5, 0.42);
    float dist = distance(uv, faceCenter);

    // Smooth falloff — strongest scatter at face center where light enters
    float scatter = smoothstep(0.48, 0.05, dist);

    // Red channel dominant (skin SSS physics), minimal blue penetration
    vec3 scatterColor = vec3(0.07, 0.025, 0.008) * scatter;

    // ── Forehead warmth ──
    // Forehead catches direct light from above — slight warm zone
    float foreheadWarm = smoothstep(0.45, 0.15, uv.y) * smoothstep(0.0, 0.15, uv.y);
    foreheadWarm *= smoothstep(0.45, 0.25, abs(uv.x - 0.5));
    scatterColor += vec3(0.03, 0.015, 0.003) * foreheadWarm;

    // ── Cheek warmth ──
    // Cheeks have thinner skin with more blood flow — subtle rosy warmth
    float leftCheek = smoothstep(0.15, 0.0, distance(uv, vec2(0.28, 0.52)));
    float rightCheek = smoothstep(0.15, 0.0, distance(uv, vec2(0.72, 0.52)));
    scatterColor += vec3(0.025, 0.008, 0.003) * (leftCheek + rightCheek);

    // ── Breathing pulse ──
    // Very subtle — feels alive without being consciously noticeable
    float breathe = sin(uTime * 1.2) * 0.5 + 0.5;
    scatterColor *= 0.88 + breathe * 0.12;

    // ── Rim lighting ──
    // Simulates backlight wrapping around the face edges.
    // Color shifts cool (blue-purple) per color theory.
    float rimDist = distance(uv, vec2(0.5, 0.45));
    float rim = smoothstep(0.30, 0.42, rimDist) * smoothstep(0.50, 0.40, rimDist);
    vec3 rimColor = vec3(0.03, 0.025, 0.06) * rim;

    // ── Chin ambient occlusion ──
    // Subtle shadow under the chin where light doesn't reach
    float chinAO = smoothstep(0.58, 0.72, uv.y) * smoothstep(0.38, 0.22, abs(uv.x - 0.5));
    vec3 aoColor = vec3(-0.015, -0.015, -0.008) * chinAO;

    // ── Nose bridge shadow ──
    // Very subtle ambient occlusion along the nose bridge
    float noseShadow = smoothstep(0.06, 0.0, abs(uv.x - 0.5))
                     * smoothstep(0.36, 0.44, uv.y)
                     * smoothstep(0.54, 0.47, uv.y);
    vec3 noseAO = vec3(-0.008, -0.008, -0.004) * noseShadow;

    // ── Composite ──
    vec3 finalColor = scatterColor + rimColor + aoColor + noseAO;
    float alpha = max(scatter * 0.12, rim * 0.06);
    alpha = max(alpha, chinAO * 0.04);
    alpha = clamp(alpha, 0.0, 0.20); // Never too heavy

    // Premultiplied alpha
    fragColor = vec4(finalColor, alpha);
}
