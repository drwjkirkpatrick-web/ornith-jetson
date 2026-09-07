#!/usr/bin/env python3
"""chat_ornith.py — Interactive chat with Ornith-1.0-9B via llama-server.

Usage:
  python3 chat_ornith.py                  # interactive chat
  python3 chat_ornith.py --once "prompt"  # single prompt, exit
  python3 chat_ornith.py --think          # show reasoning_content
  python3 chat_ornith.py --temp 0.6       # override temperature
"""
import argparse
import json
import sys
import urllib.request
import urllib.error

DEFAULT_URL = "http://localhost:8080/v1/chat/completions"


def send_message(url: str, messages: list, temp: float,
                 max_tokens: int, show_think: bool) -> dict:
    """Send a chat completion request to the llama-server."""
    payload = {
        "model": "ornith",
        "messages": messages,
        "temperature": temp,
        "max_tokens": max_tokens,
        "stream": False,
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            return json.loads(resp.read())
    except urllib.error.URLError as e:
        print(f"Error: cannot connect to server at {url}", file=sys.stderr)
        print(f"  {e}", file=sys.stderr)
        print("  Is the server running? Try: ./start_ornith.sh", file=sys.stderr)
        sys.exit(1)


def extract_response(data: dict, show_think: bool) -> str:
    """Extract text from the API response."""
    choice = data.get("choices", [{}])[0]
    msg = choice.get("message", {})
    content = msg.get("content", "")
    reasoning = msg.get("reasoning_content", "")

    if show_think and reasoning:
        return f"<think>\n{reasoning}\n</think>\n\n{content}"
    return content


def main():
    parser = argparse.ArgumentParser(description="Chat with Ornith-1.0-9B")
    parser.add_argument("--url", default=DEFAULT_URL, help="Server URL")
    parser.add_argument("--temp", type=float, default=0.3, help="Temperature")
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--once", metavar="PROMPT", help="Single prompt mode")
    parser.add_argument("--think", action="store_true", help="Show reasoning")
    parser.add_argument("--system", default=None, help="System prompt")
    args = parser.parse_args()

    messages = []
    if args.system:
        messages.append({"role": "system", "content": args.system})

    if args.once:
        messages.append({"role": "user", "content": args.once})
        data = send_message(args.url, messages, args.temp,
                            args.max_tokens, args.think)
        text = extract_response(data, args.think)
        print(text)
        # Print stats if available
        usage = data.get("usage", {})
        if usage:
            print(f"\n---\nTokens: {usage.get('completion_tokens', '?')} "
                  f"generated, {usage.get('prompt_tokens', '?')} prompt",
                  file=sys.stderr)
        return

    # Interactive mode
    print("Ornith-1.0-9B IQ3_M Chat (type 'quit' to exit, 'think' to toggle)")
    print(f"  URL: {args.url}")
    print(f"  Temp: {args.temp}")
    print(f"  Think: {'ON' if args.think else 'OFF'}")
    print("")

    show_think = args.think
    while True:
        try:
            user = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye!")
            break
        if not user:
            continue
        if user.lower() in ("quit", "exit", "q"):
            break
        if user.lower() == "think":
            show_think = not show_think
            print(f"  [think: {'ON' if show_think else 'OFF'}]")
            continue

        messages.append({"role": "user", "content": user})
        data = send_message(args.url, messages, args.temp,
                            args.max_tokens, show_think)
        text = extract_response(data, show_think)
        print(f"\nornith> {text}\n")
        messages.append({"role": "assistant", "content": text})

        usage = data.get("usage", {})
        if usage:
            print(f"  [{usage.get('completion_tokens', '?')} tok, "
                  f"{usage.get('prompt_tokens', '?')} prompt]",
                  file=sys.stderr)


if __name__ == "__main__":
    main()