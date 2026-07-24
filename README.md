# ds4-server-gui

A macOS menu bar application that embeds `ds4-server` and provides an OpenAI / Anthropic compatible local LLM API.

## Features

- Lives in the menu bar — no Dock icon
- Embeds `ds4-server` in-process and manages its lifecycle
- On first launch (or if the model file is missing / fails to load), prompts the user to select a model file
- Real-time log window
- Settings UI: port, context size, KV cache, CORS, GPU power, etc.

## API Endpoints

The server listens on `http://127.0.0.1:8000` by default:

- `GET  /v1/models`
- `POST /v1/chat/completions` (OpenAI compatible)
- `POST /v1/messages` (Anthropic compatible)
- `POST /v1/responses` (Responses API)

## Build

The DS4 inference engine is vendored as a git submodule (`DS4MacOS/ds4-engine/upstream/`),
so clone with `--recursive`:

```bash
git clone --recursive <this-repo-url>
```

If you already have a plain clone, or after pulling a change that bumps the engine
submodule pin, fetch the submodule contents with:

```bash
git submodule update --init
```

Then build:

```bash
cd DS4MacOS
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DS4.xcodeproj -scheme DS4 -configuration Release \
  -derivedDataPath ./build build
```

The built app will be at:

```
DS4MacOS/build/Build/Products/Release/ds4-server-gui.app
```

## Usage

Launch `ds4-server-gui.app`. On first launch you will be prompted to select a `.gguf` model file.

Once a model is selected the server starts automatically. You can also configure the server via **Settings…** in the menu bar icon.

### Use with Claude Code

```sh
#!/bin/sh
unset ANTHROPIC_API_KEY
export ANTHROPIC_BASE_URL="http://127.0.0.1:8000"
export ANTHROPIC_AUTH_TOKEN="ds4-local"
export ANTHROPIC_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
exec "$HOME/.local/bin/claude" "$@"
```

## Requirements

- macOS 13.5+, Apple Silicon
- A DeepSeek V4 Flash GGUF model file (e.g. from [antirez/deepseek-v4-gguf](https://huggingface.co/antirez/deepseek-v4-gguf))

## Acknowledgements

This project is built on top of the excellent work by **[@antirez](https://github.com/antirez)**.

- [**ds4**](https://github.com/antirez/ds4) — the inference engine that powers this app. antirez wrote the entire C/Metal server from scratch, making it possible to run DeepSeek V4 Flash locally on Apple Silicon with remarkable efficiency.
- [**deepseek-v4-gguf**](https://huggingface.co/antirez/deepseek-v4-gguf) — the quantized model files hosted on Hugging Face.

ds4-server-gui is nothing more than a macOS GUI wrapper around his work. All the hard parts — inference, Metal GPU acceleration, the HTTP server — are his. Please go check out his projects and give him a ⭐!

## License

MIT
