// Shared materials for the premium storefront artwork: metal gradients, soft
// light, stone and fabric textures, pearls and satin ribbons. Everything is
// computed from numbers here; no fonts, photos, traced images or downloads.
import { attributes, curve, random } from '../cartoon-storefront-art/draw.mjs';

export { attributes, circle, curve, ellipse, group, path, polygon, random, rect, svg } from '../cartoon-storefront-art/draw.mjs';

const n = (value) => Number(value.toFixed(1));
export const point = ([x, y]) => `${n(x)} ${n(y)}`;

const stopList = (stops) => stops.map(([offset, color, opacity]) =>
  `<stop offset="${offset}" stop-color="${color}"${opacity === undefined ? '' : ` stop-opacity="${opacity}"`}/>`).join('');
export const linear = (id, stops, [x1, y1, x2, y2], units = 'userSpaceOnUse') =>
  `<linearGradient id="${id}" gradientUnits="${units}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stopList(stops)}</linearGradient>`;
export const radial = (id, stops, [cx, cy, r], { units = 'userSpaceOnUse', fx, fy, transform } = {}) =>
  `<radialGradient id="${id}" gradientUnits="${units}" cx="${cx}" cy="${cy}" r="${r}"${fx === undefined ? '' : ` fx="${fx}" fy="${fy}"`}${transform ? ` gradientTransform="${transform}"` : ''}>${stopList(stops)}</radialGradient>`;

// Polished metals: bright bands between darker ones, the way a curved metal
// surface reflects a room. Used across the whole picture so fine lines catch
// the same light.
export const goldStops = [[0, '#6f5220'], [.16, '#b38b3c'], [.32, '#f3dc95'], [.46, '#c49a48'], [.62, '#f7e6a8'], [.8, '#a57d34'], [1, '#6d4f1d']];
export const paleGoldStops = [[0, '#a8823e'], [.25, '#e9cf8c'], [.45, '#fff1c8'], [.65, '#d8b56c'], [.85, '#f4dfa4'], [1, '#a37c38']];
export const silverStops = [[0, '#6d7584'], [.2, '#c3cbd7'], [.4, '#f4f6fa'], [.58, '#9fa8b6'], [.78, '#e4e9f0'], [1, '#727a88']];
export const roseStops = [[0, '#83503f'], [.22, '#c98d78'], [.42, '#f6d3c3'], [.6, '#b9796a'], [.8, '#eec2b1'], [1, '#7d4a3b']];

export const blur = (id, amount) => `<filter id="${id}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${amount}"/></filter>`;

// Fine speckle for paper, stone and fabric: noise turned into a light or dark
// dust whose strength is `amount`.
export const speckle = (id, { frequency = .9, octaves = 2, seed = 3, amount = .08, color = '#ffffff' } = {}) => {
  const [r, g, b] = color.slice(1).match(/../g).map((channel) => parseInt(channel, 16) / 255);
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
<feTurbulence type="fractalNoise" baseFrequency="${frequency}" numOctaves="${octaves}" seed="${seed}" stitchTiles="stitch"/>
<feColorMatrix type="matrix" values="0 0 0 0 ${r.toFixed(3)} 0 0 0 0 ${g.toFixed(3)} 0 0 0 0 ${b.toFixed(3)} ${(amount * 6).toFixed(3)} 0 0 0 ${(-amount * 2.6).toFixed(3)}"/>
</filter>`;
};

// Large soft clouds, the base of marble and stone.
export const clouds = (id, { frequency = '0.004 0.01', octaves = 5, seed = 8, color = '#000000', gain = 1.4, offset = -.5 } = {}) => {
  const [r, g, b] = color.slice(1).match(/../g).map((channel) => parseInt(channel, 16) / 255);
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
<feTurbulence type="fractalNoise" baseFrequency="${frequency}" numOctaves="${octaves}" seed="${seed}"/>
<feColorMatrix type="matrix" values="0 0 0 0 ${r.toFixed(3)} 0 0 0 0 ${g.toFixed(3)} 0 0 0 0 ${b.toFixed(3)} ${gain} 0 0 0 ${offset}"/>
</filter>`;
};

// A darker edge that draws the eye to the middle.
export const vignette = (id, cx, cy, r, strength = .55, color = '#000000') =>
  radial(id, [[0, color, 0], [.55, color, 0], [1, color, strength]], [cx, cy, r]);

// Four-point sparkle.
export const glint = (cx, cy, size, style) => `<path d="M${point([cx, cy - size])}Q${point([cx + size * .12, cy - size * .12])} ${point([cx + size, cy])}Q${point([cx + size * .12, cy + size * .12])} ${point([cx, cy + size])}Q${point([cx - size * .12, cy + size * .12])} ${point([cx - size, cy])}Q${point([cx - size * .12, cy - size * .12])} ${point([cx, cy - size])}Z" ${attributes(style)}/>`;

// Samples a Catmull-Rom curve through `points` as an evenly spaced polyline.
export const sampleCurve = (points, count) => {
  const samples = [];
  const segments = points.length - 1;
  for (let index = 0; index <= count; index++) {
    const t = (index / count) * segments;
    const segment = Math.min(segments - 1, Math.floor(t));
    const u = t - segment;
    const p0 = points[Math.max(0, segment - 1)], p1 = points[segment], p2 = points[segment + 1], p3 = points[Math.min(points.length - 1, segment + 2)];
    const at = (axis) => .5 * ((2 * p1[axis]) + (-p0[axis] + p2[axis]) * u + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * u * u +
      (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * u * u * u);
    samples.push([at(0), at(1)]);
  }
  return samples;
};

// Re-spaces a polyline so neighbouring points are `step` apart.
export const evenly = (polyline, step) => {
  const result = [polyline[0]];
  let carried = 0;
  for (let index = 1; index < polyline.length; index++) {
    const [x0, y0] = polyline[index - 1], [x1, y1] = polyline[index];
    const length = Math.hypot(x1 - x0, y1 - y0);
    let distance = step - carried;
    while (distance <= length) {
      result.push([x0 + (x1 - x0) * distance / length, y0 + (y1 - y0) * distance / length]);
      distance += step;
    }
    carried = length - (distance - step);
  }
  return result;
};

// An organic line of varying width (stone veins, gold seams): a filled outline
// around the centre line, thick in the middle and fine at both ends.
export const taperedLine = (points, width, next, { wobble = .35 } = {}) => {
  const line = sampleCurve(points, Math.max(24, points.length * 10));
  const widths = line.map((_, index) => {
    const t = index / (line.length - 1);
    return Math.max(.25, width * Math.sin(Math.PI * Math.min(1, .06 + t * .94)) * (1 - wobble + wobble * 2 * next()));
  });
  const smooth = widths.map((_, index) => (widths[Math.max(0, index - 1)] + widths[index] * 2 + widths[Math.min(widths.length - 1, index + 1)]) / 4);
  const side = (sign) => line.map(([x, y], index) => {
    const [px, py] = line[Math.max(0, index - 1)], [qx, qy] = line[Math.min(line.length - 1, index + 1)];
    const length = Math.hypot(qx - px, qy - py) || 1;
    return [x - (qy - py) / length * smooth[index] / 2 * sign, y + (qx - px) / length * smooth[index] / 2 * sign];
  });
  const outline = [...side(1), ...side(-1).reverse()];
  return `M${outline.map(point).join('L')}Z`;
};

// A wandering path from `start` heading `angle` (radians): veins and cracks.
export const wander = (start, angle, steps, length, next, turn = .45) => {
  const points = [start];
  let [x, y] = start, heading = angle;
  for (let index = 0; index < steps; index++) {
    heading += (next() - .5) * turn;
    heading += (angle - heading) * .18;
    x += Math.cos(heading) * length * (.7 + next() * .6);
    y += Math.sin(heading) * length * (.7 + next() * .6);
    points.push([x, y]);
  }
  return points;
};

// One pearl: soft shadow, nacre body, rim and a small window highlight.
export const pearl = (cx, cy, r, ids) => [
  `<ellipse cx="${n(cx + r * .22)}" cy="${n(cy + r * .38)}" rx="${n(r * .98)}" ry="${n(r * .9)}" fill="#6b4b3f" opacity=".22" filter="url(#${ids.shadow})"/>`,
  `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r)}" fill="url(#${ids.body})"/>`,
  `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r)}" fill="url(#${ids.sheen})" opacity=".55"/>`,
  `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r - .5)}" fill="none" stroke="#b49c90" stroke-width=".8" opacity=".45"/>`,
  `<ellipse cx="${n(cx - r * .32)}" cy="${n(cy - r * .36)}" rx="${n(r * .22)}" ry="${n(r * .14)}" fill="#ffffff" opacity=".9" transform="rotate(-35 ${n(cx - r * .32)} ${n(cy - r * .36)})"/>`,
].join('');

// A satin ribbon that turns as it travels: each slice is lit by how much it
// faces the light, and its back shows a little darker.
export const ribbon = (points, width, { front, back, light, shade }, twist, count = 520) => {
  const line = sampleCurve(points, count);
  const mix = (a, b, t) => {
    const ca = a.slice(1).match(/../g).map((channel) => parseInt(channel, 16));
    const cb = b.slice(1).match(/../g).map((channel) => parseInt(channel, 16));
    return `#${ca.map((channel, index) => Math.round(channel + (cb[index] - channel) * t).toString(16).padStart(2, '0')).join('')}`;
  };
  const slices = [];
  for (let index = 0; index < line.length - 1; index++) {
    const t = index / (line.length - 1);
    const angle = twist(t);
    const facing = Math.cos(angle);
    const half = Math.max(1.2, Math.abs(facing) * width / 2);
    const [x0, y0] = line[index], [x1, y1] = line[index + 1];
    const length = Math.hypot(x1 - x0, y1 - y0) || 1;
    const [nx, ny] = [-(y1 - y0) / length, (x1 - x0) / length];
    const nextHalf = Math.max(1.2, Math.abs(Math.cos(twist((index + 1) / (line.length - 1)))) * width / 2);
    const quad = [[x0 + nx * half, y0 + ny * half], [x1 + nx * nextHalf, y1 + ny * nextHalf], [x1 - nx * nextHalf, y1 - ny * nextHalf], [x0 - nx * half, y0 - ny * half]];
    // Satin is brightest where the cloth turns towards the viewer at an angle.
    const lit = Math.max(0, Math.min(1, .5 + .5 * Math.sin(angle * 1.6 + .6)));
    const base = facing >= 0 ? front : back;
    const color = lit > .5 ? mix(base, light, (lit - .5) * 1.7) : mix(shade, base, lit * 2);
    slices.push(`<path d="M${quad.map(point).join('L')}Z" fill="${color}" stroke="${color}" stroke-width=".6" stroke-linejoin="round"/>`);
  }
  return slices.join('');
};

// Smooth outline through points (closed or open).
export const smooth = (points, closed = false) => curve(points, closed);
export const seeded = random;
