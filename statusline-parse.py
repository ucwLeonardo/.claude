#!/usr/bin/env python3
"""Parse Claude Code statusline JSON and output shell variable assignments.
Usage: python3 statusline-parse.py '<json_string>'
"""
import json, sys

try:
    d = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
except Exception:
    d = {}

def g(obj, *keys):
    for k in keys:
        if isinstance(obj, dict):
            obj = obj.get(k)
        else:
            return ""
    return "" if obj is None else str(obj)

def shell_escape(s):
    return s.replace("'", "'\\''")

def emit(name, value):
    print(f"{name}='{shell_escape(value)}'")

emit("version", g(d, "version"))
emit("model_display", g(d, "model", "display_name"))
emit("model_id", g(d, "model", "id"))
emit("cwd", g(d, "workspace", "current_dir") or g(d, "cwd"))
emit("used_pct", g(d, "context_window", "used_percentage"))
emit("remaining_pct", g(d, "context_window", "remaining_percentage"))
emit("total_in", g(d, "context_window", "total_input_tokens"))
emit("total_out", g(d, "context_window", "total_output_tokens"))
emit("ctx_size", g(d, "context_window", "context_window_size"))
emit("total_cost", g(d, "cost", "total_cost_usd"))
emit("total_dur_ms", g(d, "cost", "total_duration_ms"))
emit("lines_added", g(d, "cost", "total_lines_added"))
emit("lines_removed", g(d, "cost", "total_lines_removed"))
emit("output_style", g(d, "output_style", "name") or "default")
emit("vim_mode", g(d, "vim", "mode"))
emit("agent_name", g(d, "agent", "name"))
