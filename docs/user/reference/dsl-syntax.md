# DSL Syntax Reference

**GOLDEN REFERENCE - DO NOT MODIFY WITHOUT EXPLICIT APPROVAL**

This document serves as the **canonical, unbreakable reference** for Dantzig DSL syntax. All implementations must support the syntax patterns documented here exactly as specified.

## Source of Truth

This reference is based on:

1. **`test/dantzig/dsl/experimental/simple_generator_test.exs`** - Marked as golden syntax
2. **`examples/nqueens_dsl.exs`** - Marked as golden syntax

## Quick Start

### Basic Problem Definition

```elixir
# Simple problem with variables and constraints
problem = Problem.define do
  new(name: "My Problem", description: "A simple optimization problem")

  # Add variables
  variables("x", [i <- 1..3], :continuous, "Decision variables")

  # Add constraints
  constraints([i <- 1..3], x(i) >= 0, "Non-negative constraint #{i}")

  # Set objective
  objective(sum(x(:_)), :maximize)
end
```

### When to Use Each Syntax

- **`Problem.define`**: Create new problems from scratch and add variables/constraints to existing problems
- **`Problem.modify`**: Amend existing problems with new or replacement variables/constraints/objectives
- **`Problem.add_variable`**: Add a single variable outside blocks
- **`Problem.add_constraint`**: Add a single constraint outside blocks
- **`Problem.set_objective`**: Set or replace the optimization objective outside blocks

## Core DSL Syntax

### Problem Definition

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")
  # ... variables, constraints, objectives
end
```

### Problem change

Once a problem has been defined, it can be amended with new variables, constraints, and objectives.

```elixir
problem = Problem.modify(problem) do
  # list of variables, constraints, objective
end
```

A problem can also be modified with new variables, constraints, and objectives outside of a `Problem.define` block with identical syntax. `Problem.modify()` can also modify existing variables, existing constraints (identified by their generated names). In this case, there is no creation of additional variables or constraints. A warning is issued if a variable or constraint with the same name already exists.

A `Problem.modify()` cannot contain a `new()` statement.

```elixir
problem = Problem.modify(problem) do
  new(name: "Problem Name", description: "Problem description") # Error: new() not allowed in Problem.modify()
end
```

`Problem.modify()` returns a new problem with the modifications applied.

`Problem.modify()` can also be called with parameters provided as a dictionary map with identical syntax:

```elixir
problem = Problem.modify(problem, model_parameters: model_parameters) do
  # list of variables, constraints, objective
end
```

### Variable Creation

#### Basic Variables (No Generators)

##### Definition in a single block

`variables/3` is used to define _individual_ variables one by one within a `Problem.define` or a `Problem.modify` block. `variables/3` cannot accept iterators.

(Note: `variables/3` is equivalent to `variables/4`, which can accept generators (see below) with an empty generator list: `variables("name", [], :type, "description")`. The empty generator list is equivalent to no generators provided. `variables/3` and `variables/4`, having different arities, are different functions.)

Variable deifinitions can include a minimum bound and/or a maximum bound provided as parameters for integer or continuous variables. The type of the variable dictates the type of the bounds. Infinity is denoted as:

- positive infinity: `:infinity`, `:infty`, `:inf`, `:pos_infinity`, `:pos_infty`, `:pos_inf`
- negative infinity: `:neg_infinity`, `:neg_infty`, `:neg_inf`

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")

  # variables/3 takes a variable name, a type and a description
  variables("var_int_1", :integer, "Description")
  variables("var_int_2", :integer, "Desciption", min_bound: 0, max_bound: 100)
  variables("var_int_3", :integer, "Desciption", min_bound: 0, max_bound: :infinity)
  variables("var_int_4", :integer, "Desciption", min_bound: :neg_infty, max_bound: 13)

  variables("var_bin_1", :binary, "Description")

  variables("var_float_1", :continuous, "Description")
  variables("var_float_2", :continuous, "Desciption", min_bound: 0, max_bound: 100)
  variables("var_float_3", :continuous, "Desciption", min_bound: 0, max_bound: :infinity)
  variables("var_float_4", :continuous, "Desciption", min_bound: :neg_infty, max_bound: 13)
  variables("var_float_2", :continuous, "Desciption", min_bound: 0.889, max_bound: 100.864)
  variables("var_float_3", :continuous, "Desciption", min_bound: -235.12, max_bound: :infinity)
  variables("var_float_4", :continuous, "Desciption", min_bound: :neg_infty, max_bound: 13.29345)
end
```

The following statements generate errors.

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")

  variables("var_int_1", :integer, "Description", min_bound: 0.0, max_bound: 100e5) # No floating point values allowed for integers

  variables("var_bin_1", :binary, "Description", min_bound: 0) # Binary variables have no bounds
  variables("var_bin_2", :binary, "Description", max_bound: :inf) # Binary variables have no bounds
end
```

##### Basic Variables - Definition in a separate block

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")
end

problem = Problem.modify(problem) do
  variables("var_name_1", :binary, "Description")
  variables("var_name_2", :continuous, "Description")
end
```

#### Generator Variables (Single Dimension)

`variables/4` is used to define _multiple_ variables at once within a `Problem.define` or a `Problem.modify` block. `variables/4` can accept iterators.

Generators are always in the form of `[variable <- list]` or `[variable <- generator]`, or a combination of both provided as a list: `[variable_1 <- list, variable_2 <- generator, {var3, var4} <- generator_map]`.

For example:

- `[food <- ["bread", "milk"]]`
- `[i <- 1..4]`
- `[i <- 1..4, j <- 1..4]`
- `[i <- 1..4, j <- 1..4 where i != j]` (In a future extension)
- `food_names = ["bread", "milk"]` and `[food <- food_names]`
- `[{k, v} <- [{"bread", 1}, {"milk", 2}]]`

Internally those are converted to quoted expressions like `quote(do: [food <- ["bread", "milk"]])` or `quote(do: [i <- 1..4])` or `[quote(do: i) <- 1..4, quote(do: j) <- 1..4]`. But that syntax with `quote(do: ...)` is not allowed in the DSL.

An empty generator list such as `variables("var_name", [], :binary, "Description")` is equivalent to `variables("var_name", :binary, "Description")`. This is a special case equivalent to `variables/3`.

##### Single Generator Variables - Definition in a single block

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")

  # Using literal lists
  # variables/4 takes a variable name, a list of generators, a type and a description
  # It would generate a list of variables/3 for each combination of the generators
  # For example, if food_names = ["bread", "milk"], it would generate:
  # variables("qty_bread", :continuous, "Amount of bread")
  # variables("qty_milk", :continuous, "Amount of milk")
  variables("qty", [food <- ["bread", "milk"]], :continuous, "Amount of food")
end
```

##### Single Generator Variables - Definition in a separate block

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")
end

problem = Problem.modify(problem) do
  # variables/4 takes a variable name, a list of generators, a type and a description
  variables("qty", [food <- ["bread", "milk"]], :continuous, "Amount of food")
end

```

##### Definition of a model providing parameters as a map

```elixir
modelParameters = %{food_names: ["bread", "milk"]}

problem = Problem.define(model_parameters: model_parameters) do
  new(name: "Problem Name", description: "Problem description")
  variables("qty", [food <- food_names], :continuous, "Amount of food")
end
```

or, equivalently in multiple blocks:

```elixir
problem = Problem.define do
  new(name: "Problem Name", description: "Problem description")
end

modelParameters = %{food_names: ["bread", "milk"]}
problem = Problem.modify(problem, model_parameters: model_parameters) do
  variables("qty", [food <- food_names], :continuous, "Amount of food")
end
```

#### Generator Variables (Multiple Dimensions)

```elixir
# 2D variables
problem = Problem.define do
  new(name: "2D Example", description: "2D variables example")
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")
  # It would generate 16 variables/3 like:
  # variables("queen2d_1_1", :binary, "Queen position 1,1")
  # variables("queen2d_1_2", :binary, "Queen position 1,2")
  # ...
  # variables("queen2d_4_4", :binary, "Queen position 4,4")
end
```

```elixir
# 3D variables
problem = Problem.define do
  new(name: "3D Example", description: "3D variables example")
  variables("queen3d", [i <- 1..4, j <- 1..4, k <- 1..4], :binary, "Queen position")
end
```

##### Definition using a model parameters map

```elixir
modelParameters = %{max_i: 4, max_j: 4, max_k: 4}

problem = Problem.define(model_parameters: model_parameters) do
  new(name: "3D Example", description: "3D variables example")
  variables("queen3d", [i <- 1..max_i, j <- 1..max_j, k <- 1..max_k], :binary, "Queen position")
  # It would generate max_i x max_j x max_k variables/3 statements like:
  # variables("queen3d_1_1_1", :binary, "Queen position 1,1,1")
  # variables("queen3d_1_1_2", :binary, "Queen position 1,1,2")
  # ...
  # variables("queen3d_1_1_#{max_k}", :binary, "Queen position 1,1,#{max_k}")
  # variables("queen3d_1_2_1", :binary, "Queen position 1,2,1")
  # ...
  # variables("queen3d_1_2_#{max_k}", :binary, "Queen position 1,2,#{max_k}")
  # variables("queen3d_1_3_1", :binary, "Queen position 1,3,1")
  # ...
  # variables("queen3d_1_#{max_j}_#{max_k}", :binary, "Queen position 1,#{max_j},#{max_k}")
  # ...
  # variables("queen3d_#{max_i}_#{max_j}_#{max_k}", :binary, "Queen position #{max_i},#{max_j},#{max_k}")
end
```

#### Variables - Adding variables to a problem

When adding one or several variables outside a `Problem.define` block to an existing problem, we use 2 approaches:

- use a `Problem.modify` block with `variables()` as above.
- use `Problem.add_variable()` one by one outside of a block. In this case, there cannot be any generators

The following 2 examples should behave the same way and should produce the same result.

##### Approach 1: Using a `Problem.modify` block

```elixir
# Defining variables within the problem definition
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")
end

problem = Problem.modify(problem) do
  variables("x", [i <- 1..4], :binary, "X variables")
  variables("y", [i <- 1..4], :binary, "Y variables")
end
```

##### Approach 2: Using `Problem.add_variable()` one by one

```elixir
# 2D variables
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")
  variables("x", [i <- 1..4], :binary, "X variables")
end

problem = Problem.add_variable(problem, "y_1", :binary, "Y variables 1")
problem = Problem.add_variable(problem, "y_2", :binary, "Y variables 2")
problem = Problem.add_variable(problem, "y_3", :binary, "Y variables 3")
problem = Problem.add_variable(problem, "y_4", :binary, "Y variables 4")
```

Note that we internally transform the former syntax to the latter syntax when adding variables to a problem.

### Constraint Creation

`constraints/2` is used to define _individual_ constraints one by one within a `Problem.define` or a `Problem.modify` block. `constraints/2` cannot accept iterators.

(Note: `constraints/2` is equivalent to `constraints/3`, which can accept generators (see below) with an empty generator list: `constraints([], expression, "description")`. The empty generator list is equivalent to no generators provided.)

#### Simple Constraints (No Generators)

`constraints/2` is used to define _individual_ constraints one by one within a `Problem.define` or a `Problem.modify` block. `constraints/2` cannot accept iterators.

```elixir
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")

  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # constraints/2 takes a constraint and a description
  constraints(queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4 == 1, "One queen per row 1")
  constraints(queen2d_2_1 + queen2d_2_2 + queen2d_2_3 + queen2d_2_4 == 1, "One queen per row 2")
  constraints(queen2d_3_1 + queen2d_3_2 + queen2d_3_3 + queen2d_3_4 == 1, "One queen per row 3")
  constraints(queen2d_4_1 + queen2d_4_2 + queen2d_4_3 + queen2d_4_4 == 1, "One queen per row 4")
end
```

#### Constraint with automatic indexing

With numerical ranges:

```elixir
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")

  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # constraints/2 takes a constraint and a description
  # :_ is a wildcard for any value of anindex
  # In this case,
  #   sum(queen2d(:_, :_)) means something like:
  #   1) create a list of all possible indices:
  #      listIndices = list of tuples (i, j) where i and j are integers between 1 and 4
  #   2) create a list of all possible queen2d variables:
  #      listVariables = list of queen2d(i, j) where i and j are integers between 1 and 4
  #   3) sum all the queen2d variables.

  # The constraints/2 has no iterators like constraints/3 (see below). This statement
  # creates a SINGLE constraint summing ALL the queen2d variables.
  constraints(sum(queen2d(:_, :_)) == 4, "4 queens in total")
  # It would generate a single constraint/2 statement like:
  # constraints(
  #     queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4 +
  #     queen2d_2_1 + queen2d_2_2 + queen2d_2_3 + queen2d_2_4 +
  #     queen2d_3_1 + queen2d_3_2 + queen2d_3_3 + queen2d_3_4 +
  #     queen2d_4_1 + queen2d_4_2 + queen2d_4_3 + queen2d_4_4 == 4, "4 queens in total")
end
```

With user supplied iterators:

```elixir
iterators = %{var_1: iterator_1, var_2: iterator_2}

problem = Problem.define(modelParameters: iterators) do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")

  variables("val", [var_1 <- iterator_1, var_2 <- iterator_2], :binary, "Variable description")

  constraints(sum(val(:_, :_)) == 4, "sum of all vals across all var_1 and var_2 possibilities")
end
```

#### Generator Constraints

```elixir
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")

  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # constraints/3 takes a list of generators, a constraint and a description
  # Here the generator will create one constraints/2 for each combination of the generators
  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row")
  # This will generate 4 constraints/2 like:
  # constraints(sum(queen2d(1, :_)) == 1, "One queen per row 1")
  # constraints(sum(queen2d(2, :_)) == 1, "One queen per row 2")
  # constraints(sum(queen2d(3, :_)) == 1, "One queen per row 3")
  # constraints(sum(queen2d(4, :_)) == 1, "One queen per row 4")

  # In turn, the constraints/2 will generate:
  # constraints(queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4 == 1, "One queen per row 1")
  # constraints(queen2d_2_1 + queen2d_2_2 + queen2d_2_3 + queen2d_2_4 == 1, "One queen per row 2")
  # constraints(queen2d_3_1 + queen2d_3_2 + queen2d_3_3 + queen2d_3_4 == 1, "One queen per row 3")
  # constraints(queen2d_4_1 + queen2d_4_2 + queen2d_4_3 + queen2d_4_4 == 1, "One queen per row 4")
end
```

#### Multiple generators

```elixir
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")
  variables("queen3d", [i <- 1..2, j <- 1..2, k <- 1..3], :binary, "Queen position")

  # Multiple generators
  # In the following statement, we have 2 generators: i <- 1..2 and k <- 1..3.
  constraints([i <- 1..2, k <- 1..3], sum(queen3d(i, :_, k)) == 1, "One queen on first axis #{i} and 3rd axis #{k}")
  # The statement will create 6 constraints/2 like:
  # constraints(sum(queen3d(1, :_, 1)) == 1, "One queen on first axis 1 and 3rd axis 1")
  # constraints(sum(queen3d(1, :_, 2)) == 1, "One queen on first axis 1 and 3rd axis 2")
  # constraints(sum(queen3d(1, :_, 3)) == 1, "One queen on first axis 1 and 3rd axis 3")
  # constraints(sum(queen3d(2, :_, 1)) == 1, "One queen on first axis 2 and 3rd axis 1")
  # constraints(sum(queen3d(2, :_, 2)) == 1, "One queen on first axis 2 and 3rd axis 2")
  # constraints(sum(queen3d(2, :_, 3)) == 1, "One queen on first axis 2 and 3rd axis 3")
  #
  # In turn, the 6 constraints/2 will respectively generate:
  # constraints(queen3d_1_1_1 + queen3d_1_2_1 == 1, "One queen on first axis 1 and 3rd axis 1")
  # constraints(queen3d_1_1_2 + queen3d_1_2_2 == 1, "One queen on first axis 1 and 3rd axis 2")
  # constraints(queen3d_1_1_3 + queen3d_1_2_3 == 1, "One queen on first axis 1 and 3rd axis 3")
  # constraints(queen3d_2_1_1 + queen3d_2_2_1 == 1, "One queen on first axis 2 and 3rd axis 1")
  # constraints(queen3d_2_1_2 + queen3d_2_2_2 == 1, "One queen on first axis 2 and 3rd axis 2")
  # constraints(queen3d_2_1_3 + queen3d_2_2_3 == 1, "One queen on first axis 2 and 3rd axis 3")

end
```

#### Constraints - Adding constraints to a problem

The following 2 examples should behave the same way and should produce the same result.

```elixir
# Defining constraints within the problem definition
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # Single generator
  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row")
  constraints([j <- 1..4], sum(queen2d(:_, j)) == 1, "One queen per column")
end
```

```elixir
problem = Problem.define do

  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # Single generator
  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row")
end

problem = Problem.modify(problem) do
  constraints([j <- 1..4], sum(queen2d(:_, j)) == 1, "One queen per column")
end
```

#### Adding constraints to a problem one constraint at a time

Similarly to `Problem.add_variable()`, it is possible to add constraints one at a time, outside of a `Problem.define` or a `Problem.modify` block. As with `Problem.add_variable()`, `Problem.add_constraint()` cannot contain generators.

```elixir
# Create problem with variables
problem = Problem.define do
  new(name: "Constraint Example", description: "Adding constraints one by one")
  variables("queen2d", [i <- 1..2, j <- 1..2], :binary, "Queen position")
end

# Add constraints one by one (no generators allowed)
problem = Problem.add_constraint(problem, queen2d_1_1 + queen2d_1_2 == 1, "Row 1 constraint")
problem = Problem.add_constraint(problem, queen2d_2_1 + queen2d_2_2 == 1, "Row 2 constraint")
problem = Problem.add_constraint(problem, queen2d_1_1 + queen2d_2_1 == 1, "Column 1 constraint")
problem = Problem.add_constraint(problem, queen2d_1_2 + queen2d_2_2 == 1, "Column 2 constraint")
```

`Problem.add_constraint()` returns a new problem with the constraint added.

**Note**: The expression `queen2d_1_1 + queen2d_1_2 == 1` must use the actual names (e.g., `queen2d_1_1`) that were generated by the `variables()` call, not the pattern generator syntax like `queen2d(1, :_)`.

### Objective Functions

#### Simple Objectives

```elixir
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  objective(queen2d_1_1 + queen2d_1_2 + queen2d_2_1 + queen2d_2_2, :maximize)
end
```

`objective()` MUST specify the direction of the optimization (either `:minimize` or `:maximize`). No default is provided.

#### Generator Objectives

##### Single Generator

```elixir
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # Using sum with patterns
  objective(sum(queen2d(:_, :_)), :maximize)
  # It would generate a single objective/2 statement like:
  objective(
    queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4 +
    queen2d_2_1 + queen2d_2_2 + queen2d_2_3 + queen2d_2_4 +
    queen2d_3_1 + queen2d_3_2 + queen2d_3_3 + queen2d_3_4 +
    queen2d_4_1 + queen2d_4_2 + queen2d_4_3 + queen2d_4_4,
    :maximize)
end
```

Note that a define block can only contain one objective function.

```elixir
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # Using sum with patterns
  objective(sum(queen2d(:_, :_)), :maximize)

  # Add another objective
  objective(sum(queen2d(:_, :_)), :maximize) # <-- This triggers an error even if the objective is identical.>
end
```

But an objective can always be set outside a `Problem.define` block with `Problem.set_objective()`. If there was a previously existing objective, only a warning is triggered, not an error.

```elixir
problem = Problem.define do
  new(name: "Adding variables to a problem", description: "Adding variables to a problem")
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")
end

# First definition of an objective (none specified in the `Problem.define()` block)
problem = Problem.set_objective(
  problem,
  queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4 +
  queen2d_2_1 + queen2d_2_2 + queen2d_2_3 + queen2d_2_4 +
  queen2d_3_1 + queen2d_3_2 + queen2d_3_3 + queen2d_3_4 +
  queen2d_4_1 + queen2d_4_2 + queen2d_4_3 + queen2d_4_4,
  :maximize
) # <-- This triggers a warning about redefining the problem objective

problem = Problem.set_objective(
  problem,
  sum(queen2d(:_, :_)), # <-- ERROR: Not allowed because iterators are not allowed outside of Problem.define or Problem.modify
  :maximize
)
```

`Problem.set_objective()` returns a new problem with the objective set. It requires `:minimize` or `:maximize` to be specified as an argument.

`Problem.set_objective()` cannot include any generator.

##### Multiple Generators

The following 3 examples should be supported and should produce the same result:

```elixir
problem = Problem.define do
  # new(...)
  variables("qty", [food <- food_names], :continuous, "Amount of food")

  # Using sum with patterns
  objective(sum(qty(:_)), :minimize)
end
```

```elixir
problem = Problem.define do
  # new(...)
  variables("qty", [food <- food_names], :continuous, "Amount of food")

  # Using for comprehensions
  objective(sum(for food <- food_names, do: qty(food)), :minimize)
end
```

```elixir
problem = Problem.define do
  # new(...)
  variables("qty", [food <- food_names], :continuous, "Amount of food")
end

# Using for comprehensions
problem = Problem.set_objective(
  problem,
  sum(for food <- food_names, do: qty(food)),
  :minimize
)
```

##### Generator redefinition

In the following example, the second definition of "queen2d" should trigger an error and should not be allowed. An error message should be generated indicating that that redefining a variable is not allowed and the problem should not be created.

```elixir
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position") # <--- THIS TRIGGERS AN ERROR>
end
```

Note that the following would be OK as the final generated variable names have different indices (and actual name in the problem definition).

```elixir
problem = Problem.define do
  # new(...)
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")
  variables("queen2d", [i <- 5..8, j <- 5..8], :binary, "Queen position") # <--- THIS DOES NOT TRIGGER AN ERROR
  variables("queen2d", [i <- 1..4, j <- 5..8], :binary, "Queen position") # <--- THIS DOES NOT TRIGGER AN ERROR
  variables("queen2d", [i <- 5..8, j <- 1..4], :binary, "Queen position") # <--- THIS DOES NOT TRIGGER AN ERROR
```

## Complete Working Examples

### Example 1: Simple Generator (Golden Reference)

```elixir
defmodule Dantzig.DSL.SimpleGeneratorTest do
  @moduledoc """
  The syntax in this module is _golden_.
  It should be considered the canonical way to write generator syntax.
  """

  test "Simple generator syntax" do
    params = %{food_names: ["bread", "milk"]}

    problem =
      Problem.define(model_parameters: params) do
        new(name: "Simple Test", description: "Test generator syntax")
        variables("qty", [food <- food_names], :continuous, "Amount of food")
      end

    assert length(problem.variable_defs) == 2
    assert Map.has_key?(problem.variable_defs, "qty_bread")
    assert Map.has_key?(problem.variable_defs, "qty_milk")
  end

  test "Generator with objective" do
    params = %{food_names: ["bread", "milk"]}

    problem =
      Problem.define(model_parameters: params) do
        new(name: "Simple Test", description: "Test generator with objective")
        variables("qty", [food <- food_names], :continuous, "Amount of food")
        objective(sum(for food <- food_names, do: qty(food)), :minimize)
      end

    assert problem.direction == :minimize
    assert problem.objective != nil
  end
end
```

### Example 2: N-Queens Problem

```elixir
# N-Queens problem using the new DSL
require Dantzig.Problem, as: Problem
require Dantzig.Problem.DSL, as: DSL

# Create the problem
problem2d =
  Problem.define do
    new(
      name: "N-Queens",
      description: "Place N queens on an N×N chessboard so that no two queens attack each other."
    )

    # Add binary variables for queen positions (4x4 board)
    variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

    # Add constraints: one queen per row
    constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row")

    # Add constraints: one queen per column
    constraints([j <- 1..4], sum(queen2d(:_, j)) == 1, "One queen per column")

    # Set objective (squeeze as many queens as possible)
    objective(sum(queen2d(:_, :_)), :maximize)
  end
```

## Function Signatures

### Inside Problem.define and Problem.modify blocks

- `variables("name", :type, "description")` - single variable (variables/3)
- `variables("name", [generators], :type, "description")` - multiple variables (variables/4)
- `constraints(expression, "description")` - single constraint (constraints/2)
- `constraints([generators], expression, "description")` - multiple constraints (constraints/3)
- `objective(expression, :direction)` - objective function (objective/2)

### Outside blocks (imperative)

- `Problem.add_variable(problem, "name", :type, "description")` - single variable
- `Problem.add_constraint(problem, expression, "description")` - single constraint
- `Problem.set_objective(problem, expression, :direction)` - objective function

### Key Differences

- **Inside blocks**: Can use generators `[i <- 1..4]`
- **Outside blocks**: Cannot use generators - must be singular

## Key Syntax Rules

### 1. Generator Syntax

- **Format**: `[variable <- list]` or `[variable <- generator]`
- **Multiple dimensions**: `[i <- 1..4, j <- 1..4]` or `[var_1 <- generator_1, var_2 <- generator_2]`
- **Provided model parameters**: Must be supported (e.g., `[food <- food_names]`) - food_names should be identified as an unknown symbol and looked up in the model parameters
- **Literal lists**: Must be supported (e.g., `[food <- ["bread", "milk"]]`)

### 2. Variable Access

`:_` is a special symbol that means "_iterate through all values_".

If a symbol is used instead of `:_`, it means "_for each value of the symbol generate a statement_".

**Bracket notation** (preferred for indexed access):

- `x[i]` — access variable `x` at index `i` (same key as used in the generator)
- `assign[worker][task]` — access 2D variable at keys `worker`, `task`
- `x[i][:_]` — wildcard: all values of the second dimension, for fixed `i`
- `x[:_]` — wildcard: all values of the (1D) variable

Bracket notation uses the generator value directly as the key — the same value used in `variables("x", [i <- 1..n], ...)` is the key for `x[i]`. This allows a **unified syntax** for both variables and constants.

**Parenthesis notation** (alternative, also supports wildcards):

- `queen2d(i, :_)` — "_for each value of i, all values of the second dimension_"
- `queen2d(:_, j)` — "_all values of the first dimension, for each j_"
- `queen2d(:_, :_)` — "_all values across both dimensions_"

Both notations support wildcards. Bracket notation is preferred for its uniformity with constant access.

### 3. Sum Functions

- **Pattern sums**: `sum(queen2d(i, :_))` means "_create a sum statement for each value of the first iterator (i) where all the values of the second iterator (j) are summed_".
- **For comprehensions**: `sum(for food <- food_names, do: qty(food))` means "_create a sum statement for each value of the food iterator (food) where the value of the `qty`'s variables are summed_".
- **All variables**: `sum(queen2d(:_, :_))` means "_create a single sum statement where all the values of the `queen2d`'s variables (every cross product of the first iterator (i) and the second iterator (j)) are summed_".

### 4. Pattern Functions

The DSL supports several pattern functions that expand expressions with wildcards:

#### Sum Function

- **Pattern sums**: `sum(queen2d(i, :_))` expands to `queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4` for each value of `i`
- **All variables**: `sum(queen2d(:_, :_))` expands to a single sum of all queen2d variables
- **Generator sums**: `sum(for food <- food_names, do: qty(food))` expands to `qty_bread + qty_milk`

#### Max Function (Future Extension)

- **Pattern max**: `max(queen2d(i, :_))` expands to `max(queen2d_1_1, queen2d_1_2, queen2d_1_3, queen2d_1_4)` for each value of `i`
- **All variables**: `max(queen2d(:_, :_))` expands to `max(queen2d_1_1, queen2d_1_2, ..., queen2d_4_4)`

#### Min Function (Future Extension)

- **Pattern min**: `min(queen2d(i, :_))` expands to `min(queen2d_1_1, queen2d_1_2, queen2d_1_3, queen2d_1_4)` for each value of `i`
- **All variables**: `min(queen2d(:_, :_))` expands to `min(queen2d_1_1, queen2d_1_2, ..., queen2d_4_4)`

#### Count Function (Future Extension)

- **Pattern count**: `count(queen2d(i, :_))` expands to `queen2d_1_1 + queen2d_1_2 + queen2d_1_3 + queen2d_1_4` for each value of `i` (same as sum for binary variables)
- **All variables**: `count(queen2d(:_, :_))` expands to sum of all queen2d variables

Note: `max()` and `min()` functions require linearization techniques for linear optimization solvers.

### 5. Constraint Descriptions

- **Static**: `"One queen per row"`
- **Dynamic with interpolation**: `"One queen per row #{i}"` expands to:
  - `"One queen per row 1"` for i=1
  - `"One queen per row 2"` for i=2
  - `"One queen per row 3"` for i=3
  - `"One queen per row 4"` for i=4
- **Multiple variable interpolation**: `"One queen on axis #{i} and #{k}"` expands to:
  - `"One queen on axis 1 and 1"` for i=1, k=1
  - `"One queen on axis 1 and 2"` for i=1, k=2
  - etc.

### 6. Access to Constants and to Enumerated Constants

Constraint definitionas and objectives can access named constants and named enumerated constants. The constants are passed via the `model_parameters` dictionary argument of the `Problem.define()` or `Problem.modify()` macros.

#### Named Constant

A _Named constants_ is a single value (no index) passed as a single key in the `model_parameters` dictionary. Here are a list of valid examples.

##### Named Constant _not_ used in the formulas

```elixir
problem = Problem.define(model_parameters: %{max_queens: 8}) do
  new(name: "Problem Name", description: "Problem description")
  variables("queen2d", [i <- 1..max_queens, j <- 1..max_queens], :binary, "Queen position")
end

```

##### Named Constant(s) used in the formulas

```elixir
# Example 1
problem = Problem.define(model_parameters: %{multiplier: 7.0}) do
  new(name: "Problem Name", description: "Problem description")
  variables("x1", :continuous, "X1")
  variables("x2", :continuous, "X2")

  # The DSL identifies variables (here `x1` and `x2`) as variables, and constants (here `multiplier`)
  constraints( x2 + multiplier * x1 <= 10, "Max constraint" )
end
```

```elixir
# Example 2
problem = Problem.define(model_parameters: %{multiplier_1: 7.0, multiplier_2: -5.0}) do
  new(name: "Problem Name", description: "Problem description")
  variables("x1", :continuous, "X1")
  variables("x2", :continuous, "X2")

  # The DSL identifies variables (here `x1` and `x2`) as variables, and constants (here `multiplier`)
  constraints( multiplier_1 * x1 - x2 * multiplier_2 <= 10, "Max constraint" )
end
```

#### Enumerated (Indexed) Constants

A _Named enumerated constant_ is an indexed set of values passed in the `model_parameters` dictionary. The index is either integer-like (like in the case of a map with integer keys), or more general (as in a map with string or atom keys). The index can be multidimensional.

> **Important**: Generator variables (e.g. `i` in `[i <- 1..4]`) produce the exact integer values from the range. Use a map with matching integer keys so that `multiplier[i]` resolves correctly for any range, including non-zero-based ranges like `2..99` or `(-7)..7`.

```elixir
# Example 1: indexed constants - 1 dimension, range 1..4
# Use a map with integer keys matching the generator range.
# Bracket notation x[i] is used uniformly for both variables and constants.
problem = Problem.define(model_parameters: %{multiplier: %{1 => 4.0, 2 => 5.0, 3 => 6.0, 4 => 7.0}}) do
  new(name: "Problem Name", description: "Problem description")
  variables( "x", [i <- 1..4], :continuous, "Xs")

  constraints( sum( for i <-  1..4, do: x[i] * multiplier[i]) <= 10, "Max constraint" )
end
```

```elixir
# Example 2: 2D indexed constants, ranges 1..2 and 1..3
# Use a nested map with integer keys for each dimension
problem = Problem.define(model_parameters: %{matrix: %{1 => %{1 => 4.0, 2 => 5.0, 3 => 6.0}, 2 => %{1 => 7.0, 2 => 8.0, 3 => 9.0}}}) do
  new(name: "Problem Name", description: "Problem description")
  variables( "x", [i <- 1..2, j <- 1..3], :continuous, "Xs")

  constraints( sum( for i <-  1..2, j <- 1..3, do: x[i][j] * matrix[i][j]) <= 10, "Max constraint" )
end
```

```elixir
# For 0-based ranges, plain lists work because Elixir list access is 0-based
problem = Problem.define(model_parameters: %{multiplier: [4.0, 5.0, 6.0, 7.0]}) do
  variables( "x", [i <- 0..3], :continuous, "Xs")
  constraints( sum( for i <- 0..3, do: x[i] * multiplier[i]) <= 10, "Max constraint" )
end
```

```elixir
# Multidimensional indexed named constants
# Cost matrix: cost[worker][task] = cost of assigning worker to task
cost_matrix = %{
  "Alice" => %{"Task1" => 2, "Task2" => 3, "Task3" => 1},
  "Bob" => %{"Task1" => 4, "Task2" => 2, "Task3" => 3},
  "Charlie" => %{"Task1" => 3, "Task2" => 1, "Task3" => 4}
}

workers = Enum.keys(cost_matrix)
# Tasks is the set of all possible tasks across all workers
tasks = Enum.flat_map(cost_matrix, fn {_, v} -> Map.keys(v) end) |> MapSet.new()

problem = Problem.define(model_parameters: %{cost: cost_matrix, workers: workers, tasks: tasks}) do
  new(name: "Assignment Problem", description: "Assign workers to tasks at minimum cost")
  variables("assign", [worker <- workers, task <- tasks], :binary, "Assignment variable")
  constraints(
    [task <- tasks],
    sum(for worker <- workers, do: assign[worker][task]) == 1,
    "Each task assigned to exactly one worker #{task}"
  )
  constraints(
    [worker <- workers],
    sum(for task <- tasks, do: assign[worker][task]) <= 1,
    "Each worker assigned to at most one task #{worker}"
  )

  # Objective: minimize total cost — bracket notation for both assign (variable) and cost (constant)
  objective(
    sum(
      for worker <- workers,
          task <- tasks,
          do: assign[worker][task] * cost[worker][task]
    ),
    :minimize
  )
end
```

```elixir
# Multidimensional indexed named constants in both constraints and objective
# Cost matrix: cost[worker][task] = cost of assigning worker to task
cost_matrix = %{
  "Alice" => %{"Task1" => 2, "Task2" => 3, "Task3" => 1},
  "Bob" => %{"Task1" => 4, "Task2" => 2, "Task3" => 3},
  "Charlie" => %{"Task1" => 3, "Task2" => 1, "Task3" => 4}
}

workers = Enum.keys(cost_matrix)
# Tasks is the set of all possible tasks across all workers
tasks = Enum.flat_map(cost_matrix, fn {_, v} -> Map.keys(v) end) |> MapSet.new()

problem = Problem.define(model_parameters: %{cost: cost_matrix, workers: workers, tasks: tasks}) do
  new(name: "Assignment Problem", description: "Assign workers to tasks at minimum cost")
  variables("assign", [worker <- workers, task <- tasks], :binary, "Assignment variable")
  constraints(
    [task <- tasks],
    sum(for worker <- workers, do: assign[worker][task]) == 1,
    "Each task assigned to exactly one worker #{task}"
  )
  constraints(
    [worker <- workers],
    sum(for task <- tasks, do: assign[worker][task]) <= 1,
    "Each worker assigned to at most one task #{worker}"
  )

  constraints(
    sum(
      for worker <- workers,
          task <- tasks,
          do: assign[worker][task] * cost[worker][task]) >= 0,
          "The overall cost is positive"
  )

  # Objective: minimize total cost — bracket notation for both variables and constants
  objective(
    sum(
      for worker <- workers,
          task <- tasks,
          do: assign[worker][task] * cost[worker][task]
    ),
    :minimize
  )
end
```

## Implementation Requirements

The DSL implementation MUST support:

1. **Model parameter lookup** in generators: `[food <- food_names]` - food_names should be identified as an unknown symbol and looked up in the model parameters. If a symbol is not found in the model parameters, an error should be raised.
2. **Literal lists** in generators: `[food <- ["bread", "milk"]]`
3. **Literal dictionaries** in generators: `[k, v <- [{"bread", 1}, {"milk", 2}]]`
4. **Range syntax**: `[i <- 1..4, j <- 1..4]`
5. **Pattern matching** in variable access: `queen2d(i, :_)`
6. **Pattern functions** with wildcards: `sum(queen2d(i, :_))`, `max(queen2d(i, :_))`, `min(queen2d(i, :_))`, `count(queen2d(i, :_))`
7. **For comprehensions** in objectives: `sum(for food <- food_names, do: qty(food))`
8. **Variable interpolation** in constraint descriptions: `"One queen per row #{i}"`
9. **Constraint deduplication** and naming clash warnings
10. **Variable range validation** for constraints

## Error Cases

The following are NOT currently supported or should be clearly documented as limitations:

1. **Nested generators** beyond the documented patterns
2. **Complex expressions** in generator lists that cannot be evaluated at compile time
3. **Dynamic constraint names** that cannot be resolved at compile time

- `Problem.add_variable()` - no generators allowed
- `Problem.add_constraint()` - no generators allowed
- `Problem.set_objective()` - no generators allowed

Those limitations are due to the semantics of Elixir macros: it is not possible to provide generators as arguments to macros. `Problem.add_variables(problem, [i <- 1..4], "x", :binary, "Description")` cannot be implemented because it would require a macro to accept a list of generators as an argument.

## Error Handling

### Constraint Redefinition

If a constraint with the same name is added multiple times, an error is issued:

```elixir
problem = Problem.define do
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row")
  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per row") # Error: duplicate constraint
end
```

### Variable Range Mismatch

If constraint ranges don't match variable ranges, an error is raised:

```elixir
problem = Problem.define do
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # ERROR: constraint range (1..5) doesn't match variable range (1..4)
  constraints([i <- 1..5], sum(queen2d(i, :_)) == 1, "One queen per row")
end
```

### Unknown Variables in Constraints

If a variable referenced in a constraint hasn't been declared, an error is raised:

```elixir
problem = Problem.define do
  variables("queen2d", [i <- 1..4, j <- 1..4], :binary, "Queen position")

  # ERROR: queen3d variable not declared
  constraints([i <- 1..4], sum(queen3d(i, :_)) == 1, "One queen per row")
end
```

## Testing Requirements

All syntax patterns in this reference must:

1. **Compile without errors**
2. **Execute successfully**
3. **Produce expected results**
4. **Be covered by tests**

## Troubleshooting

### Common DSL Errors

#### 1. "Undefined variable" errors

**Problem**: `error: undefined variable "i"`

**Cause**: Using generator variables outside of `Problem.define` or `Problem.modify` blocks.

**Solution**: Move the code inside a `Problem.define` or `Problem.modify` block, or use imperative syntax with actual variable names. Generators are not available outside of `Problem.define` or `Problem.modify` blocks.

```elixir
# ❌ Wrong - generator outside block
problem = Problem.add_constraint(problem, queen2d(i, :_) == 1, "Constraint")

# ✅ Correct - inside block
problem = Problem.define do
  constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "Constraint")
end

# ✅ Correct - imperative with actual names
problem = Problem.add_constraint(problem, queen2d_1_1 + queen2d_1_2 == 1, "Constraint")
```

#### 2. "Function clause" errors

**Problem**: `** (FunctionClauseError) no function clause matching in Problem.new/1`

**Cause**: Passing wrong arguments to `Problem.new`.

**Solution**: Use keyword arguments.

```elixir
# ❌ Wrong
problem = Problem.new("My Problem")

# ✅ Correct
problem = Problem.define do
  new(name: "My Problem", description: "Description")
end
```

#### 3. Constraint name interpolation issues

**Problem**: Constraint names not interpolating correctly (e.g., "One queen per main diagonal" instead of "One queen per diagonal 1").

**Cause**: Missing variable placeholders in constraint descriptions.

**Solution**: Include variable placeholders in descriptions.

```elixir
# ❌ Wrong - no placeholder
constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per diagonal")

# ✅ Correct - with placeholder
constraints([i <- 1..4], sum(queen2d(i, :_)) == 1, "One queen per diagonal #{i}")
```

### Debugging DSL Issues

#### 1. Check variable names

Use `IO.inspect(problem.variables)` to see actual variable names generated.

#### 2. Verify constraint generation

Use `IO.inspect(problem.constraints)` to see generated constraints.

#### 3. Test with simple examples

Start with basic examples before adding complexity:

```elixir
# Start simple
problem = Problem.define do
  new(name: "Test", description: "Test")
  variables("x", :continuous, "Variable")
  constraints(x >= 0, "Non-negative")
end
```

### Migration from Old Syntax

#### From imperative to declarative

**Old syntax**:

```elixir
problem = Problem.new(name: "Test")
problem = Problem.add_variables(problem, [i <- 1..3], "x", :continuous)
problem = Problem.add_constraints(problem, [i <- 1..3], x(i) >= 0, "Constraint")
```

**New syntax**:

```elixir
problem = Problem.define do
  new(name: "Test", description: "Test")
  variables("x", [i <- 1..3], :continuous, "Variable")
  constraints([i <- 1..3], x(i) >= 0, "Constraint")
end
```

### Best Practices

#### 1. Use descriptive names

```elixir
# ✅ Good
variables("queen_position", [i <- 1..8, j <- 1..8], :binary, "Queen at position (i,j)")

# ❌ Poor
variables("q", [i <- 1..8, j <- 1..8], :binary, "q")
```

#### 2. Use interpolation for constraint names

```elixir
# ✅ Good - descriptive and unique
constraints([i <- 1..8], sum(queen_position(i, :_)) == 1, "One queen per row #{i}")

# ❌ Poor - not unique
constraints([i <- 1..8], sum(queen_position(i, :_)) == 1, "Row constraint")
```

#### 3. Group related variables

```elixir
# ✅ Good - logical grouping
problem = Problem.define do
  new(name: "Production Planning", description: "Production planning problem")

  # Production variables
  variables("produce", [product <- products, month <- months], :continuous, "Production amount")

  # Inventory variables
  variables("inventory", [product <- products, month <- months], :continuous, "Inventory level")

  # Constraints
  constraints([product <- products], sum(produce(product, :_)) >= demand(product), "Demand constraint")
end
```

#### 4. Use model parameters for flexibility

```elixir
# ✅ Good - parameterized
params = %{products: ["A", "B"], months: 1..12}
problem = Problem.define(model_parameters: params) do
  variables("produce", [product <- products, month <- months], :continuous, "Production")
end

# ❌ Poor - hardcoded
problem = Problem.define do
  variables("produce", [product <- ["A", "B"], month <- 1..12], :continuous, "Production")
end
```

## Performance Considerations

### Compile-time vs Runtime

The DSL is designed to generate efficient code at compile time:

- **Variable generation**: All variable combinations are generated at compile time
- **Constraint generation**: All constraint combinations are generated at compile time
- **Pattern expansion**: `sum()`, `max()`, `min()` functions are expanded at compile time

### Memory Usage

- **Variable storage**: Each generated variable is stored as a separate entry
- **Constraint storage**: Each generated constraint is stored as a separate entry
- **Large problems**: For problems with many variables/constraints, consider using model parameters to control size

### Optimization Tips

#### 1. Use appropriate variable types

```elixir
# ✅ Good - binary for yes/no decisions
variables("assign", [task <- tasks, worker <- workers], :binary, "Assignment")

# ❌ Poor - continuous for binary decisions
variables("assign", [task <- tasks, worker <- workers], :continuous, "Assignment")
```

#### 2. Minimize constraint complexity

```elixir
# ✅ Good - simple constraints
constraints([task <- tasks], sum(assign(task, :_)) == 1, "One worker per task")

# ❌ Poor - complex nested constraints (when possible)
constraints([task <- tasks], sum(for worker <- workers, do: assign(task, worker) * skill(worker)) >= 1, "Skilled worker")
```

#### 3. Use model parameters for scalability

```elixir
# ✅ Good - parameterized size
params = %{board_size: 8}
problem = Problem.define(model_parameters: params) do
  variables("queen", [i <- 1..board_size, j <- 1..board_size], :binary, "Queen position")
end

# ❌ Poor - hardcoded size
problem = Problem.define do
  variables("queen", [i <- 1..8, j <- 1..8], :binary, "Queen position")
end
```

## Version History

- **v1.0** - Initial reference based on golden test file and nqueens example
- **Future changes** - Must be explicitly approved and documented

---

**REMINDER: This is the GOLDEN REFERENCE. Do not modify without explicit approval.**
