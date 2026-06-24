defmodule DotPrompt.TelemetryTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Telemetry

  @prompts_dir_1 Path.expand("test/fixtures/telemetry_test", File.cwd!())
  @prompts_dir_2 Path.expand("test/fixtures/telemetry_test2", File.cwd!())
  @prompts_dir_3 Path.expand("test/fixtures/telemetry_test3", File.cwd!())

  setup_all do
    original_dir = Application.get_env(:anantha_dot_prompt, :prompts_dir)
    # Setup first directory for compile tests
    Application.put_env(:anantha_dot_prompt, :prompts_dir, @prompts_dir_1)
    File.mkdir_p!(@prompts_dir_1)

    File.write!(Path.join(@prompts_dir_1, "demo.prompt"), """
    init do
      @version: 1
      def:
        mode: tutor
        description: A demo prompt for testing.
      params:
        @user: str = "Student"
    end init
    You are a helpful tutor teaching @user.
    """)

    # Setup second directory for compile_to_iodata tests
    File.mkdir_p!(@prompts_dir_2)

    File.write!(Path.join(@prompts_dir_2, "test.prompt"), """
    init do
      @version: 1
      def:
        mode: test
      params:
        @name: str
    end init
    Hello @name!
    """)

    # Setup third directory for render tests
    File.mkdir_p!(@prompts_dir_3)

    File.write!(Path.join(@prompts_dir_3, "render_demo.prompt"), """
    init do
      @version: 1
      def:
        mode: tutor
      params:
        @user: str = "Student"
    end init
    You are a helpful tutor teaching {{user}}.
    """)

    on_exit(fn ->
      Application.put_env(:anantha_dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir_1)
      File.rm_rf!(@prompts_dir_2)
      File.rm_rf!(@prompts_dir_3)
    end)

    :ok
  end

  describe "start_render/2" do
    test "emits [:dot_prompt, :render, :start] event with correct metadata" do
      # Setup handler to capture the event
      test_pid = self()
      handler_id = "test-start-#{:erlang.unique_integer()}"

      # Handler must accept 4 arguments for Erlang's telemetry
      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach(handler_id, [:dot_prompt, :render, :start], handler, [])

      try do
        Telemetry.start_render("test_prompt", %{user: "Alice"})

        assert_receive {:telemetry_event, [:dot_prompt, :render, :start], measurements, metadata},
                       100

        # Verify measurements contain system_time
        assert is_map(measurements)
        assert Map.has_key?(measurements, :system_time)

        # Verify metadata
        assert metadata[:prompt] == "test_prompt"
        assert metadata[:params] == %{user: "Alice"}
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "stop_render/4" do
    test "emits [:dot_prompt, :render, :stop] event with correct measurements and metadata" do
      test_pid = self()
      handler_id = "test-stop-#{:erlang.unique_integer()}"

      # Handler must accept 4 arguments for Erlang's telemetry
      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach(handler_id, [:dot_prompt, :render, :stop], handler, [])

      try do
        measurements = %{
          compiled_tokens: 150,
          vary_selections: %{"key" => "value"},
          cache_hit: false
        }

        Telemetry.stop_render(
          "test_prompt",
          %{user: "Bob"},
          42,
          measurements
        )

        assert_receive {:telemetry_event, [:dot_prompt, :render, :stop], result_measurements,
                        metadata},
                       100

        # Verify measurements contain duration and compiled_tokens
        assert result_measurements[:duration] == 42
        assert result_measurements[:compiled_tokens] == 150

        # Verify metadata
        assert metadata[:prompt] == "test_prompt"
        assert metadata[:params] == %{user: "Bob"}
        assert metadata[:vary_selections] == %{"key" => "value"}
        assert metadata[:cache_hit] == false
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits [:dot_prompt, :render, :stop] with minimal measurements (error case)" do
      test_pid = self()
      handler_id = "test-stop-minimal-#{:erlang.unique_integer()}"

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach(handler_id, [:dot_prompt, :render, :stop], handler, [])

      try do
        # Minimal measurements (like in error case)
        measurements = %{compiled_tokens: 0}

        Telemetry.stop_render(
          "error_prompt",
          %{},
          10,
          measurements
        )

        assert_receive {:telemetry_event, [:dot_prompt, :render, :stop], result_measurements,
                        metadata},
                       100

        assert result_measurements[:duration] == 10
        assert result_measurements[:compiled_tokens] == 0

        # vary_selections and cache_hit should not be in metadata when not provided
        refute Map.has_key?(metadata, :vary_selections)
        refute Map.has_key?(metadata, :cache_hit)
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits [:dot_prompt, :render, :stop] with cache_hit true" do
      test_pid = self()
      handler_id = "test-cache-hit-#{:erlang.unique_integer()}"

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach(handler_id, [:dot_prompt, :render, :stop], handler, [])

      try do
        measurements = %{
          compiled_tokens: 200,
          cache_hit: true
        }

        Telemetry.stop_render(
          "cached_prompt",
          %{name: "Test"},
          5,
          measurements
        )

        assert_receive {:telemetry_event, [:dot_prompt, :render, :stop], _result_measurements,
                        metadata},
                       100

        assert metadata[:cache_hit] == true
        refute Map.has_key?(metadata, :vary_selections)
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "compile/2 emits telemetry" do
    test "compile emits telemetry events via compile_to_iodata" do
      # Switch to the first test directory
      Application.put_env(:anantha_dot_prompt, :prompts_dir, @prompts_dir_1)

      test_pid = self()
      start_id = "compile-start-#{:erlang.unique_integer()}"
      stop_id = "compile-stop-#{:erlang.unique_integer()}"

      # Handlers must accept 4 arguments for Erlang's telemetry
      start_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:start_event, event, measurements, metadata})
      end

      stop_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:stop_event, event, measurements, metadata})
      end

      :telemetry.attach(start_id, [:dot_prompt, :render, :start], start_handler, [])
      :telemetry.attach(stop_id, [:dot_prompt, :render, :stop], stop_handler, [])

      try do
        # Call compile which internally calls compile_to_iodata which emits telemetry
        {:ok, %DotPrompt.Result{}} =
          DotPrompt.compile("demo", %{user: "Alice"})

        # Verify start event was emitted
        assert_receive {:start_event, [:dot_prompt, :render, :start], _measurements,
                        start_metadata},
                       100

        assert start_metadata[:prompt] == "demo"
        assert start_metadata[:params] == %{user: "Alice"}

        # Verify stop event was emitted
        assert_receive {:stop_event, [:dot_prompt, :render, :stop], stop_measurements,
                        stop_metadata},
                       100

        assert stop_measurements[:compiled_tokens] > 0
        assert stop_metadata[:prompt] == "demo"
        assert stop_metadata[:params] == %{user: "Alice"}
      after
        :telemetry.detach(start_id)
        :telemetry.detach(stop_id)
      end
    end
  end

  describe "compile_to_iodata/3 emits telemetry" do
    test "compile_to_iodata emits telemetry events" do
      # Switch to the second test directory
      Application.put_env(:anantha_dot_prompt, :prompts_dir, @prompts_dir_2)

      test_pid = self()
      start_id = "iodata-start-#{:erlang.unique_integer()}"
      stop_id = "iodata-stop-#{:erlang.unique_integer()}"

      start_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:start_event, event, measurements, metadata})
      end

      stop_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:stop_event, event, measurements, metadata})
      end

      :telemetry.attach(start_id, [:dot_prompt, :render, :start], start_handler, [])
      :telemetry.attach(stop_id, [:dot_prompt, :render, :stop], stop_handler, [])

      try do
        {:ok, _iodata, _selections, _vars, _cached, _hit, _warnings, _contract, _major, _version,
         _decls} =
          DotPrompt.compile_to_iodata("test", %{name: "World"}, [])

        # Verify both start and stop events were emitted
        assert_receive {:start_event, [:dot_prompt, :render, :start], _measurements,
                        start_metadata},
                       100

        assert start_metadata[:prompt] == "test"
        assert start_metadata[:params] == %{name: "World"}

        assert_receive {:stop_event, [:dot_prompt, :render, :stop], stop_measurements,
                        stop_metadata},
                       100

        assert is_integer(stop_measurements[:duration])
        assert is_integer(stop_measurements[:compiled_tokens])
        assert stop_metadata[:prompt] == "test"
      after
        :telemetry.detach(start_id)
        :telemetry.detach(stop_id)
      end
    end
  end

  describe "render/4 emits telemetry" do
    test "render emits telemetry events via internal compile call" do
      # Switch to the third test directory
      Application.put_env(:anantha_dot_prompt, :prompts_dir, @prompts_dir_3)

      test_pid = self()
      start_id = "render-start-#{:erlang.unique_integer()}"
      stop_id = "render-stop-#{:erlang.unique_integer()}"

      start_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:start_event, event, measurements, metadata})
      end

      stop_handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:stop_event, event, measurements, metadata})
      end

      :telemetry.attach(start_id, [:dot_prompt, :render, :start], start_handler, [])
      :telemetry.attach(stop_id, [:dot_prompt, :render, :stop], stop_handler, [])

      try do
        {:ok, %DotPrompt.Result{prompt: result}} =
          DotPrompt.render("render_demo", %{user: "Alice"}, %{user: "Alice"})

        assert result =~ "Alice"

        # Verify start event was emitted
        assert_receive {:start_event, [:dot_prompt, :render, :start], _measurements,
                        start_metadata},
                       100

        assert start_metadata[:prompt] == "render_demo"
        assert start_metadata[:params] == %{user: "Alice"}

        # Verify stop event was emitted
        assert_receive {:stop_event, [:dot_prompt, :render, :stop], stop_measurements,
                        stop_metadata},
                       100

        assert stop_measurements[:compiled_tokens] > 0
        assert stop_metadata[:prompt] == "render_demo"
      after
        :telemetry.detach(start_id)
        :telemetry.detach(stop_id)
      end
    end
  end
end
