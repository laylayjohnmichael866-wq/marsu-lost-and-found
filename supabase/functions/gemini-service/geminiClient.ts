/**
 * MarSU Lost & Found - Gemini API Client for Supabase Edge Functions
 * Securely communicates with Google Gemini API using server-side secrets.
 * Implements model fallback, error classification, latency tracking, and token extraction.
 */

import { GeminiApiErrorDetails, SupportedModel, TokenUsage } from './types.ts';

export interface GeminiCallResult {
  success: boolean;
  text?: string;
  modelUsed: string;
  fallbackTriggered: boolean;
  usage: TokenUsage;
  latencyMs: number;
  httpStatus: number;
  error?: GeminiApiErrorDetails;
}
export class GeminiServiceClient {
  private static readonly REQUEST_TIMEOUT_MS = 10000;
  private apiKey: string;
  private defaultModel: SupportedModel = 'gemini-3.8-flash';
  private fallbackModel: SupportedModel = 'gemini-3.8-flash';

  constructor() {
    this.apiKey = Deno.env.get('GEMINI_API_KEY') || '';
  }

  public hasValidKey(): boolean {
    return Boolean(this.apiKey && this.apiKey.trim().length > 10);
  }

  public async generateText(
    prompt: string,
    requestedModel?: SupportedModel,
    systemInstruction?: string,
    requestedFallbackModel?: SupportedModel
  ): Promise<GeminiCallResult> {
    const startTime = Date.now();

    if (!this.hasValidKey()) {
      return {
        success: false,
        modelUsed: requestedModel || this.defaultModel,
        fallbackTriggered: false,
        usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
        latencyMs: Date.now() - startTime,
        httpStatus: 401,
        error: {
          code: 'INVALID_API_KEY',
          message: 'GEMINI_API_KEY is not configured in Supabase Edge Function secrets.',
          httpStatus: 401,
          retryable: false,
        },
      };
    }

    const primaryModel = requestedModel || this.defaultModel;
    const fallbackModel = requestedFallbackModel || this.fallbackModel;

    // Attempt primary model execution
    try {
      const result = await this.executeGeminiRequest(primaryModel, prompt, systemInstruction);
      const latencyMs = Date.now() - startTime;

      return {
        success: true,
        text: result.text,
        modelUsed: primaryModel,
        fallbackTriggered: false,
        usage: result.usage,
        latencyMs,
        httpStatus: 200,
      };
    } catch (primaryError: unknown) {
      const classified = this.classifyError(primaryError);

      // Retry transient failures with the explicitly requested fallback model.
      if (fallbackModel !== primaryModel && classified.retryable) {
        try {
          const fallbackResult = await this.executeGeminiRequest(
            fallbackModel,
            prompt,
            systemInstruction
          );
          const latencyMs = Date.now() - startTime;

          return {
            success: true,
            text: fallbackResult.text,
            modelUsed: fallbackModel,
            fallbackTriggered: true,
            usage: fallbackResult.usage,
            latencyMs,
            httpStatus: 200,
          };
        } catch (fallbackError: unknown) {
          const fallbackClassified = this.classifyError(fallbackError);
          return {
            success: false,
            modelUsed: fallbackModel,
            fallbackTriggered: true,
            usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
            latencyMs: Date.now() - startTime,
            httpStatus: fallbackClassified.httpStatus,
            error: fallbackClassified,
          };
        }
      }

      return {
        success: false,
        modelUsed: primaryModel,
        fallbackTriggered: false,
        usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
        latencyMs: Date.now() - startTime,
        httpStatus: classified.httpStatus,
        error: classified,
      };
    }
  }

  private async executeGeminiRequest(
    model: string,
    prompt: string,
    systemInstruction?: string
  ): Promise<{ text: string; usage: TokenUsage }> {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

    const bodyPayload: Record<string, unknown> = {
      contents: [
        {
          role: 'user',
          parts: [{ text: prompt }],
        },
      ],
    };

    if (systemInstruction) {
      bodyPayload.systemInstruction = {
        parts: [{ text: systemInstruction }],
      };
    }

    const controller = new AbortController();
    // Keep primary + fallback attempts below the Edge Function gateway timeout.
    const timeout = setTimeout(
      () => controller.abort(),
      GeminiServiceClient.REQUEST_TIMEOUT_MS
    );

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': this.apiKey,
          'User-Agent': 'aistudio-build',
        },
        body: JSON.stringify(bodyPayload),
        signal: controller.signal,
      });
    } catch (networkErr: unknown) {
      clearTimeout(timeout);
      const errorName = networkErr instanceof Error ? networkErr.name : '';
      const errorMessage = networkErr instanceof Error ? networkErr.message : 'Connection failed';
      throw new Error(`NETWORK_FAILED:${errorName}:${errorMessage}`);
    } finally {
      clearTimeout(timeout);
    }

    const status = response.status;
    const responseText = await response.text();
    let responseJson: Record<string, any>;
    try {
      responseJson = JSON.parse(responseText);
    } catch (_parseError) {
      throw new Error(`INVALID_GEMINI_RESPONSE:Non-JSON response from Gemini (HTTP ${status})`);
    }

    if (!response.ok) {
      const errorObj = responseJson?.error || {};
      const statusText = errorObj.status || `${status}`;
      const message = errorObj.message || 'Gemini API returned an error response';
      throw new Error(`GEMINI_API_ERROR:${status}:${statusText}:${message}`);
    }

    const candidate = responseJson.candidates?.[0];
    const text = candidate?.content?.parts?.[0]?.text;

    if (!text && candidate?.finishReason && candidate.finishReason !== 'STOP') {
      throw new Error(`GEMINI_FINISH_REASON:${candidate.finishReason}`);
    }

    if (text === undefined || text === null) {
      throw new Error('INVALID_GEMINI_RESPONSE:No candidate text in response');
    }

    const usageMeta = responseJson.usageMetadata || {};
    const usage: TokenUsage = {
      promptTokens: Number.isFinite(usageMeta.promptTokenCount) ? usageMeta.promptTokenCount : 0,
      candidatesTokens: Number.isFinite(usageMeta.candidatesTokenCount) ? usageMeta.candidatesTokenCount : 0,
      totalTokens: Number.isFinite(usageMeta.totalTokenCount) ? usageMeta.totalTokenCount : 0,
    };

    return { text, usage };
  }

  private classifyError(err: unknown): GeminiApiErrorDetails {
    const rawMessage = err instanceof Error ? err.message : String(err);

    if (rawMessage.startsWith('NETWORK_FAILED') || rawMessage.includes('abort')) {
      return {
        code: 'NETWORK_ERROR',
        message: 'Network error or timeout while contacting Gemini API.',
        httpStatus: 504,
        retryable: true,
      };
    }

    if (rawMessage.startsWith('GEMINI_API_ERROR:')) {
      const parts = rawMessage.split(':');
      const statusCode = parseInt(parts[1] || '500', 10);
      const apiStatus = parts[2] || '';
      const apiMsg = parts.slice(3).join(':') || 'Upstream Gemini error';

      if (statusCode === 400 && (apiStatus.includes('API_KEY_INVALID') || apiMsg.includes('API key not valid'))) {
        return {
          code: 'INVALID_API_KEY',
          message: 'The configured Google Gemini API key is invalid or lacks proper permissions.',
          httpStatus: 401,
          retryable: false,
        };
      }

      if (statusCode === 408 || statusCode === 429 || apiStatus === 'RESOURCE_EXHAUSTED') {
        return {
          code: 'QUOTA_EXCEEDED',
          message: 'Gemini API rate limit or quota exceeded. Please wait a moment before trying again.',
          httpStatus: statusCode === 408 ? 504 : 429,
          retryable: true,
        };
      }

      if (statusCode === 403 || apiStatus === 'PERMISSION_DENIED') {
        return {
          code: 'INVALID_API_KEY',
          message: 'Permission denied. Verify Gemini API service is enabled for the key.',
          httpStatus: 403,
          retryable: false,
        };
      }

      const retryable = statusCode === 408 || statusCode === 429 || statusCode >= 500;
      return {
        code: 'INVALID_GEMINI_RESPONSE',
        message: `Upstream Gemini API error (${statusCode}): ${apiMsg}`,
        httpStatus: statusCode >= 500 ? 502 : statusCode,
        retryable,
      };
    }

    return {
      code: 'INVALID_GEMINI_RESPONSE',
      message: rawMessage || 'Unexpected response received from Gemini API.',
      httpStatus: 500,
      retryable: false,
    };
  }
}

