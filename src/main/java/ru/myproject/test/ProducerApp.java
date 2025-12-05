package ru.myproject.test;

import java.util.Properties;
import java.util.concurrent.ExecutionException;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.StringSerializer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ProducerApp {
  private static final Logger log = LoggerFactory.getLogger(ProducerApp.class);

  private static Properties getProducerConfig() {
    Properties props = new Properties();
    props.put("bootstrap.servers", "localhost:19092,localhost:29092,localhost:39092");
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

    props.put("key.serializer", StringSerializer.class.getName());
    props.put("value.serializer", StringSerializer.class.getName());

    // Для надежной доставки
    props.put("acks", "all");
    props.put("retries", 3);
    props.put("enable.idempotence", true);

    return props;
  }

  public static void main(String[] args) {
    try (Producer<String, String> producer = new KafkaProducer<>(getProducerConfig())) {
      // Отправка в topic-1 с подтверждением
      ProducerRecord<String, String> record1 = new ProducerRecord<>("topic-1", "key1", "value1");
      producer.send(record1, (metadata, exception) -> {
        if (exception != null) {
          log.error("Error sending message to topic-1", exception);
        } else {
          log.info("Sent message to topic-1, partition {}, offset {}",
              metadata.partition(), metadata.offset());
        }
      }).get(); // Блокируем до получения подтверждения

      // Отправка в topic-2 с подтверждением
      ProducerRecord<String, String> record2 = new ProducerRecord<>("topic-2", "key2", "value2");
      producer.send(record2, (metadata, exception) -> {
        if (exception != null) {
          log.error("Error sending message to topic-2", exception);
        } else {
          log.info("Sent message to topic-2, partition {}, offset {}",
              metadata.partition(), metadata.offset());
        }
      }).get(); // Блокируем до получения подтверждения

      log.info("All messages sent successfully");
    } catch (InterruptedException | ExecutionException e) {
      log.error("Exception occurred while sending messages", e);
      Thread.currentThread().interrupt();
    }
  }
}

