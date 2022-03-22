# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"
require "rspec/wait"
require "stud/try"
require "manticore"
require "json"

# Please run kafka_test_setup.sh prior to executing this integration test.
describe "inputs/kafka", :integration => true do
  # Group ids to make sure that the consumers get all the logs.
  let(:group_id_1) {rand(36**8).to_s(36)}
  let(:group_id_2) {rand(36**8).to_s(36)}
  let(:group_id_3) {rand(36**8).to_s(36)}
  let(:group_id_4) {rand(36**8).to_s(36)}
  let(:group_id_5) {rand(36**8).to_s(36)}
  let(:group_id_6) {rand(36**8).to_s(36)}
  let(:plain_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:multi_consumer_config) do
    plain_config.merge({"group_id" => group_id_4, "client_id" => "spec", "consumer_threads" => 3})
  end
  let(:snappy_config) do
    { 'topics' => ['logstash_integration_topic_snappy'], 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:lz4_config) do
    { 'topics' => ['logstash_integration_topic_lz4'], 'group_id' => group_id_1,
      'auto_offset_reset' => 'earliest' }
  end
  let(:pattern_config) do
    { 'topics_pattern' => 'logstash_integration_topic_.*', 'group_id' => group_id_2,
      'auto_offset_reset' => 'earliest' }
  end
  let(:decorate_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'group_id' => group_id_3,
      'auto_offset_reset' => 'earliest', 'decorate_events' => 'true' }
  end
  let(:decorate_headers_config) do
    { 'topics' => ['logstash_integration_topic_plain_with_headers'], 'group_id' => group_id_3,
      'auto_offset_reset' => 'earliest', 'decorate_events' => 'extended' }
  end
  let(:decorate_bad_headers_config) do
    { 'topics' => ['logstash_integration_topic_plain_with_headers_badly'], 'group_id' => group_id_3,
      'auto_offset_reset' => 'earliest', 'decorate_events' => 'extended' }
  end
  let(:manual_commit_config) do
    { 'topics' => ['logstash_integration_topic_plain'], 'group_id' => group_id_5,
      'auto_offset_reset' => 'earliest', 'enable_auto_commit' => 'false' }
  end
  let(:timeout_seconds) { 30 }
  let(:num_events) { 103 }

  before(:all) do
    # Prepare message with headers with valid UTF-8 chars
    header = org.apache.kafka.common.header.internals.RecordHeader.new("name", "John ανδρεα €".to_java_bytes)
    record = org.apache.kafka.clients.producer.ProducerRecord.new(
                "logstash_integration_topic_plain_with_headers", 0, "key", "value", [header])
    send_message(record)

    # Prepare message with headers with invalid UTF-8 chars
    invalid = "日本".encode('Shift_JIS').force_encoding(Encoding::UTF_8).to_java_bytes
    header = org.apache.kafka.common.header.internals.RecordHeader.new("name", invalid)
    record = org.apache.kafka.clients.producer.ProducerRecord.new(
                "logstash_integration_topic_plain_with_headers_badly", 0, "key", "value", [header])

    send_message(record)
  end

  def send_message(record)
    props = java.util.Properties.new
    kafka = org.apache.kafka.clients.producer.ProducerConfig
    props.put(kafka::BOOTSTRAP_SERVERS_CONFIG, "localhost:9092")
    props.put(kafka::KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")
    props.put(kafka::VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")

    producer = org.apache.kafka.clients.producer.KafkaProducer.new(props)

    producer.send(record)
    producer.close
  end

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
  end

  context "#kafka-topics-pattern" do
    it "should consume all messages from all 3 topics" do
      total_events = num_events * 3 + 2
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

    it "should show the right topic and group name in and kafka headers decorated kafka section" do
      start = LogStash::Timestamp.now.time.to_i
      consume_messages(decorate_headers_config, timeout: timeout_seconds, event_count: 1) do |queue, _|
        expect(queue.length).to eq(1)
        event = queue.shift
        expect(event.get("[@metadata][kafka][topic]")).to eq("logstash_integration_topic_plain_with_headers")
        expect(event.get("[@metadata][kafka][consumer_group]")).to eq(group_id_3)
        expect(event.get("[@metadata][kafka][timestamp]")).to be >= start
        expect(event.get("[@metadata][kafka][headers][name]")).to eq("John ανδρεα €")
      end
    end

    it "should skip headers not encoded in UTF-8" do
      start = LogStash::Timestamp.now.time.to_i
      consume_messages(decorate_bad_headers_config, timeout: timeout_seconds, event_count: 1) do |queue, _|
        expect(queue.length).to eq(1)
        event = queue.shift
        expect(event.get("[@metadata][kafka][topic]")).to eq("logstash_integration_topic_plain_with_headers_badly")
        expect(event.get("[@metadata][kafka][consumer_group]")).to eq(group_id_3)
        expect(event.get("[@metadata][kafka][timestamp]")).to be >= start

        expect(event.include?("[@metadata][kafka][headers][name]")).to eq(false)
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
end

private

def consume_messages(config, queue: Queue.new, timeout:, event_count:)
  kafka_input = LogStash::Inputs::Kafka.new(config)
  kafka_input.register
  t = Thread.new { kafka_input.run(queue) }
  begin
    t.run
    wait(timeout).for { queue.length }.to eq(event_count) unless timeout.eql?(false)
    block_given? ? yield(queue, kafka_input) : queue
  ensure
    kafka_input.do_stop
    t.kill
    t.join(30)
  end
end


describe "schema registry connection options" do
  schema_registry = Manticore::Client.new
  before (:all) do
    shutdown_schema_registry
    startup_schema_registry(schema_registry)
  end

  after(:all) do
    shutdown_schema_registry
  end

  context "remote endpoint validation" do
    it "should fail if not reachable" do
      config = {'schema_registry_url' => 'http://localnothost:8081'}
      kafka_input = LogStash::Inputs::Kafka.new(config)
      expect { kafka_input.register }.to raise_error LogStash::ConfigurationError, /Schema registry service doesn't respond.*/
    end

    it "should fail if any topic is not matched by a subject on the schema registry" do
      config = {
        'schema_registry_url' => 'http://localhost:8081',
        'topics' => ['temperature_stream']
      }

      kafka_input = LogStash::Inputs::Kafka.new(config)
      expect { kafka_input.register }.to raise_error LogStash::ConfigurationError, /The schema registry does not contain definitions for required topic subjects: \["temperature_stream-value"\]/
    end

    context "register with subject present" do
      SUBJECT_NAME = "temperature_stream-value"

      before(:each) do
        response = save_avro_schema_to_schema_registry(File.join(Dir.pwd, "spec", "unit", "inputs", "avro_schema_fixture_payment.asvc"), SUBJECT_NAME)
        expect( response.code ).to be(200)
      end

      after(:each) do
        delete_remote_schema(schema_registry, SUBJECT_NAME)
      end

      it "should correctly complete registration phase" do
        config = {
          'schema_registry_url' => 'http://localhost:8081',
          'topics' => ['temperature_stream']
        }
        kafka_input = LogStash::Inputs::Kafka.new(config)
        kafka_input.register
      end
    end
  end
end

def save_avro_schema_to_schema_registry(schema_file, subject_name)
  raw_schema = File.readlines(schema_file).map(&:chomp).join
  raw_schema_quoted = raw_schema.gsub('"', '\"')
  response = Manticore.post("http://localhost:8081/subjects/#{subject_name}/versions",
          body: '{"schema": "' + raw_schema_quoted + '"}',
          headers: {"Content-Type" => "application/vnd.schemaregistry.v1+json"})
  response
end

def delete_remote_schema(schema_registry_client, subject_name)
  expect(schema_registry_client.delete("http://localhost:8081/subjects/#{subject_name}").code ).to be(200)
  expect(schema_registry_client.delete("http://localhost:8081/subjects/#{subject_name}?permanent=true").code ).to be(200)
end

# AdminClientConfig = org.alpache.kafka.clients.admin.AdminClientConfig

def startup_schema_registry(schema_registry, auth=false)
  system('./stop_schema_registry.sh')
  auth ? system('./start_auth_schema_registry.sh') : system('./start_schema_registry.sh')
  url = auth ? "http://barney:changeme@localhost:8081" : "http://localhost:8081"
  Stud.try(20.times, [Manticore::SocketException, StandardError, RSpec::Expectations::ExpectationNotMetError]) do
    expect(schema_registry.get(url).code).to eq(200)
  end
end

describe "Schema registry API", :integration => true do
  schema_registry = Manticore::Client.new

  before(:all) do
    startup_schema_registry(schema_registry)
  end

  after(:all) do
    shutdown_schema_registry
  end

  context 'listing subject on clean instance' do
    it "should return an empty set" do
      subjects = JSON.parse schema_registry.get('http://localhost:8081/subjects').body
      expect( subjects ).to be_empty
    end
  end

  context 'send a schema definition' do
    it "save the definition" do
      response = save_avro_schema_to_schema_registry(File.join(Dir.pwd, "spec", "unit", "inputs", "avro_schema_fixture_payment.asvc"), "schema_test_1")
      expect( response.code ).to be(200)
      delete_remote_schema(schema_registry, "schema_test_1")
    end

    it "delete the schema just added" do
      response = save_avro_schema_to_schema_registry(File.join(Dir.pwd, "spec", "unit", "inputs", "avro_schema_fixture_payment.asvc"), "schema_test_1")
      expect( response.code ).to be(200)

      expect( schema_registry.delete('http://localhost:8081/subjects/schema_test_1?permanent=false').code ).to be(200)
      sleep(1)
      subjects = JSON.parse schema_registry.get('http://localhost:8081/subjects').body
      expect( subjects ).to be_empty
    end
  end
end

def shutdown_schema_registry
  system('./stop_schema_registry.sh')
end

describe "Deserializing with the schema registry", :integration => true do
  schema_registry = Manticore::Client.new

  shared_examples 'it reads from a topic using a schema registry' do |with_auth|

    before(:all) do
      shutdown_schema_registry
      startup_schema_registry(schema_registry, with_auth)
    end

    after(:all) do
      shutdown_schema_registry
    end

    after(:each) do
      expect( schema_registry.delete("#{subject_url}/#{avro_topic_name}-value").code ).to be(200)
      sleep 1
      expect( schema_registry.delete("#{subject_url}/#{avro_topic_name}-value?permanent=true").code ).to be(200)

      Stud.try(3.times, [StandardError, RSpec::Expectations::ExpectationNotMetError]) do
        wait(10).for do
          subjects = JSON.parse schema_registry.get(subject_url).body
          subjects.empty?
        end.to be_truthy
      end
    end

    let(:base_config) do
      {
          'topics' => [avro_topic_name], 'group_id' => group_id_1, 'auto_offset_reset' => 'earliest'
      }
    end

    let(:group_id_1) {rand(36**8).to_s(36)}

    def delete_topic_if_exists(topic_name, user = nil, password = nil)
      props = java.util.Properties.new
      props.put(Java::org.apache.kafka.clients.admin.AdminClientConfig::BOOTSTRAP_SERVERS_CONFIG, "localhost:9092")
      serdes_config = Java::io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig
      unless user.nil?
        props.put(serdes_config::BASIC_AUTH_CREDENTIALS_SOURCE, 'USER_INFO')
        props.put(serdes_config::USER_INFO_CONFIG,  "#{user}:#{password}")
      end
      admin_client = org.apache.kafka.clients.admin.AdminClient.create(props)
      topics_list = admin_client.listTopics().names().get()
      if topics_list.contains(topic_name)
        result = admin_client.deleteTopics([topic_name])
        result.values.get(topic_name).get()
      end
    end

    def write_some_data_to(topic_name, user = nil, password = nil)
      props = java.util.Properties.new
      config = org.apache.kafka.clients.producer.ProducerConfig

      serdes_config = Java::io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig
      props.put(serdes_config::SCHEMA_REGISTRY_URL_CONFIG, "http://localhost:8081")

      props.put(config::BOOTSTRAP_SERVERS_CONFIG, "localhost:9092")
      unless user.nil?
        props.put(serdes_config::BASIC_AUTH_CREDENTIALS_SOURCE, 'USER_INFO')
        props.put(serdes_config::USER_INFO_CONFIG,  "#{user}:#{password}")
      end
      props.put(config::KEY_SERIALIZER_CLASS_CONFIG, org.apache.kafka.common.serialization.StringSerializer.java_class)
      props.put(config::VALUE_SERIALIZER_CLASS_CONFIG, Java::io.confluent.kafka.serializers.KafkaAvroSerializer.java_class)

      parser = org.apache.avro.Schema::Parser.new()
      user_schema = '''{"type":"record",
                        "name":"myrecord",
                        "fields":[
                            {"name":"str_field", "type": "string"},
                            {"name":"map_field", "type": {"type": "map", "values": "string"}}
                        ]}'''
      schema = parser.parse(user_schema)
      avro_record = org.apache.avro.generic.GenericData::Record.new(schema)
      avro_record.put("str_field", "value1")
      avro_record.put("map_field", {"inner_field" => "inner value"})

      producer = org.apache.kafka.clients.producer.KafkaProducer.new(props)
      record = org.apache.kafka.clients.producer.ProducerRecord.new(topic_name, "avro_key", avro_record)
      producer.send(record)
    end

    it "stored a new schema using Avro Kafka serdes" do
      auth ? delete_topic_if_exists(avro_topic_name, user, password) : delete_topic_if_exists(avro_topic_name)
      auth ? write_some_data_to(avro_topic_name, user, password) : write_some_data_to(avro_topic_name)

      subjects = JSON.parse schema_registry.get(subject_url).body
      expect( subjects ).to contain_exactly("#{avro_topic_name}-value")

      num_events = 1
      queue = consume_messages(plain_config, timeout: 30, event_count: num_events)
      expect(queue.length).to eq(num_events)
      elem = queue.pop
      expect( elem.to_hash).not_to include("message")
      expect( elem.get("str_field") ).to eq("value1")
      expect( elem.get("map_field")["inner_field"] ).to eq("inner value")
    end
  end

  context 'with an unauthed schema registry' do
    let(:auth) { false }
    let(:avro_topic_name) { "topic_avro" }
    let(:subject_url) { "http://localhost:8081/subjects" }
    let(:plain_config)  { base_config.merge!({'schema_registry_url' => "http://localhost:8081"}) }

    it_behaves_like 'it reads from a topic using a schema registry', false
  end

  context 'with an authed schema registry' do
    let(:auth) { true }
    let(:user) { "barney" }
    let(:password) { "changeme" }
    let(:avro_topic_name) { "topic_avro_auth" }
    let(:subject_url) { "http://#{user}:#{password}@localhost:8081/subjects" }

    context 'using schema_registry_key' do
      let(:plain_config) do
        base_config.merge!({
          'schema_registry_url' => "http://localhost:8081",
          'schema_registry_key' => user,
          'schema_registry_secret' => password
        })
      end

      it_behaves_like 'it reads from a topic using a schema registry', true
    end

    context 'using schema_registry_url' do
      let(:plain_config) do
        base_config.merge!({
          'schema_registry_url' => "http://#{user}:#{password}@localhost:8081"
        })
      end

      it_behaves_like 'it reads from a topic using a schema registry', true
    end
  end
end