defmodule Mast.Patches.AptTest do
  use ExUnit.Case, async: true

  alias Mast.Patches.Apt

  describe "parse/1" do
    test "returns empty list for empty output" do
      assert %{total: 0, updates: []} = Apt.parse("")
    end

    test "skips the Listing... Done header" do
      assert %{total: 0, updates: []} = Apt.parse("Listing... Done\n")
    end

    test "parses a single upgradable line" do
      out = """
      Listing... Done
      openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [upgradable from: 3.0.2-0ubuntu1.10]
      """

      assert %{total: 1, updates: [u]} = Apt.parse(out)
      assert u.package == "openssl"
      assert u.repository == "jammy-updates"
      assert u.new_version == "3.0.2-0ubuntu1.15"
      assert u.architecture == "amd64"
      assert u.current_version == "3.0.2-0ubuntu1.10"
    end

    test "parses multiple lines" do
      out = """
      Listing... Done
      openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [upgradable from: 3.0.2-0ubuntu1.10]
      libssl3/jammy-updates 3.0.2-0ubuntu1.15 amd64 [upgradable from: 3.0.2-0ubuntu1.10]
      curl/jammy-updates 7.81.0-1ubuntu1.16 amd64 [upgradable from: 7.81.0-1ubuntu1.15]
      """

      assert %{total: 3, updates: updates} = Apt.parse(out)
      assert Enum.map(updates, & &1.package) == ["openssl", "libssl3", "curl"]
    end

    test "ignores untranslated localised output (LANG=C wasn't set)" do
      # German apt header + bracketed German phrase — parser must not match.
      out = """
      Auflistung... Fertig
      openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [aktualisierbar von: 3.0.2-0ubuntu1.10]
      """

      assert %{total: 0, updates: []} = Apt.parse(out)
    end
  end

  describe "safe_package_name?/1" do
    test "accepts normal package names" do
      assert Apt.safe_package_name?("openssl")
      assert Apt.safe_package_name?("libssl3")
      assert Apt.safe_package_name?("python3.11-dev")
      assert Apt.safe_package_name?("g++")
      assert Apt.safe_package_name?("libc6:i386")
    end

    test "rejects shell metacharacters" do
      refute Apt.safe_package_name?("foo;rm -rf /")
      refute Apt.safe_package_name?("foo bar")
      refute Apt.safe_package_name?("foo`whoami`")
      refute Apt.safe_package_name?("foo$(id)")
      refute Apt.safe_package_name?("")
      refute Apt.safe_package_name?("foo|bar")
    end
  end
end
