#!/bin/bash
set -e

BOOTSTRAP="my-cluster-kafka-bootstrap:9092"
TOPIC_PREFIX="test-topic"
NUM_RECORDS=100000000
RECORD_SIZE=1024
BATCH_SIZE=256000
ACKS=1
CLIENT_ID="producer-1"
LOG_DIR="/tmp"
RETENTION_MS=10800000
INSYNC_REPLICAS=2
COMPRESSION="uncompressed"
SUMMARY_FILE="${LOG_DIR}/kafka_test_summary.log"

create_topics() {
  local count=$1
  echo "=== Creating $count topics ==="
  for i in $(seq 1 $count); do
    ./kafka-topics.sh --create \
      --bootstrap-server="$BOOTSTRAP" \
      --topic ${TOPIC_PREFIX}-${i} \
      --partitions 36 \
      --replication-factor 3 \
      --config retention.ms=${RETENTION_MS} \
      --config min.insync.replicas=${INSYNC_REPLICAS} \
      --config compression.type="${COMPRESSION}"
  done
}

delete_all_topics() {
  echo "=== Deleting all topics ==="
  for t in $(./kafka-topics.sh --list --bootstrap-server "$BOOTSTRAP"); do
    ./kafka-topics.sh --delete --bootstrap-server "$BOOTSTRAP" --topic "$t" || true
  done
}

run_producers() {
  local count=$1
  echo "=== Running producer tests on $count topics ==="
  for i in $(seq 1 $count); do
    echo "→ Starting producer for ${TOPIC_PREFIX}-${i}"
    ./kafka-producer-perf-test.sh \
      --topic ${TOPIC_PREFIX}-${i} \
      --record-size=${RECORD_SIZE} \
      --throughput=-1 \
      --num-records=${NUM_RECORDS} \
      --producer-props bootstrap.servers=${BOOTSTRAP} acks=${ACKS} batch.size=${BATCH_SIZE} client.id=${CLIENT_ID} \
      > ${LOG_DIR}/${count}t-producer-t${i}.log 2>&1 &
  done

  echo "Waiting for all producer jobs to complete..."
  wait
  echo "All producers completed for $count topics"
}

summarize_round() {
  local count=$1
  local total_tput=0
  local total_mb=0
  local total_lat=0
  local num_files=0

  echo "=== Summarizing round with $count topics ==="

  for log in ${LOG_DIR}/${count}t-producer-t*.log; do
    if [[ -f "$log" ]]; then
      # read the last line only
      local last_line=$(tail -n 1 "$log")
      local tput=$(echo "$last_line" | grep -Eo '[0-9]+\.[0-9]+ records/sec' | awk '{print $1}')
      local mb=$(echo "$last_line" | grep -Eo '\([0-9]+\.[0-9]+ MB/sec\)' | tr -d '()' | awk '{print $1}')
      local lat=$(echo "$last_line" | grep -Eo '[0-9]+\.[0-9]+ ms avg latency' | awk '{print $1}')

      if [[ -n "$tput" && -n "$lat" && -n "$mb" ]]; then
        total_tput=$(awk "BEGIN {print $total_tput + $tput}")
        total_mb=$(awk "BEGIN {print $total_mb + $mb}")
        total_lat=$(awk "BEGIN {print $total_lat + $lat}")
        num_files=$((num_files + 1))
      fi
    fi
  done

  if [[ $num_files -gt 0 ]]; then
    local avg_tput=$(awk "BEGIN {print $total_tput / $num_files}")
    local avg_mb=$(awk "BEGIN {print $total_mb / $num_files}")
    local avg_lat=$(awk "BEGIN {print $total_lat / $num_files}")

    echo "=== ROUND SUMMARY ($count topics) ===" | tee -a "$SUMMARY_FILE"
    echo "Total Throughput : $total_tput records/sec  |  $total_mb MB/sec" | tee -a "$SUMMARY_FILE"
    echo "Avg Throughput   : $avg_tput records/sec   |  $avg_mb MB/sec" | tee -a "$SUMMARY_FILE"
    echo "Avg Latency      : $avg_lat ms" | tee -a "$SUMMARY_FILE"
    echo "=====================================" | tee -a "$SUMMARY_FILE"
  else
    echo "No valid log files found for $count topics."
  fi
}

main() {
  echo "Kafka Producer Test Sequence Started at $(date)" > "$SUMMARY_FILE"
  echo "" >> "$SUMMARY_FILE"

  delete_all_topics || true

  for count in 1 2; do
    create_topics "$count"
    run_producers "$count"
    summarize_round "$count"
    delete_all_topics
    echo "Sleeping 5 minutes before next iteration..."
    sleep 300
  done

  echo "=== All tests completed successfully ==="
  echo "Summary saved at: $SUMMARY_FILE"
}

main "$@"