package ru.myproject.shop;

import ru.myproject.config.AppConfig;
import ru.myproject.config.KafkaProperties;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.Properties;
import java.util.concurrent.ExecutionException;

@Slf4j
public class BlockedProductsProducer {

    public static void main(String[] args) {
        String filePath = AppConfig.getFilePathBlockedProducts();

        Properties props = KafkaProperties.getProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props);
             BufferedReader reader = new BufferedReader(new FileReader(filePath))) {

            String line;
            while ((line = reader.readLine()) != null) {
                String productId = line.trim().replace(",", "").replace(" ", "");

                if (!productId.isEmpty()) {
                    String jsonMessage = String.format("{\"product_id\": \"%s\"}", productId);
                    ProducerRecord<String, String> record =
                            new ProducerRecord<>(KafkaProperties.TOPIC_BLOCKED_PRODUCTS(), productId, jsonMessage);
                    try {
                        producer.send(record).get(); // Ждем подтверждения
                        log.debug("Successfully sent blocked product: {}", productId);
                    } catch (InterruptedException | ExecutionException e) {
                        log.error("Error sending product {}: {}", productId, e.getMessage(), e);
                    }
                }
            }

            producer.flush();
            log.debug("All blocked products from file sent to Kafka topic: {}", KafkaProperties.TOPIC_BLOCKED_PRODUCTS());

        } catch (IOException e) {
            log.error("Error reading file: {}", e.getMessage(), e);
        }
    }
}
