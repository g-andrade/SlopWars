defmodule Backend.ASB do
  @moduledoc """
  AI Slop Brain — analyzes player prompts and produces game builds.

  Each build contains a tone classification, stat values for bomb/tower/shield,
  descriptive text for 3D asset generation, and model URLs.
  """

  require Logger

  @system_prompt """
  You are the AI Slop Brain for a 2-player artillery game. A player has submitted a prompt that defines their "build" — their bombs, tower, and shields.

  Analyze the prompt and return a JSON object with these exact fields:

  - "tone": one of "aggressive", "balanced", or "defensive" based on the mood/meaning of the prompt
  - "bomb_damage": integer 1-10 (higher for aggressive prompts)
  - "tower_hp": integer 100-500 (higher for defensive prompts)
  - "shield_hp": integer 1-3 (higher for defensive prompts)
  - "bomb_description": a short, vivid description of what the bomb looks like (themed to the prompt)
  - "tower_description": a short, vivid description of what the tower looks like (themed to the prompt)
  - "shield_description": a short, vivid description of what the shield looks like (themed to the prompt)

  Tune the stats based on tone:
  - Aggressive: high bomb_damage (7-10), low tower_hp (100-250), low shield_hp (1)
  - Defensive: low bomb_damage (1-4), high tower_hp (350-500), high shield_hp (2-3)
  - Balanced: medium everything (4-7 damage, 200-400 hp, 1-2 shield)

  Return ONLY the JSON object, no other text.
  """

  def analyze(prompt, base_url) do
    if dev_mode?() do
      analyze_dev(prompt, base_url)
    else
      analyze_prod(prompt, base_url)
    end
  end

  defp analyze_dev(prompt, base_url) do
    Logger.notice("[ASB] Dev mode analysis for: #{inspect(prompt)}")
    delay = 1000 + :rand.uniform(1000)
    Process.sleep(delay)

    tone = Enum.random(["aggressive", "balanced", "defensive"])

    {bomb_damage, tower_hp, shield_hp} =
      case tone do
        "aggressive" -> {Enum.random(7..10), Enum.random(100..250), 1}
        "defensive" -> {Enum.random(1..4), Enum.random(350..500), Enum.random(2..3)}
        "balanced" -> {Enum.random(4..7), Enum.random(200..400), Enum.random(1..2)}
      end

    build = %{
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

    {:ok, build}
  end

  defp analyze_prod(prompt, base_url) do
    api_key = Application.fetch_env!(:backend, :mistral_api_key)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: prompt}
    ]

    Logger.notice("[ASB] Analyzing prompt via Mistral: #{inspect(prompt)}")

    case Backend.Mistral.Client.chat(api_key, messages) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        case Jason.decode(content) do
          {:ok, parsed} ->
            build =
              parsed
              |> Map.take(["tone", "bomb_damage", "tower_hp", "shield_hp",
                           "bomb_description", "tower_description", "shield_description"])
              |> Map.merge(%{
                "bomb_model_url" => "#{base_url}/models/placeholder.glb",
                "tower_model_url" => "#{base_url}/models/placeholder.glb",
                "shield_model_url" => "#{base_url}/models/placeholder.glb"
              })

            {:ok, build}

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
