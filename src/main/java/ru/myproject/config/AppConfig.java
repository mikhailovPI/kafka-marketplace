package ru.myproject.config;

import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Slf4j
public class AppConfig {
    private static final Properties properties = new Properties();
    private static final Pattern ENV_VAR_PATTERN = Pattern.compile("\\$\\{([^:}]+)(?::([^}]*))?\\}");

    static {
        loadProperties();
        initializeSystemProperties();
    }

    private static void initializeSystemProperties() {
        // Устанавливаем system properties для logback
        String rootLevel = getLoggingLevelRoot();
        String packageLevel = getLoggingLevelPackage();
        System.setProperty("logging.level.root", rootLevel);
        System.setProperty("logging.level.ru.myproject", packageLevel);
    }

    private static void loadProperties() {
        try (InputStream inputStream = AppConfig.class.getClassLoader()
                .getResourceAsStream("application.properties")) {
            if (inputStream == null) {
                log.warn("application.properties not found, using defaults");
                return;
            }
            properties.load(inputStream);
            // Заменяем переменные окружения
            properties.stringPropertyNames().forEach(key -> {
                String value = properties.getProperty(key);
                properties.setProperty(key, resolveEnvironmentVariables(value));
            });
        } catch (IOException e) {
            log.error("Error loading application.properties", e);
        }
    }

    private static String resolveEnvironmentVariables(String value) {
        if (value == null) {
            return null;
        }
        Matcher matcher = ENV_VAR_PATTERN.matcher(value);
        StringBuffer result = new StringBuffer();
        while (matcher.find()) {
            String envVarName = matcher.group(1);
            String defaultValue = matcher.group(2);
            String envValue = System.getenv(envVarName);
            if (envValue == null) {
                envValue = System.getProperty(envVarName);
            }
            if (envValue == null) {
                envValue = defaultValue != null ? defaultValue : "";
            }
            matcher.appendReplacement(result, Matcher.quoteReplacement(envValue));
        }
        matcher.appendTail(result);
        return result.toString();
    }

    public static String getProperty(String key) {
        String value = properties.getProperty(key);
        if (value == null || value.isEmpty()) {
            throw new IllegalStateException("Required property '" + key + "' is not set in application.properties");
        }
        return value;
    }

    public static int getIntProperty(String key) {
        String value = getProperty(key);
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            throw new IllegalStateException("Invalid integer value for property '" + key + "': " + value, e);
        }
    }

    public static long getLongProperty(String key) {
        String value = getProperty(key);
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException e) {
            throw new IllegalStateException("Invalid long value for property '" + key + "': " + value, e);
        }
    }

    public static boolean getBooleanProperty(String key) {
        String value = getProperty(key);
        return Boolean.parseBoolean(value);
    }

    // Kafka Topics
    public static String getKafkaTopicBlockedProducts() {
        return getProperty("kafka.topic.blocked-products");
    }

    public static String getKafkaTopicProducts() {
        return getProperty("kafka.topic.products");
    }

    public static String getKafkaTopicInputJsonStream() {
        return getProperty("kafka.topic.input-json-stream");
    }

    public static String getKafkaTopicUserQuery() {
        return getProperty("kafka.topic.user-query");
    }

    public static String getKafkaTopicResponse() {
        return getProperty("kafka.topic.response");
    }

    public static String getKafkaTopicRecommendations() {
        return getProperty("kafka.topic.recommendations");
    }

    public static String getKafkaTopicDataAnalysis() {
        return getProperty("kafka.topic.data-analysis");
    }

    // Client Request
    public static String getClientRequestFileStore() {
        return getProperty("client.request.file-store");
    }

    public static long getClientRequestYearsLast() {
        return getLongProperty("client.request.years-last");
    }

    // File Paths
    public static String getFilePathProducts() {
        return getProperty("file.path.products");
    }

    public static String getFilePathBlockedProducts() {
        return getProperty("file.path.blocked-products");
    }

    // Spark
    public static String getSparkAppName() {
        return getProperty("spark.app.name");
    }

    public static String getSparkMaster() {
        return getProperty("spark.master");
    }

    public static String getSparkHdfsInput() {
        return getProperty("spark.hdfs.input");
    }

    public static String getSparkHdfsDefaultFs() {
        return getProperty("spark.hdfs.default-fs");
    }

    public static String getSparkHdfsCheckpointLocation() {
        return getProperty("spark.hdfs.checkpoint-location");
    }

    public static int getSparkHadoopDfsClientSocketTimeout() {
        return getIntProperty("spark.hadoop.dfs.client.socket-timeout");
    }

    public static int getSparkHadoopDfsDatanodeSocketWriteTimeout() {
        return getIntProperty("spark.hadoop.dfs.datanode.socket.write.timeout");
    }

    public static int getSparkHadoopIpcClientConnectTimeout() {
        return getIntProperty("spark.hadoop.ipc.client.connect.timeout");
    }

    // Logging
    public static String getLoggingLevelRoot() {
        return getProperty("logging.level.root");
    }

    public static String getLoggingLevelPackage() {
        return getProperty("logging.level.ru.myproject");
    }
}

