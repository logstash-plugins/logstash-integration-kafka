#!/bin/bash
# Setup Schema Registry keystore and Kafka's schema registry client's truststore
set -ex

echo "Generating schema registry key store"
keytool -genkey -alias schema_reg -keyalg RSA -keystore tls_repository/schema_reg.jks -keypass changeit -storepass changeit  -validity 365  -keysize 2048 -dname "CN=localhost, OU=John Doe, O=Acme Inc, L=Unknown, ST=Unknown, C=IT"

echo "Exporting schema registry certificate"
keytool -exportcert -rfc -keystore tls_repository/schema_reg.jks -storepass changeit -alias schema_reg -file tls_repository/schema_reg_certificate.pem

echo "Creating client's truststore and importing schema registry's certificate"
keytool -import -trustcacerts -file tls_repository/schema_reg_certificate.pem -keypass changeit -storepass changeit -keystore tls_repository/clienttruststore.jks -noprompt