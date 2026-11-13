#version 300 es
// Hyprland's screen shader. It gives the whole composited frame a CRT look: a
// slight fish-eye bulge, a black frame that fades in at the edges, scanlines,
// a soft glow around bright pixels and a thin distortion line that rolls down
// the screen.
//
// The rolling line reads the time uniform, so the screen has to be redrawn
// every frame. The nix module sets the Hyprland options for that.
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
layout(location = 0) out vec4 fragColor;

// Strength of the bulge. The middle of the screen grows by this share and the
// edges shrink to make room. The edge midpoints stay on the screen edges and
// the corners recede, so nothing is cut off. Clicks still land on the flat
// image. Away from the centre and the edge midpoints they miss what is drawn
// by up to this share of half the screen.
const float curve = 0.016;
// Width in pixels of the fade from black to the image, and the radius of the
// image's rounded corners. Both are kept small so the bar's outer items stay
// bright.
const float edgeFade = 8.0;
const float cornerRadius = 12.0;
// Scanlines repeat every few pixels of the image and darken it by at most
// this share between lines.
const float scanlinePeriod = 3.0;
const float scanlineDepth = 0.3;
// The glow samples the image this many pixels away in four directions and
// lifts darker pixels towards it by this share.
const float glowSpread = 2.0;
const float glowMix = 0.25;
// The distortion line crosses the screen once per period in seconds. It is
// this many pixel rows tall. Its middle row shifts the image left by the full
// amount in pixels and brightens it by the gain. The rows above and below
// shift and brighten less the further out they are, so straight edges bend
// into a point as the line passes.
const float linePeriod = 7.0;
const float lineRows = 5.0;
const float lineShift = 5.0;
const float lineGain = 0.15;

void main() {
    vec2 size = vec2(textureSize(tex, 0));

    // Map the screen point to the image point it shows, in -1..1 around the
    // centre.
    vec2 c = v_texcoord * 2.0 - 1.0;
    c *= 1.0 + curve * (dot(c, c) - 1.0);
    vec2 uv = c * 0.5 + 0.5;

    // Signed distance in pixels to the image's rounded edge, negative inside.
    vec2 halfSize = size * 0.5;
    vec2 q = abs(c) * halfSize - (halfSize - cornerRadius);
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerRadius;
    float frame = smoothstep(0.0, edgeFade, -dist);
    if (frame <= 0.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // The line starts just above the screen and ends just below it, so it
    // enters and leaves whole. Its position snaps to whole rows, so it keeps
    // its height as it moves. An even row count centres it between two rows.
    float linePos = floor((fract(time / linePeriod) * 1.1 - 0.05) * size.y) + 0.5 * mod(lineRows, 2.0);
    float line = clamp(1.0 - abs(uv.y * size.y - linePos) / (0.5 * lineRows + 0.5), 0.0, 1.0);
    uv.x -= line * lineShift / size.x;

    vec2 px = glowSpread / size;
    vec3 rgb = texture(tex, uv).rgb;
    vec3 glow = (texture(tex, uv + vec2(px.x, 0.0)).rgb
        + texture(tex, uv - vec2(px.x, 0.0)).rgb
        + texture(tex, uv + vec2(0.0, px.y)).rgb
        + texture(tex, uv - vec2(0.0, px.y)).rgb) * 0.25;
    rgb += glowMix * max(glow - rgb, 0.0);

    // The lines follow the image's rows, so they bend with the curve.
    float scan = 1.0 - scanlineDepth * (0.5 - 0.5 * cos(6.2831853 * uv.y * size.y / scanlinePeriod));
    rgb *= scan * (1.0 + lineGain * line);
    fragColor = vec4(min(rgb, 1.0) * frame, 1.0);
}
