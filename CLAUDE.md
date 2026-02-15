# Noa Flutter - Development Guidelines

## Security & Privacy

- **All pushed code must be checked for PII, secrets, API keys, and IP before committing**
- Never hardcode secrets, tokens, or credentials - use `.env` (already gitignored)
- This is a public repository - treat every commit as publicly visible
- Never reference individuals by gendered terms - use they/them/the user

## Pre-Commit Hook

A pre-commit hook is installed at `.git/hooks/pre-commit` that scans staged files for:
- `.env` files (not `.env.template`)
- API key patterns (`sk-`, `pk-`, `key-` followed by long alphanumeric strings)
- Secret assignments (`password=`, `secret=`, `token=` with values)
- Hardcoded auth URL parameters (`?token=`, `?key=`, `?api_key=`)
- Email addresses
- Private IP addresses

### Setup

```bash
chmod +x scripts/pre-commit-check.sh
cp scripts/pre-commit-check.sh .git/hooks/pre-commit
```

## Project Structure

- `lib/models/app_logic_model.dart` - Core state machine and BLE interaction logic
- `assets/lua_scripts/` - Lua scripts uploaded to Frame device (app.lua is main event loop)
- `lib/noa_api.dart` - Backend API client
- `lib/stt_api.dart` - Deepgram speech-to-text client
- `lib/pages/` - UI pages (Flutter)
- `lib/util/` - Utilities (audio, BLE helpers, etc.)

## Hardware Constraints (Brilliant Labs Frame)

- 256 KB RAM - Lua must be memory-efficient, use `collectgarbage`
- Display: 640x400, ~22 chars/line, 3 lines max, 16 colors per frame
- Camera: max 720x720 JPEG
- Microphone: 8kHz or 16kHz only
- Battery: 210 mAh, auto-sleep after ~18s of no BLE messages
