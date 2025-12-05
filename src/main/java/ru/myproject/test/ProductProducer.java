//package ru.myproject.test;
//
//import ru.myproject.client.Product;
//import ru.myproject.config.KafkaProperties;
//import org.apache.kafka.clients.producer.*;
//import com.fasterxml.jackson.databind.ObjectMapper;
//import com.fasterxml.jackson.core.type.TypeReference;
//
//import java.io.File;
//import java.io.IOException;
//import java.util.List;
//import java.util.concurrent.ExecutionException;
//
//public class ProductProducer {
//
//  private static final String BOOTSTRAP_SERVERS = "localhost:9092";
//  private static final String TOPIC_NAME = "products";
//  private static final String JSON_FILE_PATH = "products.json";
//
//  public static void main(String[] args) {
////    // Создаем Kafka producer
////    Properties properties = new Properties();
////    properties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
////    properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
////    properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
////
////    // Дополнительные настройки для надежности
////    properties.put(ProducerConfig.ACKS_CONFIG, "all");
////    properties.put(ProducerConfig.RETRIES_CONFIG, 3);
////    properties.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
//
//    try (KafkaProducer<String, String> producer = new KafkaProducer<>(KafkaProperties.getProducerConfig())) {
//
//      // Читаем данные из JSON файла
//      List<Product> products = readProductsFromFile(JSON_FILE_PATH);
//
//      // Отправляем каждый продукт в топик
//      for (Product product : products) {
//        sendProductToKafka(producer, product);
//      }
//
//      System.out.println("Все продукты успешно отправлены в топик " + TOPIC_NAME);
//
//    } catch (IOException e) {
//      System.err.println("Ошибка при чтении файла: " + e.getMessage());
//    } catch (Exception e) {
//      System.err.println("Ошибка при отправке данных: " + e.getMessage());
//    }
//  }
//
//  private static List<Product> readProductsFromFile(String filePath) throws IOException {
//    ObjectMapper objectMapper = new ObjectMapper();
//    return objectMapper.readValue(new File(filePath), new TypeReference<List<Product>>() {});
//  }
//
//  private static void sendProductToKafka(KafkaProducer<String, String> producer, Product product)
//          throws IOException, ExecutionException, InterruptedException {
//
//    ObjectMapper objectMapper = new ObjectMapper();
//    String productJson = objectMapper.writeValueAsString(product);
//
//    // Используем product_id в качестве ключа
////    String key = product.getProductid();
//
//    ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC_NAME, key, productJson);
//
//    // Отправляем синхронно для гарантии доставки
//    RecordMetadata metadata = producer.send(record).get();
//
////    System.out.println("Продукт отправлен: " + product.getProductid() +
////            ", partition: " + metadata.partition() +
////            ", offset: " + metadata.offset());
//  }
//}

