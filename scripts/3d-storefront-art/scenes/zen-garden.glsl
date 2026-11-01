// Zen garden: raked sand with rings around weathered basalt stones and a
// moss island, lit by a low morning sun so every groove casts a shadow.
#define MAX_T 30.
#define STEP_SCALE .55
#define EXPOSURE 1.05

const vec3 SUN = normalize(vec3(-.65, .42, -.45));
const vec3 R1 = vec3(1.05, 0., -.55); // stone centers (x, -, z) and radii
const vec3 R2 = vec3(-.55, 0., -1.15);
const vec3 R3 = vec3(2.35, 0., .55);
const vec3 M1 = vec3(-.2, 0., -.45);

float rakeHeight(vec2 xz) {
  float d1 = length((xz - R1.xz) * vec2(.85, 1.15)) - .62;
  float d2 = length(xz - R2.xz) - .34;
  float d3 = length(xz - R3.xz) - .26;
  float dm = length((xz - M1.xz) * vec2(1., 1.3)) - .55;
  float ring = smin(smin(d1, d2, .3), smin(d3, dm, .3), .3);
  float lines = .5 + .5 * cos(xz.y * 17.);
  float rings = .5 + .5 * cos(max(ring, 0.) * 17.);
  float w = smoothstep(.75, .55, ring);
  return .024 * mix(lines, rings, w) * smoothstep(-.02, .08, ring);
}
float sdStone(vec3 p, vec3 c, vec3 r, float seed) {
  vec3 q = p - c;
  q.xz *= rot(seed);
  float d = (length(q / r) - 1.) * min(r.x, min(r.y, r.z));
  return d + .05 * (fbm3(q * 2.3 + seed * 7.) - .5) * min(r.x, r.z) * 2.;
}
vec2 map(vec3 p) {
  vec2 res = vec2((p.y - (p.z < -2.35 ? .0 : rakeHeight(p.xz))) * .8, p.z < -2.2 ? 5. : 1.);
  float b = length(p - vec3(.9, 0., -.4)) - 2.3;
  if (b < 1.) {
    float stones = sdStone(p, R1 + vec3(0., .02, 0.), vec3(.62, .48, .52), .4);
    stones = min(stones, sdStone(p, R2, vec3(.34, .3, .3), 1.7));
    res = opU(res, vec2(stones, 2.));
    float moss = sdStone(p, M1 - vec3(0., .12, 0.), vec3(.6, .3, .5), 2.6);
    moss = smin(moss, sdStone(p, M1 + vec3(.3, .05, .1), vec3(.25, .22, .25), 4.1), .15);
    res = opU(res, vec2(moss - .012 * fbm3(p * 30.), 3.));
  } else {
    res = opU(res, vec2(b, 2.));
  }
  res = opU(res, vec2(sdStone(p, R3, vec3(.26, .22, .24), 3.2), 2.));
  // A dark timber edge frames the back of the garden.
  res = opU(res, vec2(sdRoundBox(p - vec3(0., .07, -2.35), vec3(9., .14, .16), .02), 4.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(.15, 4.5, 3.8);
  vec3 ta = vec3(.25, 0., -.45);
  vec3 f = normalize(ta - ro), r = normalize(cross(f, vec3(0, 1, 0))), u = cross(r, f);
  rd = normalize(ndc.x * r + ndc.y * u + 2.6 * f);
}
vec3 light(vec3 p, vec3 n, vec3 rd, vec3 albedo, float rough, float spec) {
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .004, SUN, .01, 6., 14.) : 0.;
  float ao = calcAO(p, n, .25);
  vec3 col = albedo * hex(0xfff0dc) * dif * sh * 2.3;
  col += albedo * hex(0xb9c3d9) * (.35 + .25 * n.y) * ao;
  col += hex(0xfff0dc) * ggx(n, -rd, SUN, rough) * spec * dif * sh;
  return col;
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  vec3 col;
  if (mat < 1.5) {
    float grain = hash13(floor(p * 260.));
    col = light(p, n, rd, hex(0xe5d6bb) * (.93 + .1 * grain), .9, .0);
  } else if (mat < 2.5) {
    float f = fbm3(p * 6.);
    col = light(p, n, rd, mix(hex(0x34363b), hex(0x55534f), f) * (.9 + .2 * hash13(floor(p * 90.))), .55, .25);
  } else if (mat < 3.5) {
    float f = fbm3(p * 14.);
    col = light(p, n, rd, mix(hex(0x3f5f2b), hex(0x7b9545), f), .95, 0.);
  } else if (mat > 4.5) {
    col = light(p, n, rd, mix(hex(0x3a3f35), hex(0x5c5f52), hash13(floor(p * 70.))), .9, 0.);
  } else {
    col = light(p, n, rd, hex(0x2b1f18) * (.85 + .3 * noise3(vec3(p.x * 30., p.y, p.z * 2.))), .5, .15);
  }
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(hex(0xe5d6bb), 1.); }
