#!/bin/sh

# Campus network auto-login script - POSIX sh version
# Compatible with POSIX sh, dash, ash, zsh, and bash when invoked as sh.

# Default configuration
MAIN_URL="http://192.168.2.135/"
USERID="" # Set your campus network username here or in the config file.
PASSWORD="" # Set your campus network password here or in the config file.
MAX_ATTEMPTS_ALLOWED=5
SERVICE="EDUNET"
PING_HOST="223.5.5.5"
PING_ATTEMPTS=5
PING_TIMEOUT=1
PING_INTERVAL=1
HEALTHY_LOG_INTERVAL=300
LAST_HEALTHY_LOG_TIME=0

# Get the script directory in a POSIX-sh friendly way.
get_script_dir() {
    script_path="$0"

    case "$script_path" in
        */*) script_dir="${script_path%/*}" ;;
        *) script_dir="." ;;
    esac

    case "$script_dir" in
        /*) printf '%s\n' "$script_dir" ;;
        *)
            saved_pwd=$(pwd)
            if cd "$script_dir" 2>/dev/null; then
                pwd
                cd "$saved_pwd" || exit 1
            else
                printf '%s\n' "$script_dir"
            fi
            ;;
    esac
}

SCRIPT_DIR=$(get_script_dir)
CONFIG_FILE="$SCRIPT_DIR/scunet_config.conf"

# Trim leading and trailing whitespace.
trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Load configuration file.
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        printf "\033[1;93m[Config]\033[0m Loading settings from: %s\n" "$CONFIG_FILE"

        while IFS= read -r line || [ -n "$line" ]; do
            trimmed_line=$(trim "$line")

            case "$trimmed_line" in
                ''|\#*) continue ;;
                *=*) ;;
                *) continue ;;
            esac

            key=$(trim "${trimmed_line%%=*}")
            value=$(trim "${trimmed_line#*=}")
            value=$(printf '%s' "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

            case "$key" in
                MAIN_URL) MAIN_URL="$value" ;;
                USERID) USERID="$value" ;;
                PASSWORD) PASSWORD="$value" ;;
                SERVICE) SERVICE="$value" ;;
                PING_HOST) PING_HOST="$value" ;;
                PING_ATTEMPTS) PING_ATTEMPTS="$value" ;;
                PING_TIMEOUT) PING_TIMEOUT="$value" ;;
                PING_INTERVAL) PING_INTERVAL="$value" ;;
                HEALTHY_LOG_INTERVAL) HEALTHY_LOG_INTERVAL="$value" ;;
                MAX_ATTEMPTS_ALLOWED) MAX_ATTEMPTS_ALLOWED="$value" ;;
            esac
        done < "$CONFIG_FILE"
    else
        printf "\033[1;93m[Config]\033[0m No config file found. Using default settings.\n"
    fi
}

# Normalize configuration values after loading.
normalize_config() {
    case "$MAIN_URL" in
        */) ;;
        *) MAIN_URL="$MAIN_URL/" ;;
    esac
}

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
CONTENT_TYPE="application/x-www-form-urlencoded; charset=UTF-8"

COOKIE_JAR=""
RESPONSE_FILE=""
REDIRECT_FILE=""

make_temp_file() {
    name="$1"
    tmp_base="${TMPDIR:-/tmp}"
    tmp_base="${tmp_base%/}"

    if command -v mktemp >/dev/null 2>&1; then
        mktemp "$tmp_base/campus_network_${name}.XXXXXX"
    else
        temp_file="$tmp_base/campus_network_${name}_$$"
        : > "$temp_file" || return 1
        printf '%s\n' "$temp_file"
    fi
}

init_temp_files() {
    COOKIE_JAR=$(make_temp_file cookies) || return 1
    RESPONSE_FILE=$(make_temp_file response) || return 1
    REDIRECT_FILE=$(make_temp_file redirect) || return 1
    return 0
}

cleanup() {
    [ -n "$COOKIE_JAR" ] && rm -f "$COOKIE_JAR"
    [ -n "$RESPONSE_FILE" ] && rm -f "$RESPONSE_FILE"
    [ -n "$REDIRECT_FILE" ] && rm -f "$REDIRECT_FILE"
}

app_exit() {
    delay_time="$1"
    printf "\033[1;93m[Exit]\033[0m The program is exiting.\n" >&2
    sleep "$delay_time"
    cleanup
    exit 0
}

trap_handler() {
    printf "\n\033[1;93m[Interrupted]\033[0m User requested exit.\n" >&2
    app_exit 0
}

trap 'trap_handler' INT TERM
trap 'cleanup' EXIT

check_network_connection_status() {
    host="${1:-$PING_HOST}"
    attempts="${2:-$PING_ATTEMPTS}"
    timeout="${3:-$PING_TIMEOUT}"
    interval="${4:-$PING_INTERVAL}"

    i=1
    while [ "$i" -le "$attempts" ]; do
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
        i=$((i + 1))
    done
    return 1
}

current_timestamp() {
    date +%s 2>/dev/null || printf '0\n'
}

is_non_negative_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

should_log_healthy_status() {
    now="${1:-$(current_timestamp)}"
    interval="${HEALTHY_LOG_INTERVAL:-300}"
    last_log_time="${LAST_HEALTHY_LOG_TIME:-0}"

    is_non_negative_integer "$interval" || interval=300
    is_non_negative_integer "$now" || now=0
    is_non_negative_integer "$last_log_time" || last_log_time=0

    if [ "$interval" -eq 0 ]; then
        LAST_HEALTHY_LOG_TIME="$now"
        return 0
    fi

    if [ "$last_log_time" -eq 0 ] || \
       [ "$now" -lt "$last_log_time" ] || \
       [ $((now - last_log_time)) -ge "$interval" ]; then
        LAST_HEALTHY_LOG_TIME="$now"
        return 0
    fi

    return 1
}

get_service_code() {
    case "$SERVICE" in
        "CHINATELECOM")
            echo "%E7%94%B5%E4%BF%A1%E5%87%BA%E5%8F%A3"
            ;;
        "CHINAMOBILE")
            echo "%E7%A7%BB%E5%8A%A8%E5%87%BA%E5%8F%A3"
            ;;
        "CHINAUNICOM")
            echo "%E8%81%94%E9%80%9A%E5%87%BA%E5%8F%A3"
            ;;
        "EDUNET")
            echo "internet"
            ;;
        *)
            echo "%E7%94%B5%E4%BF%A1%E5%87%BA%E5%8F%A3"
            ;;
    esac
}

make_abs_url() {
    loc="$1"
    base="$2"

    case "$loc" in
        http://*|https://*)
            printf '%s\n' "$loc"
            ;;
        /*)
            origin=$(printf '%s\n' "$base" | sed 's#^\(https\{0,1\}://[^/]*\).*#\1#')
            printf '%s%s\n' "$origin" "$loc"
            ;;
        *)
            base_dir="${base%/*}"
            printf '%s/%s\n' "$base_dir" "$loc"
            ;;
    esac
}

extract_location() {
    sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' "$1" | head -n 1 | tr -d '\r\n'
}

get_redirect_url() {
    printf "\033[1;93m[Redirect]\033[0m Handling campus network redirects...\n" >&2

    redirect_headers=$(make_temp_file redirect_headers) || return 1
    redirect_content=$(make_temp_file redirect_content) || {
        rm -f "$redirect_headers"
        return 1
    }

    printf "\033[1;93m[Step 1]\033[0m Requesting main URL: %s\n" "$MAIN_URL" >&2
    curl -s -i \
         -H "Accept: */*" \
         -H "User-Agent: $USER_AGENT" \
         -c "$COOKIE_JAR" \
         --connect-timeout 10 \
         --max-time 30 \
         "$MAIN_URL" > "$redirect_headers" 2>/dev/null

    if [ $? -ne 0 ]; then
        printf "\033[1;91m[Redirect failed]\033[0m Could not access the main URL.\n" >&2
        rm -f "$redirect_headers" "$redirect_content"
        return 1
    fi

    first_redirect=$(extract_location "$redirect_headers")

    if [ -z "$first_redirect" ]; then
        printf "\033[1;91m[Redirect failed]\033[0m First Location header was not found.\n" >&2
        rm -f "$redirect_headers" "$redirect_content"
        return 1
    fi

    first_redirect=$(make_abs_url "$first_redirect" "$MAIN_URL")
    printf "\033[1;93m[Step 2]\033[0m First redirect URL: %s\n" "$first_redirect" >&2

    : > "$redirect_headers"
    curl -s -i \
         -H "Accept: */*" \
         -H "User-Agent: $USER_AGENT" \
         -b "$COOKIE_JAR" \
         -c "$COOKIE_JAR" \
         --connect-timeout 10 \
         --max-time 30 \
         "$first_redirect" > "$redirect_headers" 2>/dev/null

    if [ $? -ne 0 ]; then
        printf "\033[1;91m[Redirect failed]\033[0m Could not access the first redirect URL.\n" >&2
        rm -f "$redirect_headers" "$redirect_content"
        return 1
    fi

    second_redirect=$(extract_location "$redirect_headers")

    if [ -z "$second_redirect" ]; then
        printf "\033[1;91m[Redirect failed]\033[0m Second Location header was not found.\n" >&2
        rm -f "$redirect_headers" "$redirect_content"
        return 1
    fi

    second_redirect=$(make_abs_url "$second_redirect" "$first_redirect")
    printf "\033[1;93m[Step 3]\033[0m Second redirect URL: %s\n" "$second_redirect" >&2

    curl -s \
         -H "Accept: */*" \
         -H "User-Agent: $USER_AGENT" \
         -b "$COOKIE_JAR" \
         -c "$COOKIE_JAR" \
         --connect-timeout 10 \
         --max-time 30 \
         "$second_redirect" > "$redirect_content" 2>/dev/null

    if [ $? -ne 0 ]; then
        printf "\033[1;91m[Redirect failed]\033[0m Could not access the external redirect page.\n" >&2
        rm -f "$redirect_headers" "$redirect_content"
        return 1
    fi

    final_url=$(grep -o "http://[^\"']*eportal/index\.jsp?[^\"']*" "$redirect_content" | head -n 1)

    if [ -z "$final_url" ]; then
        final_url=$(grep -o "http://[^\"']*index\.jsp?[^\"']*" "$redirect_content" | head -n 1)
    fi

    if [ -z "$final_url" ]; then
        case "$second_redirect" in
            *success.jsp*)
                printf "\033[1;93m[Special case]\033[0m Detected success.jsp; it may already contain userIndex.\n" >&2
                final_url="$second_redirect"
                ;;
        esac
    fi

    rm -f "$redirect_headers" "$redirect_content"

    if [ -z "$final_url" ]; then
        printf "\033[1;91m[Redirect failed]\033[0m Could not extract the final login URL from the redirect page.\n" >&2
        printf "\033[1;93m[Debug]\033[0m Second redirect URL: %s\n" "$second_redirect" >&2
        return 1
    fi

    final_url=$(make_abs_url "$final_url" "$second_redirect")
    printf "\033[1;93m[Step 4]\033[0m Final login URL: %s\n" "$final_url" >&2
    echo "$final_url"
    return 0
}

get_query_string() {
    final_url="$1"

    printf "\033[1;93m[Parameters]\033[0m Extracting login parameters from the final URL...\n" >&2

    query_string=$(printf '%s\n' "$final_url" | sed 's/^[^?]*?//')

    case "$query_string" in
        *userIndex=*)
            printf "\033[1;93m[Special case]\033[0m URL already contains userIndex; login may already be active.\n" >&2
            user_index=$(printf '%s\n' "$query_string" | grep -o 'userIndex=[^&]*' | sed 's/userIndex=//')
            if [ -n "$user_index" ]; then
                printf "\033[1;92m[Already logged in]\033[0m Detected userIndex: %s\n" "$user_index" >&2
                echo "ALREADY_LOGGED_IN:$user_index"
                return 0
            fi
            ;;
    esac

    if [ -z "$query_string" ] || [ "$query_string" = "$final_url" ]; then
        printf "\033[1;91m[Parameter error]\033[0m Could not extract query parameters from the URL.\n" >&2
        printf "\033[1;93m[Debug]\033[0m Final URL: %s\n" "$final_url" >&2
        return 1
    fi

    printf "\033[1;93m[Parameters]\033[0m Query string extracted successfully.\n" >&2
    echo "$query_string"
    return 0
}

url_encode() {
    string="$1"

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$string" | jq -sRr @uri 2>/dev/null && return
    fi

    if command -v perl >/dev/null 2>&1; then
        printf '%s' "$string" | perl -MURI::Escape -ne 'print uri_escape($_)' 2>/dev/null && return
        printf '%s' "$string" | perl -pe 's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg' 2>/dev/null && return
    fi

    printf '%s' "$string" | sed 's/%/%25/g;s/ /%20/g;s/&/%26/g;s/=/%3D/g;s/+/%2B/g;s/?/%3F/g;s/#/%23/g'
}

autologin() {
    service_code=$(get_service_code)
    retry_count=1

    while [ "$retry_count" -le "$MAX_ATTEMPTS_ALLOWED" ]; do
        final_login_url=$(get_redirect_url)
        if [ $? -ne 0 ]; then
            handle_connection_error "$retry_count"
            retry_count=$((retry_count + 1))
            continue
        fi

        query_string=$(get_query_string "$final_login_url")
        if [ $? -ne 0 ]; then
            handle_connection_error "$retry_count"
            retry_count=$((retry_count + 1))
            continue
        fi

        case "$query_string" in
            ALREADY_LOGGED_IN:*)
                user_index="${query_string#ALREADY_LOGGED_IN:}"
                printf "\033[1;92m[Login successful]\033[0m Already logged in.\n" >&2
                echo "$user_index"
                return 0
                ;;
        esac

        login_url="${MAIN_URL}eportal/InterFace.do?method=login"

        post_data="userId=$(url_encode "$USERID")"
        post_data="${post_data}&password=$(url_encode "$PASSWORD")"
        post_data="${post_data}&service=${service_code}"
        post_data="${post_data}&queryString=$(url_encode "$query_string")"
        post_data="${post_data}&operatorPwd="
        post_data="${post_data}&operatorUserId="
        post_data="${post_data}&validcode="
        post_data="${post_data}&passwordEncrypt=false"

        printf "\033[1;93m[Login request]\033[0m %s\n" "$login_url" >&2

        curl -s -X POST \
             -H "Accept: */*" \
             -H "Content-Type: $CONTENT_TYPE" \
             -H "User-Agent: $USER_AGENT" \
             -b "$COOKIE_JAR" \
             -c "$COOKIE_JAR" \
             --connect-timeout 10 \
             --max-time 30 \
             -d "$post_data" \
             "$login_url" > "$RESPONSE_FILE"

        if [ $? -ne 0 ]; then
            handle_connection_error "$retry_count"
            retry_count=$((retry_count + 1))
            continue
        fi

        login_response=$(cat "$RESPONSE_FILE")

        case "$login_response" in
            *'"result"'*':'*'"success"'*)
                printf "\033[1;92m[Login successful]\033[0m\n" >&2

                user_index=$(printf '%s\n' "$login_response" | grep -o '"userIndex"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"userIndex"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

                if [ -n "$user_index" ]; then
                    echo "$user_index"
                    return 0
                else
                    printf "\033[1;91m[Login failed]\033[0m Could not read userIndex from the response.\n" >&2
                    return 1
                fi
                ;;
            *)
                error_message=$(printf '%s\n' "$login_response" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

                if [ -n "$error_message" ]; then
                    printf "\033[1;91m[Login failed]\033[0m %s\n" "$error_message" >&2
                else
                    printf "\033[1;91m[Login failed]\033[0m Unknown error.\n" >&2
                    printf "\033[1;93m[Response]\033[0m %s\n" "$login_response" >&2
                fi
                return 1
                ;;
        esac
    done

    printf "\033[1;91m[Retry limit reached]\033[0m\n" >&2
    return 1
}

handle_connection_error() {
    retry_count="$1"
    countdown=15

    while [ "$countdown" -ge 0 ]; do
        printf "\r\033[1;91m[Network error]\033[0m Login interface request failed. Check the WLAN connection. Retrying in %d seconds: attempt (%d/%d)" \
               "$countdown" "$retry_count" "$MAX_ATTEMPTS_ALLOWED" >&2
        sleep 1
        countdown=$((countdown - 1))
    done
    printf "\rStarting retry attempt (%d/%d)\n" "$retry_count" "$MAX_ATTEMPTS_ALLOWED" >&2
}

show_user_info() {
    user_index="$1"

    if [ -z "$user_index" ]; then
        printf "\033[1;91m[User info error]\033[0m userIndex is empty.\n"
        return 1
    fi

    printf "\033[1;93m[User info]\033[0m Fetching online user information...\n"

    user_info_url="${MAIN_URL}eportal/InterFace.do?method=getOnlineUserInfo"
    post_data="userIndex=$(url_encode "$user_index")"

    count=0
    while [ "$count" -lt 5 ]; do
        count=$((count + 1))

        curl -s -X POST \
             -H "Accept: */*" \
             -H "Content-Type: $CONTENT_TYPE" \
             -H "User-Agent: $USER_AGENT" \
             -b "$COOKIE_JAR" \
             -c "$COOKIE_JAR" \
             --connect-timeout 10 \
             --max-time 30 \
             -d "$post_data" \
             "$user_info_url" > "$RESPONSE_FILE"

        if [ $? -eq 0 ]; then
            user_info=$(cat "$RESPONSE_FILE")

            case "$user_info" in
                *'"result"'*':'*'"success"'*)
                    printf "\033[1;92m[OK]\033[0m User information fetched successfully.\n"
                    break
                    ;;
                *'"result"'*':'*'"wait"'*)
                    printf "\033[1;93m[Waiting]\033[0m User information is incomplete. Retrying (%d/5)...\n" "$count"
                    ;;
                *'"result"'*':'*'"fail"'*)
                    error_msg=$(printf '%s\n' "$user_info" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                    printf "\033[1;91m[Failed]\033[0m Server error: %s\n" "$error_msg"
                    return 1
                    ;;
                *)
                    printf "\033[1;93m[Retry]\033[0m Unexpected response format. Retrying (%d/5)...\n" "$count"
                    ;;
            esac
        else
            printf "\033[1;91m[Error]\033[0m Network request failed. Retrying (%d/5)...\n" "$count"
        fi

        if [ "$count" -eq 5 ]; then
            printf "\033[1;91m[User info error]\033[0m Failed after 5 attempts.\n"
            return 1
        fi

        sleep 0.2
    done

    if [ -z "$user_info" ]; then
        printf "\033[1;91m[User info error]\033[0m Empty response body.\n"
        return 1
    fi

    user_id=$(printf '%s\n' "$user_info" | grep -o '"userId"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"userId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    service_name=$(printf '%s\n' "$user_info" | grep -o '"service"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"service"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    user_ip=$(printf '%s\n' "$user_info" | grep -o '"userIp"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"userIp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    max_leaving_time=$(printf '%s\n' "$user_info" | grep -o '"maxLeavingTime"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"maxLeavingTime"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    remaining_time="Unlimited"
    if [ -n "$max_leaving_time" ]; then
        remaining_time="$max_leaving_time"
    fi

    printf "\033[1;92m[User information]\033[0m\n"
    printf "Campus account: %s\n" "$user_id"
    printf "Current service: %s\n" "$service_name"
    printf "Internal IP: %s\n" "$user_ip"
    printf "Remaining time: %s\n" "$remaining_time"
}

main() {
    load_config
    normalize_config

    printf "\033[1;92m=== Campus Network Auto Login Script (sh version) ===\033[0m\n"
    printf "\033[1;93mConfiguration:\033[0m\n"
    printf "Main URL: %s\n" "$MAIN_URL"
    printf "User ID: %s\n" "$USERID"
    printf "Service: %s\n" "$SERVICE"
    printf "Ping host: %s\n" "$PING_HOST"
    printf "\n"

    cleanup

    while true; do
        if check_network_connection_status; then
            if should_log_healthy_status; then
                printf "\033[1;92m[No login needed]\033[0m Network connection is working.\n"
            fi
            sleep 2
        else
            LAST_HEALTHY_LOG_TIME=0
            printf "\033[1;93m[Network check]\033[0m Network connection failed. Starting login flow.\n"

            printf "\033[1;93m[Logging in]\033[0m\n"
            user_index=$(autologin)
            login_result=$?

            if [ "$login_result" -eq 0 ] && [ -n "$user_index" ]; then
                sleep 1
                show_user_info "$user_index"
            else
                printf "\033[1;91m[Login flow error]\033[0m An error occurred during login.\n"
                printf "\033[1;93m[Retry pending]\033[0m Trying again in 5 seconds.\n"
                sleep 5
            fi
        fi
    done
}

check_dependencies() {
    missing_deps=""

    if ! command -v curl >/dev/null 2>&1; then
        missing_deps="$missing_deps curl"
    fi

    if ! command -v ping >/dev/null 2>&1; then
        missing_deps="$missing_deps ping"
    fi

    if [ -n "$missing_deps" ]; then
        printf "\033[1;91m[Dependency check failed]\033[0m Missing dependencies:\n"
        for dep in $missing_deps; do
            printf "  - %s\n" "$dep"
        done
        printf "\nPlease install the missing dependencies and run this script again.\n"
        exit 1
    fi
}

script_name=$(basename "$0")
if [ "$script_name" = "scunet_login.sh" ] || \
   [ "$0" = "${0%/*}/scunet_login.sh.sh" ]; then
    check_dependencies

    if ! init_temp_files; then
        printf "\033[1;91m[Startup error]\033[0m Could not create temporary files.\n" >&2
        exit 1
    fi

    main "$@"
fi
