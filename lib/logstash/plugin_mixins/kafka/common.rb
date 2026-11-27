module LogStash module PluginMixins module Kafka
  module Common

    def self.included(base)
      # COMMON CONFIGURATION SUPPORTED BY BOTH PRODUCER/CONSUMER

      # Close idle connections after the number of milliseconds specified by this config.
      base.config :connections_max_idle_ms, :validate => :number, :default => 540_000 # (9m) Kafka default

      # The period of time in milliseconds after which we force a refresh of metadata even if
      # we haven't seen any partition leadership changes to proactively discover any new brokers or partitions
      base.config :metadata_max_age_ms, :validate => :number, :default => 300_000 # (5m) Kafka default

      # The configuration controls the maximum amount of time the client will wait for the response of a request.
      # If the response is not received before the timeout elapses the client will resend the request if necessary
      # or fail the request if retries are exhausted.
      base.config :request_timeout_ms, :validate => :number, :default => 40_000 # Kafka default

      # SASL/OAUTHBEARER client settings (KIP-1139)

      # (optional) The fully-qualified class name of the `JwtRetriever` implementation used to request tokens
      # from the identity provider, for example `org.apache.kafka.common.security.oauthbearer.JwtBearerJwtRetriever`.
      base.config :sasl_oauthbearer_jwt_retriever_class, :validate => :string
      # (optional) The scope to request from the identity provider. Replaces the deprecated `scope` JAAS option.
      base.config :sasl_oauthbearer_scope, :validate => :string
      # The client ID to identify the client to the identity provider. Replaces the deprecated `clientId` JAAS option.
      base.config :sasl_oauthbearer_client_credentials_client_id, :validate => :string
      # The client secret for the `client_credentials` grant. Replaces the deprecated `clientSecret` JAAS option.
      base.config :sasl_oauthbearer_client_credentials_client_secret, :validate => :password
      # Path to a file that contains a pre-generated JWT assertion. The client reads the file again when it changes.
      # When set, all other `sasl_oauthbearer_assertion_*` settings are ignored.
      base.config :sasl_oauthbearer_assertion_file, :validate => :path
      # The algorithm used to sign a locally-generated JWT assertion.
      base.config :sasl_oauthbearer_assertion_algorithm, :validate => ["RS256", "ES256"], :default => "RS256" # Kafka default
      # (optional) The `aud` claim of a locally-generated JWT assertion.
      base.config :sasl_oauthbearer_assertion_claim_aud, :validate => :string
      # The number of seconds in the future for which a locally-generated JWT assertion is valid (`exp` claim).
      base.config :sasl_oauthbearer_assertion_claim_exp_seconds, :validate => :number, :default => 300 # Kafka default
      # The `iss` claim of a locally-generated JWT assertion. Setting it enables locally-generated assertions.
      base.config :sasl_oauthbearer_assertion_claim_iss, :validate => :string
      # Whether a locally-generated JWT assertion includes a unique `jti` claim.
      base.config :sasl_oauthbearer_assertion_claim_jti_include, :validate => :boolean, :default => false # Kafka default
      # The number of seconds in the past from which a locally-generated JWT assertion is valid (`nbf` claim).
      base.config :sasl_oauthbearer_assertion_claim_nbf_seconds, :validate => :number, :default => 60 # Kafka default
      # (optional) The `sub` claim of a locally-generated JWT assertion.
      base.config :sasl_oauthbearer_assertion_claim_sub, :validate => :string
      # Path to a PEM private key file used to sign a locally-generated JWT assertion.
      base.config :sasl_oauthbearer_assertion_private_key_file, :validate => :path
      # (optional) The passphrase to decrypt the private key in `sasl_oauthbearer_assertion_private_key_file`.
      base.config :sasl_oauthbearer_assertion_private_key_passphrase, :validate => :password
      # (optional) Path to a file with static JWT headers and claims for a locally-generated JWT assertion.
      base.config :sasl_oauthbearer_assertion_template_file, :validate => :path
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
      props.put("sasl.jaas.config", sasl_jaas_config.value) unless sasl_jaas_config.nil?
      props.put("sasl.client.callback.handler.class", sasl_client_callback_handler_class) unless sasl_client_callback_handler_class.nil?
      props.put("sasl.oauthbearer.token.endpoint.url", sasl_oauthbearer_token_endpoint_url) unless sasl_oauthbearer_token_endpoint_url.nil?
      props.put("sasl.oauthbearer.scope.claim.name", sasl_oauthbearer_scope_claim_name) unless sasl_oauthbearer_scope_claim_name.nil?
      set_sasl_oauthbearer_config(props) if sasl_mechanism == "OAUTHBEARER"
      props.put("sasl.login.callback.handler.class", sasl_login_callback_handler_class) unless sasl_login_callback_handler_class.nil?
      props.put("sasl.login.connect.timeout.ms", sasl_login_connect_timeout_ms.to_s) unless sasl_login_connect_timeout_ms.nil?
      props.put("sasl.login.read.timeout.ms", sasl_login_read_timeout_ms.to_s) unless sasl_login_read_timeout_ms.nil?
      props.put("sasl.login.retry.backoff.ms", sasl_login_retry_backoff_ms.to_s) unless sasl_login_retry_backoff_ms.nil?
      props.put("sasl.login.retry.backoff.max.ms", sasl_login_retry_backoff_max_ms.to_s) unless sasl_login_retry_backoff_max_ms.nil?
      sasl_iam_jar_paths&.each {|jar_path| require jar_path }
    end

    def set_sasl_oauthbearer_config(props)
      # Kafka's default validator class, DefaultJwtValidator, links to jose4j. kafka-clients does not ship that library,
      # so the login fails with a NoClassDefFoundError. ClientJwtValidator is the client-side validator and does not need it.
      props.put("sasl.oauthbearer.jwt.validator.class", "org.apache.kafka.common.security.oauthbearer.ClientJwtValidator")
      props.put("sasl.oauthbearer.jwt.retriever.class", sasl_oauthbearer_jwt_retriever_class) unless sasl_oauthbearer_jwt_retriever_class.nil?
      props.put("sasl.oauthbearer.scope", sasl_oauthbearer_scope) unless sasl_oauthbearer_scope.nil?
      props.put("sasl.oauthbearer.client.credentials.client.id", sasl_oauthbearer_client_credentials_client_id) unless sasl_oauthbearer_client_credentials_client_id.nil?
      props.put("sasl.oauthbearer.client.credentials.client.secret", sasl_oauthbearer_client_credentials_client_secret.value) unless sasl_oauthbearer_client_credentials_client_secret.nil?
      props.put("sasl.oauthbearer.assertion.file", sasl_oauthbearer_assertion_file) unless sasl_oauthbearer_assertion_file.nil?
      props.put("sasl.oauthbearer.assertion.algorithm", sasl_oauthbearer_assertion_algorithm) unless sasl_oauthbearer_assertion_algorithm.nil?
      props.put("sasl.oauthbearer.assertion.claim.aud", sasl_oauthbearer_assertion_claim_aud) unless sasl_oauthbearer_assertion_claim_aud.nil?
      props.put("sasl.oauthbearer.assertion.claim.exp.seconds", sasl_oauthbearer_assertion_claim_exp_seconds.to_s) unless sasl_oauthbearer_assertion_claim_exp_seconds.nil?
      props.put("sasl.oauthbearer.assertion.claim.iss", sasl_oauthbearer_assertion_claim_iss) unless sasl_oauthbearer_assertion_claim_iss.nil?
      props.put("sasl.oauthbearer.assertion.claim.jti.include", sasl_oauthbearer_assertion_claim_jti_include.to_s) unless sasl_oauthbearer_assertion_claim_jti_include.nil?
      props.put("sasl.oauthbearer.assertion.claim.nbf.seconds", sasl_oauthbearer_assertion_claim_nbf_seconds.to_s) unless sasl_oauthbearer_assertion_claim_nbf_seconds.nil?
      props.put("sasl.oauthbearer.assertion.claim.sub", sasl_oauthbearer_assertion_claim_sub) unless sasl_oauthbearer_assertion_claim_sub.nil?
      props.put("sasl.oauthbearer.assertion.private.key.file", sasl_oauthbearer_assertion_private_key_file) unless sasl_oauthbearer_assertion_private_key_file.nil?
      props.put("sasl.oauthbearer.assertion.private.key.passphrase", sasl_oauthbearer_assertion_private_key_passphrase.value) unless sasl_oauthbearer_assertion_private_key_passphrase.nil?
      props.put("sasl.oauthbearer.assertion.template.file", sasl_oauthbearer_assertion_template_file) unless sasl_oauthbearer_assertion_template_file.nil?
    end

    def reassign_dns_lookup
      if @client_dns_lookup == "default"
        @client_dns_lookup = "use_all_dns_ips"
        deprecation_logger.deprecated("Deprecated value `default` for `client_dns_lookup` option; please update your configuration to use `use_all_dns_ips` instead.")
      end
    end

  end
end end end