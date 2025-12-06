package ru.myproject.config;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.streams.StreamsConfig;

import java.util.Properties;

public class KafkaPropertiesDestination {

    public static Properties getConfig() {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, 
                AppConfig.getProperty("kafka.destination.application-id"));
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, 
                AppConfig.getProperty("kafka.destination.bootstrap-servers"));
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.ACKS_CONFIG, 
                AppConfig.getProperty("kafka.destination.acks"));
        props.put(ProducerConfig.RETRIES_CONFIG, 
                AppConfig.getIntProperty("kafka.destination.retries"));
        props.put("topic_data_analysis", AppConfig.getKafkaTopicDataAnalysis());
        return props;
    }
}
