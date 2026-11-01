// Terrazzo steps: polished terrazzo stair and plinth with colored stone chips,
// a terracotta ball and an olive glazed dome in warm low sun. Transparent.
#define MAX_T 30.
#define EXPOSURE 1.04

const vec3 SUN = normalize(vec3(.75, .75, .35));
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 0.);
  float stair = sdRoundBox(p - vec3(-.55, .14, 0.), vec3(.9, .14, .62), .03);
  stair = min(stair, sdRoundBox(p - vec3(-.75, .42, -.12), vec3(.7, .14, .5), .03));
  stair = min(stair, sdRoundBox(p - vec3(-.95, .7, -.24), vec3(.5, .14, .38), .03));
  res = opU(res, vec2(stair, 1.));
  res = opU(res, vec2(sdRoundCyl(p - vec3(1.05, .55, -.25), .4, .55, .04), 1.));
  res = opU(res, vec2(sdSphere(p - vec3(1.05, 1.1 + .26, -.25), .26), 2.));
  res = opU(res, vec2(max(sdSphere(p - vec3(.55, 0., .8), .3), -p.y), 3.));
  res = opU(res, vec2(sdSphere(p - vec3(-.2, .56 + .14, .2), .14), 4.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(-2.2, 2.35, 5.6);
  rd = lookAt(ndc, ro, vec3(.0, .62, 0.), 5.6);
}
vec3 terrazzo(vec3 p) {
  vec3 base = mix(hex(0xeee4d4), hex(0xf6efe3), noise3(p * 3.));
  vec2 v = voronoi3(p * 9.);
  if (v.x < .22) {
    float id = v.y;
    base = id < .28 ? hex(0xc4613a) : id < .48 ? hex(0x7d8a47) : id < .6 ? hex(0x3b3531) : id < .78 ? hex(0xe2ae98) : hex(0xd9cbb5);
  }
  vec2 s = voronoi3(p * 26. + 4.);
  if (s.x < .19) base = s.y < .35 ? hex(0xc4613a) : s.y < .6 ? hex(0x3b3531) : hex(0xfdfaf4);
  return base;
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 9., .32, hex(0x5a3322));
  vec3 albedo; float rough = .3, spec = .45;
  if (mat < 1.5) albedo = terrazzo(p);
  else if (mat < 2.5) { albedo = hex(0xc4613a) * (.92 + .1 * fbm3(p * 20.)); rough = .75; spec = .1; }
  else if (mat < 3.5) { albedo = hex(0x6f7d3c); rough = .15; spec = .8; }
  else { albedo = hex(0xe9b79f); rough = .6; spec = .2; }
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 10.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xffe6c8) * dif * sh * 2.1;
  col += albedo * hex(0xd8cfe0) * (.42 + .22 * n.y) * ao;
  col += hex(0xfff2e0) * ggx(n, -rd, SUN, rough) * spec * dif * sh;
  col += mix(hex(0xf2e2cf), vec3(1.), .3) * fresnel(.04, n, -rd) * .2 * ao;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
