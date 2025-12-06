package ru.myproject.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.datatype.jsr310.deser.LocalDateTimeDeserializer;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Data
public class Product {
    @JsonProperty("product_id")
    private String productId;

    private String name;
    private String description;

    private Price price;
    private String category;
    private String brand;

    private Stock stock;
    private String sku;
    private List<String> tags;
    private List<Image> images;
    private Specifications specifications;

    @JsonProperty("created_at")
    @JsonDeserialize(using = LocalDateTimeDeserializer.class)
    private LocalDateTime createdAt;

    @JsonProperty("updated_at")
    @JsonDeserialize(using = LocalDateTimeDeserializer.class)
    private LocalDateTime updatedAt;

    private String index;

    @JsonProperty("store_id")
    private String storeId;
}
