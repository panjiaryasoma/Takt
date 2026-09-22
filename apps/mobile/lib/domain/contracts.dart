enum ReadinessStatus {
  readyToEvaluate('READY_TO_EVALUATE'),
  needsReview('NEEDS_REVIEW'),
  eligibilityBlocked('ELIGIBILITY_BLOCKED'),
  deadlinePassed('DEADLINE_PASSED'),
  insufficientInformation('INSUFFICIENT_INFORMATION');

  const ReadinessStatus(this.wireValue);
  final String wireValue;
}

enum FeasibilityStatus {
  feasible('FEASIBLE'),
  feasibleWithTradeoffs('FEASIBLE_WITH_TRADEOFFS'),
  tightCapacity('TIGHT_CAPACITY'),
  notFeasibleUnderCurrentConstraints('NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS');

  const FeasibilityStatus(this.wireValue);
  final String wireValue;
}

enum CommitmentType {
  fixed('FIXED'),
  flexible('FLEXIBLE');

  const CommitmentType(this.wireValue);
  final String wireValue;
}

enum CanonicalFieldState {
  verified('VERIFIED'),
  singleSource('SINGLE_SOURCE'),
  conflict('CONFLICT'),
  missing('MISSING'),
  unverified('UNVERIFIED');

  const CanonicalFieldState(this.wireValue);
  final String wireValue;
}

enum RecommendationAction {
  accept('ACCEPT'),
  chooseAlternative('CHOOSE_ALTERNATIVE'),
  editConstraints('EDIT_CONSTRAINTS'),
  ignore('IGNORE');

  const RecommendationAction(this.wireValue);
  final String wireValue;
}

const readinessStatusWireValues = <String>[
  'READY_TO_EVALUATE',
  'NEEDS_REVIEW',
  'ELIGIBILITY_BLOCKED',
  'DEADLINE_PASSED',
  'INSUFFICIENT_INFORMATION',
];

const feasibilityStatusWireValues = <String>[
  'FEASIBLE',
  'FEASIBLE_WITH_TRADEOFFS',
  'TIGHT_CAPACITY',
  'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS',
];

const commitmentTypeWireValues = <String>['FIXED', 'FLEXIBLE'];

const canonicalFieldStateWireValues = <String>[
  'VERIFIED',
  'SINGLE_SOURCE',
  'CONFLICT',
  'MISSING',
  'UNVERIFIED',
];

const recommendationActionWireValues = <String>[
  'ACCEPT',
  'CHOOSE_ALTERNATIVE',
  'EDIT_CONSTRAINTS',
  'IGNORE',
];
