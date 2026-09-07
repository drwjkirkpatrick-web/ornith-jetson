# Ornith-1.0-9B IQ3_M on Jetson Orin Nano 8GB

Deployment and benchmarking of **Ornith-1.0-9B-MTP IQ3_M** on NVIDIA Jetson Orin Nano 8GB (JetPack 7.2, L4T R36.5.2).

## Why Ornith-1.0-9B?

Ornith-1.0-9B IQ3_M is the **champion model** from the [jimenezcarrero/jetson-llm-benchmarks](https://github.com/jimenezcarrero/jetson-llm-benchmarks) campaign — a month-long, first-party benchmark on the same board (Jetson Orin Nano 8GB, JetPack 7.2). It was **undefeated across all four agent arenas**:

| Arena | Result | Notes |
|-------|--------|-------|
| Single-file task | PASS (2m 51s) | Bug fix + 3-site rename |
| Multi-file task | PASS 11/11 | 3 defects, 3 modules |
| 11-turn marathon | **11/11 perfect** | 18m 06s, 22.1 kJ |
| Context crusher (4,200 lines) | **perfect** both windows | 9.2K peak ctx at 32K — never compacted |

The model wins through **surgical context usage** — it reads only what it needs (82-4,477 prefill tokens/turn vs gemma's 2-17K) and stays disciplined at any window size.

## Optimized Configuration

The settings below come directly from the benchmark campaign's production deployment. Each flag has a measured reason:

```
llama-server -m Ornith-1.0-9B-MTP-IQ3_M.gguf \
  -ngl 99 -fa on \
  -ctk q4_0 -ctv q4_0 \
  -c 65536 -ub 128 -b 512 \
  -np 1 --jinja \
  --host 0.0.0.0 --port 8080
```

### Flag-by-flag rationale

| Flag | Value | Why |
|------|-------|-----|
| `-ngl 99` | All layers on GPU | Uses all 32 Ampere tensor cores (sm_87) for matmul |
| `-fa on` | Flash attention | 6-50x prompt eval speedup on Jetson; never disable |
| `-ctk q4_0` | Q4 KV cache | Free on Qwen3.5 family (hybrid-SSM, ~8 attention layers). f16 = q8 = q4 within noise |
| `-ctv q4_0` | Q4 V-cache | Same — no quality or speed cost vs f16 on this architecture |
| `-c 65536` | 65K context | Champion deployment window. Fits comfortably in 8GB with q4 KV |
| `-ub 128` | Small compute buffer | This buffer is the allocation that OOMs first on 8GB |
| `-b 512` | Batch 512 | Prompt processing batch size |
| `-np 1` | Single slot | All RAM for one model instance |
| `--jinja` | Chat template | Required for reasoning/thinking models to get proper chat formatting |
| `-t 6` | 6 threads | Matches 6-core Cortex-A78AE |

### Measured performance (from the benchmark campaign)

| Metric | Value |
|--------|-------|
| Model size | 4.34 GiB (IQ3_M) |
| pp512 (prompt eval) | 281 tok/s |
| tg128 (generation) | 10.3 tok/s |
| Max context (q4 KV) | 131K native |
| Board power under load | 16-21W (VDD_IN) |
| Full session energy | ~5 Wh |

## Hardware

- NVIDIA Jetson Orin Nano Developer Kit 8GB
- Ampere iGPU, sm_87, unified 7.4 GiB
- JetPack 7.2 (L4T R39.2), CUDA 13.2
- MAXN_SUPER power mode
- 6-core Cortex-A78AE

## Quick Start

### 1. Download the model

```bash
curl -L -o ~/models/Ornith-1.0-9B-MTP-IQ3_M.gguf \
  "https://huggingface.co/protoLabsAI/Ornith-1.0-9B-MTP-GGUF/resolve/main/Ornith-1.0-9B-MTP-IQ3_M.gguf"
```

### 2. Start the server

```bash
cd ~/projects/ornith-jetson
./start_ornith.sh
```

### 3. Chat

```bash
# Interactive
python3 chat_ornith.py --think

# Single prompt
python3 chat_ornith.py --once "Write a haiku about the ocean"

# With custom temperature
python3 chat_ornith.py --temp 0.6
```

### 4. Benchmark

```bash
./bench_ornith.sh
```

This runs two phases:
1. **llama-bench** — raw speed (pp512, tg128) at 1K/8K/32K/65K context
2. **Quality prompts** — 12-prompt suite (HTML, Python, poetry, math, creative, function calls)

### 5. Stop

```bash
./stop_ornith.sh
```

## Build Notes

### llama.cpp build for Jetson Orin (sm_87)

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=87 \
  -DGGML_CUDA_F16=ON \
  -DGGML_CUDA_FA=ON \
  -DGGML_CUDA_FA_ALL_QUANTS=ON \
  -DGGML_CUDA_GRAPHS=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j3 --target llama-server llama-bench llama-cli
```

**Important:** Use `-j3` max — `-j6` OOM-kills nvcc CUDA template compiles on 8GB.

### Optional: NO_VMM build

For 9B+ models, the Tegra cuMemCreate/VMM bug can cause allocation failures. Build a second binary with `-DGGML_CUDA_NO_VMM=ON`:

```bash
cmake -B build-novmm \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=87 \
  -DGGML_CUDA_NO_VMM=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-novmm --config Release -j3 --target llama-server
```

Then point `LLAMA_SERVER` to the novmm build:
```bash
LLAMA_SERVER=~/llama.cpp/build-novmm/bin/llama-server ./start_ornith.sh
```

## Operational Lessons (Jetson-specific)

From the benchmark campaign's operational findings:

- **Reboot before production serving** — NvMap/CMA fragments over repeated model loads. Configs that fit at boot OOM hours later.
- **Never set `cma=` kernel parameter** — breaks GPU detection.
- **Stop the GUI** for maximum RAM: `sudo systemctl stop gdm` (frees ~600MB).
- **Kill Ollama** if running: `pkill -f "ollama serve"` (frees GPU memory).
- Board power under agent load: 16-21W (VDD_IN); a full multi-turn session is ~5 Wh.

## Project Structure

```
ornith-jetson/
+-- start_ornith.sh        # Launch llama-server with optimized flags
+-- stop_ornith.sh         # Stop the server
+-- bench_ornith.sh        # Run full benchmark (speed + quality)
+-- bench_quality.py       # 12-prompt quality evaluation script
+-- chat_ornith.py         # Interactive / single-shot chat client
+-- test_prompts.json      # 12-prompt eval suite (6 categories)
+-- README.md              # This file
+-- LICENSE                # MIT
+-- .gitignore
+-- prompts/               # (empty, for custom prompts)
+-- results/               # Benchmark output (gitignored)
```

## References

- Benchmark campaign: [jimenezcarrero/jetson-llm-benchmarks](https://github.com/jimenezcarrero/jetson-llm-benchmarks)
- Model: [protoLabsAI/Ornith-1.0-9B-MTP-GGUF](https://huggingface.co/protoLabsAI/Ornith-1.0-9B-MTP-GGUF) on HuggingFace
- llama.cpp: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- Related: [jetson-model-zoo](https://github.com/drwjkirkpatrick-web/jetson-model-zoo) — 27-model benchmark on the same board

## License

MIT — See [LICENSE](LICENSE). Results and configs adapted from the jimenezcarrero benchmark campaign (CC BY 4.0). Absolute numbers depend on thermals, power mode, and software versions — validate before relying on them.