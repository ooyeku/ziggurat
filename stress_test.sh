#!/bin/bash

# Default values - reduced concurrency and added more delay
URL="http://127.0.0.1:8080"
DURATION=30
CONCURRENT=100  # Reduced from 50 to 10
INTERVAL=0.01   # Increased from 0.1 to 0.5 seconds

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            URL="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --concurrent)
            CONCURRENT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Initialize counters
total_requests=0
total_time=0
successful_requests=0
failed_requests=0
min_time=999999
max_time=0

# Initialize associative array for response times
declare -A response_times
response_times["GET_root"]=""
response_times["POST_api_data"]=""

# Function to make a request and measure time
make_request() {
    local method=$1
    local endpoint=$2
    local start_time=$(date +%s.%N)
    
    if [ "$method" == "POST" ]; then
        response=$(curl -s -w "%{http_code} %{time_total}\n" -X POST \
            -H "Content-Type: application/json" \
            "${URL}${endpoint}" -o /dev/null 2>/dev/null || echo "000 0.0")
    else
        response=$(curl -s -w "%{http_code} %{time_total}\n" \
            "${URL}${endpoint}" -o /dev/null 2>/dev/null || echo "000 0.0")
    fi
    
    status_code=$(echo $response | cut -d' ' -f1)
    time_taken=$(echo $response | cut -d' ' -f2)
    
    # Convert time to milliseconds
    time_ms=$(echo "$time_taken * 1000" | bc)
    
    # Update statistics
    if [ "$status_code" == "200" ]; then
        echo "✓ $method $endpoint $status_code ${time_ms}ms"
    else
        echo "✗ $method $endpoint $status_code ${time_ms}ms"
    fi
    
    # Store response time in array with safe keys
    if [ "$endpoint" == "/" ]; then
        response_times["${method}_root"]="${response_times["${method}_root"]} $time_ms"
    elif [ "$endpoint" == "/api/data" ]; then
        response_times["${method}_api_data"]="${response_times["${method}_api_data"]} $time_ms"
    fi
    
    # Add delay to prevent overwhelming the server
    sleep $INTERVAL
}

# Function to calculate statistics
calculate_stats() {
    local endpoint_key=$1
    # Convert space-separated string to array
    local times_str=${response_times["$endpoint_key"]}
    local times=()
    for t in $times_str; do
        times+=($t)
    done
    local count=${#times[@]}
    
    if [ $count -eq 0 ]; then
        return
    fi
    
    # Sort times for percentile calculation
    IFS=$'\n' sorted=($(sort -n <<< "${times[*]}"))
    unset IFS
    
    local sum=0
    local min=${sorted[0]}
    local max=${sorted[-1]}
    
    for t in "${times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    
    local avg=$(echo "scale=2; $sum / $count" | bc)
    local p95_index=$(echo "($count * 95 / 100) - 1" | bc)
    local p95=${sorted[$p95_index]}
    
    echo "  Requests: $count"
    echo "  Min: ${min}ms"
    echo "  Max: ${max}ms"
    echo "  Avg: ${avg}ms"
    echo "  P95: ${p95}ms"
    echo "  RPS: $(echo "scale=2; $count / $DURATION" | bc)"
}

echo "Starting stress test..."
echo "URL: $URL"
echo "Duration: $DURATION seconds"
echo "Concurrent users: $CONCURRENT"
echo "Request interval: ${INTERVAL}s"
echo

# Start time
start_time=$(date +%s)

# Run requests in parallel
for ((i=1; i<=CONCURRENT; i++)); do
    (
        while true; do
            current_time=$(date +%s)
            if [ $((current_time - start_time)) -ge $DURATION ]; then
                break
            fi
            
            make_request "GET" "/"
            sleep $INTERVAL
            make_request "POST" "/api/data"
            sleep $INTERVAL
        done
    ) &
done

# Wait for all background processes to finish
wait

echo
echo "=== Stress Test Results ==="
echo

# Calculate and display statistics for each endpoint
echo "GET /:"
calculate_stats "GET_root"
echo
echo "POST /api/data:"
calculate_stats "POST_api_data" 