# Constants Syntax

**Part of**: [DSL Syntax Reference](../dsl-syntax.md)

## Named Constants

Single values passed via `model_parameters`.

**Syntax:**

```elixir
Problem.define(model_parameters: %{multiplier: 7.0}) do
  constraints(x1 + multiplier * x2 <= 10, "Constraint")
end
```

**Rules:**

- ✅ Constants identified automatically (not variables)
- ✅ Can be used in expressions and generator domains

## Enumerated Constants

Indexed sets of values (maps with integer or string keys).

**Syntax:**

```elixir
# Map with integer keys (matches generator range exactly)
# Generator i <- 1..3 produces 1, 2, 3 — keys must match
model_parameters: %{multiplier: %{1 => 4.0, 2 => 5.0, 3 => 6.0}}
constraints(sum(for i <- 1..3, do: x[i] * multiplier[i]) <= 10, "...")

# 0-based list (only when generator starts at 0)
model_parameters: %{multiplier: [4.0, 5.0, 6.0]}
constraints(sum(for i <- 0..2, do: x[i] * multiplier[i]) <= 10, "...")

# 2D map
model_parameters: %{cost: %{"Alice" => %{"Task1" => 2, "Task2" => 3}}}
constraints(sum(for w <- workers, do: assign[w][t] * cost[w][t]) <= 10, "...")
```

> **Note**: Bracket notation `x[i]` is used uniformly for both constants and variables.
> Generator variables (e.g. `i` in `[i <- 1..4]`) produce the exact values from the range.
> Use a map with keys that match those values. Only use a plain list when the range starts at 0,
> because Elixir list access is 0-based.

**Access Patterns:**

- ✅ Bracket notation: `cost[worker][task]` (recommended, most general)
- ✅ Dot notation: `cost[worker].task` (only for simple atom keys)
- ✅ Nested access: `foods[:_][nutrient]` (with wildcards, see [Advanced Topics](../advanced/wildcards-and-nested-maps.md))

**Rules:**

- ✅ String keys automatically converted to atom keys when accessing maps
- ✅ Map keys can contain spaces/special characters (only used for constant lookup)
- ❌ Dot notation fails for keys with spaces/special characters

## Related Documentation

- [DSL Syntax Reference](../dsl-syntax.md) - Complete syntax guide
- [Model Parameters](../model-parameters.md) - Using constants and runtime data
- [Wildcards and Nested Maps](../advanced/wildcards-and-nested-maps.md) - Advanced constant access
