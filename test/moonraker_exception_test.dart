import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/data/moonraker/moonraker_exception.dart';

void main() {
  group('parseMoonrakerError', () {
    test('extracts JSON-RPC error message', () {
      final parsed = parseMoonrakerError({
        'error': {
          'code': 400,
          'message': 'Move out of range: 0.000 100.000 248.000 [0.000]',
        },
      });

      expect(parsed.rpcCode, 400);
      expect(
        parsed.message,
        'Move out of range: 0.000 100.000 248.000 [0.000]',
      );
    });

    test('decodes JSON string response body', () {
      final parsed = parseMoonrakerError(
        '{"error":{"message":"Unable to read tmc uart register IFCNT"}}',
      );

      expect(parsed.message, 'Unable to read tmc uart register IFCNT');
    });

    test('keeps plain text response bodies readable', () {
      final parsed = parseMoonrakerError('!! I2C timeout while reading sensor');

      expect(parsed.message, '!! I2C timeout while reading sensor');
    });
  });
}
