package ru.myproject.shop;

import ru.myproject.config.KafkaProperties;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.Properties;
import java.util.concurrent.ExecutionException;

public class BlockedProductsProducer {

    public static void main(String[] args) {
        String filePath = "data/blocked_products.txt";

        Properties props = KafkaProperties.getProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props);
             BufferedReader reader = new BufferedReader(new FileReader(filePath))) {

            String line;
            while ((line = reader.readLine()) != null) {
                String productId = line.trim().replace(",", "").replace(" ", "");

                if (!productId.isEmpty()) {
                    String jsonMessage = String.format("{\"product_id\": \"%s\"}", productId);
                    ProducerRecord<String, String> record =
                            new ProducerRecord<>(KafkaProperties.TOPIC_BLOCKED_PRODUCTS, productId, jsonMessage);
                    try {
                        producer.send(record).get(); // Ждем подтверждения
                        System.out.println("Successfully sent blocked product: " + productId);
                    } catch (InterruptedException | ExecutionException e) {
                        System.err.println("Error sending product " + productId + ": " + e.getMessage());
                    }
                }
            }

            producer.flush();
            System.out.println("All blocked products from file sent to Kafka topic: " + KafkaProperties.TOPIC_BLOCKED_PRODUCTS);

        } catch (IOException e) {
            System.err.println("Error reading file: " + e.getMessage());
        }
    }
}
