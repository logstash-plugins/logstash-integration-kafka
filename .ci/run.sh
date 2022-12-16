#!/bin/bash
# This is intended to be run inside the docker container as the command of the docker-compose.

env

set -ex

export KAFKA_VERSION=3.3.1
./kafka_test_setup.sh

bundle exec rspec -fd
bundle exec rspec -fd --tag integration

./kafka_test_teardown.sh
