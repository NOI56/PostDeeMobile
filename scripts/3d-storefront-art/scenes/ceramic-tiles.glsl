// Glazed tiles: thick hand-glazed ceramic tiles stepping up in an isometric
// mosaic, cobalt and white with a lemon glaze ball. Transparent background.
#define MAX_T 40.
#define EXPOSURE 1.05

const vec3 SUN = normalize(vec3(-.45, .9, .3));
// Tile grid: xz cell, top height, glaze kind (0 cobalt, 1 white motif, 2 lemon).
const int N = 7;
const vec4 TILES[7] = vec4[7](
  vec4(-1., -1., .55, 1.), vec4(0., -1., .8, 0.), vec4(1., -1., .35, 1.),
  vec4(-1., 0., .25, 0.), vec4(0., 0., .5, 1.), vec4(1., 0., .7, 2.),
  vec4(0., 1., .15, 0.));
float sdTile(vec3 p, vec4 t) {
  vec3 c = vec3(t.x * 1.08, t.z - .13, t.y * 1.08);
  return sdRoundBox(p - c, vec3(.5, .13, .5), .06);
}
vec2 map(vec3 p) {
  vec2 res = vec2(p.y + .55, 0.);
  for (int i = uZero; i < N; i++) res = opU(res, vec2(sdTile(p, TILES[i]), 1. + float(i)));
  res = opU(res, vec2(sdSphere(p - vec3(.02, .8 + .26, -1.08), .26), 10.));
  res = opU(res, vec2(sdSphere(p - vec3(-1.12, .25 + .17, .1), .17), 11.));
  return res;
}
void cameraRay(vec2 ndc, out vec3 ro, out vec3 rd) {
  // Orthographic, true isometric-style view.
  vec3 f = normalize(vec3(-1., -.95, -1.15));
  vec3 r = normalize(cross(f, vec3(0, 1, 0))), u = cross(r, f);
  ro = vec3(.1, .2, 0.) - f * 12. + (ndc.x * r + ndc.y * u) * 1.56;
  rd = f;
}
vec3 env(vec3 r) {
  vec3 col = mix(hex(0xdfe6f2), hex(0xf7f9fc), smoothstep(-.2, .6, r.y));
  col += vec3(2.4) * smoothstep(.85, .9, dot(r, normalize(vec3(-.4, .8, .5)))); // window
  return col;
}
float motif(vec2 uv) {
  // Four quarter-circle arcs meet in the middle of each white tile.
  vec2 q = abs(uv);
  float arc = abs(length(q - vec2(.5)) - .32);
  float dot0 = length(uv) - .08;
  return min(smoothstep(.035, .02, arc), 1.) + smoothstep(.02, .0, dot0);
}
vec4 shadeHit(vec3 p, vec3 n, vec3 rd, float mat, float t) {
  if (mat < .5) return catcher(p, SUN, 8., .5, hex(0x1b2c55));
  vec3 albedo; float rough = .12;
  if (mat > 9.5) {
    albedo = mat < 10.5 ? hex(0xf2c230) : hex(0x1f4fa8);
  } else {
    vec4 tile = TILES[int(mat - .5) - 0];
    vec3 c = vec3(tile.x * 1.08, tile.z - .13, tile.y * 1.08);
    vec3 q = p - c;
    float kind = tile.w;
    albedo = kind < .5 ? hex(0x1f4fa8) : kind < 1.5 ? hex(0xf4f1ea) : hex(0xf2c230);
    if (kind > .5 && kind < 1.5 && n.y > .7) albedo = mix(albedo, hex(0x2456b4), clamp(motif(q.xz * 1.04), 0., 1.));
    // Glaze pools darker toward the beveled edges.
    float edge = smoothstep(.36, .5, max(abs(q.x), abs(q.z)));
    albedo *= 1. - .18 * edge * step(.5, n.y);
    albedo *= .96 + .06 * noise3(p * 18.);
  }
  float dif = max(dot(n, SUN), 0.);
  float sh = dif > 0. ? softShadow(p + n * .003, SUN, .01, 8., 9.) : 0.;
  float ao = calcAO(p, n, .3);
  vec3 col = albedo * hex(0xfffaf0) * dif * sh * 1.9;
  col += albedo * hex(0xd2ddf0) * (.45 + .25 * n.y) * ao;
  col += hex(0xffffff) * ggx(n, -rd, SUN, rough) * dif * sh * .9;
  col += env(reflect(rd, n)) * fresnel(.05, n, -rd) * .55 * ao;
  return vec4(col, 1.);
}
vec4 shadeMiss(vec3 ro, vec3 rd, vec2 ndc) { return vec4(0.); }
