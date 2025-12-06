package ru.myproject.spark;

import lombok.extern.slf4j.Slf4j;
import org.apache.spark.sql.SparkSession;

@Slf4j
public class SparkSessionExample {

    public static void main(String[] args) {
        SparkSession spark = SparkSession.builder()
                .appName("Java DataFrame Example")
                .master("local[*]")
                .getOrCreate();
        log.debug("Spark version: {}", spark.version());
    }
}
