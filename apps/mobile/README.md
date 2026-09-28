# Takt Mobile

Flutter source scaffold.

If Android/iOS runner directories have not been generated on your machine:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter test
flutter run
```

Do not let generated calendar UI blur the authority boundary:

```text
suggested work window != accepted commitment
```

## RevenueCat configuration contract

RevenueCat is a mobile-owned access dependency. It must never change deadline,
eligibility, source-conflict, feasibility, solver, or recommendation truth.

Block 1 freezes these identifiers:

```text
entitlement: pro
Test Store product: takt_pro_lifetime_v1
Offering identifier: default
lifetime package: $rc_lifetime
premium feature: alternative_candidates
```

The Shipaton demo path uses RevenueCat Test Store on Android. Google Play
provider setup and credentials are deferred.

Create an ignored local Test Store config from the committed example:

```bash
cp config/revenuecat.test.example.json config/revenuecat.test.local.json
```

Replace the placeholder with the RevenueCat **public Test Store SDK key**, then
run the debug build with:

```bash
flutter run --debug \
  --dart-define-from-file=config/revenuecat.test.local.json
```

Test Store config is intentionally rejected for profile and release builds.
Production Android config accepts only a public `goog_` SDK key, but a working
Google Play RevenueCat provider is not required for the Block 1 / Next Gen demo
path.

Never put RevenueCat secret `sk_` keys in the app or repository. Do not commit
`*.local.json` config files.

Block 1 defines the config and entitlement-access contracts only. SDK
configuration, CustomerInfo, Offerings, purchase, restore, and paywall behavior
belong to later 4C blocks.
