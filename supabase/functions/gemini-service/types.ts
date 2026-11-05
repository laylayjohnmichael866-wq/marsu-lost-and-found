/**
 * MarSU Lost & Found - Gemini Edge Function Types
 * Shared TypeScript contracts for Supabase Edge Function requests and responses.
 */

export const ALLOWED_ACTIONS = [
  'test_prompt',
  'item_matching',
  'image_recognition',
  'student_chatbot',
  'admin_assistant',
] as const;

export type FeatureCategory = typeof ALLOWED_ACTIONS[number];

export const ALLOWED_CLIENT_APPS = [
  'flutter_student',
  'react_admin',
  'system',
] as const;

export type ClientApp = typeof ALLOWED_CLIENT_APPS[number];

export const ALLOWED_ROLES = [
  'student',
  'moderator',
  'staff',
  'admin',
  'service',
] as const;

export type UserRole = typeof ALLOWED_ROLES[number];

export const ALLOWED_MODELS = [
  'gemini-3.8-flash',
  'gemini-2.5-pro',
] as const;

export type SupportedModel = typeof ALLOWED_MODELS[number];

export const MAX_PROMPT_LENGTH = 4000;
export const MAX_SYSTEM_INSTRUCTION_LENGTH = 4000;

export interface TokenUsage {
  promptTokens: number;
  candidatesTokens: number;
  totalTokens: number;
}
export interface GeminiApiErrorDetails {
  code:
    | 'INVALID_API_KEY'
    | 'QUOTA_EXCEEDED'
    | 'NETWORK_ERROR'
    | 'INVALID_GEMINI_RESPONSE'
    | 'UNAUTHORIZED'
    | 'FORBIDDEN'
    | 'BAD_REQUEST'
    | 'CONFIGURATION_ERROR'
    | 'INTERNAL_ERROR';
  message: string;
  httpStatus: number;
  retryable: boolean;
}

export interface GeminiServiceRequest {
  action: FeatureCategory;
  prompt: string;
  model?: SupportedModel;
  fallbackModel?: SupportedModel;
  clientApp?: ClientApp;
  parameters?: {
    systemInstruction?: string;
  };
}

export interface GeminiServiceResponse {
  success: boolean;
  text?: string;
  modelUsed: string;
  fallbackTriggered: boolean;
  usage: TokenUsage;
  latencyMs: number;
  error?: GeminiApiErrorDetails;
}

export interface AuthValidationResult {
  isAuthenticated: boolean;
  userId?: string;
  userRole?: UserRole;
  clientApp?: ClientApp;
  appPermissions?: string[];
  errorMessage?: string;
  statusCode?: number;
}

export interface AiUsageLogEntry {
  userId?: string | null;
  userRole: UserRole;
  clientApp: ClientApp;
  featureCategory: FeatureCategory;
  modelName: string;
  tokensPrompt: number;
  tokensCandidates: number;
  tokensTotal: number;
  latencyMs: number;
  httpStatus: number;
  status: 'success' | 'error';
  fallbackTriggered: boolean;
  errorCode?: string | null;
  errorMessage?: string | null;
}

