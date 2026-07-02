// ============================================================
// KATIYA STATION RMS — DIO HTTP API CLIENT
// Enterprise HTTP client with JWT auth, auto-refresh,
// error mapping, logging, and timeout configuration
// ============================================================

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/api_constants.dart';
import '../errors/app_exceptions.dart';
import '../storage/secure_storage.dart';

// ── Result Type for API calls ──────────────────────────────
typedef ApiResult<T> = Future<T>;

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  bool _initialized = false;

  // ── Initialize (called in main.dart) ──────────────────────
  void initialize() {
    if (_initialized) return;

    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.apiBase,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // ── Auth Interceptor (JWT + Auto-Refresh) ──────────────
    _dio.interceptors.add(_JwtInterceptor(_dio));

    // ── Logger (dev only) ──────────────────────────────────
    if (kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
        ),
      );
    }

    _initialized = true;
  }

  Dio get dio {
    assert(_initialized, 'ApiClient must be initialized before use.');
    return _dio;
  }

  // ── GET ────────────────────────────────────────────────────
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── POST ───────────────────────────────────────────────────
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── PUT ────────────────────────────────────────────────────
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── PATCH ──────────────────────────────────────────────────
  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── DELETE ─────────────────────────────────────────────────
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Upload multipart ───────────────────────────────────────
  Future<Response> upload(
    String path,
    FormData formData, {
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      return await _dio.post(
        path,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
        onSendProgress: onSendProgress,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Error Mapper ───────────────────────────────────────────
  AppException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('Connection timed out. Please check your internet.');

      case DioExceptionType.connectionError:
        return const NetworkException('Cannot reach the server. Check your network connection.');

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;

        String message = 'An error occurred.';
        String? code;

        if (responseData is Map<String, dynamic>) {
          message = responseData['message'] as String? ??
              responseData['error'] as String? ??
              message;
          code = responseData['code'] as String?;
        }

        if (statusCode == 401) {
          return AuthException(message);
        } else if (statusCode == 403) {
          return PermissionException(message);
        } else if (statusCode == 404) {
          return ApiException(message, statusCode: 404, code: code ?? 'NOT_FOUND');
        } else if (statusCode == 409) {
          return ApiException(message, statusCode: 409, code: code ?? 'CONFLICT');
        } else if (statusCode == 422) {
          return ValidationException(message, code: code ?? 'VALIDATION_ERROR');
        } else if (statusCode != null && statusCode >= 500) {
          return const ServerException();
        }
        return ApiException(message, statusCode: statusCode, code: code);

      case DioExceptionType.cancel:
        return const AppExceptionCancelled();

      default:
        return UnknownException(
          e.message ?? 'An unknown error occurred.',
          originalError: e,
        );
    }
  }
}

// ── JWT Interceptor ────────────────────────────────────────
class _JwtInterceptor extends QueuedInterceptorsWrapper {
  final Dio _dio;
  bool _isRefreshing = false;

  _JwtInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.instance.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final newTokens = await _refreshToken();
        if (newTokens != null) {
          // Retry the original request with the new token
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer ${newTokens['accessToken']}';
          final response = await _dio.fetch(opts);
          _isRefreshing = false;
          return handler.resolve(response);
        }
      } catch (_) {
        // Refresh failed — clear session
        await SecureStorage.instance.clearSession();
        _isRefreshing = false;
      }
    }
    _isRefreshing = false;
    handler.next(err);
  }

  Future<Map<String, dynamic>?> _refreshToken() async {
    final refreshToken = await SecureStorage.instance.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await Dio().post(
        '${ApiConstants.apiBase}${ApiConstants.refresh}',
        data: {'refreshToken': refreshToken},
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final accessToken = data['accessToken'] as String;
        final newRefreshToken = data['refreshToken'] as String?;

        await SecureStorage.instance.saveAccessToken(accessToken);
        if (newRefreshToken != null) {
          await SecureStorage.instance.saveRefreshToken(newRefreshToken);
        }
        return data;
      }
    } catch (_) {}
    return null;
  }
}

// ── Cancelled Exception (non-error) ───────────────────────
class AppExceptionCancelled extends AppException {
  const AppExceptionCancelled() : super('Request was cancelled.', code: 'CANCELLED');
}
