import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const apiDirectory = fileURLToPath(new URL('../../', import.meta.url));
const monitoringModule = new URL('./sentryMonitoring.ts', import.meta.url).href;

// Run the real initializer in a separate process: fatal handlers must never be
// installed in Vitest itself. Its only destination is a loopback HTTP sink.
const runFatalRejection = (name: string, respond = true) => new Promise<{
  code: number | null;
  timedOut: boolean;
  stdout: string;
}>((resolve, reject) => {
  const script = `
    import http from 'node:http';
    import { createSentryMonitoring } from ${JSON.stringify(monitoringModule)};
    const sink = http.createServer(async (request, response) => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const lines = Buffer.concat(chunks).toString('utf8').trim().split('\\n');
      console.log(JSON.stringify({ envelope: lines.map((line) => JSON.parse(line)) }));
      if (${JSON.stringify(respond)}) response.writeHead(200).end('{}');
    });
    await new Promise((resolve) => sink.listen(0, '127.0.0.1', resolve));
    const port = sink.address().port;
    await createSentryMonitoring({
      dsn: 'http://public123@127.0.0.1:' + port + '/123456',
      environment: 'staging', release: 'postdee-api@fatal-regression'
    });
    const error = Object.assign(new Error('private-caption secret-token'), {
      name: ${JSON.stringify(name)}
    });
    error.stack = error.name + ': private-caption secret-token\\n    at privateCaption (/app/src/server.ts:12:3)';
    Promise.reject(error);
  `;
  const child = spawn(process.execPath, ['--import', 'tsx', '--input-type=module', '--eval', script], {
    cwd: apiDirectory,
    env: {
      ...process.env,
      // Exercise Node's default rejection policy, independent of the test host.
      NODE_OPTIONS: '',
      SENTRY_DSN: '',
      http_proxy: '', https_proxy: '', HTTP_PROXY: '', HTTPS_PROXY: '', no_proxy: '127.0.0.1'
    },
    stdio: ['ignore', 'pipe', 'ignore']
  });
  let stdout = '';
  let timedOut = false;
  child.stdout.setEncoding('utf8').on('data', (chunk: string) => { stdout += chunk; });
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill();
  }, 6_000);
  child.once('error', (error) => { clearTimeout(timer); reject(error); });
  child.once('close', (code) => {
    clearTimeout(timer);
    resolve({ code, timedOut, stdout });
  });
});

describe('Sentry fatal process behavior', () => {
  it.each(['Error', 'AbortError', 'AI_NoOutputGeneratedError'])(
    'reports and exits on an unhandled %s rejection without hanging', async (name) => {
      const result = await runFatalRejection(name);
      expect(result.timedOut).toBe(false);
      expect(result.code).toBe(1);
      const envelopes = result.stdout.trim().split(/\r?\n/)
        .filter((line) => line.startsWith('{')).map((line) => JSON.parse(line).envelope);
      expect(envelopes).toHaveLength(1);
      expect(JSON.stringify(envelopes)).not.toMatch(/private|secret|caption|token|"trace":|"user":|"request":/);
      expect(envelopes[0][1]).toEqual({ type: 'event' });
      expect(envelopes[0][2]).toMatchObject({
        level: 'fatal', environment: 'staging', release: 'postdee-api@fatal-regression',
        exception: { values: [{ type: 'Error', value: 'PostDee server error',
          mechanism: { type: 'generic', handled: false },
          stacktrace: { frames: [{ filename: 'src/server.ts', lineno: 12, colno: 3 }] }
        }] }
      });
    }, 10_000
  );

  it('still exits when the reporting endpoint never responds', async () => {
    const result = await runFatalRejection('Error', false);
    expect(result.timedOut).toBe(false);
    expect(result.code).toBe(1);
    expect(result.stdout).toContain('"level":"fatal"');
    expect(result.stdout).not.toMatch(/private|secret|caption|token/);
  }, 10_000);
});
