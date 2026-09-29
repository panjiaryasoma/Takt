import 'dart:convert';

Object? canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: canonicalJsonValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(canonicalJsonValue).toList(growable: false);
  }
  return value;
}

String deterministicJsonEncode(Object? value) =>
    jsonEncode(canonicalJsonValue(value));
