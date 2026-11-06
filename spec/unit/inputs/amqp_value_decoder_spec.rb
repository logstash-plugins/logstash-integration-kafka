# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/plugin_mixins/kafka/amqp_value_decoder"

describe LogStash::PluginMixins::Kafka::AmqpValueDecoder do
  # Byte sequences produced by the Apache Qpid Proton-J AMQP encoder
  def decode(hex)
    described_class.decode([hex].pack('H*'))
  end

  {
    'null'       => ['40', nil],
    'true'       => ['41', true],
    'false'      => ['42', false],
    'boolean'    => ['5601', true],
    'uint0'      => ['43', 0],
    'ubyte'      => ['50c8', 200],
    'smallint'   => ['5402', 2],
    'negative smallint' => ['54fb', -5],
    'int'        => ['7100011170', 70000],
    'smalllong'  => ['552a', 42],
    'long'       => ['81000000012a05f200', 5000000000],
    'short'      => ['61fffe', -2],
    'ulong'      => ['80ffffffffffffffff', 18446744073709551615],
    'float'      => ['723e800000', 0.25],
    'double'     => ['823ff8000000000000', 1.5],
    'char'       => ['73000000e9', 'é'],
    'str8'       => ['a104496e666f', 'Info'],
    'multi-byte str8' => ['a110ceb1cebdceb4cf81ceb5ceb120e282ac', 'ανδρεα €'],
    'sym8'       => ['a303616263', 'abc'],
    'vbin8'      => ['a00362696e', 'bin'],
    'uuid'       => ['983f2a9c1e7b4d4e8a9c215d6e7f8a9b0c', '3f2a9c1e-7b4d-4e8a-9c21-5d6e7f8a9b0c'],
  }.each do |type, (hex, expected)|
    it "decodes #{type}" do
      expect(decode(hex)).to eq([expected])
    end
  end

  it "decodes str32" do
    expect(decode('b10000012c' + '78' * 300)).to eq(['x' * 300])
  end

  it "decodes timestamp as a LogStash::Timestamp" do
    value = decode('83000001a0ed093a7b').first
    expect(value).to be_a(LogStash::Timestamp)
    expect(value.to_iso8601).to eq('2026-09-29T12:00:00.123Z')
  end

  it "returns decoded strings as UTF-8" do
    expect(decode('a104496e666f').first.encoding).to eq(Encoding::UTF_8)
  end

  {
    'empty value'         => '',
    'plain text'          => '4a6f686e', # "John": 0x4a is not an AMQP primitive constructor
    'trailing bytes'      => '540200',
    'truncated int'       => '710001',
    'truncated str8'      => 'a1054162',
    'str8 with invalid UTF-8' => 'a102c328',
    'vbin8 that is not text'  => 'a002fffe',
    'list'                => 'c0050254015402',
    'decimal32'           => '7400000000',
  }.each do |description, hex|
    it "returns nil for #{description}" do
      expect(decode(hex)).to be_nil
    end
  end
end
