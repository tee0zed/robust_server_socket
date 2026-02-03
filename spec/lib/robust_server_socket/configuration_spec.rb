require 'spec_helper'
require './lib/robust_server_socket/configuration'

RSpec.describe RobustServerSocket::Configuration, stub_configuration: false do # rubocop:disable RSpec/MultipleDescribes
  include_context :configuration

  let(:dummy_class) { Class.new { extend RobustServerSocket::Configuration } }

  describe '#configure' do
    it 'yields the configuration object to the block' do
      dummy_class.configure do |config|
        expect(config).to be_a(RobustServerSocket::ConfigStore)
      end
    end
  end

  describe '#configured?' do
    before do
      allow(dummy_class).to receive(:correct_configuration?).and_return(true)
    end

    it 'returns false if not configured' do
      expect(dummy_class.configured?).to be(false)
    end

    it 'returns true if configured' do
      dummy_class.configure { |config| } # rubocop:disable Lint/EmptyBlock
      expect(dummy_class.configured?).to be(true)
    end
  end

  describe '#correct_configuration?' do
    it 'returns false if not configured' do
      dummy_class.configure { |config| } # rubocop:disable Lint/EmptyBlock
      expect(dummy_class.correct_configuration?).to be(false)
    end

    it 'returns true if configured' do
      dummy_class.configure do |c|
        c.allowed_services = ['client']
        c.token_expiration_time = 60
        c.redis_url = 'redis://localhost:6379/0'
        c.redis_pass = 'pass'
        c.private_key = OpenSSL::PKey::RSA.generate(2048).to_pem
      end

      expect(dummy_class.correct_configuration?).to be(true)
    end
  end
end

RSpec.describe RobustServerSocket::ConfigStore do
  subject(:config_store) { described_class.new }

  it 'has attribute allowed_services' do
    config_store.allowed_services = %w[first second]
    expect(config_store.allowed_services).to eq %w[first second]
  end

  it 'has attribute private_key' do
    config_store.private_key = 'private_key'
    expect(config_store.private_key).to eq('private_key')
  end

  it 'has attribute token_expiration_time' do
    config_store.token_expiration_time = 50
    expect(config_store.token_expiration_time).to eq 50
  end
end
