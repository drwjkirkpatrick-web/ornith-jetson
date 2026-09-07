#!/usr/bin/env python3
"""bench_quality.py — Run quality prompt suite against Ornith-1.0-9B.

Sends each prompt from test_prompts.json to llama-cli and captures
the response, generation speed, and token count. Outputs JSONL.
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path


def parse_speed(output: str) -> dict:
    """Extract speed metrics from llama-cli -st output."""
    metrics = {}
    # [ Prompt: 92.5 t/s | Generation: 24.5 t/s ]
    m = re.search(r"Prompt:\s*([\d.]+)\s*t/s.*Generation:\s*([\d.]+)\s*t/s", output)
    if m:
        metrics["prompt_tps"] = float(m.group(1))
        metrics["gen_tps"] = float(m.group(2))
    return metrics


def run_prompt(cli: str, model: str, prompt: str, max_tokens: int,
               context: int, temp: float) -> dict:
    """Run a single prompt through llama-cli."""
    cmd = [
        cli,
        "-m", model,
        "-p", prompt,
        "-n", str(max_tokens),
        "-c", str(context),
        "--temp", str(temp),
        "-ngl", "99",
        "-fa", "on",
        "--jinja",
        "--no-conversation",
        "--no-display-prompt",
        "-st",
    ]
    start = time.time()
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600
        )
        elapsed = time.time() - start
        # llama-cli prints banner to stdout; find the actual response
        # The -st summary line is at the end
        output = result.stdout
        # Extract the response text (between banner and summary line)
        lines = output.strip().split("\n")
        # Find the summary line and remove it from response
        summary_line = ""
        response_lines = []
        for line in lines:
            if re.match(r"\[ Prompt:.*Generation:.*\]", line.strip()):
                summary_line = line.strip()
            else:
                response_lines.append(line)
        response = "\n".join(response_lines).strip()
        metrics = parse_speed(summary_line)
        metrics["elapsed_s"] = round(elapsed, 1)
        metrics["response_chars"] = len(response)
        metrics["response"] = response
        metrics["rc"] = result.returncode
        if result.returncode != 0:
            metrics["error"] = result.stderr[:500]
        return metrics
    except subprocess.TimeoutExpired:
        return {
            "elapsed_s": 600,
            "error": "timeout (600s)",
            "rc": -1,
        }


def main():
    parser = argparse.ArgumentParser(description="Quality prompt evaluation")
    parser.add_argument("--model", required=True, help="Path to GGUF model")
    parser.add_argument("--cli", required=True, help="Path to llama-cli")
    parser.add_argument("--prompts", required=True, help="Path to test_prompts.json")
    parser.add_argument("--output", required=True, help="Output JSONL path")
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--context", type=int, default=8192)
    parser.add_argument("--temp", type=float, default=0.3)
    args = parser.parse_args()

    prompts_data = json.loads(Path(args.prompts).read_text())
    prompts = prompts_data["prompts"]

    print(f"Running {len(prompts)} prompts...")
    print(f"  Model:   {args.model}")
    print(f"  Temp:    {args.temp}")
    print(f"  Context: {args.context}")
    print(f"  Max tok: {args.max_tokens}")
    print("")

    results = []
    with open(args.output, "w") as f:
        for i, p in enumerate(prompts, 1):
            pid = p["id"]
            cat = p["category"]
            name = p["name"]
            prompt_text = p["prompt"]
            print(f"[{i}/{len(prompts)}] {cat}/{pid}: {name}...")

            metrics = run_prompt(
                args.cli, args.model, prompt_text,
                args.max_tokens, args.context, args.temp
            )

            record = {
                "id": pid,
                "category": cat,
                "name": name,
                "prompt": prompt_text,
                "temp": args.temp,
                "context": args.context,
                **metrics,
            }
            f.write(json.dumps(record) + "\n")
            f.flush()
            results.append(record)

            if "gen_tps" in metrics:
                print(f"  -> {metrics['gen_tps']:.1f} tok/s, "
                      f"{metrics.get('response_chars', 0)} chars, "
                      f"{metrics['elapsed_s']}s")
            else:
                print(f"  -> error: {metrics.get('error', 'unknown')}")
            print("")

    # Summary
    print("=" * 50)
    print("  Quality Benchmark Summary")
    print("=" * 50)
    successful = [r for r in results if "gen_tps" in r]
    if successful:
        avg_tps = sum(r["gen_tps"] for r in successful) / len(successful)
        avg_chars = sum(r.get("response_chars", 0) for r in successful) / len(successful)
        print(f"  Prompts run:    {len(results)}")
        print(f"  Successful:     {len(successful)}")
        print(f"  Avg gen tok/s:  {avg_tps:.1f}")
        print(f"  Avg response:   {avg_chars:.0f} chars")
    else:
        print("  No successful runs!")
    print(f"  Results file:   {args.output}")


if __name__ == "__main__":
    main()