// Pop shapes: glossy toy-plastic primitives in candy colors: a squiggle,
// a cone, a flat ring, a balanced cube and a checker ball. Transparent.
#define MAX_T 30.
#define EXPOSURE 1.04

const vec3 SUN = normalize(vec3(-.5, .95, .55));
float sdSquiggle(vec3 p) {
  vec3 q = p - vec3(-1.75, 0., -.15);
  float d = 1e5;
  vec3 a = vec3(0., .14, 0.);
  for (int i = 1 + uZero; i <= 9; i++) {
    float y = .14 + float(i) * .155;
    vec3 b = vec3(.2 * sin(float(i) * 1.75), y, .0);
    d = smin(d, sdCapsule(q, a, b, .11), .05);
    a = b;
  }
  return d;
}
vec3 cubeLocal(vec3 p) {
  vec3 q = p - vec3(1.0, .465, -.55);
  q.xz *= rot(.5);
  q.xy *= rot(.6155); // stand the cube on one corner
  q.yz *= rot(.7854);
  return q;
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 0.);
  res = opU(res, vec2(sdSquiggle(p), 1.));
  res = opU(res, vec2(sdCappedCone(p - vec3(-.55, .55, -.75), .55, .5, .015) - .02, 2.));
  res = opU(res, vec2(sdTorus(p - vec3(.15, .14, .55), vec2(.42, .14)), 3.));
  res = opU(res, vec2(sdRoundBox(cubeLocal(p), vec3(.28), .03), 4.));
  res = opU(res, vec2(sdSphere(p - vec3(1.75, .3, .45), .3), 5.));
  res = opU(res, vec2(sdSphere(p - vec3(-.95, .12, .75), .12), 6.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(.6, 3.1, 6.2);
  rd = lookAt(ndc, ro, vec3(.05, .42, 0.), 4.6);
}
vec3 env(vec3 r) {
  vec3 col = mix(hex(0xf3e9f1), hex(0xffffff), smoothstep(-.2, .6, r.y));
  col += vec3(2.2) * smoothstep(.9, .94, dot(r, normalize(vec3(-.45, .8, .4))));
  col += vec3(1.2) * smoothstep(.96, .98, dot(r, normalize(vec3(.8, .4, .3))));
  return col;
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 10., .45, hex(0x5a2340));
  vec3 albedo;
  if (mat < 1.5) albedo = hex(0xff5c9a);
  else if (mat < 2.5) albedo = hex(0xffcc1f);
  else if (mat < 3.5) albedo = hex(0x5fd3b3);
  else if (mat < 4.5) albedo = hex(0xa98cff);
  else if (mat < 5.5) {
    vec3 q = p - vec3(1.75, .3, .45);
    vec2 sph = vec2(atan(q.z, q.x), acos(clamp(q.y / .3, -1., 1.)));
    float c = step(0., sin(sph.x * 4.) * sin(sph.y * 4.));
    albedo = mix(hex(0x1d1b22), hex(0xf7f5f2), c);
  } else albedo = hex(0xff5c9a);
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 12.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xfffaf5) * dif * sh * 1.7;
  col += albedo * hex(0xf3dceb) * (.5 + .3 * n.y) * ao;
  col += hex(0xffffff) * ggx(n, -rd, SUN, .14) * dif * sh * .8;
  col += env(reflect(rd, n)) * fresnel(.045, n, -rd) * .6 * ao;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
