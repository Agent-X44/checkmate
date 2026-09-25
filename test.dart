import 'dart:core';
import 'package:flutter/foundation.dart';

void main() {
  final uri = Uri.tryParse('checkmate://join?code=ZV269C');
  debugPrint(uri?.queryParameters['code']);
}
