package ru.myproject.test;

import java.util.List;
import java.util.Properties;
import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.util.Collections;

public class ConsumerApp {
        private static Properties getConsumerConfig() {
            Properties props = new Properties();
            props.put("bootstrap.servers", "localhost:19092");
            props.put("group.id", "consumer-group");
            props.put("enable.auto.commit", "true");
            props.put("auto.commit.interval.ms", "1000");
            props.put("session.timeout.ms", "30000");
            props.put("security.protocol", "SASL_SSL");

            // SASL configuration
            props.put("sasl.mechanism", "PLAIN");
            // Альтернативный вариант с проверкой:
            String jaasConfig = "org.apache.kafka.common.security.plain.PlainLoginModule required "
                + "username=\"consumer\" "
                + "password=\"your-password\";";
            props.put("sasl.jaas.config", jaasConfig);

            // SSL configuration
            props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG,
                "./credentials/kafka-0-creds/kafka-0.truststore.jks");
            props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "your-password");
            props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG,
                "./credentials/kafka-0-creds/kafka-0.keystore.jks");
            props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, "your-password");
            props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, "your-password");

            // Deserializers
            props.put("key.deserializer", StringDeserializer.class.getName());
            props.put("value.deserializer", StringDeserializer.class.getName());

            return props;
        }

        public static void main(String[] args) {
            try (Consumer<String, String> consumer = new KafkaConsumer<>(getConsumerConfig())) {
                // Подписка на topic-1 (разрешено)
                consumer.subscribe(List.of("topic-1"));

                // Подписка на topic-2 вызовет ошибку доступа
                consumer.subscribe(List.of("topic-2"));

                while (true) {
                    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
                    records.forEach(record -> {
                        System.out.printf("Получено: %s = %s%n", record.key(), record.value());
                    });
                }
            } catch (Exception e) {
                System.err.println("Ошибка: " + e.getMessage());
            }
        }
    }

