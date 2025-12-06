package ru.myproject.spark;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.spark.api.java.JavaRDD;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.functions;
import ru.myproject.config.AppConfig;
import ru.myproject.config.KafkaPropertiesDestination;

import java.time.LocalDateTime;
import java.util.Properties;
import java.util.stream.Collectors;

@Slf4j
public class SparkReadMain {

    public static void main(String[] args) {

        Properties props = KafkaPropertiesDestination.getConfig();
        String appName = System.getProperty("spark.app.name", AppConfig.getSparkAppName());
        String master = System.getProperty("spark.master", AppConfig.getSparkMaster());
        String inputPath = System.getProperty("hdfs.input", AppConfig.getSparkHdfsInput());
        String kafkaBootstrapServers = System.getProperty("kafka.bootstrap.servers", 
                props.getProperty("bootstrap.servers"));
        String outputTopic = System.getProperty("kafka.output.topic", 
                props.getProperty("topic_data_analysis"));

        SparkSession spark = SparkSession.builder()
                .appName(appName)
                .master(master)
                .config("spark.hadoop.fs.defaultFS", AppConfig.getSparkHdfsDefaultFs())
                .config("spark.hadoop.mapreduce.input.fileinputformat.input.dir.recursive", "true")
                .config("spark.sql.adaptive.enabled", "true")
                .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
                .config("spark.hadoop.dfs.client.use.datanode.hostname", "true")
                .config("spark.hadoop.dfs.datanode.use.datanode.hostname", "true")
                .config("spark.hadoop.fs.hdfs.impl", "org.apache.hadoop.hdfs.DistributedFileSystem")
                .config("spark.hadoop.dfs.client.socket-timeout", 
                        String.valueOf(AppConfig.getSparkHadoopDfsClientSocketTimeout()))
                .config("spark.hadoop.dfs.datanode.socket.write.timeout", 
                        String.valueOf(AppConfig.getSparkHadoopDfsDatanodeSocketWriteTimeout()))
                .config("spark.hadoop.ipc.client.connect.timeout", 
                        String.valueOf(AppConfig.getSparkHadoopIpcClientConnectTimeout()))
                .config("spark.sql.streaming.checkpointLocation", AppConfig.getSparkHdfsCheckpointLocation())
                .getOrCreate();

        try {
            JavaSparkContext sc = new JavaSparkContext(spark.sparkContext());
            sc.hadoopConfiguration().set("fs.defaultFS", AppConfig.getSparkHdfsDefaultFs());
            sc.hadoopConfiguration().set("mapreduce.input.fileinputformat.input.dir.recursive", "true");
            sc.hadoopConfiguration().set("dfs.client.use.datanode.hostname", "true");
            sc.hadoopConfiguration().set("dfs.datanode.use.datanode.hostname", "true");

            log.debug("Конфигурация SparkSession:");
            log.debug("App Name: {}", appName);
            log.debug("Master: {}", master);
            log.debug("Input Path: {}", inputPath);
            log.debug("Kafka Bootstrap Servers: {}", kafkaBootstrapServers);
            log.debug("Output Topic: {}", outputTopic);
            log.debug("Default FS: {}", sc.hadoopConfiguration().get("fs.defaultFS"));

            log.debug("Начинаем чтение JSON данных из HDFS...");
            Dataset<Row> df = spark.read()
                    .option("multiline", true)
                    .json(inputPath);

            log.debug("Схема исходных данных:");
            df.printSchema();
            log.debug("Количество строк в DataFrame: {}", df.count());
            log.debug("Первые 20 строк исходных данных:");
            df.show(20, false);
            log.debug("Выполняем анализ данных...");

            Dataset<Row> analysisResult = df
                    .groupBy("brand", "category")
                    .agg(functions.count("product_id").alias("product_count"));

            log.debug("Результат анализа (количество товаров по бренду и категории):");
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

            log.debug("Данные для отправки в Kafka: {}", resultString);
            log.debug("Отправляем данные в топик Kafka: {}", outputTopic);

            String dateTime = LocalDateTime.now().toString();
            ProducerRecord<String, String> record = new ProducerRecord<>(outputTopic, dateTime, resultString);
            try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
                producer.send(record, (metadata, exception) -> {
                    if (exception != null) {
                        log.error("Error sending product {}: {}", dateTime, exception.getMessage(), exception);
                    } else {
                        log.debug("Successfully sent product: {}, partition: {}, offset: {}",
                                dateTime, metadata.partition(), metadata.offset());
                    }
                });
            }

            log.debug("Данные успешно отправлены в Kafka топик: {}", outputTopic);

            log.debug("\n=== СТАТИСТИКА АНАЛИЗА ===");
            log.debug("Общее количество брендов: {}", analysisResult.select("brand").distinct().count());
            log.debug("Общее количество категорий: {}", analysisResult.select("category").distinct().count());
            log.debug("Общее количество товаров: {}", analysisResult.agg(functions.sum("product_count")).first().getLong(0));

            log.debug("\nТоп-5 комбинаций бренд-категория:");
            analysisResult.limit(5).show(false);

        } catch (Exception e) {
            log.error("Ошибка при выполнении Spark job:", e);
        } finally {
            spark.stop();
            log.debug("Spark приложение завершено.");
        }
    }
}
