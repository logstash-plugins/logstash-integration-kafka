#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Unregistering test topics"
build/kafka/bin/kafka-topics.sh --zookeeper localhost:2181 --delete --topic 'logstash_integration_.*'
build/kafka/bin/kafka-topics.sh --zookeeper localhost:2181 --delete --topic 'topic_avro.*'

echo "Stopping Kafka broker"
build/kafka/bin/kafka-server-stop.sh
echo "Stopping zookeeper"
build/kafka/bin/zookeeper-server-stop.sh
