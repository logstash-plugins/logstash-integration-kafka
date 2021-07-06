#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Starting SchemaRegistry"
build/confluent_platform/bin/schema-registry-start build/confluent_platform/etc/schema-registry/schema-registry.properties > /dev/null 2>&1 &
