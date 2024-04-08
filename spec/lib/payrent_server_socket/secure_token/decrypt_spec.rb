require 'spec_helper'
require './lib/payrent_server_socket/secure_token/decrypt.rb'

RSpec.describe PayrentServerSocket::SecureToken::Decrypt, stub_configuration: true do
  include_context :configuration

  describe '.call' do
    let(:public_key) { private_key.public_key }
    let(:original_text) { "Hello, world!" }
    let(:encrypted_token) { Base64.strict_encode64(public_key.public_encrypt(original_text)) }
    let(:fake_token) { "Fake Token" }

    it 'decrypts a token correctly' do
      decrypted_text = described_class.call(encrypted_token)
      expect(decrypted_text).to eq(original_text)
    end

    it 'returns nil when decryption fails' do
      expect{ described_class.call(fake_token) }.to raise_error(PayrentServerSocket::SecureToken::InvalidToken)
    end
  end

  describe '#private_key' do
    it 'returns an RSA private key' do
      expect(described_class.send(:private_key)).to be_a(OpenSSL::PKey::RSA)
    end
  end
end
