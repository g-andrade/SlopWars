using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using GLTFast;
using UnityEngine;
using UnityEngine.Networking;

public class RuntimeAssetFactory : MonoBehaviour
{
    // ---------- CORE ----------

    public async Task<GameObject> CreateObjectAsync(string objectName, Dictionary<string, string> urls)
    {
        // Download GLB
        var hasUrl = urls.TryGetValue(objectName, out var modelUrl);
        if (!hasUrl)
            Debug.LogError("no url");
        
        using var modelReq = UnityWebRequest.Get(modelUrl);
        var op = modelReq.SendWebRequest();

        while (!op.isDone)
            await Task.Yield();

        if (modelReq.result != UnityWebRequest.Result.Success)
        {
            Debug.LogError($"Model download failed: {modelReq.error}");
            return null;
        }

        byte[] glbData = modelReq.downloadHandler.data;

        // Load GLB
        GameObject modelRoot = await RuntimeModelLoader.LoadGlb(glbData, objectName);
        if (modelRoot == null)
            return null;

        return modelRoot;
    }
}

public static class RuntimeModelLoader
{
    public static async Task<GameObject> LoadGlb(byte[] glbData, string name = "GLB_Model")
    {
        var gltf = new GltfImport();

        bool success = await gltf.Load(glbData);
        if (!success)
        {
            Debug.LogError("Failed to load GLB data");
            return null;
        }

        var root = new GameObject(name);
        await gltf.InstantiateMainSceneAsync(root.transform);

        return root;
    }
}