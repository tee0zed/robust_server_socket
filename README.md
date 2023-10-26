# PayrentServerSocket

Gem for in-service Authorization for using with PayrentClientSocket

## Usage

'config/initializers/payrent_server_socket.rb'

```ruby
PayrentServerSocket.configure do |c|
  c.private_key = '-----PRIVATE KEY-----[...]' # private key of the service, from pair of keys by PayrentServerSocket
  c.token_expiration_time = 10.minutes # time in seconds for token expiration
  c.allowed_services = %w(core) # list of services allowed to use this service, must be same as service name in keychain in PayrentClientSocket
  # so if we have 
  # PayrentClientSocket.configure do |c|
  # c.keychain = {
  #   core: { <<< service name
  #           base_uri: 'https://core.payrent.com',
  #           public_key: '-----BEGIN PUBLIC KEY-----[...]'
  #   },
  # we should add 'core' to allowed_services
end
  
PayrentServerSocket.load!
```

and then

```ruby
token = PayrentServerSocket::ClientToken.call(token) # token - is a Bearer from secure-token header
token.valid? #Boolean  check if token is not expired and client is allowed to use this service, main authorization check
token.client #String  name of the client
```
