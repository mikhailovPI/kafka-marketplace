# Kafka Marketplace - Аналитическая платформа для маркетплейса

## Описание проекта

Проект представляет собой аналитическую платформу для маркетплейса "Покупай выгодно", построенную на базе Apache Kafka.
Система обеспечивает сбор, обработку и анализ данных о товарах и взаимодействии клиентов с платформой.

### Основные возможности

- **Фильтрация товаров в реальном времени** - блокировка запрещенных товаров через Kafka Streams
- **Репликация данных** - дублирование данных между кластерами Kafka через MirrorMaker
- **Data Lake** - хранение данных в HDFS для долгосрочной аналитики
- **Аналитика** - обработка данных через Apache Spark
- **Мониторинг** - отслеживание метрик через Prometheus и Grafana
- **Безопасность** - SSL/TLS шифрование и SASL аутентификация

---

## Инструкция по запуску

### Требования

- **Docker** и **Docker Compose**
- **Java 17**
- **Maven** 3.6+
- **OpenSSL**
- **PowerShell** или **Bash**

### Быстрый старт

1. **Запустите автоматическое развертывание:**

   ```powershell
   # Windows
   .\scripts\deploy.ps1
   ```

   ```bash
   # Linux/Mac
   chmod +x scripts/deploy.ps1
   ./scripts/deploy.ps1
   ```

   Скрипт автоматически:
    - Проверяет наличие SSL сертификатов
    - Генерирует сертификаты, если их нет
    - Запускает все Docker контейнеры
    - Создает необходимые топики Kafka
    - Настраивает ACL (Access Control Lists)
    - Регистрирует коннекторы Kafka Connect

2. **Дождитесь запуска всех сервисов** (2-3 минуты)

3. **Проверьте статус сервисов:**

   ```powershell
   docker-compose ps
   ```

### Ручной запуск (пошагово)

Если нужно запустить вручную:

1. **Сгенерируйте SSL сертификаты**:

   ```powershell
   # Windows - упрощенный вариант (без CA)
   .\scripts\generate-certificates-simple.ps1
   
   # Windows - с CA (для production)
   .\scripts\generate-certificates.ps1
   ```

   ```bash
   # Linux/Mac
   chmod +x scripts/generate-certificates-simple.sh
   ./scripts/generate-certificates-simple.sh
   ```

2. **Запустите Docker контейнеры:**

   ```bash
   # Сначала базовые сервисы
   docker-compose up -d zookeeper kafka-0 kafka-1 kafka-2
   # Затем зависимые сервисы
   docker-compose up -d schema-registry kafka-ui
   # Целевой кластер для репликации
   docker-compose up -d zookeeper-destination kafka-0-destination kafka-1-destination kafka-2-destination
   # HDFS и остальные сервисы
   docker-compose up -d
   ```

3. **Создайте топики**:

   ```bash
   docker exec -it kafka-0 kafka-topics --create \
     --bootstrap-server kafka-0:9092 \
     --command-config /etc/kafka/secrets/admin.properties \
     --topic products --partitions 3 --replication-factor 3
   ```

### Использование системы

#### 1. Добавление заблокированных товаров

1. Отредактируйте файл `data/blocked_products.txt` (добавьте ID товаров, по одному на строку)
2. Запустите класс `ru.myproject.shop.BlockedProductsProducer`
3. Заблокированные товары будут отправлены в топик `blockedProducts`

#### 2. Загрузка товаров

1. Отредактируйте файл `data/products.json` (добавьте товары в формате JSON)
2. Запустите класс `ru.myproject.shop.ProductFilterStream`
3. Товары будут отфильтрованы и отправлены в топик `products`
4. Данные автоматически попадут в HDFS через Kafka Connect

#### 3. Запросы клиентов

1. Запустите класс `ru.myproject.client.ClientRequest`
2. Введите название товара
3. Система найдет товар, отправит рекомендации в топик `recommendations`

#### 4. Аналитика Spark

1. Убедитесь, что данные есть в HDFS
2. Запустите класс `ru.myproject.spark.SparkReadMain`
3. Результаты анализа будут отправлены в топик `dataAnalysis` во втором кластере

### Веб-интерфейсы

После запуска доступны следующие интерфейсы:

- **Kafka UI** : http://localhost:8080 и http://localhost:8082
- **Schema Registry**: http://localhost:18081
- **HDFS NameNode UI**: http://localhost:9870
- **Spark Master UI**: http://localhost:8085
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
- **Alertmanager**: http://localhost:9093

---

## Используемые инструменты и технологии

### Основной стек

- **Apache Kafka 3.6.1** 
- **Kafka Streams** 
- **Zookeeper 7.4.4** 
- **Schema Registry 7.4.4**

### Хранилище данных

- **HDFS (Hadoop Distributed File System) 3.3.6** 
- **Apache Spark 3.5.0**

### Интеграция и репликация

- **Kafka Connect 7.7.1**
    - HDFS Sink Connector - запись данных в HDFS
    - FileStreamSink - запись данных в локальные файлы
- **MirrorMaker** 

### Безопасность

- **SSL/TLS** 
- **SASL/PLAIN**
- **ACL**

### Мониторинг

- **Prometheus v2.30.3**
- **Grafana 8.1.6**
- **JMX Exporter**

### Инфраструктура

- **Docker**
- **Docker Compose**
- **Maven**

---

## Пояснение реализации

### Архитектура системы

#### Поток данных

```
SHOP API → Kafka (inputJsonStream) → Kafka Streams (фильтрация) → Kafka (products)
                                                                         ↓
                                                              Kafka Connect
                                                                     ↓
                                            ┌───────────────────────┴──────────────┐
                                            ↓                                        ↓
                                        HDFS (Data Lake)                    products-final.json
                                            ↓
                                    Apache Spark (аналитика)
                                            ↓
                                    Kafka (dataAnalysis)
```

#### Компоненты системы

**1. Основной Kafka кластер (SASL_SSL)**

- 3 брокера Kafka (kafka-0, kafka-1, kafka-2)
- Zookeeper для координации
- Schema Registry для управления схемами
- Kafka UI для визуализации

**2. Destination Kafka кластер (PLAINTEXT)**

- Отдельный кластер для репликации данных
- Используется для записи в HDFS (без SSL для упрощения)
- MirrorMaker реплицирует данные из основного кластера

**3. HDFS кластер**

- NameNode - управление файловой системой
- 3 DataNode - хранение данных с репликацией

**4. Spark кластер**

- Spark Master - координация задач
- 2 Spark Worker - выполнение задач

**5. Kafka Connect**

- HDFS Sink Connector - запись данных из Kafka в HDFS
- FileStreamSink - запись данных в локальные файлы

### Реализация компонентов

#### 1. Фильтрация товаров (Kafka Streams)

**Класс:** `ru.myproject.shop.ProductFilterStream`

**Реализация:**

- Читает список заблокированных товаров из топика `blockedProducts`
- Фильтрует входящие товары из топика `inputJsonStream`
- Пропускает только разрешенные товары в топик `products`
- Использует Kafka Streams для обработки в реальном времени

**Особенности:**

- Exactly-once семантика обработки
- Автоматическая обработка ошибок
- Поддержка перезапуска с сохранением состояния

#### 2. Клиентские запросы

**Класс:** `ru.myproject.client.ClientRequest`

**Реализация:**

- Читает данные из файла `products-final.json` (создается Kafka Connect)
- Поиск товаров по названию
- Генерация персонализированных рекомендаций на основе бренда и категории
- Запись запросов и ответов в топики `userQuery`, `response`, `recommendations`

**Особенности:**

- Фильтрация по дате (последние 3 года)
- Группировка по бренду и категории
- Асинхронная отправка в Kafka

#### 3. Аналитика Spark

**Класс:** `ru.myproject.spark.SparkReadMain`

**Реализация:**

- Читает данные из HDFS (формат JSON)
- Выполняет аналитику: группировка товаров по бренду и категории
- Отправляет результаты в топик `dataAnalysis` destination кластера

**Особенности:**

- Поддержка чтения из HDFS
- Адаптивная оптимизация запросов
- Интеграция с Kafka для отправки результатов

#### 4. Репликация данных (MirrorMaker)

**Реализация:**

- Автоматическая репликация всех топиков из основного кластера в destination
- Используется для изоляции аналитической нагрузки
- Destination кластер используется только для записи в HDFS

#### 5. Хранение данных

**HDFS (Data Lake):**

- Долгосрочное хранение данных для аналитики
- Формат: JSON строки
- Путь в HDFS: `/topics/products/`

**Локальные файлы:**

- Быстрый доступ для Java приложений
- Файл: `data/connector-output/products-final.json`
- Обновляется в реальном времени через FileStreamSink

### Безопасность

**SSL/TLS:**

- Самоподписные сертификаты для каждого брокера
- Автоматическая генерация при первом запуске
- Шифрование трафика между компонентами

**SASL/PLAIN:**

- Аутентификация через username/password
- Пользователь `admin` с паролем `your-password` (по умолчанию)
- Настроено для всех компонентов Kafka

**ACL:**

- Контроль доступа к топикам
- Настроено через `deploy.ps1`
- Пользователь `admin` имеет полный доступ

### Мониторинг

**Prometheus:**

- Сбор метрик из Kafka Connect (через JMX Exporter)
- Метрики доступны на http://localhost:9876/metrics
- Конфигурация в `monitoring/prometheus/prometheus.yml`

**Grafana:**

- Визуализация метрик Kafka Connect
- Преднастроенные дашборды в `monitoring/grafana/dashboards/`
- Автоматическая настройка через provisioning

**Alertmanager:**

- Отправка оповещений при сбоях системы
- Правила алертов в `monitoring/prometheus/alert_rules.yml`
- Маршрутизация алертов по уровням критичности
- Доступен на http://localhost:9093

---

## Структура проекта

```
kafka-marketplace/
├── credentials/              # SSL сертификаты и креды
│   ├── kafka-0-creds/        # Сертификаты для kafka-0
│   ├── kafka-1-creds/        # Сертификаты для kafka-1
│   ├── kafka-2-creds/        # Сертификаты для kafka-2
│   ├── admin.properties      # Конфигурация для админских команд
│   ├── kafka_server_jaas.conf      # JAAS конфигурация для Kafka
│   ├── schema-registry.jaas.conf   # JAAS конфигурация для Schema Registry
│   └── zookeeper.sasl.jaas.conf    # JAAS конфигурация для Zookeeper
│
├── scripts/                  # Скрипты развертывания
│   ├── deploy.ps1            # Основной скрипт развертывания
│   ├── generate-certificates-simple.ps1  # Генерация сертификатов (без CA)
│   ├── generate-certificates.ps1        # Генерация сертификатов (с CA)
│   ├── generate-certificates-simple.sh   # Bash версия (без CA)
│   ├── generate-certificates.sh          # Bash версия (с CA)
│   ├── test_hdfs.ps1         # Тестирование HDFS
│   ├── namenode_entrypoint.sh    # Entrypoint для HDFS NameNode
│   └── datanode_entrypoint.sh    # Entrypoint для HDFS DataNode
│
├── config/                   # Конфигурационные файлы
│   ├── core-site.xml         # Конфигурация Hadoop Core
│   ├── hdfs-site-namenode.xml    # Конфигурация HDFS NameNode
│   ├── hdfs-site-datanode-*.xml  # Конфигурация HDFS DataNodes
│   ├── spark-defaults.conf   # Конфигурация Spark
│   ├── mirror-consumer.properties  # Конфигурация MirrorMaker Consumer
│   ├── mirror-producer.properties  # Конфигурация MirrorMaker Producer
│   ├── kafka-connect.yml     # Конфигурация JMX Exporter для Kafka Connect
│   ├── hdfs-sink-config.json # Конфигурация HDFS Sink Connector
│   └── jmx/                  # JMX конфигурации
│
├── data/                     # Данные и тестовые файлы
│   ├── products.json         # Тестовые данные товаров
│   ├── blocked_products.txt  # Список заблокированных товаров
│   └── connector-output/     # Выходные данные коннекторов
│       └── products-final.json   # Финальный файл с товарами
│
├── docker/                   # Docker файлы
│   └── Dockerfile-kafka-connect  # Кастомный Dockerfile для Kafka Connect
│
├── monitoring/               # Конфигурация мониторинга
│   ├── prometheus/
│   │   └── prometheus.yml    # Конфигурация Prometheus
│   └── grafana/
│       ├── Dockerfile        # Кастомный образ Grafana
│       ├── config.ini        # Конфигурация Grafana
│       ├── dashboards/       # Дашборды Grafana
│       └── provisioning/     # Автоматическая настройка Grafana
│
├── lib/                      # Библиотеки и JAR файлы
│   ├── jmx_prometheus_javaagent-0.15.0.jar  # JMX Exporter
│   └── confluent-hub-components/            # Kafka Connect плагины
│
├── src/                      # Исходный код Java
│   └── main/
│       ├── java/
│       │   └── ru/myproject/
│       │       ├── client/           # Клиентские запросы
│       │       │   ├── ClientRequest.java
│       │       │   └── [модели данных]
│       │       ├── shop/            # SHOP API
│       │       │   ├── ProductFilterStream.java
│       │       │   └── BlockedProductsProducer.java
│       │       ├── spark/           # Spark аналитика
│       │       │   ├── SparkReadMain.java
│       │       │   └── SparkSessionExample.java
│       │       ├── config/          # Конфигурация Kafka
│       │       │   ├── KafkaProperties.java
│       │       │   └── KafkaPropertiesDestination.java
│       │       └── test/            # Тестовые приложения
│       └── resources/
│           └── logback.xml          # Конфигурация логирования
│
├── docker-compose.yml        # Основной файл Docker Compose
├── pom.xml                   # Maven конфигурация
└── README.md                 # Документация
```

### Описание основных директорий

**credentials/** - Все SSL сертификаты, ключи и файлы безопасности. Генерируются автоматически при первом запуске.

**scripts/** - Скрипты для автоматизации развертывания и управления системой.

**config/** - Конфигурационные файлы для всех компонентов системы (Hadoop, Spark, Kafka Connect, MirrorMaker).

**data/** - Тестовые данные и результаты работы коннекторов. Файлы здесь используются для загрузки начальных данных.

**docker/** - Docker-специфичные файлы (Dockerfile для кастомизации образов).

**monitoring/** - Конфигурация систем мониторинга (Prometheus, Grafana).

**lib/** - Внешние библиотеки и плагины, которые не доступны через Maven.

**src/** - Исходный код Java приложений.

---

## Топики Kafka

### Основной кластер (SASL_SSL)

- `inputJsonStream` - входящие товары от магазинов
- `products` - отфильтрованные разрешенные товары
- `blockedProducts` - список заблокированных товаров
- `userQuery` - запросы от клиентов
- `response` - ответы на запросы клиентов
- `recommendations` - персонализированные рекомендации

### Destination кластер (PLAINTEXT)

- Все топики из основного кластера (реплицируются через MirrorMaker)
- `dataAnalysis` - результаты аналитики от Spark

---

## Сети Docker

Система использует две изолированные сети:

1. **kafka-connect-network** - основной кластер Kafka, Zookeeper, Schema Registry, Kafka Connect
2. **kafka-cluster-network** - Spark кластер и HDFS (HDFS также подключен к основной сети для связи с Kafka Connect)

---

## Дополнительная информация

### Настройка hosts файла (Windows)

Для корректной работы HDFS на Windows может потребоваться добавить в `C:\Windows\System32\drivers\etc\hosts`:

```
127.0.0.1 hadoop-datanode-1
127.0.0.1 hadoop-datanode-2
127.0.0.1 hadoop-datanode-3
```

### Изменение паролей

По умолчанию используется пароль `your-password`. Для изменения:

1. Сгенерируйте новые сертификаты с другим паролем
2. Обновите пароль в `docker-compose.yml`
3. Обновите пароль в Java коде (`KafkaProperties.java`)

### Масштабирование

- **Kafka брокеры**: можно добавить больше брокеров в `docker-compose.yml`
- **Spark Workers**: можно добавить больше воркеров для увеличения производительности
- **HDFS DataNodes**: можно добавить больше DataNodes для увеличения емкости

---

## Устранение неполадок

### Проблемы с сертификатами

Если возникают ошибки SSL:

1. Удалите папку `credentials/`
2. Запустите `deploy.ps1` заново (сертификаты сгенерируются автоматически)

### Проблемы с HDFS

Проверьте статус HDFS:

```bash
docker exec hadoop-namenode hdfs dfsadmin -report
```

### Проблемы с Kafka Connect

Проверьте логи:

```bash
docker logs kafka-connect
```

Проверьте статус коннекторов:

```bash
curl http://localhost:18083/connectors
```

---
