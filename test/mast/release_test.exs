defmodule Mast.ReleaseTest do
  use ExUnit.Case, async: true

  describe "module surface" do
    test "exports the functions a release operator needs" do
      exports = Mast.Release.__info__(:functions)

      assert {:migrate, 0} in exports
      assert {:rollback, 2} in exports
      assert {:migrations, 0} in exports
      assert {:seed, 0} in exports
    end
  end
end
