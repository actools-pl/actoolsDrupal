#!/usr/bin/env bash
# =============================================================================
# modules/ai/assistant.sh — Phase 4: AI-Native Dev Environment
# Uses Ollama + deepseek-coder with codebase context
# =============================================================================

INSTALL_DIR="${INSTALL_DIR:-/home/actools}"
OLLAMA_URL="http://localhost:11434"
AI_MODEL="deepseek-coder:1.3b"
AI_CONTEXT_DIR="${INSTALL_DIR}/.ai-context"

# Build context from actual codebase
build_context() {
  local target="${1:-all}"
  mkdir -p "$AI_CONTEXT_DIR"

  echo "Building AI context from codebase..."

  case "$target" in
    core)
      cat "${INSTALL_DIR}"/core/*.sh > "${AI_CONTEXT_DIR}/core.txt" 2>/dev/null
      ;;
    modules)
      find "${INSTALL_DIR}/modules" -name "*.sh" -exec cat {} \; \
        > "${AI_CONTEXT_DIR}/modules.txt" 2>/dev/null
      ;;
    all|*)
      cat "${INSTALL_DIR}"/core/*.sh \
          "${INSTALL_DIR}"/modules/**/*.sh \
          "${INSTALL_DIR}"/cli/commands/*.sh \
          > "${AI_CONTEXT_DIR}/full.txt" 2>/dev/null
      ;;
  esac

  local size
  size=$(wc -l "${AI_CONTEXT_DIR}/full.txt" 2>/dev/null | awk '{print $1}')
  echo "  ✓ Context built: ${size} lines of code indexed"
}

# Ask AI with codebase context
ai_ask() {
  local question="$1"
  local context_file="${AI_CONTEXT_DIR}/full.txt"

  if [[ ! -f "$context_file" ]]; then
    build_context all
  fi

  # Build prompt with codebase context
  local context
  context=$(cat "$context_file" 2>/dev/null | head -500)

  local prompt="You are an expert in Drupal 11, Bash scripting, Docker, and MariaDB.
You are helping with the Actools platform — a modular Drupal 11 installer.

Here is the relevant codebase context:
\`\`\`bash
${context}
\`\`\`

Question: ${question}

Give a specific, practical answer based on the actual code above."

  echo ""
  echo "=== Actools AI Assistant ==="
  echo "Model: ${AI_MODEL}"
  echo ""

  curl -s "${OLLAMA_URL}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${AI_MODEL}\",
      \"prompt\": $(echo "$prompt" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"),
      \"stream\": false,
      \"options\": {
        \"temperature\": 0.3,
        \"num_predict\": 512
      }
    }" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('response', 'No response'))
"
  echo ""
}

# Explain a specific file
ai_explain() {
  local file="$1"
  local full_path="${INSTALL_DIR}/${file}"

  if [[ ! -f "$full_path" ]]; then
    echo "File not found: ${full_path}"
    exit 1
  fi

  local code
  code=$(cat "$full_path")

  echo ""
  echo "=== AI Explain: ${file} ==="
  echo ""

  curl -s "${OLLAMA_URL}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${AI_MODEL}\",
      \"prompt\": $(echo "Explain this bash script concisely. What does it do, what are its main functions, and are there any potential issues?\n\n\`\`\`bash\n${code}\n\`\`\`" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"),
      \"stream\": false,
      \"options\": {\"temperature\": 0.2, \"num_predict\": 400}
    }" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('response', 'No response'))
"
  echo ""
}

# Security review
ai_review() {
  local target="${1:-core}"
  local files

  case "$target" in
    --security)
      files=$(find "${INSTALL_DIR}/core" "${INSTALL_DIR}/modules" \
        -name "*.sh" | head -5 | xargs cat 2>/dev/null | head -300)
      local review_type="security vulnerabilities, injection risks, and hardcoded secrets"
      ;;
    --performance)
      files=$(cat "${INSTALL_DIR}/modules/db/"*.sh 2>/dev/null)
      local review_type="performance issues, inefficient queries, and optimization opportunities"
      ;;
    *)
      files=$(cat "${INSTALL_DIR}/core/"*.sh 2>/dev/null)
      local review_type="code quality, best practices, and potential bugs"
      ;;
  esac

  echo ""
  echo "=== AI Code Review: ${target} ==="
  echo ""

  curl -s "${OLLAMA_URL}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${AI_MODEL}\",
      \"prompt\": $(echo "Review this bash code for ${review_type}. List specific issues found with line references where possible.\n\n\`\`\`bash\n${files}\n\`\`\`" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"),
      \"stream\": false,
      \"options\": {\"temperature\": 0.2, \"num_predict\": 500}
    }" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('response', 'No response'))
"
  echo ""
}

# Check Ollama is running
check_ollama() {
  curl -s "${OLLAMA_URL}/api/tags" &>/dev/null || {
    echo "Ollama not running. Starting..."
    ollama serve &>/dev/null &
    sleep 3
  }
}
