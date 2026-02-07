defmodule Backend.ASB do
  @moduledoc """
  AI Slop Brain — analyzes both players' prompts together and produces balanced game builds.

  Each build contains a tone classification, stat values for bomb/tower/shield,
  descriptive text for 3D asset generation, and model URLs.
  """

  require Logger

  @system_prompt """
  You are the AI Slop Brain for a 2-player artillery game. Two players have each submitted a prompt that defines their "build" — their bombs, tower, and shields.

  Analyze BOTH prompts together and return a JSON object with "player1" and "player2" keys. Each player object must have these exact fields:

  - "tone": one of "aggressive", "balanced", or "defensive" based on the mood/meaning of that player's prompt
  - "bomb_damage": integer 1-10 (higher for aggressive prompts)
  - "tower_hp": integer 100-500 (higher for defensive prompts)
  - "shield_hp": integer 1-3 (higher for defensive prompts)
  - "bomb_description": a short, vivid description of what the bomb looks like (themed to the prompt)
  - "tower_description": a short, vivid description of what the tower looks like (themed to the prompt)
  - "shield_description": a short, vivid description of what the shield looks like (themed to the prompt)

  IMPORTANT BALANCING RULES:
  - Each build must stay thematic to its player's prompt
  - Stats should be balanced: the total power of each build should be roughly equal
  - If one player gets high bomb_damage, offset it with lower tower_hp or shield_hp
  - If one player gets high tower_hp, offset it with lower bomb_damage
  - Neither player should have a clear statistical advantage overall

  Return ONLY the JSON object, no other text. Example structure:
  {"player1": {"tone": "aggressive", "bomb_damage": 8, "tower_hp": 150, ...}, "player2": {"tone": "defensive", "bomb_damage": 3, "tower_hp": 400, ...}}
  """

  def analyze_both(prompt1, prompt2, base_url) do
    if dev_mode?() do
      analyze_both_dev(prompt1, prompt2, base_url)
    else
      analyze_both_prod(prompt1, prompt2, base_url)
    end
  end

  defp analyze_both_dev(prompt1, prompt2, base_url) do
    Logger.notice("[ASB] Dev mode analysis for: #{inspect(prompt1)} vs #{inspect(prompt2)}")
    delay = 1000 + :rand.uniform(1000)
    Process.sleep(delay)

    # Generate correlated/balanced builds: one aggressive, one defensive
    {tone1, tone2} = Enum.random([{"aggressive", "defensive"}, {"defensive", "aggressive"}, {"balanced", "balanced"}])

    build1 = dev_build(tone1, prompt1, base_url)
    build2 = dev_build(tone2, prompt2, base_url)

    {:ok, build1, build2}
  end

  defp dev_build(tone, prompt, base_url) do
    {bomb_damage, tower_hp, shield_hp} =
      case tone do
        "aggressive" -> {Enum.random(7..10), Enum.random(100..250), 1}
        "defensive" -> {Enum.random(1..4), Enum.random(350..500), Enum.random(2..3)}
        "balanced" -> {Enum.random(4..7), Enum.random(200..400), Enum.random(1..2)}
      end

    %{
      "tone" => tone,
      "bomb_damage" => bomb_damage,
      "tower_hp" => tower_hp,
      "shield_hp" => shield_hp,
      "bomb_description" => "A sloppy #{tone} projectile inspired by: #{prompt}",
      "tower_description" => "A #{tone} tower of slop themed around: #{prompt}",
      "shield_description" => "A #{tone} shield of slop based on: #{prompt}",
      "bomb_model_url" => "#{base_url}/models/placeholder.glb",
      "tower_model_url" => "#{base_url}/models/placeholder.glb",
      "shield_model_url" => "#{base_url}/models/placeholder.glb"
    }
  end

  defp analyze_both_prod(prompt1, prompt2, base_url) do
    api_key = Application.fetch_env!(:backend, :mistral_api_key)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Player 1 prompt: #{prompt1}\nPlayer 2 prompt: #{prompt2}"}
    ]

    Logger.notice("[ASB] Analyzing both prompts via Mistral: #{inspect(prompt1)} vs #{inspect(prompt2)}")

    case Backend.Mistral.Client.chat(api_key, messages) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        case Jason.decode(content) do
          {:ok, %{"player1" => p1, "player2" => p2}} ->
            build_fields = ["tone", "bomb_damage", "tower_hp", "shield_hp",
                            "bomb_description", "tower_description", "shield_description"]
            model_urls = %{
              "bomb_model_url" => "#{base_url}/models/placeholder.glb",
              "tower_model_url" => "#{base_url}/models/placeholder.glb",
              "shield_model_url" => "#{base_url}/models/placeholder.glb"
            }

            build1 = p1 |> Map.take(build_fields) |> Map.merge(model_urls)
            build2 = p2 |> Map.take(build_fields) |> Map.merge(model_urls)

            {:ok, build1, build2}

          {:ok, _unexpected} ->
            Logger.error("[ASB] Mistral JSON missing player1/player2 keys")
            {:error, "Unexpected AI response structure"}

          {:error, reason} ->
            Logger.error("[ASB] Failed to parse Mistral JSON: #{inspect(reason)}")
            {:error, "Failed to parse AI response"}
        end

      {:ok, unexpected} ->
        Logger.error("[ASB] Unexpected Mistral response: #{inspect(unexpected)}")
        {:error, "Unexpected AI response format"}

      {:error, reason} ->
        Logger.error("[ASB] Mistral API error: #{inspect(reason)}")
        {:error, "AI analysis failed: #{inspect(reason)}"}
    end
  end

  defp dev_mode? do
    Application.get_env(:backend, :dev_mode, false)
  end
end
