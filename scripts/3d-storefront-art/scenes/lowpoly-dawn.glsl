// Low-poly dawn: faceted mountains and pines above a still lake, backlit by
// a low sun in a peach-to-lilac sky. Facets come from polygonal pyramids.
#define MAX_T 90.
// Max-of-face-planes is a true lower bound, so no step scaling is needed.
#define STEP_SCALE 1.
#define STEPS 360
#define EXPOSURE 1.05

const vec3 SUN = normalize(vec3(.42, .16, -1.));
const vec3 KEY = normalize(vec3(.8, .5, .15));
// Polygonal pyramid with n sides: flat faces give the low-poly look.
float sdPeak(vec3 p, vec3 c, float h, float r, float n, float a) {
  vec3 q = p - c; q.xz *= rot(a);
  // The farthest face plane is a continuous lower bound for a convex pyramid.
  float pd = -1e5;
  for (int i = uZero; i < int(n); i++) {
    float k = float(i) * 2. * PI / n;
    pd = max(pd, dot(q.xz, vec2(cos(k), sin(k))));
  }
  float side = (pd * h / r + q.y - h) / sqrt(1. + h * h / (r * r));
  return max(side, -q.y);
}
float sdPine(vec3 p, vec3 c, float s) {
  float d = sdPeak(p, c + vec3(0., .25 * s, 0.), 1.1 * s, .55 * s, 6., .3);
  d = min(d, sdPeak(p, c + vec3(0., .85 * s, 0.), .95 * s, .42 * s, 6., .9));
  d = min(d, sdPeak(p, c + vec3(0., 1.35 * s, 0.), .75 * s, .3 * s, 6., .1));
  return min(d, sdCyl(p - c - vec3(0., .14 * s, 0.), .14 * s, .07 * s));
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y + .02, 1.); // lake
  // Plane bounds skip whole groups far from the sample point.
  float far = p.z + 25.;
  if (far < .5) {
    far = sdPeak(p, vec3(-9., -.5, -40.), 13., 13., 5., .2);
    far = min(far, sdPeak(p, vec3(7., -.5, -46.), 16., 15., 6., .7));
    far = min(far, sdPeak(p, vec3(22., -.5, -44.), 11., 12., 5., 1.1));
    far = min(far, sdPeak(p, vec3(-24., -.5, -42.), 12., 13., 6., .5));
  }
  res = opU(res, vec2(far, 2.));
  float mid = p.z + 13.;
  if (mid < .5) {
    mid = sdPeak(p, vec3(-4.5, -.3, -22.), 6.5, 7., 5., 1.3);
    mid = min(mid, sdPeak(p, vec3(4., -.3, -25.), 8., 8.5, 6., .4));
    mid = min(mid, sdPeak(p, vec3(12., -.3, -21.), 5.5, 6.5, 5., .8));
    mid = min(mid, sdPeak(p, vec3(-13., -.3, -24.), 7., 7., 5., .1));
  }
  res = opU(res, vec2(mid, 3.));
  float near = 3.2 - abs(p.x);
  if (near < 2.) {
    float shore = sdPeak(p, vec3(-8.2, -.2, -6.), 1.3, 4.6, 5., .5);
    shore = min(shore, sdPeak(p, vec3(8.6, -.2, -7.), 1.6, 5.2, 6., .2));
    res = opU(res, vec2(shore, 4.));
    float pines = sdPine(p, vec3(-6.4, .6, -6.2), 1.25);
    pines = min(pines, sdPine(p, vec3(-7.6, .35, -4.4), .9));
    pines = min(pines, sdPine(p, vec3(-5.1, .2, -4.9), .7));
    pines = min(pines, sdPine(p, vec3(7.2, .7, -7.2), 1.4));
    pines = min(pines, sdPine(p, vec3(8.9, .45, -5.2), 1.));
    pines = min(pines, sdPine(p, vec3(6., .1, -4.8), .65));
    res = opU(res, vec2(pines, 5.));
  } else {
    res = opU(res, vec2(near, 4.));
  }
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(0., 1.35, 6.);
  vec3 ta = vec3(0., 2.1, -10.);
  vec3 f = normalize(ta - ro), r = normalize(cross(f, vec3(0, 1, 0))), u = cross(r, f);
  rd = normalize(ndc.x * r + ndc.y * u + 2.35 * f);
}
vec3 sky(vec3 rd) {
  float y = rd.y;
  vec3 col = mix(hex(0xffc39a), hex(0xf2bccb), smoothstep(.0, .12, y));
  col = mix(col, hex(0x9fb2e2), smoothstep(.1, .5, y));
  float s = max(dot(rd, SUN), 0.);
  col += hex(0xfff0d8) * (pow(s, 900.) * 6. + pow(s, 40.) * .35);
  col += hex(0xffb38a) * pow(s, 6.) * .25;
  return col;
}
// Distant peaks are lit by facet angle only; cast shadows there only add
// stair-step noise at grazing angles. Only the pines keep cast shadows.
vec3 facet(vec3 p, vec3 n, vec3 base, float t, bool shadows) {
  float dif = max(dot(n, KEY), 0.);
  float sh = dif > 0. && shadows ? softShadow(p + n * .06, KEY, .25, 30., 16.) : 1.;
  base *= .88 + .24 * hash13(floor(n * 40.) + 3.); // each flat face keeps one tone
  vec3 col = base * (hex(0x9aa6dc) * (.22 + .2 * n.y) + hex(0xffd0a6) * dif * sh * 2.6);
  col += base * hex(0xff9d7a) * pow(max(dot(n, SUN), 0.), 2.) * .5;
  float fog = 1. - exp(-t * .013);
  return mix(col, hex(0xf3c6c0), fog * .65);
}
vec3 landColor(vec3 p, vec3 n, float mat, float t) {
  if (mat < 2.5) return facet(p, n, hex(0x9a8fd0), t, false);
  if (mat < 3.5) return facet(p, n, hex(0x4a55a6), t, false);
  if (mat < 4.5) return facet(p, n, hex(0x3c8a7c), t, false);
  return facet(p, n, hex(0x22574e), t, true);
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat > 1.5) return vec4(landColor(p, n, mat, t), 1.);
  // Still lake with faint facet ripples; reflections dim toward the camera.
  vec3 wn = normalize(vec3(0., 1., .007 * sin(floor(p.z * .9) * 2.3)));
  vec3 r = reflect(rd, wn);
  float m; float tr = march(p + vec3(0., .01, 0.), r, m);
  vec3 refl = tr > 0. ? landColor(p + r * tr, calcNormal(p + r * tr), m, t + tr) : sky(r);
  float fr = fresnel(.04, wn, -rd);
  vec3 col = mix(hex(0x34507a) * .5, refl, .6 + .4 * fr);
  return vec4(mix(col, hex(0xf5c8bd), (1. - exp(-t * .012)) * .6), 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(sky(rd), 1.); }
