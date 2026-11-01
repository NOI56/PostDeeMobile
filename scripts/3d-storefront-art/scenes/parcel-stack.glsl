// Parcel stack: kraft shipping boxes with paper tape and a blank label,
// in cool soft daylight. Transparent background.
#define MAX_T 30.
#define EXPOSURE 1.06

const vec3 SUN = normalize(vec3(.6, .9, .55));
const vec3 B1 = vec3(.66, .4, .5);   // half sizes
const vec3 B2 = vec3(.46, .28, .36);
const vec3 B3 = vec3(.3, .2, .24);
vec3 localOf(vec3 p, float mat) {
  vec3 q;
  if (mat < 1.5) { q = p - vec3(-.15, .4, 0.); q.xz *= rot(-.22); return q; }
  if (mat < 2.5) { q = p - vec3(-.05, 1.08, .05); q.xz *= rot(.32); return q; }
  q = p - vec3(1.12, .2, .7); q.xz *= rot(.75); return q;
}
float box(vec3 q, vec3 b) {
  float d = sdRoundBox(q, b, .025);
  // Flap seam: a shallow groove across the top along the box length.
  return max(d, -sdBox(q - vec3(0., b.y, 0.), vec3(b.x + .1, .006, .004)));
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 0.);
  res = opU(res, vec2(box(localOf(p, 1.), B1), 1.));
  res = opU(res, vec2(box(localOf(p, 2.), B2), 2.));
  res = opU(res, vec2(box(localOf(p, 3.), B3), 3.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(2.9, 2.7, 5.3);
  rd = lookAt(ndc, ro, vec3(.22, .58, .2), 5.1);
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 6., .5, hex(0x2c3b4f));
  vec3 q = localOf(p, mat);
  vec3 b = mat < 1.5 ? B1 : mat < 2.5 ? B2 : B3;
  vec3 ln = n; ln.xz *= rot(mat < 1.5 ? -.22 : mat < 2.5 ? .32 : .75);
  float fibers = fbm3(q * vec3(60., 9., 60.)) * .6 + .4 * hash13(floor(q * 400.));
  vec3 albedo = mix(hex(0xb88a57), hex(0xcfa271), fibers);
  albedo *= .94 + .1 * fbm3(q * 4.);
  float rough = .8, spec = .1;
  // Paper tape runs along x over the top and down both short ends.
  float tapeW = b.z * .3;
  bool onTape = abs(q.z) < tapeW && (ln.y > .5 || abs(ln.x) > .5) && q.y > b.y - (abs(ln.x) > .5 ? .22 : 1.);
  if (onTape) { albedo = mix(hex(0xd9bf93), hex(0xe4cda4), fibers); rough = .35; spec = .55; }
  // A blank shipping label on the big box: no printed text.
  if (mat < 1.5 && ln.z > .5) {
    vec2 lb = abs(q.xy - vec2(-.22, .02)) - vec2(.2, .13);
    if (max(lb.x, lb.y) < 0.) {
      albedo = hex(0xf6f4ef); rough = .6; spec = .2;
      if (q.y > .1) albedo = hex(0x3b78c4);
    }
  }
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 7.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xfff6ea) * dif * sh * 2.3;
  col += albedo * hex(0xbfd2ec) * (.3 + .25 * n.y) * ao;
  col += hex(0xffffff) * ggx(n, -rd, SUN, rough) * spec * dif * sh;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
