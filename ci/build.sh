#!/bin/bash
# version: 1
########################################################
#
# AUTOMATICALLY GENERATED! DO NOT EDIT
#
########################################################
set -e

./ci/setup.sh

export KAFKA_VERSION=2.4.1
./kafka_test_setup.sh

export LOGSTASH_SOURCE=1
bundle install
bundle exec rake vendor
