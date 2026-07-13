import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  final outputDirectory =
      Platform.environment['PERF_OUTPUT_DIR'] ?? 'build/performance/latest';
  return integrationDriver(
    responseDataCallback: (data) => writeResponseData(
      data,
      testOutputFilename: 'summary',
      destinationDirectory: outputDirectory,
    ),
    writeResponseOnFailure: true,
  );
}
