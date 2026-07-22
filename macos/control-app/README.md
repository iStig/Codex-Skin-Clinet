# Codex Dream Skin Control App

Native macOS control surface for the existing Dream Skin engine.

```bash
./control-app/build-app.sh
open "release/Codex Dream Skin.app"
```

The built app embeds the installable macOS engine under `Contents/Resources/Engine`.
After installation, all controls target `~/.codex/codex-dream-skin-studio`; the app
does not depend on the source checkout remaining in place.
