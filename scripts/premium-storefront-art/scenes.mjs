// The twenty premium storefront pictures, written as code in this repository.
// Originality rules (owner requirement): no existing brand, monogram canvas,
// signature colour or pattern; no text, fonts, photos, traced or AI-generated
// images. Materials are generic (gold leaf, marble, velvet, pearls, crystal)
// and the patterns are public traditional forms drawn here from geometry:
// Thai prajam yam and kranok borders, guilloche rosettes, damask scrolls,
// Art Deco fans and overlapping wave scales.
import {
  blur, circle, clouds, curve, ellipse, evenly, glint, goldStops, group, linear, paleGoldStops, path, pearl, point, polygon,
  radial, random, rect, ribbon, roseStops, sampleCurve, silverStops, speckle, svg, taperedLine, vignette, wander
} from './paint.mjs';

const banner = [1200, 600];
const portal = [800, 800];
const rad = (degrees) => degrees * Math.PI / 180;
const rotate = ([x, y], angle, [cx, cy] = [0, 0]) => [cx + (x - cx) * Math.cos(angle) - (y - cy) * Math.sin(angle), cy + (x - cx) * Math.sin(angle) + (y - cy) * Math.cos(angle)];
const ring = (cx, cy, r, style) => circle(cx, cy, r, { fill: 'none', ...style });
const gauss = (next) => (next() + next() + next() - 1.5) / 1.5;
// A pointed leaf or petal from `a` to `b`, `width` across its middle.
const lens = ([ax, ay], [bx, by], width, bend = 0) => {
  const [mx, my] = [(ax + bx) / 2, (ay + by) / 2];
  const length = Math.hypot(bx - ax, by - ay) || 1;
  const [nx, ny] = [-(by - ay) / length, (bx - ax) / length];
  const left = [mx + nx * (width + bend), my + ny * (width + bend)];
  const right = [mx - nx * (width - bend), my - ny * (width - bend)];
  return `M${point([ax, ay])}Q${point(left)} ${point([bx, by])}Q${point(right)} ${point([ax, ay])}Z`;
};

// 1. Gold leaf: flakes of beaten gold drifting across black lacquer.
const goldLeaf = () => {
  const [width, height] = banner, next = random(101);
  const defs = [
    radial('bg', [[0, '#2b261e'], [.55, '#15130f'], [1, '#090807']], [600, 260, 720]),
    linear('gold', goldStops, [0, 0, width, height]),
    linear('gold2', paleGoldStops, [width, 0, 0, height]),
    radial('glow', [[0, '#d9b45f', .32], [1, '#d9b45f', 0]], [610, 290, 420]),
    blur('soft', 2.2), vignette('edge', 600, 300, 720, .6),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), ellipse(610, 290, 520, 230, { fill: 'url(#glow)', transform: 'rotate(-22 610 290)' })];
  const band = (t) => [70 + t * 1060, 500 - t * 400 + Math.sin(t * Math.PI * 2) * 34];
  const flake = (cx, cy, size, fill, opacity) => {
    const sides = 6 + Math.floor(next() * 5), turn = next() * Math.PI;
    const points = Array.from({ length: sides }, (_, index) => {
      const angle = turn + index / sides * Math.PI * 2 + (next() - .5) * .5;
      const reach = size * (.45 + next() * .7);
      return [cx + Math.cos(angle) * reach, cy + Math.sin(angle) * reach * (.6 + next() * .5)];
    });
    return path(polygon(points), { fill, opacity });
  };
  for (let index = 0; index < 220; index++) {
    const t = next(), spread = gauss(next), [x, y] = band(t);
    const offset = spread * (40 + 110 * Math.sin(t * Math.PI));
    const size = Math.max(1.4, (1 - Math.min(1, Math.abs(spread))) * (8 + next() * 30) * (.45 + Math.sin(t * Math.PI) * .7));
    const [fx, fy] = [x + offset * .35, y + offset];
    if (size > 9) parts.push(flake(fx + 3, fy + 4, size, '#000000', .35));
    parts.push(flake(fx, fy, size, next() > .3 ? 'url(#gold)' : 'url(#gold2)', .72 + next() * .28));
    if (size > 16) parts.push(flake(fx - size * .15, fy - size * .1, size * .45, '#fff3cc', .28));
  }
  for (let index = 0; index < 260; index++) {
    const t = next(), [x, y] = band(t), spread = gauss(next) * 190;
    parts.push(circle(x + spread * .3, y + spread, .6 + next() * 1.8, { fill: '#e8c979', opacity: (.25 + next() * .6).toFixed(2) }));
  }
  parts.push(path(curve(Array.from({ length: 9 }, (_, index) => { const [x, y] = band(index / 8); return [x, y - 70]; })), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.4, opacity: .7 }));
  parts.push(path(curve(Array.from({ length: 9 }, (_, index) => { const [x, y] = band(index / 8); return [x, y + 92]; })), { fill: 'none', stroke: 'url(#gold)', strokeWidth: .9, opacity: .45 }));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 2. White marble: soft grey clouds, crisp veins and one thread of gold.
const whiteMarble = () => {
  const [width, height] = portal, next = random(202);
  const defs = [
    linear('bg', [[0, '#f7f5f1'], [.6, '#efebe4'], [1, '#e6e0d6']], [0, 0, width, height]),
    clouds('cloud', { frequency: '0.0045 0.011', octaves: 5, seed: 12, color: '#8d877d', gain: 1.25, offset: -.52 }),
    clouds('cloud2', { frequency: '0.012 0.02', octaves: 4, seed: 31, color: '#b8b1a6', gain: 1.1, offset: -.45 }),
    linear('gold', goldStops, [0, 0, width, height]),
    blur('veinBlur', 2.4), blur('fine', .5), blur('goldGlow', 3),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), rect(0, 0, width, height, { filter: 'url(#cloud)', opacity: .42 }),
    rect(0, 0, width, height, { filter: 'url(#cloud2)', opacity: .22 })];
  const vein = (start, angle, steps, length, size, color, opacity) => {
    const points = wander(start, angle, steps, length, next, .7);
    parts.push(path(taperedLine(points, size * 3, next), { fill: color, opacity: (opacity * .35).toFixed(2), filter: 'url(#veinBlur)' }));
    parts.push(path(taperedLine(points, size, next), { fill: color, opacity: opacity.toFixed(2), filter: 'url(#fine)' }));
    return points;
  };
  const main = [vein([-40, 120], rad(28), 14, 70, 3.2, '#7d776f', .75), vein([80, -30], rad(62), 13, 72, 2.4, '#8c867d', .6), vein([-30, 560], rad(-8), 12, 76, 2, '#938d84', .55)];
  for (const line of main) for (let index = 2; index < line.length - 2; index += 3) {
    if (next() > .55) vein(line[index], rad(next() * 360), 6, 40, 1.1, '#9a948b', .5);
  }
  const gold = wander([-30, 330], rad(18), 15, 66, next, .5);
  parts.push(path(taperedLine(gold, 7, next), { fill: '#d6b15c', opacity: .35, filter: 'url(#goldGlow)' }));
  parts.push(path(taperedLine(gold, 3.4, next), { fill: 'url(#gold)' }));
  for (let index = 0; index < 60; index++) parts.push(circle(next() * width, next() * height, .5 + next(), { fill: '#7d776f', opacity: (.15 + next() * .3).toFixed(2) }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// One prajam yam: four petals, four smaller leaves and a jewel, in a diamond.
const prajamYam = (cx, cy, size) => {
  const shapes = [];
  for (let index = 0; index < 4; index++) {
    const angle = rad(index * 90);
    shapes.push(lens(rotate([cx, cy - size * .16], angle, [cx, cy]), rotate([cx, cy - size], angle, [cx, cy]), size * .27));
    shapes.push(lens(rotate([cx, cy - size * .18], angle + rad(45), [cx, cy]), rotate([cx, cy - size * .62], angle + rad(45), [cx, cy]), size * .13));
  }
  return shapes.join('');
};

// 3. Thai gold: a prajam yam lattice between kranok borders on deep red.
const thaiGold = () => {
  const [width, height] = banner;
  const defs = [
    radial('bg', [[0, '#62131f'], [.6, '#3d0b14'], [1, '#22060b']], [600, 300, 700]),
    linear('gold', goldStops, [0, 0, width, height]),
    vignette('edge', 600, 300, 700, .5), blur('glow', 6),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  const lattice = [];
  const step = 118;
  for (let row = -1; row <= 6; row++) for (let column = -1; column <= 11; column++) {
    const x = 600 + (column - 5) * step + (row % 2 ? step / 2 : 0), y = 300 + (row - 2.5) * step / 2;
    lattice.push([x, y]);
  }
  // A thin diamond net joins neighbouring motifs.
  const net = [];
  for (let offset = -1400; offset <= 1400; offset += step) {
    net.push(`M${point([600 + offset - 400, -100])}L${point([600 + offset + 400, 700])}`, `M${point([600 + offset + 400, -100])}L${point([600 + offset - 400, 700])}`);
  }
  parts.push(path(net.join(''), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1, opacity: .28 }));
  parts.push(group(lattice.map(([x, y]) => prajamYam(x, y, 30)).map((d) => path(d, { fill: 'url(#gold)' })), { opacity: .92 }));
  parts.push(group(lattice.map(([x, y]) => [circle(x, y, 4.5, { fill: '#62131f' }), circle(x, y, 2.4, { fill: '#f7e3a4' })].join(''))));
  for (const [x, y] of lattice) parts.push(path(`M${point([x, y - 44])}L${point([x + 44, y])}L${point([x, y + 44])}L${point([x - 44, y])}Z`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: .9, opacity: .55 }));
  // Kranok borders: rows of flame-tipped triangles along the top and bottom.
  const border = (y, direction) => {
    const out = [];
    out.push(rect(0, direction > 0 ? y - 6 : y, width, 6, { fill: 'url(#gold)' }));
    out.push(rect(0, direction > 0 ? y - 14 : y + 10, width, 2, { fill: 'url(#gold)', opacity: .8 }));
    for (let x = -20; x < width + 40; x += 44) {
      const base = direction > 0 ? y - 16 : y + 16, tip = base - direction * 54;
      const flame = `M${point([x - 18, base])}C${point([x - 14, base - direction * 26])} ${point([x - 4, tip + direction * 16])} ${point([x + 4, tip])}C${point([x + 2, tip + direction * 14])} ${point([x + 12, base - direction * 22])} ${point([x + 18, base])}Z`;
      out.push(path(flame, { fill: 'url(#gold)' }));
      out.push(path(lens([x, base - direction * 6], [x + 1, tip + direction * 16], 4), { fill: '#3d0b14' }));
    }
    return out.join('');
  };
  parts.push(rect(0, 0, width, 78, { fill: '#2a070d', opacity: .82 }), rect(0, height - 78, width, 78, { fill: '#2a070d', opacity: .82 }));
  parts.push(border(78, 1), border(height - 78, -1));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 4. Art Deco: a sunburst halo, stepped fans and fluted lines on midnight teal.
const artDeco = () => {
  const [width, height] = banner, [cx, cy] = [600, 300];
  const defs = [
    linear('bg', [[0, '#123142'], [1, '#07131a']], [0, 0, 0, height]),
    linear('gold', goldStops, [0, 0, width, height]),
    radial('rayFade', [[0, '#ffffff', 1], [.45, '#ffffff', .9], [1, '#ffffff', 0]], [cx, cy, 640]),
    `<mask id="fade"><rect width="${width}" height="${height}" fill="url(#rayFade)"/></mask>`,
    radial('calm', [[0, '#0b1d27'], [.7, '#0b1d27', .95], [1, '#0b1d27', 0]], [cx, cy, 170]),
    vignette('edge', cx, cy, 720, .55),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  const rays = [];
  for (let index = 0; index < 96; index++) {
    const angle = rad(index * 3.75), inner = 190, outer = index % 2 ? 520 : 760;
    rays.push(`M${point([cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner])}L${point([cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer])}`);
  }
  parts.push(path(rays.join(''), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.2, opacity: .55, mask: 'url(#fade)' }));
  // Stepped fans rising from the lower corners.
  for (const [fx, flip] of [[160, 1], [1040, -1]]) {
    for (let index = 0; index < 7; index++) {
      const r = 70 + index * 30;
      parts.push(path(`M${point([fx - r, height])}A${r} ${r} 0 0 1 ${point([fx + r, height])}`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: index % 3 === 0 ? 2.2 : 1, opacity: .8 }));
    }
    for (let index = 0; index <= 8; index++) {
      const angle = rad(180 + index * 22.5);
      parts.push(path(`M${point([fx + Math.cos(angle) * 70, height + Math.sin(angle) * 70])}L${point([fx + Math.cos(angle) * 250, height + Math.sin(angle) * 250])}`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: .8, opacity: .55 }));
    }
    for (let line = 0; line < 5; line++) {
      const x = flip > 0 ? 34 + line * 12 : width - 34 - line * 12;
      parts.push(path(`M${x} 0L${x} ${height - 240 + line * 14}`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: line === 0 ? 2 : .9, opacity: .7 }));
    }
  }
  // Stepped chevrons along the top.
  for (let line = 0; line < 3; line++) {
    const y = 26 + line * 12, points = [];
    for (let x = 120; x <= 1080; x += 60) points.push([x, y], [x + 30, y + 16]);
    parts.push(path(`M${points.map(point).join('L')}`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1, opacity: .5 }));
  }
  parts.push(circle(cx, cy, 170, { fill: 'url(#calm)' }));
  parts.push(ring(cx, cy, 168, { stroke: 'url(#gold)', strokeWidth: 3 }), ring(cx, cy, 180, { stroke: 'url(#gold)', strokeWidth: 1 }));
  for (let index = 0; index < 48; index++) {
    const angle = rad(index * 7.5), [x, y] = [cx + Math.cos(angle) * 194, cy + Math.sin(angle) * 194];
    parts.push(path(`M${point([x, y - 4])}L${point([x + 4, y])}L${point([x, y + 4])}L${point([x - 4, y])}Z`, { fill: 'url(#gold)', transform: `rotate(${index * 7.5} ${x.toFixed(1)} ${y.toFixed(1)})` }));
  }
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 5. Cut emerald: a step-cut stone in a fine gold setting.
const emeraldFacet = () => {
  const [width, height] = banner, [cx, cy] = [600, 300];
  const defs = [
    radial('bg', [[0, '#144b39'], [.5, '#0a2a20'], [1, '#03100c']], [cx, cy, 680]),
    linear('gold', goldStops, [0, 0, width, height]),
    linear('table', [[0, '#1aa070'], [.45, '#0f774f'], [.55, '#13865b'], [1, '#08482f']], [cx - 160, cy - 100, cx + 160, cy + 100]),
    linear('streak', [[0, '#ffffff', 0], [.5, '#ffffff', .28], [1, '#ffffff', 0]], [cx - 200, cy - 140, cx + 120, cy + 140]),
    blur('shadow', 18), blur('halo', 30), vignette('edge', cx, cy, 700, .5),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  for (let index = 0; index < 18; index++) {
    const angle = rad(-60 + index * 7);
    parts.push(path(`M${point([cx, cy])}L${point([cx + Math.cos(angle) * 900, cy + Math.sin(angle) * 900])}`, { stroke: '#7ff0c2', strokeWidth: 1, opacity: .06 }));
  }
  parts.push(ellipse(cx, cy, 330, 220, { fill: '#1bbd84', opacity: .25, filter: 'url(#halo)' }));
  parts.push(ellipse(cx + 12, cy + 210, 280, 26, { fill: '#000000', opacity: .55, filter: 'url(#shadow)' }));
  const octagon = (w, h, cut) => [[-w + cut, -h], [w - cut, -h], [w, -h + cut], [w, h - cut], [w - cut, h], [-w + cut, h], [-w, h - cut], [-w, -h + cut]]
    .map(([x, y]) => [cx + x, cy + y]);
  const rings = [octagon(270, 186, 64), octagon(222, 150, 52), octagon(178, 118, 42), octagon(138, 88, 32)];
  // Facets facing the upper left catch the light; lower right ones fall dark.
  const shades = ['#2fd497', '#1fae78', '#127e56', '#0a5a3d', '#063c29', '#0a5a3d', '#16936a', '#27c58b'];
  for (let level = 0; level < rings.length - 1; level++) {
    const outer = rings[level], inner = rings[level + 1];
    for (let index = 0; index < 8; index++) {
      const facet = [outer[index], outer[(index + 1) % 8], inner[(index + 1) % 8], inner[index]];
      const shade = shades[(index + level * 3) % 8];
      parts.push(path(polygon(facet), { fill: shade, stroke: '#8ff5cf', strokeWidth: .8, strokeOpacity: .35 }));
    }
  }
  parts.push(path(polygon(rings[3]), { fill: 'url(#table)', stroke: '#8ff5cf', strokeWidth: .8, strokeOpacity: .4 }));
  parts.push(path(polygon(rings[0]), { fill: 'url(#streak)' }));
  parts.push(path(polygon(rings[0]), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 7, strokeLinejoin: 'round' }));
  parts.push(path(polygon(octagon(282, 198, 68)), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.4, opacity: .7 }));
  for (const [x, y] of [rings[0][0], rings[0][2], rings[0][4], rings[0][6]]) {
    const [px, py] = [x + (x < cx ? -6 : 6), y + (y < cy ? -6 : 6)];
    parts.push(circle(px, py, 11, { fill: 'url(#gold)' }), circle(px - 3, py - 3, 3.5, { fill: '#fff4cc', opacity: .8 }));
  }
  for (const [x, y, size] of [[470, 160, 18], [748, 236, 12], [540, 398, 9], [880, 140, 14], [330, 420, 10]]) {
    parts.push(glint(x, y, size, { fill: '#ffffff', opacity: .9 }));
  }
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 6. Pearl strands draped over blush satin.
const pearlStrand = () => {
  const [width, height] = portal, next = random(606);
  const defs = [
    linear('bg', [[0, '#f8ede7'], [.5, '#f0ddd3'], [1, '#e4c7ba']], [0, 0, width, height]),
    radial('body', [[0, '#ffffff'], [.42, '#f8f1ec'], [.78, '#e6d6cf'], [1, '#c8b3aa']], [.38, .34, .7], { units: 'objectBoundingBox' }),
    radial('sheen', [[0, '#f6d9e4', 0], [.7, '#f6d9e4', 0], [.9, '#e9d0f0', .9], [1, '#d7e4f4', .2]], [.5, .5, .5], { units: 'objectBoundingBox' }),
    blur('shadow', 3.5), blur('fold', 26), linear('gold', goldStops, [0, 0, width, height]),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  for (const [points, color, size, opacity] of [
    [[[-60, 260], [240, 180], [520, 330], [860, 240]], '#ffffff', 90, .55],
    [[[-60, 520], [300, 430], [560, 600], [860, 520]], '#ffffff', 70, .45],
    [[[-60, 400], [260, 330], [520, 470], [860, 390]], '#c99a8d', 60, .22],
    [[[-60, 720], [280, 650], [560, 780], [860, 700]], '#c99a8d', 70, .2],
  ]) parts.push(path(curve(points), { fill: 'none', stroke: color, strokeWidth: size, opacity, filter: 'url(#fold)' }));
  const ids = { body: 'body', sheen: 'sheen', shadow: 'shadow' };
  const strand = (points, r, gap) => {
    const line = evenly(sampleCurve(points, 400), r * 2 + gap);
    return line.map(([x, y], index) => pearl(x, y, r * (.96 + .08 * Math.sin(index * 1.7 + next())), ids)).join('');
  };
  parts.push(strand([[-80, 150], [200, 330], [520, 360], [880, 120]], 22, 1.5));
  parts.push(strand([[-80, 300], [220, 520], [560, 540], [880, 300]], 19, 1.2));
  parts.push(strand([[-80, 470], [260, 690], [600, 700], [880, 500]], 16, 1));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 7. Wine velvet: deep folds, a soft light and a twisted gold cord.
const velvetWine = () => {
  const [width, height] = banner, next = random(707);
  const stops = [];
  for (let x = 0; x <= width; x += 12) {
    const fold = .55 * Math.sin(x / 61) + .3 * Math.sin(x / 23 + 1.3) + .15 * Math.sin(x / 9.5 + .4);
    const t = Math.max(0, Math.min(1, .5 + fold * .5));
    const mix = (a, b) => Math.round(a + (b - a) * t);
    const color = `#${[mix(0x1c, 0x86), mix(0x04, 0x22), mix(0x0a, 0x3c)].map((channel) => channel.toString(16).padStart(2, '0')).join('')}`;
    stops.push([(x / width).toFixed(3), color]);
  }
  const defs = [
    linear('folds', stops, [0, 0, width, 0]),
    linear('shade', [[0, '#000000', .55], [.35, '#000000', .05], [.75, '#000000', .1], [1, '#000000', .55]], [0, 0, 0, height]),
    radial('light', [[0, '#ff9fb0', .32], [1, '#ff9fb0', 0]], [820, 230, 420]),
    speckle('nap', { frequency: 1.4, octaves: 2, seed: 9, amount: .07, color: '#ffd5dc' }),
    linear('gold', goldStops, [0, 0, width, height]),
    blur('cordShadow', 5), vignette('edge', 700, 300, 760, .55),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#folds)' }), rect(0, 0, width, height, { fill: 'url(#light)' }),
    rect(0, 0, width, height, { fill: 'url(#shade)' }), rect(0, 0, width, height, { filter: 'url(#nap)' })];
  const cord = sampleCurve([[300, 640], [520, 470], [820, 420], [1120, 300], [1260, 240]], 900);
  const strands = evenly(cord, 13);
  parts.push(path(curve(cord.filter((_, index) => index % 30 === 0)), { fill: 'none', stroke: '#000000', strokeWidth: 30, opacity: .45, filter: 'url(#cordShadow)', transform: 'translate(6 10)' }));
  for (let index = 1; index < strands.length - 1; index++) {
    const [x, y] = strands[index], [px, py] = strands[index - 1];
    const angle = Math.atan2(y - py, x - px) * 180 / Math.PI + 48;
    parts.push(ellipse(x, y, 14, 7.5, { fill: 'url(#gold)', stroke: '#5b3f14', strokeWidth: 1, transform: `rotate(${angle.toFixed(1)} ${x.toFixed(1)} ${y.toFixed(1)})` }));
  }
  for (let index = 0; index < 40; index++) parts.push(circle(next() * width, next() * height, .6 + next() * 1.2, { fill: '#ffc6cf', opacity: (.1 + next() * .2).toFixed(2) }));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 8. Champagne: rising bubbles and warm bokeh around a gold halo.
const champagne = () => {
  const [width, height] = banner, [cx, cy] = [600, 300], next = random(808);
  const defs = [
    radial('bg', [[0, '#fffaf0'], [.45, '#f5e6c6'], [1, '#d9b778']], [cx, cy, 720]),
    radial('halo', [[0, '#ffffff', .95], [.6, '#fff7e6', .6], [1, '#fff7e6', 0]], [cx, cy, 230]),
    radial('bubble', [[0, '#ffffff', .15], [.7, '#fff6dc', .3], [.92, '#c49a4c', .7], [1, '#9c7432', .8]], [.5, .5, .5], { units: 'objectBoundingBox' }),
    linear('gold', goldStops, [0, 0, width, height]),
    blur('bokeh', 6), blur('bokehSoft', 14),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  for (let index = 0; index < 26; index++) {
    const r = 18 + next() * 60;
    parts.push(circle(next() * width, next() * height, r, { fill: next() > .5 ? '#fff6dd' : '#e7c985', opacity: (.25 + next() * .35).toFixed(2), filter: r > 45 ? 'url(#bokehSoft)' : 'url(#bokeh)' }));
  }
  parts.push(circle(cx, cy, 230, { fill: 'url(#halo)' }));
  for (const stream of [80, 200, 330, 880, 1000, 1120]) {
    let y = height + 20, x = stream + (next() - .5) * 30;
    while (y > -20) {
      const r = 3 + (1 - y / height) * 9 * (.6 + next() * .7);
      x += (next() - .5) * 10;
      parts.push(circle(x, y, r, { fill: 'url(#bubble)' }), circle(x - r * .35, y - r * .35, Math.max(.8, r * .24), { fill: '#ffffff', opacity: .95 }));
      y -= r * 2.2 + 10 + next() * 26;
    }
  }
  for (let index = 0; index < 70; index++) {
    const [x, y, r] = [next() * width, next() * height, 2 + next() * 7];
    if (Math.hypot(x - cx, y - cy) < 250) continue;
    parts.push(circle(x, y, r, { fill: 'url(#bubble)', opacity: .8 }), circle(x - r * .35, y - r * .35, Math.max(.8, r * .24), { fill: '#ffffff', opacity: .9 }));
  }
  parts.push(ring(cx, cy, 162, { stroke: 'url(#gold)', strokeWidth: 2.4 }), ring(cx, cy, 174, { stroke: 'url(#gold)', strokeWidth: .9, opacity: .8 }));
  for (const [x, y, size] of [[cx - 176, cy - 70, 14], [cx + 168, cy + 80, 11], [cx + 120, cy - 150, 9], [300, 120, 10], [930, 470, 12]]) {
    parts.push(glint(x, y, size, { fill: 'url(#gold)' }));
  }
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 9. Guilloche: an engraved rosette and wave bands in silver on night blue.
const guilloche = () => {
  const [width, height] = banner, [cx, cy] = [600, 300];
  const defs = [
    radial('bg', [[0, '#1b2a44'], [.6, '#101a2c'], [1, '#080d18']], [cx, cy, 700]),
    linear('silver', silverStops, [0, 0, width, height]),
    vignette('edge', cx, 300, 720, .5),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  const rosette = (base, amplitude, waves, copies, opacity, strokeWidth) => {
    const lines = [];
    for (let copy = 0; copy < copies; copy++) {
      const turn = copy / copies * Math.PI * 2 / waves;
      const points = Array.from({ length: 721 }, (_, index) => {
        const t = index / 720 * Math.PI * 2;
        const r = base + amplitude * Math.sin(waves * (t + turn));
        return [cx + Math.cos(t) * r, cy + Math.sin(t) * r];
      });
      lines.push(`M${points.map(point).join('L')}Z`);
    }
    parts.push(path(lines.join(''), { fill: 'none', stroke: 'url(#silver)', strokeWidth, opacity }));
  };
  rosette(246, 10, 48, 14, .55, .7);
  // A rosette of turned ellipses, the classic engine-turned flower.
  const petals = [];
  for (let copy = 0; copy < 60; copy++) {
    const turn = copy / 60 * Math.PI;
    const points = Array.from({ length: 241 }, (_, index) => {
      const t = index / 240 * Math.PI * 2;
      return rotate([cx + Math.cos(t) * 214, cy + Math.sin(t) * 64], turn, [cx, cy]);
    });
    petals.push(`M${points.map(point).join('L')}Z`);
  }
  parts.push(path(petals.join(''), { fill: 'none', stroke: 'url(#silver)', strokeWidth: .6, opacity: .55 }));
  rosette(150, 9, 36, 12, .6, .7);
  rosette(84, 8, 24, 10, .7, .7);
  // Hypotrochoid star in the middle.
  const flower = Array.from({ length: 2881 }, (_, index) => {
    const t = index / 2880 * Math.PI * 2 * 3;
    const [R, r, d] = [50, 15, 34];
    return [cx + (R - r) * Math.cos(t) + d * Math.cos((R - r) / r * t), cy + (R - r) * Math.sin(t) - d * Math.sin((R - r) / r * t)];
  });
  parts.push(path(`M${flower.map(point).join('L')}`, { fill: 'none', stroke: 'url(#silver)', strokeWidth: .7, opacity: .85 }));
  for (const base of [44, 556]) {
    const lines = [];
    for (let phase = 0; phase < 12; phase++) {
      const points = Array.from({ length: 241 }, (_, index) => {
        const x = index * 5;
        return [x, base + 16 * Math.sin(x / 38 + phase * Math.PI / 12) * Math.cos(x / 210)];
      });
      lines.push(`M${points.map(point).join('L')}`);
    }
    parts.push(path(lines.join(''), { fill: 'none', stroke: 'url(#silver)', strokeWidth: .7, opacity: .55 }));
    parts.push(rect(0, base - 28, width, 1, { fill: 'url(#silver)', opacity: .5 }), rect(0, base + 27, width, 1, { fill: 'url(#silver)', opacity: .5 }));
  }
  parts.push(ring(cx, cy, 266, { stroke: 'url(#silver)', strokeWidth: 1.2, opacity: .6 }));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 10. Rose gold: a brushed half disc and fine rings on blush paper.
const roseGold = () => {
  const [width, height] = banner, next = random(1010);
  const defs = [
    linear('bg', [[0, '#faf1ee'], [1, '#ecd5cd']], [0, 0, width, height]),
    linear('rose', roseStops, [640, 120, 1080, 540]),
    linear('line', roseStops, [0, 0, width, height]),
    `<clipPath id="disc"><circle cx="840" cy="330" r="210"/></clipPath>`,
    speckle('paper', { frequency: 1.1, seed: 4, amount: .05, color: '#9b6a5c' }), blur('shadow', 16),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), rect(0, 0, width, height, { filter: 'url(#paper)' })];
  parts.push(circle(856, 352, 210, { fill: '#8b5546', opacity: .25, filter: 'url(#shadow)' }));
  const brushed = [circle(840, 330, 210, { fill: 'url(#rose)' })];
  for (let y = 120; y < 545; y += 3) brushed.push(rect(620, y, 440, .8 + next(), { fill: next() > .5 ? '#ffffff' : '#6b3a2e', opacity: (.04 + next() * .08).toFixed(2) }));
  parts.push(group(brushed, { clipPath: 'url(#disc)' }));
  parts.push(rect(600, 330, 520, 300, { fill: 'url(#bg)' }));
  parts.push(path('M630 330L1050 330', { stroke: 'url(#line)', strokeWidth: 2 }));
  parts.push(ring(470, 250, 190, { stroke: 'url(#line)', strokeWidth: 1.6 }), ring(560, 330, 128, { stroke: 'url(#line)', strokeWidth: 1 }));
  parts.push(ring(840, 330, 250, { stroke: 'url(#line)', strokeWidth: 1, strokeDasharray: '1 9', strokeLinecap: 'round', opacity: .9 }));
  for (let index = 0; index < 34; index++) {
    const angle = rad(200 + index * 4), [x, y] = [470 + Math.cos(angle) * 220, 250 + Math.sin(angle) * 220];
    parts.push(circle(x, y, index % 4 ? 1.6 : 3, { fill: 'url(#line)' }));
  }
  parts.push(path('M120 520L420 470', { stroke: 'url(#line)', strokeWidth: 1.2 }), path('M150 548L470 494', { stroke: 'url(#line)', strokeWidth: .7 }));
  parts.push(glint(300, 140, 14, { fill: 'url(#line)' }), glint(1080, 160, 10, { fill: 'url(#line)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 11. Midnight stars: orbit rings, a crescent moon and invented constellations.
const midnightStars = () => {
  const [width, height] = banner, [cx, cy] = [600, 300], next = random(1111);
  const defs = [
    radial('bg', [[0, '#26235a'], [.55, '#141233'], [1, '#07061a']], [cx, cy, 720]),
    linear('band', [[0, '#6c5aa8', 0], [.5, '#6c5aa8', .3], [1, '#6c5aa8', 0]], [0, 520, 1200, 80]),
    linear('gold', goldStops, [0, 0, width, height]),
    blur('soft', 24), blur('star', 1.6), blur('moonGlow', 14),
    `<mask id="crescent"><rect width="${width}" height="${height}" fill="#000"/><circle cx="1010" cy="128" r="48" fill="#fff"/><circle cx="1032" cy="114" r="44" fill="#000"/></mask>`,
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), path('M-80 560C300 380 800 260 1280 40', { stroke: 'url(#band)', strokeWidth: 170, fill: 'none', filter: 'url(#soft)' })];
  for (let index = 0; index < 460; index++) parts.push(circle(next() * width, next() * height, .4 + next() * 1.3, { fill: next() > .2 ? '#ffffff' : '#f5dfa8', opacity: (.25 + next() * .7).toFixed(2) }));
  for (let index = 0; index < 26; index++) {
    const [x, y] = [next() * width, next() * height];
    parts.push(circle(x, y, 2.5, { fill: '#ffffff', filter: 'url(#star)' }), circle(x, y, 1.2, { fill: '#ffffff' }));
  }
  for (const group of [[[160, 150], [230, 110], [300, 170], [370, 130], [420, 210]], [[870, 420], [940, 380], [1010, 430], [1080, 400]], [[220, 430], [290, 470], [360, 440], [400, 510]]]) {
    parts.push(path(`M${group.map(point).join('L')}`, { fill: 'none', stroke: '#f2e2b8', strokeWidth: .9, opacity: .45 }));
    for (const [x, y] of group) parts.push(circle(x, y, 3, { fill: '#fff2cc' }), circle(x, y, 7, { fill: '#fff2cc', opacity: .25, filter: 'url(#star)' }));
  }
  parts.push(ring(cx, cy, 166, { stroke: 'url(#gold)', strokeWidth: 1.8 }), ring(cx, cy, 182, { stroke: 'url(#gold)', strokeWidth: 1, strokeDasharray: '2 7', strokeLinecap: 'round' }));
  parts.push(ring(cx, cy, 236, { stroke: '#ffffff', strokeWidth: .7, opacity: .22 }));
  parts.push(circle(cx + 166 * Math.cos(rad(-40)), cy + 166 * Math.sin(rad(-40)), 6, { fill: 'url(#gold)' }), circle(cx + 236 * Math.cos(rad(152)), cy + 236 * Math.sin(rad(152)), 4, { fill: '#f5dfa8' }));
  parts.push(circle(1010, 128, 54, { fill: '#f6dc96', opacity: .35, filter: 'url(#moonGlow)' }), rect(900, 40, 200, 180, { fill: 'url(#gold)', mask: 'url(#crescent)' }));
  for (const [x, y, size] of [[120, 300, 12], [760, 90, 9], [460, 540, 10], [1110, 520, 13]]) parts.push(glint(x, y, size, { fill: '#f6dfa0' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 12. Black onyx: dark stone with quartz threads and gold-filled seams.
const blackOnyx = () => {
  const [width, height] = banner, next = random(1212);
  const defs = [
    linear('bg', [[0, '#141417'], [1, '#09090b']], [0, 0, width, height]),
    clouds('stone', { frequency: '0.005 0.011', octaves: 5, seed: 21, color: '#3a3a42', gain: 1.4, offset: -.55 }),
    speckle('glimmer', { frequency: 1.6, seed: 5, amount: .05, color: '#d8d2c4' }),
    linear('gold', goldStops, [0, 0, width, height]), blur('glow', 5), blur('fine', .6),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), rect(0, 0, width, height, { filter: 'url(#stone)', opacity: .8 }), rect(0, 0, width, height, { filter: 'url(#glimmer)' })];
  for (const [start, angle] of [[[-20, 120], 12], [[200, -20], 58], [[640, 640], -70], [[1220, 420], 196]]) {
    parts.push(path(taperedLine(wander(start, rad(angle), 14, 64, next, .7), 1.4, next), { fill: '#cfcfd8', opacity: .3, filter: 'url(#fine)' }));
  }
  const seam = (start, angle, steps, size) => {
    const points = wander(start, rad(angle), steps, 58, next, .8);
    parts.push(path(taperedLine(points, size * 2.6, next), { fill: '#d8a94a', opacity: .3, filter: 'url(#glow)' }));
    parts.push(path(taperedLine(points, size, next), { fill: 'url(#gold)' }));
    return points;
  };
  const seams = [seam([260, 640], -38, 15, 5.5), seam([1240, 90], 160, 12, 4.5), seam([520, -20], 70, 10, 3.2)];
  for (const line of seams) for (let index = 3; index < line.length - 2; index += 4) seam(line[index], (next() - .5) * 300, 4, 1.8);
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 13. Silk ribbons: two satin bands that turn as they fall.
const silkRibbon = () => {
  const [width, height] = portal;
  const defs = [radial('bg', [[0, '#fffbf3'], [.6, '#f6ecdb'], [1, '#e7d6b8']], [400, 360, 620]), blur('shadow', 14)].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  const first = [[-120, 170], [160, 110], [360, 280], [330, 500], [540, 650], [900, 580]];
  const second = [[920, 200], [640, 130], [480, 320], [580, 520], [420, 720], [180, 900]];
  parts.push(path(curve(first), { fill: 'none', stroke: '#8a6a3a', strokeWidth: 70, opacity: .18, filter: 'url(#shadow)', transform: 'translate(14 22)' }));
  parts.push(path(curve(second), { fill: 'none', stroke: '#8a6a3a', strokeWidth: 60, opacity: .16, filter: 'url(#shadow)', transform: 'translate(14 22)' }));
  parts.push(ribbon(second, 86, { front: '#efe3cc', back: '#d9c6a2', light: '#fffaf0', shade: '#a8916a' }, (t) => .4 + t * 7.4));
  parts.push(ribbon(first, 96, { front: '#dcbb7d', back: '#c39c5a', light: '#fff2d2', shade: '#7f5f2a' }, (t) => -.2 + t * 8.6));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 14. Crystal: a cluster of clear quartz points with a thin rainbow.
const crystal = () => {
  const [width, height] = banner, next = random(1414);
  const defs = [
    linear('bg', [[0, '#f7fafd'], [1, '#d9e4f1']], [0, 0, 0, height]),
    linear('faceLight', [[0, '#ffffff', .95], [1, '#e2ebf7', .7]], [0, 0, 1, 1], 'objectBoundingBox'),
    linear('faceMid', [[0, '#e1eaf6', .85], [1, '#c3d3ea', .7]], [0, 0, 1, 1], 'objectBoundingBox'),
    linear('faceDark', [[0, '#b9cbe4', .8], [1, '#93aacd', .75]], [0, 0, 1, 1], 'objectBoundingBox'),
    linear('spectrum', [[0, '#ff6b6b', 0], [.2, '#ffb86b', .5], [.4, '#fff07a', .5], [.6, '#7affb0', .5], [.8, '#7ab8ff', .5], [1, '#c58bff', 0]], [0, 0, 1, 0], 'objectBoundingBox'),
    blur('soft', 3), blur('shadow', 16), radial('glow', [[0, '#ffffff', .9], [1, '#ffffff', 0]], [600, 300, 360]),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), rect(0, 0, width, height, { fill: 'url(#glow)' })];
  parts.push(ellipse(600, 548, 360, 30, { fill: '#5b7397', opacity: .25, filter: 'url(#shadow)' }));
  const point3 = (base, angle, length, half) => {
    const [bx, by] = base, dir = [Math.sin(angle), -Math.cos(angle)], side = [Math.cos(angle), Math.sin(angle)];
    const at = (along, across) => [bx + dir[0] * along + side[0] * across, by + dir[1] * along + side[1] * across];
    const shoulder = length - half * 1.6;
    const left = [at(0, -half), at(shoulder, -half), at(shoulder + half * .5, -half * .35), at(0, -half * .35)];
    const middle = [at(0, -half * .35), at(shoulder + half * .5, -half * .35), at(shoulder + half * .5, half * .35), at(0, half * .35)];
    const right = [at(0, half * .35), at(shoulder + half * .5, half * .35), at(shoulder, half), at(0, half)];
    const tipLeft = [at(shoulder, -half), at(length, 0), at(shoulder + half * .5, -half * .35)];
    const tipMiddle = [at(shoulder + half * .5, -half * .35), at(length, 0), at(shoulder + half * .5, half * .35)];
    const tipRight = [at(shoulder + half * .5, half * .35), at(length, 0), at(shoulder, half)];
    const edge = { stroke: '#ffffff', strokeWidth: 1.4, strokeOpacity: .9, strokeLinejoin: 'round' };
    return [
      path(polygon(left), { fill: 'url(#faceLight)', ...edge }), path(polygon(middle), { fill: 'url(#faceMid)', ...edge }),
      path(polygon(right), { fill: 'url(#faceDark)', ...edge }), path(polygon(tipLeft), { fill: 'url(#faceLight)', ...edge }),
      path(polygon(tipMiddle), { fill: '#ffffff', fillOpacity: .9, ...edge }), path(polygon(tipRight), { fill: 'url(#faceMid)', ...edge }),
    ].join('');
  };
  for (const [x, angle, length, half] of [[470, -34, 260, 34], [740, 30, 280, 36], [540, -14, 360, 46], [660, 12, 400, 50], [600, -2, 300, 40], [400, -52, 180, 26], [810, 48, 200, 28]]) {
    parts.push(group(point3([x, 560], rad(angle), length, half), { opacity: .92 }));
  }
  parts.push(rect(-100, 200, 1400, 16, { fill: 'url(#spectrum)', transform: 'rotate(-14 600 300)', filter: 'url(#soft)', opacity: .55 }));
  parts.push(rect(-100, 360, 1400, 10, { fill: 'url(#spectrum)', transform: 'rotate(-14 600 300)', filter: 'url(#soft)', opacity: .35 }));
  for (let index = 0; index < 9; index++) parts.push(glint(300 + next() * 600, 80 + next() * 400, 6 + next() * 12, { fill: '#ffffff' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// One damask fleuron: a tall centre petal, curling side leaves and a bud,
// mirrored left to right.
const fleuron = (cx, cy) => {
  const right = [
    lens([cx + 34, cy + 36], [cx + 64, cy - 52], 11, 5),
    lens([cx + 26, cy + 58], [cx + 76, cy + 34], 8, -3),
    lens([cx + 20, cy - 70], [cx + 36, cy - 104], 5, 2),
  ];
  const curl = `M${point([cx + 8, cy + 66])}C${point([cx + 40, cy + 96])} ${point([cx + 74, cy + 84])} ${point([cx + 70, cy + 62])}C${point([cx + 66, cy + 48])} ${point([cx + 50, cy + 54])} ${point([cx + 54, cy + 66])}`;
  const mirror = (d) => d.replace(/(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g, (_, x, y) => `${(2 * cx - Number(x)).toFixed(1)} ${y}`);
  const leaves = [lens([cx, cy + 74], [cx, cy - 92], 17), ...right, ...right.map(mirror),
    lens([cx - 30, cy + 92], [cx + 30, cy + 92], 6), lens([cx, cy - 98], [cx, cy - 128], 6)].join('');
  return { leaves, curls: curl + mirror(curl), bud: [cx, cy - 104] };
};
const fourLeaf = (cx, cy, size) => [0, 90, 180, 270].map((angle) => lens(rotate([cx, cy - 3], rad(angle), [cx, cy]), rotate([cx, cy - size], rad(angle), [cx, cy]), size * .28)).join('');

// 15. Damask: an ogee lattice of fine gold with tone-on-tone fleurons on navy.
const damask = () => {
  const [width, height] = banner;
  const defs = [
    radial('bg', [[0, '#1f3054'], [.6, '#152342'], [1, '#0b1428']], [600, 300, 720]),
    linear('gold', goldStops, [0, 0, width, height]),
    linear('sheen', [[0, '#ffffff', 0], [.5, '#ffffff', .07], [1, '#ffffff', 0]], [0, 0, width, height]),
    vignette('edge', 600, 300, 720, .5),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  // Two mirrored waves per column meet at points, making onion-shaped cells.
  const lines = [];
  for (let column = -1; column <= 7; column++) {
    for (const sign of [1, -1]) {
      const points = Array.from({ length: 121 }, (_, index) => {
        const y = -60 + index * 6, wave = Math.sin(Math.PI * (y + 30) / 300);
        return [column * 200 + sign * 100 * Math.sign(wave) * Math.abs(wave) ** .8, y];
      });
      lines.push(`M${points.map(point).join('L')}`);
    }
  }
  parts.push(path(lines.join(''), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.3, opacity: .75 }));
  for (let column = -1; column <= 7; column++) for (let row = -1; row <= 2; row++) {
    const { leaves, curls, bud } = fleuron(column * 200, 120 + row * 300);
    parts.push(path(leaves, { fill: '#2b4377', stroke: 'url(#gold)', strokeWidth: .9, strokeOpacity: .75 }));
    parts.push(path(curls, { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.6, strokeLinecap: 'round', opacity: .8 }));
    parts.push(circle(bud[0], bud[1], 5, { fill: 'url(#gold)' }));
    // Where neighbouring cells touch, a small four-leaf rosette.
    const [x, y] = [column * 200 + 100, 120 + row * 300 + 150];
    parts.push(path(fourLeaf(x, y, 18), { fill: 'url(#gold)', opacity: .85 }), circle(x, y, 3, { fill: '#152342' }));
  }
  parts.push(rect(0, 0, width, height, { fill: 'url(#sheen)' }), rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 16. Golden palms: gold line fronds over deep tropical green.
const goldenPalms = () => {
  const [width, height] = banner, next = random(1616);
  const defs = [
    linear('bg', [[0, '#123628'], [1, '#081a13']], [0, 0, width, height]),
    radial('light', [[0, '#3f8f6b', .35], [1, '#3f8f6b', 0]], [780, 260, 520]),
    linear('gold', goldStops, [0, 0, width, height]), vignette('edge', 700, 300, 760, .55),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' }), rect(0, 0, width, height, { fill: 'url(#light)' })];
  const frond = (points, size, silhouette) => {
    const spine = sampleCurve(points, 60);
    const out = [];
    for (let index = 4; index < spine.length - 1; index += 2) {
      const t = index / (spine.length - 1);
      const [x, y] = spine[index], [px, py] = spine[index - 1];
      const heading = Math.atan2(y - py, x - px);
      const length = size * (1 - t * .75) * (.85 + next() * .3);
      for (const side of [-1, 1]) {
        const angle = heading + side * rad(52 - t * 18);
        const tip = [x + Math.cos(angle) * length, y + Math.sin(angle) * length + length * .18];
        out.push(lens([x, y], tip, length * .07, side * length * .02));
      }
    }
    if (silhouette) return path(out.join(''), { fill: '#0f3a2b', opacity: .9 });
    return [path(out.join(''), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.3 }), path(curve(points), { fill: 'none', stroke: 'url(#gold)', strokeWidth: 2.4, strokeLinecap: 'round' })].join('');
  };
  const fronds = [
    [[[1240, -40], [1060, 120], [880, 190], [700, 220]], 130],
    [[[1260, 420], [1080, 360], [920, 380], [780, 450]], 110],
    [[[640, -60], [700, 80], [660, 210], [560, 280]], 100],
    [[[1200, 640], [1040, 520], [960, 440], [930, 330]], 95],
    [[[300, -60], [380, 60], [470, 120], [560, 130]], 80],
  ];
  for (const [points, size] of fronds) parts.push(frond(points.map(([x, y]) => [x + 18, y + 14]), size * 1.05, true));
  for (const [points, size] of fronds) parts.push(frond(points, size, false));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 17. Spotlight: warm beams meet on an empty pedestal; gold dust in the light.
const spotlight = () => {
  const [width, height] = banner, [cx, cy] = [600, 300], next = random(1717);
  const defs = [
    radial('bg', [[0, '#1c1a17'], [.6, '#0c0b0a'], [1, '#050505']], [cx, 260, 700]),
    linear('beam', [[0, '#fff1cf', .55], [1, '#fff1cf', 0]], [0, 0, 0, 1], 'objectBoundingBox'),
    radial('pool', [[0, '#ffe6b0', .5], [1, '#ffe6b0', 0]], [cx, 470, 330], { transform: 'translate(0 470) scale(1 .16) translate(0 -470)' }),
    radial('center', [[0, '#fff3d6', .55], [1, '#fff3d6', 0]], [cx, cy, 240]),
    linear('stone', [[0, '#2a2723'], [.3, '#4a443c'], [.5, '#5d564c'], [.7, '#3b3630'], [1, '#1c1a17']], [cx - 170, 0, cx + 170, 0]),
    linear('gold', goldStops, [cx - 170, 0, cx + 170, 0]), blur('beamBlur', 16), blur('dust', 1.2),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#bg)' })];
  for (const [sx, spread] of [[360, 120], [600, 150], [840, 120]]) {
    parts.push(path(`M${sx - 20} -40L${sx + 20} -40L${cx + spread} 470L${cx - spread} 470Z`, { fill: 'url(#beam)', filter: 'url(#beamBlur)', opacity: .8 }));
  }
  parts.push(circle(cx, cy, 240, { fill: 'url(#center)' }), rect(0, 380, width, 220, { fill: 'url(#pool)' }));
  parts.push(rect(cx - 170, 448, 340, 200, { fill: 'url(#stone)' }));
  parts.push(ellipse(cx, 448, 170, 24, { fill: '#5a5348' }), ellipse(cx, 448, 170, 24, { fill: 'none', stroke: 'url(#gold)', strokeWidth: 3 }));
  parts.push(path(`M${cx - 170} 470C${cx - 120} 492 ${cx + 120} 492 ${cx + 170} 470`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: 1.4, opacity: .8 }));
  for (let index = 0; index < 240; index++) {
    const y = next() * 470, spread = 40 + y * .32, x = cx + (next() - .5) * 2 * spread;
    parts.push(circle(x, y, .5 + next() * 1.6, { fill: '#f5d68a', opacity: (.2 + next() * .7).toFixed(2), filter: next() > .7 ? 'url(#dust)' : undefined }));
  }
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 18. Colonnade: receding arches over a chequered marble floor.
const colonnade = () => {
  const [width, height] = portal, [vx, vy] = [400, 420];
  const defs = [
    linear('wall', [[0, '#f3ecdf'], [1, '#e2d6c1']], [0, 0, 0, height]),
    radial('light', [[0, '#ffffff', 1], [.4, '#fff9ec', .7], [1, '#fff9ec', 0]], [vx, vy - 40, 260]),
    linear('gold', goldStops, [0, 0, width, height]),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#wall)' })];
  const frame = (depth) => {
    const half = 330 / depth, spring = vy - 120 / depth, floor = vy + 380 / depth;
    return { half, spring, floor };
  };
  // Floor tiles converge on the vanishing point.
  const floor = [];
  const depths = Array.from({ length: 14 }, (_, index) => 1 + index * .45);
  for (let row = 0; row < depths.length - 1; row++) {
    const near = frame(depths[row]), far = frame(depths[row + 1]);
    for (let column = -6; column < 6; column++) {
      const x = (depth, c) => vx + c * 120 / depth;
      const tile = [[x(depths[row], column), near.floor], [x(depths[row], column + 1), near.floor], [x(depths[row + 1], column + 1), far.floor], [x(depths[row + 1], column), far.floor]];
      floor.push(path(polygon(tile), { fill: (row + column) % 2 ? '#efe7d8' : '#d9ccb4', stroke: '#c7a868', strokeWidth: .5, strokeOpacity: .5 }));
    }
  }
  parts.push(...floor);
  parts.push(rect(0, 0, width, height, { fill: 'url(#light)' }));
  for (let index = 7; index >= 0; index--) {
    const { half, spring, floor: base } = frame(1 + index * .62);
    const pillar = Math.max(4, 34 / (1 + index * .62));
    const outer = `M${point([vx - half - pillar, base])}L${point([vx - half - pillar, spring])}A${half + pillar} ${half + pillar} 0 0 1 ${point([vx + half + pillar, spring])}L${point([vx + half + pillar, base])}L${point([width + 40, base])}L${point([width + 40, -40])}L-40 -40L${point([-40, base])}Z`;
    const opening = `M${point([vx - half, base])}L${point([vx - half, spring])}A${half} ${half} 0 0 1 ${point([vx + half, spring])}L${point([vx + half, base])}`;
    if (index === 0) parts.push(path(outer, { fill: '#efe6d5' }));
    else parts.push(path(outer, { fill: '#f1e9da', opacity: (.35 + (7 - index) * .06).toFixed(2) }));
    parts.push(path(opening, { fill: 'none', stroke: 'url(#gold)', strokeWidth: (3.2 / (1 + index * .45)).toFixed(2) }));
    parts.push(path(`M${point([vx - half - pillar, base])}L${point([vx - half - pillar, spring])}A${half + pillar} ${half + pillar} 0 0 1 ${point([vx + half + pillar, spring])}L${point([vx + half + pillar, base])}`, { fill: 'none', stroke: 'url(#gold)', strokeWidth: (1.4 / (1 + index * .45)).toFixed(2), opacity: .8 }));
  }
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 19. Hand-stitched leather: pebbled cognac, saddle stitches and a gold buckle.
const leatherStitch = () => {
  const [width, height] = banner;
  const defs = [
    linear('hide', [[0, '#9c5a2f'], [.5, '#87471f'], [1, '#6a3415']], [0, 0, width, height]),
    speckle('pebble', { frequency: .09, octaves: 3, seed: 14, amount: .1, color: '#2e1406' }),
    speckle('shine', { frequency: .11, octaves: 2, seed: 15, amount: .06, color: '#ffd7b0' }),
    linear('strap', [[0, '#5a2a10'], [.5, '#6e3518'], [1, '#4a210b']], [0, 300, 0, 420]),
    linear('gold', goldStops, [0, 0, width, height]), blur('drop', 4), vignette('edge', 600, 300, 720, .6),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#hide)' }), rect(0, 0, width, height, { filter: 'url(#pebble)' }), rect(0, 0, width, height, { filter: 'url(#shine)' })];
  const groove = (inset, radius) => [
    rect(inset + 1.5, inset + 1.5, width - inset * 2, height - inset * 2, { rx: radius, fill: 'none', stroke: '#e0a273', strokeWidth: 1.4, opacity: .35 }),
    rect(inset, inset, width - inset * 2, height - inset * 2, { rx: radius, fill: 'none', stroke: '#3a1806', strokeWidth: 2.4, opacity: .55 }),
  ].join('');
  parts.push(groove(30, 26));
  const stitches = (x, y, w, h, radius) => {
    const out = [];
    const outline = [[x + radius, y], [x + w - radius, y], [x + w, y + radius], [x + w, y + h - radius], [x + w - radius, y + h], [x + radius, y + h], [x, y + h - radius], [x, y + radius], [x + radius, y]];
    const line = evenly(outline, 26);
    for (let index = 0; index < line.length - 1; index++) {
      const [ax, ay] = line[index], [bx, by] = line[index + 1];
      const [sx, sy] = [ax + (bx - ax) * .15, ay + (by - ay) * .15], [ex, ey] = [ax + (bx - ax) * .85 + (by - ay) * .08, ay + (by - ay) * .85 - (bx - ax) * .08];
      out.push(path(`M${point([sx + 1.5, sy + 2])}L${point([ex + 1.5, ey + 2])}`, { stroke: '#2a1003', strokeWidth: 4.6, strokeLinecap: 'round', opacity: .5 }));
      out.push(path(`M${point([sx, sy])}L${point([ex, ey])}`, { stroke: '#f3e2c4', strokeWidth: 4, strokeLinecap: 'round' }));
      out.push(circle(ax, ay, 2.2, { fill: '#2a1003', opacity: .7 }));
    }
    return out.join('');
  };
  parts.push(stitches(54, 54, width - 108, height - 108, 0));
  // A strap with stitched edges ends in a plain gold buckle.
  parts.push(rect(700, 318, 600, 110, { fill: '#000000', opacity: .4, filter: 'url(#drop)', transform: 'translate(0 8)' }));
  parts.push(rect(700, 318, 600, 110, { fill: 'url(#strap)' }), rect(700, 318, 600, 110, { filter: 'url(#pebble)' }));
  for (const y of [334, 412]) {
    for (let x = 720; x < 1220; x += 22) parts.push(path(`M${x} ${y}L${x + 13} ${y}`, { stroke: '#f0dcba', strokeWidth: 3, strokeLinecap: 'round', opacity: .9 }));
  }
  parts.push(rect(640, 300, 120, 146, { rx: 16, fill: 'none', stroke: '#000000', strokeWidth: 20, opacity: .35, filter: 'url(#drop)', transform: 'translate(3 7)' }));
  parts.push(rect(640, 300, 120, 146, { rx: 16, fill: 'none', stroke: 'url(#gold)', strokeWidth: 18 }));
  parts.push(rect(640, 300, 120, 146, { rx: 16, fill: 'none', stroke: '#fff1c4', strokeWidth: 1.2, opacity: .7 }));
  parts.push(rect(632, 366, 140, 14, { rx: 7, fill: 'url(#gold)' }));
  parts.push(rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 20. Sapphire waves: overlapping silver-lined wave scales on deep blue.
const sapphireWave = () => {
  const [width, height] = banner;
  const defs = [
    linear('sea', [[0, '#173f86'], [1, '#0a1c44']], [0, 0, width * .4, height]),
    linear('silver', silverStops, [0, 0, width, height]),
    linear('sheen', [[0, '#ffffff', 0], [.5, '#ffffff', .12], [1, '#ffffff', 0]], [0, height, width, 0]),
    vignette('edge', 600, 300, 720, .5),
  ].join('');
  const parts = [rect(0, 0, width, height, { fill: 'url(#sea)' })];
  const r = 64;
  for (let row = 0; row < height / (r / 2) + 3; row++) {
    const y = row * r / 2 - r / 2;
    for (let column = -1; column < width / (r * 2) + 2; column++) {
      const x = column * r * 2 + (row % 2 ? r : 0);
      parts.push(circle(x, y, r, { fill: 'url(#sea)' }));
      for (let ringIndex = 0; ringIndex < 5; ringIndex++) {
        const radius = r - ringIndex * 12.5;
        parts.push(path(`M${point([x - radius, y])}A${radius} ${radius} 0 0 1 ${point([x + radius, y])}`, { fill: 'none', stroke: 'url(#silver)', strokeWidth: ringIndex === 0 ? 2.2 : 1.3, opacity: (.85 - ringIndex * .12).toFixed(2) }));
      }
    }
  }
  parts.push(rect(0, 0, width, height, { fill: 'url(#sheen)' }), rect(0, 0, width, height, { fill: 'url(#edge)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// Pictures are drawn on a 1200 x 600 (or 800 x 800) grid and exported a little
// smaller: still sharp on a phone's full-width banner, lighter in the app.
const exported = (draw) => () => {
  const scene = draw(), factor = scene.width === scene.height ? .875 : 5 / 6;
  const [width, height] = [Math.round(scene.width * factor), Math.round(scene.height * factor)];
  return { width, height, svg: scene.svg.replace(`width="${scene.width}" height="${scene.height}"`, `width="${width}" height="${height}"`) };
};

// Catalog order.
export const premiumScenes = [
  ['premium-gold-leaf', goldLeaf], ['premium-white-marble', whiteMarble], ['premium-thai-gold', thaiGold], ['premium-art-deco', artDeco],
  ['premium-emerald-facet', emeraldFacet], ['premium-pearl-strand', pearlStrand], ['premium-velvet-wine', velvetWine], ['premium-champagne', champagne],
  ['premium-guilloche', guilloche], ['premium-rose-gold', roseGold], ['premium-midnight-stars', midnightStars], ['premium-black-onyx', blackOnyx],
  ['premium-silk-ribbon', silkRibbon], ['premium-crystal', crystal], ['premium-damask', damask], ['premium-golden-palms', goldenPalms],
  ['premium-spotlight', spotlight], ['premium-colonnade', colonnade], ['premium-leather-stitch', leatherStitch], ['premium-sapphire-wave', sapphireWave],
].map(([id, draw]) => ({ id, draw: exported(draw) }));
