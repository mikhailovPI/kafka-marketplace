package ru.myproject.spark;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.spark.api.java.JavaRDD;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.functions;
import ru.myproject.config.KafkaPropertiesDestination;

import java.time.LocalDateTime;
import java.util.Properties;
import java.util.stream.Collectors;

public class SparkReadMain {

    public static void main(String[] args) {

        Properties props = KafkaPropertiesDestination.getConfig();
        String appName = System.getProperty("spark.app.name", "SparkReadHdfsExample");
        String master = System.getProperty("spark.master", "local[*]");
        String inputPath = System.getProperty("hdfs.input", "hdfs://127.0.0.1:9000/data/products");
        String kafkaBootstrapServers = System.getProperty("kafka.bootstrap.servers", props.getProperty("bootstrap.servers"));
        String outputTopic = System.getProperty("kafka.output.topic", props.getProperty("topic_data_analysis"));

        SparkSession spark = SparkSession.builder()
                .appName(appName)
                .master(master)
                .config("spark.hadoop.fs.defaultFS", "hdfs://127.0.0.1:9000")
                .config("spark.hadoop.mapreduce.input.fileinputformat.input.dir.recursive", "true")
                .config("spark.sql.adaptive.enabled", "true")
                .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
                .config("spark.hadoop.dfs.client.use.datanode.hostname", "true")
                .config("spark.hadoop.dfs.datanode.use.datanode.hostname", "true")
                .config("spark.hadoop.fs.hdfs.impl", "org.apache.hadoop.hdfs.DistributedFileSystem")
                .config("spark.hadoop.dfs.client.socket-timeout", "60000")
                .config("spark.hadoop.dfs.datanode.socket.write.timeout", "60000")
                .config("spark.hadoop.ipc.client.connect.timeout", "60000")
                .config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint")
                .getOrCreate();

        try {
            JavaSparkContext sc = new JavaSparkContext(spark.sparkContext());
            sc.hadoopConfiguration().set("fs.defaultFS", "hdfs://127.0.0.1:9000");
            sc.hadoopConfiguration().set("mapreduce.input.fileinputformat.input.dir.recursive", "true");
            sc.hadoopConfiguration().set("dfs.client.use.datanode.hostname", "true");
            sc.hadoopConfiguration().set("dfs.datanode.use.datanode.hostname", "true");

            System.out.println("Конфигурация SparkSession:");
            System.out.println("App Name: " + appName);
            System.out.println("Master: " + master);
            System.out.println("Input Path: " + inputPath);
            System.out.println("Kafka Bootstrap Servers: " + kafkaBootstrapServers);
            System.out.println("Output Topic: " + outputTopic);
            System.out.println("Default FS: " + sc.hadoopConfiguration().get("fs.defaultFS"));

            System.out.println("Начинаем чтение JSON данных из HDFS...");
            Dataset<Row> df = spark.read()
                    .option("multiline", true)
                    .json(inputPath);

            System.out.println("Схема исходных данных:");
            df.printSchema();
            System.out.println("Количество строк в DataFrame: " + df.count());
            System.out.println("Первые 20 строк исходных данных:");
            df.show(20, false);
            System.out.println("Выполняем анализ данных...");

            Dataset<Row> analysisResult = df
                    .groupBy("brand", "category")
                    .agg(functions.count("product_id").alias("product_count"));

            System.out.println("Результат анализа (количество товаров по бренду и категории):");
            analysisResult.show(20, false);

            JavaRDD<String> kafkaJsonRDDJackson = analysisResult.toJavaRDD().map(row -> {
                ObjectMapper mapper = new ObjectMapper();
                ObjectNode jsonNode = mapper.createObjectNode();

                jsonNode.put("brand", row.isNullAt(0) ? "unknown" : row.getString(0));
                jsonNode.put("category", row.isNullAt(1) ? "unknown" : row.getString(1));
                jsonNode.put("product_count", row.getLong(2));

                return mapper.writeValueAsString(jsonNode);
            });

            String resultString = kafkaJsonRDDJackson.collect().stream()
                    .collect(Collectors.joining("\n"));

            System.out.println("Данные для отправки в Kafka: " + resultString);
            System.out.println("Отправляем данные в топик Kafka: " + outputTopic);

            String dateTime = LocalDateTime.now().toString();
            ProducerRecord<String, String> record = new ProducerRecord<>(outputTopic, dateTime, resultString);
            try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
                producer.send(record, (metadata, exception) -> {
                    if (exception != null) {
                        System.err.println("Error sending product " + dateTime + ": " + exception.getMessage());
                    } else {
                        System.out.println("Successfully sent product: " + dateTime +
                                ", partition: " + metadata.partition() +
                                ", offset: " + metadata.offset());
                    }
                });
            }

            System.out.println("Данные успешно отправлены в Kafka топик: " + outputTopic);

            System.out.println("\n=== СТАТИСТИКА АНАЛИЗА ===");
            System.out.println("Общее количество брендов: " + analysisResult.select("brand").distinct().count());
            System.out.println("Общее количество категорий: " + analysisResult.select("category").distinct().count());
            System.out.println("Общее количество товаров: " + analysisResult.agg(functions.sum("product_count")).first().getLong(0));

            System.out.println("\nТоп-5 комбинаций бренд-категория:");
            analysisResult.limit(5).show(false);

        } catch (Exception e) {
            System.err.println("Ошибка при выполнении Spark job:");
            e.printStackTrace();
        } finally {
            spark.stop();
            System.out.println("Spark приложение завершено.");
        }
    }
}
