#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
BROKER="my-cluster-kafka-bootstrap:9092"
NUM_PRODUCERS=4
NUM_RECORDS=100000000
RECORD_SIZE=1024
PARTITIONS_PER_TOPIC=36
REPLICATION_FACTOR=3
ACK=all
BATCHSIZE=256000
# ====================

# --- Parse-only mode MUST run BEFORE any numeric arithmetic or seq usage ---
if [ "${1:-}" = "parse" ]; then
  shift
  if [ $# -lt 1 ]; then
    echo "Usage: $0 parse <file-pattern-or-files> (e.g. $0 parse producer-multi-* )"
    exit 1
  fi

  FILES=("$@")
  echo "=== Parsing logs: ${FILES[*]} ==="

  # decide if the files are producer or consumer files by checking filenames
  first="${FILES[0]}"
  if echo "$first" | grep -q "producer"; then
    echo "Detected PRODUCER logs"
    gawk '
      {
        if (match($0,
          /[0-9]+[[:space:]]+records[[:space:]]+sent,[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+records\/sec[[:space:]]+\(([0-9]+\.[0-9]+)[[:space:]]+MB\/sec\),[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+ms[[:space:]]+avg[[:space:]]+latency,[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+ms[[:space:]]+max[[:space:]]+latency,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+50th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+95th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+99th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+99\.9th/,
          a)) {
          sum_rps += a[1]
          sum_mbs += a[2]
          sum_avg += a[3]
          sum_max += a[4]
          sum_p50 += a[5]
          sum_p95 += a[6]
          sum_p99 += a[7]
          sum_p999 += a[8]
          count++
        }
      }
      END {
        if (count==0) { print "❌ No producer metric lines parsed."; exit 1 }
        printf "\n📊 PRODUCER SUMMARY (%d files)\n", count
        printf "  SUM records/sec : %.3f\n", sum_rps
        printf "  SUM MB/sec      : %.3f\n", sum_mbs
        printf "  AVG avg-latency : %.3f ms\n", sum_avg/count
        printf "  AVG max-latency : %.3f ms\n", sum_max/count
        printf "  AVG p50         : %.3f ms\n", sum_p50/count
        printf "  AVG p95         : %.3f ms\n", sum_p95/count
        printf "  AVG p99         : %.3f ms\n", sum_p99/count
        printf "  AVG p99.9       : %.3f ms\n", sum_p999/count
      }
    ' "${FILES[@]}"
    exit 0
  fi

  if echo "$first" | grep -q "consumer"; then
    echo "Detected CONSUMER logs"
    awk -F, '
      {
        # trim whitespace from each field
        for (i=1;i<=NF;i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
        # require at least 10 columns as per expected CSV
        if ($0 ~ /^[0-9]/ && NF >= 10) {
          mb_consumed = ($3 + 0)
          mb_sec = ($4 + 0)
          nmsg = ($5 + 0)
          nmsg_sec = ($6 + 0)
          rebalance = ($7 + 0)
          fetch_time = ($8 + 0)
          fetch_mb_sec = ($9 + 0)
          fetch_nmsg_sec = ($10 + 0)

          sum_mb_consumed += mb_consumed
          sum_mb_sec += mb_sec
          sum_nmsg += nmsg
          sum_nmsg_sec += nmsg_sec
          sum_rebalance += rebalance
          sum_fetch_time += fetch_time
          sum_fetch_mb_sec += fetch_mb_sec
          sum_fetch_nmsg_sec += fetch_nmsg_sec
          count++
        }
      }
      END {
        if (count==0) { print "❌ No consumer CSV lines parsed."; exit 1 }
        printf "\n📊 CONSUMER SUMMARY (%d files)\n", count
        printf "  SUM data.consumed.in.MB   : %.4f\n", sum_mb_consumed
        printf "  SUM MB/sec                : %.4f\n", sum_mb_sec
        printf "  SUM data.consumed.in.nMsg : %.0f\n", sum_nmsg
        printf "  SUM nMsg/sec              : %.4f\n", sum_nmsg_sec
        printf "  AVG rebalance.time.ms     : %.2f ms\n", sum_rebalance/count
        printf "  AVG fetch.time.ms         : %.2f ms\n", sum_fetch_time/count
        printf "  SUM fetch.MB.sec          : %.4f\n", sum_fetch_mb_sec
        printf "  SUM fetch.nMsg.sec        : %.4f\n", sum_fetch_nmsg_sec
      }
    ' "${FILES[@]}"
    exit 0
  fi

  echo "❌ Could not auto-detect producer/consumer from filenames: $first"
  exit 1
fi

# --- Normal test-run mode (no parse) ---
# Now safe to use numeric args, seq, etc.
MODE=${1:-multi}
NUM_TOPICS=${2:-$NUM_PRODUCERS}

function create_topic() {
  local topic=$1; local partitions=$2
  echo "Creating topic: $topic ($partitions partitions)"
  ./kafka-topics.sh --create --if-not-exists \
    --bootstrap-server=$BROKER \
    --topic "$topic" \
    --partitions "$partitions" \
    --replication-factor $REPLICATION_FACTOR \
    --config retention.ms=10800000 \
    --config min.insync.replicas=2 \
    --config compression.type="uncompressed"
}

function delete_topic() {
        for i in `./kafka-topics.sh --list --bootstrap-server my-cluster-kafka-bootstrap:9092`; do ./kafka-topics.sh --delete --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic $i; done
}

function run_producers() {
  local mode=$1; local num_topics=$2
  echo "=== Running PRODUCERS ($mode, $num_topics topic(s)) ==="
  for i in $(seq 0 $((NUM_PRODUCERS - 1))); do
    local topic="test-topic"
    [ "$mode" == "multi" ] && topic="test-topic-$((i % num_topics))"
    nohup ./kafka-producer-perf-test.sh \
      --topic "$topic" \
      --record-size="$RECORD_SIZE" \
      --throughput=-1 \
      --num-records="$NUM_RECORDS" \
      --producer-props bootstrap.servers=$BROKER acks=$ACK batch.size=$BATCHSIZE client.id=producer-$i \
      > producer-$mode-$i.log 2>&1 &
  done
  wait
}

function run_consumers() {
  local mode=$1; local num_topics=$2
  echo "=== Running CONSUMERS ($mode, $num_topics topic(s)) ==="
  for i in $(seq 0 $((NUM_PRODUCERS - 1))); do
    local topic="test-topic"
    [ "$mode" == "multi" ] && topic="test-topic-$((i % num_topics))"
    nohup ./kafka-consumer-perf-test.sh \
      --broker-list $BROKER \
      --topic "$topic" \
      --group client-$i-$mode \
      --messages $NUM_RECORDS \
      > consumer-$mode-$i.log 2>&1 &
  done
  wait
}

function parse_producer_logs_after_run() {
  local mode=$1
  echo "=== Parsing PRODUCER logs ($mode) ==="
  gawk '
    {
      if (match($0,
        /[0-9]+[[:space:]]+records[[:space:]]+sent,[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+records\/sec[[:space:]]+\(([0-9]+\.[0-9]+)[[:space:]]+MB\/sec\),[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+ms[[:space:]]+avg[[:space:]]+latency,[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]+ms[[:space:]]+max[[:space:]]+latency,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+50th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+95th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+99th,[[:space:]]*([0-9]+)[[:space:]]+ms[[:space:]]+99\.9th/,
        a)) {
        sum_rps += a[1]; sum_mbs += a[2]; sum_avg += a[3]; sum_max += a[4]
        sum_p50 += a[5]; sum_p95 += a[6]; sum_p99 += a[7]; sum_p999 += a[8]
        count++
      }
    }
    END {
      if (count==0) { print "❌ No producer lines parsed."; exit }
      printf "\n📊 PRODUCER SUMMARY (%d logs)\n", count
      printf "  SUM records/sec : %.3f\n", sum_rps
      printf "  SUM MB/sec      : %.3f\n", sum_mbs
      printf "  AVG avg-latency : %.3f ms\n", sum_avg/count
      printf "  AVG max-latency : %.3f ms\n", sum_max/count
      printf "  AVG p50         : %.3f ms\n", sum_p50/count
      printf "  AVG p95         : %.3f ms\n", sum_p95/count
      printf "  AVG p99         : %.3f ms\n", sum_p99/count
      printf "  AVG p99.9       : %.3f ms\n", sum_p999/count
    }
  ' producer-"$mode"-*.log
}

function parse_consumer_logs_after_run() {
  local mode=$1
  echo "=== Parsing CONSUMER logs ($mode) ==="
  awk -F, '
    {
      for (i=1;i<=NF;i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
      if (NF >= 10) {
        mb_consumed = ($3 + 0)
        mb_sec = ($4 + 0)
        nmsg = ($5 + 0)
        nmsg_sec = ($6 + 0)
        rebalance = ($7 + 0)
        fetch_time = ($8 + 0)
        fetch_mb_sec = ($9 + 0)
        fetch_nmsg_sec = ($10 + 0)

        sum_mb_consumed += mb_consumed
        sum_mb_sec += mb_sec
        sum_nmsg += nmsg
        sum_nmsg_sec += nmsg_sec
        sum_rebalance += rebalance
        sum_fetch_time += fetch_time
        sum_fetch_mb_sec += fetch_mb_sec
        sum_fetch_nmsg_sec += fetch_nmsg_sec
        count++
      }
    }
    END {
      if (count==0) { print "❌ No consumer CSV lines parsed."; exit }
      printf "\n📊 CONSUMER SUMMARY (%d logs)\n", count
      printf "  SUM data.consumed.in.MB   : %.4f\n", sum_mb_consumed
      printf "  SUM MB/sec                : %.4f\n", sum_mb_sec
      printf "  SUM data.consumed.in.nMsg : %.0f\n", sum_nmsg
      printf "  SUM nMsg/sec              : %.4f\n", sum_nmsg_sec
      printf "  AVG rebalance.time.ms     : %.2f ms\n", sum_rebalance/count
      printf "  AVG fetch.time.ms         : %.2f ms\n", sum_fetch_time/count
      printf "  SUM fetch.MB.sec          : %.4f\n", sum_fetch_mb_sec
      printf "  SUM fetch.nMsg.sec        : %.4f\n", sum_fetch_nmsg_sec
    }
  ' consumer-"$mode"-*.log
}

# Main flow: create topics, run tests, parse
echo "=== Kafka Perf Test ($MODE mode, $NUM_TOPICS topic(s)) ==="

delete_topic
sleep 1
for i in $(seq 1 $NUM_TOPICS); do
  create_topic "test-topic-$i" $PARTITIONS_PER_TOPIC
done

run_producers "$MODE" "$NUM_TOPICS"
#run_consumers "$MODE" "$NUM_TOPICS"

# parse produced logs automatically after run
parse_producer_logs_after_run "$MODE"
#parse_consumer_logs_after_run "$MODE"

echo "✅ Done."