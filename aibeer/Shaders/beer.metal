#include <metal_stdlib>
using namespace metal;

// The aiBeer liquid shader, ported from shaders/beer-liquid.fsh (GLSL ES).
// Compiled at BUILD TIME by Xcode — no runtime SKShader transpilation, so
// shader errors surface in CI, not as a black screen on the device.
//
// Coordinate convention: uv from the vertex stage, +x right, +y UP.
// Time invariants (see shaders/beer-liquid.fsh header):
//   — sin/cos terms use INTEGER cycles per minute (h(n))
//   — lattice-noise offsets use INTEGER CELLS per minute

struct BeerUniforms {
    float2 gravity;        // unit direction of world-down on screen
    float2 tilt;           // unit direction of the (sloshing) liquid surface
    float2 spriteSize;     // drawable size in pixels
    float3 bodyTop;        // beer color at the surface
    float3 bodyDeep;       // beer color deep in the glass
    float3 glowColor;      // in-scatter / backlit tint
    float3 foamColor;
    float  fill;           // 0..1
    float  clock;          // seconds, wrapped at 60 by the CPU
    float  wobble;         // 0..~0.06 wave amplitude
    float  glowStrength;
    float  translucency;
    float  foamThick;
    float  bubbleDensity;
    float  bubbleSize;
    float  bubbleSpeed;
    float  rainbow;        // 1.0 = rainbow mode
};

float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Worley/cellular F1 distance — gives the foam its distinct bubbles.
float worley(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);
    float d = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 g = float2(float(i), float(j));
            float2 o = float2(hash21(n + g), hash21(n + g + 31.7));
            d = min(d, length(g + o - f));
        }
    }
    return d;
}

// Integer harmonic of the 60 s base period: n cycles per minute.
float h(float n, float tm) {
    return 6.2831853 * n * tm;
}

float3 rainbowPalette(float t) {
    return 0.5 + 0.5 * cos(6.2831853 * (t + float3(0.0, 0.33, 0.67)));
}

float3 addBubbles(float3 col, float2 p, float depth, float2 rise, float tm, constant BeerUniforms &u) {
    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float scale = 9.0 + fl * 5.0;
        // Integer cells-per-minute scroll → seamless at the clock wrap.
        float cells = floor(u.bubbleSpeed * 300.0 * (0.55 + 0.35 * fl));
        float2 q = p * scale + rise * (cells * tm);
        // Pseudo-acceleration: shear the field by depth (bubbles move faster
        // as they approach the surface).
        q += rise * (0.9 * (1.0 - smoothstep(0.0, 0.7, depth)));
        // Lazy lateral sway.
        q.x += 0.022 * sin(h(66.0 + fl * 42.0, tm) + p.y * 8.0);
        float2 id = floor(q);
        float2 f = fract(q) - 0.5;
        float rnd = hash21(id + fl * 17.31);
        if (rnd < u.bubbleDensity) {
            float2 offs = float2(hash21(id + 1.3), hash21(id + 2.7)) - 0.5;
            // Bubbles grow slightly as pressure drops near the surface.
            float grow = 1.0 + 0.35 * (1.0 - smoothstep(0.0, 0.6, depth));
            float r = u.bubbleSize * (0.6 + rnd) * (1.0 + fl * 0.4) * grow;
            float2 d2 = f - offs * 0.55;
            // Elongate the highlight along the rise direction.
            float along = dot(d2, rise);
            float across = dot(d2, float2(-rise.y, rise.x));
            float e = length(float2(across, along * 0.72));
            float body = smoothstep(r, r * 0.45, e);
            float rim = smoothstep(r, r * 0.7, e) - smoothstep(r * 0.6, r * 0.3, e);
            float fade = smoothstep(0.0, 0.08, depth);            // pop at the surface
            fade *= 1.0 - smoothstep(0.6, 0.85, depth);           // fade in from the deep
            col += (body * 0.32 + rim * 0.55) * float3(1.0, 0.98, 0.9) * fade;
        }
    }
    return col;
}

struct RasterData {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle, no vertex buffer: positions from the vertex id.
vertex RasterData beerVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    RasterData out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.uv = pos[vid] * 0.5 + 0.5;
    return out;
}

fragment float4 beerFragment(RasterData in [[stage_in]],
                             constant BeerUniforms &u [[buffer(0)]]) {
    float tm = u.clock * 0.016666667;   // time in minutes, seamless at wrap
    float2 uv = in.uv;
    float2 p = (uv - 0.5) * float2(u.spriteSize.x / u.spriteSize.y, 1.0);

    float2 surf = u.tilt;               // sloshing surface direction
    float2 rise = -u.gravity;           // bubbles rise along TRUE up

    // Surface height along the (sloshing) surface direction.
    float hgt = mix(0.62, -0.62, u.fill);
    float s = dot(p, surf);

    // Drifting choppy waves, pumped by u_wobble.
    float wav = 0.0;
    wav += sin(p.x * 16.0 + h(30.0, tm)) * 0.50;
    wav += sin(p.y * 12.0 - h(22.0, tm)) * 0.32;
    wav += sin((p.x - p.y) * 26.0 + h(54.0, tm)) * 0.22;
    wav += sin((p.x + p.y) * 33.0 - h(75.0, tm)) * 0.14;
    wav *= u.wobble;
    // Crest steepening: rounded troughs, sharper crests.
    wav = wav / (1.0 + 2.5 * abs(wav));

    float depth = s - hgt + wav;        // > 0 = below the surface = submerged

    // 0 center → 1 at the glass wall.
    float wall = smoothstep(0.55, 1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);

    float3 col;
    if (depth > 0.0) {
        // Beer-Lambert extinction + in-scattering.
        float3 sigma = -log(max(u.bodyDeep, float3(0.02)));
        float3 transmit = exp(-sigma * (depth / 0.55));
        float3 beer;
        if (u.rainbow > 0.5) {
            // Vivid, animated rainbow: saturated color bands sweep through
            // the liquid (depth + lateral position + time), much livelier
            // than the gentle single-hue cycle of the base styles.
            float bands = depth * 0.5 + p.x * 0.4 - h(3.0, tm);
            float3 pal = rainbowPalette(bands);
            pal = pal * pal * (3.0 - 2.0 * pal);   // deepen saturation
            // Mild, near-neutral extinction keeps every hue visible deep in
            // the glass instead of collapsing into one dominant color.
            float3 transmit = exp(-float3(0.50, 0.45, 0.40) * (depth / 0.55));
            beer = pal * (0.55 + 0.45 * transmit) + u.glowColor * 0.15 * (1.0 - transmit);
        } else {
            beer = u.bodyTop * transmit + u.glowColor * 0.30 * (1.0 - transmit);
        }
        // Backlit glow far from the surface.
        beer += u.glowColor * smoothstep(0.15, 0.75, depth) * u.glowStrength * u.translucency * 0.5;
        // Gentle shimmer.
        beer *= 1.0 + 0.045 * sin(p.x * 30.0 + h(19.0, tm)) * sin(p.y * 24.0 - h(13.0, tm));
        // Fresnel-ish brightening at grazing wall angles.
        beer *= 1.0 + 0.30 * wall * wall * wall;
        beer = addBubbles(beer, p, depth, rise, tm, u);
        // Meniscus: bright crease where liquid meets the glass wall.
        float men = smoothstep(0.0, 0.02, depth) * (1.0 - smoothstep(0.02, 0.09, depth));
        beer += float3(0.85, 0.9, 1.0) * men * wall * 0.30;
        col = beer;
    } else {
        // Empty glass interior.
        float3 glass = mix(float3(0.030, 0.034, 0.046), float3(0.065, 0.072, 0.095), uv.y);
        glass += float3(0.04, 0.045, 0.06) * smoothstep(0.3, 0.0, abs(depth));
        // Wet film clinging to the wall just above the surface.
        float film = exp(depth * 30.0) * wall;
        glass += u.bodyTop * film * 0.06;
        col = glass;
    }

    // ---- foam ----
    // Fluid-dynamic foam: a THICK head with a crisp edge that undulates
    // gently (low-frequency, traveling) — smooth enough that it never folds
    // into detached islands. The interior keeps organic density variation
    // and slowly drifting, shearing bubbles. Lattice offsets stay integer
    // CELLS per minute (see header) — seamless at the clock wrap.
    float along = dot(p, float2(-surf.y, surf.x));   // position along the surface
    float across = s - hgt;                          // signed distance, waves excluded
    // Edge shape: low-frequency traveling undulation only.
    float edgeNoise = vnoise(float2(along * 5.0 + 2.0 * tm, 0.0));
    float foamWave = sin(along * 10.0 - h(4.0, tm)) * u.foamThick * u.wobble * 8.0;
    float foamThick = u.foamThick * (0.82 + 0.40 * edgeNoise + foamWave) * (1.0 + min(u.wobble * 9.0, 0.8)) + abs(wav);
    float topEdge = -foamThick;
    float foamBand = smoothstep(topEdge, topEdge + 0.012, depth) * (1.0 - smoothstep(0.0, 0.012, depth));
    if (u.fill > 0.003) {
        // Interior texture: drifting, shearing bubble dots with organic
        // density variation (lumps stay inside; the edge stays smooth).
        float lumps = 0.5 * vnoise(float2(along * 24.0, across * 60.0))
                    + 0.5 * vnoise(float2(along * 9.0, across * 22.0));
        float drift = 1.5 * tm + 1.2 * u.wobble * sin(along * 5.0 - h(2.0, tm));
        float bob = 0.35 * sin(along * 8.0 - h(3.0, tm));
        float cells = worley(float2((along + drift) * 62.0, across * 55.0 + bob));
        float fine = worley(float2((along - drift * 0.6) * 100.0, across * 90.0 - bob * 0.7));
        float dots = ((1.0 - smoothstep(0.02, 0.30, cells)) * 0.16
                    + (1.0 - smoothstep(0.02, 0.30, fine)) * 0.08) * (0.55 + 0.9 * lumps);
        float3 foamCol = u.foamColor * (1.0 - dots);
        foamCol *= 0.96 + 0.04 * vnoise(float2(along * 90.0, across * 80.0));
        col = mix(col, foamCol, foamBand);
    }

    // Bright glint right at the surface line.
    col += float3(0.9) * exp(-abs(depth) * 55.0) * 0.35 * step(0.003, u.fill);

    // Glass rim light + vignette.
    float2 e = abs(uv - 0.5) * 2.0;
    float edge = max(e.x, e.y);
    col += float3(0.75, 0.8, 0.9) * smoothstep(0.94, 1.0, edge) * 0.18;
    col *= 1.0 - 0.30 * smoothstep(0.55, 1.05, length((uv - 0.5) * float2(1.4, 1.0)));

    return float4(col, 1.0);
}
