# encoding: utf-8
require 'logstash-integration-kafka_jars'

describe "[DOCS]" do

  let(:docs_files) do
    ['index.asciidoc', 'input-kafka.asciidoc', 'output-kafka.asciidoc'].map { |name| File.join('docs', name) }
  end

  let(:kafka_version_properties) do
    loader = java.lang.Thread.currentThread.getContextClassLoader
    version = loader.getResource('kafka/kafka-version.properties')
    fail "kafka-version.properties missing" unless version
    properties = java.util.Properties.new
    properties.load version.openStream
    properties
  end

  it 'is sync-ed with Kafka client version' do
    version = kafka_version_properties.get('version') # e.g. '2.5.1'

    fails = docs_files.map do |file|
      if line = File.readlines(file).find { |line| line.index(':kafka_client:') }
        puts "found #{line.inspect} in #{file}" if $VERBOSE # e.g. ":kafka_client: 2.5\n"
        if !version.start_with?(line.strip.split[1])
          "documentation at #{file} is out of sync with kafka-clients version (#{version.inspect}), detected line: #{line.inspect}"
        else
          nil
        end
      end
    end

    fail "\n" + fails.join("\n") if fails.flatten.any?
  end

end
