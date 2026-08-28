# Kinda Capsule Web3D Showcase

This package turns the Web3D repair scenario into a real Capsule episode:

- a procedural Three.js product viewer with deliberate `broken` and repaired modes;
- a fixed Playwright interaction path with screenshots, video, interaction trace,
  performance metrics, gates, scored dimensions, and explicit failure modes;
- a `Kinda.Capsule.Task` that provisions the fixture into a fresh Sandbox;
- live grading plus digest-verified export and sealed-evidence regrading;
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

This is an episode/evidence showcase, not a containment claim. The task and
verifier are trusted host components; browser isolation comes from the selected
Sandbox backend and Playwright runtime.
