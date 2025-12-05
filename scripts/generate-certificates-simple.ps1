# Упрощенный скрипт для генерации самоподписных SSL сертификатов для Kafka
# Без CA - каждый брокер получает самоподписной сертификат
# Использование: .\scripts\generate-certificates-simple.ps1 [password]

param(
    [string]$Password = "your-password"
)

$ErrorActionPreference = "Stop"

# Параметры
$CredsDir = "credentials"
$Brokers = @("kafka-0", "kafka-1", "kafka-2")

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Генерация самоподписных SSL сертификатов" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Пароль: $Password" -ForegroundColor Yellow
Write-Host ""

# Проверка наличия OpenSSL и keytool
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $?) {
        Write-Host "ОШИБКА: $Command не найден. Установите OpenSSL и Java JDK." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Проверка наличия необходимых инструментов..."
Test-Command "openssl"
Test-Command "keytool"
Write-Host "✓ Все инструменты найдены" -ForegroundColor Green
Write-Host ""

# Создаем директорию для кредов
New-Item -ItemType Directory -Force -Path $CredsDir | Out-Null

# Функция для создания конфигурации брокера (самоподписной)
function New-BrokerConfig {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $cnfFile = Join-Path $brokerDir "$broker.cnf"
    
    $config = @"
[req]
prompt = no
distinguished_name = dn
default_md = sha256
default_bits = 2048
x509_extensions = v3_req

[ dn ]
countryName = RU
organizationName = Yandex
organizationalUnitName = Practice
localityName = Moscow
commonName = $broker

[ v3_req ]
subjectKeyIdentifier = hash
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Self-Signed Certificate"
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $broker
DNS.2 = ${broker}-external
DNS.3 = localhost
IP.1 = 127.0.0.1
"@
    $config | Out-File -FilePath $cnfFile -Encoding ASCII
}

# Генерация самоподписного сертификата для брокера
function New-SelfSignedBrokerCertificate {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $cnfFile = Join-Path $brokerDir "$broker.cnf"
    $keyFile = Join-Path $brokerDir "$broker.key"
    $crtFile = Join-Path $brokerDir "$broker.crt"
    $p12File = Join-Path $brokerDir "$broker.p12"
    
    Write-Host "Генерация самоподписного сертификата для $broker..."
    
    # Создаем директорию
    New-Item -ItemType Directory -Force -Path $brokerDir | Out-Null
    
    # Создаем конфигурацию
    New-BrokerConfig -Broker $broker
    
    # Генерируем самоподписной сертификат напрямую (без CA)
    openssl req -new -x509 `
        -days 3650 `
        -newkey rsa:2048 `
        -keyout $keyFile `
        -out $crtFile `
        -config $cnfFile `
        -extensions v3_req `
        -nodes 2>&1 | Out-Null
    
    # Создаем PKCS12 хранилище (без CA chain)
    $passArg = "pass:$Password"
    openssl pkcs12 -export `
        -in $crtFile `
        -inkey $keyFile `
        -name $broker `
        -out $p12File `
        -password $passArg 2>&1 | Out-Null
    
    Write-Host "✓ Самоподписной сертификат для $broker создан" -ForegroundColor Green
}

# Создание keystore и truststore (без CA)
function New-Keystores {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $p12File = Join-Path $brokerDir "$broker.p12"
    $crtFile = Join-Path $brokerDir "$broker.crt"
    $jksKeystore = Join-Path $brokerDir "$broker.keystore.jks"
    $jksTruststore = Join-Path $brokerDir "$broker.truststore.jks"
    $pkcs12Keystore = Join-Path $brokerDir "kafka.$broker.keystore.pkcs12"
    $pkcs12Truststore = Join-Path $brokerDir "kafka.$broker.truststore.jks"
    
    Write-Host "Создание keystore и truststore для $broker..."
    
    # Импортируем PKCS12 в PKCS12 keystore (для Kafka)
    keytool -importkeystore `
        -deststorepass $Password `
        -destkeystore $pkcs12Keystore `
        -srckeystore $p12File `
        -deststoretype PKCS12 `
        -srcstoretype PKCS12 `
        -noprompt `
        -srcstorepass $Password 2>&1 | Out-Null
    
    # Импортируем PKCS12 в JKS keystore
    keytool -importkeystore `
        -srckeystore $p12File `
        -srcstoretype PKCS12 `
        -destkeystore $jksKeystore `
        -deststoretype JKS `
        -deststorepass $Password `
        -srcstorepass $Password `
        -noprompt 2>&1 | Out-Null
    
    # Создаем JKS truststore и импортируем сам сертификат брокера
    # Для самоподписных сертификатов каждый брокер доверяет своему сертификату
    keytool -import `
        -file $crtFile `
        -alias $broker `
        -keystore $jksTruststore `
        -storepass $Password `
        -noprompt 2>&1 | Out-Null
    
    # Создаем PKCS12 truststore
    keytool -import `
        -file $crtFile `
        -alias $broker `
        -keystore $pkcs12Truststore `
        -storetype PKCS12 `
        -storepass $Password `
        -noprompt 2>&1 | Out-Null
    
    Write-Host "✓ Keystore и truststore для $broker созданы" -ForegroundColor Green
}

# Создание общего truststore со всеми сертификатами брокеров
function New-CommonTruststore {
    Write-Host "Создание общего truststore со всеми сертификатами..."
    
    $commonTruststore = Join-Path $CredsDir "kafka-0-creds" "kafka-0.truststore.jks"
    
    # Используем truststore первого брокера как общий
    # Импортируем сертификаты всех брокеров
    foreach ($broker in $Brokers) {
        $brokerDir = Join-Path $CredsDir "$broker-creds"
        $crtFile = Join-Path $brokerDir "$broker.crt"
        
        if (Test-Path $crtFile) {
            keytool -import `
                -file $crtFile `
                -alias $broker `
                -keystore $commonTruststore `
                -storepass $Password `
                -noprompt 2>&1 | Out-Null
        }
    }
    
    # Копируем общий truststore в папки других брокеров
    foreach ($broker in $Brokers) {
        if ($broker -ne "kafka-0") {
            $brokerDir = Join-Path $CredsDir "$broker-creds"
            $brokerTruststore = Join-Path $brokerDir "$broker.truststore.jks"
            Copy-Item $commonTruststore $brokerTruststore -Force
        }
    }
    
    Write-Host "✓ Общий truststore создан" -ForegroundColor Green
}

# Создание файлов с паролями
function New-PasswordFiles {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    
    $Password | Out-File -FilePath (Join-Path $brokerDir "${broker}_sslkey_creds") -Encoding ASCII -NoNewline
    $Password | Out-File -FilePath (Join-Path $brokerDir "${broker}_keystore_creds") -Encoding ASCII -NoNewline
    $Password | Out-File -FilePath (Join-Path $brokerDir "${broker}_truststore_creds") -Encoding ASCII -NoNewline
}

# Создание JAAS конфигураций
function New-JaasConfigs {
    Write-Host "Создание JAAS конфигураций..."
    
    # Kafka Server JAAS
    $kafkaJaas = @"
KafkaServer {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="$Password"
   user_admin="$Password"
   user_kafka="$Password"
   user_producer="$Password"
   user_consumer="$Password";
};

Client {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="$Password";
};
"@
    $kafkaJaas | Out-File -FilePath (Join-Path $CredsDir "kafka_server_jaas.conf") -Encoding ASCII
    
    # Schema Registry JAAS
    $schemaJaas = @"
KafkaClient {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="admin"
    password="$Password";
};
"@
    $schemaJaas | Out-File -FilePath (Join-Path $CredsDir "schema-registry.jaas.conf") -Encoding ASCII
    
    # Zookeeper JAAS
    $zookeeperJaas = @"
Server {
    org.apache.zookeeper.server.auth.DigestLoginModule required
    user_admin="$Password";
};

Client {
    org.apache.zookeeper.server.auth.DigestLoginModule required
    username="admin"
    password="$Password";
};
"@
    $zookeeperJaas | Out-File -FilePath (Join-Path $CredsDir "zookeeper.sasl.jaas.conf") -Encoding ASCII
    
    # Zookeeper JAAS для kafka-0-creds
    $kafka0CredsDir = Join-Path $CredsDir "kafka-0-creds"
    New-Item -ItemType Directory -Force -Path $kafka0CredsDir | Out-Null
    Copy-Item (Join-Path $CredsDir "zookeeper.sasl.jaas.conf") (Join-Path $kafka0CredsDir "zookeeper.sasl.jaas.conf")
    
    Write-Host "✓ JAAS конфигурации созданы" -ForegroundColor Green
}

# Создание admin.properties
function New-AdminProperties {
    Write-Host "Создание admin.properties..."
    
    $adminProps = @"
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="$Password";
ssl.truststore.location=./credentials/kafka-0-creds/kafka-0.truststore.jks
ssl.truststore.password=$Password
ssl.keystore.location=./credentials/kafka-0-creds/kafka-0.keystore.jks
ssl.keystore.password=$Password
ssl.key.password=$Password
"@
    $adminProps | Out-File -FilePath (Join-Path $CredsDir "admin.properties") -Encoding ASCII
    
    # Копируем в каждую папку брокера
    foreach ($broker in $Brokers) {
        $brokerDir = Join-Path $CredsDir "$broker-creds"
        New-Item -ItemType Directory -Force -Path $brokerDir | Out-Null
        Copy-Item (Join-Path $CredsDir "admin.properties") (Join-Path $brokerDir "admin.properties")
    }
    
    Write-Host "✓ admin.properties создан" -ForegroundColor Green
}

# Основная функция
function Main {
    Write-Host "Начало генерации самоподписных сертификатов..." -ForegroundColor Yellow
    Write-Host "Примечание: Используются самоподписные сертификаты без CA" -ForegroundColor Yellow
    Write-Host ""
    
    # Генерируем самоподписные сертификаты для каждого брокера
    foreach ($broker in $Brokers) {
        Write-Host ""
        New-SelfSignedBrokerCertificate -Broker $broker
        New-Keystores -Broker $broker
        New-PasswordFiles -Broker $broker
    }
    
    # Создаем общий truststore
    Write-Host ""
    New-CommonTruststore
    
    # Создаем JAAS конфигурации
    Write-Host ""
    New-JaasConfigs
    
    # Создаем admin.properties
    New-AdminProperties
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "✓ Все самоподписные сертификаты созданы!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Сертификаты находятся в директории: $CredsDir" -ForegroundColor Yellow
    Write-Host "Примечание: CA файлы не требуются для этого варианта" -ForegroundColor Cyan
}

# Запуск
Main

