// Small vector toolkit for the cartoon storefront drawings. Everything is
// drawn here from numbers: no fonts, photos, traced images or third-party art.
// A seeded random source keeps every hand-drawn wobble reproducible.

export const random = (seed) => {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
};

const n = (value) => Number(value.toFixed(1));
const point = ([x, y]) => `${n(x)} ${n(y)}`;

// Catmull-Rom spline through the points, as cubic Bezier segments.
export const curve = (points, closed = false) => {
  const count = points.length;
  const at = (index) => closed ? points[(index + count) % count] : points[Math.max(0, Math.min(count - 1, index))];
  let path = `M${point(points[0])}`;
  for (let index = 0; index < (closed ? count : count - 1); index++) {
    const [p0, p1, p2, p3] = [at(index - 1), at(index), at(index + 1), at(index + 2)];
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    path += `C${point(c1)} ${point(c2)} ${point(p2)}`;
  }
  return closed ? `${path}Z` : path;
};

export const polygon = (points) => `M${points.map(point).join('L')}Z`;

// Nudges every point a little, the way a hand never draws a perfect line.
export const jitter = (points, amount, next) => points.map(([x, y]) => [x + (next() - .5) * 2 * amount, y + (next() - .5) * 2 * amount]);

export const ellipsePoints = (cx, cy, rx, ry, steps = 18, start = 0) => Array.from({ length: steps }, (_, index) => {
  const angle = start + (index / steps) * Math.PI * 2;
  return [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry];
});

export const roundedRectPoints = (x, y, width, height, radius, steps = 4) => {
  const corners = [[x + width - radius, y + radius, -Math.PI / 2], [x + width - radius, y + height - radius, 0],
    [x + radius, y + height - radius, Math.PI / 2], [x + radius, y + radius, Math.PI]];
  return corners.flatMap(([cx, cy, start]) => Array.from({ length: steps + 1 }, (_, index) => {
    const angle = start + (index / steps) * (Math.PI / 2);
    return [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
  }));
};

export const starPoints = (cx, cy, outer, inner, spikes = 5, rotation = -Math.PI / 2) => Array.from({ length: spikes * 2 }, (_, index) => {
  const radius = index % 2 ? inner : outer;
  const angle = rotation + (index / (spikes * 2)) * Math.PI * 2;
  return [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
});

// Evenly spaced points along a straight segment, for lines that wobble.
export const linePoints = ([x1, y1], [x2, y2], steps = 6) => Array.from({ length: steps + 1 }, (_, index) => [x1 + (x2 - x1) * index / steps, y1 + (y2 - y1) * index / steps]);

export const attributes = (values) => Object.entries(values).filter(([, value]) => value !== undefined)
  .map(([key, value]) => `${key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}="${value}"`).join(' ');

export const path = (d, style = {}) => `<path d="${d}" ${attributes(style)}/>`;
export const circle = (cx, cy, r, style = {}) => `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r)}" ${attributes(style)}/>`;
export const ellipse = (cx, cy, rx, ry, style = {}) => `<ellipse cx="${n(cx)}" cy="${n(cy)}" rx="${n(rx)}" ry="${n(ry)}" ${attributes(style)}/>`;
export const rect = (x, y, width, height, style = {}) => `<rect x="${n(x)}" y="${n(y)}" width="${n(width)}" height="${n(height)}" ${attributes(style)}/>`;
export const group = (content, style = {}) => `<g ${attributes(style)}>${Array.isArray(content) ? content.join('') : content}</g>`;

export const ink = (color, width) => ({ fill: 'none', stroke: color, strokeWidth: width, strokeLinecap: 'round', strokeLinejoin: 'round' });
export const filled = (fill, stroke, width) => ({ fill, stroke, strokeWidth: width, strokeLinejoin: 'round', strokeLinecap: 'round' });

// A hand-drawn outline drawn twice, slightly apart, like a quick ink sketch.
export const sketch = (points, closed, color, width, next, wobble = 3) => [
  path(curve(jitter(points, wobble, next), closed), ink(color, width)),
  path(curve(jitter(points, wobble * 1.4, next), closed), { ...ink(color, width * .45), opacity: '.75' }),
].join('');

export const svg = (width, height, content, defs = '') =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${defs ? `<defs>${defs}</defs>` : ''}${Array.isArray(content) ? content.join('') : content}</svg>`;

// Grain for crayon and chalk strokes: noise cuts small holes into the stroke.
export const grainFilter = (id, frequency, cut, seed = 4) => `<filter id="${id}" x="-5%" y="-5%" width="110%" height="110%">
<feTurbulence type="fractalNoise" baseFrequency="${frequency}" numOctaves="2" seed="${seed}" result="noise"/>
<feColorMatrix in="noise" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -2.2 ${cut}" result="mask"/>
<feComposite in="SourceGraphic" in2="mask" operator="in" result="grain"/>
<feTurbulence type="fractalNoise" baseFrequency="${frequency / 6}" numOctaves="1" seed="${seed + 1}" result="wave"/>
<feDisplacementMap in="grain" in2="wave" scale="5" xChannelSelector="R" yChannelSelector="G"/>
</filter>`;
