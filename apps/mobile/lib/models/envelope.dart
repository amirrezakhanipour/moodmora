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
  EnvelopeMeta({
    required this.contractVersion,
    this.requestId,
  });

  final String contractVersion;

  /// Optional — backend may or may not include it.
  /// (Some versions place request_id under meta, some don't send it at all.)
  final String? requestId;

  factory EnvelopeMeta.fromJson(Map<String, dynamic> json) {
    final v = json['contract_version'];
    if (v is! String) {
      throw FormatException('meta.contract_version missing');
    }

    final rid = json['request_id'];
    return EnvelopeMeta(
      contractVersion: v,
      requestId: rid is String ? rid : null,
    );
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

  /// Keep this field for app compatibility, but make parsing tolerant:
  /// - prefer top-level request_id if present
  /// - else meta.request_id if present
  /// - else fallback to 'n/a'
  final String requestId;

  /// Backend currently doesn't send timestamp_ms.
  /// Keep this for app compatibility; fallback to now() if missing.
  final int timestampMs;

  final EnvelopeMeta meta;
  final T? data;
  final EnvelopeError? error;

  factory Envelope.fromJson(
    Map<String, dynamic> json, {
    required FromJson<T> fromJson,
  }) {
    final statusStr = json['status'];
    final metaJson = json['meta'];
    final dataJson = json['data'];
    final errJson = json['error'];

    if (statusStr is! String) {
      throw FormatException('status missing');
    }
    if (metaJson is! Map<String, dynamic>) {
      throw FormatException('meta missing');
    }

    final status = _parseStatus(statusStr);
    final meta = EnvelopeMeta.fromJson(metaJson);

    // Optional fields (tolerant parsing)
    final topReqId = json['request_id'];
    final ts = json['timestamp_ms'];

    final requestId = (topReqId is String && topReqId.isNotEmpty)
        ? topReqId
        : (meta.requestId != null && meta.requestId!.isNotEmpty)
            ? meta.requestId!
            : 'n/a';

    final timestampMs =
        (ts is int) ? ts : DateTime.now().millisecondsSinceEpoch;

    final T? data =
        (dataJson is Map<String, dynamic>) ? fromJson(dataJson) : null;

    final EnvelopeError? error =
        (errJson is Map<String, dynamic>) ? EnvelopeError.fromJson(errJson) : null;

    // Minimal invariants (less strict to be backward/forward compatible)
    if (status == EnvelopeStatus.ok && data == null) {
      throw FormatException('ok envelope must include data');
    }
    // blocked/error may sometimes omit error; don't hard-fail
    // if (status != EnvelopeStatus.ok && error == null) { ... }

    return Envelope<T>(
      status: status,
      requestId: requestId,
      timestampMs: timestampMs,
      meta: meta,
      data: data,
      error: error,
    );
  }
}
