import { createRequire } from 'node:module';

import { describe, expect, it } from 'vitest';

type TrustProxy = (address: string, index: number) => boolean;
type ProxyRequest = {
  headers: { 'x-forwarded-for': string };
  socket: { remoteAddress: string };
};

const proxyAddr = createRequire(import.meta.url)('proxy-addr') as {
  (request: ProxyRequest, trust: TrustProxy): string;
  compile(addresses: string[]): TrustProxy;
};

describe('proxy-addr dependency security', () => {
  it('does not trust an unrelated IPv4 peer through a mapped IPv6 CIDR (GHSA-jqcg-44mw-7w3h)', () => {
    const trust = proxyAddr.compile(['::ffff:10.0.0.0/8']);
    const socketPeer = '203.0.113.42';
    const request = {
      headers: { 'x-forwarded-for': '198.51.100.25' },
      socket: { remoteAddress: socketPeer }
    };

    expect(proxyAddr(request, trust)).toBe(socketPeer);
    expect(trust(socketPeer, 0)).toBe(false);
  });
});
