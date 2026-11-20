# Unsold: Cricket League Auction Simulator

A realistic franchise-cricket auction game built in **Godot 4.7**. It runs on the **web** and on **Android** (Google Play).

- **Single player**: you run one franchise against 9 AI franchises. Works offline.
- **Online multiplayer**: 2–10 friends join a room with a 6-character code, using **Firebase Realtime Database**. Empty franchises can be filled by AI.
- **Realistic rules**:
  - ₹120 Cr purse
  - squads of 18–25 players, with a maximum of 8 overseas
  - at most 4 overseas players in the XI
  - a clean T20-league bid ladder: +10 L up to ₹1 Cr, +20 L to ₹2 Cr, +25 L to ₹5 Cr, +50 L to ₹15 Cr, then +1 Cr
  - marquee and role-based sets, and an accelerated round for unsold players
  - you can't bid money you need to keep for filling the rest of your squad
- **Live, turn-by-turn bidding**: while you're still in, AI franchises raise one increment at a time and every raise resets the clock, so the lot keeps coming back to you ("MUM BID — YOUR CALL: ₹4.5 Cr?"). A lot only goes "going once, going twice…" when nobody else wants the player. You can pass and bid again to re-enter.
- **Auctioneer voice**: an ElevenLabs auctioneer calls every lot and bid ("Two crore fifty! Anyone at two crore seventy-five?"), with on-screen subtitles. In a fast bidding war he skips to the current price instead of falling behind.
- **AI difficulty** (lobby setting): *Easy* AI bids cautiously and misjudges players, *Medium* behaves like a typical auction room, *Hard* chases stars, rarely skips a good player and answers your bids quickly.
- **Choosing the winner**: the host picks one of two modes.
  - **Simulated season**: a ball-by-ball T20 match engine runs a round-robin league, then Qualifier 1, the Eliminator, Qualifier 2 and the Final, with a points table, NRR and scorecards.
  - **Team score**: each squad gets an instant rating for batting, bowling, balance, depth and value for money.
- 214 fictional players. Each default name is a sound-alike: it keeps a similar first initial and a different surname, so fans can tell who's who without real names being used.
- **Roster editor** (home screen → *Roster editor*): rename any player or team, including team codes, on your own device.
  - Renames are saved locally in `user://roster.json`.
  - **Export** copies your renames as a roster file. On the web it also downloads the file.
  - **Import** applies a pasted roster file, so fans can share name packs.
  - Names are for display only. Online rooms sync player and team IDs, so each device shows its own roster.
- 10 fictional city franchises, e.g. *Mumbai Monsoon*, *Chennai Surge*, *Ahmedabad Kites*. They have their own names, colours and original crests; nothing is derived from any real league's branding.

## Project layout

```
data/players.json, data/teams.json   player ratings, roles, base prices, teams
scripts/engine/   pure game logic (no I/O): rules, auction, ai, xi, score, sim, db
scripts/store/    RoomStore API + LocalStore (single player) + RtdbStore (Firebase)
                  auctioneer.gd: host-side loop that closes lots and makes AI bid
scripts/firebase/ Firebase client: REST + SSE on Android/desktop, JS SDK bridge on web
scripts/ui/       screens built in code (home, lobby, auction, review, results)
web/firebase_bridge.js   loaded at runtime by the web build
database.rules.json      Realtime Database security rules
tests/                   headless tests and tools (see below)
```

## Running

Open the folder in Godot 4.7 and press **F5**. From the command line:

```
godot --path .
```

## Tests

```
godot --headless --path . -s res://tests/run_tests.gd      # engine unit tests
godot --headless --path . -s res://tests/check_scripts.gd  # compile every script
godot --headless --path . -s res://tests/bidding_flow.gd  # plays lots as a human who keeps raising
godot --path . -s res://tests/ui_smoke.gd                  # drives the UI, saves screenshots to user://smoke
```

The engine tests check the following:
- bid increments and purse reserves
- the overseas and squad caps
- that bids are validated
- that full 10-team AI auctions on several seeds finish with legal squads and XIs, and realistic top prices
- that the same seed always produces the same season (multiplayer depends on this)
- that average scores look like T20 scores (~175)
- that stronger squads win most matches

## Two editions

| | Public edition | Friends edition (private) |
|---|---|---|
| Export presets | `Web`, `Android` | `Web (Friends)`, `Android (Friends)` |
| Player and team names | Fictional sound-alikes | Real names from `private/real_roster.json` |
| Crests | Generated art | Drawn badges showing the real codes (no real logos) |
| Android package | `com.kaustubhvats.unsold` "Unsold" | `com.kaustubhvats.unsold.friends` "Unsold Friends" (both can be installed side by side) |
| Output | `export/web`, `export/android` | `export/friends/web`, `export/friends/android` |

The Friends presets add the `realnames` feature tag and bundle `private/`. The public presets exclude `private/`, so their builds contain no real names. To try the Friends edition from the editor or the command line, pass `--realnames` after `--`, for example `godot --path . -- --realnames`.

```
godot --headless --path . --export-debug "Android (Friends)" export/friends/android/unsold-friends-debug.apk
godot --headless --path . --export-release "Web (Friends)" export/friends/web/index.html
```

**Keep the Friends edition private.** `private/` is git-ignored. Don't upload the Friends build to the Play Store or to a public URL; share the APK directly with friends. Both editions can play in the same online room, because rooms sync IDs and each device shows its own names.

## Accounts and sign-in

Online rooms require an account. Solo play works offline without one.

| Method | Web | Android | Desktop |
|---|---|---|---|
| Email + password (sign up, sign in, forgot password) | Firebase JS SDK | Identity Toolkit REST | REST |
| Google | Popup (Firebase JS SDK) | Native account picker: `GoogleSignIn` plugin (Credential Manager, with a classic Google Sign-In fallback for older Play services) | Not available |

- Sessions persist: a refresh token on Android/desktop, the SDK's own persistence on the web.
- The account name becomes the player name the first time.

### Android Google sign-in plugin

The source is in `android_plugin/`, a Java Godot v2 plugin. The add-on `addons/google_signin/` packs `bin/GoogleSignIn-release.aar` and its Maven dependencies into **Gradle** Android exports. Gradle builds are enabled in both Android presets.

To rebuild the AAR after changing the Java code:

```
cd android_plugin
gradlew.bat :plugin:assembleRelease
copy plugin\build\outputs\aar\plugin-release.aar ..\addons\google_signin\bin\GoogleSignIn-release.aar
```

The Gradle export needs the Android build template: **Project → Install Android Build Template**, or `--install-android-build-template` on the command line.

### Signing fingerprints (Google sign-in on Android)

Firebase must know the SHA-1 of every key that signs the app. Add them in Firebase console → Project settings → *Unsold Android* and *Unsold Friends Android* → **Add fingerprint**.

- **Debug key** (`~/.android/debug.keystore`): already added. The current test APKs are signed with it.
- **Play Store**: after the first upload, copy the **App signing key certificate SHA-1** from Play Console → Setup → App integrity, and add it to the Firebase Android app. Also add your upload key's SHA-1. Without these, Google sign-in fails in the store build with error 10.

## Firebase setup (needed for multiplayer only)

Firebase settings are kept out of the repository:
- `scripts/firebase/config.example.gd` is a template with placeholders.
- `scripts/firebase/config.local.gd` holds your real values. It is git-ignored, and the game loads it automatically when it exists.
- Without it, online play is disabled and solo play still works.

To set up Firebase:

1. Create a project at <https://console.firebase.google.com>.
2. In **Build → Authentication → Sign-in method**, enable **Email/Password** and **Google**. Copy the Google provider's *Web client ID* into `GOOGLE_WEB_CLIENT_ID`.
3. Go to **Build → Realtime Database** and create a database. Then open the **Rules** tab and paste in the contents of `database.rules.json`.
4. In **Project settings → Your apps**, add a **Web app**. Copy `scripts/firebase/config.example.gd` to `config.local.gd` and fill in `apiKey`, `authDomain`, `databaseURL`, `projectId`, `appId` and the Google Web client ID.
5. Run the game, choose **Create Room**, and share the code.

There's no server to run. The host's device acts as the auctioneer: it closes lots and drives the AI teams. If the host disconnects, the earliest-joined player who is still online takes over automatically. Bids are Realtime Database transactions, so two people bidding at the same moment can't both win. The free Spark plan is enough for casual play.

> Firebase web API keys identify the project; they are not secrets. Access is controlled by the
> database rules. Rooms are not deleted automatically. You can clear old ones from the console now and then.

## Exporting

The export templates must be installed (**Editor → Manage Export Templates**).

### Web

```
godot --headless --path . --export-release Web export/web/index.html
```

Upload `export/web/` to any static host, e.g. Firebase Hosting (`firebase init hosting`, public dir `export/web`), GitHub Pages or itch.io. The build is single-threaded, so it needs no special COOP/COEP headers.

### Android / Google Play

1. In **Editor Settings → Export → Android**, set the Android SDK path (`%LOCALAPPDATA%\Android\Sdk`) and the Java SDK path (JDK 17).
2. Debug APK for testing on a phone:
   ```
   godot --headless --path . --export-debug Android export/android/unsold-debug.apk
   adb install -r export/android/unsold-debug.apk
   ```
   The Android emulator needs **OpenGL ES 3**: open Extended controls → Settings → Advanced → *OpenGL ES API level: Renderer maximum*. AVDs that are capped at ES 2.0 will crash on start.
3. **Play Store (AAB)**:
   - Run **Project → Install Android Build Template**.
   - In the Android export preset, set *Gradle Build → Use Gradle Build* to ON and *Export Format* to **AAB**.
   - Create an upload keystore:
     ```
     keytool -genkeypair -v -keystore unsold-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
     ```
   - Set the release keystore in the preset, or through the environment variables `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER` and `_PASSWORD`.
   - Export a release, then upload the `.aab` in the Play Console.
   - Bump `version/code` in the preset for every upload.

   Keep the keystore safe and out of git (`*.jks` is already in `.gitignore`).

## Art and audio

All art is original and was generated with ChatGPT. The raw outputs are in `assets/source/`, which is excluded from exports. They were sliced and cleaned into these files:

| File | Used for |
|---|---|
| `assets/logo.png` | Home screen logo |
| `assets/bg.jpg` | Floodlit stadium backdrop on every screen |
| `assets/crests/<team id>.png` | The 10 team crests (fictional designs, not official logos) |
| `assets/roles/<bat,wk,ar,pace,spin>.png` | Role icons on player cards and lists |
| `assets/icon.png` | App icon (web favicon and Android launcher) |

Audio was generated with the ElevenLabs CLI and lives in `assets/audio/`:

- **Music**: `music_loop.mp3`, a 20-second seamless loop.
- **Sound effects**: `bid`, `outbid`, `tick`, `sold` (gavel and applause), `unsold`, `click` and `win` (crowd and fanfare).
- **Auctioneer voice**: `vo_sold`, `vo_unsold` and `vo_going` ("Going once… going twice…"), plus `vo/bid_<lakh>.mp3` for every value on the bid ladder and `vo/open_<base>.mp3` for each base price. The spoken text (also shown as subtitles) is in `data/auctioneer.json`.

The `Sfx` autoload (`scripts/sfx.gd`) plays these. The speaker button in each screen header toggles the music, and the setting is remembered between sessions.

## Build size

- The Android APK presets build **arm64-v8a only**, with native libraries compressed. That gives about 30 MB per APK, and covers practically all phones from 2017 onward. For a Play Store **AAB**, turn `armeabi-v7a` back on: Google Play delivers only the matching CPU code to each phone, so download size isn't affected.
- `export/` contains a `.gdignore` file so that built files are never re-imported into the game.
- The bundled fonts are trimmed to the characters the UI uses: Latin, ₹, punctuation and the UI symbols. The full fonts are kept in `assets/source/fonts/`. If you add a new symbol to the UI, add it to the trimming script's ranges (or copy the full font back), and run `tests/check_glyphs.gd`.

## Fonts

Three fonts are bundled in `assets/fonts/`, all under the SIL Open Font License:
- **Bebas Neue**, the display face used for names, prices and headings.
- **Noto Sans** for body text.
- **Noto Sans Symbols 2**, which makes ₹ and the icons render the same on every platform.

## Disclaimer

This is an independent game. All players, franchises, names, crests and statistics are fictional, and any resemblance to real people or teams is coincidental. The game isn't affiliated with or endorsed by any cricket board, league or franchise.
