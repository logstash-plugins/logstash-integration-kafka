# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"
require "concurrent"


describe LogStash::Inputs::Kafka do
  let(:common_config) { { 'topics' => ['logstash'] } }
  let(:config) { common_config }
  let(:consumer_double) { double(:consumer) }
  let(:needs_raise) { false }
  let(:payload) {
    10.times.map do
      org.apache.kafka.clients.consumer.ConsumerRecord.new("logstash", 0, 0, "key", "value")
    end
  }
  subject { LogStash::Inputs::Kafka.new(config) }

  describe '#poll' do
    before do
      polled = false
      allow(consumer_double).to receive(:poll) do
        if polled
          []
        else
          polled = true
          payload
        end
      end
    end

    it 'should poll' do
      expect(consumer_double).to receive(:poll)
      expect(subject.do_poll(consumer_double)).to eq(payload)
    end

    it 'should return nil if Kafka Exception is encountered' do
      expect(consumer_double).to receive(:poll).and_raise(org.apache.kafka.common.errors.TopicAuthorizationException.new(''))
      expect(subject.do_poll(consumer_double)).to be_empty
    end

    it 'should not throw if Kafka Exception is encountered' do
      expect(consumer_double).to receive(:poll).and_raise(org.apache.kafka.common.errors.TopicAuthorizationException.new(''))
      expect{subject.do_poll(consumer_double)}.not_to raise_error
    end

    it 'should return no records if Assertion Error is encountered' do
      expect(consumer_double).to receive(:poll).and_raise(java.lang.AssertionError.new(''))
      expect{subject.do_poll(consumer_double)}.to raise_error(java.lang.AssertionError)
    end
  end

  describe '#maybe_commit_offset' do
    context 'with auto commit disabled' do
      let(:config) { common_config.merge('enable_auto_commit' => false) }

      it 'should call commit on the consumer' do
        expect(consumer_double).to receive(:commitSync)
        subject.maybe_commit_offset(consumer_double)
      end
      it 'should not throw if a Kafka Exception is encountered' do
        expect(consumer_double).to receive(:commitSync).and_raise(org.apache.kafka.common.errors.TopicAuthorizationException.new(''))
        expect{subject.maybe_commit_offset(consumer_double)}.not_to raise_error
      end

      it 'should throw if Assertion Error is encountered' do
        expect(consumer_double).to receive(:commitSync).and_raise(java.lang.AssertionError.new(''))
        expect{subject.maybe_commit_offset(consumer_double)}.to raise_error(java.lang.AssertionError)
      end
    end

    context 'with auto commit enabled' do
      let(:config) { common_config.merge('enable_auto_commit' => true) }

      it 'should not call commit on the consumer' do
        expect(consumer_double).not_to receive(:commitSync)
        subject.maybe_commit_offset(consumer_double)
      end
    end
  end

  describe '#register' do
    it "should register" do
      expect { subject.register }.to_not raise_error
    end
  end

  describe '#running' do
    let(:q) { Queue.new }
    let(:config) { common_config.merge('client_id' => 'test') }

    before do
      expect(subject).to receive(:create_consumer).once.and_return(consumer_double)
      allow(consumer_double).to receive(:wakeup)
      allow(consumer_double).to receive(:close)
      allow(consumer_double).to receive(:subscribe)
    end

    context 'when running' do
      before do
        polled = false
        allow(consumer_double).to receive(:poll) do
          if polled
            []
          else
            polled = true
            payload
          end
        end

        subject.register
        t = Thread.new do
          sleep(1)
          subject.do_stop
        end
        subject.run(q)
        t.join
      end

      it 'should process the correct number of events' do
        expect(q.size).to eq(10)
      end

      it 'should set the consumer thread name' do
        expect(subject.instance_variable_get('@runner_threads').first.get_name).to eq("kafka-input-worker-test-0")
      end
    end

    context 'when errors are encountered during poll' do
      before do
        raised, polled = false
        allow(consumer_double).to receive(:poll) do
          unless raised
            raised = true
            raise exception
          end
          if polled
            []
          else
            polled = true
            payload
          end
        end

        subject.register
        t = Thread.new do
          sleep 2
          subject.do_stop
        end
        subject.run(q)
        t.join
      end

      context "when a Kafka exception is raised" do
        let(:exception) { org.apache.kafka.common.errors.TopicAuthorizationException.new('Invalid topic') }

        it 'should poll successfully' do
          expect(q.size).to eq(10)
        end
      end

      context "when a StandardError is raised" do
        let(:exception) { StandardError.new('Standard Error') }

        it 'should retry and poll successfully' do
          expect(q.size).to eq(10)
        end
      end

      context "when a java error is raised" do
        let(:exception) { java.lang.AssertionError.new('Fatal assertion') }

        it "should not retry" do
          expect(q.size).to eq(0)
        end
      end
    end
  end

  describe "schema registry parameter verification" do
    let(:base_config) do {
          'schema_registry_url' => 'http://localhost:8081',
          'topics' => ['logstash'],
          'consumer_threads' => 4
    }
    end

    context "schema_registry_url" do
     let(:config) { base_config }

      it "conflict with value_deserializer_class should fail" do
        config['value_deserializer_class'] = 'my.fantasy.Deserializer'
        expect { subject.register }.to raise_error LogStash::ConfigurationError, /Option schema_registry_url prohibit the customization of value_deserializer_class/
      end

      it "conflict with topics_pattern should fail" do
        config['topics_pattern'] = 'topic_.*'
        expect { subject.register }.to raise_error LogStash::ConfigurationError, /Option schema_registry_url prohibit the customization of topics_pattern/
      end
    end

    context 'when kerberos auth is used' do
      ['SASL_SSL', 'SASL_PLAINTEXT'].each do |protocol|
        context "with #{protocol}" do
          ['auto', 'skip'].each do |vsr|
            context "when validata_schema_registry is #{vsr}" do
              let(:config) { base_config.merge({'security_protocol' => protocol,
                                                'schema_registry_validation' => vsr})
              }
              it 'skips verification' do
                expect(subject).not_to receive(:check_for_schema_registry_connectivity_and_subjects)
                expect { subject.register }.not_to raise_error
              end
            end
          end
        end
      end
    end

    context 'when kerberos auth is not used' do
      context "when skip_verify is set to auto" do
        let(:config) { base_config.merge({'schema_registry_validation' => 'auto'})}
        it 'performs verification' do
          expect(subject).to receive(:check_for_schema_registry_connectivity_and_subjects)
          expect { subject.register }.not_to raise_error
        end
      end

      context "when skip_verify is set to default" do
        let(:config) { base_config }
        it 'performs verification' do
          expect(subject).to receive(:check_for_schema_registry_connectivity_and_subjects)
          expect { subject.register }.not_to raise_error
        end
      end

      context "when skip_verify is set to skip" do
        let(:config) { base_config.merge({'schema_registry_validation' => 'skip'})}
        it 'should skip verification' do
          expect(subject).not_to receive(:check_for_schema_registry_connectivity_and_subjects)
          expect { subject.register }.not_to raise_error
        end
      end
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
