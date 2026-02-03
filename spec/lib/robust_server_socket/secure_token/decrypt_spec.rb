require 'spec_helper'
require './lib/robust_server_socket/secure_token/decrypt'

RSpec.describe RobustServerSocket::SecureToken::Decrypt, stub_configuration: true do
  include_context :configuration

  describe '.call' do
    let(:original_text) { 'Hello, world!' }
    let(:encrypted_token) { ::Base64.strict_encode64(private_key.public_encrypt(original_text, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }
    let(:fake_token) { 'Fake Token' }

    it 'decrypts a token correctly' do
      decrypted_text = described_class.call(encrypted_token)
      expect(decrypted_text).to eq(original_text)
    end

    it 'returns nil when decryption fails' do
      expect { described_class.call(fake_token) }.to raise_error(RobustServerSocket::SecureToken::InvalidToken)
    end
  end

  describe '#private_key' do
    it 'returns an RSA private key' do
      expect(described_class.send(:private_key)).to be_a(OpenSSL::PKey::RSA)
    end
  end
end
