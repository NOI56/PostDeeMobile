import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Exercise the shipped browser script without adding a DOM dependency or using
// real authentication, databases, mutation endpoints, or wall-clock sleeps.
class TestNode {
  children: TestNode[] = [];
  text = '';
  get textContent(): string { return this.text + this.children.map(child => child.textContent).join(''); }
  set textContent(value: string) { this.text = value; this.children = []; }
  append(...children: (TestNode | string)[]) {
    this.children.push(...children.map(child => typeof child === 'string' ? Object.assign(new TestNode(), { text: child }) : child));
  }
  replaceChildren(...children: TestNode[]) { this.children = children; }
}
class TestElement extends TestNode {
  attributes = new Map<string, string>();
  listeners = new Map<string, ((event: Record<string, unknown>) => unknown)[]>();
  value = '';
  disabled = false;
  inert = false;
  selectionStart = 0;
  selectionEnd = 0;
  constructor(readonly tagName: string, private readonly document: TestDocument) { super(); }
  get className() { return this.attributes.get('class') ?? ''; }
  set className(value: string) { this.attributes.set('class', value); }
  classList = {
    add: (value: string) => { this.className = [...new Set([...this.className.split(' '), value])].join(' ').trim(); },
    remove: (value: string) => { this.className = this.className.split(' ').filter(item => item !== value).join(' '); },
    contains: (value: string) => this.className.split(' ').includes(value),
    toggle: (value: string, force?: boolean) => {
      const add = force ?? !this.classList.contains(value);
      if (add) this.classList.add(value); else this.classList.remove(value);
      return add;
    }
  };
  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
    if (name === 'value') this.value = value;
    if (name === 'disabled') this.disabled = true;
  }
  getAttribute(name: string) { return this.attributes.get(name) ?? null; }
  removeAttribute(name: string) { this.attributes.delete(name); if (name === 'disabled') this.disabled = false; }
  addEventListener(name: string, listener: (event: Record<string, unknown>) => unknown) {
    this.listeners.set(name, [...this.listeners.get(name) ?? [], listener]);
  }
  async emit(name: string) {
    for (const listener of this.listeners.get(name) ?? []) await listener({ target: this, preventDefault() {} });
  }
  async click() {
    if (this.disabled) return;
    if (this.tagName === 'a') this.document.downloads.push(this.getAttribute('download') ?? '');
    await this.emit('click');
  }
  focus() { this.document.activeElement = this; }
  matches(selector: string) {
    const notDisabled = selector.includes(':not(:disabled)');
    selector = selector.replace(':not(:disabled)', '');
    if (notDisabled && this.disabled) return false;
    const attribute = selector.match(/^\[([^=\]]+)(?:=["']?([^"'\]]+)["']?)?\]$/);
    if (attribute) return attribute[2] ? this.getAttribute(attribute[1]) === attribute[2] : this.attributes.has(attribute[1]);
    if (selector.startsWith('.')) return this.classList.contains(selector.slice(1));
    if (selector.startsWith('#')) return this.getAttribute('id') === selector.slice(1);
    return this.tagName === selector.toLowerCase();
  }
  querySelectorAll(selector: string): TestElement[] {
    const descendants = (node: TestNode): TestElement[] => node.children.flatMap(child => child instanceof TestElement ? [child, ...descendants(child)] : descendants(child));
    return descendants(this).filter(element => selector.split(',').some(part => element.matches(part.trim())));
  }
  querySelector(selector: string) { return this.querySelectorAll(selector)[0] ?? null; }
  setCustomValidity() {}
  reportValidity() { return true; }
}
class TestDocument {
  visibilityState = 'visible';
  activeElement: TestElement | null = null;
  downloads: string[] = [];
  listeners = new Map<string, (() => unknown)[]>();
  body = new TestElement('body', this);
  app = new TestElement('div', this);
  constructor() { this.app.setAttribute('id', 'app'); this.body.append(this.app); }
  get hidden() { return this.visibilityState !== 'visible'; }
  createElement(tag: string) { return new TestElement(tag, this); }
  createElementNS(_namespace: string, tag: string) { return this.createElement(tag); }
  createTextNode(value: string) { return Object.assign(new TestNode(), { text: value }); }
  querySelector(selector: string) { return selector === '#app' ? this.app : this.body.querySelector(selector); }
  addEventListener(name: string, listener: () => unknown) { this.listeners.set(name, [...this.listeners.get(name) ?? [], listener]); }
  async visibility(value: 'visible' | 'hidden') {
    this.visibilityState = value;
    for (const listener of this.listeners.get('visibilitychange') ?? []) await listener();
  }
}
type Reply = { ok: boolean; status: number; json(): Promise<unknown>; text(): Promise<string> };
const reply = (data: unknown, status = 200): Reply => ({ ok: status < 400, status, json: async () => data, text: async () => String(data) });
const deferred = <T>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; };
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
const member = { id: 'fixture-member', email: 'member@example.com', paidPlan: 'BASIC', displayName: 'Fixture member', trial: null };
const page = (extra: Record<string, unknown> = {}) => ({ rows: [member], total: 1, asOf: new Date().toISOString(), checkedAt: new Date().toISOString(), ...extra });

async function browser(fixtureMember: Record<string, unknown> = member, role = 'OWNER') {
  const document = new TestDocument();
  const requests: { path: string; body: Record<string, unknown>; signal: AbortSignal }[] = [];
  let viewReply = async (_body: Record<string, unknown>): Promise<Reply> => reply(page());
  let trialReply = async (): Promise<Reply> => reply({ status: 'ok' });
  let deletionReply = async (): Promise<Reply> => reply({ status: 'ok', deletion: { status: 'COMPLETED' } });
  let pendingReply = async (): Promise<Reply> => reply({ count: 0, checkedAt: new Date().toISOString() });
  const fetch = vi.fn(async (url: string, options: { body?: string; signal: AbortSignal }) => {
    if (url === '/admin/config') return reply({ previewToken: 'fixture-owner', environment: 'LOCAL' });
    const path = url.replace('/admin/api/', ''); const body = JSON.parse(options?.body ?? '{}');
    requests.push({ path, body, signal: options.signal });
    if (path === 'session') return reply({ role, environment: 'LOCAL' });
    if (path === 'member') return reply({ member: fixtureMember });
    if (path === 'trials') return trialReply();
    if (path === 'account-deletions') return deletionReply();
    if (path === 'support/pending-count') return pendingReply();
    if (path === 'support/thread') return reply({ thread: { userId: 'fixture-member', status: 'WAITING_TEAM',
      botEnabled: true, teamRequested: false, lastMessageId: 'member-message', lastMessageAt: new Date().toISOString(), lastSender: 'MEMBER' },
      member: fixtureMember, messages: [], hasEarlier: false });
    if (path === 'support/reply') return reply({ message: { id: body.id, body: body.body, sender: 'TEAM', createdAt: new Date().toISOString() } });
    if (path === 'support/close') return reply({ thread: { status: 'CLOSED', lastMessageId: body.lastMessageId } });
    if (path === 'incidents') return reply({ status: 'ok', incident: { ...body, resolvedAt: new Date().toISOString() } });
    if (path === 'view') return viewReply(body);
    throw new Error(`Unexpected fixture request ${path}`);
  });
  const source = await readFile(new URL('./web/admin.js', import.meta.url), 'utf8');
  const context: Record<string, unknown> = { document, Node: TestNode, fetch, AbortController, Date, Intl, Blob,
    URL: { createObjectURL: vi.fn(() => 'blob:fixture'), revokeObjectURL: vi.fn() }, crypto: { randomUUID: () => 'fixture-request' },
    setTimeout, clearTimeout, setInterval, clearInterval, console };
  await runInNewContext(`(async () => { ${source}\n globalThis.controls = { login, load, navigate, openMember, startTrial, submitTrial, startDeletion, submitDeletion, downloadCsv, logout, openChat, submitReply, closeThread, refreshSupportCount }; })()`, context);
  const controls = context.controls as Record<string, (...args: unknown[]) => Promise<void>>;
  await controls.login(); await flush();
  return { document, controls, requests, views: () => requests.filter(request => request.path === 'view'),
    setViewReply: (handler: typeof viewReply) => { viewReply = handler; }, setTrialReply: (handler: typeof trialReply) => { trialReply = handler; },
    setDeletionReply: (handler: typeof deletionReply) => { deletionReply = handler; },
    setPendingReply: (handler: typeof pendingReply) => { pendingReply = handler; },
    pendingReads: () => requests.filter(request => request.path === 'support/pending-count'),
    button: (text: string) => { const button = document.app.querySelectorAll('button').find(item => item.textContent === text); if (!button) throw new Error(`Missing button: ${text}`); return button; } };
}

describe('administrator pending support badge', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-29T00:00:00Z')); });
  afterEach(() => { vi.useRealTimers(); });

  it('polls the pending thread count independently without replacing the current view', async () => {
    const ui = await browser(); const content = ui.document.app.querySelector('.content');
    expect(ui.pendingReads()).toHaveLength(1);
    expect(ui.document.app.querySelector('.support-badge')!.getAttribute('hidden')).not.toBeNull();
    ui.setPendingReply(async () => reply({ count: 3, checkedAt: new Date().toISOString() }));
    await vi.advanceTimersByTimeAsync(30000);
    const badge = ui.document.app.querySelector('.support-badge')!;
    expect(badge.textContent).toBe('3'); expect(badge.getAttribute('aria-label')).toContain('รอทีมงานตอบ');
    expect(ui.document.app.querySelector('.content')).toBe(content); expect(ui.views()).toHaveLength(1);
    ui.setPendingReply(async () => reply({ count: 0, checkedAt: new Date().toISOString() }));
    await ui.controls.refreshSupportCount();
    expect(badge.getAttribute('hidden')).not.toBeNull();
  });

  it('keeps the search, filters and a chat reply draft while the badge changes', async () => {
    const ui = await browser(); await ui.controls.navigate('posts');
    const search = ui.document.app.querySelector('[data-focus=search]')!;
    search.value = 'member search'; search.focus(); await search.emit('input');
    ui.setPendingReply(async () => reply({ count: 4 })); await ui.controls.refreshSupportCount();
    expect(ui.document.app.querySelector('[data-focus=search]')).toBe(search); expect(search.value).toBe('member search');
    await ui.controls.openChat('fixture-member');
    const drawer = ui.document.app.querySelector('.chat-drawer')!;
    const replyInput = drawer.querySelector('textarea')!;
    replyInput.value = 'คำตอบที่ยังไม่ส่ง'; await replyInput.emit('input');
    ui.setPendingReply(async () => reply({ count: 7 })); await ui.controls.refreshSupportCount();
    expect(ui.document.app.querySelector('.chat-drawer')).toBe(drawer);
    expect(drawer.querySelector('textarea')).toBe(replyInput); expect(replyInput.value).toBe('คำตอบที่ยังไม่ส่ง');
    expect(ui.document.app.querySelector('.support-badge')!.textContent).toBe('7');
    expect(ui.requests.some(request => request.path === 'support/reply')).toBe(false);
  });

  it('coalesces a slow count read and quietly preserves the last count after errors', async () => {
    const ui = await browser(); ui.setPendingReply(async () => reply({ count: 2 })); await ui.controls.refreshSupportCount();
    const waiting = deferred<Reply>(); ui.setPendingReply(() => waiting.promise);
    const read = ui.controls.refreshSupportCount(); await flush();
    const reads = ui.pendingReads().length;
    await ui.controls.refreshSupportCount(); expect(ui.pendingReads()).toHaveLength(reads);
    waiting.resolve(reply({ count: 9 })); await read;
    ui.setPendingReply(async () => reply({ code: 'ADMIN_SUPPORT_UNAVAILABLE' }, 503)); await ui.controls.refreshSupportCount();
    const badge = ui.document.app.querySelector('.support-badge')!;
    expect(badge.textContent).toBe('9'); expect(badge.classList.contains('stale')).toBe(true);
    expect(badge.getAttribute('title')).toContain('ยังอัปเดต');
    expect(ui.document.app.querySelector('.error')).toBeNull();
  });

  it('does not present an invalid or failed first response as zero pending chats', async () => {
    const ui = await browser(); ui.setPendingReply(async () => reply({ count: -1 })); await ui.controls.refreshSupportCount();
    const badge = ui.document.app.querySelector('.support-badge')!;
    expect(badge.textContent).toBe('!'); expect(badge.getAttribute('hidden')).toBeNull();
    expect(badge.getAttribute('aria-label')).toContain('ยังอัปเดต');
    ui.setPendingReply(async () => reply({ count: 105 })); await ui.controls.refreshSupportCount();
    expect(badge.textContent).toBe('99+'); expect(badge.getAttribute('aria-label')).toContain('105');
    expect(badge.classList.contains('stale')).toBe(false);
  });

  it('pauses hidden tabs, aborts an old read, and refreshes immediately when visible', async () => {
    const ui = await browser(); const waiting = deferred<Reply>(); ui.setPendingReply(() => waiting.promise);
    const oldRead = ui.controls.refreshSupportCount(); await flush(); const pending = ui.pendingReads().at(-1)!;
    await ui.document.visibility('hidden'); expect(pending.signal.aborted).toBe(true);
    const reads = ui.pendingReads().length; await vi.advanceTimersByTimeAsync(90000); expect(ui.pendingReads()).toHaveLength(reads);
    ui.setPendingReply(async () => reply({ count: 4 })); await ui.document.visibility('visible'); await flush();
    waiting.resolve(reply({ count: 80 })); await oldRead;
    expect(ui.document.app.querySelector('.support-badge')!.textContent).toBe('4');
  });

  it('discards a late JSON response after logout and a new sign-in', async () => {
    const ui = await browser(); const body = deferred<unknown>();
    ui.setPendingReply(async () => ({ ...reply({}), json: () => body.promise }));
    const oldRead = ui.controls.refreshSupportCount(); await flush(); await ui.controls.logout();
    const reads = ui.pendingReads().length; await vi.advanceTimersByTimeAsync(90000); expect(ui.pendingReads()).toHaveLength(reads);
    expect(ui.document.app.querySelector('.support-badge')).toBeNull();
    ui.setPendingReply(async () => reply({ count: 5 })); await ui.controls.login(); await flush();
    body.resolve({ count: 99 }); await oldRead;
    expect(ui.document.app.querySelector('.support-badge')!.textContent).toBe('5');
  });

  it('refreshes the count after a confirmed reply or close without discarding a draft', async () => {
    const ui = await browser(); await ui.controls.openChat('fixture-member');
    const replyInput = ui.document.app.querySelector('.chat-drawer')!.querySelector('textarea')!;
    replyInput.value = 'ตอบลูกค้า'; await replyInput.emit('input');
    ui.setPendingReply(async () => reply({ count: 1 })); const beforeReply = ui.pendingReads().length;
    await ui.controls.submitReply(); await flush(); expect(ui.pendingReads().length).toBeGreaterThan(beforeReply);
    expect(ui.document.app.querySelector('.support-badge')!.textContent).toBe('1');
    ui.setPendingReply(async () => reply({ count: 0 })); const beforeClose = ui.pendingReads().length;
    await ui.controls.closeThread(); await flush(); expect(ui.pendingReads().length).toBeGreaterThan(beforeClose);
    expect(ui.document.app.querySelector('.support-badge')!.getAttribute('hidden')).not.toBeNull();
  });
});

describe('administrator refresh and report presentation', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-18T08:00:00Z')); });
  afterEach(() => { vi.useRealTimers(); });

  it('labels the Facebook destination as Reels in the post channel filter', async () => {
    const ui = await browser();
    await ui.controls.navigate('posts'); await flush();
    expect(ui.document.app.textContent).toContain('Facebook Reels');
    expect(ui.document.app.textContent).not.toContain('Facebook Page Video');
  });

  it('offers a manual refresh and refreshes only visible pages every 60 seconds', async () => {
    const ui = await browser();
    expect(ui.button('รีเฟรชข้อมูล')).toBeTruthy();
    await vi.advanceTimersByTimeAsync(59999); expect(ui.views()).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1); expect(ui.views()).toHaveLength(2);
    await ui.document.visibility('hidden'); await vi.advanceTimersByTimeAsync(180000); expect(ui.views()).toHaveLength(2);
    await ui.document.visibility('visible'); await vi.advanceTimersByTimeAsync(60000); expect(ui.views()).toHaveLength(3);
  });

  it('never overlaps a slow refresh with another refresh', async () => {
    const ui = await browser(); const waiting = deferred<Reply>(); ui.setViewReply(() => waiting.promise);
    await vi.advanceTimersByTimeAsync(60000); expect(ui.views()).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(180000); await ui.button('รีเฟรชข้อมูล').click(); expect(ui.views()).toHaveLength(2);
    waiting.resolve(reply(page())); await flush();
  });

  it('retains old rows and timestamp with a retry control after a failed refresh', async () => {
    const ui = await browser(); ui.setViewReply(async () => reply({ code: 'ADMIN_DATA_UNAVAILABLE' }, 503));
    await vi.advanceTimersByTimeAsync(60000);
    expect(ui.document.app.textContent).toContain('member@example.com');
    expect(ui.document.app.textContent).toContain('ข้อมูลอาจไม่เป็นปัจจุบัน');
    expect(ui.document.app.textContent).toContain('18 ต.ค.');
    expect(ui.button('ลองโหลดใหม่')).toBeTruthy();
  });

  it('marks retained data stale after 120 seconds without replacing an open drawer', async () => {
    const ui = await browser(); await ui.controls.openMember(member);
    const drawer = ui.document.app.querySelector('.drawer'); await vi.advanceTimersByTimeAsync(120000);
    expect(ui.views()).toHaveLength(1); expect(ui.document.app.querySelector('.drawer')).toBe(drawer);
    expect(ui.document.app.textContent).toContain('ข้อมูลอาจไม่เป็นปัจจุบัน');
  });

  it('does not refresh or resubmit a trial while a reviewed command has an unknown result', async () => {
    const ui = await browser(); await ui.controls.openMember(member); await ui.controls.startTrial('GRANT');
    const reason = ui.document.app.querySelector('textarea')!; reason.value = 'เหตุผลทดสอบ'; await reason.emit('input');
    await ui.button('ตรวจสอบสิทธิ์').click(); ui.setTrialReply(async () => reply({ code: 'ADMIN_TRIAL_UNAVAILABLE' }, 503));
    await ui.controls.submitTrial(); await vi.advanceTimersByTimeAsync(180000);
    expect(ui.requests.filter(request => request.path === 'trials')).toHaveLength(1); expect(ui.views()).toHaveLength(1);
    expect(ui.document.app.querySelector('.review')).toBeTruthy();
  });

  it('preserves typed search text and does not apply an unsubmitted query during refresh', async () => {
    const ui = await browser(); const input = ui.document.app.querySelector('input')!;
    input.value = 'กำลังพิมพ์'; input.focus(); await input.emit('input');
    await vi.advanceTimersByTimeAsync(60000);
    expect(ui.views()).toHaveLength(1); expect(ui.document.app.querySelector('input')!.value).toBe('กำลังพิมพ์');
    ui.document.activeElement = null; await ui.button('รีเฟรชข้อมูล').click(); await flush();
    expect(ui.views().at(-1)!.body.query).toBe(''); expect(ui.document.app.querySelector('input')!.value).toBe('กำลังพิมพ์');
  });

  it('resets loaded pagination after a refresh instead of appending duplicate cohorts', async () => {
    const ui = await browser(); ui.setViewReply(async body => reply(page({ rows: [{ ...member, id: body.cursor ? 'second' : 'first' }], total: 2, nextCursor: body.cursor ? undefined : 'next' })));
    await ui.button('รีเฟรชข้อมูล').click(); await flush(); await ui.button('โหลดรายการถัดไป').click(); await flush();
    expect(ui.document.app.querySelectorAll('tbody')[0].children).toHaveLength(2);
    await ui.button('รีเฟรชข้อมูล').click(); await flush();
    expect(ui.views().at(-1)!.body.cursor).toBeUndefined(); expect(ui.document.app.querySelectorAll('tbody')[0].children).toHaveLength(1);
    expect(ui.document.app.textContent).toContain('แสดงหน้าแรก');
  });

  it('rejects a delayed response after logout and stops refresh timers', async () => {
    const ui = await browser(); const waiting = deferred<Reply>(); ui.setViewReply(() => waiting.promise);
    await vi.advanceTimersByTimeAsync(60000); const request = ui.views().at(-1)!; await ui.controls.logout();
    expect(request.signal.aborted).toBe(true); waiting.resolve(reply(page({ rows: [{ ...member, email: 'late@example.com' }] }))); await flush();
    expect(ui.document.app.textContent).not.toContain('late@example.com'); await vi.advanceTimersByTimeAsync(180000); expect(ui.views()).toHaveLength(2);
  });

  it('starts reports with every account, UTC month dates, whole-cohort totals and distinct delivery counts', async () => {
    const ui = await browser(); ui.setViewReply(async () => reply(page({ rows: [{ userId: member.id, email: member.email, quotaPostUnits: 4, postUnits: 3, livePostUnits: 1, draftPostUnits: 1, failedPostUnits: 1 }],
      summary: { memberCount: 150, quotaPostUnits: 20, postUnits: 15, livePostUnits: 5, draftPostUnits: 4, failedPostUnits: 3 }, reportScope: 'ALL_ACCOUNTS' })));
    await ui.controls.navigate('reports'); await flush(); const body = ui.views().at(-1)!.body;
    expect(body).toMatchObject({ reportScope: 'ALL_ACCOUNTS', from: '2026-10-01', through: '2026-10-18' });
    expect(ui.document.app.textContent).toContain('ยอดรวมทุกบัญชีที่ตรงเงื่อนไข'); expect(ui.document.app.textContent).toContain('150');
    expect(ui.document.app.textContent).toContain('เผยแพร่สาธารณะ'); expect(ui.document.app.textContent).toContain('ร่าง');
    expect(ui.document.app.textContent).toContain('ไม่ใช่ยอดเผยแพร่สำเร็จ');
    expect(ui.document.app.querySelectorAll('.chosen')).toHaveLength(0);
  });

  it('switches to latest trial scope without calling it all usage', async () => {
    const ui = await browser(); await ui.controls.navigate('reports'); await flush();
    const scope = ui.document.app.querySelectorAll('select').find(element => element.getAttribute('aria-label') === 'ขอบเขตรายงาน')!;
    scope.value = 'LATEST_TRIAL'; await scope.emit('change'); await flush();
    expect(ui.views().at(-1)!.body.reportScope).toBe('LATEST_TRIAL'); expect(ui.document.app.textContent).toContain('ช่วงทดลองล่าสุด');
  });

  it('pauses refresh during a CSV request and never downloads a late CSV after logout', async () => {
    const ui = await browser(); await ui.controls.navigate('reports'); await flush(); const waiting = deferred<Reply>();
    ui.setViewReply(body => body.csv ? waiting.promise : Promise.resolve(reply(page())));
    const download = ui.controls.downloadCsv(); await flush(); const count = ui.views().length;
    await vi.advanceTimersByTimeAsync(120000); expect(ui.views()).toHaveLength(count);
    await ui.controls.logout(); waiting.resolve(reply('fixture csv')); await download; await flush();
    expect(ui.document.downloads).toEqual([]);
  });

  it('disables filters and navigation until the current CSV request finishes', async () => {
    const ui = await browser(); await ui.controls.navigate('reports'); const waiting = deferred<Reply>();
    ui.setViewReply(body => body.csv ? waiting.promise : Promise.resolve(reply(page())));
    const download = ui.controls.downloadCsv(); await flush(); const count = ui.views().length;
    expect(ui.document.app.querySelectorAll('input,select').every(element => element.disabled)).toBe(true);
    await ui.controls.load(); await ui.controls.navigate('members'); expect(ui.views()).toHaveLength(count);
    waiting.resolve(reply('fixture csv')); await download;
    expect(ui.document.downloads).toEqual(['postdee-usage-report.csv']);
  });

  it('keeps the existing latest-trial CSV filename', async () => {
    const ui = await browser(); await ui.controls.navigate('reports');
    const scope = ui.document.app.querySelectorAll('select').find(element => element.getAttribute('aria-label') === 'ขอบเขตรายงาน')!;
    scope.value = 'LATEST_TRIAL'; await scope.emit('change'); ui.setViewReply(async () => reply('fixture csv'));
    await ui.controls.downloadCsv(); expect(ui.document.downloads).toEqual(['postdee-trial-report.csv']);
  });

  it('formats the UTC report boundaries for reading and preserves unknown cost estimates', async () => {
    const ui = await browser(); ui.setViewReply(async () => reply(page({ reportScope: 'ALL_ACCOUNTS',
      window: { from: '2026-10-01T00:00:00.000Z', until: '2026-10-18T08:00:00.000Z', timezone: 'UTC' },
      summary: { memberCount: 0, estimatedUsd: null } })));
    await ui.controls.navigate('reports');
    expect(ui.document.app.textContent).toContain('รวมเวลาเริ่ม'); expect(ui.document.app.textContent).toContain('ไม่รวมเวลาสิ้นสุด');
    expect(ui.document.app.textContent).not.toContain('2026-10-01T');
    expect(ui.document.app.querySelector('.report-totals')!.textContent).toContain('ยังไม่ได้ตั้งอัตรา');
  });

  it('discards a response whose JSON body arrives after logout', async () => {
    const ui = await browser(); const body = deferred<unknown>();
    ui.setViewReply(async () => ({ ...reply({}), json: () => body.promise }));
    await vi.advanceTimersByTimeAsync(60000); await ui.controls.logout();
    body.resolve(page({ rows: [{ ...member, email: 'late-body@example.com' }] })); await flush();
    expect(ui.document.app.textContent).not.toContain('late-body@example.com');
  });

  it('ignores an old page response after navigation has completed', async () => {
    const ui = await browser(); const waiting = deferred<Reply>();
    ui.setViewReply(body => body.view === 'members' ? waiting.promise : Promise.resolve(reply(page({ rows: [{ ...member, email: 'current@example.com' }] }))));
    await vi.advanceTimersByTimeAsync(60000); await ui.controls.navigate('channels');
    waiting.resolve(reply(page({ rows: [{ ...member, email: 'old-page@example.com' }] }))); await flush();
    expect(ui.document.app.textContent).toContain('current@example.com'); expect(ui.document.app.textContent).not.toContain('old-page@example.com');
  });

  it('retains confirmed data and shows a Thai retry message for a plain-text rate-limit response', async () => {
    const ui = await browser(); ui.setViewReply(async () => ({ ...reply('Too many requests', 429), json: async () => { throw new SyntaxError('Unexpected token T in JSON'); } }));
    await vi.advanceTimersByTimeAsync(60000);
    expect(ui.document.app.textContent).toContain('member@example.com'); expect(ui.document.app.textContent).toContain('ข้อมูลอาจไม่เป็นปัจจุบัน');
    expect(ui.document.app.textContent).toContain('โหลดข้อมูลบ่อยเกินไป'); expect(ui.document.app.textContent).not.toContain('Unexpected token');
  });

  it('does not treat a future trial as already active in the member drawer', async () => {
    const ui = await browser({ ...member, trial: { plan: 'PRO', startsAt: '2026-10-19T00:00:00Z', expiresAt: '2026-10-26T00:00:00Z', revokedAt: null } });
    await ui.controls.openMember(member); expect(ui.document.app.querySelector('.drawer')!.textContent).toContain('ยังไม่เริ่ม');
    expect(ui.document.app.querySelector('.drawer')!.querySelectorAll('button').some(button => button.textContent === 'ต่อเวลาทดลอง')).toBe(false);
  });
});

describe('administrator account deletion presentation', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-26T08:00:00Z')); });
  afterEach(() => { vi.useRealTimers(); });
  const fill = async (ui: Awaited<ReturnType<typeof browser>>, confirmation: string, reason: string) => {
    const confirm = ui.document.app.querySelector('[data-focus=delete-confirm]')!;
    confirm.value = confirmation; await confirm.emit('input');
    const text = ui.document.app.querySelector('textarea')!; text.value = reason; await text.emit('input');
  };

  it('requires the typed member email and a reason without an address before the final step', async () => {
    const ui = await browser(); await ui.controls.openMember(member);
    await ui.button('ลบบัญชีนี้').click();
    expect(ui.button('ตรวจสอบก่อนลบ').disabled).toBe(true);
    await fill(ui, 'other@example.com', 'คำขอทางอีเมล'); expect(ui.button('ตรวจสอบก่อนลบ').disabled).toBe(true);
    await fill(ui, 'MEMBER@example.com', 'ลูกค้า member@example.com'); expect(ui.button('ตรวจสอบก่อนลบ').disabled).toBe(true);
    await fill(ui, 'MEMBER@example.com', 'คำขอทางอีเมล 26 ต.ค.'); expect(ui.button('ตรวจสอบก่อนลบ').disabled).toBe(false);
    expect(ui.requests.some(request => request.path === 'account-deletions')).toBe(false);

    await ui.button('ตรวจสอบก่อนลบ').click();
    expect(ui.document.app.querySelector('.review')!.textContent).toContain('member@example.com');
    await ui.button('ลบบัญชีถาวร').click(); await flush();

    expect(ui.requests.filter(request => request.path === 'account-deletions').map(request => request.body)).toEqual([
      { requestId: 'fixture-request', userId: 'fixture-member', expectedEmail: 'member@example.com', reason: 'คำขอทางอีเมล 26 ต.ค.' }
    ]);
    expect(ui.document.app.querySelector('.drawer')).toBeNull();
    expect(ui.document.app.textContent).toContain('ลบบัญชีแล้ว');
  });

  it('keeps the reviewed request for a retry after an unknown result and does not refresh meanwhile', async () => {
    const ui = await browser(); await ui.controls.openMember(member); await ui.controls.startDeletion();
    await fill(ui, 'member@example.com', 'คำขอทางอีเมล'); await ui.button('ตรวจสอบก่อนลบ').click();
    ui.setDeletionReply(async () => reply({ code: 'ACCOUNT_MEDIA_CLEANUP_FAILED' }, 503));
    await ui.button('ลบบัญชีถาวร').click(); await flush(); await vi.advanceTimersByTimeAsync(180000);

    expect(ui.document.app.textContent).toContain('ลบวิดีโอยังไม่ครบ');
    expect(ui.views()).toHaveLength(1);
    ui.setDeletionReply(async () => reply({ status: 'ok', deletion: { status: 'COMPLETED' } }));
    await ui.button('ลองอีกครั้งด้วยคำขอเดิม').click(); await flush();
    const sent = ui.requests.filter(request => request.path === 'account-deletions');
    expect(sent).toHaveLength(2); expect(sent[1].body.requestId).toBe(sent[0].body.requestId);
    expect(ui.document.app.textContent).toContain('ลบบัญชีแล้ว');
  });

  it('confirms by UID when the member has no email and hides the action from viewers', async () => {
    const ui = await browser({ ...member, email: '' }); await ui.controls.openMember(member); await ui.controls.startDeletion();
    await fill(ui, 'fixture-member', 'คำขอทางโทรศัพท์'); expect(ui.button('ตรวจสอบก่อนลบ').disabled).toBe(false);

    const viewer = await browser(member, 'VIEWER'); await viewer.controls.openMember(member);
    expect(viewer.document.app.querySelectorAll('button').some(button => button.textContent === 'ลบบัญชีนี้')).toBe(false);
  });

  it('lists deletion history with Thai status and no customer email column', async () => {
    const ui = await browser();
    ui.setViewReply(async () => reply(page({ rows: [{ requestId: 'r1', actorId: 'owner', userId: 'deleted-uid', reason: 'คำขอทางอีเมล',
      status: 'COMPLETED', lastErrorCode: null, createdAt: '2026-10-26T01:00:00Z', completedAt: '2026-10-26T01:00:05Z' }] })));
    await ui.controls.navigate('deletions'); await flush();
    expect(ui.document.app.textContent).toContain('ประวัติการลบบัญชี');
    expect(ui.document.app.textContent).toContain('deleted-uid');
    expect(ui.document.app.textContent).toContain('ลบเรียบร้อย');
    expect(ui.document.app.querySelector('table')!.textContent).not.toContain('สมาชิก');
  });
});

describe('administrator service notice actions', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-30T03:00:00Z')); });
  afterEach(() => { vi.useRealTimers(); });
  const notice = { id: 'notice-open', title: 'TikTok ส่งช้า', message: 'ทีมงานกำลังแก้ไข', platforms: ['TIKTOK'], stage: 'IDENTIFIED',
    version: 2, startedAt: '2026-10-30T02:49:14.883Z', updatedAt: '2026-10-30T02:49:41.771Z', resolvedAt: null };
  const resolved = { ...notice, id: 'notice-closed', stage: 'RESOLVED', version: 3, resolvedAt: '2026-10-29T01:00:00.000Z' };
  const notices = async (role = 'OWNER') => {
    const ui = await browser(member, role);
    ui.setViewReply(async body => reply(body.view === 'incidents' ? page({ rows: [notice, resolved] }) : page()));
    await ui.controls.navigate('incidents'); await flush();
    return ui;
  };
  const drawerButton = (ui: Awaited<ReturnType<typeof browser>>, text: string) => {
    const found = ui.document.app.querySelector('.drawer')!.querySelectorAll('button').find(item => item.textContent === text);
    if (!found) throw new Error(`Missing drawer button: ${text}`); return found;
  };

  it('shows close and edit first in the notices table, only to owners and only for open notices', async () => {
    const ui = await notices();
    const table = ui.document.app.querySelector('table')!;
    expect(table.querySelector('th')!.textContent).toBe('จัดการ');
    const [, open, closed] = table.querySelectorAll('tr');
    expect(open.querySelector('td')!.querySelectorAll('button').map(item => item.textContent)).toEqual(['ปิดประกาศ', 'แก้ไข']);
    expect(closed.querySelector('td')!.textContent).toBe('—');

    const viewer = await notices('VIEWER');
    expect(viewer.document.app.querySelector('table')!.querySelectorAll('th').map(item => item.textContent)).not.toContain('จัดการ');
    expect(viewer.document.app.querySelectorAll('button').some(item => item.textContent === 'ปิดประกาศ')).toBe(false);
  });

  it('closes an open notice after one confirmation without changing what it says', async () => {
    const ui = await notices();
    await ui.button('ปิดประกาศ').click();
    const drawer = ui.document.app.querySelector('.drawer')!;
    expect(drawer.querySelector('h2')!.textContent).toBe('ยืนยันการปิดประกาศ');
    expect(drawer.querySelector('select')).toBeNull();
    expect(drawer.querySelector('.review')!.textContent).toContain('TikTok ส่งช้า');
    expect(ui.requests.some(request => request.path === 'incidents')).toBe(false);

    await drawerButton(ui, 'ปิดประกาศ').click(); await flush();
    expect(ui.requests.filter(request => request.path === 'incidents').map(request => request.body)).toEqual([
      { action: 'UPDATE', id: 'notice-open', expectedVersion: 2, title: 'TikTok ส่งช้า', message: 'ทีมงานกำลังแก้ไข', platforms: ['TIKTOK'], stage: 'RESOLVED' }
    ]);
    expect(ui.document.app.querySelector('.drawer')).toBeNull();
    expect(ui.document.app.textContent).toContain('ปิดประกาศแล้ว');
  });

  it('cancels a direct close without a request and keeps editing in its own form', async () => {
    const ui = await notices();
    await ui.button('ปิดประกาศ').click();
    await drawerButton(ui, 'ยกเลิก').click();
    expect(ui.document.app.querySelector('.drawer')).toBeNull();

    await ui.button('แก้ไข').click();
    const drawer = ui.document.app.querySelector('.drawer')!;
    expect(drawer.querySelector('h2')!.textContent).toBe('อัปเดตประกาศ');
    expect(drawer.querySelector('select')).not.toBeNull();
    expect(ui.requests.some(request => request.path === 'incidents')).toBe(false);
  });
});
