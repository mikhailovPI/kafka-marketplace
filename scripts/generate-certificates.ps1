# Скрипт для автоматической генерации SSL сертификатов для Kafka кластера
# Использует CA (Certificate Authority) для подписи сертификатов брокеров
# Для упрощенного варианта без CA используйте: generate-certificates-simple.ps1
# Использование: .\scripts\generate-certificates.ps1 [password]

param(
    [string]$Password = "your-password"
)

$ErrorActionPreference = "Stop"

# Параметры
$CredsDir = "credentials"
$CaCnf = Join-Path $CredsDir "ca.cnf"
$CaKey = Join-Path $CredsDir "ca-key"
$CaCrt = Join-Path $CredsDir "ca.crt"
$CaPem = Join-Path $CredsDir "ca.pem"
$CaSrl = Join-Path $CredsDir "ca.srl"

# Брокеры
$Brokers = @("kafka-0", "kafka-1", "kafka-2")

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Генерация SSL сертификатов для Kafka" -ForegroundColor Cyan
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

# Функция для создания конфигурации CA
function New-CaConfig {
    Write-Host "Создание конфигурации CA..."
    $caConfig = @"
[ policy_match ]
countryName = match
stateOrProvinceName = match
organizationName = match
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[ req ]
prompt = no
distinguished_name = dn
default_md = sha256
default_bits = 4096
x509_extensions = v3_ca

[ dn ]
countryName = RU
organizationName = Yandex
organizationalUnitName = Practice
localityName = Moscow
commonName = yandex-practice-kafka-ca

[ v3_ca ]
subjectKeyIdentifier = hash
basicConstraints = critical,CA:true
authorityKeyIdentifier = keyid:always,issuer:always
keyUsage = critical,keyCertSign,cRLSign
"@
    $caConfig | Out-File -FilePath $CaCnf -Encoding ASCII
}

# Функция для создания конфигурации брокера
function New-BrokerConfig {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $cnfFile = Join-Path $brokerDir "$broker.cnf"
    
    $config = @"
[req]
prompt = no
distinguished_name = dn
default_md = sha256
default_bits = 4096
req_extensions = v3_req

[ dn ]
countryName = RU
organizationName = Yandex
organizationalUnitName = Practice
localityName = Moscow
commonName = $broker

[ v3_ca ]
subjectKeyIdentifier = hash
basicConstraints = critical,CA:true
authorityKeyIdentifier = keyid:always,issuer:always
keyUsage = critical,keyCertSign,cRLSign

[ v3_req ]
subjectKeyIdentifier = hash
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Certificate"
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $broker
DNS.2 = ${broker}-external
DNS.3 = localhost
"@
    $config | Out-File -FilePath $cnfFile -Encoding ASCII
}

# Генерация CA сертификата
function New-CaCertificate {
    Write-Host "Генерация CA сертификата..."
    
    if (-not (Test-Path $CaCnf)) {
        New-CaConfig
    }
    
    # Генерируем CA ключ и сертификат
    try {
        openssl req -new -nodes `
            -x509 `
            -days 3650 `
            -newkey rsa:4096 `
            -keyout $CaKey `
            -out $CaCrt `
            -config $CaCnf 2>&1 | Out-Null
    } catch {
        # Если не получилось с 4096, пробуем 2048
        openssl req -new -nodes `
            -x509 `
            -days 3650 `
            -newkey rsa:2048 `
            -keyout $CaKey `
            -out $CaCrt `
            -config $CaCnf 2>&1 | Out-Null
    }
    
    # Создаем ca.pem
    Get-Content $CaCrt, $CaKey | Out-File -FilePath $CaPem -Encoding ASCII
    
    Write-Host "✓ CA сертификат создан" -ForegroundColor Green
}

# Генерация сертификата для брокера
function New-BrokerCertificate {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $cnfFile = Join-Path $brokerDir "$broker.cnf"
    $keyFile = Join-Path $brokerDir "$broker.key"
    $csrFile = Join-Path $brokerDir "$broker.csr"
    $crtFile = Join-Path $brokerDir "$broker.crt"
    $p12File = Join-Path $brokerDir "$broker.p12"
    
    Write-Host "Генерация сертификата для $broker..."
    
    # Создаем директорию
    New-Item -ItemType Directory -Force -Path $brokerDir | Out-Null
    
    # Создаем конфигурацию
    New-BrokerConfig -Broker $broker
    
    # Генерируем приватный ключ и CSR
    openssl req -new `
        -newkey rsa:2048 `
        -keyout $keyFile `
        -out $csrFile `
        -config $cnfFile `
        -nodes 2>&1 | Out-Null
    
    # Подписываем сертификат CA
    openssl x509 -req `
        -days 3650 `
        -in $csrFile `
        -CA $CaCrt `
        -CAkey $CaKey `
        -CAcreateserial `
        -out $crtFile `
        -extfile $cnfFile `
        -extensions v3_req 2>&1 | Out-Null
    
    # Создаем PKCS12 хранилище
    $passArg = "pass:$Password"
    openssl pkcs12 -export `
        -in $crtFile `
        -inkey $keyFile `
        -chain `
        -CAfile $CaPem `
        -name $broker `
        -out $p12File `
        -password $passArg 2>&1 | Out-Null
    
    Write-Host "✓ Сертификат для $broker создан" -ForegroundColor Green
}

# Создание keystore и truststore
function New-Keystores {
    param([string]$Broker)
    
    $brokerDir = Join-Path $CredsDir "$broker-creds"
    $p12File = Join-Path $brokerDir "$broker.p12"
    $pkcs12Keystore = Join-Path $brokerDir "kafka.$broker.keystore.pkcs12"
    $jksKeystore = Join-Path $brokerDir "$broker.keystore.jks"
    $jksTruststore = Join-Path $brokerDir "$broker.truststore.jks"
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
    
    # Создаем JKS truststore и импортируем CA
    keytool -import `
        -file $CaCrt `
        -alias ca `
        -keystore $jksTruststore `
        -storepass $Password `
        -noprompt 2>&1 | Out-Null
    
    # Создаем PKCS12 truststore и импортируем CA
    keytool -import `
        -file $CaCrt `
        -alias ca `
        -keystore $pkcs12Truststore `
        -storetype PKCS12 `
        -storepass $Password `
        -noprompt 2>&1 | Out-Null
    
    Write-Host "✓ Keystore и truststore для $broker созданы" -ForegroundColor Green
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
    
    # Zookeeper JAAS для kafka-0-creds (используется в docker-compose)
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
    Write-Host "Начало генерации сертификатов..." -ForegroundColor Yellow
    Write-Host ""
    
    # Генерируем CA
    New-CaCertificate
    
    # Генерируем сертификаты для каждого брокера
    foreach ($broker in $Brokers) {
        Write-Host ""
        New-BrokerCertificate -Broker $broker
        New-Keystores -Broker $broker
        New-PasswordFiles -Broker $broker
    }
    
    # Создаем JAAS конфигурации
    Write-Host ""
    New-JaasConfigs
    
    # Создаем admin.properties
    New-AdminProperties
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "✓ Все сертификаты успешно созданы!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Сертификаты находятся в директории: $CredsDir" -ForegroundColor Yellow
}

# Запуск
Main

