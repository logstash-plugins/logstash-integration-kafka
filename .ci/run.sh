#!/bin/bash
# This is intended to be run inside the docker container as the command of the docker-compose.

env

set -ex

# Define the Kafka:Confluent version pairs
VERSIONS=(
# "3.9.1:7.4.0"
  "4.1.0:8.1.1"
)

bundle exec rspec -fd
bundle exec rspec -fd --tag integration

./kafka_test_teardown.sh
