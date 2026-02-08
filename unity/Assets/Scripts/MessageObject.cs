using System;
using System.Numerics;
using Newtonsoft.Json;

[Serializable]
public class MessageObject
{
    [JsonProperty("type")]
    public string Type { get; set; }
    
    [JsonProperty("player_number")]
    public int PlayerNumber { get; set; }
    
    [JsonProperty("room_id")]
    public string RoomId { get; set; }
    
    [JsonProperty("prompt")]
    public string Prompt { get; set; }
    
    [JsonProperty("power")]
    public float Power { get; set; }
    
    [JsonProperty("opponent_build")]
    public Build OpponentBuild { get; set; }
    
    [JsonProperty("your_build")]
    public Build PlayerBuild { get; set; }

    [JsonProperty("position")]
    public Vector3 Position { get; set; }
    
    [JsonProperty("rotation1")]
    public Quaternion Rotation1 { get; set; }
    
    [JsonProperty("rotation2")]
    public Quaternion Rotation2 { get; set; }
    
    [JsonProperty("hp")]
    public float TowerHp { get; set; }
    
    [JsonProperty("winner")]
    public int Winner { get; set; }
    
    [JsonProperty("name")]
    public string Name { get; set; }
    
    [JsonProperty("url")]
    public string Url { get; set; }
    
    [JsonProperty("overall")]
    public float Progress { get; set; }
}

[Serializable]
public class Build
{
    public int bomb_damage { get; set; }
    public string bomb_description { get; set; }
    public string bomb_model_url { get; set; }

    public string shield_description { get; set; }
    public int shield_hp { get; set; }
    public string shield_model_url { get; set; }

    public string tone { get; set; }

    public string tower_description { get; set; }
    public int tower_hp { get; set; }
    public string tower_model_url { get; set; }
}