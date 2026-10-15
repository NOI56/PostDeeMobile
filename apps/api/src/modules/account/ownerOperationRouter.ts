import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { RunWithActiveOwner } from './ownerOperationQueue.js';
import { retainCurrentOwnerOperation } from './prismaOwnerOperationCoordinator.js';

const mutatingRead = (path: string) =>
  path === '/auth/me' || path === '/social-connections' ||
  path === '/billing/subscription' || /^\/uploads\/[^/]+$/.test(path);

// These checks cannot have created a remote post. TikTok creator-info GETs
// only read capabilities before any post, quota, queue or publish mutation.
const unavailableBeforeRemoteWork = new Set([
  'SOCIAL_CONNECTION_UNAVAILABLE', 'STORE_VERIFIER_NOT_CONFIGURED',
  'REVENUECAT_RESYNC_NOT_CONFIGURED', 'GOOGLE_PLAY_ACCESS_TOKEN_NOT_CONFIGURED',
  'APPLE_ROOT_CERTIFICATES_NOT_CONFIGURED',
  'TIKTOK_PUBLISHING_UNAVAILABLE', 'TIKTOK_CREATOR_INFO_UNAVAILABLE',
  'TIKTOK_CREATOR_INFO_INVALID'
]);

// Wrap the final registered handler, not the socket/response lifetime. Some
// handlers send a response before awaiting their finally cleanup.
export const createOwnerOperationRouter = (router: Router, runWithActiveOwner: RunWithActiveOwner): Router => {
  const verbs = new Set(['get', 'head', 'post', 'put', 'patch', 'delete']);
  const protectedRouter = new Proxy(router, {
    get(target, property, receiver) {
      const registrar = Reflect.get(target, property, receiver);
      if (typeof property !== 'string' || !verbs.has(property)) return registrar;
      return (...args: unknown[]) => {
        const handler = args.at(-1);
        if (args.length < 2 || typeof handler !== 'function') {
          throw new Error('An owner-aware route must end with a request handler.');
        }
        const wrapped: RequestHandler = (request, response, next) => {
          const path = request.path.toLowerCase().replace(/\/+$/, '');
          const user = readAuthUser(response.locals);
          const readOnly = request.method === 'GET' || request.method === 'HEAD';
          const deletion = (request.method === 'DELETE' && path === '/account') ||
            (readOnly && path === '/account/deletion-readiness');
          if (!user || deletion || (readOnly && !mutatingRead(path))) {
            return (handler as RequestHandler)(request, response, next);
          }
          void runWithActiveOwner(user.id, async () => {
            let code: string | undefined;
            const originalJson = response.json;
            response.json = function (body: unknown) {
              if (body && typeof body === 'object' && 'code' in body && typeof body.code === 'string') code = body.code;
              return originalJson.call(this, body);
            };
            try { await (handler as RequestHandler)(request, response, next); }
            finally { response.json = originalJson; }
            // A provider request may have been accepted before a server error.
            // Keep its private blocker until the operator reconciles the result.
            // This POST carries a private lookup intent in the body but never
            // mutates or contacts a publisher. Keep its lifetime admission and
            // completion while exempting only its exact path from write ambiguity.
            const readOnlyRecovery = request.method === 'POST' && path === '/posts/submissions/recover';
            if (response.statusCode >= 500 && !readOnlyRecovery && (!code || !unavailableBeforeRemoteWork.has(code))) {
              retainCurrentOwnerOperation(user.id);
            }
          }).catch(next);
        };
        const result = Reflect.apply(registrar, target, [...args.slice(0, -1), wrapped]);
        return result === target ? protectedRouter : result;
      };
    }
  });
  return protectedRouter;
};
