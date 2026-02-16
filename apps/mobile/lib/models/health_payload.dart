class HealthPayload {
  HealthPayload({required this.service, required this.ok});

  final String service;
  final bool ok;

  factory HealthPayload.fromJson(Map<String, dynamic> json) {
    final s = json['service'];
    final o = json['ok'];
    if (s is! String) throw FormatException('data.service missing');
    if (o is! bool) throw FormatException('data.ok missing');
    return HealthPayload(service: s, ok: o);
  }
}
