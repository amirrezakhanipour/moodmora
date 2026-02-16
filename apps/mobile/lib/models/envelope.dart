typedef FromJson<T> = T Function(Map<String, dynamic> json);

enum EnvelopeStatus { ok, blocked, error }

EnvelopeStatus _parseStatus(String s) {
  switch (s) {
    case 'ok':
      return EnvelopeStatus.ok;
    case 'blocked':
      return EnvelopeStatus.blocked;
    case 'error':
      return EnvelopeStatus.error;
    default:
      throw FormatException('Unknown envelope status: $s');
  }
}

class EnvelopeMeta {
  EnvelopeMeta({required this.contractVersion});

  final String contractVersion;

  factory EnvelopeMeta.fromJson(Map<String, dynamic> json) {
    final v = json['contract_version'];
    if (v is! String) {
      throw FormatException('meta.contract_version missing');
    }
    return EnvelopeMeta(contractVersion: v);
  }
}

class EnvelopeError {
  EnvelopeError({required this.code, required this.message});

  final String code;
  final String message;

  factory EnvelopeError.fromJson(Map<String, dynamic> json) {
    final c = json['code'];
    final m = json['message'];

    if (c is! String) {
      throw FormatException('error.code missing');
    }
    if (m is! String) {
      throw FormatException('error.message missing');
    }

    return EnvelopeError(code: c, message: m);
  }
}

class Envelope<T> {
  Envelope({
    required this.status,
    required this.requestId,
    required this.timestampMs,
    required this.meta,
    required this.data,
    required this.error,
  });

  final EnvelopeStatus status;
  final String requestId;
  final int timestampMs;
  final EnvelopeMeta meta;
  final T? data;
  final EnvelopeError? error;

  factory Envelope.fromJson(
    Map<String, dynamic> json, {
    required FromJson<T> fromJson,
  }) {
    final statusStr = json['status'];
    final reqId = json['request_id'];
    final ts = json['timestamp_ms'];
    final metaJson = json['meta'];
    final dataJson = json['data'];
    final errJson = json['error'];

    if (statusStr is! String) {
      throw FormatException('status missing');
    }
    if (reqId is! String) {
      throw FormatException('request_id missing');
    }
    if (ts is! int) {
      throw FormatException('timestamp_ms missing');
    }
    if (metaJson is! Map<String, dynamic>) {
      throw FormatException('meta missing');
    }

    final status = _parseStatus(statusStr);
    final meta = EnvelopeMeta.fromJson(metaJson);

    final T? data = (dataJson is Map<String, dynamic>)
        ? fromJson(dataJson)
        : null;
    final EnvelopeError? error = (errJson is Map<String, dynamic>)
        ? EnvelopeError.fromJson(errJson)
        : null;

    // Minimal invariants
    if (status == EnvelopeStatus.ok && data == null) {
      throw FormatException('ok envelope must include data');
    }
    if (status != EnvelopeStatus.ok && error == null) {
      // some endpoints may return error=null for blocked; adjust later if needed
      // For now, we enforce presence for non-ok
      throw FormatException('non-ok envelope must include error');
    }

    return Envelope<T>(
      status: status,
      requestId: reqId,
      timestampMs: ts,
      meta: meta,
      data: data,
      error: error,
    );
  }
}
