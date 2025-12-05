package ru.myproject.spark;

import org.apache.spark.sql.SparkSession;

public class SparkSessionExample {

    public static void main(String[] args) {
        SparkSession spark = SparkSession.builder()
                .appName("Java DataFrame Example")
                .master("local[*]")
                .getOrCreate();
        System.out.println(spark.version());
    }
}
