#!/bin/bash
# Setup Kafka and create test topics

set -ex
if [ -n "${KAFKA_VERSION+1}" ]; then
  echo "KAFKA_VERSION is $KAFKA_VERSION"
else
   KAFKA_VERSION=2.1.1
fi

export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"

rm -rf build
mkdir build

echo "Downloading Kafka version $KAFKA_VERSION"
curl -s -o build/kafka.tgz "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_2.11-$KAFKA_VERSION.tgz"
mkdir build/kafka && tar xzf build/kafka.tgz -C build/kafka --strip-components 1

echo "Starting ZooKeeper"
build/kafka/bin/zookeeper-server-start.sh -daemon build/kafka/config/zookeeper.properties
sleep 10
echo "Starting Kafka broker"
build/kafka/bin/kafka-server-start.sh -daemon build/kafka/config/server.properties --override advertised.host.name=127.0.0.1 --override log.dirs="${PWD}/build/kafka-logs"
sleep 10

echo "Downloading Confluent Platform"
curl -s -o build/confluent_platform.tar.gz http://packages.confluent.io/archive/5.5/confluent-community-5.5.1-2.12.tar.gz
mkdir build/confluent_platform && tar xzf build/confluent_platform.tar.gz -C build/confluent_platform --strip-components 1

echo "Setting up test topics with test data"
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_plain --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_snappy --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_lz4 --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_topic1 --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 2 --replication-factor 1 --topic logstash_integration_topic2 --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic3 --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_gzip_topic --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_snappy_topic --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_lz4_topic --zookeeper localhost:2181
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_partitioner_topic --zookeeper localhost:2181
curl -s -o build/apache_logs.txt https://s3.amazonaws.com/data.elasticsearch.org/apache_logs/apache_logs.txt
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_plain --broker-list localhost:9092
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_snappy --broker-list localhost:9092 --compression-codec snappy
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_lz4 --broker-list localhost:9092 --compression-codec lz4

echo "Starting SchemaRegistry"
build/confluent_platform/bin/schema-registry-start build/confluent_platform/etc/schema-registry/schema-registry.properties > /dev/null 2>&1 &
sleep 10

echo "Setup complete, running specs"
