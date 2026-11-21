// shared/runtime.js — the aibeer web runtime, inlined by tools/embed.mjs into
// BOTH the dev preview (preview/index.html) and the installable PWA
// (app/index.html). Single source of truth for the JS ports of BeerCore
// (SloshModel / WobbleModel), WebGL setup, input handling and the render loop.
//
// Host pages define FRAG_BODY and STYLES, then call:
//
//   const app = createAibeer({
//     canvas,            // <canvas> element
//     fragBody,          // GLSL ES 1.00 shader body string
//     styles,            // array from BeerCore (styles.json)
//     initial: {         // optional initial state (URL params in hosts)
//       styleId, fill, deg, wobble, freeze, kick
//     },
//     gravityProvider,   // optional () => [x, y] | null (PWA gyro module).
//                        // Null result = no live tilt → drag/keys take over.
//     onStyleChange,     // optional (style) => void — fired on drink swipes
//   });
//
// Gestures: drag = tilt, fast horizontal flick = next/previous drink.

function createAibeer(opts) {
  "use strict";
  const canvas = opts.canvas;
  const gravityProvider = opts.gravityProvider || null;
  const STYLES = opts.styles;
  const initial = opts.initial || {};

  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const num = (v, d) => (Number.isFinite(v) ? v : d);

  // =====================================================================
  // State — JS ports of BeerCore (GravityFilter implicit via drag smoothing,
  // SloshModel, WobbleModel, FillController). Tilt past ~33° drains; swipe
  // up refills.
  // =====================================================================
  const onStyleChange = opts.onStyleChange || null;
  let style = STYLES.find(s => s.id === initial.styleId) || STYLES[0];
  let fill = clamp(num(initial.fill, 0.5), 0, 1);
  const deg = num(initial.deg, 0);
  let manualDir = [Math.sin(deg * Math.PI / 180), -Math.cos(deg * Math.PI / 180)];
  const frozenWobble = initial.freeze ? clamp(num(initial.wobble, 0.02), 0, 0.06) : null;
  let wobble = frozenWobble ?? 0.012;
  let refilling = false;

  // FillController port.
  const FILL_RATE = 0.22, DRAIN_RATE = 0.55;

  // ---- SloshModel port: spring-damper free surface ----
  const slosh = {
    dir: manualDir.slice(), w: 0, err: 0,
    naturalFrequency: 8.8, dampingRatio: 0.15,
    maxDeviation: 1.2, maxAngularVelocity: 12.0
  };
  function wrapPi(a) {
    a = a % (2 * Math.PI);
    if (a <= -Math.PI) a += 2 * Math.PI;
    if (a > Math.PI) a -= 2 * Math.PI;
    return a;
  }
  function sloshUpdate(t, dt) {
    dt = Math.min(Math.max(dt, 0.0001), 0.05);
    const ta = Math.atan2(t[1], t[0]);
    const sa = Math.atan2(slosh.dir[1], slosh.dir[0]);
    let err = wrapPi(ta - sa);
    err = clamp(err, -slosh.maxDeviation, slosh.maxDeviation);
    slosh.err = Math.abs(err);
    const k = slosh.naturalFrequency * slosh.naturalFrequency;
    const c = 2 * slosh.dampingRatio * slosh.naturalFrequency;
    slosh.w = clamp(slosh.w + (k * err - c * slosh.w) * dt,
      -slosh.maxAngularVelocity, slosh.maxAngularVelocity);
    const na = sa + slosh.w * dt;
    slosh.dir = [Math.cos(na), Math.sin(na)];
    return slosh.dir;
  }
  function sloshSettle(t) {
    const l = Math.hypot(t[0], t[1]) || 1;
    slosh.dir = [t[0] / l, t[1] / l];
    slosh.w = 0; slosh.err = 0;
  }
  function sloshEnergy() {
    return Math.min(1, slosh.err / 0.35 + Math.abs(slosh.w) / slosh.naturalFrequency * 0.5);
  }

  // Screenshot helpers (preview): freeze pins the settled surface; kick
  // starts it off-level so a timed screenshot catches mid-slosh.
  if (initial.freeze) {
    sloshSettle(manualDir);
  } else if (initial.kick) {
    const a = deg * Math.PI / 180 + 0.9;
    slosh.dir = [Math.cos(a), Math.sin(a)];
    slosh.w = 3.0;
  }

  // =====================================================================
  // WebGL setup
  // =====================================================================
  const gl = canvas.getContext("webgl", { antialias: true });
  if (!gl) { document.title = "WebGL unavailable"; return null; }

  function compileShader(type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      document.title = "SHADER ERROR";
      throw new Error(gl.getShaderInfoLog(sh));
    }
    return sh;
  }

  function setupProgram() {
    const prog = gl.createProgram();
    gl.attachShader(prog, compileShader(gl.VERTEX_SHADER,
      "attribute vec2 a; void main(){ gl_Position = vec4(a, 0.0, 1.0); }"));
    gl.attachShader(prog, compileShader(gl.FRAGMENT_SHADER,
      "precision mediump float;\n" + opts.fragBody));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(prog));
    }
    gl.useProgram(prog);

    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const attr = gl.getAttribLocation(prog, "a");
    gl.enableVertexAttribArray(attr);
    gl.vertexAttribPointer(attr, 2, gl.FLOAT, false, 0, 0);
    return prog;
  }

  const UNIFORM_NAMES = ["u_gravity", "u_tilt", "u_fill", "u_clock", "u_wobble", "u_spriteSize",
    "u_bodyTop", "u_bodyDeep", "u_glowColor", "u_glowStrength", "u_translucency",
    "u_foamColor", "u_foamThick", "u_bubbleDensity", "u_bubbleSize", "u_bubbleSpeed", "u_rainbow"];

  const prog = setupProgram();
  const U = {};
  for (const n of UNIFORM_NAMES) U[n] = gl.getUniformLocation(prog, n);

  // =====================================================================
  // Input — drag sets manual tilt (when no live gravity), a fast horizontal
  // flick switches the drink, and arrows/keys adjust tilt. Manual tilt only
  // applies when no live gravity provider is driving.
  // =====================================================================
  let dragging = false, lastX = 0, lastY = 0;
  let gestureStart = null; // { x, y, t } for swipe detection

  function gravityActive() {
    return !!(gravityProvider && gravityProvider());
  }

  canvas.addEventListener("pointerdown", e => {
    dragging = true; lastX = e.clientX; lastY = e.clientY;
    gestureStart = { x: e.clientX, y: e.clientY, t: performance.now() };
  });
  window.addEventListener("pointerup", e => {
    dragging = false;
    if (gestureStart) detectStyleSwipe(e);
    gestureStart = null;
  });
  window.addEventListener("pointercancel", () => {
    dragging = false;
    gestureStart = null;
  });
  window.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - lastX, dy = e.clientY - lastY;
    lastX = e.clientX; lastY = e.clientY;
    const vx = e.clientX - canvas.clientWidth / 2;
    const vy = canvas.clientHeight / 2 - e.clientY;   // y-up
    const len = Math.hypot(vx, vy);
    if (!gravityActive() && len > 10) manualDir = [vx / len, vy / len];
    wobble = clamp(wobble + Math.hypot(dx, dy) * 0.0006, 0, 0.06);
  });

  // A fast, mostly-horizontal flick changes the drink: left = next,
  // right = previous. A fast upward flick refills. Slow drags remain tilt
  // gestures.
  function detectStyleSwipe(e) {
    const dx = e.clientX - gestureStart.x;
    const dy = e.clientY - gestureStart.y;
    const dt = performance.now() - gestureStart.t;
    if (dt >= 400) return;
    if (Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy)) {
      const step = dx < 0 ? 1 : -1;
      const idx = STYLES.findIndex(s => s.id === style.id);
      style = STYLES[(idx + step + STYLES.length) % STYLES.length];
      if (onStyleChange) onStyleChange(style);
    } else if (dy < -60 && Math.abs(dy) > 2 * Math.abs(dx)) {
      refilling = true;
    }
  }

  function norm(x, y) { const l = Math.hypot(x, y) || 1; return [x / l, y / l]; }
  window.addEventListener("keydown", e => {
    const step = 0.12;
    if (e.key === "ArrowLeft")  manualDir = norm(manualDir[0] - step, manualDir[1]);
    if (e.key === "ArrowRight") manualDir = norm(manualDir[0] + step, manualDir[1]);
    if (e.key === "ArrowUp")    manualDir = norm(manualDir[0], manualDir[1] + step);
    if (e.key === "ArrowDown")  manualDir = norm(manualDir[0], manualDir[1] - step);
  });

  // =====================================================================
  // Render loop
  // =====================================================================
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.round(canvas.clientWidth * dpr);
    const h = Math.round(canvas.clientHeight * dpr);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w; canvas.height = h;
      gl.viewport(0, 0, w, h);
    }
  }
  window.addEventListener("resize", resize);

  /// Advances slosh/wobble/fill one frame; returns the shader state.
  function advanceState(dt) {
    if (frozenWobble !== null) {
      return { surface: slosh.dir, amplitude: wobble, targetDir: manualDir };
    }
    const live = gravityProvider ? gravityProvider() : null;
    const targetDir = live ? [live[0], live[1]] : manualDir;
    const surface = sloshUpdate(targetDir, dt);
    const amplitude = Math.max(0.004, wobble * Math.exp(-dt / 0.6), sloshEnergy() * 0.06);
    wobble = amplitude;

    // Tilt-drink: rolling the glass left/right past ~30° drains it — the
    // further sideways, the faster. Pitch (push/pull) does nothing; swipe
    // up refills. Tilting also cancels an in-progress pour (you tipped the
    // glass while the tap was running).
    const rollSeverity = Math.max(0, Math.abs(targetDir[0]) - 0.5) / 0.5;
    if (rollSeverity > 0) {
      fill = Math.max(0, fill - DRAIN_RATE * (0.4 + 0.6 * Math.min(rollSeverity, 1)) * dt);
      refilling = false;
    }
    if (refilling) {
      fill = Math.min(1, fill + FILL_RATE * dt);
      if (fill >= 0.999) refilling = false;
    }
    return { surface, amplitude, targetDir };
  }

  function uploadUniforms(state, t60) {
    gl.uniform2f(U.u_gravity, state.targetDir[0], state.targetDir[1]);
    gl.uniform2f(U.u_tilt, state.surface[0], state.surface[1]);
    gl.uniform1f(U.u_fill, fill);
    gl.uniform1f(U.u_clock, t60);
    gl.uniform1f(U.u_wobble, state.amplitude);
    gl.uniform2f(U.u_spriteSize, canvas.width, canvas.height);
    gl.uniform3f(U.u_bodyTop, style.bodyTop.r, style.bodyTop.g, style.bodyTop.b);
    gl.uniform3f(U.u_bodyDeep, style.bodyDeep.r, style.bodyDeep.g, style.bodyDeep.b);
    gl.uniform3f(U.u_glowColor, style.glowColor.r, style.glowColor.g, style.glowColor.b);
    gl.uniform1f(U.u_glowStrength, style.glowStrength);
    gl.uniform1f(U.u_translucency, style.translucency);
    gl.uniform3f(U.u_foamColor, style.foamColor.r, style.foamColor.g, style.foamColor.b);
    gl.uniform1f(U.u_foamThick, style.foamThick);
    gl.uniform1f(U.u_bubbleDensity, style.bubbleDensity);
    gl.uniform1f(U.u_bubbleSize, style.bubbleSize);
    gl.uniform1f(U.u_bubbleSpeed, style.bubbleSpeed);
    gl.uniform1f(U.u_rainbow, style.rainbow ? 1 : 0);
  }

  const t0 = performance.now();
  let last = t0;
  let lastTargetDir = manualDir;
  function frame(now) {
    const t = (now - t0) / 1000;
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;

    const state = advanceState(dt);
    lastTargetDir = state.targetDir;
    // 60 s wrap: all shader harmonics are integer cycles/minute → seamless.
    const t60 = t % 60;

    resize();
    uploadUniforms(state, t60);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  return {
    setStyleById(id) {
      const s = STYLES.find(x => x.id === id);
      if (s) {
        style = s;
        if (onStyleChange) onStyleChange(style);
      }
    },
    get state() {
      return { fill, style, sloshDir: slosh.dir, gravity: lastTargetDir, refilling };
    }
  };
}
