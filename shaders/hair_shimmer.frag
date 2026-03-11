#include <flutter/runtime_effect.glsl>

// Uniforms set from Dart via FragmentShader.setFloat()
uniform vec2 uSize;    // width, height of the paint area
uniform float uTime;   // elapsed seconds (drives the band movement)
uniform float uSway;   // 0.0-1.0 sway value — shifts highlight band position

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;

    // ── Anisotropic highlight band ──
    // Follows strand direction (mostly vertical) with slight horizontal
    // influence from the sway animation, so the shimmer tracks with
    // head movement like real hair catching light.

    float swayOffset = (uSway - 0.5) * 0.4;
    float bandInput = uv.y * 18.0 + uv.x * 3.0 * swayOffset - uTime * 1.8;

    // Primary highlight — sharp and bright (narrow specular band)
    float primaryBand = pow(max(sin(bandInput), 0.0), 12.0);

    // Secondary softer band — offset phase gives depth to the shimmer
    float secondaryBand = pow(max(sin(bandInput * 0.7 + 1.2), 0.0), 6.0) * 0.3;

    // Tertiary micro-shimmer — very fine, adds realistic grain
    float microShimmer = pow(max(sin(bandInput * 3.0 + 0.8), 0.0), 16.0) * 0.12;

    float highlight = primaryBand + secondaryBand + microShimmer;

    // ── Color ──
    // Warm white with slight gold tint, warmer toward the top (light source)
    float warmShift = 1.0 - uv.y * 0.12;
    vec3 highlightColor = vec3(1.0 * warmShift, 0.96 * warmShift, 0.86);

    // ── Edge falloff ──
    // Less shimmer at the very edges to avoid artifacts at hair boundary
    float edgeFade = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
    float topFade = smoothstep(0.0, 0.08, uv.y);
    float bottomFade = smoothstep(1.0, 0.92, uv.y);

    float alpha = highlight * 0.28 * edgeFade * topFade * bottomFade;

    // Premultiplied alpha output for correct compositing
    fragColor = vec4(highlightColor * alpha, alpha);
}
