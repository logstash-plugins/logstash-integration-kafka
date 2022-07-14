#!/bin/bash
# This is intended to be run inside the docker container as the command of the docker-compose.

env

set -ex

export KAFKA_VERSION=2.8.1
./kafka_test_setup.sh

jruby -rbundler/setup -S rspec -fd
jruby -rbundler/setup -S rspec -fd --tag integration

./kafka_test_teardown.sh
