#!/usr/bin/env elixir

# Supply Chain Network Design Problem

require Dantzig.Problem, as: Problem

suppliers  = ["S_NA", "S_EU", "S_AP"]
warehouses = ["W_NA", "W_EU", "W_AP"]
retailers  = ["R_NA", "R_EU", "R_AP"]
products   = ["Electronics", "Automotive"]

# Supply capacities [supplier][product]
supply_cap = %{
  "S_NA" => %{"Electronics" => 300, "Automotive" => 200},
  "S_EU" => %{"Electronics" => 250, "Automotive" => 280},
  "S_AP" => %{"Electronics" => 350, "Automotive" => 150}
}

# Warehouse throughput capacity [warehouse][product]
wh_cap = %{
  "W_NA" => %{"Electronics" => 500, "Automotive" => 400},
  "W_EU" => %{"Electronics" => 450, "Automotive" => 380},
  "W_AP" => %{"Electronics" => 420, "Automotive" => 320}
}

# Retailer demand [retailer][product]
demand = %{
  "R_NA" => %{"Electronics" => 220, "Automotive" => 180},
  "R_EU" => %{"Electronics" => 200, "Automotive" => 160},
  "R_AP" => %{"Electronics" => 180, "Automotive" => 120}
}

# Transport cost per unit: supplier → warehouse [s][w][p] (simplified: same for all products)
trans_sw = %{
  {"S_NA", "W_NA"} => 2.0, {"S_NA", "W_EU"} => 8.0, {"S_NA", "W_AP"} => 10.0,
  {"S_EU", "W_NA"} => 8.0, {"S_EU", "W_EU"} => 2.0, {"S_EU", "W_AP"} =>  9.0,
  {"S_AP", "W_NA"} => 10.0, {"S_AP", "W_EU"} => 9.0, {"S_AP", "W_AP"} =>  2.0
}

# Transport cost per unit: warehouse → retailer [w][r][p] (simplified: same for all products)
trans_wr = %{
  {"W_NA", "R_NA"} => 1.5, {"W_NA", "R_EU"} => 7.0, {"W_NA", "R_AP"} => 9.0,
  {"W_EU", "R_NA"} => 7.0, {"W_EU", "R_EU"} => 1.5, {"W_EU", "R_AP"} => 8.0,
  {"W_AP", "R_NA"} => 9.0, {"W_AP", "R_EU"} => 8.0, {"W_AP", "R_AP"} => 1.5
}

# Production cost per unit at each supplier [s][p]
prod_cost = %{
  "S_NA" => %{"Electronics" => 10.0, "Automotive" => 15.0},
  "S_EU" => %{"Electronics" => 11.0, "Automotive" => 14.0},
  "S_AP" => %{"Electronics" =>  9.0, "Automotive" => 16.0}
}

IO.puts("=== Supply Chain Network Design ===")
IO.puts("Suppliers: #{Enum.join(suppliers, ", ")}")
IO.puts("Warehouses: #{Enum.join(warehouses, ", ")}")
IO.puts("Retailers: #{Enum.join(retailers, ", ")}")
IO.puts("Products: #{Enum.join(products, ", ")}")
IO.puts("")

# Build LP using imperative API
alias Dantzig.{Polynomial, Solution}
require Dantzig.Constraint, as: Constraint

problem = Problem.new(direction: :minimize)

# Decision variables:
# flow_sw[s,w,p] = units of product p shipped from supplier s to warehouse w
# flow_wr[w,r,p] = units of product p shipped from warehouse w to retailer r

{problem, vars_sw} =
  Enum.reduce(
    (for s <- suppliers, w <- warehouses, p <- products, do: {s, w, p}),
    {problem, %{}},
    fn {s, w, p}, {prob, vars} ->
      name = "sw_#{s}_#{w}_#{p}"
      cost = Map.get(trans_sw, {s, w}, 5.0) + prod_cost[s][p]
      {prob2, var} = Problem.new_variable(prob, name, min_bound: 0.0, max_bound: supply_cap[s][p])
      prob3 = Problem.increment_objective(prob2, Polynomial.multiply(var, cost))
      {prob3, Map.put(vars, {s, w, p}, var)}
    end
  )

{problem, vars_wr} =
  Enum.reduce(
    (for w <- warehouses, r <- retailers, p <- products, do: {w, r, p}),
    {problem, %{}},
    fn {w, r, p}, {prob, vars} ->
      name = "wr_#{w}_#{r}_#{p}"
      cost = Map.get(trans_wr, {w, r}, 5.0)
      {prob2, var} = Problem.new_variable(prob, name, min_bound: 0.0)
      prob3 = Problem.increment_objective(prob2, Polynomial.multiply(var, cost))
      {prob3, Map.put(vars, {w, r, p}, var)}
    end
  )

# Constraints: demand satisfaction at each retailer
problem =
  Enum.reduce((for r <- retailers, p <- products, do: {r, p}), problem, fn {r, p}, prob ->
    in_flow =
      Enum.reduce(warehouses, 0.0, fn w, acc ->
        Polynomial.add(acc, vars_wr[{w, r, p}])
      end)

    d = demand[r][p]
    Problem.add_constraint(prob, Constraint.new_linear(in_flow >= d, name: "demand_#{r}_#{p}"))
  end)

# Constraints: flow conservation at each warehouse (in >= out)
problem =
  Enum.reduce((for w <- warehouses, p <- products, do: {w, p}), problem, fn {w, p}, prob ->
    in_flow  = Enum.reduce(suppliers, 0.0, fn s, acc -> Polynomial.add(acc, vars_sw[{s, w, p}]) end)
    out_flow = Enum.reduce(retailers, 0.0, fn r, acc -> Polynomial.add(acc, vars_wr[{w, r, p}]) end)
    cap = wh_cap[w][p]

    prob
    |> Problem.add_constraint(Constraint.new_linear(in_flow >= out_flow, name: "balance_#{w}_#{p}"))
    |> Problem.add_constraint(Constraint.new_linear(in_flow <= cap,      name: "wh_cap_#{w}_#{p}"))
  end)

# Solve
IO.puts("Solving...")

case Dantzig.solve(problem) do
  {:ok, solution} ->
    IO.puts("Status: #{solution.model_status}")
    IO.puts("Total cost: $#{Float.round(solution.objective, 2)}")
    IO.puts("")

    IO.puts("Supplier → Warehouse flows (non-zero):")
    for s <- suppliers, w <- warehouses, p <- products do
      var_name = "sw_#{s}_#{w}_#{p}"
      val = Map.get(solution.variables, var_name, 0.0)
      if val > 0.01 do
        IO.puts("  #{s} → #{w} [#{p}]: #{Float.round(val, 1)} units")
      end
    end

    IO.puts("")
    IO.puts("Warehouse → Retailer flows (non-zero):")
    for w <- warehouses, r <- retailers, p <- products do
      var_name = "wr_#{w}_#{r}_#{p}"
      val = Map.get(solution.variables, var_name, 0.0)
      if val > 0.01 do
        IO.puts("  #{w} → #{r} [#{p}]: #{Float.round(val, 1)} units")
      end
    end

  {:error, reason} ->
    IO.puts("Solver error: #{inspect(reason)}")
end
