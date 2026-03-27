# Wildcards and Nested Maps

**Part of**: [DSL Syntax Advanced Topics](../DSL_SYNTAX_ADVANCED.md) | **See Also**: [DSL Syntax Reference](../dsl-syntax.md), [DSL Syntax Examples](../DSL_SYNTAX_EXAMPLES.md)

The DSL supports wildcard placeholders (`:_`) combined with nested map access, allowing concise notation for constraints involving multidimensional data structures.

## Equivalent Syntaxes

All four syntaxes below are equivalent and produce identical constraints:

```elixir
# Setup
model_parameters: %{
  foods: %{
    "bread" => %{calories: 100, protein: 3},
    "milk" => %{calories: 150, protein: 8}
  },
  food_names: ["bread", "milk"],
  nutrient_names: ["calories", "protein"]
}

variables("qty", [food <- food_names], :continuous, "Food quantity")

# Syntax A: Explicit for comprehension with bracket access
constraints(
  [nutrient <- nutrient_names],
  sum(for food <- food_names, do: qty[food] * foods[food][nutrient]) <= limit[nutrient],
  "Max #{nutrient}"
)

# Syntax B: Explicit for comprehension with dot notation
constraints(
  [nutrient <- nutrient_names],
  sum(for food <- food_names, do: qty[food] * foods[food].nutrient) <= limit[nutrient],
  "Max #{nutrient}"
)

# Syntax C: Wildcard with bracket access (concise)
constraints(
  [nutrient <- nutrient_names],
  sum(qty[:_] * foods[:_][nutrient]) <= limit[nutrient],
  "Max #{nutrient}"
)

# Syntax D: Wildcard with dot notation (concise)
constraints(
  [nutrient <- nutrient_names],
  sum(qty[:_] * foods[:_].nutrient) <= limit[nutrient],
  "Max #{nutrient}"
)
```

## Wildcard Expansion Rules

1. **Single wildcard with nested access:**
   - `foods[:_][nutrient]` expands to `foods[food_1][nutrient] + foods[food_2][nutrient] + ...`
   - Where `food_1, food_2, ...` are values from the variable generator

2. **Multiple wildcards:**
   - `matrix[:_][:_]` expands to all combinations
   - Wildcards are matched positionally to variable generators

3. **Mixed wildcards and explicit indices:**
   - `data[i][:_]` - second dimension uses wildcard, first is explicit
   - `data[:_][j]` - first dimension uses wildcard, second is explicit

4. **Generator variable in nested access:**
   - `foods[:_][nutrient]` where `nutrient` is a generator variable
   - The generator variable value is evaluated at expansion time
   - Example: When `nutrient = "calories"`, expands to `foods[:_]["calories"]`

## Complete Diet Problem Example

```elixir
# Diet problem demonstrating wildcard + nested access
foods = %{
  "bread" => %{cost: 2.0, calories: 100, protein: 3, fat: 1},
  "milk" => %{cost: 1.0, calories: 150, protein: 8, fat: 2.5},
  "cheese" => %{cost: 3.0, calories: 200, protein: 10, fat: 8}
}

nutrient_limits = %{
  "calories" => %{min: 1800, max: 2200},
  "protein" => %{min: 50, max: :infinity},
  "fat" => %{min: 0, max: 65}
}

problem = Problem.define model_parameters: %{
  foods: foods,
  food_names: Map.keys(foods),
  nutrient_names: Map.keys(nutrient_limits),
  nutrient_limits: nutrient_limits
} do
  new(name: "Diet Problem", description: "Minimize cost while meeting nutrition")

  variables("qty", [food <- food_names], :continuous,
    min_bound: 0.0,
    description: "Quantity of each food"
  )

  # CONCISE SYNTAX using wildcards:
  constraints(
    [nutrient <- nutrient_names],
    sum(qty[:_] * foods[:_][nutrient]) >= nutrient_limits[nutrient].min,
    "Min #{nutrient}"
  )

  constraints(
    [nutrient <- nutrient_names],
    sum(qty[:_] * foods[:_][nutrient]) <= nutrient_limits[nutrient].max,
    "Max #{nutrient}"
  )

  objective(sum(qty[:_] * foods[:_].cost), :minimize)
end
```

## Naming and Sanitization

### Variable Index Names

When using generator variables to create variable indices, the index values become part of variable names. Both DSL and LP formats use **bracket notation**. Only the characters **inside** the brackets are sanitized for LP compatibility.

**Example:**

```elixir
suppliers = ["Supplier A", "Supplier-1", "Tokyo (Main)"]
customers = ["Customer #1", "NYC Office"]

variables("ship", [s <- suppliers, c <- customers], :continuous)

# DSL level (what you write):
ship[Supplier A][Customer #1]
ship[Supplier A][NYC Office]
ship[Tokyo (Main)][Customer #1]

# LP level (brackets preserved, contents sanitized):
ship[Supplier_A][Customer_1]
ship[Supplier_A][NYC_Office]
ship[Tokyo_Main][Customer_1]
```

**Key Point:** Brackets are **preserved** in LP format. Only spaces and special characters **within** the indices are sanitized.

**Best Practice:** Use simple identifiers when possible:

- ✅ Good: `["supplier_a", "supplier_b"]` → `ship[supplier_a][customer_1]`
- ⚠️ Works: `["Supplier A", "Tokyo (Main)"]` → `ship[Supplier_A][Tokyo_Main]` (contents sanitized)
- ❌ Avoid: Excessively long names or extreme special characters

### Map Keys in Nested Access

Map keys used in nested access (e.g., `foods[:_][nutrient]`) are **only used for constant evaluation** at the Elixir level, not as symbolic names. Therefore, they can contain any valid map key characters.

**Example:**

```elixir
# Map keys with spaces and special characters are fine
foods = %{
  "bread" => %{
    "total calories": 100,
    "protein (g)": 3,
    "fat %": 1.5
  }
}

nutrient_names = ["total calories", "protein (g)", "fat %"]

# This works correctly:
constraints(
  [nutrient <- nutrient_names],
  sum(qty[:_] * foods[:_][nutrient]) >= min_nutrient[nutrient],
  "Min #{nutrient}"
)

# Generated constraint names (sanitized for LP):
# Min_total_calories
# Min_protein_g
# Min_fat_
```

**Key Point:** The nested map access `foods[:_][nutrient]` is evaluated to numeric constants (100, 3, 1.5) before LP generation. Only the constraint description `"Min #{nutrient}"` uses the key as a string, which is then sanitized.

## Bracket vs Dot Notation

### Bracket Notation (Recommended - Most General)

**Syntax:** `foods[:_][nutrient]`

**Use when:**

- Map keys contain spaces: `"total calories"`
- Map keys contain special characters: `"protein (g)"`, `"fat %"`
- Keys are strings (not atoms)
- Generator variables may produce complex keys
- Maximum flexibility needed

**Example:**

```elixir
nutrient_names = ["total calories", "protein (g)", "fat %"]
foods = %{"bread" => %{"total calories": 100, "protein (g)": 3}}

# Works perfectly:
sum(qty[:_] * foods[:_][nutrient])  # ✅
```

### Dot Notation (Syntactic Sugar - Simple Keys Only)

**Syntax:** `foods[:_].nutrient`

**Use when:**

- Map keys are simple atoms: `:calories`, `:protein`, `:fat`
- Keys have no spaces or special characters
- Cleaner, more Elixir-idiomatic syntax desired

**Example:**

```elixir
nutrient_names = [:calories, :protein, :fat]  # Atoms, no spaces
foods = %{bread: %{calories: 100, protein: 3}}

# Clean and idiomatic:
sum(qty[:_] * foods[:_].nutrient)  # ✅
```

**Avoid dot notation when:**

- Keys contain spaces or special chars
- Would require quoted atom syntax: `.:"complex key"`

**Equivalence (Simple Keys Only)**

For simple atom keys, these are equivalent:

```elixir
foods[:_].calories  ≡  foods[:_][:calories]
foods[:_][nutrient] ≡  foods[:_].nutrient   # Only if nutrient is simple atom
```

**Best Practice:** Use bracket notation `[:_][key]` for robustness unless you're certain all keys are simple atoms.

## Sanitization

### When Sanitization Occurs

The DSL sanitizes names automatically in these contexts:

1. **Variable names** - When generating LP variable declarations
2. **Constraint names** - When generating LP constraint declarations
3. **Objective name** - When generating LP objective declaration

**What is NOT sanitized:**

- Map keys in `model_parameters` (used only for constant lookup)
- Values in generator lists (used only for constant lookup)

### Sanitization Rules

The LP sanitization process:

- Replaces spaces with underscores: `"Supplier A"` → `"Supplier_A"`
- Removes special characters: `"Item #1"` → `"Item_1"`
- Adds prefix if starts with digit: `"1st_item"` → `"x_1st_item"`
- Truncates if too long (solver-dependent)

## Key Points

- **Dot vs Bracket:** Use bracket notation `[:_][key]` for robustness; dot notation only for simple atom keys
- **Generator Scope:** Generator variables (like `nutrient`) are evaluated before map access
- **Type Conversion:** String keys are automatically converted to atom keys when accessing maps
- **Validation:** The DSL validates that all accessed keys exist in the model parameters
- **DSL ≡ LP Format:** Both use bracket notation `ship[A][B]`, only contents are sanitized `ship[A_sanitized][B_sanitized]`
- **Brackets Preserved:** Maintains traceability from DSL to LP output for debugging

## Related Documentation

- [DSL Syntax Reference](../dsl-syntax.md) - Complete syntax guide
- [Error Handling](error-handling.md) - Error handling and troubleshooting
- [Model Parameters](../model-parameters.md) - Using constants and runtime data
