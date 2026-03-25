#!/usr/bin/env elixir

# Linear Programming Example 1986 UG Exam
# ========================================
#
# Source: OR-Notes by J.E. Beasley
# URL: https://people.brunel.ac.uk/~mastjjb/jeb/or/morelp.html
#
# Problem Description:
# A carpenter makes tables and chairs with profit maximization.
#
# Profits: £30 per table, £10 per chair
# Time: 6 hours per table, 3 hours per chair, max 40 hours/week
# Demand: at least 3 times as many chairs as tables
# Storage: tables take 4 times space of chairs, max 4 tables
#
# Solution (from source):
# Optimal at intersection of storage and time constraints
# xT = 4/3 ≈ 1.333 tables, xC = 10.667 chairs
# Profit = £146.667

require Dantzig.Problem, as: Problem

alias Dantzig.{Polynomial, Solution}
require Dantzig.Constraint, as: Constraint

IO.puts("=== Linear Programming Example 1986 UG Exam ===")
IO.puts("Source: OR-Notes by J.E. Beasley")
IO.puts("Carpenter production planning")
IO.puts("")

# Problem data
profit_table = 30
profit_chair = 10

# hours per table
time_table = 6
# hours per chair
time_chair = 3

max_hours = 40

# Demand constraint: chairs >= 3 * tables
demand_ratio = 3

# Storage constraint: table space = 4 * chair space, max 4 tables
max_tables = 4

IO.puts("Production Data:")
IO.puts("  Table: £#{profit_table} profit, #{time_table} hours, #{4} chair-space units")
IO.puts("  Chair: £#{profit_chair} profit, #{time_chair} hours, #{1} chair-space units")
IO.puts("  Total time available: #{max_hours} hours")
IO.puts("  Demand: at least #{demand_ratio} chairs per table")
IO.puts("  Storage: maximum #{max_tables} tables worth of space")
IO.puts("")

# Create the optimization problem using the imperative API
# (avoids DSL macro limitations with outer variable references in bounds/descriptions)
problem = Problem.new(direction: :maximize, name: "1986 UG Exam - Carpenter Production")

{problem, xT} = Problem.new_variable(problem, "xT", type: :integer, min_bound: 0, max_bound: max_tables)
{problem, xC} = Problem.new_variable(problem, "xC", type: :integer, min_bound: 0)

# Objective: maximise profit
problem =
  problem
  |> Problem.increment_objective(Polynomial.multiply(xT, profit_table))
  |> Problem.increment_objective(Polynomial.multiply(xC, profit_chair))

# Time constraint: 6xT + 3xC <= 40
time_poly = Polynomial.add(Polynomial.multiply(xT, time_table), Polynomial.multiply(xC, time_chair))
problem = Problem.add_constraint(problem, Constraint.new_linear(time_poly <= max_hours,
  name: "total_working_hours"))

# Demand constraint: xC >= 3*xT
demand_poly = Polynomial.subtract(xC, Polynomial.multiply(xT, demand_ratio))
problem = Problem.add_constraint(problem, Constraint.new_linear(demand_poly >= 0,
  name: "demand_ratio"))

# Storage constraint: xT + 0.25*xC <= 4
storage_poly = Polynomial.add(xT, Polynomial.multiply(xC, 0.25))
problem = Problem.add_constraint(problem, Constraint.new_linear(storage_poly <= 4,
  name: "storage_space"))

# Solve the problem
{:ok, solution} = Dantzig.solve(problem)
objective_value = solution.objective

IO.puts("Solution:")
IO.puts("========")
IO.puts("Profit: £#{Float.round(objective_value, 3)}")
IO.puts("")

IO.puts("Production Plan:")

solution.variables
|> Enum.sort_by(fn {k, _} -> k end)
|> Enum.each(fn {var_name, value} ->
  IO.puts("  #{var_name}: #{Float.round(value, 3)} units")
end)

IO.puts("")
IO.puts("=== SOLUTION ANALYSIS (from OR-Notes) ===")
IO.puts("")
IO.puts("Mathematical Formulation:")
IO.puts("Variables: xT (tables), xC (chairs) ≥ 0")
IO.puts("Constraints:")
IO.puts("  6xT + 3xC ≤ 40        (work time)")
IO.puts("  xC ≥ 3xT              (demand: 3 chairs per table)")
IO.puts("  xT + 0.25xC ≤ 4       (storage: 4 table-units)")
IO.puts("")
IO.puts("Objective: maximize 30xT + 10xC")
IO.puts("")
IO.puts("Storage constraint derivation:")
IO.puts("  Tables take 4 units, chairs take 1 unit")
IO.puts("  Total storage: 4 table-units maximum")
IO.puts("  xT×4 + xC×1 ≤ 16  (4 tables × 4 units each)")
IO.puts("  4xT + xC ≤ 16")
IO.puts("  xT + 0.25xC ≤ 4")
IO.puts("")
IO.puts("Graphical Solution:")
IO.puts("  Feasible region bounded by:")
IO.puts("  - 6xT + 3xC ≤ 40")
IO.puts("  - xC ≥ 3xT  (above line xC = 3xT)")
IO.puts("  - xT + 0.25xC ≤ 4")
IO.puts("  - xT ≥ 0, xC ≥ 0")
IO.puts("")
IO.puts("  Optimal solution at intersection of:")
IO.puts("  - 6xT + 3xC = 40  (work time binding)")
IO.puts("  - xT + 0.25xC = 4  (storage binding)")
IO.puts("")
IO.puts("  Solving the system:")
IO.puts("  6xT + 3xC = 40   (1)")
IO.puts("  xT + 0.25xC = 4  (2)")
IO.puts("")
IO.puts("  From (2): xT = 4 - 0.25xC")
IO.puts("  Substitute into (1): 6(4 - 0.25xC) + 3xC = 40")
IO.puts("  24 - 1.5xC + 3xC = 40")
IO.puts("  24 + 1.5xC = 40")
IO.puts("  1.5xC = 16")
IO.puts("  xC = 16/1.5 ≈ 10.667")
IO.puts("  xT = 4 - 0.25×10.667 ≈ 4 - 2.667 ≈ 1.333")
IO.puts("")
IO.puts("  Objective = 30×1.333 + 10×10.667 ≈ 40 + 106.67 ≈ 146.67")

IO.puts("")
IO.puts("Optimal Solution:")
IO.puts("  xT = 4/3 ≈ 1.333 tables")
IO.puts("  xC = 32/3 ≈ 10.667 chairs")
IO.puts("  Profit = £146.667")

IO.puts("")
IO.puts("✓ Problem solved successfully!")
