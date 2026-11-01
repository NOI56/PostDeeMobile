#version 300 es
// Shared ray-marching helpers. The studio inserts one scene file at the
// SCENE marker below; the scene defines map(), cameraRay(), shadeHit() and
// shadeMiss(). Everything is procedural: no textures or third-party assets.
precision highp float;
precision highp int;
uniform vec2 uRes;
uniform int uSS;
// Always 0. Loop bounds read it so ANGLE cannot unroll or duplicate map().
uniform int uZero;
out vec4 outColor;
// The studio hoists the scene's #define lines here so shared helpers see them.
//@@DEFINES@@

#define PI 3.14159265359
vec2 map(vec3 p);
float march(vec3 ro, vec3 rd, out float mat);
vec3 calcNormal(vec3 p);
vec3 gGlow = vec3(0.);
vec2 gNdc = vec2(0.);

float sdSphere(vec3 p, float r) { return length(p) - r; }
float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.)) + min(max(q.x, max(q.y, q.z)), 0.); }
float sdRoundBox(vec3 p, vec3 b, float r) { return sdBox(p, b - r) - r; }
float sdTorus(vec3 p, vec2 t) { vec2 q = vec2(length(p.xz) - t.x, p.y); return length(q) - t.y; }
float sdCyl(vec3 p, float h, float r) { vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h); return min(max(d.x, d.y), 0.) + length(max(d, 0.)); }
float sdRoundCyl(vec3 p, float r, float h, float rb) { vec2 d = vec2(length(p.xz) - r + rb, abs(p.y) - h + rb); return min(max(d.x, d.y), 0.) + length(max(d, 0.)) - rb; }
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) { vec3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0., 1.); return length(pa - ba * h) - r; }
float sdCappedCone(vec3 p, float h, float r1, float r2) {
  vec2 q = vec2(length(p.xz), p.y); vec2 k1 = vec2(r2, h); vec2 k2 = vec2(r2 - r1, 2. * h);
  vec2 ca = vec2(q.x - min(q.x, (q.y < 0.) ? r1 : r2), abs(q.y) - h);
  vec2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0., 1.);
  float s = (cb.x < 0. && ca.y < 0.) ? -1. : 1.;
  return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
float sdTriPrism(vec3 p, vec2 h) { vec3 q = abs(p); return max(q.z - h.y, max(q.x * .866025 + p.y * .5, -p.y) - h.x * .5); }
float smin(float a, float b, float k) { float h = clamp(.5 + .5 * (b - a) / k, 0., 1.); return mix(b, a, h) - k * h * (1. - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
vec2 opU(vec2 a, vec2 b) { return a.x < b.x ? a : b; }

float hash13(vec3 p) { p = fract(p * .1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
vec3 hash33(vec3 p) { p = fract(p * vec3(.1031, .1030, .0973)); p += dot(p, p.yxz + 33.33); return fract((p.xxy + p.yxx) * p.zyx); }
float noise3(vec3 p) {
  vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3. - 2. * f);
  return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) { float a = .5, s = 0.; for (int i = 0; i < 5; i++) { s += a * noise3(p); p = p * 2.03 + 1.7; a *= .5; } return s; }
// Returns distance to the nearest cell point (x) and that cell's random id (y).
vec2 voronoi3(vec3 p) {
  vec3 i = floor(p); vec3 f = fract(p); float best = 8.; float id = 0.;
  for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec3 g = vec3(x, y, z); vec3 o = hash33(i + g); vec3 r = g + o - f; float d = dot(r, r);
    if (d < best) { best = d; id = hash13(i + g + 7.1); }
  }
  return vec2(sqrt(best), id);
}

float softShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
  float res = 1., t = tmin, ph = 1e10;
#ifdef SIMPLE_SHADOW
  const int steps = 128;
#else
  const int steps = 96;
#endif
  for (int i = uZero; i < steps; i++) {
    float h = map(ro + rd * t).x;
#ifdef SIMPLE_SHADOW
    // Classic penumbra estimate; steadier when a scene has inexact distances.
    res = min(res, k * h / t); t += clamp(h, .02, .15);
#else
    float y = h * h / (2. * ph); float d = sqrt(max(h * h - y * y, 0.));
    res = min(res, k * d / max(0., t - y)); ph = h; t += clamp(h, .01, .25);
#endif
    if (res < .002 || t > tmax) break;
  }
  res = clamp(res, 0., 1.);
  return res * res * (3. - 2. * res);
}
float calcAO(vec3 p, vec3 n, float scale) {
  float occ = 0., w = 1.;
  for (int i = 1 + uZero; i <= 5; i++) { float h = scale * float(i) / 5.; occ += (h - map(p + n * h).x) * w; w *= .7; }
  return clamp(1. - 1.6 * occ / scale, 0., 1.);
}
float ggx(vec3 n, vec3 v, vec3 l, float rough) {
  vec3 h = normalize(v + l); float a = rough * rough; float a2 = a * a;
  float nh = max(dot(n, h), 0.); float d = nh * nh * (a2 - 1.) + 1.;
  float nl = max(dot(n, l), 0.), nv = max(dot(n, v), 1e-3);
  float k = a * .5; float g = nl / (nl * (1. - k) + k) * nv / (nv * (1. - k) + k);
  return a2 / (PI * d * d) * g / (4. * nv + 1e-4);
}
float fresnel(float f0, vec3 n, vec3 v) { return f0 + (1. - f0) * pow(1. - max(dot(n, v), 0.), 5.); }
vec3 aces(vec3 x) { return clamp((x * (2.51 * x + .03)) / (x * (2.43 * x + .59) + .14), 0., 1.); }
vec3 srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1. / 2.4)) - .055, step(.0031308, c)); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
vec3 hex(int h) { return lin(vec3(float((h >> 16) & 255), float((h >> 8) & 255), float(h & 255)) / 255.); }

// Shadow catcher for transparent artwork: only shadow and contact occlusion
// remain, so the page background shows through everywhere else.
vec4 catcher(vec3 p, vec3 l, float k, float strength, vec3 tint) {
  float sh = softShadow(p + vec3(0., .002, 0.), l, .02, 10., k);
  float ao = calcAO(p, vec3(0, 1, 0), .4);
  return vec4(tint, clamp((1. - sh) * strength + (1. - ao) * .55, 0., 1.));
}
vec3 lookAt(vec2 ndc, vec3 ro, vec3 ta, float zoom) {
  vec3 f = normalize(ta - ro), r = normalize(cross(f, vec3(0, 1, 0))), u = cross(r, f);
  return normalize(ndc.x * r + ndc.y * u + zoom * f);
}

//@@SCENE@@

#ifndef STEPS
#define STEPS 220
#endif
#ifndef MAX_T
#define MAX_T 40.
#endif
#ifndef STEP_SCALE
#define STEP_SCALE 1.
#endif
#ifndef EXPOSURE
#define EXPOSURE 1.
#endif

float march(vec3 ro, vec3 rd, out float mat) {
  float t = 0.; mat = -1.;
  for (int i = uZero; i < STEPS; i++) {
    vec3 p = ro + rd * t; vec2 h = map(p);
#ifdef HAS_GLOW
    glowAccum(p, h.x * STEP_SCALE);
#endif
    if (abs(h.x) < .0004 * t + .0002) { mat = h.y; return t; }
    t += h.x * STEP_SCALE;
    if (t > MAX_T) break;
  }
  return -1.;
}
vec3 calcNormal(vec3 p) {
  vec3 n = vec3(0.);
  for (int i = uZero; i < 4; i++) {
    vec3 e = .5773 * (2. * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.);
    n += e * map(p + .0007 * e).x;
  }
  return normalize(n);
}
vec4 renderSample(vec2 ndc) {
  vec3 ro, rd; cameraRay(ndc, ro, rd);
  gGlow = vec3(0.); gNdc = ndc;
  float mat; float t = march(ro, rd, mat);
  if (t < 0.) return shadeMiss(ro, rd, ndc);
  vec3 p = ro + rd * t;
  return shadeHit(p, calcNormal(p), rd, mat, t);
}
void main() {
  vec4 acc = vec4(0.);
  for (int j = 0; j < uSS; j++) for (int i = 0; i < uSS; i++) {
    vec2 px = gl_FragCoord.xy - .5 + (vec2(float(i), float(j)) + .5) / float(uSS);
    vec4 c = renderSample((2. * px - uRes) / uRes.y);
    vec3 m = srgb(aces(max(c.rgb, 0.) * EXPOSURE));
    acc += vec4(m * c.a, c.a);
  }
  acc /= float(uSS * uSS);
  outColor = acc.a > 1e-4 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.);
}
