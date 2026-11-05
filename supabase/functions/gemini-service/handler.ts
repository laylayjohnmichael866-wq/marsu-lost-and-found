/**
 * MarSU Lost & Found - Gemini Service Dispatcher Handler
 * Routes actions, processes prompts, enforces runtime payload validation, and records privacy-compliant usage telemetry.
 */

import {
  ALLOWED_ACTIONS,
  ALLOWED_CLIENT_APPS,
  ALLOWED_MODELS,
  AuthValidationResult,
  FeatureCategory,
  GeminiServiceRequest,
  GeminiServiceResponse,
  MAX_PROMPT_LENGTH,
  MAX_SYSTEM_INSTRUCTION_LENGTH,
  UserRole,
} from './types.ts';
import { GeminiServiceClient } from './geminiClient.ts';
import { logAiUsage } from './logger.ts';

const geminiClient = new GeminiServiceClient();

/**
 * Explicit role-based permission matrix for AI capabilities.
 * Defines which roles can access each AI feature category.
 */
const FEATURE_ROLE_PERMISSIONS: Record<FeatureCategory, readonly UserRole[]> = {
  test_prompt: ['student', 'moderator', 'staff', 'admin', 'service'],
  student_chatbot: ['student', 'moderator', 'staff', 'admin', 'service'],
  item_matching: ['student', 'moderator', 'staff', 'admin', 'service'],
  image_recognition: ['student', 'moderator', 'staff', 'admin', 'service'],
  admin_assistant: ['admin'], // Staff allowed only via explicit app_metadata permission
};

export async function handleGeminiRequest(
  request: GeminiServiceRequest,
  auth: AuthValidationResult
): Promise<GeminiServiceResponse> {
  // CRITICAL REQUIREMENT 4: Runtime payload type and field validation
  if (!request || typeof request !== 'object') {
    return {
      success: false,
      modelUsed: 'none',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: 'Request payload must be a valid JSON object.',
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  const { action, prompt, model, fallbackModel, clientApp } = request;

  // 1. Validate Action
  if (!action || !(ALLOWED_ACTIONS as readonly string[]).includes(action)) {
    return {
      success: false,
      modelUsed: 'none',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `Invalid action '${String(action)}'. Allowed actions: ${ALLOWED_ACTIONS.join(', ')}`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  // 2. Validate Model (if provided)
  if (model && !(ALLOWED_MODELS as readonly string[]).includes(model)) {
    return {
      success: false,
      modelUsed: 'none',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `Invalid model '${String(model)}'. Allowed models: ${ALLOWED_MODELS.join(', ')}`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  if (fallbackModel && !(ALLOWED_MODELS as readonly string[]).includes(fallbackModel)) {
    return {
      success: false,
      modelUsed: 'none',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `Invalid fallback model '${String(fallbackModel)}'. Allowed models: ${ALLOWED_MODELS.join(', ')}`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  if (model && fallbackModel && model === fallbackModel) {
    return {
      success: false,
      modelUsed: model,
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: 'The fallback model must differ from the primary model.',
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  // 3. Validate ClientApp (if provided)
  if (clientApp && !(ALLOWED_CLIENT_APPS as readonly string[]).includes(clientApp)) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `Invalid clientApp '${String(clientApp)}'. Allowed values: ${ALLOWED_CLIENT_APPS.join(', ')}`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  if (request.parameters !== undefined &&
      (typeof request.parameters !== 'object' || request.parameters === null || Array.isArray(request.parameters))) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: '"parameters" must be a JSON object.',
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  const requestedSystemInstruction = request.parameters?.systemInstruction;
  if (requestedSystemInstruction !== undefined &&
      (typeof requestedSystemInstruction !== 'string' || requestedSystemInstruction.trim().length === 0 ||
        requestedSystemInstruction.length > MAX_SYSTEM_INSTRUCTION_LENGTH)) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `"parameters.systemInstruction" must be a non-empty string of at most ${MAX_SYSTEM_INSTRUCTION_LENGTH} characters.`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  // 4. Validate Prompt (existence, type, length)
  if (typeof prompt !== 'string' || prompt.trim().length === 0) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: 'A non-empty string "prompt" field is required.',
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  if (prompt.length > MAX_PROMPT_LENGTH) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'BAD_REQUEST',
        message: `Prompt exceeds maximum allowed length of ${MAX_PROMPT_LENGTH} characters (received ${prompt.length}).`,
        httpStatus: 400,
        retryable: false,
      },
    };
  }

  // CRITICAL REQUIREMENT 5 & 6:
  // Role-based access control (RBAC).
  // "admin_assistant" is strictly restricted to authorized administrators unless explicitly approved staff permission exists.
  const callerRole = auth.userRole || 'student';
  const allowedRoles = FEATURE_ROLE_PERMISSIONS[action];

  let isAuthorized = allowedRoles.includes(callerRole);

  // Requirement 6: Staff permission delegation exception
  if (action === 'admin_assistant' && callerRole === 'staff') {
    const hasExplicitStaffPermission = auth.appPermissions?.includes('admin_assistant') ?? false;
    if (hasExplicitStaffPermission) {
      isAuthorized = true;
    }
  }

  if (!isAuthorized) {
    return {
      success: false,
        modelUsed: model || 'gemini-3.8-flash',
      fallbackTriggered: false,
      usage: { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 },
      latencyMs: 0,
      error: {
        code: 'FORBIDDEN',
        message: `Access Denied: Role '${callerRole}' is not authorized to access action '${action}'.`,
        httpStatus: 403,
        retryable: false,
      },
    };
  }

  // Phase 1 System Instructions for test prompt
  const systemInstruction =
    requestedSystemInstruction ||
    'You are the MarSU (Marinduque State University) Lost & Found Intelligent Assistant. ' +
    'Provide helpful, polite, and precise answers to students and campus administrators.';

  // Execute Gemini request
  const callResult = await geminiClient.generateText(
    prompt,
    model,
    systemInstruction,
    fallbackModel
  );

  // CRITICAL REQUIREMENT 10:
  // Await telemetry so the invocation cannot finish before the audit record is written.
  await logAiUsage({
    userId: auth.userId,
    userRole: callerRole,
    clientApp: auth.clientApp || 'flutter_student',
    featureCategory: action,
    modelName: callResult.modelUsed,
    tokensPrompt: callResult.usage.promptTokens,
    tokensCandidates: callResult.usage.candidatesTokens,
    tokensTotal: callResult.usage.totalTokens,
    latencyMs: callResult.latencyMs,
    httpStatus: callResult.httpStatus,
    status: callResult.success ? 'success' : 'error',
    fallbackTriggered: callResult.fallbackTriggered,
    errorCode: callResult.error?.code || null,
    errorMessage: callResult.error?.message || null,
  });

  return {
    success: callResult.success,
    text: callResult.text,
    modelUsed: callResult.modelUsed,
    fallbackTriggered: callResult.fallbackTriggered,
    usage: callResult.usage,
    latencyMs: callResult.latencyMs,
    error: callResult.error,
  };
}
