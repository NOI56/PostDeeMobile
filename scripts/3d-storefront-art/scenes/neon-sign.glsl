// Neon night: glowing glass tubes (a ring, a zigzag and a spark) mounted on
// a dark brick wall above a wet floor that mirrors their light.
#define MAX_T 30.
#define HAS_GLOW
#define EXPOSURE 1.

const vec3 PINK = vec3(1., .16, .62);
const vec3 CYAN = vec3(.1, .85, 1.);
const vec3 LILAC = vec3(.72, .5, 1.);
float sdRing(vec3 p) { vec3 q = p - vec3(.95, .2, .22); return sdTorus(q.xzy, vec2(.7, .034)); }
float sdZig(vec3 p) {
  vec3 q = p - vec3(-1.25, -.15, .22);
  float d = 1e5;
  for (int i = uZero; i < 5; i++) {
    float x0 = float(i) * .3, x1 = x0 + .3;
    vec3 a = vec3(x0, i % 2 == 0 ? -.2 : .2, 0.), b = vec3(x1, i % 2 == 0 ? .2 : -.2, 0.);
    d = min(d, sdCapsule(q, a, b, .03));
  }
  return d;
}
float sdSpark(vec3 p) {
  vec3 q = p - vec3(2.25, .62, .22);
  float d = sdCapsule(q, vec3(-.17, 0., 0.), vec3(.17, 0., 0.), .026);
  return min(d, sdCapsule(q, vec3(0., -.17, 0.), vec3(0., .17, 0.), .026));
}
float brickMortar(vec3 p) {
  vec2 uv = p.xy * vec2(3.2, 7.);
  uv.x += step(1., mod(floor(uv.y), 2.)) * .5;
  vec2 f = abs(fract(uv) - .5);
  return smoothstep(.43, .48, max(f.x * 1., f.y * 1.));
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.z + .012 * brickMortar(p) * step(-1.05, p.y), 1.); // wall
  res = opU(res, vec2(p.y + 1.1, 2.));  // floor
  res = opU(res, vec2(sdRing(p), 3.));
  res = opU(res, vec2(sdZig(p), 4.));
  res = opU(res, vec2(sdSpark(p), 5.));
  return res;
}
void glowAccum(vec3 p, float dt) {
  dt = clamp(dt, .005, .15);
  gGlow += PINK * exp(-sdRing(p) * 11.) * dt * 1.5;
  gGlow += CYAN * exp(-sdZig(p) * 11.) * dt * 1.5;
  gGlow += LILAC * exp(-sdSpark(p) * 11.) * dt * 1.4;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(.3, -.62, 5.);
  rd = lookAt(ndc, ro, vec3(.3, -.28, 0.), 2.7);
}
vec3 neonLight(vec3 p, vec3 n) {
  vec3 col = vec3(0.);
  float d;
  d = sdRing(p);  col += PINK * 1.6 / (1. + d * d * 22.) * (.4 + .6 * max(dot(n, normalize(vec3(.95, .2, .22) - p)), 0.));
  d = sdZig(p);   col += CYAN * 1.3 / (1. + d * d * 26.) * (.4 + .6 * max(dot(n, normalize(vec3(-.65, -.15, .22) - p)), 0.));
  d = sdSpark(p); col += LILAC * .7 / (1. + d * d * 40.);
  return col;
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat > 2.5) {
    vec3 c = mat < 3.5 ? PINK : mat < 4.5 ? CYAN : LILAC;
    return vec4(c * 3.5 + vec3(1.2) * pow(max(dot(n, -rd), 0.), 3.) + gGlow, 1.);
  }
  vec3 glow = gGlow;
  if (mat < 1.5) {
    float m = brickMortar(p);
    vec2 cell = floor(p.xy * vec2(3.2, 7.) + vec2(step(1., mod(floor(p.y * 7.), 2.)) * .5, 0.));
    vec3 brick = mix(hex(0x231a2b), hex(0x2f2236), hash13(vec3(cell, 3.))) * (.85 + .3 * noise3(p * 40.));
    vec3 albedo = mix(brick, hex(0x141018), m);
    vec3 col = albedo * (neonLight(p, n) * 4.2 + hex(0x3a3260) * .9);
    return vec4(col + glow, 1.);
  }
  // Polished dark floor: a faint, fading mirror of the tubes.
  vec3 r = reflect(rd, vec3(0, 1, 0));
  float mm; vec3 ro2 = p + vec3(0., .002, 0.);
  gGlow = vec3(0.);
  float tr = march(ro2, r, mm);
  vec3 refl = gGlow;
  if (tr > 0.) {
    vec3 q = ro2 + r * tr;
    if (mm > 2.5) refl += (mm < 3.5 ? PINK : mm < 4.5 ? CYAN : LILAC) * 2.5;
    else refl += hex(0x231a2b) * neonLight(q, vec3(0, 0, 1)) * 1.2;
  }
  vec3 col = hex(0x1a1422) * (neonLight(p, vec3(0, 1, 0)) * 2.5 + .25) + refl * .2 * exp(-max(tr, 0.) * .6);
  return vec4(col + glow, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(hex(0x0d0a12) + gGlow, 1.); }
