#!/bin/bash
# Setup Kafka and create test topics
set -ex

echo "Starting authed SchemaRegistry"
SCHEMA_REGISTRY_OPTS=-Djava.security.auth.login.config=$PWD/jaas.config build/confluent_platform/bin/schema-registry-start build/confluent_platform/etc/schema-registry/authed-schema-registry.properties > /dev/null 2>&1 &