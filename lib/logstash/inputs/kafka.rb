require 'logstash/namespace'
require 'logstash/inputs/base'
require 'stud/interval'
require 'java'
require "json"
require "logstash/json"
require 'logstash-integration-kafka_jars.rb'
require 'logstash/plugin_mixins/kafka/common'
require 'logstash/plugin_mixins/kafka/avro_schema_registry'
require 'logstash/plugin_mixins/deprecation_logger_support'

# This input will read events from a Kafka topic. It uses the 0.10 version of
# the consumer API provided by Kafka to read messages from the broker.
#
# Here's a compatibility matrix that shows the Kafka client versions that are compatible with each combination
# of Logstash and the Kafka input plugin: 
# 
# [options="header"]
# |==========================================================
# |Kafka Client Version |Logstash Version |Plugin Version |Why?
# |0.8       |2.0.0 - 2.x.x   |<3.0.0 |Legacy, 0.8 is still popular 
# |0.9       |2.0.0 - 2.3.x   | 3.x.x |Works with the old Ruby Event API (`event['product']['price'] = 10`)  
# |0.9       |2.4.x - 5.x.x   | 4.x.x |Works with the new getter/setter APIs (`event.set('[product][price]', 10)`)
# |0.10.0.x  |2.4.x - 5.x.x   | 5.x.x |Not compatible with the <= 0.9 broker
# |0.10.1.x  |2.4.x - 5.x.x   | 6.x.x |
# |==========================================================
# 
# NOTE: We recommended that you use matching Kafka client and broker versions. During upgrades, you should
# upgrade brokers before clients because brokers target backwards compatibility. For example, the 0.9 broker
# is compatible with both the 0.8 consumer and 0.9 consumer APIs, but not the other way around.
#
# This input supports connecting to Kafka over:
#
# * SSL (requires plugin version 3.0.0 or later)
# * Kerberos SASL (requires plugin version 5.1.0 or later) 
#
# By default security is disabled but can be turned on as needed.
#
# The Logstash Kafka consumer handles group management and uses the default offset management
# strategy using Kafka topics.
#
# Logstash instances by default form a single logical group to subscribe to Kafka topics
# Each Logstash Kafka consumer can run multiple threads to increase read throughput. Alternatively, 
# you could run multiple Logstash instances with the same `group_id` to spread the load across
# physical machines. Messages in a topic will be distributed to all Logstash instances with
# the same `group_id`.
#
# Ideally you should have as many threads as the number of partitions for a perfect balance --
# more threads than partitions means that some threads will be idle
#
# For more information see http://kafka.apache.org/documentation.html#theconsumer
#
# Kafka consumer configuration: http://kafka.apache.org/documentation.html#consumerconfigs
#
class LogStash::Inputs::Kafka < LogStash::Inputs::Base

  DEFAULT_DESERIALIZER_CLASS = "org.apache.kafka.common.serialization.StringDeserializer"

  include LogStash::PluginMixins::Kafka::Common
  include LogStash::PluginMixins::Kafka::AvroSchemaRegistry
  include LogStash::PluginMixins::DeprecationLoggerSupport

  config_name 'kafka'

  # default :codec, 'plain' or 'json' depending whether schema registry is used
  #
  # @override LogStash::Inputs::Base - removing the `:default => :plain`
  config :codec, :validate => :codec
  # NOTE: isn't necessary due the params['codec'] = ... done in #initialize
  # having the `nil` default explicit makes the behavior more noticeable.

  # The frequency in milliseconds that the consumer offsets are committed to Kafka.
  config :auto_commit_interval_ms, :validate => :number, :default => 5000 # Kafka default
  # What to do when there is no initial offset in Kafka or if an offset is out of range:
  #
  # * earliest: automatically reset the offset to the earliest offset
  # * latest: automatically reset the offset to the latest offset
  # * none: throw exception to the consumer if no previous offset is found for the consumer's group
  # * anything else: throw exception to the consumer.
  config :auto_offset_reset, :validate => :string
  # A list of URLs of Kafka instances to use for establishing the initial connection to the cluster.
  # This list should be in the form of `host1:port1,host2:port2` These urls are just used
  # for the initial connection to discover the full cluster membership (which may change dynamically)
  # so this list need not contain the full set of servers (you may want more than one, though, in
  # case a server is down).
  config :bootstrap_servers, :validate => :string, :default => "localhost:9092"
  # Automatically check the CRC32 of the records consumed. This ensures no on-the-wire or on-disk
  # corruption to the messages occurred. This check adds some overhead, so it may be
  # disabled in cases seeking extreme performance.
  config :check_crcs, :validate => :boolean, :default => true
  # How DNS lookups should be done. If set to `use_all_dns_ips`, when the lookup returns multiple 
  # IP addresses for a hostname, they will all be attempted to connect to before failing the 
  # connection. If the value is `resolve_canonical_bootstrap_servers_only` each entry will be 
  # resolved and expanded into a list of canonical names.
  # Starting from Kafka 3 `default` value for `client.dns.lookup` value has been removed. If explicitly configured it fallbacks to `use_all_dns_ips`.
  config :client_dns_lookup, :validate => ["default", "use_all_dns_ips", "resolve_canonical_bootstrap_servers_only"], :default => "use_all_dns_ips"
  # The id string to pass to the server when making requests. The purpose of this
  # is to be able to track the source of requests beyond just ip/port by allowing
  # a logical application name to be included.
  config :client_id, :validate => :string, :default => "logstash"
  # Ideally you should have as many threads as the number of partitions for a perfect
  # balance — more threads than partitions means that some threads will be idle
  config :consumer_threads, :validate => :number, :default => 1
  # If true, periodically commit to Kafka the offsets of messages already returned by the consumer. 
  # This committed offset will be used when the process fails as the position from
  # which the consumption will begin.
  config :enable_auto_commit, :validate => :boolean, :default => true
  # Whether records from internal topics (such as offsets) should be exposed to the consumer.
  # If set to true the only way to receive records from an internal topic is subscribing to it.
  config :exclude_internal_topics, :validate => :string
  # The maximum amount of data the server should return for a fetch request. This is not an 
  # absolute maximum, if the first message in the first non-empty partition of the fetch is larger 
  # than this value, the message will still be returned to ensure that the consumer can make progress.
  config :fetch_max_bytes, :validate => :number, :default => 52_428_800 # (50MB) Kafka default
  # The maximum amount of time the server will block before answering the fetch request if
  # there isn't sufficient data to immediately satisfy `fetch_min_bytes`. This
  # should be less than or equal to the timeout used in `poll_timeout_ms`
  config :fetch_max_wait_ms, :validate => :number, :default => 500 # Kafka default
  # The minimum amount of data the server should return for a fetch request. If insufficient
  # data is available the request will wait for that much data to accumulate
  # before answering the request.
  config :fetch_min_bytes, :validate => :number
  # The identifier of the group this consumer belongs to. Consumer group is a single logical subscriber
  # that happens to be made up of multiple processors. Messages in a topic will be distributed to all
  # Logstash instances with the same `group_id`
  config :group_id, :validate => :string, :default => "logstash"
  # Set a static group instance id used in static membership feature to avoid rebalancing when a
  # consumer goes offline. If set and `consumer_threads` is greater than 1 then for each
  # consumer crated by each thread an artificial suffix is appended to the user provided `group_instance_id`
  # to avoid clashing.
  config :group_instance_id, :validate => :string
  # The expected time between heartbeats to the consumer coordinator. Heartbeats are used to ensure 
  # that the consumer's session stays active and to facilitate rebalancing when new
  # consumers join or leave the group. The value must be set lower than
  # `session.timeout.ms`, but typically should be set no higher than 1/3 of that value.
  # It can be adjusted even lower to control the expected time for normal rebalances.
  config :heartbeat_interval_ms, :validate => :number, :default => 3000 # Kafka default
  # Controls how to read messages written transactionally. If set to read_committed, consumer.poll()
  # will only return transactional messages which have been committed. If set to read_uncommitted'
  # (the default), consumer.poll() will return all messages, even transactional messages which have
  # been aborted. Non-transactional messages will be returned unconditionally in either mode.
  config :isolation_level, :validate => ["read_uncommitted", "read_committed"], :default => "read_uncommitted" # Kafka default
  # Java Class used to deserialize the record's key
  config :key_deserializer_class, :validate => :string, :default => DEFAULT_DESERIALIZER_CLASS
  # The maximum delay between invocations of poll() when using consumer group management. This places 
  # an upper bound on the amount of time that the consumer can be idle before fetching more records. 
  # If poll() is not called before expiration of this timeout, then the consumer is considered failed and 
  # the group will rebalance in order to reassign the partitions to another member.
  config :max_poll_interval_ms, :validate => :number, :default => 300_000 # (5m) Kafka default
  # The maximum amount of data per-partition the server will return. The maximum total memory used for a
  # request will be <code>#partitions * max.partition.fetch.bytes</code>. This size must be at least
  # as large as the maximum message size the server allows or else it is possible for the producer to
  # send messages larger than the consumer can fetch. If that happens, the consumer can get stuck trying
  # to fetch a large message on a certain partition.
  config :max_partition_fetch_bytes, :validate => :number, :default => 1_048_576 # (1MB) Kafka default
  # The maximum number of records returned in a single call to poll().
  config :max_poll_records, :validate => :number, :default => 500 # Kafka default
  # The name of the partition assignment strategy that the client uses to distribute
  # partition ownership amongst consumer instances, supported options are `range`,
  # `round_robin`, `sticky` and `cooperative_sticky`
  # (for backwards compatibility setting the class name directly is supported).
  config :partition_assignment_strategy, :validate => :string
  # The size of the TCP receive buffer (SO_RCVBUF) to use when reading data.
  # If the value is `-1`, the OS default will be used.
  config :receive_buffer_bytes, :validate => :number, :default => 32_768 # (32KB) Kafka default
  # The base amount of time to wait before attempting to reconnect to a given host.
  # This avoids repeatedly connecting to a host in a tight loop.
  # This backoff applies to all connection attempts by the client to a broker.
  config :reconnect_backoff_ms, :validate => :number, :default => 50 # Kafka default
  # The amount of time to wait before attempting to retry a failed fetch request
  # to a given topic partition. This avoids repeated fetching-and-failing in a tight loop.
  config :retry_backoff_ms, :validate => :number, :default => 100 # Kafka default
  # The size of the TCP send buffer (SO_SNDBUF) to use when sending data.
  # If the value is -1, the OS default will be used.
  config :send_buffer_bytes, :validate => :number, :default => 131_072 # (128KB) Kafka default
  # The timeout after which, if the `poll_timeout_ms` is not invoked, the consumer is marked dead
  # and a rebalance operation is triggered for the group identified by `group_id`
  config :session_timeout_ms, :validate => :number, :default => 10_000 # (10s) Kafka default
  # Java Class used to deserialize the record's value
  config :value_deserializer_class, :validate => :string, :default => DEFAULT_DESERIALIZER_CLASS
  # A list of topics to subscribe to, defaults to ["logstash"].
  config :topics, :validate => :array, :default => ["logstash"]
  # A topic regex pattern to subscribe to. 
  # The topics configuration will be ignored when using this configuration.
  config :topics_pattern, :validate => :string
  # Time kafka consumer will wait to receive new messages from topics
  config :poll_timeout_ms, :validate => :number, :default => 100
  # The rack id string to pass to the server when making requests. This is used 
  # as a selector for a rack, region, or datacenter. Corresponds to the broker.rack parameter
  # in the broker configuration. 
  # Only has an effect in combination with brokers with Kafka 2.4+ with the broker.rack setting. Ignored otherwise. 
  config :client_rack, :validate => :string
  # The truststore type.
  config :ssl_truststore_type, :validate => :string
  # The JKS truststore path to validate the Kafka broker's certificate.
  config :ssl_truststore_location, :validate => :path
  # The truststore password
  config :ssl_truststore_password, :validate => :password
  # The keystore type.
  config :ssl_keystore_type, :validate => :string
  # If client authentication is required, this setting stores the keystore path.
  config :ssl_keystore_location, :validate => :path
  # If client authentication is required, this setting stores the keystore password
  config :ssl_keystore_password, :validate => :password
  # The password of the private key in the key store file.
  config :ssl_key_password, :validate => :password
  # Algorithm to use when verifying host. Set to "" to disable
  config :ssl_endpoint_identification_algorithm, :validate => :string, :default => 'https'
  # Security protocol to use, which can be either of PLAINTEXT,SSL,SASL_PLAINTEXT,SASL_SSL
  config :security_protocol, :validate => ["PLAINTEXT", "SSL", "SASL_PLAINTEXT", "SASL_SSL"], :default => "PLAINTEXT"
  # http://kafka.apache.org/documentation.html#security_sasl[SASL mechanism] used for client connections. 
  # This may be any mechanism for which a security provider is available.
  # GSSAPI is the default mechanism.
  config :sasl_mechanism, :validate => :string, :default => "GSSAPI"
  # The Kerberos principal name that Kafka broker runs as. 
  # This can be defined either in Kafka's JAAS config or in Kafka's config.
  config :sasl_kerberos_service_name, :validate => :string
  # The Java Authentication and Authorization Service (JAAS) API supplies user authentication and authorization 
  # services for Kafka. This setting provides the path to the JAAS file. Sample JAAS file for Kafka client:
  # [source,java]
  # ----------------------------------
  # KafkaClient {
  #   com.sun.security.auth.module.Krb5LoginModule required
  #   useTicketCache=true
  #   renewTicket=true
  #   serviceName="kafka";
  #   };
  # ----------------------------------
  #
  # Please note that specifying `jaas_path` and `kerberos_config` in the config file will add these  
  # to the global JVM system properties. This means if you have multiple Kafka inputs, all of them would be sharing the same 
  # `jaas_path` and `kerberos_config`. If this is not desirable, you would have to run separate instances of Logstash on 
  # different JVM instances.
  config :jaas_path, :validate => :path
  # JAAS configuration settings. This allows JAAS config to be a part of the plugin configuration and allows for different JAAS configuration per each plugin config.
  config :sasl_jaas_config, :validate => :string
  # Optional path to kerberos config file. This is krb5.conf style as detailed in https://web.mit.edu/kerberos/krb5-1.12/doc/admin/conf_files/krb5_conf.html
  config :kerberos_config, :validate => :path
  # Option to add Kafka metadata like topic, message size and header key values to the event.
  # With `basic` this will add a field named `kafka` to the logstash event containing the following attributes:
  #   `topic`: The topic this message is associated with
  #   `consumer_group`: The consumer group used to read in this event
  #   `partition`: The partition this message is associated with
  #   `offset`: The offset from the partition this message is associated with
  #   `key`: A ByteBuffer containing the message key
  #   `timestamp`: The timestamp of this message
  # While with `extended` it adds also all the key values present in the Kafka header if the key is valid UTF-8 else
  # silently skip it.
  #
  # Controls whether a kafka topic is automatically created when subscribing to a non-existent topic.
  # A topic will be auto-created only if this configuration is set to `true` and auto-topic creation is enabled on the broker using `auto.create.topics.enable`; 
  # otherwise auto-topic creation is not permitted.
  config :auto_create_topics, :validate => :boolean, :default => true

  config :decorate_events, :validate => %w(none basic extended false true), :default => "none"

  attr_reader :metadata_mode

  # @overload based on schema registry change the codec default
  def initialize(params = {})
    unless params.key?('codec')
      params['codec'] = params.key?('schema_registry_url') ? 'json' : 'plain'
    end

    super(params)
  end

  public
  def register
    @runner_threads = []
    @metadata_mode = extract_metadata_level(@decorate_events)
    reassign_dns_lookup
    @pattern ||= java.util.regex.Pattern.compile(@topics_pattern) unless @topics_pattern.nil?
    check_schema_registry_parameters
  end

  METADATA_NONE     = Set[].freeze
  METADATA_BASIC    = Set[:record_props].freeze
  METADATA_EXTENDED = Set[:record_props, :headers].freeze
  METADATA_DEPRECATION_MAP = { 'true' => 'basic', 'false' => 'none' }

  private
  def extract_metadata_level(decorate_events_setting)
    metadata_enabled = decorate_events_setting

    if METADATA_DEPRECATION_MAP.include?(metadata_enabled)
      canonical_value = METADATA_DEPRECATION_MAP[metadata_enabled]
      deprecation_logger.deprecated("Deprecated value `#{decorate_events_setting}` for `decorate_events` option; use `#{canonical_value}` instead.")
      metadata_enabled = canonical_value
    end

    case metadata_enabled
    when 'none'     then METADATA_NONE
    when 'basic'    then METADATA_BASIC
    when 'extended' then METADATA_EXTENDED
    end
  end

  public
  def run(logstash_queue)
    @runner_consumers = consumer_threads.times.map do |i|
      thread_group_instance_id = consumer_threads > 1 && group_instance_id ? "#{group_instance_id}-#{i}" : group_instance_id
      subscribe(create_consumer("#{client_id}-#{i}", thread_group_instance_id))
    end
    @runner_threads = @runner_consumers.map.with_index { |consumer, i| thread_runner(logstash_queue, consumer,
                                                                                     "kafka-input-worker-#{client_id}-#{i}") }
    @runner_threads.each(&:start)
    @runner_threads.each(&:join)
  end # def run

  public
  def stop
    # if we have consumers, wake them up to unblock our runner threads
    @runner_consumers && @runner_consumers.each(&:wakeup)
  end

  public
  def kafka_consumers
    @runner_consumers
  end

  def subscribe(consumer)
    @pattern.nil? ? consumer.subscribe(topics) : consumer.subscribe(@pattern)
    consumer
  end

  def thread_runner(logstash_queue, consumer, name)
    java.lang.Thread.new do
      LogStash::Util::set_thread_name(name)
      begin
        codec_instance = @codec.clone
        until stop?
          records = do_poll(consumer)
          unless records.empty?
            records.each { |record| handle_record(record, codec_instance, logstash_queue) }
            maybe_commit_offset(consumer)
          end
        end
      ensure
        consumer.close
      end
    end
  end

  def do_poll(consumer)
    records = []
    begin
      records = consumer.poll(java.time.Duration.ofMillis(poll_timeout_ms))
    rescue org.apache.kafka.common.errors.WakeupException => e
      logger.debug("Wake up from poll", :kafka_error_message => e)
      raise e unless stop?
    rescue org.apache.kafka.common.errors.FencedInstanceIdException => e
      logger.error("Another consumer with same group.instance.id has connected", :original_error_message => e.message)
      raise e unless stop?
    rescue => e
      logger.error("Unable to poll Kafka consumer",
                   :kafka_error_message => e,
                   :cause => e.respond_to?(:getCause) ? e.getCause : nil)
      Stud.stoppable_sleep(1) { stop? }
    end
    records
  end

  def handle_record(record, codec_instance, queue)
    # use + since .to_s on nil/boolean returns a frozen string since ruby 2.7
    codec_instance.decode(+record.value.to_s) do |event|
      decorate(event)
      maybe_set_metadata(event, record)
      queue << event
    end
  end

  def maybe_set_metadata(event, record)
    if @metadata_mode.include?(:record_props)
      event.set("[@metadata][kafka][topic]", record.topic)
      event.set("[@metadata][kafka][consumer_group]", @group_id)
      event.set("[@metadata][kafka][partition]", record.partition)
      event.set("[@metadata][kafka][offset]", record.offset)
      event.set("[@metadata][kafka][key]", record.key)
      event.set("[@metadata][kafka][timestamp]", record.timestamp)
    end
    if @metadata_mode.include?(:headers)
      record.headers
            .select{|h| header_with_value(h) }
            .each do |header|
        s = String.from_java_bytes(header.value)
        s.force_encoding(Encoding::UTF_8)
        if s.valid_encoding?
          event.set("[@metadata][kafka][headers][" + header.key + "]", s)
        end
      end
    end
  end

  def maybe_commit_offset(consumer)
    begin
      consumer.commitSync if @enable_auto_commit.eql?(false)
    rescue org.apache.kafka.common.errors.WakeupException => e
      logger.debug("Wake up from commitSync", :kafka_error_message => e)
      raise e unless stop?
    rescue StandardError => e
      # For transient errors, the commit should be successful after the next set of
      # polled records has been processed.
      # But, it might also be worth thinking about adding a configurable retry mechanism
      logger.error("Unable to commit records",
                   :kafka_error_message => e,
                   :cause => e.respond_to?(:getCause) ? e.getCause() : nil)
    end
  end

  private
  def create_consumer(client_id, group_instance_id)
    begin
      props = java.util.Properties.new
      kafka = org.apache.kafka.clients.consumer.ConsumerConfig

      props.put(kafka::AUTO_COMMIT_INTERVAL_MS_CONFIG, auto_commit_interval_ms.to_s) unless auto_commit_interval_ms.nil?
      props.put(kafka::AUTO_OFFSET_RESET_CONFIG, auto_offset_reset) unless auto_offset_reset.nil?
      props.put(kafka::ALLOW_AUTO_CREATE_TOPICS_CONFIG, auto_create_topics) unless auto_create_topics.nil?
      props.put(kafka::BOOTSTRAP_SERVERS_CONFIG, bootstrap_servers)
      props.put(kafka::CHECK_CRCS_CONFIG, check_crcs.to_s) unless check_crcs.nil?
      props.put(kafka::CLIENT_DNS_LOOKUP_CONFIG, client_dns_lookup)
      props.put(kafka::CLIENT_ID_CONFIG, client_id)
      props.put(kafka::CONNECTIONS_MAX_IDLE_MS_CONFIG, connections_max_idle_ms.to_s) unless connections_max_idle_ms.nil?
      props.put(kafka::ENABLE_AUTO_COMMIT_CONFIG, enable_auto_commit.to_s)
      props.put(kafka::EXCLUDE_INTERNAL_TOPICS_CONFIG, exclude_internal_topics) unless exclude_internal_topics.nil?
      props.put(kafka::FETCH_MAX_BYTES_CONFIG, fetch_max_bytes.to_s) unless fetch_max_bytes.nil?
      props.put(kafka::FETCH_MAX_WAIT_MS_CONFIG, fetch_max_wait_ms.to_s) unless fetch_max_wait_ms.nil?
      props.put(kafka::FETCH_MIN_BYTES_CONFIG, fetch_min_bytes.to_s) unless fetch_min_bytes.nil?
      props.put(kafka::GROUP_ID_CONFIG, group_id)
      props.put(kafka::GROUP_INSTANCE_ID_CONFIG, group_instance_id) unless group_instance_id.nil?
      props.put(kafka::HEARTBEAT_INTERVAL_MS_CONFIG, heartbeat_interval_ms.to_s) unless heartbeat_interval_ms.nil?
      props.put(kafka::ISOLATION_LEVEL_CONFIG, isolation_level)
      props.put(kafka::KEY_DESERIALIZER_CLASS_CONFIG, key_deserializer_class)
      props.put(kafka::MAX_PARTITION_FETCH_BYTES_CONFIG, max_partition_fetch_bytes.to_s) unless max_partition_fetch_bytes.nil?
      props.put(kafka::MAX_POLL_RECORDS_CONFIG, max_poll_records.to_s) unless max_poll_records.nil?
      props.put(kafka::MAX_POLL_INTERVAL_MS_CONFIG, max_poll_interval_ms.to_s) unless max_poll_interval_ms.nil?
      props.put(kafka::METADATA_MAX_AGE_CONFIG, metadata_max_age_ms.to_s) unless metadata_max_age_ms.nil?
      props.put(kafka::PARTITION_ASSIGNMENT_STRATEGY_CONFIG, partition_assignment_strategy_class) unless partition_assignment_strategy.nil?
      props.put(kafka::RECEIVE_BUFFER_CONFIG, receive_buffer_bytes.to_s) unless receive_buffer_bytes.nil?
      props.put(kafka::RECONNECT_BACKOFF_MS_CONFIG, reconnect_backoff_ms.to_s) unless reconnect_backoff_ms.nil?
      props.put(kafka::REQUEST_TIMEOUT_MS_CONFIG, request_timeout_ms.to_s) unless request_timeout_ms.nil?
      props.put(kafka::RETRY_BACKOFF_MS_CONFIG, retry_backoff_ms.to_s) unless retry_backoff_ms.nil?
      props.put(kafka::SEND_BUFFER_CONFIG, send_buffer_bytes.to_s) unless send_buffer_bytes.nil?
      props.put(kafka::SESSION_TIMEOUT_MS_CONFIG, session_timeout_ms.to_s) unless session_timeout_ms.nil?
      props.put(kafka::VALUE_DESERIALIZER_CLASS_CONFIG, value_deserializer_class)
      props.put(kafka::CLIENT_RACK_CONFIG, client_rack) unless client_rack.nil? 

      props.put("security.protocol", security_protocol) unless security_protocol.nil?
      if schema_registry_url
        props.put(kafka::VALUE_DESERIALIZER_CLASS_CONFIG, Java::io.confluent.kafka.serializers.KafkaAvroDeserializer.java_class)
        serdes_config = Java::io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig
        props.put(serdes_config::SCHEMA_REGISTRY_URL_CONFIG, schema_registry_url.uri.to_s)
        if schema_registry_proxy && !schema_registry_proxy.empty?
          props.put(serdes_config::PROXY_HOST, @schema_registry_proxy_host)
          props.put(serdes_config::PROXY_PORT, @schema_registry_proxy_port)
        end
        if schema_registry_key && !schema_registry_key.empty?
          props.put(serdes_config::BASIC_AUTH_CREDENTIALS_SOURCE, 'USER_INFO')
          props.put(serdes_config::USER_INFO_CONFIG, schema_registry_key + ":" + schema_registry_secret.value)
        else
          props.put(serdes_config::BASIC_AUTH_CREDENTIALS_SOURCE, 'URL')
        end
      end
      if security_protocol == "SSL"
        set_trustore_keystore_config(props)
      elsif security_protocol == "SASL_PLAINTEXT"
        set_sasl_config(props)
      elsif security_protocol == "SASL_SSL"
        set_trustore_keystore_config(props)
        set_sasl_config(props)
      end
      if schema_registry_ssl_truststore_location
        props.put('schema.registry.ssl.truststore.location', schema_registry_ssl_truststore_location)
        props.put('schema.registry.ssl.truststore.password', schema_registry_ssl_truststore_password.value)
        props.put('schema.registry.ssl.truststore.type', schema_registry_ssl_truststore_type)
      end

      if schema_registry_ssl_keystore_location
        props.put('schema.registry.ssl.keystore.location', schema_registry_ssl_keystore_location)
        props.put('schema.registry.ssl.keystore.password', schema_registry_ssl_keystore_password.value)
        props.put('schema.registry.ssl.keystore.type', schema_registry_ssl_keystore_type)
      end

      org.apache.kafka.clients.consumer.KafkaConsumer.new(props)
    rescue => e
      logger.error("Unable to create Kafka consumer from given configuration",
                   :kafka_error_message => e,
                   :cause => e.respond_to?(:getCause) ? e.getCause() : nil)
      raise e
    end
  end

  def partition_assignment_strategy_class
    case partition_assignment_strategy
    when 'range'
      'org.apache.kafka.clients.consumer.RangeAssignor'
    when 'round_robin'
      'org.apache.kafka.clients.consumer.RoundRobinAssignor'
    when 'sticky'
      'org.apache.kafka.clients.consumer.StickyAssignor'
    when 'cooperative_sticky'
      'org.apache.kafka.clients.consumer.CooperativeStickyAssignor'
    else
      unless partition_assignment_strategy.index('.')
        raise LogStash::ConfigurationError, "unsupported partition_assignment_strategy: #{partition_assignment_strategy.inspect}"
      end
      partition_assignment_strategy # assume a fully qualified class-name
    end
  end

  def header_with_value(header)
    !header.nil? && !header.value.nil? && !header.key.nil?
  end

end #class LogStash::Inputs::Kafka
