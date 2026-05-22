defmodule Mast.Release do
  @moduledoc """
  Tasks that need to run from a release binary, where `mix` is not available.

  Invoke via `bin/mast eval`:

      bin/mast eval 'Mast.Release.migrate()'
      bin/mast eval 'Mast.Release.rollback(Mast.Repo, 20260101000000)'
      bin/mast eval 'Mast.Release.seed()'
  """

  @app :mast

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def migrations do
    load_app()

    for repo <- repos() do
      {repo, Ecto.Migrator.migrations(repo)}
    end
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &run_seeds_for/1)
    end
  end

  defp run_seeds_for(repo) do
    seeds = priv_path_for(repo, "seeds.exs")
    if File.exists?(seeds), do: Code.eval_file(seeds)
  end

  defp priv_path_for(repo, filename) do
    priv_dir = "#{:code.priv_dir(@app)}"
    repo_underscore = repo |> Module.split() |> List.last() |> Macro.underscore()
    Path.join([priv_dir, repo_underscore, filename])
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
