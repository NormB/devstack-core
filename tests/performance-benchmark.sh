#!/bin/bash
#
# Performance Benchmark Suite
# Compares response times across all reference implementations
#
# Compatible with Bash 3.2+

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
ITERATIONS=100
WARMUP=10

# APIs to test (parallel arrays)
API_NAMES=("Python-FastAPI" "Python-API-First" "Go-Gin" "NodeJS-Express" "Rust-Actix")
API_URLS=("http://localhost:8000" "http://localhost:8001" "http://localhost:8002" "http://localhost:8003" "http://localhost:8004")

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Performance Benchmark Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Iterations: $ITERATIONS (after $WARMUP warmup requests)"
echo "Testing: ${#API_NAMES[@]} implementations"
echo ""

# Function to benchmark an endpoint
benchmark_endpoint() {
  local name=$1
  local url=$2

  # Warmup
  for ((i=1; i<=$WARMUP; i++)); do
    curl -s -o /dev/null "$url" 2>/dev/null || true
  done

  # Benchmark
  local total_time=0
  local successful=0
  local failed=0

  for ((i=1; i<=$ITERATIONS; i++)); do
    local start=$(date +%s%N 2>/dev/null || gdate +%s%N)
    if curl -s -f -o /dev/null "$url" 2>/dev/null; then
      local end=$(date +%s%N 2>/dev/null || gdate +%s%N)
      local duration=$(( (end - start) / 1000000 ))  # Convert to ms
      total_time=$((total_time + duration))
      ((successful++))
    else
      ((failed++))
    fi
  done

  if [ $successful -gt 0 ]; then
    local avg_time=$((total_time / successful))
    echo "$avg_time|$successful|$failed"
  else
    echo "0|0|$ITERATIONS"
  fi
}

# Results storage (parallel arrays)
ROOT_RESULTS=()
HEALTH_RESULTS=()
VAULT_RESULTS=()

echo -e "${YELLOW}Running benchmarks...${NC}"
echo ""

# Test each API
for i in "${!API_NAMES[@]}"; do
  api_name="${API_NAMES[$i]}"
  api_url="${API_URLS[$i]}"
  echo -n "Testing $api_name... "

  # Test root endpoint
  result=$(benchmark_endpoint "$api_name" "$api_url/")
  ROOT_RESULTS+=("$result")

  # Test health endpoint
  result=$(benchmark_endpoint "$api_name" "$api_url/health/")
  HEALTH_RESULTS+=("$result")

  # Test vault endpoint (if available)
  if [ "$api_name" = "Rust-Actix" ]; then
    result=$(benchmark_endpoint "$api_name" "$api_url/health/vault")
  else
    result=$(benchmark_endpoint "$api_name" "$api_url/examples/vault/secret/postgres")
  fi
  VAULT_RESULTS+=("$result")

  echo -e "${GREEN}Done${NC}"
done

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Benchmark Results${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to display results
display_results() {
  local title=$1
  shift
  local results=("$@")

  echo -e "${YELLOW}$title${NC}"
  printf "%-20s %10s %10s %10s\n" "Implementation" "Avg (ms)" "Success" "Failed"
  echo "--------------------------------------------------------"

  for i in "${!API_NAMES[@]}"; do
    api_name="${API_NAMES[$i]}"
    IFS='|' read -r avg_time successful failed <<< "${results[$i]}"
    printf "%-20s %10s %10s %10s\n" "$api_name" "$avg_time" "$successful" "$failed"
  done
  echo ""
}

# Display all results
display_results "Root Endpoint (GET /)" "${ROOT_RESULTS[@]}"
display_results "Health Check (GET /health/)" "${HEALTH_RESULTS[@]}"
display_results "Vault Integration" "${VAULT_RESULTS[@]}"

# Find fastest for each test
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

fastest_root=""
fastest_root_time=999999
for i in "${!API_NAMES[@]}"; do
  IFS='|' read -r avg_time successful failed <<< "${ROOT_RESULTS[$i]}"
  if [ "$successful" -gt 0 ] && [ "$avg_time" -lt "$fastest_root_time" ]; then
    fastest_root_time=$avg_time
    fastest_root="${API_NAMES[$i]}"
  fi
done

if [ -n "$fastest_root" ]; then
  echo -e "${GREEN}Fastest Root Endpoint:${NC} $fastest_root ($fastest_root_time ms avg)"
fi

fastest_health=""
fastest_health_time=999999
for i in "${!API_NAMES[@]}"; do
  IFS='|' read -r avg_time successful failed <<< "${HEALTH_RESULTS[$i]}"
  if [ "$successful" -gt 0 ] && [ "$avg_time" -lt "$fastest_health_time" ]; then
    fastest_health_time=$avg_time
    fastest_health="${API_NAMES[$i]}"
  fi
done

if [ -n "$fastest_health" ]; then
  echo -e "${GREEN}Fastest Health Check:${NC} $fastest_health ($fastest_health_time ms avg)"
fi

fastest_vault=""
fastest_vault_time=999999
for i in "${!API_NAMES[@]}"; do
  IFS='|' read -r avg_time successful failed <<< "${VAULT_RESULTS[$i]}"
  if [ "$successful" -gt 0 ] && [ "$avg_time" -lt "$fastest_vault_time" ]; then
    fastest_vault_time=$avg_time
    fastest_vault="${API_NAMES[$i]}"
  fi
done

if [ -n "$fastest_vault" ]; then
  echo -e "${GREEN}Fastest Vault Integration:${NC} $fastest_vault ($fastest_vault_time ms avg)"
fi

echo ""
echo -e "${BLUE}Benchmark complete!${NC}"
