package ru.myproject.config;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.streams.StreamsConfig;

import java.util.Properties;

public class KafkaPropertiesDestination {
    public static Properties getConfig() {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "data-analysis");
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:49092,localhost:59092,localhost:59093");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        props.put("topic_data_analysis", "dataAnalysis");
        return props;
    }
}

