import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

enum GeminiModel {
  flash('gemini-3.8-flash'),
  pro('gemini-2.5-pro');

  final String modelName;
  const GeminiModel(this.modelName);
}

class GeminiTokenUsage {
  final int promptTokens;
  final int candidatesTokens;
  final int totalTokens;

  const GeminiTokenUsage({
    required this.promptTokens,
    required this.candidatesTokens,
    required this.totalTokens,
  });

  factory GeminiTokenUsage.fromJson(Map<String, dynamic> json) {
    return GeminiTokenUsage(
      promptTokens: json['promptTokens'] as int? ?? 0,
      candidatesTokens: json['candidatesTokens'] as int? ?? 0,
      totalTokens: json['totalTokens'] as int? ?? 0,
    );
  }
}

class GeminiServiceResult {
  final bool success;
  final String? text;
  final String modelUsed;
  final bool fallbackTriggered;
  final GeminiTokenUsage usage;
  final int latencyMs;

  const GeminiServiceResult({
    required this.success,
    this.text,
    required this.modelUsed,
    required this.fallbackTriggered,
    required this.usage,
    required this.latencyMs,
  });

  factory GeminiServiceResult.fromJson(Map<String, dynamic> json) {
    return GeminiServiceResult(
      success: json['success'] as bool? ?? false,
      text: json['text'] as String?,
      modelUsed: json['modelUsed'] as String? ?? 'unknown',
      fallbackTriggered: json['fallbackTriggered'] as bool? ?? false,
      usage: GeminiTokenUsage.fromJson(
        json['usage'] as Map<String, dynamic>? ?? const {},
      ),
      latencyMs: json['latencyMs'] as int? ?? 0,
    );
  }
}

class GeminiApiException implements Exception {
  final String code;
  final String message;
  final int httpStatus;
  final bool retryable;

  const GeminiApiException({
    required this.code,
    required this.message,
    required this.httpStatus,
    required this.retryable,
  });

  @override
  String toString() => '[$code ($httpStatus)] $message';
}

class GeminiAiService {
  final SupabaseClient _supabase;

  GeminiAiService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  Future<String> _accessToken() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      throw const GeminiApiException(
        code: 'UNAUTHORIZED',
        message: 'You must be signed in before testing Gemini.',
        httpStatus: 401,
        retryable: false,
      );
    }

    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      final refreshed = await _supabase.auth.refreshSession();
      session = refreshed.session;
      if (session == null) {
        throw const GeminiApiException(
          code: 'UNAUTHORIZED',
          message: 'Your MarSU session has expired. Please sign in again.',
          httpStatus: 401,
          retryable: false,
        );
      }
    }
    return session.accessToken;
  }

  Future<GeminiServiceResult> testPrompt(
    String prompt, {
    GeminiModel model = GeminiModel.flash,
    GeminiModel? fallbackModel,
    String? systemInstruction,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw const GeminiApiException(
        code: 'BAD_REQUEST',
        message: 'Enter a prompt first.',
        httpStatus: 400,
        retryable: false,
      );
    }

    final accessToken = await _accessToken();
    final payload = <String, dynamic>{
      'action': 'test_prompt',
      'prompt': trimmedPrompt,
      'model': model.modelName,
      if (fallbackModel != null) 'fallbackModel': fallbackModel.modelName,
      'clientApp': 'flutter_student',
      if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
        'parameters': {'systemInstruction': systemInstruction.trim()},
    };

    try {
      final response = await _supabase.functions.invoke(
        'gemini-service',
        body: payload,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'x-client-app': 'flutter_student',
        },
      );
      final rawData = response.data;
      final data = rawData is String
          ? jsonDecode(rawData) as Map<String, dynamic>
          : Map<String, dynamic>.from(rawData as Map? ?? const {});

      if (response.status != 200 || data['success'] == false) {
        final error = Map<String, dynamic>.from(data['error'] as Map? ?? {});
        throw GeminiApiException(
          code: error['code'] as String? ?? 'EDGE_FUNCTION_ERROR',
          message: error['message'] as String? ?? 'Gemini request failed.',
          httpStatus: response.status,
          retryable: error['retryable'] as bool? ?? false,
        );
      }
      return GeminiServiceResult.fromJson(data);
    } on GeminiApiException {
      rethrow;
    } on FunctionException catch (error) {
      throw GeminiApiException(
        code: 'EDGE_FUNCTION_ERROR',
        message: error.toString(),
        httpStatus: error.status,
        retryable: error.status >= 500,
      );
    } catch (error) {
      throw GeminiApiException(
        code: 'NETWORK_ERROR',
        message: 'Could not reach gemini-service: $error',
        httpStatus: 504,
        retryable: true,
      );
    }
  }
}
