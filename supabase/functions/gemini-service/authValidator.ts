/**
 * MarSU Lost & Found - Supabase Edge Function Auth Validator
 * Verifies Supabase Auth JWT tokens and extracts user role and permissions.
 *
 * Security Invariants:
 * 1. Zero bypass: Missing environment variables produce a 500 configuration error, NEVER an authenticated user.
 * 2. Authenticates caller strictly via Supabase Auth getUser(token).
 * 3. Trusts roles strictly from user.app_metadata.role (NEVER user_metadata).
 * 4. Preserves student, moderator, staff, admin, and service role architecture without silent promotion or downgrade.
 */

declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

// @ts-ignore - remote ESM imports are valid in Deno Edge Functions but not always in editor TypeScript resolution.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import {
  ALLOWED_CLIENT_APPS,
  ALLOWED_ROLES,
  AuthValidationResult,
  ClientApp,
  UserRole,
} from './types.ts';

export async function validateAuth(
  req: Request,
  payloadClientApp?: ClientApp
): Promise<AuthValidationResult> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader || !/^Bearer\s+\S+$/i.test(authHeader)) {
    return {
      isAuthenticated: false,
      statusCode: 401,
      errorMessage: 'Missing or malformed Authorization header. Bearer token required.',
    };
  }

  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (token.length < 10) {
    return {
      isAuthenticated: false,
      statusCode: 401,
      errorMessage: 'Invalid Bearer token: Token string too short or malformed.',
    };
  }

  if (payloadClientApp !== undefined &&
      !(ALLOWED_CLIENT_APPS as readonly string[]).includes(payloadClientApp)) {
    return {
      isAuthenticated: false,
      statusCode: 400,
      errorMessage: 'Invalid client application identifier.',
    };
  }

  // Retrieve Supabase environment variables injected into Edge Functions
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');

  // CRITICAL REQUIREMENT 1: Zero auth bypass.
  // Missing environment variables MUST return a configuration error, NEVER an authenticated test user.
  if (!supabaseUrl || !supabaseAnonKey) {
    return {
      isAuthenticated: false,
      statusCode: 500,
      errorMessage:
        'Configuration Error: SUPABASE_URL or SUPABASE_ANON_KEY is not defined in Edge Function environment. Authentication unavailable.',
    };
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    // CRITICAL REQUIREMENT 2: Validate the caller using Supabase Auth getUser(token)
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      return {
        isAuthenticated: false,
        statusCode: 401,
        errorMessage: error?.message || 'Invalid or expired user session token.',
      };
    }

    // CRITICAL REQUIREMENT 3 & 5:
    // Trust roles ONLY from user.app_metadata.role, NEVER user_metadata.
    // Preserve existing student, moderator, staff, admin, service roles without silent promotion or downgrade.
    const trustedAppRole = user.app_metadata?.role;

    let resolvedRole: UserRole = 'student';
    if (trustedAppRole !== undefined) {
      if (typeof trustedAppRole !== 'string' ||
          !(ALLOWED_ROLES as readonly string[]).includes(trustedAppRole)) {
        return {
          isAuthenticated: false,
          statusCode: 403,
          errorMessage: 'Account has an invalid authorization role.',
        };
      }
      resolvedRole = trustedAppRole as UserRole;
    }

    // Extract explicit permissions from app_metadata (e.g. staff delegated admin permissions)
    const rawPermissions = user.app_metadata?.permissions;

    const appPermissions: string[] = Array.isArray(rawPermissions)
      ? rawPermissions.filter((p): p is string => typeof p === 'string')
      : [];

    // Client app is derived from the trusted role. Client headers/payloads are
    // metadata only and must not let a caller impersonate another application.
    const determinedClientApp: ClientApp = resolvedRole === 'service'
      ? 'system'
      : resolvedRole === 'admin' || resolvedRole === 'staff' || resolvedRole === 'moderator'
        ? 'react_admin'
        : 'flutter_student';

    return {
      isAuthenticated: true,
      userId: user.id,
      userRole: resolvedRole,
      clientApp: determinedClientApp,
      appPermissions,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Auth verification error';
    return {
      isAuthenticated: false,
      statusCode: 500,
      errorMessage: `Authentication service exception: ${message}`,
    };
  }
}
