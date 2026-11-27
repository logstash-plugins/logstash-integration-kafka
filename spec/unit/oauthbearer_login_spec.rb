# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"
require "logstash/outputs/kafka"
require "base64"
require "json"
require "tempfile"
require "uri"

# These specs use the real Kafka client and a token endpoint that runs in this process.
# The client logs in when it is created, so they need no broker.
# They catch a login failure, which the specs that mock the client cannot see.
describe "SASL/OAUTHBEARER login" do
  let(:allowed_urls_property) { "org.apache.kafka.sasl.oauthbearer.allowed.urls" }
  let(:allowed_files_property) { "org.apache.kafka.sasl.oauthbearer.allowed.files" }

  def unsecured_jwt(claims)
    [{ 'alg' => 'none', 'typ' => 'JWT' }.to_json, claims.to_json, 'signature'].
      map { |part| Base64.urlsafe_encode64(part, padding: false) }.join('.')
  end

  before(:all) do
    @requests = requests = []
    now = Time.now.to_i
    access_token = unsecured_jwt('sub' => 'logstash', 'iat' => now, 'exp' => now + 3600, 'scope' => 'kafka.read')
    response = { 'access_token' => access_token, 'token_type' => 'Bearer', 'expires_in' => 3600 }.to_json.to_java_bytes

    @token_endpoint = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress.new("127.0.0.1", 0), 0)
    @token_endpoint.createContext("/token") do |exchange|
      requests << {
        :authorization => exchange.getRequestHeaders.getFirst("Authorization"),
        :params => URI.decode_www_form(String.from_java_bytes(exchange.getRequestBody.readAllBytes)).to_h
      }
      exchange.getResponseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, response.length)
      body = exchange.getResponseBody
      body.write(response)
      body.close
    end
    @token_endpoint.start
    @token_endpoint_url = "http://127.0.0.1:#{@token_endpoint.getAddress.getPort}/token"
  end

  after(:all) { @token_endpoint.stop(0) }

  let(:assertion) { unsecured_jwt('iss' => 'https://issuer.example.com', 'sub' => 'logstash', 'exp' => Time.now.to_i + 3600) }
  let(:assertion_file) { Tempfile.new('assertion').tap { |file| file.write(assertion); file.flush } }

  let(:oauth_config) {{
    'bootstrap_servers' => '127.0.0.1:1',
    'security_protocol' => 'SASL_PLAINTEXT',
    'sasl_mechanism' => 'OAUTHBEARER',
    'sasl_jaas_config' => 'org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;',
    'sasl_login_callback_handler_class' => 'org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler',
    'sasl_oauthbearer_token_endpoint_url' => @token_endpoint_url,
    'sasl_oauthbearer_client_credentials_client_id' => 'logstash-client',
    'sasl_oauthbearer_scope' => 'kafka.read'
  }}

  before do
    @requests.clear
    java.lang.System.setProperty(allowed_urls_property, @token_endpoint_url)
    java.lang.System.setProperty(allowed_files_property, assertion_file.path)
  end

  after do
    java.lang.System.clearProperty(allowed_urls_property)
    java.lang.System.clearProperty(allowed_files_property)
    assertion_file.close!
  end

  let(:client_assertion_request) {{
    'grant_type' => 'client_credentials',
    'client_assertion_type' => 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
    'client_assertion' => assertion,
    'client_id' => 'logstash-client',
    'scope' => 'kafka.read'
  }}

  context 'with the output' do
    def register_and_close(config)
      output = LogStash::Outputs::Kafka.new({ 'topic_id' => 'test' }.merge(config))
      output.register
      output.close
    end

    it "logs in with a client assertion file" do
      register_and_close(oauth_config.merge('sasl_oauthbearer_assertion_file' => assertion_file.path))

      expect(@requests.size).to eq(1)
      expect(@requests.first[:authorization]).to be_nil
      expect(@requests.first[:params]).to eq(client_assertion_request)
    end

    it "logs in with a client secret" do
      register_and_close(oauth_config.merge('sasl_oauthbearer_client_credentials_client_secret' => 'client-secret'))

      expect(@requests.size).to eq(1)
      expect(@requests.first[:authorization]).to eq("Basic " + Base64.strict_encode64("logstash-client:client-secret"))
      expect(@requests.first[:params]).to eq('grant_type' => 'client_credentials', 'scope' => 'kafka.read')
    end
  end

  context 'with the input' do
    it "logs in with a client assertion file" do
      input = LogStash::Inputs::Kafka.new({ 'topics' => ['logstash'] }.merge(oauth_config).
        merge('sasl_oauthbearer_assertion_file' => assertion_file.path))
      input.send(:create_consumer, 'logstash-0', nil).close

      expect(@requests.size).to eq(1)
      expect(@requests.first[:authorization]).to be_nil
      expect(@requests.first[:params]).to eq(client_assertion_request)
    end
  end

  context 'with another SASL mechanism' do
    it "does not pass the OAuth login settings to the client" do
      props = nil
      expect(org.apache.kafka.clients.producer.KafkaProducer).to receive(:new) { |p| props = p; nil }
      LogStash::Outputs::Kafka.new(
        'topic_id' => 'test',
        'security_protocol' => 'SASL_PLAINTEXT',
        'sasl_mechanism' => 'PLAIN',
        'sasl_jaas_config' => "org.apache.kafka.common.security.plain.PlainLoginModule required username='user' password='password';"
      ).register

      expect(props.stringPropertyNames.to_a.grep(/\Asasl\.oauthbearer\.(jwt|client|assertion)\./)).to be_empty
    end

    it "rejects the OAuth login settings in the output" do
      output = LogStash::Outputs::Kafka.new(
        'topic_id' => 'test',
        'sasl_oauthbearer_scope' => 'kafka.read',
        'sasl_oauthbearer_assertion_algorithm' => 'RS256'
      )

      expect { output.register }.to raise_error(LogStash::ConfigurationError) do |error|
        expect(error.message).to include("sasl_mechanism => 'OAUTHBEARER'", 'sasl_oauthbearer_scope', 'sasl_oauthbearer_assertion_algorithm')
      end
    end

    it "rejects the OAuth login settings in the input" do
      input = LogStash::Inputs::Kafka.new(
        'topics' => ['logstash'],
        'sasl_mechanism' => 'PLAIN',
        'sasl_oauthbearer_assertion_file' => assertion_file.path
      )

      expect { input.register }.to raise_error(LogStash::ConfigurationError) do |error|
        expect(error.message).to include("sasl_mechanism => 'OAUTHBEARER'", 'sasl_oauthbearer_assertion_file')
      end
    end

    it "accepts the older OAuth settings" do
      expect(org.apache.kafka.clients.producer.KafkaProducer).to receive(:new).with(hash_including(
        'sasl.oauthbearer.token.endpoint.url' => 'https://auth.example.com/token',
        'sasl.oauthbearer.scope.claim.name' => 'custom_scope'
      ))
      LogStash::Outputs::Kafka.new(
        'topic_id' => 'test',
        'security_protocol' => 'SASL_PLAINTEXT',
        'sasl_mechanism' => 'PLAIN',
        'sasl_jaas_config' => "org.apache.kafka.common.security.plain.PlainLoginModule required username='user' password='password';",
        'sasl_oauthbearer_token_endpoint_url' => 'https://auth.example.com/token',
        'sasl_oauthbearer_scope_claim_name' => 'custom_scope'
      ).register
    end
  end
end
