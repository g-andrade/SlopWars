defmodule Backend.ASBTest do
  use ExUnit.Case

  test "dev mode analyze_both returns two valid builds" do
    {:ok, build1, build2} = Backend.ASB.analyze_both("No prisoners!", "Happy days!")

    for build <- [build1, build2] do
      assert build["tone"] in ["aggressive", "balanced", "defensive"]
      assert build["bomb_damage"] in 1..10
      assert build["tower_hp"] in 100..500
      assert build["shield_hp"] in 1..3
      assert is_binary(build["bomb_description"])
      assert is_binary(build["tower_description"])
      assert is_binary(build["shield_description"])
    end
  end
end
