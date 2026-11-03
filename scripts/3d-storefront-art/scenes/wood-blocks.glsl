// Wooden toy blocks: a hand-stacked tower of maple and painted blocks with
// visible grain, in warm afternoon sun. Transparent background.
#define MAX_T 30.
#define EXPOSURE 1.08

const vec3 SUN = normalize(vec3(-.5, 1.15, .5));
#define STEP_SCALE .85
#define SIMPLE_SHADOW
// Block placements share one table so shading can rebuild local coordinates.
vec3 localOf(vec3 p, float mat) {
  if (mat < 1.5) return p - vec3(0., .26, 0.);
  if (mat < 2.5) return p - vec3(-.46, .78, .02);
  if (mat < 3.5) return p - vec3(.48, .78, 0.);
  if (mat < 4.5) return p - vec3(0., 1.12, 0.);
  if (mat < 5.5) return p - vec3(.05, 1.47, 0.);
  if (mat < 6.5) { vec3 q = p - vec3(-1.25, .2, .75); q.xz *= rot(.45); return q; }
  return p - vec3(1.3, .2, .8);
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y, 0.);
  res = opU(res, vec2(sdRoundBox(localOf(p, 1.), vec3(.92, .26, .36), .03), 1.));
  res = opU(res, vec2(sdRoundBox(localOf(p, 2.), vec3(.26, .26, .26), .025), 2.));
  res = opU(res, vec2(sdRoundCyl(localOf(p, 3.), .27, .26, .025), 3.));
  res = opU(res, vec2(sdRoundBox(localOf(p, 4.), vec3(.86, .08, .3), .02), 4.));
  vec3 tq = localOf(p, 5.); tq.y += .02;
  res = opU(res, vec2(sdTriPrism(tq, vec2(.52, .26)) - .02, 5.));
  res = opU(res, vec2(sdRoundBox(localOf(p, 6.), vec3(.2, .2, .2), .02), 6.));
  res = opU(res, vec2(sdSphere(localOf(p, 7.), .2), 7.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  ro = vec3(3.4, 2.9, 5.6);
  rd = lookAt(ndc, ro, vec3(-.05, .72, .25), 4.4);
}
// Grain runs along the block's long axis; rings bend with low-frequency noise.
float grain(vec3 q, int axis) {
  vec2 c = axis == 0 ? q.yz : axis == 1 ? q.xz : q.xy;
  float along = axis == 0 ? q.x : axis == 1 ? q.y : q.z;
  float r = length(c + vec2(.9, -.7)) * 26. + 2.2 * noise3(vec3(along * 1.4, c * 3.));
  return smoothstep(.15, .85, abs(fract(r) - .5) * 2.) * .7 + .3 * noise3(vec3(along * 40., c * 4.));
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 7., .55, hex(0x4a3420));
  vec3 q = localOf(p, mat);
  int axis = mat < 1.5 || mat > 3.5 && mat < 4.5 ? 0 : mat > 2.5 && mat < 3.5 ? 1 : 2;
  float g = grain(q, axis);
  vec3 maple = mix(hex(0xd9ab72), hex(0xf0cf9c), g);
  vec3 albedo = maple; float rough = .55; float spec = .25;
  if (mat > 1.5 && mat < 2.5) { albedo = mix(hex(0xc8432b), hex(0xd8533a), g); rough = .4; spec = .45; }
  if (mat > 2.5 && mat < 3.5) { albedo = mix(hex(0x1f8a86), hex(0x2a9b96), g); rough = .4; spec = .45; }
  if (mat > 4.5 && mat < 5.5) { albedo = mix(hex(0xe2a52a), hex(0xf0b73b), g); rough = .4; spec = .45; }
  if (mat > 5.5 && mat < 6.5) { albedo = mix(hex(0x1f8a86), hex(0x2a9b96), g); rough = .4; spec = .45; }
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 9.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xfff0dc) * dif * sh * 2.2;
  col += albedo * hex(0xc9d6ea) * (.42 + .22 * n.y) * ao;
  col += albedo * hex(0xffd7a8) * max(-n.y, 0.) * .2 * ao;
  col += hex(0xfff3e2) * ggx(n, -rd, SUN, rough) * spec * dif * sh;
  col += hex(0xdfe8f5) * fresnel(.03, n, -rd) * .25 * ao;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
