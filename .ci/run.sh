#!/bin/bash
# This is intended to be run inside the docker container as the command of the docker-compose.

env

set -ex

# Define the Kafka:Confluent version pairs
VERSIONS=(
# "3.9.1:7.4.0"
  "4.1.0:8.0.0"
)

for pair in "${VERSIONS[@]}"; do
  KAFKA_VERSION="${pair%%:*}"
  CONFLUENT_VERSION="${pair##*:}"

  echo "=================================================="
  echo " Testing with Kafka $KAFKA_VERSION / Confluent $CONFLUENT_VERSION"
  echo "=================================================="

  export KAFKA_VERSION
  export CONFLUENT_VERSION

  ./kafka_test_setup.sh

  bundle exec rspec -fd
  bundle exec rspec -fd --tag integration

  ./kafka_test_teardown.sh
done