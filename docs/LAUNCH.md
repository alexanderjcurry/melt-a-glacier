# Launching on the App Store and Google Play

iPhone is the first launch target, Android second. Everything that can live in
code already does. This page is the list of things only the account owner can
do (accounts, keys, store listings), in the order to do them, and where each
value goes once you have it.

**Rule for secrets:** ids that ship inside the app (AdMob ids, RevenueCat
*public* keys) go in the repo. Passwords, keystores, the App Store Connect API
key, the Play service account and RevenueCat *secret* keys never do: they go in
Codemagic or GitHub Actions secrets only. The repo is public; that is fine for
the first kind and the reason for the second rule. Make it private before
launch if you prefer (note: GitHub Pages, which hosts the web playtest and the
privacy policy, needs a paid GitHub plan for private repos).

## 0. Decide two permanent things

| What | Proposed | Where it's used |
|---|---|---|
| Bundle id / package name | `com.gamequarry.meltaglacier` | `export_presets.cfg` (Android + iOS), `codemagic.yaml`, `.github/workflows/mobile.yml` |
| Contact email for players | (yours) | replace `CONTACT_EMAIL` in `docs/privacy.html` |

The bundle id can never change once the app is in either store.

## 1. Apple (iPhone)

1. **App Store Connect > Apps > + New App**: platform iOS, name, primary language,
   bundle id (register it first under Certificates, IDs & Profiles > Identifiers,
   with the *In-App Purchase* capability), SKU `meltaglacier`.
2. **Agreements, Tax and Banking**: accept the *Paid Apps* agreement and add bank
   and tax info. In-app purchases don't work, even in TestFlight, until this is active.
3. **In-app purchases** (Monetization > In-App Purchases), both *Non-Consumable*:
   - `remove_ads_2x`: "Remove Ads + 2x Melting", $2.99
   - `golden_hair_dryer`: "Golden Hair Dryer", $0.99
   Each needs a display name, description and a review screenshot (any in-game
   screenshot of the catalogue works).
4. **App Store Connect API key** (Users and Access > Integrations > App Store
   Connect API > Team keys > +, role *App Manager*). Download the `.p8` once;
   note the Issuer ID and Key ID. This is for Codemagic.
5. **App Privacy** questionnaire (App Store Connect > App Privacy). Answer:
   - Data used to track you: Device ID (advertising), *only via AdMob*.
   - Data linked to you: none. Data not linked to you: Purchase History (RevenueCat),
     Device ID, Product Interaction, Advertising Data, Coarse Location (AdMob).
   - Privacy policy URL: `https://alexanderjcurry.github.io/melt-a-glacier/privacy.html`
6. **Age rating**: no objectionable content; answer "Yes" to "contains ads".

## 2. AdMob

1. admob.google.com > Apps > Add app, once for iOS and once for Android
   (choose "not yet published"; link the store listing later).
2. For each app create two ad units: **Rewarded** and **Interstitial**.
3. **Privacy & messaging**: create a *GDPR* message (EU consent form) for both apps,
   and an *IDFA explainer* message for the iOS app (this is what shows the iPhone
   tracking prompt). Publish both.
4. After the apps are live, add the store links, and set up `app-ads.txt` (AdMob shows
   the one line to put on a website you own; GitHub Pages works).

**Send me**: the two **app ids** (with a `~`) and four **ad unit ids** (with a `/`).
They go in `project.godot` (`[admob]` section) and `scripts/monetization/store_config.gd`.

## 3. RevenueCat

1. In your RevenueCat account, **Create new project** "Melt a Glacier".
2. Add an **App Store** app: bundle id, plus the *In-App Purchase Key* (App Store
   Connect > Users and Access > Integrations > In-App Purchase > generate; upload the
   `.p8`, with its Key ID and your Issuer ID).
3. Add a **Play Store** app later (needs the Play service account from step 5).
4. **Products**: import `remove_ads_2x` and `golden_hair_dryer`.
5. **Entitlements**: create `remove_ads` (attach `remove_ads_2x`) and `golden_dryer`
   (attach `golden_hair_dryer`). The game grants by entitlement, so these names matter.
6. Offerings aren't needed (no paywall).

**Send me**: the **public SDK keys** (Project settings > API keys): `appl_...` and
later `goog_...`. They go in `store_config.gd`.

## 4. iPhone: Codemagic

1. codemagic.io > sign in with GitHub > add the `melt-a-glacier` repo
   (it finds `codemagic.yaml` by itself).
2. Team settings > Integrations > **Developer Portal** > connect the App Store
   Connect API key from step 1.4. Name it exactly `Melt a Glacier ASC key`.
3. Team settings > **Code signing identities**: let Codemagic generate an *Apple
   Distribution* certificate and fetch an *App Store* profile for the bundle id.
4. App settings > Environment variables, group **apple**:
   - `APPLE_TEAM_ID`: your 10-character Team ID (developer.apple.com > Membership).
   - `APP_STORE_APPLE_ID`: the app's numeric Apple ID (App Store Connect > App Information).
5. **Start new build** (workflow *iPhone to TestFlight*). In about 20-30 minutes the
   build appears in TestFlight. Install the TestFlight app on your iPhone to play it.

The build stops early with a clear list if any store id is still a placeholder
(`tests/release_check.gd`), so a half-wired build never reaches testers.

Free Codemagic accounts get 500 Mac minutes a month: about 15-20 builds.

## 5. Android: Google Play

1. play.google.com/console: one-time **$25** registration. Personal accounts
   need ID verification, and **new personal accounts must run a closed test with
   at least 12 testers for 14 days in a row** before production is unlocked. Start
   that early.
2. **Create app**, then set up: content rating, target audience (**13+**, so the
   stricter Families ad rules don't apply), Ads = yes, data safety form (same answers
   as Apple's App Privacy), privacy policy URL.
3. **Upload key**: on your PC run (Java's keytool, comes with Android Studio):
   `keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`
   Back up `upload.jks` and the password somewhere safe. Play App Signing holds the
   real signing key, so a lost upload key can be reset, but it's slow.
4. GitHub repo > Settings > Secrets and variables > Actions, add:
   - `ANDROID_KEYSTORE_BASE64`: in PowerShell, `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload.jks"))`
   - `ANDROID_KEYSTORE_ALIAS`: `upload`
   - `ANDROID_KEYSTORE_PASSWORD`: the password
5. Actions > *Mobile builds* > Run workflow with **release** ticked. Download the
   `.aab` from the run and upload it by hand the **first** time (Play requires the
   first upload through the Console). Create the products `remove_ads_2x` and
   `golden_hair_dryer` (one-time products) after that first upload.
6. Optional, for one-click releases after that: Google Cloud service account with
   access in Play Console (Users and permissions), JSON key into the
   `PLAY_SERVICE_ACCOUNT_JSON` secret. Release runs then publish to internal testing.

## 6. Store listing (both stores)

- **Name** (30 chars max on both), **subtitle** (Apple, 30) / short description (Google, 80).
- **Description**, keywords (Apple, 100 chars).
- **Screenshots**: iPhone 6.9" (1320 x 2868 or landscape 2868 x 1320), 3-10 of them;
  Android phone, 2-8. The game is landscape, so landscape shots.
- **Icon**: `ui/icons/icon_1024.png` (rendered from `art/icon/app_icon.svg` by
  `art/icon/make_icons.sh`).
- Support URL (the GitHub Pages site is fine) and the privacy policy URL.

## What's already done in the code

- AdMob rewarded + interstitial ads, Google's consent form, the iPhone tracking
  prompt, a "Ad privacy choices" button for EU players, test ads in every debug
  build, retry with back-off, Remove Ads stops interstitials.
- RevenueCat purchases and restore, local store prices, purchases kept in the save
  so the game works offline.
- Godot 4.7.2 (both plugins need it), Android target API 36, App Bundle export,
  signing from secrets, iOS export with icons, launch screen, ATT text and the
  encryption-exemption flag.
- CI: every pull request builds the Android bundle and the iOS Xcode project and
  runs the smoke and ads/purchases tests. `codemagic.yaml` builds and uploads to TestFlight.
- Privacy policy page (`docs/privacy.html`, published with the web build).
