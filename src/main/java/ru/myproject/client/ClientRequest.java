package ru.myproject.client;

import ru.myproject.config.KafkaProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.streams.StreamsConfig;

import java.io.File;
import java.io.IOException;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

public class ClientRequest {

    private static final String USER_QUERY_TOPIC = "userQuery";
    private static final String RESPONSE_TOPIC = "response";
    private static final String RECOMMENDATIONS_TOPIC = "recommendations";
    private static final String FILE_STORE = "./data/connector-output/products-final.json";
    private static final long YEARS_LAST = 3;

    private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());

    private static KafkaProducer<String, String> kafkaProducer;

    public static void main(String[] args) {
        try (Scanner scanner = new Scanner(System.in)) {
            initializeKafkaProducer(); // Initialize Kafka producer once
            while (true) {
                try {
                    System.out.print("Введите название товара для поиска (или 'exit' для выхода): ");
                    String productName = scanner.nextLine().trim();

                    if ("exit".equalsIgnoreCase(productName)) {
                        System.out.println("Завершение работы...");
                        break;
                    }

                    if (productName.isEmpty()) {
                        System.err.println("Ошибка: название товара не может быть пустым");
                        continue;
                    }
                    List<Product> products = readProductsFromFile(FILE_STORE);

                    Product foundProduct = findProductByName(products, productName);

                    if (foundProduct != null) {
                        logUserQuery(productName, foundProduct.getProductId());
                        sendProductResponse(foundProduct);
                        sendRecommendations(products, foundProduct);
                        System.out.println("Товар найден: " + foundProduct.getName());
                        System.out.println("ID товара: " + foundProduct.getProductId());
                        Thread.sleep(500);
                    } else {
                        logUserQuery(productName, null);
                        System.out.println("Товар с названием '" + productName + "' не найден");
                    }

                } catch (Exception e) {
                    System.err.println("Ошибка при обработке запроса: " + e.getMessage());
                    e.printStackTrace();
                }
            }
        } catch (Exception e) {
            System.err.println("Критическая ошибка при запуске приложения: " + e.getMessage());
        } finally {
            if (kafkaProducer != null) {
                kafkaProducer.close(); // :cite[3]
                System.out.println("Kafka producer закрыт.");
            }
            System.out.println("Сканнер закрыт.");
        }
    }

    private static List<Product> readProductsFromFile(String filePath) throws IOException {
        File file = new File(filePath);
        if (!file.exists()) {
            throw new IOException("Файл не найден: " + filePath);
        }

        List<Product> products = new ArrayList<>();
        Scanner scanner = new Scanner(file);

        while (scanner.hasNextLine()) {
            String line = scanner.nextLine().trim();
            if (!line.isEmpty()) {
                try {
                    Product product = parseProductFromString(line);
                    products.add(product);
                } catch (Exception e) {
                    System.err.println("Ошибка парсинга строки: " + line);
                    e.printStackTrace();
                }
            }
        }
        scanner.close();

        return products;

    }

    private static Product parseProductFromString(String line) {
        String content = line.substring(1, line.length() - 1).trim();

        Product product = new Product();
        Map<String, String> fields = parseKeyValuePairs(content);

        product.setStoreId(fields.get("store_id"));
        product.setDescription(fields.get("description"));
        product.setCreatedAt(parseDateTime(fields.get("created_at")));
        product.setIndex(fields.get("index"));
        product.setTags(parseList(fields.get("tags")));
        product.setUpdatedAt(parseDateTime(fields.get("updated_at")));
        product.setProductId(fields.get("product_id"));
        product.setName(fields.get("name"));
        product.setCategory(fields.get("category"));
        product.setSku(fields.get("sku"));
        product.setBrand(fields.get("brand"));

        product.setImages(parseImages(fields.get("images")));
        product.setSpecifications(parseSpecifications(fields.get("specifications")));
        product.setPrice(parsePrice(fields.get("price")));
        product.setStock(parseStock(fields.get("stock")));

        return product;
    }

    private static Map<String, String> parseKeyValuePairs(String content) {
        Map<String, String> result = new HashMap<>();
        int braceLevel = 0;
        int bracketLevel = 0;
        StringBuilder currentKey = new StringBuilder();
        StringBuilder currentValue = new StringBuilder();
        boolean inKey = true;

        for (int i = 0; i < content.length(); i++) {
            char c = content.charAt(i);

            if (c == '{') braceLevel++;
            if (c == '}') braceLevel--;
            if (c == '[') bracketLevel++;
            if (c == ']') bracketLevel--;

            if (c == ',' && braceLevel == 0 && bracketLevel == 0) {
                if (currentKey.length() > 0 && currentValue.length() > 0) {
                    result.put(currentKey.toString().trim(), currentValue.toString().trim());
                }
                currentKey.setLength(0);
                currentValue.setLength(0);
                inKey = true;
                continue;
            }

            if (c == '=' && braceLevel == 0 && bracketLevel == 0 && inKey) {
                inKey = false;
                continue;
            }

            if (inKey) {
                currentKey.append(c);
            } else {
                currentValue.append(c);
            }
        }

        if (currentKey.length() > 0 && currentValue.length() > 0) {
            result.put(currentKey.toString().trim(), currentValue.toString().trim());
        }

        return result;
    }

    private static List<Image> parseImages(String imagesString) {
        List<Image> images = new ArrayList<>();
        if (imagesString == null || !imagesString.startsWith("[")) {
            return images;
        }

        String content = imagesString.substring(1, imagesString.length() - 1).trim();
        List<String> imageStrings = splitByComma(content, '{', '}');

        for (String imageStr : imageStrings) {
            if (imageStr.startsWith("{")) {
                Map<String, String> imageFields = parseKeyValuePairs(imageStr.substring(1, imageStr.length() - 1));
                Image image = new Image();
                image.setAlt(imageFields.get("alt"));
                image.setUrl(imageFields.get("url"));
                images.add(image);
            }
        }

        return images;
    }

    private static Specifications parseSpecifications(String specString) {
        if (specString == null || !specString.startsWith("{")) {
            return null;
        }

        Map<String, String> specFields = parseKeyValuePairs(specString.substring(1, specString.length() - 1));
        Specifications specs = new Specifications();
        specs.setWaterResistance(specFields.get("water_resistance"));
        specs.setWeight(specFields.get("weight"));
        specs.setBatteryLife(specFields.get("battery_life"));
        specs.setDimensions(specFields.get("dimensions"));
        return specs;
    }

    private static Price parsePrice(String priceString) {
        if (priceString == null || !priceString.startsWith("{")) {
            return null;
        }

        Map<String, String> priceFields = parseKeyValuePairs(priceString.substring(1, priceString.length() - 1));
        Price price = new Price();
        price.setAmount(Double.parseDouble(priceFields.get("amount")));
        price.setCurrency(priceFields.get("currency"));
        return price;
    }

    private static Stock parseStock(String stockString) {
        if (stockString == null || !stockString.startsWith("{")) {
            return null;
        }

        Map<String, String> stockFields = parseKeyValuePairs(stockString.substring(1, stockString.length() - 1));
        Stock stock = new Stock();
        stock.setAvailable(Integer.parseInt(stockFields.get("available")));
        stock.setReserved(Integer.parseInt(stockFields.get("reserved")));
        return stock;
    }

    private static List<String> parseList(String listString) {
        List<String> result = new ArrayList<>();
        if (listString == null || !listString.startsWith("[")) {
            return result;
        }

        String content = listString.substring(1, listString.length() - 1).trim();
        String[] items = content.split(", ");
        for (String item : items) {
            result.add(item.trim());
        }
        return result;
    }

    private static LocalDateTime parseDateTime(String dateTimeString) {
        if (dateTimeString == null) {
            return null;
        }
        String cleanString = dateTimeString.replace("\"", "");
        return ZonedDateTime.parse(cleanString).toLocalDateTime();
    }

    private static List<String> splitByComma(String content, char openChar, char closeChar) {
        List<String> result = new ArrayList<>();
        int level = 0;
        int start = 0;

        for (int i = 0; i < content.length(); i++) {
            char c = content.charAt(i);
            if (c == openChar) level++;
            if (c == closeChar) level--;

            if (c == ',' && level == 0) {
                result.add(content.substring(start, i).trim());
                start = i + 1;
            }
        }
        result.add(content.substring(start).trim());
        return result;
    }

    private static void initializeKafkaProducer() {
        Properties props = KafkaProperties.getProducerConfig();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "product-filter-app");
        kafkaProducer = new KafkaProducer<>(props);
    }

    private static Product findProductByName(List<Product> products, String productName) {
        return products.stream()
                .filter(p -> p.getName() != null &&
                        p.getName().toLowerCase().contains(productName.toLowerCase()))
                .findFirst()
                .orElse(null);
    }

    private static void logUserQuery(String productName, String productId) throws IOException {
        Map<String, Object> queryLog = new HashMap<>();
        queryLog.put("timestamp", LocalDateTime.now().toString());
        queryLog.put("product_name_query", productName);
        queryLog.put("found_product_id", productId);
        queryLog.put("query_type", "product_name_search");

        String queryJson = objectMapper.writeValueAsString(queryLog);
        ProducerRecord<String, String> record = new ProducerRecord<>(USER_QUERY_TOPIC, queryJson);

        kafkaProducer.send(record, (metadata, exception) -> {
            if (exception != null) {
                System.err.println("Ошибка отправки запроса: " + exception.getMessage());
            } else {
                System.out.println("Запрос записан в топик " + USER_QUERY_TOPIC);
            }
        });
    }

    private static void sendProductResponse(Product product) throws IOException {
        Map<String, String> responseData = new HashMap<>();
        responseData.put("id", product.getProductId());
        responseData.put("name", product.getName());
        responseData.put("category", product.getCategory());

        String responseJson = objectMapper.writeValueAsString(responseData);
        ProducerRecord<String, String> record =
                new ProducerRecord<>(RESPONSE_TOPIC, product.getProductId(), responseJson);

        kafkaProducer.send(record, (metadata, exception) -> {
            if (exception != null) {
                System.err.println("Ошибка отправки ответа: " + exception.getMessage());
            } else {
                System.out.println("Ответ отправлен в топик " + RESPONSE_TOPIC);
            }
        });

        kafkaProducer.flush();
    }

    private static void sendRecommendations(List<Product> products, Product foundProduct) throws IOException {
        LocalDateTime oneYearAgo = LocalDateTime.now().minus(YEARS_LAST, ChronoUnit.YEARS);

        List<Product> recommendedProducts = products.stream()
                .filter(p -> p.getBrand() != null && p.getBrand().equals(foundProduct.getBrand()))
                .filter(p -> p.getCategory() != null && p.getCategory().equals(foundProduct.getCategory()))
                .filter(p -> p.getUpdatedAt() != null && p.getUpdatedAt().isAfter(oneYearAgo))
                .filter(p -> !p.getProductId().equals(foundProduct.getProductId())) // Exclude the found product
                .collect(Collectors.toList());

        for (Product recommended : recommendedProducts) {
            Map<String, Object> recommendationData = new HashMap<>();
            recommendationData.put("id", recommended.getProductId());
            recommendationData.put("brand", recommended.getBrand());
            recommendationData.put("name", recommended.getName());
            recommendationData.put("category", recommended.getCategory());

            String recommendationJson = objectMapper.writeValueAsString(recommendationData);
            ProducerRecord<String, String> record =
                    new ProducerRecord<>(RECOMMENDATIONS_TOPIC, recommended.getProductId(), recommendationJson);

            kafkaProducer.send(record, (metadata, exception) -> {
                if (exception != null) {
                    System.err.println("Ошибка отправки ответа: " + exception.getMessage());
                }
            });
        }
        System.out.println("Ответ отправлен в топик " + RECOMMENDATIONS_TOPIC);
        kafkaProducer.flush();
        System.out.println("Найдено рекомендаций: " + recommendedProducts.size());
    }
}
