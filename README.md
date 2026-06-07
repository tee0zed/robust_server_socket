# RobustServerSocket

Gem для межсервисной аутентификации, используется в паре с RobustClientSocket

### ⚠️ Not Production Tested (yet) but tested in staging environment

`Not vibecoded`

## ПОЧЕМУ (WHY)

### Проблема

При построении микросервисной архитектуры серверная сторона сталкивается с:

- **Отсутствием верификации**: Как проверить, что запрос пришёл от доверенного сервиса?
- **Replay-атаками**: Перехваченные запросы могут быть повторены
- **DDoS-атаками**: Необходимость ограничения частоты запросов
- **Boilerplate кодом**: Повторяющаяся логика валидации в каждом сервисе

#### Даже если инфраструктура находится за DMZ, в своей локальной сети, остаётся пространство для SSRF или OpenRedirect атак

### Решение

RobustServerSocket предоставляет:

- **RSA-дешифрование**: Проверка подлинности токенов
- **Whitelist клиентов**: Только разрешённые сервисы
- **Защиту от replay**: Блэклист использованных токенов в Redis
- **Rate limiting**: Скользящее окно запросов на клиента

## КАК ЭТО РАБОТАЕТ (HOW)

### Архитектура

```
Входящий запрос с Secure-Token
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

### Поток валидации

1. **Расшифровка**: Base64 decode → RSA decrypt с приватным ключом
2. **Парсинг**: Извлечение `{client_name}_{timestamp_ms}` из токена
3. **Whitelist**: Проверка client_name в `allowed_services`
4. **Rate limit**: Скользящее окно — проверка количества запросов за `rate_limit_window_seconds`
5. **Replay check**: Проверка, что токен не использован (Redis)
6. **Staleness**: Проверка timestamp на актуальность (с допуском ±30 секунд на рассинхрон часов)

### Модульная система

Проверки подключаются через `using_modules`:
- `:client_auth_protection` — whitelist клиентов
- `:replay_attack_protection` — защита от повторного использования токена
- `:rate_limit_protection` — rate limiting по скользящему окну

## 📋 Содержание

- [Функции безопасности](#функции-безопасности)
- [Установка](#установка)
- [Конфигурация](#конфигурация)
- [Использование](#использование)
- [Обработка ошибок](#обработка-ошибок)

## 🔒 Функции безопасности

RobustServerSocket реализует многоуровневую систему защиты для межсервисных коммуникаций:

### 1. Криптографическая защита
- **RSA-2048 шифрование**: Используется пара ключей RSA с минимальной длиной 2048 бит
- **Валидация ключей**: Автоматическая проверка размера ключа при конфигурации

### 2. Контроль доступа
- **Whitelist клиентов**: Только авторизованные сервисы могут подключаться, при включенном модуле `:client_auth_protection`
- **Идентификация по имени**: Каждый клиент должен быть явно указан в `allowed_services`

### 3. Защита от перехвата токенов (replay-attack)
- **Защита от replay-attack**: использованные токены добавляются в черный список, при включенном модуле `:replay_attack_protection`
- **Staleness**: Токены автоматически становятся недействительными после истечения `token_expiration_time`
- **Допуск на рассинхрон часов**: ±30 секунд (CLOCK_SKEW)
- **TTL блэклиста**: вычисляется автоматически как `token_expiration_time + CLOCK_SKEW`

### 4. Rate limiting
- **Скользящее окно**: при включенном модуле `:rate_limit_protection` — точный подсчёт запросов без граничного burst-эффекта фиксированного окна
- **Fail-open стратегия**: если Redis недоступен, запросы пропускаются (для надёжности сервиса)
- **Изоляция по клиентам**: лимит считается отдельно для каждого `client_name`

### 5. Защита от SSL stripping MITM attack
- **Принудительное HTTPS на сервере**: Все запросы должны быть совершены по HTTPS, чтобы защитить токены от перехвата
- **Включается на RobustClientSocket, ключём `ssl_verify: true`**

## 📦 Установка

```ruby
gem 'robust_server_socket'
```

и на клиенте:
```ruby
gem 'robust_client_socket'
```

## ⚙️ Конфигурация

Создайте файл `config/initializers/robust_server_socket.rb`:

```ruby
RobustServerSocket.configure do |c|
  c.using_modules = %i[
    client_auth_protection
    replay_attack_protection
    rate_limit_protection
  ]

  # Приватный ключ сервиса (RSA-2048 или выше)
  c.private_key = ENV['ROBUST_SERVER_PRIVATE_KEY']

  # Время жизни токена в секундах (должно совпадать с TTL на клиенте)
  c.token_expiration_time = 10

  # Список разрешённых сервисов (whitelist)
  # Должен совпадать с service_name RobustClientSocket клиента
  c.allowed_services = %w[core payments notifications]

  # Redis для replay_attack_protection и rate_limit_protection
  c.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  c.redis_pass = ENV['REDIS_PASSWORD']

  # rate_limit_protection
  c.rate_limit_max_requests = 100   # максимум запросов в окне (по умолчанию: 100)
  c.rate_limit_window_seconds = 60  # размер окна в секундах (по умолчанию: 60)
end

RobustServerSocket.load!
```

### Опции конфигурации

| Параметр                    | Тип     | Обязательный | Default                                                                             | Описание                                        |
|-----------------------------|---------|-------------|-------------------------------------------------------------------------------------|-------------------------------------------------|
| `private_key`               | String  | ✅          | —                                                                                   | Приватный RSA ключ сервиса (RSA-2048 или выше)  |
| `token_expiration_time`     | Integer | ✅          | 10                                                                                  | Время жизни токена в секундах                   |
| `allowed_services`          | Array   | ❌          | —                                                                                   | Список разрешённых сервисов (whitelist)         |
| `redis_url`                 | String  | ✅          | —                                                                                   | URL для подключения к Redis                     |
| `redis_pass`                | String  | ❌          | nil                                                                                 | Пароль для Redis                                |
| `using_modules`             | Array   | ❌          | `[:client_auth_protection, :rate_limit_protection, :replay_attack_protection]`      | Используемые модули                             |
| `rate_limit_max_requests`   | Integer | ❌          | 100                                                                                 | Максимальное количество запросов в окне         |
| `rate_limit_window_seconds` | Integer | ❌          | 60                                                                                  | Размер временного окна в секундах               |

> `store_used_token_time` больше не является конфигурируемым — вычисляется автоматически как `token_expiration_time + 30` (CLOCK_SKEW).

### Совместимость с RobustClientSocket

Токен содержит таймстамп в **миллисекундах**. RobustClientSocket начиная с версии X.X должен генерировать:

```ruby
Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
```

Устаревший `Time.now.utc.to_i` (секунды) приведёт к тому, что все токены будут отклонены как `stale`.

## 🚀 Использование

### Базовая авторизация

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

### valid? (не рейзит)

```ruby
token = request.headers['SECURE-TOKEN']&.sub(/^Bearer /, '')
client_token = RobustServerSocket::ClientToken.new(token)

if client_token.valid?
  client_name = client_token.client
else
  render json: { error: 'Unauthorized' }, status: :unauthorized
end
```

## ❌ Обработка ошибок

### Типы исключений

| Исключение                                              | Причина                                      | HTTP статус |
|---------------------------------------------------------|----------------------------------------------|-------------|
| `ClientToken::InvalidToken`                             | Токен не расшифрован или неверный формат     | 401         |
| `Modules::ClientAuthProtection::UnauthorizedClient`     | Клиент не в whitelist                        | 403         |
| `Modules::ReplayAttackProtection::UsedToken`            | Токен уже был использован                    | 401         |
| `Modules::ReplayAttackProtection::StaleToken`           | Токен истёк или из будущего (>30s)           | 401         |
| `RateLimiter::RateLimitExceeded`                        | Превышен лимит запросов                      | 429         |

### Централизованная обработка

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

## 🤝 Интеграция с RobustClientSocket

```ruby
# На клиенте (RobustClientSocket)
RobustClientSocket.configure do |c|
  c.service_name = 'core' # ← Должно быть в allowed_services сервера
  c.keychain = {
    payments: {
      base_uri: 'https://payments.example.com',
      public_key: '-----BEGIN PUBLIC KEY-----...'
    }
  }
end

# На сервере (RobustServerSocket)
RobustServerSocket.configure do |c|
  c.allowed_services = %w[core]
  c.private_key = '-----BEGIN PRIVATE KEY-----...'
end
```

## 📚 Дополнительные ресурсы

- [RobustClientSocket](https://github.com/tee0zed/robust_client_socket)
- [RSA encryption best practices](https://www.openssl.org/docs/)
- [Redis security guide](https://redis.io/topics/security)

## 📝 Лицензия

См. файл [MIT-LICENSE](MIT-LICENSE)

## 🐛 Баги и предложения

Сообщайте о багах через ишью, или напрямую тг @cruel_mango или email tee0zed@gmail.com
