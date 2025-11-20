#!/usr/bin/env bash
#######################################
# Certificate Expiration Monitoring Script
#
# This script checks the expiration status of all TLS certificates
# and provides alerts for certificates that are expired or expiring soon.
#
# Globals:
#   CERT_BASE_DIR       - Base directory for certificate storage (default: ~/.config/vault/certs)
#   WARNING_THRESHOLD   - Days before expiration to warn (default: 30)
#   CRITICAL_THRESHOLD  - Days before expiration for critical alert (default: 7)
#
# Arguments:
#   --json              - Output in JSON format
#   --nagios            - Output in Nagios plugin format (for monitoring systems)
#   --service SERVICE   - Check only specific service
#
# Usage:
#   ./check-cert-expiration.sh                    # Human-readable output
#   ./check-cert-expiration.sh --json             # JSON output
#   ./check-cert-expiration.sh --nagios           # Nagios format
#   ./check-cert-expiration.sh --service postgres # Check only postgres
#
# Exit Codes:
#   0 - OK: All certificates valid and not expiring soon
#   1 - WARNING: Some certificates expiring within WARNING_THRESHOLD
#   2 - CRITICAL: Some certificates expired or expiring within CRITICAL_THRESHOLD
#
#######################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CERT_BASE_DIR="${HOME}/.config/vault/certs"
WARNING_THRESHOLD=${WARNING_THRESHOLD:-30}
CRITICAL_THRESHOLD=${CRITICAL_THRESHOLD:-7}

# Output format
OUTPUT_FORMAT="human"
SPECIFIC_SERVICE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --nagios)
            OUTPUT_FORMAT="nagios"
            shift
            ;;
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--json] [--nagios] [--service SERVICE]"
            exit 1
            ;;
    esac
done

# Get certificate expiration date in seconds since epoch
get_cert_expiration() {
    local cert_file="$1"

    if [ ! -f "$cert_file" ]; then
        echo "0"
        return
    fi

    local expiration=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiration" ]; then
        echo "0"
        return
    fi

    # Convert to epoch seconds
    date -j -f "%b %d %T %Y %Z" "$expiration" "+%s" 2>/dev/null || echo "0"
}

# Get days until expiration
get_days_until_expiration() {
    local cert_file="$1"
    local expiration_epoch=$(get_cert_expiration "$cert_file")

    if [ "$expiration_epoch" -eq 0 ]; then
        echo "-999"
        return
    fi

    local now_epoch=$(date +%s)
    local seconds_until_expiration=$((expiration_epoch - now_epoch))
    local days_until_expiration=$((seconds_until_expiration / 86400))

    echo "$days_until_expiration"
}

# Get certificate subject
get_cert_subject() {
    local cert_file="$1"
    openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//'
}

# Check single certificate
check_certificate() {
    local service="$1"
    local cert_file="$CERT_BASE_DIR/$service/server.crt"

    if [ ! -f "$cert_file" ]; then
        echo "MISSING|$service|Certificate file not found"
        return
    fi

    local days_remaining=$(get_days_until_expiration "$cert_file")
    local subject=$(get_cert_subject "$cert_file")

    if [ "$days_remaining" -eq -999 ]; then
        echo "ERROR|$service|Cannot parse certificate"
        return
    fi

    if [ "$days_remaining" -lt 0 ]; then
        echo "EXPIRED|$service|Expired $((days_remaining * -1)) days ago|$subject"
        return
    fi

    if [ "$days_remaining" -le "$CRITICAL_THRESHOLD" ]; then
        echo "CRITICAL|$service|Expires in $days_remaining days|$subject"
        return
    fi

    if [ "$days_remaining" -le "$WARNING_THRESHOLD" ]; then
        echo "WARNING|$service|Expires in $days_remaining days|$subject"
        return
    fi

    echo "OK|$service|Valid for $days_remaining days|$subject"
}

# Get list of services
get_services() {
    if [ -n "$SPECIFIC_SERVICE" ]; then
        echo "$SPECIFIC_SERVICE"
        return
    fi

    if [ ! -d "$CERT_BASE_DIR" ]; then
        return
    fi

    find "$CERT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

# Output in human-readable format
output_human() {
    local results=("$@")

    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Certificate Expiration Status${NC}"
    echo -e "${BLUE}  Warning Threshold: $WARNING_THRESHOLD days${NC}"
    echo -e "${BLUE}  Critical Threshold: $CRITICAL_THRESHOLD days${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    local ok_count=0
    local warning_count=0
    local critical_count=0
    local error_count=0

    for result in "${results[@]}"; do
        IFS='|' read -r status service message subject <<< "$result"

        case "$status" in
            OK)
                echo -e "${GREEN}✓ $service${NC}: $message"
                ((ok_count++))
                ;;
            WARNING)
                echo -e "${YELLOW}⚠ $service${NC}: $message"
                ((warning_count++))
                ;;
            CRITICAL|EXPIRED)
                echo -e "${RED}✗ $service${NC}: $message"
                ((critical_count++))
                ;;
            MISSING|ERROR)
                echo -e "${RED}✗ $service${NC}: $message"
                ((error_count++))
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo "  OK:       $ok_count"
    echo "  Warning:  $warning_count"
    echo "  Critical: $critical_count"
    echo "  Errors:   $error_count"
    echo ""

    if [ $critical_count -gt 0 ] || [ $error_count -gt 0 ]; then
        return 2
    elif [ $warning_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Output in JSON format
output_json() {
    local results=("$@")

    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"thresholds\": {"
    echo "    \"warning\": $WARNING_THRESHOLD,"
    echo "    \"critical\": $CRITICAL_THRESHOLD"
    echo "  },"
    echo "  \"certificates\": ["

    local first=true
    for result in "${results[@]}"; do
        IFS='|' read -r status service message subject <<< "$result"

        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi

        echo "    {"
        echo "      \"service\": \"$service\","
        echo "      \"status\": \"$status\","
        echo "      \"message\": \"$message\","
        echo "      \"subject\": \"$subject\""
        echo -n "    }"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Output in Nagios format
output_nagios() {
    local results=("$@")

    local ok_count=0
    local warning_count=0
    local critical_count=0
    local output_msg=""

    for result in "${results[@]}"; do
        IFS='|' read -r status service message subject <<< "$result"

        case "$status" in
            OK)
                ((ok_count++))
                ;;
            WARNING)
                ((warning_count++))
                output_msg="$output_msg $service($message);"
                ;;
            CRITICAL|EXPIRED|MISSING|ERROR)
                ((critical_count++))
                output_msg="$output_msg $service($message);"
                ;;
        esac
    done

    if [ $critical_count -gt 0 ]; then
        echo "CRITICAL: $critical_count certificate(s) need attention -$output_msg"
        return 2
    elif [ $warning_count -gt 0 ]; then
        echo "WARNING: $warning_count certificate(s) expiring soon -$output_msg"
        return 1
    else
        echo "OK: All $ok_count certificate(s) valid"
        return 0
    fi
}

# Main execution
main() {
    local services=$(get_services)

    if [ -z "$services" ]; then
        echo "No certificates found in $CERT_BASE_DIR"
        exit 0
    fi

    local results=()
    for service in $services; do
        results+=("$(check_certificate "$service")")
    done

    case "$OUTPUT_FORMAT" in
        json)
            output_json "${results[@]}"
            ;;
        nagios)
            output_nagios "${results[@]}"
            return $?
            ;;
        *)
            output_human "${results[@]}"
            return $?
            ;;
    esac
}

# Run main function
main
