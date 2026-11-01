// Raw concrete: brutalist cast slabs with formwork tie holes, a cantilever,
// a three-step stair and one signal-orange ball under hard sun. Transparent.
#define MAX_T 30.
#define EXPOSURE .92

const vec3 SUN = normalize(vec3(-.62, .78, .5));
const int N = 6;
// Center (xyz) and half size (xyz) of each cast block.
const vec3 C[6] = vec3[6](vec3(.1, .18, 0.), vec3(-.45, .62, -.05), vec3(.75, 1.14, -.1), vec3(-1.62, .12, .3), vec3(-1.62, .36, -.02), vec3(-1.62, .6, -.34));
const vec3 S[6] = vec3[6](vec3(1.25, .18, .62), vec3(.98, .26, .5), vec3(.3, .26, .3), vec3(.36, .12, .32), vec3(.36, .12, .32), vec3(.36, .12, .32));
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 0.);
  for (int i = uZero; i < N; i++) res = opU(res, vec2(sdRoundBox(p - C[i], S[i], .012), 1. + float(i)));
  res = opU(res, vec2(sdSphere(p - vec3(1.0, .36 + .21, .32), .21), 9.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(3.1, 2.3, 5.4);
  rd = lookAt(ndc, ro, vec3(-.25, .52, 0.), 5.5);
}
// Tie holes sit on a 0.36 grid on each cast face, inset from the edges.
float tieHoles(vec3 q, vec3 n, vec3 s) {
  vec2 uv = abs(n.x) > .5 ? q.zy : abs(n.z) > .5 ? q.xy : q.xz;
  vec2 half_ = abs(n.x) > .5 ? s.zy : abs(n.z) > .5 ? s.xy : s.xz;
  vec2 cell = (uv + half_) / .36;
  vec2 f = fract(cell) - .5;
  bool inside = all(lessThan(abs(uv), half_ - .1));
  return inside ? smoothstep(.075, .055, length(f)) : 0.;
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 28., .6, hex(0x24211d));
  vec3 albedo; float rough = .85, spec = .08;
  if (mat > 8.5) { albedo = hex(0xff5a1f); rough = .3; spec = .5; }
  else {
    int i = int(mat - .5);
    vec3 q = p - C[i];
    float blot = fbm3(p * 2.2);
    albedo = mix(hex(0x7f7b74), hex(0xa29d94), blot) * (.9 + .14 * hash13(floor(p * 300.)));
    albedo *= 1. - .12 * smoothstep(.7, .9, fbm3(p * 9.)); // pores and pour marks
    albedo = mix(albedo, hex(0x4a4743), tieHoles(q, n, S[i]) * .9);
  }
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 28.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xfff4e6) * dif * sh * 2.4;
  col += albedo * hex(0xbfcadb) * (.38 + .22 * n.y) * ao;
  col += hex(0xffffff) * ggx(n, -rd, SUN, rough) * spec * dif * sh;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
