# RobustServerSocket

Gem for inter-service authorization, used in pair with RobustClientSocket

### ⚠️ Not Production Tested (yet) but tested in staging environment

`Not vibecoded`

## WHY

### The Problem

When building microservice architecture, the server side faces:

- **Lack of verification**: How to verify that a request came from a trusted service?
- **Replay attacks**: Intercepted requests can be replayed
- **DDoS attacks**: Need to limit request frequency
- **Boilerplate code**: Repetitive validation logic in every service

#### Even if infrastructure is behind a DMZ in a private network, there is still room for SSRF or OpenRedirect attacks

### The Solution

RobustServerSocket provides:

- **RSA decryption**: Token authenticity verification
- **Client whitelist**: Only authorized services allowed
- **Replay protection**: Blacklist of used tokens in Redis
- **Rate limiting**: Sliding window per-client request limits

## HOW IT WORKS

### Architecture

```
Incoming request with Secure-Token
            │
            v
┌──────────────────────────────┐
│    RobustServerSocket        │
│                              │
│  1. RSA Decrypt              │
│  2. Validate Format          │
│  3. Check Client Whitelist   │
│  4. Check Rate Limit         │
│  5. Check Token Reuse        │
│  6. Check Token Expiration   │
└──────────────┬───────────────┘
               │
      ┌────────┼────────┐
      v                  v
 ✅ Success          ❌ Error
 (continue)         (401/403/429)
```

### Validation Flow

1. **Decryption**: Base64 decode → RSA decrypt with private key
2. **Parsing**: Extract `{client_name}_{timestamp_ms}` from token
3. **Whitelist**: Verify client_name is in `allowed_services`
4. **Rate limit**: Sliding window — check request count within `rate_limit_window_seconds`
5. **Replay check**: Verify token hasn't been used (Redis)
6. **Staleness**: Verify timestamp is current (with ±30s clock skew tolerance)

### Modular System

Checks are enabled via `using_modules`:
- `:client_auth_protection` — client whitelist
- `:replay_attack_protection` — prevent token reuse
- `:rate_limit_protection` — sliding window rate limiting

## 📋 Table of Contents

- [Security Features](#security-features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Error Handling](#error-handling)

## 🔒 Security Features

RobustServerSocket implements a multi-layered protection system for inter-service communications:

### 1. Cryptographic Protection
- **RSA-2048 Encryption**: Uses RSA key pairs with minimum 2048-bit length
- **Key Validation**: Automatic key size verification during configuration

### 2. Access Control
- **Client Whitelist**: Only authorized services can connect, when `:client_auth_protection` module is enabled
- **Name-based Identification**: Each client must be explicitly listed in `allowed_services`

### 3. Replay Attack Protection
- **One-time Tokens**: Used tokens are added to a Redis blacklist, when `:replay_attack_protection` is enabled
- **Staleness Check**: Tokens automatically become invalid after `token_expiration_time`
- **Clock Skew Tolerance**: ±30 seconds (CLOCK_SKEW)
- **Blacklist TTL**: Computed automatically as `token_expiration_time + CLOCK_SKEW`

### 4. Rate Limiting
- **Sliding Window**: When `:rate_limit_protection` is enabled — precise request counting without the burst effect of fixed windows
- **Fail-open Strategy**: If Redis is unavailable, requests are allowed through (for service reliability)
- **Per-client Isolation**: Counter is tracked individually per `client_name`

### 5. SSL Stripping / MITM Protection
- **Enforce HTTPS on server**: All requests should be made over HTTPS to protect tokens from interception
- **Enabled on RobustClientSocket with `ssl_verify: true`**

### 6. Injection Protection
- **Input Validation**: Type, length, and format verification of tokens
- **Maximum Token Length**: 2048 character limit
- **Empty Value Checks**: Rejection of empty or malformed tokens

## 📦 Installation

```ruby
gem 'robust_server_socket'
```

and on the client:
```ruby
gem 'robust_client_socket'
```

## ⚙️ Configuration

Create file `config/initializers/robust_server_socket.rb`:

```ruby
RobustServerSocket.configure do |c|
  c.using_modules = %i[
    client_auth_protection
    replay_attack_protection
    rate_limit_protection
  ]

  # Service private key (RSA-2048 or higher)
  c.private_key = ENV['ROBUST_SERVER_PRIVATE_KEY']

  # Token lifetime in seconds (must match TTL on client side)
  c.token_expiration_time = 10

  # List of allowed services (whitelist)
  # Must match service_name in RobustClientSocket
  c.allowed_services = %w[core payments notifications]

  # Redis for replay_attack_protection and rate_limit_protection
  c.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  c.redis_pass = ENV['REDIS_PASSWORD']

  # rate_limit_protection
  c.rate_limit_max_requests = 100   # max requests per window (default: 100)
  c.rate_limit_window_seconds = 60  # window size in seconds (default: 60)
end

RobustServerSocket.load!
```

### Configuration Options

| Parameter                   | Type    | Required | Default                                                                             | Description                                     |
|-----------------------------|---------|----------|-------------------------------------------------------------------------------------|-------------------------------------------------|
| `private_key`               | String  | ✅       | —                                                                                   | Service private RSA key (RSA-2048 or higher)    |
| `token_expiration_time`     | Integer | ✅       | 10                                                                                  | Token lifetime in seconds                       |
| `allowed_services`          | Array   | ✅       | —                                                                                   | Allowed services whitelist                      |
| `redis_url`                 | String  | ✅       | —                                                                                   | Redis connection URL                            |
| `redis_pass`                | String  | ❌       | nil                                                                                 | Redis password                                  |
| `using_modules`             | Array   | ❌       | `[:client_auth_protection, :rate_limit_protection, :replay_attack_protection]`      | Enabled modules                                 |
| `rate_limit_max_requests`   | Integer | ❌       | 100                                                                                 | Max requests per window                         |
| `rate_limit_window_seconds` | Integer | ❌       | 60                                                                                  | Window size in seconds                          |

> `store_used_token_time` is no longer configurable — computed automatically as `token_expiration_time + 30` (CLOCK_SKEW).

### Compatibility with RobustClientSocket

The token contains a timestamp in **milliseconds**. RobustClientSocket starting from version 0.5.3 must generate:

```ruby
Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
```

The legacy `Time.now.utc.to_i` (seconds) will cause all tokens to be rejected as `stale`.

## 🚀 Usage

### Basic Authorization

```ruby
class ApiController < ApplicationController
  before_action :authenticate_service!

  private

  def authenticate_service!
    token = request.headers['SECURE-TOKEN']&.sub(/^Bearer /, '')
    @current_service = RobustServerSocket::ClientToken.validate!(token)
  rescue RobustServerSocket::ClientToken::InvalidToken
    render json: { error: 'Invalid token' }, status: :unauthorized
  rescue RobustServerSocket::Modules::ClientAuthProtection::UnauthorizedClient
    render json: { error: 'Unauthorized service' }, status: :forbidden
  rescue RobustServerSocket::Modules::ReplayAttackProtection::UsedToken
    render json: { error: 'Token already used' }, status: :unauthorized
  rescue RobustServerSocket::Modules::ReplayAttackProtection::StaleToken
    render json: { error: 'Token expired' }, status: :unauthorized
  rescue RobustServerSocket::RateLimiter::RateLimitExceeded => e
    render json: { error: e.message }, status: :too_many_requests
  end
end
```

### valid? (non-raising)

```ruby
token = request.headers['SECURE-TOKEN']&.sub(/^Bearer /, '')
client_token = RobustServerSocket::ClientToken.new(token)

if client_token.valid?
  client_name = client_token.client
else
  render json: { error: 'Unauthorized' }, status: :unauthorized
end
```

## ❌ Error Handling

### Exception Types

| Exception                                                  | Reason                                    | HTTP Status |
|------------------------------------------------------------|-------------------------------------------|-------------|
| `ClientToken::InvalidToken`                                | Token cannot be decrypted or wrong format | 401         |
| `Modules::ClientAuthProtection::UnauthorizedClient`        | Client not in whitelist                   | 403         |
| `Modules::ReplayAttackProtection::UsedToken`               | Token has already been used               | 401         |
| `Modules::ReplayAttackProtection::StaleToken`              | Token expired or from the future (>30s)   | 401         |
| `RateLimiter::RateLimitExceeded`                           | Rate limit exceeded                       | 429         |

### Centralized Error Handling

```ruby
rescue_from RobustServerSocket::ClientToken::InvalidToken,
            RobustServerSocket::Modules::ReplayAttackProtection::UsedToken,
            RobustServerSocket::Modules::ReplayAttackProtection::StaleToken,
            with: :unauthorized_response

rescue_from RobustServerSocket::Modules::ClientAuthProtection::UnauthorizedClient,
            with: :forbidden_response

rescue_from RobustServerSocket::RateLimiter::RateLimitExceeded,
            with: :rate_limit_response

private

def unauthorized_response(exception)
  render json: { error: 'Authentication failed', message: exception.message }, status: :unauthorized
end

def forbidden_response(exception)
  render json: { error: 'Access denied', message: exception.message }, status: :forbidden
end

def rate_limit_response(exception)
  render json: {
    error: 'Too many requests',
    message: exception.message,
    retry_after: RobustServerSocket.configuration.rate_limit_window_seconds
  }, status: :too_many_requests
end
```

## 🤝 Integration with RobustClientSocket

```ruby
# On client (RobustClientSocket)
RobustClientSocket.configure do |c|
  c.service_name = 'core' # ← Must be in server's allowed_services
  c.keychain = {
    payments: {
      base_uri: 'https://payments.example.com',
      public_key: '-----BEGIN PUBLIC KEY-----...'
    }
  }
end

# On server (RobustServerSocket)
RobustServerSocket.configure do |c|
  c.allowed_services = %w[core]
  c.private_key = '-----BEGIN PRIVATE KEY-----...'
end
```

## 📊 Performance

### Benchmark: 1000 Requests with Token Validation

**Without RobustServerSocket (plain HTTP controller):**
- Real time: ~2.5 seconds
- No token verification, no RSA decryption, no Redis checks

**With RobustServerSocket (full protection):**
- Real time: ~2.77 seconds
- User CPU: 0.23s, System CPU: 0.54s

### Security Overhead Analysis

| Operation              | Time        | % of Request |
|------------------------|-------------|-------------|
| RSA Decryption         | ~0.1–0.2ms  | 3–7%        |
| Redis Token Check      | ~0.05–0.1ms | 2–3%        |
| Rate Limiting          | ~0.02–0.05ms| 1%          |
| Whitelist Validation   | <0.01ms     | <1%         |
| **Total Overhead**     | **~0.2–0.4ms** | **~10–15%** |

Up to 1000 req/s — excellent performance. Higher loads require Redis Sentinel/Cluster.

## 🗺️ TODO

- [ ] **Per-client rate limit keys** — configurable individual limits per `client_name` instead of a single global limit

## 📚 Additional Resources

- [RobustClientSocket](https://github.com/tee0zed/robust_client_socket)
- [RSA encryption best practices](https://www.openssl.org/docs/)
- [Redis security guide](https://redis.io/topics/security)

## 📝 License

See [MIT-LICENSE](MIT-LICENSE) file

## 🐛 Bugs and Suggestions

Report issues via GitHub issues, or directly at Telegram @cruel_mango or email tee0zed@gmail.com
