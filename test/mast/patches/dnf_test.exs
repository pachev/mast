defmodule Mast.Patches.DnfTest do
  use ExUnit.Case, async: true

  alias Mast.Patches.Dnf

  describe "parse/1" do
    test "returns empty list for empty output" do
      assert %{total: 0, updates: []} = Dnf.parse("")
    end

    test "returns empty list when only whitespace" do
      assert %{total: 0, updates: []} = Dnf.parse("\n\n  \n")
    end

    test "parses a single upgradable line" do
      out = """
      openssl.x86_64    1:3.0.8-1.amzn2023.0.7    amazonlinux
      """

      assert %{total: 1, updates: [u]} = Dnf.parse(out)
      assert u.package == "openssl"
      assert u.architecture == "x86_64"
      assert u.new_version == "1:3.0.8-1.amzn2023.0.7"
      assert u.repository == "amazonlinux"
    end

    test "parses multiple lines" do
      out = """
      openssl.x86_64    1:3.0.8-1.amzn2023.0.7    amazonlinux
      curl.x86_64       8.5.0-1.amzn2023          amazonlinux
      kernel.x86_64     6.1.79-99.167.amzn2023    amazonlinux
      """

      assert %{total: 3, updates: updates} = Dnf.parse(out)
      assert Enum.map(updates, & &1.package) == ["openssl", "curl", "kernel"]
    end

    test "ignores the Obsoleting Packages section" do
      # `dnf check-update` appends an `Obsoleting Packages` block after a
      # blank line. Those lines describe replacements, not upgrades, and
      # share the same shape — but the section header and the indented
      # `replacing ...` lines must not be counted as upgrades.
      out = """
      openssl.x86_64    1:3.0.8-1.amzn2023.0.7    amazonlinux

      Obsoleting Packages
      newpkg.x86_64     2.0.0-1.amzn2023          amazonlinux
          oldpkg.x86_64   1.0.0-1.amzn2023          @amazonlinux
      """

      assert %{total: 1, updates: [u]} = Dnf.parse(out)
      assert u.package == "openssl"
    end

    test "ignores 'Last metadata expiration' header" do
      out = """
      Last metadata expiration check: 0:12:34 ago on Mon 18 May 2026.

      openssl.x86_64    1:3.0.8-1.amzn2023.0.7    amazonlinux
      """

      assert %{total: 1, updates: [u]} = Dnf.parse(out)
      assert u.package == "openssl"
    end

    test "tolerates a wrapped second line for long package descriptors" do
      # Some dnf versions wrap when the package column is wide; the version
      # and repo land on the next line, indented. We only count lines that
      # carry the full triple — wrapped continuations are skipped rather
      # than producing a malformed entry.
      out = """
      really-long-package-name-that-wraps.x86_64
                       1.2.3-4.amzn2023          amazonlinux
      curl.x86_64      8.5.0-1.amzn2023          amazonlinux
      """

      assert %{total: 1, updates: [u]} = Dnf.parse(out)
      assert u.package == "curl"
    end
  end
end
