package ru.myproject.config;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsConfig;

import java.util.Properties;

public class KafkaProperties {

    public static String TOPIC_BLOCKED_PRODUCTS() {
        return AppConfig.getKafkaTopicBlockedProducts();
    }

    public static String TOPIC_PRODUCTS() {
        return AppConfig.getKafkaTopicProducts();
    }

    public static String TOPIC_INPUT_JSON_STREAM() {
        return AppConfig.getKafkaTopicInputJsonStream();
    }

    public static Properties getProducerConfig() {
        Properties props = new Properties();

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, 
                AppConfig.getProperty("kafka.producer.bootstrap-servers"));
        props.put("security.protocol", 
                AppConfig.getProperty("kafka.producer.security-protocol"));
        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, 
                AppConfig.getProperty("kafka.producer.ssl.truststore-location"));
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.producer.ssl.truststore-password"));
        props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, 
                AppConfig.getProperty("kafka.producer.ssl.keystore-location"));
        props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.producer.ssl.keystore-password"));
        props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.producer.ssl.key-password"));

        props.put("sasl.mechanism", 
                AppConfig.getProperty("kafka.producer.sasl.mechanism"));
        String saslUsername = AppConfig.getProperty("kafka.producer.sasl.username");
        String saslPassword = AppConfig.getProperty("kafka.producer.sasl.password");
        props.put("sasl.jaas.config",
                "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                        "username=\"" + saslUsername + "\" password=\"" + saslPassword + "\";");

        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");

        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, 
                AppConfig.getProperty("kafka.producer.enable-idempotence"));
        props.put(ProducerConfig.ACKS_CONFIG, 
                AppConfig.getProperty("kafka.producer.acks"));
        props.put(ProducerConfig.RETRIES_CONFIG, 
                AppConfig.getProperty("kafka.producer.retries"));

        return props;
    }

    public static Properties getStreamsConfig() {
        Properties props = new Properties();

        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, 
                AppConfig.getProperty("kafka.streams.bootstrap-servers"));
        props.put("security.protocol", 
                AppConfig.getProperty("kafka.streams.security-protocol"));
        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, 
                AppConfig.getProperty("kafka.streams.ssl.truststore-location"));
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.streams.ssl.truststore-password"));
        props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, 
                AppConfig.getProperty("kafka.streams.ssl.keystore-location"));
        props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.streams.ssl.keystore-password"));
        props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, 
                AppConfig.getProperty("kafka.streams.ssl.key-password"));

        props.put("sasl.mechanism", 
                AppConfig.getProperty("kafka.streams.sasl.mechanism"));
        String saslUsername = AppConfig.getProperty("kafka.streams.sasl.username");
        String saslPassword = AppConfig.getProperty("kafka.streams.sasl.password");
        props.put("sasl.jaas.config",
                "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                        "username=\"" + saslUsername + "\" password=\"" + saslPassword + "\";");

        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, 
                AppConfig.getProperty("kafka.streams.processing-guarantee"));

        return props;
    }
}
