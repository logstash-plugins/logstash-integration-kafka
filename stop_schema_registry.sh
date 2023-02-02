#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Stopping SchemaRegistry"
build/confluent_platform/bin/schema-registry-stop
sleep 5