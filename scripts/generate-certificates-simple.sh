#!/bin/bash

# Упрощенный скрипт для генерации самоподписных SSL сертификатов для Kafka
# Без CA - каждый брокер получает самоподписной сертификат
# Использование: ./scripts/generate-certificates-simple.sh [password]

set -e

# Параметры
PASSWORD="${1:-your-password}"
CREDS_DIR="credentials"

# Брокеры
BROKERS=("kafka-0" "kafka-1" "kafka-2")

echo "=========================================="
echo "Генерация самоподписных SSL сертификатов"
echo "=========================================="
echo "Пароль: $PASSWORD"
echo ""

# Создаем директорию для кредов
mkdir -p "$CREDS_DIR"

# Функция для создания конфигурации брокера (самоподписной)
create_broker_config() {
    local broker=$1
    local cnf_file="$CREDS_DIR/$broker-creds/$broker.cnf"
    
    cat > "$cnf_file" <<EOF
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
EOF
}

# Генерация самоподписного сертификата для брокера
generate_self_signed_broker_cert() {
    local broker=$1
    local broker_dir="$CREDS_DIR/$broker-creds"
    local cnf_file="$broker_dir/$broker.cnf"
    local key_file="$broker_dir/$broker.key"
    local crt_file="$broker_dir/$broker.crt"
    local p12_file="$broker_dir/$broker.p12"
    
    echo "Генерация самоподписного сертификата для $broker..."
    
    # Создаем директорию
    mkdir -p "$broker_dir"
    
    # Создаем конфигурацию
    create_broker_config "$broker"
    
    # Генерируем самоподписной сертификат напрямую (без CA)
    openssl req -new -x509 \
        -days 3650 \
        -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$crt_file" \
        -config "$cnf_file" \
        -extensions v3_req \
        -nodes
    
    # Создаем PKCS12 хранилище (без CA chain)
    openssl pkcs12 -export \
        -in "$crt_file" \
        -inkey "$key_file" \
        -name "$broker" \
        -out "$p12_file" \
        -password "pass:$PASSWORD"
    
    echo "✓ Самоподписной сертификат для $broker создан"
}

# Создание keystore и truststore (без CA)
create_keystores() {
    local broker=$1
    local broker_dir="$CREDS_DIR/$broker-creds"
    local p12_file="$broker_dir/$broker.p12"
    local crt_file="$broker_dir/$broker.crt"
    local jks_keystore="$broker_dir/$broker.keystore.jks"
    local jks_truststore="$broker_dir/$broker.truststore.jks"
    local pkcs12_keystore="$broker_dir/kafka.$broker.keystore.pkcs12"
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
    
    # Создаем JKS truststore и импортируем сам сертификат брокера
    keytool -import \
        -file "$crt_file" \
        -alias "$broker" \
        -keystore "$jks_truststore" \
        -storepass "$PASSWORD" \
        -noprompt
    
    # Создаем PKCS12 truststore
    keytool -import \
        -file "$crt_file" \
        -alias "$broker" \
        -keystore "$pkcs12_truststore" \
        -storetype PKCS12 \
        -storepass "$PASSWORD" \
        -noprompt
    
    echo "✓ Keystore и truststore для $broker созданы"
}

# Создание общего truststore со всеми сертификатами брокеров
create_common_truststore() {
    echo "Создание общего truststore со всеми сертификатами..."
    
    local common_truststore="$CREDS_DIR/kafka-0-creds/kafka-0.truststore.jks"
    
    # Используем truststore первого брокера как общий
    # Импортируем сертификаты всех брокеров
    for broker in "${BROKERS[@]}"; do
        local crt_file="$CREDS_DIR/$broker-creds/$broker.crt"
        if [ -f "$crt_file" ]; then
            keytool -import \
                -file "$crt_file" \
                -alias "$broker" \
                -keystore "$common_truststore" \
                -storepass "$PASSWORD" \
                -noprompt
        fi
    done
    
    # Копируем общий truststore в папки других брокеров
    for broker in "${BROKERS[@]}"; do
        if [ "$broker" != "kafka-0" ]; then
            local broker_truststore="$CREDS_DIR/$broker-creds/$broker.truststore.jks"
            cp "$common_truststore" "$broker_truststore"
        fi
    done
    
    echo "✓ Общий truststore создан"
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
    
    # Zookeeper JAAS для kafka-0-creds
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
    echo "Начало генерации самоподписных сертификатов..."
    echo "Примечание: Используются самоподписные сертификаты без CA"
    echo ""
    
    # Генерируем самоподписные сертификаты для каждого брокера
    for broker in "${BROKERS[@]}"; do
        echo ""
        generate_self_signed_broker_cert "$broker"
        create_keystores "$broker"
        create_password_files "$broker"
    done
    
    # Создаем общий truststore
    echo ""
    create_common_truststore
    
    # Создаем JAAS конфигурации
    echo ""
    create_jaas_configs
    
    # Создаем admin.properties
    create_admin_properties
    
    echo ""
    echo "=========================================="
    echo "✓ Все самоподписные сертификаты созданы!"
    echo "=========================================="
    echo "Сертификаты находятся в директории: $CREDS_DIR"
    echo "Примечание: CA файлы не требуются для этого варианта"
}

# Запуск
main

