package ru.myproject.model;

import lombok.Data;

@Data
public class Stock {
    private int available;
    private int reserved;
}
