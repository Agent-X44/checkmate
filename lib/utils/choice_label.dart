/// Removes a choice's own A-D prefix when its position already supplies it.
String stripChoiceLabel(Object? value, int index) {
  var text = (value ?? '').toString().trim();
  final letter = String.fromCharCode(65 + index);
  final prefix = RegExp('^$letter[.):]\\s*', caseSensitive: false);
  while (prefix.hasMatch(text)) {
    text = text.replaceFirst(prefix, '').trimLeft();
  }
  return text;
}
