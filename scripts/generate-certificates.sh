#!/bin/bash

# Скрипт для автоматической генерации SSL сертификатов для Kafka кластера
# Использует CA (Certificate Authority) для подписи сертификатов брокеров
# Для упрощенного варианта без CA используйте: generate-certificates-simple.sh
# Использование: ./scripts/generate-certificates.sh [password]

set -e

# Параметры
PASSWORD="${1:-your-password}"
CREDS_DIR="credentials"
CA_CNF="$CREDS_DIR/ca.cnf"
CA_KEY="$CREDS_DIR/ca-key"
CA_CRT="$CREDS_DIR/ca.crt"
CA_PEM="$CREDS_DIR/ca.pem"
CA_SRL="$CREDS_DIR/ca.srl"

# Брокеры
BROKERS=("kafka-0" "kafka-1" "kafka-2")

echo "=========================================="
echo "Генерация SSL сертификатов для Kafka"
echo "=========================================="
echo "Пароль: $PASSWORD"
echo ""

# Создаем директорию для кредов
mkdir -p "$CREDS_DIR"

# Функция для создания конфигурации CA
create_ca_config() {
    echo "Создание конфигурации CA..."
    cat > "$CA_CNF" <<EOF
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
EOF
}

# Функция для создания конфигурации брокера
create_broker_config() {
    local broker=$1
    local cnf_file="$CREDS_DIR/$broker-creds/$broker.cnf"
    
    cat > "$cnf_file" <<EOF
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
EOF
}

# Генерация CA сертификата
generate_ca() {
    echo "Генерация CA сертификата..."
    
    if [ ! -f "$CA_CNF" ]; then
        create_ca_config
    fi
    
    # Генерируем CA ключ и сертификат
    openssl req -new -nodes \
        -x509 \
        -days 3650 \
        -newkey rsa:4096 \
        -keyout "$CA_KEY" \
        -out "$CA_CRT" \
        -config "$CA_CNF" 2>/dev/null || {
        # Если не получилось с 4096, пробуем 2048
        openssl req -new -nodes \
            -x509 \
            -days 3650 \
            -newkey rsa:2048 \
            -keyout "$CA_KEY" \
            -out "$CA_CRT" \
            -config "$CA_CNF"
    }
    
    # Создаем ca.pem
    cat "$CA_CRT" "$CA_KEY" > "$CA_PEM"
    
    echo "✓ CA сертификат создан"
}

# Генерация сертификата для брокера
generate_broker_cert() {
    local broker=$1
    local broker_dir="$CREDS_DIR/$broker-creds"
    local cnf_file="$broker_dir/$broker.cnf"
    local key_file="$broker_dir/$broker.key"
    local csr_file="$broker_dir/$broker.csr"
    local crt_file="$broker_dir/$broker.crt"
    local p12_file="$broker_dir/$broker.p12"
    
    echo "Генерация сертификата для $broker..."
    
    # Создаем директорию
    mkdir -p "$broker_dir"
    
    # Создаем конфигурацию
    create_broker_config "$broker"
    
    # Генерируем приватный ключ и CSR
    openssl req -new \
        -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$csr_file" \
        -config "$cnf_file" \
        -nodes
    
    # Подписываем сертификат CA
    openssl x509 -req \
        -days 3650 \
        -in "$csr_file" \
        -CA "$CA_CRT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$crt_file" \
        -extfile "$cnf_file" \
        -extensions v3_req
    
    # Создаем PKCS12 хранилище
    openssl pkcs12 -export \
        -in "$crt_file" \
        -inkey "$key_file" \
        -chain \
        -CAfile "$CA_PEM" \
        -name "$broker" \
        -out "$p12_file" \
        -password "pass:$PASSWORD"
    
    echo "✓ Сертификат для $broker создан"
}

# Создание keystore и truststore
create_keystores() {
    local broker=$1
    local broker_dir="$CREDS_DIR/$broker-creds"
    local p12_file="$broker_dir/$broker.p12"
    local pkcs12_keystore="$broker_dir/kafka.$broker.keystore.pkcs12"
    local jks_keystore="$broker_dir/$broker.keystore.jks"
    local jks_truststore="$broker_dir/$broker.truststore.jks"
    local pkcs12_truststore="$broker_dir/kafka.$broker.truststore.jks"
    
    echo "Создание keystore и truststore для $broker..."
    
    # Импортируем PKCS12 в PKCS12 keystore (для Kafka)
    keytool -importkeystore \
        -deststorepass "$PASSWORD" \
        -destkeystore "$pkcs12_keystore" \
        -srckeystore "$p12_file" \
        -deststoretype PKCS12 \
        -srcstoretype PKCS12 \
        -noprompt \
        -srcstorepass "$PASSWORD" 2>/dev/null || true
    
    # Импортируем PKCS12 в JKS keystore
    keytool -importkeystore \
        -srckeystore "$p12_file" \
        -srcstoretype PKCS12 \
        -destkeystore "$jks_keystore" \
        -deststoretype JKS \
        -deststorepass "$PASSWORD" \
        -srcstorepass "$PASSWORD" \
        -noprompt
    
    # Создаем JKS truststore и импортируем CA
    keytool -import \
        -file "$CA_CRT" \
        -alias ca \
        -keystore "$jks_truststore" \
        -storepass "$PASSWORD" \
        -noprompt
    
    # Создаем PKCS12 truststore и импортируем CA
    keytool -import \
        -file "$CA_CRT" \
        -alias ca \
        -keystore "$pkcs12_truststore" \
        -storetype PKCS12 \
        -storepass "$PASSWORD" \
        -noprompt
    
    echo "✓ Keystore и truststore для $broker созданы"
}

# Создание файлов с паролями
create_password_files() {
    local broker=$1
    local broker_dir="$CREDS_DIR/$broker-creds"
    
    echo "$PASSWORD" > "$broker_dir/${broker}_sslkey_creds"
    echo "$PASSWORD" > "$broker_dir/${broker}_keystore_creds"
    echo "$PASSWORD" > "$broker_dir/${broker}_truststore_creds"
}

# Создание JAAS конфигураций
create_jaas_configs() {
    echo "Создание JAAS конфигураций..."
    
    # Kafka Server JAAS
    cat > "$CREDS_DIR/kafka_server_jaas.conf" <<EOF
KafkaServer {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="$PASSWORD"
   user_admin="$PASSWORD"
   user_kafka="$PASSWORD"
   user_producer="$PASSWORD"
   user_consumer="$PASSWORD";
};

Client {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="$PASSWORD";
};
EOF
    
    # Schema Registry JAAS
    cat > "$CREDS_DIR/schema-registry.jaas.conf" <<EOF
KafkaClient {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="admin"
    password="$PASSWORD";
};
EOF
    
    # Zookeeper JAAS
    cat > "$CREDS_DIR/zookeeper.sasl.jaas.conf" <<EOF
Server {
    org.apache.zookeeper.server.auth.DigestLoginModule required
    user_admin="$PASSWORD";
};

Client {
    org.apache.zookeeper.server.auth.DigestLoginModule required
    username="admin"
    password="$PASSWORD";
};
EOF
    
    # Zookeeper JAAS для kafka-0-creds (используется в docker-compose)
    mkdir -p "$CREDS_DIR/kafka-0-creds"
    cp "$CREDS_DIR/zookeeper.sasl.jaas.conf" "$CREDS_DIR/kafka-0-creds/zookeeper.sasl.jaas.conf"
    
    echo "✓ JAAS конфигурации созданы"
}

# Создание admin.properties
create_admin_properties() {
    echo "Создание admin.properties..."
    
    cat > "$CREDS_DIR/admin.properties" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="$PASSWORD";
ssl.truststore.location=./credentials/kafka-0-creds/kafka-0.truststore.jks
ssl.truststore.password=$PASSWORD
ssl.keystore.location=./credentials/kafka-0-creds/kafka-0.keystore.jks
ssl.keystore.password=$PASSWORD
ssl.key.password=$PASSWORD
EOF
    
    # Копируем в каждую папку брокера
    for broker in "${BROKERS[@]}"; do
        mkdir -p "$CREDS_DIR/$broker-creds"
        cp "$CREDS_DIR/admin.properties" "$CREDS_DIR/$broker-creds/admin.properties"
    done
    
    echo "✓ admin.properties создан"
}

# Основная функция
main() {
    echo "Начало генерации сертификатов..."
    echo ""
    
    # Генерируем CA
    generate_ca
    
    # Генерируем сертификаты для каждого брокера
    for broker in "${BROKERS[@]}"; do
        echo ""
        generate_broker_cert "$broker"
        create_keystores "$broker"
        create_password_files "$broker"
    done
    
    # Создаем JAAS конфигурации
    echo ""
    create_jaas_configs
    
    # Создаем admin.properties
    create_admin_properties
    
    echo ""
    echo "=========================================="
    echo "✓ Все сертификаты успешно созданы!"
    echo "=========================================="
    echo "Сертификаты находятся в директории: $CREDS_DIR"
}

# Запуск
main

