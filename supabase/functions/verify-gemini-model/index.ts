/**
 * Temporary MarSU diagnostic function.
 *
 * This function intentionally returns only Gemini model-catalog metadata. It
 * never returns or logs GEMINI_API_KEY, bearer tokens, or Gemini response text.
 */

import { validateAuth } from '../gemini-service/authValidator.ts';

const TARGET_MODEL = 'models/gemini-3.5-flash';

function corsHeaders(req: Request): Record<string, string> {
  const configuredOrigins = (Deno.env.get('CORS_ALLOWED_ORIGINS') || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const requestOrigin = req.headers.get('Origin');
  const allowOrigin = requestOrigin &&
      (configuredOrigins.includes('*') || configuredOrigins.includes(requestOrigin))
    ? requestOrigin
    : (configuredOrigins[0] || '');

  return {
    ...(allowOrigin ? { 'Access-Control-Allow-Origin': allowOrigin } : {}),
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
  };
}

function responseBody(
  req: Request,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(req),
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(req) });
  }

  if (req.method !== 'POST') {
    return responseBody(req, 405, {
      success: false,
      httpStatus: 405,
      modelListed: false,
      error: 'Method Not Allowed',
    });
  }

  const auth = await validateAuth(req);
  if (!auth.isAuthenticated || auth.userRole !== 'admin') {
    return responseBody(req, auth.isAuthenticated ? 403 : (auth.statusCode || 401), {
      success: false,
      httpStatus: auth.isAuthenticated ? 403 : (auth.statusCode || 401),
      modelListed: false,
      error: 'Administrator authentication required.',
    });
  }

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    return responseBody(req, 500, {
      success: false,
      httpStatus: 500,
      modelListed: false,
      error: 'Gemini API request could not be made because the server secret is not configured.',
    });
  }

  try {
    const upstream = await fetch(
      'https://generativelanguage.googleapis.com/v1beta/models',
      {
        method: 'GET',
        headers: {
          'x-goog-api-key': apiKey,
          'Accept': 'application/json',
        },
      },
    );

    const httpStatus = upstream.status;
    if (!upstream.ok) {
      return responseBody(req, 200, {
        success: false,
        httpStatus,
        modelListed: false,
        error: 'Gemini model-list request failed.',
      });
    }

    const payload: unknown = await upstream.json();
    const models = payload && typeof payload === 'object' && !Array.isArray(payload) &&
        Array.isArray((payload as { models?: unknown }).models)
      ? (payload as { models: unknown[] }).models
      : [];
    const matchingModel = models.find((model): model is Record<string, unknown> =>
      typeof model === 'object' && model !== null &&
      (model as { name?: unknown }).name === TARGET_MODEL);
    const supportedGenerationMethods = matchingModel &&
        Array.isArray(matchingModel.supportedGenerationMethods)
      ? matchingModel.supportedGenerationMethods.filter((method): method is string =>
        typeof method === 'string')
      : undefined;

    return responseBody(req, 200, {
      success: true,
      httpStatus,
      modelListed: Boolean(matchingModel),
      ...(supportedGenerationMethods
        ? { supportedGenerationMethods }
        : {}),
    });
  } catch (_error) {
    // Do not return the exception: it could contain request or credential data.
    return responseBody(req, 200, {
      success: false,
      httpStatus: 0,
      modelListed: false,
      error: 'Gemini model-list request failed.',
    });
  }
});
