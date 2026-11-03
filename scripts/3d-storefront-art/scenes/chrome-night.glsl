// Night chrome: a twisted mirror column, molten metal and floating droplets
// in a navy studio with cool softboxes and one warm rim light.
#define MAX_T 30.
#define STEP_SCALE .75
#define EXPOSURE 1.1

float sdColumn(vec3 p) {
  vec3 q = p - vec3(1.0, 0., -.35);
  q.xz *= rot(q.y * .95 + .4);
  return sdRoundBox(q - vec3(0., .95, 0.), vec3(.3, .95, .3), .11);
}
float sdMolten(vec3 p) {
  vec3 c = p - vec3(-.55, 0., .35);
  float d = sdSphere(c - vec3(0., .52, 0.), .5);
  d = smin(d, sdSphere(c - vec3(.56, .3, .22), .3), .26);
  d = smin(d, sdSphere(c - vec3(-.52, .22, .12), .22), .24);
  d = smin(d, sdSphere(c - vec3(1.0, .16, .45), .16), .22);
  d = smin(d, sdSphere(c - vec3(-.9, .1, .35), .1), .18);
  return d;
}
float sdDrops(vec3 p) {
  float d = sdSphere(p - vec3(-1.75, 1.15, -.55), .16);
  d = smin(d, sdSphere(p - vec3(-1.75, 1.33, -.55), .07), .12);
  d = min(d, sdSphere(p - vec3(2.15, 1.4, -1.05), .13));
  d = min(d, sdSphere(p - vec3(.15, 1.55, -.9), .085));
  return d;
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 1.);
  res = opU(res, vec2(min(min(sdColumn(p), sdMolten(p)), sdDrops(p)), 2.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(0., 1.25, 5.6);
  vec3 ta = vec3(.15, .62, 0.);
  vec3 f = normalize(ta - ro), r = normalize(cross(f, vec3(0, 1, 0))), u = cross(r, f);
  rd = normalize(ndc.x * r + ndc.y * u + 3.1 * f);
}
vec3 env(vec3 rd) {
  vec3 col = mix(hex(0x080d1a), hex(0x1b2846), smoothstep(-.3, .7, rd.y));
  float az = atan(rd.x, rd.z);
  // Overhead softbox, a tall cool strip front-left and a warm rim back-right.
  col += vec3(1.7, 1.9, 2.3) * smoothstep(.62, .7, rd.y) * smoothstep(.75, .55, abs(rd.x));
  col += vec3(2.2, 2.5, 3.0) * smoothstep(.2, .12, abs(az + .85)) * smoothstep(-.15, .05, rd.y) * smoothstep(.75, .55, rd.y);
  col += vec3(2.4, 1.35, .6) * smoothstep(.16, .06, abs(az - 2.25)) * smoothstep(-.1, .1, rd.y) * smoothstep(.6, .4, rd.y);
  col += vec3(.35, .55, .9) * exp(-abs(rd.y) * 14.) * .6;
  return col;
}
vec3 backdrop(vec3 rd, vec2 ndc) {
  vec3 col = mix(hex(0x0a1122), hex(0x1a2642), smoothstep(-.2, .5, rd.y));
  col += hex(0x3b5a96) * .55 * exp(-dot(ndc - vec2(.55, .25), ndc - vec2(.55, .25)) * 1.1);
  return col * (1. - .25 * dot(ndc * vec2(.45, .8), ndc * vec2(.45, .8)));
}
vec3 floorBase(vec3 p) {
  vec2 s = p.xz - vec2(.35, -.1);
  float spot = exp(-dot(s, s) * .3);
  vec3 l = normalize(vec3(-.3, 1., .35));
  float sh = softShadow(p + vec3(0., .002, 0.), l, .02, 6., 9.);
  float ao = calcAO(p, vec3(0, 1, 0), .6);
  return hex(0x16213b) * (.18 + 1.25 * spot * (.35 + .65 * sh)) * (.35 + .65 * ao);
}
vec3 chromeSimple(vec3 n, vec3 rd) {
  vec3 r = reflect(rd, n);
  return env(r) * mix(vec3(.82, .86, .93), vec3(1.), fresnel(.75, n, -rd));
}
vec3 chromeFull(vec3 p, vec3 n, vec3 rd) {
  vec3 r = reflect(rd, n);
  float m; float t = march(p + n * .004, r, m);
  vec3 refl = env(r);
  if (t > 0.) {
    vec3 q = p + n * .004 + r * t;
    refl = m < 1.5 ? floorBase(q) * 1.4 : chromeSimple(calcNormal(q), r);
  }
  float ao = calcAO(p, n, .35);
  return refl * mix(vec3(.8, .85, .93), vec3(1.), fresnel(.75, n, -rd)) * (.55 + .45 * ao);
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat > 1.5) return vec4(chromeFull(p, n, rd), 1.);
  vec3 col = floorBase(p);
  vec3 r = reflect(rd, vec3(0, 1, 0));
  float m; float tr = march(p + vec3(0., .003, 0.), r, m);
  if (tr > 0.) {
    vec3 q = p + vec3(0., .003, 0.) + r * tr;
    col += chromeFull(q, calcNormal(q), r) * .3 * exp(-tr * .55);
  } else {
    col += env(r) * .05;
  }
  vec3 bg = backdrop(rd, gNdc);
  return vec4(mix(col, bg, smoothstep(6., 16., t)), 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(backdrop(rd, ndc), 1.); }
