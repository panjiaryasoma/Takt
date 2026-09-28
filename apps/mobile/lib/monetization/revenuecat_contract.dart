enum EntitlementAccess {
  unknown,
  inactive,
  active,
}

enum EntitlementSync {
  idle,
  loading,
  ready,
  error,
}

enum PremiumFeature {
  alternativeCandidates,
}

abstract final class RevenueCatContract {
  static const entitlementIdentifier = 'pro';
  static const offeringIdentifier = 'default';
  static const lifetimePackageIdentifier = r'$rc_lifetime';
  static const testStoreProductIdentifier = 'takt_pro_lifetime_v1';
  static const alternativeCandidatesFeatureIdentifier = 'alternative_candidates';
}

abstract final class FeatureAccessPolicy {
  static bool canAccess(
    PremiumFeature feature,
    EntitlementAccess entitlementAccess,
  ) {
    switch (feature) {
      case PremiumFeature.alternativeCandidates:
        return entitlementAccess == EntitlementAccess.active;
    }
  }
}
