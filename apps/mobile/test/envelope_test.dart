import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/envelope.dart';
import 'package:mobile/models/health_payload.dart';

void main() {
  group('Envelope.fromJson', () {
    test('parses ok envelope with data', () {
      final json = <String, dynamic>{
        'status': 'ok',
        'request_id': 'req_test_1',
        'timestamp_ms': 1700000000000,
        'data': {'service': 'api-worker', 'ok': true},
        'error': null,
        'meta': {'contract_version': '1.0.0'},
      };

      final env = Envelope<HealthPayload>.fromJson(
        json,
        fromJson: HealthPayload.fromJson,
      );

      expect(env.status, EnvelopeStatus.ok);
      expect(env.requestId, 'req_test_1');
      expect(env.meta.contractVersion, '1.0.0');
      expect(env.data, isNotNull);
      expect(env.data!.service, 'api-worker');
      expect(env.data!.ok, true);
      expect(env.error, isNull);
    });

    test('parses error envelope with error payload', () {
      final json = <String, dynamic>{
        'status': 'error',
        'request_id': 'req_test_2',
        'timestamp_ms': 1700000000001,
        'data': null,
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'bad input',
          'details': {'path': 'input.draft_text'},
        },
        'meta': {'contract_version': '1.0.0'},
      };

      final env = Envelope<Map<String, dynamic>>.fromJson(
        json,
        fromJson: (j) => j, // should not be called (data is null)
      );

      expect(env.status, EnvelopeStatus.error);
      expect(env.data, isNull);
      expect(env.error, isNotNull);
      expect(env.error!.code, 'VALIDATION_ERROR');
      expect(env.error!.message, 'bad input');
    });

    test('throws if ok envelope has null data', () {
      final json = <String, dynamic>{
        'status': 'ok',
        'request_id': 'req_test_3',
        'timestamp_ms': 1700000000002,
        'data': null,
        'error': null,
        'meta': {'contract_version': '1.0.0'},
      };

      expect(
        () => Envelope<Map<String, dynamic>>.fromJson(json, fromJson: (j) => j),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on unknown status', () {
      final json = <String, dynamic>{
        'status': 'weird',
        'request_id': 'req_test_4',
        'timestamp_ms': 1700000000003,
        'data': {'x': 1},
        'error': null,
        'meta': {'contract_version': '1.0.0'},
      };

      expect(
        () => Envelope<Map<String, dynamic>>.fromJson(json, fromJson: (j) => j),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
