#version 440
// The wallpaper redrawn with a slow life in it: the painted sky turns around the tree, the emblem
// breathes, a light climbs it now and then, a few motes wander, petals fall, a creature breathes and
// blinks. With every strength at 0 the picture comes out untouched.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float breath;        // 0 = the painting as it is, 1 = full inhale
    float strength;      // peak opacity of the breath
    float wave;          // 0..1 = a light on its way from the foot to the crown, above 1 = none
    float waveStrength;
    float t;             // seconds, wraps every hour: all motion below runs whole cycles per hour
    float mistStrength;  // how far the sky travels in one cycle, in mask pixels
    float moteStrength;
    float owl;           // 0 = exhaled, 1 = inhaled; times how far the body swells, 0 when there is no creature
    float blink;         // 0 = eye open, 1 = shut
    float petalStrength; // opacity of the falling petals, 0 when the wallpaper has none
};
layout(binding = 1) uniform sampler2D mask;  // R emblem + halo, G distance from the trunk's foot, B sky that may flow
layout(binding = 2) uniform sampler2D art;   // the wallpaper itself
layout(binding = 3) uniform sampler2D life;  // a creature: R, G where its pixels go on an inhale, B its eye
layout(binding = 4) uniform sampler2D petals; // three petals cut from the painting, side by side

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

    float a = m.r * strength * breath;

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
