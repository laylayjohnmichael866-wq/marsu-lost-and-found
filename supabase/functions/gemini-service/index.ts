/**
 * MarSU Lost & Found - Gemini Edge Function Entrypoint
 * Deno server handling CORS, authentication gating, and request routing.
 */

import { validateAuth } from './authValidator.ts';
import { handleGeminiRequest } from './handler.ts';
import { GeminiServiceRequest, GeminiServiceResponse } from './types.ts';

function getCorsHeaders(req: Request): Record<string, string> {
  const configuredOrigins = (Deno.env.get('CORS_ALLOWED_ORIGINS') ||
    'http://localhost:3000,http://127.0.0.1:3000')
    .split(',').map((origin) => origin.trim()).filter(Boolean);
  const requestOrigin = req.headers.get('Origin');
  const isLocalFlutterOrigin = (() => {
    if (!requestOrigin) return false;
    try {
      const origin = new URL(requestOrigin);
      return origin.protocol === 'http:' &&
        (origin.hostname === 'localhost' ||
          origin.hostname === '127.0.0.1');
    } catch {
      return false;
    }
  })();

  const allowOrigin = configuredOrigins.includes('*')
    ? '*'
    : requestOrigin &&
        (configuredOrigins.includes(requestOrigin) || isLocalFlutterOrigin)
      ? requestOrigin
      : (configuredOrigins[0] || '*');

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-client-app',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: getCorsHeaders(req) });
  }

  // Only allow POST
  if (req.method !== 'POST') {
    const errorResponse: GeminiServiceResponse = {
      success: false,
      modelUsed: 'none',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: 'Method Not Allowed. Supabase Edge Function accepts only POST.',
        httpStatus: 405,
        retryable: false,
      },
    };
    return new Response(JSON.stringify(errorResponse), {
      status: 405,
      headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    let body: GeminiServiceRequest;
    try {
      const parsedBody: unknown = await req.json();
      if (typeof parsedBody !== 'object' || parsedBody === null || Array.isArray(parsedBody)) {
        throw new Error('Request body must be a JSON object.');
      }
      body = parsedBody as GeminiServiceRequest;
    } catch (_e) {
      const parseError: GeminiServiceResponse = {
        success: false,
        modelUsed: 'none',
        fallbackTriggered: false,
        usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
        latencyMs: 0,
        error: {
          code: 'BAD_REQUEST',
          message: 'Malformed JSON payload in request body.',
          httpStatus: 400,
          retryable: false,
        },
      };
      return new Response(JSON.stringify(parseError), {
        status: 400,
        headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Authenticate caller (validates JWT session)
    const authResult = await validateAuth(req, body.clientApp);

    if (!authResult.isAuthenticated) {
      const authStatus = authResult.statusCode || 401;
      const authErrorCode = authStatus === 400
        ? 'BAD_REQUEST'
        : authStatus === 403
          ? 'FORBIDDEN'
          : authStatus >= 500
            ? 'CONFIGURATION_ERROR'
            : 'UNAUTHORIZED';
      const authErrorResponse: GeminiServiceResponse = {
        success: false,
        modelUsed: body.model || 'gemini-3.8-flash',
        fallbackTriggered: false,
        usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
        latencyMs: 0,
        error: {
          code: authErrorCode,
          message: authResult.errorMessage || 'Unauthorized request. Please log in first.',
          httpStatus: authStatus,
          retryable: false,
        },
      };

      return new Response(JSON.stringify(authErrorResponse), {
        status: authStatus,
        headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Dispatch and execute request
    const responsePayload = await handleGeminiRequest(body, authResult);

    const httpStatusCode = responsePayload.success
      ? 200
      : responsePayload.error?.httpStatus || 500;

    return new Response(JSON.stringify(responsePayload), {
      status: httpStatusCode,
      headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (unexpectedError: unknown) {
    const errorMsg = 'Unexpected Edge Function error.';
    const crashResponse: GeminiServiceResponse = {
      success: false,
      modelUsed: 'unknown',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'INTERNAL_ERROR',
        message: errorMsg,
        httpStatus: 500,
        retryable: false,
      },
    };

    return new Response(JSON.stringify(crashResponse), {
      status: 500,
      headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
