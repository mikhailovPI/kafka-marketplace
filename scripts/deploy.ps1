# Скрипт автоматического развертывания Kafka кластера
# Автоматически генерирует сертификаты, если их нет

$ErrorActionPreference = "Stop"

# Параметры
$Password = "your-password"
$CredsDir = "credentials"
$CaCrt = Join-Path $CredsDir "ca.crt"

# Проверка и генерация сертификатов
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Проверка SSL сертификатов" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Проверяем наличие сертификатов брокеров (не CA)
$firstBrokerCrt = Join-Path $CredsDir "kafka-0-creds" "kafka-0.crt"

if (-not (Test-Path $firstBrokerCrt)) {
    Write-Host "Сертификаты не найдены. Генерация сертификатов..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Выберите вариант:" -ForegroundColor Cyan
    Write-Host "1. С CA (рекомендуется для production)" -ForegroundColor Yellow
    Write-Host "2. Без CA - самоподписные (проще для разработки)" -ForegroundColor Yellow
    Write-Host ""
    
    # По умолчанию используем упрощенный вариант без CA
    $useSimple = $true
    
    # Проверяем, есть ли переменная окружения для выбора
    if ($env:USE_CA_CERTS -eq "true") {
        $useSimple = $false
    }
    
    if ($useSimple) {
        Write-Host "Используется упрощенный вариант (без CA)..." -ForegroundColor Cyan
        $scriptPath = Join-Path $PSScriptRoot "generate-certificates-simple.ps1"
    } else {
        Write-Host "Используется вариант с CA..." -ForegroundColor Cyan
        $scriptPath = Join-Path $PSScriptRoot "generate-certificates.ps1"
    }
    
    if (Test-Path $scriptPath) {
        & $scriptPath -Password $Password
        Write-Host ""
        Write-Host "✓ Сертификаты успешно сгенерированы" -ForegroundColor Green
    } else {
        Write-Host "ОШИБКА: Скрипт генерации сертификатов не найден!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✓ Сертификаты уже существуют" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Запуск Docker контейнеров" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Сначала базовые сервисы
docker-compose up -d zookeeper kafka-0 kafka-1 kafka-2

# Потом зависимые сервисы
docker-compose up -d schema-registry kafka-ui

# Затем целевой кластер
docker-compose up -d zookeeper-destination kafka-0-destination etc.

# В конце все остальное
docker-compose up -d


# Создать топики
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic inputJsonStream --partitions 3 --replication-factor 3
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic products --partitions 3 --replication-factor 3
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic blockedProducts --partitions 3 --replication-factor 3
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic response --partitions 3 --replication-factor 3
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic userQuery --partitions 3 --replication-factor 3
docker exec -it kafka-0 kafka-topics --create --bootstrap-server kafka-0:9092 --command-config /etc/kafka/secrets/admin.properties --topic recommendations --partitions 3 --replication-factor 3
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic inputJsonStream --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic products --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic blockedProducts --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic response --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic userQuery --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic recommendations --partitions 3 --replication-factor 1
docker exec -it kafka-0-destination kafka-topics --create --bootstrap-server kafka-0-destination:9095 --topic dataAnalysis --partitions 3 --replication-factor 1
# Выдать права
docker exec -it kafka-0 kafka-acls `
  --bootstrap-server kafka-0:9092 `
  --command-config /etc/kafka/secrets/admin.properties `
  --add `
  --allow-principal User:admin `
  --operation All `
  --cluster `
  --topic "*" `
  --group "*" `
  --transactional-id "*" `
  --delegation-token "*"

#Создайте СХЕМЫ для реплики
#products-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "products-value"

$schema = @'
{
"type": "record",
"name": "Product",
"namespace": "com.example.avro",
"fields": [
{"name": "product_id", "type": "string"},
{"name": "name", "type": "string"},
{"name": "description", "type": "string"},
{
"name": "price",
"type": {
"type": "record",
"name": "Price",
"fields": [
{"name": "amount", "type": "double"},
{"name": "currency", "type": "string"}
]
}
},
{"name": "category", "type": "string"},
{"name": "brand", "type": "string"},
{
"name": "stock",
"type": {
"type": "record",
"name": "Stock",
"fields": [
{"name": "available", "type": "int"},
{"name": "reserved", "type": "int"}
]
}
},
{"name": "sku", "type": "string"},
{
"name": "tags",
"type": {
"type": "array",
"items": "string"
}
},
{
"name": "images",
"type": {
"type": "array",
"items": {
"type": "record",
"name": "Image",
"fields": [
{"name": "url", "type": "string"},
{"name": "alt", "type": "string"}
]
}
}
},
{
"name": "specifications",
"type": {
"type": "record",
"name": "Specifications",
"fields": [
{"name": "weight", "type": "string"},
{"name": "dimensions", "type": "string"},
{"name": "battery_life", "type": "string"},
{"name": "water_resistance", "type": "string"}
]
}
},
{"name": "created_at", "type": "string"},
{"name": "updated_at", "type": "string"},
{"name": "index", "type": "string"},
{"name": "store_id", "type": "string"}
]
}
'@

$schemaData = @{
schema = $schema
} | ConvertTo-Json

$headers = @{
"Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема Product успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы Product: $($_.Exception.Message)"
}

#inputJsonStream-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "inputJsonStream-value"

$schema = @'
{
"type": "record",
"name": "inputJsonStream",
"namespace": "com.example.avro",
"fields": [
{"name": "product_id", "type": "string"},
{"name": "name", "type": "string"},
{"name": "description", "type": "string"},
{
"name": "price",
"type": {
"type": "record",
"name": "Price",
"fields": [
{"name": "amount", "type": "double"},
{"name": "currency", "type": "string"}
]
}
},
{"name": "category", "type": "string"},
{"name": "brand", "type": "string"},
{
"name": "stock",
"type": {
"type": "record",
"name": "Stock",
"fields": [
{"name": "available", "type": "int"},
{"name": "reserved", "type": "int"}
]
}
},
{"name": "sku", "type": "string"},
{
"name": "tags",
"type": {
"type": "array",
"items": "string"
}
},
{
"name": "images",
"type": {
"type": "array",
"items": {
"type": "record",
"name": "Image",
"fields": [
{"name": "url", "type": "string"},
{"name": "alt", "type": "string"}
]
}
}
},
{
"name": "specifications",
"type": {
"type": "record",
"name": "Specifications",
"fields": [
{"name": "weight", "type": "string"},
{"name": "dimensions", "type": "string"},
{"name": "battery_life", "type": "string"},
{"name": "water_resistance", "type": "string"}
]
}
},
{"name": "created_at", "type": "string"},
{"name": "updated_at", "type": "string"},
{"name": "index", "type": "string"},
{"name": "store_id", "type": "string"}
]
}
'@

$schemaData = @{
schema = $schema
} | ConvertTo-Json

$headers = @{
"Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема inputJsonStream успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы inputJsonStream: $($_.Exception.Message)"
}

#blockedProducts-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "blockedProducts-value"

$schema = @'
{
  "type": "record",
  "name": "BlockedProduct",
  "namespace": "com.example.avro",
  "fields": [
    {
      "name": "product_id",
      "type": "string"
    }
  ]
}
'@

$schemaData = @{
  schema = $schema
} | ConvertTo-Json

$headers = @{
  "Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема BlockedProduct успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы BlockedProduct: $($_.Exception.Message)"
}


#recommendation-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "recommendation-value"

$schemaRecommendation = @'
{
  "type": "record",
  "name": "Recommendation",
  "namespace": "com.example.avro",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "id", "type": "string"},
    {"name": "category", "type": "string"},
    {"name": "brand", "type": "string"}
  ]
}
'@

$schemaData = @{
  schema = $schema
} | ConvertTo-Json

$headers = @{
  "Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема Recommendation успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы Recommendation: $($_.Exception.Message)"
}

#response-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "response-value"

$schemaResponse = @'
{
  "type": "record",
  "name": "Response",
  "namespace": "com.example.avro",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "id", "type": "string"},
    {"name": "category", "type": "string"}
  ]
}
'@


$schemaData = @{
  schema = $schema
} | ConvertTo-Json

$headers = @{
  "Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема Response успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы Response: $($_.Exception.Message)"
}


#userQuery-value
$schemaRegistryUrl = "http://localhost:18082"
$subject = "userQuery-value"

$schemaUserQuery = @'
{
  "type": "record",
  "name": "UserQuery",
  "namespace": "com.example.avro",
  "fields": [
    {"name": "found_product_id", "type": "string"},
    {"name": "product_name_query", "type": "string"},
    {"name": "query_type", "type": "string"},
    {"name": "timestamp", "type": "string"}
  ]
}
'@

$schemaData = @{
  schema = $schema
} | ConvertTo-Json

$headers = @{
  "Content-Type" = "application/vnd.schemaregistry.v1+json"
}

try {
  $response = Invoke-RestMethod -Uri "$schemaRegistryUrl/subjects/$subject/versions" -Method Post -Body $schemaData -Headers $headers
  Write-Host "Схема userQuery успешно зарегистрирована! Response: $($response | ConvertTo-Json)"
} catch {
  Write-Host "Ошибка при регистрации схемы userQuery: $($_.Exception.Message)"
}

try {
$response = Invoke-RestMethod `
-Uri "$schemaRegistryUrl/subjects/$subject/versions" `
-Method Post `
-Body $schemaData `
-Headers $headers
Write-Output "Схема зарегистрирована для реплики. ID: $response"
}
catch {
Write-Output "Ошибка регистрации схемы: $($_.Exception.Message)"
}


# Регистрация HDFS Sink Connector JsonFormat
# try {
#     $response = Invoke-RestMethod -Uri "http://localhost:18083/connectors/hdfs-sink-connector1" -Method Delete
#     Write-Host "Старый коннектор удален"
# } catch {
#     Write-Host "Ошибка удаления коннектора (возможно его нет): $($_.Exception.Message)"
# }

Start-Sleep -Seconds 60

$connectorConfig = @{
    "name" = "hdfs-sink-connector-final"
    "config" = @{
        "connector.class" = "io.confluent.connect.hdfs.HdfsSinkConnector"
        "tasks.max" = "1"
        "topics" = "products"

        "hdfs.url" = "hdfs://hadoop-namenode:9000"

        "consumer.override.bootstrap.servers" = "kafka-0-destination:9095,kafka-1-destination:9093,kafka-2-destination:9094"
        "consumer.override.security.protocol" = "PLAINTEXT"

        "format.class" = "io.confluent.connect.hdfs.string.StringFormat"
        "key.converter" = "org.apache.kafka.connect.storage.StringConverter"
        "key.converter.schemas.enable" = "false"
        "value.converter" = "org.apache.kafka.connect.storage.StringConverter"
        "value.converter.schemas.enable" = "false"

        "topics.dir" = "/data"
        "logs.dir" = "/logs"
        "flush.size" = "3"
        "rotate.interval.ms" = "30000"

        "errors.tolerance" = "all"
        "errors.log.enable" = "true"
        "errors.log.include.messages" = "true"

        "hdfs.authentication.kerberos" = "false"
        "schema.compatibility" = "NONE"
        "timezone" = "Europe/Moscow"
    }
} | ConvertTo-Json -Depth 10

# Отправка обновленной конфигурации в Kafka Connect REST API
Invoke-RestMethod -Uri "http://localhost:18083/connectors/" -Method Post -ContentType "application/json" -Body $connectorConfig

# Проверить статус коннектора
#Invoke-RestMethod -Uri "http://localhost:18083/connectors/hdfs-sink-connector-final/status" | ConvertTo-Json
# отчет
# PS C:\projects\KafkaSSlDemo>
# docker exec hadoop-namenode hdfs dfsadmin -report
# docker logs hadoop-namenode --tail 20 | findstr /i "pause gc memory"

#глубокий анализ логов!!!
# docker logs kafka-connect | findstr /i "error exception fail"
# docker logs hadoop-namenode | findstr /i "error exception fail"

# # Проверка существующих директорий
# docker exec hadoop-namenode hdfs dfs -ls /
# #Если вы видите директории /data и /logs, то ничего создавать не нужно!
#
# # Правильные команды (если действительно нужно)
# docker exec hadoop-namenode hdfs dfs -mkdir -p /data
# docker exec hadoop-namenode hdfs dfs -mkdir -p /logs
# docker exec hadoop-namenode hdfs dfs -chmod 755 /data
# docker exec hadoop-namenode hdfs dfs -chmod 755 /logs

# права, если надо
# docker exec hadoop-namenode hdfs dfs -chmod -R 777 /

# Создать коннектор FileStreamSink
# try {
#     $response = Invoke-RestMethod -Uri "http://localhost:18083/connectors/file-sink-products-final" -Method Delete
#     Write-Host "Старый коннектор удален"
# } catch {
#     Write-Host "Ошибка удаления коннектора (возможно его нет): $($_.Exception.Message)"
# }


$body = @{
    "name" = "file-sink-products-final"
    "config" = @{
        "connector.class" = "FileStreamSink"
        "tasks.max" = "1"
        "topics" = "products"
        "file" = "/data/output/products-final.json"

        "key.converter" = "org.apache.kafka.connect.storage.StringConverter"
        "value.converter" = "org.apache.kafka.connect.json.JsonConverter"
        "value.converter.schemas.enable" = "false"

        "consumer.override.bootstrap.servers" = "kafka-0:9092,kafka-1:9092,kafka-2:9092"
        "consumer.override.security.protocol" = "SASL_SSL"
        "consumer.override.sasl.mechanism" = "PLAIN"
        "consumer.override.sasl.jaas.config" = "org.apache.kafka.common.security.plain.PlainLoginModule required username=`"admin`" password=`"your-password`";"
        "consumer.override.ssl.truststore.location" = "/etc/kafka/secrets/kafka-0.truststore.jks"
        "consumer.override.ssl.truststore.password" = "your-password"
        "consumer.override.ssl.endpoint.identification.algorithm" = "HTTPS"

        "consumer.override.auto.offset.reset" = "earliest"
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "http://localhost:18083/connectors" -Method Post `
    -ContentType "application/json" `
    -Body $body

