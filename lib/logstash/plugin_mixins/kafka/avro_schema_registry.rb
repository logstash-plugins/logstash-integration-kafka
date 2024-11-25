require 'manticore'

module LogStash module PluginMixins module Kafka
  module AvroSchemaRegistry

    def self.included(base)
      base.extend(self)
      base.setup_schema_registry_config
    end

    def setup_schema_registry_config
      # Option to set key to access Schema Registry.
      config :schema_registry_key, :validate => :string

      # Option to set secret to access Schema Registry.
      config :schema_registry_secret, :validate => :password

      # Option to set the endpoint of the Schema Registry.
      # This option permit the usage of Avro Kafka deserializer which retrieve the schema of the Avro message from an
      # instance of schema registry. If this option has value `value_deserializer_class` nor `topics_pattern` could be valued
      config :schema_registry_url, :validate => :uri

      # Option to set the proxy of the Schema Registry.
      # This option permits to define a proxy to be used to reach the schema registry service instance.
      config :schema_registry_proxy, :validate => :string

      # If schema registry client authentication is required, this setting stores the keystore path.
      config :schema_registry_ssl_keystore_location, :validate => :string

      # The keystore password.
      config :schema_registry_ssl_keystore_password, :validate => :password

      # The keystore type
      config :schema_registry_ssl_keystore_type, :validate => ['jks', 'PKCS12'], :default => "jks"

      # The JKS truststore path to validate the Schema Registry's certificate.
      config :schema_registry_ssl_truststore_location, :validate => :string

      # The truststore password.
      config :schema_registry_ssl_truststore_password, :validate => :password

      # The truststore type
      config :schema_registry_ssl_truststore_type, :validate => ['jks', 'PKCS12'], :default => "jks"

      # Option to skip validating the schema registry during registration. This can be useful when using
      # certificate based auth
      config :schema_registry_validation, :validate => ['auto', 'skip'], :default => 'auto'
    end

    def check_schema_registry_parameters
      if @schema_registry_url
        check_for_schema_registry_conflicts
        @schema_registry_proxy_host, @schema_registry_proxy_port  = split_proxy_into_host_and_port(schema_registry_proxy)
        check_for_key_and_secret
        check_for_schema_registry_connectivity_and_subjects if schema_registry_validation?
      end
    end

    def schema_registry_validation?
      return false if schema_registry_validation.to_s == 'skip'
      return false if using_kerberos? # pre-validation doesn't support kerberos

      true
    end

    def using_kerberos?
      security_protocol == "SASL_PLAINTEXT" || security_protocol == "SASL_SSL"
    end

    private
    def check_for_schema_registry_conflicts
      if @value_deserializer_class != LogStash::Inputs::Kafka::DEFAULT_DESERIALIZER_CLASS
        raise LogStash::ConfigurationError, 'Option schema_registry_url prohibit the customization of value_deserializer_class'
      end
      if @topics_pattern && !@topics_pattern.empty?
       raise LogStash::ConfigurationError, 'Option schema_registry_url prohibit the customization of topics_pattern'
      end
    end

    private
    def check_for_schema_registry_connectivity_and_subjects
      options = {}
      if @schema_registry_proxy_host
        options[:proxy] = { host: @schema_registry_proxy_host, port: @schema_registry_proxy_port }
      end
      if schema_registry_key and !schema_registry_key.empty?
        options[:auth] = {:user => schema_registry_key, :password => schema_registry_secret.value}
      end
      if schema_registry_ssl_truststore_location and !schema_registry_ssl_truststore_location.empty?
        options[:ssl] = {} unless options.key?(:ssl)
        options[:ssl][:truststore] = schema_registry_ssl_truststore_location unless schema_registry_ssl_truststore_location.nil?
        options[:ssl][:truststore_password] = schema_registry_ssl_truststore_password.value unless schema_registry_ssl_truststore_password.nil?
        options[:ssl][:truststore_type] = schema_registry_ssl_truststore_type unless schema_registry_ssl_truststore_type.nil?
      end
      if schema_registry_ssl_keystore_location and !schema_registry_ssl_keystore_location.empty?
        options[:ssl] = {} unless options.key? :ssl
        options[:ssl][:keystore] = schema_registry_ssl_keystore_location unless schema_registry_ssl_keystore_location.nil?
        options[:ssl][:keystore_password] = schema_registry_ssl_keystore_password.value unless schema_registry_ssl_keystore_password.nil?
        options[:ssl][:keystore_type] = schema_registry_ssl_keystore_type unless schema_registry_ssl_keystore_type.nil?
      end

      registered_subjects = retrieve_subjects(options)
      expected_subjects = @topics.map { |t| "#{t}-value"}
      if (expected_subjects & registered_subjects).size != expected_subjects.size
        undefined_topic_subjects = expected_subjects - registered_subjects
        raise LogStash::ConfigurationError, "The schema registry does not contain definitions for required topic subjects: #{undefined_topic_subjects}"
      end
    end

    def retrieve_subjects(options)
      client = Manticore::Client.new(options)
      response = client.get(@schema_registry_url.uri.to_s + '/subjects').body
      JSON.parse response
    rescue Manticore::ManticoreException => e
      raise LogStash::ConfigurationError.new("Schema registry service doesn't respond, error: #{e.message}")
    end

    def split_proxy_into_host_and_port(proxy_uri)
      return nil unless proxy_uri && !proxy_uri.empty?

      proxy_uri = LogStash::Util::SafeURI.new(proxy_uri)

      port = proxy_uri.port
      host = proxy_uri.host

      [host, port]
    end

    def check_for_key_and_secret
      if schema_registry_key and !schema_registry_key.empty?
        if !schema_registry_secret or schema_registry_secret.value.empty?
          raise LogStash::ConfigurationError, "Setting `schema_registry_secret` is required when `schema_registry_key` is provided."
        end
      end
    end

  end
end end end
