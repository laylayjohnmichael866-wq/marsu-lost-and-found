/**
 * MarSU Lost & Found - Privacy-Safe AI Usage Logger
 * Records token consumption, latency, and status in Supabase PostgreSQL without persisting prompts.
 *
 * Security Invariants:
 * 1. SUPABASE_SERVICE_ROLE_KEY is accessed strictly server-side within the Edge Function environment.
 * 2. Never records raw prompts, student contact info, or PII.
 * 3. Sanitizes error messages to prevent token or header reflection.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { AiUsageLogEntry } from './types.ts';

export async function logAiUsage(entry: AiUsageLogEntry): Promise<void> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('AI usage logging is not configured: Supabase URL or service role key is missing.');
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Sanitization: Ensure NO sensitive prompts, student contact info, or personal data are passed
    const sanitizedErrorMsg = entry.errorMessage
      ? entry.errorMessage
          .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer [REDACTED]')
          .substring(0, 300)
      : null;

    const dbPayload = {
      user_id: entry.userId || null,
      user_role: entry.userRole,
      client_app: entry.clientApp,
      feature_category: entry.featureCategory,
      model_name: entry.modelName,
      tokens_prompt: entry.tokensPrompt,
      tokens_candidates: entry.tokensCandidates,
      tokens_total: entry.tokensTotal,
      latency_ms: entry.latencyMs,
      http_status: entry.httpStatus,
      status: entry.status,
      fallback_triggered: entry.fallbackTriggered,
      error_code: entry.errorCode || null,
      error_message: sanitizedErrorMsg,
    };

    const { error } = await supabase.from('ai_usage_logs').insert(dbPayload);

    if (error) {
      console.error('[AI_LOGGER_ERROR] Failed to write to ai_usage_logs:', error.message);
      throw new Error('AI usage logging failed.');
    }
  } catch (err: unknown) {
    console.error('[AI_LOGGER_EXCEPTION] Exception writing telemetry log:', err);
    throw new Error('AI usage logging failed.');
  }
}
