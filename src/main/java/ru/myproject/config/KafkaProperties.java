package ru.myproject.config;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsConfig;

import java.util.Properties;

public class KafkaProperties {
    public static Properties getProducerConfig() {
        Properties props = new Properties();

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:19092,localhost:29092,localhost:39092");
        props.put("security.protocol", "SASL_SSL");
        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "./credentials/kafka-0-creds/kafka-0.truststore.jks");
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "your-password");
        props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, "./credentials/kafka-0-creds/kafka-0.keystore.jks");
        props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, "your-password");
        props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, "your-password");

        props.put("sasl.mechanism", "PLAIN");
        props.put("sasl.jaas.config",
                "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                        "username=\"admin\" password=\"your-password\";");

        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");

        // Для надежной доставки
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, "3");

        return props;
    }

    public static Properties getStreamsConfig() {
        Properties props = new Properties();

        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:19092,localhost:29092,localhost:39092");
        props.put("security.protocol", "SASL_SSL");
        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "./credentials/kafka-0-creds/kafka-0.truststore.jks");
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "your-password");
        props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, "./credentials/kafka-0-creds/kafka-0.keystore.jks");
        props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, "your-password");
        props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, "your-password");

        props.put("sasl.mechanism", "PLAIN");
        props.put("sasl.jaas.config",
                "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                        "username=\"admin\" password=\"your-password\";");

        // Streams конфигурация
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);

        return props;
    }

    // Константы для имен топиков
    public static final String TOPIC_BLOCKED_PRODUCTS = "blockedProducts";
    public static final String TOPIC_PRODUCTS = "products";
    public static final String TOPIC_INPUT_JSON_STREAM = "inputJsonStream";
}

