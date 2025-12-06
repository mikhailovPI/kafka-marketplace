package ru.myproject.shop;

import ru.myproject.config.AppConfig;
import ru.myproject.config.KafkaProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Produced;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashSet;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.CountDownLatch;

@Slf4j
public class ProductFilterStream {
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final Set<String> blockedProductIds = new HashSet<>();

    public static void main(String[] args) {
        sendJsonFileToKafka(ru.myproject.config.AppConfig.getFilePathProducts());
        startStreamsProcessing();
    }

    private static void sendJsonFileToKafka(String filename) {
        Properties props = KafkaProperties.getProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            String content = new String(Files.readAllBytes(Paths.get(filename)));
            JsonNode productsArray = mapper.readTree(content);
            if (productsArray.isArray()) {
                for (JsonNode product : productsArray) {
                    String productJson = product.toString();
                    String productId = product.get("product_id").asText();
                    ProducerRecord<String, String> record =
                            new ProducerRecord<>(KafkaProperties.TOPIC_INPUT_JSON_STREAM(), productId, productJson);

                    producer.send(record, (metadata, exception) -> {
                        if (exception != null) {
                            log.error("Error sending product {}: {}", productId, exception.getMessage(), exception);
                        } else {
                            log.debug("Product sent to Kafka: {}, partition: {}, offset: {}",
                                    productId, metadata.partition(), metadata.offset());
                        }
                    });
                }
            }
            producer.flush();
            log.debug("All products from file sent to Kafka topic: {}", KafkaProperties.TOPIC_INPUT_JSON_STREAM());

        } catch (IOException e) {
            log.error("Error reading file: {}", e.getMessage(), e);
        }
    }

    private static void startStreamsProcessing() {
        Properties props = KafkaProperties.getStreamsConfig();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, 
                AppConfig.getProperty("kafka.streams.application-id"));

        StreamsBuilder builder = new StreamsBuilder();
        builder.stream(KafkaProperties.TOPIC_BLOCKED_PRODUCTS(),
                        Consumed.with(Serdes.String(), Serdes.String()))
                .foreach((key, value) -> {
                    try {
                        if (value != null) {
                            JsonNode blockedProduct = mapper.readTree(value);
                            String productId = blockedProduct.get("product_id").asText();
                            blockedProductIds.add(productId);
                            log.debug("Blocked product added: {}, total blocked: {}", productId, blockedProductIds.size());
                        }
                    } catch (Exception e) {
                        log.error("Error parsing blocked product JSON: {}", e.getMessage(), e);
                    }
                });
        builder.stream(KafkaProperties.TOPIC_INPUT_JSON_STREAM(),
                        Consumed.with(Serdes.String(), Serdes.String()))
                .filter((key, value) -> {
                    try {
                        if (value == null) {
                            log.debug("Skipping null value");
                            return false;
                        }

                        JsonNode product = mapper.readTree(value);
                        if (!product.has("product_id")) {
                            log.debug("Skipping product without product_id");
                            return false;
                        }

                        String productId = product.get("product_id").asText();
                        boolean isBlocked = blockedProductIds.contains(productId);

                        if (!isBlocked) {
                            log.debug("Product allowed: {}", productId);
                            return true;
                        } else {
                            log.debug("Product blocked: {}", productId);
                            return false;
                        }
                    } catch (Exception e) {
                        log.error("Error parsing product JSON: {}", e.getMessage(), e);
                        return false;
                    }
                })
                .to(KafkaProperties.TOPIC_PRODUCTS(), Produced.with(Serdes.String(), Serdes.String()));

        KafkaStreams streams = new KafkaStreams(builder.build(), props);

        final CountDownLatch latch = new CountDownLatch(1);

        Runtime.getRuntime().addShutdownHook(new Thread("product-filter-shutdown-hook") {
            @Override
            public void run() {
                log.debug("Shutting down streams application...");
                streams.close();
                latch.countDown();
                log.debug("Streams application closed");
            }
        });

        try {
            streams.start();
            log.debug("Streams application started");
            latch.await();
        } catch (final Throwable e) {
            log.error("Error starting streams application: {}", e.getMessage(), e);
            System.exit(1);
        }
    }
}
