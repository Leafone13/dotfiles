#version 440
// The wallpaper redrawn with a slow life in it: the painted sky turns around the tree, the emblem
// breathes, a light climbs it now and then and ripples on through the scene, a few motes wander,
// petals fall, a bough stirs, a creature breathes and blinks. With every strength at 0 the picture
// comes out untouched.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float breathPhase;   // 0..1 through one breath: the painting as it is at 0, full inhale at 0.5
    float strength;      // peak opacity of the breath
    float wave;          // 0..1 = a light on its way from the foot to the crown, above 1 = none
    float waveStrength;
    float t;             // seconds, wraps every hour: all motion below runs whole cycles per hour
    float mistStrength;  // how far the sky travels in one cycle, in mask pixels
    float moteStrength;
    float owl;           // 0 = exhaled, 1 = inhaled; times how far the body swells, 0 when there is no creature
    float blink;         // 0 = eye open, 1 = shut
    float petalStrength; // opacity of the falling petals, 0 when the wallpaper has none
    float rippleStrength; // how much brighter the painting's own lights get as the wave passes them
    float swayStrength;  // radians a bough turns at the height of a gust, 0 when the wallpaper has none
    float creatureRipple; // the share of the ripple the creature takes, 1 when the wallpaper has none
    float rippleLarge;   // the share of the ripple a large bright thing takes, the moon first of all
    float haloLag;       // how far behind the lines the faintest halo breathes, as a share of a breath
};
layout(binding = 1) uniform sampler2D mask;  // R emblem + halo, G distance from the trunk's foot, B sky that may flow
layout(binding = 2) uniform sampler2D art;   // the wallpaper itself
layout(binding = 3) uniform sampler2D life;  // a creature: R, G where its pixels go on an inhale, B its eye
layout(binding = 4) uniform sampler2D petals; // three petals cut from the painting, side by side
layout(binding = 5) uniform sampler2D sway;  // a bough: R, G where its pixels go per radian of turn

const float TAU = 6.2831853;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void main() {
    vec3 m = texture(mask, qt_TexCoord0).rgb;
    vec2 px = qt_TexCoord0 * vec2(1920.0, 1080.0);
    float turn = TAU * t / 3600.0;  // one full turn per hour

    // mist: the sky drifts along circles around the trunk's foot. Two copies of the picture, half a
    // cycle apart, each fading out before it jumps back, so the drift never ends and never resets.
    const vec2 e = vec2(40.0 / 1920.0, 40.0 / 1080.0);
    vec2 out_ = vec2(texture(mask, qt_TexCoord0 + vec2(e.x, 0)).g - texture(mask, qt_TexCoord0 - vec2(e.x, 0)).g,
                     texture(mask, qt_TexCoord0 + vec2(0, e.y)).g - texture(mask, qt_TexCoord0 - vec2(0, e.y)).g);
    vec2 along = length(out_) > 0.002 ? normalize(vec2(-out_.y, out_.x)) : vec2(0.0);
    vec2 reach = along * m.b * mistStrength / vec2(1920.0, 1080.0);
    float cycle = turn * 80.0 / TAU + noise(px / 260.0);  // 45 s, out of step from place to place
    float p1 = fract(cycle), p2 = fract(cycle + 0.5);
    // the creature breathes: its body is drawn from a little nearer its feet, so it rises and swells.
    // It sits in a still zone, so the drift above is zero here and the two never fight.
    vec3 l = texture(life, qt_TexCoord0).rgb;
    vec2 at = qt_TexCoord0 - (l.rg - 127.0 / 255.0) * 400.0 * owl / vec2(1920.0, 1080.0);
    // a bough stirs: a small turn around the point it hangs from, the tips a little behind the base, in
    // gusts that come every minute and a half and leave it nearly at rest between them
    vec2 arm = (texture(sway, qt_TexCoord0).rg - 127.0 / 255.0) * 800.0;
    float lag = length(arm) / 150.0;
    at -= arm * swayStrength * (0.3 + 0.7 * (0.5 + 0.5 * sin(turn * 40.0)))
          * (0.6 * sin(turn * 450.0 - lag) + 0.4 * sin(turn * 277.0 - 1.7 * lag + 1.0)) / vec2(1920.0, 1080.0);
    vec3 c = mix(texture(art, at - reach * (p2 - 0.5)).rgb,
                 texture(art, at - reach * (p1 - 0.5)).rgb, 1.0 - abs(2.0 * p1 - 1.0));
    // a blink paints the eye over with the feathers beside it
    c = mix(c, texture(art, at + vec2(-11.0 / 1920.0, 3.0 / 1080.0)).rgb, texture(life, at).b * blink * sign(owl + blink));

    // three petals leave the leafy branch on the left, ten minutes apart, each taking twelve minutes to
    // sink and dissolve in the air well before the ground, then resting unseen: seldom two at once,
    // and no petal ever enters or leaves, it fades in and out
    const vec3 FROM = vec3(0.25, 0.30, 0.14), SIDEWAYS = vec3(0.04, -0.03, -0.04);
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float lap = fract(t / 3600.0 * 2.0 + fk / 3.0) * 2.5;  // a fall is the first 40 % of a half-hour turn
        if (lap >= 1.0) continue;
        vec2 spot = vec2(FROM[k] + SIDEWAYS[k] * lap + 0.012 * sin(TAU * (lap * 3.0 + 0.3 * fk)), 0.10 + 0.60 * lap)
                    * vec2(1920.0, 1080.0);
        float turned = fk + 0.7 * sin(TAU * (lap * 2.0 + 0.2 * fk));
        vec2 d = px - spot;
        vec2 s = vec2(cos(turned) * d.x - sin(turned) * d.y, sin(turned) * d.x + cos(turned) * d.y) / 56.0 + 0.5;
        if (s.x > 0.0 && s.x < 1.0 && s.y > 0.0 && s.y < 1.0) {
            float there = smoothstep(0.0, 0.08, lap) * (1.0 - smoothstep(0.30, 1.0, lap));
            vec4 petal = texture(petals, vec2((s.x + fk) / 3.0, s.y)) * petalStrength * there;  // premultiplied
            c = c * (1.0 - petal.a) + petal.rgb;
        }
    }

    // the ripple: the light that climbed the tree travels on past the crown, and whatever the painting
    // already lit (owl, leaves, flowers, at last the moon) answers in its own colour, later the farther
    // it is from the foot. Not the emblem (the wave has it), not the corners beyond the mask's reach.
    // A large bright thing answers fainter: lit in full, the moon was louder than the emblem itself.
    // Large = bright on most sides, 45 px away in eight directions (the moon to its very rim); a flower or a leaf is not.
    // (Distance cannot tell them apart: the moon is as far from the foot as the far flowers.)
    const vec3 LUM = vec3(0.299, 0.587, 0.114);
    float around = 0.0;
    for (int k = 0; k < 8; k++)
        around += dot(texture(art, qt_TexCoord0 + 45.0 * vec2(cos(0.7854 * float(k)), sin(0.7854 * float(k))) / vec2(1920.0, 1080.0)).rgb, LUM);
    float lit = smoothstep(0.45, 0.85, dot(c, LUM)) * (1.0 - smoothstep(0.02, 0.25, m.r))
                * (1.0 - smoothstep(0.93, 1.0, m.g))
                * mix(1.0, rippleLarge, smoothstep(0.25, 0.5, around / 8.0))
                // the creature is the largest bright thing near the tree: lit in full it flares
                * mix(1.0, creatureRipple, smoothstep(0.0, 0.03, length(l.rg - 127.0 / 255.0)));
    float lift = lit * smoothstep(0.12, 0.0, abs(m.g - wave * 0.62))
                 * smoothstep(0.5, 0.9, wave) * (1.0 - smoothstep(1.45, 1.7, wave)) * rippleStrength;
    c *= 1.0 + lift;
    c += (hash(gl_FragCoord.yx) - 0.5) / 255.0 * step(0.0005, lift);  // dither, as for the light below

    // the breath starts in the lines and spreads out through the halo: the fainter the glow, the later
    // it follows, so the light has a body and not one flat pulse
    float a = m.r * strength * (0.5 - 0.5 * cos(TAU * (breathPhase - haloLag * (1.0 - m.r))));

    // a soft band of light climbing away from the foot, only on the lines themselves (r squared drops the halo)
    float band = smoothstep(0.09, 0.0, abs(m.g - wave * 0.62));
    a += m.r * m.r * band * sin(3.14159 * clamp(wave, 0.0, 1.0)) * waveStrength;

    // motes: at most one per 240 px cell, each wandering around its own spot and fading in and out
    vec2 cell = floor(px / 240.0);
    float id = hash(cell);
    if (id < 0.4) {
        vec2 spot = (cell + 0.5) * 240.0 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 130.0;
        float k = floor(40.0 + 50.0 * hash(cell + 1.3));  // whole cycles per hour, so 40 to 90 s each
        float ph = TAU * hash(cell + 5.9);
        spot += 38.0 * vec2(sin(turn * k + ph), cos(turn * (k + 13.0) + ph * 1.7));
        float d = length(px - spot);
        float glow = exp(-d * d / 4.5) + 0.25 * exp(-d * d / 40.0);
        a += glow * (0.5 + 0.5 * sin(turn * (k * 3.0 + 7.0) + ph * 2.3)) * moteStrength;
    }

    // half a level of static noise, or the slow fades crawl in visible 8-bit steps
    a = clamp(a + (hash(gl_FragCoord.xy) - 0.5) / 255.0 * step(0.002, a), 0.0, 1.0);
    fragColor = vec4(mix(c, vec3(0.80, 0.90, 1.0), a), 1.0) * qt_Opacity;
}
