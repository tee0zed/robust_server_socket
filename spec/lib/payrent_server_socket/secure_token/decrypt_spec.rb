require 'spec_helper'
require 'base64'
require 'openssl'
require './lib/payrent_server_socket/secure_token/decrypt.rb'

RSpec.describe PayrentServerSocket::SecureToken::Decrypt do
  let(:configuration) { instance_double(PayrentServerSocket::ConfigStore, private_key: private_key) }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }

  before do
    allow(PayrentServerSocket).to receive(:configuration).and_return(configuration)
  end

  describe '.call' do
    let(:public_key) { private_key.public_key }
    let(:original_text) { "Hello, world!" }
    let(:encrypted_token) { Base64.strict_encode64(public_key.public_encrypt(original_text)) }
    let(:fake_token) { Base64.strict_encode64("Fake Token") }

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
