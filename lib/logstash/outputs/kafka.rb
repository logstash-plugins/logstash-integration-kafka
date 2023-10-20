require 'logstash/namespace'
require 'logstash/outputs/base'
require 'java'
require 'logstash-integration-kafka_jars.rb'
require 'logstash/plugin_mixins/kafka/common'

# Write events to a Kafka topic. This uses the Kafka Producer API to write messages to a topic on
# the broker.
#
# Here's a compatibility matrix that shows the Kafka client versions that are compatible with each combination
# of Logstash and the Kafka output plugin: 
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
# This output supports connecting to Kafka over:
#
# * SSL (requires plugin version 3.0.0 or later)
# * Kerberos SASL (requires plugin version 5.1.0 or later)
#
# By default security is disabled but can be turned on as needed.
#
# The only required configuration is the topic_id. The default codec is plain,
# so events will be persisted on the broker in plain format. Logstash will encode your messages with not 
# only the message but also with a timestamp and hostname. If you do not want anything but your message 
# passing through, you should make the output configuration something like:
# [source,ruby]
#     output {
#       kafka {
#         codec => plain {
#            format => "%{message}"
#         }
#         topic_id => "mytopic"
#       }
#     }
# For more information see http://kafka.apache.org/documentation.html#theproducer
#
# Kafka producer configuration: http://kafka.apache.org/documentation.html#newproducerconfigs
class LogStash::Outputs::Kafka < LogStash::Outputs::Base

  java_import org.apache.kafka.clients.producer.ProducerRecord

  include LogStash::PluginMixins::Kafka::Common

  declare_threadsafe!

  config_name 'kafka'

  default :codec, 'plain'

  # The number of acknowledgments the producer requires the leader to have received
  # before considering a request complete.
  #
  # acks=0,   the producer will not wait for any acknowledgment from the server at all.
  # acks=1,   This will mean the leader will write the record to its local log but
  #           will respond without awaiting full acknowledgement from all followers.
  # acks=all, This means the leader will wait for the full set of in-sync replicas to acknowledge the record.
  config :acks, :validate => ["0", "1", "all"], :default => "1"
  # The producer will attempt to batch records together into fewer requests whenever multiple
  # records are being sent to the same partition. This helps performance on both the client
  # and the server. This configuration controls the default batch size in bytes.
  config :batch_size, :validate => :number, :default => 16_384 # Kafka default
  # This is for bootstrapping and the producer will only use it for getting metadata (topics,
  # partitions and replicas). The socket connections for sending the actual data will be
  # established based on the broker information returned in the metadata. The format is
  # `host1:port1,host2:port2`, and the list can be a subset of brokers or a VIP pointing to a
  # subset of brokers.
  config :bootstrap_servers, :validate => :string, :default => 'localhost:9092'
  # The total bytes of memory the producer can use to buffer records waiting to be sent to the server.
  config :buffer_memory, :validate => :number, :default => 33_554_432 # (32M) Kafka default
  # The compression type for all data generated by the producer.
  # The default is none (i.e. no compression). Valid values are none, gzip, snappy, lz4 or zstd.
  config :compression_type, :validate => ["none", "gzip", "snappy", "lz4", "zstd"], :default => "none"
  # How DNS lookups should be done. If set to `use_all_dns_ips`, when the lookup returns multiple 
  # IP addresses for a hostname, they will all be attempted to connect to before failing the 
  # connection. If the value is `resolve_canonical_bootstrap_servers_only` each entry will be 
  # resolved and expanded into a list of canonical names.
  # Starting from Kafka 3 `default` value for `client.dns.lookup` value has been removed. If explicitly configured it fallbacks to `use_all_dns_ips`.
  config :client_dns_lookup, :validate => ["default", "use_all_dns_ips", "resolve_canonical_bootstrap_servers_only"], :default => "use_all_dns_ips"
  # The id string to pass to the server when making requests.
  # The purpose of this is to be able to track the source of requests beyond just
  # ip/port by allowing a logical application name to be included with the request
  config :client_id, :validate => :string
  # When set to ‘true’, the producer will ensure that exactly one copy of each message is written in the stream.
  # If ‘false’, producer retries due to broker failures, etc., may write duplicates of the retried message in the stream. 
  # Note that enabling idempotence requires max.in.flight.requests.per.connection to be less than or equal to 5 
  # (with message ordering preserved for any allowable value), retries to be greater than 0, and acks must be ‘all’.
  config :enable_idempotence, :validate => :boolean
  # Serializer class for the key of the message
  config :key_serializer, :validate => :string, :default => 'org.apache.kafka.common.serialization.StringSerializer'
  # The producer groups together any records that arrive in between request
  # transmissions into a single batched request. Normally this occurs only under
  # load when records arrive faster than they can be sent out. However in some circumstances
  # the client may want to reduce the number of requests even under moderate load.
  # This setting accomplishes this by adding a small amount of artificial delay—that is,
  # rather than immediately sending out a record the producer will wait for up to the given delay
  # to allow other records to be sent so that the sends can be batched together.
  config :linger_ms, :validate => :number, :default => 0 # Kafka default
  # The maximum number of unacknowledged requests the client will send on a single connection before blocking.
  config :max_in_flight_requests_per_connection, :validate => :number, :default => 5 # Kafka default
  # The maximum size of a request
  config :max_request_size, :validate => :number, :default => 1_048_576 # (1MB) Kafka default
  # The key for the message
  config :message_key, :validate => :string
  # the timeout setting for initial metadata request to fetch topic metadata.
  config :metadata_fetch_timeout_ms, :validate => :number, :default => 60_000
  # Partitioner to use - can be `default`, `uniform_sticky`, `round_robin` or a fully qualified class name of a custom partitioner.
  config :partitioner, :validate => :string
  # The size of the TCP receive buffer to use when reading data
  config :receive_buffer_bytes, :validate => :number, :default => 32_768 # (32KB) Kafka default
  # The amount of time to wait before attempting to reconnect to a given host when a connection fails.
  config :reconnect_backoff_ms, :validate => :number, :default => 50 # Kafka default
  # The default retry behavior is to retry until successful. To prevent data loss,
  # the use of this setting is discouraged.
  #
  # If you choose to set `retries`, a value greater than zero will cause the
  # client to only retry a fixed number of times. This will result in data loss
  # if a transient error outlasts your retry count.
  #
  # A value less than zero is a configuration error.
  config :retries, :validate => :number
  # The amount of time to wait before attempting to retry a failed produce request to a given topic partition.
  config :retry_backoff_ms, :validate => :number, :default => 100 # Kafka default
  # The size of the TCP send buffer to use when sending data.
  config :send_buffer_bytes, :validate => :number, :default => 131_072 # (128KB) Kafka default
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

  # The topic to produce messages to
  config :topic_id, :validate => :string, :required => true
  # Serializer class for the value of the message
  config :value_serializer, :validate => :string, :default => 'org.apache.kafka.common.serialization.StringSerializer'

  public
  def register
    @thread_batch_map = Concurrent::Hash.new

    if !@retries.nil? 
      if @retries < 0
        raise ConfigurationError, "A negative retry count (#{@retries}) is not valid. Must be a value >= 0"
      end

      logger.warn("Kafka output is configured with finite retry. This instructs Logstash to LOSE DATA after a set number of send attempts fails. If you do not want to lose data if Kafka is down, then you must remove the retry setting.", :retries => @retries)
    end

    reassign_dns_lookup

    @producer = create_producer
    if value_serializer == 'org.apache.kafka.common.serialization.StringSerializer'
      @codec.on_event do |event, data|
        write_to_kafka(event, data)
      end
    elsif value_serializer == 'org.apache.kafka.common.serialization.ByteArraySerializer'
      @codec.on_event do |event, data|
        write_to_kafka(event, data.to_java_bytes)
      end
    else
      raise ConfigurationError, "'value_serializer' only supports org.apache.kafka.common.serialization.ByteArraySerializer and org.apache.kafka.common.serialization.StringSerializer" 
    end
  end

  def prepare(record)
    # This output is threadsafe, so we need to keep a batch per thread.
    @thread_batch_map[Thread.current].add(record)
  end

  def multi_receive(events)
    t = Thread.current
    if !@thread_batch_map.include?(t)
      @thread_batch_map[t] = java.util.ArrayList.new(events.size)
    end

    events.each do |event|
      @codec.encode(event)
    end

    batch = @thread_batch_map[t]
    if batch.any?
      retrying_send(batch)
      batch.clear
    end
  end

  def retrying_send(batch)
    remaining = @retries

    while batch.any?
      unless remaining.nil?
        if remaining < 0
          # TODO(sissel): Offer to DLQ? Then again, if it's a transient fault,
          # DLQing would make things worse (you dlq data that would be successful
          # after the fault is repaired)
          logger.info("Exhausted user-configured retry count when sending to Kafka. Dropping these events.",
                      :max_retries => @retries, :drop_count => batch.count)
          break
        end

        remaining -= 1
      end

      failures = []

      futures = batch.collect do |record| 
        begin
          # send() can throw an exception even before the future is created.
          @producer.send(record)
        rescue org.apache.kafka.common.errors.InterruptException,
               org.apache.kafka.common.errors.RetriableException => e
          logger.info("producer send failed, will retry sending", :exception => e.class, :message => e.message)
          failures << record
          nil
        rescue org.apache.kafka.common.KafkaException => e
          # This error is not retriable, drop event
          # TODO: add DLQ support
          logger.warn("producer send failed, dropping record",:exception => e.class, :message => e.message,
                      :record_value => record.value)
          nil
        end
      end

      futures.each_with_index do |future, i|
        # We cannot skip nils using `futures.compact` because then our index `i` will not align with `batch`
        unless future.nil?
          begin
            future.get
          rescue java.util.concurrent.ExecutionException => e
            # TODO(sissel): Add metric to count failures, possibly by exception type.
            if e.get_cause.is_a? org.apache.kafka.common.errors.RetriableException or
               e.get_cause.is_a? org.apache.kafka.common.errors.InterruptException
              logger.info("producer send failed, will retry sending", :exception => e.cause.class,
                          :message => e.cause.message)
              failures << batch[i]
            elsif e.get_cause.is_a? org.apache.kafka.common.KafkaException
              # This error is not retriable, drop event
              # TODO: add DLQ support
              logger.warn("producer send failed, dropping record", :exception => e.cause.class,
                          :message => e.cause.message, :record_value => batch[i].value)
            end
          end
        end
      end

      # No failures? Cool. Let's move on.
      break if failures.empty?

      # Otherwise, retry with any failed transmissions
      if remaining.nil? || remaining >= 0
        delay = @retry_backoff_ms / 1000.0
        logger.info("Sending batch to Kafka failed. Will retry after a delay.", :batch_size => batch.size,
                                                                                :failures => failures.size,
                                                                                :sleep => delay)
        batch = failures
        sleep(delay)
      end
    end
  end

  def close
    @producer.close
  end

  private

  def write_to_kafka(event, serialized_data)
    if @message_key.nil?
      record = ProducerRecord.new(event.sprintf(@topic_id), serialized_data)
    else
      record = ProducerRecord.new(event.sprintf(@topic_id), event.sprintf(@message_key), serialized_data)
    end
    prepare(record)
  rescue LogStash::ShutdownSignal
    logger.debug('producer received shutdown signal')
  rescue => e
    logger.warn('producer threw exception, restarting', :exception => e.class, :message => e.message)
  end

  def create_producer
    begin
      props = java.util.Properties.new
      kafka = org.apache.kafka.clients.producer.ProducerConfig

      props.put(kafka::ACKS_CONFIG, acks)
      props.put(kafka::BATCH_SIZE_CONFIG, batch_size.to_s)
      props.put(kafka::BOOTSTRAP_SERVERS_CONFIG, bootstrap_servers)
      props.put(kafka::BUFFER_MEMORY_CONFIG, buffer_memory.to_s)
      props.put(kafka::COMPRESSION_TYPE_CONFIG, compression_type)
      props.put(kafka::CLIENT_DNS_LOOKUP_CONFIG, client_dns_lookup)
      props.put(kafka::CLIENT_ID_CONFIG, client_id) unless client_id.nil?
      props.put(kafka::ENABLE_IDEMPOTENCE_CONFIG, enable_idempotence.to_s) unless enable_idempotence.nil?
      props.put(kafka::KEY_SERIALIZER_CLASS_CONFIG, key_serializer)
      props.put(kafka::LINGER_MS_CONFIG, linger_ms.to_s)
      props.put(kafka::MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, max_in_flight_requests_per_connection.to_s)
      props.put(kafka::MAX_REQUEST_SIZE_CONFIG, max_request_size.to_s)
      props.put(kafka::METADATA_MAX_AGE_CONFIG, metadata_max_age_ms.to_s) unless metadata_max_age_ms.nil?
      unless partitioner.nil?
        props.put(kafka::PARTITIONER_CLASS_CONFIG, partitioner = partitioner_class)
        logger.debug('producer configured using partitioner', :partitioner_class => partitioner)
      end
      props.put(kafka::RECEIVE_BUFFER_CONFIG, receive_buffer_bytes.to_s) unless receive_buffer_bytes.nil?
      props.put(kafka::RECONNECT_BACKOFF_MS_CONFIG, reconnect_backoff_ms.to_s) unless reconnect_backoff_ms.nil?
      props.put(kafka::REQUEST_TIMEOUT_MS_CONFIG, request_timeout_ms.to_s) unless request_timeout_ms.nil?
      props.put(kafka::RETRIES_CONFIG, retries.to_s) unless retries.nil?
      props.put(kafka::RETRY_BACKOFF_MS_CONFIG, retry_backoff_ms.to_s) 
      props.put(kafka::SEND_BUFFER_CONFIG, send_buffer_bytes.to_s)
      props.put(kafka::VALUE_SERIALIZER_CLASS_CONFIG, value_serializer)

      props.put("security.protocol", security_protocol) unless security_protocol.nil?

      if security_protocol == "SSL"
        set_trustore_keystore_config(props)
      elsif security_protocol == "SASL_PLAINTEXT"
        set_sasl_config(props)
      elsif security_protocol == "SASL_SSL"
        set_trustore_keystore_config(props)
        set_sasl_config(props)
      end

      org.apache.kafka.clients.producer.KafkaProducer.new(props)
    rescue => e
      logger.error("Unable to create Kafka producer from given configuration",
                   :kafka_error_message => e,
                   :cause => e.respond_to?(:getCause) ? e.getCause() : nil)
      raise e
    end
  end

  def partitioner_class
    case partitioner
    when 'round_robin'
      'org.apache.kafka.clients.producer.RoundRobinPartitioner'
    when 'uniform_sticky'
      'org.apache.kafka.clients.producer.UniformStickyPartitioner'
    when 'default'
      'org.apache.kafka.clients.producer.internals.DefaultPartitioner'
    else
      unless partitioner.index('.')
        raise LogStash::ConfigurationError, "unsupported partitioner: #{partitioner.inspect}"
      end
      partitioner # assume a fully qualified class-name
    end
  end

end #class LogStash::Outputs::Kafka
