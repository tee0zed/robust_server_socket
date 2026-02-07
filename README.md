# RobustServerSocket

Gem для межсервисной авторизации, используется в паре с RobustClientSocket

### ⚠️ Not Production Tested (yet)
### 🤖 🛑 🥈 Not vibecoded 

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
- **Асимметричное шифрование**: Приватный ключ на сервере, публичный — у клиентов

### 2. Защита от повторного использования токенов
- **Одноразовые токены**: Каждый токен может быть использован только один раз
- **Blacklist в Redis**: Использованные токены автоматически добавляются в черный список
- **Атомарная проверка**: Race condition защищена благодаря Redis Lua скриптам

### 3. Временные ограничения
- **Expiration time**: Настраиваемое время жизни токена
- **Автоматическое истечение**: Токены автоматически становятся недействительными после истечения времени
- **Защита от replay attacks**: Старые токены не могут быть использованы повторно

### 4. Контроль доступа
- **Whitelist клиентов**: Только авторизованные сервисы могут подключаться
- **Идентификация по имени**: Каждый клиент должен быть явно указан в `allowed_services`
- **Валидация формата токена**: Строгая проверка структуры токена

### 5. Rate Limiting (опционально)
- **Защита от DDoS**: Ограничение количества запросов от каждого клиента
- **Sliding window**: Справедливое распределение запросов во времени
- **Fail-open стратегия**: Если Redis недоступен, запросы пропускаются (для надёжности)
- **Per-client лимиты**: Индивидуальные счётчики для каждого клиента

### 6. Защита от инъекций
- **Валидация входных данных**: Проверка типа, длины и формата токенов
- **Максимальная длина токена**: Ограничение 2048 символов
- **Проверка на пустые значения**: Отклонение пустых или некорректных токенов

## 📦 Установка

```ruby
gem 'robust_server_socket'
```

## ⚙️ Конфигурация

Создайте файл `config/initializers/robust_server_socket.rb`:

```ruby
RobustServerSocket.configure do |c|
  # ОБЯЗАТЕЛЬНЫЕ ПАРАМЕТРЫ
  
  # Приватный ключ сервиса (RSA-2048 или выше)
  c.private_key = ENV['ROBUST_SERVER_PRIVATE_KEY']
  c.token_expiration_time = 3
  
  # Список разрешённых сервисов (whitelist)
  # Должен совпадать с именами RobustClientSocket клиента
  c.allowed_services = %w[core payments notifications]
  
  # Redis для работы replay-attack protection и throttling
  c.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  c.redis_pass = ENV['REDIS_PASSWORD']

  # НЕОБЯЗАТЕЛЬНЫЕ ПАРАМЕТРЫ
  # Включить ограничение частоты запросов (по умолчанию: false)
  c.rate_limit_enabled = true
  # Максимальное количество запросов в окне времени (по умолчанию: 100)
  c.rate_limit_max_requests = 100
  # Размер временного окна в секундах (по умолчанию: 60)
  c.rate_limit_window_seconds = 60
end

# Загрузка конфигурации с валидацией
RobustServerSocket.load!
```

### Опции конфигурации сервиса

| Параметр | Тип | Обязательный | Default | Описание |
|----------|-----|--------------|---------|----------|
| `private_key` | String | ✅ | - | Приватный RSA ключ сервиса (RSA-2048 или выше) |
| `token_expiration_time` | Integer | ✅ | - | Время жизни токена в секундах |
| `allowed_services` | Array | ✅ | - | Список разрешённых сервисов (whitelist) |
| `redis_url` | String | ✅ | - | URL для подключения к Redis |
| `redis_pass` | String | ❌ | nil | Пароль для Redis (если требуется) |
| `rate_limit_enabled` | Boolean | ❌ | false | Включить ограничение частоты запросов |
| `rate_limit_max_requests` | Integer | ❌ | 100 | Максимальное количество запросов в окне времени |
| `rate_limit_window_seconds` | Integer | ❌ | 60 | Размер временного окна в секундах |

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

### Rate Limiting вручную

```ruby
# Проверка текущего количества попыток
attempts = RobustServerSocket::RateLimiter.current_attempts('core')
puts "Core service made #{attempts} requests"

# Сброс счётчика для конкретного клиента
RobustServerSocket::RateLimiter.reset!('core')

# Проверка с исключением при превышении
begin
  RobustServerSocket::RateLimiter.check!('core')
rescue RobustServerSocket::RateLimiter::RateLimitExceeded => e
  puts e.message # "Rate limit exceeded for core: 101/100 requests per 60s"
end

# Проверка без исключения (возвращает false при превышении)
if RobustServerSocket::RateLimiter.check('core')
  # Лимит не превышен
else
  # Лимит превышен
end
```

## 🚦 Rate Limiting (Ограничение частоты запросов)

### Принцип работы

Rate Limiter защищает ваш сервис от перегрузки, ограничивая количество запросов от каждого клиента в определённом временном окне.

**Характеристики:**
- **Per-client counters**: Отдельный счётчик для каждого сервиса
- **Sliding window**: Окно сбрасывается автоматически после истечения времени
- **Атомарность**: Инкремент и проверка выполняются атомарно (Redis LUA script)
- **Fail-open**: При недоступности Redis запросы пропускаются (не блокируются)

### Мониторинг

```ruby
# Проверка текущего состояния
clients = ['core', 'payments', 'notifications']
clients.each do |client|
  attempts = RobustServerSocket::RateLimiter.current_attempts(client)
  max = RobustServerSocket.configuration.rate_limit_max_requests
  puts "#{client}: #{attempts}/#{max}"
end

# В метриках (Prometheus, StatsD и т.д.)
clients.each do |client|
  attempts = RobustServerSocket::RateLimiter.current_attempts(client)
  Metrics.gauge("rate_limiter.attempts.#{client}", attempts)
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

## 💡 Рекомендации по использованию

### 1. Управление ключами

**✅ DO:**
```ruby
# Храните ключи в переменных окружения
c.private_key = ENV['ROBUST_SERVER_PRIVATE_KEY']

# Используйте secrets management (AWS Secrets Manager, Vault, и т.д.)
c.private_key = Rails.application.credentials.dig(:robust_server, :private_key)

# Генерируйте ключи правильно
# openssl genrsa -out private_key.pem 2048
# openssl rsa -in private_key.pem -pubout -out public_key.pem
```

**❌ DON'T:**
```ruby
# НЕ коммитьте ключи в git
c.private_key = "-----BEGIN PRIVATE KEY-----\nMII..."

# НЕ используйте слабые ключи
# Минимум RSA-2048, рекомендуется RSA-4096 для высокой безопасности
```

### 2. Конфигурация Redis

**✅ DO:**
```ruby
# Используйте отдельный namespace для каждого окружения
c.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

# Настройте connection pool в production
# В config/initializers/redis.rb
Redis.current = ConnectionPool.new(size: 5, timeout: 5) do
  Redis.new(url: ENV['REDIS_URL'], password: ENV['REDIS_PASSWORD'])
end

# Мониторьте состояние Redis
# Используйте Redis Sentinel или Cluster для высокой доступности
```

**❌ DON'T:**
```ruby
# НЕ используйте одну БД Redis для всех окружений, используйте отдельную bd redis
# НЕ игнорируйте ошибки Redis (rate limiter уже fail-open, но логируйте их)
```

### 5. Whitelist сервисов

```ruby
# Явно указывайте только необходимые сервисы
c.allowed_services = %w[core payments] # ✅

# НЕ используйте wildcards или регулярные выражения
c.allowed_services = %w[*] # ❌ ОПАСНО!

# Синхронизируйте с keychain клиента
# Server (robust_server_socket):
c.allowed_services = %w[core]

# Client (robust_client_socket):
c.keychain = {
  core: { # ← Должно совпадать
    base_uri: 'https://core.example.com',
    public_key: '-----BEGIN PUBLIC KEY-----...'
  }
}
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

- [BENCHMARK_ANALYSIS.md](BENCHMARK_ANALYSIS.md)
- [RobustClientSocket documentation](https://github.com/tee0zed/robust_client_socket)
- [RSA encryption best practices](https://www.openssl.org/docs/)
- [Redis security guide](https://redis.io/topics/security)

## 📝 Лицензия

См. файл [MIT-LICENSE](MIT-LICENSE)

## 🐛 Баги и предложения

Сообщайте о проблемах через issue tracker вашего репозитория.
