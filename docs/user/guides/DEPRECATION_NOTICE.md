# Deprecation Notice

**⚠️ Specific functions deprecated — not the entire imperative/functional API ⚠️**

This document lists the **specific deprecated functions** that should no longer be used.
The Functional API (`Problem.new_variable/3`, `Problem.add_constraint/2`,
`Problem.increment_objective/2`, etc.) is **not deprecated** — it is the stable foundation
that the DSL expands to, and the correct choice for runtime/dynamic problems.

## What Is (and Is Not) Deprecated

### ❌ Deprecated: `Problem.maximize/2` and `Problem.minimize/2`

These functions **replace the entire objective** on every call, making it impossible to build
up an objective incrementally. They also conflate direction with objective-setting.

**❌ DEPRECATED:**

```elixir
problem = Problem.maximize(problem, 3*x + 4*y)
problem = Problem.minimize(problem, cost)
```

**✅ USE INSTEAD:**

```elixir
# Set direction once in new/1; accumulate objective with increment_objective/2
problem = Problem.new(direction: :maximize)
problem = Problem.increment_objective(problem, Polynomial.multiply(x, 3))
problem = Problem.increment_objective(problem, Polynomial.multiply(y, 4))
```

Or if you want to set the full objective at once:

```elixir
problem = Problem.new(direction: :maximize)
problem = Problem.set_objective(problem, 3*x + 4*y)
```

---

### ❌ Deprecated: `add_variables/5` macro (explicit `problem` first arg)

**❌ DEPRECATED:**

```elixir
# Old macro requiring explicit problem threading
problem = Problem.add_variables(problem, "x", [i <- 1..4, j <- 1..4], :binary, "Queen position")
```

**✅ USE INSTEAD — DSL style (static problems):**

```elixir
Problem.define do
  variables("x", [i <- 1..4, j <- 1..4], :binary, "Queen position")
end
```

**✅ USE INSTEAD — Functional API (dynamic/runtime problems):**

```elixir
{problem, x} = Problem.new_variable(problem, "x_1_1", type: :binary)
# or in a loop:
{problem, vars} = Problem.new_variables(problem, names, type: :binary)
```

---

## What Is NOT Deprecated (Current APIs)

### ✅ The DSL (`Problem.define do … end`)

The preferred style for statically-shaped problems:

```elixir
problem = Problem.define do
  new(direction: :maximize)
  variables("x", [i <- 1..3], :continuous, min_bound: 0)
  constraints([i <- 1..3], x(i) <= 10, "Bound #{i}")
  objective(sum(x(:_)), direction: :maximize)
end
```

### ✅ The Functional API

The correct choice when problem structure depends on runtime data:

```elixir
problem = Problem.new(direction: :maximize)
{problem, x} = Problem.new_variable(problem, "x", type: :continuous, min_bound: 0)
problem = Problem.add_constraint(problem, Constraint.new_linear(x <= 10, name: "bound"))
problem = Problem.increment_objective(problem, x)
{:ok, solution} = Dantzig.solve(problem)
```

See the README section **"Choosing an API Style"** for a full comparison of when to use each.

---

## Timeline

- **v0.2.0**: `maximize/2`, `minimize/2`, and old `add_variables/5` marked as deprecated
- **v0.3.0**: These will emit deprecation warnings at compile time
- **v1.0.0**: Deprecated functions will be removed

## Support

If you need help, please:

1. Check the [DSL Syntax Reference](../reference/dsl-syntax.md)
2. Look at the updated examples in the [Examples Directory](../examples/README.md)
3. Review the [Comprehensive Tutorial](../tutorial/comprehensive.md)

