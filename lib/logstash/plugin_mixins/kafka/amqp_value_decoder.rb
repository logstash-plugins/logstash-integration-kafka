require 'logstash/timestamp'

module LogStash module PluginMixins module Kafka
  # Decodes a header value holding a single AMQP 1.0 primitive, the way Azure Event Hubs hands the
  # application properties of AMQP-produced events to Kafka consumers.
  # See https://docs.oasis-open.org/amqp/core/v1.0/os/amqp-core-types-v1.0-os.html#section-primitive-type-definitions
  module AmqpValueDecoder
    FIXED_WIDTH = {
      0x50 => [1, 'C'],  # ubyte
      0x51 => [1, 'c'],  # byte
      0x52 => [1, 'C'],  # smalluint
      0x53 => [1, 'C'],  # smallulong
      0x54 => [1, 'c'],  # smallint
      0x55 => [1, 'c'],  # smalllong
      0x60 => [2, 'n'],  # ushort
      0x61 => [2, 's>'], # short
      0x70 => [4, 'N'],  # uint
      0x71 => [4, 'l>'], # int
      0x72 => [4, 'g'],  # float
      0x80 => [8, 'Q>'], # ulong
      0x81 => [8, 'q>'], # long
      0x82 => [8, 'G'],  # double
    }.freeze

    CONSTANTS = {
      0x40 => nil,   # null
      0x41 => true,  # true
      0x42 => false, # false
      0x43 => 0,     # uint0
      0x44 => 0,     # ulong0
    }.freeze

    # One-byte (8) and four-byte (32) length prefixes of binary, string and symbol.
    VARIABLE_WIDTH = {
      0xa0 => [1, 'C'], # vbin8
      0xa1 => [1, 'C'], # str8-utf8
      0xa3 => [1, 'C'], # sym8
      0xb0 => [4, 'N'], # vbin32
      0xb1 => [4, 'N'], # str32-utf8
      0xb3 => [4, 'N'], # sym32
    }.freeze

    module_function

    # Returns [value] when bytes are exactly one supported AMQP primitive, nil otherwise
    # (composite and decimal types, trailing bytes, truncated values, invalid UTF-8).
    def decode(bytes)
      bytes = bytes.b
      return nil if bytes.empty?
      code = bytes.getbyte(0)
      payload = bytes.byteslice(1, bytes.bytesize - 1)

      if CONSTANTS.key?(code)
        return payload.empty? ? [CONSTANTS[code]] : nil
      end

      if (width, directive = FIXED_WIDTH[code])
        return payload.bytesize == width ? [payload.unpack1(directive)] : nil
      end

      case code
      when 0x56 # boolean
        return payload.bytesize == 1 && payload.getbyte(0) <= 1 ? [payload.getbyte(0) == 1] : nil
      when 0x73 # char, one UTF-32 code point
        return nil unless payload.bytesize == 4
        char = payload.force_encoding(Encoding::UTF_32BE)
        return char.valid_encoding? ? [char.encode(Encoding::UTF_8)] : nil
      when 0x83 # timestamp, milliseconds since the Unix epoch
        return nil unless payload.bytesize == 8
        millis = payload.unpack1('q>')
        return [LogStash::Timestamp.at(millis / 1000, (millis % 1000) * 1000)]
      when 0x98 # uuid
        return nil unless payload.bytesize == 16
        return [payload.unpack1('H*').sub(/\A(\h{8})(\h{4})(\h{4})(\h{4})(\h{12})\z/, '\1-\2-\3-\4-\5')]
      end

      if (prefix, directive = VARIABLE_WIDTH[code])
        return nil if payload.bytesize < prefix
        length = payload.byteslice(0, prefix).unpack1(directive)
        return nil unless payload.bytesize == prefix + length
        value = payload.byteslice(prefix, length).force_encoding(Encoding::UTF_8)
        # binary is kept only when it is text, matching the UTF-8 rule for plain headers
        return value.valid_encoding? ? [value] : nil
      end

      nil
    end
  end
end end end
