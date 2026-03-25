defmodule Dantzig.Problem.DSL.ExpressionParser do
  @moduledoc """
  Parses and evaluates expressions for the Dantzig DSL.

  The `ExpressionParser` module is responsible for converting Elixir AST expressions
  into `Dantzig.Polynomial` structures. It handles constant evaluation, binding
  propagation, and complex expression normalization.

  ## Key Responsibilities

  - **Polynomial expression parsing**: Converts AST to polynomial structures
  - **Constant evaluation**: Evaluates constants from model parameters
  - **Binding propagation**: Makes generator variables available during evaluation
  - **Sum expression processing**: Handles `sum()` expressions with wildcards
  - **Complex expression normalization**: Normalizes arithmetic and comparison operations

  ## Evaluation Environment

  The parser uses a process dictionary-based evaluation environment:

  - **`:dantzig_eval_env`**: Stores model parameters and bindings
  - Set automatically during DSL block evaluation
  - Contains `:model_parameters` and `:bindings` keys

  ## Constant Access

  Constants are accessed from model parameters via:

  - `try_evaluate_constant/2`: Evaluates constant expressions
  - `evaluate_expression_with_bindings/2`: Evaluates expressions with bindings
  - Supports nested map access: `map[key1][key2]`
  - Automatic string/atom key conversion

  ## Binding Propagation

  Generator variables create bindings that are available during expression evaluation:

      variables("x", [i <- 1..n], :continuous)
      constraints([i <- 1..n], x(i) <= limit[i], "Bound")

  The binding `i` is available in the constraint expression.

  ## See Also

  - `Dantzig.Problem.DSL.ConstraintManager` - Constraint parsing
  - `Dantzig.Problem.DSL.VariableManager` - Variable creation
  - `Dantzig.Problem.define/1` - DSL entry point
  """

  require Dantzig.Problem, as: Problem
  require Dantzig.Polynomial, as: Polynomial

  alias Dantzig.Problem.DSL.ExpressionParser.ConstantEvaluation
  alias Dantzig.Problem.DSL.ExpressionParser.SumProcessing
  alias Dantzig.Problem.DSL.ExpressionParser.WildcardExpansion

  def parse_expression_to_polynomial(expr, bindings, problem) do
    # Normalize sum AST first - this converts sum(for ...) to {:for, ...}
    # and sum(expr) to expr
    normalized_expr = SumProcessing.normalize_sum_ast(expr)

    # Check if normalization produced a for-comprehension (from sum(for ...))
    case normalized_expr do
      {:for, _, _} = for_expr ->
        # This was sum(for ...), process the for-comprehension
        SumProcessing.parse_sum_expression(for_expr, bindings, problem)

      _ ->
        # Continue with normal polynomial ops normalization
        expr = normalize_polynomial_ops(normalized_expr)

        # Check for wildcards BEFORE processing - if expression contains wildcards,
        # it should be handled by sum processing, not regular parsing
        if WildcardExpansion.contains_wildcard?(expr) do
          # This expression contains wildcards, so it should be inside a sum()
          # But if we're here, it means the sum() was already normalized away
          # So we need to handle it as a wildcard sum expression
          SumProcessing.parse_sum_expression(expr, bindings, problem)
        else
          case expr do
            {:sum, [], [sum_expr]} ->
              SumProcessing.parse_sum_expression(sum_expr, bindings, problem)

            {:sum, sum_expr} ->
              SumProcessing.parse_sum_expression(sum_expr, bindings, problem)

            # Unary minus (must come before binary arithmetic)
            {:-, _meta, [v]} ->
              # Check if this is a variable access pattern (e.g., qty(food))
              case v do
                {var_name, _, indices} when is_atom(var_name) and is_list(indices) ->
                  # This is a variable access pattern, parse it directly
                  case parse_expression_to_polynomial(v, bindings, problem) do
                    %Polynomial{} = p ->
                      Polynomial.scale(p, -1)

                    other ->
                      raise ArgumentError,
                            "Unsupported unary minus on variable access: #{inspect(other)}"
                  end

                _ ->
                  # Try to evaluate as a number first
                  case ConstantEvaluation.evaluate_expression_with_bindings(v, bindings) do
                    val when is_number(val) ->
                      Polynomial.const(-val)

                    _ ->
                      case parse_expression_to_polynomial(v, bindings, problem) do
                        %Polynomial{} = p -> Polynomial.scale(p, -1)
                        other -> raise ArgumentError, "Unsupported unary minus: #{inspect(other)}"
                      end
                  end
              end

            # Arithmetic between expressions
            {op, _, [left, right]} when op in [:+, :-, :*, :/] ->
              left_poly_or_val =
                # First check if left side is a constant access expression (e.g., multiplier[i])
                # This must be checked BEFORE trying to parse as polynomial
                cond do
                  # Check if it's an Access.get pattern (constant access)
                  match?({{:., _, [Access, :get]}, _, _}, left) ->
                    # Try to evaluate as constant first
                    case ConstantEvaluation.try_evaluate_constant(left, bindings) do
                      {:ok, val} when is_number(val) ->
                        Polynomial.const(val)

                      _ ->
                        # Not a constant, try parsing as polynomial
                        case parse_expression_to_polynomial(left, bindings, problem) do
                          %Polynomial{} = p -> p
                          _ -> Polynomial.const(0)
                        end
                    end

                  true ->
                    # Not an Access.get pattern, try parsing as polynomial first
                    case parse_expression_to_polynomial(left, bindings, problem) do
                      %Polynomial{} = p ->
                        p

                      _ ->
                        case ConstantEvaluation.evaluate_expression_with_bindings(left, bindings) do
                          v when is_number(v) ->
                            Polynomial.const(v)

                          nil ->
                            Polynomial.const(0)

                          other ->
                            raise ArgumentError,
                                  """
                                  Cannot use non-numeric value in arithmetic expression: #{inspect(other)}

                                  Arithmetic operations (+, -, *, /) require numeric values or polynomials.
                                  Got: #{inspect(other)}

                                  Common causes:
                                  1. Using a string or atom where a number is expected
                                  2. Accessing an undefined variable or constant
                                  3. Using a generator variable outside its scope

                                  Example of correct usage:
                                    x(i) + y(j)        # Adding variables
                                    x(i) * 2.5         # Multiplying by a number
                                    cost[i] * x(i)     # Using constants from model_parameters
                                  """
                        end
                    end
                end

              right_poly_or_val =
                # First check if right side is a constant access expression (e.g., multiplier[i])
                # This must be checked BEFORE trying to parse as polynomial
                cond do
                  # Check if it's an Access.get pattern (constant access)
                  match?({{:., _, [Access, :get]}, _, _}, right) ->
                    # Try to evaluate as constant first
                    case ConstantEvaluation.try_evaluate_constant(right, bindings) do
                      {:ok, val} when is_number(val) ->
                        Polynomial.const(val)

                      _ ->
                        # Not a constant, try parsing as polynomial
                        case parse_expression_to_polynomial(right, bindings, problem) do
                          %Polynomial{} = p -> p
                          _ -> Polynomial.const(0)
                        end
                    end

                  true ->
                    # Not an Access.get pattern, try parsing as polynomial first
                    case parse_expression_to_polynomial(right, bindings, problem) do
                      %Polynomial{} = p ->
                        p

                      _ ->
                        case ConstantEvaluation.evaluate_expression_with_bindings(right, bindings) do
                          v when is_number(v) ->
                            Polynomial.const(v)

                          nil ->
                            Polynomial.const(0)

                          other ->
                            raise ArgumentError,
                                  "Cannot use non-numeric value in arithmetic: #{inspect(other)}"
                        end
                    end
                end

              case {op, left_poly_or_val, right_poly_or_val} do
                {:+, %Polynomial{} = p1, %Polynomial{} = p2} ->
                  Polynomial.add(p1, p2)

                {:+, %Polynomial{} = p, v} when is_number(v) ->
                  Polynomial.add(p, Polynomial.const(v))

                {:+, v, %Polynomial{} = p} when is_number(v) ->
                  Polynomial.add(Polynomial.const(v), p)

                {:-, %Polynomial{} = p1, %Polynomial{} = p2} ->
                  Polynomial.add(p1, Polynomial.scale(p2, -1))

                {:-, %Polynomial{} = p, v} when is_number(v) ->
                  # Guard ensures v is a number - convert to float then negate
                  v_float = if is_integer(v), do: :erlang.float(v), else: v
                  # Explicit float operation - type checker needs literal float
                  neg_val = -1.0 * v_float
                  Polynomial.add(p, Polynomial.const(neg_val))

                {:-, v, %Polynomial{} = p} when is_number(v) ->
                  Polynomial.add(Polynomial.const(v), Polynomial.scale(p, -1))

                {:*, %Polynomial{} = p, v} when is_number(v) ->
                  Polynomial.scale(p, v)

                {:*, v, %Polynomial{} = p} when is_number(v) ->
                  Polynomial.scale(p, v)

                {:*, %Polynomial{} = p1, %Polynomial{} = p2} ->
                  # Handle polynomial * polynomial (e.g., variable * constant polynomial)
                  # This should only happen when one is a constant polynomial
                  cond do
                    Polynomial.constant?(p1) ->
                      {_non_constant, constant_val} = Polynomial.split_constant(p1)
                      Polynomial.scale(p2, constant_val)

                    Polynomial.constant?(p2) ->
                      {_non_constant, constant_val} = Polynomial.split_constant(p2)
                      Polynomial.scale(p1, constant_val)

                    true ->
                      raise ArgumentError,
                            "Multiplication of non-constant polynomials is not supported: #{inspect({p1, p2})}"
                  end

                {:/, %Polynomial{} = p, v} when is_number(v) ->
                  # Guard ensures v is a number - convert to float explicitly
                  v_float =
                    case v do
                      n when is_integer(n) -> :erlang.float(n)
                      n when is_float(n) -> n
                    end

                  Polynomial.scale(p, 1.0 / v_float)

                {:/, %Polynomial{} = p1, %Polynomial{} = p2} ->
                  # Handle polynomial / polynomial (e.g., variable / constant polynomial)
                  # This should only happen when the second is a constant polynomial
                  if Polynomial.constant?(p2) do
                    {_non_constant, constant_val} = Polynomial.split_constant(p2)
                    Polynomial.scale(p1, 1.0 / constant_val)
                  else
                    raise ArgumentError,
                          "Division of non-constant polynomials is not supported: #{inspect({p1, p2})}"
                  end

                _ ->
                  raise ArgumentError,
                        """
                        Unsupported arithmetic operation: #{op}

                        Operation: #{op}
                        Left operand: #{inspect(left)}
                        Right operand: #{inspect(right)}

                        Supported arithmetic operations in DSL expressions:
                        - Addition (+): x(i) + y(j), x(i) + 5.0
                        - Subtraction (-): x(i) - y(j), x(i) - 5.0
                        - Multiplication (*): x(i) * 2.0, cost[i] * x(i)
                        - Division (/): x(i) / 2.0

                        Note: Division by variables is not supported in linear programming.
                        Only division by constants (numbers) is allowed.

                        Example of correct usage:
                          constraints([i <- 1..n], x(i) + y(i) <= 10)
                          constraints([i <- 1..n], cost[i] * x(i) <= budget)
                        """
              end

            # Simple variable access: {var_name, _, nil} (no indices)
            {var_name, _, nil} when is_atom(var_name) or is_binary(var_name) ->
              var_name_str =
                case var_name do
                  str when is_binary(str) -> str
                  atom when is_atom(atom) -> to_string(atom)
                  _ -> raise ArgumentError, "Invalid variable name: #{inspect(var_name)}"
                end

              # Check if this is a base variable name that has indexed variants
              var_map = Problem.get_variables_nd(problem, var_name_str)

              if var_map do
                # This is a base variable name with indexed variants (e.g., "qty" with "qty_chicken", "qty_hamburger")
                # Return the sum of all indexed variants
                Enum.reduce(var_map, Polynomial.const(0), fn {_key, poly}, acc ->
                  Polynomial.add(acc, poly)
                end)
              else
                # Check for simple variables (no indices)
                var_def = Problem.get_variable(problem, var_name_str)

                if var_def do
                  Polynomial.variable(var_name_str)
                else
                  raise ArgumentError,
                        """
                        Undefined variable: #{var_name_str}

                        To fix this:
                        1. Make sure you've defined the variable using `variables("#{var_name_str}", ...)` in your Problem.define block
                        2. Check for typos in the variable name
                        3. If using indexed variables (e.g., x(i)), ensure the indices match your generator variables

                        Example:
                          Problem.define do
                            variables("#{var_name_str}", [i <- 1..n], :continuous)
                            constraints([i <- 1..n], #{var_name_str}(i) <= 10)
                          end
                        """
                end
              end

            # Generator-based variable access: {var_name, _, indices} with indices
            {var_name, _, indices} when is_list(indices) and is_atom(var_name) ->
              resolved_indices =
                Enum.map(indices, fn
                  :_ ->
                    :_

                  {var_atom, _, _} = var_ast when is_atom(var_atom) ->
                    # Find the binding by matching the atom name, ignoring line/column info
                    # First try direct map lookup (most common case)
                    case Map.fetch(bindings, var_atom) do
                      {:ok, value} ->
                        value

                      :error ->
                        # Try finding by AST node structure (for compatibility)
                        Enum.find_value(bindings, fn {key, value} ->
                          case key do
                            {^var_atom, _, _} -> value
                            _ -> nil
                          end
                        end) || var_ast
                    end

                  var when is_atom(var) ->
                    # Try to find the binding by atom (direct map lookup first)
                    case Map.fetch(bindings, var) do
                      {:ok, value} ->
                        value

                      :error ->
                        # Try finding by AST node structure (for compatibility)
                        Enum.find_value(bindings, fn {key, value} ->
                          case key do
                            {^var, _, _} -> value
                            _ -> nil
                          end
                        end) || var
                    end

                  val ->
                    val
                end)

              var_name_str =
                case var_name do
                  str when is_binary(str) -> str
                  atom when is_atom(atom) -> to_string(atom)
                  _ -> raise ArgumentError, "Invalid variable name: #{inspect(var_name)}"
                end

              var_map = Problem.get_variables_nd(problem, var_name_str)

              cond do
                is_map(var_map) and Enum.any?(resolved_indices, &(&1 == :_)) ->
                  matching_vars =
                    Enum.filter(var_map, fn {key, _mono} ->
                      key_list = Tuple.to_list(key)

                      Enum.zip_with(resolved_indices, key_list, fn p, a ->
                        if p == :_, do: true, else: p == a
                      end)
                      |> Enum.all?()
                    end)

                  Enum.reduce(matching_vars, Polynomial.const(0), fn {_k, mono}, acc ->
                    Polynomial.add(acc, mono)
                  end)

                is_map(var_map) ->
                  key = List.to_tuple(resolved_indices)
                  Map.get(var_map, key, Polynomial.const(0))

                true ->
                  Polynomial.const(0)
              end

            val when is_number(val) ->
              Polynomial.const(val)

            # Handle bare atoms that might be variable names (when variable not in scope)
            atom when is_atom(atom) and not is_nil(problem) ->
              var_name_str = to_string(atom)
              # Check if this atom corresponds to a variable name in the problem
              var_def = Problem.get_variable(problem, var_name_str)

              if var_def do
                Polynomial.variable(var_name_str)
              else
                # Not a variable - try to evaluate as a constant from model_parameters/environment
                case ConstantEvaluation.try_evaluate_constant(expr, bindings) do
                  {:ok, val} when is_number(val) ->
                    Polynomial.const(val)

                  {:ok, _other} ->
                    raise ArgumentError,
                          """
                          Unsupported expression in constraint/objective: #{inspect(expr)}

                          The expression #{inspect(atom)} was evaluated as a constant from model_parameters,
                          but it cannot be used directly in a constraint or objective expression.

                          If #{inspect(atom)} is meant to be a variable:
                            1. Define it using `variables("#{atom}", ...)` in your Problem.define block
                            2. Use it with proper indexing: #{atom}(i) or #{atom}(i, j)

                          If #{inspect(atom)} is meant to be a constant:
                            1. Access it directly by name in expressions: #{atom}
                            2. Use it in arithmetic: cost[i] * x(i) where cost is from model_parameters

                          Example:
                            Problem.define model_parameters: %{max_val: 10} do
                              variables("x", [i <- 1..n], :continuous)
                              constraints([i <- 1..n], x(i) <= max_val)  # max_val from model_parameters
                            end
                          """

                  :error ->
                    raise ArgumentError,
                          """
                          Cannot evaluate expression: #{inspect(expr)}

                          The expression #{inspect(atom)} could not be evaluated as:
                          - A variable (not found in problem variables)
                          - A constant from model_parameters (not found in model_parameters map)

                          To fix this:
                          1. If #{inspect(atom)} should be a variable:
                             - Define it using `variables("#{atom}", ...)` before using it
                             - Check for typos in the variable name

                          2. If #{inspect(atom)} should be a constant:
                             - Add it to model_parameters: `Problem.define model_parameters: %{#{atom}: value} do`
                             - Or use a literal value instead

                          Example:
                            Problem.define model_parameters: %{n: 10} do
                              variables("x", [i <- 1..n], :continuous)
                              constraints([i <- 1..n], x(i) <= 10)
                            end
                          """
                end
              end

            # Handle variable reference AST nodes like {:queen2d_1_1, [], Elixir} (when variable not in scope)
            {var_name, _meta, _context}
            when is_atom(var_name) and
                   tuple_size(expr) == 3 and
                   var_name not in [:+, :-, :*, :/, :==, :<=, :>=, :!=, :<, :>, :., :|>, :..] ->
              var_name_str = to_string(var_name)

              # If problem is provided, check if this corresponds to a variable name
              if not is_nil(problem) do
                var_def = Problem.get_variable(problem, var_name_str)

                if var_def do
                  Polynomial.variable(var_name_str)
                else
                  # Not a variable - try to evaluate as a constant from model_parameters/environment
                  case ConstantEvaluation.try_evaluate_constant(expr, bindings) do
                    {:ok, val} when is_number(val) ->
                      Polynomial.const(val)

                    {:ok, _other} ->
                      raise ArgumentError,
                            """
                            Unsupported expression in constraint/objective: #{inspect(expr)}

                            The expression #{inspect(var_name)} was evaluated as a constant from model_parameters,
                            but it cannot be used directly in a constraint or objective expression.

                            If #{inspect(var_name)} is meant to be a variable:
                              1. Define it using `variables("#{var_name}", ...)` in your Problem.define block
                              2. Use it with proper indexing: #{var_name}(i) or #{var_name}(i, j)

                            If #{inspect(var_name)} is meant to be a constant:
                              1. Access it directly by name in expressions: #{var_name}
                              2. Use it in arithmetic: cost[i] * x(i) where cost is from model_parameters

                            Example:
                              Problem.define model_parameters: %{max_val: 10} do
                                variables("x", [i <- 1..n], :continuous)
                                constraints([i <- 1..n], x(i) <= max_val)  # max_val from model_parameters
                              end
                            """

                    :error ->
                      raise ArgumentError,
                            """
                            Cannot evaluate expression: #{inspect(expr)}

                            The expression #{inspect(var_name)} could not be evaluated as:
                            - A variable (not found in problem variables)
                            - A constant from model_parameters (not found in model_parameters map)

                            To fix this:
                            1. If #{inspect(var_name)} should be a variable:
                               - Define it using `variables("#{var_name}", ...)` before using it
                               - Check for typos in the variable name

                            2. If #{inspect(var_name)} should be a constant:
                               - Add it to model_parameters: `Problem.define model_parameters: %{#{var_name}: value} do`
                               - Or use a literal value instead

                            Example:
                              Problem.define model_parameters: %{n: 10} do
                                variables("x", [i <- 1..n], :continuous)
                                constraints([i <- 1..n], x(i) <= 10)
                              end
                            """
                  end
                end
              else
                # No problem context - treat as variable name (for backward compatibility)
                Polynomial.variable(var_name_str)
              end

            # Handle struct field access after map/list access (e.g., items_dict[item].weight)
            # Pattern: {{:., meta}, [Access.get_result, field_atom], []}
            {{:., _, [container_ast, field_atom]}, _, []} when is_atom(field_atom) ->
              # Evaluate the container (which might be an Access.get result)
              expr_with_field = {{:., [], [container_ast, field_atom]}, [], []}

              case ConstantEvaluation.try_evaluate_constant(expr_with_field, bindings) do
                {:ok, val} when is_number(val) ->
                  Polynomial.const(val)

                {:ok, :infinity} ->
                  # Allow :infinity for constraint bounds (handled by constraint manager)
                  Polynomial.const(:infinity)

                {:ok, non_numeric_val} ->
                  raise ArgumentError,
                        """
                        Constant access expression evaluated to non-numeric value: #{inspect(expr_with_field)} => #{inspect(non_numeric_val)}

                        In constraint/objective expressions, constants from model_parameters must evaluate to numbers.
                        Got: #{inspect(non_numeric_val)}

                        Common causes:
                        1. Accessing a non-numeric field from a map/struct (e.g., items_dict[item].name instead of items_dict[item].weight)
                        2. The constant in model_parameters is not a number (e.g., it's a string or list)

                        Example of correct usage:
                          # In model_parameters: %{items: [%{weight: 5.0, name: "item1"}]}
                          constraints([i <- 1..n], x(i) * items[i].weight <= 10)  # ✓ weight is numeric
                          # NOT: constraints([i <- 1..n], x(i) * items[i].name <= 10)  # ✗ name is string
                        """

                :error ->
                  raise ArgumentError,
                        """
                        Cannot evaluate constant access expression: #{inspect(expr_with_field)}

                        Ensure:
                        1. The constant exists in model_parameters
                        2. All indices are valid (within range for lists, keys exist for maps)
                        3. Generator variables used in indices are bound (e.g., i <- 1..n)

                        Example:
                          Problem.define model_parameters: %{costs: [10, 20, 30]} do
                            variables("x", [i <- 1..3], :continuous)
                            constraints([i <- 1..3], x(i) * costs[i] <= 100)  # costs[i] accesses model_parameters
                          end
                        """
              end

            # Handle Access.get AST nodes (e.g., multiplier[i], cost[worker][task], qty[p])
            # Single level: {{:., _, [Access, :get]}, _, [container_ast, key_ast]}
            # Nested: {{:., _, [Access, :get]}, _, [{{:., _, [Access, :get]}, _, [container, key1]}, key2]}
            # The key itself might also be an Access.get expression (e.g., foods_dict[food][nutrient_to_atom[limit]])
            {{:., _, [Access, :get]}, _, _} = access_expr ->
              # First check: is the base name a known variable in the problem?
              # This allows bracket notation for variable access: qty[p], assign[worker][task]
              case try_parse_access_as_variable(access_expr, bindings, problem) do
                {:ok, poly} ->
                  poly

                :not_a_variable ->
                  # Fall through to constant evaluation
                  case ConstantEvaluation.try_evaluate_constant(access_expr, bindings) do
                    {:ok, val} when is_number(val) ->
                      Polynomial.const(val)

                    {:ok, nil} ->
                      binding_info =
                        if map_size(bindings) > 0 do
                          "Available bindings: #{inspect(Map.keys(bindings))}. "
                        else
                          "No bindings available. "
                        end

                      raise ArgumentError,
                            "Cannot evaluate constant access expression: #{inspect(access_expr)}. " <>
                              "The expression evaluated to nil. " <>
                              binding_info <>
                              "Ensure the constant exists in model_parameters and indices are valid. " <>
                              "If using generator bindings (e.g., multiplier[i] where i <- 1..3), " <>
                              "ensure the binding variable is in scope."

                    {:ok, non_numeric_val} ->
                      raise ArgumentError,
                            "Constant access expression evaluated to non-numeric value: #{inspect(access_expr)} => #{inspect(non_numeric_val)}"

                    :error ->
                      binding_info =
                        if map_size(bindings) > 0 do
                          "Available bindings: #{inspect(Map.keys(bindings))}. "
                        else
                          "No bindings available. "
                        end

                      raise ArgumentError,
                            "Cannot evaluate constant access expression: #{inspect(access_expr)}. " <>
                              binding_info <>
                              "Ensure the constant exists in model_parameters and indices are valid. " <>
                              "If using generator bindings (e.g., multiplier[i] where i <- 1..3), " <>
                              "ensure the binding variable is in scope."
                  end
              end

            _ ->
              raise ArgumentError, "Unsupported expression: #{inspect(expr)}"
          end
        end
    end
  end

  # Attempt to parse a bracket access expression as a variable access.
  # Returns {:ok, polynomial} if the base name is a known variable in the problem,
  # or :not_a_variable to fall through to constant evaluation.
  # This enables unified bracket notation: qty[p] works exactly like qty(p).
  defp try_parse_access_as_variable(access_expr, bindings, problem) when not is_nil(problem) do
    case unwrap_access_get_chain(access_expr) do
      {base_name, key_asts} when is_atom(base_name) ->
        var_name_str = to_string(base_name)
        var_map = Problem.get_variables_nd(problem, var_name_str)

        if var_map do
          resolved_keys =
            Enum.map(key_asts, fn key_ast ->
              case key_ast do
                :_ ->
                  :_

                {key_name, _, _} when is_atom(key_name) ->
                  Map.get(bindings, key_name, key_name)

                key_atom when is_atom(key_atom) ->
                  Map.get(bindings, key_atom, key_atom)

                key when is_binary(key) ->
                  key

                _ ->
                  ConstantEvaluation.evaluate_expression_with_bindings(key_ast, bindings)
              end
            end)

          poly =
            if Enum.any?(resolved_keys, &(&1 == :_)) do
              var_map
              |> Enum.filter(fn {key, _} ->
                key_list = Tuple.to_list(key)

                Enum.zip_with(resolved_keys, key_list, fn p, a ->
                  if p == :_, do: true, else: p == a
                end)
                |> Enum.all?()
              end)
              |> Enum.reduce(Polynomial.const(0), fn {_k, mono}, acc ->
                Polynomial.add(acc, mono)
              end)
            else
              key_tuple = List.to_tuple(resolved_keys)
              Map.get(var_map, key_tuple, Polynomial.const(0))
            end

          {:ok, poly}
        else
          :not_a_variable
        end

      _ ->
        :not_a_variable
    end
  end

  defp try_parse_access_as_variable(_access_expr, _bindings, _problem), do: :not_a_variable

  # Unwrap a chain of Access.get calls to extract (base_atom, [key_asts]).
  # E.g. qty[p] → {:qty, [{:p, [], nil}]}
  #      assign[worker][task] → {:assign, [{:worker, [], nil}, {:task, [], nil}]}
  # Returns nil if the chain doesn't bottom out in a simple atom.
  defp unwrap_access_get_chain({{:., _, [Access, :get]}, _, [container_ast, key_ast]}) do
    case container_ast do
      {{:., _, [Access, :get]}, _, _} ->
        case unwrap_access_get_chain(container_ast) do
          {base, keys} -> {base, keys ++ [key_ast]}
          nil -> nil
        end

      {atom_name, _, _} when is_atom(atom_name) ->
        {atom_name, [key_ast]}

      _ ->
        nil
    end
  end

  defp unwrap_access_get_chain(_), do: nil

  # Normalize Dantzig.Polynomial operator calls (from Polynomial.algebra) back to Kernel ops
  defp normalize_polynomial_ops(ast) do
    Macro.prewalk(ast, fn
      {{:., meta1, [Dantzig.Polynomial, :add]}, meta2, [l, r]} ->
        {:+, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [Dantzig.Polynomial, :subtract]}, meta2, [l, r]} ->
        {:-, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [Dantzig.Polynomial, :multiply]}, meta2, [l, r]} ->
        {:*, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [Dantzig.Polynomial, :divide]}, meta2, [l, r]} ->
        {:/, merge_meta(meta1, meta2), [l, r]}

      # Handle __aliases__ form for the module
      {{:., meta1, [{:__aliases__, _, [:Dantzig, :Polynomial]}, :add]}, meta2, [l, r]} ->
        {:+, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [{:__aliases__, _, [:Dantzig, :Polynomial]}, :subtract]}, meta2, [l, r]} ->
        {:-, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [{:__aliases__, _, [:Dantzig, :Polynomial]}, :multiply]}, meta2, [l, r]} ->
        {:*, merge_meta(meta1, meta2), [l, r]}

      {{:., meta1, [{:__aliases__, _, [:Dantzig, :Polynomial]}, :divide]}, meta2, [l, r]} ->
        {:/, merge_meta(meta1, meta2), [l, r]}

      other ->
        other
    end)
  end

  defp merge_meta(m1, m2) do
    case {m1, m2} do
      {m1, m2} when is_list(m1) and is_list(m2) -> Keyword.merge(m1, m2)
      {m1, _} -> m1
    end
  end

  # Delegate to ConstantEvaluation module
  def evaluate_expression_with_bindings(expr, bindings) do
    ConstantEvaluation.evaluate_expression_with_bindings(expr, bindings)
  end

  def try_evaluate_constant(expr, bindings) do
    ConstantEvaluation.try_evaluate_constant(expr, bindings)
  end

  # Delegate to SumProcessing module
  def parse_sum_expression(expr, bindings, problem) do
    SumProcessing.parse_sum_expression(expr, bindings, problem)
  end

  def enumerate_for_bindings(generators, bindings) do
    SumProcessing.enumerate_for_bindings(generators, bindings)
  end

  def normalize_sum_ast(expr) do
    SumProcessing.normalize_sum_ast(expr)
  end

  # Expression evaluation for generators (imported from VariableManager)
  def evaluate_expression(expr),
    do: Dantzig.Problem.DSL.VariableManager.evaluate_expression(expr)
end
