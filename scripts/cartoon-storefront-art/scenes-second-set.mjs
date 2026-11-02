// The second ten cartoon storefront drawings (owner approval 2026-11-03),
// written as code in this repository under the same originality rules as
// scenes.mjs. Avoided on purpose: puppets or characters on the stage;
// orange-and-white striped or blue-and-yellow fish and faces on sea life; a
// house lifted by balloons; blocks, mushrooms, pipes, coins or ghosts from
// well-known games; skulls and pirate hats on the map.
import {
  circle, cloudPath, curve, ellipse, filled, group, heartPath, ink, jitter, linePoints, path, polygon, random, rect,
  sparkle, starPoints, svg
} from './draw.mjs';

// 11. Puppet stage: an empty curtained stage with a spotlight in the middle.
const puppetStage = () => {
  const width = 1600, height = 900, line = '#2a0f1a', gold = '#f0c45c';
  const defs = `<radialGradient id="spot" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff3c4" stop-opacity=".6"/><stop offset="1" stop-color="#fff3c4" stop-opacity="0"/></radialGradient>`;
  const parts = [rect(0, 0, width, height, { fill: '#1d0d16' }), rect(200, 100, 1200, 660, { fill: '#4a1a2e' })];
  for (let x = 240; x < 1400; x += 80) parts.push(path(`M${x} 100L${x} 760`, { ...ink('#3d1426', 10), opacity: '.7' }));
  parts.push(ellipse(800, 450, 420, 360, { fill: 'url(#spot)' }));
  // Floor planks.
  parts.push(path('M120 740H1480L1600 900H0Z', filled('#8a5532', line, 6)));
  for (let index = 1; index < 9; index++) {
    const x = 120 + index * (1360 / 9);
    parts.push(path(`M${x} 742L${(x - 800) * 1.18 + 800} 900`, ink('#6e4026', 5)));
  }
  parts.push(ellipse(800, 800, 320, 46, { fill: '#fff3c4', opacity: '.35' }));
  parts.push(rect(0, 728, 1600, 20, filled('#5e3420', line, 5)), path('M0 731H1600', ink(gold, 5)));
  for (let x = 160; x < 1600; x += 160) parts.push(path(`M${x - 26} 748A26 20 0 0 0 ${x + 26} 748Z`, filled('#ffe9a8', line, 4)));
  // Tied-back curtains with folds.
  const curtain = (flip) => {
    const fx = (x) => flip ? width - x : x;
    const shape = `M${fx(0)} 0H${fx(380)}C${fx(350)} 220 ${fx(320)} 420 ${fx(250)} 560C${fx(215)} 640 ${fx(165)} 700 ${fx(130)} 770H${fx(0)}Z`;
    const folds = [80, 160, 240, 320].map((x, index) => path(`M${fx(x)} 0C${fx(x - 10)} 220 ${fx(x - 40 - index * 20)} 420 ${fx(x - 90 - index * 30)} 560`, ink('#8a1a2c', 12)));
    return group([path(shape, filled('#c0283a', line, 7)), ...folds, path(shape, ink(line, 7)),
      ellipse(fx(255), 560, 34, 18, filled(gold, line, 5)), path(`M${fx(255)} 578L${fx(245)} 640M${fx(262)} 578L${fx(270)} 636`, ink(gold, 6))]);
  };
  parts.push(curtain(false), curtain(true));
  // Scalloped valance with gold trim and tassels.
  let valance = 'M0 0H1600V96';
  for (let x = 1600; x > 0; x -= 100) valance += `A50 40 0 0 1 ${x - 100} 96`;
  parts.push(path(`${valance}Z`, filled('#a81f33', line, 7)));
  let trim = 'M1600 96';
  for (let x = 1600; x > 0; x -= 100) trim += `A50 40 0 0 1 ${x - 100} 96`;
  parts.push(path(trim, ink(gold, 8)));
  for (let x = 100; x < 1600; x += 100) parts.push(path(`M${x} 96L${x} 118`, ink(gold, 5)), ellipse(x, 126, 9, 12, filled(gold, line, 3)));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 12. Corkboard: pinned notes and tape around a calm centre for the photo.
const corkboard = () => {
  const width = 1600, height = 900, next = random(149), line = '#3b2a1a';
  const parts = [rect(0, 0, width, height, { fill: '#c8955f' })];
  for (let index = 0; index < 1100; index++) {
    parts.push(circle(next() * width, next() * height, 1.4 + next() * 2.6, { fill: ['#b07a46', '#dcae78', '#a56c3c'][index % 3], opacity: '.8' }));
  }
  const pin = (x, y, color) => group([ellipse(x + 4, y + 7, 13, 6, { fill: '#000000', opacity: '.18' }), circle(x, y, 15, filled(color, line, 4)), circle(x - 5, y - 5, 5, { fill: '#ffffff', opacity: '.7' })]);
  const note = (x, y, size, fill, rotate, pinColor) => group([
    rect(x + 8, y + 10, size, size * .92, { fill: '#000000', opacity: '.16' }),
    rect(x, y, size, size * .92, filled(fill, line, 4)),
    ...[.38, .54, .7].map((at, index) => path(`M${x + 24} ${y + size * at}H${x + size - 30 - index * 22}`, { ...ink('#8d8577', 6), opacity: '.6' })),
    pin(x + size / 2, y + 16, pinColor)], { transform: `rotate(${rotate} ${x + size / 2} ${y + size / 2})` });
  parts.push(note(90, 90, 200, '#fff3a0', -8, '#e5533d'), note(1310, 80, 190, '#cfe6ff', 6, '#3a7bd5'),
    note(150, 590, 180, '#ffd6e3', 5, '#f2b705'), note(1300, 600, 200, '#d4f5d0', -6, '#e5533d'));
  parts.push(rect(470, 70, 150, 40, { fill: '#7fd1c7', opacity: '.75', transform: 'rotate(-12 545 90)' }));
  parts.push(rect(1020, 790, 170, 40, { fill: '#ff9f80', opacity: '.75', transform: 'rotate(8 1105 810)' }));
  parts.push(group([path(polygon(starPoints(560, 760, 62, 28)), filled('#ffd84d', line, 4)), pin(560, 730, '#3a7bd5')]));
  parts.push(group([path(heartPath(1070, 150, 50), filled('#ff8fa3', line, 4)), pin(1070, 120, '#f2b705')]));
  return { width, height, svg: svg(width, height, parts) };
};

// 13. Treasure map: islands, a dotted trail and a compass on old paper.
const treasureMap = () => {
  const width = 1600, height = 800, next = random(163), line = '#6b4423';
  const defs = '<radialGradient id="age" cx="50%" cy="50%" r="70%"><stop offset=".55" stop-color="#c9a46a" stop-opacity="0"/><stop offset="1" stop-color="#b78c4f" stop-opacity=".55"/></radialGradient>';
  const parts = [rect(0, 0, width, height, { fill: '#f0dcae' })];
  for (let x = 100; x < width; x += 140) parts.push(path(`M${x} 0V${height}`, { ...ink('#dcc28e', 3) }));
  for (let y = 80; y < height; y += 140) parts.push(path(`M0 ${y}H${width}`, { ...ink('#dcc28e', 3) }));
  for (let index = 0; index < 26; index++) {
    const x = 80 + next() * 1440, y = 60 + next() * 680;
    if (Math.hypot(x - 380, y - 430) < 260 || Math.hypot(x - 1220, y - 360) < 200) continue;
    parts.push(path(`M${x} ${y}q14 -12 28 0t28 0`, ink('#7a9fb0', 5)));
  }
  const island = (cx, cy, rx, ry) => {
    const outline = curve(jitter(Array.from({ length: 16 }, (_, index) => {
      const angle = index / 16 * Math.PI * 2;
      return [cx + Math.cos(angle) * rx * (1 + (index % 3) * .08), cy + Math.sin(angle) * ry * (1 + (index % 2) * .1)];
    }), 8, next), true);
    return [path(outline, filled('#e6d39a', line, 7)), path(outline, { fill: '#cfe0a0', transform: `translate(${cx * .12} ${cy * .12}) scale(.88)` })];
  };
  parts.push(...island(380, 440, 250, 170), ...island(1220, 370, 170, 120));
  parts.push(path('M300 380L350 300L400 380Z', filled('#d9b98a', line, 6)), path('M360 400L420 310L480 400Z', filled('#d9b98a', line, 6)));
  parts.push(path('M470 520C480 470 476 430 462 400', ink('#8a5a2b', 12)));
  for (const angle of [-150, -110, -60, -20, 20]) {
    const radians = angle * Math.PI / 180;
    parts.push(path(`M462 398Q${462 + Math.cos(radians) * 50} ${398 + Math.sin(radians) * 50 - 20} ${462 + Math.cos(radians) * 90} ${398 + Math.sin(radians) * 90}`, ink('#4f8a3a', 12)));
  }
  parts.push(path('M500 500C700 640 900 600 1000 480C1080 390 1150 380 1205 370', { ...ink('#8a4b1c', 7), strokeDasharray: '2 18' }));
  parts.push(path('M1185 350L1225 390M1225 350L1185 390', ink('#c0392b', 12)));
  // Compass rose without letters.
  parts.push(circle(1440, 150, 86, filled('#f7e8c4', line, 5)), path(polygon(starPoints(1440, 150, 76, 16, 4)), filled('#c0392b', line, 4)),
    path(polygon(starPoints(1440, 150, 46, 12, 4, -Math.PI / 4)), filled('#e6d39a', line, 4)), circle(1440, 150, 9, { fill: line }));
  // A small sailboat.
  parts.push(path('M720 640H860L830 680H750Z', filled('#a0673a', line, 5)), path('M790 636V540L850 630Z', filled('#fffaf0', line, 5)), path('M786 636L740 620L786 580Z', filled('#ffffff', line, 5)));
  parts.push(rect(0, 0, width, height, { fill: 'url(#age)' }), rect(10, 10, width - 20, height - 20, { fill: 'none', stroke: '#b78c4f', strokeWidth: 6, strokeDasharray: '24 10' }));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 14. Party bunting: a garland of flags, balloons and confetti.
const partyBunting = () => {
  const width = 1600, height = 800, next = random(181), line = '#2a1d33';
  const colors = ['#ff8fa3', '#ffd36e', '#7fd1ff', '#9be3b0', '#c7a6ff'];
  const parts = [rect(0, 0, width, height, { fill: '#fff4f6' })];
  for (let y = 30; y < height; y += 60) for (let x = 30 + (y / 60 % 2) * 30; x < width; x += 60) parts.push(circle(x, y, 5, { fill: '#ffe3ea' }));
  const garland = (start, control, end, flags, size) => {
    const at = (t) => [(1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t * t * end[0], (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t * t * end[1]];
    const items = [path(`M${start.join(' ')}Q${control.join(' ')} ${end.join(' ')}`, ink(line, 5))];
    for (let index = 0; index < flags; index++) {
      const [x1, y1] = at((index + .1) / flags), [x2, y2] = at((index + .9) / flags), [mx, my] = at((index + .5) / flags);
      items.push(path(`M${x1} ${y1}L${x2} ${y2}L${mx} ${my + size}Z`, filled(colors[index % colors.length], line, 4)));
    }
    return items;
  };
  parts.push(...garland([-20, 40], [800, 300], [1620, 40], 16, 90));
  parts.push(...garland([-20, 260], [180, 360], [380, 250], 4, 60), ...garland([1220, 250], [1420, 360], [1620, 260], 4, 60));
  const balloon = (cx, cy, rx, color) => group([
    path(`M${cx} ${cy + rx * 1.2}C${cx - 18} ${cy + rx * 1.6} ${cx + 22} ${cy + rx * 1.9} ${cx - 6} ${cy + rx * 2.5}`, ink(line, 4)),
    ellipse(cx, cy, rx, rx * 1.2, filled(color, line, 5)), path(`M${cx - 12} ${cy + rx * 1.2}L${cx + 12} ${cy + rx * 1.2}L${cx} ${cy + rx * 1.32}Z`, filled(color, line, 4)),
    ellipse(cx - rx * .35, cy - rx * .45, rx * .16, rx * .3, { fill: '#ffffff', opacity: '.7' })]);
  parts.push(balloon(170, 470, 70, '#ff8fa3'), balloon(300, 420, 60, '#7fd1ff'), balloon(1320, 430, 64, '#ffd36e'), balloon(1450, 480, 72, '#9be3b0'));
  for (let index = 0; index < 90; index++) {
    const x = next() * width, y = 120 + next() * 660, color = colors[index % colors.length];
    if (Math.hypot(x - 800, y - 700) < 230) continue;
    parts.push(index % 2 ? rect(x, y, 16, 9, { fill: color, transform: `rotate(${Math.round(next() * 180)} ${x} ${y})` }) : circle(x, y, 6, { fill: color }));
  }
  for (const [x, y, flip] of [[560, 420, 1], [1040, 400, -1]]) {
    parts.push(path(`M${x} ${y}c${flip * 30} -30 ${flip * 60} 30 ${flip * 90} 0s${flip * 60} 30 ${flip * 90} 0`, ink('#c7a6ff', 7)));
  }
  return { width, height, svg: svg(width, height, parts) };
};

// A jigsaw piece: each edge is flat (0), a knob out (1) or a socket in (-1).
const pieceEdge = ([x1, y1], [x2, y2], tab, size) => {
  if (!tab) return `L${x2} ${y2}`;
  const dx = (x2 - x1) / size, dy = (y2 - y1) / size;
  const nx = dy * tab, ny = -dx * tab;
  const p = (along, out) => `${(x1 + dx * along * size + nx * out * size).toFixed(1)} ${(y1 + dy * along * size + ny * out * size).toFixed(1)}`;
  return `L${p(.36, 0)}C${p(.42, 0)} ${p(.42, .08)} ${p(.38, .14)}C${p(.32, .24)} ${p(.42, .3)} ${p(.5, .3)}C${p(.58, .3)} ${p(.68, .24)} ${p(.62, .14)}C${p(.58, .08)} ${p(.58, 0)} ${p(.64, 0)}L${x2} ${y2}`;
};
const piecePath = (x, y, size, [top, right, bottom, left]) => {
  const corners = [[x, y], [x + size, y], [x + size, y + size], [x, y + size]];
  return `M${x} ${y}${pieceEdge(corners[0], corners[1], top, size)}${pieceEdge(corners[1], corners[2], right, size)}${pieceEdge(corners[2], corners[3], bottom, size)}${pieceEdge(corners[3], corners[0], left, size)}Z`;
};

// 15. Jigsaw: three pieces fitted together and a fourth on its way in.
const jigsaw = () => {
  const width = 1200, height = 960, line = '#1c2340', size = 250;
  const parts = [];
  const [x, y] = [330, 380];
  parts.push(path(piecePath(x, y, size, [0, 1, -1, 0]), filled('#ffd9a8', line, 10)));
  parts.push(path(piecePath(x, y + size, size, [1, -1, 0, 0]), filled('#c4ecd4', line, 10)));
  parts.push(path(piecePath(x + size, y + size, size, [-1, 0, 0, 1]), filled('#cfe0ff', line, 10)));
  parts.push(group(path(piecePath(x + size, y, size, [0, 0, 1, -1]), filled('#ffd0dc', line, 10)), { transform: `translate(90 -150) rotate(14 ${x + size * 1.5} ${y + size / 2})` }));
  for (const [x1, y1, x2, y2] of [[640, 560, 700, 500], [700, 600, 770, 530], [770, 610, 830, 550]]) parts.push(path(`M${x1} ${y1}L${x2} ${y2}`, ink(line, 9)));
  for (const [cx, cy, s] of [[200, 280, 40], [1020, 620, 34], [240, 860, 26], [1060, 180, 24]]) parts.push(sparkle(cx, cy, s, filled('#ffd36e', line, 6)));
  return { width, height, svg: svg(width, height, parts) };
};

// 16. Pixel landscape: an 8-bit style view drawn on a 32px grid.
const pixelLand = () => {
  const width = 1600, height = 800, cell = 32, next = random(197);
  const cells = [];
  const put = (column, row, color) => cells.push(rect(column * cell, row * cell, cell, cell, { fill: color }));
  for (let row = 0; row < 25; row++) for (let column = 0; column < 50; column++) put(column, row, row < 6 ? '#9fd3ff' : row < 11 ? '#b7deff' : '#cfe8ff');
  for (let row = 2; row <= 8; row++) for (let column = 5; column <= 11; column++) {
    const distance = Math.hypot(column - 8, row - 5);
    if (distance <= 3.2) put(column, row, distance > 2.4 ? '#ff9f1c' : '#ffd23f');
  }
  const cloud = (column, row, length) => {
    for (let index = 0; index < length; index++) put(column + index, row + 1, '#ffffff');
    for (let index = 1; index < length - 1; index++) put(column + index, row, '#ffffff');
    for (let index = 0; index < length; index++) put(column + index, row + 2, '#e6f2ff');
  };
  cloud(19, 3, 6); cloud(35, 5, 5); cloud(44, 2, 4);
  const mountain = (peak, top, base, color, snow) => {
    for (let row = top; row <= base; row++) {
      const half = row - top;
      for (let column = peak - half; column <= peak + half; column++) put(column, row, row - top < 2 && snow ? '#ffffff' : color);
    }
  };
  mountain(15, 9, 17, '#8f9bd9', true); mountain(31, 8, 17, '#7c88cf', true); mountain(45, 10, 17, '#8f9bd9', true); mountain(24, 12, 17, '#a3aee3', false);
  for (let row = 16; row < 25; row++) for (let column = 0; column < 50; column++) put(column, row, row === 16 ? '#4fa037' : row < 20 ? '#6cc04a' : '#5bb540');
  const pine = (column, row) => {
    for (let level = 0; level < 4; level++) for (let index = -level; index <= level; index++) put(column + index, row + level, level % 2 ? '#2a7d45' : '#2f8f4e');
    put(column, row + 4, '#7a4a2a'); put(column, row + 5, '#7a4a2a');
  };
  for (const [column, row] of [[4, 12], [9, 13], [38, 12], [42, 13], [47, 12]]) pine(column, row);
  for (let index = 0; index < 28; index++) {
    const column = Math.floor(next() * 50), row = 18 + Math.floor(next() * 7);
    if (column > 18 && column < 32 && row > 20) continue;
    put(column, row, index % 2 ? '#ff6b8b' : '#ffd23f');
  }
  return { width, height, svg: svg(width, height, `<g shape-rendering="crispEdges">${cells.join('')}</g>`) };
};

// 17. Rainy day: an umbrella under a rain cloud, puddles and a small rainbow.
const rainyDay = () => {
  const width = 1200, height = 960, next = random(211), line = '#15283d';
  const drop = (x, y, size) => path(`M${x} ${y - size}C${x + size * .7} ${y - size * .1} ${x + size * .7} ${y + size * .6} ${x} ${y + size * .6}C${x - size * .7} ${y + size * .6} ${x - size * .7} ${y - size * .1} ${x} ${y - size}Z`, filled('#5aa9e6', line, 4));
  const parts = [path(cloudPath(600, 170, 300, 110, 9), filled('#c9d8e8', line, 9))];
  for (let index = 0; index < 22; index++) {
    const x = 160 + next() * 880, y = 300 + next() * 560;
    if ((Math.abs(x - 600) < 300 && y < 700) || (x > 860 && y > 680)) continue;
    parts.push(drop(x, y, 18 + next() * 8));
  }
  parts.push(ellipse(450, 860, 170, 32, filled('#bfe0f7', line, 6)), ellipse(450, 860, 90, 14, ink('#8cc2e8', 4)));
  parts.push(ellipse(820, 890, 120, 24, filled('#bfe0f7', line, 6)), ellipse(820, 890, 60, 10, ink('#8cc2e8', 4)));
  for (const [color, radius] of [['#ff8fa3', 120], ['#ffd36e', 96], ['#7fd1ff', 72]]) parts.push(path(`M${1040 - radius} 860A${radius} ${radius} 0 0 1 ${1040 + radius} 860`, ink(color, 22)));
  // Umbrella: a dome with a scalloped rim, alternate panels and a hooked handle.
  const [cx, cy, radius, segments] = [600, 570, 260, 4];
  const rimX = (index) => cx + radius - index * 2 * radius / segments;
  let canopy = `M${cx - radius} ${cy}A${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`;
  for (let index = 1; index <= segments; index++) canopy += `A${radius / segments} ${radius / segments * .6} 0 0 0 ${rimX(index)} ${cy}`;
  canopy += 'Z';
  const defs = `<clipPath id="canopy"><path d="${canopy}"/></clipPath>`;
  parts.push(path(`M${cx} ${cy}V790Q${cx} 840 ${cx - 46} 840Q${cx - 86} 840 ${cx - 86} 802`, ink(line, 14)));
  // Each panel is bounded by the same curved ribs that are drawn on top; the
  // outer two also sweep round the dome's sides.
  const tip = `${cx} ${cy - radius}`;
  const rib = (index) => `Q${(cx + rimX(index)) / 2} ${cy - radius * .45} ${rimX(index)} ${cy}`;
  const ribBack = (index) => `Q${(cx + rimX(index)) / 2} ${cy - radius * .45} ${tip}`;
  const panels = Array.from({ length: segments }, (_, index) => {
    const start = index === 0 ? `M${tip}L${cx + radius * 2} ${cy - radius}L${cx + radius * 2} ${cy + 80}` : `M${tip}${rib(index)}L${rimX(index)} ${cy + 80}`;
    const end = index === segments - 1 ? `L${cx - radius * 2} ${cy + 80}L${cx - radius * 2} ${cy - radius}Z` : `L${rimX(index + 1)} ${cy + 80}L${rimX(index + 1)} ${cy}${ribBack(index + 1)}Z`;
    return path(start + end, { fill: index % 2 ? '#fff4e6' : '#ff7a59' });
  });
  parts.push(group(panels, { clipPath: 'url(#canopy)' }));
  for (let index = 1; index < segments; index++) parts.push(path(`M${tip}${rib(index)}`, ink(line, 6)));
  parts.push(path(canopy, { fill: 'none', stroke: line, strokeWidth: 10, strokeLinejoin: 'round' }), circle(cx, cy - radius - 14, 14, filled('#ff7a59', line, 6)));
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 18. Hot-air balloons: striped balloons with baskets among clouds.
const hotAirBalloons = () => {
  const width = 1200, height = 960, line = '#2b1f1a';
  const defs = [];
  const parts = [path(cloudPath(980, 760, 130, 60, 8), filled('#ffffff', '#d9c7bb', 7)), path(cloudPath(200, 260, 110, 52, 8), filled('#ffffff', '#d9c7bb', 7))];
  const balloon = (id, cx, cy, r, colors) => {
    const envelope = `M${cx} ${cy - r}C${cx + r * 1.35} ${cy - r} ${cx + r * 1.15} ${cy + r * .55} ${cx + r * .3} ${cy + r * 1.15}L${cx - r * .3} ${cy + r * 1.15}C${cx - r * 1.15} ${cy + r * .55} ${cx - r * 1.35} ${cy - r} ${cx} ${cy - r}Z`;
    defs.push(`<clipPath id="${id}"><path d="${envelope}"/></clipPath>`);
    const stripes = Array.from({ length: 5 }, (_, index) => ellipse(cx, cy, r * (1.25 - index * .25), r * 1.5, { fill: colors[index % 2] }));
    const basketY = cy + r * 1.55;
    return group([
      path(`M${cx - r * .28} ${cy + r * 1.15}L${cx - r * .22} ${basketY}M${cx + r * .28} ${cy + r * 1.15}L${cx + r * .22} ${basketY}`, ink(line, Math.max(4, r * .03))),
      group(stripes, { clipPath: `url(#${id})` }), path(envelope, { fill: 'none', stroke: line, strokeWidth: Math.max(6, r * .05), strokeLinejoin: 'round' }),
      path(`M${cx - r * .3} ${cy + r * 1.15}H${cx + r * .3}`, ink(line, Math.max(5, r * .045))),
      rect(cx - r * .26, basketY, r * .52, r * .34, { ...filled('#c08552', line, Math.max(4, r * .035)), rx: r * .05 }),
      path(`M${cx - r * .26} ${basketY + r * .12}H${cx + r * .26}M${cx - r * .26} ${basketY + r * .23}H${cx + r * .26}`, ink('#8a5a2b', Math.max(3, r * .025)))]);
  };
  parts.push(balloon('balloon-a', 540, 330, 220, ['#ff8fa3', '#ffe08a']), balloon('balloon-b', 960, 230, 120, ['#7fd1ff', '#ffffff']), balloon('balloon-c', 220, 600, 95, ['#9be3b0', '#c7a6ff']));
  return { width, height, svg: svg(width, height, parts, defs.join('')) };
};

// 19. Under the sea: seaweed, coral and round fish around open water.
const underTheSea = () => {
  const width = 1600, height = 900, next = random(227), line = '#04202c';
  const defs = '<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d5a74"/><stop offset="1" stop-color="#062433"/></linearGradient>';
  const parts = [rect(0, 0, width, height, { fill: 'url(#water)' })];
  for (const [x, spread] of [[300, 120], [760, 160], [1260, 130]]) parts.push(path(`M${x - 40} 0H${x + 40}L${x + spread} 900H${x - spread}Z`, { fill: '#ffffff', opacity: '.05' }));
  parts.push(path('M0 800C200 770 400 820 620 790C860 760 1080 820 1320 785C1450 770 1540 790 1600 780V900H0Z', filled('#c8b27e', line, 5)));
  for (let index = 0; index < 60; index++) parts.push(circle(next() * width, 820 + next() * 70, 2 + next() * 3, { fill: '#a8915e' }));
  const weed = (x, height, color, sway) => path(curve(Array.from({ length: 7 }, (_, index) => [x + Math.sin(index * 1.2) * sway, 820 - index * height / 6])), { ...ink(color, 26) });
  parts.push(weed(110, 420, '#2fa37a', 26), weed(190, 330, '#46c08f', 20), weed(270, 260, '#2fa37a', 18), weed(1340, 300, '#46c08f', 22), weed(1420, 410, '#2fa37a', 26), weed(1500, 280, '#46c08f', 18));
  const coral = (x, color) => group([path(`M${x} 820V700M${x} 740L${x - 50} 670M${x} 720L${x + 46} 650M${x - 50} 670L${x - 70} 620M${x + 46} 650L${x + 70} 610`, ink(line, 30)),
    path(`M${x} 820V700M${x} 740L${x - 50} 670M${x} 720L${x + 46} 650M${x - 50} 670L${x - 70} 620M${x + 46} 650L${x + 70} 610`, ink(color, 20))]);
  parts.push(coral(420, '#ff8fa3'), coral(1170, '#ffb37a'));
  parts.push(path(polygon(starPoints(1260, 805, 40, 18)), filled('#ffb37a', line, 5)));
  const fish = (cx, cy, size, color, dir) => group([
    path(`M${cx - dir * size * .9} ${cy}L${cx - dir * size * 1.5} ${cy - size * .5}L${cx - dir * size * 1.5} ${cy + size * .5}Z`, filled(color, line, 5)),
    ellipse(cx, cy, size, size * .7, filled(color, line, 5)), circle(cx + dir * size * .45, cy - size * .12, size * .16, { fill: '#ffffff' }),
    circle(cx + dir * size * .5, cy - size * .12, size * .08, { fill: line })]);
  parts.push(fish(360, 250, 50, '#b69cff', 1), fish(1260, 290, 44, '#ffe066', -1), fish(1100, 610, 30, '#7fe3d0', -1), fish(560, 620, 34, '#ffb37a', 1));
  for (let index = 0; index < 24; index++) {
    const x = [520, 1080, 230, 1400][index % 4] + (next() - .5) * 60, y = 760 - (index / 4) * 110 - next() * 40;
    parts.push(circle(x, y, 6 + next() * 10, { fill: 'none', stroke: '#bfe9ff', strokeWidth: 4, opacity: '.7' }));
  }
  return { width, height, svg: svg(width, height, parts, defs) };
};

// 20. Tiny town: little houses along a winding road over the hills.
const tinyTown = () => {
  const width = 1600, height = 800, line = '#1f2a1c';
  const parts = [rect(0, 0, width, height, { fill: '#dff0ff' })];
  parts.push(path(cloudPath(300, 120, 110, 46, 8), filled('#ffffff', '#c6dbea', 6)), path(cloudPath(1250, 90, 90, 40, 8), filled('#ffffff', '#c6dbea', 6)));
  parts.push(path('M0 420C300 330 520 380 800 370C1080 360 1300 320 1600 400V800H0Z', filled('#b9dca0', line, 5)));
  parts.push(path('M0 560C260 470 520 520 800 500C1080 480 1340 470 1600 540V800H0Z', filled('#8fcb72', line, 5)));
  parts.push(path('M660 800C700 700 860 640 830 560C810 500 760 460 790 400L812 400C800 460 850 500 870 560C900 650 820 720 940 800Z', filled('#8a8f99', line, 5)));
  parts.push(path('M800 790C800 700 870 650 850 570C835 510 790 470 800 404', { ...ink('#ffe066', 6), strokeDasharray: '22 18' }));
  const house = (x, y, w, h, wall, roof) => group([rect(x, y, w, h, filled(wall, line, 5)), path(`M${x - w * .12} ${y}L${x + w / 2} ${y - h * .65}L${x + w * 1.12} ${y}Z`, filled(roof, line, 5)),
    rect(x + w * .38, y + h * .45, w * .24, h * .55, filled('#7a4a2a', line, 4)), rect(x + w * .1, y + h * .2, w * .2, w * .2, filled('#cfe8f0', line, 3)),
    rect(x + w * .7, y + h * .2, w * .2, w * .2, filled('#cfe8f0', line, 3))]);
  const tree = (x, y, r) => group([rect(x - r * .12, y, r * .24, r * .9, filled('#8a5a2b', line, 4)), circle(x, y - r * .2, r, filled('#4caf6a', line, 5))]);
  parts.push(house(620, 380, 70, 50, '#fff1e0', '#e4572e'), house(900, 370, 64, 46, '#e0f0ff', '#3a7bd5'), tree(560, 400, 26), tree(1000, 390, 24));
  parts.push(house(420, 470, 110, 80, '#ffe0e6', '#7a5af8'), house(1060, 450, 120, 84, '#e8f5d8', '#2e9e6a'), tree(320, 500, 40), tree(1240, 480, 40));
  parts.push(house(130, 580, 170, 120, '#fff6d6', '#e4572e'), house(1300, 590, 170, 120, '#e0f0ff', '#d9534f'), tree(380, 640, 52), tree(1180, 650, 52));
  return { width, height, svg: svg(width, height, parts) };
};

export const secondCartoonScenes = [
  { id: 'cartoon-puppet-stage', draw: puppetStage },
  { id: 'cartoon-corkboard', draw: corkboard },
  { id: 'cartoon-treasure-map', draw: treasureMap },
  { id: 'cartoon-party-bunting', draw: partyBunting },
  { id: 'cartoon-jigsaw', draw: jigsaw },
  { id: 'cartoon-pixel-land', draw: pixelLand },
  { id: 'cartoon-rainy-day', draw: rainyDay },
  { id: 'cartoon-hot-air-balloons', draw: hotAirBalloons },
  { id: 'cartoon-under-the-sea', draw: underTheSea },
  { id: 'cartoon-tiny-town', draw: tinyTown },
];
