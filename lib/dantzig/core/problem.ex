defmodule Dantzig.Problem do
  @moduledoc """
  Optimization model: variables, constraints, and objective.

  The `Problem` module provides the main interface for defining and managing
  optimization problems in Dantzig. It supports both a declarative DSL syntax
  and an imperative API.

  ## Problem Structure

  A problem holds:

  - `:direction` – `:maximize` or `:minimize`
  - `:objective` – a `Dantzig.Polynomial` (linear or quadratic)
  - `:variable_defs` – map of scalar variable name to `%Dantzig.ProblemVariable{}` containing
    optional bounds and `:type`
  - `:variables` – map of variable set name to index-to-monomial mapping
    (N‑D families; scalars appear with the empty tuple key `{}`)
  - `:constraints` – map of unique constraint id to `%Dantzig.Constraint{}`

  ## DSL Syntax (Recommended)

  The primary way to define problems is using the `define/1` and `modify/2` macros:

      require Dantzig.Problem, as: Problem

      problem = Problem.define do
        new(direction: :maximize)
        variables("x", [i <- 1..n], :continuous, min_bound: 0)
        constraints([i <- 1..n], x(i) <= limit[i], "Constraint")
        objective(sum(x(:_)), direction: :maximize)
      end

  With model parameters:

      problem = Problem.define(model_parameters: %{n: 10, limit: [1, 2, 3]}) do
        new(direction: :maximize)
        variables("x", [i <- 1..n], :continuous, min_bound: 0)
        constraints([i <- 1..n], x(i) <= limit[i], "Bound")
        objective(sum(x(:_)), direction: :maximize)
      end

  Modify an existing problem:

      modified = Problem.modify(problem) do
        constraints(x(1) >= 5, "Additional constraint")
      end

  ## Imperative API

  For programmatic problem building:

      problem = Problem.new(direction: :maximize)
      {problem, x} = Problem.new_variable(problem, "x", type: :continuous, min_bound: 0)
      problem = Problem.add_constraint(problem, Constraint.new(x <= 10))
      problem = Problem.set_objective(problem, x, direction: :maximize)

  ## Solving

  Once a problem is defined, solve it with:

      {:ok, solution} = Dantzig.solve(problem)

  ## Key Features

  - **Pattern-based modeling**: Use generators `[i <- 1..n]` to create N-dimensional variables
  - **Model parameters**: Pass runtime data via `model_parameters: %{...}`
  - **Automatic linearization**: Non-linear expressions (abs, max, min, and, or) are automatically linearized
  - **Incremental building**: Use `Problem.modify/2` to build problems incrementally

  ## See Also

  - `Dantzig.Polynomial` - Polynomial representation and operations
  - `Dantzig.Constraint` - Constraint creation and manipulation
  - `Dantzig.solve/1` - Solving optimization problems
  """
  alias Dantzig.Polynomial
  alias Dantzig.ProblemVariable
  alias Dantzig.Constraint
  alias Dantzig.SolvedConstraint
  alias Dantzig.Problem.DSLReducer

  @type t :: %__MODULE__{}

  defstruct variable_counter: 0,
            constraint_counter: 0,
            objective: Polynomial.const(0.0),
            direction: nil,
            name: nil,
            description: nil,
            variable_defs: %{},
            variables: %{},
            constraints: %{},
            contraints_metadata: %{}

  @spec solve_for_all_variables(t()) :: %{
          ProblemVariable.variable_namme() => SolvedConstraint.t()
        }
  def solve_for_all_variables(%__MODULE__{} = problem) do
    Enum.reduce(problem.constraints, %{}, fn {_id, constraint}, acc ->
      variable_names = Polynomial.variables(constraint.left_hand_side)

      Enum.reduce(variable_names, acc, fn variable_name, acc2 ->
        solved_constraint = Constraint.solve_for_variable(constraint, variable_name)

        if solved_constraint do
          Map.put(acc2, variable_name, solved_constraint)
        else
          acc2
        end
      end)
    end)
  end

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description)
    direction = Keyword.get(opts, :direction)

    %__MODULE__{
      name: name,
      description: description,
      direction: direction
    }
  end

  @spec add_constraint(t(), Constraint.t()) :: t()
  def add_constraint(problem, constraint) do
    constraint_id = generate_constraint_id(problem.constraint_counter)
    new_constraint_counter = problem.constraint_counter + 1

    %{
      problem
      | constraints: Map.put(problem.constraints, constraint_id, constraint),
        constraint_counter: new_constraint_counter
    }
  end

  @spec new_variable(t(), String.t(), keyword()) :: {t(), Polynomial.t()}
  def new_variable(problem, name, opts \\ []) do
    type = Keyword.get(opts, :type, :continuous)
    min_bound = Keyword.get(opts, :min_bound, nil)
    max_bound = Keyword.get(opts, :max_bound, nil)
    description = Keyword.get(opts, :description, nil)

    # Set default bounds for binary variables if not specified
    {final_min, final_max} =
      case {type, min_bound, max_bound} do
        {:binary, nil, nil} -> {0, 1}
        {:binary, nil, max_val} -> {0, max_val}
        {:binary, min_val, nil} -> {min_val, 1}
        _ -> {min_bound, max_bound}
      end

    variable = %ProblemVariable{
      name: name,
      type: type,
      min_bound: final_min,
      max_bound: final_max,
      description: description
    }

    new_problem = %{
      problem
      | variable_defs: Map.put(problem.variable_defs, name, variable),
        variable_counter: problem.variable_counter + 1
    }

    monomial = Polynomial.variable(name)

    # mirror scalar in N-D map with empty tuple key
    existing_map = Map.get(new_problem.variables, name, %{})
    updated_map = Map.put(existing_map, {}, monomial)

    newer_problem = %{
      new_problem
      | variables: Map.put(new_problem.variables, name, updated_map)
    }

    {newer_problem, monomial}
  end

  @spec new_unmangled_variable(t(), String.t(), keyword()) :: {t(), Polynomial.t()}
  def new_unmangled_variable(problem, name, opts \\ []) do
    new_variable(problem, name, opts)
  end

  @doc """
  Compatibility: add a variable with default settings.
  Returns {problem, monomial}.
  """
  def add_variable(problem, name) do
    new_variable(problem, name, [])
  end

  @spec new_variables(t(), [String.t()], keyword()) :: {t(), [Polynomial.t()]}
  def new_variables(problem, names, opts \\ []) do
    Enum.reduce(names, {problem, []}, fn name, {current_problem, monomials} ->
      {new_problem, monomial} = new_variable(current_problem, name, opts)
      {new_problem, [monomial | monomials]}
    end)
    |> then(fn {final_problem, monomials} -> {final_problem, Enum.reverse(monomials)} end)
  end

  @spec minimize(t(), Polynomial.t()) :: t()
  def minimize(problem, objective) do
    %{problem | objective: objective, direction: :minimize}
  end

  @spec maximize(t(), Polynomial.t()) :: t()
  def maximize(problem, objective) do
    %{problem | objective: objective, direction: :maximize}
  end

  @spec set_objective(t(), Polynomial.t()) :: t()
  def set_objective(problem, objective) do
    %{problem | objective: objective}
  end

  @spec increment_objective(t(), Polynomial.t()) :: t()
  def increment_objective(problem, objective_increment) do
    new_objective = Polynomial.add(problem.objective, objective_increment)
    %{problem | objective: new_objective}
  end

  @spec get_variable(t(), String.t()) :: ProblemVariable.t() | nil
  def get_variable(problem, name) do
    Map.get(problem.variable_defs, name)
  end

  @spec get_constraint(t(), String.t()) :: Constraint.t() | nil
  def get_constraint(problem, constraint_id) do
    Map.get(problem.constraints, constraint_id)
  end

  @spec get_variables_nd(t(), String.t()) :: map() | nil
  def get_variables_nd(problem, set_name) do
    Map.get(problem.variables, set_name)
  end

  @spec put_variables_nd(t(), String.t(), map()) :: t()
  def put_variables_nd(problem, set_name, var_map) do
    %{problem | variables: Map.put(problem.variables, set_name, var_map)}
  end

  # Imperative API functions for integration tests

  @doc """
  Add variables to a problem using imperative syntax.

  This macro supports the imperative API used in integration tests.
  """
  defmacro add_variables(problem, var_name, generators, var_type, description \\ nil) do
    # Transform raw generator syntax to proper AST format using the same approach as define macro
    transformed_generators =
      Macro.prewalk(generators, fn
        {:<-, meta, [var, range]} ->
          # Handle variables from outer scope by properly quoting them
          {:<-, meta, [quote(do: unquote(var)), range]}

        other ->
          other
      end)

    quote do
      # Ensure modules/macros are available in the generated context
      # Require both fully-qualified and aliased names so macros expand either way
      require Dantzig.Problem.DSL
      require Dantzig.Problem.DSL, as: DSL

      # Process the generators with the current environment
      unquote(__MODULE__).__add_variables_with_env__(
        unquote(problem),
        unquote(Macro.escape(transformed_generators)),
        unquote(var_name),
        unquote(var_type),
        unquote(description),
        binding()
      )
    end
  end

  @doc """
  Set objective function using imperative syntax.

  This macro supports the imperative API used in integration tests.
  """
  defmacro set_objective(problem, objective_expr, opts) do
    quote do
      # Ensure modules/macros are available in the generated context
      require Dantzig.Problem.DSL, as: DSL

      # Process the objective with the current environment
      unquote(__MODULE__).__set_objective_with_env__(
        unquote(problem),
        unquote(Macro.escape(objective_expr)),
        unquote(opts),
        binding()
      )
    end
  end

  # Helper functions for imperative API macro transformation

  @doc false
  defp transform_constraint_expression_to_ast(expr),
    do: Dantzig.Problem.AST.transform_constraint_expression_to_ast(expr)

  @doc """
  Solve the problem and return both solution and objective value.

  This is a convenience function for the new DSL that returns `{solution, objective}`.
  """
  @spec solve(t(), keyword()) :: {Dantzig.Solution.t(), number()} | :error
  def solve(%__MODULE__{} = problem, opts \\ []) do
    print_optimizer_input = Keyword.get(opts, :print_optimizer_input, false)

    case Dantzig.solve(problem, solver: :highs, print_optimizer_input: print_optimizer_input) do
      {:ok, solution} -> {solution, solution.objective}
      :error -> :error
    end
  end

  @doc """
  Macro entrypoint to define a problem with unqualified DSL calls inside a block.

  Supports inside the block:
  - `new(opts)` – initializes the problem
  - `variables(name, generators, type, opts_or_desc)` – adds variables
  - `constraints(generators, expr, desc \\ nil)` – adds constraints
  - `objective(expr, opts)` – sets objective

  Additionally, rewrites nested `sum(...)` calls to `Dantzig.Problem.DSL.sum/1`
  so they expand correctly without requiring explicit imports in user code.
  """
  defmacro define(do: block) do
    define_impl(block, [])
  end

  @doc """
  Macro entrypoint to define a problem with model parameters.

  Accepts `model_parameters:` keyword option to provide runtime values
  accessible within the DSL block.

  Example:
    Problem.define model_parameters: %{food_names: ["bread", "milk"]} do
      variables("qty", [food <- food_names], :continuous, "Amount")
    end
  """
  defmacro define(opts, do: block) when is_list(opts) do
    define_impl(block, opts)
  end

  # Internal implementation shared by define/1 and define/2
  defp define_impl(block, opts) do
    # Extract model_parameters AST from options if provided (will be evaluated at runtime)
    model_params_ast = Keyword.get(opts, :model_parameters, nil)

    # Rewrite nested calls that must be qualified (e.g., sum(...))
    # and transform generator syntax [var <- list] into quoted expressions
    rewritten_block =
      Macro.prewalk(block, fn
        {:sum, meta, args} ->
          {{:., meta, [Dantzig.Problem.DSL, :sum]}, meta, args}

        # Transform generator syntax [var <- list] into quoted expressions
        list when is_list(list) ->
          Enum.map(list, fn
            {:<-, meta2, [var2, range2]} ->
              {:<-, meta2, [quote(do: unquote(var2)), range2]}

            other ->
              other
          end)

        # Rewrite fully-qualified DSL.generators([...]) even if caller didn't require the macro
        {{:., m, [alias_ast, :generators]}, meta, [gen_arg]} ->
          case {alias_ast, gen_arg} do
            {{:__aliases__, _, [:Dantzig, :Problem, :DSL]}, list} when is_list(list) ->
              transformed =
                Enum.map(list, fn
                  {:<-, gmeta, [var, range]} -> {:<-, gmeta, [quote(do: unquote(var)), range]}
                  other -> other
                end)

              transformed

            _ ->
              {{:., m, [alias_ast, :generators]}, meta, [gen_arg]}
          end

        other ->
          other
      end)

    # Normalize block to a flat list of expressions
    exprs =
      case rewritten_block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    quote do
      # Ensure modules/macros are available in the generated context
      require Dantzig.Problem.DSL, as: DSL

      # Evaluate model parameters at runtime and merge with caller bindings
      model_params = unquote(model_params_ast || quote(do: %{}))
      caller_binding = binding()

      # Merge model parameters into binding for variable resolution
      # Model parameters take precedence over caller bindings if there's a conflict
      extended_binding =
        case model_params do
          %{} = params_map when map_size(params_map) > 0 ->
            # Convert map to keyword list format for Code.eval_quoted
            Enum.reduce(params_map, caller_binding, fn {key, value}, acc ->
              Keyword.put(acc, key, value)
            end)

          _ ->
            caller_binding
        end

      # Process the block expressions left-to-right, threading the problem
      unquote(__MODULE__).__define_with_env__(unquote(Macro.escape(exprs)), extended_binding)
    end
  end

  @doc """
  Modify an existing problem by applying additional DSL statements inside a block.

  Supports inside the block (same as in define, but without `new/1`):
  - `variables(name, generators, type, opts_or_desc)` – adds variables
  - `constraints(generators, expr, desc \\ nil)` – adds constraints
  - `objective(expr, opts)` – sets or updates objective

  Additionally, rewrites nested `sum(...)` calls to `Dantzig.Problem.DSL.sum/1`
  so they expand correctly without requiring explicit imports in user code.
  """
  defmacro modify(problem, do: block) do
    rewritten_block =
      Macro.prewalk(block, fn
        {:sum, meta, args} ->
          {{:., meta, [Dantzig.Problem.DSL, :sum]}, meta, args}

        {:objective, meta, [objective_expr, opts]} ->
          {:objective, meta, [objective_expr, opts]}

        {:objective, meta, [objective_expr]} ->
          {:objective, meta, [objective_expr, []]}

        list when is_list(list) ->
          case list do
            [{:<-, _, [var, list_expr]}] ->
              [{:<-, [], [quote(do: unquote(var)), list_expr]}]

            _ ->
              list
          end

        other ->
          other
      end)

    exprs =
      case rewritten_block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    quote do
      # Ensure macros expand for both fully-qualified and aliased usage
      require Dantzig.Problem.DSL
      require Dantzig.Problem.DSL, as: DSL
      import Dantzig.Problem.DSL, only: [objective: 1, objective: 2]

      unquote(__MODULE__).__modify_with_env__(
        unquote(problem),
        unquote(Macro.escape(exprs)),
        binding()
      )
    end
  end

  # Helper used by the imperative API macros to process with environment
  def __add_variables_with_env__(problem, generators, var_name, var_type, description, env) do
    # Set the environment for variable resolution
    Process.put(:dantzig_eval_env, env)

    try do
      Dantzig.Problem.DSL.__add_variables__(problem, generators, var_name, var_type, description)
    after
      Process.delete(:dantzig_eval_env)
    end
  end

  def __set_objective_with_env__(problem, objective_expr, opts, env) do
    # Set the environment for variable resolution
    Process.put(:dantzig_eval_env, env)

    try do
      Dantzig.Problem.DSL.__set_objective__(problem, objective_expr, opts)
    after
      Process.delete(:dantzig_eval_env)
    end
  end

  # Helper used by the macro to reduce the block at compile-time into runtime calls
  def __define_reduce__(exprs) when is_list(exprs) do
    DSLReducer.__define_reduce__(exprs)
  end

  # Internal helper to run reduce with caller's runtime bindings available
  def __define_with_env__(exprs, env) when is_list(exprs) and is_list(env) do
    previous = Process.get(:dantzig_eval_env)
    Process.put(:dantzig_eval_env, env)

    try do
      __define_reduce__(exprs)
    after
      if previous do
        Process.put(:dantzig_eval_env, previous)
      else
        Process.delete(:dantzig_eval_env)
      end
    end
  end

  # Internal helper to run modify with caller's runtime bindings available
  def __modify_with_env__(%__MODULE__{} = problem, exprs, env)
      when is_list(exprs) and is_list(env) do
    previous = Process.get(:dantzig_eval_env)
    Process.put(:dantzig_eval_env, env)

    try do
      __modify_reduce__(problem, exprs)
    after
      if previous do
        Process.put(:dantzig_eval_env, previous)
      else
        Process.delete(:dantzig_eval_env)
      end
    end
  end

  # Reduce over modify expressions reusing same handlers as define (minus new/1)
  def __modify_reduce__(%__MODULE__{} = initial_problem, exprs) when is_list(exprs) do
    DSLReducer.__modify_reduce__(initial_problem, exprs)
  end

  # New DSL Functions (JuMP-like API)

  @doc """
  Create variables with JuMP-like syntax.

  ## Examples

      # Single variable
      problem = Problem.variable(problem, "x", :continuous, min_bound: 0, max_bound: 10)

      # Multiple variables with generators
      problem = Problem.variables(problem, "x", [i <- 1..4, j <- 1..4], :binary, "Queen position")
  """
  @spec variables(t(), String.t(), list(), atom(), keyword()) :: t()
  def variables(problem, var_name, generators, var_type, opts \\ []) do
    # Use the existing DSL implementation - pass entire opts for bounds handling
    Dantzig.Problem.DSL.__add_variables__(
      problem,
      generators,
      var_name,
      var_type,
      opts
    )
  end

  @doc """
  Create a single variable with JuMP-like syntax.

  ## Examples

      problem = Problem.variable(problem, "x", :continuous, min_bound: 0, max_bound: 10)
  """
  @spec variable(t(), String.t(), atom(), keyword()) :: {t(), Polynomial.t()}
  def variable(problem, var_name, var_type, opts \\ []) do
    min_bound = Keyword.get(opts, :min_bound)
    max_bound = Keyword.get(opts, :max_bound)
    _description = Keyword.get(opts, :description)

    new_variable(problem, var_name, type: var_type, min_bound: min_bound, max_bound: max_bound)
  end

  # Public: Add constraints with JuMP-like syntax.
  # Used by both the define/modify reducers and publicly in tests.
  @spec constraints(t(), list(), any(), String.t() | nil) :: t()
  def constraints(problem, generators, constraint_expr, description \\ nil) do
    # Use the working constraint manager implementation
    Dantzig.Problem.DSL.ConstraintManager.add_constraints(
      problem,
      generators,
      constraint_expr,
      description
    )
  end

  @doc """
  Add a single constraint with JuMP-like syntax.

  ## Examples

      problem = Problem.constraint(problem, x <= 10, "Variable bound")
  """
  @spec constraint(t(), any(), String.t() | nil) :: t()
  def constraint(problem, constraint_expr, description \\ nil) do
    # Transform the constraint expression AST
    transformed = transform_constraint_expression_to_ast(constraint_expr)

    # Parse the simple constraint expression (no generators)
    constraint = parse_simple_constraint_expression(problem, transformed, description)

    # Add the constraint to the problem
    add_constraint(problem, constraint)
  end

  @doc """
  Set objective with JuMP-like syntax.

  ## Examples

      problem = Problem.objective(problem, x + 2*y, direction: :maximize)
  """
  @spec objective(t(), any(), keyword()) :: t()
  def objective(problem, objective_expr, opts \\ []) do
    # Use the existing DSL implementation
    Dantzig.Problem.DSL.__set_objective__(
      problem,
      objective_expr,
      opts
    )
  end

  # Private functions

  defp generate_constraint_id(counter) do
    "c#{String.pad_leading(to_string(counter), 8, "0")}"
  end

  # Parse simple constraint expressions (no generators)
  defp parse_simple_constraint_expression(problem, constraint_expr, description) do
    # Check if this is a complex expression (sum, for, Access.get) that needs the full parser
    if is_complex_expression?(constraint_expr) do
      # Use the full expression parser with empty bindings (for expressions create their own bindings)
      parse_constraint_with_full_parser(problem, constraint_expr, description, %{})
    else
      # Use simple parser for basic expressions
      case constraint_expr do
        {:==, _, [left_expr, right_value]} ->
          left_poly = parse_simple_expression_to_polynomial(problem, left_expr)

          right_poly =
            case right_value do
              val when is_number(val) -> Polynomial.const(val)
              _ -> parse_simple_expression_to_polynomial(problem, right_value)
            end

          c = Constraint.new_linear(left_poly, :==, right_poly, name: description)
          if is_binary(description), do: %{c | description: description}, else: c

        {:<=, _, [left_expr, right_value]} ->
          left_poly = parse_simple_expression_to_polynomial(problem, left_expr)

          right_poly =
            case right_value do
              val when is_number(val) -> Polynomial.const(val)
              _ -> parse_simple_expression_to_polynomial(problem, right_value)
            end

          c = Constraint.new_linear(left_poly, :<=, right_poly, name: description)
          if is_binary(description), do: %{c | description: description}, else: c

        {:>=, _, [left_expr, right_value]} ->
          left_poly = parse_simple_expression_to_polynomial(problem, left_expr)

          right_poly =
            case right_value do
              val when is_number(val) -> Polynomial.const(val)
              _ -> parse_simple_expression_to_polynomial(problem, right_value)
            end

          c = Constraint.new_linear(left_poly, :>=, right_poly, name: description)
          if is_binary(description), do: %{c | description: description}, else: c

        _ ->
          raise ArgumentError,
                """
                Unsupported constraint expression: #{inspect(constraint_expr)}

                Constraint expressions must be comparison operations (==, <=, >=) between:
                - Variables (e.g., x(i))
                - Polynomial expressions (e.g., x(i) + y(j))
                - Constants (e.g., 10, cost[i])

                Valid constraint formats:
                  1. Variable comparison: x(i) <= 10
                  2. Expression comparison: x(i) + y(j) <= capacity[i]
                  3. Sum comparison: sum(x(:_)) <= total

                Examples:
                  constraints([i <- 1..n], x(i) <= 10, "Upper bound")
                  constraints([i <- 1..n], x(i) + y(i) <= capacity[i], "Capacity constraint")
                  constraints(sum(x(:_)) <= 100, "Total constraint")

                Got: #{inspect(constraint_expr)}
                """
      end
    end
  end

  # Check if expression contains complex constructs (sum, for, Access.get)
  defp is_complex_expression?(expr) do
    check_for_complex(expr, false)
  end

  defp check_for_complex(expr, _found) when is_atom(expr) or is_number(expr) or is_binary(expr),
    do: false

  defp check_for_complex({:sum, _, _}, _found), do: true
  defp check_for_complex({{:., _, [_, :sum]}, _, _}, _found), do: true
  defp check_for_complex({:sum, {:for, _, _}}, _found), do: true
  defp check_for_complex({:for, _, _}, _found), do: true
  defp check_for_complex({{:., _, [Access, :get]}, _, _}, _found), do: true

  defp check_for_complex({op, _, args}, found) when is_atom(op) and is_list(args) do
    Enum.reduce(args, found, fn arg, acc ->
      acc or check_for_complex(arg, acc)
    end)
  end

  defp check_for_complex(tuple, found) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(found, fn elem, acc ->
      acc or check_for_complex(elem, acc)
    end)
  end

  defp check_for_complex(list, found) when is_list(list) do
    Enum.reduce(list, found, fn elem, acc ->
      acc or check_for_complex(elem, acc)
    end)
  end

  defp check_for_complex(_, _found), do: false

  # Parse constraint using the full expression parser (handles sum, for, Access.get)
  defp parse_constraint_with_full_parser(problem, constraint_expr, description, bindings) do
    case constraint_expr do
      {:==, _, [left_expr, right_value]} ->
        left_poly =
          Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
            left_expr,
            bindings,
            problem
          )

        right_poly =
          case right_value do
            val when is_number(val) ->
              Polynomial.const(val)

            _ ->
              Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
                right_value,
                bindings,
                problem
              )
          end

        c = Constraint.new_linear(left_poly, :==, right_poly, name: description)
        if is_binary(description), do: %{c | description: description}, else: c

      {:<=, _, [left_expr, right_value]} ->
        left_poly =
          Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
            left_expr,
            bindings,
            problem
          )

        right_poly =
          case right_value do
            val when is_number(val) ->
              Polynomial.const(val)

            _ ->
              Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
                right_value,
                bindings,
                problem
              )
          end

        c = Constraint.new_linear(left_poly, :<=, right_poly, name: description)
        if is_binary(description), do: %{c | description: description}, else: c

      {:>=, _, [left_expr, right_value]} ->
        left_poly =
          Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
            left_expr,
            bindings,
            problem
          )

        right_poly =
          case right_value do
            val when is_number(val) ->
              Polynomial.const(val)

            _ ->
              Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
                right_value,
                bindings,
                problem
              )
          end

        c = Constraint.new_linear(left_poly, :>=, right_poly, name: description)
        if is_binary(description), do: %{c | description: description}, else: c

      _ ->
        raise ArgumentError,
              "Unsupported constraint expression: #{inspect(constraint_expr)}"
    end
  end

  # Parse simple expressions to polynomials (with problem context for variable lookup)
  defp parse_simple_expression_to_polynomial(problem, expr),
    do: Dantzig.Problem.AST.parse_simple_expression_to_polynomial(expr, problem)
end
