# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require 'logstash/outputs/kafka'
require 'json'

describe "outputs/kafka" do
  let (:simple_kafka_config) {{'topic_id' => 'test'}}
  let (:event) { LogStash::Event.new({'message' => 'hello', 'topic_name' => 'my_topic', 'host' => '172.0.0.1',
                                      '@timestamp' => LogStash::Timestamp.now}) }

  let(:future) { double('kafka producer future') }
  subject { LogStash::Outputs::Kafka.new(config) }

  context 'when initializing' do
    it "should register" do
      output = LogStash::Plugin.lookup("output", "kafka").new(simple_kafka_config)
      expect {output.register}.to_not raise_error
    end

    it 'should populate kafka config with default values' do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
      expect(kafka.bootstrap_servers).to eql 'localhost:9092'
      expect(kafka.topic_id).to eql 'test'
      expect(kafka.key_serializer).to eql 'org.apache.kafka.common.serialization.StringSerializer'
    end

    it 'should fallback `client_dns_lookup` to `use_all_dns_ips` when the deprecated `default` is specified' do
      simple_kafka_config["client_dns_lookup"] = 'default'
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
      kafka.register

      expect(kafka.client_dns_lookup).to eq('use_all_dns_ips')
    end
  end

  context 'when outputting messages' do
    it 'should send logstash event to kafka broker' do
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).
          with(an_instance_of(org.apache.kafka.clients.producer.ProducerRecord))
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
      kafka.register
      kafka.multi_receive([event])
    end

    it 'should support Event#sprintf placeholders in topic_id' do
      topic_field = 'topic_name'
      expect(org.apache.kafka.clients.producer.ProducerRecord).to receive(:new).
          with("my_topic", event.to_s).and_call_original
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send)
      kafka = LogStash::Outputs::Kafka.new({'topic_id' => "%{#{topic_field}}"})
      kafka.register
      kafka.multi_receive([event])
    end

    it 'should support field referenced message_keys' do
      expect(org.apache.kafka.clients.producer.ProducerRecord).to receive(:new).
          with("test", "172.0.0.1", event.to_s).and_call_original
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send)
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge({"message_key" => "%{host}"}))
      kafka.register
      kafka.multi_receive([event])
    end

    it 'should support field referenced message_headers' do
      expect(org.apache.kafka.clients.producer.ProducerRecord).to receive(:new).
          with("test", event.to_s).and_call_original
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send)
      expect_any_instance_of(org.apache.kafka.common.header.internals.RecordHeaders).to receive(:add).with("host","172.0.0.1".to_java_bytes).and_call_original
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge({"message_headers" => { "host" => "%{host}"}}))
      kafka.register
      kafka.multi_receive([event])
    end

    it 'should not raise config error when truststore location is not set and ssl is enabled' do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("security_protocol" => "SSL"))
      expect(org.apache.kafka.clients.producer.KafkaProducer).to receive(:new)
      expect { kafka.register }.to_not raise_error
    end
  end

  context 'when using message_headers_field' do
    let(:headers_field) { "[@metadata][kafka][headers]" }
    let(:config_with_headers_field) { simple_kafka_config.merge({"message_headers_field" => headers_field}) }
    let(:sent_record) { @sent_record }

    def register_and_receive(kafka, event)
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send) do |_, record|
        @sent_record = record
        nil
      end
      kafka.register
      kafka.multi_receive([event])
    end

    def record_headers(record)
      record.headers.toArray.map { |h| [h.key, String.from_java_bytes(h.value).force_encoding(Encoding::UTF_8)] }
    end

    it 'should add a header for each entry of the referenced hash' do
      event.set(headers_field, { "breadcrumbId" => "breadcrumb-456", "updateMode" => "FULL", "retryCount" => 3,
                                 "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" })
      register_and_receive(LogStash::Outputs::Kafka.new(config_with_headers_field), event)
      expect(record_headers(sent_record)).to contain_exactly(
        ["breadcrumbId", "breadcrumb-456"], ["updateMode", "FULL"], ["retryCount", "3"],
        ["traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"])
    end

    it 'should leave the message value and key unchanged' do
      event.set(headers_field, { "breadcrumbId" => "breadcrumb-456" })
      kafka = LogStash::Outputs::Kafka.new(config_with_headers_field.merge({"message_key" => "%{host}"}))
      register_and_receive(kafka, event)
      expect(sent_record.key).to eq("172.0.0.1")
      expect(sent_record.value).to eq(event.to_s)
    end

    it 'should send the event without headers when the referenced field is absent' do
      register_and_receive(LogStash::Outputs::Kafka.new(config_with_headers_field), event)
      expect(record_headers(sent_record)).to eq([])
    end

    it 'should warn and add no headers when the referenced field is not a hash' do
      event.set(headers_field, "not-a-hash")
      kafka = LogStash::Outputs::Kafka.new(config_with_headers_field)
      allow(kafka.logger).to receive(:warn)
      register_and_receive(kafka, event)
      expect(record_headers(sent_record)).to eq([])
      expect(kafka.logger).to have_received(:warn).with(/does not contain a hash/, anything)
    end

    it 'should skip entries with an empty key or a nil value' do
      event.set(headers_field, { "breadcrumbId" => "breadcrumb-456", "" => "no-name", "empty" => nil })
      register_and_receive(LogStash::Outputs::Kafka.new(config_with_headers_field), event)
      expect(record_headers(sent_record)).to contain_exactly(["breadcrumbId", "breadcrumb-456"])
    end

    it 'should skip non-scalar values with a warning' do
      event.set(headers_field, { "breadcrumbId" => "breadcrumb-456", "nested" => { "a" => "b" }, "list" => ["a", "b"] })
      kafka = LogStash::Outputs::Kafka.new(config_with_headers_field)
      allow(kafka.logger).to receive(:warn)
      register_and_receive(kafka, event)
      expect(record_headers(sent_record)).to contain_exactly(["breadcrumbId", "breadcrumb-456"])
      expect(kafka.logger).to have_received(:warn).with(/non-scalar header value/, anything)
    end

    it 'should append dynamic headers after static message_headers, keeping duplicate names' do
      event.set(headers_field, { "host" => "dynamic-value" })
      kafka = LogStash::Outputs::Kafka.new(config_with_headers_field.merge({"message_headers" => { "host" => "%{host}" }}))
      register_and_receive(kafka, event)
      expect(record_headers(sent_record)).to eq([["host", "172.0.0.1"], ["host", "dynamic-value"]])
    end

    it 'should raise a configuration error on an invalid field reference' do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge({"message_headers_field" => "[@metadata][kafka]headers]"}))
      expect { kafka.register }.to raise_error(LogStash::ConfigurationError, /message_headers_field/)
    end

    it 'should raise a configuration error on an empty field reference' do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge({"message_headers_field" => " "}))
      expect { kafka.register }.to raise_error(LogStash::ConfigurationError, /message_headers_field/)
    end
  end

  context "when KafkaProducer#send() raises a retriable exception" do
    let(:failcount) { (rand * 10).to_i }
    let(:sendcount) { failcount + 1 }

    let(:exception_classes) { [
      org.apache.kafka.common.errors.TimeoutException,
      org.apache.kafka.common.errors.DisconnectException,
      org.apache.kafka.common.errors.CoordinatorNotAvailableException,
      org.apache.kafka.common.errors.InterruptException,
    ] }

    before do
      count = 0
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send)
        .exactly(sendcount).times do
        if count < failcount # fail 'failcount' times in a row.
          count += 1
          # Pick an exception at random
          raise exception_classes.shuffle.first.new("injected exception for testing")
        else
          count = :done
          future # return future
        end
      end
      expect(future).to receive :get
    end

    it "should retry until successful" do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
      kafka.register
      kafka.multi_receive([event])
      sleep(1.0) # allow for future.get call
    end
  end

  context "when KafkaProducer#send() raises a non-retriable exception" do
    let(:failcount) { 3 }

    let(:exception_classes) { [
        org.apache.kafka.common.errors.SerializationException,
        org.apache.kafka.common.errors.RecordTooLargeException,
        org.apache.kafka.common.errors.InvalidTopicException
    ] }

    before do
      count = 0
      expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).exactly(1).times do
        if count < failcount # fail 'failcount' times in a row.
          count += 1
          # Pick an exception at random
          raise exception_classes.shuffle.first.new("injected exception for testing")
        else
          fail 'unexpected producer#send invocation'
        end
      end
    end

    it "should not retry" do
      kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
      kafka.register
      kafka.multi_receive([event])
    end
  end

  context "when a send fails" do
    context "and the default retries behavior is used" do
      # Fail this many times and then finally succeed.
      let(:failcount) { (rand * 10).to_i }

      # Expect KafkaProducer.send() to get called again after every failure, plus the successful one.
      let(:sendcount) { failcount + 1 }

      it "should retry until successful" do
        count = 0
        success = nil
        expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).exactly(sendcount).times do
          if count < failcount
            count += 1
            # inject some failures.

            # Return a custom Future that will raise an exception to simulate a Kafka send() problem.
            future = java.util.concurrent.FutureTask.new { raise org.apache.kafka.common.errors.TimeoutException.new("Failed") }
          else
            success = true
            future = java.util.concurrent.FutureTask.new { nil } # return no-op future
          end
          future.tap { Thread.start { future.run } }
        end
        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config)
        kafka.register
        kafka.multi_receive([event])
        expect( success ).to be true
      end
    end

    context 'when retries is 0' do
      let(:retries) { 0  }
      let(:max_sends) { 1 }

      it "should should only send once" do
        expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).once do
          # Always fail.
          future = java.util.concurrent.FutureTask.new { raise org.apache.kafka.common.errors.TimeoutException.new("Failed") }
          future.run
          future
        end
        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("retries" => retries))
        kafka.register
        kafka.multi_receive([event])
      end

      it 'should not sleep' do
        expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).once do
          # Always fail.
          future = java.util.concurrent.FutureTask.new { raise org.apache.kafka.common.errors.TimeoutException.new("Failed") }
          future.run
          future
        end

        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("retries" => retries))
        expect(kafka).not_to receive(:sleep).with(anything)
        kafka.register
        kafka.multi_receive([event])
      end
    end

    context "and when retries is set by the user" do
      let(:retries) { (rand * 10).to_i }
      let(:max_sends) { retries + 1 }

      it "should give up after retries are exhausted" do
        expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).at_most(max_sends).times do
          # Always fail.
          future = java.util.concurrent.FutureTask.new { raise org.apache.kafka.common.errors.TimeoutException.new("Failed") }
          future.tap { Thread.start { future.run } }
        end
        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("retries" => retries))
        kafka.register
        kafka.multi_receive([event])
      end

      it 'should only sleep retries number of times' do
        expect_any_instance_of(org.apache.kafka.clients.producer.KafkaProducer).to receive(:send).at_most(max_sends).times do
          # Always fail.
          future = java.util.concurrent.FutureTask.new { raise org.apache.kafka.common.errors.TimeoutException.new("Failed") }
          future.run
          future
        end
        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("retries" => retries))
        expect(kafka).to receive(:sleep).exactly(retries).times
        kafka.register
        kafka.multi_receive([event])
      end
    end
    context 'when retries is -1' do
      let(:retries) { -1 }

      it "should raise a Configuration error" do
        kafka = LogStash::Outputs::Kafka.new(simple_kafka_config.merge("retries" => retries))
        expect { kafka.register }.to raise_error(LogStash::ConfigurationError)
      end
    end
  end

  describe "value_serializer" do
    let(:output) { LogStash::Plugin.lookup("output", "kafka").new(config) }

    context "when a random string is set" do
      let(:config) { { "topic_id" => "random", "value_serializer" => "test_string" } }

      it "raises a ConfigurationError" do
        expect { output.register }.to raise_error(LogStash::ConfigurationError)
      end
    end
  end

  context 'when ssl endpoint identification disabled' do

    let(:config) do
      simple_kafka_config.merge(
          'security_protocol' => 'SSL',
          'ssl_endpoint_identification_algorithm' => '',
          'ssl_truststore_location' => truststore_path,
      )
    end

    let(:truststore_path) do
      File.join(File.dirname(__FILE__), '../../fixtures/trust-store_stub.jks')
    end

    it 'sets empty ssl.endpoint.identification.algorithm' do
      expect(org.apache.kafka.clients.producer.KafkaProducer).
          to receive(:new).with(hash_including('ssl.endpoint.identification.algorithm' => ''))
      subject.register
    end

    it 'configures truststore' do
      expect(org.apache.kafka.clients.producer.KafkaProducer).
          to receive(:new).with(hash_including('ssl.truststore.location' => truststore_path))
      subject.register
    end

  end

  context 'when oauth is configured' do
    let(:config) {
      simple_kafka_config.merge(
        'security_protocol' => 'SASL_PLAINTEXT',
        'sasl_mechanism' => 'OAUTHBEARER',
        'sasl_oauthbearer_token_endpoint_url' => 'https://auth.example.com/token',
        'sasl_oauthbearer_scope_claim_name' => 'custom_scope'
      )
    }

    it "sets oauth properties" do
      expect(org.apache.kafka.clients.producer.KafkaProducer).
        to receive(:new).with(hash_including(
          'security.protocol' => 'SASL_PLAINTEXT',
          'sasl.mechanism' => 'OAUTHBEARER',
          'sasl.oauthbearer.token.endpoint.url' => 'https://auth.example.com/token',
          'sasl.oauthbearer.scope.claim.name' => 'custom_scope'
        ))
      subject.register
    end
  end

  context 'when sasl is configured' do
    let(:config) {
      simple_kafka_config.merge(
        'security_protocol' => 'SASL_PLAINTEXT',
        'sasl_mechanism' => 'OAUTHBEARER',
        'sasl_login_connect_timeout_ms' => 15000,
        'sasl_login_read_timeout_ms' => 5000,
        'sasl_login_retry_backoff_ms' => 200,
        'sasl_login_retry_backoff_max_ms' => 15000,
        'sasl_login_callback_handler_class' => 'org.example.CustomLoginHandler'
      )
    }

    it "sets sasl login properties" do
      expect(org.apache.kafka.clients.producer.KafkaProducer).
        to receive(:new).with(hash_including(
          'security.protocol' => 'SASL_PLAINTEXT',
          'sasl.mechanism' => 'OAUTHBEARER',
          'sasl.login.connect.timeout.ms' => '15000',
          'sasl.login.read.timeout.ms' => '5000',
          'sasl.login.retry.backoff.ms' => '200',
          'sasl.login.retry.backoff.max.ms' => '15000',
          'sasl.login.callback.handler.class' => 'org.example.CustomLoginHandler'
        ))
      subject.register
    end

    context 'with sasl_jaas_config' do
      let(:config) {
        simple_kafka_config.merge(
          'security_protocol' => 'SASL_PLAINTEXT',
          'sasl_mechanism' => 'PLAIN'
        )
      }

      shared_examples 'sasl_jaas_config password handling' do
        it "sasl_jaas_config.value returns the original string" do
          subject.register
          expect(subject.sasl_jaas_config.value).to eq(jaas_config_value)
        end

        it "sasl_jaas_config.inspect does not expose the password" do
          subject.register
          expect(subject.sasl_jaas_config.inspect).not_to include('admin-secret')
          expect(subject.sasl_jaas_config.inspect).to eq('<password>')
        end
      end

      context 'with single-line config' do
        let(:jaas_config_value) { 'org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";' }
        let(:config) { super().merge('sasl_jaas_config' => jaas_config_value) }

        include_examples 'sasl_jaas_config password handling'
      end

      context 'with multiline config' do
        let(:jaas_config_value) {
          <<~JAAS
            org.apache.kafka.common.security.plain.PlainLoginModule required
              username="admin"
              password="admin-secret"
              user_admin="admin-secret"
              user_alice="alice-secret";
          JAAS
        }
        let(:config) { super().merge('sasl_jaas_config' => jaas_config_value) }

        include_examples 'sasl_jaas_config password handling'
      end
    end
  end
end
