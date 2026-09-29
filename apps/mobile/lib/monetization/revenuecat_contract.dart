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

final class EntitlementState {
  const EntitlementState._({
    required this.access,
    required this.sync,
  });

  const EntitlementState.initial()
      : access = EntitlementAccess.unknown,
        sync = EntitlementSync.idle;

  final EntitlementAccess access;
  final EntitlementSync sync;

  EntitlementState loading() {
    return EntitlementState._(
      access: access,
      sync: EntitlementSync.loading,
    );
  }

  EntitlementState resolved({required bool isActive}) {
    return EntitlementState._(
      access: isActive ? EntitlementAccess.active : EntitlementAccess.inactive,
      sync: EntitlementSync.ready,
    );
  }

  EntitlementState failed() {
    return EntitlementState._(
      access: access,
      sync: EntitlementSync.error,
    );
  }
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
