defmodule Dantzig.Problem.DSL.ExpressionParser.WildcardExpansion do
  @moduledoc """
  Wildcard expansion for nested map access in DSL expressions.

  Supports concise wildcard syntax like:
    sum(qty(:_) * foods[:_][nutrient])
  Instead of verbose for comprehensions:
    sum(for food <- food_names, do: qty(food) * foods[food][nutrient])
  """

  require Dantzig.Problem, as: Problem
  require Dantzig.Polynomial, as: Polynomial

  # Detect if :_ appears anywhere in the AST
  def contains_wildcard?(expr) do
    {_, found?} =
      Macro.traverse(
        expr,
        false,
        fn node, acc -> {node, acc or node == :_} end,
        fn node, acc -> {node, acc} end
      )

    found?
  end

  # Expand sum(...) when the body contains :_
  def expand_wildcard_sum(expr, bindings, problem) do
    domain = resolve_wildcard_domain(expr, bindings, problem)

    Enum.reduce(domain, Polynomial.const(0), fn value, acc ->
      inst_expr = replace_wildcards(expr, value)
      # Use the parent module to avoid circular dependency
      term_poly =
        Dantzig.Problem.DSL.ExpressionParser.parse_expression_to_polynomial(
          inst_expr,
          bindings,
          problem
        )

      Polynomial.add(acc, term_poly)
    end)
  end

  # Infer the wildcard domain from:
  # - variables with :_ in their indices (e.g., qty(:_))
  # - Access.get with :_ (e.g., foods[:_])
  # If multiple sources are found, intersect them.
  defp resolve_wildcard_domain(expr, bindings, problem) do
    var_sets = collect_var_domains_for_wildcard(expr, problem, bindings)
    acc_sets = collect_access_domains_for_wildcard(expr, bindings, problem)
    sets = var_sets ++ acc_sets

    case sets do
      [] ->
        raise ArgumentError,
              "Wildcard :_ used in sum/1, but no domain could be inferred. " <>
                "Use a declared indexed variable or a constant map like foods[:_]."

      [single] ->
        MapSet.to_list(single)

      _ ->
        inter = Enum.reduce(sets, hd(sets), &MapSet.intersection/2)

        if MapSet.size(inter) == 0 do
          raise ArgumentError,
                "Inferred wildcard domains do not overlap (empty intersection). " <>
                  "Ensure variable indices and constant keys align."
        end

        MapSet.to_list(inter)
    end
  end

  # For variable accesses like qty(:_), x(:_, j), x[i][:_] — infer value set from variable map keys.
  # Handles both parenthesis form {var_name, _, indices} and chained bracket form x[i][:_].
  defp collect_var_domains_for_wildcard(expr, problem, bindings \\ %{}) do
    # List of operators to exclude from variable matching
    operators = [:+, :-, :*, :/, :==, :<=, :>=, :<, :>, :., :{}, :|>, :&, :and, :or, :not]

    {_, sets} =
      Macro.traverse(
        expr,
        [],
        fn
          # Parenthesis form: x(i, :_)
          {var_name, _, indices} = node, acc when is_list(indices) and is_atom(var_name) ->
            if var_name not in operators and Enum.any?(indices, &(&1 == :_)) do
              var_map = Problem.get_variables_nd(problem, to_string(var_name)) || %{}

              # Use the first wildcard position for domain
              pos =
                indices
                |> Enum.with_index()
                |> Enum.find_value(fn
                  {:_, i} -> i
                  _ -> nil
                end)

              values =
                for {key_tuple, _mono} <- var_map do
                  # var_map keys are tuples even for 1-D
                  elem(key_tuple, pos)
                end

              {node, [MapSet.new(values) | acc]}
            else
              {node, acc}
            end

          # Bracket form: x[i][:_] — chained Access.get with :_ as the outermost key
          {{:., _, [Access, :get]}, _, [_container_ast, :_]} = node, acc ->
            case unwrap_access_get_chain_for_var(node, problem, bindings) do
              {_var_name_str, var_map, keys_before_wildcard, wildcard_pos} ->
                values =
                  for {key_tuple, _mono} <- var_map,
                      # All keys up to wildcard position must match
                      match_prefix?(key_tuple, keys_before_wildcard) do
                    elem(key_tuple, wildcard_pos)
                  end

                {node, [MapSet.new(values) | acc]}

              nil ->
                {node, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    sets
  end

  # For constant map access like foods[:_][nutrient] or foods[:_].cost
  # Skips Access.get chains whose base is a known variable (handled by collect_var_domains_for_wildcard).
  defp collect_access_domains_for_wildcard(expr, bindings, problem) do
    {_, sets} =
      Macro.traverse(
        expr,
        [],
        fn
          {{:., _, [Access, :get]}, _, [container_ast, key_ast]} = node, acc ->
            if key_ast == :_ do
              # Skip if the whole chain resolves to a known variable — handled by collect_var_domains_for_wildcard
              if variable_access_chain?(node, problem) do
                {node, acc}
              else
                container = eval_container(container_ast, bindings)

                domain =
                  cond do
                    is_map(container) -> Map.keys(container)
                    is_list(container) -> 0..(length(container) - 1) |> Enum.to_list()
                    true -> []
                  end

                {node, [MapSet.new(domain) | acc]}
              end
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    sets
  end


  # Returns true if the Access.get chain's base atom is a known variable in the problem.
  defp variable_access_chain?(access_expr, problem) when not is_nil(problem) do
    case unwrap_access_get_chain_for_var(access_expr, problem) do
      {_var_name, _var_map, _prefix, _pos} -> true
      nil -> false
    end
  end

  defp variable_access_chain?(_, _), do: false

  # Unwrap a chained Access.get expression to detect bracket-notation variable access with wildcards.
  # Returns {var_name_str, var_map, resolved_prefix_keys, wildcard_position} or nil.
  # E.g. x[1][:_]  → {"x", var_map, [1], 1}
  #      x[:_]     → {"x", var_map, [], 0}
  #      x[i][:_]  → {"x", var_map, [bound_i], 1}  (with bindings)
  defp unwrap_access_get_chain_for_var(access_expr, problem, bindings \\ %{}) do
    case unwrap_chain(access_expr) do
      {base_name, key_asts} when is_atom(base_name) ->
        var_name_str = to_string(base_name)
        var_map = Problem.get_variables_nd(problem, var_name_str)

        if var_map && Enum.any?(key_asts, &(&1 == :_)) do
          wildcard_pos =
            key_asts
            |> Enum.with_index()
            |> Enum.find_value(fn {k, i} -> if k == :_, do: i end)

          prefix_keys =
            key_asts
            |> Enum.take(wildcard_pos)
            |> Enum.map(fn
              {k, _, _} when is_atom(k) -> Map.get(bindings, k, k)
              k -> k
            end)

          {var_name_str, var_map, prefix_keys, wildcard_pos}
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp unwrap_chain({{:., _, [Access, :get]}, _, [container_ast, key_ast]}) do
    case container_ast do
      {{:., _, [Access, :get]}, _, _} ->
        case unwrap_chain(container_ast) do
          {base, keys} -> {base, keys ++ [key_ast]}
          nil -> nil
        end

      {atom_name, _, _} when is_atom(atom_name) ->
        {atom_name, [key_ast]}

      _ ->
        nil
    end
  end

  defp unwrap_chain(_), do: nil

  defp match_prefix?(key_tuple, prefix_keys) do
    key_list = Tuple.to_list(key_tuple)
    Enum.zip(prefix_keys, key_list) |> Enum.all?(fn {p, k} -> p == k end)
  end

  defp eval_container(container_ast, bindings) do
    case Dantzig.Problem.DSL.ExpressionParser.try_evaluate_constant(container_ast, bindings) do
      {:ok, val} -> val
      :error ->
        try do
          Dantzig.Problem.DSL.ExpressionParser.evaluate_expression_with_bindings(
            container_ast,
            bindings
          )
        rescue
          _ -> nil
        end
    end
  end

  # Replace all occurrences of :_ with the concrete value
  defp replace_wildcards(expr, value) do
    Macro.postwalk(expr, fn
      :_ -> value
      other -> other
    end)
  end
end
