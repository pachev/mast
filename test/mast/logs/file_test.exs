defmodule Mast.Logs.FileTest do
  use ExUnit.Case, async: true

  alias Mast.Logs.File, as: LogFile

  describe "validate_target/1" do
    test "accepts a simple absolute path" do
      assert :ok = LogFile.validate_target("/var/log/myapp/app.log")
    end

    test "rejects relative paths" do
      assert {:error, _} = LogFile.validate_target("var/log/app.log")
      assert {:error, _} = LogFile.validate_target("./app.log")
    end

    test "rejects parent traversal" do
      assert {:error, _} = LogFile.validate_target("/var/log/../../etc/passwd")
    end

    test "rejects globs" do
      assert {:error, _} = LogFile.validate_target("/var/log/*.log")
      assert {:error, _} = LogFile.validate_target("/var/log/app[1].log")
    end

    test "rejects shell metacharacters" do
      for bad <- [
            "/var/log/a;b",
            "/var/log/a|b",
            "/var/log/a&b",
            "/var/log/$x",
            "/var/log/`x`",
            "/var/log/a\nb",
            "/var/log/a b"
          ] do
        assert {:error, _} = LogFile.validate_target(bad), "expected #{inspect(bad)} to fail"
      end
    end

    test "rejects non-binary" do
      assert {:error, _} = LogFile.validate_target(nil)
    end
  end

  describe "stream_command/1" do
    test "wraps in sudo -n tail -F with last 200 lines" do
      assert LogFile.stream_command("/var/log/myapp/app.log") ==
               "sudo -n tail -n 200 -F /var/log/myapp/app.log"
    end
  end
end
