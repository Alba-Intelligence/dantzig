# Quick Start with Dantzig

Welcome! This guide will take you from installation to solving your first optimization problems using Dantzig's powerful DSL. We'll start simple and build up to advanced features like model parameters and incremental problem building.

## Installation & Setup

Add Dantzig to your `mix.exs`:

```elixir
defp deps do
  [
    {:dantzig, "~> 0.2.0"}
  ]
end
```

Install and verify:

```bash
mix deps.get
mix compile
```

## Your First Optimization Problem

Let's start with a simple production planning problem: maximize profit subject to resource constraints.

```elixir
require Dantzig.Problem, as: Problem

# Maximize profit: $3 per unit of product A, $4 per unit of product B
problem = Problem.define do
  new(direction: :maximize)

  # Decision variables: how much of each product to produce
  variables("A", :continuous, min_bound: 0, description: "Units of Product A")
  variables("B", :continuous, min_bound: 0, description: "Units of Product B")

  # Constraints: limited resources
  constraints(2*A + B <= 10, "Material constraint")
  constraints(A + 3*B <= 12, "Labor constraint")

  # Objective: maximize profit
  objective(3*A + 4*B, direction: :maximize)
end

# Solve and inspect results
{:ok, solution} = Dantzig.solve(problem)
IO.puts("Optimal profit: $#{solution.objective_value}")
IO.puts("Product A: #{solution.variables["A"]} units")
IO.puts("Product B: #{solution.variables["B"]} units")
```

**Output:**

```
Optimal profit: $22.0
Product A: 1.0 units
Product B: 6.0 units
```

## Pattern-Based Modeling

Dantzig excels at N-dimensional problems. Instead of manually creating variables, use generators:

```elixir
# Production planning for multiple products over time
problem = Problem.define do
  new(direction: :maximize)

  # Variables: production[product][time_period]
  variables("production", [product <- ["A", "B"], time <- 1..4], :continuous, min_bound: 0)

  # Constraints: capacity limits by time period
  constraints([time <- 1..4],
    sum(production(product, time) for product <- ["A", "B"]) <= 100,
    "Capacity for period #{time}"
  )

  # Constraints: demand minimums by product
  constraints([product <- ["A", "B"]],
    sum(production(product, time) for time <- 1..4) >= 50,
    "Demand for #{product}"
  )

  # Objective: maximize total production
  objective(sum(production(product, time) for product <- ["A", "B"], time <- 1..4), :maximize)
end
```

## Using Model Parameters

Pass runtime data directly into your optimization models:

```elixir
# External data for our optimization.
# Use maps keyed by product name so parameter[p] resolves correctly
# when iterating over the same product variable in the generator.
product_data = %{
  products:       ["Widget", "Gadget", "Tool"],
  profit:         %{"Widget" => 10, "Gadget" => 15, "Tool" => 8},
  material:       %{"Widget" => 2,  "Gadget" => 3,  "Tool" => 1},
  labor:          %{"Widget" => 1,  "Gadget" => 2,  "Tool" => 3},
  material_limit: 100,
  labor_limit:    80
}

problem = Problem.define(model_parameters: product_data) do
  new(direction: :maximize)

  # Variables: production quantity for each product (keyed by name)
  variables("qty", [product <- products], :integer, min_bound: 0)

  # Bracket notation is used uniformly for both constants (material[p]) and variables (qty[p])
  constraints(sum(for p <- products, do: material[p] * qty[p]) <= material_limit, "Material")
  constraints(sum(for p <- products, do: labor[p]    * qty[p]) <= labor_limit,    "Labor")

  # Objective: maximize total profit
  objective(sum(for p <- products, do: profit[p] * qty[p]), :maximize)
end

{:ok, solution} = Dantzig.solve(problem)
# Access results...
```

> **Tip**: When generator variables are integers from a range like `i <- 1..n`, use maps with
> matching integer keys (e.g. `%{1 => 10, 2 => 20, 3 => 30}`). Plain Elixir lists use 0-based
> indexing and are only correct when the range also starts at 0.

## Incremental Problem Building with Problem.modify

Start simple and build up your optimization problems incrementally:

```elixir
# Start with basic production variables
base_problem = Problem.define do
  new(direction: :maximize)
  variables("production", [i <- 1..3], :continuous, min_bound: 0)
end

# Add capacity constraints
with_capacity = Problem.modify(base_problem) do
  constraints([i <- 1..3], production(i) <= 50, "Capacity #{i}")
end

# Add quality constraints
final_problem = Problem.modify(with_capacity) do
  constraints(production(1) + production(2) + production(3) <= 100, "Total capacity")
  objective(10*production(1) + 15*production(2) + 8*production(3), :maximize)
end

# Solve the incrementally built problem
{:ok, solution} = Dantzig.solve(final_problem)
```

## Advanced Features

### Logical and Non-Linear Expressions

Dantzig automatically linearizes many non-linear expressions:

```elixir
problem = Problem.define do
  new(direction: :maximize)

  variables("x", :binary)
  variables("y", :binary)
  variables("z", :continuous, min_bound: 0, max_bound: 10)

  # Logical AND constraint
  constraints(x AND y, "Both required")

  # Absolute value (automatically linearized)
  constraints(abs(z - 5) <= 2, "Close to 5")

  # Maximum function (automatically linearized)
  constraints(max(x, y, z) <= 8, "Bounded maximum")

  objective(x + y + z, :maximize)
end
```

### Integer and Binary Variables

```elixir
problem = Problem.define do
  new(direction: :minimize)

  # Integer variables (counts, quantities)
  variables("num_workers", :integer, min_bound: 1, max_bound: 20)

  # Binary variables (decisions: yes/no, on/off)
  variables("use_machine", [i <- 1..5], :binary)

  # Constraints mixing types
  constraints(num_workers <= 10 + 2*sum(use_machine(i) for i <- 1..5), "Workforce")

  objective(100*num_workers + sum(50*use_machine(i) for i <- 1..5), :minimize)
end
```

## Working with Solutions

The solution contains all variable values and metadata:

```elixir
{:ok, solution} = Dantzig.solve(problem)

# Key information
IO.puts("Status: #{solution.status}")           # :optimal, :infeasible, etc.
IO.puts("Objective: #{solution.objective_value}") # Final objective value

# Variable values
solution.variables
# %{"x" => 5.0, "y" => 10.0, "production_1" => 25.0, ...}

# Access specific variables
product_a = Problem.get_variable(solution, "production_A")
```

## Error Handling

Dantzig provides clear error messages for common issues:

```elixir
case Dantzig.solve(problem) do
  {:ok, solution} ->
    # Process successful solution
    handle_solution(solution)

  {:error, :infeasible} ->
    IO.puts("Problem has no feasible solution")

  {:error, :unbounded} ->
    IO.puts("Objective is unbounded")

  {:error, reason} ->
    IO.puts("Solver error: #{reason}")
end
```

## Next Steps

**Build your first model** using the examples above

**Deepen your knowledge:**

- [DSL Syntax Reference](reference/dsl-syntax.md) - Complete syntax guide
- [Tutorial](tutorial/basics.md) - Step-by-step modeling guide
- [Examples Directory](examples/README.md) - Runnable examples for common problems

**Advanced topics:**

- [Modeling Guide](guides/modeling-patterns.md) - Best practices and patterns
- [Pattern Operations](reference/pattern-operations.md) - Pattern-based operations
- [Variadic Operations](reference/variadic-operations.md) - Variadic max/min/and/or

**Ready to optimize?** Check out the [Examples Directory](examples/README.md) for complete, runnable optimization problems covering assignment, transportation, production planning, and more!
