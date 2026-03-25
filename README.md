# Dantzig

[![Hex.pm](https://img.shields.io/hexpm/v/dantzig.svg)](https://hex.pm/packages/dantzig)
[![Hex.pm](https://img.shields.io/hexpm/dt/dantzig.svg)](https://hex.pm/packages/dantzig)
[![Build Status](https://github.com/tmbb/dantzig/workflows/CI/badge.svg)](https://github.com/tmbb/dantzig/actions)

**Mathematical Optimization for Elixir** — Write optimization problems naturally, like mathematical notation, with automatic linearization and powerful pattern-based modeling.

> ℹ️ **Two supported APIs**: The DSL (`Problem.define do…end`) is ideal for static problems; the Functional API (`Problem.new_variable`, `Problem.add_constraint`, etc.) is the right choice for dynamic/runtime problems. Only `Problem.maximize/2` and `Problem.minimize/2` are deprecated. See [Choosing an API Style](#️-choosing-an-api-style) and the [Deprecation Notice](docs/user/guides/DEPRECATION_NOTICE.md).

```elixir
require Dantzig.Problem, as: Problem

# Pattern-based N-dimensional modeling
problem =
  Problem.define do
    new(direction: :maximize)

    # Create x[i,j] for i=1..8, j=1..8 — that's 64 variables in one line!
    variables("x", [i <- 1..8, j <- 1..8], :binary, "Queen position")

    # One queen per row: sum over j for each i
    constraints([i <- 1..8], sum(x(i, :_)) == 1, "One queen per row")

    # One queen per column: sum over i for each j
    constraints([j <- 1..8], sum(x(:_, j)) == 1, "One queen per column")

    # Maximize queens placed (will be 8 for valid N-Queens solution)
    objective(sum(x(:_, :_)), direction: :maximize)
  end

{:ok, solution} = Dantzig.solve(problem)
```

## ✨ What Makes Dantzig Special

**Pattern-Based Modeling**: Create N-dimensional variables with intuitive generator syntax

```elixir
# Instead of manually creating x11, x12, x13, x21, x22, x23, ...
variables("x", [i <- 1..3, j <- 1..3], :binary)

# Use natural patterns: x(i, :_) sums over second dimension
constraints([i <- 1..3], sum(x(i, :_)) == 1, "Row constraint")
```

**Automatic Linearization**: Non-linear expressions become linear constraints automatically

```elixir
# These work out of the box — no manual linearization needed!
constraints(abs(x) + max(x, y, z) <= 5, "Non-linear with auto-linearization")
constraints(a AND b AND c, "Logical AND constraint")
```

**Model Parameters**: Pass runtime data directly into your optimization models

```elixir
# Use a map with integer keys matching the generator range
# Bracket notation is used uniformly: costs[i] for constants, x[i] for variables
params = %{costs: %{1 => 10, 2 => 20, 3 => 30}, capacity: 100}

problem = Problem.define(model_parameters: params) do
  variables("x", [i <- 1..3], :integer, min_bound: 0)

  constraints(sum(for i <- 1..3, do: costs[i] * x[i]) <= capacity, "Budget")
  objective(sum(for i <- 1..3, do: x[i]), :maximize)
end
```

**Problem.modify**: Build problems incrementally

```elixir
# Start with base problem
base = Problem.define do
  variables("x", [i <- 1..3], :continuous)
  constraints([i <- 1..3], x(i) >= 0)
end

# Add more constraints and variables
problem = Problem.modify(base) do
  variables("y", [j <- 1..2], :binary)
  constraints(x(1) + x(2) + x(3) <= 10, "Capacity")
  objective(x(1) + 2*x(2) + 3*x(3), :maximize)
end
```

**Multiple Modeling Styles**: Choose the approach that fits your problem

- **Simple syntax** for basic problems
- **Pattern-based** for N-dimensional problems
- **Model parameters** for configurable problems
- **Problem.modify** for incremental building
- **Explicit control** when you need it
- **AST transformations** for advanced use cases

## 🚀 Quick Start

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:dantzig, "~> 0.2.0"}
  ]
end
```

### Your First Problem

```elixir
require Dantzig.Problem, as: Problem

problem =
  Problem.define do
    new(direction: :maximize)

    variables("x", :continuous, min_bound: 0, description: "Items to produce")
    variables("y", :continuous, min_bound: 0, description: "Items to sell")

    constraints(x + 2*y <= 14, "Resource constraint")
    constraints(3*x - y <= 0, "Quality constraint")

    objective(3*x + 4*y, direction: :maximize)
  end

{:ok, solution} = Dantzig.solve(problem)
IO.inspect({solution.objective, solution.variables})
```

## 📖 Documentation & Learning

| Level               | Guide                                          | Description                     |
| ------------------- | ---------------------------------------------- | ------------------------------- |
| 🏃 **Beginner**     | [Quick Start](docs/user/quickstart.md)         | Your first optimization problem |
| 📚 **Intermediate** | [Tutorial](docs/user/tutorial/comprehensive.md) | Complete guide with examples    |
| 🏗️ **Advanced**     | [Architecture](docs/developer/architecture/overview.md) | System design deep dive         |
| 🔧 **Reference**    | [API Docs](https://hexdocs.pm/dantzig)         | Complete function reference     |

**Generate full docs locally:**

```bash
mix docs
```

## 🎯 Core Features

### Pattern-Based Variables

Create complex variable structures with simple generators:

```elixir
# 2D transportation problem: supply[i] to demand[j]
variables("transport", [i <- 1..3, j <- 1..4], :continuous, min_bound: 0)

# 3D production planning: product[p] in period[t] at plant[f]
variables("produce", [p <- products, t <- 1..12, f <- facilities], :integer, min_bound: 0)

# 4D chess tournament: player[a] vs player[b] in round[r] at table[t]
variables("game", [a <- 1..8, b <- 1..8, r <- 1..7, t <- 1..4], :binary)
```

### Automatic Linearization

Non-linear expressions become linear constraints behind the scenes:

```elixir
# Absolute values
constraints(abs(inventory) <= max_inventory, "Absolute inventory")

# Maximum functions
constraints(max(profit1, profit2, profit3) >= target, "Max profit")

# Minimum functions
constraints(min(cost1, cost2) <= budget, "Min cost")

# Logical operations (binary variables)
constraints(decision1 AND decision2 AND decision3, "All decisions required")
constraints(decision1 OR decision2 OR decision3, "At least one decision")
```

### Flexible Constraint Patterns

Express complex constraints naturally:

```elixir
# Sum over specific dimensions
constraints([i <- 1..5], sum(x(i, :_)) == 1, "One per row")
constraints([j <- 1..5], sum(x(:_, j)) == 1, "One per column")

# Complex aggregations
constraints([i <- 1..3], sum(x(i, :_)) >= demand[i], "Demand satisfaction")

# Multi-dimensional constraints
constraints([i <- 1..3, j <- 1..3], x(i, j) <= capacity[i][j], "Capacity limits")
```

## 💡 Examples

Complete, runnable examples are available in the [Examples Directory](docs/user/examples/README.md):

### **Simple Problems**

- **Resource Allocation**: `mix run docs/user/examples/simple_working_example.exs`
- **Knapsack**: `mix run docs/user/examples/knapsack_problem.exs`
- **Assignment**: `mix run docs/user/examples/assignment_problem.exs`

### **Medium Problems**

- **Transportation**: `mix run docs/user/examples/transportation_problem.exs`
- **Production Planning**: `mix run docs/user/examples/production_planning.exs`
- **Blending**: `mix run docs/user/examples/blending_problem.exs`

### **Complex Problems**

- **N-Queens**: `mix run docs/user/examples/nqueens_dsl.exs`
- **Pattern Operations**: `mix run docs/user/examples/pattern_based_operations_example.exs`
- **Network Flow**: `mix run docs/user/examples/network_flow.exs`

See the [Examples Directory](docs/user/examples/README.md) for a complete categorized list of all examples.

## 🏗️ Choosing an API Style

Dantzig exposes **two current, supported APIs** and one deprecated one. Understanding the difference helps you pick the right tool.

### API 1: The DSL (`Problem.define do … end`)

A compile-time macro that lets you write optimization problems in a declarative, mathematical style. Internally it expands to the Functional API (below) via `DSLReducer`.

```elixir
require Dantzig.Problem, as: Problem

problem = Problem.define do
  new(direction: :maximize)
  variables("x", [i <- 1..3], :continuous, min_bound: 0)
  constraints([i <- 1..3], x(i) <= 10, "Bound")
  objective(sum(x(:_)), direction: :maximize)
end
```

**Use the DSL when:**
- The problem structure is **statically known at compile time**
- You want concise, mathematical notation
- You're building textbook-style problems (knapsack, N-queens, blending, etc.)

**Limitation:** outer-scope Elixir variables referenced inside `max_bound:`, `description:`, or
string-interpolated constraint names may not resolve correctly — they are captured as AST, not
evaluated values. Use `model_parameters:` to pass runtime data into the DSL:

```elixir
Problem.define(model_parameters: %{capacity: 100}) do
  new(direction: :minimize)
  variables("x", [i <- 1..3], :continuous, min_bound: 0)
  constraints(sum(x(:_)) <= capacity, "Capacity")   # capacity resolved at runtime ✓
  objective(sum(x(:_)), direction: :minimize)
end
```

---

### API 2: The Functional API

Regular Elixir functions that `Problem.define` expands to. Fully public, supported, and the right
choice for **dynamic problems** where the shape (number of variables, constraints) is determined at
runtime — for example, from database records or user input.

Key functions:

```elixir
alias Dantzig.{Polynomial, Constraint}
require Dantzig.Constraint, as: Constraint

problem = Problem.new(direction: :maximize)

# Add variables one at a time; each returns {updated_problem, polynomial_handle}
{problem, x} = Problem.new_variable(problem, "x", type: :continuous, min_bound: 0)
{problem, y} = Problem.new_variable(problem, "y", type: :continuous, min_bound: 0)

# Build the objective incrementally
problem = problem
  |> Problem.increment_objective(Polynomial.multiply(x, 3))
  |> Problem.increment_objective(Polynomial.multiply(y, 4))

# Add constraints (Constraint.new_linear is a macro — require it)
problem = Problem.add_constraint(problem,
  Constraint.new_linear(x + 2*y <= 14, name: "resource"))

{:ok, solution} = Dantzig.solve(problem)
```

**Use the Functional API when:**
- The problem shape depends on **runtime data** (e.g. from a database or API)
- You're building a helper that programmatically generates variables or constraints in a loop
- You need fine-grained control over variable naming

---

### ❌ Deprecated: Old Objective API

The following functions still exist but are **deprecated** and will be removed in v1.0.0:

```elixir
# ❌ DEPRECATED — sets objective but discards any previously accumulated terms
problem = Problem.maximize(problem, 3*x + 4*y)
problem = Problem.minimize(problem, cost)
```

Replace with:

```elixir
# ✅ Set direction in new/1, build objective with increment_objective/2
problem = Problem.new(direction: :maximize)
problem = Problem.increment_objective(problem, Polynomial.multiply(x, 3))
problem = Problem.increment_objective(problem, Polynomial.multiply(y, 4))

# or set it all at once with set_objective/2 + direction in new/1
problem = Problem.set_objective(problem, 3*x + 4*y)
```

The old `add_variables/5` macro (with explicit `problem` as first arg) is similarly deprecated in
favour of `variables/5` inside a `define` block or `Problem.new_variable/3` in the Functional API.



**World-Class Optimization Power**: Dantzig integrates seamlessly with the HiGHS solver, providing access to cutting-edge optimization algorithms.

**Automatic Binary Management**: The HiGHS solver binary is automatically downloaded and managed for your platform.

**High Performance**: Leverages HiGHS's advanced algorithms for linear programming, mixed-integer programming, and quadratic programming.

```elixir
# Automatic HiGHS integration - no manual setup required!
{:ok, solution} = Dantzig.solve(problem)

# Custom configuration (optional)
config :dantzig, :highs_binary_path, "/usr/local/bin/highs"
config :dantzig, :highs_version, "1.9.0"

# Advanced solver options
config :dantzig, :solver_options, [
  parallel: true,
  presolve: :on,
  time_limit: 300.0
]
```

## 🔧 Configuration

Dantzig automatically downloads the HiGHS solver binary for your platform:

```elixir
# Custom binary path (optional)
config :dantzig, :highs_binary_path, "/usr/local/bin/highs"

# HiGHS version (default: "1.9.0")
config :dantzig, :highs_version, "1.9.0"
```

## 📊 Current Capabilities

| Feature                     | Status      | Notes                                   |
| --------------------------- | ----------- | --------------------------------------- |
| **Linear Programming**      | ✅ Complete | Full support                            |
| **Quadratic Programming**   | ✅ Complete | Degree ≤ 2 expressions                  |
| **Pattern-based Modeling**  | ✅ Complete | N-dimensional variables                 |
| **Automatic Linearization** | ✅ Complete | abs, max/min, logical ops               |
| **Mixed-Integer Variables** | ⚠️ Tracked  | Types defined, LP serialization pending |
| **Custom Operators**        | 🚧 Reserved | `:in` operator for future use           |

## 🤝 Contributing

We welcome contributions! Explore the [architecture docs](docs/ARCHITECTURE.md) to understand the system design, and feel free to submit issues and pull requests on GitHub.

**Key Areas for Contribution**:

- Mixed-integer LP serialization
- Additional non-linear function support
- Performance optimizations
- Documentation and examples

## 📜 License

MIT License - see [LICENSE.TXT](LICENSE.TXT) for details.

## 🙏 Acknowledgments

- **[HiGHS](https://github.com/ERGO-Code/HiGHS)** - World-class optimization solver
- **[JuliaBinaryWrappers](https://github.com/JuliaBinaryWrappers)** - Pre-compiled binaries
- **Elixir Community** - Inspiration and valuable feedback

---

**Ready to optimize?** Start with the [Quick Start Guide](docs/user/quickstart.md) or dive into the [Tutorial](docs/user/tutorial/comprehensive.md) for comprehensive examples!
