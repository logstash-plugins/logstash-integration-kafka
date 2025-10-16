#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Unregistering test topics"
build/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic 'logstash_integration_.*'
build/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic 'topic_avro.*' 2>&1

echo "Stopping Kafka broker"
build/kafka/bin/kafka-server-stop.sh

if [ -f "build/kafka/bin/zookeeper-server-stop.sh" ]; then
  echo "Stopping ZooKeeper"
  build/kafka/bin/zookeeper-server-stop.sh
fi

echo "Clean TLS folder"
rm -Rf tls_repository
