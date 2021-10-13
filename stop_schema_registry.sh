#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Stoppping SchemaRegistry"
build/confluent_platform/bin/schema-registry-stop
sleep 5