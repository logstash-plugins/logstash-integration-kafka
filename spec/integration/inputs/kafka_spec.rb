# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"
require "rspec/wait"

# Please run kafka_test_setup.sh prior to executing this integration test.
describe "inputs/kafka", :integration => true do
  # Group ids to make sure that the consumers get all the logs.
  let(:group_id_1) {rand(36**8).to_s(36)}
  let(:group_id_2) {rand(36**8).to_s(36)}
  let(:group_id_3) {rand(36**8).to_s(36)}
  let(:group_id_4) {rand(36**8).to_s(36)}
  let(:group_id_5) {rand(36**8).to_s(36)}
  let(:group_id_6) {rand(36**8).to_s(36)}
  let(:group_id_7) {rand(36**8).to_s(36)}
  let(:plain_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'codec' => 'plain', 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:multi_consumer_config) do
    plain_config.merge({"group_id" => group_id_4, "client_id" => "spec", "consumer_threads" => 3})
  end
  let(:not_append_thread_num_config) do
    plain_config.merge({"group_id" => group_id_7, "client_id" => "spec", "consumer_threads" => 3, "append_thread_num_to_client_id" => false})
  end
  let(:snappy_config) do
    { 'topics' => ['logstash_integration_topic_snappy'], 'codec' => 'plain', 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:lz4_config) do
    { 'topics' => ['logstash_integration_topic_lz4'], 'codec' => 'plain', 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:pattern_config) do
    { 'topics_pattern' => 'logstash_integration_topic_.*', 'group_id' => group_id_2, 'codec' => 'plain',
      'auto_offset_reset' => 'earliest' }
  end
  let(:decorate_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'codec' => 'plain', 'group_id' => group_id_3,
      'auto_offset_reset' => 'earliest', 'decorate_events' => true }
  end
  let(:manual_commit_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'codec' => 'plain', 'group_id' => group_id_5,
      'auto_offset_reset' => 'earliest', 'enable_auto_commit' => 'false' }
  end
  let(:timeout_seconds) { 30 }
  let(:num_events) { 103 }

  describe "#kafka-topics" do

    it "should consume all messages from plain 3-partition topic" do
      queue = consume_messages(plain_config, timeout: timeout_seconds, event_count: num_events)
      expect(queue.length).to eq(num_events)
    end

    it "should consume all messages from snappy 3-partition topic" do
      queue = consume_messages(snappy_config, timeout: timeout_seconds, event_count: num_events)
      expect(queue.length).to eq(num_events)
    end

    it "should consume all messages from lz4 3-partition topic" do
      queue = consume_messages(lz4_config, timeout: timeout_seconds, event_count: num_events)
      expect(queue.length).to eq(num_events)
    end

    it "should consumer all messages with multiple consumers" do
      consume_messages(multi_consumer_config, timeout: timeout_seconds, event_count: num_events) do |queue, kafka_input|
        expect(queue.length).to eq(num_events)
        kafka_input.kafka_consumers.each_with_index do |consumer, i|
          expect(consumer.metrics.keys.first.tags["client-id"]).to eq("spec-#{i}")
        end
      end
    end
    it "should consumer all messages with same client_id" do
      consume_messages(not_append_thread_num_config, timeout: timeout_seconds, event_count: num_events) do |queue, kafka_input|
        expect(queue.length).to eq(num_events)
        kafka_input.kafka_consumers.each_with_index do |consumer, i|
          expect(consumer.metrics.keys.first.tags["client-id"]).to eq("spec")
        end
      end
    end
  end

  context "#kafka-topics-pattern" do
    it "should consume all messages from all 3 topics" do
      total_events = num_events * 3
      queue = consume_messages(pattern_config, timeout: timeout_seconds, event_count: total_events)
      expect(queue.length).to eq(total_events)
    end
  end

  context "#kafka-decorate" do
    it "should show the right topic and group name in decorated kafka section" do
      start = LogStash::Timestamp.now.time.to_i
      consume_messages(decorate_config, timeout: timeout_seconds, event_count: num_events) do |queue, _|
        expect(queue.length).to eq(num_events)
        event = queue.shift
        expect(event.get("[@metadata][kafka][topic]")).to eq("logstash_integration_topic_plain")
        expect(event.get("[@metadata][kafka][consumer_group]")).to eq(group_id_3)
        expect(event.get("[@metadata][kafka][timestamp]")).to be >= start
      end
    end
  end

  context "#kafka-offset-commit" do
    it "should manually commit offsets" do
      queue = consume_messages(manual_commit_config, timeout: timeout_seconds, event_count: num_events)
      expect(queue.length).to eq(num_events)
    end
  end

  context 'setting partition_assignment_strategy' do
    let(:test_topic) { 'logstash_integration_partitioner_topic' }
    let(:consumer_config) do
      plain_config.merge(
          "topics" => [test_topic],
          'group_id' => group_id_6,
          "client_id" => "partition_assignment_strategy-spec",
          "consumer_threads" => 2,
          "partition_assignment_strategy" => partition_assignment_strategy
      )
    end
    let(:partition_assignment_strategy) { nil }

    # NOTE: just verify setting works, as its a bit cumbersome to do in a unit spec
    [ 'range', 'round_robin', 'sticky', 'org.apache.kafka.clients.consumer.CooperativeStickyAssignor' ].each do |partition_assignment_strategy|
      describe partition_assignment_strategy do
        let(:partition_assignment_strategy) { partition_assignment_strategy }
        it 'consumes data' do
          consume_messages(consumer_config, timeout: false, event_count: 0)
        end
      end
    end
  end

  private

  def consume_messages(config, queue: Queue.new, timeout:, event_count:)
    kafka_input = LogStash::Inputs::Kafka.new(config)
    t = Thread.new { kafka_input.run(queue) }
    begin
      t.run
      wait(timeout).for { queue.length }.to eq(event_count) unless timeout.eql?(false)
      block_given? ? yield(queue, kafka_input) : queue
    ensure
      t.kill
      t.join(30_000)
    end
  end

end
