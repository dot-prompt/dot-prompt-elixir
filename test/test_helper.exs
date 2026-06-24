ExUnit.start()

Application.put_env(
  :anantha_dot_prompt,
  :prompts_dir,
  Path.expand("test/fixtures/prompts", File.cwd!())
)
