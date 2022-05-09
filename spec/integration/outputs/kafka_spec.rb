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
  let(:message_content) do
    '"GET /scripts/netcat-webserver HTTP/1.1" 200 182 "-" "Mozilla/5.0 (compatible; EasouSpider; +http://www.easou.com/search/spider.html)"'
  end
  let(:event) do
    LogStash::Event.new({ 'message' =>
      '183.60.215.50 - - [11/Sep/2014:22:00:00 +0000] ' + message_content,
      '@timestamp' => LogStash::Timestamp.at(0)
    })
  end

  let(:kafka_client) { Kafka.new ["#{kafka_host}:#{kafka_port}"] }

  context 'when outputting messages serialized as String' do
    let(:test_topic) { 'logstash_integration_topic1' }
    let(:num_events) { 3 }

    before :each do
      # NOTE: the connections_max_idle_ms is irrelevant just testing that configuration works ...
      config = base_config.merge({"topic_id" => test_topic, "connections_max_idle_ms" => 540_000})
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
    let(:test_topic) { 'logstash_integration_topicbytearray' }
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

  context 'when using zstd compression' do
    let(:test_topic) { 'logstash_integration_zstd_topic' }

    before :each do
      config = base_config.merge({"topic_id" => test_topic, "compression_type" => "zstd"})
      load_kafka_data(config)
    end

    # NOTE: depends on zstd-ruby gem which is using a C-extension
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
    let(:num_events) { 100 } # ~ more than (batch.size) 16,384 bytes
    let(:test_topic) { 'logstash_integration_topic3' }

    before :each do
      config = base_config.merge("topic_id" => test_topic, "partitioner" => 'org.apache.kafka.clients.producer.UniformStickyPartitioner')
      load_kafka_data(config) do # let's have a bit more (diverse) dataset
        num_events.times.collect do
          LogStash::Event.new.tap do |e|
            e.set('message', event.get('message').sub('183.60.215.50') { "#{rand(126)+1}.#{rand(126)+1}.#{rand(126)+1}.#{rand(126)+1}" })
          end
        end
      end
    end

    it 'should distribute events to all partitions' do
      consumer0_records = fetch_messages(test_topic, partition: 0)
      consumer1_records = fetch_messages(test_topic, partition: 1)
      consumer2_records = fetch_messages(test_topic, partition: 2)

      all_records = consumer0_records + consumer1_records + consumer2_records
      expect(all_records.size).to eq(num_events * 2)
      all_records.each do |m|
        expect(m.value).to include message_content
      end

      expect(consumer0_records.size).to be > 1
      expect(consumer1_records.size).to be > 1
      expect(consumer2_records.size).to be > 1
    end
  end

  context 'setting partitioner' do
    let(:test_topic) { 'logstash_integration_partitioner_topic' }
    let(:partitioner) { nil }

    before :each do
      @messages_offset = fetch_messages_from_all_partitions

      config = base_config.merge("topic_id" => test_topic, 'partitioner' => partitioner)
      load_kafka_data(config)
    end

    [ 'default', 'round_robin', 'uniform_sticky' ].each do |partitioner|
      describe partitioner do
        let(:partitioner) { partitioner }
        it 'loads data' do
          expect(fetch_messages_from_all_partitions - @messages_offset).to eql num_events
        end
      end
    end

    def fetch_messages_from_all_partitions
      3.times.map { |i| fetch_messages(test_topic, partition: i).size }.sum
    end
  end

  def load_kafka_data(config)
    kafka = LogStash::Outputs::Kafka.new(config)
    kafka.register
    kafka.multi_receive(num_events.times.collect { event })
    kafka.multi_receive(Array(yield)) if block_given?
    kafka.close
  end

  def fetch_messages(topic, partition: 0, offset: :earliest)
    kafka_client.fetch_messages(topic: topic, partition: partition, offset: offset)
  end

end
