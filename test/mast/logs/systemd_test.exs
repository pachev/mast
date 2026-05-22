defmodule Mast.Logs.SystemdTest do
  use ExUnit.Case, async: true

  alias Mast.Logs.Systemd

  describe "validate_target/1" do
    test "accepts a bare service name" do
      assert :ok = Systemd.validate_target("hermes")
    end

    test "accepts a .service suffix" do
      assert :ok = Systemd.validate_target("hermes.service")
    end

    test "accepts dashes, dots, underscores, @ instances" do
      for unit <- ["myapp-web", "myapp.web", "myapp_web", "ssh@.service"] do
        assert :ok = Systemd.validate_target(unit), "expected #{unit} to be valid"
      end
    end

    test "rejects empty string" do
      assert {:error, _} = Systemd.validate_target("")
    end

    test "rejects whitespace" do
      assert {:error, _} = Systemd.validate_target("bad unit")
    end

    test "rejects shell metacharacters" do
      for bad <- ["a;b", "a&b", "a|b", "$(x)", "`x`", "a\nb"] do
        assert {:error, _} = Systemd.validate_target(bad), "expected #{inspect(bad)} to fail"
      end
    end

    test "rejects non-binary" do
      assert {:error, _} = Systemd.validate_target(nil)
      assert {:error, _} = Systemd.validate_target(123)
    end
  end

  describe "stream_command/1" do
    test "wraps in sudo -n journalctl with follow + last 200 lines" do
      assert Systemd.stream_command("hermes.service") ==
               "sudo -n journalctl -u hermes.service -f -n 200 --output=cat"
    end
  end
end
