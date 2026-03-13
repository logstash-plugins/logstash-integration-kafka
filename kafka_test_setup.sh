#!/bin/bash
# Setup Kafka and create test topics

set -ex
# check if KAFKA_VERSION env var is set
if [ -n "${KAFKA_VERSION+1}" ]; then
  echo "KAFKA_VERSION is $KAFKA_VERSION"
else
   KAFKA_VERSION=4.2.0
fi

KAFKA_MAJOR_VERSION="${KAFKA_VERSION%%.*}"

export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"

rm -rf build
mkdir build

echo "Setup Kafka version $KAFKA_VERSION"
if [ ! -e "kafka_2.13-$KAFKA_VERSION.tgz" ]; then
  echo "Kafka not present locally, downloading"
  curl -s -o "kafka_2.13-$KAFKA_VERSION.tgz" "https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz"
fi
cp "kafka_2.13-$KAFKA_VERSION.tgz" "build/kafka.tgz"
mkdir "build/kafka" && tar xzf "build/kafka.tgz" -C "build/kafka" --strip-components 1

if [ -f "build/kafka/bin/zookeeper-server-start.sh" ]; then
  echo "Starting ZooKeeper"
  build/kafka/bin/zookeeper-server-start.sh -daemon "build/kafka/config/zookeeper.properties"
  sleep 10
else
  echo "Use KRaft for Kafka version $KAFKA_VERSION"

  echo "log.dirs=${PWD}/build/kafka-logs" >> build/kafka/config/server.properties

  build/kafka/bin/kafka-storage.sh format \
    --cluster-id $(build/kafka/bin/kafka-storage.sh random-uuid) \
    --config build/kafka/config/server.properties \
    --ignore-formatted \
    --standalone
fi

echo "Configuring SASL_PLAINTEXT listener on port 9094"
# Add SASL configuration to server.properties (using inline sasl.jaas.config)
cat >> build/kafka/config/server.properties << EOF

# SASL Configuration
listeners=PLAINTEXT://:9092,CONTROLLER://:9093,SASL_PLAINTEXT://:9094
advertised.listeners=PLAINTEXT://localhost:9092,SASL_PLAINTEXT://localhost:9094
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT

# Enable multiple SASL mechanisms
sasl.enabled.mechanisms=PLAIN,SCRAM-SHA-256,SCRAM-SHA-512
sasl.mechanism.inter.broker.protocol=PLAIN

# JAAS config for PLAIN mechanism
listener.name.sasl_plaintext.plain.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
    username="admin" \\
    password="admin-secret" \\
    user_admin="admin-secret" \\
    user_logstash="logstash-secret";

# JAAS config for SCRAM mechanisms (will be configured via kafka-configs)
listener.name.sasl_plaintext.scram-sha-256.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \\
    username="admin" \\
    password="admin-secret";

listener.name.sasl_plaintext.scram-sha-512.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \\
    username="admin" \\
    password="admin-secret";
EOF

echo "Starting Kafka broker"
build/kafka/bin/kafka-server-start.sh -daemon "build/kafka/config/server.properties" --override advertised.host.name=127.0.0.1 --override log.dirs="${PWD}/build/kafka-logs"
sleep 10

echo "Creating SCRAM credentials for logstash user"
build/kafka/bin/kafka-configs.sh --bootstrap-server localhost:9092 --alter --add-config 'SCRAM-SHA-256=[iterations=8192,password=logstash-secret]' --entity-type users --entity-name logstash
build/kafka/bin/kafka-configs.sh --bootstrap-server localhost:9092 --alter --add-config 'SCRAM-SHA-512=[iterations=8192,password=logstash-secret]' --entity-type users --entity-name logstash

echo "Setup Confluent Platform"
# check if CONFLUENT_VERSION env var is set
if [ -n "${CONFLUENT_VERSION+1}" ]; then
  echo "CONFLUENT_VERSION is $CONFLUENT_VERSION"
else
   CONFLUENT_VERSION=8.0.0
fi
if [ ! -e "confluent-community-$CONFLUENT_VERSION.tar.gz" ]; then
  echo "Confluent Platform not present locally, downloading"
  CONFLUENT_MINOR=$(echo "$CONFLUENT_VERSION" | sed -n 's/^\([[:digit:]]*\.[[:digit:]]*\)\.[[:digit:]]*$/\1/p')
  echo "CONFLUENT_MINOR is $CONFLUENT_MINOR"
  curl -s -o "confluent-community-$CONFLUENT_VERSION.tar.gz" "http://packages.confluent.io/archive/$CONFLUENT_MINOR/confluent-community-$CONFLUENT_VERSION.tar.gz"
fi
cp "confluent-community-$CONFLUENT_VERSION.tar.gz" "build/confluent_platform.tar.gz"
mkdir "build/confluent_platform" && tar xzf "build/confluent_platform.tar.gz" -C "build/confluent_platform" --strip-components 1

echo "Configuring TLS on Schema registry"
rm -Rf tls_repository
mkdir tls_repository
./setup_keystore_and_truststore.sh
# configure schema-registry to handle https on 8083 port
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/http:\/\/0.0.0.0:8081/http:\/\/0.0.0.0:8081, https:\/\/0.0.0.0:8083/g' "build/confluent_platform/etc/schema-registry/schema-registry.properties"
else
  sed -i 's/http:\/\/0.0.0.0:8081/http:\/\/0.0.0.0:8081, https:\/\/0.0.0.0:8083/g' "build/confluent_platform/etc/schema-registry/schema-registry.properties"
fi
echo "ssl.keystore.location=`pwd`/tls_repository/schema_reg.jks" >> "build/confluent_platform/etc/schema-registry/schema-registry.properties"
echo "ssl.keystore.password=changeit" >> "build/confluent_platform/etc/schema-registry/schema-registry.properties"
echo "ssl.key.password=changeit" >> "build/confluent_platform/etc/schema-registry/schema-registry.properties"

cp "build/confluent_platform/etc/schema-registry/schema-registry.properties" "build/confluent_platform/etc/schema-registry/authed-schema-registry.properties"
echo "authentication.method=BASIC" >> "build/confluent_platform/etc/schema-registry/authed-schema-registry.properties"
echo "authentication.roles=admin,developer,user,sr-user" >> "build/confluent_platform/etc/schema-registry/authed-schema-registry.properties"
echo "authentication.realm=SchemaRegistry-Props" >> "build/confluent_platform/etc/schema-registry/authed-schema-registry.properties"
cp spec/fixtures/jaas.config "build/confluent_platform/etc/schema-registry"
if [[ "$KAFKA_MAJOR_VERSION" -eq 3 ]]; then
  cp "spec/fixtures/jaas$KAFKA_MAJOR_VERSION.config" "build/confluent_platform/etc/schema-registry/jaas.config"
fi

cp spec/fixtures/pwd "build/confluent_platform/etc/schema-registry"

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
build/kafka/bin/kafka-topics.sh --create --partitions 3 --replication-factor 1 --topic logstash_integration_sasl_topic --bootstrap-server localhost:9092
curl -s -o build/apache_logs.txt https://s3.amazonaws.com/data.elasticsearch.org/apache_logs/apache_logs.txt
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_plain --bootstrap-server localhost:9092
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_snappy --bootstrap-server localhost:9092 --compression-codec snappy
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_topic_lz4 --bootstrap-server localhost:9092 --compression-codec lz4
cat build/apache_logs.txt | build/kafka/bin/kafka-console-producer.sh --topic logstash_integration_sasl_topic --bootstrap-server localhost:9092

echo "Setup complete, running specs"
