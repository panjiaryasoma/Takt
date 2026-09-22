import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/domain/contracts.dart';

void main() {
  test('wire contracts match backend canonical values', () {
    expect(
      ReadinessStatus.values.map((value) => value.wireValue).toList(),
      readinessStatusWireValues,
    );
    expect(
      FeasibilityStatus.values.map((value) => value.wireValue).toList(),
      feasibilityStatusWireValues,
    );
    expect(
      CommitmentType.values.map((value) => value.wireValue).toList(),
      commitmentTypeWireValues,
    );
    expect(
      CanonicalFieldState.values.map((value) => value.wireValue).toList(),
      canonicalFieldStateWireValues,
    );
    expect(
      RecommendationAction.values.map((value) => value.wireValue).toList(),
      recommendationActionWireValues,
    );
  });
}
