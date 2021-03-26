# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"
require "concurrent"

class MockConsumer
  def initialize
    @wake = Concurrent::AtomicBoolean.new(false)
  end

  def subscribe(topics)
  end
  
  def poll(ms)
    if @wake.value
      raise org.apache.kafka.common.errors.WakeupException.new
    else
      10.times.map do
        org.apache.kafka.clients.consumer.ConsumerRecord.new("logstash", 0, 0, "key", "value")
      end
    end
  end

  def close
  end

  def wakeup
    @wake.make_true
  end
end

describe LogStash::Inputs::Kafka do
  let(:config) { { 'topics' => ['logstash'], 'consumer_threads' => 4 } }
  subject { LogStash::Inputs::Kafka.new(config) }

  it "should register" do
    expect { subject.register }.to_not raise_error
  end

  context "register parameter verification" do
    context "schema_registry_url" do
      let(:config) do
        { 'schema_registry_url' => 'http://localhost:8081', 'topics' => ['logstash'], 'consumer_threads' => 4 }
      end

      it "conflict with value_deserializer_class should fail" do
        config['value_deserializer_class'] = 'my.fantasy.Deserializer'
        expect { subject.register }.to raise_error LogStash::ConfigurationError, /Option schema_registry_url prohibit the customization of value_deserializer_class/
      end

      it "conflict with topics_pattern should fail" do
        config['topics_pattern'] = 'topic_.*'
        expect { subject.register }.to raise_error LogStash::ConfigurationError, /Option schema_registry_url prohibit the customization of topics_pattern/
      end
    end

    context "decorate_events" do
      let(:config) { { 'decorate_events' => 'extended'} }

      it "should raise error for invalid value" do
        config['decorate_events'] = 'avoid'
        expect { subject.register }.to raise_error LogStash::ConfigurationError, /Something is wrong with your configuration./
      end

      it "should map old true boolean value to :record_props mode" do
        config['decorate_events'] = "true"
        subject.register
        expect(subject.metadata_mode).to include(:record_props)
      end
    end
  end

  context 'with client_rack' do
    let(:config) { super().merge('client_rack' => 'EU-R1') }

    it "sets broker rack parameter" do
      expect(org.apache.kafka.clients.consumer.KafkaConsumer).
          to receive(:new).with(hash_including('client.rack' => 'EU-R1')).
              and_return kafka_client = double('kafka-consumer')

      expect( subject.send(:create_consumer, 'sample_client-0') ).to be kafka_client
    end
  end

  context 'string integer config' do
    let(:config) { super().merge('session_timeout_ms' => '25000', 'max_poll_interval_ms' => '345000') }

    it "sets integer values" do
      expect(org.apache.kafka.clients.consumer.KafkaConsumer).
          to receive(:new).with(hash_including('session.timeout.ms' => '25000', 'max.poll.interval.ms' => '345000')).
              and_return kafka_client = double('kafka-consumer')

      expect( subject.send(:create_consumer, 'sample_client-1') ).to be kafka_client
    end
  end

  context 'integer config' do
    let(:config) { super().merge('session_timeout_ms' => 25200, 'max_poll_interval_ms' => 123_000) }

    it "sets integer values" do
      expect(org.apache.kafka.clients.consumer.KafkaConsumer).
          to receive(:new).with(hash_including('session.timeout.ms' => '25200', 'max.poll.interval.ms' => '123000')).
              and_return kafka_client = double('kafka-consumer')

      expect( subject.send(:create_consumer, 'sample_client-2') ).to be kafka_client
    end
  end

  context 'string boolean config' do
    let(:config) { super().merge('enable_auto_commit' => 'false', 'check_crcs' => 'true') }

    it "sets parameters" do
      expect(org.apache.kafka.clients.consumer.KafkaConsumer).
          to receive(:new).with(hash_including('enable.auto.commit' => 'false', 'check.crcs' => 'true')).
              and_return kafka_client = double('kafka-consumer')

      expect( subject.send(:create_consumer, 'sample_client-3') ).to be kafka_client
      expect( subject.enable_auto_commit ).to be false
    end
  end

  context 'boolean config' do
    let(:config) { super().merge('enable_auto_commit' => true, 'check_crcs' => false) }

    it "sets parameters" do
      expect(org.apache.kafka.clients.consumer.KafkaConsumer).
          to receive(:new).with(hash_including('enable.auto.commit' => 'true', 'check.crcs' => 'false')).
              and_return kafka_client = double('kafka-consumer')

      expect( subject.send(:create_consumer, 'sample_client-4') ).to be kafka_client
      expect( subject.enable_auto_commit ).to be true
    end
  end
end
