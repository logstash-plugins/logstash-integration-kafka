module LogStash module PluginMixins module Kafka
  module Common

    def self.included(base)
      # COMMON CONFIGURATION SUPPORTED BY BOTH PRODUCER/CONSUMER

      # Close idle connections after the number of milliseconds specified by this config.
      base.config :connections_max_idle_ms, :validate => :number, :default => 540_000 # (9m) Kafka default
    end

    def set_trustore_keystore_config(props)
      props.put("ssl.truststore.type", ssl_truststore_type) unless ssl_truststore_type.nil?
      props.put("ssl.truststore.location", ssl_truststore_location) unless ssl_truststore_location.nil?
      props.put("ssl.truststore.password", ssl_truststore_password.value) unless ssl_truststore_password.nil?

      # Client auth stuff
      props.put("ssl.keystore.type", ssl_keystore_type) unless ssl_keystore_type.nil?
      props.put("ssl.key.password", ssl_key_password.value) unless ssl_key_password.nil?
      props.put("ssl.keystore.location", ssl_keystore_location) unless ssl_keystore_location.nil?
      props.put("ssl.keystore.password", ssl_keystore_password.value) unless ssl_keystore_password.nil?
      props.put("ssl.endpoint.identification.algorithm", ssl_endpoint_identification_algorithm) unless ssl_endpoint_identification_algorithm.nil?
    end

    def set_sasl_config(props)
      java.lang.System.setProperty("java.security.auth.login.config", jaas_path) unless jaas_path.nil?
      java.lang.System.setProperty("java.security.krb5.conf", kerberos_config) unless kerberos_config.nil?

      props.put("sasl.mechanism", sasl_mechanism)
      if sasl_mechanism == "GSSAPI" && sasl_kerberos_service_name.nil?
        raise LogStash::ConfigurationError, "sasl_kerberos_service_name must be specified when SASL mechanism is GSSAPI"
      end

      props.put("sasl.kerberos.service.name", sasl_kerberos_service_name) unless sasl_kerberos_service_name.nil?
      props.put("sasl.jaas.config", sasl_jaas_config) unless sasl_jaas_config.nil?
    end

  end
end end end