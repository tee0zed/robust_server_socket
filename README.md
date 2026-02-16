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
- **Rate limiting**: Ограничение запросов на клиента

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
2. **Парсинг**: Извлечение `{client_name}_{timestamp}` из токена
3. **Whitelist**: Проверка client_name в `allowed_services`
4. **Rate limit**: Проверка количества запросов в окне
5. **Replay check**: Проверка, что токен не использован (Redis)
6. **Staleness**: Проверка timestamp на актуальность

### Модульная система

Проверки подключаются через `using_modules`:
- `:client_auth_protection` — whitelist клиентов
- `:replay_attack_protection` — защита от повторного использования
- `:dos_attack_protection` — rate limiting

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
- **Защита от replay-attack**: использованные токены добавляются в черный список и имеют время жизни, при включенном модуле `:replay_attack_protection`
- **Staleness**: Токены автоматически становятся недействительными после истечения времени
- **Blacklisting использованных токенов**: Redis как хранилище черного списка
- **Настраиваемое время жизни токенов в черном списке**: по умолчанию 10 минут
- **Настраиваемое ttl токена**: Должно быть в окно ответа между серверами, по умолчанию 10сек

### 4. Защита от DoS
- **Защита от DDoS**: Ограничение количества запросов от каждого клиента, при включенном модуле `:dos_attack_protection`
- **Sliding window**: Распределение запросов во времени
- **Fail-open стратегия**: Если Redis недоступен, запросы пропускаются (для надёжности)

-
### 5. Защита от SSL stripping MITM attack
- **Принудительное HTTPS на сервере**: Все запросы должны быть совершены по HTTPS, чтобы защитить токены от перехвата
- **Включается на RobustClientSoket, ключём `ssl_verify: true`**

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
    :client_auth_protection
    :replay_attack_protection
    :dos_attack_protection
  ]
  
  # Приватный ключ сервиса (RSA-2048 или выше)
  c.private_key = ENV['ROBUST_SERVER_PRIVATE_KEY']
  c.token_expiration_time = 3
  
  # Список разрешённых сервисов (whitelist)
  # Должен совпадать с именами RobustClientSocket клиента
  # Для client_auth_protection
  c.allowed_services = %w[core payments notifications]
  
  # Redis для работы replay_attack_protection и ddos_attack_protection
  c.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  c.redis_pass = ENV['REDIS_PASSWORD']

  # ddos_attack_protection
  # Максимальное количество запросов в окне времени (по умолчанию: 100)
  c.rate_limit_max_requests = 100
  # Размер временного окна в секундах (по умолчанию: 60)
  c.rate_limit_window_seconds = 60
end

# Загрузка конфигурации с валидацией
RobustServerSocket.load!
```
`using_modules` - это используемые модули, добавление или удаление которых изменит поведение гема.

### Опции конфигурации сервиса

| Параметр                    | Тип | Обязательный | Default                                                                      | Описание                                        |
|-----------------------------|-----|-------------|------------------------------------------------------------------------------|-------------------------------------------------|
| `private_key`               | String | ✅ | -                                                                            | Приватный RSA ключ сервиса (RSA-2048 или выше)  |
| `token_expiration_time`     | Integer | ✅ | 10                                                                           | Время жизни токена в секундах                   |
| `store_used_token_time`     | Integer | ✅ | 600                                                                          | Время жизни токена в блеклисте в секундах       |
| `allowed_services`          | Array | ❌ | -                                                                            | Список разрешённых сервисов (whitelist)         |
| `redis_url`                 | String | ✅ | -                                                                            | URL для подключения к Redis                     |
| `using_modules`             | Array | ❌ | [:client_auth_protection, :replay_attack_protection, :dos_attack_protection] | Используемые модули                             |
| `redis_pass`                | String | ❌ | nil                                                                          | Пароль для Redis (если требуется)               |
| `rate_limit_max_requests`   | Integer | ❌ | 100                                                                          | Максимальное количество запросов в окне времени |
| `rate_limit_window_seconds` | Integer | ❌ | 60                                                                           | Размер временного окна в секундах               |

## 🚀 Использование

### Базовая авторизация

```ruby
# В контроллере или middleware
class ApiController < ApplicationController
  before_action :authenticate_service!
  
  private
  
  def authenticate_service!
    # Хедер, прописанный в RobustClientSocket (SECURE-TOKEN default)
    token = request.headers['SECURE-TOKEN']&.sub(/^Bearer /, '')
    
    @current_service = RobustServerSocket::ClientToken.validate!(token) # bang method (рейзит ошибки)
  rescue RobustServerSocket::ClientToken::InvalidToken
    render json: { error: 'Invalid token' }, status: :unauthorized
  rescue RobustServerSocket::ClientToken::UnauthorizedClient
    render json: { error: 'Unauthorized service' }, status: :forbidden
  rescue RobustServerSocket::ClientToken::UsedToken
    render json: { error: 'Token already used' }, status: :unauthorized
  rescue RobustServerSocket::ClientToken::StaleToken
    render json: { error: 'Token expired' }, status: :unauthorized
  rescue RobustServerSocket::RateLimiter::RateLimitExceeded => e
    render json: { error: e.message }, status: :too_many_requests
  end
  
  def authenticate_service
    token = request.headers['SECURE-TOKEN']&.sub(/^Bearer /, '')
    @current_service = RobustServerSocket::ClientToken.valid?(token) # не рейзит
    
    if @current_service
      # Токен валиден
    else
      # Токен невалиден
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
```

### Расширенное использование

```ruby
# Создание объекта токена
token_string = request.headers['Authorization']&.sub(/^Bearer /, '')
client_token = RobustServerSocket::ClientToken.new(token_string)

# Проверка валидности (возвращает true/false)
if client_token.valid?
  # Получение имени клиента
  client_name = client_token.client
  puts "Authorized client: #{client_name}"
else
  # Токен невалиден
  render json: { error: 'Unauthorized' }, status: :unauthorized
end

# Быстрая валидация с исключениями
begin
  service_token = RobustServerSocket::ClientToken.validate!(token_string)
  client_name = service_token.client
rescue => e
  # Обработка специфичных ошибок
end
```

## ❌ Обработка ошибок

### Типы исключений

| Исключение | Причина | HTTP статус | Действие |
|-----------|---------|-------------|----------|
| `InvalidToken` | Токен не может быть расшифрован или имеет неверный формат | 401 | Проверьте корректность токена и ключей |
| `UnauthorizedClient` | Клиент не в whitelist | 403 | Добавьте клиента в `allowed_services` |
| `UsedToken` | Токен уже был использован | 401 | Клиент должен запросить новый токен |
| `StaleToken` | Токен истёк | 401 | Клиент должен запросить новый токен |
| `RateLimitExceeded` | Превышен лимит запросов | 429 | Клиент должен подождать или ретраить позже |

### Централизованная обработка

```ruby
# В ApplicationController
rescue_from RobustServerSocket::ClientToken::InvalidToken,
            RobustServerSocket::ClientToken::UsedToken,
            RobustServerSocket::ClientToken::StaleToken,
            with: :unauthorized_response

rescue_from RobustServerSocket::ClientToken::UnauthorizedClient,
            with: :forbidden_response

rescue_from RobustServerSocket::RateLimiter::RateLimitExceeded,
            with: :rate_limit_response

private

def unauthorized_response(exception)
  render json: {
    error: 'Authentication failed',
    message: exception.message,
    type: exception.class.name
  }, status: :unauthorized
end

def forbidden_response(exception)
  render json: {
    error: 'Access denied',
    message: exception.message,
    type: exception.class.name
  }, status: :forbidden
end

def rate_limit_response(exception)
  render json: {
    error: 'Too many requests',
    message: exception.message,
    type: exception.class.name,
    retry_after: RobustServerSocket.configuration.rate_limit_window_seconds
  }, status: :too_many_requests
end
```

## 🤝 Интеграция с RobustClientSocket

Для полноценной работы необходимо настроить клиентскую часть:

```ruby
# На клиенте (RobustClientSocket)
RobustClientSocket.configure do |c|
  c.service_name = 'core' # ← Должно быть в allowed_services сервера
  c.keychain = {
    payments: {
      base_uri: 'https://payments.example.com',
      public_key: '-----BEGIN PUBLIC KEY-----...' # Публичный ключ сервера payments
    }
  }
end

# На сервере (RobustServerSocket)
RobustServerSocket.configure do |c|
  c.allowed_services = %w[core] # ← Соответствует service_name клиента
  c.private_key = '-----BEGIN PRIVATE KEY-----...' # Приватная пара к public_key
end
```

## 📚 Дополнительные ресурсы

- [RobustClientSocket documentation](https://github.com/tee0zed/robust_client_socket)
- [RSA encryption best practices](https://www.openssl.org/docs/)
- [Redis security guide](https://redis.io/topics/security)

## 📝 Лицензия

См. файл [MIT-LICENSE](MIT-LICENSE)

## 🐛 Баги и предложения

Сообщайте о багах через ишью, или напрямую тг @cruel_mango или email tee0zed@gmail.com
