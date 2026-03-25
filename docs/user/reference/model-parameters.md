# Model Parameters

## Overview

Model parameters allow you to pass runtime data directly into your optimization models. This enables dynamic problem definition based on external data.

## Basic Usage

Pass model parameters via the `model_parameters:` keyword option:

```elixir
data = %{
  products: ["Widget", "Gadget"],
  profits: [10, 15],
  limits: [100, 200]
}

problem = Problem.define(model_parameters: data) do
  new(direction: :maximize)
  variables("qty", [product <- products], :continuous, min_bound: 0)
  constraints([i <- 0..1], qty(products[i]) <= limits[i], "Limit")
  objective(sum(profits[i] * qty(products[i]) for i <- 0..1), :maximize)
end
```

## Parameter Types

### Simple Values

```elixir
Problem.define(model_parameters: %{limit: 100, budget: 1000}) do
  constraints(x <= limit, "Bound")
  constraints(cost <= budget, "Budget")
end
```

### Arrays/Lists (0-based indexing)

```elixir
Problem.define(model_parameters: %{costs: [10, 20, 30]}) do
  variables("x", [i <- 0..2], :continuous)
  constraints(x(i) <= costs[i], "Cost bound")
end
```

### Maps with Integer Keys (arbitrary ranges)

When your generator range does not start at 0, use a map with integer keys that match
the generator values. This ensures `costs[i]` resolves correctly for any `i` in the range.

```elixir
# Generator i <- 1..3: use a map with keys 1, 2, 3
Problem.define(model_parameters: %{costs: %{1 => 10, 2 => 20, 3 => 30}}) do
  variables("x", [i <- 1..3], :continuous)
  constraints([i <- 1..3], x(i) <= costs[i], "Cost bound #{i}")
end
```

### Maps

```elixir
Problem.define(model_parameters: %{
  cost: %{"A" => 10, "B" => 20}
}) do
  variables("x", ["A", "B"], :continuous)
  constraints(x("A") <= cost["A"], "Cost A")
end
```

### Nested Maps

```elixir
Problem.define(model_parameters: %{
  data: %{
    "worker" => %{"task1" => 5, "task2" => 10}
  }
}) do
  variables("assign", ["worker"], ["task1", "task2"], :binary)
  constraints(assign("worker", "task1") * data["worker"]["task1"] <= 100)
end
```

## Access Patterns

### Bracket Notation (Recommended)

```elixir
# Simple access
limit

# Map access
cost["worker"]

# Nested access
data["worker"]["task"]

# Array access
costs[0]
```

### Dot Notation (Simple Keys Only)

```elixir
# Works for simple atom keys
cost.worker

# Fails for keys with spaces/special characters
# cost."worker name"  # ❌ Not supported
```

## Key Conversion

String keys are automatically converted to atom keys when accessing maps:

```elixir
# Both work:
cost["worker"]  # String key
cost[:worker]   # Atom key (converted automatically)
```

## Generator Domains

Model parameters can be used in generator domains:

```elixir
Problem.define(model_parameters: %{food_names: ["bread", "milk"]}) do
  variables("qty", [food <- food_names], :continuous)
end
```

## Best Practices

1. **Use descriptive names**: `product_names` instead of `names`
2. **Group related data**: Use nested maps for complex structures
3. **Validate data**: Ensure data structure matches expected format
4. **Document parameters**: Comment on expected parameter structure

## Related Documentation

- [DSL Syntax Reference](dsl-syntax.md) - Complete syntax guide
- [Expressions](expressions.md) - Expression evaluation
- [Quick Start](../quickstart.md) - Getting started guide
