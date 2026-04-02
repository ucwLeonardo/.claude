#!/usr/bin/env bash
# Claude Code Status Line — AI STATUSLINE
# Receives JSON on stdin from Claude Code
# Uses python3 for reliable JSON parsing
# Adapts to terminal width (min 50, max 120)

input=$(cat)

# --- Extract all fields via python3 (pass JSON as argument) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$SCRIPT_DIR/statusline-parse.py" "$input" 2>/dev/null)"

# --- Defaults ---
[ -z "$version" ]       && version="?"
[ -z "$model_display" ] && model_display="?"
[ -z "$total_in" ]      && total_in=0
[ -z "$total_out" ]     && total_out=0
[ -z "$output_style" ]  && output_style="default"

# --- Terminal width → box width ---
term_w=$(tput cols 2>/dev/null || echo 80)
BOX=$term_w
[ "$BOX" -gt 120 ] && BOX=120
[ "$BOX" -lt 50 ]  && BOX=50

# --- Algorithm from model id ---
algo="Claude"
echo "$model_id" | grep -qi "opus"   && algo="Opus"
echo "$model_id" | grep -qi "sonnet" && algo="Sonnet"
echo "$model_id" | grep -qi "haiku"  && algo="Haiku"

# --- Context size label ---
ctx_label=""
if [ -n "$ctx_size" ] && [ "$ctx_size" != "0" ]; then
  ctx_k=$(( ${ctx_size%.*} / 1000 ))
  ctx_label="${ctx_k}K"
fi

# --- Session duration ---
dur_label=""
if [ -n "$total_dur_ms" ] && [ "${total_dur_ms%.*}" -gt 0 ] 2>/dev/null; then
  dur_s=$(( ${total_dur_ms%.*} / 1000 ))
  dur_m=$(( dur_s / 60 ))
  dur_h=$(( dur_m / 60 ))
  rem_m=$(( dur_m % 60 ))
  if [ "$dur_h" -gt 0 ]; then
    dur_label="${dur_h}h${rem_m}m"
  elif [ "$dur_m" -gt 0 ]; then
    dur_label="${dur_m}m$(( dur_s % 60 ))s"
  else
    dur_label="${dur_s}s"
  fi
fi

# --- Cost label ---
cost_label=""
if [ -n "$total_cost" ] && [ "$total_cost" != "0" ]; then
  cost_label="\$${total_cost}"
fi

# --- Git info ---
git_branch=""
git_sync=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
               || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  upstream=$(git -C "$cwd" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
  if [ -n "$upstream" ]; then
    ahead=$(git -C "$cwd" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git -C "$cwd" rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      git_sync="~${ahead}/+${behind}"
    elif [ "$ahead" -gt 0 ]; then
      git_sync="+${ahead}"
    elif [ "$behind" -gt 0 ]; then
      git_sync="-${behind}"
    fi
  else
    git_sync="local"
  fi
fi

# --- Context progress bar (adaptive width) ---
# Reserve: "| " (2) + "CTX " (4) + "[" (1) + "] " (2) + "NNN%" (4) + " NNNK free" (max ~12) + " |" (2) = ~27 fixed
bar_width=$(( BOX - 36 ))
[ "$bar_width" -lt 10 ] && bar_width=10
[ "$bar_width" -gt 30 ] && bar_width=30

if [ -n "$used_pct" ] && [ "$used_pct" != "0" ] && [ "${used_pct%.*}" -gt 0 ] 2>/dev/null; then
  pct_int=${used_pct%.*}
  filled=$(( pct_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))
  bar=""
  for (( i=0; i<filled; i++ )); do bar="${bar}#"; done
  for (( i=0; i<empty; i++ ));  do bar="${bar}-"; done
  ctx_bar="[${bar}] ${pct_int}%"
  free_pct="${remaining_pct:-$(( 100 - pct_int ))}%"
  [ -n "$ctx_label" ] && free_pct="${free_pct}/${ctx_label}"
else
  bar=""
  for (( i=0; i<bar_width; i++ )); do bar="${bar}-"; done
  ctx_bar="[${bar}] 0%"
  free_pct="100%"
  [ -n "$ctx_label" ] && free_pct="100%/${ctx_label}"
fi

# --- Token display ---
total_tokens=$(( total_in + total_out ))
if [ "$total_tokens" -gt 0 ]; then
  if [ "$total_tokens" -ge 1000000 ]; then
    tok_disp="$(( total_tokens / 1000000 )).$(( (total_tokens % 1000000) / 100000 ))M"
  elif [ "$total_tokens" -ge 1000 ]; then
    tok_disp="$(( total_tokens / 1000 )).$(( (total_tokens % 1000) / 100 ))K"
  else
    tok_disp="${total_tokens}"
  fi
else
  tok_disp="0"
fi

# --- Build compact usage ---
usage_parts="${tok_disp}tok"
[ -n "$dur_label" ]  && usage_parts="${usage_parts} ${dur_label}"
[ -n "$cost_label" ] && usage_parts="${usage_parts} ${cost_label}"
la="${lines_added:-0}"; lr="${lines_removed:-0}"
if [ "$la" -gt 0 ] 2>/dev/null || [ "$lr" -gt 0 ] 2>/dev/null; then
  usage_parts="${usage_parts} +${la}/-${lr}"
fi

# --- Extra flags ---
extras=""
[ -n "$vim_mode" ]   && extras="${extras} vim:${vim_mode}"
[ -n "$agent_name" ] && extras="${extras} @${agent_name}"

# --- Compact env ---
env_line="v${version} ${algo} ${model_display}${extras}"

# --- PWD + git ---
pwd_short="${cwd}"
# Shorten home prefix
pwd_short="${pwd_short/#$HOME/\~}"
pwd_line="${pwd_short}"
if [ -n "$git_branch" ]; then
  pwd_line="${pwd_line} [${git_branch}]"
  [ -n "$git_sync" ] && pwd_line="${pwd_line} ${git_sync}"
fi

# ===== RENDER =====
# Truncate helper: truncates text to fit inside box (BOX - 4 for "| " and " |")
max_content=$(( BOX - 4 ))
trunc() {
  local text="$1"
  if [ "${#text}" -gt "$max_content" ]; then
    echo "${text:0:$(( max_content - 1 ))}~"
  else
    echo "$text"
  fi
}

pad() {
  local text="$1"
  local len=${#text}
  local spaces=$(( BOX - len - 4 ))
  [ "$spaces" -lt 0 ] && spaces=0
  printf "| %s%*s|\n" "$text" "$spaces" ""
}

sep() {
  printf "+"
  printf '%*s' "$(( BOX - 2 ))" '' | tr ' ' '-'
  printf "+\n"
}

title() {
  local text="$1"
  local inner=$(( BOX - 2 ))
  local pad_l=$(( (inner - ${#text}) / 2 ))
  local pad_r=$(( inner - ${#text} - pad_l ))
  printf "|%*s%s%*s|\n" "$pad_l" "" "$text" "$pad_r" ""
}

printf "\n"
sep
title "AI STATUSLINE"
sep
pad "$(trunc " ENV  ${env_line}")"
pad "$(trunc " CTX  ${ctx_bar} ${free_pct}")"
pad "$(trunc " USE  ${usage_parts}")"
pad "$(trunc " PWD  ${pwd_line}")"
sep
printf "\n"
