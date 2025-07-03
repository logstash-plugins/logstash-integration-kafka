#!/bin/bash
# Setup Kafka and create test topics

set -ex
# check if KAFKA_VERSION env var is set
if [ -n "${KAFKA_VERSION+1}" ]; then
  echo "KAFKA_VERSION is $KAFKA_VERSION"
else
   KAFKA_VERSION=3.4.1
fi

export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
export CURL_OPTS="--fail --show-error --no-progress-meter --location --retry 3 --retry-delay 5"

rm -rf build
mkdir build

echo "Setup Kafka version $KAFKA_VERSION"
if [ ! -e "kafka_2.13-$KAFKA_VERSION.tgz" ]; then
  echo "Kafka not present locally, downloading"
  curl $CURL_OPTS -o "kafka_2.13-$KAFKA_VERSION.tgz" "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz"
fi
cp kafka_2.13-$KAFKA_VERSION.tgz build/kafka.tgz
mkdir build/kafka && tar xzf build/kafka.tgz -C build/kafka --strip-components 1

echo "Starting ZooKeeper"
build/kafka/bin/zookeeper-server-start.sh -daemon build/kafka/config/zookeeper.properties
sleep 10
echo "Starting Kafka broker"
build/kafka/bin/kafka-server-start.sh -daemon build/kafka/config/server.properties --override advertised.host.name=127.0.0.1 --override log.dirs="${PWD}/build/kafka-logs"
sleep 10

echo "Setup Confluent Platform"
# check if CONFLUENT_VERSION env var is set
if [ -n "${CONFLUENT_VERSION+1}" ]; then
  echo "CONFLUENT_VERSION is $CONFLUENT_VERSION"
else
   CONFLUENT_VERSION=7.4.0
fi
if [ ! -e confluent-community-$CONFLUENT_VERSION.tar.gz ]; then
  echo "Confluent Platform not present locally, downloading"
  CONFLUENT_MINOR=$(echo "$CONFLUENT_VERSION" | sed -n 's/^\([[:digit:]]*\.[[:digit:]]*\)\.[[:digit:]]*$/\1/p')
  echo "CONFLUENT_MINOR is $CONFLUENT_MINOR"
  curl $CURL_OPTS -o confluent-community-$CONFLUENT_VERSION.tar.gz http://packages.confluent.io/archive/$CONFLUENT_MINOR/confluent-community-$CONFLUENT_VERSION.tar.gz
fi
cp confluent-community-$CONFLUENT_VERSION.tar.gz build/confluent_platform.tar.gz
mkdir build/confluent_platform && tar xzf build/confluent_platform.tar.gz -C build/confluent_platform --strip-components 1

echo "Configuring TLS on Schema registry"
rm -Rf tls_repository
mkdir tls_repository
./setup_keystore_and_truststore.sh
# configure schema-registry to handle https on 8083 port
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/http:\/\/0.0.0.0:8081/http:\/\/0.0.0.0:8081, https:\/\/0.0.0.0:8083/g' build/confluent_platform/etc/schema-registry/schema-registry.properties
else
  sed -i 's/http:\/\/0.0.0.0:8081/http:\/\/0.0.0.0:8081, https:\/\/0.0.0.0:8083/g' build/confluent_platform/etc/schema-registry/schema-registry.properties
fi
echo "ssl.keystore.location=`pwd`/tls_repository/schema_reg.jks" >> build/confluent_platform/etc/schema-registry/schema-registry.properties
echo "ssl.keystore.password=changeit" >> build/confluent_platform/etc/schema-registry/schema-registry.properties
echo "ssl.key.password=changeit" >> build/confluent_platform/etc/schema-registry/schema-registry.properties

cp build/confluent_platform/etc/schema-registry/schema-registry.properties build/confluent_platform/etc/schema-registry/authed-schema-registry.properties
echo "authentication.method=BASIC" >> build/confluent_platform/etc/schema-registry/authed-schema-registry.properties
echo "authentication.roles=admin,developer,user,sr-user" >> build/confluent_platform/etc/schema-registry/authed-schema-registry.properties
echo "authentication.realm=SchemaRegistry-Props" >> build/confluent_platform/etc/schema-registry/authed-schema-registry.properties
cp spec/fixtures/jaas.config build/confluent_platform/etc/schema-registry
cp spec/fixtures/pwd build/confluent_platform/etc/schema-registry

echo "Setting up test topics with test data"
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_plain --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_plain_with_headers --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_plain_with_headers_badly --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_snappy --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic_lz4 --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_topic1 --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 2 --replication-factor 1 --topic logstash_integration_topic2 --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_topic3 --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_gzip_topic --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_snappy_topic --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_lz4_topic --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 1 --replication-factor 1 --topic logstash_integration_zstd_topic --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_partitioner_topic --bootstrap-server localhost:9092
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_static_membership_topic --bootstrap-server localhost:9092
curl $CURL_OPTS -o build/apache_logs.txt https://s3.amazonaws.com/data.elasticsearch.org/apache_logs/apache_logs.txt
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_plain --broker-list localhost:9092
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_snappy --broker-list localhost:9092 --compression-codec snappy
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_lz4 --broker-list localhost:9092 --compression-codec lz4

echo "Setup complete, running specs"
