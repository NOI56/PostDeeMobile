// The ten cartoon storefront drawings, written as code in this repository.
// Originality rules (owner requirement, 2026-11-02): no existing or
// recognizable character, franchise, studio, mascot or brand style; no text,
// fonts, photos, traced or AI-generated images. Shapes are generic (stars,
// clouds, awnings, bubbles, signs, planets) and the one mascot, a hang tag, was
// designed here. Colors avoid well-known brand liveries, for example
// convenience-store awnings, chat-app greens and the orange marketplace bag.
import {
  circle, curve, ellipse, ellipsePoints, filled, grainFilter, group, ink, jitter, linePoints, path, polygon, random,
  rect, roundedRectPoints, sketch, starPoints, svg
} from './draw.mjs';

const arrowHead = (tip, angle, size, color, width) => {
  const wing = (offset) => [tip[0] - Math.cos(angle + offset) * size, tip[1] - Math.sin(angle + offset) * size];
  return path(`M${wing(.5).join(' ')}L${tip.join(' ')}L${wing(-.5).join(' ')}`, ink(color, width));
};
const sparkle = (cx, cy, size, style) => path(curve([[cx, cy - size], [cx + size * .18, cy - size * .18], [cx + size, cy], [cx + size * .18, cy + size * .18],
  [cx, cy + size], [cx - size * .18, cy + size * .18], [cx - size, cy], [cx - size * .18, cy - size * .18]], true), style);
const plus = (cx, cy, size, color, width) => path(`M${cx - size} ${cy}L${cx + size} ${cy}M${cx} ${cy - size}L${cx} ${cy + size}`, ink(color, width));
const heartPath = (cx, cy, size) => `M${cx} ${cy + size * .9}C${cx - size * 1.6} ${cy - size * .1} ${cx - size * .9} ${cy - size * 1.3} ${cx} ${cy - size * .45}C${cx + size * .9} ${cy - size * 1.3} ${cx + size * 1.6} ${cy - size * .1} ${cx} ${cy + size * .9}Z`;
// Scalloped cloud: outward arcs between points around an ellipse.
const cloudPath = (cx, cy, rx, ry, bumps, next, wobble = 0) => {
  const points = ellipsePoints(cx, cy, rx, ry, bumps, -Math.PI / 2)
    .map(([x, y]) => next ? [x + (next() - .5) * wobble * rx, y + (next() - .5) * wobble * ry] : [x, y]);
  const format = ([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`;
  return `M${format(points[0])}${points.map((current, index) => {
    const following = points[(index + 1) % points.length];
    const radius = Math.hypot(following[0] - current[0], following[1] - current[1]) * .62;
    return `A${radius.toFixed(1)} ${radius.toFixed(1)} 0 0 1 ${format(following)}`;
  }).join('')}Z`;
};
// Straight edges split into short steps, so a wobbly spline stays box-shaped.
const box = (corners, steps = 6) => corners.flatMap((corner, index) => linePoints(corner, corners[(index + 1) % corners.length], steps).slice(0, -1));

// 1. Doodle shop: black ink doodles and highlighter on cream paper.
const doodleShop = () => {
  const width = 1600, height = 800, next = random(11), line = '#1f1b16';
  const parts = [rect(0, 0, width, height, { fill: '#fff4df' })];
  for (let y = 36; y < height; y += 44) for (let x = 36; x < width; x += 44) parts.push(circle(x, y, 2.4, { fill: '#ecd9b6' }));
  // Shop: highlighter fills sit slightly off the ink, as quick markers do.
  const [x, y, w] = [590, 150, 420];
  parts.push(path(polygon(jitter([[x - 22, y + 18], [x + w + 30, y + 18], [x + w + 12, y + 118], [x - 4, y + 118]], 5, next)), { fill: '#ffd84d' }));
  parts.push(path(polygon(jitter([[x + 52, y + 168], [x + 202, y + 168], [x + 202, y + 268], [x + 52, y + 268]], 4, next)), { fill: '#9fdcf3' }));
  parts.push(path(polygon(jitter([[x + 262, y + 168], [x + 372, y + 168], [x + 372, y + 360], [x + 262, y + 360]], 4, next)), { fill: '#ff9f80' }));
  parts.push(sketch(box([[x - 30, y], [x + w + 30, y], [x + w, y + 92], [x, y + 92]]), true, line, 7, next, 2.5));
  for (let index = 0; index < 6; index++) {
    const sx = x + index * (w / 6);
    parts.push(path(curve(jitter([[sx, y + 92], [sx + w / 12, y + 128], [sx + w / 6, y + 92]], 2.5, next)), ink(line, 7)));
    if (index) parts.push(path(curve(jitter(linePoints([x - 30 + index * ((w + 60) / 6), y], [sx, y + 92], 3), 2, next)), ink(line, 5)));
  }
  parts.push(sketch(linePoints([x + 14, y + 128], [x + 14, y + 360], 4), false, line, 7, next, 2.5));
  parts.push(sketch(linePoints([x + w - 14, y + 128], [x + w - 14, y + 360], 4), false, line, 7, next, 2.5));
  parts.push(sketch(box([[x + 40, y + 156], [x + 190, y + 156], [x + 190, y + 256], [x + 40, y + 256]], 4), true, line, 6, next, 2));
  parts.push(path(curve(jitter(linePoints([x + 115, y + 158], [x + 115, y + 254], 3), 2, next)), ink(line, 5)));
  parts.push(path(curve(jitter(linePoints([x + 42, y + 206], [x + 188, y + 206], 3), 2, next)), ink(line, 5)));
  parts.push(sketch(box([[x + 250, y + 156], [x + 360, y + 156], [x + 360, y + 360], [x + 250, y + 360]], 4), true, line, 6, next, 2));
  parts.push(circle(x + 340, y + 262, 7, { fill: line }));
  parts.push(path(curve(jitter(linePoints([x - 120, y + 362], [x + w + 120, y + 362], 10), 3, next)), ink(line, 7)));
  // Doodles around the shop.
  const star = starPoints(255, 215, 82, 36);
  parts.push(path(polygon(jitter(star.map(([sx, sy]) => [sx + 10, sy + 9]), 3, next)), { fill: '#ffd84d' }));
  parts.push(sketch(star, true, line, 7, next, 3));
  const spiral = Array.from({ length: 34 }, (_, index) => [160 + Math.cos(index * .45) * (6 + index * 2.6), 520 + Math.sin(index * .45) * (6 + index * 2.6)]);
  parts.push(path(curve(jitter(spiral, 1.5, next)), ink(line, 6)));
  const arrow = [[250, 660], [340, 690], [430, 650], [480, 560], [510, 470]];
  parts.push(path(curve(jitter(arrow, 3, next)), ink(line, 7)));
  parts.push(arrowHead([510, 470], Math.atan2(-90, 30), 38, line, 7));
  parts.push(path(cloudPath(380, 390, 92, 50, 7, next, .1), ink(line, 7)));
  parts.push(plus(450, 120, 18, line, 6), plus(110, 330, 14, line, 6), plus(1090, 110, 16, line, 6), plus(1530, 200, 18, line, 6));
  parts.push(path(curve(jitter(roundedRectPoints(1170, 170, 240, 140, 40, 3), 3, next), true), ink(line, 7)));
  parts.push(path(curve(jitter([[1220, 306], [1196, 360], [1262, 308]], 2, next)), ink(line, 7)));
  for (let index = 0; index < 3; index++) parts.push(circle(1240 + index * 50, 240, 9, { fill: line }));
  parts.push(path(heartPath(1450, 452, 44), { fill: '#ff9f80', transform: 'translate(8 8)' }));
  parts.push(path(heartPath(1450, 452, 44), ink(line, 7)));
  parts.push(path(polygon(jitter([[1196, 486], [1336, 486], [1336, 596], [1196, 596]], 4, next)), { fill: '#7fd1ae', transform: 'translate(10 9)' }));
  parts.push(sketch(box([[1180, 470], [1340, 470], [1340, 590], [1180, 590]], 4), true, line, 7, next, 2));
  parts.push(sketch(box([[1166, 440], [1354, 440], [1354, 474], [1166, 474]], 4), true, line, 7, next, 2));
  parts.push(path(curve(jitter(linePoints([1260, 442], [1260, 588], 4), 2, next)), ink(line, 7)));
  parts.push(path(curve(jitter([[1260, 440], [1210, 390], [1200, 430], [1258, 440]], 2, next)), ink(line, 7)));
  parts.push(path(curve(jitter([[1262, 440], [1312, 390], [1322, 430], [1264, 440]], 2, next)), ink(line, 7)));
  parts.push(path(curve(jitter([[1180, 650], [1220, 620], [1260, 650], [1300, 620], [1340, 650], [1380, 620], [1420, 650]], 2, next)), ink(line, 6)));
  for (const [dx, dy] of [[90, 120], [1520, 640], [80, 720], [700, 60], [920, 70], [1530, 420]]) parts.push(circle(dx, dy, 7, { fill: line }));
  return { width, height, svg: svg(width, height, parts) };
};

// 2. Comic panels: three slanted panels with halftone, a burst and speed lines.
const comicPanels = () => {
  const width = 1600, height = 700, next = random(23), line = '#141414';
  const panels = [
    [[0, 0], [549, 0], [489, height], [0, height]],
    [[571, 0], [1089, 0], [1149, height], [511, height]],
    [[1111, 0], [width, 0], [width, height], [1171, height]],
  ];
  const dots = (id, color, size, gap) => `<pattern id="${id}" width="${gap}" height="${gap}" patternUnits="userSpaceOnUse" patternTransform="rotate(20)"><circle cx="${gap / 2}" cy="${gap / 2}" r="${size}" fill="${color}"/></pattern>`;
  const defs = [dots('dots-a', '#f08c00', 6, 22), dots('dots-b', '#2a6fb0', 5, 22), dots('dots-c', '#d6336c', 6, 24),
    ...panels.map((points, index) => `<clipPath id="panel-${index}"><path d="${polygon(points)}"/></clipPath>`)].join('');
  const parts = [rect(0, 0, width, height, { fill: '#fffdf5' })];
  // Panel A: action burst.
  parts.push(group([rect(0, 0, 600, height, { fill: '#ffe14d' }), rect(0, 0, 600, height, { fill: 'url(#dots-a)', opacity: '.45' }),
    ...Array.from({ length: 22 }, (_, index) => {
      const angle = (index / 22) * Math.PI * 2;
      return path(`M${270 + Math.cos(angle) * 250} ${350 + Math.sin(angle) * 250}L${270 + Math.cos(angle) * 520} ${350 + Math.sin(angle) * 520}`, ink(line, 6));
    }),
    path(polygon(jitter(starPoints(270, 350, 230, 140, 14, .1), 10, next)), filled('#ff5a4f', line, 10)),
    path(polygon(jitter(starPoints(270, 350, 125, 82, 12, .3), 6, next)), filled('#fff6c2', line, 8))], { clipPath: 'url(#panel-0)' }));
  // Panel B: sky, clouds and speed lines.
  const clouds = [[700, 180, 120, 62], [960, 420, 110, 56], [780, 560, 70, 36]];
  parts.push(group([rect(500, 0, 700, height, { fill: '#8fd3ff' }), rect(500, 0, 700, height, { fill: 'url(#dots-b)', opacity: '.3' }),
    ...[150, 250, 330, 470, 610].map((sy, index) => path(`M${1180} ${sy}L${940 - index * 40} ${sy}`, ink('#ffffff', 10))),
    ...clouds.map(([cx, cy, rx, ry]) => path(cloudPath(cx, cy, rx, ry, 8, next, .12), filled('#ffffff', line, 9))),
    sparkle(1010, 170, 40, filled('#ffe14d', line, 7))], { clipPath: 'url(#panel-1)' }));
  // Panel C: twinkle.
  parts.push(group([rect(1100, 0, 500, height, { fill: '#ffb3c7' }), rect(1100, 0, 500, height, { fill: 'url(#dots-c)', opacity: '.3' }),
    sparkle(1390, 330, 190, filled('#ffffff', line, 10)), sparkle(1240, 140, 56, filled('#ffe14d', line, 7)),
    sparkle(1500, 600, 48, filled('#8fd3ff', line, 7)), circle(1250, 560, 16, { fill: line }), circle(1530, 110, 12, { fill: line })], { clipPath: 'url(#panel-2)' }));
  for (const points of panels) parts.push(path(polygon(points), { fill: 'none', stroke: line, strokeWidth: 9, strokeLinejoin: 'round' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 3. Little tag buddy: the one mascot, a hang tag designed for PostDee.
const tagBuddy = () => {
  const width = 1200, height = 960, next = random(37), line = '#16302b', body = '#ff7a59';
  const corner = (points, radius) => {
    let d = '';
    points.forEach((current, index) => {
      const previous = points[(index - 1 + points.length) % points.length];
      const following = points[(index + 1) % points.length];
      const towards = (from, to) => {
        const length = Math.hypot(to[0] - from[0], to[1] - from[1]);
        return [from[0] + (to[0] - from[0]) * Math.min(radius, length / 2) / length, from[1] + (to[1] - from[1]) * Math.min(radius, length / 2) / length];
      };
      const start = towards(current, previous);
      const end = towards(current, following);
      d += `${index ? 'L' : 'M'}${start[0].toFixed(1)} ${start[1].toFixed(1)}Q${current[0]} ${current[1]} ${end[0].toFixed(1)} ${end[1].toFixed(1)}`;
    });
    return `${d}Z`;
  };
  const shape = [[600, 150], [810, 330], [810, 770], [390, 770], [390, 330]];
  const parts = [
    ellipse(600, 878, 300, 36, { fill: '#0f6b5c', opacity: '.16' }),
    path('M600 262C560 200 520 120 560 82C600 44 660 70 650 120C642 170 620 220 612 262', ink('#0f6b5c', 12)),
    // Legs and feet.
    path(corner([[500, 740], [560, 740], [560, 850], [500, 850]], 18), filled(body, line, 12)),
    path(corner([[640, 740], [700, 740], [700, 850], [640, 850]], 18), filled(body, line, 12)),
    ellipse(522, 856, 56, 26, filled('#16302b', line, 6)), ellipse(678, 856, 56, 26, filled('#16302b', line, 6)),
    // Arms: one waving.
    path('M400 520C340 490 300 440 292 392', ink(line, 30)), path('M400 520C340 490 300 440 292 392', ink(body, 16)),
    circle(288, 376, 34, filled(body, line, 12)),
    path('M800 540C850 570 880 610 890 652', ink(line, 30)), path('M800 540C850 570 880 610 890 652', ink(body, 16)),
    circle(894, 668, 32, filled(body, line, 12)),
    // Body with a soft highlight.
    path(corner(shape, 46), filled(body, line, 14)),
    path(corner([[430, 360], [470, 330], [470, 700], [430, 700]], 20), { fill: '#ff9b80' }),
    circle(600, 300, 40, filled('#ffd36e', line, 10)), circle(600, 300, 18, filled('#fff8ef', line, 6)),
    // Face.
    ellipse(528, 478, 24, 32, { fill: line }), ellipse(672, 478, 24, 32, { fill: line }),
    circle(520, 466, 9, { fill: '#ffffff' }), circle(664, 466, 9, { fill: '#ffffff' }),
    ellipse(476, 540, 36, 20, { fill: '#ffb8a6' }), ellipse(724, 540, 36, 20, { fill: '#ffb8a6' }),
    path('M556 544Q600 616 644 544Z', filled('#7a1f1f', line, 8)),
    path('M576 572Q600 600 624 572Q600 560 576 572Z', { fill: '#ff8fa3' }),
  ];
  for (const [cx, cy, size] of [[230, 230, 46], [990, 260, 38], [1030, 520, 28], [170, 560, 24]]) parts.push(sparkle(cx, cy, size, filled('#3cc4a0', line, 6)));
  for (const [cx, cy] of [[300, 140], [930, 140], [1080, 400], [140, 420]]) parts.push(circle(cx, cy, 9 + next() * 4, { fill: '#0f6b5c' }));
  return { width, height, svg: svg(width, height, parts) };
};

// 4. Sticker sheet: die-cut stickers with thick white edges.
const stickerSheet = () => {
  const width = 1600, height = 800, next = random(41), line = '#3d2f63';
  const defs = '<filter id="lift" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="8" stdDeviation="8" flood-color="#2a2140" flood-opacity=".22"/></filter>';
  const parts = [rect(0, 0, width, height, { fill: '#f3eefe' })];
  for (let y = 30; y < height; y += 40) for (let x = 30 + (y / 40 % 2) * 20; x < width; x += 40) parts.push(circle(x, y, 2.2, { fill: '#e2d8fb' }));
  const sticker = (d, fill, transform, extra = '') => group([path(d, { fill: '#ffffff', stroke: '#ffffff', strokeWidth: 30, strokeLinejoin: 'round' }),
    path(d, filled(fill, line, 5)), extra], { transform, filter: 'url(#lift)' });
  parts.push(sticker(polygon(starPoints(0, 0, 110, 52)), '#ffd23f', 'translate(250 250) rotate(-12)'));
  const rainbow = [['#ff8fa3', 120], ['#ffd36e', 92], ['#7fd1ff', 64]].map(([color, radius]) =>
    path(`M${-radius} 0A${radius} ${radius} 0 0 1 ${radius} 0`, ink(color, 26))).join('');
  parts.push(group([path('M-146 0A146 146 0 0 1 146 0L146 12L-146 12Z', { fill: '#ffffff', stroke: '#ffffff', strokeWidth: 34, strokeLinejoin: 'round' }),
    rainbow, path('M-133 0A133 133 0 0 1 133 0', ink(line, 5)), path('M-51 0A51 51 0 0 1 51 0', ink(line, 5)),
    path(cloudPath(-128, 14, 44, 26, 6), filled('#ffffff', line, 5)), path(cloudPath(128, 14, 44, 26, 6), filled('#ffffff', line, 5))],
  { transform: 'translate(640 210) rotate(6)', filter: 'url(#lift)' }));
  parts.push(sticker(cloudPath(0, 0, 110, 58, 8, next, .06), '#ffffff', 'translate(1010 190) rotate(-6)',
    path('M-60 18Q-20 34 30 22', ink('#cfe6ff', 12))));
  parts.push(sticker('M20 -120L-60 10L-6 10L-30 120L64 -30L8 -30L36 -120Z', '#ff9f43', 'translate(1350 250) rotate(14)'));
  const petals = Array.from({ length: 6 }, (_, index) => {
    const angle = index * Math.PI / 3;
    return `<ellipse cx="${(Math.cos(angle) * 62).toFixed(1)}" cy="${(Math.sin(angle) * 62).toFixed(1)}" rx="50" ry="38" transform="rotate(${index * 60} ${(Math.cos(angle) * 62).toFixed(1)} ${(Math.sin(angle) * 62).toFixed(1)})"/>`;
  }).join('');
  parts.push(group([`<g fill="#ffffff" stroke="#ffffff" stroke-width="30">${petals}</g>`, `<g fill="#ff9ecb" stroke="${line}" stroke-width="5">${petals}</g>`,
    circle(0, 0, 42, filled('#ffd23f', line, 5))], { transform: 'translate(360 590) rotate(10)', filter: 'url(#lift)' }));
  parts.push(sticker(curve([[0, -130], [24, -24], [130, 0], [24, 24], [0, 130], [-24, 24], [-130, 0], [-24, -24]], true), '#5fd3a8', 'translate(1190 580) rotate(8)'));
  parts.push(sticker(heartPath(0, 0, 60), '#ff6b8b', 'translate(120 560) rotate(-14)'));
  parts.push(sticker('M40 -96A100 100 0 1 0 40 96A76 76 0 1 1 40 -96Z', '#ffe08a', 'translate(1480 560) rotate(-20)'));
  for (const [cx, cy, radius, color] of [[520, 470, 30, '#a78bfa'], [1060, 470, 24, '#7fd1ff'], [880, 120, 20, '#ff8fa3'], [90, 120, 26, '#5fd3a8'], [1540, 110, 22, '#a78bfa']]) {
    parts.push(group([circle(cx, cy, radius + 12, { fill: '#ffffff' }), circle(cx, cy, radius, filled(color, line, 4))], { filter: 'url(#lift)' }));
  }
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 5. Chalkboard: chalk flourishes, a blank ribbon and a ray burst.
const chalkboard = () => {
  const width = 1600, height = 800, next = random(53), chalk = '#f4f1e8', yellow = '#f3d27a', pink = '#f6a5b8';
  const defs = `${grainFilter('chalk', .55, 1.55, 7)}<filter id="smudge"><feGaussianBlur stdDeviation="40"/></filter>`;
  const parts = [rect(0, 0, width, height, { fill: '#2f4a3e' })];
  parts.push(group(Array.from({ length: 9 }, () => ellipse(next() * width, next() * height, 160 + next() * 220, 60 + next() * 90, { fill: '#ffffff', opacity: (.025 + next() * .035).toFixed(3) })), { filter: 'url(#smudge)' }));
  const strokes = [];
  // Ray burst behind where the owner's avatar sits.
  for (let index = 0; index <= 16; index++) {
    const angle = Math.PI + (index / 16) * Math.PI;
    strokes.push(path(curve(jitter(linePoints([800 + Math.cos(angle) * 300, 640 + Math.sin(angle) * 300], [800 + Math.cos(angle) * 380, 640 + Math.sin(angle) * 380], 2), 3, next)), ink(index % 2 ? yellow : chalk, 9)));
  }
  // Blank ribbon banner.
  const ribbon = 'M560 150C680 120 920 120 1040 150L1040 230C920 200 680 200 560 230Z';
  strokes.push(path(ribbon, { fill: '#ffffff', opacity: '.07' }), path(ribbon, ink(chalk, 12)));
  strokes.push(path('M560 168L480 160L512 200L480 244L560 230', ink(chalk, 12)), path('M1040 168L1120 160L1088 200L1120 244L1040 230', ink(chalk, 12)));
  // Corner scrolls.
  const scroll = (cx, cy, flipX, flipY) => {
    const points = Array.from({ length: 30 }, (_, index) => {
      const angle = index * .42;
      const radius = 70 - index * 2.1;
      return [cx + flipX * (Math.cos(angle) * radius + index * 6), cy + flipY * Math.sin(angle) * radius];
    });
    return path(curve(jitter(points, 2, next)), ink(chalk, 11));
  };
  strokes.push(scroll(150, 140, 1, 1), scroll(1450, 140, -1, 1), scroll(150, 690, 1, -1), scroll(1450, 690, -1, -1));
  // Doodles.
  strokes.push(path(curve(jitter([[200, 300], [300, 280], [390, 320], [450, 390], [480, 470]], 3, next)), ink(pink, 16)));
  strokes.push(arrowHead([480, 470], Math.atan2(80, 30), 44, pink, 12));
  strokes.push(path(polygon(jitter(starPoints(430, 150, 46, 20), 3, next)), ink(yellow, 12)), path(polygon(jitter(starPoints(1180, 150, 40, 18), 3, next)), ink(yellow, 12)));
  strokes.push(path(polygon(jitter(starPoints(1300, 420, 54, 24), 3, next)), ink(chalk, 12)));
  strokes.push(path(heartPath(1340, 600, 40), ink(pink, 12)), path(heartPath(240, 560, 32), ink(yellow, 12)));
  strokes.push(plus(1420, 300, 18, yellow, 7), plus(180, 420, 16, chalk, 7), plus(800, 60, 16, chalk, 7));
  for (let index = 0; index < 14; index++) strokes.push(circle(1060 + index * 26, 330 - Math.sin(index / 13 * Math.PI) * 60, 7, { fill: chalk }));
  parts.push(group(strokes, { filter: 'url(#chalk)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 6. Street shopfront: a striped awning, window and door; the owner's logo
// hangs as the sign above it, so the wall above the awning is left calm.
const streetFront = () => {
  const width = 1600, height = 800, next = random(67), line = '#2b1d16', teal = '#2f8f83', terracotta = '#d9634a', cream = '#fff4e6';
  const parts = [rect(0, 0, width, height, { fill: '#f6d8c0' }), rect(0, 0, width, 36, { fill: '#e8b896' }), path('M0 36L1600 36', ink(line, 6))];
  for (const [bx, by] of [[90, 120], [190, 200], [70, 300], [1420, 110], [1510, 230], [1390, 330], [300, 90], [1250, 80]]) {
    parts.push(path(curve(roundedRectPoints(bx, by, 86, 34, 10, 2), true), ink('#ecbf9f', 5)));
  }
  // Wall lamps.
  for (const lx of [430, 1170]) {
    parts.push(circle(lx, 300, 70, { fill: '#fff1c9', opacity: '.55' }), path(`M${lx} 230L${lx} 262`, ink(line, 7)),
      path(`M${lx - 36} 262L${lx + 36} 262L${lx + 24} 330L${lx - 24} 330Z`, filled('#ffe08a', line, 7)), path(`M${lx - 30} 336L${lx + 30} 336`, ink(line, 7)));
  }
  // Awning.
  const top = 432, bottom = 528, left = 230, right = 1370, stripes = 14, stripe = (right - left) / stripes;
  for (let index = 0; index < stripes; index++) {
    const x1 = left + index * stripe, x2 = x1 + stripe;
    const topX1 = 260 + index * ((1340 - 260) / stripes), topX2 = topX1 + (1340 - 260) / stripes;
    parts.push(path(`M${topX1} ${top}L${topX2} ${top}L${x2} ${bottom}A${stripe / 2} ${stripe / 2} 0 0 1 ${x1} ${bottom}Z`, filled(index % 2 ? cream : terracotta, line, 6)));
  }
  parts.push(path(`M260 ${top}L1340 ${top}`, ink(line, 8)));
  // Shopfront below the awning.
  parts.push(rect(250, 560, 1100, 260, { fill: '#e9c3a5' }));
  parts.push(rect(300, 590, 440, 240, filled(teal, line, 8)), rect(326, 614, 388, 220, filled('#cfe8f0', line, 6)));
  parts.push(path('M380 640L440 600M420 700L520 620', ink('#ffffff', 12)), path('M326 760L714 760', ink(line, 6)));
  parts.push(path('M600 760L600 704', ink(line, 6)), ellipse(600, 690, 34, 24, filled('#7bc96f', line, 6)), path('M576 760L624 760L616 800L584 800Z', filled(terracotta, line, 6)));
  parts.push(rect(840, 580, 230, 250, filled(teal, line, 8)), rect(870, 612, 170, 92, filled('#3ca597', line, 5)),
    circle(1040, 724, 11, filled('#ffd36e', line, 5)), circle(955, 658, 34, filled('#cfe8f0', line, 6)));
  parts.push(rect(1130, 590, 190, 240, filled(teal, line, 8)), rect(1154, 614, 142, 220, filled('#cfe8f0', line, 6)), path('M1180 660L1230 620', ink('#ffffff', 10)));
  // Potted plants on the pavement.
  for (const [px, flip] of [[150, 1], [1450, -1]]) {
    parts.push(path(`M${px - 60} 690L${px + 60} 690L${px + 46} 800L${px - 46} 800Z`, filled(terracotta, line, 7)));
    for (const [dx, dy, rotate] of [[-34, 640, -30], [0, 610, 0], [34, 640, 30], [-10 * flip, 580, 10 * flip]]) {
      parts.push(ellipse(px + dx, dy, 26, 54, { ...filled('#4caf7a', line, 6), transform: `rotate(${rotate} ${px + dx} ${dy})` }));
    }
  }
  return { width, height, svg: svg(width, height, parts) };
};

// 7. Chat bubbles: empty speech bubbles in a friendly cluster.
const chatBubbles = () => {
  const width = 1600, height = 640, line = '#14233a';
  const bubble = (d, fill, inner = '') => group([path(d, filled(fill, line, 9)), inner]);
  const rounded = (x, y, w, h, r, tail) => `M${x + r} ${y}H${x + w - r}Q${x + w} ${y} ${x + w} ${y + r}V${y + h - r}Q${x + w} ${y + h} ${x + w - r} ${y + h}`
    + (tail === 'right' ? `H${x + w - 70}L${x + w - 20} ${y + h + 60}L${x + w - 120} ${y + h}` : '')
    + `H${tail === 'left' ? x + 130 : x + r}${tail === 'left' ? `L${x + 30} ${y + h + 64}L${x + 70} ${y + h}H${x + r}` : ''}Q${x} ${y + h} ${x} ${y + h - r}V${y + r}Q${x} ${y} ${x + r} ${y}Z`;
  const parts = [];
  parts.push(bubble(rounded(380, 60, 440, 210, 70, 'left'), '#ffd36e', [520, 600, 680].map((cx) => circle(cx, 165, 22, { fill: line })).join('')));
  parts.push(bubble(`M1060 70C1220 70 1320 130 1320 210C1320 290 1220 350 1080 350L1180 420L990 342C880 326 800 276 800 210C800 130 900 70 1060 70Z`, '#8fd3ff',
    path(heartPath(1060, 210, 52), { fill: '#ffffff' })));
  parts.push(bubble(`M230 300C320 300 380 360 380 430C380 500 320 560 240 560C220 560 200 556 182 550L110 600L132 528C100 504 80 470 80 430C80 360 140 300 230 300Z`, '#b8f0c9',
    sparkle(230, 430, 62, filled('#ffffff', line, 6))));
  parts.push(bubble(rounded(620, 360, 400, 170, 60, 'right'), '#ffb3c7',
    rect(680, 410, 280, 24, { fill: '#ffffff', rx: 12 }) + rect(680, 456, 190, 24, { fill: '#ffffff', rx: 12 })));
  parts.push(bubble(cloudPath(1340, 470, 140, 78, 8), '#ffffff', [1296, 1340, 1384].map((cx) => circle(cx, 474, 12, { fill: line })).join('')));
  parts.push(circle(1170, 590, 26, filled('#ffffff', line, 8)), circle(1120, 620, 14, filled('#ffffff', line, 7)));
  for (const [cx, cy, size, color] of [[300, 120, 34, '#ffd36e'], [1460, 150, 40, '#ffb3c7'], [560, 560, 28, '#8fd3ff'], [1500, 330, 24, '#b8f0c9']]) parts.push(sparkle(cx, cy, size, filled(color, line, 6)));
  return { width, height, svg: svg(width, height, parts) };
};

// 8. Signposts: blank wooden arrow signs on a grassy mound.
const signposts = () => {
  const width = 1200, height = 960, next = random(83), line = '#2a1a0c', wood = '#d9a066', dark = '#b7793f';
  const grain = (x1, x2, y1, y2) => Array.from({ length: 3 }, (_, index) => {
    const y = y1 + (index + 1) * (y2 - y1) / 4;
    return path(curve(jitter(linePoints([x1 + 30, y], [x2 - 50, y], 5), 3, next)), ink(dark, 5));
  }).join('');
  const board = (x1, x2, y1, y2, pointRight, rotate) => group([
    path(pointRight ? `M${x1} ${y1}H${x2 - 60}L${x2} ${(y1 + y2) / 2}L${x2 - 60} ${y2}H${x1}Z` : `M${x2} ${y1}H${x1 + 60}L${x1} ${(y1 + y2) / 2}L${x1 + 60} ${y2}H${x2}Z`, filled(wood, line, 11)),
    grain(x1, x2, y1, y2), circle(pointRight ? x1 + 36 : x2 - 36, (y1 + y2) / 2, 8, { fill: line })], { transform: `rotate(${rotate} 600 ${(y1 + y2) / 2})` });
  const parts = [
    path(cloudPath(250, 170, 110, 56, 8), filled('#ffffff', '#c9b79c', 7)),
    ellipse(600, 884, 380, 74, filled('#8bcf6a', line, 10)),
    path('M560 860L560 150Q560 120 600 120Q640 120 640 150L640 860Z', filled(dark, line, 11)),
    path('M584 200L584 840M616 240L616 820', ink('#a0662f', 5)),
    board(420, 980, 200, 300, true, -3), board(180, 760, 350, 450, false, 4), board(460, 1010, 500, 600, true, 2),
  ];
  for (let index = 0; index < 16; index++) {
    const gx = 260 + index * 44 + (next() - .5) * 20;
    parts.push(path(`M${gx} 860Q${gx - 8} 820 ${gx - 18} 800M${gx} 860Q${gx + 4} 816 ${gx + 14} 794`, ink('#4f9a3c', 7)));
  }
  for (const [fx, fy, color] of [[330, 840, '#ffffff'], [880, 850, '#ffd36e'], [760, 900, '#ffffff'], [420, 905, '#ffd36e']]) {
    parts.push(group([...Array.from({ length: 5 }, (_, index) => circle(fx + Math.cos(index * 1.256) * 14, fy + Math.sin(index * 1.256) * 14, 11, filled(color, line, 4))),
      circle(fx, fy, 8, { fill: '#ff9f43' })]));
  }
  for (const [cx, cy, size] of [[980, 140, 34], [1080, 420, 26], [150, 640, 24]]) parts.push(sparkle(cx, cy, size, filled('#ffd36e', line, 6)));
  return { width, height, svg: svg(width, height, parts) };
};

// 9. Crayon sky: a child-like crayon drawing on white paper.
const crayonSky = () => {
  const width = 1600, height = 800, next = random(97);
  const defs = grainFilter('crayon', .9, 1.9, 11);
  const parts = [rect(0, 0, width, height, { fill: '#fffdf7' })];
  const strokes = [];
  // Sky hatching.
  for (let index = 0; index < 70; index++) {
    const x = next() * width, y = next() * 330;
    strokes.push(path(`M${x.toFixed(1)} ${y.toFixed(1)}l${(60 + next() * 50).toFixed(1)} ${(-30 - next() * 20).toFixed(1)}`, { ...ink('#8ecae6', 9), opacity: '.55' }));
  }
  // Sun without a face, with scribbled fill and rays.
  const scribble = Array.from({ length: 60 }, (_, index) => {
    const angle = index * .9, radius = 96 * Math.sqrt((index + 1) / 60);
    return [300 + Math.cos(angle) * radius, 200 + Math.sin(angle) * radius];
  });
  strokes.push(circle(300, 200, 100, { fill: '#ffd95a' }), path(curve(scribble), ink('#ffc93c', 22)), path(curve(jitter(ellipsePoints(300, 200, 104, 104, 20), 4, next), true), ink('#f4a300', 10)));
  for (let index = 0; index < 12; index++) {
    const angle = index / 12 * Math.PI * 2;
    strokes.push(path(curve(jitter(linePoints([300 + Math.cos(angle) * 135, 200 + Math.sin(angle) * 135], [300 + Math.cos(angle) * 190, 200 + Math.sin(angle) * 190], 2), 4, next)), ink('#f4a300', 11)));
  }
  // Clouds.
  for (const [cx, cy, rx, ry] of [[790, 160, 120, 60], [1110, 110, 90, 46]]) {
    strokes.push(path(cloudPath(cx, cy, rx, ry, 8, next, .15), { fill: '#ffffff', stroke: '#5aa9e6', strokeWidth: 10, strokeLinejoin: 'round' }));
  }
  // Hills, back to front, then light grass hatching over both.
  strokes.push(path('M-20 610C200 470 420 450 640 560C760 620 840 640 900 650L900 820L-20 820Z', { fill: '#9ad27f' }));
  strokes.push(path('M-20 610C200 470 420 450 640 560C760 620 840 640 900 650', ink('#3f8f3a', 10)));
  strokes.push(path('M440 820C560 700 800 520 1100 480C1260 470 1460 560 1640 650L1640 820Z', { fill: '#6dbb5c' }));
  strokes.push(path('M440 820C560 700 800 520 1100 480C1260 470 1460 560 1640 650', ink('#2e7d32', 10)));
  for (let index = 0; index < 50; index++) {
    const x = next() * width, y = 600 + next() * 200;
    strokes.push(path(`M${x.toFixed(1)} ${y.toFixed(1)}l${(40 + next() * 30).toFixed(1)} ${(-18 - next() * 10).toFixed(1)}`, { ...ink('#3f8f3a', 8), opacity: '.4' }));
  }
  // Kite with a bowed tail.
  strokes.push(path('M1330 160L1400 260L1330 380L1260 260Z', { fill: '#e4572e', stroke: '#b23a1f', strokeWidth: 9, strokeLinejoin: 'round' }));
  strokes.push(path('M1330 160L1330 380M1260 260L1400 260', ink('#ffd36e', 8)));
  const tail = [[1330, 380], [1300, 430], [1340, 480], [1290, 530], [1320, 580], [1270, 630]];
  strokes.push(path(curve(tail), ink('#4a4752', 6)));
  for (const [[bx, by], color] of [[tail[1], '#2e86de'], [tail[3], '#ffc93c'], [tail[5], '#2e86de']]) {
    strokes.push(path(`M${bx - 26} ${by - 16}L${bx + 26} ${by + 16}L${bx + 26} ${by - 16}L${bx - 26} ${by + 16}Z`, { fill: color, stroke: color, strokeWidth: 4, strokeLinejoin: 'round' }));
  }
  // Flowers.
  for (const [fx, fy, color] of [[230, 640, '#ff8fa3'], [1430, 640, '#c084fc'], [1180, 700, '#ff8fa3'], [430, 700, '#ffc93c']]) {
    strokes.push(path(`M${fx} ${fy}L${fx} ${fy + 70}`, ink('#2e7d32', 8)));
    for (let index = 0; index < 5; index++) strokes.push(circle(fx + Math.cos(index * 1.256) * 20, fy + Math.sin(index * 1.256) * 20, 16, { fill: color }));
    strokes.push(circle(fx, fy, 12, { fill: '#ffc93c' }));
  }
  parts.push(group(strokes, { filter: 'url(#crayon)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 10. Cartoon rocket: a rounded rocket, a ringed planet and stars at night.
const rocketNight = () => {
  const width = 1600, height = 800, next = random(109), line = '#0b1028';
  const defs = '<linearGradient id="night" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0f1736"/><stop offset="1" stop-color="#24346f"/></linearGradient>';
  const parts = [rect(0, 0, width, height, { fill: 'url(#night)' })];
  for (let index = 0; index < 90; index++) {
    const x = next() * width, y = next() * height;
    if (Math.hypot(x - 1120, y - 360) < 260 || Math.hypot(x - 300, y - 230) < 200) continue;
    parts.push(circle(x, y, 1.6 + next() * 3.4, { fill: '#ffe7a3', opacity: (.5 + next() * .5).toFixed(2) }));
  }
  for (const [cx, cy, size] of [[620, 120, 26], [1500, 520, 30], [140, 520, 22], [880, 640, 18]]) parts.push(sparkle(cx, cy, size, { fill: '#ffe7a3' }));
  // Dotted flight path.
  for (let index = 0; index < 18; index++) {
    const t = index / 17;
    parts.push(circle(160 + t * 760, 760 - Math.sin(t * Math.PI * .9) * 220 - t * 60, 6, { fill: '#c9d1f2', opacity: '.55' }));
  }
  // Ringed planet: back ring, planet, front ring.
  parts.push(path('M120 260A190 46 -18 0 1 480 140', { ...ink('#ffd36e', 18), opacity: '.9' }));
  parts.push(circle(300, 230, 110, filled('#ff9e7a', line, 9)), path('M206 190Q300 170 392 196M196 250Q300 236 404 262', ink('#ffb899', 14)));
  parts.push(path('M120 260A190 46 -18 0 0 480 140', ink('#ffd36e', 18)), path('M120 260A190 46 -18 0 0 480 140', { fill: 'none', stroke: line, strokeWidth: 4, opacity: '.6' }));
  parts.push(circle(1430, 160, 52, filled('#6fe0c0', line, 8)), circle(1412, 146, 12, { fill: '#4bc4a4' }), circle(1450, 182, 8, { fill: '#4bc4a4' }));
  // Exhaust puffs trailing behind the rocket.
  for (const [cx, cy, radius] of [[900, 600, 46], [840, 650, 36], [790, 690, 28], [960, 640, 30], [740, 720, 20]]) parts.push(circle(cx, cy, radius, filled('#d9d4ff', line, 7)));
  // Rocket, drawn upright and tilted toward the top right.
  const rocket = [
    path('M-46 186Q0 330 46 186Z', filled('#ffa53b', line, 7)), path('M-24 190Q0 270 24 190Z', { fill: '#ffe066' }),
    path('M-90 70L-176 176L-156 214L-86 170Z', filled('#ff6b5b', line, 9)), path('M90 70L176 176L156 214L86 170Z', filled('#ff6b5b', line, 9)),
    path('M0 -232C90 -170 104 -60 96 40C92 100 88 150 80 186L-80 186C-88 150 -92 100 -96 40C-104 -60 -90 -170 0 -232Z', filled('#fff6e6', line, 10)),
    path('M0 -232C52 -196 76 -150 86 -112C30 -96 -30 -96 -86 -112C-76 -150 -52 -196 0 -232Z', filled('#ff6b5b', line, 9)),
    rect(-58, 186, 116, 28, { ...filled('#9aa5c7', line, 8), rx: 10 }),
    circle(0, -24, 54, filled('#ffd36e', line, 9)), circle(0, -24, 36, filled('#8fd3ff', line, 7)), path('M-18 -42A24 24 0 0 1 10 -50', ink('#ffffff', 8)),
    path('M-60 110L60 110', ink('#e7dccb', 10)),
  ];
  parts.push(group(rocket, { transform: 'translate(1120 360) rotate(35)' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

export const cartoonScenes = [
  { id: 'cartoon-doodle-shop', draw: doodleShop },
  { id: 'cartoon-comic-panels', draw: comicPanels },
  { id: 'cartoon-tag-buddy', draw: tagBuddy },
  { id: 'cartoon-sticker-sheet', draw: stickerSheet },
  { id: 'cartoon-chalkboard', draw: chalkboard },
  { id: 'cartoon-street-front', draw: streetFront },
  { id: 'cartoon-chat-bubbles', draw: chatBubbles },
  { id: 'cartoon-signposts', draw: signposts },
  { id: 'cartoon-crayon-sky', draw: crayonSky },
  { id: 'cartoon-rocket-night', draw: rocketNight },
];
