#!/bin/bash
# This is intended to be run inside the docker container as the command of the docker-compose.

env

set -ex

# Extract apacheKafkaVersion from gradle.properties
export KAFKA_VERSION=$(grep "^apacheKafkaVersion" gradle.properties | cut -d'=' -f2)
./kafka_test_setup.sh

bundle exec rspec -fd
bundle exec rspec -fd --tag integration

./kafka_test_teardown.sh
