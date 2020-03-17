# encoding: utf-8

require "logstash/devutils/rspec/spec_helper"
require 'logstash/outputs/kafka'
require 'json'
require 'kafka'

describe "outputs/kafka", :integration => true do
  let(:kafka_host) { 'localhost' }
  let(:kafka_port) { 9092 }
  let(:num_events) { 10 }

  let(:base_config) { {'client_id' => 'kafkaoutputspec'} }
  let(:event) do
    LogStash::Event.new({ 'message' =>
      '183.60.215.50 - - [11/Sep/2014:22:00:00 +0000] "GET /scripts/netcat-webserver HTTP/1.1" 200 182 "-" "Mozilla/5.0 (compatible; EasouSpider; +http://www.easou.com/search/spider.html)"',
      '@timestamp' => LogStash::Timestamp.at(0)
    })
  end

  let(:kafka_client) { Kafka.new ["#{kafka_host}:#{kafka_port}"] }

  context 'when outputting messages serialized as String' do
    let(:test_topic) { 'logstash_integration_topic1' }
    let(:num_events) { 3 }

    before :each do
      config = base_config.merge({"topic_id" => test_topic})
      load_kafka_data(config)
    end

    it 'should have data integrity' do
      messages = fetch_messages(test_topic)

      expect(messages.size).to eq(num_events)
      messages.each do |m|
        expect(m.value).to eq(event.to_s)
      end
    end

  end

  context 'when outputting messages serialized as Byte Array' do
    let(:test_topic) { 'topic1b' }
    let(:num_events) { 3 }

    before :each do
      config = base_config.merge(
        {
          "topic_id" => test_topic,
          "value_serializer" => 'org.apache.kafka.common.serialization.ByteArraySerializer'
        }
      )
      load_kafka_data(config)
    end

    it 'should have data integrity' do
      messages = fetch_messages(test_topic)

      expect(messages.size).to eq(num_events)
      messages.each do |m|
        expect(m.value).to eq(event.to_s)
      end
    end

  end

  context 'when setting message_key' do
    let(:num_events) { 10 }
    let(:test_topic) { 'logstash_integration_topic2' }

    before :each do
      config = base_config.merge({"topic_id" => test_topic, "message_key" => "static_key"})
      load_kafka_data(config)
    end

    it 'should send all events to one partition' do
      data0 = fetch_messages(test_topic, partition: 0)
      data1 = fetch_messages(test_topic, partition: 1)
      expect(data0.size == num_events || data1.size == num_events).to be true
    end
  end

  context 'when using gzip compression' do
    let(:test_topic) { 'logstash_integration_gzip_topic' }

    before :each do
      config = base_config.merge({"topic_id" => test_topic, "compression_type" => "gzip"})
      load_kafka_data(config)
    end

    it 'should have data integrity' do
      messages = fetch_messages(test_topic)

      expect(messages.size).to eq(num_events)
      messages.each do |m|
        expect(m.value).to eq(event.to_s)
      end
    end
  end

  context 'when using snappy compression' do
    let(:test_topic) { 'logstash_integration_snappy_topic' }

    before :each do
      config = base_config.merge({"topic_id" => test_topic, "compression_type" => "snappy"})
      load_kafka_data(config)
    end

    it 'should have data integrity' do
      messages = fetch_messages(test_topic)

      expect(messages.size).to eq(num_events)
      messages.each do |m|
        expect(m.value).to eq(event.to_s)
      end
    end
  end

  context 'when using LZ4 compression' do
    let(:test_topic) { 'logstash_integration_lz4_topic' }

    before :each do
      config = base_config.merge({"topic_id" => test_topic, "compression_type" => "lz4"})
      load_kafka_data(config)
    end

    # NOTE: depends on extlz4 gem which is using a C-extension
    # it 'should have data integrity' do
    #   messages = fetch_messages(test_topic)
    #
    #   expect(messages.size).to eq(num_events)
    #   messages.each do |m|
    #     expect(m.value).to eq(event.to_s)
    #   end
    # end
  end

  context 'when using multi partition topic' do
    let(:num_events) { 10 }
    let(:test_topic) { 'logstash_integration_topic3' }

    before :each do
      config = base_config.merge("topic_id" => test_topic, "partitioner" => 'org.apache.kafka.clients.producer.RoundRobinPartitioner')
      load_kafka_data(config)
    end

    it 'should distribute events to all partition' do
      consumer0_records = fetch_messages(test_topic, partition: 0)
      consumer1_records = fetch_messages(test_topic, partition: 1)
      consumer2_records = fetch_messages(test_topic, partition: 2)

      all_records = consumer0_records + consumer1_records + consumer2_records
      expect(all_records.size).to eq(num_events)
      all_records.each do |m|
        expect(m.value).to eq(event.to_s)
      end

      expect(consumer0_records.size).to be > 1
      expect(consumer1_records.size).to be > 1
      expect(consumer2_records.size).to be > 1
    end
  end

  def load_kafka_data(config)
    kafka = LogStash::Outputs::Kafka.new(config)
    kafka.register
    kafka.multi_receive(num_events.times.collect { event })
    kafka.close
  end

  def fetch_messages(topic, partition: 0, offset: :earliest)
    kafka_client.fetch_messages(topic: topic, partition: partition, offset: offset)
  end

end
