// beer-liquid.fsh — the aibeer liquid shader, single source of truth.
//
// Consumed by two wrappers that only add what the environment requires:
//   • iOS: SKShader (SpriteKit injects #version/precision and provides main prolog)
//   • Web: preview/template.html prepends "precision mediump float;"
//          tools/validate-shader.sh prepends "#version 100" + precision for glslangValidator
//
// Coordinate convention (both hosts): gl_FragCoord, +x right, +y UP.
// Uniforms are fed by BeerScene.swift (iOS) and the preview harness JS (web).
//
// Physics model (see README "How it works"):
//   • u_gravity = TRUE world-down (filtered). Bubbles rise along -u_gravity.
//   • u_tilt    = the liquid SURFACE direction from BeerCore's SloshModel — a
//     spring-damper oscillator that lags, overshoots and sloshes around level.
//     Surface geometry uses u_tilt; carbonation uses u_gravity.
//   • u_clock wraps at 60 s on the CPU and the wrap is seamless even on
//     mediump mobile GPUs (no ever-growing sin() arguments). Two invariants:
//     — sin()/cos() terms use INTEGER cycles per minute (h(n) helpers).
//     — lattice-noise offsets (vnoise/worley) use INTEGER CELLS per minute:
//       those functions are periodic per lattice cell, so e.g. "6.0 * tm",
//       never a 2π-scaled h() — otherwise the pattern jumps at every wrap.

uniform vec2  u_gravity;       // unit direction of world-down on screen
uniform vec2  u_tilt;          // unit direction of the (sloshing) liquid surface
uniform float u_fill;          // 0..1 fill level
uniform float u_clock;         // seconds, wrapped at 60 by the CPU
uniform float u_wobble;        // 0..~0.06 wave amplitude
uniform vec2  u_spriteSize;    // viewport size in pixels

uniform vec3  u_bodyTop;       // beer color at the surface (unit optical path)
uniform vec3  u_bodyDeep;      // beer color deep in the glass
uniform vec3  u_glowColor;     // in-scatter / backlit tint
uniform float u_glowStrength;
uniform float u_translucency;
uniform vec3  u_foamColor;
uniform float u_foamThick;     // foam band thickness, screen units
uniform float u_bubbleDensity; // 0..1
uniform float u_bubbleSize;    // bubble radius, screen units
uniform float u_bubbleSpeed;
uniform float u_rainbow;       // 1.0 = rainbow mode


float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Worley/cellular F1 distance — gives the foam its distinct bubbles.
float worley(vec2 p) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    float d = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = vec2(hash21(n + g), hash21(n + g + 31.7));
            d = min(d, length(g + o - f));
        }
    }
    return d;
}

// Integer harmonic of the 60 s base period: n cycles per minute.
// tm is passed explicitly (no shader globals — SKShader's GLSL->Metal
// translation is picky about them).
float h(float n, float tm) {
    return 6.2831853 * n * tm;
}

vec3 rainbowPalette(float t) {
    return 0.5 + 0.5 * cos(6.2831853 * (t + vec3(0.0, 0.33, 0.67)));
}

vec3 addBubbles(vec3 col, vec2 p, float depth, vec2 rise, float tm) {
    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float scale = 9.0 + fl * 5.0;
        // Integer cells-per-minute scroll → seamless at the clock wrap.
        float cells = floor(u_bubbleSpeed * 300.0 * (0.55 + 0.35 * fl));
        vec2 q = p * scale + rise * (cells * tm);
        // Pseudo-acceleration: shear the field by depth (bubbles move faster
        // as they approach the surface).
        q += rise * (0.9 * (1.0 - smoothstep(0.0, 0.7, depth)));
        // Lazy lateral sway.
        q.x += 0.022 * sin(h(66.0 + fl * 42.0, tm) + p.y * 7.0);
        vec2 id = floor(q);
        vec2 f = fract(q) - 0.5;
        float rnd = hash21(id + fl * 17.31);
        if (rnd < u_bubbleDensity) {
            vec2 offs = vec2(hash21(id + 1.3), hash21(id + 2.7)) - 0.5;
            // Bubbles grow slightly as pressure drops near the surface.
            float grow = 1.0 + 0.35 * (1.0 - smoothstep(0.0, 0.6, depth));
            float r = u_bubbleSize * (0.6 + rnd) * (1.0 + fl * 0.4) * grow;
            vec2 d2 = f - offs * 0.55;
            // Elongate the highlight along the rise direction.
            float along = dot(d2, rise);
            float across = dot(d2, vec2(-rise.y, rise.x));
            float e = length(vec2(across, along * 0.72));
            float body = smoothstep(r, r * 0.45, e);
            float rim = smoothstep(r, r * 0.7, e) - smoothstep(r * 0.6, r * 0.3, e);
            float fade = smoothstep(0.0, 0.08, depth);           // pop at the surface
            fade *= 1.0 - smoothstep(0.6, 0.85, depth);          // fade in from the deep
            col += (body * 0.32 + rim * 0.55) * vec3(1.0, 0.98, 0.9) * fade;
        }
    }
    return col;
}

void main() {
    float tm = u_clock * 0.016666667;
    vec2 uv = gl_FragCoord.xy / u_spriteSize;
    vec2 p = (uv - 0.5) * vec2(u_spriteSize.x / u_spriteSize.y, 1.0);

    vec2 surf = u_tilt;                       // sloshing surface direction
    vec2 rise = -u_gravity;                   // bubbles rise along TRUE up

    // Surface height along the (sloshing) surface direction.
    float hgt = mix(0.62, -0.62, u_fill);
    float s = dot(p, surf);

    // Drifting choppy waves, pumped by u_wobble; all harmonics are integer
    // cycles per minute.
    float wav = 0.0;
    wav += sin(p.x * 16.0 + h(30.0, tm)) * 0.50;
    wav += sin(p.y * 12.0 - h(22.0, tm)) * 0.32;
    wav += sin((p.x - p.y) * 26.0 + h(54.0, tm)) * 0.22;
    wav += sin((p.x + p.y) * 33.0 - h(75.0, tm)) * 0.14;
    wav *= u_wobble;
    // Crest steepening: rounded troughs, sharper crests.
    wav = wav / (1.0 + 2.5 * abs(wav));

    float depth = s - hgt + wav;              // > 0 = below the surface = submerged

    // 0 center → 1 at the glass wall.
    float wall = smoothstep(0.55, 1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);

    vec3 col;
    if (depth > 0.0) {
        // ---- Beer-Lambert extinction + in-scattering ----
        // Extinction coefficients derived from the deep color: beer absorbs
        // blue hardest, so sigma grows R < G < B — physically sensible.
        vec3 sigma = -log(max(u_bodyDeep, vec3(0.02)));
        vec3 transmit = exp(-sigma * (depth / 0.55));
        vec3 beer;
        if (u_rainbow > 0.5) {
            // Vivid, animated rainbow: saturated color bands sweep through
            // the liquid (depth + lateral position + time), much livelier
            // than the gentle single-hue cycle of the base styles.
            float bands = depth * 0.5 + p.x * 0.4 - h(3.0, tm);
            vec3 pal = rainbowPalette(bands);
            pal = pal * pal * (3.0 - 2.0 * pal);   // deepen saturation
            // Mild, near-neutral extinction keeps every hue visible deep in
            // the glass instead of collapsing into one dominant color.
            vec3 transmit = exp(-vec3(0.50, 0.45, 0.40) * (depth / 0.55));
            beer = pal * (0.55 + 0.45 * transmit) + u_glowColor * 0.15 * (1.0 - transmit);
        } else {
            beer = u_bodyTop * transmit + u_glowColor * 0.30 * (1.0 - transmit);
        }
        // Backlit glow far from the surface (light panel behind the glass).
        beer += u_glowColor * smoothstep(0.35, 0.9, depth) * u_glowStrength * u_translucency * 0.5;
        // Gentle shimmer: two drifting octaves.
        beer *= 1.0 + 0.045 * sin(p.x * 30.0 + h(19.0, tm)) * sin(p.y * 24.0 - h(13.0, tm));
        // Fresnel-ish brightening at grazing wall angles.
        beer *= 1.0 + 0.30 * wall * wall * wall;
        beer = addBubbles(beer, p, depth, rise, tm);
        // Meniscus: bright crease where liquid meets the glass wall.
        float men = smoothstep(0.0, 0.02, depth) * (1.0 - smoothstep(0.02, 0.09, depth));
        beer += vec3(0.85, 0.9, 1.0) * men * wall * 0.30;
        col = beer;
    } else {
        // Empty glass interior: dark, slightly blue-tinted, brighter near the
        // surface line so a just-emptied glass reads as "wet".
        vec3 glass = mix(vec3(0.030, 0.034, 0.046), vec3(0.065, 0.072, 0.095), uv.y);
        glass += vec3(0.04, 0.045, 0.06) * smoothstep(0.3, 0.0, abs(depth));
        // Wet film clinging to the wall just above the surface.
        float film = exp(depth * 30.0) * wall;
        glass += u_bodyTop * film * 0.06;
        col = glass;
    }

    // ---- foam ----
    // THICK head with a crisp, lumpy edge. Lumps and bubbles are sampled in
    // SURFACE-ALIGNED coordinates with NO time drift, so the foam is one
    // piece anchored to the sloshing surface: it tilts, rides the waves and
    // settles as a whole — no bits generate or fall.
    float along = dot(p, vec2(-surf.y, surf.x));   // position along the surface
    float across = s - hgt;                        // signed distance, waves excluded
    float fn = vnoise(vec2(along * 24.0, across * 60.0));
    float lumps = 0.5 * fn + 0.5 * vnoise(vec2(along * 9.0, across * 22.0));
    float foamThick = u_foamThick * (0.55 + 0.9 * lumps) * (1.0 + min(u_wobble * 9.0, 0.8)) + abs(wav);
    float topEdge = -foamThick;
    float foamBand = smoothstep(topEdge, topEdge + 0.012, depth) * (1.0 - smoothstep(0.0, 0.012, depth));
    if (u_fill > 0.003) {
        float cells = worley(vec2(along * 62.0, across * 55.0));
        float fine = worley(vec2(along * 100.0, across * 90.0));
        float dots = (1.0 - smoothstep(0.02, 0.30, cells)) * 0.16
                   + (1.0 - smoothstep(0.02, 0.30, fine)) * 0.08;
        vec3 foamCol = u_foamColor * (1.0 - dots);
        foamCol *= 0.96 + 0.04 * vnoise(vec2(along * 90.0, across * 80.0));
        col = mix(col, foamCol, foamBand);
    }

    // Bright glint right at the surface line.
    col += vec3(0.9) * exp(-abs(depth) * 55.0) * 0.35 * step(0.003, u_fill);

    // Glass rim light + vignette.
    vec2 e = abs(uv - 0.5) * 2.0;
    float edge = max(e.x, e.y);
    col += vec3(0.75, 0.8, 0.9) * smoothstep(0.94, 1.0, edge) * 0.18;
    col *= 1.0 - 0.30 * smoothstep(0.55, 1.05, length((uv - 0.5) * vec2(1.4, 1.0)));

    gl_FragColor = vec4(col, 1.0);
}
