package com.platform.inventory;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/inventory")
public class InventoryController {

    @GetMapping
    public List<Map<String, Object>> getInventory() {
        return List.of(
            Map.of("id", 1, "name", "Widget A", "quantity", 100),
            Map.of("id", 2, "name", "Widget B", "quantity", 50)
        );
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
