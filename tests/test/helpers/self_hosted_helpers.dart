import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:test/test.dart';

String environmentValue(String name, [String fallback = '']) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  return value.trim();
}

Future<bool> isReachable(String url, {Map<String, String> headers = const {}}) async {
  try {
    await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 5));
    return true;
  } catch (_) {
    return false;
  }
}

bool skipUnless(bool available, String reason) {
  if (available) {
    return false;
  }
  markTestSkipped(reason);
  return true;
}

Future<String> probeContentType(String url, Map<String, String> headers) async {
  final response = await http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(seconds: 30));
  expect(response.statusCode, 200, reason: 'GET $url');
  expect(response.bodyBytes, isNotEmpty);
  return (response.headers['content-type'] ?? '').split(';').first.trim();
}

class SilentLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

void silenceInterpreterLogs() {
  Logger.level = Level.off;
  Logger.defaultOutput = () => SilentLogOutput();
}
