# Kinda Capsule Web3D Showcase

This package turns the Web3D repair scenario into a real Capsule episode:

- a procedural Three.js product viewer with deliberate `broken` and repaired modes;
- a fixed Playwright interaction path with screenshots, video, raw interaction
  and performance evidence;
- a `Kinda.Capsule.Task` that provisions the fixture into a fresh Sandbox;
- live grading plus digest-verified export and sealed-evidence regrading that
  recomputes gates and scores from raw domain evidence;
- a one-page viewer where findings link back to timeline events and evidence.

## Run the visual fixture

```bash
cd priv/web3d
npm ci
npx playwright install chromium
npm run dev
```

Open `http://127.0.0.1:5173`. Add `?mode=broken` for the faulty baseline.

## Run and export an episode

The browser executable must already be installed in Playwright's cache.

```bash
mix web3d.showcase --parent tmp/capsules --bundle episode
```

The resulting bundle contains `manifest.json`, task/trace/score documents,
screenshots, interaction video, and metric evidence. A neighboring SQLite file
indexes the episode and its reset, command, artifact, and sealed events. The
bundle can be checked and regraded without a live Capsule:

```elixir
Kinda.Capsule.Bundle.verify("episode")
Kinda.Capsule.Bundle.regrade("episode", Kinda.Capsule.Web3D.Verifier)
```

Bundle export writes and verifies a sibling staging tree, then atomically
publishes it at the requested path. Regrading defaults to portable verifier
source identity; pass `identity: :exact` to require the recorded local BEAM
build identity as well.

Fixture and browser-verifier integrity are computed by the trusted Task and
sealed as `integrity.json`; they are not self-reported by browser code. The
included `expert-review.json` is explicitly illustrative and versioned. It
demonstrates the expert-evidence contract but is not presented as a real human
review. This package currently evaluates a supplied repaired fixture; inserting
a model-driven inspection and patch action is intentionally a separate agent
harness concern.

The browser verifier and host runner use a bounded ready/ack handoff for the
fixed artifact set. The runner projects evidence into Capsule-owned staging
while the verifier action is still alive, before hashing and attachment, so
evidence does not depend on a command workspace surviving after command exit.
The episode runtime points to `browser.json`, which records the resolved browser
version, architecture/CPU class, headless/GPU mode, and timing policy.

This is an episode/evidence showcase, not a containment claim. The task and
verifier are trusted host components; browser isolation comes from the selected
Sandbox backend and Playwright runtime.
